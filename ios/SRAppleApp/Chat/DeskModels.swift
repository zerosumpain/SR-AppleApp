import Foundation

// MARK: - The desk page
//
// The site's /jkai chat is a column beside a "desk": a right-hand panel that
// shows each answer's evidence as a PAGE of blocks. The page belongs to one
// assistant message and arrives on it as `panel` (SR-Main's
// `GET /api/native/chat/conversations/{id}/messages`). The shape is SR-Main's
// `$lib/jkai/panel/schema.ts`, the zod file the desk itself draws with; this is
// that file read by a phone.
//
// EVERYTHING DECODES TOLERANTLY. Swift's synthesised `Decodable` throws on a
// missing key even where the property has a default, and a throw inside a
// message's `panel` would throw the whole message page — the transcript would
// go blank because one block on the desk was a shape this build had not met.
// So: every field is `decodeIfPresent` with a default, every array is lossy (a
// bad element is skipped, not fatal), an unknown block type decodes as
// `.unknown` and is dropped by its section, and a `panel` that is not an object
// at all decodes as an empty page, which the drawer treats as no page.
//
// Foundation only, on purpose: this file has no SwiftUI in it, so it compiles
// (and its decoder can be exercised) on a Linux Swift toolchain.

struct PanelPage: Decodable, Hashable {
    var version: Int = 1
    /// `model`, `turn`, `context`, `thread` or `today`.
    var producer: String = "turn"
    var head: PanelHead = PanelHead()
    var sections: [PanelSection] = []
    /// The turn made nothing; the desk holds the previous page.
    var quiet: Bool = false

    init(version: Int = 1, producer: String = "turn", head: PanelHead = PanelHead(), sections: [PanelSection] = [], quiet: Bool = false) {
        self.version = version
        self.producer = producer
        self.head = head
        self.sections = sections
        self.quiet = quiet
    }

    private enum Keys: String, CodingKey { case version, producer, head, sections, quiet }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: Keys.self) else { return }
        version = c.desk_int(.version) ?? 1
        producer = c.desk_string(.producer) ?? "turn"
        head = (try? c.decodeIfPresent(PanelHead.self, forKey: .head)) ?? PanelHead()
        sections = c.desk_lossy(.sections).filter { !$0.blocks.isEmpty }
        quiet = c.desk_bool(.quiet) ?? false
    }

    /// Something to draw. A page whose every block was unknown or broken is
    /// the same as no page.
    var hasContent: Bool { sections.contains { !$0.blocks.isEmpty } }
}

struct PanelHead: Decodable, Hashable {
    /// Mono kicker: "THIS TURN", "HEALTH", "TODAY".
    var kicker: String = ""
    /// Domains or anchors, shown muted after the kicker.
    var context: [String] = []
    var title: String = ""
    var standfirst: String?

    init(kicker: String = "", context: [String] = [], title: String = "", standfirst: String? = nil) {
        self.kicker = kicker
        self.context = context
        self.title = title
        self.standfirst = standfirst
    }

    private enum Keys: String, CodingKey { case kicker, context, title, standfirst }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: Keys.self) else { return }
        kicker = c.desk_string(.kicker) ?? ""
        context = c.desk_lossy(.context)
        title = c.desk_string(.title) ?? ""
        standfirst = c.desk_string(.standfirst)
    }
}

struct PanelSection: Decodable, Hashable, Identifiable {
    var id: String
    /// Mono section label. Empty draws no label row.
    var label: String
    var blocks: [PanelBlock]

    init(id: String, label: String = "", blocks: [PanelBlock]) {
        self.id = id
        self.label = label
        self.blocks = blocks
    }

    private enum Keys: String, CodingKey { case id, label, blocks }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = c.desk_string(.id) ?? UUID().uuidString
        label = c.desk_string(.label) ?? ""
        blocks = (c.desk_lossy(.blocks) as [PanelBlock]).filter { $0.kind != .unknown }
    }
}

/// A button's prompt: what the composer is handed.
struct PanelAsk: Decodable, Hashable {
    var label: String
    var detail: String

    init(label: String, detail: String) {
        self.label = label
        self.detail = detail
    }

    private enum Keys: String, CodingKey { case label, detail }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        detail = c.desk_string(.detail) ?? ""
        label = c.desk_string(.label) ?? detail
        if detail.isEmpty { throw PanelDecodeError.unusable }
    }
}

