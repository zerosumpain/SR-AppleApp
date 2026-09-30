import XCTest
import CoreLocation
@testable import SRAppleApp

/// The planned-routes contract (SR-Main `$lib/server/native-routes`), decoded
/// from the demo's own answers — so a fixture that drifts from the models fails
/// here, not as a blank showcase screenshot. SYNTHETIC coordinates only.
final class RouteTests: XCTestCase {

    private func decode<T: Decodable>(_ json: String?, as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(try XCTUnwrap(json).utf8))
    }

    func testTheSavedListDecodes() throws {
        let page: RoutesPage = try decode(SRDemoFixtures.routesList)
        XCTAssertEqual(page.routes.count, 2)
        XCTAssertEqual(page.routes[0].summaryLine, "8.04 km · 96 m up · 1:42:00")
        XCTAssertNil(page.routes[1].score)
    }

    func testTheDetailCarriesItsGeometryAndHeight() throws {
        let d: PlannedRouteDetail = try decode(SRDemoFixtures.routeDetail(id: SRDemoFixtures.demoRouteId))
        XCTAssertEqual(d.route.count, 161)
        XCTAssertNotNil(d.route[0].ele)
        XCTAssertEqual(d.waypoints.first?.name, "Water fountain")
    }

    func testAMalformedPointIsDroppedNotDrawnToNullIsland() {
        let points = RoutePoint.decodeList([[40.78, -73.96, 30], [nil, -73.9], [95, 0], [40.79, -73.95]])
        XCTAssertEqual(points.count, 2)
        XCTAssertNil(points[1].ele)
    }

    func testAPlanDecodesAndItsBreakdownGoesBackOnSave() throws {
        let body = try JSONEncoder().encode(RoutePlanRequest(
            startLat: 40.78, startLng: -73.96, sport: "walk", targetDistanceM: 8000
        ))
        let plan: RoutePlan = try decode(SRDemoFixtures.routePlan(body: body))
        XCTAssertEqual(plan.candidates.map(\.rank), [1, 2, 3])
        let first = plan.candidates[0]
        XCTAssertEqual(first.notes.first, "Little doubling back.")
        XCTAssertNotNil(first.breakdown)

        let save = RouteSaveRequest(
            name: "x", sport: "walk", route: first.route.map(\.json), distanceM: first.distanceM,
            ascentM: first.ascentM, descentM: first.descentM, durationS: first.durationS, score: first.score,
            scoreBreakdown: first.breakdown, targetDistanceM: plan.targetDistanceM, source: "planned"
        )
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(save)) as? [String: Any])
        let breakdown = try XCTUnwrap(sent["scoreBreakdown"] as? [String: Any])
        XCTAssertEqual(breakdown["distanceScore"] as? Double, 0.93)
        let firstPoint = try XCTUnwrap((sent["route"] as? [[Any]])?.first)
        XCTAssertEqual(firstPoint.count, 3, "points go back as [lat, lng, ele]")
    }

    @MainActor
    func testALoopAsksForADistanceAndAToBDoesNot() {
        let planner = RoutePlanner()
        planner.start = CLLocationCoordinate2D(latitude: 40.78, longitude: -73.96)
        planner.distanceKm = 8
        XCTAssertEqual(planner.makeRequest()?.targetDistanceM, 8000)
        XCTAssertNil(planner.makeRequest()?.finishLat)

        planner.shape = .toPlace
        XCTAssertNil(planner.makeRequest(), "A to B with no finish is not a request")
        planner.finish = CLLocationCoordinate2D(latitude: 40.79, longitude: -73.95)
        XCTAssertNil(planner.makeRequest()?.targetDistanceM)
        XCTAssertEqual(planner.makeRequest()?.finishLat, 40.79)
    }

    @MainActor
    func testASentenceFillsTheFormAndPlansNothing() throws {
        let planner = RoutePlanner()
        let read: RouteInterpretation = try decode(
            SRDemoFixtures.routesRoute(method: "POST", parts: ["api", "native", "health", "routes", "interpret"], query: [:], body: nil)
        )
        planner.apply(read)
        XCTAssertEqual(planner.sport, .walk)
        XCTAssertEqual(planner.distanceKm, 8)
        XCTAssertEqual(planner.climb, .rolling)
        XCTAssertTrue(planner.steady)
        XCTAssertNil(planner.plan)
    }
}

/// The live walk contract (SR-Main `route-session.viewOf`), from the demo's answers.
final class RouteLiveTests: XCTestCase {
    func testALiveWalkDecodesWithItsTrailAsPositionsNotHeights() throws {
        let walk = try JSONDecoder().decode(LiveWalk.self, from: Data(SRDemoFixtures.liveWalk(full: true).utf8))
        XCTAssertEqual(walk.name, "Alex")
        XCTAssertEqual(walk.trail.count, 65)
        XCTAssertNil(walk.trail[0].ele, "the third number on a trail point is a time")
        XCTAssertEqual(walk.fraction, 3260.0 / 8040.0, accuracy: 1e-9)
        XCTAssertEqual(walk.line, "3.26 of 8.04 km · ~58:00 left")
    }

    func testTheListIsNamesAndProgressOnly() throws {
        let page = try JSONDecoder().decode(LiveWalksPage.self, from: Data(
            try XCTUnwrap(SRDemoFixtures.routeSessionRoute(method: "GET", parts: ["api", "native", "route-session"])).utf8
        ))
        XCTAssertEqual(page.sessions.count, 1)
        XCTAssertTrue(page.sessions[0].trail.isEmpty)
    }

    func testAnOffRouteWalkSaysSo() throws {
        let json = SRDemoFixtures.liveWalk(full: false)
            .replacingOccurrences(of: #""offRouteM": 6, "offRoute": false"#, with: #""offRouteM": 140, "offRoute": true"#)
        let walk = try JSONDecoder().decode(LiveWalk.self, from: Data(json.utf8))
        XCTAssertEqual(walk.line, "Off route · 140 m from the line")
    }

    func testARouteSentToAMemberArrivesWholeWithWhoItCanGoTo() throws {
        let page = try JSONDecoder().decode(RouteGiftsPage.self, from: Data(
            try XCTUnwrap(SRDemoFixtures.routeGiftsRoute(method: "GET")).utf8
        ))
        XCTAssertEqual(page.gifts.first?.route.name, "Park Drive loop")
        XCTAssertGreaterThan(page.gifts.first?.route.route.count ?? 0, 100, "a gift carries the line to follow")
        XCTAssertEqual(page.recipients.map(\.name), ["Alex", "Sam"])
    }
}
