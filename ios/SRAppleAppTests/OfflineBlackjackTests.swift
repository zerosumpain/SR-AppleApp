import XCTest
@testable import SRAppleApp

/// Blackjack's rules: betting, the deal, hit/stand/double/split, the dealer's
/// draw, the payouts, the timers, players leaving, the end of the match, and
/// that nobody ever sees the dealer's hole card early.
final class OfflineBlackjackTests: XCTestCase {
    private typealias Rules = BlackjackRules

    private let players = [
        OfflinePlayer(id: "a", name: "Ann"),
        OfflinePlayer(id: "b", name: "Ben"),
    ]

    private func started(seed: UInt64 = 1, now: Double = 100, players: [OfflinePlayer]? = nil) -> (Rules.State, OfflineRNG) {
        var rng = OfflineRNG(seed: seed)
        let state = Rules.start(players: players ?? self.players, now: now, rng: &rng)
        return (state, rng)
    }

    private func card(_ rank: Int, _ suit: OfflineSuit = .clubs) -> OfflineCard { OfflineCard(rank, suit) }

    /// Make the next cards off the shoe come out in `cards` order, with plenty
    /// of filler underneath so the deal does not reshuffle.
    private func stack(_ state: inout Rules.State, _ cards: [OfflineCard]) {
        let filler = Array(repeating: card(2, .spades), count: 200)
        state.shoe = filler + cards.reversed()
    }

    /// Both players bet; the deal happens on the last bet.
    private func betAll(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ amounts: [String: Int], now: Double = 101) throws {
        for player in players where amounts[player.id] != nil {
            try Rules.apply(.bet(round: state.round, amount: amounts[player.id]!), by: player.id, to: &state, now: now, rng: &rng)
        }
    }

    private func act(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ id: String,
                     _ make: (Int) -> Rules.Action, now: Double = 102) throws {
        try Rules.apply(make(state.move), by: id, to: &state, now: now, rng: &rng)
    }

    /// Run the dealer's turn to the settle.
    private func runDealer(_ state: inout Rules.State, _ rng: inout OfflineRNG, from now: Double = 103) {
        var t = now
        while state.phase == .dealer && t < now + 60 {
            Rules.tick(&state, now: t, rng: &rng)
            t += Rules.dealerStep
        }
    }

    private func refusal(_ block: () throws -> Void) -> String? {
        do { try block(); return nil } catch { return (error as? OfflineRefusal)?.reason ?? "\(error)" }
    }

    // MARK: - Basics

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(Rules.info.id, "blackjack")
        XCTAssertEqual(Rules.info.category, .card)
        XCTAssertEqual(Rules.info.minPlayers, 1)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    func testCountingHands() {
        XCTAssertEqual(Rules.total([card(1), card(13)]), 21)
        XCTAssertTrue(Rules.isBlackjack([card(1), card(12)]))
        XCTAssertEqual(Rules.total([card(1), card(1), card(9)]), 21)
        XCTAssertEqual(Rules.total([card(1), card(6)]), 17)
        XCTAssertTrue(Rules.isSoft([card(1), card(6)]))
        XCTAssertEqual(Rules.total([card(1), card(6), card(10)]), 17)
        XCTAssertFalse(Rules.isSoft([card(1), card(6), card(10)]))
        XCTAssertEqual(Rules.total([card(10), card(12), card(2)]), 22)
    }

    func testAMatchOpensOnBetting() {
        let (state, _) = started(now: 100)
        XCTAssertEqual(state.round, 1)
        XCTAssertEqual(state.phase, .betting)
        XCTAssertEqual(state.bettingEndsAt, 100 + Rules.bettingTime)
        XCTAssertEqual(state.chips, ["a": 100, "b": 100])
        XCTAssertEqual(state.shoe.count, 6 * 52)
        XCTAssertTrue(state.hands.isEmpty)
        XCTAssertTrue(state.dealer.isEmpty)
        XCTAssertFalse(Rules.isOver(state))
        let view = Rules.view(of: state, for: "a")
        XCTAssertEqual(view.myMaxBet, 25)
        XCTAssertEqual(Rules.view(of: state, for: nil).myMaxBet, 0)
    }

