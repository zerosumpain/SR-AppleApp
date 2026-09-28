import Foundation
import UIKit

/// This phone's APNs token, handed to the site.
///
/// ## What push changed
///
/// Until 2026-09-28 every notification here was pulled: a background refresh
/// iOS runs when it likes, a five-second poll while Games is open. The site
/// now pushes the owner's alerts (a chat turn waiting on an answer among them),
/// game invites and household departures the moment they happen — as long as
/// it holds this phone's token, which is what this does.
///
/// ## Why on every launch
///
/// iOS may change the token at any time and always does on a restore, and
/// registering never shows a prompt — whether a push is SHOWN is the separate
/// notification permission. So the app asks for a token on each launch and
/// sends it once per launch per site credential. The server stores it on the
/// credential row, so a re-sent token is an update, never a second phone.
///
/// ## Which gateway
///
/// An Xcode build talks to Apple's sandbox gateway and a TestFlight build to
/// production; a token sent to the wrong one is refused as `BadDeviceToken`.
/// DEBUG is an Xcode build here — CI's debug builds never reach a device.
///
/// Pull stays. A phone with no token, a push Apple drops, a site that cannot
/// push: the refresh still collects everything, as it did before.
@MainActor
final class PushRegistration {
    static let shared = PushRegistration()

    /// Hex, as Apple's HTTP/2 API wants it.
    private(set) var token: String?
    /// The site credential the current token was last accepted for.
    private var sentFor: String?

    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    /// Ask iOS for a token. No prompt; the answer arrives at the app delegate.
    func start(_ application: UIApplication) {
        guard !Self.isDemo else { return }
        application.registerForRemoteNotifications()
    }

    func received(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        if hex != token { sentFor = nil }
        token = hex
        Task { await sync() }
    }

    /// Send the token to the site, unless this credential already has it.
    /// Silent on failure: the next launch sends it again, and until then the
    /// phone is exactly as reachable as it was before push existed.
    func sync() async {
        // The Live Activity start token rides the same credential; it keeps
        // its own "already sent" mark.
        await JourneyLive.shared.sync()
        guard !Self.isDemo, let token, let credential = SiteClient.shared.token else { return }
        guard sentFor != credential else { return }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["token": token, "environment": Self.environment])
            let _: EmptyReply = try await SiteClient.shared.send("api/native/push", method: "POST", body: body, asSelf: true)
            sentFor = credential
        } catch {
            return
        }
    }

    /// "Send a test notification", from the notification settings. The
    /// sentence is Apple's answer in words, for whoever is checking the wiring.
    func sendTest() async -> String {
        await sync()
        guard token != nil else { return "This iPhone has no push token yet. Reopen the app and try again." }
        struct Reply: Decodable { let ok: Bool; let status: Int; let reason: String? }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["test": true])
            let reply: Reply = try await SiteClient.shared.send("api/native/push", method: "POST", body: body, asSelf: true)
            return reply.ok ? "Sent. It should arrive in a few seconds." : "Apple refused it: \(reply.reason ?? "status \(reply.status)")."
        } catch {
            return error.localizedDescription
        }
    }

    private static var isDemo: Bool { SRDemo.isOn }
}
