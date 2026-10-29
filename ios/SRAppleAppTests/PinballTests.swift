import XCTest
@testable import SRAppleApp

final class PinballTests: XCTestCase {
    private let frame = 1.0 / 60

    /// Runs `seconds` of play with the same input every frame, collecting the events.
    @discardableResult
    private func run(_ machine: inout PinballMachine, seconds: Double, _ input: PinballInput = PinballInput()) -> [PinballEvent] {
        var events: [PinballEvent] = []
        let frames = Int((seconds / frame).rounded())
        for _ in 0..<frames {
            machine.step(input, dt: frame)
            events += machine.takeEvents()
        }
        return events
    }

    private func isLegal(_ p: PinballVec, on table: PinballTable) -> Bool {
        guard p.isFinite else { return false }
        // Below the flippers the ball is falling out of the drain.
        let inside = PinballGeometry.inside(p, table.outline) || (p.y > 990 && p.x > 0 && p.x < PinballTable.width)
        guard inside else { return false }
        if table.solids.contains(where: { PinballGeometry.inside(p, $0) }) { return false }
        for bumper in table.bumpers where (p - bumper.centre).length < bumper.radius + PinballTable.ballRadius - 3 {
            return false
        }
        return true
    }

    // MARK: - Physics

    func testTheBallNeverLeavesTheTableUnderRandomFlippingAtTopSpeed() {
        var rng = PinballRandom(seed: 2026)
        var machine = PinballMachine(seed: 7, balls: 10_000)
        var left = false, right = false
        var played = 0
        for step in 0..<10_000 {
            if rng.unit() < 0.12 { left.toggle() }
            if rng.unit() < 0.12 { right.toggle() }
            var input = PinballInput(left: left, right: right)
            if machine.ballWaiting && rng.unit() < 0.1 { input.launch = rng.unit() }
            if rng.unit() < 0.01 { input.nudge = PinballVec(rng.range(-1, 1), -1) }
            machine.step(input, dt: frame)
            _ = machine.takeEvents()
            // Every so often, fling every free ball at the top speed in a random direction.
            if step % 40 == 0 {
                for i in machine.balls.indices where machine.balls[i].ramp == nil && machine.balls[i].inPlay {
                    let angle = rng.range(0, 2 * Double.pi)
                    let ball = machine.balls[i]
                    machine.put(ballAt: ball.p, moving: PinballVec(cos(angle), sin(angle)) * PinballPhysics.maxSpeed)
                    break
                }
            }
            for ball in machine.balls where ball.ramp == nil {
                played += 1
                XCTAssertTrue(isLegal(ball.p, on: machine.table), "step \(step): ball at \(ball.p) left the table")
                XCTAssertLessThanOrEqual(ball.speed, PinballPhysics.maxSpeed + 1e-6)
            }
        }
        XCTAssertGreaterThan(played, 5_000)
    }

    func testAFlipperHeldUpCatchesTheBall() {
        var machine = PinballMachine(seed: 5)
        machine.put(ballAt: PinballVec(215, 700), moving: PinballVec(0, 300))
        let events = run(&machine, seconds: 4, PinballInput(left: true))
        XCTAssertFalse(events.contains { if case .drain = $0 { return true }; return false })
        guard let ball = machine.balls.first else { return XCTFail("the ball went") }
        XCTAssertLessThan(ball.speed, 30, "a cradled ball is still")
        let flipper = machine.flippers[0]
        XCTAssertLessThan((ball.p - flipper.spec.pivot).length, flipper.spec.length, "it rests on the left flipper")
        XCTAssertLessThan(ball.p.y, flipper.spec.pivot.y)
    }

    func testAFlipperHitSendsTheBallUpTheTable() {
        for side in PinballSide.allCases {
            var machine = PinballMachine(seed: 5)
            let flipper = machine.flippers[side.rawValue]
            let spot = flipper.spec.pivot + flipper.direction * (flipper.spec.length * 0.55) + PinballVec(0, -26)
            machine.put(ballAt: spot)
            run(&machine, seconds: 0.1)
            var input = PinballInput()
            if side == .left { input.left = true } else { input.right = true }
            var highest = Double.infinity
            var fastest = 0.0
            for _ in 0..<45 {
                machine.step(input, dt: frame)
                _ = machine.takeEvents()
                if let ball = machine.balls.first {
                    highest = min(highest, ball.p.y)
                    fastest = max(fastest, -ball.v.y)
                }
            }
            XCTAssertLessThan(highest, 600, "\(side) flipper sends the ball up the table")
            XCTAssertGreaterThan(fastest, 1_500)
        }
    }

