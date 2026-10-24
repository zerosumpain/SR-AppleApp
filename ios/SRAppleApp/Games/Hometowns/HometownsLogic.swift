import Foundation

// Hometowns, the family county game (SR-Main spec 2026-10-24 Hometowns, §9,
// §10.7, §10.9, §10.13). The engine, the economy and the map all live on the
// site: the map page (the wire's `client.page`, `/projects/hometowns/<pageHash>/mobile.html`) runs the
// same engine in a web view and predicts this phone's town tick by tick. The
// app is the shell around it — the top bar, the Wants bar, the toolbar and
// every sheet — and it holds the stream and posts the moves, because the page
// does no authenticated network.
//
// This file is the app's half of the contract, and nothing here imports UIKit
// or SwiftUI:
//   - the WIRE, decoded leniently into the parts the sheets read. A frame is
//     whole (`base: null`) or a delta cut against the frame this phone holds
//     at `rev` `base`; `HometownsFrames.merge` is the server's `applyFrame`
//     (src/lib/games/hometowns/wire.ts) written out again over JSON
//     dictionaries, and the whole frame it gives back is what is decoded.
//     The town is kept as the server sent it, never re-derived here.
//   - the COPY: the game's words come from the site's one copy file
//     (`hometowns-copy-en-GB.json`, a copy of engine/copy/en-GB.json), at two
//     levels, kid and adult, through the same small template grammar the
//     engine renders with (engine/copy.ts). Numbers are formatted by our own
//     arithmetic, as there, so a Why line reads the same on the page and here.
//   - the CATALOGUE the Build trays need: which tray a building sits in and
//     the tier that unlocks it. The wire says what is unlocked and what it
//     costs; an id this table does not know still shows, in the last tray.
//   - MOVES: every mutating move carries its own id (`planId` for a build,
//     `moveId` for the rest) so a repeat is answered from the server's log
//     rather than applied twice (A28).

// MARK: - Lenient decoding

/// A key by name, so each model reads exactly the fields it uses and ignores
/// the rest. The wire grows with every work package; a field this app does
/// not know is never a decode failure, and a field it expects but does not
/// get takes an obvious default.
struct HometownsKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ name: String) { stringValue = name }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

fileprivate extension KeyedDecodingContainer where K == HometownsKey {
    /// The value under `name`, or `fallback` when it is absent, null or the wrong shape.
    func ht<T: Decodable>(_ name: String, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: HometownsKey(name))) ?? fallback
    }

    /// An optional value: nil when absent, null or the wrong shape.
    func htMaybe<T: Decodable>(_ name: String) -> T? {
        (try? decodeIfPresent(T.self, forKey: HometownsKey(name))) ?? nil
    }

    /// A list where one malformed element drops only that element.
    func htList<T: Decodable>(_ name: String) -> [T] {
        ((try? decodeIfPresent([HometownsLossy<T>].self, forKey: HometownsKey(name))) ?? nil)?.compactMap(\.value) ?? []
    }
}

/// One element of a lossy list.
struct HometownsLossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// Any JSON value at all, read only to be counted.
struct HometownsIgnored: Decodable {
    init(from decoder: Decoder) throws {}
}

/// A card's or an inbox item's data value: the wire's `number | string`.
enum HometownsValue: Decodable, Equatable, Hashable {
    case number(Double)
    case text(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .text(s)
        } else if let b = try? c.decode(Bool.self) {
            self = .number(b ? 1 : 0)
        } else {
            self = .text("")
        }
    }

    var number: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    var text: String? {
        if case .text(let s) = self { return s }
        return nil
    }
}

typealias HometownsData = [String: HometownsValue]

// MARK: - The wire (§10.7)

/// A framework player row, with the seat once they have one.
struct HometownsPlayer: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let status: String
    let seat: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        id = try c.decode(String.self, forKey: HometownsKey("id"))
        name = c.ht("name", "Mayor")
        status = c.ht("status", "joined")
        seat = c.htMaybe("seat")
    }
}

/// Which page runs this county's engine: `page` is a path on the site, and
/// the app loads exactly that path. Its folder is the page's own hash (the
/// engine and the page code together, SR-Main §10.10), so a page-only change
/// is a new path; `engineHash` is the simulation's, for the canary.
struct HometownsClient: Decodable, Equatable {
    let engineHash: String
    let page: String
    let bridge: Int

    /// The page's folder: `<pageHash>` in `/projects/hometowns/<pageHash>/mobile.html`, or nil.
    var pageHash: String? {
        let parts = page.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0].isEmpty, parts[1] == "projects", parts[2] == "hometowns", parts[4] == "mobile.html" else { return nil }
        let hash = String(parts[3])
        guard !hash.isEmpty, hash.count <= 64, hash.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return hash
    }

    init(engineHash: String = "", page: String = "", bridge: Int = 1) {
        self.engineHash = engineHash; self.page = page; self.bridge = bridge
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        engineHash = c.ht("engineHash", "")
        page = c.ht("page", "")
        bridge = c.ht("bridge", 1)
    }
}

struct HometownsSeason: Decodable, Equatable {
    let n: Int
    let theme: String
    let day: Int
    let daysLeft: Int

    init(n: Int = 1, theme: String = "", day: Int = 0, daysLeft: Int = 0) {
        self.n = n; self.theme = theme; self.day = day; self.daysLeft = daysLeft
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        n = c.ht("n", 1)
        theme = c.ht("theme", "")
        day = c.ht("day", 0)
        daysLeft = c.ht("daysLeft", 0)
    }
}

/// The county clock. Every instant is server epoch ms.
struct HometownsClock: Decodable, Equatable {
    let gridTick: Int
    let tickMs: Double
    let nextTickAt: Double
    let nextRegionalDayAt: Double
    let nextGazetteAt: Double
    let paused: Bool
    let napping: Bool
    let season: HometownsSeason

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        gridTick = c.ht("gridTick", 0)
        tickMs = c.ht("tickMs", 1_800_000)
        nextTickAt = c.ht("nextTickAt", 0)
        nextRegionalDayAt = c.ht("nextRegionalDayAt", 0)
        nextGazetteAt = c.ht("nextGazetteAt", 0)
        paused = c.ht("paused", false)
        napping = c.ht("napping", false)
        season = c.ht("season", HometownsSeason())
    }
}

/// `key` names a copy entry; `data` fills its slots.
struct HometownsCard: Decodable, Equatable, Hashable {
    let key: String
    let data: HometownsData

    init(key: String, data: HometownsData = [:]) {
        self.key = key; self.data = data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        key = c.ht("key", "")
        data = c.ht("data", [:])
    }
}

/// A wants bubble (§5.15). `hatched` (A9): people want it, but no land can
/// reach what it needs yet.
struct HometownsWant: Decodable, Equatable, Identifiable {
    let key: String
    let severity: Double
    let tile: Int
    let hatched: Bool

    var id: String { key }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        key = c.ht("key", "")
        severity = c.ht("severity", 0)
        tile = c.ht("tile", -1)
        hatched = c.ht("hatched", false)
    }
}

/// An advisor card (§9.7): which mascot, the rule (copy `advisor.<key>`),
/// and its one action (`data.action`, copy `action.<action>`).
struct HometownsAdvisorCard: Decodable, Equatable, Identifiable {
    let advisor: String
    let key: String
    let data: HometownsData

    var id: String { key }
    var action: String? { data["action"]?.text }

    init(advisor: String, key: String, data: HometownsData = [:]) {
        self.advisor = advisor; self.key = key; self.data = data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        advisor = c.ht("advisor", "bramble")
        key = c.ht("key", "")
        data = c.ht("data", [:])
    }
}

struct HometownsNeedItem: Decodable, Equatable, Identifiable {
    let key: String
    /// The share of the tier it is met for, 0–1.
    let met: Double
    let buildable: Bool

