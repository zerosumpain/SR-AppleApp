import Foundation

// MARK: - Wildmind's owner lane, as the site sends it
//
// Talk, Chronicle, Inventions and whispers: the parts of Wildmind that carry
// what the model writes (speech, thoughts, diaries, John's whispers), so they
// reach the owner's phone alone, through SR-Main's `withDevice` routes:
//
//   GET  api/native/wildmind/talk?before&since&limit&who&kinds
//   GET  api/native/wildmind/chronicle?id=main|companion
//   GET  api/native/wildmind/inventions
//   GET  api/native/wildmind/whispers?limit
//   POST api/native/wildmind/whisper   {text} + Idempotency-Key: <uuid>
//
// The shapes are Wildmind's own (its W5 owner contract), re-validated by
// SR-Main and passed through with the same field names, plus SR-Main's
// `state`: `"live"` on an answer, or the whole body `{"state":"offline"}`
// (still a 200) when the lane is closed or Wildmind is silent. A body with no
// `state` at all is read as live, so Wildmind's own examples decode too.
//
// Foundation only, like `WildmindModels.swift`, whose tolerant helpers these
// use: the decoders and the whisper rules are the part of these screens that
// can be compiled and RUN on Linux. A row that will not read is dropped and
// the rest kept; a kind this build has not met is `unknown`, never a throw.

/// The valley an owner answer is about. A changed `seed` is a new valley: the
/// phone drops what it held and starts again.
struct WildmindValley: Decodable, Sendable, Equatable, Hashable {
    var seed: Int?
    var generation: Int?
    var day: Int?
    /// "Day 24, 17:00".
    var clock: String?

    init(seed: Int? = nil, generation: Int? = nil, day: Int? = nil, clock: String? = nil) {
        self.seed = seed
        self.generation = generation
        self.day = day
        self.clock = clock
    }

    private enum CodingKeys: String, CodingKey { case seed, generation, day, clock }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seed = c.wmInt(.seed)
        generation = c.wmInt(.generation)
        day = c.wmInt(.day)
        clock = c.wmLabel(.clock)
    }
}

/// SR-Main's word on the lane: everything but `"offline"` is an answer.
enum WildmindLane {
    static func isOffline(_ state: String?) -> Bool { state == "offline" }
}

// MARK: - Talk

enum WildmindTalkKind: String, Sendable, Equatable, Hashable, CaseIterable {
    case speech, thought, whisper, diary
    /// A kind this build has not heard of: shown as a quiet line.
    case unknown

    init(raw: String?) {
        self = raw.flatMap(WildmindTalkKind.init(rawValue:)) ?? .unknown
    }
}

/// One thing said, thought, written or whispered.
struct WildmindTalkEntry: Decodable, Sendable, Equatable, Hashable, Identifiable {
    /// Wildmind's log id. Whispers and the thoughts that answer them share
    /// this numbering with `/whispers`.
    var id: Int
    var minute: Double?
    var when: String?
    /// "main" or "companion".
    var who: String?
    var name: String?
    var kind: WildmindTalkKind
    /// Speech only: the person spoken to.
    var to: String?
    var toName: String?
    var text: String
    /// A model thought's "Goal: … · Mood: …".
    var detail: String?

    init(id: Int, minute: Double? = nil, when: String? = nil, who: String? = nil, name: String? = nil,
         kind: WildmindTalkKind, to: String? = nil, toName: String? = nil, text: String, detail: String? = nil) {
        self.id = id
        self.minute = minute
        self.when = when
        self.who = who
        self.name = name
        self.kind = kind
        self.to = to
        self.toName = toName
        self.text = text
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey { case id, minute, when, who, name, kind, to, toName, text, detail }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // An entry with no id cannot be paged past or matched to a whisper,
        // and one with no text has nothing to show: both are dropped.
        guard let id = c.wmInt(.id), let text = c.wmString(.text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no id or text"))
        }
        self.id = id
        self.text = text
        minute = c.wmNumber(.minute)
        when = c.wmLabel(.when)
        who = c.wmString(.who)
        name = c.wmString(.name)
        kind = WildmindTalkKind(raw: c.wmString(.kind))
        to = c.wmString(.to)
        toName = c.wmString(.toName)
        detail = c.wmString(.detail)
    }

