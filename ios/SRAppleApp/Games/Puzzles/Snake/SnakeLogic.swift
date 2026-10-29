import Foundation

// Snake's rules, with nothing to draw: the grid, the snake on it, its turns,
// the apples and the golden apple, the speed it moves at and how a game ends.
// Foundation only, so every rule is unit-tested on the cheap Linux job.
//
// The board is `columns` × `rows` cells, x to the right and y DOWN the screen
// (the way it is drawn). The snake is a list of cells, head first.

/// One square of the board.
struct SnakePoint: Hashable, Codable {
    var x: Int
    var y: Int

    init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

/// Which way the head is going.
enum SnakeDirection: String, CaseIterable, Codable {
    case up, down, left, right

    var dx: Int {
        switch self {
        case .left: return -1
        case .right: return 1
        case .up, .down: return 0
        }
    }

    /// Down the screen is +1.
    var dy: Int {
        switch self {
        case .up: return -1
        case .down: return 1
        case .left, .right: return 0
        }
    }

    var opposite: SnakeDirection {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }

    /// Screen angle in radians: right is 0, down is a quarter turn clockwise.
    var angle: Double {
        switch self {
        case .right: return 0
        case .down: return Double.pi / 2
        case .left: return Double.pi
        case .up: return -Double.pi / 2
        }
    }

    /// For VoiceOver and the card: "up", "left".
    var word: String { rawValue }
}

/// The three ways to play.
enum SnakeMode: String, CaseIterable, Codable, Identifiable {
    /// The edges are walls.
    case classic
    /// Off one edge and back on the opposite one.
    case wrap
    /// The edges wrap, but walls stand on the board. Layouts open with score.
    case maze

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .wrap: return "Wrap"
        case .maze: return "Maze"
        }
    }

    var line: String {
        switch self {
        case .classic: return "The edges are walls. Stay on the grass."
        case .wrap: return "Go off one edge and you come back on the other side."
        case .maze: return "The edges wrap, but there are walls in the way. Score well to open the next maze."
        }
    }

    var icon: String {
        switch self {
        case .classic: return "square.dashed"
        case .wrap: return "arrow.left.arrow.right"
        case .maze: return "square.grid.3x3.middle.filled"
        }
    }

    /// The edge of the board ends the game.
    var edgesKill: Bool { self == .classic }
}

/// How a game ended.
enum SnakeDeath: String, Codable, Equatable {
    /// Ran off the board in Classic.
    case edge
    /// Ran into a maze wall.
    case wall
    /// Bit its own body.
    case tail

    var sentence: String {
        switch self {
        case .edge: return "You hit the edge."
        case .wall: return "You ran into a wall."
        case .tail: return "You bit your own tail."
        }
    }

    var tip: String {
        switch self {
        case .edge: return "Turn early: at top speed the edge comes up fast. Wrap mode has no edges."
        case .wall: return "Line up with a gap before you reach it. Two quick swipes make a U-turn."
        case .tail: return "Keep to the outside and leave yourself a way out as you grow."
        }
    }
}

/// A small, fast, seeded generator (SplitMix64), so a seed always gives the
/// same game: the tests rely on it, and so does the demo.
struct SnakeRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< n, the same on every platform and Swift version.
    mutating func below(_ n: Int) -> Int {
        guard n > 1 else { return 0 }
        let wide = next().multipliedFullWidth(by: UInt64(n))
        return Int(wide.high)
    }
}

/// The golden apple: worth a lot, there for a short while.
struct SnakeGolden: Equatable {
    var at: SnakePoint
    /// Steps of the snake before it goes.
    var stepsLeft: Int
    let steps: Int

    /// 1 when it has just appeared, 0 as it goes.
    var remaining: Double { steps > 0 ? Double(stepsLeft) / Double(steps) : 0 }
}

/// What one step did, for the screen's sounds, sparks and haptics.
struct SnakeStepResult: Equatable {
    var turned = false
    var ate: SnakePoint?
    var ateGolden: SnakePoint?
    var goldenAppeared: SnakePoint?
    var goldenMissed = false
    var died: SnakeDeath?
    /// No room left for an apple: the board is full and the game is won.
    var filled = false
}

/// The numbers the game is tuned by.
enum SnakeRules {
    static let columns = 15
    static let rows = 17
    static let startLength = 3
    static let applePoints = 10
    static let goldenPoints = 50
    /// How long a golden apple stays, in steps.
    static let goldenSteps = 42
    /// Apples before a golden one can appear at all.
    static let goldenAfter = 3
    /// After this many apples without one, the next apple always brings one.
    static let goldenAtMost = 6
    /// Quick swipes waiting their turn. Two make a U-turn; three is a cushion.
    static let maxQueuedTurns = 3

    /// Seconds a step takes at the start.
    static let startInterval = 0.18
    /// The fastest it ever goes.
    static let fastestInterval = 0.085
    /// Each apple makes a step this much shorter, until the cap.
    static let speedUp = 0.97

