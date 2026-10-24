import XCTest
@testable import SRAppleApp

/// Cheat's rules: the deal, laying cards, calling and letting plays stand,
/// who picks up the pile, going out, timers, players leaving, and — above
/// all — that nobody's phone is ever sent a card it should not see.
final class OfflineCheatTests: XCTestCase {
    private typealias Rules = CheatRules

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

    /// A table set by hand: Ann to play aces, with the hands given.
    private func table(_ hands: [String: [OfflineCard]], turnPlayer: String = "a", rank: Int = 1,
                       pile: [OfflineCard] = []) -> Rules.State {
        var state = Rules.State(players: players, turnPlayer: turnPlayer)
        state.hands = hands
        state.rank = rank
        state.pile = pile
        state.turnEndsAt = 100 + Rules.turnSeconds
        return state
    }

    private func refusal(_ body: () throws -> Void) -> String? {
        do { try body() } catch { return (error as? OfflineRefusal)?.reason ?? "\(error)" }
        return nil
    }

    private let aceS = OfflineCard(1, .spades), aceH = OfflineCard(1, .hearts)
    private let twoC = OfflineCard(2, .clubs), sevenD = OfflineCard(7, .diamonds)
    private let kingS = OfflineCard(13, .spades), nineH = OfflineCard(9, .hearts)

    // MARK: - Setup

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(Rules.info.id, "cheat")
        XCTAssertEqual(Rules.info.category, .card)
        XCTAssertEqual(Rules.info.minPlayers, 3)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    func testTheWholeDeckIsDealt() {
        for count in 3...5 {
            let group = (1...count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            var rng = OfflineRNG(seed: UInt64(count))
            let state = Rules.start(players: group, now: 0, rng: &rng)
            let all = group.flatMap { state.hands[$0.id] ?? [] }
            XCTAssertEqual(all.count, 52)
            XCTAssertEqual(Set(all.map(\.id)).count, 52)
            let sizes = group.map { state.hands[$0.id]?.count ?? 0 }
            XCTAssertLessThanOrEqual((sizes.max() ?? 0) - (sizes.min() ?? 0), 1)
            XCTAssertEqual(state.phase, .play)
            XCTAssertEqual(state.rank, 1)
            XCTAssertEqual(state.turn, 1)
            XCTAssertTrue(group.contains { $0.id == state.turnPlayer })
            XCTAssertTrue(state.pile.isEmpty)
            XCTAssertEqual(state.turnEndsAt, Rules.turnSeconds)
        }
    }

    func testTheSeedDecidesTheDeal() {
        XCTAssertEqual(started(seed: 5).0, started(seed: 5).0)
        XCTAssertNotEqual(started(seed: 5).0.hands, started(seed: 6).0.hands)
    }

    // MARK: - Playing

    func testAPlayGoesFaceDownAndOpensTheWindow() throws {
        var state = table(["a": [aceS, twoC, sevenD], "b": [kingS], "c": [nineH]])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.play(turn: 1, cards: [aceS, sevenD]), by: "a", to: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.phase, .challenge)
        XCTAssertEqual(state.hands["a"], [twoC])
        XCTAssertEqual(state.pile.count, 2)
        XCTAssertEqual(state.lastPlay, Rules.Play(playerId: "a", count: 2, rank: 1, turn: 1, timedOut: false))
        XCTAssertEqual(state.challengeEndsAt, 101 + Rules.challengeSeconds)
    }