    func testTheOneWayGateLetsALaunchOutButNotABallBackIn() {
        var machine = PinballMachine(seed: 1)
        let events = run(&machine, seconds: 0.05, PinballInput(launch: 1))
        XCTAssertTrue(events.contains(.launch))
        run(&machine, seconds: 0.8)
        XCTAssertTrue(machine.balls[0].inPlay, "the launched ball left the plunger lane")

        var other = PinballMachine(seed: 1)
        other.put(ballAt: PinballVec(540, 250), moving: PinballVec(0, 600))
        run(&other, seconds: 0.6)
        if let ball = other.balls.first {
            XCTAssertLessThan(ball.p.x, other.table.plungerLeft, "the gate turned the ball into the playfield")
        }
    }

    func testDrawingThePlungerBackKeepsTheBallOnItAndTheReleaseFires() {
        for seconds in [0.05, 0.25, 0.6] {
            var machine = PinballMachine(seed: 3)
            run(&machine, seconds: 0.4)
            XCTAssertTrue(machine.ballWaiting)
            let frames = Int((seconds / frame).rounded())
            for k in 1...frames {
                let pull = min(1, Double(k) / Double(frames))
                machine.step(PinballInput(pull: pull), dt: frame)
                _ = machine.takeEvents()
                XCTAssertTrue(machine.ballWaiting, "the ball is still on the plunger mid-pull (\(seconds) s)")
                XCTAssertEqual(machine.pull, pull, accuracy: 1e-9)
            }
            machine.step(PinballInput(launch: 1), dt: frame)
            XCTAssertTrue(machine.takeEvents().contains(.launch), "a release after a \(seconds) s pull launches")
        }
    }

    func testRampShotRidesOverAndDropsIntoTheLeftInlane() {
        var machine = PinballMachine(seed: 1)
        let ramp = machine.table.ramp
        machine.put(ballAt: ramp.backCentre - ramp.direction * 40, moving: ramp.direction * 1_800)
        var events = run(&machine, seconds: 0.1)
        XCTAssertTrue(events.contains(.ramp(1)))
        XCTAssertNotNil(machine.balls[0].ramp)
        XCTAssertEqual(machine.score, PinballScoring.ramp)
        events = run(&machine, seconds: ramp.length / ramp.rideSpeed + 0.05)
        let ball = machine.balls[0]
        XCTAssertNil(ball.ramp)
        XCTAssertLessThan(ball.p.x, 110)
        XCTAssertGreaterThan(ball.v.y, 0, "it leaves the ramp heading down the inlane")
    }

    func testASlowBallRollsBackOutOfTheRamp() {
        var machine = PinballMachine(seed: 1)
        let ramp = machine.table.ramp
        machine.put(ballAt: ramp.backCentre - ramp.direction * 50, moving: ramp.direction * 300)
        let events = run(&machine, seconds: 1)
        XCTAssertFalse(events.contains { if case .ramp = $0 { return true }; return false })
    }

    func testTheOrbitSpinsTheSpinner() {
        var machine = PinballMachine(seed: 1)
        machine.put(ballAt: PinballVec(37, 420), moving: PinballVec(0, -2_000))
        let events = run(&machine, seconds: 0.2)
        XCTAssertTrue(events.contains(.orbit))
        XCTAssertTrue(events.contains { if case .spinner(let n) = $0 { return n >= 5 }; return false })
        XCTAssertGreaterThan(machine.spinnerRate, 0)
    }

    // MARK: - Drains and ball save

    func testACentreDrainEndsTheBallAndServesTheNext() {
        var machine = PinballMachine(seed: 1)
        machine.put(ballAt: PinballVec(259, 1_010), moving: PinballVec(0, 500))
        var events = run(&machine, seconds: 0.2)
        XCTAssertTrue(events.contains(.drain(.centre)))
        XCTAssertTrue(events.contains { if case .ballOver = $0 { return true }; return false })
        if case .ballOver(let until) = machine.phase {
            XCTAssertGreaterThan(until, machine.time, "the bonus is being counted")
        } else {
            XCTFail("expected the ball to be over, got \(machine.phase)")
        }
        events = run(&machine, seconds: 3)
        XCTAssertEqual(machine.ballNumber, 2)
        XCTAssertEqual(machine.phase, .playing)
        XCTAssertTrue(machine.ballWaiting)
    }

