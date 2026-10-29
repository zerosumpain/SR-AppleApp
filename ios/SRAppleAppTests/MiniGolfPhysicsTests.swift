import XCTest
@testable import SRAppleApp

/// Mini Golf's ball: the cup, walls, sand, water, slopes, bumpers and
/// windmills, and a fuzz of random putts that must never leave the felt.
final class MiniGolfPhysicsTests: XCTestCase {
    /// A plain open hole, long enough that nothing near the cup is a wall.
    private let open = MiniGolfHole(
        number: 99, name: "Test", tip: "", par: 3,
        tee: MiniGolfVec(12, 70), cup: MiniGolfVec(12, 40),
        boundary: MiniGolfGeo.frame(0, 0, 24, 80))

    private func power(forSpeed speed: Double) -> Double {
        (speed - MiniGolfRules.minShot) / (MiniGolfRules.maxShot - MiniGolfRules.minShot)
    }

    /// Roll a shot to its end, collecting every event.
    private func run(_ sim: inout MiniGolfBallSim) -> [MiniGolfEvent] {
        var all: [MiniGolfEvent] = []
        var guardSteps = 0
        while sim.state == .rolling && guardSteps < 20_000 {
            sim.step(events: &all)
            guardSteps += 1
        }
        return all
    }

    // MARK: - The cup

    func testSlowBallOverTheCupDrops() {
        var sim = MiniGolfBallSim(hole: open, at: MiniGolfVec(12, 46))
        sim.putt(angle: -.pi / 2, power: power(forSpeed: 20))
        let events = run(&sim)
        XCTAssertEqual(sim.state, .holed)
        XCTAssertEqual(sim.position, open.cup)
        XCTAssertTrue(events.contains(.holed))
        XCTAssertFalse(events.contains { if case .lipOut = $0 { return true } else { return false } })
    }

    func testFastBallLipsOut() {
        var sim = MiniGolfBallSim(hole: open, at: MiniGolfVec(12, 50))
        sim.putt(angle: -.pi / 2, power: power(forSpeed: 50))
        var events: [MiniGolfEvent] = []
        // Step until the ball is well past the cup.
        var steps = 0
        while sim.state == .rolling && sim.position.y > open.cup.y - 6 && steps < 5_000 {
            sim.step(events: &events)
            steps += 1
        }
        XCTAssertEqual(sim.state, .rolling, "a fast ball must not drop")
        XCTAssertLessThan(sim.position.y, open.cup.y - 5)
        XCTAssertTrue(events.contains { if case .lipOut = $0 { return true } else { return false } })
        XCTAssertGreaterThan(sim.speed, MiniGolfRules.lipSpeed, "it carries on past at speed")
    }

    func testSlowBallGrazingTheRimCurlsIn() {
        // Off-centre by more than the drop depth, but slow: the rim pulls it in.
        var sim = MiniGolfBallSim(hole: open, at: MiniGolfVec(13.4, 46))
        sim.putt(angle: -.pi / 2, power: power(forSpeed: 19))
        _ = run(&sim)
        XCTAssertEqual(sim.state, .holed)
    }

    func testBallWideOfTheCupRollsBy() {
        var sim = MiniGolfBallSim(hole: open, at: MiniGolfVec(16, 46))
        sim.putt(angle: -.pi / 2, power: power(forSpeed: 20))
        _ = run(&sim)
        XCTAssertEqual(sim.state, .resting)
    }

    // MARK: - Walls, sand, water, slopes

    func testWallBouncesBackSlowerAndNeverThrough() {
        var sim = MiniGolfBallSim(hole: open, at: MiniGolfVec(6, 20))
        sim.putt(angle: .pi, power: 1) // straight at the left wall
        var events: [MiniGolfEvent] = []
        var bounced = false
        for _ in 0..<600 {
            sim.step(events: &events)
            XCTAssertGreaterThanOrEqual(sim.position.x, MiniGolfRules.wallContact - 1e-6)
            if sim.velocity.x > 0 { bounced = true; break }
        }
        XCTAssertTrue(bounced)
        XCTAssertLessThan(sim.velocity.x, MiniGolfRules.maxShot * MiniGolfRules.wallRestitution)
        XCTAssertTrue(events.contains { if case .wall = $0 { return true } else { return false } })
    }

