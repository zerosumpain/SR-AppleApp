import Foundation

/// Tilt Maze's numbers, in cell units (a cell is 1 across) and seconds.
enum TiltMazeRules {
    /// How thick a wall is.
    static let wall = 0.16
    /// The marble's radius. A corridor is 0.84 wide, the marble 0.54.
    static let radius = 0.27
    /// A hole's drawn radius.
    static let holeRadius = 0.36
    /// The marble drops once its middle is this close to a hole's middle.
    static let fallReach = 0.29
    /// Within this of a hole the rim tugs the marble in, harder the closer.
    static let lipReach = 0.52
    static let lipPull = 5.0
    /// The goal cup catches the marble this close to its middle…
    static let goalReach = 0.30
    /// …and draws it in from a little further.
    static let goalPullReach = 0.55
    static let goalPull = 6.0
    /// Acceleration for one g of tilt. A real marble rolls at 5/7 g sin θ; a
    /// cell is about a centimetre and a half, so this is near life.
    static let gravity = 15.0
    /// Tilt beyond this many g counts as this: a phone turned on its side
    /// does not fling the marble.
    static let maxTilt = 0.55
    /// Tilt under this is level: a hand is never perfectly still.
    static let deadZone = 0.012
    /// Rolling on wood: a drag that grows with speed, and a little that does not.
    static let drag = 0.75
    static let rolling = 0.22
    static let maxSpeed = 9.0
    /// How much of its speed into a wall the marble keeps bouncing off.
    static let bounce = 0.38
    /// Slower than this into a wall and it does not bounce at all, it settles.
    static let settle = 0.35
    /// The fixed physics step: 120 a second whatever the screen does, so the
    /// marble rolls the same on every phone.
    static let step = 1.0 / 120
    /// The longest gap one frame may make up (a frame after a pause steps
    /// once, not the whole gap).
    static let longestFrame = 0.1
    /// Down a hole, then back at the flag.
    static let fallTime = 0.55
    static let respawnTime = 0.45
    /// Into the cup.
    static let sinkTime = 0.65
    /// The marble has to be rolling this fast before the clock starts.
    static let startSpeed = 0.15
}

/// The marble: where it is and how it is moving, in cells and cells a second.
struct TiltMazeBall: Equatable {
    var x: Double
    var y: Double
    var vx: Double = 0
    var vy: Double = 0

    init(at point: TiltMazeVector) {
        x = point.x
        y = point.y
    }

    var position: TiltMazeVector { TiltMazeVector(x: x, y: y) }
    var speed: Double { (vx * vx + vy * vy).squareRoot() }
}

/// How the marble moves: tilt and the holes' rims pull it, the wood slows it,
/// the walls stop it.
enum TiltMazePhysics {
    /// The tilt as the marble feels it: nothing inside the dead zone, never
    /// more than `maxTilt`.
    static func clampTilt(_ tilt: TiltMazeVector) -> TiltMazeVector {
        let length = tilt.length
        guard length.isFinite, length > TiltMazeRules.deadZone else { return .zero }
        let scale = min(length, TiltMazeRules.maxTilt) / length
        return TiltMazeVector(x: tilt.x * scale, y: tilt.y * scale)
    }

