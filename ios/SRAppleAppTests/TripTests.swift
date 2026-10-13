import XCTest
@testable import SRAppleApp

/// The trip companion's contracts: the Live Activity's shape (SR-Main
/// `docs/superpowers/specs/2026-10-13-trips.md`, "Live Activity"), the wire
/// shapes the phone sends, and the pure logic the Day screen stands on.
final class TripTests: XCTestCase {

    // MARK: Live Activity

    /// The contract's ContentState, verbatim: epoch SECONDS, not
    /// ActivityKit's 2001-based dates. A key that drifts drops the update.
    func testTheContractsContentStateDecodes() throws {
        let json = #"{"nextTitle":"Pantheon","leaveAt":1792152000,"legMode":"walk","legMinutes":12,"arriveAt":1792152720,"stopIndex":3,"stopCount":8}"#
        let state = try JSONDecoder().decode(TripAttributes.ContentState.self, from: Data(json.utf8))
        XCTAssertEqual(state.nextTitle, "Pantheon")
        XCTAssertEqual(state.leave, Date(timeIntervalSince1970: 1_792_152_000))
        XCTAssertEqual(state.arrive.timeIntervalSince(state.leave), 720)
        XCTAssertEqual(state.legLine, "12 min walk")
        XCTAssertEqual(state.stopLine, "Stop 4 of 8")
        XCTAssertEqual(state.symbol, "figure.walk")
        XCTAssertEqual(state.leaveLine(now: Date(timeIntervalSince1970: 1_792_152_000 - 8 * 60 - 5)), "leave in 8 min")
        XCTAssertEqual(state.leaveLine(now: Date(timeIntervalSince1970: 1_792_152_030)), "leave now")
    }

    func testTheContractsAttributesDecode() throws {
        let json = #"{"tripId":"trip-rome","title":"Rome in October"}"#
        let attributes = try JSONDecoder().decode(TripAttributes.self, from: Data(json.utf8))
        XCTAssertEqual(attributes.tripId, "trip-rome")
        XCTAssertEqual(attributes.title, "Rome in October")
    }

    func testTransitSaysSo() throws {
        let json = #"{"nextTitle":"Vatican Museums","leaveAt":0,"legMode":"transit","legMinutes":25,"arriveAt":1500,"stopIndex":0,"stopCount":2}"#
        let state = try JSONDecoder().decode(TripAttributes.ContentState.self, from: Data(json.utf8))
        XCTAssertEqual(state.legLine, "25 min by transit")
        XCTAssertEqual(state.symbol, "tram.fill")
    }

    /// What the app puts on the Lock Screen at the Pantheon: the next stop,
    /// the plan's leave time and the leg, in epoch seconds.
    func testTheCardIsBuiltFromWhereYouAre() throws {
        let clock = TripClock("Europe/Rome")
        let day = Self.day()
        let marks = ["stay:2026-10-27:start": TripStopMark(leftAt: clock.date("2026-10-27", minutes: 540))]
        let progress = TripProgress.of(day: day, marks: marks, nowMin: 600, clock: clock)
        let state = try XCTUnwrap(TripLive.state(day: day, progress: progress, clock: clock))
        XCTAssertEqual(state.nextTitle, "Pantheon")
        XCTAssertEqual(state.legMinutes, 12)
        XCTAssertEqual(state.stopIndex, 1)
        XCTAssertEqual(state.stopCount, 3)
        XCTAssertEqual(state.arriveAt, try XCTUnwrap(clock.date("2026-10-27", minutes: 560)).timeIntervalSince1970)
    }

    // MARK: Where you are in the day

    func testNoMarksMeansAtTheStayAndNeverBehind() {
        let p = TripProgress.of(day: Self.day(), marks: [:], nowMin: 900, clock: TripClock("Europe/Rome"))
        XCTAssertEqual(p.phase, .at(0))
        XCTAssertEqual(p.next, 1)
        XCTAssertEqual(p.behindMin, 0, "silence is not evidence of lateness")
    }

    func testArrivingLateIsBehind() throws {
        let clock = TripClock("Europe/Rome")
        let marks = [
            "stay:2026-10-27:start": TripStopMark(leftAt: clock.date("2026-10-27", minutes: 548)),
            "pantheon": TripStopMark(arrivedAt: clock.date("2026-10-27", minutes: 585)),
        ]
        let p = TripProgress.of(day: Self.day(), marks: marks, nowMin: 590, clock: clock)
        XCTAssertEqual(p.phase, .at(1))
        XCTAssertEqual(p.behindMin, 25)
        XCTAssertTrue(p.showsBehind)
        XCTAssertEqual(p.atStopId, "pantheon")
        XCTAssertEqual(p.doneStopIds, ["stay:2026-10-27:start"])
    }

    // MARK: The wire

