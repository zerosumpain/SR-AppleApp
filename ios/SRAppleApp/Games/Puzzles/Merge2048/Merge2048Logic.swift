import Foundation

// 2048's rules, with nothing on screen: the board, a slide in each direction,
// the merges, the spawn and the one-step undo. Foundation only, so the rules
// are unit-tested on any machine (`Merge2048LogicTests`); the screen
// (`Merge2048Screen`) only draws what this decides.
//
// Every tile carries a stable `id` for as long as it lives. A slide moves
// tiles, it does not remake them, which is what lets the board animate each
// tile from where it was to where it went. When two tiles merge, the one
// nearer the wall it was pushed towards survives with double the value; the
// other is handed back as `consumed`, already moved onto the survivor's cell,
// so the screen can slide it there before it goes.

/// A way to slide the board.
enum Merge2048Direction: String, CaseIterable, Codable {
    case up, down, left, right

    /// Said aloud, and on the arrow buttons.
    var word: String {
        switch self {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        }
    }
}

/// The three boards on offer. The raw value is the side, in cells.
enum Merge2048Size: Int, CaseIterable, Codable, Identifiable {
    case classic = 4
    case relaxed = 5
    case hard = 3

    var id: Int { rawValue }
    var side: Int { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .relaxed: return "Relaxed"
        case .hard: return "Hard"
        }
    }

    /// "4×4".
    var dimension: String { "\(rawValue)×\(rawValue)" }

    var line: String {
        switch self {
        case .classic: return "The original 4×4 board. Reach 2048."
        case .relaxed: return "A roomy 5×5 board with space to plan. Reach 2048."
        case .hard: return "A tiny 3×3 board. Every move counts. Reach 512."
        }
    }

    /// The tile that wins. A 3×3 board has nine cells, and 2048 needs more
    /// room than that in all but freak games, so the small board aims lower.
    var target: Int {
        switch self {
        case .classic, .relaxed: return 2048
        case .hard: return 512
        }
    }
}

/// A row and a column, from the top left.
struct Merge2048Cell: Hashable, Codable {
    let row: Int
    let col: Int
}

/// One tile on the board.
struct Merge2048Tile: Codable, Equatable, Identifiable {
    let id: Int
    var value: Int
    var row: Int
    var col: Int

    var cell: Merge2048Cell { Merge2048Cell(row: row, col: col) }
}

/// Two tiles that became one this move.
struct Merge2048Merge: Equatable {
    let row: Int
    let col: Int
    /// The value after the merge (double either tile).
    let value: Int
    let survivorId: Int
    let consumedId: Int
}

/// What a slide did to the board, before anything spawns.
struct Merge2048Slide: Equatable {
    /// Every tile still on the board, in its new place.
    var tiles: [Merge2048Tile]
    /// The tiles merged away, placed on the cell they merged into.
    var consumed: [Merge2048Tile]
    var merges: [Merge2048Merge]
    /// The points: the sum of every merged value.
    var gained: Int
    /// False when the slide moved nothing and merged nothing.
    var changed: Bool
}

/// A small, fast, seedable generator (SplitMix64), so a game is the same game
/// every time from the same seed, and an undo can wind the spawns back too.
struct Merge2048Random: Equatable, Codable {
    private(set) var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< `bound`; `bound` must be at least 1.
    mutating func below(_ bound: Int) -> Int {
        Int(next() % UInt64(max(1, bound)))
    }

    /// 0 ..< 1.
    mutating func unit() -> Double {
        Double(next() >> 11) / 9_007_199_254_740_992.0
    }

    // Kept as text: a UInt64 above 2^53 does not survive every JSON reader.
    private enum CodingKeys: String, CodingKey { case state }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let text = try box.decode(String.self, forKey: .state)
        state = UInt64(text) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(String(state), forKey: .state)
    }
}

/// The sliding itself, as plain functions over tiles.
enum Merge2048Engine {
    /// Line `index` of the board, read from the wall the tiles slide towards:
    /// for `.left`, row `index` from column 0; for `.down`, column `index`
    /// from the bottom.
    static func lineCells(side: Int, direction: Merge2048Direction, index: Int) -> [Merge2048Cell] {
        let span = Array(0..<side)
        switch direction {
        case .left: return span.map { Merge2048Cell(row: index, col: $0) }
        case .right: return span.reversed().map { Merge2048Cell(row: index, col: $0) }
        case .up: return span.map { Merge2048Cell(row: $0, col: index) }
        case .down: return span.reversed().map { Merge2048Cell(row: $0, col: index) }
        }
    }

