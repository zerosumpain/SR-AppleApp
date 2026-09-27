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
/// (what the loop noticed) and Games — then the alerts, the workflows, the
/// wire, and Sync at the foot. An urgent alert pins itself under the bar.
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
    /// Read AFTER Today's own request, never beside it — the card is a
    /// nudge, and the first paint must not wait on the workflow list.
    @StateObject private var flows = FlowAttentionStore()
    /// Today's Move ring, live from Apple Health on this phone.
    @StateObject private var move = MoveRingStore()
    @ObservedObject private var noticed = NoticedFeedback.shared
    @ObservedObject private var daydream = DaydreamStore.shared
    @EnvironmentObject private var games: GamesStore
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
                    // Everything else the owner is owed, as one list, below
                    // the fold on a phone: the inbox and the workflows.
                    if access.current.owner { upNext }
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
        .animation(.snappy, value: TodayAlerts.urgent(in: alerts.recent, dismissed: waved)?.id)
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
            await flows.load()
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
                    TodayBell(unread: alerts.unread) { SRHaptic.tap(); router.openAlerts() }
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
            await flows.load()
            // Then keep the day's numbers moving for as long as Today is on
            // screen. The task is cancelled when the tab goes away and starts
            // again, with a fresh read, when it comes back.
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled else { break }
                move.start()
                await store.load()
                daydream.seed(store.payload?.daydream)
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

    /// Unrated notes: what the tile counts as new. A rated one leaves the
    /// count a few seconds after the rating saves.
    private var freshNotes: [DaydreamNote] {
        daydream.notes.filter(noticed.isShowing)
    }

    /// What the daydream loop noticed, as a door: the count and the newest
    /// title. The notes themselves open in their own page, in More.
    private var daydreamTile: some View {
        let fresh = freshNotes
        let title = fresh.isEmpty ? "All caught up" : fresh.count == 1 ? "1 new note" : "\(fresh.count) new notes"
        return Button {
            SRHaptic.tap()
            router.openDaydream()
        } label: {
            TodayTileCard(kicker: "Daydream", title: title, subline: (fresh.first ?? daydream.notes.first)?.title) {
                TodayTileGlyph(symbol: "sparkles", tone: SR.accentInk, count: fresh.count)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daydream, \(title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("today-daydream")
    }

    /// An invitation first, then a game in progress, then the shelf.
    private var gamesTile: some View {
        let invite = games.invites.first
        let title: String
        let subline: String?
        if let invite {
            title = games.invites.count == 1 ? "1 invitation" : "\(games.invites.count) invitations"
            subline = "\(invite.hostName) · \(GameNames.title(invite.game))"
        } else if !games.rooms.isEmpty {
            title = games.rooms.count == 1 ? "1 in progress" : "\(games.rooms.count) in progress"
            subline = games.rooms.first.map { GameNames.title($0.game) }
        } else {
            title = "Play together"
            subline = "\(GameKind.allCases.count) quick games"
        }
        return Button {
            SRHaptic.tap()
            router.show(.games)
        } label: {
            TodayTileCard(kicker: "Games", title: title, subline: subline) {
                TodayTileGlyph(symbol: "gamecontroller.fill", tone: SR.accent, count: games.invites.count)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Games, \(title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("today-games")
        .task { if games.lobby == nil { await games.load() } }
    }

    private var alertRows: [TodayAlerts.Latest] {
        TodayAlerts.rows(
            recent: alerts.recent,
            latest: store.payload?.alerts?.latest ?? [],
            cleared: alerts.clearedFromToday
        )
    }

    /// Up next: the newest few alerts and the workflows, as ONE
    /// grouped list rather than a card each. A tap on an alert opens it in
    /// full; the cross takes it off Today. The bell in the bar is the way into
    /// the inbox. Clearing is Today's alone — the Alerts screen keeps
    /// everything.
    private var upNext: some View {
        let rows = alertRows
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SRSectionLabel(
                    text: "Up next",
                    trailing: alerts.unread > 0 ? "\(alerts.unread) unread" : nil
                )
                if !rows.isEmpty {
                    Button {
                        SRHaptic.select()
                        // Everything the phone knows of, not just the rows on
                        // show — otherwise the next three slide up and the list
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
                            .foregroundStyle(SR.accentDeep)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear all alerts from Today")
                    .accessibilityIdentifier("today-alerts-clear-all")
                }
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    HStack(spacing: 14) {
                        rowIcon("bell.slash", tone: SR.inkMuted)
                        Text("Nothing to report.")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                        Spacer()
                    }
                    .padding(.vertical, SR.rowPadding)
                    .frame(minHeight: SR.tapTarget)
                    .accessibilityElement(children: .combine)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { rowDivider }
                        alertRow(row)
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .opacity.combined(with: .move(edge: .trailing))
                            ))
                    }
                }
                if flows.loaded {
                    rowDivider
                    flowsRow
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .srGlassCard(.paper)
        }
    }

    /// Between two rows of Up next, starting where the text does.
    private var rowDivider: some View {
        Rectangle().fill(SR.divider).frame(height: 1).padding(.leading, 48)
    }

    /// The glyph at a row's leading edge, on a soft square of its own tone.
    private func rowIcon(_ symbol: String, tone: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tone)
            .frame(width: 34, height: 34)
            .background(tone.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }

    /// The whole alert, from the inbox the phone holds when it has it — Today's
    /// own rows carry no body.
    private func open(_ row: TodayAlerts.Latest) {
        SRHaptic.tap()
        opened = alerts.recent.first { $0.id == row.id } ?? SiteAlert(latest: row)
    }

    private func alertRow(_ row: TodayAlerts.Latest) -> some View {
        let severe = row.severity == "alert" || row.severity == "high"
        let tone = severe ? SR.error : row.severity == "warn" ? SR.warn : SR.accentInk
        return HStack(alignment: .center, spacing: 4) {
            Button { open(row) } label: {
                HStack(alignment: .center, spacing: 14) {
                    rowIcon(severe ? "exclamationmark.triangle" : "bell", tone: tone)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(SR.Text.title())
                            .foregroundStyle(SR.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(alertLine(row))
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                    }
                    Spacer(minLength: 6)
                }
                .padding(.vertical, SR.rowPadding)
                .frame(minHeight: SR.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(shortAgo(row.createdAt).isEmpty ? row.title : "\(row.title), \(shortAgo(row.createdAt)) ago")
            .accessibilityHint("Opens the alert")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("today-alert-open-\(row.id)")

            Button {
                SRHaptic.select()
                withAnimation(.snappy) { alerts.clearFromToday([row.id]) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SR.inkMuted)
                    // The mark is small so the row stays a row; the target
                    // round it is not.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(row.title)")
            .accessibilityIdentifier("today-alert-clear-\(row.id)")
        }
        .accessibilityElement(children: .contain)
    }

    /// "Alert · 12m ago" — or the category alone for one with no time.
    private func alertLine(_ row: TodayAlerts.Latest) -> String {
        let kind: String = row.category.isEmpty ? "Alert" : row.category.prefix(1).uppercased() + String(row.category.dropFirst())
        let ago = shortAgo(row.createdAt)
        return ago.isEmpty ? kind : "\(kind) · \(ago) ago"
    }

    /// The workflows in one row: what runs next, and how many are working.
    /// One tap to the Flows tab.
    private var flowsRow: some View {
        let stats = flows.stats(now: Date())
        let health: String = stats.failing > 0
            ? "\(stats.working) working, \(stats.failing) not"
            : "\(stats.working) working"
        // "Next at 07:00 · 5 working, 1 not".
        let next: String? = stats.next.map { "Next at \(FlowStats.when($0.at, now: Date()))" }
        let subline: String = [next, health].compactMap { $0 }.joined(separator: " · ")
        return Button {
            SRHaptic.tap()
            router.show(.flows)
        } label: {
            HStack(spacing: 14) {
                rowIcon("point.3.connected.trianglepath.dotted", tone: stats.failing > 0 ? SR.error : SR.good)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.next?.title ?? "Nothing scheduled")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(subline)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SR.inkGhost)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, SR.rowPadding)
            .frame(minHeight: SR.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-flows")
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
