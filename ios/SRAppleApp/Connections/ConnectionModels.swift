import Foundation
import UserNotifications

// MARK: - A connection the site holds that needs the owner
//
// Not either of this iPhone's two pairings. These are the accounts the WEBSITE
// signs in to on the owner's behalf — Gmail above all, whose authorisation
// lapses about weekly and, until this existed, lapsed silently. The site knows
// when one has; `GET /api/native/connections` says which.
//
// Every field is decoded leniently. This contract was written alongside the
// server, and a phone on an older build must survive a server that adds a
// field, drops one, or sends a status nobody here has heard of: one malformed
// item must never cost the reader the whole list, because the list is the
// warning.

/// One site connection that needs the owner — expired, revoked or failing.
struct ConnectionItem: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let group: String
    let status: String
    let detail: String
    let fixHint: String?
    /// Kept as the server sent it; `fixURL` is the checked version.
    let fixUrl: String?
    /// ISO-8601, when the site first saw it lapse. `sinceDate` parses it.
    let since: String?

    init(id: String, label: String, group: String = "", status: String, detail: String,
         fixHint: String? = nil, fixUrl: String? = nil, since: String? = nil) {
        self.id = id
        self.label = label
        self.group = group
        self.status = status
        self.detail = detail
        self.fixHint = fixHint
        self.fixUrl = fixUrl
        self.since = since
    }

    enum CodingKeys: String, CodingKey { case id, label, group, status, detail, fixHint, fixUrl, since }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawId = c.flexString(.id)
        let rawLabel = c.lenient(String.self, .label)
        label = rawLabel ?? rawId ?? "A connection"
        // A stable id matters: the banner's "collapsed" state is keyed on the
        // set of ids, and a random one would re-expand it on every refresh.
        id = rawId ?? "connection-\(label)"
        group = c.lenient(String.self, .group) ?? ""
        status = c.lenient(String.self, .status) ?? ""
        detail = c.lenient(String.self, .detail) ?? ""
        fixHint = c.lenient(String.self, .fixHint)
        fixUrl = c.lenient(String.self, .fixUrl)
        since = c.lenient(String.self, .since)
    }

    var state: ConnectionStatus { ConnectionStatus(status) }

    /// The one line the banner leads with.
    var headline: String {
        switch state {
        case .needsReauth: return "\(label) needs re-authorising"
        case .failing: return "\(label) is failing"
        case .other: return "\(label) needs you"
        }
    }

    /// The supporting line: what the site said, or what to do about it.
    var subline: String {
        if !detail.isEmpty { return detail }
        if let fixHint, !fixHint.isEmpty { return fixHint }
        return "Open the site to reconnect it."
    }

    /// Where Fix goes — an absolute HTTPS address or nothing.
    ///
    /// The consent screen has to run in Safari, where the site session lives;
    /// a link to anywhere that is not HTTPS is not one this app will open.
    var fixURL: URL? {
        guard let fixUrl, let url = URL(string: fixUrl), url.scheme?.lowercased() == "https", url.host != nil else {
            return nil
        }
        return url
    }

    var sinceDate: Date? { since.flatMap(parseTimestamp) }

    var icon: String {
        switch state {
        case .needsReauth: return "key.slash"
        case .failing: return "exclamationmark.triangle.fill"
        case .other: return "exclamationmark.circle.fill"
        }
    }
}

/// What a connection's `status` means to this screen.
///
/// Open-ended on purpose: the server owns the vocabulary, and a status this
/// build has never seen still reads as "needs you" rather than failing to
/// decode the row that carries it.
enum ConnectionStatus: Equatable {
    case needsReauth
    case failing
    case other(String)

    init(_ raw: String) {
        let key = raw.lowercased().replacingOccurrences(of: "-", with: "_")
        switch key {
        // `auth_expired` and `broken` are what SR-Main's monitor sends (#947);
        // the rest are tolerated so a vocabulary change degrades gracefully.
        case "auth_expired", "expired", "revoked", "reauth", "needs_reauth", "reauthorise", "reauthorize",
             "needs_reauthorisation", "needs_reauthorization", "unauthorised", "unauthorized",
             "invalid_grant", "disconnected", "missing", "not_connected":
            self = .needsReauth
        case "broken", "error", "failing", "failed", "degraded", "down":
            self = .failing
        default:
            self = .other(raw)
        }
    }
}

/// `GET /api/native/connections`.
struct ConnectionsFeed: Decodable {
    let needsAttention: [ConnectionItem]
    let checkedAt: String?

    enum CodingKeys: String, CodingKey { case needsAttention, checkedAt }

    init(needsAttention: [ConnectionItem], checkedAt: String?) {
        self.needsAttention = needsAttention
        self.checkedAt = checkedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        needsAttention = c.lossy(ConnectionItem.self, .needsAttention)
        checkedAt = c.lenient(String.self, .checkedAt)
    }
}

/// The `connections` block on `/api/native/today`. Absent on an older server,
/// which reads as nothing needing the owner.
struct TodayConnections: Decodable, Hashable {
    let needsAttention: Int
    let items: [ConnectionItem]

    enum CodingKeys: String, CodingKey { case needsAttention, items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(ConnectionItem.self, .items)
        needsAttention = c.lenient(Int.self, .needsAttention) ?? items.count
    }
}

/// The last answer, kept across launches in `PersistedState`.
///
/// So the banner is up the moment the app opens, before any request — and
/// stays up on a flight, which is exactly when a lapsed Gmail goes unnoticed.
struct ConnectionsSnapshot: Codable, Equatable {
    var items: [ConnectionItem] = []
    var checkedAt: Date?

    init(items: [ConnectionItem] = [], checkedAt: Date? = nil) {
        self.items = items
        self.checkedAt = checkedAt
    }

    /// Same rule as `PersistedState`: every field optional-with-a-default, so a
    /// shape written by another build decodes rather than throws.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(ConnectionItem.self, .items)
        checkedAt = c.lenient(Date.self, .checkedAt)
    }
}

// MARK: - The banner's three states

/// What the banner at the top of every tab shows.
///
/// It cannot be dismissed, only made smaller, and only for as long as the set
/// of connections needing the owner stays the same: a NEW one re-opens it.
enum ConnectionBannerMode: Equatable {
    case hidden
    case full
    case slim

    static func of(items: [ConnectionItem], collapsedFor: Set<String>?) -> ConnectionBannerMode {
        guard !items.isEmpty else { return .hidden }
        guard let collapsedFor else { return .full }
        return Set(items.map(\.id)).isSubset(of: collapsedFor) ? .slim : .full
    }
}

// MARK: - The app icon's badge

/// The red number on the icon: unread alerts PLUS connections needing you.
///
/// Two stores write it, at different times and sometimes from a background
/// wake with no views alive, so each hands in its half and the last-known other
/// half is kept here. The permission is the one the notification settings
/// screen already asks for (`.badge` is in that request); nothing here asks.
enum AppBadge {
    static func total(unread: Int, connections: Int) -> Int {
        max(unread, 0) + max(connections, 0)
    }

    private static let unreadKey = "badge-unread"
    private static let connectionsKey = "badge-connections"

    @MainActor
    static func update(unread: Int? = nil, connections: Int? = nil, defaults: UserDefaults = .standard) async {
        if let unread { defaults.set(unread, forKey: unreadKey) }
        if let connections { defaults.set(connections, forKey: connectionsKey) }
        let count = total(unread: defaults.integer(forKey: unreadKey), connections: defaults.integer(forKey: connectionsKey))
        // Allowed to fail silently — a badge is the least important signal
        // here, and without permission there is simply no badge.
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}
