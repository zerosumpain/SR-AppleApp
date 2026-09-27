import SwiftUI
import UIKit
import CoreSpotlight

/// Where the app goes, held outside the views that navigate.
///
/// A `NavigationPath` owned by a screen is reset every time that screen is torn
/// down — which a `TabView` does freely — and there is no way for a Shortcut, a
/// notification or a Home Screen quick action to push anything onto it. Holding
/// the paths here makes "open this thread" a value somebody outside SwiftUI can
/// write, which is what every one of those entry points needs.
@MainActor
final class Router: ObservableObject {
    enum Tab: String, Hashable { case today, chat, health, family, games, news, flows, more }

    @Published var tab: Tab = .today
    @Published var chat = NavigationPath()
    @Published var health = NavigationPath()
    @Published var family = NavigationPath()
    @Published var games = NavigationPath()
    @Published var news = NavigationPath()
    @Published var flows = NavigationPath()
    /// The app's own More tab: its first entry is the place opened from the
    /// hub (a `Tab`), and that place's own pushes follow it on the same stack.
    @Published var more = NavigationPath()
    /// The one modal, whichever it currently is.
    ///
    /// NOT two `.sheet(isPresented:)` modifiers on the same view. SwiftUI
    /// honours one sheet per view: attach a second and whichever is asked for
    /// first silently does nothing. Settings and the alert inbox are both
    /// opened from several places, so that failure would have been
    /// intermittent and impossible to reproduce on demand.
    @Published var sheet: Sheet?
    /// Which settings group to open on, when something sent the reader there
    /// for a reason.
    @Published var settingsTarget: SettingsTarget?
    /// A question handed in from outside — a Shortcut, Siri, a quick action.
    @Published var pendingQuestion: String?
    /// Files handed in from another app — "Open in SR" on a Share sheet.
    @Published var pendingFiles: [URL] = []

    enum Sheet: String, Identifiable { case settings, alerts, connections; var id: String { rawValue } }
    /// Pages that live only inside More — not places with a tab of their own.
    enum MorePage: String, Hashable { case daydream }
    enum SettingsTarget: String, Hashable { case notifications, connections, health, location }

    func openSettings(_ target: SettingsTarget? = nil) {
        // Where alerts go is the owner's site inbox; nobody else has a
        // Notifications screen to be sent to.
        settingsTarget = target == .notifications && !AccessStore.shared.current.owner ? nil : target
        sheet = .settings
    }

    /// The site's alert inbox — the owner's alone.
    func openAlerts() {
        guard AccessStore.shared.current.owner else { return }
        sheet = .alerts
    }

    /// The daydream loop's notes, a page in More — the owner's alone. More
    /// is always on an owner's bar (seven places, five slots), so there is
    /// always a stack to push it onto.
    func openDaydream() {
        guard AccessStore.shared.current.owner, AccessStore.shared.allows(.more) else { return }
        var path = NavigationPath()
        path.append(MorePage.daydream)
        more = path
        tab = .more
    }

    /// Every site connection that needs the owner — the banner's chevron, and
    /// a tapped "connections" notification.
    func openConnections() {
        guard AccessStore.shared.current.owner else { return }
        sheet = .connections
    }

    /// Go to a tab and clear whatever was stacked on it.
    ///
    /// Clearing matters: an intent that opens Chat while a thread is already
    /// pushed would otherwise land on that thread, which is not what "open
    /// chat" means to the person who said it.
    ///
    /// A tab this person may not open does not exist, so whatever asked for it
    /// — a stale quick action, an old notification, a Shortcut — lands on
    /// Today instead.
    func show(_ tab: Tab) {
        guard AccessStore.shared.allows(tab) else {
            self.tab = .today
            return
        }
        // A place inside More opens as More with that place pushed, so its
        // back button leads to the hub and the bar stays where it was.
        if inMore(tab) {
            var path = NavigationPath()
            path.append(tab)
            more = path
            self.tab = .more
            return
        }
        switch tab {
        case .chat: chat = NavigationPath()
        case .health: health = NavigationPath()
        case .family: family = NavigationPath()
        case .games: games = NavigationPath()
        case .news: news = NavigationPath()
        case .flows: flows = NavigationPath()
        case .more: more = NavigationPath()
        case .today: break
        }
        self.tab = tab
    }

