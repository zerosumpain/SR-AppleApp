import XCTest
@testable import SRAppleApp

/// Snap's rules: the deal, the beat of turning cards, who wins a pair, false
/// snaps and their price, running out, the clock, and what each phone sees.
final class OfflineSnapTests: XCTestCase {
    private typealias Rules = SnapRules

    private let players = [
        OfflinePlayer(id: "a", name: "Ann"),
        OfflinePlayer(id: "b", name: "Ben"),
        OfflinePlayer(id: "c", name: "Cat"),
    ]

    private func started(seed: UInt64 = 1, now: Double = 100, count: Int = 3) -> (Rules.State, OfflineRNG) {
        var rng = OfflineRNG(seed: seed)
        let state = Rules.start(players: Array(players.prefix(count)), now: now, rng: &rng)
        return (state, rng)
    }

    /// A table laid by hand: each seat's stack and pile (bottom first).
    private func table(_ seats: [([OfflineCard], [OfflineCard])], now: Double = 100) -> Rules.State {
        var state = Rules.State(players: Array(players.prefix(seats.count)),
                                seats: seats.map { Rules.Seat(stack: $0.0, pile: $0.1) })
        state.startedAt = now
        state.nextFlipAt = now
        state.endsAt = now + Rules.matchLength
        return state
    }

    private func cards(_ state: Rules.State) -> Int {
        state.seats.reduce(0) { $0 + $1.total }
    }

    private func c(_ rank: Int, _ suit: OfflineSuit = .spades) -> OfflineCard { OfflineCard(rank, suit) }

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(Rules.info.id, "snap")
        XCTAssertEqual(Rules.info.category, .reaction)
        XCTAssertEqual(Rules.info.minPlayers, 2)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    func testTheWholeDeckIsDealtFaceDown() {
        for count in 2...3 {
            let (state, _) = started(count: count)
            XCTAssertEqual(cards(state), 52)
            XCTAssertEqual(Set(state.seats.flatMap(\.stack).map(\.id)).count, 52)
            XCTAssertTrue(state.seats.allSatisfy { $0.pile.isEmpty })
            let sizes = state.seats.map(\.stack.count)
            XCTAssertLessThanOrEqual(sizes.max()! - sizes.min()!, 1)
        }
        let (state, _) = started(now: 100)
        XCTAssertEqual(state.phase, .playing)
        XCTAssertEqual(state.flip, 0)
        XCTAssertEqual(state.nextFlipAt, 100 + Rules.firstFlipDelay)
        XCTAssertEqual(state.endsAt, 100 + Rules.firstFlipDelay + Rules.matchLength)
        XCTAssertEqual(started(seed: 3).0, started(seed: 3).0)
        XCTAssertNotEqual(started(seed: 3).0.seats, started(seed: 4).0.seats)
    }

    func testCardsTurnInSeatOrderAndTheBeatQuickens() {
        var (state, rng) = started(now: 100)
        Rules.tick(&state, now: 101, rng: &rng)
        XCTAssertEqual(state.flip, 0, "not before the first beat")
        let annTop = state.seats[0].stack.last
        Rules.tick(&state, now: 102, rng: &rng)
        XCTAssertEqual(state.flip, 1)
        XCTAssertEqual(state.seats[0].pile.last, annTop)
        XCTAssertEqual(state.lastFlipSeat, 0)
        XCTAssertEqual(state.flipAt, 102)
        XCTAssertEqual(state.turn, 1)
        Rules.tick(&state, now: 102, rng: &rng)
        XCTAssertEqual(state.flip, 1, "one card per beat, however often it ticks")
        XCTAssertEqual(state.nextFlipAt, 102 + Rules.interval(after: 1), accuracy: 1e-9)
        XCTAssertLessThan(Rules.interval(after: 30), Rules.interval(after: 1))
        XCTAssertEqual(Rules.interval(after: 10_000), Rules.fastestInterval)
    }

