import Foundation

// Minesweeper's rules, kept apart from the screen so they run (and are tested)
// anywhere: the three classic fields and a custom one, mines laid only after
// the first dig so it is always safe, flood-fill through the empty squares,
// flags, chords and the win. Nothing here knows about time or drawing.

/// Which field to play.
enum MinesweeperLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case beginner
    case intermediate
    case expert
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .expert: return "Expert"
        case .custom: return "Custom"
        }
    }

    /// Width, height and mines for the standard fields. Expert is the classic
    /// 30 × 16 stood on its end, so it fills a phone held upright.
    var standardSize: (width: Int, height: Int, mines: Int)? {
        switch self {
        case .beginner: return (9, 9, 10)
        case .intermediate: return (16, 16, 40)
        case .expert: return (16, 30, 99)
        case .custom: return nil
        }
    }

    var icon: String {
        switch self {
        case .beginner: return "leaf.fill"
        case .intermediate: return "flame.fill"
        case .expert: return "bolt.fill"
        case .custom: return "slider.horizontal.3"
        }
    }
}

/// The choices on the start card, remembered between games.
struct MinesweeperSetup: Codable, Equatable, Sendable {
    var level: MinesweeperLevel = .beginner
    var customWidth = 12
    var customHeight = 18
    var customMines = 30
    /// Lay only fields that logic alone can clear from the first dig.
    var noGuess = false

    /// Custom sides run 5 to 30 squares.
    static let sides = 5...30

    /// The most mines a custom field can hold: everything but the first dig's
    /// three-by-three, so the first dig always opens an area.
    static func mostMines(width: Int, height: Int) -> Int { max(1, width * height - 9) }

    var width: Int {
        level.standardSize?.width ?? min(Self.sides.upperBound, max(Self.sides.lowerBound, customWidth))
    }

    var height: Int {
        level.standardSize?.height ?? min(Self.sides.upperBound, max(Self.sides.lowerBound, customHeight))
    }

    var mines: Int {
        level.standardSize?.mines ?? min(Self.mostMines(width: width, height: height), max(1, customMines))
    }

    /// The key a best time is kept under. A no-guessing field is a different
    /// puzzle from a lucky one, so their times are kept apart.
    var recordKey: String {
        let base: String
        if level == .custom {
            base = "custom-\(width)x\(height)-\(mines)"
        } else {
            base = level.rawValue
        }
        return noGuess ? base + "-logic" : base
    }

    /// "9 × 9 · 10 mines"
    var sizeLine: String { "\(width) × \(height) · \(mines) mines" }

    /// Keeps the custom numbers inside the limits after a stepper moves.
    mutating func tidyCustom() {
        customWidth = min(Self.sides.upperBound, max(Self.sides.lowerBound, customWidth))
        customHeight = min(Self.sides.upperBound, max(Self.sides.lowerBound, customHeight))
        customMines = min(Self.mostMines(width: customWidth, height: customHeight), max(1, customMines))
    }
}

/// A small, fast, seedable generator (SplitMix64), so a test can lay the same
/// field twice.
struct MinesweeperRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed ^ 0x5DEE_CE66_D1CE_4E5B }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// What the player can see of one square.
enum MinesweeperCell: UInt8, Codable, Sendable {
    case hidden
    case flagged
    case revealed
}

enum MinesweeperStatus: Equatable, Sendable {
    /// Nothing dug yet; the mines are not laid.
    case ready
    case playing
    case won
    case lost
}

/// One square uncovered by a dig, and how many steps the flood took to reach
/// it (the screen ripples the opening outwards by it).
struct MinesweeperOpening: Equatable, Sendable {
    var index: Int
    var depth: Int
}

/// What a dig, a chord or a first dig did.
struct MinesweeperOutcome: Equatable, Sendable {
    var opened: [MinesweeperOpening] = []
    /// The mine that went off, if one did.
    var hitMine: Int? = nil
    /// This move cleared the field.
    var won = false

    var changed: Bool { !opened.isEmpty || hitMine != nil }
}