    /// One fixed step of `dt` seconds. Returns how hard the marble hit a wall
    /// (its speed into it, cells a second), 0 for no knock.
    @discardableResult
    static func step(_ ball: inout TiltMazeBall, tilt: TiltMazeVector, level: TiltMazeLevel, dt: Double) -> Double {
        let t = clampTilt(tilt)
        var ax = t.x * TiltMazeRules.gravity
        var ay = t.y * TiltMazeRules.gravity

        // A hole's rim tugs the marble towards the middle.
        let reach = TiltMazeRules.lipReach
        for hole in level.holes {
            let dx = Double(hole.x) + 0.5 - ball.x, dy = Double(hole.y) + 0.5 - ball.y
            guard abs(dx) < reach, abs(dy) < reach else { continue }
            let d = (dx * dx + dy * dy).squareRoot()
            guard d < reach, d > 1e-6 else { continue }
            let pull = TiltMazeRules.lipPull * (1 - d / reach)
            ax += dx / d * pull
            ay += dy / d * pull
        }
        // So does the goal cup's.
        let gx = Double(level.goal.x) + 0.5 - ball.x, gy = Double(level.goal.y) + 0.5 - ball.y
        let gd = (gx * gx + gy * gy).squareRoot()
        if gd < TiltMazeRules.goalPullReach && gd > 1e-6 {
            let pull = TiltMazeRules.goalPull * (1 - gd / TiltMazeRules.goalPullReach)
            ax += gx / gd * pull
            ay += gy / gd * pull
        }

        ball.vx += ax * dt
        ball.vy += ay * dt

        // Rolling on wood.
        let speed = ball.speed
        if speed > 0 {
            let slower = max(0, speed - (TiltMazeRules.rolling + TiltMazeRules.drag * speed) * dt)
            let capped = min(slower, TiltMazeRules.maxSpeed)
            let k = capped / speed
            ball.vx *= k
            ball.vy *= k
        }

        ball.x += ball.vx * dt
        ball.y += ball.vy * dt
        let knock = collide(&ball, level: level)
        keepOnBoard(&ball, level: level)
        return knock
    }

    /// Push the marble out of every wall it overlaps and bounce it off.
    /// Twice round, for the corners where two walls meet. A step moves the
    /// marble at most `maxSpeed / 120` = 0.075 of a cell, well under its
    /// radius, so it can never pass through a wall between two looks.
    static func collide(_ ball: inout TiltMazeBall, level: TiltMazeLevel) -> Double {
        let r = TiltMazeRules.radius
        var knock = 0.0
        for _ in 0..<2 {
            var touched = false
            for box in level.boxes {
                if ball.x + r <= box.minX || ball.x - r >= box.maxX || ball.y + r <= box.minY || ball.y - r >= box.maxY {
                    continue
                }
                let cx = min(max(ball.x, box.minX), box.maxX)
                let cy = min(max(ball.y, box.minY), box.maxY)
                var nx = ball.x - cx, ny = ball.y - cy
                let d2 = nx * nx + ny * ny
                guard d2 < r * r else { continue }
                var push: Double
                if d2 > 1e-12 {
                    let d = d2.squareRoot()
                    nx /= d
                    ny /= d
                    push = r - d
                } else {
                    // The middle is inside the wall: out the nearest side.
                    let left = ball.x - box.minX, right = box.maxX - ball.x
                    let top = ball.y - box.minY, bottom = box.maxY - ball.y
                    let nearest = min(min(left, right), min(top, bottom))
                    if nearest == left { nx = -1; ny = 0 } else if nearest == right { nx = 1; ny = 0 }
                    else if nearest == top { nx = 0; ny = -1 } else { nx = 0; ny = 1 }
                    push = nearest + r
                }
                push = max(0, push)
                ball.x += nx * push
                ball.y += ny * push
                let into = ball.vx * nx + ball.vy * ny
                if into < 0 {
                    knock = max(knock, -into)
                    let keep = -into < TiltMazeRules.settle ? 0 : TiltMazeRules.bounce
                    ball.vx -= (1 + keep) * into * nx
                    ball.vy -= (1 + keep) * into * ny
                    // A little grip along the wall.
                    ball.vx *= 0.985
                    ball.vy *= 0.985
                }
                touched = true
            }
            if !touched { break }
        }
        return knock
    }

    /// Whatever happened, the marble stays on the board.
    static func keepOnBoard(_ ball: inout TiltMazeBall, level: TiltMazeLevel) {
        let inset = TiltMazeRules.wall / 2 + TiltMazeRules.radius
        let minX = inset, maxX = level.width - inset, minY = inset, maxY = level.height - inset
        if !ball.x.isFinite || !ball.y.isFinite || !ball.vx.isFinite || !ball.vy.isFinite {
            ball = TiltMazeBall(at: level.start.centre)
            return
        }
        if ball.x < minX { ball.x = minX; ball.vx = max(0, ball.vx) }
        if ball.x > maxX { ball.x = maxX; ball.vx = min(0, ball.vx) }
        if ball.y < minY { ball.y = minY; ball.vy = max(0, ball.vy) }
        if ball.y > maxY { ball.y = maxY; ball.vy = min(0, ball.vy) }
    }
}

