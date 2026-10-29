import XCTest
@testable import SRAppleApp

/// Car Racer+ screen logic: skid marks and puffs, the chase camera, the
/// controls, the scenery, and the words the screens show.
final class CarProPresentationTests: XCTestCase {
    // MARK: - Effects

    /// A time trial's one car, sliding hard on tarmac at 20 m/s.
    private func slidingRacers() -> [CarProRacer] {
        let player = CarProEntrant.player(setup: CarProCarSetup(model: .hatch))
        let session = CarProSession(config: .timeTrial(track: "brackenfield", player: player, assists: .full, ghost: nil))
        var racers = session.racers
        racers[0].vehicle.forwardSpeed = 20
        for w in 0..<4 {
            racers[0].vehicle.wheels[w].combinedSlip = 2.4
            racers[0].vehicle.wheels[w].surface = .tarmac
        }
        return racers
    }

    func testSlidingTyresLayMarksAndSmokeThatFade() {
        var effects = CarProEffects()
        var racers = slidingRacers()
        var time = 0.0
        for step in 0..<40 {
            for w in 0..<4 {
                racers[0].vehicle.wheels[w].position = CarProVec(x: Double(step) * 1.0, y: Double(w) * 1.5)
            }
            time += 1.0 / 20
            effects.update(racers: racers, time: time, dt: 1.0 / 20)
        }
        XCTAssertGreaterThan(effects.skids.count, 40, "each tyre lays rubber as it slides")
        XCTAssertTrue(effects.skids.allSatisfy { !$0.loose && $0.strength > 0.2 })
        XCTAssertGreaterThan(effects.particles.count, 10, "and smokes")
        XCTAssertTrue(effects.particles.allSatisfy { $0.kind == .smoke })
        let near = effects.visibleSkids(at: time, near: CarProVec(x: 20, y: 0), reach: 100)
        XCTAssertEqual(near.count, effects.skids.count)
        // Long after, the marks have faded and the smoke has cleared.
        XCTAssertTrue(effects.visibleSkids(at: time + CarProEffects.skidLife + 1, near: .zero, reach: 1000).isEmpty)
        for w in 0..<4 { racers[0].vehicle.wheels[w].combinedSlip = 0 }
        effects.update(racers: racers, time: time + 5, dt: 1.0 / 60)
        XCTAssertTrue(effects.particles.isEmpty)
    }

    func testGrippingTyresLeaveNothingAndAJumpDrawsNoLine() {
        var effects = CarProEffects()
        var racers = slidingRacers()
        for w in 0..<4 { racers[0].vehicle.wheels[w].combinedSlip = 0.6 }
        for step in 0..<20 {
            for w in 0..<4 { racers[0].vehicle.wheels[w].position = CarProVec(x: Double(step), y: 0) }
            effects.update(racers: racers, time: Double(step) / 20, dt: 1.0 / 20)
        }
        XCTAssertTrue(effects.skids.isEmpty)
        XCTAssertTrue(effects.particles.isEmpty)
        // Sliding again, then put back by a wall 30 m away: no mark across the gap.
        racers = slidingRacers()
        for w in 0..<4 { racers[0].vehicle.wheels[w].position = .zero }
        effects.update(racers: racers, time: 2, dt: 1.0 / 20)
        for w in 0..<4 { racers[0].vehicle.wheels[w].position = CarProVec(x: 30, y: 0) }
        effects.update(racers: racers, time: 2.05, dt: 1.0 / 20)
        XCTAssertTrue(effects.skids.isEmpty)
    }

    func testEffectsStayBoundedAndLooseGroundThrowsDust() {
        var effects = CarProEffects()
        var racers = slidingRacers()
        for w in 0..<4 { racers[0].vehicle.wheels[w].surface = .gravel }
        var time = 0.0
        for step in 0..<4000 {
            for w in 0..<4 { racers[0].vehicle.wheels[w].position = CarProVec(x: Double(step % 3000), y: Double(w)) }
            time += 1.0 / 60
            effects.update(racers: racers, time: time, dt: 1.0 / 60)
        }
        XCTAssertLessThanOrEqual(effects.skids.count, CarProEffects.skidCapacity)
        XCTAssertLessThanOrEqual(effects.particles.count, CarProEffects.particleCapacity)
        XCTAssertTrue(effects.skids.allSatisfy(\.loose), "ruts, not rubber")
        XCTAssertTrue(effects.particles.contains { $0.kind == .dust })
        effects.sparks(at: .zero, impact: 8, time: time)
        XCTAssertTrue(effects.particles.contains { $0.kind == .spark })
        effects.reset()
        XCTAssertTrue(effects.skids.isEmpty && effects.particles.isEmpty)
    }

