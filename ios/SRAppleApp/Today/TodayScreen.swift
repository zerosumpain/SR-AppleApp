import SwiftUI
import Combine

// MARK: - What one request answers with

struct TodayHealth: Decodable {
    let isMock: Bool
    let strap: String
    let readiness: HealthReadiness?
    let figures: [HealthFigure]
    let generatedAt: String
}

struct TodayAlerts: Decodable {
    let pending: Int
    let unread: Int
    let latest: [Latest]

    struct Latest: Decodable, Identifiable, Hashable {
        let id: String
        let category: String
        let title: String
        let severity: String
        let createdAt: String
    }
}

extension TodayAlerts {
    /// What the Today card lists: the newest few that have not been cleared.
    ///
    /// The inbox the app already holds is preferred — it is 25 deep, so a
    /// cleared row makes room for the next one down instead of leaving the card
    /// short. Today's own three are the fallback for the first paint, before
    /// the inbox has answered.
    static func rows(
        recent: [SiteAlert],
        latest: [Latest],
        cleared: Set<String>,
        limit: Int = 3
    ) -> [Latest] {
        let source = recent.isEmpty
            ? latest
            : recent.map {
                Latest(id: $0.id, category: $0.category, title: $0.title, severity: $0.severity, createdAt: $0.createdAt)
            }
        return Array(source.filter { !cleared.contains($0.id) }.prefix(limit))
    }
}

struct TodayNews: Decodable {
    let updatedAt: String?
    let unseen: Int
    let stories: [Story]

    struct Story: Decodable, Identifiable, Hashable {
        let key: String
        let title: String
        let sourceLabel: String
        let url: String?
        let heat: Double?

        var id: String { key }
    }
}

struct TodayThread: Decodable, Hashable {
    let id: String
    let title: String?
    let updatedAt: String
}

struct TodayPayload: Decodable {
    let generatedAt: String
    let health: TodayHealth?
    let alerts: TodayAlerts?
    let news: TodayNews?
    let lastThread: TodayThread?
    /// Site connections needing the owner. Absent on a server older than the
    /// connection monitor, which decodes as nil and means nothing to show.
    let connections: TodayConnections?
    /// The daydream loop's latest notes. Absent on a server older than the
    /// loop — the synthesised decoder reads a missing key as nil, and
    /// `DaydreamFeed` never throws, so a malformed block costs only the card.
    let daydream: DaydreamFeed?

}

/// The first screen's data, in one request.
///
/// Four calls would be the tidy decomposition and the wrong one — this is the
/// screen the app opens on, over whatever the phone happens to be connected to,
/// and four round trips is four chances to show a spinner. The server settles
/// them in parallel and degrades each card on its own.
@MainActor
final class TodayStore: ObservableObject {
    @Published private(set) var payload: TodayPayload?
    @Published private(set) var loading = false
    @Published var message: String?

    private let client = SiteClient.shared

