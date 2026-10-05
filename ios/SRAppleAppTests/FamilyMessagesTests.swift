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

    // MARK: - One list with jkai's threads

    private func thread(_ id: String, updated: String?) -> Conversation {
        Conversation(id: id, title: id, source: "web", pinned: false, messageCount: 2, modelProvider: nil,
                     modelId: nil, preview: nil, createdAt: updated, updatedAt: updated)
    }

    func testTheFamilyChatSitsAmongThreadsByWhenItLastMoved() {
        let threads = [thread("a", updated: "2026-10-05T12:00:00Z"), thread("b", updated: "2026-10-05T09:00:00Z")]
        let at = ISO8601DateFormatter().date(from: "2026-10-05T10:00:00Z")
        XCTAssertEqual(FamilyThreadPlacement.merge(threads, family: at).map(\.id), ["thread-a", "family", "thread-b"])
        // Never moved: last. No family chat at all: not there.
        XCTAssertEqual(FamilyThreadPlacement.merge(threads, family: .distantPast).map(\.id), ["thread-a", "thread-b", "family"])
        XCTAssertEqual(FamilyThreadPlacement.merge(threads, family: nil).map(\.id), ["thread-a", "thread-b"])
        XCTAssertEqual(FamilyThreadPlacement.merge([], family: .distantPast).map(\.id), ["family"])
    }
}
