import XCTest
@testable import SRAppleApp

/// The Games page's parent tools and the family's ideas, as the demo answers
/// them — the same shapes the site sends.
final class GamesParentTests: XCTestCase {
    private let clock = SRDemoFixtures.DemoClock(now: Date())

    /// Alex is a parent in the showcase: two open lobbies, one not Alex's.
    func testTheDemoLobbyMakesAlexAParent() throws {
        let lobby = try JSONDecoder().decode(GamesLobby.self, from: Data(SRDemoFixtures.gamesLobby(clock).utf8))
        XCTAssertTrue(lobby.parent)
        XCTAssertEqual(lobby.openLobbies.map(\.id), [SRDemoFixtures.demoLobbyRoom, SRDemoFixtures.demoSamLobbyRoom])
        XCTAssertEqual(lobby.openLobbies.map(\.mine), [true, false])
    }

    /// An older site sends neither field: nobody is a parent, nothing to close.
    func testAnOlderLobbyHasNoParentTools() throws {
        let json = #"{"me":{"id":"p_a","name":"A"},"players":[],"invites":[],"rooms":[],"serverNow":1}"#
        let lobby = try JSONDecoder().decode(GamesLobby.self, from: Data(json.utf8))
        XCTAssertFalse(lobby.parent)
        XCTAssertTrue(lobby.openLobbies.isEmpty)
    }

    /// The suggestions route is answered before `/games/<id>` takes it for a room.
    func testTheDemoAnswersTheIdeas() throws {
        let parts = ["api", "native", "games", "suggestions"]
        let text = try XCTUnwrap(SRDemoFixtures.gamesRoute(method: "GET", parts: parts, body: nil, clock: clock))
        let list = try JSONDecoder().decode(GameSuggestionList.self, from: Data(text.utf8))
        XCTAssertEqual(list.suggestions.map(\.name), ["Moon lander", "Kart race", "Snakes and ladders"])

        let body = try JSONSerialization.data(withJSONObject: ["name": "Sky \"golf\""])
        let added = try XCTUnwrap(SRDemoFixtures.gamesRoute(method: "POST", parts: parts, body: body, clock: clock))
        let after = try JSONDecoder().decode(GameSuggestionList.self, from: Data(added.utf8))
        XCTAssertEqual(after.suggestions.last?.name, "Sky golf")
        XCTAssertEqual(after.suggestions.last?.mine, true)
    }

    /// A parent closing a lobby tells the phones in it who did.
    func testAClosedRoomSaysWhoClosedIt() throws {
        let json = #"{"id":"g_1","game":"chess","phase":"closed","serverNow":1,"closedBy":"Dad"}"#
        let room = try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
        XCTAssertEqual(room.phase, .closed)
        XCTAssertEqual(room.closedBy, "Dad")
    }
}
