import XCTest
import CoreLocation
@testable import SRAppleApp

/// `RouteNav` is a port of SR-Health's `field/nav.ts` + `tracker.ts`; these
/// are `field.test.ts`'s cases, number for number, so the phone and
/// /health/record agree. Then the one thing the phone adds: following a loop.
final class RouteNavTests: XCTestCase {

    private func c(_ lng: Double, _ lat: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// A 2 km line running east at 53.4N (the web test's own line).
    private var line: [CLLocationCoordinate2D] { [c(-1.5, 53.4), c(-1.47, 53.4)] }

    func testAPointOnTheLineIsAtZeroDistance() throws {
        let n = try XCTUnwrap(RouteNav.nearest(c(-1.485, 53.4), on: line))
        XCTAssertLessThan(n.distanceM, 1)
    }

    func testPerpendicularDistanceOffTheLine() throws {
        let d = try XCTUnwrap(RouteNav.nearest(c(-1.485, 53.401), on: line)).distanceM
        XCTAssertGreaterThan(d, 100)
        XCTAssertLessThan(d, 125)
    }

    func testLongitudeIsScaledAgainstLatitude() throws {
        let north = try XCTUnwrap(RouteNav.nearest(c(-1.485, 53.401), on: line)).distanceM
        let east = try XCTUnwrap(RouteNav.nearest(c(-1.469, 53.4), on: line)).distanceM
        XCTAssertGreaterThan(east / north, 0.5)
        XCTAssertLessThan(east / north, 0.7)
    }

    func testAClampedOvershootIsTrueGroundDistance() throws {
        let d = try XCTUnwrap(RouteNav.nearest(c(-1.4695, 53.4), on: line)).distanceM
        XCTAssertGreaterThan(d, 30)
        XCTAssertLessThan(d, 37)
    }

    func testClampsToTheSegmentEnds() throws {
        let n = try XCTUnwrap(RouteNav.nearest(c(-1.6, 53.4), on: line))
        XCTAssertEqual(n.point.longitude, -1.5, accuracy: 1e-4)
    }

    func testTooShortToBeALine() {
        XCTAssertNil(RouteNav.nearest(c(-1.5, 53.4), on: []))
        XCTAssertNil(RouteNav.nearest(c(-1.5, 53.4), on: [c(-1.5, 53.4)]))
    }

    func testOffRouteOnlyPastTheThreshold() {
        XCTAssertFalse(RouteNav.isOffRoute(20))
        XCTAssertTrue(RouteNav.isOffRoute(80))
        XCTAssertFalse(RouteNav.isOffRoute(80, threshold: 100))
    }

    func testProgressAlongTheRoute() throws {
        XCTAssertEqual(try XCTUnwrap(RouteNav.progress(c(-1.5, 53.4), on: line)).fraction, 0, accuracy: 0.01)
        let middle = try XCTUnwrap(RouteNav.progress(c(-1.485, 53.4), on: line))
        XCTAssertGreaterThan(middle.fraction, 0.4)
        XCTAssertLessThan(middle.fraction, 0.6)
        XCTAssertGreaterThan(middle.remainingM, 0)
        let end = try XCTUnwrap(RouteNav.progress(c(-1.47, 53.4), on: line))
        XCTAssertEqual(end.fraction, 1, accuracy: 0.01)
        XCTAssertLessThan(end.remainingM, 2)
    }

    func testNaismith() {
        XCTAssertGreaterThan(RouteNav.estimateTimeS(distanceM: 10_000, ascentM: 300, sport: "run"),
                             RouteNav.estimateTimeS(distanceM: 10_000, ascentM: 0, sport: "run"))
        XCTAssertLessThan(RouteNav.estimateTimeS(distanceM: 10_000, ascentM: 0, sport: "ride"),
                          RouteNav.estimateTimeS(distanceM: 10_000, ascentM: 0, sport: "run"))
        XCTAssertEqual(RouteNav.estimateTimeS(distanceM: 0, ascentM: 100, sport: "run"), 0)
        XCTAssertGreaterThan(RouteNav.estimateTimeS(distanceM: 5000, ascentM: 0, sport: "kitesurf"), 0)
    }

    func testTheFixFilter() {
        XCTAssertEqual(FixFilter.classify(accuracy: 8, lat: 53.4, lng: -1.5), .accept)
        XCTAssertEqual(FixFilter.classify(accuracy: 45, lat: 53.4, lng: -1.5), .flag)
        XCTAssertEqual(FixFilter.classify(accuracy: 250, lat: 53.4, lng: -1.5), .reject)
        XCTAssertEqual(FixFilter.classify(accuracy: 8, lat: .nan, lng: -1.5), .reject)
        let t0 = Date(timeIntervalSince1970: 8)
        XCTAssertFalse(FixFilter.shouldRecord(Date(timeIntervalSince1970: 10), after: t0))
        XCTAssertTrue(FixFilter.shouldRecord(Date(timeIntervalSince1970: 11), after: t0))
        let from = CLLocation(coordinate: c(-1.5, 53.4), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date(timeIntervalSince1970: 0))
        let teleport = CLLocation(coordinate: c(-1.5, 53.41), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date(timeIntervalSince1970: 3))
        XCTAssertFalse(FixFilter.isPlausibleStep(from: from, to: teleport))
    }

    // MARK: Following

    /// A square loop, ~1 km a side, starting and finishing at the same corner.
    private var loop: [RoutePoint] {
        [(53.4, -1.5), (53.4, -1.485), (53.409, -1.485), (53.409, -1.5), (53.4, -1.5)]
            .map { RoutePoint(lat: $0.0, lng: $0.1, ele: nil) }
    }

    func testSettingOffOnALoopIsTheStartNotTheFinish() throws {
        // The whole-route nearest point at the start of a loop is ambiguous;
        // the web can read 100%. Following from nothing must read ~0%.
        var follower = RouteFollower(route: loop)
        let p = try XCTUnwrap(follower.update(c(-1.4999, 53.4)))
        XCTAssertLessThan(p.fraction, 0.05)
    }

    func testArrivingBackAtTheStartIsTheFinish() throws {
        var follower = RouteFollower(route: loop)
        // Walk it round, one fix every ~200 m.
        for p in loop {
            _ = follower.update(p.coordinate)
        }
        var last: RouteNav.Progress?
        for step in stride(from: 53.409, through: 53.4, by: -0.0015) {
            last = follower.update(c(-1.5, step))
        }
        XCTAssertGreaterThan(try XCTUnwrap(last).fraction, 0.95)
    }

    func testADetourDoesNotMoveYouAlong() throws {
        var follower = RouteFollower(route: loop)
        _ = follower.update(c(-1.495, 53.4))
        let before = try XCTUnwrap(follower.update(c(-1.49, 53.4))).alongM
        // 300 m south of the line: off route, and still at the same place on it.
        let off = try XCTUnwrap(follower.update(c(-1.49, 53.3973)))
        XCTAssertTrue(off.offRoute)
        let back = try XCTUnwrap(follower.update(c(-1.4899, 53.4)))
        XCTAssertEqual(back.alongM, before, accuracy: 15)
    }
}
