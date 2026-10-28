import XCTest
@testable import SRAppleApp

/// "Quick answer from jkai": one read-only turn, said aloud, never hanging.
final class QuickAnswerTests: XCTestCase {

    /// A clock that moves only when the code under test sleeps.
    private final class Clock {
        var now = Date(timeIntervalSince1970: 0)
        var slept: [TimeInterval] = []
        func sleep(_ s: TimeInterval) { slept.append(s); now = now.addingTimeInterval(s) }
    }

    private struct Boom: Error {}

    func testTheTurnIsHandsFreeAndNamesThePlaceholderThread() throws {
        let request = QuickAnswer.request(question: "  What's on today? ", surface: "siri")
        XCTAssertEqual(request.message, "What's on today?")
        XCTAssertEqual(request.conversationId, "quick-answers")
        XCTAssertNil(request.attachmentIds)
        XCTAssertEqual(request.envelope?.surface, "siri")
        XCTAssertEqual(request.envelope?.capabilities, [])
        let wire = try JSONSerialization.jsonObject(with: request.body()) as? [String: Any]
        XCTAssertEqual((wire?["envelope"] as? [String: Any])?["surface"] as? String, "siri")
        XCTAssertNotNil(wire?["requestId"] as? String)
    }

    func testTheWatchSaysWatchAndAnythingElseIsSiri() {
        XCTAssertEqual(QuickAnswer.request(question: "q", surface: "watch").envelope?.surface, "watch")
        XCTAssertEqual(QuickAnswer.request(question: "q", surface: "ios").envelope?.surface, "siri")
    }

    func testPollReading() {
        let done = Data(#"{"status":"done","result":{"message":"**Two** things."}}"#.utf8)
        XCTAssertEqual(QuickAnswer.readPoll(status: 200, body: done), .done("**Two** things."))
        XCTAssertEqual(QuickAnswer.readPoll(status: 200, body: Data(#"{"status":"running"}"#.utf8)), .running)
        XCTAssertEqual(QuickAnswer.readPoll(status: 200, body: Data(#"{"status":"error","error":"nope"}"#.utf8)), .failed("nope"))
        XCTAssertEqual(QuickAnswer.readPoll(status: 404, body: Data()), .gone)
        XCTAssertEqual(QuickAnswer.readPoll(status: 500, body: Data()), .failed(nil))
    }

    func testAnAnswerIsSpokenWithoutMarkdown() async {
        let clock = Clock()
        var polls = 0
        let outcome = await QuickAnswer.run(
            now: { clock.now }, sleep: { clock.sleep($0) },
            post: { .started(jobId: "j1") },
            poll: { job in
                XCTAssertEqual(job, "j1")
                polls += 1
                return polls < 3 ? .running : .done("You have **two** meetings.")
            }
        )
        XCTAssertEqual(outcome, .answer("You have **two** meetings."))
        XCTAssertEqual(QuickAnswer.spoken(outcome), "You have two meetings.")
        XCTAssertEqual(polls, 3)
    }

    func testASlowTurnSaysItIsStillWorkingWithinTheBudget() async {
        let clock = Clock()
        let outcome = await QuickAnswer.run(
            now: { clock.now }, sleep: { clock.sleep($0) },
            post: { .started(jobId: "j1") },
            poll: { _ in .running }
        )
        XCTAssertEqual(outcome, .stillWorking)
        XCTAssertLessThanOrEqual(clock.now.timeIntervalSince1970, QuickAnswer.budget + QuickAnswer.pollInterval)
        XCTAssertEqual(QuickAnswer.spoken(outcome), QuickAnswer.stillWorking)
    }

    func testARefusalIsSaidPlainly() async {
        let clock = Clock()
        let outcome = await QuickAnswer.run(
            now: { clock.now }, sleep: { clock.sleep($0) },
            post: { .refused("Too many chat requests") },
            poll: { _ in XCTFail("no job to poll"); return .running }
        )
        XCTAssertEqual(QuickAnswer.spoken(outcome), "Too many chat requests")
    }

    func testAFailedTurnAndAVanishedJobAreNotSilent() async {
        let clock = Clock()
        let failed = await QuickAnswer.run(now: { clock.now }, sleep: { clock.sleep($0) },
                                           post: { .started(jobId: "j") }, poll: { _ in .failed(nil) })
        XCTAssertEqual(QuickAnswer.spoken(failed), "That didn't work.")
        let gone = await QuickAnswer.run(now: { clock.now }, sleep: { clock.sleep($0) },
                                         post: { .started(jobId: "j") }, poll: { _ in .gone })
        XCTAssertEqual(gone, .stillWorking)
        XCTAssertEqual(QuickAnswer.spoken(.answer("")), QuickAnswer.emptyAnswer)
    }

    func testRetriesTheSameSendThenGivesUp() async {
        let clock = Clock()
        var posts = 0
        let outcome = await QuickAnswer.run(
            now: { clock.now }, sleep: { clock.sleep($0) },
            post: { posts += 1; return .unavailable("The site is not answering just now.") },
            poll: { _ in .running }
        )
        XCTAssertEqual(posts, 1 + TurnStart.retryDelays.count)
        XCTAssertEqual(outcome, .refused("The site is not answering just now."))

        posts = 0
        let thrown = await QuickAnswer.run(
            now: { clock.now }, sleep: { clock.sleep($0) },
            post: { posts += 1; if posts == 1 { throw Boom() }; return .started(jobId: "j") },
            poll: { _ in .done("Yes.") }
        )
        XCTAssertEqual(thrown, .answer("Yes."))
    }

    func testPendingWaitsThenStopsAsking() async {
        let clock = Clock()
        var posts = 0
        let outcome = await QuickAnswer.run(
            now: { clock.now }, sleep: { clock.sleep($0) },
            post: { posts += 1; return .pending(retryAfter: 2) },
            poll: { _ in .running }
        )
        XCTAssertEqual(outcome, .stillWorking)
        XCTAssertEqual(posts, TurnStart.pendingTries + 1)
    }
}
