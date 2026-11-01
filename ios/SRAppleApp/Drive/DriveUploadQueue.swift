import BackgroundTasks
import CryptoKit
import Foundation

/// Uploads to Drive that carry on when the app is shut.
///
/// Each file is copied into Application Support (`DriveUploads/`), hashed,
/// and handed to a BACKGROUND `URLSession` as a file upload — so a hundred
/// photos never sit in memory, and the system keeps sending them after the
/// app is swiped away. The request is the one the app always made (`POST
/// api/native/drive/files`, raw body, fields in the query) plus `sha256`
/// and `takenAt`. The token is read as each file is queued
/// (`SiteClient.request`).
///
/// The queue is a JSON file beside the staged copies, so what the system
/// finished while the app was shut is matched up when it next opens
/// (`application(_:handleEventsForBackgroundURLSession:)` in `AppDelegate`),
/// and the `drive-upload` background task picks up whatever was left
/// waiting. The rules about what an answer means live in
/// `DriveUploadJobs.swift`, as tests.
@MainActor
final class DriveUploadQueue: ObservableObject {
    static let shared = DriveUploadQueue()
    /// The background session's identity, and the processing task's.
    static let sessionIdentifier = "com.strangeramblings.com.appleapp.drive-upload"
    static let taskIdentifier = "com.strangeramblings.com.appleapp.drive-upload"

    @Published private(set) var jobs: [DriveUploadJob] = []
    @Published private(set) var ledger = DriveMoveLedger()
    /// The folder a file last landed in, and a count that moves each time,
    /// so a Drive screen showing it reloads.
    @Published private(set) var landed = DriveLanding(count: 0, ref: DriveRef())

    /// Handed over by `AppDelegate` when the system woke the app for this
    /// session; called once every event is in.
    var backgroundCompletion: (() -> Void)?

