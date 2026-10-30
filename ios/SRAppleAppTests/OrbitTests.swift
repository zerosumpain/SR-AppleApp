import XCTest
@testable import SRAppleApp

/// Orbit's rules: the integrator keeps an orbit's energy, every level can be
/// done, crashes stop the probe, moons keep to their rails, and the stars,
/// bests and runs add up.
final class OrbitTests: XCTestCase {

    // MARK: - Helpers

    /// A bare level round one body, launching from a free station.
    private func level(bodies: [OrbitBody], pad: OrbitPad, target: OrbitTarget = OrbitKit.station(-500, -500, radius: 1),
                       stars: [OrbitVec] = [], belts: [OrbitBelt] = [], timeLimit: Double = 1_000) -> OrbitLevel {
        OrbitLevel(number: 1, name: "Test", hint: "", pad: pad, bodies: bodies, belts: belts, target: target,
                   stars: stars, par: 2, preview: 2, timeLimit: timeLimit, demo: OrbitShot(angle: 0, power: 0.5))
    }

    /// The shot that leaves a free pad at `speed`, heading `angle`.
    private func shot(angle: Double, speed: Double) -> OrbitShot {
        OrbitShot(angle: angle, power: (speed - OrbitPhysics.minSpeed) / (OrbitPhysics.maxSpeed - OrbitPhysics.minSpeed))
    }

    // MARK: - The integrator

    func testEnergyHoldsOnACircularOrbitForTenThousandSteps() {
        let mass = 2_400_000.0, r = 150.0
        let centre = OrbitVec(300, 450)
        let lv = level(bodies: [OrbitKit.planet("Sol", .rocky, centre.x, centre.y, radius: 20, mass: mass)],
                       pad: OrbitKit.launcher(centre.x + r, centre.y))
        let v = OrbitPhysics.circularSpeed(mass: mass, radius: r)
        XCTAssertGreaterThan(v, OrbitPhysics.minSpeed)
        XCTAssertLessThan(v, OrbitPhysics.maxSpeed)
        var flight = OrbitFlight(level: lv, shot: shot(angle: -Double.pi / 2, speed: v))
        let e0 = flight.energy
        var worst = 0.0
        for _ in 0..<10_000 {
            flight.step()
            XCTAssertTrue(flight.flying, "the probe should still be in orbit")
            worst = max(worst, abs(flight.energy - e0) / abs(e0))
            XCTAssertEqual(flight.position.distance(to: centre), r, accuracy: r * 0.02, "a circular orbit stays circular")
        }
        XCTAssertLessThan(worst, 0.01, "energy drift \(worst)")
    }

    func testEnergyHoldsOnAnEccentricOrbit() {
        let mass = 2_400_000.0, r = 130.0
        let centre = OrbitVec(300, 450)
        let lv = level(bodies: [OrbitKit.planet("Sol", .rocky, centre.x, centre.y, radius: 20, mass: mass)],
                       pad: OrbitKit.launcher(centre.x + r, centre.y))
        let v = OrbitPhysics.circularSpeed(mass: mass, radius: r) * 1.15
        var flight = OrbitFlight(level: lv, shot: shot(angle: -Double.pi / 2, speed: v))
        let e0 = flight.energy
        XCTAssertLessThan(e0, 0, "the orbit is bound")
        var worst = 0.0, nearest = Double.infinity, farthest = 0.0
        for _ in 0..<10_000 {
            flight.step()
            XCTAssertTrue(flight.flying)
            worst = max(worst, abs(flight.energy - e0) / abs(e0))
            let d = flight.position.distance(to: centre)
            nearest = min(nearest, d)
            farthest = max(farthest, d)
        }
        XCTAssertLessThan(worst, 0.01, "energy drift \(worst)")
        XCTAssertGreaterThan(farthest - nearest, 40, "an eccentric orbit swings in and out")
    }

