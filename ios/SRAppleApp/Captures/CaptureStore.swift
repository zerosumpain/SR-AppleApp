import Foundation
import UIKit

/// Captures: the queue on the phone and the list on the site.
///
/// The queue is the phone's half: every capture lands in it at Stop and
/// leaves only when the site has the metadata, the recording and (unless the
/// deny list said no) the screenshot. `drain` walks each one through
/// read → create → audio → screen, saving after every step, so a capture the
/// app was killed halfway through picks up where it stopped and never sends
/// twice. It runs at Stop, when the app comes to the front, and when the
/// Captures page opens — never on a timer.
///
/// The owner's alone (`AccessStore.ownerSite`): the site's routes are
/// `withDevice`, which answers anybody else 403.
@MainActor
final class CaptureStore: ObservableObject {
    static let shared = CaptureStore()

    /// Waiting on the phone, oldest first.
    @Published private(set) var queue: [PendingCapture] = []
    /// The site's list, newest first.
    @Published private(set) var items: [CaptureSummary] = []
    @Published private(set) var next: String?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    /// A capture is being read or sent right now.
    @Published private(set) var draining = false

    private let client = SiteClient.shared

    private init() {
        if let data = try? Data(contentsOf: CaptureFiles.queueURL) {
            queue = CaptureQueueFile.decode(data).items
        }
    }

    // MARK: - The queue

    func enqueue(_ capture: PendingCapture) {
        queue.removeAll { $0.id == capture.id }
        queue.append(capture)
        persist()
        Task { await drain() }
    }

    /// Throw a waiting capture away, files and all.
    func discard(_ id: String) {
        guard let item = queue.first(where: { $0.id == id }) else { return }
        CaptureFiles.remove(item.audioFile)
        CaptureFiles.remove(item.screenshotFile)
        queue.removeAll { $0.id == id }
        persist()
    }

    /// Read and send whatever is due. Stops at the first network failure:
    /// the rest would fail the same way.
    func drain(force: Bool = false) async {
        guard !draining, AccessStore.ownerSite || SRDemo.isOn else { return }
        draining = true
        // A capture stopped from the Lock Screen is sent in the seconds iOS
        // gives a backgrounded app; past them it waits for the next open.
        let background = CaptureBackgroundTask()
        defer {
            draining = false
            background.end()
        }
        var sentAny = false
        for id in queue.map(\.id) {
            guard var item = queue.first(where: { $0.id == id }) else { continue }
            guard force || item.isDue() else { continue }
            let ok = await advance(&item)
            if item.stage == .done {
                CaptureFiles.remove(item.audioFile)
                CaptureFiles.remove(item.screenshotFile)
                queue.removeAll { $0.id == id }
                persist()
                sentAny = true
            }
            if !ok { break }
        }
        if sentAny { await load() }
    }

    /// Walk one capture as far as it will go. False on a failure worth
    /// stopping the whole drain for.
    private func advance(_ item: inout PendingCapture) async -> Bool {
        while true {
            switch item.stage {
            case .done:
                return true
            case .process:
                // Long recordings are not read with the app in the background.
                if UIApplication.shared.applicationState != .active, item.duration > CaptureProcessor.backgroundLimit {
                    return true
                }
                // Counted BEFORE the pass, so a pass that crashes the app is
                // not retried for ever.
                item.processAttempts += 1
                save(item)
                item = await CaptureProcessor.process(item)
                save(item)
            case .create:
                do {
                    let body = try JSONEncoder().encode(item.createRequest())
                    let made: CaptureCreated = try await client.send(CapturePaths.root, method: "POST", body: body)
                    item.serverId = made.id
                    item.attempts = 0
                    item.lastError = nil
                    save(item)
                } catch {
                    failed(&item, error)
                    return false
                }
            case .audio:
                guard let id = item.serverId, let file = item.audioFile else { return true }
                do {
                    try await put(CapturePaths.audio(id), file: CaptureFiles.url(file), type: "audio/mp4")
                    item.audioSent = true
                    item.attempts = 0
                    item.lastError = nil
                    save(item)
                } catch {
                    if (error as? SiteError)?.status == 404 { item.serverId = nil }
                    failed(&item, error)
                    return false
                }
            case .screen:
                guard let id = item.serverId, let file = item.screenshotFile else { return true }
                do {
                    try await put(CapturePaths.screen(id), file: CaptureFiles.url(file), type: "image/jpeg")
                    item.screenSent = true
                    item.attempts = 0
                    item.lastError = nil
                    save(item)
                } catch {
                    if (error as? SiteError)?.status == 404 { item.serverId = nil; item.audioSent = false }
                    failed(&item, error)
                    return false
                }
            }
        }
    }

