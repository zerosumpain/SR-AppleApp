import XCTest
@testable import SRAppleApp

/// Colour Clash's rules: the deck, the card schedule, scoring a match and a
/// mismatch, late and bad taps, the end of the match, players leaving, and
/// what each phone is allowed to see.
final class OfflineColourClashTests: XCTestCase {
    private typealias Rules = ColourClashRules

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

    /// Tick to the moment card `index` shows.
    private func show(_ index: Int, _ state: inout Rules.State, _ rng: inout OfflineRNG) {
        Rules.tick(&state, now: Rules.showAt(index, state), rng: &rng)
    }

    /// A state running on card 0, with a deck chosen by the test.
    private func running(_ cards: [Rules.Card]) -> (Rules.State, OfflineRNG) {
        var (state, rng) = started()
        state.cards = cards
        show(0, &state, &rng)
        return (state, rng)
    }

    private func tap(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ id: String, card: Int, ms: Int, at now: Double? = nil) throws {
        let when = now ?? (Rules.showAt(card, state) + Double(ms) / 1000 + 0.05)
        try Rules.apply(.tap(card: card, ms: ms), by: id, to: &state, now: when, rng: &rng)
    }

    private func refusal(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch { return (error as? OfflineRefusal)?.reason ?? "\(error)" }
    }

    private let match = Rules.Card(word: .red, ink: .red)
    private let clash = Rules.Card(word: .red, ink: .blue)

    // MARK: - Setup

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(Rules.info.id, "colour-clash")
        XCTAssertEqual(Rules.info.category, .reaction)
        XCTAssertEqual(Rules.info.minPlayers, 2)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    func testTheDeckHasThirtyCardsTwelveOfThemMatches() {
        for seed in UInt64(1)...40 {
            let (state, _) = started(seed: seed)
            XCTAssertEqual(state.cards.count, Rules.cardCount)
            XCTAssertEqual(state.cards.filter(\.isMatch).count, Rules.matchCount)
            for index in 1..<state.cards.count {
                XCTAssertNotEqual(state.cards[index], state.cards[index - 1], "seed \(seed): a card must visibly change")
            }
        }
    }

    func testTheSeedDecidesTheDeck() {
        XCTAssertEqual(started(seed: 4).0.cards, started(seed: 4).0.cards)
        XCTAssertNotEqual(started(seed: 4).0.cards, started(seed: 5).0.cards)
    }

    func testAMatchOpensOnTheLeadIn() {
        let (state, _) = started(now: 100)
        XCTAssertEqual(state.phase, .ready)
        XCTAssertEqual(state.firstAt, 100 + Rules.leadIn)
        XCTAssertEqual(state.current, -1)
        XCTAssertEqual(state.points, ["a": 0, "b": 0, "c": 0])
        let view = Rules.view(of: state, for: "a")
        XCTAssertNil(view.card)
        XCTAssertEqual(view.index, -1)
        XCTAssertFalse(Rules.isOver(state))
    }

    // MARK: - The schedule

    func testCardsGoByAtTheirTimes() {
        var (state, rng) = started()
        Rules.tick(&state, now: state.firstAt - 0.01, rng: &rng)
        XCTAssertEqual(state.phase, .ready)
        Rules.tick(&state, now: state.firstAt, rng: &rng)
        XCTAssertEqual(state.phase, .running)
        XCTAssertEqual(state.current, 0)
        Rules.tick(&state, now: Rules.showAt(1, state) - 0.01, rng: &rng)
        XCTAssertEqual(state.current, 0)
        Rules.tick(&state, now: Rules.showAt(1, state), rng: &rng)
        XCTAssertEqual(state.current, 1)
        // A late tick catches up several cards at once.
        Rules.tick(&state, now: Rules.showAt(5, state) + 0.3, rng: &rng)
        XCTAssertEqual(state.current, 5)
        XCTAssertEqual(Rules.view(of: state, for: "a").card, state.cards[5])
        XCTAssertEqual(Rules.view(of: state, for: "a").shownAt, Rules.showAt(5, state))
    }

    func testACardNobodyTapsIsScoredAfterTheGrace() {
        var (state, rng) = running([clash, match, clash])
        Rules.tick(&state, now: Rules.closesAt(0, state) - 0.01, rng: &rng)
        XCTAssertEqual(state.scoredThrough, -1)
        Rules.tick(&state, now: Rules.closesAt(0, state), rng: &rng)
        XCTAssertEqual(state.scoredThrough, 0)
        XCTAssertEqual(state.last?.points, [:])
    }

    // MARK: - Scoring

