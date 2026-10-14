import Foundation

/// What the phone knows happened at one stop: arrived, left, skipped.
/// Recorded by arrival detection or by the person, and correctable.
struct TripStopMark: Codable, Hashable {
    var arrivedAt: Date?
    var leftAt: Date?
    var skipped = false
    /// Set or changed by hand rather than detected.
    var corrected = false

    var done: Bool { leftAt != nil || skipped }
}

/// Where the person is in a running day, worked out from the plan, the
/// marks and the clock. Pure: the Day screen, the Today card, the banner and
/// the Live Activity all read the same answer.
///
/// Foundation only: the Linux harness compiles it with the solver port.
struct TripProgress: Equatable {
    enum Phase: Equatable {
        /// At a stop (arrived and not left, or the morning's stay).
        case at(Int)
        /// Between stops, heading for this one.
        case heading(Int)
        /// Every stop is done.
        case finished
    }

    let phase: Phase
    /// The stop after the one you are at, or the one you are heading for.
    let next: Int?
    /// When the plan says to leave for `next` (local minutes).
    let leaveMin: Double?
    /// Behind the plan, minutes — only when arrival detection (or a hand
    /// mark) gives evidence; 0 otherwise. Never guessed from silence: a day
    /// with no marks is not a day running six hours late.
    let behindMin: Double
    /// Stop ids visited or skipped, for `replanDay`'s `doneStopIds`.
    let doneStopIds: [String]
    /// The stop you are at, for `replanDay`'s `atStopId`.
    var atStopId: String?

    /// The banner's threshold: under ten minutes is noise, not news.
    static let behindThresholdMin = 10.0

    static func of(day: PlannedDay, marks: [String: TripStopMark], nowMin: Double, clock: TripClock) -> TripProgress {
        let stops = day.stops
        func mark(_ i: Int) -> TripStopMark? { marks[stops[i].id] }
        func minutes(_ d: Date?) -> Double? {
            guard let d else { return nil }
            // A mark from another local day (a correction days later) is not
            // a time on this day's clock.
            return clock.localDate(d) == day.date ? clock.minutes(d) : nil
        }

        let done = stops.indices.filter { mark($0)?.done == true }.map { stops[$0].id }
        // The first stop not yet left or skipped.
        guard let pointer = stops.indices.first(where: { mark($0)?.done != true }) else {
            return TripProgress(phase: .finished, next: nil, leaveMin: nil, behindMin: 0, doneStopIds: done, atStopId: nil)
        }
        func following(_ i: Int) -> Int? {
            stops.indices.first { $0 > i && mark($0)?.skipped != true }
        }

        let anyMark = stops.indices.contains { mark($0) != nil }
        let arrivedHere = mark(pointer)?.arrivedAt != nil
        // The morning starts at the stay: with nothing marked yet you are
        // there, whatever the clock says.
        let atStart = pointer == 0 && stops[0].kind == .stay && !anyMark

        if arrivedHere || atStart {
            let stop = stops[pointer]
            var behind = 0.0
            if arrivedHere, let arrived = minutes(mark(pointer)?.arrivedAt) {
                // Arrived late and staying the planned time leaves late; still
                // here after the planned leave is late by the overrun.
                behind = max(arrived - stop.arriveMin, nowMin - stop.departMin, 0)
            }
            return TripProgress(
                phase: .at(pointer), next: following(pointer), leaveMin: stop.departMin,
                behindMin: behind, doneStopIds: done, atStopId: stop.id
            )
        }

        // Heading for `pointer`, from the last stop left.
        let previous = stops.indices.last { $0 < pointer && mark($0)?.leftAt != nil }
        var behind = 0.0
        if let previous, let left = minutes(mark(previous)?.leftAt) {
            let stop = stops[pointer]
            behind = max(left - stops[previous].departMin, nowMin - stop.arriveMin, 0)
        }
        let leave = pointer > 0 ? stops[pointer - 1].departMin : nil
        return TripProgress(
            phase: .heading(pointer), next: pointer, leaveMin: leave,
            behindMin: behind, doneStopIds: done, atStopId: nil
        )
    }

    var showsBehind: Bool { behindMin >= Self.behindThresholdMin }

    /// The stop the Now card is about: where you are, or where you are going.
    var currentIndex: Int? {
        switch phase {
        case .at(let i), .heading(let i): return i
        case .finished: return nil
        }
    }

    /// The index `retimeDay` restarts from: the next stop to arrive at.
    var retimeFrom: Int? {
        switch phase {
        case .at: return next
        case .heading(let i): return i
        case .finished: return nil
        }
    }
}
