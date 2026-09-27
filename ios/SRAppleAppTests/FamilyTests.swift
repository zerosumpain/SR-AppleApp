import XCTest
import CoreLocation
@testable import SRAppleApp

/// The Family tab's model: what the site files for this person, and the few
/// things the phone decides for itself — where a line may be drawn, how a
/// figure reads, what a battery level says.
final class FamilyTests: XCTestCase {

    private func person(_ json: String) throws -> FamilyPerson {
        try JSONDecoder().decode(FamilyPerson.self, from: Data(json.utf8))
    }

    // MARK: - Decoding

    func testAPersonDecodesWithSelfRenamed() throws {
        let p = try person(#"{"subject":"sam","name":"Sam","self":true,"status":"out","line":"At School · seen 3m ago","batteryPct":64,"lastSeenAt":"2026-09-26T09:00:00Z","position":{"lat":40.77,"lon":-73.97,"at":"2026-09-26T09:00:00Z"},"today":{"firstOut":"08:12","minutesOut":125,"distanceKm":4.25,"stops":["Home","School"],"trail":[[40.77,-73.97,1790000000]]}}"#)
        XCTAssertTrue(p.isSelf)
        XCTAssertEqual(p.initial, "S")
        XCTAssertEqual(p.position?.coordinate.latitude, 40.77)
        XCTAssertEqual(p.today?.stops, ["Home", "School"])
    }

    func testSomebodyNotSharingDecodesWithNothingButTheirName() throws {
        let p = try person(#"{"subject":"pat","name":"Pat","self":false,"status":"off","line":"Not sharing their location.","batteryPct":null,"lastSeenAt":null,"position":null,"today":null}"#)
        XCTAssertFalse(p.sharing)
        XCTAssertNil(p.position)
        XCTAssertNil(p.batteryPct)
        XCTAssertNil(p.today)
    }

    func testNoViewYetDecodesAsNil() throws {
        let r = try JSONDecoder().decode(HouseholdViewResponse.self, from: Data(#"{"view":null,"updated":null}"#.utf8))
        XCTAssertNil(r.view)
    }

    func testTheDemoHouseholdDecodesAndCoversEveryState() {
        let view = SRDemoFixtures.householdView(now: Date()).view
        XCTAssertNotNil(view)
        XCTAssertEqual(Set(view?.people.map(\.status) ?? []), ["out", "home", "unknown", "off"])
        XCTAssertEqual(view?.people.first?.isSelf, true)
        XCTAssertEqual(view?.placed.count, 4, "somebody not sharing has no pin")
    }

    // MARK: - Where a line may be drawn

    func testATrailBreaksAtAGapAndDropsALoneFix() {
        let today = FamilyPerson.Today(firstOut: nil, minutesOut: 0, distanceKm: 0, stops: [], trail: [
            [51.0, 0, 1000], [51.001, 0, 1060], [51.002, 0, 1120],
            // Twenty minutes later: a new stretch.
            [51.1, 0, 2320], [51.101, 0, 2380],
            // And a lone fix after another hole draws nothing.
            [51.3, 0, 5000],
        ])
        let segments = today.segments()
        XCTAssertEqual(segments.map(\.count), [3, 2])
    }

    func testTheDemoWalkBreaksWhereItsHoleIs() {
        let walker = SRDemoFixtures.householdView(now: Date()).view?.people.first
        XCTAssertEqual(walker?.today?.segments().count, 2)
    }

    // MARK: - Figures

    func testTimeOutAndDistanceRead() {
        let make = { (mins: Int, km: Double) in FamilyPerson.Today(firstOut: nil, minutesOut: mins, distanceKm: km, stops: [], trail: []) }
        XCTAssertEqual(make(0, 0).timeOut, "—")
        XCTAssertEqual(make(40, 0).timeOut, "40m")
        XCTAssertEqual(make(125, 0).timeOut, "2h 05m")
        XCTAssertEqual(make(0, 0).distance, "—")
        XCTAssertEqual(make(0, 4.25).distance, "4.2 km")
        XCTAssertEqual(make(0, 12.4).distance, "12 km")
    }

    func testTheSummaryNamesOnlyStatesSomebodyHas() throws {
        let view = try XCTUnwrap(SRDemoFixtures.householdView(now: Date()).view)
        XCTAssertEqual(view.summary, "1 home · 2 out · 1 not seen lately · 1 not sharing")
        let empty = HouseholdView(generatedAt: "", viewer: "owner", people: [])
        XCTAssertEqual(empty.summary, "Nobody yet")
    }

    // MARK: - Battery

    func testBatteryGlyphAndLowThreshold() {
        XCTAssertEqual(BatteryReading.symbol(5), "battery.0percent")
        XCTAssertEqual(BatteryReading.symbol(50), "battery.50percent")
        XCTAssertEqual(BatteryReading.symbol(100), "battery.100percent")
        XCTAssertTrue(BatteryReading.isLow(20))
        XCTAssertFalse(BatteryReading.isLow(21))
    }

    @MainActor func testAFixCarriesWholePercentOrNothing() {
        XCTAssertEqual(LocationCollector.batteryPercent(level: 0.644), 64)
        XCTAssertEqual(LocationCollector.batteryPercent(level: 1), 100)
        XCTAssertNil(LocationCollector.batteryPercent(level: -1), "the simulator answers -1")
    }

    func testAQueuedFixFromBeforeBatteryStillDecodes() throws {
        // The outbox persists LocationRecords: an upgrade must not throw away
        // what an older build queued.
        let old = try JSONDecoder().decode(LocationRecord.self, from: Data(#"{"id":"a","recorded":"2026-09-26T09:00:00Z","latitude":51,"longitude":0,"accuracy":5,"speed":0,"moving":false}"#.utf8))
        XCTAssertNil(old.battery)
        let encoded = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        XCTAssertFalse(encoded.contains("battery"), "no battery is sent as no key, which every pilot accepts")
    }

    // MARK: - Who is moving

    func testMovingDecodesAndIsOptional() throws {
        let json = #"{"subject":"sam","name":"Sam","self":false,"status":"out","line":"x","batteryPct":null,"lastSeenAt":null,"position":{"lat":1,"lon":2,"at":"2026-09-26T09:00:00Z"},"moving":{"mode":"vehicle","speedKmh":48,"since":"2026-09-26T08:55:00Z"},"today":null}"#
        let sam = try JSONDecoder().decode(FamilyPerson.self, from: Data(json.utf8))
        XCTAssertEqual(sam.moving?.verb, "travelling")
        XCTAssertEqual(sam.movingLead, "Sam is travelling")
        let older = #"{"subject":"sam","name":"Sam","self":true,"status":"home","line":"x","batteryPct":null,"lastSeenAt":null,"position":null,"today":null}"#
        XCTAssertNil(try JSONDecoder().decode(FamilyPerson.self, from: Data(older.utf8)).moving, "a site older than moving")
    }

    func testTheDemoHouseholdHasSomebodyMoving() {
        let view = SRDemoFixtures.householdView(now: Date()).view
        XCTAssertEqual(view?.moving.map(\.subject), ["alex"])
        XCTAssertEqual(view?.moving.first?.movingLead, "You are walking", "your own card says you")
    }

    func testAPlaceIsPhrasedStreetThenTownWithoutRepeats() {
        XCTAssertEqual(PlaceNamer.phrase(street: "Station Road", area: "Bank Top", town: "Darlington"), "Station Road, Darlington")
        XCTAssertEqual(PlaceNamer.phrase(street: nil, area: "Bank Top", town: "Darlington"), "Bank Top, Darlington")
        XCTAssertEqual(PlaceNamer.phrase(street: nil, area: nil, town: "Darlington"), "Darlington")
        XCTAssertEqual(PlaceNamer.phrase(street: "Darlington", area: nil, town: "Darlington"), "Darlington")
        XCTAssertNil(PlaceNamer.phrase(street: nil, area: " ", town: nil))
        XCTAssertEqual(PlaceNamer.key(lat: 54.52345, lon: -1.55432), "54.523,-1.554")
    }

    // MARK: - Today's places

    /// A person at a spot, for the grouping tests. `moving` makes them a walker.
    private func at(_ name: String, _ line: String, status: String = "out", lat: Double = 51, lon: Double = 0,
                    isSelf: Bool = false, moving: Bool = false) throws -> FamilyPerson {
        let walk = moving ? #","moving":{"mode":"walking","speedKmh":5,"since":"2026-09-27T08:00:00Z"}"# : ""
        return try person(#"{"subject":"\#(name.lowercased())","name":"\#(name)","self":\#(isSelf),"status":"\#(status)","line":"\#(line)","batteryPct":80,"lastSeenAt":"2026-09-27T08:10:00Z","position":{"lat":\#(lat),"lon":\#(lon),"at":"2026-09-27T08:10:00Z"},"today":null\#(walk)}"#)
    }

    func testTheSitesPlaceIsReadFromTheLine() throws {
        XCTAssertEqual(try at("Sam", "At School · seen 6m ago").placeName, "School")
        XCTAssertEqual(try at("Alex", "Bethesda Terrace · seen 2m ago").placeName, "Bethesda Terrace")
        XCTAssertEqual(try at("Robin", "At home · seen 4m ago", status: "home").placeName, "Home")
        XCTAssertEqual(try at("Kit", "Last at The Reservoir · 2h ago", status: "unknown").placeName, "The Reservoir")
        XCTAssertNil(try at("Pat", "Not sharing their location.", status: "off").placeName)
        XCTAssertEqual(try at("Sam", "At School · seen 6m ago").seenLine, "Seen 6m ago")
    }

    func testTheDemoHouseholdGroupsYouFirstThenHome() {
        let view = SRDemoFixtures.householdView(now: Date()).view
        XCTAssertEqual(view?.places().map(\.name), ["Bethesda Terrace", "Home", "School"])
        XCTAssertEqual(view?.absentLines, ["Kit was last at The Reservoir, 2h ago.", "Pat isn't sharing their location."])
    }

    func testTwoPeopleAtOneSavedPlaceAreOneGroup() throws {
        let view = HouseholdView(generatedAt: "", viewer: "owner", people: [
            try at("Sam", "At School · seen 6m ago", lat: 51),
            try at("Kit", "At school · seen 1m ago", lat: 52),
        ])
        XCTAssertEqual(view.places().map(\.name), ["School"])
        XCTAssertEqual(view.places().first?.people.map(\.name), ["Sam", "Kit"])
    }

    func testPeopleStandingTogetherMergeUnderTheSavedPlacesName() throws {
        // ~55 m apart: one matched to a saved place, one not.
        let view = HouseholdView(generatedAt: "", viewer: "owner", people: [
            try at("Robin", "Station Road · seen 1m ago", lat: 51.0005, isSelf: true),
            try at("Sam", "At Café Nero · seen 2m ago", lat: 51.0),
        ])
        let places = view.places()
        XCTAssertEqual(places.map(\.name), ["Café Nero"])
        XCTAssertEqual(places.first?.people.map(\.name), ["Robin", "Sam"], "you first within a place")
    }

    func testHomeAndWalkersNeverMergeByDistance() throws {
        let view = HouseholdView(generatedAt: "", viewer: "owner", people: [
            try at("Robin", "At home · seen 4m ago", status: "home", lat: 51.0),
            try at("Sam", "At The Park · seen 2m ago", lat: 51.0005),
            try at("Alex", "Park Lane · seen 1m ago", lat: 51.0004, moving: true),
        ])
        XCTAssertEqual(view.places().map(\.name), ["Home", "The Park", "Park Lane"])
        XCTAssertEqual(view.places().last?.isMoving, true)
    }

    func testFarApartPeopleStaySeparateAndBiggerGroupsComeFirst() throws {
        let view = HouseholdView(generatedAt: "", viewer: "owner", people: [
            try at("Kit", "At The Gym · seen 3m ago", lat: 52),
            try at("Sam", "At School · seen 6m ago", lat: 51),
            try at("Pat", "At School · seen 5m ago", lat: 51.0001),
        ])
        XCTAssertEqual(view.places().map(\.name), ["School", "The Gym"])
    }
}

