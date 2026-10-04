import Foundation

// Landgrab on the phone: the family territory game's weekly board and the map
// of what changed hands. The wire shapes, and every rule about them as a pure
// function.
//
// Foundation only, like `FamilyBoardModels.swift`, so the rules can be compiled
// and run on Linux (the decoder harness) — but NOT shared with the widget
// extension: nothing on a widget draws Landgrab, so this file is in the app
// target alone (`app.yml`'s recursive `SRAppleApp` source) and not in
// `watch.yml`'s `SRAppleLive` list.
//
// The contract is SR-Main's `GET /api/native/family/landgrab?weeks=6` and
// `GET /api/native/family/landgrab/changes?week=YYYY-MM-DD` (spec: Landgrab in
// the SR iPhone app, 2026-10-04). The unit everywhere is the HEX — the 48 m
// cell of ground the /health/landgrab board draws — so the numbers match the
// map. Every decoder is lenient: a missing, null or odd field costs that
// field, never the board. Swift's synthesised `Codable` throws on a missing
// non-optional key, so every type here decodes by hand.

// MARK: - Lenient reading

private struct LandgrabKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private extension KeyedDecodingContainer where K == LandgrabKey {
    func text(_ keys: String...) -> String? {
        for key in keys {
            if let value = try? decodeIfPresent(String.self, forKey: LandgrabKey(key)) { return value }
            // A number where a string was promised (an id sent as 7): keep it.
            if let value = try? decodeIfPresent(Int.self, forKey: LandgrabKey(key)) { return String(value) }
        }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: LandgrabKey(key)) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: LandgrabKey(key)), value.isFinite,
           abs(value) < 1e12 { return Int(value.rounded()) }
        if let value = try? decodeIfPresent(String.self, forKey: LandgrabKey(key)) { return Int(value) }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: LandgrabKey(key)), value.isFinite { return value }
        if let value = try? decodeIfPresent(String.self, forKey: LandgrabKey(key)), let parsed = Double(value),
           parsed.isFinite { return parsed }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: LandgrabKey(key)) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: LandgrabKey(key)) { return value != 0 }
        return nil
    }

    /// An array whose bad elements are dropped one by one, rather than the
    /// whole array failing on the first.
    func list<T: Decodable>(_ type: T.Type, _ key: String) -> [T] {
        guard var items = try? nestedUnkeyedContainer(forKey: LandgrabKey(key)) else { return [] }
        var out: [T] = []
        while !items.isAtEnd {
            if let item = try? items.decode(T.self) {
                out.append(item)
            } else if (try? items.decode(LandgrabSkip.self)) == nil {
                break
            }
        }
        return out
    }
}

/// Consumes one element of any shape, so `list` can step past a bad one.
private struct LandgrabSkip: Decodable {
    init(from decoder: Decoder) throws {}
}

// MARK: - The weekly board (`/api/native/family/landgrab`)

/// Every week the site sent, newest first; `weeks[0]` is the current one.
struct LandgrabBoard: Decodable, Equatable {
    var updatedAt: String?
    var weeks: [LandgrabWeek]

    init(updatedAt: String? = nil, weeks: [LandgrabWeek]) {
        self.updatedAt = updatedAt
        self.weeks = weeks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LandgrabKey.self)
        updatedAt = c.text("updatedAt")
        // Weeks with no Monday cannot be asked about or labelled.
        weeks = c.list(LandgrabWeek.self, "weeks").filter { !$0.start.isEmpty }
    }
}

struct LandgrabWeek: Decodable, Equatable, Hashable, Identifiable {
    /// "2026-09-28" — a Monday, London.
    var start: String
    /// "2026-10-04" — the Sunday.
    var end: String
    var current: Bool
    var people: [LandgrabPerson]

    var id: String { start }

    init(start: String, end: String, current: Bool = false, people: [LandgrabPerson]) {
        self.start = start; self.end = end; self.current = current; self.people = people
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LandgrabKey.self)
        start = c.text("start") ?? ""
        end = c.text("end") ?? ""
        current = c.bool("current") ?? false
        people = c.list(LandgrabPerson.self, "people")
    }
}

