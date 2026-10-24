import XCTest
@testable import SRAppleApp

/// Four in a Row's rules: the board for each table size, dropping discs,
/// lines across, down and on both diagonals, a full board, the turn clock,
/// players leaving, the end of the match, and that every phone sees the
/// same (secret-free) board.
final class OfflineFourInARowTests: XCTestCase {
    private typealias Rules = FourInARowRules

    private let players = [
        OfflinePlayer(id: "a", name: "Ann"),
        OfflinePlayer(id: "b", name: "Ben"),
        OfflinePlayer(id: "c", name: "Cat"),
        OfflinePlayer(id: "d", name: "Dan"),
    ]

    /// A started match with seat 0 (Ann) to move first, whatever the seed drew.
    private func started(_ count: Int = 2, seed: UInt64 = 1, now: Double = 100) -> (Rules.State, OfflineRNG) {
        var rng = OfflineRNG(seed: seed)
        var state = Rules.start(players: Array(players.prefix(count)), now: now, rng: &rng)
        state.turn = 0
        return (state, rng)
    }

    /// Whoever's turn it is drops in `column`.
    private func play(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ column: Int, now: Double = 101) throws {
        let id = state.players[state.turn].id
        try Rules.apply(.drop(turn: state.turnNumber, column: column), by: id, to: &state, now: now, rng: &rng)
    }

    private func refusal(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch { return (error as? OfflineRefusal)?.reason ?? "not a refusal" }
    }

