import XCTest
@testable import SRAppleApp

/// Tap Duel: the wire contract, and the timing that decides who won.
final class GamesTests: XCTestCase {

    // MARK: - The wire (the spec's JSON)

    private let roomJSON = #"""
    { "id":"g_1", "game":"tap-duel", "difficulty":"medium",
      "phase":"armed",
      "hostId":"p_a", "meId":"p_b", "rounds":5,
      "players":[{"id":"p_a","name":"John","status":"joined","score":1,"isHost":true},
                 {"id":"p_b","name":"Sam","status":"joined","score":0,"isHost":false},
                 {"id":"p_c","name":"Robin","status":"declined","score":0,"isHost":false}],
      "phaseEndsAt": null,
      "round": { "number":2, "goAt":1790000003000, "windowMs":1200, "closesAt":1790000005200,
                 "decoys":[{"at":1790000001500,"ms":350}],
                 "responses":[{"playerId":"p_a","reactionMs":null,"early":false}],
                 "winnerId": null },
      "standings": null,
      "winnerIds": [],
      "serverNow": 1790000000000 }
    """#

    func testARoomDecodesFromTheContract() throws {
        let room = try JSONDecoder().decode(GameRoom.self, from: Data(roomJSON.utf8))
        XCTAssertEqual(room.id, "g_1")
        XCTAssertEqual(room.phase, .armed)
        XCTAssertEqual(room.difficulty, "medium")
        XCTAssertEqual(room.rounds, 5)
        XCTAssertFalse(room.isHost)
        XCTAssertEqual(room.me?.name, "Sam")
        XCTAssertEqual(room.host?.name, "John")
        XCTAssertEqual(room.playing.map(\.id), ["p_a", "p_b"], "declined is not playing")
        XCTAssertNil(room.phaseEndsAt)
        let round = try XCTUnwrap(room.round)
        XCTAssertEqual(round.number, 2)
        XCTAssertEqual(round.goAt, 1_790_000_003_000)
        XCTAssertEqual(round.windowMs, 1200)
        XCTAssertEqual(round.decoys, [GameDecoy(at: 1_790_000_001_500, ms: 350)])
        XCTAssertNil(round.response(for: "p_a")?.reactionMs, "armed: who answered, not how fast")
        XCTAssertNil(round.response(for: "p_b"))
        XCTAssertNil(room.standings)
        XCTAssertEqual(room.serverNow, 1_790_000_000_000)
    }

    func testAFinishedRoomDecodesStandingsAndTies() throws {
        let json = #"""
        {"id":"g_2","game":"tap-duel","difficulty":"hard","phase":"finished","hostId":"p_a","meId":"p_a","rounds":5,
         "players":[{"id":"p_a","name":"John","status":"joined","score":2,"isHost":true},
                    {"id":"p_b","name":"Sam","status":"joined","score":2,"isHost":false}],
         "phaseEndsAt":1790000600000,"round":null,
         "standings":[{"id":"p_a","name":"John","score":2,"bestMs":198,"avgMs":240.4,"falseStarts":1},
                      {"id":"p_b","name":"Sam","score":2,"bestMs":null,"avgMs":null,"falseStarts":0}],
         "winnerIds":["p_a","p_b"],"serverNow":1790000000000}
        """#
        let room = try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
        XCTAssertEqual(room.phase, .finished)
        XCTAssertTrue(room.isHost)
        XCTAssertEqual(room.winnerIds, ["p_a", "p_b"])
        let standings = try XCTUnwrap(room.standings)
        XCTAssertEqual(standings[0].bestMs, 198)
        XCTAssertEqual(standings[0].avgMs, 240, "a fractional average rounds")
        XCTAssertEqual(standings[0].falseStarts, 1)
        XCTAssertNil(standings[1].bestMs)
    }

    func testAResultResponseCarriesItsTime() throws {
        let json = #"{"playerId":"p_a","reactionMs":231,"early":false}"#
        let response = try JSONDecoder().decode(GameResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.reactionMs, 231)
        XCTAssertFalse(response.early)
    }

    func testAnUnknownPhaseIsNotAThrow() throws {
        let json = #"{"id":"g_3","phase":"intermission","serverNow":1}"#
        let room = try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
        XCTAssertEqual(room.phase, .unknown)
        XCTAssertEqual(room.winnerIds, [])
    }

    func testAStreamFrameCarriesARoom() throws {
        let frame = try JSONDecoder().decode(GameStreamFrame.self, from: Data(#"{"type":"room","room":\#(roomJSON)}"#.utf8))
        XCTAssertEqual(frame.type, "room")
        XCTAssertEqual(frame.room?.id, "g_1")
    }

    func testTheLobbyPollDecodes() throws {
        let json = #"""
        { "me": {"id":"p_a","name":"John"},
          "players": [{"id":"p_b","name":"Sam"}],
          "invites": [{"roomId":"g_9","game":"tap-duel","difficulty":"easy","hostName":"Sam",
                       "players":["Sam","John"],"expiresAt":1790000000000}],
          "rooms":   [{"id":"g_1","game":"tap-duel","phase":"lobby","hostName":"John"}],
          "serverNow": 1790000000000 }
        """#
        let lobby = try JSONDecoder().decode(GamesLobby.self, from: Data(json.utf8))
        XCTAssertEqual(lobby.me.name, "John")
        XCTAssertEqual(lobby.players.map(\.name), ["Sam"])
        XCTAssertEqual(lobby.invites.first?.roomId, "g_9")
        XCTAssertEqual(lobby.rooms.first?.phase, .lobby)
    }

    func testActionBodiesLeaveOutWhatTheyDoNotSay() throws {
        let join = try JSONSerialization.jsonObject(with: JSONEncoder().encode(GameActionBody(action: "join"))) as? [String: Any]
        XCTAssertEqual(join?.count, 1)
        XCTAssertEqual(join?["action"] as? String, "join")

        let early = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TapOutcome.early.body(round: 3))) as? [String: Any]
        XCTAssertEqual(early?["action"] as? String, "tap")
        XCTAssertEqual(early?["round"] as? Int, 3)
        XCTAssertEqual(early?["early"] as? Bool, true)
        XCTAssertNil(early?["reactionMs"])

        let good = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TapOutcome.reaction(231).body(round: 3))) as? [String: Any]
        XCTAssertEqual(good?["reactionMs"] as? Int, 231)
        XCTAssertEqual(good?["early"] as? Bool, false)

        let create = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CreateGameBody(difficulty: "hard", invite: ["p_b"]))) as? [String: Any]
        XCTAssertEqual(create?["game"] as? String, "tap-duel")
        XCTAssertEqual(create?["difficulty"] as? String, "hard")
        XCTAssertEqual(create?["invite"] as? [String], ["p_b"])
    }

    func testTheInviteNotificationNamesHostDifficultyAndPlayers() {
        let invite = GameInvite(roomId: "g_9", game: "tap-duel", difficulty: "medium", hostName: "Sam",
                                players: ["Sam", "Robin", "John"], expiresAt: nil)
        XCTAssertEqual(invite.notificationTitle, "Sam invited you to Tap Duel")
        XCTAssertEqual(invite.notificationBody, "Medium, with Sam, Robin and John. Tap to join.")
        let request = GamesStore.request(for: invite)
        XCTAssertEqual(request.content.categoryIdentifier, "game")
        XCTAssertEqual(request.content.threadIdentifier, "game")
        XCTAssertEqual(request.content.userInfo["roomId"] as? String, "g_9")
        XCTAssertEqual(request.content.interruptionLevel, .active)
        XCTAssertEqual(request.identifier, "game-g_9", "one invite, one banner")
    }

    // MARK: - The clock

    func testAPushedFrameIsALowerBoundAndTheQuickestWins() {
        var clock = GameClock()
        // True offset 1_000_000. Latencies 80, 20, 300 ms.
        clock.record(serverNow: 1_000_000 + 1000, receivedAt: 1000 + 80)
        clock.record(serverNow: 1_000_000 + 2000, receivedAt: 2000 + 20)
        clock.record(serverNow: 1_000_000 + 3000, receivedAt: 3000 + 300)
        XCTAssertEqual(clock.offsetMs, 1_000_000 - 20)
    }

    func testAReplayedStaleFrameDoesNotMoveTheClock() {
        var clock = GameClock()
        clock.record(serverNow: 1_000_000 + 5000, receivedAt: 5000 + 30)
        // The same room replayed on reconnect, stamped a minute ago.
        clock.record(serverNow: 1_000_000 - 55_000, receivedAt: 5100)
        XCTAssertEqual(clock.offsetMs, 1_000_000 - 30)
    }

    func testARoundTripBoundsTheOffsetFromBothSides() {
        var clock = GameClock()
        // Sent at 1000, answered at 1100, server stamped halfway.
        clock.record(serverNow: 1_000_000 + 1050, sentAt: 1000, receivedAt: 1100)
        XCTAssertEqual(clock.offsetMs, 1_000_000)
        XCTAssertEqual(clock.uncertaintyMs, 50)
        // A quick pushed frame raises the floor: the interval is now
        // [999_990, 1_000_050], and the estimate its middle.
        clock.record(serverNow: 1_000_000 + 2000, receivedAt: 2000 + 10)
        XCTAssertEqual(clock.offsetMs, 1_000_020)
        XCTAssertEqual(clock.uncertaintyMs, 30)
    }

    func testContradictorySamplesResetToTheNewest() {
        var clock = GameClock()
        clock.record(serverNow: 1_000_000 + 1050, sentAt: 1000, receivedAt: 1100)
        // The server's clock stepped forward by ten seconds.
        clock.record(serverNow: 1_010_000 + 2000, receivedAt: 2000 + 20)
        XCTAssertEqual(clock.samples.count, 1)
        XCTAssertEqual(clock.offsetMs, 1_010_000 - 20)
    }

    func testTheWindowForgetsOldSamples() {
        var clock = GameClock()
        for i in 0..<(GameClock.window + 5) {
            clock.record(serverNow: Double(i * 1000), receivedAt: Double(i * 1000))
        }
        XCTAssertEqual(clock.samples.count, GameClock.window)
    }

    func testServerTimeMapsToLocalAndBack() {
        var clock = GameClock()
        XCTAssertNil(clock.local(5000), "no sample, no mapping")
        clock.record(serverNow: 1_790_000_000_000, receivedAt: 10_000)
        XCTAssertEqual(clock.local(1_790_000_003_000), 13_000, "green three seconds from now is three seconds from now here")
        XCTAssertEqual(clock.server(13_000), 1_790_000_003_000)
    }

    // MARK: - The signal

    private func round(goAt: Double, decoys: [(Double, Double)]) throws -> GameRound {
        let decoyJSON = decoys.map { "{\"at\":\(Int64($0.0)),\"ms\":\(Int64($0.1))}" }.joined(separator: ",")
        let json = "{\"number\":1,\"goAt\":\(Int64(goAt)),\"windowMs\":800,\"decoys\":[\(decoyJSON)],\"responses\":[]}"
        return try JSONDecoder().decode(GameRound.self, from: Data(json.utf8))
    }

    func testTheSignalWaitsFlashesThenGoes() throws {
        let r = try round(goAt: 10_000, decoys: [(4000, 350), (7000, 200)])
        XCTAssertEqual(TapTiming.signal(for: r, atServer: 3999), .wait)
        XCTAssertEqual(TapTiming.signal(for: r, atServer: 4000), .decoy)
        XCTAssertEqual(TapTiming.signal(for: r, atServer: 4349), .decoy)
        XCTAssertEqual(TapTiming.signal(for: r, atServer: 4350), .wait, "a decoy lasts exactly its ms")
        XCTAssertEqual(TapTiming.signal(for: r, atServer: 7100), .decoy)
        XCTAssertEqual(TapTiming.signal(for: r, atServer: 9999), .wait)
        XCTAssertEqual(TapTiming.signal(for: r, atServer: 10_000), .go)
        XCTAssertEqual(TapTiming.signal(for: r, atServer: 12_000), .go)
    }

    // MARK: - Judging a tap

    func testReactionIsShownToTapRoundedToTheMillisecond() {
        XCTAssertEqual(TapTiming.reactionMs(shown: 100.0, tapped: 100.2314), 231)
        XCTAssertEqual(TapTiming.reactionMs(shown: 100.0, tapped: 100.2316), 232)
        XCTAssertEqual(TapTiming.judge(tappedAt: 50.25, shownAt: 50.0), .reaction(250))
    }

    func testATapBeforeGreenIsEarly() {
        XCTAssertEqual(TapTiming.judge(tappedAt: 10, shownAt: nil), .early, "green never shown — a decoy or the wait")
        XCTAssertEqual(TapTiming.judge(tappedAt: 9.99, shownAt: 10), .early, "green scheduled but not yet on the glass")
    }

    func testAnticipationDoesNotCount() {
        XCTAssertFalse(TapOutcome.reaction(99).counts)
        XCTAssertTrue(TapOutcome.reaction(100).counts)
        XCTAssertFalse(TapOutcome.early.counts)
    }

    func testOneTapPerRound() {
        var ledger = TapLedger()
        XCTAssertTrue(ledger.claim(round: 1))
        XCTAssertFalse(ledger.claim(round: 1))
        XCTAssertTrue(ledger.hasTapped(round: 1))
        XCTAssertFalse(ledger.hasTapped(round: 2))
        XCTAssertTrue(ledger.claim(round: 2))
    }

    func testTheCountdownCountsWholeSecondsUp() {
        XCTAssertEqual(GameCountdown.secondsLeft(until: 3000, atServer: 0), 3)
        XCTAssertEqual(GameCountdown.secondsLeft(until: 3000, atServer: 1), 3)
        XCTAssertEqual(GameCountdown.secondsLeft(until: 3000, atServer: 2001), 1)
        XCTAssertEqual(GameCountdown.secondsLeft(until: 3000, atServer: 3000), 0)
        XCTAssertEqual(GameCountdown.secondsLeft(until: 3000, atServer: 9000), 0)
    }

    // MARK: - Demo

    #if DEBUG
    func testTheDemoGamesDecode() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let lobby = try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/games", query: [:], body: nil, clock: clock))
        let decoded = try JSONDecoder().decode(GamesLobby.self, from: Data(lobby.utf8))
        XCTAssertEqual(decoded.players.map(\.name), ["Sam", "Robin"])
        XCTAssertEqual(decoded.invites.count, 1)

        let room = try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/games/g_demo_lobby", query: [:], body: nil, clock: clock))
        let envelope = try JSONDecoder().decode(GameRoomEnvelope.self, from: Data(room.utf8))
        XCTAssertEqual(envelope.room.phase, .lobby)
        XCTAssertTrue(envelope.room.isHost)

        XCTAssertNil(SRDemoFixtures.route(method: "GET", path: "/api/native/games/g_demo_lobby/stream", query: [:], body: nil, clock: clock),
                     "the stream 404s in demo; the room falls back to the snapshot")
    }
    #endif
}
