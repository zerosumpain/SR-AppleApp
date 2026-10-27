import Foundation
import AVFoundation
import CoreMedia
import Speech
import Vision
import UIKit

// Reading a capture on the phone, after Stop: speech to text, the
// screenshot's words, and which voice said what. Nothing here runs while
// recording, and nothing listens — every step works on the file.

// MARK: - The owner's choices

/// Settings → Captures, in UserDefaults.
enum CaptureSettings {
    private static let defaults = UserDefaults.standard
    private static let denyKey = "captures.denyList"
    private static let sensitiveKey = "captures.denySensitive"
    private static let cellularKey = "captures.modelsOnCellular"
    private static let diarizeKey = "captures.diarize"

    /// The apps whose screenshots never leave the phone.
    static var denyList: [String] {
        get { defaults.stringArray(forKey: denyKey) ?? ScreenshotPolicy.defaultDenyList }
        set { defaults.set(newValue, forKey: denyKey) }
    }

    /// Also deny a screen that shows a password, a code or a card number.
    static var denySensitive: Bool {
        get { defaults.object(forKey: sensitiveKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: sensitiveKey) }
    }

    /// Download the speaker models over mobile data. Off until the owner says.
    static var modelsOnCellular: Bool {
        get { defaults.bool(forKey: cellularKey) }
        set { defaults.set(newValue, forKey: cellularKey) }
    }

    /// Tell voices apart on the phone. On by default; off sends one speaker.
    static var diarize: Bool {
        get { defaults.object(forKey: diarizeKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: diarizeKey) }
    }
}

// MARK: - Speech to text

/// Speech to text, from the file. iOS 26: `SpeechAnalyzer` with
/// `SpeechTranscriber`, which reads a long recording on the device with no
/// one-minute cap. Before that: `SFSpeechRecognizer`, as chat's voice notes
/// use it, on the device where the language allows. Nil on any failure —
/// the capture then goes up without words and the server transcribes it.
///
/// One protocol, so a better model (Parakeet, Whisper) can be swapped in
/// later without touching the pipeline.
protocol CaptureTranscribing {
    func transcribe(_ url: URL, duration: TimeInterval) async -> [CaptureTimedText]?
}

enum CaptureTranscription {
    static let locale = Locale(identifier: "en-GB")

    static func transcribe(_ url: URL, duration: TimeInterval) async -> [CaptureTimedText]? {
        guard await VoiceTranscriber.authorised() else { return nil }
        if #available(iOS 26.0, *) {
            if let words = await AnalyzerTranscriber().transcribe(url, duration: duration), !words.isEmpty {
                return words
            }
        }
        return await RecognizerTranscriber().transcribe(url, duration: duration)
    }
}

@available(iOS 26.0, *)
struct AnalyzerTranscriber: CaptureTranscribing {
    func transcribe(_ url: URL, duration: TimeInterval) async -> [CaptureTimedText]? {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: CaptureTranscription.locale) else { return nil }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        do {
            // The speech model is the system's own, fetched once per language.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let file = try AVAudioFile(forReading: url)
            let collect = Task { () throws -> [CaptureTimedText] in
                var out: [CaptureTimedText] = []
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let start = result.range.start.seconds
                    let end = CMTimeRangeGetEnd(result.range).seconds
                    guard start.isFinite, end.isFinite else {
                        out += CaptureTurns.spread(text, start: out.last?.end ?? 0, end: out.last?.end ?? 0)
                        continue
                    }
                    out += CaptureTurns.spread(text, start: start, end: end)
                }
                return out
            }
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return try await collect.value
        } catch {
            return nil
        }
    }
}

