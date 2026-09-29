import Foundation
import Combine
import WatchConnectivity

/// The iPhone's side of the Watch app.
///
/// The Watch holds no credential (docs/WATCH.md, "Credentials"). This watches
/// the stores the phone already has — Today, the inbox, the connections, the
/// upload queue, the pinned workflows and what this person may see — and when
/// any of them moves it sends the Watch a fresh `WatchSnapshot` as the
/// WatchConnectivity application context. It makes no network call of its own
/// to do that. What the Watch asks for comes back as a `WatchCommand`, and each
/// one is something the phone already does from a screen or a notification
/// button, done the same way.
@MainActor
final class WatchBridge: NSObject, ObservableObject {
    static let shared = WatchBridge()

    /// Whether a Watch with the app installed is paired, for Settings.
    @Published private(set) var watchAppInstalled = false

    private var session: WCSession?
    private weak var companion: Companion?
    private var bag: [String: AnyCancellable] = [:]

    // The last value of each input. The snapshot is built from these.
    private var health: TodayHealth?
    private var latestAlerts: [TodayAlerts.Latest] = []
    private var recent: [SiteAlert] = []
    private var unread = 0
    private var cleared: Set<String> = []
    private var connectionNeedsFixing = false
    private var sync = WatchSnapshot.Sync(queued: 0, lastUpload: nil, gate: nil)

    private var lastSent: WatchSnapshot?
    private var publishTask: Task<Void, Never>?

    // MARK: - Wiring

    /// At launch, before any scene: a Watch message can wake the app in the
    /// background, and it must find a session that is already listening.
    func start(companion: Companion?) {
        self.companion = companion
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session

        if let companion {
            bag["queue"] = companion.$queueCount.sink { [weak self] queued in
                self?.noteSync(queued: queued)
            }
            bag["upload"] = companion.$lastUpload.sink { [weak self] last in
                self?.noteSync(lastUpload: last)
            }
            bag["gate"] = companion.location.$gate.sink { [weak self] gate in
                self?.noteSync(gate: gate.rawValue)
            }
        }
        bag["access"] = AccessStore.shared.$current.sink { [weak self] _ in self?.setNeedsPublish() }
        bag["pins"] = PinnedFlows.shared.$pins.sink { [weak self] _ in self?.setNeedsPublish() }
    }

    /// The inbox and the connections, from the instances `ContentView` holds.
    /// Not from transient stores (a background pass makes its own), whose
    /// empty state would otherwise reach the wrist.
    func attach(alerts: AlertStore, connections: ConnectionsStore) {
        bag["recent"] = alerts.$recent.sink { [weak self] recent in
            self?.recent = recent
            self?.setNeedsPublish()
        }
        bag["unread"] = alerts.$unread.sink { [weak self] unread in
            self?.unread = unread
            self?.setNeedsPublish()
        }
        bag["cleared"] = alerts.$clearedFromToday.sink { [weak self] cleared in
            self?.cleared = cleared
            self?.setNeedsPublish()
        }
        bag["connections"] = connections.$items.sink { [weak self] items in
            self?.connectionNeedsFixing = !items.isEmpty
            self?.setNeedsPublish()
        }
    }

    /// Today's payload: the health figures and Today's own first three alerts.
    func attach(today: TodayStore) {
        bag["today"] = today.$payload.sink { [weak self] payload in
            guard let self, let payload else { return }
            self.health = payload.health
            self.latestAlerts = payload.alerts?.latest ?? []
            self.setNeedsPublish()
        }
    }

    private func noteSync(queued: Int? = nil, lastUpload: Date?? = nil, gate: String? = nil) {
        sync = WatchSnapshot.Sync(
            queued: queued ?? sync.queued,
            lastUpload: lastUpload ?? sync.lastUpload,
            gate: gate ?? sync.gate
        )
        setNeedsPublish()
    }

    // MARK: - Sending

