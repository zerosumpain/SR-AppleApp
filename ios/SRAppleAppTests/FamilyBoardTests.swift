import XCTest
@testable import SRAppleApp

/// The family step board and task list: the wire contract (the spec's own
/// JSON, decoded as the site will send it), and every rule the pages apply.
final class FamilyBoardTests: XCTestCase {

    // MARK: - The wire

    private let stepsJSON = #"""
    { "day": "2026-09-28", "updatedAt": "2026-09-28T14:05:00.000Z", "people": [
      { "id": "f_ab12", "name": "Katie", "steps": 8412, "rank": 1, "me": false, "updatedAt": "2026-09-28T14:05:00.000Z" },
      { "id": "f_cd34", "name": "John", "steps": 7000, "rank": 2, "me": true, "updatedAt": "2026-09-28T14:05:00.000Z" },
      { "id": "f_ef56", "name": "Rory", "steps": 0, "rank": 3, "me": false, "updatedAt": null } ],
      "yesterday": { "leaderName": "Rory", "steps": 14210 } }
    """#

    private let tasksJSON = #"""
    { "me": { "id": "f_me", "parent": true },
      "people": [ { "id": "f_me", "name": "John" }, { "id": "f_r", "name": "Rory" }, { "id": "f_k", "name": "Kit" } ],
      "open": [
        { "id": "t1", "title": "Bins", "notes": null, "deadline": "2026-09-29", "assignee": null, "createdBy": "f_me",
          "status": "open", "doneBy": null, "doneAt": null, "sentBackNote": null, "confirmedBy": null, "confirmedAt": null,
          "reward": { "kind": "cash", "pence": 200, "note": null, "paidAt": null }, "createdAt": "2026-09-28T08:00:00Z" },
        { "id": "t2", "title": "Lawn", "notes": "Front and back", "deadline": null, "assignee": "f_r", "createdBy": "f_me",
          "status": "done", "doneBy": "f_r", "doneAt": "2026-09-28T09:00:00Z", "sentBackNote": null, "confirmedBy": null,
          "confirmedAt": null, "reward": null, "createdAt": "2026-09-27T08:00:00Z" } ],
      "completed": [
        { "id": "t3", "title": "Car", "notes": null, "deadline": null, "assignee": "f_k", "createdBy": "f_me",
          "status": "confirmed", "doneBy": "f_k", "doneAt": "2026-09-27T09:00:00Z", "sentBackNote": null,
          "confirmedBy": "f_me", "confirmedAt": "2026-09-27T10:00:00Z",
          "reward": { "kind": "cash", "pence": 1500, "note": null, "paidAt": null }, "createdAt": "2026-09-26T08:00:00Z" },
        { "id": "t4", "title": "Shop", "notes": null, "deadline": null, "assignee": null, "createdBy": "f_me",
          "status": "confirmed", "doneBy": "f_r", "doneAt": "2026-09-27T09:00:00Z", "sentBackNote": null,
          "confirmedBy": "f_me", "confirmedAt": "2026-09-27T10:00:00Z",
          "reward": { "kind": "day_out", "pence": null, "note": "The zoo", "paidAt": null }, "createdAt": "2026-09-26T08:00:00Z" } ],
      "owed": { "totalPence": 1500, "items": [] } }
    """#

    private func board() throws -> FamilyTasksBoard {
        var decoded = try JSONDecoder().decode(FamilyTasksBoard.self, from: Data(tasksJSON.utf8))
        decoded.owed.items = decoded.completed
        return decoded
    }

    func testTheStepBoardDecodesAsTheSpecSendsIt() throws {
        let board = try JSONDecoder().decode(FamilyStepsBoard.self, from: Data(stepsJSON.utf8))
        XCTAssertEqual(board.day, "2026-09-28")
        XCTAssertEqual(board.people.count, 3)
        XCTAssertEqual(board.mine?.name, "John")
        XCTAssertNil(board.people[2].updatedAt)
        XCTAssertEqual(board.yesterday?.leaderName, "Rory")
    }

    func testAStepBoardWithMissingFieldsStillDecodes() throws {
        // No yesterday, no updatedAt, a person with no `me`: nothing thrown.
        let json = #"{ "day": "2026-09-28", "people": [ { "id": "f_1", "name": "Sam", "steps": 10, "rank": 1 } ] }"#
        let board = try JSONDecoder().decode(FamilyStepsBoard.self, from: Data(json.utf8))
        XCTAssertNil(board.yesterday)
        XCTAssertNil(board.updatedAt)
        XCTAssertFalse(board.people[0].me)
        XCTAssertNil(board.mine)
    }

    func testTheTaskListDecodesAsTheSpecSendsIt() throws {
        let decoded = try JSONDecoder().decode(FamilyTasksBoard.self, from: Data(tasksJSON.utf8))
        XCTAssertTrue(decoded.me.parent)
        XCTAssertEqual(decoded.open.map(\.id), ["t1", "t2"])
        XCTAssertEqual(decoded.open[0].reward?.kindValue, .cash)
        XCTAssertEqual(decoded.open[0].reward?.pence, 200)
        XCTAssertNil(decoded.open[1].reward)
        XCTAssertEqual(decoded.completed[1].reward?.kindValue, .dayOut)
        XCTAssertEqual(decoded.owed.totalPence, 1500)
    }

    func testATaskWithMissingOptionalFieldsStillDecodes() throws {
        let json = #"{ "id": "t9", "title": "Minimal", "createdBy": "f_me", "status": "open", "createdAt": "x" }"#
        let task = try JSONDecoder().decode(FamilyTask.self, from: Data(json.utf8))
        XCTAssertNil(task.deadline)
        XCTAssertNil(task.reward)
        XCTAssertTrue(task.isOpen)
    }

    func testTheCreateBodyLeavesOutWhatWasNotGiven() throws {
        let body = FamilyTaskCreateBody(title: "Bins")
        let json = String(data: try JSONEncoder().encode(body), encoding: .utf8)
        XCTAssertEqual(json, #"{"title":"Bins"}"#)
    }

    // MARK: - Steps

    func testRanksAreCompetitionRanksAndTiesKeepTheirOrder() {
        let people = [
            FamilyStepsPerson(id: "a", name: "A", steps: 500, rank: 0),
            FamilyStepsPerson(id: "b", name: "B", steps: 900, rank: 0),
            FamilyStepsPerson(id: "c", name: "C", steps: 500, rank: 0),
            FamilyStepsPerson(id: "d", name: "D", steps: 100, rank: 0),
        ]
        let ranked = FamilySteps.ranked(people)
        XCTAssertEqual(ranked.map(\.id), ["b", "a", "c", "d"])
        XCTAssertEqual(ranked.map(\.rank), [1, 2, 2, 4])
    }

    func testTheLiveCountLiftsMyRowOnlyWhenItIsHigher() throws {
        let board = try JSONDecoder().decode(FamilyStepsBoard.self, from: Data(stepsJSON.utf8))
        let lower = FamilySteps.withLive(board, liveSteps: 6000)
        XCTAssertEqual(lower, board, "a lower phone count changes nothing")

        let higher = FamilySteps.withLive(board, liveSteps: 9000)
        XCTAssertEqual(higher.mine?.steps, 9000)
        XCTAssertEqual(higher.mine?.rank, 1)
        XCTAssertTrue(higher.mine?.live ?? false)
        XCTAssertEqual(higher.people.first?.name, "John")
        XCTAssertEqual(higher.people.first { $0.name == "Katie" }?.rank, 2)
    }

    func testOrdinals() {
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111].map(FamilySteps.ordinal),
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd", "101st", "111th"])
    }

    func testPlaceAndGapFromTheCallersSeat() throws {
        let board = try JSONDecoder().decode(FamilyStepsBoard.self, from: Data(stepsJSON.utf8))
        XCTAssertEqual(FamilySteps.place(board), "2nd of 3")
        XCTAssertEqual(FamilySteps.gap(board), "1,412 behind Katie")

        let leading = FamilySteps.withLive(board, liveSteps: 10_000)
        XCTAssertEqual(FamilySteps.gap(leading), "1,588 ahead of Katie")

        let level = FamilySteps.withLive(board, liveSteps: 8412)
        XCTAssertEqual(FamilySteps.place(level), "Joint 1st of 3")
        XCTAssertEqual(FamilySteps.gap(level), "Level with Katie")
    }

    func testFiguresAreGroupedTheBritishWay() {
        XCTAssertEqual(FamilySteps.figure(12300), "12,300")
        XCTAssertEqual(FamilySteps.figure(0), "0")
    }

    func testTheBoardIsTodaysOnTheLondonDay() {
        // 23:30 UTC on 28 September is 00:30 on the 29th in London (BST).
        let lateUTC = ISO8601DateFormatter().date(from: "2026-09-28T23:30:00Z")!
        XCTAssertEqual(FamilySteps.ymd(lateUTC), "2026-09-29")
        XCTAssertFalse(FamilySteps.isToday(FamilyStepsBoard(day: "2026-09-28", people: []), now: lateUTC))
    }

    func testYesterdaysLine() throws {
        let board = try JSONDecoder().decode(FamilyStepsBoard.self, from: Data(stepsJSON.utf8))
        XCTAssertEqual(FamilySteps.yesterdayLine(board), "Yesterday Rory won with 14,210 steps.")
    }

    // MARK: - Tasks: who may do what

    func testWhatEachPersonMayDoToATask() throws {
        let tasks = try board()
        let parent = FamilyTaskMe(id: "f_me", parent: true)
        let doer = FamilyTaskMe(id: "f_r", parent: false)
        let other = FamilyTaskMe(id: "f_k", parent: false)
        let open = tasks.open[0], done = tasks.open[1], owed = tasks.completed[0]

        XCTAssertEqual(FamilyTaskRules.actions(for: open, me: parent), [.done, .delete])
        XCTAssertEqual(FamilyTaskRules.actions(for: open, me: other), [.done], "not the creator: no delete")

        XCTAssertEqual(FamilyTaskRules.actions(for: done, me: parent), [.confirm, .sendBack, .undo, .delete])
        XCTAssertEqual(FamilyTaskRules.actions(for: done, me: doer), [.undo], "the doer may take it back, not confirm it")
        XCTAssertEqual(FamilyTaskRules.actions(for: done, me: other), [])

        XCTAssertEqual(FamilyTaskRules.actions(for: owed, me: parent), [.paid])
        XCTAssertEqual(FamilyTaskRules.actions(for: owed, me: other), [], "only a parent marks paid")

        var paid = owed
        paid.reward?.paidAt = "2026-09-28T10:00:00Z"
        XCTAssertEqual(FamilyTaskRules.actions(for: paid, me: parent), [])
    }

    func testNamesResolveFromThePeopleList() throws {
        let tasks = try board()
        XCTAssertEqual(FamilyTaskRules.name("f_me", in: tasks), "You")
        XCTAssertEqual(FamilyTaskRules.name("f_r", in: tasks), "Rory")
        XCTAssertEqual(FamilyTaskRules.name("f_gone", in: tasks), "Someone")
        XCTAssertNil(FamilyTaskRules.name(nil, in: tasks))
    }

    func testOwedGroupsPerPersonMostOwedFirst() throws {
        let groups = FamilyTaskRules.owedGroups(try board())
        XCTAssertEqual(groups.map(\.name), ["Kit", "Rory"])
        XCTAssertEqual(groups.map(\.pence), [1500, 0])
        XCTAssertEqual(FamilyTaskRules.owedOther(try board()).map(\.id), ["t4"])
    }

    // MARK: - Tasks: money and rewards

    func testMoney() {
        XCTAssertEqual(FamilyTaskRules.money(500), "£5")
        XCTAssertEqual(FamilyTaskRules.money(550), "£5.50")
        XCTAssertEqual(FamilyTaskRules.money(5), "£0.05")
        XCTAssertEqual(FamilyTaskRules.money(100_000), "£1,000")
    }

    func testPoundsTypedIntoPence() {
        XCTAssertEqual(FamilyTaskRules.pence(from: "5"), 500)
        XCTAssertEqual(FamilyTaskRules.pence(from: "5.5"), 550)
        XCTAssertEqual(FamilyTaskRules.pence(from: "£5.50"), 550)
        XCTAssertEqual(FamilyTaskRules.pence(from: "5,50"), 550)
        XCTAssertEqual(FamilyTaskRules.pence(from: ".75"), 75)
        XCTAssertNil(FamilyTaskRules.pence(from: ""))
        XCTAssertNil(FamilyTaskRules.pence(from: "five"))
        XCTAssertNil(FamilyTaskRules.pence(from: "5.555"))
        XCTAssertNil(FamilyTaskRules.pence(from: "-5"))
    }

    func testRewardLabels() {
        XCTAssertEqual(FamilyReward(kind: "cash", pence: 500).label, "£5")
        XCTAssertEqual(FamilyReward(kind: "day_out").label, "Day out")
        XCTAssertEqual(FamilyReward(kind: "day_out", pence: 1000, note: "The zoo").label, "Day out · £10 · The zoo")
        XCTAssertEqual(FamilyReward(kind: "something_new").label, "Reward")
    }

    func testTheDraftHoldsTheSitesRules() {
        var draft = FamilyTaskDraft()
        XCTAssertNotNil(draft.problem, "no title")
        draft.title = "  Bins  "
        XCTAssertNil(draft.problem)
        XCTAssertEqual(draft.body()?.title, "Bins")

        draft.hasReward = true
        draft.kind = .cash
        XCTAssertEqual(draft.problem, "A cash reward needs an amount.")
        draft.pounds = "2.50"
        XCTAssertNil(draft.problem)
        XCTAssertEqual(draft.body()?.reward, FamilyTaskRewardBody(kind: "cash", pence: 250, note: nil))

        draft.pounds = "2000"
        XCTAssertEqual(draft.problem, "Rewards stop at £1,000.")

        draft.kind = .gameTime
        draft.pounds = ""
        draft.rewardNote = "An hour"
        XCTAssertNil(draft.problem, "a category takes no amount")
        XCTAssertEqual(draft.body()?.reward, FamilyTaskRewardBody(kind: "game_time", pence: nil, note: "An hour"))

        draft.hasReward = false
        XCTAssertNil(draft.body()?.reward, "no reward, no reward fields")
    }

    func testTheDeadlineGoesAsALocalDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        var draft = FamilyTaskDraft()
        draft.title = "Bins"
        draft.hasDeadline = true
        draft.deadline = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 23, minute: 30))!
        XCTAssertEqual(draft.body(calendar: calendar)?.deadline, "2026-10-03")
    }

    func testDeadlinesAreSaidRelativeToToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12))!
        XCTAssertEqual(FamilyTaskRules.deadline("2026-09-28", now: now, calendar: calendar)?.text, "Due today")
        XCTAssertEqual(FamilyTaskRules.deadline("2026-09-29", now: now, calendar: calendar)?.text, "Due tomorrow")
        XCTAssertEqual(FamilyTaskRules.deadline("2026-10-02", now: now, calendar: calendar)?.text, "Due Fri 2 Oct")
        // October, not September: en_GB abbreviates that one "Sept" on some
        // releases and "Sep" on others.
        let later = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!
        let overdue = FamilyTaskRules.deadline("2026-10-06", now: later, calendar: calendar)
        XCTAssertEqual(overdue?.text, "Overdue · Tue 6 Oct")
        XCTAssertEqual(overdue?.overdue, true)
        XCTAssertNil(FamilyTaskRules.deadline("soon", now: now, calendar: calendar))
    }

    func testTheSummaryACardOrWidgetShows() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12))!
        let summary = FamilyTasksSummary.make(try board(), now: now, calendar: calendar)
        XCTAssertEqual(summary.toDo, 1)
        XCTAssertEqual(summary.awaiting, 1)
        XCTAssertTrue(summary.parent)
        XCTAssertEqual(summary.owedPence, 1500)
        XCTAssertEqual(summary.owedOther, 1)
        XCTAssertEqual(summary.next.map(\.title), ["Bins"])
        XCTAssertEqual(summary.next.first?.due, "Due tomorrow")
        XCTAssertEqual(summary.owedLine, "£15 + 1 treat owed")
    }

    func testTodayShowsTheTaskCardOnlyWhileSomethingIsOutstanding() throws {
        var summary = FamilyTasksSummary.make(try board())
        XCTAssertTrue(summary.outstanding)
        summary.toDo = 0
        XCTAssertTrue(summary.outstanding, "done and waiting for a parent is still outstanding")
        summary.awaiting = 0
        XCTAssertFalse(summary.outstanding, "money owed is a debt, not a task")
    }

    // MARK: - Where a tap goes

    func testFamilyLinks() {
        XCTAssertEqual(FamilyPage.from(url: URL(string: "sr://family/steps")!), .steps)
        XCTAssertEqual(FamilyPage.from(url: URL(string: "sr://family/tasks")!), .tasks)
        XCTAssertEqual(FamilyPage.from(url: URL(string: "SR://Family/Tasks")!), .tasks)
        XCTAssertNil(FamilyPage.from(url: URL(string: "sr://family/other")!))
        XCTAssertNil(FamilyPage.from(url: URL(string: "https://strangeramblings.com/family/steps")!))
        XCTAssertEqual(FamilyPage.steps.url.absoluteString, "sr://family/steps")
    }

    func testANotificationFindsItsPage() {
        XCTAssertEqual(FamilyPage.from(category: "family-steps", userInfo: [:]), .steps)
        XCTAssertEqual(FamilyPage.from(category: "family-tasks", userInfo: [:]), .tasks)
        XCTAssertEqual(FamilyPage.from(category: "anything", userInfo: ["url": "sr://family/tasks"]), .tasks,
                       "the url wins whatever the category")
        XCTAssertEqual(FamilyPage.from(category: "family", userInfo: ["page": "steps"]), .steps)
        XCTAssertNil(FamilyPage.from(category: "game", userInfo: ["roomId": "g_1"]))
        XCTAssertNil(FamilyPage.from(category: "household", userInfo: [:]))
    }

    func testTheNotificationOutcomeOpensTheFamilyCategory() {
        let outcome = AlertActions.outcome(
            action: "com.apple.UNNotificationDefaultActionIdentifier",
            categoryIdentifier: "",
            userInfo: ["category": "family-steps", "url": "sr://family/steps"]
        )
        XCTAssertEqual(outcome, .open(category: "family-steps"))
    }

    // MARK: - Who sees the boards

    func testTheBoardsNeedTheFamilyAndTheSite() {
        XCTAssertTrue(AccessPolicy.familyBoards(.everything, sitePaired: true))
        XCTAssertTrue(AccessPolicy.familyBoards(AppAccess(family: true), sitePaired: true))
        XCTAssertFalse(AccessPolicy.familyBoards(AppAccess(family: true), sitePaired: false), "the boards live on the site")
        XCTAssertFalse(AccessPolicy.familyBoards(AppAccess(chat: true, news: true, games: true), sitePaired: true), "not family")
        XCTAssertTrue(AccessPolicy.familyBoards(AppAccess(owner: true), sitePaired: true))
    }
}
