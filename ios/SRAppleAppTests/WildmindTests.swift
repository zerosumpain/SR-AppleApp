import XCTest
@testable import SRAppleApp

/// The Wildmind page reads a game that keeps growing, so its decoders are
/// tested for what they keep AND for what they shrug off.
///
/// The example is the SR-Main contract's own (`GET /api/native/wildmind`,
/// SR-Main #1178), with a few bad rows added: a valley must still draw when a
/// row is new or broken. The same checks run on Linux against these files in
/// the build's harness; these are the ones that run with the app.
final class WildmindTests: XCTestCase {

    private let example = """
    {"state":"live","ageSeconds":0,"snapshot":{"v":1,"status":"running","terrainVersion":"23076.6067.0",
    "time":{"day":16,"season":"spring","dayOfSeason":6,"hour":22.4,"daylight":0,"weather":"rain","tempC":7},
    "people":[{"id":"main","name":"JKai","x":13.2,"z":-20.5,"heading":0.79,"activity":"sleeping","alive":true,
    "thinking":false,"near":"Tusker Wood","trail":[[12.4,-20.9],[13.2,-20.5]],"morale":"getting-by","doing":"asleep"},
    {"id":"companion","name":"Wren","x":14.0,"z":-20.0,"heading":-1.2,"activity":"working","alive":true,"thinking":true,
    "near":null,"trail":[],"morale":"good","doing":"at work"}],
    "species":["rabbit","deer","boar","duck","wolf"],"animals":[[1,14.5,-19.6,0],["bad"]],
    "structures":[[13,-20,1,1,"shelter"],[1,2,0,0,"windmill"]],"fires":[],
    "stats":{"generation":3,"earlierLives":[{"n":2,"days":2.9,"cause":"starvation"},{"n":1,"days":32.3,"cause":"cold"}],
    "invented":7,"latest":[{"name":"Reed basket","kind":"container","day":8,"by":"companion"}],
    "refused":1,"placesFound":15,"exploredTiles":6067,"built":{"shelter":42,"store":1,"fire":0,"pen":0,"other":0},
    "tamed":0,"milestones":{"met":false,"partners":false,"shelter":true,"fire":false,"store":true,"pen":false},
    "choices":{"thought":179,"habit":220},"models":{"mind":"claude-haiku-5-5","designer":"claude-sonnet-5-5"}}},
    "terrain":{"origin":[12,-21],"step":1,"w":3,"h":2,
    "terrains":["deep_sea","shallow_sea","deep_fresh","shallow_fresh","sand","grass","forest","marsh","rock","path",
    "farmland","snow","tundra","volcanic","jungle"],
    "t":"BgYHAQAF","height":"GRooDwAV","regions":[{"n":"Tusker Wood","k":"h","x":14,"z":-21}]}}
    """

    private func decode() throws -> WildmindAnswer {
        try JSONDecoder().decode(WildmindAnswer.self, from: Data(example.utf8))
    }

    func testTheContractExampleDecodes() throws {
        let answer = try decode()
        XCTAssertEqual(answer.state, .live)
        let snapshot = try XCTUnwrap(answer.snapshot)
        XCTAssertEqual(snapshot.terrainVersion, "23076.6067.0")
        XCTAssertEqual(snapshot.main?.name, "JKai")
        XCTAssertEqual(snapshot.companion?.name, "Wren")
        XCTAssertEqual(snapshot.people.first?.trail.count, 2)
        XCTAssertEqual(snapshot.stats.models.mind, "Haiku")
        XCTAssertEqual(snapshot.stats.models.designer, "Sonnet")
        XCTAssertEqual(snapshot.stats.habit, .aboutHalf)
        XCTAssertEqual(snapshot.stats.met, false)
        XCTAssertTrue(snapshot.time.isNight)
    }

    /// A broken row is stepped over; a new structure class is "other".
    func testBadRowsAreDroppedNotFatal() throws {
        let snapshot = try XCTUnwrap(try decode().snapshot)
        XCTAssertEqual(snapshot.animals.count, 1)
        XCTAssertEqual(snapshot.structures.count, 2)
        XCTAssertEqual(snapshot.structures[1].kind, .other)
        XCTAssertTrue(snapshot.structures[0].lit)
    }

