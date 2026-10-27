import XCTest
@testable import SRAppleApp

/// msg family's tools: polls, unread lines, mentions, day headings, search,
/// "where I am", the counter and reminders.
///
/// Foundation only: `scripts/home-check.sh` runs this file on Linux too.
final class FamilyMessageToolsTests: XCTestCase {

    private let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    /// Tuesday 27 October 2026, 10:00 in London (GMT).
    private let ten = Date(timeIntervalSince1970: 1_793_095_200)

    // MARK: - Polls

    func testAPollRoundTripsThroughItsWords() throws {
        let poll = try XCTUnwrap(FamilyPoll.make(question: " Dinner tonight? ", options: ["Pizza", " ", "Pasta", "Tacos"]))
        XCTAssertEqual(poll.body, "📊 Dinner tonight?\n1️⃣ Pizza\n2️⃣ Pasta\n3️⃣ Tacos")
        XCTAssertEqual(FamilyPoll.parse(poll.body), poll)
    }

    func testOnlyARealPollParses() {
        XCTAssertNil(FamilyPoll.parse("Dinner at 7?"))
        XCTAssertNil(FamilyPoll.parse("📊 Dinner?\n1️⃣ Pizza"), "one option is not a choice")
        XCTAssertNil(FamilyPoll.parse("📊 Dinner?\n1️⃣ Pizza\n3️⃣ Pasta"), "options out of order")
        XCTAssertNil(FamilyPoll.make(question: "", options: ["a", "b"]))
        XCTAssertNil(FamilyPoll.make(question: "Q", options: ["a", "b", "c", "d", "e"]))
    }

    func testEachPersonsNewestVoteIsTheOneThatCounts() throws {
        let poll = try XCTUnwrap(FamilyPoll.parse("📊 Film?\n1️⃣ Up\n2️⃣ Cars"))
        let votes = [
            FamilyPoll.Vote(voter: "sam", name: "Sam", body: "1️⃣", at: ten, mine: false),
            FamilyPoll.Vote(voter: "kit", name: "Kit", body: "2️⃣", at: ten.addingTimeInterval(10), mine: false),
            FamilyPoll.Vote(voter: "me", name: "Alex", body: "1️⃣", at: ten.addingTimeInterval(20), mine: true),
            // Sam changed their mind.
            FamilyPoll.Vote(voter: "sam", name: "Sam", body: "2️⃣", at: ten.addingTimeInterval(30), mine: false),
            FamilyPoll.Vote(voter: "kit", name: "Kit", body: "Nice", at: ten.addingTimeInterval(40), mine: false),
            FamilyPoll.Vote(voter: "kit", name: "Kit", body: "4️⃣", at: ten.addingTimeInterval(50), mine: false),
        ]
        let counts = poll.tally(votes)
        XCTAssertEqual(counts.map(\.votes), [1, 2])
        XCTAssertEqual(counts[0].names, ["Alex"])
        XCTAssertTrue(counts[0].mine)
        XCTAssertEqual(counts[1].names, ["Kit", "Sam"])
        XCTAssertFalse(counts[1].mine)
        XCTAssertNil(poll.option(of: "3️⃣"), "a marker past the last option is not a vote")
    }

    // MARK: - Unread

    func testUnreadIsOtherPeoplesLinesSinceLastRead() {
        let items: [(at: Date?, mine: Bool)] = [
            (ten.addingTimeInterval(-600), false), (ten.addingTimeInterval(60), false),
            (ten.addingTimeInterval(120), true), (nil, false), (ten.addingTimeInterval(180), false),
        ]
        XCTAssertEqual(FamilyMessageTools.unread(items, since: ten), 2)
        XCTAssertEqual(FamilyMessageTools.unread(items, since: nil), 3, "never opened: everyone else's dated lines")
    }

    // MARK: - Mentions

    func testTheMentionBeingTyped() {
        XCTAssertEqual(FamilyMessageTools.mentionQuery("Pick up @Sa"), "Sa")
        XCTAssertEqual(FamilyMessageTools.mentionQuery("@"), "")
        XCTAssertNil(FamilyMessageTools.mentionQuery("mail me@home"), "an @ inside a word")
        XCTAssertNil(FamilyMessageTools.mentionQuery("@Sam is home"), "the mention is finished")
        XCTAssertNil(FamilyMessageTools.mentionQuery("No mention"))
        XCTAssertEqual(FamilyMessageTools.complete("Pick up @Sa", with: "Sam"), "Pick up @Sam ")
    }

    func testCandidatesStartWithWhatWasTyped() {
        let names = ["Robin", "Sam", "Rosa", "Sam", "Kit"]
        XCTAssertEqual(FamilyMessageTools.mentionCandidates("ro", names: names), ["Robin", "Rosa"])
        XCTAssertEqual(FamilyMessageTools.mentionCandidates("", names: names), ["Robin", "Sam", "Rosa", "Kit"])
        XCTAssertEqual(FamilyMessageTools.mentionCandidates("i", names: names), ["Robin", "Kit"])
    }

