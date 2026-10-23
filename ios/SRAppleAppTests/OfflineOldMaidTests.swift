import XCTest
@testable import SRAppleApp

/// Old Maid's rules: the deal and its pairs, blind draws in turn, who is safe,
/// the odd queen at the end, the turn timer, a phone leaving, and what each
/// phone is allowed to see of the others' hands.
final class OfflineOldMaidTests: XCTestCase {
    private typealias Rules = OldMaidRules

    private let players = [
        OfflinePlayer(id: "a", name: "Ann"),
        OfflinePlayer(id: "b", name: "Ben"),
        OfflinePlayer(id: "c", name: "Cat"),
    ]

    private func started(seed: UInt64 = 1, now: Double = 100, count: Int = 3) -> (Rules.State, OfflineRNG) {
        var rng = OfflineRNG(seed: seed)
        let list = (0..<count).map { i in i < players.count ? players[i] : OfflinePlayer(id: "p\(i)", name: "Player \(i)") }
        let state = Rules.start(players: list, now: now, rng: &rng)
        return (state, rng)
    }

    /// A table set by hand: Ann to draw from Ben.
    private func table(_ hands: [String: [OfflineCard]], turn: String = "a", now: Double = 100) -> Rules.State {
        var state = Rules.State(players: players)
        state.hands = hands
        for player in players where (hands[player.id] ?? []).isEmpty { state.safe.append(player.id) }
        state.turn = turn
        state.turnEndsAt = now + Rules.turnSeconds
        return state
    }

    private func refusal(_ body: () throws -> Void) -> String? {
        do { try body() } catch { return (error as? OfflineRefusal)?.reason ?? "\(error)" }
        return nil
    }

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(Rules.info.id, "old-maid")
        XCTAssertEqual(Rules.info.category, .card)
        XCTAssertEqual(Rules.info.minPlayers, 2)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    // MARK: - The deal

    func testTheDealUsesFiftyOneCardsAndPutsDownEveryPair() {
        for count in 2...5 {
            for seed in UInt64(1)...20 {
                let (state, _) = started(seed: seed, count: count)
                let held = state.hands.values.flatMap { $0 }
                XCTAssertEqual(held.count + state.discarded, 51)
                XCTAssertFalse(held.contains(Rules.removedQueen), "the queen of clubs is out")
                XCTAssertEqual(held.filter { $0.rank == 12 }.count % 2, 1, "one queen can never pair")
                for (_, hand) in state.hands {
                    XCTAssertEqual(Set(hand.map(\.rank)).count, hand.count, "no pair is left in a hand")
                }
                XCTAssertEqual(state.pairs.values.reduce(0, +) * 2, state.discarded)
                XCTAssertEqual(state.phase, .playing)
                XCTAssertEqual(state.turnNumber, 1)
                XCTAssertEqual(state.turnEndsAt, 100 + Rules.turnSeconds)
                XCTAssertNotNil(state.turn)
                XCTAssertFalse(state.hands[state.turn ?? ""]?.isEmpty ?? true)
            }
        }
    }

    func testTheSeedDecidesTheDeal() {
        XCTAssertEqual(started(seed: 4).0, started(seed: 4).0)
        XCTAssertNotEqual(started(seed: 4).0.hands, started(seed: 5).0.hands)
    }

    func testDiscardPairsKeepsOnlyUnmatchedCards() {
        let cards = [OfflineCard(3, .hearts), OfflineCard(5, .clubs), OfflineCard(3, .spades),
                     OfflineCard(3, .clubs), OfflineCard(5, .hearts), OfflineCard(9, .clubs)]
        let (kept, pairs) = Rules.discardPairs(cards)
        XCTAssertEqual(pairs, 2)
        XCTAssertEqual(kept, [OfflineCard(3, .clubs), OfflineCard(9, .clubs)])
    }

    // MARK: - Drawing