    func testSandStopsABallSooner() {
        let sandy = MiniGolfHole(number: 98, name: "Sand", tip: "", par: 3,
                                 tee: MiniGolfVec(12, 70), cup: MiniGolfVec(12, 4),
                                 boundary: MiniGolfGeo.frame(0, 0, 24, 80),
                                 sand: [MiniGolfGeo.rect(0, 30, 24, 30)])
        var plain = MiniGolfBallSim(hole: open, at: MiniGolfVec(4, 62))
        var sand = MiniGolfBallSim(hole: sandy, at: MiniGolfVec(4, 62))
        plain.putt(angle: -.pi / 2, power: 0.5)
        sand.putt(angle: -.pi / 2, power: 0.5)
        _ = run(&plain)
        let events = run(&sand)
        XCTAssertGreaterThan(sand.position.y, plain.position.y + 10, "the bunker stops it well short")
        XCTAssertTrue(events.contains { if case .sand = $0 { return true } else { return false } })
    }

    func testWaterSplashesAndGoesBackToTheLastSpot() {
        let hole = MiniGolfCourse.pond
        var sim = MiniGolfBallSim(hole: hole)
        sim.putt(angle: -.pi / 2 - 0.3, power: 0.6) // up and left of the bridge
        let events = run(&sim)
        XCTAssertEqual(sim.state, .splashed)
        XCTAssertTrue(events.contains { if case .splash = $0 { return true } else { return false } })
        sim.returnToLastSpot()
        XCTAssertEqual(sim.state, .resting)
        XCTAssertEqual(sim.position, hole.tee)
    }

    func testBridgeKeepsTheBallDry() {
        let hole = MiniGolfCourse.tightrope
        var sim = MiniGolfBallSim(hole: hole)
        sim.putt(angle: -.pi / 2, power: 1) // straight along the bridge
        _ = run(&sim)
        XCTAssertNotEqual(sim.state, .splashed)
        XCTAssertLessThan(sim.position.y, 24, "it crossed the water")
    }

    func testSoftPuttUpTheRampRollsBack() {
        let hole = MiniGolfCourse.ramp
        var sim = MiniGolfBallSim(hole: hole)
        sim.putt(angle: -.pi / 2, power: 0.6)
        var highest = sim.position.y
        var events: [MiniGolfEvent] = []
        while sim.state == .rolling {
            sim.step(events: &events)
            highest = min(highest, sim.position.y)
        }
        XCTAssertLessThan(highest, 38, "it got onto the ramp")
        XCTAssertGreaterThan(sim.position.y, 38, "and rolled back off the bottom")
    }

    func testGentleSlopeCurvesTheBall() {
        let hole = MiniGolfCourse.camber
        var sim = MiniGolfBallSim(hole: hole, at: MiniGolfVec(8, 50))
        sim.putt(angle: -.pi / 2, power: 0.5)
        _ = run(&sim)
        XCTAssertGreaterThan(sim.position.x, 9, "the camber pushed it right")
    }

    func testBumperGivesBackMoreThanItTakes() {
        let hole = MiniGolfHole(number: 97, name: "Bumper", tip: "", par: 3,
                                tee: MiniGolfVec(12, 70), cup: MiniGolfVec(20, 6),
                                boundary: MiniGolfGeo.frame(0, 0, 24, 80),
                                posts: [MiniGolfPost(MiniGolfVec(12, 30), 2, .bumper)])
        var sim = MiniGolfBallSim(hole: hole, at: MiniGolfVec(12, 40))
        sim.putt(angle: -.pi / 2, power: power(forSpeed: 30))
        var events: [MiniGolfEvent] = []
        var into = 0.0
        for _ in 0..<600 {
            let before = sim.velocity.y
            sim.step(events: &events)
            if sim.velocity.y > 0 { into = -before; break }
        }
        XCTAssertGreaterThan(into, 0)
        XCTAssertGreaterThan(sim.velocity.y, into, "it comes off faster than it went in")
        XCTAssertTrue(events.contains { if case .bumper(let index, _, _) = $0 { return index == 0 } else { return false } })
    }