    /// Slide every tile towards `direction`. Equal neighbours merge once each
    /// per move: [2, 2, 2, 2] becomes [4, 4], and [2, 2, 4] becomes [4, 4],
    /// never 8.
    static func slide(_ tiles: [Merge2048Tile], side: Int, direction: Merge2048Direction) -> Merge2048Slide {
        var at: [Merge2048Cell: Merge2048Tile] = [:]
        for tile in tiles { at[tile.cell] = tile }
        var placed: [Merge2048Tile] = []
        placed.reserveCapacity(tiles.count)
        var consumed: [Merge2048Tile] = []
        var merges: [Merge2048Merge] = []
        var gained = 0
        var changed = false

        for index in 0..<side {
            let cells = lineCells(side: side, direction: direction, index: index)
            var line: [Merge2048Tile] = []
            for cell in cells {
                if let tile = at[cell] { line.append(tile) }
            }
            var read = 0
            var write = 0
            while read < line.count {
                let target = cells[write]
                var front = line[read]
                if read + 1 < line.count && line[read + 1].value == front.value {
                    var behind = line[read + 1]
                    front.value *= 2
                    front.row = target.row
                    front.col = target.col
                    behind.row = target.row
                    behind.col = target.col
                    placed.append(front)
                    consumed.append(behind)
                    merges.append(Merge2048Merge(row: target.row, col: target.col, value: front.value,
                                                 survivorId: front.id, consumedId: behind.id))
                    gained += front.value
                    changed = true
                    read += 2
                } else {
                    if front.row != target.row || front.col != target.col { changed = true }
                    front.row = target.row
                    front.col = target.col
                    placed.append(front)
                    read += 1
                }
                write += 1
            }
        }
        return Merge2048Slide(tiles: placed, consumed: consumed, merges: merges, gained: gained, changed: changed)
    }

    /// One line on its own, as values from the wall outward (0 is empty):
    /// [2, 2, 4, 0] slides to [4, 4, 0, 0] for 4 points.
    static func slideLine(_ values: [Int]) -> (values: [Int], gained: Int) {
        let tiles = values.enumerated().compactMap { index, value -> Merge2048Tile? in
            value == 0 ? nil : Merge2048Tile(id: index, value: value, row: 0, col: index)
        }
        // A line is the top row of a square board with nothing else on it.
        let side = values.count
        let slid = slide(tiles, side: side, direction: .left)
        var out = Array(repeating: 0, count: side)
        for tile in slid.tiles { out[tile.col] = tile.value }
        return (out, slid.gained)
    }

    /// True when some slide would change the board.
    static func canMove(_ tiles: [Merge2048Tile], side: Int) -> Bool {
        if tiles.count < side * side { return true }
        let rows = grid(tiles, side: side)
        for r in 0..<side {
            for c in 0..<side {
                let v = rows[r][c]
                if c + 1 < side && rows[r][c + 1] == v { return true }
                if r + 1 < side && rows[r + 1][c] == v { return true }
            }
        }
        return false
    }

    /// The board as rows of values, 0 for an empty cell.
    static func grid(_ tiles: [Merge2048Tile], side: Int) -> [[Int]] {
        var rows = Array(repeating: Array(repeating: 0, count: side), count: side)
        for tile in tiles where tile.row >= 0 && tile.row < side && tile.col >= 0 && tile.col < side {
            rows[tile.row][tile.col] = tile.value
        }
        return rows
    }

    /// Tiles for a grid of values, numbered from `firstId` in reading order.
    static func tiles(from rows: [[Int]], firstId: Int = 1) -> [Merge2048Tile] {
        var out: [Merge2048Tile] = []
        var id = firstId
        for (r, row) in rows.enumerated() {
            for (c, value) in row.enumerated() where value != 0 {
                out.append(Merge2048Tile(id: id, value: value, row: r, col: c))
                id += 1
            }
        }
        return out
    }

    /// The empty cells, in reading order.
    static func emptyCells(_ tiles: [Merge2048Tile], side: Int) -> [Merge2048Cell] {
        var taken = Set<Merge2048Cell>()
        for tile in tiles { taken.insert(tile.cell) }
        var out: [Merge2048Cell] = []
        for r in 0..<side {
            for c in 0..<side {
                let cell = Merge2048Cell(row: r, col: c)
                if !taken.contains(cell) { out.append(cell) }
            }
        }
        return out
    }
}

/// The board as it was before the last move, for the one undo.
struct Merge2048Snapshot: Codable, Equatable {
    let tiles: [Merge2048Tile]
    let score: Int
    let moves: Int
    let random: Merge2048Random
    let reachedTarget: Bool
}

