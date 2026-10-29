import Foundation

// Car Racer+ ("car-racer-plus"): a deeper top-down racer than Car Race, with
// a tyre model, a gearbox, eight circuits, AI drivers on a racing line, and a
// career with a garage and upgrades. Everything that decides a race lives in
// the CarPro*Logic.swift files, free of SwiftUI: Foundation only, the same
// result on every phone and in every test for the same inputs.
//
// Units are METRES, SECONDS, KILOGRAMS, NEWTONS and RADIANS. The world is
// screen-shaped like Car Race: x runs right, y runs DOWN, a heading of 0
// points right and a positive turn is clockwise on the screen. A car's own
// frame is x forward, y to its right; a positive yaw rate turns it right.
//
// HOW A SCREEN DRIVES IT
// ----------------------
// Everything below is plain value types: keep a `CarProSession` (and the
// `CarProCareer`) in a reference holder on the screen and mutate it there.
//
// 1. Career and garage (CarProCareerLogic.swift)
//      let store = CarProStore()
//      var career = store.load()                    // a fresh career when nothing is saved
//      try career.buy(.roadster)                    // throws CarProCareerError
//      try career.buyUpgrade(carId: id, kind: .tyres)   // next stage; money comes off
//      try career.setTuning(carId: id, CarProTuning(brakeBias:wing:finalDrive:))
//      store.save(career)                           // after every change
//    Upgrade cards: `car.setup.stats` (bars 0…1 via `value(_:)`, `pi`,
//    `piClass`), `car.setup.withUpgrade(kind)?.stats` for the after-bars,
//    `car.setup.upgradeCost(kind)` (nil when maxed), `kind.stageName(_:)`.
//    Tiers: `CarProTier.allCases`, `career.isUnlocked(_:)`,
//    `career.isEligible(carId:for:)` (PI against `tier.piLimit`).
//
// 2. A championship weekend
//      try career.startSeason(.club, carId: id)
//      let weekend = career.nextWeekend()!          // track, laps, AI field
//      qualifying: CarProSession(config: weekend.qualifyingConfig(assists: career.settings.assists))
//      let grid = weekend.grid(playerLap: qualifyingSession.player.bestLap)  // `qualifying(playerLap:)` for the sheet
//      race:       CarProSession(config: weekend.raceConfig(grid: grid, assists: ...))
//      when race.phase == .finished: let reward = career.recordRace(race.results)  // points, prize, unlocks
//    Quick race: `CarProSessionConfig.quickRace(track:laps:player:opponents:assists:)` with
//    opponents from `CarProField.quickRace(for:count:difficulty:seed:)`.
//    Time trial: `CarProSessionConfig.timeTrial(track:player:assists:ghost: store.ghost(track:model:))`;
//    on each `.lap` event with `personalBest`, `career.recordTimeTrial(...)` and, when
//    `session.newGhost`, `store.saveGhost(session.bestGhost!)`.
//
// 3. Driving a session (CarProSessionLogic.swift), once a display frame:
//      session.step(dt: frameSeconds, input: CarProInput(throttle:brake:steer:shiftUp:shiftDown:))
//    `step` runs the physics in fixed 1/240 s substeps with an accumulator,
//    so a 60 Hz and a 120 Hz screen drive the same race. Pedals are 0…1
//    (press height), steering −1…1 (tilt or an on-screen wheel). Shift taps
//    are edges: true on the one frame the paddle is tapped. Pausing is simply
//    not calling `step`; nothing here keeps a timer.
//    Then read, for drawing:
//      session.phase            .countdown(remaining:) (`lightsLit` 0…5) / .racing / .finished
//      session.racers           every car: `vehicle` (position, heading, speed, wheels with
//                               position/skid/surface/temperature/wear, steerAngle, brake
//                               glow, brake lights from `brake`), `params.length/width`,
//                               `entrant` (name, number, hue), `position`, laps, sectors
//      session.player / session.hud   the player's car and the HUD numbers
//      session.events           what happened during this step (haptics, banners)
//      session.track            samples (centre, normal, halfWidth, kerbs, run-off and walls,
//                               surface, bank, racing line), `points(every:offset:)` and
//                               `runs(where:)` to build paths, corners, sectors, `minimap()`
//      session.brakeMarkers     the braking boards for the player's car
//      session.ghostPose        where the best lap's ghost is now
//      session.lastTelemetry / bestTelemetry   speed, throttle and brake against distance
//      session.results          the classification once `phase == .finished`
//    `session.retire()` ends it for a player who gives up.

