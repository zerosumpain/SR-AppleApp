import XCTest
@testable import SRAppleApp

/// The owner's location hold: when a stretch ends, and what the phone keeps.
final class LocationHoldTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "LocationHoldTests")
        defaults.removePersistentDomain(forName: "LocationHoldTests")
    }

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    func testAHoldIsKeptUntilItEndsAndNotAMomentAfter() throws {
        let now = Date()
        let hold = LocationHold(lat: 40.78, lon: -73.97, label: "Home", since: iso(now), until: iso(now.addingTimeInterval(3600)))
        defaults.set(try JSONEncoder().encode(hold), forKey: LocationHold.key)
        XCTAssertEqual(LocationHold.current(now: now, defaults: defaults), hold)
        XCTAssertNil(LocationHold.current(now: now.addingTimeInterval(3601), defaults: defaults))
    }

    func testNothingStoredIsNoHold() {
        XCTAssertNil(LocationHold.current(defaults: defaults))
    }

    func testUntil8amIsTodaysBeforeEightAndTomorrowsAfter() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let early = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 6, minute: 30))!
        let late = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 21))!
        let eightToday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 8))!
        let eightTomorrow = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 8))!
        XCTAssertEqual(LocationHoldLength.tomorrowMorning.end(from: early, calendar: calendar), eightToday)
        XCTAssertEqual(LocationHoldLength.tomorrowMorning.end(from: late, calendar: calendar), eightTomorrow)
        XCTAssertEqual(LocationHoldLength.hour.end(from: early), early.addingTimeInterval(3600))
    }

    func testTheLineSaysWhereAndUntilWhen() {
        let now = Date()
        let hold = LocationHold(lat: 0, lon: 0, label: "Home", since: iso(now), until: iso(now.addingTimeInterval(600)))
        XCTAssertTrue(hold.line(now: now).hasPrefix("Held at Home until "))
    }
}
