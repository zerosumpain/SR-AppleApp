import Foundation

/// When is someone off the plan? The thresholds from the trips spec (v2,
/// "Off the plan"), as one pure function over the plan, the marks, the
/// clock and a few recent positions. `TripOffPlan` feeds it from cheap
/// location wake-ups and raises at most one prompt per condition.
///
/// Foundation only: the Linux harness compiles it.
enum TripOffPlanRules {
    /// `behind`: past a stop's planned depart by more than this.
    static let behindMin = 10.0
    /// `idle`: still at a stop this long past its planned depart.
    static let idleMin = 20.0
    /// `off-route`: getting further from the next stop for this long…
    static let offRouteMin = 5.0
    /// …and this far from the leg's line.
    static let offRouteM = 300.0
    /// `unplanned-stop`: still for this long…
    static let unplannedStopMin = 12.0
    /// …this far from every planned stop.
    static let unplannedStopM = 150.0

    /// A position at a local minute of the day.
    struct Fix: Equatable {
        var at: TripLatLng
        var minute: Double
    }

    /// Somewhere the phone has been still since a local minute (a visit).
    struct Dwell: Equatable {
        var at: TripLatLng
        var sinceMin: Double
    }

    struct Finding: Equatable {
        var observation: Observation
        /// A booked or locked slot later today would be missed or late.
        var slotAtRisk: Bool
        /// The stop the finding is about, for "one prompt per condition".
        var key: String
    }