    func testIllegalPlaysAreRefused() {
        var rng = OfflineRNG(seed: 1)
        let base = table(["a": [aceS, aceH, twoC, sevenD, kingS], "b": [nineH], "c": [OfflineCard(3, .clubs)]])
        var state = base
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: 1, cards: [nineH]), by: "b", to: &state, now: 101, rng: &rng) },
                       "It's Ann's turn.")
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: 1, cards: [nineH]), by: "a", to: &state, now: 101, rng: &rng) },
                       "You don't have that card.")
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: 1, cards: []), by: "a", to: &state, now: 101, rng: &rng) },
                       "Pick at least one card.")
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: 1, cards: [aceS, aceH, twoC, sevenD, kingS]), by: "a", to: &state, now: 101, rng: &rng) },
                       "You can play at most 4 cards.")
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: 1, cards: [aceS, aceS]), by: "a", to: &state, now: 101, rng: &rng) },
                       "You picked the same card twice.")
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: 0, cards: [aceS]), by: "a", to: &state, now: 101, rng: &rng) },
                       "That play was for an earlier turn.")
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: 1, cards: [aceS]), by: "z", to: &state, now: 101, rng: &rng) },
                       "You are not in this game.")
        XCTAssertEqual(refusal { try Rules.apply(.call(turn: 1), by: "b", to: &state, now: 101, rng: &rng) },
                       "That play has already been settled.")
        XCTAssertEqual(refusal { try Rules.apply(.back, by: "b", to: &state, now: 101, rng: &rng) },
                       "You are already at the table.")
        XCTAssertEqual(state, base)
    }

    func testNobodyPlaysWhileTheWindowIsOpen() throws {
        var state = table(["a": [aceS, twoC], "b": [kingS, nineH], "c": [sevenD]])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.play(turn: 1, cards: [aceS]), by: "a", to: &state, now: 101, rng: &rng)
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: 2, cards: [kingS]), by: "b", to: &state, now: 102, rng: &rng) },
                       "Wait — the last play can still be called.")
        XCTAssertEqual(refusal { try Rules.apply(.call(turn: 1), by: "a", to: &state, now: 102, rng: &rng) },
                       "You can't call your own play.")
        XCTAssertEqual(refusal { try Rules.apply(.pass(turn: 1), by: "a", to: &state, now: 102, rng: &rng) },
                       "It's your own play.")
    }

    func testTheWindowClosesAndTheNextPlayerTakesTheNextRank() throws {
        var state = table(["a": [aceS, twoC], "b": [kingS, nineH], "c": [sevenD]])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.play(turn: 1, cards: [aceS]), by: "a", to: &state, now: 101, rng: &rng)
        Rules.tick(&state, now: 103, rng: &rng)
        XCTAssertEqual(state.phase, .challenge)
        Rules.tick(&state, now: 101 + Rules.challengeSeconds, rng: &rng)
        XCTAssertEqual(state.phase, .play)
        XCTAssertEqual(state.turnPlayer, "b")
        XCTAssertEqual(state.rank, 2)
        XCTAssertEqual(state.turn, 2)
        XCTAssertEqual(state.pile.count, 1)
        // Too late to call the play now.
        XCTAssertEqual(refusal { try Rules.apply(.call(turn: 1), by: "c", to: &state, now: 107, rng: &rng) },
                       "Too late to call that one.")
    }

    func testKingsCycleBackToAces() throws {
        var state = table(["a": [aceS, twoC], "b": [kingS, nineH], "c": [sevenD]], rank: 13)
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.play(turn: 1, cards: [twoC]), by: "a", to: &state, now: 101, rng: &rng)
        try Rules.apply(.pass(turn: 1), by: "b", to: &state, now: 102, rng: &rng)
        XCTAssertEqual(state.phase, .challenge)
        try Rules.apply(.pass(turn: 1), by: "c", to: &state, now: 102, rng: &rng)
        // Everybody let it go: the window shuts at once.
        XCTAssertEqual(state.phase, .play)
        XCTAssertEqual(state.rank, 1)
        XCTAssertEqual(refusal { try Rules.apply(.pass(turn: 1), by: "c", to: &state, now: 102, rng: &rng) },
                       "That play has already been settled.")
    }

    // MARK: - Calling

    func testCatchingALiarHandsThemThePile() throws {
        var state = table(["a": [aceS, sevenD, twoC], "b": [kingS, nineH], "c": [OfflineCard(3, .clubs)]],
                          pile: [OfflineCard(4, .hearts), OfflineCard(5, .hearts)])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.play(turn: 1, cards: [aceS, sevenD]), by: "a", to: &state, now: 101, rng: &rng)
        try Rules.apply(.call(turn: 1), by: "c", to: &state, now: 102, rng: &rng)
        XCTAssertEqual(state.phase, .reveal)
        let reveal = try XCTUnwrap(state.reveal)
        XCTAssertFalse(reveal.truthful)
        XCTAssertEqual(reveal.pickedUpBy, "a")
        XCTAssertEqual(reveal.pileSize, 4)
        XCTAssertEqual(reveal.cards, [aceS, sevenD])
        XCTAssertEqual(state.hands["a"]?.count, 5)
        XCTAssertTrue(state.pile.isEmpty)
        XCTAssertEqual(state.callsRight["c"], 1)
        // The second call is too slow.
        XCTAssertEqual(refusal { try Rules.apply(.call(turn: 1), by: "b", to: &state, now: 102.1, rng: &rng) },
                       "Cat called it first.")
        Rules.tick(&state, now: 102 + Rules.revealSeconds, rng: &rng)
        XCTAssertEqual(state.phase, .play)
        XCTAssertEqual(state.turnPlayer, "b")
        XCTAssertEqual(state.rank, 2)
    }

    func testCallingAnHonestPlayCostsTheCaller() throws {
        var state = table(["a": [aceS, aceH, twoC], "b": [kingS, nineH], "c": [OfflineCard(3, .clubs)]])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.play(turn: 1, cards: [aceS, aceH]), by: "a", to: &state, now: 101, rng: &rng)
        try Rules.apply(.call(turn: 1), by: "b", to: &state, now: 102, rng: &rng)
        let reveal = try XCTUnwrap(state.reveal)
        XCTAssertTrue(reveal.truthful)
        XCTAssertEqual(reveal.pickedUpBy, "b")
        XCTAssertEqual(state.hands["b"]?.count, 4)
        XCTAssertEqual(state.hands["a"], [twoC])
        XCTAssertNil(state.callsRight["b"])
    }

    func testAPlayerWhoLetItGoCannotThenCall() throws {
        var state = table(["a": [aceS, twoC], "b": [kingS, nineH], "c": [sevenD]])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.play(turn: 1, cards: [twoC]), by: "a", to: &state, now: 101, rng: &rng)
        try Rules.apply(.pass(turn: 1), by: "b", to: &state, now: 101.5, rng: &rng)
        XCTAssertEqual(refusal { try Rules.apply(.call(turn: 1), by: "b", to: &state, now: 102, rng: &rng) },
                       "You already let that one go.")
        XCTAssertEqual(refusal { try Rules.apply(.pass(turn: 1), by: "b", to: &state, now: 102, rng: &rng) },
                       "You already let that one go.")
    }

    // MARK: - Going out

    func testEmptyingYourHandWinsOnceTheWindowShuts() throws {
        var state = table(["a": [aceS], "b": [kingS, nineH], "c": [sevenD]])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.play(turn: 1, cards: [aceS]), by: "a", to: &state, now: 101, rng: &rng)
        XCTAssertNil(state.winner)
        Rules.tick(&state, now: 101 + Rules.challengeSeconds, rng: &rng)
        XCTAssertEqual(state.phase, .won)
        XCTAssertEqual(state.winner, "a")
        XCTAssertFalse(Rules.isOver(state))
        Rules.tick(&state, now: state.wonUntil, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "c", "b"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(table.first?.score, 0)
        XCTAssertEqual(table.first?.detail, "went out")
        XCTAssertEqual(refusal { try Rules.apply(.call(turn: 1), by: "b", to: &state, now: 200, rng: &rng) },
                       "The game is over.")
    }

    func testAnHonestLastPlaySurvivesACall() throws {
        var state = table(["a": [aceS], "b": [kingS, nineH], "c": [sevenD]])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.play(turn: 1, cards: [aceS]), by: "a", to: &state, now: 101, rng: &rng)
        try Rules.apply(.call(turn: 1), by: "c", to: &state, now: 102, rng: &rng)
        XCTAssertEqual(state.phase, .reveal)
        Rules.tick(&state, now: 102 + Rules.revealSeconds, rng: &rng)
        XCTAssertEqual(state.phase, .won)
        XCTAssertEqual(state.winner, "a")
    }

    func testALyingLastPlayCaughtKeepsTheGameGoing() throws {
        var state = table(["a": [twoC], "b": [kingS, nineH], "c": [sevenD]])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.play(turn: 1, cards: [twoC]), by: "a", to: &state, now: 101, rng: &rng)
        try Rules.apply(.call(turn: 1), by: "b", to: &state, now: 102, rng: &rng)
        Rules.tick(&state, now: 102 + Rules.revealSeconds, rng: &rng)
        XCTAssertEqual(state.phase, .play)
        XCTAssertNil(state.winner)
        XCTAssertEqual(state.hands["a"], [twoC])
    }

    func testTiesShareARank() {
        let state = table(["a": [aceS], "b": [kingS], "c": [sevenD, nineH]])
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.rank), [1, 1, 3])
        XCTAssertEqual(table.last?.playerId, "c")
    }

    // MARK: - Timers

    func testTheHostPlaysForASlowPlayer() {
        var state = table(["a": [twoC, aceH, sevenD], "b": [kingS], "c": [nineH]])
        var rng = OfflineRNG(seed: 1)
        Rules.tick(&state, now: state.turnEndsAt - 0.1, rng: &rng)
        XCTAssertEqual(state.phase, .play)
        Rules.tick(&state, now: state.turnEndsAt, rng: &rng)
        XCTAssertEqual(state.phase, .challenge)
        // An ace is held, so the honest card goes down.
        XCTAssertEqual(state.lastPlay?.timedOut, true)
        XCTAssertEqual(state.lastPlay?.count, 1)
        XCTAssertEqual(state.pile, [aceH])
        let settled = state
        Rules.tick(&state, now: settled.challengeEndsAt - 1, rng: &rng)
        Rules.tick(&state, now: settled.challengeEndsAt - 1, rng: &rng)
        XCTAssertEqual(state, settled)
    }

    func testTickIsIdempotentAtOneInstant() throws {
        var (state, rng) = started()
        for now in stride(from: 100.0, through: 400.0, by: 0.7) {
            Rules.tick(&state, now: now, rng: &rng)
            let once = state
            Rules.tick(&state, now: now, rng: &rng)
            XCTAssertEqual(state, once)
        }
    }

    // MARK: - Leaving

    func testATurnPassesOverAPlayerWhoLeaves() {
        var state = table(["a": [aceS, twoC], "b": [kingS], "c": [nineH]])
        var rng = OfflineRNG(seed: 1)
        Rules.playerLeft("a", state: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.turnPlayer, "b")
        XCTAssertEqual(state.rank, 1)
        XCTAssertEqual(state.turnEndsAt, 110 + Rules.turnSeconds)
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: 1, cards: [aceS]), by: "a", to: &state, now: 111, rng: &rng) },
                       "You left this game — rejoin to play.")
        Rules.playerLeft("a", state: &state, now: 111, rng: &rng)
        XCTAssertEqual(state.away, ["a"])
    }

    func testAPlayerWhoComesBackIsDealtBackIn() throws {
        var state = table(["a": [aceS, twoC], "b": [kingS, nineH], "c": [sevenD]])
        var rng = OfflineRNG(seed: 1)
        Rules.playerLeft("c", state: &state, now: 101, rng: &rng)
        try Rules.apply(.play(turn: 1, cards: [aceS]), by: "a", to: &state, now: 102, rng: &rng)
        // Only Ben can call; when he lets it go the window shuts and Cat is skipped.
        try Rules.apply(.pass(turn: 1), by: "b", to: &state, now: 103, rng: &rng)
        XCTAssertEqual(state.turnPlayer, "b")
        try Rules.apply(.back, by: "c", to: &state, now: 104, rng: &rng)
        XCTAssertTrue(state.away.isEmpty)
        try Rules.apply(.play(turn: 2, cards: [kingS]), by: "b", to: &state, now: 105, rng: &rng)
        try Rules.apply(.pass(turn: 2), by: "a", to: &state, now: 106, rng: &rng)
        XCTAssertEqual(state.phase, .challenge, "Cat is back, so the window waits for her too")
        try Rules.apply(.call(turn: 2), by: "c", to: &state, now: 106.5, rng: &rng)
        XCTAssertEqual(state.reveal?.pickedUpBy, "b")
    }

    func testACallAfterTheWindowIsRefusedEvenBeforeTheTick() throws {
        var state = table(["a": [aceS, twoC], "b": [kingS, nineH], "c": [sevenD]])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.play(turn: 1, cards: [twoC]), by: "a", to: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.phase, .challenge, "no tick has closed the window yet")
        XCTAssertEqual(refusal { try Rules.apply(.call(turn: 1), by: "b", to: &state, now: 101 + Rules.challengeSeconds + 0.3, rng: &rng) },
                       "Too late to call that one.")
        XCTAssertEqual(state.hands["a"], [aceS], "the lie stands")
    }

    func testALeaverRanksBelowEveryoneStillPlaying() {
        var state = table(["a": [aceS, twoC, sevenD], "b": [kingS], "c": [nineH, aceH]])
        var rng = OfflineRNG(seed: 1)
        Rules.playerLeft("b", state: &state, now: 101, rng: &rng)
        state.phase = .over
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["c", "a", "b"], "walking out holding one card does not win")
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
    }

    func testTheLastOpponentLeavingEndsIt() {
        var state = table(["a": [aceS, twoC], "b": [kingS], "c": [nineH]])
        var rng = OfflineRNG(seed: 1)
        Rules.playerLeft("b", state: &state, now: 101, rng: &rng)
        XCTAssertFalse(Rules.isOver(state))
        Rules.playerLeft("c", state: &state, now: 102, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(Rules.standings(state).count, 3)
    }

    func testTheWindowShutsWhenTheLastPossibleCallerLeaves() throws {
        var state = table(["a": [aceS, twoC], "b": [kingS, nineH], "c": [sevenD]])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.play(turn: 1, cards: [aceS]), by: "a", to: &state, now: 101, rng: &rng)
        try Rules.apply(.pass(turn: 1), by: "b", to: &state, now: 101.5, rng: &rng)
        Rules.playerLeft("c", state: &state, now: 102, rng: &rng)
        XCTAssertEqual(state.phase, .play)
        XCTAssertEqual(state.turnPlayer, "b")
    }

    // MARK: - Redaction

    /// The view's JSON with my own hand taken out: whatever card is left in
    /// it is a card somebody else's phone knows about.
    private func jsonWithoutMyHand(_ view: Rules.PlayerView) throws -> String {
        let stripped = Rules.PlayerView(
            phase: view.phase, turn: view.turn, rank: view.rank, turnPlayer: view.turnPlayer,
            turnEndsAt: view.turnEndsAt, challengeEndsAt: view.challengeEndsAt,
            revealUntil: view.revealUntil, wonUntil: view.wonUntil, seats: view.seats,
            pileCount: view.pileCount, lastPlay: view.lastPlay, reveal: view.reveal,
            myCards: [], canCall: view.canCall, winner: view.winner)
        return String(decoding: try OfflineCoding.encode(stripped), as: UTF8.self)
    }

    func testNobodySeesAnotherHandOrThePile() throws {
        var (state, rng) = started(seed: 3)
        let first = state.turnPlayer
        let laid = Array((state.hands[first] ?? []).prefix(3))
        try Rules.apply(.play(turn: 1, cards: laid), by: first, to: &state, now: 101, rng: &rng)

        for player in players {
            let view = Rules.view(of: state, for: player.id)
            XCTAssertEqual(view.myCards, state.hands[player.id])
            XCTAssertNil(view.reveal)
            XCTAssertEqual(view.pileCount, 3)
            XCTAssertEqual(view.lastPlay?.count, 3)
            XCTAssertEqual(view.canCall, player.id != first)
            XCTAssertEqual(view.seats.map(\.cards), players.map { state.hands[$0.id]?.count ?? 0 })
            let json = try jsonWithoutMyHand(view)
            XCTAssertFalse(json.contains("suit"), "a card leaked into \(player.name)'s view: \(json)")
        }
        let spectator = Rules.view(of: state, for: nil)
        XCTAssertTrue(spectator.myCards.isEmpty)
        XCTAssertFalse(spectator.canCall)
        let json = String(decoding: try OfflineCoding.encode(spectator), as: UTF8.self)
        XCTAssertFalse(json.contains("suit"))
    }

    func testACallShowsOnlyTheCalledCards() throws {
        var state = table(["a": [aceS, sevenD, twoC], "b": [kingS, nineH], "c": [OfflineCard(3, .clubs)]],
                          pile: [OfflineCard(4, .hearts), OfflineCard(5, .hearts)])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.play(turn: 1, cards: [sevenD]), by: "a", to: &state, now: 101, rng: &rng)
        try Rules.apply(.call(turn: 1), by: "b", to: &state, now: 102, rng: &rng)
        let view = Rules.view(of: state, for: "c")
        XCTAssertEqual(view.reveal?.cards, [sevenD])
        let json = try jsonWithoutMyHand(view)
        // The seven is public now; the fours and fives that were under it are not.
        XCTAssertFalse(json.contains("\"rank\":4"))
        XCTAssertFalse(json.contains("\"rank\":5"))
        XCTAssertTrue(json.contains("\"rank\":7"))
    }

    // MARK: - Whole games

    /// Random but legal play from every seat, with random calls and passes,
    /// many seeds and every table size: never a refusal, always an end.
    func testRandomGamesAlwaysFinish() throws {
        for seed in UInt64(1)...60 {
            let count = 3 + Int(seed % 3)
            let group = (1...count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            var rng = OfflineRNG(seed: seed)
            var choices = OfflineRNG(seed: seed &* 7919)
            var state = Rules.start(players: group, now: 0, rng: &rng)
            var now = 0.0
            var steps = 0
            while !Rules.isOver(state) && steps < 20_000 {
                steps += 1
                now += 0.5
                switch state.phase {
                case .play:
                    if choices.chance(0.05) { break } // sometimes let the clock run out
                    let hand = state.hands[state.turnPlayer] ?? []
                    let honest = hand.filter { $0.rank == state.rank }
                    let size = min(hand.count, choices.int(in: 1...4))
                    let cards = !honest.isEmpty && choices.chance(0.6)
                        ? Array(honest.prefix(size)) : Array(choices.shuffled(hand).prefix(size))
                    try Rules.apply(.play(turn: state.turn, cards: cards), by: state.turnPlayer, to: &state, now: now, rng: &rng)
                case .challenge:
                    guard let last = state.lastPlay else { XCTFail("no last play"); return }
                    let others = group.filter { $0.id != last.playerId && !state.passed.contains($0.id) }
                    if let who = choices.pick(others) {
                        if choices.chance(0.25) {
                            try Rules.apply(.call(turn: last.turn), by: who.id, to: &state, now: now, rng: &rng)
                        } else if choices.chance(0.7) {
                            try Rules.apply(.pass(turn: last.turn), by: who.id, to: &state, now: now, rng: &rng)
                        }
                    }
                case .reveal, .won, .over:
                    break
                }
                Rules.tick(&state, now: now, rng: &rng)
                let total = group.reduce(state.pile.count) { $0 + (state.hands[$1.id]?.count ?? 0) }
                XCTAssertEqual(total, 52, "cards went missing, seed \(seed)")
            }
            XCTAssertTrue(Rules.isOver(state), "seed \(seed) did not finish")
            let table = Rules.standings(state)
            XCTAssertEqual(table.count, count)
            if let winner = state.winner {
                XCTAssertEqual(table.first?.playerId, winner)
                XCTAssertEqual(state.hands[winner]?.count, 0)
            }
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.join(players[2], version: OfflineEnvelope.version)
        try room.choose("cheat")
        try room.start(seed: 11, now: 0)
        _ = room.outbox()

        var now = 0.0
        var plays = 0
        while room.phase == .playing && now < 5_000 {
            now += 0.5
            room.tick(now: now)
            for player in players {
                guard room.phase == .playing, let data = room.currentView(for: player.id) else { continue }
                let view = try OfflineCoding.decode(Rules.PlayerView.self, from: data)
                // Everyone plays honestly when they can; nobody ever calls.
                if view.phase == .play, view.turnPlayer == player.id {
                    let honest = view.myCards.filter { $0.rank == view.rank }
                    let cards = honest.isEmpty ? [view.myCards[0]] : Array(honest.prefix(4))
                    try room.act(OfflineCoding.encode(Rules.Action.play(turn: view.turn, cards: cards)),
                                 by: player.id, match: 1, now: now)
                    plays += 1
                } else if view.canCall, let last = view.lastPlay {
                    try room.act(OfflineCoding.encode(Rules.Action.pass(turn: last.turn)), by: player.id, match: 1, now: now)
                }
            }
            _ = room.outbox()
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertGreaterThan(plays, 10)
        XCTAssertEqual(room.standings?.count, 3)
        XCTAssertEqual(room.standings?.first?.score, 0)
        XCTAssertEqual(room.standings?.first?.detail, "went out")
    }
}