    func testTheSeedDecidesTheShoe() {
        XCTAssertEqual(started(seed: 4).0, started(seed: 4).0)
        XCTAssertNotEqual(started(seed: 4).0.shoe, started(seed: 5).0.shoe)
    }

    // MARK: - Betting

    func testBadBetsAreRefused() {
        var (state, rng) = started()
        XCTAssertEqual(refusal { try Rules.apply(.bet(round: 1, amount: 4), by: "a", to: &state, now: 101, rng: &rng) },
                       "Bets are 5 to 25 chips.")
        XCTAssertEqual(refusal { try Rules.apply(.bet(round: 1, amount: 26), by: "a", to: &state, now: 101, rng: &rng) },
                       "Bets are 5 to 25 chips.")
        XCTAssertEqual(refusal { try Rules.apply(.bet(round: 2, amount: 10), by: "a", to: &state, now: 101, rng: &rng) },
                       "That bet was for another round.")
        XCTAssertEqual(refusal { try Rules.apply(.bet(round: 1, amount: 10), by: "zed", to: &state, now: 101, rng: &rng) },
                       "You are not at this table.")
        XCTAssertEqual(refusal { try Rules.apply(.hit(move: state.move), by: "a", to: &state, now: 101, rng: &rng) },
                       "Nobody is playing a hand right now.")
        XCTAssertNil(refusal { try Rules.apply(.bet(round: 1, amount: 10), by: "a", to: &state, now: 101, rng: &rng) })
        XCTAssertEqual(state.chips["a"], 90)
        XCTAssertEqual(refusal { try Rules.apply(.bet(round: 1, amount: 10), by: "a", to: &state, now: 101, rng: &rng) },
                       "You have already bet this round.")
        XCTAssertEqual(Rules.view(of: state, for: "a").myMaxBet, 0)

        state.chips["b"] = 7
        XCTAssertEqual(refusal { try Rules.apply(.bet(round: 1, amount: 10), by: "b", to: &state, now: 101, rng: &rng) },
                       "You only have 7 chips.")
        XCTAssertEqual(Rules.view(of: state, for: "b").myMaxBet, 7)
        state.chips["b"] = 3
        XCTAssertEqual(refusal { try Rules.apply(.bet(round: 1, amount: 5), by: "b", to: &state, now: 101, rng: &rng) },
                       "You don't have enough chips to bet.")
    }

    func testTheLastBetDeals() throws {
        var (state, rng) = started()
        stack(&state, [card(10), card(9), card(7), card(8), card(6), card(10, .hearts)])
        try Rules.apply(.bet(round: 1, amount: 10), by: "a", to: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.phase, .betting, "still waiting for Ben")
        try Rules.apply(.bet(round: 1, amount: 20), by: "b", to: &state, now: 102, rng: &rng)
        XCTAssertEqual(state.phase, .playing)
        // Round the table: Ann, Ben, dealer, Ann, Ben, dealer.
        XCTAssertEqual(state.hands["a"]?.first?.cards, [card(10), card(8)])
        XCTAssertEqual(state.hands["b"]?.first?.cards, [card(9), card(6)])
        XCTAssertEqual(state.dealer, [card(7), card(10, .hearts)])
        XCTAssertEqual(state.chips, ["a": 90, "b": 80])
        XCTAssertEqual(state.order, ["a", "b"])
        XCTAssertEqual(state.turnEndsAt, 102 + Rules.turnTime)
    }

    func testTheBettingTimerSitsOutTheSlow() throws {
        var (state, rng) = started(now: 100)
        try Rules.apply(.bet(round: 1, amount: 5), by: "b", to: &state, now: 101, rng: &rng)
        Rules.tick(&state, now: state.bettingEndsAt - 0.1, rng: &rng)
        XCTAssertEqual(state.phase, .betting)
        Rules.tick(&state, now: state.bettingEndsAt, rng: &rng)
        XCTAssertNotEqual(state.phase, .betting)
        XCTAssertEqual(state.order, ["b"])
        XCTAssertNil(state.hands["a"])
        XCTAssertEqual(state.chips["a"], 100)
    }

    func testNobodyBettingPassesTheRound() {
        var (state, rng) = started(now: 100)
        Rules.tick(&state, now: state.bettingEndsAt, rng: &rng)
        XCTAssertEqual(state.phase, .settled)
        XCTAssertTrue(state.dealer.isEmpty)
        Rules.tick(&state, now: state.nextRoundAt, rng: &rng)
        XCTAssertEqual(state.round, 2)
        XCTAssertEqual(state.phase, .betting)
    }

