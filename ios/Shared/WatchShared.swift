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
    /// The reader's palette, chosen on the phone (Settings → Colours). Nil
    /// from a phone older than palettes; the Watch then wears Prism.
    var palette: WatchPalette? = nil

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

/// The reader's palette, as a wrist wears it. watchOS is always dark, so these
/// are the dark page and the lifted partners the phone uses in dark mode, plus
/// a colour for each of Today's three rings. `0xRRGGBB`; Foundation only, so
/// the phone, the Watch app and the complications all read the same value.
struct WatchPalette: Codable, Equatable, Hashable {
    var ground: UInt32
    var cream: UInt32
    var accent: UInt32
    var good: UInt32
    var warn: UInt32
    var bad: UInt32
    /// The rings: Move (read on the wrist), Recovery and Readiness.
    var move: UInt32
    var recovery: UInt32
    var readiness: UInt32

    static let prism = WatchPalette(
        ground: 0x0B0A1C, cream: 0xF4F3FB, accent: 0xA194FF, good: 0x4ADE80, warn: 0xFFC24B, bad: 0xFF6B85,
        move: 0xFF5FA2, recovery: 0x3DDC84, readiness: 0xA194FF
    )
}

/// What the wrist can ask the phone to do. Every one is something the phone
/// already does from a screen or a notification button.
enum WatchCommand: Equatable {
    case markRead(id: String)
    case clearFromToday(id: String)
    case syncNow
    /// Put in the phone's composer, NEVER sent — see `AskJkaiIntent`.
    case ask(question: String)
    /// A quick answer, said back to the wrist: the phone runs the same
    /// read-only turn as `QuickAnswerIntent`, with surface 'watch', and
    /// replies with the text. Only while the phone is reachable — nobody is
    /// waiting on a queued one.
    case askAloud(question: String)
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
        case .askAloud(let question): return [Self.key: "askAloud", "question": question]
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
        case "askAloud":
            let question = (message["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !question.isEmpty else { return nil }
            self = .askAloud(question: question)
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
