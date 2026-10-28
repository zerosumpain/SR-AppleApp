import XCTest
@testable import SRAppleApp

/// The Trips widget: which face it draws as the day goes on, its words, its
/// timeline and its link.
///
/// Foundation only: `scripts/home-check.sh` runs this file on Linux too.
final class TripsWidgetTests: XCTestCase {

    /// Wednesday 28 October 2026, 10:00 in Rome (09:00 UTC).
    private let ten = Date(timeIntervalSince1970: 1_793_178_000)
    private let rome = "Europe/Rome"

    private func at(_ minutes: Double) -> Date { ten.addingTimeInterval(minutes * 60) }

    private var day: TripsWidgetSnapshot {
        TripsWidgetSnapshot(
            kind: .running, tripId: "t/1", title: "Rome", destination: "Rome, Italy", timeZone: rome,
            startDate: "2026-10-26", endDate: "2026-11-01", date: "2026-10-28",
            stops: [
                TripsWidgetStop(title: "Pantheon", leaveAt: at(18), arriveAt: at(30), legMode: "walk", legMinutes: 12, number: 3),
                TripsWidgetStop(title: "Lunch", leaveAt: at(95), arriveAt: at(110), legMode: "transit", legMinutes: 15, number: 4),
            ],
            stopCount: 5, dayEndsAt: at(240), savedAt: ten
        )
    }

    private var upcoming: TripsWidgetSnapshot {
        TripsWidgetSnapshot(
            kind: .upcoming, tripId: "t2", title: "Lisbon", destination: nil, timeZone: rome,
            startDate: "2026-11-09", endDate: "2026-11-14", date: nil, stops: [], stopCount: 0, dayEndsAt: nil, savedAt: ten
        )
    }

    // MARK: - Faces

    func testTheNextStopIsTheFirstNotYetReached() {
        guard case .next(let stop, let after) = TripsWidget.face(day, now: ten) else { return XCTFail("a next stop") }
        XCTAssertEqual(stop.title, "Pantheon")
        XCTAssertEqual(after.map(\.title), ["Lunch"])
    }

    func testThePlanMovesOnAsArrivalsPass() {
        guard case .next(let stop, let after) = TripsWidget.face(day, now: at(31)) else { return XCTFail("a next stop") }
        XCTAssertEqual(stop.title, "Lunch")
        XCTAssertTrue(after.isEmpty)
    }

    func testAfterTheLastStopTheDayIsDoneUntilMidnight() {
        XCTAssertEqual(TripsWidget.face(day, now: at(120)), .dayDone)
        XCTAssertEqual(TripsWidget.face(day, now: at(600)), .dayDone, "still the 28th in Rome")
        XCTAssertEqual(TripsWidget.face(day, now: at(15 * 60)), .none, "the 29th: the app has a new day to work out")
    }

    func testTheCountdownIsOnTheTripsClock() {
        XCTAssertEqual(TripsWidget.face(upcoming, now: ten), .countdown(days: 12))
        // 23:30 UTC on the 8th is already the 9th in Rome.
        let late = Date(timeIntervalSince1970: 1_794_180_600)
        XCTAssertEqual(TripsWidget.face(upcoming, now: late), .countdown(days: 0))
        XCTAssertEqual(TripsWidget.face(nil, now: ten), .none)
    }

    func testAStartedUpcomingTripShowsNothing() {
        var started = upcoming
        started.startDate = "2026-10-27"
        XCTAssertEqual(TripsWidget.face(started, now: ten), .none)
    }

    // MARK: - Words

    func testCountdownWords() {
        XCTAssertEqual(TripsWidget.countdown(0), "Today")
        XCTAssertEqual(TripsWidget.countdown(1), "Tomorrow")
        XCTAssertEqual(TripsWidget.countdown(12), "In 12 days")
    }

    func testLeaveWordsAreOnTheTripsClock() throws {
        let stop = try XCTUnwrap(day.stops.first)
        XCTAssertEqual(TripsWidget.leave(stop, now: ten, zone: rome), "Leave by 10:18")
        XCTAssertEqual(TripsWidget.leave(stop, now: at(19), zone: rome), "Leave now")
        XCTAssertEqual(TripsWidget.leave(stop, now: at(25), zone: rome), "Due 10:30")
        var first = stop
        first.leaveAt = nil
        XCTAssertEqual(TripsWidget.leave(first, now: ten, zone: rome), "Arrive 10:30")
        XCTAssertEqual(TripsWidget.leave(stop, now: ten, zone: "Europe/London"), "Leave by 09:18")
    }

    func testLegWords() throws {
        XCTAssertEqual(TripsWidget.leg(try XCTUnwrap(day.stops.first)), "12 min walk")
        XCTAssertEqual(TripsWidget.leg(try XCTUnwrap(day.stops.last)), "15 min by transit")
        XCTAssertNil(TripsWidget.leg(TripsWidgetStop(title: "Hotel", leaveAt: nil, arriveAt: ten, legMode: nil, legMinutes: nil, number: 1)))
        XCTAssertEqual(TripsWidget.symbol("transit"), "tram.fill")
        XCTAssertEqual(TripsWidget.symbol("boat"), "mappin.and.ellipse")
    }

    func testDayLineAndRange() {
        XCTAssertEqual(TripsWidget.dayLine(day), "Day 3 of 7")
        XCTAssertNil(TripsWidget.dayLine(upcoming))
        XCTAssertEqual(TripsWidget.range("2026-11-09", "2026-11-14"), "9–14 Nov")
        XCTAssertEqual(TripsWidget.range("2026-10-28", "2026-11-02"), "28 Oct – 2 Nov")
        XCTAssertEqual(TripsWidget.range("2026-11-09", "2026-11-09"), "9 Nov")
    }

    // MARK: - Timeline and link

    func testTheTimelineChangesAtEachDepartureArrivalAndMidnight() {
        let dates = TripsWidget.timeline(day, now: ten)
        XCTAssertEqual(dates.first, ten)
        XCTAssertTrue(dates.contains(at(18)))
        XCTAssertTrue(dates.contains(at(30)))
        XCTAssertTrue(dates.contains(at(240)))
        // Midnight in Rome: 23:00 UTC on the 28th.
        XCTAssertTrue(dates.contains(Date(timeIntervalSince1970: 1_793_228_400)))
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertTrue(dates.allSatisfy { $0 >= ten })
    }

    func testATimelineAlwaysReachesAnHourAhead() {
        let dates = TripsWidget.timeline(nil, now: ten)
        XCTAssertGreaterThanOrEqual(dates.last ?? ten, ten.addingTimeInterval(3600))
    }

    func testTheLinkIsTheDayTheTripOrTheList() {
        XCTAssertEqual(TripsWidget.url(day).absoluteString, "sr://trips/t%2F1/2026-10-28")
        XCTAssertEqual(TripsWidget.url(upcoming).absoluteString, "sr://trips/t2")
        XCTAssertEqual(TripsWidget.url(nil).absoluteString, "sr://trips")
    }

    func testSameContentIgnoresWhenItWasSaved() {
        var later = day
        later.savedAt = at(5)
        XCTAssertTrue(later.sameContent(as: day))
        later.stops.removeFirst()
        XCTAssertFalse(later.sameContent(as: day))
    }
}
