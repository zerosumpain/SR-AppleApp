import XCTest
@testable import SRAppleApp

/// Azul: the spec's wire contract (SR-Main `azul.ts` `toWire`), and the little
/// the phone works out itself — the wall's colours, the lit lines, what a take
/// would spill, the floor's cost and the bonuses in words — plus the TV code
/// field (`GameScreenCode`). Pure: these run on Linux in `home-check.sh`.
final class AzulLogicTests: XCTestCase {

    private func decode(_ json: String) throws -> AzulState {
        try JSONDecoder().decode(AzulState.self, from: Data(json.utf8))
    }

    // MARK: - The wire

    private let playingJSON = #"""
    { "id":"g_a", "game":"azul", "difficulty":"medium", "phase":"playing", "hostId":"p_a", "meId":"p_b",
      "table":"tv", "turnMs":90000, "deadlineHours":null, "startedAt":1790000000000, "phaseEndsAt":1790000090000,
      "round":2, "lastRound":false, "turnId":"p_b", "turnStartedAt":1790000000000,
      "colours":["blue","yellow","red","black","white"],
      "factories":[[{"id":3,"c":"blue"},{"id":4,"c":"blue"},{"id":25,"c":"yellow"},{"id":61,"c":"black"}],[]],
      "centre":[{"id":45,"c":"red"},{"id":82,"c":"white"}], "firstInCentre":true, "bag":40, "lid":3,
      "canPlace":{"blue":[0,2,4],"yellow":[1],"red":[],"black":[3,9],"white":[0]},
      "last":{"by":"p_a","source":1,"colour":"red","tiles":[44],"line":"floor","overflow":1,"toCentre":[45,82],
              "tookFirst":false,"auto":true,"at":1789999990000},
      "roundScores":null,
      "log":[{"n":1,"at":1789999000000,"by":null,"text":"Round 2. Sam to start.","auto":false},
             {"n":2,"at":1789999990000,"by":"p_a","text":"Sam took 1 red from factory 2 → the floor.","auto":true}],
      "players":[
        {"id":"p_a","name":"Sam","status":"joined","isHost":true,"seat":0,"score":7,"away":true,
         "lines":[[],[{"id":21,"c":"yellow"}],[],[],[]],
         "wall":[[1,null,null,null,null],[null,null,null,null,null],[null,null,null,null,null],[null,null,null,null,null],[null,null,null,null,null]],
         "floor":[{"id":44,"c":"red"}],"floorPenalty":1,"rows":0,"hasFirst":false},
        {"id":"p_b","name":"John","status":"joined","isHost":false,"seat":1,"score":4,"away":false,
         "lines":[[],[],[{"id":5,"c":"blue"}],[{"id":62,"c":"black"},{"id":63,"c":"black"}],[]],
         "wall":[[null,null,null,null,null],[null,null,41,null,null],[null,null,null,null,null],[null,null,null,null,null],[null,null,null,null,null]],
         "floor":[],"floorPenalty":0,"rows":0,"hasFirst":false},
        {"id":"p_c","name":"Kit","status":"joined","isHost":false,"seat":2,"score":0,"away":false,
         "lines":[[],[],[],[],[]],"wall":[],"floor":[],"floorPenalty":0,"rows":0,"hasFirst":false}],
      "result":null, "standings":null, "winnerIds":[], "serverNow":1790000010000 }
    """#

    func testAPlayingRoomDecodesFromTheContract() throws {
        let state = try decode(playingJSON)
        XCTAssertEqual(state.phase, .playing)
        XCTAssertEqual(state.meId, "p_b")
        XCTAssertEqual(state.table, .tv)
        XCTAssertEqual(state.turnMs, 90_000)
        XCTAssertNil(state.deadlineHours)
        XCTAssertFalse(state.isAsync)
        XCTAssertEqual(state.round, 2)
        XCTAssertEqual(state.turnId, "p_b")
        XCTAssertEqual(state.factories.count, 2)
        XCTAssertEqual(state.factories[0].map(\.id), [3, 4, 25, 61])
        XCTAssertTrue(state.factories[1].isEmpty)
        XCTAssertEqual(state.centre.map(\.c), ["red", "white"])
        XCTAssertTrue(state.firstInCentre)
        XCTAssertEqual(state.bag, 40)
        XCTAssertEqual(state.lid, 3)
        XCTAssertEqual(state.canPlace["blue"], [0, 2, 4])
        XCTAssertEqual(state.log.map(\.n), [1, 2])
        XCTAssertTrue(state.log[1].auto)
        let last = try XCTUnwrap(state.last)
        XCTAssertEqual(last.source, .factory(1))
        XCTAssertEqual(last.line, .floor)
        XCTAssertEqual(last.toCentre, [45, 82])
        XCTAssertTrue(last.auto)
        let sam = try XCTUnwrap(state.board("p_a"))
        XCTAssertTrue(sam.away)
        XCTAssertEqual(sam.floorPenalty, 1)
        XCTAssertEqual(sam.colour(ofLine: 1), "yellow")
        XCTAssertEqual(sam.wallTile(0, 0), 1)
        XCTAssertNil(sam.wallTile(0, 1))
        let kit = try XCTUnwrap(state.board("p_c"))
        XCTAssertEqual(kit.wall.count, 5, "an empty wall is filled out to 5×5")
        XCTAssertTrue(kit.wall.allSatisfy { $0.count == 5 })
        XCTAssertEqual(state.seated.map(\.id), ["p_a", "p_b", "p_c"])
        XCTAssertEqual(state.others(after: "p_b").map(\.id), ["p_c", "p_a"], "the others in the order they move after me")
    }

    func testTheSourceAndLineReadEitherKind() throws {
        let json = #"{"phase":"playing","last":{"by":"p_a","source":"centre","colour":"blue","tiles":[1,2],"line":3,"overflow":0,"toCentre":[],"tookFirst":true,"auto":false,"at":1}}"#
        let last = try XCTUnwrap(try decode(json).last)
        XCTAssertEqual(last.source, .centre)
        XCTAssertEqual(last.line, .line(3))
        XCTAssertTrue(last.tookFirst)
    }

    func testAScoringRoomCarriesEachRound() throws {
        let json = #"""
        {"phase":"scoring","round":3,"lastRound":true,
         "roundScores":[{"id":"p_a","placements":[{"line":0,"col":2,"tile":44,"points":3},{"line":2,"col":4,"tile":7,"points":1}],
                         "floor":2,"before":10,"after":12}],
         "players":[{"id":"p_a","name":"Sam","seat":0,"score":12,"floor":[{"id":100,"c":"first"},{"id":9,"c":"blue"}]}]}
        """#
        let state = try decode(json)
        XCTAssertEqual(state.phase, .scoring)
        XCTAssertTrue(state.lastRound)
        let score = try XCTUnwrap(state.roundScore("p_a"))
        XCTAssertEqual(score.gained, 4)
        XCTAssertEqual(score.delta, 2)
        XCTAssertEqual(score.placements.map(\.tile), [44, 7])
        let sam = try XCTUnwrap(state.board("p_a"))
        XCTAssertTrue(sam.hasFirst, "derived from the marker on the floor when the field is absent")
        XCTAssertEqual(sam.floorPenalty, 2)
        XCTAssertTrue(sam.floor[0].isMarker)
        XCTAssertEqual(state.markerHolder, "p_a")
    }

    func testAFinishedRoomCarriesStandingsAndBonuses() throws {
        let json = #"""
        {"phase":"finished","result":{"winnerIds":["p_a"],"reason":"wall"},
         "standings":[{"id":"p_a","name":"Sam","place":1,"score":61,"rows":1,"bonus":{"rows":1,"columns":1,"colours":0,"points":9},"result":"won"},
                      {"id":"p_b","name":"John","place":2,"score":40,"rows":0,"bonus":null,"result":"lost"}]}
        """#
        let state = try decode(json)
        XCTAssertEqual(state.phase, .finished)
        XCTAssertEqual(state.result?.winnerIds, ["p_a"])
        XCTAssertEqual(state.result?.reason, "wall")
        XCTAssertEqual(state.standing("p_a")?.bonus?.points, 9)
        XCTAssertNil(state.standing("p_b")?.bonus)
        XCTAssertEqual(state.standing("p_b")?.result, "lost")
    }

    func testAnAlmostEmptyRoomStillDecodes() throws {
        let state = try decode(#"{"phase":"lobby"}"#)
        XCTAssertEqual(state.phase, .lobby)
        XCTAssertEqual(state.table, .phones)
        XCTAssertEqual(state.colours, AzulRules.colours)
        XCTAssertTrue(state.players.isEmpty)
        XCTAssertTrue(state.canPlace.isEmpty)
        XCTAssertEqual(AzulPhase.from("glacial"), .unknown)
        XCTAssertEqual(AzulTable.from(nil), .phones)
    }

    func testAsyncCarriesTheHostsHours() throws {
        let state = try decode(#"{"phase":"playing","deadlineHours":24,"turnMs":86400000}"#)
        XCTAssertTrue(state.isAsync)
        XCTAssertEqual(state.deadlineHours, 24)
    }

    // MARK: - The wall

    func testTheWallPatternIsColourMinusRow() {
        XCTAssertEqual((0..<5).map { AzulRules.wallColour(row: 0, col: $0) }, ["blue", "yellow", "red", "black", "white"])
        XCTAssertEqual((0..<5).map { AzulRules.wallColour(row: 1, col: $0) }, ["white", "blue", "yellow", "red", "black"])
        XCTAssertEqual(AzulRules.wallColour(row: 4, col: 0), "yellow")
        for row in 0..<5 {
            for colour in AzulRules.colours {
                let col = AzulRules.wallColumn(row: row, colour: colour)
                XCTAssertEqual(col.map { AzulRules.wallColour(row: row, col: $0) }, colour, "row \(row) \(colour)")
            }
            XCTAssertEqual(Set((0..<5).map { AzulRules.wallColour(row: row, col: $0) }).count, 5, "each colour once a row")
        }
        XCTAssertNil(AzulRules.wallColumn(row: 0, colour: "green"))
    }

    func testEveryColourHasItsOwnGlyph() {
        let glyphs = AzulRules.colours.map(AzulRules.glyph)
        XCTAssertEqual(Set(glyphs).count, 5)
        XCTAssertFalse(glyphs.contains(AzulRules.glyph(AzulRules.marker)))
    }

    // MARK: - Lit lines and the preview

    func testLitLinesAreExactlyWhatTheServerSent() {
        let canPlace = ["blue": [0, 2, 4], "black": [3, 9, -1]]
        XCTAssertEqual(AzulRules.litLines(canPlace, colour: "blue"), [0, 2, 4])
        XCTAssertEqual(AzulRules.litLines(canPlace, colour: "black"), [3], "nothing outside 0–4")
        XCTAssertEqual(AzulRules.litLines(canPlace, colour: "red"), [], "a colour not sent lights nothing")
    }

    func testColoursAtASourceAreInTheWallsOrder() {
        let tiles = [AzulTile(id: 1, c: "white"), AzulTile(id: 2, c: "blue"), AzulTile(id: 3, c: "white")]
        XCTAssertEqual(AzulRules.coloursAt(tiles), ["blue", "white"])
        XCTAssertEqual(AzulRules.tiles("white", in: tiles).map(\.id), [1, 3])
    }

    private func board(lines: [[AzulTile]] = [], floor: Int = 0) -> AzulBoard {
        AzulBoard(id: "p", name: "P", lines: lines, floor: (0..<floor).map { AzulTile(id: 200 + $0, c: "red") })
    }

    func testASpillOntoALine() {
        let b = board(lines: [[], [], [AzulTile(id: 1, c: "blue")], [], []])
        let s = AzulRules.spill(count: 4, onto: .line(2), of: b)
        XCTAssertEqual(s.fit, 2)
        XCTAssertEqual(s.floor, 2)
        XCTAssertEqual(s.lost, 0)
        XCTAssertEqual(s.cost, 2)
        XCTAssertEqual(AzulRules.previewText(s), "2 fit, 2 to the floor")
        XCTAssertEqual(AzulRules.costText(s), "−2 points")
        let all = AzulRules.spill(count: 3, onto: .line(4), of: b)
        XCTAssertEqual(AzulRules.previewText(all), "All 3 fit")
        XCTAssertNil(AzulRules.costText(all))
        XCTAssertEqual(AzulRules.previewText(AzulRules.spill(count: 1, onto: .line(0), of: b)), "It fits")
        XCTAssertEqual(AzulRules.previewText(AzulRules.spill(count: 4, onto: .line(0), of: b)), "1 fits, 3 to the floor")
    }

    func testTheFloorTakesSevenAndTheMarkerFirst() {
        let b = board(floor: 5)
        let s = AzulRules.spill(count: 3, onto: .floor, of: b, marker: true)
        XCTAssertEqual(s.fit, 0)
        XCTAssertEqual(s.floor, 3)
        XCTAssertEqual(s.lost, 2, "the marker takes a space, one tile lands, two go to the lid")
        XCTAssertEqual(s.cost, 6, "spaces six and seven cost 3 each")
        XCTAssertEqual(AzulRules.previewText(s), "3 to the floor, and the marker")
        let full = AzulRules.spill(count: 2, onto: .floor, of: board(floor: 7))
        XCTAssertEqual(full.lost, 2)
        XCTAssertEqual(full.cost, 0)
    }

    func testDestinationsAreTheLitLinesThenTheFloor() {
        let b = board()
        let list = AzulRules.destinations(for: "blue", count: 2, board: b, canPlace: ["blue": [4, 0]], marker: false)
        XCTAssertEqual(list.map(\.line), [.line(0), .line(4), .floor])
        XCTAssertEqual(list.map(\.id), ["line-0", "line-4", "floor"])
        XCTAssertEqual(list[0].spill.floor, 1)
        XCTAssertEqual(list[1].spill.fit, 2)
        XCTAssertEqual(AzulRules.destinations(for: "red", count: 1, board: b, canPlace: [:], marker: false).map(\.line), [.floor],
                       "the floor is always allowed")
    }

    // MARK: - The floor and the score

    func testTheFloorCosts() {
        XCTAssertEqual(AzulRules.floorPenalty(count: 0), 0)
        XCTAssertEqual(AzulRules.floorPenalty(count: 2), 2)
        XCTAssertEqual(AzulRules.floorPenalty(count: 7), 14)
        XCTAssertEqual(AzulRules.floorPenalty(count: 9), 14)
        XCTAssertEqual((0..<7).map(AzulRules.floorLabel), ["−1", "−1", "−2", "−2", "−2", "−3", "−3"])
        XCTAssertEqual(AzulRules.floorLabel(7), "")
    }

    func testBonusesInWords() {
        XCTAssertEqual(AzulBonus(rows: 2, columns: 1, colours: 0).points, 11)
        XCTAssertEqual(AzulRules.bonusLine(AzulBonus(rows: 2, columns: 1, colours: 0)), "2 rows +4 · 1 column +7 · no colours")
        XCTAssertEqual(AzulRules.bonusLine(AzulBonus(rows: 1, columns: 0, colours: 1)), "1 row +2 · no columns · 1 colour +10")
        XCTAssertEqual(AzulRules.deltaText(5), "+5")
        XCTAssertEqual(AzulRules.deltaText(-2), "−2")
        XCTAssertEqual(AzulRules.deltaText(0), "±0")
    }

    func testABoardBuiltInCodeWorksItsFiguresOut() {
        let wall: [[Int?]] = [[1, 2, 3, 4, 5], [nil, nil, nil, nil, nil]]
        let b = AzulBoard(id: "p", name: "P", wall: wall, floor: [AzulTile(id: 100, c: "first")])
        XCTAssertEqual(b.rows, 1)
        XCTAssertEqual(b.placed, 5)
        XCTAssertTrue(b.hasFirst)
        XCTAssertEqual(b.floorPenalty, 1)
        XCTAssertEqual(b.lines.count, 5)
    }

    func testEndingsAndLeaving() {
        XCTAssertTrue(AzulRules.endingLine(nil).contains("over"))
        XCTAssertTrue(AzulRules.leaveWarning(staying: 1).contains("ends here"))
        XCTAssertTrue(AzulRules.leaveWarning(staying: 2).contains("play on"))
    }

    // MARK: - The TV's code

    func testTheCodeFieldKeepsOnlyLettersATVCouldShow() {
        XCTAssertEqual(GameScreenCode.typing("bcdf"), "BCDF")
        XCTAssertEqual(GameScreenCode.typing("b-c d f g"), "BCDF", "four at most")
        XCTAssertEqual(GameScreenCode.typing("bad1"), "BD", "no vowels, no digits")
        XCTAssertEqual(GameScreenCode.normalise("bc-df"), "BCDF")
        XCTAssertEqual(GameScreenCode.normalise(" b c d f "), "BCDF")
        XCTAssertNil(GameScreenCode.normalise("BCD"))
        XCTAssertNil(GameScreenCode.normalise("BCDA"))
        XCTAssertEqual(GameScreenCode.address("azul"), "strangeramblings.com/games/azul")
        XCTAssertTrue(GameScreenCode.instruction("azul").contains("four letters"))
    }
}
