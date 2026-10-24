import XCTest
@testable import SRAppleApp

/// Whack-a-Mole's rules: the schedule of moles, who takes a mole when two go
/// for it, golden moles and bombs, the whistle, and what each phone may see.
final class OfflineWhackAMoleTests: XCTestCase {
    private typealias Rules = WhackAMoleRules

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

    /// Tick until a mole of `kind` is drawn and return its id, at its `upAt`.
    private func advance(to kind: Rules.Kind, _ state: inout Rules.State, _ rng: inout OfflineRNG) throws -> Int {
        var now = state.startsAt
        while now < state.endsAt {
            Rules.tick(&state, now: now, rng: &rng)
            if let mole = state.moles.first(where: { $0.kind == kind && !$0.resolved && $0.upAt >= now }) {
                Rules.tick(&state, now: mole.upAt, rng: &rng)
                return mole.id
            }
            now += 0.1
        }
        throw XCTSkip("no \(kind) mole with this seed")
    }

    private func mole(_ id: Int, in state: Rules.State) -> Rules.Mole? {
        state.moles.first { $0.id == id }
    }

    /// A whack `ms` after the mole showed, arriving 50 ms after that.
    private func whack(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ who: String, _ id: Int, ms: Int) throws {
        let upAt = try XCTUnwrap(mole(id, in: state)).upAt
        try Rules.apply(.whack(mole: id, ms: ms), by: who, to: &state, now: upAt + Double(ms) / 1000 + 0.05, rng: &rng)
    }

    // MARK: - Setup

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(Rules.info.id, "whack-a-mole")
        XCTAssertEqual(Rules.info.category, .reaction)
        XCTAssertEqual(Rules.info.minPlayers, 2)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    func testAMatchOpensWithALeadInAndAFullSchedule() {
        let (state, _) = started(now: 100)
        XCTAssertEqual(state.phase, .playing)
        XCTAssertEqual(state.startsAt, 103)
        XCTAssertEqual(state.endsAt, 148)
        XCTAssertEqual(state.scores, ["a": 0, "b": 0, "c": 0])
        XCTAssertTrue(state.moles.isEmpty, "the first mole is beyond the lookahead at the start")
        XCTAssertFalse(Rules.isOver(state))
    }

    func testTheSeedDecidesTheMoles() {
        func schedule(_ seed: UInt64) -> [Rules.Mole] {
            var (state, rng) = started(seed: seed)
            var all: [Rules.Mole] = []
            var now = state.startsAt
            while now < state.startsAt + 10 {
                Rules.tick(&state, now: now, rng: &rng)
                for mole in state.moles where !all.contains(where: { $0.id == mole.id }) { all.append(mole) }
                now += 0.1
            }
            return all
        }
        XCTAssertEqual(schedule(4), schedule(4))
        XCTAssertNotEqual(schedule(4).map(\.hole), schedule(5).map(\.hole))
    }

    func testTheScheduleDoesNotDependOnHowOftenTheHostTicks() {
        func moles(step: Double) -> [Int] {
            var (state, rng) = started(seed: 9)
            var seen: [Int] = []
            var now = state.startsAt
            while now < state.endsAt {
                Rules.tick(&state, now: now, rng: &rng)
                for mole in state.moles where !seen.contains(mole.id * 10 + mole.hole) { seen.append(mole.id * 10 + mole.hole) }
                now += step
            }
            return seen
        }
        XCTAssertEqual(moles(step: 0.1), moles(step: 0.13))
    }

