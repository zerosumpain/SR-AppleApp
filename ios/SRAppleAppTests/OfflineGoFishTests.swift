import XCTest
@testable import SRAppleApp

/// Go Fish's rules: the deal, asking and fishing, books, whose turn it is,
/// the idle-turn timer, players leaving, the end of the game, and what each
/// phone is allowed to see.
final class OfflineGoFishTests: XCTestCase {
    private typealias Rules = GoFishRules

    private let players = [
        OfflinePlayer(id: "a", name: "Ann"),
        OfflinePlayer(id: "b", name: "Ben"),
        OfflinePlayer(id: "c", name: "Cat"),
    ]

    private func started(_ count: Int = 3, seed: UInt64 = 1, now: Double = 100) -> (Rules.State, OfflineRNG) {
        let seats = (0..<count).map { i in i < players.count ? players[i] : OfflinePlayer(id: "p\(i)", name: "P\(i)") }
        var rng = OfflineRNG(seed: seed)
        let state = Rules.start(players: seats, now: now, rng: &rng)
        return (state, rng)
    }

    /// A table set by hand: Ann to ask, the given hands and pond (drawn from the end).
    private func table(_ hands: [String: [OfflineCard]], stock: [OfflineCard], now: Double = 100) -> Rules.State {
        var state = Rules.State(players: players)
        for player in players {
            state.hands[player.id] = hands[player.id] ?? []
            state.books[player.id] = []
        }
        state.stock = stock
        state.turnIndex = 0
        state.turnEndsAt = now + Rules.turnSeconds
        return state
    }

    private func c(_ rank: Int, _ suit: OfflineSuit) -> OfflineCard { OfflineCard(rank, suit) }

    private func refusal(_ action: Rules.Action, by id: String, _ state: Rules.State) -> String? {
        var copy = state
        var rng = OfflineRNG(seed: 3)
        do {
            try Rules.apply(action, by: id, to: &copy, now: 101, rng: &rng)
            return nil
        } catch {
            return (error as? OfflineRefusal)?.reason
        }
    }

