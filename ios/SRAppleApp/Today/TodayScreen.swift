import SwiftUI
import Combine

// MARK: - What one request answers with

struct TodayHealth: Decodable {
    let isMock: Bool
    let strap: String
    let readiness: HealthReadiness?
    let figures: [HealthFigure]
    let generatedAt: String
}

struct TodayAlerts: Decodable {
    let pending: Int
    let unread: Int
    let latest: [Latest]

    struct Latest: Decodable, Identifiable, Hashable {
        let id: String
        let category: String
        let title: String
        let severity: String
        let createdAt: String
    }
}

extension TodayAlerts {
    /// What the Today card lists: the newest few that have not been cleared.
    ///
    /// The inbox the app already holds is preferred — it is 25 deep, so a
    /// cleared row makes room for the next one down instead of leaving the card
    /// short. Today's own three are the fallback for the first paint, before
    /// the inbox has answered.
    static func rows(
        recent: [SiteAlert],
        latest: [Latest],
        cleared: Set<String>,
        limit: Int = 3
    ) -> [Latest] {
        let source = recent.isEmpty
            ? latest
            : recent.map {
                Latest(id: $0.id, category: $0.category, title: $0.title, severity: $0.severity, createdAt: $0.createdAt)
            }
        return Array(source.filter { !cleared.contains($0.id) }.prefix(limit))
    }
}

struct TodayNews: Decodable {
    let updatedAt: String?
    let unseen: Int
    let stories: [Story]

    struct Story: Decodable, Identifiable, Hashable {
        let key: String
        let title: String
        let sourceLabel: String
        let url: String?
        let heat: Double?

        var id: String { key }
    }
}

struct TodayThread: Decodable, Hashable {
    let id: String
    let title: String?
    let updatedAt: String
}

struct TodayPayload: Decodable {
    let generatedAt: String
    let health: TodayHealth?
    let alerts: TodayAlerts?
    let news: TodayNews?
    let lastThread: TodayThread?
    /// Site connections needing the owner. Absent on a server older than the
    /// connection monitor, which decodes as nil and means nothing to show.
    let connections: TodayConnections?
    /// The daydream loop's latest notes. Absent on a server older than the
    /// loop — the synthesised decoder reads a missing key as nil, and
    /// `DaydreamFeed` never throws, so a malformed block costs only the card.
    let daydream: DaydreamFeed?
}

/// The first screen's data, in one request.
///
/// Four calls would be the tidy decomposition and the wrong one — this is the
/// screen the app opens on, over whatever the phone happens to be connected to,
/// and four round trips is four chances to show a spinner. The server settles
/// them in parallel and degrades each card on its own.
@MainActor
final class TodayStore: ObservableObject {
    @Published private(set) var payload: TodayPayload?
    @Published private(set) var loading = false
    @Published var message: String?

    private let client = SiteClient.shared