    // MARK: - Camera

    func testCameraTurnsWithTheCarAndPullsBackWithSpeed() {
        let params = CarProCarSetup(model: .gt).params
        var car = CarProVehicle(params: params, position: CarProVec(x: 10, y: 20), heading: 0)
        var camera = CarProCamera(vehicle: car)
        XCTAssertEqual(camera.span, CarProCamera.nearSpan, accuracy: 0.01)
        car.heading = 1.0
        car.forwardSpeed = 70
        for _ in 0..<600 { camera.follow(car, dt: 1.0 / 60) }
        XCTAssertEqual(camera.heading, 1.0, accuracy: 0.01)
        XCTAssertGreaterThan(camera.span, 100)
        XCTAssertLessThanOrEqual(camera.span, CarProCamera.farSpan)
        // The car sits at the anchor, and the road ahead of it is up the screen.
        let here = camera.screen(car.position, width: 390, height: 800, anchor: 0.7)
        XCTAssertEqual(here.x, 195, accuracy: 1e-6)
        XCTAssertEqual(here.y, 560, accuracy: 1e-6)
        let ahead = camera.screen(car.position + CarProVec.heading(1.0) * 10, width: 390, height: 800, anchor: 0.7)
        XCTAssertEqual(ahead.x, 195, accuracy: 1e-6)
        XCTAssertLessThan(ahead.y, 560)
        let right = camera.screen(car.position + CarProVec.heading(1.0).right * 10, width: 390, height: 800, anchor: 0.7)
        XCTAssertGreaterThan(right.x, 195, "the car's right is the screen's right")
        camera.bump(10)
        XCTAssertGreaterThan(camera.shake, 0.5)
        for _ in 0..<120 { camera.follow(car, dt: 1.0 / 60) }
        XCTAssertLessThan(camera.shake, 0.01)
    }

    // MARK: - Controls

    func testPedalsReadPressHeightAndSteeringMapsToLock() {
        XCTAssertEqual(CarProControlMath.pedal(touchY: 200, height: 200), 0.15, accuracy: 1e-9)
        XCTAssertEqual(CarProControlMath.pedal(touchY: 0, height: 200), 1, accuracy: 1e-9)
        XCTAssertEqual(CarProControlMath.pedal(touchY: 60, height: 200), 1, accuracy: 1e-9, "the top third is full")
        let mid = CarProControlMath.pedal(touchY: 140, height: 200)
        XCTAssertGreaterThan(mid, 0.3)
        XCTAssertLessThan(mid, 0.7)
        XCTAssertEqual(CarProControlMath.pedal(touchY: 500, height: 200), 0.15, accuracy: 1e-9)

        XCTAssertEqual(CarProControlMath.tilt(0.01), 0)
        XCTAssertEqual(CarProControlMath.tilt(0.3), 1, accuracy: 1e-9)
        XCTAssertEqual(CarProControlMath.tilt(-0.3), -1, accuracy: 1e-9)
        XCTAssertGreaterThan(CarProControlMath.tilt(0.1), 0)
        XCTAssertLessThan(CarProControlMath.tilt(0.1), 0.5, "fine near the middle")

        XCTAssertEqual(CarProControlMath.wheel(turn: CarProControlMath.wheelLock), 1, accuracy: 1e-9)
        XCTAssertEqual(CarProControlMath.wheel(turn: -4), -1, accuracy: 1e-9)
        XCTAssertEqual(CarProControlMath.angleChange(from: 3.0, to: -3.0), 2 * .pi - 6, accuracy: 1e-9,
                       "a drag across the bottom of the wheel is a small turn, not a whole one")
        XCTAssertEqual(CarProControlMath.slider(offset: 0, width: 200), 0)
        XCTAssertEqual(CarProControlMath.slider(offset: 200, width: 200), 1)
        XCTAssertEqual(CarProControlMath.slider(offset: -42, width: 200), -0.5, accuracy: 1e-9)
        var v = 0.0
        for _ in 0..<60 { v = CarProControlMath.ease(v, to: 1, rate: 10, dt: 1.0 / 60) }
        XCTAssertGreaterThan(v, 0.99)
    }