    func testTheQuickestCorrectTapScoresTwoAndTheRestOne() throws {
        var (state, rng) = running([match, clash, match])
        try tap(&state, &rng, "a", card: 0, ms: 420)
        try tap(&state, &rng, "b", card: 0, ms: 310)
        XCTAssertEqual(state.scoredThrough, -1, "still waiting for Cat")
        try tap(&state, &rng, "c", card: 0, ms: 500)
        XCTAssertEqual(state.scoredThrough, 0, "everyone tapped, so it is scored at once")
        XCTAssertEqual(state.points, ["a": 1, "b": 2, "c": 1])
        XCTAssertEqual(state.last?.quickest, ["b"])
        XCTAssertEqual(state.best, ["a": 420, "b": 310, "c": 500])
        XCTAssertEqual(state.right, ["a": 1, "b": 1, "c": 1])
    }

    func testAnExactTieSharesTheBonus() throws {
        var (state, rng) = running([match, clash])
        try tap(&state, &rng, "a", card: 0, ms: 300)
        try tap(&state, &rng, "b", card: 0, ms: 300)
        Rules.tick(&state, now: Rules.closesAt(0, state), rng: &rng)
        XCTAssertEqual(state.points, ["a": 2, "b": 2, "c": 0])
        XCTAssertEqual(state.last?.quickest, ["a", "b"])
    }

    func testTappingAMismatchCostsAPoint() throws {
        var (state, rng) = running([clash, match])
        try tap(&state, &rng, "a", card: 0, ms: 350)
        Rules.tick(&state, now: Rules.closesAt(0, state), rng: &rng)
        XCTAssertEqual(state.points["a"], -1)
        XCTAssertEqual(state.points["b"], 0)
        XCTAssertEqual(state.wrong["a"], 1)
        XCTAssertEqual(state.last?.match, false)
        XCTAssertEqual(state.last?.points, ["a": -1])
    }

    func testAGuessTooQuickToBeAReactionScoresNothing() throws {
        var (state, rng) = running([match, clash])
        try tap(&state, &rng, "a", card: 0, ms: 40)
        try tap(&state, &rng, "b", card: 0, ms: 600)
        Rules.tick(&state, now: Rules.closesAt(0, state), rng: &rng)
        XCTAssertEqual(state.points["a"], 0)
        XCTAssertEqual(state.points["b"], 2, "the honest slow tap is the quickest real one")
        XCTAssertNil(state.best["a"])
    }

    func testALateTapStillCountsWithinTheGrace() throws {
        var (state, rng) = running([match, clash, clash])
        show(1, &state, &rng)
        XCTAssertEqual(state.current, 1)
        try tap(&state, &rng, "a", card: 0, ms: 1150, at: Rules.showAt(1, state) + 0.3)
        Rules.tick(&state, now: Rules.closesAt(0, state), rng: &rng)
        XCTAssertEqual(state.points["a"], 2)
    }

    // MARK: - Refusals

    func testBadTapsAreRefused() throws {
        var (state, rng) = started()
        XCTAssertEqual(refusal { try tap(&state, &rng, "a", card: 0, ms: 300, at: state.firstAt - 1) },
                       "Wait for the first card.")
        state.cards[0] = match
        show(0, &state, &rng)
        XCTAssertEqual(refusal { try tap(&state, &rng, "zed", card: 0, ms: 300) }, "You are not in this game.")
        XCTAssertEqual(refusal { try tap(&state, &rng, "a", card: 1, ms: 300, at: state.firstAt + 0.5) },
                       "That card isn't up yet.")
        XCTAssertEqual(refusal { try tap(&state, &rng, "a", card: -1, ms: 300) }, "There is no such card.")
        XCTAssertEqual(refusal { try tap(&state, &rng, "a", card: 99, ms: 300, at: state.firstAt + 0.5) },
                       "There is no such card.")
        XCTAssertEqual(refusal { try tap(&state, &rng, "a", card: 0, ms: -5) }, "That time cannot be right.")
        XCTAssertEqual(refusal { try tap(&state, &rng, "a", card: 0, ms: 60_000, at: state.firstAt + 0.5) },
                       "That time cannot be right.")
        try tap(&state, &rng, "a", card: 0, ms: 300)
        XCTAssertEqual(refusal { try tap(&state, &rng, "a", card: 0, ms: 280) }, "You already tapped that card.")
        Rules.tick(&state, now: Rules.closesAt(0, state), rng: &rng)
        XCTAssertEqual(refusal { try tap(&state, &rng, "b", card: 0, ms: 300, at: Rules.closesAt(0, state) + 0.1) },
                       "Too late for that card.")
        Rules.playerLeft("c", state: &state, now: Rules.closesAt(0, state), rng: &rng)
        XCTAssertEqual(refusal { try tap(&state, &rng, "c", card: 1, ms: 300) }, "You have left this game.")
    }

    // MARK: - The end

