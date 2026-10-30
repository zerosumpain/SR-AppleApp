import XCTest
@testable import SRAppleApp

final class MinesweeperLogicTests: XCTestCase {

    // MARK: - Levels

    func testStandardFields() {
        var setup = MinesweeperSetup()
        setup.level = .beginner
        XCTAssertEqual([setup.width, setup.height, setup.mines], [9, 9, 10])
        setup.level = .intermediate
        XCTAssertEqual([setup.width, setup.height, setup.mines], [16, 16, 40])
        setup.level = .expert
        XCTAssertEqual([setup.width, setup.height, setup.mines], [16, 30, 99], "Expert stands upright on a phone")
    }

    func testCustomIsClampedAndKeyedBySize() {
        var setup = MinesweeperSetup()
        setup.level = .custom
        setup.customWidth = 2
        setup.customHeight = 99
        setup.customMines = 10_000
        XCTAssertEqual(setup.width, 5)
        XCTAssertEqual(setup.height, 30)
        XCTAssertEqual(setup.mines, 5 * 30 - 9)
        setup.tidyCustom()
        XCTAssertEqual(setup.customMines, 141)
        XCTAssertEqual(setup.recordKey, "custom-5x30-141")
        setup.noGuess = true
        XCTAssertEqual(setup.recordKey, "custom-5x30-141-logic")
    }

    // MARK: - First dig

    func testFirstDigIsSafeWithAClearNeighbourhood() {
        for seed in 0..<60 {
            var rng = MinesweeperRandom(seed: UInt64(seed))
            var board = MinesweeperBoard(width: 16, height: 30, mines: 99)
            let first = Int.random(in: 0..<board.size, using: &rng)
            let outcome = board.firstDig(first, using: &rng)
            XCTAssertNil(outcome.hitMine, "seed \(seed)")
            XCTAssertFalse(board.mines[first])
            for n in board.neighbours(of: first) { XCTAssertFalse(board.mines[n], "seed \(seed): a mine touches the first dig") }
            XCTAssertEqual(board.counts[first], 0)
            XCTAssertGreaterThan(outcome.opened.count, 1, "the first dig opens an area")
            XCTAssertTrue(board.status == .playing || board.status == .won)
        }
    }

    func testMineCountIsExact() {
        for (w, h, m) in [(9, 9, 10), (16, 16, 40), (16, 30, 99), (5, 5, 16), (30, 30, 891)] {
            var rng = MinesweeperRandom(seed: UInt64(w * h + m))
            var board = MinesweeperBoard(width: w, height: h, mines: m)
            board.layMines(sparing: board.size / 2, using: &rng)
            XCTAssertEqual(board.mines.filter { $0 }.count, m, "\(w)×\(h)")
            XCTAssertEqual(board.mineCount, m)
        }
    }

    func testCrowdedFieldStillSparesTheFirstDig() {
        // 5×5 with 24 mines cannot spare the whole neighbourhood: only the dig.
        var rng = MinesweeperRandom(seed: 3)
        var board = MinesweeperBoard(width: 5, height: 5, mines: 24)
        let outcome = board.firstDig(12, using: &rng)
        XCTAssertNil(outcome.hitMine)
        XCTAssertEqual(board.mines.filter { $0 }.count, 24)
        XCTAssertEqual(board.status, .won, "the one safe square was dug")
    }

    func testMinesAreLaidOnce() {
        var rng = MinesweeperRandom(seed: 9)
        var board = MinesweeperBoard(width: 9, height: 9, mines: 10)
        board.layMines(sparing: 0, using: &rng)
        let first = board.mines
        board.layMines(sparing: 80, using: &rng)
        XCTAssertEqual(board.mines, first)
    }

    // MARK: - Numbers and digging

    func testNumbersCountTouchingMines() {
        // Mines at (0,0), (2,0) and (1,2) on a 4×4.
        let board = MinesweeperBoard(width: 4, height: 4, mineAt: [0, 2, 9])
        XCTAssertEqual(board.counts[1], 2)   // (1,0): touches (0,0) and (2,0)
        XCTAssertEqual(board.counts[5], 3)   // (1,1): all three
        XCTAssertEqual(board.counts[3], 1)   // (3,0): (2,0)
        XCTAssertEqual(board.counts[15], 0)  // (3,3): none
        XCTAssertEqual(board.counts[12], 1)  // (0,3): (1,2)
        XCTAssertEqual(board.neighbours(of: 0).count, 3)
        XCTAssertEqual(board.neighbours(of: 5).count, 8)
        XCTAssertEqual(board.neighbours(of: 7).count, 5)
    }

