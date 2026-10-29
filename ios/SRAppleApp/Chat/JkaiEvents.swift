import Foundation

// MARK: - The phone's jkai channel
//
// One server-sent-events stream per phone, `GET /api/jkai/events?scope=me`,
// open only while the app is in the foreground. It carries what happens to
// this person's threads AFTER a turn's own stream has ended, or on threads the
// phone is not streaming at all: a turn starting on the web, the desk
// analyst's and the red team's sections landing on an answer, a follow-up
// message, a gate opening or closing.
//
// This file is the rules: what a frame says, and what the app does about it.
// Foundation only, so the Linux harness (`scripts/chat-check.sh`) tests them;
// the connection itself is `JkaiLive` (`JkaiLive.swift`).
//
// Receiver-tolerant: an unknown `kind`, or a known one missing what it needs,
// is ignored. Keepalive comments (`: keepalive`, every 30 s) never reach here.

/// One frame from the channel.
enum JkaiEvent: Equatable {
    case connected
    /// A turn changed state: `running`, `gated`, `done`, `error`,
    /// `interrupted` or `cancelled`.
    case turn(conversationId: String, jobId: String, status: String)
    /// The analyst's or the red team's section for one answer row.
    case desk(conversationId: String, update: JkaiDeskUpdate)
    /// A follow-up message landed in a thread.
    case message(conversationId: String, role: String)
    case gate(conversationId: String, jobId: String, gate: String, open: Bool)

    static func parse(_ json: [String: Any]) -> JkaiEvent? {
        if json["type"] as? String == "connected" { return .connected }
        guard let kind = json["kind"] as? String,
              let conversation = json["conversationId"] as? String, !conversation.isEmpty else { return nil }
        switch kind {
        case "turn":
            guard let job = json["jobId"] as? String, let status = json["status"] as? String else { return nil }
            return .turn(conversationId: conversation, jobId: job, status: status)
        case "desk":
            guard let update = JkaiDeskUpdate(json) else { return nil }
            return .desk(conversationId: conversation, update: update)
        case "message":
            return .message(conversationId: conversation, role: json["role"] as? String ?? "assistant")
        case "gate":
            guard let job = json["jobId"] as? String, let gate = json["gate"] as? String,
                  let open = json["open"] as? Bool else { return nil }
            return .gate(conversationId: conversation, jobId: job, gate: gate, open: open)
        default:
            return nil
        }
    }

    static func parse(_ data: Data) -> JkaiEvent? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return parse(json)
    }

    var conversationId: String? {
        switch self {
        case .connected: return nil
        case .turn(let id, _, _), .desk(let id, _), .message(let id, _), .gate(let id, _, _, _): return id
        }
    }
}

/// A `desk` frame: one section of one answer's page.
struct JkaiDeskUpdate: Equatable {
    static let analyst = "analyst"
    static let redTeam = "red-team"

    /// The server's row id for the answer.
    let messageId: String
    /// `analyst` or `red-team` (an absent `section` is the red team).
    let section: String
    /// `running`, `partial`, `done` or `failed`.
    let phase: String
    let blocks: [PanelBlock]
    let headline: String?

    init(messageId: String, section: String, phase: String, blocks: [PanelBlock], headline: String? = nil) {
        self.messageId = messageId
        self.section = section
        self.phase = phase
        self.blocks = blocks
        self.headline = headline
    }

    init?(_ json: [String: Any]) {
        guard let messageId = json["messageId"] as? String, !messageId.isEmpty,
              let phase = json["phase"] as? String else { return nil }
        self.messageId = messageId
        section = (json["section"] as? String) == Self.analyst ? Self.analyst : Self.redTeam
        self.phase = phase
        headline = json["headline"] as? String
        // Each block on its own: one this build cannot read is skipped, as the
        // desk skips it anywhere else.
        var blocks: [PanelBlock] = []
        for raw in json["blocks"] as? [Any] ?? [] {
            guard JSONSerialization.isValidJSONObject(raw),
                  let data = try? JSONSerialization.data(withJSONObject: raw),
                  let block = try? JSONDecoder().decode(PanelBlock.self, from: data) else { continue }
            blocks.append(block)
        }
        self.blocks = blocks
    }

    /// The ops this section makes on the answer's page: SR-Jkai-Core's
    /// `deskFrameOps` (`panel/chat-desk.ts`), so the phone's page is the
    /// web's. The analyst appears only when done; the red team draws its
    /// partial verdicts and, when done, drops what the final one no longer
    /// has. `running` and `failed` change nothing on the page.
    func ops(on page: PanelPage?) -> [PanelOp] {
        let empty = !(page?.sections.contains { !$0.blocks.isEmpty } ?? false)
        if section == Self.analyst {
            guard phase == "done" else { return [] }
            var ops: [PanelOp] = []
            if empty {
                let title = String((headline ?? "Worth knowing").prefix(140))
                ops.append(.head(PanelHead(kicker: "Desk", context: [], title: title), producer: nil))
            }
            ops += blocks.map { .upsert(section: Self.analyst, sectionLabel: "Worth knowing", block: $0) }
            return ops
        }
        guard phase == "partial" || phase == "done" else { return [] }
        var ops: [PanelOp] = []
        if empty {
            ops.append(.head(PanelHead(kicker: "Red team", context: [], title: "A second look at this answer"), producer: nil))
        }
        ops += blocks.map { .upsert(section: Self.redTeam, sectionLabel: "Red team", block: $0) }
        if phase == "done" {
            let keep = Set(blocks.map(\.id))
            let stale = page?.sections.first { $0.id == Self.redTeam }?.blocks.filter { !keep.contains($0.id) } ?? []
            ops += stale.map { .remove(id: $0.id) }
        }
        return ops
    }

