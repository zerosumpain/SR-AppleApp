import SwiftUI
import AVFoundation
import Speech

/// Hold to talk.
///
/// AAC in an MP4 box (`.m4a`), mono, 22 kHz: a minute is about 350 KB, which
/// uploads on a train, and speech loses nothing at that rate. The PHONE
/// transcribes it (`VoiceTranscriber`) and the words are what the model reads;
/// the audio goes up alongside for playback and /drive.
@MainActor
final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var recording = false
    @Published private(set) var elapsed: TimeInterval = 0

    /// Shorter than this is a tap, not a message.
    static let minimumLength: TimeInterval = 0.7

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var url: URL?

    enum Failure: Error { case denied, unavailable }

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw Failure.denied }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: file, settings: settings)
        recorder.delegate = self
        guard recorder.record() else { throw Failure.unavailable }
        self.recorder = recorder
        url = file
        elapsed = 0
        recording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed = self?.recorder?.currentTime ?? 0 }
        }
    }

    /// Stop, and hand back the recording if it was long enough to be one.
    func stop() -> Data? {
        let length = recorder?.currentTime ?? 0
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        recorder = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        defer { if let url { try? FileManager.default.removeItem(at: url) } ; url = nil }
        guard length >= Self.minimumLength, let url else { return nil }
        return try? Data(contentsOf: url)
    }

    func cancel() { _ = stop() }
}

/// A voice note in a sent turn: play, and how long it is.
struct VoiceNoteRow: View {
    let attachment: ChatAttachment
    let register: SRRegister
    @StateObject private var player = VoiceNotePlayer()

    var body: some View {
        Button {
            SRHaptic.tap()
            Task { await player.toggle(attachment.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: player.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(register.accent.opacity(0.18), in: Circle())
                Text("Voice note")
                    .font(SR.Text.bodyMedium(15))
                if let duration = player.duration {
                    Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                        .font(SR.Text.mono())
                }
                if player.loading { ProgressView().scaleEffect(0.6) }
            }
            .foregroundStyle(register.primary)
            .frame(minHeight: SR.tapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.playing ? "Pause voice note" : "Play voice note")
    }
}

@MainActor
final class VoiceNotePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playing = false
    @Published private(set) var loading = false
    @Published private(set) var duration: TimeInterval?
    private var player: AVAudioPlayer?

    func toggle(_ id: String) async {
        if let player, player.isPlaying {
            player.pause()
            playing = false
            return
        }
        if player == nil {
            loading = true
            defer { loading = false }
            guard let data = try? await SiteClient.shared.bytes("api/native/chat/attachments/\(id)"),
                  let made = try? AVAudioPlayer(data: data) else { return }
            made.delegate = self
            player = made
            duration = made.duration
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        playing = player?.play() ?? false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = false }
    }
}

/// Speech to text on this iPhone.
///
/// The site's own transcription rode an OpenRouter model that was retired, and
/// no Codex model takes audio, so a voice note reached the chat model as a file
/// it could not open. iOS already has a recogniser; on any recent iPhone it
/// runs ON THE DEVICE, so the recording goes nowhere to be read. (Where the
/// language has no on-device model, iOS uses Apple's own server instead.)
///
/// Nil on any failure — no permission, no recogniser, no words — and the note
/// then goes as audio alone, as it always did.
enum VoiceTranscriber {
    /// A voice note that takes longer than this to read is sent without words.
    static let timeout: Duration = .seconds(30)

    @MainActor
    static func transcribe(_ data: Data, locale: Locale = Locale(identifier: "en-GB")) async -> String? {
        guard await authorised() else { return nil }
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("transcribe-\(UUID().uuidString).m4a")
        guard (try? data.write(to: url)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let once = Once()
        let text: String? = await withCheckedContinuation { continuation in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    once.run { continuation.resume(returning: result.bestTranscription.formattedString) }
                } else if error != nil {
                    once.run { continuation.resume(returning: nil) }
                }
            }
            Task {
                try? await Task.sleep(for: timeout)
                once.run {
                    task.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Asked the first time a voice note is sent, never at launch.
    static func authorised() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    /// The recogniser can call back more than once, and the timeout races it:
    /// the continuation must be resumed exactly once.
    private final class Once: @unchecked Sendable {
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
}
