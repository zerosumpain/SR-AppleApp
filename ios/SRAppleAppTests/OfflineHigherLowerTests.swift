import XCTest
@testable import SRAppleApp

/// Higher or Lower's rules: the opening card, secret calls, the reveal and its
/// scoring with streaks, the timer, the end after fifteen cards, players who
/// leave, and that nobody sees the next card or anyone else's call early.
final class OfflineHigherLowerTests: XCTestCase {
    private typealias Rules = HigherLowerRules

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

    /// A state with a chosen card showing and a chosen card to come.
    private func rigged(current: OfflineCard, upcoming: OfflineCard, now: Double = 0) -> (Rules.State, OfflineRNG) {
        var (state, rng) = started(now: now)
        state.current = current
        state.upcoming = upcoming
        state.seen = [current]
        return (state, rng)
    }

    private func call(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ id: String, _ call: Rules.Call, now: Double? = nil) throws {
        try Rules.apply(.call(round: state.round, call: call), by: id, to: &state,
                        now: now ?? state.callEndsAt - 1, rng: &rng)
    }

    /// The right call for the state's next card (or `.higher` on a same-rank card).
    private func rightCall(_ state: Rules.State) -> Rules.Call {
        Rules.compare(state.upcoming, to: state.current) == .lower ? .lower : .higher
    }

    private func wrongCall(_ state: Rules.State) -> Rules.Call {
        rightCall(state) == .higher ? .lower : .higher
    }

    private func refusal(_ expression: @autoclosure () throws -> Void) -> String? {
        do { try expression() } catch { return (error as? OfflineRefusal)?.reason ?? "not a refusal" }
        return nil
    }

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(Rules.info.id, "higher-lower")
        XCTAssertEqual(Rules.info.category, .card)
        XCTAssertEqual(Rules.info.minPlayers, 1)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    func testAMatchOpensWithOneCardUpAndTheTimerRunning() {
        let (state, _) = started(now: 100)
        XCTAssertEqual(state.round, 1)
        XCTAssertEqual(state.phase, .calling)
        XCTAssertEqual(state.callEndsAt, 100 + Rules.callWindow)
        XCTAssertEqual(state.deck.count, 50)
        XCTAssertEqual(state.seen, [state.current])
        XCTAssertNotEqual(state.current, state.upcoming)
        XCTAssertFalse(state.deck.contains(state.current))
        XCTAssertFalse(state.deck.contains(state.upcoming))
        XCTAssertEqual(state.scores, ["a": 0, "b": 0, "c": 0])
        XCTAssertFalse(Rules.isOver(state))
    }

    func testTheSeedDecidesTheDeal() {
        XCTAssertEqual(started(seed: 4).0, started(seed: 4).0)
        XCTAssertNotEqual(started(seed: 4).0.deck, started(seed: 5).0.deck)
    }

    func testAcesAreHighAndTheSameRankIsSame() {
        XCTAssertEqual(Rules.compare(OfflineCard(1, .spades), to: OfflineCard(13, .hearts)), .higher)
        XCTAssertEqual(Rules.compare(OfflineCard(2, .spades), to: OfflineCard(1, .hearts)), .lower)
        XCTAssertEqual(Rules.compare(OfflineCard(7, .clubs), to: OfflineCard(7, .hearts)), .same)
    }

    func testCallsAreScoredAtTheReveal() throws {
        var (state, rng) = rigged(current: OfflineCard(5, .clubs), upcoming: OfflineCard(11, .hearts))
        try call(&state, &rng, "a", .higher)
        try call(&state, &rng, "b", .lower)
        XCTAssertEqual(state.phase, .calling, "still waiting for Cat")
        try call(&state, &rng, "c", .higher)
        XCTAssertEqual(state.phase, .reveal)
        XCTAssertEqual(state.outcome, .higher)
        XCTAssertEqual(state.scores, ["a": 1, "b": 0, "c": 1])
        XCTAssertEqual(state.streaks, ["a": 1, "b": 0, "c": 1])
        XCTAssertEqual(state.gained, ["a": 1, "b": 0, "c": 1])
    }

    func testTheSameRankIsWrongForEveryone() throws {
        var (state, rng) = rigged(current: OfflineCard(9, .clubs), upcoming: OfflineCard(9, .hearts))
        state.streaks["a"] = 4
        try call(&state, &rng, "a", .higher)
        try call(&state, &rng, "b", .lower)
        try call(&state, &rng, "c", .higher)
        XCTAssertEqual(state.outcome, .same)
        XCTAssertEqual(state.scores, ["a": 0, "b": 0, "c": 0])
        XCTAssertEqual(state.streaks["a"], 0, "a same-rank card breaks a streak")
    }