    var id: String { key }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        key = c.ht("key", "")
        met = c.ht("met", 0)
        buildable = c.ht("buildable", false)
    }
}

/// One wealth tier's needs ladder (`tier` 0–2).
struct HometownsNeedRow: Decodable, Equatable, Identifiable {
    let cohort: Int
    let tier: Int
    let items: [HometownsNeedItem]

    var id: Int { tier }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        cohort = c.ht("cohort", 0)
        tier = c.ht("tier", 0)
        items = c.htList("items")
    }
}

/// A Town Talk line: the share of residents who say it.
struct HometownsTalk: Equatable, Identifiable {
    let key: String
    let pct: Double
    var id: String { key }
}

/// The month step's blackboard as shown (never predicted, never hashed).
struct HometownsDerived: Decodable, Equatable {
    /// Perceived stars, 0–100, in the engine's STAR layout: the 11 town stars first.
    let stars: [Double]
    /// Demand meters, METER order (homes £, ££, £££, shops, leisure, industry, offices, farms).
    let meters: [Double]
    let wants: [HometownsWant]
    let advisors: [HometownsAdvisorCard]
    let needs: [HometownsNeedRow]
    let pipelineHomes: Int
    let pipelineMovers: Int
    let townTalk: [HometownsTalk]

    static let empty = HometownsDerived()

    private init() {
        stars = []; meters = []; wants = []; advisors = []; needs = []
        pipelineHomes = 0; pipelineMovers = 0; townTalk = []
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        stars = c.ht("stars", [])
        meters = c.ht("meters", [])
        wants = c.htList("wants")
        advisors = c.htList("advisors")
        needs = c.htList("needs")
        let pipeline: [String: Double] = c.ht("pipeline", [:])
        pipelineHomes = Int(pipeline["homes"] ?? 0)
        pipelineMovers = Int(pipeline["movers"] ?? 0)
        // `[key, pct]` pairs on the wire.
        let talk: [[HometownsValue]] = c.ht("townTalk", [])
        townTalk = talk.compactMap { pair in
            guard pair.count == 2, let key = pair[0].text, let pct = pair[1].number else { return nil }
            return HometownsTalk(key: key, pct: pct)
        }
    }
}

/// What the viewer may build now, what things cost, and what can still be undone today.
struct HometownsAffordances: Decodable, Equatable {
    let unlocked: [String]
    let costs: [String: Double]
    let initiatives: Int
    let slots: Int
    let canUndo: [String]

    static let empty = HometownsAffordances(unlocked: [], costs: [:], initiatives: 0, slots: 0, canUndo: [])

    init(unlocked: [String], costs: [String: Double], initiatives: Int, slots: Int, canUndo: [String]) {
        self.unlocked = unlocked; self.costs = costs; self.initiatives = initiatives
        self.slots = slots; self.canUndo = canUndo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        unlocked = c.ht("unlocked", [])
        costs = c.ht("costs", [:])
        initiatives = c.ht("initiatives", 0)
        slots = c.ht("slots", 0)
        canUndo = c.ht("canUndo", [])
    }
}

/// What exact prediction needs beyond the town and snapshot (read by the page; shown here only as settings).
struct HometownsPredict: Decodable, Equatable {
    let townIndex: Int
    let dayIndex: Int
    let rivalry: String
    let mishaps: String
    let paramsVersion: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        townIndex = c.ht("townIndex", 0)
        dayIndex = c.ht("dayIndex", 0)
        rivalry = c.ht("rivalry", "friendly")
        mishaps = c.ht("mishaps", "mild")
        paramsVersion = c.ht("paramsVersion", "v1")
    }
}

/// One of this seat's logged moves, newest last (A28: a pending move whose id is here has landed).
struct HometownsMoveRecord: Decodable, Equatable {
    let id: String
    let type: String
    let atTick: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        id = c.ht("id", "")
        type = c.ht("type", "")
        atTick = c.ht("atTick", -1)
    }
}

struct HometownsInboxItem: Decodable, Equatable, Identifiable {
    let id: String
    let kind: String
    let day: Int
    let from: Int?
    let data: HometownsData

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        let kind: String = c.ht("kind", "")
        let day: Int = c.ht("day", 0)
        // Stable across decodes, so a row keeps its identity from frame to frame.
        id = c.ht("id", "\(kind).\(day)")
        self.kind = kind
        self.day = day
        from = c.htMaybe("from")
        data = c.ht("data", [:])
    }
}

/// A standing order (§5.18). Children switch them on and off; adults may change the thresholds.
struct HometownsOrder: Decodable, Equatable, Identifiable {
    let kind: String
    var on: Bool
    var args: [Double]

    var id: String { kind }

    init(kind: String, on: Bool, args: [Double]) {
        self.kind = kind; self.on = on; self.args = args
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        kind = c.ht("kind", "")
        on = c.ht("on", false)
        args = c.ht("args", [])
    }

    /// As the `orders` move sends it. Whole thresholds go as integers, so the
    /// server's bounds check sees the number the reader picked.
    var json: [String: Any] {
        ["kind": kind, "on": on, "args": args.map { $0 == $0.rounded() && abs($0) < 1e9 ? Int($0) as Any : $0 as Any }]
    }
}

/// One of today's plans (§9.3), undoable in full before the next Regional Day.
struct HometownsUndo: Decodable, Equatable, Identifiable {
    let planId: String
    let day: Int
    let atTick: Int
    let cost: Double

    var id: String { planId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        planId = c.ht("planId", "")
        day = c.ht("day", 0)
        atTick = c.ht("atTick", 0)
        cost = c.ht("cost", 0)
    }
}

/// Tax rates in basis points (A25): 800 is 8%. `homes` is per wealth tier.
struct HometownsTaxes: Decodable, Equatable {
    var town: Int
    var homes: [Int]
    var business: Int
    var sales: Int
    var hotel: Int

    init(town: Int = 800, homes: [Int] = [800, 800, 800], business: Int = 400, sales: Int = 200, hotel: Int = 500) {
        self.town = town; self.homes = homes; self.business = business; self.sales = sales; self.hotel = hotel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        town = c.ht("town", 800)
        homes = c.ht("homes", [800, 800, 800])
        business = c.ht("business", 400)
        sales = c.ht("sales", 200)
        hotel = c.ht("hotel", 500)
    }
}

/// The town's own money: only ever sent to its mayor.
struct HometownsMoney: Decodable, Equatable {
    let reserves: Double
    /// Index into RATINGS (AAA … B).
    let rating: Int
    let hasLoan: Bool
    let bonds: Int
    /// Helper Mode (§5.13): Kingsport is covering the shortfall.
    let helper: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        reserves = c.ht("reserves", 0)
        rating = c.ht("rating", 2)
        let loan: [String: Double]? = c.htMaybe("loan")
        hasLoan = loan != nil
        let bonds: [HometownsIgnored] = c.ht("bonds", [])
        self.bonds = bonds.count
        let helper: [String: Double]? = c.htMaybe("helper")
        self.helper = helper != nil
    }

    private init() {
        reserves = 0; rating = 2; hasLoan = false; bonds = 0; helper = false
    }

    /// A town record without its money (an older or partial frame): nothing to show yet.
    static let none = HometownsMoney()

    static let ratings = ["AAA", "AA", "A", "BBB", "BB", "B"]
    var ratingName: String { Self.ratings.indices.contains(rating) ? Self.ratings[rating] : "A" }
}

