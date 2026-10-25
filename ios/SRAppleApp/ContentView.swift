import SwiftUI
import UIKit
import CoreSpotlight
import Combine

/// Where the app goes, held outside the views that navigate.
///
/// A `NavigationPath` owned by a screen is reset every time that screen is torn
/// down — which a `TabView` does freely — and there is no way for a Shortcut, a
/// notification or a Home Screen quick action to push anything onto it. Holding
/// the paths here makes "open this thread" a value somebody outside SwiftUI can
/// write, which is what every one of those entry points needs.
@MainActor
final class Router: ObservableObject {
    enum Tab: String, Hashable { case today, chat, health, family, games, news, flows }

    @Published var tab: Tab = .today
    /// Today's own stack: Trips push onto it (no tab of their own).
    @Published var today = NavigationPath()
    @Published var chat = NavigationPath()
    @Published var health = NavigationPath()
    @Published var family = NavigationPath()
    @Published var games = NavigationPath()
    @Published var news = NavigationPath()
    @Published var flows = NavigationPath()
    /// The tab whose stack the hub was last opened on. The hub is not a tab:
    /// it is pushed onto whichever tab you are on (`openHub`), and what it
    /// opens — News, Flows, Daydream, Steps — is pushed above it on the same
    /// stack, so there is one bar, one back button and the tab bar stays.
    @Published private(set) var hubHost: Tab = .today
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

    /// What the What's new sheet shows, fixed when it is opened: the sheet
    /// marks them seen as it appears, and must not empty itself as it does.
    @Published var whatsNew: [WhatsNewRelease] = []
    @Published var whatsNewHistory = false

    enum Sheet: String, Identifiable { case settings, alerts, connections, colours, whatsNew; var id: String { rawValue } }
    /// Pages that live only inside More — not places with a tab of their own.
    /// Wildmind, like Daydream, is the owner's.
    enum MorePage: String, Hashable { case daydream, wildmind }
    enum SettingsTarget: String, Hashable { case notifications, connections, health, location, hold }

    /// The palette sheet. A sheet, not a pushed page, so the app behind it
    /// can redraw in the new colours while the reader is still choosing.
    func openColours() {
        sheet = .colours
    }

    /// After an update: what changed, once. Only into an empty slot — a
    /// notification tap's sheet came first and keeps it; the notes wait — and
    /// only in front of somebody: a background relaunch builds the window too.
    /// Asked on every return to the foreground, so notes that lost the race
    /// to another modal are shown next time rather than next cold start.
    func offerWhatsNew(owner: Bool) {
        guard sheet == nil, UIApplication.shared.applicationState == .active else { return }
        let releases = WhatsNew.pending(owner: owner)
        guard !releases.isEmpty else { return }
        whatsNew = releases
        whatsNewHistory = false
        sheet = .whatsNew
    }

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

    /// The daydream loop's notes, a page in the hub — the owner's alone.
    /// Opened from outside (a notification, a commission) it lands on Home
    /// with the hub beneath it, so Back walks to the hub and then Home.
    func openDaydream() {
        guard AccessStore.shared.current.owner else { return }
        openFromHub(MorePage.daydream)
    }

    /// Wildmind, a page in the hub — the owner's alone, like Daydream.
    func openWildmind() {
        guard AccessStore.shared.current.owner else { return }
        openFromHub(MorePage.wildmind)
    }

    /// The hub, pushed onto the tab that is open: the ⊞ in every page's bar.
    func openHub() {
        hubHost = tab
        append(HubRef(), to: tab)
    }

    /// Something the hub holds, opened from outside the app's screens: Home's
    /// stack becomes hub-then-it, and Home is shown.
    private func openFromHub<Value: Hashable>(_ value: Value) {
        var path = NavigationPath()
        path.append(HubRef())
        path.append(value)
        today = path
        hubHost = .today
        tab = .today
    }

