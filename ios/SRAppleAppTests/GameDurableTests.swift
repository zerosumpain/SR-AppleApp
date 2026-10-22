import XCTest
@testable import SRAppleApp

/// Durable rooms: the lobby's new fields (with and without them), the order
/// of "Your games", the deadline copy, the pace a create sends, and the push
/// gate for the room on screen.
final class GameDurableTests: XCTestCase {

    private let now: Double = 1_790_000_000_000
    private let hour: Double = 3_600_000

    // MARK: - Decoding

    func testTheLobbyDecodesDurableFieldsAndPaces() throws {
        let json = #"""
        { "me": {"id":"p_a","name":"John"}, "players": [], "invites": [],
          "rooms": [
            {"id":"g_4be1c2d09a7f","game":"homestead","phase":"playing","hostName":"John",
             "durable":true,"pace":"async","myTurn":true,
             "waitingFor":["Rory"],"dueAt":1761300000000,"updatedAt":1761213600000},
            {"id":"g_2","game":"tap-duel","phase":"lobby","hostName":"Sam",
             "durable":false,"pace":"live","myTurn":false,"waitingFor":null,"dueAt":null,"updatedAt":null}
          ],
          "paces": {"homestead": ["live","async"]},
          "serverNow": 1790000000000 }
        """#
        let lobby = try JSONDecoder().decode(GamesLobby.self, from: Data(json.utf8))
        let durable = lobby.rooms[0]
        XCTAssertTrue(durable.durable)
        XCTAssertEqual(durable.pace, .async)
        XCTAssertTrue(durable.myTurn)
        XCTAssertEqual(durable.waitingFor, ["Rory"])
        XCTAssertEqual(durable.dueAt, 1_761_300_000_000)
        XCTAssertEqual(durable.updatedAt, 1_761_213_600_000)
        let live = lobby.rooms[1]
        XCTAssertFalse(live.durable)
        XCTAssertEqual(live.pace, .live)
        XCTAssertEqual(live.waitingFor, [], "null reads as nobody")
        XCTAssertNil(live.dueAt)
        XCTAssertEqual(lobby.paces["homestead"], ["live", "async"])
        XCTAssertEqual(lobby.paceChoices(for: "homestead"), [.live, .async])
        XCTAssertEqual(lobby.paceChoices(for: "tap-duel"), [], "a game not listed offers no picker")
    }

    func testAnOlderLobbyWithoutTheFieldsReadsAsLiveAndNotDurable() throws {
        let json = #"""
        { "me": {"id":"p_a","name":"John"},
          "rooms": [{"id":"g_1","game":"chess","phase":"playing","hostName":"John"}],
          "serverNow": 1790000000000 }
        """#
        let lobby = try JSONDecoder().decode(GamesLobby.self, from: Data(json.utf8))
        let room = try XCTUnwrap(lobby.rooms.first)
        XCTAssertEqual(room, GameRoomSummary(id: "g_1", game: "chess", phase: .playing, hostName: "John"))
        XCTAssertFalse(room.durable)
        XCTAssertEqual(room.pace, .live)
        XCTAssertFalse(room.myTurn)
        XCTAssertNil(YourGames.status(room, atServer: now), "a room that is not durable keeps 'Hosted by'")
        XCTAssertEqual(lobby.paces, [:])
    }

    func testAnUnknownPaceIsLive() throws {
        let json = #"{"id":"g_1","game":"homestead","phase":"playing","hostName":"Sam","durable":true,"pace":"glacial"}"#
        let room = try JSONDecoder().decode(GameRoomSummary.self, from: Data(json.utf8))
        XCTAssertEqual(room.pace, .live)
        XCTAssertEqual(GamePace.from(nil), .live)
    }

    func testARoomCarriesDurablePaceAndVersion() throws {
        let durable = #"""
        {"id":"g_1","game":"homestead","difficulty":"easy","phase":"playing","hostId":"p_a","meId":"p_a",
         "players":[],"winnerIds":[],"serverNow":1790000000000,"durable":true,"pace":"async","version":41}
        """#
        let room = try JSONDecoder().decode(GameRoom.self, from: Data(durable.utf8))
        XCTAssertTrue(room.durable)
        XCTAssertEqual(room.pace, .async)
        XCTAssertEqual(room.version, 41)

        let plain = #"{"id":"g_2","game":"tap-duel","phase":"lobby","serverNow":1790000000000}"#
        let old = try JSONDecoder().decode(GameRoom.self, from: Data(plain.utf8))
        XCTAssertFalse(old.durable)
        XCTAssertEqual(old.pace, .live)
        XCTAssertNil(old.version)
    }

    // MARK: - Your games

    func testMyMoveComesFirstSoonestDeadlineFirstThenNewest() {
        let rooms = [
            GameRoomSummary(id: "old", game: "homestead", phase: .playing, hostName: "Sam",
                            durable: true, pace: .async, waitingFor: ["Sam"], dueAt: now + 30 * hour, updatedAt: now - 9 * hour),
            GameRoomSummary(id: "live", game: "tap-duel", phase: .lobby, hostName: "Sam"),
            GameRoomSummary(id: "mine-later", game: "homestead", phase: .playing, hostName: "Rory",
                            durable: true, pace: .async, myTurn: true, dueAt: now + 20 * hour, updatedAt: now - 4 * hour),
            GameRoomSummary(id: "recent", game: "homestead", phase: .playing, hostName: "John",
                            durable: true, pace: .async, waitingFor: ["Rory"], dueAt: now + 10 * hour, updatedAt: now - 1 * hour),
            GameRoomSummary(id: "mine-soon", game: "homestead", phase: .playing, hostName: "Katie",
                            durable: true, pace: .async, myTurn: true, dueAt: now + 2 * hour, updatedAt: now - 20 * hour),
            GameRoomSummary(id: "live-2", game: "chess", phase: .playing, hostName: "John"),
        ]
        XCTAssertEqual(YourGames.ordered(rooms).map(\.id),
                       ["mine-soon", "mine-later", "live", "live-2", "recent", "old"],
                       "my moves by deadline, then games in play now in the site's order, then the newest change")
        XCTAssertEqual(YourGames.myMoves(rooms), 2)
    }

    func testTheRowSaysWhoseMoveAndHowLongIsLeft() {
        let mine = GameRoomSummary(id: "a", game: "homestead", phase: .playing, hostName: "Sam",
                                   durable: true, pace: .async, myTurn: true, waitingFor: ["John"], dueAt: now + 21.5 * hour)
        XCTAssertEqual(YourGames.status(mine, atServer: now), "Your move · 21 h left")
        XCTAssertEqual(YourGames.status(mine, atServer: nil), "Your move", "no clock yet: no promise of time")

        let waiting = GameRoomSummary(id: "b", game: "homestead", phase: .playing, hostName: "Sam",
                                      durable: true, pace: .async, waitingFor: ["Rory"], dueAt: now + hour)
        XCTAssertEqual(YourGames.status(waiting, atServer: now), "Waiting for Rory")

        let discard = GameRoomSummary(id: "c", game: "homestead", phase: .playing, hostName: "Sam",
                                      durable: true, waitingFor: ["Rory", "Katie", "Sam"])
        XCTAssertEqual(YourGames.status(discard, atServer: now), "Waiting for Rory, Katie and Sam")

        let lobby = GameRoomSummary(id: "d", game: "homestead", phase: .lobby, hostName: "Sam", durable: true)
        XCTAssertNil(YourGames.status(lobby, atServer: now), "waiting on nobody: the row says who hosts")
    }

    func testDeadlineCopy() {
        XCTAssertEqual(GameDeadline.left(until: now + 23.99 * hour, atServer: now), "23 h left", "hours round down")
        XCTAssertEqual(GameDeadline.left(until: now + hour, atServer: now), "1 h left")
        XCTAssertEqual(GameDeadline.left(until: now + 59 * 60_000 + 1, atServer: now), "60 min left", "minutes round up")
        XCTAssertEqual(GameDeadline.left(until: now + 1_000, atServer: now), "1 min left", "never 0 min")
        XCTAssertEqual(GameDeadline.left(until: now, atServer: now), "Time's up")
        XCTAssertEqual(GameDeadline.left(until: now - hour, atServer: now), "Time's up")
        XCTAssertEqual(GameDeadline.left(until: .nan, atServer: now), "Time's up")
    }

    func testTheLobbyClockReadsHoursPastAnHour() {
        XCTAssertEqual(GameDeadline.clock(seconds: 161), "2:41", "a live lobby looks as it did")
        XCTAssertEqual(GameDeadline.clock(seconds: 0), "0:00")
        XCTAssertEqual(GameDeadline.clock(seconds: -5), "0:00")
        XCTAssertEqual(GameDeadline.clock(seconds: 3599), "59:59")
        XCTAssertEqual(GameDeadline.clock(seconds: 24 * 3600 - 1), "23 h 59 m")
        XCTAssertEqual(GameDeadline.clock(seconds: 3600 + 5 * 60), "1 h 05 m")
    }

    // MARK: - Creating

    func testPaceIsSentOnlyWithItsHours() throws {
        let base = CreateGameBody(game: "homestead", difficulty: "easy", invite: ["p_b"])
        let plain = try json(base)
        XCTAssertNil(plain["pace"], "a game with no pace sends none")
        XCTAssertNil(plain["deadlineHours"])

        let live = try json(GamePaceSettings(pace: .live, deadlineHours: 48).apply(to: base))
        XCTAssertEqual(live["pace"] as? String, "live")
        XCTAssertNil(live["deadlineHours"], "hours mean nothing to a live game")

        let async = try json(GamePaceSettings(pace: .async, deadlineHours: 12).apply(to: base))
        XCTAssertEqual(async["pace"] as? String, "async")
        XCTAssertEqual(async["deadlineHours"] as? Int, 12)
        XCTAssertEqual(async["game"] as? String, "homestead")
        XCTAssertEqual(async["invite"] as? [String], ["p_b"])

        let odd = try json(GamePaceSettings(pace: .async, deadlineHours: 7).apply(to: base))
        XCTAssertEqual(odd["deadlineHours"] as? Int, 24, "only the site's 12, 24 or 48; anything else is a day")
    }

    func testThePacePickerSpeaksPlainly() {
        XCTAssertEqual(GamePace.live.label, "Play now")
        XCTAssertEqual(GamePace.async.label, "Over days")
        XCTAssertEqual(GamePace.deadlineHours, [12, 24, 48])
        XCTAssertEqual(GamePaceSettings(pace: .async, deadlineHours: 48).line,
                       "Up to 48 hours a turn. Run out and the game moves for you.")
    }

    // MARK: - The push

    func testATurnPushNamesItsRoomAndIsSwallowedOnlyWhileThatRoomIsOnScreen() {
        let info: [AnyHashable: Any] = ["roomId": "g_1", "game": "homestead", "category": "game", "kind": "turn"]
        let room = GameTurnPush.roomId(category: "game", userInfo: info)
        XCTAssertEqual(room, "g_1")
        XCTAssertEqual(GameTurnPush.kind(info), "turn")
        XCTAssertTrue(GameTurnPush.silenced(roomId: room, onScreen: ["g_1"]))
        XCTAssertFalse(GameTurnPush.silenced(roomId: room, onScreen: ["g_2"]), "another room's move still rings")
        XCTAssertFalse(GameTurnPush.silenced(roomId: room, onScreen: []))
        XCTAssertNil(GameTurnPush.roomId(category: "chat", userInfo: info), "only the game category")
        XCTAssertNil(GameTurnPush.kind(["roomId": "g_1"]), "an invite carries no kind")
        XCTAssertEqual(GameTurnPush.identifier("g_1"), "game-g_1", "the site's collapse id and the invite banner's")
    }

    @MainActor func testOnScreenRoomsAreCounted() {
        GameRoomsOnScreen.opened("g_t1")
        GameRoomsOnScreen.opened("g_t1")
        GameRoomsOnScreen.closed("g_t1")
        XCTAssertTrue(GameRoomsOnScreen.ids.contains("g_t1"), "one of two links still holds it")
        GameRoomsOnScreen.closed("g_t1")
        XCTAssertFalse(GameRoomsOnScreen.ids.contains("g_t1"))
        GameRoomsOnScreen.closed("g_t1")
        XCTAssertFalse(GameRoomsOnScreen.ids.contains("g_t1"), "an extra close is harmless")
    }

    // MARK: - Demo

    #if DEBUG
    func testTheDemoLobbyListsDurableGamesMyMoveFirst() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let text = try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/games", query: [:], body: nil, clock: clock))
        let lobby = try JSONDecoder().decode(GamesLobby.self, from: Data(text.utf8))
        XCTAssertEqual(lobby.paceChoices(for: "homestead"), [.live, .async])
        guard !SRDemo.isStoreShots else { return }
        let durable = lobby.rooms.filter(\.durable)
        XCTAssertEqual(durable.map(\.id), [SRDemoFixtures.demoDurableMineRoom, SRDemoFixtures.demoDurableWaitingRoom])
        XCTAssertEqual(YourGames.ordered(lobby.rooms).first?.id, SRDemoFixtures.demoDurableMineRoom)
        let status = YourGames.status(durable[0], atServer: lobby.serverNow)
        XCTAssertEqual(status, "Your move · 21 h left")
        XCTAssertEqual(YourGames.status(durable[1], atServer: lobby.serverNow), "Waiting for Sam")

        let snapshot = try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/games/\(SRDemoFixtures.demoDurableMineRoom)",
                                                          query: [:], body: nil, clock: clock))
        let room = try JSONDecoder().decode(GameRoomEnvelope.self, from: Data(snapshot.utf8)).room
        XCTAssertEqual(room.game, "homestead")
        // The Homestead fixtures answer with a real board, not a lobby.
        XCTAssertNotNil(room.homestead)
        XCTAssertTrue(room.durable)
        XCTAssertEqual(room.pace, .async)
    }
    #endif

    // MARK: - Late action answers

    func testALateActionAnswerOlderThanTheStreamIsDropped() {
        // Sam's discard reached me over the stream as v11; my own answer (v10) lands after it.
        XCTAssertTrue(GameRoomLink.isStale(answer: 10, after: 11))
        XCTAssertFalse(GameRoomLink.isStale(answer: 11, after: 11), "the same version is the same room")
        XCTAssertFalse(GameRoomLink.isStale(answer: 12, after: 11))
        XCTAssertFalse(GameRoomLink.isStale(answer: 10, after: nil), "nothing seen yet")
        XCTAssertFalse(GameRoomLink.isStale(answer: nil, after: 11), "a room that is not durable has no version: always applied")
    }

    private func json(_ body: CreateGameBody) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
    }
}
