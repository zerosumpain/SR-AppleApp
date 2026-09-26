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

    init(companion: Companion) {
        self.companion = companion
    }

    func load() async {
        guard !loading else { return }
        #if DEBUG
        // DEBUG only, like every demo path: `SRDemo` does not exist in a
        // Release build, and the companion lane has no fixture protocol.
        if SRDemo.isOn {
            let demo = SRDemoFixtures.householdView(now: Date())
            view = demo.view
            updated = demo.updated
            loaded = true
            return
        }
        #endif
        guard companion.paired else {
            view = nil
            loaded = true
            return
        }
        loading = true
        defer { loading = false; loaded = true }
        do {
            let response: HouseholdViewResponse = try await companion.api.request("household/view", timeout: 12)
            companion.adoptWatch(response.view?.watch)
            await companion.adoptAccess(response.view?.access)
            view = response.view?.showsHousehold == true ? response.view : nil
            updated = response.updated
            message = nil
        } catch {
            // Keep the last view: a map that vanishes on a dropped connection
            // is worse than one labelled with its age.
            message = error.localizedDescription
        }
    }

    /// "Updated 2m ago", from when the server filed the view.
    var freshness: String? {
        guard let updated, !shortAgo(updated).isEmpty else { return nil }
        let ago = shortAgo(updated)
        return ago == "0m" ? "Updated just now" : "Updated \(ago) ago"
    }
}
