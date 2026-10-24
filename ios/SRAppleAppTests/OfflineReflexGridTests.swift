import XCTest
@testable import SRAppleApp

/// Reflex Grid's rules: the shared run, each tile reported, impossible
/// reports refused, the close of the race, the table, and what each phone sees.
final class OfflineReflexGridTests: XCTestCase {
    private typealias Rules = ReflexGridRules

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

    /// Report tile `step` at `ms` after GO, arriving at the host just after it.
    private func tile(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ id: String,
                      step: Int, ms: Int, misses: Int = 0) throws {
        try Rules.apply(.tile(step: step, ms: ms, misses: misses), by: id, to: &state,
                        now: state.startsAt + Double(ms) / 1000 + 0.05, rng: &rng)
    }

    /// Clear the whole run, `perTile` ms a tile.
    private func finish(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ id: String,
                        perTile: Int, misses: Int = 0) throws {
        for step in 1...Rules.runLength {
            try tile(&state, &rng, id, step: step, ms: step * perTile, misses: step == Rules.runLength ? misses : 0)
        }
    }

    private func reason(_ block: () throws -> Void) -> String? {
        do { try block(); return nil } catch { return (error as? OfflineRefusal)?.reason }
    }

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(Rules.info.id, "reflex-grid")
        XCTAssertEqual(Rules.info.category, .reaction)
        XCTAssertEqual(Rules.info.minPlayers, 1)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    func testARaceOpensWithACountdownAndOneSharedRun() {
        let (state, _) = started(now: 100)
        XCTAssertEqual(state.phase, .racing)
        XCTAssertEqual(state.startsAt, 100 + Rules.leadIn)
        XCTAssertEqual(state.endsAt, state.startsAt + Rules.raceLimit)
        XCTAssertEqual(state.sequence.count, Rules.runLength)
        XCTAssertTrue(state.sequence.allSatisfy { (0..<Rules.cellCount).contains($0) })
        for index in 1..<state.sequence.count {
            XCTAssertNotEqual(state.sequence[index], state.sequence[index - 1], "the lit tile always moves")
        }
        XCTAssertEqual(state.runs.count, 3)
        XCTAssertTrue(state.runs.values.allSatisfy { $0 == Rules.Run() })
        // Everyone sees the same run.
        let runs = ["a", "b", "c", nil].map { Rules.view(of: state, for: $0).sequence }
        XCTAssertTrue(runs.allSatisfy { $0 == state.sequence })
        XCTAssertFalse(Rules.isOver(state))
    }

    func testTheSeedDecidesTheRun() {
        XCTAssertEqual(started(seed: 4).0.sequence, started(seed: 4).0.sequence)
        XCTAssertNotEqual(started(seed: 4).0.sequence, started(seed: 5).0.sequence)
        for seed in UInt64(0)..<200 {
            let sequence = started(seed: seed).0.sequence
            for index in 1..<sequence.count { XCTAssertNotEqual(sequence[index], sequence[index - 1]) }
        }
    }

    func testEachTileMovesTheBar() throws {
        var (state, rng) = started()
        try tile(&state, &rng, "a", step: 1, ms: 400)
        try tile(&state, &rng, "a", step: 2, ms: 750, misses: 1)
        XCTAssertEqual(state.runs["a"], Rules.Run(cleared: 2, ms: 750, misses: 1))
        XCTAssertEqual(state.runs["a"]?.totalMs, 750 + Rules.penaltyMs)
        XCTAssertEqual(state.phase, .racing)
        let ben = Rules.view(of: state, for: "b")
        XCTAssertEqual(ben.rows.first { $0.id == "a" }?.cleared, 2)
        XCTAssertEqual(ben.rows.first { $0.id == "a" }?.misses, 1)
    }

    func testASkippedReportIsAcceptedButAnOldOneIsNot() throws {
        var (state, rng) = started()
        try tile(&state, &rng, "a", step: 1, ms: 300)
        // Tile 2's report never needs to arrive: tile 3 carries the progress.
        try tile(&state, &rng, "a", step: 3, ms: 900)
        XCTAssertEqual(state.runs["a"]?.cleared, 3)
        XCTAssertEqual(reason { try tile(&state, &rng, "a", step: 2, ms: 950) }, "You have already cleared that tile.")
        XCTAssertEqual(reason { try tile(&state, &rng, "a", step: 3, ms: 950) }, "You have already cleared that tile.")
    }