/// The viewer's own town: the parts of TownState the sheets read. The page
/// gets the whole record, untouched, from the frame itself.
struct HometownsTown: Decodable, Equatable {
    let seat: String
    let name: String
    let avatar: String
    let flag: Int
    let site: Int
    let siteKind: String
    /// Town ticks: a game week each, 4 to a month, 48 to a year.
    let tick: Int
    let sprintLeft: Int
    /// When the last founding week ran, server epoch ms (0 before the first).
    let sprintAt: Double
    let sprintAuto: Bool
    /// Null while the town is in its Founding Fortnight.
    let gridBase: Int?
    let archived: Bool
    let tier: Int
    let parcelRights: Int
    /// The 13 person stocks (stage × wealth tier, then students).
    let people: [Double]
    /// Happiness by the 10 cohorts.
    let happy: [Double]
    let approval: Double
    let money: HometownsMoney
    let taxes: HometownsTaxes
    /// Low 0 / Normal 1 / High 2 per FUNDING_KEYS.
    let funding: [Int]
    let orders: [HometownsOrder]
    let initiatives: Int
    let policies: Int
    let undo: [HometownsUndo]
    let lastSeenTick: Int
    /// The day's money so far: the sum of the day's ledger lines (£).
    let dayNet: Double
    /// Tiles still under construction.
    let building: Int
    let holidayUntil: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        seat = c.ht("seat", "")
        name = c.ht("name", "Your town")
        avatar = c.ht("avatar", "fox")
        flag = c.ht("flag", 0)
        site = c.ht("site", 0)
        siteKind = c.ht("siteKind", "flatland")
        tick = c.ht("tick", 0)
        sprintLeft = c.ht("sprintLeft", 0)
        sprintAt = c.ht("sprintAt", 0)
        sprintAuto = c.ht("sprintAuto", false)
        gridBase = c.htMaybe("gridBase")
        archived = c.ht("archived", false)
        tier = c.ht("tier", 0)
        parcelRights = c.ht("parcelRights", 0)
        people = c.ht("people", [])
        happy = c.ht("happy", [])
        approval = c.ht("approval", 0)
        money = c.ht("money", HometownsMoney.none)
        taxes = c.ht("taxes", HometownsTaxes())
        funding = c.ht("funding", Array(repeating: 1, count: HometownsCatalogue.fundingKeys.count))
        orders = c.htList("orders")
        initiatives = c.ht("initiatives", 0)
        let policies: [HometownsIgnored] = c.ht("policies", [])
        self.policies = policies.count
        undo = c.htList("undo")
        lastSeenTick = c.ht("lastSeenTick", 0)
        let books: HometownsBooks? = c.htMaybe("books")
        dayNet = (books?.dayLines ?? []).reduce(0, +)
        let construction: [Int] = c.ht("construction", [])
        building = construction.count / 2
        let holiday: [String: Double?] = c.ht("holiday", [:])
        holidayUntil = holiday["until"] ?? nil
    }

    var population: Int { Int(people.reduce(0, +)) }
    var inFortnight: Bool { gridBase == nil && !archived }
    var onHoliday: Bool { holidayUntil != nil }
}

/// The day's ledger lines (Books.dayLines, £ per LEDGER_LINES): their sum is the day's money so far.
struct HometownsBooks: Decodable {
    let dayLines: [Double]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        dayLines = c.ht("dayLines", [])
    }
}

/// What everyone may see of a town. Never money, bonds, orders or contract books.
struct HometownsPublicTown: Decodable, Equatable, Identifiable {
    let seat: String
    let name: String
    let avatar: String
    let flag: Int
    let tier: Int
    let pop: Int
    /// Persons by FACES (workers, professionals, families, retirees, students).
    let faces: [Int]
    /// The 11 town stars, 0–100.
    let stars: [Double]
    let holiday: Bool
    let archived: Bool
    let inFortnight: Bool
    let mayor: String
    let linked: [Int]

    var id: String { seat }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        seat = c.ht("seat", "")
        name = c.ht("name", "")
        avatar = c.ht("avatar", "fox")
        flag = c.ht("flag", 0)
        tier = c.ht("tier", 0)
        pop = c.ht("pop", 0)
        faces = c.ht("faces", [])
        stars = c.ht("stars", [])
        holiday = c.ht("holiday", false)
        archived = c.ht("archived", false)
        inFortnight = c.ht("inFortnight", false)
        mayor = c.ht("mayor", "")
        linked = c.ht("linked", [])
    }
}

/// A site around Kingsport; `owner` is a town index.
struct HometownsSite: Decodable, Equatable, Identifiable {
    let index: Int
    let kind: String
    let terrainSeed: Double
    let owner: Int?

    var id: Int { index }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        index = c.ht("index", 0)
        kind = c.ht("kind", "flatland")
        terrainSeed = c.ht("terrainSeed", 0)
        owner = c.htMaybe("owner")
    }
}

/// The county around the viewer. M1 reads the name, the sites, Kingsport and the Bulletin.
struct HometownsCountyWire: Decodable, Equatable {
    let name: String
    let sites: [HometownsSite]
    let kingsport: HometownsPublicTown?
    let bulletin: [HometownsCard]
    let fund: Double
    let links: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        name = c.ht("name", "Kingsport County")
        sites = c.htList("sites")
        kingsport = c.htMaybe("kingsport")
        bulletin = c.htList("bulletin")
        fund = c.ht("fund", 0)
        let links: [HometownsIgnored] = c.ht("links", [])
        self.links = links.count
    }
}

/// The viewer's own side of the frame.
struct HometownsMe: Decodable, Equatable {
    let seat: String
    let profile: String
    let isParent: Bool
    let townHash: String
    let town: HometownsTown?
    let derived: HometownsDerived
    let affordances: HometownsAffordances
    let inbox: [HometownsInboxItem]
    let welcomeBack: [HometownsCard]
    let predict: HometownsPredict?
    let moves: [HometownsMoveRecord]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        seat = c.ht("seat", "")
        profile = c.ht("profile", "adult")
        isParent = c.ht("isParent", false)
        townHash = c.ht("townHash", "")
        town = c.htMaybe("town")
        derived = c.ht("derived", HometownsDerived.empty)
        affordances = c.ht("affordances", HometownsAffordances.empty)
        inbox = c.htList("inbox")
        welcomeBack = c.htList("welcomeBack")
        predict = c.htMaybe("predict")
        moves = c.htList("moves")
    }

    var level: HometownsCopyLevel { profile == "kid" ? .kid : .adult }
}

/// Of a visit (planes and buildings, for the page), the app reads only whose town it is.
struct HometownsVisitSeat: Decodable {
    let seat: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        seat = try c.decode(String.self, forKey: HometownsKey("seat"))
    }
}

/// One whole frame, as the sheets read it.
struct HometownsWire: Decodable, Equatable {
    let id: String
    /// lobby | running | closed
    let phase: String
    let serverNow: Double
    let rev: Int
    let base: Int?
    let hostId: String
    let meId: String
    let players: [HometownsPlayer]
    let client: HometownsClient
    let clock: HometownsClock?
    let me: HometownsMe?
    let towns: [HometownsPublicTown]
    let county: HometownsCountyWire?
    /// The seat whose town this phone is visiting, if any.
    let visitingSeat: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: HometownsKey.self)
        id = try c.decode(String.self, forKey: HometownsKey("id"))
        phase = c.ht("phase", "lobby")
        serverNow = c.ht("serverNow", 0)
        rev = c.ht("rev", 0)
        base = c.htMaybe("base")
        hostId = c.ht("hostId", "")
        meId = c.ht("meId", "")
        players = c.htList("players")
        client = c.ht("client", HometownsClient())
        clock = c.htMaybe("clock")
        me = c.htMaybe("me")
        towns = c.htList("towns")
        county = c.htMaybe("county")
        let visiting: HometownsVisitSeat? = c.htMaybe("visiting")
        visitingSeat = visiting?.seat
    }

    var town: HometownsTown? { me?.town }
    var level: HometownsCopyLevel { me?.level ?? .adult }
    var isHost: Bool { !meId.isEmpty && meId == hostId }
    /// This phone's public card (faces, the public stars).
    var myCard: HometownsPublicTown? {
        guard let seat = me?.seat, !seat.isEmpty else { return nil }
        return towns.first { $0.seat == seat }
    }

    /// The sites a new town can still be founded on.
    var freeSites: [HometownsSite] { (county?.sites ?? []).filter { $0.owner == nil } }
}

