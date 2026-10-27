import XCTest
@testable import SRAppleApp

/// Home's briefing: which three things lead the page, and what each says.
///
/// Foundation only: `scripts/home-check.sh` runs this file on Linux too.
final class HomeBriefingTests: XCTestCase {

    private let london = TimeZone(identifier: "Europe/London")!
    /// Tuesday 27 October 2026, 10:00 in London (GMT).
    private let ten = Date(timeIntervalSince1970: 1_793_095_200)

    private func facts(hour: Int = 10) -> HomeBriefing.Facts {
        HomeBriefing.Facts(now: ten.addingTimeInterval(Double(hour - 10) * 3600), zone: london)
    }

    // MARK: - The ranking

    func testAQuietDaySaysSoRatherThanNothing() {
        let lines = HomeBriefing.rank(facts())
        XCTAssertEqual(lines.map(\.source), [.calm])
        XCTAssertEqual(lines.first?.text, "All quiet")
    }

    func testThreeLinesAtMostAndOnePerSource() {
        var f = facts()
        f.tasks = .init(toDo: 3, overdue: 1, awaiting: 0, parent: true, owedPence: 0, overdueTitle: "Bins", nextTitle: nil, nextDue: nil)
        f.steps = [.init(name: "Sam", steps: 6000, me: false), .init(name: "Alex", steps: 5000, me: true)]
        f.failingFlows = ["Nightly backup"]
        f.newsUnseen = 4
        f.toDecide = 2
        let lines = HomeBriefing.rank(f)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(Set(lines.map(\.source)).count, 3)
        XCTAssertEqual(lines.map(\.source), [.tasks, .flows, .steps], "overdue, failing, then the race")
    }

    func testTimeBoundThingsOutrankHealth() {
        var f = facts()
        f.vitals = [.init(key: "hrv", label: "HRV", value: 80, shown: "80 ms", delta: 20, deltaDisplay: "+20 vs 7d", improving: true)]
        f.moves = [.init(name: "Sam", isSelf: false, to: "School", leaveAt: ten.addingTimeInterval(20 * 60), arriving: false, arriveFrom: nil)]
        XCTAssertEqual(HomeBriefing.rank(f).first?.source, .moves)
    }

    // MARK: - Steps

    func testBehindTheLeaderSaysHowLongAWalkWouldTake() throws {
        var f = facts()
        f.steps = [.init(name: "Sam", steps: 10_360, me: false), .init(name: "Alex", steps: 9_120, me: true), .init(name: "Kit", steps: 4000, me: false)]
        let line = try XCTUnwrap(HomeBriefing.steps(f))
        XCTAssertEqual(line.figure, "1,240")
        XCTAssertEqual(line.text, "steps behind Sam")
        XCTAssertEqual(line.detail, "About 13 min of walking to draw level")
    }

    func testFarBehindGivesThePlaceInstead() throws {
        var f = facts()
        f.steps = [.init(name: "Sam", steps: 20_000, me: false), .init(name: "Alex", steps: 2_000, me: true)]
        let line = try XCTUnwrap(HomeBriefing.steps(f))
        XCTAssertEqual(line.detail, "2nd of 2 · 2,000 so far")
        XCTAssertLessThan(line.weight, 50, "a race that is lost is not news")
    }

    func testLeadingAndLevel() throws {
        var f = facts()
        f.steps = [.init(name: "Sam", steps: 8_000, me: false), .init(name: "Alex", steps: 8_300, me: true)]
        let lead = try XCTUnwrap(HomeBriefing.steps(f))
        XCTAssertEqual(lead.figure, "1st")
        XCTAssertEqual(lead.text, "on steps, 300 ahead of Sam")
        XCTAssertEqual(lead.tone, .good)
        f.steps = [.init(name: "Sam", steps: 8_000, me: false), .init(name: "Alex", steps: 8_000, me: true)]
        XCTAssertEqual(HomeBriefing.steps(f)?.figure, "Level")
    }

