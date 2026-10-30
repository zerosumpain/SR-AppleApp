import Foundation

// Tilt Maze's board: a grid of square cells with thin wooden walls between
// them, holes to drop down, checkpoints to come back to, a start and a brass
// goal cup. Everything is in cell units — a cell is 1 × 1, x across from the
// left, y down from the top, the same way round as the screen — so the rules
// never need to know how big the phone is.
//
// Foundation only: the physics, the generator and the tests all read it.

/// One square of a maze: column `x`, row `y`, from the top-left.
struct TiltMazeCell: Hashable, Codable {
    var x: Int
    var y: Int

    init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    /// The middle of the cell, in board units.
    var centre: TiltMazeVector { TiltMazeVector(x: Double(x) + 0.5, y: Double(y) + 0.5) }

    /// The four cells sharing a side, in a fixed order (right, left, down, up)
    /// so a search always finds the same path.
    var sides: [TiltMazeCell] {
        [TiltMazeCell(x + 1, y), TiltMazeCell(x - 1, y), TiltMazeCell(x, y + 1), TiltMazeCell(x, y - 1)]
    }
}

/// A point or a direction on the board, in cell units. Also the tilt, in g.
struct TiltMazeVector: Equatable {
    var x: Double
    var y: Double

    static let zero = TiltMazeVector(x: 0, y: 0)

    var length: Double { (x * x + y * y).squareRoot() }

    func distance(to other: TiltMazeVector) -> Double {
        let dx = other.x - x, dy = other.y - y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// A solid wooden wall as an axis-aligned box. Neighbouring wall pieces on
/// one line are merged into a single long box, so a corridor wall is one
/// thing to bump along rather than a row of seams.
struct TiltMazeBox: Equatable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
}

/// A maze: its walls, holes, checkpoints, start and goal.
struct TiltMazeLevel: Equatable {
    let cols: Int
    let rows: Int
    /// `vertical[y * (cols + 1) + x]`: a wall on the line x, beside row y
    /// (the west side of cell (x, y)). x runs 0...cols.
    let vertical: [Bool]
    /// `horizontal[y * cols + x]`: a wall on the line y, above column x
    /// (the north side of cell (x, y)). y runs 0...rows.
    let horizontal: [Bool]
    let start: TiltMazeCell
    let goal: TiltMazeCell
    let holes: [TiltMazeCell]
    /// Reached in any order; a fall goes back to the last one rolled over.
    let checkpoints: [TiltMazeCell]
    /// The walls as boxes, merged into runs: what the ball bumps and what is drawn.
    let boxes: [TiltMazeBox]
    let holeSet: Set<TiltMazeCell>

    /// The outer walls are always there, whatever the arrays say: the ball
    /// can never leave the board.
    init(cols: Int, rows: Int, vertical: [Bool], horizontal: [Bool], start: TiltMazeCell, goal: TiltMazeCell,
         holes: [TiltMazeCell], checkpoints: [TiltMazeCell]) {
        let cols = max(1, cols), rows = max(1, rows)
        var v = vertical.count == (cols + 1) * rows ? vertical : [Bool](repeating: true, count: (cols + 1) * rows)
        var h = horizontal.count == cols * (rows + 1) ? horizontal : [Bool](repeating: true, count: cols * (rows + 1))
        for y in 0..<rows {
            v[y * (cols + 1)] = true
            v[y * (cols + 1) + cols] = true
        }
        for x in 0..<cols {
            h[x] = true
            h[rows * cols + x] = true
        }
        self.cols = cols
        self.rows = rows
        self.vertical = v
        self.horizontal = h
        self.start = start
        self.goal = goal
        // A hole never sits on the start or the goal.
        let cleanHoles = holes.filter { $0 != start && $0 != goal }
        self.holes = cleanHoles
        self.checkpoints = checkpoints.filter { $0 != start && $0 != goal && !cleanHoles.contains($0) }
        self.holeSet = Set(cleanHoles)
        self.boxes = Self.mergedBoxes(cols: cols, rows: rows, vertical: v, horizontal: h)
    }

    /// Every wall standing: the starting block a generator carves into.
    static func solidWalls(cols: Int, rows: Int) -> (vertical: [Bool], horizontal: [Bool]) {
        ([Bool](repeating: true, count: (cols + 1) * rows), [Bool](repeating: true, count: cols * (rows + 1)))
    }

    var cellCount: Int { cols * rows }
    var width: Double { Double(cols) }
    var height: Double { Double(rows) }

