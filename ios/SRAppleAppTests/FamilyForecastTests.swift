import XCTest
@testable import SRAppleApp

/// The travel desk forecast: the wire contract (the JSON SR-Main's
/// `/api/native/family/forecast` sends, extra fields and all) and the words
/// the Family tab builds from it. Synthetic — the repository is public.
final class FamilyForecastTests: XCTestCase {

    private let json = #"""
    { "generatedAt": "2026-09-28T06:45:00.000Z", "days": 28,
      "routines": [
        { "id": "sam:home:school:vehicle:weekday", "routeId": "sam:home:school:vehicle", "subject": "sam", "person": "Sam",
          "fromId": "home", "toId": "school", "from": "Home", "to": "School", "mode": "vehicle", "dayType": "weekday",
          "departure": "08:24", "departureMin": 504, "window": [497, 512], "days": 11, "of": 18,
          "minutes": { "median": 16.4, "low": 13.2, "high": 17.9, "p80": 17.4 }, "dates": ["2026-09-21"] } ],
      "next": [
        { "subject": "sam", "kind": "routine", "routineId": "sam:home:school:vehicle:weekday", "from": "Home", "to": "School",
          "leaveAt": "2026-09-28T07:24:00.000Z", "arriveFrom": "2026-09-28T07:37:00.000Z", "arriveTo": "2026-09-28T07:42:00.000Z",
          "days": 11, "of": 18, "dayType": "weekday", "confidence": "established" },
        { "subject": "alex", "kind": "arriving", "routineId": null, "from": "Home", "to": "Office",
          "leaveAt": "2026-09-28T06:40:00.000Z", "arriveFrom": "2026-09-28T07:02:00.000Z", "arriveTo": "2026-09-28T07:08:00.000Z",
          "days": 3, "of": 3, "dayType": null, "confidence": "emerging" } ],
      "watch": [
        { "key": "quiet:kit:2026-09-28T02:00:00.000Z", "kind": "quiet", "subject": "kit", "severity": "watch",
          "title": "No location from Kit for 4 h 45 m", "detail": "Last seen 03:00. A flat battery or no signal reads the same.",
          "at": "2026-09-28T06:45:00.000Z" } ],
      "arrivals": [], "departures": [[0,0,0]],
      "people": [ { "subject": "sam", "name": "Sam", "coverage": 0.94 }, { "subject": "alex", "name": "Alex", "coverage": 0.9 } ] }
    """#

    private func forecast() throws -> FamilyForecast {
        try JSONDecoder().decode(FamilyForecast.self, from: Data(json.utf8))
    }

    func testDecodesTheSiteContract() throws {
        let f = try forecast()
        XCTAssertEqual(f.days, 28)
        XCTAssertEqual(f.routines(for: "sam").first?.departure, "08:24")
        XCTAssertEqual(f.next(for: "alex")?.kind, "arriving")
        XCTAssertEqual(f.watch(for: "kit").count, 1)
        XCTAssertEqual(f.coverage(for: "sam"), 0.94)
        XCTAssertNil(f.next(for: "pat"))
    }

    func testRoutineWords() throws {
        let r = try XCTUnwrap(try forecast().routines.first)
        XCTAssertEqual(ForecastWords.routineWhen(r), "Weekdays · leaves 08:17–08:32, usually 08:24")
        XCTAssertEqual(ForecastWords.routineTime(r).headline, "16 min")
        XCTAssertEqual(ForecastWords.routineTime(r).detail, "13–18 min · 11 of 18 weekdays")
        XCTAssertEqual(ForecastWords.leaveAhead(r), "Leave 18 min ahead to be on time four trips in five.")
    }

    func testNextLineBeforeAndAfterTheUsualTime() throws {
        let f = try forecast()
        let move = try XCTUnwrap(f.next(for: "sam"))
        let before = try XCTUnwrap(parseTimestamp("2026-09-28T07:00:00Z"))
        let after = try XCTUnwrap(parseTimestamp("2026-09-28T07:30:00Z"))
        XCTAssertTrue(ForecastWords.nextLine(move, now: before).hasPrefix("Leaves "))
        XCTAssertTrue(ForecastWords.nextLine(move, now: before).contains("for School · there"))
        XCTAssertTrue(ForecastWords.nextLine(move, now: after).hasPrefix("Due to leave for School"))
        let arriving = try XCTUnwrap(f.next(for: "alex"))
        XCTAssertTrue(ForecastWords.nextLine(arriving, now: before).hasPrefix("Arriving Office "))
    }

    func testClockWordsWrapTheDay() {
        XCTAssertEqual(ForecastWords.hhmm(504), "08:24")
        XCTAssertEqual(ForecastWords.hhmm(-10), "23:50")
        XCTAssertEqual(ForecastWords.ofDays(3, 5, "weekend"), "3 of 5 weekend days")
        XCTAssertEqual(ForecastWords.ofDays(4, 4, nil), "4 similar trips")
    }

    // MARK: - Demo

    #if DEBUG
    func testTheDemoForecastDecodes() throws {
        let url = URL(string: "https://strangeramblings.com/api/native/family/forecast")!
        let f = try JSONDecoder().decode(FamilyForecast.self, from: SRDemoFixtures.reply(method: "GET", url: url, body: nil).body)
        XCTAssertEqual(f.next(for: "alex")?.kind, "arriving")
        XCTAssertEqual(f.routines(for: "sam").count, 2)
        XCTAssertEqual(f.watch.first?.subject, "kit")
    }
    #endif
}
