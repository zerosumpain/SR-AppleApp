import XCTest
@testable import SRAppleApp

/// Offline Fireworks: the deck and the deal, plays, misfires, drops and
/// hints with their refusals, the last lap, the endings, leaving, what each
/// phone may see, and the computer partner — that it plays only what it can
/// know, hints playable cards, drops sensibly, never peeks, and that a table
/// of partners plays a whole show through the room.
final class OfflineFireworksTests: XCTestCase {
    private typealias Rules = OfflineFireworksRules
    private typealias Card = OfflineFireworksRules.Card
    private let players = [OfflinePlayer(id: "a", name: "Ann"), OfflinePlayer(id: "b", name: "Ben"),
                           OfflinePlayer(id: "c", name: "Cat")]

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
    }

    func testSoloSeatsTwoPartners() {
        XCTAssertEqual(OfflinePlayModes.soloBots(Rules.info, hasBot: true), 2)
    }

    func testTheDeckAndTheDeal() {
        var rng = OfflineRNG(seed: 4)
        let state = Rules.start(players: players, now: 0, rng: &rng)
        let all = state.deck + state.hands.values.flatMap { $0.map(\.card) }
        XCTAssertEqual(all.count, 50)
        XCTAssertEqual(Set(all.map(\.id)), Set(1...50))
        for colour in Rules.colours {
            XCTAssertEqual(all.filter { $0.colour == colour }.map(\.rank).sorted(), [1, 1, 1, 2, 2, 3, 3, 4, 4, 5])
        }
        for player in players { XCTAssertEqual(state.hands[player.id]?.count, 5) }
        XCTAssertEqual(state.deck.count, 35)
        XCTAssertEqual(state.hints, 8)
        XCTAssertEqual(Rules.handSize(players: 4), 4)
    }

    /// A table with hands we choose (oldest first) and a small deck (top last).
    private func table(_ hands: [String: [Card]], deck: [Card] = [], stacks: [Int] = [0, 0, 0, 0, 0],
                       hints: Int = 8, players count: Int = 3) -> (Rules.State, OfflineRNG) {
        var rng = OfflineRNG(seed: 1)
        let seats = Array(players.prefix(count))
        var state = Rules.start(players: seats, now: 0, rng: &rng)
        for player in seats { state.hands[player.id] = (hands[player.id] ?? []).map { Rules.Held(card: $0) } }
        state.deck = deck
        state.stacks = stacks
        state.hints = hints
        state.turn = 0
        return (state, rng)
    }

    private var n = 100
    private func card(_ colour: String, _ rank: Int) -> Card {
        n += 1
        return Card(id: n, colour: colour, rank: rank)
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

    func testPlaysMisfiresAndDrops() throws {
        let red1 = card("red", 1)
        let blue3 = card("blue", 3)
        let next = card("green", 2)
        var (state, rng) = table(["a": [red1, blue3, card("white", 4)], "b": [card("red", 2)], "c": [card("yellow", 1)]],
                                 deck: [card("white", 1), next], hints: 7)
        try Rules.apply(.play(turn: state.turnNumber, card: red1.id), by: "a", to: &state, now: 1, rng: &rng)
        XCTAssertEqual(state.stacks, [1, 0, 0, 0, 0])
        XCTAssertEqual(state.hands["a"]?.last?.card, next, "drew the top card")
        XCTAssertEqual(state.turn, 1)
        // Ben's red 2 lands; Cat drops her yellow 1 for a token.
        try Rules.apply(.play(turn: state.turnNumber, card: state.hands["b"]![0].card.id), by: "b", to: &state, now: 2, rng: &rng)
        XCTAssertEqual(state.stacks[0], 2)
        try Rules.apply(.discard(turn: state.turnNumber, card: state.hands["c"]![0].card.id), by: "c", to: &state, now: 3, rng: &rng)
        XCTAssertEqual(state.hints, 8)
        XCTAssertEqual(state.discards.count, 1)
        // Ann's blue 3 is not next: a misfire, and it goes on the discards.
        try Rules.apply(.play(turn: state.turnNumber, card: blue3.id), by: "a", to: &state, now: 4, rng: &rng)
        XCTAssertEqual(state.misfires, 1)
        XCTAssertEqual(state.discards.last, blue3)
        XCTAssertEqual(state.log.last?.ok, false)
        XCTAssertEqual(Rules.logLine(state.log.last!, name: { $0 == "a" ? "Ann" : $0 }), "Ann played the Blue 3 — a misfire.")
    }

    func testRefusals() {
        let (state, _) = table(["a": [card("red", 1)], "b": [card("red", 2)], "c": [card("blue", 1)]], hints: 8)
        let turn = state.turnNumber
        let red = state.hands["a"]![0].card.id
        XCTAssertEqual(refusal(.play(turn: turn, card: red), by: "b", state), "It's Ann's turn.")
        XCTAssertEqual(refusal(.play(turn: turn, card: 999), by: "a", state), "That card is not in your hand.")
        XCTAssertEqual(refusal(.discard(turn: turn, card: red), by: "a", state),
                       "All 8 hint tokens are in — give a hint or play a card.")
        XCTAssertEqual(refusal(.hintColour(turn: turn, to: "a", colour: "red"), by: "a", state),
                       "Pick another player at the table to hint.")
        XCTAssertEqual(refusal(.hintColour(turn: turn, to: "b", colour: "blue"), by: "a", state),
                       "Ben has no card that hint points at.")
        XCTAssertEqual(refusal(.hintRank(turn: turn, to: "b", rank: 7), by: "a", state), "Hint a number from 1 to 5.")
        XCTAssertEqual(refusal(.play(turn: turn + 1, card: red), by: "a", state), "That was for an earlier turn.")
        var empty = state
        empty.hints = 0
        XCTAssertEqual(refusal(.hintRank(turn: turn, to: "b", rank: 2), by: "a", empty), "No hint tokens left — play or drop a card.")
    }

    func testHintsTellEveryMatchingCardAndWhatTheOthersAreNot() throws {
        let r2 = card("red", 2)
        let b2 = card("blue", 2)
        let g4 = card("green", 4)
        var (state, rng) = table(["a": [card("red", 1)], "b": [r2, b2, g4], "c": [card("white", 1)]])
        try Rules.apply(.hintRank(turn: state.turnNumber, to: "b", rank: 2), by: "a", to: &state, now: 1, rng: &rng)
        XCTAssertEqual(state.hints, 7)
        let ben = state.hands["b"]!
        XCTAssertEqual(ben.map(\.knows.rank), [2, 2, nil])
        XCTAssertEqual(ben[2].knows.notRanks, [2])
        XCTAssertEqual(state.log.last?.cards, [r2.id, b2.id])
        // Ben sees what he knows, not what he holds.
        let seen = Rules.view(of: state, for: "b").seats[1].hand
        XCTAssertEqual(seen.map(\.colour), [nil, nil, nil])
        XCTAssertEqual(seen.map(\.ranks), [[2], [2], [1, 3, 4, 5]])
        // Ann sees Ben's cards face up.
        XCTAssertEqual(Rules.view(of: state, for: "a").seats[1].hand.map(\.colour), ["red", "blue", "green"])
    }

    func testNobodySeesTheirOwnCardsAndASpectatorSeesNoHands() throws {
        var rng = OfflineRNG(seed: 9)
        let state = Rules.start(players: players, now: 0, rng: &rng)
        for player in players {
            let view = Rules.view(of: state, for: player.id)
            let own = try XCTUnwrap(view.seats.first { $0.id == player.id })
            XCTAssertTrue(own.hand.allSatisfy { $0.colour == nil && $0.rank == nil })
            XCTAssertTrue(view.seats.filter { $0.id != player.id }.allSatisfy { $0.hand.allSatisfy { $0.colour != nil } })
        }
        XCTAssertTrue(Rules.view(of: state, for: nil).seats.allSatisfy { $0.hand.isEmpty })
        let encoded = String(decoding: try OfflineCoding.encode(Rules.view(of: state, for: "a")), as: UTF8.self)
        for held in state.hands["a"]! {
            XCTAssertFalse(encoded.contains("\"id\":\(held.card.id),\"rank\""), "Ann's card \(held.card.id) face is not sent to her")
        }
    }

    func testTheLastLapAndTheDeckEnding() throws {
        let last = card("white", 3)
        var (state, rng) = table(["a": [card("blue", 4)], "b": [card("blue", 5)], "c": [card("yellow", 5)]],
                                 deck: [last], hints: 5)
        // Ann drops and draws the last card: everyone, Ann too, has one more turn.
        try Rules.apply(.discard(turn: state.turnNumber, card: state.hands["a"]![0].card.id), by: "a", to: &state, now: 1, rng: &rng)
        XCTAssertEqual(state.finalTurns, ["a", "b", "c"])
        XCTAssertEqual(Rules.view(of: state, for: "a").finalTurns, 3)
        try Rules.apply(.hintRank(turn: state.turnNumber, to: "c", rank: 5), by: "b", to: &state, now: 2, rng: &rng)
        try Rules.apply(.hintRank(turn: state.turnNumber, to: "a", rank: 3), by: "c", to: &state, now: 3, rng: &rng)
        XCTAssertEqual(state.phase, .playing)
        try Rules.apply(.hintRank(turn: state.turnNumber, to: "b", rank: 5), by: "a", to: &state, now: 4, rng: &rng)
        XCTAssertEqual(state.phase, .done)
        XCTAssertEqual(state.ending, .deck)
        Rules.tick(&state, now: 4 + Rules.resultPause, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
    }

    func testThreeMisfiresEndTheShowAndEveryoneSharesTheScore() throws {
        var (state, rng) = table(["a": [card("red", 3)], "b": [card("red", 4)], "c": [card("red", 5)]],
                                 stacks: [0, 2, 0, 0, 0])
        for id in ["a", "b", "c"] {
            try Rules.apply(.play(turn: state.turnNumber, card: state.hands[id]![0].card.id), by: id, to: &state, now: 1, rng: &rng)
        }
        XCTAssertEqual(state.ending, .misfires)
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.rank), [1, 1, 1])
        XCTAssertEqual(table.map(\.score), [2, 2, 2])
        XCTAssertEqual(table.first?.detail, "team score 2 of 25 · 3 misfires")
    }

    func testAFiveWinsATokenAndAPerfectShowEnds() throws {
        var (state, rng) = table(["a": [card("white", 5)], "b": [card("red", 1)], "c": [card("red", 1)]],
                                 stacks: [5, 5, 5, 5, 4], hints: 3)
        try Rules.apply(.play(turn: state.turnNumber, card: state.hands["a"]![0].card.id), by: "a", to: &state, now: 1, rng: &rng)
        XCTAssertEqual(state.hints, 4)
        XCTAssertEqual(state.ending, .perfect)
        XCTAssertEqual(Rules.score(state), 25)
    }

    func testTheClockDropsTheOldestUntouchedCard() throws {
        let touched = card("red", 1)
        let oldestUntouched = card("blue", 2)
        var (state, rng) = table(["a": [touched, oldestUntouched, card("green", 3)], "b": [card("red", 2)], "c": [card("white", 1)]],
                                 hints: 8)
        state.hands["a"]![0].knows.rank = 1
        Rules.tick(&state, now: Rules.turnSeconds, rng: &rng)
        XCTAssertEqual(state.discards.last, oldestUntouched)
        XCTAssertEqual(state.hints, 8, "every token was in: dropped for nothing")
        XCTAssertEqual(state.log.last?.auto, true)
        XCTAssertEqual(state.turn, 1)
    }

    func testLeavingPutsYourCardsOnTheDiscards() {
        var (state, rng) = table(["a": [card("red", 1)], "b": [card("red", 2), card("blue", 2)], "c": [card("white", 1)]])
        state.turn = 1
        Rules.playerLeft("b", state: &state, now: 5, rng: &rng)
        XCTAssertEqual(state.discards.count, 2)
        XCTAssertEqual(state.turn, 2, "Ben's turn passes on")
        Rules.playerLeft("c", state: &state, now: 6, rng: &rng)
        XCTAssertEqual(state.ending, .left, "one player cannot be given a hint")
        XCTAssertTrue(Rules.standings(state).first { $0.playerId == "b" }?.detail?.contains("left early") ?? false)
    }

    // MARK: - The computer partner

    func testThePartnerPlaysWhatItKnowsWillLand() throws {
        var (state, _) = table(["a": [card("red", 1)], "b": [card("blue", 3), card("yellow", 1)], "c": [card("white", 1)]])
        state.turn = 1
        // Ben has been told his second card is a 1: every 1 is playable now.
        state.hands["b"]![1].knows.rank = 1
        var rng = OfflineRNG(seed: 1)
        let plan = Rules.botActions(state, for: "b", rng: &rng)
        XCTAssertEqual(plan.first, .play(turn: state.turnNumber, card: state.hands["b"]![1].card.id))
        XCTAssertTrue(Rules.botActions(state, for: "a", rng: &rng).isEmpty, "not Ann's turn")
    }

    func testThePartnerHintsAPlayableCardOutright() {
        let red1 = card("red", 1)
        let (state, _) = table(["a": [card("blue", 4)], "b": [card("green", 3), red1, card("blue", 2)], "c": [card("white", 3)]],
                               hints: 4)
        var rng = OfflineRNG(seed: 1)
        // Ann (a bot here) knows nothing playable of her own; Ben's red 1 is
        // playable, and "1" tells him so outright.
        let plan = Rules.botActions(state, for: "a", rng: &rng)
        XCTAssertEqual(plan.first, .hintRank(turn: state.turnNumber, to: "b", rank: 1))
    }

    func testThePartnerSavesAFiveAboutToBeDropped() {
        // Nothing of Ben's is playable, and his oldest unhinted card is the
        // only blue 5: "5" keeps him from dropping it.
        let (state, _) = table(["a": [card("white", 4)], "b": [card("blue", 5), card("green", 3)], "c": [card("white", 3)]],
                               hints: 4)
        var rng = OfflineRNG(seed: 1)
        XCTAssertEqual(Rules.botActions(state, for: "a", rng: &rng).first, .hintRank(turn: state.turnNumber, to: "b", rank: 5))
    }

    func testThePartnerDropsItsOldestUntouchedCardAndNeverPeeks() throws {
        // No tokens: it must play or drop. It knows nothing, so it drops its
        // oldest card no hint has touched — whatever that card really is.
        let (state, _) = table(["a": [card("red", 1)], "b": [card("red", 5), card("blue", 1), card("green", 2)], "c": [card("white", 3)]],
                               hints: 0)
        var copy = state
        copy.turn = 1
        copy.hands["b"]![0].knows.rank = 5
        var rng = OfflineRNG(seed: 1)
        let plan = Rules.botActions(copy, for: "b", rng: &rng)
        XCTAssertEqual(plan.first, .discard(turn: copy.turnNumber, card: copy.hands["b"]![1].card.id))
        // The same plan whatever its hidden cards are: it decides from its view alone.
        var swapped = copy
        swapped.hands["b"]![1] = Rules.Held(card: Card(id: copy.hands["b"]![1].card.id, colour: "white", rank: 4))
        XCTAssertEqual(Rules.botActions(swapped, for: "b", rng: &rng).first, plan.first)
    }

    func testAShowOfPartnersPlaysThroughTheRoom() throws {
        var scores: [Int] = []
        for seed in [UInt64(1), 2, 3] {
            var room = OfflineRoom(host: OfflinePlayer(id: "h", name: "Hana"), roomName: "Solo",
                                   games: [OfflineGameEntry(withBot: Rules.self)])
            try room.choose("fireworks")
            for _ in 0..<2 { _ = try room.addBot() }
            try room.start(seed: seed, now: 1_000)
            // The host never moves (the clock drops a card for them); the
            // partners play the show to its end.
            var now = 1_000.0
            while room.phase == .playing && now < 20_000 {
                now += 0.5
                room.tick(now: now)
            }
            XCTAssertEqual(room.phase, .finished, "seed \(seed)")
            let table = try XCTUnwrap(room.standings)
            XCTAssertEqual(table.count, 3)
            scores.append(table[0].score)
        }
        // Partners who only play what they know never misfire: some show goes up.
        XCTAssertGreaterThan(scores.max() ?? 0, 5, "\(scores)")
    }
}
