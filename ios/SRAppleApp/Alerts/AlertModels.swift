import Foundation

/// Something the site wanted to tell you.
///
/// The `data` field the server can attach is deliberately not decoded. It is
/// free-form JSON whose shape is the producer's business, `Decodable` has no
/// pleasant representation for that, and nothing on this screen reads it — the
/// title and the body are the notification.
struct SiteAlert: Decodable, Identifiable, Hashable {
    let id: String
    let category: String
    let title: String
    let body: String
    let url: String?
    let severity: String
    let createdAt: String
    var read: Bool

    /// `alert` is the notification ledger's loudest level — and what SR-Main's
    /// connection monitor sends for a lapsed authorisation. `high` is accepted
    /// too, in case a producer ever uses it. Raised at the loudest level this
    /// app is allowed.
    var isAlert: Bool { severity == "alert" || severity == "high" }
    /// A site connection (Gmail, a calendar…) that needs re-authorising.
    var isConnections: Bool { category == "connections" }
    var isWarning: Bool { severity == "warn" }

    /// The SF Symbol for the category. A notification list where every row has
    /// the same glyph is a list with no glyph.
    var icon: String {
        switch category {
        case "health": return "heart.fill"
        case "chat": return "bubble.left.fill"
        case "build": return "hammer.fill"
        case "deploy": return "shippingbox.fill"
        case "uptime": return "wave.3.right"
        case "intel": return "sparkle.magnifyingglass"
        case "news": return "newspaper.fill"
        case "connections": return "key.slash"
        default: return "bell.fill"
        }
    }
}

struct AlertFeed: Decodable {
    let pending: [SiteAlert]
    let recent: [SiteAlert]
    let unread: Int
}

/// Where one category goes, as the phone sees it.
struct AlertRoute: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
    let description: String
    var whatsapp: Bool
    var native: Bool
    var minIntervalSeconds: Int
    let customised: Bool

    /// "No more than once every 3 hours", said the way a person would.
    var floorSentence: String? {
        guard minIntervalSeconds > 0 else { return nil }
        let hours = minIntervalSeconds / 3600
        let minutes = (minIntervalSeconds % 3600) / 60
        if hours > 0 && minutes == 0 { return "At most once every \(hours) hour\(hours == 1 ? "" : "s")" }
        if hours > 0 { return "At most once every \(hours)h \(minutes)m" }
        return "At most once every \(minutes) minutes"
    }

    /// The one-line answer to "where does this go".
    var destination: String {
        switch (whatsapp, native) {
        case (true, true): return "WhatsApp and this iPhone"
        case (true, false): return "WhatsApp only"
        case (false, true): return "This iPhone only"
        case (false, false): return "Off"
        }
    }
}

struct AlertRoutes: Decodable {
    let categories: [AlertRoute]
}
