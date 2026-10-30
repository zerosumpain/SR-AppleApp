import Foundation

// The motion on the field, as times rather than as state that ticks: when
// each square started to uncover, when each mine shows in the ripple after a
// loss (or each flag plants after a win), and a few hundred sparks whose
// paths are worked out from their launch, so nothing is stepped per frame and
// a frame allocates nothing. The painter asks "where is everything at time
// t?" and the answer is arithmetic. Times are seconds since the reference date.

/// A spark, a clod of grass or a piece of confetti.
struct MinesweeperParticle: Sendable {
    enum Kind: UInt8, Sendable {
        /// Bits of turf flicked up as squares are dug.
        case turf
        /// Hot sparks from a mine.
        case spark
        /// Confetti for a win, drawn over the whole window.
        case confetti
    }

    var kind: Kind
    /// Launch point: in squares for turf and sparks, in fractions of the
    /// window for confetti.
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var gravity: Double
    var born: Double
    var life: Double
    var size: Double
    var spin: Double
    /// Picks the colour from the painter's set.
    var tint: Int

    /// Where it is `t` seconds after launch.
    func position(at now: Double) -> (x: Double, y: Double) {
        let t = max(0, now - born)
        return (x + vx * t, y + vy * t + 0.5 * gravity * t * t)
    }

    /// 1 at launch, fading to 0 at the end of its life.
    func fade(at now: Double) -> Double {
        let t = (now - born) / life
        if t < 0 || t > 1 { return 0 }
        return 1 - t * t
    }
}

struct MinesweeperEffects: Sendable {
    /// When each square began to uncover (0: long ago, drawn settled).
    private(set) var uncoverAt: [Double]
    /// When each mine appears after a loss, or each flag plants after a win.
    private(set) var rippleAt: [Double]
    /// When each flag last went in or came out, for its little pop.
    private(set) var flagAt: [Double]
    private(set) var particles: [MinesweeperParticle] = []
    /// When the board last shook (a mine).
    private(set) var shakeAt: Double = -100
    /// A number tapped without enough flags round it: its squares blink.
    private(set) var hintAt: Double = -100
    private(set) var hintCells: [Int] = []
    /// The last moment anything on the field is still moving.
    private(set) var settlesAt: Double = 0
    private var rng = MinesweeperRandom(seed: 7)

    /// How long a square takes to uncover.
    static let uncoverTime = 0.24
    /// How long a mine or flag takes to pop in.
    static let popTime = 0.32
    static let shakeTime = 0.45
    static let hintTime = 0.5
    /// The most sparks alive at once, so a big loss on Expert stays cheap.
    static let particleCap = 420

    init(count: Int) {
        uncoverAt = Array(repeating: 0, count: count)
        rippleAt = Array(repeating: 0, count: count)
        flagAt = Array(repeating: 0, count: count)
    }

    /// Anything still moving at `now`.
    func isMoving(at now: Double) -> Bool { now < settlesAt }

    private mutating func extend(to time: Double) {
        settlesAt = max(settlesAt, time)
    }

