import Foundation
import ActivityKit

/// Puts the running trip day on the Lock Screen and keeps it current.
///
/// Local only in this phase: the app starts, updates and ends the activity
/// itself, whenever something changes what comes next — an arrival, a skip,
/// an applied option, the app coming to the front. Between those the card
/// counts down on its own (`Text(timerInterval:)`), so it needs no pushes to
/// stay right for the length of a leg.
@MainActor
final class TripLive {
    static let shared = TripLive()

    /// Up from an hour before the day's first departure.
    nonisolated static let leadMinutes = 60.0

    private init() {}

    func refresh(now: Date = Date()) {
        TripsWidgetBridge.save(now: now)
        guard !SRDemo.isOn, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let store = TripStore.shared
        guard let running = store.running(now: now),
              let day = store.day(running.bundle.trip.id, running.date),
              let clock = store.clock(running.bundle.trip.id),
              // A slot whose time has gone is not "next", ticked or not.
              let progress = store.progressToTell(running.bundle.trip.id, running.date, now: now),
              let state = Self.state(day: day, progress: progress, clock: clock),
              Self.isOn(day: day, clock: clock, now: now),
              // "Stop prompting the plan today" takes the card away too.
              !TripOffPlan.shared.isPaused(running.bundle.trip.id, running.date) else {
            Task { await self.endAll() }
            return
        }
        let trip = running.bundle.trip
        let content = ActivityContent(state: state, staleDate: state.arrive.addingTimeInterval(30 * 60))
        Task {
            // One activity: the one for this trip is updated, any other ended.
            var current: Activity<TripAttributes>?
            for activity in Activity<TripAttributes>.activities {
                if activity.attributes.tripId == trip.id, current == nil {
                    current = activity
                } else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            if let current {
                await current.update(content)
            } else {
                _ = try? Activity.request(
                    attributes: TripAttributes(tripId: trip.id, title: trip.title),
                    content: content,
                    pushType: nil
                )
            }
        }
    }

    func endAll() async {
        for activity in Activity<TripAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Whether the day is running: from the lead time before its first
    /// departure to the end of its last stop.
    nonisolated static func isOn(day: PlannedDay, clock: TripClock, now: Date) -> Bool {
        guard let first = day.stops.first, let last = day.stops.last,
              clock.localDate(now) == day.date else { return false }
        let minutes = clock.minutes(now)
        return minutes >= first.departMin - leadMinutes && minutes <= last.arriveMin + 30
    }

    /// The card's content for where the person is in the day, or nil once
    /// there is nothing next.
    nonisolated static func state(day: PlannedDay, progress: TripProgress, clock: TripClock) -> TripAttributes.ContentState? {
        guard let next = progress.next, next < day.stops.count,
              let leg = day.leg(before: next) else { return nil }
        let stop = day.stops[next]
        let leaveMin = progress.leaveMin ?? (stop.arriveMin - leg.durationSec / 60)
        guard let leave = clock.date(day.date, minutes: leaveMin),
              let arrive = clock.date(day.date, minutes: stop.arriveMin) else { return nil }
        return TripAttributes.ContentState(
            nextTitle: stop.title,
            leaveAt: leave.timeIntervalSince1970.rounded(),
            legMode: leg.mode.rawValue,
            legMinutes: max(1, Int((leg.durationSec / 60).rounded())),
            arriveAt: arrive.timeIntervalSince1970.rounded(),
            stopIndex: next,
            stopCount: day.stops.count
        )
    }
}
