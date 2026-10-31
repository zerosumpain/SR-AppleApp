import Foundation

// Azul's wire pieces and the little the phone works out itself — which wall
// square is which colour, which lines are lit for a colour, how many tiles
// would fit and how many would fall, what the floor costs, the bonuses in
// words — as pure values, so each is a unit test. The server keeps the bag,
// judges every take and scores every round; nothing here decides a move.
//
// The wire is SR-Main's `toWire` in `src/lib/games/azul.ts` (spec
// docs/superpowers/specs/2026-10-31-family-games-azul.md). Nothing in Azul is
// hidden: every phone (and the TV board) gets the same table, and only the
// player whose turn it is is sent `canPlace`, the lines each colour on offer
// may go on. The phone lights exactly those, so it never needs the rules.
//
// Tile ids are stable for the whole game (0–99; the first-player marker is
// 100), which is what lets the board fly a tile from where it was to where
// it is now.
//
// Foundation only, so it runs in `scripts/home-check.sh` on Linux. The room's
// Azul side is decoded whole into `AzulState`, read off the same JSON as
// `GameRoom` (`GameRoom.azul`).

/// Where an Azul room is. `scoring` is Azul's own: the pause after a round is
/// tiled, while the table watches the walls fill.
enum AzulPhase: String, Equatable {
    case lobby, countdown, playing, scoring, finished, closed, unknown

    static func from(_ raw: String?) -> AzulPhase {
        guard let raw else { return .unknown }
        return AzulPhase(rawValue: raw) ?? .unknown
    }
}

/// Whether the host set the game up for a TV board. Either way every phone
/// shows the whole table; `tv` only leads with "Show on TV" and keeps the
/// others' boards a tap away.
enum AzulTable: String, CaseIterable, Identifiable, Equatable {
    case phones, tv

    var id: String { rawValue }

    static func from(_ raw: String?) -> AzulTable { raw == "tv" ? .tv : .phones }

    /// The new-game sheet's words.
    var label: String {
        switch self {
        case .phones: return "Phones only"
        case .tv: return "TV board"
        }
    }

    var line: String {
        switch self {
        case .phones: return "Everyone plays on their phone. Each phone shows every board."
        case .tv: return "The table on the TV too, for everyone to watch. Pair it from the lobby."
        }
    }
}

/// Where a take comes from: one factory (its index) or the centre.
enum AzulSource: Hashable {
    case factory(Int)
    case centre

    /// "factory 2", "the centre".
    var spoken: String {
        switch self {
        case .factory(let i): return "factory \(i + 1)"
        case .centre: return "the centre"
        }
    }
}

/// Where tiles are laid: a pattern line (0–4) or the floor.
enum AzulLine: Hashable {
    case line(Int)
    case floor

    var spoken: String {
        switch self {
        case .line(let i): return "line \(i + 1)"
        case .floor: return "the floor"
        }
    }
}

/// A JSON value that is a whole number or a string: `source` (`"centre"` or a
/// factory index) and `line` (an index or `"floor"`).
private enum AzulWireSpot: Decodable {
    case index(Int)
    case name(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            self = .index(i)
        } else {
            self = .name(try c.decode(String.self))
        }
    }

    var source: AzulSource? {
        switch self {
        case .index(let i): return i >= 0 ? .factory(i) : nil
        case .name(let n): return n == "centre" || n == "center" ? .centre : nil
        }
    }

    var line: AzulLine? {
        switch self {
        case .index(let i): return (0..<5).contains(i) ? .line(i) : nil
        case .name(let n): return n == "floor" ? .floor : nil
        }
    }
}

/// One tile: its id for the whole game and its colour. On a floor `c` may be
/// `"first"`: the first-player marker.
struct AzulTile: Decodable, Equatable, Identifiable, Hashable {
    let id: Int
    let c: String

    init(id: Int, c: String) {
        self.id = id
        self.c = c
    }

