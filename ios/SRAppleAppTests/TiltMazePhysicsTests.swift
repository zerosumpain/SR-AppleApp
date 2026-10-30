import XCTest
@testable import SRAppleApp

/// Tilt Maze's marble: it never leaves the board or passes through a wall
/// however the phone is shaken, it drops down a hole it rolls over, comes
/// back at the last flag, sinks into the cup, and every level can be
/// finished by a steady hand obeying the same physics.
final class TiltMazePhysicsTests: XCTestCase {
    private let frame = 1.0 / 60

    /// Roll `run` for `seconds` at a fixed tilt, collecting what happened.
    private func roll(_ run: inout TiltMazeRun, tilt: TiltMazeVector, seconds: Double) -> [TiltMazeEvents] {
        var all: [TiltMazeEvents] = []
        var t = 0.0
        while t < seconds {
            all.append(run.advance(tilt: tilt, dt: frame))
            t += frame
        }
        return all
    }

    // MARK: - Walls and the board

    func testTheMarbleStaysOnTheBoardAndOutOfTheWallsInAFuzz() {
        var rng = TiltMazeRandom(seed: 2026)
        let levels = [1, 3, 6, 9, 10, 17, 28, 40].map { TiltMazeCatalogue.level($0) }
            + [TiltMazeCatalogue.endless(depth: 12, seed: 5)]
        let r = TiltMazeRules.radius
        for (index, level) in levels.enumerated() {
            var ball = TiltMazeBall(at: level.start.centre)
            var tilt = TiltMazeVector.zero
            var cell = level.cell(under: ball.position)
            for step in 0..<(120 * 30) {
                // A new shake every quarter second, some of it far past the limit.
                if step % 30 == 0 {
                    tilt = TiltMazeVector(x: (rng.unit() - 0.5) * 3, y: (rng.unit() - 0.5) * 3)
                }
                TiltMazePhysics.step(&ball, tilt: tilt, level: level, dt: TiltMazeRules.step)
                XCTAssertTrue(ball.x >= r && ball.x <= level.width - r, "maze \(index): off the side at step \(step)")
                XCTAssertTrue(ball.y >= r && ball.y <= level.height - r, "maze \(index): off the end at step \(step)")
                XCTAssertLessThanOrEqual(ball.speed, TiltMazeRules.maxSpeed * 1.5 + 1e-9)
                // Never deep inside a wall.
                let inside = level.boxes.contains { box in
                    ball.x > box.minX + 0.01 && ball.x < box.maxX - 0.01 && ball.y > box.minY + 0.01 && ball.y < box.maxY - 0.01
                }
                XCTAssertFalse(inside, "maze \(index): inside a wall at step \(step)")
                // Never through one: a new cell is always reached through open sides.
                let now = level.cell(under: ball.position)
                if now != cell {
                    let way = level.path(from: cell, to: now, avoidingHoles: false)
                    XCTAssertNotNil(way, "maze \(index): through a wall from \(cell) to \(now) at step \(step)")
                    XCTAssertLessThanOrEqual(way?.count ?? 99, 3, "maze \(index): jumped from \(cell) to \(now)")
                    cell = now
                }
            }
        }
    }

    func testTheMarbleBouncesOffAWallAndReportsTheKnock() {
        let level = TiltMazeCatalogue.level(1)
        var ball = TiltMazeBall(at: TiltMazeVector(x: 4.5, y: 0.5))
        ball.vx = 6
        var hardest = 0.0
        for _ in 0..<60 {
            hardest = max(hardest, TiltMazePhysics.step(&ball, tilt: .zero, level: level, dt: TiltMazeRules.step))
        }
        XCTAssertGreaterThan(hardest, 3, "a hard knock is reported")
        XCTAssertLessThan(ball.vx, 0, "and the marble comes back off the wall")
        XCTAssertLessThan(ball.x, 5 - TiltMazeRules.radius)
    }

    func testAGentleTiltRollsAndAHardOneIsCapped() {
        let level = TiltMazeCatalogue.level(3)
        var gentle = TiltMazeBall(at: TiltMazeVector(x: 0.5, y: 0.5))
        TiltMazePhysics.step(&gentle, tilt: TiltMazeVector(x: 0.1, y: 0), level: level, dt: 0.1)
        XCTAssertGreaterThan(gentle.vx, 0)
        var tiny = TiltMazeBall(at: TiltMazeVector(x: 0.5, y: 0.5))
        TiltMazePhysics.step(&tiny, tilt: TiltMazeVector(x: 0.005, y: 0), level: level, dt: 0.1)
        XCTAssertEqual(tiny.vx, 0, "inside the dead zone nothing moves")
        let capped = TiltMazePhysics.clampTilt(TiltMazeVector(x: 3, y: 4))
        XCTAssertEqual(capped.length, TiltMazeRules.maxTilt, accuracy: 1e-9)
        XCTAssertEqual(TiltMazePhysics.clampTilt(TiltMazeVector(x: .nan, y: 0)), .zero)
    }

