import XCTest
@testable import SRAppleApp

/// Dots and Boxes' rules: the board for each table size, drawing lines,
/// claiming boxes and going again, the turn clock, players leaving, the end
/// of the match, and that every phone sees the same (secret-free) board.
final class OfflineDotsAndBoxesTests: XCTestCase {
    private typealias Rules = DotsAndBoxesRules
    private typealias Line = DotsAndBoxesRules.Line

    private let players = [
        OfflinePlayer(id: "a", name: "Ann"),
        OfflinePlayer(id: "b", name: "Ben"),
        OfflinePlayer(id: "c", name: "Cat"),
    ]

    private func started(_ count: Int = 2, seed: UInt64 = 1, now: Double = 100) -> (Rules.State, OfflineRNG) {
        var rng = OfflineRNG(seed: seed)
        let state = Rules.start(players: Array(players.prefix(count)), now: now, rng: &rng)
        return (state, rng)
    }

    private func h(_ row: Int, _ col: Int) -> Line { Line(horizontal: true, row: row, col: col) }
    private func v(_ row: Int, _ col: Int) -> Line { Line(horizontal: false, row: row, col: col) }

    /// Whoever's turn it is draws `line`.
    private func play(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ line: Line, now: Double = 101) throws {
        let id = state.players[state.turn].id
        try Rules.apply(.draw(turn: state.turnNumber, line: line), by: id, to: &state, now: now, rng: &rng)
    }

    private func refusal(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch { return (error as? OfflineRefusal)?.reason ?? "not a refusal" }
    }

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(Rules.info.id, "dots-and-boxes")
        XCTAssertEqual(Rules.info.category, .skill)
        XCTAssertEqual(Rules.info.minPlayers, 2)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    func testTheBoardGrowsWithTheTable() {
        XCTAssertTrue(Rules.boardSize(players: 2) == (4, 4))
        XCTAssertTrue(Rules.boardSize(players: 3) == (5, 5))
        XCTAssertTrue(Rules.boardSize(players: 4) == (6, 5))
        XCTAssertTrue(Rules.boardSize(players: 5) == (6, 5))

        let (two, _) = started(2)
        XCTAssertEqual(two.hLines.count, 5 * 4)
        XCTAssertEqual(two.vLines.count, 4 * 5)
        XCTAssertEqual(two.boxes, Array(repeating: -1, count: 16))
        XCTAssertEqual(Rules.openLines(two).count, 40)

        let five = (1...5).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
        var rng = OfflineRNG(seed: 3)
        let big = Rules.start(players: five, now: 0, rng: &rng)
        XCTAssertEqual(big.rows, 6)
        XCTAssertEqual(big.cols, 5)
        XCTAssertEqual(Rules.openLines(big).count, 7 * 5 + 6 * 6)
    }

    func testAMatchOpensOnTheFirstSeatsTurn() {
        let (state, _) = started(3, now: 100)
        XCTAssertEqual(state.phase, .playing)
        XCTAssertEqual(state.turn, 0)
        XCTAssertEqual(state.turnNumber, 1)
        XCTAssertEqual(state.turnEndsAt, 100 + Rules.turnSeconds)
        XCTAssertFalse(Rules.isOver(state))
    }

