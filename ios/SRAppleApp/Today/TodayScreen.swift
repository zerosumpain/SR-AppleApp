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
/// Every card is a summary that goes somewhere. Nothing here is the only place
/// to read anything.
struct TodayScreen: View {
    @ObservedObject var companion: Companion
    @ObservedObject var alerts: AlertStore
    @ObservedObject var site: SitePairingModel
    @StateObject private var store = TodayStore()
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !site.paired {
                    connectCard
                } else {
                    if let health = store.payload?.health { healthCard(health) }
                    alertsCard
                    if let thread = store.payload?.lastThread { threadCard(thread) }
                    if let news = store.payload?.news, !news.stories.isEmpty { newsCard(news) }
                    quickActions
                }
                syncFooter
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .srPaper()
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await store.load(fresh: true)
            await alerts.refresh()
            if companion.paired { await companion.sync() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { SRHaptic.tap(); router.openSettings() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("open-settings")
            }
        }
        .task { await store.load() }
        .overlay(alignment: .bottom) {
            if let message = store.message { SRBanner(text: message, tone: SR.error) }
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
                    Text("CONNECT")
                        .font(SR.Text.label())
                        .tracking(1.3)
                        .foregroundStyle(SR.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(SR.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func healthCard(_ health: TodayHealth) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Health", trailing: shortAgo(health.generatedAt))

            Button {
                SRHaptic.tap()
                router.show(.health)
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    if let readiness = health.readiness {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(Int(readiness.score.rounded()))")
                                .font(SR.Text.hero(44))
                                .foregroundStyle(SR.ink)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(readiness.label.uppercased())
                                    .font(SR.Text.label())
                                    .tracking(1.3)
                                    .foregroundStyle(SR.accent)
                                Text("Readiness").font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(SR.inkMuted)
                        }
                    }

                    SRTileGrid {
                        ForEach(health.figures) { figure in
                            FigureTile(figure: figure)
                        }
                    }

                    if health.isMock {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(SR.warn)
                            Text("Demonstration data — no real measurement in this window.")
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkSecondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(
                text: "Alerts",
                trailing: alerts.unread > 0 ? "\(alerts.unread) unread" : nil
            )

            Button {
                SRHaptic.tap()
                router.openAlerts()
            } label: {
                SRCard {
                    if let latest = store.payload?.alerts?.latest, !latest.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(latest) { row in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(row.severity == "alert" ? SR.error : row.severity == "warn" ? SR.warn : SR.inkGhost)
                                        .frame(width: 6, height: 6)
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

    @ViewBuilder
    private func threadCard(_ thread: TodayThread) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Carry on", trailing: shortAgo(thread.updatedAt))
            Button {
                SRHaptic.tap()
                router.show(.chat)
            } label: {
                SRCard(accented: true) {
                    HStack(spacing: 10) {
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
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func newsCard(_ news: TodayNews) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "On the wire", trailing: news.unseen > 0 ? "\(news.unseen) new" : nil)
            Button {
                SRHaptic.tap()
                router.show(.news)
            } label: {
                SRCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(news.stories) { story in
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
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var quickActions: some View {
        HStack(spacing: SR.cardGap) {
            QuickAction(title: "Ask jkai", icon: "bubble.left.and.text.bubble.right") {
                router.show(.chat)
            }
            QuickAction(title: companion.busy ? "Syncing…" : "Sync now", icon: "arrow.triangle.2.circlepath") {
                Task { await companion.sync() }
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
        .padding(.top, 4)
    }
}

/// A square-ish tap target with a glyph and a word. Two across.
struct QuickAction: View {
    let title: String
    let icon: String
    let run: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            run()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(SR.accent)
                Text(title.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SR.cardPadding)
            .frame(minHeight: 76, alignment: .leading)
            .background(SR.surface)
            .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
