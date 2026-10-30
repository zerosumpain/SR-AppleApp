import XCTest
@testable import SRAppleApp

final class SnakeLogicTests: XCTestCase {
    private func line(_ cells: [(Int, Int)]) -> [SnakePoint] { cells.map { SnakePoint($0.0, $0.1) } }

    private func game(_ mode: SnakeMode = .classic, body: [(Int, Int)], heading: SnakeDirection = .right,
                      food: (Int, Int)? = (0, 0), walls: Set<SnakePoint> = [], columns: Int = 10, rows: Int = 10,
                      seed: UInt64 = 1) -> SnakeGame {
        SnakeGame(mode: mode, columns: columns, rows: rows, walls: walls, body: line(body), heading: heading,
                  food: food.map { SnakePoint($0.0, $0.1) }, seed: seed)
    }

    // MARK: - Moving

    func testStartsInTheMiddleFacingRight() {
        let g = SnakeGame(mode: .classic, seed: 4)
        XCTAssertEqual(g.length, SnakeRules.startLength)
        XCTAssertEqual(g.heading, .right)
        XCTAssertEqual(g.body, line([(6, 8), (5, 8), (4, 8)]))
        XCTAssertNotNil(g.food)
        XCTAssertFalse(g.isOver)
    }

    func testMovesOneCellAndTheTailFollows() {
        var g = game(body: [(4, 4), (3, 4), (2, 4)])
        let r = g.step()
        XCTAssertNil(r.died)
        XCTAssertEqual(g.body, line([(5, 4), (4, 4), (3, 4)]))
        XCTAssertEqual(g.vacated, SnakePoint(2, 4))
        XCTAssertEqual(g.steps, 1)
    }

    func testWrapModeComesBackOnTheOtherSide() {
        var g = game(.wrap, body: [(9, 4), (8, 4), (7, 4)])
        XCTAssertNil(g.step().died)
        XCTAssertEqual(g.head, SnakePoint(0, 4))
        var up = game(.wrap, body: [(3, 0), (3, 1), (3, 2)], heading: .up)
        XCTAssertNil(up.step().died)
        XCTAssertEqual(up.head, SnakePoint(3, 9))
        var left = game(.wrap, body: [(0, 5), (1, 5), (2, 5)], heading: .left)
        _ = left.step()
        XCTAssertEqual(left.head, SnakePoint(9, 5))
        var down = game(.wrap, body: [(6, 9), (6, 8), (6, 7)], heading: .down)
        _ = down.step()
        XCTAssertEqual(down.head, SnakePoint(6, 0))
    }

    func testMazeModeWrapsToo() {
        var g = game(.maze, body: [(9, 4), (8, 4), (7, 4)])
        XCTAssertNil(g.step().died)
        XCTAssertEqual(g.head, SnakePoint(0, 4))
    }

    // MARK: - Eating

    func testEatingScoresAndGrowsByOneOnTheNextStep() {
        var g = game(body: [(4, 4), (3, 4), (2, 4)], food: (5, 4))
        let r = g.step()
        XCTAssertEqual(r.ate, SnakePoint(5, 4))
        XCTAssertEqual(g.score, SnakeRules.applePoints)
        XCTAssertEqual(g.eaten, 1)
        XCTAssertEqual(g.length, 3, "the tail still moves on the step that eats")
        XCTAssertNotEqual(g.food, SnakePoint(5, 4))
        _ = g.step()
        XCTAssertEqual(g.length, 4)
        XCTAssertNil(g.vacated, "the tail stayed put to grow")
        _ = g.step()
        XCTAssertEqual(g.length, 4, "one apple, one cell")
        XCTAssertNotNil(g.vacated)
    }

    func testSpeedsUpAsItEats() {
        var g = game(body: [(4, 4), (3, 4), (2, 4)], food: (5, 4))
        let before = g.stepInterval
        _ = g.step()
        XCTAssertLessThan(g.stepInterval, before)
    }

    // MARK: - Dying

