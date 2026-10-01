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

    // MARK: - Where today sits

    private func figure(value: Double, series: [Double]?, display: String = "1") throws -> HealthFigure {
        var object: [String: Any] = [
            "key": "k", "label": "K", "value": value, "unit": "ms", "display": display, "caption": "",
        ]
        if let series { object["series"] = series }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(HealthFigure.self, from: data)
    }

    func testTodayIsPlacedInTheWindowAndTheTickIsTheWeek() throws {
        // The demo's HRV: 55…65 over the fortnight, 64 today, the last seven
        // averaging 62.29 — the artboard's dot at 90%, tick at 72.9%.
        let hrv = try figure(value: 64, series: [57, 59, 58, 55, 60, 61, 59, 62, 58, 63, 61, 65, 63, 64])
        let range = try XCTUnwrap(FigureRange.make(hrv))
        XCTAssertEqual(range.position, 0.9, accuracy: 0.001)
        XCTAssertEqual(range.baseline, 0.729, accuracy: 0.001)
    }

    func testTodayAtTheLowEndSitsAtZero() throws {
        let rhr = try figure(value: 52, series: [56, 55, 55, 56, 54, 54, 53, 54, 53, 53, 52, 53, 52, 52])
        let range = try XCTUnwrap(FigureRange.make(rhr))
        XCTAssertEqual(range.position, 0, accuracy: 0.001)
        XCTAssertEqual(range.baseline, 0.179, accuracy: 0.001)
    }

    func testNoBarWithoutAWindowToPlaceItIn() throws {
        XCTAssertNil(FigureRange.make(try figure(value: 5, series: nil)))
        XCTAssertNil(FigureRange.make(try figure(value: 5, series: [5])))
        // A flat series has no range: a bar would put the dot at NaN.
        XCTAssertNil(FigureRange.make(try figure(value: 5, series: [5, 5, 5])))
        // No reading today is not a position.
        XCTAssertNil(FigureRange.make(try figure(value: 0, series: [1, 2, 3], display: "—")))
    }

    func testAValueOutsideTheWindowIsClamped() throws {
        let range = try XCTUnwrap(FigureRange.make(try figure(value: 99, series: [1, 2, 3])))
        XCTAssertEqual(range.position, 1)
    }

    func testRingFractionsAndWords() {
        let move = ActivityRingsStore.demo.move!
        XCTAssertEqual(move.fraction, 412.0 / 600.0, accuracy: 0.0001)
        XCTAssertEqual(move.spoken, "Move 412 of 600 kcal")
        XCTAssertFalse(ActivityRingsStore.demo.isEmpty)
        XCTAssertTrue(ActivityRingsStore.Rings(move: nil, exercise: nil, stand: nil).isEmpty)
    }
}
