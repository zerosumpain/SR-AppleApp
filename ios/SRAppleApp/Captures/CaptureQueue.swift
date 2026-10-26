import Foundation

// Captures waiting on the phone: recorded, perhaps read, not yet all the way
// up. Kept on disk so a capture made with no signal — or one iOS killed the
// app halfway through sending — goes up later, whole.
//
// Every field decodes `decodeIfPresent ?? default` BY HAND. Swift's
// synthesised `Codable` throws `keyNotFound` on a missing key whatever the
// property's default, so one field added in a later build would otherwise
// make the whole queue unreadable on upgrade — and a queue that cannot be
// read is recordings lost.
//
// Foundation only (`scripts/captures-check.sh`).

struct PendingCapture: Codable, Equatable, Identifiable {
    /// The phone's own id, also the files' names. Not the server's.
    var id: String
    var startedAt: Date
    var endedAt: Date
    /// The recording's file name in `CaptureFiles.directory`, or nil once sent
    /// and removed (or for a screenshot-only capture).
    var audioFile: String?
    var screenshotFile: String?
    var transcript: String
    var turns: [CaptureTurn]
    var speakerCount: Int
    var ownerSpeaker: String?
    var ocrText: String?
    var appHint: String?
    /// The deny list matched: the image and its OCR text never leave.
    var screenDenied: Bool
    var screenDeniedReason: String?
    var place: CapturePlace?
    /// "button" | "app" | "shortcut".
    var source: String
    /// The phone has transcribed, diarized and read the screenshot (or tried
    /// to `processAttempts` times — then it goes up as it is and the server
    /// transcribes).
    var processed: Bool
    var processAttempts: Int
    /// Set once `POST /api/native/captures` answered.
    var serverId: String?
    var audioSent: Bool
    var screenSent: Bool
    var attempts: Int
    var lastError: String?
    var lastTriedAt: Date?