    func testTheShoeIsReshuffledPastThePenetration() throws {
        var (state, rng) = started()
        state.shoe = Array(state.shoe.prefix(70))
        try betAll(&state, &rng, ["a": 5, "b": 5])
        XCTAssertTrue(state.reshuffled)
        XCTAssertEqual(state.shoe.count, 6 * 52 - 6)
        XCTAssertTrue(Rules.view(of: state, for: "a").reshuffled)
    }

    // MARK: - Playing

    func testTurnsGoInSeatOrder() throws {
        var (state, rng) = started()
        stack(&state, [card(10), card(9), card(7), card(5), card(6), card(10, .hearts), card(3), card(10, .spades)])
        try betAll(&state, &rng, ["a": 10, "b": 10])
        XCTAssertEqual(refusal { try act(&state, &rng, "b") { .hit(move: $0) } }, "It's Ann's turn.")
        XCTAssertEqual(refusal { try Rules.apply(.hit(move: state.move - 1), by: "a", to: &state, now: 102, rng: &rng) },
                       "The table has moved on since then.")
        try act(&state, &rng, "a") { .hit(move: $0) }
        XCTAssertEqual(state.hands["a"]?[0].cards.count, 3)
        XCTAssertEqual(state.hands["a"]?[0].total, 18)
        XCTAssertEqual(Rules.view(of: state, for: "a").turnPlayer, "a")
        try act(&state, &rng, "a") { .stand(move: $0) }
        XCTAssertEqual(Rules.view(of: state, for: "a").turnPlayer, "b")
        XCTAssertEqual(refusal { try act(&state, &rng, "a") { .hit(move: $0) } }, "It's Ben's turn.")
        try act(&state, &rng, "b") { .hit(move: $0) }
        XCTAssertTrue(state.hands["b"]?[0].busted ?? false, "9 + 6 + 10 is 25")
        XCTAssertEqual(state.phase, .dealer)
        XCTAssertTrue(state.holeShown)
    }

    func testTwentyOneStopsTheHand() throws {
        var (state, rng) = started()
        stack(&state, [card(10), card(9), card(7), card(5), card(6), card(10, .hearts), card(6, .hearts)])
        try betAll(&state, &rng, ["a": 10, "b": 10])
        try act(&state, &rng, "a") { .hit(move: $0) }
        XCTAssertEqual(state.hands["a"]?[0].total, 21)
        XCTAssertTrue(state.hands["a"]?[0].done ?? false)
        XCTAssertEqual(Rules.view(of: state, for: "b").turnPlayer, "b")
    }

    func testTheDealerDrawsToSixteenAndStandsOnSoftSeventeen() throws {
        var (state, rng) = started()
        // Dealer 6 + 5, then draws an ace: 6 + 5 + A = 12 (hard) → draws 5 → 17.
        stack(&state, [card(10), card(10, .hearts), card(6), card(9), card(9, .hearts), card(5), card(1), card(5, .hearts)])
        try betAll(&state, &rng, ["a": 10, "b": 10])
        try act(&state, &rng, "a") { .stand(move: $0) }
        try act(&state, &rng, "b") { .stand(move: $0) }
        runDealer(&state, &rng)
        XCTAssertEqual(state.dealer, [card(6), card(5), card(1), card(5, .hearts)])
        XCTAssertEqual(Rules.total(state.dealer), 17)
        XCTAssertEqual(state.phase, .settled)

        // A soft 17 stands.
        var (soft, rng2) = started(seed: 2)
        stack(&soft, [card(10), card(10, .hearts), card(1), card(9), card(9, .hearts), card(6), card(4)])
        try betAll(&soft, &rng2, ["a": 10, "b": 10])
        try act(&soft, &rng2, "a") { .stand(move: $0) }
        try act(&soft, &rng2, "b") { .stand(move: $0) }
        runDealer(&soft, &rng2)
        XCTAssertEqual(soft.dealer, [card(1), card(6)])
        XCTAssertEqual(soft.phase, .settled)
    }

