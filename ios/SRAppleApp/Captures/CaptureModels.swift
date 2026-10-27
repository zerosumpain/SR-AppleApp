import Foundation

// Captures on the wire: what SR-Main's `/api/native/captures` routes send and
// take. The binding description is the captures CONTRACT.md (phone ⇄ SR-Main
// ⇄ SR-Jkai-Core), mirrored by SR-Main `$lib/captures/types.ts`.
//
// Every decoder here is LENIENT: a missing or mistyped field takes its
// default rather than throwing. Swift's synthesised `Codable` throws
// `keyNotFound` on any absent key, whatever the property's default — and a
// list that throws on one odd row shows the owner nothing at all.
//
// Foundation only, so the same file compiles in the Linux check
// (`scripts/captures-check.sh`) where there is no Mac to build the app on.

extension KeyedDecodingContainer {
    /// The value at `key`, or `fallback` when it is absent, null or the
    /// wrong type.
    func capValue<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }

    /// The value at `key`, or nil when it is absent, null or the wrong type.
    func capOptional<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// A number the server may send as an integer, a float or a numeric
    /// string (Postgres `numeric` arrives as a string through some drivers).
    func capNumber(_ key: Key) -> Double? {
        if let value = capOptional(key) as Double? { return value }
        if let text = capOptional(key) as String?, let value = Double(text) { return value }
        return nil
    }

    /// A list whose unreadable rows are dropped one by one, not wholesale.
    func capList<T: Decodable>(_ key: Key) -> [T] {
        guard var list = try? nestedUnkeyedContainer(forKey: key) else { return [] }
        var out: [T] = []
        while !list.isAtEnd {
            if let item = try? list.decode(T.self) {
                out.append(item)
            } else if (try? list.decode(CapSkip.self)) == nil {
                break
            }
        }
        return out
    }
}

/// Swallows one element of any shape, so `capList` can step past a bad row.
private struct CapSkip: Decodable {
    init(from decoder: Decoder) throws {}
}

// MARK: - Pieces of a capture

/// One diarized turn: who spoke, from when to when (seconds into the
/// recording), and what they said. Made on the phone and sent up as is.
struct CaptureTurn: Codable, Equatable, Hashable {
    var speaker: String
    var start: Double
    var end: Double
    var text: String

    init(speaker: String, start: Double, end: Double, text: String) {
        self.speaker = speaker; self.start = start; self.end = end; self.text = text
    }

    private enum CodingKeys: String, CodingKey { case speaker, start, end, text }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speaker = c.capValue(.speaker, "S1")
        start = c.capNumber(.start) ?? 0
        end = c.capNumber(.end) ?? 0
        text = c.capValue(.text, "")
    }
}

/// A name for a speaker, with the graph entity it is, when known.
struct CaptureSpeakerName: Codable, Equatable, Hashable {
    var name: String
    var entityId: String?

    init(name: String, entityId: String? = nil) { self.name = name; self.entityId = entityId }

    private enum CodingKeys: String, CodingKey { case name, entityId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.capValue(.name, "")
        entityId = c.capOptional(.entityId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(entityId, forKey: .entityId)
    }
}

/// The server's scored guess at who a speaker is — never stated as fact.
struct CaptureSpeakerGuess: Decodable, Equatable, Hashable {
    var name: String
    var entityId: String?
    /// 0…1, clamped on the way in.
    var confidence: Double
    var evidence: [String]

    init(name: String, entityId: String? = nil, confidence: Double, evidence: [String] = []) {
        self.name = name; self.entityId = entityId
        self.confidence = min(max(confidence, 0), 1); self.evidence = evidence
    }

    private enum CodingKeys: String, CodingKey { case name, entityId, confidence, evidence }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.capValue(.name, "")
        entityId = c.capOptional(.entityId)
        confidence = min(max(c.capNumber(.confidence) ?? 0, 0), 1)
        evidence = c.capList(.evidence)
    }
}

struct CaptureSpeaker: Decodable, Equatable, Hashable, Identifiable {
    var label: String
    var guess: CaptureSpeakerGuess?
    var confirmed: CaptureSpeakerName?
    var isOwner: Bool

    var id: String { label }

