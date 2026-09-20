import SwiftUI
import UIKit
import BackgroundTasks

@MainActor final class Companion: ObservableObject {
    let api = API()
    let outbox: Outbox
    let health: HealthCollector
    let location: LocationCollector
    @Published var profile: Profile?
    @Published var family: [FamilyMember] = []
    @Published var records: [HealthRecord] = []
    @Published var message = "Pair your iPhone to get started."
    @Published var busy = false
    @Published var paired: Bool
    @Published var queueCount = 0
    @Published var lastUpload: Date?
    private var sending = false
    private var retryTask: Task<Void, Never>?
    init(outbox: Outbox) {
        self.outbox = outbox; health = HealthCollector(outbox: outbox); location = LocationCollector(outbox: outbox)
        paired = api.token != nil
        health.onUpdate = { [weak self] in Task { await self?.flush() } }
        location.onUpdate = { [weak self] in Task { await self?.flush() } }
        updateQueue()
        if paired { health.startObservers(); location.start() }
    }
    func updateQueue() { queueCount = outbox.state.batches.reduce(0) { $0 + $1.health.count + $1.locations.count + $1.deleted.count }; lastUpload = outbox.state.lastUpload }
    func pair(server: String, code: String) async {
        busy = true; defer { busy = false }
        do {
            guard !paired else { throw CompanionError.message("Disconnect this device before pairing another account.") }
            try outbox.clear()
            try await api.pair(server: server, code: code)
            paired = true
            message = "Connected. Choose health categories and location sharing below."
            try await refresh()
        } catch { message = error.localizedDescription }
    }
    func setHealth(_ kind: String, enabled: Bool) {
        do {
            try outbox.change {
                $0.healthEnabled.removeAll { $0 == kind }
                if enabled { $0.healthEnabled.append(kind) }
                else {
                    // Remove unsent records and restart this category's anchor if re-enabled.
                    $0.anchors.removeValue(forKey: kind)
                    for index in $0.batches.indices { $0.batches[index].health.removeAll { $0.kind == kind } }
                    $0.batches.removeAll { $0.health.isEmpty && $0.locations.isEmpty && $0.deleted.isEmpty }
                }
            }
            health.startObservers(); updateQueue()
        } catch { message = error.localizedDescription }
    }
    func authorizeHealth() async {
        busy = true; defer { busy = false }
        do { try await health.authorize(); try await health.collect(); await flush(); message = "Permission request finished. Only readable, selected records can sync." }
        catch { message = error.localizedDescription }
    }
    func setSharing(_ enabled: Bool) async {
        do {
            // Pause locally immediately, including while offline. Retry server pause on next flush.
            try outbox.change { $0.sharing = enabled; if !enabled { for i in $0.batches.indices { $0.batches[i].locations = [] } } }
            if enabled { location.requestPermission(); location.start() } else { location.stop() }
            let _: API.Acknowledgement = try await api.request("sharing", method: "PUT", data: JSONEncoder().encode(["enabled": enabled]))
            message = enabled ? "Family location sharing enabled." : "Location sharing paused."
            try await refresh()
        } catch { message = "Saved on this phone. Server update pending: \(error.localizedDescription)" }
        updateQueue()
    }
    func sync() async {
        guard paired, !busy else { return }
        busy = true; defer { busy = false }
        do { try await health.collect(); await flush(); try await refresh() }
        catch { message = error.localizedDescription }
    }
    func refresh() async throws {
        profile = try await api.request("me")
        let f: FamilyResponse = try await api.request("family"); family = f.members
        let h: HealthResponse = try await api.request("health"); records = h.records
    }
    func flush() async {
        updateQueue()
        guard paired, !sending else { return }
        sending = true; defer { sending = false; updateQueue() }
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "Sync SR records") { UIApplication.shared.endBackgroundTask(taskID); taskID = .invalid }
        defer { if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) } }
        do {
            // Reconcile with server before uploads so a browser pause is respected.
            let me: Profile = try await api.request("me")
            if !me.sharing && outbox.state.sharing {
                try outbox.change { $0.sharing = false; for i in $0.batches.indices { $0.batches[i].locations = [] } }
                location.stop()
            } else if me.sharing && !outbox.state.sharing {
                let _: API.Acknowledgement = try await api.request("sharing", method: "PUT", data: JSONEncoder().encode(["enabled": false]))
            }
            while let batch = outbox.state.batches.first {
                if batch.health.isEmpty && batch.locations.isEmpty && batch.deleted.isEmpty {
                    try outbox.change { $0.batches.removeFirst() }; continue
                }
                let _: API.Acknowledgement = try await api.request("sync", method: "POST", data: JSONEncoder().encode(batch))
                try outbox.change { $0.batches.removeAll { $0.id == batch.id }; $0.lastUpload = Date() }
            }
            message = "Up to date with the server."
            retryTask?.cancel(); retryTask = nil
        } catch {
            message = "Upload pending: \(error.localizedDescription)"
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await self?.flush()
            }
        }
    }
    func disconnect() async {
        guard !sending, !busy else { message = "Wait for the current sync before disconnecting."; return }
        // Require an acknowledged server pause/revocation before dropping credentials.
        do {
            try outbox.change { $0.sharing = false }; location.stop()
            let _: API.Acknowledgement = try await api.request("sharing", method: "PUT", data: JSONEncoder().encode(["enabled": false]))
            let _: API.Acknowledgement = try await api.request("logout", method: "POST", data: Data("{}".utf8))
            try Keychain.save(nil); api.token = nil; paired = false
            try outbox.clear(); health.startObservers(); retryTask?.cancel()
            profile = nil; records = []; family = []; updateQueue(); message = "Disconnected. Uploaded health records remain in your private dashboard."
        } catch { message = "Disconnect pending: \(error.localizedDescription). You can revoke this device on the website." }
    }
    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.strangeramblings.appleapp.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