/// One person's week. `won` = hexes they hold now that they did not at the
/// week's start; `taken` = the part of that somebody else held; `lost` =
/// hexes they held that somebody else holds now; `net` = won − lost; `held`
/// = all they hold now.
struct LandgrabPerson: Decodable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var me: Bool
    var won: Int
    var taken: Int
    var lost: Int
    var net: Int
    var held: Int
    var rank: Int
    /// "#c2410c", the person's Landgrab colour. Nil or unreadable → a
    /// fallback (`LandgrabColour.resolve`).
    var colour: String?

    init(id: String, name: String, me: Bool = false, won: Int = 0, taken: Int = 0, lost: Int = 0,
         net: Int? = nil, held: Int = 0, rank: Int = 0, colour: String? = nil) {
        self.id = id; self.name = name; self.me = me
        self.won = won; self.taken = taken; self.lost = lost
        self.net = net ?? (won - lost); self.held = held; self.rank = rank; self.colour = colour
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LandgrabKey.self)
        id = c.text("id") ?? UUID().uuidString
        name = c.text("name") ?? ""
        me = c.bool("me") ?? false
        won = max(0, c.int("won") ?? 0)
        taken = max(0, c.int("taken") ?? 0)
        lost = max(0, c.int("lost") ?? 0)
        // A missing net is worked out, never guessed as nought.
        net = c.int("net") ?? (won - lost)
        held = max(0, c.int("held") ?? 0)
        rank = c.int("rank") ?? 0
        colour = c.text("colour", "color")
    }
}

// MARK: - What changed (`/api/native/family/landgrab/changes`)

/// A point as the wire sends it: `[lat, lon]`. An `{lat, lon}` object is read
/// too. Anything off the globe is refused, so a bad point is dropped rather
/// than drawn at 0,0 off the coast of Africa.
struct LandgrabPoint: Decodable, Equatable, Hashable {
    var lat: Double
    var lon: Double

    init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }

    init(from decoder: Decoder) throws {
        if var pair = try? decoder.unkeyedContainer() {
            let lat = try pair.decode(Double.self)
            let lon = try pair.decode(Double.self)
            self.init(lat: lat, lon: lon)
        } else {
            let c = try decoder.container(keyedBy: LandgrabKey.self)
            guard let lat = c.double("lat"), let lon = c.double("lon") ?? c.double("lng") else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no lat/lon"))
            }
            self.init(lat: lat, lon: lon)
        }
        guard Self.valid(lat: lat, lon: lon) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "off the globe"))
        }
    }

    static func valid(lat: Double, lon: Double) -> Bool {
        lat.isFinite && lon.isFinite && abs(lat) <= 90 && abs(lon) <= 180
    }
}

struct LandgrabWeekRange: Decodable, Equatable, Hashable {
    var start: String
    var end: String
    var current: Bool

    init(start: String, end: String, current: Bool = false) {
        self.start = start; self.end = end; self.current = current
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LandgrabKey.self)
        start = c.text("start") ?? ""
        end = c.text("end") ?? ""
        current = c.bool("current") ?? false
    }
}

struct LandgrabBounds: Decodable, Equatable, Hashable {
    var minLat: Double
    var minLon: Double
    var maxLat: Double
    var maxLon: Double

    init(minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
        self.minLat = minLat; self.minLon = minLon; self.maxLat = maxLat; self.maxLon = maxLon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LandgrabKey.self)
        guard let minLat = c.double("minLat"), let minLon = c.double("minLon"),
              let maxLat = c.double("maxLat"), let maxLon = c.double("maxLon"),
              LandgrabPoint.valid(lat: minLat, lon: minLon), LandgrabPoint.valid(lat: maxLat, lon: maxLon),
              minLat <= maxLat, minLon <= maxLon else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad bounds"))
        }
        self.init(minLat: minLat, minLon: minLon, maxLat: maxLat, maxLon: maxLon)
    }

    var points: [LandgrabPoint] {
        [LandgrabPoint(lat: minLat, lon: minLon), LandgrabPoint(lat: maxLat, lon: maxLon)]
    }
}

