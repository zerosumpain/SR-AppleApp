import XCTest
@testable import SRAppleApp

/// The mazes, the records and the drawing maths behind Snake.
final class SnakeBoardTests: XCTestCase {
    // MARK: - Mazes

    func testEveryMazeLeavesTheStartClear() {
        let start = SnakeRules.start(columns: SnakeRules.columns, rows: SnakeRules.rows)
        for maze in SnakeMaze.all {
            for i in -SnakeRules.startLength...4 {
                let cell = SnakePoint(start.head.x + i, start.head.y)
                XCTAssertFalse(maze.walls.contains(cell), "\(maze.name) blocks the start at \(cell)")
            }
        }
    }

    func testEveryMazeIsOnTheBoard() {
        for maze in SnakeMaze.all {
            XCTAssertFalse(maze.walls.isEmpty)
            for w in maze.walls {
                XCTAssertTrue((0..<SnakeRules.columns).contains(w.x) && (0..<SnakeRules.rows).contains(w.y),
                              "\(maze.name) has a wall off the board")
            }
        }
    }

    func testEveryFreeCellInEveryMazeCanBeReached() {
        for maze in SnakeMaze.all {
            let g = SnakeGame(mode: .maze, maze: maze, seed: 1)
            var seen: Set<SnakePoint> = [g.head]
            var queue: [SnakePoint] = [g.head]
            while let cell = queue.popLast() {
                for d in SnakeDirection.allCases {
                    guard let n = g.neighbour(of: cell, going: d), !g.walls.contains(n), !seen.contains(n) else { continue }
                    seen.insert(n)
                    queue.append(n)
                }
            }
            let free = SnakeRules.columns * SnakeRules.rows - maze.walls.count
            XCTAssertEqual(seen.count, free, "\(maze.name) has cells you cannot get to")
        }
    }

    func testMazesOpenInOrderWithRisingScores() {
        XCTAssertEqual(SnakeMaze.all.first?.unlockScore, 0)
        XCTAssertGreaterThanOrEqual(SnakeMaze.all.count, 3)
        for i in 1..<SnakeMaze.all.count {
            XCTAssertGreaterThan(SnakeMaze.all[i].unlockScore, SnakeMaze.all[i - 1].unlockScore)
            XCTAssertEqual(SnakeMaze.all[i].previous, SnakeMaze.all[i - 1])
        }
        XCTAssertEqual(Set(SnakeMaze.all.map(\.id)).count, SnakeMaze.all.count)
        XCTAssertEqual(SnakeMaze.named("nope"), SnakeMaze.all[0])
    }

    func testWallsOnlyInMazeMode() {
        XCTAssertTrue(SnakeGame(mode: .classic, maze: SnakeMaze.box, seed: 1).walls.isEmpty)
        XCTAssertTrue(SnakeGame(mode: .wrap, maze: SnakeMaze.box, seed: 1).walls.isEmpty)
        XCTAssertEqual(SnakeGame(mode: .maze, maze: SnakeMaze.box, seed: 1).walls, SnakeMaze.box.walls)
    }

    // MARK: - Records

    private func finished(mode: SnakeMode, maze: SnakeMaze? = nil, apples: Int, seed: UInt64 = 5) -> SnakeGame {
        // Eat `apples` in a straight line on a wrapping board, then stop.
        var g = SnakeGame(mode: mode == .classic ? .wrap : mode, maze: maze, seed: seed)
        var eaten = 0
        var guardSteps = 0
        while eaten < apples && guardSteps < 20_000 && !g.isOver {
            g.turn(SnakeAutopilot.choose(g))
            if g.step().ate != nil { eaten += 1 }
            guardSteps += 1
        }
        return g
    }

    func testRecordsKeepTheBestPerMode() {
        var records = SnakeRecords()
        let g = finished(mode: .wrap, apples: 4)
        let first = records.record(g, maze: nil)
        XCTAssertTrue(first.newBest)
        XCTAssertEqual(first.best, g.score)
        XCTAssertEqual(records.best(mode: .wrap, maze: nil).score, g.score)
        XCTAssertEqual(records.best(mode: .classic, maze: nil).score, 0, "each mode has its own best")
        let worse = records.record(finished(mode: .wrap, apples: 1), maze: nil)
        XCTAssertFalse(worse.newBest)
        XCTAssertEqual(worse.best, g.score)
        XCTAssertEqual(records.best(mode: .wrap, maze: nil).games, 2)
        XCTAssertEqual(records.games, 2)
    }

    func testAZeroScoreIsNeverANewBest() {
        var records = SnakeRecords()
        let g = SnakeGame(mode: .classic, seed: 1)
        XCTAssertFalse(records.record(g, maze: nil).newBest)
    }

