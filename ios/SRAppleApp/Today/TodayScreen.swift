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
/// Under glass the screen is a stack of lifted sheets on a warm ground: the
/// date and the headline in the page, three rings for the body (Move,
/// Recovery, Readiness), what the daydream loop noticed, an "Ask jkai" field
/// that is one tap from a fresh thread, then the alerts, the workflows and the
/// wire. Nothing here is the only place to read anything.
///
/// No "carry on" card for the last thread: the Chat tab is one tap away on the
/// bar and opens on that list.
struct TodayScreen: View {
    @ObservedObject var companion: Companion
    @ObservedObject var alerts: AlertStore
    @ObservedObject var site: SitePairingModel
    @ObservedObject var family: FamilyStore
    @StateObject private var store = TodayStore()
    /// Read AFTER Today's own request, never beside it — the card is a
    /// nudge, and the first paint must not wait on the workflow list.
    @StateObject private var flows = FlowAttentionStore()
    /// Today's Move ring, live from Apple Health on this phone.
    @StateObject private var move = MoveRingStore()
    @ObservedObject private var noticed = NoticedFeedback.shared
    /// What this person may use. The owner's cards (the site's figures,
    /// alerts, workflows, what the loop noticed) are not drawn for anybody
    /// else — their endpoints would only refuse a member.
    @ObservedObject private var access = AccessStore.shared
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var connections: ConnectionsStore
    @Environment(\.scenePhase) private var scenePhase

    /// How often the numbers are re-read while Today is on screen. Readiness
    /// and recovery move when a sync lands on the site; five minutes is often
    /// enough to catch that and rare enough to cost nothing.
    static let refreshInterval: Duration = .seconds(300)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SRPageHeader(kicker: dateLine, title: greeting)
                    .padding(.horizontal, SR.gutter)
                    .padding(.top, 4)

                if ownerSite {
                    vitalsCard
                        .padding(.horizontal, SR.gutter)
                }

                // Everyone, on a map, one tap from the Family tab. Over the
                // companion pairing, so a family member without the site's
                // sees it too — if the owner gave them the family. Draws
                // nothing until there is somebody to pin.
                if access.current.family {
                    FamilyMiniMap(store: family) {
                        router.show(.family)
                    }
                    .padding(.horizontal, SR.gutter)
                }

                // What the daydream loop noticed, straight under the body's
                // numbers: the notes are the part of Today that is an opinion.
                // A rated note leaves a few seconds after the rating saves.
                if ownerSite, !visibleNotes.isEmpty {
                    NoticedCard(notes: visibleNotes)
                        .padding(.horizontal, SR.gutter)
                }

                VStack(alignment: .leading, spacing: 22) {
                    if access.current.owner && !site.paired {
                        // The owner's QR. A member's phone pairs itself, and a
                        // member with neither chat nor news has nothing to pair.
                        connectCard
                    } else if !companion.paired && !access.current.owner {
                        // Nobody knows who this is yet: the companion is where
                        // that answer comes from.
                        companionCard
                    } else {
                        if access.current.chat && site.paired { askField }
                        if access.current.owner {
                            alertsCard
                            if flows.loaded { flowsCard }
                        }
                        if access.current.news, let news = store.payload?.news, !news.stories.isEmpty { newsCard(news) }
                        quickActions
                    }
                    syncFooter
                }
                .padding(.horizontal, SR.gutter)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .srGround(.warm)
        .navigationTitle("Today")
        // Inline, and the title itself is replaced by the `sr.` mark: the page
        // carries the headline (see `SRPageHeader` for why a large title is not
        // an option on this OS with a custom face).
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable {
            move.start()
            await family.load()
            await store.load(fresh: true)
            await alerts.refresh()
            await connections.refresh()
            await flows.load()
            if companion.paired { await companion.sync() }
        }
        .toolbar {
            ToolbarItem(placement: .principal) { SRBarMark() }
            // The bell is the site's inbox, which is the owner's.
            if access.current.owner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { SRHaptic.tap(); router.openAlerts() } label: {
                        Image(systemName: alerts.unread > 0 ? "bell.badge" : "bell")
                    }
                    .accessibilityLabel(alerts.unread > 0 ? "Alerts, \(alerts.unread) unread" : "Alerts")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { SRHaptic.tap(); router.openSettings() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("open-settings")
            }
        }
        .task {
            move.start()
            // Not awaited before Today's own request: the map is a glance, and
            // the first paint must not wait on a second server.
            Task { await family.load() }
            await store.load()
            await connections.reconcile(with: store.payload?.connections)
            await flows.load()
            // Then keep the day's numbers moving for as long as Today is on
            // screen. The task is cancelled when the tab goes away and starts
            // again, with a fresh read, when it comes back.
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled else { break }
                move.start()
                await store.load()
                await flows.load()
                await family.load()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            move.start()
            Task {
                await store.load()
                await flows.load()
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
    }

    // MARK: - Header

    private var dateLine: String {
        Date().formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    /// A time of day rather than a tab name — the tab bar already says where
    /// you are, so the page can say something.
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Morning."
        case 12..<18: return "Afternoon."
        case 18..<23: return "Evening."
        default: return "Late one."
        }
    }

