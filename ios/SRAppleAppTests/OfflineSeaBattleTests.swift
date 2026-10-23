import XCTest
@testable import SRAppleApp

/// Sea Battle's rules: placing a fleet, the shooting, extra shots for hits,
/// sinking and knocking out, the clocks, leaving, and above all that nobody's
/// phone is ever sent where another player's ships are.
final class OfflineSeaBattleTests: XCTestCase {
    private typealias Rules = SeaBattleRules
    private typealias P = SeaBattleRules.Placement

    private let players = [
        OfflinePlayer(id: "a", name: "Ann"),
        OfflinePlayer(id: "b", name: "Ben"),
        OfflinePlayer(id: "c", name: "Cat"),
    ]

    /// A fixed layout: the ships lie across rows A, C, E and G from column 1.
    /// Battleship A1–A4, cruiser C1–C3, destroyer E1–E2, patrol boat G1–G2.
    private let rowsFleet = [P(bow: 0, across: true), P(bow: 16, across: true),
                             P(bow: 32, across: true), P(bow: 48, across: true)]
    /// The squares of `rowsFleet`, every one.
    private let rowsFleetCells = [0, 1, 2, 3, 16, 17, 18, 32, 33, 48, 49]

    /// A firing state with known fleets: everyone has `rowsFleet`, and Ann shoots first.
    private func firing(now: Double = 100) -> (Rules.State, OfflineRNG) {
        var rng = OfflineRNG(seed: 3)
        var state = Rules.start(players: players, now: 0, rng: &rng)
        for player in players { state.fleets[player.id] = rowsFleet }
        state.phase = .firing
        state.ready = players.map(\.id)
        state.turnPlayer = "a"
        state.turnNumber = 1
        state.turnEndsAt = now + Rules.turnSeconds
        return (state, rng)
    }

    private func fire(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ by: String, at target: String,
                      _ cell: Int, now: Double = 100) throws {
        try Rules.apply(.fire(turn: state.turnNumber, target: target, cell: cell), by: by, to: &state, now: now, rng: &rng)
    }

    private func refusal(_ body: () throws -> Void) -> String? {
        do { try body() } catch { return (error as? OfflineRefusal)?.reason ?? "not a refusal" }
        return nil
    }

