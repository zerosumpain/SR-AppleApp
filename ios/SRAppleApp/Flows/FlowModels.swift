import Foundation

// MARK: - The wire, as the phone reads it
//
// `/api/native/workflows/*` (SR-Main, contract v1). Everything is decoded
// DEFENSIVELY: a workflow is an open-ended graph the site keeps growing new
// node types, field kinds and trigger kinds for, and a phone that refused a
// whole list because one step carried a kind it had not heard of would be the
// worst possible failure — the screen goes blank over one unknown word. So an
// unknown field kind reads as `json`, an unknown trigger kind as `other`, an
// id may arrive as a number or a string, and every array may be missing.

/// Any JSON value. A step's config is an open object the phone edits, and it
/// must go back to the server exactly as it came — `[String: Any]` does not
/// survive a round trip through Codable, and a typed struct per node type
/// would be a second copy of the site's node registry.
enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var string: String? { if case .string(let v) = self { return v }; return nil }
    var number: Double? { if case .number(let v) = self { return v }; return nil }
    var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    var array: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    var isNull: Bool { self == .null }

    subscript(key: String) -> JSONValue? { object?[key] }

    /// A short, human rendering — for a dropdown option's value or a chip.
    var display: String {
        switch self {
        case .string(let v): return v
        case .number(let v): return v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(v)
        case .bool(let v): return v ? "true" : "false"
        case .null: return ""
        case .object, .array: return pretty
        }
    }

    /// Indented JSON with sorted keys, for the code editor and raw view.
    var pretty: String {
        guard let data = try? Self.prettyEncoder.encode(self),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// Parse text the reader typed. `nil` means it is not JSON.
    static func parse(_ text: String) -> JSONValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

extension KeyedDecodingContainer {
    /// An id the server might send as a string or as a number.
    func flexString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(Int(value)) }
        return nil
    }

    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

/// Decodes each element on its own, dropping the ones that fail. One bad run
/// row must not take the other nine with it.
struct Lossy<Element: Decodable>: Decodable {
    let items: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !container.isAtEnd {
            if let item = try? container.decode(Element.self) {
                out.append(item)
            } else {
                _ = try? container.decode(JSONValue.self)
            }
        }
        items = out
    }
}

extension KeyedDecodingContainer {
    func lossy<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        ((try? decodeIfPresent(Lossy<T>.self, forKey: key)) ?? nil)?.items ?? []
    }
}

// MARK: - Triggers

enum FlowTriggerKind: Hashable {
    case manual, cron, webhook, event, whatsapp, gmail, chat
    case other(String)

    init(raw: String) {
        switch raw {
        case "manual": self = .manual
        case "cron": self = .cron
        case "webhook": self = .webhook
        case "event": self = .event
        case "whatsapp": self = .whatsapp
        case "gmail": self = .gmail
        case "chat": self = .chat
        default: self = .other(raw)
        }
    }

    var raw: String {
        switch self {
        case .manual: return "manual"
        case .cron: return "cron"
        case .webhook: return "webhook"
        case .event: return "event"
        case .whatsapp: return "whatsapp"
        case .gmail: return "gmail"
        case .chat: return "chat"
        case .other(let value): return value
        }
    }

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .cron: return "Schedule"
        case .webhook: return "Webhook"
        case .event: return "Event"
        case .whatsapp: return "WhatsApp"
        case .gmail: return "Gmail"
        case .chat: return "Chat"
        case .other(let value): return value.capitalized
        }
    }

    var icon: String {
        switch self {
        case .manual: return "hand.tap"
        case .cron: return "clock"
        case .webhook: return "link"
        case .event: return "bolt"
        case .whatsapp: return "phone.bubble"
        case .gmail: return "envelope"
        case .chat: return "bubble.left"
        case .other: return "questionmark.circle"
        }
    }
}

struct FlowTrigger: Decodable, Hashable {
    var kind: FlowTriggerKind
    var cron: String?
    var timezone: String?
    var enabled: Bool
    var description: String
    var nextRuns: [String]

    enum CodingKeys: String, CodingKey { case kind, cron, timezone, enabled, description, nextRuns }

    init(kind: FlowTriggerKind, cron: String? = nil, timezone: String? = nil, enabled: Bool = true,
         description: String = "", nextRuns: [String] = []) {
        self.kind = kind
        self.cron = cron
        self.timezone = timezone
        self.enabled = enabled
        self.description = description
        self.nextRuns = nextRuns
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = FlowTriggerKind(raw: c.lenient(String.self, .kind) ?? "manual")
        cron = c.lenient(String.self, .cron)
        timezone = c.lenient(String.self, .timezone)
        enabled = c.lenient(Bool.self, .enabled) ?? true
        description = c.lenient(String.self, .description) ?? ""
        nextRuns = c.lossy(String.self, .nextRuns)
    }