    /// Seconds per step after `eaten` apples: shorter with every apple, a
    /// little less each time, and never shorter than `fastestInterval`.
    static func stepInterval(eaten: Int) -> Double {
        let raw = startInterval * pow(speedUp, Double(max(0, eaten)))
        return max(fastestInterval, raw)
    }

    /// 0 at the start to 1 at top speed, for the speed gauge.
    static func speedLevel(eaten: Int) -> Double {
        let span = startInterval - fastestInterval
        guard span > 0 else { return 1 }
        return min(1, max(0, (startInterval - stepInterval(eaten: eaten)) / span))
    }

    /// The head's first cell and the way it faces, on any board.
    static func start(columns: Int, rows: Int) -> (head: SnakePoint, heading: SnakeDirection) {
        (SnakePoint(columns / 2 - 1, rows / 2), .right)
    }
}

/// One game of Snake.
struct SnakeGame {
    let columns: Int
    let rows: Int
    let mode: SnakeMode
    let walls: Set<SnakePoint>
    /// Head first.
    private(set) var body: [SnakePoint]
    private(set) var heading: SnakeDirection
    /// The heading before the last step, so a turn can be drawn as a curve.
    private(set) var previousHeading: SnakeDirection
    /// Swipes not yet acted on, oldest first.
    private(set) var turns: [SnakeDirection] = []
    private(set) var food: SnakePoint?
    private(set) var golden: SnakeGolden?
    /// The cell the tail left on the last step; nil when the snake grew.
    private(set) var vacated: SnakePoint?
    /// Steps still to come on which the tail stays put.
    private(set) var growth = 0
    private(set) var score = 0
    private(set) var eaten = 0
    private(set) var goldenEaten = 0
    private(set) var steps = 0
    private(set) var death: SnakeDeath?
    private(set) var filled = false
    private var applesSinceGolden = 0
    private var rng: SnakeRandom

    /// A new game: a short snake in the middle facing right, and an apple.
    init(mode: SnakeMode, maze: SnakeMaze? = nil, columns: Int = SnakeRules.columns,
         rows: Int = SnakeRules.rows, seed: UInt64) {
        let start = SnakeRules.start(columns: columns, rows: rows)
        var body: [SnakePoint] = []
        for i in 0..<SnakeRules.startLength {
            body.append(SnakePoint(start.head.x - i * start.heading.dx, start.head.y - i * start.heading.dy))
        }
        let walls: Set<SnakePoint> = mode == .maze ? (maze ?? SnakeMaze.all[0]).walls : []
        self.init(mode: mode, columns: columns, rows: rows, walls: walls, body: body,
                  heading: start.heading, food: nil, seed: seed)
    }

    /// Any position, for the tests. `food` nil places one at random.
    init(mode: SnakeMode, columns: Int, rows: Int, walls: Set<SnakePoint>, body: [SnakePoint],
         heading: SnakeDirection, food: SnakePoint?, seed: UInt64) {
        self.mode = mode
        self.columns = max(2, columns)
        self.rows = max(2, rows)
        self.walls = walls
        self.body = body
        self.heading = heading
        self.previousHeading = heading
        self.rng = SnakeRandom(seed: seed)
        if let food {
            self.food = food
        } else {
            self.food = spawnSpot(avoiding: nil)
        }
    }

    var head: SnakePoint { body[0] }
    var length: Int { body.count }
    var isOver: Bool { death != nil || filled }
    var stepInterval: Double { SnakeRules.stepInterval(eaten: eaten) }
    /// The way it will go next: the first queued turn, or straight on.
    var nextHeading: SnakeDirection { turns.first ?? heading }

    // MARK: - Turning

    /// Queue a turn. Ignored when it is the way the snake will already be
    /// going, straight back on itself, or the queue is full. Each turn is
    /// checked against the one queued before it, so two quick swipes (up,
    /// then left, while going right) both count.
    @discardableResult
    mutating func turn(_ direction: SnakeDirection) -> Bool {
        guard !isOver else { return false }
        let reference = turns.last ?? heading
        guard direction != reference, direction != reference.opposite else { return false }
        guard turns.count < SnakeRules.maxQueuedTurns else { return false }
        turns.append(direction)
        return true
    }

    // MARK: - Moving

    /// The cell one step from `point`, wrapped round the edges; nil when it
    /// is off the board in a mode where the edges are walls.
    func neighbour(of point: SnakePoint, going direction: SnakeDirection) -> SnakePoint? {
        let x = point.x + direction.dx
        let y = point.y + direction.dy
        if mode.edgesKill {
            guard x >= 0, x < columns, y >= 0, y < rows else { return nil }
            return SnakePoint(x, y)
        }
        return SnakePoint((x % columns + columns) % columns, (y % rows + rows) % rows)
    }

