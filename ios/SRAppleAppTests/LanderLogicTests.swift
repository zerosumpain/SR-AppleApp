import XCTest
@testable import SRAppleApp

final class LanderLogicTests: XCTestCase {
    /// A flat world with a pad in the middle, so a test knows exactly where the ground is.
    private func flatFlight(level: Int = 1, x: Double = 240, y: Double = 52.2, fuel: Double = 100) -> LanderFlight {
        LanderFlight(level: .make(level),
                     terrain: LanderTerrain(heights: Array(repeating: 50, count: 61), step: 8,
                                            padStart: 216, padEnd: 264, padHeight: 50),
                     craft: LanderCraft(x: x, y: y, fuel: fuel))
    }

    // MARK: - Levels

    func testLevelsGetHarderAndStayFlyable() {
        let one = LanderLevel.make(1), five = LanderLevel.make(5), forty = LanderLevel.make(40)
        XCTAssertEqual(one.gravity, 1.62, accuracy: 1e-9)
        XCTAssertEqual(one.wind, 0)
        XCTAssertGreaterThan(five.gravity, one.gravity)
        XCTAssertLessThan(five.fuel, one.fuel)
        XCTAssertLessThan(five.padWidth, one.padWidth)
        XCTAssertNotEqual(LanderLevel.make(3).wind, 0)
        // The ceiling: full thrust always beats gravity, and the pad never vanishes.
        XCTAssertLessThan(forty.gravity, LanderRules.thrustAccel)
        XCTAssertGreaterThanOrEqual(forty.padWidth, 16)
        XCTAssertGreaterThanOrEqual(forty.fuel, 80)
        XCTAssertEqual(LanderLevel.make(0).number, 1)
    }

    // MARK: - Terrain

