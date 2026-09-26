import Foundation
import Combine

/// The site's connections that need the owner, and whether the banner shows.
///
/// ## Why this exists
///
/// The site's Gmail authorisation lapses about once a week. Nothing said so:
/// the mail steps quietly stopped, and the owner found out when something
/// downstream was missing. The site now knows when a connection has lapsed;
/// this is the phone's half — a banner at the top of every tab that cannot be
/// dismissed while anything is wrong, a count on the app icon, and a louder
/// local notification when the pull lane brings one down.
///
/// ## When it asks
///
/// On launch, on every return to the foreground, on Today's pull-to-refresh,
/// and on the two background wakes the app already gets (`BGAppRefreshTask`
/// and the HealthKit observer), beside the notification drain. There is no
/// push certificate — see `AlertStore` — so those wakes are all there is.
///
/// The last answer is kept in `PersistedState`, so the banner is there the
/// instant the app opens and survives a launch with no network.
@MainActor
final class ConnectionsStore: ObservableObject {
    @Published private(set) var items: [ConnectionItem]
    @Published private(set) var checkedAt: Date?
    @Published private(set) var loading = false
    @Published var message: String?
    /// Problems with this phone's OWN health link — everyone's, owner or not.
    /// See `PersonalHealthCheck`.
    @Published private(set) var personal: [ConnectionItem] = []
    /// What the banner was dismissed for, by `dismissKey`. Kept across
    /// launches — a dismissal that came back on every open would not be one —
    /// and pruned as problems clear, so a relapse shows again.
    @Published private(set) var dismissed: Set<String>
    /// What the banner's button does for a problem the phone fixes itself.
    /// Set by `ContentView`, which holds the companion and the router.
    var runLocalFix: ((PersonalFix) -> Void)?

    private let outbox: Outbox?
    private let client = SiteClient.shared
    private let defaults: UserDefaults
    static let dismissedKey = "connections-dismissed"

    init(outbox: Outbox?, defaults: UserDefaults = .standard) {
        self.outbox = outbox
        self.defaults = defaults
        dismissed = Set(defaults.stringArray(forKey: Self.dismissedKey) ?? [])
        // Only while the site is paired, and paired as the owner: a cache left
        // by a credential since revoked — or read on a member's phone, which
        // has no business with the site's connections — would put up a banner
        // nobody on this phone can act on.
        let saved = AccessStore.ownerSite ? outbox?.state.connections : nil
        items = saved?.items ?? []
        checkedAt = saved?.checkedAt
    }

    /// The site's connections needing the owner.
    var count: Int { items.count }

    /// Everything wrong: the site's (owner only) and this phone's own.
    var all: [ConnectionItem] { items + personal }

    /// What the banner shows: everything not dismissed.
    var visible: [ConnectionItem] { all.filter { !dismissed.contains($0.dismissKey) } }

    var bannerMode: ConnectionBannerMode {
        ConnectionBannerMode.of(items: all, dismissed: dismissed)
    }

    /// Take the banner down for what it is showing now.
    func dismiss() {
        SRHaptic.select()
        dismissed.formUnion(visible.map(\.dismissKey))
        saveDismissed()
    }

    /// This phone's own problems, re-checked. Dismissals of personal problems
    /// that have cleared are forgotten here; the site's are pruned in `apply`.
    func setPersonal(_ found: [ConnectionItem]) {
        if found != personal { personal = found }
        prune(personal: true, keeping: found)
    }

    private func prune(personal: Bool, keeping current: [ConnectionItem]) {
        let live = Set(current.map(\.dismissKey))
        let kept = dismissed.filter { key in
            key.hasPrefix(PersonalHealthCheck.prefix) != personal || live.contains(key)
        }
        guard kept != dismissed else { return }
        dismissed = kept
        saveDismissed()
    }

    private func saveDismissed() {
        defaults.set(Array(dismissed), forKey: Self.dismissedKey)
    }

    // MARK: - Reading

    func refresh() async {
        guard AccessStore.ownerSite else {
            // Unpaired — or just disconnected, or a member's phone. The site's
            // connections are the owner's business, and this phone does not
            // speak for them.
            await apply(ConnectionsSnapshot())
            return
        }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let feed: ConnectionsFeed = try await client.send("api/native/connections")
            await apply(Self.snapshot(of: feed))
            message = nil
        } catch SiteError.unpaired {
            await apply(ConnectionsSnapshot())
        } catch {
            // Keep the last answer. A banner that vanished because the phone
            // went into a tunnel would say "all fixed" when nothing was.
            message = error.localizedDescription
        }
    }

    /// Today's payload carries a count. When it disagrees with what is showing,
    /// ask for the list rather than trusting a three-item preview.
    func reconcile(with today: TodayConnections?) async {
        guard let today, today.needsAttention != items.count else { return }
        await refresh()
    }

    // MARK: - Writing

    nonisolated static func snapshot(of feed: ConnectionsFeed, now: Date = Date()) -> ConnectionsSnapshot {
        ConnectionsSnapshot(
            items: feed.needsAttention,
            checkedAt: feed.checkedAt.flatMap(parseTimestamp) ?? now
        )
    }

    private func apply(_ snapshot: ConnectionsSnapshot) async {
        items = snapshot.items
        checkedAt = snapshot.checkedAt
        prune(personal: false, keeping: snapshot.items)
        Self.persist(snapshot, in: outbox)
        await AppBadge.update(connections: snapshot.items.count)
    }

    /// Into the state file only when the list actually changed. That file is
    /// the health upload queue and a write is the whole queue, so a refresh on
    /// every foreground must not rewrite it for a timestamp.
    static func persist(_ snapshot: ConnectionsSnapshot, in outbox: Outbox?) {
        guard let outbox, (outbox.state.connections?.items ?? []) != snapshot.items else { return }
        try? outbox.change { $0.connections = snapshot }
    }

    /// One background pass, beside the notification drain.
    ///
    /// Static, like `AlertStore.backgroundPass`: a wake has no view hierarchy
    /// watching `@Published` state, and seconds to finish in.
    static func backgroundPass(outbox: Outbox?) async {
        guard AccessStore.ownerSite else { return }
        do {
            let feed: ConnectionsFeed = try await SiteClient.shared.send("api/native/connections")
            let fresh = Self.snapshot(of: feed)
            persist(fresh, in: outbox)
            await AppBadge.update(connections: fresh.items.count)
        } catch {
            return
        }
    }
}