    /// One move of one cell.
    mutating func step() -> SnakeStepResult {
        var result = SnakeStepResult()
        guard !isOver else { return result }
        previousHeading = heading
        if !turns.isEmpty {
            heading = turns.removeFirst()
            result.turned = true
        }
        guard let next = neighbour(of: head, going: heading) else {
            death = .edge
            result.died = .edge
            vacated = nil
            return result
        }
        if walls.contains(next) {
            death = .wall
            result.died = .wall
            vacated = nil
            return result
        }
        // The tail moves out of the way this step unless the snake is growing,
        // so chasing your own tail round a tight loop is allowed.
        let tailLeaves = growth == 0
        let solid = tailLeaves ? body.count - 1 : body.count
        if body.prefix(solid).contains(next) {
            death = .tail
            result.died = .tail
            vacated = nil
            return result
        }

        body.insert(next, at: 0)
        if tailLeaves {
            vacated = body.removeLast()
        } else {
            growth -= 1
            vacated = nil
        }
        steps += 1

        if var gold = golden {
            if gold.at == next {
                score += SnakeRules.goldenPoints
                goldenEaten += 1
                golden = nil
                result.ateGolden = next
            } else {
                gold.stepsLeft -= 1
                if gold.stepsLeft <= 0 {
                    golden = nil
                    result.goldenMissed = true
                } else {
                    golden = gold
                }
            }
        }

        if next == food {
            score += SnakeRules.applePoints
            eaten += 1
            growth += 1
            result.ate = next
            // Long enough (counting the growing still to come) to cover every
            // open cell: the board is full and the game is won.
            if body.count + growth >= columns * rows - walls.count {
                food = nil
                golden = nil
                filled = true
                result.filled = true
                return result
            }
            food = spawnSpot(avoiding: nil)
            result.goldenAppeared = maybeGolden()
        } else if food == nil {
            // The last free cell was under the golden apple; now it is gone.
            food = spawnSpot(avoiding: nil)
        }
        return result
    }

    // MARK: - Apples

    /// Every cell an apple could go in: not a wall, not the snake, not the
    /// other apple.
    func freeCells(avoiding extra: SnakePoint?) -> [SnakePoint] {
        let taken = Set(body)
        var out: [SnakePoint] = []
        out.reserveCapacity(columns * rows)
        for y in 0..<rows {
            for x in 0..<columns {
                let p = SnakePoint(x, y)
                if walls.contains(p) || taken.contains(p) { continue }
                if p == extra || p == golden?.at || p == food { continue }
                out.append(p)
            }
        }
        return out
    }

    private mutating func spawnSpot(avoiding extra: SnakePoint?) -> SnakePoint? {
        let free = freeCells(avoiding: extra)
        guard !free.isEmpty else { return nil }
        return free[rng.below(free.count)]
    }

    /// Put a golden apple down now. For the tests and nothing else.
    mutating func placeGolden(at spot: SnakePoint, steps: Int = SnakeRules.goldenSteps) {
        golden = SnakeGolden(at: spot, stepsLeft: steps, steps: steps)
    }

    /// After an apple: perhaps a golden one, never before the third apple,
    /// and always by the sixth without one.
    private mutating func maybeGolden() -> SnakePoint? {
        guard golden == nil, eaten >= SnakeRules.goldenAfter else { return nil }
        applesSinceGolden += 1
        let due = applesSinceGolden >= SnakeRules.goldenAtMost || rng.below(4) == 0
        guard due, let spot = spawnSpot(avoiding: nil) else { return nil }
        applesSinceGolden = 0
        golden = SnakeGolden(at: spot, stepsLeft: SnakeRules.goldenSteps, steps: SnakeRules.goldenSteps)
        return spot
    }
}

/// Steers for the demo: towards the nearest apple, never into a wall or
/// itself if there is another way. Not clever, but it keeps going a while.
enum SnakeAutopilot {
    static func choose(_ game: SnakeGame) -> SnakeDirection {
        let target = game.golden?.at ?? game.food ?? game.head
        var best = game.heading
        var bestScore = Int.min
        for direction in SnakeDirection.allCases where direction != game.heading.opposite {
            guard let next = game.neighbour(of: game.head, going: direction) else { continue }
            if game.walls.contains(next) || game.body.dropLast().contains(next) { continue }
            let dx = distance(next.x, target.x, span: game.columns, wraps: !game.mode.edgesKill)
            let dy = distance(next.y, target.y, span: game.rows, wraps: !game.mode.edgesKill)
            let room = openNeighbours(of: next, in: game)
            let score = -(dx + dy) * 4 + room * 3 + (direction == game.heading ? 1 : 0)
            if score > bestScore {
                bestScore = score
                best = direction
            }
        }
        return best
    }

    private static func distance(_ a: Int, _ b: Int, span: Int, wraps: Bool) -> Int {
        let straight = abs(a - b)
        return wraps ? min(straight, span - straight) : straight
    }

    private static func openNeighbours(of point: SnakePoint, in game: SnakeGame) -> Int {
        var count = 0
        for direction in SnakeDirection.allCases {
            guard let n = game.neighbour(of: point, going: direction) else { continue }
            if !game.walls.contains(n) && !game.body.contains(n) { count += 1 }
        }
        return count
    }
}