    func load(fresh: Bool = false) async {
        guard AccessStore.ownerSite, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            // Annotated: assigning into the optional would infer `TodayPayload?`
            // as the decoded type. See HealthStore for the same note.
            let fetched: TodayPayload = try await client.send(
                "api/native/today\(fresh ? "?fresh=1" : "")"
            )
            payload = fetched
            message = nil
        } catch SiteError.unpaired {
            payload = nil
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Today.
///
/// This tab did not exist. Its slot on the bar was `Connect` — a QR scanner,
/// permanently on the tab bar, for a job you do once and never again. What an
/// iPhone wants in that slot is the thing you open the app FOR, and for this app
/// that is a glance: how the body is doing, what the site has been trying to
/// tell you, and where the conversation got to.
///
/// It opens on a short live sky (`TodayHero`): the light of the time of day,
/// a sun that is the readiness ring — tap it for Health, press and hold for
/// the day's figures — and under it a line for the day so far. Then, as
/// lifted sheets on a warm ground: who is where, a trip running today, the
/// family boards somebody switched on, and the doors — Ask jkai, Daydream
/// (what the loop noticed) and Play. The alerts and the workflows are the
/// bell's: Up next repeated them and went. An urgent alert still pins itself
/// under the bar. Nothing here is the only place to read anything.
///
/// No "carry on" card for the last thread: the Chat tab is one tap away on the
/// bar and opens on that list.
struct TodayScreen: View {
    /// Held, not observed: it publishes on every upload and status line, and
    /// each one redrew all of Today. The one value drawn from it is mirrored
    /// in `companionPaired`.
    let companion: Companion
    @State private var companionPaired: Bool?
    /// When Today last re-read past the site's cache after an upload.
    @State private var freshAfterUpload = Date.distantPast
    @ObservedObject var alerts: AlertStore
    @ObservedObject var site: SitePairingModel
    @ObservedObject var family: FamilyStore
    @StateObject private var store = TodayStore()
    /// Today's Move ring, live from Apple Health on this phone.
    @StateObject private var move = MoveRingStore()
    @ObservedObject private var noticed = NoticedFeedback.shared
    private var daydream: DaydreamStore { DaydreamStore.shared }
    /// What this person may use. The owner's cards (the site's figures,
    /// alerts, workflows, what the loop noticed) are not drawn for anybody
    /// else — their endpoints would only refuse a member.
    @ObservedObject private var access = AccessStore.shared
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var connections: ConnectionsStore
    @Environment(\.scenePhase) private var scenePhase
    /// The alert tapped on the card, read in full in a sheet.
    @State private var opened: SiteAlert?
    /// Urgent alerts waved off the banner this session. Dismissing also marks
    /// the alert read, so this only bridges the moment before the inbox agrees.
    @State private var waved: Set<String> = []
    /// Today is the tab in front — the bell only rings while it is.
    @State private var onScreen = false
    /// The family's step board and task list, each a card only when this
    /// person turned it on (Settings → Today, or the page's own switch).
    @AppStorage(TodayCards.steps) private var showSteps = false
    @AppStorage(TodayCards.tasks) private var showTasks = false
    @AppStorage(TodayCards.backlog) private var showBacklog = false

    /// How often the numbers are re-read while Today is on screen. Readiness
    /// and recovery move when a sync lands on the site; five minutes is often
    /// enough to catch that and rare enough to cost nothing.
    static let refreshInterval: Duration = .seconds(300)

    var body: some View {
        ScrollView {
            // No page title. The tab bar already says this is Today and the
            // bar carries the date, so the first thing under the bar is the
            // sky, and straight under that the thing the app is opened for:
            // where everyone is.
            VStack(spacing: 0) {
                hero
                cards
            }
        }
        .srGround(.warm)
        // Pinned under the bar, not scrolled with the page: something urgent
        // stays in view until it is opened or waved away.
        .safeAreaInset(edge: .top, spacing: 0) {
            if access.current.owner, let urgent = TodayAlerts.urgent(in: alerts.recent, dismissed: waved) {
                TodayUrgentBanner(
                    alert: urgent,
                    open: {
                        SRHaptic.tap()
                        opened = urgent
                        Task { await alerts.markRead(urgent.id) }
                    },
                    dismiss: {
                        SRHaptic.select()
                        withAnimation(.snappy) { _ = waved.insert(urgent.id) }
                        Task { await alerts.markRead(urgent.id) }
                    }
                )
            }
        }
        .navigationTitle("Today")
        // Trips push onto Today's own stack: no tab of their own.
        .tripDestinations()
        // Inline, and the title itself is replaced by the `sr.` mark. There is
        // no headline on the page either: see `SRPageHeader` for why a large
        // title is not an option on this OS with a custom face, and the body
        // above for why the page does not need one.
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable {
            move.start()
            await family.load()
            await loadFamilyBoards()
            await store.load(fresh: true)
            daydream.seed(store.payload?.daydream)
            await alerts.refresh()
            await connections.refresh()
            if companion.paired { await companion.sync() }
            if access.current.owner || access.current.family { await TripStore.shared.refresh() }
        }
        .toolbar {
            // The date, where the page title used to carry it.
            ToolbarItem(placement: .topBarLeading) {
                Text(dateLine.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel(fullDate)
            }
            ToolbarItem(placement: .principal) { SRBarMark() }
            // The bell is the site's inbox, which is the owner's.
            if access.current.owner {
                ToolbarItem(placement: .topBarTrailing) {
                    TodayBell(unread: alerts.unread, active: onScreen && scenePhase == .active) {
                        SRHaptic.tap()
                        router.openAlerts()
                    }
                }
            }
            // Settings live in More. Without a More (a member with four
            // places or fewer) the cog stays here, or there would be no way in.
            if !access.allows(.more) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { SRHaptic.tap(); router.openSettings() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("open-settings")
                }
            }
        }
        .task {
            // The Watch's health figures and Today's first alerts come from
            // this store's payload — no second request.
            WatchBridge.shared.attach(today: store)
            move.start()
            // Not awaited before Today's own request: the family is a glance, and
            // the first paint must not wait on a second server.
            Task { await family.load() }
            Task { await loadFamilyBoards() }
            Task { await loadTrips() }
            await store.load()
            daydream.seed(store.payload?.daydream)
            await connections.reconcile(with: store.payload?.connections)
            // Then keep the day's numbers moving for as long as Today is on
            // screen. The task is cancelled when the tab goes away and starts
            // again, with a fresh read, when it comes back.
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled else { break }
                move.start()
                await store.load()
                daydream.seed(store.payload?.daydream)
                    await family.load()
                await loadFamilyBoards()
            }
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // A planner job left running in the background: pick it up.
            TripJobs.shared.resume()
            move.start()
            Task {
                await store.load()
                    await family.load()
                await loadFamilyBoards()
                await loadTrips()
            }
        }
        // The companion just put new health data on the site: re-read, past
        // the site's cache, so recovery and readiness reflect it.
        //
        // At most once in five minutes: location points upload every thirty
        // seconds while moving, and re-reading the whole day past the cache
        // on each one kept the radio busy for nothing.
        .onReceive(companion.$lastUpload.removeDuplicates().dropFirst()) { _ in
            guard onScreen, Date().timeIntervalSince(freshAfterUpload) > 300 else { return }
            freshAfterUpload = Date()
            Task { await store.load(fresh: true) }
        }
        .onReceive(companion.$paired.removeDuplicates()) { companionPaired = $0 }
        .overlay(alignment: .bottom) {
            if let message = store.message { SRBanner(text: message, tone: SR.error) }
        }
        .sheet(item: $opened) { alert in
            NavigationStack {
                AlertDetailScreen(alert: alert, alerts: alerts) {
                    withAnimation(.snappy) { alerts.clearFromToday([alert.id]) }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { opened = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    /// The sky, its sun and the day so far. Full width; it insets its own
    /// content. Everything it reads is already observed here — the trip's
    /// stops come from the store the hero watches itself, as the trip card
    /// does — so Today gains no new observed store.
    private var hero: some View {
        let lead = TodayHeroLead.make(
            ownerSite: access.current.owner && site.paired,
            health: store.payload?.health,
            move: move.reading,
            now: Date()
        )
        let view = family.view
        let shown = access.current.family ? (view?.people.filter { $0.status != "off" } ?? []) : []
        let initials = view?.initials ?? [:]
        let people = shown.map { person in
            TodayHeroInput.Person(subject: person.subject, name: person.name,
                                  initials: initials[person.subject] ?? person.initial, isSelf: person.isSelf,
                                  firstOut: person.today?.firstOut, out: person.status == "out")
        }
        let freshness = Dictionary(shown.map { ($0.subject, $0.freshness()) }, uniquingKeysWith: { first, _ in first })
        let selfFix = view?.people.first(where: \.isSelf)?.position.map { (lat: $0.lat, lon: $0.lon) }
        return TodayHero(
            vitals: lead.rings,
            lead: lead,
            people: people,
            freshness: freshness,
            selfFix: selfFix,
            showsTrip: site.paired && (access.current.owner || access.current.family),
            showsFamily: access.current.family,
            live: onScreen && scenePhase == .active,
            openHealth: {
                SRHaptic.tap()
                router.show(.health)
            },
            openFamily: { router.show(.family) },
            openTripDay: { router.openTrips(day: $0) }
        )
    }

    /// Everything under the sky, in the gutter.
    private var cards: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Over the companion pairing, so a family member without the
            // site's sees it too — if the owner gave them the family. Draws
            // nothing until there is somebody to show.
            if access.current.family {
                TodayFamilyCard(store: family) {
                    router.show(.family)
                }
            }

            // The family's next moves live on the Family tab now, not
            // here: one place for where everyone is going.

            // A trip running today (in its own time zone): what is next
            // and when to leave. Before one, a quieter line; with no
            // trips at all, nothing. Every family member's (v5).
            if site.paired && (access.current.owner || access.current.family) {
                TodayTripCard()
            }

            // Off unless asked for; over the SITE credential.
            if access.familyBoards && site.paired {
                if showSteps {
                    TodayStepsCard { router.openFamilyPage(.steps) }
                }
                if showTasks {
                    TodayTasksCard { router.openFamilyPage(.tasks) }
                }
                if showBacklog {
                    TodayBacklogCard { router.openFamilyPage(.backlog) }
                }
            }

            if access.current.owner && !site.paired {
                // The owner's QR. A member's phone pairs itself, and a
                // member with neither chat nor news has nothing to pair.
                connectCard
            } else if !(companionPaired ?? companion.paired) && !access.current.owner {
                // Nobody knows who this is yet: the companion is where
                // that answer comes from.
                companionCard
            } else {
                // The doors, two by two: Ask and Daydream, then Play across
                // the row. Health is the sun now, not a door.
                TodayTileGrid(tiles: TodayTile.doors(access: access.current, sitePaired: site.paired)) { kind in
                    tile(kind)
                }
                // No top story here: News is a door in More (John, 2026-10-05).
            }
            // Sync now and its status moved to More (and stay in
            // Settings): a maintenance control, not a first-screen one.
        }
        .padding(.horizontal, SR.gutter)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The boards behind whichever family cards are on. Nothing is read for
    /// a card that is off.
    private func loadFamilyBoards() async {
        guard access.familyBoards else { return }
        if showSteps { await FamilyStepsStore.shared.load() }
        if showTasks { await FamilyTasksStore.shared.load() }
        if showBacklog { await FamilyBacklogStore.shared.load() }
        // No card, but still read: every read reschedules this phone's
        // leave-by reminders.
        await FamilyForecastStore.shared.load()
    }

    /// Trips: refreshed on a foreground when online (every bundle on its
    /// ETag, so an unchanged trip costs a 304), and the running day's Lock
    /// Screen card and geofences brought up to date.
    private func loadTrips() async {
        guard site.paired && (access.current.owner || access.current.family) else { return }
        await TripStore.shared.refreshIfStale()
        TripLive.shared.refresh()
        TripArrivals.shared.refresh()
        TripOffPlan.shared.refresh()
    }

    // MARK: - Header

    /// "SUN 27 SEP" in the bar: short enough to sit beside the mark and the
    /// two buttons at any width a phone has.
    private var dateLine: String {
        Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// What VoiceOver says for it: "Sunday 27 September".
    private var fullDate: String {
        Date().formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    // MARK: - Cards

    /// Before the companion is paired the app cannot know who is holding it,
    /// so it offers only the pairing every person needs.
    private var companionCard: some View {
        SRCard(accented: true) {
            VStack(alignment: .leading, spacing: 12) {
                SRSectionLabel(text: "Not connected", prominent: true)
                Text("Connect this iPhone")
                    .font(SR.Text.display())
                    .foregroundStyle(SR.ink)
                Text("Pair with the companion to upload from Apple Health. What else appears here is up to the account it pairs as.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { SRHaptic.tap(); router.openSettings(.connections) } label: {
                    SRButtonLabel(title: "Connect", icon: "qrcode.viewfinder", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityLabel("CONNECT")
                .padding(.top, 4)
            }
        }
    }

    private var connectCard: some View {
        SRCard(accented: true) {
            VStack(alignment: .leading, spacing: 12) {
                SRSectionLabel(text: "Not connected", prominent: true)
                Text("Connect this iPhone")
                    .font(SR.Text.display())
                    .foregroundStyle(SR.ink)
                Text("Pair with strangeramblings.com to read your threads, the news desk and your health figures here.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { SRHaptic.tap(); router.openSettings(.connections) } label: {
                    SRButtonLabel(title: "Connect", icon: "qrcode.viewfinder", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityLabel("CONNECT")
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Tiles

    @ViewBuilder
    private func tile(_ kind: TodayTile) -> some View {
        switch kind {
        case .ask: askTile
        // Not a door any more: the sun in the sky opens Health. Kept for
        // the switch, since `kinds` still lists it.
        case .health: EmptyView()
        case .daydream: daydreamTile
        case .games: gamesTile
        }
    }

    /// Chat: a new jkai thread or "msg family", both from its list. The one
    /// filled control on Today.
    private var askTile: some View {
        Button {
            SRHaptic.tap()
            router.show(.chat)
        } label: {
            TodayAskTile()
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel("JkAi and messages")
        .accessibilityIdentifier("today-ask")
    }

    /// Its own view, watching the notes: a rating or a re-read redraws the
    /// tile, not the whole of Today.
    private var daydreamTile: some View {
        Button {
            SRHaptic.tap()
            router.openDaydream()
        } label: {
            TodayDaydreamTile()
        }
        .buttonStyle(SRPressStyle())
        .accessibilityIdentifier("today-daydream")
    }

    /// Its own view, watching the lobby: the invite poll redraws the tile,
    /// not the whole of Today.
    private var gamesTile: some View {
        Button {
            SRHaptic.tap()
            router.show(.games)
        } label: {
            TodayGamesTile()
        }
        .buttonStyle(SRPressStyle())
        .accessibilityIdentifier("today-games")
    }
}
