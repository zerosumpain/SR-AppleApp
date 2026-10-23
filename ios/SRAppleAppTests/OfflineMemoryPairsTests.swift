import XCTest
@testable import SRAppleApp

/// Pairs' rules: the layout, turning cards, keeping a match and going again,
/// a miss passing the turn, timers, players leaving, the end of the match,
/// and that no phone is ever told where a face-down picture is.
final class OfflineMemoryPairsTests: XCTestCase {
    private typealias Rules = MemoryPairsRules

    private let players = [
        OfflinePlayer(id: "a", name: "Ann"),
        OfflinePlayer(id: "b", name: "Ben"),
        OfflinePlayer(id: "c", name: "Cat"),
    ]

    private func started(seed: UInt64 = 1, now: Double = 100,
                         players: [OfflinePlayer]? = nil) -> (Rules.State, OfflineRNG) {
        var rng = OfflineRNG(seed: seed)
        let state = Rules.start(players: players ?? self.players, now: now, rng: &rng)
        return (state, rng)
    }

    /// Two positions holding the same picture, still on the table.
    private func aPair(_ state: Rules.State) -> (Int, Int) {
        for i in state.layout.indices where state.owner[i] == nil {
            if let j = state.layout.indices.first(where: { $0 != i && state.owner[$0] == nil && state.layout[$0] == state.layout[i] }) {
                return (i, j)
            }
        }
        fatalError("no pair left")
    }

    /// Two positions with different pictures, still on the table.
    private func aMiss(_ state: Rules.State) -> (Int, Int) {
        for i in state.layout.indices where state.owner[i] == nil {
            if let j = state.layout.indices.first(where: { state.owner[$0] == nil && state.layout[$0] != state.layout[i] }) {
                return (i, j)
            }
        }
        fatalError("no miss possible")
    }

    private func flip(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ id: String, _ index: Int, now: Double = 101) throws {
        try Rules.apply(.flip(turn: state.turn, index: index), by: id, to: &state, now: now, rng: &rng)
    }

    private func reason(_ block: () throws -> Void) -> String? {
        do { try block() } catch { return (error as? OfflineRefusal)?.reason }
        return nil
    }