/// The field: where the mines are, what is showing, and whether it is over.
struct MinesweeperBoard: Equatable, Sendable {
    let width: Int
    let height: Int
    let mineCount: Int
    private(set) var mines: [Bool]
    /// Mines touching each square (0 to 8), valid once the mines are laid.
    private(set) var counts: [Int]
    private(set) var cells: [MinesweeperCell]
    private(set) var minesLaid = false
    private(set) var status: MinesweeperStatus = .ready
    /// The mine that ended the game.
    private(set) var exploded: Int? = nil
    /// Safe squares uncovered so far.
    private(set) var revealedCount = 0
    private(set) var flagCount = 0

    /// An empty field, mines to be laid on the first dig.
    init(width: Int, height: Int, mines: Int) {
        let w = max(2, width), h = max(2, height)
        self.width = w
        self.height = h
        mineCount = max(0, min(mines, w * h - 1))
        self.mines = Array(repeating: false, count: w * h)
        counts = Array(repeating: 0, count: w * h)
        cells = Array(repeating: .hidden, count: w * h)
    }

    /// A field with its mines already in place: for tests and the start card's picture.
    init(width: Int, height: Int, mineAt spots: Set<Int>) {
        let w = max(2, width), h = max(2, height)
        let valid = spots.filter { $0 >= 0 && $0 < w * h }
        self.init(width: w, height: h, mines: valid.count)
        lay(valid)
    }

    var size: Int { width * height }
    var safeCount: Int { size - mineCount }
    /// The counter at the top: mines less flags. Can go below zero.
    var minesLeft: Int { mineCount - flagCount }
    var isOver: Bool { status == .won || status == .lost }

    func column(of index: Int) -> Int { index % width }
    func row(of index: Int) -> Int { index / width }
    func index(column: Int, row: Int) -> Int { row * width + column }

    func contains(column: Int, row: Int) -> Bool {
        column >= 0 && column < width && row >= 0 && row < height
    }

    /// The up-to-eight squares touching `index`.
    func neighbours(of index: Int) -> [Int] {
        var out: [Int] = []
        out.reserveCapacity(8)
        forEachNeighbour(of: index) { out.append($0) }
        return out
    }

    /// Calls `body` with each square touching `index`, without building an
    /// array: the flood and the solver run this hundreds of thousands of times.
    @inline(__always)
    func forEachNeighbour(of index: Int, _ body: (Int) -> Void) {
        let c = index % width, r = index / width
        let left = c > 0, right = c < width - 1
        if r > 0 {
            let up = index - width
            if left { body(up - 1) }
            body(up)
            if right { body(up + 1) }
        }
        if left { body(index - 1) }
        if right { body(index + 1) }
        if r < height - 1 {
            let down = index + width
            if left { body(down - 1) }
            body(down)
            if right { body(down + 1) }
        }
    }

    /// The first dig and everything touching it: kept clear of mines so the
    /// first dig opens an area. When a crowded custom field cannot spare
    /// them all, only the dig itself is kept clear.
    func spared(around index: Int) -> Set<Int> {
        var keep = Set(neighbours(of: index))
        keep.insert(index)
        if size - keep.count >= mineCount { return keep }
        return [index]
    }

    /// Lays the mines at random anywhere but `spared(around: first)`.
    mutating func layMines<R: RandomNumberGenerator>(sparing first: Int, using rng: inout R) {
        guard !minesLaid, first >= 0, first < size else { return }
        let keep = spared(around: first)
        var spots: [Int] = []
        spots.reserveCapacity(size)
        for i in 0..<size where !keep.contains(i) { spots.append(i) }
        // A partial Fisher–Yates: the first `mineCount` places are the mines.
        let take = min(mineCount, spots.count)
        for i in 0..<take {
            let j = Int.random(in: i..<spots.count, using: &rng)
            spots.swapAt(i, j)
        }
        lay(Set(spots.prefix(take)))
    }

    private mutating func lay(_ spots: Set<Int>) {
        for i in 0..<size { mines[i] = spots.contains(i) }
        for i in 0..<size {
            var n = 0
            forEachNeighbour(of: i) { if mines[$0] { n += 1 } }
            counts[i] = n
        }
        minesLaid = true
        status = .playing
    }

