import XCTest
@testable import SRAppleApp

/// Trips v8, reach: questions outside the app — the links they carry, the
/// buttons a question's notification wears and what each press sends — and
/// how the Home tile says the next trip.
///
/// Foundation only, like the code under test: the Linux harness runs this
/// file too (`swift test` over the trip models).
final class TripReachTests: XCTestCase {

    // MARK: - Fixtures

    private func answer(_ id: String, _ label: String) -> QuestionAnswer {
        QuestionAnswer(id: id, label: label, ops: [], brief: nil, remember: nil, summary: nil, changes: 1)
    }

    private func question(
        _ id: String = "q1",
        answers: [QuestionAnswer]? = nil,
        status: QuestionStatus = .open,
        audience: String = "owner",
        defaultAnswerId: String = "a1"
    ) -> TripQuestion {
        TripQuestion(
            id: id, key: "k-\(id)", origin: "tie", prompt: "After the Vatican — rest or carry on?",
            why: "Changes Wednesday afternoon", answers: answers ?? [answer("a0", "Back to the flat"), answer("a1", "Carry on")],
            defaultAnswerId: defaultAnswerId, appliedDefault: true, ifSkipped: "Carry on",
            affects: TripQuestion.Affects(dates: ["2026-10-28"], stops: 3), impact: 3, audience: audience,
            deadline: nil, status: status, answerId: nil, answeredByName: nil, votes: [:], basedOnVersion: 12,
            createdAt: "2026-10-21T13:00:00.000Z", answeredAt: nil
        )
    }

    // MARK: - Links

    func testAQuestionLinkOpensTheTripAtTheQuestionNotADayCalledQuestions() {
        XCTAssertEqual(TripLink.from(url: URL(string: "sr://trips/rome/questions/q1")!),
                       TripLink(tripId: "rome", date: nil, questionId: "q1"))
        XCTAssertEqual(TripLink.from(url: URL(string: "sr://trips/rome/questions")!),
                       TripLink(tripId: "rome", date: nil, questionId: nil))
        // The day links are as they were.
        XCTAssertEqual(TripLink.from(url: URL(string: "sr://trips/rome/2026-10-27")!), TripLink(tripId: "rome", date: "2026-10-27"))
        XCTAssertEqual(TripLink.from(url: URL(string: "sr://trips")!), TripLink(tripId: nil, date: nil))
    }

    func testAQuestionLinkRoundTrips() throws {
        let url = try XCTUnwrap(TripLink.questionURL(tripId: "rome", questionId: "q 1"))
        XCTAssertEqual(TripLink.from(url: url), TripLink(tripId: "rome", date: nil, questionId: "q 1"))
    }

    func testANotificationNamesItsQuestionInUserInfoOrInItsLink() {
        XCTAssertEqual(TripLink.from(userInfo: ["tripId": "rome", "questionId": "q1", "date": "2026-10-27"]),
                       TripLink(tripId: "rome", date: nil, questionId: "q1"))
        // A private preview keeps only `category` and `url`.
        XCTAssertEqual(TripLink.from(userInfo: ["category": "trip-question", "url": "sr://trips/rome/questions/q1"]),
                       TripLink(tripId: "rome", date: nil, questionId: "q1"))
        XCTAssertEqual(TripLink.from(userInfo: ["category": "trip", "url": "https://example.org"]), TripLink(tripId: nil, date: nil))
    }

    // MARK: - A question's buttons

    func testAQuestionWearsItsOwnAnswersThenYouDecide() throws {
        let category = try XCTUnwrap(TripQuestionPushes.category(question()))
        XCTAssertEqual(category.identifier, "trip-q-q1")
        XCTAssertEqual(category.buttons.map(\.id), ["a0", "a1", "decide"])
        XCTAssertEqual(category.buttons.map(\.title), ["Back to the flat", "Carry on", "You decide"])
    }

