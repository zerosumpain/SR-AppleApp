import Foundation
import SwiftUI
import UIKit

// MARK: - The App Review demo
//
// App Review Guideline 2.1 accepts "a fully-featured demo mode" in place of a
// reviewer account, and a real account is ruled out here: anyone the family
// lane admits can see the household's live locations.
//
// So: Welcome → "I have a pairing code" → the reviewer types the review code →
// `POST /api/native/review-demo {code}` on the site, which compares it with a
// secret held there (the code is NOT in this binary) and answers
// `{demo: true}`. From then on, until Settings → Leave demo:
//
//  * every site request is answered in-process from `SRDemoFixtures` — the
//    same synthetic fixtures the `-SRDemo` screenshots use — by the demo
//    session in `SiteClient`. Nothing reaches the site;
//  * the companion lane (health and location uploads, `API.request`) refuses
//    before it builds a request, and nothing is paired, so nothing uploads.
//    Permission prompts still appear, so a reviewer sees them;
//  * no push token goes to the site (`PushRegistration`), no Live Activity
//    token, nothing into Spotlight, no credential for the widgets;
//  * what the reviewer does (a chat message, a task added or confirmed) is
//    remembered in memory by `SRDemoSession` and forgotten on leaving.
//
// Persisted (UserDefaults), so a relaunch mid-review is still the demo.

@MainActor
final class ReviewDemo: ObservableObject {
    static let shared = ReviewDemo()

    nonisolated static let key = "review-demo"

    /// Readable from any thread: the fixture protocol and `SRDemo.isOn` ask.
    nonisolated static var isActive: Bool { UserDefaults.standard.bool(forKey: key) }

    /// The same fact, for views to observe.
    @Published private(set) var active: Bool

    private init() {
        active = Self.isActive
    }

    /// Called first thing at launch. DEBUG only: a UI test's fresh install, or
    /// a `-SRDemo` screenshot run, must not inherit a review demo an earlier
    /// test on the same simulator left switched on.
    nonisolated static func prepareLaunch() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-SRFreshInstall") || args.contains("-SRDemo") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        #endif
    }

    /// The site said yes: run on fixtures from now on.
    func enter() {
        UserDefaults.standard.set(true, forKey: Self.key)
        settle()
    }

    /// Back to Welcome, with nothing of the demo left behind.
    func leave() {
        guard Self.isActive || active else { return }
        UserDefaults.standard.removeObject(forKey: Self.key)
        settle()
    }

    /// Bring every shared piece of state into line with the flag.
    private func settle() {
        SRDemoSession.shared.reset()
        SiteClient.shared.demoChanged()
        AccessStore.shared.demoChanged()
        // Shared stores that outlive `ContentView`: drop whatever they read.
        FamilyStepsStore.shared.reset()
        FamilyTasksStore.shared.reset()
        LandgrabStore.shared.reset()
        UIApplication.shared.shortcutItems = AccessPolicy.quickActions(for: AccessStore.shared.current).map { $0.item }
        active = Self.isActive
    }

    // MARK: - Asking the site

    /// Whether the site's answer to `api/native/review-demo` switches the demo
    /// on. Only a 200 whose body says `demo: true` does; anything else — a
    /// 401 wrong code, a 404 switched-off route, a 429, an HTML error page —
    /// is "not the review code", and the caller tries it as a pairing code.
    nonisolated static func switchesOn(status: Int, body: Data) -> Bool {
        guard status == 200 else { return false }
        struct Answer: Decodable { let demo: Bool? }
        return (try? JSONDecoder().decode(Answer.self, from: body))?.demo == true
    }
}

/// Said on every screen while the review demo runs, so a look at made-up data
/// never passes for the real thing. A strip stacked above the tabs, not an
/// overlay: it covers nothing.
struct DemoBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.rectangle")
                .imageScale(.small)
            Text("DEMO")
                .font(SR.Text.mono(11))
                .tracking(1.2)
            Text("Sample data · nothing leaves this iPhone")
                .font(SR.Text.secondary())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(SR.paper)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(SR.accentDeep.ignoresSafeArea(edges: .top))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Demo mode. Sample data; nothing leaves this iPhone.")
        .accessibilityIdentifier("demo-badge")
    }
}

/// Settings' first section while the review demo runs: what it is, and the
/// way out. Leaving swaps the window back to Welcome, which also closes this.
struct ReviewDemoSettingsSection: View {
    @ObservedObject private var demo = ReviewDemo.shared

