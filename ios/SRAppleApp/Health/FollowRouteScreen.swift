import SwiftUI

/// Walking a route: the map with you on it, how far along, how far left, how
/// long, and a banner when you leave the line. Full screen — a thing you
/// glance at mid-stride, not a page in a stack you can swipe away by accident.
struct FollowRouteScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: FollowSession
    @State private var confirmFinish = false
    @State private var finished: RouteRecording?

    init(detail: PlannedRouteDetail) {
        _session = StateObject(wrappedValue: FollowSession(detail: detail))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                map.ignoresSafeArea(edges: .bottom)
                if let p = session.progress, p.offRoute {
                    offRouteBanner(p)
                }
            }
            .safeAreaInset(edge: .bottom) { panel }
            .navigationTitle(session.detail.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(session.phase == .ready ? "Close" : "Finish") {
                        if session.phase == .ready { dismiss() } else { confirmFinish = true }
                    }
                }
            }
            .confirmationDialog("Finish this walk?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finish and save") {
                    finished = session.finish()
                    if finished == nil { dismiss() }
                }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("It is saved to your activities, now or as soon as there is signal.")
            }
            .alert("Saved", isPresented: Binding(get: { finished != nil }, set: { if !$0 { dismiss() } })) {
                Button("Done") { dismiss() }
            } message: {
                Text(savedLine)
            }
            .alert("Location is off", isPresented: .constant(session.denied)) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("Close", role: .cancel) { dismiss() }
            } message: {
                Text("Following a route needs your location while the app is in use.")
            }
            .interactiveDismissDisabled(session.phase != .ready)
        }
    }

    /// MapLibre, not MapKit: this is the map that has to work on a hill with
    /// no signal, from the route's downloaded pack.
    private var map: some View {
        SRRouteMap(
            route: session.coordinates,
            walked: session.walked,
            followsUser: true,
            marker: SRDemo.isOn ? session.here?.coordinate : nil
        )
    }

    private func offRouteBanner(_ p: RouteNav.Progress) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Off route — \(TrailFormat.metres(p.offRouteM)) m from the line")
                .font(SR.Text.body(15))
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(SR.accent, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .accessibilityIdentifier("follow-off-route")
    }

    private var panel: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                figure("DONE", session.progress.map { "\(TrailFormat.km($0.alongM)) km" } ?? "—")
                figure("LEFT", session.progress.map { "\(TrailFormat.km($0.remainingM)) km" } ?? "\(TrailFormat.km(session.detail.distanceM)) km")
                figure("TIME LEFT", session.timeLeftS.map { TrailFormat.duration($0) } ?? "—")
                figure("ELAPSED", TrailFormat.duration(session.elapsedS))
            }
            if let p = session.progress {
                ProgressView(value: p.fraction)
                    .tint(SR.accent)
                    .accessibilityLabel("\(Int((p.fraction * 100).rounded())) percent of the route")
            }
            if session.weakSignal {
                Text("Weak GPS — positions are approximate.")
                    .font(SR.Text.secondary(12))
                    .foregroundStyle(SR.inkMuted)
            }
            HStack(spacing: 12) {
                switch session.phase {
                case .ready:
                    Button { session.start() } label: { Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .srButton(.prominent)
                        .accessibilityIdentifier("follow-start")
                case .following:
                    Button { session.pause() } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                        .srButton(.regular)
                case .paused:
                    Button { session.start() } label: { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .srButton(.prominent)
                case .finished:
                    EmptyView()
                }
            }
        }
        .padding(16)
        .srGlassCard()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SR.Text.mono(10))
                .tracking(0.8)
                .foregroundStyle(SR.inkMuted)
            Text(value)
                .font(SR.Text.mono(17))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var savedLine: String {
        guard let r = finished else { return "" }
        let queued = RecordingQueue.shared.pending.contains { $0.clientId == r.clientId }
        return queued
            ? "\(TrailFormat.km(session.distanceM)) km recorded. It goes to your activities when there is signal."
            : "\(TrailFormat.km(session.distanceM)) km recorded and added to your activities."
    }
}
