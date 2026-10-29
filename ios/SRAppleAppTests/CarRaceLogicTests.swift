import XCTest
@testable import SRAppleApp

final class CarRaceLogicTests: XCTestCase {
    /// A long straight "track": a thin loop, so the tests know where the walls are.
    private let straight = CarTrack(id: "test", name: "Test", line: "", width: 20,
                                    control: [(0, 0), (250, 0), (500, 0), (750, 0), (1000, 0), (1000, 400), (500, 400), (0, 400)])

    // MARK: - Tracks

    func testEveryTrackIsAClosedLoopThatNeverCrossesItself() {
        for track in CarTrack.all {
            XCTAssertGreaterThan(track.length, 300, track.id)
            XCTAssertEqual(track.points.count, track.distances.count)
            // Points far apart round the track must be far apart on the ground
            // too, or the walls of two stretches would overlap.
            let n = track.points.count
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let round = abs(track.distances[j] - track.distances[i])
                    let apart = min(round, track.length - round)
                    guard apart > track.width * 3 else { continue }
                    let gap = (track.points[i] - track.points[j]).length
                    XCTAssertGreaterThan(gap, track.width * 1.4, "\(track.id): points \(i) and \(j) are \(gap) m apart")
                }
            }
            XCTAssertEqual(CarTrack.named(track.id), track)
        }
        XCTAssertNil(CarTrack.named("nowhere"))
    }

    func testEightTracksEachNamedOnce() {
        XCTAssertEqual(CarTrack.all.map(\.id), ["paddock", "riverside", "quarry", "harbour", "forest", "canyon", "alpine", "city"])
        XCTAssertEqual(Set(CarTrack.all.map(\.id)).count, CarTrack.all.count)
        XCTAssertTrue(CarTrack.nearby.allSatisfy { CarTrack.all.contains($0) })
    }

    func testSceneryStandsBesideTheRoadNeverOnIt() {
        for track in CarTrack.all {
            if track.scenery == .meadow {
                XCTAssertTrue(track.props.isEmpty, track.id)
                continue
            }
            XCTAssertGreaterThan(track.props.count, 40, track.id)
            for prop in track.props {
                let footprint = track.scenery == .city ? prop.size * 1.42 : prop.size
                let off = abs(track.spot(of: prop.at).offset)
                XCTAssertGreaterThan(off - footprint, track.width / 2 + track.verge - 1e-9, "\(track.id) prop at \(prop.at)")
            }
        }
        XCTAssertEqual(Set(CarTrack.all.map(\.scenery)).count, CarScenery.allCases.count, "every scenery has a track")
        // Seeded by the id: the same on every phone and every race, and another id lays it out differently.
        let control: [(Double, Double)] = [(0, 0), (90, 0), (180, 0), (225, 45), (180, 95), (90, 95), (0, 95), (-45, 45)]
        let a = CarTrack(id: "woods", name: "A", line: "", width: 16, scenery: .forest, control: control)
        let b = CarTrack(id: "woods", name: "B", line: "", width: 16, scenery: .forest, control: control)
        let c = CarTrack(id: "other", name: "C", line: "", width: 16, scenery: .forest, control: control)
        XCTAssertEqual(a.props, b.props)
        XCTAssertNotEqual(a.props, c.props)
    }

    func testPointAtWrapsAndSpotFindsItAgain() {
        let track = CarTrack.riverside
        for d in stride(from: 0.0, to: track.length, by: 37) {
            let p = track.point(at: d)
            let spot = track.spot(of: p.at)
            XCTAssertEqual(spot.offset, 0, accuracy: 0.01)
            XCTAssertEqual(spot.distance, d, accuracy: 0.05)
        }
        XCTAssertEqual(track.point(at: track.length + 10).at, track.point(at: 10).at)
        XCTAssertEqual(track.point(at: -10).at.x, track.point(at: track.length - 10).at.x, accuracy: 1e-6)
    }

    func testSpotOffsetIsPositiveToTheRight() {
        // Along the top straight the track runs right (+x); right is +y in a y-down world.
        let spot = straight.spot(of: CarVec(x: 500, y: 5))
        XCTAssertEqual(spot.offset, 5, accuracy: 1e-6)
        XCTAssertEqual(spot.direction, 0, accuracy: 1e-6)
        XCTAssertEqual(straight.spot(of: CarVec(x: 500, y: -3)).offset, -3, accuracy: 1e-6)
    }

    func testTheGridIsBehindTheLineAndOnTheTrack() {
        for track in CarTrack.all {
            for slot in 0..<4 {
                let g = track.grid(slot)
                let spot = track.spot(of: g.at)
                XCTAssertLessThan(abs(spot.offset), track.width / 2 - CarPhysics.halfWidth, "\(track.id) slot \(slot)")
                XCTAssertGreaterThan(spot.distance, track.length / 2, "behind the line: \(track.id) slot \(slot)")
            }
            XCTAssertNotEqual(track.grid(0).at, track.grid(1).at)
        }
    }

    // MARK: - Physics

    func testThrottleAcceleratesTowardsATopSpeed() {
        var car = CarState(x: 300, y: 0, heading: 0)
        for _ in 0..<4 { CarPhysics.step(&car, input: CarInput(throttle: 1), track: straight, dt: 0.25) }
        XCTAssertEqual(car.speed, 14, accuracy: 1.5)
        XCTAssertEqual(car.vy, 0, accuracy: 1e-9)
        var fast = CarState(x: 300, y: 0, heading: 0)
        fast.vx = 60
        CarPhysics.step(&fast, input: CarInput(throttle: 1), track: straight, dt: 0.25)
        XCTAssertLessThan(fast.speed, 60, "drag beats the engine above the top speed")
    }

    func testBrakingStopsAndThenReverses() {
        var car = CarState(x: 300, y: 0, heading: 0)
        car.vx = 20
        for _ in 0..<5 { CarPhysics.step(&car, input: CarInput(throttle: -1), track: straight, dt: 0.25) }
        XCTAssertLessThan(car.forwardSpeed, 0.5)
        for _ in 0..<8 { CarPhysics.step(&car, input: CarInput(throttle: -1), track: straight, dt: 0.25) }
        XCTAssertLessThan(car.forwardSpeed, -1)
    }

    func testSteeringRightTurnsClockwiseAndNotAtAStandstill() {
        var parked = CarState(x: 300, y: 0, heading: 0)
        CarPhysics.step(&parked, input: CarInput(throttle: 0, steer: 1), track: straight, dt: 0.25)
        XCTAssertEqual(parked.heading, 0)
        var car = CarState(x: 300, y: 0, heading: 0)
        car.vx = 15
        CarPhysics.step(&car, input: CarInput(throttle: 0, steer: 1), track: straight, dt: 0.1)
        XCTAssertGreaterThan(car.heading, 0)
        XCTAssertGreaterThan(car.vy, 0, "turning right in a y-down world moves down the screen")
    }

    func testGripPullsTheVelocityRoundAndAHardTurnDrifts() {
        var car = CarState(x: 300, y: 0, heading: 0)
        car.vx = 12
        car.heading = 0.3   // pointing off the way it is moving: sideways speed ~3.5
        for _ in 0..<2 { CarPhysics.step(&car, input: CarInput(), track: straight, dt: 0.25) }
        let slip = abs(car.velocity.dot(CarVec(x: -sin(car.heading), y: cos(car.heading))))
        XCTAssertLessThan(slip, 0.1, "grip kills a small slide quickly")
        XCTAssertFalse(car.drifting)

        var fast = CarState(x: 300, y: 0, heading: 1.0)
        fast.vx = 35   // sideways ~29: the tyres let go
        CarPhysics.step(&fast, input: CarInput(), track: straight, dt: 1.0 / 60)
        XCTAssertTrue(fast.drifting)
    }

    func testTheWallPutsTheCarBackAndBouncesIt() {
        var car = CarState(x: 300, y: 8.5, heading: .pi / 2)
        car.vy = 10   // straight into the right-hand wall (y = 10)
        let hit = CarPhysics.step(&car, input: CarInput(), track: straight, dt: 0.2)
        XCTAssertNotNil(hit)
        XCTAssertGreaterThan(hit?.impact ?? 0, 5)
        XCTAssertLessThanOrEqual(car.y, 10 - CarPhysics.halfWidth + 1e-6)
        XCTAssertLessThanOrEqual(car.vy, 0, "bounced back off the wall")
        // Within the walls: no hit.
        var free = CarState(x: 300, y: 0, heading: 0)
        free.vx = 20
        XCTAssertNil(CarPhysics.step(&free, input: CarInput(throttle: 1), track: straight, dt: 0.2))
    }

    func testBoostIsFasterWhileTheTankLasts() {
        var plain = CarState(x: 100, y: 0, heading: 0)
        var boosted = CarState(x: 100, y: 0, heading: 0)
        for _ in 0..<8 {
            CarPhysics.step(&plain, input: CarInput(throttle: 1), track: straight, dt: 0.25)
            CarPhysics.step(&boosted, input: CarInput(throttle: 1, boost: true), track: straight, dt: 0.25)
        }
        // Two seconds in: the boosted car is well ahead and its tank nearly dry.
        XCTAssertGreaterThan(boosted.speed, plain.speed + 10)
        XCTAssertEqual(boosted.boost, 1 - 2 / CarPhysics.boostBurn, accuracy: 0.01)
        XCTAssertEqual(plain.boost, 1, "a full tank stays full")
        XCTAssertTrue(boosted.boosting)
        // Held on with the tank dry: no more thrust, and no refill while held.
        for _ in 0..<4 { CarPhysics.step(&boosted, input: CarInput(throttle: 1, boost: true), track: straight, dt: 0.25) }
        XCTAssertEqual(boosted.boost, 0)
        XCTAssertFalse(boosted.boosting)
        // Let go: it refills, driving.
        CarPhysics.step(&boosted, input: CarInput(throttle: 1), track: straight, dt: 0.25)
        XCTAssertEqual(boosted.boost, 0.25 / CarPhysics.boostRefill, accuracy: 1e-6)
        // Never past the safe top speed the nearby rules check finish times against.
        var flatOut = CarState(x: 0, y: 0, heading: 0)
        flatOut.vx = 40
        for _ in 0..<40 {
            flatOut.boost = 1
            CarPhysics.step(&flatOut, input: CarInput(throttle: 1, boost: true), track: straight, dt: 0.25)
            flatOut.x = 100
        }
        // (`CarRaceNearbyRules.fastest`, 60 m/s, is a whole race's average.)
        XCTAssertLessThan(flatOut.speed, 50)
    }

    func testBrakingNeverBoostsAndADriftRefillsFaster() {
        var car = CarState(x: 300, y: 0, heading: 0)
        car.vx = 20
        CarPhysics.step(&car, input: CarInput(throttle: -1, boost: true), track: straight, dt: 0.1)
        XCTAssertFalse(car.boosting)
        XCTAssertEqual(car.boost, 1)

        var gripping = CarState(x: 300, y: 0, heading: 0)
        gripping.vx = 20
        gripping.boost = 0
        CarPhysics.step(&gripping, input: CarInput(throttle: 1), track: straight, dt: 1.0 / 60)
        var sliding = CarState(x: 300, y: 0, heading: 1.0)
        sliding.vx = 35
        sliding.boost = 0
        CarPhysics.step(&sliding, input: CarInput(throttle: 1), track: straight, dt: 1.0 / 60)
        CarPhysics.step(&sliding, input: CarInput(throttle: 1), track: straight, dt: 1.0 / 60)
        XCTAssertTrue(sliding.drifting)
        XCTAssertGreaterThan(sliding.boost, gripping.boost * 2.5)
    }

    // MARK: - Car against car

    func testCirclesPushTheFirstOutOfTheSecond() {
        let hit = CarCollision.circles(CarVec(x: 1.5, y: 0), 1, CarVec(x: 0, y: 0), 1)
        XCTAssertEqual(hit?.normal.x ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(hit?.depth ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertNil(CarCollision.circles(CarVec(x: 2.5, y: 0), 1, .zero, 1))
        // Dead on top of each other: still a way out.
        XCTAssertEqual(CarCollision.circles(.zero, 1, .zero, 1)?.depth ?? 0, 2, accuracy: 1e-9)
    }

    func testABoxIsPushedAwayFromACircleOnEverySide() {
        // A box pointing right, 2.2 either way long and 1.1 wide.
        func hit(_ x: Double, _ y: Double) -> CarContact? {
            CarCollision.box(at: .zero, heading: 0, halfLength: 2.2, halfWidth: 1.1, circle: CarVec(x: x, y: y), radius: 1)
        }
        // Circle ahead of the nose: the box goes back.
        let nose = hit(3, 0)
        XCTAssertEqual(nose?.normal.x ?? 0, -1, accuracy: 1e-9)
        XCTAssertEqual(nose?.depth ?? 0, 0.2, accuracy: 1e-9)
        // Circle off the right-hand side (+y): the box goes left.
        let side = hit(0, 1.8)
        XCTAssertEqual(side?.normal.y ?? 0, -1, accuracy: 1e-9)
        XCTAssertEqual(side?.depth ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertNil(hit(3.3, 0))
        XCTAssertNil(hit(0, 2.2))
        // Off a corner, the push is along the line from the corner.
        let corner = hit(2.2 + 0.5, 1.1 + 0.5)
        XCTAssertEqual(corner?.normal.x ?? 0, -(0.5).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(corner?.normal.y ?? 0, -(0.5).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(corner?.depth ?? 0, 1 - 0.5 * 2.0.squareRoot(), accuracy: 1e-9)
        // A centre inside the box: out by the nearest side.
        let inside = hit(0.3, 0.9)
        XCTAssertEqual(inside?.normal.y ?? 0, -1, accuracy: 1e-9)
        XCTAssertEqual(inside?.depth ?? 0, 0.2 + 1, accuracy: 1e-9)
        // The box turned round: its frame turns with it.
        let turned = CarCollision.box(at: .zero, heading: .pi / 2, halfLength: 2.2, halfWidth: 1.1,
                                      circle: CarVec(x: 0, y: 3), radius: 1)
        XCTAssertEqual(turned?.normal.y ?? 0, -1, accuracy: 1e-9)
        XCTAssertEqual(turned?.depth ?? 0, 0.2, accuracy: 1e-9)
    }

    func testCarsTouchNoseToTailAndSideBySideButNotApart() {
        let me = CarBody(at: CarVec(x: 0, y: 0), heading: 0)
        // Nose to tail, 4 m apart (cars are 4.4 long): touching.
        let tail = CarCollision.contact(me, CarBody(at: CarVec(x: 4, y: 0), heading: 0))
        XCTAssertEqual(tail?.normal.x ?? 0, -1, accuracy: 1e-9)
        XCTAssertEqual(tail?.depth ?? 0, 0.4, accuracy: 1e-9)
        // Side by side, 2 m apart (cars are 2.2 wide).
        let side = CarCollision.contact(me, CarBody(at: CarVec(x: 0, y: 2), heading: 0))
        XCTAssertEqual(side?.normal.y ?? 0, -1, accuracy: 1e-9)
        XCTAssertEqual(side?.depth ?? 0, 0.2, accuracy: 1e-9)
        XCTAssertNil(CarCollision.contact(me, CarBody(at: CarVec(x: 4.5, y: 0), heading: 0)))
        XCTAssertNil(CarCollision.contact(me, CarBody(at: CarVec(x: 0, y: 2.3), heading: 0)))
        XCTAssertNil(CarCollision.contact(me, CarBody(at: CarVec(x: 40, y: 0), heading: 0)))
        // Each car sees the other: the pushes are opposite.
        let mine = CarCollision.contact(me, CarBody(at: CarVec(x: 3, y: 1), heading: 0.3))
        let theirs = CarCollision.contact(CarBody(at: CarVec(x: 3, y: 1), heading: 0.3), me)
        XCTAssertNotNil(mine)
        XCTAssertNotNil(theirs)
        XCTAssertLessThan(mine!.normal.dot(theirs!.normal), 0)
    }

    func testABounceOnlyComesWhileClosingAndConservesMomentum() {
        let n = CarVec(x: -1, y: 0)   // they are ahead of me (+x): I am pushed back
        let mine = CarVec(x: 20, y: 0), theirs = CarVec(x: 10, y: 0)
        let bump = CarCollision.bounce(mine, off: theirs, normal: n)
        XCTAssertEqual(bump?.impact ?? 0, 10, accuracy: 1e-9)
        XCTAssertEqual(bump?.kick.x ?? 0, -(1 + CarCollision.restitution) * 10 / 2, accuracy: 1e-9)
        // Their half, from their side, is the same kick the other way.
        let back = CarCollision.bounce(theirs, off: mine, normal: n * -1)
        XCTAssertEqual((bump!.kick + back!.kick).length, 0, accuracy: 1e-9)
        // After both halves they are moving apart at restitution times the closing speed.
        let after = (mine + bump!.kick) - (theirs + back!.kick)
        XCTAssertEqual(after.x, -10 * CarCollision.restitution, accuracy: 1e-9)
        // Already moving apart: no bounce.
        XCTAssertNil(CarCollision.bounce(theirs, off: mine, normal: n))
    }

    func testTwoCarsOnOnePhoneArePushedApartAndBounced() {
        var a = CarState(x: 300, y: 0, heading: 0)
        a.vx = 25
        var b = CarState(x: 303.5, y: 0, heading: 0)
        b.vx = 15
        let momentum = a.vx + b.vx
        let bump = CarCollision.pair(&a, &b)
        XCTAssertNotNil(bump)
        XCTAssertEqual(a.vx + b.vx, momentum, accuracy: 1e-9)
        XCTAssertLessThan(a.vx, b.vx, "rear-ended: the car in front comes away faster")
        XCTAssertNil(CarCollision.contact(a.body, b.body), "pushed clear")
        XCTAssertNil(CarCollision.pair(&a, &b))
    }

    /// Each phone takes its own half against what it knows of the other car,
    /// and the two halves together are the one-phone answer.
    func testEachPhoneTakesItsOwnHalfAndTheHalvesAgree() {
        var a = CarState(x: 300, y: 0, heading: 0)
        a.vx = 25
        var b = CarState(x: 303.5, y: 0.4, heading: 0.1)
        b.vx = 15
        var together = (a, b)
        CarCollision.pair(&together.0, &together.1)

        var onA = a, onB = b
        var clockA = CarBumpClock(), clockB = CarBumpClock()
        XCTAssertNotNil(CarCollision.collide(&onA, with: [(id: "b", body: b.body)], clock: &clockA, at: 1))
        XCTAssertNotNil(CarCollision.collide(&onB, with: [(id: "a", body: a.body)], clock: &clockB, at: 1))
        XCTAssertEqual(onA.vx + onB.vx, a.vx + b.vx, accuracy: 0.6, "momentum near enough kept")
        XCTAssertLessThan(onA.vx, a.vx)
        XCTAssertGreaterThan(onB.vx, b.vx)
        XCTAssertEqual(onA.vx, together.0.vx, accuracy: 0.6)
        XCTAssertEqual(onB.vx, together.1.vx, accuracy: 0.6)
    }

    func testTheCooldownStopsASecondBounceOffTheSameCar() {
        var me = CarState(x: 300, y: 0, heading: 0)
        me.vx = 25
        let other = CarBody(at: CarVec(x: 303.5, y: 0), heading: 0, velocity: CarVec(x: 10, y: 0))
        var clock = CarBumpClock()
        XCTAssertNotNil(CarCollision.collide(&me, with: [(id: "b", body: other)], clock: &clock, at: 2))
        // Still overlapping a stale report and, say, still closing: pushed out, not bounced again.
        var again = CarState(x: 300.2, y: 0, heading: 0)
        again.vx = 25
        XCTAssertNil(CarCollision.collide(&again, with: [(id: "b", body: other)], clock: &clock, at: 2.1))
        XCTAssertEqual(again.vx, 25)
        XCTAssertLessThan(again.x, 300.2, "but still pushed out of the overlap")
        // Another car is its own cooldown; and after the cooldown, a fresh hit bounces.
        XCTAssertTrue(clock.ready("c", at: 2.1))
        var later = CarState(x: 300.2, y: 0, heading: 0)
        later.vx = 25
        XCTAssertNotNil(CarCollision.collide(&later, with: [(id: "b", body: other)], clock: &clock, at: 2.01 + CarCollision.cooldown))
    }

    /// Two phones over a laggy link, each knowing the other car only from
    /// reports eight times a second that arrive 0.15 s late: a rear-end
    /// still bounces both cars the right way, each once or twice, and never
    /// leaves them stuck together or knocks one through the other.
    func testALaggyRearEndBouncesBothPhonesFairly() {
        var a = CarState(x: 300, y: 0, heading: 0)
        a.vx = 30
        var b = CarState(x: 316, y: 0, heading: 0)
        b.vx = 12
        var seenOnA = CarGhost(trackId: "test", laps: 1, name: "B")
        var seenOnB = CarGhost(trackId: "test", laps: 1, name: "A")
        var inFlight: [(arrives: Double, toA: Bool, sample: CarGhost.Sample)] = []
        var clockA = CarBumpClock(), clockB = CarBumpClock()
        var bouncesA = 0, bouncesB = 0
        let dt = 1.0 / 60
        var t = 0.0, lastSend = -1.0
        var aSlowed = false, bSped = false
        while t < 3 {
            t += dt
            CarPhysics.step(&a, input: CarInput(throttle: 1), track: straight, dt: dt)
            CarPhysics.step(&b, input: CarInput(throttle: 1), track: straight, dt: dt)
            if t - lastSend >= 0.125 {
                lastSend = t
                inFlight.append((arrives: t + 0.15, toA: false, sample: CarGhost.Sample(t: t, x: a.x, y: a.y, heading: a.heading)))
                inFlight.append((arrives: t + 0.15, toA: true, sample: CarGhost.Sample(t: t, x: b.x, y: b.y, heading: b.heading)))
            }
            for message in inFlight where message.arrives <= t {
                if message.toA { seenOnA.append(message.sample) } else { seenOnB.append(message.sample) }
            }
            inFlight.removeAll { $0.arrives <= t }
            let beforeA = a.vx, beforeB = b.vx
            if let body = seenOnA.predict(at: t), CarCollision.collide(&a, with: [(id: "b", body: body)], clock: &clockA, at: t) != nil {
                bouncesA += 1
                if a.vx < beforeA { aSlowed = true }
            }
            if let body = seenOnB.predict(at: t), CarCollision.collide(&b, with: [(id: "a", body: body)], clock: &clockB, at: t) != nil {
                bouncesB += 1
                if b.vx > beforeB { bSped = true }
            }
        }
        XCTAssertTrue(aSlowed, "the car behind is knocked back")
        XCTAssertTrue(bSped, "the car in front is knocked on")
        XCTAssertGreaterThanOrEqual(bouncesA, 1)
        XCTAssertGreaterThanOrEqual(bouncesB, 1)
        XCTAssertLessThanOrEqual(bouncesA, 3, "no bouncing again and again off one knock")
        XCTAssertLessThanOrEqual(bouncesB, 3)
        XCTAssertNil(CarCollision.contact(a.body, b.body), "not left stuck together")
        XCTAssertGreaterThan(b.x, a.x, "nobody was knocked through the other")
    }

    // MARK: - Laps

    func testLapsCountOnlyForwardDistance() {
        var laps = CarLapCounter(length: 1000, laps: 2, startDistance: 994)
        XCTAssertEqual(laps.lap, 1)
        laps.update(distance: 2, time: 0.5)      // over the line from the grid: not a lap
        XCTAssertEqual(laps.splits, [])
        laps.update(distance: 500, time: 20)
        laps.update(distance: 999, time: 40)
        laps.update(distance: 3, time: 41)
        XCTAssertEqual(laps.splits, [41])
        XCTAssertEqual(laps.lap, 2)
        // Back over the line and forward again does not count twice.
        laps.update(distance: 998, time: 42)
        laps.update(distance: 4, time: 43)
        XCTAssertEqual(laps.splits, [41])
        laps.update(distance: 500, time: 60)
        laps.update(distance: 999, time: 79)
        laps.update(distance: 1, time: 80)
        XCTAssertTrue(laps.finished)
        XCTAssertEqual(laps.finishTime, 80)
        XCTAssertEqual(laps.lapTimes, [41, 39])
        XCTAssertEqual(laps.bestLap, 39)
        XCTAssertEqual(laps.progress, 1)
        laps.update(distance: 600, time: 90)
        XCTAssertEqual(laps.splits.count, 2, "nothing counts after the finish")
    }

    func testDrivingBackwardsNeverMakesALap() {
        var laps = CarLapCounter(length: 400, laps: 1, startDistance: 10)
        var d = 10.0, t = 0.0
        for _ in 0..<100 {
            d -= 10
            if d < 0 { d += 400 }
            t += 1
            laps.update(distance: d, time: t)
        }
        XCTAssertFalse(laps.finished)
        XCTAssertEqual(laps.progress, 0)
    }

    // MARK: - Ghosts

    func testAGhostRecordsTenTimesASecondAndInterpolates() {
        var ghost = CarGhost(trackId: "paddock", laps: 1, name: "Me")
        var car = CarState(x: 0, y: 0, heading: 0)
        for frame in 0...60 {
            car.x = Double(frame)
            ghost.record(car, raced: Double(frame), at: Double(frame) / 60)
        }
        XCTAssertEqual(ghost.samples.count, 11)
        let mid = ghost.pose(at: 0.25)
        XCTAssertEqual(mid?.at.x ?? 0, 15, accuracy: 0.6)
        XCTAssertEqual(ghost.pose(at: -1)?.at.x, 0)
        XCTAssertEqual(ghost.pose(at: 99)?.at.x, 60)
        XCTAssertNil(CarGhost(trackId: "x", laps: 1, name: "").pose(at: 0))
        // How far it had got, and when it got somewhere: the gap to a best.
        XCTAssertEqual(ghost.raced(at: 0.25) ?? 0, 15, accuracy: 0.6)
        XCTAssertEqual(ghost.time(atRaced: 30) ?? 0, 0.5, accuracy: 0.02)
        XCTAssertEqual(ghost.time(atRaced: -5), 0)
        XCTAssertNil(ghost.time(atRaced: 999))
    }

    func testHeardSamplesKeepOrderAndOnlyTheRecentPast() {
        var rival = CarGhost(trackId: "paddock", laps: 3, name: "Bo")
        rival.append(.init(t: 1, x: 10, y: 0, heading: 0))
        rival.append(.init(t: 0.5, x: 5, y: 0, heading: 0))
        rival.append(.init(t: 1.2, x: 12, y: 0, heading: 0))
        XCTAssertEqual(rival.samples.map(\.t), [1, 1.2])
        XCTAssertEqual(rival.pose(at: 1.1)?.at.x ?? 0, 11, accuracy: 1e-9)
        for i in 0..<300 { rival.append(.init(t: 2 + Double(i) * 0.1, x: 0, y: 0, heading: 0)) }
        XCTAssertEqual(rival.samples.count, 120)
    }

    func testAPredictionCarriesOnAtTheLastSpeedForAtMostTheHorizon() {
        var heard = CarGhost(trackId: "paddock", laps: 3, name: "Bo")
        XCTAssertNil(heard.predict(at: 0))
        heard.append(.init(t: 1, x: 10, y: 0, heading: 0))
        // One report: standing still where it was.
        XCTAssertEqual(heard.predict(at: 1.3)?.at, CarVec(x: 10, y: 0))
        XCTAssertEqual(heard.predict(at: 1.3)?.velocity, .zero)
        heard.append(.init(t: 1.1, x: 12, y: 0, heading: 0))
        let soon = heard.predict(at: 1.2)
        XCTAssertEqual(soon?.at.x ?? 0, 14, accuracy: 1e-9)
        XCTAssertEqual(soon?.velocity.x ?? 0, 20, accuracy: 1e-9)
        // No further than the horizon, however long the silence.
        let late = heard.predict(at: 9)
        XCTAssertEqual(late?.at.x ?? 0, 12 + 20 * CarCollision.horizon, accuracy: 1e-9)
        // Between reports it is simply where it was.
        XCTAssertEqual(heard.predict(at: 1.05)?.at.x ?? 0, 11, accuracy: 1e-9)
    }

    func testAPredictionKeepsTurning() {
        var heard = CarGhost(trackId: "paddock", laps: 3, name: "Bo")
        heard.append(.init(t: 0, x: 0, y: 0, heading: 0))
        heard.append(.init(t: 0.1, x: 2, y: 0, heading: 0.1))
        let next = heard.predict(at: 0.2)
        XCTAssertEqual(next?.heading ?? 0, 0.2, accuracy: 1e-9)
        XCTAssertGreaterThan(next?.at.y ?? 0, 0, "turning right in a y-down world moves down the screen")
        XCTAssertGreaterThan(next?.velocity.y ?? 0, 0)
        XCTAssertEqual(next?.velocity.length ?? 0, 20, accuracy: 1e-9)
    }

    func testAGhostTurnsTheShortWayRound() {
        var ghost = CarGhost(trackId: "paddock", laps: 1, name: "Me")
        ghost.record(CarState(x: 0, y: 0, heading: 3.1), at: 0)
        ghost.record(CarState(x: 0, y: 0, heading: -3.1), at: 0.1)
        let heading = ghost.pose(at: 0.05)?.heading ?? 0
        XCTAssertEqual(abs(heading), .pi, accuracy: 0.01)
    }

    // MARK: - The autopilot

    /// The demo's driver gets round every track, both laps, without living on the wall.
    func testTheAutopilotFinishesEveryTrack() {
        for track in CarTrack.all {
            let start = track.grid(0)
            var car = CarState(x: start.at.x, y: start.at.y, heading: start.heading)
            var laps = CarLapCounter(length: track.length, laps: 2, startDistance: track.spot(of: start.at).distance)
            var t = 0.0, hits = 0
            let dt = 1.0 / 60
            while !laps.finished && t < 240 {
                if CarPhysics.step(&car, input: CarAutopilot.input(for: car, on: track), track: track, dt: dt) != nil { hits += 1 }
                t += dt
                laps.update(distance: track.spot(of: car.position).distance, time: t)
            }
            XCTAssertTrue(laps.finished, "\(track.id): \(laps.progress) after \(t)s")
            XCTAssertLessThan(hits, 60, "\(track.id): \(hits) frames on the wall")
            if let time = laps.finishTime {
                // A lap at an honest average speed: not crawling, not teleporting.
                let average = track.length * 2 / time
                XCTAssertGreaterThan(average, 12, track.id)
                XCTAssertLessThan(average, 42, track.id)
            }
        }
    }

    // MARK: - Tables

    func testRankingPutsFinishersFirstFastestFirst() {
        let ranked = CarRaceEntry.ranked([
            CarRaceEntry(id: "a", name: "A", time: nil, bestLap: nil),
            CarRaceEntry(id: "b", name: "B", time: 70, bestLap: 33),
            CarRaceEntry(id: "c", name: "C", time: 65, bestLap: 31),
            CarRaceEntry(id: "d", name: "D", time: nil, bestLap: nil),
        ])
        XCTAssertEqual(ranked.map(\.id), ["c", "b", "a", "d"])
    }

    func testTimesFormat() {
        XCTAssertEqual(CarRaceFormat.time(48.2), "48.20")
        XCTAssertEqual(CarRaceFormat.time(62.375), "1:02.38")
        XCTAssertEqual(CarRaceFormat.time(0), "0.00")
        XCTAssertEqual(CarRaceFormat.time(-3), "0.00")
    }
}