    static let manual = FlowTrigger(kind: .manual)
}

// MARK: - Runs

struct FlowRunSummary: Decodable, Hashable, Identifiable {
    let id: String
    let status: String
    let trigger: String?
    let startedAt: String?
    let completedAt: String?
    let durationMs: Double?
    let error: String?

    enum CodingKeys: String, CodingKey { case id, status, trigger, startedAt, completedAt, durationMs, error }

    init(id: String, status: String, trigger: String? = nil, startedAt: String? = nil,
         completedAt: String? = nil, durationMs: Double? = nil, error: String? = nil) {
        self.id = id
        self.status = status
        self.trigger = trigger
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMs = durationMs
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.flexString(.id) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "run without an id"))
        }
        self.id = id
        status = c.lenient(String.self, .status) ?? "unknown"
        trigger = c.lenient(String.self, .trigger)
        startedAt = c.lenient(String.self, .startedAt)
        completedAt = c.lenient(String.self, .completedAt)
        durationMs = c.lenient(Double.self, .durationMs)
        error = c.lenient(String.self, .error)
    }

    var state: FlowRunState { FlowRunState(status) }
}

/// A run's (or a step's) status, folded into the four things a reader acts on.
enum FlowRunState: Equatable {
    case running, succeeded, failed, waiting, other

    init(_ raw: String) {
        switch raw.lowercased() {
        case "running", "pending", "queued", "started", "in_progress": self = .running
        case "completed", "complete", "success", "succeeded", "done", "ok": self = .succeeded
        case "failed", "error", "errored", "cancelled", "canceled", "timeout", "timed_out": self = .failed
        case "paused", "waiting", "awaiting_approval", "approval": self = .waiting
        default: self = .other
        }
    }

    var isFinished: Bool { self != .running && self != .waiting }

    var icon: String {
        switch self {
        case .running: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .waiting: return "pause.circle.fill"
        case .other: return "circle.dotted"
        }
    }
}

/// "1.2s", "3m 04s" — a duration in the ledger's register.
func flowDuration(_ ms: Double?) -> String? {
    guard let ms, ms.isFinite, ms >= 0 else { return nil }
    if ms < 1000 { return "\(Int(ms))ms" }
    let seconds = ms / 1000
    if seconds < 60 { return String(format: "%.1fs", seconds) }
    let whole = Int(seconds)
    if whole < 3600 { return String(format: "%dm %02ds", whole / 60, whole % 60) }
    return String(format: "%dh %02dm", whole / 3600, (whole % 3600) / 60)
}

// MARK: - List

struct FlowSummary: Decodable, Hashable, Identifiable {
    let slug: String
    var title: String
    var description: String?
    var trigger: FlowTrigger
    var nodeCount: Int
    var lastRun: FlowRunSummary?
    var needsAttention: Bool
    var attentionReason: String?
    var updatedAt: String?

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, title, description, trigger, nodeCount, lastRun, needsAttention, attentionReason, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let slug = c.flexString(.slug) else {
            throw DecodingError.keyNotFound(CodingKeys.slug, .init(codingPath: c.codingPath, debugDescription: "workflow without a slug"))
        }
        self.slug = slug
        title = c.lenient(String.self, .title) ?? slug
        description = c.lenient(String.self, .description)
        trigger = c.lenient(FlowTrigger.self, .trigger) ?? .manual
        nodeCount = c.lenient(Int.self, .nodeCount) ?? 0
        lastRun = c.lenient(FlowRunSummary.self, .lastRun)
        needsAttention = c.lenient(Bool.self, .needsAttention) ?? false
        attentionReason = c.lenient(String.self, .attentionReason)
        updatedAt = c.lenient(String.self, .updatedAt)
    }
}

struct FlowList: Decodable {
    let workflows: [FlowSummary]

    enum CodingKeys: String, CodingKey { case workflows }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workflows = c.lossy(FlowSummary.self, .workflows)
    }
}

struct FlowCreated: Decodable {
    let slug: String
    let building: Bool

    enum CodingKeys: String, CodingKey { case slug, building }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = c.flexString(.slug) ?? ""
        building = c.lenient(Bool.self, .building) ?? false
    }
}

// MARK: - Forms

