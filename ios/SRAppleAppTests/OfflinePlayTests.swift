import XCTest
@testable import SRAppleApp

/// Playing with no internet, beyond any one game's rules: finding a room on
/// two links at once, judging a connection, getting back in after a drop,
/// computer players for solo play, and the results that wait to be synced.
final class OfflinePlayTests: XCTestCase {

    // MARK: - Finding rooms

    func testARoomSeenOnBothLinksIsOneRowWithWiFiFirst() {
        let merged = OfflineDiscovery.merge([
            .nearby: [OfflineFoundHost(id: "r1", name: "Sam's game"), OfflineFoundHost(id: "r2", name: "Ali's game")],
            .hotspot: [OfflineFoundHost(id: "r1", name: "Sam's game (2)")],
        ])
        XCTAssertEqual(merged.map(\.id), ["r2", "r1"], "sorted by name")
        let sam = merged.first { $0.id == "r1" }
        XCTAssertEqual(sam?.via, [.hotspot, .nearby])
        XCTAssertEqual(sam?.name, "Sam's game (2)", "the preferred link's name")
        XCTAssertEqual(merged.first { $0.id == "r2" }?.via, [.nearby])
    }

    func testRoutesFollowWhatWasSeen() {
        XCTAssertEqual(OfflineDiscovery.routes(for: OfflineFoundHost(id: "a", name: "A", via: [.nearby])), [.nearby])
        XCTAssertEqual(OfflineDiscovery.routes(for: OfflineFoundHost(id: "a", name: "A", via: [.nearby, .hotspot])),
                       [.hotspot, .nearby])
        // Nothing known: try both.
        XCTAssertEqual(OfflineDiscovery.routes(for: OfflineFoundHost(id: "a", name: "A")), [.hotspot, .nearby])
    }

    func testARoomKeyIsEightHexDigits() {
        for seed: UInt64 in [0, 1, 0xFFFF_FFFF_FFFF_FFFF, 0xABCDEF] {
            let key = OfflineDiscovery.roomKey(seed: seed)
            XCTAssertEqual(key.count, 8, key)
            XCTAssertTrue(key.allSatisfy { $0.isHexDigit }, key)
        }
        XCTAssertEqual(OfflineDiscovery.roomKey(seed: 0xABCDEF), "00abcdef")
    }

    func testATXTRecordRoundTripsAndSaysNothingTooLong() {
        let data = OfflineTXT.encode(["rid": "00abcdef", "v": "1"])
        XCTAssertEqual([UInt8](data).first, 12, "rid=00abcdef is 12 bytes")
        XCTAssertEqual(OfflineTXT.decode(data), ["rid": "00abcdef", "v": "1"])
        XCTAssertEqual(OfflineTXT.encode([:]), Data([0]))
        let long = OfflineTXT.encode(["k": String(repeating: "x", count: 300), "v": "1"])
        XCTAssertEqual(OfflineTXT.decode(long), ["v": "1"])
    }

    // MARK: - Connection health

    func testHealthComesFromWhenAPhoneWasLastHeard() {
        XCTAssertEqual(OfflinePeerHealth.of(lastHeard: 100, now: 103, present: true), .good)
        XCTAssertEqual(OfflinePeerHealth.of(lastHeard: 100, now: 112.7, present: true), .quiet(12))
        XCTAssertEqual(OfflinePeerHealth.of(lastHeard: 100, now: 101, present: false), .away)
        XCTAssertEqual(OfflinePeerHealth.of(lastHeard: nil, now: 101, present: true), .quiet(0))
        XCTAssertEqual(OfflinePeerHealth.quiet(12).label, "Quiet 12 s")
        XCTAssertEqual(OfflinePeerHealth.quiet(0).label, "Connecting")
        XCTAssertNil(OfflinePeerHealth.local.label)
        XCTAssertFalse(OfflinePeerHealth.good.isTrouble)
        XCTAssertTrue(OfflinePeerHealth.away.isTrouble)
    }

