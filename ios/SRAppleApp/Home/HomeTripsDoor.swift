import SwiftUI

/// Trips, as a short door at the top of the hub (⊞), for everyone who has
/// trips: hiding the Trips tile from Home must never hide Trips (plan §5.5).
/// One unit tall and the hub's full width, like the hub's other doors; the
/// count on its glyph is the next trip's open questions.
///
/// Its own file, and one line in `MoreScreen`, so the hub needs no new case.
struct HomeTripsDoor: View {
    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var access = AccessStore.shared
    @EnvironmentObject private var router: Router
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Today's tile height, as the hub's other short doors.
    @ScaledMetric(relativeTo: .body) private var short: CGFloat = 82

    /// The same rule as the Home tile (`HomeTileKind.trips`): the family,
    /// over the site.
    private var allowed: Bool {
        (access.current.owner || access.current.family) && (SiteClient.shared.isPaired || SRDemo.isOn)
    }

    var body: some View {
        if allowed {
            let next = store.upcoming()
            let questions = HomeTripWords.openQuestions(next.flatMap { store.bundles[$0.id] })
            Button {
                SRHaptic.tap()
                open(next: next, questions: questions)
            } label: {
                TodayTileCard(title: "Trips") {
                    TodayTileGlyph(symbol: HomeTileKind.trips.symbol, tone: HomeTileKind.trips.hue.base, count: questions.count)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .frame(height: typeSize.isAccessibilitySize ? nil : short)
            .accessibilityLabel("Trips")
            .accessibilityValue(line(next: next, questions: questions.count))
            .accessibilityIdentifier("more-trips")
        }
    }

    /// The trip running now, the next one, or nothing yet.
    private func line(next: TripSummary?, questions: Int) -> String {
        if let running = store.running() { return HomeTripWords.place(running.bundle.trip.destination) + " · on now" }
        if let next {
            let clock = TripClock(next.timeZone)
            return HomeTripWords.spoken(destination: next.destination, days: clock.days(from: clock.localDate(Date()), to: next.startDate), questions: questions)
        }
        return store.summaries.isEmpty ? "Plan a trip" : "\(store.summaries.count) on this phone"
    }

    /// Questions waiting: the trip, at the first. No trips at all: straight
    /// into a new one. Otherwise the list.
    private func open(next: TripSummary?, questions: [TripQuestion]) {
        if let next, let first = questions.first, store.running() == nil {
            router.openTrip(TripLink(tripId: next.id, date: nil, questionId: first.id))
        } else if store.summaries.isEmpty {
            router.openTrips(start: true)
        } else {
            router.openTrips()
        }
    }
}