    func testOutlanesAreDrainsOnTheirSide() {
        var left = PinballMachine(seed: 1)
        left.put(ballAt: PinballVec(36, 985), moving: PinballVec(0, 400))
        XCTAssertTrue(run(&left, seconds: 0.2).contains(.drain(.left)))
        var right = PinballMachine(seed: 1)
        right.put(ballAt: PinballVec(482, 985), moving: PinballVec(0, 400))
        XCTAssertTrue(run(&right, seconds: 0.2).contains(.drain(.right)))
    }

    func testBallSaveReturnsTheBall() {
        var machine = PinballMachine(seed: 1)
        machine.startSave()
        XCTAssertTrue(machine.saveActive)
        machine.put(ballAt: PinballVec(259, 1_010), moving: PinballVec(0, 500))
        var events = run(&machine, seconds: 0.2)
        XCTAssertTrue(events.contains(.ballSaved))
        XCTAssertFalse(events.contains { if case .ballOver = $0 { return true }; return false })
        XCTAssertEqual(machine.ballNumber, 1)
        // Served back on the plunger and launched by the machine.
        events = run(&machine, seconds: 1.2)
        XCTAssertTrue(events.contains(.launch))
        XCTAssertEqual(machine.balls.count, 1)
        XCTAssertLessThan(machine.balls[0].v.y, 0)
    }

    func testBallSaveRunsOutAndThreeBallsEndTheGame() {
        var machine = PinballMachine(seed: 1)
        machine.startSave()
        run(&machine, seconds: PinballScoring.ballSave + 0.5)
        XCTAssertFalse(machine.saveActive)
        for ball in 1...3 {
            XCTAssertEqual(machine.ballNumber, ball)
            machine.put(ballAt: PinballVec(259, 1_010), moving: PinballVec(0, 500))
            run(&machine, seconds: 3)
        }
        XCTAssertTrue(machine.isOver)
        let before = machine.score
        machine.step(PinballInput(left: true), dt: frame)
        XCTAssertEqual(machine.score, before, "nothing moves after the game")
    }

    // MARK: - Rules

    func testTopLanesLightTheMultiplierAndTheFlippersMoveThem() {
        var machine = PinballMachine(seed: 1)
        machine.register(.lane(0))
        XCTAssertEqual(machine.lanesLit, [true, false, false])
        XCTAssertEqual(machine.score, PinballScoring.lane)
        machine.register(.lane(0))
        XCTAssertEqual(machine.score, PinballScoring.lane + PinballScoring.laneAgain, "a lit lane pays a little")
        // The right flipper passes the light one lane to the right.
        machine.step(PinballInput(right: true), dt: frame)
        XCTAssertEqual(machine.lanesLit, [false, true, false])
        machine.step(PinballInput(), dt: frame)
        machine.step(PinballInput(left: true), dt: frame)
        XCTAssertEqual(machine.lanesLit, [true, false, false])
        machine.register(.lane(1))
        machine.register(.lane(2))
        XCTAssertEqual(machine.multiplier, 2)
        XCTAssertEqual(machine.lanesLit, [false, false, false], "the lanes go out to be lit again")
        XCTAssertTrue(machine.events.contains(.lanesComplete(2)))
    }

    func testTheMultiplierStopsAtFiveAndThenPays() {
        var machine = PinballMachine(seed: 1)
        for _ in 0..<4 { for i in 0..<3 { machine.register(.lane(i)) } }
        XCTAssertEqual(machine.multiplier, 5)
        let before = machine.score
        for i in 0..<3 { machine.register(.lane(i)) }
        XCTAssertEqual(machine.multiplier, 5)
        XCTAssertEqual(machine.score - before, PinballScoring.lane * 3 + PinballScoring.lanesAll + PinballScoring.multiplierFull)
    }

    func testDropTargetsScoreClearAndComeBackUp() {
        var machine = PinballMachine(seed: 1)
        machine.register(.target(1))
        XCTAssertEqual(machine.targetsUp, [true, false, true])
        machine.register(.target(1))
        XCTAssertEqual(machine.score, PinballScoring.target, "a target that is down cannot score")
        machine.register(.target(0))
        machine.register(.target(2))
        XCTAssertEqual(machine.targetsUp, [false, false, false])
        XCTAssertEqual(machine.bankClears, 1)
        XCTAssertEqual(machine.score, PinballScoring.target * 3 + PinballScoring.bank)
        XCTAssertTrue(machine.events.contains(.bankCleared))
        // The ball is on the plunger, far from the bank: the targets come back.
        run(&machine, seconds: 1.7)
        XCTAssertEqual(machine.targetsUp, [true, true, true])
        // The second clear pays double.
        for i in 0..<3 { machine.register(.target(i)) }
        XCTAssertEqual(machine.score, PinballScoring.target * 6 + PinballScoring.bank * 3)
    }

