import XCTest
import CoreLocation
@testable import SRAppleApp

/// Close tracking: when it stops, what it watches, and that adding it cannot
/// cost an upgrade its queued uploads.
final class OutingTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func state(startedAt: Date? = nil, movedAt: Date? = nil) -> OutingState {
        OutingState(placeID: "h", placeLabel: "Home", startedAt: startedAt ?? t0, lastMovedAt: movedAt ?? t0,
                    anchorLat: 51.0, anchorLon: -1.0)
    }

    // MARK: - Movement

    func testJitterInsideFiftyMetresIsNotMovement() {
        // ~33 m north: a phone sitting still at a table.
        let next = Outing.moved(state(), lat: 51.0003, lon: -1.0, at: t0.addingTimeInterval(200))
        XCTAssertEqual(next.lastMovedAt, t0, "stillness clock must keep running")
    }

    func testLeavingTheStillRadiusRestartsTheClockAndMovesTheAnchor() {
        let at = t0.addingTimeInterval(200)
        let next = Outing.moved(state(), lat: 51.001, lon: -1.0, at: at) // ~111 m
        XCTAssertEqual(next.lastMovedAt, at)
        XCTAssertEqual(next.anchorLat, 51.001)
    }

    func testTheFirstFixSetsTheAnchor() {
        var s = state(); s.anchorLat = nil; s.anchorLon = nil
        let at = t0.addingTimeInterval(3)
        let next = Outing.moved(s, lat: 51.2, lon: -1.2, at: at)
        XCTAssertEqual(next.anchorLat, 51.2)
        XCTAssertEqual(next.lastMovedAt, at)
    }

    // MARK: - When it ends

    func testEndsAfterFiveStillMinutesNotBefore() {
        XCTAssertNil(Outing.shouldEnd(state(), now: t0.addingTimeInterval(299), battery: 0.8, charging: false))
        XCTAssertEqual(Outing.shouldEnd(state(), now: t0.addingTimeInterval(300), battery: 0.8, charging: false), .still)
    }

    func testTheFourHourCeilingEvenWhileMoving() {
        let s = state(startedAt: t0, movedAt: t0.addingTimeInterval(4 * 3600 - 1))
        XCTAssertEqual(Outing.shouldEnd(s, now: t0.addingTimeInterval(4 * 3600), battery: 0.8, charging: false), .tooLong)
    }

    func testLowBatteryEndsItUnlessCharging() {
        let s = state(movedAt: t0.addingTimeInterval(10))
        let now = t0.addingTimeInterval(20)
        XCTAssertEqual(Outing.shouldEnd(s, now: now, battery: 0.15, charging: false), .lowBattery)
        XCTAssertNil(Outing.shouldEnd(s, now: now, battery: 0.15, charging: true), "a phone on a car charger keeps going")
        XCTAssertNil(Outing.shouldEnd(s, now: now, battery: nil, charging: false), "unreadable battery (simulator) is not low")
    }

    // MARK: - What it watches

    func testATightPlaceIsWidenedToWhatIOSCanDetect() {
        let p = WatchedPlace(id: "s", label: "School", lat: 51, lon: -1, radiusM: 40)
        XCTAssertEqual(p.region.radius, WatchedPlace.minimumRadius)
        XCTAssertTrue(p.region.notifyOnExit)
        XCTAssertTrue(p.region.notifyOnEntry, "coming back ends the stretch")
        XCTAssertTrue(p.regionID.hasPrefix(Outing.regionPrefix))
    }

    func testMoreThanIOSWillHoldKeepsTheNearest() {
        let places = (0..<20).map { i in WatchedPlace(id: "\(i)", label: "P\(i)", lat: 51 + Double(i) * 0.1, lon: -1, radiusM: 150) }
        let chosen = Outing.toRegister(places, near: CLLocation(latitude: 52.9, longitude: -1))
        XCTAssertEqual(chosen.count, WatchedPlace.maximum)
        XCTAssertTrue(chosen.contains { $0.id == "19" })
        XCTAssertFalse(chosen.contains { $0.id == "0" })
    }

    // MARK: - Wire and state file

    func testAViewCarriesItsWatchListAndANoneViewShowsNobody() throws {
        let json = #"{"generatedAt":"2026-09-26T12:00:00Z","viewer":"none","people":[],"watch":[{"id":"h","label":"Home","lat":51,"lon":-1,"radiusM":120}]}"#
        let view = try JSONDecoder().decode(HouseholdView.self, from: Data(json.utf8))
        XCTAssertFalse(view.showsHousehold)
        XCTAssertEqual(view.watch?.first?.label, "Home")
        let older = try JSONDecoder().decode(HouseholdView.self, from: Data(#"{"generatedAt":"x","viewer":"owner","people":[]}"#.utf8))
        XCTAssertNil(older.watch, "a site older than close tracking changes nothing")
        XCTAssertTrue(older.showsHousehold)
    }

    func testAStateFileFromBeforeCloseTrackingStillDecodesWithItOn() throws {
        let old = try JSONDecoder().decode(PersistedState.self, from: Data(#"{"sharing":true,"batches":[]}"#.utf8))
        XCTAssertTrue(old.closeTracking, "on for everyone sharing")
        XCTAssertTrue(old.watchedPlaces.isEmpty)
        XCTAssertNil(old.outing)
        XCTAssertTrue(old.sharing)
    }

    func testAnOutingSurvivesTheStateFile() throws {
        var s = PersistedState()
        s.outing = state()
        s.watchedPlaces = [WatchedPlace(id: "h", label: "Home", lat: 51, lon: -1, radiusM: 120)]
        let back = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.outing, s.outing)
        XCTAssertEqual(back.watchedPlaces, s.watchedPlaces)
    }
}
