import XCTest
@testable import SRAppleApp

/// Pass the Plate: the spec's wire contract, the deck the app knows (pinned to
/// the server's), and the little the phone works out itself — what a tap
/// chooses, the turn clock, the sentences.
final class PassThePlateTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    // MARK: - The wire (the spec's JSON)

    private let pickingJSON = #"""
    { "id":"g_p", "game":"pass-the-plate", "difficulty":"easy", "phase":"picking",
      "hostId":"p_a", "meId":"p_b", "rounds":3, "round":2, "turn":3, "handSize":10,
      "direction":"right", "passTo":"p_a", "passFrom":"p_a", "turnMs":40000, "scoringMs":8000, "hints":"gains",
      "kinds":[{"kind":"pancake","name":"Pancake Stack","emoji":"🥞","family":"pair","count":14,"value":0,"rule":"Every two make a pair worth 6."},
               {"kind":"pie4","name":"Family Pie","emoji":"🥧","family":"pie","count":6,"value":4,"rule":"Worth 4."}],
      "startedAt":1790000000000, "phaseEndsAt":1790000040000,
      "hand":[{"uid":7,"kind":"pancake","gain":6},{"uid":9,"kind":"pie4","gain":4}],
      "myPick":[9], "canTakeTwo":false,
      "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"seated":true,"handCount":8,"picked":true,
                  "played":[{"uid":3,"kind":"gravy","boosted":false,"spent":true},{"uid":4,"kind":"pie3","boosted":true,"spent":false}],
                  "iceCream":2,"berries":0,"score":21,"roundSoFar":6,"left":false},
                 {"id":"p_b","name":"John","status":"joined","isHost":false,"seated":true,"handCount":8,"picked":true,
                  "played":[{"uid":5,"kind":"pancake","boosted":false,"spent":false}],
                  "iceCream":0,"berries":0,"score":18,"roundSoFar":0,"left":false}],
      "lastTurn":[{"playerId":"p_a","cards":[{"uid":4,"kind":"pie3"}],"auto":true},
                  {"playerId":"p_b","cards":[{"uid":5,"kind":"pancake"}],"auto":false}],
      "results":[{"round":1,"rows":[{"playerId":"p_a","pancakes":6,"pizza":0,"popcorn":3,"pies":5,"berryCount":4,"berries":7,"scoops":2,"total":21},
                                    {"playerId":"p_b","pancakes":0,"pizza":12,"popcorn":0,"pies":3,"berryCount":1,"berries":3,"scoops":0,"total":18}]}],
      "dessert":null, "standings":null, "winnerIds":[], "serverNow":1790000010000 }
    """#

    func testAPickingRoomDecodesFromTheContract() throws {
        let room = try decode(pickingJSON)
        XCTAssertEqual(room.kind, .passThePlate)
        XCTAssertEqual(room.phase, .unknown, "the shared phase has no `picking`")
        XCTAssertEqual(PassThePlateScreenPhase.of(room), .picking)
        let state = try XCTUnwrap(room.passThePlate)
        XCTAssertEqual(state.phase, .picking)
        XCTAssertEqual(state.round, 2)
        XCTAssertEqual(state.turn, 3)
        XCTAssertEqual(state.direction, "right")
        XCTAssertEqual(state.hints, .gains)
        XCTAssertEqual(state.turnMs, 40_000)
        XCTAssertEqual(state.hand.map(\.uid), [7, 9])
        XCTAssertEqual(state.hand.first?.gain, 6)
        XCTAssertEqual(state.myPick, [9])
        XCTAssertFalse(state.canTakeTwo)
        XCTAssertEqual(state.seat("p_a")?.played.map(\.kind), ["gravy", "pie3"])
        XCTAssertEqual(state.seat("p_a")?.played.last?.boosted, true)
        XCTAssertEqual(state.seat("p_a")?.handCount, 8)
        XCTAssertEqual(state.seat("p_a")?.roundSoFar, 6)
        XCTAssertEqual(state.lastTurn?.first?.auto, true)
        XCTAssertEqual(state.results.first?.rows.map(\.total), [21, 18])
        for row in state.results.flatMap(\.rows) { XCTAssertEqual(row.sum, row.total, "the breakdown adds up") }
        XCTAssertEqual(state.info("pie4").value, 4)
        XCTAssertEqual(state.info("spoon").name, "Serving Spoon", "a kind the room did not send falls back to the app's copy")
        XCTAssertEqual(room.players.first?.score, 21, "the shared player row reads the same score")
    }

    func testAFinishedRoomDecodesStandingsAndDessert() throws {
        let json = #"""
        { "id":"g_p", "game":"pass-the-plate", "difficulty":"hard", "phase":"finished", "hostId":"p_a", "meId":"p_a",
          "hints":"none", "players":[{"id":"p_a","name":"Sam","status":"joined","seated":true,"score":40,"roundSoFar":null},
                                     {"id":"p_b","name":"John","status":"left","seated":true,"score":12,"left":true}],
          "dessert":[{"playerId":"p_a","scoops":3,"points":5}],
          "standings":[{"id":"p_a","name":"Sam","place":1,"score":40,"scoops":3,"left":false},
                       {"id":"p_b","name":"John","place":2,"score":12,"scoops":0,"left":true}],
          "winnerIds":["p_a"], "serverNow":1790000010000 }
        """#
        let room = try decode(json)
        XCTAssertEqual(PassThePlateScreenPhase.of(room), .finished)
        let state = try XCTUnwrap(room.passThePlate)
        XCTAssertEqual(state.hints, PassThePlateHints.none)
        XCTAssertNil(state.seat("p_a")?.roundSoFar)
        XCTAssertEqual(state.seat("p_b")?.left, true)
        XCTAssertEqual(state.dessert?.first?.points, 5)
        XCTAssertEqual(state.standings?.map(\.place), [1, 2])
        XCTAssertEqual(room.standings?.map(\.score), [40, 12], "the shared standings carry the score for the leaderboard")
        XCTAssertEqual(room.winnerIds, ["p_a"])
    }

    func testALobbyWithNoneOfItStillDecodes() throws {
        let json = #"""
        { "id":"g_p", "game":"pass-the-plate", "difficulty":"medium", "phase":"lobby",
          "hostId":"p_a", "meId":"p_a", "players":[{"id":"p_a","name":"Sam","status":"joined"}],
          "serverNow":1790000010000 }
        """#
        let room = try decode(json)
        XCTAssertEqual(PassThePlateScreenPhase.of(room), .lobby)
        let state = try XCTUnwrap(room.passThePlate)
        XCTAssertEqual(state.rounds, 3)
        XCTAssertEqual(state.hand, [])
        XCTAssertEqual(state.results, [])
    }

    func testOtherGamesCarryNoPlate() throws {
        XCTAssertNil(try decode(#"{ "id":"g_t", "game":"tap-duel", "phase":"lobby", "serverNow":1 }"#).passThePlate)
    }

    func testPhases() {
        XCTAssertEqual(PassThePlatePhase.from("picking"), .picking)
        XCTAssertEqual(PassThePlatePhase.from("scoring"), .scoring)
        XCTAssertEqual(PassThePlatePhase.from("something-new"), .unknown)
        XCTAssertEqual(PassThePlatePhase.from(nil), .unknown)
    }

    // MARK: - Pinned to the server

    func testTheGameIdIsTheServers() {
        XCTAssertEqual(GameKind(rawValue: "pass-the-plate"), .passThePlate)
        XCTAssertEqual(GameKind.passThePlate.title, "Pass the Plate")
    }

    /// SR-Main `src/lib/games/pass-the-plate.ts` `KINDS`, in order.
    func testTheDeckKindsAreTheServers() {
        XCTAssertEqual(PlateDeck.kinds, ["pancake", "pizza", "popcorn", "berry1", "berry2", "berry3",
                                         "pie2", "pie3", "pie4", "gravy", "spoon", "icecream"])
        for kind in PlateDeck.kinds {
            let info = PlateDeck.fallback(kind)
            XCTAssertFalse(info.name.isEmpty)
            XCTAssertFalse(info.emoji.isEmpty)
            XCTAssertNotEqual(info.name, "A card", "\(kind) has no copy in the app")
        }
    }

    func testEveryLevelSaysSomething() {
        for level in GameDifficulty.allCases {
            XCTAssertTrue(level.line(for: .passThePlate).contains("a turn"))
        }
        XCTAssertEqual(PassThePlateSettings.about(difficulty: "easy"), "Three rounds · simple deck · hints on")
    }

    // MARK: - Choosing

    func testATapChoosesOneCard() {
        XCTAssertEqual(PassThePlateRules.toggle(7, in: [], takeTwo: false), [7])
        XCTAssertEqual(PassThePlateRules.toggle(9, in: [7], takeTwo: false), [9])
        XCTAssertTrue(PassThePlateRules.ready([9], takeTwo: false))
    }

    func testTheSpoonHoldsUpToTwo() {
        var chosen = PassThePlateRules.toggle(7, in: [], takeTwo: true)
        XCTAssertEqual(chosen, [7])
        XCTAssertFalse(PassThePlateRules.ready(chosen, takeTwo: true))
        chosen = PassThePlateRules.toggle(9, in: chosen, takeTwo: true)
        XCTAssertEqual(chosen, [7, 9])
        XCTAssertTrue(PassThePlateRules.ready(chosen, takeTwo: true))
        XCTAssertEqual(PassThePlateRules.toggle(7, in: [7], takeTwo: true), [], "a second tap takes it back")
        XCTAssertEqual(PassThePlateRules.toggle(3, in: [7, 9], takeTwo: true), [9, 3], "never more than two")
    }

    func testTheActionBodyCarriesTheCards() throws {
        let data = try JSONEncoder().encode(GameActionBody(action: "pick", cards: [7, 9]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["action"] as? String, "pick")
        XCTAssertEqual(json["cards"] as? [Int], [7, 9])
        XCTAssertNil(json["index"])
    }

    // MARK: - Sentences and the clock

    func testSentences() {
        XCTAssertEqual(PassThePlateRules.passLine(direction: "right", to: "Sam"), "Plates go right, to Sam.")
        XCTAssertEqual(PassThePlateRules.passLine(direction: "left", to: nil), "Plates go left.")
        XCTAssertEqual(PassThePlateRules.waitingLine(["Sam", "Kim"]), "Waiting for Sam and Kim…")
        XCTAssertNil(PassThePlateRules.waitingLine([]))
        XCTAssertEqual(PassThePlateRules.gainText(6), "+6")
        XCTAssertNil(PassThePlateRules.gainText(nil))
        let pie = PlateDeck.fallback("pie4")
        XCTAssertEqual(PassThePlateRules.spoken(pie, gain: 4, chosen: true), "Family Pie. Adds 4 points. Chosen")
        XCTAssertEqual(PassThePlateRules.spoken(pie, gain: nil, chosen: false), "Family Pie")
    }

    func testTheBreakdownLineSkipsZeros() throws {
        let room = try decode(pickingJSON)
        let row = try XCTUnwrap(room.passThePlate?.results.first?.rows.first)
        XCTAssertEqual(PassThePlateRules.breakdownLine(row), "Pancakes 6 · Popcorn 3 · Pies 5 · Berries 7")
    }

    func testTheTurnClock() {
        XCTAssertEqual(PassThePlateRules.turnLeft(endsAt: 40_000, turnMs: 40_000, now: 20_000), 0.5)
        XCTAssertEqual(PassThePlateRules.turnLeft(endsAt: 40_000, turnMs: 40_000, now: 90_000), 0)
        XCTAssertEqual(PassThePlateRules.turnLeft(endsAt: nil, turnMs: 40_000, now: 1), 1)
    }

    // MARK: - The demo rooms

    func testTheDemoRoomsDecodeAndAddUp() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let playing = try decode(SRDemoFixtures.plateRoom(finished: false, clock: clock))
        let live = try XCTUnwrap(playing.passThePlate)
        XCTAssertEqual(live.phase, .picking)
        XCTAssertEqual(live.hand.count, 6)
        XCTAssertTrue(live.canTakeTwo)
        XCTAssertEqual(live.kinds.map(\.kind), PlateDeck.kinds)

        let done = try decode(SRDemoFixtures.plateRoom(finished: true, clock: clock))
        let state = try XCTUnwrap(done.passThePlate)
        XCTAssertEqual(state.results.count, 3)
        for row in state.results.flatMap(\.rows) { XCTAssertEqual(row.sum, row.total) }
        for standing in state.standings ?? [] {
            let rounds = state.results.compactMap { r in r.rows.first { $0.playerId == standing.id }?.total }
            let dessert = state.dessert?.first { $0.playerId == standing.id }?.points ?? 0
            XCTAssertEqual(rounds.reduce(0, +) + dessert, standing.score, "\(standing.name)'s total")
            XCTAssertEqual(state.seat(standing.id)?.score, standing.score)
        }
        XCTAssertEqual(done.winnerIds, ["p_alex"])
    }
}
