import XCTest
@testable import SRAppleApp

final class Merge2048LogicTests: XCTestCase {

    // MARK: - Helpers

    private func slid(_ rows: [[Int]], _ direction: Merge2048Direction) -> (rows: [[Int]], gained: Int, changed: Bool) {
        let side = rows.count
        let result = Merge2048Engine.slide(Merge2048Engine.tiles(from: rows), side: side, direction: direction)
        return (Merge2048Engine.grid(result.tiles, side: side), result.gained, result.changed)
    }

    /// Mirror left to right.
    private func mirror(_ rows: [[Int]]) -> [[Int]] { rows.map { Array($0.reversed()) } }

    private func transpose(_ rows: [[Int]]) -> [[Int]] {
        let n = rows.count
        return (0..<n).map { c in (0..<n).map { r in rows[r][c] } }
    }

    /// A quarter turn clockwise.
    private func rotate(_ rows: [[Int]]) -> [[Int]] { mirror(transpose(rows)) }

    private func randomRows(side: Int, seed: UInt64) -> [[Int]] {
        var random = Merge2048Random(seed: seed)
        return (0..<side).map { _ in
            (0..<side).map { _ in
                let roll = random.below(6)
                return roll < 2 ? 0 : 2 << random.below(4)
            }
        }
    }

    // MARK: - One line

    func testFourTwosMakeTwoFours() {
        let line = Merge2048Engine.slideLine([2, 2, 2, 2])
        XCTAssertEqual(line.values, [4, 4, 0, 0])
        XCTAssertEqual(line.gained, 8)
    }

    func testAMergedTileDoesNotMergeAgainInTheSameMove() {
        let line = Merge2048Engine.slideLine([2, 2, 4, 0])
        XCTAssertEqual(line.values, [4, 4, 0, 0], "not 8")
        XCTAssertEqual(line.gained, 4)
    }

    func testPairsMergeSeparately() {
        let line = Merge2048Engine.slideLine([4, 4, 8, 8])
        XCTAssertEqual(line.values, [8, 16, 0, 0])
        XCTAssertEqual(line.gained, 24)
    }

    func testGapsCloseAndTheFrontPairMergesFirst() {
        XCTAssertEqual(Merge2048Engine.slideLine([0, 2, 0, 2]).values, [4, 0, 0, 0])
        XCTAssertEqual(Merge2048Engine.slideLine([2, 2, 2, 0]).values, [4, 2, 0, 0])
        XCTAssertEqual(Merge2048Engine.slideLine([0, 0, 0, 2]).values, [2, 0, 0, 0])
        XCTAssertEqual(Merge2048Engine.slideLine([2, 4, 2, 4]).values, [2, 4, 2, 4])
        XCTAssertEqual(Merge2048Engine.slideLine([8, 0, 8, 8, 8]).values, [16, 16, 0, 0, 0])
    }