    private enum CodingKeys: String, CodingKey { case id, c }

    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        id = try k.decode(Int.self, forKey: .id)
        c = (try? k.decodeIfPresent(String.self, forKey: .c)) ?? "white"
    }

    var isMarker: Bool { c == AzulRules.marker }
}

/// One player's board: pattern lines, wall, floor and score.
struct AzulBoard: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    /// invited | joined | declined | left
    let status: String
    let isHost: Bool
    /// Turn order once play starts; nil before, or for somebody not seated.
    let seat: Int?
    let score: Int
    /// Their clock ran out last turn: the server is moving for them.
    let away: Bool
    /// Five lines; line i holds up to i + 1 tiles of one colour.
    let lines: [[AzulTile]]
    /// 5×5: the id of the tile on each square, or nil. The colour is the square's.
    let wall: [[Int?]]
    let floor: [AzulTile]
    /// What the floor costs right now, as a positive number.
    let floorPenalty: Int
    /// Complete wall rows.
    let rows: Int
    /// The first-player marker is on their floor.
    let hasFirst: Bool

    init(id: String, name: String, status: String = "joined", isHost: Bool = false, seat: Int? = 0, score: Int = 0,
         away: Bool = false, lines: [[AzulTile]] = [], wall: [[Int?]] = [], floor: [AzulTile] = []) {
        self.id = id; self.name = name; self.status = status; self.isHost = isHost; self.seat = seat
        self.score = score; self.away = away
        let squares = AzulBoard.fullWall(wall)
        self.lines = AzulBoard.fiveLines(lines)
        self.wall = squares
        self.floor = floor
        self.floorPenalty = AzulRules.floorPenalty(count: floor.count)
        self.rows = squares.filter { $0.allSatisfy { $0 != nil } }.count
        self.hasFirst = floor.contains { $0.isMarker }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, status, isHost, seat, score, away, lines, wall, floor, floorPenalty, rows, hasFirst
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Player"
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "joined"
        isHost = (try? c.decodeIfPresent(Bool.self, forKey: .isHost)) ?? false
        seat = (try? c.decodeIfPresent(Int.self, forKey: .seat)) ?? nil
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        away = (try? c.decodeIfPresent(Bool.self, forKey: .away)) ?? false
        lines = AzulBoard.fiveLines((try? c.decodeIfPresent([[AzulTile]].self, forKey: .lines)) ?? [])
        let squares = AzulBoard.fullWall((try? c.decodeIfPresent([[Int?]].self, forKey: .wall)) ?? [])
        let items = (try? c.decodeIfPresent([AzulTile].self, forKey: .floor)) ?? []
        wall = squares
        floor = items
        floorPenalty = (try? c.decodeIfPresent(Int.self, forKey: .floorPenalty)) ?? AzulRules.floorPenalty(count: items.count)
        rows = (try? c.decodeIfPresent(Int.self, forKey: .rows)) ?? squares.filter { $0.allSatisfy { $0 != nil } }.count
        hasFirst = (try? c.decodeIfPresent(Bool.self, forKey: .hasFirst)) ?? items.contains { $0.isMarker }
    }

    /// Exactly five lines, whatever arrived.
    static func fiveLines(_ raw: [[AzulTile]]) -> [[AzulTile]] {
        (0..<5).map { i in i < raw.count ? Array(raw[i].prefix(i + 1)) : [] }
    }

    /// Exactly 5×5, whatever arrived.
    static func fullWall(_ raw: [[Int?]]) -> [[Int?]] {
        (0..<5).map { r in (0..<5).map { c in r < raw.count && c < raw[r].count ? raw[r][c] : nil } }
    }

    var joined: Bool { status == "joined" }
    var seated: Bool { seat != nil }

    /// The colour a pattern line is collecting, if any.
    func colour(ofLine i: Int) -> String? { lines.indices.contains(i) ? lines[i].first?.c : nil }

    /// The tile on a wall square, if one is there.
    func wallTile(_ row: Int, _ col: Int) -> Int? {
        guard wall.indices.contains(row), wall[row].indices.contains(col) else { return nil }
        return wall[row][col]
    }

    /// Wall squares filled.
    var placed: Int { wall.reduce(0) { $0 + $1.compactMap { $0 }.count } }
}

