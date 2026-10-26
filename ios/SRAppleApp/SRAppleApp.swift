import SwiftUI
import BackgroundTasks
import UserNotifications
import CoreSpotlight
import UIKit
import Combine

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var companion: Companion?
    var battery: BatteryMonitor?
    var startupError: String?
    /// Written by a notification tap or a Home Screen quick action before the
    /// scene exists, read by `ContentView` once it does.
    static let pending = PendingEntry()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Before anything reads `SRDemo.isOn` (the site client, access):
        // a UI test's fresh install must not inherit an earlier review demo.
        ReviewDemo.prepareLaunch()
        // Before Welcome can pair a fresh install, which would then look
        // like an update and be shown every set of notes.
        WhatsNew.prepareLaunch(paired: SiteClient.shared.isPaired,
                                protectedDataAvailable: application.isProtectedDataAvailable)
        // Teach UIKit the palette before the first view is laid out. Doing it
        // later leaves one system-grey navigation bar on screen for a frame.
        SRChrome.install()
        // The Cast SDK wants its context before any screen; it does not look
        // for TVs (or ask for the local network) until the Cast button is tapped.
        BacklogCastSetup.install()

        do {
            let outbox = try Outbox()
            companion = Companion(outbox: outbox)
            battery = BatteryMonitor(outbox: outbox)
        }
        catch { startupError = "Saved sync data could not be opened: \(error.localizedDescription). Reopen the app after unlocking your phone. Existing data has not been discarded." }

        UNUserNotificationCenter.current().delegate = self
        // Before anything is raised, and on every launch: a category that is
        // not registered when a notification arrives shows it with no buttons,
        // on the phone and on the Watch alike.
        UNUserNotificationCenter.current().setNotificationCategories(AlertActions.categories)
        // v8: and each open trip question's own buttons, merged into those —
        // now from the trips saved on the phone, and again whenever they
        // are re-read (`TripQuestionPushes`).
        TripQuestionAlerts.shared.start()
        // A push token on every launch; the site is handed it once paired.
        PushRegistration.shared.start(application)
        // The family journey: a site-started Live Activity wakes the app in
        // the background, and this must already be listening to report its
        // update token.
        JourneyLive.shared.start()
        // Trip stops' geofences: a crossing relaunches the app in the
        // background and must find this delegate. It takes only the regions
        // the location collector leaves free (`regionsReserved`).
        if let location = companion?.location {
            TripArrivals.shared.start { [weak location] in location?.regionsReserved ?? 1 + WatchedPlace.maximum }
        } else {
            TripArrivals.shared.start { 1 + WatchedPlace.maximum }
        }
        // A capture card left on the Lock Screen by an app that was killed
        // while recording: nothing is recording now, so it goes. (A launch BY
        // the Start intent starts its own card after this.)
        Task { @MainActor in
            if !CaptureRecorder.shared.recording { await CaptureLive.shared.endAll() }
        }
        // Off the plan: significant-change and visit wake-ups while a trip
        // day runs, so a relaunch for one must find this delegate too.
        TripOffPlan.shared.start()
        // A planner job started before the app was closed: collect it.
        TripJobs.shared.resume()
        // Before the first fix of a background relaunch, so a ride that woke
        // the app is marked from its start. A no-op until a bike is set up.
        BikePresence.shared.resume()
        // Listening before any scene exists: a message from the Watch can wake
        // the app in the background, and must find a session to arrive at.
        WatchBridge.shared.start(companion: companion)
        installQuickActions(application)

        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.strangeramblings.com.appleapp.refresh", using: nil) { [weak self] task in
            Task { @MainActor in
                guard let companion = self?.companion else { task.setTaskCompleted(success: false); return }
                companion.scheduleRefresh()
                let work = Task {
                    // Two jobs in the seconds iOS grants: push what the phone
                    // has collected up, and bring what the site has been trying
                    // to say down. The second is the floor under push: anything
                    // a push did not reach this phone with (no token yet, Apple
                    // dropped it) is collected here, so it runs even when the
                    // outbox is empty, and it runs SECOND so a full outbox
                    // cannot starve it of the whole budget.
                    await companion.sync(collectingFor: 15)
                    await AlertStore.backgroundPass()
                    // Someone waiting on the owner: approval while the app is
                    // shut is told once, as a local notification.
                    await RegistrationStore.backgroundPass()
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
                    // Last, and only for a phone that already follows trips:
                    // re-read them (each on its ETag), so an open question's
                    // buttons are registered before its push arrives.
                    await AppDelegate.refreshTripsInBackground()
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
    /// Four verbs, chosen because each is something you want BEFORE the app
    /// has finished opening: start a capture (the owner's), ask a question,
    /// see the figures, push what is queued. Registered in code rather than `Info.plist` so the titles live
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
        case .capture:
            // Straight into recording, on the Captures page so the timer and
            // Stop are in front of you. Pressed again while recording, it stops.
            Self.pending.capture = CaptureLink(captureId: nil)
            NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
            await CaptureRecorder.shared.toggle(source: "app")
        case .ask: Self.pending.tab = .chat
        case .health: Self.pending.tab = .health
        case .sync:
            Self.pending.tab = .today
            await companion?.sync()
        }
        return true
    }

    // MARK: - Notifications

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistration.shared.received(deviceToken)
    }

    /// No token (a simulator, no network at launch). Nothing is lost: the pull
    /// still delivers everything, and the next launch asks again.
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    /// An answer to a stalled chat turn, from a notification button — often on
    /// the Watch, with the app in the background. Said only when it did NOT
    /// land: a notification for every success would be noise over the silence
    /// that success is.
    static func answer(_ gate: GateAnswer) async {
        guard case .failed(let reason) = await gate.send() else { return }
        let content = UNMutableNotificationContent()
        content.title = gate.failureTitle
        content.body = "Open the chat to answer it. (\(reason))"
        content.sound = .default
        content.threadIdentifier = "chat"
        content.userInfo = ["category": "chat"]
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "gate-failed-\(gate.jobId)", content: content, trigger: nil)
        )
    }

    /// The trips, from the background refresh: at most hourly, and only on a
    /// phone that already holds some — a phone with no trips has no question
    /// to be asked. `TripQuestionAlerts` registers whatever the re-read brings.
    static func refreshTripsInBackground() async {
        let access = AccessStore.shared.current
        guard access.owner || access.family, !TripStore.shared.summaries.isEmpty else { return }
        await TripStore.shared.refreshIfStale(after: 3600)
    }

    /// A "msg family" reply from a notification's button. Said on a local
    /// notification only when it did not land.
    static func replyToFamily(_ messageId: String, _ body: String) async {
        guard let reason = await FamilyMessagesStore.post(reply: body, to: messageId, asSelf: true) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your reply was not sent"
        content.body = "Open msg family to answer it. (\(reason))"
        content.sound = .default
        content.threadIdentifier = AlertActions.familyMessageCategory
        content.userInfo = ["category": AlertActions.familyMessageCategory, "messageId": messageId]
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "msg-failed-\(messageId)", content: content, trigger: nil)
        )
    }

    /// Show a notification even while the app is open — AND keep it.
    ///
    /// The default is to swallow it, which here would mean the one moment the
    /// app is certain to be running — a background refresh that finished as the
    /// reader opened it — is the one moment nothing appears.
    ///
    /// `.list` is the half that was missing. Without it a foreground delivery
    /// shows as a banner and is then gone: it never enters Notification Centre.
    /// Before push, opening the app was the most common moment the queue got
    /// collected, so for most alerts that was the only delivery there was. A
    /// push that lands while the app is open takes the same path.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // A family alarm with the app open: the app rings it itself, on a
        // loop through the silent switch, instead of the push's 28 seconds.
        let info = notification.request.content.userInfo
        let category = info["category"] as? String ?? notification.request.content.categoryIdentifier
        if category == FamilyAlarmStore.category, let alarm = FamilyAlarm(userInfo: info) {
            FamilyAlarmStore.shared.receive(alarm)
            return [.list]
        }
        if category == FamilyAlarmStore.cancelCategory, let id = info["alarmId"] as? String {
            FamilyAlarmStore.shared.cancelled(id)
            return [.banner, .list]
        }
        // A build the owner sent this phone, with the app open: ask the site
        // now, and the app's own prompt offers it. The banner would say the
        // same thing twice.
        if category == AppUpdate.pushCategory {
            Task { await AppUpdate.shared.check(force: true) }
            return [.list]
        }
        // A family message or a reply while msg family may be on screen.
        if FamilyPage.from(category: category, userInfo: info) == .messages {
            Task { await FamilyMessagesStore.shared.load() }
        }
        // A game push ("Your move in …", "… is over", an invite) with the app
        // open: the room and the lobby re-read now, and the room on screen
        // swallows it — the board already says whose move it is.
        if let room = GameTurnPush.roomId(category: category, userInfo: info) {
            NotificationCenter.default.post(name: GameTurnPush.arrived, object: room)
            if GameTurnPush.silenced(roomId: room, onScreen: GameRoomsOnScreen.ids) { return [] }
        }
        return [.banner, .list, .sound, .badge]
    }

    /// A tapped notification goes to the tab that owns its category.
    ///
    /// Except a lapsed connection, which opens the list of them with Fix on
    /// each, over whichever tab was open: the inbox would be one tap further
    /// from the only thing the reader can do about it.
    ///
    /// A pressed BUTTON is different: it arrives with the app in the
    /// background, often from the Watch, and does its job without navigating
    /// anywhere. See `AlertActions`.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let outcome = AlertActions.outcome(
            action: response.actionIdentifier,
            categoryIdentifier: content.categoryIdentifier,
            userInfo: content.userInfo,
            text: (response as? UNTextInputNotificationResponse)?.userText
        )
        let category: String
        switch outcome {
        case .openCommission(let id):
            Self.pending.daydreamCommission = id
            NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
            return
        case .answer(let gate):
            await Self.answer(gate)
            return
        case .familyReply(let messageId, let body):
            await Self.replyToFamily(messageId, body)
            return
        case .tripAnswer(let answer):
            await TripQuestionAlerts.answer(answer)
            return
        case .openTrip(let link):
            // "Off the plan?" / "A booking is at risk", raised on this phone
            // by `TripOffPlan`: its day, where the ways to carry on are. A
            // trip question: the trip's planning home, at the question. Both
            // used to fall through to the alerts inbox, which never holds one.
            Self.pending.trip = link
            NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
            return
        case .read(let id):
            await AlertStore.markReadFromNotification(id)
            return
        case .clear(let id):
            AlertStore.clearFromNotification(id)
            return
        case .ignore:
            return
        case .open(let tapped):
            category = tapped
        }
        // The site's categories reach only the owner's phone (a member's never
        // polls the owner's inbox), but a notification can outlive the access
        // that raised it. The router refuses a tab, the inbox or the
        // connections sheet this person may not reach, so a stale tap opens
        // Today.
        // A family alarm, tapped from the Lock Screen: ring it in the app and
        // put it over the Family tab, where everybody is on the map.
        if category == FamilyAlarmStore.category || category == FamilyAlarmStore.cancelCategory {
            let info = response.notification.request.content.userInfo
            if category == FamilyAlarmStore.category, let alarm = FamilyAlarm(userInfo: info) {
                FamilyAlarmStore.shared.receive(alarm)
            } else if let id = info["alarmId"] as? String {
                FamilyAlarmStore.shared.cancelled(id)
            }
            Self.pending.tab = .family
            NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
            return
        }
        // A build the owner sent this phone: ask the site now — the hourly
        // check may have just run — and its prompt offers the install.
        if category == AppUpdate.pushCategory {
            await AppUpdate.shared.check(force: true)
            return
        }
        // "Capture ready" (`url: sr://captures/<id>`): the capture, to review.
        if let capture = CaptureLink.from(userInfo: response.notification.request.content.userInfo) {
            Self.pending.capture = capture
            NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
            return
        }
        if category == "connections" {
            Self.pending.openConnections = true
            NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
            return
        }
        // A household arrival is not in the site's inbox (a member has no site
        // pairing at all), so opening the inbox for it would show nothing.
        // A leave-by reminder, scheduled on this phone from Coming up.
        if category == LeaveByReminders.category {
            Self.pending.tab = .family
            NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
            return
        }
        if category == "household" {
            Self.pending.tab = .today
            NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
            return
        }
        // The family's step board or task list: a dethroning, the 4pm
        // standings, a task done, confirmed or sent back. The site sends
        // `url: sr://family/…` (and a `family-steps` / `family-tasks`
        // category); `Router.openFamilyPage` refuses it for somebody without them.
        if let page = FamilyPage.from(category: category, userInfo: response.notification.request.content.userInfo) {
            Self.pending.familyPage = page
            // A message or a reply opens on its thread.
            Self.pending.familyThread = page == .messages
                ? response.notification.request.content.userInfo["messageId"] as? String : nil
            NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
            return
        }
        // A game invite, pushed by the site or raised by the foreground poll,
        // or a durable game's "Your move" / "… is over" push (`kind` turn |
        // finished, same `roomId` and `game`): each opens the room, days later
        // too. `Router.openGame` refuses it for somebody without games.
        if category == "game" {
            let info = response.notification.request.content.userInfo
            if let room = info["roomId"] as? String {
                Self.pending.gameRoom = room
                Self.pending.gameKind = info["game"] as? String
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
    /// Which game that room is, when the notification said.
    var gameKind: String?
    /// The step board or the task list, from a tapped family notification.
    var familyPage: FamilyPage?
    /// The msg family thread that notification was about.
    var familyThread: String?
    /// A trip day, from a tapped trip alert.
    var trip: TripLink?
    /// A capture, from a tapped "Capture ready".
    var capture: CaptureLink?
    var openAlerts = false
    var openConnections = false
    var daydreamCommission: String?
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
            router.openGame(gameRoom, game: gameKind)
            self.gameRoom = nil
            gameKind = nil
            tab = nil
        }
        if let familyPage {
            router.openFamilyPage(familyPage, thread: familyThread)
            self.familyPage = nil
            familyThread = nil
            tab = nil
        }
        if let trip {
            router.openTrip(trip)
            self.trip = nil
            tab = nil
        }
        if let capture {
            router.openCaptures(capture)
            self.capture = nil
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
            Group {
                if let companion = delegate.companion, let battery = delegate.battery {
                    EntryGate(companion: companion, battery: battery)
                        .task {
                            battery.start()
                            // A route walk the app was killed during becomes a
                            // recording, then anything waiting goes up.
                            FollowSession.recoverInterrupted()
                            await RecordingQueue.shared.flush()
                            // A capture that was waiting — recorded offline,
                            // or stopped as the app was killed — goes up.
                            await CaptureStore.shared.drain()
                            if companion.paired { await companion.sync() }
                        }
                        .onChange(of: scenePhase) { _, phase in
                            if phase == .active {
                                // A reading on every foreground, so a long background
                                // stretch is bracketed by two real samples rather
                                // than guessed at.
                                battery.sample()
                                if companion.paired { Task { await companion.sync() } }
                                Task { await SiteClient.shared.retryPendingRevocations(); await PushRegistration.shared.sync() }
                                Task { await RecordingQueue.shared.flush() }
                                Task { await CaptureStore.shared.drain() }
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
            // Light, dark or the phone's own: every screen, every sheet.
            .srAppearanceRoot()
        }
    }
}

/// Welcome, the review screen, or the app — decided by `EntryPolicy` from
/// what this phone holds. Re-read on every change to the registration and
/// the companion pairing, so an approval swaps the whole window over.
private struct EntryGate: View {
    /// Held, not observed: the gate only needs "paired", mirrored below.
    /// Observed, every upload and status line re-ran the app's root.
    let companion: Companion
    @State private var companionPaired: Bool?
    let battery: BatteryMonitor
    @ObservedObject private var registration = RegistrationStore.shared
    /// The App Review demo: entered from Welcome's code box, left from
    /// Settings. Either way the whole window swaps.
    @ObservedObject private var reviewDemo = ReviewDemo.shared
    /// A copy installed from strangeramblings.com/app offering its own update.
    @ObservedObject private var update = AppUpdate.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group { gate }
            .onReceive(companion.$paired.removeDuplicates()) { companionPaired = $0 }
            .appUpdatePrompt(update)
            .task { await update.check() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await update.check() } }
            }
    }

    @ViewBuilder
    private var gate: some View {
        switch registration.entry(companionPaired: companionPaired ?? companion.paired) {
        case .welcome:
            WelcomeScreen(registration: registration, companion: companion)
        case .reviewing(let status):
            ReviewScreen(registration: registration, status: status)
        case .app:
            ContentView(companion: companion, outbox: companion.outbox,
                        location: companion.location, battery: battery)
                // A fresh set of screens into and out of the demo: nothing
                // loaded from fixtures survives into the real app, or back.
                .id(reviewDemo.active)
                // Approved from Welcome: health and location connect through
                // the site, no QR. A no-op for every other phone.
                .task(id: registration.status) { await registration.connectCompanion(companion) }
        }
    }
}