    // MARK: - Cards

    /// The owner's site lane: paired, and the owner. A member may be
    /// site-paired now (for chat or news) and still see none of this.
    private var ownerSite: Bool { access.current.owner && site.paired }

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

    /// Move, Recovery and Readiness as three small rings. The whole card is
    /// one tap into the Health tab, which has the reasoning behind them.
    private var vitalsCard: some View {
        let health = store.payload?.health
        return Button {
            SRHaptic.tap()
            router.show(.health)
        } label: {
            TodayVitalsCard(
                vitals: TodayVital.make(health: health, move: move.reading),
                updated: health.flatMap { updatedLine($0.generatedAt) },
                isMock: health?.isMock ?? false
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-health")
        .accessibilityHint("Opens Health")
    }

    private var visibleNotes: [DaydreamNote] {
        (store.payload?.daydream?.notes ?? []).filter(noticed.isShowing)
    }

    private func updatedLine(_ iso: String) -> String? {
        let ago = shortAgo(iso)
        return ago.isEmpty ? nil : "\(ago) ago"
    }

    /// A field that is really a button: tap it and a new thread opens with the
    /// keyboard up. The shape is the composer's, so the thumb learns it once.
    private var askField: some View {
        Button {
            SRHaptic.tap()
            router.ask("")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SR.accent)
                Text("Ask jkai anything…")
                    .font(SR.Text.body())
                    .foregroundStyle(SR.inkMuted)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SR.paper)
                    .frame(width: 34, height: 34)
                    .background(SR.accent, in: Circle())
            }
            .padding(.leading, 18)
            .padding(.trailing, 7)
            .frame(minHeight: 50)
            .srGlass(.paper, in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask jkai")
        .accessibilityIdentifier("today-ask")
    }

    private var alertRows: [TodayAlerts.Latest] {
        TodayAlerts.rows(
            recent: alerts.recent,
            latest: store.payload?.alerts?.latest ?? [],
            cleared: alerts.clearedFromToday
        )
    }

    /// The newest few alerts, each one tap off this card. The bell in the bar
    /// is the way into the inbox, so a row here does not duplicate it.
    /// Clearing is Today's alone — the Alerts screen keeps everything.
    private var alertsCard: some View {
        let rows = alertRows
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SRSectionLabel(
                    text: "Alerts",
                    trailing: alerts.unread > 0 ? "\(alerts.unread) unread" : nil
                )
                if !rows.isEmpty {
                    Button {
                        SRHaptic.select()
                        // Everything the phone knows of, not just the rows on
                        // show — otherwise the next three slide up and the card
                        // looks as if the clear did not take.
                        let ids = (store.payload?.alerts?.latest.map(\.id) ?? []) + alerts.recent.map(\.id)
                        withAnimation(.snappy) { alerts.clearFromToday(ids) }
                        // And the bell with it: a clear that left the badge up
                        // would be half a clear.
                        Task { await alerts.markAllRead() }
                    } label: {
                        Text("CLEAR ALL")
                            .font(SR.Text.label())
                            .tracking(1.2)
                            .foregroundStyle(SR.accent)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear all alerts from Today")
                    .accessibilityIdentifier("today-alerts-clear-all")
                }
            }
            .padding(.horizontal, 4)

            SRCard {
                if rows.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.slash")
                            .foregroundStyle(SR.inkMuted)
                        Text("Nothing to report.")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(rows) { row in
                            alertRow(row)
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .opacity.combined(with: .move(edge: .trailing))
                                ))
                        }
                    }
                }
            }
        }
    }

    private func alertRow(_ row: TodayAlerts.Latest) -> some View {
        HStack(alignment: .top, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(row.severity == "alert" || row.severity == "high" ? SR.error : row.severity == "warn" ? SR.warn : SR.inkGhost)
                    .frame(width: 7, height: 7)
                    .padding(.top, 6)
                Text(row.title)
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                Text(shortAgo(row.createdAt))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .padding(.top, 2)
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(shortAgo(row.createdAt).isEmpty ? row.title : "\(row.title), \(shortAgo(row.createdAt)) ago")

            Button {
                SRHaptic.select()
                withAnimation(.snappy) { alerts.clearFromToday([row.id]) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SR.inkMuted)
                    // The mark is small so the row stays a row; the target
                    // round it is not.
                    .frame(width: 40, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(row.title)")
            .accessibilityIdentifier("today-alert-clear-\(row.id)")
        }
        .accessibilityElement(children: .contain)
    }

    /// The workflows as three numbers: how many are working, how many are
    /// not, and which one runs next and when. One tap to the Flows tab.
    private var flowsCard: some View {
        let stats = flows.stats(now: Date())
        return VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Workflows")
                .padding(.horizontal, 4)
            Button {
                SRHaptic.tap()
                router.show(.flows)
            } label: {
                SRCard(interactive: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            flowNumber(stats.working, label: "Working", tone: SR.good)
                            flowNumber(stats.failing, label: "Not working", tone: stats.failing > 0 ? SR.error : SR.inkMuted)
                        }
                        Rectangle().fill(SR.divider).frame(height: 1)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "clock")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SR.accent)
                            if let next = stats.next {
                                Text("Next: \(next.title)")
                                    .font(SR.Text.secondary(15))
                                    .foregroundStyle(SR.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text("@ \(FlowStats.when(next.at, now: Date()))")
                                    .font(SR.Text.mono())
                                    .foregroundStyle(SR.inkMuted)
                                    .fixedSize()
                            } else {
                                Text("Nothing scheduled")
                                    .font(SR.Text.secondary(15))
                                    .foregroundStyle(SR.inkMuted)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today-flows")
        }
    }

    private func flowNumber(_ count: Int, label: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)")
                .font(SR.Text.figure(28))
                .foregroundStyle(tone)
            Text(label.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func newsCard(_ news: TodayNews) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "On the wire", trailing: news.unseen > 0 ? "\(news.unseen) new" : nil)
                .padding(.horizontal, 4)
            Button {
                SRHaptic.tap()
                router.show(.news)
            } label: {
                SRCard(interactive: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(news.stories.enumerated()), id: \.element.id) { index, story in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                // The ranked-moves numeral, kept: a position is
                                // the one thing a wire has that a feed does not.
                                Text("\(index + 1)")
                                    .font(SR.Text.display(20))
                                    .foregroundStyle(SR.accent)
                                    .frame(width: 22, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(story.title)
                                        .font(SR.Text.secondary(15))
                                        .foregroundStyle(SR.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(story.sourceLabel.uppercased())
                                        .font(SR.Text.mono())
                                        .tracking(1)
                                        .foregroundStyle(SR.inkMuted)
                                }
                            }
                            .padding(.vertical, 10)
                            if index < news.stories.count - 1 {
                                Rectangle().fill(SR.divider).frame(height: 1).padding(.leading, 34)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var quickActions: some View {
        SRGlassGroup(spacing: SR.cardGap) {
            HStack(spacing: SR.cardGap) {
                if access.current.chat && site.paired {
                    QuickAction(title: "New thread", icon: "square.and.pencil") {
                        router.ask("")
                    }
                }
                QuickAction(title: companion.busy ? "Syncing…" : "Sync now", icon: "arrow.triangle.2.circlepath") {
                    Task { await companion.sync() }
                }
            }
        }
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

/// A glass tile with a glyph and a word. Two across.
struct QuickAction: View {
    let title: String
    let icon: String
    let run: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            run()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SR.accent)
                    .frame(width: 34, height: 34)
                    .background(SR.accent.opacity(0.12), in: Circle())
                Text(title.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.ink)
                    // Two lines rather than smaller type. "SYNCING…" at a large
                    // accessibility size does not fit on one, and the reader
                    // asked for it to be that size.
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SR.cardPadding)
            .frame(minHeight: 88, alignment: .leading)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 6, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
