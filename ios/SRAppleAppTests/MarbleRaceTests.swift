import XCTest
@testable import SRAppleApp

/// Marble Race: the site's wire contract (SR-Main `marble-race.ts` `toWire`),
/// the race handed to Marbler's page, the course the host sends, and today's
/// course matching the page's own pick.
final class MarbleRaceTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    private let racingJSON = #"""
    { "id":"g_m", "game":"marble-race", "difficulty":"easy", "phase":"racing",
      "hostId":"p_a", "meId":"p_b",
      "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"marble":2,"reported":true},
                 {"id":"p_b","name":"John","status":"joined","isHost":false,"marble":5,"reported":false},
                 {"id":"p_c","name":"Kim","status":"declined","isHost":false,"marble":null,"reported":false}],
      "course":{"id":"c9006","name":"Rusted Foundry","marbles":11,"seconds":107},
      "race":{"seed":4294967295,"startAt":1790000006000},
      "result":null, "phaseEndsAt":1790000327000,
      "standings":null, "winnerIds":[], "serverNow":1790000016000 }
    """#

    func testARacingRoomDecodesFromTheContract() throws {
        let room = try decode(racingJSON)
        XCTAssertEqual(room.kind, .marbleRace)
        XCTAssertEqual(room.phase, .unknown, "the shared enum does not know `racing`")
        let state = try XCTUnwrap(room.marbleRace)
        XCTAssertEqual(state.phase, .racing)
        XCTAssertEqual(state.course, .init(id: "c9006", name: "Rusted Foundry", marbles: 11, seconds: 107))
        XCTAssertEqual(state.race?.seed, 4_294_967_295, "a seed is a full unsigned 32-bit number")
        XCTAssertEqual(state.marble(of: "p_b"), 5)
        XCTAssertEqual(state.backer(of: 2), "p_a")
        XCTAssertNil(state.backer(of: 0))
        XCTAssertNil(state.result)
    }

    func testAnotherGamesRoomHasNoMarbleRace() throws {
        let room = try decode(#"{"id":"g_t","game":"tap-duel","phase":"lobby","serverNow":1}"#)
        XCTAssertNil(room.marbleRace)
    }

    func testTheFinishReadsPlacesFromTheAgreedOrder() throws {
        let json = racingJSON
            .replacingOccurrences(of: #""phase":"racing""#, with: #""phase":"finished""#)
            .replacingOccurrences(of: #""result":null"#, with: #""result":{"order":[5,0,1,2,3,4,6,7,8,9,10],"disputed":true}"#)
        let state = try XCTUnwrap(try decode(json).marbleRace)
        XCTAssertEqual(state.phase, .finished)
        XCTAssertEqual(state.place(of: 5), 1)
        XCTAssertEqual(state.place(of: 2), 4)
        XCTAssertEqual(state.result?.disputed, true)
    }

    func testThePageIsHandedTheRaceAsTheRoomsClockHasIt() throws {
        let room = try decode(racingJSON)
        let state = try XCTUnwrap(room.marbleRace)
        let script = try XCTUnwrap(MarbleRaceBridge.script(room: room, state: state, elapsed: 10))
        XCTAssertTrue(script.hasPrefix("room({"), script)
        let json = String(script.dropFirst("room(".count).dropLast())
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(payload["course"] as? String, "c9006")
        XCTAssertEqual((payload["seed"] as? NSNumber)?.uint32Value, 4_294_967_295)
        XCTAssertEqual(payload["elapsed"] as? Double, 10)
        XCTAssertEqual(payload["you"] as? Int, 5)
        let backers = try XCTUnwrap(payload["backers"] as? [[String: Any]])
        XCTAssertEqual(backers.map { $0["name"] as? String }, ["Sam", "John"])
        XCTAssertEqual(backers.map { $0["marble"] as? Int }, [2, 5])
    }

    func testNoRaceIsHandedOverBeforeOneIsDealt() throws {
        let json = racingJSON
            .replacingOccurrences(of: #""phase":"racing""#, with: #""phase":"picking""#)
            .replacingOccurrences(of: #""race":{"seed":4294967295,"startAt":1790000006000}"#, with: #""race":null"#)
        let room = try decode(json)
        XCTAssertNil(MarbleRaceBridge.script(room: room, state: try XCTUnwrap(room.marbleRace), elapsed: 0))
    }

    func testTheHostSendsTheCourseTheyPicked() throws {
        let course = MarblerPack.Entry(id: "c9010", name: "Copper Cascade", layout: "relay", marbles: 12, seconds: 224)
        let body = MarbleRaceSettings(difficulty: .easy, course: course).createBody(invite: ["p_b"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(json["game"] as? String, "marble-race")
        let sent = try XCTUnwrap(json["course"] as? [String: Any])
        XCTAssertEqual(sent["id"] as? String, "c9010")
        XCTAssertEqual(sent["name"] as? String, "Copper Cascade")
        XCTAssertEqual(sent["marbles"] as? Int, 12)
        XCTAssertEqual(sent["seconds"] as? Int, 224)
        XCTAssertNil(json["seconds"], "the course's length is not Boggle's clock")
    }

    func testTodaysCourseIsThePagesPick() throws {
        // The page: Math.floor(Date.UTC(y, m, d) / 86_400_000) % courses (local date).
        let entries = (1...10).map { MarblerPack.Entry(id: "c900\($0)", name: "C\($0)", layout: "relay", marbles: 8, seconds: 120) }
        let pack = MarblerPack(courses: entries)
        let noon = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12)))
        // 2026-10-20 is day 20,746 since 1970; 20,746 % 10 = 6.
        XCTAssertEqual(pack.today(noon)?.id, entries[6].id)
    }

    func testTheGameIsOnTheShelf() {
        XCTAssertEqual(GameKind(rawValue: "marble-race"), .marbleRace)
        XCTAssertEqual(GameKind.marbleRace.title, "Marble Race")
        XCTAssertEqual(MarblePalette.name(0), "Red")
        XCTAssertEqual(MarblePalette.colours.count, 30, "Marbler's palette: one colour per marble, up to 30")
    }
}