    func testTheSameShotFliesTheSamePath() {
        let lv = OrbitLevels.level(12)
        let a = OrbitFlight.outcome(lv, shot: lv.demo)
        let b = OrbitFlight.outcome(lv, shot: lv.demo)
        XCTAssertEqual(a.position, b.position)
        XCTAssertEqual(a.steps, b.steps)
        XCTAssertEqual(a.end, b.end)
    }

    func testThePredictionIsTheStartOfTheFlight() {
        let lv = OrbitLevels.level(5)
        let prediction = OrbitFlight.predict(lv, shot: lv.demo, seconds: 1, every: 4)
        var flight = OrbitFlight(level: lv, shot: lv.demo)
        for _ in 0..<4 { flight.step() }
        XCTAssertEqual(prediction.points[1], flight.position)
        XCTAssertEqual(prediction.points.count, 1 + 240 / 4)
    }

    // MARK: - Every level can be done

    func testThereAreThirtyLevelsInThreeSystems() {
        XCTAssertEqual(OrbitLevels.all.count, 30)
        for (i, lv) in OrbitLevels.all.enumerated() {
            XCTAssertEqual(lv.number, i + 1)
            XCTAssertEqual(lv.system, OrbitSystem(rawValue: i / 10))
            XCTAssertFalse(lv.name.isEmpty)
            XCTAssertFalse(lv.hint.isEmpty)
            XCTAssertTrue((1...3).contains(lv.stars.count), "level \(lv.number) has 1 to 3 stars")
            XCTAssertTrue((1...OrbitPhysics.probes).contains(lv.par))
            XCTAssertTrue(OrbitField.shows(lv.pad.at), "level \(lv.number)'s pad is on the field")
            XCTAssertTrue(OrbitField.shows(lv.target.position(at: 0)), "level \(lv.number)'s target is on the field")
            for b in lv.bodies {
                XCTAssertGreaterThan(lv.pad.at.distance(to: b.position(at: 0)), b.radius + OrbitPhysics.probeRadius,
                                     "level \(lv.number)'s pad is clear of \(b.name)")
            }
        }
        XCTAssertEqual(Set(OrbitLevels.all.map(\.name)).count, 30, "every level has its own name")
    }

    func testTheAimingLineShrinksAsTheLevelsGetHarder() {
        let previews = OrbitLevels.all.map(\.preview)
        for i in 1..<previews.count {
            XCTAssertLessThanOrEqual(previews[i], previews[i - 1], "level \(i + 1) shows no more than level \(i)")
        }
        XCTAssertGreaterThan(previews[0], previews[29] * 2)
    }

    func testEveryDemoArrivesWithEveryStar() {
        for lv in OrbitLevels.all {
            let flight = OrbitFlight.outcome(lv, shot: lv.demo)
            XCTAssertEqual(flight.end, .arrived, "level \(lv.number)'s demo ends \(String(describing: flight.end))")
            XCTAssertFalse(flight.collected.contains(false), "level \(lv.number)'s demo misses a star")
            XCTAssertLessThan(flight.time, lv.timeLimit)
        }
    }

    /// A fresh search, not the demo: every direction the pad allows a degree
    /// apart, at every power two percent apart, until one launch arrives.
    /// It looks coarse to fine (4 degrees by 10%, then 2 by 5%, then the lot)
    /// so an easy level is answered quickly, and never flies a launch twice.
    func testEveryLevelIsSolvableByBruteForce() {
        for lv in OrbitLevels.all {
            let found = search(lv)
            XCTAssertNotNil(found, "no launch reaches the target on level \(lv.number)")
        }
    }

    private func search(_ lv: OrbitLevel) -> OrbitShot? {
        let degree = Double.pi / 180
        let any = lv.pad.arc >= Double.pi
        let low = any ? -180.0 : ((lv.pad.facing - lv.pad.arc) / degree).rounded(.up)
        let high = any ? 179.0 : (lv.pad.facing + lv.pad.arc) / degree
        var tried = Set<Int>()
        for (angleStep, powerStep) in [(4.0, 10), (2.0, 5), (1.0, 2)] {
            var a = low
            while a <= high {
                for p in stride(from: 0, through: 100, by: powerStep) {
                    let key = Int((a * 10).rounded()) * 1000 + p
                    guard tried.insert(key).inserted else { continue }
                    let shot = OrbitShot(angle: a * degree, power: Double(p) / 100)
                    if OrbitFlight.outcome(lv, shot: shot).end == .arrived { return shot }
                }
                a += angleStep
            }
        }
        return nil
    }