    func testStreaksPayMore() throws {
        var (state, rng) = started()
        var gains: [Int] = []
        for _ in 0..<5 {
            try call(&state, &rng, "a", rightCall(state))
            try call(&state, &rng, "b", wrongCall(state))
            try call(&state, &rng, "c", wrongCall(state))
            // Guard against a same-rank card spoiling the streak in this seed.
            if state.outcome == .same { return XCTFail("seed 1 deals a pair in the first five; pick another") }
            gains.append(state.gained["a"] ?? -1)
            Rules.tick(&state, now: state.revealUntil, rng: &rng)
        }
        XCTAssertEqual(gains, [1, 2, 3, 3, 3])
        XCTAssertEqual(state.scores["a"], 12)
        XCTAssertEqual(state.bestStreaks["a"], 5)
        XCTAssertEqual(state.scores["b"], 0)
        XCTAssertEqual(Rules.gain(forStreak: 1), 1)
        XCTAssertEqual(Rules.gain(forStreak: 9), Rules.maxGain)
    }

    func testAWrongCallBreaksTheStreak() throws {
        var (state, rng) = rigged(current: OfflineCard(3, .clubs), upcoming: OfflineCard(2, .hearts))
        state.streaks["a"] = 2
        try call(&state, &rng, "a", .higher)
        try call(&state, &rng, "b", .lower)
        try call(&state, &rng, "c", .lower)
        XCTAssertEqual(state.streaks["a"], 0)
        XCTAssertEqual(state.gained["b"], 1)
    }

    func testTheTimerClosesTheCallsAndNoCallIsWrong() throws {
        var (state, rng) = rigged(current: OfflineCard(4, .clubs), upcoming: OfflineCard(10, .hearts), now: 0)
        state.streaks["c"] = 3
        try call(&state, &rng, "a", .higher)
        Rules.tick(&state, now: state.callEndsAt - 0.1, rng: &rng)
        XCTAssertEqual(state.phase, .calling)
        Rules.tick(&state, now: state.callEndsAt + 0.05, rng: &rng)
        XCTAssertEqual(state.phase, .reveal)
        XCTAssertEqual(state.scores, ["a": 1, "b": 0, "c": 0])
        XCTAssertEqual(state.streaks["c"], 0, "no call counts as wrong")

        let revealEnds = state.revealUntil
        let turned = state.upcoming
        Rules.tick(&state, now: revealEnds - 0.1, rng: &rng)
        XCTAssertEqual(state.phase, .reveal)
        Rules.tick(&state, now: revealEnds, rng: &rng)
        XCTAssertEqual(state.phase, .calling)
        XCTAssertEqual(state.round, 2)
        XCTAssertEqual(state.current, turned, "the turned card is the next one to call against")
        XCTAssertEqual(state.seen.count, 2)
        XCTAssertTrue(state.calls.isEmpty)
        XCTAssertNil(state.outcome)
        XCTAssertEqual(state.callEndsAt, revealEnds + Rules.callWindow)
    }

    func testBadCallsAreRefused() throws {
        var (state, rng) = started()
        XCTAssertEqual(refusal(try Rules.apply(.call(round: 1, call: .higher), by: "zed", to: &state, now: 101, rng: &rng)),
                       "You are not in this game.")
        XCTAssertEqual(refusal(try Rules.apply(.call(round: 2, call: .higher), by: "a", to: &state, now: 101, rng: &rng)),
                       "That call was for another card.")
        XCTAssertEqual(refusal(try Rules.apply(.call(round: 1, call: .higher), by: "a", to: &state, now: state.callEndsAt + 1, rng: &rng)),
                       "Time is up for this card.")
        try call(&state, &rng, "a", .higher)
        XCTAssertEqual(refusal(try self.call(&state, &rng, "a", .lower)), "You have already called this card.")
        XCTAssertEqual(state.calls["a"], .higher, "the first call stands")
        try call(&state, &rng, "b", .higher)
        try call(&state, &rng, "c", .higher)
        XCTAssertEqual(state.phase, .reveal)
        XCTAssertEqual(refusal(try Rules.apply(.call(round: 1, call: .lower), by: "c", to: &state, now: 102, rng: &rng)),
                       "The card has already turned.")
        Rules.playerLeft("b", state: &state, now: 102, rng: &rng)
        Rules.tick(&state, now: state.revealUntil, rng: &rng)
        XCTAssertEqual(refusal(try self.call(&state, &rng, "b", .lower)), "You have left this game.")
    }