enum FlowFieldKind: String, Hashable, CaseIterable {
    case text, textarea, template, number, toggle, dropdown, code, json, phone, chips

    /// Unknown kinds fall back to raw JSON — the one editor that can hold any
    /// value without losing it.
    init(raw: String) { self = FlowFieldKind(rawValue: raw) ?? .json }
}

struct FlowFieldOption: Decodable, Hashable {
    let value: JSONValue
    let label: String

    enum CodingKeys: String, CodingKey { case value, label }

    init(value: JSONValue, label: String) {
        self.value = value
        self.label = label
    }

    init(from decoder: Decoder) throws {
        // An option may be a bare string as well as `{ value, label }`.
        if let single = try? decoder.singleValueContainer(), let raw = try? single.decode(String.self) {
            value = .string(raw)
            label = raw
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = c.lenient(JSONValue.self, .value) ?? .null
        label = c.lenient(String.self, .label) ?? value.display
    }
}

struct FlowField: Decodable, Hashable, Identifiable {
    let key: String
    let label: String
    let kind: FlowFieldKind
    let options: [FlowFieldOption]
    let min: Double?
    let max: Double?
    let step: Double?
    let placeholder: String?
    let help: String?
    let advanced: Bool
    let section: String?

    var id: String { key }

    enum CodingKeys: String, CodingKey { case key, label, kind, options, min, max, step, placeholder, help, advanced, section }

    init(key: String, label: String, kind: FlowFieldKind, options: [FlowFieldOption] = [], min: Double? = nil,
         max: Double? = nil, step: Double? = nil, placeholder: String? = nil, help: String? = nil,
         advanced: Bool = false, section: String? = nil) {
        self.key = key
        self.label = label
        self.kind = kind
        self.options = options
        self.min = min
        self.max = max
        self.step = step
        self.placeholder = placeholder
        self.help = help
        self.advanced = advanced
        self.section = section
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = c.lenient(String.self, .key) else {
            throw DecodingError.keyNotFound(CodingKeys.key, .init(codingPath: c.codingPath, debugDescription: "field without a key"))
        }
        self.key = key
        label = c.lenient(String.self, .label) ?? key
        kind = FlowFieldKind(raw: c.lenient(String.self, .kind) ?? "json")
        options = c.lossy(FlowFieldOption.self, .options)
        min = c.lenient(Double.self, .min)
        max = c.lenient(Double.self, .max)
        step = c.lenient(Double.self, .step)
        placeholder = c.lenient(String.self, .placeholder)
        help = c.lenient(String.self, .help)
        advanced = c.lenient(Bool.self, .advanced) ?? false
        section = c.lenient(String.self, .section)
    }
}

// MARK: - Detail

struct FlowNext: Decodable, Hashable {
    let handle: String?
    let targetId: String

    enum CodingKeys: String, CodingKey { case handle, targetId }

    init(handle: String?, targetId: String) {
        self.handle = handle
        self.targetId = targetId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let target = c.flexString(.targetId) else {
            throw DecodingError.keyNotFound(CodingKeys.targetId, .init(codingPath: c.codingPath, debugDescription: "edge without a target"))
        }
        targetId = target
        let raw = c.lenient(String.self, .handle)
        handle = raw?.isEmpty == true ? nil : raw
    }
}

struct FlowStep: Decodable, Hashable, Identifiable {
    let id: String
    var type: String
    var label: String
    var category: String
    var icon: String?
    var summary: String
    var config: [String: JSONValue]
    var form: [FlowField]
    var next: [FlowNext]
    var legacy: Bool

    enum CodingKeys: String, CodingKey { case id, type, label, category, icon, summary, config, form, next, legacy }

