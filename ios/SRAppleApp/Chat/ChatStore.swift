import Foundation
import Combine
import UIKit

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
            // Titles into iPhone search. Only on a reset — a page of older
            // threads is not what somebody is searching their Home Screen for,
            // and re-indexing on every scroll would write the index all day.
            if reset && term.isEmpty { ThreadIndex.update(conversations) }
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
        guard hasMore, cursor != nil, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await load(reset: false)
    }

    // MARK: - The two groups
    //
    // The endpoint already orders pinned first, so this is a split of one
    // ordered page rather than a second sort. It exists because a phone list
    // with a `Pinned` header above three rows and `Recent` above the rest is
    // read at a glance, and one undifferentiated run with a pin glyph in it is
    // not — the glyph is 10pt and it is the first thing lost to a sunny bus.
    var pinned: [Conversation] { conversations.filter(\.pinned) }
    var unpinned: [Conversation] { conversations.filter { !$0.pinned && $0.isListable() } }
    /// The unpinned threads by when they were last touched.
    var sections: [ThreadSections.Group] { ThreadSections.group(unpinned) }

    // MARK: - Mutations
    //
    // Every one of these writes the local row FIRST and reconciles after. A
    // pin that waits for a round trip on a train reads as a swipe that did not
    // take, and the user swipes again — which un-pins it.

    func create() async -> Conversation? {
        do {
            let fresh: Conversation = try await client.send(
                "api/native/chat/conversations",
                method: "POST",
                body: try JSONEncoder().encode(["title": "New thread"])
            )
            conversations.insert(fresh, at: pinned.count)
            SRHaptic.ok()
            return fresh
        } catch {
            message = error.localizedDescription
            SRHaptic.bad()
            return nil
        }
    }

    func togglePin(_ conversation: Conversation) async {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        let wanted = !conversations[index].pinned
        conversations[index].pinned = wanted
        // Re-sort locally so the row moves to the group its new state belongs
        // in. Without this the pinned row keeps its old position until the next
        // load and appears under `Recent` with a pin on it.
        conversations.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return (a.updatedAt ?? "") > (b.updatedAt ?? "")
        }
        await patch(conversation.id, ["pinned": wanted], revertingTo: !wanted, at: conversation.id)
    }

    func rename(_ conversation: Conversation, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let previous = conversation.title
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index].title = trimmed
        }
        do {
            let _: EmptyReply = try await client.send(
                "api/native/chat/conversations/\(conversation.id)",
                method: "PATCH",
                body: try JSONEncoder().encode(["title": trimmed])
            )
        } catch {
            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[index].title = previous
            }
            message = error.localizedDescription
        }
    }

    func delete(_ conversation: Conversation) async {
        let snapshot = conversations
        conversations.removeAll { $0.id == conversation.id }
        do {
            let _: EmptyReply = try await client.send(
                "api/native/chat/conversations/\(conversation.id)",
                method: "DELETE"
            )
            SRHaptic.ok()
        } catch {
            conversations = snapshot
            message = error.localizedDescription
            SRHaptic.bad()
        }
    }

    private func patch(_ id: String, _ body: [String: Bool], revertingTo previous: Bool, at rowId: String) async {
        do {
            let _: EmptyReply = try await client.send(
                "api/native/chat/conversations/\(id)",
                method: "PATCH",
                body: try JSONEncoder().encode(body)
            )
        } catch {
            if let index = conversations.firstIndex(where: { $0.id == rowId }) {
                conversations[index].pinned = previous
            }
            message = error.localizedDescription
        }
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
    /// A plan or a question the phone CAN answer. See `ChatGates.swift`.
    @Published private(set) var plan: PlanGate?
    @Published private(set) var clarify: ClarifyGate?
    @Published private(set) var answering = false
    /// Files picked for the next turn. See `PendingAttachment`.
    @Published private(set) var pending: [PendingAttachment] = []
    @Published var message: String?
    /// Bumped on every frame that changes what is on screen.
    ///
    /// The transcript follows the stream by scrolling to its foot, and the only
    /// signal it had was `messages.count` — which stops moving the instant the
    /// assistant bubble exists. Every token after that appended to a bubble the
    /// view never scrolled to, so a long answer wrote itself off the bottom of
    /// the screen while the reader looked at the top of it. A counter is the
    /// cheapest thing that moves once per frame and cannot loop: nothing that
    /// reads it writes it.
    @Published private(set) var streamTick = 0

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

    // MARK: - Attachments

    /// The server's ceiling on one turn.
    static let maxAttachments = 10

    var canAttachMore: Bool { pending.count < Self.maxAttachments }

    /// A send waits for uploads rather than dropping them. Sending with a photo
    /// still on its way would ask jkai about a picture it never received.
    var uploading: Bool { pending.contains { $0.state == .uploading } }

    func attach(_ data: Data, filename: String, mimeType: String, preview: UIImage? = nil) {
        guard canAttachMore else {
            message = "Ten files is the most one message can carry."
            return
        }
        let item = PendingAttachment(filename: filename, mimeType: mimeType, preview: preview)
        pending.append(item)
        Task { await upload(item, data: data) }
    }

    func attachPhoto(_ image: UIImage) {
        guard let photo = ChatUpload.photo(image) else {
            message = "That photo could not be read."
            return
        }
        // Named by when it was taken: every photo from the library is otherwise
        // "image.jpg", and they all land in the same /drive folder.
        let stamp = Self.photoStamp.string(from: Date())
        attach(photo.data, filename: "Photo \(stamp).jpg", mimeType: "image/jpeg", preview: photo.preview)
    }

    private static let photoStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return formatter
    }()

    func removePending(_ item: PendingAttachment) {
        pending.removeAll { $0.id == item.id }
    }

    private func upload(_ item: PendingAttachment, data: Data) async {
        let state: PendingAttachment.State
        do {
            let row: ChatAttachment = try await client.upload(
                "api/native/chat/attachments",
                file: data,
                filename: item.filename,
                mimeType: item.mimeType,
                fields: ["conversationId": conversationId]
            )
            if let preview = item.preview { AttachmentImages.shared.put(preview, for: row.id) }
            state = .ready(row)
        } catch {
            state = .failed(error.localizedDescription)
            message = error.localizedDescription
            SRHaptic.bad()
        }
        // Removed while it was uploading: nothing to update.
        guard let index = pending.firstIndex(where: { $0.id == item.id }) else { return }
        pending[index].state = state
    }

    // MARK: - Sending

    private struct JobStart: Decodable { let jobId: String? ; let error: String? }

    private struct TurnBody: Encodable {
        let message: String
        let conversationId: String
        let attachmentIds: [String]?
    }

    func send(_ text: String, extra: [ChatAttachment] = []) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sending, !uploading else { return }
        sending = true
        blocked = nil
        plan = nil
        clarify = nil
        activity = TurnActivity()

        // Only what actually arrived. A failed chip stays behind in the strip
        // with its warning, rather than silently vanishing with the send.
        let attached = pending.compactMap(\.uploaded) + extra
        pending.removeAll { $0.uploaded != nil }

        var userBubble = ChatMessage.pending(id: "local-user-\(UUID().uuidString)", role: "user", content: trimmed)
        userBubble.attachments = attached
        let assistantId = "local-assistant-\(UUID().uuidString)"
        messages.append(userBubble)
        messages.append(ChatMessage.pending(id: assistantId, role: "assistant", content: ""))
        liveBubbleId = assistantId

        do {
            let body = try JSONEncoder().encode(TurnBody(
                message: trimmed,
                conversationId: conversationId,
                attachmentIds: attached.isEmpty ? nil : attached.map(\.id)
            ))
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

        // The gates this app cannot answer. Naming them stops a turn hanging
        // silently with a spinner that never resolves.
        //
        // AND THEN LET GO OF THE STREAM. This is the fix for a silent hang that
        // was worse than the one the card was written for: the site escalates a
        // stalled turn to WhatsApp after a fifteen-second grace period, and it
        // skips the ping if anything still holds the job's SSE stream open. A
        // phone sitting on this card IS that subscriber. So the one case where
        // you most need to be told — a turn stopped, waiting on an answer only
        // the desk can give — was the one case where nothing told you.
        //
        // Dropping the socket takes the subscriber count to zero inside the
        // grace window, the escalation fires, and the message that arrives
        // carries the link. The turn is unaffected; it was already waiting.
        case "plan", "confirm", "clarify", "secret_request", "approval":
            // A plan and a question are answered on the phone now; the other
            // three still need the desk. A frame this app cannot read falls
            // back to the desk card rather than to nothing.
            if type == "plan", let gate = PlanGate(frame.json) {
                plan = gate
            } else if type == "clarify", let gate = ClarifyGate(frame.json) {
                clarify = gate
            } else {
                blocked = BlockedTurn(kind: type, detail: (frame.json["prompt"] as? String) ?? "")
            }
            park()
            // Scheduled rather than called: `stop()` cancels the task this
            // handler is running inside, and cancelling yourself mid-frame
            // throws through the middle of the loop.
            Task { [weak self] in self?.stop() }

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
        streamTick &+= 1
    }

    private func setLiveBubble(_ content: String) {
        guard let id = liveBubbleId, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
        streamTick &+= 1
    }

    /// Put a turn down without calling it finished.
    ///
    /// NOT `finish(with:)`. That one writes "*(no reply)*" into an empty bubble,
    /// which is the right thing to say about a turn that ended with nothing and
    /// exactly the wrong thing to say about one that is still waiting on you.
    /// It also plays the success haptic. Here the placeholder is removed and
    /// the card takes its place.
    private func park() {
        sending = false
        if let id = liveBubbleId { messages.removeAll { $0.id == id && $0.content.isEmpty } }
        liveBubbleId = nil
        activity = TurnActivity()
        streamTick &+= 1
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
        streamTick &+= 1
        if let error {
            message = error
            SRHaptic.bad()
        } else {
            // The one haptic that is worth it: an answer that finished while
            // the phone was in a pocket. Nothing fires per token — a buzzing
            // pocket for ninety seconds is a bug, not a flourish.
            SRHaptic.ok()
        }
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

    /// Pick a dropped stream back up.
    ///
    /// `stop()` cancels the socket and deliberately keeps `jobId` and
    /// `lastEventId`, so this is a reconnect rather than a restart — the server
    /// honours `Last-Event-ID` and replays only what was missed. Replaying the
    /// whole buffer into a handler that APPENDS is what silently doubled every
    /// bubble on the web client, which is why that header exists at all.
    ///
    /// A no-op unless a turn is actually in flight.
    func resume() {
        guard sending, streamTask == nil, let job = jobId else { return }
        listen(to: job)
    }

    // MARK: - Answering a gate

    private struct PlanAck: Encodable {
        let type = "plan_ack"
        let planId: String
        let decision: String
        let adjustment: String?
    }

    private struct ClarifyAck: Encodable {
        let type = "clarify_ack"
        let clarifyId: String
        let answers: [String: String]
    }

    func answerPlan(_ decision: String, adjustment: String?) async {
        guard let gate = plan else { return }
        await acknowledge(PlanAck(planId: gate.planId, decision: decision, adjustment: adjustment))
    }

    func answerClarify(_ answers: [String: String]) async {
        guard let gate = clarify else { return }
        await acknowledge(ClarifyAck(clarifyId: gate.clarifyId, answers: answers))
    }

    /// Send the answer, then pick the turn back up where it stopped.
    ///
    /// The job id and the last event id survived `park()` and `stop()` for
    /// exactly this: the reconnect replays only what came after the gate.
    private func acknowledge<Body: Encodable>(_ ack: Body) async {
        guard let job = jobId, !answering else { return }
        answering = true
        defer { answering = false }
        do {
            let _: EmptyReply = try await client.send(
                "api/workflows/orchestrator/chat?jobId=\(job)",
                method: "PATCH",
                body: try JSONEncoder().encode(ack)
            )
        } catch SiteError.status(let code, _) where code == 404 {
            // Answered at the desk already, or the turn gave up waiting.
            plan = nil
            clarify = nil
            jobId = nil
            message = "That was already answered, or the turn stopped waiting."
            await load()
            return
        } catch {
            message = error.localizedDescription
            SRHaptic.bad()
            return
        }
        plan = nil
        clarify = nil
        sending = true
        activity = TurnActivity()
        let assistantId = "local-assistant-\(UUID().uuidString)"
        messages.append(ChatMessage.pending(id: assistantId, role: "assistant", content: ""))
        liveBubbleId = assistantId
        streamTick &+= 1
        listen(to: job)
    }

    // MARK: - Voice notes

    /// Upload a recording and send it as its own turn.
    ///
    /// The chat endpoint will not take a turn with no words, and the web does
    /// not send one either, so a voice note goes out as "Voice note" with the
    /// audio attached. The site transcribes it before the model reads it.
    func sendVoiceNote(_ data: Data) async {
        guard !sending else { return }
        do {
            let row: ChatAttachment = try await client.upload(
                "api/native/chat/attachments",
                file: data,
                filename: "Voice note \(Self.photoStamp.string(from: Date())).m4a",
                mimeType: "audio/mp4",
                fields: ["conversationId": conversationId]
            )
            await send("Voice note", extra: [row])
        } catch {
            message = error.localizedDescription
            SRHaptic.bad()
        }
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