    func testMolesStayInTheFieldAndSpeedUp() {
        var (state, rng) = started(seed: 3)
        var all: [Rules.Mole] = []
        var now = state.startsAt
        while state.phase == .playing && now < state.endsAt + 5 {
            Rules.tick(&state, now: now, rng: &rng)
            for mole in state.moles where !all.contains(where: { $0.id == mole.id }) { all.append(mole) }
            now += 0.1
        }
        XCTAssertGreaterThan(all.count, 50)
        XCTAssertTrue(all.allSatisfy { (0..<Rules.holes).contains($0.hole) })
        XCTAssertTrue(all.allSatisfy { $0.upAt >= state.startsAt && $0.downAt <= state.endsAt })
        XCTAssertEqual(all.map(\.id), Array(1...all.count), "ids count up in schedule order")
        let first = all[0], last = all[all.count - 1]
        XCTAssertEqual(first.downAt - first.upAt, Rules.upAtStart, accuracy: 0.05)
        XCTAssertLessThan(last.downAt - last.upAt, 0.7, "moles are quicker at the end")
        XCTAssertTrue(all.filter { $0.upAt - state.startsAt < Rules.specialsAfter }.allSatisfy { $0.kind == .mole })
        // Two moles up at once never share a hole.
        for (i, x) in all.enumerated() {
            for y in all[(i + 1)...] where y.upAt < x.downAt {
                XCTAssertNotEqual(x.hole, y.hole)
            }
        }
    }

    // MARK: - Whacking

    func testTheQuickestWhackTakesTheMole() throws {
        var (state, rng) = started()
        let id = try advance(to: .mole, &state, &rng)
        try whack(&state, &rng, "a", id, ms: 420)
        try whack(&state, &rng, "b", id, ms: 330)
        XCTAssertFalse(try XCTUnwrap(mole(id, in: state)).resolved, "still waiting for Cat or the window")
        try whack(&state, &rng, "c", id, ms: 500)
        let done = try XCTUnwrap(mole(id, in: state))
        XCTAssertTrue(done.resolved, "everybody has had a go")
        XCTAssertEqual(done.takenBy, "b")
        XCTAssertEqual(state.scores, ["a": 0, "b": 1, "c": 0])
        XCTAssertEqual(state.best["b"], 330)
    }

    func testAQuickerTimeThatArrivesLaterStillWins() throws {
        var (state, rng) = started()
        let id = try advance(to: .mole, &state, &rng)
        let upAt = try XCTUnwrap(mole(id, in: state)).upAt
        // Ann's message lands first; Ben's (over Bluetooth) a little later, with a lower time.
        try Rules.apply(.whack(mole: id, ms: 300), by: "a", to: &state, now: upAt + 0.35, rng: &rng)
        try Rules.apply(.whack(mole: id, ms: 260), by: "b", to: &state, now: upAt + 0.5, rng: &rng)
        Rules.tick(&state, now: upAt + 0.35 + Rules.claimWindow, rng: &rng)
        XCTAssertEqual(mole(id, in: state)?.takenBy, "b")
        XCTAssertEqual(state.scores["b"], 1)
    }

    func testTheClaimWindowClosesTheMole() throws {
        var (state, rng) = started()
        let id = try advance(to: .mole, &state, &rng)
        let upAt = try XCTUnwrap(mole(id, in: state)).upAt
        try Rules.apply(.whack(mole: id, ms: 300), by: "a", to: &state, now: upAt + 0.35, rng: &rng)
        Rules.tick(&state, now: upAt + 0.35 + Rules.claimWindow - 0.01, rng: &rng)
        XCTAssertFalse(try XCTUnwrap(mole(id, in: state)).resolved)
        Rules.tick(&state, now: upAt + 0.35 + Rules.claimWindow, rng: &rng)
        XCTAssertEqual(mole(id, in: state)?.takenBy, "a")
        XCTAssertThrowsError(try Rules.apply(.whack(mole: id, ms: 200), by: "b", to: &state, now: upAt + 0.7, rng: &rng)) { error in
            XCTAssertEqual((error as? OfflineRefusal)?.reason, "Too late — that mole has gone.")
        }
    }

