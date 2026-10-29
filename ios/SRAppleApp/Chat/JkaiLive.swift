import Foundation
import Combine

/// The phone's jkai channel, and what it knows about this person's threads.
///
/// One `GET /api/jkai/events?scope=me` stream for the whole app, open only
/// while the app is in the foreground, and only once the server has said it
/// has one (`features.events` on `/chat/active`). It resumes with
/// `Last-Event-ID` after a drop, with the turn stream's backoff, and gives up
/// until the next foreground once that is spent or the server refuses it.
/// What a frame means and what is done about it are `JkaiEvents.swift`'s
/// rules; this applies them to the open threads and the thread list.
///
/// Never in a demo, and never while viewing as somebody: the channel is this
/// phone's own person, and the look-as-them view is a read of THEIR threads.
@MainActor
final class JkaiLive: ObservableObject {
    static let shared = JkaiLive()

    /// What the server last said it can do. Kept across launches, so the
    /// channel and the presence beat start without waiting for a probe.
    @Published private(set) var features: JkaiFeatures
    /// Each thread's dots: running, waiting on an answer, something new.
    @Published private(set) var marks: [String: Set<JkaiRowMark>] = [:]
    /// The site refused this phone a red team (a member's credential): the
    /// desk stops offering it until the app is relaunched.
    @Published var redTeamRefused = false

    private let client = SiteClient.shared
    private static let featuresKey = "jkai-features"

    private final class Weak {
        weak var store: ChatStore?
        init(_ store: ChatStore) { self.store = store }
    }
    /// The threads on screen, by conversation id.
    private var open: [String: Weak] = [:]

    private var task: Task<Void, Never>?
    /// Bumped on every connect and disconnect, so a loop that ends late does
    /// not clear the handle of the one that replaced it.
    private var generation = 0
    private var resume = JkaiEventsResume()
    private var foreground = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.featuresKey),
           let saved = try? JSONDecoder().decode(JkaiFeatures.self, from: data) {
            features = saved
        } else {
            features = .off
        }
    }

    /// The one dot a thread row shows, if any.
    func mark(for conversationId: String) -> JkaiRowMark? {
        JkaiEventAction.strongest(marks[conversationId] ?? [])
    }

    // MARK: - What the server said

    func note(_ next: JkaiFeatures) {
        guard next != features else { return }
        features = next
        if let data = try? JSONEncoder().encode(next) { UserDefaults.standard.set(data, forKey: Self.featuresKey) }
        sync()
    }

    /// `GET /chat/active` with no thread: the running dots, and the features.
    /// Quietly nothing on a server that does not answer it.
    func refreshActive() async {
        guard client.isPaired, !SRDemo.isOn else { return }
        guard let reply = try? await client.exchange("api/workflows/orchestrator/chat/active", method: "GET"),
              (200..<300).contains(reply.1.statusCode),
              let list = ActiveTurnList.read(reply.0) else { return }
        var next = marks
        for id in next.keys { next[id]?.remove(.running) }
        for id in list.running.keys { next[id, default: []].insert(.running) }
        marks = next.filter { !$0.value.isEmpty }
        note(list.features)
    }

    /// A thread's own probe, which knows better than the list.
    func setRunning(_ conversationId: String, _ running: Bool) {
        set(conversationId, .running, running)
    }

    // MARK: - Open threads

    func opened(_ store: ChatStore) {
        open[store.conversationId] = Weak(store)
        // Opening a thread is reading it.
        set(store.conversationId, .reply, false)
        set(store.conversationId, .waiting, false)
    }

    func closed(_ store: ChatStore) {
        if open[store.conversationId]?.store === store { open[store.conversationId] = nil }
    }

    // MARK: - The connection

    func setForeground(_ active: Bool) {
        foreground = active
        if active {
            Task {
                await refreshActive()
                sync()
            }
        } else {
            disconnect()
        }
    }

    /// Open or close the channel for what is true now: the foreground, a
    /// pairing, nobody being viewed as, and a server that has one.
    func sync() {
        let allowed = foreground && client.isPaired && !SRDemo.isOn
            && AccessStore.shared.viewingAs == nil && features.events
        if allowed { connect() } else { disconnect() }
    }

    /// "View as" changed: the dots were somebody else's.
    func reset() {
        marks = [:]
        redTeamRefused = false
        resume = JkaiEventsResume()
        disconnect()
        sync()
    }

    private func connect() {
        guard task == nil else { return }
        resume.restart()
        generation += 1
        let mine = generation
        task = Task { [weak self] in
            await self?.run()
            guard let self, self.generation == mine else { return }
            self.task = nil
        }
    }

    private func disconnect() {
        generation += 1
        task?.cancel()
        task = nil
    }

    private func run() async {
        while !Task.isCancelled {
            var status: Int?
            do {
                for try await frame in try client.events(after: resume.lastEventId) {
                    if Task.isCancelled { return }
                    guard resume.accept(frame.id) else { continue }
                    guard let event = JkaiEvent.parse(frame.json) else { continue }
                    // Anything but the greeting means the link is good.
                    if event != .connected { resume.restart() }
                    apply(event)
                }
            } catch is CancellationError {
                return
            } catch SiteError.expired {
                status = 401
            } catch SiteError.status(let code, _) {
                status = code
            } catch {
                let ns = error as NSError
                if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            }
            if Task.isCancelled { return }
            switch resume.next(afterStatus: status) {
            case .reconnect(let wait):
                try? await Task.sleep(for: .seconds(wait))
            case .stop:
                return
            }
        }
    }

    private func apply(_ event: JkaiEvent) {
        let showing = Set(open.compactMap { $0.value.store == nil ? nil : $0.key })
        for action in JkaiEventAction.route(event, open: showing) {
            switch action {
            case .running(let id, let on):
                set(id, .running, on)
            case .mark(let id, let mark):
                set(id, mark, true)
            case .unmark(let id, let mark):
                set(id, mark, false)
            case .reload(let id):
                if let store = open[id]?.store { Task { await store.reloadFromServer() } }
            case .probe(let id):
                if let store = open[id]?.store { Task { await store.rejoin() } }
            case .turnEnded(let id, let job):
                if let store = open[id]?.store { Task { await store.serverTurnEnded(jobId: job) } }
            case .desk(let id, let update):
                open[id]?.store?.applyDesk(update)
            }
        }
    }

    private func set(_ conversationId: String, _ mark: JkaiRowMark, _ on: Bool) {
        var current = marks[conversationId] ?? []
        if on { current.insert(mark) } else { current.remove(mark) }
        guard current != (marks[conversationId] ?? []) else { return }
        marks[conversationId] = current.isEmpty ? nil : current
    }
}