    /// The thought's goal, from `detail`.
    var goal: String? { Self.part("Goal", of: detail) }
    /// The thought's mood, from `detail`.
    var mood: String? { Self.part("Mood", of: detail) }

    /// `Goal: Build a reed raft · Mood: eager` → "Build a reed raft" for "Goal".
    static func part(_ label: String, of detail: String?) -> String? {
        guard let detail else { return nil }
        for piece in detail.components(separatedBy: " \u{00B7} ") {
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            let prefix = label + ":"
            if trimmed.lowercased().hasPrefix(prefix.lowercased()) {
                let value = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}

/// `GET api/native/wildmind/talk`: entries NEWEST FIRST.
struct WildmindTalkPage: Decodable, Sendable, Equatable {
    var offline: Bool
    var valley: WildmindValley?
    var entries: [WildmindTalkEntry]
    var oldestId: Int?
    var latestId: Int?
    /// Without `since`: older entries remain. With `since`: newer remain.
    var more: Bool

    init(offline: Bool = false, valley: WildmindValley? = nil, entries: [WildmindTalkEntry] = [],
         oldestId: Int? = nil, latestId: Int? = nil, more: Bool = false) {
        self.offline = offline
        self.valley = valley
        self.entries = entries
        self.oldestId = oldestId
        self.latestId = latestId
        self.more = more
    }

    private enum CodingKeys: String, CodingKey { case state, valley, entries, oldestId, latestId, more }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offline = WildmindLane.isOffline(c.wmString(.state))
        valley = try? c.decodeIfPresent(WildmindValley.self, forKey: .valley)
        entries = c.wmList(.entries)
        oldestId = c.wmInt(.oldestId)
        latestId = c.wmInt(.latestId)
        more = c.wmBool(.more) ?? false
    }
}

/// What Talk asks for: which kinds, whose.
struct WildmindTalkFilter: Equatable, Hashable, Sendable {
    enum Kinds: String, CaseIterable, Sendable {
        case all, said, thought, whispers, diaries

        var label: String {
            switch self {
            case .all: return "All"
            case .said: return "Said"
            case .thought: return "Thought"
            case .whispers: return "Whispers"
            case .diaries: return "Diaries"
            }
        }

        /// The `kinds=` value, or nil for everything.
        var query: String? {
            switch self {
            case .all: return nil
            case .said: return "speech"
            case .thought: return "thought"
            case .whispers: return "whisper"
            case .diaries: return "diary"
            }
        }
    }

    enum Who: String, CaseIterable, Sendable {
        case both, main, companion

        /// The `who=` value, or nil for both.
        var query: String? { self == .both ? nil : rawValue }
    }

    var kinds: Kinds = .all
    var who: Who = .both

    /// Whether John's whispers show under this filter: they are JKai's, and
    /// a whisper kind.
    var showsWhispers: Bool {
        (kinds == .all || kinds == .whispers) && who != .companion
    }

    /// The path for one page: the newest, one older than `before`, or the
    /// ones newer than `since`.
    func path(before: Int? = nil, since: Int? = nil, limit: Int = 60) -> String {
        var items = ["limit=\(max(1, min(200, limit)))"]
        if let before, before >= 1 { items.append("before=\(before)") }
        if let since, since >= 0 { items.append("since=\(since)") }
        if let who = who.query { items.append("who=\(who)") }
        if let kinds = kinds.query { items.append("kinds=\(kinds)") }
        return "api/native/wildmind/talk?" + items.joined(separator: "&")
    }
}

/// The entries Talk holds, oldest first for the thread, merged page by page.
enum WildmindTalkMerge {
    /// `held` and a fresh page, by id, oldest first, one copy of each.
    static func merge(_ held: [WildmindTalkEntry], _ page: [WildmindTalkEntry]) -> [WildmindTalkEntry] {
        var byId: [Int: WildmindTalkEntry] = [:]
        for entry in held { byId[entry.id] = entry }
        for entry in page { byId[entry.id] = entry }
        return byId.values.sorted { $0.id < $1.id }
    }
}

/// The thread Talk holds and where to ask after it.
///
/// `cursor` is the newest log id a page from the site has brought, and is
/// what `since` asks after. It is never a whisper shown straight after
/// sending: that whisper's log id is the valley's newest, so asking `since`
/// it would skip whatever was said or thought between the last page and the
/// whisper, and those entries would never come. Such a whisper is held in
/// `optimistic`, shown in `entries`, until a page brings it.
struct WildmindTalkThread: Equatable, Sendable {
    /// Oldest first.
    private(set) var entries: [WildmindTalkEntry] = []
    private(set) var cursor: Int?
    private(set) var optimistic: [WildmindTalkEntry] = []

    /// Start again: a new filter, a new valley, a closed route.
    mutating func forget() {
        entries = []
        cursor = nil
        optimistic = []
    }

    /// A page from the site: the newest page (`replacing`, which starts the
    /// thread again) or the ones after `cursor`.
    mutating func adopt(_ page: [WildmindTalkEntry], replacing: Bool, newValley: Bool = false) {
        if newValley { optimistic = [] }
        let brought = Set(page.map(\.id))
        optimistic.removeAll { brought.contains($0.id) }
        let newest = page.map(\.id).max()
        if replacing {
            entries = WildmindTalkMerge.merge(page, optimistic)
            cursor = newest
        } else {
            entries = WildmindTalkMerge.merge(entries, page)
            if let newest { cursor = max(cursor ?? newest, newest) }
        }
    }

    /// An older page: it never moves the cursor.
    mutating func adoptOlder(_ page: [WildmindTalkEntry]) {
        let brought = Set(page.map(\.id))
        optimistic.removeAll { brought.contains($0.id) }
        entries = WildmindTalkMerge.merge(entries, page)
    }

    /// A whisper just accepted, shown before a page brings it.
    mutating func showSent(_ entry: WildmindTalkEntry) {
        optimistic = WildmindTalkMerge.merge(optimistic, [entry])
        entries = WildmindTalkMerge.merge(entries, [entry])
    }
}

// MARK: - Chronicle

struct WildmindChronicle: Decodable, Sendable, Equatable {
    var offline: Bool
    var valley: WildmindValley?
    var who: Who?
    var now: Now?
    /// Newest first.
    var timeline: [Event]
    /// Newest first.
    var diary: [Diary]

    struct Who: Decodable, Sendable, Equatable {
        var id: String
        var name: String
        var alive: Bool
        var causeOfDeath: String?
        var persona: String?

        private enum CodingKeys: String, CodingKey { case id, name, alive, causeOfDeath, persona }

        init(id: String, name: String, alive: Bool = true, causeOfDeath: String? = nil, persona: String? = nil) {
            self.id = id
            self.name = name
            self.alive = alive
            self.causeOfDeath = causeOfDeath
            self.persona = persona
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.wmString(.id) ?? "main"
            name = c.wmString(.name) ?? (id == "companion" ? "Wren" : "JKai")
            alive = c.wmBool(.alive) ?? true
            causeOfDeath = c.wmString(.causeOfDeath)
            persona = c.wmString(.persona).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    struct Now: Decodable, Sendable, Equatable {
        var lastThought: String?
        var mood: String?
        var goal: String?
        var ambitions: [Ambition]
        var values: [Value]
        var attitudes: [Attitude]
        var people: [Person]

        private enum CodingKeys: String, CodingKey { case lastThought, mood, goal, ambitions, values, attitudes, people }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Wildmind sends "" for "no thought yet"; that is nothing to show.
            lastThought = c.wmString(.lastThought).flatMap { $0.isEmpty ? nil : $0 }
            mood = c.wmString(.mood).flatMap { $0.isEmpty ? nil : $0 }
            goal = c.wmString(.goal).flatMap { $0.isEmpty ? nil : $0 }
            ambitions = c.wmList(.ambitions)
            values = c.wmList(.values)
            attitudes = c.wmList(.attitudes)
            people = c.wmList(.people)
        }
    }

    struct Ambition: Decodable, Sendable, Equatable, Hashable {
        var text: String
        /// active | done | abandoned
        var status: String?

        private enum CodingKeys: String, CodingKey { case text, status }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let text = c.wmString(.text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no text"))
            }
            self.text = text
            status = c.wmString(.status)
        }

        var isActive: Bool { status == nil || status == "active" }
    }

    struct Value: Decodable, Sendable, Equatable, Hashable {
        var text: String
        var strength: Double?
        var since: String?
        var kept: Int?
        var broken: Int?

        private enum CodingKeys: String, CodingKey { case text, strength, since, kept, broken }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let text = c.wmString(.text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no text"))
            }
            self.text = text
            strength = c.wmNumber(.strength)
            since = c.wmLabel(.since)
            kept = c.wmInt(.kept)
            broken = c.wmInt(.broken)
        }
    }

    struct Attitude: Decodable, Sendable, Equatable, Hashable {
        var subject: String
        /// -100…100.
        var feeling: Double?
        var reason: String?
        var since: String?

        private enum CodingKeys: String, CodingKey { case subject, feeling, reason, since }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let subject = c.wmString(.subject) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no subject"))
            }
            self.subject = subject
            feeling = c.wmNumber(.feeling)
            reason = c.wmString(.reason).flatMap { $0.isEmpty ? nil : $0 }
            since = c.wmLabel(.since)
        }
    }

    struct Person: Decodable, Sendable, Equatable, Hashable {
        var name: String
        var trust: Double?
        var affection: Double?
        var note: String?
        var partner: Bool

        private enum CodingKeys: String, CodingKey { case name, trust, affection, note, partner }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let name = c.wmString(.name) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no name"))
            }
            self.name = name
            trust = c.wmNumber(.trust)
            affection = c.wmNumber(.affection)
            note = c.wmString(.note).flatMap { $0.isEmpty ? nil : $0 }
            partner = c.wmBool(.partner) ?? false
        }
    }

    struct Event: Decodable, Sendable, Equatable, Hashable {
        var minute: Double?
        var day: Int?
        var when: String?
        var kind: String
        var icon: String?
        var text: String

        private enum CodingKeys: String, CodingKey { case minute, day, when, kind, icon, text }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let text = c.wmString(.text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no text"))
            }
            self.text = text
            minute = c.wmNumber(.minute)
            day = c.wmInt(.day)
            when = c.wmLabel(.when)
            kind = c.wmString(.kind) ?? "other"
            icon = c.wmString(.icon).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    struct Diary: Decodable, Sendable, Equatable, Hashable {
        var day: Int?
        var text: String

        private enum CodingKeys: String, CodingKey { case day, text }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let text = c.wmString(.text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no text"))
            }
            self.text = text
            day = c.wmInt(.day)
        }
    }

    private enum CodingKeys: String, CodingKey { case state, valley, who, now, timeline, diary }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offline = WildmindLane.isOffline(c.wmString(.state))
        valley = try? c.decodeIfPresent(WildmindValley.self, forKey: .valley)
        who = try? c.decodeIfPresent(Who.self, forKey: .who)
        now = try? c.decodeIfPresent(Now.self, forKey: .now)
        timeline = c.wmList(.timeline)
        diary = c.wmList(.diary)
    }

    /// The timeline's kinds, most frequent first, for the filter chips.
    var kinds: [String] {
        var counts: [String: Int] = [:]
        for event in timeline { counts[event.kind, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }
}

// MARK: - Inventions

struct WildmindInventionEntry: Decodable, Sendable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var kind: String?
    var description: String?
    var inventor: String?
    var day: Int?
    var placed: Bool
    /// The recipe in a line: "made at a workstation", "build: 10 Bark, …".
    var summary: String?
    /// The referee's notes.
    var notes: [String]
    var rationale: String?

    init(id: String, name: String, kind: String? = nil, description: String? = nil, inventor: String? = nil,
         day: Int? = nil, placed: Bool = false, summary: String? = nil, notes: [String] = [], rationale: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.description = description
        self.inventor = inventor
        self.day = day
        self.placed = placed
        self.summary = summary
        self.notes = notes
        self.rationale = rationale
    }

    private enum CodingKeys: String, CodingKey { case id, name, kind, description, inventor, day, placed, summary, notes, rationale }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.wmString(.id), let name = c.wmString(.name) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no id or name"))
        }
        self.id = id
        self.name = name
        kind = c.wmString(.kind).flatMap { $0.isEmpty ? nil : $0 }
        description = c.wmString(.description).flatMap { $0.isEmpty ? nil : $0 }
        inventor = c.wmString(.inventor).flatMap { $0.isEmpty ? nil : $0 }
        day = c.wmInt(.day)
        placed = c.wmBool(.placed) ?? false
        summary = c.wmString(.summary).flatMap { $0.isEmpty ? nil : $0 }
        notes = (c.wmList(.notes) as [String]).filter { !$0.isEmpty }
        rationale = c.wmString(.rationale).flatMap { $0.isEmpty ? nil : $0 }
    }
}