    func testImpossibleReportsAreRefused() throws {
        var (state, rng) = started()
        XCTAssertEqual(reason { try tile(&state, &rng, "zed", step: 1, ms: 300) }, "You are not in this race.")
        XCTAssertEqual(reason { try tile(&state, &rng, "a", step: 0, ms: 300) }, "There is no such tile.")
        XCTAssertEqual(reason { try tile(&state, &rng, "a", step: Rules.runLength + 1, ms: 5000) }, "There is no such tile.")
        XCTAssertEqual(reason { try tile(&state, &rng, "a", step: 1, ms: -5) }, "That time cannot be right.")
        XCTAssertEqual(reason { try tile(&state, &rng, "a", step: 5, ms: 300) }, "That time cannot be right.", "under 100 ms a tile")
        XCTAssertEqual(reason { try tile(&state, &rng, "a", step: 1, ms: 300, misses: -1) }, "That miss count cannot be right.")
        XCTAssertEqual(reason { try tile(&state, &rng, "a", step: 1, ms: 300, misses: 5000) }, "That miss count cannot be right.")
        // Before GO (by more than the clock slack) nothing counts.
        XCTAssertEqual(reason {
            try Rules.apply(.tile(step: 1, ms: 300, misses: 0), by: "a", to: &state, now: state.startsAt - 2, rng: &rng)
        }, "Wait for GO.")
        // A stopwatch that has run longer than the race has: the phone started early.
        XCTAssertEqual(reason {
            try Rules.apply(.tile(step: 1, ms: 5000, misses: 0), by: "a", to: &state, now: state.startsAt + 1, rng: &rng)
        }, "That time cannot be right.")

        try tile(&state, &rng, "a", step: 2, ms: 800, misses: 2)
        XCTAssertEqual(reason { try tile(&state, &rng, "a", step: 3, ms: 700, misses: 2) }, "That time cannot be right.", "time runs forward")
        XCTAssertEqual(reason { try tile(&state, &rng, "a", step: 3, ms: 1100, misses: 1) }, "That miss count cannot be right.", "misses never go away")
        XCTAssertEqual(state.runs["a"], Rules.Run(cleared: 2, ms: 800, misses: 2), "refusals leave the run alone")
    }

    func testNothingMoreOnceFinishedOrGone() throws {
        var (state, rng) = started()
        try finish(&state, &rng, "a", perTile: 300)
        XCTAssertEqual(reason { try tile(&state, &rng, "a", step: 20, ms: 6500) }, "You have already finished.")
        Rules.playerLeft("b", state: &state, now: state.startsAt + 7, rng: &rng)
        XCTAssertEqual(reason { try tile(&state, &rng, "b", step: 1, ms: 300) }, "You have left this race.")
    }

