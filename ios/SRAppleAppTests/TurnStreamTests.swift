import XCTest
@testable import SRAppleApp

/// A chat turn across a bad network: the send, the stream, the reconnect.
final class TurnStreamTests: XCTestCase {

    // MARK: - Drop and reconnect, without doubled text

    /// One frame as the server sends it: `id: <seq>` and a token.
    private struct Frame { let id: Int?; let type: String; let delta: String }

    private let turn: [Frame] = [
        Frame(id: nil, type: "connected", delta: ""),
        Frame(id: 0, type: "status", delta: ""),
        Frame(id: 1, type: "token", delta: "The "),
        Frame(id: 2, type: "token", delta: "flight "),
        Frame(id: 3, type: "token", delta: "leaves "),
        Frame(id: 4, type: "token", delta: "at "),
        Frame(id: 5, type: "token", delta: "09:40."),
        Frame(id: 6, type: "done", delta: ""),
    ]

    /// Feed frames through the resume point and build the bubble the way
    /// `ChatStore` does: tokens APPEND.
    private func play(_ frames: [Frame], into text: inout String, resume: inout TurnStreamResume) -> Bool {
        var done = false
        for frame in frames where resume.accept(frame.id) {
            if frame.type == "token" { text += frame.delta }
            if frame.type == "done" { done = true }
        }
        return done
    }

    func testADroppedStreamResumesWithoutDoublingTheText() {
        var resume = TurnStreamResume()
        var text = ""
        // The first connection dies after "flight ".
        XCTAssertFalse(play(Array(turn[0...3]), into: &text, resume: &resume))
        XCTAssertEqual(resume.lastEventId, 2)
        XCTAssertEqual(resume.next(after: .network), .reconnect(after: 1))
        // The reconnect sends Last-Event-ID: 2. A careless proxy or an older
        // server replays from the start anyway: the resume point drops it.
        let replay = [Frame(id: nil, type: "connected", delta: "")] + turn[1...]
        XCTAssertTrue(play(Array(replay), into: &text, resume: &resume))
        XCTAssertEqual(text, "The flight leaves at 09:40.")
    }

    func testTheServersOwnReplayFromTheResumePointIsTakenAsIs() {
        var resume = TurnStreamResume()
        var text = ""
        _ = play(Array(turn[0...2]), into: &text, resume: &resume)
        _ = resume.next(after: .closedEarly)
        // What the server does with `Last-Event-ID: 1`: seq 2 onwards.
        XCTAssertTrue(play([Frame(id: nil, type: "connected", delta: "")] + turn.filter { ($0.id ?? -1) >= 2 }, into: &text, resume: &resume))
        XCTAssertEqual(text, "The flight leaves at 09:40.")
    }

    func testFramesWithoutAnIdAreAlwaysHandled() {
        var resume = TurnStreamResume(lastEventId: 9)
        XCTAssertTrue(resume.accept(nil))
        XCTAssertFalse(resume.accept(9))
        XCTAssertFalse(resume.accept(3))
        XCTAssertTrue(resume.accept(10))
        XCTAssertEqual(resume.lastEventId, 10)
    }

    // MARK: - Backoff

    func testReconnectsBackOffThenWait() {
        var resume = TurnStreamResume()
        var waits: [TimeInterval] = []
        while case .reconnect(let wait) = resume.next(after: .network) { waits.append(wait) }
        XCTAssertEqual(waits, TurnStreamResume.backoff)
        XCTAssertEqual(waits.reduce(0, +), 60, "a minute: twenty seconds of airplane mode is well inside it")
        XCTAssertEqual(resume.next(after: .network), .wait)
        // The app comes back to the foreground: a fresh count.
        resume.restart()
        XCTAssertEqual(resume.next(after: .closedEarly), .reconnect(after: 1))
    }

    /// The server answered and then sent nothing — not even the heartbeat a
    /// running job sends every five seconds. Once is a hiccup; twice in a row
    /// is a job that has finished, and the thread holds its answer.
    func testTwoSilentConnectionsInARowMeanTheTurnIsOver() {
        var resume = TurnStreamResume()
        XCTAssertEqual(resume.next(after: .silent), .reconnect(after: 1))
        XCTAssertEqual(resume.next(after: .silent), .reload)
        // A frame in between is a turn still running.
        var live = TurnStreamResume()
        XCTAssertEqual(live.next(after: .silent), .reconnect(after: 1))
        XCTAssertTrue(live.accept(4))
        XCTAssertEqual(live.next(after: .silent), .reconnect(after: 1))
        // So is a plain drop.
        XCTAssertEqual(live.next(after: .network), .reconnect(after: 2))
        XCTAssertEqual(live.next(after: .silent), .reconnect(after: 4))
    }