    private func cell(_ state: Rules.State, row: Int, col: Int) -> Int { state.grid[row * state.cols + col] }

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self, seed: 99), [])
        XCTAssertEqual(Rules.info.id, "four-in-a-row")
        XCTAssertEqual(Rules.info.category, .skill)
        XCTAssertEqual(Rules.info.minPlayers, 2)
        XCTAssertEqual(Rules.info.maxPlayers, 4)
    }

    func testTheBoardGrowsWithTheTable() {
        XCTAssertTrue(Rules.boardSize(players: 2) == (7, 6))
        XCTAssertTrue(Rules.boardSize(players: 3) == (9, 7))
        XCTAssertTrue(Rules.boardSize(players: 4) == (9, 7))

        let (two, _) = started(2)
        XCTAssertEqual(two.cols, 7)
        XCTAssertEqual(two.rows, 6)
        XCTAssertEqual(two.grid, Array(repeating: -1, count: 42))
        XCTAssertEqual(Rules.openColumns(two), Array(0..<7))

        let (four, _) = started(4)
        XCTAssertEqual(four.cols, 9)
        XCTAssertEqual(four.rows, 7)
        XCTAssertEqual(four.grid.count, 63)
        XCTAssertEqual(four.timeouts, ["a": 0, "b": 0, "c": 0, "d": 0])
    }

    func testAMatchOpensWithASeededFirstPlayer() {
        var rng = OfflineRNG(seed: 5)
        let state = Rules.start(players: Array(players.prefix(3)), now: 100, rng: &rng)
        XCTAssertEqual(state.phase, .playing)
        XCTAssertTrue((0..<3).contains(state.turn))
        XCTAssertEqual(state.turnNumber, 1)
        XCTAssertEqual(state.turnEndsAt, 100 + Rules.turnSeconds)
        XCTAssertFalse(Rules.isOver(state))

        // Across many seeds, every seat gets to open sometimes.
        var openers = Set<Int>()
        for seed in 1...60 {
            var r = OfflineRNG(seed: UInt64(seed))
            openers.insert(Rules.start(players: Array(players.prefix(3)), now: 0, rng: &r).turn)
        }
        XCTAssertEqual(openers, [0, 1, 2])
    }

    func testDiscsFallToTheLowestFreeSpaceAndTheTurnPasses() throws {
        var (state, rng) = started(3)
        try play(&state, &rng, 4, now: 105)
        XCTAssertEqual(cell(state, row: 6, col: 4), 0, "Ann's disc lands on the bottom row")
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.turnNumber, 2)
        XCTAssertEqual(state.turnEndsAt, 105 + Rules.turnSeconds)
        XCTAssertEqual(state.lastMove, Rules.Move(playerId: "a", column: 4, row: 6, timedOut: false))
        try play(&state, &rng, 4)
        XCTAssertEqual(cell(state, row: 5, col: 4), 1, "Ben's lands on top of it")
        try play(&state, &rng, 0)
        XCTAssertEqual(cell(state, row: 6, col: 0), 2)
        XCTAssertEqual(state.turn, 0, "round the table and back to Ann")
    }

    func testIllegalMovesAreRefused() throws {
        var (state, rng) = started(3)
        XCTAssertEqual(refusal { try Rules.apply(.drop(turn: 1, column: 0), by: "b", to: &state, now: 101, rng: &rng) },
                       "It's Ann's turn.")
        XCTAssertEqual(refusal { try Rules.apply(.drop(turn: 1, column: 0), by: "zed", to: &state, now: 101, rng: &rng) },
                       "You are not in this game.")
        XCTAssertEqual(refusal { try Rules.apply(.drop(turn: 2, column: 0), by: "a", to: &state, now: 101, rng: &rng) },
                       "That move was for an earlier turn.")
        XCTAssertEqual(refusal { try Rules.apply(.drop(turn: 1, column: -1), by: "a", to: &state, now: 101, rng: &rng) },
                       "That column is not on the board.")
        XCTAssertEqual(refusal { try Rules.apply(.drop(turn: 1, column: 9), by: "a", to: &state, now: 101, rng: &rng) },
                       "That column is not on the board.")

        // Fill column 0 and ask for one more.
        for _ in 0..<state.rows { try play(&state, &rng, 0) }
        XCTAssertNil(Rules.landingRow(column: 0, in: state))
        XCTAssertFalse(Rules.openColumns(state).contains(0))
        let id = state.players[state.turn].id
        XCTAssertEqual(refusal { try Rules.apply(.drop(turn: state.turnNumber, column: 0), by: id, to: &state, now: 101, rng: &rng) },
                       "That column is full.")

        // A player who has left cannot act.
        Rules.playerLeft("c", state: &state, now: 102, rng: &rng)
        XCTAssertEqual(refusal { try Rules.apply(.drop(turn: state.turnNumber, column: 1), by: "c", to: &state, now: 103, rng: &rng) },
                       "You have left this game.")
    }

    func testARefusalLeavesTheStateAlone() {
        let (state, rng) = started(2)
        var copy = state
        var copyRng = rng
        XCTAssertNotNil(refusal { try Rules.apply(.drop(turn: 1, column: 0), by: "b", to: &copy, now: 101, rng: &copyRng) })
        XCTAssertEqual(copy, state)
    }

    func testFourAcrossWins() throws {
        var (state, rng) = started(2)
        // Ann 0,1,2,3 on the bottom; Ben stacks on top of them.
        for column in [0, 0, 1, 1, 2, 2] { try play(&state, &rng, column) }
        XCTAssertEqual(state.phase, .playing)
        try play(&state, &rng, 3, now: 110)
        XCTAssertEqual(state.phase, .done)
        XCTAssertEqual(state.ending, .line)
        XCTAssertEqual(state.winner, "a")
        let bottom = (state.rows - 1) * state.cols
        XCTAssertEqual(state.winningCells, [bottom, bottom + 1, bottom + 2, bottom + 3])
        XCTAssertEqual(state.resultUntil, 110 + Rules.resultPause)
        XCTAssertFalse(Rules.isOver(state))

        XCTAssertEqual(refusal { try Rules.apply(.drop(turn: state.turnNumber, column: 5), by: "b", to: &state, now: 111, rng: &rng) },
                       "The game is over.")

        Rules.tick(&state, now: 112, rng: &rng)
        XCTAssertEqual(state.phase, .done, "the board stays up for the pause")
        Rules.tick(&state, now: 110 + Rules.resultPause, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))

        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "b"])
        XCTAssertEqual(table.map(\.rank), [1, 2])
        XCTAssertEqual(table.first?.detail, "four in a row · 4 discs")
    }

    func testFourUpAndDownWins() throws {
        var (state, rng) = started(2)
        for column in [3, 4, 3, 4, 3, 4] { try play(&state, &rng, column) }
        try play(&state, &rng, 3)
        XCTAssertEqual(state.winner, "a")
        XCTAssertEqual(state.winningCells.count, 4)
        XCTAssertTrue(state.winningCells.allSatisfy { $0 % state.cols == 3 })
    }

    func testBothDiagonalsWin() {
        // Rising to the right: seat 1 at (5,0) (4,1) (3,2) and the last at (2,3).
        var grid = Array(repeating: -1, count: 42)
        for (row, col) in [(5, 0), (4, 1), (3, 2), (2, 3)] { grid[row * 7 + col] = 1 }
        let rising = Rules.winningLine(row: 2, col: 3, cols: 7, rows: 6, grid: grid)
        XCTAssertEqual(rising, [2 * 7 + 3, 3 * 7 + 2, 4 * 7 + 1, 5 * 7 + 0])
        XCTAssertEqual(Rules.winningLine(row: 5, col: 0, cols: 7, rows: 6, grid: grid), rising,
                     "found from either end")

        // Falling to the right.
        var other = Array(repeating: -1, count: 42)
        for (row, col) in [(1, 2), (2, 3), (3, 4), (4, 5)] { other[row * 7 + col] = 0 }
        XCTAssertEqual(Rules.winningLine(row: 3, col: 4, cols: 7, rows: 6, grid: other).count, 4)

        // Three is not enough, and someone else's disc breaks a line.
        other[4 * 7 + 5] = 1
        XCTAssertEqual(Rules.winningLine(row: 3, col: 4, cols: 7, rows: 6, grid: other), [])
        XCTAssertEqual(Rules.winningLine(row: 0, col: 0, cols: 7, rows: 6, grid: other), [], "an empty space is no line")
        XCTAssertEqual(Rules.winningLine(row: 9, col: 0, cols: 7, rows: 6, grid: other), [], "off the board is no line")
    }

    func testALineOfFiveRingsAllFive() {
        var grid = Array(repeating: -1, count: 42)
        for col in [0, 1, 3, 4] { grid[5 * 7 + col] = 0 }
        grid[5 * 7 + 2] = 0
        XCTAssertEqual(Rules.winningLine(row: 5, col: 2, cols: 7, rows: 6, grid: grid).count, 5)
    }

    func testThreeAndFourPlayerLinesWinToo() throws {
        var (state, rng) = started(4)
        // Ann builds across the bottom while the others drop high and away.
        for column in [0, 8, 8, 8, 1, 7, 7, 7, 2, 6, 6, 6] { try play(&state, &rng, column) }
        XCTAssertEqual(state.phase, .playing)
        try play(&state, &rng, 3)
        XCTAssertEqual(state.winner, "a")
        XCTAssertEqual(Rules.standings(state).first?.playerId, "a")
    }

    func testAFullBoardIsADraw() throws {
        // A board with one space left (top right) and no line of four,
        // whoever fills it — found by search, written out top row first.
        let rows: [[Int]] = [
            [1, 0, 0, 1, 0, 1, -1],
            [0, 1, 1, 0, 0, 1, 1],
            [0, 0, 1, 1, 1, 0, 0],
            [1, 1, 1, 0, 1, 1, 1],
            [1, 0, 0, 1, 0, 0, 1],
            [0, 0, 1, 1, 0, 0, 1],
        ]
        let grid = rows.flatMap { $0 }
        for index in grid.indices where grid[index] >= 0 {
            XCTAssertEqual(Rules.winningLine(row: index / 7, col: index % 7, cols: 7, rows: 6, grid: grid), [],
                           "the test board itself must hold no line (index \(index))")
        }
        for seat in 0..<2 {
            var (state, rng) = started(2)
            state.grid = grid
            state.turn = seat
            try play(&state, &rng, 6, now: 200)
            XCTAssertEqual(state.phase, .done)
            XCTAssertEqual(state.ending, .draw)
            XCTAssertNil(state.winner)
            XCTAssertEqual(state.winningCells, [])
            XCTAssertEqual(state.resultUntil, 200 + Rules.resultPause)
            let table = Rules.standings(state)
            XCTAssertEqual(table.map(\.rank), [1, 1], "a draw shares first place")
            XCTAssertTrue(table.allSatisfy { $0.detail?.hasPrefix("draw") == true })
        }
    }

    func testTheTurnClockDropsARandomDisc() {
        var (state, rng) = started(2, now: 100)
        Rules.tick(&state, now: 129.9, rng: &rng)
        XCTAssertEqual(state.turnNumber, 1, "not yet")
        Rules.tick(&state, now: 130.2, rng: &rng)
        XCTAssertEqual(state.turnNumber, 2)
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.lastMove?.playerId, "a")
        XCTAssertEqual(state.lastMove?.timedOut, true)
        XCTAssertEqual(state.lastMove?.row, 5)
        XCTAssertEqual(state.timeouts["a"], 1)
        XCTAssertEqual(state.turnEndsAt, 130.2 + Rules.turnSeconds)
        XCTAssertEqual(state.grid.filter { $0 == 0 }.count, 1)

        // Twice at one instant changes nothing more.
        let before = state
        Rules.tick(&state, now: 130.2, rng: &rng)
        XCTAssertEqual(state, before)

        // A timed-out drop never picks a full column.
        var (full, fullRng) = started(2)
        for col in 0..<6 {
            for row in 0..<6 { full.grid[row * 7 + col] = (row + col / 3) % 2 == 0 ? 0 : 1 }
        }
        full.turnEndsAt = 0
        Rules.tick(&full, now: 1, rng: &fullRng)
        XCTAssertEqual(full.lastMove?.column, 6)

        let table = Rules.standings(state)
        XCTAssertTrue(table.first { $0.playerId == "a" }?.detail?.contains("1 turn timed out") == true)
    }

    func testAPlayerLeavingIsSkipped() throws {
        var (state, rng) = started(3)
        try play(&state, &rng, 0)              // Ann; now Ben
        Rules.playerLeft("b", state: &state, now: 102, rng: &rng)
        XCTAssertEqual(state.away, ["b"])
        XCTAssertEqual(state.turn, 2, "Ben's turn passes to Cat")
        XCTAssertEqual(state.turnNumber, 3)
        XCTAssertEqual(state.turnEndsAt, 102 + Rules.turnSeconds)
        try play(&state, &rng, 1)              // Cat; skips Ben
        XCTAssertEqual(state.turn, 0)
        try play(&state, &rng, 2)              // Ann
        XCTAssertEqual(state.turn, 2)

        // Leaving twice changes nothing; a stranger leaving changes nothing.
        let before = state
        Rules.playerLeft("b", state: &state, now: 103, rng: &rng)
        Rules.playerLeft("zed", state: &state, now: 103, rng: &rng)
        XCTAssertEqual(state, before)

        // Ann leaving too leaves Cat alone: she wins by default.
        Rules.playerLeft("a", state: &state, now: 104, rng: &rng)
        XCTAssertEqual(state.phase, .done, "only Cat is left")
        XCTAssertEqual(state.ending, .forfeit)
        XCTAssertEqual(state.winner, "c")
        let table = Rules.standings(state)
        XCTAssertEqual(table.first?.playerId, "c")
        XCTAssertEqual(table.first?.detail?.hasPrefix("won by default"), true)
        XCTAssertEqual(table.map(\.playerId).sorted(), ["a", "b", "c"])
        XCTAssertTrue(table.first { $0.playerId == "b" }?.detail?.hasSuffix("left") == true)
    }

    func testAnOffTurnLeaverKeepsTheTurnWhereItIs() throws {
        var (state, rng) = started(4)
        Rules.playerLeft("c", state: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.turn, 0)
        XCTAssertEqual(state.turnNumber, 1)
        try play(&state, &rng, 0)
        try play(&state, &rng, 0)
        XCTAssertEqual(state.turn, 3, "Cat is skipped")
    }

    func testAPhoneThatComesBackTakesItsTurnsAgain() throws {
        var (state, rng) = started(3)
        Rules.playerLeft("b", state: &state, now: 101, rng: &rng)
        try play(&state, &rng, 0)   // Ann; Ben skipped
        XCTAssertEqual(state.turn, 2)
        XCTAssertEqual(refusal { try Rules.apply(.back, by: "c", to: &state, now: 102, rng: &rng) },
                       "You are already in this game.")
        try Rules.apply(.back, by: "b", to: &state, now: 102, rng: &rng)
        XCTAssertEqual(state.away, [])
        XCTAssertEqual(state.turn, 2, "coming back does not take the turn from Cat")
        try play(&state, &rng, 1)   // Cat
        try play(&state, &rng, 2)   // Ann
        XCTAssertEqual(state.turn, 1, "Ben is in the turn order again")
        try Rules.apply(.drop(turn: state.turnNumber, column: 3), by: "b", to: &state, now: 103, rng: &rng)

        // Once someone has won by default there is nothing to come back to.
        var (two, rng2) = started(2)
        Rules.playerLeft("b", state: &two, now: 101, rng: &rng2)
        XCTAssertEqual(two.ending, .forfeit)
        XCTAssertEqual(refusal { try Rules.apply(.back, by: "b", to: &two, now: 102, rng: &rng2) }, "The game is over.")
    }

    func testEveryPhoneSeesTheSameBoard() throws {
        var (state, rng) = started(3)
        try play(&state, &rng, 2)
        try play(&state, &rng, 3)
        let spectator = Rules.view(of: state, for: nil)
        for player in state.players {
            XCTAssertEqual(Rules.view(of: state, for: player.id), spectator)
        }
        XCTAssertEqual(spectator.grid, state.grid)
        XCTAssertEqual(spectator.turnPlayer, "c")
        XCTAssertEqual(spectator.seats.map(\.name), ["Ann", "Ben", "Cat"])
        XCTAssertEqual(spectator.seats.map(\.seat), [0, 1, 2])
        XCTAssertNil(spectator.winner)

        // Once decided, nobody's turn is shown.
        state.phase = .done
        XCTAssertNil(Rules.view(of: state, for: "a").turnPlayer)
    }

    func testRandomMatchesAlwaysFinish() throws {
        for seed in 1...200 {
            let count = 2 + seed % 3
            var rng = OfflineRNG(seed: UInt64(seed))
            var state = Rules.start(players: Array(players.prefix(count)), now: 0, rng: &rng)
            var now = 0.0
            var moves = 0
            while !Rules.isOver(state) && moves < 500 {
                now += 1
                if state.phase == .playing {
                    if seed % 7 == 0 && moves % 5 == 4 {
                        // Sometimes let the clock play instead.
                        now = state.turnEndsAt
                        Rules.tick(&state, now: now, rng: &rng)
                    } else {
                        let column = try XCTUnwrap(rng.pick(Rules.openColumns(state)))
                        try play(&state, &rng, column, now: now)
                    }
                    moves += 1
                } else {
                    Rules.tick(&state, now: now + Rules.resultPause, rng: &rng)
                }
                if seed % 11 == 0 && moves == 6 && count > 2 {
                    Rules.playerLeft(state.players[1].id, state: &state, now: now, rng: &rng)
                }
            }
            XCTAssertTrue(Rules.isOver(state), "seed \(seed) did not finish")
            XCTAssertLessThanOrEqual(moves, state.cols * state.rows)
            XCTAssertNotNil(state.ending)
            if state.ending == .line {
                let winnerSeat = try XCTUnwrap(state.players.firstIndex { $0.id == state.winner })
                XCTAssertGreaterThanOrEqual(state.winningCells.count, Rules.lineLength)
                XCTAssertTrue(state.winningCells.allSatisfy { state.grid[$0] == winnerSeat })
            }
            let table = Rules.standings(state)
            XCTAssertEqual(table.map(\.playerId).sorted(), state.players.map(\.id).sorted())
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("four-in-a-row")
        try room.start(seed: 8, now: 0)
        _ = room.outbox()

        var now = 0.0
        var guard_ = 0
        while room.phase == .playing && guard_ < 400 {
            guard_ += 1
            now += 0.5
            room.tick(now: now)
            guard let data = room.currentView(for: "a") else { continue }
            let view = try OfflineCoding.decode(Rules.PlayerView.self, from: data)
            guard view.phase == .playing, let turn = view.turnPlayer else { continue }
            // Ann always plays column 0, Ben column 1: Ann gets four up first
            // unless Ben opened, in which case Ben does.
            let column = turn == "a" ? 0 : 1
            try room.act(OfflineCoding.encode(Rules.Action.drop(turn: view.turnNumber, column: column)),
                         by: turn, match: 1, now: now)
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.count, 2)
        XCTAssertEqual(room.standings?.first?.rank, 1)
        XCTAssertEqual(room.standings?.first?.score, 2)
    }
}
