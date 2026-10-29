import Foundation

/// What the player is doing this frame.
struct PinballInput: Equatable {
    var left = false
    var right = false
    /// How far the plunger is pulled back, 0…1, while a finger holds it.
    var pull: Double = 0
    /// Let go of the plunger this frame, at this power (0…1).
    var launch: Double?
    /// The phone was shaken: which way (x about −1…1), and the table gets a shove.
    var nudge: PinballVec?
}

/// Where a game is.
enum PinballPhase: Equatable {
    case playing
    /// The last ball drained: the bonus is counted, then the next ball.
    case ballOver(until: Double)
    case over
}

/// A game of pinball: the table, the balls and flippers moving under fixed
/// 1/480 s substeps, and the rules — lanes, targets, bumpers, the ramp,
/// modes, multiball, ball save and tilt — scoring as they go.
///
/// Plain values and no clock of its own: the phone hands it each frame's
/// time, a test hands it whatever it likes, and the same seed and inputs
/// always play the same game.
struct PinballMachine {
    let table: PinballTable
    private(set) var balls: [PinballBall] = []
    private(set) var flippers: [PinballFlipper]
    private(set) var targetsUp: [Bool]
    private(set) var lanesLit: [Bool]
    private(set) var score = 0
    /// Which ball this is, from 1.
    private(set) var ballNumber = 1
    private(set) var ballsPerGame: Int
    private(set) var extraBalls = 0
    /// The bonus multiplier, lit by the top lanes: 1…5.
    private(set) var multiplier = 1
    /// Points banked this ball, paid times the multiplier when it drains.
    private(set) var bonus = 0
    /// The last end-of-ball bonus paid.
    private(set) var lastBonus = 0
    private(set) var mode: PinballMode = .bumperBlitz
    /// How many times round all four modes.
    private(set) var modeCycle = 0
    private(set) var modeProgress = 0
    private(set) var bankClears = 0
    /// Ramps and orbits in quick succession.
    private(set) var combo = 0
    private(set) var comboUntil: Double = -1
    private(set) var jackpot = PinballScoring.jackpot
    private(set) var multiball = false
    private(set) var saveUntil: Double = 0
    private(set) var tiltMeter: Double = 0
    private(set) var tiltWarnings = 0
    private(set) var tilted = false
    private(set) var phase: PinballPhase = .playing
    /// Seconds of play, advanced only by the substeps.
    private(set) var time: Double = 0
    /// The plunger's pull, 0…1, as drawn.
    private(set) var pull: Double = 0
    /// The lane that pays the skill shot, flashing while the ball waits.
    private(set) var skillLane = 1
    private(set) var skillArmedUntil: Double?
    /// Balls waiting to be served and launched by the machine (multiball, a saved ball).
    private(set) var queued = 0
    private(set) var autoLaunchAt: Double?
    /// The spinner flag, for drawing.
    private(set) var spinnerAngle: Double = 0
    private(set) var spinnerRate: Double = 0
    private(set) var flashes = PinballFlashes()
    private(set) var stats = PinballStats()
    private(set) var message: PinballMessage?
    private(set) var events: [PinballEvent] = []
    /// Times the ball search has had to free a stuck ball.
    private(set) var searches = 0

    private var targetsResetAt: Double?
    private var skillReady = true
    private var saveStarted = false
    private var accumulator: Double = 0
    private var rng: PinballRandom
    private var nextBallID = 1
    private var prevLeft = false
    private var prevRight = false
    private var messageSerial = 0
    private var cooldown: [Double] = [-9, -9, -9, -9, -9]
    private var prevPositions: [PinballVec] = []

    init(seed: UInt64 = 1, balls: Int = 3, table: PinballTable = .classic) {
        self.table = table
        ballsPerGame = max(1, balls)
        flippers = table.flippers.map { PinballFlipper(spec: $0) }
        targetsUp = Array(repeating: true, count: table.targets.count)
        lanesLit = Array(repeating: false, count: table.lanes.count)
        rng = PinballRandom(seed: seed)
        prevPositions.reserveCapacity(6)
        startBall()
    }

    // MARK: - Reading

