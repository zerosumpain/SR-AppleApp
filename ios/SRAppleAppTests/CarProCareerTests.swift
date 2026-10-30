import XCTest
@testable import SRAppleApp

/// Car Racer+ sessions (races, qualifying, time trial) and the career.
final class CarProCareerTests: XCTestCase {
    // MARK: - Sessions

    private func field(_ count: Int, model: CarProCarModel = .hatch) -> [CarProEntrant] {
        (0..<count).map { i in
            let driver = CarProDriverProfile(id: "ai-\(i)", name: "Driver \(i)", skill: 0.5 + 0.1 * Double(i),
                                             aggression: 0.5, number: 10 + i, hue: Double(i) / 10)
            return .ai(driver, setup: CarProCarSetup(model: model))
        }
    }

    func testARaceRunsFromTheLightsToTheFlag() {
        let player = CarProEntrant.player(setup: CarProCarSetup(model: .hatch))
        var config = CarProSessionConfig.quickRace(track: "quarry-rx", laps: 2, player: player, opponents: field(3),
                                                   assists: .full, playerSlot: 3)
        config.autopilot = true
        var session = CarProSession(config: config)
        XCTAssertEqual(session.racers.count, 4)
        XCTAssertEqual(session.playerIndex, 3)
        guard case .countdown = session.phase else { return XCTFail("starts on the lights") }
        var lights: [Int] = [], lightsOut = false, laps = 0, sectors = 0, finishes = 0
        var frames = 0
        while session.phase != .finished && frames < 30 * 400 {
            session.step(dt: 1.0 / 30, input: CarProInput())
            frames += 1
            for event in session.events {
                switch event {
                case let .light(n): lights.append(n)
                case .lightsOut: lightsOut = true
                case .lap: laps += 1
                case .sector: sectors += 1
                case .finished: finishes += 1
                default: break
                }
            }
            if !lightsOut {
                // Nobody moves on the grid.
                for racer in session.racers { XCTAssertLessThan(racer.vehicle.speed, 0.5) }
            }
        }
        XCTAssertEqual(lights, [2, 3, 4, 5], "the lights come on one by one")
        XCTAssertTrue(lightsOut)
        XCTAssertEqual(session.phase, .finished)
        XCTAssertEqual(session.player.lapsDone, 2)
        XCTAssertGreaterThanOrEqual(laps, 5, "everyone counts laps")
        XCTAssertGreaterThanOrEqual(sectors, 8)
        XCTAssertGreaterThanOrEqual(finishes, 1)
        // Places are a permutation, and the results are in order with times.
        XCTAssertEqual(Set(session.racers.map(\.position)), Set(1...4))
        let results = session.results
        XCTAssertEqual(results.map(\.position), [1, 2, 3, 4])
        let times = results.compactMap(\.time)
        XCTAssertEqual(times.count, 4)
        XCTAssertEqual(times, times.sorted())
        XCTAssertTrue(results.contains { $0.isPlayer })
        XCTAssertNotNil(session.player.bestLap)
        XCTAssertEqual(session.player.lapTimes.count, 2)
        // Standing start: the first lap includes getting away.
        XCTAssertGreaterThan(session.player.lapTimes[0], session.player.lapTimes[1])
        let hud = session.hud
        XCTAssertEqual(hud.cars, 4)
        XCTAssertEqual(hud.tyreTemperatures.count, 4)
        XCTAssertGreaterThan(hud.redline, 5000)
    }

