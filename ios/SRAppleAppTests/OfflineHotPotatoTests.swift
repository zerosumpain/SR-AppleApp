import XCTest
@testable import SRAppleApp

/// Hot Potato's rules: the hidden fuse, the holder's puzzle, throwing, lives,
/// the last one standing, leaving mid-game, and what each phone may see.
final class OfflineHotPotatoTests: XCTestCase {
    private typealias Rules = HotPotatoRules

    private let players = [
        OfflinePlayer(id: "a", name: "Ann"),
        OfflinePlayer(id: "b", name: "Ben"),
        OfflinePlayer(id: "c", name: "Cat"),
    ]

    private func started(seed: UInt64 = 1, now: Double = 100, with list: [OfflinePlayer]? = nil) -> (Rules.State, OfflineRNG) {
        var rng = OfflineRNG(seed: seed)
        let state = Rules.start(players: list ?? players, now: now, rng: &rng)
        return (state, rng)
    }

    /// The holder taps the odd shape out.
    private func solve(_ state: inout Rules.State, _ rng: inout OfflineRNG, now: Double) throws {
        let holder = try XCTUnwrap(state.holder)
        try Rules.apply(.tap(task: state.task.number, choice: state.task.odd), by: holder, to: &state, now: now, rng: &rng)
    }

    /// The holder solves and throws to `target`.
    private func pass(_ state: inout Rules.State, _ rng: inout OfflineRNG, to target: String, now: Double) throws {
        try solve(&state, &rng, now: now)
        let holder = try XCTUnwrap(state.holder)
        try Rules.apply(.throwTo(pass: state.pass, target: target), by: holder, to: &state, now: now, rng: &rng)
    }

    /// A wrong choice for the current puzzle.
    private func wrongChoice(_ state: Rules.State) -> Int { (state.task.odd + 1) % Rules.taskSize }

    private func reason(_ block: () throws -> Void) -> String? {
        do { try block(); return nil } catch { return (error as? OfflineRefusal)?.reason ?? "\(error)" }
    }

