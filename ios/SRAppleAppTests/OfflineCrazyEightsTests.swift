import XCTest
@testable import SRAppleApp

/// Crazy Eights' rules: the deal, what may be played, drawing and passing,
/// the turn timer, scoring a hand, the end of the match, players leaving,
/// and what each phone is allowed to see.
final class OfflineCrazyEightsTests: XCTestCase {
    private typealias Rules = CrazyEightsRules

    private let players = [
        OfflinePlayer(id: "a", name: "Ann"),
        OfflinePlayer(id: "b", name: "Ben"),
        OfflinePlayer(id: "c", name: "Cat"),
    ]

    private func started(seed: UInt64 = 1, now: Double = 100, players: [OfflinePlayer]? = nil) -> (Rules.State, OfflineRNG) {
        var rng = OfflineRNG(seed: seed)
        let state = Rules.start(players: players ?? self.players, now: now, rng: &rng)
        return (state, rng)
    }

    /// A hand laid out by hand: Ann to play, 7♥ on the pile.
    private func table() -> (Rules.State, OfflineRNG) {
        var (state, rng) = started()
        state.hands = [
            "a": [OfflineCard(5, .hearts), OfflineCard(7, .clubs), OfflineCard(8, .spades), OfflineCard(13, .diamonds)],
            "b": [OfflineCard(2, .clubs), OfflineCard(3, .clubs)],
            "c": [OfflineCard(12, .spades), OfflineCard(1, .diamonds), OfflineCard(10, .hearts)],
        ]
        state.discard = [OfflineCard(7, .hearts)]
        state.suit = .hearts
        state.stock = [OfflineCard(4, .spades), OfflineCard(9, .clubs), OfflineCard(6, .hearts)]
        state.turn = 0
        state.drawn = nil
        state.hasDrawn = false
        return (state, rng)
    }

    private func refusal(_ body: () throws -> Void) -> String? {
        do { try body() } catch { return (error as? OfflineRefusal)?.reason ?? "\(error)" }
        return nil
    }

    // MARK: - Setup

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(Rules.info.id, "crazy-eights")
        XCTAssertEqual(Rules.info.category, .card)
        XCTAssertEqual(Rules.info.minPlayers, 2)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    func testSevenEachForThreeAndFiveEachForFive() {
        let (three, _) = started()
        XCTAssertEqual(three.hands.values.map(\.count), [7, 7, 7])
        XCTAssertEqual(three.discard.count, 1)
        XCTAssertEqual(three.stock.count, 52 - 21 - 1)
        XCTAssertEqual(three.suit, three.discard.last?.suit)
        XCTAssertNotEqual(three.discard.last?.rank, 8, "the starter is never an eight")
        XCTAssertEqual(three.turn, 0)
        XCTAssertEqual(three.turnEndsAt, 100 + Rules.turnSeconds)
        XCTAssertEqual(three.phase, .playing)

        let five = (1...5).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
        let (state, _) = started(players: five)
        XCTAssertEqual(state.players.map { state.hands[$0.id]?.count }, [5, 5, 5, 5, 5])
        XCTAssertEqual(state.stock.count, 52 - 25 - 1)
        var all = state.stock + state.discard
        for hand in state.hands.values { all += hand }
        XCTAssertEqual(Set(all.map(\.id)).count, 52, "every card exactly once")
    }

    func testTheStarterIsNeverAnEightAcrossSeeds() {
        for seed in 1...300 {
            let (state, _) = started(seed: UInt64(seed))
            XCTAssertNotEqual(state.discard.last?.rank, 8)
            XCTAssertEqual(state.stock.count + state.discard.count + 21, 52)
        }
    }

    // MARK: - Playing

    func testAMatchingCardIsPlayed() throws {
        var (state, rng) = table()
        try Rules.apply(.play(turn: state.turnNumber, card: OfflineCard(5, .hearts), suit: nil), by: "a", to: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.discard.last, OfflineCard(5, .hearts))
        XCTAssertEqual(state.suit, .hearts)
        XCTAssertEqual(state.hands["a"]?.count, 3)
        XCTAssertEqual(state.turn, 1, "Ben is next")
        XCTAssertEqual(state.turnEndsAt, 101 + Rules.turnSeconds)
        XCTAssertEqual(state.lastMove, Rules.Move(playerId: "a", kind: .played, card: OfflineCard(5, .hearts), named: nil))
    }

