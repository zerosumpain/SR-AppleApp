import Foundation

/// The household view, read from the companion server — shared by the Today
/// mini-map and the Family tab, so opening the tab from the map shows the same
/// picture it was opened from rather than a spinner.
///
/// Over the COMPANION pairing, not the site's: every phone in the family has
/// that one, and only the owner's has the other.
///
/// A failed read never empties the map. The first request after iOS wakes the
/// app, or as it changes network, often fails; the map used to go blank then
/// ("Nobody is sharing a place yet") until the next refresh. Now a failure is
/// retried once, the last view stays up with its "Updated … ago", and a cold
/// start opens on the last view this phone was sent (`FamilyViewCache`). Only
/// the server refusing this phone (401/403) takes the family off the screen.
@MainActor
final class FamilyStore: ObservableObject {
    @Published private(set) var view: HouseholdView?
    /// When the server last filed this view — up to one observe cycle (two
    /// minutes) behind the positions it describes.
    @Published private(set) var updated: String?
    @Published private(set) var loaded = false
    @Published var message: String?

    /// Re-read while a map is on screen. The view itself changes every two
    /// minutes on the server; asking more often than that buys nothing.
    /// 15 s: the site files a fresh view within about 30 s of a phone's
    /// upload while somebody is out on close tracking.
    static let refreshInterval: Duration = .seconds(15)

    private let companion: Companion
    private var loading = false
    /// This phone's own view, as read. `view` is this — or, while the owner
    /// is viewing the app as somebody, that person's view instead.
    private var real: HouseholdView?

    /// The app's one store, for what reads the family without being handed
    /// it — msg family's circles (`FamilyFaces`).
    private(set) static weak var current: FamilyStore?

    init(companion: Companion) {
        self.companion = companion
        Self.current = self
        if !SRDemo.isOn, companion.paired, let cached = FamilyViewCache.load() {
            real = cached.view
            updated = cached.updated
            applyViewingAs()
        }
    }

    func load() async {
        guard !loading else { return }
        // Demo mode (the review demo, or `-SRDemo`): the companion lane has
        // no fixture protocol, and a demo sends nothing to it.
        if SRDemo.isOn {
            let demo = SRDemoFixtures.householdView(now: Date())
            view = demo.view
            updated = demo.updated
            loaded = true
            return
        }
        guard companion.paired else {
            real = nil
            view = nil
            FamilyViewCache.clear()
            loaded = true
            return
        }
        loading = true
        defer { loading = false; if !loaded { loaded = true } }
        do {
            let response = try await fetchView()
            companion.adoptWatch(response.view?.watch)
            await companion.adoptAccess(response.view?.access)
            AccessStore.shared.adopt(previews: response.view?.previewAs)
            // Polled every 15 s, but the server files a new view every two
            // minutes or so: a read that changed nothing must not republish
            // (each publish re-evaluates the map) or rewrite the cache file.
            let changed = real != response.view || updated != response.updated
            real = response.view
            applyViewingAs()
            if updated != response.updated { updated = response.updated }
            if changed {
                FamilyNowWidgetBridge.save(response.view)
                if let fresh = response.view {
                    FamilyViewCache.save(view: fresh, updated: response.updated)
                } else {
                    FamilyViewCache.clear()
                }
            }
            if message != nil { message = nil }
            // The family's pictures ride along, at most every five minutes.
            Task { await FamilyPhotos.shared.load() }
        } catch {
            if Self.isRefusal(error) {
                real = nil; view = nil; updated = nil
                companion.adoptWatch(nil)
                AccessStore.shared.adopt(previews: nil)
                FamilyWidgetBridge.clear()
                FamilyViewCache.clear()
            }
            // Anything else — offline, a timeout, the first request after iOS
            // wakes the app — leaves the last view up; its "Updated … ago"
            // says how old it is.
            message = error.localizedDescription
        }
    }

    /// One read, and one more a moment later if the first did not land (a
    /// refusal is an answer, not a blip: it is not retried). A view the sync
    /// read seconds ago (`Companion.reusableView`) is that read.
    private func fetchView() async throws -> HouseholdViewResponse {
        if let recent = companion.reusableView() { return recent }
        let response: HouseholdViewResponse
        do {
            response = try await companion.api.request("household/view", timeout: 12)
        } catch where !Self.isRefusal(error) {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            response = try await companion.api.request("household/view", timeout: 12)
        }
        companion.noteView(response)
        return response
    }

    /// The companion server refusing this phone: its access has ended.
    nonisolated static func isRefusal(_ error: Error) -> Bool {
        if case .response(let status, _)? = error as? CompanionError { return status == 401 || status == 403 }
        return false
    }

    /// Show the person the owner is viewing the app as, or this phone's own
    /// view. Called on every read, and when "View as" changes.
    func applyViewingAs() {
        let shown = AccessStore.shared.viewingAs?.view ?? real
        let next = shown?.showsHousehold == true ? shown : nil
        if view != next { view = next }
    }

    /// "Updated 2m ago", from when the server filed the view.
    var freshness: String? {
        guard let updated, !shortAgo(updated).isEmpty else { return nil }
        let ago = shortAgo(updated)
        return ago == "0m" ? "Updated just now" : "Updated \(ago) ago"
    }
}

/// The last family view this phone was sent, kept on disk so a cold start
/// opens on where everyone was rather than an empty map while the first read
/// is in flight (or failing). Positions carry their own ages, and the view its
/// "Updated … ago"; one older than `maxAge` is not shown at all.
///
/// Family positions, so: in this app's own container, excluded from backups,
/// and deleted wherever the phone loses family access (`FamilyStore` on a
/// refusal or an unpaired companion; `Companion` and `SiteClient` on revoke).
enum FamilyViewCache {
    struct Entry: Codable, Equatable {
        let view: HouseholdView
        let updated: String?
        let savedAt: Date
    }

    static let maxAge: TimeInterval = 12 * 60 * 60

    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("family-view.json")
    }

    static func load(now: Date = Date(), from file: URL = url) -> Entry? {
        guard let data = try? Data(contentsOf: file),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              now.timeIntervalSince(entry.savedAt) <= maxAge
        else { return nil }
        return entry
    }

    static func save(view: HouseholdView, updated: String?, now: Date = Date(), to file: URL = url) {
        guard let data = try? JSONEncoder().encode(Entry(view: view, updated: updated, savedAt: now)) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = file
        try? target.setResourceValues(values)
    }

    static func clear(at file: URL = url) {
        try? FileManager.default.removeItem(at: file)
    }
}