    func testAPairOpensAWindowAndTheQuickestTimeTakesThePiles() throws {
        // Ann's 7 is up; Ben is about to turn another 7.
        var state = table([([c(2)], [c(4, .hearts), c(7, .hearts)]), ([c(9), c(7, .clubs)], [c(3)]), ([c(5)], [])])
        state.turn = 1
        var rng = OfflineRNG(seed: 1)
        Rules.tick(&state, now: 100, rng: &rng)
        XCTAssertEqual(state.flip, 1)
        let window = try XCTUnwrap(state.window)
        XCTAssertEqual(window.closesAt, 100 + Rules.snapWindow)

        try Rules.apply(.snap(flip: 1, ms: 320), by: "a", to: &state, now: 100.4, rng: &rng)
        try Rules.apply(.snap(flip: 1, ms: 260), by: "c", to: &state, now: 100.5, rng: &rng)
        XCTAssertNotNil(state.window, "Ben has not answered yet")
        XCTAssertThrowsError(try Rules.apply(.snap(flip: 1, ms: 200), by: "a", to: &state, now: 100.6, rng: &rng)) { error in
            XCTAssertEqual((error as? OfflineRefusal)?.reason, "You have already snapped.")
        }
        Rules.tick(&state, now: 100 + Rules.snapWindow - 0.01, rng: &rng)
        XCTAssertNotNil(state.window)
        Rules.tick(&state, now: 100 + Rules.snapWindow, rng: &rng)
        XCTAssertNil(state.window)
        // Cat, slower to arrive but quicker to react, wins both piles.
        XCTAssertEqual(state.seats[2].stack.count, 1 + 2 + 2)
        XCTAssertEqual(state.seats[2].stack.last, c(5), "the winnings go underneath")
        XCTAssertTrue(state.seats[0].pile.isEmpty)
        XCTAssertTrue(state.seats[1].pile.isEmpty)
        XCTAssertEqual(state.snapsWon["c"], 1)
        XCTAssertEqual(state.best["c"], 260)
        XCTAssertEqual(state.notice?.kind, .won)
        XCTAssertEqual(state.notice?.cards, 4)
        XCTAssertEqual(cards(state), 7)
        XCTAssertEqual(state.nextFlipAt, 100 + Rules.snapWindow + Rules.resultPause, accuracy: 1e-9)

        XCTAssertThrowsError(try Rules.apply(.snap(flip: 1, ms: 400), by: "b", to: &state, now: 101.7, rng: &rng)) { error in
            XCTAssertEqual((error as? OfflineRefusal)?.reason, "Too slow — that snap is over.")
        }
        XCTAssertEqual(state.falseSnaps["b"], nil, "a late snap is not a false one")
    }

    func testTheWindowClosesOnceEveryoneHasSnapped() throws {
        var state = table([([c(2)], [c(7, .hearts)]), ([c(7, .clubs)], [])])
        state.turn = 1
        var rng = OfflineRNG(seed: 1)
        Rules.tick(&state, now: 100, rng: &rng)
        try Rules.apply(.snap(flip: 1, ms: 300), by: "a", to: &state, now: 100.3, rng: &rng)
        try Rules.apply(.snap(flip: 1, ms: 280), by: "b", to: &state, now: 100.35, rng: &rng)
        XCTAssertNil(state.window)
        XCTAssertEqual(state.seats[1].stack.count, 2)
        XCTAssertEqual(state.seats[0].total, 1)
    }

    func testAnUnsnappedPairStaysAndIsJudgedEmpty() {
        var state = table([([c(2)], [c(7, .hearts)]), ([c(9), c(7, .clubs)], [])])
        state.turn = 1
        var rng = OfflineRNG(seed: 1)
        Rules.tick(&state, now: 100, rng: &rng)
        Rules.tick(&state, now: 100 + Rules.snapWindow, rng: &rng)
        XCTAssertEqual(state.notice?.kind, .missed)
        XCTAssertEqual(state.seats[0].pile.count, 1)
        XCTAssertEqual(state.seats[1].pile.count, 1)
    }