    func testAnUnwhackedMoleSettlesWithNobody() throws {
        var (state, rng) = started()
        let id = try advance(to: .mole, &state, &rng)
        let closesAt = try XCTUnwrap(mole(id, in: state)).closesAt
        Rules.tick(&state, now: closesAt, rng: &rng)
        let done = try XCTUnwrap(mole(id, in: state))
        XCTAssertTrue(done.resolved)
        XCTAssertNil(done.takenBy)
        XCTAssertEqual(state.scores.values.reduce(0, +), 0)
        Rules.tick(&state, now: closesAt + Rules.keepResolved, rng: &rng)
        XCTAssertNil(mole(id, in: state), "long-gone moles leave the state")
    }

    func testAGoldenMoleIsWorthThree() throws {
        for seed in UInt64(1)...20 {
            var (state, rng) = started(seed: seed)
            guard let id = try? advance(to: .golden, &state, &rng) else { continue }
            for who in ["a", "b", "c"] { try whack(&state, &rng, who, id, ms: who == "c" ? 250 : 400) }
            XCTAssertEqual(state.scores["c"], 3)
            XCTAssertEqual(state.golden["c"], 1)
            return
        }
        XCTFail("no golden mole in twenty seeds")
    }

    func testABombCostsEveryoneWhoHitsIt() throws {
        for seed in UInt64(1)...20 {
            var (state, rng) = started(seed: seed)
            guard let id = try? advance(to: .bomb, &state, &rng) else { continue }
            try whack(&state, &rng, "a", id, ms: 300)
            try whack(&state, &rng, "b", id, ms: 450)
            XCTAssertEqual(state.scores, ["a": -2, "b": -2, "c": 0])
            XCTAssertEqual(mole(id, in: state)?.bombed, ["a", "b"])
            XCTAssertEqual(mole(id, in: state)?.resolved, false, "Cat may still hit it")
            let closesAt = try XCTUnwrap(mole(id, in: state)).closesAt
            Rules.tick(&state, now: closesAt, rng: &rng)
            XCTAssertNil(mole(id, in: state)?.takenBy, "nobody takes a bomb")
            XCTAssertEqual(state.bombs, ["a": 1, "b": 1])
            XCTAssertEqual(Rules.standings(state).first?.playerId, "c")
            return
        }
        XCTFail("no bomb in twenty seeds")
    }

    // MARK: - Refusals

    func testBadWhacksAreRefused() throws {
        var (state, rng) = started()
        let id = try advance(to: .mole, &state, &rng)
        let upAt = try XCTUnwrap(mole(id, in: state)).upAt

        func refused(_ action: Rules.Action, by who: String, at now: Double, _ reason: String, line: UInt = #line) {
            XCTAssertThrowsError(try Rules.apply(action, by: who, to: &state, now: now, rng: &rng), line: line) { error in
                XCTAssertEqual((error as? OfflineRefusal)?.reason, reason, line: line)
            }
        }
        refused(.whack(mole: id, ms: 300), by: "zed", at: upAt + 0.4, "You are not in this game.")
        refused(.whack(mole: 999, ms: 300), by: "a", at: upAt + 0.4, "That mole has gone.")
        refused(.whack(mole: id, ms: -1), by: "a", at: upAt + 0.4, "That time cannot be right.")
        refused(.whack(mole: id, ms: 60_000), by: "a", at: upAt + 0.4, "That time cannot be right.")
        refused(.whack(mole: id, ms: 40), by: "a", at: upAt + 0.1, "Too quick to be a real whack.")
        refused(.whack(mole: id, ms: 300), by: "a", at: upAt - 1, "That mole isn't up yet.")
        refused(.whack(mole: id, ms: 2_000), by: "a", at: upAt + 0.5, "Too late — that mole had dropped.")
        XCTAssertEqual(state.scores.values.reduce(0, +), 0, "no refused whack scored")

        try whack(&state, &rng, "a", id, ms: 300)
        refused(.whack(mole: id, ms: 280), by: "a", at: upAt + 0.4, "You have already whacked that one.")
    }

