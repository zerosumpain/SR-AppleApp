import Foundation

/// Something that happened to the ball in a step, for the sound of the game:
/// a haptic, a puff of sand, a splash, a flash on a bumper.
enum MiniGolfEvent: Equatable {
    /// Off the timber at this speed into it.
    case wall(at: MiniGolfVec, speed: Double)
    case post(at: MiniGolfVec, speed: Double)
    /// Bumper number `index` in the hole's posts.
    case bumper(index: Int, at: MiniGolfVec, speed: Double)
    /// Clipped by a windmill's sail.
    case sail(at: MiniGolfVec, speed: Double)
    /// Rolled into a bunker.
    case sand(at: MiniGolfVec)
    case splash(at: MiniGolfVec)
    /// Over the cup too fast: it curled round the rim and out.
    case lipOut(at: MiniGolfVec)
    case holed
    /// The ball has come to rest.
    case stopped(at: MiniGolfVec)
}

/// One ball on one hole: the shot, and the felt it rolls over.
///
/// Stepped at a fixed 240 a second whatever the screen does (`advance`), so a
/// putt goes the same way on every phone and in the tests. A step moves the
/// ball at most a third of its radius (the speed is capped), so it cannot pass
/// through a wall between two steps; each step then pushes it back out of
/// anything it overlaps and reflects the speed it had into it.
struct MiniGolfBallSim {
    enum State: Equatable {
        /// Waiting for the next putt.
        case resting
        case rolling
        case holed
        /// In the water: the game adds a stroke and puts the ball back.
        case splashed
    }

    let hole: MiniGolfHole
    private(set) var position: MiniGolfVec
    private(set) var velocity: MiniGolfVec = .zero
    private(set) var state: State = .resting
    /// The course clock, which turns the windmills. It runs while the ball rests.
    private(set) var clock: Double
    /// Seconds since the current putt.
    private(set) var shotTime: Double = 0
    /// Where the current putt was played from: where a ball out of the water goes back to.
    private(set) var lastSpot: MiniGolfVec
    /// Times the ball was found outside the felt and put back. Never, on these
    /// holes (the tests check); counted so the tests can say so.
    private(set) var rescues = 0
    /// The shot ran past `maxShotTime` and was stopped by hand.
    private(set) var forcedStop = false

    private var accumulator: Double = 0
    private var restFor: Double = 0
    private var wasInSand = false
    private var wasOverCup = false

    init(hole: MiniGolfHole, at spot: MiniGolfVec? = nil, clock: Double = 0) {
        self.hole = hole
        position = spot ?? hole.tee
        lastSpot = spot ?? hole.tee
        self.clock = clock
        wasInSand = hole.inSand(position)
    }

    var speed: Double { velocity.length }

    /// Play a putt from where the ball rests: `angle` radians (−π/2 is
    /// straight up the screen), `power` from 0 to 1. False if the ball is not
    /// resting.
    @discardableResult
    mutating func putt(angle: Double, power: Double) -> Bool {
        guard state == .resting else { return false }
        velocity = MiniGolfVec.heading(angle) * MiniGolfRules.shotSpeed(power: power)
        lastSpot = position
        state = .rolling
        shotTime = 0
        restFor = 0
        forcedStop = false
        wasOverCup = position.distance(to: hole.cup) < MiniGolfRules.cupRadius
        return true
    }

    /// Back to where the last putt was played from, resting: after a splash.
    mutating func returnToLastSpot() {
        position = lastSpot
        velocity = .zero
        state = .resting
        restFor = 0
        wasInSand = hole.inSand(position)
    }

    /// Put the ball down somewhere, resting (a new player on the tee).
    mutating func place(at spot: MiniGolfVec) {
        position = spot
        lastSpot = spot
        velocity = .zero
        state = .resting
        restFor = 0
        accumulator = 0
        wasInSand = hole.inSand(spot)
    }