    func testADrawThatPairsGoesDownAndTheTurnPasses() throws {
        var state = table([
            "a": [OfflineCard(5, .hearts), OfflineCard(9, .clubs)],
            "b": [OfflineCard(5, .spades)],
            "c": [OfflineCard(9, .spades), OfflineCard(12, .hearts)],
        ])
        var rng = OfflineRNG(seed: 3)
        try Rules.apply(.draw(turn: 1, position: 0), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.hands["a"], [OfflineCard(9, .clubs)])
        XCTAssertEqual(state.hands["b"], [])
        XCTAssertEqual(state.safe, ["b"], "Ben gave up his last card")
        XCTAssertEqual(state.pairs["a"], 1)
        XCTAssertEqual(state.discarded, 2)
        XCTAssertEqual(state.lastDraw?.pair, [OfflineCard(5, .hearts), OfflineCard(5, .spades)])
        XCTAssertEqual(state.turn, "c", "Ben is safe, so Cat draws next")
        XCTAssertEqual(state.turnNumber, 2)
        XCTAssertEqual(state.turnEndsAt, 110 + Rules.turnSeconds)
        XCTAssertEqual(Rules.target(state), "a", "Cat draws from the next one round who has cards")
    }

    func testADrawThatDoesNotPairIsKept() throws {
        var state = table([
            "a": [OfflineCard(5, .hearts)],
            "b": [OfflineCard(12, .spades), OfflineCard(7, .clubs)],
            "c": [OfflineCard(5, .spades), OfflineCard(7, .hearts)],
        ])
        var rng = OfflineRNG(seed: 3)
        try Rules.apply(.draw(turn: 1, position: 0), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.hands["a"]?.count, 2)
        XCTAssertTrue(state.hands["a"]?.contains(OfflineCard(12, .spades)) ?? false)
        XCTAssertNil(state.lastDraw?.pair)
        XCTAssertEqual(state.turn, "b")
        XCTAssertEqual(Rules.target(state), "c")
    }

