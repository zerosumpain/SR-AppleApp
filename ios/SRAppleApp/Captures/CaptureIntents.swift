import AppIntents
import Foundation
import UniformTypeIdentifiers

// Start and stop a capture from anywhere: the Action Button, a Control Center
// or Lock Screen control, Back Tap (through a Shortcut), the Live Activity's
// Stop button, or a personal Shortcut that takes a screenshot first.
//
// Compiled into BOTH the app and the SRAppleLive extension (`watch.yml`): the
// control and the Live Activity's button name these intents, so the
// extension must see their types, and an intent in both targets is performed
// in the APP's process — which owns the microphone, the queue and the
// credential. The extension's copy is built with `SR_LIVE_EXTENSION` and does
// nothing; it is never the one that runs.
//
// The metadata names no Apple product (ITMS-90626 —
// `scripts/check-intent-metadata.mjs`).

/// Start a capture — or, if one is recording, stop it, so one button does
/// both. iOS 18: `AudioRecordingIntent` records without bringing the app
/// forward, as long as the Live Activity shows while it runs.
@available(iOS 18.0, *)
struct StartCaptureIntent: AudioRecordingIntent {
    static var title: LocalizedStringResource = "Start capture"
    static var description = IntentDescription(
        "Record what is said and send it to Strange Ramblings to be transcribed and read. Run it again to stop. A screenshot taken just before can go with it."
    )

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
    var screenshot: IntentFile?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if SR_LIVE_EXTENSION
        return .result()
        #else
        guard AccessStore.ownerSite else { throw AccessRefusal.unavailable }
        let recorder = CaptureRecorder.shared
        if recorder.recording {
            await recorder.stop()
        } else {
            let image = screenshot?.data
            try await recorder.start(source: image == nil ? "button" : "shortcut", screenshot: image)
        }
        return .result()
        #endif
    }
}

/// "New capture" — the phrase and Spotlight tile. Opens the app on Captures
/// and starts recording (or stops, if one is running). iOS 17, so it can sit
/// in `SRShortcuts`, whose builder takes no availability check: that is what
/// puts it in Siri, Spotlight and the Action Button's Shortcut list with no
/// setup at all. `StartCaptureIntent` stays the one that records without
/// opening the app.
struct NewCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "New capture"
    static var description = IntentDescription("Open Captures and start recording. Run it again to stop.")
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if SR_LIVE_EXTENSION
        return .result()
        #else
        guard AccessStore.ownerSite else { throw AccessRefusal.unavailable }
        AppDelegate.pending.capture = CaptureLink(captureId: nil)
        NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
        await CaptureRecorder.shared.toggle(source: "button")
        return .result()
        #endif
    }
}

/// Stop the capture that is recording, and send it. The Live Activity's
/// Stop button runs this (a `LiveActivityIntent`, so iOS 17).
struct StopCaptureIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop capture"
    static var description = IntentDescription("Stop the capture that is recording and send it to be read.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if SR_LIVE_EXTENSION
        return .result()
        #else
        await CaptureRecorder.shared.stop()
        return .result()
        #endif
    }
}