struct WildmindRefusal: Decodable, Sendable, Equatable, Hashable {
    var when: String?
    var text: String

    private enum CodingKeys: String, CodingKey { case when, text }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let text = c.wmString(.text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no text"))
        }
        self.text = text
        when = c.wmLabel(.when)
    }
}

/// `GET api/native/wildmind/inventions`: newest first.
struct WildmindInventions: Decodable, Sendable, Equatable {
    var offline: Bool
    var valley: WildmindValley?
    var inventions: [WildmindInventionEntry]
    var refused: [WildmindRefusal]

    private enum CodingKeys: String, CodingKey { case state, valley, inventions, refused }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offline = WildmindLane.isOffline(c.wmString(.state))
        valley = try? c.decodeIfPresent(WildmindValley.self, forKey: .valley)
        inventions = c.wmList(.inventions)
        refused = c.wmList(.refused)
    }
}

// MARK: - Whispers

enum WildmindWhisperStatus: String, Sendable, Equatable, Hashable {
    /// Still on JKai's pending list.
    case pending
    /// Heard by a thought whose prompt held it (`answer`).
    case heard
    /// Pushed out by two newer whispers before any thought heard it.
    case dropped
    case unknown

    init(raw: String?) {
        self = raw.flatMap(WildmindWhisperStatus.init(rawValue:)) ?? .unknown
    }
}

