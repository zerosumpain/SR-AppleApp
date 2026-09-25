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
    /// The ids that were showing when the reader made the banner smaller.
    /// Session-only by design: never persisted, so a relaunch shows it in full.
    @Published private(set) var collapsedFor: Set<String>?

    private let outbox: Outbox?
    private let client = SiteClient.shared

    init(outbox: Outbox?) {
        self.outbox = outbox
        // Only while the site is paired: a cache left by a credential since
        // revoked would put up a banner nobody on this phone can act on.
        let saved = SiteClient.shared.isPaired ? outbox?.state.connections : nil
        items = saved?.items ?? []
        checkedAt = saved?.checkedAt
    }

    var count: Int { items.count }

    var bannerMode: ConnectionBannerMode {
        ConnectionBannerMode.of(items: items, collapsedFor: collapsedFor)
    }

    func collapse() {
        SRHaptic.select()
        collapsedFor = Set(items.map(\.id))
    }

    func expand() {
        SRHaptic.select()
        collapsedFor = nil
    }

    // MARK: - Reading

    func refresh() async {
        guard client.isPaired else {
            // Unpaired — or just disconnected. The site's connections are the
            // site's business, and this phone no longer speaks for it.
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
        if let collapsedFor, collapsedFor.isEmpty || items.isEmpty { self.collapsedFor = nil }
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
        guard SiteClient.shared.isPaired else { return }
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
