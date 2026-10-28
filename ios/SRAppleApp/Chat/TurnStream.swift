import Foundation

// MARK: - A chat turn that survives the network
//
// The rules a chat turn's send and stream follow, kept apart from `ChatStore`
// so they can be tested rather than eyeballed. Foundation only: the Linux
// harness (`scripts/chat-check.sh`) compiles and tests this file.
//
// What the server gives the phone to work with (SR-Jkai-Core):
//
// - `POST /api/workflows/orchestrator/chat` with a `requestId` is idempotent
//   (`onceChatRequest`): the same id and the same body return the first
//   answer, so a send retried after a lost reply is ONE turn, not two. A 409
//   with `pending: true` means the first attempt is still being accepted.
// - The stream tags every frame with `id: <seq>` and honours `Last-Event-ID`,
//   replaying only what came after it.
// - A job the server no longer holds streams `connected` and then
//   `{type:'error', message:'job not found'}` (owner), or 404s (member).
// - A running job sends a `heartbeat` frame every five seconds.
// - The job itself ends at ten minutes (`HARD_TIMEOUT_MS`), longer only while
//   a tool or a delegation runs. Reconnecting does not extend that: a turn the
//   server has ended is over, and the thread is reloaded to show what it saved.

/// Where a turn came from — SR-Jkai-Core's `TurnEnvelope`
/// (`site-tools/invoke-contract.ts`). The server picks jkai's length and
/// format from `surface` and labels the rows with it; the phone's clock lets
/// "tonight" mean where John is. Additive: a server that predates it ignores
/// it. `deviceId` is never sent — the server takes it from the credential.
struct TurnEnvelope: Encodable, Equatable {
    struct Client: Encodable, Equatable {
        let app: String
        let build: String?
    }

    let surface: String
    let locale: String?
    let tz: String?
    let client: Client?
    /// What the turn is about, by id. Nothing hands one over from the phone yet.
    let refs: [TurnRef]?
    /// Client tools the phone can run now: none (the device protocol is deferred).
    let capabilities: [String]

    /// The iPhone app's envelope, read once per send.
    static func phone(
        surface: String = "ios",
        info: [String: Any]? = Bundle.main.infoDictionary,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> TurnEnvelope {
        let build = (info?["CFBundleVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return TurnEnvelope(
            surface: surface,
            locale: bcp47(locale.identifier),
            tz: timeZone.identifier.isEmpty ? nil : timeZone.identifier,
            client: Client(app: "SRAppleApp", build: build),
            refs: nil,
            capabilities: []
        )
    }

    /// `en_GB@calendar=gregorian` → `en-GB`; nil for an identifier the server
    /// would drop anyway.
    static func bcp47(_ identifier: String) -> String? {
        let base = identifier.split(separator: "@").first.map(String.init) ?? ""
        let tag = base.replacingOccurrences(of: "_", with: "-")
        return tag.range(of: #"^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,3}$"#, options: .regularExpression) != nil ? tag : nil
    }
}

/// A thing handed over by id (`TurnEnvelope.refs`).
struct TurnRef: Encodable, Equatable {
    let kind: String
    let id: String
}

/// One send, as the POST body — built ONCE and kept, so every retry of it is
/// byte-for-byte the same request. The server fingerprints the whole body: a
/// retry that differed in anything (a re-ordered key, an attachment dropped)
/// would be refused as "a different message" rather than answered as the same.
/// The envelope is part of that body, so it too is read once, at send.
struct TurnRequest: Equatable {
    let requestId: String
    let message: String
    let conversationId: String
    let attachmentIds: [String]?
    let envelope: TurnEnvelope?

    private struct Wire: Encodable {
        let message: String
        let conversationId: String
        let attachmentIds: [String]?
        let requestId: String
        let envelope: TurnEnvelope?
    }

    init(
        message: String,
        conversationId: String,
        attachmentIds: [String]?,
        envelope: TurnEnvelope? = nil,
        requestId: String = TurnStart.newRequestId()
    ) {
        self.requestId = requestId
        self.message = message
        self.conversationId = conversationId
        self.attachmentIds = attachmentIds
        self.envelope = envelope
    }

    func body() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Wire(message: message, conversationId: conversationId, attachmentIds: attachmentIds, requestId: requestId, envelope: envelope))
    }
}

/// How a send's POST came back.
enum TurnStart: Equatable {
    case started(jobId: String)
    /// The same `requestId` is still being accepted. Ask again after the wait.
    case pending(retryAfter: TimeInterval)
    /// The site is between releases or overloaded. Safe to retry: the id makes
    /// a second attempt the same send.
    case unavailable(String)
    /// A refusal that a retry will not change.
    case refused(String)