    func testTheSameSeedMakesTheSameGround() {
        let a = LanderTerrain.generate(level: .make(2), seed: 99, startsLeft: true)
        let b = LanderTerrain.generate(level: .make(2), seed: 99, startsLeft: true)
        let c = LanderTerrain.generate(level: .make(2), seed: 100, startsLeft: true)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testThePadIsFlatAndOnTheFarSide() {
        for seed in UInt64(1)...40 {
            let level = LanderLevel.make(Int(seed % 8) + 1)
            for startsLeft in [true, false] {
                let t = LanderTerrain.generate(level: level, seed: seed, startsLeft: startsLeft)
                XCTAssertEqual(t.width, LanderRules.worldWidth, accuracy: 1e-9)
                XCTAssertEqual(t.height(at: t.padStart), t.padHeight, accuracy: 1e-9)
                XCTAssertEqual(t.height(at: t.padCentre), t.padHeight, accuracy: 1e-9)
                XCTAssertEqual(t.height(at: t.padEnd), t.padHeight, accuracy: 1e-9)
                XCTAssertGreaterThanOrEqual(t.padWidth, 16)
                if startsLeft {
                    XCTAssertGreaterThan(t.padStart, t.width / 3 - 8)
                } else {
                    XCTAssertLessThan(t.padEnd, t.width * 2 / 3 + 8)
                }
                XCTAssertTrue(t.heights.allSatisfy { $0 >= LanderRules.groundFloor - 1e-9 && $0 <= LanderRules.groundCeiling + 1e-9 })
            }
        }
    }

    func testHeightInterpolatesAndClamps() {
        let t = LanderTerrain(heights: [0, 10, 30], step: 10, padStart: 0, padEnd: 10, padHeight: 0)
        XCTAssertEqual(t.height(at: 5), 5, accuracy: 1e-9)
        XCTAssertEqual(t.height(at: 15), 20, accuracy: 1e-9)
        XCTAssertEqual(t.height(at: -4), 0, accuracy: 1e-9)
        XCTAssertEqual(t.height(at: 99), 30, accuracy: 1e-9)
        XCTAssertEqual(t.highest(between: 12, and: 2), 14, accuracy: 1e-9)
    }

    // MARK: - Integration

    func testFreeFallFollowsGravity() {
        var flight = flatFlight(y: 300)
        flight.step(LanderInput(), dt: 2)   // capped at 0.25 s a call
        XCTAssertEqual(flight.elapsed, 0.25, accuracy: 1e-9)
        for _ in 0..<7 { flight.step(LanderInput(), dt: 0.25) }
        // v = g t; semi-implicit Euler at 1/120 s is within a hair of ½ g t².
        XCTAssertEqual(flight.craft.vy, -1.62 * 2, accuracy: 1e-6)
        XCTAssertEqual(300 - flight.craft.y, 0.5 * 1.62 * 4, accuracy: 0.03)
        XCTAssertEqual(flight.craft.fuel, 100)
    }

    func testFullThrustUprightClimbsAndBurnsFuel() {
        var flight = flatFlight(y: 200)
        for _ in 0..<4 { flight.step(LanderInput(targetAngle: 0, throttle: 1), dt: 0.25) }
        XCTAssertEqual(flight.craft.vy, (LanderRules.thrustAccel - 1.62) * 1, accuracy: 1e-6)
        XCTAssertEqual(flight.craft.fuel, 100 - LanderRules.burnRate, accuracy: 1e-6)
        XCTAssertEqual(flight.craft.vx, 0, accuracy: 1e-9)
    }

    func testTheCraftTurnsAtItsRateAndNoFurtherThanTheLimit() {
        var flight = flatFlight(y: 300)
        flight.step(LanderInput(targetAngle: 5, throttle: 0), dt: 0.25)
        XCTAssertEqual(flight.craft.angle, LanderRules.turnRate * 0.25, accuracy: 1e-9)
        for _ in 0..<8 { flight.step(LanderInput(targetAngle: 5, throttle: 0), dt: 0.25) }
        XCTAssertEqual(flight.craft.angle, LanderRules.maxTilt, accuracy: 1e-9)
    }

    func testLeaningRightPushesRight() {
        var flight = flatFlight(y: 300)
        flight.craft.angle = 0.4
        flight.step(LanderInput(targetAngle: 0.4, throttle: 1), dt: 0.25)
        XCTAssertGreaterThan(flight.craft.vx, 0)
    }

    func testAnEmptyTankGivesNoThrust() {
        var flight = flatFlight(y: 300, fuel: 0.01)
        for _ in 0..<4 { flight.step(LanderInput(targetAngle: 0, throttle: 1), dt: 0.25) }
        XCTAssertEqual(flight.craft.fuel, 0)
        XCTAssertEqual(flight.craft.burning, 0)
        XCTAssertLessThan(flight.craft.vy, 0)
    }

    func testTheSidesAndCeilingHoldTheCraftIn() {
        var flight = flatFlight(x: 10, y: 300)
        flight.craft.vx = -20
        flight.craft.vy = 50
        flight.step(LanderInput(), dt: 0.25)
        XCTAssertEqual(flight.craft.x, LanderRules.sideMargin, accuracy: 1e-9)
        XCTAssertEqual(flight.craft.vx, 0)
        flight.craft.y = LanderRules.ceiling - 0.1
        flight.craft.vy = 30
        flight.step(LanderInput(), dt: 0.1)
        XCTAssertLessThanOrEqual(flight.craft.y, LanderRules.ceiling)
    }

    // MARK: - Verdicts

    func testVerdictRules() {
        XCTAssertNil(LanderRules.verdict(vx: 0.5, vy: -1.5, angle: 0.05, feetOnPad: true))
        XCTAssertEqual(LanderRules.verdict(vx: 0, vy: -1, angle: 0, feetOnPad: false), .offPad)
        XCTAssertEqual(LanderRules.verdict(vx: 0, vy: -1, angle: 0.3, feetOnPad: true), .tilted)
        XCTAssertEqual(LanderRules.verdict(vx: 0, vy: -3, angle: 0, feetOnPad: true), .tooFast)
        XCTAssertEqual(LanderRules.verdict(vx: 2, vy: -1, angle: 0, feetOnPad: true), .sliding)
        XCTAssertFalse(LanderCrash.tooFast.sentence.isEmpty)
    }

    private func touchdown(_ flight: inout LanderFlight, vx: Double = 0, vy: Double, angle: Double = 0) {
        flight.craft.vx = vx
        flight.craft.vy = vy
        flight.craft.angle = angle
        for _ in 0..<200 where !flight.outcome.isOver {
            flight.step(LanderInput(targetAngle: angle, throttle: 0), dt: 1.0 / 60)
        }
    }

    func testASoftLandingOnThePadScores() throws {
        var flight = flatFlight(y: 52.3)
        touchdown(&flight, vy: -0.6)
        guard case .landed(let landing) = flight.outcome else { return XCTFail("expected a landing, got \(flight.outcome)") }
        XCTAssertTrue(landing.gentle)
        XCTAssertEqual(landing.offset, 0, accuracy: 0.01)
        XCTAssertEqual(landing.points, LanderRules.points(level: 1, fuelLeft: 100, offset: landing.offset,
                                                          padHalfWidth: 24, gentle: true))
        XCTAssertEqual(landing.points, 100 + 200 + 30 + 50)
        // The craft rests on the ground, stopped.
        XCTAssertEqual(flight.craft.y - LanderRules.footDrop, 50, accuracy: 1e-6)
        XCTAssertEqual(flight.craft.speed, 0)
        // Nothing moves after the end.
        let after = flight
        flight.step(LanderInput(targetAngle: 0, throttle: 1), dt: 0.25)
        XCTAssertEqual(flight, after)
    }

    func testAHardLandingCrashes() {
        var flight = flatFlight(y: 54)
        touchdown(&flight, vy: -4)
        XCTAssertEqual(flight.outcome, .crashed(.tooFast))
    }

    func testLandingOffThePadCrashes() {
        var flight = flatFlight(x: 100, y: 52.5)
        touchdown(&flight, vy: -0.5)
        XCTAssertEqual(flight.outcome, .crashed(.offPad))
    }

    func testOneFootOverTheEdgeIsOffThePad() {
        var flight = flatFlight(x: 264.5, y: 52.5)
        touchdown(&flight, vy: -0.5)
        XCTAssertEqual(flight.outcome, .crashed(.offPad))
    }

    func testSlidingAndLeaningCrash() {
        var sliding = flatFlight(y: 52.5)
        touchdown(&sliding, vx: 3, vy: -0.5)
        XCTAssertEqual(sliding.outcome, .crashed(.sliding))
        var leaning = flatFlight(y: 53.5)
        touchdown(&leaning, vy: -0.5, angle: 0.4)
        XCTAssertEqual(leaning.outcome, .crashed(.tilted))
    }

    func testPointsRewardFuelPrecisionAndLevel() {
        let centre = LanderRules.points(level: 1, fuelLeft: 10, offset: 0, padHalfWidth: 20, gentle: false)
        let edge = LanderRules.points(level: 1, fuelLeft: 10, offset: 20, padHalfWidth: 20, gentle: false)
        let later = LanderRules.points(level: 3, fuelLeft: 10, offset: 0, padHalfWidth: 20, gentle: false)
        XCTAssertEqual(centre - edge, 30)
        XCTAssertEqual(later - centre, 200)
        XCTAssertGreaterThan(LanderRules.points(level: 1, fuelLeft: 50, offset: 0, padHalfWidth: 20, gentle: false), centre)
    }

    // MARK: - A run

    func testARunAddsLandingsAndEndsOnACrash() {
        var run = LanderRun(seed: 4)
        XCTAssertEqual(run.level, 1)
        fly(&run)
        guard case .landed(let first) = run.flight.outcome else { return XCTFail("the autopilot should land level 1") }
        XCTAssertEqual(run.score, first.points)
        XCTAssertEqual(run.landings, 1)
        run.nextLevel()
        XCTAssertEqual(run.level, 2)
        XCTAssertEqual(run.flight.outcome, .flying)
        // Straight down at full lean: a crash, and the run is over.
        while !run.flight.outcome.isOver { run.step(LanderInput(targetAngle: 0.6, throttle: 0), dt: 0.25) }
        XCTAssertTrue(run.isOver)
        XCTAssertEqual(run.score, first.points)
        run.nextLevel()
        XCTAssertEqual(run.level, 2, "no next level after a crash")
    }

    private func fly(_ run: inout LanderRun, seconds: Double = 240) {
        var t = 0.0
        while !run.flight.outcome.isOver && t < seconds {
            run.step(LanderAutopilot.input(for: run.flight), dt: 1.0 / 60)
            t += 1.0 / 60
        }
    }

    /// The autopilot lands every level a long run reaches, on many grounds —
    /// so no level is unwinnable with the fuel it gives.
    func testTheAutopilotLandsEveryLevel() {
        for seed in UInt64(1)...12 {
            for level in [1, 2, 3, 4, 6, 8, 10, 14] {
                var flight = LanderFlight(level: .make(level), seed: seed &* 31 &+ UInt64(level))
                var t = 0.0
                while !flight.outcome.isOver && t < 300 {
                    flight.step(LanderAutopilot.input(for: flight), dt: 1.0 / 60)
                    t += 1.0 / 60
                }
                guard case .landed(let landing) = flight.outcome else {
                    XCTFail("seed \(seed) level \(level): \(flight.outcome) at x \(flight.craft.x) fuel \(flight.craft.fuel) after \(t)s")
                    continue
                }
                XCTAssertGreaterThan(landing.fuelLeft, 0, "seed \(seed) level \(level)")
            }
        }
    }
}