    /// Whether `tab` lives inside More for this person rather than on the bar.
    func inMore(_ tab: Tab) -> Bool { AccessStore.shared.inMore.contains(tab) }

    /// Push onto a place's stack, wherever that place is on the bar — its own
    /// tab, or inside More behind the hub. Games, News and Flows push through
    /// this rather than onto `games`/`news`/`flows` directly.
    func push<Value: Hashable>(_ value: Value, on tab: Tab) {
        if inMore(tab) { more.append(value); return }
        switch tab {
        case .chat: chat.append(value)
        case .health: health.append(value)
        case .family: family.append(value)
        case .games: games.append(value)
        case .news: news.append(value)
        case .flows: flows.append(value)
        case .more: more.append(value)
        case .today: break
        }
    }

    /// Pop the top of a place's stack, never past the place itself — inside
    /// More the bottom entry is the place, and popping it would land on the hub.
    func pop(on tab: Tab) {
        if inMore(tab) {
            if more.count > 1 { more.removeLast() }
            return
        }
        switch tab {
        case .chat: if !chat.isEmpty { chat.removeLast() }
        case .health: if !health.isEmpty { health.removeLast() }
        case .family: if !family.isEmpty { family.removeLast() }
        case .games: if !games.isEmpty { games.removeLast() }
        case .news: if !news.isEmpty { news.removeLast() }
        case .flows: if !flows.isEmpty { flows.removeLast() }
        case .more: if !more.isEmpty { more.removeLast() }
        case .today: break
        }
    }

    /// Open one game room — a tapped invite notification. Lands on Games
    /// with the room pushed; somebody without games lands on Today.
    /// `game` picks the room's screen at once; without it the room is read
    /// first to find out.
    func openGame(_ roomId: String, game: String? = nil) {
        show(.games)
        guard AccessStore.shared.allows(.games) else { return }
        push(GameRoomRef(id: roomId, game: game), on: .games)
    }

    func ask(_ question: String) {
        guard AccessStore.shared.allows(.chat) else { show(.today); return }
        pendingQuestion = question
        show(.chat)
    }

    func share(_ files: [URL]) {
        guard AccessStore.shared.allows(.chat) else { show(.today); return }
        pendingFiles = files
        show(.chat)
    }
}

/// The app.
///
/// Four tabs, and the fourth used to be `Connect` — a QR scanner, permanently
/// on the tab bar, for a job you do once. That is the clearest example of what
/// this overhaul is about: the tab bar is the app's table of contents and every
/// slot in it should be somewhere you go back to. Pairing is setup, so it lives
/// under the gear with the other setup.
///
/// What replaced it is `Today`: the figures, the alerts and the headline on one
/// screen, which is the thing a phone is actually opened for.
///
/// The whole app is light-locked. That is not laziness about dark mode: the site
/// has no dark mode. Its palette is one warm cream ground with ink type, and the
/// ink is chrome — a bar, a footer, one ledger. Inverting it would not be the
/// same design with different values, it would be a different design. CI runs the
/// simulator in DARK appearance deliberately, so a regression here shows up as a
/// screenshot rather than as a surprise on somebody's phone.
struct ContentView: View {
    @ObservedObject var companion: Companion
    @ObservedObject var outbox: Outbox
    @ObservedObject var location: LocationCollector
    @ObservedObject var battery: BatteryMonitor
    @StateObject private var site = SitePairingModel()
    @StateObject private var router = Router()
    @StateObject private var alerts = AlertStore()
    @StateObject private var connections: ConnectionsStore
    /// One household view for the Today mini-map and the Family tab, so the
    /// tab opens on the picture it was opened from.
    @StateObject private var family: FamilyStore
    /// The Games tab's lobby, held here because its invite poll runs whichever
    /// tab is open — see `syncGamesPoll`.
    @StateObject private var games = GamesStore()
    /// What this person may use. Every tab below, and most of what is in them,
    /// is built from it — see `AccessPolicy`.
    @ObservedObject private var access = AccessStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init(companion: Companion, outbox: Outbox, location: LocationCollector, battery: BatteryMonitor) {
        self.companion = companion
        self.outbox = outbox
        self.location = location
        self.battery = battery
        // Seeded from the state file, so a lapsed connection is on screen from
        // the first frame rather than after the first request.
        _connections = StateObject(wrappedValue: ConnectionsStore(outbox: outbox))
        _family = StateObject(wrappedValue: FamilyStore(companion: companion))
    }

