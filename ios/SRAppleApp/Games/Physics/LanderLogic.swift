import Foundation

// Lander: bring a little craft down onto a landing pad by tilting the phone
// and holding a finger down for thrust. One player, on this phone, offline.
//
// Every rule lives here, free of SwiftUI, SceneKit and Core Motion, so the
// whole flight is a unit test on Linux: the screen only turns tilt and touch
// into a `LanderInput`, calls `step` once a frame and draws `craft`.
//
// The world is flat 2D in METRES and SECONDS: x runs right, y runs up, the
// ground is a height map. The screen draws it in 3D (the terrain extruded
// into a ridge, a camera that follows the craft), but a landing is decided in
// the plane, which keeps the maths honest and the tests exact.

/// One level: how strong gravity is, how much fuel the tank holds, how wide
/// the pad is, and the wind. Each level is harder than the last, up to a
/// ceiling that a good pilot can still land.
struct LanderLevel: Codable, Equatable {
    let number: Int
    /// Downward pull, m/s². The Moon's is 1.62.
    let gravity: Double
    /// Fuel at the start, in units: full thrust burns `LanderRules.burnRate` a second.
    let fuel: Double
    /// The pad's width, metres, before it is snapped to the terrain grid.
    let padWidth: Double
    /// A steady sideways push, m/s² (positive pushes right).
    let wind: Double
    /// How jagged the ground is: the largest climb between two grid points, as a slope.
    let roughness: Double

    static func make(_ number: Int) -> LanderLevel {
        let n = max(1, number)
        let step = Double(min(n, 10) - 1)
        // Wind arrives on level 3 and swaps side each level, so a pilot cannot
        // learn one lean and keep it.
        let windStrength = n >= 3 ? min(0.3, 0.1 + 0.03 * Double(n - 3)) : 0
        return LanderLevel(
            number: n,
            gravity: min(2.5, 1.62 + 0.11 * step),
            fuel: max(80, 110 - 3 * step),
            padWidth: max(16, 40 - 3 * step),
            wind: n % 2 == 0 ? windStrength : -windStrength,
            roughness: min(1.2, 0.45 + 0.08 * step)
        )
    }

    /// A place name for the level's heading, so a run reads like a journey.
    var place: String {
        let places = ["Sea of Tranquility", "Ocean of Storms", "Sea of Serenity", "Bay of Rainbows",
                      "Lake of Dreams", "Sea of Crises", "Marsh of Decay", "Sea of Clouds",
                      "Tycho's Rim", "Shackleton's Edge"]
        return places[(number - 1) % places.count]
    }
}

/// The ground: heights every `step` metres across the world, with one flat
/// pad. Heights are metres above the world's floor.
struct LanderTerrain: Codable, Equatable {
    let heights: [Double]
    let step: Double
    let padStart: Double
    let padEnd: Double
    let padHeight: Double

    var width: Double { Double(max(0, heights.count - 1)) * step }
    var padCentre: Double { (padStart + padEnd) / 2 }
    var padWidth: Double { padEnd - padStart }
    var highest: Double { heights.max() ?? 0 }

    /// The ground's height under `x`, straight lines between grid points.
    func height(at x: Double) -> Double {
        guard heights.count > 1, step > 0 else { return heights.first ?? 0 }
        let position = min(max(x / step, 0), Double(heights.count - 1))
        let index = min(Int(position), heights.count - 2)
        let fraction = position - Double(index)
        return heights[index] + (heights[index + 1] - heights[index]) * fraction
    }

    /// Whether `x` is on the pad itself.
    func isOnPad(_ x: Double) -> Bool { x >= padStart && x <= padEnd }

    /// The highest ground between two x positions, either way round — what a
    /// craft flying from one to the other has to clear.
    func highest(between a: Double, and b: Double) -> Double {
        let lo = max(0, min(a, b)), hi = min(width, max(a, b))
        var best = max(height(at: lo), height(at: hi))
        var x = (lo / step).rounded(.up) * step
        while x < hi {
            best = max(best, height(at: x))
            x += step
        }
        return best
    }

