import Foundation

/// One file waiting to go up to Drive, or gone. Written to Application
/// Support as JSON with the rest of the queue, so an upload the system
/// carries on with while the app is shut is still known when it reopens.
///
/// The pure half of `DriveUploadQueue`: every state change is a function
/// here, so the rules that decide whether a photo may later be deleted from
/// the phone are unit tests, not a reading of the delegate.
///
/// Foundation only (the Linux harness compiles it).
struct DriveUploadJob: Codable, Equatable, Identifiable {
    enum State: Codable, Equatable {
        /// Made, not yet handed to the system.
        case waiting
        /// The system is sending it.
        case sending
        /// On the site. `safe`: the answer was a 201, or a 200 that said
        /// `duplicate: true` — the only two answers that prove these bytes are
        /// held, and the only ones that let "Move from phone" delete the
        /// original.
        case stored(fileId: String, duplicate: Bool, safe: Bool)
        /// Did not get there; tried again by itself (no signal, the site busy).
        case failed(String)
        /// The site said no and will say it again (too big, no room, not
        /// allowed). Not retried.
        case refused(String)
    }

    let id: String
    let space: DriveSpace
    let folder: String
    /// The name it is sent under; the site may rename a camera `IMG_` photo.
    let filename: String
    let mimeType: String
    let sizeBytes: Int
    /// Lowercase hex: sent, so a truncated body is refused rather than kept.
    let sha256: String
    /// When a photo was taken, as the phone's wall clock with its offset.
    let takenAt: String?
    /// The staged copy's name inside the queue's folder. A name, never a
    /// path: the app's container moves between installs.
    let staged: String
    /// The library photo this came from, for "Move from phone".
    let assetId: String?
    let createdAt: Date
    var attempts: Int = 0
    var sentBytes: Int = 0
    var state: State = .waiting
    /// A file over the single-shot limit goes up a piece at a time
    /// (`DriveChunks.swift`): how far it has got. Nil for a single upload —
    /// and for every job written before big uploads, which decode as before.
    var chunked: DriveChunkState? = nil

    /// What the queue says it is adding: the name the site will give it.
    var displayName: String {
        DriveLogic.photoName(takenAt: takenAt, filename: filename, mimeType: mimeType) ?? filename
    }

    var dedupeKey: String { DriveLogic.dedupeKey(space: space, folder: folder, sha256: sha256) }

    var isFinished: Bool {
        switch state {
        case .stored, .refused: return true
        case .waiting, .sending, .failed: return false
        }
    }

    var isActive: Bool { state == .waiting || state == .sending }

    /// Whether these bytes are proven to be on the site.
    var isSafelyStored: Bool {
        if case .stored(_, _, let safe) = state { return safe }
        return false
    }

    var storedFileId: String? {
        if case .stored(let id, _, _) = state { return id }
        return nil
    }

    // MARK: - Transitions

    /// Handed to the system.
    func started() -> DriveUploadJob {
        var next = self
        next.state = .sending
        next.attempts += 1
        next.sentBytes = chunkedFloor
        return next
    }

    /// What a big upload already has on the site; nothing for a single one.
    private var chunkedFloor: Int { min(chunked?.received ?? 0, sizeBytes) }

    func progressed(_ sent: Int64) -> DriveUploadJob {
        var next = self
        next.sentBytes = Int(max(0, min(sent, Int64(sizeBytes))))
        return next
    }

    /// The system finished with it: what the site said, or that it never answered.
    func finished(status: Int?, body: Data?, transportError: String?) -> DriveUploadJob {
        if let chunked { return answered(chunked, status: status, body: body, transportError: transportError) }
        var next = self
        next.state = DriveUploadOutcome.classify(status: status, body: body, transportError: transportError)
        if case .stored = next.state { next.sentBytes = sizeBytes }
        return next
    }

    /// Whether the queue tries it again by itself, now: failed (not refused),
    /// and fewer than `DriveUploadOutcome.maxAttempts` goes so far.
    var retriesItself: Bool {
        if case .failed = state { return attempts < DriveUploadOutcome.maxAttempts }
        return false
    }

    /// Back to waiting — Try again, or the queue's own retry. A big upload
    /// keeps its session: it carries on from what the site holds.
    func retried() -> DriveUploadJob {
        var next = self
        next.state = .waiting
        next.chunked = chunked?.resumed
        next.sentBytes = chunkedFloor
        return next
    }

    /// Try again, pressed: the count of goes, and of lost sessions, start over.
    func retriedByHand() -> DriveUploadJob {
        var next = self
        next.attempts = 0
        next.chunked?.restarts = 0
        return next.retried()
    }

    /// The answer to one step of a big upload (`DriveChunks.answer`). Only a
    /// `complete` that answered 201, or a duplicate, is stored safely.
    private func answered(_ chunk: DriveChunkState, status: Int?, body: Data?, transportError: String?) -> DriveUploadJob {
        var next = self
        switch DriveChunks.answer(chunk, size: sizeBytes, status: status, body: body, transportError: transportError) {
        case .next(let state, let progressed):
            next.chunked = state
            next.state = .sending
            next.sentBytes = min(state.received, sizeBytes)
            // Bytes went in: a long upload's earlier troubles are behind it.
            if progressed { next.attempts = 1 }
        case .stored(let fileId, let duplicate, let safe):
            next.state = .stored(fileId: fileId, duplicate: duplicate, safe: safe)
            next.sentBytes = sizeBytes
        case .failed(let why, let resume):
            next.chunked = resume
            next.state = .failed(why)
            next.sentBytes = min(resume.received, sizeBytes)
        case .refused(let why):
            next.state = .refused(why)
        }
        return next
    }
}