    func testFifteenCardsEndTheMatch() throws {
        var (state, rng) = started(seed: 3)
        var rounds = 0
        while !Rules.isOver(state) {
            rounds += 1
            XCTAssertEqual(state.round, rounds)
            try call(&state, &rng, "a", rightCall(state))
            try call(&state, &rng, "b", wrongCall(state))
            try call(&state, &rng, "c", rounds % 2 == 0 ? rightCall(state) : wrongCall(state))
            Rules.tick(&state, now: state.revealUntil, rng: &rng)
            XCTAssertLessThanOrEqual(rounds, Rules.rounds)
        }
        XCTAssertEqual(rounds, Rules.rounds)
        XCTAssertEqual(state.seen.count, Rules.rounds)
        XCTAssertEqual(Rules.champions(state), ["a"])
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "c", "b"])
        XCTAssertEqual(table.first?.rank, 1)
        XCTAssertEqual(table.last?.score, 0)
        XCTAssertTrue(table.last?.detail?.hasPrefix("0 right calls") ?? false)
        XCTAssertEqual(refusal(try self.call(&state, &rng, "a", .higher)), "The game is over.")
    }

    func testTiesShareARank() {
        var (state, _) = started()
        state.scores = ["a": 4, "b": 4, "c": 1]
        XCTAssertEqual(Rules.standings(state).map(\.rank), [1, 1, 3])
        state.phase = .over
        XCTAssertEqual(Rules.champions(state), ["a", "b"])
        state.scores = ["a": 0, "b": 0, "c": 0]
        XCTAssertEqual(Rules.champions(state), [], "nobody wins with no points")
    }

    func testAPlayerWhoLeavesIsNotWaitedFor() throws {
        var (state, rng) = started()
        try call(&state, &rng, "a", .higher)
        try call(&state, &rng, "b", .lower)
        Rules.playerLeft("c", state: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.phase, .reveal, "Cat was the only one left to call")
        XCTAssertNil(state.gained["c"], "an absent player is not scored")
        Rules.playerLeft("c", state: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.away, ["c"], "leaving twice changes nothing")
        XCTAssertTrue(Rules.standings(state).first { $0.playerId == "c" }?.detail?.hasSuffix("left") ?? false)
    }

    func testEveryoneLeavingEndsIt() {
        var (state, rng) = started()
        for id in ["a", "b", "c"] { Rules.playerLeft(id, state: &state, now: 101, rng: &rng) }
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(Rules.standings(state).count, 3)
    }

    func testEveryViewHidesTheDeckAndTheOtherCalls() throws {
        for viewer in players.map({ Optional($0.id) }) + [nil] {
            var (state, rng) = started(seed: 9)
            // Play a few cards in, so the history is not empty.
            for _ in 0..<3 {
                Rules.tick(&state, now: state.callEndsAt, rng: &rng)
                Rules.tick(&state, now: state.revealUntil, rng: &rng)
            }
            // Everyone else calls; the viewer has not yet.
            for player in players where player.id != viewer {
                try call(&state, &rng, player.id, .lower)
            }
            XCTAssertEqual(state.phase, viewer == nil ? .reveal : .calling)
            guard state.phase == .calling else { continue }
            let json = String(decoding: try OfflineCoding.encode(Rules.view(of: state, for: viewer)), as: UTF8.self)
            XCTAssertFalse(json.contains("lower"), "another player's call leaked to \(viewer ?? "a spectator")")
            for card in [state.upcoming] + state.deck {
                let encoded = String(decoding: try OfflineCoding.encode(card), as: UTF8.self)
                XCTAssertFalse(json.contains(encoded), "the unturned \(card) leaked to \(viewer ?? "a spectator")")
            }
        }
        // And a spectator mid-call, with nobody having called.
        let (fresh, _) = started(seed: 9)
        let json = String(decoding: try OfflineCoding.encode(Rules.view(of: fresh, for: nil)), as: UTF8.self)
        for card in [fresh.upcoming] + fresh.deck {
            XCTAssertFalse(json.contains(String(decoding: try OfflineCoding.encode(card), as: UTF8.self)))
        }
    }

    func testTheNextCardAndOthersCallsStayHidden() throws {
        var (state, rng) = started()
        try call(&state, &rng, "a", .lower)
        for viewer in [Optional("b"), nil] {
            let view = Rules.view(of: state, for: viewer)
            XCTAssertNil(view.revealed, "nobody sees the next card")
            XCTAssertNil(view.outcome)
            XCTAssertNil(view.myCall)
            XCTAssertTrue(view.rows.allSatisfy { $0.call == nil && $0.gained == nil })
            XCTAssertEqual(view.rows.first { $0.id == "a" }?.called, true, "only that Ann has called")
            XCTAssertEqual(view.current, state.current)
            XCTAssertEqual(view.cardsLeft, 51)
            XCTAssertTrue(view.history.isEmpty)
            let json = String(decoding: try OfflineCoding.encode(view), as: UTF8.self)
            XCTAssertFalse(json.contains("lower"), "Ann's call does not leak")
        }
        XCTAssertEqual(Rules.view(of: state, for: "a").myCall, .lower, "Ann sees her own")

        try call(&state, &rng, "b", .higher)
        try call(&state, &rng, "c", .higher)
        let after = Rules.view(of: state, for: nil)
        XCTAssertEqual(after.revealed, state.upcoming)
        XCTAssertEqual(after.rows.map(\.call), [.lower, .higher, .higher])
        XCTAssertNotNil(after.outcome)
        XCTAssertEqual(after.cardsLeft, 50)
    }

    func testTheHistoryShowsTurnedCards() throws {
        var (state, rng) = started()
        let first = state.current
        Rules.tick(&state, now: state.callEndsAt, rng: &rng)
        Rules.tick(&state, now: state.revealUntil, rng: &rng)
        let view = Rules.view(of: state, for: "a")
        XCTAssertEqual(view.history, [first])
        XCTAssertEqual(view.round, 2)
        XCTAssertEqual(view.cardsLeft, 50)
    }

    func testOnePlayerCanPlayAlone() throws {
        var rng = OfflineRNG(seed: 9)
        var state = Rules.start(players: [players[0]], now: 0, rng: &rng)
        try Rules.apply(.call(round: 1, call: .higher), by: "a", to: &state, now: 1, rng: &rng)
        XCTAssertEqual(state.phase, .reveal, "a lone player's call turns the card at once")
    }

    func testRandomPlayoutsAlwaysFinish() throws {
        for seed in UInt64(1)...200 {
            var rng = OfflineRNG(seed: seed)
            var picker = OfflineRNG(seed: seed &* 7919)
            let count = 1 + Int(seed % 5)
            let seats = (0..<count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            var state = Rules.start(players: seats, now: 0, rng: &rng)
            var now = 0.0
            var steps = 0
            while !Rules.isOver(state) {
                steps += 1
                XCTAssertLessThan(steps, 5000, "seed \(seed) never finished")
                if steps >= 5000 { break }
                now += 0.1
                if state.phase == .calling {
                    for seat in seats where state.calls[seat.id] == nil && !state.away.contains(seat.id) && picker.chance(0.2) {
                        let call: Rules.Call = picker.chance(0.5) ? .higher : .lower
                        try Rules.apply(.call(round: state.round, call: call), by: seat.id, to: &state, now: now, rng: &rng)
                        if state.phase != .calling { break }
                    }
                }
                if count > 1, seed % 7 == 0, state.round == 5, !state.away.contains("p1") {
                    Rules.playerLeft("p1", state: &state, now: now, rng: &rng)
                }
                Rules.tick(&state, now: now, rng: &rng)
            }
            XCTAssertTrue(Rules.isOver(state))
            XCTAssertEqual(state.round, Rules.rounds)
            let table = Rules.standings(state)
            XCTAssertEqual(Set(table.map(\.playerId)), Set(seats.map(\.id)))
            XCTAssertTrue(table.allSatisfy { $0.score <= Rules.rounds * Rules.maxGain })
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("higher-lower")
        try room.start(seed: 8, now: 0)
        _ = room.outbox()

        var now = 0.0
        while room.phase == .playing && now < 600 {
            now += 0.1
            room.tick(now: now)
            let ben = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "b")))
            if ben.phase == .calling, ben.myCall == nil {
                // Ben always calls higher; Ann always lower.
                try room.act(OfflineCoding.encode(Rules.Action.call(round: ben.round, call: .higher)), by: "b", match: 1, now: now)
                try room.act(OfflineCoding.encode(Rules.Action.call(round: ben.round, call: .lower)), by: "a", match: 1, now: now)
            }
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.count, 2)
    }
}