    func testMatchingByRankIsAllowed() throws {
        var (state, rng) = table()
        try Rules.apply(.play(turn: state.turnNumber, card: OfflineCard(7, .clubs), suit: nil), by: "a", to: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.suit, .clubs, "the suit follows the new card")
    }

    func testAnEightNamesTheSuit() throws {
        var (state, rng) = table()
        let turn = state.turnNumber
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: turn, card: OfflineCard(8, .spades), suit: nil), by: "a", to: &state, now: 101, rng: &rng) },
                       "Name a suit for your eight.")
        try Rules.apply(.play(turn: turn, card: OfflineCard(8, .spades), suit: .clubs), by: "a", to: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.suit, .clubs)
        // Ben follows the named suit, not the eight's.
        try Rules.apply(.play(turn: state.turnNumber, card: OfflineCard(2, .clubs), suit: nil), by: "b", to: &state, now: 102, rng: &rng)
        // Cat has no club and no two: the queen of spades does not fit.
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: state.turnNumber, card: OfflineCard(12, .spades), suit: nil), by: "c", to: &state, now: 103, rng: &rng) },
                       "Follow clubs or play a 2 — or an eight.")
    }

    func testIllegalMovesAreRefused() throws {
        var (state, rng) = table()
        let turn = state.turnNumber
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: turn, card: OfflineCard(2, .clubs), suit: nil), by: "b", to: &state, now: 101, rng: &rng) },
                       "It's Ann's turn.")
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: turn), by: "zed", to: &state, now: 101, rng: &rng) },
                       "You are not in this game.")
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: turn, card: OfflineCard(2, .clubs), suit: nil), by: "a", to: &state, now: 101, rng: &rng) },
                       "You don't have that card.")
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: turn, card: OfflineCard(13, .diamonds), suit: nil), by: "a", to: &state, now: 101, rng: &rng) },
                       "Follow hearts or play a 7 — or an eight.")
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: turn, card: OfflineCard(5, .hearts), suit: .clubs), by: "a", to: &state, now: 101, rng: &rng) },
                       "Only an eight can name a suit.")
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: turn - 1, card: OfflineCard(5, .hearts), suit: nil), by: "a", to: &state, now: 101, rng: &rng) },
                       "That move was for an earlier turn.")
        XCTAssertEqual(refusal { try Rules.apply(.pass(turn: turn), by: "a", to: &state, now: 101, rng: &rng) },
                       "Draw a card first, or play one.")
        let before = state
        XCTAssertEqual(state, before, "refusals leave the table alone")
    }

    func testTurnsGoRoundInSeatOrder() throws {
        var (state, rng) = table()
        try Rules.apply(.play(turn: state.turnNumber, card: OfflineCard(7, .clubs), suit: nil), by: "a", to: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.turn, 1)
        try Rules.apply(.play(turn: state.turnNumber, card: OfflineCard(3, .clubs), suit: nil), by: "b", to: &state, now: 102, rng: &rng)
        XCTAssertEqual(state.turn, 2)
        // Cat draws the 6♥ (top of stock): it does not fit clubs or a 3, so the turn moves on.
        try Rules.apply(.draw(turn: state.turnNumber), by: "c", to: &state, now: 103, rng: &rng)
        XCTAssertEqual(state.turn, 0, "back to Ann")
        XCTAssertEqual(state.hands["c"]?.count, 4)
        XCTAssertEqual(state.lastMove?.kind, .drew)
        XCTAssertNil(state.lastMove?.card, "a drawn card is never named")
    }

    func testADrawnCardThatFitsMayBePlayedOrKept() throws {
        var (state, rng) = table()
        state.stock = [OfflineCard(9, .clubs), OfflineCard(9, .hearts)]
        let turn = state.turnNumber
        try Rules.apply(.draw(turn: turn), by: "a", to: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.turn, 0, "the 9♥ fits, so Ann may still play it")
        XCTAssertEqual(state.drawn, OfflineCard(9, .hearts))
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: turn), by: "a", to: &state, now: 101, rng: &rng) },
                       "You have already drawn this turn.")
        XCTAssertEqual(refusal { try Rules.apply(.play(turn: turn, card: OfflineCard(5, .hearts), suit: nil), by: "a", to: &state, now: 101, rng: &rng) },
                       "After drawing you may only play the card you drew.")
        var kept = state
        try Rules.apply(.pass(turn: turn), by: "a", to: &kept, now: 102, rng: &rng)
        XCTAssertEqual(kept.turn, 1)
        XCTAssertEqual(kept.hands["a"]?.count, 5)
        try Rules.apply(.play(turn: turn, card: OfflineCard(9, .hearts), suit: nil), by: "a", to: &state, now: 102, rng: &rng)
        XCTAssertEqual(state.discard.last, OfflineCard(9, .hearts))
        XCTAssertEqual(state.turn, 1)
    }

    func testAnEmptyStockTakesThePile() throws {
        var (state, rng) = table()
        state.stock = []
        state.discard = [OfflineCard(4, .clubs), OfflineCard(6, .diamonds), OfflineCard(7, .hearts)]
        try Rules.apply(.draw(turn: state.turnNumber), by: "a", to: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.discard, [OfflineCard(7, .hearts)], "the top card stays")
        XCTAssertEqual(state.stock.count + 1, 2, "one of the two reshuffled cards was drawn")
        XCTAssertEqual(state.hands["a"]?.count, 5)
    }

    func testWithNothingToDrawAPlayerMayPassAndAStuckHandEnds() throws {
        var (state, rng) = table()
        state.stock = []
        state.hands["a"] = [OfflineCard(13, .diamonds)]
        state.hands["b"] = [OfflineCard(2, .clubs)]
        state.hands["c"] = [OfflineCard(12, .spades)]
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: state.turnNumber), by: "a", to: &state, now: 101, rng: &rng) },
                       "There is nothing left to draw — pass instead.")
        XCTAssertTrue(Rules.view(of: state, for: "a").canPass)
        XCTAssertFalse(Rules.view(of: state, for: "a").canDraw)
        try Rules.apply(.pass(turn: state.turnNumber), by: "a", to: &state, now: 101, rng: &rng)
        try Rules.apply(.pass(turn: state.turnNumber), by: "b", to: &state, now: 102, rng: &rng)
        XCTAssertEqual(state.phase, .playing)
        try Rules.apply(.pass(turn: state.turnNumber), by: "c", to: &state, now: 103, rng: &rng)
        XCTAssertEqual(state.phase, .handOver, "a full round of passes blocks the hand")
        XCTAssertNil(state.handWinner)
        XCTAssertEqual(state.handPenalty, ["a": 10, "b": 2, "c": 10])
    }

    // MARK: - Scoring and the end

    func testGoingOutWinsTheHandAndOthersPay() throws {
        var (state, rng) = table()
        state.hands["a"] = [OfflineCard(5, .hearts)]
        state.hands["b"] = [OfflineCard(8, .clubs), OfflineCard(12, .clubs), OfflineCard(1, .clubs)]
        state.hands["c"] = [OfflineCard(10, .hearts), OfflineCard(3, .diamonds)]
        try Rules.apply(.play(turn: state.turnNumber, card: OfflineCard(5, .hearts), suit: nil), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.phase, .handOver)
        XCTAssertEqual(state.handWinner, "a")
        XCTAssertEqual(state.handPenalty, ["a": 0, "b": 61, "c": 13])
        XCTAssertEqual(state.scores, ["a": 0, "b": 61, "c": 13])
        XCTAssertEqual(state.nextHandAt, 110 + Rules.resultPause)
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: state.turnNumber), by: "b", to: &state, now: 111, rng: &rng) },
                       "This hand is over — the next deal is coming.")

        Rules.tick(&state, now: state.nextHandAt - 0.1, rng: &rng)
        XCTAssertEqual(state.phase, .handOver)
        Rules.tick(&state, now: state.nextHandAt, rng: &rng)
        XCTAssertEqual(state.phase, .playing)
        XCTAssertEqual(state.hand, 2)
        XCTAssertEqual(state.turn, 1, "the first turn moves round each hand")
        XCTAssertEqual(state.hands.values.map(\.count), [7, 7, 7])
        XCTAssertEqual(state.scores, ["a": 0, "b": 61, "c": 13], "totals carry over")
    }

    func testReachingTheTargetEndsTheMatchLowestWins() throws {
        var (state, rng) = table()
        state.scores = ["a": 40, "b": 90, "c": 30]
        state.hands["a"] = [OfflineCard(5, .hearts)]
        state.hands["b"] = [OfflineCard(13, .clubs)]
        state.hands["c"] = [OfflineCard(2, .diamonds)]
        try Rules.apply(.play(turn: state.turnNumber, card: OfflineCard(5, .hearts), suit: nil), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.scores, ["a": 40, "b": 100, "c": 32])
        XCTAssertFalse(Rules.isOver(state), "the hand's result shows first")
        Rules.tick(&state, now: state.nextHandAt, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(Rules.champions(state), ["c"])
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["c", "a", "b"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(table[1].detail, "won 1 hand")
        XCTAssertEqual(Rules.view(of: state, for: "b").champions, ["c"])
    }

    func testTiesShareARank() {
        var (state, _) = started()
        state.scores = ["a": 12, "b": 12, "c": 30]
        XCTAssertEqual(Rules.standings(state).map(\.rank), [1, 1, 3])
    }

    func testTheLastHandEndsTheMatch() throws {
        var (state, rng) = table()
        state.hand = Rules.maxHands
        state.hands["a"] = [OfflineCard(5, .hearts)]
        try Rules.apply(.play(turn: state.turnNumber, card: OfflineCard(5, .hearts), suit: nil), by: "a", to: &state, now: 110, rng: &rng)
        Rules.tick(&state, now: state.nextHandAt + 1, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: state.turnNumber), by: "b", to: &state, now: 120, rng: &rng) },
                       "The game is over.")
    }

    // MARK: - Time

    func testTheTurnTimerDrawsAndMovesOn() {
        var (state, rng) = table()
        let ends = state.turnEndsAt
        Rules.tick(&state, now: ends - 0.1, rng: &rng)
        XCTAssertEqual(state.turn, 0)
        Rules.tick(&state, now: ends + 0.3, rng: &rng)
        XCTAssertEqual(state.turn, 1, "a late tick still moves on")
        XCTAssertEqual(state.hands["a"]?.count, 5, "the host drew for Ann")
        XCTAssertEqual(state.lastMove?.kind, .timedOut)
        XCTAssertEqual(state.turnEndsAt, ends + 0.3 + Rules.turnSeconds)
        let settled = state
        Rules.tick(&state, now: ends + 0.3, rng: &rng)
        XCTAssertEqual(state, settled, "ticking twice at one instant changes nothing")
    }

    // MARK: - Leaving

    func testAPlayerWhoLeavesIsSkippedAndPaysForMissingHands() throws {
        var (state, rng) = table()
        Rules.playerLeft("b", state: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.away, ["b"])
        XCTAssertEqual(state.hands["b"], [])
        XCTAssertEqual(state.stock.count, 5, "Ben's two cards folded under the stock")
        try Rules.apply(.play(turn: state.turnNumber, card: OfflineCard(5, .hearts), suit: nil), by: "a", to: &state, now: 102, rng: &rng)
        XCTAssertEqual(state.turn, 2, "Ben's seat is skipped")
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: state.turnNumber), by: "b", to: &state, now: 103, rng: &rng) },
                       "You have left this game.")
        state.hands["c"] = [OfflineCard(10, .hearts)]
        try Rules.apply(.play(turn: state.turnNumber, card: OfflineCard(10, .hearts), suit: nil), by: "c", to: &state, now: 104, rng: &rng)
        XCTAssertEqual(state.handPenalty["b"], Rules.absentPenalty)
        Rules.tick(&state, now: state.nextHandAt, rng: &rng)
        XCTAssertEqual(state.hands["b"], [], "no cards dealt to an empty seat")
        XCTAssertEqual(state.hands["a"]?.count, 7)
        XCTAssertNotEqual(state.turn, 1)
        XCTAssertEqual(Rules.standings(state).first { $0.playerId == "b" }?.detail, "left")
    }

    func testTheCurrentPlayerLeavingPassesTheTurn() {
        var (state, rng) = table()
        let turn = state.turnNumber
        Rules.playerLeft("a", state: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.turnNumber, turn + 1)
    }

    func testFallingBelowTwoPlayersEndsTheMatch() {
        var (state, rng) = started(players: Array(players.prefix(2)))
        Rules.playerLeft("b", state: &state, now: 101, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(Rules.champions(state), ["a"])
        XCTAssertEqual(Rules.standings(state).first?.playerId, "a")
    }

    func testTheLastOneLeftTakesTheHandWithoutPaying() {
        var (state, rng) = started(players: Array(players.prefix(2)))
        state.hands["a"] = [OfflineCard(8, .hearts), OfflineCard(13, .clubs)]
        Rules.playerLeft("b", state: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.handWinner, "a")
        XCTAssertEqual(state.handPenalty["a"], 0, "the hand's winner pays nothing for the cards still held")
        XCTAssertEqual(state.scores["a"], 0)
        XCTAssertEqual(state.scores["b"], Rules.absentPenalty)
    }

    func testALeaverNeverOutranksThePlayersStillHere() {
        var (state, rng) = table()
        state.scores = ["a": 80, "b": 0, "c": 90]
        Rules.playerLeft("b", state: &state, now: 101, rng: &rng)
        state.phase = .over
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "c", "b"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(Rules.champions(state), ["a"])
    }

    func testALeaversPenaltiesDoNotEndTheMatchEarly() throws {
        var (state, rng) = table()
        Rules.playerLeft("b", state: &state, now: 101, rng: &rng)
        state.scores["b"] = 150
        state.hands["a"] = [OfflineCard(5, .hearts)]
        try Rules.apply(.play(turn: state.turnNumber, card: OfflineCard(5, .hearts), suit: nil), by: "a", to: &state, now: 102, rng: &rng)
        XCTAssertEqual(state.phase, .handOver)
        XCTAssertFalse(Rules.decided(state), "only the players still here can reach the target")
        Rules.tick(&state, now: state.nextHandAt, rng: &rng)
        XCTAssertEqual(state.phase, .playing)
    }

    // MARK: - Redaction

    func testNobodySeesAnotherHand() throws {
        var (state, rng) = table()
        state.stock = [OfflineCard(9, .clubs), OfflineCard(9, .hearts)]
        try Rules.apply(.draw(turn: state.turnNumber), by: "a", to: &state, now: 101, rng: &rng)

        let ann = Rules.view(of: state, for: "a")
        XCTAssertEqual(Set(ann.myCards.map(\.id)), Set(state.hands["a"]!.map(\.id)))
        XCTAssertEqual(ann.drawn, OfflineCard(9, .hearts))
        XCTAssertEqual(ann.playable, ["9H"])
        XCTAssertTrue(ann.canPass)
        XCTAssertFalse(ann.canDraw)

        for viewer in ["b", "c", nil] as [String?] {
            let view = Rules.view(of: state, for: viewer)
            let mine = viewer.flatMap { state.hands[$0] } ?? []
            XCTAssertEqual(view.myCards.count, mine.count)
            XCTAssertNil(view.drawn, "only Ann knows what she drew")
            XCTAssertEqual(view.playable, [])
            XCTAssertNil(view.lastMove?.card)
            let json = String(decoding: try OfflineCoding.encode(view), as: UTF8.self)
            for card in state.hands["a"]! where card != view.top {
                XCTAssertFalse(view.myCards.contains(card))
                let leaked = json.contains("\"rank\":\(card.rank),\"suit\":\"\(card.suit.rawValue)\"")
                    || json.contains("\"suit\":\"\(card.suit.rawValue)\",\"rank\":\(card.rank)")
                XCTAssertFalse(leaked, "\(card) leaked to \(viewer ?? "a spectator")")
            }
            XCTAssertEqual(view.seats.map(\.cards), [5, 2, 3], "counts only")
        }
        XCTAssertEqual(Rules.view(of: state, for: nil).myCards, [])
    }

    func testEveryViewHidesEveryOtherHandAndTheStock() throws {
        for count in 2...5 {
            let seats = (0..<count).map { OfflinePlayer(id: "p\($0)", name: "Player \($0)") }
            var (state, rng) = started(seed: UInt64(20 + count), players: seats)
            // A few turns in, so a drawn card may be sitting in someone's hand.
            for step in 0..<6 where state.phase == .playing {
                let id = state.players[state.turn].id
                let view = Rules.view(of: state, for: id)
                if let card = view.myCards.first(where: { view.playable.contains($0.id) }) {
                    try Rules.apply(.play(turn: view.turnNumber, card: card, suit: card.rank == 8 ? .hearts : nil),
                                    by: id, to: &state, now: 101 + Double(step), rng: &rng)
                } else if view.canDraw {
                    try Rules.apply(.draw(turn: view.turnNumber), by: id, to: &state, now: 101 + Double(step), rng: &rng)
                } else {
                    try Rules.apply(.pass(turn: view.turnNumber), by: id, to: &state, now: 101 + Double(step), rng: &rng)
                }
            }
            for viewer in seats.map({ Optional($0.id) }) + [nil] {
                let json = String(decoding: try OfflineCoding.encode(Rules.view(of: state, for: viewer)), as: UTF8.self)
                let secrets = seats.filter { $0.id != viewer }.flatMap { state.hands[$0.id] ?? [] } + state.stock
                for card in secrets {
                    let encoded = String(decoding: try OfflineCoding.encode(card), as: UTF8.self)
                    XCTAssertFalse(json.contains(encoded), "\(card) leaked to \(viewer ?? "a spectator") (\(count) players)")
                }
            }
        }
    }

    func testPlayableCardsShowOnlyOnMyTurn() {
        let (state, _) = table()
        XCTAssertEqual(Set(Rules.view(of: state, for: "a").playable), ["5H", "7C", "8S"])
        XCTAssertEqual(Rules.view(of: state, for: "b").playable, [])
        XCTAssertEqual(Rules.view(of: state, for: "a").turnPlayer, "a")
        XCTAssertTrue(Rules.view(of: state, for: "a").canDraw)
        XCTAssertFalse(Rules.view(of: state, for: "b").canDraw)
    }

    // MARK: - Whole games

    /// Random but legal play from many seeds and table sizes always finishes.
    func testRandomGamesAlwaysFinish() throws {
        for seed in 1...120 {
            let count = 2 + seed % 4
            let seats = (1...count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            var (state, rng) = started(seed: UInt64(seed), now: 0, players: seats)
            var chooser = OfflineRNG(seed: UInt64(seed) &* 31 &+ 7)
            var now = 0.0
            var steps = 0
            while !Rules.isOver(state) && steps < 20_000 {
                steps += 1
                now += 0.5
                if state.phase != .playing {
                    Rules.tick(&state, now: now, rng: &rng)
                    continue
                }
                // Now and then, let the clock run out instead.
                if chooser.chance(0.02) {
                    Rules.tick(&state, now: state.turnEndsAt, rng: &rng)
                    continue
                }
                let id = state.players[state.turn].id
                let view = Rules.view(of: state, for: id)
                let action: Rules.Action
                if let pick = chooser.pick(view.playable), chooser.chance(0.85) {
                    let card = try XCTUnwrap(view.myCards.first { $0.id == pick })
                    action = .play(turn: view.turnNumber, card: card, suit: card.rank == 8 ? chooser.pick(OfflineSuit.allCases) : nil)
                } else if view.canDraw {
                    action = .draw(turn: view.turnNumber)
                } else if view.canPass {
                    action = .pass(turn: view.turnNumber)
                } else {
                    let card = try XCTUnwrap(view.myCards.first { $0.id == view.playable.first })
                    action = .play(turn: view.turnNumber, card: card, suit: card.rank == 8 ? .hearts : nil)
                }
                try Rules.apply(action, by: id, to: &state, now: now, rng: &rng)

                var cards = state.stock + state.discard
                for hand in state.hands.values { cards += hand }
                XCTAssertEqual(cards.count, 52, "seed \(seed): the deck stays whole")
            }
            XCTAssertTrue(Rules.isOver(state), "seed \(seed) did not finish")
            XCTAssertEqual(Rules.standings(state).count, count)
            XCTAssertFalse(Rules.champions(state).isEmpty)
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("crazy-eights")
        try room.start(seed: 11, now: 0)
        _ = room.outbox()

        var now = 0.0
        var steps = 0
        while room.phase == .playing && steps < 20_000 {
            steps += 1
            now += 0.5
            room.tick(now: now)
            for id in ["a", "b"] {
                guard let data = room.currentView(for: id) else { continue }
                let view = try OfflineCoding.decode(Rules.PlayerView.self, from: data)
                guard view.turnPlayer == id else { continue }
                let action: Rules.Action
                if let id = view.playable.first, let card = view.myCards.first(where: { $0.id == id }) {
                    action = .play(turn: view.turnNumber, card: card, suit: card.rank == 8 ? card.suit : nil)
                } else if view.canDraw {
                    action = .draw(turn: view.turnNumber)
                } else {
                    action = .pass(turn: view.turnNumber)
                }
                try room.act(OfflineCoding.encode(action), by: id, match: 1, now: now)
            }
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.count, 2)
    }
}