    init(id: String, type: String, label: String, category: String = "", icon: String? = nil, summary: String = "",
         config: [String: JSONValue] = [:], form: [FlowField] = [], next: [FlowNext] = [], legacy: Bool = false) {
        self.id = id
        self.type = type
        self.label = label
        self.category = category
        self.icon = icon
        self.summary = summary
        self.config = config
        self.form = form
        self.next = next
        self.legacy = legacy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.flexString(.id) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "step without an id"))
        }
        self.id = id
        type = c.lenient(String.self, .type) ?? "unknown"
        label = c.lenient(String.self, .label) ?? type
        category = c.lenient(String.self, .category) ?? ""
        icon = c.lenient(String.self, .icon)
        summary = c.lenient(String.self, .summary) ?? ""
        config = c.lenient([String: JSONValue].self, .config) ?? [:]
        form = c.lossy(FlowField.self, .form)
        next = c.lossy(FlowNext.self, .next)
        legacy = c.lenient(Bool.self, .legacy) ?? false
    }

    /// The site's icon names are Lucide; the phone wants SF Symbols. Mapped by
    /// category, which is stable, rather than by the icon string, which is not.
    var symbol: String {
        switch category.lowercased() {
        case "trigger", "triggers": return "bolt.circle"
        case "ai", "llm", "agent", "agents": return "sparkle"
        case "logic", "control", "flow", "control flow": return "arrow.triangle.branch"
        case "data", "transform", "transforms": return "tablecells"
        case "output", "outputs", "notify", "notification", "messaging", "communication": return "paperplane"
        case "integration", "integrations", "http", "web": return "globe"
        case "code", "script": return "chevron.left.forwardslash.chevron.right"
        case "home", "smart home": return "house"
        default: return "square.stack.3d.up"
        }
    }
}

struct FlowEdge: Decodable, Hashable, Identifiable {
    let id: String
    let source: String
    let target: String
    let sourceHandle: String?

    enum CodingKeys: String, CodingKey { case id, source, target, sourceHandle }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = c.flexString(.source) ?? ""
        target = c.flexString(.target) ?? ""
        id = c.flexString(.id) ?? "\(source)->\(target)"
        sourceHandle = c.lenient(String.self, .sourceHandle)
    }
}

struct FlowFixProposal: Decodable, Hashable, Identifiable {
    let id: String
    let nodeId: String
    let nodeLabel: String
    let description: String
    let createdAt: String?
    let runId: String?
    /// The config keys the fix would change. Optional on the wire.
    let changedKeys: [String]
    /// How many failing runs the same fix rescued. Optional on the wire.
    let occurrences: Int?

    enum CodingKeys: String, CodingKey { case id, nodeId, nodeLabel, description, createdAt, runId, changedKeys, occurrences }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.flexString(.id) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "proposal without an id"))
        }
        self.id = id
        nodeId = c.flexString(.nodeId) ?? ""
        nodeLabel = c.lenient(String.self, .nodeLabel) ?? "a step"
        description = c.lenient(String.self, .description) ?? ""
        createdAt = c.lenient(String.self, .createdAt)
        runId = c.flexString(.runId)
        changedKeys = c.lossy(String.self, .changedKeys)
        occurrences = c.lenient(Int.self, .occurrences)
    }
}

struct FlowDetail: Decodable {
    let slug: String
    var title: String
    var description: String?
    /// An OPAQUE hash of the graph, not a counter. Compared for equality and
    /// sent back as `expectedVersion`; never ordered or incremented.
    var version: Int?
    var trigger: FlowTrigger
    var building: Bool
    var buildError: String?
    var steps: [FlowStep]
    var edges: [FlowEdge]
    var recentRuns: [FlowRunSummary]
    var fixProposals: [FlowFixProposal]

    enum CodingKeys: String, CodingKey {
        case slug, title, description, version, trigger, building, buildError, steps, edges, recentRuns, fixProposals
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = c.flexString(.slug) ?? ""
        title = c.lenient(String.self, .title) ?? slug
        description = c.lenient(String.self, .description)
        version = c.lenient(Int.self, .version)
        trigger = c.lenient(FlowTrigger.self, .trigger) ?? .manual
        building = c.lenient(Bool.self, .building) ?? false
        buildError = c.lenient(String.self, .buildError)
        steps = c.lossy(FlowStep.self, .steps)
        edges = c.lossy(FlowEdge.self, .edges)
        recentRuns = c.lossy(FlowRunSummary.self, .recentRuns)
        fixProposals = c.lossy(FlowFixProposal.self, .fixProposals)
    }

    func step(_ id: String) -> FlowStep? { steps.first { $0.id == id } }
}

// MARK: - Catalogue

struct FlowNodeType: Decodable, Hashable, Identifiable {
    let type: String
    let label: String
    let description: String
    let icon: String?
    let defaultConfig: [String: JSONValue]
    let form: [FlowField]

    var id: String { type }

    enum CodingKeys: String, CodingKey { case type, label, description, icon, defaultConfig, form }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let type = c.lenient(String.self, .type) else {
            throw DecodingError.keyNotFound(CodingKeys.type, .init(codingPath: c.codingPath, debugDescription: "node type without a type"))
        }
        self.type = type
        label = c.lenient(String.self, .label) ?? type
        description = c.lenient(String.self, .description) ?? ""
        icon = c.lenient(String.self, .icon)
        defaultConfig = c.lenient([String: JSONValue].self, .defaultConfig) ?? [:]
        form = c.lossy(FlowField.self, .form)
    }
}