/// Which block it is. `.unknown` is anything this build has not met — dropped
/// by its section, never drawn and never fatal.
enum PanelBlockKind: String, Hashable {
    case figures, series, bars, heat, rows, table, timeline, kv, prose, entity, actions, group
    case unknown
}

struct PanelFigure: Decodable, Hashable {
    var label: String = ""
    var value: String = ""
    var unit: String?
    var delta: String?
    /// `up` (petrol), `down` (accent), `flat`. The analytics convention:
    /// direction is not a judgement, so never good/error.
    var direction: String?
    var spark: [Double] = []
    var tone: String?

    init(label: String, value: String, unit: String? = nil, delta: String? = nil, direction: String? = nil, spark: [Double] = [], tone: String? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
        self.delta = delta
        self.direction = direction
        self.spark = spark
        self.tone = tone
    }

    private enum Keys: String, CodingKey { case label, value, unit, delta, direction, spark, tone }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        label = c.desk_string(.label) ?? ""
        value = c.desk_string(.value) ?? c.desk_double(.value).map(PanelCell.format) ?? "—"
        unit = c.desk_string(.unit)
        delta = c.desk_string(.delta)
        direction = c.desk_string(.direction)
        spark = c.desk_lossy(.spark)
        tone = c.desk_string(.tone)
    }
}

struct PanelPoint: Decodable, Hashable {
    var x: String
    var y: Double

    init(x: String, y: Double) {
        self.x = x
        self.y = y
    }

    private enum Keys: String, CodingKey { case x, y }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        guard let y = c.desk_double(.y) else { throw PanelDecodeError.unusable }
        self.y = y
        x = c.desk_string(.x) ?? c.desk_double(.x).map(PanelCell.format) ?? ""
    }
}

struct PanelSeries: Decodable, Hashable {
    var key: String
    var label: String
    var points: [PanelPoint]

    init(key: String, label: String, points: [PanelPoint]) {
        self.key = key
        self.label = label
        self.points = points
    }

    private enum Keys: String, CodingKey { case key, label, points }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        label = c.desk_string(.label) ?? ""
        key = c.desk_string(.key) ?? label
        points = c.desk_lossy(.points)
        if points.isEmpty { throw PanelDecodeError.unusable }
    }
}

struct PanelBar: Decodable, Hashable {
    var id: String
    var label: String
    var value: Double
    var display: String?
    var highlight: Bool
    var href: String?

    init(id: String, label: String, value: Double, display: String? = nil, highlight: Bool = false, href: String? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.display = display
        self.highlight = highlight
        self.href = href
    }

    private enum Keys: String, CodingKey { case id, label, value, display, highlight, href }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        guard let value = c.desk_double(.value) else { throw PanelDecodeError.unusable }
        self.value = value
        label = c.desk_string(.label) ?? ""
        id = c.desk_string(.id) ?? label
        display = c.desk_string(.display)
        highlight = c.desk_bool(.highlight) ?? false
        href = c.desk_string(.href)
    }
}

struct PanelHeatRow: Decodable, Hashable {
    var label: String
    var values: [Double?]

    private enum Keys: String, CodingKey { case label, values }

    init(label: String, values: [Double?]) {
        self.label = label
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        label = c.desk_string(.label) ?? ""
        let numbers: [PanelOptionalNumber] = c.desk_lossy(.values)
        values = numbers.map(\.value)
    }
}

struct PanelRow: Decodable, Hashable, Identifiable {
    var id: String
    var title: String
    var sub: String?
    var meta: String?
    var tone: String?
    var href: String?
    var external: Bool
    var ask: PanelAsk?

    init(id: String, title: String, sub: String? = nil, meta: String? = nil, tone: String? = nil, href: String? = nil, external: Bool = false, ask: PanelAsk? = nil) {
        self.id = id
        self.title = title
        self.sub = sub
        self.meta = meta
        self.tone = tone
        self.href = href
        self.external = external
        self.ask = ask
    }

