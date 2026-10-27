import XCTest
@testable import SRAppleApp

/// msg family's widgets: the snapshot the app leaves on the shelf, the feed a
/// widget reads for itself, and the bat phone's link.
///
/// Foundation only: `scripts/home-check.sh` runs this file on Linux too.
final class FamilyMessagesWidgetTests: XCTestCase {

    private let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    /// Tuesday 27 October 2026, 10:00 in London (GMT).
    private let ten = Date(timeIntervalSince1970: 1_793_095_200)

    private func iso(_ minutesAgo: Double) -> String {
        ISO8601DateFormatter().string(from: ten.addingTimeInterval(-minutesAgo * 60))
    }

    private typealias Message = FamilyMessagesWidgetFeed.Message
    private typealias Reply = FamilyMessagesWidgetFeed.Reply

    private var feed: [Message] {
        [
            Message(id: "m1", fromName: "Robin Lee", mine: false, body: "Pizza tonight?", at: iso(60), replies: [
                Reply(fromName: "Kit", mine: false, body: "Yes!", reaction: false, at: iso(50)),
                Reply(fromName: "Sam", mine: true, body: "👍", reaction: true, at: iso(5)),
            ]),
            Message(id: "m2", fromName: "Kit", mine: false, body: "Bring my kit", at: iso(20)),
            Message(id: "m3", fromName: "Sam", mine: true, body: "Home by six", at: iso(120)),
        ]
    }

    // MARK: - Snapshot

    func testThreadsAreNewestActivityFirst() {
        let snapshot = FamilyMessagesWidget.snapshot(feed, readAt: nil, now: ten)
        XCTAssertEqual(snapshot.threads.map(\.id), ["m1", "m2", "m3"], "a reply five minutes ago lifts m1 to the top")
        XCTAssertEqual(snapshot.savedAt, ten)
    }

    func testAThreadRowCarriesWhoRepliesAndTheNewestAnswer() throws {
        let row = try XCTUnwrap(FamilyMessagesWidget.snapshot(feed, readAt: nil, now: ten).threads.first)
        XCTAssertEqual(row.who, "Robin")
        XCTAssertEqual(row.initials, "RL")
        XCTAssertEqual(row.text, "Pizza tonight?")
        XCTAssertEqual(row.replies, 1)
        XCTAssertEqual(row.reactions, 1)
        XCTAssertEqual(row.latest, "You 👍")
        XCTAssertEqual(row.at, ten.addingTimeInterval(-5 * 60))
        XCTAssertFalse(row.mine)
    }

    func testMyOwnThreadSaysYou() throws {
        let row = try XCTUnwrap(FamilyMessagesWidget.snapshot(feed, readAt: nil, now: ten).threads.last)
        XCTAssertEqual(row.who, "You")
        XCTAssertTrue(row.mine)
        XCTAssertNil(row.latest)
        XCTAssertFalse(row.unread, "nothing in it from anybody else")
    }

    func testUnreadCountsOtherPeoplesLinesSinceTheLastRead() {
        // Never read: every line that is not mine — Robin, Kit's reply, Kit.
        XCTAssertEqual(FamilyMessagesWidget.snapshot(feed, readAt: nil, now: ten).unread, 3)
        // Read 30 minutes ago: only Kit's message, 20 minutes ago.
        let since = FamilyMessagesWidget.snapshot(feed, readAt: ten.addingTimeInterval(-30 * 60), now: ten)
        XCTAssertEqual(since.unread, 1)
        XCTAssertEqual(since.threads.map(\.unread), [false, true, false])
        // Read now: nothing.
        XCTAssertEqual(FamilyMessagesWidget.snapshot(feed, readAt: ten, now: ten).unread, 0)
    }

    func testNewestSenderIsTheNewestLineThatIsNotMine() {
        let snapshot = FamilyMessagesWidget.snapshot(feed, readAt: nil, now: ten)
        XCTAssertEqual(snapshot.newestFrom, "Kit")
        XCTAssertEqual(snapshot.newestInitials, "K")
        XCTAssertNil(FamilyMessagesWidget.snapshot([feed[2]], readAt: nil, now: ten).newestFrom, "only mine")
    }

    func testKeepsAtMostFive() {
        let many = (0..<9).map { Message(id: "m\($0)", fromName: "Kit", mine: false, body: "\($0)", at: iso(Double($0))) }
        let snapshot = FamilyMessagesWidget.snapshot(many, readAt: nil, now: ten)
        XCTAssertEqual(snapshot.threads.map(\.id), ["m0", "m1", "m2", "m3", "m4"])
        XCTAssertEqual(snapshot.unread, 9, "the count is the whole feed's, not the rows'")
        XCTAssertTrue(FamilyMessagesWidget.snapshot(many, readAt: nil, now: ten, keep: 0).threads.isEmpty)
    }

    func testSameContentIgnoresWhenItWasSaved() {
        let a = FamilyMessagesWidget.snapshot(feed, readAt: nil, now: ten)
        var b = a
        b.savedAt = ten.addingTimeInterval(600)
        XCTAssertTrue(a.sameContent(as: b))
        b.unread = 0
        XCTAssertFalse(a.sameContent(as: b))
        XCTAssertFalse(a.sameContent(as: nil))
    }

