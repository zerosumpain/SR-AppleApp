import Foundation
import Network

/// Offline results waiting for the internet, and the sync that sends them.
///
/// Every finished match this phone played — alone or nearby — is queued here
/// (`OfflineResultQueue`), saved to a file at once, and sent to
/// `POST api/native/games/offline-results` when the phone is paired with the
/// site and online: at once if it can, when the network comes back, when the
/// app comes to the front (`ContentView` calls `syncSoon()`), and on a
/// backoff after a failure. The queue keeps
/// what the site has not answered for, so nothing is lost to a dropped
/// connection or a site that cannot take them yet.
@MainActor
final class OfflineResultStore: ObservableObject {
    static let shared = OfflineResultStore()

    /// The site's half of sync later.
    static let path = "api/native/games/offline-results"

    enum SyncState: Equatable {
        /// Nothing waiting, or waiting for the next try.
        case idle
        case syncing
        /// No internet: results wait for it.
        case offline
        /// This phone is not connected to Strange Ramblings.
        case unpaired
        /// The site answered but cannot take offline results yet.
        case notReady
        /// Something else went wrong; the sentence says what.
        case failed(String)
    }

    @Published private(set) var queue: OfflineResultQueue
    @Published private(set) var state: SyncState = .idle
    @Published private(set) var lastSynced: Date?

    private let monitor = NWPathMonitor()
    private var online = true
    private var syncing = false
    private var nextAttempt = Date.distantPast
    private var retry: Task<Void, Never>?

    private init() {
        queue = Self.load() ?? OfflineResultQueue()
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in OfflineResultStore.shared.networkChanged(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "offline-results.path"))
    }

    // MARK: - What screens read

    var pendingCount: Int { queue.pending.count }

    /// One line for the Play nearby page, or nil when nothing is waiting.
    var statusLine: String? {
        guard let waiting = queue.waitingLine else { return nil }
        switch state {
        case .idle: return "\(waiting) — sending when there is internet."
        case .syncing: return "\(waiting) — sending now…"
        case .offline: return "\(waiting) — no internet yet."
        case .unpaired: return "\(waiting) — connect this iPhone to Strange Ramblings to add them to the leaderboard."
        case .notReady: return "\(waiting) — the site cannot take offline results yet; they are kept here until it can."
        case .failed(let why): return "\(waiting) — the last try failed (\(why)). Trying again soon."
        }
    }

    /// Games by how much they are played offline here, most first.
    func mostPlayed(limit: Int = 6) -> [String] {
        queue.mostPlayed(now: Date().timeIntervalSince1970 * 1000, limit: limit)
    }

    // MARK: - Recording and syncing

    /// Queue a finished match and try to send it.
    func record(_ result: OfflineResult) {
        guard queue.add(result) else { return }
        save()
        syncSoon()
    }

    /// Try to send what is waiting, unless a backoff says not yet.
    func syncSoon(force: Bool = false) {
        if force { nextAttempt = .distantPast }
        Task { await sync() }
    }

    private func networkChanged(online: Bool) {
        let cameBack = online && !self.online
        self.online = online
        if !online, !queue.pending.isEmpty { state = .offline }
        if cameBack { syncSoon(force: true) }
    }

    private func sync() async {
        guard !syncing else { return }
        guard !queue.pending.isEmpty else {
            state = .idle
            return
        }
        // A demo never talks to the site about games it did not play.
        guard !SRDemo.isOn else { return }
        guard SiteClient.shared.isPaired else {
            state = .unpaired
            return
        }
        guard online else {
            state = .offline
            return
        }
        guard Date() >= nextAttempt else { return }
        syncing = true
        state = .syncing
        defer { syncing = false }
        // Batch after batch while the site keeps taking them.
        while !queue.pending.isEmpty {
            let batch = queue.batch()
            do {
                let body = try JSONEncoder().encode(OfflineResultUpload(results: batch))
                let data = try await SiteClient.shared.post(Self.path, body: body)
                let receipt = (try? JSONDecoder().decode(OfflineResultReceipt.self, from: data)) ?? OfflineResultReceipt(recorded: [])
                queue.settle(receipt.settled)
                save()
                lastSynced = Date()
                state = .idle
                // A site that answered without settling anything would loop.
                if receipt.settled.isEmpty { break }
            } catch {
                failed(error)
                return
            }
        }
    }

    private func failed(_ error: Error) {
        queue.failed()
        save()
        let wait = OfflineResultQueue.backoff(failures: queue.failures)
        nextAttempt = Date().addingTimeInterval(wait)
        if let site = error as? SiteError {
            switch site.status {
            case 401?: state = .unpaired
            // No such route yet (an older site), or not allowed to post here.
            case 404?, 405?: state = .notReady
            default: state = .failed(site.localizedDescription)
            }
        } else if error is URLError {
            state = .offline
        } else {
            state = .failed(error.localizedDescription)
        }
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(1, wait) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    // MARK: - The file

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("offline-results.json")
    }

    private static func load() -> OfflineResultQueue? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OfflineResultQueue.self, from: data)
    }

    private func save() {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(queue) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