    func testTheBonusIsPaidTimesTheMultiplierWhenTheBallDrains() {
        var machine = PinballMachine(seed: 1)
        for i in 0..<3 { machine.register(.lane(i)) }
        machine.register(.target(0))
        let bonus = machine.bonus
        XCTAssertGreaterThan(bonus, 0)
        let before = machine.score
        machine.put(ballAt: PinballVec(259, 1_010), moving: PinballVec(0, 500))
        let events = run(&machine, seconds: 0.2)
        XCTAssertTrue(events.contains(.ballOver(bonus * 2)))
        XCTAssertEqual(machine.score - before, bonus * 2)
    }

    func testFinishingAModeStartsMultiballAndTheRampPaysJackpots() {
        var machine = PinballMachine(seed: 1)
        XCTAssertEqual(machine.mode, .bumperBlitz)
        machine.put(ballAt: PinballVec(259, 600))
        for _ in 0..<PinballMode.bumperBlitz.goal(cycle: 0) { machine.register(.bumper(0)) }
        XCTAssertTrue(machine.events.contains(.modeComplete(.bumperBlitz)))
        XCTAssertTrue(machine.events.contains(.multiball))
        XCTAssertEqual(machine.mode, .rampRush)
        XCTAssertTrue(machine.multiball)
        XCTAssertEqual(machine.liveBalls, 3)
        XCTAssertTrue(machine.saveActive)
        // The machine serves and launches the two new balls itself.
        let events = run(&machine, seconds: 2.5, PinballInput(left: true))
        XCTAssertEqual(events.filter { $0 == .launch }.count, 2)
        let before = machine.score
        machine.register(.ramp)
        XCTAssertTrue(machine.events.contains(.jackpot(PinballScoring.jackpot)))
        XCTAssertEqual(machine.score - before, PinballScoring.ramp + PinballScoring.jackpot)
        XCTAssertEqual(machine.jackpot, PinballScoring.jackpot + PinballScoring.jackpotStep)
    }

    func testRampsAndOrbitsInQuickSuccessionCombo() {
        var machine = PinballMachine(seed: 1)
        machine.register(.ramp)
        XCTAssertEqual(machine.score, PinballScoring.ramp)
        machine.register(.orbit)
        XCTAssertEqual(machine.score, PinballScoring.ramp + PinballScoring.orbit * 2)
        run(&machine, seconds: PinballScoring.comboWindow + 0.5)
        XCTAssertEqual(machine.combo, 0)
        let before = machine.score
        machine.register(.ramp)
        XCTAssertEqual(machine.score - before, PinballScoring.ramp)
    }

    func testTheFourModesComeRoundWithAnExtraBall() {
        var machine = PinballMachine(seed: 1)
        for _ in 0..<PinballMode.bumperBlitz.goal(cycle: 0) { machine.register(.bumper(1)) }
        for _ in 0..<PinballMode.rampRush.goal(cycle: 0) { machine.register(.ramp) }
        for _ in 0..<PinballMode.targetPractice.goal(cycle: 0) {
            for i in 0..<3 { machine.register(.target(i)) }
            run(&machine, seconds: 1.7)
        }
        XCTAssertEqual(machine.mode, .orbitRun)
        for _ in 0..<PinballMode.orbitRun.goal(cycle: 0) { machine.register(.orbit) }
        XCTAssertEqual(machine.mode, .bumperBlitz)
        XCTAssertEqual(machine.modeCycle, 1)
        XCTAssertEqual(machine.extraBalls, 1)
        XCTAssertEqual(machine.totalBalls, 4)
        XCTAssertEqual(machine.stats.modes, 4)
        XCTAssertGreaterThan(PinballMode.bumperBlitz.goal(cycle: 1), PinballMode.bumperBlitz.goal(cycle: 0))
    }