    func testNothingIsTakenAfterTheWhistle() throws {
        var (state, rng) = started()
        var now = state.startsAt
        while state.phase == .playing { Rules.tick(&state, now: now, rng: &rng); now += 0.1 }
        XCTAssertEqual(state.phase, .timeUp)
        XCTAssertGreaterThanOrEqual(now, state.endsAt + Rules.lateSlack)
        XCTAssertThrowsError(try Rules.apply(.whack(mole: 1, ms: 300), by: "a", to: &state, now: now, rng: &rng)) { error in
            XCTAssertEqual((error as? OfflineRefusal)?.reason, "Time's up.")
        }
        XCTAssertFalse(Rules.isOver(state), "Time's up shows first")
        Rules.tick(&state, now: state.resultUntil - 0.01, rng: &rng)
        XCTAssertFalse(Rules.isOver(state))
        Rules.tick(&state, now: state.resultUntil, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
    }

    // MARK: - Ticks, the end and leaving

    func testTickingTwiceAtOneInstantChangesNothing() {
        var (state, rng) = started()
        var now = state.startsAt
        while now < state.endsAt + 5 {
            Rules.tick(&state, now: now, rng: &rng)
            let once = state, rngOnce = rng
            Rules.tick(&state, now: now, rng: &rng)
            XCTAssertEqual(state, once)
            XCTAssertEqual(rng, rngOnce)
            now += 0.37
        }
    }

    func testTheMostPointsWinAndTiesShareARank() throws {
        var (state, _) = started()
        state.scores = ["a": 7, "b": 9, "c": 7]
        state.taken = ["a": 7, "b": 9, "c": 7]
        state.best = ["b": 210]
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["b", "a", "c"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 2])
        XCTAssertEqual(table.first?.detail, "9 moles · best 210 ms")
        XCTAssertEqual(Rules.champions(state), ["b"])
        state.scores["a"] = 9
        XCTAssertEqual(Rules.champions(state), ["a", "b"])
    }

    func testNobodyWinsWhenNobodyScored() {
        var (state, _) = started()
        state.scores = ["a": 0, "b": -2, "c": 0]
        XCTAssertEqual(Rules.champions(state), [])
    }

    func testAPlayerWhoLeavesIsNotWaitedFor() throws {
        var (state, rng) = started()
        let id = try advance(to: .mole, &state, &rng)
        try whack(&state, &rng, "a", id, ms: 300)
        try whack(&state, &rng, "b", id, ms: 350)
        XCTAssertFalse(try XCTUnwrap(mole(id, in: state)).resolved)
        Rules.playerLeft("c", state: &state, now: state.startsAt + 1, rng: &rng)
        XCTAssertEqual(mole(id, in: state)?.takenBy, "a", "Cat was the only one left to whack")
        XCTAssertThrowsError(try whack(&state, &rng, "c", id, ms: 200))
        Rules.playerLeft("c", state: &state, now: state.startsAt + 1, rng: &rng)
        XCTAssertEqual(state.away, ["c"], "leaving twice is leaving once")
        XCTAssertEqual(Rules.standings(state).first { $0.playerId == "c" }?.detail, "0 moles · left")
    }

    // MARK: - Redaction

    func testOthersWhacksStayHiddenUntilTheMoleSettles() throws {
        var (state, rng) = started()
        let id = try advance(to: .mole, &state, &rng)
        try whack(&state, &rng, "a", id, ms: 250)

        let ben = Rules.view(of: state, for: "b")
        let seen = try XCTUnwrap(ben.moles.first { $0.id == id })
        XCTAssertFalse(seen.mine)
        XCTAssertNil(seen.takenBy, "Ben cannot see who is ahead yet")
        XCTAssertTrue(Rules.view(of: state, for: "a").moles.first { $0.id == id }?.mine == true)
        XCTAssertTrue(Rules.view(of: state, for: nil).moles.allSatisfy { !$0.mine && $0.takenBy == nil })

        // Nobody's reported times ever travel in a view.
        let json = String(decoding: try OfflineCoding.encode(Rules.view(of: state, for: "b")), as: UTF8.self)
        XCTAssertFalse(json.contains("250"))
        XCTAssertFalse(json.contains("whacks"))

        try whack(&state, &rng, "b", id, ms: 300)
        try whack(&state, &rng, "c", id, ms: 350)
        XCTAssertEqual(Rules.view(of: state, for: "c").moles.first { $0.id == id }?.takenBy, "a")
        XCTAssertEqual(Rules.view(of: state, for: nil).rows.map(\.score), [1, 0, 0])
    }