/// The last take, for the boards' highlight and the log.
struct AzulLast: Decodable, Equatable {
    let by: String
    let source: AzulSource?
    let colour: String
    let tiles: [Int]
    let line: AzulLine?
    let overflow: Int
    let toCentre: [Int]
    let tookFirst: Bool
    let auto: Bool
    let at: Double

    private enum CodingKeys: String, CodingKey { case by, source, colour, tiles, line, overflow, toCentre, tookFirst, auto, at }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        by = (try? c.decodeIfPresent(String.self, forKey: .by)) ?? ""
        source = ((try? c.decodeIfPresent(AzulWireSpot.self, forKey: .source)) ?? nil)?.source
        colour = (try? c.decodeIfPresent(String.self, forKey: .colour)) ?? ""
        tiles = (try? c.decodeIfPresent([Int].self, forKey: .tiles)) ?? []
        line = ((try? c.decodeIfPresent(AzulWireSpot.self, forKey: .line)) ?? nil)?.line
        overflow = (try? c.decodeIfPresent(Int.self, forKey: .overflow)) ?? 0
        toCentre = (try? c.decodeIfPresent([Int].self, forKey: .toCentre)) ?? []
        tookFirst = (try? c.decodeIfPresent(Bool.self, forKey: .tookFirst)) ?? false
        auto = (try? c.decodeIfPresent(Bool.self, forKey: .auto)) ?? false
        at = (try? c.decodeIfPresent(Double.self, forKey: .at)) ?? 0
    }
}

/// One tile moved to the wall at a round's end, and what it scored.
struct AzulPlacement: Decodable, Equatable {
    let line: Int
    let col: Int
    let tile: Int
    let points: Int

    private enum CodingKeys: String, CodingKey { case line, col, tile, points }

    init(line: Int, col: Int, tile: Int, points: Int) {
        self.line = line; self.col = col; self.tile = tile; self.points = points
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        line = (try? c.decodeIfPresent(Int.self, forKey: .line)) ?? 0
        col = (try? c.decodeIfPresent(Int.self, forKey: .col)) ?? 0
        tile = (try? c.decodeIfPresent(Int.self, forKey: .tile)) ?? -1
        points = (try? c.decodeIfPresent(Int.self, forKey: .points)) ?? 0
    }
}

/// A player's round: the tiles placed, the floor's cost, the score before and after.
struct AzulRoundScore: Decodable, Equatable, Identifiable {
    let id: String
    let placements: [AzulPlacement]
    /// The floor's cost, as a positive number.
    let floor: Int
    let before: Int
    let after: Int

    private enum CodingKeys: String, CodingKey { case id, placements, floor, before, after }

    init(id: String, placements: [AzulPlacement], floor: Int, before: Int, after: Int) {
        self.id = id; self.placements = placements; self.floor = floor; self.before = before; self.after = after
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        placements = (try? c.decodeIfPresent([AzulPlacement].self, forKey: .placements)) ?? []
        floor = (try? c.decodeIfPresent(Int.self, forKey: .floor)) ?? 0
        before = (try? c.decodeIfPresent(Int.self, forKey: .before)) ?? 0
        after = (try? c.decodeIfPresent(Int.self, forKey: .after)) ?? before
    }

    /// What the round did to the score, floor and all.
    var delta: Int { after - before }
    /// What the wall tiles alone scored.
    var gained: Int { placements.reduce(0) { $0 + $1.points } }
}

/// One line of what happened, written by the server.
struct AzulLogEntry: Decodable, Equatable, Identifiable {
    let n: Int
    let at: Double
    let by: String?
    let text: String
    let auto: Bool

    var id: Int { n }