enum DriveUploadOutcome {
    /// A third failure in a row waits for a person to press Try again.
    static let maxAttempts = 3

    private struct Refusal: Decodable { let error: String? }

    /// What one answer means for the file.
    ///
    /// - 201: stored, safe.
    /// - 200 with `duplicate: true`: already there, safe.
    /// - Any other 2xx with a file: stored, but NOT proven — never deletes an original.
    /// - 401: the phone needs pairing again; tried again once it is.
    /// - 408, 429, 5xx, no answer: failed, tried again.
    /// - Any other 4xx: refused, in the site's own words.
    static func classify(status: Int?, body: Data?, transportError: String?) -> DriveUploadJob.State {
        guard let status else {
            return .failed(transportError ?? "Couldn't reach the site.")
        }
        switch status {
        case 200..<300:
            guard let body, let reply = try? JSONDecoder().decode(DriveUploadReply.self, from: body) else {
                return .failed("The site's answer couldn't be read.")
            }
            let duplicate = reply.duplicate == true
            let safe = status == 201 || (status == 200 && duplicate)
            return .stored(fileId: reply.file.id, duplicate: duplicate, safe: safe)
        case 401:
            return .failed("This phone needs connecting again.")
        case 408, 429, 500...:
            return .failed(message(body) ?? "The site was busy.")
        case 413:
            return .refused(message(body) ?? "That file is too big for Drive.")
        default:
            return .refused(message(body) ?? "The site wouldn't take that (\(status)).")
        }
    }

    private static func message(_ body: Data?) -> String? {
        guard let body, let text = (try? JSONDecoder().decode(Refusal.self, from: body))?.error,
              !text.isEmpty else { return nil }
        return text
    }

    /// The banner while uploads run: "Adding 3 of 10 · 40%", or nil when nothing is.
    static func banner(_ jobs: [DriveUploadJob]) -> String? {
        let active = jobs.filter { $0.isActive }
        guard !active.isEmpty else { return nil }
        // The batch is everything not yet cleared away: done ones count
        // towards "of", so the number goes up rather than the total down.
        let total = jobs.filter { $0.isActive || $0.isFinished }.count
        let done = total - active.count
        let bytes = active.reduce(0) { $0 + $1.sizeBytes }
        let sent = active.reduce(0) { $0 + $1.sentBytes }
        let percent = bytes > 0 ? Int((Double(sent) / Double(bytes) * 100).rounded()) : 0
        let head = total > 1 ? "Adding \(min(done + 1, total)) of \(total)" : "Adding \(active[0].displayName)"
        // A big file says how far it has got itself: "1.2 GB of 3 GB".
        if let big = active.first(where: { $0.chunked != nil && $0.state == .sending && $0.sentBytes > 0 }) {
            return "\(head) · \(DriveLogic.size(big.sentBytes)) of \(DriveLogic.size(big.sizeBytes))"
        }
        return percent > 0 ? "\(head) · \(percent)%" : "\(head)…"
    }

    /// One line for what did not make it, or nil.
    static func trouble(_ jobs: [DriveUploadJob]) -> String? {
        let stuck = jobs.filter {
            switch $0.state {
            case .failed, .refused: return true
            default: return false
            }
        }
        guard let first = stuck.first else { return nil }
        let why: String
        switch first.state {
        case .failed(let text), .refused(let text): why = text
        default: why = ""
        }
        return stuck.count == 1 ? "\(first.displayName): \(why)" : "\(stuck.count) files didn't go up. \(why)"
    }
}

/// Photos already moved off this phone, by library id: never offered for
/// moving twice, and the list "Remove from phone" deletes from. Kept in
/// Application Support as JSON.
struct DriveMoveLedger: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let assetId: String
        let fileId: String
        let space: DriveSpace
        let storedAt: Date
        /// Removed from the phone's library (the system asked first).
        var removed: Bool = false
    }

    var entries: [Entry] = []

    func contains(_ assetId: String) -> Bool { entries.contains { $0.assetId == assetId } }

    /// Stored safely and still on the phone: what "Remove from phone" offers.
    var removable: [Entry] { entries.filter { !$0.removed } }

    /// A job that proved its bytes are on the site, written down. Anything
    /// else — a refusal, a 2xx that did not say 201 or duplicate — is not.
    func recording(_ job: DriveUploadJob, at now: Date = Date()) -> DriveMoveLedger {
        guard let assetId = job.assetId, job.isSafelyStored, let fileId = job.storedFileId, !contains(assetId) else { return self }
        var next = self
        next.entries.append(Entry(assetId: assetId, fileId: fileId, space: job.space, storedAt: now))
        return next
    }

    /// The library said these are gone.
    func removing(_ assetIds: Set<String>) -> DriveMoveLedger {
        var next = self
        for i in next.entries.indices where assetIds.contains(next.entries[i].assetId) { next.entries[i].removed = true }
        return next
    }
}