    // MARK: - Crashes

    func testFlyingIntoAPlanetStopsTheProbe() {
        let lv = level(bodies: [OrbitKit.planet("Rock", .rocky, 300, 300, radius: 40, mass: 500_000)],
                       pad: OrbitKit.launcher(300, 700))
        var flight = OrbitFlight(level: lv, shot: OrbitShot(angle: -Double.pi / 2, power: 0.6))
        flight.run()
        XCTAssertEqual(flight.end, .crashed(0))
        XCTAssertFalse(flight.flying)
        XCTAssertLessThanOrEqual(flight.position.distance(to: OrbitVec(300, 300)), 40 + OrbitPhysics.probeRadius + 0.01)
        let stopped = flight.position, steps = flight.steps
        let result = flight.step()
        XCTAssertEqual(result.end, .crashed(0))
        XCTAssertEqual(flight.position, stopped, "a crashed probe does not move")
        XCTAssertEqual(flight.steps, steps)
        XCTAssertEqual(flight.end?.sentence(in: lv), "Crashed into Rock.")
    }

    func testTheSunBurnsAndTheBlackHoleSwallows() {
        let sunLevel = level(bodies: [OrbitKit.sun(300, 300, radius: 40, mass: 500_000)], pad: OrbitKit.launcher(300, 700))
        XCTAssertEqual(OrbitFlight.outcome(sunLevel, shot: OrbitShot(angle: -Double.pi / 2, power: 0.5)).end, .burned(0))
        let holeLevel = level(bodies: [OrbitKit.hole(300, 300, horizon: 12, mass: 800_000)], pad: OrbitKit.launcher(300, 700))
        XCTAssertEqual(OrbitFlight.outcome(holeLevel, shot: OrbitShot(angle: -Double.pi / 2, power: 0.5)).end, .swallowed(0))
    }

    func testRocksAndTheEdgeAndTheBatteryEndAFlight() {
        let rocks = level(bodies: [], pad: OrbitKit.launcher(300, 700),
                          belts: [OrbitKit.belt(300, 450, inner: 100, outer: 130, from: 0, span: 360)])
        XCTAssertEqual(OrbitFlight.outcome(rocks, shot: OrbitShot(angle: -Double.pi / 2, power: 0.5)).end, .asteroids)
        let empty = level(bodies: [], pad: OrbitKit.launcher(300, 700))
        XCTAssertEqual(OrbitFlight.outcome(empty, shot: OrbitShot(angle: 0, power: 1)).end, .lost)
        let flat = level(bodies: [], pad: OrbitKit.launcher(300, 450), timeLimit: 0.5)
        XCTAssertEqual(OrbitFlight.outcome(flat, shot: OrbitShot(angle: 0, power: 0)).end, .flat)
    }

    func testABeltOnlyCoversItsSpan() {
        let belt = OrbitKit.belt(0, 0, inner: 100, outer: 120, from: 0, span: 90)
        XCTAssertTrue(belt.contains(OrbitVec(110 * cos(0.5), 110 * sin(0.5))))
        XCTAssertFalse(belt.contains(OrbitVec(110 * cos(2.0), 110 * sin(2.0))), "outside the span")
        XCTAssertFalse(belt.contains(OrbitVec(90, 10)), "inside the inner edge")
    }