    func testTimeTrialKeepsTheBestLapAsAGhostAndATrace() {
        let player = CarProEntrant.player(setup: CarProCarSetup(model: .roadster))
        var config = CarProSessionConfig.timeTrial(track: "old-town", player: player, assists: .full, ghost: nil)
        config.autopilot = true
        var session = CarProSession(config: config)
        XCTAssertEqual(session.phase, .racing, "a rolling start")
        var sawDelta = false
        while session.player.lapsDone < 2 && session.time < 400 {
            session.step(dt: 1.0 / 60, input: CarProInput())
            if session.deltaToBest != nil { sawDelta = true }
            if session.player.lapsDone == 1 { XCTAssertNotNil(session.ghostPose) }
        }
        XCTAssertEqual(session.player.lapsDone, 2)
        XCTAssertTrue(sawDelta, "the second lap shows its delta to the first")
        let ghost = try! XCTUnwrap(session.bestGhost)
        XCTAssertTrue(session.newGhost)
        XCTAssertEqual(ghost.lapTime, session.player.bestLap!, accuracy: 1e-9)
        XCTAssertEqual(ghost.trackId, "old-town")
        XCTAssertGreaterThan(ghost.samples.count, Int(ghost.lapTime * 10))
        XCTAssertEqual(ghost.time(atDistance: 0)!, 0, accuracy: 0.2)
        XCTAssertEqual(ghost.time(atDistance: session.track.length - 5)!, ghost.lapTime, accuracy: 0.5)
        let trace = try! XCTUnwrap(session.lastTelemetry)
        XCTAssertGreaterThan(trace.speeds.count, Int(session.track.length / CarProTelemetry.binSize) - 3)
        XCTAssertGreaterThan(trace.speeds.max()!, 20)
        // Driven again, the stored ghost is the one to beat.
        var again = CarProSessionConfig.timeTrial(track: "old-town", player: player, assists: .full, ghost: ghost)
        again.autopilot = true
        let next = CarProSession(config: again)
        XCTAssertEqual(next.bestGhost, ghost)
        XCTAssertNotNil(try? JSONDecoder().decode(CarProGhost.self, from: JSONEncoder().encode(ghost)))
    }

    func testCuttingTheTrackCostsTheLapAndInARaceTime() {
        let player = CarProEntrant.player(setup: CarProCarSetup(model: .hatch))
        // Flat out with the wheel straight: off at the first bend, into the run-off.
        var session = CarProSession(config: .qualifying(track: "brackenfield", player: player, assists: .full, laps: 1))
        var strikes = 0
        for _ in 0..<(60 * 40) {
            session.step(dt: 1.0 / 60, input: CarProInput(throttle: 1))
            for event in session.events { if case .trackLimits = event { strikes += 1 } }
            if strikes > 0 { break }
            // Steer back towards the road once off it.
            if session.player.vehicle.offTrack {
                let v = session.player.vehicle
                let back: Double = v.trackOffset > 0 ? -1 : 1
                session.step(dt: 1.0 / 60, input: CarProInput(throttle: 0.6, steer: back))
            }
        }
        XCTAssertGreaterThan(strikes, 0)
        XCTAssertFalse(session.player.lapValid)
        XCTAssertGreaterThan(session.player.strikes, 0)
    }

    func testSessionsAreDeterministic() {
        func run() -> [CarProVec] {
            let player = CarProEntrant.player(setup: CarProCarSetup(model: .touring))
            var config = CarProSessionConfig.quickRace(track: "neon-harbour", laps: 1, player: player,
                                                       opponents: field(3, model: .touring), assists: .full, seed: 9)
            config.autopilot = true
            var session = CarProSession(config: config)
            for frame in 0..<(60 * 25) {
                // Uneven frames: a fixed step underneath makes them the same race.
                session.step(dt: frame % 3 == 0 ? 1.0 / 40 : 1.0 / 80, input: CarProInput())
            }
            return session.racers.map(\.vehicle.position)
        }
        XCTAssertEqual(run(), run())
    }

    // MARK: - Career

    func testANewCareerHasAHatchbackAndTheClubCup() {
        let career = CarProCareer.newCareer()
        XCTAssertEqual(career.garage.count, 1)
        XCTAssertEqual(career.selectedCar.model, .hatch)
        XCTAssertEqual(career.unlocked, [.club])
        XCTAssertEqual(career.money, CarProCareer.startingMoney)
        XCTAssertTrue(career.isEligible(carId: career.selectedCarId, for: .club))
        XCTAssertNil(career.season)
        XCTAssertNil(career.nextWeekend())
        // Tiers climb in PI, prizes and calendar length; every round is a real circuit.
        for (a, b) in zip(CarProTier.allCases, CarProTier.allCases.dropFirst()) {
            XCTAssertLessThan(a.piLimit, b.piLimit)
            XCTAssertLessThan(a.prizes[0], b.prizes[0])
            XCTAssertEqual(a.next, b)
            XCTAssertEqual(b.previous, a)
        }
        for tier in CarProTier.allCases {
            XCTAssertTrue((4...6).contains(tier.calendar.count))
            for id in tier.calendar { XCTAssertNotNil(CarProCircuits.track(id), id) }
            for model in tier.fieldModels {
                XCTAssertLessThanOrEqual(CarProCarSetup(model: model).stats.pi, tier.piLimit, "\(tier) \(model)")
            }
        }
    }