    var body: some View {
        if demo.active {
            Section {
                SRRow(title: "You are in the demo",
                      subtitle: "Everything here is sample data made up on this iPhone. Nothing you do is sent anywhere.",
                      icon: "play.rectangle")
                    .srGlassRow()
                    .accessibilityIdentifier("settings-demo-note")
                Button {
                    SRHaptic.select()
                    demo.leave()
                } label: {
                    SRRow(title: "Leave demo", subtitle: "Back to the welcome screen", icon: "rectangle.portrait.and.arrow.right", tone: SR.error)
                }
                .srGlassRow()
                .accessibilityIdentifier("settings-leave-demo")
            } header: {
                SRSectionLabel(text: "Demo")
            }
        }
    }
}

// MARK: - What the demo remembers

/// The review demo's short memory: messages sent and the task list as changed.
///
/// In memory only, reset on entering and leaving. Locked, because the fixture
/// protocol answers on URLSession's own threads.
final class SRDemoSession: @unchecked Sendable {
    static let shared = SRDemoSession()

    private let lock = NSLock()
    /// Message JSON objects, per conversation, in order.
    private var sent: [String: [String]] = [:]
    /// Replies waiting to be streamed, by job id.
    private var replies: [String: String] = [:]
    private var turns = 0
    private var tasks: FamilyTasksBoard?
    private var newTasks = 0

    func reset() {
        lock.lock(); defer { lock.unlock() }
        sent = [:]
        replies = [:]
        turns = 0
        tasks = nil
        newTasks = 0
    }

    // MARK: Chat

    /// `POST api/workflows/orchestrator/chat`: remember the message and a canned
    /// reply, and hand back a job id for the stream.
    func startTurn(body: Data?, clock: SRDemoFixtures.DemoClock) -> String {
        let fields = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let message = (fields["message"] as? String) ?? ""
        let conversation = (fields["conversationId"] as? String) ?? "demo-thread-new"
        let reply = Self.reply(to: message)

        lock.lock(); defer { lock.unlock() }
        turns += 1
        let job = "demo-job-\(turns)"
        replies[job] = reply
        let asked = Self.message(id: "demo-sent-\(turns)-q", role: "user", content: message, at: clock.iso(minutesAgo: 0))
        let answered = Self.message(id: "demo-sent-\(turns)-a", role: "assistant", content: reply, at: clock.iso(minutesAgo: 0))
        sent[conversation, default: []] += [asked, answered]
        return "{\"jobId\": \(SRDemoFixtures.s(job))}"
    }