    func testTheSkillShotPaysOnlyTheFlashingLaneAfterALaunch() {
        var machine = PinballMachine(seed: 3)
        machine.step(PinballInput(launch: 0.5), dt: frame)
        machine.register(.lane(machine.skillLane))
        XCTAssertTrue(machine.events.contains(.skillShot))
        XCTAssertEqual(machine.score, PinballScoring.skillShot + PinballScoring.lane)

        var miss = PinballMachine(seed: 3)
        miss.step(PinballInput(launch: 0.5), dt: frame)
        miss.register(.lane((miss.skillLane + 1) % 3))
        miss.register(.lane(miss.skillLane))
        XCTAssertFalse(miss.events.contains(.skillShot), "only the first lane after the launch counts")
    }

    func testShakingTooMuchTilts() {
        var machine = PinballMachine(seed: 1)
        machine.put(ballAt: PinballVec(259, 600))
        machine.register(.target(0))
        var warnings = 0
        var tilted = false
        for _ in 0..<12 {
            machine.step(PinballInput(nudge: PinballVec(1, -1)), dt: frame)
            for event in machine.takeEvents() {
                if case .tiltWarning = event { warnings += 1 }
                if event == .tilt { tilted = true }
            }
            if tilted { break }
        }
        XCTAssertEqual(warnings, 2)
        XCTAssertTrue(tilted)
        XCTAssertTrue(machine.tilted)
        // Dead flippers and no points while tilted.
        let before = machine.score
        machine.step(PinballInput(left: true), dt: frame)
        run(&machine, seconds: 0.1, PinballInput(left: true))
        XCTAssertFalse(machine.flippers[0].held)
        XCTAssertEqual(machine.flippers[0].angle, machine.flippers[0].spec.restAngle, accuracy: 1e-9)
        machine.register(.bumper(0))
        XCTAssertEqual(machine.score, before)
        // No bonus for a tilted ball, and the next ball is fresh.
        machine.put(ballAt: PinballVec(259, 1_010), moving: PinballVec(0, 500))
        let events = run(&machine, seconds: 3)
        XCTAssertTrue(events.contains(.ballOver(0)))
        XCTAssertEqual(machine.ballNumber, 2)
        XCTAssertFalse(machine.tilted)
    }

    func testAGentleNudgeIsJustANudge() {
        var machine = PinballMachine(seed: 1)
        machine.put(ballAt: PinballVec(259, 600))
        machine.step(PinballInput(nudge: PinballVec(-1, -1)), dt: frame)
        XCTAssertLessThan(machine.balls[0].v.x, 0)
        XCTAssertLessThan(machine.balls[0].v.y, 0)
        XCTAssertEqual(machine.tiltWarnings, 0)
        run(&machine, seconds: 3)
        machine.step(PinballInput(nudge: PinballVec(1, -1)), dt: frame)
        XCTAssertEqual(machine.tiltWarnings, 0, "the bob settles between nudges")
    }

    func testTheSameSeedAndInputsPlayTheSameGame() {
        func play() -> (Int, Int) {
            var machine = PinballMachine(seed: 11, balls: 2)
            var rng = PinballRandom(seed: 4)
            for _ in 0..<3_000 {
                var input = PinballInput(left: rng.unit() < 0.4, right: rng.unit() < 0.4)
                if machine.ballWaiting { input.launch = rng.unit() }
                machine.step(input, dt: frame)
            }
            return (machine.score, machine.ballNumber)
        }
        let a = play(), b = play()
        XCTAssertEqual(a.0, b.0)
        XCTAssertEqual(a.1, b.1)
    }

    // MARK: - The strip and the table

    func testTheDotMatrixDrawsScoresAndMessages() {
        XCTAssertEqual(PinballScoring.digits(0), "0")
        XCTAssertEqual(PinballScoring.digits(1_234_567), "1,234,567")
        XCTAssertEqual(PinballScoring.digits(999), "999")
        let small = PinballDotFrame.score(12_340)
        XCTAssertGreaterThan(small.litCount, 0)
        XCTAssertLessThanOrEqual(PinballDotFont.width("1,234,567", scale: 2), PinballDotFrame.columns)
        let huge = PinballDotFrame.score(1_234_567_890_123)
        XCTAssertGreaterThan(huge.litCount, 0)
        XCTAssertNotEqual(PinballDotFrame.message("JACKPOT", ""), PinballDotFrame.message("TILT", ""))
        XCTAssertEqual(PinballDotFont.glyph(",").width, 2)
        XCTAssertEqual(PinballDotFont.glyph("a").rows, PinballDotFont.glyph("A").rows)
        // A letter that upper-cases to two must not crash the strip.
        XCTAssertEqual(PinballDotFont.glyph("ß").rows, PinballDotFont.glyph("S").rows)
        // Every message the machine can show fits on a line of the strip.
        for line in ["PULL BACK TO LAUNCH", "ONE MORE AND IT TILTS", "EASY ON THE SHAKING", "AND AN EXTRA BALL", "TARGET PRACTICE"] {
            XCTAssertLessThanOrEqual(PinballDotFont.width(line, scale: 1), PinballDotFrame.columns, line)
        }
    }

