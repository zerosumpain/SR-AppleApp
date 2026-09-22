import SwiftUI
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
    enum Tab: String, Hashable { case today, chat, health, news }

    @Published var tab: Tab = .today
    @Published var chat = NavigationPath()
    @Published var health = NavigationPath()
    @Published var news = NavigationPath()
    @Published var settingsOpen = false
    /// Which settings group to open on, when something sent the reader there
    /// for a reason.
    @Published var settingsTarget: SettingsTarget?
    /// A question handed in from outside — a Shortcut, Siri, a quick action.
    @Published var pendingQuestion: String?

    enum SettingsTarget: String, Hashable { case notifications, connections, health, location }

    func openSettings(_ target: SettingsTarget? = nil) {
        settingsTarget = target
        settingsOpen = true
    }

    /// Go to a tab and clear whatever was stacked on it.
    ///
    /// Clearing matters: an intent that opens Chat while a thread is already
    /// pushed would otherwise land on that thread, which is not what "open
    /// chat" means to the person who said it.
    func show(_ tab: Tab) {
        switch tab {
        case .chat: chat = NavigationPath()
        case .health: health = NavigationPath()
        case .news: news = NavigationPath()
        case .today: break
        }
        self.tab = tab
    }

    func ask(_ question: String) {
        pendingQuestion = question
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var alertsOpen = false

    var body: some View {
        TabView(selection: tabBinding) {
            NavigationStack {
                TodayScreen(companion: companion, alerts: alerts, site: site)
            }
            .tabItem { Label("Today", systemImage: "square.grid.2x2") }
            .tag(Router.Tab.today)

            NavigationStack(path: $router.chat) {
                paired(what: "your threads") { ThreadListScreen() }
            }
            .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            .tag(Router.Tab.chat)

            NavigationStack(path: $router.health) {
                HealthScreen(companion: companion)
            }
            .tabItem { Label("Health", systemImage: "heart.text.square") }
            .tag(Router.Tab.health)

            NavigationStack(path: $router.news) {
                paired(what: "the news desk") { NewsScreen() }
            }
            .tabItem { Label("News", systemImage: "newspaper") }
            .tag(Router.Tab.news)
        }
        .tint(SR.accent)
        .preferredColorScheme(.light)
        .environmentObject(router)
        .environmentObject(alerts)
        .task {
            // Anything a quick action, a notification tap or a Shortcut left
            // waiting before there was a router to receive it.
            AppDelegate.pending.drain(into: router, companion: companion)
            if AppDelegate.pending.openAlerts {
                AppDelegate.pending.openAlerts = false
                alertsOpen = true
            }
            await site.check()
            await alerts.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // A quick action taken while the app was merely backgrounded never
            // goes through `task`, which runs once per view lifetime.
            AppDelegate.pending.drain(into: router, companion: companion)
            if AppDelegate.pending.openAlerts {
                AppDelegate.pending.openAlerts = false
                alertsOpen = true
            }
            Task { await alerts.refresh() }
        }
        .sheet(isPresented: $alertsOpen) {
            NavigationStack { AlertsScreen(alerts: alerts) }
        }
        // A thread opened from Spotlight. The index carries the conversation id
        // as the item identifier, so this is a push rather than a search.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
            router.show(.chat)
            router.chat.append(ThreadReference(id: id))
        }
        .sheet(isPresented: $router.settingsOpen) {
            SettingsScreen(
                outbox: outbox,
                companion: companion,
                location: location,
                battery: battery,
                site: site,
                alerts: alerts,
                target: router.settingsTarget
            )
        }
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

    /// A tab that needs the site credential, or the one screen that explains
    /// why it does not have it.
    @ViewBuilder
    private func paired<Content: View>(what: String, @ViewBuilder content: () -> Content) -> some View {
        if site.paired {
            content()
        } else {
            SREmpty(
                title: "Not connected yet",
                icon: "qrcode.viewfinder",
                message: "Connect this iPhone to Strange Ramblings to read \(what).",
                action: (label: "Connect", run: { router.openSettings(.connections) })
            )
            .frame(maxHeight: .infinity)
            .srPaper()
            .navigationTitle(what.capitalized)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