    func testBuyingCarsAndUpgradesSpendsMoney() throws {
        var career = CarProCareer.newCareer()
        let hatch = career.selectedCarId
        let before = career.money
        let cost = try career.buyUpgrade(carId: hatch, kind: .tyres)
        XCTAssertEqual(career.money, before - cost)
        XCTAssertEqual(career.car(hatch)?.setup.upgrades.tyres, 1)
        XCTAssertThrowsError(try career.buy(.prototype)) { error in
            XCTAssertEqual(error as? CarProCareerError, .notEnoughMoney(needed: CarProCarModel.prototype.price - career.money))
        }
        career.money = 1_000_000
        let roadster = try career.buy(.roadster)
        XCTAssertEqual(career.selectedCarId, roadster.id)
        XCTAssertEqual(career.money, 1_000_000 - CarProCarModel.roadster.price)
        XCTAssertThrowsError(try career.buy(.roadster)) { XCTAssertEqual($0 as? CarProCareerError, .alreadyOwned) }
        for _ in 0..<3 { try career.buyUpgrade(carId: roadster.id, kind: .engine) }
        XCTAssertThrowsError(try career.buyUpgrade(carId: roadster.id, kind: .engine)) {
            XCTAssertEqual($0 as? CarProCareerError, .maxedOut)
        }
        try career.setTuning(carId: roadster.id, CarProTuning(brakeBias: 0.6, wing: 0.8, finalDrive: 1.05))
        XCTAssertEqual(career.car(roadster.id)?.setup.tuning.wing, 0.8)
        try career.select(carId: hatch)
        XCTAssertEqual(career.selectedCar.model, .hatch)
        XCTAssertThrowsError(try career.select(carId: "nope"))
    }

    /// A made-up result with the player `place`d.
    private func results(for weekend: CarProWeekend, playerPlace: Int) -> [CarProResult] {
        // A different AI driver wins each round.
        let field = weekend.field.map(\.id)
        var ids = (0..<field.count).map { field[($0 + weekend.round) % field.count] }
        ids.insert(CarProEntrant.playerId, at: playerPlace - 1)
        return ids.enumerated().map { i, id in
            CarProResult(id: id, name: id, isPlayer: id == CarProEntrant.playerId, model: .hatch, position: i + 1,
                         laps: weekend.laps, time: 100 + Double(i), bestLap: 40 + Double(i), penalty: 0, estimated: false)
        }
    }

