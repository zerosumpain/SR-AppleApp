import Foundation

/// Every ten minutes of a running trip day (`TripOffPlan`): is the person
/// where the plan has them, and if not, can the plan bend so they still keep
/// to it? John, 2026-10-27: "iterate the plan so they can stick to it until
/// they're unable, then either offer alternate suggestions of things to do
/// near where they are and / offer to stop prompting the plan."
///
/// So a slip is met first by RE-TIMING the rest of the day — the same stops in
/// the same order, later — used without asking, because that is still the
/// plan. Only when re-timing alone cannot keep it (a booked slot would be
/// missed, a stop would have to go or move, the day would run past its end)
/// is the person asked, with things to do near them and the way to stop
/// being prompted for the day.
///
/// Foundation only, beside the solver port it leans on.
enum TripKeepUp {
    /// Under this many minutes adrift is keeping to the plan.
    static let slackMin = 10.0
    /// This close to a stop is being at it.
    static let atStopM = 150.0
    /// How often a running day is looked at.
    static let everySec: TimeInterval = 600

    enum Verdict: Equatable {
        case onPlan
        /// The rest of the day re-timed with nothing lost: used without asking.
        case retime(ReplanOption, slipMin: Double)
        /// Re-timing alone no longer keeps the plan.
        case cannotKeep(slipMin: Double)
    }

    /// How many minutes behind the plan the person is from where they stand:
    /// at a stop, how far past its planned leave they still are; anywhere
    /// else, when they would reach the stop they should be making for
    /// against when the plan has them there. 0 when on time or early; nil
    /// when the day says nothing (no stop ahead, no place to measure from).
    static func slip(day: PlannedDay, progress: TripProgress, position: TripLatLng, nowMin: Double) -> Double? {
        guard let current = progress.currentIndex, current < day.stops.count else { return nil }
        let here = day.stops[current]
        if let at = here.location, TripReplan.haversineM(at, position) <= atStopM {
            return max(0, nowMin - here.departMin)
        }
        // Away from the stop the day has them at: they have left it, so it
        // is the next one they are making for.
        var target = current
        if case .at = progress.phase {
            guard let next = progress.next, next < day.stops.count else { return nil }
            target = next
        }
        let stop = day.stops[target]
        guard let to = stop.location else { return nil }
        let mode = day.leg(before: target)?.mode ?? .walk
        let eta = nowMin + TripReplan.estimateLeg(position, to, mode).seconds / 60
        return max(0, eta - stop.arriveMin)
    }

    /// The re-timed day still IS the plan: nothing dropped, every stop still
    /// to come still there and in the same order, and no new warning (a
    /// missed slot, a meal with no time, a late finish all arrive as one).
    static func keepsThePlan(_ option: ReplanOption, day: PlannedDay, done: Set<String>) -> Bool {
        guard option.dropped.isEmpty else { return false }
        let ahead = day.stops.map(\.id).filter { !done.contains($0) }
        let kept = option.day.stops.map(\.id).filter { !done.contains($0) }
        guard ahead == kept else { return false }
        let known = Set(day.warnings)
        return option.day.warnings.allSatisfy { known.contains($0) }
    }

    /// What to do about a slip. `options` is the solver's (`replanDay`), asked
    /// for only when there is a slip worth it.
    static func verdict(day: PlannedDay, slip: Double?, done: Set<String>, options: () -> [ReplanOption]) -> Verdict {
        guard let slip, slip >= slackMin else { return .onPlan }
        if let shift = options().first(where: { $0.kind == .shift }), keepsThePlan(shift, day: day, done: done) {
            return .retime(shift, slipMin: slip)
        }
        return .cannotKeep(slipMin: slip)
    }

    /// "Plan moved 20 min later so you can keep to it."
    static func retimedLine(_ option: ReplanOption) -> String {
        let minutes = Int(option.endsLaterMin.rounded())
        guard minutes > 0 else { return "Plan re-timed so you can keep to it" }
        return "Plan moved \(minutes) min later so you can keep to it"
    }

    /// "Can't keep to the plan from here — about 35 min behind".
    static func cannotKeepLine(slipMin: Double) -> String {
        "Can't keep to the plan from here — about \(Int(slipMin.rounded())) min behind"
    }
}
