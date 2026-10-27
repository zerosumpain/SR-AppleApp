import XCTest
@testable import SRAppleApp

/// The family's explored ground: the wire (`/api/native/family/landgrab/explored`,
/// as SR-Main sends it, and again with fields missing, null and odd), the
/// encoded polylines its shapes arrive in, the words and figures, and where
/// the map opens. Foundation only, so it also runs on Linux. Coordinates are
/// Central Park, New York, and Boston Common — synthetic, as everywhere in
/// this public repository.
final class LandgrabExploredTests: XCTestCase {

    // A small square in the park, and one on the Common, encoded.
    private var park: String {
        LandgrabPolyline.encode([
            LandgrabPoint(lat: 40.7800, lon: -73.9700), LandgrabPoint(lat: 40.7800, lon: -73.9600),
            LandgrabPoint(lat: 40.7880, lon: -73.9600), LandgrabPoint(lat: 40.7880, lon: -73.9700),
        ])
    }
    private var pond: String {
        LandgrabPolyline.encode([
            LandgrabPoint(lat: 40.7830, lon: -73.9660), LandgrabPoint(lat: 40.7830, lon: -73.9640),
            LandgrabPoint(lat: 40.7850, lon: -73.9640),
        ])
    }
    private var common: String {
        LandgrabPolyline.encode([
            LandgrabPoint(lat: 42.3540, lon: -71.0680), LandgrabPoint(lat: 42.3540, lon: -71.0640),
            LandgrabPoint(lat: 42.3570, lon: -71.0640), LandgrabPoint(lat: 42.3570, lon: -71.0680),
        ])
    }

    /// A polyline inside a JSON string: `\\` is in the polyline alphabet.
    private func j(_ text: String) -> String { text.replacingOccurrences(of: "\\", with: "\\\\") }

    private func json() -> String {
        """
        { "family": "The Parkers", "updatedAt": "2026-10-27T14:00:00.000Z", "since": "2025-01-04",
          "today": "2026-10-27", "weekStart": "2026-10-26",
          "total": { "cells": 9321, "km2": 18.43 }, "todayNew": { "cells": 412, "km2": 1.31 },
          "weekNew": { "cells": 655, "km2": 2.02 },
          "people": [
            { "id": "f_a", "name": "Alex", "me": true, "colour": "#c2410c", "cells": 6000, "km2": 11.9, "firsts": 5000, "today": 300 },
            { "id": "f_s", "name": "Sam", "me": false, "colour": "#1d4ed8", "cells": 4100, "km2": 8.1, "firsts": 4321, "today": 112 },
            { "name": "No id" },
            "not a person" ],
          "places": [
            { "lat": 40.781, "lon": -73.967, "cells": 8000, "km2": 15.8,
              "bounds": { "minLat": 40.76, "minLon": -73.99, "maxLat": 40.80, "maxLon": -73.94 },
              "first": "2025-01-04", "last": "2026-10-20", "home": true },
            { "lat": 42.355, "lon": -71.066, "cells": 600, "km2": 1.9,
              "bounds": { "minLat": 42.35, "minLon": -71.07, "maxLat": 42.36, "maxLon": -71.06 },
              "first": "2026-10-26", "last": "2026-10-27", "home": false },
            { "lat": 95, "lon": 0 } ],
          "otherPlaces": { "count": 3, "cells": 21, "km2": 0.07 },
          "shape": { "zoom": 19, "vertices": 11, "truncated": false,
                     "polygons": [ { "outer": "\(j(park))", "holes": ["\(j(pond))", "not a ring {"] },
                                   { "outer": "\(j(common))", "holes": [] },
                                   { "outer": "~~~" } ] },
          "fresh": { "day": "2026-10-27", "cells": 412, "km2": 1.31,
                     "shape": { "zoom": 19, "polygons": [ { "outer": "\(j(common))", "holes": [] } ] } },
          "focus": { "lat": 40.7812, "lon": -73.9665, "radiusM": 3219 },
          "somethingNew": true }
        """
    }

    private func explored() throws -> LandgrabExplored {
        try JSONDecoder().decode(LandgrabExplored.self, from: Data(json().utf8))
    }

    // MARK: - The wire