    var isOver: Bool { phase == .over }
    var totalBalls: Int { ballsPerGame + extraBalls }
    var ballsLeft: Int { max(0, totalBalls - ballNumber) }
    var liveBalls: Int { balls.count + queued }
    var saveActive: Bool { time < saveUntil && !tilted }
    var modeGoal: Int { mode.goal(cycle: modeCycle) }
    /// Where the plunger's tip is now.
    var plungerY: Double { table.plungerRest + table.plungerTravel * pull }

    /// The ball sitting on the plunger, if one is.
    var waitingIndex: Int? {
        balls.firstIndex { ball in
            ball.ramp == nil && ball.p.x > table.plungerLeft && ball.p.y > plungerY - PinballTable.ballRadius - 8 && ball.speed < 90
        }
    }

    /// A ball waits for the player to pull the plunger (not one the machine will launch itself).
    var ballWaiting: Bool { phase == .playing && autoLaunchAt == nil && waitingIndex != nil }

    /// The strip's message now, if one is showing.
    var showing: PinballMessage? {
        guard let message, message.until > time else { return nil }
        return message
    }

    /// Hands over the step's events and forgets them.
    mutating func takeEvents() -> [PinballEvent] {
        let out = events
        events.removeAll(keepingCapacity: true)
        return out
    }

    // MARK: - Stepping

    mutating func step(_ input: PinballInput, dt: Double) {
        guard dt > 0, phase != .over else { return }
        let dt = min(dt, 1.0 / 20)
        let live = phase == .playing && !tilted
        let left = input.left && live
        let right = input.right && live
        if left && !prevLeft {
            events.append(.flipper(.left))
            rotateLanes(by: -1)
        }
        if right && !prevRight {
            events.append(.flipper(.right))
            rotateLanes(by: 1)
        }
        prevLeft = left
        prevRight = right
        flippers[0].held = left
        flippers[1].held = right
        let waiting = ballWaiting ? waitingIndex : nil
        pull = waiting != nil ? min(max(input.pull, 0), 1) : 0
        if let i = waiting {
            // The ball rides the plunger's tip as it is drawn back. Left to
            // fall after it, the ball stops counting as waiting mid-pull: the
            // plunger snaps back and a release in that moment is lost.
            balls[i].p.y = plungerY - PinballTable.ballRadius
            balls[i].v = .zero
        }
        if let power = input.launch { launch(power: power, manual: true) }
        if let nudge = input.nudge { shove(nudge) }

        accumulator += dt
        let h = PinballPhysics.substep
        while accumulator >= h {
            accumulator -= h
            substep(h)
            if phase == .over { break }
        }
    }

    private mutating func substep(_ h: Double) {
        time += h
        for i in flippers.indices { flippers[i].step(h) }

        prevPositions.removeAll(keepingCapacity: true)
        for i in balls.indices {
            prevPositions.append(balls[i].p)
            if let along = balls[i].ramp {
                ride(i, along + table.ramp.rideSpeed * h)
                continue
            }
            balls[i].v.y += PinballPhysics.gravity * h
            balls[i].v = PinballPhysics.clampSpeed(balls[i].v)
            balls[i].p += balls[i].v * h
        }
        if balls.count > 1 {
            for i in 0..<(balls.count - 1) {
                for j in (i + 1)..<balls.count where balls[i].ramp == nil && balls[j].ramp == nil {
                    var one = balls[i], two = balls[j]
                    if PinballPhysics.knock(&one, &two) {
                        balls[i] = one
                        balls[j] = two
                    }
                }
            }
        }
        for i in balls.indices where balls[i].ramp == nil {
            var ball = balls[i]
            contacts(&ball, from: prevPositions[i], h)
            balls[i] = ball
        }
        var i = 0
        while i < balls.count {
            if balls[i].ramp == nil && balls[i].p.y > PinballTable.drainY {
                let gone = balls.remove(at: i)
                prevPositions.remove(at: i)
                drained(gone)
            } else {
                i += 1
            }
        }
        tick(h)
    }