    private enum Keys: String, CodingKey { case id, title, sub, meta, tone, href, external, ask }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        guard let title = c.desk_string(.title) else { throw PanelDecodeError.unusable }
        self.title = title
        id = c.desk_string(.id) ?? title
        sub = c.desk_string(.sub)
        meta = c.desk_string(.meta)
        tone = c.desk_string(.tone)
        href = c.desk_string(.href)
        external = c.desk_bool(.external) ?? false
        ask = try? c.decodeIfPresent(PanelAsk.self, forKey: .ask)
    }
}

struct PanelEvent: Decodable, Hashable, Identifiable {
    var id: String
    var when: String
    var what: String
    var sub: String?
    var hot: Bool
    var href: String?

    init(id: String, when: String, what: String, sub: String? = nil, hot: Bool = false, href: String? = nil) {
        self.id = id
        self.when = when
        self.what = what
        self.sub = sub
        self.hot = hot
        self.href = href
    }

    private enum Keys: String, CodingKey { case id, when, what, sub, hot, href }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        guard let what = c.desk_string(.what) else { throw PanelDecodeError.unusable }
        self.what = what
        when = c.desk_string(.when) ?? ""
        id = c.desk_string(.id) ?? "\(when)|\(what)"
        sub = c.desk_string(.sub)
        hot = c.desk_bool(.hot) ?? false
        href = c.desk_string(.href)
    }
}

struct PanelKV: Decodable, Hashable {
    var label: String
    var value: String
    var tone: String?

    init(label: String, value: String, tone: String? = nil) {
        self.label = label
        self.value = value
        self.tone = tone
    }

    private enum Keys: String, CodingKey { case label, value, tone }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        label = c.desk_string(.label) ?? ""
        value = c.desk_string(.value) ?? c.desk_double(.value).map(PanelCell.format) ?? "—"
        tone = c.desk_string(.tone)
    }
}

/// A desk button. The phone is sent only `ask` and `link` (the site strips the
/// kinds that post), and anything else that arrives is skipped here too.
struct PanelAction: Decodable, Hashable, Identifiable {
    var id: String
    var label: String
    /// `ask` or `link`.
    var kind: String
    var href: String?
    var ask: PanelAsk?

    init(id: String, label: String, kind: String, href: String? = nil, ask: PanelAsk? = nil) {
        self.id = id
        self.label = label
        self.kind = kind
        self.href = href
        self.ask = ask
    }

    private enum Keys: String, CodingKey { case id, label, kind, href, ask }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        kind = c.desk_string(.kind) ?? ""
        label = c.desk_string(.label) ?? ""
        id = c.desk_string(.id) ?? label
        href = c.desk_string(.href)
        ask = try? c.decodeIfPresent(PanelAsk.self, forKey: .ask)
        switch kind {
        case "ask" where ask != nil: break
        case "link" where href != nil: break
        default: throw PanelDecodeError.unusable
        }
    }
}

/// One cell of a desk table: text, a number, or nothing.
enum PanelCell: Decodable, Hashable {
    case text(String)
    case number(Double)
    case none

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .none }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .text(s) }
        else { self = .none }
    }

    var display: String {
        switch self {
        case .text(let s): return s
        case .number(let n): return Self.format(n)
        case .none: return "—"
        }
    }

    static func format(_ n: Double) -> String {
        if n.rounded() == n && abs(n) < 1e15 { return String(Int(n)) }
        return String(format: "%.2f", n)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
    }
}

/// What a block draws. Payloads per kind; the envelope is on `PanelBlock`.
indirect enum PanelContent: Hashable {
    case figures([PanelFigure])
    case series([PanelSeries], unit: String?, zero: Bool)
    case bars([PanelBar])
    case heat(columns: [String], rows: [PanelHeatRow], unit: String?)
    case rows([PanelRow], numbered: Bool, empty: String?)
    case table(columns: [String], rows: [[PanelCell]], pick: Int?)
    case timeline([PanelEvent])
    case kv([PanelKV])
    case prose(String, tone: String?)
    case entity(name: String, kind: String?, summary: String?)
    case actions([PanelAction])
    case group([PanelBlock])
    case unknown(String)
}

struct PanelBlock: Decodable, Hashable, Identifiable {
    var id: String
    var title: String?
    var note: String?
    var foot: String?
    /// Which tool call or composer made it, shown as provenance.
    var source: String?
    var href: String?
    var ask: PanelAsk?
    var content: PanelContent