struct FlowNodeCategory: Decodable, Hashable, Identifiable {
    let id: String
    let label: String
    let types: [FlowNodeType]

    enum CodingKeys: String, CodingKey { case id, label, types }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexString(.id) ?? UUID().uuidString
        label = c.lenient(String.self, .label) ?? id
        types = c.lossy(FlowNodeType.self, .types)
    }
}

struct FlowCatalogue: Decodable {
    let categories: [FlowNodeCategory]

    enum CodingKeys: String, CodingKey { case categories }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = c.lossy(FlowNodeCategory.self, .categories)
    }
}

// MARK: - Amend, ask, run

struct FlowAmendOutcome: Decodable, Hashable {
    let op: String
    let summary: String

    enum CodingKeys: String, CodingKey { case op, summary }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        op = c.lenient(String.self, .op) ?? ""
        summary = c.lenient(String.self, .summary) ?? ""
    }
}

struct FlowAmendResult: Decodable {
    let version: Int?
    let outcomes: [FlowAmendOutcome]

    enum CodingKeys: String, CodingKey { case version, outcomes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.lenient(Int.self, .version)
        outcomes = c.lossy(FlowAmendOutcome.self, .outcomes)
    }
}

struct FlowAmendRequest: Encodable {
    let ops: [JSONValue]
    let expectedVersion: Int?
}

struct FlowProposal: Decodable {
    let summary: String
    let ops: [JSONValue]
    let warnings: [String]

    enum CodingKeys: String, CodingKey { case summary, ops, warnings }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = c.lenient(String.self, .summary) ?? ""
        ops = c.lenient([JSONValue].self, .ops) ?? []
        warnings = c.lossy(String.self, .warnings)
    }
}

struct FlowRunStarted: Decodable {
    let runId: String

    enum CodingKeys: String, CodingKey { case runId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runId = c.flexString(.runId) ?? ""
    }
}

struct FlowRunStep: Decodable, Hashable, Identifiable {
    let nodeId: String
    let label: String
    let type: String
    let status: String
    let startedAt: String?
    let durationMs: Double?
    let error: String?
    let output: String?
    let rows: Int?

    var id: String { nodeId + (startedAt ?? "") }
    var state: FlowRunState { FlowRunState(status) }

    enum CodingKeys: String, CodingKey { case nodeId, label, type, status, startedAt, durationMs, error, output, rows }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nodeId = c.flexString(.nodeId) ?? UUID().uuidString
        type = c.lenient(String.self, .type) ?? ""
        label = c.lenient(String.self, .label) ?? type
        status = c.lenient(String.self, .status) ?? "unknown"
        startedAt = c.lenient(String.self, .startedAt)
        durationMs = c.lenient(Double.self, .durationMs)
        error = c.lenient(String.self, .error)
        output = c.lenient(String.self, .output)
        rows = c.lenient(Int.self, .rows)
    }
}

struct FlowRunDetail: Decodable {
    let run: FlowRunSummary
    let steps: [FlowRunStep]

    enum CodingKeys: String, CodingKey { case run, steps }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        run = try c.decode(FlowRunSummary.self, forKey: .run)
        steps = c.lossy(FlowRunStep.self, .steps)
    }
}

struct FlowRunList: Decodable {
    let runs: [FlowRunSummary]

    enum CodingKeys: String, CodingKey { case runs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runs = c.lossy(FlowRunSummary.self, .runs)
    }
}

// MARK: - Navigation values

struct FlowRef: Hashable {
    let slug: String
    let title: String
}

struct FlowRunRef: Hashable {
    let runId: String
    let title: String
}

// MARK: - Amend ops, built and read back
//
// The ops are sent as JSON objects in exactly the shapes `amend.server.ts`
// takes. A proposal from `/ask` is sent back VERBATIM — the phone renders it,
// it never rebuilds it, so an op field the phone has not heard of survives.

enum FlowOps {
    /// The one field a step without a form carries: kind `json`, meaning
    /// "the whole config". It is edited as a single object and sent back
    /// whole, not as a patch of one key called `$config`.
    static let wholeConfigKey = "$config"