    func testTheHostsTestSaysWhoIsNotAnswering() {
        XCTAssertTrue(OfflinePeerHealth.summary([]).hasPrefix("Nobody has joined yet"))
        XCTAssertEqual(OfflinePeerHealth.summary([("Ali", .good), ("Bo", .good)]),
                       "All 2 phones answered in the last few seconds.")
        XCTAssertEqual(OfflinePeerHealth.summary([("Ali", .good)]), "Ali's phone answered in the last few seconds.")
        let trouble = OfflinePeerHealth.summary([("Ali", .good), ("Bo", .quiet(9)), ("Cy", .away)])
        XCTAssertTrue(trouble.contains("Bo has been quiet for 9 s"))
        XCTAssertTrue(trouble.contains("Cy is out of reach"))
        XCTAssertFalse(trouble.contains("Ali"))
    }

    func testARoundTripReadsAsASentence() {
        XCTAssertTrue(OfflineRoundTrip.sentence(ms: 30).contains("strong"))
        XCTAssertTrue(OfflineRoundTrip.sentence(ms: 120).contains("fine"))
        XCTAssertTrue(OfflineRoundTrip.sentence(ms: 400).contains("slow"))
        XCTAssertTrue(OfflineRoundTrip.sentence(ms: nil).hasPrefix("No answer"))
    }

    func testADroppedGuestLooksForItsOwnRoomAndThenGivesUp() {
        let back = OfflineReconnect(roomId: "r1", hostName: "Sam", since: 100)
        XCTAssertNil(back.match(in: [OfflineFoundHost(id: "r2", name: "Other")]))
        XCTAssertEqual(back.match(in: [OfflineFoundHost(id: "r2", name: "Other"), OfflineFoundHost(id: "r1", name: "Sam's game")])?.id, "r1")
        XCTAssertFalse(back.givenUp(now: 100 + OfflineReconnect.patience - 1))
        XCTAssertTrue(back.givenUp(now: 100 + OfflineReconnect.patience))
    }

    // MARK: - The room with computer players

    private let host = OfflinePlayer(id: "h", name: "Host")

    private func room() -> OfflineRoom {
        OfflineRoom(host: host, roomName: "Host's game",
                    games: [OfflineGameEntry(withBot: FourInARowRules.self), OfflineGameEntry(CodeBreakerRules.self),
                            OfflineGameEntry(withBot: CrazyEightsRules.self)],
                    roomKey: "0000beef")
    }

    func testTheLobbyCarriesTheRoomKey() {
        var room = room()
        XCTAssertEqual(room.lobby.roomKey, "0000beef")
        let lobby = room.outbox().compactMap { item -> OfflineLobby? in
            if case .lobby(let lobby) = item.message { return lobby }
            return nil
        }.first
        XCTAssertEqual(lobby?.roomKey, "0000beef")
    }

    func testABotSitsOnlyAtAGameThatHasOne() throws {
        var room = room()
        XCTAssertThrowsError(try room.addBot(), "no game chosen")
        try room.choose("code-breaker")
        XCTAssertNotNil(room.addBotProblem)
        XCTAssertThrowsError(try room.addBot())
        try room.choose("four-in-a-row")
        XCTAssertNil(room.addBotProblem)
        let id = try room.addBot()
        XCTAssertEqual(room.bots.map(\.id), [id])
        XCTAssertEqual(room.bots.first?.name, "Robo")
        XCTAssertNil(room.startProblem, "a bot makes two")
        // Switching to a game with no bot stands the bot down.
        try room.choose("code-breaker")
        XCTAssertTrue(room.bots.isEmpty)
    }

    func testAPersonTakesABotsSeatInAFullRoom() throws {
        var room = room()
        try room.choose("crazy-eights")
        for _ in 0..<4 { try room.addBot() }
        XCTAssertEqual(room.players.count, OfflineRoom.capacity)
        XCTAssertNotNil(room.addBotProblem)
        try room.join(OfflinePlayer(id: "g1", name: "Ali"), version: OfflineEnvelope.version)
        XCTAssertEqual(room.players.count, OfflineRoom.capacity)
        XCTAssertEqual(room.bots.count, 3)
        XCTAssertTrue(room.players.contains { $0.id == "g1" })
    }

