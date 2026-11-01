import Foundation

/// Photo sync's rules: which photos go next, how many at once, and what the
/// screen says. The pure half of `DrivePhotoSync` — Foundation only, so the
/// tests own every decision about what is "in Drive".
///
/// "In Drive" means one thing everywhere: the move ledger holds it. An entry
/// is written only when the site proved it holds those exact bytes — a 201, a
/// 200 duplicate, or (sync's own check) Drive naming the file that holds that
/// sha256 and size. So "Remove from phone" and this screen agree by
/// construction.

struct DriveSyncSettings: Codable, Equatable {
    /// Off until the person turns it on: it sends the whole library.
    var on = false
    var videos = true
    /// On mobile data, nothing new is started. What is already going finishes.
    var wifiOnly = true
    /// Only photos taken on or after this day; nil, the whole library.
    var since: Date?

    static let key = "drive.sync.settings"

    static func load(_ defaults: UserDefaults = .standard) -> DriveSyncSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(DriveSyncSettings.self, from: data) else { return DriveSyncSettings() }
        return settings
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

/// Why sync is not sending right now, or `.none` when it may.
enum DriveSyncPause: Equatable {
    case off
    case demo
    case unpaired
    case viewingAs
    /// No access to the library, or not asked yet.
    case noAccess
    case cellular
    case lowData
    case lowPower
    case none

    var sentence: String? {
        switch self {
        case .off: return "Photo sync is off."
        case .demo: return "Drive is switched off in the demo."
        case .unpaired: return "Connect this phone to the site first."
        case .viewingAs: return "View as is look-only."
        case .noAccess: return "SR needs access to your photos."
        case .cellular: return "Waiting for Wi-Fi."
        case .lowData: return "Paused while Low Data Mode is on."
        case .lowPower: return "Paused while Low Power Mode is on."
        case .none: return nil
        }
    }

    /// The order the checks run in: the first that applies says why.
    static func of(on: Bool, demo: Bool, paired: Bool, viewingAs: Bool, access: Bool,
                   wifiOnly: Bool, expensive: Bool, constrained: Bool, lowPower: Bool) -> DriveSyncPause {
        if !on { return .off }
        if demo { return .demo }
        if !paired { return .unpaired }
        if viewingAs { return .viewingAs }
        if !access { return .noAccess }
        if constrained { return .lowData }
        if wifiOnly, expensive { return .cellular }
        if lowPower { return .lowPower }
        return .none
    }
}

/// The comparison: this phone's library against what Drive holds.
struct DriveSyncCounts: Equatable {
    /// Photos and videos sync covers (the settings' range and kinds).
    var library = 0
    /// Of those, proven to be in Drive.
    var inDrive = 0
    /// On their way up now.
    var sending = 0
    /// Drive refused them (too big, no room); not tried again by sync.
    var skipped = 0
    /// Neither in Drive, going, nor refused: what sync still has to do.
    var notYet: Int { max(0, library - inDrive - sending - skipped) }
}

enum DriveSync {
    /// Sync's own files in the queue at once: enough to keep the line busy,
    /// few enough that the phone never stages gigabytes it cannot send yet.
    static let window = 8
    /// One "which of these do you have?" question.
    static let haveBatch = 8
    /// The size Drive re-hashes at request time: a bigger film not yet
    /// fingerprinted waits until Drive's sweep has caught up, rather than
    /// going up only for Drive to find it already had it.
    static let bigFile = 32 * 1024 * 1024
    /// Failures that have used their three goes are tried again at most this often.
    static let retryEvery: TimeInterval = 15 * 60

    /// Sync's jobs still going, or still to try by themselves.
    static func inFlight(_ jobs: [DriveUploadJob]) -> [DriveUploadJob] {
        jobs.filter { $0.assetId != nil && ($0.isActive || $0.retriesItself) }
    }

    /// Room for more: the window less what is already going.
    static func room(_ jobs: [DriveUploadJob]) -> Int {
        max(0, window - inFlight(jobs).count)
    }

    /// Every library photo the queue holds and has not given up on — going,
    /// waiting, or failed (a failure is Try again's, not sync's to resend).
    static func queued(_ jobs: [DriveUploadJob]) -> Set<String> {
        Set(jobs.compactMap { job in
            guard let id = job.assetId else { return nil }
            if case .refused = job.state { return nil }
            return job.isSafelyStored ? nil : id
        })
    }

    /// Sync's refusals in the queue, by library photo: never sent again by sync.
    static func refusals(_ jobs: [DriveUploadJob]) -> [String: String] {
        var out: [String: String] = [:]
        for job in jobs {
            guard let id = job.assetId, case .refused(let why) = job.state else { continue }
            out[id] = why
        }
        return out
    }

    /// The comparison, from the library (in sync's order) and what is known.
    static func counts(library: [String], inDrive: Set<String>, sending: Set<String>, skipped: Set<String>) -> DriveSyncCounts {
        var counts = DriveSyncCounts(library: library.count)
        for id in library {
            if inDrive.contains(id) { counts.inDrive += 1 } else if sending.contains(id) { counts.sending += 1 } else if skipped.contains(id) { counts.skipped += 1 }
        }
        return counts
    }

    /// The next photos to send, in the library's order (newest first),
    /// passing over anything known or put off.
    static func next(library: [String], known: Set<String>, later: Set<String>, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var out: [String] = []
        for id in library where !known.contains(id) && !later.contains(id) {
            out.append(id)
            if out.count == limit { break }
        }
        return out
    }

    /// One line for the screen: why it is paused, what it is doing, or that it is done.
    static func status(pause: DriveSyncPause, counts: DriveSyncCounts, working: String?) -> String {
        if let why = pause.sentence { return why }
        if let working { return working }
        if counts.notYet == 0, counts.sending == 0 { return "Up to date. Everything here is in Drive." }
        if counts.sending > 0 {
            return counts.notYet > 0 ? "Sending \(counts.sending) · \(counts.notYet) to go" : "Sending the last \(counts.sending)"
        }
        return counts.notYet == 1 ? "1 photo to go" : "\(counts.notYet) photos to go"
    }
}

/// `POST api/native/drive/have?space=`: which of these bytes Drive holds.
struct DriveHaveRequest: Encodable, Equatable {
    struct Item: Encodable, Equatable {
        let sha256: String
        let size: Int
    }

    let items: [Item]
}

struct DriveHaveReply: Decodable, Equatable {
    struct Hit: Decodable, Equatable {
        let sha256: String
        let file: DriveFile
    }

    let have: [Hit]
    /// Drive's pictures not fingerprinted yet: a "not had" may still be had.
    let unchecked: Int?

    /// The file holding these bytes, if Drive named one of the same size.
    func file(sha256: String, size: Int) -> DriveFile? {
        have.first { $0.sha256 == sha256.lowercased() && $0.file.sizeBytes == size }?.file
    }
}

extension DriveMoveLedger {
    /// A photo Drive named as already holding (sync's own check): written
    /// down exactly as an upload's 200 duplicate would be.
    func recordingKnown(assetId: String, fileId: String, space: DriveSpace, at now: Date = Date()) -> DriveMoveLedger {
        guard !assetId.isEmpty, !fileId.isEmpty, !contains(assetId) else { return self }
        var next = self
        next.entries.append(Entry(assetId: assetId, fileId: fileId, space: space, storedAt: now))
        return next
    }

    /// Every library photo it holds, removed from the phone or not.
    var assetIds: Set<String> { Set(entries.map(\.assetId)) }
}
