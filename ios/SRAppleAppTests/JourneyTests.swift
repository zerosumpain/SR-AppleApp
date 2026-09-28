import XCTest
@testable import SRAppleApp

/// The family-journey Live Activity's contract with SR-Main
/// (`$lib/home/presence/live-journey`). ActivityKit decodes the push's JSON
/// straight into `JourneyAttributes`; a key that drifts on either side drops
/// the whole push with no error anywhere. These are the server's shapes,
/// verbatim.
final class JourneyTests: XCTestCase {

    func testTheServersMovingStateDecodes() throws {
        let json = #"{"phase":"moving","headline":"Sam left School","detail":"2.2 km from home · walking · ~35 min","distanceHomeM":2224,"progress":0.26,"etaMinutes":35,"mode":"walking","updatedAt":1790604000}"#
        let state = try JSONDecoder().decode(JourneyAttributes.ContentState.self, from: Data(json.utf8))
        XCTAssertTrue(state.moving)
        XCTAssertEqual(state.etaMinutes, 35)
        XCTAssertEqual(state.shortDistance, "2.2 km")
        XCTAssertEqual(state.symbol, "figure.walk")
        XCTAssertEqual(state.updated, Date(timeIntervalSince1970: 1_790_604_000))
    }

    func testAnArrivalWithNullsDecodes() throws {
        let json = #"{"phase":"arrived","headline":"Sam arrived at Home","detail":"at 17:52","distanceHomeM":0,"progress":1,"etaMinutes":null,"mode":null,"updatedAt":1790605000}"#
        let state = try JSONDecoder().decode(JourneyAttributes.ContentState.self, from: Data(json.utf8))
        XCTAssertTrue(state.arrived)
        XCTAssertNil(state.etaMinutes)
        XCTAssertEqual(state.symbol, "house.fill")
    }

    func testTheServersAttributesDecode() throws {
        let json = #"{"journeyId":"sam:school:leave:1790604000","name":"Sam","fromPlace":"School","startedAt":1790604000}"#
        let attributes = try JSONDecoder().decode(JourneyAttributes.self, from: Data(json.utf8))
        XCTAssertEqual(attributes.journeyId, "sam:school:leave:1790604000")
        XCTAssertEqual(attributes.fromPlace, "School")
    }

    func testShortDistances() {
        var state = JourneyAttributes.ContentState(phase: "moving", headline: "", detail: "", distanceHomeM: 644, progress: nil, etaMinutes: nil, mode: "vehicle", updatedAt: 0)
        XCTAssertEqual(state.shortDistance, "640 m")
        XCTAssertEqual(state.symbol, "car.fill")
        state.distanceHomeM = 18_300
        XCTAssertEqual(state.shortDistance, "18 km")
    }
}