    func testTheOfflineBodyAndUnknownStates() throws {
        let offline = try JSONDecoder().decode(
            WildmindAnswer.self,
            from: Data(#"{"state":"offline","ageSeconds":null,"snapshot":null,"terrain":null}"#.utf8)
        )
        XCTAssertEqual(offline.state, .offline)
        XCTAssertNil(offline.snapshot)
        XCTAssertEqual(WildmindState(raw: "between-lives"), .betweenLives)
        XCTAssertEqual(WildmindState(raw: "dozing"), .unknown)
        XCTAssertEqual(WildmindState.live.cadence, 10)
        XCTAssertEqual(WildmindState.resting.cadence, 30)
        XCTAssertEqual(WildmindState.stale.cadence, 60)
    }

    /// The contract's own decoding: `t` is `[6,6,7, 1,0,5]` (grass, grass,
    /// forest / deep sea, unseen, sand); heights 0.5, 0.6, 2.0 / -0.5, -, 0.1.
    func testTheGridDecodesRowMajor() throws {
        let answer = try decode()
        let terrain = try XCTUnwrap(answer.terrain)
        XCTAssertEqual(WildmindGrid.bytes(base64: terrain.t), [6, 6, 7, 1, 0, 5])
        XCTAssertEqual(WildmindGrid.bytes(base64: terrain.height), [25, 26, 40, 15, 0, 21])
        let grid = try XCTUnwrap(WildmindGrid(terrain: terrain, version: "23076.6067.0"))
        XCTAssertEqual(grid.ground(0, 0), .open)
        XCTAssertEqual(grid.ground(2, 0), .wood)
        XCTAssertEqual(grid.ground(0, 1), .sea)
        XCTAssertEqual(grid.ground(1, 1), .unseen)
        XCTAssertEqual(grid.ground(2, 1), .shore)
        XCTAssertEqual(try XCTUnwrap(grid.height(2, 0)), 2.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(grid.height(0, 1)), -0.5, accuracy: 1e-9)
        XCTAssertNil(grid.height(1, 1))
        // World tiles to cells: tile centres sit mid-cell.
        let cell = grid.cell(x: 13.2, z: -20.5)
        XCTAssertEqual(cell.x, 1.7, accuracy: 1e-9)
        XCTAssertEqual(cell.y, 1.0, accuracy: 1e-9)
    }

    /// A plane that does not add up to `w × h` is no map, not a wrong one.
    func testAShortGridIsRefused() throws {
        var terrain = try XCTUnwrap(try decode().terrain)
        terrain.t = "BgYH"
        XCTAssertNil(WildmindGrid(terrain: terrain, version: "x"))
        XCTAssertNil(WildmindGrid.bytes(base64: "!!!!"))
    }

    func testTheCoastAndTheEdgeOfTheKnown() throws {
        let grid = try XCTUnwrap(WildmindGrid(terrain: try XCTUnwrap(try decode().terrain), version: "v"))
        let lines = WildmindOutline.lines(grid)
        XCTAssertEqual(lines.coast, [WildmindSegment(x0: 0, y0: 1, x1: 1, y1: 1)])
        XCTAssertTrue(lines.edge.contains(WildmindSegment(x0: 0, y0: 0, x1: 3, y1: 0)))
    }

    /// A map much wider than tall is turned a quarter on the phone, west at
    /// the top, as the site turns it.
    func testAWideMapTurns() {
        let shape = WildmindMapShape(w: 3, h: 2)
        XCTAssertTrue(shape.turned)
        XCTAssertEqual(shape.width, 2)
        XCTAssertEqual(shape.height, 3)
        let placed = shape.place(1.7, 1.0)
        XCTAssertEqual(placed.x, 1.0, accuracy: 1e-9)
        XCTAssertEqual(placed.y, 1.7, accuracy: 1e-9)
        XCTAssertFalse(WildmindMapShape(w: 46, h: 40).turned)
    }

    func testTheWordsFollowTheSitesRules() throws {
        XCTAssertEqual(WildmindWords.count(23), "twenty-three")
        XCTAssertEqual(WildmindWords.count(0), "no")
        XCTAssertEqual(WildmindWords.ordinal(16), "sixteenth")
        XCTAssertEqual(WildmindWords.ordinal(21), "twenty-first")
        XCTAssertEqual(WildmindWords.roman(4), "iv")
        let snapshot = try XCTUnwrap(try decode().snapshot)
        XCTAssertEqual(WildmindWords.daySentence(snapshot.time), "Day sixteen of this life, a wet spring night.")
        XCTAssertEqual(WildmindWords.lifeLine(snapshot.stats.earlierLives[1]),
                       "the first lasted thirty-two days and died of the cold")
        XCTAssertEqual(WildmindWords.tag(snapshot.people[0], pastTense: true), "JKai was asleep")
        // No digits in the fixed copy of the caption.
        let caption = WildmindWords.caption(snapshot, state: .live)
        XCTAssertNil(caption.rangeOfCharacter(from: .decimalDigits), caption)
    }

    /// The `-SRDemo` valley: a whole answer, and none of the grid when the
    /// phone already holds its version.
    func testTheDemoValley() throws {
        let base = "https://strangeramblings.com/"
        let full = SRDemoFixtures.reply(method: "GET", url: URL(string: base + "api/native/wildmind")!, body: nil)
        XCTAssertEqual(full.status, 200)
        let answer = try JSONDecoder().decode(WildmindAnswer.self, from: full.body)
        let snapshot = try XCTUnwrap(answer.snapshot)
        let version = try XCTUnwrap(snapshot.terrainVersion)
        let grid = try XCTUnwrap(WildmindGrid(terrain: try XCTUnwrap(answer.terrain), version: version))
        XCTAssertEqual(snapshot.people.count, 2)
        func ground(_ x: Double, _ z: Double) -> WildmindGround {
            let cell = grid.cell(x: x, z: z)
            return grid.ground(Int(cell.x), Int(cell.y))
        }
        // The showcase draws all of this, so nothing may stand in the stream
        // or out on blank paper beyond what has been explored.
        for person in snapshot.people {
            let at = ground(person.x, person.z)
            XCTAssertTrue(at.isSeen && !at.isWater, "\(person.name) should stand on seen land")
            for point in person.trail {
                let step = ground(point.x, point.z)
                XCTAssertTrue(step.isSeen && !step.isWater, "\(person.name)'s trail should keep to seen land")
            }
        }
        for structure in snapshot.structures {
            let at = ground(structure.x, structure.z)
            XCTAssertTrue(at.isSeen && !at.isWater, "the \(structure.kind) should stand on seen land")
        }
        for animal in snapshot.animals {
            XCTAssertTrue(ground(animal.x, animal.z).isSeen, "an animal should be inside the explored ground")
        }
        XCTAssertEqual(grid.regions.count, 4)

        let held = SRDemoFixtures.reply(
            method: "GET", url: URL(string: base + "api/native/wildmind?have=\(version)")!, body: nil
        )
        let again = try JSONDecoder().decode(WildmindAnswer.self, from: held.body)
        XCTAssertNotNil(again.snapshot)
        XCTAssertNil(again.terrain)
    }

    /// The owner lane's demo routes reach `WildmindDemoLane` through the
    /// fixtures' front door, a POST body included; anything else under
    /// `api/native/wildmind/` is still a 404.
    func testTheDemoOwnerLaneIsRouted() throws {
        let base = "https://strangeramblings.com/api/native/wildmind/"
        WildmindDemoLane.shared.reset()
        defer { WildmindDemoLane.shared.reset() }
        for path in ["talk?limit=20", "chronicle?id=companion", "inventions", "whispers?limit=5"] {
            let reply = SRDemoFixtures.reply(method: "GET", url: URL(string: base + path)!, body: nil)
            XCTAssertEqual(reply.status, 200, path)
        }
        let talk = try JSONDecoder().decode(
            WildmindTalkPage.self,
            from: SRDemoFixtures.reply(method: "GET", url: URL(string: base + "talk?kinds=diary")!, body: nil).body
        )
        XCTAssertTrue(talk.entries.allSatisfy { $0.kind == .diary })
        let sent = SRDemoFixtures.reply(method: "POST", url: URL(string: base + "whisper")!, body: Data(#"{"text":"Hello"}"#.utf8))
        XCTAssertEqual(sent.status, 200)
        XCTAssertEqual(try JSONDecoder().decode(WildmindWhisperAccepted.self, from: sent.body).pending, ["Hello"])
        XCTAssertEqual(SRDemoFixtures.reply(method: "GET", url: URL(string: base + "whisper")!, body: nil).status, 404)
        XCTAssertEqual(SRDemoFixtures.reply(method: "GET", url: URL(string: base + "talk/extra")!, body: nil).status, 404)
        XCTAssertEqual(SRDemoFixtures.reply(method: "POST", url: URL(string: String(base.dropLast()))!, body: nil).status, 404)
    }

    /// `?have=` goes into the query as it is, so only the site's own version
    /// shape is ever sent back.
    func testOnlyASafeVersionIsSentBack() {
        XCTAssertTrue(WildmindStore.isSafeVersion("23076.6067.0"))
        XCTAssertFalse(WildmindStore.isSafeVersion(""))
        XCTAssertFalse(WildmindStore.isSafeVersion("a&b=c"))
        XCTAssertFalse(WildmindStore.isSafeVersion("caf\u{E9}"))
        XCTAssertFalse(WildmindStore.isSafeVersion(String(repeating: "a", count: 65)))
    }
}