    /// The first dig of a game: lays the mines clear of it, then digs.
    mutating func firstDig<R: RandomNumberGenerator>(_ index: Int, using rng: inout R) -> MinesweeperOutcome {
        layMines(sparing: index, using: &rng)
        return reveal(index)
    }

    /// Digs one square. An empty one (no mines touching) opens the whole
    /// empty region and its numbered edge. Flags are never dug.
    mutating func reveal(_ index: Int) -> MinesweeperOutcome {
        var outcome = MinesweeperOutcome()
        guard status == .playing, index >= 0, index < size, cells[index] == .hidden else { return outcome }
        open(from: index, into: &outcome)
        settle(&outcome)
        return outcome
    }

    /// Plants or lifts a flag. False when nothing changed.
    @discardableResult
    mutating func toggleFlag(_ index: Int) -> Bool {
        guard status == .playing, index >= 0, index < size else { return false }
        switch cells[index] {
        case .hidden:
            cells[index] = .flagged
            flagCount += 1
            return true
        case .flagged:
            cells[index] = .hidden
            flagCount -= 1
            return true
        case .revealed:
            return false
        }
    }

    func flags(around index: Int) -> Int {
        var n = 0
        forEachNeighbour(of: index) { if cells[$0] == .flagged { n += 1 } }
        return n
    }

    func hiddenNeighbours(of index: Int) -> [Int] {
        neighbours(of: index).filter { cells[$0] == .hidden }
    }

    /// A number can be chorded when it is showing, it has exactly as many
    /// flags round it as it says, and something round it is still covered.
    func canChord(_ index: Int) -> Bool {
        guard status == .playing, index >= 0, index < size, cells[index] == .revealed, counts[index] > 0 else { return false }
        return flags(around: index) == counts[index] && !hiddenNeighbours(of: index).isEmpty
    }

    /// Digs every unflagged square round a satisfied number in one go. A
    /// flag in the wrong place means a mine is dug: the game is lost.
    mutating func chord(_ index: Int) -> MinesweeperOutcome {
        var outcome = MinesweeperOutcome()
        guard canChord(index) else { return outcome }
        for n in hiddenNeighbours(of: index) {
            guard status == .playing, cells[n] == .hidden else { continue }
            open(from: n, into: &outcome)
        }
        settle(&outcome)
        return outcome
    }

    /// Flags on squares with no mine under them: shown crossed out at the end.
    var wrongFlags: [Int] {
        (0..<size).filter { cells[$0] == .flagged && !mines[$0] }
    }

    var mineIndices: [Int] { (0..<size).filter { mines[$0] } }

    // MARK: - Digging

    private mutating func open(from start: Int, into outcome: inout MinesweeperOutcome) {
        guard cells[start] == .hidden else { return }
        cells[start] = .revealed
        if mines[start] {
            exploded = start
            status = .lost
            outcome.hitMine = start
            return
        }
        revealedCount += 1
        outcome.opened.append(MinesweeperOpening(index: start, depth: 0))
        var queue: [MinesweeperOpening] = [MinesweeperOpening(index: start, depth: 0)]
        var head = 0
        while head < queue.count {
            let here = queue[head]
            head += 1
            guard counts[here.index] == 0 else { continue }
            var found: [Int] = []
            forEachNeighbour(of: here.index) { n in
                if cells[n] == .hidden && !mines[n] { found.append(n) }
            }
            for n in found {
                cells[n] = .revealed
                revealedCount += 1
                let next = MinesweeperOpening(index: n, depth: here.depth + 1)
                outcome.opened.append(next)
                queue.append(next)
            }
        }
    }

    /// After a move: a cleared field is won, and every mine gets its flag.
    private mutating func settle(_ outcome: inout MinesweeperOutcome) {
        guard status == .playing, revealedCount == safeCount else { return }
        status = .won
        outcome.won = true
        for i in 0..<size where mines[i] { cells[i] = .flagged }
        flagCount = mineCount
    }
}
