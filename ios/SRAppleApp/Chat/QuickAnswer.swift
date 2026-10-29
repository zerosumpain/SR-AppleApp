import Foundation

// MARK: - A spoken answer from jkai, hands-free
//
// "Quick answer from jkai" (Siri, the Action button, Shortcuts) and the
// Watch's quick answer send ONE read-only turn and say what came back. The
// rules are kept here, Foundation only, so the Linux harness
// (`scripts/chat-check.sh`) tests them; the intent and `WatchBridge` only
// wire them to `SiteClient`.
//
// What SR-Jkai-Core does with such a turn (surface 'siri' or 'watch' from a
// paired device): it runs in the owner's single "Quick answers" thread,
// whatever conversationId the body names, with read-only tools, every gate
// auto-denied, at most four rounds and the voice overlay (short, speakable).
// The POST answers `{ jobId, conversationId }`; the job is then polled at
// `GET …/orchestrator/chat?jobId=`, which deletes it once it reports a
// terminal status — so the terminal answer is read exactly once.

enum QuickAnswer {
    /// Core ignores the body's thread for a hands-free turn and uses the
    /// Quick answers thread; this only fills the required field.
    static let placeholderConversation = "quick-answers"
    /// The hands-free surfaces Core knows.
    static let surfaces: Set<String> = ["siri", "watch"]
    /// How long a person holding the button waits before being told it is
    /// still going. Siri gives up on an intent not long after this.
    static let budget: TimeInterval = 20
    static let pollInterval: TimeInterval = 1

    static let stillWorking = "Still working on that. It'll be in your Quick answers thread."
    static let emptyAnswer = "No answer came back. Have a look in your Quick answers thread."

    /// The turn, with the hands-free surface on its envelope. An unknown
    /// surface is 'siri': this path is never an ordinary phone turn.
    static func request(question: String, surface: String, envelope: TurnEnvelope? = nil) -> TurnRequest {
        let surface = surfaces.contains(surface) ? surface : "siri"
        return TurnRequest(
            message: question.trimmingCharacters(in: .whitespacesAndNewlines),
            conversationId: placeholderConversation,
            attachmentIds: nil,
            envelope: envelope ?? TurnEnvelope.phone(surface: surface)
        )
    }

    /// One read of the job.
    enum Poll: Equatable {
        case running
        case done(String)
        case failed(String?)
        /// The server no longer holds the job (a restart, or read already).
        case gone
    }

    private struct PollBody: Decodable {
        struct Result: Decodable { let message: String? }
        let status: String?
        let result: Result?
        let error: String?
    }

    static func readPoll(status: Int, body: Data) -> Poll {
        if status == 404 { return .gone }
        guard (200..<300).contains(status),
              let decoded = try? JSONDecoder().decode(PollBody.self, from: body) else {
            return .failed(nil)
        }
        switch decoded.status {
        case "done": return .done(decoded.result?.message ?? "")
        case "error", "cancelled", "interrupted": return .failed(decoded.error)
        default: return .running
        }
    }

    /// How it ended, before it is said.
    enum Outcome: Equatable {
        case answer(String)
        case stillWorking
        case refused(String)
    }

    /// The whole exchange, with the network and the clock passed in so it can
    /// be tested. Never throws and never runs past `budget` (plus one poll):
    /// a hands-free answer that hangs is worse than one that says "later".
    static func run(
        budget: TimeInterval = budget,
        interval: TimeInterval = pollInterval,
        now: () -> Date = Date.init,
        sleep: (TimeInterval) async -> Void,
        post: () async throws -> TurnStart,
        poll: (String) async throws -> Poll
    ) async -> Outcome {
        let deadline = now().addingTimeInterval(budget)
        var job: String?
        var pendingLeft = TurnStart.pendingTries
        var retries = TurnStart.retryDelays[...]
        while job == nil {
            let start: TurnStart
            do {
                start = try await post()
            } catch {
                guard let wait = retries.popFirst(), now().addingTimeInterval(wait) < deadline else {
                    return .refused(error.localizedDescription)
                }
                await sleep(wait)
                continue
            }
            switch start {
            case .started(let id):
                job = id
            case .pending(let wait):
                pendingLeft -= 1
                guard pendingLeft >= 0, now().addingTimeInterval(wait) < deadline else { return .stillWorking }
                await sleep(wait)
            case .unavailable(let why):
                guard let wait = retries.popFirst(), now().addingTimeInterval(wait) < deadline else {
                    return .refused(why)
                }
                await sleep(wait)
            case .refused(let why):
                return .refused(why)
            }
        }
        guard let job else { return .stillWorking }
        while now() < deadline {
            await sleep(interval)
            let read: Poll
            do {
                read = try await poll(job)
            } catch {
                continue
            }
            switch read {
            case .running: continue
            case .done(let text): return .answer(text)
            case .failed(let why): return .refused(why ?? "That didn't work.")
            case .gone: return .stillWorking
            }
        }
        return .stillWorking
    }

    /// The line Siri (or the Watch) says.
    static func spoken(_ outcome: Outcome) -> String {
        switch outcome {
        case .answer(let markdown):
            let plain = SpokenText.plain(markdown)
            return plain.isEmpty ? emptyAnswer : plain
        case .stillWorking:
            return stillWorking
        case .refused(let why):
            let trimmed = why.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "That didn't work." : trimmed
        }
    }

    // MARK: - The Watch's private-read gate

    /// Whether the Watch's "ask aloud" may be answered, and what to say if not.
    ///
    /// A quick answer reads John's private tools (his day, his health, his
    /// mail), and the Watch holds no credential: the iPhone answers for it.
    /// The Siri path has `.requiresAuthentication`; a WatchConnectivity
    /// message has nothing like it, so the phone must judge presence itself.
    ///
    /// What the platform lets the iPhone see (checked 2026-10-29):
    /// - The iPhone's own lock: `UIApplication.isProtectedDataAvailable` is
    ///   true while it is unlocked and for a few seconds after it locks (the
    ///   `NSFileProtectionComplete` grace). That is the "unlocked recently"
    ///   signal, and it is what is required here.
    /// - The Watch's wrist and lock state: NOT available. `WCSession` reports
    ///   paired, installed and reachable only, and watchOS has no public
    ///   on-wrist API to pass across (wrist detection can also be switched
    ///   off, leaving a Watch unlocked on a table). So "on-wrist and unlocked"
    ///   cannot be proved from the bridge.
    ///
    /// Server-side, a 'watch' turn already gets only read tools (Core), but
    /// there is no "non-private reads only" mode the phone could ask for — so
    /// with the iPhone locked the restriction is the strict one: no quick
    /// answer at all, and the Watch is told to unlock the phone. Non-private
    /// reads (the Today snapshot the Watch already shows) need no question.
    enum WatchGate: Equatable {
        case answer
        case refuse(String)
    }

    static let watchLockedReply = "Unlock your iPhone to ask jkai from the Watch."

    static func watchGate(phoneUnlockedRecently: Bool) -> WatchGate {
        phoneUnlockedRecently ? .answer : .refuse(watchLockedReply)
    }

}
