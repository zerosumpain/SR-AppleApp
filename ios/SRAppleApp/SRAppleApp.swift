import SwiftUI
import BackgroundTasks
import UserNotifications
import CoreSpotlight
import UIKit

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var companion: Companion?
    var battery: BatteryMonitor?
    var startupError: String?
    /// Written by a notification tap or a Home Screen quick action before the
    /// scene exists, read by `ContentView` once it does.
    static let pending = PendingEntry()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Teach UIKit the palette before the first view is laid out. Doing it
        // later leaves one system-grey navigation bar on screen for a frame.
        SRChrome.install()

        do {
            let outbox = try Outbox()
            companion = Companion(outbox: outbox)
            battery = BatteryMonitor(outbox: outbox)
        }
        catch { startupError = "Saved sync data could not be opened: \(error.localizedDescription). Reopen the app after unlocking your phone. Existing data has not been discarded." }

        UNUserNotificationCenter.current().delegate = self
        installQuickActions(application)

        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.strangeramblings.com.appleapp.refresh", using: nil) { [weak self] task in
            Task { @MainActor in
                guard let companion = self?.companion else { task.setTaskCompleted(success: false); return }
                companion.scheduleRefresh()
                let work = Task {
                    // Two jobs in the seconds iOS grants: push what the phone
                    // has collected up, and bring what the site has been trying
                    // to say down. The second is the ONLY way a notification
                    // from this site ever reaches this phone — there is no push
                    // certificate — so it runs even when the outbox is empty,
                    // and it runs SECOND so a full outbox cannot starve it of
                    // the whole budget.
                    await companion.sync(collectingFor: 15)
                    await AlertStore.backgroundPass()
                    // The household's arrivals and departures, from the
                    // companion server (members have no site lane). `sync`
                    // already asked if it ran; this covers a sync skipped
                    // because another was in flight, and is throttled.
                    await companion.drainHouseholdAlerts()
                    // And whether a site connection has lapsed, for the badge
                    // and the banner the next launch opens on.
                    await ConnectionsStore.backgroundPass(outbox: companion.outbox)
                    // And whether this phone's OWN uploads have stalled — told
                    // once, to whoever holds it, owner or not.
                    await PersonalHealthCheck.backgroundPass(outbox: companion.outbox, paired: companion.paired)
                    task.setTaskCompleted(success: companion.queueCount == 0)
                }
                task.expirationHandler = { work.cancel() }
                await work.value
            }
        }
        return true
    }

    /// Long-press the app icon.
    ///
    /// Three verbs, chosen because each is something you want BEFORE the app
    /// has finished opening: ask a question, see the figures, push what is
    /// queued. Registered in code rather than `Info.plist` so the titles live
    /// beside the routing that honours them — and so they can follow what this
    /// person may use: "Ask jkai" is only there with chat. `ContentView`
    /// re-sets them whenever the site's answer changes.
    private func installQuickActions(_ application: UIApplication) {
        application.shortcutItems = AccessPolicy.quickActions(for: AccessStore.shared.current).map { $0.item }
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        guard let kind = QuickActionKind(rawValue: shortcutItem.type) else { return false }
        // iOS can hand back an item set before access changed. One for a
        // feature this person no longer has opens the app on Today, nothing more.
        guard AccessPolicy.quickActions(for: AccessStore.shared.current).contains(kind) else {
            Self.pending.tab = .today
            return true
        }
        switch kind {
        case .ask: Self.pending.tab = .chat
        case .health: Self.pending.tab = .health
        case .sync:
            Self.pending.tab = .today
            await companion?.sync()
        }
        return true
    }

    // MARK: - Notifications

    /// Show a notification even while the app is open — AND keep it.
    ///
    /// The default is to swallow it, which here would mean the one moment the
    /// app is certain to be running — a background refresh that finished as the
    /// reader opened it — is the one moment nothing appears.
    ///
    /// `.list` is the half that was missing. Without it a foreground delivery
    /// shows as a banner and is then gone: it never enters Notification Centre.
    /// With no push certificate, opening the app is the most common moment the
    /// queue gets collected, so for most alerts that was the only delivery
    /// there was.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    /// A tapped notification goes to the tab that owns its category.
    ///
    /// Except a lapsed connection, which opens the list of them with Fix on
    /// each, over whichever tab was open: the inbox would be one tap further
    /// from the only thing the reader can do about it.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let category = response.notification.request.content.categoryIdentifier
        // The site's categories reach only the owner's phone (a member's never
        // polls the owner's inbox), but a notification can outlive the access
        // that raised it. The router refuses a tab, the inbox or the
        // connections sheet this person may not reach, so a stale tap opens
        // Today.
        if category == "connections" {
            Self.pending.openConnections = true
            NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
            return
        }
        // A household arrival is not in the site's inbox (a member has no site
        // pairing at all), so opening the inbox for it would show nothing.
        if category == "household" {
            Self.pending.tab = .today
            NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
            return
        }
        // A game invite, raised by this phone's own foreground poll. Opens the
        // room; `Router.openGame` refuses it for somebody without games.
        if category == "game" {
            if let room = response.notification.request.content.userInfo["roomId"] as? String {
                Self.pending.gameRoom = room
            } else {
                Self.pending.tab = .games
            }
            NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
            return
        }
        switch category {
        case "health": Self.pending.tab = .health
        case "chat": Self.pending.tab = .chat
        case "news": Self.pending.tab = .news
        default: Self.pending.tab = .today
        }
        Self.pending.openAlerts = true
        NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
    }
}