    /// `GET …/chat/stream?jobId=`: the reply as server-sent events, a few words
    /// a frame, then `done` — the same frames a real turn sends.
    func stream(jobId: String) -> String? {
        lock.lock()
        let reply = replies[jobId]
        lock.unlock()
        guard let reply else { return nil }

        var frames: [[String: Any]] = [["type": "connected"], ["type": "status", "text": "Demo reply"]]
        let words = reply.split(separator: " ", omittingEmptySubsequences: false)
        stride(from: 0, to: words.count, by: 4).forEach { start in
            let chunk = words[start..<min(start + 4, words.count)].joined(separator: " ")
            frames.append(["type": "token", "delta": start + 4 < words.count ? chunk + " " : chunk])
        }
        frames.append(["type": "done", "result": ["reply": reply]])

        return frames.enumerated().map { index, frame in
            let data = (try? JSONSerialization.data(withJSONObject: frame)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return "id: \(index + 1)\ndata: \(data)\n\n"
        }.joined()
    }

    func sentMessages(conversation: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return sent[conversation] ?? []
    }

    static func message(id: String, role: String, content: String, at: String) -> String {
        "{\"id\": \(SRDemoFixtures.s(id)), \"role\": \(SRDemoFixtures.s(role)), \"content\": \(SRDemoFixtures.s(content)), \"createdAt\": \(SRDemoFixtures.s(at)), \"source\": \"web\", \"toolSteps\": [], \"attachments\": []}"
    }

    /// A canned answer. Honest about being one, and useful about what the real
    /// thing does with the same question.
    static func reply(to message: String) -> String {
        let text = message.lowercased()
        let lead: String
        if ["sleep", "run", "step", "heart", "hrv", "health", "train", "walk"].contains(where: { text.contains($0) }) {
            lead = "Here's how a health question is answered. For real, jkai reads your own figures (sleep, heart rate, steps and workouts from Apple Health) and replies with the numbers and a short read of the trend.\n\n- **Sleep** last night: 7h 24m, 18 minutes over your week\n- **Resting heart rate**: 52 bpm, down 2\n- **Steps** so far today: 9,120"
        } else if ["news", "story", "headline", "article"].contains(where: { text.contains($0) }) {
            lead = "Here's how a news question is answered. For real, jkai reads the stories on your news desk and summarises the ones that match, with a link to each."
        } else {
            lead = "Thanks. This is a demo reply: in demo mode the assistant is not connected, so nothing you type leaves this iPhone.\n\nFor real, jkai answers from your notes, your health figures and the web, and shows each step it took under the reply."
        }
        return lead + "\n\n*(Demo mode: sample data, generated on this iPhone.)*"
    }

    // MARK: Family tasks

    func tasksJSON(clock: SRDemoFixtures.DemoClock) -> String {
        lock.lock(); defer { lock.unlock() }
        return Self.encode(board(clock))
    }

    /// `POST api/native/family/tasks`: add it to the list.
    func createTask(body: Data?, clock: SRDemoFixtures.DemoClock) -> String? {
        let fields = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let title = ((fields["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        var list = board(clock)
        newTasks += 1
        var reward: FamilyReward?
        if let r = fields["reward"] as? [String: Any], let kind = r["kind"] as? String {
            reward = FamilyReward(kind: kind, pence: (r["pence"] as? NSNumber)?.intValue, note: r["note"] as? String)
        }
        let task = FamilyTask(
            id: "t_demo_\(newTasks)", title: title, notes: fields["notes"] as? String,
            deadline: fields["deadline"] as? String, assignee: fields["assigneeId"] as? String,
            createdBy: list.me.id, reward: reward, createdAt: clock.iso(minutesAgo: 0)
        )
        list.open.insert(task, at: 0)
        tasks = list
        return "{\"task\": \(Self.encode(task))}"
    }

    /// `PATCH api/native/family/tasks/<id>` `{action, note?}`: move it along.
    func actOnTask(id: String, body: Data?, clock: SRDemoFixtures.DemoClock) -> String? {
        let fields = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        guard let action = FamilyTaskAction(rawValue: (fields["action"] as? String) ?? "") else { return nil }
        lock.lock(); defer { lock.unlock() }
        var list = board(clock)
        let now = clock.iso(minutesAgo: 0)
        let me = list.me.id

        guard var task = list.open.first(where: { $0.id == id }) ?? list.completed.first(where: { $0.id == id }) else { return nil }
        list.open.removeAll { $0.id == id }
        list.completed.removeAll { $0.id == id }

        switch action {
        case .done:
            task.status = "done"; task.doneBy = me; task.doneAt = now; task.sentBackNote = nil
        case .undo:
            task.status = "open"; task.doneBy = nil; task.doneAt = nil
        case .confirm:
            task.status = "confirmed"; task.confirmedBy = me; task.confirmedAt = now
            if task.doneBy == nil { task.doneBy = me; task.doneAt = now }
        case .sendBack:
            task.status = "open"; task.doneBy = nil; task.doneAt = nil
            task.sentBackNote = (fields["note"] as? String) ?? "Not quite yet."
        case .paid:
            task.reward?.paidAt = now
        case .delete:
            task.status = "deleted"
        }
        if task.status == "confirmed" {
            list.completed.insert(task, at: 0)
        } else if task.status != "deleted" {
            list.open.insert(task, at: 0)
        }
        list.owed = Self.owed(list.completed)
        tasks = list
        return "{\"task\": \(Self.encode(task))}"
    }

    /// The board as it stands, starting from the canned one. Lock held.
    private func board(_ clock: SRDemoFixtures.DemoClock) -> FamilyTasksBoard {
        if let tasks { return tasks }
        let start = (try? JSONDecoder().decode(FamilyTasksBoard.self, from: Data(SRDemoFixtures.familyTasks(clock).utf8)))
            ?? FamilyTasksBoard(me: FamilyTaskMe(id: "f_alex", parent: true), people: [], open: [], completed: [],
                                owed: FamilyOwed(totalPence: 0, items: []))
        tasks = start
        return start
    }

    /// Confirmed with a reward not yet paid.
    static func owed(_ completed: [FamilyTask]) -> FamilyOwed {
        let items = completed.filter { $0.reward != nil && $0.reward?.paid == false }
        return FamilyOwed(totalPence: items.reduce(0) { $0 + ($1.reward?.pence ?? 0) }, items: items)
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }
}

#if DEBUG
/// `-SRStubNetwork` (UI tests only): the site, as far as Welcome's code box
/// needs one. `POST api/native/review-demo` says yes to `stubCode` and 401s
/// anything else; every other request is a 404, as if the site had no such
/// pairing code. Compiled out of Release — the real review code lives only on
/// the server.
final class SRStubURLProtocol: URLProtocol {
    static let stubCode = "UITEST-REVIEW-CODE"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        var status = 404
        var body = #"{"error":"That pairing code is not valid."}"#
        if url.path.hasSuffix("api/native/review-demo") {
            let sent = Self.body(of: request).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            if (sent?["code"] as? String) == Self.stubCode {
                status = 200
                body = #"{"demo":true}"#
            } else {
                status = 401
            }
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
#endif
