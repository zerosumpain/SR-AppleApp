import Foundation

/// The four modes, played in turn through a game. Finishing one starts
/// multiball; finishing the last also earns an extra ball, and the round
/// starts again a little harder.
enum PinballMode: Int, CaseIterable, Codable {
    case bumperBlitz, rampRush, targetPractice, orbitRun

    var title: String {
        switch self {
        case .bumperBlitz: return "BUMPER BLITZ"
        case .rampRush: return "RAMP RUSH"
        case .targetPractice: return "TARGET PRACTICE"
        case .orbitRun: return "ORBIT RUN"
        }
    }

    /// What to do, in plain words, for the screen beside the table.
    var instruction: String {
        switch self {
        case .bumperBlitz: return "Hit the pop bumpers"
        case .rampRush: return "Shoot the ramp"
        case .targetPractice: return "Knock down every drop target"
        case .orbitRun: return "Shoot round the left orbit"
        }
    }

    /// How many it takes, the `cycle`th time round (0 the first time).
    func goal(cycle: Int) -> Int {
        let c = max(0, cycle)
        switch self {
        case .bumperBlitz: return 20 + 10 * c
        case .rampRush: return 3 + c
        case .targetPractice: return 2 + c
        case .orbitRun: return 3 + c
        }
    }

    var next: PinballMode { PinballMode(rawValue: rawValue + 1) ?? .bumperBlitz }
}

/// Something the ball did that scores.
enum PinballHit: Equatable {
    case bumper(Int)
    case sling(PinballSide)
    case target(Int)
    case lane(Int)
    case spinner(Int)
    case orbit
    case ramp
}

/// Which drain a ball went down.
enum PinballDrain: Equatable {
    case left, centre, right
}

/// What happened in a step, for the sounds-and-lights side: haptics,
/// sparks, a shake of the picture.
enum PinballEvent: Equatable {
    case flipper(PinballSide)
    case bumper(Int)
    case sling(PinballSide)
    case target(Int)
    case bankCleared
    case lane(Int)
    case lanesComplete(Int)
    case spinner(Int)
    case orbit
    case ramp(Int)
    case jackpot(Int)
    case skillShot
    case launch
    case drain(PinballDrain)
    case ballSaved
    case multiball
    case modeComplete(PinballMode)
    case extraBall
    case tiltWarning(Int)
    case tilt
    case ballOver(Int)
    case gameOver
}

/// The points. Kept together so the how-to-play card and the tests agree.
enum PinballScoring {
    static let bumper = 250
    static let sling = 50
    static let target = 1_000
    static let bank = 10_000
    static let lane = 500
    static let laneAgain = 100
    static let lanesAll = 5_000
    static let spin = 100
    static let orbit = 5_000
    static let ramp = 15_000
    static let skillShot = 25_000
    static let mode = 50_000
    static let jackpot = 100_000
    static let jackpotStep = 50_000
    static let maxMultiplier = 5
    /// All three lanes lit again with the multiplier already at the top.
    static let multiplierFull = 25_000
    static let maxCombo = 5
    /// Seconds.
    static let ballSave: Double = 10
    static let multiballSave: Double = 12
    static let comboWindow: Double = 5
    static let skillWindow: Double = 5

    /// 1234567 → "1,234,567".
    static func digits(_ n: Int) -> String {
        let negative = n < 0
        let raw = String(abs(n))
        var out = ""
        for (i, ch) in raw.enumerated() {
            if i > 0 && (raw.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return negative ? "-" + out : out
    }
}

/// A line or two for the dot-matrix strip, held for a few seconds. A more
/// important message is not talked over by a lesser one.
struct PinballMessage: Equatable {
    var top: String
    var bottom: String
    var until: Double
    var priority: Int
    /// Changes with every new message, so the strip can flash it in.
    var serial: Int
}

/// The game's running tally, for the end card.
struct PinballStats: Equatable, Codable {
    var bumpers = 0
    var ramps = 0
    var orbits = 0
    var banks = 0
    var jackpots = 0
    var modes = 0
    var skillShots = 0
    var saves = 0
}

/// When each light was last hit, in machine time, for the glow.
struct PinballFlashes: Equatable {
    var bumpers: [Double] = [-9, -9, -9]
    var slings: [Double] = [-9, -9]
    var targets: [Double] = [-9, -9, -9]
    var lanes: [Double] = [-9, -9, -9]
    var lanesAll: Double = -9
    var ramp: Double = -9
    var orbit: Double = -9
    var bank: Double = -9
    var jackpot: Double = -9
    var mode: Double = -9
    var save: Double = -9
    var tilt: Double = -9
}