    func testAPadOnAPlanetOnlyLaunchesAwayFromTheGround() {
        let bodies = [OrbitKit.planet("Home", .ocean, 300, 800, radius: 50, mass: 300_000)]
        let pad = OrbitKit.pad(on: bodies, 0, at: -90)
        XCTAssertEqual(pad.at.y, 800 - 50 - OrbitPhysics.padLift, accuracy: 1e-9)
        XCTAssertEqual(pad.clamp(Double.pi / 2), pad.facing + pad.arc, accuracy: 1e-9, "straight down is turned back to the edge")
        XCTAssertEqual(pad.clamp(-Double.pi / 2), -Double.pi / 2, accuracy: 1e-9)
        let free = OrbitKit.launcher(300, 300)
        XCTAssertEqual(free.clamp(2.5), 2.5, accuracy: 1e-9)
    }

    // MARK: - Moons on rails

    func testMoonsFollowTheirRails() throws {
        let moon = OrbitKit.moon("Luna", around: 300, 400, distance: 120, period: 8, phase: 90, radius: 10, mass: 1000)
        let rail = try XCTUnwrap(moon.rail)
        XCTAssertEqual(moon.position(at: 0).x, 300, accuracy: 1e-9)
        XCTAssertEqual(moon.position(at: 0).y, 520, accuracy: 1e-9, "90 degrees round is straight down the screen")
        for t in stride(from: 0.0, through: 20, by: 0.37) {
            XCTAssertEqual(moon.position(at: t).distance(to: OrbitVec(300, 400)), 120, accuracy: 1e-9)
            let later = moon.position(at: t + rail.period)
            XCTAssertEqual(later.x, moon.position(at: t).x, accuracy: 1e-6)
            XCTAssertEqual(later.y, moon.position(at: t).y, accuracy: 1e-6)
        }
        let back = OrbitKit.moon("Back", around: 300, 400, distance: 120, period: -8, phase: 90, radius: 10, mass: 1000)
        XCTAssertEqual(back.position(at: 2).x, 420, accuracy: 1e-6, "a negative period runs the other way")
        XCTAssertEqual(moon.position(at: 2).x, 180, accuracy: 1e-6)
    }

    func testAMoonIsWhereItsRailSaysWhateverTheProbeDoes() {
        let lv = OrbitLevels.all.first { $0.bodies.contains { $0.rail != nil } }!
        let index = lv.bodies.firstIndex { $0.rail != nil }!
        var a = OrbitFlight(level: lv, shot: lv.demo)
        var b = OrbitFlight(level: lv, shot: OrbitShot(angle: lv.pad.facing, power: 0.1))
        var n = 0
        while a.flying && b.flying && n < 200 {
            a.step()
            b.step()
            n += 1
        }
        XCTAssertGreaterThan(n, 10)
        let moon = lv.bodies[index]
        XCTAssertEqual(moon.position(at: a.time), moon.position(at: b.time))
        XCTAssertEqual(a.time, b.time, accuracy: 1e-12)
    }

    // MARK: - Stars and bests

    func testStarsForArrivingCollectingAndPar() {
        XCTAssertEqual(OrbitRating.stars(arrived: false, allStars: true, launches: 1, par: 2), 0)
        XCTAssertEqual(OrbitRating.stars(arrived: true, allStars: false, launches: 3, par: 2), 1)
        XCTAssertEqual(OrbitRating.stars(arrived: true, allStars: true, launches: 3, par: 2), 2)
        XCTAssertEqual(OrbitRating.stars(arrived: true, allStars: false, launches: 2, par: 2), 2)
        XCTAssertEqual(OrbitRating.stars(arrived: true, allStars: true, launches: 1, par: 2), 3)
    }

    func testStarsPickedUpOnAMissStayPickedUp() {
        let lv = OrbitLevels.level(1)
        var attempt = OrbitAttempt(level: lv)
        // A probe that grabs the first star and is then called off.
        var miss = OrbitFlight(level: lv, shot: lv.demo)
        while miss.flying && !miss.collected[0] { miss.step() }
        miss.abort()
        attempt.record(miss)
        XCTAssertEqual(attempt.launches, 1)
        XCTAssertEqual(attempt.starsCollected, 1)
        XCTAssertFalse(attempt.arrived)
        let hit = OrbitFlight.outcome(lv, shot: lv.demo)
        attempt.record(hit)
        XCTAssertTrue(attempt.arrived)
        XCTAssertTrue(attempt.allStars)
        XCTAssertEqual(attempt.rating, 3, "two launches is par on level 1")
    }

