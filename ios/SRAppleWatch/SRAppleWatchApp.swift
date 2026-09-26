import SwiftUI

/// The Watch app: a glance and a few verbs. See docs/WATCH.md.
///
/// Pages, top to bottom, by the crown: Today, then the alerts and the pinned
/// workflows when this person has them, then the phone's sync status. Every
/// number comes from the iPhone's last snapshot, except the Move ring, which is
/// read here.
@main
struct SRAppleWatchApp: App {
    @StateObject private var model = WatchModel.shared
    @StateObject private var move = WatchMove()

    init() {
        WatchModel.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchRoot()
                .environmentObject(model)
                .environmentObject(move)
        }
    }
}

struct WatchRoot: View {
    @EnvironmentObject private var model: WatchModel
    @EnvironmentObject private var move: WatchMove
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            TabView {
                WatchTodayPage()
                if model.snapshot.showsAlerts { WatchAlertsPage() }
                if !model.snapshot.pinnedFlows.isEmpty { WatchFlowsPage() }
                WatchStatusPage()
            }
            .tabViewStyle(.verticalPage)
            .background(WatchInk.ground)
        }
        .tint(WatchInk.accent)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast.text)
                    .font(WatchInk.mono(12))
                    .foregroundStyle(WatchInk.ground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(toast.ok ? WatchInk.cream : WatchInk.bad, in: Capsule())
                    .padding(.bottom, 4)
                    .transition(.opacity)
                    .task(id: toast.text) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { model.toast = nil }
                    }
            }
        }
        .task { move.start() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            move.start()
            if model.isStale { model.requestRefresh() }
        }
    }
}