    /// A whole-config edit: every key of the new object, and the keys that
    /// went. `update_node` merges, so a key deleted in the editor must be
    /// named in `removeConfigKeys` or it would survive the save.
    static func replaceConfig(_ nodeId: String, from original: [String: JSONValue], to edited: [String: JSONValue], label: String?) -> JSONValue {
        let removed = original.keys.filter { edited[$0] == nil }.sorted()
        var op: [String: JSONValue] = ["op": .string("update_node"), "nodeId": .string(nodeId), "config": .object(edited)]
        if !removed.isEmpty { op["removeConfigKeys"] = .array(removed.map { .string($0) }) }
        if let label { op["label"] = .string(label) }
        return .object(op)
    }

    static func updateNode(_ nodeId: String, config: [String: JSONValue]?, removeKeys: [String], label: String?) -> JSONValue {
        var op: [String: JSONValue] = ["op": .string("update_node"), "nodeId": .string(nodeId)]
        if let config, !config.isEmpty { op["config"] = .object(config) }
        if !removeKeys.isEmpty { op["removeConfigKeys"] = .array(removeKeys.map { .string($0) }) }
        if let label { op["label"] = .string(label) }
        return .object(op)
    }

    static func removeNode(_ nodeId: String) -> JSONValue {
        .object(["op": .string("remove_node"), "nodeId": .string(nodeId)])
    }

    /// A new step after `after`. Spliced onto the line when there is one to
    /// splice into; otherwise added and wired, the second op pointing at the
    /// first by `#ref` because the row has no id until it exists.
    static func insertStep(after step: FlowStep, type: String, label: String, config: [String: JSONValue]) -> [JSONValue] {
        let body: [String: JSONValue] = [
            "type": .string(type),
            "label": .string(label),
            "config": .object(config),
        ]
        // The un-labelled successor first: splicing into a condition's `false`
        // arm when the reader meant "after this step" would surprise them.
        let successor = step.next.first(where: { $0.handle == nil }) ?? step.next.first
        if let successor {
            var op = body
            op["op"] = .string("insert_between")
            op["sourceNodeId"] = .string(step.id)
            op["targetNodeId"] = .string(successor.targetId)
            return [.object(op)]
        }
        var add = body
        add["op"] = .string("add_node")
        add["ref"] = .string("new")
        let edge: [String: JSONValue] = [
            "op": .string("add_edge"),
            "sourceNodeId": .string(step.id),
            "targetNodeId": .string("#new"),
        ]
        return [.object(add), .object(edge)]
    }

    /// A config edit as a PATCH: only what changed, and the keys that went.
    /// `update_node` merges, so sending the whole object would re-write every
    /// value the reader never touched — including ones another device changed.
    static func diff(from original: [String: JSONValue], to edited: [String: JSONValue]) -> (patch: [String: JSONValue], removed: [String]) {
        var patch: [String: JSONValue] = [:]
        for (key, value) in edited where original[key] != value {
            patch[key] = value
        }
        let removed = original.keys.filter { edited[$0] == nil }.sorted()
        return (patch, removed)
    }

    /// One op, in words. The proposal sheet is the only thing standing between
    /// a model's plan and the saved workflow, so it has to be readable.
    static func describe(_ op: JSONValue, steps: [FlowStep]) -> String {
        func name(_ id: JSONValue?) -> String {
            guard let raw = id?.string else { return "a step" }
            if raw.hasPrefix("#") { return "the new step" }
            if let step = steps.first(where: { $0.id == raw }) { return "“\(step.label)”" }
            return "a step"
        }
        let kind = op["op"]?.string ?? ""
        let label = op["label"]?.string
        let type = op["type"]?.string
        switch kind {
        case "add_node":
            return "Add a \(type ?? "new") step" + (label.map { " called “\($0)”" } ?? "")
        case "update_node":
            var parts: [String] = []
            if let label { parts.append("rename it “\(label)”") }
            if let keys = op["config"]?.object?.keys.sorted(), !keys.isEmpty {
                parts.append("change " + keys.joined(separator: ", "))
            }
            if let removed = op["removeConfigKeys"]?.array?.compactMap(\.string), !removed.isEmpty {
                parts.append("clear " + removed.joined(separator: ", "))
            }
            if let type { parts.append("make it a \(type) step") }
            let detail = parts.isEmpty ? "update it" : parts.joined(separator: "; ")
            return "Edit \(name(op["nodeId"])): \(detail)"
        case "remove_node":
            return "Delete \(name(op["nodeId"]))"
        case "add_edge":
            let handle = op["sourceHandle"]?.string.map { " (on “\($0)”)" } ?? ""
            return "Connect \(name(op["sourceNodeId"])) to \(name(op["targetNodeId"]))\(handle)"
        case "remove_edge":
            return "Remove a connection"
        case "insert_between":
            return "Insert a \(type ?? "new") step" + (label.map { " “\($0)”" } ?? "")
                + " between \(name(op["sourceNodeId"])) and \(name(op["targetNodeId"]))"
        default:
            return kind.isEmpty ? "An unrecognised change" : "“\(kind)” (the phone does not know this change)"
        }
    }
}

