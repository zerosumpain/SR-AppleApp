import XCTest
@testable import SRAppleApp

/// Tilt Maze's levels: every hand-drawn and generated maze, and fifty
/// endless ones, have a way from the start to the goal round the holes, and
/// no hole ever sits on it.
final class TiltMazeLevelTests: XCTestCase {
    /// Every step of `path` goes through an open side, from start to goal.
    private func assertWalkable(_ path: [TiltMazeCell], in level: TiltMazeLevel, _ label: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(path.first, level.start, "\(label): the way starts at the start", file: file, line: line)
        XCTAssertEqual(path.last, level.goal, "\(label): the way ends at the goal", file: file, line: line)
        for (a, b) in zip(path, path.dropFirst()) {
            XCTAssertTrue(level.isOpen(a, b), "\(label): \(a) to \(b) goes through a wall", file: file, line: line)
        }
    }

    private func assertSound(_ level: TiltMazeLevel, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let path = level.solution else {
            XCTFail("\(label): no way from the start to the goal round the holes", file: file, line: line)
            return
        }
        assertWalkable(path, in: level, label, file: file, line: line)
        let holes = Set(level.holes)
        for cell in path {
            XCTAssertFalse(holes.contains(cell), "\(label): a hole on the way through at \(cell)", file: file, line: line)
        }
        XCTAssertFalse(holes.contains(level.start), "\(label): a hole on the start", file: file, line: line)
        XCTAssertFalse(holes.contains(level.goal), "\(label): a hole on the goal", file: file, line: line)
        for flag in level.checkpoints {
            XCTAssertTrue(path.contains(flag), "\(label): flag \(flag) is off the way through", file: file, line: line)
        }
        for hole in level.holes {
            XCTAssertTrue(level.contains(hole), "\(label): hole \(hole) is off the board", file: file, line: line)
        }
        XCTAssertNotEqual(level.start, level.goal, "\(label): start and goal are the same cell", file: file, line: line)
    }

    // MARK: - The campaign

    func testEveryHandLevelParses() {
        XCTAssertEqual(TiltMazeCatalogue.handBuiltCount, 10)
        for (i, drawn) in TiltMazeCatalogue.hand.enumerated() {
            let level = TiltMazeLevel.parse(drawn.map)
            XCTAssertNotNil(level, "hand level \(i + 1) does not parse")
            let info = TiltMazeCatalogue.info(i + 1)
            XCTAssertEqual(level?.cols, info.cols, "hand level \(i + 1)")
            XCTAssertEqual(level?.rows, info.rows, "hand level \(i + 1)")
            XCTAssertFalse(drawn.name.isEmpty)
            XCTAssertFalse(drawn.tip.isEmpty)
        }
    }

    func testEveryCampaignLevelHasAWayRoundTheHoles() {
        for n in 1...TiltMazeCatalogue.campaignCount {
            assertSound(TiltMazeCatalogue.level(n), "level \(n)")
        }
    }

    func testFiftyEndlessMazesHaveAWayRoundTheHoles() {
        for seed in 1...50 {
            let depth = (seed * 7) % 24
            let level = TiltMazeCatalogue.endless(depth: depth, seed: UInt64(seed) &* 0x9E37_79B9)
            assertSound(level, "endless seed \(seed) depth \(depth)")
        }
    }

    func testHolesSitOffTheWayEvenWhenTheyAreIgnored() {
        // The way the generator kept clear is still the shortest way when
        // holes are walked straight over: holes never shorten a level.
        for n in (TiltMazeCatalogue.handBuiltCount + 1)...TiltMazeCatalogue.campaignCount {
            let level = TiltMazeCatalogue.level(n)
            let round = level.solution?.count ?? 0
            let over = level.path(from: level.start, to: level.goal, avoidingHoles: false)?.count ?? 0
            XCTAssertEqual(round, over, "level \(n)")
        }
    }

    func testGeneratedLevelsAreTheSameEveryTime() {
        XCTAssertEqual(TiltMazeCatalogue.level(23), TiltMazeCatalogue.level(23))
        XCTAssertEqual(TiltMazeCatalogue.endless(depth: 5, seed: 99), TiltMazeCatalogue.endless(depth: 5, seed: 99))
        XCTAssertNotEqual(TiltMazeCatalogue.endless(depth: 5, seed: 99), TiltMazeCatalogue.endless(depth: 5, seed: 100))
    }

