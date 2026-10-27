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
