import Foundation
import ActivityKit

/// Hands the site the two tokens a family-journey Live Activity needs.
///
/// 1. The PUSH-TO-START token (iOS 17.2+): lets the site put a journey on
///    this phone's Lock Screen while the app is closed. One per phone per
///    activity type; sent once per launch per site credential, like the
///    ordinary push token (`PushRegistration`).
/// 2. Each running activity's UPDATE token: what the site moves the journey
///    on and ends it with. iOS wakes the app in the background when the site
///    starts an activity, which is when this hears about it
///    (`activityUpdates`) and reports its token.
///
/// A journey with no update token reported still shows, and goes grey at its
/// stale date — so a failure here costs freshness, never a stuck card.
@MainActor
final class JourneyLive {
    static let shared = JourneyLive()

    private var started = false
    private var startToken: String?
    private var startSentFor: String?
    private var watched = Set<String>()

    /// Begin listening. Called at launch, before any scene exists, because a
    /// push-started activity wakes the app in the background to hear about it.
    func start() {
        guard !started, !Self.isDemo else { return }
        started = true
        if #available(iOS 17.2, *) {
            Task {
                for await data in Activity<JourneyAttributes>.pushToStartTokenUpdates {
                    self.startToken = Self.hex(data)
                    self.startSentFor = nil
                    await self.sync()
                }
            }
        }
        Task {
            for await activity in Activity<JourneyAttributes>.activityUpdates {
                self.watch(activity)
            }
        }
        for activity in Activity<JourneyAttributes>.activities { watch(activity) }
    }

    /// Send the start token if this site credential does not have it yet.
    /// Called again whenever the site pairing changes (`PushRegistration.sync`).
    func sync() async {
        guard let startToken, let credential = SiteClient.shared.token, startSentFor != credential else { return }
        if await post(["liveActivityStartToken": startToken]) { startSentFor = credential }
    }

    func endAll() async {
        startSentFor = nil
        for activity in Activity<JourneyAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func watch(_ activity: Activity<JourneyAttributes>) {
        guard watched.insert(activity.id).inserted else { return }
        let journey = activity.attributes.journeyId
        Task {
            for await data in activity.pushTokenUpdates {
                _ = await self.post(["journeyId": journey, "activityToken": Self.hex(data)])
            }
        }
    }

    /// The owner's pretend journey: starts on this phone, moves twice, arrives.
    func runTest() async -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Live Activities are off for this app: Settings → SR → Live Activities."
        }
        await sync()
        guard startToken != nil else { return "This iPhone has no Live Activity token yet. Reopen the app and try again." }
        struct Reply: Decodable { let ok: Bool; let status: Int; let reason: String? }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["liveActivityTest": true])
            let reply: Reply = try await SiteClient.shared.send("api/native/push", method: "POST", body: body, asSelf: true)
            return reply.ok
                ? "Started. Lock the phone: it moves twice and arrives within a minute."
                : "Apple refused it: \(reply.reason ?? "status \(reply.status)")."
        } catch {
            return error.localizedDescription
        }
    }

    private func post(_ fields: [String: String]) async -> Bool {
        guard SiteClient.shared.isPaired, let body = try? JSONSerialization.data(withJSONObject: fields) else { return false }
        do {
            let _: EmptyReply = try await SiteClient.shared.send("api/native/push", method: "POST", body: body, asSelf: true)
            return true
        } catch {
            return false
        }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static var isDemo: Bool { SRDemo.isOn }
}