    func testAtMostThreeAnswersAsButtons() throws {
        let many = question(answers: (0..<5).map { answer("a\($0)", "Answer \($0)") })
        let category = try XCTUnwrap(TripQuestionPushes.category(many))
        XCTAssertEqual(category.buttons.map(\.id), ["a0", "a1", "a2", "decide"])
    }

    func testAnAnswerThatWouldPassForAnotherButtonIsLeftOff() throws {
        let odd = question(answers: [answer("decide", "Odd"), answer("com.apple.UNNotificationDefaultActionIdentifier", "Odder"),
                                     answer("a1", "Carry on"), answer("a2", "  ")])
        let category = try XCTUnwrap(TripQuestionPushes.category(odd))
        XCTAssertEqual(category.buttons.map(\.id), ["a1", "decide"])
    }

    func testOnlyOpenQuestionsWithAnswersGetButtons() {
        XCTAssertNil(TripQuestionPushes.category(question(status: .answered)))
        XCTAssertNil(TripQuestionPushes.category(question(status: .skipped)))
        XCTAssertNil(TripQuestionPushes.category(question(answers: [])))
    }

    func testEveryOpenQuestionOnceSortedSoAnUnchangedSetComparesEqual() {
        let a = TripQuestionPushes.categories(questions: [question("q2"), question("q1"), question("q2"), question("q3", status: .expired)])
        XCTAssertEqual(a.map(\.identifier), ["trip-q-q1", "trip-q-q2"])
        XCTAssertEqual(a, TripQuestionPushes.categories(questions: [question("q1"), question("q2")]))
    }

    func testCategoryIdentifiersRoundTrip() {
        XCTAssertEqual(TripQuestionPushes.questionId(categoryIdentifier: "trip-q-q1"), "q1")
        XCTAssertNil(TripQuestionPushes.questionId(categoryIdentifier: "trip-q-"))
        XCTAssertNil(TripQuestionPushes.questionId(categoryIdentifier: "trip"))
        XCTAssertTrue(TripQuestionPushes.isQuestion("trip-question"))
        XCTAssertTrue(TripQuestionPushes.isQuestion("trip-q-q1"))
        XCTAssertFalse(TripQuestionPushes.isQuestion("trip"))
    }

    // MARK: - What a press means

    private let push: [AnyHashable: Any] = [
        "category": "trip-question", "tripId": "rome", "questionId": "q1",
        "url": "sr://trips/rome/questions/q1", "prompt": "Rest or carry on?",
    ]

    func testAnAnswerButtonAnswersThatQuestion() {
        XCTAssertEqual(
            TripQuestionPushes.response(action: "a0", categoryIdentifier: "trip-q-q1", userInfo: push),
            .answer(.init(tripId: "rome", questionId: "q1", choice: .answer("a0")))
        )
        XCTAssertEqual(
            TripQuestionPushes.response(action: "decide", categoryIdentifier: "trip-q-q1", userInfo: push),
            .answer(.init(tripId: "rome", questionId: "q1", choice: .decide))
        )
    }

    func testATapOpensTheQuestionEvenWithoutItsButtons() {
        // The contract's fixed category: nothing registered, a plain banner.
        XCTAssertEqual(
            TripQuestionPushes.response(action: TripQuestionPushes.tapAction, categoryIdentifier: "trip-question", userInfo: push),
            .open(TripLink(tripId: "rome", date: nil, questionId: "q1"))
        )
    }

    func testAPrivatePreviewStillAnswersFromItsLinkAndCategory() {
        let hidden: [AnyHashable: Any] = ["category": "trip-question", "url": "sr://trips/rome"]
        XCTAssertEqual(
            TripQuestionPushes.response(action: "a1", categoryIdentifier: "trip-q-q9", userInfo: hidden),
            .answer(.init(tripId: "rome", questionId: "q9", choice: .answer("a1")))
        )
    }

