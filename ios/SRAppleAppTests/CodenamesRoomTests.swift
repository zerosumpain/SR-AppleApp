import XCTest
@testable import SRAppleApp

/// Codenames in the app's shared models: the room's Codenames side read off
/// `GameRoom` (with and without the key), the lobby's `screens` for it and
/// Quiz Night, what Start sends, and the demo rooms. The pure rules are
/// `CodenamesLogicTests` (which also run on Linux).
final class CodenamesRoomTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    private func object(_ body: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The spec's wire sample, as one phone sees it: `key` for a spymaster, null otherwise.
    private func wire(me: String, key: Bool, phase: String = "guess", finished: Bool = false) -> String {
        let cards = (0..<25).map { i -> String in
            i == 4 ? #"{"i":4,"word":"snowman","kind":"blue","by":"p_d","turn":2}"#
                : #"{"i":\#(i),"word":"word\#(i)","kind":null,"by":null,"turn":null}"#
        }.joined(separator: ",")
        let kinds = (0..<25).map { i in i == 0 ? "\"assassin\"" : i < 10 ? "\"red\"" : i < 18 ? "\"blue\"" : "\"neutral\"" }
        return """
        {"id":"g_c","game":"codenames","difficulty":"hard","phase":"\(finished ? "finished" : phase)","hostId":"p_a","meId":"\(me)",
         "mode":"teams","clueMs":90000,"guessMs":90000,"startedAt":1790000000000,"phaseEndsAt":1790000090000,
         "starting":"red","turnTeam":"blue","turns":2,"cards":[\(cards)],
         "key":\(key ? "[" + kinds.joined(separator: ",") + "]" : "null"),
         "clue":{"team":"blue","by":"p_c","word":"WINTER","count":2,"cards":[4],"at":1790000050000,"guessesLeft":2},
         "clues":[{"team":"red","by":"p_a","word":"SEA","count":1,"cards":[],"at":1790000010000},
                  {"team":"blue","by":"p_c","word":"WINTER","count":2,"cards":[4],"at":1790000050000}],
         "teams":[{"team":"red","agents":9,"left":9,"spymasterId":"p_a"},{"team":"blue","agents":8,"left":7,"spymasterId":"p_c"}],
         "last":{"card":4,"kind":"blue","team":"blue","by":"p_d","at":1790000060000},
         "canGuess":\(me == "p_d" && !finished),"canClue":false,
         "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"team":"red","spymaster":true},
                    {"id":"p_b","name":"John","status":"joined","isHost":false,"team":"red","spymaster":false},
                    {"id":"p_c","name":"Kit","status":"joined","isHost":false,"team":"blue","spymaster":true},
                    {"id":"p_d","name":"Ali","status":"joined","isHost":false,"team":"blue","spymaster":false}],
         "result":\(finished ? #"{"winner":"blue","reason":"assassin"}"# : "null"),
         "standings":\(finished ? #"[{"id":"p_c","name":"Kit","team":"blue","spymaster":true,"score":1,"place":1,"result":"won"},{"id":"p_a","name":"Sam","team":"red","spymaster":true,"score":0,"place":2,"result":"lost"}]"# : "null"),
         "winnerIds":\(finished ? #"["p_c","p_d"]"# : "[]"),"serverNow":1790000070000}
        """
    }

    func testAnOperativesRoomCarriesNoKey() throws {
        let room = try decode(wire(me: "p_d", key: false))
        XCTAssertEqual(room.kind, .codenames)
        XCTAssertEqual(room.phase, .unknown, "guess is Codenames' own phase")
        XCTAssertEqual(CodenamesScreenPhase.of(room), .guess)
        let state = try XCTUnwrap(room.codenames)
        XCTAssertNil(state.key)
        XCTAssertEqual(state.cards.count, 25)
        XCTAssertEqual(state.shownKind(4), .blue)
        XCTAssertNil(state.shownKind(0))
        XCTAssertTrue(state.canGuess)
        XCTAssertEqual(state.clue?.word, "WINTER")
        XCTAssertEqual(state.guessesLeft, 2)
        XCTAssertEqual(state.teams.map(\.team), [.red, .blue])
        XCTAssertEqual(state.side(.blue)?.left, 7)
        XCTAssertEqual(state.myTeam, .blue)
        XCTAssertEqual(room.players.count, 4, "the shared player rows still read")
        XCTAssertNil(room.azul)
        XCTAssertNil(room.oneClue)
    }

    func testASpymastersRoomCarriesTheKey() throws {
        let room = try decode(wire(me: "p_c", key: true))
        let state = try XCTUnwrap(room.codenames)
        XCTAssertEqual(state.key?.count, 25)
        XCTAssertEqual(state.shownKind(0), .assassin)
        XCTAssertTrue(state.amSpymaster)
        XCTAssertFalse(state.canGuess)
    }

    func testTheFinishCarriesTheResultAndTheTeams() throws {
        let room = try decode(wire(me: "p_b", key: true, finished: true))
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(CodenamesScreenPhase.of(room), .finished)
        let state = try XCTUnwrap(room.codenames)
        XCTAssertEqual(state.result?.winner, .blue)
        XCTAssertEqual(state.result?.reason, "assassin")
        XCTAssertEqual(state.standings?.first?.place, 1)
        XCTAssertEqual(state.standing("p_a")?.team, .red)
        XCTAssertEqual(room.winnerIds, ["p_c", "p_d"])
        XCTAssertEqual(room.standings?.count, 2, "the shared standings read the same rows")
    }

    func testANullResultAtTheEndIsCoOpLost() throws {
        let json = wire(me: "p_b", key: true, finished: true)
            .replacingOccurrences(of: #"{"winner":"blue","reason":"assassin"}"#, with: #"{"winner":null,"reason":"agents"}"#)
        let state = try XCTUnwrap(try decode(json).codenames)
        XCTAssertNotNil(state.result)
        XCTAssertNil(state.result?.winner)
    }

    func testTheLobbyListsTheTVBoards() throws {
        let lobby = try JSONDecoder().decode(GamesLobby.self, from: Data(#"""
        {"me":{"id":"p_a","name":"Sam"},"players":[],"invites":[],"rooms":[],"serverNow":1,
         "screens":["azul","quiz-night","codenames"]}
        """#.utf8))
        XCTAssertTrue(GameScreenPairing.offered("quiz-night", lobby: lobby))
        XCTAssertTrue(GameScreenPairing.offered("codenames", lobby: lobby))
        XCTAssertFalse(GameScreenPairing.offered("chess", lobby: lobby))
    }

    func testStartSendsTheLevel() throws {
        let body = CreateGameBody(game: GameKind.codenames.rawValue, difficulty: GameDifficulty.hard.rawValue, invite: ["p_b"])
        let sent = try object(body)
        XCTAssertEqual(sent["game"] as? String, "codenames")
        XCTAssertEqual(sent["difficulty"] as? String, "hard")
        XCTAssertNil(sent["table"])
        XCTAssertNil(sent["pace"])
    }

    func testTheGameIsOnTheShelfUnderTheServersId() {
        XCTAssertEqual(GameKind(rawValue: "codenames"), .codenames)
        XCTAssertEqual(GameKind.codenames.title, "Codenames")
        XCTAssertEqual(GameCategory.of("codenames"), .word)
        XCTAssertEqual(GamesPagePlan.playersChip("codenames", onPhone: false), "2–8")
        XCTAssertFalse(GameKind.codenames.playsOnPhone)
        XCTAssertTrue(GamesPagePlan.newGames.contains("codenames"))
    }

    func testTheDemoRoomsDecode() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        func room(_ id: String) throws -> GameRoom {
            try decode(try XCTUnwrap(SRDemoFixtures.codenamesRoom(id: id, clock: clock)))
        }
        let lobby = try room(SRDemoFixtures.demoCodenamesLobbyRoom)
        XCTAssertEqual(CodenamesScreenPhase.of(lobby), .lobby)
        XCTAssertEqual(lobby.codenames?.mode, .teams)
        XCTAssertEqual(lobby.codenames?.anywhere.map(\.id), ["p_robin"])

        let spy = try XCTUnwrap(try room(SRDemoFixtures.demoCodenamesSpyRoom).codenames)
        XCTAssertEqual(spy.phase, .clue)
        XCTAssertTrue(spy.canClue)
        XCTAssertEqual(spy.key?.count, 25)
        XCTAssertEqual(spy.key?.filter { $0 == .red }.count, 9)
        XCTAssertEqual(spy.key?.filter { $0 == .assassin }.count, 1)
        XCTAssertEqual(spy.side(.red)?.left, 6)
        XCTAssertEqual(spy.clues.count, 4)

        let guess = try XCTUnwrap(try room(SRDemoFixtures.demoCodenamesGuessRoom).codenames)
        XCTAssertEqual(guess.phase, .guess)
        XCTAssertNil(guess.key, "an operative is never sent the key")
        XCTAssertTrue(guess.canGuess)
        XCTAssertTrue(guess.canPass)
        XCTAssertEqual(guess.clue?.word, "WINTER")
        XCTAssertEqual(guess.myTeam, .blue)
        XCTAssertTrue(guess.cards.filter(\.faceDown).allSatisfy { $0.kind == nil })

        let done = try room(SRDemoFixtures.demoCodenamesDoneRoom)
        XCTAssertEqual(CodenamesScreenPhase.of(done), .finished)
        XCTAssertEqual(done.codenames?.result?.winner, .red)
        XCTAssertEqual(done.codenames?.side(.red)?.left, 0)
        XCTAssertEqual(done.codenames?.standings?.count, 4)
        XCTAssertTrue(done.winnerIds.contains(done.meId))

        let routed = SRDemoFixtures.demoRoom(id: SRDemoFixtures.demoCodenamesGuessRoom, meJoined: true, clock: clock)
        XCTAssertTrue(routed.contains("\"game\": \"codenames\""))
        let games = try JSONDecoder().decode(GamesLobby.self, from: Data(SRDemoFixtures.gamesLobby(clock).utf8))
        XCTAssertTrue(games.screens.contains("codenames"))
        XCTAssertTrue(games.screens.contains("quiz-night"))
    }
}