    func testAFalseSnapPaysACardToEachOtherPlayer() throws {
        var state = table([([c(2), c(3)], [c(4)]), ([c(9)], [c(5)]), ([c(10)], [])])
        state.turn = 2
        var rng = OfflineRNG(seed: 1)
        Rules.tick(&state, now: 100, rng: &rng)
        XCTAssertNil(state.window, "4, 5 and 10 are no pair")
        try Rules.apply(.snap(flip: 1, ms: 300), by: "a", to: &state, now: 100.4, rng: &rng)
        XCTAssertEqual(state.seats[0].stack, [], "Ann paid off the top of her stack")
        XCTAssertEqual(state.seats[0].pile, [c(4)])
        XCTAssertEqual(state.seats[1].stack, [c(3), c(9)], "a paid card goes underneath")
        XCTAssertEqual(state.seats[2].stack, [c(2)])
        XCTAssertEqual(state.seats[2].pile, [c(10)])
        XCTAssertEqual(state.falseSnaps["a"], 1)
        XCTAssertEqual(state.notice?.kind, .falseSnap)
        XCTAssertEqual(state.notice?.cards, 2)
        XCTAssertEqual(cards(state), 6)
        XCTAssertThrowsError(try Rules.apply(.snap(flip: 1, ms: 400), by: "a", to: &state, now: 100.5, rng: &rng)) { error in
            XCTAssertEqual((error as? OfflineRefusal)?.reason, "You have already snapped at this card.")
        }
        XCTAssertEqual(state.falseSnaps["a"], 1, "a double tap pays once")
    }

    func testAGuessAtAPairIsAFalseSnap() throws {
        var state = table([([c(2), c(3)], [c(7, .hearts)]), ([c(7, .clubs)], []), ([c(10)], [])])
        state.turn = 1
        var rng = OfflineRNG(seed: 1)
        Rules.tick(&state, now: 100, rng: &rng)
        try Rules.apply(.snap(flip: 1, ms: 40), by: "a", to: &state, now: 100.1, rng: &rng)
        XCTAssertEqual(state.falseSnaps["a"], 1)
        XCTAssertEqual(state.seats[0].stack.count, 0)
        try Rules.apply(.snap(flip: 1, ms: 500), by: "c", to: &state, now: 100.6, rng: &rng)
        try Rules.apply(.snap(flip: 1, ms: 600), by: "b", to: &state, now: 100.7, rng: &rng)
        XCTAssertNil(state.window)
        XCTAssertEqual(state.notice?.kind, .won)
        XCTAssertEqual(state.notice?.playerId, "c", "the guess cannot win even though it was quickest")
    }

    func testSnappingAtThePreviousCardWhileANewPairIsUpIsFalse() throws {
        var state = table([([c(2)], [c(7, .hearts)]), ([c(4)], []), ([c(7, .clubs)], [])])
        state.turn = 1
        var rng = OfflineRNG(seed: 1)
        Rules.tick(&state, now: 100, rng: &rng) // Ben's 4: no pair
        XCTAssertNil(state.window)
        Rules.tick(&state, now: state.nextFlipAt, rng: &rng) // Cat's 7: pair
        XCTAssertEqual(state.window?.flip, 2)
        try Rules.apply(.snap(flip: 1, ms: 900), by: "b", to: &state, now: state.flipAt + 0.05, rng: &rng)
        XCTAssertEqual(state.falseSnaps["b"], 1)
    }

    func testBadSnapsAreRefused() throws {
        var (state, rng) = started()
        func reason(_ action: Rules.Action, _ who: String) -> String? {
            do {
                try Rules.apply(action, by: who, to: &state, now: 103, rng: &rng)
                return nil
            } catch {
                return (error as? OfflineRefusal)?.reason
            }
        }
        XCTAssertEqual(reason(.snap(flip: 1, ms: 300), "zed"), "You are not in this game.")
        XCTAssertEqual(reason(.snap(flip: 0, ms: 300), "a"), "Wait for the first card.")
        XCTAssertEqual(reason(.snap(flip: 1, ms: -1), "a"), "That time cannot be right.")
        XCTAssertEqual(reason(.snap(flip: 1, ms: 999_999), "a"), "That time cannot be right.")
        XCTAssertEqual(reason(.snap(flip: 1, ms: 300), "a"), "That card has not been turned yet.")
        for step in 0..<3 { Rules.tick(&state, now: 102 + Double(step) * 1.2, rng: &rng) }
        if state.window == nil {
            XCTAssertEqual(reason(.snap(flip: state.flip - 2, ms: 300), "a"), "Too late — the cards have moved on.")
        }
        state.out = ["b"]
        XCTAssertEqual(reason(.snap(flip: state.flip, ms: 300), "b"), "You are out — no more snapping.")
        state.away = ["c"]
        XCTAssertEqual(reason(.snap(flip: state.flip, ms: 300), "c"), "You have left this game.")
    }