    init(label: String, guess: CaptureSpeakerGuess? = nil, confirmed: CaptureSpeakerName? = nil, isOwner: Bool = false) {
        self.label = label; self.guess = guess; self.confirmed = confirmed; self.isOwner = isOwner
    }

    private enum CodingKeys: String, CodingKey { case label, guess, confirmed, isOwner }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = c.capValue(.label, "S1")
        guess = c.capOptional(.guess)
        confirmed = c.capOptional(.confirmed)
        isOwner = c.capValue(.isOwner, false)
    }

    /// What to call this speaker on screen: the confirmed name, "You", the
    /// guess with a question mark, or the bare label.
    var displayName: String {
        if let confirmed, !confirmed.name.isEmpty { return confirmed.name }
        if isOwner { return "You" }
        if let guess, !guess.name.isEmpty { return "\(guess.name)?" }
        return "Speaker \(label.drop(while: { !$0.isNumber }))".trimmingCharacters(in: .whitespaces)
    }
}

/// What was on screen at the press, as the server read it.
struct CaptureScreen: Decodable, Equatable {
    struct App: Decodable, Equatable {
        var name: String
        var confidence: Double

        private enum CodingKeys: String, CodingKey { case name, confidence }

        init(name: String, confidence: Double) { self.name = name; self.confidence = confidence }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = c.capValue(.name, "")
            confidence = min(max(c.capNumber(.confidence) ?? 0, 0), 1)
        }
    }

    var app: App?
    var summary: String
    var ocrText: String
    var corrected: String?
    var denied: Bool

    private enum CodingKeys: String, CodingKey { case app, summary, ocrText, corrected, denied }

    init(app: App? = nil, summary: String = "", ocrText: String = "", corrected: String? = nil, denied: Bool = false) {
        self.app = app; self.summary = summary; self.ocrText = ocrText; self.corrected = corrected; self.denied = denied
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = c.capOptional(.app)
        summary = c.capValue(.summary, "")
        ocrText = c.capValue(.ocrText, "")
        corrected = c.capOptional(.corrected)
        denied = c.capValue(.denied, false)
    }

    /// The app's name as the owner should see it: a correction wins.
    var appName: String? {
        if let corrected, !corrected.isEmpty { return corrected }
        if let app, !app.name.isEmpty { return app.name }
        return nil
    }
}

struct CapturePlace: Codable, Equatable {
    var lat: Double
    var lon: Double
    var name: String?

    init(lat: Double, lon: Double, name: String? = nil) { self.lat = lat; self.lon = lon; self.name = name }

    private enum CodingKeys: String, CodingKey { case lat, lon, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lat = c.capNumber(.lat) ?? 0
        lon = c.capNumber(.lon) ?? 0
        name = c.capOptional(.name)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lat, forKey: .lat)
        try c.encode(lon, forKey: .lon)
        try c.encodeIfPresent(name, forKey: .name)
    }
}

/// One stretch of the conversation: a topic and who was in it. Snake-case
/// keys, as the row's jsonb holds them (`from_s`, `to_s`).
struct CaptureFlowItem: Decodable, Equatable, Hashable {
    var topic: String
    var fromS: Double
    var toS: Double
    var speakers: [String]

    private enum CodingKeys: String, CodingKey {
        case topic, speakers
        case fromS = "from_s"
        case toS = "to_s"
    }

    init(topic: String, fromS: Double, toS: Double, speakers: [String]) {
        self.topic = topic; self.fromS = fromS; self.toS = toS; self.speakers = speakers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        topic = c.capValue(.topic, "")
        fromS = c.capNumber(.fromS) ?? 0
        toS = c.capNumber(.toS) ?? 0
        speakers = c.capList(.speakers)
    }
}

/// Somebody or something the capture mentioned.
struct CaptureMention: Decodable, Equatable, Hashable {
    var name: String
    /// person | place | org | object | event | topic. Kept as text: a type
    /// the phone has not heard of still shows, with a plain icon.
    var type: String
    var mention: String

    private enum CodingKeys: String, CodingKey { case name, type, mention }

    init(name: String, type: String, mention: String = "") { self.name = name; self.type = type; self.mention = mention }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.capValue(.name, "")
        type = c.capValue(.type, "topic")
        mention = c.capValue(.mention, "")
    }
}

// MARK: - Follow-ups