    func contains(_ cell: TiltMazeCell) -> Bool {
        cell.x >= 0 && cell.y >= 0 && cell.x < cols && cell.y < rows
    }

    func index(_ cell: TiltMazeCell) -> Int { cell.y * cols + cell.x }

    func cell(at index: Int) -> TiltMazeCell { TiltMazeCell(index % cols, index / cols) }

    /// The cell a point on the board is over, kept on the board.
    func cell(under point: TiltMazeVector) -> TiltMazeCell {
        let x = min(max(Int(point.x.rounded(.down)), 0), cols - 1)
        let y = min(max(Int(point.y.rounded(.down)), 0), rows - 1)
        return TiltMazeCell(x, y)
    }

    func wallWest(_ x: Int, _ y: Int) -> Bool { vertical[y * (cols + 1) + x] }
    func wallNorth(_ x: Int, _ y: Int) -> Bool { horizontal[y * cols + x] }

    /// Whether the ball can roll straight from `a` to the side-by-side cell `b`.
    func isOpen(_ a: TiltMazeCell, _ b: TiltMazeCell) -> Bool {
        guard contains(a), contains(b) else { return false }
        if b.y == a.y && b.x == a.x + 1 { return !wallWest(b.x, b.y) }
        if b.y == a.y && b.x == a.x - 1 { return !wallWest(a.x, a.y) }
        if b.x == a.x && b.y == a.y + 1 { return !wallNorth(b.x, b.y) }
        if b.x == a.x && b.y == a.y - 1 { return !wallNorth(a.x, a.y) }
        return false
    }

    /// The cells the ball can roll into from `cell`.
    func neighbours(of cell: TiltMazeCell) -> [TiltMazeCell] {
        cell.sides.filter { isOpen(cell, $0) }
    }

    /// The shortest way from `a` to `b` through open sides, both ends
    /// included; round the holes unless `avoidingHoles` is false. Nil when
    /// there is none.
    func path(from a: TiltMazeCell, to b: TiltMazeCell, avoidingHoles: Bool = true) -> [TiltMazeCell]? {
        guard contains(a), contains(b) else { return nil }
        let target = index(b)
        var previous = [Int](repeating: -1, count: cellCount)
        var seen = [Bool](repeating: false, count: cellCount)
        var queue: [Int] = [index(a)]
        seen[index(a)] = true
        var head = 0
        while head < queue.count {
            let i = queue[head]
            head += 1
            if i == target { break }
            for next in neighbours(of: cell(at: i)) {
                let j = index(next)
                if seen[j] { continue }
                if avoidingHoles && holeSet.contains(next) && next != b { continue }
                seen[j] = true
                previous[j] = i
                queue.append(j)
            }
        }
        guard seen[target] else { return nil }
        var out: [TiltMazeCell] = [b]
        var i = target
        while previous[i] >= 0 {
            i = previous[i]
            out.append(cell(at: i))
        }
        return out.reversed()
    }

    /// The way from the start to the goal, round every hole.
    var solution: [TiltMazeCell]? { path(from: start, to: goal) }

    /// Steps from `a` to every cell it can reach (−1 for none), ignoring holes.
    func distances(from a: TiltMazeCell) -> [Int] {
        var distance = [Int](repeating: -1, count: cellCount)
        guard contains(a) else { return distance }
        var queue: [Int] = [index(a)]
        distance[index(a)] = 0
        var head = 0
        while head < queue.count {
            let i = queue[head]
            head += 1
            for next in neighbours(of: cell(at: i)) where distance[index(next)] < 0 {
                distance[index(next)] = distance[i] + 1
                queue.append(index(next))
            }
        }
        return distance
    }

    // MARK: - Walls as boxes

    private static func mergedBoxes(cols: Int, rows: Int, vertical: [Bool], horizontal: [Bool]) -> [TiltMazeBox] {
        let half = TiltMazeRules.wall / 2
        var boxes: [TiltMazeBox] = []
        // Runs along each horizontal line, each end grown by half a wall so
        // runs meeting at a corner post leave no gap.
        for y in 0...rows {
            var x = 0
            while x < cols {
                guard horizontal[y * cols + x] else {
                    x += 1
                    continue
                }
                let first = x
                while x < cols && horizontal[y * cols + x] { x += 1 }
                boxes.append(TiltMazeBox(minX: Double(first) - half, minY: Double(y) - half,
                                         maxX: Double(x) + half, maxY: Double(y) + half))
            }
        }
        for x in 0...cols {
            var y = 0
            while y < rows {
                guard vertical[y * (cols + 1) + x] else {
                    y += 1
                    continue
                }
                let first = y
                while y < rows && vertical[y * (cols + 1) + x] { y += 1 }
                boxes.append(TiltMazeBox(minX: Double(x) - half, minY: Double(first) - half,
                                         maxX: Double(x) + half, maxY: Double(y) + half))
            }
        }
        return boxes
    }