    // MARK: - Setup

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self, seed: 99), [])
        XCTAssertEqual(Rules.info.id, "go-fish")
        XCTAssertEqual(Rules.info.category, .card)
        XCTAssertEqual(Rules.info.minPlayers, 2)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    func testSevenEachForTwoOrThreeAndFiveForMore() {
        for count in 2...5 {
            let (state, _) = started(count, seed: UInt64(count))
            let each = count >= 4 ? 5 : 7
            var total = state.stock.count
            for player in state.players {
                let held = state.hands[player.id]?.count ?? 0
                let booked = (state.books[player.id]?.count ?? 0) * 4
                XCTAssertEqual(held + booked, each, "\(count) players")
                total += held + booked
            }
            XCTAssertEqual(total, 52)
            XCTAssertEqual(state.turnIndex, 0)
            XCTAssertEqual(state.turnNumber, 1)
            XCTAssertEqual(state.turnEndsAt, 100 + Rules.turnSeconds)
            XCTAssertEqual(state.phase, .playing)
        }
    }

    func testTheSeedDecidesTheDeal() {
        XCTAssertEqual(started(seed: 4).0, started(seed: 4).0)
        XCTAssertNotEqual(started(seed: 4).0.hands, started(seed: 5).0.hands)
    }

    // MARK: - Asking

    func testAHitHandsOverEveryCardAndGoesAgain() throws {
        var state = table(["a": [c(7, .clubs), c(2, .hearts)],
                           "b": [c(7, .hearts), c(7, .spades), c(9, .clubs)],
                           "c": [c(5, .clubs)]],
                          stock: [c(3, .clubs)])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.ask(turn: 1, target: "b", rank: 7), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.hands["a"]?.filter { $0.rank == 7 }.count, 3)
        XCTAssertEqual(state.hands["b"], [c(9, .clubs)])
        XCTAssertEqual(state.turnIndex, 0, "a hit goes again")
        XCTAssertEqual(state.turnNumber, 2)
        XCTAssertEqual(state.turnEndsAt, 110 + Rules.turnSeconds)
        XCTAssertEqual(state.stock.count, 1, "no fishing on a hit")
        let entry = try XCTUnwrap(state.log.last)
        XCTAssertEqual(entry.got, 2)
        XCTAssertFalse(entry.fished)
    }

    func testAMissGoesFishingAndPassesTheTurn() throws {
        var state = table(["a": [c(7, .clubs)], "b": [c(9, .clubs)], "c": [c(5, .clubs)]],
                          stock: [c(3, .clubs), c(4, .hearts)])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.ask(turn: 1, target: "b", rank: 7), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.hands["a"], [c(7, .clubs), c(4, .hearts)])
        XCTAssertEqual(state.lastFished["a"], c(4, .hearts))
        XCTAssertEqual(state.turnIndex, 1, "Ben's turn")
        let entry = try XCTUnwrap(state.log.last)
        XCTAssertEqual(entry.got, 0)
        XCTAssertTrue(entry.fished)
        XCTAssertFalse(entry.luckyDraw)
    }

    func testFishingTheAskedRankGoesAgain() throws {
        var state = table(["a": [c(7, .clubs)], "b": [c(9, .clubs)], "c": [c(5, .clubs)]],
                          stock: [c(3, .clubs), c(7, .hearts)])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.ask(turn: 1, target: "b", rank: 7), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.turnIndex, 0)
        XCTAssertTrue(try XCTUnwrap(state.log.last).luckyDraw)
    }

    func testAnEmptyPondJustPassesTheTurn() throws {
        var state = table(["a": [c(7, .clubs)], "b": [c(9, .clubs)], "c": [c(5, .clubs)]], stock: [])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.ask(turn: 1, target: "c", rank: 7), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.turnIndex, 1)
        XCTAssertFalse(try XCTUnwrap(state.log.last).fished)
    }

    func testFourOfAKindIsABookLaidAtOnce() throws {
        var state = table(["a": [c(7, .clubs), c(7, .diamonds), c(2, .clubs)],
                           "b": [c(7, .hearts), c(7, .spades)],
                           "c": [c(5, .clubs)]],
                          stock: [c(3, .clubs)])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.ask(turn: 1, target: "b", rank: 7), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.books["a"], [7])
        XCTAssertEqual(state.hands["a"], [c(2, .clubs)])
        XCTAssertEqual(try XCTUnwrap(state.log.last).books, [7])
        XCTAssertEqual(state.turnIndex, 0)
    }

    func testAnEmptyHandDrawsFiveOnItsTurn() throws {
        // Ann books her last cards and goes again with an empty hand: she refills.
        var state = table(["a": [c(7, .clubs), c(7, .diamonds), c(7, .hearts)],
                           "b": [c(7, .spades), c(9, .clubs)],
                           "c": [c(5, .clubs)]],
                          stock: [c(1, .clubs), c(2, .clubs), c(3, .clubs), c(4, .clubs), c(6, .clubs), c(8, .clubs)])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.ask(turn: 1, target: "b", rank: 7), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.books["a"], [7])
        XCTAssertEqual(state.hands["a"]?.count, 5)
        XCTAssertEqual(state.stock, [c(1, .clubs)])
        XCTAssertEqual(state.turnIndex, 0)
    }

    func testAnEmptyHandWithAnEmptyPondIsSkipped() throws {
        var state = table(["a": [c(7, .clubs)], "b": [], "c": [c(5, .clubs)]], stock: [])
        var rng = OfflineRNG(seed: 1)
        // Ben holds nothing, so only Cat may be asked.
        XCTAssertEqual(Rules.askable(state), ["c"])
        try Rules.apply(.ask(turn: 1, target: "c", rank: 7), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.turnIndex, 2, "Ben is out of cards and skipped")
    }

    // MARK: - Refusals

    func testIllegalAsksAreRefused() {
        let state = table(["a": [c(7, .clubs)], "b": [c(9, .clubs)], "c": []], stock: [c(3, .clubs)])
        XCTAssertEqual(refusal(.ask(turn: 1, target: "a", rank: 9), by: "b", state), "It's Ann's turn.")
        XCTAssertEqual(refusal(.ask(turn: 1, target: "b", rank: 9), by: "a", state), "You can only ask for a rank you hold.")
        XCTAssertEqual(refusal(.ask(turn: 1, target: "a", rank: 7), by: "a", state), "Ask someone else.")
        XCTAssertEqual(refusal(.ask(turn: 1, target: "z", rank: 7), by: "a", state), "That player is not in this game.")
        XCTAssertEqual(refusal(.ask(turn: 1, target: "c", rank: 7), by: "a", state), "Cat has no cards. Ask someone who does.")
        XCTAssertEqual(refusal(.ask(turn: 1, target: "b", rank: 0), by: "a", state), "That is not a card rank.")
        XCTAssertEqual(refusal(.ask(turn: 1, target: "b", rank: 14), by: "a", state), "That is not a card rank.")
        XCTAssertEqual(refusal(.ask(turn: 0, target: "b", rank: 7), by: "a", state), "That ask was for an earlier turn.")
        XCTAssertEqual(refusal(.ask(turn: 1, target: "b", rank: 7), by: "x", state), "You are not in this game.")
        XCTAssertNil(refusal(.ask(turn: 1, target: "b", rank: 7), by: "a", state))

        var gone = state
        gone.away = ["b"]
        XCTAssertEqual(refusal(.ask(turn: 1, target: "b", rank: 7), by: "a", gone), "Ben has left the game.")
        XCTAssertEqual(refusal(.ask(turn: 1, target: "a", rank: 9), by: "b", gone), "You have left this game.")

        var over = state
        over.phase = .over
        XCTAssertEqual(refusal(.ask(turn: 1, target: "b", rank: 7), by: "a", over), "The game is over.")
    }

    func testARepeatedAskIsStale() throws {
        var state = table(["a": [c(7, .clubs)], "b": [c(7, .hearts)], "c": [c(5, .clubs)]], stock: [c(3, .clubs)])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.ask(turn: 1, target: "b", rank: 7), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertThrowsError(try Rules.apply(.ask(turn: 1, target: "c", rank: 7), by: "a", to: &state, now: 111, rng: &rng)) { error in
            XCTAssertEqual((error as? OfflineRefusal)?.reason, "That ask was for an earlier turn.")
        }
    }

    // MARK: - Timer

    func testAnIdleTurnIsAskedForThePlayer() {
        var state = table(["a": [c(7, .clubs), c(7, .hearts), c(2, .clubs)],
                           "b": [c(9, .clubs)],
                           "c": [c(5, .clubs)]],
                          stock: [c(3, .clubs)])
        var rng = OfflineRNG(seed: 1)
        let deadline = state.turnEndsAt
        Rules.tick(&state, now: deadline - 0.1, rng: &rng)
        XCTAssertEqual(state.turnNumber, 1, "not yet")
        Rules.tick(&state, now: deadline + 0.3, rng: &rng)
        XCTAssertEqual(state.turnNumber, 2)
        let entry = state.log.last
        XCTAssertEqual(entry?.target, "b", "the next player with cards")
        XCTAssertEqual(entry?.rank, 7, "the rank Ann holds most of")
        XCTAssertEqual(entry?.timedOut, true)
        XCTAssertEqual(state.turnIndex, 1)
        let settled = state
        Rules.tick(&state, now: deadline + 0.3, rng: &rng)
        XCTAssertEqual(state, settled)
    }

    // MARK: - Leaving

    func testALeaverReturnsTheirCardsAndIsSkipped() throws {
        var state = table(["a": [c(7, .clubs)], "b": [c(9, .clubs), c(9, .hearts)], "c": [c(5, .clubs)]],
                          stock: [c(3, .clubs)])
        state.books["b"] = [12]
        var rng = OfflineRNG(seed: 1)
        Rules.playerLeft("b", state: &state, now: 105, rng: &rng)
        XCTAssertEqual(state.away, ["b"])
        XCTAssertEqual(state.hands["b"], [])
        XCTAssertEqual(state.stock.count, 3)
        XCTAssertEqual(state.books["b"], [12], "books made are kept")
        XCTAssertEqual(Rules.askable(state), ["c"])
        XCTAssertEqual(state.turnIndex, 0, "still Ann's turn")
        // Ann misses; Ben is skipped, so Cat asks next.
        try Rules.apply(.ask(turn: 1, target: "c", rank: 7), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.turnIndex, 2)
        Rules.playerLeft("b", state: &state, now: 111, rng: &rng)
        XCTAssertEqual(state.away, ["b"], "leaving twice changes nothing")
    }

    func testTheAskersLeavingPassesTheTurn() {
        var state = table(["a": [c(7, .clubs)], "b": [c(9, .clubs)], "c": [c(5, .clubs)]], stock: [])
        var rng = OfflineRNG(seed: 1)
        Rules.playerLeft("a", state: &state, now: 105, rng: &rng)
        XCTAssertEqual(state.turnIndex, 1)
        XCTAssertEqual(state.turnNumber, 2)
        XCTAssertEqual(state.turnEndsAt, 105 + Rules.turnSeconds)
        Rules.playerLeft("b", state: &state, now: 106, rng: &rng)
        XCTAssertTrue(Rules.isOver(state), "one player left cannot play on")
        XCTAssertEqual(Rules.standings(state).count, 3)
    }

    // MARK: - The end

    func testTheLastBookEndsItAndMostBooksWins() throws {
        var state = table(["a": [c(13, .clubs), c(13, .diamonds), c(13, .hearts)],
                           "b": [c(13, .spades)],
                           "c": []],
                          stock: [])
        state.books = ["a": [1, 2, 3, 4, 5], "b": [6, 7, 8, 9, 10], "c": [11, 12]]
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.ask(turn: 1, target: "b", rank: 13), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(Rules.champions(state), ["a"])
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "b", "c"])
        XCTAssertEqual(table.map(\.score), [6, 5, 2])
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(Rules.view(of: state, for: "b").champions, ["a"])
        XCTAssertNil(Rules.view(of: state, for: "b").turn)
    }

    func testTiesShareARank() {
        var state = table([:], stock: [])
        state.books = ["a": [1, 2, 3, 4, 5], "b": [6, 7, 8, 9, 10], "c": [11, 12, 13]]
        state.phase = .over
        XCTAssertEqual(Rules.standings(state).map(\.rank), [1, 1, 3])
        XCTAssertEqual(Rules.champions(state), ["a", "b"])
    }

    // MARK: - Redaction

    func testNobodySeesAnotherHand() throws {
        let (state, _) = started(seed: 11)
        let annCards = Set(try XCTUnwrap(state.hands["a"]).map(\.id))
        for viewer in ["b", "c", nil] as [String?] {
            let view = Rules.view(of: state, for: viewer)
            let json = String(decoding: try OfflineCoding.encode(view), as: UTF8.self)
            if let mine = view.myHand {
                XCTAssertTrue(Set(mine.map(\.id)).isDisjoint(with: annCards))
            }
            XCTAssertFalse(json.contains("\"hands\""))
            XCTAssertEqual(view.seats.first { $0.id == "a" }?.cards, annCards.count)
        }
        XCTAssertNil(Rules.view(of: state, for: nil).myHand, "a spectator holds no hand")
        XCTAssertEqual(Set(try XCTUnwrap(Rules.view(of: state, for: "a").myHand).map(\.id)), annCards)
        XCTAssertNil(Rules.view(of: state, for: "zz").myHand)
    }

    func testAFishedCardIsPrivateUnlessLucky() throws {
        var state = table(["a": [c(7, .clubs)], "b": [c(9, .clubs)], "c": [c(5, .clubs)]],
                          stock: [c(3, .clubs), c(4, .hearts)])
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.ask(turn: 1, target: "b", rank: 7), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertEqual(Rules.view(of: state, for: "a").myFished, c(4, .hearts))
        for viewer in ["b", "c", nil] as [String?] {
            let view = Rules.view(of: state, for: viewer)
            XCTAssertNil(view.myFished)
            let json = String(decoding: try OfflineCoding.encode(view), as: UTF8.self)
            XCTAssertFalse(json.contains("hearts"), "the fished four of hearts leaked to \(viewer ?? "a spectator")")
        }
    }

    func testEveryViewHidesEveryOtherHand() throws {
        for count in 2...5 {
            var (state, rng) = started(count, seed: UInt64(40 + count))
            // A few asks first, so hands and fished cards have moved.
            for step in 0..<6 where !Rules.isOver(state) {
                let asker = state.players[state.turnIndex].id
                guard let rank = state.hands[asker]?.first?.rank, let target = Rules.askable(state).first else { break }
                try Rules.apply(.ask(turn: state.turnNumber, target: target, rank: rank), by: asker,
                                to: &state, now: 101 + Double(step), rng: &rng)
            }
            for viewer in state.players.map({ Optional($0.id) }) + [nil] {
                let json = String(decoding: try OfflineCoding.encode(Rules.view(of: state, for: viewer)), as: UTF8.self)
                for other in state.players where other.id != viewer {
                    for card in state.hands[other.id] ?? [] {
                        let encoded = String(decoding: try OfflineCoding.encode(card), as: UTF8.self)
                        XCTAssertFalse(json.contains(encoded),
                                       "\(other.name)'s \(card) leaked to \(viewer ?? "a spectator") (\(count) players)")
                    }
                }
                for card in state.stock {
                    let encoded = String(decoding: try OfflineCoding.encode(card), as: UTF8.self)
                    XCTAssertFalse(json.contains(encoded), "the pond's \(card) leaked to \(viewer ?? "a spectator")")
                }
            }
        }
    }

    func testALeaverRanksBelowEveryoneStillPlaying() {
        var state = table(["a": [c(7, .clubs)], "b": [c(9, .clubs)], "c": [c(5, .clubs)]], stock: [])
        state.books = ["a": [1], "b": [2, 3, 4], "c": []]
        var rng = OfflineRNG(seed: 2)
        Rules.playerLeft("b", state: &state, now: 101, rng: &rng)
        Rules.playerLeft("c", state: &state, now: 102, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "b", "c"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 3], "walking out with the lead does not win it")
        XCTAssertEqual(Rules.champions(state), ["a"])
    }

    func testOnlyTheAskerIsOfferedTargets() {
        let state = table(["a": [c(7, .clubs)], "b": [c(9, .clubs)], "c": [c(5, .clubs)]], stock: [])
        XCTAssertEqual(Rules.view(of: state, for: "a").askable, ["b", "c"])
        XCTAssertEqual(Rules.view(of: state, for: "b").askable, [])
        XCTAssertEqual(Rules.view(of: state, for: nil).askable, [])
    }

    // MARK: - Whole games

    /// Plays from a seed with a simple strategy (sometimes timing out) and checks
    /// the cards are conserved after every step.
    private func playOut(count: Int, seed: UInt64) throws -> Rules.State {
        var (state, rng) = started(count, seed: seed, now: 0)
        var pick = OfflineRNG(seed: seed &+ 1000)
        var now = 0.0
        var steps = 0
        while !Rules.isOver(state) && steps < 5000 {
            steps += 1
            now += 1
            let turn = try XCTUnwrap(Rules.view(of: state, for: nil).turn)
            let view = Rules.view(of: state, for: turn)
            if pick.chance(0.05) {
                Rules.tick(&state, now: view.turnEndsAt, rng: &rng)
                now = view.turnEndsAt
            } else {
                let hand = try XCTUnwrap(view.myHand)
                let rank = try XCTUnwrap(pick.pick(hand)).rank
                let target = try XCTUnwrap(pick.pick(view.askable))
                try Rules.apply(.ask(turn: view.turnNumber, target: target, rank: rank), by: turn, to: &state, now: now, rng: &rng)
            }
            if count >= 3, steps == 20 { Rules.playerLeft(state.players[count - 1].id, state: &state, now: now, rng: &rng) }
            let held = state.hands.values.reduce(0) { $0 + $1.count }
            let booked = state.books.values.reduce(0) { $0 + $1.count } * 4
            XCTAssertEqual(held + booked + state.stock.count, 52)
        }
        return state
    }

    func testManySeededGamesReachTheEnd() throws {
        for seed in 1...60 as ClosedRange<UInt64> {
            for count in 2...5 {
                let state = try playOut(count: count, seed: seed)
                XCTAssertTrue(Rules.isOver(state), "seed \(seed), \(count) players")
                let books = state.books.values.reduce(0) { $0 + $1.count }
                XCTAssertEqual(books, 13, "seed \(seed), \(count) players")
                XCTAssertEqual(Rules.standings(state).count, count)
                XCTAssertFalse(Rules.view(of: state, for: nil).champions.isEmpty)
            }
        }
    }

    func testAWholeGameThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("go-fish")
        try room.start(seed: 8, now: 0)
        _ = room.outbox()

        var now = 0.0
        var steps = 0
        while room.phase == .playing && steps < 2000 {
            steps += 1
            now += 0.5
            room.tick(now: now)
            for id in ["a", "b"] {
                let view = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: id)))
                guard view.turn == id, let hand = view.myHand, let rank = hand.first?.rank,
                      let target = view.askable.first else { continue }
                try room.act(OfflineCoding.encode(Rules.Action.ask(turn: view.turnNumber, target: target, rank: rank)),
                             by: id, match: 1, now: now)
                break
            }
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.map(\.score).reduce(0, +), 13)
    }
}