    func testIllegalDrawsAreRefused() throws {
        var state = table([
            "a": [OfflineCard(5, .hearts)],
            "b": [OfflineCard(5, .spades), OfflineCard(7, .clubs)],
            "c": [OfflineCard(7, .hearts), OfflineCard(12, .hearts)],
        ])
        var rng = OfflineRNG(seed: 3)
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: 1, position: 0), by: "b", to: &state, now: 101, rng: &rng) },
                       "It's Ann's turn.")
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: 1, position: 0), by: "zed", to: &state, now: 101, rng: &rng) },
                       "You are not in this game.")
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: 2, position: 0), by: "a", to: &state, now: 101, rng: &rng) },
                       "That pick was for an earlier turn.")
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: 1, position: 2), by: "a", to: &state, now: 101, rng: &rng) },
                       "That card isn't there.")
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: 1, position: -1), by: "a", to: &state, now: 101, rng: &rng) },
                       "That card isn't there.")
        try Rules.apply(.draw(turn: 1, position: 0), by: "a", to: &state, now: 101, rng: &rng)
        XCTAssertNotNil(refusal { try Rules.apply(.draw(turn: 1, position: 0), by: "b", to: &state, now: 102, rng: &rng) },
                        "a stale turn number is refused even on the right turn")
    }

    func testASafePlayerIsToldSo() {
        var state = table([
            "a": [OfflineCard(5, .hearts)],
            "b": [],
            "c": [OfflineCard(5, .spades), OfflineCard(12, .hearts)],
        ])
        var rng = OfflineRNG(seed: 3)
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: 1, position: 0), by: "b", to: &state, now: 101, rng: &rng) },
                       "You are safe — you have no cards left.")
    }

    func testHandsAreShuffledAfterADraw() throws {
        let many = [2, 3, 4, 6, 7, 8, 9, 10].map { OfflineCard($0, .hearts) }
        var moved = false
        for seed in UInt64(1)...10 {
            var state = table([
                "a": [OfflineCard(5, .hearts)] + many,
                "b": [OfflineCard(11, .spades)] + many.map { OfflineCard($0.rank, .spades) },
                "c": [OfflineCard(12, .hearts)],
            ])
            var rng = OfflineRNG(seed: seed)
            let before = state.hands["b"]!
            try Rules.apply(.draw(turn: 1, position: 0), by: "a", to: &state, now: 101, rng: &rng)
            var expected = before
            expected.removeFirst()
            if state.hands["b"]! != expected { moved = true }
            XCTAssertEqual(Set(state.hands["b"]!), Set(expected))
        }
        XCTAssertTrue(moved, "the fan drawn from gets shuffled")
    }

    // MARK: - The end

    func testTheLastHolderOfTheQueenIsTheOldMaid() throws {
        var state = table([
            "a": [OfflineCard(5, .hearts)],
            "b": [OfflineCard(5, .spades)],
            "c": [OfflineCard(12, .hearts)],
        ])
        var rng = OfflineRNG(seed: 3)
        try Rules.apply(.draw(turn: 1, position: 0), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.phase, .finale)
        XCTAssertEqual(state.loser, "c")
        XCTAssertNil(state.turn)
        XCTAssertEqual(state.safe, ["a", "b"])
        XCTAssertFalse(Rules.isOver(state), "the Old Maid is unmasked first")
        XCTAssertNotNil(refusal { try Rules.apply(.draw(turn: 2, position: 0), by: "c", to: &state, now: 111, rng: &rng) })

        Rules.tick(&state, now: state.finaleUntil - 0.1, rng: &rng)
        XCTAssertEqual(state.phase, .finale)
        Rules.tick(&state, now: state.finaleUntil, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))

        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "b", "c"])
        XCTAssertEqual(table.map(\.rank), [1, 1, 3])
        XCTAssertEqual(table.map(\.score), [0, 0, 1])
        XCTAssertEqual(table.last?.detail, "the Old Maid · 0 pairs")
        XCTAssertEqual(table.first?.detail, "safe · 1st out · 1 pair")

        let view = Rules.view(of: state, for: nil)
        XCTAssertEqual(view.loser, "c")
        XCTAssertEqual(view.oldMaidCard, OfflineCard(12, .hearts), "the queen is shown to all at the end")
    }

    // MARK: - Timer

    func testTheClockDrawsForASlowPlayer() {
        var state = table([
            "a": [OfflineCard(5, .hearts)],
            "b": [OfflineCard(5, .spades), OfflineCard(7, .clubs)],
            "c": [OfflineCard(7, .hearts), OfflineCard(12, .hearts)],
        ])
        var rng = OfflineRNG(seed: 9)
        Rules.tick(&state, now: state.turnEndsAt - 0.1, rng: &rng)
        XCTAssertEqual(state.turnNumber, 1)
        let deadline = state.turnEndsAt
        Rules.tick(&state, now: deadline + 0.3, rng: &rng)
        XCTAssertEqual(state.turnNumber, 2)
        XCTAssertEqual(state.lastDraw?.drawer, "a")
        XCTAssertEqual(state.lastDraw?.automatic, true)
        XCTAssertEqual(state.turnEndsAt, deadline + 0.3 + Rules.turnSeconds)
        let after = state
        Rules.tick(&state, now: deadline + 0.3, rng: &rng)
        XCTAssertEqual(state, after, "ticking again at the same instant changes nothing")
    }

    // MARK: - Leaving

    func testALeaverIsSkippedButStillDrawnFrom() throws {
        var state = table([
            "a": [OfflineCard(5, .hearts), OfflineCard(8, .hearts)],
            "b": [OfflineCard(5, .spades), OfflineCard(7, .clubs)],
            "c": [OfflineCard(7, .hearts), OfflineCard(8, .clubs), OfflineCard(12, .hearts)],
        ], turn: "b")
        var rng = OfflineRNG(seed: 2)
        Rules.playerLeft("b", state: &state, now: 120, rng: &rng)
        XCTAssertEqual(state.away, ["b"])
        XCTAssertEqual(state.turn, "c", "Ben's turn passes on")
        XCTAssertEqual(state.turnNumber, 2)
        XCTAssertEqual(state.turnEndsAt, 120 + Rules.turnSeconds)
        XCTAssertEqual(Rules.target(state), "a")
        XCTAssertEqual(refusal { try Rules.apply(.draw(turn: 2, position: 0), by: "b", to: &state, now: 121, rng: &rng) },
                       "You have left this game.")
        try Rules.apply(.draw(turn: 2, position: 0), by: "c", to: &state, now: 121, rng: &rng)
        XCTAssertEqual(state.turn, "a", "the turn goes round past Ben")
        XCTAssertEqual(Rules.target(state), "b", "but Ann may still draw from Ben's hand")
        Rules.playerLeft("b", state: &state, now: 122, rng: &rng)
        XCTAssertEqual(state.away, ["b"], "leaving twice is harmless")
        XCTAssertTrue(Rules.standings(state).first { $0.playerId == "b" }?.detail?.hasSuffix("left") ?? false)
    }

    func testTheGameEndsWhenNobodyHereCanDraw() {
        var state = table([
            "a": [],
            "b": [OfflineCard(5, .spades), OfflineCard(12, .hearts)],
            "c": [OfflineCard(5, .hearts)],
        ], turn: "c")
        var rng = OfflineRNG(seed: 2)
        Rules.playerLeft("b", state: &state, now: 129, rng: &rng)
        XCTAssertEqual(state.phase, .playing, "Cat can still draw from Ben's hand")
        Rules.playerLeft("c", state: &state, now: 130, rng: &rng)
        XCTAssertEqual(state.phase, .finale, "only away players still hold cards")
        XCTAssertEqual(state.loser, "b", "the queen's holder is the Old Maid")
        XCTAssertEqual(Rules.standings(state).count, 3)
    }

    // MARK: - Redaction

    func testNobodySeesAnotherHand() throws {
        var state = table([
            "a": [OfflineCard(5, .hearts), OfflineCard(9, .diamonds)],
            "b": [OfflineCard(12, .spades), OfflineCard(7, .clubs)],
            "c": [OfflineCard(7, .hearts), OfflineCard(9, .clubs), OfflineCard(5, .diamonds)],
        ])
        let ann = Rules.view(of: state, for: "a")
        XCTAssertEqual(ann.myHand, OfflineCard.sortedForHand(state.hands["a"]!))
        XCTAssertEqual(ann.seats.map(\.cards), [2, 2, 3])
        XCTAssertEqual(ann.target, "b")
        XCTAssertEqual(ann.targetCards, 2)
        let annData = try OfflineCoding.encode(ann)
        let annText = String(decoding: annData, as: UTF8.self)
        XCTAssertFalse(annText.contains("spades"), "Ann's view carries nothing of Ben's hand")
        XCTAssertNil(Rules.view(of: state, for: nil).myHand)
        XCTAssertNil(Rules.view(of: state, for: "zed").myHand)

        // Ann draws Ben's queen: only Ann and Ben learn which card moved.
        var rng = OfflineRNG(seed: 1)
        let queenAt = try XCTUnwrap(state.hands["b"]?.firstIndex(of: OfflineCard(12, .spades)))
        try Rules.apply(.draw(turn: 1, position: queenAt), by: "a", to: &state, now: 101, rng: &rng)
        XCTAssertEqual(Rules.view(of: state, for: "a").lastDraw?.card, OfflineCard(12, .spades))
        XCTAssertEqual(Rules.view(of: state, for: "b").lastDraw?.card, OfflineCard(12, .spades))
        XCTAssertNil(Rules.view(of: state, for: "c").lastDraw?.card)
        XCTAssertNil(Rules.view(of: state, for: nil).lastDraw?.card)
        XCTAssertNil(Rules.view(of: state, for: "c").oldMaidCard)
        for viewer in [nil, "c"] as [String?] {
            let text = String(decoding: try OfflineCoding.encode(Rules.view(of: state, for: viewer)), as: UTF8.self)
            XCTAssertFalse(text.contains("spades"), "the queen's whereabouts stay hidden from \(viewer ?? "a spectator")")
        }
        // A pair, once down, is public.
        try Rules.apply(.draw(turn: 2, position: 0), by: "b", to: &state, now: 102, rng: &rng)
        let pairNote = Rules.view(of: state, for: "a").lastDraw
        XCTAssertEqual(pairNote?.pair != nil, pairNote?.card != nil)
    }

    func testEveryViewHidesEveryOtherHand() throws {
        for count in 2...5 {
            var (state, rng) = started(seed: UInt64(70 + count), count: count)
            for step in 0..<8 where state.phase == .playing {
                guard let drawer = state.turn, let from = Rules.target(state) else { break }
                let size = state.hands[from]?.count ?? 0
                try Rules.apply(.draw(turn: state.turnNumber, position: step % max(1, size)), by: drawer,
                                to: &state, now: 101 + Double(step), rng: &rng)
            }
            for viewer in state.players.map({ Optional($0.id) }) + [nil] {
                let view = Rules.view(of: state, for: viewer)
                let json = String(decoding: try OfflineCoding.encode(view), as: UTF8.self)
                // The card that just moved is known to the two players it moved between.
                let known = state.lastDraw.flatMap { draw in
                    viewer == draw.drawer || viewer == draw.from || draw.pair != nil ? draw.card : nil
                }
                for other in state.players where other.id != viewer {
                    for card in state.hands[other.id] ?? [] where card != known && card != view.oldMaidCard {
                        let encoded = String(decoding: try OfflineCoding.encode(card), as: UTF8.self)
                        XCTAssertFalse(json.contains(encoded),
                                       "\(other.name)'s \(card) leaked to \(viewer ?? "a spectator") (\(count) players)")
                    }
                }
            }
        }
    }

    func testALeaverRanksBelowEveryoneStillPlaying() {
        var state = table([
            "a": [],
            "b": [],
            "c": [OfflineCard(12, .hearts)],
        ], turn: "c")
        state.away = ["b"]
        state.safe = ["b", "a"]
        state.loser = "c"
        state.phase = .over
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "c", "b"],
                       "going safe by walking out (and never drawing the queen) does not count")
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(table.last?.detail, "safe · 1st out · 0 pairs · left")
    }

    // MARK: - Whole games

    func testRandomPlayoutsAlwaysFindAnOldMaid() throws {
        for count in 2...5 {
            for seed in UInt64(1)...60 {
                var (state, rng) = started(seed: seed, count: count)
                var pick = OfflineRNG(seed: seed &* 31 &+ 7)
                var now = 100.0
                var steps = 0
                while state.phase == .playing && steps < 5_000 {
                    steps += 1
                    now += 1
                    if steps % 7 == 0 {
                        // Somebody dawdles: the clock picks for them.
                        Rules.tick(&state, now: state.turnEndsAt, rng: &rng)
                        continue
                    }
                    let drawer = try XCTUnwrap(state.turn)
                    let from = try XCTUnwrap(Rules.target(state))
                    let size = state.hands[from]?.count ?? 0
                    try Rules.apply(.draw(turn: state.turnNumber, position: pick.int(below: size)),
                                    by: drawer, to: &state, now: now, rng: &rng)
                    let held = state.hands.values.reduce(0) { $0 + $1.count }
                    XCTAssertEqual(held + state.discarded, 51)
                }
                XCTAssertEqual(state.phase, .finale, "\(count) players, seed \(seed)")
                let loser = try XCTUnwrap(state.loser)
                XCTAssertEqual(state.hands[loser]?.count, 1)
                XCTAssertEqual(state.hands[loser]?.first?.rank, 12)
                XCTAssertEqual(state.safe.count, count - 1)
                Rules.tick(&state, now: state.finaleUntil, rng: &rng)
                XCTAssertTrue(Rules.isOver(state))
                let table = Rules.standings(state)
                XCTAssertEqual(table.count, count)
                XCTAssertEqual(table.last?.playerId, loser)
                XCTAssertEqual(table.last?.rank, count)
            }
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.join(players[2], version: OfflineEnvelope.version)
        try room.choose("old-maid")
        try room.start(seed: 11, now: 0)
        _ = room.outbox()

        var now = 0.0
        var steps = 0
        while room.phase == .playing && steps < 3_000 {
            steps += 1
            now += 0.5
            room.tick(now: now)
            let view = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "a")))
            if view.phase == .playing, let turn = view.turn, view.targetCards > 0 {
                try room.act(OfflineCoding.encode(Rules.Action.draw(turn: view.turnNumber, position: steps % view.targetCards)),
                             by: turn, match: 1, now: now)
            }
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.count, 3)
        XCTAssertEqual(room.standings?.last?.score, 1, "the Old Maid is left with the queen")
    }
}