    func testMazeBestsAreFiledPerMazeAndOpenTheNext() {
        var records = SnakeRecords()
        XCTAssertTrue(records.isUnlocked(SnakeMaze.pillars))
        XCTAssertFalse(records.isUnlocked(SnakeMaze.box))
        let apples = SnakeMaze.box.unlockScore / SnakeRules.applePoints
        let g = finished(mode: .maze, maze: SnakeMaze.pillars, apples: apples)
        XCTAssertGreaterThanOrEqual(g.score, SnakeMaze.box.unlockScore)
        let result = records.record(g, maze: SnakeMaze.pillars)
        XCTAssertEqual(result.unlockedMazes, [SnakeMaze.box.name])
        XCTAssertEqual(result.place, SnakeMaze.pillars.name)
        XCTAssertTrue(records.isUnlocked(SnakeMaze.box))
        XCTAssertFalse(records.isUnlocked(SnakeMaze.corners))
        XCTAssertEqual(records.best("maze.pillars").score, g.score)
        XCTAssertEqual(SnakeRecords.key(mode: .maze, maze: SnakeMaze.box), "maze.box")
        XCTAssertEqual(SnakeRecords.key(mode: .classic, maze: SnakeMaze.box), "classic")
    }

    func testALockedMazeFallsBackToTheFirst() {
        var records = SnakeRecords()
        records.mazeId = SnakeMaze.corridors.id
        XCTAssertEqual(records.maze, SnakeMaze.pillars)
    }

    func testColoursOpenWithApplesInAll() {
        var records = SnakeRecords()
        XCTAssertEqual(records.nextSkin, .grape)
        records.skin = .rainbow
        XCTAssertEqual(records.activeSkin, .sky, "a locked colour is not worn")
        records.apples = SnakeSkin.grape.unlockApples - 2
        let g = finished(mode: .wrap, apples: 3)
        let result = records.record(g, maze: nil)
        XCTAssertEqual(result.unlockedSkins, [SnakeSkin.grape.title])
        XCTAssertTrue(records.isUnlocked(.grape))
        XCTAssertEqual(records.nextSkin, .sunset)
        var last: Int = -1
        for skin in SnakeSkin.allCases {
            XCTAssertGreaterThan(skin.unlockApples, last)
            last = skin.unlockApples
        }
    }

