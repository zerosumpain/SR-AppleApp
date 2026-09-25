import Foundation
import Combine
import UserNotifications
import UIKit

/// The notification inbox, and the thing that actually raises them.
///
/// ## Why these are local notifications and not push
///
/// A push notification needs an `aps-environment` entitlement, which needs a
/// provisioning profile that carries it, which needs a key generated in Apple's
/// developer portal. This repository's TestFlight lane holds a distribution
/// certificate and ONE profile, minted without push; adding the entitlement
/// without re-minting the profile fails the archive at the signing step. So
/// there is no APNs certificate, and nothing on the server can wake this phone.
///
/// What there is: a background refresh task the app already registers, and
/// `UNUserNotificationCenter`, which will post a notification from a running
/// app whether or not it is in the foreground. So the phone PULLS. iOS decides
/// when a refresh runs — a few times a day for an app opened occasionally, more
/// for one opened often — and each run drains the server's queue and posts what
/// it finds.
///
/// **That is a real limitation and it is stated rather than hidden**: an alert
/// can be minutes or hours late, and the settings screen says so. It is why the
/// three-hour health floor costs nothing, and it is why anything genuinely
/// urgent should stay routed to WhatsApp, which has a push certificate of its
/// own.
///
/// The queue is drained by ACKNOWLEDGEMENT, not by reading. A refresh iOS kills
/// mid-flight — which is ordinary; the budget is seconds — must not consume
/// what it never raised.
@MainActor
final class AlertStore: ObservableObject {
    @Published private(set) var recent: [SiteAlert] = []
    @Published private(set) var unread = 0
    @Published private(set) var routes: [AlertRoute] = []
    @Published private(set) var loading = false
    @Published private(set) var permission: UNAuthorizationStatus = .notDetermined
    @Published var message: String?
    /// Alerts swept off the Today card, by id.
    ///
    /// Kept on the phone, not the site: the site's inbox is a ledger — it can
    /// mark things read, and there is nothing to delete — and the Alerts screen
    /// stays the whole record. What this remembers is only that the owner has
    /// seen these and does not want them on the first screen any more. A new
    /// alert has a new id, so it arrives on Today whatever was cleared before.
    @Published private(set) var clearedFromToday: Set<String>

    private let client = SiteClient.shared
    private let defaults: UserDefaults