    func testFloodFillOpensEmptyRegionAndItsEdge() {
        // A 5×5 with one mine in the corner: digging the far corner opens all 24 safe squares.
        var board = MinesweeperBoard(width: 5, height: 5, mineAt: [0])
        let outcome = board.reveal(24)
        XCTAssertEqual(outcome.opened.count, 24)
        XCTAssertEqual(Set(outcome.opened.map(\.index)).count, 24, "each square opened once")
        XCTAssertTrue(outcome.won)
        XCTAssertEqual(board.status, .won)
        XCTAssertEqual(board.cells[0], .flagged, "a win flags the mines")
        XCTAssertEqual(outcome.opened.first?.depth, 0)
        XCTAssertGreaterThan(outcome.opened.last?.depth ?? 0, 2)
    }

    func testFloodStopsAtNumbersAndSkipsFlags() {
        // A wall of mines down column 2 of a 5×3: the left side is cut off from the right.
        var board = MinesweeperBoard(width: 5, height: 3, mineAt: [2, 7, 12])
        board.toggleFlag(4)
        let outcome = board.reveal(0)
        let opened = Set(outcome.opened.map(\.index))
        XCTAssertEqual(opened, [0, 1, 5, 6, 10, 11])
        XCTAssertEqual(board.cells[4], .flagged)
        XCTAssertEqual(board.cells[3], .hidden)
        XCTAssertEqual(board.status, .playing)
    }

    func testNumberedSquareOpensAlone() {
        var board = MinesweeperBoard(width: 4, height: 4, mineAt: [0, 2, 9])
        let outcome = board.reveal(5)
        XCTAssertEqual(outcome.opened.map(\.index), [5])
        XCTAssertEqual(board.revealedCount, 1)
    }

    func testDiggingAMineLoses() {
        var board = MinesweeperBoard(width: 4, height: 4, mineAt: [0, 2, 9])
        let outcome = board.reveal(9)
        XCTAssertEqual(outcome.hitMine, 9)
        XCTAssertEqual(board.status, .lost)
        XCTAssertEqual(board.exploded, 9)
        XCTAssertFalse(board.reveal(15).changed, "nothing moves after a loss")
        XCTAssertFalse(board.toggleFlag(15))
    }

    func testFlagsCountDownAndBlockDigging() {
        var board = MinesweeperBoard(width: 4, height: 4, mineAt: [0, 2, 9])
        XCTAssertTrue(board.toggleFlag(0))
        XCTAssertEqual(board.minesLeft, 2)
        XCTAssertFalse(board.reveal(0).changed, "a flagged square is not dug")
        XCTAssertTrue(board.toggleFlag(0))
        XCTAssertEqual(board.cells[0], .hidden)
        XCTAssertEqual(board.minesLeft, 3)
        _ = board.reveal(5)
        XCTAssertFalse(board.toggleFlag(5), "an open square takes no flag")
        for i in [1, 3, 4] { board.toggleFlag(i) }
        XCTAssertEqual(board.minesLeft, 0)
        board.toggleFlag(6)
        XCTAssertEqual(board.minesLeft, -1, "the counter can go below zero")
    }

    // MARK: - Chords

    func testChordNeedsMatchingFlags() {
        // 3×3, one mine top-left; the middle is a 1.
        var board = MinesweeperBoard(width: 3, height: 3, mineAt: [0])
        _ = board.reveal(4)
        XCTAssertEqual(board.counts[4], 1)
        XCTAssertFalse(board.canChord(4), "no flag yet")
        XCTAssertFalse(board.chord(4).changed)
        board.toggleFlag(0)
        XCTAssertTrue(board.canChord(4))
        let outcome = board.chord(4)
        XCTAssertNil(outcome.hitMine)
        XCTAssertEqual(Set(outcome.opened.map(\.index)), [1, 2, 3, 5, 6, 7, 8])
        XCTAssertTrue(outcome.won)
        XCTAssertEqual(board.status, .won)
    }