    func testTheCampaignGrowsAndGetsHolier() {
        var cols = 0, holes = -1.0
        for n in (TiltMazeCatalogue.handBuiltCount + 1)...TiltMazeCatalogue.campaignCount {
            let recipe = TiltMazeCatalogue.recipe(campaign: n)
            XCTAssertGreaterThanOrEqual(recipe.cols, cols, "level \(n)")
            XCTAssertGreaterThan(recipe.holeShare, holes, "level \(n)")
            XCTAssertGreaterThan(recipe.rows, recipe.cols, "level \(n) is taller than wide")
            cols = recipe.cols
            holes = recipe.holeShare
        }
        XCTAssertEqual(TiltMazeCatalogue.recipe(campaign: 11).cols, 6)
        XCTAssertEqual(TiltMazeCatalogue.recipe(campaign: 40).cols, 12)
        XCTAssertEqual(TiltMazeCatalogue.level(40).cols, 12)
        XCTAssertGreaterThan(TiltMazeCatalogue.level(40).holes.count, TiltMazeCatalogue.level(11).holes.count)
    }

    func testEndlessGrowsAndStopsGrowing() {
        XCTAssertEqual(TiltMazeCatalogue.endlessRecipe(depth: 0).cols, 6)
        XCTAssertLessThanOrEqual(TiltMazeCatalogue.endlessRecipe(depth: 500).cols, 12)
        XCTAssertLessThanOrEqual(TiltMazeCatalogue.endlessRecipe(depth: 500).holeShare, 0.16)
        XCTAssertGreaterThan(TiltMazeCatalogue.endlessRecipe(depth: 10).cols, TiltMazeCatalogue.endlessRecipe(depth: 0).cols)
    }

    func testNoGeneratedHoleBesideTheStart() {
        for n in (TiltMazeCatalogue.handBuiltCount + 1)...TiltMazeCatalogue.campaignCount {
            let level = TiltMazeCatalogue.level(n)
            for side in level.neighbours(of: level.start) {
                XCTAssertFalse(level.holeSet.contains(side), "level \(n): a hole beside the start")
            }
        }
    }

    func testLongMazesHaveCheckpoints() {
        let level = TiltMazeCatalogue.level(40)
        XCTAssertFalse(level.checkpoints.isEmpty)
        XCTAssertTrue(TiltMazeCatalogue.level(1).checkpoints.isEmpty)
        XCTAssertEqual(TiltMazeCatalogue.level(5).checkpoints.count, 1)
    }

    func testEveryLevelHasANameAndATip() {
        var names = Set<String>()
        for n in 1...TiltMazeCatalogue.campaignCount {
            let info = TiltMazeCatalogue.info(n)
            XCTAssertEqual(info.number, n)
            XCTAssertFalse(info.name.isEmpty)
            XCTAssertFalse(info.tip.isEmpty)
            names.insert(info.name)
        }
        XCTAssertEqual(names.count, TiltMazeCatalogue.campaignCount, "every level has its own name")
    }

    // MARK: - Walls

    func testOuterWallsAreAlwaysThere() {
        let open = TiltMazeLevel(cols: 3, rows: 3, vertical: [Bool](repeating: false, count: 12),
                                 horizontal: [Bool](repeating: false, count: 12),
                                 start: TiltMazeCell(0, 0), goal: TiltMazeCell(2, 2), holes: [], checkpoints: [])
        XCTAssertFalse(open.isOpen(TiltMazeCell(0, 0), TiltMazeCell(-1, 0)))
        XCTAssertTrue(open.isOpen(TiltMazeCell(0, 0), TiltMazeCell(1, 0)))
        XCTAssertTrue(open.wallWest(0, 1))
        XCTAssertTrue(open.wallWest(3, 1))
        XCTAssertTrue(open.wallNorth(1, 0))
        XCTAssertTrue(open.wallNorth(1, 3))
        // Four merged runs: the board's four sides.
        XCTAssertEqual(open.boxes.count, 4)
    }

