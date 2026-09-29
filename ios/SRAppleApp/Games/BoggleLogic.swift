import Foundation
import CoreGraphics

// Boggle's wire pieces and the rules the phone applies itself — which tiles
// touch, the word a trace spells, whether a finger may move on to a tile, the
// round the host picks — as pure values, so each is a unit test. The server
// judges every word; nothing here decides whether one counts or what it scores.

/// One of my words, as scored. `shared` is null until the game finishes;
/// then true for a word somebody else found too — in classic scoring it is
/// crossed out and `points` is 0. `path` is the tiles it was traced through.
struct BoggleWord: Decodable, Equatable, Identifiable {
    let word: String
    let points: Int
    let shared: Bool?
    let path: [Int]

    var id: String { word }

    init(word: String, points: Int, shared: Bool? = nil, path: [Int] = []) {
        self.word = word
        self.points = points
        self.shared = shared
        self.path = path
    }

    private enum CodingKeys: String, CodingKey { case word, points, shared, path }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = try c.decode(String.self, forKey: .word).lowercased()
        points = (try? c.decodeIfPresent(Int.self, forKey: .points)) ?? 0
        shared = (try? c.decodeIfPresent(Bool.self, forKey: .shared)) ?? nil
        path = (try? c.decodeIfPresent([Int].self, forKey: .path)) ?? []
    }
}

/// A word somebody found, at the finish. A `shared` word in classic scoring
/// scored nothing for anyone; `points` is what it scored each finder.
struct BoggleFound: Decodable, Equatable, Identifiable {
    let word: String
    let points: Int
    let finderIds: [String]
    let shared: Bool
    let path: [Int]

    var id: String { word }

    private enum CodingKeys: String, CodingKey { case word, points, finderIds, shared, path }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = try c.decode(String.self, forKey: .word).lowercased()
        points = (try? c.decodeIfPresent(Int.self, forKey: .points)) ?? 0
        finderIds = (try? c.decodeIfPresent([String].self, forKey: .finderIds)) ?? []
        shared = (try? c.decodeIfPresent(Bool.self, forKey: .shared)) ?? false
        path = (try? c.decodeIfPresent([Int].self, forKey: .path)) ?? []
    }
}

/// One of the best words nobody found, with where it was on the board.
struct BoggleMissed: Decodable, Equatable, Identifiable {
    let word: String
    let points: Int
    let path: [Int]

    var id: String { word }

    private enum CodingKeys: String, CodingKey { case word, points, path }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = try c.decode(String.self, forKey: .word).lowercased()
        points = (try? c.decodeIfPresent(Int.self, forKey: .points)) ?? 0
        path = (try? c.decodeIfPresent([Int].self, forKey: .path)) ?? []
    }
}

/// Every valid word the board held, and what they were worth together.
struct BogglePossible: Decodable, Equatable {
    let words: Int
    let points: Int

    private enum CodingKeys: String, CodingKey { case words, points }

    init(words: Int, points: Int) {
        self.words = words
        self.points = points
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        words = (try? c.decodeIfPresent(Int.self, forKey: .words)) ?? 0
        points = (try? c.decodeIfPresent(Int.self, forKey: .points)) ?? 0
    }
}

// MARK: - The round the host picks

enum BoggleScoring: String, CaseIterable, Identifiable {
    /// A word two or more players found is crossed out for all of them.
    case classic
    /// Every word counts for whoever found it.
    case every

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "Classic"
        case .every: return "Every word counts"
        }
    }

    var line: String {
        switch self {
        case .classic: return "A word someone else also found is crossed out for both of you. Hunt the odd ones."
        case .every: return "Every word scores for whoever found it. Kinder with younger players."
        }
    }

    /// From the wire; anything unknown reads as classic, the server's default.
    static func from(_ raw: String?) -> BoggleScoring { raw.flatMap(BoggleScoring.init(rawValue:)) ?? .classic }
}

/// Grid, time and scoring — Boggle's own choices on the new-game sheet.
struct BoggleSettings: Equatable {
    static let sizes = [4, 5, 6]
    static let times = [30, 90, 120, 180]

    var difficulty: GameDifficulty
    var size: Int = 4
    var seconds: Int = 120
    var scoring: BoggleScoring = .classic

