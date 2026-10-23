import XCTest
@testable import SRAppleApp

final class OfflineKnockoutWhistTests: XCTestCase {
    private typealias Rules = KnockoutWhistRules
    private let players = [OfflinePlayer(id: "a", name: "Ann"), OfflinePlayer(id: "b", name: "Ben"),
                           OfflinePlayer(id: "c", name: "Cat")]

    // MARK: - Setup

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
    }

    func testTheFirstHandDealsSevenAndTurnsUpTrumps() {
        for count in 2...5 {
            let table = (0..<count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            var rng = OfflineRNG(seed: UInt64(count))
            let state = Rules.start(players: table, now: 0, rng: &rng)
            XCTAssertEqual(state.hand, 1)
            XCTAssertEqual(state.handSize, 7)
            XCTAssertEqual(state.phase, .playing)
            XCTAssertEqual(state.turn, 1, "the player after the dealer leads")
            let trumpCard = try! XCTUnwrap(state.trumpCard)
            XCTAssertEqual(state.trump, trumpCard.suit)
            var seen = Set<String>()
            for player in table {
                let hand = state.hands[player.id] ?? []
                XCTAssertEqual(hand.count, 7)
                for card in hand { XCTAssertTrue(seen.insert(card.id).inserted, "\(card) dealt twice") }
            }
            XCTAssertFalse(seen.contains(trumpCard.id), "the turned-up card is not in anyone's hand")
        }
    }

    func testTheSameSeedDealsTheSameCards() {
        var one = OfflineRNG(seed: 42), two = OfflineRNG(seed: 42)
        XCTAssertEqual(Rules.start(players: players, now: 0, rng: &one), Rules.start(players: players, now: 0, rng: &two))
    }

    // MARK: - Tricks

    func testTrumpsBeatTheSuitLedAndOffSuitCardsNeverWin() {
        let trick = [Rules.Played(playerId: "a", card: OfflineCard(1, .hearts)),
                     Rules.Played(playerId: "b", card: OfflineCard(13, .clubs)),
                     Rules.Played(playerId: "c", card: OfflineCard(2, .spades))]
        XCTAssertEqual(Rules.winner(of: trick, trump: .spades), "c")
        XCTAssertEqual(Rules.winner(of: trick, trump: .diamonds), "a", "no trump: the highest of the suit led")
        XCTAssertEqual(Rules.winner(of: trick, trump: .hearts), "a")
        let twoTrumps = trick + [Rules.Played(playerId: "d", card: OfflineCard(5, .spades))]
        XCTAssertEqual(Rules.winner(of: twoTrumps, trump: .spades), "d")
        let acesHigh = [Rules.Played(playerId: "a", card: OfflineCard(13, .clubs)),
                        Rules.Played(playerId: "b", card: OfflineCard(1, .clubs))]
        XCTAssertEqual(Rules.winner(of: acesHigh, trump: nil), "b")
    }

    func testAScriptedHandKnocksOutTheBlankPlayer() throws {
        var state = twoCardHand()
        var rng = OfflineRNG(seed: 1)

        try Rules.apply(.play(turn: 10, card: OfflineCard(1, .hearts)), by: "a", to: &state, now: 1, rng: &rng)
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(Rules.view(of: state, for: "b").playable, ["KH"], "Ben holds a heart, so only it may go")
        try Rules.apply(.play(turn: 11, card: OfflineCard(13, .hearts)), by: "b", to: &state, now: 2, rng: &rng)
        // Cat has no hearts and trumps it.
        try Rules.apply(.play(turn: 12, card: OfflineCard(5, .spades)), by: "c", to: &state, now: 3, rng: &rng)
        XCTAssertEqual(state.phase, .trickWon)
        XCTAssertEqual(state.trickWinner, "c")
        XCTAssertEqual(state.tricks["c"], 1)

        // The trick stays on the table, then Cat leads.
        Rules.tick(&state, now: 3.5, rng: &rng)
        XCTAssertEqual(state.phase, .trickWon)
        Rules.tick(&state, now: 3 + Rules.trickPause, rng: &rng)
        XCTAssertEqual(state.phase, .playing)
        XCTAssertEqual(state.turn, 2)
        XCTAssertTrue(state.trick.isEmpty)

        let turn = state.turnNumber
        try Rules.apply(.play(turn: turn, card: OfflineCard(4, .clubs)), by: "c", to: &state, now: 6, rng: &rng)
        try Rules.apply(.play(turn: turn + 1, card: OfflineCard(2, .clubs)), by: "a", to: &state, now: 7, rng: &rng)
        try Rules.apply(.play(turn: turn + 2, card: OfflineCard(12, .clubs)), by: "b", to: &state, now: 8, rng: &rng)

        XCTAssertEqual(state.phase, .handOver)
        XCTAssertEqual(state.knockedOut, ["a"])
        XCTAssertEqual(state.outInHand["a"], 6)
        XCTAssertNil(state.champion)
        XCTAssertEqual(state.nextChooser, "c", "Ben and Cat tie on one trick; Cat got there first")

        // The next hand: one card each, Cat names trumps.
        Rules.tick(&state, now: 8 + Rules.resultPause, rng: &rng)
        XCTAssertEqual(state.hand, 7)
        XCTAssertEqual(state.handSize, 1)
        XCTAssertEqual(state.phase, .choosingTrump)
        XCTAssertEqual(state.chooser, "c")
        XCTAssertEqual(state.hands["a"], [])
        XCTAssertEqual(state.hands["b"]?.count, 1)
        XCTAssertEqual(state.hands["c"]?.count, 1)
        XCTAssertNil(state.trump)

        XCTAssertThrowsError(try Rules.apply(.chooseTrump(hand: 7, suit: .hearts), by: "b", to: &state, now: 14, rng: &rng)) {
            XCTAssertEqual(($0 as? OfflineRefusal)?.reason, "It's Cat's choice of trumps.")
        }
        XCTAssertThrowsError(try Rules.apply(.chooseTrump(hand: 7, suit: .hearts), by: "a", to: &state, now: 14, rng: &rng)) {
            XCTAssertEqual(($0 as? OfflineRefusal)?.reason, "You've been knocked out — watch the rest.")
        }
        XCTAssertThrowsError(try Rules.apply(.chooseTrump(hand: 6, suit: .hearts), by: "c", to: &state, now: 14, rng: &rng)) {
            XCTAssertEqual(($0 as? OfflineRefusal)?.reason, "That choice was for an earlier hand.")
        }
        let catsCard = try XCTUnwrap(state.hands["c"]?.first)
        XCTAssertThrowsError(try Rules.apply(.play(turn: state.turnNumber, card: catsCard), by: "c", to: &state, now: 14, rng: &rng)) {
            XCTAssertEqual(($0 as? OfflineRefusal)?.reason, "Wait for Cat to choose trumps.")
        }
        try Rules.apply(.chooseTrump(hand: 7, suit: .hearts), by: "c", to: &state, now: 14, rng: &rng)
        XCTAssertEqual(state.trump, .hearts)
        XCTAssertEqual(state.phase, .playing)
        XCTAssertEqual(state.turn, 2, "the chooser leads")

        // One trick decides it.
        try Rules.apply(.play(turn: state.turnNumber, card: catsCard), by: "c", to: &state, now: 15, rng: &rng)
        let bensCard = try XCTUnwrap(state.hands["b"]?.first)
        try Rules.apply(.play(turn: state.turnNumber, card: bensCard), by: "b", to: &state, now: 16, rng: &rng)
        XCTAssertEqual(state.phase, .handOver)
        let champion = try XCTUnwrap(state.champion)
        XCTAssertFalse(Rules.isOver(state), "the result shows first")
        Rules.tick(&state, now: 16 + Rules.resultPause, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))

        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId).first, champion)
        XCTAssertEqual(table.first?.rank, 1)
        XCTAssertEqual(table.first?.score, 2)
        XCTAssertEqual(table.last?.playerId, "a")
        XCTAssertEqual(table.last?.rank, 3)
        XCTAssertEqual(table.last?.detail, "out in hand 6 · 0 tricks")
        XCTAssertEqual(Set(table.map(\.playerId)), ["a", "b", "c"])
    }

    func testPlayersKnockedOutTogetherShareARank() throws {
        var state = twoCardHand()
        var rng = OfflineRNG(seed: 2)
        // Ann's ace leads, Ben follows, Cat trumps; then Cat leads and wins again.
        state.hands["b"] = [OfflineCard(13, .hearts), OfflineCard(3, .clubs)]
        try Rules.apply(.play(turn: 10, card: OfflineCard(1, .hearts)), by: "a", to: &state, now: 1, rng: &rng)
        try Rules.apply(.play(turn: 11, card: OfflineCard(13, .hearts)), by: "b", to: &state, now: 1, rng: &rng)
        try Rules.apply(.play(turn: 12, card: OfflineCard(5, .spades)), by: "c", to: &state, now: 1, rng: &rng)
        Rules.tick(&state, now: 5, rng: &rng)
        let turn = state.turnNumber
        try Rules.apply(.play(turn: turn, card: OfflineCard(4, .clubs)), by: "c", to: &state, now: 6, rng: &rng)
        try Rules.apply(.play(turn: turn + 1, card: OfflineCard(2, .clubs)), by: "a", to: &state, now: 6, rng: &rng)
        try Rules.apply(.play(turn: turn + 2, card: OfflineCard(3, .clubs)), by: "b", to: &state, now: 6, rng: &rng)
        XCTAssertEqual(state.knockedOut, ["a", "b"])
        XCTAssertEqual(state.champion, "c")
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.rank), [1, 2, 2])
        XCTAssertEqual(table.first?.detail, "last one standing · 2 tricks")
    }

    // MARK: - Refusals

    func testIllegalMovesAreRefused() throws {
        var state = twoCardHand()
        var rng = OfflineRNG(seed: 3)
        func refuses(_ action: Rules.Action, by id: String, _ reason: String, line: UInt = #line) {
            let before = state
            XCTAssertThrowsError(try Rules.apply(action, by: id, to: &state, now: 1, rng: &rng), line: line) {
                XCTAssertEqual(($0 as? OfflineRefusal)?.reason, reason, line: line)
            }
            state = before
        }
        refuses(.play(turn: 10, card: OfflineCard(13, .hearts)), by: "b", "It's Ann's turn.")
        refuses(.play(turn: 10, card: OfflineCard(1, .hearts)), by: "zed", "You are not in this game.")
        refuses(.play(turn: 9, card: OfflineCard(1, .hearts)), by: "a", "That move was for an earlier turn.")
        refuses(.play(turn: 10, card: OfflineCard(13, .hearts)), by: "a", "You don't have that card.")
        refuses(.chooseTrump(hand: 6, suit: .clubs), by: "a", "Trumps are already set for this hand.")

        try Rules.apply(.play(turn: 10, card: OfflineCard(1, .hearts)), by: "a", to: &state, now: 1, rng: &rng)
        refuses(.play(turn: 11, card: OfflineCard(12, .clubs)), by: "b", "You have hearts, so you must follow suit.")

        var gone = state
        Rules.playerLeft("a", state: &gone, now: 1, rng: &rng)
        XCTAssertThrowsError(try Rules.apply(.play(turn: gone.turnNumber, card: OfflineCard(2, .clubs)), by: "a", to: &gone, now: 1, rng: &rng)) {
            XCTAssertEqual(($0 as? OfflineRefusal)?.reason, "You have left this game.")
        }

        try Rules.apply(.play(turn: 11, card: OfflineCard(13, .hearts)), by: "b", to: &state, now: 1, rng: &rng)
        try Rules.apply(.play(turn: 12, card: OfflineCard(5, .spades)), by: "c", to: &state, now: 1, rng: &rng)
        refuses(.play(turn: state.turnNumber, card: OfflineCard(4, .clubs)), by: "c", "Wait a moment — the next trick is about to start.")
    }

    // MARK: - Redaction

    func testNobodySeesAnotherPlayersCards() throws {
        var rng = OfflineRNG(seed: 9)
        let state = Rules.start(players: players, now: 0, rng: &rng)
        for player in players {
            let view = Rules.view(of: state, for: player.id)
            XCTAssertEqual(view.myCards, OfflineCard.sortedForHand(state.hands[player.id] ?? []))
            XCTAssertEqual(view.seats.map(\.cards), [7, 7, 7])
            let bytes = String(decoding: try OfflineCoding.encode(view), as: UTF8.self)
            for other in players where other.id != player.id {
                for card in state.hands[other.id] ?? [] {
                    let encoded = String(decoding: try OfflineCoding.encode(card), as: UTF8.self)
                    XCTAssertFalse(bytes.contains(encoded), "\(player.name) can see \(other.name)'s \(card)")
                }
            }
        }
        let spectator = Rules.view(of: state, for: nil)
        XCTAssertTrue(spectator.myCards.isEmpty)
        XCTAssertTrue(spectator.playable.isEmpty)
        let bytes = String(decoding: try OfflineCoding.encode(spectator), as: UTF8.self)
        for player in players {
            for card in state.hands[player.id] ?? [] {
                XCTAssertFalse(bytes.contains(String(decoding: try OfflineCoding.encode(card), as: UTF8.self)))
            }
        }
        XCTAssertEqual(spectator.trumpCard, state.trumpCard, "the turned-up card is public")
    }

    func testOnlyThePlayerWhoseTurnItIsGetsPlayableCards() {
        var rng = OfflineRNG(seed: 4)
        let state = Rules.start(players: players, now: 0, rng: &rng)
        XCTAssertEqual(Rules.view(of: state, for: "b").playable.count, 7)
        XCTAssertTrue(Rules.view(of: state, for: "a").playable.isEmpty)
        XCTAssertEqual(Rules.view(of: state, for: "a").turnPlayer, "b")
    }

    // MARK: - Timers

    func testAnIdlePlayerHasTheLowestLegalCardPlayedForThem() throws {
        var state = twoCardHand()
        var rng = OfflineRNG(seed: 5)
        let before = state
        Rules.tick(&state, now: state.turnEndsAt - 0.1, rng: &rng)
        XCTAssertEqual(state, before)
        Rules.tick(&state, now: state.turnEndsAt + 0.3, rng: &rng)
        XCTAssertEqual(state.trick, [Rules.Played(playerId: "a", card: OfflineCard(2, .clubs))], "the two, not the ace")
        XCTAssertEqual(state.turn, 1)
        let again = state
        Rules.tick(&state, now: before.turnEndsAt + 0.3, rng: &rng)
        XCTAssertEqual(state, again, "a repeated tick changes nothing")
    }

    func testAnIdleChooserNamesTheirLongestSuit() {
        var state = Rules.State(players: players)
        state.hand = 3
        state.handSize = 3
        state.phase = .choosingTrump
        state.chooser = "b"
        state.turnEndsAt = 30
        state.hands = ["a": [OfflineCard(2, .clubs), OfflineCard(3, .clubs), OfflineCard(4, .clubs)],
                       "b": [OfflineCard(2, .hearts), OfflineCard(9, .diamonds), OfflineCard(3, .hearts)],
                       "c": [OfflineCard(5, .clubs), OfflineCard(6, .clubs), OfflineCard(7, .clubs)]]
        var rng = OfflineRNG(seed: 6)
        Rules.tick(&state, now: 29, rng: &rng)
        XCTAssertEqual(state.phase, .choosingTrump)
        Rules.tick(&state, now: 30, rng: &rng)
        XCTAssertEqual(state.trump, .hearts)
        XCTAssertEqual(state.phase, .playing)
        XCTAssertEqual(state.turn, 1)
    }

    // MARK: - Leaving

    func testAPlayerWhoLeavesOnTheirTurnIsSkippedAndKnockedOut() {
        var state = twoCardHand()
        var rng = OfflineRNG(seed: 7)
        Rules.playerLeft("a", state: &state, now: 2, rng: &rng)
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.outInHand["a"], 6)
        XCTAssertEqual(state.hands["a"], [])
        XCTAssertEqual(state.turnEndsAt, 2 + Rules.turnSeconds)
        XCTAssertFalse(Rules.isOver(state))

        Rules.playerLeft("b", state: &state, now: 3, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(state.champion, "c")
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["c", "b", "a"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(table[2].detail, "left in hand 6 · 0 tricks")
    }

    func testALeaverWhoCompletesTheTrickByGoingEndsIt() throws {
        var state = twoCardHand()
        var rng = OfflineRNG(seed: 8)
        try Rules.apply(.play(turn: 10, card: OfflineCard(1, .hearts)), by: "a", to: &state, now: 1, rng: &rng)
        try Rules.apply(.play(turn: 11, card: OfflineCard(13, .hearts)), by: "b", to: &state, now: 1, rng: &rng)
        Rules.playerLeft("c", state: &state, now: 2, rng: &rng)
        XCTAssertEqual(state.phase, .trickWon)
        XCTAssertEqual(state.trickWinner, "a")
    }

    func testAChooserWhoLeavesPassesTheChoiceOn() {
        var state = Rules.State(players: players)
        state.hand = 2
        state.handSize = 6
        state.phase = .choosingTrump
        state.chooser = "b"
        state.turnEndsAt = 30
        var rng = OfflineRNG(seed: 9)
        Rules.playerLeft("b", state: &state, now: 5, rng: &rng)
        XCTAssertEqual(state.chooser, "c")
        XCTAssertEqual(state.turnEndsAt, 5 + Rules.chooseSeconds)
    }

    func testTheChampionLeavingDuringTheResultChangesNothing() throws {
        var state = twoCardHand()
        state.phase = .handOver
        state.champion = "c"
        state.outInHand = ["a": 6, "b": 6]
        state.outEvent = ["a": 1, "b": 1]
        var rng = OfflineRNG(seed: 10)
        Rules.playerLeft("c", state: &state, now: 1, rng: &rng)
        XCTAssertEqual(state.champion, "c")
        XCTAssertEqual(Rules.standings(state).first?.playerId, "c")
    }

    // MARK: - Whole games

    func testRandomGamesAlwaysFinish() throws {
        for seed in 1...150 {
            let count = 2 + seed % 4
            let table = (0..<count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            var rng = OfflineRNG(seed: UInt64(seed))
            var choices = OfflineRNG(seed: UInt64(seed) &* 7919)
            var state = Rules.start(players: table, now: 0, rng: &rng)
            var now = 0.0
            var steps = 0
            var leftOne = false
            while !Rules.isOver(state) && steps < 5_000 {
                steps += 1
                now += 0.5
                if seed % 5 == 0, !leftOne, state.hand == 2 {
                    leftOne = true
                    Rules.playerLeft(table[1].id, state: &state, now: now, rng: &rng)
                    continue
                }
                switch state.phase {
                case .choosingTrump:
                    if choices.chance(0.8), let chooser = state.chooser {
                        let suit = choices.pick(OfflineSuit.allCases) ?? .clubs
                        try Rules.apply(.chooseTrump(hand: state.hand, suit: suit), by: chooser, to: &state, now: now, rng: &rng)
                    } else {
                        now += Rules.chooseSeconds
                    }
                case .playing:
                    let id = state.players[state.turn].id
                    let view = Rules.view(of: state, for: id)
                    XCTAssertFalse(view.playable.isEmpty, "seed \(seed): \(id) has nothing to play")
                    if choices.chance(0.9), let pick = choices.pick(view.myCards.filter { view.playable.contains($0.id) }) {
                        try Rules.apply(.play(turn: view.turnNumber, card: pick), by: id, to: &state, now: now, rng: &rng)
                    } else {
                        now += Rules.turnSeconds
                    }
                case .trickWon, .handOver, .over:
                    break
                }
                Rules.tick(&state, now: now, rng: &rng)
            }
            XCTAssertTrue(Rules.isOver(state), "seed \(seed) did not finish")
            XCTAssertLessThanOrEqual(state.hand, Rules.firstHandSize)
            let table2 = Rules.standings(state)
            XCTAssertEqual(table2.count, count)
            XCTAssertEqual(table2.filter { $0.rank == 1 }.count, 1, "seed \(seed): one winner")
            XCTAssertEqual(table2.first?.playerId, state.champion)
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.join(players[2], version: OfflineEnvelope.version)
        try room.choose("knockout-whist")
        try room.start(seed: 11, now: 0)
        _ = room.outbox()

        var now = 0.0
        while room.phase == .playing && now < 3_000 {
            now += 0.5
            room.tick(now: now)
            for player in players {
                guard let data = room.currentView(for: player.id) else { continue }
                let view = try OfflineCoding.decode(Rules.PlayerView.self, from: data)
                if view.phase == .choosingTrump, view.chooser == player.id {
                    try room.act(OfflineCoding.encode(Rules.Action.chooseTrump(hand: view.hand, suit: .spades)),
                                 by: player.id, match: 1, now: now)
                } else if view.phase == .playing, view.turnPlayer == player.id,
                          let card = view.myCards.first(where: { view.playable.contains($0.id) }) {
                    try room.act(OfflineCoding.encode(Rules.Action.play(turn: view.turnNumber, card: card)),
                                 by: player.id, match: 1, now: now)
                }
            }
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.count, 3)
        XCTAssertEqual(room.standings?.filter { $0.rank == 1 }.count, 1)
    }

    // MARK: - Helpers

    /// Hand 6 (two cards each), spades trumps, Ann to lead on turn 10:
    /// Ann A♥ 2♣ · Ben K♥ Q♣ · Cat 5♠ 4♣.
    private func twoCardHand() -> Rules.State {
        var state = Rules.State(players: players)
        state.hand = 6
        state.handSize = 2
        state.phase = .playing
        state.trump = .spades
        state.turn = 0
        state.leader = 0
        state.turnNumber = 10
        state.turnEndsAt = 40
        state.hands = ["a": [OfflineCard(1, .hearts), OfflineCard(2, .clubs)],
                       "b": [OfflineCard(13, .hearts), OfflineCard(12, .clubs)],
                       "c": [OfflineCard(5, .spades), OfflineCard(4, .clubs)]]
        state.tricks = ["a": 0, "b": 0, "c": 0]
        state.totalTricks = ["a": 0, "b": 0, "c": 0]
        return state
    }
}
