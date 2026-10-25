import SwiftUI

/// The hub: everything that is not a tab — News, Flows, Daydream, the family
/// boards — and Settings at the foot. Opened by the ⊞ at the top left of every
/// page (`SRHubButton`), the same for everyone (John, 2026-10-21: "one layout
/// for all"); there is no More tab.
///
/// Not iOS's More. That is a navigation controller wrapping each tab's own
/// `NavigationStack`, so a page opened from it had two bars and two back
/// buttons. The hub is pushed onto the tab you are on (`Router.openHub`), and
/// what it opens is pushed above it on the same stack: one bar, one back
/// button, the tab bar where it was.
///
/// A front page rather than a list of names: one card per place saying what
/// is in it. Games are a tab now, so their invitations are on the tab's badge
/// and page, not repeated here.
struct MoreScreen: View {
    /// What sits in More for this person, in bar order.
    let places: [Router.Tab]
    @ObservedObject var games: GamesStore
    /// Sync now lives here (and in Settings), off Today.
    @ObservedObject var companion: Companion
    @ObservedObject private var daydream = DaydreamStore.shared
    @ObservedObject private var feedback = NoticedFeedback.shared
    @ObservedObject private var commissions = CommissionStore.shared
    @ObservedObject private var steps = FamilyStepsStore.shared
    @ObservedObject private var tasks = FamilyTasksStore.shared
    @ObservedObject private var backlog = FamilyBacklogStore.shared
    @ObservedObject private var landgrab = LandgrabStore.shared
    @ObservedObject private var access = AccessStore.shared
    @ObservedObject private var wildmind = WildmindStore.shared
    @ObservedObject private var offline = OfflineSession.shared
    @EnvironmentObject private var router: Router
    @Environment(\.dynamicTypeSize) private var typeSize
    /// A 2×2 tile: half the width (~169pt on a 390pt phone) and a little
    /// taller, so the mark, the name, two lines and a status chip fit
    /// unclipped. Games and News are 1×2 — Today's tile height (~82pt).
    @ScaledMetric(relativeTo: .body) private var square: CGFloat = 190
    @ScaledMetric(relativeTo: .body) private var short: CGFloat = 82

    /// News, as a short door at the top of the hub for whoever has it
    /// (John, 2026-10-05). Games was its partner; it is a tab now.
    private var shortcuts: [Router.Tab] { [Router.Tab.news].filter { access.allows($0) } }