    private enum CodingKeys: String, CodingKey { case n, at, by, text, auto }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = (try? c.decodeIfPresent(Int.self, forKey: .n)) ?? 0
        at = (try? c.decodeIfPresent(Double.self, forKey: .at)) ?? 0
        by = (try? c.decodeIfPresent(String.self, forKey: .by)) ?? nil
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        auto = (try? c.decodeIfPresent(Bool.self, forKey: .auto)) ?? false
    }
}

/// End-of-game bonuses for one wall.
struct AzulBonus: Decodable, Equatable {
    let rows: Int
    let columns: Int
    let colours: Int
    let points: Int

    init(rows: Int, columns: Int, colours: Int) {
        self.rows = rows
        self.columns = columns
        self.colours = colours
        self.points = rows * AzulRules.rowBonus + columns * AzulRules.columnBonus + colours * AzulRules.colourBonus
    }

    private enum CodingKeys: String, CodingKey { case rows, columns, colours, points }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = (try? c.decodeIfPresent(Int.self, forKey: .rows)) ?? 0
        columns = (try? c.decodeIfPresent(Int.self, forKey: .columns)) ?? 0
        colours = (try? c.decodeIfPresent(Int.self, forKey: .colours)) ?? 0
        points = (try? c.decodeIfPresent(Int.self, forKey: .points))
            ?? rows * AzulRules.rowBonus + columns * AzulRules.columnBonus + colours * AzulRules.colourBonus
    }
}

/// A row of the final table.
struct AzulStanding: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let place: Int
    let score: Int
    let rows: Int
    /// Nil when the game ended because people left: no bonuses then.
    let bonus: AzulBonus?
    /// won | lost | drew | left
    let result: String

    private enum CodingKeys: String, CodingKey { case id, name, place, score, rows, bonus, result }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Player"
        place = (try? c.decodeIfPresent(Int.self, forKey: .place)) ?? 0
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        rows = (try? c.decodeIfPresent(Int.self, forKey: .rows)) ?? 0
        bonus = (try? c.decodeIfPresent(AzulBonus.self, forKey: .bonus)) ?? nil
        result = (try? c.decodeIfPresent(String.self, forKey: .result)) ?? "lost"
    }
}

/// How the game ended: `wall` (a row was finished), `left`, or `tiles` (the bag ran dry).
struct AzulResult: Decodable, Equatable {
    let winnerIds: [String]
    let reason: String

    private enum CodingKeys: String, CodingKey { case winnerIds, reason }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        winnerIds = (try? c.decodeIfPresent([String].self, forKey: .winnerIds)) ?? []
        reason = (try? c.decodeIfPresent(String.self, forKey: .reason)) ?? "wall"
    }
}

/// The room's Azul side, decoded from the same JSON as `GameRoom`. Lenient
/// throughout: a lobby from the create call carries little of it.
struct AzulState: Decodable, Equatable {
    let phase: AzulPhase
    let meId: String
    let table: AzulTable
    /// The turn's clock: the difficulty's when live, the host's hours over days.
    let turnMs: Double
    /// Over days: hours a turn. Nil for a live game.
    let deadlineHours: Int?
    let round: Int
    /// Somebody finished a wall row: this round is the last.
    let lastRound: Bool
    let turnId: String?
    let turnStartedAt: Double?
    let phaseEndsAt: Double?
    let colours: [String]
    let factories: [[AzulTile]]
    let centre: [AzulTile]
    /// The first-player marker is still in the centre.
    let firstInCentre: Bool
    /// Tiles left in the bag and in the lid (counts only).
    let bag: Int
    let lid: Int
    /// Only to the player whose turn it is: each colour on offer, the lines it may go on.
    let canPlace: [String: [Int]]
    let last: AzulLast?
    /// During and after the scoring pause: what each player's round did.
    let roundScores: [AzulRoundScore]?
    let log: [AzulLogEntry]
    let players: [AzulBoard]
    let result: AzulResult?
    let standings: [AzulStanding]?