    /// Every wall, toy and sensor against one ball.
    private mutating func contacts(_ ball: inout PinballBall, from prev: PinballVec, _ h: Double) {
        for wall in table.walls {
            _ = PinballPhysics.collide(&ball, a: wall.a, b: wall.b, radius: wall.radius, bounce: wall.bounce, oneWay: wall.oneWay)
        }
        for (i, bumper) in table.bumpers.enumerated() {
            if tilted {
                // A tilted table's bumpers are dead rubber.
                _ = PinballPhysics.collide(&ball, a: bumper.centre, b: bumper.centre, radius: bumper.radius, bounce: 0.3)
            } else if PinballPhysics.bump(&ball, bumper) != nil, time - cooldown[i] > 0.06 {
                cooldown[i] = time
                register(.bumper(i))
            }
        }
        for (i, sling) in table.slings.enumerated() {
            guard let hit = PinballPhysics.collide(&ball, a: sling.a, b: sling.b, radius: 3, bounce: 0.5) else { continue }
            if !tilted, hit.impact > PinballPhysics.slingTrigger, hit.t > 0.06, hit.t < 0.94, time - cooldown[3 + i] > 0.1 {
                cooldown[3 + i] = time
                let n = sling.normal
                let along = ball.v - n * ball.v.dot(n)
                ball.v = along * 0.8 + n * PinballPhysics.slingKick
                register(.sling(sling.side))
            }
        }
        for (i, target) in table.targets.enumerated() where targetsUp[i] {
            if let hit = PinballPhysics.collide(&ball, a: target.a, b: target.b, radius: 3, bounce: 0.3), hit.impact > 40 {
                register(.target(i))
            }
        }
        for flipper in flippers {
            _ = PinballPhysics.flip(&ball, flipper)
        }
        // The plunger's tip under the ball in its lane.
        let floor = plungerY - PinballTable.ballRadius
        if ball.p.x > table.plungerLeft, ball.p.y > floor {
            ball.p.y = floor
            if ball.v.y > 0 { ball.v.y = ball.v.y > PinballPhysics.restingSpeed * 2 ? -ball.v.y * 0.2 : 0 }
            ball.v.x *= 0.9
        }
        ball.v = PinballPhysics.clampSpeed(ball.v)
        sense(&ball, from: prev, h)
    }

    /// The sensors: the ramp's mouth, the spinner, the top lanes, and the ball search.
    private mutating func sense(_ ball: inout PinballBall, from prev: PinballVec, _ h: Double) {
        let ramp = table.ramp
        let back = ramp.backCentre
        let s0 = (prev - back).dot(ramp.direction), s1 = (ball.p - back).dot(ramp.direction)
        let across = (ramp.backB - ramp.backA)
        let off = abs((ball.p - back).dot(across.normalized))
        if s0 < 0, s1 >= 0, off < across.length / 2, ball.v.dot(ramp.direction) > ramp.minSpeed {
            ball.ramp = 0
            ball.lane = nil
            register(.ramp)
            return
        }
        let spinner = table.spinner
        if PinballGeometry.crosses(prev, ball.p, spinner.a, spinner.b) {
            let spins = max(1, Int(abs(ball.v.y) / 240))
            register(.spinner(spins))
            if ball.v.y < -700 { register(.orbit) }
        }
        var over: Int?
        let reach = table.laneRadius
        for (i, lane) in table.lanes.enumerated() where (ball.p - lane).lengthSquared < reach * reach {
            over = i
        }
        if let over, ball.lane != over {
            ball.lane = over
            register(.lane(over))
        } else if over == nil, let was = ball.lane, (ball.p - table.lanes[was]).length > reach + 8 {
            ball.lane = nil
        }
        if !ball.inPlay, ball.p.x < table.plungerLeft - PinballTable.ballRadius {
            ball.inPlay = true
            if !saveStarted {
                saveStarted = true
                saveUntil = max(saveUntil, time + PinballScoring.ballSave)
            }
        }
        // Ball search: a ball that has hardly moved for a few seconds, with no
        // flipper holding it, gets a kick so a game can never jam.
        if (ball.p - ball.anchor).lengthSquared > 64 {
            ball.anchor = ball.p
            ball.still = 0
        } else if ball.inPlay, !cradled(ball) {
            ball.still += h
            if ball.still > 3.5 {
                ball.still = 0
                searches += 1
                ball.v = PinballVec(rng.range(-420, 420), -800)
            }
        } else {
            ball.still = 0
        }
    }

    /// Held on a raised flipper on purpose: the ball search leaves it be.
    private func cradled(_ ball: PinballBall) -> Bool {
        flippers.contains { $0.held && ($0.spec.pivot - ball.p).length < $0.spec.length + 30 }
    }