    func testTheSnapshotRoundTripsThroughTheShelf() throws {
        let snapshot = FamilyMessagesWidget.snapshot(feed, readAt: ten, now: ten)
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(FamilyMessagesSnapshot.self, from: data), snapshot)
    }

    // MARK: - Words

    func testInitials() {
        XCTAssertEqual(FamilyMessagesWidget.initials("Sam Lee"), "SL")
        XCTAssertEqual(FamilyMessagesWidget.initials("  robin  "), "R")
        XCTAssertEqual(FamilyMessagesWidget.initials("Ana María López"), "AM")
        XCTAssertEqual(FamilyMessagesWidget.initials(""), "?")
    }

    func testShortFlattensAndCutsAtAWord() {
        XCTAssertEqual(FamilyMessagesWidget.short("  Home\n\nby   six "), "Home by six")
        XCTAssertEqual(FamilyMessagesWidget.short("one two three four", max: 10), "one two…")
        XCTAssertEqual(FamilyMessagesWidget.short("abcdefghijklmnop", max: 10), "abcdefghij…")
        XCTAssertEqual(FamilyMessagesWidget.short("📊 Dinner tonight?\n1️⃣ Pizza\n2️⃣ Pasta"), "📊 Dinner tonight?", "a poll is its question")
    }

    func testLatestLine() {
        XCTAssertEqual(FamilyMessagesWidget.latestLine(Reply(fromName: "Robin Lee", mine: false, body: "On my\nway", reaction: false, at: "")),
                       "Robin: On my way")
        XCTAssertEqual(FamilyMessagesWidget.latestLine(Reply(fromName: "Kit", mine: false, body: "👍", reaction: true, at: "")), "Kit 👍")
        XCTAssertEqual(FamilyMessagesWidget.latestLine(Reply(fromName: "Sam", mine: true, body: "ok", reaction: false, at: "")), "You: ok")
    }

    func testWhen() {
        XCTAssertEqual(FamilyMessagesWidget.when(nil, now: ten), "")
        XCTAssertEqual(FamilyMessagesWidget.when(ten.addingTimeInterval(-20), now: ten), "now")
        XCTAssertEqual(FamilyMessagesWidget.when(ten.addingTimeInterval(-5 * 60), now: ten), "5m")
        XCTAssertEqual(FamilyMessagesWidget.when(ten.addingTimeInterval(-3 * 3600), now: ten), "3h")
        XCTAssertEqual(FamilyMessagesWidget.when(ten.addingTimeInterval(-2 * 86_400), now: ten, calendar: london), "Sun")
        XCTAssertEqual(FamilyMessagesWidget.when(ten.addingTimeInterval(-10 * 86_400), now: ten, calendar: london), "17 Oct")
    }

    func testPhrases() {
        XCTAssertNil(FamilyMessagesWidget.unreadPhrase(0))
        XCTAssertEqual(FamilyMessagesWidget.unreadPhrase(3), "3 unread")
        XCTAssertNil(FamilyMessagesWidget.repliesPhrase(0))
        XCTAssertEqual(FamilyMessagesWidget.repliesPhrase(1), "1 reply")
        XCTAssertEqual(FamilyMessagesWidget.repliesPhrase(4), "4 replies")
    }

    func testTimestampsWithAndWithoutFractions() {
        XCTAssertEqual(FamilyMessagesWidget.date("2026-10-27T10:00:00Z"), ten)
        XCTAssertEqual(FamilyMessagesWidget.date("2026-10-27T10:00:00.000Z"), ten)
        XCTAssertNil(FamilyMessagesWidget.date(""))
        XCTAssertNil(FamilyMessagesWidget.date("yesterday"))
    }

    // MARK: - The feed off the wire

    func testTheFeedDecodesLenientlyAndDropsOnlyABadMessage() throws {
        let json = """
        {"me":{"id":"f_sam"},"messages":[
          {"id":"m1","fromName":"Robin","body":"Hi","at":"2026-10-27T09:00:00Z",
           "replies":[{"fromName":"Kit","body":"👍","at":"2026-10-27T09:01:00Z"},{"body":"ok"}]},
          {"fromName":"No id"},
          {"id":"m2"}
        ]}
        """
        let decoded = try JSONDecoder().decode(FamilyMessagesWidgetFeed.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.messages.map(\.id), ["m1", "m2"])
        XCTAssertEqual(decoded.messages[0].replies.map(\.reaction), [true, false], "a lone quick-set emoji is a reaction")
        XCTAssertEqual(decoded.messages[0].replies[1].fromName, "Someone")
        XCTAssertEqual(decoded.messages[1].body, "")
        XCTAssertFalse(decoded.messages[1].mine)
    }

    func testAnEmptyFeedIsAnEmptySnapshot() throws {
        let decoded = try JSONDecoder().decode(FamilyMessagesWidgetFeed.self, from: Data("{}".utf8))
        let snapshot = FamilyMessagesWidget.snapshot(decoded.messages, readAt: nil, now: ten)
        XCTAssertEqual(snapshot.unread, 0)
        XCTAssertTrue(snapshot.threads.isEmpty)
        XCTAssertNil(snapshot.newestFrom)
    }

    // MARK: - Samples and the bat phone

    func testTheSamplesFillEveryWidget() {
        let sample = FamilyMessagesWidgetSamples.snapshot(now: ten)
        XCTAssertEqual(sample.threads.count, 5)
        XCTAssertGreaterThan(sample.unread, 0)
        XCTAssertNotNil(sample.newestFrom)
    }

    func testBatPhoneLink() {
        XCTAssertEqual(BatPhoneURL.url.absoluteString, "sr://batphone")
        XCTAssertTrue(BatPhoneURL.matches(URL(string: "sr://batphone")!))
        XCTAssertTrue(BatPhoneURL.matches(URL(string: "SR://BatPhone")!))
        XCTAssertFalse(BatPhoneURL.matches(URL(string: "sr://family/messages")!))
        XCTAssertFalse(BatPhoneURL.matches(URL(string: "https://batphone")!))
    }
}