    private enum CodingKeys: String, CodingKey {
        case phase, meId, table, turnMs, deadlineHours, round, lastRound, turnId, turnStartedAt, phaseEndsAt
        case colours, factories, centre, firstInCentre, bag, lid, canPlace, last, roundScores, log, players
        case result, standings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = AzulPhase.from((try? c.decodeIfPresent(String.self, forKey: .phase)) ?? nil)
        meId = (try? c.decodeIfPresent(String.self, forKey: .meId)) ?? ""
        table = AzulTable.from((try? c.decodeIfPresent(String.self, forKey: .table)) ?? nil)
        turnMs = (try? c.decodeIfPresent(Double.self, forKey: .turnMs)) ?? 90_000
        deadlineHours = (try? c.decodeIfPresent(Int.self, forKey: .deadlineHours)) ?? nil
        round = (try? c.decodeIfPresent(Int.self, forKey: .round)) ?? 0
        lastRound = (try? c.decodeIfPresent(Bool.self, forKey: .lastRound)) ?? false
        turnId = (try? c.decodeIfPresent(String.self, forKey: .turnId)) ?? nil
        turnStartedAt = (try? c.decodeIfPresent(Double.self, forKey: .turnStartedAt)) ?? nil
        phaseEndsAt = (try? c.decodeIfPresent(Double.self, forKey: .phaseEndsAt)) ?? nil
        colours = (try? c.decodeIfPresent([String].self, forKey: .colours)) ?? AzulRules.colours
        factories = (try? c.decodeIfPresent([[AzulTile]].self, forKey: .factories)) ?? []
        centre = (try? c.decodeIfPresent([AzulTile].self, forKey: .centre)) ?? []
        firstInCentre = (try? c.decodeIfPresent(Bool.self, forKey: .firstInCentre)) ?? false
        bag = (try? c.decodeIfPresent(Int.self, forKey: .bag)) ?? 0
        lid = (try? c.decodeIfPresent(Int.self, forKey: .lid)) ?? 0
        canPlace = (try? c.decodeIfPresent([String: [Int]].self, forKey: .canPlace)) ?? [:]
        last = (try? c.decodeIfPresent(AzulLast.self, forKey: .last)) ?? nil
        roundScores = (try? c.decodeIfPresent([AzulRoundScore].self, forKey: .roundScores)) ?? nil
        log = (try? c.decodeIfPresent([AzulLogEntry].self, forKey: .log)) ?? []
        players = (try? c.decodeIfPresent([AzulBoard].self, forKey: .players)) ?? []
        result = (try? c.decodeIfPresent(AzulResult.self, forKey: .result)) ?? nil
        standings = (try? c.decodeIfPresent([AzulStanding].self, forKey: .standings)) ?? nil
    }

    func board(_ id: String) -> AzulBoard? { players.first { $0.id == id } }

    /// Everyone at the table, in turn order.
    var seated: [AzulBoard] {
        players.filter(\.seated).sorted { ($0.seat ?? 0) < ($1.seat ?? 0) }
    }

    /// The table in turn order starting from the player after `id` — the
    /// others' boards, in the order they will move after me.
    func others(after id: String) -> [AzulBoard] {
        let order = seated
        guard let mine = order.firstIndex(where: { $0.id == id }) else { return order.filter { $0.id != id } }
        return Array(order[(mine + 1)...]) + Array(order[..<mine])
    }

    var isAsync: Bool { deadlineHours != nil }

    func roundScore(_ id: String) -> AzulRoundScore? { roundScores?.first { $0.id == id } }

    func standing(_ id: String) -> AzulStanding? { standings?.first { $0.id == id } }

    /// The tiles at a source.
    func tiles(at source: AzulSource) -> [AzulTile] {
        switch source {
        case .centre: return centre
        case .factory(let i): return factories.indices.contains(i) ? factories[i] : []
        }
    }

    /// Who holds the first-player marker, if anybody does yet this round.
    var markerHolder: String? { players.first { $0.hasFirst }?.id }
}