    // MARK: - Holes, flags and the cup

    func testAMarbleOverAHoleDrops() throws {
        let level = TiltMazeCatalogue.level(3)
        let hole = try XCTUnwrap(level.holes.first)
        var run = TiltMazeRun(level: level, at: hole.centre)
        let events = run.advance(tilt: .zero, dt: frame)
        XCTAssertTrue(events.fell)
        XCTAssertEqual(run.falls, 1)
        guard case .falling(let into, _) = run.phase else { return XCTFail("not falling: \(run.phase)") }
        XCTAssertEqual(into, hole)
        XCTAssertFalse(run.steerable)
    }

    func testEveryHoleOnEveryLevelSwallowsAMarbleAtItsMiddle() {
        for n in [3, 6, 9, 20, 40] {
            let level = TiltMazeCatalogue.level(n)
            for hole in level.holes {
                var run = TiltMazeRun(level: level, at: hole.centre)
                XCTAssertTrue(run.advance(tilt: .zero, dt: frame).fell, "level \(n) hole \(hole)")
            }
        }
    }

    func testTheRimDrawsInAMarbleThatStopsNearIt() throws {
        let level = TiltMazeCatalogue.level(3)
        let hole = try XCTUnwrap(level.holes.first)
        var run = TiltMazeRun(level: level, at: TiltMazeVector(x: hole.centre.x + 0.4, y: hole.centre.y))
        let events = roll(&run, tilt: .zero, seconds: 2)
        XCTAssertTrue(events.contains { $0.fell }, "a marble resting on the rim slips in")
    }

    func testAFallComesBackToTheStartThenToTheLastFlag() throws {
        let level = TiltMazeCatalogue.level(5)
        let flag = try XCTUnwrap(level.checkpoints.first)
        let hole = try XCTUnwrap(level.holes.first)

        var run = TiltMazeRun(level: level, at: hole.centre)
        _ = roll(&run, tilt: .zero, seconds: TiltMazeRules.fallTime + TiltMazeRules.respawnTime + 0.1)
        XCTAssertEqual(run.phase, .rolling)
        XCTAssertEqual(run.ball.position, level.start.centre, "no flag yet: back to the start")

        var driven = TiltMazeRun(level: level, at: flag.centre)
        let first = driven.advance(tilt: .zero, dt: frame)
        XCTAssertEqual(first.checkpoint, flag)
        XCTAssertEqual(driven.respawn, flag)
        // Now steer from the flag into a hole further on.
        let below = try XCTUnwrap(level.holes.first { $0.y > flag.y })
        let way = try XCTUnwrap(level.path(from: flag, to: below, avoidingHoles: false))
        var fell = false
        for _ in 0..<(60 * 20) {
            let tilt = TiltMazeAutopilot.tilt(for: driven, path: way)
            if driven.advance(tilt: tilt, dt: frame).fell {
                fell = true
                break
            }
        }
        XCTAssertTrue(fell, "the autopilot can be steered into a hole")
        _ = roll(&driven, tilt: .zero, seconds: TiltMazeRules.fallTime + 0.05)
        XCTAssertEqual(driven.ball.position, flag.centre, "back at the flag, not the start")
    }

    func testTheCupCatchesTheMarbleAndStopsTheClock() {
        let level = TiltMazeCatalogue.level(1)
        var run = TiltMazeRun(level: level, at: TiltMazeVector(x: level.goal.centre.x - 0.1, y: level.goal.centre.y))
        // Get the clock going first.
        var started = TiltMazeRun(level: level)
        _ = roll(&started, tilt: TiltMazeVector(x: 0.3, y: 0), seconds: 0.5)
        XCTAssertGreaterThan(started.time, 0)

        let events = roll(&run, tilt: .zero, seconds: TiltMazeRules.sinkTime + 0.2)
        XCTAssertTrue(events.contains { $0.reachedGoal })
        XCTAssertTrue(events.contains { $0.cleared })
        XCTAssertTrue(run.isOver)
        let stopped = run.time
        _ = roll(&run, tilt: TiltMazeVector(x: 0.3, y: 0.3), seconds: 1)
        XCTAssertEqual(run.time, stopped, "the clock stays stopped")
    }

    func testTheClockWaitsForTheFirstRoll() {
        var run = TiltMazeRun(level: TiltMazeCatalogue.level(2))
        _ = roll(&run, tilt: .zero, seconds: 2)
        XCTAssertEqual(run.time, 0)
        XCTAssertEqual(run.phase, .ready)
        let events = roll(&run, tilt: TiltMazeVector(x: 0.3, y: 0), seconds: 1)
        XCTAssertTrue(events.contains { $0.started })
        XCTAssertGreaterThan(run.time, 0.5)
    }