// MARK: - Frames (§10.7: whole or delta)

/// The server's merge rule (`applyFrame` in src/lib/games/hometowns/wire.ts)
/// over JSON dictionaries. The phone keeps a few recent whole frames by `rev`,
/// so a frame cut against any of them merges; one cut against a rev it does
/// not hold is a gap, and the store reads the room whole.
enum HometownsFrames {
    static let meParts = ["derived", "affordances", "snapshot", "inbox", "predict", "moves", "welcomeBack"]
    static let topParts = ["county", "visiting"]

    struct Gap: Error, Equatable {
        let have: Int?
        let base: Int
    }

    /// A JSON number as an Int, whichever way JSONSerialization handed it over.
    static func int(_ value: Any?) -> Int? {
        if value is NSNull { return nil }
        if let n = value as? Int { return n }
        if let d = value as? Double, d.isFinite { return Int(d) }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    static func rev(_ frame: [String: Any]) -> Int? { int(frame["rev"]) }
    static func base(_ frame: [String: Any]) -> Int? { int(frame["base"]) }

    /// The whole frame `frame` stands for, given the whole frame held at its `base`.
    static func merge(_ held: [String: Any]?, _ frame: [String: Any]) throws -> [String: Any] {
        var out = frame
        out["base"] = NSNull()
        guard let base = base(frame) else {
            out["townsPatch"] = nil
            return out
        }
        guard let held, rev(held) == base else { throw Gap(have: held.flatMap(rev), base: base) }
        for k in topParts where frame[k] == nil { out[k] = held[k] }
        if frame["towns"] == nil {
            let cards = held["towns"] as? [[String: Any]] ?? []
            let patch = frame["townsPatch"] as? [Any] ?? []
            out["towns"] = cards.enumerated().map { index, card -> [String: Any] in
                guard index < patch.count, let fields = patch[index] as? [String: Any] else { return card }
                return card.merging(fields) { _, new in new }
            }
        }
        out["townsPatch"] = nil
        if let me = frame["me"] as? [String: Any] {
            let hm = held["me"] as? [String: Any] ?? [:]
            var merged = me
            for k in meParts where me[k] == nil { merged[k] = hm[k] }
            if me["town"] == nil {
                let town = hm["town"] as? [String: Any]
                if let delta = me["townDelta"] as? [String: Any] {
                    let changed = delta["changed"] as? [String: Any] ?? [:]
                    merged["town"] = (town ?? [:]).merging(changed) { _, new in new }
                } else if let town {
                    merged["town"] = town
                }
                merged["townDelta"] = nil
            }
            out["me"] = merged
        }
        return out
    }

    /// A whole frame (a dictionary) decoded for the sheets. Nil if it is not a frame at all.
    static func decode(_ whole: [String: Any]) -> HometownsWire? {
        guard JSONSerialization.isValidJSONObject(whole),
              let data = try? JSONSerialization.data(withJSONObject: whole) else { return nil }
        return try? JSONDecoder().decode(HometownsWire.self, from: data)
    }

    /// `{"room": …}` (a snapshot or an action's answer) or `{"type":"room","room": …}` (a stream frame): the room.
    static func room(in envelope: Data) -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: envelope) as? [String: Any] else { return nil }
        return object["room"] as? [String: Any]
    }
}

// MARK: - Copy (engine/copy.ts, ported)

enum HometownsCopyLevel: String, Equatable {
    case kid, adult
}

struct HometownsCopyEntry: Equatable {
    let kid: String
    let adult: String
    var kidLess: String? = nil
    var adultLess: String? = nil

    func pick(_ level: HometownsCopyLevel, sign: Double) -> String {
        if sign < 0, let less = level == .kid ? kidLess : adultLess { return less }
        return level == .kid ? kid : adult
    }
}

/// The game's words at two levels, from the site's copy file. An unknown key
/// says itself, so a gap is visible rather than blank.
final class HometownsCopy {
    let strings: [String: HometownsCopyEntry]

    init(strings: [String: HometownsCopyEntry]) {
        self.strings = strings
    }

    /// The copy file's JSON (`{_about, locale, version, strings: {key: {kid, adult, kidLess?, adultLess?}}}`).
    convenience init(json: Data) {
        var out: [String: HometownsCopyEntry] = [:]
        if let file = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
           let strings = file["strings"] as? [String: [String: String]] {
            for (key, e) in strings {
                guard let kid = e["kid"], let adult = e["adult"] else { continue }
                out[key] = HometownsCopyEntry(kid: kid, adult: adult, kidLess: e["kidLess"], adultLess: e["adultLess"])
            }
        }
        self.init(strings: out)
    }

    /// The bundled file, read once.
    static let shared: HometownsCopy = {
        guard let url = Bundle.main.url(forResource: "hometowns-copy-en-GB", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return HometownsCopy(strings: [:]) }
        return HometownsCopy(json: data)
    }()

    func has(_ key: String) -> Bool { strings[key] != nil }

    /// The words for `key` at `level`, filled from `data`. `sign` < 0 picks
    /// the "Less" wording where there is one. `<key>.kid` and `<key>.adult`
    /// name their own level, as in the engine.
    func say(_ key: String, _ level: HometownsCopyLevel, _ data: HometownsData = [:], sign: Double = 1) -> String {
        var k = key
        var lv = level
        if strings[k] == nil {
            if k.hasSuffix(".kid") { k = String(k.dropLast(4)); lv = .kid }
            else if k.hasSuffix(".adult") { k = String(k.dropLast(6)); lv = .adult }
        }
        guard let e = strings[k] else { return key }
        return fill(e.pick(lv, sign: sign), lv, data)
    }

    /// `say` for a screen: never the raw key. The site's copy can move ahead
    /// of the file this build bundles (a new advisor rule), and a child must
    /// not read "advisor.mo.newRule": a missing key is the last part of its
    /// name in plain words ("New rule").
    func line(_ key: String, _ level: HometownsCopyLevel, _ data: HometownsData = [:], sign: Double = 1) -> String {
        let s = say(key, level, data, sign: sign)
        guard s == key else { return s }
        return HometownsCatalogue.humanised(String(key.split(separator: ".").last ?? Substring(key)))
    }

    /// `say` when the key exists, else `fallback`.
    func say(_ key: String, _ level: HometownsCopyLevel, _ data: HometownsData = [:], or fallback: String) -> String {
        has(key) ? say(key, level, data) : fallback
    }