    func testPayouts() throws {
        var (state, rng) = started()
        // Ann: A + K blackjack. Ben: 10 + 8 = 18. Dealer: 10 + 7 = 17.
        stack(&state, [card(1), card(10), card(10, .hearts), card(13), card(8), card(7)])
        try betAll(&state, &rng, ["a": 10, "b": 20])
        XCTAssertTrue(state.hands["a"]?[0].done ?? false, "a blackjack needs no decision")
        XCTAssertEqual(Rules.view(of: state, for: "b").turnPlayer, "b")
        try act(&state, &rng, "b") { .stand(move: $0) }
        runDealer(&state, &rng)
        XCTAssertEqual(state.hands["a"]?[0].outcome, .blackjack)
        XCTAssertEqual(state.hands["b"]?[0].outcome, .win)
        XCTAssertEqual(state.chips["a"], 115, "3 to 2 on 10")
        XCTAssertEqual(state.chips["b"], 120)
        XCTAssertEqual(state.lastNet, ["a": 15, "b": 20])
        XCTAssertEqual(Rules.view(of: state, for: "a").seats.map(\.net), [15, 20])
    }

    func testPushLoseAndBust() throws {
        var (state, rng) = started()
        // Ann 10 + 7 = 17 (push vs 17). Ben 10 + 6 = 16, stands, loses. Dealer 10 + 7.
        stack(&state, [card(10), card(10, .hearts), card(10, .spades), card(7), card(6), card(7, .hearts)])
        try betAll(&state, &rng, ["a": 5, "b": 7])
        try act(&state, &rng, "a") { .stand(move: $0) }
        try act(&state, &rng, "b") { .stand(move: $0) }
        runDealer(&state, &rng)
        XCTAssertEqual(state.hands["a"]?[0].outcome, .push)
        XCTAssertEqual(state.hands["b"]?[0].outcome, .lose)
        XCTAssertEqual(state.chips, ["a": 100, "b": 93])

        // A bust loses even when the dealer busts too.
        var (bust, rng2) = started(seed: 3)
        stack(&bust, [card(10), card(10, .hearts), card(10, .spades), card(6), card(9), card(6, .hearts), card(5), card(10, .diamonds)])
        try betAll(&bust, &rng2, ["a": 10, "b": 10])
        try act(&bust, &rng2, "a") { .hit(move: $0) }   // 10 + 6 + 5 = 21, done
        try act(&bust, &rng2, "b") { .hit(move: $0) }   // 10 + 9 + 10 = 29, bust
        runDealer(&bust, &rng2)
        XCTAssertEqual(bust.hands["b"]?[0].outcome, .bust)
        XCTAssertEqual(bust.chips["b"], 90)
        XCTAssertEqual(bust.chips["a"], 110, "21 against the dealer's 16-and-draw")
    }

    func testDoubling() throws {
        var (state, rng) = started()
        // Ann 6 + 5 = 11 doubles into a 10. Ben 10 + 9. Dealer 10 + 8.
        stack(&state, [card(6), card(10), card(10, .hearts), card(5), card(9), card(8), card(10, .spades)])
        try betAll(&state, &rng, ["a": 20, "b": 10])
        XCTAssertTrue(Rules.view(of: state, for: "a").canDouble)
        XCTAssertFalse(Rules.view(of: state, for: "b").canDouble, "not Ben's turn")
        try act(&state, &rng, "a") { .double(move: $0) }
        let hand = try XCTUnwrap(state.hands["a"]?[0])
        XCTAssertEqual(hand.bet, 40)
        XCTAssertTrue(hand.doubled)
        XCTAssertTrue(hand.done)
        XCTAssertEqual(hand.total, 21)
        XCTAssertEqual(state.chips["a"], 60)
        try act(&state, &rng, "b") { .stand(move: $0) }
        XCTAssertEqual(refusal { try act(&state, &rng, "b") { .double(move: $0) } }, "Nobody is playing a hand right now.")
        runDealer(&state, &rng)
        XCTAssertEqual(state.chips["a"], 140)
    }

