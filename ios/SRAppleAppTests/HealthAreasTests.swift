import XCTest
@testable import SRAppleApp

/// The arithmetic under the Activities band and the month headers.
final class HealthAreasTests: XCTestCase {

    private func row(_ id: String, local: String?, iso: String = "2026-09-30T06:00:00Z", distanceM: Double? = 5000) throws -> ActivityRow {
        var object: [String: Any] = ["id": id, "startDate": iso, "durationS": 1800]
        if let local { object["startDateLocal"] = local }
        if let distanceM { object["distanceM"] = distanceM }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(ActivityRow.self, from: data)
    }

    func testTheDayIsTheOneLivedNotTheInstant() throws {
        // 23:30 local on the 29th is already the 30th in UTC: the local day wins.
        let evening = try row("a", local: "2026-09-29T23:30:00", iso: "2026-09-30T06:30:00Z")
        XCTAssertEqual(ActivityDay.key(evening), "2026-09-29")
    }

    func testAMalformedLocalDateFallsBackToTheInstant() throws {
        let odd = try row("b", local: "yesterday-ish")
        XCTAssertNotNil(ActivityDay.key(odd))
    }

    func testMonthLabels() {
        XCTAssertEqual(ActivityDay.month("2026-09"), "September 2026")
        XCTAssertEqual(ActivityDay.month("2026-01-04"), "January 2026")
        XCTAssertEqual(ActivityDay.month("earlier"), "Earlier")
    }

    func testTheLastSevenDaysEndToday() throws {
        let now = Date()
        let calendar = Calendar.current
        let today = ActivityDay.key(now)
        let twoAgo = ActivityDay.key(calendar.date(byAdding: .day, value: -2, to: now)!)
        let tenAgo = ActivityDay.key(calendar.date(byAdding: .day, value: -10, to: now)!)
        let rows = [
            try row("1", local: "\(today)T07:00:00", distanceM: 5000),
            try row("2", local: "\(today)T18:00:00", distanceM: 3000),
            try row("3", local: "\(twoAgo)T07:00:00", distanceM: nil),
            try row("4", local: "\(tenAgo)T07:00:00", distanceM: 42000),
        ]
        let days = ActivityWeekDay.lastSeven(rows, now: now)

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last?.key, today)
        XCTAssertTrue(days.last?.today == true)
        XCTAssertEqual(days.filter(\.today).count, 1)
        XCTAssertEqual(days.last?.count, 2)
        XCTAssertEqual(days.last?.km ?? 0, 8, accuracy: 0.001)
        // An outing with no distance still counts as a day something happened.
        XCTAssertEqual(days[4].key, twoAgo)
        XCTAssertEqual(days[4].count, 1)
        XCTAssertEqual(days[4].km, 0)
        // Ten days ago is not in the week.
        XCTAssertFalse(days.contains { $0.key == tenAgo })
    }
}
