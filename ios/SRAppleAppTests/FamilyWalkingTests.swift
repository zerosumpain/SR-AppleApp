import XCTest
@testable import SRAppleApp

/// "Your walking": the site's movement figures as the app reads and says them
/// (`Family/FamilyWalking.swift`). Linux-run.
final class FamilyWalkingTests: XCTestCase {
    private let json = """
    {"subject":"rory","name":"Rory","days":30,"stats":{
      "byMode":{"foot":{"count":20,"metres":24000,"seconds":19800},"car":{"count":4,"metres":40000,"seconds":3600},
                "rail":{"count":0,"metres":0,"seconds":0},"other":{"count":0,"metres":0,"seconds":0}},
      "walkingPace":{"medianMps":1.4,"p75Mps":1.5,"n":18,"weekly":[
        {"weekStart":"2026-10-12","medianMps":1.25,"n":4},{"weekStart":"2026-10-19","medianMps":1.25,"n":4},
        {"weekStart":"2026-10-26","medianMps":1.4,"n":5},{"weekStart":"2026-11-02","medianMps":1.4,"n":5}]},
      "commonTrips":[
        {"fromLabel":"Home","toLabel":"Pool","count":4,"usualDeparture":"17:30","medianSeconds":720,"totalSeconds":2900,"mode":"car"},
        {"fromLabel":"Home","toLabel":"School","count":9,"usualDeparture":"08:24","medianSeconds":1020,"totalSeconds":9180,"mode":"foot",
         "medianMetres":1300,"fastestSeconds":840,"medianPaceSecPerKm":785,"lastAt":"2026-11-06T08:21:00.000Z"}],
      "roundTrips":null,
      "timeOut":[{"date":"2026-11-08","minutesOut":95,"firstOut":"10:30","lastIn":"12:05"}],
      "placeTime":{"windowMinutes":43200,"places":[],"unnamed":{"minutes":0,"visits":0},"transitMinutes":0}}}
    """

    func testDecodesTheSiteAndAnOlderSiteWithoutTheNewTripFields() throws {
        let movement = try JSONDecoder().decode(FamilyMovement.self, from: Data(json.utf8))
        XCTAssertEqual(movement.stats.commonTrips.count, 2)
        XCTAssertNil(movement.stats.commonTrips[0].medianPaceSecPerKm, "the car trip, and an older site, have none")
        XCTAssertEqual(movement.stats.commonTrips[1].medianPaceSecPerKm, 785)
        XCTAssertEqual(movement.stats.byMode["foot"]?.metres, 24000)
        let bare = try JSONDecoder().decode(FamilyMovement.self, from: Data(#"{"subject":"a","name":"A","days":30,"stats":{}}"#.utf8))
        XCTAssertNil(bare.stats.walkingPace)
        XCTAssertTrue(bare.stats.commonTrips.isEmpty)
    }

    func testSaysPaceSpeedAndBand() {
        XCTAssertEqual(WalkingWords.pace(mps: 1.4), "11:54 /km")
        XCTAssertEqual(WalkingWords.speed(mps: 1.4), "5.0 km/h")
        XCTAssertEqual(WalkingWords.band(mps: 1.4), "Brisk")
        XCTAssertEqual(WalkingWords.band(mps: 1.2), "Steady")
        XCTAssertEqual(WalkingWords.band(mps: 0.95), "Easy")
    }

    func testTrendNeedsFourWeeksAndARealChange() throws {
        let movement = try JSONDecoder().decode(FamilyMovement.self, from: Data(json.utf8))
        let trend = try XCTUnwrap(WalkingWords.trend(movement.stats.walkingPace?.weekly ?? []))
        XCTAssertTrue(trend.quicker)
        XCTAssertEqual(trend.text, "Quicker lately — 1:26 per km faster than the weeks before")
        XCTAssertNil(WalkingWords.trend(Array(movement.stats.walkingPace!.weekly.prefix(3))))
        let flat = (0..<5).map { FamilyMovement.Pace.Week(weekStart: "2026-10-0\($0)", medianMps: 1.4, n: 3) }
        XCTAssertNil(WalkingWords.trend(flat))
    }

    func testWalkedTripsComeFirstAndSayTimeBestDistanceAndPace() throws {
        let movement = try JSONDecoder().decode(FamilyMovement.self, from: Data(json.utf8))
        let (walked, other) = WalkingWords.ordered(movement.stats.commonTrips)
        XCTAssertEqual(walked.map(\.id), ["Home→School·foot"])
        XCTAssertEqual(other.map(\.id), ["Home→Pool·car"])
        XCTAssertEqual(WalkingWords.tripLine(walked[0]), "Usually 17 min · best 14 min · 1.3 km · 13:05 /km")
        XCTAssertEqual(WalkingWords.tripWhen(walked[0]), "9 times · leaves about 08:24")
        XCTAssertEqual(WalkingWords.tripLine(other[0]), "Usually 12 min")
        XCTAssertEqual(WalkingWords.perWeek(metres: 24000, days: 30), "5.6 km a week")
    }
}