    func testDecodesTheContract() throws {
        let e = try explored()
        XCTAssertEqual(e.family, "The Parkers")
        XCTAssertEqual(e.total, LandgrabFigure(cells: 9321, km2: 18.43))
        XCTAssertEqual(e.todayNew, LandgrabFigure(cells: 412, km2: 1.31))
        XCTAssertEqual(e.weekNew.cells, 655)
        XCTAssertEqual(e.today, "2026-10-27")
        XCTAssertEqual(e.since, "2025-01-04")
        XCTAssertEqual(e.people.map(\.id), ["f_a", "f_s"], "a person with no id, and a non-object, are dropped")
        XCTAssertEqual(e.people[0].me, true)
        XCTAssertEqual(e.places.count, 2, "a place off the globe is dropped")
        XCTAssertTrue(e.places[0].home)
        XCTAssertEqual(e.otherPlaces, 3)
        XCTAssertEqual(e.shape.areas.count, 2, "an outline that is not a polyline is dropped, the rest kept")
        XCTAssertEqual(e.shape.areas[0].outer.count, 4)
        XCTAssertEqual(e.shape.areas[0].holes.count, 1, "a bad hole is dropped, the area kept")
        XCTAssertEqual(e.fresh?.day, "2026-10-27")
        XCTAssertEqual(e.fresh?.figure.cells, 412)
        XCTAssertEqual(e.fresh?.shape.areas.count, 1)
        XCTAssertEqual(e.focus?.radiusM, 3219)
    }