/// The thought that heard a whisper.
struct WildmindWhisperAnswer: Decodable, Sendable, Equatable, Hashable {
    var logId: Int?
    var when: String?
    var thought: String?
    var goal: String?
    var mood: String?

    init(logId: Int? = nil, when: String? = nil, thought: String? = nil, goal: String? = nil, mood: String? = nil) {
        self.logId = logId
        self.when = when
        self.thought = thought
        self.goal = goal
        self.mood = mood
    }

    private enum CodingKeys: String, CodingKey { case logId, when, thought, goal, mood }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        logId = c.wmInt(.logId)
        when = c.wmLabel(.when)
        thought = c.wmString(.thought).flatMap { $0.isEmpty ? nil : $0 }
        goal = c.wmString(.goal).flatMap { $0.isEmpty ? nil : $0 }
        mood = c.wmString(.mood).flatMap { $0.isEmpty ? nil : $0 }
    }
}

struct WildmindWhisper: Decodable, Sendable, Equatable, Hashable {
    var logId: Int
    var when: String?
    var text: String
    var status: WildmindWhisperStatus
    var answer: WildmindWhisperAnswer?

    init(logId: Int, when: String? = nil, text: String, status: WildmindWhisperStatus, answer: WildmindWhisperAnswer? = nil) {
        self.logId = logId
        self.when = when
        self.text = text
        self.status = status
        self.answer = answer
    }

