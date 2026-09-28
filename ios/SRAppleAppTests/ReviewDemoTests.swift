import XCTest
@testable import SRAppleApp

/// The App Review demo: in with the review code, out from Settings, and — the
/// promise it rests on — nothing sent anywhere while it runs.
///
/// These flip the real, persisted flag on the shared singletons, so every test
/// leaves the demo in `tearDown`, whatever happened.
@MainActor
final class ReviewDemoTests: XCTestCase {

    /// Counts every request that reaches the LIVE site session, and answers it
    /// with a 500 so nothing real is ever needed.
    final class Recorder: URLProtocol {
        private static let lock = NSLock()
        private static var seen: [String] = []
        static var paths: [String] { lock.lock(); defer { lock.unlock() }; return seen }
        static func clear() { lock.lock(); seen = []; lock.unlock() }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.lock.lock(); Self.seen.append(request.url?.path ?? "?"); Self.lock.unlock()
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    override func setUp() async throws {
        try XCTSkipIf(SRDemo.isShowcase, "the -SRDemo harness is on for the whole process")
        ReviewDemo.shared.leave()
        Recorder.clear()
        SiteClient.shared.useLiveTransport([Recorder.self])
    }

    override func tearDown() async throws {
        ReviewDemo.shared.leave()
        SiteClient.shared.useLiveTransport([])
    }

    // MARK: - The site's answer