    /// Every condition that holds now, most pressing first.
    static func detect(
        day: PlannedDay, marks: [String: TripStopMark], progress: TripProgress, nowMin: Double,
        fixes: [Fix], dwell: Dwell?, clock: TripClock
    ) -> [Finding] {
        var out: [Finding] = []
        let stops = day.stops
        let motion = Self.motion(fixes, dwell: dwell, nowMin: nowMin)
        let here = fixes.last.map { Observation.Place(name: nil, location: $0.at) }

        // out-of-order: arrived at a later stop while an earlier visit is undone.
        for (j, stop) in stops.enumerated() where stop.kind == .wish {
            guard let arrived = marks[stop.id]?.arrivedAt, marks[stop.id]?.leftAt == nil,
                  clock.localDate(arrived) == day.date else { continue }
            let skippedOver = stops[..<j].contains { s in
                s.kind == .wish && marks[s.id]?.done != true && marks[s.id]?.arrivedAt == nil
            }
            if skippedOver {
                out.append(Finding(
                    observation: Observation(kind: .outOfOrder, place: here, sinceMin: clock.minutes(arrived), motion: motion, stopId: stop.id),
                    slotAtRisk: lockedAhead(day, from: j + 1), key: "out-of-order:\(stop.id)"
                ))
            }
        }

        switch progress.phase {
        case .at(let i):
            let stop = stops[i]
            // Evidence, not silence: an arrival recorded here, or — for the
            // morning's stay, which nothing records arriving at — a recent
            // fix that is still at it.
            let stillAtStay = stop.kind == .stay && fixes.last.map { fix in
                nowMin - fix.minute <= 15 && (stop.location.map { TripReplan.haversineM($0, fix.at) <= unplannedStopM } ?? false)
            } == true
            let evidence = marks[stop.id]?.arrivedAt != nil || stillAtStay
            if evidence && nowMin > stop.departMin + idleMin && stop.kind != .stay {
                out.append(Finding(
                    observation: Observation(kind: .idle, place: here, sinceMin: stop.departMin, motion: motion, stopId: stop.id),
                    slotAtRisk: lockedAhead(day, from: i + 1), key: "idle:\(stop.id)"
                ))
            }
            if evidence && nowMin > stop.departMin + behindMin {
                out.append(Finding(
                    observation: Observation(kind: .behind, place: here, sinceMin: stop.departMin, motion: motion, stopId: stop.id),
                    slotAtRisk: slotAtRisk(day, from: i + 1, lateBy: nowMin - stop.departMin), key: "behind:\(stop.id)"
                ))
            }
        case .heading(let i):
            let stop = stops[i]
            // ETA from where the phone is, else the leg's own time from now.
            var eta: Double?
            if let fix = fixes.last, let to = stop.location {
                eta = nowMin + TripReplan.estimateLeg(fix.at, to, .walk).seconds / 60
            } else if let previous = stops[..<i].lastIndex(where: { marks[$0.id]?.leftAt != nil }),
                      let leg = day.leg(before: i), previous == i - 1 {
                eta = nowMin + leg.durationSec / 60
            }
            if let eta, eta > stop.arriveMin + behindMin || slotAtRisk(day, from: i, lateBy: eta - stop.arriveMin) {
                out.append(Finding(
                    observation: Observation(kind: .behind, place: here, sinceMin: stop.arriveMin, motion: motion, stopId: stop.id),
                    slotAtRisk: slotAtRisk(day, from: i, lateBy: eta - stop.arriveMin), key: "behind:\(stop.id)"
                ))
            }
            if let off = offRoute(day: day, to: i, fixes: fixes, nowMin: nowMin) {
                out.append(Finding(
                    observation: Observation(kind: .offRoute, place: here, sinceMin: off, motion: motion, stopId: stop.id),
                    slotAtRisk: lockedAhead(day, from: i), key: "off-route:\(stop.id)"
                ))
            }
        case .finished:
            break
        }

        // unplanned-stop: still somewhere that is none of today's stops.
        if let dwell, nowMin - dwell.sinceMin >= unplannedStopMin {
            let near = stops.contains { s in
                s.location.map { TripReplan.haversineM($0, dwell.at) <= unplannedStopM } ?? false
            }
            if !near {
                let cell = "\(Int((dwell.at.lat * 500).rounded())):\(Int((dwell.at.lng * 500).rounded()))"
                out.append(Finding(
                    observation: Observation(kind: .unplannedStop, place: Observation.Place(name: nil, location: dwell.at),
                                             sinceMin: dwell.sinceMin, motion: "stationary", stopId: nil),
                    slotAtRisk: lockedAhead(day, from: progress.retimeFrom ?? stops.count),
                    key: "unplanned-stop:\(cell)"
                ))
            }
        }

        let rank: [OffPlanKind: Int] = [.behind: 0, .outOfOrder: 1, .unplannedStop: 2, .offRoute: 3, .idle: 4]
        return out.enumerated().sorted { a, b in
            let ra = (a.element.slotAtRisk ? 0 : 10) + (rank[a.element.observation.kind] ?? 9)
            let rb = (b.element.slotAtRisk ? 0 : 10) + (rank[b.element.observation.kind] ?? 9)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// A locked stop from `from` on that running `lateBy` minutes late would
    /// reach after its start.
    static func slotAtRisk(_ day: PlannedDay, from: Int, lateBy: Double) -> Bool {
        guard lateBy > 0 else { return false }
        for stop in day.stops.dropFirst(max(0, from)) where stop.locked && stop.kind != .stay {
            let start = stop.arriveMin + stop.waitSec / 60
            // The slack before a slot (its wait) absorbs lateness first.
            return stop.arriveMin + lateBy > start
        }
        return false
    }

    static func lockedAhead(_ day: PlannedDay, from: Int) -> Bool {
        day.stops.dropFirst(max(0, from)).contains { $0.locked && $0.kind != .stay }
    }

    /// The minute the person started heading away, when they have been
    /// getting further from stop `to` for `offRouteMin`, have moved, and are
    /// more than `offRouteM` from the leg's line; nil otherwise.
    static func offRoute(day: PlannedDay, to i: Int, fixes: [Fix], nowMin: Double) -> Double? {
        guard let target = day.stops[i].location, let last = fixes.last,
              let first = fixes.last(where: { last.minute - $0.minute >= offRouteMin }) else { return nil }
        let window = fixes.filter { $0.minute >= first.minute }
        let distances = window.map { TripReplan.haversineM($0.at, target) }
        // Further away overall, and never coming back by more than GPS noise.
        guard distances.last! > distances.first! + 50,
              zip(distances, distances.dropFirst()).allSatisfy({ $1 >= $0 - 40 }),
              TripReplan.haversineM(first.at, last.at) > 100 else { return nil }
        var line = day.leg(before: i)?.line ?? []
        if line.count < 2, i > 0, let from = day.stops[i - 1].location { line = [from, target] }
        guard line.count >= 2, distanceToLine(last.at, line) > offRouteM else { return nil }
        return first.minute
    }

    /// Metres from a point to a polyline, on a local flat projection.
    static func distanceToLine(_ p: TripLatLng, _ line: [TripLatLng]) -> Double {
        let k = cos(p.lat * .pi / 180) * 111_320
        func xy(_ q: TripLatLng) -> (Double, Double) { ((q.lng - p.lng) * k, (q.lat - p.lat) * 111_320) }
        var best = Double.infinity
        for (a, b) in zip(line, line.dropFirst()) {
            let (ax, ay) = xy(a), (bx, by) = xy(b)
            let dx = bx - ax, dy = by - ay
            let len = dx * dx + dy * dy
            let t = len == 0 ? 0 : max(0, min(1, -(ax * dx + ay * dy) / len))
            let cx = ax + t * dx, cy = ay + t * dy
            best = min(best, (cx * cx + cy * cy).squareRoot())
        }
        return best
    }

    /// "walking", "cycling", "automotive", "stationary" or "unknown", from
    /// the last few minutes' speed.
    static func motion(_ fixes: [Fix], dwell: Dwell?, nowMin: Double) -> String {
        if dwell != nil { return "stationary" }
        guard let last = fixes.last, let first = fixes.last(where: { last.minute - $0.minute >= 2 }) else { return "unknown" }
        let speed = TripReplan.haversineM(first.at, last.at) / ((last.minute - first.minute) * 60)
        switch speed {
        case ..<0.3: return "stationary"
        case ..<2.5: return "walking"
        case ..<7: return "cycling"
        default: return "automotive"
        }
    }

    /// What the card and a notification say: "You've stopped at Caffè X",
    /// "Running 18 min behind", …
    static func headline(_ o: Observation, day: PlannedDay, nowMin: Double) -> String {
        let stop = o.stopId.flatMap { id in day.stops.first { $0.id == id } }
        let minutes = Int(max(0, nowMin - o.sinceMin).rounded())
        switch o.kind {
        case .behind where minutes < 1:
            return "Running late for \(stop?.title ?? "the next stop")"
        case .behind: return "Running about \(minutes) min behind" + (stop.map { " — \($0.title) was due \(TripFormat.time($0.departMin))" } ?? "")
        case .idle: return "Still at \(stop?.title ?? "this stop") \(minutes) min past leaving time"
        case .offRoute: return "Heading away from \(stop?.title ?? "the next stop")"
        case .unplannedStop: return "Stopped at \(o.place?.name ?? "somewhere not on the plan") for \(minutes) min"
        case .outOfOrder: return "Reached \(stop?.title ?? "a later stop") early — earlier stops are still to do"
        }
    }
}