    static let clearedKey = "today-cleared-alerts"
    /// Enough to outlast the inbox the phone asks for (60), with room over; the
    /// oldest ids fall off first, and by then their alerts have too.
    static let clearedCap = 200

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        clearedFromToday = Set(defaults.stringArray(forKey: Self.clearedKey) ?? [])
    }

    // MARK: - Reading

    func refresh() async {
        guard client.isPaired, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let feed: AlertFeed = try await client.send("api/native/notifications?limit=25&inbox=60")
            recent = feed.recent
            unread = feed.unread
            await raise(feed.pending)
            message = nil
        } catch SiteError.unpaired {
            // Not an error worth a banner: the reader has not connected yet and
            // every screen already says so.
            recent = []
            unread = 0
        } catch {
            message = error.localizedDescription
        }
        await refreshBadge()
    }

    func loadRoutes() async {
        guard client.isPaired else { return }
        do {
            let payload: AlertRoutes = try await client.send("api/native/notifications/routes")
            routes = payload.categories
        } catch {
            message = error.localizedDescription
        }
    }

    func setRoute(_ route: AlertRoute, whatsapp: Bool? = nil, native: Bool? = nil, floor: Int? = nil) async {
        // Optimistic, then reconciled. A toggle that waits for a round trip
        // springs back under the thumb and reads as a control that does not work.
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else { return }
        let snapshot = routes
        if let whatsapp { routes[index].whatsapp = whatsapp }
        if let native { routes[index].native = native }
        if let floor { routes[index].minIntervalSeconds = floor }
        SRHaptic.select()

        var body: [String: AnyEncodable] = ["category": AnyEncodable(route.id)]
        if let whatsapp { body["whatsapp"] = AnyEncodable(whatsapp) }
        if let native { body["native"] = AnyEncodable(native) }
        if let floor { body["minIntervalSeconds"] = AnyEncodable(floor) }

        do {
            let payload: AlertRoutes = try await client.send(
                "api/native/notifications/routes",
                method: "PUT",
                body: try JSONEncoder().encode(body)
            )
            routes = payload.categories
        } catch {
            routes = snapshot
            message = error.localizedDescription
            SRHaptic.bad()
        }
    }

    func markAllRead() async {
        guard client.isPaired, unread > 0 else { return }
        unread = 0
        recent = recent.map { alert in
            var copy = alert
            copy.read = true
            return copy
        }
        await refreshBadge()
        _ = try? await client.post(
            "api/native/notifications",
            body: try JSONSerialization.data(withJSONObject: ["readAll": true])
        )
    }

    // MARK: - Clearing Today

    /// Take alerts off the Today card. Local only — see `clearedFromToday`.
    func clearFromToday(_ ids: [String]) {
        var fresh: [String] = []
        for id in ids where !clearedFromToday.contains(id) && !fresh.contains(id) {
            fresh.append(id)
        }
        guard !fresh.isEmpty else { return }
        clearedFromToday.formUnion(fresh)
        // Stored oldest first so the cap trims from the front.
        var order = defaults.stringArray(forKey: Self.clearedKey) ?? []
        order.append(contentsOf: fresh)
        if order.count > Self.clearedCap {
            order.removeFirst(order.count - Self.clearedCap)
            clearedFromToday = Set(order)
        }
        defaults.set(order, forKey: Self.clearedKey)
    }

    // MARK: - Raising

    /// Ask once. Called from the notification settings screen, never at launch.
    ///
    /// A permission sheet on first open, before the reader has seen what the app
    /// does, is the reliable way to get it denied — and a denied notification
    /// permission cannot be asked for again, only changed in Settings.
    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted { SRHaptic.ok() }
        } catch {
            message = error.localizedDescription
        }
        await readPermission()
    }

    func readPermission() async {
        permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Post the queue as local notifications, then acknowledge what was posted.
    ///
    /// Acknowledging only what actually scheduled is the whole point: a throw
    /// half way through leaves the rest of the queue on the server, to be posted
    /// by the next refresh rather than lost.
    func raise(_ pending: [SiteAlert]) async {
        guard !pending.isEmpty else { return }
        await readPermission()
        guard permission == .authorized || permission == .provisional else { return }

        var delivered: [String] = []
        let centre = UNUserNotificationCenter.current()
        for alert in pending {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            // Connections get a thread of their own, so a lapsed Gmail never
            // stacks under a pile of health nudges in Notification Centre.
            content.threadIdentifier = alert.isConnections ? "connections" : alert.category
            content.categoryIdentifier = alert.category
            // Graded, and deliberately not upward. `.timeSensitive` and
            // `.critical` both need entitlements this profile does not carry, so
            // the only honest lever is DOWN: a health reading or a headline is
            // something to find later, not something to break a Focus for. An
            // alert-severity row keeps the default level, which is as loud as
            // this app is allowed to be.
            //
            // A connection that needs re-authorising is always `.active`,
            // whatever severity it arrived with: it is the one alert that stops
            // something working until the owner acts. And it ranks first in a
            // notification summary — the most this app can do short of
            // `.timeSensitive`, which it cannot have.
            let loud = alert.isAlert || alert.isConnections
            content.interruptionLevel = loud ? .active : .passive
            content.relevanceScore = alert.isConnections ? 1 : (loud ? 0.8 : 0.2)
            var info: [String: String] = ["id": alert.id, "category": alert.category]
            if let url = alert.url { info["url"] = url }
            content.userInfo = info
            // nil trigger means "as soon as this returns". The alert is already
            // late by however long iOS sat on the refresh; scheduling it further
            // out would be adding to that.
            let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
            do {
                try await centre.add(request)
                delivered.append(alert.id)
            } catch {
                // Leave it unacknowledged. The next refresh tries again.
                continue
            }
        }

        guard !delivered.isEmpty else { return }
        _ = try? await client.post(
            "api/native/notifications",
            body: try JSONSerialization.data(withJSONObject: ["collected": delivered])
        )
    }

    /// The red dot on the app icon.
    ///
    /// `setBadgeCount` rather than the deprecated `applicationIconBadgeNumber`,
    /// and it is allowed to fail silently — a badge is the least important thing
    /// on this screen and its permission is bundled with the alert permission.
    ///
    /// Through `AppBadge`, which adds the connections needing the owner.
    private func refreshBadge() async {
        await AppBadge.update(unread: unread)
    }

    /// One background pass: collect, raise, acknowledge.
    ///
    /// Separate from `refresh()` because a background run must not touch
    /// `@Published` state that a torn-down view hierarchy is not watching, and
    /// must finish inside the seconds iOS grants it. It asks for the queue only.
    static func backgroundPass() async {
        guard SiteClient.shared.isPaired else { return }
        do {
            let feed: AlertFeed = try await SiteClient.shared.send("api/native/notifications?limit=20&inbox=1")
            await AlertStore().raise(feed.pending)
            await AppBadge.update(unread: feed.unread)
        } catch {
            return
        }
    }
}

/// A one-off encoder box, so a settings PATCH can carry mixed value types.
///
/// `JSONEncoder` needs a concrete `Encodable`, and the routing body is three
/// optional fields of two different types. A `[String: Any]` through
/// `JSONSerialization` would do it, but then every call site loses the
/// compiler's check that the value is encodable at all.
struct AnyEncodable: Encodable {
    // Named with an underscore so it cannot shadow — or be shadowed by — the
    // `encode(to:)` requirement it implements. `private let encode` compiled and
    // then called itself.
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        _encode = { encoder in try value.encode(to: encoder) }
    }

    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
