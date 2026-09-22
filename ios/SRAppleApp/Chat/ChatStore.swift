import Foundation
import Combine

/// The thread ledger.
@MainActor
final class ThreadListStore: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var loading = false
    @Published private(set) var hasMore = false
    @Published var query = ""
    @Published var message: String?

    private var cursor: ConversationPage.Cursor?
    private let client = SiteClient.shared
    /// Plain `let`/`var`, never `@State`/`@Published`: a search task handle that
    /// the function starting it also reads is the read-own-write shape that
    /// loops.
    private var searchTask: Task<Void, Never>?

    func load(reset: Bool = true) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        if reset { cursor = nil }
        do {
            var path = "api/native/chat/conversations?limit=40"
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !term.isEmpty {
                path += "&q=\(term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            } else if let cursor, !reset {
                path += "&before=\(cursor.before)&beforeId=\(cursor.beforeId)&beforePinned=\(cursor.pinned ? 1 : 0)"
            }
            let page: ConversationPage = try await client.send(path)
            conversations = reset ? page.conversations : conversations + page.conversations
            cursor = page.cursor
            hasMore = page.hasMore && term.isEmpty
            message = nil
        } catch SiteError.expired {
            message = "This iPhone needs pairing again."
        } catch {
            message = error.localizedDescription
        }
    }

    /// Debounced, because the search reaches the whole archive.
    func search() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    func loadMore() async {
        guard hasMore, cursor != nil else { return }
        await load(reset: false)
    }
}