    func testRightSlideMergesFromTheRightWall() {
        let result = slid([[2, 2, 2, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], .right)
        XCTAssertEqual(result.rows[0], [0, 0, 2, 4])
    }

    // MARK: - Ids and animation hand-off

    func testTilesKeepTheirIdsAndTheFrontTileSurvivesAMerge() {
        let tiles = [
            Merge2048Tile(id: 7, value: 2, row: 0, col: 1),
            Merge2048Tile(id: 9, value: 2, row: 0, col: 3),
            Merge2048Tile(id: 4, value: 8, row: 2, col: 2),
        ]
        let result = Merge2048Engine.slide(tiles, side: 4, direction: .left)
        XCTAssertEqual(result.tiles.count, 2)
        let survivor = result.tiles.first { $0.id == 7 }
        XCTAssertEqual(survivor?.value, 4)
        XCTAssertEqual(survivor?.col, 0)
        XCTAssertEqual(result.consumed.map(\.id), [9])
        XCTAssertEqual(result.consumed.first?.col, 0, "the merged-away tile slides onto the survivor")
        XCTAssertEqual(result.tiles.first { $0.id == 4 }?.col, 0)
        XCTAssertEqual(result.merges, [Merge2048Merge(row: 0, col: 0, value: 4, survivorId: 7, consumedId: 9)])
    }

    // MARK: - Moves and spawns

    func testNoMoveMeansNoSpawn() {
        var state = Merge2048State(side: 4, target: 2048,
                                   rows: [[2, 4, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], seed: 3)
        let before = state
        XCTAssertNil(state.move(.left))
        XCTAssertNil(state.move(.up))
        XCTAssertEqual(state, before)
        XCTAssertEqual(state.tiles.count, 2)
        XCTAssertFalse(state.canUndo)
    }

    func testAMoveSpawnsExactlyOneTwoOrFourOnAnEmptyCell() {
        for seed in UInt64(1)...200 {
            var state = Merge2048State(side: 4, target: 2048,
                                       rows: [[2, 4, 8, 16], [0, 0, 0, 0], [32, 0, 0, 0], [0, 0, 0, 64]], seed: seed)
            let slide = Merge2048Engine.slide(state.tiles, side: 4, direction: .right)
            let empty = Set(Merge2048Engine.emptyCells(slide.tiles, side: 4))
            guard let turn = state.move(.right), let spawned = turn.spawned else {
                return XCTFail("a changing move spawns")
            }
            XCTAssertTrue(empty.contains(spawned.cell), "seed \(seed): spawned on a taken cell")
            XCTAssertTrue(spawned.value == 2 || spawned.value == 4)
            XCTAssertEqual(state.tiles.count, slide.tiles.count + 1)
            XCTAssertEqual(Set(state.tiles.map(\.cell)).count, state.tiles.count, "two tiles on one cell")
        }
    }

    func testSpawnsAreMostlyTwos() {
        var random = Merge2048Random(seed: 42)
        var fours = 0
        for _ in 0..<10_000 where random.unit() >= 0.9 { fours += 1 }
        XCTAssertGreaterThan(fours, 800)
        XCTAssertLessThan(fours, 1200)
    }

    func testANewGameHasTwoTiles() {
        for size in Merge2048Size.allCases {
            let state = Merge2048State(size: size, seed: 11)
            XCTAssertEqual(state.tiles.count, 2)
            XCTAssertEqual(state.side, size.side)
            XCTAssertTrue(state.tiles.allSatisfy { $0.value == 2 || $0.value == 4 })
            XCTAssertNotEqual(state.tiles[0].cell, state.tiles[1].cell)
        }
    }

    func testScoreAddsMergedValues() {
        var state = Merge2048State(side: 4, target: 2048,
                                   rows: [[4, 4, 8, 8], [2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], seed: 1)
        let turn = state.move(.left)
        XCTAssertEqual(turn?.gained, 8 + 16 + 4)
        XCTAssertEqual(state.score, 28)
        XCTAssertEqual(Array(state.rows[0].prefix(2)), [8, 16])
        XCTAssertEqual(state.rows[1][0], 4)
        XCTAssertEqual(turn?.newBiggest, 16)
    }

    // MARK: - The end

    func testAFullBoardWithNoPairsIsOver() {
        let rows = [[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 2, 4, 2]]
        let state = Merge2048State(side: 4, target: 2048, rows: rows, seed: 1)
        XCTAssertTrue(state.isOver)
        XCTAssertFalse(Merge2048Engine.canMove(state.tiles, side: 4))
        for direction in Merge2048Direction.allCases {
            XCTAssertFalse(slid(rows, direction).changed)
        }
    }

    func testAFullBoardWithAPairIsNotOver() {
        let across = [[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 2, 8, 8]]
        XCTAssertFalse(Merge2048State(side: 4, target: 2048, rows: across, seed: 1).isOver)
        let down = [[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 8], [4, 2, 4, 8]]
        XCTAssertFalse(Merge2048State(side: 4, target: 2048, rows: down, seed: 1).isOver)
        let gap = [[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 0, 4], [4, 2, 4, 2]]
        XCTAssertFalse(Merge2048State(side: 4, target: 2048, rows: gap, seed: 1).isOver)
    }

    func testTheLastMoveReportsTheGameOver() {
        // Merging the 8s leaves one gap; the spawn fills it with a 2 or a 4
        // that matches nothing beside it.
        var state = Merge2048State(side: 3, target: 512,
                                   rows: [[8, 8, 64], [32, 128, 256], [16, 256, 32]], seed: 5)
        let turn = state.move(.left)
        XCTAssertNotNil(turn)
        XCTAssertEqual(turn?.over, true)
        XCTAssertTrue(state.isOver)
    }

    func testReachingTheTargetWinsOnceAndPlayCarriesOn() {
        var state = Merge2048State(side: 4, target: 2048,
                                   rows: [[1024, 1024, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [2, 0, 0, 0]], seed: 9)
        XCTAssertFalse(state.hasWon)
        let turn = state.move(.left)
        XCTAssertEqual(turn?.reachedTarget, true)
        XCTAssertTrue(state.hasWon)
        let next = state.move(.right) ?? state.move(.down)
        XCTAssertEqual(next?.reachedTarget, false, "the win card is shown once")
    }

    // MARK: - Undo

    func testUndoRestoresTheBoardScoreAndSpawnOnce() {
        var state = Merge2048State(size: .classic, seed: 77)
        let start = state
        var moved: Merge2048Turn?
        for direction in Merge2048Direction.allCases where moved == nil {
            moved = state.move(direction)
        }
        XCTAssertNotNil(moved)
        XCTAssertTrue(state.canUndo)
        XCTAssertTrue(state.undo())
        XCTAssertEqual(state.tiles, start.tiles)
        XCTAssertEqual(state.score, start.score)
        XCTAssertEqual(state.moves, 0)
        XCTAssertEqual(state.random, start.random, "the spawn winds back too")
        XCTAssertFalse(state.canUndo)
        XCTAssertFalse(state.undo(), "one undo per move")
        XCTAssertEqual(state.undosUsed, 1)
    }

    func testUndoUnwindsAWin() {
        var state = Merge2048State(side: 4, target: 2048,
                                   rows: [[1024, 1024, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], seed: 2)
        _ = state.move(.left)
        XCTAssertTrue(state.hasWon)
        state.undo()
        XCTAssertFalse(state.hasWon)
        XCTAssertEqual(state.score, 0)
    }

    func testRedoingAnUndoneMoveSpawnsTheSameTile() {
        var state = Merge2048State(side: 4, target: 2048,
                                   rows: [[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], seed: 123)
        let first = state.move(.left)?.spawned
        state.undo()
        let second = state.move(.left)?.spawned
        XCTAssertEqual(first?.cell, second?.cell)
        XCTAssertEqual(first?.value, second?.value)
    }

    // MARK: - Determinism

    func testTheSameSeedPlaysTheSameGame() {
        let script: [Merge2048Direction] = [.left, .up, .right, .down, .left, .left, .up, .right, .down, .down,
                                            .left, .up, .up, .right, .left, .down, .right, .up, .left, .down]
        func play(_ seed: UInt64) -> Merge2048State {
            var state = Merge2048State(size: .classic, seed: seed)
            for _ in 0..<5 {
                for direction in script { state.move(direction) }
            }
            return state
        }
        XCTAssertEqual(play(2048), play(2048))
        XCTAssertNotEqual(play(2048).tiles, play(2049).tiles)
    }

    func testTheGeneratorIsStable() {
        var a = Merge2048Random(seed: 1)
        var b = Merge2048Random(seed: 1)
        for _ in 0..<100 { XCTAssertEqual(a.next(), b.next()) }
        var c = Merge2048Random(seed: 0)
        XCTAssertNotEqual(c.next(), 0)
        for _ in 0..<1000 {
            let n = c.below(7)
            XCTAssertTrue((0..<7).contains(n))
        }
    }

    // MARK: - All four directions are the same rule turned

    func testEveryDirectionIsLeftTurned() {
        for seed in UInt64(1)...60 {
            for side in [3, 4, 5] {
                let rows = randomRows(side: side, seed: seed &* 31 &+ UInt64(side))
                let left = slid(rows, .left)
                // Right is left in a mirror.
                let right = slid(rows, .right)
                let mirroredLeft = slid(mirror(rows), .left)
                XCTAssertEqual(right.rows, mirror(mirroredLeft.rows))
                XCTAssertEqual(right.gained, mirroredLeft.gained)
                // Up is left on the transpose.
                let up = slid(rows, .up)
                let transposedLeft = slid(transpose(rows), .left)
                XCTAssertEqual(up.rows, transpose(transposedLeft.rows))
                XCTAssertEqual(up.gained, transposedLeft.gained)
                // Down is left after a quarter turn clockwise, turned back.
                let down = slid(rows, .down)
                let turned = slid(rotate(rows), .left).rows
                XCTAssertEqual(down.rows, rotate(rotate(rotate(turned))))
                // And every line of a left slide is the one-line rule.
                XCTAssertEqual(left.rows, rows.map { Merge2048Engine.slideLine($0).values })
            }
        }
    }

    func testDirectionsKeepTheTotal() {
        for seed in UInt64(1)...40 {
            let rows = randomRows(side: 4, seed: seed)
            let total = rows.flatMap { $0 }.reduce(0, +)
            for direction in Merge2048Direction.allCases {
                XCTAssertEqual(slid(rows, direction).rows.flatMap { $0 }.reduce(0, +), total)
            }
        }
    }

    // MARK: - Sizes, ladder and save

    func testSizesAndTargets() {
        XCTAssertEqual(Merge2048Size.classic.target, 2048)
        XCTAssertEqual(Merge2048Size.relaxed.target, 2048)
        XCTAssertEqual(Merge2048Size.hard.target, 512)
        XCTAssertEqual(Merge2048Size.allCases.map(\.side), [4, 5, 3])
        XCTAssertEqual(Merge2048Ladder.step(2), 1)
        XCTAssertEqual(Merge2048Ladder.step(2048), 11)
        XCTAssertEqual(Merge2048Ladder.milestones(target: 2048), [64, 128, 256, 512, 1024, 2048, 4096])
    }

    func testAGameSurvivesASaveAndALoad() throws {
        var state = Merge2048State(size: .relaxed, seed: UInt64.max - 3)
        state.move(.left)
        state.move(.up)
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(Merge2048State.self, from: data)
        XCTAssertEqual(back, state)
        XCTAssertEqual(back.random, state.random)
        XCTAssertEqual(back.canUndo, state.canUndo)
    }

    func testTheBookKeepsBestsPerSize() {
        guard let defaults = UserDefaults(suiteName: "merge-2048-tests") else { return XCTFail("no suite") }
        defaults.removePersistentDomain(forName: "merge-2048-tests")
        let store = Merge2048Store(defaults: defaults)
        var book = store.loadBook()
        XCTAssertTrue(book.note(size: .classic, score: 500, biggest: 64))
        XCTAssertFalse(book.note(size: .classic, score: 300, biggest: 128))
        XCTAssertTrue(book.note(size: .hard, score: 40, biggest: 16))
        book.finish(size: .classic, won: true)
        store.saveBook(book)
        let back = store.loadBook()
        XCTAssertEqual(back.record(.classic).bestScore, 500)
        XCTAssertEqual(back.record(.classic).biggestTile, 128)
        XCTAssertEqual(back.record(.classic).wins, 1)
        XCTAssertEqual(back.record(.hard).bestScore, 40)
        XCTAssertEqual(back.record(.relaxed), Merge2048Record())

        let game = Merge2048State(size: .hard, seed: 8)
        store.saveGame(game, size: .hard)
        XCTAssertEqual(store.loadGame(.hard), game)
        XCTAssertNil(store.loadGame(.classic))
        store.clearGame(.hard)
        XCTAssertNil(store.loadGame(.hard))
        defaults.removePersistentDomain(forName: "merge-2048-tests")
    }
}
