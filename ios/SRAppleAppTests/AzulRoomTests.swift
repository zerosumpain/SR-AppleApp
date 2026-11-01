import XCTest
@testable import SRAppleApp

/// Azul in the app's shared models: the room's Azul side read off `GameRoom`,
/// the lobby's `screens`, what Start and a take send, and the demo rooms.
/// The pure rules are `AzulLogicTests` (which also run on Linux).
final class AzulRoomTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    private func object(_ body: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheRoomCarriesItsAzulSide() throws {
        let room = try decode(#"""
        {"id":"g_a","game":"azul","difficulty":"medium","phase":"scoring","hostId":"p_a","meId":"p_a","round":2,
         "table":"tv","serverNow":1,
         "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"seat":0,"score":3,"rows":1,
                     "lines":[[],[],[],[],[]],"wall":[[1,2,3,4,5],[null,null,null,null,null]],"floor":[]}]}
        """#)
        XCTAssertEqual(room.kind, .azul)
        XCTAssertEqual(room.phase, .unknown, "scoring is Azul's own phase")
        XCTAssertEqual(AzulScreenPhase.of(room), .scoring)
        let state = try XCTUnwrap(room.azul)
        XCTAssertEqual(state.table, .tv)
        XCTAssertEqual(state.board("p_a")?.rows, 1)
        XCTAssertEqual(room.players.first?.score, 3, "the shared player row still reads")
        XCTAssertNil(room.fireworks)
    }

    func testTheLobbyListsTheGamesWithATVBoard() throws {
        let lobby = try JSONDecoder().decode(GamesLobby.self, from: Data(#"""
        {"me":{"id":"p_a","name":"Sam"},"players":[],"invites":[],"rooms":[],"serverNow":1,"screens":["azul"]}
        """#.utf8))
        XCTAssertEqual(lobby.screens, ["azul"])
        XCTAssertTrue(GameScreenPairing.offered("azul", lobby: lobby))
        XCTAssertFalse(GameScreenPairing.offered("chess", lobby: lobby))
        let older = try JSONDecoder().decode(GamesLobby.self, from: Data(#"{"me":{"id":"p_a","name":"Sam"}}"#.utf8))
        XCTAssertEqual(older.screens, [], "an older site lists none")
        XCTAssertFalse(GameScreenPairing.offered("azul", lobby: older))
    }

    func testStartSendsTheTableAndThePace() throws {
        let base = AzulSettings(difficulty: .hard, table: .tv).createBody(invite: ["p_b"])
        let body = GamePaceSettings(pace: .async, deadlineHours: 48).apply(to: base)
        let sent = try object(body)
        XCTAssertEqual(sent["game"] as? String, "azul")
        XCTAssertEqual(sent["difficulty"] as? String, "hard")
        XCTAssertEqual(sent["table"] as? String, "tv")
        XCTAssertEqual(sent["pace"] as? String, "async")
        XCTAssertEqual(sent["deadlineHours"] as? Int, 48)
        let phones = try object(AzulSettings(difficulty: .easy).createBody(invite: []))
        XCTAssertEqual(phones["table"] as? String, "phones")
    }

    func testATakeAndAScreenSendTheirFields() throws {
        var take = GameActionBody(action: "take")
        take.source = .named("centre")
        take.colour = "red"
        take.line = .id(2)
        let sent = try object(take)
        XCTAssertEqual(sent["action"] as? String, "take")
        XCTAssertEqual(sent["source"] as? String, "centre")
        XCTAssertEqual(sent["colour"] as? String, "red")
        XCTAssertEqual(sent["line"] as? Int, 2)
        XCTAssertNil(sent["code"])
        var floor = GameActionBody(action: "take")
        floor.source = .id(4)
        floor.line = .named("floor")
        let other = try object(floor)
        XCTAssertEqual(other["source"] as? Int, 4)
        XCTAssertEqual(other["line"] as? String, "floor")
        var screen = GameActionBody(action: "screen")
        screen.code = "BCDF"
        XCTAssertEqual(try object(screen)["code"] as? String, "BCDF")
    }

    func testTheGameIsOnTheShelfUnderTheServersId() {
        XCTAssertEqual(GameKind(rawValue: "azul"), .azul)
        XCTAssertEqual(GameKind.azul.title, "Azul")
        XCTAssertEqual(GameDifficulty.medium.line(for: .azul), "90 seconds a turn.")
        XCTAssertEqual(GameCategory.of("azul"), .strategy)
        XCTAssertEqual(GamesPagePlan.playersChip("azul", onPhone: false), "2–4")
        XCTAssertFalse(GameKind.azul.playsOnPhone)
    }

    func testTheDemoRoomsDecode() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let playing = try decode(try XCTUnwrap(SRDemoFixtures.azulRoom(id: SRDemoFixtures.demoAzulRoom, clock: clock)))
        let state = try XCTUnwrap(playing.azul)
        XCTAssertEqual(AzulScreenPhase.of(playing), .playing)
        XCTAssertEqual(state.turnId, playing.meId)
        XCTAssertEqual(state.seated.count, 3)
        XCTAssertEqual(state.factories.count, 7, "seven factories for three")
        XCTAssertTrue(state.firstInCentre)
        XCTAssertEqual(AzulRules.litLines(state.canPlace, colour: "red"), [0, 2, 4])
        XCTAssertTrue(state.board("p_robin")?.away == true)
        let done = try decode(try XCTUnwrap(SRDemoFixtures.azulRoom(id: SRDemoFixtures.demoAzulDoneRoom, clock: clock)))
        XCTAssertEqual(AzulScreenPhase.of(done), .finished)
        XCTAssertEqual(done.standings?.count, 3)
        XCTAssertEqual(done.azul?.standing("p_sam")?.bonus?.rows, 1)
    }
}
