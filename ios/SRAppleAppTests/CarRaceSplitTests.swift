import XCTest
@testable import SRAppleApp

final class CarRaceSplitTests: XCTestCase {
    // MARK: - Holding

    func testHoldingASideSteersAndBothBrakes() {
        XCTAssertEqual(CarSplitHold().input, CarInput(throttle: 1, steer: 0))
        XCTAssertEqual(CarSplitHold(left: true).input, CarInput(throttle: 1, steer: -1))
        XCTAssertEqual(CarSplitHold(right: true).input, CarInput(throttle: 1, steer: 1))
        XCTAssertEqual(CarSplitHold(left: true, right: true).input, CarInput(throttle: -1, steer: 0))
    }

    // MARK: - Layout

    private func assertTiles(_ panes: [CarSplitPane], _ width: Double, _ height: Double,
                             file: StaticString = #filePath, line: UInt = #line) {
        let area = panes.reduce(0) { $0 + $1.width * $1.height }
        XCTAssertEqual(area, width * height, accuracy: 1e-6, "the parts fill the screen", file: file, line: line)
        for (i, a) in panes.enumerated() {
            XCTAssertGreaterThanOrEqual(a.x, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(a.y, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(a.x + a.width, width + 1e-9, file: file, line: line)
            XCTAssertLessThanOrEqual(a.y + a.height, height + 1e-9, file: file, line: line)
            for b in panes[(i + 1)...] {
                let apart = a.x + a.width <= b.x || b.x + b.width <= a.x || a.y + a.height <= b.y || b.y + b.height <= a.y
                XCTAssertTrue(apart, "seats \(a.seat) and \(b.seat) overlap", file: file, line: line)
            }
        }
        XCTAssertEqual(Set(panes.map(\.seat)), Set(0..<panes.count), file: file, line: line)
    }

    func testUprightTheScreenIsCutAcrossAndTheFarSideTurned() {
        for players in 2...4 {
            let panes = CarSplitLayout.panes(players: players, width: 390, height: 840, facing: true)
            XCTAssertEqual(panes.count, players)
            assertTiles(panes, 390, 840)
            // The near players have the bottom half, the right way up; the far ones the top, turned.
            for pane in panes {
                XCTAssertEqual(pane.turned, pane.y < 420, "players \(players), seat \(pane.seat)")
            }
            XCTAssertEqual(panes.first { $0.seat == 0 }?.y, 420)
        }
        // Three: the third player gets the whole top half.
        let three = CarSplitLayout.panes(players: 3, width: 390, height: 840, facing: true)
        XCTAssertEqual(three.first { $0.seat == 2 }?.width, 390)
        // Not facing: nobody is turned.
        XCTAssertTrue(CarSplitLayout.panes(players: 4, width: 390, height: 840, facing: false).allSatisfy { !$0.turned })
    }

    func testOnItsSideThePlayersSitSideBySide() {
        let two = CarSplitLayout.panes(players: 2, width: 840, height: 390, facing: true)
        assertTiles(two, 840, 390)
        XCTAssertEqual(two.map(\.height), [390, 390])
        XCTAssertTrue(two.allSatisfy { !$0.turned })
        let three = CarSplitLayout.panes(players: 3, width: 840, height: 390, facing: true)
        assertTiles(three, 840, 390)
        assertTiles(CarSplitLayout.panes(players: 4, width: 840, height: 390, facing: true), 840, 390)
        assertTiles(CarSplitLayout.panes(players: 1, width: 840, height: 390, facing: true), 840, 390)
    }

    func testFingersCountOnThePlayersOwnSides() {
        let panes = CarSplitLayout.panes(players: 2, width: 400, height: 800, facing: true)
        // Seat 0 is the bottom half, upright: screen left is their left.
        var holds = CarSplitLayout.holds(touches: [CarVec(x: 50, y: 700)], panes: panes, players: 2)
        XCTAssertEqual(holds, [CarSplitHold(left: true), CarSplitHold()])
        // Seat 1 is the top half, turned to face them: screen left is their RIGHT.
        holds = CarSplitLayout.holds(touches: [CarVec(x: 50, y: 100)], panes: panes, players: 2)
        XCTAssertEqual(holds, [CarSplitHold(), CarSplitHold(right: true)])
        // Everyone at once: both of seat 0's sides (the brake), one of seat 1's.
        holds = CarSplitLayout.holds(touches: [CarVec(x: 20, y: 790), CarVec(x: 380, y: 790), CarVec(x: 380, y: 10)],
                                     panes: panes, players: 2)
        XCTAssertEqual(holds, [CarSplitHold(left: true, right: true), CarSplitHold(left: true)])
        // Off the screen: nothing.
        XCTAssertEqual(CarSplitLayout.holds(touches: [CarVec(x: -5, y: 900)], panes: panes, players: 2),
                       [CarSplitHold(), CarSplitHold()])
        // Side by side, nobody turned.
        let wide = CarSplitLayout.panes(players: 2, width: 800, height: 400, facing: true)
        XCTAssertEqual(CarSplitLayout.holds(touches: [CarVec(x: 700, y: 200)], panes: wide, players: 2),
                       [CarSplitHold(), CarSplitHold(right: true)])
    }

    // MARK: - The race

    func testCarsStartOnTheirOwnGridSlots() {
        let race = CarSplitRace(track: .paddock, laps: 3, names: ["Ann", "Bo", "Cy", "Di", "Ed"])
        XCTAssertEqual(race.racers.map(\.name), ["Ann", "Bo", "Cy", "Di"], "four at most")
        for racer in race.racers {
            XCTAssertEqual(racer.car.position, CarTrack.paddock.grid(racer.id).at)
        }
        for (i, a) in race.racers.enumerated() {
            for b in race.racers[(i + 1)...] {
                XCTAssertNil(CarCollision.contact(a.car.body, b.car.body), "\(a.name) and \(b.name) start clear")
            }
        }
        XCTAssertFalse(race.over)
    }

    func testHeldSidesSteerEachCarEasedIn() {
        var race = CarSplitRace(track: .paddock, laps: 3, names: ["Ann", "Bo"])
        // Ann starts on the left of the grid and Bo on the right: each steers away from the other.
        let holds = [CarSplitHold(left: true), CarSplitHold(right: true)]
        race.step(holds: holds, autopilot: false, dt: 1.0 / 60, time: 1.0 / 60)
        XCTAssertLessThan(race.racers[0].steer, 0)
        XCTAssertGreaterThan(race.racers[0].steer, -1, "eased, not snapped")
        XCTAssertGreaterThan(race.racers[1].steer, 0)
        var t = 1.0 / 60
        for _ in 2...30 {
            t += 1.0 / 60
            race.step(holds: holds, autopilot: false, dt: 1.0 / 60, time: t)
        }
        XCTAssertLessThan(race.racers[0].car.heading, CarTrack.paddock.grid(0).heading)
        XCTAssertGreaterThan(race.racers[1].car.heading, CarTrack.paddock.grid(1).heading)
        // Let go: straight on, with the throttle down.
        for _ in 1...30 {
            t += 1.0 / 60
            race.step(holds: [CarSplitHold(), CarSplitHold()], autopilot: false, dt: 1.0 / 60, time: t)
        }
        XCTAssertEqual(race.racers[0].steer, 0, accuracy: 0.01)
        XCTAssertGreaterThan(race.racers[0].car.speed, 5)
    }

    func testCarsInOneRaceBounceOffEachOther() {
        var race = CarSplitRace(track: .paddock, laps: 3, names: ["Ann", "Bo"])
        // Both on the line, Bo just ahead of Ann in the same lane and slower.
        race.place(0, at: 40, speed: 25)
        race.place(1, at: 44.5, speed: 12)
        let before = race.racers.map(\.car.forwardSpeed)
        var hardest = 0.0
        for frame in 1...10 {
            let events = race.step(holds: [CarSplitHold(), CarSplitHold()], autopilot: false, dt: 1.0 / 60, time: Double(frame) / 60)
            hardest = max(hardest, events.hardest)
        }
        XCTAssertGreaterThan(hardest, 5, "a knock to feel")
        XCTAssertLessThan(race.racers[0].car.forwardSpeed, before[0] - 3, "Ann is knocked back")
        XCTAssertGreaterThan(race.racers[1].car.forwardSpeed, before[1] + 3, "Bo is knocked on")
        XCTAssertNil(CarCollision.contact(race.racers[0].car.body, race.racers[1].car.body))
    }

    /// The demo's pilots, four abreast, all get round and home, bumping as
    /// they go; the table ranks them.
    func testTheDemoPackFinishesEveryTrack() {
        for track in CarTrack.all {
            var race = CarSplitRace(track: track, laps: 2, names: ["A", "B", "C", "D"])
            var t = 0.0
            let dt = 1.0 / 60
            while !race.over && t < 300 {
                t += dt
                race.step(holds: [], autopilot: true, dt: dt, time: t)
            }
            XCTAssertTrue(race.over, track.id)
            XCTAssertTrue(race.racers.allSatisfy { $0.laps.finished }, "\(track.id): \(race.racers.map(\.laps.progress))")
            let entries = race.entries
            XCTAssertEqual(entries.count, 4)
            XCTAssertEqual(entries, CarRaceEntry.ranked(entries))
            XCTAssertEqual(race.place(of: Int(entries[0].id) ?? -1), 1)
            // Each run is kept as a ghost, with its time, to race in a time trial.
            for racer in race.racers {
                XCTAssertEqual(racer.ghost.time, racer.laps.finishTime)
                XCTAssertGreaterThan(racer.ghost.samples.count, 100)
            }
        }
    }

    func testTheFirstHomeStartsTheClockOnTheRest() {
        var race = CarSplitRace(track: .paddock, laps: 1, names: ["Ann", "Bo"])
        let length = CarTrack.paddock.length
        var t = 0.0
        var home: [Int] = []
        while home.isEmpty && t < 120 {
            t += 1.0 / 60
            // Bo has stopped before the line, off to one side; Ann's pilot drives the lap.
            race.place(1, at: length - 30, speed: 0, offset: 5)
            home += race.step(holds: [], autopilot: true, dt: 1.0 / 60, time: t).finished
        }
        XCTAssertEqual(home, [0])
        XCTAssertEqual(race.endsAt, t + CarSplitRace.finishGrace, accuracy: 1e-9)
        XCTAssertFalse(race.over)
        XCTAssertEqual(race.place(of: 0), 1)
        XCTAssertEqual(race.entries.map(\.id), ["0", "1"])
        XCTAssertNil(race.entries[1].time)
        // The grace runs out.
        race.step(holds: [], autopilot: false, dt: 1.0 / 60, time: t + CarSplitRace.finishGrace)
        XCTAssertTrue(race.over)
        // Over is over.
        let after = race
        race.step(holds: [], autopilot: false, dt: 1.0 / 60, time: t + CarSplitRace.finishGrace + 1)
        XCTAssertEqual(race, after)
    }

    func testStoppingEndsTheRaceWithTheRestUnplaced() {
        var race = CarSplitRace(track: .riverside, laps: 3, names: ["Ann", "Bo", "Cy"])
        for frame in 1...120 {
            race.step(holds: [CarSplitHold(), CarSplitHold(left: true, right: true), CarSplitHold()], autopilot: false,
                      dt: 1.0 / 60, time: Double(frame) / 60)
        }
        race.stop()
        XCTAssertTrue(race.over)
        XCTAssertTrue(race.entries.allSatisfy { $0.time == nil })
        // Nobody home: furthest round first, so the braking Bo is last.
        XCTAssertEqual(race.entries.last?.id, "1")
    }
}

private extension CarSplitRace {
    /// Put seat `seat` `distance` round the track, `offset` metres right of
    /// the middle line, pointing along it at `speed`.
    mutating func place(_ seat: Int, at distance: Double, speed: Double, offset: Double = 0) {
        let spot = track.point(at: distance)
        let right = CarVec(x: -sin(spot.direction), y: cos(spot.direction))
        let at = spot.at + right * offset
        var car = CarState(x: at.x, y: at.y, heading: spot.direction)
        car.vx = cos(spot.direction) * speed
        car.vy = sin(spot.direction) * speed
        move(seat, to: car)
    }
}
