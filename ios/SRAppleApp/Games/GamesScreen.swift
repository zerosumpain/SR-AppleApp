import SwiftUI

/// The Games tab: invitations waiting, rooms I am in, and a game to start.
///
/// Tap Duel is the first of a series, so the tab is a shelf of games rather
/// than one game's front door — one card per game, and the rooms and invites
/// above them are game-agnostic.
struct GamesScreen: View {
    @ObservedObject var store: GamesStore
    @EnvironmentObject private var router: Router
    @State private var starting = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SR.sectionGap) {
                VStack(alignment: .leading, spacing: 8) {
                    SRPageHeader(kicker: "Family games", title: "Games")
                    // The one honest sentence about delivery. No push
                    // certificate: an invite rings only a phone with the app open.
                    Text("Invites reach phones with the app open.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("games-delivery-note")
                }

                if !store.invites.isEmpty {
                    section("Invitations", trailing: "\(store.invites.count)") {
                        ForEach(store.invites) { invite in
                            GameInviteCard(
                                invite: invite,
                                busy: store.busy == invite.roomId,
                                join: {
                                    Task {
                                        if await store.join(invite) {
                                            router.games.append(GameRoomRef(id: invite.roomId))
                                        }
                                    }
                                },
                                decline: { Task { await store.decline(invite) } }
                            )
                        }
                    }
                }

                if !store.rooms.isEmpty {
                    section("Your games", trailing: nil) {
                        ForEach(store.rooms) { room in
                            NavigationLink(value: GameRoomRef(id: room.id)) {
                                GameRoomRow(room: room)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("games-room-\(room.id)")
                        }
                    }
                }

                section("Play", trailing: nil) {
                    Button {
                        SRHaptic.tap()
                        starting = true
                    } label: {
                        TapDuelCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("games-new")
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("games-screen")
        .srGround(.warm)
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SRBarMark() } }
        .navigationDestination(for: GameRoomRef.self) { TapDuelScreen(roomId: $0.id).id($0.id) }
        .task {
            if store.lobby == nil { await store.load() }
            await store.askForNotificationsIfUndecided()
        }
        .srRefreshable { await store.load() }
        .overlay {
            if store.loading && store.lobby == nil { ProgressView().tint(SR.accent) }
        }
        .overlay(alignment: .bottom) {
            if let message = store.message { SRBanner(text: message) }
        }
        .sheet(isPresented: $starting) {
            NewGameSheet(players: store.players, busy: store.busy == "new") { difficulty, invite in
                guard let room = await store.create(difficulty: difficulty, invite: invite) else { return false }
                starting = false
                router.games.append(GameRoomRef(id: room.id))
                return true
            }
        }
    }

    private func section<Content: View>(_ title: String, trailing: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: title, trailing: trailing)
            content()
        }
    }
}

/// An invitation: who, how hard, who else — Join or Decline.
struct GameInviteCard: View {
    let invite: GameInvite
    let busy: Bool
    let join: () -> Void
    let decline: () -> Void

    var body: some View {
        SRCard(accented: true) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(invite.hostName) invited you")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(GameNames.title(invite.game)) · \(GameDifficulty.label(for: invite.difficulty)) · \(GameNames.list(invite.players))")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button { SRHaptic.tap(); join() } label: {
                        SRButtonLabel(title: "Join", icon: "play.fill", fill: true)
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .accessibilityIdentifier("games-invite-join-\(invite.roomId)")
                    Button { decline() } label: {
                        SRButtonLabel(title: "Decline", fill: true)
                    }
                    .srButton(.regular)
                    .controlSize(.large)
                    .accessibilityIdentifier("games-invite-decline-\(invite.roomId)")
                }
                .disabled(busy)
            }
        }
        .accessibilityIdentifier("games-invite-\(invite.roomId)")
    }
}

/// A room I am in, to go back to.
struct GameRoomRow: View {
    let room: GameRoomSummary

    var body: some View {
        SRCard(interactive: true) {
            HStack(spacing: 12) {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SR.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(GameNames.title(room.game))
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Text("Hosted by \(room.hostName)")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 8)
                SRGlassChip(text: phaseLabel, tone: SR.accentInk)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SR.inkGhost)
            }
            .frame(minHeight: SR.tapTarget)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Resume")
    }

    private var phaseLabel: String {
        switch room.phase {
        case .lobby: return "Lobby"
        case .countdown, .armed, .result: return "Playing"
        case .finished: return "Finished"
        case .closed: return "Closed"
        case .unknown: return "Open"
        }
    }
}

/// The Tap Duel card on the shelf.
struct TapDuelCard: View {
    var body: some View {
        SRCard(interactive: true) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SR.paper)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(SR.accent))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tap Duel")
                        .font(SR.Text.display(22))
                        .foregroundStyle(SR.ink)
                    Text("Five rounds. Wait for green, then tap faster than everyone else. Tap early and the round is gone.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("NEW GAME")
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(SR.accent)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Difficulty, who to invite, Start.
struct NewGameSheet: View {
    let players: [GamePerson]
    let busy: Bool
    /// Creates the room; true when it did, and the sheet is then closed by
    /// its owner.
    let start: (GameDifficulty, [String]) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var difficulty: GameDifficulty = .easy
    @State private var invited: Set<String> = []
    @State private var working = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    SRPageHeader(kicker: "New game", title: "Tap Duel")

                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "Difficulty")
                        ForEach(GameDifficulty.allCases) { level in
                            choice(
                                title: level.label,
                                line: level.line,
                                selected: difficulty == level,
                                id: "games-difficulty-\(level.rawValue)"
                            ) { difficulty = level }
                        }
                    }

                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "Players", trailing: invited.isEmpty ? "Solo" : "\(invited.count + 1)")
                        if players.isEmpty {
                            Text("Nobody else in the family can play yet, so this is a solo game.")
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(players) { person in
                                choice(
                                    title: person.name,
                                    line: nil,
                                    selected: invited.contains(person.id),
                                    multi: true,
                                    id: "games-player-\(person.id)"
                                ) {
                                    invited.formSymmetricDifference([person.id])
                                }
                            }
                            Text("Tick nobody to play solo. Invites reach phones with the app open.")
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Button {
                        SRHaptic.tap()
                        working = true
                        Task {
                            _ = await start(difficulty, players.filter { invited.contains($0.id) }.map(\.id))
                            working = false
                        }
                    } label: {
                        SRButtonLabel(title: invited.isEmpty ? "Start solo" : "Start and invite", icon: "play.fill", fill: true)
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .disabled(working || busy)
                    .accessibilityIdentifier("games-start")
                }
                .padding(.horizontal, SR.gutter)
                .padding(.vertical, 12)
            }
            .srGround(.warm)
            .navigationTitle("New game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("games-new-cancel")
                }
            }
        }
        .presentationDetents([.large])
    }

    private func choice(title: String, line: String?, selected: Bool, multi: Bool = false, id: String,
                        action: @escaping () -> Void) -> some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected
                      ? (multi ? "checkmark.square.fill" : "largecircle.fill.circle")
                      : (multi ? "square" : "circle"))
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(selected ? SR.accent : SR.inkGhost)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    if let line {
                        Text(line)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, SR.rowPadding)
            .frame(maxWidth: .infinity, minHeight: SR.tapTarget, alignment: .leading)
            .srGlassCard(selected ? .paper : .clear, radius: SR.Glass.innerRadius + 4, interactive: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
