import SwiftUI
import UIKit
import BackgroundTasks
import os

private let syncLog = Logger(subsystem: "com.strangeramblings.com.appleapp", category: "sync")
private let reviewPrompt = "Apple Health has new categories. Tap Review Apple Health permissions to allow them."

/// Network failures a retry can plausibly fix on its own — worth a calm
/// "paused, will resume" message rather than the raw `URLError` text (which
/// is what a long backfill outrunning `beginBackgroundTask` and getting
/// suspended mid-request looks like: "The request timed out.").
func isTransientUploadFailure(_ error: Error) -> Bool {
    guard let code = (error as? URLError)?.code else { return false }
    let transient: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost, .notConnectedToInternet, .cancelled,
        .cannotConnectToHost, .dnsLookupFailed, .backgroundSessionWasDisconnected,
        .internationalRoamingOff, .dataNotAllowed,
    ]
    return transient.contains(code)
}
/// A flush that got at least one batch through is worth retrying soon — the
/// backfill it interrupted is still moving. One that accepted nothing waits
/// the old 60 s, so a systemic failure does not hammer the server.
func retryDelay(madeProgress: Bool) -> TimeInterval { madeProgress ? 5 : 60 }

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
            if !enabled { health.forgetFailures(for: kinds) }
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
        // A stale error must not sit on screen for the minutes a backfill can
        // take: show the queue's size now, and count it down as it drains.
        if queueCount > 0 { message = "Uploading \(queueCount) record\(queueCount == 1 ? "" : "s")…" }
        var dropped = 0
        var madeProgress = false
        var lastPersist = Date()
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "Sync SR records") { UIApplication.shared.endBackgroundTask(taskID); taskID = .invalid }
        defer {
            // Whatever a deferred removal left unwritten must not outlive the
            // flush that made it.
            try? outbox.persistIfDirty()
            if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
        }
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
            var round = UploadRound()
            while let batch = round.next(in: outbox.state.batches) {
                try Task.checkCancellation()
                if batch.health.isEmpty && batch.locations.isEmpty && batch.deleted.isEmpty {
                    try outbox.change { $0.batches.removeAll { $0.id == batch.id } }; continue
                }
                do {
                    let _: API.Acknowledgement = try await api.request("sync", method: "POST", data: JSONEncoder().encode(batch), timeout: 60)
                } catch CompanionError.response(let status, let reason) where HealthBatching.isRefusal(status: status) {
                    // Refused (400/413). Judge the batch as it stands now (the
                    // collector may have replaced records in it meanwhile).
                    guard let current = outbox.state.batches.first(where: { $0.id == batch.id }) else { continue }
                    switch round.refused(current, reason: reason) {
                    case .split:
                        try outbox.change { state in
                            guard let index = state.batches.firstIndex(where: { $0.id == batch.id }) else { return }
                            state.batches.replaceSubrange(index...index, with: HealthBatching.split(state.batches[index]))
                        }
                    case .drop:
                        dropped += try drop([batch.id], status: status, reason: reason)
                    case .hold:
                        break
                    case .stop:
                        // Possibly systemic (catalogue ahead of the server, clock
                        // ahead, truncated body): keep everything, retry later.
                        throw CompanionError.response(status, reason)
                    }
                    continue
                }
                // Deferred: the server upserts by id, so a crash before the
                // next write just re-sends an already-accepted batch, which is
                // harmless — unlike deferring an append, which could lose a
                // record that exists nowhere else.
                try outbox.change(persist: false) { $0.batches.removeAll { $0.id == batch.id }; $0.lastUpload = Date() }
                madeProgress = true
                updateQueue()
                if queueCount > 0 { message = "Uploading \(queueCount) record\(queueCount == 1 ? "" : "s")…" }
                if Date().timeIntervalSince(lastPersist) >= 2 { try outbox.persistIfDirty(); lastPersist = Date() }
                let evidenced = round.accepted()
                if !evidenced.isEmpty { dropped += try drop(evidenced, status: 400, reason: "refused while others were accepted") }
            }
            // A held deletion (or a record no acceptance vouched against)
            // is still queued: retry it later, as for any failed upload.
            if outbox.state.batches.contains(where: { round.held.contains($0.id) }) {
                throw CompanionError.message("Some records were refused and will retry.")
            }
            message = health.needsPermissionReview ? reviewPrompt : withHealthNotes("Up to date with the server.", dropped: dropped)
            retryTask?.cancel(); retryTask = nil
        } catch {
            message = isTransientUploadFailure(error)
                ? withHealthNotes("Upload paused — \(queueCount) record\(queueCount == 1 ? "" : "s") left; it will resume automatically.", dropped: dropped)
                : withHealthNotes("Upload pending: \(error.localizedDescription)", dropped: dropped)
            retryTask?.cancel()
            let delay = retryDelay(madeProgress: madeProgress)
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await self?.flush()
            }
        }
    }
    /// Removes refused batches (each a lone record) and logs what went — kind
    /// and id, never values. Returns how many records that was.
    private func drop(_ ids: [UUID], status: Int, reason: String) throws -> Int {
        let gone = outbox.state.batches.filter { ids.contains($0.id) }
        try outbox.change { $0.batches.removeAll { ids.contains($0.id) } }
        for b in gone {
            for r in b.health { syncLog.error("Dropped a refused health record: kind \(r.kind, privacy: .public) id \(r.id, privacy: .public) status \(status) reason \(reason, privacy: .public)") }
            if !b.locations.isEmpty { syncLog.error("Dropped a refused location: status \(status) reason \(reason, privacy: .public)") }
        }
        return gone.reduce(0) { $0 + $1.health.count + $1.locations.count }
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
