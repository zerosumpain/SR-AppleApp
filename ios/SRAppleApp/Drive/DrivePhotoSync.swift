import BackgroundTasks
import Combine
import Network
import Photos
import UIKit

/// Photo sync: keep this phone's photos and videos in Drive, by itself.
///
/// Each pass compares the library with the move ledger (what Drive has
/// proven it holds), then fills a small window of uploads with the newest
/// photos not yet there. Before a photo goes, Drive is asked whether it
/// already has those bytes (`api/native/drive/have`, by sha256 and size) —
/// a photo sent another way, or before this phone kept a ledger, is written
/// down without sending it again. What is sent goes through
/// `DriveUploadQueue`, so it carries on with the app shut, and lands in My
/// files › Incoming photos or Incoming movies (the site decides).
///
/// When it runs: on opening the app, when the library changes while it is
/// open, as each upload finishes, and in a background processing window the
/// system grants (most often overnight, on charge). iOS lets no app watch the
/// library while shut, so a photo taken with the app closed goes at the next
/// of those. Nothing is ever removed from the phone here: that stays "Remove
/// from phone", which the system confirms.
@MainActor
final class DrivePhotoSync: NSObject, ObservableObject {
    static let shared = DrivePhotoSync()
    static let taskIdentifier = "com.strangeramblings.com.appleapp.drive-sync"

