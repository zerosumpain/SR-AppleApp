import XCTest
@testable import SRAppleApp

/// Trips v8 — propose, research, ask — on the phone.
///
/// The wire shapes decode from the SAME fixture the server's tests read
/// (`Fixtures/TripDecisions/decisions-wire.json`, copied from SR-Main
/// `src/lib/trips/fixtures/decisions-wire.json`), what the phone sends
/// encodes as the contract says, and the pure logic the cards draw from
/// (`TripDecisionLogic.swift`) says what the plan says it should.
///
/// Foundation only, like the code it tests: the same file runs on Linux
/// (`swift test` in a scratch package with the four Foundation sources),
/// so it is checked before the macOS job ever sees it.
final class TripDecisionTests: XCTestCase {

    // MARK: The fixture

    struct Fixture: Decodable {
        var decisions: DecisionsWire
        var packPlace: PackPlace
        var job: StagedJob
        var notes: [NoteFact]
        var start: TripStart
    }

    private static let rome = TimeZone(identifier: "Europe/Rome")!

    private func fixtureData() throws -> Data {
        let bundle = Bundle(for: TripDecisionTests.self)
        // At the bundle root (how xcodegen copies a source folder's
        // resources), under TripDecisions/, or — on Linux — beside this file.
        let candidates = [
            bundle.url(forResource: "decisions-wire", withExtension: "json"),
            bundle.url(forResource: "decisions-wire", withExtension: "json", subdirectory: "TripDecisions"),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Fixtures/TripDecisions/decisions-wire.json"),
        ].compactMap { $0 }
        for url in candidates {
            if let data = try? Data(contentsOf: url) { return data }
        }
        XCTFail("decisions-wire.json is not in the test bundle")
        throw CocoaError(.fileNoSuchFile)
    }