    /// Move the course on by `dt` seconds of real time, in fixed steps.
    mutating func advance(_ dt: Double, events: inout [MiniGolfEvent]) {
        guard dt > 0 else { return }
        guard state == .rolling else {
            // Resting, holed or wet: only the windmills move.
            clock += dt
            accumulator = 0
            return
        }
        accumulator += dt
        var steps = 0
        while accumulator >= MiniGolfRules.step && steps < MiniGolfRules.maxStepsPerFrame {
            accumulator -= MiniGolfRules.step
            steps += 1
            step(events: &events)
            if state != .rolling {
                // The remainder of the frame is still time on the clock.
                clock += accumulator
                accumulator = 0
                return
            }
        }
        if steps == MiniGolfRules.maxStepsPerFrame { accumulator = 0 }
    }

    /// Roll until the ball stops, drops or splashes: for the tests and for
    /// skipping ahead. Returns the number of steps taken.
    @discardableResult
    mutating func finishShot(events: inout [MiniGolfEvent]) -> Int {
        var steps = 0
        while state == .rolling {
            step(events: &events)
            steps += 1
            if events.count > 256 { events.removeAll(keepingCapacity: true) }
        }
        return steps
    }

    /// One fixed step of 1/240 s.
    mutating func step(events: inout [MiniGolfEvent]) {
        guard state == .rolling else { return }
        let dt = MiniGolfRules.step
        clock += dt
        shotTime += dt
        var p = position
        var v = velocity

        // Downhill, and the curl of the cup's rim.
        var push = hole.slopePush(at: p)
        let toCup = hole.cup - p
        let cupDistance = toCup.length
        if cupDistance < MiniGolfRules.cupRadius && cupDistance > 1e-6 {
            push += toCup * (MiniGolfRules.cupPull / cupDistance)
        }
        v += push * dt

        // Rolling resistance against the way the ball is going, then the air.
        let inSand = hole.inSand(p)
        let friction = inSand ? MiniGolfRules.sandFriction : MiniGolfRules.feltFriction
        let s = v.length
        if s > 0 {
            var slowed = max(0, s - friction * dt) * (1 - MiniGolfRules.drag * dt)
            slowed = min(slowed, MiniGolfRules.maxSpeed)
            v = v * (slowed / s)
        }

        let before = p
        p += v * dt
        let touched = collide(&p, &v, events: &events)

        // Never off the felt: if it happens, step back and turn round. A step
        // is shorter than the reach of a wall, so a ball that touched nothing
        // cannot have crossed one, and only a touching step needs the check.
        if touched && !hole.isOpen(p) {
            p = before
            v = v * -0.5
            rescues += 1
        }

        position = p
        velocity = v

        if inSand && !wasInSand { events.append(.sand(at: p)) }
        wasInSand = inSand

        if hole.inWater(p) {
            state = .splashed
            velocity = .zero
            events.append(.splash(at: p))
            return
        }

        let overCup = p.distance(to: hole.cup) < MiniGolfRules.cupRadius
        if overCup && p.distance(to: hole.cup) < MiniGolfRules.cupRadius - MiniGolfRules.dropDepth
            && v.length < MiniGolfRules.lipSpeed {
            state = .holed
            position = hole.cup
            velocity = .zero
            events.append(.holed)
            return
        }
        if wasOverCup && !overCup { events.append(.lipOut(at: p)) }
        wasOverCup = overCup

        // At rest once slow for a moment — but never inside a windmill's
        // sweep, where the next sail will move it on.
        if v.length < MiniGolfRules.restSpeed && !hole.inSweep(p) {
            restFor += dt
            if restFor >= MiniGolfRules.restTime { settle(events: &events) }
        } else {
            restFor = 0
        }
        if state == .rolling && shotTime > MiniGolfRules.maxShotTime {
            forcedStop = true
            settle(events: &events)
        }
    }

    private mutating func settle(events: inout [MiniGolfEvent]) {
        velocity = .zero
        state = .resting
        restFor = 0
        events.append(.stopped(at: position))
    }