    var body: some View {
        TabView(selection: tabBinding) {
            NavigationStack {
                TodayScreen(companion: companion, alerts: alerts, site: site, family: family)
                    .srConnectionsBanner(connections) { router.openConnections() }
            }
            .tabItem { SRTabIcon.label("Today", "square.grid.2x2") }
            .tag(Router.Tab.today)

            // Only the tabs this person may open are BUILT: a feature somebody
            // lacks is not a greyed-out tab or an explanation, it is not there.
            //
            // Where everyone is, straight after Today, which leads with it. Over
            // the COMPANION pairing, which every phone in the family has — so,
            // unlike Chat or News, not behind `paired`. The bar's order is
            // `AccessPolicy.tabs`; this follows it.
            if access.allows(.family) {
                NavigationStack(path: $router.family) {
                    FamilyScreen(store: family, companion: companion)
                        .srConnectionsBanner(connections) { router.openConnections() }
                }
                .tabItem { SRTabIcon.label("Family", "person.2.wave.2") }
                .tag(Router.Tab.family)
            }

            // Games, News and Flows: each its own tab while the bar has room,
            // otherwise all three behind our own More (see `AccessPolicy.inMore`).
            // Games straight after Family, so a member given both sees them together.
            if access.allows(.games) && !router.inMore(.games) {
                NavigationStack(path: $router.games) {
                    place(.games).placeDestinations()
                }
                .tabItem { SRTabIcon.label("Games", "gamecontroller") }
                .badge(games.invites.count)
                .tag(Router.Tab.games)
            }

            if access.allows(.chat) {
                NavigationStack(path: $router.chat) {
                    paired(what: "your threads") { ThreadListScreen() }
                        .srConnectionsBanner(connections) { router.openConnections() }
                }
                .tabItem { SRTabIcon.label("Chat", "bubble.left.and.bubble.right") }
                .tag(Router.Tab.chat)
            }

            NavigationStack(path: $router.health) {
                HealthScreen(companion: companion)
                    .srConnectionsBanner(connections) { router.openConnections() }
            }
            .tabItem { SRTabIcon.label("Health", "heart.text.square") }
            .tag(Router.Tab.health)

            if access.allows(.news) && !router.inMore(.news) {
                NavigationStack(path: $router.news) {
                    place(.news).placeDestinations()
                }
                .tabItem { SRTabIcon.label("News", "newspaper") }
                .tag(Router.Tab.news)
            }

            if access.allows(.flows) && !router.inMore(.flows) {
                NavigationStack(path: $router.flows) {
                    place(.flows).placeDestinations()
                }
                .tabItem { SRTabIcon.label("Flows", "point.3.connected.trianglepath.dotted") }
                .tag(Router.Tab.flows)
            }

            // One stack for the hub and whatever it opens, so a game has one
            // bar and one back button, and popping it lands on a screen that
            // has a tab bar — neither was true of iOS's own More.
            if access.allows(.more) {
                NavigationStack(path: $router.more) {
                    MoreScreen(places: access.inMore, games: games)
                        .srConnectionsBanner(connections) { router.openConnections() }
                        .navigationDestination(for: Router.Tab.self) { place($0) }
                        .navigationDestination(for: Router.MorePage.self) { page in
                            switch page {
                            case .daydream: DaydreamScreen()
                            }
                        }
                        .placeDestinations()
                }
                .tabItem { SRTabIcon.label("More", "square.grid.3x3.square") }
                .badge(games.invites.count)
                .tag(Router.Tab.more)
            }
        }
        // The deeper accent: the selected tab's label is 10-point text on
        // glass, where `SR.accent` measures 3.5:1 and this holds 4.8:1.
        .tint(SR.accentDeep)
        // Viewing the app as somebody else: said on every screen, with the way
        // back one tap away, so a look never passes for the real thing.
        .overlay(alignment: .bottom) {
            if let preview = access.viewingAs {
                ViewingAsBanner(name: preview.name) {
                    SRHaptic.select()
                    access.view(as: nil)
                }
                .padding(.bottom, 64)
            }
        }
        // On iOS 26 the glass tab bar shrinks to a pill while you read and
        // comes back when you scroll up — the content gets the screen.
        .srTabBarMinimizes()
        .preferredColorScheme(.light)
        .environmentObject(router)
        .environmentObject(alerts)
        .environmentObject(connections)
        .environmentObject(access)
        // The lobby's "ask more people" reads the family roster from here.
        .environmentObject(games)
        // An install paired before the household question existed is asked
        // once, here. A phone pairing now is asked by the Connections screen.
        .srSharingQuestion(companion: companion, onPairing: false)
        .task {
            // Anything a quick action, a notification tap or a Shortcut left
            // waiting before there was a router to receive it.
            drainPending()
            // The Watch mirrors this inbox and these connections, not a
            // transient store's empty ones.
            WatchBridge.shared.attach(alerts: alerts, connections: connections)
            connections.runLocalFix = { [companion = self.companion, router = self.router] fix in
                switch fix {
                case .syncNow: Task { await companion.sync() }
                case .healthPermissions: router.openSettings(.health)
                }
            }
            checkPersonal()
            syncGamesPoll()
            await site.check()
            await reconcileSite()
            await alerts.refresh()
            await connections.refresh()
        }
        // This phone's own health link, re-judged whenever what it is judged
        // on moves. Everyone's, owner or member — see `PersonalHealthCheck`.
        .onChange(of: companion.lastUpload) { _, _ in checkPersonal() }
        .onChange(of: companion.healthReviewNeeded) { _, _ in checkPersonal() }
        .onChange(of: companion.paired) { _, _ in checkPersonal() }
        .onChange(of: scenePhase) { _, phase in
            // The invite poll is a foreground thing: it stops the moment the
            // scene leaves, and nothing claims it runs when the app is shut.
            syncGamesPoll()
            guard phase == .active else { return }
            // A quick action taken while the app was merely backgrounded never
            // goes through `task`, which runs once per view lifetime.
            drainPending()
            checkPersonal()
            Task {
                await alerts.refresh()
                // Back from Safari after pressing Fix is the commonest way in
                // here, and the banner should go the moment the site agrees.
                await connections.refresh()
            }
        }
        // Disconnecting the site clears its connections; connecting fetches them.
        .onChange(of: site.paired) { _, _ in
            syncGamesPoll()
            Task {
                await reconcileSite()
                await connections.refresh()
            }
        }
        // The site changed its mind about this person, or sent the pairing
        // code a member's phone asked for.
        .onChange(of: access.current) { _, _ in
            // Also when a place moved between the bar and More: its old tab is gone.
            if !access.allows(router.tab) || router.inMore(router.tab) { router.tab = .today }
            syncGamesPoll()
            Task { await reconcileSite() }
        }
        // "View as" changed: the family is theirs now, or yours again.
        .onChange(of: access.viewingAs) { _, _ in
            family.applyViewingAs()
        }
        .onChange(of: access.offer) { _, _ in
            Task { await reconcileSite() }
        }
        // A thread opened from Spotlight. The index carries the conversation id
        // as the item identifier, so this is a push rather than a search.
        // A photo or document sent here from another app's Share sheet. The
        // system copies it into this app's Inbox and hands over a file URL.
        //
        // Not a share EXTENSION, which would be the richer version (web pages,
        // text, a compose sheet without leaving the other app): an extension is
        // a second target with its own bundle id and provisioning profile, and
        // this app has exactly one — see the signing notes. A document type
        // lives in the app target and needs nothing new from the portal.
        //
        // The document types are in Info.plist and cannot change per person,
        // so "Open in SR" stays on the Share sheet for everyone; somebody
        // without chat has nowhere for a file to go, and it is dropped —
        // including the copy iOS put in Inbox.
        .onOpenURL { url in
            guard url.isFileURL else { return }
            guard access.allows(.chat) else {
                if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
                return
            }
            router.share([url])
        }
        // A notification tapped while the app is already open — a game invite
        // banner, most often. No scene-phase change comes with that, so
        // nothing else would drain what the delegate left waiting.
        .onReceive(NotificationCenter.default.publisher(for: PendingEntry.changed)) { _ in
            drainPending()
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard access.allows(.chat),
                  let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
            router.show(.chat)
            router.chat.append(ThreadReference(id: id))
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .settings:
                SettingsScreen(
                    outbox: outbox,
                    companion: companion,
                    location: location,
                    battery: battery,
                    site: site,
                    alerts: alerts,
                    connections: connections,
                    target: router.settingsTarget
                )
            case .alerts:
                NavigationStack { AlertsScreen(alerts: alerts) }
            case .connections:
                ConnectionsSheet(store: connections)
            }
        }
    }

    private func checkPersonal() {
        connections.setPersonal(PersonalHealthCheck.items(
            paired: companion.paired,
            healthEnabled: !outbox.state.healthEnabled.isEmpty,
            reviewNeeded: companion.healthReviewNeeded,
            lastUpload: companion.lastUpload
        ))
    }

    /// Run the Games invite poll exactly while it can be useful: the scene is
    /// active, this person may play, and the site credential exists.
    private func syncGamesPoll() {
        games.setPolling(scenePhase == .active && access.allows(.games) && site.paired)
    }

    private func drainPending() {
        // The router refuses anything this person may not reach — a question
        // without chat, a hidden tab, the owner's inbox — so a stale entry
        // lands on Today rather than on a screen that is not there.
        AppDelegate.pending.drain(into: router, companion: companion)
        if AppDelegate.pending.openAlerts {
            AppDelegate.pending.openAlerts = false
            router.openAlerts()
        }
        if AppDelegate.pending.openConnections {
            AppDelegate.pending.openConnections = false
            router.openConnections()
        }
    }

    /// Bring the site credential into line with what this person may use.
    ///
    /// A member entitled to chat, news or games is paired automatically, with the
    /// one-time code SR-Main put in their view after the phone asked
    /// (`Companion.adoptAccess`); through `site` so `site.paired` — and every
    /// tab watching it — updates. A member who has lost both is signed out so
    /// nothing lingers, and without chat the thread titles leave Spotlight.
    /// (Games counts as a lane: its rooms are on the site too.)
    /// An owner is never touched: the QR flow is theirs.
    private func reconcileSite() async {
        UIApplication.shared.shortcutItems = AccessPolicy.quickActions(for: access.current).map { $0.item }
        #if DEBUG
        // Demo mode's credential is pretend and its access fixed.
        if SRDemo.isOn { return }
        #endif
        access.siteChanged(paired: site.paired)
        // Not while viewing as somebody: that is a look, and the Spotlight
        // index is the owner's own.
        if !access.current.chat && access.viewingAs == nil { ThreadIndex.clear() }
        if AccessPolicy.signsOutSite(known: access.known, sitePaired: site.paired, siteRole: access.siteRole) {
            site.signOut()
            access.siteChanged(paired: false)
            return
        }
        guard AccessPolicy.wantsSitePair(known: access.known, sitePaired: site.paired),
              !site.busy, let offer = access.takeOffer() else { return }
        await site.pair(offer.pairing)
        access.siteChanged(paired: site.paired)
        if site.paired { await companion.confirmSitePaired() }
    }

    /// `TabView`'s selection, with a haptic on the change.
    ///
    /// Not `.onChange(of: router.tab)` — that fires for a programmatic change
    /// too, so a Shortcut that opens Health would buzz the phone from a locked
    /// pocket. Only a tap goes through the binding's setter.
    private var tabBinding: Binding<Router.Tab> {
        Binding(
            get: { router.tab },
            set: { next in
                if next != router.tab { SRHaptic.select() }
                router.tab = next
            }
        )
    }

    /// Games, News or Flows — the same screen whether it is a tab of its own
    /// or opened from More.
    @ViewBuilder
    private func place(_ tab: Router.Tab) -> some View {
        switch tab {
        case .games:
            // Its rooms live on the site, hence `paired` — a games-only
            // member's phone pairs itself for it.
            paired(what: "family games") { GamesScreen(store: games) }
                .srConnectionsBanner(connections) { router.openConnections() }
        case .news:
            paired(what: "the news desk") { NewsScreen() }
                .srConnectionsBanner(connections) { router.openConnections() }
        case .flows:
            // The site's workflows: list, run, pause, edit a step, ask jkai to
            // change one. The owner's alone.
            paired(what: "your workflows") { FlowsScreen() }
                .srConnectionsBanner(connections) { router.openConnections() }
        default:
            EmptyView()
        }
    }

    /// A tab that needs the site credential, or the one screen that explains
    /// why it does not have it.
    ///
    /// A member is never sent to the QR scanner — their phone pairs itself
    /// (`reconcileSite`), so the screen says so and offers nothing to press.
    @ViewBuilder
    private func paired<Content: View>(what: String, @ViewBuilder content: () -> Content) -> some View {
        if site.paired {
            content()
        } else if !access.current.owner {
            SREmpty(
                title: "Connecting",
                icon: "arrow.triangle.2.circlepath",
                message: "This iPhone is being connected to Strange Ramblings for \(what). It happens by itself — nothing to scan."
            )
            .frame(maxHeight: .infinity)
            .srPaper()
            .navigationTitle(what.capitalized)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            SREmpty(
                title: "Not connected yet",
                icon: "qrcode.viewfinder",
                message: "Connect this iPhone to Strange Ramblings to read \(what).",
                actionLabel: "Connect",
                action: { router.openSettings(.connections) }
            )
            .frame(maxHeight: .infinity)
            .srPaper()
            .navigationTitle(what.capitalized)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension View {
    /// Where Games, News and Flows push to, registered on the ROOT of whichever
    /// stack holds them. On the root rather than on each screen: inside More the
    /// screen is itself pushed, and a notification that opens a game sets the
    /// hub-then-room path in one go — the room's destination must already exist.
    func placeDestinations() -> some View {
        self
            .navigationDestination(for: GameRoomRef.self) { GameRoomScreen(ref: $0).id($0.id) }
            .navigationDestination(for: NewsStory.self) { NewsStoryScreen(story: $0) }
            .navigationDestination(for: FlowRef.self) { FlowDetailScreen(ref: $0).id($0.slug) }
            .navigationDestination(for: FlowRunRef.self) { FlowRunScreen(ref: $0).id($0.runId) }
    }

    @ViewBuilder
    func srTabBarMinimizes() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
