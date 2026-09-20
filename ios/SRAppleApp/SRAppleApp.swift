import SwiftUI
import BackgroundTasks

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate {
    var companion: Companion?
    var startupError: String?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        do { companion = Companion(outbox: try Outbox()) }
        catch { startupError = "Saved sync data could not be opened: \(error.localizedDescription). Reopen the app after unlocking your phone. Existing data has not been discarded." }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.strangeramblings.com.appleapp.refresh", using: nil) { [weak self] task in
            Task { @MainActor in
                guard let companion = self?.companion else { task.setTaskCompleted(success: false); return }
                companion.scheduleRefresh()
                let work = Task { await companion.sync(); task.setTaskCompleted(success: companion.queueCount == 0) }
                task.expirationHandler = { work.cancel() }
                await work.value
            }
        }
        return true
    }
}
@main struct SRAppleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            if let companion = delegate.companion {
                ContentView(companion: companion, outbox: companion.outbox, location: companion.location)
                    .task { if companion.paired { await companion.sync() } }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active && companion.paired { Task { await companion.sync() } }
                        if phase == .background { companion.scheduleRefresh() }
                    }
            } else { ContentUnavailableView("Sync unavailable", systemImage: "lock.shield", description: Text(delegate.startupError ?? "Starting…")) }
        }
    }
}