/// Somebody on the map: their id (the steps board's), name and colour.
struct LandgrabMapPerson: Decodable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var colour: String?
    var me: Bool

    init(id: String, name: String, colour: String? = nil, me: Bool = false) {
        self.id = id; self.name = name; self.colour = colour; self.me = me
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LandgrabKey.self)
        id = c.text("id", "subject") ?? UUID().uuidString
        name = c.text("name") ?? ""
        colour = c.text("colour", "color")
        me = c.bool("me") ?? false
    }
}

/// One hex that changed owner this week: who holds it now, who held it at
/// the week's start (nil: nobody did).
struct LandgrabHex: Decodable, Equatable, Hashable, Identifiable {
    var id: Int
    var polygon: [LandgrabPoint]
    var owner: String?
    var previous: String?

    init(id: Int, polygon: [LandgrabPoint], owner: String?, previous: String? = nil) {
        self.id = id; self.polygon = polygon; self.owner = owner; self.previous = previous
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LandgrabKey.self)
        guard let id = c.int("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no hex id"))
        }
        let polygon = c.list(LandgrabPoint.self, "polygon")
        // Fewer than three corners is not a shape; drop the hex, keep the map.
        guard polygon.count >= 3 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a polygon"))
        }
        self.init(id: id, polygon: polygon, owner: c.text("owner"), previous: c.text("previous"))
    }
}

/// Where a change's ground came from: so many hexes from a person, or from
/// nobody (`id` nil: unclaimed ground).
struct LandgrabSource: Decodable, Equatable, Hashable {
    var id: String?
    var hexes: Int

    init(id: String?, hexes: Int) { self.id = id; self.hexes = hexes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LandgrabKey.self)
        id = c.text("id", "subject")
        hexes = max(0, c.int("hexes") ?? 0)
    }
}

enum LandgrabActivityType: String, CaseIterable {
    case walk, run, ride, hike
}

/// The outing that took the ground. Its trace is already trimmed (200 m at
/// both ends) and thinned by the site; it may be empty.
struct LandgrabActivity: Decodable, Equatable, Hashable {
    /// "workout" or "trail".
    var kind: String
    /// "walk", "run", "ride", "hike", or nil / something new.
    var type: String?
    var startedAt: String?
    var endedAt: String?
    var distanceM: Double?
    var durationS: Double?
    /// Closed a loop — which takes everything inside it.
    var loop: Bool
    var trace: [LandgrabPoint]

    init(kind: String = "workout", type: String? = nil, startedAt: String? = nil, endedAt: String? = nil,
         distanceM: Double? = nil, durationS: Double? = nil, loop: Bool = false, trace: [LandgrabPoint] = []) {
        self.kind = kind; self.type = type; self.startedAt = startedAt; self.endedAt = endedAt
        self.distanceM = distanceM; self.durationS = durationS; self.loop = loop; self.trace = trace
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LandgrabKey.self)
        kind = c.text("kind") ?? "workout"
        type = c.text("type")
        startedAt = c.text("startedAt")
        endedAt = c.text("endedAt")
        distanceM = c.double("distanceM").flatMap { $0 >= 0 ? $0 : nil }
        durationS = c.double("durationS").flatMap { $0 >= 0 ? $0 : nil }
        loop = c.bool("loop") ?? false
        trace = c.list(LandgrabPoint.self, "trace")
    }

    var typeValue: LandgrabActivityType? { type.flatMap { LandgrabActivityType(rawValue: $0.lowercased()) } }
}

/// One outing's haul, or the ground nobody's outing explains.
struct LandgrabChange: Decodable, Equatable, Hashable, Identifiable {
    var id: String
    /// Who won it. The contract replaces Health's `subject` with the person's
    /// id; because a change already has an `id` of its own, the person is read
    /// from `personId` first, then `person`, then `subject`, and failing all
    /// three from the owner of its hexes (`LandgrabChanges.init`).
    var personId: String?
    var at: String?
    var won: Int
    var taken: Int
    var from: [LandgrabSource]
    var hexIds: [Int]
    var activity: LandgrabActivity?