    /// `string | null` fields go up as null, not missing.
    func testAnEventWritesItsNulls() throws {
        let event = TripEvent(clientId: "c1", kind: .optionApplied, stopId: nil, wishId: nil, at: "2026-10-27T10:00:00.000Z",
                              detail: ["day": try XCTUnwrap(TripJSON.from(Self.day()))])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "option-applied")
        XCTAssertTrue(object["stopId"] is NSNull)
        let day = try XCTUnwrap((object["detail"] as? [String: Any])?["day"] as? [String: Any])
        let stops = try XCTUnwrap(day["stops"] as? [[String: Any]])
        XCTAssertTrue(stops[0]["bookingId"] is NSNull)
        XCTAssertEqual(event.detail?["day"]?.decode(PlannedDay.self), Self.day())
    }

    func testAReplanRequestWritesItsNulls() throws {
        let body = TripReplanBody(date: "2026-10-27", nowMin: 600, position: nil, atStopId: nil, doneStopIds: [])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertTrue(object["position"] is NSNull)
        XCTAssertTrue(object["atStopId"] is NSNull)
    }

    func testTripIdsAreEscapedInPaths() {
        XCTAssertEqual(TripsAPI.path("trip-rome"), "api/native/trips/trip-rome")
        XCTAssertEqual(TripsAPI.path("a/b"), "api/native/trips/a%2Fb")
    }

    /// The demo's Rome trip is a valid bundle, and its day is running now.
    func testTheDemoTripDecodesAndRunsToday() throws {
        let base = "https://strangeramblings.com/"
        let list = try JSONDecoder().decode(TripList.self, from:
            SRDemoFixtures.reply(method: "GET", url: URL(string: base + "api/native/trips")!, body: nil).body)
        XCTAssertEqual(list.trips.map(\.id), [TripDemo.tripId])
        let bundle = try JSONDecoder().decode(TripBundle.self, from:
            SRDemoFixtures.reply(method: "GET", url: URL(string: base + "api/native/trips/\(TripDemo.tripId)")!, body: nil).body)
        let today = TripClock(bundle.trip.timeZone).localDate(Date())
        let day = try XCTUnwrap(bundle.day(today))
        XCTAssertEqual(day.legs.count, day.stops.count - 1)
        XCTAssertNotNil(bundle.matrices[today])
    }

    // MARK: Regions

    func testTheRegionBudgetLeavesTheCollectorsPlaces() {
        XCTAssertEqual(TripArrivals.budget(reserved: 1, foreignNow: 0), 15)
        XCTAssertEqual(TripArrivals.budget(reserved: 16, foreignNow: 3), 4)
        XCTAssertEqual(TripArrivals.budget(reserved: 1, foreignNow: 19), 1)
        XCTAssertEqual(TripArrivals.budget(reserved: 21, foreignNow: 0), 0)
    }

    func testRegionIdentifiersRoundTrip() throws {
        let id = TripArrivals.identifier(trip: "trip-rome", date: "2026-10-27", stop: "stay:2026-10-27:end")
        let key = try XCTUnwrap(TripArrivals.parse(id))
        XCTAssertEqual(key.trip, "trip-rome")
        XCTAssertEqual(key.stop, "stay:2026-10-27:end")
        XCTAssertNil(TripArrivals.parse("sr.watch.home"))
    }

    // MARK: Words

    func testLongWaitsAreFreeTime() {
        var stop = Self.day().stops[1]
        stop.waitSec = 20 * 60
        XCTAssertEqual(TripWords.wait(stop), "Wait 20 min before it starts")
        stop.waitSec = 70 * 60
        XCTAssertEqual(TripWords.wait(stop), "Free time · 1 h 10 first")
        stop.waitSec = 0
        XCTAssertNil(TripWords.wait(stop))
    }

    func testTimesAreLocalAndWrap() {
        XCTAssertEqual(TripFormat.time(860), "14:20")
        XCTAssertEqual(TripFormat.time(1450), "00:10")
        XCTAssertEqual(TripFormat.duration(minutes: 65), "1 h 05")
        let clock = TripClock("Europe/Rome")
        XCTAssertEqual(clock.date("2026-10-27", minutes: 860).map(clock.localDate), "2026-10-27")
        XCTAssertEqual(clock.date("2026-10-27", minutes: 860).map(clock.minutes), 860)
    }

    // MARK: Fixture

    private static func day() -> PlannedDay {
        func stop(_ id: String, _ kind: StopKind, _ a: Double, _ d: Double) -> PlannedStop {
            PlannedStop(id: id, kind: kind, wishId: kind == .wish ? id : nil, title: id == "pantheon" ? "Pantheon" : id,
                        location: TripLatLng(lat: 41.8986, lng: 12.4769), arriveMin: a, departMin: d, waitSec: 0,
                        locked: false, bookingId: nil, warnings: [])
        }
        let leg = PlannedLeg(fromStopId: "", toStopId: "", mode: .walk, durationSec: 720, distanceM: 900, estimated: false, line: nil)
        return PlannedDay(
            date: "2026-10-27", stayId: "campo",
            stops: [stop("stay:2026-10-27:start", .stay, 540, 548), stop("pantheon", .wish, 560, 605), stop("stay:2026-10-27:end", .stay, 640, 640)],
            legs: [leg, leg], warnings: []
        )
    }
}