    /// Coalesced: a refresh moves four stores in the same second, and the Watch
    /// wants one context, not four.
    func setNeedsPublish() {
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.publish()
        }
    }

    var snapshot: WatchSnapshot {
        WatchSnapshotBuilder.build(
            health: health,
            recent: recent,
            latest: latestAlerts,
            cleared: cleared,
            unread: unread,
            access: AccessStore.shared.current,
            ownerSite: AccessStore.ownerSite,
            sync: sync,
            connectionNeedsFixing: connectionNeedsFixing,
            pinned: PinnedFlows.shared.pins,
            now: Date()
        )
    }

    private func publish(force: Bool = false) {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        let next = snapshot
        // `generatedAt` always moves; compare everything else.
        if !force, let lastSent, WatchSnapshotBuilder.sameContent(lastSent, next) { return }
        do {
            try session.updateApplicationContext(next.context())
            lastSent = next
        } catch {
            // Not paired after all, or the Watch app was removed. The next
            // change tries again.
        }
    }

    // MARK: - Commands from the wrist

    func handle(_ command: WatchCommand) async -> WatchReply {
        switch command {
        case .refresh:
            guard AccessStore.ownerSite else {
                publish(force: true)
                return WatchReply(ok: true, text: "Showing the iPhone’s last received data")
            }
            do {
                let fetched: TodayPayload = try await SiteClient.shared.send("api/native/today")
                health = fetched.health
                latestAlerts = fetched.alerts?.latest ?? []
                publish(force: true)
                let source = health?.generatedAt ?? "unknown"
                return WatchReply(ok: true, text: OfflineSnapshotStatus.shared.message ?? "Health source: \(source)")
            } catch {
                publish(force: true)
                return WatchReply(ok: false, text: "Could not refresh. Showing the last received data.")
            }

        case .markRead(let id):
            guard AccessStore.ownerSite else { return WatchReply(ok: false, text: "Not on this iPhone's access") }
            await AlertStore.markReadFromNotification(id)
            return WatchReply(ok: true, text: "Marked read")

        case .clearFromToday(let id):
            AlertStore.clearFromNotification(id)
            // The store `ContentView` holds re-reads through `changedElsewhere`
            // and its sink republishes; if no screen exists yet (a background
            // wake), read the defaults directly.
            cleared.insert(id)
            setNeedsPublish()
            return WatchReply(ok: true, text: "Cleared")

        case .syncNow:
            guard let companion else { return WatchReply(ok: false, text: "The iPhone app is not ready") }
            // Answered at once: a sync collects for a while, longer than a
            // Watch waits for a reply. The queue count in the next snapshot is
            // the result — and the same short window a background refresh gets.
            Task { await companion.sync(collectingFor: 15) }
            return WatchReply(ok: true, text: "Syncing on your iPhone")

        case .ask(let question):
            guard AccessStore.shared.allows(.chat) else { return WatchReply(ok: false, text: "No chat on this iPhone") }
            // In the composer, unsent — the rule `AskJkaiIntent` keeps.
            AppDelegate.pending.question = question
            NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
            return WatchReply(ok: true, text: "Waiting in the composer on your iPhone")

        case .runFlow(let slug):
            guard AccessStore.ownerSite else { return WatchReply(ok: false, text: "Workflows are the owner's") }
            guard let pin = PinnedFlows.shared.pins.first(where: { $0.slug == slug }) else {
                // Only a pinned flow runs from the wrist: an old snapshot must
                // not be able to start one that was unpinned since.
                return WatchReply(ok: false, text: "Not pinned any more")
            }
            do {
                let _: FlowRunStarted = try await SiteClient.shared.send(
                    "api/native/workflows/\(slug)/run", method: "POST", body: Data("{}".utf8)
                )
                return WatchReply(ok: true, text: "Started \(pin.title)")
            } catch {
                return WatchReply(ok: false, text: error.localizedDescription)
            }
        }
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.watchAppInstalled = session.isPaired && session.isWatchAppInstalled
            self.publish(force: true)
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.watchAppInstalled = session.isPaired && session.isWatchAppInstalled
            self.publish(force: true)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// A Watch was swapped for another: activate again for the new one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let command = WatchCommand(message: message) else {
            replyHandler(WatchReply(ok: false, text: "The iPhone app needs updating").message)
            return
        }
        Task { @MainActor in
            let reply = await self.handle(command)
            replyHandler(reply.message)
        }
    }

    /// The queued form, sent when the phone was out of reach. No one is waiting
    /// on the answer; the snapshot that follows is the answer.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let command = WatchCommand(message: userInfo) else { return }
        Task { @MainActor in _ = await self.handle(command) }
    }
}

