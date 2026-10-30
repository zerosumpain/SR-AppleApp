import XCTest
@testable import SRAppleApp

/// Homestead's moments: what a roll paid out, a point's toast, my turn's
/// first step, and which pieces have just appeared.
final class HomesteadMomentsTests: XCTestCase {
    /// Four hexes: fields 8, woods 8 (under the fox when asked), quarry 5, dunes.
    private func state(dice: String?, fox: String? = nil, buildings: String = "[]", roads: String = "[]") throws -> HomesteadState {
        let foxField = fox.map { #""fox": "\#($0)","# } ?? ""
        let diceField = dice.map { #""dice": \#($0),"# } ?? ""
        let json = """
        {
          "phase": "playing", "step": "main", "meId": "p1", "activeId": "p1", "vpTarget": 10,
          \(foxField)
          \(diceField)
          "board": {"hexes": [
            {"q": 0, "r": 0, "kind": "fields", "token": 8},
            {"q": 1, "r": 0, "kind": "woods", "token": 8},
            {"q": 0, "r": 1, "kind": "quarry", "token": 5},
            {"q": -1, "r": 1, "kind": "dunes"}
          ], "harbours": []},
          "buildings": \(buildings),
          "roads": \(roads)
        }
        """
        return try JSONDecoder().decode(HomesteadState.self, from: Data(json.utf8))
    }

    private func name(_ id: String) -> String { id == "p1" ? "You" : "Sam" }

    func testAnEightPaysBothEightsInResourceOrder() throws {
        let s = try state(dice: #"{"a": 3, "b": 5, "by": "p1", "at": 1}"#)
        XCTAssertEqual(HomesteadMoments.paying(s).map(\.id).sorted(), ["0,0", "1,0"])
        XCTAssertEqual(HomesteadMoments.payingResources(s), [.timber, .grain])
        let line = try XCTUnwrap(HomesteadMoments.roll(s, name: name))
        XCTAssertEqual(line.title, "You rolled 8")
        XCTAssertEqual(line.detail, "Timber and grain for everyone beside an 8.")
    }

    func testTheFoxsHexPaysNobody() throws {
        let s = try state(dice: #"{"a": 4, "b": 4, "by": "p2", "at": 1}"#, fox: "1,0")
        XCTAssertEqual(HomesteadMoments.payingResources(s), [.grain])
        XCTAssertEqual(HomesteadMoments.roll(s, name: name)?.title, "Sam rolled 8")
    }

    func testASevenIsTheFoxAndPaysNothing() throws {
        let s = try state(dice: #"{"a": 3, "b": 4, "by": "p2", "at": 1}"#)
        XCTAssertTrue(HomesteadMoments.paying(s).isEmpty)
        XCTAssertEqual(HomesteadMoments.roll(s, name: name), HomesteadMoments.Line(title: "Sam rolled 7", detail: "The fox is on the move!"))
    }

    func testANumberOnNoHexSaysSo() throws {
        let s = try state(dice: #"{"a": 6, "b": 6, "at": 1}"#)
        XCTAssertEqual(HomesteadMoments.roll(s, name: name), HomesteadMoments.Line(title: "Someone rolled 12", detail: "Nothing pays out this time."))
    }

    func testNoRollNoLine() throws {
        let s = try state(dice: nil)
        XCTAssertNil(HomesteadMoments.roll(s, name: name))
        XCTAssertTrue(HomesteadMoments.paying(s).isEmpty)
    }

    func testArticles() {
        XCTAssertEqual(HomesteadMoments.article(8), "an")
        XCTAssertEqual(HomesteadMoments.article(11), "an")
        XCTAssertEqual(HomesteadMoments.article(6), "a")
        XCTAssertEqual(HomesteadMoments.article(2), "a")
    }

    func testPointsOnlyWhenTheyGoUp() {
        XCTAssertNil(HomesteadMoments.points(from: nil, to: 4, target: 10))
        XCTAssertNil(HomesteadMoments.points(from: 4, to: 4, target: 10))
        XCTAssertNil(HomesteadMoments.points(from: 5, to: 4, target: 10))
        XCTAssertEqual(HomesteadMoments.points(from: 4, to: 5, target: 10),
                       HomesteadMoments.Line(title: "+1 point", detail: "5 of 10: 5 to go."))
        XCTAssertEqual(HomesteadMoments.points(from: 6, to: 8, target: 8),
                       HomesteadMoments.Line(title: "+2 points", detail: "That's the target!"))
    }

    func testTurnDetailByStep() {
        XCTAssertEqual(HomesteadMoments.turnDetail(.roll), "Roll the dice to start.")
        XCTAssertEqual(HomesteadMoments.turnDetail(.setup), "Place your piece on a lit spot.")
        XCTAssertNil(HomesteadMoments.turnDetail(.main))
        XCTAssertNil(HomesteadMoments.turnDetail(nil))
    }

    func testPieceKeysAndATownIsNew() throws {
        let before = try state(dice: nil, buildings: #"[{"at": "0,0,N", "owner": "p1", "piece": "cottage"}]"#,
                               roads: #"[{"at": "0,0,NE", "owner": "p1"}]"#)
        let after = try state(dice: nil, buildings: #"[{"at": "0,0,N", "owner": "p1", "piece": "town"}]"#,
                              roads: #"[{"at": "0,0,NE", "owner": "p1"}]"#)
        let a = HomesteadMoments.pieceKeys(before)
        let b = HomesteadMoments.pieceKeys(after)
        XCTAssertEqual(a, ["b|0,0,N|cottage", "r|0,0,NE"])
        XCTAssertEqual(HomesteadMoments.fresh(previous: a, now: b), ["b|0,0,N|town"])
        XCTAssertNil(HomesteadMoments.fresh(previous: a, now: a), "nothing new")
    }

    func testABigRereadIsNotAMove() {
        let now = Set((0..<6).map { "r|\($0),0,NE" })
        XCTAssertNil(HomesteadMoments.fresh(previous: [], now: now))
        XCTAssertEqual(HomesteadMoments.fresh(previous: [], now: now, limit: 6)?.count, 6)
    }

    func testSpotOfAKey() {
        XCTAssertEqual(HomesteadMoments.spot(of: "r|0,0,NE")?.road, true)
        XCTAssertEqual(HomesteadMoments.spot(of: "b|0,0,N|town")?.id, "0,0,N")
        XCTAssertNil(HomesteadMoments.spot(of: "x|0,0,N"))
        XCTAssertNil(HomesteadMoments.spot(of: "nonsense"))
    }

    func testOrdinalsAndShare() {
        XCTAssertEqual(HomesteadMoments.ordinal(2), "second")
        XCTAssertEqual(HomesteadMoments.ordinal(7), "7th")
        XCTAssertEqual(HomesteadMoments.share(5, of: 10), 0.5)
        XCTAssertEqual(HomesteadMoments.share(12, of: 10), 1)
        XCTAssertEqual(HomesteadMoments.share(3, of: 0), 1)
    }
}