    func load(fresh: Bool = false) async {
        guard AccessStore.ownerSite, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            // Annotated: assigning into the optional would infer `TodayPayload?`
            // as the decoded type. See HealthStore for the same note.
            let fetched: TodayPayload = try await client.send(
                "api/native/today\(fresh ? "?fresh=1" : "")"
            )
            payload = fetched
            message = nil
        } catch SiteError.unpaired {
            payload = nil
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Today.
///
/// This tab did not exist. Its slot on the bar was `Connect` — a QR scanner,
/// permanently on the tab bar, for a job you do once and never again. What an
/// iPhone wants in that slot is the thing you open the app FOR, and for this app
/// that is a glance: how the body is doing, what the site has been trying to
/// tell you, and where the conversation got to.
///
/// Under glass the screen is a stack of lifted sheets on a warm ground: who is
/// where, then four squares — Ask jkai, Health (the three rings), Daydream
/// (what the loop noticed) and Games — then the wire, and Sync at the foot.
/// The alerts and the workflows are the bell's: Up next repeated them and
/// went. An urgent alert still pins itself under the bar.
/// Nothing here is the only place to read anything.
///
/// No "carry on" card for the last thread: the Chat tab is one tap away on the
/// bar and opens on that list.
struct TodayScreen: View {
    @ObservedObject var companion: Companion
    @ObservedObject var alerts: AlertStore
    @ObservedObject var site: SitePairingModel
    @ObservedObject var family: FamilyStore
    @StateObject private var store = TodayStore()
    /// Today's Move ring, live from Apple Health on this phone.
    @StateObject private var move = MoveRingStore()
    @ObservedObject private var noticed = NoticedFeedback.shared
    private var daydream: DaydreamStore { DaydreamStore.shared }
    /// What this person may use. The owner's cards (the site's figures,
    /// alerts, workflows, what the loop noticed) are not drawn for anybody
    /// else — their endpoints would only refuse a member.
    @ObservedObject private var access = AccessStore.shared
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var connections: ConnectionsStore
    @Environment(\.scenePhase) private var scenePhase
    /// The alert tapped on the card, read in full in a sheet.
    @State private var opened: SiteAlert?
    /// Urgent alerts waved off the banner this session. Dismissing also marks
    /// the alert read, so this only bridges the moment before the inbox agrees.
    @State private var waved: Set<String> = []
    /// Today is the tab in front — the bell only rings while it is.
    @State private var onScreen = false

    /// How often the numbers are re-read while Today is on screen. Readiness
    /// and recovery move when a sync lands on the site; five minutes is often
    /// enough to catch that and rare enough to cost nothing.
    static let refreshInterval: Duration = .seconds(300)

    var body: some View {
        ScrollView {
            // No page title. The tab bar already says this is Today and the
            // bar carries the date, so the first thing under the bar is the
            // thing the app is opened for: where everyone is.
            VStack(alignment: .leading, spacing: 24) {
                // Over the companion pairing, so a family member without the
                // site's sees it too — if the owner gave them the family. Draws
                // nothing until there is somebody to show.
                if access.current.family {
                    TodayFamilyCard(store: family) {
                        router.show(.family)
                    }
                }

                if access.current.owner && !site.paired {
                    // The owner's QR. A member's phone pairs itself, and a
                    // member with neither chat nor news has nothing to pair.
                    connectCard
                } else if !companion.paired && !access.current.owner {
                    // Nobody knows who this is yet: the companion is where
                    // that answer comes from.
                    companionCard
                } else {
                    // Four doors, two by two: Ask and Health, Daydream and Games.
                    TodayTileGrid(tiles: TodayTile.kinds(access: access.current, sitePaired: site.paired)) { kind in
                        tile(kind)
                    }
                    if access.current.news, let news = store.payload?.news, let story = news.stories.first {
                        newsCard(news, story: story)
                    }
                    syncAction
                }
                syncFooter
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .srGround(.warm)
        // Pinned under the bar, not scrolled with the page: something urgent
        // stays in view until it is opened or waved away.
        .safeAreaInset(edge: .top, spacing: 0) {
            if access.current.owner, let urgent = TodayAlerts.urgent(in: alerts.recent, dismissed: waved) {
                TodayUrgentBanner(
                    alert: urgent,
                    open: {
                        SRHaptic.tap()
                        opened = urgent
                        Task { await alerts.markRead(urgent.id) }
                    },
                    dismiss: {
                        SRHaptic.select()
                        withAnimation(.snappy) { _ = waved.insert(urgent.id) }
                        Task { await alerts.markRead(urgent.id) }
                    }
                )
            }
        }
        .navigationTitle("Today")
        // Inline, and the title itself is replaced by the `sr.` mark. There is
        // no headline on the page either: see `SRPageHeader` for why a large
        // title is not an option on this OS with a custom face, and the body
        // above for why the page does not need one.
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable {
            move.start()
            await family.load()
            await store.load(fresh: true)
            daydream.seed(store.payload?.daydream)
            await alerts.refresh()
            await connections.refresh()
            if companion.paired { await companion.sync() }
        }
        .toolbar {
            // The date, where the page title used to carry it.
            ToolbarItem(placement: .topBarLeading) {
                Text(dateLine.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel(fullDate)
            }
            ToolbarItem(placement: .principal) { SRBarMark() }
            // The bell is the site's inbox, which is the owner's.
            if access.current.owner {
                ToolbarItem(placement: .topBarTrailing) {
                    TodayBell(unread: alerts.unread, active: onScreen && scenePhase == .active) {
                        SRHaptic.tap()
                        router.openAlerts()
                    }
                }
            }
            // Settings live in More. Without a More (a member with four
            // places or fewer) the cog stays here, or there would be no way in.
            if !access.allows(.more) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { SRHaptic.tap(); router.openSettings() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("open-settings")
                }
            }
        }
        .task {
            // The Watch's health figures and Today's first alerts come from
            // this store's payload — no second request.
            WatchBridge.shared.attach(today: store)
            move.start()
            // Not awaited before Today's own request: the family is a glance, and
            // the first paint must not wait on a second server.
            Task { await family.load() }
            await store.load()
            daydream.seed(store.payload?.daydream)
            await connections.reconcile(with: store.payload?.connections)
            // Then keep the day's numbers moving for as long as Today is on
            // screen. The task is cancelled when the tab goes away and starts
            // again, with a fresh read, when it comes back.
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled else { break }
                move.start()
                await store.load()
                daydream.seed(store.payload?.daydream)
                    await family.load()
            }
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            move.start()
            Task {
                await store.load()
                    await family.load()
            }
        }
        // The companion just put new health data on the site: re-read, past
        // the site's cache, so recovery and readiness reflect it.
        .onChange(of: companion.lastUpload) { _, _ in
            Task { await store.load(fresh: true) }
        }
        .overlay(alignment: .bottom) {
            if let message = store.message { SRBanner(text: message, tone: SR.error) }
        }
        .sheet(item: $opened) { alert in
            NavigationStack {
                AlertDetailScreen(alert: alert, alerts: alerts) {
                    withAnimation(.snappy) { alerts.clearFromToday([alert.id]) }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { opened = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    /// "SUN 27 SEP" in the bar: short enough to sit beside the mark and the
    /// two buttons at any width a phone has.
    private var dateLine: String {
        Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// What VoiceOver says for it: "Sunday 27 September".
    private var fullDate: String {
        Date().formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    // MARK: - Cards

    /// Before the companion is paired the app cannot know who is holding it,
    /// so it offers only the pairing every person needs.
    private var companionCard: some View {
        SRCard(accented: true) {
            VStack(alignment: .leading, spacing: 12) {
                SRSectionLabel(text: "Not connected")
                Text("Connect this iPhone")
                    .font(SR.Text.display())
                    .foregroundStyle(SR.ink)
                Text("Pair with the companion to upload from Apple Health. What else appears here is up to the account it pairs as.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { SRHaptic.tap(); router.openSettings(.connections) } label: {
                    SRButtonLabel(title: "Connect", icon: "qrcode.viewfinder", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityLabel("CONNECT")
                .padding(.top, 4)
            }
        }
    }

    private var connectCard: some View {
        SRCard(accented: true) {
            VStack(alignment: .leading, spacing: 12) {
                SRSectionLabel(text: "Not connected")
                Text("Connect this iPhone")
                    .font(SR.Text.display())
                    .foregroundStyle(SR.ink)
                Text("Pair with strangeramblings.com to read your threads, the news desk and your health figures here.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { SRHaptic.tap(); router.openSettings(.connections) } label: {
                    SRButtonLabel(title: "Connect", icon: "qrcode.viewfinder", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityLabel("CONNECT")
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Tiles

    @ViewBuilder
    private func tile(_ kind: TodayTile) -> some View {
        switch kind {
        case .ask: askTile
        case .health: healthTile
        case .daydream: daydreamTile
        case .games: gamesTile
        }
    }

    /// A new thread with the keyboard up. The one filled control on Today.
    private var askTile: some View {
        Button {
            SRHaptic.tap()
            router.ask("")
        } label: {
            TodayAskTile()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask jkai")
        .accessibilityIdentifier("today-ask")
    }

    /// The three rings — Move, Recovery, Readiness — and the verdict. One tap
    /// into the Health tab, which has the reasoning behind the numbers.
    private var healthTile: some View {
        let health = store.payload?.health
        let vitals = TodayVital.make(health: health, move: move.reading)
        let readiness = vitals.first { $0.key == "readiness" }
        let others = vitals.filter { $0.key != "readiness" }
        // "Primed · Move 76%": the verdict, then as much as fits.
        var parts: [String] = []
        if let caption = readiness?.caption { parts.append(caption) }
        parts += others.map { "\($0.label) \($0.value)" }
        let subline = (health?.isMock ?? false) ? "Demonstration figures" : parts.joined(separator: " · ")
        return Button {
            SRHaptic.tap()
            router.show(.health)
        } label: {
            TodayTileCard(
                kicker: "Health",
                title: readiness.map { "Readiness \($0.value)" } ?? "Readiness",
                subline: subline
            ) {
                TodayRings(vitals: vitals).frame(width: 68, height: 68)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health. " + vitals.map(\.spoken).joined(separator: ". "))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens Health")
        .accessibilityIdentifier("today-health")
    }

    /// Its own view, watching the notes: a rating or a re-read redraws the
    /// tile, not the whole of Today.
    private var daydreamTile: some View {
        Button {
            SRHaptic.tap()
            router.openDaydream()
        } label: {
            TodayDaydreamTile()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-daydream")
    }

    /// Its own view, watching the lobby: the invite poll redraws the tile,
    /// not the whole of Today.
    private var gamesTile: some View {
        Button {
            SRHaptic.tap()
            router.show(.games)
        } label: {
            TodayGamesTile()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-games")
    }

    /// The wire's top story, not a list: the News tab has the rest, and "5
    /// new" beside the heading is the way there.
    private func newsCard(_ news: TodayNews, story: TodayNews.Story) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SRSectionLabel(text: "On the wire")
                if news.unseen > 0 {
                    Button {
                        SRHaptic.tap()
                        router.show(.news)
                    } label: {
                        Text("\(news.unseen) new")
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.accentInk)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(news.unseen) new stories")
                }
            }
            .padding(.horizontal, 4)
            Button {
                SRHaptic.tap()
                router.show(.news)
            } label: {
                SRCard(interactive: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(story.sourceLabel.uppercased())
                            .font(SR.Text.label())
                            .tracking(1)
                            .foregroundStyle(SR.inkMuted)
                        Text(story.title)
                            .font(SR.Text.display(20))
                            .foregroundStyle(SR.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today-news")
        }
    }

    /// Sync now, as a quiet glass button at the foot of the page.
    private var syncAction: some View {
        Button {
            SRHaptic.tap()
            Task { await companion.sync() }
        } label: {
            SRButtonLabel(title: companion.busy ? "Syncing…" : "Sync now", icon: "arrow.triangle.2.circlepath", fill: true)
        }
        .srButton(.regular)
        .controlSize(.large)
        .disabled(companion.busy)
        .accessibilityIdentifier("today-sync")
    }

    private var syncFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(companion.message)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sync-status")
            if let last = companion.lastUpload {
                Text("Last upload \(last.formatted(date: .omitted, time: .shortened))")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}
