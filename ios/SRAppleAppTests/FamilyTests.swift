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
}