    private mutating func ride(_ i: Int, _ along: Double) {
        let ramp = table.ramp
        if along >= ramp.length {
            balls[i].ramp = nil
            balls[i].p = ramp.path.last ?? balls[i].p
            balls[i].v = ramp.exitVelocity
            balls[i].anchor = balls[i].p
            balls[i].still = 0
        } else {
            let at = PinballGeometry.along(ramp.path, along)
            balls[i].ramp = along
            balls[i].p = at.point
            balls[i].v = at.heading * ramp.rideSpeed
        }
    }

    /// The clocks: targets coming back up, balls served and launched, the
    /// end of a ball, the spinner and tilt bob settling.
    private mutating func tick(_ h: Double) {
        tiltMeter = max(0, tiltMeter - 0.35 * h)
        spinnerAngle += spinnerRate * h
        spinnerRate *= max(0, 1 - 1.6 * h)
        if let at = targetsResetAt, time >= at {
            let clear = table.targets.allSatisfy { target in
                balls.allSatisfy { (PinballGeometry.closest($0.p, target.a, target.b).point - $0.p).length > PinballTable.ballRadius + 6 }
            }
            if clear {
                targetsUp = Array(repeating: true, count: table.targets.count)
                targetsResetAt = nil
            }
        }
        if let until = skillArmedUntil, time > until { skillArmedUntil = nil }
        if comboUntil >= 0, time > comboUntil {
            combo = 0
            comboUntil = -1
        }
        switch phase {
        case .playing:
            if queued > 0, autoLaunchAt == nil, !laneOccupied {
                queued -= 1
                serve()
                autoLaunchAt = time + 0.6
            }
            if let at = autoLaunchAt, time >= at {
                autoLaunchAt = nil
                launch(power: 0.84 + rng.range(0, 0.12), manual: false)
            }
        case .ballOver(let until):
            if time >= until { nextBall() }
        case .over:
            break
        }
    }

    private var laneOccupied: Bool {
        balls.contains { $0.ramp == nil && $0.p.x > table.plungerLeft && $0.p.y > 300 }
    }

    // MARK: - Balls

    private mutating func serve() {
        balls.append(PinballBall(id: nextBallID, p: table.serve))
        nextBallID += 1
    }

    private mutating func startBall() {
        multiplier = 1
        bonus = 0
        lanesLit = Array(repeating: false, count: table.lanes.count)
        tiltMeter = 0
        tiltWarnings = 0
        tilted = false
        saveStarted = false
        saveUntil = 0
        skillLane = rng.int(table.lanes.count)
        skillReady = true
        skillArmedUntil = nil
        combo = 0
        comboUntil = -1
        multiball = false
        queued = 0
        autoLaunchAt = nil
        balls.removeAll()
        serve()
        say("BALL \(ballNumber)", "PULL BACK TO LAUNCH", 3, priority: 1)
    }

    private mutating func nextBall() {
        if ballNumber >= totalBalls {
            phase = .over
            events.append(.gameOver)
            say("GAME OVER", PinballScoring.digits(score), 60, priority: 9)
            return
        }
        ballNumber += 1
        phase = .playing
        startBall()
    }

    private mutating func launch(power: Double, manual: Bool) {
        guard phase == .playing, let i = waitingIndex else { return }
        let p = min(max(power, 0), 1)
        balls[i].v = PinballVec(0, -(PinballPhysics.launchMin + (PinballPhysics.launchMax - PinballPhysics.launchMin) * p))
        pull = 0
        events.append(.launch)
        if manual, skillReady {
            skillReady = false
            skillArmedUntil = time + PinballScoring.skillWindow
        }
    }

    private mutating func drained(_ ball: PinballBall) {
        let side: PinballDrain = ball.p.x < 70 ? .left : (ball.p.x > 448 ? .right : .centre)
        events.append(.drain(side))
        if saveActive {
            queued += 1
            stats.saves += 1
            flashes.save = time
            events.append(.ballSaved)
            say("BALL SAVED", "", 2, priority: 6)
            return
        }
        guard liveBalls == 0 else {
            if liveBalls == 1, multiball {
                multiball = false
                say("MULTIBALL OVER", "", 2, priority: 3)
            }
            return
        }
        endBall()
    }