/// A point or a direction in the plane.
struct CarProVec: Codable, Equatable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    static let zero = CarProVec(x: 0, y: 0)

    static func + (a: CarProVec, b: CarProVec) -> CarProVec { CarProVec(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CarProVec, b: CarProVec) -> CarProVec { CarProVec(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CarProVec, k: Double) -> CarProVec { CarProVec(x: a.x * k, y: a.y * k) }
    static prefix func - (a: CarProVec) -> CarProVec { CarProVec(x: -a.x, y: -a.y) }

    func dot(_ b: CarProVec) -> Double { x * b.x + y * b.y }
    /// The z of the cross product: positive when `b` is clockwise of self on screen.
    func cross(_ b: CarProVec) -> Double { x * b.y - y * b.x }
    var length: Double { (x * x + y * y).squareRoot() }
    var lengthSquared: Double { x * x + y * y }

    var normalized: CarProVec {
        let l = length
        return l > 1e-12 ? CarProVec(x: x / l, y: y / l) : .zero
    }

    /// Ninety degrees clockwise on the screen: the right of a direction of travel.
    var right: CarProVec { CarProVec(x: -y, y: x) }

    /// Turned `angle` radians clockwise on the screen.
    func rotated(by angle: Double) -> CarProVec {
        let c = cos(angle), s = sin(angle)
        return CarProVec(x: x * c - y * s, y: x * s + y * c)
    }

    /// The unit vector at `angle` radians.
    static func heading(_ angle: Double) -> CarProVec { CarProVec(x: cos(angle), y: sin(angle)) }

    func distance(to b: CarProVec) -> Double { (self - b).length }
}

/// Small numeric helpers shared by the Car Racer+ files.
enum CarProMath {
    /// `angle` folded into −π…π.
    static func wrap(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a < -.pi { a += 2 * .pi }
        return a
    }

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

    /// Moves `value` towards `target` by at most `step`.
    static func approach(_ value: Double, _ target: Double, _ step: Double) -> Double {
        if value < target { return min(target, value + step) }
        return max(target, value - step)
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// 1 m/s in km/h and mph, for the speedometer.
    static let kmh = 3.6
    static let mph = 2.236_936
}

/// A seeded splitmix64: no Foundation randomness anywhere in a race, so the
/// same seed gives the same AI mistakes on every phone and in every test.
struct CarProRandom: Codable, Equatable {
    private(set) var state: UInt64

    init(seed: UInt64) { state = seed }

    /// A seed from a string: a track id, a driver id.
    static func seed(_ text: String, salt: UInt64 = 0) -> UInt64 {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15 ^ salt
        for byte in text.utf8 { seed = (seed ^ UInt64(byte)) &* 0x1000_0000_01B3 }
        return seed
    }

    /// 0..<1.
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }

    /// −1..<1.
    mutating func signed() -> Double { next() * 2 - 1 }
}

/// What a tyre is standing on. The first four are the racing surface (a lap
/// stays valid on them); grass and gravel are run-off.
enum CarProSurface: String, Codable, CaseIterable {
    case tarmac
    /// The striped kerbs on an apex: a little less grip, and bumpy.
    case kerb
    /// Loose dirt: the unsealed half of the rallycross.
    case dirt
    /// A damp patch on tarmac.
    case wet
    case grass
    /// A gravel trap: very little grip and it drags the car down hard.
    case gravel

    /// Friction against dry tarmac's 1.
    var grip: Double {
        switch self {
        case .tarmac: return 1.0
        case .kerb: return 0.92
        case .dirt: return 0.74
        case .wet: return 0.72
        case .grass: return 0.52
        case .gravel: return 0.46
        }
    }

    /// Rolling resistance coefficient: the drag of the ground on a rolling tyre.
    var rolling: Double {
        switch self {
        case .tarmac, .wet: return 0.013
        case .kerb: return 0.02
        case .dirt: return 0.035
        case .grass: return 0.075
        case .gravel: return 0.42
        }
    }

    /// How much the ground shakes the load on a tyre, 0…1 (kerb ripples, ruts).
    var bump: Double {
        switch self {
        case .tarmac, .wet: return 0
        case .kerb: return 0.24
        case .dirt: return 0.07
        case .grass: return 0.09
        case .gravel: return 0.14
        }
    }

    /// On the racing surface: a lap stays clean while any tyre is on it.
    var isTrack: Bool {
        switch self {
        case .tarmac, .kerb, .dirt, .wet: return true
        case .grass, .gravel: return false
        }
    }

    /// Throws up dust rather than tyre smoke when the tyres slide.
    var isLoose: Bool { self == .dirt || self == .grass || self == .gravel }
}

/// What the driver asks for this frame. Pedals are analogue (press height is
/// the amount); steering is −1 full left to 1 full right.
struct CarProInput: Equatable {
    var throttle: Double = 0
    var brake: Double = 0
    var steer: Double = 0
    /// The up paddle was tapped this frame (manual gears).
    var shiftUp = false
    /// The down paddle was tapped this frame (manual gears).
    var shiftDown = false

    init(throttle: Double = 0, brake: Double = 0, steer: Double = 0, shiftUp: Bool = false, shiftDown: Bool = false) {
        self.throttle = throttle
        self.brake = brake
        self.steer = steer
        self.shiftUp = shiftUp
        self.shiftDown = shiftDown
    }

    /// The same pedals and steering with the paddle taps spent.
    var held: CarProInput { CarProInput(throttle: throttle, brake: brake, steer: steer) }
}

/// The driving aids the player can switch on and off.
struct CarProAssists: Codable, Equatable {
    /// Steering is a share of the front tyres' grip, and the wheels follow a
    /// slide (counter-steer) by themselves.
    var steering = true
    /// Traction control: the throttle is trimmed while the driven tyres spin.
    var traction = true
    /// Anti-lock brakes: a locking tyre's brake is let off.
    var abs = true
    /// The gearbox shifts itself.
    var autoGears = true
    /// Boards before each braking zone (drawing only).
    var brakingMarkers = true
    /// The racing line painted on the road (drawing only).
    var racingLine = true

    init(steering: Bool = true, traction: Bool = true, abs: Bool = true, autoGears: Bool = true,
         brakingMarkers: Bool = true, racingLine: Bool = true) {
        self.steering = steering
        self.traction = traction
        self.abs = abs
        self.autoGears = autoGears
        self.brakingMarkers = brakingMarkers
        self.racingLine = racingLine
    }

    static let full = CarProAssists()
    static let none = CarProAssists(steering: false, traction: false, abs: false, autoGears: false,
                                    brakingMarkers: false, racingLine: false)
    /// What the AI drives with: every aid that touches the car.
    static let ai = CarProAssists(steering: true, traction: true, abs: true, autoGears: true,
                                  brakingMarkers: false, racingLine: false)

    /// How many aids are on, for a "3 of 6" label.
    var count: Int { [steering, traction, abs, autoGears, brakingMarkers, racingLine].filter { $0 }.count }
}

/// "1:02.374", or "48.205" under a minute; "--:--.---" for none.
enum CarProFormat {
    static func time(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "--:--.---" }
        let thousandths = Int((max(0, seconds) * 1000).rounded())
        let minutes = thousandths / 60000, rest = thousandths % 60000
        let secs = rest / 1000, frac = rest % 1000
        if minutes > 0 { return String(format: "%d:%02d.%03d", minutes, secs, frac) }
        return String(format: "%d.%03d", secs, frac)
    }

    /// "+0.42" / "−1.08" for a delta.
    static func delta(_ seconds: Double) -> String {
        let sign = seconds < 0 ? "\u{2212}" : "+"
        return sign + String(format: "%.2f", abs(seconds))
    }

    /// "£12,500".
    static func money(_ amount: Int) -> String {
        let digits = String(abs(amount))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (amount < 0 ? "-£" : "£") + out
    }

    /// "1.85 km".
    static func length(_ metres: Double) -> String { String(format: "%.2f km", metres / 1000) }

    /// "1st", "2nd", "3rd", "11th".
    static func ordinal(_ n: Int) -> String {
        let tens = n % 100
        if tens >= 11 && tens <= 13 { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }
}