    func testTheRaceClosesWhenEveryoneFinishes() throws {
        var (state, rng) = started()
        try finish(&state, &rng, "a", perTile: 400, misses: 1)   // 8000 + 500
        try finish(&state, &rng, "b", perTile: 420)              // 8400
        XCTAssertEqual(state.phase, .racing, "still waiting for Cat")
        try finish(&state, &rng, "c", perTile: 500)              // 10000
        XCTAssertEqual(state.phase, .result)
        XCTAssertEqual(Rules.winners(state), ["b"], "Ann's miss cost her the race")
        XCTAssertEqual(Rules.view(of: state, for: nil).winners, ["b"])

        let closes = state.resultUntil
        Rules.tick(&state, now: closes - 0.1, rng: &rng)
        XCTAssertFalse(Rules.isOver(state))
        Rules.tick(&state, now: closes, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))

        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["b", "a", "c"])
        XCTAssertEqual(table.map(\.score), [8400, 8500, 10000])
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(table[0].detail, "8.40 s")
        XCTAssertEqual(table[1].detail, "8.50 s · 1 miss")
    }

    func testTheClockClosesTheRaceOnStragglers() throws {
        var (state, rng) = started()
        try finish(&state, &rng, "a", perTile: 300)
        try tile(&state, &rng, "b", step: 1, ms: 400)
        try tile(&state, &rng, "b", step: 2, ms: 800)
        Rules.tick(&state, now: state.endsAt + Rules.clockSlack - 0.1, rng: &rng)
        XCTAssertEqual(state.phase, .racing)
        Rules.tick(&state, now: state.endsAt + Rules.clockSlack, rng: &rng)
        XCTAssertEqual(state.phase, .result)
        XCTAssertEqual(reason { try tile(&state, &rng, "c", step: 1, ms: 400) }, "The race is over.")

        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "b", "c"], "more tiles beats fewer among those who did not finish")
        XCTAssertEqual(table[1].detail, "did not finish · 2 of 20")
        XCTAssertEqual(table[2].detail, "did not finish · 0 of 20")
        XCTAssertTrue(table[0].score < table[1].score && table[1].score < table[2].score)
    }

    func testATieSharesFirstPlace() throws {
        var (state, rng) = started()
        try finish(&state, &rng, "a", perTile: 300)
        try finish(&state, &rng, "b", perTile: 300)
        try finish(&state, &rng, "c", perTile: 310)
        XCTAssertEqual(Rules.winners(state), ["a", "b"])
        XCTAssertEqual(Rules.standings(state).map(\.rank), [1, 1, 3])
    }

    func testNobodyWinsIfNobodyFinishes() {
        var (state, rng) = started()
        Rules.tick(&state, now: state.endsAt + 5, rng: &rng)
        XCTAssertEqual(state.phase, .result)
        XCTAssertEqual(Rules.winners(state), [])
        XCTAssertEqual(Rules.standings(state).map(\.rank), [1, 1, 1])
    }

    func testAPlayerWhoLeavesIsNotWaitedFor() throws {
        var (state, rng) = started()
        try finish(&state, &rng, "a", perTile: 300)
        try finish(&state, &rng, "b", perTile: 350)
        try tile(&state, &rng, "c", step: 1, ms: 400)
        Rules.playerLeft("c", state: &state, now: state.startsAt + 8, rng: &rng)
        XCTAssertEqual(state.phase, .result, "Cat was the only one still racing")
        Rules.playerLeft("c", state: &state, now: state.startsAt + 8, rng: &rng)
        XCTAssertEqual(state.away, ["c"], "leaving twice changes nothing")
        Rules.playerLeft("zed", state: &state, now: state.startsAt + 8, rng: &rng)
        XCTAssertEqual(state.away, ["c"])
        let cat = Rules.standings(state).last
        XCTAssertEqual(cat?.playerId, "c")
        XCTAssertEqual(cat?.detail, "did not finish · 1 of 20 · left")
    }

    func testAFinisherWhoLeavesKeepsTheirTime() throws {
        var (state, rng) = started()
        try finish(&state, &rng, "a", perTile: 300)
        Rules.playerLeft("a", state: &state, now: state.startsAt + 7, rng: &rng)
        try finish(&state, &rng, "b", perTile: 350)
        try finish(&state, &rng, "c", perTile: 400)
        XCTAssertEqual(Rules.winners(state), ["a"])
        XCTAssertEqual(Rules.standings(state).first?.detail, "6.00 s · left")
    }

    func testOthersRunningTimesStayPrivateUntilTheyFinish() throws {
        var (state, rng) = started()
        try tile(&state, &rng, "a", step: 3, ms: 987)
        let ben = Rules.view(of: state, for: "b")
        let annRow = try XCTUnwrap(ben.rows.first { $0.id == "a" })
        XCTAssertEqual(annRow.cleared, 3)
        XCTAssertNil(annRow.totalMs, "Ben sees Ann's bar, not her stopwatch")
        XCTAssertEqual(ben.mine, Rules.Run())
        XCTAssertFalse(String(decoding: try OfflineCoding.encode(ben), as: UTF8.self).contains("987"))
        XCTAssertEqual(Rules.view(of: state, for: "a").mine?.ms, 987, "Ann sees her own")

        let spectator = Rules.view(of: state, for: nil)
        XCTAssertNil(spectator.mine)
        XCTAssertFalse(String(decoding: try OfflineCoding.encode(spectator), as: UTF8.self).contains("987"))
        XCTAssertNil(Rules.view(of: state, for: "zed").mine, "a stranger has no run")

        for step in 4...Rules.runLength { try tile(&state, &rng, "a", step: step, ms: step * 330) }
        XCTAssertEqual(Rules.view(of: state, for: "b").rows.first { $0.id == "a" }?.totalMs, 6600)
        XCTAssertEqual(Rules.view(of: state, for: "b").winners, [], "no winner while the race runs")
    }

    func testTickIsIdempotentAndHarmlessBeforeTheDeadline() throws {
        var (state, rng) = started()
        try tile(&state, &rng, "a", step: 1, ms: 300)
        let before = state
        Rules.tick(&state, now: state.startsAt + 2, rng: &rng)
        Rules.tick(&state, now: state.startsAt + 2, rng: &rng)
        XCTAssertEqual(state, before)
        Rules.tick(&state, now: state.endsAt + 30, rng: &rng)    // very late
        Rules.tick(&state, now: state.endsAt + 30, rng: &rng)
        XCTAssertEqual(state.phase, .result)
        let closed = state
        Rules.tick(&state, now: state.endsAt + 30, rng: &rng)
        XCTAssertEqual(state, closed)
    }

    func testOnePlayerCanRaceAlone() throws {
        var (state, rng) = started(players: [players[0]])
        try finish(&state, &rng, "a", perTile: 250, misses: 2)
        XCTAssertEqual(state.phase, .result)
        XCTAssertEqual(Rules.standings(state).first?.score, 6000)
    }

    func testRandomRacesAlwaysFinish() throws {
        for seed in UInt64(1)...150 {
            var rng = OfflineRNG(seed: seed)
            let count = 1 + Int(seed % 5)
            let field = (0..<count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            var state = Rules.start(players: field, now: 0, rng: &rng)
            var dice = OfflineRNG(seed: seed &* 7919)
            var clocks = [String: Int]()
            var now = state.startsAt
            var guardSteps = 0
            while !Rules.isOver(state) && guardSteps < 5000 {
                guardSteps += 1
                now += 0.1
                for player in field where state.phase == .racing && !state.away.contains(player.id) {
                    let run = state.runs[player.id] ?? Rules.Run()
                    guard !run.finished, dice.chance(0.6) else { continue }
                    if dice.chance(0.01) {
                        Rules.playerLeft(player.id, state: &state, now: now, rng: &rng)
                        continue
                    }
                    let elapsed = clocks[player.id, default: 0] + dice.int(in: 120...900)
                    let ms = min(elapsed, Int((now - state.startsAt) * 1000))
                    guard ms >= (run.cleared + 1) * Rules.minTileMs else { continue }
                    clocks[player.id] = ms
                    let misses = run.misses + (dice.chance(0.1) ? 1 : 0)
                    try Rules.apply(.tile(step: run.cleared + 1, ms: max(ms, run.ms), misses: misses),
                                    by: player.id, to: &state, now: now, rng: &rng)
                }
                Rules.tick(&state, now: now, rng: &rng)
            }
            XCTAssertTrue(Rules.isOver(state), "seed \(seed)")
            XCTAssertEqual(Set(Rules.standings(state).map(\.playerId)), Set(field.map(\.id)))
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("reflex-grid")
        try room.start(seed: 8, now: 0)
        _ = room.outbox()

        var now = 0.0
        while room.phase == .playing && now < 120 {
            now += 0.1
            room.tick(now: now)
            for (id, perTile) in [("a", 400), ("b", 300)] {
                let view = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: id)))
                guard view.phase == .racing, let mine = view.mine, !mine.finished else { continue }
                let step = mine.cleared + 1
                let ms = step * perTile
                guard now >= view.startsAt + Double(ms) / 1000 else { continue }
                try room.act(OfflineCoding.encode(Rules.Action.tile(step: step, ms: ms, misses: 0)), by: id, match: 1, now: now)
            }
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.map(\.playerId), ["b", "a"])
        XCTAssertEqual(room.standings?.first?.score, 6000)
    }

    // MARK: - Review additions

    func testAFinisherAlwaysRanksAboveSomeoneWhoDidNotFinish() throws {
        // Ann crawls home with a pile of misses: 58 s + 10 × 0.5 s = 63 s.
        // Ben gets to 19 of 20. Finishing still beats not finishing.
        var (state, rng) = started()
        try finish(&state, &rng, "a", perTile: 2_900, misses: 10)
        XCTAssertEqual(state.runs["a"]?.totalMs, 63_000)
        try tile(&state, &rng, "b", step: 19, ms: 19 * 500)
        Rules.tick(&state, now: state.endsAt + Rules.clockSlack, rng: &rng)
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "b", "c"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertGreaterThan(Rules.score(Rules.Run(cleared: 19, ms: 1_000, misses: 0)),
                             Rules.Run(cleared: Rules.runLength, ms: Int(Rules.raceLimit * 1000),
                                       misses: Rules.maxMisses).totalMs)
    }

    func testNoViewDependsOnAnotherPlayersSecrets() throws {
        var (state, rng) = started()
        try tile(&state, &rng, "a", step: 3, ms: 987)
        try tile(&state, &rng, "b", step: 5, ms: 1_543)
        for viewer in ["a", "b", "c", nil] as [String?] {
            // Every other unfinished racer's stopwatch changed: what this phone
            // is sent must not move.
            var other = state
            for (id, run) in other.runs where id != viewer && !run.finished {
                other.runs[id] = Rules.Run(cleared: run.cleared, ms: run.ms + 4_321, misses: run.misses)
            }
            XCTAssertEqual(Rules.view(of: other, for: viewer), Rules.view(of: state, for: viewer),
                           "\(viewer ?? "a spectator") can see someone else's running time")
        }
    }
}