    init(id: String, personId: String?, at: String? = nil, won: Int, taken: Int = 0,
         from: [LandgrabSource] = [], hexIds: [Int] = [], activity: LandgrabActivity? = nil) {
        self.id = id; self.personId = personId; self.at = at; self.won = won; self.taken = taken
        self.from = from; self.hexIds = hexIds; self.activity = activity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LandgrabKey.self)
        id = c.text("id") ?? UUID().uuidString
        personId = c.text("personId", "person", "subject")
        at = c.text("at")
        hexIds = c.list(Int.self, "hexIds")
        won = max(0, c.int("won") ?? hexIds.count)
        from = c.list(LandgrabSource.self, "from")
        taken = max(0, c.int("taken") ?? from.filter { $0.id != nil }.reduce(0) { $0 + $1.hexes })
        activity = (try? c.decodeIfPresent(LandgrabActivity.self, forKey: LandgrabKey("activity"))) ?? nil
    }
}

/// `GET /api/native/family/landgrab/changes?week=…`.
struct LandgrabChanges: Decodable, Equatable {
    var week: LandgrabWeekRange
    var bounds: LandgrabBounds?
    var people: [LandgrabMapPerson]
    var hexes: [LandgrabHex]
    var changes: [LandgrabChange]
    /// Over the site's 4,000-hex cap: the largest changes were kept.
    var truncated: Bool

    init(week: LandgrabWeekRange, bounds: LandgrabBounds? = nil, people: [LandgrabMapPerson],
         hexes: [LandgrabHex], changes: [LandgrabChange], truncated: Bool = false) {
        self.week = week; self.bounds = bounds; self.people = people
        self.hexes = hexes; self.changes = changes; self.truncated = truncated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LandgrabKey.self)
        week = (try? c.decodeIfPresent(LandgrabWeekRange.self, forKey: LandgrabKey("week")))
            ?? LandgrabWeekRange(start: "", end: "")
        bounds = (try? c.decodeIfPresent(LandgrabBounds.self, forKey: LandgrabKey("bounds"))) ?? nil
        people = c.list(LandgrabMapPerson.self, "people")
        hexes = c.list(LandgrabHex.self, "hexes")
        truncated = c.bool("truncated") ?? false
        var changes = c.list(LandgrabChange.self, "changes")
        // A change with no person says whose it is through its hexes.
        let owners = Dictionary(hexes.map { ($0.id, $0.owner) }, uniquingKeysWith: { a, _ in a })
        for index in changes.indices where changes[index].personId == nil {
            changes[index].personId = changes[index].hexIds.lazy.compactMap { owners[$0] ?? nil }.first
        }
        self.changes = changes
    }
}

// MARK: - Colour

/// A person's Landgrab colour, and what can be written on it.
///
/// The site sends each person's colour; the app draws a swatch or a hex in it
/// and never sets body text in it (a mid-tone that reads on cream vanishes on
/// the dark ground). Anything written ON the colour — an initial on an avatar
/// — takes whichever of ink or cream contrasts with it more.
struct LandgrabRGB: Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) { self.red = red; self.green = green; self.blue = blue }

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// WCAG relative luminance, 0 (black) … 1 (white).
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, 1 … 21.
    func contrast(with other: LandgrabRGB) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

enum LandgrabColour {
    /// The design system's ink and paper (`SR.Fixed`), the two candidates for
    /// writing on a person's colour.
    static let ink = LandgrabRGB(hex: 0x1A1008)
    static let paper = LandgrabRGB(hex: 0xEDE4D4)

    /// Used when the site sends no colour, or one that is not a colour —
    /// picked by the person's id, so a person keeps theirs between reads.
    static let fallbacks: [UInt32] = [0xC4570A, 0x0E5B66, 0x55663A, 0x7A4E9C, 0xB0892A, 0x9C3D54]

    /// "#c2410c", "c2410c", "#c41" → the colour; anything else → nil.
    static func parse(_ text: String?) -> LandgrabRGB? {
        guard var raw = text?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if raw.hasPrefix("#") { raw.removeFirst() }
        if raw.count == 3 { raw = raw.map { "\($0)\($0)" }.joined() }
        guard raw.count == 6, raw.allSatisfy(\.isHexDigit), let value = UInt32(raw, radix: 16) else { return nil }
        return LandgrabRGB(hex: value)
    }

    /// The colour to draw a person in.
    static func resolve(_ text: String?, id: String) -> LandgrabRGB {
        parse(text) ?? LandgrabRGB(hex: fallbacks[stableIndex(id, count: fallbacks.count)])
    }