    func testALineThatClosesNothingPassesTheTurn() throws {
        var (state, rng) = started(3)
        try play(&state, &rng, h(0, 0), now: 105)
        XCTAssertTrue(state.hLines[0])
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.turnNumber, 2)
        XCTAssertEqual(state.turnEndsAt, 105 + Rules.turnSeconds)
        XCTAssertEqual(state.lastMove, Rules.Move(playerId: "a", line: h(0, 0), claimed: 0, timedOut: false))
        try play(&state, &rng, v(0, 0))
        try play(&state, &rng, v(2, 5))
        XCTAssertEqual(state.turn, 0, "round the table and back to Ann")
    }

    func testClosingABoxClaimsItAndGoesAgain() throws {
        var (state, rng) = started(2)
        try play(&state, &rng, h(0, 0))   // Ann
        try play(&state, &rng, h(1, 0))   // Ben
        try play(&state, &rng, v(0, 0))   // Ann — the third side
        XCTAssertEqual(state.turn, 1)
        try play(&state, &rng, v(0, 1))   // Ben closes it
        XCTAssertEqual(state.boxes[0], 1)
        XCTAssertEqual(state.turn, 1, "Ben goes again")
        XCTAssertEqual(state.lastMove?.claimed, 1)
        XCTAssertEqual(Rules.boxCount(state, seat: 1), 1)
    }

    func testOneLineCanCloseTwoBoxes() throws {
        var (state, rng) = started(2)
        // Boxes (0,0) and (0,1) share the vertical line v(0,1).
        for line in [h(0, 0), h(1, 0), v(0, 0), h(0, 1), h(1, 1), v(0, 2)] {
            try play(&state, &rng, line)
        }
        let mover = state.turn
        try play(&state, &rng, v(0, 1))
        XCTAssertEqual(state.boxes[0], mover)
        XCTAssertEqual(state.boxes[1], mover)
        XCTAssertEqual(state.lastMove?.claimed, 2)
        XCTAssertEqual(state.turn, mover)
    }

    func testIllegalMovesAreRefused() throws {
        var (state, rng) = started(3)
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: 1, line: h(0, 0)), by: "b", to: &state, now: 101, rng: &rng) },
                       "It's Ann's turn.")
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: 1, line: h(0, 0)), by: "zed", to: &state, now: 101, rng: &rng) },
                       "You are not in this game.")
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: 2, line: h(0, 0)), by: "a", to: &state, now: 101, rng: &rng) },
                       "That move was for an earlier turn.")
        for bad in [h(6, 0), h(0, 5), h(-1, 0), v(5, 0), v(0, 6), v(0, -1)] {
            XCTAssertEqual(refusal { try Rules.apply(.draw(turn: 1, line: bad), by: "a", to: &state, now: 101, rng: &rng) },
                           "That line is not on the board.", "\(bad)")
        }
        try play(&state, &rng, h(0, 0))
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: 2, line: h(0, 0)), by: "b", to: &state, now: 102, rng: &rng) },
                       "That line is already drawn.")
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: 1, line: h(1, 1)), by: "b", to: &state, now: 102, rng: &rng) },
                       "That move was for an earlier turn.", "a stale tap from an old turn")
        XCTAssertEqual(state.turnNumber, 2, "refusals change nothing")
    }

    func testAPlayerWhoLeftCannotMove() {
        var (state, rng) = started(3)
        Rules.playerLeft("a", state: &state, now: 101, rng: &rng)
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: state.turnNumber, line: h(0, 0)), by: "a", to: &state, now: 102, rng: &rng) },
                       "You have left this game.")
    }

    func testAPhoneThatComesBackTakesItsTurnsAgain() throws {
        var (state, rng) = started(3)
        try play(&state, &rng, h(0, 0))   // Ann; now Ben
        Rules.playerLeft("b", state: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.turn, 2, "Cat while Ben is away")
        XCTAssertEqual(refusal { try Rules.apply(.back, by: "a", to: &state, now: 111, rng: &rng) },
                       "You are already in this game.")
        try Rules.apply(.back, by: "b", to: &state, now: 111, rng: &rng)
        XCTAssertEqual(state.away, [])
        XCTAssertEqual(state.turn, 2, "coming back does not take the turn from Cat")
        try play(&state, &rng, h(0, 1))   // Cat
        try play(&state, &rng, h(0, 2))   // Ann
        XCTAssertEqual(state.turn, 1, "Ben is in the turn order again")
        try play(&state, &rng, h(0, 3))
        XCTAssertFalse(Rules.standings(state).contains { $0.detail?.hasSuffix("left") == true })

        state.phase = .over
        Rules.playerLeft("c", state: &state, now: 120, rng: &rng)
        XCTAssertEqual(refusal { try Rules.apply(.back, by: "c", to: &state, now: 121, rng: &rng) }, "The game is over.")
    }

    func testLeavingOnYourTurnPassesItOn() throws {
        var (state, rng) = started(3)
        try play(&state, &rng, h(0, 0))   // Ann; now Ben
        Rules.playerLeft("b", state: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.away, ["b"])
        XCTAssertEqual(state.turn, 2, "Cat is next")
        XCTAssertEqual(state.turnNumber, 3)
        XCTAssertEqual(state.turnEndsAt, 110 + Rules.turnSeconds)
        try play(&state, &rng, h(0, 1))   // Cat; Ben is skipped
        XCTAssertEqual(state.turn, 0)
        try play(&state, &rng, h(0, 2))
        XCTAssertEqual(state.turn, 2)
        Rules.playerLeft("b", state: &state, now: 111, rng: &rng)
        XCTAssertEqual(state.away, ["b"], "leaving twice changes nothing")

        // Someone leaving while it is not their turn leaves the turn alone.
        Rules.playerLeft("a", state: &state, now: 112, rng: &rng)
        XCTAssertEqual(state.turn, 2)
    }

    func testARunningOutTurnDrawsARandomLine() throws {
        var (state, rng) = started(2, now: 100)
        Rules.tick(&state, now: 129.9, rng: &rng)
        XCTAssertEqual(Rules.openLines(state).count, 40, "not yet")
        Rules.tick(&state, now: 130.2, rng: &rng)
        XCTAssertEqual(Rules.openLines(state).count, 39)
        XCTAssertEqual(state.lastMove?.playerId, "a")
        XCTAssertEqual(state.lastMove?.timedOut, true)
        XCTAssertEqual(state.timeouts["a"], 1)
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.turnEndsAt, 130.2 + Rules.turnSeconds)

        let before = state
        Rules.tick(&state, now: 130.2, rng: &rng)
        XCTAssertEqual(state, before, "a repeated tick changes nothing")
    }

    func testTheRandomLineDependsOnlyOnTheSeed() {
        func timedOut(seed: UInt64) -> Line? {
            var (state, rng) = started(2, seed: seed, now: 0)
            Rules.tick(&state, now: 31, rng: &rng)
            return state.lastMove?.line
        }
        XCTAssertEqual(timedOut(seed: 9), timedOut(seed: 9))
    }

    func testTheLastBoxEndsTheMatchAfterAPause() throws {
        var (state, rng) = started(2)
        // Fill everything but box (3,3)'s right side; give the rest to Ann.
        for i in state.hLines.indices { state.hLines[i] = true }
        for i in state.vLines.indices { state.vLines[i] = true }
        state.vLines[3 * 5 + 4] = false
        for i in 0..<15 { state.boxes[i] = i < 9 ? 0 : 1 }
        state.turn = 1
        try play(&state, &rng, v(3, 4), now: 200)
        XCTAssertEqual(state.boxes[15], 1)
        XCTAssertEqual(state.phase, .done)
        XCTAssertEqual(state.resultUntil, 200 + Rules.resultPause)
        XCTAssertFalse(Rules.isOver(state), "the final board shows first")
        XCTAssertEqual(refusal { try play(&state, &rng, h(0, 0), now: 201) }, "The game is over.")

        Rules.tick(&state, now: 203.9, rng: &rng)
        XCTAssertFalse(Rules.isOver(state))
        Rules.tick(&state, now: 204, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))

        XCTAssertEqual(Rules.champions(state), ["a"])
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "b"])
        XCTAssertEqual(table.map(\.score), [9, 7])
        XCTAssertEqual(table.map(\.rank), [1, 2])
        XCTAssertEqual(table.first?.detail, "9 boxes")
    }

    func testTiesShareTheTop() {
        var (state, _) = started(3)
        for i in state.boxes.indices { state.boxes[i] = i < 10 ? 0 : (i < 20 ? 2 : 1) }
        state.away = ["b"]
        state.timeouts["c"] = 2
        XCTAssertEqual(Rules.champions(state), ["a", "c"])
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "c", "b"])
        XCTAssertEqual(table.map(\.rank), [1, 1, 3])
        XCTAssertEqual(table[1].detail, "10 boxes · 2 turns timed out")
        XCTAssertEqual(table[2].detail, "5 boxes · left")
    }

    func testEveryoneSeesTheSameBoard() throws {
        var (state, rng) = started(3)
        try play(&state, &rng, h(0, 0))
        try play(&state, &rng, v(1, 1))
        let spectator = Rules.view(of: state, for: nil)
        for player in players {
            XCTAssertEqual(Rules.view(of: state, for: player.id), spectator, "nothing is secret, so nobody sees more")
        }
        XCTAssertEqual(spectator.turnPlayer, "c")
        XCTAssertEqual(spectator.seats.map(\.name), ["Ann", "Ben", "Cat"])
        XCTAssertEqual(spectator.seats.map(\.seat), [0, 1, 2])
        XCTAssertEqual(spectator.champions, [])
        XCTAssertEqual(Rules.isDrawn(h(0, 0), rows: spectator.rows, cols: spectator.cols,
                                     hLines: spectator.hLines, vLines: spectator.vLines), true)
        XCTAssertEqual(Rules.isDrawn(h(0, 1), rows: spectator.rows, cols: spectator.cols,
                                     hLines: spectator.hLines, vLines: spectator.vLines), false)
        XCTAssertNil(Rules.isDrawn(h(9, 0), rows: spectator.rows, cols: spectator.cols,
                                   hLines: spectator.hLines, vLines: spectator.vLines))
        // The view carries the board and the table — not the rules' bookkeeping.
        let json = String(decoding: try OfflineCoding.encode(spectator), as: UTF8.self)
        XCTAssertFalse(json.contains("timeouts"))
    }

    func testRandomGamesAlwaysFinish() throws {
        for count in 2...5 {
            let table = (1...count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            for seed in UInt64(1)...40 {
                var rng = OfflineRNG(seed: seed &* 31 &+ UInt64(count))
                var state = Rules.start(players: table, now: 0, rng: &rng)
                var now = 0.0
                var moves = 0
                while !Rules.isOver(state) && moves < 500 {
                    now += 1
                    moves += 1
                    if state.phase == .playing {
                        // Mostly random moves; now and then let the clock play one.
                        if rng.chance(0.15) {
                            Rules.tick(&state, now: state.turnEndsAt, rng: &rng)
                            now = max(now, state.turnEndsAt - Rules.turnSeconds)
                        } else {
                            let line = try XCTUnwrap(rng.pick(Rules.openLines(state)))
                            try play(&state, &rng, line, now: now)
                        }
                        if seed == 7, count == 4, moves == 10 {
                            Rules.playerLeft(table[state.turn].id, state: &state, now: now, rng: &rng)
                        }
                    } else {
                        Rules.tick(&state, now: state.resultUntil, rng: &rng)
                    }
                }
                XCTAssertTrue(Rules.isOver(state), "\(count) players, seed \(seed)")
                XCTAssertFalse(state.boxes.contains(-1))
                XCTAssertTrue(Rules.openLines(state).isEmpty)
                XCTAssertEqual(Rules.standings(state).map(\.score).reduce(0, +), state.rows * state.cols)
            }
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("dots-and-boxes")
        try room.start(seed: 8, now: 0)
        _ = room.outbox()

        var now = 0.0
        var guardSteps = 0
        while room.phase == .playing && guardSteps < 1000 {
            guardSteps += 1
            now += 0.5
            room.tick(now: now)
            let view = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "b")))
            guard view.phase == .playing, let turn = view.turnPlayer else { continue }
            // Each player draws the first free line, as their phone would send it.
            var free: Line?
            outer: for row in 0...view.rows {
                for col in 0..<view.cols where Rules.isDrawn(h(row, col), rows: view.rows, cols: view.cols,
                                                              hLines: view.hLines, vLines: view.vLines) == false {
                    free = h(row, col)
                    break outer
                }
            }
            if free == nil {
                outer: for row in 0..<view.rows {
                    for col in 0...view.cols where Rules.isDrawn(v(row, col), rows: view.rows, cols: view.cols,
                                                                  hLines: view.hLines, vLines: view.vLines) == false {
                        free = v(row, col)
                        break outer
                    }
                }
            }
            let line = try XCTUnwrap(free)
            try room.act(OfflineCoding.encode(Rules.Action.draw(turn: view.turnNumber, line: line)), by: turn, match: 1, now: now)
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.map(\.score).reduce(0, +), 16)
    }
}