    func testParseReadsWallsHolesAndFlags() throws {
        let level = try XCTUnwrap(TiltMazeLevel.parse([
            "+-+-+",
            "|S|O|",
            "+ + +",
            "|C G|",
            "+-+-+",
        ]))
        XCTAssertEqual(level.cols, 2)
        XCTAssertEqual(level.rows, 2)
        XCTAssertEqual(level.start, TiltMazeCell(0, 0))
        XCTAssertEqual(level.goal, TiltMazeCell(1, 1))
        XCTAssertEqual(level.holes, [TiltMazeCell(1, 0)])
        XCTAssertEqual(level.checkpoints, [TiltMazeCell(0, 1)])
        XCTAssertFalse(level.isOpen(TiltMazeCell(0, 0), TiltMazeCell(1, 0)))
        XCTAssertTrue(level.isOpen(TiltMazeCell(0, 0), TiltMazeCell(0, 1)))
        XCTAssertEqual(level.solution, [TiltMazeCell(0, 0), TiltMazeCell(0, 1), TiltMazeCell(1, 1)])
        XCTAssertNil(TiltMazeLevel.parse(["+-+", "| |", "+-+"]), "no start or goal")
        XCTAssertNil(TiltMazeLevel.parse(["+-+-+", "|S G|", "+-+"]), "ragged")
    }

    // MARK: - Stars

    func testStarThresholdsAreMonotonic() {
        for n in 1...TiltMazeCatalogue.campaignCount {
            let par = TiltMazePar.of(TiltMazeCatalogue.level(n))
            XCTAssertGreaterThan(par.three, 0, "level \(n)")
            XCTAssertLessThan(par.three, par.two, "level \(n)")
            var last = 3
            var t = 0.0
            while t < par.two * 3 {
                let stars = par.stars(for: t)
                XCTAssertLessThanOrEqual(stars, last, "level \(n) at \(t)s")
                XCTAssertTrue((1...3).contains(stars))
                last = stars
                t += 0.25
            }
            XCTAssertEqual(par.stars(for: par.three), 3)
            XCTAssertEqual(par.stars(for: par.two), 2)
            XCTAssertEqual(par.stars(for: par.two + 0.01), 1)
        }
    }

    func testLongerMazesGiveMoreTime() {
        let small = TiltMazePar.of(TiltMazeCatalogue.level(11))
        let big = TiltMazePar.of(TiltMazeCatalogue.level(40))
        XCTAssertGreaterThan(big.three, small.three)
    }

    // MARK: - The book

    func testTheBookKeepsTheBestAndOpensLevelsInOrder() {
        var book = TiltMazeBook()
        XCTAssertEqual(book.unlocked, 1)
        XCTAssertTrue(book.isOpen(1))
        XCTAssertFalse(book.isOpen(2))
        let first = book.recordClear(level: 1, time: 20, stars: 2)
        XCTAssertTrue(first.newStars)
        XCTAssertFalse(first.newBestTime, "a first finish is not a beaten best")
        XCTAssertEqual(book.unlocked, 2)
        let slower = book.recordClear(level: 1, time: 25, stars: 1)
        XCTAssertFalse(slower.newBestTime)
        XCTAssertFalse(slower.newStars)
        XCTAssertEqual(book.stars(for: 1), 2, "stars never go down")
        XCTAssertEqual(book.bestTime(for: 1), 20)
        let faster = book.recordClear(level: 1, time: 12, stars: 3)
        XCTAssertTrue(faster.newBestTime)
        XCTAssertEqual(book.stars(for: 1), 3)
        XCTAssertEqual(book.totalStars, 3)
        XCTAssertEqual(book.mazesCleared, 3)
        XCTAssertTrue(book.recordEndless(mazes: 4))
        XCTAssertFalse(book.recordEndless(mazes: 2))
        XCTAssertEqual(book.endlessBest, 4)
        XCTAssertEqual(book.endlessRuns, 2)
    }

    func testTheBookSurvivesTheStoreAndOldData() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "tilt-maze-tests"))
        defaults.removePersistentDomain(forName: "tilt-maze-tests")
        let store = TiltMazeStore(defaults: defaults)
        XCTAssertEqual(store.load(), TiltMazeBook())
        var book = TiltMazeBook()
        book.recordClear(level: 3, time: 9.5, stars: 3)
        book.recordFall()
        store.save(book)
        XCTAssertEqual(store.load(), book)
        XCTAssertTrue(TiltMazeStore.key.hasPrefix("tilt-maze"))
        // A book missing fields (an older app) still opens.
        let old = try JSONDecoder().decode(TiltMazeBook.self, from: Data(#"{"endlessBest": 7}"#.utf8))
        XCTAssertEqual(old.endlessBest, 7)
        XCTAssertEqual(old.unlocked, 1)
        defaults.removePersistentDomain(forName: "tilt-maze-tests")
    }
}
