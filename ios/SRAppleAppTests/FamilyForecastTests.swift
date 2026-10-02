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
      "upcoming": { "available": true, "items": [
        { "id": "ev1", "title": "Dentist", "start": "2026-09-28T14:30:00.000Z", "end": null, "place": "Clinic", "subjects": ["sam"],
          "leaveBy": "2026-09-28T14:12:00.000Z", "from": "School",
          "travel": { "source": "routed", "median": 14, "p80": 18, "samples": 0, "mode": "vehicle" }, "issue": null },
        { "id": "ev2", "title": "Call", "start": "2026-09-28T16:00:00.000Z", "end": null, "place": "Nowhere placeable", "subjects": ["alex"],
          "leaveBy": null, "from": null, "travel": null,
          "issue": { "kind": "unplaced", "text": "“Nowhere placeable” could not be placed on the map." } } ] },
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
        XCTAssertEqual(f.upcoming?.items.count, 2)
    }
    #endif

    // MARK: - Coming up and leave-by reminders

    func testDecodesComingUp() throws {
        let up = try XCTUnwrap(try forecast().upcoming)
        XCTAssertTrue(up.available)
        XCTAssertEqual(up.items.map(\.id), ["ev1", "ev2"])
        XCTAssertNil(up.items[1].leaveBy)
        XCTAssertEqual(ForecastWords.travelLine(up.items[0], names: ["sam": "Sam"]), "14 min by car · routed, nobody has made this trip yet")
    }

    func testAnOlderSiteWithoutComingUpStillDecodes() throws {
        let older = json.replacingOccurrences(of: #""upcoming""#, with: #""upcomingIgnored""#)
        XCTAssertNil(try JSONDecoder().decode(FamilyForecast.self, from: Data(older.utf8)).upcoming)
    }

    func testRemindersFireTenMinutesBeforeLeaveBy() throws {
        let items = try XCTUnwrap(try forecast().upcoming).items
        let now = try XCTUnwrap(parseTimestamp("2026-09-28T13:00:00Z"))
        let plan = LeaveByReminders.plan(items, names: ["sam": "Sam"], now: now)
        XCTAssertEqual(plan.count, 1, "an item with no leave-by time gets no reminder")
        XCTAssertEqual(plan[0].fireAt, try XCTUnwrap(parseTimestamp("2026-09-28T14:02:00Z")))
        XCTAssertTrue(plan[0].title.hasPrefix("Leave by "))
        XCTAssertTrue(plan[0].title.hasSuffix(" for Dentist"))
        XCTAssertTrue(plan[0].body.hasPrefix("Sam · Clinic at "))
        XCTAssertTrue(plan[0].body.contains("(routed)"))
    }

    func testALateListFiresOnceNowAndNeverAfterTheLeaveBy() throws {
        let items = try XCTUnwrap(try forecast().upcoming).items
        let late = try XCTUnwrap(parseTimestamp("2026-09-28T14:05:00Z"))
        let first = LeaveByReminders.plan(items, names: [:], now: late)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].fireAt, late.addingTimeInterval(5))
        XCTAssertTrue(LeaveByReminders.plan(items, names: [:], now: late, sent: [first[0].id]).isEmpty)
        let gone = try XCTUnwrap(parseTimestamp("2026-09-28T14:13:00Z"))
        XCTAssertTrue(LeaveByReminders.plan(items, names: [:], now: gone).isEmpty)
    }

    func testTodayShowsTheNextLeaveByWithinSixHours() throws {
        let up = try XCTUnwrap(try forecast().upcoming)
        let now = try XCTUnwrap(parseTimestamp("2026-09-28T13:00:00Z"))
        XCTAssertEqual(TodayForecastCard.nextLeave(up, now: now)?.id, "ev1")
        XCTAssertNil(TodayForecastCard.nextLeave(up, now: try XCTUnwrap(parseTimestamp("2026-09-28T06:00:00Z"))))
        XCTAssertNil(TodayForecastCard.nextLeave(.init(available: false, items: up.items), now: now))
    }

    // MARK: - Corrections

    func testADismissedJourneyLeavesTheListAndItsReminder() throws {
        let up = try XCTUnwrap(try forecast().upcoming)
        let fixes = ["ev1": JourneyCorrections.Correction(dismissed: true, destination: nil, at: Date())]
        let applied = try XCTUnwrap(JourneyCorrections.apply(up, corrections: fixes))
        XCTAssertEqual(applied.items.map(\.id), ["ev2"])
        let now = try XCTUnwrap(parseTimestamp("2026-09-28T13:00:00Z"))
        XCTAssertNil(TodayForecastCard.nextLeave(applied, now: now))
        XCTAssertTrue(LeaveByReminders.plan(applied.items, names: [:], now: now).isEmpty)
    }

    func testACorrectedDestinationIsReTimedFromAppleMaps() throws {
        let up = try XCTUnwrap(try forecast().upcoming)
        let to = JourneyCorrections.Destination(name: "Castle Clinic", lat: 54.5, lon: -1.5, minutes: 30, mode: "vehicle")
        let fixes = ["ev1": JourneyCorrections.Correction(dismissed: false, destination: to, at: Date())]
        let item = try XCTUnwrap(JourneyCorrections.apply(up, corrections: fixes)?.items.first)
        XCTAssertEqual(item.place, "Castle Clinic")
        XCTAssertEqual(item.travel?.source, "corrected")
        XCTAssertNil(item.issue)
        // 30 min plus a fifth: leave 36 min before the 14:30 start.
        XCTAssertEqual(item.leaveBy.flatMap(parseTimestamp), parseTimestamp("2026-09-28T13:54:00Z"))
        XCTAssertEqual(ForecastWords.travelLine(item, names: [:]), "30 min by car · your destination, timed by Apple Maps")
        // A short trip gets at least five minutes' allowance.
        let near = JourneyCorrections.corrected(up.items[0], to: .init(name: "Next door", lat: 0, lon: 0, minutes: 4, mode: "active"))
        XCTAssertEqual(near.leaveBy.flatMap(parseTimestamp), parseTimestamp("2026-09-28T14:21:00Z"))
    }

    func testNoCorrectionsLeaveTheListAlone() throws {
        let up = try XCTUnwrap(try forecast().upcoming)
        XCTAssertEqual(JourneyCorrections.apply(up, corrections: [:]), up)
        XCTAssertNil(JourneyCorrections.apply(nil, corrections: [:]))
    }

    func testTheCountdownBeyondADaySaysDays() {
        XCTAssertEqual(LeaveCountdown.days(26 * 3600 + 120), "1d 2h")
        XCTAssertEqual(LeaveCountdown.spoken(42 * 60), "42 minutes")
        XCTAssertEqual(LeaveCountdown.spoken(90 * 60), "1 hour 30 minutes")
    }
}