    /// The step board or the task list — a tapped push, a widget, a link.
    /// Pushed onto the Family tab, which everyone with the boards has.
    /// Somebody without them — no family, or no site credential — lands on Today.
    ///
    /// `thread`: a msg family message to open above the list — a tapped
    /// message or reply notification lands in its thread.
    func openFamilyPage(_ page: FamilyPage, thread: String? = nil) {
        let access = AccessStore.shared
        guard access.familyBoards else { show(.today); return }
        var path = NavigationPath()
        path.append(page)
        if page == .messages, let thread { path.append(FamilyThreadRef(id: thread)) }
        // "msg family" lives beside jkai in Chat, for whoever has Chat.
        if page == .messages, access.allows(.chat) {
            chat = path
            tab = .chat
            return
        }
        if access.allows(.family) {
            family = path
            tab = .family
        } else {
            show(.today)
        }
    }

    /// A trip day, or the list — from Today's trip card, and from a trip
    /// notification. Pushed onto Today's own stack.
    ///
    /// A day lands with the list and its trip stacked beneath it, so Back
    /// walks day → trip → all trips. Pushing the day alone sent Back straight
    /// to Today, and there was no way into the trips list while a trip ran.
    ///
    /// `start`: straight into "New trip" — Today's "Plan a trip", for someone
    /// with no trips yet, who otherwise had no way in at all.
    func openTrips(day: TripDayRef? = nil, start: Bool = false) {
        var path = NavigationPath()
        path.append(TripsListRef(start: start && day == nil))
        if let day {
            path.append(TripRef(tripId: day.tripId))
            path.append(day)
        }
        today = path
        tab = .today
    }

    /// A tapped trip alert, the Lock Screen card, or an `sr://trips` link:
    /// the day it names — or, naming none, the day running now — else the
    /// trip, else the list. Before this a trip alert fell through to the
    /// alerts inbox, which never holds one.
    func openTrip(_ link: TripLink) {
        let access = AccessStore.shared.current
        guard access.owner || access.family else { show(.today); return }
        guard let id = link.tripId else { openTrips(); return }
        // v8: a question — the trip's planning home, scrolled to it, even
        // while the trip runs (the day screen holds no questions).
        if let question = link.questionId {
            TripQuestionFocus.shared.request(tripId: id, questionId: question)
            var path = NavigationPath()
            path.append(TripsListRef())
            path.append(TripRef(tripId: id))
            today = path
            tab = .today
            return
        }
        let running = TripStore.shared.running().flatMap { $0.bundle.trip.id == id ? $0.date : nil }
        if let date = link.date ?? running {
            openTrips(day: TripDayRef(tripId: id, date: date))
            return
        }
        var path = NavigationPath()
        path.append(TripsListRef())
        path.append(TripRef(tripId: id))
        today = path
        tab = .today
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
        // A place in the hub (News, Flows) opens on Home with the hub
        // beneath it, so its back button leads to the hub.
        if inHub(tab) {
            openFromHub(tab)
            return
        }
        switch tab {
        case .chat: chat = NavigationPath()
        case .health: health = NavigationPath()
        case .family: family = NavigationPath()
        case .games: games = NavigationPath()
        case .news: news = NavigationPath()
        case .flows: flows = NavigationPath()
        case .today: break
        }
        self.tab = tab
    }

    /// Whether `tab` lives in the hub for this person rather than on the bar.
    func inHub(_ tab: Tab) -> Bool { AccessStore.shared.inHub.contains(tab) }

    /// Push onto a place's stack, wherever that place is — its own tab, or the
    /// stack the hub was opened on. Games, News and Flows push through this
    /// rather than onto `games`/`news`/`flows` directly.
    func push<Value: Hashable>(_ value: Value, on tab: Tab) {
        append(value, to: inHub(tab) ? hubHost : tab)
    }

    /// Push onto the stack the hub is on — a card in the hub opening its page.
    func pushFromHub<Value: Hashable>(_ value: Value) {
        append(value, to: hubHost)
    }

    /// Pop the top of a place's stack.
    func pop(on tab: Tab) {
        let host = inHub(tab) ? hubHost : tab
        switch host {
        case .today: if !today.isEmpty { today.removeLast() }
        case .chat: if !chat.isEmpty { chat.removeLast() }
        case .health: if !health.isEmpty { health.removeLast() }
        case .family: if !family.isEmpty { family.removeLast() }
        case .games: if !games.isEmpty { games.removeLast() }
        case .news: if !news.isEmpty { news.removeLast() }
        case .flows: if !flows.isEmpty { flows.removeLast() }
        }
    }

