import SwiftUI
import UIKit
import BackgroundTasks
import os

private let syncLog = Logger(subsystem: "com.strangeramblings.com.appleapp", category: "sync")
private let reviewPrompt = "Apple Health has new categories. Tap Review Apple Health permissions to allow them."

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
    /// An enabled Apple Health type the permission sheet has never shown, or
    /// an upgraded install not yet re-asked. See `refreshHealthReview()`.
    @Published private(set) var healthReviewNeeded = false
    private var sending = false
    private var retryTask: Task<Void, Never>?
    init(outbox: Outbox) {
        self.outbox = outbox; health = HealthCollector(outbox: outbox); location = LocationCollector(outbox: outbox)
        paired = api.token != nil
        health.onUpdate = { [weak self] in Task { await self?.flush() } }
        location.onUpdate = { [weak self] in Task { await self?.flush() } }
        updateQueue()
        if paired { health.startObservers(); location.start() }
        if paired && health.needsPermissionReview { message = reviewPrompt }
        Task { [weak self] in await self?.refreshHealthReview() }
    }
    /// HealthKit only says asynchronously whether a type was never asked for.
    func refreshHealthReview() async {
        await health.refreshAuthorizationStatus()
        healthReviewNeeded = health.needsPermissionReview
        if paired && healthReviewNeeded { message = reviewPrompt }
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
    /// Toggles a GROUP. Turning one off drops its kinds' anchors and hourly
    /// cursors (so re-enabling re-reads from historyStart) and purges their
    /// unsent records — the behaviour the per-kind toggle had. Turning one on
    /// asks HealthKit for its types, then reads them.
    func setHealth(_ group: String, enabled: Bool) {
        let kinds = Set(HealthCatalogue.kinds(inGroups: [group]))
        do {
            try outbox.change {
                var groups = Set($0.healthEnabled)
                groups.remove(group)
                if enabled { groups.insert(group) }
                $0.healthEnabled = HealthCatalogue.groupOrder.filter { groups.contains($0) }
                if !enabled {
                    // `hourlySent` too: the purge below unqueues those values, so
                    // a re-enable must send every bucket again, not skip them.
                    for kind in kinds { $0.anchors.removeValue(forKey: kind); $0.hourlyFrom.removeValue(forKey: kind); $0.hourlySent.removeValue(forKey: kind) }
                    if kinds.contains("workout") { $0.pendingRoutes.removeAll() }
                    for index in $0.batches.indices { $0.batches[index].health.removeAll { kinds.contains($0.kind) } }
                    $0.batches.removeAll { $0.health.isEmpty && $0.locations.isEmpty && $0.deleted.isEmpty }
                }
            }
            health.startObservers(); updateQueue()
        } catch { message = error.localizedDescription; return }
        // A group turned on later brings types the reader was never asked
        // for: ask now (the sheet shows only those), then read them.
        Task { [weak self] in
            guard let self else { return }
            if enabled && !self.busy { await self.authorizeHealth() } else { await self.refreshHealthReview() }
        }
    }
    func authorizeHealth() async {
        busy = true; defer { busy = false }
        do {
            try await health.authorize()
            await refreshHealthReview()
            try await health.collect(until: Date().addingTimeInterval(120)); await flush()
        } catch {
            message = error.localizedDescription
            await refreshHealthReview()
        }
    }
    func setSharing(_ enabled: Bool) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            // Pause locally immediately, including while offline. Retry server pause on next flush.
            try outbox.change { $0.sharing = enabled; $0.pendingSharing = enabled; if !enabled { for i in $0.batches.indices { $0.batches[i].locations = [] } } }
            if enabled { location.requestPermission(); location.start() } else { location.stop() }
            let _: API.Acknowledgement = try await api.request("sharing", method: "PUT", data: JSONEncoder().encode(["enabled": enabled]))
            try outbox.change { $0.pendingSharing = nil }
            message = enabled ? "Family location sharing enabled." : "Location sharing paused."
            try await refresh()
        } catch { message = "Saved on this phone. Server update pending: \(error.localizedDescription)" }
        updateQueue()
    }
    /// `collectingFor`: 120 s in the foreground; a background refresh passes
    /// 15 s so the upload and the notification pass still fit its budget.
    func sync(collectingFor seconds: TimeInterval = 120) async {
        guard paired, !busy else { return }
        busy = true; defer { busy = false }
        do { try await health.collect(until: Date().addingTimeInterval(seconds)); await flush(); try await refresh() }
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
        var dropped = 0
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "Sync SR records") { UIApplication.shared.endBackgroundTask(taskID); taskID = .invalid }
        defer { if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) } }
        do {
            // Apply a local offline choice before reconciling remote changes.
            if let pending = outbox.state.pendingSharing {
                let _: API.Acknowledgement = try await api.request("sharing", method: "PUT", data: JSONEncoder().encode(["enabled": pending]))
                try outbox.change { $0.pendingSharing = nil }
            }
            // Reconcile with server before uploads so a browser pause is respected.
            let me: Profile = try await api.request("me")
            if !me.sharing && outbox.state.sharing && outbox.state.pendingSharing == nil {
                try outbox.change { $0.sharing = false; for i in $0.batches.indices { $0.batches[i].locations = [] } }
                location.stop()
            }
            while let batch = outbox.state.batches.first {
                try Task.checkCancellation()
                if batch.health.isEmpty && batch.locations.isEmpty && batch.deleted.isEmpty {
                    try outbox.change { $0.batches.removeFirst() }; continue
                }
                do {
                    let _: API.Acknowledgement = try await api.request("sync", method: "POST", data: JSONEncoder().encode(batch))
                } catch CompanionError.response(let status, let reason) where HealthBatching.isRefusal(status: status) {
                    // Refused (400/413): resending can only fail again, and it
                    // holds every later upload behind it. Halve the batch as it
                    // stands now; a lone record still refused is dropped.
                    var lost: [HealthRecord] = [], lostOther = 0
                    try outbox.change { state in
                        guard let index = state.batches.firstIndex(where: { $0.id == batch.id }) else { return }
                        let halves = HealthBatching.split(state.batches[index])
                        if halves.isEmpty {
                            lost = state.batches[index].health
                            lostOther = state.batches[index].locations.count + state.batches[index].deleted.count
                        }
                        state.batches.replaceSubrange(index...index, with: halves)
                    }
                    for r in lost { syncLog.error("Dropped a refused health record: kind \(r.kind, privacy: .public) id \(r.id, privacy: .public) status \(status) reason \(reason, privacy: .public)") }
                    if lostOther > 0 { syncLog.error("Dropped a refused location or deletion: status \(status) reason \(reason, privacy: .public)") }
                    dropped += lost.count + lostOther
                    continue
                }
                try outbox.change { $0.batches.removeAll { $0.id == batch.id }; $0.lastUpload = Date() }
            }
            message = health.needsPermissionReview ? reviewPrompt : withHealthNotes("Up to date with the server.", dropped: dropped)
            retryTask?.cancel(); retryTask = nil
        } catch {
            message = withHealthNotes("Upload pending: \(error.localizedDescription)", dropped: dropped)
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await self?.flush()
            }
        }
    }
    /// `base`, then anything the user should know that did not stop the
    /// upload: records the server refused, and Apple Health kinds that could
    /// not be read (including a full offline queue).
    private func withHealthNotes(_ base: String, dropped: Int) -> String {
        var parts = [base]
        if dropped > 0 { parts.append("Skipped \(dropped) record\(dropped == 1 ? "" : "s") the server refused.") }
        if let failed = HealthBatching.failureSummary(health.failures) { parts.append(failed) }
        return parts.joined(separator: " ")
    }
    func disconnect() async {
        guard !sending, !busy else { message = "Wait for the current sync before disconnecting."; return }
        // Require an acknowledged server pause/revocation before dropping credentials.
        do {
            try outbox.change { $0.sharing = false }; location.stop()
            do {
                let _: API.Acknowledgement = try await api.request("sharing", method: "PUT", data: JSONEncoder().encode(["enabled": false]))
                let _: API.Acknowledgement = try await api.request("logout", method: "POST", data: Data("{}".utf8))
            } catch CompanionError.response(401, _) {
                // Already revoked or expired: it is safe to remove the local credential.
            }
            try Keychain.save(nil); api.token = nil; paired = false
            try outbox.clear(); health.startObservers(); retryTask?.cancel()
            profile = nil; records = []; family = []; updateQueue(); message = "Disconnected. Uploaded health records remain in your private dashboard."
        } catch { message = "Disconnect pending: \(error.localizedDescription). You can revoke this device on the website." }
    }
    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.strangeramblings.com.appleapp.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
