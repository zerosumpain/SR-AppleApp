import Foundation

/// The offline half of "re-plan the rest of the trip": bring a sight from a
/// LATER day that is close to where the person is now into today.
///
/// Today comes from the solver port's `pullForwardCandidates` and
/// `pullForwardDay` (SR-Main trip.ts, d7313eb3) — the same day the server's
/// `replanTrip` would offer. The day the sight leaves is re-FITTED by the
/// server (that needs `solveTrip`, which stays server-side); offline the
/// phone removes the sight and re-times that day from its own start, which
/// keeps every other stop and only closes the gap.
///
/// Foundation only: the Linux harness compiles it.
enum TripPullForward {
    struct Input {
        var bundle: TripBundle
        /// The day as shown (the phone's version if it has one), by date.
        var dayFor: (String) -> PlannedDay?
        var today: String
        var progress: TripProgress
        var position: TripLatLng
        var nowMin: Double
    }

    static func option(_ input: Input) -> TripReplanOption? {
        let b = input.bundle
        guard let today = input.dayFor(input.today) else { return nil }
        let laterDays = (b.plan?.plan.days ?? []).map(\.date).filter { $0 > input.today }.sorted().compactMap(input.dayFor)
        guard let candidate = TripReplan.pullForwardCandidates(
            b.wishes, b.bookings, today: input.today, laterDays: laterDays, position: input.position
        ).first, let wish = b.wish(candidate.wishId) else { return nil }

        let context = TripReplan.Context(
            trip: b.trip, stays: b.stays, wishes: b.wishes, bookings: b.bookings,
            matrix: b.tripMatrix ?? b.matrices[input.today] ?? TravelMatrix(points: [], seconds: [:], metres: [:], estimated: [:])
        )
        let replan = TripReplan.Input(
            context: context, day: today, nowMin: input.nowMin, position: input.position,
            atStopId: input.progress.atStopId, doneStopIds: input.progress.doneStopIds
        )
        let pulled = TripReplan.pullForwardDay(replan, wishIds: [wish.id])
        // Squeezed straight back out of today: not worth offering.
        guard !pulled.gone.contains(where: { $0.wishId == wish.id }) else { return nil }

        guard var from = input.dayFor(candidate.from) else { return nil }
        let start = from.stops.first?.departMin ?? 0
        from.stops.removeAll { $0.wishId == wish.id }
        let newFrom = TripReplan.retimeDay(from, fromIndex: 0, startMin: start, context: context)

        let walk = max(1, Int(js.round(candidate.walkSec / 60)))
        let dayName = TripReplan.dayLabel(candidate.from)
        let names = pulled.dropped.compactMap { b.wish($0)?.title }
        return TripReplanOption(
            id: "pull-forward:\(wish.id)",
            label: "Fit in \(wish.title) now — \(walk) min away",
            kind: "pull-forward",
            days: [pulled.day, newFrom],
            dropped: pulled.dropped,
            moved: [TripReplanOption.Moved(wishId: wish.id, from: candidate.from, to: input.today)],
            explanation: "It is on \(dayName)'s plan and only \(walk) min on foot from here, so doing it now frees up \(dayName)."
                + (names.isEmpty ? "" : " Today then leaves out \(TripReplan.joinNames(names)).")
        )
    }
}