    func testAnEmptyOrOddAnswerIsAQuietNothing() throws {
        let e = try JSONDecoder().decode(LandgrabExplored.self, from: Data(#"{ "total": null, "people": "no", "fresh": { "day": "soon" } }"#.utf8))
        XCTAssertEqual(e.family, Landgrab.familyFallback)
        XCTAssertEqual(e.total, LandgrabFigure())
        XCTAssertTrue(e.people.isEmpty)
        XCTAssertNil(e.fresh)
        XCTAssertFalse(Landgrab.showsExplored(e))
        XCTAssertFalse(Landgrab.showsExplored(nil))
        XCTAssertTrue(Landgrab.showsExplored(try explored()))
    }

    // MARK: - Polylines

    func testPolylineMatchesGooglesWorkedExample() {
        // developers.google.com/maps/documentation/utilities/polylinealgorithm
        let points = LandgrabPolyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(points?.count, 3)
        XCTAssertEqual(points?[0].lat ?? 0, 38.5, accuracy: 1e-9)
        XCTAssertEqual(points?[0].lon ?? 0, -120.2, accuracy: 1e-9)
        XCTAssertEqual(points?[2].lat ?? 0, 43.252, accuracy: 1e-9)
        XCTAssertEqual(points?[2].lon ?? 0, -126.453, accuracy: 1e-9)
        XCTAssertEqual(LandgrabPolyline.encode(points ?? []), "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
    }

    func testPolylineRoundTripsAndRefusesJunk() {
        let ring = [LandgrabPoint(lat: 40.78123, lon: -73.96654), LandgrabPoint(lat: -33.9, lon: 151.2),
                    LandgrabPoint(lat: 0, lon: 0), LandgrabPoint(lat: 89.99999, lon: -179.99999)]
        XCTAssertEqual(LandgrabPolyline.decode(LandgrabPolyline.encode(ring)), ring)
        XCTAssertEqual(LandgrabPolyline.decode(""), [])
        XCTAssertNil(LandgrabPolyline.decode("_p~iF~ps|U_"), "a truncated number")
        XCTAssertNil(LandgrabPolyline.decode("_p~iF ~ps|U"), "a character outside the alphabet")
        XCTAssertNil(LandgrabPolyline.decode("~~~~~~~~~~~~~~"), "a number that never ends")
    }

    // MARK: - Words and figures

    func testAreas() {
        XCTAssertEqual(Landgrab.area(18.43), "18.4 km²")
        XCTAssertEqual(Landgrab.area(2.314), "2.3 km²")
        XCTAssertEqual(Landgrab.area(0.314), "0.31 km²")
        XCTAssertEqual(Landgrab.area(1234.4), "1,234 km²")
        XCTAssertEqual(Landgrab.area(0), "0 km²")
        XCTAssertEqual(Landgrab.area(.nan), "0 km²")
        XCTAssertEqual(Landgrab.spokenArea(18.43), "18.4 square kilometres")
    }

    func testTheHeadline() throws {
        let e = try explored()
        XCTAssertEqual(Landgrab.exploredLead(e), "The Parkers have explored")
        XCTAssertEqual(Landgrab.exploredSentence(e), "The Parkers have explored 18.4 km².")
        XCTAssertEqual(Landgrab.exploredSentence(e, spoken: true), "The Parkers have explored 18.4 square kilometres.")
        XCTAssertEqual(Landgrab.newGround(e.todayNew, "new today"), "+1.3 km² new today")
        XCTAssertEqual(Landgrab.newGround(e.weekNew, "this week"), "+2.0 km² this week")
        XCTAssertNil(Landgrab.newGround(LandgrabFigure(), "new today"))
        XCTAssertEqual(Landgrab.sinceLabel(e), "since Jan 2025")
        XCTAssertEqual(Landgrab.spokenHeadline(e),
                       "The Parkers have explored 18.4 square kilometres. 1.3 square kilometres new today, 2.0 square kilometres this week.")
        XCTAssertEqual(Landgrab.familyMapSummary(e),
                       "Map. Everywhere explored, 18.4 square kilometres, filled in. Today's new ground, 1.3 square kilometres, is lit up.")
        let none = LandgrabExplored(today: "2026-10-27", total: LandgrabFigure())
        XCTAssertEqual(Landgrab.spokenHeadline(none), "The family haven't explored anywhere yet.")
        XCTAssertEqual(Landgrab.familyMapSummary(none), "Map. Nothing explored yet.")
        XCTAssertEqual(Landgrab.exploredSentence(none), "The family haven't explored anywhere yet.")
        XCTAssertNil(Landgrab.sinceLabel(none))
    }

    func testShares() throws {
        let e = try explored()
        let alex = e.people[0], sam = e.people[1]
        XCTAssertEqual(Landgrab.percent(Landgrab.share(alex, of: e.total)), "64%")
        XCTAssertEqual(Landgrab.percent(Landgrab.share(sam, of: e.total)), "44%")
        XCTAssertEqual(Landgrab.percent(0.004), "<1%")
        XCTAssertEqual(Landgrab.percent(0), "0%")
        XCTAssertEqual(Landgrab.percent(1), "100%")
        XCTAssertEqual(Landgrab.share(alex, of: LandgrabFigure()), 0)
        XCTAssertEqual(
            Landgrab.spokenPart(sam, of: e),
            "Sam, 8.1 square kilometres, 44% of the family's ground, 0.36 square kilometres of it new today."
        )
        XCTAssertEqual(Landgrab.spokenPart(alex, of: e).prefix(4), "You,")
        let tied = [LandgrabExploredPerson(id: "b", name: "Bea", cells: 5),
                    LandgrabExploredPerson(id: "a", name: "Al", me: true, cells: 5),
                    LandgrabExploredPerson(id: "c", name: "Cy", cells: 9)]
        XCTAssertEqual(Landgrab.rankedParts(tied).map(\.id), ["c", "a", "b"])
    }

    func testFreshLabels() {
        let fresh = { (day: String) in LandgrabFresh(day: day, figure: LandgrabFigure(cells: 1), shape: LandgrabShape()) }
        XCTAssertEqual(Landgrab.freshLabel(fresh("2026-10-27"), today: "2026-10-27"), "Today")
        XCTAssertEqual(Landgrab.freshLabel(fresh("2026-10-26"), today: "2026-10-27"), "Yesterday")
        XCTAssertEqual(Landgrab.freshLabel(fresh("2026-10-24"), today: "2026-10-27"), "Sat 24 Oct")
    }

    func testPlaces() throws {
        let e = try explored()
        XCTAssertEqual(Landgrab.placeFallback(e.places[0]), "Home")
        XCTAssertEqual(Landgrab.placeFallback(e.places[1]), "Explored 26 Oct – 27 Oct")
        XCTAssertEqual(Landgrab.placeFallback(LandgrabPlace(lat: 1, lon: 1, first: "2026-10-01", last: "2026-10-01")), "Explored 1 Oct")
        XCTAssertEqual(Landgrab.placeDetail(e.places[0], today: e.today), "Since 4 Jan 2025 · newest 20 Oct")
        XCTAssertEqual(Landgrab.placeDetail(e.places[1], today: e.today), "Since 26 Oct 2026 · new ground today")
        XCTAssertEqual(Landgrab.placeDetail(LandgrabPlace(lat: 1, lon: 1, first: "2026-10-01", last: "2026-10-01"), today: e.today), "Since 1 Oct 2026")
        XCTAssertNil(Landgrab.placeDetail(LandgrabPlace(lat: 1, lon: 1), today: e.today))
        XCTAssertEqual(Landgrab.placesLine(["Darlington", "Rome"], others: 3), "Darlington, Rome and 3 more places")
        XCTAssertEqual(Landgrab.placesLine(["Darlington", "Rome"], others: 0), "Darlington and Rome")
        XCTAssertEqual(Landgrab.placesLine([], others: 1), "1 more place")
        XCTAssertNil(Landgrab.placesLine([], others: 0))
        XCTAssertEqual(Landgrab.townName(locality: " ", area: nil, region: "Lazio", country: "Italy"), "Lazio")
        XCTAssertEqual(Landgrab.townName(locality: "Rome", area: "Roma", region: "Lazio", country: "Italy"), "Rome")
        XCTAssertNil(Landgrab.townName(locality: nil, area: nil, region: nil, country: nil))
    }

    // MARK: - The demo

    func testTheDemoAnswersTheFamilyViewWithTodayAway() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let raw = try XCTUnwrap(SRDemoFixtures.landgrabRoute(method: "GET", parts: ["api", "native", "family", "landgrab", "explored"],
                                                             query: [:], clock: clock))
        let e = try JSONDecoder().decode(LandgrabExplored.self, from: Data(raw.utf8))
        XCTAssertTrue(Landgrab.showsExplored(e))
        XCTAssertEqual(e.today, Landgrab.ymd(clock.now))
        XCTAssertEqual(e.shape.areas.count, 7, "every made-up shape arrives as a ring")
        XCTAssertEqual(e.fresh?.day, e.today)
        XCTAssertEqual(e.fresh?.shape.areas.count, 2)
        XCTAssertEqual(e.people.filter(\.me).count, 1)
        XCTAssertEqual(e.places.filter(\.home).count, 1)
        // The map opens on today's ground, away from home.
        XCTAssertEqual(LandgrabExploredPlan(e).opening?.centreLat ?? 0, 42.355, accuracy: 0.01)
        XCTAssertNil(SRDemoFixtures.landgrabRoute(method: "POST", parts: ["api", "native", "family", "landgrab", "explored"],
                                                  query: [:], clock: clock))
    }

    // MARK: - Modes and the map

    func testModeFallsBackToWhatThereIs() {
        XCTAssertEqual(LandgrabMode.effective("", hasFamily: true, hasWeek: true), .family, "family is the default")
        XCTAssertEqual(LandgrabMode.effective("week", hasFamily: true, hasWeek: true), .week)
        XCTAssertEqual(LandgrabMode.effective("family", hasFamily: false, hasWeek: true), .week)
        XCTAssertEqual(LandgrabMode.effective("week", hasFamily: true, hasWeek: false), .family)
        XCTAssertEqual(LandgrabMode.effective("nonsense", hasFamily: true, hasWeek: true), .family)
    }

    func testTheMapOpensOnFreshGroundThenHomeThenEverything() throws {
        var e = try explored()
        let plan = LandgrabExploredPlan(e)
        XCTAssertEqual(plan.areas.count, 2)
        XCTAssertEqual(plan.fresh.count, 1)
        // Today's ground is on the Common, not at home.
        XCTAssertEqual(plan.opening?.centreLat ?? 0, 42.3555, accuracy: 0.001)
        XCTAssertEqual(plan.opening, plan.freshRegion)
        XCTAssertNotNil(plan.placeRegions[e.places[1].id])

        e.fresh = nil
        let home = LandgrabExploredPlan(e)
        XCTAssertEqual(home.opening, home.placeRegions[e.places[0].id])
        XCTAssertEqual(home.opening?.centreLat ?? 0, 40.78, accuracy: 0.001)

        e.places = []
        XCTAssertEqual(LandgrabExploredPlan(e).opening, e.focus.map(LandgrabRegion.around))
        e.focus = nil
        let everything = LandgrabExploredPlan(e)
        XCTAssertEqual(everything.opening, everything.everything)
        XCTAssertGreaterThan(everything.everything?.latSpan ?? 0, 1, "home and the Common, both in view")
    }
}