    /// The answer's page with this section on it, as the drawer shows it.
    func applied(to page: PanelPage?) -> PanelPage? {
        let ops = ops(on: page)
        guard !ops.isEmpty else { return page }
        return PanelReducer.shown(PanelReducer.apply(page, ops))
    }
}

/// What a thread row shows besides its title: one small dot, at most.
enum JkaiRowMark: String, Equatable {
    /// A turn is running in it.
    case running
    /// A turn in it is waiting on an answer.
    case waiting
    /// Something new arrived since it was last open.
    case reply
}

/// What the app does with one event.
enum JkaiEventAction: Equatable {
    /// The thread list's dot: running (true) or not.
    case running(conversationId: String, Bool)
    case mark(conversationId: String, JkaiRowMark)
    case unmark(conversationId: String, JkaiRowMark)
    /// An open thread re-reads itself.
    case reload(conversationId: String)
    /// An open thread asks the server about its turn and attaches to it —
    /// a turn started on the web, or a gate that opened or closed.
    case probe(conversationId: String)
    /// An open thread finished a turn it may have been streaming: re-read,
    /// unless that turn's own stream is handling it.
    case turnEnded(conversationId: String, jobId: String)
    /// An open thread puts a section on an answer's page.
    case desk(conversationId: String, JkaiDeskUpdate)

    /// `open`: the threads on screen (a `ChatScreen` is showing them).
    static func route(_ event: JkaiEvent, open: Set<String>) -> [JkaiEventAction] {
        switch event {
        case .connected:
            return []
        case .turn(let id, let job, let status):
            let live = status == "running" || status == "gated"
            var out: [JkaiEventAction] = [.running(conversationId: id, live)]
            if open.contains(id) {
                out.append(live ? .probe(conversationId: id) : .turnEnded(conversationId: id, jobId: job))
            } else if !live {
                out.append(.unmark(conversationId: id, .waiting))
            }
            return out
        case .message(let id, _):
            return open.contains(id) ? [.reload(conversationId: id)] : [.mark(conversationId: id, .reply)]
        case .gate(let id, _, _, let isOpen):
            if open.contains(id) { return [.probe(conversationId: id)] }
            return [isOpen ? .mark(conversationId: id, .waiting) : .unmark(conversationId: id, .waiting)]
        case .desk(let id, let update):
            // A closed thread has the section stored on its row already; the
            // next open shows it. Nothing to mark: it is not a new message.
            return open.contains(id) ? [.desk(conversationId: id, update)] : []
        }
    }

    /// The marks a thread row carries, newest rule last: a running turn
    /// outranks a waiting one, which outranks a reply.
    static func strongest(_ marks: Set<JkaiRowMark>) -> JkaiRowMark? {
        if marks.contains(.running) { return .running }
        if marks.contains(.waiting) { return .waiting }
        if marks.contains(.reply) { return .reply }
        return nil
    }
}

/// The channel's resume point and reconnect count.
///
/// Like `TurnStreamResume`, without a job to lose: a drop reconnects with
/// `Last-Event-ID` and the same backoff, and once the backoff is spent the
/// channel waits for the app's next return to the foreground. A refusal
/// (403, 404, 401) closes it until then too: the server does not have it.
///
/// Deduped by the ids seen, not by a high-water mark: the server's seqs commit
/// out of order, so 104 can arrive after 105 and is still news. A reconnect
/// sends the highest id seen as `Last-Event-ID`, and the server replays from
/// `window` behind it (its `LOOKBACK`), so what the phone already had comes
/// again and is dropped here. Bounded like the server's own record: an id
/// `window` or more below the highest is forgotten and refused, because the
/// server no longer looks that far back either.
struct JkaiEventsResume: Equatable {
    /// The server's `LOOKBACK` (`events.server.ts`).
    static let window = 200

    /// The highest id seen: the next connection's `Last-Event-ID`.
    private(set) var lastEventId: Int?
    private(set) var attempts = 0
    private var seen: Set<Int> = []

    /// Whether a frame is new: one already seen is a replay.
    mutating func accept(_ id: Int?) -> Bool {
        guard let id else { return true }
        let high = lastEventId ?? Int.min
        if lastEventId != nil, id <= high - Self.window { return false }
        guard seen.insert(id).inserted else { return false }
        if id > high {
            lastEventId = id
            let floor = id - Self.window
            seen = seen.filter { $0 > floor }
        }
        attempts = 0
        return true
    }

    enum Next: Equatable {
        case reconnect(after: TimeInterval)
        /// Stop until the next foreground.
        case stop
    }

    mutating func next(afterStatus status: Int?) -> Next {
        if let status, (400..<500).contains(status), status != 408, status != 429 { return .stop }
        guard attempts < TurnStreamResume.backoff.count else { return .stop }
        let wait = TurnStreamResume.backoff[attempts]
        attempts += 1
        return .reconnect(after: wait)
    }

    mutating func restart() {
        attempts = 0
    }
}