    private mutating func random(_ range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &rng)
    }

    /// Sparks that have finished are dropped before new ones are added.
    private mutating func prune(at now: Double) {
        particles.removeAll { now > $0.born + $0.life }
    }

    private mutating func add(_ p: MinesweeperParticle) {
        guard particles.count < Self.particleCap else { return }
        particles.append(p)
    }

    /// Squares opened by a dig: each starts a beat after the one before it in
    /// the flood, so a big opening rolls outwards. Returns how long it runs.
    @discardableResult
    mutating func uncover(_ opened: [MinesweeperOpening], width: Int, at now: Double) -> Double {
        guard !opened.isEmpty else { return 0 }
        prune(at: now)
        rng = MinesweeperRandom(seed: UInt64(truncatingIfNeeded: Int(now * 1000)) &+ UInt64(opened.count))
        let deepest = opened.reduce(0) { max($0, $1.depth) }
        // A beat per step of the flood, squeezed so the widest opening is done in about half a second.
        let beat = deepest == 0 ? 0 : min(0.028, 0.5 / Double(deepest))
        var last = now
        // Turf from a sample of the opened squares, so a huge opening does not flood the cap.
        let every = max(1, opened.count / 28)
        for (n, o) in opened.enumerated() where o.index >= 0 && o.index < uncoverAt.count {
            let start = now + Double(o.depth) * beat
            uncoverAt[o.index] = start
            last = max(last, start)
            if n % every == 0 {
                let cx = Double(o.index % width) + 0.5, cy = Double(o.index / width) + 0.5
                for _ in 0..<2 {
                    add(MinesweeperParticle(kind: .turf, x: cx + random(-0.25...0.25), y: cy + random(-0.2...0.2),
                                            vx: random(-2.2...2.2), vy: random(-5.5 ... -2.5), gravity: 16,
                                            born: start, life: random(0.45...0.7), size: random(0.12...0.22),
                                            spin: random(-8...8), tint: Int(random(0...2.99))))
                }
            }
        }
        let end = last + Self.uncoverTime + 0.7
        extend(to: end)
        return end - now
    }

    mutating func flag(_ index: Int, at now: Double) {
        guard index >= 0, index < flagAt.count else { return }
        flagAt[index] = now
        extend(to: now + Self.popTime)
    }

    /// A number with too few flags was tapped: its covered squares blink.
    mutating func hint(_ cells: [Int], at now: Double) {
        hintCells = cells
        hintAt = now
        extend(to: now + Self.hintTime)
    }

    /// How long after the start each square's turn comes in a ripple out from
    /// `origin`: further squares later, the furthest at `span` seconds.
    static func rippleDelays(from origin: Int, to cells: [Int], width: Int, span: Double) -> [Double] {
        guard !cells.isEmpty, width > 0 else { return [] }
        let ox = Double(origin % width), oy = Double(origin / width)
        let distances = cells.map { c -> Double in
            let dx = Double(c % width) - ox, dy = Double(c / width) - oy
            return (dx * dx + dy * dy).squareRoot()
        }
        let far = distances.max() ?? 0
        guard far > 0 else { return distances.map { _ in 0 } }
        // At most a tenth of a second per square of distance, so a small field does not crawl.
        let perSquare = min(0.1, span / far)
        return distances.map { $0 * perSquare }
    }

    /// A mine went off at `origin`: the board shakes, sparks fly, and every
    /// other mine shows in a ripple outwards. Returns when the ripple is done.
    @discardableResult
    mutating func explode(at origin: Int, mines: [Int], width: Int, now: Double) -> Double {
        prune(at: now)
        rng = MinesweeperRandom(seed: UInt64(truncatingIfNeeded: Int(now * 1000)) &+ 99)
        shakeAt = now
        let ox = Double(origin % width) + 0.5, oy = Double(origin / width) + 0.5
        if origin >= 0 && origin < rippleAt.count { rippleAt[origin] = now }
        for _ in 0..<36 {
            let angle = random(0...(2 * Double.pi)), speed = random(3...9)
            add(MinesweeperParticle(kind: .spark, x: ox, y: oy, vx: cos(angle) * speed, vy: sin(angle) * speed - 2,
                                    gravity: 9, born: now, life: random(0.5...1.0), size: random(0.08...0.18),
                                    spin: 0, tint: Int(random(0...2.99))))
        }
        let others = mines.filter { $0 != origin }
        let delays = Self.rippleDelays(from: origin, to: others, width: width, span: 1.5)
        var last = now
        let perMine = others.count > 60 ? 2 : 4
        for (m, delay) in zip(others, delays) where m >= 0 && m < rippleAt.count {
            let at = now + 0.25 + delay
            rippleAt[m] = at
            last = max(last, at)
            let mx = Double(m % width) + 0.5, my = Double(m / width) + 0.5
            for _ in 0..<perMine {
                let angle = random(0...(2 * Double.pi)), speed = random(1.5...4)
                add(MinesweeperParticle(kind: .spark, x: mx, y: my, vx: cos(angle) * speed, vy: sin(angle) * speed - 1,
                                        gravity: 7, born: at, life: random(0.35...0.6), size: random(0.07...0.13),
                                        spin: 0, tint: Int(random(0...2.99))))
            }
        }
        extend(to: max(now + Self.shakeTime, last + Self.popTime) + 1.0)
        return last + Self.popTime - now
    }

    /// The field is clear: a flag plants on every mine in a ripple from the
    /// last dig, and confetti falls. Returns when the flags are all in.
    @discardableResult
    mutating func celebrate(from origin: Int, mines: [Int], width: Int, now: Double) -> Double {
        prune(at: now)
        rng = MinesweeperRandom(seed: UInt64(truncatingIfNeeded: Int(now * 1000)) &+ 5)
        let delays = Self.rippleDelays(from: origin, to: mines, width: width, span: 1.0)
        var last = now
        for (m, delay) in zip(mines, delays) where m >= 0 && m < rippleAt.count {
            let at = now + 0.1 + delay
            rippleAt[m] = at
            flagAt[m] = at
            last = max(last, at)
        }
        for _ in 0..<90 {
            add(MinesweeperParticle(kind: .confetti, x: random(0.05...0.95), y: random(-0.25 ... -0.02),
                                    vx: random(-0.12...0.12), vy: random(0.15...0.45), gravity: 0.35,
                                    born: now + random(0...0.6), life: random(2.2...3.2), size: random(5...9),
                                    spin: random(-9...9), tint: Int(random(0...5.99))))
        }
        extend(to: max(last + Self.popTime, now + 3.8))
        return last + Self.popTime - now
    }
}
