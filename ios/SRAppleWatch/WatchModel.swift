import Foundation
import SwiftUI
import WatchConnectivity
import WidgetKit

/// The Watch's half of the bridge. It holds the last snapshot the phone sent
/// and passes what the wrist asks for back to the phone. It never talks to the
/// site: the phone holds the credential, so revoking the phone revokes this.
@MainActor
final class WatchModel: NSObject, ObservableObject {
    static let shared = WatchModel()

    @Published private(set) var snapshot: WatchSnapshot
    /// The phone's answer to the last command, shown for a moment.
    @Published var toast: WatchReply?
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var reachable = false

    private var session: WCSession?

    override init() {
        // The last copy, so the app opens on numbers rather than a spinner.
        snapshot = WatchShelf.load() ?? .empty
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    /// How old the numbers are, for the line that says so.
    var isStale: Bool { Date().timeIntervalSince(snapshot.generatedAt) > 30 * 60 }

    private func adopt(_ next: WatchSnapshot) {
        guard next.generatedAt >= snapshot.generatedAt else { return }
        snapshot = next
        WatchShelf.save(next)
        // Complications draw from the shelf; tell them it moved.
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Commands

    /// Send a command. With the phone in reach the answer comes straight back;
    /// out of reach it is queued and done when they meet again — the snapshot
    /// that follows is the answer.
    func send(_ command: WatchCommand, key: String) {
        guard let session, session.activationState == .activated else {
            toast = WatchReply(ok: false, text: "No iPhone connection")
            return
        }
        busy.insert(key)
        if session.isReachable {
            session.sendMessage(command.message, replyHandler: { reply in
                Task { @MainActor in
                    self.busy.remove(key)
                    self.toast = WatchReply(message: reply)
                }
            }, errorHandler: { _ in
                Task { @MainActor in
                    // Reachable a moment ago and not now: queue it rather than lose it.
                    session.transferUserInfo(command.message)
                    self.busy.remove(key)
                    self.toast = WatchReply(ok: true, text: "Queued for your iPhone")
                }
            })
        } else {
            session.transferUserInfo(command.message)
            busy.remove(key)
            toast = WatchReply(ok: true, text: "Queued for your iPhone")
        }
    }

    /// Optimistic, so a swiped row goes at once; the phone's next snapshot is
    /// the truth either way.
    func clear(_ alert: WatchSnapshot.Alert) {
        dropAlert(alert.id)
        send(.clearFromToday(id: alert.id), key: "clear-\(alert.id)")
    }

    func markRead(_ alert: WatchSnapshot.Alert) {
        send(.markRead(id: alert.id), key: "read-\(alert.id)")
    }

    private func dropAlert(_ id: String) {
        let s = snapshot
        snapshot = WatchSnapshot(
            version: s.version, generatedAt: s.generatedAt, readiness: s.readiness, recovery: s.recovery,
            figures: s.figures, healthUpdatedAt: s.healthUpdatedAt,
            alerts: s.alerts.filter { $0.id != id }, unread: s.unread, showsAlerts: s.showsAlerts,
            sync: s.sync, connectionNeedsFixing: s.connectionNeedsFixing,
            pinnedFlows: s.pinnedFlows, canAsk: s.canAsk
        )
    }

    func requestRefresh() {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(WatchCommand.refresh.message, replyHandler: nil, errorHandler: nil)
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in
            if let snapshot = WatchSnapshot.from(context: context) { self.adopt(snapshot) }
            self.reachable = session.isReachable
            if self.isStale { self.requestRefresh() }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.reachable = session.isReachable
            if session.isReachable, self.isStale { self.requestRefresh() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let snapshot = WatchSnapshot.from(context: applicationContext) else { return }
        Task { @MainActor in self.adopt(snapshot) }
    }
}