    /// Fills a template's `{name:fmt:arg1:arg2}` slots from `data`.
    func fill(_ template: String, _ level: HometownsCopyLevel, _ data: HometownsData = [:]) -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            let after = rest[rest.index(after: open)...]
            guard let close = after.firstIndex(of: "}"), let slot = Self.slot(after[..<close]) else {
                out += "{"
                rest = after
                continue
            }
            out += format(slot, data[slot.name], level)
            rest = after[after.index(after: close)...]
        }
        out += rest
        return out
    }

    struct Slot: Equatable {
        let name: String
        let fmt: String
        let arg1: String
        let arg2: String
    }

    /// The engine's slot pattern: a name of letters, digits and `_`; then
    /// optionally a format of letters, a first argument without `:` and a
    /// second argument that may hold anything but `}`.
    static func slot(_ body: Substring) -> Slot? {
        let parts = body.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        let nameOK = !parts[0].isEmpty && parts[0].allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" }
        guard nameOK else { return nil }
        let fmt = parts.count > 1 ? parts[1] : ""
        if parts.count > 1, fmt.isEmpty || !fmt.allSatisfy({ $0.isASCII && $0.isLetter }) { return nil }
        return Slot(name: parts[0], fmt: fmt, arg1: parts.count > 2 ? parts[2] : "", arg2: parts.count > 3 ? parts[3] : "")
    }

    private func format(_ slot: Slot, _ value: HometownsValue?, _ level: HometownsCopyLevel) -> String {
        if slot.fmt == "ref" {
            let member: String? = value.map {
                switch $0 {
                case .text(let s): return s
                case .number(let n): return HometownsNumber.plain(n)
                }
            }
            if let member, let e = strings["\(slot.arg1).\(member)"] { return e.pick(level, sign: 1) }
            // A kid never sees a raw value: an unknown reference reads as a neutral word.
            return level == .kid ? "something" : (member ?? "")
        }
        guard let value else { return level == .kid ? "some" : "?" }
        guard case .number(let v) = value else { return level == .kid ? "something" : (value.text ?? "") }
        guard v.isFinite else { return "?" }
        let N = HometownsNumber.self
        switch slot.fmt {
        case "", "n": return N.group(N.round(v))
        case "signed": return N.signed(v)
        case "money": return N.pounds(v)
        case "signedMoney":
            let r = N.round(v)
            return r > 0 ? "+" + N.pounds(r) : N.pounds(r)
        case "pct": return N.group(N.round(v * 100)) + "%"
        case "bp": return N.oneDecimal(v / 100) + "%"
        case "stars": return "★" + N.oneDecimal(N.round(max(0, min(100, v)) / 10) / 2)
        case "time": return N.time(ticks: v, level)
        case "ms": return N.realTime(ms: v)
        case "count":
            let r = N.round(v)
            return "\(N.group(r)) \(r == 1 || r == -1 ? slot.arg1 : slot.arg2)"
        default: return N.group(N.round(v))
        }
    }
}

// MARK: - Numbers (engine/num.ts and copy.ts, by arithmetic)

enum HometownsNumber {
    /// JavaScript's Math.round: halves go up, −2.5 → −2.
    static func round(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

    /// "£12,345" and "−£12,345".
    static func pounds(_ n: Double) -> String {
        let neg = n < 0
        var x = round(neg ? -n : n)
        guard x.isFinite, x < 1e15 else { return neg ? "−£…" : "£…" }
        var s = ""
        repeat {
            let part = x.truncatingRemainder(dividingBy: 1000)
            x = (x - part) / 1000
            let digits = String(Int(part))
            let padded = x > 0 ? String(repeating: "0", count: max(0, 3 - digits.count)) + digits : digits
            s = padded + (s.isEmpty ? "" : "," + s)
        } while x > 0
        return (neg ? "−£" : "£") + s
    }

    /// "12,345" and "−12,345".
    static func group(_ n: Double) -> String {
        let s = pounds(n)
        return s.hasPrefix("−") ? "−" + s.dropFirst(2) : String(s.dropFirst())
    }

    /// A data value as a copy reference member ("3", not "3.0").
    static func plain(_ n: Double) -> String {
        n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
    }

    static func signed(_ n: Double) -> String {
        let r = round(n)
        return r > 0 ? "+" + group(r) : group(r)
    }

    /// One decimal place at most (2.5, 3, −0.5).
    static func oneDecimal(_ x: Double) -> String {
        let r = round(x * 10)
        let neg = r < 0
        let a = neg ? -r : r
        let whole = (a / 10).rounded(.down)
        let tenth = Int(a.truncatingRemainder(dividingBy: 10))
        return (neg ? "−" : "") + group(whole) + (tenth != 0 ? ".\(tenth)" : "")
    }

    /// Game ticks as words: a tick is a week, four make a month, 48 a year.
    static func time(ticks: Double, _ level: HometownsCopyLevel) -> String {
        let t = max(0, round(ticks))
        if t < 4 { return t == 1 ? "a week" : "\(Int(t)) weeks" }
        if t < 48 {
            let m = round(t / 4)
            return m == 1 ? "a month" : "\(Int(m)) months"
        }
        let y = level == .kid ? round(t / 48) : round(t / 4.8) / 10
        return y == 1 ? "a year" : "\(level == .kid ? group(y) : oneDecimal(y)) years"
    }

    /// Real time as words, for "ready in" and "can afford it in".
    static func realTime(ms: Double) -> String {
        let min = round(max(0, ms) / 60000)
        if min < 1 { return "a moment" }
        if min < 90 { return min == 1 ? "about a minute" : "about \(Int(min)) minutes" }
        let h = round(min / 60)
        if h < 36 { return h == 1 ? "about an hour" : "about \(Int(h)) hours" }
        let d = round(h / 24)
        return d == 1 ? "about a day" : "about \(group(d)) days"
    }
}

// MARK: - What the shell shows

enum HometownsText {
    static let months = ["January", "February", "March", "April", "May", "June", "July",
                         "August", "September", "October", "November", "December"]

    /// "Year 12 · May": 48 ticks to a year, 4 to a month, counted from 1.
    static func date(tick: Int) -> String {
        let t = max(0, tick)
        return "Year \(t / 48 + 1) · \(months[(t % 48) / 4])"
    }

    /// Money for the top bar: in full for adults; a child sees "£171k", not
    /// six-figure arithmetic (§0).
    static func money(_ n: Double, _ level: HometownsCopyLevel) -> String {
        guard level == .kid else { return HometownsNumber.pounds(n) }
        let a = abs(n)
        let sign = n < 0 ? "−" : ""
        if a >= 1_000_000 { return "\(sign)£\(HometownsNumber.oneDecimal(a / 1_000_000))m" }
        if a >= 10_000 { return "\(sign)£\(Int(HometownsNumber.round(a / 1000)))k" }
        return HometownsNumber.pounds(n)
    }

    /// "2,340".
    static func people(_ n: Int) -> String { HometownsNumber.group(Double(n)) }

    /// A tax rate in basis points as a percentage: 850 → "8.5%".
    static func rate(_ bp: Int) -> String { HometownsNumber.oneDecimal(Double(bp) / 100) + "%" }

    /// A 0–100 star as halves out of five: 72 → 3.5.
    static func starHalves(_ star: Double) -> Double {
        HometownsNumber.round(max(0, min(100, star)) / 10) / 2
    }

    /// The town's mood, 0–100: happiness weighted by how many live in each cohort.
    static func mood(_ town: HometownsTown) -> Double {
        let p = town.people
        func at(_ i: Int) -> Double { p.indices.contains(i) ? p[i] : 0 }
        // COHORTS (wL fL rL wM fM rM wH fH rH s) from the PERSON stocks
        // (stage × 3 + tier: workers 0–2, parents 3–5, children 6–8, retirees 9–11, students 12).
        let weights = [at(0), at(3) + at(6), at(9), at(1), at(4) + at(7), at(10), at(2), at(5) + at(8), at(11), at(12)]
        var total = 0.0, weighted = 0.0
        for (i, w) in weights.enumerated() where town.happy.indices.contains(i) {
            total += w
            weighted += w * town.happy[i]
        }
        return total > 0 ? weighted / total : town.approval
    }

    /// The SF Symbol for a mood (there are no fear faces: the lowest is a grey cloud).
    static func moodSymbol(_ mood: Double) -> String {
        if mood >= 65 { return "face.smiling.inverse" }
        if mood >= 45 { return "face.smiling" }
        return "cloud"
    }