    private struct Body: Decodable {
        let jobId: String?
        let error: String?
        let pending: Bool?
    }

    static func classify(status: Int, body: Data, retryAfter: String?) -> TurnStart {
        let decoded = try? JSONDecoder().decode(Body.self, from: body)
        switch status {
        case 200..<300:
            if let job = decoded?.jobId, !job.isEmpty { return .started(jobId: job) }
            return .refused(decoded?.error ?? "The server did not start that turn.")
        case 409 where decoded?.pending == true:
            let wait = retryAfter.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? 3
            return .pending(retryAfter: min(max(wait, 1), 10))
        case 502, 503, 504:
            return .unavailable(decoded?.error ?? "The site is not answering just now.")
        default:
            return .refused(decoded?.error ?? "\(status) from the server.")
        }
    }

    /// A send's id: a lowercase UUID, which is what the route's pattern and
    /// the receipts table's `uuid` column accept.
    static func newRequestId() -> String { UUID().uuidString.lowercased() }

    /// Waits before each automatic re-POST of the same send after a network
    /// failure or a 5xx. Short: the reader is watching the spinner, and the
    /// manual "Try again" (same id) covers anything longer.
    static let retryDelays: [TimeInterval] = [1, 3]
    /// How many times a `pending` answer is asked again before the thread is
    /// re-read instead.
    static let pendingTries = 3
}

/// Why a stream stopped, as far as what to do next is concerned.
enum TurnStreamFailure: Equatable {
    /// The connection dropped, timed out or could not be made.
    case network
    /// It closed without a `done` or `error` frame — a proxy hung up.
    case closedEarly
    /// The server answered (`connected`) and then said nothing for
    /// `TurnStreamResume.silence` seconds. A running job heartbeats every five,
    /// so a job that does this is not running: it finished after its replay
    /// buffer was dropped (a minute after the end), and the stream has nothing
    /// left to send it.
    case silent
    /// The server's answer to the stream request itself.
    case status(Int)
    /// The server no longer holds this job.
    case jobGone
    /// The pairing is gone.
    case expired
    case other(String)
}

/// The resume state of one turn's stream: where it got to, and how many times
/// in a row it has had to reconnect. A value type, owned by `ChatStore`.
struct TurnStreamResume: Equatable {
    /// The waits before each reconnect in a row. Sixty seconds in all —
    /// enough for a tunnel, a lift or twenty seconds of airplane mode.
    static let backoff: [TimeInterval] = [1, 2, 4, 8, 15, 30]
    /// The chat stream session's idle timeout: four missed heartbeats. See
    /// `TurnStreamFailure.silent`.
    static let silence: TimeInterval = 20
    /// Silent connections in a row before the job is taken to be over.
    static let silentLimit = 2

    /// The highest sequence number handled. Sent as `Last-Event-ID`.
    private(set) var lastEventId: Int?
    /// Reconnects in a row with nothing new arriving between them.
    private(set) var attempts = 0
    /// Of those, the ones where the server answered and then said nothing.
    private(set) var silentInARow = 0

    init(lastEventId: Int? = nil) {
        self.lastEventId = lastEventId
    }

    /// Whether a frame is new. A frame without an id (`connected`, the
    /// server's "job not found") is always new; one at or below the resume
    /// point is a replay and is dropped — the second guard, after the server's
    /// own `Last-Event-ID` replay, against an appended token being appended twice.
    ///
    /// Anything new resets the reconnect count: a link that keeps coming back
    /// is not a link that has failed six times.
    mutating func accept(_ id: Int?) -> Bool {
        guard let id else { return true }
        if let last = lastEventId, id <= last { return false }
        lastEventId = id
        attempts = 0
        silentInARow = 0
        return true
    }

    enum Next: Equatable {
        case reconnect(after: TimeInterval)
        /// The job is gone: re-read the thread, which holds what was saved.
        case reload
        case expired
        case fail(String)
        /// Out of reconnects. The turn may well still be running; wait for
        /// the app to come back to the foreground (or the screen to reappear)
        /// and try again from the same point.
        case wait
    }

    mutating func next(after failure: TurnStreamFailure) -> Next {
        switch failure {
        case .jobGone, .status(404):
            return .reload
        case .expired, .status(401):
            return .expired
        case .status(let code) where (400..<500).contains(code) && code != 408 && code != 429:
            return .fail("\(code) from the server.")
        case .other(let message):
            return .fail(message)
        case .silent where silentInARow + 1 >= Self.silentLimit:
            silentInARow = 0
            return .reload
        case .network, .closedEarly, .silent, .status:
            if failure == .silent { silentInARow += 1 } else { silentInARow = 0 }
            guard attempts < Self.backoff.count else { return .wait }
            let wait = Self.backoff[attempts]
            attempts += 1
            return .reconnect(after: wait)
        }
    }