/// Somewhere for a launch-time intent to wait.
///
/// A quick action or a notification tap can arrive before `ContentView` exists,
/// and there is no `Router` yet to write to. This is a plain box the delegate
/// can fill and the first `task` can drain — deliberately not `ObservableObject`,
/// because nothing should re-render when it changes; it is read once.
@MainActor final class PendingEntry {
    /// Posted when a notification tap filled the box while the app was
    /// already in the foreground, so `ContentView` drains it at once.
    nonisolated static let changed = Notification.Name("SRPendingEntryChanged")

    var tab: Router.Tab?
    /// A game room to open, from a tapped invite.
    var gameRoom: String?
    var openAlerts = false
    var openConnections = false
    /// A question handed in by Siri or a Shortcut. Put in the composer, never
    /// sent: a turn sent from a locked phone is a turn you cannot see go wrong.
    var question: String?
    var sync = false

    func drain(into router: Router, companion: Companion?) {
        if let question {
            router.ask(question)
            self.question = nil
            tab = nil
        }
        if let gameRoom {
            router.openGame(gameRoom)
            self.gameRoom = nil
            tab = nil
        }
        if let tab { router.show(tab) }
        tab = nil
        if sync {
            sync = false
            Task { await companion?.sync() }
        }
    }
}

@main struct SRAppleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if let companion = delegate.companion, let battery = delegate.battery {
                ContentView(companion: companion, outbox: companion.outbox,
                            location: companion.location, battery: battery)
                    .task {
                        battery.start()
                        if companion.paired { await companion.sync() }
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active {
                            // A reading on every foreground, so a long background
                            // stretch is bracketed by two real samples rather
                            // than guessed at.
                            battery.sample()
                            if companion.paired { Task { await companion.sync() } }
                        }
                        if phase == .background {
                            battery.sample()
                            companion.scheduleRefresh()
                            // A deferred outbox removal (an accepted batch,
                            // written lazily during a flush) must not ride
                            // into a suspend unwritten.
                            try? companion.outbox.persistIfDirty()
                        }
                    }
            } else { ContentUnavailableView("Sync unavailable", systemImage: "lock.shield", description: Text(delegate.startupError ?? "Starting…")) }
        }
    }
}