    private func append<Value: Hashable>(_ value: Value, to tab: Tab) {
        switch tab {
        case .today: today.append(value)
        case .chat: chat.append(value)
        case .health: health.append(value)
        case .family: family.append(value)
        case .games: games.append(value)
        case .news: news.append(value)
        case .flows: flows.append(value)
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
    // Held, not observed. These publish on every location fix, upload and
    // battery sample; observed here, each one redrew every tab behind its
    // glass — about once a second while out walking, and the phone ran hot.
    // Settings observes them itself, and the few values read here arrive
    // through `onReceive` with duplicates dropped.
    let companion: Companion
    let outbox: Outbox
    let location: LocationCollector
    let battery: BatteryMonitor
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
    /// The App Review demo: a strip on every screen while it runs.
    @ObservedObject private var reviewDemo = ReviewDemo.shared
    /// The reader's colours: a change rebuilds the tabs (see `.id` below).
    @ObservedObject private var palette = SRPaletteStore.shared
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

    /// The review demo, said above every screen so made-up data never passes
    /// for the real thing. Stacked ABOVE the tabs rather than inset into them:
    /// iOS 26's transparent bars ignore a TabView's inset and draw under it.
    var body: some View {
        VStack(spacing: 0) {
            if reviewDemo.active { DemoBanner() }
            tabs
        }
        // A family member's alarm, over whichever tab is open.
        .modifier(FamilyAlarmHost())
    }

    private var tabs: some View {
        TabView(selection: tabBinding) {
            NavigationStack(path: $router.today) {
                hosted(TodayScreen(companion: companion, alerts: alerts, site: site, family: family))
                    .srConnectionsBanner(connections) { router.openConnections() }
            }
            .tabItem { SRTabIcon.label("Home", "square.grid.2x2.fill") }
            .tag(Router.Tab.today)

            // Only the tabs this person may open are BUILT: a feature somebody
            // lacks is not a greyed-out tab or an explanation, it is not there.
            //
            // Where everyone is, straight after Today, which leads with it. Over
            // the COMPANION pairing, which every phone in the family has — so,
            // unlike Chat or News, not behind `paired`. The bar's order is
            // `AccessPolicy.bar`; this follows it.
            if access.allows(.family) {
                NavigationStack(path: $router.family) {
                    hosted(FamilyScreen(store: family, companion: companion))
                        .srConnectionsBanner(connections) { router.openConnections() }
                }
                .tabItem { SRTabIcon.label("Family", "person.2.wave.2") }
                .tag(Router.Tab.family)
            }

            // Games straight after Family, so whoever has both sees them
            // together — the owner as well as the family (John, 2026-10-21:
            // one layout for everyone).
            if access.allows(.games) {
                NavigationStack(path: $router.games) {
                    hosted(place(.games))
                }
                .tabItem { SRTabIcon.label("Games", "gamecontroller") }
                .badge(games.invites.count)
                .tag(Router.Tab.games)
            }

            if access.allows(.chat) {
                NavigationStack(path: $router.chat) {
                    hosted(paired(what: "your threads") { ThreadListScreen() })
                        .srConnectionsBanner(connections) { router.openConnections() }
                }
                .tabItem { SRTabIcon.label("Chat", "bubble.left.and.bubble.right") }
                .tag(Router.Tab.chat)
            }

            NavigationStack(path: $router.health) {
                hosted(HealthScreen(companion: companion))
                    .srConnectionsBanner(connections) { router.openConnections() }
            }
            .tabItem { SRTabIcon.label("Health", "heart.text.square") }
            .tag(Router.Tab.health)

            // News and Flows have no tab: they are in the hub, pushed onto
            // whichever tab it was opened on (see `AccessPolicy.inHub`).
        }
        // The deeper accent: the selected tab's label is 10-point text on
        // glass, where `SR.accent` measures 3.5:1 and this holds 4.8:1.
        // A fresh set of screens whenever "View as" changes: every tab's
        // stores were loaded as the person before, and a thread list or story
        // kept from the owner under Katie's tabs is the leak this exists to
        // rule out. The shared stores (family, alerts) re-apply on their own.
        //
        // And whenever the palette changes: every token is read as a view is
        // built, so a fresh set of screens is the whole app in the new
        // colours. The paths live on the router, so the reader stays where
        // they were; the Colours sheet is attached outside this, so it stays
        // open while the app redraws behind it.
        .id("\(access.viewingAs?.email ?? "self")#\(palette.epoch)")
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
            // First open after an update: what is in it. A beat after the
            // first frame, so it does not race the window's own first
            // presentation; the foreground handler below asks again.
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                router.offerWhatsNew(owner: access.current.owner)
            }
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
            // The widgets paint in the reader's palette, read from the shelf.
            palette.shareWithWidgets()
            await location.askForMotionIfNeeded()
            await site.check()
            await reconcileSite()
            // What the site holds of the owner's location hold, if anything:
            // it is the truth the family sees, and it may have ended.
            await LocationHoldStore.shared.refresh()
            syncFamilyWidgets()
            await alerts.refresh()
            await connections.refresh()
        }
        // This phone's own health link, re-judged whenever what it is judged
        // on moves. Everyone's, owner or member — see `PersonalHealthCheck`.
        .onReceive(companion.$lastUpload.removeDuplicates().dropFirst()) { _ in checkPersonal() }
        .onReceive(companion.$healthReviewNeeded.removeDuplicates().dropFirst()) { _ in checkPersonal() }
        .onReceive(companion.$paired.removeDuplicates().dropFirst()) { _ in checkPersonal() }
        .onChange(of: scenePhase) { _, phase in
            // The invite poll is a foreground thing: it stops the moment the
            // scene leaves, and nothing claims it runs when the app is shut.
            syncGamesPoll()
            guard phase == .active else { return }
            // A quick action taken while the app was merely backgrounded never
            // goes through `task`, which runs once per view lifetime.
            drainPending()
            // Notes a background relaunch built the window for, or that lost
            // to another sheet, are offered now.
            router.offerWhatsNew(owner: access.current.owner)
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
            if !AccessStore.ownerSite { CommissionStore.shared.clear() }
            syncGamesPoll()
            syncFamilyWidgets()
            Task {
                await reconcileSite()
                await connections.refresh()
                drainPending()
            }
        }
        // The site changed its mind about this person, or sent the pairing
        // code a member's phone asked for.
        .onChange(of: access.current) { _, _ in
            if !AccessStore.ownerSite { CommissionStore.shared.clear() }
            // Also when a place is no longer on the bar: its old tab is gone.
            if !access.allows(router.tab) || router.inHub(router.tab) { router.tab = .today }
            syncGamesPoll()
            syncFamilyWidgets()
            Task { await reconcileSite(); drainPending() }
        }
        // "View as" changed: the family is theirs now, or yours again.
        .onChange(of: access.viewingAs) { _, _ in
            CommissionStore.shared.clear()
            family.applyViewingAs()
            // The boards were the person before's; the site answers as the
            // new one on the next read.
            FamilyStepsStore.shared.reset()
            FamilyTasksStore.shared.reset()
            FamilyBacklogStore.shared.reset()
            FamilyForecastStore.shared.reset()
            LandgrabStore.shared.reset()
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
            // sr://family/steps, sr://family/tasks — a widget tapped, or a link.
            if let page = FamilyPage.from(url: url) {
                router.openFamilyPage(page)
                return
            }
            // sr://trips/<id>/<date> — the trip day's Lock Screen card.
            if let trip = TripLink.from(url: url) {
                router.openTrip(trip)
                return
            }
            // sr://pair?join=…&server=… — "Open SR" on the install page: the
            // link that put the app here connects the phone as its person.
            if let payload = PairingPayload.fromLink(url.absoluteString) {
                Task { await CodePairing.shared.scanned(payload, companion: companion) }
                return
            }
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
            sheetContent(sheet)
                // A sheet sits outside the `.environmentObject`s above, so it
                // is handed them again here: Settings' Colours row reads the
                // router, and without it the tap trapped (build 121, 10-20).
                .environmentObject(router)
                .environmentObject(alerts)
                .environmentObject(connections)
                .environmentObject(access)
                .environmentObject(games)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: Router.Sheet) -> some View {
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
        case .colours:
            SRPaletteSheet()
        case .whatsNew:
            WhatsNewSheet(releases: router.whatsNew, history: router.whatsNewHistory)
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

    /// Keep the family widgets' credential in step with this person: there
    /// while they may see the boards, gone the moment they may not.
    private func syncFamilyWidgets() {
        guard access.viewingAs == nil else { return }
        FamilyWidgetBridge.sync(allowed: AccessPolicy.familyBoards(access.current, sitePaired: site.paired))
    }

    /// The step board or the task list, on whichever stack holds it.
    @ViewBuilder
    private func familyPage(_ page: FamilyPage) -> some View {
        switch page {
        case .steps: FamilyStepsScreen()
        case .tasks: FamilyTasksScreen()
        case .messages: FamilyMessagesScreen()
        case .backlog: FamilyBacklogScreen()
        }
    }

    private func drainPending() {
        // The router refuses anything this person may not reach — a question
        // without chat, a hidden tab, the owner's inbox — so a stale entry
        // lands on Today rather than on a screen that is not there.
        AppDelegate.pending.drain(into: router, companion: companion)
        if let id = AppDelegate.pending.daydreamCommission, AccessStore.ownerSite {
            AppDelegate.pending.daydreamCommission = nil
            // "All": the note the double-check belongs to is on screen
            // behind the sheet, whichever list it sits in.
            DaydreamStore.shared.requestedFilter = .all
            router.openDaydream()
            CommissionStore.shared.destination = CommissionDestination(id: id)
        }
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
        // Demo mode's credential is pretend and its access fixed.
        if SRDemo.isOn { return }
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

    /// A tab's root, with everything any tab may push registered on it: the
    /// hub and what it opens (News, Flows, Daydream, Wildmind, the family
    /// boards, Landgrab's map) and what Games, News and Flows push. Every
    /// stack has the same set because the hub is opened on whichever tab is
    /// showing — and each type is registered ONCE per stack here, never again
    /// on a root, or SwiftUI picks one of the two at random.
    private func hosted<Root: View>(_ root: Root) -> some View {
        root
            .navigationDestination(for: HubRef.self) { _ in
                MoreScreen(places: access.inHub, games: games, companion: companion)
            }
            .navigationDestination(for: Router.Tab.self) { place($0) }
            .navigationDestination(for: Router.MorePage.self) { page in
                switch page {
                case .daydream: DaydreamScreen()
                case .wildmind: WildmindScreen()
                }
            }
            // Talk, Chronicle and Inventions, from the Wildmind page.
            .navigationDestination(for: WildmindPage.self) { WildmindPageView(page: $0) }
            .navigationDestination(for: FamilyPage.self) { familyPage($0) }
            // One person's moves looked back over, from a name under Next moves.
            .navigationDestination(for: FamilyMoveHistoryRef.self) { FamilyMoveHistoryScreen(ref: $0).id($0.subject) }
            // One msg family thread, from the list or a tapped message.
            .navigationDestination(for: FamilyThreadRef.self) { FamilyThreadScreen(ref: $0).id($0.id) }
            // Landgrab's map: from its own card in the hub and from Steps.
            .navigationDestination(for: LandgrabMapRef.self) { LandgrabMapScreen(week: $0.week) }
            .placeDestinations()
    }

    /// Games, News or Flows — Games as its tab's root, News and Flows pushed
    /// from the hub.
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
            .navigationDestination(for: GameLeaderboardRef.self) { _ in GameLeaderboardScreen() }
            .navigationDestination(for: MarblerRef.self) { _ in MarblerScreen() }
            // Play nearby: offline games, from the Games page and from More.
            .navigationDestination(for: OfflineGamesRef.self) { _ in OfflineGamesScreen() }
            // The Travel kit and its five tools, from the hub.
            .navigationDestination(for: TravelKitRef.self) { _ in TravelKitScreen() }
            .navigationDestination(for: TravelToolRef.self) { $0.screen }
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
