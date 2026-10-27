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

    // MARK: - What is behind you comes off the map

    /// A routed day: hotel → Pantheon → Trevi → hotel, each leg a line of
    /// points a few metres apart, the way home down the morning's streets.
    private func routedDay() -> PlannedDay {
        var d = day()
        let hotel = d.stops[0].location!, pantheon = d.stops[1].location!, trevi = d.stops[2].location!
        func leg(_ from: Int, _ a: TripLatLng, _ b: TripLatLng) -> PlannedLeg {
            PlannedLeg(fromStopId: d.stops[from].id, toStopId: d.stops[from + 1].id, mode: .walk, durationSec: 600,
                       distanceM: nil, estimated: false, line: TripMapScene.densify([a, b], stepM: 20))
        }
        d.legs = [leg(0, hotel, pantheon), leg(1, pantheon, trevi), leg(2, trevi, hotel)]
        return d
    }

    private func walk(_ a: TripLatLng, _ b: TripLatLng, upTo share: Double = 1) -> [TripLatLng] {
        let line = TripMapScene.densify([a, b], stepM: 10)
        return Array(line.prefix(Int(Double(line.count) * share)))
    }

    func testAWalkedLegComesOffAndItsStopFades() {
        let d = routedDay()
        let hotel = d.stops[0].location!, pantheon = d.stops[1].location!
        let walked = TripMapScene.Walked(trail: walk(hotel, pantheon))
        let scene = TripMapScene.day(d, stages: [.morning, .morning, .afternoon, .evening], done: [], nextId: "trevi",
                                     selectedId: nil, walked: walked)
        XCTAssertEqual(scene.lines.count, 2, "hotel → Pantheon is behind you")
        XCTAssertEqual(scene.pins.first { $0.id == "pantheon" }?.badge.faded, true)
    }

    func testTheLegYouAreOnStartsWhereYouAre() {
        let d = routedDay()
        let pantheon = d.stops[1].location!, trevi = d.stops[2].location!
        let hotel = d.stops[0].location!
        let trail = walk(hotel, pantheon) + walk(pantheon, trevi, upTo: 0.5)
        let lines = TripMapScene.legs(d, done: [], nextId: "trevi", walked: TripMapScene.Walked(trail: trail))
        XCTAssertEqual(lines.count, 2)
        let left = TripMapScene.lengthM(lines[0].points)
        let whole = TripMapScene.lengthM([pantheon, trevi])
        XCTAssertEqual(left, whole / 2, accuracy: 40, "about half the way to Trevi is left")
        XCTAssertEqual(lines[0].points.last, trevi)
    }

    /// The walk home goes the morning's way; it stays on the map until it
    /// is the walk you are on.
    func testALaterLegDownTheSameStreetsStays() {
        var d = routedDay()
        let hotel = d.stops[0].location!, pantheon = d.stops[1].location!
        // Trevi moved onto the morning's street, so the way home retraces it.
        d.stops[2].location = TripLatLng(lat: (hotel.lat + pantheon.lat) / 2, lng: (hotel.lng + pantheon.lng) / 2)
        d.legs[1].line = nil
        d.legs[2].line = [d.stops[2].location!, hotel]
        let walked = TripMapScene.Walked(trail: walk(hotel, pantheon, upTo: 0.3))
        let lines = TripMapScene.legs(d, done: [], nextId: "pantheon", walked: walked)
        XCTAssertEqual(lines.count, 3, "nothing walked to the end yet, so every leg is ahead")
        XCTAssertEqual(lines[2].points, [d.stops[2].location!, hotel])
    }

    func testADoneStopsLegIsNotDrawnAtAll() {
        let lines = TripMapScene.legs(routedDay(), done: ["pantheon"], nextId: "trevi")
        XCTAssertEqual(lines.count, 2)
    }

    func testTheOverviewDropsDaysGoneBy() {
        var yesterday = routedDay()
        yesterday.date = "2026-10-26"
        let today = routedDay()
        let scene = TripMapScene.overview([yesterday, today], stays: [], today: "2026-10-27")
        XCTAssertEqual(scene.lines.count, 3, "only today's legs")
        XCTAssertEqual(scene.pins.filter { $0.id == "2026-10-26" }.allSatisfy(\.badge.faded), true)
        XCTAssertEqual(TripMapScene.overview([yesterday, today], stays: []).lines.count, 6, "no date: every day whole")
    }
}