    func testClassicEdgeKills() {
        var g = game(body: [(9, 4), (8, 4), (7, 4)])
        let r = g.step()
        XCTAssertEqual(r.died, .edge)
        XCTAssertEqual(g.death, .edge)
        XCTAssertTrue(g.isOver)
        XCTAssertEqual(g.head, SnakePoint(9, 4), "it stops where it hit")
        XCTAssertEqual(g.step(), SnakeStepResult(), "nothing happens after the end")
    }

    func testClassicEdgeKillsOnEverySide() {
        var top = game(body: [(3, 0), (3, 1), (3, 2)], heading: .up)
        XCTAssertEqual(top.step().died, .edge)
        var left = game(body: [(0, 3), (1, 3), (2, 3)], heading: .left)
        XCTAssertEqual(left.step().died, .edge)
        var bottom = game(body: [(3, 9), (3, 8), (3, 7)], heading: .down)
        XCTAssertEqual(bottom.step().died, .edge)
    }

    func testMazeWallKills() {
        var g = game(.maze, body: [(4, 4), (3, 4), (2, 4)], walls: [SnakePoint(5, 4)])
        XCTAssertEqual(g.step().died, .wall)
        XCTAssertEqual(g.death, .wall)
    }

    func testBitingYourselfKills() {
        // A hook: head at (4,4) going up, body curling round beneath it.
        var g = game(body: [(4, 4), (4, 5), (5, 5), (5, 4), (5, 3), (4, 3), (3, 3)], heading: .left)
        XCTAssertTrue(g.turn(.up))
        XCTAssertEqual(g.step().died, .tail)
        XCTAssertEqual(g.death, .tail)
    }

    func testChasingTheTailIsAllowedBecauseItMovesAway() {
        // A 2x2 loop: the head steps into the cell the tail is leaving.
        var g = game(body: [(4, 4), (4, 5), (5, 5), (5, 4)], heading: .up)
        XCTAssertTrue(g.turn(.right))
        XCTAssertNil(g.step().died)
        XCTAssertEqual(g.head, SnakePoint(5, 4))
    }

    func testTheTailCellIsSolidWhileGrowing() {
        // Eat at (4,4) going up, which leaves a 2x2 loop; the tail at (5,4)
        // stays put on the next step to grow, so stepping into it bites.
        var g = game(body: [(4, 5), (5, 5), (5, 4), (5, 3)], heading: .left, food: (4, 4))
        XCTAssertTrue(g.turn(.up))
        XCTAssertEqual(g.step().ate, SnakePoint(4, 4))
        XCTAssertEqual(g.body, line([(4, 4), (4, 5), (5, 5), (5, 4)]))
        XCTAssertEqual(g.growth, 1)
        XCTAssertTrue(g.turn(.right))
        XCTAssertEqual(g.step().died, .tail)
    }

    // MARK: - Turning

    func testReverseTurnIgnored() {
        var g = game(body: [(4, 4), (3, 4), (2, 4)])
        XCTAssertFalse(g.turn(.left))
        XCTAssertFalse(g.turn(.right), "already going that way")
        XCTAssertTrue(g.turns.isEmpty)
        _ = g.step()
        XCTAssertEqual(g.heading, .right)
        XCTAssertNil(g.death)
    }

    func testTwoQuickTurnsBothRegister() {
        var g = game(.wrap, body: [(4, 4), (3, 4), (2, 4)])
        XCTAssertTrue(g.turn(.up))
        XCTAssertTrue(g.turn(.left), "checked against the queued up, not the current right")
        XCTAssertEqual(g.turns, [.up, .left])
        _ = g.step()
        XCTAssertEqual(g.head, SnakePoint(4, 3))
        XCTAssertEqual(g.heading, .up)
        _ = g.step()
        XCTAssertEqual(g.head, SnakePoint(3, 3))
        XCTAssertEqual(g.heading, .left)
        XCTAssertNil(g.death, "a U-turn in two swipes, without biting")
    }

    func testQueuedReverseOfTheQueuedTurnIsIgnored() {
        var g = game(body: [(4, 4), (3, 4), (2, 4)])
        XCTAssertTrue(g.turn(.up))
        XCTAssertFalse(g.turn(.down))
        XCTAssertFalse(g.turn(.up))
        XCTAssertEqual(g.turns, [.up])
    }