    func testProgressResetsTheCount() {
        var resume = TurnStreamResume()
        _ = resume.next(after: .network)
        _ = resume.next(after: .network)
        XCTAssertEqual(resume.attempts, 2)
        XCTAssertTrue(resume.accept(0))
        XCTAssertEqual(resume.attempts, 0)
        XCTAssertEqual(resume.next(after: .network), .reconnect(after: 1))
    }

    func testWhatEachFailureLeadsTo() {
        func next(_ failure: TurnStreamFailure) -> TurnStreamResume.Next {
            var resume = TurnStreamResume()
            return resume.next(after: failure)
        }
        XCTAssertEqual(next(.status(404)), .reload, "the job is gone: re-read the thread")
        XCTAssertEqual(next(.jobGone), .reload)
        XCTAssertEqual(next(.status(401)), .expired)
        XCTAssertEqual(next(.expired), .expired)
        XCTAssertEqual(next(.status(403)), .fail("403 from the server."))
        XCTAssertEqual(next(.status(502)), .reconnect(after: 1), "a release in progress")
        XCTAssertEqual(next(.status(429)), .reconnect(after: 1))
        XCTAssertEqual(next(.silent), .reconnect(after: 1), "one silent connection is a hiccup")
        XCTAssertEqual(next(.other("Bad")), .fail("Bad"))
    }

    func testTheServersJobNotFoundFrameMeansGone() {
        XCTAssertTrue(TurnStreamResume.isJobGone(type: "error", message: "job not found"))
        XCTAssertFalse(TurnStreamResume.isJobGone(type: "error", message: "That turn failed."))
        XCTAssertFalse(TurnStreamResume.isJobGone(type: "done", message: "job not found"))
    }

