import Foundation

// MARK: - Whispering to JKai: the rules, without the screen
//
// Foundation only, so the whole flow — what may be sent, which key it goes
// with, how fast to poll after it, what each refusal says — compiles and runs
// on Linux as well as in the app's tests. `WildmindTalkStore` drives it; the
// screen only reads it.
//
// The contract (Wildmind W5, SR-Main S3): `POST api/native/wildmind/whisper`
// with `{text}` and an `Idempotency-Key: <uuid>`. 1…240 characters once
// trimmed, line breaks folded to spaces and control characters dropped,
// counted as Wildmind counts them (Unicode code points). Wildmind replays its
// first 202 for the same key and the same words, and refuses the same key with
// other words (422 `key-reused`), so:
//
//  - a retry of the SAME words reuses the key: if the first attempt did land
//    and only its answer was lost, the retry is answered once, not twice;
//  - different words get a new key;
//  - an accepted whisper retires its key.
//
// After a 202 the phone asks `/whispers` every three seconds for a minute, so
// "JKai heard you" turns up while John is still looking, then goes back to the
// page's normal pace.

/// What may be sent, and why not.
enum WildmindWhisperText {
    static let limit = 240

    /// The words as they will be kept: a line break, with any spaces round
    /// it, becomes one space; control characters go; the ends are trimmed.
    /// The same steps SR-Main takes, so the count here is the count there.
    static func clean(_ raw: String) -> String {
        let folded = raw.replacingOccurrences(of: #"\s*[\r\n\t]+\s*"#, with: " ", options: .regularExpression)
        var out = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars where scalar.value >= 0x20 && scalar.value != 0x7F {
            out.append(scalar)
        }
        return String(out).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Characters as Wildmind counts them: code points of the cleaned text.
    static func count(_ raw: String) -> Int {
        clean(raw).unicodeScalars.count
    }

    enum Problem: Equatable {
        case empty
        case tooLong(over: Int)
    }

    static func problem(_ raw: String) -> Problem? {
        let n = count(raw)
        if n == 0 { return .empty }
        if n > limit { return .tooLong(over: n - limit) }
        return nil
    }
}

/// A refusal, as the site says it, and as the phone says it to John.
enum WildmindWhisperFailure: Equatable, Sendable {
    /// 429: one at a time. `retryAfter` in seconds, when the site said.
    case slowDown(retryAfter: Int?)
    case empty
    case tooLong
    case onlyJkai
    case dead
    case halted
    case betweenLives
    /// The same key was sent with other words: start again with a new key.
    case keyReused
    /// The site could not read the request (no key, a bad body).
    case badRequest
    /// The lane is closed or Wildmind did not answer: nothing was sent.
    case offline
    /// No answer at all reached the phone: it may or may not have landed.
    case network
    /// This phone may not whisper (a member's, or viewing as one).
    case refused
    /// This phone needs pairing again.
    case expired
    /// The site does not have the route yet (an older SR-Main).
    case notOnSite
    case other(String)

    /// From the site's status and its fixed error string.
    static func from(status: Int, error: String?, retryAfter: Int?) -> WildmindWhisperFailure {
        switch (status, error ?? "") {
        case (429, _): return .slowDown(retryAfter: retryAfter)
        case (400, "empty"): return .empty
        case (400, "too-long"): return .tooLong
        case (400, _): return .badRequest
        case (403, "only-jkai"): return .onlyJkai
        case (403, _): return .refused
        case (409, "dead"): return .dead
        case (409, "halted"): return .halted
        case (409, "between-lives"): return .betweenLives
        // SR-Main's stand-in for a 409 it did not recognise.
        case (409, _): return .other(error ?? "unavailable")
        case (422, _): return .keyReused
        case (401, _): return .expired
        case (404, _): return .notOnSite
        case (503, _), (502, _), (504, _): return .offline
        default: return .other(error ?? "\(status)")
        }
    }

    /// What John reads under the composer.
    var message: String {
        switch self {
        case .slowDown(let seconds):
            if let seconds, seconds > 0 {
                return "One whisper at a time \u{2014} try again in \(seconds) s."
            }
            return "One whisper at a time \u{2014} try again in a little while."
        case .empty: return "Write something to whisper first."
        case .tooLong: return "That\u{2019}s over \(WildmindWhisperText.limit) characters. Trim it a little and send it again."
        case .onlyJkai: return "Only JKai can hear whispers."
        case .dead: return "JKai has died, so there\u{2019}s nobody to hear it until the next life begins."
        case .halted: return "The valley\u{2019}s paused, so nobody can hear a whisper just now."
        case .betweenLives: return "The valley\u{2019}s between lives. Try again once the next one begins."
        case .keyReused: return "That didn\u{2019}t go. Send it again."
        case .badRequest: return "The site couldn\u{2019}t read that whisper. Send it again."
        case .offline: return "The valley isn\u{2019}t answering, so it wasn\u{2019}t sent. Try again in a moment."
        case .network: return "No answer from the site. Send it again \u{2014} it won\u{2019}t arrive twice."
        case .refused: return "Whispers go from the owner\u{2019}s own phone."
        case .expired: return "This iPhone needs pairing again."
        case .notOnSite: return "Whispering needs a newer site than this one."
        case .other: return "That whisper didn\u{2019}t go. Try again."
        }
    }

    /// Whether resending the same words should reuse the same key. A key that
    /// the site has seen with these words is still good; one it refused as
    /// reused, or could not read, is not.
    var keepsKey: Bool {
        switch self {
        case .keyReused, .badRequest: return false
        default: return true
        }
    }

    /// The valley cannot hear anyone just now: sending stays off until it can.
    var blocksSending: Bool {
        switch self {
        case .dead, .halted, .betweenLives, .refused, .expired, .notOnSite, .onlyJkai: return true
        default: return false
        }
    }
}

/// The composer's state machine. A value type so it can be tested step by step.
struct WildmindWhisperFlow: Equatable {
    enum Phase: Equatable {
        case idle
        /// A POST is out with these words and this key.
        case sending(text: String, key: String)
        /// The last attempt failed. `key` is kept for a retry of the same words.
        case failed(WildmindWhisperFailure, text: String, key: String?)
        /// Accepted.
        case sent(logId: Int)
    }

    static let fastPoll: TimeInterval = 3
    static let fastWindow: TimeInterval = 60

    private(set) var phase: Phase = .idle
    /// When the last whisper was accepted: the fast poll runs a minute from it.
    private(set) var lastSentAt: Date?
    /// The log ids sent from this phone, newest last, so Talk can show them
    /// on its own side before the next page brings them.
    private(set) var sentIds: [Int] = []
    /// No sending before this (a 429's retry-after).
    private(set) var coolUntil: Date?

    var isSending: Bool {
        if case .sending = phase { return true }
        return false
    }

    var failure: WildmindWhisperFailure? {
        if case .failed(let failure, _, _) = phase { return failure }
        return nil
    }

    /// May these words go now? `blocked` is the page's own reason not to
    /// (offline, a dead or paused valley, View as).
    func canSend(_ raw: String, blocked: Bool, now: Date) -> Bool {
        guard !blocked, !isSending, WildmindWhisperText.problem(raw) == nil else { return false }
        if let coolUntil, now < coolUntil { return false }
        return true
    }

    /// Seconds before the next send is allowed, rounded up; nil when it is.
    func coolingSeconds(now: Date) -> Int? {
        guard let coolUntil, now < coolUntil else { return nil }
        return Int(coolUntil.timeIntervalSince(now).rounded(.up))
    }

    /// Start sending `raw`. Returns the words and the key to send them with,
    /// or nil when they may not go. A retry of the words that just failed
    /// reuses that attempt's key.
    mutating func begin(_ raw: String, now: Date, newKey: () -> String = { UUID().uuidString.lowercased() })
        -> (text: String, key: String)? {
        guard canSend(raw, blocked: false, now: now) else { return nil }
        let text = WildmindWhisperText.clean(raw)
        let key: String
        if case .failed(let failure, let previous, let held) = phase, previous == text, failure.keepsKey, let held {
            key = held
        } else {
            key = newKey()
        }
        phase = .sending(text: text, key: key)
        return (text, key)
    }

    /// The site accepted it.
    mutating func accepted(_ reply: WildmindWhisperAccepted, now: Date) {
        phase = .sent(logId: reply.logId)
        lastSentAt = now
        coolUntil = nil
        if !sentIds.contains(reply.logId) { sentIds.append(reply.logId) }
        if sentIds.count > 50 { sentIds.removeFirst(sentIds.count - 50) }
    }

    /// The site refused it, or nothing came back.
    mutating func failed(_ failure: WildmindWhisperFailure, now: Date) {
        guard case .sending(let text, let key) = phase else {
            phase = .failed(failure, text: "", key: nil)
            return
        }
        phase = .failed(failure, text: text, key: failure.keepsKey ? key : nil)
        if case .slowDown(let seconds) = failure {
            coolUntil = now.addingTimeInterval(TimeInterval(max(1, seconds ?? 20)))
        }
    }

    /// The error has been read (John is typing again): keep the key for a
    /// retry, lose the banner.
    mutating func acknowledge() {
        if case .sent = phase { phase = .idle }
    }

    /// How long to wait before asking `/whispers` again: three seconds for a
    /// minute after a whisper went, `normal` otherwise.
    func pollInterval(now: Date, normal: TimeInterval) -> TimeInterval {
        if isSending { return Self.fastPoll }
        guard let lastSentAt, now.timeIntervalSince(lastSentAt) < Self.fastWindow else { return normal }
        return Self.fastPoll
    }

    /// Inside the minute after a whisper went.
    func isWatching(now: Date) -> Bool {
        guard let lastSentAt else { return false }
        return now.timeIntervalSince(lastSentAt) < Self.fastWindow
    }
}

/// The few words under a whisper.
enum WildmindWhisperWords {
    static func status(_ whisper: WildmindWhisper?, main: String = "JKai") -> String {
        switch whisper?.status {
        case .heard?: return "\(main) heard you"
        case .dropped?: return "Lost \u{2014} two newer whispers pushed it out"
        case .pending?: return "Waiting for \(main) to hear it"
        case .unknown?, nil: return "Sent"
        }
    }

    /// The line over the composer about whether a whisper will be heard soon.
    static func readiness(_ whispers: WildmindWhispers?, asleep: Bool, main: String = "JKai") -> String? {
        if asleep { return "\(main)\u{2019}s asleep, so it\u{2019}ll be heard on waking." }
        guard let whispers else { return nil }
        if !whispers.modelAvailable {
            return "\(main)\u{2019}s mind is resting, so a whisper waits until it wakes."
        }
        if whispers.pending.count >= 2 {
            return "Two whispers are already waiting. A third pushes the oldest out."
        }
        return nil
    }
}
