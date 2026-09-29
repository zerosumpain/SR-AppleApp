import Foundation

/// The household view, read from the companion server — shared by the Today
/// mini-map and the Family tab, so opening the tab from the map shows the same
/// picture it was opened from rather than a spinner.
///
/// Over the COMPANION pairing, not the site's: every phone in the family has
/// that one, and only the owner's has the other.
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

    init(companion: Companion) {
        self.companion = companion
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
            loaded = true
            return
        }
        loading = true
        defer { loading = false; loaded = true }
        do {
            let response: HouseholdViewResponse = try await companion.api.request("household/view", timeout: 12)
            await companion.adoptWatch(response.view?.watch)
            await companion.adoptAccess(response.view?.access)
            AccessStore.shared.adopt(previews: response.view?.previewAs)
            real = response.view
            applyViewingAs()
            updated = response.updated
            message = nil
        } catch {
            if case .response(let status, _)? = error as? CompanionError, status == 401 || status == 403 {
                real = nil; view = nil; updated = nil
                await companion.adoptWatch(nil)
                AccessStore.shared.adopt(previews: nil)
                FamilyWidgetBridge.clear()
            } else if let updated, let date = ISO8601DateFormatter().date(from: updated), Date().timeIntervalSince(date) > 300 {
                real = nil; view = nil
            }
            message = error.localizedDescription
        }
    }

    /// Event-driven long polling sends only current positions. Rich household
    /// history keeps its slower refresh; neither lane blocks the other.
    func followLive() async {
        guard companion.paired, !SRDemo.isOn else { return }
        var revision: String?
        while !Task.isCancelled, companion.paired {
            do {
                let response: LiveFamilyResponse = try await companion.api.request("household/live", query: revision.map { [URLQueryItem(name: "since", value: $0)] } ?? [], timeout: 28)
                try Task.checkCancellation()
                revision = response.revision
                if response.revision == "unavailable" {
                    real = nil; view = nil
                    await load()
                    try await Task.sleep(for: .seconds(5))
                    continue
                }
                // Owner preview views have their own scope and remain on their
                // scoped snapshot until a fresh preview arrives.
                for fix in response.positions {
                    guard let index = real?.people.firstIndex(where: { $0.subject == fix.subject && $0.sharing }) else { continue }
                    if let old = real?.people[index].position, old.at > fix.position.at { continue }
                    real?.people[index].position = fix.position
                    real?.people[index].lastSeenAt = fix.position.at
                    real?.people[index].batteryPct = fix.battery
                }
                applyViewingAs()
            } catch {
                if Task.isCancelled { return }
                if case .response(let status, _)? = error as? CompanionError, status == 401 || status == 403 {
                    real = nil; view = nil; updated = nil
                    FamilyWidgetBridge.clear()
                    return
                }
                message = "Live updates paused. The map shows the last received fix."
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }

    /// Show the person the owner is viewing the app as, or this phone's own
    /// view. Called on every read, and when "View as" changes.
    func applyViewingAs() {
        let shown = AccessStore.shared.viewingAs?.view ?? real
        view = shown?.showsHousehold == true ? shown : nil
    }

    /// "Updated 2m ago", from when the server filed the view.
    var freshness: String? {
        guard let updated, !shortAgo(updated).isEmpty else { return nil }
        let ago = shortAgo(updated)
        return ago == "0m" ? "Updated just now" : "Updated \(ago) ago"
    }
}
