import XCTest
@testable import SRAppleApp

/// Trips v8, craft (plan §5.5): map pins VoiceOver can reach. (The money
/// that follows the destination is the planning batch's
/// `TripDecisions.currencySymbol`, tested with it.)
///
/// Foundation only: the Linux harness runs this file too.
final class TripCraftTests: XCTestCase {

    // MARK: - Pins VoiceOver can reach

    /// The hotel, the Pantheon (next), Trevi, back to the hotel.
    private func day() -> PlannedDay {
        let hotel = TripLatLng(lat: 41.895, lng: 12.474)
        func stop(_ id: String, _ title: String, _ kind: StopKind, _ at: TripLatLng, _ a: Double) -> PlannedStop {
            PlannedStop(id: id, kind: kind, wishId: kind == .wish ? id : nil, title: title, location: at,
                        arriveMin: a, departMin: a + 30, waitSec: 0, locked: false, bookingId: nil, warnings: [])
        }
        return PlannedDay(
            date: "2026-10-27", stayId: "h",
            stops: [stop("s1", "Hotel Artemide", .stay, hotel, 540),
                    stop("pantheon", "Pantheon", .wish, TripLatLng(lat: 41.8986, lng: 12.4769), 570),
                    stop("trevi", "Trevi Fountain", .wish, TripLatLng(lat: 41.9009, lng: 12.4833), 860),
                    stop("s2", "Hotel Artemide", .stay, hotel, 1080)],
            legs: [], warnings: []
        )
    }

    func testEveryPinSaysItsNumberTitleAndTime() {
        let scene = TripMapScene.day(day(), stages: [.morning, .morning, .afternoon, .evening], done: [], nextId: "pantheon", selectedId: nil)
        // The hotel twice is one pin, as it is drawn.
        XCTAssertEqual(scene.pins.map(\.label), ["Hotel Artemide, 09:00", "1. Pantheon, 09:30, next", "2. Trevi Fountain, 14:20"])
    }

    func testADonePinSaysSo() {
        let scene = TripMapScene.day(day(), stages: [.morning, .morning, .afternoon, .evening], done: ["pantheon"], nextId: "trevi", selectedId: nil)
        XCTAssertEqual(scene.pins.first { $0.id == "pantheon" }?.label, "1. Pantheon, 09:30, done")
        XCTAssertEqual(scene.pins.first { $0.id == "trevi" }?.label, "2. Trevi Fountain, 14:20, next")
    }

    func testTheOverviewSpeaksForEachDayNotEachDot() {
        let scene = TripMapScene.overview([day()], stays: [])
        XCTAssertEqual(scene.pins.compactMap(\.label), ["Day 1, from Pantheon, 2 places"])
        XCTAssertEqual(scene.pins.count, 2, "the second visit is a dot with no element of its own")
    }
}