    func testAChampionshipPaysPointsAndPrizesAndOpensTheNextTier() throws {
        var career = CarProCareer.newCareer()
        XCTAssertThrowsError(try career.startSeason(.national, carId: career.selectedCarId)) {
            XCTAssertEqual($0 as? CarProCareerError, .tierLocked)
        }
        try career.startSeason(.club, carId: career.selectedCarId)
        let season = try XCTUnwrap(career.season)
        XCTAssertEqual(season.field.count, 7)
        for entrant in season.field { XCTAssertLessThanOrEqual(entrant.setup.stats.pi, CarProTier.club.piLimit) }
        XCTAssertEqual(Set(season.field.map(\.id)).count, 7)

        let weekend = try XCTUnwrap(career.nextWeekend())
        XCTAssertEqual(weekend.trackId, CarProTier.club.calendar[0])
        XCTAssertGreaterThanOrEqual(weekend.laps, 2)
        // Qualifying: a quick lap takes pole, no lap starts last.
        let pole = weekend.grid(playerLap: 1)
        XCTAssertTrue(pole[0].isPlayer)
        let back = weekend.grid(playerLap: nil)
        XCTAssertTrue(back.last!.isPlayer)
        XCTAssertEqual(back.count, 8)
        let race = weekend.raceConfig(grid: back, assists: .full)
        XCTAssertEqual(race.kind, .championship)
        XCTAssertEqual(race.entrants.count, 8)

        let money = career.money
        let reward = try XCTUnwrap(career.recordRace(results(for: weekend, playerPlace: 1)))
        XCTAssertEqual(reward.position, 1)
        XCTAssertEqual(reward.points, 26, "25 for the win and 1 for the fastest lap")
        XCTAssertTrue(reward.fastestLap)
        XCTAssertEqual(reward.prize, CarProTier.club.prizes[0])
        XCTAssertEqual(career.money, money + reward.prize)
        XCTAssertEqual(career.season?.round, 1)
        XCTAssertEqual(career.season?.table.first?.isPlayer, true)
        XCTAssertFalse(reward.seasonComplete)

        // Second in every other round: still champion on points.
        var last: CarProRaceReward?
        while let next = career.nextWeekend() {
            last = career.recordRace(results(for: next, playerPlace: 2))
        }
        let end = try XCTUnwrap(last)
        XCTAssertTrue(end.seasonComplete)
        XCTAssertEqual(end.championshipPosition, 1)
        XCTAssertTrue(end.title)
        XCTAssertEqual(end.unlocked, .national)
        XCTAssertEqual(end.seasonBonus, CarProTier.club.seasonBonus[0])
        XCTAssertTrue(career.isUnlocked(.national))
        XCTAssertEqual(career.titles, [.club])
        XCTAssertEqual(career.stats.races, CarProTier.club.calendar.count)
        XCTAssertEqual(career.stats.wins, 1)
        XCTAssertNil(career.nextWeekend())
        XCTAssertNil(career.recordRace(results(for: weekend, playerPlace: 1)), "nothing to score once it is over")
        // A car over the limit is turned away.
        career.money = 10_000_000
        let prototype = try career.buy(.prototype)
        XCTAssertThrowsError(try career.startSeason(.national, carId: prototype.id)) { error in
            guard case .notEligible = error as? CarProCareerError else { return XCTFail("\(error)") }
        }
    }

    func testAIFieldsAreBuiltUpToTheirTiersAndQualifyByPace() {
        for tier in CarProTier.allCases {
            let field = CarProField.season(tier, difficulty: .normal, seed: 4)
            XCTAssertEqual(field.count, 7)
            for entrant in field {
                let pi = entrant.setup.stats.pi
                XCTAssertLessThanOrEqual(pi, tier.piLimit)
                XCTAssertTrue((0...1).contains(entrant.driver!.skill))
            }
        }
        XCTAssertEqual(CarProField.season(.gt, difficulty: .normal, seed: 4), CarProField.season(.gt, difficulty: .normal, seed: 4))
        let easy = CarProField.season(.club, difficulty: .easy, seed: 4).map { $0.driver!.skill }
        let hard = CarProField.season(.club, difficulty: .hard, seed: 4).map { $0.driver!.skill }
        XCTAssertLessThan(easy.reduce(0, +), hard.reduce(0, +))
        let built = CarProField.build(.hatch, targetPI: 350)
        XCTAssertLessThanOrEqual(built.stats.pi, 350)
        XCTAssertGreaterThan(built.stats.pi, 320)
        // Qualifying estimates: a quicker car and a better driver go faster.
        let track = CarProCircuits.track("brackenfield")!
        let slow = CarProEntrant.ai(CarProDriverProfile(id: "a", name: "A", skill: 0.2, aggression: 0.5, number: 1, hue: 0),
                                    setup: CarProCarSetup(model: .hatch))
        var quick = slow
        quick.driver?.skill = 1
        var fast = quick
        fast.setup = CarProCarSetup(model: .gt)
        let times = [slow, quick, fast].map { CarProQualifying.estimate($0, track: track, seed: 1) }
        XCTAssertEqual(times, times.sorted(by: >))
        let opponents = CarProField.quickRace(for: CarProCarSetup(model: .touring), count: 5, difficulty: .normal, seed: 2)
        XCTAssertEqual(opponents.count, 5)
        for entrant in opponents {
            XCTAssertLessThan(abs(entrant.setup.stats.pi - CarProCarSetup(model: .touring).stats.pi), 60)
        }
    }