    func testOnlyAYesFromTheSiteSwitchesTheDemoOn() {
        XCTAssertTrue(ReviewDemo.switchesOn(status: 200, body: Data(#"{"demo":true}"#.utf8)))
        XCTAssertFalse(ReviewDemo.switchesOn(status: 200, body: Data(#"{"demo":false}"#.utf8)))
        XCTAssertFalse(ReviewDemo.switchesOn(status: 200, body: Data(#"{"token":"x"}"#.utf8)))
        XCTAssertFalse(ReviewDemo.switchesOn(status: 200, body: Data("<html>".utf8)))
        // A wrong code, the route switched off, the ceiling hit.
        XCTAssertFalse(ReviewDemo.switchesOn(status: 401, body: Data(#"{"demo":true}"#.utf8)))
        XCTAssertFalse(ReviewDemo.switchesOn(status: 404, body: Data(#"{"error":"Not found"}"#.utf8)))
        XCTAssertFalse(ReviewDemo.switchesOn(status: 429, body: Data()))
    }

    func testAskingTheSiteGoesToTheReviewRouteOnly() async {
        // The live transport answers 500: not the review code.
        let yes = await SiteClient.shared.isReviewDemoCode("NOT-THE-CODE")
        XCTAssertFalse(yes)
        XCTAssertEqual(Recorder.paths, ["/api/native/review-demo"])
        XCTAssertFalse(ReviewDemo.isActive)
    }

    // MARK: - In and out

    func testEnteringOpensTheWholeAppAsAPretendOwner() {
        XCTAssertFalse(SRDemo.isOn)
        ReviewDemo.shared.enter()

        XCTAssertTrue(ReviewDemo.isActive)
        XCTAssertTrue(ReviewDemo.shared.active)
        XCTAssertTrue(SRDemo.isOn)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: ReviewDemo.key), "a relaunch mid-review must still be the demo")
        XCTAssertEqual(SiteClient.shared.token, SRDemo.token)
        XCTAssertEqual(SiteClient.shared.origin, SiteClient.defaultOrigin)
        XCTAssertEqual(AccessStore.shared.current, .everything)
        XCTAssertFalse(AccessStore.shared.isRealOwner, "the demo can never view the app as a real person")
        XCTAssertEqual(EntryPolicy.entry(status: nil, sitePaired: false, companionPaired: false, skipped: false, demo: SRDemo.isOn), .app)
        XCTAssertEqual(RegistrationStore.shared.entry(companionPaired: false), .app)
    }

    func testLeavingGoesBackToWelcomeWithNothingLeftBehind() async throws {
        let keychainToken = SiteKeychain.read()
        ReviewDemo.shared.enter()
        // Something to forget: a message and a task.
        _ = try await SiteClient.shared.post("api/workflows/orchestrator/chat",
                                             body: Data(#"{"message":"hello","conversationId":"demo-thread-new"}"#.utf8))
        _ = try await SiteClient.shared.post("api/native/family/tasks", body: Data(#"{"title":"Feed the cat"}"#.utf8))
        XCTAssertFalse(SRDemoSession.shared.sentMessages(conversation: "demo-thread-new").isEmpty)

        ReviewDemo.shared.leave()

        XCTAssertFalse(ReviewDemo.isActive)
        XCTAssertFalse(ReviewDemo.shared.active)
        XCTAssertFalse(SRDemo.isOn)
        XCTAssertNil(UserDefaults.standard.object(forKey: ReviewDemo.key))
        XCTAssertEqual(SiteClient.shared.token, keychainToken, "the real credential (or none) again, never the pretend one")
        XCTAssertNotEqual(SiteClient.shared.token, SRDemo.token)
        XCTAssertTrue(SRDemoSession.shared.sentMessages(conversation: "demo-thread-new").isEmpty)
        XCTAssertNil(FamilyTasksStore.shared.board)
        if keychainToken == nil && !RegistrationStore.shared.skipped && RegistrationStore.shared.status == nil {
            XCTAssertEqual(RegistrationStore.shared.entry(companionPaired: false), .welcome)
        }
    }

    func testSigningOutOrDeletingTheAccountInTheDemoJustLeavesIt() async throws {
        ReviewDemo.shared.enter()
        // Settings → Delete account ends with the site's DELETE and a sign-out.
        _ = try await SiteClient.shared.call("api/native/account", method: "DELETE")
        SiteClient.shared.signOut()
        XCTAssertFalse(ReviewDemo.isActive)
        XCTAssertTrue(Recorder.paths.isEmpty, "the DELETE went to the fixtures, not the site")
    }

    // MARK: - Nothing leaves the phone

    func testNoSiteRequestReachesTheNetworkInTheDemo() async throws {
        ReviewDemo.shared.enter()
        let before = SRDemoURLProtocol.served

        let today = try await SiteClient.shared.call("api/native/today", method: "GET")
        XCTAssertFalse(today.isEmpty)
        _ = try await SiteClient.shared.call("api/native/news?view=top", method: "GET")
        _ = try await SiteClient.shared.call("api/native/family/steps", method: "GET")
        _ = try await SiteClient.shared.call("api/native/games", method: "GET")
        _ = try await SiteClient.shared.post("api/native/notifications", body: Data("{}".utf8))
        let start = try await SiteClient.shared.post("api/workflows/orchestrator/chat",
                                                     body: Data(#"{"message":"How did I sleep?","conversationId":"demo-thread-training"}"#.utf8))
        let job = try XCTUnwrap((try JSONSerialization.jsonObject(with: start) as? [String: Any])?["jobId"] as? String)
        var frames = 0
        for try await _ in try SiteClient.shared.stream(jobId: job) { frames += 1 }
        XCTAssertGreaterThan(frames, 2)
        // A path with no fixture is a 404 from the fixtures — still not the network.
        do { _ = try await SiteClient.shared.call("api/native/nothing-here", method: "GET") } catch {}
        // Pairing is refused before a request exists.
        do {
            try await SiteClient.shared.redeem(code: "123456")
            XCTFail("a demo redeemed a pairing code")
        } catch {}
        // And the review route itself is not asked again.
        let again = await SiteClient.shared.isReviewDemoCode("anything")
        XCTAssertFalse(again)

        XCTAssertEqual(Recorder.paths, [], "a demo request reached the live site session")
        XCTAssertGreaterThanOrEqual(SRDemoURLProtocol.served - before, 8)

        // The recorder is live: out of the demo, the same client does reach it.
        ReviewDemo.shared.leave()
        _ = await SiteClient.shared.isReviewDemoCode("anything")
        XCTAssertEqual(Recorder.paths.count, 1)
    }

    func testTheCompanionLaneRefusesInTheDemo() async {
        ReviewDemo.shared.enter()
        let api = API()
        api.baseURL = URL(string: "https://companion.example.org")!
        api.token = "not-a-real-token"
        do {
            let _: API.Acknowledgement = try await api.request("sync", method: "POST", data: Data("{}".utf8))
            XCTFail("the companion lane sent something in the demo")
        } catch {
            XCTAssertEqual(error.localizedDescription, API.demoRefusal)
        }
        do {
            try await api.pair(server: "https://companion.example.org", code: "123456")
            XCTFail("the companion paired in the demo")
        } catch {
            XCTAssertEqual(error.localizedDescription, API.demoRefusal)
        }
        XCTAssertEqual(api.token, "not-a-real-token", "a refused pairing leaves the old credential alone")
    }

    // MARK: - What the demo remembers

    func testAChatMessageGetsACannedReplyThatStaysInTheThread() async throws {
        ReviewDemo.shared.enter()
        let start = try await SiteClient.shared.post("api/workflows/orchestrator/chat",
                                                     body: Data(#"{"message":"What's in the news?","conversationId":"demo-thread-new"}"#.utf8))
        let job = try XCTUnwrap((try JSONSerialization.jsonObject(with: start) as? [String: Any])?["jobId"] as? String)

        var tokens = ""
        var done: String?
        for try await frame in try SiteClient.shared.stream(jobId: job) {
            switch frame.json["type"] as? String {
            case "token": tokens += frame.json["delta"] as? String ?? ""
            case "done": done = (frame.json["result"] as? [String: Any])?["reply"] as? String
            default: break
            }
        }
        let reply = try XCTUnwrap(done)
        XCTAssertEqual(tokens, reply, "the streamed tokens add up to the reply")
        XCTAssertTrue(reply.contains("Demo mode"))

        let page = try await SiteClient.shared.call("api/native/chat/conversations/demo-thread-new/messages", method: "GET")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: page) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant"])
        XCTAssertEqual(messages.first?["content"] as? String, "What's in the news?")

        // A thread with history keeps it, with the new turn after.
        _ = try await SiteClient.shared.post("api/workflows/orchestrator/chat",
                                             body: Data(#"{"message":"and my sleep?","conversationId":"demo-thread-training"}"#.utf8))
        let training = try await SiteClient.shared.call("api/native/chat/conversations/demo-thread-training/messages", method: "GET")
        let trainingJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: training) as? [String: Any])
        let trainingMessages = try XCTUnwrap(trainingJSON["messages"] as? [[String: Any]])
        XCTAssertEqual(trainingMessages.count, 6)
        XCTAssertEqual(trainingMessages[4]["content"] as? String, "and my sleep?")
    }

    func testTasksCanBeAddedDoneAndConfirmedInMemory() async throws {
        ReviewDemo.shared.enter()
        func board() async throws -> FamilyTasksBoard {
            try await SiteClient.shared.send("api/native/family/tasks")
        }
        let first = try await board()
        XCTAssertTrue(first.me.parent)
        let owedBefore = first.owed.totalPence

        try await SiteClient.shared.post("api/native/family/tasks", body: JSONEncoder().encode(
            FamilyTaskCreateBody(title: "Feed the cat", reward: FamilyTaskRewardBody(kind: "cash", pence: 150))
        ))
        var now = try await board()
        let added = try XCTUnwrap(now.open.first { $0.title == "Feed the cat" })
        XCTAssertTrue(added.isOpen)

        _ = try await SiteClient.shared.call("api/native/family/tasks/\(added.id)", method: "PATCH",
                                             body: JSONEncoder().encode(FamilyTaskActionBody(action: "done")))
        now = try await board()
        XCTAssertTrue(try XCTUnwrap(now.open.first { $0.id == added.id }).isAwaiting)

        _ = try await SiteClient.shared.call("api/native/family/tasks/\(added.id)", method: "PATCH",
                                             body: JSONEncoder().encode(FamilyTaskActionBody(action: "confirm")))
        now = try await board()
        XCTAssertNil(now.open.first { $0.id == added.id })
        XCTAssertTrue(try XCTUnwrap(now.completed.first { $0.id == added.id }).isConfirmed)
        XCTAssertEqual(now.owed.totalPence, owedBefore + 150, "a confirmed cash reward is owed")

        _ = try await SiteClient.shared.call("api/native/family/tasks/\(added.id)", method: "PATCH",
                                             body: JSONEncoder().encode(FamilyTaskActionBody(action: "paid")))
        now = try await board()
        XCTAssertEqual(now.owed.totalPence, owedBefore)

        // Gone on leaving; a fresh demo starts from the canned list.
        ReviewDemo.shared.leave()
        ReviewDemo.shared.enter()
        now = try await board()
        XCTAssertNil(now.open.first { $0.title == "Feed the cat" })
        XCTAssertNil(now.completed.first { $0.title == "Feed the cat" })
    }

    // MARK: - Made-up people

    /// The demo is shown to a stranger: no real family names in it.
    func testTheDemoPeopleAreMadeUp() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let bodies = [
            SRDemoFixtures.familyTasks(clock),
            SRDemoFixtures.familySteps(clock),
            try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/games", query: [:], body: nil, clock: clock)),
            SRDemoFixtures.me(clock),
        ]
        for body in bodies {
            XCTAssertFalse(body.contains("John"), String(body.prefix(80)))
            XCTAssertFalse(body.lowercased().contains("kelly"))
        }
    }
}