    func testChordWithTooManyFlagsDoesNothing() {
        var board = MinesweeperBoard(width: 3, height: 3, mineAt: [0])
        _ = board.reveal(4)
        board.toggleFlag(0)
        board.toggleFlag(8)
        XCTAssertFalse(board.canChord(4))
        XCTAssertFalse(board.chord(4).changed)
    }

    func testChordWithAWrongFlagBlowsUp() {
        var board = MinesweeperBoard(width: 3, height: 3, mineAt: [0])
        _ = board.reveal(4)
        board.toggleFlag(8) // wrong: the mine is at 0
        let outcome = board.chord(4)
        XCTAssertEqual(outcome.hitMine, 0)
        XCTAssertEqual(board.status, .lost)
        XCTAssertEqual(board.wrongFlags, [8])
    }

    func testChordOnZeroOrHiddenIsRefused() {
        var board = MinesweeperBoard(width: 5, height: 5, mineAt: [0])
        XCTAssertFalse(board.canChord(24), "hidden")
        _ = board.reveal(12)
        XCTAssertFalse(board.canChord(24), "a zero has nothing to chord")
    }

    // MARK: - Win

    func testWinNeedsEverySafeSquare() {
        var board = MinesweeperBoard(width: 4, height: 4, mineAt: [0, 10])
        var wins = 0
        for i in 0..<board.size where !board.mines[i] {
            let outcome = board.reveal(i)
            if outcome.won { wins += 1 }
            if board.revealedCount < board.safeCount {
                XCTAssertFalse(outcome.won)
                XCTAssertEqual(board.status, .playing)
            }
        }
        XCTAssertEqual(wins, 1, "the win is reported once, on the move that clears the field")
        XCTAssertEqual(board.status, .won)
        XCTAssertEqual(board.minesLeft, 0)
        XCTAssertTrue(board.isOver)
    }

    func testAWrongFlagHoldsBackTheWin() {
        var board = MinesweeperBoard(width: 3, height: 3, mineAt: [0])
        board.toggleFlag(8) // a safe square under a flag is never dug, so the field is not clear
        _ = board.reveal(4)
        for i in [1, 2, 3, 5, 6, 7] { _ = board.reveal(i) }
        XCTAssertEqual(board.status, .playing)
        XCTAssertEqual(board.revealedCount, board.safeCount - 1)
        board.toggleFlag(8)
        XCTAssertTrue(board.reveal(8).won)
    }

    // MARK: - No guessing

    func testSolverSolvesItsOwnBoards() {
        let fields: [(Int, Int, Int)] = [(9, 9, 10), (16, 16, 40), (16, 30, 99), (12, 18, 30)]
        for (n, f) in fields.enumerated() {
            let first = (f.0 * f.1) / 2 + f.0 / 3
            let field = MinesweeperGenerator.field(width: f.0, height: f.1, mines: f.2, firstDig: first,
                                                   noGuess: true, seed: UInt64(100 + n))
            XCTAssertTrue(field.logical, "\(f): no logical field in \(field.attempts) tries")
            XCTAssertTrue(MinesweeperSolver.solves(field.board, from: first))
            XCTAssertEqual(field.board.mines.filter { $0 }.count, f.2)
            XCTAssertFalse(field.board.mines[first])
            var play = field.board
            XCTAssertNil(play.reveal(first).hitMine)
        }
    }

    func testSolverRefusesACoinToss() {
        // A 2×2 field with one mine at the bottom left: digging the top right
        // shows a 1 touching all three other squares, and nothing can say which.
        let board = MinesweeperBoard(width: 2, height: 2, mineAt: [2])
        XCTAssertFalse(MinesweeperSolver.solves(board, from: 1))
    }

    func testSolverUsesTheSubsetRule() {
        // 3 wide, 4 tall, mines in the bottom corners. The first dig opens the
        // top three rows and leaves a 1-2-1 over the bottom row: no single
        // number settles anything, but the 1s sit inside the 2.
        let board = MinesweeperBoard(width: 3, height: 4, mineAt: [9, 11])
        XCTAssertEqual([board.counts[6], board.counts[7], board.counts[8]], [1, 2, 1])
        XCTAssertTrue(MinesweeperSolver.solves(board, from: 1))
    }