    func testWindmillSailHitsABallInItsPath() {
        let hole = MiniGolfCourse.windmill
        guard let mill = hole.windmills.first else { return XCTFail("no windmill") }
        // Roll slowly through the sweep, beside the hub: a sail must strike it.
        var hit = false
        for start in stride(from: 0.0, to: 6.0, by: 0.5) {
            var sim = MiniGolfBallSim(hole: hole, at: MiniGolfVec(mill.pivot.x - 4.5, mill.pivot.y + 9), clock: start)
            sim.putt(angle: -.pi / 2, power: 0.25)
            var events: [MiniGolfEvent] = []
            _ = sim.finishShot(events: &events)
            if events.contains(where: { if case .sail = $0 { return true } else { return false } }) { hit = true }
        }
        XCTAssertTrue(hit)
    }

    func testBallNeverRestsInsideAWindmillSweep() {
        for hole in MiniGolfCourse.holes where !hole.windmills.isEmpty {
            var rng = MiniGolfTestRandom(seed: UInt64(hole.number))
            for _ in 0..<40 {
                var sim = MiniGolfBallSim(hole: hole, clock: rng.next(in: 0...20))
                sim.putt(angle: rng.next(in: 0...(2 * .pi)), power: rng.next(in: 0...1))
                var events: [MiniGolfEvent] = []
                _ = sim.finishShot(events: &events)
                if sim.state == .resting { XCTAssertFalse(hole.inSweep(sim.position), "hole \(hole.number)") }
            }
        }
    }

    // MARK: - Steps and rest

    func testFrameRateDoesNotChangeTheShot() {
        let hole = MiniGolfCourse.bumperBounce
        var at60 = MiniGolfBallSim(hole: hole)
        var at120 = MiniGolfBallSim(hole: hole)
        at60.putt(angle: -.pi / 2 + 0.2, power: 0.8)
        at120.putt(angle: -.pi / 2 + 0.2, power: 0.8)
        var events: [MiniGolfEvent] = []
        // 1/48 s and 1/96 s are whole numbers of 1/240 s steps, so both phones step identically.
        for _ in 0..<240 { at60.advance(1.0 / 48, events: &events) }
        for _ in 0..<480 { at120.advance(1.0 / 96, events: &events) }
        XCTAssertEqual(at60.position.x, at120.position.x, accuracy: 1e-9)
        XCTAssertEqual(at60.position.y, at120.position.y, accuracy: 1e-9)
    }

    func testEveryShotComesToRest() {
        var rng = MiniGolfTestRandom(seed: 42)
        for hole in MiniGolfCourse.holes {
            for _ in 0..<25 {
                var sim = MiniGolfBallSim(hole: hole, clock: rng.next(in: 0...10))
                sim.putt(angle: rng.next(in: 0...(2 * .pi)), power: rng.next(in: 0...1))
                var events: [MiniGolfEvent] = []
                let steps = sim.finishShot(events: &events)
                XCTAssertNotEqual(sim.state, .rolling)
                XCTAssertFalse(sim.forcedStop, "hole \(hole.number) needed stopping by hand")
                XCTAssertLessThan(Double(steps) * MiniGolfRules.step, 20, "hole \(hole.number) rolled for ever")
            }
        }
    }

    /// 500 random putts, played on from wherever each stops: the ball is on
    /// the felt after every single step, and never needed putting back.
    func testFuzzedPuttsNeverLeaveTheHole() {
        var rng = MiniGolfTestRandom(seed: 2026)
        var shots = 0
        var events: [MiniGolfEvent] = []
        while shots < 500 {
            let hole = MiniGolfCourse.holes[Int(rng.next(in: 0...17.999))]
            var sim = MiniGolfBallSim(hole: hole, clock: rng.next(in: 0...30))
            for _ in 0..<4 where shots < 500 {
                sim.putt(angle: rng.next(in: 0...(2 * .pi)), power: rng.next(in: 0...1))
                shots += 1
                while sim.state == .rolling {
                    sim.step(events: &events)
                    events.removeAll(keepingCapacity: true)
                    if !hole.isOpen(sim.position) {
                        return XCTFail("hole \(hole.number): ball off the felt at \(sim.position)")
                    }
                }
                XCTAssertEqual(sim.rescues, 0, "hole \(hole.number)")
                if sim.state == .splashed { sim.returnToLastSpot() }
                if sim.state == .holed { break }
            }
        }
    }
}

/// A small seeded generator, so a failing fuzz fails the same way twice.
struct MiniGolfTestRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

    mutating func nextBits() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(nextBits() >> 11) / Double(1 << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}
