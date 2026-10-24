import XCTest
@testable import SRAppleApp

/// Quick Draw's rules: the stand-off, who takes a round, false starts, the
/// end of the match, and what each phone is allowed to see.
final class OfflineQuickDrawTests: XCTestCase {
    private typealias Rules = QuickDrawRules

    private let players = [
        OfflinePlayer(id: "a", name: "Ann"),
        OfflinePlayer(id: "b", name: "Ben"),
        OfflinePlayer(id: "c", name: "Cat"),
    ]

    private func started(seed: UInt64 = 1, now: Double = 100) -> (Rules.State, OfflineRNG) {
        var rng = OfflineRNG(seed: seed)
        let state = Rules.start(players: players, now: now, rng: &rng)
        return (state, rng)
    }

    /// A tap reported `ms` after DRAW, arriving at the host just after it.
    private func draw(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ id: String, ms: Int) throws {
        try Rules.apply(.draw(round: state.round, ms: ms), by: id, to: &state,
                        now: state.drawAt + Double(ms) / 1000 + 0.05, rng: &rng)
    }

    /// Play one whole round where `winner` is quickest, then let the result pass.
    private func win(_ state: inout Rules.State, _ rng: inout OfflineRNG, by winner: String) throws {
        for player in players where !state.away.contains(player.id) {
            try draw(&state, &rng, player.id, ms: player.id == winner ? 200 : 300)
        }
        Rules.tick(&state, now: state.resultUntil, rng: &rng)
    }

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(Rules.info.id, "quick-draw")
        XCTAssertEqual(Rules.info.category, .reaction)
    }

    func testAMatchOpensOnAStandOff() {
        let (state, _) = started(now: 100)
        XCTAssertEqual(state.round, 1)
        XCTAssertEqual(state.phase, .waiting)
        XCTAssertGreaterThanOrEqual(state.drawAt, 102)
        XCTAssertLessThanOrEqual(state.drawAt, 106)
        XCTAssertEqual(state.wins, ["a": 0, "b": 0, "c": 0])
        XCTAssertFalse(Rules.isOver(state))
    }

    func testTheSeedDecidesTheWait() {
        XCTAssertEqual(started(seed: 4).0.drawAt, started(seed: 4).0.drawAt)
        XCTAssertNotEqual(started(seed: 4).0.drawAt, started(seed: 5).0.drawAt)
    }

    func testTheQuickestTapTakesTheRound() throws {
        var (state, rng) = started()
        try draw(&state, &rng, "a", ms: 310)
        try draw(&state, &rng, "b", ms: 245)
        XCTAssertEqual(state.phase, .waiting, "still waiting for Cat")
        try draw(&state, &rng, "c", ms: 260)
        XCTAssertEqual(state.phase, .result)
        XCTAssertEqual(state.roundWinner, "b")
        XCTAssertEqual(state.wins["b"], 1)
        XCTAssertEqual(state.best, ["a": 310, "b": 245, "c": 260])

        let resultEnds = state.resultUntil
        Rules.tick(&state, now: resultEnds - 0.1, rng: &rng)
        XCTAssertEqual(state.phase, .result)
        Rules.tick(&state, now: resultEnds, rng: &rng)
        XCTAssertEqual(state.round, 2)
        XCTAssertEqual(state.phase, .waiting)
        XCTAssertTrue(state.taps.isEmpty)
        XCTAssertGreaterThanOrEqual(state.drawAt, resultEnds + 2)
    }

    func testAFalseStartSitsTheRoundOut() throws {
        var (state, rng) = started()
        try Rules.apply(.early(round: 1), by: "a", to: &state, now: state.drawAt - 1, rng: &rng)
        XCTAssertEqual(state.taps["a"], Rules.Tap(early: true, ms: nil))
        XCTAssertThrowsError(try draw(&state, &rng, "a", ms: 150), "no second go after jumping the gun")
        try draw(&state, &rng, "b", ms: 400)
        try draw(&state, &rng, "c", ms: 500)
        XCTAssertEqual(state.roundWinner, "b", "the slow but honest tap beats the false start")
        XCTAssertEqual(state.falseStarts["a"], 1)
        XCTAssertNil(state.best["a"])
    }

    func testTooQuickToBeARealReactionIsAFalseStart() throws {
        var (state, rng) = started()
        try draw(&state, &rng, "a", ms: 40)
        XCTAssertEqual(state.taps["a"]?.early, true)
        // A claimed time that reached the host long before DRAW was due.
        try Rules.apply(.draw(round: 1, ms: 220), by: "b", to: &state, now: state.drawAt - 1, rng: &rng)
        XCTAssertEqual(state.taps["b"]?.early, true)
        XCTAssertEqual(state.falseStarts, ["a": 1, "b": 1])
    }

    func testNobodyTakesARoundEveryoneJumped() throws {
        var (state, rng) = started()
        for id in ["a", "b", "c"] {
            try Rules.apply(.early(round: 1), by: id, to: &state, now: state.drawAt - 0.5, rng: &rng)
        }
        XCTAssertEqual(state.phase, .result)
        XCTAssertNil(state.roundWinner)
        XCTAssertEqual(state.wins.values.reduce(0, +), 0)
    }

    func testTheRoundClosesWithoutTheSlowest() throws {
        var (state, rng) = started()
        try draw(&state, &rng, "a", ms: 300)
        Rules.tick(&state, now: state.drawAt + Rules.drawWindow - 0.1, rng: &rng)
        XCTAssertEqual(state.phase, .waiting)
        Rules.tick(&state, now: state.drawAt + Rules.drawWindow, rng: &rng)
        XCTAssertEqual(state.phase, .result)
        XCTAssertEqual(state.roundWinner, "a")
    }

    func testBadTapsAreRefused() throws {
        var (state, rng) = started()
        XCTAssertThrowsError(try Rules.apply(.draw(round: 2, ms: 200), by: "a", to: &state, now: state.drawAt + 1, rng: &rng))
        XCTAssertThrowsError(try Rules.apply(.draw(round: 1, ms: -5), by: "a", to: &state, now: state.drawAt + 1, rng: &rng))
        XCTAssertThrowsError(try Rules.apply(.draw(round: 1, ms: 200), by: "zed", to: &state, now: state.drawAt + 1, rng: &rng))
        try draw(&state, &rng, "a", ms: 200)
        XCTAssertThrowsError(try draw(&state, &rng, "a", ms: 180), "one tap a round")
        try draw(&state, &rng, "b", ms: 300)
        try draw(&state, &rng, "c", ms: 300)
        XCTAssertThrowsError(try draw(&state, &rng, "c", ms: 100), "the round is over")
    }

    func testFiveRoundWinsTakeTheMatch() throws {
        var (state, rng) = started()
        for _ in 0..<4 { try win(&state, &rng, by: "c") }
        XCTAssertFalse(Rules.isOver(state))
        for player in players { try draw(&state, &rng, player.id, ms: player.id == "c" ? 200 : 300) }
        XCTAssertEqual(state.wins["c"], 5)
        XCTAssertFalse(Rules.isOver(state), "the last round's result is shown first")
        Rules.tick(&state, now: state.resultUntil, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(Rules.champions(state), ["c"])
        let table = Rules.standings(state)
        XCTAssertEqual(table.first?.playerId, "c")
        XCTAssertEqual(table.first?.score, 5)
        XCTAssertEqual(table.first?.detail, "best 200 ms")
        XCTAssertEqual(table.map(\.rank), [1, 2, 2])
    }

    func testNineRoundsEndItWithoutFiveWins() throws {
        var (state, rng) = started()
        let order = ["a", "b", "c", "a", "b", "c", "a", "b", "a"]
        for winner in order { try win(&state, &rng, by: winner) }
        XCTAssertEqual(state.round, 9)
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(Rules.champions(state), ["a"])
        XCTAssertEqual(state.wins, ["a": 4, "b": 3, "c": 2])
    }

    func testAPlayerWhoLeavesIsNotWaitedFor() throws {
        var (state, rng) = started()
        try draw(&state, &rng, "a", ms: 300)
        try draw(&state, &rng, "b", ms: 280)
        Rules.playerLeft("c", state: &state, now: state.drawAt + 0.5, rng: &rng)
        XCTAssertEqual(state.phase, .result, "Cat was the only one left to tap")
        XCTAssertEqual(state.roundWinner, "b")
        XCTAssertThrowsError(try draw(&state, &rng, "c", ms: 100))
        XCTAssertEqual(Rules.standings(state).last?.detail, "left")
    }

    func testOthersTimesStayHiddenUntilTheRoundCloses() throws {
        var (state, rng) = started()
        try draw(&state, &rng, "a", ms: 250)
        let ben = Rules.view(of: state, for: "b")
        XCTAssertNil(ben.myTap)
        let annRow = try XCTUnwrap(ben.rows.first { $0.id == "a" })
        XCTAssertTrue(annRow.tapped)
        XCTAssertNil(annRow.ms, "Ben cannot see Ann's time yet")
        XCTAssertEqual(Rules.view(of: state, for: "a").myTap?.ms, 250, "Ann sees her own")
        XCTAssertNil(Rules.view(of: state, for: nil).myTap)

        try draw(&state, &rng, "b", ms: 300)
        try draw(&state, &rng, "c", ms: 350)
        let after = Rules.view(of: state, for: "b")
        XCTAssertEqual(after.rows.map(\.ms), [250, 300, 350])
        XCTAssertEqual(after.roundWinner, "a")
        XCTAssertEqual(after.drawAt, state.drawAt)
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("quick-draw")
        try room.start(seed: 8, now: 0)
        let first = room.outbox()
        let annPacket = try XCTUnwrap(first.compactMap { item -> OfflineViewPacket? in
            if item.to == "a", case .view(let packet) = item.message { return packet }
            return nil
        }.first)
        let view = try OfflineCoding.decode(Rules.PlayerView.self, from: annPacket.data)
        XCTAssertEqual(view.rows.map(\.name), ["Ann", "Ben"])

        var now = 0.0
        while room.phase == .playing && now < 600 {
            now += 0.1
            room.tick(now: now)
            let due = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "b")))
            if due.phase == .waiting, now >= due.drawAt, due.myTap == nil {
                // Ben is always quicker.
                try room.act(OfflineCoding.encode(Rules.Action.draw(round: due.round, ms: 210)), by: "b", match: 1, now: now)
                try room.act(OfflineCoding.encode(Rules.Action.draw(round: due.round, ms: 290)), by: "a", match: 1, now: now)
            }
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.first?.playerId, "b")
        XCTAssertEqual(room.standings?.first?.score, Rules.winsNeeded)
    }
}