    private func failed(_ item: inout PendingCapture, _ error: Error) {
        item.attempts += 1
        item.lastTriedAt = Date()
        item.lastError = error.localizedDescription
        save(item)
    }

    /// A raw body, never multipart: SvelteKit refuses a cross-site form POST
    /// before any route runs (see `SiteClient.upload`).
    private func put(_ path: String, file: URL, type: String) async throws {
        let data = try Data(contentsOf: file)
        let (body, response) = try await client.exchange(path, method: "PUT", body: data, headers: ["Content-Type": type], timeout: 600)
        guard (200..<300).contains(response.statusCode) else {
            struct Refusal: Decodable { let error: String }
            let message = (try? JSONDecoder().decode(Refusal.self, from: body))?.error
                ?? "\(response.statusCode) from the server."
            throw SiteError.status(response.statusCode, message)
        }
    }

    private func save(_ item: PendingCapture) {
        if let index = queue.firstIndex(where: { $0.id == item.id }) {
            queue[index] = item
        }
        persist()
    }

    private func persist() {
        CaptureFiles.prepare()
        guard let data = CaptureQueueFile(items: queue).encoded() else { return }
        try? data.write(to: CaptureFiles.queueURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: - The site's list

    func load() async {
        guard AccessStore.ownerSite || SRDemo.isOn else { return }
        loading = true
        defer { loading = false }
        do {
            let page: CapturePage = try await client.send(CapturePaths.list())
            items = page.items
            next = page.next
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard let next, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page: CapturePage = try await client.send(CapturePaths.list(before: next))
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            self.next = page.next
        } catch {
            self.error = error.localizedDescription
        }
    }

    func search(_ filters: CaptureSearchFilters) async throws -> CaptureSearchResult {
        try await client.send(CapturePaths.search(filters))
    }

    func capture(_ id: String) async throws -> Capture {
        try await client.send(CapturePaths.capture(id))
    }

    func entity(_ id: String) async throws -> CaptureEntityPage {
        try await client.send(CapturePaths.entity(id))
    }

    func patch(_ id: String, _ patch: CapturePatch) async throws -> Capture {
        let capture: Capture = try await client.send(CapturePaths.capture(id), method: "PATCH", body: try JSONEncoder().encode(patch))
        refreshRow(from: capture)
        return capture
    }

    func decide(_ captureId: String, _ actionId: String, _ decision: CaptureDecision) async throws -> CaptureAction {
        try await client.send(CapturePaths.action(captureId, actionId), method: "POST", body: try JSONEncoder().encode(decision))
    }

    func delete(_ id: String) async throws {
        try await client.call(CapturePaths.capture(id), method: "DELETE")
        items.removeAll { $0.id == id }
    }

    /// The recording's bytes, for the player.
    func audio(_ id: String) async throws -> Data { try await client.bytes(CapturePaths.audio(id)) }
    func screen(_ id: String) async throws -> Data { try await client.bytes(CapturePaths.screen(id)) }

    /// Keep the list row in step with a detail that changed.
    func refreshRow(from capture: Capture) {
        guard let index = items.firstIndex(where: { $0.id == capture.id }) else { return }
        items[index].title = capture.title ?? items[index].title
        items[index].status = capture.status
        items[index].actionsOpen = capture.openActions
        items[index].app = capture.screen?.appName ?? items[index].app
        items[index].speakers = capture.speakers.map(\.displayName)
    }

    /// Signed out, or the credential went: nothing of the list stays.
    func reset() {
        items = []
        next = nil
        error = nil
    }
}

/// The seconds iOS grants a backgrounded app, asked for once and handed back
/// once — at the end of the work, or when iOS says time is up.
@MainActor
final class CaptureBackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init() {
        id = UIApplication.shared.beginBackgroundTask(withName: "sr.captures.drain") { [weak self] in
            // Called on the main thread, and it must end the task before it
            // returns or iOS ends the app.
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