    // MARK: - Collisions

    /// Push the ball out of every wall, post and sail it overlaps, a few
    /// passes so a corner (two walls at once) settles too. True if it touched anything.
    private func collide(_ p: inout MiniGolfVec, _ v: inout MiniGolfVec, events: inout [MiniGolfEvent]) -> Bool {
        let r = MiniGolfRules.ballRadius
        var any = false
        for pass in 0..<3 {
            var touched = false
            for wall in hole.walls where wall.box.contains(p) {
                let q = MiniGolfGeo.closest(wall.a, wall.b, to: p)
                if let hit = Self.bounce(&p, &v, from: q, radius: MiniGolfRules.wallContact,
                                         restitution: MiniGolfRules.wallRestitution, surface: .zero) {
                    touched = true
                    if pass == 0 && hit > MiniGolfRules.bounceFloor { events.append(.wall(at: p, speed: hit)) }
                }
            }
            for (index, post) in hole.posts.enumerated() {
                let reach = post.radius + r
                let d = p - post.centre
                guard abs(d.x) < reach, abs(d.y) < reach, d.lengthSquared < reach * reach else { continue }
                if let hit = Self.bounce(&p, &v, from: post.centre, radius: reach,
                                         restitution: post.restitution, surface: .zero) {
                    touched = true
                    if pass == 0 && hit > MiniGolfRules.bounceFloor {
                        events.append(post.kind == .bumper ? .bumper(index: index, at: p, speed: hit) : .post(at: p, speed: hit))
                    }
                }
            }
            for mill in hole.windmills where p.distance(to: mill.pivot) < mill.reach + 0.1 {
                // The hub.
                if let hit = Self.bounce(&p, &v, from: mill.pivot, radius: mill.hub + r,
                                         restitution: MiniGolfRules.postRestitution, surface: .zero) {
                    touched = true
                    if pass == 0 && hit > MiniGolfRules.bounceFloor { events.append(.post(at: p, speed: hit)) }
                }
                for k in 0..<mill.arms {
                    let dir = MiniGolfVec.heading(mill.angle(k, at: clock))
                    let a = mill.pivot + dir * mill.hub
                    let b = mill.pivot + dir * mill.arm
                    let q = MiniGolfGeo.closest(a, b, to: p)
                    // The sail at the touching point moves round the pivot.
                    let surface = (q - mill.pivot).perp * mill.speed
                    if let hit = Self.bounce(&p, &v, from: q, radius: r + MiniGolfRules.armHalf,
                                             restitution: MiniGolfRules.armRestitution, surface: surface) {
                        touched = true
                        if pass == 0 && hit > MiniGolfRules.bounceFloor { events.append(.sail(at: p, speed: hit)) }
                    }
                }
            }
            if !touched { break }
            any = true
        }
        return any
    }

    /// If the ball at `p` is closer than `radius` to the surface point `q`,
    /// push it out to `radius` and reflect the part of its speed (relative to
    /// the surface, which may be moving) that was going in. Returns how fast it
    /// was going in, or nil when not touching.
    static func bounce(_ p: inout MiniGolfVec, _ v: inout MiniGolfVec, from q: MiniGolfVec, radius: Double,
                       restitution: Double, surface: MiniGolfVec) -> Double? {
        let d = p - q
        let dist2 = d.lengthSquared
        guard dist2 < radius * radius else { return nil }
        let dist = dist2.squareRoot()
        var n: MiniGolfVec
        if dist > 1e-9 {
            n = d * (1 / dist)
        } else {
            n = (-v).unit
            if n == .zero { n = MiniGolfVec(0, -1) }
        }
        p = q + n * radius
        let vn = (v - surface).dot(n)
        guard vn < 0 else { return 0 }
        let into = -vn
        let e = into < MiniGolfRules.bounceFloor ? 0 : restitution
        v = v - n * ((1 + e) * vn)
        return into
    }
}