    // MARK: - Scenery

    func testSceneryStandsClearOfEveryCircuitAndIsTheSameEachTime() {
        for track in CarProCircuits.all {
            let props = CarProScenery.props(for: track)
            XCTAssertGreaterThan(props.count, 25, "\(track.id) has scenery")
            for prop in props {
                XCTAssertGreaterThan(CarProScenery.clearance(prop.position, track: track), 0.5,
                                     "\(track.id): a \(prop.kind) stands on the circuit")
            }
            XCTAssertEqual(props, CarProScenery.props(for: track))
            if track.theme.isNight {
                XCTAssertGreaterThan(props.filter { $0.kind == .floodlight }.count, 10, "floodlights after dark")
            }
        }
        let street = CarProCircuits.track("old-town")!
        XCTAssertTrue(CarProScenery.props(for: street).contains { $0.kind == .building })
    }

    // MARK: - Words

    func testBannersSayWhatHappenedToThePlayerOnly() {
        let sector = CarProPresent.banner(for: .sector(racer: 0, sector: 1, time: 21.5, delta: -0.25), player: 0,
                                          kind: .timeTrial, laps: 0)
        XCTAssertEqual(sector?.title, "Sector 2")
        XCTAssertEqual(sector?.tone, .good)
        XCTAssertNil(CarProPresent.banner(for: .sector(racer: 2, sector: 1, time: 21.5, delta: nil), player: 0,
                                          kind: .quickRace, laps: 3))
        let deleted = CarProPresent.banner(for: .lap(racer: 0, lap: 2, time: 64, valid: false, personalBest: false),
                                           player: 0, kind: .timeTrial, laps: 0)
        XCTAssertEqual(deleted?.title, "Lap 2 deleted")
        XCTAssertEqual(deleted?.tone, .bad)
        let last = CarProPresent.banner(for: .lap(racer: 0, lap: 2, time: 64, valid: true, personalBest: false),
                                        player: 0, kind: .quickRace, laps: 3)
        XCTAssertEqual(last?.title, "Final lap")
        XCTAssertNil(CarProPresent.banner(for: .lap(racer: 0, lap: 3, time: 64, valid: true, personalBest: true),
                                          player: 0, kind: .quickRace, laps: 3), "the flag has its own banner")
        let limits = CarProPresent.banner(for: .trackLimits(racer: 0, strikes: 4), player: 0, kind: .championship, laps: 5)
        XCTAssertEqual(limits?.detail, "Warning 1 of 3: the third is 5 seconds")
        let penalty = CarProPresent.banner(for: .penalty(racer: 0, seconds: 5), player: 0, kind: .championship, laps: 5)
        XCTAssertGreaterThan(penalty!.priority, limits!.priority)
        XCTAssertEqual(CarProPresent.banner(for: .position(from: 4, to: 3), player: 0, kind: .quickRace, laps: 3)?.title,
                       "Up to P3")
        XCTAssertEqual(CarProPresent.banner(for: .finished(racer: 0, position: 2), player: 0, kind: .championship,
                                            laps: 3)?.detail, "You finished 2nd")
    }

    func testResultsGapsAndUnits() {
        let winner = CarProResult(id: "a", name: "A", isPlayer: false, model: .gt, position: 1, laps: 3, time: 200,
                                  bestLap: 65, penalty: 0, estimated: false)
        let second = CarProResult(id: "b", name: "B", isPlayer: true, model: .gt, position: 2, laps: 3, time: 204.25,
                                  bestLap: 66, penalty: 0, estimated: false)
        let lapped = CarProResult(id: "c", name: "C", isPlayer: false, model: .gt, position: 3, laps: 2, time: 210,
                                  bestLap: 70, penalty: 0, estimated: true)
        let out = CarProResult(id: "d", name: "D", isPlayer: false, model: .gt, position: 4, laps: 1, time: nil,
                               bestLap: nil, penalty: 0, estimated: false)
        XCTAssertEqual(CarProPresent.gap(winner, leader: winner), "3:20.000")
        XCTAssertEqual(CarProPresent.gap(second, leader: winner), "+4.250")
        XCTAssertEqual(CarProPresent.gap(lapped, leader: winner), "+1 lap")
        XCTAssertEqual(CarProPresent.gap(out, leader: winner), "DNF")
        XCTAssertEqual(CarProPresent.points(forPosition: 1), 25)
        XCTAssertEqual(CarProPresent.points(forPosition: 9), 0)
        XCTAssertEqual(CarProPresent.speed(30, mph: false), 108)
        XCTAssertEqual(CarProPresent.speed(30, mph: true), 67)
        XCTAssertEqual(CarProPresent.mass(1080), "1,080 kg")
        XCTAssertEqual(CarProPresent.tyreHeat(CarProTyreCompound.sport.optimalTemperature, compound: .sport), 0)
        XCTAssertEqual(CarProPresent.tyreHeat(-100, compound: .sport), -1)
    }

