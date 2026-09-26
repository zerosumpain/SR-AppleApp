import Foundation

// Compiled into three targets: the iPhone app, the Watch app and the Watch's
// complications. Foundation only, so it builds for both platforms, and pure,
// so the iPhone's unit tests cover the Watch's half of the contract too.
//
// The phone is the only thing holding a credential. It builds a
// `WatchSnapshot` from what it already loaded, sends it as the WatchConnectivity
// application context, and does whatever a `WatchCommand` from the wrist asks.
// See docs/WATCH.md.

/// Everything the Watch shows. Small by design: the application context is
/// replaced whole on every send, and a wrist has no use for a transcript.
struct WatchSnapshot: Codable, Equatable {
    struct Figure: Codable, Equatable, Identifiable {
        let key: String
        let label: String
        /// Rendered by the site ("64", "7h 24m"), unit apart.
        let display: String
        let unit: String?
        /// 0…1 for a ring, when the figure is a score.
        let fraction: Double?

        var id: String { key }
    }

    struct Alert: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let severity: String
        let createdAt: String
    }

    struct PinnedFlow: Codable, Equatable, Identifiable {
        let slug: String
        let title: String
        var id: String { slug }
    }

    struct Sync: Codable, Equatable {
        let queued: Int
        let lastUpload: Date?
        /// "tracking", "armed" (GPS asleep until motion), "blocked", or nil when
        /// the phone never set location sharing up.
        let gate: String?
    }

    /// Bumped when a field changes meaning. A Watch reading a snapshot from a
    /// newer phone shows what it recognises and ignores the rest.
    var version = 1
    let generatedAt: Date

    /// nil when the site sent no readiness today.
    let readiness: Figure?
    let recovery: Figure?
    /// HRV, resting heart rate, sleep — the figures /health leads with.
    let figures: [Figure]
    let healthUpdatedAt: String?

    /// The uncleared alerts Today would show. Empty for anyone but the owner.
    let alerts: [Alert]
    let unread: Int
    /// Whether this person may see the inbox at all. Hides the tab, rather than
    /// showing an empty one that reads as "nothing happened".
    let showsAlerts: Bool

    let sync: Sync
    let connectionNeedsFixing: Bool

    /// Up to three, owner only.
    let pinnedFlows: [PinnedFlow]
    /// Whether a question may be started from the wrist (this person has chat).
    let canAsk: Bool

    static let empty = WatchSnapshot(
        generatedAt: .distantPast, readiness: nil, recovery: nil, figures: [], healthUpdatedAt: nil,
        alerts: [], unread: 0, showsAlerts: false,
        sync: Sync(queued: 0, lastUpload: nil, gate: nil), connectionNeedsFixing: false,
        pinnedFlows: [], canAsk: false
    )

    // MARK: Wire format

    /// WatchConnectivity carries property-list dictionaries, so the snapshot
    /// travels as one JSON blob under one key.
    static let contextKey = "snapshot"

    func context() -> [String: Any] {
        guard let data = try? Self.encoder.encode(self) else { return [:] }
        return [Self.contextKey: data]
    }

    static func from(context: [String: Any]) -> WatchSnapshot? {
        guard let data = context[contextKey] as? Data else { return nil }
        return try? decoder.decode(WatchSnapshot.self, from: data)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

/// What the wrist can ask the phone to do. Every one is something the phone
/// already does from a screen or a notification button.
enum WatchCommand: Equatable {
    case markRead(id: String)
    case clearFromToday(id: String)
    case syncNow
    /// Put in the phone's composer, NEVER sent — see `AskJkaiIntent`.
    case ask(question: String)
    case runFlow(slug: String)
    /// "Send me what you have": the Watch opened with nothing, or a stale copy.
    case refresh

    static let key = "command"

    var message: [String: Any] {
        switch self {
        case .markRead(let id): return [Self.key: "markRead", "id": id]
        case .clearFromToday(let id): return [Self.key: "clear", "id": id]
        case .syncNow: return [Self.key: "sync"]
        case .ask(let question): return [Self.key: "ask", "question": question]
        case .runFlow(let slug): return [Self.key: "runFlow", "slug": slug]
        case .refresh: return [Self.key: "refresh"]
        }
    }

    init?(message: [String: Any]) {
        switch message[Self.key] as? String {
        case "markRead":
            guard let id = message["id"] as? String, !id.isEmpty else { return nil }
            self = .markRead(id: id)
        case "clear":
            guard let id = message["id"] as? String, !id.isEmpty else { return nil }
            self = .clearFromToday(id: id)
        case "sync": self = .syncNow
        case "ask":
            let question = (message["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !question.isEmpty else { return nil }
            self = .ask(question: question)
        case "runFlow":
            guard let slug = message["slug"] as? String, !slug.isEmpty else { return nil }
            self = .runFlow(slug: slug)
        case "refresh": self = .refresh
        default: return nil
        }
    }
}

/// The phone's answer to a command, shown on the wrist for a moment.
struct WatchReply: Equatable {
    let ok: Bool
    let text: String

    static let okKey = "ok"
    static let textKey = "text"

    var message: [String: Any] { [Self.okKey: ok, Self.textKey: text] }

    init(ok: Bool, text: String) {
        self.ok = ok
        self.text = text
    }

    init(message: [String: Any]) {
        ok = message[Self.okKey] as? Bool ?? false
        text = message[Self.textKey] as? String ?? (ok ? "Done" : "The iPhone did not answer.")
    }
}

/// Where the Watch app leaves the snapshot for its complications. The group is
/// named in each target's Info.plist (`SRAppGroup`), derived from the bundle
/// identifier the build was given, so a fork signs with its own.
enum WatchShelf {
    static let key = "watch.snapshot"

    static var groupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "SRAppGroup") as? String
    }

    static var defaults: UserDefaults? {
        groupID.flatMap { UserDefaults(suiteName: $0) }
    }

    static func save(_ snapshot: WatchSnapshot) {
        guard let data = try? WatchSnapshot.encoder.encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    static func load() -> WatchSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? WatchSnapshot.decoder.decode(WatchSnapshot.self, from: data)
    }
}