    /// The five faces' happiness, from the cohorts, weighted by head-count.
    static func faceHappiness(_ town: HometownsTown) -> [Double] {
        let p = town.people
        let h = town.happy
        func at(_ a: [Double], _ i: Int) -> Double { a.indices.contains(i) ? a[i] : 0 }
        func mean(_ pairs: [(Double, Double)]) -> Double {
            let w = pairs.reduce(0) { $0 + $1.0 }
            return w > 0 ? pairs.reduce(0) { $0 + $1.0 * $1.1 } / w : pairs.map(\.1).reduce(0, +) / Double(max(1, pairs.count))
        }
        return [
            mean([(at(p, 0), at(h, 0)), (at(p, 1), at(h, 3))]),
            at(h, 6),
            mean([(at(p, 3) + at(p, 6), at(h, 1)), (at(p, 4) + at(p, 7), at(h, 4)), (at(p, 5) + at(p, 8), at(h, 7))]),
            mean([(at(p, 9), at(h, 2)), (at(p, 10), at(h, 5)), (at(p, 11), at(h, 8))]),
            at(h, 9),
        ]
    }
}

// MARK: - The catalogue (engine/content.ts, the parts the trays need)

/// A build tool, as the page's `tool({kind, id, variant, rot})` takes it.
struct HometownsTool: Equatable, Hashable {
    /// none | road | upgrade | zone | dezone | place | bulldoze | eraser | parcel
    let kind: String
    var id: String? = nil
    var variant: String? = nil
    var rot: Int? = nil

    static let none = HometownsTool(kind: "none")

    var json: [String: Any] {
        var out: [String: Any] = ["kind": kind]
        if let id { out["id"] = id }
        if let variant { out["variant"] = variant }
        if let rot { out["rot"] = rot }
        return out
    }
}

/// One thing in a Build tray: its cost, and why it is locked if it is.
struct HometownsBuildItem: Equatable, Identifiable {
    let id: String
    let tray: String
    let label: String
    let tool: HometownsTool
    /// £ to build (per tile for roads); nil for painting and clearing, which are free.
    let cost: Double?
    let locked: String?
}

enum HometownsCatalogue {
    /// The Build menu's trays (§9.3), by copy id (`tray.<id>`).
    static let trays = ["roads", "zones", "powerWater", "safety", "learning", "health", "fun", "cultureVisitors", "transport", "landmarks"]

    /// Each catalogue building's tray and the tier it unlocks at (content.ts BUILDINGS).
    static let buildings: [(id: String, tray: String, tier: Int)] = [
        ("busDepot", "transport", 2), ("busStop", "transport", 2), ("railStation", "transport", 3),
        ("freightYard", "transport", 3), ("harbour", "transport", 2), ("airfield", "transport", 3),
        ("well", "powerWater", 0), ("windmill", "powerWater", 0), ("generator", "powerWater", 1),
        ("waterTower", "powerWater", 1), ("windTurbine", "powerWater", 2), ("coalPlant", "powerWater", 2),
        ("gasPlant", "powerWater", 2), ("pumpingStation", "powerWater", 2), ("solarFarm", "powerWater", 3),
        ("waterWorks", "powerWater", 3),
        ("constablePost", "safety", 1), ("policeStation", "safety", 2), ("fireVolunteers", "safety", 1),
        ("fireStation", "safety", 2),
        ("surgery", "health", 1), ("healthCentre", "health", 2), ("hospital", "health", 3),
        ("schoolHouse", "learning", 0), ("villageSchool", "learning", 1), ("primarySchool", "learning", 2),
        ("secondarySchool", "learning", 2), ("library", "learning", 2), ("university", "learning", 3),
        ("villageGreen", "fun", 0), ("pocketPark", "fun", 0), ("park", "fun", 1), ("playground", "fun", 1),
        ("sportsPitches", "fun", 2), ("swimmingPool", "fun", 2), ("cinema", "fun", 2), ("youthClub", "fun", 2),
        ("stadium", "fun", 3),
        ("communityHall", "cultureVisitors", 1), ("viewpoint", "cultureVisitors", 1),
        ("botanicGarden", "cultureVisitors", 2), ("museum", "cultureVisitors", 2), ("theatre", "cultureVisitors", 3),
        ("clockTower", "landmarks", 3), ("grandPier", "landmarks", 3), ("townLandmark", "landmarks", 4),
    ]

    /// Drawn roads: lane, street and avenue, and rail from a City (`road:<id>` in affordances).
    static let roads: [(id: String, tier: Int)] = [("lane", 0), ("street", 1), ("avenue", 2), ("rail", 3)]

    /// Zones and the tier each opens at (content.ts ZONE_DEFS).
    static let zones: [(id: String, tier: Int)] = [("homes", 0), ("shops", 0), ("farms", 0), ("industry", 0), ("leisure", 2), ("offices", 2)]

    /// The lenses (§9.4): a Hamlet has Happy and Land value; a Village has all 14.
    static let lenses = ["happy", "landValue", "pollution", "noise", "safety", "schools", "health", "fun",
                         "culture", "traffic", "utilities", "jobs", "visitors", "desirability"]

    static func lenses(forTier tier: Int) -> [String] {
        tier >= 1 ? lenses : Array(lenses.prefix(2))
    }

    /// FUNDING_KEYS, and the Hamlet's three dials over them.
    static let fundingKeys = ["police", "fire", "health", "education", "fun", "culture", "transit", "roads", "utilities"]
    static let fundingGroups: [(id: String, keys: [String])] = [
        ("safety", ["police", "fire"]), ("learning", ["health", "education"]), ("fun", ["fun", "culture"]),
    ]

    /// Mayor avatars for the Founding sheet (copy `avatar.<id>`), and each one's symbol.
    static let avatars = ["fox", "owl", "rabbit", "squirrel", "duck", "mole", "deer", "robin", "frog", "puffin", "mouse", "heron"]

    /// Flag colours by `flag` (copy `flag.<n>`): poppy, sunny, meadow, sea, heather, fox, blossom, chalk.
    static let flagColours: [UInt32] = [0xD6463A, 0xF2C230, 0x5BA35B, 0x2F7FC1, 0x8E5BB5, 0xE07B2E, 0xEE8FB5, 0xF4F0E6]

    /// The two halves of a town name (content.ts NAME_FIRST and NAME_SECOND,
    /// append-only there): the server refuses any other half.
    static let nameFirst = ["Sunny", "Oak", "Elm", "Brook", "Meadow", "Fox", "Willow", "Ash", "Bramble", "Kestrel", "Hazel",
                            "Otter", "Clover", "Heather", "Mill", "Stone", "Bluebell", "Primrose", "Badger", "Pebble", "Puffin",
                            "Thistle", "Honey", "Maple", "Orchard", "Copper", "Swan", "Acorn", "Bracken", "Cherry", "Salt", "Lark"]
    static let nameSecond = ["vale", "ridge", "field", "ford", "bury", "wick", "by", "mouth", "stead", "ton", "hollow", "dale",
                             "cliff", "bridge", "haven", "combe", "well", "green", "wood", "port", "minster", "thorpe", "gate",
                             "hill", "moor", "leigh", "holme", "end"]

    /// Tier populations, for "Unlocks at Town: 2,000 people" (content.ts TIER_DEFS; a retune shows up as a stale
    /// number here, never as a wrong unlock: the server decides what is unlocked).
    static let tierPopulation = [0, 300, 2000, 15000, 80000]


