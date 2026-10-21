import XCTest
@testable import SRAppleApp

/// msg family as threads: who started it, who answered, and when it last moved.
final class FamilyThreadTests: XCTestCase {
    private func reply(_ id: String, from: String, _ body: String, at: String, mine: Bool = false) -> FamilyMessageReply {
        FamilyMessageReply(id: id, fromId: "f_\(from)", fromName: from.capitalized, fromSubject: from, mine: mine,
                           body: body, reaction: FamilyMessages.reactions.contains(body), at: at)
    }

    private var message: FamilyMessage {
        FamilyMessage(id: "m1", fromId: "f_sam", fromName: "Sam", fromSubject: "sam", mine: true,
                      body: "Pizza tonight?", at: "2026-10-21T17:00:00Z",
                      replies: [
                          reply("r1", from: "alex", "❤️", at: "2026-10-21T17:05:00Z"),
                          reply("r2", from: "robin", "Pepperoni please!", at: "2026-10-21T17:10:00Z"),
                          reply("r3", from: "sam", "Pepperoni it is.", at: "2026-10-21T17:12:00Z", mine: true),
                          reply("r4", from: "robin", "And garlic bread", at: "2026-10-21T17:20:00Z"),
                      ])
    }

    func testTheSendersOwnFollowUpStaysInLineAndEveryoneElseIsIndented() {
        let m = message
        XCTAssertEqual(m.textReplies.map { m.isFromSender($0) }, [false, true, false])
    }

    func testWithoutIdsTheSenderIsKnownByMine() {
        let m = FamilyMessage(id: "m", fromId: "", fromName: "You", mine: true, body: "x", at: "2026-10-21T17:00:00Z")
        let mineReply = FamilyMessageReply(id: "r", fromId: "", fromName: "You", mine: true, body: "y", reaction: false, at: "")
        let theirs = FamilyMessageReply(id: "s", fromId: "", fromName: "Kit", mine: false, body: "z", reaction: false, at: "")
        XCTAssertTrue(m.isFromSender(mineReply))
        XCTAssertFalse(m.isFromSender(theirs))
    }

    func testRepliersAreEachPersonOnceInTheOrderTheyFirstAnsweredInWords() {
        XCTAssertEqual(message.repliers.map(\.fromName), ["Robin", "Sam"])
    }

    func testAThreadLastMovedAtItsNewestReply() {
        XCTAssertEqual(message.lastActivity, parseTimestamp("2026-10-21T17:20:00Z"))
        let quiet = FamilyMessage(id: "q", fromId: "f_kit", fromName: "Kit", mine: false, body: "x", at: "2026-10-21T09:00:00Z")
        XCTAssertEqual(quiet.lastActivity, parseTimestamp("2026-10-21T09:00:00Z"))
    }

    func testTheSendersSubjectDecodesAndAnOlderSiteWithoutItStillReads() throws {
        let json = """
        {"me":{"id":"f_sam"},"messages":[
          {"id":"m1","fromId":"f_sam","fromName":"Sam","fromSubject":"sam","mine":true,"body":"Hi","at":"2026-10-21T17:00:00Z",
           "replies":[{"id":"r1","fromId":"f_kit","fromName":"Kit","mine":false,"body":"Hello","at":"2026-10-21T17:01:00Z"}]}
        ]}
        """
        let feed = try JSONDecoder().decode(FamilyMessagesFeed.self, from: Data(json.utf8))
        XCTAssertEqual(feed.messages.first?.fromSubject, "sam")
        XCTAssertNil(feed.messages.first?.replies.first?.fromSubject)
    }

    func testANotificationOpensItsThreadAboveTheList() {
        XCTAssertEqual(FamilyThreadRef(id: "m1"), FamilyThreadRef(id: "m1"))
        XCTAssertEqual(FamilyPage.from(category: "family-msg-reply", userInfo: ["messageId": "m1"]), .messages)
    }
}