    private enum CodingKeys: String, CodingKey { case logId, when, text, status, answer }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let logId = c.wmInt(.logId), let text = c.wmString(.text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no logId or text"))
        }
        self.logId = logId
        self.text = text
        when = c.wmLabel(.when)
        status = WildmindWhisperStatus(raw: c.wmString(.status))
        answer = try? c.decodeIfPresent(WildmindWhisperAnswer.self, forKey: .answer)
    }
}

/// `GET api/native/wildmind/whispers`: John's recent whispers, newest first.
struct WildmindWhispers: Decodable, Sendable, Equatable {
    var offline: Bool
    /// JKai's pending whispers now, oldest first (two at most).
    var pending: [String]
    /// What is left of today's whisper reserve, in dollars.
    var reserveLeftUsd: Double?
    /// A thought could call the model now, so a whisper would be heard soon.
    var modelAvailable: Bool
    var whispers: [WildmindWhisper]

    init(offline: Bool = false, pending: [String] = [], reserveLeftUsd: Double? = nil, modelAvailable: Bool = true,
         whispers: [WildmindWhisper] = []) {
        self.offline = offline
        self.pending = pending
        self.reserveLeftUsd = reserveLeftUsd
        self.modelAvailable = modelAvailable
        self.whispers = whispers
    }