    func createBody(invite: [String]) -> CreateGameBody {
        CreateGameBody(
            game: GameKind.boggle.rawValue,
            difficulty: difficulty.rawValue,
            invite: invite,
            size: size,
            seconds: seconds,
            scoring: scoring.rawValue
        )
    }

    /// "30 s", "90 s", "2 min", "3 min" — the time picker's segments.
    static func timeLabel(_ seconds: Int) -> String {
        seconds >= 120 && seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
    }

    /// "4×4".
    static func sizeLabel(_ size: Int) -> String { "\(size)×\(size)" }

    /// One line under the pickers, saying what that board and clock are like.
    static func line(size: Int, seconds: Int) -> String {
        let board: String
        switch size {
        case 4: board = "The classic 16 dice."
        case 5: board = "25 dice, room for longer words."
        default: board = "36 dice, some with two letters on a face."
        }
        let clock: String
        switch seconds {
        case ..<60: clock = "A 30-second dash."
        case ..<150: clock = "\(timeLabel(seconds)) on the clock."
        default: clock = "Three minutes, like the sand timer."
        }
        return "\(board) \(clock)"
    }

    /// "5×5 · 2 min · every word counts", for the lobby.
    static func about(_ room: GameRoom) -> String {
        var parts = [sizeLabel(room.size)]
        if let limit = room.timeLimitMs { parts.append(timeLabel(Int((limit / 1000).rounded()))) }
        if BoggleScoring.from(room.scoring) == .every { parts.append("every word counts") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - The rules

enum BoggleRules {
    /// A word's points by its length in letters (`qu` is two), from the room's
    /// table; a room that did not send that row gets the spec's rule, a point
    /// a letter past two.
    static func points(for word: String, table: [String: Int]) -> Int {
        let length = word.count
        if length < 3 { return 0 }
        return table[String(length)] ?? length - 2
    }

    /// Row and column of a tile on a `size`-wide grid.
    static func cell(_ tile: Int, size: Int) -> (row: Int, column: Int) {
        (tile / max(size, 1), tile % max(size, 1))
    }

    /// Two different tiles that touch — side or corner.
    static func adjacent(_ a: Int, _ b: Int, size: Int) -> Bool {
        guard a != b, a >= 0, b >= 0, a < size * size, b < size * size else { return false }
        let x = cell(a, size: size), y = cell(b, size: size)
        return abs(x.row - y.row) <= 1 && abs(x.column - y.column) <= 1
    }

    /// A trace the server would accept: tiles on the board, each used once,
    /// each touching the one before.
    static func isPath(_ path: [Int], size: Int) -> Bool {
        guard !path.isEmpty, Set(path).count == path.count else { return false }
        guard path.allSatisfy({ $0 >= 0 && $0 < size * size }) else { return false }
        return zip(path, path.dropFirst()).allSatisfy { adjacent($0, $1, size: size) }
    }

    /// The word a trace spells, lower-case. Empty for a tile off the grid.
    static func word(_ path: [Int], grid: [String]) -> String {
        guard path.allSatisfy({ $0 >= 0 && $0 < grid.count }) else { return "" }
        return path.map { grid[$0].lowercased() }.joined()
    }

    /// What a face shows: "A", "Qu", "Th", "In" — first letter up, the rest down.
    static func display(_ face: String) -> String {
        guard let first = face.first else { return "" }
        return first.uppercased() + face.dropFirst().lowercased()
    }

    /// Checked on the phone before a word is sent, in the server's order, so
    /// the obvious refusals answer at once. Nil when the word should go.
    static func localRefusal(word: String, minLength: Int, mine: [String]) -> String? {
        if word.count < minLength { return "Words need at least \(minLength) letters." }
        if mine.contains(word) { return "You already have that one." }
        return nil
    }

    /// The side of a tile for a board `width` wide with `gap` between tiles,
    /// never above `cap` (a 4×4 on a big phone should not be a wall of dice).
    static func tileSide(width: CGFloat, size: Int, gap: CGFloat, cap: CGFloat = 84) -> CGFloat {
        let n = CGFloat(max(size, 1))
        let side = (width - gap * (n - 1)) / n
        return max(24, min(cap, side.rounded(.down)))
    }

    /// The tile under a point on a board of tiles `side` wide with `gap`
    /// between them — but only within `reach` of a tile's centre (a fraction
    /// of the side). Crossing a tile's corner on the way to a diagonal does not
    /// pick up its neighbours, which is what makes a diagonal easy to draw.
    static func tile(at point: CGPoint, size: Int, side: CGFloat, gap: CGFloat, reach: CGFloat = 0.42) -> Int? {
        let pitch = side + gap
        guard pitch > 0, point.x >= 0, point.y >= 0 else { return nil }
        let column = Int(point.x / pitch), row = Int(point.y / pitch)
        guard row < size, column < size else { return nil }
        let centre = CGPoint(x: CGFloat(column) * pitch + side / 2, y: CGFloat(row) * pitch + side / 2)
        let dx = point.x - centre.x, dy = point.y - centre.y
        guard (dx * dx + dy * dy).squareRoot() <= side * reach else { return nil }
        return row * size + column
    }

    /// Where a tile shows once the board is turned `turns` quarter turns
    /// clockwise — the Boggle habit of spinning the tray for a fresh look.
    /// The tiles keep their indices; only where they are drawn changes.
    static func displayed(_ tile: Int, size: Int, turns: Int) -> Int {
        var (row, column) = cell(tile, size: size)
        for _ in 0..<((turns % 4 + 4) % 4) { (row, column) = (column, size - 1 - row) }
        return row * size + column
    }

    /// The tile drawn at a display position — `displayed`'s inverse.
    static func tile(atDisplay index: Int, size: Int, turns: Int) -> Int {
        var (row, column) = cell(index, size: size)
        for _ in 0..<((turns % 4 + 4) % 4) { (row, column) = (size - 1 - column, row) }
        return row * size + column
    }

    /// My words, newest first, for the list under the grid.
    static func newestFirst(_ words: [BoggleWord]) -> [BoggleWord] { words.reversed() }

    /// "You found 23 of 187 words" — how much of the board the family found.
    static func possibleLine(found: Int, possible: BogglePossible?, solo: Bool) -> String? {
        guard let possible, possible.words > 0 else { return nil }
        let who = solo ? "You" : "Between you, you"
        return "\(who) found \(found) of \(possible.words) words on this board."
    }
}

/// The trace being drawn: tiles in order, each touching the last.
///
/// A finger moving onto a free neighbour adds it; moving back onto the tile
/// before the last takes the last one off, so a wrong turn is undone by
/// retracing it. A tap anywhere works the same way (the VoiceOver path):
/// a free neighbour adds, the last tile removes, and a tile that touches
/// nothing starts a new word there.
struct BoggleTrace: Equatable {
    let size: Int
    private(set) var path: [Int] = []

    init(size: Int) { self.size = size }

    var isEmpty: Bool { path.isEmpty }
    var last: Int? { path.last }

    func contains(_ tile: Int) -> Bool { path.contains(tile) }

    /// Where a tile sits in the trace, from 0; nil when it is not in it.
    func position(of tile: Int) -> Int? { path.firstIndex(of: tile) }

    /// Can a finger on the last tile move on to this one?
    func canExtend(to tile: Int) -> Bool {
        guard tile >= 0, tile < size * size, !path.contains(tile) else { return false }
        guard let last else { return true }
        return BoggleRules.adjacent(last, tile, size: size)
    }

    /// A finger entering a tile mid-drag. True when the trace changed.
    @discardableResult
    mutating func drag(to tile: Int) -> Bool {
        if path.count >= 2, path[path.count - 2] == tile {
            path.removeLast()
            return true
        }
        guard canExtend(to: tile) else { return false }
        path.append(tile)
        return true
    }

    /// A tap on a tile. True when the trace changed.
    @discardableResult
    mutating func tap(_ tile: Int) -> Bool {
        guard tile >= 0, tile < size * size else { return false }
        if tile == path.last {
            path.removeLast()
            return true
        }
        if canExtend(to: tile) {
            path.append(tile)
            return true
        }
        if path.contains(tile) {
            // Back to that tile: everything after it comes off.
            path.removeSubrange((path.firstIndex(of: tile)! + 1)...)
            return true
        }
        // Not next to the trace: start again from here.
        path = [tile]
        return true
    }

    @discardableResult
    mutating func delete() -> Bool {
        guard !path.isEmpty else { return false }
        path.removeLast()
        return true
    }

    mutating func clear() { path.removeAll() }
}