    func testNothingIsSentToABot() throws {
        var room = room()
        try room.choose("four-in-a-row")
        let bot = try room.addBot()
        try room.start(seed: 3, now: 1_000)
        let sentTo = Set(room.outbox().map(\.to))
        XCTAssertEqual(sentTo, ["h"])
        XCTAssertFalse(sentTo.contains(bot))
    }

    /// A whole solo game of Four in a Row: the host drops in random columns,
    /// the bot answers after thinking, and the match ends with a table.
    func testASoloGameAgainstTheBotPlaysToTheEnd() throws {
        var room = room()
        try room.choose("four-in-a-row")
        let bot = try room.addBot()
        try room.start(seed: 11, now: 1_000)
        var rng = OfflineRNG(seed: 5)
        var now = 1_000.0
        var botMoves = 0
        var lastTurnPlayer: String?
        for _ in 0..<4_000 where room.phase == .playing {
            now += 0.1
            room.tick(now: now)
            _ = room.outbox()
            guard let data = room.currentView(for: "h"),
                  let view = try? OfflineCoding.decode(FourInARowRules.PlayerView.self, from: data) else { continue }
            if view.turnPlayer != lastTurnPlayer {
                if lastTurnPlayer == bot { botMoves += 1 }
                lastTurnPlayer = view.turnPlayer
            }
            if view.turnPlayer == "h" {
                let open = (0..<view.cols).filter {
                    FourInARowRules.landingRow(column: $0, cols: view.cols, rows: view.rows, grid: view.grid) != nil
                }
                if let column = rng.pick(open) {
                    try? room.act(OfflineCoding.encode(FourInARowRules.Action.drop(turn: view.turnNumber, column: column)),
                                  by: "h", match: room.matchNumber, now: now)
                }
            }
        }
        XCTAssertEqual(room.phase, .finished, "the match finished")
        XCTAssertGreaterThan(botMoves, 2, "the bot moved by itself")
        XCTAssertEqual(Set(room.standings?.map(\.playerId) ?? []), ["h", bot])
    }