    /// A level's ground, the same for the same seed on every phone and in
    /// every test. The pad sits on the far side from where the craft starts.
    static func generate(level: LanderLevel, seed: UInt64, startsLeft: Bool) -> LanderTerrain {
        var rng = LanderRandom(seed: seed)
        let step = LanderRules.terrainStep
        let count = Int(LanderRules.worldWidth / step) + 1
        var heights: [Double] = []
        heights.reserveCapacity(count)
        var h = rng.double(in: 30...70)
        for _ in 0..<count {
            h += rng.double(in: -1...1) * level.roughness * step
            h = min(max(h, LanderRules.groundFloor), LanderRules.groundCeiling)
            heights.append(h)
        }
        // One smoothing pass: hills rather than saw teeth.
        var smooth = heights
        for i in 1..<(count - 1) {
            smooth[i] = (heights[i - 1] + heights[i] * 2 + heights[i + 1]) / 4
        }
        heights = smooth

        let cells = max(2, Int((level.padWidth / step).rounded()))
        // The pad goes between a third and four fifths of the way across,
        // measured from the side the craft starts.
        let farLo = Int(Double(count) * 0.35), farHi = Int(Double(count) * 0.8) - cells
        let index0 = farLo + rng.int(below: max(1, farHi - farLo))
        let first = startsLeft ? index0 : (count - 1 - cells - index0)
        let padHeight = (first...(first + cells)).map { heights[$0] }.reduce(0, +) / Double(cells + 1)
        for i in first...(first + cells) { heights[i] = padHeight }
        return LanderTerrain(heights: heights, step: step,
                             padStart: Double(first) * step, padEnd: Double(first + cells) * step,
                             padHeight: padHeight)
    }
}

/// The craft: where it is, how fast it moves, which way it leans, the fuel left.
struct LanderCraft: Codable, Equatable {
    var x: Double
    var y: Double
    var vx: Double = 0
    var vy: Double = 0
    /// Lean from upright, radians; positive leans right, so thrust pushes right.
    var angle: Double = 0
    var fuel: Double
    /// The throttle actually burning last step (0 with an empty tank), for the flame.
    var burning: Double = 0

    /// The craft's feet, world metres: left then right.
    var feet: [(x: Double, y: Double)] {
        let half = LanderRules.legSpan / 2, drop = LanderRules.footDrop
        let c = cos(angle), s = sin(angle)
        // Local (±half, -drop) turned by the lean: right is (c, -s), up is (s, c).
        return [
            (x + -half * c + -drop * s, y - -half * s + -drop * c),
            (x + half * c + -drop * s, y - half * s + -drop * c),
        ]
    }

    /// Ground speed, m/s.
    var speed: Double { (vx * vx + vy * vy).squareRoot() }
}

/// What the pilot asks for this frame: the lean they want and how hard to burn.
struct LanderInput: Equatable {
    /// Radians; the craft turns towards it at `LanderRules.turnRate`.
    var targetAngle: Double = 0
    /// 0…1.
    var throttle: Double = 0
}

/// Why a touchdown was a crash. The sentence is what the screen says.
enum LanderCrash: String, Codable, Equatable {
    case offPad, tilted, tooFast, sliding

    var sentence: String {
        switch self {
        case .offPad: return "Came down on rough ground, off the pad."
        case .tilted: return "Touched down leaning too far over."
        case .tooFast: return "Hit the ground too hard."
        case .sliding: return "Touched down sliding sideways."
        }
    }
}

/// A safe landing and what it scored.
struct LanderLanding: Codable, Equatable {
    /// Speeds and lean at touchdown, all positive: m/s, m/s, radians.
    let vertical: Double
    let horizontal: Double
    let angle: Double
    let fuelLeft: Double
    /// Metres from the pad's centre.
    let offset: Double
    /// Softer than `LanderRules.gentleVertical` and nearly upright: a bonus.
    let gentle: Bool
    let points: Int
}

enum LanderOutcome: Codable, Equatable {
    case flying
    case landed(LanderLanding)
    case crashed(LanderCrash)

    var isOver: Bool { self != .flying }
}

/// The numbers every flight shares.
enum LanderRules {
    static let worldWidth: Double = 480
    static let terrainStep: Double = 8
    static let groundFloor: Double = 10
    static let groundCeiling: Double = 140
    /// How high above the highest ground the craft starts.
    static let startHeight: Double = 110
    /// No flying off the top: the craft is held under this, metres above the floor.
    static let ceiling: Double = 360
    /// Metres between the feet, and from the craft's centre down to them.
    static let legSpan: Double = 4
    static let footDrop: Double = 2.2
    /// The craft is held this far inside the world's sides.
    static let sideMargin: Double = 6

    /// The steepest lean the pilot can ask for, radians (about 34°).
    static let maxTilt: Double = 0.6
    /// How fast the craft turns towards the lean asked for, radians a second.
    static let turnRate: Double = 1.8
    /// Full thrust, m/s² — enough to climb against the strongest gravity.
    static let thrustAccel: Double = 4.8
    /// Fuel units a second at full thrust.
    static let burnRate: Double = 3

