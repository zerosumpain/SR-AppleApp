import SwiftUI

/// The More tab: Games, News and Flows once the bar is full.
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
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SR.sectionGap) {
                if places.contains(.games) { waiting }

                VStack(alignment: .leading, spacing: SR.cardGap) {
                    ForEach(places, id: \.self) { place in
                        Button {
                            SRHaptic.tap()
                            router.show(place)
                        } label: {
                            MorePlaceCard(place: place, games: games)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("more-\(place.rawValue)")
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
        .task { if games.lobby == nil { await games.load() } }
        .srRefreshable { await games.load() }
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
        SRCard(interactive: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(SR.paper)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(fill))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(SR.Text.display(22))
                            .foregroundStyle(SR.ink)
                        Text(blurb)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SR.inkGhost)
                        .padding(.top, 4)
                }
                if place == .games { shelf }
                if let status {
                    SRGlassChip(text: status, tone: SR.accent)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// The six games as a row of marks — what is on the shelf, at a glance.
    private var shelf: some View {
        HStack(spacing: 8) {
            ForEach(GameKind.allCases) { kind in
                Image(systemName: kind.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SR.accent)
                    .frame(width: 34, height: 34)
                    .srGlass(.paper, in: Circle())
            }
        }
        .accessibilityHidden(true)
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