    func testTurnBufferIsCapped() {
        var g = game(body: [(4, 4), (3, 4), (2, 4)])
        XCTAssertTrue(g.turn(.up))
        XCTAssertTrue(g.turn(.right))
        XCTAssertTrue(g.turn(.down))
        XCTAssertFalse(g.turn(.right), "full")
        XCTAssertEqual(g.turns.count, SnakeRules.maxQueuedTurns)
        XCTAssertEqual(g.nextHeading, .up)
    }

    func testOneTurnUsedPerStep() {
        var g = game(.wrap, body: [(4, 4), (3, 4), (2, 4)])
        g.turn(.down)
        g.turn(.left)
        let first = g.step()
        XCTAssertTrue(first.turned)
        XCTAssertEqual(g.turns, [.left])
        XCTAssertEqual(g.previousHeading, .right)
        _ = g.step()
        XCTAssertTrue(g.turns.isEmpty)
        XCTAssertFalse(g.step().turned)
    }

    // MARK: - Apples

    func testFoodNeverOnTheSnakeOrAWall() {
        for seed in UInt64(1)...200 {
            let maze = SnakeMaze.all[Int(seed) % SnakeMaze.all.count]
            let g = SnakeGame(mode: .maze, maze: maze, seed: seed)
            guard let food = g.food else { return XCTFail("no food") }
            XCTAssertFalse(g.body.contains(food))
            XCTAssertFalse(g.walls.contains(food))
        }
    }

    func testFoodRespawnsClearOfTheSnakeAndWallsAsItPlays() {
        var seed: UInt64 = 11
        for maze in SnakeMaze.all {
            var g = SnakeGame(mode: .maze, maze: maze, seed: seed)
            seed += 1
            var guardSteps = 0
            while !g.isOver && guardSteps < 3000 {
                g.turn(SnakeAutopilot.choose(g))
                _ = g.step()
                guardSteps += 1
                if let food = g.food {
                    XCTAssertFalse(g.body.contains(food), "food on the snake in \(maze.name)")
                    XCTAssertFalse(g.walls.contains(food), "food on a wall in \(maze.name)")
                    XCTAssertNotEqual(food, g.golden?.at)
                }
                if let gold = g.golden {
                    XCTAssertFalse(g.body.contains(gold.at))
                    XCTAssertFalse(g.walls.contains(gold.at))
                }
            }
            XCTAssertGreaterThan(g.eaten, 0, "the autopilot should eat something in \(maze.name)")
        }
    }

    func testFoodFillsTheOnlyFreeCell() {
        // A 2x2 board with a 3-long snake: one free cell.
        let g = SnakeGame(mode: .wrap, columns: 2, rows: 2, walls: [],
                          body: line([(0, 0), (1, 0), (1, 1)]), heading: .down, food: nil, seed: 9)
        XCTAssertEqual(g.food, SnakePoint(0, 1))
    }

    func testFillingTheBoardWins() {
        var g = SnakeGame(mode: .wrap, columns: 2, rows: 2, walls: [],
                          body: line([(0, 0), (1, 0), (1, 1)]), heading: .left, food: SnakePoint(0, 1), seed: 9)
        g.turn(.down)
        let r = g.step()
        XCTAssertEqual(r.ate, SnakePoint(0, 1))
        XCTAssertTrue(r.filled)
        XCTAssertTrue(g.filled)
        XCTAssertTrue(g.isOver)
        XCTAssertNil(g.death)
    }

    func testGoldenAppleAppearsByTheSixthAppleAndScoresBig() {
        var g = SnakeGame(mode: .wrap, seed: 3)
        var appeared = false
        var steps = 0
        while !appeared && steps < 5000 && !g.isOver {
            g.turn(SnakeAutopilot.choose(g))
            let r = g.step()
            if r.goldenAppeared != nil { appeared = true }
            steps += 1
        }
        XCTAssertTrue(appeared)
        XCTAssertGreaterThanOrEqual(g.eaten, SnakeRules.goldenAfter)
        XCTAssertLessThanOrEqual(g.eaten, SnakeRules.goldenAfter + SnakeRules.goldenAtMost - 1)
        let gold = g.golden
        XCTAssertNotNil(gold)
        XCTAssertEqual(gold?.stepsLeft, SnakeRules.goldenSteps)
    }

