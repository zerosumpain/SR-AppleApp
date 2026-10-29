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
            // Not while viewing as somebody: Spotlight on this phone is the
            // owner's, and their threads must not land in it.
            if reset && term.isEmpty && AccessStore.shared.viewingAs == nil && !SRDemo.isOn { ThreadIndex.update(conversations) }
            // Which of them have a turn running, for the rows' dots.
            if reset { await JkaiLive.shared.refreshActive() }
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
    /// A voice note being read on the phone before it is sent.
    @Published private(set) var transcribing = false
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
    /// The id of the bubble currently being streamed into.
    private var liveBubbleId: String?

    init(conversationId: String) {
        self.conversationId = conversationId
    }

    func load() async {
        // Not over a turn being streamed. The screen reloads every time it
        // reappears — a tab switch mid-answer — and replacing the transcript
        // then threw away the live bubble the reconnect was about to write
        // into. The turn's own `done` reloads once it has finished.
        guard !loading, liveBubbleId == nil else { return }
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
        attachEncoded(photo)
    }

    /// A photo's file bytes, from the library or Files: read down to size and
    /// re-encoded off the main thread, which a 48-megapixel HEIC held for
    /// most of a second per photo.
    func attachPhoto(data: Data) async {
        let photo = await Task.detached(priority: .userInitiated) { () -> (data: Data, preview: UIImage)? in
            ChatUpload.downscaled(data).flatMap(ChatUpload.photo)
        }.value
        guard let photo else {
            message = "That photo could not be read."
            return
        }
        attachEncoded(photo)
    }

    private func attachEncoded(_ photo: (data: Data, preview: UIImage)) {
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
    //
    // A send is a `TurnRequest`: built once, with its own `requestId`, and
    // POSTed as the same bytes however many times it takes. The server
    // (`onceChatRequest`) answers a repeat with the first answer, so a send
    // whose reply was lost on a train is retried into ONE turn — never two.

    /// A send that did not get through, kept so "Try again" sends the SAME
    /// request rather than a new one.
    struct FailedSend: Equatable {
        let request: TurnRequest
        let attachments: [ChatAttachment]
        /// The question's bubble, left on screen so the reader can see what
        /// did not go. The retry takes it away and draws the turn afresh.
        let bubbleId: String
        /// Set when the server answered `pending` (409): when the first
        /// attempt was made, for `PendingSend.decide`. Nil for other failures.
        var pendingSince: Date? = nil
        /// Fresh-id re-sends already made for this message.
        var freshRetries = 0
    }

    @Published private(set) var failedSend: FailedSend?

    /// `refs`: what an "Ask jkai" hand-over is about (a capture, a note, a
    /// trip day, a health day), sent once with this message.
    func send(_ text: String, extra: [ChatAttachment] = [], refs: [TurnRef] = []) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sending, !uploading else { return }
        // Only what actually arrived. A failed chip stays behind in the strip
        // with its warning, rather than silently vanishing with the send.
        let attached = pending.compactMap(\.uploaded) + extra
        pending.removeAll { $0.uploaded != nil }
        let request = TurnRequest(
            message: trimmed,
            conversationId: conversationId,
            attachmentIds: attached.isEmpty ? nil : attached.map(\.id),
            // Where it was sent from, read once so a retry is the same bytes.
            envelope: .phone(refs: refs)
        )
        await start(request, attachments: attached)
    }

    /// "Try again" on a send that did not get through: the same request, so
    /// a first attempt that DID reach the server is answered, not repeated.
    ///
    /// Except after a `pending` answer: the same id would only be answered
    /// `pending` again, forever. Then the thread decides (`PendingSend`).
    func retryFailedSend() async {
        guard let failed = failedSend, !sending else { return }
        guard let since = failed.pendingSince else {
            messages.removeAll { $0.id == failed.bubbleId }
            await start(failed.request, attachments: failed.attachments)
            return
        }
        failedSend = nil
        messages.removeAll { $0.id == failed.bubbleId }
        await load()
        let rows = messages.map { PendingSend.Row(role: $0.role, content: $0.content, createdAt: $0.createdAt) }
        switch PendingSend.decide(request: failed.request, firstTriedAt: since,
                                  freshRetriesUsed: failed.freshRetries, thread: rows) {
        case .arrived:
            message = "That message arrived — it is in the thread above."
        case .resend(let fresh):
            await start(fresh, attachments: failed.attachments,
                        pendingSince: since, freshRetries: failed.freshRetries + 1)
        case .giveUp(let reason):
            message = reason
            SRHaptic.bad()
        }
    }

    private func start(_ request: TurnRequest, attachments: [ChatAttachment],
                       pendingSince: Date? = nil, freshRetries: Int = 0) async {
        let attemptedAt = Date()
        sending = true
        blocked = nil
        plan = nil
        clarify = nil
        failedSend = nil
        message = nil
        activity = TurnActivity()

        var userBubble = ChatMessage.pending(id: "local-user-\(UUID().uuidString)", role: "user", content: request.message)
        userBubble.attachments = attachments
        let assistantId = "local-assistant-\(UUID().uuidString)"
        messages.append(userBubble)
        messages.append(ChatMessage.pending(id: assistantId, role: "assistant", content: ""))
        liveBubbleId = assistantId
        livePage = nil

        let body: Data
        do {
            body = try request.body()
        } catch {
            finish(with: error.localizedDescription)
            return
        }
        switch await post(body) {
        case .started(let job):
            begin(job)
        case .refused(let reason):
            finish(with: reason)
        case .expired:
            finish(with: "This iPhone needs pairing again.")
        case .notSent(let reason):
            notSent(request, attachments: attachments, bubbleId: userBubble.id, reason: reason)
        case .stillPending:
            // The server holds this send and has not finished accepting it —
            // it may have started a turn. Re-read the thread rather than guess;
            // "Try again" stays, and is safe, because it is the same request.
            // "Try again" then re-reads the thread and re-sends at most once
            // under a fresh id (`retryFailedSend`), never this id forever.
            let reason = "That message is still being accepted. Check the thread before sending it again."
            notSent(request, attachments: attachments, bubbleId: userBubble.id, reason: reason)
            failedSend?.pendingSince = pendingSince ?? attemptedAt
            failedSend?.freshRetries = freshRetries
            await load()
            // `load` clears the banner on success; put the reason back.
            if freshRetries >= PendingSend.freshRetryCap {
                // Already re-sent once and still stuck: no more "Try again".
                failedSend = nil
                message = PendingSend.giveUpMessage
            } else {
                message = reason
            }
        }
    }

    private enum PostOutcome: Equatable {
        case started(String)
        case refused(String)
        case expired
        case notSent(String)
        case stillPending
    }

    /// POST one send, retrying the network and a release-in-progress a couple
    /// of times, and a `pending` answer as the server asks.
    private func post(_ body: Data) async -> PostOutcome {
        var retries = 0
        var pendings = 0
        while true {
            do {
                let reply = try await client.postTurn(body)
                switch TurnStart.classify(status: reply.status, body: reply.body, retryAfter: reply.retryAfter) {
                case .started(let job):
                    return .started(job)
                case .refused(let reason):
                    return .refused(reason)
                case .pending(let wait):
                    pendings += 1
                    guard pendings < TurnStart.pendingTries else { return .stillPending }
                    try? await Task.sleep(for: .seconds(wait))
                case .unavailable(let reason):
                    guard retries < TurnStart.retryDelays.count else { return .notSent(reason) }
                    try? await Task.sleep(for: .seconds(TurnStart.retryDelays[retries]))
                    retries += 1
                }
            } catch SiteError.expired {
                return .expired
            } catch {
                guard Self.isNetwork(error) else { return .refused(error.localizedDescription) }
                guard retries < TurnStart.retryDelays.count else {
                    return .notSent("Not sent: \(error.localizedDescription)")
                }
                try? await Task.sleep(for: .seconds(TurnStart.retryDelays[retries]))
                retries += 1
            }
        }
    }

    /// The send did not get through. The question stays on screen with
    /// "Try again" in the banner; the empty answer under it goes.
    private func notSent(_ request: TurnRequest, attachments: [ChatAttachment], bubbleId: String, reason: String) {
        if let id = liveBubbleId { messages.removeAll { $0.id == id } }
        liveBubbleId = nil
        livePage = nil
        sending = false
        activity = TurnActivity()
        failedSend = FailedSend(request: request, attachments: attachments, bubbleId: bubbleId)
        message = reason
        streamTick &+= 1
        SRHaptic.bad()
    }

    private static func isNetwork(_ error: Error) -> Bool {
        let ns = error as NSError
        return TurnStreamResume.isNetwork(domain: ns.domain, code: ns.code)
    }

    // MARK: - The stream
    //
    // One turn's frames, kept alive across a bad network. A drop reconnects
    // from the last frame handled (`Last-Event-ID`), so nothing is appended
    // twice; a job the server no longer holds re-reads the thread, which has
    // whatever it saved. What this cannot do is outlive the turn: the server
    // ends a turn at its own limits (ten minutes for an ordinary one), and
    // reconnecting after that finds the thread, not the turn.

    /// Turns that were running when the app last went away. Not in a demo:
    /// its jobs live in memory and are gone with the app.
    private let activeTurns = ActiveTurns()
    /// Where the stream got to, and how often in a row it has had to reconnect.
    private var streamResume = TurnStreamResume()
    /// This turn was picked up again after a relaunch and is being replayed
    /// from its start. See `GateHold`.
    private var rejoining = false
    private var gateHold = GateHold()
    private var heldGate: SiteClient.StreamFrame?
    private var gateTimer: Task<Void, Never>?
    /// The live turn's desk page, as reduced from its `panel` frames —
    /// including blocks the phone does not draw. The bubble carries the
    /// shown version (`PanelReducer.shown`).
    private var livePage: PanelPage?

    private func begin(_ job: String) {
        jobId = job
        streamResume = TurnStreamResume()
        rejoining = false
        if !SRDemo.isOn { activeTurns.record(job, for: conversationId) }
        listen(to: job)
    }

    // MARK: - A turn running anywhere
    //
    // The server knows every turn on a thread, wherever it was started — the
    // web, another phone, this one before it was killed — and answers
    // `GET /chat/active?conversationId=` with it (`ActiveTurnProbe`). That
    // answer wins over the phone's own `ActiveTurns` hint, which is only
    // asked when the server cannot be (an older site, no network).

    /// Set while a turn attached from the server's answer is streaming: what
    /// the server had of its reply then, for if the stream loses the job.
    private var attachedPartial: String?
    /// A gate card is up and its stream is still held open, because the phone
    /// is beating presence (see the gates in `handle`).
    private var gateOnStream = false

    /// Ask the server whether this thread has a turn running, and join it.
    ///
    /// After the thread loads, on returning to the foreground, and when the
    /// phone's channel says a turn started or a gate moved. Nothing happens
    /// over a send or a stream already in flight.
    func rejoin() async {
        // Not in a demo: its jobs live in memory and are gone with the app.
        guard !SRDemo.isOn, !sending, streamTask == nil else { return }
        guard let probe = await probeActive() else {
            // An older site, or no network: the phone's own hint is all there is.
            rejoinIfRunning()
            return
        }
        JkaiLive.shared.note(probe.features)
        JkaiLive.shared.setRunning(conversationId, probe.liveJob != nil)
        if presenceTask != nil && lastBeat == nil { Task { await beat() } }
        let local = TurnRejoin.Local(
            busy: sending || streamTask != nil,
            jobId: jobId,
            gateShown: plan != nil || clarify != nil || blocked != nil,
            hint: activeTurns.entry(for: conversationId)?.jobId
        )
        switch TurnRejoin.decide(probe, local: local) {
        case .nothing:
            // Sitting on a gate with the stream let go (the screen went away
            // for a moment): hold it again while presence says the phone is open.
            if local.gateShown, let job = jobId, keepsStreamAtGate, streamTask == nil {
                gateOnStream = true
                listen(to: job)
            }
        case .attach(let job, _, let partial):
            attach(job, gate: probe.openGate, turn: probe.turn, partialText: partial)
        case .carryOn(let job):
            continueTurn(job)
        case .reload:
            // Nothing is running: what the turn saved is in the thread — an
            // interrupted turn's partial reply included, as a row of its own.
            plan = nil
            clarify = nil
            blocked = nil
            if let job = jobId ?? local.hint { activeTurns.clear(conversationId, jobId: job) }
            jobId = nil
            await load()
        }
    }

    private func probeActive() async -> ActiveTurnProbe? {
        let id = conversationId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? conversationId
        guard let reply = try? await client.exchange("api/workflows/orchestrator/chat/active?conversationId=\(id)", method: "GET"),
              (200..<300).contains(reply.1.statusCode) else { return nil }
        return ActiveTurnProbe.read(reply.0)
    }

    /// Join a turn the server says is running.
    ///
    /// With a gate open and the server's place in the stream known, the card
    /// goes up at once over what the turn had said so far, and the stream
    /// (held only with presence) picks up after the gate. Otherwise a fresh
    /// bubble and a full replay from the first frame — safe, because the
    /// bubble is new — with any gate in it held until the replay settles
    /// (`GateHold`).
    private func attach(_ job: String, gate: ActiveTurnProbe.OpenGate?, turn: ActiveTurnProbe.Turn?, partialText: String) {
        plan = nil
        clarify = nil
        blocked = nil
        message = nil
        failedSend = nil
        jobId = job
        livePage = nil
        gateOnStream = false
        gateTimer?.cancel(); gateTimer = nil
        heldGate = nil

        if let gate, let seq = turn?.resumePoint, turn?.jobId == job {
            if !partialText.isEmpty {
                messages.append(ChatMessage.pending(id: "local-assistant-\(UUID().uuidString)", role: "assistant", content: partialText))
            }
            showGate(gate.frame)
            sending = false
            activity = TurnActivity()
            liveBubbleId = nil
            rejoining = false
            streamResume = TurnStreamResume(lastEventId: seq)
            streamTick &+= 1
            if keepsStreamAtGate {
                gateOnStream = true
                listen(to: job)
            }
            return
        }

        sending = true
        activity = TurnActivity()
        activity.status = "Picking the turn up…"
        let assistantId = "local-assistant-\(UUID().uuidString)"
        messages.append(ChatMessage.pending(id: assistantId, role: "assistant", content: ""))
        liveBubbleId = assistantId
        attachedPartial = partialText.isEmpty ? nil : partialText
        streamResume = TurnStreamResume()
        rejoining = true
        gateHold = GateHold()
        streamTick &+= 1
        listen(to: job)
    }

    /// The channel says a thread's turn ended. The stream that was following
    /// it already knows; otherwise re-read the thread for what it saved.
    func serverTurnEnded(jobId job: String) async {
        guard !sending, streamTask == nil || gateOnStream else { return }
        if jobId == job {
            stop()
            gateOnStream = false
            plan = nil
            clarify = nil
            blocked = nil
            jobId = nil
        }
        activeTurns.clear(conversationId, jobId: job)
        await load()
    }

    /// The channel says something new landed in this thread.
    func reloadFromServer() async {
        guard !sending else { return }
        await load()
    }

    /// The channel's analyst or red-team section for one answer: onto that
    /// answer's page, the way the web's desk puts it there (`JkaiDeskUpdate`).
    /// An answer not on screen under its server id — still a local bubble,
    /// or older than the page — is re-read instead, once the turn is over:
    /// the row holds the section already.
    func applyDesk(_ update: JkaiDeskUpdate) {
        guard let index = messages.firstIndex(where: { $0.id == update.messageId }) else {
            if !sending, !update.ops(on: nil).isEmpty { Task { await load() } }
            return
        }
        let next = update.applied(to: messages[index].panel)
        guard next != messages[index].panel else { return }
        messages[index].panel = next
    }

    /// Red-team one answer (owner only): `POST /api/jkai/conversations/<id>/red-team`.
    /// The site stores the section on the answer's row, so a re-read shows it.
    func redTeam(messageId: String) async -> DeskRedTeamOutcome {
        do {
            let body = try JSONEncoder().encode(["messageId": messageId])
            let (_, response) = try await client.exchange(
                "api/jkai/conversations/\(conversationId)/red-team", method: "POST", body: body, timeout: 120
            )
            switch response.statusCode {
            case 200..<300:
                await load()
                return .done
            case 403:
                JkaiLive.shared.redTeamRefused = true
                return .refused
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    // MARK: - Presence
    //
    // While the thread is on screen, the phone says so every fifteen seconds
    // (`POST /chat/presence`), and stops the moment it is not. The server
    // holds a gate's WhatsApp nudge while the beats come and sends it within
    // about thirty seconds of them stopping. Only on a server that reads them
    // (`features.presence`).

    static let presenceEvery: TimeInterval = 15
    private var presenceTask: Task<Void, Never>?
    private var lastBeat: Date?

    func startPresence() {
        guard presenceTask == nil, !SRDemo.isOn else { return }
        presenceTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.beat()
                try? await Task.sleep(for: .seconds(ChatStore.presenceEvery))
            }
        }
    }

    func stopPresence() {
        presenceTask?.cancel()
        presenceTask = nil
        lastBeat = nil
        // A gate's stream was held only because the phone was open. It is not
        // now, so let it go: the server's nudge goes out as it used to.
        if gateOnStream {
            gateOnStream = false
            stop()
        }
    }

    /// At a gate, keep the stream: the beats, not the socket, now tell the
    /// server the phone is open.
    private var keepsStreamAtGate: Bool { JkaiLive.shared.features.presence && presenceTask != nil }

    private func beat() async {
        guard JkaiLive.shared.features.presence, AccessStore.shared.viewingAs == nil, client.isPaired else { return }
        guard let body = try? JSONEncoder().encode(["conversationId": conversationId, "surface": "ios"]) else { return }
        lastBeat = Date()
        _ = try? await client.call("api/workflows/orchestrator/chat/presence", method: "POST", body: body)
    }

    /// A turn this phone started, still running when the app was killed or
    /// the thread closed: pick it up again. Only when the server cannot be
    /// asked (`rejoin()`).
    ///
    /// Only when the thread ends with the question — if the answer is already
    /// there, the turn finished and there is nothing to rejoin. It is replayed
    /// from its first frame into a fresh bubble, which is safe because the
    /// bubble is new; a gate in that replay is held until the replay settles
    /// (`GateHold`), so one answered at the desk meanwhile is not shown again.
    private func rejoinIfRunning() {
        guard !sending, jobId == nil, !SRDemo.isOn, let entry = activeTurns.entry(for: conversationId) else { return }
        guard let last = messages.last, last.isUser else {
            activeTurns.clear(conversationId, jobId: entry.jobId)
            return
        }
        sending = true
        activity = TurnActivity()
        activity.status = "Picking the turn back up…"
        let assistantId = "local-assistant-\(UUID().uuidString)"
        messages.append(ChatMessage.pending(id: assistantId, role: "assistant", content: ""))
        liveBubbleId = assistantId
        livePage = nil
        jobId = entry.jobId
        streamResume = TurnStreamResume()
        rejoining = true
        gateHold = GateHold()
        streamTick &+= 1
        listen(to: entry.jobId)
    }

    private func listen(to job: String) {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.follow(job)
        }
    }

    /// What a connection's frames came to.
    private enum Stop {
        /// `done` or `error`: the turn is over and `finish` has run.
        case finished
        /// A gate: the turn waits on an answer and the stream is let go.
        case parked
        case failed(TurnStreamFailure)
    }

    /// Connect, read, and — on a drop — wait and connect again from the last
    /// frame handled, until the turn ends, waits on a gate, or is gone.
    private func follow(_ job: String) async {
        while !Task.isCancelled {
            let stop = await connect(job)
            if Task.isCancelled { return }
            switch stop {
            case .finished, .parked:
                streamTask = nil
                return
            case .failed(let failure):
                switch streamResume.next(after: failure) {
                case .reconnect(let wait):
                    if !gateOnStream {
                        activity.status = "Reconnecting…"
                        streamTick &+= 1
                    }
                    try? await Task.sleep(for: .seconds(wait))
                case .reload:
                    await jobGone()
                    return
                case .expired:
                    finish(with: "This iPhone needs pairing again.")
                    streamTask = nil
                    return
                case .fail(let reason):
                    finish(with: reason)
                    streamTask = nil
                    return
                case .wait:
                    // Out of tries for now, and the turn may well still be
                    // running. Keep it — `resume()` picks it up from here when
                    // the app or the screen comes back.
                    activity.status = "Waiting for the connection…"
                    streamTick &+= 1
                    streamTask = nil
                    return
                }
            }
        }
    }

    /// One connection.
    private func connect(_ job: String) async -> Stop {
        // Whether the server answered, and whether it said anything after
        // that: a timeout with the first and not the second is `.silent`.
        var opened = false
        var heardSomething = false
        do {
            let stream = try client.stream(jobId: job, after: streamResume.lastEventId)
            for try await frame in stream {
                if Task.isCancelled { return .parked }
                let type = frame.json["type"] as? String ?? ""
                if TurnStreamResume.isKeepalive(type) { opened = true } else { heardSomething = true }
                switch handle(frame) {
                case .more: continue
                case .finished: return .finished
                case .parked: return .parked
                case .gone: return .failed(.jobGone)
                }
            }
            return .failed(.closedEarly)
        } catch is CancellationError {
            return .parked
        } catch SiteError.expired {
            return .failed(.expired)
        } catch SiteError.status(let code, _) {
            return .failed(.status(code))
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return .parked }
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorTimedOut && opened && !heardSomething { return .failed(.silent) }
            if TurnStreamResume.isNetwork(domain: ns.domain, code: ns.code) { return .failed(.network) }
            return .failed(.other(error.localizedDescription))
        }
    }

    private enum FrameOutcome { case more, finished, parked, gone }

    private func handle(_ frame: SiteClient.StreamFrame) -> FrameOutcome {
        // A frame at or before the resume point was handled on an earlier
        // connection. Handling it again is how a reconnect doubles the text.
        guard streamResume.accept(frame.id) else { return .more }
        guard let type = frame.json["type"] as? String else { return .more }
        if TurnStreamResume.isJobGone(type: type, message: frame.json["message"] as? String) { return .gone }

        // A gate held open on the stream, answered somewhere else (the desk,
        // another phone): the turn is moving again, so the card goes and a
        // fresh bubble takes what follows.
        if gateOnStream, !GateHold.gates.contains(type), type != "heartbeat", type != "connected" {
            gateOnStream = false
            openBubbleAfterGate()
        }

        // A rejoined turn's replay: a gate waits until the replay shows
        // whether the turn moved on past it.
        if rejoining {
            if gateHold.note(type) {
                heldGate = frame
                holdGate()
                return .more
            }
            if gateHold.held == nil, heldGate != nil {
                heldGate = nil
                gateTimer?.cancel(); gateTimer = nil
            }
        }

        switch type {
        case "connected":
            return .more

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
            // Not under a card: a gate's heartbeats only say it is still waiting.
            if !gateOnStream { activity.status = frame.json["summary"] as? String }

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

        case "panel":
            // The desk, live: one op on this turn's page (`PanelReducer`).
            // An op this build cannot read is a no-op.
            guard let op = try? JSONDecoder().decode(PanelFrame.self, from: frame.data).op, op != .ignored else { return .more }
            livePage = PanelReducer.apply(livePage, op)
            setLivePanel(PanelReducer.shown(livePage))

        // A gate: a card the phone can answer (plan, question) or one that
        // names what the desk must answer. Naming them stops a turn hanging
        // silently with a spinner that never resolves.
        //
        // What happens to the stream depends on the server.
        //
        // WITHOUT PRESENCE (`features.presence` off, or an older site): LET GO
        // OF THE STREAM. The site escalates a stalled turn to WhatsApp after a
        // fifteen-second grace period, and it skips the ping if anything still
        // holds the job's SSE stream open. A phone sitting on this card IS that
        // subscriber — so the one case where you most need to be told, a turn
        // waiting on an answer, was the one case where nothing told you.
        // Dropping the socket takes the subscriber count to zero inside the
        // grace window, the escalation fires, and the message carries the
        // link. The turn is unaffected; it was already waiting. (`.parked`
        // ends the connection's loop, which drops the socket.)
        //
        // WITH PRESENCE: KEEP IT. The site now decides on the phone's presence
        // beats, not on the socket: while this screen is open and beating, the
        // nudge is held (you are looking at the card); once the beats stop —
        // the screen closed, the phone pocketed — it goes out within about
        // thirty seconds. Holding the stream means a gate answered at the desk
        // carries straight on here (`gateOnStream` above), and `stopPresence()`
        // lets the stream go the moment the beats stop.
        case "plan", "confirm", "clarify", "secret_request", "approval":
            openGate(frame)
            if keepsStreamAtGate {
                gateOnStream = true
                return .more
            }
            return .parked

        case "done":
            let result = frame.json["result"] as? [String: Any] ?? [:]
            // `message` is what the server saved; `reply`/`content` are older
            // and demo shapes. The saved text wins over what was streamed.
            if let reply = Self.text(result, "message", "reply", "content") {
                setLiveBubble(reply)
            }
            switch PanelReducer.final(fromResult: result) {
            case .keep: break
            case .none:
                livePage = nil
                setLivePanel(nil)
            case .page(let page):
                setLivePanel(PanelReducer.shown(page))
            }
            finish(with: nil)
            Task { await refreshAfterTurn() }
            return .finished

        case "error":
            finish(with: frame.json["message"] as? String ?? "That turn failed.")
            return .finished

        default:
            return .more
        }
        return .more
    }

    private static func text(_ result: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let value = result[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    /// A plan and a question are answered on the phone now; the other three
    /// still need the desk. A frame this app cannot read falls back to the
    /// desk card rather than to nothing.
    private func openGate(_ frame: SiteClient.StreamFrame) {
        showGate(frame.json)
        park()
    }

    /// The card for a gate frame — from the stream, or the server's `openGate`.
    private func showGate(_ json: [String: Any]) {
        let type = json["type"] as? String ?? ""
        if type == "plan", let gate = PlanGate(json) {
            plan = gate
        } else if type == "clarify", let gate = ClarifyGate(json) {
            clarify = gate
        } else {
            blocked = BlockedTurn(kind: type, detail: (json["prompt"] as? String) ?? "")
        }
    }

    /// In a rejoin, believe a held gate once the replay has been quiet for a
    /// moment, and let go of the stream as a live gate does.
    private func holdGate() {
        gateTimer?.cancel()
        gateTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(GateHold.settle))
            guard !Task.isCancelled, let self, let frame = self.heldGate, self.gateHold.release() != nil else { return }
            self.heldGate = nil
            self.gateTimer = nil
            self.openGate(frame)
            if self.keepsStreamAtGate {
                self.gateOnStream = true
            } else {
                self.stop()
            }
        }
    }

    /// The server has let this job go — finished and cleared, or lost to a
    /// restart. The thread has whatever it saved, so read that.
    private func jobGone() async {
        flushTokens()
        // What the turn had said: the bubble's streamed text, or the server's
        // partial text from when the phone attached, whichever is longer.
        let streamed = liveBubbleId.flatMap { id in messages.first { $0.id == id }?.content } ?? ""
        let partial = [streamed, attachedPartial ?? ""].max { $0.count < $1.count } ?? ""
        attachedPartial = nil
        // A card held open on the stream is moot with the job gone.
        gateOnStream = false
        plan = nil
        clarify = nil
        blocked = nil
        if let job = jobId { activeTurns.clear(conversationId, jobId: job) }
        jobId = nil
        sending = false
        streamTask = nil
        if let id = liveBubbleId { messages.removeAll { $0.id == id && $0.content.isEmpty } }
        liveBubbleId = nil
        livePage = nil
        activity = TurnActivity()
        rejoining = false
        streamTick &+= 1
        await load()
        // Lost before anything was saved (a restart on a site without the
        // durable record, another slot): keep what it had said on screen
        // rather than leave the question looking unanswered.
        if !partial.isEmpty, messages.last?.isUser == true {
            messages.append(ChatMessage.pending(id: "local-assistant-\(UUID().uuidString)", role: "assistant", content: partial))
            streamTick &+= 1
        }
    }

    /// Deltas not yet in the bubble. Each one used to publish `messages`,
    /// which re-renders the thread: a fast model sends forty a second.
    private var tokenBuffer = ""
    private var tokenFlush: Task<Void, Never>?

    private func appendToLiveBubble(_ delta: String) {
        tokenBuffer += delta
        guard tokenFlush == nil else { return }
        tokenFlush = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(75))
            guard !Task.isCancelled else { return }
            self?.flushTokens()
        }
    }

    /// Into the bubble now. Before anything else reads or replaces it.
    private func flushTokens() {
        tokenFlush?.cancel(); tokenFlush = nil
        let text = tokenBuffer
        tokenBuffer = ""
        guard !text.isEmpty, let id = liveBubbleId, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += text
        streamTick &+= 1
    }

    private func setLiveBubble(_ content: String) {
        tokenBuffer = ""; tokenFlush?.cancel(); tokenFlush = nil
        guard let id = liveBubbleId, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
        streamTick &+= 1
    }

    /// The live answer's desk page, which the drawer pages to while it fills.
    private func setLivePanel(_ page: PanelPage?) {
        guard let id = liveBubbleId, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        guard messages[index].panel != page else { return }
        messages[index].panel = page
    }

    /// The bubble the stream is writing into, for the desk to follow.
    var liveMessageId: String? { liveBubbleId }

    /// Put a turn down without calling it finished.
    ///
    /// NOT `finish(with:)`. That one writes "*(no reply)*" into an empty bubble,
    /// which is the right thing to say about a turn that ended with nothing and
    /// exactly the wrong thing to say about one that is still waiting on you.
    /// It also plays the success haptic. Here the placeholder is removed and
    /// the card takes its place.
    private func park() {
        flushTokens()
        sending = false
        if let id = liveBubbleId { messages.removeAll { $0.id == id && $0.content.isEmpty } }
        liveBubbleId = nil
        activity = TurnActivity()
        rejoining = false
        streamTick &+= 1
    }

    private func finish(with error: String?) {
        flushTokens()
        sending = false
        if let job = jobId { activeTurns.clear(conversationId, jobId: job) }
        jobId = nil
        rejoining = false
        gateOnStream = false
        attachedPartial = nil
        gateTimer?.cancel(); gateTimer = nil
        heldGate = nil
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
        livePage = nil
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
    /// the turn keeps running and is picked up again by `resume()`, from the
    /// last frame handled.
    func stop() {
        streamTask?.cancel()
        streamTask = nil
    }

    /// Pick a dropped stream back up: the screen back on top, the app back in
    /// the foreground, or the connection given up on for a while.
    ///
    /// `stop()` and a run of failed reconnects both keep `jobId` and the
    /// resume point, so this is a reconnect rather than a restart — the server
    /// honours `Last-Event-ID` and replays only what was missed. Replaying the
    /// whole buffer into a handler that APPENDS is what silently doubled every
    /// bubble on the web client, which is why that header exists at all.
    ///
    /// A no-op unless a turn is actually in flight.
    func resume() {
        guard sending, streamTask == nil, let job = jobId else { return }
        streamResume.restart()
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
        // A stream held at the gate would start delivering the turn's next
        // frames the moment the answer lands, into a second bubble. Let it go;
        // the reconnect below resumes from the same place.
        if gateOnStream {
            gateOnStream = false
            stop()
        }
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
            blocked = nil
            activeTurns.clear(conversationId, jobId: job)
            jobId = nil
            message = "That was already answered, or the turn stopped waiting."
            await load()
            return
        } catch {
            message = error.localizedDescription
            SRHaptic.bad()
            return
        }
        continueTurn(job)
    }

    /// A gate answered (here or elsewhere): the card goes, a fresh bubble
    /// takes what follows, and the stream reconnects from where it stopped.
    private func continueTurn(_ job: String) {
        gateOnStream = false
        openBubbleAfterGate()
        listen(to: job)
    }

    private func openBubbleAfterGate() {
        plan = nil
        clarify = nil
        blocked = nil
        sending = true
        activity = TurnActivity()
        let assistantId = "local-assistant-\(UUID().uuidString)"
        messages.append(ChatMessage.pending(id: assistantId, role: "assistant", content: ""))
        liveBubbleId = assistantId
        streamTick &+= 1
    }

    // MARK: - Voice notes

    /// Upload a recording and send it as its own turn.
    ///
    /// Transcribed on the phone first (`VoiceTranscriber`): the words are the
    /// turn, so the model reads what was said and the thread is titled by it.
    /// The transcript also rides the upload, where the site files it as the
    /// audio's reading — without that, the site would try to transcribe the
    /// file itself and tell the model it "could not be read". With no words
    /// (no permission, silence), the note goes as "Voice note" and audio.
    func sendVoiceNote(_ data: Data) async {
        guard !sending else { return }
        transcribing = true
        let transcript = await VoiceTranscriber.transcribe(data)
        transcribing = false
        var fields = ["conversationId": conversationId]
        if let transcript { fields["transcript"] = transcript }
        do {
            let row: ChatAttachment = try await client.upload(
                "api/native/chat/attachments",
                file: data,
                filename: "Voice note \(Self.photoStamp.string(from: Date())).m4a",
                mimeType: "audio/mp4",
                fields: fields
            )
            await send(transcript ?? "Voice note", extra: [row])
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
