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
    /// beside the routing that honours them.
    private func installQuickActions(_ application: UIApplication) {
        application.shortcutItems = [
            UIApplicationShortcutItem(
                type: "com.strangeramblings.com.appleapp.ask",
                localizedTitle: "Ask jkai",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "bubble.left.and.text.bubble.right")
            ),
            UIApplicationShortcutItem(
                type: "com.strangeramblings.com.appleapp.health",
                localizedTitle: "Health today",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "heart.text.square")
            ),
            UIApplicationShortcutItem(
                type: "com.strangeramblings.com.appleapp.sync",
                localizedTitle: "Sync now",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "arrow.triangle.2.circlepath")
            ),
        ]
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        switch shortcutItem.type {
        case "com.strangeramblings.com.appleapp.ask": Self.pending.tab = .chat
        case "com.strangeramblings.com.appleapp.health": Self.pending.tab = .health
        case "com.strangeramblings.com.appleapp.sync":
            Self.pending.tab = .today
            await companion?.sync()
        default: return false
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
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        switch response.notification.request.content.categoryIdentifier {
        case "health": Self.pending.tab = .health
        case "chat": Self.pending.tab = .chat
        case "news": Self.pending.tab = .news
        default: Self.pending.tab = .today
        }
        Self.pending.openAlerts = true
    }
}

/// Somewhere for a launch-time intent to wait.
///
/// A quick action or a notification tap can arrive before `ContentView` exists,
/// and there is no `Router` yet to write to. This is a plain box the delegate
/// can fill and the first `task` can drain — deliberately not `ObservableObject`,
/// because nothing should re-render when it changes; it is read once.
@MainActor final class PendingEntry {
    var tab: Router.Tab?
    var openAlerts = false
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