    /// Every Build item for this town, tray by tray, from what the wire says is unlocked and what it costs.
    static func items(_ affordances: HometownsAffordances, town: HometownsTown?, copy: HometownsCopy, level: HometownsCopyLevel) -> [HometownsBuildItem] {
        let unlocked = Set(affordances.unlocked)
        let tier = town?.tier ?? 0
        var out: [HometownsBuildItem] = []
        func lock(_ need: Int, open: Bool) -> String? {
            open ? nil : lockReason(need, copy: copy, level: level)
        }
        for road in roads {
            let key = "road:\(road.id)"
            out.append(HometownsBuildItem(
                id: key, tray: "roads", label: copy.say("roadName.\(road.id)", level, or: road.id.capitalized),
                tool: HometownsTool(kind: "road", variant: road.id), cost: affordances.costs[key],
                locked: lock(max(road.tier, tier + 1), open: unlocked.contains(key))))
        }
        for road in roads where road.id == "street" || road.id == "avenue" {
            let key = "road:\(road.id)"
            let name = copy.say("roadName.\(road.id)", level, or: road.id.capitalized)
            out.append(HometownsBuildItem(
                id: "upgrade:\(road.id)", tray: "roads", label: "Upgrade to \(name.lowercased())",
                tool: HometownsTool(kind: "upgrade", variant: road.id), cost: affordances.costs[key],
                locked: lock(max(road.tier, tier + 1), open: unlocked.contains(key))))
        }
        out.append(HometownsBuildItem(id: "bulldoze", tray: "roads", label: level == .kid ? "Clear away" : "Bulldoze",
                                      tool: HometownsTool(kind: "bulldoze"), cost: nil, locked: nil))
        for zone in zones {
            let key = "zone:\(zone.id)"
            out.append(HometownsBuildItem(
                id: key, tray: "zones", label: copy.say("zoneName.\(zone.id)", level, or: zone.id.capitalized),
                tool: HometownsTool(kind: "zone", variant: zone.id), cost: nil,
                locked: unlocked.contains(key) ? nil : (tier < zone.tier ? lockReason(zone.tier, copy: copy, level: level)
                                                         : (level == .kid ? "Not any more" : "New zones of this kind have stopped"))))
        }
        out.append(HometownsBuildItem(id: "dezone", tray: "zones", label: level == .kid ? "Rub out paint" : "Clear zoning",
                                      tool: HometownsTool(kind: "dezone"), cost: nil, locked: nil))
        if let rights = town?.parcelRights, rights > 0 {
            out.append(HometownsBuildItem(id: "parcel", tray: "zones", label: "Open new land (\(rights) left)",
                                          tool: HometownsTool(kind: "parcel"), cost: nil, locked: nil))
        }
        let known = Set(buildings.map(\.id))
        for b in buildings where affordances.costs[b.id] != nil || unlocked.contains(b.id) {
            out.append(HometownsBuildItem(
                id: b.id, tray: b.tray, label: copy.say("buildingName.\(b.id)", level, or: humanised(b.id)),
                tool: HometownsTool(kind: "place", id: b.id, rot: 0), cost: affordances.costs[b.id],
                locked: lock(max(b.tier, tier + 1), open: unlocked.contains(b.id))))
        }
        // A building a newer site added: shown, in the last tray, with what the wire says.
        let roadKeys = Set(roads.map { "road:\($0.id)" })
        let extra = Set(affordances.costs.keys).union(unlocked)
            .filter { !known.contains($0) && !roadKeys.contains($0) && !$0.hasPrefix("zone:") && !$0.hasPrefix("road:") }
            .sorted()
        for id in extra {
            out.append(HometownsBuildItem(
                id: id, tray: "landmarks", label: copy.say("buildingName.\(id)", level, or: humanised(id)),
                tool: HometownsTool(kind: "place", id: id, rot: 0), cost: affordances.costs[id],
                locked: unlocked.contains(id) ? nil : (level == .kid ? "Not yet" : "Not unlocked yet")))
        }
        return out
    }

    /// "Unlocks at Town: 2,000 people".
    static func lockReason(_ tier: Int, copy: HometownsCopy, level: HometownsCopyLevel) -> String {
        let t = min(max(tier, 1), tierPopulation.count - 1)
        let data: HometownsData = ["tier": .number(Double(t)), "pop": .number(Double(tierPopulation[t]))]
        if copy.has("lock.unlocksAt") { return copy.say("lock.unlocksAt", level, data) }
        return "Unlocks at \(tierName(t)): \(HometownsText.people(tierPopulation[t])) people"
    }

    static func tierName(_ tier: Int) -> String {
        ["Hamlet", "Village", "Town", "City", "Metropolis"][min(max(tier, 0), 4)]
    }

    /// "schoolHouse" → "School house".
    static func humanised(_ id: String) -> String {
        var out = ""
        for ch in id {
            if ch.isUppercase, !out.isEmpty { out += " " + ch.lowercased() } else { out.append(ch) }
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }
}

// MARK: - Moves (§10.6)

/// The body of one move, as the act endpoint takes it: `action` plus the
/// engine's own fields. Bodies are dictionaries because a plan's ops arrive
/// from the page as JSON and go back to the server as the page wrote them.
struct HometownsMove {
    let action: String
    var fields: [String: Any] = [:]

    /// The client id that makes the move idempotent (A28): planId or moveId.
    var clientId: String? { fields["planId"] as? String ?? fields["moveId"] as? String }

    /// The JSON the act endpoint gets, with the frame this phone holds as
    /// `since` so the answer is a delta.
    func body(since: Int?) -> Data? {
        var out = fields
        out["action"] = action
        if let since { out["since"] = since }
        guard JSONSerialization.isValidJSONObject(out) else { return nil }
        return try? JSONSerialization.data(withJSONObject: out)
    }

    /// A fresh id for a move: short, letters and digits only (the page's id rule).
    static func newId(_ prefix: String) -> String {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "\(prefix)\(raw.prefix(16))"
    }

    static func hello() -> HometownsMove { HometownsMove(action: "hello") }

    static func seen(tick: Int) -> HometownsMove { HometownsMove(action: "seen", fields: ["tick": tick]) }

    static func sprint(auto: Bool = false) -> HometownsMove {
        var fields: [String: Any] = ["moveId": newId("s")]
        if auto { fields["auto"] = true }
        return HometownsMove(action: "sprint", fields: fields)
    }

    /// Build a whole plan (§9.3): one atomic move of up to 60 ops, by the page's planId.
    static func build(planId: String, ops: [Any]) -> HometownsMove {
        HometownsMove(action: "build", fields: ["planId": planId, "plan": ops])
    }

    static func undo(planId: String) -> HometownsMove {
        HometownsMove(action: "undo", fields: ["moveId": newId("u"), "planId": planId])
    }

    /// `taxes` in basis points; `funding` Low 0 / Normal 1 / High 2 by service or Hamlet group.
    static func budget(taxes: [String: Any]? = nil, funding: [String: Int]? = nil) -> HometownsMove {
        var fields: [String: Any] = ["moveId": newId("b")]
        if let taxes { fields["taxes"] = taxes }
        if let funding { fields["funding"] = funding }
        return HometownsMove(action: "budget", fields: fields)
    }

    static func orders(_ orders: [HometownsOrder]) -> HometownsMove {
        HometownsMove(action: "orders", fields: ["moveId": newId("o"), "orders": orders.map(\.json)])
    }

    /// Found a town: preset halves for everyone; a typed name only from an adult (the server decides).
    static func found(site: Int, nameParts: (String, String)?, name: String?, avatar: String, flag: Int) -> HometownsMove {
        var fields: [String: Any] = ["moveId": newId("f"), "site": site, "avatar": avatar, "flag": flag]
        if let nameParts { fields["nameParts"] = [nameParts.0, nameParts.1] }
        if let name { fields["name"] = name }
        return HometownsMove(action: "found", fields: fields)
    }

    static func pause(_ on: Bool) -> HometownsMove {
        HometownsMove(action: "pause", fields: ["moveId": newId("p"), "on": on])
    }