    /// Run a whole match: on every match card Ben is quickest and Ann slower;
    /// Cat taps every mismatch.
    private func playThrough(_ state: inout Rules.State, _ rng: inout OfflineRNG) throws {
        for index in 0..<state.cards.count {
            show(index, &state, &rng)
            if state.cards[index].isMatch {
                try tap(&state, &rng, "b", card: index, ms: 300)
                try tap(&state, &rng, "a", card: index, ms: 450)
            } else {
                try tap(&state, &rng, "c", card: index, ms: 350)
            }
        }
        Rules.tick(&state, now: Rules.closesAt(state.cards.count - 1, state), rng: &rng)
    }

    func testThirtyCardsEndTheMatchAndTheMostPointsWin() throws {
        var (state, rng) = started(seed: 9)
        try playThrough(&state, &rng)
        XCTAssertEqual(state.phase, .result)
        XCTAssertFalse(Rules.isOver(state), "the final table is shown first")
        XCTAssertEqual(state.points, ["a": 12, "b": 24, "c": -18])
        XCTAssertEqual(Rules.view(of: state, for: "a").champions, ["b"])
        XCTAssertNil(Rules.view(of: state, for: "a").card)
        Rules.tick(&state, now: state.resultUntil - 0.01, rng: &rng)
        XCTAssertFalse(Rules.isOver(state))
        Rules.tick(&state, now: state.resultUntil, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["b", "a", "c"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(table.first?.detail, "12 right · best 300 ms")
        XCTAssertEqual(table.last?.detail, "0 right · 18 wrong")
        XCTAssertThrowsError(try tap(&state, &rng, "a", card: 29, ms: 300, at: state.resultUntil + 1))
    }

    func testTiesShareARank() {
        var (state, _) = started()
        state.points = ["a": 3, "b": 3, "c": 1]
        XCTAssertEqual(Rules.standings(state).map(\.rank), [1, 1, 3])
        XCTAssertEqual(Rules.champions(state), ["a", "b"])
    }

    // MARK: - Leaving

    func testAPlayerWhoLeavesIsNotWaitedFor() throws {
        var (state, rng) = running([match, clash])
        try tap(&state, &rng, "a", card: 0, ms: 300)
        try tap(&state, &rng, "b", card: 0, ms: 350)
        XCTAssertEqual(state.scoredThrough, -1)
        Rules.playerLeft("c", state: &state, now: state.firstAt + 0.5, rng: &rng)
        XCTAssertEqual(state.scoredThrough, 0, "Cat was the only one still to tap")
        XCTAssertEqual(state.points["a"], 2)
        Rules.playerLeft("c", state: &state, now: state.firstAt + 0.6, rng: &rng)
        XCTAssertEqual(state.away, ["c"], "leaving twice changes nothing")
        XCTAssertEqual(Rules.standings(state).last?.detail, "0 right · left")
    }

    // MARK: - Redaction

    func testOthersTapsAndFutureCardsStayHidden() throws {
        var (state, rng) = running([match, clash, match])
        try tap(&state, &rng, "a", card: 0, ms: 280)
        let ben = Rules.view(of: state, for: "b")
        XCTAssertNil(ben.myMs, "Ben cannot see Ann's tap")
        XCTAssertNil(ben.last)
        XCTAssertEqual(ben.rows.map(\.points), [0, 0, 0])
        XCTAssertEqual(Rules.view(of: state, for: "a").myMs, 280, "Ann sees her own")
        let spectator = Rules.view(of: state, for: nil)
        XCTAssertNil(spectator.myMs)
        XCTAssertEqual(spectator.card, match)

        // Nothing in any view mentions the cards still to come or Ann's time.
        let data = try OfflineCoding.encode(ben)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("280"))
        XCTAssertFalse(text.contains("blue"), "card 1 (RED in blue) is not up yet")

        // Before the first card, no card at all.
        let (fresh, _) = started()
        let early = String(decoding: try OfflineCoding.encode(Rules.view(of: fresh, for: "a")), as: UTF8.self)
        for hue in Rules.Hue.allCases { XCTAssertFalse(early.contains("\"\(hue.rawValue)\"")) }
    }

    func testTheScoredCardIsShownToEveryone() throws {
        var (state, rng) = running([match, clash])
        for id in ["a", "b", "c"] { try tap(&state, &rng, id, card: 0, ms: id == "c" ? 250 : 400) }
        let view = Rules.view(of: state, for: nil)
        XCTAssertEqual(view.lastCard, match)
        XCTAssertEqual(view.rows.map(\.lastPoints), [1, 1, 2])
        XCTAssertEqual(view.rows.map(\.quickest), [false, false, true])
    }

    // MARK: - Whole matches

    func testRandomMatchesAlwaysFinish() throws {
        for seed in UInt64(1)...60 {
            for count in 2...5 {
                let roster = (0..<count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
                var rng = OfflineRNG(seed: seed)
                var chooser = OfflineRNG(seed: seed &* 7919 &+ 3)
                var state = Rules.start(players: roster, now: 0, rng: &rng)
                var now = 0.0
                var guard_ = 0
                while !Rules.isOver(state) && guard_ < 2_000 {
                    guard_ += 1
                    now += 0.1
                    Rules.tick(&state, now: now, rng: &rng)
                    let before = state
                    Rules.tick(&state, now: now, rng: &rng)
                    XCTAssertEqual(before, state, "tick is idempotent")
                    if state.phase == .running, state.current < state.cards.count {
                        for player in roster where chooser.chance(0.3) {
                            let card = state.current - chooser.int(in: 0...1)
                            let ms = chooser.int(in: 50...1500)
                            _ = try? Rules.apply(.tap(card: card, ms: ms), by: player.id, to: &state, now: now, rng: &rng)
                        }
                        if seed % 7 == 0, count > 2, state.current == 10 {
                            Rules.playerLeft(roster[count - 1].id, state: &state, now: now, rng: &rng)
                        }
                    }
                    for player in roster {
                        _ = Rules.view(of: state, for: player.id)
                    }
                }
                XCTAssertTrue(Rules.isOver(state), "seed \(seed), \(count) players")
                XCTAssertEqual(state.scoredThrough, Rules.cardCount - 1)
                XCTAssertEqual(Rules.standings(state).count, count)
                XCTAssertTrue(state.marks.isEmpty)
            }
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("colour-clash")
        try room.start(seed: 8, now: 0)
        _ = room.outbox()

        var now = 0.0
        var tapped: Set<Int> = []
        while room.phase == .playing && now < 120 {
            now += 0.1
            room.tick(now: now)
            let due = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "b")))
            if let card = due.card, card.isMatch, !tapped.contains(due.index) {
                tapped.insert(due.index)
                // Ben is always quicker.
                try room.act(OfflineCoding.encode(Rules.Action.tap(card: due.index, ms: 300)), by: "b", match: 1, now: now)
                try room.act(OfflineCoding.encode(Rules.Action.tap(card: due.index, ms: 500)), by: "a", match: 1, now: now)
            }
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.first?.playerId, "b")
        XCTAssertEqual(room.standings?.first?.score, Rules.matchCount * Rules.firstPoints)
        XCTAssertEqual(room.standings?.last?.score, Rules.matchCount * Rules.correctPoints)
    }