    func testDoublingNeedsTwoCardsAndTheChips() throws {
        var (state, rng) = started()
        stack(&state, [card(2), card(10), card(10, .hearts), card(3), card(9), card(8), card(4)])
        state.chips["a"] = 30
        try betAll(&state, &rng, ["a": 25, "b": 10])
        XCTAssertFalse(Rules.view(of: state, for: "a").canDouble)
        XCTAssertEqual(refusal { try act(&state, &rng, "a") { .double(move: $0) } }, "You need 25 more chips to double.")
        state.chips["a"] = 100
        try act(&state, &rng, "a") { .hit(move: $0) }
        XCTAssertEqual(refusal { try act(&state, &rng, "a") { .double(move: $0) } },
                       "You can only double on your first two cards.")
    }

    func testSplittingAPair() throws {
        var (state, rng) = started()
        // Ann 8 + 8 splits; each 8 gets a 3 then a 10. Ben 10 + 9. Dealer 10 + 7.
        stack(&state, [card(8), card(10), card(10, .hearts), card(8, .hearts), card(9), card(7), card(3), card(3, .hearts)])
        try betAll(&state, &rng, ["a": 10, "b": 10])
        XCTAssertTrue(Rules.view(of: state, for: "a").canSplit)
        try act(&state, &rng, "a") { .split(move: $0) }
        var hands = try XCTUnwrap(state.hands["a"])
        XCTAssertEqual(hands.count, 2)
        XCTAssertEqual(hands.map(\.cards), [[card(8), card(3)], [card(8, .hearts), card(3, .hearts)]])
        XCTAssertEqual(hands.map(\.bet), [10, 10])
        XCTAssertEqual(state.chips["a"], 80)
        XCTAssertEqual(state.turnHand, 0)
        XCTAssertFalse(Rules.view(of: state, for: "a").canSplit, "only one split")
        XCTAssertEqual(refusal { try act(&state, &rng, "a") { .split(move: $0) } }, "You can only split once.")

        stack(&state, [card(10, .spades), card(10, .diamonds)])
        try act(&state, &rng, "a") { .hit(move: $0) }       // 8 + 3 + 10 = 21: done
        XCTAssertEqual(state.turnHand, 1)
        XCTAssertEqual(Rules.view(of: state, for: "a").turnHand, 1)
        try act(&state, &rng, "a") { .hit(move: $0) }       // second hand 21 too
        XCTAssertEqual(Rules.view(of: state, for: "b").turnPlayer, "b")
        try act(&state, &rng, "b") { .stand(move: $0) }
        runDealer(&state, &rng)
        hands = try XCTUnwrap(state.hands["a"])
        XCTAssertEqual(hands.map(\.outcome), [.win, .win])
        XCTAssertEqual(state.chips["a"], 120)
    }

    func testOnlyAPairSplits() throws {
        var (state, rng) = started()
        stack(&state, [card(8), card(10), card(10, .hearts), card(9, .hearts), card(9), card(7)])
        try betAll(&state, &rng, ["a": 10, "b": 10])
        XCTAssertFalse(Rules.view(of: state, for: "a").canSplit)
        XCTAssertEqual(refusal { try act(&state, &rng, "a") { .split(move: $0) } }, "You can only split a pair.")
    }

    func testSplitAcesTakeOneCardAndAreNotBlackjack() throws {
        var (state, rng) = started()
        stack(&state, [card(1), card(10), card(10, .hearts), card(1, .hearts), card(9), card(7), card(13), card(5)])
        try betAll(&state, &rng, ["a": 10, "b": 10])
        try act(&state, &rng, "a") { .split(move: $0) }
        let hands = try XCTUnwrap(state.hands["a"])
        XCTAssertTrue(hands.allSatisfy(\.done))
        XCTAssertEqual(hands[0].total, 21)
        XCTAssertFalse(hands[0].isBlackjack)
        XCTAssertEqual(Rules.view(of: state, for: "b").turnPlayer, "b")
        try act(&state, &rng, "b") { .stand(move: $0) }
        runDealer(&state, &rng)
        XCTAssertEqual(state.hands["a"]?[0].outcome, .win)
        XCTAssertEqual(state.hands["a"]?[0].returned, 20, "even money, not 3 to 2")
    }

