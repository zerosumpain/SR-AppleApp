import XCTest
@testable import SRAppleApp

/// A turn's map (`ChatMap`): read tolerantly, opened on the right box.
final class ChatMapTests: XCTestCase {

    private func map(_ json: String) throws -> ChatMap {
        try JSONDecoder().decode(ChatMap.self, from: Data(json.utf8))
    }

    func testPinsTracksAndBoundsAreRead() throws {
        let m = try map("""
        {"type":"map","simple":true,"caption":"Saturday's ride",
         "points":[{"lat":51.5,"lon":-0.12,"label":"Start"},{"lat":51.52,"lon":-0.1}],
         "tracks":[[{"lat":51.5,"lon":-0.12},{"lat":51.51,"lon":-0.11},{"lat":51.52,"lon":-0.1}]],
         "bounds":{"south":51.49,"west":-0.13,"north":51.53,"east":-0.09}}
        """)
        XCTAssertEqual(m.caption, "Saturday's ride")
        XCTAssertEqual(m.points.map(\.label), ["Start", nil])
        XCTAssertEqual(m.tracks.first?.count, 3)
        XCTAssertTrue(m.drawable)
        let r = try XCTUnwrap(m.region)
        XCTAssertEqual(r.centerLat, 51.51, accuracy: 1e-9)
        XCTAssertEqual(r.centerLon, -0.11, accuracy: 1e-9)
        XCTAssertEqual(r.latDelta, 0.04 * ChatMap.padding, accuracy: 1e-9)
    }

    func testBadPointsAreSkippedNotFatal() throws {
        let m = try map("""
        {"points":[{"lat":"north","lon":1},{"lat":95,"lon":0},{"lon":3},7,{"lat":10,"lon":20,"label":"  "}],
         "tracks":[[{"lat":1,"lon":1}],"line",[{"lat":1,"lon":1},{"lat":2,"lon":2}]],
         "bounds":{"south":5,"west":0,"north":1,"east":1}}
        """)
        XCTAssertEqual(m.points.count, 1)
        XCTAssertNil(m.points.first?.label, "a blank label is no label")
        XCTAssertEqual(m.tracks.count, 1, "a one-point track and a non-track go")
        XCTAssertNil(m.bounds, "south of north is not a box")
    }

    func testWithoutBoundsTheRegionFitsWhatIsDrawn() throws {
        let one = try map(#"{"points":[{"lat":48.85,"lon":2.35}]}"#)
        let r = try XCTUnwrap(one.region)
        XCTAssertEqual(r.centerLat, 48.85, accuracy: 1e-9)
        XCTAssertEqual(r.latDelta, ChatMap.minimumSpan, "a single pin opens on a street, not a building")
        XCTAssertNil(try map(#"{"points":[]}"#).region)
        XCTAssertFalse(try map(#"{"points":[],"tracks":[]}"#).drawable)
    }

    func testABoxAcrossTheDateLineCentresOnIt() throws {
        let m = try map(#"{"points":[{"lat":0,"lon":179}],"bounds":{"south":-1,"west":170,"north":1,"east":-170}}"#)
        let r = try XCTUnwrap(m.region)
        XCTAssertEqual(abs(r.centerLon), 180, accuracy: 1e-9)
        XCTAssertEqual(r.lonDelta, 20 * ChatMap.padding, accuracy: 1e-9)
    }
}
