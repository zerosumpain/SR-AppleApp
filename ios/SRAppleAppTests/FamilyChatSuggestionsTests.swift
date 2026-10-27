import XCTest
@testable import SRAppleApp

/// msg family's landing: the status under each person's circle, the "what
/// you missed" line, and the suggestions.
///
/// Foundation only: `scripts/home-check.sh` runs this file on Linux too.
final class FamilyChatSuggestionsTests: XCTestCase {

    private let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    /// Tuesday 27 October 2026, 10:00 in London (GMT).
    private let ten = Date(timeIntervalSince1970: 1_793_095_200)

    /// Tuesday at hh:mm, London.
    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        ten.addingTimeInterval(Double((hour - 10) * 3600 + minute * 60 + dayOffset * 86_400))
    }

    private typealias Person = FamilyChatNow.Person
    private typealias Thread = FamilyChatSuggestions.Thread
    private typealias Line = FamilyChatSuggestions.Line

    private func make(_ now: Date, people: [Person] = [], me: String? = "Alex", threads: [Thread] = [],
                      steps: [FamilyChatSuggestions.Walker] = [], unread: Int = 0,
                      lastActivity: Date? = nil) -> [FamilyChatSuggestions.Suggestion] {
        FamilyChatSuggestions.make(now: now, people: people, me: me, threads: threads, steps: steps,
                                   unreadCount: unread, lastActivity: lastActivity ?? now.addingTimeInterval(-600),
                                   calendar: london)
    }

    // MARK: - Who's around

    func testStatusSaysWhereInTheFewestWords() {
        let now = at(16)
        func line(_ p: Person) -> String { FamilyChatNow.status(p, now: now, calendar: london).line }
        XCTAssertEqual(line(Person(subject: "r", name: "Robin", status: "home", atHome: true)), "Home")
        XCTAssertEqual(line(Person(subject: "s", name: "Sam", status: "out", place: "School", km: 1.4)), "School")
        XCTAssertEqual(line(Person(subject: "k", name: "Kit", status: "out", km: 2.13)), "Out · 2.1 km")
        XCTAssertEqual(line(Person(subject: "k", name: "Kit", status: "out", km: 0.38)), "Out · 400 m")
        XCTAssertEqual(line(Person(subject: "k", name: "Kit", status: "out", km: 14.4)), "Out · 14 km")
        XCTAssertEqual(line(Person(subject: "a", name: "Alex", status: "out", place: "Park", moving: "walking")), "Walking",
                       "on the move, a place is already behind them")
        XCTAssertEqual(line(Person(subject: "a", name: "Alex", status: "out", moving: "vehicle")), "Travelling")
        XCTAssertEqual(line(Person(subject: "p", name: "Pat", status: "off", battery: 5)), "Not sharing")
        XCTAssertEqual(line(Person(subject: "r", name: "Robin", status: "out", km: 0.05, atHome: true)), "Home",
                       "inside home's radius is home, whatever the site's word")
    }

    func testStatusMarksALowBatteryAndALostPerson() {
        let now = at(16)
        let low = FamilyChatNow.status(Person(subject: "s", name: "Sam", status: "out", place: "School", battery: 18), now: now, calendar: london)
        XCTAssertEqual(low.lowBattery, 18)
        XCTAssertEqual(low.spoken, "Sam, at School, battery 18%, low")
        XCTAssertNil(FamilyChatNow.status(Person(subject: "s", name: "Sam", status: "out", battery: 21), now: now, calendar: london).lowBattery)
        XCTAssertNil(FamilyChatNow.status(Person(subject: "p", name: "Pat", status: "off", battery: 5), now: now, calendar: london).lowBattery,
                     "not sharing: no battery is shown")

        let lost = FamilyChatNow.status(Person(subject: "k", name: "Kit", status: "unknown", place: "The Reservoir", moving: "walking",
                                               lastSeen: now.addingTimeInterval(-130 * 60)), now: now, calendar: london)
        XCTAssertEqual(lost.line, "The Reservoir")
        XCTAssertEqual(lost.detail, "2h ago")
        XCTAssertTrue(lost.quiet)
        XCTAssertEqual(lost.spoken, "Kit, last seen at The Reservoir, seen 2h ago")
        XCTAssertEqual(FamilyChatNow.status(Person(subject: "k", name: "Kit", status: "unknown"), now: now, calendar: london).line, "Not seen lately")
    }

    func testTheForecastSaysWhenTheyWillBeHomeWithinTwoHours() {
        let now = at(15, 10)
        let soon = Person(subject: "s", name: "Sam", status: "out", place: "School", homeBy: at(16, 5))
        let status = FamilyChatNow.status(soon, now: now, calendar: london)
        XCTAssertEqual(status.detail, "Home ~16:05")
        XCTAssertEqual(status.spoken, "Sam, at School, due home about 16:05")

        var later = soon
        later.homeBy = at(17, 30)
        XCTAssertNil(FamilyChatNow.status(later, now: now, calendar: london).detail, "further out than two hours is a routine, not news")
        var gone = soon
        gone.homeBy = at(15)
        XCTAssertNil(FamilyChatNow.status(gone, now: now, calendar: london).detail, "an arrival already past says nothing")
        var home = soon
        home.status = "home"
        XCTAssertNil(FamilyChatNow.status(home, now: now, calendar: london).detail, "home already")
    }

    // MARK: - What you missed

    func testMissedCountsOtherPeoplesLinesAndNamesThemInOrder() throws {
        let threads = [
            Thread(id: "1", from: "Katie", body: "Bus is late", at: at(8, 30), mine: false,
                   replies: [Line(from: "Alex", body: "Ok", at: at(8, 35), mine: true),
                             Line(from: "Fintan", body: "👍", at: at(9, 0), mine: false)]),
            Thread(id: "2", from: "Katie", body: "Home at 4", at: at(9, 30), mine: false),
            Thread(id: "3", from: "Robin", body: "Old news", at: at(7, 0), mine: false),
        ]
        let missed = try XCTUnwrap(FamilyChatNow.missed(threads, since: at(8, 10), now: at(10), calendar: london))
        XCTAssertEqual(missed.count, 3)
        XCTAssertEqual(missed.text, "3 new since 08:10 — Katie, Fintan")

        XCTAssertEqual(FamilyChatNow.missed(threads, since: at(21, 40, dayOffset: -1), now: at(10), calendar: london)?.text,
                       "4 new since yesterday 21:40 — Robin, Katie, Fintan")
        XCTAssertEqual(FamilyChatNow.missed(threads, since: at(18, 20, dayOffset: -2), now: at(10), calendar: london)?.text,
                       "4 new since Sun 18:20 — Robin, Katie, Fintan")
        XCTAssertEqual(FamilyChatNow.missed(threads, since: nil, now: at(10), calendar: london)?.text,
                       "4 new — Robin, Katie, Fintan", "never opened: everything is new")
        XCTAssertNil(FamilyChatNow.missed(threads, since: at(9, 45), now: at(10), calendar: london))
    }

    func testMissedNamesThreeThenCounts() {
        let threads = ["Ann", "Ben", "Cat", "Dan", "Ben"].enumerated().map { index, name in
            Thread(id: "\(index)", from: name, body: "hi", at: at(9, index), mine: false)
        }
        XCTAssertEqual(FamilyChatNow.missed(threads, since: at(8), now: at(10), calendar: london)?.text,
                       "5 new since 08:00 — Ann, Ben, Cat +1")
    }

    // MARK: - Suggestions

    func testDinnerIsAPollInTheLateAfternoon() throws {
        let ideas = make(at(16, 30))
        let dinner = try XCTUnwrap(ideas.first { $0.id == "dinner" })
        XCTAssertEqual(dinner.title, "Dinner tonight?")
        guard case .poll(let question, let options) = dinner.action else { return XCTFail("dinner is a poll") }
        XCTAssertEqual(question, "Dinner tonight?")
        XCTAssertEqual(options.count, 3)
        XCTAssertNotNil(FamilyPoll.make(question: question, options: options), "the poll sheet can send it as it stands")
        XCTAssertFalse(make(at(14)).contains { $0.id == "dinner" }, "too early")
        XCTAssertFalse(make(at(19)).contains { $0.id == "dinner" }, "too late")
    }

    func testDinnerIsNotSuggestedOnceItHasComeUpToday() {
        let talk = [Thread(id: "1", from: "Robin", body: "Pizza tonight?", at: at(12), mine: false)]
        XCTAssertFalse(make(at(16, 30), threads: talk).contains { $0.id == "dinner" })
        let yesterday = [Thread(id: "1", from: "Robin", body: "Dinner?", at: at(17, dayOffset: -1), mine: false)]
        XCTAssertTrue(make(at(16, 30), threads: yesterday).contains { $0.id == "dinner" })
        let steam = [Thread(id: "1", from: "Robin", body: "Team steamed ahead", at: at(12), mine: false)]
        XCTAssertTrue(make(at(16, 30), threads: steam).contains { $0.id == "dinner" }, "whole words only")
    }

    func testLateEveningAsksWhoeverIsStillOut() throws {
        let kit = Person(subject: "k", name: "Kit", status: "out", place: "Station")
        let robin = Person(subject: "r", name: "Robin", status: "home", atHome: true)
        let one = try XCTUnwrap(make(at(22, 15), people: [kit, robin]).first { $0.id == "home-safe" })
        XCTAssertEqual(one.title, "Home safe, Kit?")
        XCTAssertEqual(one.action, .fill("@Kit are you home safe?"))

        let sam = Person(subject: "s", name: "Sam", status: "unknown", place: "Park")
        let two = try XCTUnwrap(make(at(0, 30), people: [kit, sam, robin]).first { $0.id == "home-safe" })
        XCTAssertEqual(two.title, "Everyone home safe?")
        XCTAssertEqual(two.reason, "Kit and Sam are still out")

        XCTAssertFalse(make(at(20), people: [kit]).contains { $0.id == "home-safe" }, "not late yet")
        let everyoneIn = make(at(22, 15), people: [robin])
        XCTAssertFalse(everyoneIn.contains { $0.id == "home-safe" })
        XCTAssertEqual(everyoneIn.first?.id, "night")
    }

    func testTheStepLeaderIsCongratulatedUnlessItIsYou() throws {
        let board = [FamilyChatSuggestions.Walker(name: "Katie", steps: 14_200, me: false),
                     FamilyChatSuggestions.Walker(name: "Alex", steps: 9_000, me: true)]
        let steps = try XCTUnwrap(make(at(11), steps: board).first { $0.id == "steps" })
        XCTAssertEqual(steps.title, "Well done Katie — 14,200 steps")
        XCTAssertEqual(steps.action, .fill("Well done Katie — 14,200 steps today! 👟"))

        let mine = [FamilyChatSuggestions.Walker(name: "Alex", steps: 14_200, me: true),
                    FamilyChatSuggestions.Walker(name: "Katie", steps: 9_000, me: false)]
        XCTAssertFalse(make(at(11), steps: mine).contains { $0.id == "steps" })
        let early = [FamilyChatSuggestions.Walker(name: "Katie", steps: 1_200, me: false)]
        XCTAssertFalse(make(at(11), steps: early).contains { $0.id == "steps" }, "not worth a word yet")
    }

    func testAMentionOfYouIsTheFirstThingToAnswer() throws {
        let threads = [
            Thread(id: "milk", from: "Robin", body: "Shop run", at: at(9, 40), mine: false,
                   replies: [Line(from: "Robin", body: "@Alex can you grab milk?", at: at(9, 54), mine: false)]),
            Thread(id: "film", from: "Kit", body: "Film?", at: at(9, 30), mine: false),
        ]
        let first = try XCTUnwrap(make(at(10), threads: threads).first)
        XCTAssertEqual(first.id, "reply")
        XCTAssertEqual(first.title, "Reply to Robin")
        XCTAssertEqual(first.reason, "\u{201C}@Alex can you grab milk?\u{201D}")
        XCTAssertEqual(first.action, .open(thread: "milk"))

        // Answered since: nothing to nudge.
        var answered = threads
        answered[0].replies.append(Line(from: "Alex", body: "On it", at: at(9, 58), mine: true))
        XCTAssertNotEqual(make(at(10), threads: answered).first?.id, "reply")
        XCTAssertNotEqual(make(at(10), me: nil, threads: threads).first?.id, "reply", "no name, no mention")
    }

    func testAPollYouHaveNotVotedInAsksForYourVote() throws {
        let body = FamilyPoll(question: "Film night?", options: ["Up", "Cars"]).body
        let poll = Thread(id: "p", from: "Robin", body: body, at: at(8), mine: false,
                          replies: [Line(from: "Kit", body: "1️⃣", at: at(8, 5), mine: false)])
        let vote = try XCTUnwrap(make(at(10), threads: [poll]).first)
        XCTAssertEqual(vote.title, "Vote in Robin's poll")
        XCTAssertEqual(vote.reason, "Film night?")
        XCTAssertEqual(vote.action, .open(thread: "p"))

        var voted = poll
        voted.replies.append(Line(from: "Alex", body: "2️⃣", at: at(8, 10), mine: true))
        XCTAssertFalse(make(at(10), threads: [voted]).contains { $0.id == "vote" })
        XCTAssertFalse(make(at(10, dayOffset: 2), threads: [poll]).contains { $0.id == "vote" }, "a poll from days ago is over")
    }

    func testAQuestionNobodyHasAnsweredGetsANudgeAfterTwentyMinutes() throws {
        let ask = Thread(id: "q", from: "Kit", body: "Has anyone seen my\nblue jumper?", at: at(9, 30), mine: false)
        let nudge = try XCTUnwrap(make(at(10), threads: [ask]).first)
        XCTAssertEqual(nudge.title, "Answer Kit")
        XCTAssertEqual(nudge.reason, "\u{201C}Has anyone seen my blue jumper?\u{201D} · no replies yet")
        XCTAssertFalse(make(at(9, 40), threads: [ask]).contains { $0.id == "answer" }, "give the family a chance first")
        var answered = ask
        answered.replies = [Line(from: "Sam", body: "👍", at: at(9, 35), mine: false)]
        XCTAssertFalse(make(at(10), threads: [answered]).contains { $0.id == "answer" })
        let statement = Thread(id: "s", from: "Kit", body: "Home late", at: at(9, 30), mine: false)
        XCTAssertFalse(make(at(10), threads: [statement]).contains { $0.id == "answer" }, "not a question")
    }

    func testALowBatteryOutGetsANudgeToCharge() throws {
        let sam = Person(subject: "s", name: "Sam", status: "out", place: "School", battery: 18)
        let idea = try XCTUnwrap(make(at(11), people: [sam]).first { $0.id == "battery" })
        XCTAssertEqual(idea.title, "Sam's battery is low")
        XCTAssertEqual(idea.reason, "18% at School")
        XCTAssertEqual(idea.action, .fill("@Sam your battery's on 18% — charge up if you can 🔋"))
        let home = Person(subject: "s", name: "Sam", status: "home", atHome: true, battery: 8)
        XCTAssertFalse(make(at(11), people: [home]).contains { $0.id == "battery" }, "a charger is to hand")
    }

    func testTheTimeOfDayPicksTheStarter() {
        XCTAssertEqual(make(at(7, 45)).first?.id, "today")
        XCTAssertEqual(make(at(13)).first?.id, "tonight")
        // Friday 30 October.
        XCTAssertEqual(make(at(13, dayOffset: 3)).first?.id, "weekend")
        XCTAssertEqual(make(at(13, dayOffset: 3)).first?.reason, "It's Friday")
        XCTAssertEqual(make(at(9, dayOffset: 4)).first?.id, "weekend")
        XCTAssertTrue(make(at(10, 40)).isEmpty, "mid-morning with nothing to say says nothing")
    }

    func testAQuietChatIsNudgedToSayHello() {
        let quiet = FamilyChatSuggestions.make(now: at(10, 40), people: [], me: "Alex", threads: [], steps: [],
                                               unreadCount: 0, lastActivity: at(18, dayOffset: -2), calendar: london)
        XCTAssertEqual(quiet.first?.id, "hello")
        XCTAssertEqual(quiet.first?.reason, "Quiet since Sunday")
        let empty = FamilyChatSuggestions.make(now: at(10, 40), people: [], me: "Alex", threads: [], steps: [],
                                               unreadCount: 0, lastActivity: nil, calendar: london)
        XCTAssertEqual(empty.first?.reason, "No messages yet")
    }

    func testThreeAtMostAndTwoWhileThereIsSomethingNew() {
        let kit = Person(subject: "k", name: "Kit", status: "out", place: "Station", battery: 9)
        let board = [FamilyChatSuggestions.Walker(name: "Kit", steps: 12_000, me: false)]
        let ask = Thread(id: "q", from: "Kit", body: "Lift?", at: at(22), mine: false)
        let all = make(at(22, 30), people: [kit], threads: [ask], steps: board)
        XCTAssertEqual(all.map(\.id), ["answer", "home-safe", "battery"])
        XCTAssertEqual(make(at(22, 30), people: [kit], threads: [ask], steps: board, unread: 4).map(\.id), ["answer", "home-safe"])
    }
}