    var body: some View {
        ScrollView {
            // A plain stack: a handful of cards and one row need no laziness,
            // and a lazy stack whose last child (Settings) is measured at a
            // different height than it was estimated at loops at the bottom.
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                // Every tile the same size, so the page reads as a set of
                // doors rather than a list to scroll: Games and News short
                // (1×2), everything else square (2×2), two to a row. One
                // column at the accessibility text sizes, where a square
                // would clip its own words.
                let folded = typeSize.isAccessibilitySize
                VStack(spacing: SR.cardGap) {
                    if !shortcuts.isEmpty {
                        HStack(spacing: SR.cardGap) {
                            ForEach(shortcuts, id: \.self) { shortcut($0) }
                            if shortcuts.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                        }
                        .frame(height: folded ? nil : short)
                    }
                    ForEach(Array(rows(folded: folded).enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: SR.cardGap) {
                            ForEach(row, id: \.self) { tile($0) }
                            if row.count == 1 && !folded { Color.clear.frame(maxWidth: .infinity) }
                        }
                        .frame(height: folded ? nil : square)
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("more-screen")
        .srGround(.warm)
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SRBarMark() } }
        .task {
            if access.familyBoards {
                if steps.board == nil { await steps.load() }
                if tasks.board == nil { await tasks.load() }
                if backlog.board == nil { await backlog.load() }
                if landgrab.board == nil { await landgrab.load() }
            }
        }
        .srRefreshable {
            if access.familyBoards {
                await steps.load()
                await tasks.load()
                await backlog.load()
                await landgrab.load()
            }
        }
    }

    private func familyCard(_ page: FamilyPage) -> some View {
        Button {
            SRHaptic.tap()
            router.pushFromHub(page)
        } label: {
            switch page {
            case .steps:
                MoreCard(
                    icon: "figure.walk",
                    fill: SR.good,
                    title: "Steps",
                    blurb: "Today's family step board. Top spot is checked every fifteen minutes.",
                    status: steps.shown.flatMap(FamilySteps.place)
                )
            case .tasks:
                MoreCard(
                    icon: "checklist",
                    fill: SR.accentDeep,
                    title: "Tasks",
                    blurb: "Jobs for the family, with a reward when a parent confirms them.",
                    status: tasks.summary.flatMap { taskStatus($0) }
                )
            case .backlog:
                MoreCard(
                    icon: "tray.full",
                    fill: SR.accentInk,
                    title: "Backlog",
                    blurb: "Videos, links and ideas the family shared to watch or do together.",
                    status: backlog.board.flatMap(FamilyBacklogRules.status)
                )
            case .messages:
                MoreCard(
                    icon: "bubble.left.and.text.bubble.right",
                    fill: SR.accent,
                    title: "msg family",
                    blurb: "One line to everyone's phone, and their replies."
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("more-\(page.rawValue)")
    }

    private func taskStatus(_ summary: FamilyTasksSummary) -> String? {
        if summary.parent && summary.awaiting > 0 {
            return summary.awaiting == 1 ? "1 to confirm" : "\(summary.awaiting) to confirm"
        }
        return summary.toDo > 0 ? "\(summary.toDo) to do" : nil
    }

    private var toDecide: Int {
        daydream.toDecide(feedback: feedback, commissions: commissions)
    }

    /// What sits in More, in order, as tiles.
    enum Item: Hashable {
        case daydream, wildmind, steps, tasks, backlog, messages, landgrab, travel, offline, sync, settings
        case place(Router.Tab)
    }

    private var items: [Item] {
        var all: [Item] = []
        // The daydream loop is the owner's, over the site, and so is the
        // Wildmind valley beside it.
        if AccessStore.ownerSite { all += [.daydream, .wildmind] }
        // The family's step board and task list: pages, not tabs, for
        // everyone with the family and the site credential.
        if access.familyBoards { all += [.steps, .tasks, .backlog] }
        // "msg family" lives in Chat; somebody without Chat finds it here.
        if access.familyBoards && !access.allows(.chat) { all.append(.messages) }
        // Landgrab, once its board has somebody on it — hidden, like the
        // section on Steps, when the site says no or has nothing.
        if access.familyBoards && landgrab.visible { all.append(.landgrab) }
        // News is the short door above the grid, not a square.
        all += places.filter { $0 != .news }.map(Item.place)
        // The Travel kit: translation, signs, phrases, money, the way back.
        // Everyone's, like Play nearby — it all runs on the phone.
        all.append(.travel)
        // Play nearby: offline games over Bluetooth or a hotspot. Everyone's —
        // it never touches the site, so no pairing and no games access needed.
        all.append(.offline)
        // Sync now and Settings last, tiles like the rest.
        all += [.sync, .settings]
        return all
    }

    /// Pairs, for the grid. A plain stack of rows rather than a lazy grid: a
    /// lazy container whose last child is measured at a different height than
    /// it was estimated at loops at the bottom.
    private func rows(folded: Bool) -> [[Item]] {
        if folded { return items.map { [$0] } }
        return stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
    }

    /// News, one unit tall and two across, as Today's tiles are.
    private func shortcut(_ place: Router.Tab) -> some View {
        Button {
            SRHaptic.tap()
            router.pushFromHub(place)
        } label: {
            TodayTileCard(title: place == .games ? "Games" : "News") {
                TodayTileGlyph(
                    symbol: place == .games ? "gamecontroller.fill" : "newspaper.fill",
                    tone: place == .games ? SR.accent : SR.accentInk,
                    count: place == .games ? games.invites.count : 0
                )
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("more-\(place.rawValue)")
    }

    @ViewBuilder
    private func tile(_ item: Item) -> some View {
        switch item {
        case .daydream:
            Button {
                SRHaptic.tap()
                router.pushFromHub(Router.MorePage.daydream)
            } label: {
                MoreCard(
                    icon: "sparkles",
                    fill: SR.accentInk,
                    title: "Daydream",
                    blurb: "What jkai spotted in your days, and your call on each.",
                    status: toDecide > 0 ? "\(toDecide) to decide" : nil
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("more-daydream")
        case .wildmind:
            Button {
                SRHaptic.tap()
                router.pushFromHub(Router.MorePage.wildmind)
            } label: {
                MoreCard(
                    icon: "mountain.2",
                    fill: SR.good,
                    title: "Wildmind",
                    blurb: "Two Claude minds in a valley, inventing whatever they need.",
                    // The day of this life, once the page has been opened —
                    // More does not ask the valley on its own.
                    status: wildmind.answer?.snapshot?.time.day.map { "Day \($0)" }
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("more-wildmind")
        case .steps: familyCard(.steps)
        case .tasks: familyCard(.tasks)
        case .backlog: familyCard(.backlog)
        case .messages: familyCard(.messages)
        case .landgrab:
            Button {
                SRHaptic.tap()
                if let week = landgrab.board.flatMap(Landgrab.currentWeek) {
                    router.pushFromHub(LandgrabMapRef(week: week.start))
                }
            } label: {
                MoreCard(
                    icon: "hexagon.fill",
                    fill: SR.accent,
                    title: "Landgrab",
                    blurb: "Ground the family won and lost this week, and the outings that took it.",
                    status: Landgrab.moreStatus(landgrab.board)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("more-landgrab")
        case .place(let place):
            Button {
                SRHaptic.tap()
                router.pushFromHub(place)
            } label: {
                MorePlaceCard(place: place, games: games)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("more-\(place.rawValue)")
        case .travel:
            Button {
                SRHaptic.tap()
                router.pushFromHub(TravelKitRef())
            } label: {
                MoreCard(
                    icon: "airplane",
                    fill: SR.accentDeep,
                    title: "Travel kit",
                    blurb: "Live translation, signs, phrases, money and the way back."
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("more-travel")
        case .offline:
            Button {
                SRHaptic.tap()
                router.pushFromHub(OfflineGamesRef())
            } label: {
                MoreCard(
                    icon: "dot.radiowaves.left.and.right",
                    fill: SR.accent,
                    title: "Play nearby",
                    blurb: "Games for phones in the same room. No internet needed.",
                    status: offline.inRoom ? "In a room" : nil
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("more-offline")
        case .sync:
            Button {
                SRHaptic.tap()
                Task { await companion.sync() }
            } label: {
                MoreCard(
                    icon: "arrow.triangle.2.circlepath",
                    fill: SR.good,
                    title: companion.busy ? "Syncing…" : "Sync now",
                    blurb: companion.message,
                    status: companion.lastUpload.map { "Last upload \($0.formatted(date: .omitted, time: .shortened))" }
                )
            }
            .buttonStyle(.plain)
            .disabled(companion.busy)
            .accessibilityIdentifier("more-sync")
        case .settings:
            Button {
                SRHaptic.tap()
                router.openSettings()
            } label: {
                MoreCard(
                    icon: "gearshape.fill",
                    fill: SR.inkSecondary,
                    title: "Settings",
                    blurb: "Notifications, connections, Apple Health and this iPhone."
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("open-settings")
        }
    }
}

/// Navigation value for the hub, pushed onto whichever tab it is opened on.
struct HubRef: Hashable {}

/// The ⊞ at the top left of every tab's first page: the hub, one tap away,
/// in the same place on every page and for everyone.
struct SRHubButton: View {
    @EnvironmentObject private var router: Router

    var body: some View {
        Button {
            SRHaptic.tap()
            router.openHub()
        } label: {
            Image(systemName: "square.grid.2x2")
        }
        .accessibilityLabel("More")
        .accessibilityHint("News, Flows, the family boards and Settings")
        .accessibilityIdentifier("open-hub")
    }
}

/// One place's card: an icon on its own colour, the name, what is in it now.
struct MorePlaceCard: View {
    let place: Router.Tab
    @ObservedObject var games: GamesStore

    var body: some View {
        // No row of game marks: the Games page lists them, once. Ten marks
        // also ran past the edge of a phone.
        MoreCard(icon: icon, fill: fill, title: title, blurb: blurb, status: status)
    }

    private var title: String {
        switch place {
        case .games: return "Games"
        case .news: return "News"
        case .flows: return "Flows"
        default: return place.rawValue.capitalized
        }
    }

    private var icon: String {
        switch place {
        case .games: return "gamecontroller.fill"
        case .news: return "newspaper.fill"
        case .flows: return "point.3.connected.trianglepath.dotted"
        default: return "square.grid.2x2"
        }
    }

    private var fill: Color {
        switch place {
        case .games: return SR.accent
        case .news: return SR.accentInk
        default: return SR.good
        }
    }

    private var blurb: String {
        switch place {
        case .games:
            return "\(GameKind.allCases.count) quick games to play together, live, from any phone in the family."
        case .news: return "The wire, ranked by what is moving. Save and keep stories."
        case .flows: return "Your workflows: run, pause, change a step, or ask jkai to build one."
        default: return ""
        }
    }

    /// Something live to say, or nothing.
    private var status: String? {
        guard place == .games else { return nil }
        let invites = games.invites.count
        let rooms = games.rooms.count
        if invites > 0 { return invites == 1 ? "1 invitation" : "\(invites) invitations" }
        if rooms > 0 { return rooms == 1 ? "1 game in progress" : "\(rooms) games in progress" }
        return nil
    }
}

/// A card in More: an icon on its own colour, the name, what is in it, and
/// anything live to say.
struct MoreCard<Extra: View>: View {
    let icon: String
    let fill: Color
    let title: String
    let blurb: String
    var status: String? = nil
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        SRCard(interactive: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(SR.paper)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(fill))
                        .accessibilityHidden(true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SR.inkGhost)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(SR.Text.display(19))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(blurb)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                extra()
                if let status {
                    SRGlassChip(text: status, tone: SR.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

extension MoreCard where Extra == EmptyView {
    init(icon: String, fill: Color, title: String, blurb: String, status: String? = nil) {
        self.init(icon: icon, fill: fill, title: title, blurb: blurb, status: status) { EmptyView() }
    }
}