// MARK: - Schedules

/// The four schedules a phone wants to set, and everything else as raw cron.
///
/// Presets are recognised FROM the expression rather than stored beside it, so
/// a schedule set on the web in a preset's shape opens here as that preset.
enum CronPreset: Hashable {
    case hourly(minute: Int)
    case daily(hour: Int, minute: Int)
    case weekdays(hour: Int, minute: Int)
    /// `weekday` is cron's: 0 = Sunday … 6 = Saturday.
    case weekly(weekday: Int, hour: Int, minute: Int)
    case custom(String)

    enum Kind: String, CaseIterable, Identifiable {
        case hourly, daily, weekdays, weekly, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .hourly: return "Hourly"
            case .daily: return "Daily"
            case .weekdays: return "Weekdays"
            case .weekly: return "Weekly"
            case .custom: return "Custom"
            }
        }
    }

    var kind: Kind {
        switch self {
        case .hourly: return .hourly
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .weekly: return .weekly
        case .custom: return .custom
        }
    }

    var expression: String {
        switch self {
        case .hourly(let m): return "\(m) * * * *"
        case .daily(let h, let m): return "\(m) \(h) * * *"
        case .weekdays(let h, let m): return "\(m) \(h) * * 1-5"
        case .weekly(let d, let h, let m): return "\(m) \(h) * * \(d)"
        case .custom(let raw): return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var hour: Int {
        switch self {
        case .daily(let h, _), .weekdays(let h, _), .weekly(_, let h, _): return h
        default: return 9
        }
    }

    var minute: Int {
        switch self {
        case .hourly(let m), .daily(_, let m), .weekdays(_, let m), .weekly(_, _, let m): return m
        case .custom: return 0
        }
    }

    var weekday: Int {
        if case .weekly(let d, _, _) = self { return d }
        return 1
    }

    static func parse(_ raw: String) -> CronPreset {
        let fields = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count == 5,
              let minute = Int(fields[0]), (0...59).contains(minute),
              fields[2] == "*", fields[3] == "*" else { return .custom(raw) }
        if fields[1] == "*" {
            return fields[4] == "*" ? .hourly(minute: minute) : .custom(raw)
        }
        guard let hour = Int(fields[1]), (0...23).contains(hour) else { return .custom(raw) }
        switch fields[4] {
        case "*": return .daily(hour: hour, minute: minute)
        case "1-5", "MON-FRI", "mon-fri": return .weekdays(hour: hour, minute: minute)
        default:
            if let day = Int(fields[4]), (0...7).contains(day) {
                return .weekly(weekday: day % 7, hour: hour, minute: minute)
            }
            return .custom(raw)
        }
    }

    /// Switch preset, carrying the time across.
    func converted(to kind: Kind) -> CronPreset {
        switch kind {
        case .hourly: return .hourly(minute: minute)
        case .daily: return .daily(hour: hour, minute: minute)
        case .weekdays: return .weekdays(hour: hour, minute: minute)
        case .weekly: return .weekly(weekday: weekday, hour: hour, minute: minute)
        case .custom: return .custom(expression)
        }
    }

    /// A cron expression is five fields, each of a small alphabet. This is a
    /// sanity check before a round trip, not a validator — the server's
    /// parser is the one that decides.
    static func looksValid(_ raw: String) -> Bool {
        let fields = raw.split(whereSeparator: \.isWhitespace)
        guard fields.count == 5 else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789*/,-?LW#ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        return fields.allSatisfy { $0.unicodeScalars.allSatisfy(allowed.contains) }
    }

    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
}

// MARK: - Steps in reading order, branches grouped

/// One line of the steps list: a step at a depth, or the label over a branch.
struct FlowLayoutRow: Hashable, Identifiable {
    enum Kind: Hashable {
        case step(String)
        /// The label over one arm of a branch — the edge's handle.
        case branch(String)
        /// An arm that goes straight on to where the branches meet.
        case passthrough
    }

    let kind: Kind
    let depth: Int
    let id: String
}

/// Turns a graph into a list a thumb can scroll.
///
/// The site draws a canvas; a phone gets a column. The trick is where the
/// column bends: a step with more than one way out becomes a set of indented
/// groups, one per arm, each labelled by its handle ("true", "approved"…), and
/// a step more than one arm leads to (a merge) is held back and drawn once,
/// back at the outer depth, after every arm that reaches it. A step that is
/// unreachable from any root is still listed, at the end, rather than hidden.
enum FlowLayout {
    static func rows(for steps: [FlowStep]) -> [FlowLayoutRow] {
        var byId: [String: FlowStep] = [:]
        var order: [String: Int] = [:]
        for (index, step) in steps.enumerated() where byId[step.id] == nil {
            byId[step.id] = step
            order[step.id] = index
        }
        var predecessors: [String: [String]] = [:]
        for step in steps {
            for next in step.next where byId[next.targetId] != nil && next.targetId != step.id {
                predecessors[next.targetId, default: []].append(step.id)
            }
        }
        func inDegree(_ id: String) -> Int { Set(predecessors[id] ?? []).count }

        var visited = Set<String>()
        var rows: [FlowLayoutRow] = []
        var counter = 0
        func emit(_ kind: FlowLayoutRow.Kind, _ depth: Int) {
            counter += 1
            let key: String
            switch kind {
            case .step(let id): key = "step-\(id)"
            case .branch(let label): key = "branch-\(counter)-\(label)"
            case .passthrough: key = "pass-\(counter)"
            }
            rows.append(FlowLayoutRow(kind: kind, depth: depth, id: key))
        }
        func ready(_ id: String) -> Bool { (predecessors[id] ?? []).allSatisfy(visited.contains) }
        func sorted(_ ids: [String]) -> [String] {
            var seen = Set<String>()
            return ids.filter { seen.insert($0).inserted }.sorted { (order[$0] ?? 0) < (order[$1] ?? 0) }
        }

        /// Walk a line from `start` at `depth`. Returns the merges it could
        /// not yet draw, for the caller to place.
        func walk(_ start: String, depth: Int) -> [String] {
            var current: String? = start
            var deferred: [String] = []
            while let id = current, !visited.contains(id), let step = byId[id] {
                visited.insert(id)
                emit(.step(id), depth)
                current = nil
                let outs = step.next.filter { byId[$0.targetId] != nil && $0.targetId != id }
                if outs.isEmpty { break }
                if outs.count == 1 {
                    let target = outs[0].targetId
                    if visited.contains(target) { break }
                    // A merge is never drawn from inside one of the lines
                    // that meets there — the caller places it once, after
                    // all of them, at the depth they branched from.
                    if inDegree(target) > 1 {
                        deferred.append(target)
                        break
                    }
                    current = target
                    continue
                }
                // A branch point: one indented group per arm.
                var merges: [String] = []
                for out in outs {
                    emit(.branch(out.handle ?? "then"), depth + 1)
                    let target = out.targetId
                    if visited.contains(target) || inDegree(target) > 1 {
                        emit(.passthrough, depth + 1)
                        merges.append(target)
                        continue
                    }
                    merges += walk(target, depth: depth + 1)
                }
                // Back at this depth: draw the merges every arm has reached.
                for merge in sorted(merges) where !visited.contains(merge) {
                    if ready(merge) {
                        deferred += walk(merge, depth: depth)
                    } else {
                        deferred.append(merge)
                    }
                }
            }
            return deferred
        }

        let roots = steps.filter { inDegree($0.id) == 0 }.map(\.id)
        var pending: [String] = []
        for root in sorted(roots.isEmpty ? steps.prefix(1).map(\.id) : roots) {
            pending += walk(root, depth: 0)
        }
        // Merges nobody could place (a cycle, or an arm from an unreached
        // step): drawn at the top level, in the server's order.
        while let next = sorted(pending).first(where: { !visited.contains($0) }) {
            pending.removeAll { $0 == next }
            pending += walk(next, depth: 0)
        }
        for step in steps where !visited.contains(step.id) {
            _ = walk(step.id, depth: 0)
        }
        return rows
    }

    /// Every step upstream of `id` — what a template field can refer to.
    static func upstream(of id: String, in steps: [FlowStep]) -> [FlowStep] {
        var parents: [String: [String]] = [:]
        for step in steps {
            for next in step.next { parents[next.targetId, default: []].append(step.id) }
        }
        var seen = Set<String>()
        var stack = parents[id] ?? []
        while let top = stack.popLast() {
            guard seen.insert(top).inserted else { continue }
            stack += parents[top] ?? []
        }
        return steps.filter { seen.contains($0.id) && $0.id != id }
    }
}
