import XCTest
@testable import SRAppleApp

/// Sequence Memory: the spec's wire contract, and the rules the phone applies
/// itself — when each flash happens, which tile is lit, collecting the taps.
final class SequenceMemoryTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    // MARK: - The wire (the spec's JSON)

    /// Round 1, easy: three flashes of 700 ms, 150 ms apart, the first 1 s
    /// after dealing at 1790000000000.
    private let showJSON = #"""
    { "id":"g_s", "game":"sequence-memory", "difficulty":"easy",
      "phase":"show", "hostId":"p_a", "meId":"p_b",
      "tiles":4, "startLength":3, "maxLength":20, "phaseEndsAt":1790000003400,
      "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"playing":true,"alive":true,"best":0,"roundsSurvived":0,"outRound":null},
                 {"id":"p_b","name":"John","status":"joined","isHost":false,"playing":true,"alive":true,"best":0,"roundsSurvived":0,"outRound":null}],
      "round": {"number":1,"length":3,"showAt":1790000001000,"stepMs":700,"gapMs":150,
         "steps": [{"tile":2,"at":1790000001000,"ms":700},{"tile":0,"at":1790000001850,"ms":700},{"tile":3,"at":1790000002700,"ms":700}],
         "inputAt":1790000003400,"windowMs":4400,"inputEndsAt":1790000007800,"closesAt":1790000008800,
         "answeredIds":[], "attempts": null, "survivorIds": null},
      "standings": null, "winnerIds": [], "serverNow":1790000000000 }
    """#

    func testAShowDecodesFromTheContract() throws {
        let room = try decode(showJSON)
        XCTAssertEqual(room.kind, .sequenceMemory)
        XCTAssertEqual(room.phase, .show)
        XCTAssertEqual(room.tiles, 4)
        XCTAssertEqual(room.startLength, 3)
        XCTAssertEqual(room.maxLength, 20)
        XCTAssertNil(room.round, "not a Tap Duel round")
        let round = try XCTUnwrap(room.memory)
        XCTAssertEqual(round.number, 1)
        XCTAssertEqual(round.length, 3)
        XCTAssertEqual(round.stepMs, 700)
        XCTAssertEqual(round.gapMs, 150)
        XCTAssertEqual(round.sequence, [2, 0, 3])
        XCTAssertEqual(round.inputAt, 1_790_000_003_400)
        XCTAssertEqual(round.windowMs, 4400)
        XCTAssertEqual(round.inputEndsAt, 1_790_000_007_800)
        XCTAssertEqual(round.closesAt, 1_790_000_008_800)
        XCTAssertNil(round.attempts)
        let me = try XCTUnwrap(room.me)
        XCTAssertTrue(me.seated, "`playing` on the wire")
        XCTAssertTrue(me.alive)
        XCTAssertEqual(room.playing.count, 2, "`GameRoom.playing` is still the joined players")
    }

    func testInputHidesTheSequence() throws {
        let json = #"""
        { "id":"g_s", "game":"sequence-memory", "difficulty":"medium", "phase":"input",
          "hostId":"p_a", "meId":"p_b", "tiles":6, "startLength":3, "maxLength":20, "phaseEndsAt":1790000010000,
          "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"playing":true,"alive":true,"best":3,"roundsSurvived":1,"outRound":null},
                     {"id":"p_b","name":"John","status":"joined","isHost":false,"playing":true,"alive":true,"best":3,"roundsSurvived":1,"outRound":null},
                     {"id":"p_c","name":"Robin","status":"joined","isHost":false,"playing":true,"alive":false,"best":0,"roundsSurvived":0,"outRound":1}],
          "round": {"number":2,"length":4,"showAt":1790000000000,"stepMs":550,"gapMs":150,"steps":null,
                    "inputAt":1790000002650,"windowMs":5200,"inputEndsAt":1790000007850,"closesAt":1790000008850,
                    "answeredIds":["p_a"],"attempts":null,"survivorIds":null},
          "standings": null, "winnerIds": [], "serverNow":1790000003000 }
        """#
        let room = try decode(json)
        XCTAssertEqual(room.phase, .input)
        let round = try XCTUnwrap(room.memory)
        XCTAssertNil(round.steps, "the sequence is off the wire during input")
        XCTAssertNil(round.sequence)
        XCTAssertEqual(round.answeredIds, ["p_a"], "who has answered, never what")
        let robin = try XCTUnwrap(room.players.last)
        XCTAssertFalse(robin.alive)
        XCTAssertEqual(robin.outRound, 1)
    }

    func testAResultAndAFinishDecode() throws {
        let result = #"""
        { "id":"g_s", "game":"sequence-memory", "difficulty":"easy", "phase":"result",
          "hostId":"p_a", "meId":"p_b", "tiles":4, "startLength":3, "maxLength":20, "phaseEndsAt":1790000012000,
          "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"playing":true,"alive":true,"best":3,"roundsSurvived":1,"outRound":null},
                     {"id":"p_b","name":"John","status":"joined","isHost":false,"playing":true,"alive":false,"best":0,"roundsSurvived":0,"outRound":1}],
          "round": {"number":1,"length":3,"showAt":1790000001000,"stepMs":700,"gapMs":150,
                    "steps":[{"tile":2,"at":1790000001000,"ms":700},{"tile":0,"at":1790000001850,"ms":700},{"tile":3,"at":1790000002700,"ms":700}],
                    "inputAt":1790000003400,"windowMs":4400,"inputEndsAt":1790000007800,"closesAt":1790000008800,
                    "answeredIds":["p_a","p_b"],
                    "attempts":[{"playerId":"p_a","taps":[2,0,3],"correct":true},{"playerId":"p_b","taps":[2,1],"correct":false}],
                    "survivorIds":["p_a"]},
          "standings": null, "winnerIds": [], "serverNow":1790000010000 }
        """#
        let room = try decode(result)
        XCTAssertEqual(room.phase, .result)
        let round = try XCTUnwrap(room.memory)
        XCTAssertEqual(round.survivorIds, ["p_a"])
        XCTAssertEqual(round.attempt(of: "p_b")?.taps, [2, 1], "a short attempt is a wrong one")
        XCTAssertEqual(round.attempt(of: "p_b")?.correct, false)
        XCTAssertEqual(round.sequence, [2, 0, 3], "the sequence is back once settled")

        let finished = #"""
        { "id":"g_s", "game":"sequence-memory", "difficulty":"easy", "phase":"finished",
          "hostId":"p_a", "meId":"p_b", "tiles":4, "startLength":3, "maxLength":20, "phaseEndsAt":1790000612000,
          "players":[], "round": null,
          "standings":[{"id":"p_a","name":"Sam","best":7,"roundsSurvived":5,"outRound":6},
                       {"id":"p_b","name":"John","best":0,"roundsSurvived":0,"outRound":1}],
          "winnerIds":["p_a"], "serverNow":1790000020000 }
        """#
        let end = try decode(finished)
        let standings = try XCTUnwrap(end.standings)
        XCTAssertEqual(standings[0].best, 7)
        XCTAssertEqual(standings[0].roundsSurvived, 5)
        XCTAssertEqual(standings[0].outRound, 6)
        XCTAssertEqual(end.winnerIds, ["p_a"])
        XCTAssertNil(end.memory)
    }

    func testATapDuelRoundIsNotASequenceRound() throws {
        let json = #"""
        {"id":"g_t","game":"tap-duel","phase":"armed","serverNow":1,
         "round":{"number":1,"goAt":1790000003000,"windowMs":2000,"decoys":[],"responses":[]}}
        """#
        let room = try decode(json)
        XCTAssertNotNil(room.round)
        XCTAssertNil(room.memory)
    }

    func testAnAttemptBodyIsRoundAndTaps() throws {
        var taps = SequenceTaps(round: 2, length: 3, tiles: 4)
        _ = taps.tap(1)
        _ = taps.tap(3)
        _ = taps.tap(0)
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(taps.body())) as? [String: Any]
        XCTAssertEqual(body?.count, 3)
        XCTAssertEqual(body?["action"] as? String, "attempt")
        XCTAssertEqual(body?["round"] as? Int, 2)
        XCTAssertEqual(body?["taps"] as? [Int], [1, 3, 0])
    }

    // MARK: - The flash schedule

    func testTheScheduleMatchesTheServersDeal() {
        // The server: flash i at showAt + i·(step + gap); input when the last ends.
        let flashes = SequenceSchedule.flashes(showAt: 1_000, stepMs: 700, gapMs: 150, tiles: [2, 0, 3])
        XCTAssertEqual(flashes, [SequenceStep(tile: 2, at: 1_000, ms: 700),
                                 SequenceStep(tile: 0, at: 1_850, ms: 700),
                                 SequenceStep(tile: 3, at: 2_700, ms: 700)])
        XCTAssertEqual(SequenceSchedule.inputAt(showAt: 1_000, stepMs: 700, gapMs: 150, length: 3), 3_400)
        XCTAssertEqual(SequenceSchedule.inputAt(showAt: 0, stepMs: 400, gapMs: 150, length: 20), 20 * 400 + 19 * 150)
        XCTAssertEqual(SequenceSchedule.windowMs(length: 3), 4_400)
    }

    func testARoundWithoutTimingsWorksThemOut() throws {
        let json = #"{"number":1,"length":3,"showAt":1000,"stepMs":700,"gapMs":150,"steps":null,"answeredIds":[]}"#
        let round = try JSONDecoder().decode(SequenceRound.self, from: Data(json.utf8))
        XCTAssertEqual(round.inputAt, 3_400)
        XCTAssertEqual(round.windowMs, 4_400)
        XCTAssertEqual(round.inputEndsAt, 7_800)
    }

    func testWhichTileIsLitAtAnInstant() {
        let steps = SequenceSchedule.flashes(showAt: 1_000, stepMs: 700, gapMs: 150, tiles: [2, 0, 2])
        XCTAssertNil(SequenceSchedule.lit(steps, atServer: 999), "before the show")
        XCTAssertEqual(SequenceSchedule.lit(steps, atServer: 1_000)?.tile, 2)
        XCTAssertEqual(SequenceSchedule.lit(steps, atServer: 1_699)?.step, 0)
        XCTAssertNil(SequenceSchedule.lit(steps, atServer: 1_700), "a flash lasts exactly its ms")
        XCTAssertNil(SequenceSchedule.lit(steps, atServer: 1_849), "the gap")
        XCTAssertEqual(SequenceSchedule.lit(steps, atServer: 1_850)?.tile, 0)
        // The same tile twice is two flashes, told apart by their step.
        XCTAssertEqual(SequenceSchedule.lit(steps, atServer: 2_700)?.step, 2)
        XCTAssertEqual(SequenceSchedule.lit(steps, atServer: 2_700)?.tile, 2)
        XCTAssertNil(SequenceSchedule.lit(steps, atServer: 3_400), "the show is over")
    }

    func testTheFlashLandsAtTheSameInstantOnThisPhonesClock() {
        // Server 1_790_000_001_000 is 1 s after this phone's 10_000 ms.
        var clock = GameClock()
        clock.record(serverNow: 1_790_000_000_000, receivedAt: 10_000)
        let steps = SequenceSchedule.flashes(showAt: 1_790_000_001_000, stepMs: 700, gapMs: 150, tiles: [1, 3])
        XCTAssertEqual(clock.local(steps[0].at), 11_000)
        XCTAssertEqual(clock.local(steps[1].at), 11_850)
        XCTAssertNil(SequenceSchedule.lit(steps, atServer: clock.server(10_999)!))
        XCTAssertEqual(SequenceSchedule.lit(steps, atServer: clock.server(11_000)!)?.tile, 1)
    }

    func testTheInputWindowOpensOnThePhonesClockToo() throws {
        let round = try XCTUnwrap(try decode(showJSON).memory)
        XCTAssertFalse(SequenceSchedule.inputOpen(phase: .show, round: round, atServer: 1_790_000_003_399))
        XCTAssertTrue(SequenceSchedule.inputOpen(phase: .show, round: round, atServer: 1_790_000_003_400))
        XCTAssertTrue(SequenceSchedule.inputOpen(phase: .input, round: round, atServer: nil))
        XCTAssertFalse(SequenceSchedule.inputOpen(phase: .result, round: round, atServer: 1_790_000_009_000))
    }

    func testTheGridShape() {
        XCTAssertEqual(SequenceSchedule.columns(tiles: 4), 2)
        XCTAssertEqual(SequenceSchedule.columns(tiles: 6), 3)
        XCTAssertEqual(SequenceSchedule.columns(tiles: 9), 3)
    }

    // MARK: - Collecting the taps

    func testTapsCompleteAtTheRoundsLength() {
        var taps = SequenceTaps(round: 1, length: 3, tiles: 4)
        XCTAssertEqual(taps.tap(2), .added)
        XCTAssertEqual(taps.tap(0), .added)
        XCTAssertEqual(taps.tap(3), .complete([2, 0, 3]))
        XCTAssertTrue(taps.isComplete)
        XCTAssertEqual(taps.tap(1), .ignored, "the attempt is sent; nothing more counts")
        XCTAssertEqual(taps.taps, [2, 0, 3])
    }

    func testUndoTakesBackTheLastTapUntilComplete() {
        var taps = SequenceTaps(round: 1, length: 3, tiles: 4)
        XCTAssertFalse(taps.undo(), "nothing to undo")
        _ = taps.tap(2)
        _ = taps.tap(1)
        XCTAssertTrue(taps.canUndo)
        XCTAssertTrue(taps.undo())
        XCTAssertEqual(taps.taps, [2])
        _ = taps.tap(0)
        _ = taps.tap(3)
        XCTAssertFalse(taps.canUndo, "a complete attempt has gone")
        XCTAssertFalse(taps.undo())
        XCTAssertEqual(taps.taps, [2, 0, 3])
    }

    func testATileOffTheGridIsIgnored() {
        var taps = SequenceTaps(round: 1, length: 3, tiles: 4)
        XCTAssertEqual(taps.tap(4), .ignored)
        XCTAssertEqual(taps.tap(-1), .ignored)
        XCTAssertTrue(taps.taps.isEmpty)
    }

    // MARK: - Demo

    #if DEBUG
    /// The `-SRDemo` rooms for all three new games decode, mid-play, as the
    /// screenshots need them.
    func testTheDemoRoomsForTheNewGamesAreMidPlay() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let lobbyJSON = try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/games", query: [:], body: nil, clock: clock))
        let lobby = try JSONDecoder().decode(GamesLobby.self, from: Data(lobbyJSON.utf8))
        XCTAssertTrue(lobby.rooms.contains { $0.id == "g_demo_anagram" && $0.phase == .playing })
        XCTAssertTrue(lobby.rooms.contains { $0.id == "g_demo_sprint" && $0.phase == .playing })
        XCTAssertTrue(lobby.rooms.contains { $0.id == "g_demo_memory" && $0.phase == .input })

        func get(_ id: String) throws -> GameRoom {
            let json = try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/games/\(id)", query: [:], body: nil, clock: clock))
            return try JSONDecoder().decode(GameRoomEnvelope.self, from: Data(json.utf8)).room
        }
        let anagram = try get("g_demo_anagram")
        XCTAssertEqual(anagram.kind, .anagramBlitz)
        XCTAssertEqual(anagram.letters?.count, 7)
        XCTAssertEqual(anagram.me?.words?.count, 5)
        var input = AnagramInput(tiles: anagram.letters ?? [])
        for letter in "pai" { XCTAssertTrue(input.add(letter), "the demo's half-built word fits the tiles") }
        for word in anagram.me?.words ?? [] {
            var check = AnagramInput(tiles: anagram.letters ?? [])
            XCTAssertTrue(word.word.allSatisfy { check.add($0) }, "\(word.word) fits the tiles")
        }

        let sprint = try get("g_demo_sprint")
        XCTAssertEqual(sprint.kind, .mathsSprint)
        XCTAssertEqual(sprint.sprint?.problem?.text, "7 × 8")
        XCTAssertTrue(MathsSprint.onBonus(streak: sprint.sprint?.streak ?? 0, every: sprint.streakBonus), "the shot shows the bonus cue")

        let memory = try get("g_demo_memory")
        XCTAssertEqual(memory.kind, .sequenceMemory)
        XCTAssertEqual(memory.tiles, 6)
        let round = try XCTUnwrap(memory.memory)
        XCTAssertNil(round.steps)
        XCTAssertEqual(round.inputAt, SequenceSchedule.inputAt(showAt: round.showAt, stepMs: round.stepMs, gapMs: round.gapMs, length: round.length),
                       accuracy: 2)
        XCTAssertGreaterThan(round.inputEndsAt, memory.serverNow)
        XCTAssertEqual(memory.players.filter(\.alive).count, 2)
    }
    #endif

    func testEveryTileHasItsOwnSymbolAndName() {
        let symbols = (0..<9).map(SequencePalette.symbol)
        XCTAssertEqual(Set(symbols).count, 9, "nine tiles, nine shapes — colour is never the only cue")
        XCTAssertEqual(SequencePalette.spoken(0), "Tile 1, circle, orange")
        XCTAssertEqual(GameNames.title("sequence-memory"), "Sequence Memory")
        XCTAssertEqual(GamePhase(rawValue: "show"), .show)
        XCTAssertEqual(GamePhase(rawValue: "input"), .input)
    }
}
