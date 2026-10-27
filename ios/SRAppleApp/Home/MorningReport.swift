import Foundation

/// The morning report, as `GET /api/native/briefing` sends it.
///
/// The canvas workflow writes one briefing a day; SR-Main reads it back for
/// the phone with the nineteen factor cards and the connections between them
/// (wire contract §2–§3, 2026-10-27). The screen is `MorningReportScreen`.
///
/// Foundation only and TOLERANT by design, so every rule here is a unit test
/// the Linux harness runs (`scripts/home-check.sh`): a status, group or mode
/// this build has never heard of decodes as `.other`, a missing list is
/// empty (a record written before the factors existed has neither), and one
/// malformed card costs that card, not the whole report.
struct NativeBriefing: Codable, Equatable, Sendable {
    var day: String
    var title: String
    var dateLabel: String
    var generatedAt: String
    var headline: String
    /// The verified prose, or the plain fallback when verification failed.
    var markdown: String
    var verified: Bool
    var mode: Mode?
    /// Always nineteen on a new record; empty on one written before them.
    var factors: [FactorCard]
    /// Most salient first, 0…6.
    var connections: [Connection]
    var gaps: [Gap]
    var daydreamsText: String
    /// The web page for the same day — absolute, or a site path.
    var pageUrl: String
    /// Newest first, up to fourteen days that have a record.
    var days: [String]

    enum Mode: Codable, Equatable, Hashable, Sendable {
        case weekday, monday, weekend, travel
        case other(String)

        init(raw: String) {
            switch raw {
            case "weekday": self = .weekday
            case "monday": self = .monday
            case "weekend": self = .weekend
            case "travel": self = .travel
            default: self = .other(raw)
            }
        }

        var raw: String {
            switch self {
            case .weekday: return "weekday"
            case .monday: return "monday"
            case .weekend: return "weekend"
            case .travel: return "travel"
            case .other(let raw): return raw
            }
        }

        /// A short word for the header chip; nil for a mode with nothing to say.
        var label: String? {
            switch self {
            case .weekday: return nil
            case .monday: return "Week ahead"
            case .weekend: return "Weekend"
            case .travel: return "Travelling"
            case .other: return nil
            }
        }

        init(from decoder: Decoder) throws {
            self.init(raw: try decoder.singleValueContainer().decode(String.self))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(raw)
        }
    }

    /// A cross-factor observation: "Rain at 16:00 and the school run".
    struct Connection: Codable, Equatable, Hashable, Sendable {
        var text: String
        var factors: [String]
        var salience: Double
        var action: Bool

        init(text: String, factors: [String] = [], salience: Double = 0, action: Bool = false) {
            self.text = text
            self.factors = factors
            self.salience = salience
            self.action = action
        }

        private enum CodingKeys: String, CodingKey { case text, factors, salience, action }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            text = c.lenientString(.text) ?? ""
            factors = (try? c.decodeIfPresent([String].self, forKey: .factors)) ?? []
            salience = c.lenientDouble(.salience) ?? 0
            action = (try? c.decodeIfPresent(Bool.self, forKey: .action)) ?? false
        }
    }

    /// A section the briefing could not fill, and why.
    struct Gap: Codable, Equatable, Hashable, Sendable {
        var section: String
        var reason: String

        init(section: String, reason: String) {
            self.section = section
            self.reason = reason
        }

        private enum CodingKeys: String, CodingKey { case section, reason }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            section = c.lenientString(.section) ?? ""
            reason = c.lenientString(.reason) ?? ""
        }
    }

    private enum CodingKeys: String, CodingKey {
        case day, title, dateLabel, generatedAt, headline, markdown, verified, mode
        case factors, connections, gaps, daydreamsText, pageUrl, days
    }

    init(
        day: String, title: String = "", dateLabel: String = "", generatedAt: String = "", headline: String = "",
        markdown: String = "", verified: Bool = false, mode: Mode? = nil, factors: [FactorCard] = [],
        connections: [Connection] = [], gaps: [Gap] = [], daydreamsText: String = "", pageUrl: String = "",
        days: [String] = []
    ) {
        self.day = day
        self.title = title
        self.dateLabel = dateLabel
        self.generatedAt = generatedAt
        self.headline = headline
        self.markdown = markdown
        self.verified = verified
        self.mode = mode
        self.factors = factors
        self.connections = connections
        self.gaps = gaps
        self.daydreamsText = daydreamsText
        self.pageUrl = pageUrl
        self.days = days
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = c.lenientString(.day) ?? ""
        title = c.lenientString(.title) ?? ""
        dateLabel = c.lenientString(.dateLabel) ?? ""
        generatedAt = c.lenientString(.generatedAt) ?? ""
        headline = c.lenientString(.headline) ?? ""
        markdown = c.lenientString(.markdown) ?? ""
        verified = (try? c.decodeIfPresent(Bool.self, forKey: .verified)) ?? false
        mode = (try? c.decodeIfPresent(String.self, forKey: .mode)).map(Mode.init(raw:))
        factors = c.lossyArray(FactorCard.self, .factors)
        connections = c.lossyArray(Connection.self, .connections)
        gaps = c.lossyArray(Gap.self, .gaps)
        daydreamsText = c.lenientString(.daydreamsText) ?? ""
        pageUrl = c.lenientString(.pageUrl) ?? ""
        days = (try? c.decodeIfPresent([String].self, forKey: .days)) ?? []
    }
}

