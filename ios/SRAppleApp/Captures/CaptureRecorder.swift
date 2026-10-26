import Foundation
import AVFoundation
import ActivityKit
import CoreLocation
import UIKit

/// The microphone, for a capture.
///
/// Records exactly while the owner is recording and not a moment more: there
/// is no wake word, no buffer kept running, and no listening between
/// captures. Started by the in-app button or an intent (`StartCaptureIntent`),
/// with the Live Activity (`CaptureLive`) up for as long as it runs — iOS
/// keeps background recording alive only while one shows — and both end at
/// Stop. The `audio` background mode is what lets a recording started from
/// the Action Button carry on with the screen locked; it is never used to
/// keep the app awake otherwise.
///
/// The same format as chat's voice notes (`VoiceRecorder.settings`): AAC,
/// mono, 22 kHz, about 350 KB a minute. Written straight to Application
/// Support, so a recording survives the app being killed before it is sent.
@MainActor
final class CaptureRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = CaptureRecorder()

    @Published private(set) var recording = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var withScreenshot = false
    /// Why the last start failed, in words for the Captures page.
    @Published private(set) var problem: String?

    /// Shorter than this is a mis-press, not a capture.
    static let minimumLength: TimeInterval = 1.0
    /// A capture stops itself after this: two hours is ~42 MB, under the
    /// server's 60 MB cap, and a forgotten recording should not run all day.
    static let maximumLength: TimeInterval = 2 * 3600

    private var recorder: AVAudioRecorder?
    private var id: String?
    private var source = "app"
    private var screenshotFile: String?
    private var limit: Task<Void, Never>?
    private var interruption: NSObjectProtocol?

    enum Failure: LocalizedError {
        case denied, unavailable, busy

        var errorDescription: String? {
            switch self {
            case .denied: return "The microphone is off for SR. Turn it on in Settings → SR → Microphone."
            case .unavailable: return "The microphone wouldn't start."
            case .busy: return "Another app is using the microphone."
            }
        }
    }

    /// Start, or stop if already recording.
    func toggle(source: String = "app") async {
        if recording {
            await stop()
        } else {
            do { try await start(source: source, screenshot: nil) } catch { problem = error.localizedDescription }
        }
    }

    /// Begin recording. `screenshot`: the image a Shortcut took at the press,
    /// kept beside the recording until it has been read on the phone.
    func start(source: String, screenshot: Data?) async throws {
        guard !recording else { return }
        problem = nil
        // Asked the first time the owner records from inside the app. From the
        // Action Button with no answer yet, iOS cannot ask and this says so.
        guard await AVAudioApplication.requestRecordPermission() else {
            problem = Failure.denied.localizedDescription
            throw Failure.denied
        }
        CaptureFiles.prepare()
        let id = UUID().uuidString
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            problem = Failure.busy.localizedDescription
            throw Failure.busy
        }
        let file = CaptureFiles.url("\(id).m4a")
        let made: AVAudioRecorder
        do {
            made = try AVAudioRecorder(url: file, settings: VoiceRecorder.settings)
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            problem = Failure.unavailable.localizedDescription
            throw Failure.unavailable
        }
        made.delegate = self
        guard made.record() else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            problem = Failure.unavailable.localizedDescription
            throw Failure.unavailable
        }
        recorder = made
        self.id = id
        self.source = source
        screenshotFile = screenshot.flatMap { Self.saveScreenshot($0, id: id) }
        let now = Date()
        startedAt = now
        withScreenshot = screenshotFile != nil
        recording = true
        watchInterruptions()
        await CaptureLive.shared.start(startedAt: now, source: source, withScreenshot: withScreenshot)
        limit = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maximumLength))
            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }

    /// Stop, end the Live Activity, queue the capture and start reading it.
    func stop() async {
        guard recording, let recorder, let id, let startedAt else {
            await CaptureLive.shared.endAll()
            return
        }
        let length = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        limit?.cancel()
        limit = nil
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
        interruption = nil
        recording = false
        self.startedAt = nil
        withScreenshot = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        await CaptureLive.shared.endAll()

        let audio = "\(id).m4a"
        guard length >= Self.minimumLength || screenshotFile != nil else {
            CaptureFiles.remove(audio)
            CaptureFiles.remove(screenshotFile)
            screenshotFile = nil
            self.id = nil
            return
        }
        let ended = Date()
        let pending = PendingCapture(
            id: id,
            startedAt: startedAt,
            endedAt: ended,
            audioFile: length >= Self.minimumLength ? audio : nil,
            screenshotFile: screenshotFile,
            place: Self.lastPlace(near: startedAt),
            source: source
        )
        if pending.audioFile == nil { CaptureFiles.remove(audio) }
        screenshotFile = nil
        self.id = nil
        CaptureStore.shared.enqueue(pending)
    }

    /// Throw the recording away: nothing is kept or sent.
    func discard() async {
        guard recording, let recorder, let id else { return }
        recorder.stop()
        recorder.deleteRecording()
        self.recorder = nil
        limit?.cancel()
        limit = nil
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
        interruption = nil
        recording = false
        startedAt = nil
        withScreenshot = false
        CaptureFiles.remove("\(id).m4a")
        CaptureFiles.remove(screenshotFile)
        screenshotFile = nil
        self.id = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        await CaptureLive.shared.endAll()
    }

    /// A phone call or another app taking the microphone ends the capture
    /// where it is, kept — not silently paused with the timer still running.
    private func watchInterruptions() {
        interruption = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in await self?.stop() }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in await self.stop() }
    }

    /// The screenshot as a JPEG no larger than chat sends a photo, or nil if
    /// it is not an image.
    private static func saveScreenshot(_ data: Data, id: String) -> String? {
        guard let image = ChatUpload.downscaled(data), let photo = ChatUpload.photo(image) else { return nil }
        let name = "\(id).jpg"
        do {
            try photo.data.write(to: CaptureFiles.url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return name
        } catch {
            return nil
        }
    }

    /// Where the phone already knew it was, if that fix is recent. The cached
    /// fix only: asking for a new one would start the GPS for a capture.
    private static func lastPlace(near date: Date) -> CapturePlace? {
        let manager = CLLocationManager()
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse,
              let fix = manager.location,
              abs(fix.timestamp.timeIntervalSince(date)) < 15 * 60,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy < 500 else { return nil }
        return CapturePlace(lat: fix.coordinate.latitude, lon: fix.coordinate.longitude)
    }
}

/// The capture's Live Activity: up at start, gone at Stop.
@MainActor
final class CaptureLive {
    static let shared = CaptureLive()
    private init() {}

    func start(startedAt: Date, source: String, withScreenshot: Bool) async {
        await endAll()
        guard !SRDemo.isOn, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = CaptureAttributes.ContentState(
            startedAt: startedAt.timeIntervalSince1970.rounded(),
            phase: "recording",
            withScreenshot: withScreenshot
        )
        _ = try? Activity.request(
            attributes: CaptureAttributes(source: source),
            content: ActivityContent(state: state, staleDate: startedAt.addingTimeInterval(CaptureRecorder.maximumLength)),
            pushType: nil
        )
    }

    /// Every capture card, at once. Called at Stop, on discard, and on launch
    /// (a card left by an app that was killed while recording).
    func endAll() async {
        for activity in Activity<CaptureAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