// MARK: - The rules the phone applies

/// What a take would do to one destination: tiles that fit on the line, tiles
/// that fall to the floor, and any past the seventh floor space that go to the
/// lid for nothing.
struct AzulSpill: Equatable {
    let fit: Int
    let floor: Int
    let lost: Int
    /// The first-player marker comes too (the first take from the centre).
    let marker: Bool
    /// What it adds to the floor's cost.
    let cost: Int
}

/// One place the picked tiles may go, with what would happen there.
struct AzulDestination: Equatable, Identifiable {
    let line: AzulLine
    let spill: AzulSpill

    var id: String {
        switch line {
        case .line(let i): return "line-\(i)"
        case .floor: return "floor"
        }
    }
}

enum AzulRules {
    /// The wall's pattern starts from these, in this order (row 0).
    static let colours = ["blue", "yellow", "red", "black", "white"]
    /// The first-player marker's colour on a floor.
    static let marker = "first"
    static let markerId = 100
    /// What each floor space costs, left to right.
    static let floorPenalties = [1, 1, 2, 2, 2, 3, 3]
    static let rowBonus = 2
    static let columnBonus = 7
    static let colourBonus = 10

    static let minPlayers = 2
    static let maxPlayers = 4
    static let sheetTrailing = "2 to 4"
    static let sheetNobody = "Nobody else in the family can play yet, and Azul needs two to four. The lobby can wait for somebody to pair a phone."
    static let sheetPick = "Azul is for two to four: invite at least one. Play in one sitting, or over days a turn at a time. The lobby waits for them to join."
    /// Under the sheet's Table choice.
    static let tableNote = "The TV board is optional: every phone shows the whole table either way. For the TV, open \(GameScreenCode.address("azul")) on it."

    /// The colour that belongs on a wall square: `COLOURS[(col - row) mod 5]`.
    static func wallColour(row: Int, col: Int) -> String {
        colours[(((col - row) % 5) + 5) % 5]
    }

    /// The column a colour takes in a row; nil for a colour that is not one.
    static func wallColumn(row: Int, colour: String) -> Int? {
        guard let i = colours.firstIndex(of: colour) else { return nil }
        return (i + row) % 5
    }

    static func colourName(_ colour: String) -> String {
        colour == marker ? "First-player marker" : colour.capitalized
    }

    /// A mark printed on every tile, so nobody needs to tell the colours
    /// apart by colour: an SF Symbol per colour.
    static func glyph(_ colour: String) -> String {
        switch colour {
        case "blue": return "drop.fill"
        case "yellow": return "sun.max.fill"
        case "red": return "flame.fill"
        case "black": return "moon.fill"
        case "white": return "snowflake"
        default: return "1.circle.fill"
        }
    }

    /// The colours at a source, in the wall's order.
    static func coloursAt(_ tiles: [AzulTile]) -> [String] {
        colours.filter { c in tiles.contains { $0.c == c } }
    }

    /// The tiles of one colour at a source.
    static func tiles(_ colour: String, in tiles: [AzulTile]) -> [AzulTile] {
        tiles.filter { $0.c == colour }
    }

    /// The pattern lines lit for a colour: exactly what the server sent in
    /// `canPlace`, kept to 0–4. The floor is always allowed and is not listed.
    static func litLines(_ canPlace: [String: [Int]], colour: String) -> Set<Int> {
        Set((canPlace[colour] ?? []).filter { (0..<5).contains($0) })
    }

    /// What the floor costs with `count` things on it (at most seven count).
    static func floorPenalty(count: Int) -> Int {
        floorPenalties.prefix(max(0, count)).reduce(0, +)
    }

    /// "−1", the floor space's printed cost.
    static func floorLabel(_ index: Int) -> String {
        guard floorPenalties.indices.contains(index) else { return "" }
        return "−\(floorPenalties[index])"
    }