    private mutating func endBall() {
        let award = tilted ? 0 : bonus * multiplier
        score += award
        lastBonus = award
        multiball = false
        events.append(.ballOver(award))
        if tilted {
            say("TILT", "NO BONUS", 2.6, priority: 8)
        } else {
            say("BONUS \(PinballScoring.digits(bonus)) X\(multiplier)", "+" + PinballScoring.digits(award), 2.6, priority: 8)
        }
        phase = .ballOver(until: time + 2.6)
    }

    // MARK: - Nudge and tilt

    private mutating func shove(_ way: PinballVec) {
        guard phase == .playing else { return }
        let side = min(max(way.x, -1), 1)
        for i in balls.indices where balls[i].ramp == nil && balls[i].inPlay {
            balls[i].v += PinballVec(side * PinballPhysics.nudgeSide, -PinballPhysics.nudgeLift)
        }
        guard !tilted else { return }
        tiltMeter += 0.55
        guard tiltMeter >= 1 else { return }
        tiltMeter = 0.35
        tiltWarnings += 1
        if tiltWarnings >= 3 {
            tilted = true
            flashes.tilt = time
            flippers[0].held = false
            flippers[1].held = false
            events.append(.tilt)
            say("TILT", "", 4, priority: 9)
        } else {
            events.append(.tiltWarning(tiltWarnings))
            say("DANGER", tiltWarnings == 2 ? "ONE MORE AND IT TILTS" : "EASY ON THE SHAKING", 2, priority: 7)
        }
    }

    // MARK: - Rules

    /// A hit scores and moves the modes on. Called by the physics; a test
    /// can call it directly.
    mutating func register(_ hit: PinballHit) {
        switch hit {
        case .bumper(let i):
            flashes.bumpers[i] = time
            events.append(.bumper(i))
            guard !tilted else { return }
            stats.bumpers += 1
            add(mode == .bumperBlitz ? PinballScoring.bumper * 2 : PinballScoring.bumper)
            bonus += 25
            if mode == .bumperBlitz { advance() }
        case .sling(let side):
            flashes.slings[side.rawValue] = time
            events.append(.sling(side))
            guard !tilted else { return }
            add(PinballScoring.sling)
            bonus += 10
        case .target(let i):
            guard i < targetsUp.count, targetsUp[i] else { return }
            targetsUp[i] = false
            flashes.targets[i] = time
            events.append(.target(i))
            let cleared = !targetsUp.contains(true)
            if cleared { targetsResetAt = time + 1.5 }
            guard !tilted else { return }
            add(PinballScoring.target)
            bonus += 250
            if cleared {
                bankClears += 1
                stats.banks += 1
                flashes.bank = time
                let award = PinballScoring.bank * min(bankClears, 5)
                add(award)
                events.append(.bankCleared)
                say("TARGETS CLEARED", "+" + PinballScoring.digits(award), 2, priority: 4)
                if mode == .targetPractice { advance() }
            }
        case .lane(let i):
            guard i < lanesLit.count else { return }
            flashes.lanes[i] = time
            events.append(.lane(i))
            guard !tilted else { return }
            if let until = skillArmedUntil, time <= until {
                skillArmedUntil = nil
                if i == skillLane {
                    add(PinballScoring.skillShot)
                    stats.skillShots += 1
                    events.append(.skillShot)
                    say("SKILL SHOT", "+" + PinballScoring.digits(PinballScoring.skillShot), 2.2, priority: 6)
                }
            }
            guard !lanesLit[i] else {
                add(PinballScoring.laneAgain)
                return
            }
            lanesLit[i] = true
            add(PinballScoring.lane)
            bonus += 100
            if !lanesLit.contains(false) {
                lanesLit = Array(repeating: false, count: lanesLit.count)
                flashes.lanesAll = time
                add(PinballScoring.lanesAll)
                if multiplier < PinballScoring.maxMultiplier {
                    multiplier += 1
                    say("BONUS X\(multiplier)", "LANES COMPLETE", 2, priority: 4)
                } else {
                    add(PinballScoring.multiplierFull)
                    say("LANES COMPLETE", "+" + PinballScoring.digits(PinballScoring.multiplierFull), 2, priority: 4)
                }
                events.append(.lanesComplete(multiplier))
            }
        case .spinner(let spins):
            spinnerRate = min(80, spinnerRate + Double(spins) * 9)
            events.append(.spinner(spins))
            guard !tilted else { return }
            add(PinballScoring.spin * spins)
        case .orbit:
            flashes.orbit = time
            events.append(.orbit)
            guard !tilted else { return }
            let c = comboUp()
            stats.orbits += 1
            add(PinballScoring.orbit * c)
            bonus += 500
            say("ORBIT", c > 1 ? "COMBO X\(c)" : "+" + PinballScoring.digits(PinballScoring.orbit), 1.8, priority: 3)
            if mode == .orbitRun { advance() }
        case .ramp:
            flashes.ramp = time
            guard !tilted else {
                events.append(.ramp(0))
                return
            }
            let c = comboUp()
            events.append(.ramp(c))
            stats.ramps += 1
            add(PinballScoring.ramp * c)
            bonus += 1_000
            if multiball {
                add(jackpot)
                stats.jackpots += 1
                flashes.jackpot = time
                events.append(.jackpot(jackpot))
                say("JACKPOT", PinballScoring.digits(jackpot), 2.4, priority: 7)
                jackpot += PinballScoring.jackpotStep
            } else {
                say("RAMP", c > 1 ? "COMBO X\(c)" : "+" + PinballScoring.digits(PinballScoring.ramp), 1.8, priority: 3)
            }
            if mode == .rampRush { advance() }
        }
    }