    // MARK: - Setup

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self, seed: 99), [])
        XCTAssertEqual(Rules.info.id, "hot-potato")
        XCTAssertEqual(Rules.info.category, .reaction)
        XCTAssertEqual(Rules.info.minPlayers, 3)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    func testAGameStartsWithOnePotatoAndAHiddenFuse() {
        let (state, _) = started(now: 100)
        XCTAssertEqual(state.phase, .passing)
        XCTAssertEqual(state.round, 1)
        XCTAssertEqual(state.pass, 1)
        XCTAssertEqual(state.lives, ["a": 3, "b": 3, "c": 3])
        XCTAssertNotNil(state.holder)
        XCTAssertTrue(players.map(\.id).contains(state.holder!))
        XCTAssertNil(state.thrower)
        XCTAssertGreaterThanOrEqual(state.fuseEndsAt, 108)
        XCTAssertLessThanOrEqual(state.fuseEndsAt, 120)
        XCTAssertFalse(state.solved)
        XCTAssertFalse(Rules.isOver(state))
    }

    func testThePuzzleHasExactlyOneOddShape() {
        var rng = OfflineRNG(seed: 3)
        for number in 1...300 {
            let puzzle = Rules.newPuzzle(number: number, rng: &rng)
            XCTAssertEqual(puzzle.shapes.count, 4)
            let odd = puzzle.shapes[puzzle.odd]
            XCTAssertEqual(puzzle.shapes.filter { $0 == odd }.count, 1)
            let others = puzzle.shapes.enumerated().filter { $0.offset != puzzle.odd }.map(\.element)
            XCTAssertEqual(Set(others).count, 1, "the other three match")
        }
    }

    func testTheSeedDecidesHolderAndFuse() {
        XCTAssertEqual(started(seed: 4).0, started(seed: 4).0)
        let fuses = Set((1...10).map { started(seed: UInt64($0)).0.fuseEndsAt })
        XCTAssertGreaterThan(fuses.count, 1)
        let holders = Set((1...30).map { started(seed: UInt64($0)).0.holder ?? "" })
        XCTAssertEqual(holders, ["a", "b", "c"], "any player may start with it")
    }

    // MARK: - Legal moves

    func testSolvingThenThrowingPassesThePotato() throws {
        var (state, rng) = started()
        let first = try XCTUnwrap(state.holder)
        let target = players.map(\.id).first { $0 != first }!
        let puzzleBefore = state.task.number
        try solve(&state, &rng, now: 101)
        XCTAssertTrue(state.solved)
        XCTAssertEqual(state.holder, first)
        try Rules.apply(.throwTo(pass: state.pass, target: target), by: first, to: &state, now: 101.5, rng: &rng)
        XCTAssertEqual(state.holder, target)
        XCTAssertEqual(state.thrower, first)
        XCTAssertEqual(state.pass, 2)
        XCTAssertFalse(state.solved, "the catcher starts a fresh puzzle")
        XCTAssertEqual(state.task.number, puzzleBefore + 1)
        XCTAssertEqual(state.tosses[first], 1)
    }

    func testAWrongTapFumblesAndCostsTime() throws {
        var (state, rng) = started()
        let holder = try XCTUnwrap(state.holder)
        let number = state.task.number
        try Rules.apply(.tap(task: number, choice: wrongChoice(state)), by: holder, to: &state, now: 101, rng: &rng)
        XCTAssertFalse(state.solved)
        XCTAssertEqual(state.fumbles[holder], 1)
        XCTAssertEqual(state.task.number, number + 1, "a fresh puzzle after a fumble")
        XCTAssertEqual(state.lockedUntil, 101 + Rules.fumblePenalty)

        XCTAssertEqual(reason {
            try Rules.apply(.tap(task: state.task.number, choice: state.task.odd), by: holder, to: &state, now: 102, rng: &rng)
        }, "You fumbled — wait a moment.")
        XCTAssertEqual(reason {
            try Rules.apply(.tap(task: number, choice: 0), by: holder, to: &state, now: 103, rng: &rng)
        }, "That was for an old task.")
        try Rules.apply(.tap(task: state.task.number, choice: state.task.odd), by: holder, to: &state,
                        now: 101 + Rules.fumblePenalty, rng: &rng)
        XCTAssertTrue(state.solved)
    }

    // MARK: - Refusals

    func testIllegalActionsAreRefused() throws {
        var (state, rng) = started()
        let holder = try XCTUnwrap(state.holder)
        let other = players.map(\.id).first { $0 != holder }!
        let holderName = players.first { $0.id == holder }!.name
        let task = state.task.number

        XCTAssertEqual(reason {
            try Rules.apply(.tap(task: task, choice: 0), by: other, to: &state, now: 101, rng: &rng)
        }, "\(holderName) has the potato, not you.")
        XCTAssertEqual(reason {
            try Rules.apply(.tap(task: task, choice: 0), by: "zed", to: &state, now: 101, rng: &rng)
        }, "You are not in this game.")
        XCTAssertEqual(reason {
            try Rules.apply(.tap(task: task, choice: 4), by: holder, to: &state, now: 101, rng: &rng)
        }, "There's no shape there.")
        XCTAssertEqual(reason {
            try Rules.apply(.tap(task: task, choice: -1), by: holder, to: &state, now: 101, rng: &rng)
        }, "There's no shape there.")
        XCTAssertEqual(reason {
            try Rules.apply(.throwTo(pass: state.pass, target: other), by: holder, to: &state, now: 101, rng: &rng)
        }, "Tap the odd shape out first.")

        try solve(&state, &rng, now: 101)
        XCTAssertEqual(reason {
            try Rules.apply(.tap(task: task, choice: state.task.odd), by: holder, to: &state, now: 101, rng: &rng)
        }, "Done — now throw it!")
        XCTAssertEqual(reason {
            try Rules.apply(.throwTo(pass: state.pass, target: holder), by: holder, to: &state, now: 101, rng: &rng)
        }, "You can't throw it to yourself.")
        XCTAssertEqual(reason {
            try Rules.apply(.throwTo(pass: state.pass, target: "zed"), by: holder, to: &state, now: 101, rng: &rng)
        }, "That player isn't here.")
        XCTAssertEqual(reason {
            try Rules.apply(.throwTo(pass: state.pass - 1, target: other), by: holder, to: &state, now: 101, rng: &rng)
        }, "You've already passed that one on.")
        XCTAssertEqual(reason {
            try Rules.apply(.throwTo(pass: state.pass, target: other), by: holder, to: &state, now: state.fuseEndsAt, rng: &rng)
        }, "Too late — it burst!")
        // Nothing above changed the state but the one good tap.
        XCTAssertEqual(state.holder, holder)
        XCTAssertTrue(state.solved)
    }

    func testYouCannotThrowToSomeoneOut() throws {
        var (state, rng) = started()
        let holder = try XCTUnwrap(state.holder)
        let outId = players.map(\.id).first { $0 != holder }!
        state.lives[outId] = 0
        state.outOrder = [outId]
        try solve(&state, &rng, now: 101)
        XCTAssertEqual(reason {
            try Rules.apply(.throwTo(pass: state.pass, target: outId), by: holder, to: &state, now: 101, rng: &rng)
        }, "They're out — pick someone still in.")
        XCTAssertEqual(reason {
            try Rules.apply(.tap(task: state.task.number, choice: 0), by: outId, to: &state, now: 101, rng: &rng)
        }, "You are out — watch the others.")
    }

    // MARK: - The fuse

    func testTheFuseBurstsOnWhoeverHoldsIt() throws {
        var (state, rng) = started()
        let fuse = state.fuseEndsAt
        let first = try XCTUnwrap(state.holder)
        let target = players.map(\.id).first { $0 != first }!
        try pass(&state, &rng, to: target, now: 101)

        Rules.tick(&state, now: fuse - 0.01, rng: &rng)
        XCTAssertEqual(state.phase, .passing)
        Rules.tick(&state, now: fuse + 0.05, rng: &rng)
        XCTAssertEqual(state.phase, .burst)
        XCTAssertEqual(state.burstOn, target)
        XCTAssertEqual(state.lives[target], 2)
        XCTAssertEqual(state.lives[first], 3)
        XCTAssertNil(state.holder)

        let snapshot = state
        Rules.tick(&state, now: fuse + 0.05, rng: &rng)
        XCTAssertEqual(state, snapshot, "a repeated tick changes nothing")
        XCTAssertEqual(reason {
            try Rules.apply(.tap(task: state.task.number, choice: state.task.odd), by: target, to: &state, now: fuse + 1, rng: &rng)
        }, "Wait for the next potato.")

        Rules.tick(&state, now: state.burstUntil, rng: &rng)
        XCTAssertEqual(state.phase, .passing)
        XCTAssertEqual(state.round, 2)
        XCTAssertNil(state.burstOn)
        XCTAssertGreaterThanOrEqual(state.fuseEndsAt, fuse + 0.05 + Rules.burstPause + 8)
    }

    func testLosingTheLastLifePutsYouOutAndTheLastStandingWins() throws {
        var (state, rng) = started()
        state.lives = ["a": 1, "b": 1, "c": 3]
        // Burst on whoever holds it until only one player is left.
        var now = 100.0
        var guardSteps = 0
        while !Rules.isOver(state) && guardSteps < 100 {
            guardSteps += 1
            if state.phase == .passing {
                now = state.fuseEndsAt
                // Hand it to an "a"/"b" survivor first, so Cat outlasts them.
                if let holder = state.holder, holder == "c",
                   let victim = Rules.survivors(state).first(where: { $0 != "c" }) {
                    try pass(&state, &rng, to: victim, now: now - 1)
                }
            } else if state.phase == .burst {
                now = state.burstUntil
            }
            Rules.tick(&state, now: now, rng: &rng)
        }
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(Rules.winner(state), "c")
        XCTAssertEqual(state.lives["c"], 3)
        XCTAssertEqual(state.outOrder.count, 2)
        let table = Rules.standings(state)
        XCTAssertEqual(table.first?.playerId, "c")
        XCTAssertEqual(table.first?.score, 2)
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(table.last?.playerId, state.outOrder.first)
        XCTAssertEqual(Rules.view(of: state, for: "a").winner, "c")
    }

    func testANewPotatoStartsWithASurvivor() throws {
        var (state, rng) = started(with: players + [OfflinePlayer(id: "d", name: "Dan")])
        state.lives["a"] = 0
        state.outOrder = ["a"]
        state.holder = "b"
        Rules.tick(&state, now: state.fuseEndsAt, rng: &rng)
        Rules.tick(&state, now: state.burstUntil, rng: &rng)
        XCTAssertEqual(state.phase, .passing)
        XCTAssertNotEqual(state.holder, "a")
        XCTAssertTrue(["b", "c", "d"].contains(state.holder ?? ""))
    }

    // MARK: - Leaving

    func testTheHolderLeavingHandsThePotatoOn() throws {
        var (state, rng) = started(with: players + [OfflinePlayer(id: "d", name: "Dan")])
        let holder = try XCTUnwrap(state.holder)
        let fuse = state.fuseEndsAt
        Rules.playerLeft(holder, state: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.phase, .passing)
        XCTAssertNotNil(state.holder)
        XCTAssertNotEqual(state.holder, holder)
        XCTAssertEqual(state.fuseEndsAt, fuse, "the same fuse keeps burning")
        XCTAssertEqual(state.outOrder, [holder])
        XCTAssertThrowsError(try Rules.apply(.tap(task: state.task.number, choice: 0), by: holder, to: &state, now: 101, rng: &rng))
        let standing = Rules.standings(state).first { $0.playerId == holder }
        XCTAssertEqual(standing?.detail, "left")
        XCTAssertEqual(standing?.score, 0)

        // A thrower may not pick them.
        let now = try XCTUnwrap(state.holder)
        try solve(&state, &rng, now: 102)
        XCTAssertThrowsError(try Rules.apply(.throwTo(pass: state.pass, target: holder), by: now, to: &state, now: 102, rng: &rng))
    }

    func testDownToOneEndsTheGame() throws {
        var (state, rng) = started()
        Rules.playerLeft("a", state: &state, now: 101, rng: &rng)
        XCTAssertFalse(Rules.isOver(state))
        Rules.playerLeft("b", state: &state, now: 102, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        XCTAssertEqual(Rules.winner(state), "c")
        Rules.playerLeft("b", state: &state, now: 103, rng: &rng)
        XCTAssertEqual(state.outOrder, ["a", "b"], "leaving twice is a no-op")
        XCTAssertEqual(Rules.standings(state).map(\.playerId), ["c", "b", "a"])
    }

    // MARK: - Redaction

    func testOnlyTheHolderSeesThePuzzleAndNobodySeesTheFuse() throws {
        var (state, rng) = started()
        let holder = try XCTUnwrap(state.holder)
        let other = players.map(\.id).first { $0 != holder }!

        let mine = Rules.view(of: state, for: holder)
        XCTAssertEqual(mine.myTask?.shapes, state.task.shapes)
        XCTAssertEqual(mine.holder, holder)
        XCTAssertNil(Rules.view(of: state, for: other).myTask)
        XCTAssertNil(Rules.view(of: state, for: nil).myTask)
        XCTAssertEqual(Rules.view(of: state, for: other).holder, holder, "everyone sees who holds it")

        // The fuse time appears in nobody's bytes.
        let fuseText = "\(state.fuseEndsAt)"
        for id in players.map({ Optional($0.id) }) + [nil] {
            let json = String(decoding: try OfflineCoding.encode(Rules.view(of: state, for: id)), as: UTF8.self)
            XCTAssertFalse(json.contains(fuseText), "the fuse leaked to \(id ?? "a spectator")")
            XCTAssertFalse(json.contains("fuse"))
        }
        // Ticking toward the fuse changes nobody's view, so nothing hints at it.
        let before = players.map { Rules.view(of: state, for: $0.id) }
        Rules.tick(&state, now: state.fuseEndsAt - 0.5, rng: &rng)
        XCTAssertEqual(players.map { Rules.view(of: state, for: $0.id) }, before)
    }

    // MARK: - Whole games

    func testRandomGamesAlwaysFinish() throws {
        for seed in 1...150 {
            let count = 3 + Int(seed % 3)
            let list = (1...count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            var (state, rng) = started(seed: UInt64(seed), with: list)
            var choices = OfflineRNG(seed: UInt64(seed) &* 31 &+ 7)
            var now = 100.0
            var steps = 0
            var leftOne = false
            while !Rules.isOver(state) && steps < 20_000 {
                steps += 1
                now += 0.1
                if !leftOne, seed % 5 == 0, now > 130 {
                    leftOne = true
                    Rules.playerLeft(list[seed % count].id, state: &state, now: now, rng: &rng)
                }
                if state.phase == .passing, let holder = state.holder, choices.chance(0.3) {
                    let choice = choices.int(below: 4)
                    if !state.solved {
                        _ = try? Rules.apply(.tap(task: state.task.number, choice: choice), by: holder, to: &state, now: now, rng: &rng)
                    } else if let target = choices.pick(Rules.survivors(state).filter({ $0 != holder })) {
                        _ = try? Rules.apply(.throwTo(pass: state.pass, target: target), by: holder, to: &state, now: now, rng: &rng)
                    }
                }
                Rules.tick(&state, now: now, rng: &rng)
                XCTAssertLessThanOrEqual(Rules.survivors(state).count, count)
            }
            XCTAssertTrue(Rules.isOver(state), "seed \(seed) never finished")
            XCTAssertNotNil(Rules.winner(state), "seed \(seed) has a winner")
            let table = Rules.standings(state)
            XCTAssertEqual(table.count, count)
            XCTAssertEqual(table.first?.rank, 1)
            XCTAssertEqual(table.filter { $0.rank == 1 }.count, 1)
        }
    }

    func testAWholeGameThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.join(players[2], version: OfflineEnvelope.version)
        try room.choose("hot-potato")
        try room.start(seed: 11, now: 0)
        _ = room.outbox()

        var now = 0.0
        while room.phase == .playing && now < 900 {
            now += 0.1
            room.tick(now: now)
            // Whoever holds it always solves and throws to the next seat.
            for player in players {
                guard let data = room.currentView(for: player.id) else { continue }
                let view = try OfflineCoding.decode(Rules.PlayerView.self, from: data)
                guard let task = view.myTask, view.holder == player.id, view.phase == .passing else { continue }
                if !task.solved {
                    // The holder can see the shapes, so finds the odd one.
                    let odd = task.shapes.indices.first { index in
                        task.shapes.filter { $0 == task.shapes[index] }.count == 1
                    }!
                    try room.act(OfflineCoding.encode(Rules.Action.tap(task: task.number, choice: odd)),
                                 by: player.id, match: 1, now: now)
                } else {
                    let alive = view.rows.filter { !$0.out && !$0.away && $0.id != player.id }
                    if let target = alive.first {
                        try room.act(OfflineCoding.encode(Rules.Action.throwTo(pass: view.pass, target: target.id)),
                                     by: player.id, match: 1, now: now)
                    }
                }
            }
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.count, 3)
        XCTAssertEqual(room.standings?.first?.rank, 1)
    }

    // MARK: - Review additions

    func testAPotatoWithNoHolderNeverStalls() {
        var (state, rng) = started()
        state.holder = nil
        let round = state.round
        Rules.tick(&state, now: state.fuseEndsAt, rng: &rng)
        XCTAssertEqual(state.phase, .passing)
        XCTAssertEqual(state.round, round + 1)
        XCTAssertNotNil(state.holder)
    }

    func testNoViewDependsOnAnotherPlayersSecrets() throws {
        let (state, _) = started()
        let holder = try XCTUnwrap(state.holder)
        for viewer in players.map({ Optional($0.id) }) + [nil] {
            // A different fuse for everyone; a different puzzle for everyone
            // but the holder: what this phone is sent must not move.
            var other = state
            other.fuseEndsAt += 7.25
            if viewer != holder {
                other.task = Rules.Puzzle(number: state.task.number, shapes: [.heart, .heart, .shield, .heart], odd: 2)
            }
            XCTAssertEqual(Rules.view(of: other, for: viewer), Rules.view(of: state, for: viewer),
                           "\(viewer ?? "a spectator") can see a secret")
            let json = String(decoding: try OfflineCoding.encode(Rules.view(of: state, for: viewer)), as: UTF8.self)
            XCTAssertFalse(json.contains("\"odd\""), "the answer itself never travels")
        }
    }
}