    func testGeneratorFallsBackAfterTheCap() {
        // A field so crowded that it can never be solved without guessing.
        let field = MinesweeperGenerator.field(width: 5, height: 5, mines: 15, firstDig: 12, noGuess: true,
                                               seed: 1, maxAttempts: 4)
        XCTAssertLessThanOrEqual(field.attempts, 4)
        XCTAssertEqual(field.board.mines.filter { $0 }.count, 15)
        XCTAssertFalse(field.board.mines[12])
    }

    func testPlainFieldIsOneTry() {
        let field = MinesweeperGenerator.field(width: 16, height: 30, mines: 99, firstDig: 0, noGuess: false, seed: 5)
        XCTAssertEqual(field.attempts, 1)
        XCTAssertFalse(field.logical)
        XCTAssertTrue(field.board.minesLaid)
    }

    func testSameSeedSameField() {
        let a = MinesweeperGenerator.field(width: 9, height: 9, mines: 10, firstDig: 40, noGuess: false, seed: 42)
        let b = MinesweeperGenerator.field(width: 9, height: 9, mines: 10, firstDig: 40, noGuess: false, seed: 42)
        XCTAssertEqual(a.board.mines, b.board.mines)
    }

    // MARK: - Records

    func testRecordsKeepTheFastestFive() {
        var records = MinesweeperRecords()
        XCTAssertEqual(records.recordWin(key: "beginner", time: 30), 1)
        XCTAssertEqual(records.recordWin(key: "beginner", time: 20), 1)
        XCTAssertEqual(records.recordWin(key: "beginner", time: 25), 2)
        for t in [40.0, 50, 60] { records.recordWin(key: "beginner", time: t) }
        XCTAssertNil(records.recordWin(key: "beginner", time: 99))
        XCTAssertEqual(records.top("beginner"), [20, 25, 30, 40, 50])
        XCTAssertEqual(records.best("beginner"), 20)
        XCTAssertNil(records.best("expert"))
        XCTAssertEqual(records.wonCount("beginner"), 7)
        XCTAssertEqual(records.streakCount("beginner"), 7)
        records.recordLoss(key: "beginner")
        XCTAssertEqual(records.streakCount("beginner"), 0)
        XCTAssertEqual(records.bestStreakCount("beginner"), 7)
        XCTAssertEqual(records.playedCount("beginner"), 8)
    }