    func testNetworkErrorsAreTellable() {
        XCTAssertTrue(TurnStreamResume.isNetwork(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost))
        XCTAssertTrue(TurnStreamResume.isNetwork(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        XCTAssertTrue(TurnStreamResume.isNetwork(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
        XCTAssertFalse(TurnStreamResume.isNetwork(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        XCTAssertFalse(TurnStreamResume.isNetwork(domain: "SRAppleApp.SiteError", code: NSURLErrorTimedOut))
    }

    // MARK: - The send

    func testTheRequestIdIsWhatTheServerAccepts() throws {
        let id = TurnStart.newRequestId()
        // SR-Jkai-Core orchestrator/chat/+server.ts.
        XCTAssertNotNil(id.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: .regularExpression))
        XCTAssertNotEqual(id, TurnStart.newRequestId())
    }

    func testARetryIsTheSameRequestByteForByte() throws {
        let request = TurnRequest(message: "When do we land?", conversationId: "c1", attachmentIds: ["a2", "a1"])
        let first = try request.body()
        XCTAssertEqual(try request.body(), first)
        let json = try JSONSerialization.jsonObject(with: first) as? [String: Any]
        XCTAssertEqual(json?["requestId"] as? String, request.requestId)
        XCTAssertEqual(json?["conversationId"] as? String, "c1")
        XCTAssertEqual(json?["attachmentIds"] as? [String], ["a2", "a1"], "the order is the order picked")
        let bare = try JSONSerialization.jsonObject(with: try TurnRequest(message: "x", conversationId: "c", attachmentIds: nil).body()) as? [String: Any]
        XCTAssertNotNil(bare)
        XCTAssertNil(bare?["attachmentIds"], "no attachments: no key, as before")
    }

    /// The server's receipts (`onceChatRequest`) as a stand-in: the same id
    /// and the same body answer with the first job; a different body with the
    /// same id is refused. A retry after a lost reply is one turn.
    func testARetryWithTheSameRequestIdIsOneTurn() throws {
        final class Receipts {
            var turns = 0
            var byId: [String: (body: Data, job: String)] = [:]
            func post(_ body: Data) -> (Int, Data) {
                let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                let id = json?["requestId"] as? String ?? ""
                if let seen = byId[id] {
                    guard seen.body == body else { return (409, Data(#"{"error":"This send identifier belongs to a different message."}"#.utf8)) }
                    return (200, Data("{\"jobId\":\"\(seen.job)\"}".utf8))
                }
                turns += 1
                let job = "job-\(turns)"
                byId[id] = (body, job)
                return (200, Data("{\"jobId\":\"\(job)\"}".utf8))
            }
        }
        let server = Receipts()
        let request = TurnRequest(message: "When do we land?", conversationId: "c1", attachmentIds: nil)
        let body = try request.body()
        // The first POST arrives, and its reply is lost on the way back.
        _ = server.post(body)
        // The retry: the same body.
        let (status, data) = server.post(body)
        XCTAssertEqual(TurnStart.classify(status: status, body: data, retryAfter: nil), .started(jobId: "job-1"))
        XCTAssertEqual(server.turns, 1)
        // A NEW send gets a new id and is a new turn.
        _ = server.post(try TurnRequest(message: "When do we land?", conversationId: "c1", attachmentIds: nil).body())
        XCTAssertEqual(server.turns, 2)
    }

    func testHowAStartIsRead() {
        let body = { (s: String) in Data(s.utf8) }
        XCTAssertEqual(TurnStart.classify(status: 200, body: body(#"{"jobId":"j1"}"#), retryAfter: nil), .started(jobId: "j1"))
        XCTAssertEqual(TurnStart.classify(status: 200, body: body(#"{"error":"No model"}"#), retryAfter: nil), .refused("No model"))
        XCTAssertEqual(
            TurnStart.classify(status: 409, body: body(#"{"error":"This send is still being accepted","pending":true}"#), retryAfter: "3"),
            .pending(retryAfter: 3))
        XCTAssertEqual(TurnStart.classify(status: 409, body: body(#"{"pending":true}"#), retryAfter: "600"), .pending(retryAfter: 10), "capped")
        XCTAssertEqual(
            TurnStart.classify(status: 409, body: body(#"{"error":"This send identifier belongs to a different message."}"#), retryAfter: nil),
            .refused("This send identifier belongs to a different message."))
        XCTAssertEqual(TurnStart.classify(status: 503, body: body("<html>"), retryAfter: nil), .unavailable("The site is not answering just now."))
        XCTAssertEqual(TurnStart.classify(status: 429, body: body(#"{"error":"Slow down"}"#), retryAfter: nil), .refused("Slow down"))
    }

    // MARK: - A rejoined turn's gates

    func testAGateAnsweredBeforeTheRejoinIsDropped() {
        var hold = GateHold()
        XCTAssertTrue(hold.note("plan"))
        XCTAssertFalse(hold.note("heartbeat"))
        XCTAssertEqual(hold.held, "plan", "a heartbeat ticks while a gate waits")
        XCTAssertFalse(hold.note("tool_start"))
        XCTAssertNil(hold.held, "the turn moved on: the plan was answered")
        XCTAssertNil(hold.release())
    }

    func testAGateStillOpenAtTheEndOfTheReplayIsTheRealOne() {
        var hold = GateHold()
        for type in ["connected", "status", "token", "clarify", "heartbeat"] { _ = hold.note(type) }
        XCTAssertEqual(hold.release(), "clarify")
        XCTAssertNil(hold.held)
    }

    // MARK: - The turn in flight, across a relaunch

    private func defaults() -> UserDefaults {
        let name = "TurnStreamTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testAnActiveTurnIsRememberedAndForgotten() {
        let turns = ActiveTurns(defaults: defaults())
        let now = Date()
        turns.record("job-1", for: "c1", at: now)
        turns.record("job-9", for: "c2", at: now)
        XCTAssertEqual(turns.entry(for: "c1", now: now)?.jobId, "job-1")
        // An older job finishing must not forget the newer one.
        turns.record("job-2", for: "c1", at: now)
        turns.clear("c1", jobId: "job-1")
        XCTAssertEqual(turns.entry(for: "c1", now: now)?.jobId, "job-2")
        turns.clear("c1", jobId: "job-2")
        XCTAssertNil(turns.entry(for: "c1", now: now))
        XCTAssertEqual(turns.entry(for: "c2", now: now)?.jobId, "job-9")
    }

    func testAnOldTurnIsNotRejoined() {
        let turns = ActiveTurns(defaults: defaults())
        let then = Date(timeIntervalSince1970: 1_000_000)
        turns.record("job-1", for: "c1", at: then)
        XCTAssertNil(turns.entry(for: "c1", now: then.addingTimeInterval(ActiveTurns.maxAge + 1)))
        XCTAssertNil(turns.entry(for: "c1", now: then), "and it was cleared, not just hidden")
    }

    func testJunkInTheStoreIsAnEmptyMap() {
        let store = defaults()
        store.set(Data("not json".utf8), forKey: ActiveTurns.key)
        let turns = ActiveTurns(defaults: store)
        XCTAssertNil(turns.entry(for: "c1"))
        turns.record("job-1", for: "c1")
        XCTAssertEqual(turns.entry(for: "c1")?.jobId, "job-1")
    }
}