    // MARK: - Drawn by hand

    /// A maze drawn in text, two characters a cell plus one:
    ///
    ///     +-+-+
    ///     |S  |      `+` a corner post, `-` and `|` a wall, a space no wall;
    ///     + +-+      in a cell, `S` the start, `G` the goal, `O` a hole,
    ///     |  G|      `C` a checkpoint.
    ///     +-+-+
    ///
    /// Nil when the drawing is ragged or has no start or goal.
    static func parse(_ lines: [String]) -> TiltMazeLevel? {
        let grid: [[Character]] = lines.map { Array($0) }
        guard grid.count >= 3, grid.count % 2 == 1, let width = grid.first?.count, width >= 3, width % 2 == 1,
              grid.allSatisfy({ $0.count == width }) else { return nil }
        let cols = width / 2, rows = grid.count / 2
        var vertical = [Bool](repeating: false, count: (cols + 1) * rows)
        var horizontal = [Bool](repeating: false, count: cols * (rows + 1))
        var start: TiltMazeCell?
        var goal: TiltMazeCell?
        var holes: [TiltMazeCell] = []
        var checkpoints: [TiltMazeCell] = []
        let space: Character = " "
        for y in 0..<rows {
            let line = grid[2 * y + 1]
            for x in 0...cols {
                vertical[y * (cols + 1) + x] = line[2 * x] != space
            }
            for x in 0..<cols {
                let cell = TiltMazeCell(x, y)
                switch line[2 * x + 1] {
                case "S": start = cell
                case "G": goal = cell
                case "O": holes.append(cell)
                case "C": checkpoints.append(cell)
                default: break
                }
            }
        }
        for y in 0...rows {
            let line = grid[2 * y]
            for x in 0..<cols {
                horizontal[y * cols + x] = line[2 * x + 1] != space
            }
        }
        guard let first = start, let last = goal else { return nil }
        return TiltMazeLevel(cols: cols, rows: rows, vertical: vertical, horizontal: horizontal, start: first, goal: last,
                             holes: holes, checkpoints: checkpoints)
    }
}

/// The clock to beat for each star on a level, from how long and twisty the
/// way through is. A finish always earns one star.
struct TiltMazePar: Equatable {
    /// At or under this many seconds: three stars.
    let three: Double
    /// At or under this: two.
    let two: Double

    static func of(_ level: TiltMazeLevel) -> TiltMazePar {
        let path = level.solution ?? []
        let steps = Double(max(0, path.count - 1))
        let turns = Double(Self.turns(in: path))
        let three = (2.0 + 0.38 * steps + 0.32 * turns).rounded()
        let two = (three * 1.6 + 4).rounded()
        return TiltMazePar(three: three, two: two)
    }

    /// How many corners a path turns.
    static func turns(in path: [TiltMazeCell]) -> Int {
        guard path.count > 2 else { return 0 }
        var turns = 0
        for i in 1..<(path.count - 1) {
            let a = path[i - 1], b = path[i], c = path[i + 1]
            if (b.x - a.x) != (c.x - b.x) || (b.y - a.y) != (c.y - b.y) { turns += 1 }
        }
        return turns
    }

    func stars(for time: Double) -> Int {
        if time <= three { return 3 }
        if time <= two { return 2 }
        return 1
    }
}

/// A small, fast, seeded random source (SplitMix64), so a level number
/// always makes the same maze on every phone.
struct TiltMazeRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed ^ 0x5DEE_CE66_D1CE_4E5B
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0..<n (0 when n is not positive).
    mutating func int(_ n: Int) -> Int {
        guard n > 0 else { return 0 }
        return Int(next() % UInt64(n))
    }

    /// 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }

    mutating func shuffle<T>(_ items: inout [T]) {
        guard items.count > 1 else { return }
        for i in stride(from: items.count - 1, to: 0, by: -1) {
            let j = int(i + 1)
            if i != j { items.swapAt(i, j) }
        }
    }
}