    func testTheTableIsBuiltSoundly() {
        let table = PinballTable.classic
        XCTAssertEqual(table.bumpers.count, 3)
        XCTAssertEqual(table.targets.count, 3)
        XCTAssertEqual(table.lanes.count, 3)
        XCTAssertEqual(table.slings.count, 2)
        // The slings kick into the playfield, towards the middle.
        XCTAssertGreaterThan(table.slings[0].normal.x, 0)
        XCTAssertLessThan(table.slings[1].normal.x, 0)
        XCTAssertTrue(table.walls.contains { $0.oneWay })
        // The ball fits down the plunger lane, the outlanes and between the flippers.
        XCTAssertGreaterThan(table.plungerRight - table.plungerLeft, PinballTable.ballRadius * 2)
        let left = PinballFlipper(spec: table.flippers[0]), right = PinballFlipper(spec: table.flippers[1])
        XCTAssertGreaterThan((right.tip - left.tip).length - left.spec.tipRadius * 2, PinballTable.ballRadius * 2)
        XCTAssertTrue(PinballGeometry.inside(table.serve, table.outline))
        XCTAssertGreaterThan(table.ramp.length, 600)
    }

    // MARK: - High scores

    func testTheHighScoreTableKeepsTheTopTen() {
        var book = PinballScoreBook()
        XCTAssertNil(book.record(score: 0, modes: 0), "an empty game is not a score")
        for n in 1...12 { book.record(score: n * 1_000, modes: 0, id: "g\(n)") }
        XCTAssertEqual(book.entries.count, PinballScoreBook.size)
        XCTAssertEqual(book.best, 12_000)
        XCTAssertEqual(book.entries.last?.score, 3_000)
        XCTAssertNil(book.record(score: 500, modes: 0))
        XCTAssertEqual(book.record(score: 12_000, modes: 2, id: "tie"), 2, "a tie goes below the older score")
        book.rename("tie", to: "j k!l9")
        XCTAssertEqual(book.entries[1].initials, "JKL")
        XCTAssertEqual(book.lastInitials, "JKL")
        XCTAssertEqual(book.games, 15)

        let defaults = UserDefaults(suiteName: "pinball-tests")!
        defaults.removePersistentDomain(forName: "pinball-tests")
        let store = PinballScoreStore(defaults: defaults)
        XCTAssertEqual(store.load(), PinballScoreBook())
        store.save(book)
        XCTAssertEqual(store.load(), book)
    }

    // MARK: - Sparks and the demo pilot

    func testSparksFlyFadeAndNeverPileUp() {
        var sparks = PinballSparks()
        var rng = PinballRandom(seed: 1)
        sparks.burst(at: PinballVec(100, 100), count: 20, speed: 400, hue: 0, rng: &rng)
        XCTAssertEqual(sparks.items.count, 20)
        sparks.step(0.1)
        XCTAssertTrue(sparks.items.allSatisfy { $0.fade < 1 && $0.fade > 0 })
        for _ in 0..<20 { sparks.burst(at: .zero, count: 30, speed: 300, hue: 1, rng: &rng) }
        XCTAssertEqual(sparks.items.count, PinballSparks.cap)
        for _ in 0..<60 { sparks.step(1.0 / 60) }
        XCTAssertTrue(sparks.isEmpty)
    }

    func testTheDemoPilotKeepsAGameGoing() {
        var machine = PinballMachine(seed: 21)
        var flips = 0
        for _ in 0..<(60 * 60) {
            machine.step(PinballAutopilot.input(for: machine), dt: frame)
            flips += machine.takeEvents().filter { if case .flipper = $0 { return true }; return false }.count
            if machine.isOver { break }
        }
        XCTAssertGreaterThan(flips, 5)
        XCTAssertGreaterThan(machine.score, 0)
        XCTAssertEqual(machine.searches, 0, "nothing jammed")
    }
}