    func testRecordsSurviveARoundTrip() throws {
        let suite = "minesweeper-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MinesweeperRecordStore(defaults: defaults)
        var records = store.load()
        records.recordWin(key: "expert", time: 123.4)
        store.save(records)
        XCTAssertEqual(store.load(), records)
        var setup = MinesweeperSetup()
        setup.level = .custom
        setup.customWidth = 20
        setup.noGuess = true
        store.saveSetup(setup)
        XCTAssertEqual(store.loadSetup(), setup)
        // An older save with fewer fields still loads.
        defaults.set(Data(#"{"times":{"beginner":[9.5]}}"#.utf8), forKey: MinesweeperRecordStore.recordsKey)
        XCTAssertEqual(store.load().best("beginner"), 9.5)
    }

    func testFormatting() {
        XCTAssertEqual(MinesweeperFormat.clock(7.9), "0:07")
        XCTAssertEqual(MinesweeperFormat.clock(83), "1:23")
        XCTAssertEqual(MinesweeperFormat.precise(7.46), "7.4 s")
        XCTAssertEqual(MinesweeperFormat.precise(83), "1:23.0")
        XCTAssertEqual(MinesweeperFormat.spoken(61), "1 minute 1 second")
    }

    // MARK: - Viewport

    func testExpertStartsZoomedToAFairSquare() {
        let v = MinesweeperViewport(columns: 16, rows: 30, width: 343, height: 430)
        XCTAssertLessThan(v.fitCell, 32)
        XCTAssertGreaterThanOrEqual(v.cell, 32, "zoomed in, never smaller than 32 points")
        XCTAssertTrue(v.canZoom)
        XCTAssertTrue(v.canPan, "zoomed in, the field runs off the window")
        let fitted = v.fitted()
        XCTAssertFalse(fitted.canPan)
        XCTAssertEqual(fitted.scale, 1)
        XCTAssertGreaterThanOrEqual(fitted.zoomedIn(on: 0).cell, 32)
        XCTAssertLessThanOrEqual(fitted.contentWidth, 343 + 0.001)
    }

    func testBeginnerFitsWithoutZoom() {
        let v = MinesweeperViewport(columns: 9, rows: 9, width: 343, height: 420)
        XCTAssertEqual(v.scale, 1)
        XCTAssertGreaterThan(v.cell, 32)
        XCTAssertFalse(v.canPan)
        XCTAssertEqual(v.offsetX, 0, accuracy: 0.001)
        XCTAssertEqual(v.offsetY, (420 - v.contentHeight) / 2, accuracy: 0.001)
    }

    func testTapsFindTheSquareUnderTheFinger() {
        let v = MinesweeperViewport(columns: 9, rows: 9, width: 360, height: 360)
        XCTAssertEqual(v.cell, 40, accuracy: 0.001)
        XCTAssertEqual(v.cellIndex(x: 5, y: 5), 0)
        XCTAssertEqual(v.cellIndex(x: 85, y: 45), 1 * 9 + 2)
        XCTAssertNil(v.cellIndex(x: 361, y: 5))
        XCTAssertNil(v.cellIndex(x: -1, y: 5))
    }

    func testZoomKeepsTheFocusStillAndStaysInBounds() {
        let v = MinesweeperViewport(columns: 16, rows: 16, width: 320, height: 320) // 20pt squares
        let z = v.zoomed(to: 2, focusX: 160, focusY: 160)
        XCTAssertEqual(z.cell, 40, accuracy: 0.001)
        let before = v.fieldPoint(x: 160, y: 160), after = z.fieldPoint(x: 160, y: 160)
        XCTAssertEqual(before.column, after.column, accuracy: 0.001)
        XCTAssertEqual(before.row, after.row, accuracy: 0.001)
        let corner = z.zoomed(to: 2, focusX: 0, focusY: 0).centred(onColumn: -10, row: -10)
        XCTAssertEqual(corner.offsetX, 0, accuracy: 0.001, "pinned to the edge")
        XCTAssertLessThanOrEqual(z.zoomed(to: 100, focusX: 0, focusY: 0).cell, MinesweeperViewport.largestCell + 0.001)
        var dragged = z
        dragged.offsetX = 50
        XCTAssertLessThan(dragged.rubberBanded().offsetX, 50)
        XCTAssertGreaterThan(dragged.rubberBanded().offsetX, 0)
    }

    func testResizeKeepsAWholeFieldWholeAndAZoomedOneZoomed() {
        let whole = MinesweeperViewport(columns: 9, rows: 9, width: 343, height: 420)
        let shrunk = whole.resized(width: 343, height: 200)
        XCTAssertEqual(shrunk.scale, 1, "the end card rising must not crop a whole field")
        XCTAssertFalse(shrunk.canPan)
        XCTAssertLessThanOrEqual(shrunk.contentHeight, 200 + 0.001)
        let zoomed = MinesweeperViewport(columns: 16, rows: 30, width: 343, height: 430)
        let kept = zoomed.resized(width: 343, height: 300)
        XCTAssertEqual(kept.cell, zoomed.cell, accuracy: 0.001, "a zoomed field keeps its square size")
        XCTAssertTrue(kept.isZoomedIn)
    }

    // MARK: - Effects

    func testRippleRunsOutwardsFromTheMine() {
        let delays = MinesweeperEffects.rippleDelays(from: 0, to: [1, 10, 99], width: 10, span: 1.5)
        XCTAssertEqual(delays.count, 3)
        XCTAssertLessThan(delays[0], delays[2])
        XCTAssertLessThanOrEqual(delays.max() ?? 0, 1.5 + 0.001)
        var fx = MinesweeperEffects(count: 100)
        let span = fx.explode(at: 0, mines: [0, 1, 99], width: 10, now: 1000)
        XCTAssertGreaterThan(span, 0)
        XCTAssertTrue(fx.isMoving(at: 1000.5))
        XCTAssertFalse(fx.isMoving(at: 1010))
        XCTAssertLessThanOrEqual(fx.particles.count, MinesweeperEffects.particleCap)
    }
}
