import Foundation
import UserNotifications

// MARK: - This person's own health link
//
// The site's connections (Gmail, calendars, Whoop…) are the OWNER's: accounts
// the website signs in to on his behalf, which nobody else on the app can fix
// and nobody else should be told about. `/api/native/connections` is
// owner-only on the server and `ConnectionsStore` only asks from the owner's
// phone.
//
// What every person CAN act on is their own phone's link to the site — the
// Apple Health permission and the uploads it feeds. Those are checked here, on
// the phone, from state the phone already holds: no request, nothing about
// anybody else, and the same banner the owner's site connections use.

/// What the banner's button does for a problem this phone can fix itself.
enum PersonalFix: String, Hashable {
    /// Push what is queued now.
    case syncNow
    /// Settings → Apple Health, where the permission sheet is asked again.
    case healthPermissions

    var buttonTitle: String {
        switch self {
        case .syncNow: return "Sync"
        case .healthPermissions: return "Allow"
        }
    }
}

enum PersonalHealthCheck {
    /// Ids start with this, so the dismissals of these and of the site's
    /// connections can be pruned separately.
    static let prefix = "personal:"
    /// Nothing uploaded for this long, with Apple Health switched on, is a
    /// broken link rather than a quiet day: steps alone change every hour.
    static let staleAfter: TimeInterval = 24 * 60 * 60

    /// The problems with this phone's own health link, right now. PURE.
    static func items(
        paired: Bool,
        healthEnabled: Bool,
        reviewNeeded: Bool,
        lastUpload: Date?,
        now: Date = Date()
    ) -> [ConnectionItem] {
        guard paired, healthEnabled else { return [] }
        var out: [ConnectionItem] = []
        if reviewNeeded {
            var item = ConnectionItem(
                id: "\(prefix)health-permission",
                label: "Apple Health",
                group: "personal",
                status: "needs_permission",
                detail: "Some categories you switched on have not been allowed yet.",
                fixHint: "Allow them in Settings → Apple Health."
            )
            item.localFix = .healthPermissions
            item.headlineOverride = "Apple Health needs your permission"
            out.append(item)
        }
        if let lastUpload, now.timeIntervalSince(lastUpload) > staleAfter {
            var item = ConnectionItem(
                id: "\(prefix)health-stale",
                label: "Your health uploads",
                group: "personal",
                status: "failing",
                detail: "Nothing has reached the site since \(lastUpload.formatted(.dateTime.weekday(.abbreviated).hour().minute())).",
                fixHint: "Open the app on Wi-Fi, or tap Sync."
            )
            item.localFix = .syncNow
            item.headlineOverride = "Your health has stopped uploading"
            out.append(item)
        }
        return out
    }

    // MARK: - Telling the person when the app is closed

    private static let notifiedKey = "personal-health-notified"

    /// One background pass: if this phone's uploads have stalled, say so ONCE
    /// per problem. Only the stale check runs here — the permission check
    /// needs HealthKit's async answer, and the banner covers it on the next
    /// open. Everyone gets this, owner or not: it is about their own phone.
    @MainActor
    static func backgroundPass(outbox: Outbox, paired: Bool, defaults: UserDefaults = .standard) async {
        let state = outbox.state
        let found = items(paired: paired, healthEnabled: !state.healthEnabled.isEmpty, reviewNeeded: false, lastUpload: state.lastUpload)
        await notifyOnce(found, defaults: defaults) { request in
            try await UNUserNotificationCenter.current().add(request)
        }
    }

    /// Post each problem not already posted, and forget the ones that cleared
    /// so a relapse is told again. Returns the ids posted.
    @MainActor
    @discardableResult
    static func notifyOnce(
        _ found: [ConnectionItem],
        defaults: UserDefaults,
        add: (UNNotificationRequest) async throws -> Void
    ) async -> [String] {
        let told = Set(defaults.stringArray(forKey: notifiedKey) ?? [])
        let current = Set(found.map(\.dismissKey))
        var posted: [String] = []
        for item in found where !told.contains(item.dismissKey) {
            let content = UNMutableNotificationContent()
            content.title = item.headline
            content.body = item.subline
            content.sound = .default
            content.threadIdentifier = "connections"
            content.userInfo = ["category": "connections", "id": item.id]
            let request = UNNotificationRequest(identifier: item.dismissKey, content: content, trigger: nil)
            do {
                try await add(request)
                posted.append(item.dismissKey)
            } catch {
                continue
            }
        }
        defaults.set(Array(told.intersection(current).union(posted)), forKey: notifiedKey)
        return posted
    }
}
