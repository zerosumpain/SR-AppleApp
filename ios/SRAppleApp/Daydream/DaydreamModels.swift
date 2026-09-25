import Foundation

// MARK: - Noticed: the daydream loop's notes
//
// The site's daydream loop writes short, cited NOTES about the owner's life —
// nought to two every 45 minutes, across health, home, mail, chat, diary,
// money and research. The phone shows the latest two on Today and the health
// ones on the Health tab, and sends back a verdict on each so the loop learns
// what is worth saying.
//
// Wire contract (SR-Main, `/api/native/*`, the site credential):
//
//   GET  api/native/today                    → { …, "daydream": { "notes": [Note] } }   (key optional)
//   GET  api/native/daydream?scope=health&limit=5 → { "notes": [Note] }
//   POST api/native/daydream/feedback        { "id", "verdict": useful|not_useful|never } → { "ok": true }
//
// Everything decodes defensively. The server side is being built in parallel
// with this, and a Today payload that throws is a blank first screen, so an
// unknown outcome is a generic label, a malformed note is dropped on its own,
// and a `daydream` block of the wrong shape is simply no notes.

/// What kind of thing the loop concluded. Drives the small label over a note.
enum DaydreamOutcome: Hashable {
    case correlate, efficiency, qualityOfLife, research, build, healthPlan, suggest, moneyAnalysis
    /// A kind this build does not know yet. Still shown, under a generic label.
    case other(String)

    init(raw: String) {
        switch raw {
        case "correlate": self = .correlate
        case "efficiency": self = .efficiency
        case "quality_of_life": self = .qualityOfLife
        case "research": self = .research
        case "build": self = .build
        case "health_plan": self = .healthPlan
        case "suggest": self = .suggest
        case "money_analysis": self = .moneyAnalysis
        default: self = .other(raw)
        }
    }

    var raw: String {
        switch self {
        case .correlate: return "correlate"
        case .efficiency: return "efficiency"
        case .qualityOfLife: return "quality_of_life"
        case .research: return "research"
        case .build: return "build"
        case .healthPlan: return "health_plan"
        case .suggest: return "suggest"
        case .moneyAnalysis: return "money_analysis"
        case .other(let value): return value
        }
    }

    /// Human wording. The raw keys are the loop's vocabulary, not the reader's.
    var label: String {
        switch self {
        case .correlate: return "A connection"
        case .efficiency: return "Time saver"
        case .qualityOfLife: return "Quality of life"
        case .research: return "Research"
        case .build: return "Build idea"
        case .healthPlan: return "Health plan"
        case .suggest: return "Worth trying"
        case .moneyAnalysis: return "Money"
        case .other: return "Noticed"
        }
    }
}

/// Which part of life the note is about. Drives the glyph beside the label.
enum DaydreamChannel: Hashable {
    case health, home, mail, chat, diary, money, research
    case other(String)

    init(raw: String) {
        switch raw {
        case "health": self = .health
        case "home": self = .home
        case "mail": self = .mail
        case "chat": self = .chat
        case "diary": self = .diary
        case "money": self = .money
        case "research": self = .research
        default: self = .other(raw)
        }
    }

    var icon: String {
        switch self {
        case .health: return "heart"
        case .home: return "house"
        case .mail: return "envelope"
        case .chat: return "bubble.left"
        case .diary: return "book.closed"
        case .money: return "sterlingsign.circle"
        case .research: return "magnifyingglass"
        case .other: return "sparkle"
        }
    }
}

/// The reader's answer to a note. `never` means "never show this KIND again"
/// — the loop decides what a kind is; the phone only says so.
enum DaydreamVerdict: String, Codable, Hashable {
    case useful
    case notUseful = "not_useful"
    case never
}

struct DaydreamNote: Decodable, Identifiable, Hashable {
    let id: String
    let outcome: DaydreamOutcome
    let channel: DaydreamChannel
    let title: String
    let body: String
    /// ISO-8601, as sent. `shortAgo` reads it.
    let createdAt: String
    /// A site path (`/jkai/daydreams?note=<id>`), opened on the website.
    let url: String
    /// The verdict already recorded on the site, if any.
    let feedback: DaydreamVerdict?

    init(id: String, outcome: DaydreamOutcome, channel: DaydreamChannel, title: String, body: String,
         createdAt: String, url: String? = nil, feedback: DaydreamVerdict? = nil) {
        self.id = id
        self.outcome = outcome
        self.channel = channel
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.url = url ?? DaydreamNote.defaultPath(for: id)
        self.feedback = feedback
    }

    enum CodingKeys: String, CodingKey { case id, outcome, channel, title, body, createdAt, url, feedback }

    /// An id and a title are the note; without either there is nothing to show
    /// or to answer, so the note throws and `Lossy` drops it alone.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.flexString(.id), !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "a note needs an id")
        }
        guard let title = c.lenient(String.self, .title), !title.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .title, in: c, debugDescription: "a note needs a title")
        }
        self.id = id
        self.title = title
        outcome = DaydreamOutcome(raw: c.lenient(String.self, .outcome) ?? "")
        channel = DaydreamChannel(raw: c.lenient(String.self, .channel) ?? "")
        body = c.lenient(String.self, .body) ?? ""
        createdAt = c.lenient(String.self, .createdAt) ?? ""
        let path = c.lenient(String.self, .url) ?? ""
        url = path.isEmpty ? DaydreamNote.defaultPath(for: id) : path
        // `null`, absent, or a verdict this build does not know — all "not yet".
        feedback = c.lenient(String.self, .feedback).flatMap(DaydreamVerdict.init(rawValue:))
    }

    static func defaultPath(for id: String) -> String {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        return "/jkai/daydreams?note=\(escaped)"
    }
}

/// `{ "notes": [...] }` — the Today block and the scoped endpoint's answer.
///
/// Never throws. A `daydream` key that arrives as something other than an
/// object must cost the Noticed card, not the whole of Today.
struct DaydreamFeed: Decodable, Hashable {
    let notes: [DaydreamNote]

    init(notes: [DaydreamNote]) { self.notes = notes }

    enum CodingKeys: String, CodingKey { case notes }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            notes = []
            return
        }
        notes = c.lossy(DaydreamNote.self, .notes)
    }
}

/// The body of `POST api/native/daydream/feedback`.
struct DaydreamFeedbackRequest: Encodable, Equatable {
    let id: String
    let verdict: DaydreamVerdict
}