    func testALongFrameStepsOnlyALittle() {
        var run = TiltMazeRun(level: TiltMazeCatalogue.level(2))
        _ = run.advance(tilt: TiltMazeVector(x: 0.3, y: 0), dt: 0.5)
        _ = run.advance(tilt: TiltMazeVector(x: 0.3, y: 0), dt: 30)
        XCTAssertLessThanOrEqual(run.time, TiltMazeRules.longestFrame * 2 + 1e-9)
    }

    // MARK: - Reading the tilt

    func testLeanIsZeroAtTheLevelHoldAndPlainWhenLevelledFlat() {
        let flat = TiltMazeLean.lean(gx: 0.2, gy: -0.1, gz: -0.97, levelX: 0, levelY: 0, levelZ: -1)
        XCTAssertEqual(flat.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(flat.y, 0.1, accuracy: 1e-9, "gravity up the screen is a roll down it")
        let held = TiltMazeLean.lean(gx: 0.1, gy: -0.7, gz: -0.7, levelX: 0.1, levelY: -0.7, levelZ: -0.7)
        XCTAssertEqual(held.x, 0, accuracy: 1e-9)
        XCTAssertEqual(held.y, 0, accuracy: 1e-9)
    }

    /// Held upright, a tip of the top edge away still rolls the marble up
    /// the screen as briskly as it would from flat.
    func testLeanFeelsTheSameHeldUpright() {
        let angle = 0.2
        let upright = TiltMazeLean.lean(gx: 0, gy: -cos(angle), gz: -sin(angle), levelX: 0, levelY: -1, levelZ: 0)
        XCTAssertEqual(upright.y, -sin(angle), accuracy: 1e-9)
        XCTAssertEqual(upright.x, 0, accuracy: 1e-9)
        let right = TiltMazeLean.lean(gx: sin(angle), gy: -cos(angle), gz: 0, levelX: 0, levelY: -1, levelZ: 0)
        XCTAssertEqual(right.x, sin(angle), accuracy: 1e-9)
        XCTAssertEqual(right.y, 0, accuracy: 1e-9)
        let fromFlat = TiltMazeLean.lean(gx: 0, gy: sin(angle), gz: -cos(angle), levelX: 0, levelY: 0, levelZ: -1)
        XCTAssertEqual(fromFlat.y, upright.y, accuracy: 1e-9)
    }

    func testLeanNeverReturnsNaN() {
        let cases: [(Double, Double, Double, Double, Double, Double)] = [
            (0, 0, 1, 0, 0, 1), (0, 0, 0, 0, 0, 0), (.nan, 0, 0, 0, 0, -1), (0.3, 0.2, -0.9, 0, 0, 0.999),
        ]
        for c in cases {
            let v = TiltMazeLean.lean(gx: c.0, gy: c.1, gz: c.2, levelX: c.3, levelY: c.4, levelZ: c.5)
            XCTAssertTrue(v.x.isFinite && v.y.isFinite, "\(c)")
        }
    }

    // MARK: - Every level can be finished

    /// Drive a level with the autopilot; nil if it never gets there.
    private func autopilot(_ level: TiltMazeLevel, limit: Double = 240) -> TiltMazeRun? {
        guard let path = level.solution else { return nil }
        var run = TiltMazeRun(level: level)
        var t = 0.0
        while t < limit && !run.isOver {
            _ = run.advance(tilt: TiltMazeAutopilot.tilt(for: run, path: path), dt: frame)
            t += frame
        }
        return run.isOver ? run : nil
    }

    func testTheAutopilotFinishesEveryCampaignLevelWithinTwoStars() {
        for n in 1...TiltMazeCatalogue.campaignCount {
            let level = TiltMazeCatalogue.level(n)
            let par = TiltMazePar.of(level)
            guard let run = autopilot(level) else {
                XCTFail("level \(n): the autopilot never reached the cup")
                continue
            }
            XCTAssertEqual(run.falls, 0, "level \(n): the autopilot fell \(run.falls) times")
            XCTAssertLessThanOrEqual(run.time, par.two, "level \(n): \(run.time)s against two stars at \(par.two)s")
        }
    }

    func testTheAutopilotFinishesEndlessMazes() {
        for seed in 1...12 {
            let level = TiltMazeCatalogue.endless(depth: seed * 2, seed: UInt64(seed) &* 31)
            let run = autopilot(level)
            XCTAssertNotNil(run, "endless seed \(seed)")
            XCTAssertEqual(run?.falls ?? -1, 0, "endless seed \(seed)")
        }
    }
}
