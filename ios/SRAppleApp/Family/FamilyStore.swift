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
    private var liveFixes: [String: LiveFamilyResponse.Fix] = [:]

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
            liveFixes = [:]
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
                real = nil; view = nil; updated = nil; liveFixes = [:]
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
        var scope: String?
        while !Task.isCancelled, companion.paired {
            do {
                let response: LiveFamilyResponse = try await companion.api.request("household/live", query: revision.map { [URLQueryItem(name: "since", value: $0)] } ?? [], timeout: 28)
                try Task.checkCancellation()
                revision = response.revision
                if response.revision == "unavailable" {
                    real = nil; view = nil; liveFixes = [:]
                    await load()
                    try await Task.sleep(for: .seconds(5))
                    continue
                }
                // Owner preview views have their own scope and remain on their
                // scoped snapshot until a fresh preview arrives.
                if let currentScope = response.scope, currentScope != scope {
                    real = nil; view = nil; liveFixes = [:]
                    await load()
                    scope = currentScope
                }
                for fix in response.positions {
                    if let old = liveFixes[fix.subject], old.position.at > fix.position.at { continue }
                    liveFixes[fix.subject] = fix
                }
                message = nil
                applyViewingAs()
            } catch {
                if Task.isCancelled { return }
                if case .response(let status, _)? = error as? CompanionError, status == 401 || status == 403 {
                    real = nil; view = nil; updated = nil; liveFixes = [:]
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
        if var own = real {
            liveFixes = liveFixes.filter { id, _ in own.people.contains { $0.subject == id && $0.sharing } }
            for index in own.people.indices {
                guard let fix = liveFixes[own.people[index].subject], own.people[index].sharing else { continue }
                if let old = own.people[index].position, old.at > fix.position.at { continue }
                own.people[index].position = fix.position
                own.people[index].lastSeenAt = fix.position.at
                own.people[index].batteryPct = fix.battery
                if fix.moving, fix.speed >= 0.5, Self.fixAge(fix.position.at) < 30 {
                    own.people[index].moving = FamilyPerson.Moving(mode: fix.speed < 2.8 ? "walking" : fix.speed < 7.5 ? "active" : "vehicle",
                        speedKmh: fix.speed * 3.6, since: own.people[index].moving?.since ?? fix.position.at)
                } else { own.people[index].moving = nil }
            }
            real = own
        }
        if var current = real {
            for index in current.people.indices where Self.fixAge(current.people[index].position?.at) >= 30 {
                current.people[index].moving = nil
            }
            real = current
        }
        let shown = AccessStore.shared.viewingAs?.view ?? real
        view = shown?.showsHousehold == true ? shown : nil
    }

    private static func fixAge(_ at: String?) -> TimeInterval {
        guard let at else { return .infinity }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let precise = formatter.date(from: at)
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = precise ?? formatter.date(from: at) else { return .infinity }
        return Date().timeIntervalSince(date)
    }

    /// "Updated 2m ago", from when the server filed the view.
    var freshness: String? {
        guard let updated, !shortAgo(updated).isEmpty else { return nil }
        let ago = shortAgo(updated)
        return ago == "0m" ? "Updated just now" : "Updated \(ago) ago"
    }
}