    // MARK: - Whole matches

    func testRandomMatchesAlwaysFinish() throws {
        for seed in UInt64(1)...40 {
            var rng = OfflineRNG(seed: seed)
            let count = 2 + Int(seed % 4)
            let cast = (0..<count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            var state = Rules.start(players: cast, now: 0, rng: &rng)
            var bot = OfflineRNG(seed: seed &* 31)
            var now = 0.0
            while !Rules.isOver(state) && now < 120 {
                now += 0.1
                Rules.tick(&state, now: now, rng: &rng)
                if seed % 5 == 0, now > 20, !state.away.contains("p1") {
                    Rules.playerLeft("p1", state: &state, now: now, rng: &rng)
                }
                for mole in state.moles where !mole.resolved && now >= mole.upAt {
                    for player in cast where bot.chance(0.15) {
                        let ms = bot.int(in: 120...900)
                        // Bots that try anything: refusals are fine, crashes are not.
                        _ = try? Rules.apply(.whack(mole: mole.id, ms: ms), by: player.id, to: &state, now: now, rng: &rng)
                    }
                }
            }
            XCTAssertTrue(Rules.isOver(state), "seed \(seed) did not finish")
            XCTAssertEqual(Rules.standings(state).count, count)
            let points = state.taken.values.reduce(0, +) + 2 * state.golden.values.reduce(0, +) - 2 * state.bombs.values.reduce(0, +)
            XCTAssertEqual(state.scores.values.reduce(0, +), points, "seed \(seed): the score adds up")
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("whack-a-mole")
        try room.start(seed: 8, now: 0)
        _ = room.outbox()

        var now = 0.0
        var tried: Set<Int> = []
        while room.phase == .playing && now < 120 {
            now += 0.1
            room.tick(now: now)
            let due = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "b")))
            for mole in due.moles where !mole.resolved && mole.kind != .bomb && now >= mole.upAt && now < mole.downAt && !tried.contains(mole.id) {
                tried.insert(mole.id)
                // Ben is always quicker, and never touches a bomb.
                try room.act(OfflineCoding.encode(Rules.Action.whack(mole: mole.id, ms: 220)), by: "b", match: 1, now: now)
                try room.act(OfflineCoding.encode(Rules.Action.whack(mole: mole.id, ms: 310)), by: "a", match: 1, now: now)
            }
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.first?.playerId, "b")
        XCTAssertEqual(room.standings?.last?.score, 0)
    }

    // MARK: - Review additions

    func testNoViewDependsOnAnotherPlayersSecrets() throws {
        var (state, rng) = started()
        let id = try advance(to: .mole, &state, &rng)
        try whack(&state, &rng, "a", id, ms: 250)
        try whack(&state, &rng, "b", id, ms: 320)
        XCTAssertEqual(mole(id, in: state)?.resolved, false, "still waiting for a quicker time")

        for viewer in ["a", "b", "c", nil] as [String?] {
            // Every other player's reported time changed: what this phone is
            // sent must not move.
            var other = state
            for index in other.moles.indices {
                other.moles[index].whacks = other.moles[index].whacks.map { whack in
                    whack.playerId == viewer ? whack : Rules.Whack(playerId: whack.playerId, ms: 999)
                }
            }
            XCTAssertEqual(Rules.view(of: other, for: viewer), Rules.view(of: state, for: viewer),
                           "\(viewer ?? "a spectator") can see someone else's time")
            let json = String(decoding: try OfflineCoding.encode(Rules.view(of: state, for: viewer)), as: UTF8.self)
            XCTAssertFalse(json.contains("whacks"))
            XCTAssertFalse(json.contains("\"ms\""))
        }
    }
}