    func testGoldenAppleScoresAndDoesNotGrow() {
        var g = game(.wrap, body: [(4, 4), (3, 4), (2, 4)], food: (0, 9))
        g.placeGolden(at: SnakePoint(5, 4))
        let r = g.step()
        XCTAssertEqual(r.ateGolden, SnakePoint(5, 4))
        XCTAssertEqual(g.score, SnakeRules.goldenPoints)
        XCTAssertEqual(g.goldenEaten, 1)
        XCTAssertNil(g.golden)
        _ = g.step()
        XCTAssertEqual(g.length, 3)
    }

    func testGoldenAppleGoesAfterItsTime() {
        var g = game(.wrap, body: [(4, 4), (3, 4), (2, 4)], food: (0, 9))
        g.placeGolden(at: SnakePoint(4, 8))
        var missed = false
        for _ in 0..<SnakeRules.goldenSteps {
            if g.step().goldenMissed { missed = true }
        }
        XCTAssertTrue(missed)
        XCTAssertNil(g.golden)
    }

    // MARK: - Speed

    func testSpeedCurveIsMonotonicAndCapped() {
        var last = SnakeRules.stepInterval(eaten: 0)
        XCTAssertEqual(last, SnakeRules.startInterval, accuracy: 1e-9)
        for eaten in 1...400 {
            let now = SnakeRules.stepInterval(eaten: eaten)
            XCTAssertLessThanOrEqual(now, last)
            XCTAssertGreaterThanOrEqual(now, SnakeRules.fastestInterval)
            last = now
        }
        XCTAssertEqual(SnakeRules.stepInterval(eaten: 400), SnakeRules.fastestInterval, accuracy: 1e-9)
        XCTAssertEqual(SnakeRules.speedLevel(eaten: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(SnakeRules.speedLevel(eaten: 400), 1, accuracy: 1e-9)
        XCTAssertEqual(SnakeRules.stepInterval(eaten: -5), SnakeRules.startInterval, accuracy: 1e-9)
    }

    func testSpeedRampsSmoothly() {
        // No single apple changes the pace by more than a few per cent.
        for eaten in 0..<100 {
            let a = SnakeRules.stepInterval(eaten: eaten), b = SnakeRules.stepInterval(eaten: eaten + 1)
            XCTAssertLessThanOrEqual((a - b) / a, 0.031)
        }
        // And it takes a good run to reach the top.
        XCTAssertGreaterThan(SnakeRules.stepInterval(eaten: 15), SnakeRules.fastestInterval)
    }

    // MARK: - Determinism

    func testSameSeedSameGame() {
        func play(_ seed: UInt64) -> (Int, [SnakePoint], SnakePoint?, Int) {
            var g = SnakeGame(mode: .wrap, seed: seed)
            for _ in 0..<600 where !g.isOver {
                g.turn(SnakeAutopilot.choose(g))
                _ = g.step()
            }
            return (g.score, g.body, g.food, g.steps)
        }
        let a = play(42), b = play(42), c = play(43)
        XCTAssertEqual(a.0, b.0)
        XCTAssertEqual(a.1, b.1)
        XCTAssertEqual(a.2, b.2)
        XCTAssertEqual(a.3, b.3)
        XCTAssertTrue(a.1 != c.1 || a.2 != c.2 || a.0 != c.0, "a different seed should play differently")
    }

    func testRandomIsSeededAndInRange() {
        var a = SnakeRandom(seed: 7), b = SnakeRandom(seed: 7)
        for _ in 0..<100 { XCTAssertEqual(a.next(), b.next()) }
        var r = SnakeRandom(seed: 1)
        var seen = Set<Int>()
        for _ in 0..<1000 {
            let v = r.below(6)
            XCTAssertTrue((0..<6).contains(v))
            seen.insert(v)
        }
        XCTAssertEqual(seen.count, 6)
        XCTAssertEqual(r.below(1), 0)
        XCTAssertEqual(r.below(0), 0)
    }
}