    func testADealerBlackjackEndsTheRoundAtOnce() throws {
        var (state, rng) = started()
        // Ann A + K (push), Ben 10 + 9 (loses). Dealer A + Q.
        stack(&state, [card(1), card(10), card(1, .hearts), card(13), card(9), card(12)])
        try betAll(&state, &rng, ["a": 10, "b": 10])
        XCTAssertEqual(state.phase, .settled)
        XCTAssertEqual(state.hands["a"]?[0].outcome, .push)
        XCTAssertEqual(state.hands["b"]?[0].outcome, .lose)
        XCTAssertEqual(state.chips, ["a": 100, "b": 90])
        XCTAssertEqual(Rules.view(of: state, for: "b").dealerCards.count, 2)
    }

    // MARK: - Secrets

    func testTheHoleCardStaysHiddenUntilTheDealersTurn() throws {
        var (state, rng) = started()
        let hole = card(13, .diamonds)
        stack(&state, [card(10), card(9), card(7), card(8), card(6), hole])
        try betAll(&state, &rng, ["a": 10, "b": 10])
        XCTAssertEqual(state.phase, .playing)
        for id in ["a", "b", nil] as [String?] {
            let view = Rules.view(of: state, for: id)
            XCTAssertEqual(view.dealerCards, [card(7)])
            XCTAssertEqual(view.dealerHidden, 1)
            XCTAssertEqual(view.dealerTotal, 7)
            let shown = view.seats.flatMap { $0.hands.flatMap(\.cards) } + view.dealerCards
            XCTAssertFalse(shown.contains(hole), "the hole card leaked to \(id ?? "a spectator")")
            let json = try String(decoding: OfflineCoding.encode(view), as: UTF8.self)
            XCTAssertFalse(json.contains("diamonds"), "nothing on the table is a diamond but the hole card")
            XCTAssertFalse(view.canHit && id != "a")
        }
        try act(&state, &rng, "a") { .stand(move: $0) }
        try act(&state, &rng, "b") { .stand(move: $0) }
        let after = Rules.view(of: state, for: "b")
        XCTAssertEqual(after.dealerCards, [card(7), hole])
        XCTAssertEqual(after.dealerHidden, 0)
    }

    func testOnlyThePlayerWhoseTurnItIsGetsButtons() throws {
        var (state, rng) = started()
        stack(&state, [card(10), card(9), card(7), card(5), card(6), card(10, .hearts)])
        try betAll(&state, &rng, ["a": 10, "b": 10])
        let ann = Rules.view(of: state, for: "a")
        XCTAssertTrue(ann.canHit && ann.canStand)
        let ben = Rules.view(of: state, for: "b")
        XCTAssertFalse(ben.canHit || ben.canStand || ben.canDouble || ben.canSplit)
        let watcher = Rules.view(of: state, for: nil)
        XCTAssertFalse(watcher.canHit || watcher.canStand)
    }

    // MARK: - Timers and leaving

    func testTheTurnTimerStandsTheHand() throws {
        var (state, rng) = started()
        stack(&state, [card(10), card(9), card(7), card(5), card(6), card(10, .hearts)])
        try betAll(&state, &rng, ["a": 10, "b": 10], now: 101)
        let ends = state.turnEndsAt
        Rules.tick(&state, now: ends - 0.1, rng: &rng)
        XCTAssertEqual(Rules.view(of: state, for: "a").turnPlayer, "a")
        Rules.tick(&state, now: ends, rng: &rng)
        let snapshot = state
        Rules.tick(&state, now: ends, rng: &rng)
        XCTAssertEqual(state, snapshot, "a repeated tick changes nothing")
        XCTAssertTrue(state.hands["a"]?[0].done ?? false)
        XCTAssertEqual(state.hands["a"]?[0].cards.count, 2)
        XCTAssertEqual(state.timeouts["a"], 1)
        XCTAssertEqual(Rules.view(of: state, for: "a").turnPlayer, "b")
        XCTAssertEqual(state.turnEndsAt, ends + Rules.turnTime)
    }

    func testAPlayerWhoLeavesInTheBettingWindowIsNotWaitedFor() throws {
        var (state, rng) = started()
        try Rules.apply(.bet(round: 1, amount: 10), by: "a", to: &state, now: 101, rng: &rng)
        Rules.playerLeft("b", state: &state, now: 102, rng: &rng)
        XCTAssertNotEqual(state.phase, .betting)
        XCTAssertEqual(state.order, ["a"])
        XCTAssertEqual(refusal { try Rules.apply(.bet(round: 1, amount: 10), by: "b", to: &state, now: 103, rng: &rng) },
                       "You have left this table.")
    }

