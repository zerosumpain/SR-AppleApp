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

    /// Readiness and today's figures on the smoked slab, the way /health opens.
    /// The whole slab is one tap into the Health tab.
    @ViewBuilder
    private func healthHero(_ health: TodayHealth) -> some View {
        Button {
            SRHaptic.tap()
            router.show(.health)
        } label: {
            SRInkBand(kicker: "Health · Today", meta: updatedLine(health.generatedAt)) {
                if let readiness = health.readiness {
                    SRInkReadiness(readiness: readiness, donut: 96)
                } else {
                    Text(health.strap)
                        .font(SR.Text.body(15))
                        .foregroundStyle(SR.onInk(.note))
                        .fixedSize(horizontal: false, vertical: true)
                }

                SRTileGrid {
                    ForEach(health.figures) { figure in
                        InkFigureTile(figure: figure)
                    }
                }

                if health.isMock {
                    SRInkMockNote()
                }

                HStack(spacing: 6) {
                    Text("OPEN HEALTH")
                        .font(SR.Text.label())
                        .tracking(SR.inkLabelTracking)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(SR.accentOnDark)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-health")
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

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(
                text: "Alerts",
                trailing: alerts.unread > 0 ? "\(alerts.unread) unread" : nil
            )
            .padding(.horizontal, 4)

            Button {
                SRHaptic.tap()
                router.openAlerts()
            } label: {
                SRCard(interactive: true) {
                    if let latest = store.payload?.alerts?.latest, !latest.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(latest) { row in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(row.severity == "alert" ? SR.error : row.severity == "warn" ? SR.warn : SR.inkGhost)
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
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.slash")
                                .foregroundStyle(SR.inkMuted)
                            Text("Nothing to report.")
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkMuted)
                            Spacer()
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
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