    // MARK: - Setup

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(Rules.info.id, "memory-pairs")
        XCTAssertEqual(Rules.info.category, .skill)
        XCTAssertEqual(Rules.info.minPlayers, 2)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    func testTheLayoutHoldsEveryPictureTwice() {
        for count in 2...5 {
            let group = (1...count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            let (state, _) = started(players: group)
            let pairs = Rules.pairCount(players: count)
            XCTAssertEqual(state.layout.count, pairs * 2)
            XCTAssertEqual(state.owner, Array(repeating: nil, count: pairs * 2))
            var counts: [Int: Int] = [:]
            for symbol in state.layout { counts[symbol, default: 0] += 1 }
            XCTAssertEqual(counts.count, pairs)
            XCTAssertTrue(counts.values.allSatisfy { $0 == 2 })
            XCTAssertTrue(state.layout.allSatisfy { Rules.symbols.indices.contains($0) })
            XCTAssertEqual(Rules.columns(cards: state.layout.count), count >= 4 ? 5 : 4)
            XCTAssertEqual(state.layout.count % Rules.columns(cards: state.layout.count), 0, "a full grid")
        }
    }

    func testAMatchOpensWithTheHostToPlay() {
        let (state, _) = started(now: 100)
        XCTAssertEqual(state.turnPlayer, "a")
        XCTAssertEqual(state.phase, .choosing)
        XCTAssertEqual(state.turnEndsAt, 100 + Rules.turnTime)
        XCTAssertEqual(state.pairs, ["a": 0, "b": 0, "c": 0])
        XCTAssertEqual(Rules.pairsLeft(state), 12)
        XCTAssertFalse(Rules.isOver(state))
    }

    func testTheSeedDecidesTheLayout() {
        XCTAssertEqual(started(seed: 4).0.layout, started(seed: 4).0.layout)
        XCTAssertNotEqual(started(seed: 4).0.layout, started(seed: 5).0.layout)
    }

    // MARK: - Turns

    func testAMatchIsKeptAndThePlayerGoesAgain() throws {
        var (state, rng) = started()
        let (i, j) = aPair(state)
        try flip(&state, &rng, "a", i)
        XCTAssertEqual(state.flipped, [i])
        let turnBefore = state.turn
        try flip(&state, &rng, "a", j, now: 105)
        XCTAssertEqual(state.owner[i], "a")
        XCTAssertEqual(state.owner[j], "a")
        XCTAssertEqual(state.pairs["a"], 1)
        XCTAssertEqual(state.flipped, [])
        XCTAssertEqual(state.turnPlayer, "a", "a match earns another go")
        XCTAssertEqual(state.turn, turnBefore + 1)
        XCTAssertEqual(state.turnEndsAt, 105 + Rules.turnTime)
        XCTAssertEqual(state.last, Rules.Last(kind: .matched, playerId: "a", symbol: state.layout[i]))
        XCTAssertEqual(Rules.pairsLeft(state), 11)
    }

    func testAMissIsShownThenTurnsBackAndPassesOn() throws {
        var (state, rng) = started()
        let (i, j) = aMiss(state)
        try flip(&state, &rng, "a", i)
        try flip(&state, &rng, "a", j, now: 110)
        XCTAssertEqual(state.phase, .showing)
        XCTAssertEqual(state.flipped, [i, j])
        XCTAssertEqual(state.hideAt, 110 + Rules.missPause)
        XCTAssertEqual(state.last?.kind, .missed)

        // Everyone sees the miss while it is up.
        let ben = Rules.view(of: state, for: "b")
        XCTAssertEqual(ben.cards[i].symbol, state.layout[i])
        XCTAssertEqual(ben.cards[j].symbol, state.layout[j])

        Rules.tick(&state, now: state.hideAt - 0.05, rng: &rng)
        XCTAssertEqual(state.phase, .showing)
        Rules.tick(&state, now: state.hideAt, rng: &rng)
        XCTAssertEqual(state.phase, .choosing)
        XCTAssertEqual(state.flipped, [])
        XCTAssertEqual(state.turnPlayer, "b")
        XCTAssertEqual(state.owner[i], nil)
        XCTAssertNil(Rules.view(of: state, for: "b").cards[i].symbol, "turned back means hidden again")
    }

    func testTurnsGoRoundInSeatOrder() throws {
        var (state, rng) = started()
        var order: [String] = []
        for _ in 0..<4 {
            order.append(state.turnPlayer)
            let (i, j) = aMiss(state)
            try flip(&state, &rng, state.turnPlayer, i)
            try flip(&state, &rng, state.turnPlayer, j)
            Rules.tick(&state, now: state.hideAt, rng: &rng)
        }
        XCTAssertEqual(order, ["a", "b", "c", "a"])
    }

    // MARK: - Refusals

    func testIllegalFlipsAreRefused() throws {
        var (state, rng) = started()
        let turn = state.turn
        XCTAssertEqual(reason { try Rules.apply(.flip(turn: turn, index: 0), by: "b", to: &state, now: 101, rng: &rng) },
                       "It's Ann's turn.")
        XCTAssertEqual(reason { try Rules.apply(.flip(turn: turn, index: 0), by: "zed", to: &state, now: 101, rng: &rng) },
                       "You are not playing this game.")
        XCTAssertEqual(reason { try Rules.apply(.flip(turn: turn, index: -1), by: "a", to: &state, now: 101, rng: &rng) },
                       "There is no card there.")
        XCTAssertEqual(reason { try Rules.apply(.flip(turn: turn, index: 24), by: "a", to: &state, now: 101, rng: &rng) },
                       "There is no card there.")
        XCTAssertEqual(reason { try Rules.apply(.flip(turn: turn + 1, index: 0), by: "a", to: &state, now: 101, rng: &rng) },
                       "That tap was for an earlier turn.")

        let (i, j) = aPair(state)
        try flip(&state, &rng, "a", i)
        XCTAssertEqual(reason { try flip(&state, &rng, "a", i) }, "That card is already face up.")
        try flip(&state, &rng, "a", j)
        XCTAssertEqual(reason { try flip(&state, &rng, "a", i) }, "That pair has already been taken.")
        // A tap from the turn before the extra go is stale.
        XCTAssertEqual(reason { try Rules.apply(.flip(turn: turn, index: 0), by: "a", to: &state, now: 101, rng: &rng) },
                       "That tap was for an earlier turn.")

        let (k, l) = aMiss(state)
        try flip(&state, &rng, "a", k)
        try flip(&state, &rng, "a", l)
        let other = state.layout.indices.first { state.owner[$0] == nil && $0 != k && $0 != l }!
        XCTAssertEqual(reason { try flip(&state, &rng, "a", other) }, "Wait — those cards are turning back.")
        XCTAssertEqual(reason { try flip(&state, &rng, "b", other) }, "Wait — those cards are turning back.")
    }

    func testAPlayerWhoLeftCannotFlip() throws {
        var (state, rng) = started()
        Rules.playerLeft("b", state: &state, now: 101, rng: &rng)
        XCTAssertEqual(reason { try flip(&state, &rng, "b", 0) }, "You have left this game.")
    }

    // MARK: - Timers

    func testASlowTurnRunsOutAndPassesOn() throws {
        var (state, rng) = started(now: 100)
        try flip(&state, &rng, "a", 3)
        Rules.tick(&state, now: 100 + Rules.turnTime - 0.1, rng: &rng)
        XCTAssertEqual(state.turnPlayer, "a")
        XCTAssertEqual(state.flipped, [3])
        Rules.tick(&state, now: 100 + Rules.turnTime + 0.4, rng: &rng)
        XCTAssertEqual(state.turnPlayer, "b")
        XCTAssertEqual(state.flipped, [], "the lone card turns back")
        XCTAssertEqual(state.last, Rules.Last(kind: .timedOut, playerId: "a", symbol: nil))
        XCTAssertEqual(state.turnEndsAt, 100 + Rules.turnTime + 0.4 + Rules.turnTime)
        let again = state
        Rules.tick(&state, now: 100 + Rules.turnTime + 0.4, rng: &rng)
        XCTAssertEqual(state, again, "ticking twice at one instant changes nothing")
    }

    // MARK: - Leaving

    func testALeaverOnTurnIsSkipped() throws {
        var (state, rng) = started()
        try flip(&state, &rng, "a", 0)
        Rules.playerLeft("a", state: &state, now: 102, rng: &rng)
        XCTAssertEqual(state.turnPlayer, "b")
        XCTAssertEqual(state.flipped, [])
        XCTAssertEqual(state.phase, .choosing)

        // Ben misses; Cat is next; Ann is skipped after Cat.
        var (i, j) = aMiss(state)
        try flip(&state, &rng, "b", i)
        try flip(&state, &rng, "b", j)
        Rules.tick(&state, now: state.hideAt, rng: &rng)
        XCTAssertEqual(state.turnPlayer, "c")
        (i, j) = aMiss(state)
        try flip(&state, &rng, "c", i)
        try flip(&state, &rng, "c", j)
        Rules.playerLeft("c", state: &state, now: 103, rng: &rng)
        XCTAssertEqual(state.phase, .showing, "a miss on show runs its course")
        Rules.tick(&state, now: state.hideAt, rng: &rng)
        XCTAssertEqual(state.turnPlayer, "b")
        XCTAssertEqual(Rules.standings(state).first { $0.playerId == "c" }?.detail, "left")
    }

    func testEverybodyLeavingEndsIt() {
        var (state, rng) = started()
        for id in ["a", "b", "c"] { Rules.playerLeft(id, state: &state, now: 101, rng: &rng) }
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(Rules.standings(state).count, 3)
    }

    func testAPhoneThatComesBackTakesItsTurnsAgain() throws {
        var (state, rng) = started()
        Rules.playerLeft("b", state: &state, now: 101, rng: &rng)
        XCTAssertEqual(reason { try Rules.apply(.back, by: "a", to: &state, now: 102, rng: &rng) },
                       "You are already in this game.")
        // Ann misses; Ben is away, so Cat is next.
        var (i, j) = aMiss(state)
        try flip(&state, &rng, "a", i)
        try flip(&state, &rng, "a", j)
        try Rules.apply(.back, by: "b", to: &state, now: 102, rng: &rng)
        XCTAssertEqual(state.away, [])
        XCTAssertEqual(state.phase, .showing, "coming back does not cut a miss short")
        Rules.tick(&state, now: state.hideAt, rng: &rng)
        XCTAssertEqual(state.turnPlayer, "b", "Ben is in the turn order again")
        (i, _) = aMiss(state)
        try flip(&state, &rng, "b", i)

        for id in ["a", "b", "c"] { Rules.playerLeft(id, state: &state, now: 110, rng: &rng) }
        XCTAssertEqual(reason { try Rules.apply(.back, by: "a", to: &state, now: 111, rng: &rng) }, "The game is over.")
    }

    // MARK: - Redaction

    func testFaceDownPicturesNeverLeaveTheHost() throws {
        var (state, rng) = started()
        let (i, j) = aPair(state)
        try flip(&state, &rng, "a", i)
        try flip(&state, &rng, "a", j)
        let (k, _) = aMiss(state)
        try flip(&state, &rng, "a", k)

        for viewer in ["a", "b", "c", nil] as [String?] {
            let view = Rules.view(of: state, for: viewer)
            for card in view.cards {
                let visible = card.index == i || card.index == j || card.index == k
                if visible {
                    XCTAssertEqual(card.symbol, state.layout[card.index])
                } else {
                    XCTAssertNil(card.symbol, "card \(card.index) leaked to \(viewer ?? "a spectator")")
                }
            }
            XCTAssertEqual(view.cards[i].owner, "a")
            XCTAssertTrue(view.cards[k].up)
            XCTAssertEqual(view.pairsLeft, 11)
            XCTAssertEqual(view.columns, 4)
            XCTAssertEqual(view.seats.map(\.pairs), [1, 0, 0])
        }

        // And the encoded view has no layout in it at all.
        let json = String(decoding: try OfflineCoding.encode(Rules.view(of: state, for: "b")), as: UTF8.self)
        XCTAssertFalse(json.contains("layout"))
    }

    /// Every viewer's encoded view, read back as plain JSON: a picture appears
    /// for exactly the cards everybody can see, mid-turn and mid-miss alike.
    func testNoViewersJSONCarriesAFaceDownPicture() throws {
        var (state, rng) = started()
        let (i, j) = aPair(state)
        try flip(&state, &rng, "a", i)
        try flip(&state, &rng, "a", j)
        let (k, l) = aMiss(state)
        try flip(&state, &rng, "a", k)
        for step in 0..<2 {
            if step == 1 { try flip(&state, &rng, "a", l) }   // now a miss on show
            let visible: Set<Int> = step == 0 ? [i, j, k] : [i, j, k, l]
            for viewer in ["a", "b", "c", nil, "zed"] as [String?] {
                let data = try OfflineCoding.encode(Rules.view(of: state, for: viewer))
                let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertNil(object["layout"])
                let cards = try XCTUnwrap(object["cards"] as? [[String: Any]])
                XCTAssertEqual(cards.count, state.layout.count)
                let shown = Set(cards.compactMap { card -> Int? in
                    card["symbol"] == nil || card["symbol"] is NSNull ? nil : card["index"] as? Int
                })
                XCTAssertEqual(shown, visible, "pictures sent to \(viewer ?? "a spectator")")
            }
        }
    }

    // MARK: - The end

    func testClearingTheTableEndsItAfterTheFinale() throws {
        var (state, rng) = started()
        // Ann takes seven pairs, misses; Ben takes the remaining five.
        for _ in 0..<7 {
            let (i, j) = aPair(state)
            try flip(&state, &rng, "a", i)
            try flip(&state, &rng, "a", j)
        }
        let (m, n) = aMiss(state)
        try flip(&state, &rng, "a", m)
        try flip(&state, &rng, "a", n)
        Rules.tick(&state, now: state.hideAt, rng: &rng)
        for _ in 0..<5 {
            let (i, j) = aPair(state)
            try flip(&state, &rng, "b", i, now: 120)
            try flip(&state, &rng, "b", j, now: 120)
        }
        XCTAssertEqual(state.phase, .finale)
        XCTAssertEqual(Rules.pairsLeft(state), 0)
        XCTAssertFalse(Rules.isOver(state), "the cleared table shows first")
        XCTAssertEqual(Rules.view(of: state, for: nil).champions, ["a"])
        XCTAssertEqual(reason { try flip(&state, &rng, "b", 0) }, "The game is over.")
        Rules.tick(&state, now: 120 + Rules.finalePause, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))

        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "b", "c"])
        XCTAssertEqual(table.map(\.score), [7, 5, 0])
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(table[0].detail, "7 in a row")
        XCTAssertEqual(table[1].detail, "5 in a row")
        XCTAssertNil(table[2].detail)
    }

    func testTiesShareARank() {
        var (state, _) = started()
        state.pairs = ["a": 4, "b": 4, "c": 4]
        XCTAssertEqual(Rules.standings(state).map(\.rank), [1, 1, 1])
        XCTAssertEqual(Rules.champions(state), ["a", "b", "c"])
    }

    // MARK: - Whole games

    func testRandomPlayoutsAlwaysFinish() throws {
        for seed in 1...100 as ClosedRange<UInt64> {
            let count = Int(seed % 4) + 2
            let group = (1...count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            var (state, rng) = started(seed: seed, players: group)
            var moves = OfflineRNG(seed: seed &* 31)
            var now = 100.0
            var steps = 0
            while !Rules.isOver(state) && steps < 5_000 {
                steps += 1
                now += 0.2
                if state.phase == .choosing, moves.chance(0.9) {
                    let open = state.layout.indices.filter { state.owner[$0] == nil && !state.flipped.contains($0) }
                    if let pick = moves.pick(open) {
                        try Rules.apply(.flip(turn: state.turn, index: pick), by: state.turnPlayer,
                                        to: &state, now: now, rng: &rng)
                    }
                }
                if moves.chance(0.002), let leaver = moves.pick(group.map(\.id)) {
                    Rules.playerLeft(leaver, state: &state, now: now, rng: &rng)
                }
                Rules.tick(&state, now: now, rng: &rng)
                // Never a face-down picture in anyone's view.
                guard steps % 5 == 0 else { continue }
                let view = Rules.view(of: state, for: group[0].id)
                for card in view.cards where card.owner == nil && !card.up { XCTAssertNil(card.symbol) }
            }
            XCTAssertTrue(Rules.isOver(state), "seed \(seed) did not finish")
            XCTAssertEqual(Rules.standings(state).count, count)
            let taken = state.pairs.values.reduce(0, +)
            if state.away.count < count {
                XCTAssertEqual(taken, Rules.pairCount(players: count), "seed \(seed)")
            }
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("memory-pairs")
        try room.start(seed: 8, now: 0)
        _ = room.outbox()

        // Ben has a perfect memory of what he has seen; Ann turns cards in order.
        var seen: [Int: Int] = [:]
        var now = 0.0
        while room.phase == .playing && now < 2_000 {
            now += 0.25
            room.tick(now: now)
            let view = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "b")))
            for card in view.cards { if let symbol = card.symbol { seen[card.index] = symbol } }
            guard view.phase == .choosing else { continue }
            let open = view.cards.filter { $0.owner == nil && !$0.up }.map(\.index)
            guard !open.isEmpty else { continue }
            var pick = open[0]
            if view.turnPlayer == "b" {
                let up = view.cards.first { $0.up }
                if let up, let symbol = up.symbol,
                   let twin = open.first(where: { seen[$0] == symbol }) {
                    pick = twin
                } else if up == nil,
                          let known = open.first(where: { i in open.contains { $0 != i && seen[$0] != nil && seen[$0] == seen[i] } }) {
                    pick = known
                } else if let fresh = open.first(where: { seen[$0] == nil }) {
                    pick = fresh
                }
            }
            try room.act(OfflineCoding.encode(Rules.Action.flip(turn: view.turn, index: pick)),
                         by: view.turnPlayer, match: 1, now: now)
        }
        XCTAssertEqual(room.phase, .finished)
        let table = try XCTUnwrap(room.standings)
        XCTAssertEqual(table.count, 2)
        XCTAssertEqual(table.map(\.score).reduce(0, +), 12)
    }
}
