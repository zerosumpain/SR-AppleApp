import XCTest
@testable import SRAppleApp

/// "Health today": the snapshot as it stands through the day and past
/// midnight, when it is worth a reload, and its words.
///
/// Foundation only: `scripts/home-check.sh` runs this file on Linux too.
final class HealthWidgetTests: XCTestCase {

    private let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    /// Tuesday 27 October 2026, 10:00 in London (GMT).
    private let ten = Date(timeIntervalSince1970: 1_793_095_200)

    private func ring(_ key: String, _ value: Double, _ goal: Double, _ unit: String = "kcal") -> HealthWidgetRing {
        HealthWidgetRing(key: key, label: key.capitalized, value: value, goal: goal, unit: unit)
    }

    private var day: HealthWidgetSnapshot {
        HealthWidgetSnapshot(
            day: "2026-10-27",
            rings: [ring("move", 412, 600), ring("exercise", 22, 30, "min"), ring("stand", 9, 12, "h")],
            steps: 9_120, readiness: 72, readinessLabel: "Primed", savedAt: ten
        )
    }

    // MARK: - The day

    func testTodaysSnapshotIsShownAsItIs() {
        XCTAssertEqual(HealthWidget.today(day, now: ten, calendar: london), day)
        XCTAssertFalse(HealthWidget.isCarriedOver(day, now: ten, calendar: london))
        XCTAssertNil(HealthWidget.today(nil, now: ten, calendar: london))
    }

    func testPastMidnightYesterdaysRingsAreNotPassedOffAsTodays() throws {
        let tomorrow = ten.addingTimeInterval(15 * 3600)
        let shown = try XCTUnwrap(HealthWidget.today(day, now: tomorrow, calendar: london))
        XCTAssertEqual(shown.day, "2026-10-28")
        XCTAssertEqual(shown.rings.map(\.value), [0, 0, 0])
        XCTAssertEqual(shown.rings.map(\.goal), [600, 30, 12], "the goals stand")
        XCTAssertNil(shown.steps)
        XCTAssertNil(shown.readiness)
        XCTAssertTrue(HealthWidget.isCarriedOver(day, now: tomorrow, calendar: london))
    }

    func testNextMidnightIsOnThePhonesCalendar() {
        XCTAssertEqual(HealthWidget.nextMidnight(after: ten, calendar: london), Date(timeIntervalSince1970: 1_793_145_600))
        XCTAssertEqual(HealthWidget.day(ten, calendar: london), "2026-10-27")
    }

    // MARK: - Worth a reload

    func testTheFirstSnapshotAndANewDayAreWorthAReload() {
        XCTAssertTrue(HealthWidget.worthReload(from: nil, to: day))
        var next = day
        next.day = "2026-10-28"
        XCTAssertTrue(HealthWidget.worthReload(from: day, to: next))
    }

    func testSmallMovesAreNot() {
        var next = day
        next.rings[0].value = 418          // 69.7% → still 70 rounded, 1 point at most
        next.steps = 9_300
        next.savedAt = ten.addingTimeInterval(60)
        XCTAssertFalse(HealthWidget.worthReload(from: day, to: next))
    }

    func testARingMovingTwoPointsOrClosingIs() {
        var moved = day
        moved.rings[1].value = 23          // 73% → 77%
        XCTAssertTrue(HealthWidget.worthReload(from: day, to: moved))
        var closing = day
        closing.rings[2].value = 12        // 75% → closed
        XCTAssertTrue(HealthWidget.worthReload(from: day, to: closing))
    }

    func testStepsMovingAQuarterThousandAreAndReadinessIs() {
        var walked = day
        walked.steps = 9_370
        XCTAssertTrue(HealthWidget.worthReload(from: day, to: walked))
        var lost = day
        lost.steps = nil
        XCTAssertTrue(HealthWidget.worthReload(from: day, to: lost))
        var ready = day
        ready.readiness = 70
        XCTAssertTrue(HealthWidget.worthReload(from: day, to: ready))
    }

    func testRingsAppearingIsWorthAReload() {
        var none = day
        none.rings = []
        XCTAssertTrue(HealthWidget.worthReload(from: none, to: day))
    }

    // MARK: - Words

    func testFigures() throws {
        let move = try XCTUnwrap(day.rings.first)
        XCTAssertEqual(HealthWidget.percent(move), 69)
        XCTAssertEqual(HealthWidget.figure(move), "412/600 kcal")
        XCTAssertEqual(HealthWidget.percent(ring("move", 900, 600)), 150, "past the goal reads past 100")
        XCTAssertEqual(HealthWidget.percent(ring("move", 10, 0)), 0, "no goal, no fraction")
        XCTAssertEqual(HealthWidget.steps(9_120), "9,120")
        XCTAssertEqual(HealthWidget.compact(640), "640")
        XCTAssertEqual(HealthWidget.compact(9_120), "9.1k")
        XCTAssertEqual(HealthWidget.compact(14_800), "14k")
    }

    func testTheCentreIsReadinessThenMoveThenSteps() {
        XCTAssertTrue(HealthWidget.centre(day) == ("72", "Primed"))
        var member = day
        member.readiness = nil
        member.readinessLabel = nil
        XCTAssertTrue(HealthWidget.centre(member) == ("69%", "Move"))
        member.rings = []
        XCTAssertTrue(HealthWidget.centre(member) == ("9.1k", "steps"))
        member.steps = nil
        XCTAssertTrue(HealthWidget.centre(member) == ("—", "Today"))
    }

    func testTheLockScreenLineAndVoiceOver() {
        XCTAssertEqual(HealthWidget.ringsLine(day), "Move 69% · Exercise 73% · Stand 9/12")
        var none = day
        none.rings = []
        XCTAssertNil(HealthWidget.ringsLine(none))
        XCTAssertEqual(HealthWidget.spoken(day),
                       "Readiness 72, Primed. Move 69 percent, 412 of 600 kcal. Exercise 73 percent, 22 of 30 min. Stand 75 percent, 9 of 12 h. 9,120 steps")
        XCTAssertEqual(HealthWidget.spoken(HealthWidgetSnapshot(day: "2026-10-27", rings: [], steps: nil, readiness: nil,
                                                                readinessLabel: nil, savedAt: ten)), "Nothing in yet today")
    }

    func testSameContentIgnoresWhenItWasSaved() throws {
        var later = day
        later.savedAt = ten.addingTimeInterval(600)
        XCTAssertTrue(later.sameContent(as: day))
        let data = try JSONEncoder().encode(day)
        XCTAssertEqual(try JSONDecoder().decode(HealthWidgetSnapshot.self, from: data), day)
    }
}