/// The board's lean from the sensor's gravity, measured from however the
/// phone was held when it was made level.
///
/// Subtracting the two gravity readings works when the phone was levelled
/// lying flat, but held up at a slant (the way most people hold a phone
/// sitting down) the forwards-and-back change barely shows in gravity's y,
/// so the marble would hardly answer a tip of the top edge. Instead the
/// reading is turned by the rotation that takes the level hold to flat, and
/// the lean is read off that: the same feel at any angle.
enum TiltMazeLean {
    /// `g` and `level` are device-motion gravity in g (x to the right of the
    /// screen, y up it, z out of the glass). The result is in g: x towards
    /// the right edge, y towards the bottom of the screen (the way a marble
    /// would roll). Zero when `g` is `level`.
    static func lean(gx: Double, gy: Double, gz: Double, levelX: Double, levelY: Double, levelZ: Double) -> TiltMazeVector {
        let size = (levelX * levelX + levelY * levelY + levelZ * levelZ).squareRoot()
        guard gx.isFinite, gy.isFinite, gz.isFinite else { return .zero }
        // Flat on its back: c is 1. Face down (c near −1) the turn is
        // undefined, so fall back to the plain difference.
        let c = size > 1e-6 ? -levelZ / size : 1
        guard size > 0.2, size.isFinite, c > -0.95 else {
            return TiltMazeVector(x: gx - levelX, y: -(gy - levelY))
        }
        let ax = levelX / size, ay = levelY / size
        // Rodrigues: the turn taking `level` to straight down the back,
        // (0, 0, −1). Its axis is level × down = (−ay, ax, 0).
        let vx = -ay, vy = ax
        let along = vx * gx + vy * gy
        let k = 1 / (1 + c)
        let x = gx * c + vy * gz + vx * along * k
        let y = gy * c - vx * gz + vy * along * k
        return TiltMazeVector(x: x, y: -y)
    }
}

/// What happened during one frame, for the sound of it: haptics, the
/// particles and the cards.
struct TiltMazeEvents: Equatable {
    /// The hardest knock against a wall, cells a second (0 for none).
    var knock = 0.0
    /// The clock started: the marble's first roll.
    var started = false
    var fell = false
    var respawned = false
    /// A flag rolled over for the first time.
    var checkpoint: TiltMazeCell?
    /// Into the cup: the clock has stopped.
    var reachedGoal = false
    /// The cup animation is over: the level is done.
    var cleared = false
}

/// One go at one maze: the marble, the clock, the falls and the flags.
struct TiltMazeRun: Equatable {
    enum Phase: Equatable {
        /// On the start, waiting to be tilted; the clock has not started.
        case ready
        case rolling
        /// Dropping down `hole`, `elapsed` seconds in.
        case falling(TiltMazeCell, Double)
        /// Back on the flag (or the start), settling.
        case respawning(Double)
        /// Rolling into the cup.
        case sinking(Double)
        case cleared
    }

    let level: TiltMazeLevel
    private(set) var ball: TiltMazeBall
    private(set) var phase: Phase = .ready
    /// The clock, seconds. It runs while the marble rolls and while it falls.
    private(set) var time = 0.0
    private(set) var falls = 0
    /// Where a fall comes back to: the start, or the last flag rolled over.
    private(set) var respawn: TiltMazeCell
    private(set) var reached: [TiltMazeCell] = []
    private var accumulator = 0.0
    /// Where the marble was when it began to drop (down a hole or into the cup).
    private(set) var dropFrom = TiltMazeVector.zero

    /// A go from the start; `at` puts the marble somewhere else on the
    /// board (the tests use it).
    init(level: TiltMazeLevel, at point: TiltMazeVector? = nil) {
        self.level = level
        ball = TiltMazeBall(at: point ?? level.start.centre)
        respawn = level.start
    }

    var isOver: Bool { phase == .cleared }

    /// Whether the player's tilt moves the marble just now.
    var steerable: Bool {
        switch phase {
        case .ready, .rolling: return true
        default: return false
        }
    }