enum CaptureActionKind: String, CaseIterable {
    case todoMe = "todo_me"
    case todoOther = "todo_other"
    case research
    case calendar
    case followup
    case remember

    /// Who acts, in the owner's words.
    var label: String {
        switch self {
        case .todoMe: return "For you"
        case .todoOther: return "For someone else"
        case .research: return "Research"
        case .calendar: return "Calendar"
        case .followup: return "Follow up"
        case .remember: return "Remember"
        }
    }

    var symbol: String {
        switch self {
        case .todoMe: return "checkmark.circle"
        case .todoOther: return "person.crop.circle.badge.checkmark"
        case .research: return "magnifyingglass"
        case .calendar: return "calendar.badge.plus"
        case .followup: return "clock.arrow.circlepath"
        case .remember: return "brain"
        }
    }

    /// What approving does, said before the tap.
    var approveLine: String {
        switch self {
        case .todoMe: return "Approve to add it as a reminder."
        case .todoOther: return "Approve to keep a message draft. Nothing is sent."
        case .research: return "Approve to start a research run."
        case .calendar: return "Approve to put it in your calendar."
        case .followup: return "Approve to have jkai follow up then."
        case .remember: return "Approve to save it to your graph."
        }
    }
}

enum CaptureActionState: String {
    case proposed, approved, dismissed, done, failed, refused

    /// Still waiting for the owner.
    var open: Bool { self == .proposed }

    var label: String {
        switch self {
        case .proposed: return "Proposed"
        case .approved: return "Running"
        case .dismissed: return "Dismissed"
        case .done: return "Done"
        case .failed: return "Failed"
        case .refused: return "Refused"
        }
    }
}

struct CaptureAction: Decodable, Equatable, Identifiable {
    var id: String
    var captureId: String
    /// The raw kind. `kindValue` is nil for one this phone does not know,
    /// which is then shown but cannot be approved.
    var kind: String
    var title: String
    var detail: String?
    var who: String?
    var dueAt: String?
    /// Kind-dependent, kept as flat text for display and editing.
    var params: [String: String]
    var state: String
    var refKind: String?
    var refId: String?
    var error: String?
    var createdAt: String?
    var decidedAt: String?

    var kindValue: CaptureActionKind? { CaptureActionKind(rawValue: kind) }
    var stateValue: CaptureActionState { CaptureActionState(rawValue: state) ?? .proposed }

    private enum CodingKeys: String, CodingKey {
        case id, captureId, kind, title, detail, who, dueAt, params, state, refKind, refId, error, createdAt, decidedAt
    }

    init(id: String, captureId: String, kind: String, title: String, detail: String? = nil, who: String? = nil,
         dueAt: String? = nil, params: [String: String] = [:], state: String = "proposed", refKind: String? = nil,
         refId: String? = nil, error: String? = nil, createdAt: String? = nil, decidedAt: String? = nil) {
        self.id = id; self.captureId = captureId; self.kind = kind; self.title = title; self.detail = detail
        self.who = who; self.dueAt = dueAt; self.params = params; self.state = state; self.refKind = refKind
        self.refId = refId; self.error = error; self.createdAt = createdAt; self.decidedAt = decidedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.capValue(.id, "")
        captureId = c.capValue(.captureId, "")
        kind = c.capValue(.kind, "")
        title = c.capValue(.title, "")
        detail = c.capOptional(.detail)
        who = c.capOptional(.who)
        dueAt = c.capOptional(.dueAt)
        params = (c.capOptional(.params) as CaptureFlatParams?)?.values ?? [:]
        state = c.capValue(.state, "proposed")
        refKind = c.capOptional(.refKind)
        refId = c.capOptional(.refId)
        error = c.capOptional(.error)
        createdAt = c.capOptional(.createdAt)
        decidedAt = c.capOptional(.decidedAt)
    }
}