    func testRunningOutOfProbes() {
        let lv = OrbitLevels.level(1)
        var attempt = OrbitAttempt(level: lv)
        for _ in 0..<OrbitPhysics.probes {
            var f = OrbitFlight(level: lv, shot: OrbitShot(angle: Double.pi / 2, power: 1))
            f.run()
            attempt.record(f)
        }
        XCTAssertTrue(attempt.outOfProbes)
        XCTAssertEqual(attempt.probesLeft, 0)
        attempt.record(OrbitFlight.outcome(lv, shot: lv.demo))
        XCTAssertFalse(attempt.arrived, "no launches after the last probe")
    }

    func testProgressOpensLevelsInTurnAndKeepsTheBest() {
        var progress = OrbitProgress()
        XCTAssertTrue(progress.isOpen(1))
        XCTAssertFalse(progress.isOpen(2))
        XCTAssertEqual(progress.nextLevel(of: 30), 1)

        let lv = OrbitLevels.level(1)
        var slow = OrbitAttempt(level: lv)
        for _ in 0..<3 {
            var f = OrbitFlight(level: lv, shot: OrbitShot(angle: Double.pi / 2, power: 1))
            f.run()
            slow.record(f)
        }
        slow.record(OrbitFlight.outcome(lv, shot: lv.demo))
        XCTAssertEqual(slow.rating, 2)
        XCTAssertTrue(progress.record(slow))
        XCTAssertTrue(progress.isOpen(2))
        XCTAssertEqual(progress.nextLevel(of: 30), 2)

        var quick = OrbitAttempt(level: lv)
        quick.record(OrbitFlight.outcome(lv, shot: lv.demo))
        XCTAssertTrue(progress.record(quick), "three stars beats two")
        XCTAssertEqual(progress.best(1)?.stars, 3)
        XCTAssertEqual(progress.best(1)?.launches, 1)
        XCTAssertFalse(progress.record(slow), "a worse go is not a new best")
        XCTAssertEqual(progress.stars(1), 3)
        XCTAssertEqual(progress.totalStars, 3)
    }

    func testProgressIsSavedOnThePhone() throws {
        let suite = "orbit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OrbitStore(defaults: defaults)
        XCTAssertEqual(store.load(), OrbitProgress())
        var progress = OrbitProgress()
        var attempt = OrbitAttempt(level: OrbitLevels.level(1))
        attempt.record(OrbitFlight.outcome(OrbitLevels.level(1), shot: OrbitLevels.level(1).demo))
        progress.record(attempt)
        progress.noteLaunch()
        store.save(progress)
        XCTAssertEqual(store.load(), progress)
        XCTAssertTrue(OrbitStore.key.hasPrefix("orbit."))
    }

    // MARK: - A run on the screen

    func testARunLaunchesFliesAndComesBackToAim() {
        let lv = OrbitLevels.level(2)
        var run = OrbitRun(level: lv, aim: OrbitShot(angle: Double.pi / 2 + 0.3, power: 1))
        XCTAssertTrue(run.isAiming)
        XCTAssertFalse(run.prediction.points.isEmpty)
        XCTAssertTrue(run.launch())
        XCTAssertFalse(run.launch(), "one probe at a time")
        var ended: OrbitEnd?
        var frames = 0
        while ended == nil && frames < 60 * 60 {
            for event in run.advance(1.0 / 60) {
                if case .ended(let end) = event { ended = end }
            }
            frames += 1
        }
        XCTAssertNotNil(ended)
        XCTAssertNotEqual(ended, .arrived)
        XCTAssertEqual(run.attempt.launches, 1)
        XCTAssertEqual(run.attempt.probesLeft, OrbitPhysics.probes - 1)
        for _ in 0..<90 { _ = run.advance(1.0 / 60) }
        XCTAssertEqual(run.skyTime, 0, accuracy: 1e-9, "the sky winds back to the moment of launch")
        run.ready()
        XCTAssertTrue(run.isAiming)
        XCTAssertFalse(run.path.isEmpty, "the flight's path stays until the next launch")
        run.launch()
        XCTAssertFalse(run.lastPath.isEmpty, "the last flight is kept as a ghost")
    }

