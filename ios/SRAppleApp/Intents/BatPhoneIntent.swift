import AppIntents
import Foundation

// The bat phone from outside the app: the Control Center and Lock Screen
// control (iOS 18, `SRAppleLive/FamilyMessagesWidgets.swift`), and the
// Shortcuts app, which lists every intent — so the Action Button can run it.
//
// It OPENS the app on the bat phone's check and sends nothing itself. A
// control, a Shortcut or a widget is pressed by accident far more often than
// a button in the app; the send stays behind the in-app button's own guard
// (`BatPhoneButton`), where the person can see what it does.
//
// Compiled into BOTH the app and the SRAppleLive extension (`watch.yml`), as
// the capture intents are: the control names this type, and an intent in
// both targets runs in the APP. The extension's copy is built with
// `SR_LIVE_EXTENSION` and does nothing.
//
// The metadata names no Apple product (ITMS-90626 —
// `scripts/check-intent-metadata.mjs`).

struct OpenBatPhoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Bat phone"
    static var description = IntentDescription(
        "Open the bat phone in SR. Nothing is sent until you press its button there."
    )
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if SR_LIVE_EXTENSION
        return .result()
        #else
        guard BatPhoneLink.allowed else { throw AccessRefusal.unavailable }
        BatPhoneLink.shared.open()
        return .result()
        #endif
    }
}