    init(id: String, title: String? = nil, note: String? = nil, foot: String? = nil, source: String? = nil, href: String? = nil, ask: PanelAsk? = nil, content: PanelContent) {
        self.id = id
        self.title = title
        self.note = note
        self.foot = foot
        self.source = source
        self.href = href
        self.ask = ask
        self.content = content
    }

    var kind: PanelBlockKind {
        switch content {
        case .figures: return .figures
        case .series: return .series
        case .bars: return .bars
        case .heat: return .heat
        case .rows: return .rows
        case .table: return .table
        case .timeline: return .timeline
        case .kv: return .kv
        case .prose: return .prose
        case .entity: return .entity
        case .actions: return .actions
        case .group: return .group
        case .unknown: return .unknown
        }
    }

    /// A title, a note or a foot makes a block a card; without them it is
    /// drawn bare, the way the desk does it.
    var isCard: Bool { title != nil || note != nil || foot != nil }

    private enum Keys: String, CodingKey {
        case id, type, title, note, foot, source, href, ask
        case items, unit, zero, series, rows, columns, numbered, empty, pick, events
        case markdown, tone, entityId, name, kind, summary, blocks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = c.desk_string(.type) ?? ""
        id = c.desk_string(.id) ?? UUID().uuidString
        title = c.desk_string(.title)
        note = c.desk_string(.note)
        foot = c.desk_string(.foot)
        source = c.desk_string(.source)
        href = c.desk_string(.href)
        ask = try? c.decodeIfPresent(PanelAsk.self, forKey: .ask)

        switch PanelBlockKind(rawValue: type) ?? .unknown {
        case .figures:
            let items: [PanelFigure] = c.desk_lossy(.items)
            content = items.isEmpty ? .unknown(type) : .figures(items)
        case .series:
            let series: [PanelSeries] = c.desk_lossy(.series)
            content = series.isEmpty ? .unknown(type) : .series(series, unit: c.desk_string(.unit), zero: c.desk_bool(.zero) ?? false)
        case .bars:
            let bars: [PanelBar] = c.desk_lossy(.rows)
            content = bars.isEmpty ? .unknown(type) : .bars(bars)
        case .heat:
            let rows: [PanelHeatRow] = c.desk_lossy(.rows)
            let columns: [String] = c.desk_lossy(.columns)
            content = rows.isEmpty || columns.isEmpty ? .unknown(type) : .heat(columns: columns, rows: rows, unit: c.desk_string(.unit))
        case .rows:
            content = .rows(c.desk_lossy(.rows), numbered: c.desk_bool(.numbered) ?? false, empty: c.desk_string(.empty))
        case .table:
            let columns: [String] = c.desk_lossy(.columns)
            let rows: [[PanelCell]] = c.desk_lossy(.rows)
            let pick = c.desk_int(.pick)
            content = columns.isEmpty ? .unknown(type) : .table(columns: columns, rows: rows, pick: pick)
        case .timeline:
            let events: [PanelEvent] = c.desk_lossy(.events)
            content = events.isEmpty ? .unknown(type) : .timeline(events)
        case .kv:
            let items: [PanelKV] = c.desk_lossy(.items)
            content = items.isEmpty ? .unknown(type) : .kv(items)
        case .prose:
            let markdown = c.desk_string(.markdown) ?? ""
            content = markdown.isEmpty ? .unknown(type) : .prose(markdown, tone: c.desk_string(.tone))
        case .entity:
            let name = c.desk_string(.name) ?? ""
            content = name.isEmpty ? .unknown(type) : .entity(name: name, kind: c.desk_string(.kind), summary: c.desk_string(.summary))
        case .actions:
            let items: [PanelAction] = c.desk_lossy(.items)
            content = items.isEmpty ? .unknown(type) : .actions(items)
        case .group:
            // One level deep on the desk; a group inside a group is dropped.
            let blocks = (c.desk_lossy(.blocks) as [PanelBlock]).filter { $0.kind != .unknown && $0.kind != .group }
            content = blocks.isEmpty ? .unknown(type) : .group(blocks)
        case .unknown:
            content = .unknown(type)
        }
    }
}

enum PanelDecodeError: Error { case unusable }

/// `number | null` in an array, where a stray string must not drop the row.
struct PanelOptionalNumber: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        value = c.decodeNil() ? nil : (try? c.decode(Double.self))
    }
}