    func testARunFliesTheSameAtAnyFrameRate() {
        let lv = OrbitLevels.level(5)
        func fly(_ fps: Double) -> OrbitFlight? {
            var run = OrbitRun(level: lv, aim: lv.demo)
            run.launch()
            var n = 0
            while run.isFlying && n < 100_000 {
                _ = run.advance(1 / fps)
                n += 1
            }
            return run.flight
        }
        let sixty = fly(60), oneTwenty = fly(120)
        XCTAssertEqual(sixty?.end, .arrived)
        XCTAssertEqual(sixty?.end, oneTwenty?.end)
        XCTAssertEqual(sixty?.steps, oneTwenty?.steps)
    }

    func testTheAimStaysInsideThePad() {
        let lv = OrbitLevels.level(3)
        var run = OrbitRun(level: lv)
        run.setAim(OrbitShot(angle: Double.pi / 2, power: 2))
        XCTAssertEqual(run.aim.power, 1)
        XCTAssertLessThanOrEqual(abs(OrbitAngle.delta(run.aim.angle, from: lv.pad.facing)), lv.pad.arc + 1e-9)
        let before = run.aim.angle
        run.nudge(degrees: -1, power: -0.5)
        XCTAssertEqual(run.aim.power, 0.5, accuracy: 1e-9)
        XCTAssertEqual(OrbitAngle.delta(run.aim.angle, from: before), -Double.pi / 180, accuracy: 1e-9)
    }

    func testRestartGivesEveryProbeBack() {
        let lv = OrbitLevels.level(1)
        var run = OrbitRun(level: lv, aim: lv.demo)
        run.launch()
        _ = run.abort()
        XCTAssertEqual(run.attempt.launches, 1)
        run.restart()
        XCTAssertEqual(run.attempt.launches, 0)
        XCTAssertEqual(run.aim, OrbitShot(angle: lv.pad.clamp(lv.demo.angle), power: lv.demo.power))
        XCTAssertTrue(run.isAiming)
    }

    // MARK: - Drawing sums

    func testTheViewportFitsTheFieldAndMapsBothWays() throws {
        let view = OrbitViewport(width: 375, height: 600)
        XCTAssertEqual(view.scale, 0.625, accuracy: 1e-9)
        let p = OrbitVec(120, 640)
        let s = view.screen(p)
        let back = view.world(s.x, s.y)
        XCTAssertEqual(back.x, p.x, accuracy: 1e-9)
        XCTAssertEqual(back.y, p.y, accuracy: 1e-9)
        XCTAssertNil(view.edgeMarker(for: OrbitVec(300, 450), inset: 10))
        let marker = try XCTUnwrap(view.edgeMarker(for: OrbitVec(-200, 450), inset: 10))
        XCTAssertEqual(marker.x, 10)
    }

    func testSparksBurnOut() {
        var sparks = OrbitSparks()
        sparks.burst(at: .zero, count: 1000, speed: 100, life: 1, size: 2, tone: .fire)
        XCTAssertEqual(sparks.items.count, OrbitSparks.cap)
        for _ in 0..<70 { sparks.step(1.0 / 60) }
        XCTAssertTrue(sparks.isEmpty)
    }

    func testTheSkyIsTheSameEveryTime() {
        let lv = OrbitLevels.level(24)
        XCTAssertEqual(OrbitSkyLayout(level: lv), OrbitSkyLayout(level: lv))
        XCTAssertFalse(OrbitSkyLayout(level: lv).rocks.isEmpty)
        XCTAssertTrue(OrbitSkyLayout(level: OrbitLevels.level(1)).rocks.isEmpty)
    }
}