    func testAButtonThatNamesNoTripDoesNothingRatherThanOpeningTheApp() {
        XCTAssertEqual(TripQuestionPushes.response(action: "a1", categoryIdentifier: "trip-q-q1", userInfo: [:]), .ignore)
        XCTAssertEqual(TripQuestionPushes.response(action: TripQuestionPushes.dismissAction, categoryIdentifier: "trip-q-q1", userInfo: push), .ignore)
    }

    func testOtherNotificationsAreNotTripQuestions() {
        XCTAssertNil(TripQuestionPushes.response(action: "sr.alert.read", categoryIdentifier: "sr.alert", userInfo: ["category": "health"]))
        XCTAssertNil(TripQuestionPushes.response(action: TripQuestionPushes.tapAction, categoryIdentifier: "", userInfo: ["category": "trip", "tripId": "rome"]))
    }

    func testThePathEscapesTheIds() {
        XCTAssertEqual(TripQuestionPushes.Answer(tripId: "rome", questionId: "q/1", choice: .decide).path,
                       "api/native/trips/rome/questions/q%2F1")
    }

    // MARK: - What a press sends

    func testAnOwnersPressAnswersOrDecides() {
        let owner = TripAccess.owner
        XCTAssertEqual(TripQuestionPushes.body(.answer("a0"), question: question(), access: owner), ["action": "answer", "answerId": "a0"])
        XCTAssertEqual(TripQuestionPushes.body(.decide, question: question(), access: owner), ["action": "decide"])
        // A trip not on the phone yet: answer, and let the site judge.
        XCTAssertEqual(TripQuestionPushes.body(.answer("a0"), question: nil, access: nil), ["action": "answer", "answerId": "a0"])
    }

    func testAMemberVotesOnAFamilyQuestionAndADecisionIsAVoteForTheAssumedAnswer() {
        let member = TripAccess(canEdit: false, canApprove: false, canSuggest: true, role: "member")
        let family = question(audience: "family", defaultAnswerId: "a1")
        XCTAssertEqual(TripQuestionPushes.body(.answer("a0"), question: family, access: member), ["action": "vote", "answerId": "a0"])
        XCTAssertEqual(TripQuestionPushes.body(.decide, question: family, access: member), ["action": "vote", "answerId": "a1"])
        // A parent decides.
        let parent = TripAccess(canEdit: false, canApprove: true, canSuggest: true, role: "parent")
        XCTAssertEqual(TripQuestionPushes.body(.answer("a0"), question: family, access: parent), ["action": "answer", "answerId": "a0"])
    }

    // MARK: - The Home tile's words

    func testTheTileSaysTheNextTripAndItsQuestions() {
        XCTAssertEqual(HomeTripWords.spoken(destination: "Rome, Italy", days: 5, questions: 2), "Rome · in 5 days · 2 quick questions")
        XCTAssertEqual(HomeTripWords.spoken(destination: "Rome, Italy", days: 1, questions: 1), "Rome · Tomorrow · 1 quick question")
        XCTAssertEqual(HomeTripWords.spoken(destination: "Edinburgh", days: 12, questions: 0), "Edinburgh · in 12 days")
        XCTAssertEqual(HomeTripWords.countdown(days: nil), "Soon")
        XCTAssertNil(HomeTripWords.questions(0))
    }

    func testTheTilesDatesSayTheWeekdays() {
        XCTAssertEqual(HomeTripWords.dates(start: "2026-10-26", end: "2026-10-30"), "Mon 26 – Fri 30 Oct")
        XCTAssertEqual(HomeTripWords.dates(start: "2026-10-30", end: "2026-11-02"), "Fri 30 Oct – Mon 2 Nov")
        XCTAssertEqual(HomeTripWords.caption(destination: "Rome, Italy", start: "2026-10-26", end: "2026-10-30"), "Rome · Mon 26 – Fri 30 Oct")
        XCTAssertNil(HomeTripWords.dates(start: "soon", end: "later"))
    }
}