/// A params object read as text: strings stay strings, numbers and booleans
/// are printed, lists of strings are joined with ", ". Nested objects are
/// dropped — no kind in the closed list has one.
struct CaptureFlatParams: Decodable, Equatable {
    var values: [String: String]

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        var out: [String: String] = [:]
        for key in c.allKeys {
            if let text = try? c.decode(String.self, forKey: key) {
                out[key.stringValue] = text
            } else if let flag = try? c.decode(Bool.self, forKey: key) {
                out[key.stringValue] = flag ? "true" : "false"
            } else if let number = try? c.decode(Double.self, forKey: key) {
                out[key.stringValue] = number == number.rounded() && abs(number) < 1e15
                    ? String(Int(number)) : String(number)
            } else if let list = try? c.decode([String].self, forKey: key) {
                out[key.stringValue] = list.joined(separator: ", ")
            }
        }
        values = out
    }
}

/// `POST /api/native/captures/:id/actions/:actionId`.
struct CaptureDecision: Encodable {
    var decision: String
    var params: [String: CaptureParamValue]?

    static func approve(params: [String: CaptureParamValue]? = nil) -> CaptureDecision {
        CaptureDecision(decision: "approve", params: params)
    }
    static let dismiss = CaptureDecision(decision: "dismiss", params: nil)
}

/// A param the owner edited before approving: text, or a list (attendees).
enum CaptureParamValue: Encodable, Equatable {
    case text(String)
    case list([String])

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let value): try c.encode(value)
        case .list(let value): try c.encode(value)
        }
    }

    /// Back to the server's shape: `attendees` is a list, the rest text.
    static func from(_ flat: [String: String]) -> [String: CaptureParamValue] {
        var out: [String: CaptureParamValue] = [:]
        for (key, value) in flat {
            if key == "attendees" {
                out[key] = .list(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            } else {
                out[key] = .text(value)
            }
        }
        return out
    }
}

// MARK: - A capture

enum CaptureStatus: String {
    case received, analysing, ready, failed

    var label: String {
        switch self {
        case .received: return "Received"
        case .analysing: return "Reading it"
        case .ready: return "Ready"
        case .failed: return "Failed"
        }
    }
}

/// A row in the list, and a search hit (which adds `score` and `snippet`).
struct CaptureSummary: Decodable, Equatable, Identifiable, Hashable {
    var id: String
    var title: String
    var startedAt: String
    var durationS: Double?
    var status: String
    var app: String?
    var speakers: [String]
    var actionsOpen: Int
    var snippet: String
    var score: Double?

    var statusValue: CaptureStatus { CaptureStatus(rawValue: status) ?? .received }
    var started: Date? { CaptureClock.parse(startedAt) }

    private enum CodingKeys: String, CodingKey { case id, title, startedAt, durationS, status, app, speakers, actionsOpen, snippet, score }

    init(id: String, title: String, startedAt: String, durationS: Double?, status: String, app: String? = nil,
         speakers: [String] = [], actionsOpen: Int = 0, snippet: String = "", score: Double? = nil) {
        self.id = id; self.title = title; self.startedAt = startedAt; self.durationS = durationS; self.status = status
        self.app = app; self.speakers = speakers; self.actionsOpen = actionsOpen; self.snippet = snippet; self.score = score
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = c.capValue(.title, "")
        startedAt = c.capValue(.startedAt, "")
        durationS = c.capNumber(.durationS)
        status = c.capValue(.status, "received")
        app = c.capOptional(.app)
        speakers = c.capList(.speakers)
        actionsOpen = Int(c.capNumber(.actionsOpen) ?? 0)
        snippet = c.capValue(.snippet, "")
        score = c.capNumber(.score)
    }
}

struct CapturePage: Decodable, Equatable {
    var items: [CaptureSummary]
    var next: String?

    private enum CodingKeys: String, CodingKey { case items, next }

    init(items: [CaptureSummary], next: String? = nil) { self.items = items; self.next = next }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.capList(.items)
        next = c.capOptional(.next)
    }
}

/// `GET /api/native/captures/:id`: the full row, its follow-ups, and where
/// the media are.
struct Capture: Decodable, Equatable, Identifiable {
    var id: String
    var startedAt: String
    var endedAt: String?
    var durationS: Double?
    var transcript: String
    var transcriptSource: String
    var turns: [CaptureTurn]
    var speakers: [CaptureSpeaker]
    var screen: CaptureScreen?
    var place: CapturePlace?
    var title: String?
    var summary: String?
    var flow: [CaptureFlowItem]
    var entities: [CaptureMention]
    var status: String
    var error: String?
    var analysisCostUsd: Double?
    var audioUrl: String?
    var screenUrl: String?
    var actions: [CaptureAction]

