import Foundation

/// One line of a level's walkthrough. Positions are where a pal's middle
/// should end up, in tiles from the left.
enum TetherPalsMove: Equatable {
    /// Walk until standing at `x`.
    case walk(Int, Double)
    /// Jump, steering towards `x`, until standing again.
    case hop(Int, Double)
    /// Walk into a pal and jump onto their head.
    case climb(Int, onto: Int)
    /// Everyone walks to `x`, a little apart.
    case gather(Double)
    /// Stand still a moment (a haul settling).
    case wait(Double)

    /// The pal this line moves, if just one.
    var pal: Int? {
        switch self {
        case .walk(let pal, _), .hop(let pal, _), .climb(let pal, _): return pal
        case .gather, .wait: return nil
        }
    }

    /// Whether a team this size has every pal the line needs.
    func fits(team: Int) -> Bool {
        switch self {
        case .walk(let pal, _), .hop(let pal, _): return pal < team
        case .climb(let pal, let onto): return pal < team && onto < team
        case .gather, .wait: return true
        }
    }
}

/// Plays a level's walkthrough, one line at a time, by holding the same
/// buttons a player would. The demo uses it so the screenshots move, and the
/// tests use it to prove every level can be finished. A line that takes too
/// long is skipped (and counted), so the pilot can never hang.
struct TetherPalsAutopilot: Equatable {
    let script: [TetherPalsMove]
    private(set) var index = 0
    /// Lines given up on: zero for a good walkthrough.
    private(set) var stalls = 0
    private var elapsed = 0.0
    private var phase = 0
    private var phaseTime = 0.0

    static let lineLimit = 6.0

    init(script: [TetherPalsMove]) {
        self.script = script
    }

    var finished: Bool { index >= script.count }

    /// The pal the current line moves (the one Solo would be driving).
    var currentPal: Int? { finished ? nil : script[index].pal }

    /// What every pal holds this step.
    mutating func inputs(for world: TetherPalsWorld) -> [TetherPalsInput] {
        var out = Array(repeating: TetherPalsInput.none, count: world.team)
        while index < script.count && !script[index].fits(team: world.team) { next() }
        guard index < script.count else { return out }
        let line = script[index]
        elapsed += TetherPalsRules.step
        if elapsed > Self.lineLimit {
            stalls += 1
            next()
            return out
        }
        switch line {
        case .wait(let seconds):
            if elapsed >= seconds { next() }
        case .gather(let x):
            gather(x, world: world, into: &out)
        case .walk(let pal, let x):
            walk(pal, to: x, world: world, into: &out)
        case .hop(let pal, let x):
            hop(pal, to: x, world: world, into: &out)
        case .climb(let pal, let onto):
            climb(pal, onto: onto, world: world, into: &out)
        }
        return out
    }

    private mutating func next() {
        index += 1
        elapsed = 0
        phase = 0
        phaseTime = 0
    }

    private static func steer(_ d: Double, slack: Double) -> TetherPalsInput {
        guard abs(d) > slack else { return .none }
        return TetherPalsInput(left: d < 0, right: d > 0, jump: false)
    }

    private mutating func gather(_ x: Double, world: TetherPalsWorld, into out: inout [TetherPalsInput]) {
        var done = true
        for (k, pal) in world.pals.enumerated() {
            guard pal.active else {
                done = false
                continue
            }
            let d = x - 0.55 * Double(k) - pal.centreX
            if abs(d) > 0.08 || !pal.support.standing { done = false }
            out[k] = Self.steer(d, slack: 0.04)
        }
        if done { next() }
    }

    private mutating func walk(_ index: Int, to x: Double, world: TetherPalsWorld, into out: inout [TetherPalsInput]) {
        let pal = world.pals[index]
        guard pal.active else { return }
        let d = x - pal.centreX
        if abs(d) <= 0.08 && pal.support.standing {
            next()
            return
        }
        out[index] = Self.steer(d, slack: 0.04)
    }

    private mutating func hop(_ index: Int, to x: Double, world: TetherPalsWorld, into out: inout [TetherPalsInput]) {
        let pal = world.pals[index]
        guard pal.active else { return }
        var input = Self.steer(x - pal.centreX, slack: 0.05)
        switch phase {
        case 0:
            // Wait to be standing, then press jump.
            guard pal.support.standing else { return }
            phase = 1
            input.jump = true
        case 1:
            if !pal.support.standing { phase = 2 }
        default:
            if pal.support.standing {
                next()
                return
            }
        }
        out[index] = input
    }

    private mutating func climb(_ index: Int, onto other: Int, world: TetherPalsWorld, into out: inout [TetherPalsInput]) {
        let pal = world.pals[index]
        guard pal.active else { return }
        if pal.support == .pal(other) {
            next()
            return
        }
        let d = world.pals[other].centreX - pal.centreX
        var input = Self.steer(d, slack: 0.05)
        if phase == 0 {
            if pal.support.standing && abs(d) <= 0.1 {
                phase = 1
                phaseTime = 0
                input = TetherPalsInput(left: false, right: false, jump: true)
            }
        } else {
            phaseTime += TetherPalsRules.step
            // Landed back on the ground: walk in and try again.
            if pal.support.standing && phaseTime > 0.25 { phase = 0 }
        }
        out[index] = input
    }
}
