import XCTest
@testable import SRAppleApp

/// Offline Liar's Dice: the deal, bids and their refusals, a call settled
/// both ways, rounds and going out, the clock, leaving, redaction, and the
/// computer player's odds and choices.
final class OfflineLiarsDiceTests: XCTestCase {
    private typealias Rules = OfflineLiarsDiceRules
    private let players = [OfflinePlayer(id: "a", name: "Ann"), OfflinePlayer(id: "b", name: "Ben"),
                           OfflinePlayer(id: "c", name: "Cat")]

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
    }

    func testSoloSeatsThreeComputerPlayers() {
        XCTAssertEqual(OfflinePlayModes.soloBots(Rules.info, hasBot: true), 3)
    }

    /// A three-player table with cups we choose, Ann to bid.
    private func table(_ cups: [String: [Int]] = ["a": [2, 2, 3, 5, 6], "b": [1, 2, 4, 4, 6], "c": [3, 3, 3, 5, 6]])
        -> (Rules.State, OfflineRNG) {
        var rng = OfflineRNG(seed: 1)
        var state = Rules.start(players: players, now: 0, rng: &rng)
        state.dice = cups
        state.turn = "a"
        return (state, rng)
    }

    private func refusal(_ action: Rules.Action, by id: String, _ state: Rules.State) -> String? {
        var copy = state
        var rng = OfflineRNG(seed: 0)
        do {
            try Rules.apply(action, by: id, to: &copy, now: 1, rng: &rng)
            return nil
        } catch {
            return (error as? OfflineRefusal)?.reason
        }
    }

    func testTheDeal() {
        var rng = OfflineRNG(seed: 3)
        let state = Rules.start(players: players, now: 0, rng: &rng)
        for player in players {
            XCTAssertEqual(state.counts[player.id], 5)
            XCTAssertEqual(state.dice[player.id]?.count, 5)
            XCTAssertTrue(state.dice[player.id]?.allSatisfy { (1...6).contains($0) } ?? false)
        }
        XCTAssertNotNil(state.turn)
        XCTAssertEqual(state.phase, .bidding)
        XCTAssertEqual(Rules.totalDice(state), 15)
    }

    func testBidsMustRise() throws {
        var (state, rng) = table()
        let turn = state.turnNumber
        XCTAssertEqual(refusal(.bid(turn: turn, quantity: 2, face: 3), by: "b", state), "It's Ann's turn.")
        XCTAssertEqual(refusal(.liar(turn: turn), by: "a", state), "Nobody has bid yet — open the bidding.")
        XCTAssertEqual(refusal(.bid(turn: turn, quantity: 2, face: 1), by: "a", state), "Ones are wild — bid on 2 to 6.")
        XCTAssertEqual(refusal(.bid(turn: turn, quantity: 16, face: 3), by: "a", state), "There are only 15 dice in play.")
        XCTAssertEqual(refusal(.bid(turn: turn - 1, quantity: 2, face: 3), by: "a", state), "That was for an earlier turn.")
        try Rules.apply(.bid(turn: turn, quantity: 3, face: 4), by: "a", to: &state, now: 1, rng: &rng)
        XCTAssertEqual(state.turn, "b")
        XCTAssertEqual(refusal(.bid(turn: state.turnNumber, quantity: 3, face: 3), by: "b", state),
                       "Bid more dice, or the same number of a higher face.")
        XCTAssertNil(refusal(.bid(turn: state.turnNumber, quantity: 3, face: 5), by: "b", state))
        XCTAssertNil(refusal(.bid(turn: state.turnNumber, quantity: 4, face: 2), by: "b", state))
    }

    func testACallTheBidSurvivesCostsTheCaller() throws {
        var (state, rng) = table()
        // Threes: Ann 1, Ben's wild one 1, Cat 3 = 5.
        try Rules.apply(.bid(turn: state.turnNumber, quantity: 5, face: 3), by: "a", to: &state, now: 1, rng: &rng)
        try Rules.apply(.liar(turn: state.turnNumber), by: "b", to: &state, now: 2, rng: &rng)
        XCTAssertEqual(state.phase, .reveal)
        let reveal = try XCTUnwrap(state.reveal)
        XCTAssertEqual(reveal.count, 5)
        XCTAssertTrue(reveal.bidStood)
        XCTAssertEqual(reveal.loserId, "b")
        XCTAssertEqual(state.counts["b"], 4)
        XCTAssertEqual(Rules.revealLine(reveal, name: { $0 == "b" ? "You" : $0 == "a" ? "Ann" : "Cat" }),
                       "You called Ann’s five 3s. There were 5 — You lose a die.")
        // Every cup is up for everyone now.
        XCTAssertEqual(Rules.view(of: state, for: "c").reveal?.cups.count, 3)

        // After the reveal, a fresh roll, and the loser opens.
        Rules.tick(&state, now: 2 + Rules.revealSeconds, rng: &rng)
        XCTAssertEqual(state.phase, .bidding)
        XCTAssertEqual(state.round, 2)
        XCTAssertEqual(state.turn, "b")
        XCTAssertEqual(state.dice["b"]?.count, 4)
        XCTAssertTrue(state.bids.isEmpty)
    }

    func testACaughtBluffCostsTheBidder() throws {
        var (state, rng) = table()
        try Rules.apply(.bid(turn: state.turnNumber, quantity: 4, face: 2), by: "a", to: &state, now: 1, rng: &rng)
        try Rules.apply(.bid(turn: state.turnNumber, quantity: 6, face: 6), by: "b", to: &state, now: 2, rng: &rng)
        // Sixes: 1 + 1 + 1, plus Ben's one = 4 < 6.
        try Rules.apply(.liar(turn: state.turnNumber), by: "c", to: &state, now: 3, rng: &rng)
        XCTAssertEqual(state.reveal?.count, 4)
        XCTAssertEqual(state.reveal?.loserId, "b")
        XCTAssertEqual(state.goodCalls["c"], 1)
    }

    func testGoingOutAndWinning() throws {
        var (state, rng) = table()
        state.counts = ["a": 1, "b": 1, "c": 0]
        state.outOrder = ["c"]
        state.outRound = ["c": 1]
        state.dice = ["a": [4], "b": [2], "c": []]
        try Rules.apply(.bid(turn: state.turnNumber, quantity: 2, face: 4), by: "a", to: &state, now: 1, rng: &rng)
        try Rules.apply(.liar(turn: state.turnNumber), by: "b", to: &state, now: 2, rng: &rng)
        XCTAssertEqual(state.reveal?.loserId, "a")
        XCTAssertEqual(state.reveal?.eliminated, true)
        Rules.tick(&state, now: 2 + Rules.revealSeconds, rng: &rng)
        XCTAssertEqual(state.phase, .done)
        XCTAssertEqual(Rules.winner(state), "b")
        Rules.tick(&state, now: 100, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["b", "a", "c"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(table.first?.detail, "won with 1 die left · 1 good call")
    }

    func testTheClockBidsForYou() {
        var (state, rng) = table()
        Rules.tick(&state, now: Rules.turnSeconds, rng: &rng)
        // Ann's favourite face (counting ones): 2s.
        XCTAssertEqual(state.bids.last, Rules.Bid(playerId: "a", quantity: 1, face: 2, auto: true))
        XCTAssertEqual(state.turn, "b")
        // Ben's clock runs out: one more of the same face.
        Rules.tick(&state, now: 2 * Rules.turnSeconds, rng: &rng)
        XCTAssertEqual(state.bids.last, Rules.Bid(playerId: "b", quantity: 2, face: 2, auto: true))
        // Repeated at the same instant, nothing more happens.
        let settled = state
        Rules.tick(&state, now: 2 * Rules.turnSeconds, rng: &rng)
        XCTAssertEqual(state, settled)
    }

    func testLeavingTakesYourDiceAndPassesTheTurn() {
        var (state, rng) = table()
        Rules.playerLeft("a", state: &state, now: 5, rng: &rng)
        XCTAssertEqual(state.turn, "b")
        XCTAssertEqual(Rules.totalDice(state), 10)
        XCTAssertEqual(state.outOrder, ["a"])
        Rules.playerLeft("b", state: &state, now: 6, rng: &rng)
        XCTAssertEqual(state.phase, .done)
        XCTAssertEqual(Rules.winner(state), "c")
        XCTAssertEqual(Rules.standings(state).last?.detail, "left in round 1")
    }

    func testEachPhoneSeesOnlyItsOwnCup() throws {
        let (state, _) = table()
        let ann = Rules.view(of: state, for: "a")
        XCTAssertEqual(ann.myDice, [2, 2, 3, 5, 6])
        XCTAssertNil(ann.reveal)
        let encoded = String(decoding: try OfflineCoding.encode(ann), as: UTF8.self)
        XCTAssertFalse(encoded.contains("[1,2,4,4,6]"), "Ben's cup is not in Ann's view")
        XCTAssertTrue(Rules.view(of: state, for: nil).myDice.isEmpty, "a spectator sees no dice")
    }

    // MARK: - The computer player

    func testTheOdds() {
        XCTAssertEqual(Rules.chance(atLeast: 0, of: 5), 1)
        XCTAssertEqual(Rules.chance(atLeast: 6, of: 5), 0)
        XCTAssertEqual(Rules.chance(atLeast: 1, of: 1), 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(Rules.chance(atLeast: 1, of: 2), 1 - 4.0 / 9, accuracy: 1e-9)
        XCTAssertEqual(Rules.chance(atLeast: 5, of: 15), 0.5959, accuracy: 0.001)
    }

    func testItCallsAnImpossibleBidAndRaisesASafeOne() {
        var rng = OfflineRNG(seed: 5)
        // Twelve 6s among fifteen dice, holding none: call it.
        let wild = Rules.Bid(playerId: "a", quantity: 12, face: 6, auto: false)
        let calls = Rules.botChoices(mine: [2, 3, 3, 4, 5], total: 15, standing: wild, turn: 4, rng: &rng)
        XCTAssertEqual(calls.first, .liar(turn: 4))
        // Two 3s, holding three of them: raise, never call.
        let small = Rules.Bid(playerId: "a", quantity: 2, face: 3, auto: false)
        for seed in 1...20 {
            var rng = OfflineRNG(seed: UInt64(seed))
            let raise = Rules.botChoices(mine: [1, 3, 3, 4, 5], total: 15, standing: small, turn: 4, rng: &rng)
            guard case .bid(_, let quantity, let face)? = raise.first else {
                return XCTFail("seed \(seed): \(String(describing: raise.first))")
            }
            XCTAssertNil(Rules.problem(quantity: quantity, face: face, standing: small, total: 15))
        }
    }

    func testItOpensOnWhatItHolds() {
        var rng = OfflineRNG(seed: 2)
        let open = Rules.botChoices(mine: [1, 5, 5, 5, 2], total: 10, standing: nil, turn: 1, rng: &rng)
        guard case .bid(_, let quantity, let face)? = open.first else { return XCTFail("no opening bid") }
        XCTAssertEqual(face, 5)
        XCTAssertTrue((3...5).contains(quantity), "\(quantity)")
    }

    func testTheBotMovesOnlyOnItsTurnThroughTheRoom() throws {
        var room = OfflineRoom(host: OfflinePlayer(id: "h", name: "Hana"), roomName: "Solo",
                               games: [OfflineGameEntry(withBot: Rules.self)])
        try room.choose("liars-dice")
        for _ in 0..<3 { _ = try room.addBot() }
        try room.start(seed: 8, now: 1_000)
        // The host never bids: the clock bids for them, the bots play on,
        // and the game runs to its end.
        var now = 1_000.0
        while room.phase == .playing && now < 30_000 {
            now += 0.5
            room.tick(now: now)
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.count, 4)
        XCTAssertEqual(room.standings?.first?.rank, 1)
    }
}