    func testCareerStatesAndSeasonLimits() throws {
        var career = CarProCareer.newCareer()
        XCTAssertEqual(CarProPresent.state(of: .club, in: career), .open)
        XCTAssertEqual(CarProPresent.state(of: .national, in: career), .locked)
        XCTAssertTrue(CarProPresent.unlockHint(.national).contains("Club Cup"))
        let car = career.selectedCarId
        try career.startSeason(.club, carId: car)
        XCTAssertEqual(CarProPresent.state(of: .club, in: career), .current)
        XCTAssertNil(CarProPresent.seasonLimitBreached(career: career, carId: car, pi: 390))
        XCTAssertEqual(CarProPresent.seasonLimitBreached(career: career, carId: car, pi: 401), .club)
        XCTAssertNil(CarProPresent.seasonLimitBreached(career: career, carId: "elsewhere", pi: 900))
        XCTAssertEqual(CarProPresent.playerPlaces(career.season!), [nil, nil, nil, nil])
        // A round raced: the player's place is remembered for the calendar.
        let weekend = try XCTUnwrap(career.nextWeekend())
        var results: [CarProResult] = weekend.field.enumerated().map { i, e in
            CarProResult(id: e.id, name: e.name, isPlayer: false, model: e.setup.model, position: i + 1, laps: 3,
                         time: 100 + Double(i), bestLap: 33, penalty: 0, estimated: false)
        }
        results.insert(CarProResult(id: CarProEntrant.playerId, name: "You", isPlayer: true, model: .hatch, position: 2,
                                    laps: 3, time: 100.5, bestLap: 33.1, penalty: 0, estimated: false), at: 1)
        for i in results.indices { results[i].position = i + 1 }
        career.recordRace(results)
        XCTAssertEqual(CarProPresent.playerPlaces(career.season!), [2, nil, nil, nil])
        XCTAssertEqual(CarProPresent.eligibleTiers(pi: 500), [.national, .gt, .pro])
        XCTAssertEqual(CarProPresent.tierLine(pi: 990), "Pro Championship only")
        XCTAssertGreaterThan(CarProPresent.seasonPurse(.pro), CarProPresent.seasonPurse(.club))
        XCTAssertEqual(CarProPresent.words(for: .notEnoughMoney(needed: 1_250)), "You need £1,250 more for that.")
        XCTAssertEqual(CarProPresent.words(for: .notEligible(pi: 420, limit: 400)),
                       "This car's PI is 420, over the limit of 400.")
    }

    func testQuickSetupRemembersChoicesAndRefusesNonsense() throws {
        XCTAssertEqual(CarProGridStart.pole.slot(opponents: 5), 0)
        XCTAssertEqual(CarProGridStart.middle.slot(opponents: 5), 2)
        XCTAssertEqual(CarProGridStart.back.slot(opponents: 5), 5)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "car-pro-quick-tests"))
        defaults.removePersistentDomain(forName: "car-pro-quick-tests")
        XCTAssertEqual(CarProQuickSetup.load(defaults), CarProQuickSetup())
        var setup = CarProQuickSetup()
        setup.trackId = "nordwald"
        setup.laps = 5
        setup.start = .pole
        setup.save(defaults)
        XCTAssertEqual(CarProQuickSetup.load(defaults), setup)
        let odd = Data(#"{"trackId":"nowhere","laps":99,"opponents":0}"#.utf8)
        let decoded = try JSONDecoder().decode(CarProQuickSetup.self, from: odd)
        XCTAssertEqual(decoded.trackId, CarProCircuits.ids.first)
        XCTAssertEqual(decoded.laps, 10)
        XCTAssertEqual(decoded.opponents, 1)
        XCTAssertEqual(decoded.start, .back)
    }
}