/// The snapshot, from its inputs. Pure, so the access rules are tested.
enum WatchSnapshotBuilder {
    static func build(
        health: TodayHealth?,
        recent: [SiteAlert],
        latest: [TodayAlerts.Latest],
        cleared: Set<String>,
        unread: Int,
        access: AppAccess,
        ownerSite: Bool,
        sync: WatchSnapshot.Sync,
        connectionNeedsFixing: Bool,
        pinned: [WatchSnapshot.PinnedFlow],
        now: Date
    ) -> WatchSnapshot {
        // The inbox and the workflows are the owner's, on the Watch as on the
        // phone: a family member's wrist never carries them.
        let alerts = ownerSite
            ? TodayAlerts.rows(recent: recent, latest: latest, cleared: cleared).map {
                WatchSnapshot.Alert(id: $0.id, title: $0.title, severity: $0.severity, createdAt: $0.createdAt)
            }
            : []

        return WatchSnapshot(
            generatedAt: now,
            readiness: readiness(health),
            recovery: recovery(health),
            figures: figures(health),
            healthUpdatedAt: health?.generatedAt,
            alerts: alerts,
            unread: ownerSite ? unread : 0,
            showsAlerts: ownerSite,
            sync: sync,
            connectionNeedsFixing: ownerSite && connectionNeedsFixing,
            pinnedFlows: ownerSite ? Array(pinned.prefix(PinnedFlows.limit)) : [],
            canAsk: AccessPolicy.allows(.chat, access)
        )
    }

    static func readiness(_ health: TodayHealth?) -> WatchSnapshot.Figure? {
        guard let readiness = health?.readiness else { return nil }
        return WatchSnapshot.Figure(key: "readiness", label: readiness.label,
                                    display: "\(Int(readiness.score.rounded()))", unit: nil,
                                    fraction: readiness.score / 100)
    }

    /// The same order of sources Today's ring uses (`TodayVital.recoveryVital`).
    static func recovery(_ health: TodayHealth?) -> WatchSnapshot.Figure? {
        if let figure = health?.figures.first(where: { $0.key == "recovery" }), figure.measured {
            return WatchSnapshot.Figure(key: "recovery", label: "Recovery", display: figure.display,
                                        unit: "%", fraction: figure.value / 100)
        }
        if let factor = health?.readiness?.factors.first(where: { $0.key == "recovery" }) {
            return WatchSnapshot.Figure(key: "recovery", label: "Recovery",
                                        display: "\(Int(factor.score.rounded()))", unit: "%",
                                        fraction: factor.score / 100)
        }
        return nil
    }

    static let figureKeys = ["hrv", "rhr", "sleep"]

    static func figures(_ health: TodayHealth?) -> [WatchSnapshot.Figure] {
        figureKeys.compactMap { key in
            guard let figure = health?.figures.first(where: { $0.key == key }) else { return nil }
            let value = figure.inkValue
            return WatchSnapshot.Figure(key: key, label: figure.label, display: value.value,
                                        unit: value.unit, fraction: nil)
        }
    }

    static func sameContent(_ a: WatchSnapshot, _ b: WatchSnapshot) -> Bool {
        var a = a, b = b
        a = a.with(generatedAt: .distantPast)
        b = b.with(generatedAt: .distantPast)
        return a == b
    }
}

private extension WatchSnapshot {
    func with(generatedAt: Date) -> WatchSnapshot {
        WatchSnapshot(version: version, generatedAt: generatedAt, readiness: readiness, recovery: recovery,
                      figures: figures, healthUpdatedAt: healthUpdatedAt, alerts: alerts, unread: unread,
                      showsAlerts: showsAlerts, sync: sync, connectionNeedsFixing: connectionNeedsFixing,
                      pinnedFlows: pinnedFlows, canAsk: canAsk)
    }
}