/// `SFSpeechRecognizer` on the file, word by word.
struct RecognizerTranscriber: CaptureTranscribing {
    func transcribe(_ url: URL, duration: TimeInterval) async -> [CaptureTimedText]? {
        guard let recognizer = SFSpeechRecognizer(locale: CaptureTranscription.locale) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let once = CaptureOnce()
        let timeout = max(60, duration * 1.5)
        return await withCheckedContinuation { (continuation: CheckedContinuation<[CaptureTimedText]?, Never>) in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let words = result.bestTranscription.segments.map {
                        CaptureTimedText(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
                    }
                    once.run { continuation.resume(returning: words) }
                } else if error != nil {
                    once.run { continuation.resume(returning: nil) }
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                once.run {
                    task.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// A continuation resumed exactly once, whichever of the callback and the
/// timeout gets there first.
final class CaptureOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}

// MARK: - The screenshot's words

enum CaptureOCR {
    /// The text on screen, read on the phone, line by line. Nil if the
    /// image cannot be read.
    static func read(_ data: Data) async -> String? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        let once = CaptureOnce()
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                once.run { continuation.resume(returning: lines.joined(separator: "\n")) }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                once.run { continuation.resume(returning: nil) }
            }
            // `perform` is synchronous: if the handler never ran, nothing will.
            once.run { continuation.resume(returning: nil) }
        }
    }
}

// MARK: - The whole pass

enum CaptureProcessor {
    /// A recording longer than this is not read in the background, where iOS
    /// gives seconds rather than minutes: it waits for the app to be opened.
    static let backgroundLimit: TimeInterval = 120

    /// Read one capture: the screenshot (and whether it may leave the
    /// phone), the words, and the voices. Every step may come back empty;
    /// the capture is marked read either way, and the server fills in what
    /// the phone could not.
    static func process(_ item: PendingCapture) async -> PendingCapture {
        var out = item

        if let shot = item.screenshotFile, let data = try? Data(contentsOf: CaptureFiles.url(shot)) {
            let text = await CaptureOCR.read(data) ?? ""
            let verdict = ScreenshotPolicy.evaluate(
                ocrText: text, denyList: CaptureSettings.denyList, sensitive: CaptureSettings.denySensitive
            )
            out.appHint = verdict.appHint
            out.screenDenied = verdict.denied
            out.screenDeniedReason = verdict.reason
            if verdict.denied {
                // Neither the picture nor its words go anywhere — and the
                // picture is not kept on the phone either.
                out.ocrText = nil
                CaptureFiles.remove(shot)
                out.screenshotFile = nil
            } else {
                out.ocrText = String(text.prefix(8_000))
            }
        }

        if let audio = item.audioFile {
            let url = CaptureFiles.url(audio)
            let words = await CaptureTranscription.transcribe(url, duration: item.duration) ?? []
            var segments: [CaptureVoiceSegment] = []
            if CaptureSettings.diarize {
                segments = await CaptureDiarization.shared.diarize(url, duration: item.duration) ?? []
            }
            let result = CaptureTurns.build(words: words, segments: segments)
            out.turns = result.turns
            out.transcript = CaptureTurns.transcript(result.turns)
            out.speakerCount = result.speakerCount
            if let enrolled = OwnerVoice.load() {
                out.ownerSpeaker = CaptureOwnerMatch.ownerLabel(enrolled: enrolled, centroids: result.centroids)
            }
        }

        out.processed = true
        return out
    }
}

// MARK: - The owner's voice

/// The owner's voice, as one embedding: twenty seconds recorded once in
/// Settings → Captures, kept in Application Support and nowhere else. The
/// recording itself is deleted as soon as the embedding is made.
enum OwnerVoice {
    static let length: TimeInterval = 20

    private static var url: URL { CaptureFiles.directory.appendingPathComponent("owner-voice.json") }

    private struct Stored: Codable {
        var embedding: [Float]
        var madeAt: Date

        private enum CodingKeys: String, CodingKey { case embedding, madeAt }

        init(embedding: [Float], madeAt: Date) { self.embedding = embedding; self.madeAt = madeAt }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            embedding = c.capValue(.embedding, [])
            madeAt = c.capValue(.madeAt, Date(timeIntervalSince1970: 0))
        }
    }

    static func load() -> [Float]? {
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              !stored.embedding.isEmpty else { return nil }
        return stored.embedding
    }

    static var madeAt: Date? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(Stored.self, from: data))?.madeAt
    }

    static func save(_ embedding: [Float]) throws {
        CaptureFiles.prepare()
        let data = try JSONEncoder().encode(Stored(embedding: embedding, madeAt: Date()))
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func forget() { try? FileManager.default.removeItem(at: url) }
}