    /// The marble as drawn: where, how big (1 on the board, smaller down a
    /// hole) and how far down (0 on the board, 1 at the bottom).
    var drawn: (position: TiltMazeVector, scale: Double, depth: Double) {
        switch phase {
        case .ready, .rolling:
            return (ball.position, 1, 0)
        case .falling(let hole, let elapsed):
            let k = Self.ease(min(1, elapsed / TiltMazeRules.fallTime))
            return (Self.mix(dropFrom, hole.centre, k), 1 - 0.7 * k, k)
        case .respawning(let elapsed):
            let k = min(1, elapsed / TiltMazeRules.respawnTime)
            // Drops back onto the board from above: a touch big, then settles.
            let pop = 1 + 0.35 * (1 - k) * (1 - k)
            return (ball.position, pop, 0)
        case .sinking(let elapsed):
            let k = Self.ease(min(1, elapsed / TiltMazeRules.sinkTime))
            return (Self.mix(dropFrom, level.goal.centre, k), 1 - 0.45 * k, k)
        case .cleared:
            return (level.goal.centre, 0.55, 1)
        }
    }

    /// Move on by one display frame of `dt` seconds, in fixed steps.
    mutating func advance(tilt: TiltMazeVector, dt: Double) -> TiltMazeEvents {
        var events = TiltMazeEvents()
        guard phase != .cleared else { return events }
        let frame = dt.isFinite ? min(max(dt, 0), TiltMazeRules.longestFrame) : 0
        accumulator += frame
        while accumulator >= TiltMazeRules.step {
            accumulator -= TiltMazeRules.step
            tick(tilt, &events)
            if phase == .cleared {
                accumulator = 0
                break
            }
        }
        return events
    }

    private mutating func tick(_ tilt: TiltMazeVector, _ events: inout TiltMazeEvents) {
        let dt = TiltMazeRules.step
        switch phase {
        case .ready:
            let knock = TiltMazePhysics.step(&ball, tilt: tilt, level: level, dt: dt)
            events.knock = max(events.knock, knock)
            if ball.speed > TiltMazeRules.startSpeed {
                phase = .rolling
                events.started = true
            }
            checkCells(&events)
        case .rolling:
            time += dt
            let knock = TiltMazePhysics.step(&ball, tilt: tilt, level: level, dt: dt)
            events.knock = max(events.knock, knock)
            checkCells(&events)
        case .falling(let hole, let elapsed):
            time += dt
            let next = elapsed + dt
            if next >= TiltMazeRules.fallTime {
                ball = TiltMazeBall(at: respawn.centre)
                phase = .respawning(0)
                events.respawned = true
            } else {
                phase = .falling(hole, next)
            }
        case .respawning(let elapsed):
            time += dt
            let next = elapsed + dt
            phase = next >= TiltMazeRules.respawnTime ? .rolling : .respawning(next)
        case .sinking(let elapsed):
            let next = elapsed + dt
            if next >= TiltMazeRules.sinkTime {
                phase = .cleared
                events.cleared = true
            } else {
                phase = .sinking(next)
            }
        case .cleared:
            break
        }
    }

    /// Over a hole, in the cup, or over a flag.
    private mutating func checkCells(_ events: inout TiltMazeEvents) {
        let here = ball.position
        for hole in level.holes where here.distance(to: hole.centre) < TiltMazeRules.fallReach {
            dropFrom = here
            phase = .falling(hole, 0)
            ball.vx = 0
            ball.vy = 0
            falls += 1
            events.fell = true
            return
        }
        if here.distance(to: level.goal.centre) < TiltMazeRules.goalReach {
            dropFrom = here
            phase = .sinking(0)
            ball.vx = 0
            ball.vy = 0
            events.reachedGoal = true
            return
        }
        for flag in level.checkpoints where !reached.contains(flag) && here.distance(to: flag.centre) < 0.42 {
            reached.append(flag)
            respawn = flag
            events.checkpoint = flag
        }
    }

    private static func mix(_ a: TiltMazeVector, _ b: TiltMazeVector, _ k: Double) -> TiltMazeVector {
        TiltMazeVector(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }

    private static func ease(_ k: Double) -> Double { k * k * (3 - 2 * k) }
}