    func testAnEmptyStackTurnsThePileOver() {
        var state = table([([], [c(3), c(4), c(5)]), ([c(9)], [])])
        var rng = OfflineRNG(seed: 1)
        Rules.tick(&state, now: 100, rng: &rng)
        XCTAssertEqual(state.seats[0].pile, [c(3)], "the old bottom card shows first")
        XCTAssertEqual(state.seats[0].stack, [c(5), c(4)])
        XCTAssertEqual(state.notice?.kind, .turnedOver)
    }

    func testLosingYourLastCardsKnocksYouOutAndTheLastStandingWins() throws {
        // Ann has only her pile; Ben's 7 wins it from her.
        var state = table([([], [c(7, .hearts)]), ([c(7, .clubs)], []), ([c(2)], [])])
        state.turn = 1
        var rng = OfflineRNG(seed: 1)
        Rules.tick(&state, now: 100, rng: &rng)
        try Rules.apply(.snap(flip: 1, ms: 250), by: "b", to: &state, now: 100.3, rng: &rng)
        Rules.tick(&state, now: 100 + Rules.snapWindow, rng: &rng)
        XCTAssertEqual(state.out, ["a"])
        XCTAssertEqual(state.phase, .playing)
        XCTAssertThrowsError(try Rules.apply(.snap(flip: 1, ms: 300), by: "a", to: &state, now: 102, rng: &rng))

        // Cat false-snaps her last card away.
        Rules.tick(&state, now: state.nextFlipAt, rng: &rng) // Cat's 2
        try Rules.apply(.snap(flip: 2, ms: 300), by: "c", to: &state, now: state.flipAt + 0.3, rng: &rng)
        XCTAssertEqual(state.out, ["a", "c"])
        XCTAssertEqual(state.phase, .ending)
        XCTAssertEqual(Rules.champions(state), ["b"])
        XCTAssertFalse(Rules.isOver(state), "the result shows first")
        Rules.tick(&state, now: state.endingUntil, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(cards(state), 3)

        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["b", "a", "c"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 2])
        XCTAssertEqual(table.first?.score, 3)
        XCTAssertEqual(table.first?.detail, "1 snap · best 250 ms")
        XCTAssertEqual(table.last?.detail, "0 snaps · 1 false snap · out")
    }

    func testAfterThreeMinutesTheMostCardsWins() {
        var state = table([([c(2), c(3), c(4)], []), ([c(5)], []), ([c(6), c(8)], [])])
        state.nextFlipAt = 10_000
        var rng = OfflineRNG(seed: 1)
        Rules.tick(&state, now: state.endsAt - 0.01, rng: &rng)
        XCTAssertEqual(state.phase, .playing)
        Rules.tick(&state, now: state.endsAt, rng: &rng)
        XCTAssertEqual(state.phase, .ending)
        XCTAssertEqual(Rules.champions(state), ["a"])
        XCTAssertEqual(Rules.standings(state).map(\.score), [3, 2, 1])
    }

    func testTimeUpJudgesAnOpenPairFirst() throws {
        var state = table([([c(2)], [c(7, .hearts)]), ([c(7, .clubs)], [])])
        state.turn = 1
        var rng = OfflineRNG(seed: 1)
        Rules.tick(&state, now: 100, rng: &rng)
        try Rules.apply(.snap(flip: 1, ms: 300), by: "a", to: &state, now: 100.3, rng: &rng)
        Rules.tick(&state, now: state.endsAt, rng: &rng)
        XCTAssertEqual(state.phase, .ending)
        XCTAssertEqual(state.snapsWon["a"], 1)
        XCTAssertEqual(Rules.champions(state), ["a"])
    }