    private enum CodingKeys: String, CodingKey { case state, pending, reserveLeftUsd, modelAvailable, whispers }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offline = WildmindLane.isOffline(c.wmString(.state))
        pending = c.wmList(.pending)
        reserveLeftUsd = c.wmNumber(.reserveLeftUsd)
        modelAvailable = c.wmBool(.modelAvailable) ?? false
        whispers = c.wmList(.whispers)
    }

    /// The whisper with this log id, if it is among the recent ones.
    func whisper(_ logId: Int) -> WildmindWhisper? {
        whispers.first { $0.logId == logId }
    }
}

/// The 202 for an accepted whisper.
struct WildmindWhisperAccepted: Decodable, Sendable, Equatable {
    var logId: Int
    var when: String?
    var pending: [String]
    /// The text this whisper pushed off JKai's list, if it pushed one.
    var dropped: String?
    var asleep: Bool
    var modelAvailable: Bool

    init(logId: Int, when: String? = nil, pending: [String] = [], dropped: String? = nil, asleep: Bool = false,
         modelAvailable: Bool = true) {
        self.logId = logId
        self.when = when
        self.pending = pending
        self.dropped = dropped
        self.asleep = asleep
        self.modelAvailable = modelAvailable
    }

    private enum CodingKeys: String, CodingKey { case ok, logId, when, pending, dropped, asleep, modelAvailable }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.wmBool(.ok) != false, let logId = c.wmInt(.logId) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not accepted"))
        }
        self.logId = logId
        when = c.wmLabel(.when)
        pending = c.wmList(.pending)
        dropped = c.wmString(.dropped).flatMap { $0.isEmpty ? nil : $0 }
        asleep = c.wmBool(.asleep) ?? false
        modelAvailable = c.wmBool(.modelAvailable) ?? false
    }
}

extension KeyedDecodingContainer {
    /// A clock label ("Day 24, 17:00"); a bare number is kept as its digits.
    func wmLabel(_ key: Key) -> String? {
        if let text = wmString(key) { return text.isEmpty ? nil : text }
        return wmInt(key).map(String.init)
    }
}

// MARK: - Talk's words

enum WildmindTalkWords {
    /// A diary as logged starts "Wren's diary, day 4: …"; the card says whose
    /// and which day already, so the body is what follows.
    static func diaryBody(_ text: String) -> String {
        guard let range = text.range(of: #"^[^:\n]{1,60}\bdiary, day -?\d+:\s*"#, options: [.regularExpression, .caseInsensitive]) else {
            return text
        }
        let rest = text[range.upperBound...]
        return rest.isEmpty ? text : String(rest)
    }

    /// The day a diary is for, from its "…, day 4:" opening.
    static func diaryDay(_ text: String) -> Int? {
        guard let range = text.range(of: #"\bday -?\d+:"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return Int(text[range].dropFirst(4).dropLast())
    }

    /// The valley day of an entry: from its minute, else from "Day 5, …".
    static func day(_ entry: WildmindTalkEntry) -> Int? {
        if let minute = entry.minute, minute >= 0 { return Int(minute / 1440) }
        return day(of: entry.when)
    }

    /// 5 from "Day 5, 15:30".
    static func day(of label: String?) -> Int? {
        guard let label, let range = label.range(of: #"^Day -?\d+"#, options: .regularExpression) else { return nil }
        return Int(label[range].dropFirst(4))
    }

    /// "15:30" from "Day 5, 15:30"; the label itself when it is not that shape.
    static func time(of label: String?) -> String? {
        guard let label else { return nil }
        if let comma = label.range(of: ", ") { return String(label[comma.upperBound...]) }
        return label
    }

    /// The mono line over a speech: "JKai → Wren · 15:12", or "JKai · 12:05"
    /// for a word said aloud to nobody.
    static func speechByline(_ entry: WildmindTalkEntry) -> String {
        let who = entry.name ?? (entry.who == "companion" ? "Wren" : "JKai")
        var line = who
        if let to = entry.toName ?? entry.to { line += " \u{2192} \(to)" }
        if let time = time(of: entry.when) { line += " \u{00B7} \(time)" }
        return line
    }
}