    // MARK: - Review additions

    func testATapOnADueCardIsTakenBeforeTheHostTicks() throws {
        // The host ticks about ten times a second; a tap on a card that is
        // already due must not be refused because the tick has not come yet.
        var (state, rng) = running([match, clash, match])
        XCTAssertEqual(state.current, 0)
        try Rules.apply(.tap(card: 1, ms: 250), by: "a", to: &state, now: Rules.showAt(1, state) + 0.3, rng: &rng)
        XCTAssertEqual(state.current, 1)
        XCTAssertTrue(state.marks.contains { $0.card == 1 && $0.player == "a" })

        var (fresh, freshRng) = started()
        XCTAssertEqual(fresh.phase, .ready)
        try Rules.apply(.tap(card: 0, ms: 260), by: "b", to: &fresh, now: fresh.firstAt + 0.3, rng: &freshRng)
        XCTAssertEqual(fresh.phase, .running)
        XCTAssertEqual(Rules.view(of: fresh, for: "b").myMs, 260)
    }

    func testNoViewDependsOnAnotherPlayersSecrets() throws {
        var (state, rng) = running([match, clash, match, clash, match])
        try tap(&state, &rng, "a", card: 0, ms: 280)
        try tap(&state, &rng, "b", card: 0, ms: 330)
        XCTAssertEqual(state.scoredThrough, -1, "Cat has not tapped, so card 0 is still open")

        for viewer in ["a", "b", "c", nil] as [String?] {
            // Every card still to come swapped, and every other player's time
            // changed: what this phone is sent must not move.
            var other = state
            for index in other.cards.indices where index > other.current {
                other.cards[index] = Rules.Card(word: .purple, ink: .green)
            }
            other.marks = other.marks.map { mark in
                mark.player == viewer ? mark : Rules.Mark(card: mark.card, player: mark.player, ms: 999)
            }
            XCTAssertEqual(Rules.view(of: other, for: viewer), Rules.view(of: state, for: viewer),
                           "\(viewer ?? "a spectator") can see someone else's secret")
            let json = String(decoding: try OfflineCoding.encode(Rules.view(of: state, for: viewer)), as: UTF8.self)
            XCTAssertFalse(json.contains("marks"))
            XCTAssertFalse(json.contains("\"cards\""))
        }
    }
}