    /// Taking `count` tiles onto `line` of `board`: how many fit, how many
    /// fall, how many are lost past the floor, and what the floor then costs
    /// more. `marker` when the take is the first from the centre: the marker
    /// lands on the floor first (and is never lost).
    static func spill(count: Int, onto line: AzulLine, of board: AzulBoard, marker: Bool = false) -> AzulSpill {
        let n = max(0, count)
        let fit: Int
        switch line {
        case .floor:
            fit = 0
        case .line(let i):
            let held = board.lines.indices.contains(i) ? board.lines[i].count : 0
            fit = min(n, max(0, i + 1 - held))
        }
        let falling = n - fit
        let space = max(0, floorPenalties.count - board.floor.count)
        let markerTakes = marker && space > 0 ? 1 : 0
        let landed = min(falling, max(0, space - markerTakes))
        let lost = falling - landed
        let before = floorPenalty(count: board.floor.count)
        let after = floorPenalty(count: board.floor.count + markerTakes + landed)
        return AzulSpill(fit: fit, floor: falling, lost: lost, marker: marker, cost: after - before)
    }

    /// Every place the picked tiles may go — the lit lines, top first, then
    /// the floor — with what each would do.
    static func destinations(for colour: String, count: Int, board: AzulBoard, canPlace: [String: [Int]],
                             marker: Bool) -> [AzulDestination] {
        let lines = litLines(canPlace, colour: colour).sorted().map(AzulLine.line)
        return (lines + [.floor]).map { AzulDestination(line: $0, spill: spill(count: count, onto: $0, of: board, marker: marker)) }
    }

    /// The preview in a few words: "3 fit, 1 to the floor", "All 4 fit",
    /// "2 to the floor".
    static func previewText(_ spill: AzulSpill) -> String {
        var text: String
        if spill.fit == 0 {
            text = "\(spill.floor) to the floor"
        } else if spill.floor == 0 {
            text = spill.fit == 1 ? "It fits" : "All \(spill.fit) fit"
        } else {
            text = "\(spill.fit) \(spill.fit == 1 ? "fits" : "fit"), \(spill.floor) to the floor"
        }
        if spill.marker { text += ", and the marker" }
        return text
    }

    /// The preview's cost line: "−2 points" when the floor charges, else nil.
    static func costText(_ spill: AzulSpill) -> String? {
        guard spill.cost > 0 else { return nil }
        return spill.cost == 1 ? "−1 point" : "−\(spill.cost) points"
    }

    /// The final bonuses in words: "2 rows +4 · 1 column +7 · no colours".
    static func bonusLine(_ bonus: AzulBonus) -> String {
        func part(_ n: Int, _ one: String, _ many: String, each: Int) -> String {
            n == 0 ? "no \(many)" : "\(n) \(n == 1 ? one : many) +\(n * each)"
        }
        return [part(bonus.rows, "row", "rows", each: rowBonus),
                part(bonus.columns, "column", "columns", each: columnBonus),
                part(bonus.colours, "colour", "colours", each: colourBonus)].joined(separator: " · ")
    }

    /// How the game ended, in a sentence.
    static func endingLine(_ result: AzulResult?) -> String {
        switch result?.reason {
        case "wall": return "A wall row was finished, so that round was the last. Bonuses added: +2 a row, +7 a column, +10 a colour."
        case "tiles": return "The bag and the lid ran dry: no tiles left to draft. Bonuses added."
        case "left": return "Not enough players left to carry on. No bonuses."
        default: return "The game is over."
        }
    }

    /// Leaving mid-game, for the confirm: what happens to the table.
    static func leaveWarning(staying: Int) -> String {
        staying < minPlayers
            ? "Your board stays where it is, and with only one player left the game ends here."
            : "Your board stays where it is and you're out of the running. The others play on."
    }

    /// A round's change in a few characters: "+7", "−2", "±0".
    static func deltaText(_ delta: Int) -> String {
        delta > 0 ? "+\(delta)" : delta < 0 ? "−\(-delta)" : "±0"
    }
}
