import XCTest
@testable import SRAppleApp

/// Steady Hand's rules: rounds and their timing, what a report may say, the
/// multiplier, the ring's path and the ball's maths, leaving and coming back,
/// and the end of the match.
final class OfflineSteadyHandTests: XCTestCase {
    private typealias Rules = SteadyHandRules

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

    /// Tick the round into play.
    private func play(_ state: inout Rules.State, _ rng: inout OfflineRNG) {
        Rules.tick(&state, now: state.startsAt, rng: &rng)
    }

    /// `id` reports `second` just after it ends.
    private func report(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ id: String,
                        second: Int, tenths: Int) throws {
        try Rules.apply(.report(round: state.round, second: second, tenths: tenths), by: id, to: &state,
                        now: state.startsAt + Double(second + 1) + 0.05, rng: &rng)
    }

    /// Everyone present reports a whole round at `tenths(id)` a second, then
    /// the result passes.
    private func playRound(_ state: inout Rules.State, _ rng: inout OfflineRNG,
                           tenths: (String) -> Int) throws {
        play(&state, &rng)
        for second in 0..<Rules.roundSeconds {
            for player in state.players where !state.away.contains(player.id) {
                try report(&state, &rng, player.id, second: second, tenths: tenths(player.id))
            }
        }
        XCTAssertEqual(state.phase, .result, "everyone reported every second")
        Rules.tick(&state, now: state.resultUntil, rng: &rng)
    }

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self, seed: 99), [])
        XCTAssertEqual(Rules.info.id, "steady-hand")
        XCTAssertEqual(Rules.info.category, .skill)
        XCTAssertEqual(Rules.info.minPlayers, 1)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    func testAMatchOpensOnGetReady() {
        let (state, _) = started(now: 100)
        XCTAssertEqual(state.round, 1)
        XCTAssertEqual(state.phase, .ready)
        XCTAssertEqual(state.startsAt, 100 + Rules.readyPause)
        XCTAssertEqual(state.endsAt, state.startsAt + Double(Rules.roundSeconds))
        XCTAssertEqual(state.closesAt, state.endsAt + Rules.reportGrace)
        XCTAssertEqual(state.totals, ["a": 0, "b": 0, "c": 0])
        XCTAssertEqual(state.roundPoints, ["a": 0, "b": 0, "c": 0])
        XCTAssertFalse(Rules.isOver(state))
    }

    func testTheSeedDecidesTheRing() {
        XCTAssertEqual(started(seed: 4).0.path, started(seed: 4).0.path)
        XCTAssertNotEqual(started(seed: 4).0.path, started(seed: 5).0.path)
    }

    func testTheRingStaysOnTheTableAndShrinks() {
        for seed in UInt64(1)...40 {
            var rng = OfflineRNG(seed: seed)
            var previousStart = Double.infinity
            for round in 1...Rules.rounds {
                let path = Rules.makePath(round: round, rng: &rng)
                XCTAssertLessThan(path.startRadius, previousStart, "smaller each round")
                previousStart = path.startRadius
                var t = 0.0
                while t <= Double(Rules.roundSeconds) {
                    let c = path.center(at: t)
                    let r = path.radius(at: t)
                    XCTAssertLessThanOrEqual(abs(c.x) + r, 0.921)
                    XCTAssertLessThanOrEqual(abs(c.y) + r, 0.921)
                    t += 0.25
                }
                XCTAssertEqual(path.radius(at: 0), path.startRadius, accuracy: 1e-9)
                XCTAssertEqual(path.radius(at: Double(Rules.roundSeconds)), path.endRadius, accuracy: 1e-9)
                XCTAssertEqual(path.radius(at: 999), path.endRadius, accuracy: 1e-9, "clamped after the round")
                XCTAssertLessThan(path.endRadius, path.startRadius)
            }
        }
    }

    func testInsideTheRing() {
        let path = Rules.RingPath(ampX: 0, ampY: 0, freqX: 1, freqY: 1, phaseX: 0, phaseY: 0,
                                  startRadius: 0.4, endRadius: 0.2)
        XCTAssertTrue(path.contains(x: 0.3, y: 0, at: 0))
        XCTAssertFalse(path.contains(x: 0.3, y: 0, at: 20), "the ring has shrunk")
        XCTAssertTrue(path.contains(x: 0, y: -0.2, at: 20))
        XCTAssertFalse(path.contains(x: 0.3, y: 0.3, at: 0))
    }

    func testTheBallRollsDownhillAndStopsAtTheEdge() {
        var ball = Rules.Ball()
        for _ in 0..<30 { ball.roll(tiltX: 0.5, tiltY: 0, dt: 1.0 / 60) }
        XCTAssertGreaterThan(ball.x, 0, "tilted right, rolls right")
        XCTAssertEqual(ball.y, 0, accuracy: 1e-12)

        var up = Rules.Ball()
        for _ in 0..<30 { up.roll(tiltX: 0, tiltY: 0.5, dt: 1.0 / 60) }
        XCTAssertLessThan(up.y, 0, "top tipped down: up the screen")

        var far = Rules.Ball()
        for _ in 0..<1_000 { far.roll(tiltX: -1, tiltY: -1, dt: 1.0 / 60) }
        let edge = 1 - Rules.ballRadius
        XCTAssertEqual(far.x, -edge, accuracy: 1e-9)
        XCTAssertEqual(far.y, edge, accuracy: 1e-9)

        var still = Rules.Ball(x: 0.2, y: 0.1, vx: 0, vy: 0)
        still.roll(tiltX: 0, tiltY: 0, dt: 1)
        XCTAssertEqual(still, Rules.Ball(x: 0.2, y: 0.1, vx: 0, vy: 0), "flat and still stays put")
    }

    func testTheBallFollowsAFingerWithALag() {
        var ball = Rules.Ball()
        ball.follow(toX: 0.8, toY: -0.8, dt: 1.0 / 60)
        XCTAssertGreaterThan(ball.x, 0)
        XCTAssertLessThan(ball.x, 0.8, "it lags behind")
        for _ in 0..<300 { ball.follow(toX: 0.8, toY: -0.8, dt: 1.0 / 60) }
        XCTAssertEqual(ball.x, 0.8, accuracy: 0.001)
        XCTAssertEqual(ball.y, -0.8, accuracy: 0.001)
        var edge = Rules.Ball()
        for _ in 0..<300 { edge.follow(toX: 5, toY: 5, dt: 1.0 / 60) }
        XCTAssertEqual(edge.x, 1 - Rules.ballRadius, accuracy: 1e-9, "a finger off the table cannot drag it off")
    }

    func testTheRoundRunsOnTheHostClock() {
        var (state, rng) = started()
        Rules.tick(&state, now: state.startsAt - 0.01, rng: &rng)
        XCTAssertEqual(state.phase, .ready)
        Rules.tick(&state, now: state.startsAt, rng: &rng)
        XCTAssertEqual(state.phase, .playing)
        Rules.tick(&state, now: state.endsAt, rng: &rng)
        XCTAssertEqual(state.phase, .playing, "late reports still welcome")
        Rules.tick(&state, now: state.closesAt, rng: &rng)
        XCTAssertEqual(state.phase, .result)
        let resultEnds = state.resultUntil
        XCTAssertEqual(resultEnds, state.closesAt + Rules.resultPause)
        Rules.tick(&state, now: resultEnds - 0.01, rng: &rng)
        XCTAssertEqual(state.phase, .result)
        let firstPath = state.path
        Rules.tick(&state, now: resultEnds + 0.4, rng: &rng)
        XCTAssertEqual(state.round, 2)
        XCTAssertEqual(state.phase, .ready)
        XCTAssertEqual(state.startsAt, resultEnds + 0.4 + Rules.readyPause, "copes with a late tick")
        XCTAssertNotEqual(state.path, firstPath)
        XCTAssertEqual(state.path.startRadius, 0.34)
        XCTAssertTrue(state.reported.isEmpty)
    }

    func testATickTwiceAtOneInstantChangesNothing() {
        var (state, rng) = started()
        for t in [state.startsAt, state.closesAt] {
            Rules.tick(&state, now: t, rng: &rng)
            let once = state
            Rules.tick(&state, now: t, rng: &rng)
            XCTAssertEqual(state, once)
        }
    }

    func testReportsScoreTimesTheRound() throws {
        var (state, rng) = started()
        play(&state, &rng)
        try report(&state, &rng, "a", second: 0, tenths: 10)
        try report(&state, &rng, "a", second: 1, tenths: 4)
        try report(&state, &rng, "b", second: 0, tenths: 7)
        XCTAssertEqual(state.roundPoints["a"], 14)
        XCTAssertEqual(state.totals["a"], 14)
        XCTAssertEqual(state.totals["b"], 7)
        XCTAssertEqual(state.reported["a"], [0, 1])
        XCTAssertEqual(state.tenths["a"], 14)

        // Seconds may arrive out of order (a resend after a hiccup).
        try report(&state, &rng, "c", second: 3, tenths: 1)
        try report(&state, &rng, "c", second: 2, tenths: 1)
        XCTAssertEqual(state.reported["c"], [2, 3])

        // Round three is worth three times as much.
        var (late, lateRng) = started()
        try playRound(&late, &lateRng) { _ in 0 }
        try playRound(&late, &lateRng) { _ in 0 }
        XCTAssertEqual(late.round, 3)
        play(&late, &lateRng)
        try report(&late, &lateRng, "b", second: 0, tenths: 5)
        XCTAssertEqual(late.totals["b"], 15)
        XCTAssertEqual(Rules.view(of: late, for: "b").multiplier, 3)
    }

    func testBadReportsAreRefused() throws {
        var (state, rng) = started()
        func refused(_ action: Rules.Action, by id: String = "a", now: Double, _ reason: String,
                     line: UInt = #line) {
            XCTAssertThrowsError(try Rules.apply(action, by: id, to: &state, now: now, rng: &rng), line: line) { error in
                XCTAssertEqual((error as? OfflineRefusal)?.reason, reason, line: line)
            }
        }
        refused(.report(round: 1, second: 0, tenths: 5), now: state.startsAt - 1, "The round has not started yet.")
        play(&state, &rng)
        let later = state.startsAt + 5
        refused(.report(round: 1, second: 0, tenths: 5), by: "zed", now: later, "You are not in this match.")
        refused(.report(round: 2, second: 0, tenths: 5), now: later, "That score was for another round.")
        refused(.report(round: 1, second: -1, tenths: 5), now: later, "A round has only 20 seconds.")
        refused(.report(round: 1, second: 20, tenths: 5), now: later, "A round has only 20 seconds.")
        refused(.report(round: 1, second: 0, tenths: 11), now: later, "That score cannot be right.")
        refused(.report(round: 1, second: 0, tenths: -1), now: later, "That score cannot be right.")
        refused(.report(round: 1, second: 6, tenths: 5), now: later, "That second has not finished yet.")
        // Just inside the slack is fine.
        try Rules.apply(.report(round: 1, second: 5, tenths: 5), by: "a", to: &state,
                        now: state.startsAt + 6 - Rules.earlySlack, rng: &rng)
        refused(.report(round: 1, second: 5, tenths: 9), now: later + 1, "You have already scored that second.")
        XCTAssertEqual(state.totals["a"], 5, "refusals changed nothing")

        Rules.tick(&state, now: state.closesAt, rng: &rng)
        refused(.report(round: 1, second: 19, tenths: 5), now: state.closesAt + 0.1, "This round is over.")
    }

    func testAPhoneThatGoesQuietDoesNotStallTheRound() throws {
        var (state, rng) = started()
        play(&state, &rng)
        for second in 0..<Rules.roundSeconds {
            try report(&state, &rng, "a", second: second, tenths: 10)
            try report(&state, &rng, "b", second: second, tenths: 10)
        }
        XCTAssertEqual(state.phase, .playing, "Cat has not reported")
        Rules.tick(&state, now: state.closesAt, rng: &rng)
        XCTAssertEqual(state.phase, .result)
        XCTAssertEqual(Rules.roundLeaders(state), ["a", "b"])
    }

    func testAPlayerWhoLeavesIsNotWaitedForAndMayComeBack() throws {
        var (state, rng) = started()
        play(&state, &rng)
        try report(&state, &rng, "c", second: 0, tenths: 10)
        Rules.playerLeft("c", state: &state, now: state.startsAt + 2, rng: &rng)
        Rules.playerLeft("c", state: &state, now: state.startsAt + 2, rng: &rng)
        Rules.playerLeft("zed", state: &state, now: state.startsAt + 2, rng: &rng)
        XCTAssertEqual(state.away, ["c"])
        for second in 0..<Rules.roundSeconds {
            try report(&state, &rng, "a", second: second, tenths: 3)
            try report(&state, &rng, "b", second: second, tenths: 2)
        }
        XCTAssertEqual(state.phase, .result, "Cat was not waited for")
        XCTAssertEqual(state.totals["c"], 10, "what Cat scored stands")
        XCTAssertEqual(Rules.standings(state).last?.detail, "1.0 s in the ring · left")

        // Cat's phone rejoins and reports in round two.
        Rules.tick(&state, now: state.resultUntil, rng: &rng)
        play(&state, &rng)
        try report(&state, &rng, "c", second: 0, tenths: 10)
        XCTAssertEqual(state.away, [])
        XCTAssertEqual(state.totals["c"], 30)
    }

    func testEveryoneLeavingAfterTheClockClosesTheRound() throws {
        var (state, rng) = started(players: [players[0], players[1]])
        play(&state, &rng)
        for second in 0..<Rules.roundSeconds { try report(&state, &rng, "a", second: second, tenths: 10) }
        XCTAssertEqual(state.phase, .playing)
        Rules.playerLeft("b", state: &state, now: state.endsAt + 0.2, rng: &rng)
        XCTAssertEqual(state.phase, .result)
    }

    func testThreeRoundsEndTheMatch() throws {
        var (state, rng) = started()
        let rates = ["a": 6, "b": 9, "c": 6]
        for _ in 1...Rules.rounds { try playRound(&state, &rng) { rates[$0] ?? 0 } }
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(state.round, Rules.rounds)
        // 20 s × 9 tenths × (1 + 2 + 3).
        XCTAssertEqual(state.totals["b"], 20 * 9 * 6)
        XCTAssertEqual(state.totals["a"], 20 * 6 * 6)
        XCTAssertEqual(Rules.champions(state), ["b"])
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["b", "a", "c"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 2])
        XCTAssertEqual(table.first?.detail, "54.0 s in the ring")
        let view = Rules.view(of: state, for: "a")
        XCTAssertEqual(view.champions, ["b"])
        XCTAssertEqual(view.phase, .over)

        // Nothing changes after the end.
        var after = state
        Rules.tick(&after, now: 1e6, rng: &rng)
        XCTAssertEqual(after, state)
        XCTAssertThrowsError(try Rules.apply(.report(round: 3, second: 0, tenths: 1), by: "a", to: &after, now: 1e6, rng: &rng))
    }

    func testNobodyScoringCrownsNobody() throws {
        var (state, rng) = started()
        for _ in 1...Rules.rounds { try playRound(&state, &rng) { _ in 0 } }
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(Rules.champions(state), [])
        XCTAssertEqual(Rules.standings(state).map(\.rank), [1, 1, 1])
    }

    func testOnePlayerCanPlayAlone() throws {
        var (state, rng) = started(players: [players[0]])
        for _ in 1...Rules.rounds { try playRound(&state, &rng) { _ in 10 } }
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(state.totals["a"], 1_200)
    }

    func testTheViewShowsMineAndOnlyMine() throws {
        var (state, rng) = started()
        play(&state, &rng)
        try report(&state, &rng, "a", second: 0, tenths: 8)
        try report(&state, &rng, "a", second: 1, tenths: 8)
        try report(&state, &rng, "b", second: 0, tenths: 3)

        let ann = Rules.view(of: state, for: "a")
        XCTAssertEqual(ann.myReported, [0, 1])
        XCTAssertEqual(Rules.view(of: state, for: "b").myReported, [0])
        XCTAssertEqual(Rules.view(of: state, for: "c").myReported, [])
        let spectator = Rules.view(of: state, for: nil)
        XCTAssertEqual(spectator.myReported, [])
        XCTAssertEqual(spectator.rows.map(\.total), [16, 3, 0])
        XCTAssertEqual(spectator.rows.map(\.seconds), [2, 1, 0])
        XCTAssertEqual(ann.path, state.path, "everyone chases the same ring")
        XCTAssertEqual(ann.startsAt, state.startsAt)
        XCTAssertEqual(ann.roundLeaders, [], "no leaders until the round closes")
        XCTAssertEqual(ann.champions, [])
        XCTAssertEqual(ann.roundSeconds, Rules.roundSeconds)
    }

    func testRandomMatchesAlwaysFinish() throws {
        for seed in UInt64(1)...60 {
            var rng = OfflineRNG(seed: seed)
            var chaos = OfflineRNG(seed: seed &* 31 &+ 7)
            let count = chaos.int(in: 1...5)
            let cast = (0..<count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            var state = Rules.start(players: cast, now: 0, rng: &rng)
            var now = 0.0
            var steps = 0
            while !Rules.isOver(state) && steps < 2_000 {
                steps += 1
                now += chaos.double(in: 0.05...0.6)
                Rules.tick(&state, now: now, rng: &rng)
                if chaos.chance(0.02), let gone = chaos.pick(cast) {
                    Rules.playerLeft(gone.id, state: &state, now: now, rng: &rng)
                }
                guard let who = chaos.pick(cast) else { continue }
                let action = Rules.Action.report(round: state.round + (chaos.chance(0.1) ? 1 : 0),
                                                 second: chaos.int(in: -1...20),
                                                 tenths: chaos.int(in: -1...11))
                var copy = state
                do {
                    try Rules.apply(action, by: who.id, to: &copy, now: now, rng: &rng)
                    state = copy
                } catch {
                    XCTAssertTrue(error is OfflineRefusal)
                }
                for player in cast {
                    let total = state.totals[player.id] ?? 0
                    XCTAssertGreaterThanOrEqual(total, 0)
                    XCTAssertLessThanOrEqual(total, 1_200)
                }
            }
            XCTAssertTrue(Rules.isOver(state), "seed \(seed) did not finish")
            XCTAssertEqual(Rules.standings(state).count, count)
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("steady-hand")
        try room.start(seed: 8, now: 0)
        _ = room.outbox()

        var now = 0.0
        var sent: [String: Set<String>] = [:]
        while room.phase == .playing && now < 600 {
            now += 0.1
            room.tick(now: now)
            for (id, rate) in [("a", 4), ("b", 9)] {
                let view = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: id)))
                guard view.phase == .playing else { continue }
                for second in 0..<view.roundSeconds where now >= view.startsAt + Double(second + 1) {
                    let key = "\(view.round)-\(second)"
                    guard !sent[id, default: []].contains(key) else { continue }
                    sent[id, default: []].insert(key)
                    try room.act(OfflineCoding.encode(Rules.Action.report(round: view.round, second: second, tenths: rate)),
                                 by: id, match: 1, now: now)
                }
            }
            _ = room.outbox()
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.first?.playerId, "b")
        XCTAssertEqual(room.standings?.first?.score, 20 * 9 * 6)
    }
}