    func testABotWaitsBeforeItMoves() throws {
        var room = room()
        try room.choose("four-in-a-row")
        _ = try room.addBot()
        // Seed 2 gives the bot the first turn.
        var seed: UInt64 = 1
        var view: FourInARowRules.PlayerView?
        repeat {
            seed += 1
            room.backToLobby()
            if room.phase != .lobby { room.endMatch(); room.backToLobby() }
            try room.start(seed: seed, now: 1_000)
            view = try room.currentView(for: "h").map { try OfflineCoding.decode(FourInARowRules.PlayerView.self, from: $0) }
        } while view?.turnPlayer == "h" && seed < 50
        XCTAssertNotEqual(view?.turnPlayer, "h")
        room.tick(now: 1_000.1)
        room.tick(now: 1_000.5)
        let early = try OfflineCoding.decode(FourInARowRules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "h")))
        XCTAssertNil(early.lastMove, "still thinking")
        room.tick(now: 1_000.1 + OfflineRoom.botThink + 0.05)
        let after = try OfflineCoding.decode(FourInARowRules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "h")))
        XCTAssertNotNil(after.lastMove, "moved once it had thought")
    }

    // MARK: - The bots' choices

    private func fourInARow(_ players: Int = 2) -> FourInARowRules.State {
        var rng = OfflineRNG(seed: 1)
        let seats = (0..<players).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
        var state = FourInARowRules.start(players: seats, now: 0, rng: &rng)
        state.turn = 1
        return state
    }

    private func place(_ state: inout FourInARowRules.State, seat: Int, column: Int) {
        guard let row = FourInARowRules.landingRow(column: column, in: state) else { return }
        state.grid[row * state.cols + column] = seat
    }

    func testFourInARowsBotTakesAWin() {
        var state = fourInARow()
        for _ in 0..<3 { place(&state, seat: 1, column: 0) }
        place(&state, seat: 0, column: 3)
        var rng = OfflineRNG(seed: 9)
        XCTAssertEqual(FourInARowRules.botColumns(state, seat: 1, rng: &rng).first, 0)
    }

    func testFourInARowsBotBlocksAThreat() {
        var state = fourInARow()
        for column in 1...3 { place(&state, seat: 0, column: column) }
        var rng = OfflineRNG(seed: 9)
        let first = FourInARowRules.botColumns(state, seat: 1, rng: &rng).first
        XCTAssertTrue(first == 0 || first == 4, "blocks one end, got \(String(describing: first))")
    }

    func testFourInARowsBotIsOnlyAskedOnItsTurn() {
        let state = fourInARow()
        var rng = OfflineRNG(seed: 9)
        XCTAssertTrue(FourInARowRules.botActions(state, for: "p0", rng: &rng).isEmpty)
        XCTAssertFalse(FourInARowRules.botActions(state, for: "p1", rng: &rng).isEmpty)
    }

    func testDotsAndBoxesBotClosesABoxAndAvoidsAThirdSide() {
        var rng = OfflineRNG(seed: 1)
        let players = [OfflinePlayer(id: "a", name: "A"), OfflinePlayer(id: "b", name: "B")]
        var state = DotsAndBoxesRules.start(players: players, now: 0, rng: &rng)
        // Box (0, 0) has three sides: the bot must take the fourth.
        let sides = DotsAndBoxesRules.sides(row: 0, col: 0)
        for line in sides.prefix(3) { draw(line, in: &state) }
        let best = DotsAndBoxesRules.botLines(state, rng: &rng).first
        XCTAssertEqual(best, sides[3])
        // Close it, then give box (1, 1) two sides: its other two are unsafe.
        draw(sides[3], in: &state)
        let inner = DotsAndBoxesRules.sides(row: 1, col: 1)
        draw(inner[0], in: &state)
        draw(inner[1], in: &state)
        let next = DotsAndBoxesRules.botLines(state, rng: &rng).first
        XCTAssertNotEqual(next, inner[2])
        XCTAssertNotEqual(next, inner[3])
    }

    private func draw(_ line: DotsAndBoxesRules.Line, in state: inout DotsAndBoxesRules.State) {
        if line.horizontal {
            state.hLines[line.row * state.cols + line.col] = true
        } else {
            state.vLines[line.row * (state.cols + 1) + line.col] = true
        }
    }

    func testCrazyEightsBotPlaysWhatFitsAndSavesItsEights() {
        var rng = OfflineRNG(seed: 4)
        let players = [OfflinePlayer(id: "a", name: "A"), OfflinePlayer(id: "b", name: "B")]
        var state = CrazyEightsRules.start(players: players, now: 0, rng: &rng)
        state.phase = .playing
        state.turn = 1
        state.discard = [OfflineCard(5, .hearts)]
        state.suit = .hearts
        state.hands["b"] = [OfflineCard(8, .clubs), OfflineCard(2, .hearts), OfflineCard(13, .hearts), OfflineCard(3, .spades)]
        let actions = CrazyEightsRules.botActions(state, for: "b", rng: &rng)
        let turn = state.turnNumber
        XCTAssertEqual(actions.first, .play(turn: turn, card: OfflineCard(13, .hearts), suit: nil), "the dearest card that fits")
        XCTAssertEqual(actions[1], .play(turn: turn, card: OfflineCard(2, .hearts), suit: nil))
        XCTAssertEqual(actions[2], .play(turn: turn, card: OfflineCard(8, .clubs), suit: .hearts), "the eight names its best suit")
        XCTAssertEqual(actions.suffix(2), [.draw(turn: turn), .pass(turn: turn)])

        // Nothing fits: draw, then pass.
        state.hands["b"] = [OfflineCard(3, .spades)]
        XCTAssertEqual(CrazyEightsRules.botActions(state, for: "b", rng: &rng), [.draw(turn: turn), .pass(turn: turn)])
        // Not its turn: nothing.
        XCTAssertTrue(CrazyEightsRules.botActions(state, for: "a", rng: &rng).isEmpty)
    }

    func testABotsMoveGoesThroughTheRules() {
        // The match tries candidates in order and keeps the first legal one.
        var match = OfflineMatchOf<FourInARowRules>(players: [OfflinePlayer(id: "a", name: "A"), OfflinePlayer(id: "b", name: "B")],
                                                    seed: 1, now: 0, bot: { state, id, rng in
            [.drop(turn: state.turnNumber, column: 99), .drop(turn: state.turnNumber, column: 2)]
        })
        let mover = match.state.players[match.state.turn].id
        let other = mover == "a" ? "b" : "a"
        XCTAssertFalse(match.botAct(other, now: 1), "not its turn: nothing legal")
        XCTAssertTrue(match.botAct(mover, now: 1))
        XCTAssertEqual(match.state.lastMove?.column, 2)
    }

    // MARK: - Solo

    func testWhichGamesCanBePlayedAlone() {
        let solo = OfflineGameInfo(id: "a", title: "A", blurb: "b", category: .skill, minPlayers: 1, maxPlayers: 4,
                                   symbol: "x", howToPlay: ["x"])
        let pair = OfflineGameInfo(id: "b", title: "B", blurb: "b", category: .skill, minPlayers: 2, maxPlayers: 4,
                                   symbol: "x", howToPlay: ["x"])
        let three = OfflineGameInfo(id: "c", title: "C", blurb: "b", category: .card, minPlayers: 3, maxPlayers: 5,
                                    symbol: "x", howToPlay: ["x"])
        XCTAssertEqual(OfflinePlayModes.soloBots(solo, hasBot: false), 0)
        XCTAssertNil(OfflinePlayModes.soloBots(pair, hasBot: false))
        XCTAssertEqual(OfflinePlayModes.soloBots(pair, hasBot: true), 1)
        XCTAssertEqual(OfflinePlayModes.soloBots(three, hasBot: true), 2)
        XCTAssertTrue(OfflinePlayModes.canPlayNearby(three))
        XCTAssertEqual(OfflinePlayModes.offlineId(for: "maths-sprint"), "maths-sprint")
        XCTAssertEqual(OfflinePlayModes.offlineId(for: "four-in-a-row"), "four-in-a-row")
    }

    // MARK: - Maths Sprint

    private typealias Sprint = OfflineSprintRules

    private func sprint(_ count: Int = 2) -> (Sprint.State, OfflineRNG) {
        var rng = OfflineRNG(seed: 21)
        let players = (1...count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
        let state = Sprint.start(players: players, now: 1_000, rng: &rng)
        return (state, rng)
    }

    func testSprintPassesTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Sprint.self), [])
    }

    func testEveryoneGetsTheSameSumsAndTheyClimb() {
        let (state, _) = sprint(3)
        XCTAssertEqual(state.problems.count, Sprint.dealt)
        XCTAssertTrue(state.problems.allSatisfy { $0.answer >= 0 })
        XCTAssertTrue(state.problems.prefix(10).allSatisfy { $0.answer <= 30 }, "the first ten are small")
        let views = ["p1", "p2", "p3"].map { Sprint.view(of: state, for: $0) }
        XCTAssertTrue(views.allSatisfy { $0.me?.problem == nil }, "no sum before the start")
        var playing = state
        var rng = OfflineRNG(seed: 1)
        Sprint.tick(&playing, now: 1_003, rng: &rng)
        XCTAssertEqual(playing.phase, .playing)
        let texts = ["p1", "p2", "p3"].map { Sprint.view(of: playing, for: $0).me?.problem }
        XCTAssertEqual(Set(texts.compactMap { $0 }).count, 1, "the same first sum for everyone")
    }

    func testRightAnswersScoreAndAStreakEarnsABonus() throws {
        var (state, rng) = sprint()
        Sprint.tick(&state, now: 1_003, rng: &rng)
        for index in 0..<5 {
            try Sprint.apply(.answer(index: index, value: state.problems[index].answer), by: "p1", to: &state, now: 1_004, rng: &rng)
        }
        XCTAssertEqual(state.racers["p1"]?.score, 5 * Sprint.pointsRight + Sprint.streakBonus)
        try Sprint.apply(.answer(index: 5, value: state.problems[5].answer + 1), by: "p1", to: &state, now: 1_005, rng: &rng)
        XCTAssertEqual(state.racers["p1"]?.streak, 0)
        XCTAssertEqual(state.racers["p1"]?.wrong, 1)
        XCTAssertEqual(state.racers["p1"]?.index, 6, "a wrong answer moves on")
        XCTAssertEqual(Sprint.view(of: state, for: "p1").me?.lastRight, false)
        XCTAssertThrowsError(try Sprint.apply(.answer(index: 2, value: 0), by: "p1", to: &state, now: 1_006, rng: &rng),
                             "an answer to an old sum")
        XCTAssertEqual(Sprint.standings(state).first?.playerId, "p1")
    }

    func testSprintRefusesAnswersOutsideTheMinute() {
        var (state, rng) = sprint()
        XCTAssertThrowsError(try Sprint.apply(.answer(index: 0, value: 1), by: "p1", to: &state, now: 1_001, rng: &rng))
        Sprint.tick(&state, now: 1_003, rng: &rng)
        Sprint.tick(&state, now: 1_063, rng: &rng)
        XCTAssertEqual(state.phase, .done)
        XCTAssertThrowsError(try Sprint.apply(.answer(index: 0, value: 1), by: "p1", to: &state, now: 1_063.5, rng: &rng))
        Sprint.tick(&state, now: 1_068, rng: &rng)
        XCTAssertTrue(Sprint.isOver(state))
    }

    // MARK: - Results to sync later

    private func finishedLobby(standings: [OfflineStanding], bots: [String] = [], match: Int = 3) -> OfflineLobby {
        let players = standings.map { row in
            OfflineLobbyPlayer(id: row.playerId, name: row.name, present: true, inMatch: true,
                               bot: bots.contains(row.playerId) ? true : nil)
        }
        return OfflineLobby(hostId: "h", roomName: "Sam's game", players: players, gameId: "four-in-a-row",
                            phase: .finished, match: match, standings: standings, roomKey: "0000beef")
    }

    private func result(_ id: String, game: String = "four-in-a-row", won: Bool = true, score: Int = 2,
                        at: Double = 1_000) -> OfflineResult {
        OfflineResult(id: id, game: game, title: "Four in a Row", mode: .solo, finishedAt: at, players: 2, bots: 1,
                      rank: won ? 1 : 2, score: score, won: won, detail: nil, opponents: ["Robo"])
    }

    func testAFinishedLobbyMakesThisPhonesRow() throws {
        let lobby = finishedLobby(standings: [
            OfflineStanding(playerId: "h", name: "Sam", rank: 1, score: 2, detail: "four in a row"),
            OfflineStanding(playerId: "bot-1", name: "Robo", rank: 2, score: 1, detail: nil),
        ], bots: ["bot-1"])
        let row = try XCTUnwrap(OfflineResult.from(lobby: lobby, me: "h", title: "Four in a Row", mode: .solo, finishedAt: 5))
        XCTAssertEqual(row.id, "0000beef-3")
        XCTAssertEqual(row.players, 2)
        XCTAssertEqual(row.bots, 1)
        XCTAssertTrue(row.won)
        XCTAssertEqual(row.opponents, ["Robo"])
        XCTAssertNil(OfflineResult.from(lobby: lobby, me: "watcher", title: "x", mode: .nearby, finishedAt: 5),
                     "a spectator files nothing")
        var playing = lobby
        playing.phase = .playing
        XCTAssertNil(OfflineResult.from(lobby: playing, me: "h", title: "x", mode: .nearby, finishedAt: 5))
    }

    func testAGamePlayedAloneWinsNothing() throws {
        let lobby = finishedLobby(standings: [OfflineStanding(playerId: "h", name: "Sam", rank: 1, score: 140, detail: nil)])
        let row = try XCTUnwrap(OfflineResult.from(lobby: lobby, me: "h", title: "Maths Sprint", mode: .solo, finishedAt: 5))
        XCTAssertFalse(row.won)
        XCTAssertEqual(row.score, 140)
    }

    func testTheQueueTakesAMatchOnceAndForgetsItOnceSettled() {
        var queue = OfflineResultQueue()
        XCTAssertTrue(queue.add(result("a")))
        XCTAssertFalse(queue.add(result("a")), "the same match twice")
        XCTAssertTrue(queue.add(result("b", won: false, score: 1)))
        XCTAssertEqual(queue.batch(max: 1).map(\.id), ["a"])
        XCTAssertEqual(queue.waitingLine, "2 games waiting to sync")
        queue.failed()
        XCTAssertEqual(queue.failures, 1)
        queue.settle(["a"])
        XCTAssertEqual(queue.pending.map(\.id), ["b"])
        XCTAssertEqual(queue.failures, 0)
        XCTAssertFalse(queue.add(result("a")), "already synced")
        XCTAssertEqual(queue.waitingLine, "1 game waiting to sync")
        let tally = queue.tallies["four-in-a-row"]
        XCTAssertEqual(tally?.played, 2)
        XCTAssertEqual(tally?.won, 1)
        XCTAssertEqual(tally?.best, 2)
    }

    func testTheQueueKeepsTheNewestWhenFull() {
        var queue = OfflineResultQueue()
        for n in 0..<(OfflineResultQueue.limit + 5) { queue.add(result("m\(n)")) }
        XCTAssertEqual(queue.pending.count, OfflineResultQueue.limit)
        XCTAssertEqual(queue.pending.first?.id, "m5")
    }

    func testTheQueueSurvivesJSON() throws {
        var queue = OfflineResultQueue()
        queue.add(result("a"))
        queue.settle(["a"])
        queue.add(result("b"))
        let back = try JSONDecoder().decode(OfflineResultQueue.self, from: JSONEncoder().encode(queue))
        XCTAssertEqual(back, queue)
    }

    func testTheBackoffGrowsAndStops() {
        XCTAssertEqual(OfflineResultQueue.backoff(failures: 0), 0)
        XCTAssertLessThan(OfflineResultQueue.backoff(failures: 1), OfflineResultQueue.backoff(failures: 2))
        XCTAssertEqual(OfflineResultQueue.backoff(failures: 4), OfflineResultQueue.backoff(failures: 40))
    }

    func testMostPlayedWeighsRecentGames() {
        var queue = OfflineResultQueue()
        let day = 24 * 3_600_000.0
        let now = 100 * day
        for n in 0..<3 { queue.add(result("old\(n)", game: "snap", at: now - 30 * day)) }
        for n in 0..<2 { queue.add(result("new\(n)", game: "maths-sprint", at: now - day)) }
        XCTAssertEqual(queue.mostPlayed(now: now), ["maths-sprint", "snap"])
    }

    func testTheReceiptIsReadLeniently() throws {
        let full = try JSONDecoder().decode(OfflineResultReceipt.self, from: Data(#"{"recorded":["a"],"rejected":["b"]}"#.utf8))
        XCTAssertEqual(full.settled, ["a", "b"])
        let bare = try JSONDecoder().decode(OfflineResultReceipt.self, from: Data("{}".utf8))
        XCTAssertEqual(bare.settled, [])
    }

    func testTheUploadIsTheRowsAsTheyAre() throws {
        let body = try JSONEncoder().encode(OfflineResultUpload(results: [result("a")]))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let rows = try XCTUnwrap(object["results"] as? [[String: Any]])
        XCTAssertEqual(rows.first?["id"] as? String, "a")
        XCTAssertEqual(rows.first?["mode"] as? String, "solo")
        XCTAssertEqual(rows.first?["won"] as? Bool, true)
    }

    // MARK: - The wire stays readable

    func testALobbyFromAnOlderHostStillReads() throws {
        // No `roomKey`, no `bot`: what a phone on the last version sends.
        let json = #"{"hostId":"h","roomName":"R","players":[{"id":"h","name":"Sam","present":true,"inMatch":false}],"phase":"lobby","match":0}"#
        let lobby = try OfflineCoding.decode(OfflineLobby.self, from: Data(json.utf8))
        XCTAssertNil(lobby.roomKey)
        XCTAssertEqual(lobby.players.first?.isBot, false)
    }
}