    func testCareerSavesAndLoadsWholeAndSurvivesOldAndNewSaves() throws {
        var career = CarProCareer.newCareer()
        career.money = 123_456
        _ = try career.buy(.touring)
        try career.buyUpgrade(carId: career.selectedCarId, kind: .aero)
        try career.startSeason(.club, carId: career.selectedCarId)
        if let weekend = career.nextWeekend() { career.recordRace(results(for: weekend, playerPlace: 3)) }
        career.recordTimeTrial(track: "saltcliff", model: .touring, lap: 92.5)
        XCTAssertFalse(career.recordTimeTrial(track: "saltcliff", model: .touring, lap: 95))
        XCTAssertTrue(career.recordTimeTrial(track: "saltcliff", model: .touring, lap: 91))
        XCTAssertEqual(career.best(track: "saltcliff", model: .touring), 91)
        career.settings.steering = .wheel
        career.settings.assists.abs = false

        let data = try XCTUnwrap(career.encoded())
        XCTAssertEqual(CarProCareer.decode(data), career)

        // Through UserDefaults, as the app keeps it.
        let suite = "car-racer-plus.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CarProStore(defaults: defaults, folder: nil)
        XCTAssertEqual(store.load(), .newCareer(), "nothing saved: a fresh career")
        store.save(career)
        XCTAssertEqual(store.load(), career)

        // An old save without the newer fields still opens.
        let old = #"{"version":1,"money":500,"garage":[{"id":"car-1","setup":{"model":"hatch","upgrades":{"engine":1,"turbo":0,"gearbox":0,"tyres":0,"brakes":0,"suspension":0,"weight":0,"aero":0,"differential":0},"tuning":{"brakeBias":0.7,"wing":0.5,"finalDrive":1}}}],"selectedCarId":"car-1","unlocked":["club"]}"#
        let opened = try XCTUnwrap(CarProCareer.decode(Data(old.utf8)))
        XCTAssertEqual(opened.money, 500)
        XCTAssertEqual(opened.selectedCar.setup.upgrades.engine, 1)
        XCTAssertEqual(opened.settings, CarProSettings())
        // A save from a newer build is left alone, and junk is not a career.
        XCTAssertNil(CarProCareer.decode(Data(#"{"version":99,"money":1}"#.utf8)))
        XCTAssertNil(CarProCareer.decode(Data("not json".utf8)))
    }

    func testGhostsAreKeptPerCircuitAndCar() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("carpro-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CarProStore(defaults: .standard, folder: folder)
        var ghost = CarProGhost(trackId: "saltcliff", model: .gt, lapTime: 88)
        ghost.record(t: 0, at: .zero, heading: 0, distance: 0)
        ghost.record(t: 0.5, at: CarProVec(x: 20, y: 0), heading: 0, distance: 20)
        store.saveGhost(ghost)
        XCTAssertEqual(store.ghost(track: "saltcliff", model: .gt), ghost)
        XCTAssertNil(store.ghost(track: "saltcliff", model: .hatch))
        XCTAssertNil(store.ghost(track: "../etc", model: .gt))
        let halfway = try XCTUnwrap(ghost.pose(at: 0.25))
        XCTAssertEqual(halfway.position.x, 10, accuracy: 1e-9)
    }

    func testFormatting() {
        XCTAssertEqual(CarProFormat.time(62.374), "1:02.374")
        XCTAssertEqual(CarProFormat.time(48.2), "48.200")
        XCTAssertEqual(CarProFormat.time(nil), "--:--.---")
        XCTAssertEqual(CarProFormat.money(12_500), "£12,500")
        XCTAssertEqual(CarProFormat.money(999), "£999")
        XCTAssertEqual(CarProFormat.ordinal(1), "1st")
        XCTAssertEqual(CarProFormat.ordinal(12), "12th")
        XCTAssertEqual(CarProFormat.ordinal(23), "23rd")
        XCTAssertEqual(CarProFormat.delta(-0.5), "\u{2212}0.50")
    }
}