    private let delegate = DriveUploadDelegate()
    private var started = false

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config, delegate: self.delegate, delegateQueue: nil)
    }()

    private init() {
        jobs = Self.read([DriveUploadJob].self, Self.jobsFile) ?? []
        ledger = Self.read(DriveMoveLedger.self, Self.ledgerFile) ?? DriveMoveLedger()
        // Yesterday's finished files are history, not news.
        let dayAgo = Date().addingTimeInterval(-86_400)
        jobs.removeAll { $0.isFinished && $0.createdAt < dayAgo }
    }

    /// At launch: reconnect to the system's session (so its finished events
    /// arrive) and send whatever was left waiting.
    func start() {
        guard !SRDemo.isOn else { return }
        started = true
        _ = session
        reconcile()
    }

    // MARK: - Adding

    enum Refusal: Error, LocalizedError {
        case tooLarge(String)
        case unreadable(String)
        case notNow(String)

        var errorDescription: String? {
            switch self {
            case .tooLarge(let text), .unreadable(let text), .notNow(let text): return text
            }
        }
    }

    /// Queue one file. `source` is copied (or, with `consume`, moved — a temp
    /// file the caller made) into the queue's folder first, so the caller's
    /// copy can go at once. Nil when the same bytes are already queued for
    /// the same folder.
    @discardableResult
    func enqueue(_ source: URL, consume: Bool, space: DriveSpace, folder: String, filename: String,
                 mimeType: String, takenAt: String? = nil, assetId: String? = nil, limit: Int) async throws -> DriveUploadJob? {
        guard !SRDemo.isOn else { throw Refusal.notNow("Drive is switched off in the demo.") }
        guard AccessStore.shared.viewingAs == nil else { throw Refusal.notNow("View as is look-only.") }
        guard SiteClient.shared.isPaired else { throw Refusal.notNow(SiteError.unpaired.errorDescription ?? "") }
        if !started { start() }
        let id = UUID().uuidString
        let ext = (filename as NSString).pathExtension
        let staged = ext.isEmpty ? id : "\(id).\(ext)"
        let target = Self.folder.appendingPathComponent(staged)
        let prepared: (size: Int, sha: String)
        do {
            prepared = try await Task.detached(priority: .utility) {
                try Self.stage(source, to: target, consume: consume)
            }.value
        } catch {
            throw Refusal.unreadable("\(filename) could not be read.")
        }
        if let refusal = DriveLogic.tooLarge(prepared.size, limit: limit) {
            try? FileManager.default.removeItem(at: target)
            throw Refusal.tooLarge("\(filename): \(refusal)")
        }
        let job = DriveUploadJob(
            id: id, space: space, folder: folder, filename: filename, mimeType: mimeType,
            sizeBytes: prepared.size, sha256: prepared.sha, takenAt: takenAt, staged: staged,
            assetId: assetId, createdAt: Date()
        )
        // The same bytes, already on their way (or there) into the same place.
        if jobs.contains(where: { $0.dedupeKey == job.dedupeKey && ($0.isActive || $0.isSafelyStored) }) {
            try? FileManager.default.removeItem(at: target)
            return nil
        }
        jobs.append(job)
        submit(job.id)
        persist()
        return job
    }

    // MARK: - Sending

    private func submit(_ id: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let job = jobs[index]
        var fields = [
            "space": job.space.rawValue, "filename": job.filename, "type": job.mimeType, "sha256": job.sha256,
        ]
        if !job.folder.isEmpty { fields["folder"] = job.folder }
        if let takenAt = job.takenAt { fields["takenAt"] = takenAt }
        let query = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\(DriveLogic.escape($0.value))" }
            .joined(separator: "&")
        let file = Self.folder.appendingPathComponent(job.staged)
        guard FileManager.default.fileExists(atPath: file.path) else {
            jobs[index].state = .refused("The copy waiting to go up has gone. Add it again.")
            return
        }
        do {
            // No body on the request: the system streams it from the file.
            var request = try SiteClient.shared.request("api/native/drive/files?\(query)", method: "POST", asSelf: true)
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let task = session.uploadTask(with: request, fromFile: file)
            task.taskDescription = job.id
            jobs[index] = job.started()
            task.resume()
        } catch {
            jobs[index] = job.started().finished(status: nil, body: nil, transportError: error.localizedDescription)
        }
    }

    /// Match the queue against what the system still holds: a job marked
    /// sending with no task behind it (the phone restarted) goes again, as
    /// does anything waiting or due a retry.
    func reconcile() {
        guard !SRDemo.isOn else { return }
        session.getAllTasks { tasks in
            let live = Set(tasks.compactMap { $0.taskDescription })
            Task { @MainActor in DriveUploadQueue.shared.resubmit(except: live) }
        }
    }

    private func resubmit(except live: Set<String>) {
        var changed = false
        for job in jobs where !live.contains(job.id) {
            switch job.state {
            case .sending:
                // Lost: the attempt counts, and it goes again if it may.
                if let i = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[i] = job.finished(status: nil, body: nil, transportError: "Interrupted.")
                    if jobs[i].retriesItself {
                        jobs[i] = jobs[i].retried()
                        submit(job.id)
                    }
                    changed = true
                }
            case .waiting:
                submit(job.id)
                changed = true
            case .failed where job.retriesItself:
                if let i = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[i] = job.retried()
                    submit(job.id)
                    changed = true
                }
            default:
                break
            }
        }
        if changed { persist() }
    }

    /// Try again, from a tap on the banner: every failed file, the count reset.
    func retryFailed() {
        for i in jobs.indices {
            if case .failed = jobs[i].state {
                jobs[i].attempts = 0
                jobs[i] = jobs[i].retried()
                submit(jobs[i].id)
            }
        }
        persist()
    }

    /// Clear what is finished or refused from the banner.
    func dismissFinished() {
        let gone = jobs.filter { job in
            if case .refused = job.state { return true }
            return job.isFinished
        }
        for job in gone { try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(job.staged)) }
        jobs.removeAll { job in gone.contains { $0.id == job.id } }
        persist()
    }

    // MARK: - The system's answers (from `DriveUploadDelegate`)

    fileprivate func progressed(_ id: String, sent: Int64) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].state == .sending else { return }
        jobs[i] = jobs[i].progressed(sent)
    }

    fileprivate func finished(_ id: String, status: Int?, body: Data?, error: String?) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        let job = jobs[i].finished(status: status, body: body, transportError: error)
        jobs[i] = job
        switch job.state {
        case .stored:
            try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(job.staged))
            let next = ledger.recording(job)
            if next != ledger {
                ledger = next
                Self.write(ledger, Self.ledgerFile)
            }
            landed = DriveLanding(count: landed.count + 1, ref: DriveRef(space: job.space, folder: job.folder))
            if !jobs.contains(where: { $0.isActive }) { SRHaptic.ok() }
        case .refused:
            try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(job.staged))
        case .failed where job.retriesItself:
            // Again shortly, while the app is open; the background task
            // and the next launch catch it otherwise.
            let wait = UInt64(job.attempts) * 5_000_000_000
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: wait)
                guard let at = DriveUploadQueue.shared.jobs.firstIndex(where: { $0.id == id }),
                      DriveUploadQueue.shared.jobs[at].retriesItself else { return }
                DriveUploadQueue.shared.jobs[at] = DriveUploadQueue.shared.jobs[at].retried()
                DriveUploadQueue.shared.submit(id)
                DriveUploadQueue.shared.persist()
            }
            scheduleBackgroundResume()
        default:
            break
        }
        persist()
    }

    fileprivate func eventsFinished() {
        backgroundCompletion?()
        backgroundCompletion = nil
    }

    // MARK: - "Move from phone"

    /// The library said these photos are gone.
    func markRemoved(_ assetIds: Set<String>) {
        ledger = ledger.removing(assetIds)
        Self.write(ledger, Self.ledgerFile)
    }

    // MARK: - Background

    /// Ask for a processing window to send what is still waiting, when
    /// there is any. The system runs it on its own timetable.
    func scheduleBackgroundResume() {
        guard jobs.contains(where: { $0.isActive || $0.retriesItself }) else { return }
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Signed out: nothing of the person before is left to send, and no
    /// record of their photos.
    func clear() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        jobs = []
        ledger = DriveMoveLedger()
        try? FileManager.default.removeItem(at: Self.folder)
    }

    // MARK: - Files

    nonisolated static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DriveUploads", isDirectory: true)
    }

    nonisolated private static var jobsFile: URL { folder.appendingPathComponent("jobs.json") }
    nonisolated private static var ledgerFile: URL { folder.appendingPathComponent("moved.json") }

    private func persist() {
        Self.write(jobs, Self.jobsFile)
    }

    nonisolated private static func ensureFolder() {
        var url = folder
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Copies on their way up are not worth a backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    nonisolated private static func read<T: Decodable>(_ type: T.Type, _ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    nonisolated private static func write<T: Encodable>(_ value: T, _ url: URL) {
        ensureFolder()
        guard let data = try? JSONEncoder().encode(value) else { return }
        // Readable after first unlock: the system sends, and the app is
        // woken to finish, while the phone is locked.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Copy (or move) into the queue's folder and hash it, a megabyte at a time.
    nonisolated private static func stage(_ source: URL, to target: URL, consume: Bool) throws -> (size: Int, sha: String) {
        ensureFolder()
        let manager = FileManager.default
        try? manager.removeItem(at: target)
        if consume {
            do { try manager.moveItem(at: source, to: target) } catch { try manager.copyItem(at: source, to: target) }
        } else {
            try manager.copyItem(at: source, to: target)
        }
        let size = (try manager.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.intValue ?? 0
        return (size, try sha256(of: target))
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// A file landing in a folder: the count moves each time.
struct DriveLanding: Equatable {
    let count: Int
    let ref: DriveRef
}

/// The background session's delegate. The system calls it on its own queue,
/// even after a relaunch for a session it finished alone; each event is
/// handed to the queue on the main actor. Bodies are collected here, by
/// task, until the task completes.
final class DriveUploadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [Int: Data] = [:]

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let id = task.taskDescription else { return }
        Task { @MainActor in DriveUploadQueue.shared.progressed(id, sent: totalBytesSent) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        bodies[dataTask.taskIdentifier, default: Data()].append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let body = bodies.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let id = task.taskDescription else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode
        let message = error?.localizedDescription
        Task { @MainActor in DriveUploadQueue.shared.finished(id, status: status, body: body, error: message) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in DriveUploadQueue.shared.eventsFinished() }
    }
}