    var statusValue: CaptureStatus { CaptureStatus(rawValue: status) ?? .received }
    var started: Date? { CaptureClock.parse(startedAt) }

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, durationS, transcript, transcriptSource, turns, speakers, screen, place, title,
             summary, flow, entities, status, error, analysisCostUsd, audioUrl, screenUrl, actions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        startedAt = c.capValue(.startedAt, "")
        endedAt = c.capOptional(.endedAt)
        durationS = c.capNumber(.durationS)
        transcript = c.capValue(.transcript, "")
        transcriptSource = c.capValue(.transcriptSource, "phone")
        turns = c.capList(.turns)
        speakers = c.capList(.speakers)
        screen = c.capOptional(.screen)
        place = c.capOptional(.place)
        title = c.capOptional(.title)
        summary = c.capOptional(.summary)
        flow = c.capList(.flow)
        entities = c.capList(.entities)
        status = c.capValue(.status, "received")
        error = c.capOptional(.error)
        analysisCostUsd = c.capNumber(.analysisCostUsd)
        audioUrl = c.capOptional(.audioUrl)
        screenUrl = c.capOptional(.screenUrl)
        actions = c.capList(.actions)
    }

    func speaker(_ label: String) -> CaptureSpeaker? { speakers.first { $0.label == label } }

    /// The turns, or — when the phone sent none — the whole transcript as
    /// one speaker's.
    var shownTurns: [CaptureTurn] {
        if !turns.isEmpty { return turns }
        guard !transcript.isEmpty else { return [] }
        return [CaptureTurn(speaker: speakers.first?.label ?? "S1", start: 0, end: durationS ?? 0, text: transcript)]
    }

    var openActions: Int { actions.filter { $0.stateValue.open }.count }
}

// MARK: - Search and the graph

struct CaptureEntityHit: Decodable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var type: String
    var captureCount: Int

    private enum CodingKeys: String, CodingKey { case id, name, type, captureCount }

    init(id: String, name: String, type: String, captureCount: Int) {
        self.id = id; self.name = name; self.type = type; self.captureCount = captureCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.capValue(.name, "")
        type = c.capValue(.type, "topic")
        captureCount = Int(c.capNumber(.captureCount) ?? 0)
    }
}

/// `GET /api/native/captures/search`.
struct CaptureSearchResult: Decodable, Equatable {
    var captures: [CaptureSummary]
    var entities: [CaptureEntityHit]

    private enum CodingKeys: String, CodingKey { case captures, entities }

    init(captures: [CaptureSummary] = [], entities: [CaptureEntityHit] = []) {
        self.captures = captures; self.entities = entities
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        captures = c.capList(.captures)
        entities = c.capList(.entities)
    }
}

/// `GET /api/native/captures/entities/:entityId`.
struct CaptureEntityPage: Decodable, Equatable {
    struct Entity: Decodable, Equatable {
        var id: String
        var name: String
        var type: String
        var summary: String?

        private enum CodingKeys: String, CodingKey { case id, name, type, summary }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.capValue(.id, "")
            name = c.capValue(.name, "")
            type = c.capValue(.type, "topic")
            summary = c.capOptional(.summary)
        }
    }

    struct Neighbour: Decodable, Equatable, Identifiable, Hashable {
        var id: String
        var name: String
        var type: String
        var relation: String

        private enum CodingKeys: String, CodingKey { case id, name, type, relation }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = c.capValue(.name, "")
            type = c.capValue(.type, "topic")
            relation = c.capValue(.relation, "")
        }
    }

    var entity: Entity
    var captures: [CaptureSummary]
    var neighbours: [Neighbour]

    private enum CodingKeys: String, CodingKey { case entity, captures, neighbours }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entity = try c.decode(Entity.self, forKey: .entity)
        captures = c.capList(.captures)
        neighbours = c.capList(.neighbours)
    }
}

/// The SF Symbol for an entity type.
enum CaptureEntityKind {
    static func symbol(_ type: String) -> String {
        switch type {
        case "person": return "person.fill"
        case "place": return "mappin.and.ellipse"
        case "org": return "building.2.fill"
        case "object": return "cube.fill"
        case "event": return "calendar"
        default: return "number"
        }
    }
}