    func testRecordsRoundTripAndReadOldData() throws {
        var records = SnakeRecords()
        records.apples = 12
        records.mode = .maze
        records.pad = true
        records.skin = .grape
        records.bests["wrap"] = SnakeBest(score: 90, length: 12, games: 3)
        let data = try JSONEncoder().encode(records)
        XCTAssertEqual(try JSONDecoder().decode(SnakeRecords.self, from: data), records)
        let old = try JSONDecoder().decode(SnakeRecords.self, from: Data(#"{"apples": 4, "mode": "nonsense"}"#.utf8))
        XCTAssertEqual(old.apples, 4)
        XCTAssertEqual(old.mode, .classic)
        XCTAssertFalse(old.pad)
    }

    func testStoreSavesUnderItsOwnKey() {
        let suite = "snake-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("no defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SnakeRecordStore(defaults: defaults)
        XCTAssertEqual(store.load(), SnakeRecords())
        var records = SnakeRecords()
        records.games = 7
        store.save(records)
        XCTAssertEqual(store.load().games, 7)
        XCTAssertTrue(SnakeRecordStore.key.hasPrefix("snake."))
    }

    // MARK: - Drawing maths

    func testPathGlidesFromTheLastStep() {
        let body = [SnakePoint(5, 4), SnakePoint(4, 4), SnakePoint(3, 4)]
        let start = SnakePath.centres(body: body, vacated: SnakePoint(2, 4), fraction: 0, columns: 10, rows: 10)
        XCTAssertEqual(start.first, SnakeVec(4.5, 4.5), "the head starts in the cell behind")
        XCTAssertEqual(start.last, SnakeVec(2.5, 4.5), "the tail starts in the cell it is leaving")
        let half = SnakePath.centres(body: body, vacated: SnakePoint(2, 4), fraction: 0.5, columns: 10, rows: 10)
        XCTAssertEqual(half.first, SnakeVec(5.0, 4.5))
        XCTAssertEqual(half.last, SnakeVec(3.0, 4.5))
        XCTAssertEqual(SnakePath.length(half), 2, accuracy: 1e-9, "the length holds as it glides")
        let done = SnakePath.centres(body: body, vacated: SnakePoint(2, 4), fraction: 1, columns: 10, rows: 10)
        XCTAssertEqual(done, [SnakeVec(5.5, 4.5), SnakeVec(4.5, 4.5), SnakeVec(3.5, 4.5)])
    }

    func testPathGrowsWhenNothingWasVacated() {
        let body = [SnakePoint(5, 4), SnakePoint(4, 4), SnakePoint(3, 4), SnakePoint(2, 4)]
        let p = SnakePath.centres(body: body, vacated: nil, fraction: 0.25, columns: 10, rows: 10)
        XCTAssertEqual(SnakePath.length(p), 2.25, accuracy: 1e-9)
    }

    func testPathUnwrapsAcrossAnEdge() {
        let body = [SnakePoint(0, 4), SnakePoint(9, 4), SnakePoint(8, 4)]
        let p = SnakePath.centres(body: body, vacated: SnakePoint(7, 4), fraction: 0.5, columns: 10, rows: 10)
        for i in 1..<p.count { XCTAssertLessThanOrEqual(p[i].distance(to: p[i - 1]), 1.0 + 1e-9) }
        XCTAssertEqual(p.first, SnakeVec(0.0, 4.5), "the head is half over the left-hand edge")
        XCTAssertEqual(p.last?.x ?? 0, -2.0, accuracy: 1e-9, "the body carries on past the edge")
        let shifts = SnakePath.copies(of: p, columns: 10, rows: 10)
        XCTAssertTrue(shifts.contains(SnakeVec(0, 0)))
        XCTAssertTrue(shifts.contains(SnakeVec(10, 0)), "drawn again one board to the right")
        let inside = SnakePath.copies(of: [SnakeVec(4.5, 4.5), SnakeVec(5.5, 4.5)], columns: 10, rows: 10)
        XCTAssertEqual(inside, [SnakeVec(0, 0)])
    }

    func testLongSnakeOverTheSameEdgeTwiceIsDrawnInFull() {
        // Going right along row 5, up into row 4, and right again: off the
        // right-hand edge twice, so the unwrapped line reaches more than a
        // whole board to the left of the head.
        var body: [SnakePoint] = []
        for x in [2, 1, 0, 9, 8, 7] { body.append(SnakePoint(x, 4)) }
        for x in [7, 6, 5, 4, 3, 2, 1, 0, 9, 8] { body.append(SnakePoint(x, 5)) }
        XCTAssertEqual(Set(body).count, body.count, "a real snake: no cell twice")
        let p = SnakePath.centres(body: body, vacated: nil, fraction: 1, columns: 10, rows: 10)
        XCTAssertLessThan(p.last?.x ?? 0, -10, "the tail unwraps past one whole board")
        let shifts = SnakePath.copies(of: p, columns: 10, rows: 10)
        XCTAssertEqual(shifts.first, SnakeVec(0, 0))
        XCTAssertTrue(shifts.contains(SnakeVec(10, 0)))
        XCTAssertTrue(shifts.contains(SnakeVec(20, 0)), "the far end is brought back two boards")
        // Every point lands on the board in at least one copy.
        for v in p {
            let seen = shifts.contains { s in
                let x = v.x + s.x, y = v.y + s.y
                return x >= 0 && x <= 10 && y >= 0 && y <= 10
            }
            XCTAssertTrue(seen, "\(v) is drawn somewhere")
        }
    }

    func testPathUnwrapsVertically() {
        let body = [SnakePoint(3, 9), SnakePoint(3, 0), SnakePoint(3, 1)]
        let p = SnakePath.centres(body: body, vacated: nil, fraction: 1, columns: 10, rows: 10)
        XCTAssertEqual(p, [SnakeVec(3.5, 9.5), SnakeVec(3.5, 10.5), SnakeVec(3.5, 11.5)])
    }

    func testSplitTapersTheLastCells() {
        let points = (0..<6).map { SnakeVec(Double($0) + 0.5, 2.5) }
        let parts = SnakePath.split(points, tail: 1.5, spacing: 0.25)
        XCTAssertEqual(parts.body.last?.x ?? 0, 4.0, accuracy: 1e-9)
        XCTAssertEqual(SnakePath.length(parts.body), 3.5, accuracy: 1e-9)
        XCTAssertEqual(parts.tail.first?.x ?? 0, 4.0, accuracy: 1e-9)
        XCTAssertEqual(parts.tail.last, SnakeVec(5.5, 2.5))
        XCTAssertGreaterThanOrEqual(parts.tail.count, 6)
        let short = SnakePath.split([SnakeVec(0, 0), SnakeVec(1, 0)], tail: 3, spacing: 0.25)
        XCTAssertEqual(short.body.count, 2, "too short to taper: all body")
        XCTAssertTrue(short.tail.isEmpty)
    }

    func testHeadTurnsTheShortWayRound() {
        let end = SnakePath.angle(from: .left, to: .up, fraction: 1)
        XCTAssertEqual(cos(end), 0, accuracy: 1e-9)
        XCTAssertEqual(sin(end), -1, accuracy: 1e-9, "ends facing up")
        let mid = SnakePath.angle(from: .left, to: .up, fraction: 0.5)
        XCTAssertGreaterThan(mid, Double.pi, "left (π) to up turns on through 5π/4, not back through 0")
        XCTAssertEqual(SnakePath.angle(from: .right, to: .down, fraction: 0), 0, accuracy: 1e-9)
    }
}