    init(id: String = UUID().uuidString, startedAt: Date, endedAt: Date, audioFile: String? = nil,
         screenshotFile: String? = nil, transcript: String = "", turns: [CaptureTurn] = [], speakerCount: Int = 0,
         ownerSpeaker: String? = nil, ocrText: String? = nil, appHint: String? = nil, screenDenied: Bool = false,
         screenDeniedReason: String? = nil, place: CapturePlace? = nil, source: String = "app",
         processed: Bool = false, processAttempts: Int = 0, serverId: String? = nil, audioSent: Bool = false,
         screenSent: Bool = false, attempts: Int = 0, lastError: String? = nil, lastTriedAt: Date? = nil) {
        self.id = id; self.startedAt = startedAt; self.endedAt = endedAt; self.audioFile = audioFile
        self.screenshotFile = screenshotFile; self.transcript = transcript; self.turns = turns
        self.speakerCount = speakerCount; self.ownerSpeaker = ownerSpeaker; self.ocrText = ocrText
        self.appHint = appHint; self.screenDenied = screenDenied; self.screenDeniedReason = screenDeniedReason
        self.place = place; self.source = source; self.processed = processed; self.processAttempts = processAttempts
        self.serverId = serverId; self.audioSent = audioSent; self.screenSent = screenSent; self.attempts = attempts
        self.lastError = lastError; self.lastTriedAt = lastTriedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, audioFile, screenshotFile, transcript, turns, speakerCount, ownerSpeaker,
             ocrText, appHint, screenDenied, screenDeniedReason, place, source, processed, processAttempts,
             serverId, audioSent, screenSent, attempts, lastError, lastTriedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The one field without which a row is not a capture at all.
        id = try c.decode(String.self, forKey: .id)
        let started = c.capValue(.startedAt, Date(timeIntervalSince1970: 0))
        startedAt = started
        endedAt = c.capValue(.endedAt, started)
        audioFile = c.capOptional(.audioFile)
        screenshotFile = c.capOptional(.screenshotFile)
        transcript = c.capValue(.transcript, "")
        turns = c.capList(.turns)
        speakerCount = c.capValue(.speakerCount, 0)
        ownerSpeaker = c.capOptional(.ownerSpeaker)
        ocrText = c.capOptional(.ocrText)
        appHint = c.capOptional(.appHint)
        screenDenied = c.capValue(.screenDenied, false)
        screenDeniedReason = c.capOptional(.screenDeniedReason)
        place = c.capOptional(.place)
        source = c.capValue(.source, "app")
        processed = c.capValue(.processed, false)
        processAttempts = c.capValue(.processAttempts, 0)
        serverId = c.capOptional(.serverId)
        audioSent = c.capValue(.audioSent, false)
        screenSent = c.capValue(.screenSent, false)
        attempts = c.capValue(.attempts, 0)
        lastError = c.capOptional(.lastError)
        lastTriedAt = c.capOptional(.lastTriedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encodeIfPresent(audioFile, forKey: .audioFile)
        try c.encodeIfPresent(screenshotFile, forKey: .screenshotFile)
        try c.encode(transcript, forKey: .transcript)
        try c.encode(turns, forKey: .turns)
        try c.encode(speakerCount, forKey: .speakerCount)
        try c.encodeIfPresent(ownerSpeaker, forKey: .ownerSpeaker)
        try c.encodeIfPresent(ocrText, forKey: .ocrText)
        try c.encodeIfPresent(appHint, forKey: .appHint)
        try c.encode(screenDenied, forKey: .screenDenied)
        try c.encodeIfPresent(screenDeniedReason, forKey: .screenDeniedReason)
        try c.encodeIfPresent(place, forKey: .place)
        try c.encode(source, forKey: .source)
        try c.encode(processed, forKey: .processed)
        try c.encode(processAttempts, forKey: .processAttempts)
        try c.encodeIfPresent(serverId, forKey: .serverId)
        try c.encode(audioSent, forKey: .audioSent)
        try c.encode(screenSent, forKey: .screenSent)
        try c.encode(attempts, forKey: .attempts)
        try c.encodeIfPresent(lastError, forKey: .lastError)
        try c.encodeIfPresent(lastTriedAt, forKey: .lastTriedAt)
    }

    // MARK: What happens next

    enum Stage: Equatable {
        /// Transcribe, diarize, read the screenshot.
        case process
        /// `POST` the metadata.
        case create
        /// `PUT` the recording.
        case audio
        /// `PUT` the screenshot.
        case screen
        /// Nothing left: remove from the queue.
        case done
    }

    /// How many times the phone tries to read a capture before sending it
    /// as it is. A recording that crashes the transcriber every time must
    /// still go up.
    static let maxProcessAttempts = 2

    var stage: Stage {
        if !processed && processAttempts < Self.maxProcessAttempts { return .process }
        if serverId == nil { return .create }
        if audioFile != nil && !audioSent { return .audio }
        if sendsScreenshot && !screenSent { return .screen }
        return .done
    }

    /// The screenshot goes up only if there is one and it was not denied.
    var sendsScreenshot: Bool { screenshotFile != nil && !screenDenied }

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

    /// The metadata body. A denied screenshot sends the app's name and
    /// nothing it showed.
    func createRequest() -> CaptureCreateRequest {
        let screen: CaptureCreateRequest.Screen?
        if screenshotFile != nil || ocrText != nil || appHint != nil || screenDenied {
            screen = CaptureCreateRequest.Screen(
                ocrText: screenDenied ? "" : (ocrText ?? ""),
                appHint: appHint,
                denied: screenDenied
            )
        } else {
            screen = nil
        }
        return CaptureCreateRequest(
            startedAt: CaptureClock.iso(startedAt),
            endedAt: CaptureClock.iso(endedAt),
            transcript: transcript,
            turns: turns,
            speakerCount: max(speakerCount, turns.isEmpty ? 0 : 1),
            ownerSpeaker: ownerSpeaker,
            screen: screen,
            place: place,
            audio: audioFile != nil,
            screenshot: sendsScreenshot,
            source: ["button", "app", "shortcut"].contains(source) ? source : "app"
        )
    }

    /// Back off after failures: 30 s, 1, 2, 4… minutes, never more than an
    /// hour, so a dead network does not wake the radio every few seconds.
    func isDue(now: Date = Date()) -> Bool {
        guard attempts > 0, let lastTriedAt else { return true }
        let wait = min(30 * pow(2, Double(min(attempts - 1, 12))), 3600)
        return now.timeIntervalSince(lastTriedAt) >= wait
    }

    /// What the queue row says on the Captures page.
    var statusLine: String {
        switch stage {
        case .process: return "Reading it on the phone"
        case .create, .audio, .screen:
            if let lastError, attempts > 0 { return "Waiting to send · \(lastError)" }
            return "Waiting to send"
        case .done: return "Sent"
        }
    }
}

/// The queue file: a version and the rows. A row that does not decode is
/// dropped alone, never the file.
struct CaptureQueueFile: Codable, Equatable {
    var version: Int
    var items: [PendingCapture]

    init(items: [PendingCapture]) { version = 1; self.items = items }

    private enum CodingKeys: String, CodingKey { case version, items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.capValue(.version, 1)
        items = c.capList(.items)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(items, forKey: .items)
    }

    static func decode(_ data: Data) -> CaptureQueueFile {
        (try? JSONDecoder().decode(CaptureQueueFile.self, from: data)) ?? CaptureQueueFile(items: [])
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
}

/// Where a capture's files live: Application Support, out of iCloud backup,
/// protected until first unlock (a capture started from the Lock Screen has
/// to be writable before the phone is opened).
enum CaptureFiles {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("captures", isDirectory: true)
    }

    static var queueURL: URL { directory.appendingPathComponent("queue.json") }

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static func prepare() {
        var dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
    }

    static func remove(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: url(name))
    }
}
