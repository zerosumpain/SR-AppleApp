import XCTest
@testable import SRAppleApp

/// v8.1: the day-row sketch's geometry — north up, the shape kept, a margin, and no sketch for one place.
final class TripDaySketchTests: XCTestCase {
    private func stop(_ id: String, _ lat: Double, _ lng: Double, kind: StopKind = .wish, stage: String? = "morning") -> PlannedStop {
        PlannedStop(id: id, kind: kind, wishId: kind == .wish ? id : nil, title: id, location: TripLatLng(lat: lat, lng: lng),
                    arriveMin: 600, departMin: 660, waitSec: 0, locked: false, bookingId: nil, warnings: [], stage: stage)
    }

    func testNorthIsUpAndTheShapeIsKept() {
        let day = PlannedDay(date: "2026-10-27", stayId: nil, stops: [
            stop("stay", 41.8975, 12.4720, kind: .stay, stage: nil),
            stop("pantheon", 41.8986, 12.4769),
            stop("colosseum", 41.8902, 12.4922, stage: "afternoon"),
        ], legs: [], warnings: [])
        let p = TripDaySketchLogic.points(day)
        XCTAssertEqual(p.count, 3)
        XCTAssertTrue(p[0].isStay)
        // The Pantheon is north of the Colosseum: higher up (smaller y).
        XCTAssertLessThan(p[1].y, p[2].y)
        // The Colosseum is east: further right.
        XCTAssertGreaterThan(p[2].x, p[1].x)
        for q in p { XCTAssertTrue((0.13...0.87).contains(q.x) && (0.13...0.87).contains(q.y), "\(q)") }
        XCTAssertEqual(p[2].stage, "afternoon")
    }

    func testOnePlaceIsNotARoute() {
        let day = PlannedDay(date: "2026-10-27", stayId: nil, stops: [stop("a", 41.9, 12.48), stop("b", 41.9, 12.48)], legs: [], warnings: [])
        XCTAssertEqual(TripDaySketchLogic.points(day), [])
        XCTAssertEqual(TripDaySketchLogic.points(PlannedDay(date: "2026-10-27", stayId: nil, stops: [stop("a", 41.9, 12.48)], legs: [], warnings: [])), [])
    }
}