    // A safe touchdown: both feet on the pad, and no faster or more leaning than these.
    static let safeVertical: Double = 2.5
    static let safeHorizontal: Double = 1.5
    static let safeAngle: Double = 0.18
    /// Softer than this and nearly upright is a gentle landing, worth a bonus.
    static let gentleVertical: Double = 1.0

    /// The longest step `step` takes at once; a slow frame is split into these.
    static let maxStep: Double = 1.0 / 120

    /// What a landing scores: more on later levels, more for fuel kept, a
    /// touch exactly in the middle, and a gentle touchdown.
    static func points(level: Int, fuelLeft: Double, offset: Double, padHalfWidth: Double, gentle: Bool) -> Int {
        let base = 100 * max(1, level)
        let fuelBonus = Int((max(0, fuelLeft) * 2).rounded())
        let precision = padHalfWidth > 0 ? Int((30 * max(0, 1 - offset / padHalfWidth)).rounded()) : 0
        return base + fuelBonus + precision + (gentle ? 50 : 0)
    }

    /// The verdict on a touchdown with these speeds, this lean, these feet.
    static func verdict(vx: Double, vy: Double, angle: Double, feetOnPad: Bool) -> LanderCrash? {
        if !feetOnPad { return .offPad }
        if abs(angle) > safeAngle { return .tilted }
        if -vy > safeVertical { return .tooFast }
        if abs(vx) > safeHorizontal { return .sliding }
        return nil
    }
}

/// One flight: a level's ground, the craft, and how it ended.
struct LanderFlight: Equatable {
    let level: LanderLevel
    let terrain: LanderTerrain
    var craft: LanderCraft
    var outcome: LanderOutcome = .flying
    /// Seconds flown.
    var elapsed: Double = 0

    /// A new flight on `level`. The seed picks the ground and which side the craft starts.
    init(level: LanderLevel, seed: UInt64) {
        self.level = level
        let startsLeft = seed % 2 == 0
        let terrain = LanderTerrain.generate(level: level, seed: seed, startsLeft: startsLeft)
        self.terrain = terrain
        let x = startsLeft ? 40 : terrain.width - 40
        craft = LanderCraft(x: x, y: terrain.highest + LanderRules.startHeight,
                            vx: startsLeft ? 6 : -6, vy: 0, angle: 0, fuel: level.fuel)
    }

    /// A flight over ground made by hand: the tests' flat worlds.
    init(level: LanderLevel, terrain: LanderTerrain, craft: LanderCraft) {
        self.level = level
        self.terrain = terrain
        self.craft = craft
    }

    /// Height of the craft's feet above the ground straight under it, metres.
    var altitude: Double {
        craft.y - LanderRules.footDrop - terrain.height(at: craft.x)
    }

    /// Fly for `dt` seconds with `input` held. Long steps are split, so a
    /// dropped frame flies the same path as two smooth ones.
    mutating func step(_ input: LanderInput, dt: Double) {
        guard dt > 0 else { return }
        var left = min(dt, 0.25)
        while left > 1e-9, outcome == .flying {
            let h = min(left, LanderRules.maxStep)
            substep(input, h)
            left -= h
        }
    }

    private mutating func substep(_ input: LanderInput, _ h: Double) {
        var c = craft
        let target = min(max(input.targetAngle, -LanderRules.maxTilt), LanderRules.maxTilt)
        let turn = LanderRules.turnRate * h
        c.angle += min(max(target - c.angle, -turn), turn)

        let throttle = c.fuel > 0 ? min(max(input.throttle, 0), 1) : 0
        c.burning = throttle
        let thrust = throttle * LanderRules.thrustAccel
        let ax = sin(c.angle) * thrust + level.wind
        let ay = cos(c.angle) * thrust - level.gravity
        // Semi-implicit Euler: the speed first, then the position with it.
        c.vx += ax * h
        c.vy += ay * h
        c.x += c.vx * h
        c.y += c.vy * h
        c.fuel = max(0, c.fuel - LanderRules.burnRate * throttle * h)

        let lo = LanderRules.sideMargin, hi = terrain.width - LanderRules.sideMargin
        if c.x < lo { c.x = lo; c.vx = max(0, c.vx) }
        if c.x > hi { c.x = hi; c.vx = min(0, c.vx) }
        if c.y > LanderRules.ceiling { c.y = LanderRules.ceiling; c.vy = min(0, c.vy) }
        elapsed += h

        // Touchdown: either foot at or under the ground, or the body's middle.
        let feet = c.feet
        let gaps = feet.map { $0.y - terrain.height(at: $0.x) }
        let belly = c.y - LanderRules.footDrop * 0.4 - terrain.height(at: c.x)
        let lowest = min(gaps.min() ?? 0, belly)
        guard lowest <= 0 else {
            craft = c
            return
        }
        c.y -= lowest
        let onPad = feet.allSatisfy { terrain.isOnPad($0.x) }
        if let crash = LanderRules.verdict(vx: c.vx, vy: c.vy, angle: c.angle, feetOnPad: onPad) {
            outcome = .crashed(crash)
        } else {
            let offset = abs(c.x - terrain.padCentre)
            let gentle = -c.vy <= LanderRules.gentleVertical && abs(c.angle) <= LanderRules.safeAngle / 2
            let points = LanderRules.points(level: level.number, fuelLeft: c.fuel, offset: offset,
                                            padHalfWidth: terrain.padWidth / 2, gentle: gentle)
            outcome = .landed(LanderLanding(vertical: max(0, -c.vy), horizontal: abs(c.vx), angle: abs(c.angle),
                                            fuelLeft: c.fuel, offset: offset, gentle: gentle, points: points))
        }
        c.vx = 0
        c.vy = 0
        c.burning = 0
        craft = c
    }
}