/// One of the nineteen things the briefing looks at, as a card.
struct FactorCard: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// `location`, `weather-here`, … — kept as a string so a twentieth factor
    /// decodes rather than failing the report.
    var key: String
    /// 1…19, display order.
    var n: Int
    var label: String
    var group: Group
    /// An SF Symbol name.
    var icon: String
    var status: Status
    /// One code-written line; empty when the status is failed or off.
    var headline: String
    /// 0…100.
    var salience: Double
    var facts: [Fact]
    /// The source's one-liner — the reason, when the status is not ok.
    var detail: String

    var id: String { key.isEmpty ? "n\(n)" : key }

    enum Status: Codable, Equatable, Hashable, Sendable {
        case ok, stale, empty, failed, off
        case other(String)

        init(raw: String) {
            switch raw {
            case "ok": self = .ok
            case "stale": self = .stale
            case "empty": self = .empty
            case "failed": self = .failed
            case "off": self = .off
            default: self = .other(raw)
            }
        }

        var raw: String {
            switch self {
            case .ok: return "ok"
            case .stale: return "stale"
            case .empty: return "empty"
            case .failed: return "failed"
            case .off: return "off"
            case .other(let raw): return raw
            }
        }

        /// The chip on a card that is not simply fine; nil for `ok`.
        var badge: String? {
            switch self {
            case .ok: return nil
            case .stale: return "Stale"
            case .empty: return "Nothing yet"
            case .failed: return "Failed"
            case .off: return "Off"
            case .other(let raw): return raw.isEmpty ? nil : raw.capitalized
            }
        }

        /// Drawn quieter: nothing to read on it today.
        var isQuiet: Bool { self == .empty || self == .off }

        init(from decoder: Decoder) throws {
            self.init(raw: try decoder.singleValueContainer().decode(String.self))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(raw)
        }
    }

    enum Group: Codable, Equatable, Hashable, Sendable {
        case place, body, day, homeFamily, intelligence, systems
        case other(String)

        /// The order the screen draws the groups in.
        static let order: [Group] = [.place, .body, .day, .homeFamily, .intelligence, .systems]

        init(raw: String) {
            switch raw {
            case "Place": self = .place
            case "Body": self = .body
            case "Day": self = .day
            case "Home & family": self = .homeFamily
            case "Intelligence": self = .intelligence
            case "Systems": self = .systems
            default: self = .other(raw)
            }
        }

        var raw: String {
            switch self {
            case .place: return "Place"
            case .body: return "Body"
            case .day: return "Day"
            case .homeFamily: return "Home & family"
            case .intelligence: return "Intelligence"
            case .systems: return "Systems"
            case .other(let raw): return raw
            }
        }

        var title: String { raw.isEmpty ? "Other" : raw }

        init(from decoder: Decoder) throws {
            self.init(raw: try decoder.singleValueContainer().decode(String.self))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(raw)
        }
    }

    struct Fact: Codable, Equatable, Hashable, Sendable {
        var label: String
        var value: String
        var assessment: String?
        /// A site path (`/jkai/…`) or an absolute URL (a news story).
        var href: String?
        var action: Bool

        init(label: String, value: String, assessment: String? = nil, href: String? = nil, action: Bool = false) {
            self.label = label
            self.value = value
            self.assessment = assessment
            self.href = href
            self.action = action
        }

        private enum CodingKeys: String, CodingKey { case label, value, assessment, href, action }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = c.lenientString(.label) ?? ""
            value = c.lenientString(.value) ?? ""
            assessment = c.lenientString(.assessment).flatMap { $0.isEmpty ? nil : $0 }
            href = c.lenientString(.href).flatMap { $0.isEmpty ? nil : $0 }
            action = (try? c.decodeIfPresent(Bool.self, forKey: .action)) ?? false
        }
    }

    init(
        key: String, n: Int, label: String, group: Group, icon: String = "circle", status: Status = .ok,
        headline: String = "", salience: Double = 0, facts: [Fact] = [], detail: String = ""
    ) {
        self.key = key
        self.n = n
        self.label = label
        self.group = group
        self.icon = icon
        self.status = status
        self.headline = headline
        self.salience = salience
        self.facts = facts
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey {
        case key, n, label, group, icon, status, headline, salience, facts, detail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.lenientString(.key) ?? ""
        n = c.lenientDouble(.n).map { Int($0.rounded()) } ?? 0
        label = c.lenientString(.label) ?? ""
        group = (c.lenientString(.group)).map(Group.init(raw:)) ?? .other("")
        icon = c.lenientString(.icon) ?? ""
        status = (c.lenientString(.status)).map(Status.init(raw:)) ?? .other("")
        headline = c.lenientString(.headline) ?? ""
        salience = c.lenientDouble(.salience) ?? 0
        facts = c.lossyArray(Fact.self, .facts)
        detail = c.lenientString(.detail) ?? ""
    }

    /// What the card says under its label: the headline, or — on a card
    /// with none (failed, off) — the reason.
    var line: String {
        let head = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        if !head.isEmpty { return head }
        let why = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !why.isEmpty { return why }
        return status.badge ?? ""
    }

    /// Whether any fact on it asks for something to be done.
    var hasAction: Bool { facts.contains(where: \.action) }
}

