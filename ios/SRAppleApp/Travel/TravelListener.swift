import Foundation
import UIKit
import AVFoundation
import Speech

/// Live speech to text from the microphone, cut into sentences at the pauses.
///
/// The recogniser keeps one transcription growing for as long as audio keeps
/// coming, so a guide talking for ten minutes would be one line. A pause of
/// `pause` ends the segment: its words go to `onSegment` and a fresh request
/// starts on the same microphone tap, with nothing lost between them.
///
/// On the device where the language has an on-device model (Italian and
/// English do on any recent phone), so it works with no signal; otherwise iOS
/// uses Apple's server and a segment is capped near a minute, which the pause
/// cut keeps well under.
@MainActor
final class TravelListener: ObservableObject {
    @Published private(set) var listening = false
    /// The words of the segment in progress, as they are heard.
    @Published private(set) var partial = ""
    @Published private(set) var problem: String?

    var onPartial: @MainActor (String) -> Void = { _ in }
    var onSegment: @MainActor (String) -> Void = { _ in }

    /// Silence that ends a sentence.
    var pause: TimeInterval = 1.4
    /// Stop after one sentence (conversation) or keep going (captions).
    var continuous = false

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private let feed = Feed()
    private var quiet: Task<Void, Never>?
    /// Bumped per segment, so a late callback from an ended one is ignored.
    private var segment = 0

    /// The audio thread appends to whichever request is current.
    private final class Feed: @unchecked Sendable {
        private let lock = NSLock()
        private var request: SFSpeechAudioBufferRecognitionRequest?

        func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
            lock.lock(); defer { lock.unlock() }
            self.request = request
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            lock.lock(); defer { lock.unlock() }
            request?.append(buffer)
        }

        func end() {
            lock.lock(); defer { lock.unlock() }
            request?.endAudio()
            request = nil
        }
    }

    /// Asked on the first tap, never at launch.
    static func authorise() async -> Bool {
        let speech: Bool
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speech = true
        case .notDetermined:
            speech = await withCheckedContinuation { c in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
            }
        default: speech = false
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    func start(_ speech: String) async {
        stop()
        problem = nil
        guard await Self.authorise() else {
            problem = "Microphone or speech recognition is off for SR. Turn both on in Settings → SR."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: speech)), recognizer.isAvailable else {
            problem = "This phone can't listen to that language right now."
            return
        }
        self.recognizer = recognizer
        let session = AVAudioSession.sharedInstance()
        do {
            // Play and record, out of the speaker: the translation is said
            // aloud to the person opposite straight after.
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            problem = "The microphone is busy."
            return
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            problem = "No microphone found."
            return
        }
        let feed = self.feed
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in feed.append(buffer) }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            problem = "The microphone wouldn't start."
            return
        }
        listening = true
        UIApplication.shared.isIdleTimerDisabled = true
        begin()
    }

    /// Stop listening; whatever was heard so far is kept as a segment.
    func stop() {
        guard listening else { return }
        listening = false
        quiet?.cancel()
        let last = partial
        finishSegment(emit: false)
        if !last.isEmpty { onSegment(last) }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func begin() {
        guard let recognizer else { return }
        segment += 1
        let mine = segment
        partial = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        feed.set(request)
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in self?.heard(text, final: final, failed: failed, segment: mine) }
        }
    }

    private func heard(_ text: String?, final: Bool, failed: Bool, segment mine: Int) {
        guard mine == segment, listening else { return }
        if let text, !text.isEmpty, text != partial {
            partial = text
            onPartial(text)
            armQuiet()
        }
        if final || failed {
            // The recogniser ended the segment itself (its own pause rule, or
            // the server's minute): keep the words and carry on.
            finishSegment(emit: true)
            if continuous { begin() } else { stop() }
        }
    }

    private func armQuiet() {
        quiet?.cancel()
        let wait = UInt64(pause * 1_000_000_000)
        quiet = Task { [weak self] in
            try? await Task.sleep(nanoseconds: wait)
            guard !Task.isCancelled else { return }
            self?.paused()
        }
    }

    private func paused() {
        guard listening, !partial.isEmpty else { return }
        finishSegment(emit: true)
        if continuous { begin() } else { stop() }
    }

    private func finishSegment(emit: Bool) {
        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        segment += 1
        feed.end()
        task?.cancel()
        task = nil
        partial = ""
        if emit, !text.isEmpty { onSegment(text) }
    }
}
