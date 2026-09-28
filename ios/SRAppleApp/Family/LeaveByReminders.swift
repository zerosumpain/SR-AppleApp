import Foundation
import UserNotifications

/// Leave-by reminders, scheduled ON THIS PHONE from the forecast's Coming up
/// list: ten minutes before each leave-by time, "Leave by 15:10 for Dentist".
///
/// Local rather than pushed so the timing is the phone's own clock, not the
/// site's two-minute heartbeat plus Apple's delivery. The cost is that a
/// reminder exists only for events this phone has seen — every forecast read
/// (the Family tab, Today, a pull-to-refresh) reschedules the lot.
///
/// The owner's phone only: `upcoming` is null for anyone else. One switch,
/// Settings → Notifications → Leave-by reminders, on by default. (The site's
/// own "time to leave" push on /home/people is a second route to the same
/// nudge; leave that off if this is on.)
enum LeaveByReminders {
    static let key = "leave-by-reminders"
    static let category = "leave-by"
    static let prefix = "leave-by:"
    /// How long before the leave-by time the reminder goes off.
    static let lead: TimeInterval = 10 * 60
    private static let sentKey = "leave-by-sent"

    struct Planned: Equatable {
        let id: String
        let fireAt: Date
        let title: String
        let body: String
    }

    /// What should be pending now. PURE.
    ///
    /// A reminder whose moment has passed but whose leave-by has not (the list
    /// arrived late) fires at once — unless it already did, which `sent` says.
    static func plan(
        _ items: [FamilyForecast.UpcomingItem],
        names: [String: String],
        now: Date,
        sent: Set<String> = []
    ) -> [Planned] {
        items.compactMap { item in
            guard let leaveISO = item.leaveBy, let leave = parseTimestamp(leaveISO), leave > now else { return nil }
            let id = "\(prefix)\(item.id)|\(leaveISO)"
            var fire = leave.addingTimeInterval(-lead)
            if fire <= now {
                if sent.contains(id) { return nil }
                fire = now.addingTimeInterval(5)
            }
            let who = item.subjects.map { names[$0] ?? $0.capitalized }.joined(separator: ", ")
            let at = ForecastWords.clock(item.start) ?? ""
            var body = "\(who) · \(item.place) at \(at)"
            if let travel = item.travel {
                body += " · about \(Int(travel.median.rounded())) min\(travel.source == "routed" ? " (routed)" : "")"
            }
            if let issue = item.issue { body += ". \(issue.text)" }
            return Planned(id: id, fireAt: fire, title: "Leave by \(ForecastWords.clock(leaveISO) ?? "") for \(item.title)", body: body)
        }
    }

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    /// Bring the pending reminders in line with `upcoming`. A diary that could
    /// not be read changes NOTHING — a failed read must never cancel a
    /// reminder that was right an hour ago.
    @MainActor
    static func sync(_ upcoming: FamilyForecast.Upcoming?, names: [String: String], now: Date = Date()) async {
        let centre = UNUserNotificationCenter.current()
        let pending = await centre.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard enabled else {
            centre.removePendingNotificationRequests(withIdentifiers: pending)
            return
        }
        guard let upcoming, upcoming.available else { return }
        let settings = await centre.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        var sent = Set(UserDefaults.standard.stringArray(forKey: sentKey) ?? [])
        let planned = plan(upcoming.items, names: names, now: now, sent: sent)
        let wanted = Set(planned.map(\.id))
        centre.removePendingNotificationRequests(withIdentifiers: pending.filter { !wanted.contains($0) })
        for p in planned where !pending.contains(p.id) {
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = .default
            content.threadIdentifier = category
            content.categoryIdentifier = category
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["category": category]
            let interval = max(1, p.fireAt.timeIntervalSince(now))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            do {
                try await centre.add(UNNotificationRequest(identifier: p.id, content: content, trigger: trigger))
                sent.insert(p.id)
            } catch {
                continue
            }
        }
        // Ids carry their leave-by time, so two days of them is plenty.
        UserDefaults.standard.set(Array(sent.suffix(200)), forKey: sentKey)
    }
}