    func testAloneOnTheBoardIsJustTheCount() {
        var f = facts()
        f.steps = [.init(name: "Alex", steps: 12_345, me: true)]
        XCTAssertEqual(HomeBriefing.steps(f)?.figure, "12,345")
        f.steps = [.init(name: "Sam", steps: 100, me: false)]
        XCTAssertNil(HomeBriefing.steps(f), "a board you are not on says nothing about you")
    }

    // MARK: - Health

    func testTheFigureThatMovedFurthestIsTheOneNamed() throws {
        var f = facts()
        f.vitals = [
            .init(key: "rhr", label: "Resting HR", value: 52, shown: "52 bpm", delta: -1, deltaDisplay: "−1 vs 7d", improving: true),
            .init(key: "sleep", label: "Sleep", value: 5.5, shown: "5h 30m", delta: -1.5, deltaDisplay: "−1h 30m vs 7d", improving: false),
            .init(key: "hrv", label: "HRV", value: 64, shown: "64 ms", delta: 5, deltaDisplay: "+5 vs 7d", improving: true),
        ]
        let line = try XCTUnwrap(HomeBriefing.vitals(f))
        XCTAssertEqual(line.figureKey, "sleep")
        XCTAssertEqual(line.figure, "5h 30m")
        XCTAssertEqual(line.text, "Sleep, 1h 30m below your week")
        XCTAssertEqual(line.tone, .warn)
    }

    func testASmallWobbleIsNotNews() {
        var f = facts()
        f.vitals = [.init(key: "rhr", label: "Resting HR", value: 52, shown: "52 bpm", delta: -1, deltaDisplay: "−1 vs 7d", improving: true)]
        XCTAssertNil(HomeBriefing.vitals(f))
    }

    func testAMissingFigureIsNeverRead() {
        var f = facts()
        f.vitals = [.init(key: "hrv", label: "HRV", value: 0, shown: "—", delta: -60, deltaDisplay: "—", improving: false)]
        XCTAssertNil(HomeBriefing.vitals(f), "zero is missing in this data, not a collapse")
    }

    func testReadinessSpeaksOnlyAtTheEnds() {
        var f = facts()
        f.readiness = .init(score: 62, label: "Steady", recommendation: "Keep it easy.")
        XCTAssertNil(HomeBriefing.readiness(f))
        f.readiness = .init(score: 31, label: "Depleted", recommendation: "Rest today. Sleep early.")
        let low = HomeBriefing.readiness(f)
        XCTAssertEqual(low?.tone, .bad)
        XCTAssertEqual(low?.detail, "Rest today.")
        f.readiness = .init(score: 84, label: "Primed", recommendation: "")
        XCTAssertEqual(HomeBriefing.readiness(f)?.tone, .good)
        XCTAssertNil(HomeBriefing.readiness(f)?.detail)
    }

    // MARK: - Rings

    func testTheMoveRingIsPressedLateInTheDayWhenItIsWithinReach() throws {
        var f = facts(hour: 17)
        f.rings = [.init(key: "move", label: "Move", value: 412, goal: 600, unit: "kcal"),
                   .init(key: "exercise", label: "Exercise", value: 18, goal: 30, unit: "min")]
        let line = try XCTUnwrap(HomeBriefing.rings(f))
        XCTAssertEqual(line.figure, "188 kcal")
        XCTAssertEqual(line.text, "to close your Move ring")
        XCTAssertEqual(line.detail, "69% there · Exercise 18/30 min")
        XCTAssertEqual(line.weight, 72)
        XCTAssertEqual(HomeBriefing.rings(facts(hour: 9).with { $0.rings = f.rings })?.weight, 36, "mornings are not a nag")
    }

