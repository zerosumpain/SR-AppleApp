import Foundation
import UserNotifications

/// The trip reminders, scheduled ON THIS PHONE (as `LeaveByReminders` are):
/// the evening-before briefing for each day to come, and a nudge two days
/// before each booking deadline. Every trip refresh brings the pending ones
/// in line with the plan (`TripReminderPlan`); a tap opens that day.
enum TripReminders {
    static let key = "trip-reminders"

    static var enabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    /// Late booking nudges already scheduled once (`TripReminderPlan` skips them after).
    private static let nudgedKey = "trip-reminders-late-nudged"
    /// iOS keeps 64 pending notifications for the app, shared with leave-by
    /// reminders: the soonest of these, no more.
    static let cap = 40

    @MainActor
    static func sync(_ bundles: [TripBundle], now: Date = Date()) async {
        guard !SRDemo.isOn else { return }
        let centre = UNUserNotificationCenter.current()
        let pending = await centre.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(TripReminderPlan.prefix) }
        guard enabled else {
            centre.removePendingNotificationRequests(withIdentifiers: pending)
            return
        }
        let settings = await centre.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        var nudged = Set(UserDefaults.standard.stringArray(forKey: nudgedKey) ?? [])
        var planned: [(TripReminderPlan.Planned, TimeZone)] = []
        for bundle in bundles {
            let clock = TripClock(bundle.trip.timeZone)
            let place = TripWeatherStore.place(bundle)
            let plan = TripReminderPlan.plan(
                bundle, today: clock.localDate(now), nowMin: clock.minutes(now), clock: clock,
                weather: TripWeatherStore.shared.forecast(bundle.trip.id),
                sun: { date in place.flatMap { TripSun.day(date, at: $0, zone: clock.zone) } },
                words: { TripFormat.day($0, zone: clock.zone) },
                nudged: nudged
            )
            planned += plan.map { ($0, clock.zone) }
            // A booking nudge due by tomorrow will have gone off: once is enough.
            if let tomorrow = clock.adding(days: 1, to: clock.localDate(now)) {
                for p in plan where p.id.contains(":book|") && p.date <= tomorrow { nudged.insert(p.id) }
            }
        }
        UserDefaults.standard.set(Array(nudged), forKey: nudgedKey)
        // The soonest first, within what iOS will keep.
        planned.sort { ($0.0.date, $0.0.minute) < ($1.0.date, $1.0.minute) }
        planned = Array(planned.prefix(cap))
        let wanted = Set(planned.map(\.0.id))
        centre.removePendingNotificationRequests(withIdentifiers: pending.filter { !wanted.contains($0) })
        for (p, zone) in planned {
            let parts = p.date.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { continue }
            var when = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: Int(p.minute) / 60, minute: Int(p.minute) % 60)
            when.timeZone = zone
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.threadIdentifier = "trip"
            // Category "trip" opens the day (`TripLink`).
            content.userInfo = ["category": TripLink.category, "tripId": p.tripId, "date": p.opens ?? ""]
            let request = UNNotificationRequest(identifier: p.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            // Same id: replaced, so a changed briefing is the new one.
            try? await centre.add(request)
        }
    }
}