    func testAPlayerWhoLeavesIsSkippedAndNotWaitedFor() throws {
        var state = table([([c(2)], [c(7, .hearts)]), ([c(3), c(7, .clubs)], []), ([c(9), c(10)], [])])
        state.turn = 1
        var rng = OfflineRNG(seed: 1)
        Rules.tick(&state, now: 100, rng: &rng)
        try Rules.apply(.snap(flip: 1, ms: 300), by: "a", to: &state, now: 100.3, rng: &rng)
        try Rules.apply(.snap(flip: 1, ms: 350), by: "b", to: &state, now: 100.3, rng: &rng)
        XCTAssertNotNil(state.window)
        Rules.playerLeft("c", state: &state, now: 100.4, rng: &rng)
        XCTAssertNil(state.window, "Cat was the only one left to snap")
        XCTAssertEqual(state.snapsWon["a"], 1)
        XCTAssertEqual(state.turn, 2)
        Rules.tick(&state, now: state.nextFlipAt, rng: &rng)
        XCTAssertEqual(state.lastFlipSeat, 0, "Cat's turn is skipped")
        XCTAssertEqual(Rules.standings(state).last?.playerId, "c")
        XCTAssertEqual(Rules.standings(state).last?.detail, "0 snaps · left")

        Rules.playerLeft("b", state: &state, now: 103, rng: &rng)
        XCTAssertEqual(state.phase, .ending, "one player cannot snap alone")
    }

    func testOthersCardsAndSnapsStayHidden() throws {
        var state = table([([c(2), c(3)], [c(7, .hearts)]), ([c(7, .clubs), c(9)], []), ([c(12), c(13)], [])])
        state.turn = 1
        var rng = OfflineRNG(seed: 1)
        Rules.tick(&state, now: 100, rng: &rng) // Ben turns his 9: no pair
        state.nextFlipAt = 100
        Rules.tick(&state, now: 101, rng: &rng) // Cat turns her king
        state.turn = 1
        Rules.tick(&state, now: 103, rng: &rng) // Ben turns his 7: a pair
        XCTAssertNotNil(state.window)
        try Rules.apply(.snap(flip: 3, ms: 270), by: "a", to: &state, now: 103.3, rng: &rng)

        let ben = Rules.view(of: state, for: "b")
        XCTAssertNil(ben.mySnap, "Ben cannot see Ann's time")
        XCTAssertEqual(Rules.view(of: state, for: "a").mySnap, 270)
        XCTAssertNil(Rules.view(of: state, for: nil).mySnap)
        XCTAssertEqual(ben.piles.map(\.stack), [2, 0, 1])
        XCTAssertEqual(ben.piles.map(\.top), [c(7, .hearts), c(7, .clubs), c(13)])
        XCTAssertEqual(ben.lastFlipper, "b")
        XCTAssertEqual(ben.flip, 3)
        XCTAssertEqual(ben.piles.first { $0.isTurn }?.id, "c")

        // Nothing face down is anywhere in what is sent.
        for who in ["a", "b", "c", nil] as [String?] {
            let json = String(decoding: try OfflineCoding.encode(Rules.view(of: state, for: who)), as: UTF8.self)
            XCTAssertFalse(json.contains("\"stack\":["), "a stack's cards are never sent")
            XCTAssertFalse(json.contains("claims"))
        }
        // Everyone's view matches apart from their own snap.
        let spectator = Rules.view(of: state, for: nil)
        XCTAssertEqual(ben.piles, spectator.piles)
        XCTAssertEqual(ben.notice, spectator.notice)
    }