/// What one move did, for the screen's feedback.
struct Merge2048Turn: Equatable {
    let direction: Merge2048Direction
    let merges: [Merge2048Merge]
    /// Merged-away tiles, on the cell they merged into.
    let consumed: [Merge2048Tile]
    let spawned: Merge2048Tile?
    let gained: Int
    /// This move made the winning tile for the first time.
    let reachedTarget: Bool
    /// The move made a tile bigger than any on the board before it.
    let newBiggest: Int?
    /// No move is left after this one.
    let over: Bool
}

/// One game of 2048.
struct Merge2048State: Codable, Equatable {
    /// Cells along one edge.
    let side: Int
    /// The tile that wins.
    let target: Int
    private(set) var tiles: [Merge2048Tile]
    private(set) var score: Int = 0
    private(set) var moves: Int = 0
    private(set) var undosUsed: Int = 0
    /// The winning tile has been made (the win card has been shown).
    private(set) var reachedTarget = false
    private(set) var random: Merge2048Random
    private(set) var nextId: Int
    private var previous: Merge2048Snapshot?

    /// A new game: an empty board and two tiles.
    init(size: Merge2048Size, seed: UInt64) {
        self.init(side: size.side, target: size.target, seed: seed)
    }

    init(side: Int, target: Int, seed: UInt64) {
        self.side = max(2, side)
        self.target = target
        tiles = []
        random = Merge2048Random(seed: seed)
        nextId = 1
        spawn()
        spawn()
    }

    /// A game from a set position (tests, and a board set up on purpose).
    init(side: Int, target: Int, rows: [[Int]], seed: UInt64) {
        self.side = side
        self.target = target
        tiles = Merge2048Engine.tiles(from: rows)
        nextId = tiles.count + 1
        random = Merge2048Random(seed: seed)
        reachedTarget = tiles.contains { $0.value >= target }
    }

    var rows: [[Int]] { Merge2048Engine.grid(tiles, side: side) }
    var biggest: Int { tiles.map(\.value).max() ?? 0 }
    var isOver: Bool { !Merge2048Engine.canMove(tiles, side: side) }
    var canUndo: Bool { previous != nil }
    var hasWon: Bool { reachedTarget }

    /// Slide the board. Nil, and nothing changes (no spawn either), when the
    /// slide would move nothing.
    @discardableResult
    mutating func move(_ direction: Merge2048Direction) -> Merge2048Turn? {
        let slid = Merge2048Engine.slide(tiles, side: side, direction: direction)
        guard slid.changed else { return nil }
        let snapshot = Merge2048Snapshot(tiles: tiles, score: score, moves: moves, random: random,
                                         reachedTarget: reachedTarget)
        let biggestBefore = biggest
        tiles = slid.tiles
        score += slid.gained
        moves += 1
        previous = snapshot
        let spawned = spawn()
        let after = biggest
        let won = !reachedTarget && after >= target
        if won { reachedTarget = true }
        return Merge2048Turn(direction: direction, merges: slid.merges, consumed: slid.consumed,
                             spawned: spawned, gained: slid.gained, reachedTarget: won,
                             newBiggest: after > biggestBefore ? after : nil, over: isOver)
    }

    /// Take back the last move, spawn and all. One step only: the next undo
    /// waits for the next move.
    @discardableResult
    mutating func undo() -> Bool {
        guard let snapshot = previous else { return false }
        tiles = snapshot.tiles
        score = snapshot.score
        moves = snapshot.moves
        random = snapshot.random
        reachedTarget = snapshot.reachedTarget
        previous = nil
        undosUsed += 1
        return true
    }

    /// A 2 (nine times in ten) or a 4 in a random empty cell.
    @discardableResult
    mutating func spawn() -> Merge2048Tile? {
        let empty = Merge2048Engine.emptyCells(tiles, side: side)
        guard !empty.isEmpty else { return nil }
        let cell = empty[random.below(empty.count)]
        let value = random.unit() < 0.9 ? 2 : 4
        let tile = Merge2048Tile(id: nextId, value: value, row: cell.row, col: cell.col)
        nextId += 1
        tiles.append(tile)
        return tile
    }
}

/// How far up the ladder a value is: 2 is 1, 4 is 2, 2048 is 11.
enum Merge2048Ladder {
    static func step(_ value: Int) -> Int {
        guard value > 1 else { return 0 }
        var v = value
        var n = 0
        while v > 1 { v >>= 1; n += 1 }
        return n
    }

    /// The milestones shown on the intro card, up to and past the target.
    static func milestones(target: Int) -> [Int] {
        var out: [Int] = []
        var v = 64
        while v <= target * 2 {
            out.append(v)
            v *= 2
        }
        return out
    }
}