    private func fixture() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: try fixtureData())
    }

    func testTheSharedFixtureDecodes() throws {
        let f = try fixture()
        XCTAssertEqual(f.decisions.brief.items.count, 7)
        XCTAssertEqual(f.decisions.brief.assumed, 1)
        XCTAssertEqual(f.decisions.brief.items.first { $0.key == "meal-times" }?.origin, .assumed)
        XCTAssertEqual(f.decisions.brief.items.first { $0.kind == "stay" }?.origin, .notes)
        XCTAssertEqual(f.decisions.questions.count, 1)
        XCTAssertEqual(f.decisions.questions[0].defaultAnswer?.label, "Carry on")
        XCTAssertEqual(f.decisions.answered[0].chosenAnswer?.label, "Standard ticket")
        XCTAssertEqual(f.decisions.proposals.map(\.kind), [.swap, .shape])
        XCTAssertEqual(f.decisions.proposals[0].image?.credit, "Jane Smith")
        XCTAssertEqual(f.decisions.proposals[1].shape?.days.count, 5)
        XCTAssertEqual(f.decisions.pack.counts.places, 38)
        XCTAssertTrue(f.decisions.pack.isReady)
        XCTAssertEqual(f.packPlace.kind, "museum")
        XCTAssertEqual(f.job.stages?.count, 5)
        XCTAssertEqual(f.job.madeTripId, "ac7cde28-7d32-4456-95bc-01dffa53078f")
        XCTAssertEqual(f.notes.count, 2)
        XCTAssertEqual(f.start.travellers[1].age, 9)
    }

    /// A newer server's kind or state never fails a trip.
    func testAnUnknownKindDecodesAsUnknown() throws {
        var json = String(decoding: try fixtureData(), as: UTF8.self)
        json = json.replacingOccurrences(of: "\"kind\": \"swap\"", with: "\"kind\": \"teleport\"")
        json = json.replacingOccurrences(of: "\"state\": \"waiting\"", with: "\"state\": \"pondering\"")
        let f = try JSONDecoder().decode(Fixture.self, from: Data(json.utf8))
        XCTAssertEqual(f.decisions.proposals[0].kind, .unknown)
        XCTAssertEqual(f.job.stages?.last?.state, .unknown)
    }

    // MARK: What the phone sends

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    func testProposalAndQuestionActionsEncodeAsTheContractSays() throws {
        XCTAssertEqual(try object(ProposalAction.accept) as NSDictionary, ["action": "accept"] as NSDictionary)
        XCTAssertEqual(try object(ProposalAction.reject(.tooFar, note: nil)) as NSDictionary,
                       ["action": "reject", "reason": "too-far"] as NSDictionary)
        XCTAssertEqual(try object(QuestionAction.answer("a0")) as NSDictionary, ["action": "answer", "answerId": "a0"] as NSDictionary)
        XCTAssertEqual(try object(QuestionAction.decide) as NSDictionary, ["action": "decide"] as NSDictionary)
        XCTAssertEqual(try object(QuestionAction.skip) as NSDictionary, ["action": "skip"] as NSDictionary)
        XCTAssertEqual(try object(QuestionAction.vote("a1")) as NSDictionary, ["action": "vote", "answerId": "a1"] as NSDictionary)
    }

    func testProposalRequestsEncodeTheirTargets() throws {
        let swap = try object(ProposalRequest.swap(stopId: "s1", wishId: "w1", date: "2026-10-27"))
        XCTAssertEqual(swap["kind"] as? String, "swap")
        XCTAssertEqual((swap["target"] as? [String: Any])?["stopId"] as? String, "s1")
        XCTAssertNil(swap["nudge"], "absent, not null")
        let day = try object(ProposalRequest.day(.swapDays, date: "2026-10-27", withDate: "2026-10-29"))
        XCTAssertEqual(day["variant"] as? String, "swap-days")
        XCTAssertEqual(day["withDate"] as? String, "2026-10-29")
        let f = try fixture()
        let nudge = try object(ProposalRequest.nudge(.lessWalking, on: f.decisions.proposals[0]))
        XCTAssertEqual(nudge["nudge"] as? String, "less-walking")
        XCTAssertEqual((nudge["target"] as? [String: Any])?["proposalId"] as? String, f.decisions.proposals[0].id)
    }

    func testBriefPatchesEncodeByField() throws {
        XCTAssertEqual(try object(BriefPatch.confirm(key: "meal-times")) as NSDictionary,
                       ["field": "confirm", "key": "meal-times"] as NSDictionary)
        XCTAssertEqual(try object(BriefPatch.dates(start: "2026-10-26", end: "2026-10-30")) as NSDictionary,
                       ["field": "dates", "startDate": "2026-10-26", "endDate": "2026-10-30"] as NSDictionary)
        let people = try object(BriefPatch.travellers([TripStart.Traveller(name: "Sam", age: 9, personId: nil)]))
        let first = (people["travellers"] as? [[String: Any]])?.first
        XCTAssertEqual(first?["name"] as? String, "Sam")
        XCTAssertTrue(first?["personId"] is NSNull, "nullable, and present")
    }

    /// The guided start: every nullable field present, as the server reads it.
    func testTheStartEncodesNullsExplicitly() throws {
        let start = TripStart(destination: "Rome", startDate: "2026-10-26", endDate: "2026-10-30",
                              travellers: [TripStart.Traveller(name: "Alex", age: nil, personId: "alex")],
                              pace: "normal", confirmNotes: [], text: nil)
        let body = try object(StartBody(start: start))
        XCTAssertEqual(body["async"] as? Bool, true)
        let s = body["start"] as? [String: Any]
        XCTAssertTrue(s?["text"] is NSNull)
        XCTAssertTrue((s?["travellers"] as? [[String: Any]])?.first?["age"] is NSNull)
        // And it still reads back.
        let back = try JSONDecoder().decode(TripStart.self, from: try JSONEncoder().encode(start))
        XCTAssertEqual(back, start)
    }

    // MARK: Questions

    private func question(_ id: String, impact: Double, deadline: String? = nil, audience: String = "owner",
                          status: QuestionStatus = .open, created: String = "2026-10-21T10:00:00Z") -> TripQuestion {
        TripQuestion(
            id: id, key: id, origin: "planner", prompt: "Q \(id)?", why: "Changes Tuesday",
            answers: [QuestionAnswer(id: "a0", label: "Yes", ops: [], brief: nil, remember: nil, summary: "Tuesday changes", changes: 2),
                      QuestionAnswer(id: "a1", label: "No", ops: [], brief: nil, remember: nil, summary: nil, changes: 0)],
            defaultAnswerId: "a1", appliedDefault: true, ifSkipped: "carry on as planned", affects: .init(dates: [], stops: 2),
            impact: impact, audience: audience, deadline: deadline, status: status, answerId: nil, answeredByName: nil,
            votes: [:], basedOnVersion: 1, createdAt: created, answeredAt: nil
        )
    }

    private static let member = TripAccess(canEdit: false, canApprove: false, canSuggest: true, role: "member")

    func testOpenQuestionsAreRankedCappedAndFilteredForMembers() {
        let qs = [
            question("low", impact: 1),
            question("soon", impact: 4, deadline: "2026-10-22"),
            question("later", impact: 4, deadline: "2026-10-25"),
            question("big", impact: 9, audience: "family"),
            question("done", impact: 20, status: .answered),
        ]
        XCTAssertEqual(TripDecisions.openQuestions(qs, access: .owner).map(\.id), ["big", "soon", "later"])
        XCTAssertEqual(TripDecisions.openQuestions(qs, access: Self.member).map(\.id), ["big"], "members see family questions only")
        XCTAssertEqual(TripDecisions.counter(0, of: 3), "1 of 3")
        XCTAssertEqual(TripDecisions.questionsHeading(1), "1 quick question")
        XCTAssertEqual(TripDecisions.questionsHeading(3), "3 quick questions")
    }

    func testAQuestionSaysWhatSkippingDoesAndWhenItIsDue() throws {
        let f = try fixture()
        XCTAssertEqual(TripDecisions.ifSkipped(f.decisions.questions[0]), "If you skip: carry on, with a long lunch.")
        let due = question("d", impact: 1, deadline: "2026-10-23")
        XCTAssertEqual(TripDecisions.deadline(due, today: "2026-10-21", zone: Self.rome)?.text, "Answer by Fri 23 Oct")
        XCTAssertEqual(TripDecisions.deadline(due, today: "2026-10-21", zone: Self.rome)?.urgent, true)
        XCTAssertEqual(TripDecisions.deadline(due, today: "2026-10-10", zone: Self.rome)?.urgent, false)
        XCTAssertEqual(TripDecisions.deadline(due, today: "2026-10-23", zone: Self.rome)?.text, "Answer today")
        XCTAssertEqual(TripDecisions.deadline(due, today: "2026-10-24", zone: Self.rome)?.text, "Was due Fri 23 Oct")
        XCTAssertNil(TripDecisions.deadline(question("n", impact: 1), today: "2026-10-21", zone: Self.rome))
        XCTAssertEqual(TripDecisions.votesLine(f.decisions.answered[0]), "Votes: Yes, I'll book — Sam · Standard ticket — John")
        let spoken = TripDecisions.spoken(f.decisions.questions[0].answers[1], in: f.decisions.questions[0], voting: false)
        XCTAssertEqual(spoken, "Answer: Carry on. The plan assumes this now")
    }

    // MARK: Proposals

    func testGroupsPutShapesFirstAndNameTheirChoice() throws {
        let f = try fixture()
        let groups = TripDecisions.groups(f.decisions.proposals, bundle: nil, zone: Self.rome)
        XCTAssertEqual(groups.map(\.kind), [.shape, .swap])
        XCTAssertEqual(groups[0].heading, "A way to do the trip")
        XCTAssertEqual(groups[1].heading, "Instead of Capitoline Museums")
        var closed = f.decisions.proposals
        closed[0].status = .rejected
        XCTAssertEqual(TripDecisions.groups(closed, bundle: nil, zone: Self.rome).count, 1, "only open proposals show")
    }

    func testTradeOffChipsReadAsTheCardSaysThem() throws {
        let f = try fixture()
        let swap = TripDecisions.chips(f.decisions.proposals[0], currencySymbol: "eurosign.circle")
        XCTAssertEqual(swap.map(\.text), ["11 min less walking", "€10 each", "Indoors", "Good for children", "Less visited"])
        XCTAssertEqual(swap.first?.tone, .good)
        let shape = TripDecisions.chips(f.decisions.proposals[1], currencySymbol: "eurosign.circle")
        XCTAssertEqual(shape.map(\.text), ["6.1 km a day", "2 early starts", "2 to book", "Good for children", "Less visited"])
        XCTAssertNil(TripDecisions.pushesOut(f.decisions.proposals[0]))
        var pushy = f.decisions.proposals[0]
        pushy.tradeoffs.pushesOut = ["Trevi Fountain", "Spanish Steps"]
        pushy.tradeoffs.fits = false
        XCTAssertEqual(TripDecisions.pushesOut(pushy), "Pushes out Trevi Fountain and Spanish Steps")
        XCTAssertEqual(TripDecisions.chips(pushy, currencySymbol: "banknote").first?.tone, .warn)
    }

    func testCompareHighlightsOnlyTheDifferences() throws {
        let f = try fixture()
        let a = f.decisions.proposals[0]
        var b = a
        b.id = "other"
        b.title = "Palazzo Massimo"
        b.tradeoffs.costText = "€12 each"
        b.tradeoffs.walkMin = 4
        let rows = TripDecisions.compare(a, b, zone: Self.rome)
        XCTAssertEqual(rows.filter(\.differs).map(\.label), ["Walking", "Cost"])
        XCTAssertEqual(rows.first { $0.id == "walk" }?.left, "11 min less")
        XCTAssertEqual(rows.first { $0.id == "walk" }?.right, "4 min more")
        XCTAssertTrue(rows.contains { $0.id == "kids" && !$0.differs }, "what is the same still shows, quietly")
        XCTAssertEqual(rows.first { $0.id == "walk" }?.better, 0, "less walking is ticked")
        XCTAssertNil(rows.first { $0.id == "cost" }?.better, "a price in words is not judged")
    }

    func testTheFitSplitsIntoATimeAndTheRest() {
        XCTAssertEqual(TripDecisions.fitParts("15:10–16:25, 12 min walk in").time, "15:10–16:25")
        XCTAssertEqual(TripDecisions.fitParts("15:10–16:25, 12 min walk in").rest, "12 min walk in")
        XCTAssertEqual(TripDecisions.fitParts("14:30").time, "14:30")
        XCTAssertNil(TripDecisions.fitParts("Would push out dinner").time)
        XCTAssertEqual(TripDecisions.fitParts("Would push out dinner").rest, "Would push out dinner")
        XCTAssertNil(TripDecisions.fitParts(nil).rest)
    }

    func testTheQuestionEyebrowNamesTheDay() throws {
        let f = try fixture()
        XCTAssertEqual(TripDecisions.eyebrow(f.decisions.questions[0], today: "2026-10-21", zone: Self.rome), "Wed 28 Oct")
        XCTAssertEqual(TripDecisions.eyebrow(f.decisions.answered[0], today: "2026-10-14", zone: Self.rome), "Thu 29 Oct · book soon")
    }

    // MARK: What changed

    func testADiffReadsAsBeforeAndAfterPerDay() throws {
        let f = try fixture()
        let days = TripDecisions.changeDays(f.decisions.proposals[0].diff, zone: Self.rome)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].title, "Tue 27 Oct")
        XCTAssertEqual(days[0].lines.map(\.title), ["Palazzo Altemps", "Capitoline Museums"])
        XCTAssertEqual(days[0].lines[0].after, "15:10")
        XCTAssertNil(days[0].lines[0].before)
        XCTAssertEqual(days[0].lines[1].before, "15:00")
        XCTAssertEqual(days[0].lines[1].after, "Removed")
        XCTAssertEqual(days[0].lines[0].spoken, "Palazzo Altemps added at 15:10")
        XCTAssertEqual(TripDecisions.walkDelta(-850), "850 m less walking")
        XCTAssertEqual(TripDecisions.walkDelta(1240), "1.2 km more walking")
        XCTAssertNil(TripDecisions.walkDelta(20))
        XCTAssertEqual(TripDecisions.summary(f.decisions.proposals[0].diff, zone: Self.rome), "2 changes · Tue 27 Oct")
        XCTAssertEqual(TripDecisions.undoLabel(f.decisions.proposals[0].diff), "Undo these 2")
        XCTAssertEqual(TripDecisions.undoLabel(.empty), "Undo this")
        XCTAssertEqual(TripDecisions.summary(.empty, zone: Self.rome), "Nothing moved")
    }

    func testAMoveSaysBothDays() {
        let move = PlanChange(kind: "moved", wishId: "w", title: "Pantheon", date: "2026-10-29", fromDate: "2026-10-27",
                              fromMin: 660, toMin: 705, reason: nil)
        let diff = PlanDiff(lines: [], changes: [move], dates: ["2026-10-27", "2026-10-29"], walkDeltaM: nil, dropped: [])
        let days = TripDecisions.changeDays(diff, zone: Self.rome)
        XCTAssertEqual(days.map(\.title), ["Thu 29 Oct"], "a day with nothing on it is not drawn")
        XCTAssertEqual(days[0].lines[0].before, "Tue 27 Oct 11:00")
        XCTAssertEqual(days[0].lines[0].after, "Thu 29 Oct 11:45")
        let plain = PlanDiff(lines: ["Pantheon moved to Thursday."], changes: [], dates: [], walkDeltaM: nil, dropped: [])
        XCTAssertEqual(TripDecisions.changeDays(plain, zone: Self.rome).first?.lines.first?.title, "Pantheon moved to Thursday.")
    }

    // MARK: The money symbol

    func testTheCurrencyFollowsTheTrip() {
        XCTAssertEqual(TripDecisions.currencySymbol(timeZone: "Europe/London"), "sterlingsign.circle", "no euro for Edinburgh")
        XCTAssertEqual(TripDecisions.currencySymbol(timeZone: "Europe/Rome"), "eurosign.circle")
        XCTAssertEqual(TripDecisions.currencySymbol(timeZone: "America/New_York"), "dollarsign.circle")
        XCTAssertEqual(TripDecisions.currencySymbol(timeZone: "Europe/London", costText: "€10"), "eurosign.circle", "the price's own symbol wins")
        XCTAssertEqual(TripDecisions.currencySymbol(timeZone: "Asia/Bangkok"), "banknote")
    }

    // MARK: Starting a trip

    func testTheStartProgressTicksItsStages() throws {
        let f = try fixture()
        let p = TripDecisions.progress(f.job)
        XCTAssertEqual(p.count, "3 of 5 done")
        XCTAssertEqual(p.current, "Checking opening hours on your dates")
        XCTAssertFalse(p.finished)
        XCTAssertNil(p.failed)
        XCTAssertEqual(p.lines.first?.detail, "Rome, 26–30 Oct, 4 travellers")
        var failed = f.job
        failed.status = "failed"
        failed.error = "The research ran out of time."
        XCTAssertEqual(TripDecisions.progress(failed).failed, "The research ran out of time.")
        var cancelled = f.job
        cancelled.status = "cancelled"
        XCTAssertTrue(TripDecisions.progress(cancelled).cancelled)
        XCTAssertEqual(TripDecisions.symbol(.done), "checkmark.circle.fill")
    }

    func testTheDraftChecksItselfAndBecomesAStart() {
        let zone = TimeZone(identifier: "Europe/London")!
        func day(_ s: String) -> Date { TripClock("Europe/London").date(s, minutes: 12 * 60)! }
        var draft = TripStartDraft(startDate: day("2026-10-26"), endDate: day("2026-10-24"))
        XCTAssertEqual(draft.problems(zone: zone), ["Say where you're going.", "The trip ends before it starts."])
        draft.destination = "  Rome "
        draft.endDate = day("2026-10-30")
        draft.travellers = [TripStart.Traveller(name: "Alex", age: nil, personId: "alex"), TripStart.Traveller(name: "Sam", age: 9, personId: nil)]
        draft.confirmNotes = ["note:stay:1", "note:gone"]
        draft.text = " We love food markets "
        XCTAssertEqual(draft.problems(zone: zone), [])
        let notes = [NoteFact(id: "note:stay:1", kind: "stay", label: "Airbnb", detail: nil, ops: [], ref: nil)]
        let start = draft.start(zone: zone, notes: notes)
        XCTAssertEqual(start.destination, "Rome")
        XCTAssertEqual(start.startDate, "2026-10-26")
        XCTAssertEqual(start.endDate, "2026-10-30")
        XCTAssertEqual(start.confirmNotes, ["note:stay:1"], "a note no longer offered is not sent")
        XCTAssertEqual(start.text, "We love food markets")
        XCTAssertEqual(draft.sentence(zone: zone), "Rome, 26–30 Oct, with Alex and Sam (9), normal pace. We love food markets")
        draft.endDate = day("2026-12-30")
        XCTAssertEqual(draft.problems(zone: zone), ["A trip can be up to 30 days."])
    }

    // MARK: Converse

    func testStartersFollowThePhase() {
        XCTAssertEqual(TripDecisions.starters(phase: .before, canEdit: true).first, "What are we missing?")
        XCTAssertEqual(TripDecisions.starters(phase: .during, canEdit: true).first, "We're running about 20 minutes late")
        XCTAssertEqual(TripDecisions.starters(phase: .before, canEdit: false).count, 3)
        XCTAssertEqual(TripPhase.of(start: "2026-10-26", end: "2026-10-30", today: "2026-10-21"), .before)
        XCTAssertEqual(TripPhase.of(start: "2026-10-26", end: "2026-10-30", today: "2026-10-30"), .during)
        XCTAssertEqual(TripPhase.of(start: "2026-10-26", end: "2026-10-30", today: "2026-11-01"), .after)
    }

    // MARK: The phone's copy after a decision

    private func bundle(_ f: Fixture) -> TripBundle {
        let trip = Trip(id: "t", title: "Rome", destination: "Rome", timeZone: "Europe/Rome", startDate: "2026-10-26",
                        endDate: "2026-10-30", pace: .normal, modes: [.walk], status: .draft, notes: nil)
        var b = TripBundle(trip: trip, stays: [], wishes: [], bookings: [], plan: nil, matrices: [:], etag: "e")
        b.brief = f.decisions.brief
        b.questions = f.decisions.questions
        b.answered = f.decisions.answered
        b.proposals = f.decisions.proposals
        b.pack = f.decisions.pack
        return b
    }

    private func alternative(_ p: TripProposal, _ id: String) -> TripProposal {
        var q = p
        q.id = id
        return q
    }

    func testTakingAProposalSettlesItsGroup() throws {
        let f = try fixture()
        var b = bundle(f)
        let swap = f.decisions.proposals[0]
        b.proposals = [swap, alternative(swap, "alt-1"), f.decisions.proposals[1]]
        b.settle(accepted: swap)
        XCTAssertEqual(b.proposals?.map(\.id), [f.decisions.proposals[1].id], "the other swap is superseded; the shape stays")
        b.settle(accepted: f.decisions.proposals[1])
        XCTAssertEqual(b.proposals?.count, 0)
    }

    func testTurningOneDownLeavesItsAlternatives() throws {
        let f = try fixture()
        var b = bundle(f)
        let swap = f.decisions.proposals[0]
        b.proposals = [swap, alternative(swap, "alt-1")]
        b.settle(rejected: swap)
        XCTAssertEqual(b.proposals?.map(\.id), ["alt-1"])
    }

    func testANewGroupReplacesTheOldOneAndAStaleProposalIsSwappedIn() throws {
        let f = try fixture()
        var b = bundle(f)
        let swap = f.decisions.proposals[0]
        b.merge(group: [alternative(swap, "n1"), alternative(swap, "n2")])
        XCTAssertEqual(b.proposals?.map(\.id), [f.decisions.proposals[1].id, "n1", "n2"], "same group id: replaced, not added")
        var moved = alternative(swap, "n1")
        moved.title = "Palazzo Altemps, later"
        b.replace(moved)
        XCTAssertEqual(b.proposals?.first { $0.id == "n1" }?.title, "Palazzo Altemps, later")
    }

    func testAnAnsweredQuestionMovesAndAVoteStays() throws {
        let f = try fixture()
        var b = bundle(f)
        var voted = f.decisions.questions[0]
        voted.votes = ["a0": ["Sam"]]
        b.settle(question: voted)
        XCTAssertEqual(b.questions?.first?.votes["a0"], ["Sam"], "a vote leaves it open")
        var answered = voted
        answered.status = .answered
        answered.answerId = "a0"
        b.settle(question: answered)
        XCTAssertEqual(b.questions?.count, 0)
        XCTAssertEqual(b.answered?.first?.id, answered.id)
        var skipped = f.decisions.questions[0]
        skipped.id = "s"
        skipped.status = .skipped
        b.questions = [skipped]
        b.settle(question: skipped)
        XCTAssertEqual(b.questions?.count, 0)
        XCTAssertEqual(b.answered?.count, 2, "a skip is not an answer")
    }

    func testAChangeRecordKeepsItsUndo() throws {
        let f = try fixture()
        let result = DecisionResult(proposal: f.decisions.proposals[0], question: nil, planVersion: 13, changes: ["Palazzo Altemps added"],
                                    diff: f.decisions.proposals[0].diff, undo: UndoPoint(toVersion: 12), remember: nil, stale: nil)
        let record = TripChangeRecord.of(result, tripId: "t", title: "Used Palazzo Altemps")
        XCTAssertEqual(record.undoTo, 12)
        XCTAssertEqual(record.planVersion, 13)
        let back = try JSONDecoder().decode(TripChangeRecord.self, from: try JSONEncoder().encode(record))
        XCTAssertEqual(back, record, "it survives a relaunch")
    }

    func testOnlyEditorsSwapAndOnlyUnlockedVisits() throws {
        let f = try fixture()
        var b = bundle(f)
        let free = PlannedStop(id: "w1", kind: .wish, wishId: "w1", title: "Trevi", location: nil, arriveMin: 600, departMin: 630,
                               waitSec: 0, locked: false, bookingId: nil, warnings: [])
        var locked = free
        locked.locked = true
        var meal = free
        meal.kind = .meal
        XCTAssertTrue(TripDecisions.canSwap(free, bundle: b))
        XCTAssertFalse(TripDecisions.canSwap(locked, bundle: b))
        XCTAssertFalse(TripDecisions.canSwap(meal, bundle: b))
        b.access = Self.member
        XCTAssertFalse(TripDecisions.canSwap(free, bundle: b), "members suggest; they never swap")
        b.access = .owner
        b.proposals = nil
        b.questions = nil
        b.brief = nil
        XCTAssertFalse(TripDecisions.canSwap(free, bundle: b), "an older server has no swaps")
    }
}