    func testAPlayerWhoLeavesOnTheirTurnStands() throws {
        var (state, rng) = started()
        stack(&state, [card(10), card(9), card(7), card(5), card(6), card(10, .hearts)])
        try betAll(&state, &rng, ["a": 10, "b": 10])
        Rules.playerLeft("a", state: &state, now: 103, rng: &rng)
        XCTAssertEqual(Rules.view(of: state, for: "b").turnPlayer, "b")
        XCTAssertTrue(state.hands["a"]?[0].done ?? false)
        Rules.playerLeft("b", state: &state, now: 104, rng: &rng)
        XCTAssertEqual(state.phase, .dealer)
        runDealer(&state, &rng, from: 105)
        XCTAssertEqual(state.phase, .settled)
        Rules.tick(&state, now: state.nextRoundAt, rng: &rng)
        XCTAssertTrue(Rules.isOver(state), "nobody left to bet")
        XCTAssertEqual(Rules.standings(state).count, 2)
        XCTAssertTrue(Rules.standings(state).allSatisfy { $0.detail?.contains("left") ?? false })
    }

    // MARK: - The end

    func testEightRoundsEndTheMatch() {
        var (state, rng) = started(now: 0)
        var now = 0.0
        while !Rules.isOver(state) && now < 10_000 {
            now += 1
            Rules.tick(&state, now: now, rng: &rng)
        }
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(state.round, Rules.maxRounds)
        XCTAssertEqual(Rules.champions(state), ["a", "b"], "nobody bet, so a tie at 100")
        XCTAssertEqual(Rules.standings(state).map(\.rank), [1, 1])
    }

    func testEveryoneBrokeEndsTheMatch() throws {
        var (state, rng) = started()
        state.chips = ["a": 5, "b": 5]
        // Both 10 + 6 stand; dealer 10 + 8.
        stack(&state, [card(10), card(10, .hearts), card(10, .spades), card(6), card(6, .hearts), card(8)])
        try betAll(&state, &rng, ["a": 5, "b": 5])
        try act(&state, &rng, "a") { .stand(move: $0) }
        try act(&state, &rng, "b") { .stand(move: $0) }
        runDealer(&state, &rng)
        XCTAssertEqual(state.chips, ["a": 0, "b": 0])
        XCTAssertTrue(Rules.view(of: state, for: "a").seats.allSatisfy(\.broke))
        Rules.tick(&state, now: state.nextRoundAt, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(state.round, 1)
    }

    func testStandingsRankByChips() {
        var (state, _) = started(players: [
            OfflinePlayer(id: "a", name: "Ann"), OfflinePlayer(id: "b", name: "Ben"), OfflinePlayer(id: "c", name: "Cat"),
        ])
        state.phase = .over
        state.chips = ["a": 80, "b": 140, "c": 80]
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["b", "a", "c"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 2])
        XCTAssertEqual(table.first?.detail, "+40 chips")
        XCTAssertEqual(table.last?.detail, "-20 chips")
        XCTAssertEqual(Rules.champions(state), ["b"])
    }