    func testRandomMatchesAlwaysFinishAndKeepEveryCard() throws {
        for seed in UInt64(1)...60 {
            let count = Int(seed % 4) + 2
            let table = (0..<count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            var rng = OfflineRNG(seed: seed)
            var bots = OfflineRNG(seed: seed &* 31 &+ 7)
            var state = Rules.start(players: table, now: 0, rng: &rng)
            var now = 0.0
            var lastFlip = 0
            while !Rules.isOver(state) && now < 400 {
                now += 0.1
                Rules.tick(&state, now: now, rng: &rng)
                if state.flip != lastFlip { lastFlip = state.flip }
                for player in table where state.phase == .playing && bots.chance(0.08) {
                    guard !state.out.contains(player.id), !state.away.contains(player.id), state.flip > 0 else { continue }
                    // Mostly honest snaps; now and then a careless one.
                    let honest = state.window != nil || bots.chance(0.05)
                    guard honest else { continue }
                    do {
                        try Rules.apply(.snap(flip: state.flip, ms: bots.int(in: 60...900)), by: player.id,
                                        to: &state, now: now, rng: &rng)
                    } catch is OfflineRefusal {
                        // Already snapped, too slow: fine.
                    }
                }
                if seed % 7 == 0, now > 30, now < 30.11 {
                    Rules.playerLeft(table[count - 1].id, state: &state, now: now, rng: &rng)
                }
                XCTAssertEqual(cards(state), 52, "seed \(seed)")
            }
            XCTAssertTrue(Rules.isOver(state), "seed \(seed) never finished")
            XCTAssertGreaterThan(state.flip, 0)
            let standings = Rules.standings(state)
            XCTAssertEqual(standings.count, count)
            XCTAssertEqual(standings.first?.rank, 1)
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("snap")
        try room.start(seed: 8, now: 0)
        _ = room.outbox()

        var now = 0.0
        var snapped = -1
        while room.phase == .playing && now < 400 {
            now += 0.1
            room.tick(now: now)
            let view = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "b")))
            XCTAssertLessThanOrEqual(view.piles.count, 2)
            let tops = view.piles.compactMap { $0.top?.rank }
            // Ben snaps every pair, quickly; Ann never does.
            if view.phase == .playing, view.flip != snapped, Set(tops).count < tops.count {
                snapped = view.flip
                try room.act(OfflineCoding.encode(Rules.Action.snap(flip: view.flip, ms: 220)), by: "b", match: 1, now: now)
            }
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.first?.playerId, "b")
    }

    // MARK: - Review additions

    func testAPairBrokenInsideTheWindowWinsNothing() throws {
        // Ann's only card is one half of the pair. Cat snaps honestly, then Ann
        // guesses: her false snap pays that very card away, so by the time the
        // window is judged there is no pair left to win.
        var state = table([([], [c(7, .hearts)]), ([c(2), c(3)], [c(7, .clubs)]), ([c(12), c(13)], [c(9)])])
        state.flip = 5
        state.flipAt = 100
        state.window = Rules.Window(flip: 5, closesAt: 100 + Rules.snapWindow)
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(.snap(flip: 5, ms: 300), by: "c", to: &state, now: 100.4, rng: &rng)
        try Rules.apply(.snap(flip: 5, ms: 50), by: "a", to: &state, now: 100.5, rng: &rng)
        XCTAssertEqual(state.out, ["a"])
        Rules.tick(&state, now: 100 + Rules.snapWindow, rng: &rng)
        XCTAssertNil(state.window)
        XCTAssertEqual(state.notice?.kind, .missed)
        XCTAssertEqual(state.snapsWon["c", default: 0], 0, "no snap is credited for an empty win")
        XCTAssertNil(state.best["c"])
        XCTAssertEqual(cards(state), 7)
    }

    func testNoViewDependsOnAnotherPlayersSecrets() throws {
        var (state, rng) = started(count: 3)
        var now = 100.0
        while state.window == nil && now < 300 {
            now += 0.1
            Rules.tick(&state, now: now, rng: &rng)
        }
        let window = try XCTUnwrap(state.window, "seed 1 makes a pair")
        try Rules.apply(.snap(flip: window.flip, ms: 250), by: "a", to: &state, now: now + 0.3, rng: &rng)
        try Rules.apply(.snap(flip: window.flip, ms: 320), by: "b", to: &state, now: now + 0.4, rng: &rng)
        XCTAssertNotNil(state.window)

        for viewer in ["a", "b", "c", nil] as [String?] {
            // Every face-down stack reordered and every other player's snap time
            // changed: what this phone is sent must not move.
            var other = state
            for index in other.seats.indices { other.seats[index].stack.reverse() }
            let claims = (other.window?.claims ?? []).map { claim in
                claim.playerId == viewer ? claim : Rules.Claim(playerId: claim.playerId, ms: 999)
            }
            other.window?.claims = claims
            XCTAssertEqual(Rules.view(of: other, for: viewer), Rules.view(of: state, for: viewer),
                           "\(viewer ?? "a spectator") can see someone else's secret")
            let json = String(decoding: try OfflineCoding.encode(Rules.view(of: state, for: viewer)), as: UTF8.self)
            XCTAssertFalse(json.contains("claims"))
            XCTAssertFalse(json.contains("\"stack\":["))
        }
    }
}
