import XCTest
@testable import SRAppleApp

/// "msg family": the wire (SR-Main's own shape), the rules the screen applies,
/// and the demo session that answers for it.
final class FamilyMessagesTests: XCTestCase {
    private let clock = SRDemoFixtures.DemoClock(now: Date(timeIntervalSince1970: 1_791_200_000))

    override func setUp() {
        super.setUp()
        FamilyMessagesDemo.shared.reset()
    }

    func testTheSitesFeedDecodesAndTalliesEmoji() throws {
        let json = #"""
        {"me":{"id":"f_kid"},"reactions":["👍","❤️"],"messages":[{"id":"m1","fromId":"f_kid","fromName":"Kid",
        "mine":true,"body":"Dinner?","at":"2026-10-05T17:00:00.000Z","pushed":2,"recipients":2,"replies":[
        {"id":"r1","fromId":"f_owner","fromName":"John","mine":false,"body":"👍","reaction":true,"at":"2026-10-05T17:01:00.000Z"},
        {"id":"r2","fromId":"f_karen","fromName":"Karen","mine":false,"body":"Yes","reaction":false,"at":"2026-10-05T17:02:00.000Z"},
        {"id":"r3","fromId":"f_kid","fromName":"Kid","mine":true,"body":"👍","reaction":true,"at":"2026-10-05T17:03:00.000Z"}]}]}
        """#
        let feed = try JSONDecoder().decode(FamilyMessagesFeed.self, from: Data(json.utf8))
        XCTAssertEqual(feed.reactions, ["👍", "❤️"])
        let message = try XCTUnwrap(feed.messages.first)
        XCTAssertEqual(message.tally, [FamilyMessages.Tally(emoji: "👍", count: 2, mine: true, names: ["John", "Kid"])])
        XCTAssertEqual(message.textReplies.map(\.body), ["Yes"])
    }

    func testAMissingFieldCostsThatFieldOnly() throws {
        let feed = try JSONDecoder().decode(FamilyMessagesFeed.self, from: Data(#"{"messages":[{"id":"m1"}]}"#.utf8))
        XCTAssertEqual(feed.reactions, FamilyMessages.reactions)
        XCTAssertEqual(feed.messages.first?.fromName, "Someone")
        XCTAssertEqual(feed.messages.first?.replies, [])
    }

    func testOnlyTrimmedNonEmptyTextIsSent() {
        XCTAssertEqual(FamilyMessages.sendable("  On my way \n"), "On my way")
        XCTAssertNil(FamilyMessages.sendable("   "))
        XCTAssertNil(FamilyMessages.sendable(String(repeating: "x", count: FamilyMessages.bodyMax + 1)))
    }

    func testTheDemoKeepsWhatIsSentAndRepliedThisSession() throws {
        func feed() throws -> FamilyMessagesFeed {
            let raw = try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/family/messages", query: [:], body: nil, clock: clock))
            return try JSONDecoder().decode(FamilyMessagesFeed.self, from: Data(raw.utf8))
        }
        let before = try feed()
        XCTAssertFalse(before.messages.isEmpty)

        XCTAssertNotNil(SRDemoFixtures.route(method: "POST", path: "/api/native/family/messages", query: [:],
                                             body: Data(#"{"body":"Home soon"}"#.utf8), clock: clock))
        XCTAssertNotNil(SRDemoFixtures.route(method: "POST", path: "/api/native/family/messages/demo-msg-2/replies", query: [:],
                                             body: Data(#"{"body":"❤️"}"#.utf8), clock: clock))
        XCTAssertNil(SRDemoFixtures.route(method: "POST", path: "/api/native/family/messages", query: [:],
                                          body: Data(#"{"body":"  "}"#.utf8), clock: clock))

        let after = try feed()
        XCTAssertEqual(after.messages.first?.body, "Home soon")
        XCTAssertEqual(after.messages.first?.mine, true)
        let alex = try XCTUnwrap(after.messages.first { $0.id == "demo-msg-2" })
        XCTAssertTrue(alex.tally.contains { $0.emoji == "❤️" && $0.mine })
    }

    // MARK: - Read as one conversation

    /// The demo's threads as msg family draws them: emoji and poll votes are
    /// counted, not lines; a reply quotes the message it answers.
    @MainActor
    func testTheDemoReadsAsOneConversation() throws {
        let raw = try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/family/messages", query: [:], body: nil, clock: clock))
        let feed = try JSONDecoder().decode(FamilyMessagesFeed.self, from: Data(raw.utf8))
        let lines = FamilyChatStream.lines(feed.messages.reversed().map(FamilyMessagesStore.streamed), now: clock.now)
        XCTAssertFalse(lines.contains { FamilyMessages.reactions.contains($0.body) }, "emoji are counted on their message")
        XCTAssertFalse(lines.contains { $0.body == "2️⃣" }, "a vote is a bar on the poll, not a line")
        XCTAssertEqual(lines.first?.id, "demo-msg-3", "oldest first: yesterday's poll")
        let milk = try XCTUnwrap(lines.first { $0.id == "demo-rep-8" })
        XCTAssertEqual(milk.thread, "demo-msg-2")
        XCTAssertEqual(milk.quote?.name, "Alex")
        XCTAssertEqual(milk.subject, "robin", "the circle's colour comes with the line")
        let times = lines.compactMap(\.at)
        XCTAssertEqual(times, times.sorted(), "in time order")
    }

    /// The bat phone is a message now: it goes through msg family's own send.
    func testTheBatPhoneMessageIsSendable() {
        let body = BatPhoneWords.message(place: "Station Road, Anytown", battery: 0.07, lat: 51.5, lon: -0.12)
        XCTAssertEqual(FamilyMessages.sendable(body), body)
    }

    func testAMessageOrReplyIsDeletedAtItsOwnAddress() {
        XCTAssertEqual(FamilyMessages.itemPath("m1"), "api/native/family/messages/m1")
        XCTAssertEqual(FamilyMessages.repliesPath("m1"), "api/native/family/messages/m1/replies")
        // An id can never reach a different route.
        XCTAssertEqual(FamilyMessages.itemPath("a/b"), "api/native/family/messages/a%2Fb")
    }
}