/// A run of flights: land and go on to the next level; crash and the run is over.
struct LanderRun: Equatable {
    /// The seed the run's first level was flown on; each level adds to it.
    let seed: UInt64
    private(set) var flight: LanderFlight
    private(set) var score = 0
    private(set) var landings = 0

    init(seed: UInt64, level: Int = 1) {
        self.seed = seed
        flight = LanderFlight(level: .make(level), seed: seed &+ UInt64(max(1, level)))
    }

    var level: Int { flight.level.number }
    var isOver: Bool {
        if case .crashed = flight.outcome { return true }
        return false
    }

    mutating func step(_ input: LanderInput, dt: Double) {
        let before = flight.outcome
        flight.step(input, dt: dt)
        if before == .flying, case .landed(let landing) = flight.outcome {
            score += landing.points
            landings += 1
        }
    }

    /// After a landing: the next level, a new seed's ground.
    mutating func nextLevel() {
        guard case .landed = flight.outcome else { return }
        let next = level + 1
        flight = LanderFlight(level: .make(next), seed: seed &+ UInt64(next))
    }
}

/// A steady pilot for demo mode and for the tests: it proves every level can
/// be landed with the fuel it is given, and it flies the screenshots.
///
/// Fly high and level towards the pad, clearing the ground in between; once
/// over it, come straight down, slowing as the ground nears.
enum LanderAutopilot {
    static func input(for flight: LanderFlight) -> LanderInput {
        let c = flight.craft
        let t = flight.terrain
        let g = flight.level.gravity
        let dx = t.padCentre - c.x
        let feetY = c.y - LanderRules.footDrop
        let overPad = abs(dx) < t.padWidth * 0.25

        // Sideways: a speed towards the pad that falls off as it gets close.
        let wantVx = min(max(dx * 0.18, -15), 15)
        let ax = (wantVx - c.vx) * 1.2 - flight.level.wind

        // Up and down: hold a safe height on the way, then descend over the pad.
        let wantVy: Double
        if overPad {
            let height = feetY - t.padHeight
            wantVy = -min(max(height * 0.22 + 0.4, 0.6), 9)
        } else {
            let clear = t.highest(between: c.x, and: t.padCentre) + 30
            wantVy = min(max((clear - feetY) * 0.4, -5), 5)
        }
        let ay = (wantVy - c.vy) * 1.8 + g

        // Lean the thrust towards the push wanted; stay nearly upright low down.
        let above = feetY - t.padHeight
        let limit = !overPad || above > 10 ? LanderRules.maxTilt
            : above > 3 ? LanderRules.safeAngle * 0.9 : LanderRules.safeAngle * 0.6
        let angle = min(max(atan2(ax, max(ay, 0.2)), -limit), limit)
        let thrust = max(0, ay) / max(cos(angle), 0.3)
        return LanderInput(targetAngle: angle, throttle: min(max(thrust / LanderRules.thrustAccel, 0), 1))
    }
}

/// SplitMix64, written out so a seed means the same ground forever and on
/// every platform (the standard library's `random(in:using:)` may change).
struct LanderRandom: Equatable {
    private(set) var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A fraction in 0..<1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    /// A whole number in 0..<bound; modulo bias is immaterial at these sizes.
    mutating func int(below bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        return Int(next() % UInt64(bound))
    }
}
