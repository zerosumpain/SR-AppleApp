import SwiftUI
import AVFoundation

/// Hold to talk.
///
/// AAC in an MP4 box (`.m4a`), mono, 22 kHz: a minute is about 350 KB, which
/// uploads on a train, and speech loses nothing at that rate. The site
/// transcribes it before the model sees it — `audio/mp4` is on its list, and
/// the `audio/x-m4a` that sniffing produces is folded into it on arrival.
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