/// One thread, live.
@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var title: String?
    @Published private(set) var loading = false
    @Published private(set) var hasOlder = false
    @Published private(set) var sending = false
    @Published private(set) var activity = TurnActivity()
    @Published private(set) var blocked: BlockedTurn?
    @Published var message: String?

    let conversationId: String
    private let client = SiteClient.shared
    private var cursor: MessagePage.Cursor?

    /// Stream plumbing. All plain `var` — a task handle or a sequence number in
    /// `@Published` would re-enter the function that writes it.
    private var streamTask: Task<Void, Never>?
    private var jobId: String?
    private var lastEventId: Int?
    /// The id of the bubble currently being streamed into.
    private var liveBubbleId: String?

    init(conversationId: String) {
        self.conversationId = conversationId
    }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page: MessagePage = try await client.send(
                "api/native/chat/conversations/\(conversationId)/messages?limit=60"
            )
            messages = page.messages
            title = page.conversation.title
            hasOlder = page.hasOlder
            cursor = page.cursor
            message = nil
        } catch SiteError.expired {
            message = "This iPhone needs pairing again."
        } catch {
            message = error.localizedDescription
        }
    }

    func loadOlder() async {
        guard hasOlder, let cursor, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page: MessagePage = try await client.send(
                "api/native/chat/conversations/\(conversationId)/messages?limit=60&before=\(cursor.before)&beforeId=\(cursor.beforeId)"
            )
            // Prepend: the page is older than everything on screen.
            messages = page.messages + messages
            hasOlder = page.hasOlder
            self.cursor = page.cursor
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: - Sending

    private struct JobStart: Decodable { let jobId: String? ; let error: String? }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sending else { return }
        sending = true
        blocked = nil
        activity = TurnActivity()

        let userBubble = ChatMessage.pending(id: "local-user-\(UUID().uuidString)", role: "user", content: trimmed)
        let assistantId = "local-assistant-\(UUID().uuidString)"
        messages.append(userBubble)
        messages.append(ChatMessage.pending(id: assistantId, role: "assistant", content: ""))
        liveBubbleId = assistantId

        do {
            let body = try JSONEncoder().encode([
                "message": trimmed,
                "conversationId": conversationId,
            ])
            let data = try await client.post("api/workflows/orchestrator/chat", body: body)
            let start = try JSONDecoder().decode(JobStart.self, from: data)
            guard let job = start.jobId else {
                throw SiteError.message(start.error ?? "The server did not start that turn.")
            }
            jobId = job
            lastEventId = nil
            listen(to: job)
        } catch {
            finish(with: error.localizedDescription)
        }
    }

    private func listen(to job: String) {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try self.client.stream(jobId: job, after: self.lastEventId)
                for try await frame in stream {
                    if Task.isCancelled { return }
                    await self.handle(frame)
                }
                // The stream closed without a terminal frame. The turn may still
                // be running server-side, so this is not an error — but the app
                // must stop showing a spinner for it.
                if self.sending { self.finish(with: nil) }
            } catch is CancellationError {
                return
            } catch {
                if self.sending { self.finish(with: error.localizedDescription) }
            }
        }
    }

    private func handle(_ frame: SiteClient.StreamFrame) {
        if let id = frame.id { lastEventId = id }
        guard let type = frame.json["type"] as? String else { return }

        switch type {
        case "connected":
            return

        case "token":
            if let delta = frame.json["delta"] as? String { appendToLiveBubble(delta) }

        case "replace_bubble":
            // A revision, not an append: the model rewrote the answer.
            if let content = frame.json["content"] as? String { setLiveBubble(content) }

        case "thinking":
            if let delta = frame.json["delta"] as? String { activity.thinking += delta }

        case "status":
            activity.status = frame.json["text"] as? String

        case "heartbeat":
            activity.status = frame.json["summary"] as? String

        case "tool_start":
            let tool = frame.json["tool"] as? String
            activity.steps.append(ToolStep(
                tool: tool,
                status: "running",
                summary: frame.json["summary"] as? String
            ))

        case "tool_result":
            let tool = frame.json["tool"] as? String
            let status = frame.json["status"] as? String
            let summary = frame.json["summary"] as? String
            // Close the matching open step rather than appending a second row
            // for the same call.
            if let index = activity.steps.lastIndex(where: { $0.tool == tool && $0.status == "running" }) {
                activity.steps[index] = ToolStep(tool: tool, status: status, summary: summary ?? activity.steps[index].summary)
            } else {
                activity.steps.append(ToolStep(tool: tool, status: status, summary: summary))
            }

        // The four gates this app cannot answer. Naming them stops a turn
        // hanging silently with a spinner that never resolves.
        case "plan", "confirm", "clarify", "secret_request", "approval":
            blocked = BlockedTurn(kind: type, detail: (frame.json["prompt"] as? String) ?? "")

        case "done":
            if let result = frame.json["result"] as? [String: Any],
               let reply = result["reply"] as? String ?? result["content"] as? String,
               !reply.isEmpty {
                setLiveBubble(reply)
            }
            finish(with: nil)
            Task { await refreshAfterTurn() }

        case "error":
            finish(with: frame.json["message"] as? String ?? "That turn failed.")

        default:
            return
        }
    }

    private func appendToLiveBubble(_ delta: String) {
        guard let id = liveBubbleId, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += delta
    }

    private func setLiveBubble(_ content: String) {
        guard let id = liveBubbleId, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
    }

    private func finish(with error: String?) {
        sending = false
        jobId = nil
        // The steps taken stay attached to the finished bubble; the thinking and
        // the status line do not, because they described a turn that is over.
        if let id = liveBubbleId, let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].toolSteps = activity.steps
            if messages[index].content.isEmpty && error == nil {
                messages[index].content = "*(no reply)*"
            }
        }
        activity = TurnActivity()
        liveBubbleId = nil
        if let error { message = error }
    }

    /// Re-read the thread so the local bubbles are replaced by the server's rows
    /// with their real ids. Without it, a second send in the same session builds
    /// on optimistic state the server never confirmed.
    private func refreshAfterTurn() async {
        try? await Task.sleep(for: .milliseconds(600))
        await load()
    }

    /// Drop the stream without telling the server. Used when the screen closes —
    /// the turn keeps running and is picked up again by reloading the thread,
    /// which is what the web client does when a tab is closed mid-turn.
    func stop() {
        streamTask?.cancel()
        streamTask = nil
    }

    func cancel() async {
        guard let job = jobId else { return }
        streamTask?.cancel()
        let _: EmptyReply? = try? await client.send(
            "api/workflows/orchestrator/chat?jobId=\(job)",
            method: "DELETE"
        )
        finish(with: "Stopped.")
    }
}

/// A body we do not read. `send` needs a Decodable and some endpoints answer
/// with a shape this app has no use for.
struct EmptyReply: Decodable {}
