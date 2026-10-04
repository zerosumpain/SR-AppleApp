import SwiftUI

/// The More tab: Daydream, then Games, News and Flows once the bar is full,
/// and Settings at the foot.
///
/// Ours, not iOS's. The system More is a navigation controller that wraps each
/// tab's own `NavigationStack`, so a game opened from it had two bars and two
/// back buttons — "More" and "Games" — and a game screen that hid the tab bar
/// could pop back onto a More list with no bar at all, and nothing to press.
/// Here the hub and everything it opens share ONE stack (`Router.more`): one
/// bar, one back button, and the hub is always under it.
///
/// And a front page rather than a list of names. What is waiting on you comes
/// first — an invitation, a game you are in — then one card per place saying
/// what is in it.
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
    @ObservedObject private var landgrab = LandgrabStore.shared
    @ObservedObject private var access = AccessStore.shared
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            // A plain stack: a handful of cards and one row need no laziness,
            // and a lazy stack whose last child (Settings) is measured at a
            // different height than it was estimated at loops at the bottom.
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                if places.contains(.games) { waiting }

                // Two by two: every place a tile of the same size, so the
                // page reads as a set of doors rather than a list to scroll.
                VStack(spacing: SR.cardGap) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: SR.cardGap) {
                            ForEach(row, id: \.self) { tile($0) }
                            if row.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                        }
                        .fixedSize(horizontal: false, vertical: true)
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
                if landgrab.board == nil { await landgrab.load() }
            }
            if games.lobby == nil { await games.load() }
        }
        .srRefreshable {
            if access.familyBoards {
                await steps.load()
                await tasks.load()
                await landgrab.load()
            }
            await games.load()
        }
    }

    private func familyCard(_ page: FamilyPage) -> some View {
        Button {
            SRHaptic.tap()
            router.openFamilyPage(page)
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
        case daydream, steps, tasks, landgrab, sync, settings
        case place(Router.Tab)
    }

    private var items: [Item] {
        var all: [Item] = []
        // The daydream loop is the owner's, over the site.
        if AccessStore.ownerSite { all.append(.daydream) }
        // The family's step board and task list: pages, not tabs, for
        // everyone with the family and the site credential.
        if access.familyBoards { all += [.steps, .tasks] }
        // Landgrab, once its board has somebody on it — hidden, like the
        // section on Steps, when the site says no or has nothing.
        if access.familyBoards && landgrab.visible { all.append(.landgrab) }
        all += places.map(Item.place)
        // Sync now and Settings last, tiles like the rest.
        all += [.sync, .settings]
        return all
    }

    /// Pairs, for the grid. A plain stack of rows rather than a lazy grid: a
    /// lazy container whose last child is measured at a different height than
    /// it was estimated at loops at the bottom.
    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
    }

    @ViewBuilder
    private func tile(_ item: Item) -> some View {
        switch item {
        case .daydream:
            Button {
                SRHaptic.tap()
                router.more.append(Router.MorePage.daydream)
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
        case .steps: familyCard(.steps)
        case .tasks: familyCard(.tasks)
        case .landgrab:
            Button {
                SRHaptic.tap()
                if let week = landgrab.board.flatMap(Landgrab.currentWeek) {
                    router.more.append(LandgrabMapRef(week: week.start))
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
                router.show(place)
            } label: {
                MorePlaceCard(place: place, games: games)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("more-\(place.rawValue)")
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

    /// Invitations and games in progress — the reason to open More at all,
    /// one tap from the room rather than two screens away.
    @ViewBuilder
    private var waiting: some View {
        if !games.invites.isEmpty || !games.rooms.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Waiting for you")
                ForEach(games.invites) { invite in
                    GameInviteCard(
                        invite: invite,
                        busy: games.busy == invite.roomId,
                        join: {
                            Task {
                                if await games.join(invite) { router.openGame(invite.roomId, game: invite.game) }
                            }
                        },
                        decline: { Task { await games.decline(invite) } }
                    )
                }
                ForEach(games.rooms) { room in
                    Button {
                        SRHaptic.tap()
                        router.openGame(room.id, game: room.game)
                    } label: {
                        GameRoomRow(room: room)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("more-room-\(room.id)")
                }
            }
        }
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
                    .lineLimit(4)
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