    // MARK: - Setup

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self, seed: 99), [])
        XCTAssertEqual(Rules.info.id, "sea-battle")
        XCTAssertEqual(Rules.info.category, .skill)
        XCTAssertEqual(Rules.info.minPlayers, 2)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    func testAMatchOpensWithARandomLegalFleetForEveryone() {
        var rng = OfflineRNG(seed: 1)
        let state = Rules.start(players: players, now: 50, rng: &rng)
        XCTAssertEqual(state.phase, .placing)
        XCTAssertEqual(state.placeEndsAt, 50 + Rules.placeSeconds)
        XCTAssertNil(state.turnPlayer)
        for player in players {
            let fleet = try? XCTUnwrap(state.fleets[player.id])
            XCTAssertTrue(Rules.isValidFleet(fleet ?? []), "\(player.name)'s fleet")
            XCTAssertEqual(state.shots[player.id], [])
        }
        XCTAssertFalse(Rules.isOver(state))
    }

    func testRandomFleetsAreAlwaysLegalAndFollowTheSeed() {
        for seed in UInt64(1)...300 {
            var rng = OfflineRNG(seed: seed)
            XCTAssertTrue(Rules.isValidFleet(Rules.randomFleet(&rng)), "seed \(seed)")
        }
        var one = OfflineRNG(seed: 12)
        var two = OfflineRNG(seed: 12)
        XCTAssertEqual(Rules.randomFleet(&one), Rules.randomFleet(&two))
    }

    func testGeometry() {
        XCTAssertEqual(Rules.cells(bow: 0, across: true, length: 4), [0, 1, 2, 3])
        XCTAssertEqual(Rules.cells(bow: 0, across: false, length: 3), [0, 8, 16])
        XCTAssertNil(Rules.cells(bow: 5, across: true, length: 4), "F… would run off the right edge")
        XCTAssertEqual(Rules.cells(bow: 4, across: true, length: 4), [4, 5, 6, 7])
        XCTAssertNil(Rules.cells(bow: 48, across: false, length: 3), "G1 down three runs off the bottom")
        XCTAssertNil(Rules.cells(bow: 64, across: true, length: 2))
        XCTAssertNil(Rules.cells(bow: -1, across: true, length: 2))
        XCTAssertEqual(Rules.coordinate(0), "A1")
        XCTAssertEqual(Rules.coordinate(63), "H8")
        XCTAssertEqual(Rules.coordinate(11), "B4")
        XCTAssertTrue(Rules.isValidFleet(rowsFleet))
        XCTAssertFalse(Rules.isValidFleet(Array(rowsFleet.prefix(3))), "a ship short")
        XCTAssertFalse(Rules.isValidFleet([P(bow: 0, across: true), P(bow: 1, across: false),
                                           P(bow: 32, across: true), P(bow: 48, across: true)]), "overlapping")
    }

    // MARK: - Placing

    func testPlacingShufflingAndReady() throws {
        var rng = OfflineRNG(seed: 2)
        var state = Rules.start(players: players, now: 0, rng: &rng)
        try Rules.apply(.place(ships: rowsFleet), by: "a", to: &state, now: 1, rng: &rng)
        XCTAssertEqual(state.fleets["a"], rowsFleet)

        let before = state.fleets["b"]
        try Rules.apply(.shuffle, by: "b", to: &state, now: 1, rng: &rng)
        XCTAssertTrue(Rules.isValidFleet(state.fleets["b"] ?? []))
        XCTAssertNotEqual(state.fleets["b"], before)

        try Rules.apply(.ready, by: "a", to: &state, now: 2, rng: &rng)
        try Rules.apply(.ready, by: "b", to: &state, now: 2, rng: &rng)
        XCTAssertEqual(state.phase, .placing, "Cat is not ready yet")
        XCTAssertEqual(refusal { try Rules.apply(.place(ships: self.rowsFleet), by: "a", to: &state, now: 3, rng: &rng) },
                       "You have already said Ready.")
        XCTAssertEqual(refusal { try Rules.apply(.ready, by: "a", to: &state, now: 3, rng: &rng) },
                       "You have already said Ready.")
        XCTAssertEqual(refusal { try Rules.apply(.fire(turn: 0, target: "b", cell: 0), by: "a", to: &state, now: 3, rng: &rng) },
                       "The shooting hasn't started yet.")

        try Rules.apply(.ready, by: "c", to: &state, now: 4, rng: &rng)
        XCTAssertEqual(state.phase, .firing)
        XCTAssertEqual(state.turnNumber, 1)
        XCTAssertNotNil(state.turnPlayer)
        XCTAssertEqual(state.turnEndsAt, 4 + Rules.turnSeconds)
        XCTAssertEqual(refusal { try Rules.apply(.shuffle, by: "c", to: &state, now: 5, rng: &rng) },
                       "The fleets are already at sea.")
    }

    func testABadLayoutIsRefused() {
        var rng = OfflineRNG(seed: 2)
        var state = Rules.start(players: players, now: 0, rng: &rng)
        let original = state.fleets["a"]
        let offGrid = [P(bow: 6, across: true), P(bow: 16, across: true), P(bow: 32, across: true), P(bow: 48, across: true)]
        XCTAssertEqual(refusal { try Rules.apply(.place(ships: offGrid), by: "a", to: &state, now: 1, rng: &rng) },
                       "Ships must stay on the grid and must not overlap.")
        XCTAssertEqual(refusal { try Rules.apply(.place(ships: []), by: "a", to: &state, now: 1, rng: &rng) },
                       "Ships must stay on the grid and must not overlap.")
        XCTAssertEqual(state.fleets["a"], original)
        XCTAssertEqual(refusal { try Rules.apply(.ready, by: "zed", to: &state, now: 1, rng: &rng) },
                       "You are not in this game.")
    }

    func testPlacingTimesOutIntoTheShooting() {
        var rng = OfflineRNG(seed: 5)
        var state = Rules.start(players: players, now: 10, rng: &rng)
        Rules.tick(&state, now: 10 + Rules.placeSeconds - 0.1, rng: &rng)
        XCTAssertEqual(state.phase, .placing)
        Rules.tick(&state, now: 10 + Rules.placeSeconds + 0.3, rng: &rng)
        XCTAssertEqual(state.phase, .firing)
        let snapshot = state
        Rules.tick(&state, now: 10 + Rules.placeSeconds + 0.3, rng: &rng)
        XCTAssertEqual(state, snapshot, "a second tick at the same instant changes nothing")
        XCTAssertTrue(players.map(\.id).contains(state.turnPlayer ?? ""))
    }

    // MARK: - Shooting

    func testAMissPassesTheTurnInSeatOrder() throws {
        var (state, rng) = firing()
        try fire(&state, &rng, "a", at: "b", 63)
        XCTAssertEqual(state.shots["b"], [Rules.Shot(cell: 63, hit: false)])
        XCTAssertEqual(state.turnPlayer, "b")
        XCTAssertEqual(state.turnNumber, 2)
        XCTAssertEqual(state.shotsThisTurn, 0)
        try fire(&state, &rng, "b", at: "a", 63)
        XCTAssertEqual(state.turnPlayer, "c")
        try fire(&state, &rng, "c", at: "a", 62)
        XCTAssertEqual(state.turnPlayer, "a", "round the table and back")
    }

    func testAHitEarnsAnotherShotUpToThree() throws {
        var (state, rng) = firing()
        try fire(&state, &rng, "a", at: "b", 0, now: 101)
        XCTAssertEqual(state.turnPlayer, "a")
        XCTAssertEqual(state.shotsThisTurn, 1)
        XCTAssertEqual(state.turnEndsAt, 101 + Rules.turnSeconds, "a fresh clock for the extra shot")
        try fire(&state, &rng, "a", at: "c", 16)
        XCTAssertEqual(state.turnPlayer, "a")
        try fire(&state, &rng, "a", at: "b", 1)
        XCTAssertEqual(state.turnPlayer, "b", "three shots is the most in a turn, hit or not")
        XCTAssertEqual(state.hits["a"], 3)
        XCTAssertEqual(state.fired["a"], 3)
    }

    func testIllegalShotsAreRefused() throws {
        var (state, rng) = firing()
        XCTAssertEqual(refusal { try self.fire(&state, &rng, "b", at: "a", 5) }, "It's Ann's turn.")
        XCTAssertEqual(refusal { try self.fire(&state, &rng, "a", at: "a", 5) }, "You can't fire at your own fleet.")
        XCTAssertEqual(refusal { try self.fire(&state, &rng, "a", at: "zed", 5) }, "There is no such fleet.")
        XCTAssertEqual(refusal { try self.fire(&state, &rng, "a", at: "b", 64) }, "That square is off the grid.")
        XCTAssertEqual(refusal { try self.fire(&state, &rng, "a", at: "b", -1) }, "That square is off the grid.")
        XCTAssertEqual(refusal { try self.fire(&state, &rng, "zed", at: "b", 5) }, "You are not in this game.")
        XCTAssertEqual(refusal {
            try Rules.apply(.fire(turn: 7, target: "b", cell: 5), by: "a", to: &state, now: 100, rng: &rng)
        }, "That shot was for an earlier turn.")
        XCTAssertEqual(refusal { try Rules.apply(.ready, by: "a", to: &state, now: 100, rng: &rng) },
                       "The fleets are already at sea.")

        try fire(&state, &rng, "a", at: "b", 0)     // a hit: Ann goes again
        XCTAssertEqual(refusal { try self.fire(&state, &rng, "a", at: "b", 0) }, "A1 on Ben's grid has already been fired at.")
        XCTAssertEqual(state.shots["b"]?.count, 1, "a refused shot leaves no mark")
    }

    func testSinkingAShipAnnouncesItAndShowsItsSquares() throws {
        var (state, rng) = firing()
        // The patrol boat at G1–G2.
        try fire(&state, &rng, "a", at: "b", 48)
        try fire(&state, &rng, "a", at: "b", 49)
        XCTAssertEqual(state.lastShot?.sunk, "Patrol boat")
        XCTAssertEqual(state.lastShot?.hit, true)
        XCTAssertEqual(state.lastShot?.knockedOut, false)
        XCTAssertEqual(state.sank["a"], 1)
        let view = Rules.view(of: state, for: "c")
        let ben = try XCTUnwrap(view.boards.first { $0.id == "b" })
        XCTAssertEqual(ben.sunk, [Rules.Sunk(name: "Patrol boat", cells: [48, 49])])
        XCTAssertEqual(ben.shipsLeft, 3)
    }

    func testSinkingAWholeFleetKnocksAPlayerOutAndSkipsThem() throws {
        var (state, rng) = firing()
        // Sink everything of Ben's but one square, with friendly misses in between.
        state.shots["b"] = rowsFleetCells.dropLast().map { Rules.Shot(cell: $0, hit: true) }
        try fire(&state, &rng, "a", at: "b", 49)
        XCTAssertEqual(state.lastShot?.knockedOut, true)
        XCTAssertEqual(state.out, ["b"])
        XCTAssertEqual(state.turnPlayer, "a", "the knockout was a hit: Ann fires again")
        XCTAssertEqual(refusal { try self.fire(&state, &rng, "a", at: "b", 63) }, "Ben's fleet is already gone.")
        try fire(&state, &rng, "a", at: "c", 63)  // miss
        XCTAssertEqual(state.turnPlayer, "c", "Ben is skipped")
    }

    func testTheLastFleetAfloatWins() throws {
        var (state, rng) = firing(now: 200)
        state.out = ["b"]
        state.shots["c"] = rowsFleetCells.dropLast().map { Rules.Shot(cell: $0, hit: true) }
        try fire(&state, &rng, "a", at: "c", 49, now: 200)
        XCTAssertEqual(state.phase, .done)
        XCTAssertEqual(state.winner, "a")
        XCTAssertNil(state.turnPlayer)
        XCTAssertFalse(Rules.isOver(state), "the final grids stay up for a moment")
        XCTAssertEqual(refusal { try self.fire(&state, &rng, "a", at: "c", 60) }, "The battle is over.")
        Rules.tick(&state, now: 200 + Rules.donePause - 0.1, rng: &rng)
        XCTAssertFalse(Rules.isOver(state))
        Rules.tick(&state, now: 200 + Rules.donePause, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))

        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "c", "b"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(table.map(\.score), [2, 1, 0])
        XCTAssertEqual(table.first?.detail, "1 of 1 shot hit · sank 1 ship")
    }

    func testStandingsMidMatchTieTheSurvivors() {
        let (state, _) = firing()
        let table = Rules.standings(state)
        XCTAssertEqual(table.count, 3)
        XCTAssertEqual(table.map(\.rank), [1, 1, 1])
        XCTAssertEqual(Set(table.map(\.playerId)), ["a", "b", "c"])
    }

    // MARK: - Clocks

    func testARunOutTurnFiresOneShotAtRandomAndPassesOn() {
        var (state, rng) = firing(now: 100)
        Rules.tick(&state, now: 100 + Rules.turnSeconds - 0.1, rng: &rng)
        XCTAssertEqual(state.turnPlayer, "a")
        Rules.tick(&state, now: 100 + Rules.turnSeconds + 0.05, rng: &rng)
        XCTAssertEqual(state.lastShot?.shooter, "a")
        XCTAssertEqual(state.lastShot?.timedOut, true)
        XCTAssertNotEqual(state.lastShot?.target, "a")
        XCTAssertEqual(state.turnPlayer, "b", "the turn passes even on a lucky hit")
        XCTAssertEqual((state.shots["b"]?.count ?? 0) + (state.shots["c"]?.count ?? 0), 1)
        let snapshot = state
        Rules.tick(&state, now: 100 + Rules.turnSeconds + 0.05, rng: &rng)
        XCTAssertEqual(state, snapshot)
    }

    // MARK: - Leaving

    func testALeaverScuttlesTheirFleetAndLosesTheirTurn() {
        var (state, rng) = firing()
        Rules.playerLeft("a", state: &state, now: 110, rng: &rng)
        XCTAssertEqual(state.out, ["a"])
        XCTAssertEqual(state.away, ["a"])
        XCTAssertEqual(state.turnPlayer, "b")
        XCTAssertEqual(state.turnEndsAt, 110 + Rules.turnSeconds)
        XCTAssertEqual(refusal { try self.fire(&state, &rng, "a", at: "b", 5) }, "You have left this game.")
        XCTAssertEqual(refusal { try self.fire(&state, &rng, "b", at: "a", 5) }, "Ann's fleet is already gone.")
        let ann = Rules.view(of: state, for: "b").boards.first { $0.id == "a" }
        XCTAssertEqual(ann?.out, true)
        XCTAssertEqual(ann?.sunk, [], "a scuttled fleet is never revealed")

        Rules.playerLeft("c", state: &state, now: 111, rng: &rng)
        XCTAssertEqual(state.phase, .done)
        XCTAssertEqual(state.winner, "b")
    }

    func testALeaverWhilePlacingNoLongerHoldsUpTheStart() throws {
        var rng = OfflineRNG(seed: 9)
        var state = Rules.start(players: players, now: 0, rng: &rng)
        try Rules.apply(.ready, by: "a", to: &state, now: 1, rng: &rng)
        try Rules.apply(.ready, by: "b", to: &state, now: 1, rng: &rng)
        Rules.playerLeft("c", state: &state, now: 2, rng: &rng)
        XCTAssertEqual(state.phase, .firing)
        XCTAssertTrue(["a", "b"].contains(state.turnPlayer ?? ""))
    }

    func testAPhoneThatComesBackSailsItsFleetAgain() throws {
        var (state, rng) = firing()
        try fire(&state, &rng, "a", at: "b", 63)   // a miss; Ben's turn
        Rules.playerLeft("b", state: &state, now: 101, rng: &rng)
        XCTAssertEqual(state.out, ["b"])
        XCTAssertEqual(state.turnPlayer, "c")
        XCTAssertEqual(refusal { try Rules.apply(.back, by: "a", to: &state, now: 102, rng: &rng) },
                       "You are already in this battle.")
        try Rules.apply(.back, by: "b", to: &state, now: 102, rng: &rng)
        XCTAssertEqual(state.away, [])
        XCTAssertEqual(state.out, [], "the fleet was only set aside")
        XCTAssertEqual(state.fleets["b"], rowsFleet)
        XCTAssertEqual(state.turnPlayer, "c", "coming back does not take the turn")
        try fire(&state, &rng, "c", at: "b", 62)   // Cat misses Ben: Ann, then Ben
        try fire(&state, &rng, "a", at: "c", 61)
        XCTAssertEqual(state.turnPlayer, "b")

        // A fleet already sunk stays sunk.
        for cell in rowsFleetCells {
            state.shots["c", default: []].append(Rules.Shot(cell: cell, hit: true))
        }
        state.out.append("c")
        Rules.playerLeft("c", state: &state, now: 103, rng: &rng)
        try Rules.apply(.back, by: "c", to: &state, now: 104, rng: &rng)
        XCTAssertEqual(state.out, ["c"])

        state.phase = .done
        Rules.playerLeft("a", state: &state, now: 105, rng: &rng)
        XCTAssertEqual(refusal { try Rules.apply(.back, by: "a", to: &state, now: 106, rng: &rng) }, "The battle is over.")
    }

    func testAPhoneThatComesBackWhilePlacingIsWaitedForAgain() throws {
        var rng = OfflineRNG(seed: 9)
        var state = Rules.start(players: players, now: 0, rng: &rng)
        Rules.playerLeft("c", state: &state, now: 1, rng: &rng)
        try Rules.apply(.back, by: "c", to: &state, now: 2, rng: &rng)
        XCTAssertEqual(state.out, [])
        try Rules.apply(.ready, by: "a", to: &state, now: 3, rng: &rng)
        try Rules.apply(.ready, by: "b", to: &state, now: 3, rng: &rng)
        XCTAssertEqual(state.phase, .placing, "Cat is back, so the shooting waits for her")
        try Rules.apply(.ready, by: "c", to: &state, now: 4, rng: &rng)
        XCTAssertEqual(state.phase, .firing)
    }

    // MARK: - Secrets

    func testNobodySeesAnotherPlayersShips() throws {
        var rng = OfflineRNG(seed: 4)
        let state = Rules.start(players: players, now: 0, rng: &rng)
        for viewer in players {
            let view = Rules.view(of: state, for: viewer.id)
            XCTAssertEqual(view.myFleet, state.fleets[viewer.id])
            let json = String(decoding: try OfflineCoding.encode(view), as: UTF8.self)
            XCTAssertFalse(json.contains("fleets"))
            // The only layout in the view is my own; nothing else carries a bow.
            XCTAssertEqual(json.components(separatedBy: "\"bow\"").count - 1, Rules.fleetLengths.count)
        }
        let spectator = Rules.view(of: state, for: nil)
        XCTAssertNil(spectator.myFleet)
        let json = String(decoding: try OfflineCoding.encode(spectator), as: UTF8.self)
        XCTAssertFalse(json.contains("bow"))
        XCTAssertNil(Rules.view(of: state, for: "zed").myFleet, "a stranger gets no fleet")
    }

    func testOnlyShotsAndSunkShipsShowOnAnotherPlayersGrid() throws {
        var (state, rng) = firing()
        try fire(&state, &rng, "a", at: "b", 0)    // hit on the battleship
        try fire(&state, &rng, "a", at: "b", 63)   // miss
        let view = Rules.view(of: state, for: "c")
        let ben = try XCTUnwrap(view.boards.first { $0.id == "b" })
        XCTAssertEqual(ben.shots, [Rules.Shot(cell: 0, hit: true), Rules.Shot(cell: 63, hit: false)])
        XCTAssertEqual(ben.sunk, [])
        XCTAssertEqual(ben.shipsLeft, 4)
        // Cat's view mentions none of Ben's other ship squares anywhere.
        let shown = Set(view.boards.flatMap { $0.shots.map(\.cell) + $0.sunk.flatMap(\.cells) })
        XCTAssertEqual(shown, [0, 63])
    }

    // MARK: - Whole games

    /// Random play from many seeds and table sizes: every game ends, without
    /// one refused move, and the table is whole.
    func testRandomGamesAlwaysFinish() throws {
        for seed in UInt64(1)...60 {
            let count = 2 + Int(seed % 4)
            let table = (0..<count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            var rng = OfflineRNG(seed: seed)
            var chooser = OfflineRNG(seed: seed &* 31 &+ 7)
            var now = 0.0
            var state = Rules.start(players: table, now: now, rng: &rng)
            for player in table where chooser.chance(0.5) {
                try Rules.apply(.shuffle, by: player.id, to: &state, now: now, rng: &rng)
            }
            for player in table { try Rules.apply(.ready, by: player.id, to: &state, now: now, rng: &rng) }
            XCTAssertEqual(state.phase, .firing)

            var moves = 0
            while state.phase == .firing && moves < 2_000 {
                moves += 1
                now += 1
                guard let shooter = state.turnPlayer else { break }
                if chooser.chance(0.05) {
                    // Sometimes a turn just runs out.
                    now = state.turnEndsAt
                    Rules.tick(&state, now: now, rng: &rng)
                    continue
                }
                let targets = table.map(\.id).filter { $0 != shooter && !state.out.contains($0) }
                let target = try XCTUnwrap(chooser.pick(targets))
                let taken = Set((state.shots[target] ?? []).map(\.cell))
                let cell = try XCTUnwrap(chooser.pick((0..<64).filter { !taken.contains($0) }))
                try Rules.apply(.fire(turn: state.turnNumber, target: target, cell: cell), by: shooter,
                                to: &state, now: now, rng: &rng)
            }
            XCTAssertEqual(state.phase, .done, "seed \(seed)")
            XCTAssertNotNil(state.winner)
            Rules.tick(&state, now: state.doneUntil, rng: &rng)
            XCTAssertTrue(Rules.isOver(state))
            let standings = Rules.standings(state)
            XCTAssertEqual(standings.count, count)
            XCTAssertEqual(standings.first?.playerId, state.winner)
            XCTAssertEqual(standings.filter { $0.rank == 1 }.count, 1)
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("sea-battle")
        try room.start(seed: 8, now: 0)
        let first = room.outbox()
        let annPacket = try XCTUnwrap(first.compactMap { item -> OfflineViewPacket? in
            if item.to == "a", case .view(let packet) = item.message { return packet }
            return nil
        }.first)
        let view = try OfflineCoding.decode(Rules.PlayerView.self, from: annPacket.data)
        XCTAssertEqual(view.boards.map(\.name), ["Ann", "Ben"])
        XCTAssertEqual(view.phase, .placing)

        // Nobody says Ready: the placing clock runs out, then everyone fires
        // the lowest square they have not tried, row by row.
        var now = 0.0
        while room.phase == .playing && now < 3_000 {
            now += 0.5
            room.tick(now: now)
            for id in ["a", "b"] {
                guard let data = room.currentView(for: id) else { continue }
                let due = try OfflineCoding.decode(Rules.PlayerView.self, from: data)
                guard due.phase == .firing, due.turnPlayer == id else { continue }
                let other = id == "a" ? "b" : "a"
                let taken = Set(due.boards.first { $0.id == other }?.shots.map(\.cell) ?? [])
                guard let cell = (0..<64).first(where: { !taken.contains($0) }) else { continue }
                try room.act(OfflineCoding.encode(Rules.Action.fire(turn: due.turnNumber, target: other, cell: cell)),
                             by: id, match: 1, now: now)
            }
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.count, 2)
        XCTAssertEqual(room.standings?.first?.rank, 1)
    }
}