    func testClosedRings() {
        var f = facts()
        f.rings = [.init(key: "move", label: "Move", value: 700, goal: 600, unit: "kcal"),
                   .init(key: "exercise", label: "Exercise", value: 40, goal: 30, unit: "min"),
                   .init(key: "stand", label: "Stand", value: 12, goal: 12, unit: "h")]
        XCTAssertEqual(HomeBriefing.rings(f)?.text, "rings closed today")
        XCTAssertEqual(HomeBriefing.rings(f)?.figure, "3")
        f.rings[2] = .init(key: "stand", label: "Stand", value: 9, goal: 12, unit: "h")
        XCTAssertEqual(HomeBriefing.rings(f)?.text, "Move ring closed")
        XCTAssertEqual(HomeBriefing.rings(f)?.detail, "Stand 3 h to go")
    }

    // MARK: - The family and the diary

    func testTheSoonestMoveAndItsClock() throws {
        var f = facts()
        f.moves = [
            .init(name: "Kit", isSelf: false, to: "Gym", leaveAt: ten.addingTimeInterval(3 * 3600), arriving: false, arriveFrom: nil),
            .init(name: "Sam", isSelf: false, to: "School", leaveAt: ten.addingTimeInterval(25 * 60), arriving: false, arriveFrom: nil),
        ]
        let line = try XCTUnwrap(HomeBriefing.moves(f))
        XCTAssertEqual(line.figure, "10:25")
        XCTAssertEqual(line.text, "Sam leaves for School")
        XCTAssertEqual(line.detail, "In 25 min")
    }

    func testYourOwnMoveIsInTheSecondPerson() {
        var f = facts()
        f.moves = [.init(name: "Alex", isSelf: true, to: "Work", leaveAt: ten.addingTimeInterval(70 * 60), arriving: false, arriveFrom: nil)]
        XCTAssertEqual(HomeBriefing.moves(f)?.text, "You leave for Work")
        XCTAssertEqual(HomeBriefing.moves(f)?.detail, "In 1 h 10 min")
    }

    func testAMoveTooFarOffIsLeftToTheTile() {
        var f = facts()
        f.moves = [.init(name: "Sam", isSelf: false, to: "School", leaveAt: ten.addingTimeInterval(6 * 3600), arriving: false, arriveFrom: nil)]
        XCTAssertNil(HomeBriefing.moves(f))
    }

    func testAnAlertOutranksEverything() {
        var f = facts()
        f.watch = [.init(title: "Sam is quiet", detail: "", alert: false), .init(title: "Sam is overdue at home", detail: "Usually back by 09:40", alert: true)]
        f.tasks = .init(toDo: 1, overdue: 1, awaiting: 0, parent: true, owedPence: 0, overdueTitle: nil, nextTitle: nil, nextDue: nil)
        let first = HomeBriefing.rank(f).first
        XCTAssertEqual(first?.source, .watch)
        XCTAssertEqual(first?.text, "Sam is overdue at home")
        XCTAssertEqual(first?.tone, .bad)
    }

    func testTheDiarySaysWhenToLeave() throws {
        var f = facts()
        f.diary = [.init(title: "Dentist", start: ten.addingTimeInterval(4 * 3600), leaveBy: ten.addingTimeInterval(3.5 * 3600), place: "Elvet"),
                   .init(title: "Call", start: ten.addingTimeInterval(45 * 60), leaveBy: nil, place: nil)]
        let call = try XCTUnwrap(HomeBriefing.diary(f))
        XCTAssertEqual(call.figure, "10:45", "an hour or so out, with nowhere to go: the start")
        f.diary = [.init(title: "Dentist", start: ten.addingTimeInterval(40 * 60), leaveBy: ten.addingTimeInterval(12 * 60), place: "Elvet")]
        let soon = try XCTUnwrap(HomeBriefing.diary(f))
        XCTAssertEqual(soon.figure, "10:12")
        XCTAssertEqual(soon.text, "leave for Dentist")
        XCTAssertEqual(soon.detail, "In 12 min · starts 10:40 · Elvet")
        XCTAssertEqual(soon.tone, .warn)
        f.now = ten.addingTimeInterval(15 * 60)
        XCTAssertEqual(HomeBriefing.diary(f)?.figure, "Now")
    }

    // MARK: - Trips