/// Decodes anything and keeps nothing: how a lossy array steps past an
/// element it could not read.
private struct PanelSkip: Decodable {
    init(from decoder: Decoder) throws {}
}

fileprivate extension KeyedDecodingContainer {
    func desk_string(_ key: Key) -> String? { (try? decodeIfPresent(String.self, forKey: key)) ?? nil }
    func desk_double(_ key: Key) -> Double? { (try? decodeIfPresent(Double.self, forKey: key)) ?? nil }
    func desk_int(_ key: Key) -> Int? { (try? decodeIfPresent(Int.self, forKey: key)) ?? nil }
    func desk_bool(_ key: Key) -> Bool? { (try? decodeIfPresent(Bool.self, forKey: key)) ?? nil }

    /// An array where one bad element is skipped rather than fatal. A missing
    /// key, a null or a non-array is an empty array.
    func desk_lossy<T: Decodable>(_ key: Key) -> [T] {
        guard var items = try? nestedUnkeyedContainer(forKey: key) else { return [] }
        var out: [T] = []
        while !items.isAtEnd {
            let before = items.currentIndex
            if let value = try? items.decode(T.self) {
                out.append(value)
            } else {
                // `null` will not decode even as a skip on every Foundation;
                // `decodeNil` steps over it.
                if (try? items.decodeNil()) != true { _ = try? items.decode(PanelSkip.self) }
            }
            // A decoder that neither read nor skipped would loop forever.
            if items.currentIndex == before { break }
        }
        return out
    }
}

// MARK: - Which page the desk shows

/// One turn as the desk sees it: an assistant message and its page, if any.
struct DeskTurn: Hashable {
    let id: String
    let isAssistant: Bool
    let page: PanelPage?

    var hasPage: Bool { isAssistant && (page?.hasContent ?? false) }
}

/// Picks the page for a turn. PURE, so the rule is tested rather than eyeballed.
enum DeskPager {
    struct Choice: Equatable {
        /// Into `pages(of:)`. `nil` means no page is worth showing: the desk
        /// shows Today instead.
        let index: Int?
        /// The turn asked about has no page of its own, so an earlier one is
        /// being held — "Quiet turn · desk held".
        let held: Bool
    }

    /// The turns that have a page, oldest first.
    static func pages(of turns: [DeskTurn]) -> [DeskTurn] { turns.filter(\.hasPage) }

    /// The page for `focus`: its own if it has one, else the nearest EARLIER
    /// page, held. No focus means the latest turn. A turn with no page and
    /// nothing before it shows Today.
    static func choose(turns: [DeskTurn], focus: String?) -> Choice {
        let pages = pages(of: turns)
        guard !pages.isEmpty else { return Choice(index: nil, held: false) }
        let target = focus.flatMap { id in turns.firstIndex { $0.id == id } }
            ?? turns.lastIndex(where: \.isAssistant)
            ?? (turns.count - 1)
        let turn = turns[target]
        if turn.hasPage, let own = pages.firstIndex(where: { $0.id == turn.id }) {
            return Choice(index: own, held: false)
        }
        // A user turn is asking about the answer that follows it, if there is
        // one; otherwise it is the newest thing and the desk holds.
        if !turn.isAssistant, target + 1 < turns.count, turns[target + 1].hasPage,
           let next = pages.firstIndex(where: { $0.id == turns[target + 1].id }) {
            return Choice(index: next, held: false)
        }
        let earlier = turns[..<target].last(where: \.hasPage)
        guard let earlier, let index = pages.firstIndex(where: { $0.id == earlier.id }) else {
            return Choice(index: nil, held: false)
        }
        return Choice(index: index, held: true)
    }
}

// MARK: - Links

enum DeskLinks {
    /// An `href` from a page: absolute http(s), or a site path resolved against
    /// the site the app is paired with. Anything else (the schema refuses
    /// `javascript:` and `//host`, and so does this) is nil.
    static func resolve(_ href: String?, origin: URL) -> URL? {
        guard let href = href?.trimmingCharacters(in: .whitespaces), !href.isEmpty else { return nil }
        let lower = href.lowercased()
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") { return URL(string: href) }
        guard href.hasPrefix("/"), !href.hasPrefix("//") else { return nil }
        return URL(string: href, relativeTo: origin)?.absoluteURL
    }
}