    private mutating func add(_ points: Int) { score += points }

    private mutating func comboUp() -> Int {
        combo = time <= comboUntil ? min(combo + 1, PinballScoring.maxCombo) : 1
        comboUntil = time + PinballScoring.comboWindow
        return combo
    }

    private mutating func advance() {
        modeProgress += 1
        guard modeProgress >= modeGoal else { return }
        let done = mode
        let award = PinballScoring.mode * (modeCycle + 1)
        add(award)
        stats.modes += 1
        flashes.mode = time
        events.append(.modeComplete(done))
        modeProgress = 0
        if done == .orbitRun {
            extraBalls += 1
            events.append(.extraBall)
            modeCycle += 1
        }
        mode = done.next
        startMultiball(after: done, award: award)
    }

    private mutating func startMultiball(after done: PinballMode, award: Int) {
        if multiball {
            // Already in multiball: the mode pays a jackpot instead.
            add(jackpot)
            stats.jackpots += 1
            events.append(.jackpot(jackpot))
            say(done.title, "COMPLETE  +" + PinballScoring.digits(award + jackpot), 2.6, priority: 8)
            return
        }
        multiball = true
        queued += 2
        jackpot = PinballScoring.jackpot * (modeCycle + 1)
        saveUntil = max(saveUntil, time + PinballScoring.multiballSave)
        events.append(.multiball)
        say("MULTIBALL", done == .orbitRun ? "AND AN EXTRA BALL" : "RAMP FOR JACKPOT", 3, priority: 8)
    }

    /// The flippers pass the lit lanes along, so a player can line up the gap.
    private mutating func rotateLanes(by step: Int) {
        guard lanesLit.contains(true), lanesLit.contains(false) else { return }
        let n = lanesLit.count
        var out = lanesLit
        for i in 0..<n { out[((i + step) % n + n) % n] = lanesLit[i] }
        lanesLit = out
    }

    private mutating func say(_ top: String, _ bottom: String, _ seconds: Double, priority: Int) {
        if let showing, showing.priority > priority { return }
        messageSerial += 1
        message = PinballMessage(top: top, bottom: bottom, until: time + seconds, priority: priority, serial: messageSerial)
    }

    // MARK: - Placing (tests, the demo)

    /// Puts the first ball (serving one if there is none) at `p`, moving at `v`, in play.
    mutating func put(ballAt p: PinballVec, moving v: PinballVec = .zero) {
        if balls.isEmpty { serve() }
        balls[0].p = p
        balls[0].v = v
        balls[0].ramp = nil
        balls[0].inPlay = true
        balls[0].anchor = p
        balls[0].still = 0
        autoLaunchAt = nil
    }

    /// Starts this ball's save clock now, as a launch out of the lane would.
    mutating func startSave() {
        saveStarted = true
        saveUntil = time + PinballScoring.ballSave
    }
}