    func testAMentionIsTheWholeName() {
        XCTAssertTrue(FamilyMessageTools.mentions("Can @sam get milk?", name: "Sam"))
        XCTAssertTrue(FamilyMessageTools.mentions("@Sam", name: "Sam"))
        XCTAssertFalse(FamilyMessageTools.mentions("@Samantha is here", name: "Sam"))
        XCTAssertTrue(FamilyMessageTools.mentions("@Samantha and @Sam!", name: "Sam"))
        XCTAssertFalse(FamilyMessageTools.mentions("Sam, milk?", name: "Sam"), "no @, no mention")
    }

    // MARK: - Days

    func testDayTitles() {
        XCTAssertEqual(FamilyMessageTools.dayTitle(ten.addingTimeInterval(-3600), now: ten, calendar: london), "Today")
        XCTAssertEqual(FamilyMessageTools.dayTitle(ten.addingTimeInterval(-86_400), now: ten, calendar: london), "Yesterday")
        XCTAssertEqual(FamilyMessageTools.dayTitle(ten.addingTimeInterval(-3 * 86_400), now: ten, calendar: london), "Saturday")
        XCTAssertEqual(FamilyMessageTools.dayTitle(ten.addingTimeInterval(-10 * 86_400), now: ten, calendar: london), "Sat 17 Oct")
    }

    // MARK: - Search

    func testSearchNeedsEveryWordSomewhere() {
        let texts = ["Robin", "Pizza tonight?", "Kit: Pepperoni please"]
        XCTAssertTrue(FamilyMessageTools.matches("", in: texts))
        XCTAssertTrue(FamilyMessageTools.matches("pizza robin", in: texts))
        XCTAssertTrue(FamilyMessageTools.matches("PEPPERONI", in: texts))
        XCTAssertFalse(FamilyMessageTools.matches("pizza sam", in: texts))
        XCTAssertTrue(FamilyMessageTools.matches("cafe", in: ["Café at 3"]), "accents do not matter")
    }

    // MARK: - Where I am

    func testWhereIAm() {
        XCTAssertEqual(FamilyMessageTools.whereIAm(atHome: true, place: "Home", km: 0), "I'm at home")
        XCTAssertEqual(FamilyMessageTools.whereIAm(atHome: false, place: "School", km: 2), "I'm at School")
        XCTAssertEqual(FamilyMessageTools.whereIAm(atHome: false, place: nil, km: 3.24), "I'm 3.2 km from home")
        XCTAssertEqual(FamilyMessageTools.whereIAm(atHome: false, place: nil, km: 0.43), "I'm 450 m from home")
        XCTAssertNil(FamilyMessageTools.whereIAm(atHome: false, place: nil, km: nil))
    }

    // MARK: - The counter and reminders

    func testTheCounterAppearsNearTheLimit() {
        XCTAssertNil(FamilyMessageTools.remaining(String(repeating: "a", count: 399)))
        XCTAssertEqual(FamilyMessageTools.remaining(String(repeating: "a", count: 450)), 50)
        XCTAssertEqual(FamilyMessageTools.remaining(String(repeating: "a", count: 510)), -10)
    }

    func testReminderTimes() {
        XCTAssertEqual(FamilyMessageTools.remindAt(.hour, now: ten, calendar: london), ten.addingTimeInterval(3600))
        XCTAssertEqual(FamilyMessageTools.remindAt(.evening, now: ten, calendar: london), ten.addingTimeInterval(8 * 3600))
        let late = ten.addingTimeInterval(8 * 3600 - 600) // 17:50
        XCTAssertEqual(FamilyMessageTools.remindAt(.evening, now: late, calendar: london), ten.addingTimeInterval(32 * 3600),
                       "ten minutes before six is tomorrow's six")
        XCTAssertEqual(FamilyMessageTools.remindAt(.morning, now: ten, calendar: london), ten.addingTimeInterval(22 * 3600))
    }

    // MARK: - Bat phone

    func testBatPhoneSaysWhatItKnows() {
        XCTAssertEqual(BatPhoneWords.facts(place: "Elton Parade, Darlington", battery: 0.234, drive: "14 min drive from you"),
                       ["At Elton Parade, Darlington", "Battery 23%", "14 min drive from you"])
        XCTAssertEqual(BatPhoneWords.facts(place: "  ", battery: nil, drive: nil), [])
        XCTAssertEqual(BatPhoneWords.facts(place: nil, battery: 1.2, drive: nil), [], "a level iOS never gives is dropped")
    }

    func testBatPhoneDriveWords() {
        XCTAssertEqual(BatPhoneWords.drive(seconds: 13 * 60 + 5), "14 min drive from you")
        XCTAssertEqual(BatPhoneWords.drive(seconds: 0), "1 min drive from you")
        XCTAssertEqual(BatPhoneWords.drive(seconds: 95 * 60), "1 h 35 drive from you")
        XCTAssertNil(BatPhoneWords.drive(seconds: nil))
        XCTAssertNil(BatPhoneWords.drive(seconds: .infinity))
    }

    func testQuickLinesAreShortAndDistinct() {
        XCTAssertEqual(Set(FamilyMessageTools.quickSend).count, FamilyMessageTools.quickSend.count)
        XCTAssertTrue(FamilyMessageTools.quickSend.allSatisfy { !$0.isEmpty && $0.count <= 24 })
    }
}
