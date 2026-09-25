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
        guard client.isPaired, !loading else { return }
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
/// date and the headline in the page, the smoked readiness slab, an "Ask jkai"
/// field that is one tap from a fresh thread, then the alerts, the last thread
/// and the wire. Every card is a summary that goes somewhere. Nothing here is
/// the only place to read anything.
struct TodayScreen: View {
    @ObservedObject var companion: Companion
    @ObservedObject var alerts: AlertStore
    @ObservedObject var site: SitePairingModel
    @StateObject private var store = TodayStore()
    /// Read AFTER Today's own request, never beside it — the card is a
    /// nudge, and the first paint must not wait on the workflow list.
    @StateObject private var flows = FlowAttentionStore()
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var connections: ConnectionsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SRPageHeader(kicker: dateLine, title: greeting)
                    .padding(.horizontal, SR.gutter)
                    .padding(.top, 4)

                if site.paired, let health = store.payload?.health {
                    healthHero(health)
                }

                // What the daydream loop noticed, straight under the body's
                // numbers: the notes are the part of Today that is an opinion.
                if site.paired, let notes = store.payload?.daydream?.notes, !notes.isEmpty {
                    NoticedCard(notes: notes)
                        .padding(.horizontal, SR.gutter)
                }

                VStack(alignment: .leading, spacing: 22) {
                    if !site.paired {
                        connectCard
                    } else {
                        askField
                        alertsCard
                        if !flows.flows.isEmpty { flowsCard }
                        if let thread = store.payload?.lastThread { threadCard(thread) }
                        if let news = store.payload?.news, !news.stories.isEmpty { newsCard(news) }
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
            await store.load(fresh: true)
            await alerts.refresh()
            await connections.refresh()
            await flows.load()
            if companion.paired { await companion.sync() }
        }
        .toolbar {
            ToolbarItem(placement: .principal) { SRBarMark() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { SRHaptic.tap(); router.openAlerts() } label: {
                    Image(systemName: alerts.unread > 0 ? "bell.badge" : "bell")
                }
                .accessibilityLabel(alerts.unread > 0 ? "Alerts, \(alerts.unread) unread" : "Alerts")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { SRHaptic.tap(); router.openSettings() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("open-settings")
            }
        }
        .task {
            await store.load()
            await connections.reconcile(with: store.payload?.connections)
            await flows.load()
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

    /// Readiness and today's figures on one short smoked strip. The detail —
    /// the verdict's sentence, the sparklines, the movement — is a tap away on
    /// the Health tab; the first screen only has to say how the body is doing.
    @ViewBuilder
    private func healthHero(_ health: TodayHealth) -> some View {
        Button {
            SRHaptic.tap()
            router.show(.health)
        } label: {
            TodayHealthStrip(health: health, updated: updatedLine(health.generatedAt))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-health")
        .accessibilityHint("Opens Health")
    }

    private func updatedLine(_ iso: String) -> String? {
        let ago = shortAgo(iso)
        return ago.isEmpty ? nil : "Updated \(ago) ago"
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

    /// The newest few alerts, each one tap into the inbox and one tap off this
    /// card. Clearing is Today's alone — the Alerts screen keeps everything.
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
                    Button {
                        SRHaptic.tap()
                        router.openAlerts()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.slash")
                                .foregroundStyle(SR.inkMuted)
                            Text("Nothing to report.")
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkMuted)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(SR.inkGhost)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("No alerts. Open the inbox")
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
            Button {
                SRHaptic.tap()
                router.openAlerts()
            } label: {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(shortAgo(row.createdAt).isEmpty ? row.title : "\(row.title), \(shortAgo(row.createdAt)) ago")
            .accessibilityHint("Opens the inbox")

            Button {
                SRHaptic.select()
                withAnimation(.snappy) { alerts.clearFromToday([row.id]) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SR.inkMuted)
                    // The mark is small so the row stays a row; the target
                    // round it is not.
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear \(row.title) from Today")
            .accessibilityIdentifier("today-alert-clear-\(row.id)")
        }
        .accessibilityElement(children: .contain)
    }

    /// Workflows that failed or are stuck. One tap to the Flows tab, where
    /// they head the list.
    private var flowsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Workflows need attention", trailing: "\(flows.flows.count)")
                .padding(.horizontal, 4)
            Button {
                SRHaptic.tap()
                router.show(.flows)
            } label: {
                SRCard(accented: true, interactive: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(flows.flows.prefix(3)) { flow in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(SR.error)
                                    .padding(.top, 3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(flow.title)
                                        .font(SR.Text.secondary(15))
                                        .foregroundStyle(SR.ink)
                                        .lineLimit(1)
                                    if let reason = flow.attentionReason {
                                        Text(reason)
                                            .font(SR.Text.secondary(13))
                                            .foregroundStyle(SR.inkMuted)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                Spacer(minLength: 6)
                            }
                        }
                    }
                    .padding(.leading, 6)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today-flows")
        }
    }

    @ViewBuilder
    private func threadCard(_ thread: TodayThread) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Carry on", trailing: shortAgo(thread.updatedAt))
                .padding(.horizontal, 4)
            Button {
                SRHaptic.tap()
                router.show(.chat)
                router.chat.append(ThreadReference(id: thread.id))
            } label: {
                SRCard(accented: true, interactive: true) {
                    HStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(SR.accent)
                            .frame(width: 36, height: 36)
                            .background(SR.accent.opacity(0.12), in: Circle())
                        Text(thread.title?.isEmpty == false ? thread.title! : "Untitled thread")
                            .font(SR.Text.title())
                            .foregroundStyle(SR.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SR.inkMuted)
                    }
                    .padding(.leading, 6)
                }
            }
            .buttonStyle(.plain)
        }
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
                QuickAction(title: "New thread", icon: "square.and.pencil") {
                    router.ask("")
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

/// Today's health, as one short strip.
///
/// It used to be /health's opening band whole — the 96pt donut on its own
/// panel, the verdict's full sentence, a two-by-two of tiles and an "open
/// health" line — and on a phone that was the whole first screen before
/// anything the site had to say. The strip keeps the answer (the score, the
/// verdict, the four figures and which way each is going) and leaves the
/// reasoning on the Health tab, a tap away. Still smoked ink, so it still
/// reads as the body's part of the page.
struct TodayHealthStrip: View {
    let health: TodayHealth
    var updated: String? = nil

    /// Four, in the server's order. The strip is two lines of two; a fifth
    /// would be a third line for the sake of one number.
    private var figures: [HealthFigure] { Array(health.figures.prefix(4)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                if let readiness = health.readiness {
                    SRInkDonut(
                        fraction: readiness.score / 100,
                        score: "\(Int(readiness.score.rounded()))",
                        lineWidth: 6,
                        scoreSize: 19
                    )
                    .frame(width: 54, height: 54)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(health.readiness == nil ? "HEALTH · TODAY" : "HEALTH · READINESS")
                        .font(SR.Text.label())
                        .tracking(SR.inkLabelTracking)
                        .foregroundStyle(SR.accentOnDark)
                        .lineLimit(1)
                    if let readiness = health.readiness {
                        Text(readiness.label.uppercased())
                            .font(SR.Text.display(17))
                            .foregroundStyle(SR.onInk(.primary))
                            .lineLimit(2)
                    } else {
                        Text(health.strap)
                            .font(SR.Text.body(15))
                            .foregroundStyle(SR.onInk(.note))
                            .lineLimit(2)
                    }
                    if let updated {
                        Text(updated.uppercased())
                            .font(SR.Text.mono())
                            .tracking(1)
                            .foregroundStyle(SR.onInk(.unit))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SR.accentOnDark)
            }

            if !figures.isEmpty {
                Rectangle()
                    .fill(SR.onInk(.hairline))
                    .frame(height: 1)
                SRTileGrid {
                    ForEach(figures) { figure in
                        figureCell(figure)
                    }
                }
            }

            if health.isMock {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SR.accentOnDark)
                    Text("Demonstration data, not a measurement.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.onInk(.note))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            SRGrain(opacity: 0.05)
                .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
        }
        .srGlassCard(.ink, radius: SR.Glass.radius)
        .environment(\.colorScheme, .dark)
        .contentShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
        .padding(.horizontal, SR.Glass.bandInset)
        .accessibilityElement(children: .combine)
    }

    /// Label on the left, value on the right, one line: a figure and its
    /// direction, without the tile round it.
    private func figureCell(_ figure: HealthFigure) -> some View {
        let value = figure.inkValue
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(figure.label.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.onInk(.label))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(value.value)
                .font(SR.Text.figure(17))
                .foregroundStyle(SR.onInk(.primary))
                .lineLimit(1)
                .fixedSize()
            if let unit = value.unit {
                Text(unit)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.onInk(.unit))
                    .lineLimit(1)
                    .fixedSize()
            }
            if figure.deltaDisplay != nil, let improving = figure.improving {
                Image(systemName: figure.direction == "down" ? "arrow.down.right" : "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(improving ? SR.goodOnDark : SR.accentOnDark)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(figure.label): \(figure.displayWithUnit)"
            + (figure.deltaDisplay.map { ", \($0)" } ?? "")
            + (figure.improving == nil ? "" : figure.improving! ? ", improving" : ", worse")
        )
    }
}