    /// A reconnect asked for from outside — the app back in the foreground,
    /// the screen back on top — starts the count again.
    mutating func restart() {
        attempts = 0
        silentInARow = 0
    }

    /// The server's "this job is gone" frame.
    static func isJobGone(type: String, message: String?) -> Bool {
        type == "error" && message?.lowercased() == "job not found"
    }

    /// Frames that say nothing about where the turn has got to. A silent
    /// stream is one with none of anything else.
    static func isKeepalive(_ type: String) -> Bool {
        type == "connected"
    }

    /// The URL loading errors that mean "the network", as opposed to a bug.
    static func isNetwork(domain: String, code: Int) -> Bool {
        guard domain == NSURLErrorDomain else { return false }
        return networkCodes.contains(code)
    }

    private static let networkCodes: Set<Int> = [
        NSURLErrorTimedOut,
        NSURLErrorCannotFindHost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorDNSLookupFailed,
        NSURLErrorNotConnectedToInternet,
        NSURLErrorInternationalRoamingOff,
        NSURLErrorCallIsActive,
        NSURLErrorDataNotAllowed,
        NSURLErrorSecureConnectionFailed,
        NSURLErrorCannotLoadFromNetwork,
        NSURLErrorBackgroundSessionWasDisconnected,
    ]
}

/// Gates replayed into a REJOINED turn.
///
/// A turn picked up again after a relaunch is streamed from the start, into a
/// fresh bubble. If it stopped at a plan or a question and was answered at the
/// desk, the replay carries that gate AND everything after it — and acting on
/// the gate the moment it arrives would park the turn on a card nobody needs.
/// So in a rejoin a gate is HELD; anything that shows the turn moved on drops
/// it; a gate still held once the replay has gone quiet is the real one.
struct GateHold: Equatable {
    static let gates: Set<String> = ["plan", "confirm", "clarify", "secret_request", "approval"]
    /// How long the replay must be quiet before a held gate is believed.
    static let settle: TimeInterval = 1.2

    private(set) var held: String?

    /// Note a frame. Returns true when the frame is a gate and is now held.
    mutating func note(_ type: String) -> Bool {
        if Self.gates.contains(type) {
            held = type
            return true
        }
        // A heartbeat ticks while a gate waits; it is not progress.
        if type != "heartbeat" && type != "connected" { held = nil }
        return false
    }

    mutating func release() -> String? {
        defer { held = nil }
        return held
    }
}

// MARK: - The turn in flight, across a relaunch

/// The phone's own turns that were still running, by thread.
///
/// Written when a turn starts, cleared when it ends. If the app is killed in
/// between, the thread finds the job id here on its next open and picks the
/// turn up again — or, if the server has let it go, simply re-reads the
/// thread. A read that finds nothing, or a value that is not what this wrote,
/// is an empty map: losing this costs a reload, never a crash.
struct ActiveTurns {
    struct Entry: Codable, Equatable {
        let jobId: String
        let startedAt: Date
    }

    static let key = "chat-active-turns"
    /// Past this the server has certainly ended the job (its longest cap is
    /// the 45-minute delegation limit).
    static let maxAge: TimeInterval = 50 * 60

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func entry(for conversationId: String, now: Date = Date()) -> Entry? {
        guard let entry = all()[conversationId] else { return nil }
        guard now.timeIntervalSince(entry.startedAt) < Self.maxAge else {
            clear(conversationId)
            return nil
        }
        return entry
    }

    func record(_ jobId: String, for conversationId: String, at now: Date = Date()) {
        var map = all().filter { now.timeIntervalSince($0.value.startedAt) < Self.maxAge }
        map[conversationId] = Entry(jobId: jobId, startedAt: now)
        save(map)
    }

    /// `jobId`: only if it is still that job — a newer turn in the same
    /// thread must not be forgotten because an older one finished.
    func clear(_ conversationId: String, jobId: String? = nil) {
        var map = all()
        guard let current = map[conversationId] else { return }
        if let jobId, current.jobId != jobId { return }
        map[conversationId] = nil
        save(map)
    }

    private func all() -> [String: Entry] {
        guard let data = defaults.data(forKey: Self.key),
              let map = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return map
    }

    private func save(_ map: [String: Entry]) {
        if map.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