// MARK: - Uploading one

/// `POST /api/native/captures`: the metadata, sent before the audio. The
/// transcript travels here as JSON, never in a URL.
struct CaptureCreateRequest: Encodable, Equatable {
    struct Screen: Encodable, Equatable {
        var ocrText: String
        var appHint: String?
        var denied: Bool
    }

    var startedAt: String
    var endedAt: String
    var transcript: String
    var turns: [CaptureTurn]
    var speakerCount: Int
    var ownerSpeaker: String?
    var screen: Screen?
    var place: CapturePlace?
    var audio: Bool
    var screenshot: Bool
    var source: String
}

/// `201 {id, uploadAudio, uploadScreen?}`.
struct CaptureCreated: Decodable, Equatable {
    var id: String
    var uploadAudio: String?
    var uploadScreen: String?

    private enum CodingKeys: String, CodingKey { case id, uploadAudio, uploadScreen }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        uploadAudio = c.capOptional(.uploadAudio)
        uploadScreen = c.capOptional(.uploadScreen)
    }
}

/// `PATCH /api/native/captures/:id`.
struct CapturePatch: Encodable, Equatable {
    struct SpeakerConfirmation: Encodable, Equatable {
        var label: String
        var confirmed: CaptureSpeakerName
    }

    var title: String?
    var speakers: [SpeakerConfirmation]?
    var screenApp: String?
}

/// Paths under `/api/native/captures`, in one place. Ids are escaped once.
enum CapturePaths {
    static let root = "api/native/captures"

    static func escape(_ id: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    }

    static func capture(_ id: String) -> String { "\(root)/\(escape(id))" }
    static func audio(_ id: String) -> String { "\(capture(id))/audio" }
    static func screen(_ id: String) -> String { "\(capture(id))/screen" }
    static func action(_ id: String, _ actionId: String) -> String { "\(capture(id))/actions/\(escape(actionId))" }
    static func entity(_ id: String) -> String { "\(root)/entities/\(escape(id))" }

    static func list(before: String? = nil, limit: Int = 30) -> String {
        var query = ["limit=\(limit)"]
        if let before { query.append("before=\(queryValue(before))") }
        return "\(root)?\(query.joined(separator: "&"))"
    }

    /// The search route, with only the filters that are set.
    static func search(_ filters: CaptureSearchFilters) -> String {
        var query: [String] = []
        func add(_ name: String, _ value: String?) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
            query.append("\(name)=\(queryValue(value))")
        }
        add("q", filters.q)
        add("person", filters.person)
        add("app", filters.app)
        add("place", filters.place)
        add("from", filters.from)
        add("to", filters.to)
        query.append("limit=\(filters.limit)")
        return "\(root)/search?\(query.joined(separator: "&"))"
    }

    /// RFC 3986 unreserved; everything else in a query value is escaped.
    static func queryValue(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

struct CaptureSearchFilters: Equatable {
    var q: String = ""
    var person: String?
    var app: String?
    var place: String?
    /// ISO dates.
    var from: String?
    var to: String?
    var limit: Int = 30

    var isEmpty: Bool {
        q.trimmingCharacters(in: .whitespaces).isEmpty && person == nil && app == nil && place == nil && from == nil && to == nil
    }
}

/// ISO-8601 with or without fractional seconds.
enum CaptureClock {
    static func iso(_ date: Date) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.string(from: date)
    }

    static func parse(_ text: String) -> Date? {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = format.date(from: text) { return date }
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: text)
    }

    /// "4:07" or "1:02:09".
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}


/// Where a capture link leads: `sr://captures` (the page) or
/// `sr://captures/<id>` (one capture) — the Live Activity's tap, and the
/// "Capture ready" push.
struct CaptureLink: Equatable {
    var captureId: String?

    static func from(url: URL) -> CaptureLink? {
        guard url.scheme?.lowercased() == "sr", url.host?.lowercased() == "captures" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        return CaptureLink(captureId: parts.first)
    }

    /// A notification's `url`, when it is a capture's.
    static func from(userInfo: [AnyHashable: Any]) -> CaptureLink? {
        guard let text = userInfo["url"] as? String, let url = URL(string: text) else { return nil }
        return from(url: url)
    }
}
