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

/// Home (the `today` tab).
///
/// The first screen is the whole app at a glance: a greeting, the briefing —
/// the three things worth knowing, ranked across everything — then one tile
/// per feature this person may use, the family's Orbit first, each a chart
/// with its numbers on it and a tap into the detail. Which tiles, and in what
/// order, is the reader's: Settings → Home, or a long press on any tile. See
/// `HomeLayout`.
///
/// Prism (2026-10-18) replaced the First Light sky here. What it kept: the
/// urgent alert pinned under the bar, the bell, one request for the owner's
/// figures (`/api/native/today`), every tile at a fixed height, and nothing
/// animating while the page is idle.
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
    /// Today's Move, Exercise and Stand, live from Apple Health on this phone.
    @StateObject private var rings = ActivityRingsStore()
    @ObservedObject private var noticed = NoticedFeedback.shared
    private var daydream: DaydreamStore { DaydreamStore.shared }
    /// What this person may use. The owner's cards (the site's figures,
    /// alerts, workflows, what the loop noticed) are not drawn for anybody
    /// else — their endpoints would only refuse a member.
    @ObservedObject private var access = AccessStore.shared
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var connections: ConnectionsStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The alert tapped on the card, read in full in a sheet.
    @State private var opened: SiteAlert?
    /// Urgent alerts waved off the banner this session. Dismissing also marks
    /// the alert read, so this only bridges the moment before the inbox agrees.
    @State private var waved: Set<String> = []
    /// Today is the tab in front — the bell only rings while it is.
    @State private var onScreen = false
    /// Which tiles, in what order — Settings → Home.
    @AppStorage(HomeLayout.key) private var homeLayout = ""
    /// The workflows' three numbers, for the Flows tile. Read only while it
    /// is on Home.
    @StateObject private var flowAttention = FlowAttentionStore()

    /// How often the numbers are re-read while Today is on screen. Readiness
    /// and recovery move when a sync lands on the site; five minutes is often
    /// enough to catch that and rare enough to cost nothing.
    static let refreshInterval: Duration = .seconds(300)

    var body: some View {
        ScrollView {
            // No page title: the greeting is the page's top, and straight
            // under it the thing the app is opened for — where everyone is.
            VStack(alignment: .leading, spacing: 18) {
                HomeHeader(name: family.view?.people.first(where: \.isSelf)?.name,
                           line: HomeHeader.line(view: access.current.family ? family.view : nil, tasksToDo: nil))
                cards
            }
            .padding(.horizontal, SR.gutter)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .srGround(.warm)
        // Pinned under the bar, not scrolled with the page: something urgent
        // stays in view until it is opened or waved away.
        .safeAreaInset(edge: .top, spacing: 0) {
            if access.current.owner, let urgent = TodayAlerts.urgent(in: alerts.forToday, dismissed: waved) {
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
        .navigationTitle("Home")
        // Trips push onto Today's own stack: no tab of their own.
        .tripDestinations()
        .navigationDestination(for: HomeCustomizeRef.self) { _ in HomeCustomizeScreen() }
        // Inline, and the title itself is replaced by the `sr.` mark. There is
        // no headline on the page either: see `SRPageHeader` for why a large
        // title is not an option on this OS with a custom face, and the body
        // above for why the page does not need one.
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable {
            rings.start()
            await family.load()
            await loadFamilyBoards()
            await store.load(fresh: true)
            daydream.seed(store.payload?.daydream)
            await alerts.refresh()
            await connections.refresh()
            if companion.paired { await companion.sync() }
            if access.current.owner || access.current.family { await TripStore.shared.refresh() }
        }
        .srTabBar()
        .toolbar {
            // The bell is the site's inbox, which is the owner's.
            if access.current.owner {
                ToolbarItem(placement: .topBarTrailing) {
                    TodayBell(unread: alerts.unread, active: onScreen && scenePhase == .active) {
                        SRHaptic.tap()
                        router.openAlerts()
                    }
                }
            }
            // Settings are in the hub (⊞), for everyone.
        }
        .task {
            // The Watch's health figures and Today's first alerts come from
            // this store's payload — no second request.
            WatchBridge.shared.attach(today: store)
            rings.start()
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
                rings.start()
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
            rings.start()
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
        // Health uploads only: location points upload every thirty seconds
        // while moving, and re-reading the whole day past the cache on each
        // one kept the radio busy for nothing. And at most once in five
        // minutes, for a backfill that lands batch after batch.
        .onReceive(companion.$lastHealthUpload.removeDuplicates().dropFirst()) { _ in
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

    /// The morning report is the owner's, over the site — not drawn for a
    /// member, nor while the owner is viewing the app as one.
    private var ownsReport: Bool { access.current.owner && site.paired }

    /// What Home draws, in order.
    private var visibleTiles: [HomeTileKind] {
        HomeLayout.decode(homeLayout).visible(HomeTileKind.available(access: access.current, sitePaired: site.paired))
    }

    /// Everything under the greeting.
    @ViewBuilder
    private var cards: some View {
        if access.current.owner && !site.paired {
            // The owner's QR. A member's phone pairs itself, and a
            // member with neither chat nor news has nothing to pair.
            connectCard
        } else if !(companionPaired ?? companion.paired) && !access.current.owner {
            // Nobody knows who this is yet: the companion is where that
            // answer comes from.
            companionCard
        }
        HomeGrid(kinds: visibleTiles, briefingReport: ownsReport) { kind in
            tile(kind)
        }
        .environment(\.homeColours, { router.openColours() })
        // Side by side, or stacked once the type is too big for two labels.
        let footer = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        footer {
            Button {
                SRHaptic.tap()
                router.today.append(HomeCustomizeRef())
            } label: {
                // "Arrange", not "Arrange Home": half the width in capitals
                // cut it to "ARRANGE H…".
                SRButtonLabel(title: "Arrange", icon: "slider.horizontal.3", fill: true)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("home-customise")
            Button {
                SRHaptic.tap()
                router.openColours()
            } label: {
                SRButtonLabel(title: "Colours", icon: "paintpalette.fill", fill: true)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("home-colours")
        }
        .padding(.top, 4)
    }

    /// The boards behind whichever tiles are on. Nothing is read for a tile
    /// that is off — except what the briefing ranks, which reads the same
    /// boards whether or not their tiles are shown.
    private func loadFamilyBoards() async {
        let shown = Set(visibleTiles)
        let briefing = shown.contains(.briefing)
        if shown.contains(.flows) || (briefing && access.current.owner) { await flowAttention.load() }
        guard access.familyBoards else { return }
        if shown.contains(.steps) || briefing { await FamilyStepsStore.shared.load() }
        if shown.contains(.tasks) || briefing { await FamilyTasksStore.shared.load() }
        if shown.contains(.backlog) { await FamilyBacklogStore.shared.load() }
        if shown.contains(.messages) || briefing { await FamilyMessagesStore.shared.load() }
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
                Text("Pair with your own code from strangeramblings.com/welcome. One code connects health, location, chat and news, as you.")
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
                Text("Pair with your code from strangeramblings.com/welcome to read your threads, the news desk and your health figures here.")
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
    private func tile(_ kind: HomeTileKind) -> some View {
        let hide = { withAnimation(.snappy) { var next = HomeLayout.decode(homeLayout); next.set(kind, shown: false); homeLayout = next.raw } }
        let arrange = { router.today.append(HomeCustomizeRef()) }
        switch kind {
        case .briefing:
            let report: (() -> Void)? = ownsReport ? { router.openMorningReport() } : nil
            HomeBriefingTile(health: store.payload?.health, rings: rings.rings, news: store.payload?.news,
                             household: access.current.family ? family.view : nil, flows: flowAttention,
                             open: openInsight, hide: hide, customise: arrange,
                             report: report)
        case .family:
            HomeTileButton(kind: kind, id: "today-family", action: { router.show(.family) }, hide: hide, customise: arrange, keepsChildren: true) {
                HomeFamilyTile(store: family, watch: family.view?.watch, live: onScreen && scenePhase == .active)
            }
        case .familyDay:
            HomeTileButton(kind: kind, id: "home-family-day", action: { router.show(.family) }, hide: hide, customise: arrange) {
                HomeFamilyDayTile(store: family, watch: family.view?.watch)
            }
        case .health:
            // The owner's figures are each a button into their own chart, so
            // the tile keeps its children; a member's is one button.
            let figures = access.current.owner && site.paired
            let openFigure: ((HealthFigure) -> Void)? = figures ? { router.openHealthFigure($0) } : nil
            HomeTileButton(kind: kind, id: "today-health", action: { router.show(.health) }, hide: hide, customise: arrange,
                           keepsChildren: figures) {
                HomeHealthTile(health: store.payload?.health, rings: rings.rings, showsReadiness: figures, openFigure: openFigure)
            }
        case .steps:
            HomeTileButton(kind: kind, id: "today-steps", action: { router.openFamilyPage(.steps) }, hide: hide, customise: arrange) {
                HomeStepsTile()
            }
        case .tasks:
            HomeTileButton(kind: kind, id: "today-tasks", action: { router.openFamilyPage(.tasks) }, hide: hide, customise: arrange) {
                HomeTasksTile()
            }
        case .trips:
            HomeTripsTile(hide: hide, customise: arrange) { target in
                switch target {
                case .day(let day): router.openTrips(day: day)
                case .list: router.openTrips()
                case .plan: router.openTrips(start: true)
                case .questions(let trip, let question): router.openTrip(TripLink(tripId: trip, date: nil, questionId: question))
                }
            }
        case .moves:
            HomeTileButton(kind: kind, id: "home-moves", action: { router.show(.family) }, hide: hide, customise: arrange) {
                HomeMovesTile(colours: SR.PersonHue.assign((family.view?.people ?? []).map(\.subject)),
                              initials: family.view?.initials ?? [:])
            }
        case .messages:
            HomeTileButton(kind: kind, id: "home-messages", action: { router.openFamilyPage(.messages) }, hide: hide, customise: arrange) {
                HomeMessagesTile()
            }
        case .backlog:
            HomeTileButton(kind: kind, id: "today-backlog", action: { router.openFamilyPage(.backlog) }, hide: hide, customise: arrange) {
                HomeBacklogTile()
            }
        case .games:
            HomeTileButton(kind: kind, id: "today-games", action: { router.show(.games) }, hide: hide, customise: arrange) {
                HomeGamesTile()
            }
        case .chat:
            HomeTileButton(kind: kind, id: "today-ask", action: { router.show(.chat) }, hide: hide, customise: arrange) {
                HomeShortcutTile(kind: kind, line: store.payload?.lastThread?.title.map { "Last: \($0)" } ?? "Ask anything, any time")
            }
        case .news:
            HomeTileButton(kind: kind, id: "home-news", action: { router.show(.news) }, hide: hide, customise: arrange) {
                HomeNewsTile(news: store.payload?.news)
            }
        case .daydream:
            HomeTileButton(kind: kind, id: "today-daydream", action: { router.openDaydream() }, hide: hide, customise: arrange) {
                HomeDaydreamTile()
            }
        case .flows:
            HomeTileButton(kind: kind, id: "home-flows", action: { router.show(.flows) }, hide: hide, customise: arrange) {
                HomeFlowsTile(store: flowAttention)
            }
        case .wildmind:
            HomeTileButton(kind: kind, id: "home-wildmind", action: { router.openWildmind() }, hide: hide, customise: arrange) {
                HomeShortcutTile(kind: kind, line: "The world it is building")
            }
        }
    }

    /// A briefing line tapped: the place it came from, as near the figure as
    /// the app goes — a health figure opens its own chart.
    private func openInsight(_ line: HomeInsight) {
        switch line.source {
        case .watch, .moves, .diary: router.show(.family)
        case .trip:
            if let running = TripStore.shared.running() {
                router.openTrips(day: TripDayRef(tripId: running.bundle.trip.id, date: running.date))
            } else {
                router.openTrips()
            }
        case .tasks: router.openFamilyPage(.tasks)
        case .steps: router.openFamilyPage(.steps)
        case .messages: router.openFamilyPage(.messages)
        case .vitals:
            if let key = line.figureKey, let figure = store.payload?.health?.figures.first(where: { $0.key == key }) {
                router.openHealthFigure(figure)
            } else {
                router.show(.health)
            }
        case .readiness, .rings: router.show(.health)
        case .flows: router.show(.flows)
        case .games: router.show(.games)
        case .daydream: router.openDaydream()
        case .news: router.show(.news)
        case .calm: break
        }
    }
}

/// "Arrange Home", pushed onto Home's own stack.
struct HomeCustomizeRef: Hashable {}
