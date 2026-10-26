import SwiftUI

/// The valley in 3D, full-screen: Wildmind's own world (`WildmindWorld.swift`)
/// under the app's glass bars. Pushed from the Wildmind page.
///
/// The top bar is the page's clock and its controls: the day and season, the
/// time and the sky, pause and speed, and a menu of everything else — watch,
/// sound, detail, the tech tree, the valley's words (Talk, Chronicle,
/// Inventions, the app's own screens) and Wildmind's other pages (Economy,
/// Stats, Lineage…, each in its own web view, so the world keeps running
/// behind them). The bottom bar has the people, to follow with a tap, the
/// panels the desktop keeps down its side, the map, and a whisper.
///
/// The world itself is the page's: drag to turn, pinch to zoom, two fingers
/// to pan, tap a built thing to see it, double-tap to look there.
struct WildmindWorldScreen: View {
    @StateObject private var model = WildmindWorldModel()
    @Environment(\.scenePhase) private var scenePhase
    /// A page of Wildmind's own, pushed over the world.
    @State private var web: WildmindWebRef?
    /// One of the app's own Wildmind screens, pushed over the world.
    @State private var native: WildmindPage?
    @State private var insets = EdgeInsets()
    @AppStorage("wildmind.world.lowDetail") private var lowDetail = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                WildmindWorldWebView(model: model, open: openLink)
                    .ignoresSafeArea()
                    .accessibilityLabel("The valley in 3D")
                    .accessibilityIdentifier("wildmind-world")
                cover
                if let news = model.news {
                    newsBanner(news)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.news)
            .onAppear { insets = geo.safeAreaInsets; sendInsets() }
            .onChange(of: geo.safeAreaInsets) { _, next in insets = next; sendInsets() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) { clock }
            ToolbarItemGroup(placement: .topBarTrailing) {
                pauseButton
                moreMenu
            }
        }
        .navigationDestination(item: $web) { WildmindWebScreen(ref: $0) }
        .navigationDestination(item: $native) { WildmindPageView(page: $0) }
        .task { await model.start() }
        .onChange(of: model.phase) { _, phase in if phase == .ready { sendInsets() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refresh() } }
    }

    private func retry() {
        Task { await model.start() }
    }

    private func sendInsets() {
        model.insets(top: insets.top, bottom: insets.bottom)
    }

    // MARK: - Before the world is up

    @ViewBuilder
    private var cover: some View {
        switch model.phase {
        case .ready:
            EmptyView()
        case .signingIn, .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text(model.phase == .signingIn ? "Signing in to the valley\u{2026}" : "Drawing the valley\u{2026}")
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkSecondary)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .srGlassCard(.paper)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("wildmind-world-loading")
        case .failed(let message):
            SREmpty(
                title: "The valley didn\u{2019}t open",
                icon: "mountain.2",
                message: message,
                actionLabel: "Try again",
                action: retry
            )
            .padding(SR.gutter)
            .srGlassCard(.paper)
            .padding(SR.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("wildmind-world-failed")
        }
    }

    private func newsBanner(_ text: String) -> some View {
        Text(text)
            .font(SR.Text.bodyMedium(14))
            .foregroundStyle(SR.ink)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
            .padding(.horizontal, SR.gutter)
            .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Top bar

    private var clock: some View {
        VStack(spacing: 0) {
            Text(model.state.dayLine.uppercased())
                .font(SR.Text.label(11))
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(model.state.clock)
                    .font(SR.Text.figure(17))
                    .foregroundStyle(SR.ink)
                Image(systemName: model.state.skyIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SR.accent)
                    .accessibilityHidden(true)
                Text("\(model.state.temperature)\u{00B0}")
                    .font(SR.Text.mono(12))
                    .foregroundStyle(SR.inkSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.state.dayLine), \(model.state.clock), \(model.state.skyLine)")
        .accessibilityIdentifier("wildmind-world-clock")
    }

    /// Pause, with the speeds behind a long press; the label says the speed.
    private var pauseButton: some View {
        Menu {
            Picker("Speed", selection: Binding(get: { model.state.speed }, set: { SRHaptic.select(); model.setSpeed($0) })) {
                ForEach(WildmindSpeed.all, id: \.self) { Text(WildmindSpeed.label($0)).tag($0) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.state.paused ? "play.fill" : "pause.fill")
                Text(WildmindSpeed.label(model.state.speed))
                    .font(SR.Text.mono(12))
            }
        } primaryAction: {
            SRHaptic.tap()
            model.setPaused(!model.state.paused)
        }
        .accessibilityLabel(model.state.paused ? "Resume" : "Pause")
        .accessibilityHint("Hold for the speed")
        .accessibilityIdentifier("wildmind-world-pause")
    }

    private var moreMenu: some View {
        Menu {
            Section {
                Toggle(isOn: Binding(get: { model.state.watching }, set: { model.setWatching($0) })) {
                    Label("Watch", systemImage: "video")
                }
                Toggle(isOn: Binding(get: { model.state.sound }, set: { model.setSound($0) })) {
                    Label("Sound", systemImage: "speaker.wave.2")
                }
                Toggle(isOn: Binding(get: { lowDetail }, set: { lowDetail = $0; model.setQuality(!$0) })) {
                    Label("Low detail", systemImage: "battery.50")
                }
                Button { model.techTree() } label: { Label("Tech tree", systemImage: "point.3.connected.trianglepath.dotted") }
            }
            Section("The valley\u{2019}s words") {
                Button { native = .talk(compose: false) } label: { Label("Talk", systemImage: "text.bubble") }
                Button { native = .chronicle } label: { Label("Chronicle", systemImage: "book") }
                Button { native = .inventions } label: { Label("Inventions", systemImage: "lightbulb") }
            }
            Section("Pages") {
                ForEach(WildmindPlace.allCases) { place in
                    Button { open(place) } label: { Label(place.title, systemImage: place.icon) }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("wildmind-world-more")
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if !model.state.people.isEmpty { peopleRow }
            HStack(spacing: 8) {
                panelMenu
                barButton(model.state.map ? "3D" : "Map", icon: model.state.map ? "cube" : "map", id: "wildmind-world-view") {
                    SRHaptic.select()
                    model.setMap(!model.state.map)
                }
                barButton("Whisper", icon: "ear", id: "wildmind-world-whisper") {
                    native = .talk(compose: true)
                }
            }
        }
        .padding(.horizontal, SR.gutter)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var peopleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.state.people) { person in
                    personChip(person)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func personChip(_ p: WildmindWorldState.Person) -> some View {
        let chosen = p.id == model.state.selected
        return Button {
            SRHaptic.select()
            model.follow(p.id)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(p.alive ? (p.alarm > 0 ? SR.warn : SR.accent) : SR.inkMuted)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(p.name)
                    .font(SR.Text.title(14))
                    .foregroundStyle(SR.ink)
                Text(p.alive ? p.label : "Died")
                    .font(SR.Text.mono(12))
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(1)
                if p.alive {
                    Text("\(p.health)")
                        .font(SR.Text.mono(12).weight(.bold))
                        .foregroundStyle(p.health < 30 ? SR.warn : SR.accent)
                }
                if chosen && model.state.following {
                    Image(systemName: "scope")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SR.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .srGlass(chosen ? .paper : .clear, in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .disabled(!p.alive)
        .accessibilityLabel("\(p.name), \(p.alive ? p.label : "died"), health \(p.health)")
        .accessibilityValue(chosen && model.state.following ? "Following" : "")
        .accessibilityHint("Follow \(p.name)")
        .accessibilityIdentifier("wildmind-world-person-\(p.id)")
    }

    /// The desktop's side panel, one tab at a time as the page's sheet.
    private var panelMenu: some View {
        Menu {
            ForEach(WildmindPanel.allCases) { panel in
                Button { model.openPanel(panel) } label: {
                    Label(panel == .economy && model.state.alarm > 0 ? "\(panel.title) \u{2014} a day cannot last" : panel.title, systemImage: panel.icon)
                }
            }
            if model.state.panel != nil {
                Divider()
                Button { model.openPanel(nil) } label: { Label("Put the panel away", systemImage: "chevron.down") }
            }
        } label: {
            barLabel(currentPanel?.title ?? "Panels", icon: currentPanel?.icon ?? "rectangle.bottomhalf.inset.filled", alarm: model.state.alarm > 0)
        }
        .accessibilityIdentifier("wildmind-world-panels")
    }

    private var currentPanel: WildmindPanel? { model.state.panel.flatMap(WildmindPanel.init(rawValue:)) }

    private func barButton(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { barLabel(title, icon: icon, alarm: false) }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
    }

    private func barLabel(_ title: String, icon: String, alarm: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(alarm ? SR.warn : SR.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(SR.Text.title(14))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .srGlass(.paper, in: Capsule(), interactive: true)
    }

    // MARK: - Wildmind's other pages

    private func open(_ place: WildmindPlace) {
        guard let page = model.pageURL else { return }
        web = WildmindWebRef(title: place.title, url: page.appendingPathComponent(place.rawValue))
    }

    /// A link in the valley to another of Wildmind's pages.
    private func openLink(_ url: URL) {
        let place = WildmindPlace(rawValue: url.lastPathComponent)
        web = WildmindWebRef(title: place?.title ?? "Wildmind", url: url)
    }
}

/// One of Wildmind's own pages, pushed over the world.
struct WildmindWebRef: Hashable, Identifiable {
    let title: String
    let url: URL
    var id: URL { url }
}

struct WildmindWebScreen: View {
    let ref: WildmindWebRef
    @State private var failed: String?

    var body: some View {
        WildmindWebPageView(url: ref.url, failed: $failed)
            .ignoresSafeArea(edges: .bottom)
            .overlay {
                if let failed {
                    SREmpty(title: "That page didn\u{2019}t open", icon: "wifi.slash", message: failed)
                        .padding(SR.gutter)
                        .srGlassCard(.paper)
                        .padding(SR.gutter)
                }
            }
            .srGround(.wire)
            .navigationTitle(ref.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .accessibilityIdentifier("wildmind-web-page")
    }
}