    /// Whether text on `colour` should be the ink (dark) or the paper (light).
    static func writesInInk(on colour: LandgrabRGB) -> Bool {
        colour.contrast(with: ink) >= colour.contrast(with: paper)
    }

    /// A stable index for a string — `hashValue` changes every launch.
    static func stableIndex(_ text: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return Int(hash % UInt32(count))
    }
}

// MARK: - The rules

enum Landgrab {
    /// The board's clock: weeks run Monday 00:00 → Sunday 24:00, London.
    static let zone = TimeZone(identifier: "Europe/London")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    // Names spelled here, not by a DateFormatter: en_GB abbreviates
    // September "Sept" on some releases and "Sep" on others, and a label that
    // changes with the OS cannot be tested.
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let shortDays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let longDays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// "21 Sep", London.
    static func dayMonth(_ date: Date) -> String {
        let parts = calendar.dateComponents([.day, .month], from: date)
        let month = months[max(0, min(11, (parts.month ?? 1) - 1))]
        return "\(parts.day ?? 0) \(month)"
    }

    /// "14:05", London, 24-hour.
    static func clock(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func weekday(_ date: Date, long: Bool) -> String {
        let index = max(0, min(6, calendar.component(.weekday, from: date) - 1))
        return long ? longDays[index] : shortDays[index]
    }

    // MARK: Weeks

    /// The week on the steps page: the one marked current, else the newest.
    static func currentWeek(_ board: LandgrabBoard) -> LandgrabWeek? {
        board.weeks.first { $0.current } ?? board.weeks.first
    }

    /// The week before the current one, when the site sent it.
    static func previousWeek(_ board: LandgrabBoard) -> LandgrabWeek? {
        guard let current = currentWeek(board), let index = board.weeks.firstIndex(of: current),
              board.weeks.indices.contains(index + 1) else { return nil }
        return board.weeks[index + 1]
    }

    /// Whether the steps page shows the section at all: only with somebody
    /// on this week's board.
    static func shows(_ board: LandgrabBoard?) -> Bool {
        guard let board, let week = currentWeek(board) else { return false }
        return !week.people.isEmpty
    }

    /// "2026-09-28" → that day at London midnight.
    static func day(_ ymd: String) -> Date? {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func ymd(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The London Monday of the week holding `date`, as "YYYY-MM-DD".
    static func monday(of date: Date) -> String {
        let cal = calendar
        let start = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: start) // 1 = Sunday … 7 = Saturday
        let back = (weekday + 5) % 7                         // days since Monday
        return ymd(cal.date(byAdding: .day, value: -back, to: start) ?? start)
    }

    /// "This week", "Last week", or "Week of 21 Sep".
    static func weekLabel(start: String, current: Bool, now: Date = Date()) -> String {
        let thisMonday = monday(of: now)
        if current || start == thisMonday { return "This week" }
        if let monday = day(thisMonday), let previous = calendar.date(byAdding: .day, value: -7, to: monday),
           start == ymd(previous) {
            return "Last week"
        }
        guard let date = day(start) else { return start }
        return "Week of \(dayMonth(date))"
    }

    /// A week's label inside a sentence: "this week", "last week", "in the
    /// week of 14 Sep".
    static func phrase(_ label: String) -> String {
        if label == "This week" || label == "Last week" { return label.lowercased() }
        guard let first = label.first else { return label }
        return "in the " + first.lowercased() + label.dropFirst()
    }

    /// "28 Sep – 4 Oct".
    static func weekRange(start: String, end: String) -> String? {
        guard let from = day(start) else { return nil }
        let to = day(end) ?? calendar.date(byAdding: .day, value: 6, to: from)
        guard let to else { return dayMonth(from) }
        return "\(dayMonth(from)) – \(dayMonth(to))"
    }

    // MARK: Ranking and figures

    /// Net first, then won, then name; ties (same net, same won) share a
    /// rank: 1, 1, 3.
    static func ranked(_ people: [LandgrabPerson]) -> [LandgrabPerson] {
        let sorted = people.sorted { a, b in
            if a.net != b.net { return a.net > b.net }
            if a.won != b.won { return a.won > b.won }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        var out: [LandgrabPerson] = []
        for (index, person) in sorted.enumerated() {
            var next = person
            if let previous = out.last, previous.net == person.net, previous.won == person.won {
                next.rank = previous.rank
            } else {
                next.rank = index + 1
            }
            out.append(next)
        }
        return out
    }

    /// The More card's status: your place and net this week ("2nd · +38"),
    /// or who leads when you are not on the board ("Sam leads, +100"). Nil
    /// with nobody on it.
    static func moreStatus(_ board: LandgrabBoard?) -> String? {
        guard let board, let week = currentWeek(board) else { return nil }
        let people = ranked(week.people)
        if let mine = people.first(where: { $0.me }) {
            return "\(FamilySteps.ordinal(mine.rank)) · \(signed(mine.net))"
        }
        guard let leader = people.first else { return nil }
        return "\(leader.name) leads, \(signed(leader.net))"
    }

    /// 1,234 — grouped the British way whatever the phone's region.
    static func figure(_ n: Int) -> String {
        let format = NumberFormatter()
        format.numberStyle = .decimal
        format.locale = Locale(identifier: "en_GB")
        return format.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// "+38", "−3" (a true minus), "0".
    static func signed(_ n: Int) -> String {
        if n > 0 { return "+\(figure(n))" }
        if n < 0 { return "\u{2212}\(figure(-n))" }
        return "0"
    }

    /// "1 hex", "18 hexes".
    static func hexes(_ n: Int) -> String { n == 1 ? "1 hex" : "\(figure(n)) hexes" }

    /// The row, said aloud: "1st, Lee, won 41 hexes, lost 3, net plus 38."
    static func spoken(_ person: LandgrabPerson, tied: Bool = false) -> String {
        let place = FamilySteps.ordinal(person.rank)
        let who = person.me ? "you" : person.name
        let net: String
        switch person.net {
        case let n where n > 0: net = "net plus \(figure(n))"
        case let n where n < 0: net = "net minus \(figure(-n))"
        default: net = "net nought"
        }
        return "\(tied ? "Joint \(place)" : place), \(who), won \(hexes(person.won)), lost \(figure(person.lost)), \(net)"
    }

    /// Whether somebody else shares this person's rank.
    static func tied(_ person: LandgrabPerson, in people: [LandgrabPerson]) -> Bool {
        people.contains { $0.id != person.id && $0.rank == person.rank }
    }

    /// "Last week: Lee won most ground." / "Last week: you won most ground."
    /// / "Last week: Lee and Sam won the same ground." Nil when nobody won
    /// any, or there was no last week.
    static func lastWeekLine(_ board: LandgrabBoard) -> String? {
        guard let week = previousWeek(board) else { return nil }
        let top = week.people.map(\.won).max() ?? 0
        guard top > 0 else { return nil }
        let leaders = week.people.filter { $0.won == top }
        let names = leaders.map { $0.me ? "you" : $0.name }
        if names.count == 1 { return "Last week: \(names[0]) won most ground." }
        return "Last week: \(list(names)) won the same ground."
    }

    /// "Lee", "Lee and Sam", "Lee, Sam and Pat".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }

    // MARK: Changes

    /// "Lee's walk", "John's ride", "Your run", "Kit's journey"; nil for the
    /// ground no outing explains (`unattributedLabel`).
    static func activityLabel(_ change: LandgrabChange, name: String?, me: Bool) -> String {
        guard let activity = change.activity else { return unattributedLabel }
        let noun: String
        if let type = activity.typeValue {
            noun = type.rawValue
        } else {
            noun = activity.kind == "trail" ? "journey" : "workout"
        }
        if me { return "Your \(noun)" }
        guard let name, !name.isEmpty else { return "A \(noun)" }
        return "\(name)'s \(noun)"
    }

    static let unattributedLabel = "Ground that changed hands"

    /// "Sat 09:12", London.
    static func shortTime(_ iso: String?) -> String? {
        guard let iso, let date = date(iso: iso) else { return nil }
        return "\(weekday(date, long: false)) \(clock(date))"
    }

    /// "Saturday 09:12", for VoiceOver.
    static func spokenTime(_ iso: String?) -> String? {
        guard let iso, let date = date(iso: iso) else { return nil }
        return "\(weekday(date, long: true)) \(clock(date))"
    }

    /// "850 m", "3.4 km", "112 km".
    static func distance(_ metres: Double?) -> String? {
        guard let metres, metres.isFinite, metres > 0 else { return nil }
        if metres < 1000 { return "\(Int((metres / 10).rounded() * 10)) m" }
        let km = metres / 1000
        return km < 100 ? String(format: "%.1f km", km) : "\(Int(km.rounded())) km"
    }

    /// "850 metres", "3.4 kilometres".
    static func spokenDistance(_ metres: Double?) -> String? {
        guard let text = distance(metres) else { return nil }
        if text.hasSuffix(" km") { return text.replacingOccurrences(of: " km", with: " kilometres") }
        return text.replacingOccurrences(of: " m", with: " metres")
    }

    /// "won 18 hexes, 9 from John" / "won 6 hexes, none from anyone" — the
    /// ground taken from people, by name; unclaimed ground is in the total.
    static func wonLine(_ change: LandgrabChange, name: (String?) -> String) -> String {
        let fromPeople = change.from.filter { $0.id != nil && $0.hexes > 0 }
        let takenTotal = fromPeople.isEmpty ? change.taken : fromPeople.reduce(0) { $0 + $1.hexes }
        var line = "won \(hexes(change.won))"
        if takenTotal > 0 {
            let names = fromPeople.sorted { $0.hexes > $1.hexes }.map { name($0.id) }
            line += names.isEmpty ? ", \(figure(takenTotal)) from others" : ", \(figure(takenTotal)) from \(list(names))"
        }
        return line
    }

    /// "Lee's walk · Sat 09:12 · 3.4 km · won 18 hexes, 9 from John".
    static func changeLine(_ change: LandgrabChange, label: String, name: (String?) -> String) -> String {
        [shortTime(change.activity?.startedAt ?? change.at), distance(change.activity?.distanceM), wonLine(change, name: name)]
            .compactMap { $0 }
            .reduce(label) { "\($0) · \($1)" }
    }

    /// The whole row for VoiceOver: "Lee's walk, Saturday 09:12, 3.4
    /// kilometres, closed a loop. Won 18 hexes: 9 from John, 6 nobody held."
    static func spokenChange(_ change: LandgrabChange, label: String, name: (String?) -> String) -> String {
        var head = [label]
        if let time = spokenTime(change.activity?.startedAt ?? change.at) { head.append(time) }
        if let distance = spokenDistance(change.activity?.distanceM) { head.append(distance) }
        if change.activity?.loop == true { head.append("closed a loop") }
        var parts: [String] = []
        for source in change.from.sorted(by: { $0.hexes > $1.hexes }) where source.hexes > 0 {
            parts.append(source.id == nil ? "\(figure(source.hexes)) nobody held" : "\(figure(source.hexes)) from \(name(source.id))")
        }
        let tail = parts.isEmpty ? "Won \(hexes(change.won))." : "Won \(hexes(change.won)): \(parts.joined(separator: ", "))."
        return head.joined(separator: ", ") + ". " + tail
    }

    /// What the map shows, for VoiceOver: "312 hexes changed hands this week,
    /// in 4 changes. Lee won the most, 120."
    static func mapSummary(_ changes: LandgrabChanges, weekLabel: String, name: (String?) -> String) -> String {
        let when = phrase(weekLabel)
        guard !changes.hexes.isEmpty else { return "Map. No ground changed hands \(when)." }
        var byPerson: [String: Int] = [:]
        for hex in changes.hexes { if let owner = hex.owner { byPerson[owner, default: 0] += 1 } }
        let count = changes.changes.count
        var text = "Map. \(hexes(changes.hexes.count)) changed hands \(when), in \(count == 1 ? "1 change" : "\(count) changes")."
        if let top = byPerson.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }) {
            text += " \(name(top.key)) won the most, \(figure(top.value))."
        }
        if changes.truncated { text += " Only the largest changes are shown." }
        return text
    }

    /// The changes in the order the list shows them: newest first, the
    /// unattributed ground last.
    static func ordered(_ changes: [LandgrabChange]) -> [LandgrabChange] {
        changes.enumerated().sorted { a, b in
            let ua = a.element.activity == nil, ub = b.element.activity == nil
            if ua != ub { return !ua }
            let da = a.element.at.flatMap(date(iso:)), db = b.element.at.flatMap(date(iso:))
            if let da, let db, da != db { return da > db }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// ISO 8601, with or without fractional seconds.
    static func date(iso: String) -> Date? {
        let fraction = ISO8601DateFormatter()
        fraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fraction.date(from: iso) { return date }
        return ISO8601DateFormatter().date(from: iso)
    }

    /// "Updated 14:05", London.
    static func updated(_ board: LandgrabBoard) -> String? {
        guard let raw = board.updatedAt, let date = date(iso: raw) else { return nil }
        return "Updated \(clock(date))"
    }
}

// MARK: - The map, worked out once

/// A region to fit the camera to: centre and spans, in degrees.
struct LandgrabRegion: Equatable {
    var centreLat: Double
    var centreLon: Double
    var latSpan: Double
    var lonSpan: Double

    /// Every point inside, with a margin (`pad` × the extent) and never
    /// tighter than `minSpan` — one hex fills the screen otherwise.
    static func fitting(_ points: [LandgrabPoint], pad: Double = 1.3, minSpan: Double = 0.004) -> LandgrabRegion? {
        guard let first = points.first else { return nil }
        var minLat = first.lat, maxLat = first.lat, minLon = first.lon, maxLon = first.lon
        for p in points.dropFirst() {
            minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
            minLon = min(minLon, p.lon); maxLon = max(maxLon, p.lon)
        }
        return LandgrabRegion(
            centreLat: (minLat + maxLat) / 2,
            centreLon: (minLon + maxLon) / 2,
            latSpan: min(180, max(minSpan, (maxLat - minLat) * pad)),
            lonSpan: min(360, max(minSpan, (maxLon - minLon) * pad))
        )
    }
}

/// Everything the map screen needs from one week's changes, decided once
/// when the week arrives — never in a view's `body`, which runs on every
/// selection and every frame of a camera move.
struct LandgrabMapPlan: Equatable {
    struct Shape: Equatable, Identifiable {
        let id: Int
        let points: [LandgrabPoint]
        let ownerId: String?
        let colour: LandgrabRGB
    }

    let shapes: [Shape]
    /// Change id → the hex ids it holds.
    let hexesByChange: [String: Set<Int>]
    /// Change id → its trace (may be empty).
    let traces: [String: [LandgrabPoint]]
    /// The whole week.
    let weekRegion: LandgrabRegion?
    /// Change id → the region that fits its hexes and its trace.
    let changeRegions: [String: LandgrabRegion]

    init(_ changes: LandgrabChanges) {
        var colours: [String: LandgrabRGB] = [:]
        for person in changes.people { colours[person.id] = LandgrabColour.resolve(person.colour, id: person.id) }
        let neutral = LandgrabRGB(hex: 0x8A7D6A)
        shapes = changes.hexes.map { hex in
            Shape(id: hex.id, points: hex.polygon, ownerId: hex.owner,
                  colour: hex.owner.map { colours[$0] ?? LandgrabColour.resolve(nil, id: $0) } ?? neutral)
        }
        let byId = Dictionary(changes.hexes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var hexesByChange: [String: Set<Int>] = [:]
        var traces: [String: [LandgrabPoint]] = [:]
        var regions: [String: LandgrabRegion] = [:]
        for change in changes.changes {
            let ids = Set(change.hexIds.filter { byId[$0] != nil })
            hexesByChange[change.id] = ids
            let trace = change.activity?.trace ?? []
            traces[change.id] = trace
            let corners = ids.flatMap { byId[$0]?.polygon ?? [] }
            if let region = LandgrabRegion.fitting(corners + trace) { regions[change.id] = region }
        }
        self.hexesByChange = hexesByChange
        self.traces = traces
        self.changeRegions = regions
        let all = changes.hexes.flatMap(\.polygon)
        weekRegion = LandgrabRegion.fitting(all.isEmpty ? (changes.bounds?.points ?? []) : all)
    }
}