extension NativeBriefing {
    /// The factors under their group headings, in the contract's group order
    /// and then any group this build does not know, each group by `n`.
    var grouped: [(group: FactorCard.Group, factors: [FactorCard])] {
        var order = FactorCard.Group.order
        for factor in factors where !order.contains(factor.group) { order.append(factor.group) }
        return order.compactMap { group in
            let members = factors.filter { $0.group == group }.sorted { $0.n == $1.n ? $0.key < $1.key : $0.n < $1.n }
            return members.isEmpty ? nil : (group, members)
        }
    }

    /// A connection's factors by their labels, as the cards name them.
    func labels(for connection: Connection) -> [String] {
        connection.factors.map { key in factors.first(where: { $0.key == key })?.label ?? key }
    }

    /// Connections that ask for something to be done.
    var actionable: Int { connections.filter(\.action).count }

    /// The site path for one day's report, or the newest. A `day` that is not
    /// `YYYY-MM-DD` is dropped rather than sent.
    static func path(day: String? = nil) -> String {
        guard let day, isDay(day) else { return "api/native/briefing" }
        return "api/native/briefing?day=\(day)"
    }

    static func isDay(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return false }
        return parts.allSatisfy { $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    /// "Wed 28 Oct" for `2026-10-28`, for the day picker. The string back
    /// when it is not a day.
    static func shortLabel(_ day: String) -> String {
        guard isDay(day) else { return day }
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = TimeZone(identifier: "UTC")
        parse.dateFormat = "yyyy-MM-dd"
        guard let date = parse.date(from: day) else { return day }
        let show = DateFormatter()
        show.locale = Locale(identifier: "en_GB")
        show.timeZone = TimeZone(identifier: "UTC")
        show.dateFormat = "EEE d MMM"
        return show.string(from: date)
    }
}

/// Where a link in the report goes.
enum BriefingLinks {
    /// The site a relative `href` is resolved against.
    static let origin = URL(string: "https://strangeramblings.com")!

    /// Absolute http(s) as it is; a site path against `origin`. Anything else
    /// — `javascript:`, `//host`, a bare word — is nil, and nothing opens.
    static func resolve(_ href: String?, origin: URL = BriefingLinks.origin) -> URL? {
        guard let href = href?.trimmingCharacters(in: .whitespacesAndNewlines), !href.isEmpty else { return nil }
        let lower = href.lowercased()
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
            guard let url = URL(string: href), url.host != nil else { return nil }
            return url
        }
        guard href.hasPrefix("/"), !href.hasPrefix("//") else { return nil }
        return URL(string: href, relativeTo: origin)?.absoluteURL
    }
}

// MARK: - Lenient decoding

private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private extension KeyedDecodingContainer {
    /// A string, or a number or bool said as one; nil when absent, null or
    /// anything else.
    func lenientString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value ? "true" : "false" }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Double(value) }
        return nil
    }

    /// The elements that decode; a missing key, a null or a non-array is [].
    func lossyArray<Value: Decodable>(_ type: Value.Type, _ key: Key) -> [Value] {
        guard let items = try? decodeIfPresent([Lossy<Value>].self, forKey: key) else { return [] }
        return items.compactMap(\.value)
    }
}