    func testTheNextTripCountsDownAndAsks() throws {
        var f = facts()
        f.trip = .init(place: "Rome", days: 5, questions: 2, nextStop: nil, leaveInMinutes: nil)
        let line = try XCTUnwrap(HomeBriefing.trip(f))
        XCTAssertEqual(line.figure, "5 days")
        XCTAssertEqual(line.text, "until Rome")
        XCTAssertEqual(line.detail, "2 quick questions to answer")
        f.trip = .init(place: "Rome", days: 60, questions: 0, nextStop: nil, leaveInMinutes: nil)
        XCTAssertNil(HomeBriefing.trip(f), "two months out is not this morning's news")
    }

    func testARunningTripSaysWhenToLeave() {
        var f = facts()
        f.trip = .init(place: "Rome", days: nil, questions: 0, nextStop: "Pantheon", leaveInMinutes: 8)
        XCTAssertEqual(HomeBriefing.trip(f)?.figure, "8 min")
        XCTAssertEqual(HomeBriefing.trip(f)?.text, "until you leave for Pantheon")
    }

    // MARK: - Tasks

    func testTasksInOrderOfWhatIsOwed() {
        var f = facts()
        f.tasks = .init(toDo: 2, overdue: 0, awaiting: 1, parent: true, owedPence: 250, overdueTitle: nil, nextTitle: "Bins", nextDue: "today 18:00")
        XCTAssertEqual(HomeBriefing.tasks(f)?.text, "done, waiting for you to confirm")
        f.tasks?.parent = false
        let todo = HomeBriefing.tasks(f)
        XCTAssertEqual(todo?.text, "tasks to do")
        XCTAssertEqual(todo?.detail, "Next: Bins · today 18:00")
        XCTAssertEqual(todo?.weight, 56, "due today is pressed harder")
        f.tasks = .init(toDo: 0, overdue: 0, awaiting: 0, parent: true, owedPence: 250, overdueTitle: nil, nextTitle: nil, nextDue: nil)
        XCTAssertEqual(HomeBriefing.tasks(f)?.figure, "£2.50")
    }

    // MARK: - Messages

    func testOnlySomebodyElsesRecentMessage() {
        var f = facts()
        f.message = .init(line: "Sam: Back at six", at: ten.addingTimeInterval(-12 * 60), mine: false)
        XCTAssertEqual(HomeBriefing.messages(f)?.detail, "12 min ago")
        f.message = .init(line: "You: On my way", at: ten.addingTimeInterval(-60), mine: true)
        XCTAssertNil(HomeBriefing.messages(f))
        f.message = .init(line: "Sam: Morning", at: ten.addingTimeInterval(-5 * 3600), mine: false)
        XCTAssertNil(HomeBriefing.messages(f))
    }

    // MARK: - Words

    func testWords() {
        XCTAssertEqual(HomeBriefing.grouped(1_234_567), "1,234,567")
        XCTAssertEqual(HomeBriefing.grouped(999), "999")
        XCTAssertEqual(HomeBriefing.duration(59), "59 min")
        XCTAssertEqual(HomeBriefing.duration(120), "2 h")
        XCTAssertEqual(HomeBriefing.magnitude("+18m vs 7d"), "18m")
        XCTAssertEqual(HomeBriefing.magnitude("−2 vs 7d"), "2")
        XCTAssertNil(HomeBriefing.magnitude("—"))
        XCTAssertEqual(HomeBriefing.ordinal(12), "12th")
        XCTAssertEqual(HomeBriefing.ordinal(22), "22nd")
    }

    func testSpokenReadsTheWholeLine() {
        let line = HomeInsight(source: .steps, figure: "1,240", text: "steps behind Sam", detail: "About 13 min of walking", tone: .plain, weight: 1)
        XCTAssertEqual(line.spoken, "1,240 steps behind Sam. About 13 min of walking")
    }
}

private extension HomeBriefing.Facts {
    func with(_ change: (inout Self) -> Void) -> Self {
        var copy = self
        change(&copy)
        return copy
    }
}
