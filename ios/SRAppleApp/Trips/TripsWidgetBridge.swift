import Foundation
import WidgetKit

/// The app's half of the Trips widget: on a trip day, the next stop, when to
/// leave for it and the rest of the day's plan behind it; otherwise the next
/// trip. Left on the shared Keychain shelf (`FamilyShelf`, account `.trips`)
/// from the trips this phone already holds — no request of its own — each
/// time `TripStore` refreshes and each time `TripLive` refreshes the Lock
/// Screen card (an arrival, a skip, an applied option, the app coming to the
/// front). One line in each.
///
/// "Next" is `TripStore.progressToTell`, the card's own answer: a slot whose
/// time has gone is not next, ticked or not. The stops after it carry their
/// planned times, so the widget moves on as they pass without the app.
///
/// Never in demo mode, never while viewing the app as somebody, and only
/// while this person may see the family's trips.
@MainActor
enum TripsWidgetBridge {
    private static var active: Bool {
        if SRDemo.isOn { return false }
        let access = AccessStore.shared
        return access.viewingAs == nil && access.familyBoards
    }

    static func save(now: Date = Date()) {
        guard active else { return }
        let current = FamilyShelf.load(TripsWidgetSnapshot.self, .trips)
        guard let made = snapshot(TripStore.shared, now: now) else {
            // No trip running and none to come.
            if current != nil, FamilyShelf.write(nil, .trips) {
                WidgetCenter.shared.reloadTimelines(ofKind: FamilyWidgetKind.trips)
            }
            return
        }
        guard !made.sameContent(as: current) else { return }
        if FamilyShelf.save(made, .trips) {
            WidgetCenter.shared.reloadTimelines(ofKind: FamilyWidgetKind.trips)
        }
    }

    /// The running day, else the next trip, else nil.
    static func snapshot(_ store: TripStore, now: Date = Date()) -> TripsWidgetSnapshot? {
        if let running = store.running(now: now) {
            let trip = running.bundle.trip
            var stops: [TripsWidgetStop] = []
            var count = 0
            var end: Date?
            if let day = store.day(trip.id, running.date), let clock = store.clock(trip.id) {
                count = day.stops.count
                end = day.stops.last.flatMap { clock.date(day.date, minutes: $0.arriveMin + 30) }
                // "Stop prompting the plan today" takes the next stop away
                // too, as it does the Lock Screen card.
                let paused = TripOffPlan.shared.isPaused(trip.id, running.date)
                if !paused, let progress = store.progressToTell(trip.id, running.date, now: now),
                   let next = progress.next, next < day.stops.count {
                    let marks = store.marks(trip.id)
                    for index in next..<day.stops.count where stops.count < TripsWidget.keep {
                        let stop = day.stops[index]
                        if index > next, marks[stop.id]?.skipped == true { continue }
                        guard let arrive = clock.date(day.date, minutes: stop.arriveMin) else { continue }
                        let leg = day.leg(before: index)
                        // The next stop's leave is the progress's own (it
                        // knows where you are); the ones after it, the plan's.
                        let leaveMin: Double? = index == next
                            ? (progress.leaveMin ?? leg.map { stop.arriveMin - $0.durationSec / 60 })
                            : day.stops[index - 1].departMin
                        stops.append(TripsWidgetStop(
                            title: stop.title,
                            leaveAt: leaveMin.flatMap { clock.date(day.date, minutes: $0) },
                            arriveAt: arrive,
                            legMode: leg?.mode.rawValue,
                            legMinutes: leg.map { max(1, Int(($0.durationSec / 60).rounded())) },
                            number: index + 1
                        ))
                    }
                }
            }
            return TripsWidgetSnapshot(
                kind: .running, tripId: trip.id, title: trip.title, destination: trip.destination,
                timeZone: trip.timeZone, startDate: trip.startDate, endDate: trip.endDate, date: running.date,
                stops: stops, stopCount: count, dayEndsAt: end, savedAt: now
            )
        }
        if let next = store.upcoming(now: now) {
            return TripsWidgetSnapshot(
                kind: .upcoming, tripId: next.id, title: next.title, destination: next.destination,
                timeZone: next.timeZone, startDate: next.startDate, endDate: next.endDate, date: nil,
                stops: [], stopCount: 0, dayEndsAt: nil, savedAt: now
            )
        }
        return nil
    }
}