    /// Parent settings (§9.13): county fields and/or one seat's.
    static func settings(county: [String: Any]? = nil, seat: [String: Any]? = nil) -> HometownsMove {
        var fields: [String: Any] = ["moveId": newId("g")]
        if let county { fields["county"] = county }
        if let seat { fields["seat"] = seat }
        return HometownsMove(action: "settings", fields: fields)
    }

    static func visit(_ seat: String?) -> HometownsMove {
        HometownsMove(action: "visit", fields: ["seat": seat.map { $0 as Any } ?? NSNull()])
    }

    /// The page's telemetry, relayed (§10.15): logged on the server, never stored.
    static func stats(_ message: [String: Any]) -> HometownsMove {
        var fields: [String: Any] = [:]
        for key in ["fps", "minFps", "simMs", "thermal", "canary"] where message[key] != nil && !(message[key] is NSNull) {
            fields[key] = message[key]
        }
        return HometownsMove(action: "stats", fields: fields)
    }

    /// Moves the server answers from its log when repeated, so the store may
    /// post them again after a lost write (A28). `hello`, `seen` and `visit`
    /// change nothing worth repeating.
    var isPending: Bool { clientId != nil && action != "stats" }
}

/// The Regional Day is still finishing (A19): the move is retried after a second.
enum HometownsRetry {
    static let sentence = "Kingsport is just finishing the day"
    static func matches(_ text: String) -> Bool { text.hasPrefix(sentence) }
}

// MARK: - The page's messages (§10.9 page → app)

/// The forecast card's numbers (§9.8): p10–p90 ranges as [p10, p50, p90].
struct HometownsForecast: Equatable {
    let seeds: Int
    let cost: Double
    let upkeep: Double
    let monthly: [Double]
    let people: [Double]
    /// Per FACE: [p10, p50, p90].
    let happy: [[Double]]
    let months: Int
    let readyTicks: Int
    let readyMs: Double
    let exactForMs: Double
    let refused: String?

    init?(_ d: [String: Any]?) {
        guard let d else { return nil }
        func num(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
        func nums(_ v: Any?) -> [Double] { (v as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.doubleValue } }
        seeds = Int(num("seeds"))
        cost = num("cost")
        upkeep = num("upkeep")
        monthly = nums(d["monthly"])
        people = nums(d["people"])
        happy = (d["happy"] as? [Any] ?? []).map(nums)
        months = Int(num("months"))
        readyTicks = Int(num("readyTicks"))
        readyMs = num("readyMs")
        exactForMs = num("exactForMs")
        refused = d["refused"] as? String
    }

    /// The low and high ends of a range (p10, p90).
    static func ends(_ r: [Double]) -> (Double, Double) {
        guard r.count >= 3 else { return (r.first ?? 0, r.last ?? 0) }
        return (r[0], r[2])
    }

    /// Beyond the next Regional Day the snapshot is held fixed: "after tomorrow: estimate".
    var isEstimate: Bool { readyMs > exactForMs }
}

/// The plan the page is holding, with its forecast once one is in.
struct HometownsPlan: Equatable {
    let planId: String
    let ops: Int
    let cost: Double
    let forecast: HometownsForecast?
}

/// The inspector card (§9.5), drawn by SwiftUI from what the page worked out.
struct HometownsInspect: Equatable, Identifiable {
    let tile: Int
    let title: String
    let kind: String
    let level: Int?
    let tier: Int?
    let who: String?
    let mood: String?
    let wants: [String]
    let landValue: Double?
    let landTerms: [(String, Double)]
    let growLine: String?
    /// The ghost plan "What would make it grow?" drops, as the page sent it.
    let growPlan: [Any]?

    var id: Int { tile }

    init?(_ m: [String: Any]) {
        guard let card = m["card"] as? [String: Any] else { return nil }
        tile = (m["tile"] as? NSNumber)?.intValue ?? -1
        title = card["title"] as? String ?? "Here"
        kind = card["kind"] as? String ?? "land"
        level = (card["level"] as? NSNumber)?.intValue
        tier = (card["tier"] as? NSNumber)?.intValue
        who = card["who"] as? String
        mood = card["mood"] as? String
        wants = card["wants"] as? [String] ?? []
        let lv = card["landValue"] as? [String: Any]
        landValue = (lv?["value"] as? NSNumber)?.doubleValue
        landTerms = (lv?["terms"] as? [[Any]] ?? []).compactMap { pair in
            guard pair.count == 2, let label = pair[0] as? String, let amount = (pair[1] as? NSNumber)?.doubleValue else { return nil }
            return (label, amount)
        }
        growLine = card["growLine"] as? String
        growPlan = card["growPlan"] as? [Any]
    }

    static func == (a: HometownsInspect, b: HometownsInspect) -> Bool {
        a.tile == b.tile && a.title == b.title && a.kind == b.kind && a.level == b.level && a.who == b.who
            && a.wants == b.wants && a.landValue == b.landValue && a.growLine == b.growLine
    }
}

// MARK: - Bramble's three steps (§1.5 step 2)

/// How far the founding tutorial has got, counted from the plans this phone
/// has built: a lane from the County Road, 12 Homes tiles, 2 Farms and a
/// Well. The page draws the arrows; this decides which line Bramble says.
struct HometownsTutorial: Equatable, Codable {
    var roads = 0
    var homes = 0
    var farms = 0
    var well = false

    /// Count a committed plan's ops.
    mutating func note(_ ops: [Any]) {
        for raw in ops {
            guard let op = raw as? [String: Any], let kind = op["op"] as? String else { continue }
            switch kind {
            case "road": roads += 1
            case "zone":
                let rect = (op["rect"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.intValue }
                let tiles = rect.count == 4 ? max(0, rect[2]) * max(0, rect[3]) : 0
                if op["zone"] as? String == "homes" { homes += tiles }
                if op["zone"] as? String == "farms" { farms += tiles }
            case "place":
                if op["id"] as? String == "well" { well = true }
            default: break
            }
        }
    }

    /// The step Bramble is on: 0 the road, 1 homes, 2 farms and a well, 3 done.
    var step: Int {
        if roads == 0 { return 0 }
        if homes < 12 { return 1 }
        if farms < 2 || !well { return 2 }
        return 3
    }

    /// Bramble's line for this step, and the line under it.
    func lines(_ copy: HometownsCopy, _ level: HometownsCopyLevel) -> (String, String?) {
        switch step {
        case 0: return (copy.say("tutorial.hello", level), copy.say("tutorial.road", level))
        case 1:
            let more = copy.say("tutorial.homesMore", level, ["n": .number(Double(12 - homes))])
            return (homes == 0 ? copy.say("tutorial.homes", level) : more, copy.say("tutorial.ghosts", level))
        case 2:
            return (farms < 2 ? copy.say("tutorial.farms", level) : copy.say("tutorial.well", level), copy.say("tutorial.buildIt", level))
        default:
            return (copy.say("tutorial.farmsDone", level), nil)
        }
    }
}

// MARK: - The new-county sheet (§10.12 F7)

/// The create request's `county` option. The server bounds every field
/// itself; the Regional Day's hour must sit inside the push hours (08–19).
struct HometownsCountySetup: Encodable, Equatable {
    var name: String = "Kingsport County"
    var rivalry: String = "friendly"
    var regionalHour: Int = 18
    var mishaps: String = "mild"

    static let hours = Array(8...19)

    static func hourLabel(_ hour: Int) -> String { String(format: "%02d:00", hour) }

    /// One line under the settings.
    var line: String {
        let rivals = rivalry == "spirited" ? "Spirited: towns compete a little harder for newcomers." : "Friendly: towns grow side by side."
        return "\(rivals) The Regional Day is at \(Self.hourLabel(regionalHour)) each day."
    }
}