    @Published var settings = DriveSyncSettings.load() {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.on { begin() }
            kick()
        }
    }

    @Published private(set) var counts = DriveSyncCounts()
    @Published private(set) var pause: DriveSyncPause = .off
    /// What a pass is doing now ("Checking 3 of 8…"), or nil.
    @Published private(set) var working: String?
    /// Drive's pictures it has not fingerprinted yet, as last told.
    @Published private(set) var unchecked = 0
    @Published private(set) var lastChecked: Date?
    /// Photos sync will not send again, with Drive's reason.
    @Published private(set) var skipped: [String: String] = [:]
    /// The newest photos not yet in Drive, for the screen to show.
    @Published private(set) var waiting: [String] = []
    @Published private(set) var access: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    private var running = false
    private var again = false
    private var begun = false
    private var observing = false
    private var expensive = false
    private var constrained = false
    private var lastRetry = Date.distantPast
    /// Put off for this run of the app: an export that failed (iCloud out of
    /// reach), or a big film Drive has not fingerprinted yet.
    private var later = Set<String>()
    private var bag = Set<AnyCancellable>()
    private let path = NWPathMonitor()

    private override init() {
        super.init()
        skipped = Self.readSkipped()
    }

    // MARK: - Starting

    /// At launch. Does nothing much until sync is on.
    func start() {
        guard !SRDemo.isOn else { return }
        if settings.on { begin() }
    }

    private func begin() {
        guard !begun else { return }
        begun = true
        path.pathUpdateHandler = { update in
            let expensive = update.isExpensive || update.usesInterfaceType(.cellular)
            let constrained = update.isConstrained
            Task { @MainActor in
                let sync = DrivePhotoSync.shared
                let changed = sync.expensive != expensive || sync.constrained != constrained
                sync.expensive = expensive
                sync.constrained = constrained
                if changed { sync.kick() }
            }
        }
        path.start(queue: DispatchQueue(label: "drive-sync-path"))
        // Each upload that finishes makes room: fill it.
        DriveUploadQueue.shared.$jobs
            .map { DriveSync.inFlight($0).count }
            .removeDuplicates()
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { _ in Task { @MainActor in DrivePhotoSync.shared.kick() } }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { _ in Task { @MainActor in DrivePhotoSync.shared.kick() } }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { _ in Task { @MainActor in DrivePhotoSync.shared.scheduleBackground() } }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)
            .sink { _ in Task { @MainActor in DrivePhotoSync.shared.kick() } }
            .store(in: &bag)
        observeLibrary()
    }

    private func observeLibrary() {
        guard !observing, Self.canRead(access) else { return }
        observing = true
        PHPhotoLibrary.shared().register(self)
    }

    /// Full or limited access: sync reads the library either way (limited
    /// sees only the photos chosen for SR).
    nonisolated static func canRead(_ status: PHAuthorizationStatus) -> Bool {
        status == .authorized || status == .limited
    }

    func askForAccess() async {
        access = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        observeLibrary()
        kick()
    }

    // MARK: - A pass

    func kick() {
        Task { await pass() }
    }

    /// Compare, then send what is missing until the window is full (or
    /// `deadline`, in a background window). One at a time: a pass asked for
    /// while one runs goes straight after it.
    func pass(deadline: Date? = nil) async {
        if running {
            again = true
            return
        }
        running = true
        defer {
            running = false
            working = nil
            if again {
                again = false
                kick()
            }
        }
        access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        pause = DriveSyncPause.of(
            on: settings.on, demo: SRDemo.isOn, paired: SiteClient.shared.isPaired,
            viewingAs: AccessStore.shared.viewingAs != nil, access: Self.canRead(access),
            wifiOnly: settings.wifiOnly, expensive: expensive, constrained: constrained,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        guard settings.on, Self.canRead(access) else { return }
        noteRefusals()
        var library = fetchLibrary()
        refresh(library)
        guard pause == .none else { return }
        retryGivenUp()

        while true {
            if let deadline, Date() >= deadline { break }
            let queue = DriveUploadQueue.shared
            let known = queue.ledger.assetIds.union(DriveSync.queued(queue.jobs)).union(skipped.keys)
            let ids = DriveSync.next(library: library.ids, known: known, later: later,
                                     limit: min(DriveSync.room(queue.jobs), DriveSync.haveBatch))
            guard !ids.isEmpty else { break }
            let asked = await send(ids, from: library)
            refresh(library)
            // Drive could not be asked (no signal, an older site): try again later, not photo by photo.
            guard asked else { break }
            // Paused meanwhile (Wi-Fi gone, switched off): stop feeding.
            guard settings.on, currentPause() == .none else { break }
            library = fetchLibrary()
        }
        lastChecked = Date()
        refresh(library)
        if counts.notYet > 0 || counts.sending > 0 { scheduleBackground() }
    }

    private func currentPause() -> DriveSyncPause {
        DriveSyncPause.of(
            on: settings.on, demo: SRDemo.isOn, paired: SiteClient.shared.isPaired,
            viewingAs: AccessStore.shared.viewingAs != nil, access: Self.canRead(access),
            wifiOnly: settings.wifiOnly, expensive: expensive, constrained: constrained,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    /// Export, hash, ask Drive, then queue only what it lacks. False when
    /// Drive could not be asked, so the pass stops instead of exporting the
    /// whole library one unanswered batch at a time.
    private func send(_ ids: [String], from library: Library) async -> Bool {
        struct Ready {
            let asset: PHAsset
            let url: URL
            let size: Int
            let sha: String
        }
        var ready: [Ready] = []
        for (i, id) in ids.enumerated() {
            guard let asset = library.assets[id] else { continue }
            working = "Getting \(i + 1) of \(ids.count) ready…"
            guard let url = await DrivePhotoImport.export(asset) else {
                later.insert(id) // iCloud out of reach, most often: next time the app opens
                continue
            }
            let hashed = await Task.detached(priority: .utility) { () -> (Int, String)? in
                guard let size = DriveFileIO.size(of: url), let sha = try? DriveFileIO.sha256(of: url) else { return nil }
                return (size, sha)
            }.value
            guard let hashed else {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                later.insert(id)
                continue
            }
            ready.append(Ready(asset: asset, url: url, size: hashed.0, sha: hashed.1))
        }
        guard !ready.isEmpty else { return true }

        working = "Checking Drive…"
        guard let reply = await have(ready.map { DriveHaveRequest.Item(sha256: $0.sha, size: $0.size) }) else {
            for item in ready { try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent()) }
            return false
        }
        unchecked = reply.unchecked ?? 0
        var found: [(assetId: String, fileId: String, space: DriveSpace)] = []
        for (i, item) in ready.enumerated() {
            let id = item.asset.localIdentifier
            if let file = reply.file(sha256: item.sha, size: item.size) {
                found.append((assetId: id, fileId: file.id, space: DriveSpace.mine))
                try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent())
                continue
            }
            // A big film Drive may not have fingerprinted yet: wait for its sweep
            // rather than send gigabytes it might already hold.
            if (reply.unchecked ?? 0) > 0, item.size > DriveSync.bigFile {
                later.insert(id)
                try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent())
                continue
            }
            working = "Adding \(i + 1) of \(ready.count)…"
            let created = item.asset.creationDate
            let keep = UserDefaults.standard.object(forKey: DrivePhotoImport.keepOriginalsKey) as? Bool ?? true
            let media = await Task.detached(priority: .utility) {
                DrivePhotoImport.describe(item.url, keepOriginals: keep, fallbackDate: created)
            }.value
            let takenAt = created.map { DriveLogic.localISO($0) } ?? media.takenAt
            do {
                // The top of My files: the site files it under Incoming photos or movies.
                _ = try await DriveUploadQueue.shared.enqueue(
                    media.url, consume: true, space: .mine, folder: "", filename: media.filename,
                    mimeType: media.mimeType, takenAt: takenAt, assetId: id
                )
                try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent())
            } catch let refusal as DriveUploadQueue.Refusal {
                if case .tooLarge(let why) = refusal { skip(id, why) } else { later.insert(id) }
                try? FileManager.default.removeItem(at: media.url.deletingLastPathComponent())
            } catch {
                later.insert(id)
                try? FileManager.default.removeItem(at: media.url.deletingLastPathComponent())
            }
        }
        if !found.isEmpty { DriveUploadQueue.shared.recordKnown(found) }
        return true
    }

    /// Drive's answer, or nil when it could not be asked (no signal, an
    /// older site): then nothing is sent this pass, so a re-send never costs
    /// a copy's worth of data on a guess.
    private func have(_ items: [DriveHaveRequest.Item]) async -> DriveHaveReply? {
        guard let body = try? JSONEncoder().encode(DriveHaveRequest(items: items)) else { return nil }
        return try? await SiteClient.shared.send("api/native/drive/have?space=mine", method: "POST", body: body, asSelf: true, timeout: 25)
    }

    // MARK: - What is where

    struct Library {
        /// Newest first: a new photo goes before last year's.
        var ids: [String] = []
        var assets: [String: PHAsset] = [:]
    }

    private func fetchLibrary() -> Library {
        let options = PHFetchOptions()
        // The phone's own library: not shared albums, not iTunes-synced copies.
        options.includeAssetSourceTypes = [.typeUserLibrary]
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var kinds = [NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)]
        if settings.videos { kinds.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)) }
        var parts: [NSPredicate] = [NSCompoundPredicate(orPredicateWithSubpredicates: kinds)]
        if let since = settings.since {
            parts.append(NSPredicate(format: "creationDate >= %@", Calendar.current.startOfDay(for: since) as NSDate))
        }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: parts)
        let result = PHAsset.fetchAssets(with: options)
        var library = Library()
        library.ids.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            library.ids.append(asset.localIdentifier)
            library.assets[asset.localIdentifier] = asset
        }
        return library
    }

    private func refresh(_ library: Library) {
        let queue = DriveUploadQueue.shared
        let inDrive = queue.ledger.assetIds
        let sending = DriveSync.queued(queue.jobs)
        counts = DriveSync.counts(library: library.ids, inDrive: inDrive, sending: sending, skipped: Set(skipped.keys))
        waiting = DriveSync.next(library: library.ids, known: inDrive.union(sending).union(skipped.keys), later: [], limit: 60)
    }

    // MARK: - Trouble

    /// Refusals in the queue become skips, kept across launches.
    private func noteRefusals() {
        let refused = DriveSync.refusals(DriveUploadQueue.shared.jobs)
        guard !refused.isEmpty else { return }
        var next = skipped
        for (id, why) in refused { next[id] = why }
        guard next != skipped else { return }
        skipped = next
        Self.writeSkipped(skipped)
    }

    private func skip(_ id: String, _ why: String) {
        skipped[id] = why
        Self.writeSkipped(skipped)
    }

    /// Give every skipped photo another go (from the screen).
    func retrySkipped() {
        skipped = [:]
        later = []
        Self.writeSkipped(skipped)
        DriveUploadQueue.shared.retryFailed()
        kick()
    }

    /// A failure that has used its three goes waits for Try again; sync
    /// presses it itself, now and then.
    private func retryGivenUp() {
        let givenUp = DriveUploadQueue.shared.jobs.contains { job in
            guard job.assetId != nil, case .failed = job.state else { return false }
            return !job.retriesItself
        }
        guard givenUp, Date().timeIntervalSince(lastRetry) > DriveSync.retryEvery else { return }
        lastRetry = Date()
        DriveUploadQueue.shared.retryFailed()
    }

    nonisolated private static var skippedFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DriveSync", isDirectory: true)
            .appendingPathComponent("skipped.json")
    }

    nonisolated private static func readSkipped() -> [String: String] {
        guard let data = try? Data(contentsOf: skippedFile),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    nonisolated private static func writeSkipped(_ map: [String: String]) {
        let file = skippedFile
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: - Background

    /// Ask for a processing window while there is anything to send.
    func scheduleBackground() {
        guard settings.on else { return }
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The window the system granted: keep the line fed until it ends. The
    /// background session sends; this only has to hand it the next files.
    func runInBackground(_ task: BGTask) {
        let work = Task { @MainActor in
            let until = Date().addingTimeInterval(25 * 60)
            while !Task.isCancelled, Date() < until {
                await pass(deadline: until)
                if counts.notYet == 0 || pause != .none { break }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
            scheduleBackground()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    /// Signed out: nothing of the person before is kept.
    func clear() {
        settings = DriveSyncSettings()
        skipped = [:]
        later = []
        counts = DriveSyncCounts()
        waiting = []
        Self.writeSkipped([:])
    }
}

extension DrivePhotoSync: PHPhotoLibraryChangeObserver {
    /// A photo taken, or one deleted, while the app is open: compare again shortly.
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            let sync = DrivePhotoSync.shared
            guard sync.settings.on else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            sync.kick()
        }
    }
}