    func testALeaverRanksBelowEveryoneStillPlaying() {
        var (state, rng) = started(players: [
            OfflinePlayer(id: "a", name: "Ann"), OfflinePlayer(id: "b", name: "Ben"), OfflinePlayer(id: "c", name: "Cat"),
        ])
        state.chips = ["a": 80, "b": 140, "c": 60]
        Rules.playerLeft("b", state: &state, now: 101, rng: &rng)
        state.phase = .over
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "c", "b"], "walking out with the most chips does not bank the win")
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(table.last?.detail, "+40 chips · left")
        XCTAssertEqual(Rules.champions(state), ["a"])
    }

    func testNoViewEverCarriesTheHoleCardOrTheShoe() throws {
        let three = [
            OfflinePlayer(id: "a", name: "Ann"), OfflinePlayer(id: "b", name: "Ben"), OfflinePlayer(id: "c", name: "Cat"),
        ]
        var checked = 0
        for seed in UInt64(1)...40 {
            var (state, rng) = started(seed: seed, players: three)
            for player in three {
                try Rules.apply(.bet(round: 1, amount: 10), by: player.id, to: &state, now: 101, rng: &rng)
            }
            guard state.phase == .playing, state.dealer.count == 2 else { continue }
            let hole = state.dealer[1]
            let upcoming = state.shoe.suffix(3)
            for viewer in three.map({ Optional($0.id) }) + [nil] {
                let view = Rules.view(of: state, for: viewer)
                let visible = view.seats.flatMap { $0.hands.flatMap(\.cards) } + view.dealerCards
                let json = String(decoding: try OfflineCoding.encode(view), as: UTF8.self)
                for secret in [hole] + upcoming where !visible.contains(secret) {
                    let encoded = String(decoding: try OfflineCoding.encode(secret), as: UTF8.self)
                    XCTAssertFalse(json.contains(encoded), "\(secret) leaked to \(viewer ?? "a spectator") (seed \(seed))")
                }
                XCTAssertEqual(view.dealerHidden, 1)
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 30)
    }

    func testStandingsMidRoundCountChipsOnTheTable() throws {
        var (state, rng) = started()
        stack(&state, [card(10), card(9), card(7), card(5), card(6), card(10, .hearts)])
        try betAll(&state, &rng, ["a": 25, "b": 10])
        XCTAssertEqual(Rules.standings(state).map(\.score), [100, 100])
    }

    // MARK: - Whole matches

    /// Random legal play from many seeds always reaches the end, never
    /// refuses a move the view offered, and never mints or loses chips.
    func testRandomMatchesAlwaysFinish() throws {
        for seed in UInt64(1)...UInt64(60) {
            let count = Int(seed % 5) + 1
            let table = (1...count).map { OfflinePlayer(id: "p\($0)", name: "Player \($0)") }
            var rng = OfflineRNG(seed: seed)
            var choices = OfflineRNG(seed: seed &+ 1000)
            var state = Rules.start(players: table, now: 0, rng: &rng)
            var now = 0.0
            var steps = 0
            while !Rules.isOver(state) && steps < 20_000 {
                steps += 1
                now += 0.25
                if choices.chance(0.002), let leaver = choices.pick(table.map(\.id)) {
                    Rules.playerLeft(leaver, state: &state, now: now, rng: &rng)
                }
                for player in table where !state.away.contains(player.id) {
                    let view = Rules.view(of: state, for: player.id)
                    if view.myMaxBet > 0, choices.chance(0.5) {
                        let amount = choices.int(in: view.minBet...view.myMaxBet)
                        try Rules.apply(.bet(round: view.round, amount: amount), by: player.id, to: &state, now: now, rng: &rng)
                    } else if view.canHit, choices.chance(0.6) {
                        var options: [Rules.Action] = [.hit(move: view.move), .stand(move: view.move)]
                        if view.canDouble { options.append(.double(move: view.move)) }
                        if view.canSplit { options.append(.split(move: view.move)) }
                        try Rules.apply(choices.pick(options)!, by: player.id, to: &state, now: now, rng: &rng)
                    }
                }
                Rules.tick(&state, now: now, rng: &rng)
                for id in state.players.map(\.id) {
                    XCTAssertGreaterThanOrEqual(state.chips[id] ?? -1, 0, "seed \(seed)")
                }
            }
            XCTAssertTrue(Rules.isOver(state), "seed \(seed) did not finish")
            XCTAssertEqual(Rules.standings(state).count, count)
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("blackjack")
        try room.start(seed: 8, now: 0)
        _ = room.outbox()

        var now = 0.0
        while room.phase == .playing && now < 2_000 {
            now += 0.5
            room.tick(now: now)
            for id in ["a", "b"] {
                guard let data = room.currentView(for: id) else { continue }
                let view = try OfflineCoding.decode(Rules.PlayerView.self, from: data)
                if view.myMaxBet > 0 {
                    try room.act(OfflineCoding.encode(Rules.Action.bet(round: view.round, amount: view.minBet)), by: id, match: 1, now: now)
                } else if view.canStand {
                    // Ann hits to 15; Ben always stands.
                    let mine = view.seats.first { $0.id == id }?.hands[view.turnHand].total ?? 21
                    let action: Rules.Action = id == "a" && mine < 15 ? .hit(move: view.move) : .stand(move: view.move)
                    try room.act(OfflineCoding.encode(action), by: id, match: 1, now: now)
                }
            }
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.count, 2)
    }
}
