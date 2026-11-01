import SwiftUI
import UIKit

/// One Codenames room, from the lobby to the whole key.
///
/// A TV game first: the grid is meant to be up on the TV board
/// (`GameScreenPairing`) for the room to argue over, so the lobby leads with
/// "Show on TV". The lobby and the 3-2-1 are every game's (`GameLobby`,
/// `GameCountdownView`), with Codenames' own panel: the TV, what the table
/// will play (two teams, or co-op for two or three), and each player's pick
/// — red, blue or anywhere, and whether they'd give the clues.
///
/// In play every phone shows the teams' agents left, the clue, the clock and
/// the grid. A spymaster's grid is tinted by the key (face-down cards light,
/// turned ones solid, the assassin dark) and, on their turn, has the clue
/// field under it: one word, a number from 1 to 9, Send — checked here first
/// so a word on the board is refused at once, and the server's sentence
/// under the field when it refuses. An operative's grid is words; on their
/// team's turn a tap lifts a card and a second tap turns it over, and End
/// turn is there once one is turned. Each card flips to its colour as it
/// turns, and the phone feels what it was.
///
/// The finish is who won, the rest of the key fading in under the cards
/// nobody touched, every clue, and the teams.
struct CodenamesScreen: View {
    let roomId: String
    @StateObject private var store: CodenamesStore
    @EnvironmentObject private var games: GamesStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingHowTo = false
    @State private var showingTV = false

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: CodenamesStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Codenames")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar(immersive ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(immersive)
            .onAppear { store.open() }
            .onDisappear { store.close() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.open() } else if phase == .background { store.close() }
            }
            .overlay(alignment: .top) {
                if let message = store.message, !immersive { SRBanner(text: message) }
            }
            .toolbar { toolbarItems }
            .sheet(isPresented: $showingHowTo) {
                TableHowToSheet(game: "Codenames", steps: CodenamesHowTo.steps, note: TableHowToNote.live, id: "codenames-how-to")
            }
            .sheet(isPresented: $showingTV) {
                GameScreenPairingSheet(roomId: roomId, game: GameKind.codenames.rawValue, prefix: "codenames")
            }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if offersTV {
            ToolbarItem(placement: .topBarTrailing) {
                GameShowOnTVToolbarButton(prefix: "codenames") { showingTV = true }
            }
        }
        if phase?.inPlay == true {
            ToolbarItem(placement: .topBarTrailing) {
                TableHelpButton(id: "codenames-help") { showingHowTo = true }
            }
        }
    }

    private var phase: CodenamesPhase? {
        guard !store.ended, let room = store.room else { return nil }
        return CodenamesScreenPhase.of(room)
    }

    private var immersive: Bool { phase == .countdown }

    /// "Show on TV" while there is a grid to show (or about to be): the lobby
    /// and play — once the site has a TV board for it.
    private var offersTV: Bool {
        guard let phase, phase == .lobby || phase.inPlay else { return false }
        return GameScreenPairing.offered(GameKind.codenames.rawValue, lobby: games.lobby)
    }

    private var tvAction: (() -> Void)? {
        guard offersTV else { return nil }
        return { showingTV = true }
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "codenames-ended", done: { dismiss() })
        } else if let room = store.room {
            switch CodenamesScreenPhase.of(room) {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "codenames", done: { dismiss() },
                          panel: AnyView(CodenamesLobbyPanel(room: room, store: store, showTV: tvAction)),
                          startBlocked: room.playing.count < CodenamesRules.minPlayers)
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Spymasters: one word and a number. Everyone else: keep away from the assassin.",
                                  id: "codenames-countdown")
            case .clue, .guess:
                CodenamesPlaying(room: room, store: store, done: { dismiss() })
            case .finished:
                CodenamesFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "codenames-ended", done: { dismiss() })
            }
        } else {
            CodenamesSettingUp()
        }
    }
}

/// The wait for the first room: a row of cards and a spinner.
private struct CodenamesSettingUp: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach([CodenamesKind.red, .neutral, .blue, .assassin], id: \.rawValue) { kind in
                    RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                        .fill(CodenamesInk.fill(kind))
                        .frame(width: 44, height: 30)
                }
            }
            ProgressView().tint(SR.accent)
            Text("Dealing the words…")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srPaper()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dealing the words")
    }
}

// MARK: - How to play

enum CodenamesHowTo {
    static let steps = [
        TableHowToStep(icon: "rectangle.grid.3x2.fill", title: "25 words",
                       text: "Some are red agents, some blue, seven are bystanders and one is the assassin. Only the spymasters can see which."),
        TableHowToStep(icon: "text.bubble.fill", title: "One word, one number",
                       text: "On your turn your spymaster gives one word and how many cards it points to: ocean 2. It can't be a word on the board."),
        TableHowToStep(icon: "hand.tap.fill", title: "Touch the cards",
                       text: "Tap a card to lift it, tap again to turn it over. Your own agent and you can go on, up to the number plus one."),
        TableHowToStep(icon: "xmark.octagon.fill", title: "Mind the assassin",
                       text: "A bystander or the other team's agent ends your turn. The assassin loses the game. You can end the turn after one guess."),
        TableHowToStep(icon: "flag.checkered", title: "The end",
                       text: "The first team to find all their agents wins. Two or three play together: find all nine before blue's agents turn themselves over."),
    ]
}

// MARK: - Lobby

/// The lobby's panel: the TV first, then what the table will play, my pick
/// (red, blue or anywhere, and the clues) and who is on which side.
struct CodenamesLobbyPanel: View {
    let room: GameRoom
    @ObservedObject var store: CodenamesStore
    /// Opens the TV sheet; nil when the site has no TV board to offer.
    let showTV: (() -> Void)?

    private var state: CodenamesState? { room.codenames }
    private var mode: CodenamesMode {
        state?.mode ?? (room.playing.count >= CodenamesRules.teamsMin ? .teams : .coop)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let showTV {
                VStack(alignment: .leading, spacing: 8) {
                    GameShowOnTVButton(prefix: "codenames", action: showTV)
                    Text("Open \(GameScreenCode.address(GameKind.codenames.rawValue)) on the TV first. The grid goes up there; the key stays on the spymasters' phones.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("\(CodenamesRules.modeLabel(mode)) · \(GameDifficulty.label(for: room.difficulty))".uppercased())
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.accent)
                .accessibilityIdentifier("codenames-mode")
            Text(mode == .teams ? "Pick a side" : "All on red")
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
            Text(CodenamesRules.modeLine(mode))
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("codenames-mode-line")
            if let hint = CodenamesRules.modeHint(mode, joined: room.playing.count) {
                Label(hint, systemImage: "person.2.fill")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            if room.me?.joined == true, let state { picker(state) }
            if let state { teams(state) }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("codenames-table")
    }

    /// Red, blue or anywhere — three buttons, mine lit — and the clues switch.
    private func picker(_ state: CodenamesState) -> some View {
        let mine = state.mySeat
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                pickButton("Red", team: .red, picked: mine?.team == .red)
                pickButton("Blue", team: .blue, picked: mine?.team == .blue)
                pickButton("Anywhere", team: nil, picked: mine?.team == nil)
            }
            Toggle(isOn: Binding(get: { mine?.spymaster ?? false }, set: { store.askToGiveClues($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("I'll give the clues")
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.ink)
                    Text("Spymasters see the key. If nobody asks, the game picks somebody who hasn't had a go.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(SR.accent)
            .disabled(store.sending)
            .accessibilityIdentifier("codenames-spymaster")
        }
    }

    private func pickButton(_ title: String, team: CodenamesTeam?, picked: Bool) -> some View {
        let tone = team.map(CodenamesInk.team) ?? SR.accentInk
        return Button {
            guard !picked else { return }
            store.pickTeam(team)
        } label: {
            Text(title.uppercased())
                .font(SR.Text.label(13))
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(picked ? Color.white : tone)
                .frame(maxWidth: .infinity, minHeight: SR.tapTarget)
                .background(Capsule().fill(picked ? tone : Color.clear))
                .overlay(Capsule().strokeBorder(tone.opacity(picked ? 0 : 0.6), lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(SRPressStyle())
        .disabled(store.sending)
        .accessibilityLabel(team == nil ? "Put me anywhere" : "Join \(title)")
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("codenames-pick-\(team?.rawValue ?? "anywhere")")
    }

    /// Who has picked which side, a key beside anyone who would give clues.
    private func teams(_ state: CodenamesState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                column(.red, state.members(.red))
                column(.blue, state.members(.blue))
            }
            if !state.anywhere.isEmpty {
                Text("Anywhere: \(GameNames.list(state.anywhere.map { $0.id == room.meId ? "you" : $0.name }))")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("codenames-anywhere")
            }
            Text(mode == .teams
                 ? "At the start each side gets at least two; anyone left over fills the smaller side."
                 : "In co-op everybody plays red, whatever they picked.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func column(_ team: CodenamesTeam, _ seats: [CodenamesSeat]) -> some View {
        let tone = CodenamesInk.team(team)
        return VStack(alignment: .leading, spacing: 6) {
            Text(team.label.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(tone)
            if seats.isEmpty {
                Text("Nobody yet")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
            }
            ForEach(seats) { seat in
                HStack(spacing: 6) {
                    Text(seat.id == room.meId ? "\(seat.name) (you)" : seat.name)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                    if seat.spymaster {
                        Image(systemName: "key.fill")
                            .font(SR.Text.label(12))
                            .foregroundStyle(tone)
                            .accessibilityLabel("would give the clues")
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).fill(tone.opacity(0.08)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("codenames-lobby-\(team.rawValue)")
    }
}

// MARK: - Playing

struct CodenamesPlaying: View {
    let room: GameRoom
    @ObservedObject var store: CodenamesStore
    /// Back to the games list, after leaving.
    let done: () -> Void
    @State private var confirmingLeave = false

    private var state: CodenamesState? { room.codenames }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CodenamesBanner(room: room, store: store)
                if let state {
                    CodenamesSidesHeader(state: state, room: room)
                    if let clue = state.clue, state.phase == .guess {
                        CodenamesClueBanner(clue: clue, state: state, room: room)
                    }
                    if state.amSpymaster {
                        Label("You can see the key. Faces straight.", systemImage: "key.fill")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .accessibilityIdentifier("codenames-key-note")
                    }
                    CodenamesGrid(state: state, room: room, lifted: store.lifted) { store.tap($0) }
                    if let note = store.revealNote {
                        Text(note)
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("codenames-reveal")
                    }
                    if state.canClue {
                        CodenamesClueComposer(state: state, store: store)
                    }
                    if state.canGuess {
                        CodenamesGuessBar(state: state, store: store)
                    }
                    if !state.clues.isEmpty {
                        CodenamesClueHistory(state: state, room: room)
                    }
                    if store.seated { leaveButton(state) }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
            .srAnimation(.spring(response: 0.5, dampingFraction: 0.82), value: motion)
        }
        .scrollDismissesKeyboard(.interactively)
        .srGround(.warm)
        .accessibilityIdentifier("codenames-playing")
        .onChange(of: store.revealNote) { _, note in
            if let note { UIAccessibility.post(notification: .announcement, argument: note) }
        }
        .onChange(of: store.refusal) { _, refusal in
            if let refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
        .confirmationDialog("Leave the game?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Task {
                    if await store.act("leave") { done() }
                }
            }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text(leaveWarning)
        }
    }

    /// Changes with every clue and every card: the page's moves animate on it.
    private var motion: String {
        "\(state?.turns ?? 0)-\(state?.phase.rawValue ?? "")-\(state?.last?.card ?? -1)"
    }

    private var leaveWarning: String {
        guard let state, let team = state.myTeam else { return "" }
        let mates = state.members(team).filter { $0.id != room.meId }.count
        return CodenamesRules.leaveWarning(spymaster: state.amSpymaster, mates: mates)
    }

    private func leaveButton(_ state: CodenamesState) -> some View {
        Button {
            SRHaptic.select()
            confirmingLeave = true
        } label: {
            TableButtonLabel(title: "Leave the game", icon: "rectangle.portrait.and.arrow.right")
        }
        .buttonStyle(TableSolidButtonStyle(outline: true))
        .disabled(store.busy)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .accessibilityIdentifier("codenames-leave")
    }
}

// MARK: The banner

/// Who is up, said big, with the clock: the spymaster thinking or the team
/// guessing, and on this phone's move the accent.
struct CodenamesBanner: View {
    let room: GameRoom
    @ObservedObject var store: CodenamesStore

    private var state: CodenamesState? { room.codenames }

    var body: some View {
        TableTurnBanner(mine: store.myMove) {
            TableTurnWords(mine: store.myMove, kicker: kicker,
                           title: state.map(CodenamesRules.headline) ?? "Setting up…",
                           detail: state.flatMap { CodenamesRules.detail($0, name: room.name(of:)) },
                           titleId: "codenames-headline")
        } clock: {
            if let state, state.phase.inPlay {
                TableTurnClock(store: store, endsAt: state.phaseEndsAt,
                               turnMs: state.phase == .clue ? state.clueMs : state.guessMs, mine: store.myMove)
                    .accessibilityIdentifier("codenames-clock")
            }
        }
    }

    private var kicker: String {
        var bits = ["Codenames", "turn \(max(1, state?.turns ?? 1))"]
        if let team = state?.myTeam, state?.mode == .teams {
            bits.append(state?.amSpymaster == true ? "\(team.label) spymaster" : "you're \(team.label.lowercased())")
        } else {
            bits.append(GameDifficulty.label(for: room.difficulty))
        }
        return bits.joined(separator: " · ")
    }
}

// MARK: The clue field

/// The spymaster's turn: one word, a number from 1 to 9, Send. The check
/// runs here first; a refusal (here or from the server) stays under the field.
struct CodenamesClueComposer: View {
    let state: CodenamesState
    @ObservedObject var store: CodenamesStore
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Your clue", trailing: "\(state.side(state.turnTeam)?.left ?? 0) to find")
            TextField("One word", text: Binding(get: { store.clueDraft }, set: { store.editClue($0) }))
                .font(SR.Text.title(22))
                .foregroundStyle(SR.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .focused($focused)
                .onSubmit { store.sendClue() }
                .padding(.horizontal, 16)
                .frame(minHeight: 60)
                .background(
                    RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 2, style: .continuous)
                        .fill(SR.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 2, style: .continuous)
                        .strokeBorder(stroke, lineWidth: focused || problem != nil ? 2 : 1)
                )
                .accessibilityLabel("Your clue")
                .accessibilityIdentifier("codenames-clue-field")
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(store.clueRefusal != nil ? SR.error : SR.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("codenames-clue-refusal")
            }
            HStack(spacing: 14) {
                TableRoundButton(icon: "minus", label: "One fewer", enabled: store.clueCount > 1,
                                 id: "codenames-count-down") { store.stepCount(-1) }
                VStack(spacing: 0) {
                    Text("\(store.clueCount)")
                        .font(SR.Text.figure(34))
                        .foregroundStyle(SR.ink)
                        .srNumeric(Double(store.clueCount))
                    Text(store.clueCount == 1 ? "CARD" : "CARDS")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(store.clueCount == 1 ? "1 card" : "\(store.clueCount) cards")
                .accessibilityIdentifier("codenames-count")
                TableRoundButton(icon: "plus", label: "One more", enabled: store.clueCount < CodenamesRules.maxCount,
                                 id: "codenames-count-up") { store.stepCount(1) }
            }
            Button { store.sendClue() } label: {
                if store.sending {
                    ProgressView().tint(SR.paper)
                } else {
                    TableButtonLabel(title: store.clueDraft.isEmpty ? "Send" : "Send \(store.clueDraft) · \(store.clueCount)",
                                     icon: "paperplane.fill")
                }
            }
            .buttonStyle(TableSolidButtonStyle(fill: CodenamesInk.team(state.turnTeam)))
            .disabled(!store.canSendClue)
            .accessibilityIdentifier("codenames-send-clue")
            Text("One word, not on the board and not part of a word on it. The number is how many of your agents it points to; your team can guess one more than that.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("codenames-composer")
    }

    /// The refusal once sent; while typing, what the check would say.
    private var problem: String? { store.clueRefusal ?? store.draftProblem }

    private var stroke: Color {
        if store.clueRefusal != nil { return SR.error }
        if store.draftProblem != nil { return SR.warn }
        return focused ? SR.accent : SR.line
    }
}

// MARK: The guesses

/// Under the grid on my team's turn: what is lifted, Turn it over, End turn,
/// and why a touch was refused.
struct CodenamesGuessBar: View {
    let state: CodenamesState
    @ObservedObject var store: CodenamesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let refusal = store.refusal {
                Label(refusal, systemImage: "exclamationmark.circle")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("codenames-refusal")
            }
            if let i = store.lifted, let card = state.cards.first(where: { $0.i == i }) {
                HStack(spacing: 10) {
                    Button { store.confirm() } label: {
                        TableButtonLabel(title: "Turn over \(card.word)", icon: "hand.tap.fill")
                    }
                    .buttonStyle(TableSolidButtonStyle(fill: CodenamesInk.team(state.turnTeam)))
                    .disabled(store.sending)
                    .accessibilityIdentifier("codenames-confirm")
                    Button("Put back") { store.putDown() }
                        .font(SR.Text.label(13))
                        .frame(minHeight: SR.tapTarget)
                        .accessibilityIdentifier("codenames-put-back")
                }
            }
            Button { store.pass() } label: {
                TableButtonLabel(title: "End turn", icon: "hand.raised.fill")
            }
            .buttonStyle(TableSolidButtonStyle(outline: true))
            .disabled(!state.canPass || store.sending)
            .accessibilityHint(state.canPass ? "Stops guessing; the other team is up" : "Turn over one card first")
            .accessibilityIdentifier("codenames-pass")
            if !state.canPass {
                Text("Turn over at least one card before you can stop.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
        }
    }
}

// MARK: - Finished

struct CodenamesFinished: View {
    let room: GameRoom
    @ObservedObject var store: CodenamesStore
    let done: () -> Void
    @State private var record: TableGameRecord?

    private var state: CodenamesState? { room.codenames }
    private var gameKey: String { TableGameKey.finished(roomId: room.id, startedAt: room.startedAt) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Codenames · \(GameDifficulty.label(for: room.difficulty)) · final",
                             title: CodenamesRules.endingTitle(state?.result, mode: state?.mode ?? .teams, myTeam: state?.myTeam),
                             strap: GameResults.strap(room))
                    .accessibilityIdentifier("codenames-title")

                winner

                if let state {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "The key", trailing: "faded: never touched")
                        CodenamesGrid(state: state, room: room, final: true)
                    }
                    standings(state)
                }

                if let record {
                    TableRecordCard(record: record, gameKey: gameKey, bestLabel: "Most agents found", id: "codenames-record")
                }

                GameFinishedButtons(room: room, store: store, prefix: "codenames", done: done)

                if let state, !state.clues.isEmpty {
                    CodenamesClueHistory(state: state, room: room)
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("codenames-finished")
        .overlay(alignment: .top) {
            if GameResults.celebrates(room) {
                GameConfettiView(seed: GameResults.seed(room.id))
                    .frame(height: 420)
                    .allowsHitTesting(false)
            }
        }
        .onAppear(perform: noteRecord)
    }

    /// The winner's banner in their colour; ink when co-op lost.
    private var winner: some View {
        let team = state?.result?.winner
        let fill = team.map(CodenamesInk.team) ?? CodenamesInk.fill(.assassin)
        return VStack(alignment: .leading, spacing: 6) {
            Text(team.map { "\($0.label) win" }?.uppercased() ?? "NOBODY WINS")
                .font(SR.Text.label(13))
                .tracking(SR.kickerTracking)
                .foregroundStyle(Color.white.opacity(0.88))
            Text(CodenamesRules.endingLine(state?.result, mode: state?.mode ?? .teams, last: state?.last))
                .font(SR.Text.bodyMedium(16))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous).fill(fill))
        .tablePopIn()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("codenames-outcome")
    }

    /// The teams, winners first: each player, the spymasters marked, and the
    /// agents their team found.
    private func standings(_ state: CodenamesState) -> some View {
        let rows = state.standings ?? []
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "The teams", trailing: GameResults.count(rows.count, "player", "players"))
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(SR.divider) }
                    standingRow(row, state: state)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("codenames-standings")
    }

    private func standingRow(_ row: CodenamesStanding, state: CodenamesState) -> some View {
        let mine = row.id == room.meId
        let tone = row.team.map(CodenamesInk.team) ?? SR.accentInk
        let agents = row.team.flatMap { state.side($0)?.agents } ?? 0
        return HStack(spacing: 12) {
            GameInitial(name: row.name, tone: tone, side: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name + (mine ? " (you)" : ""))
                        .font(SR.Text.title())
                        .foregroundStyle(mine ? SR.accentInk : SR.ink)
                    if row.result == "won" {
                        Image(systemName: "crown.fill")
                            .font(SR.Text.label(13))
                            .foregroundStyle(Color(hex: 0xE9A800))
                            .accessibilityLabel("Winner")
                    }
                }
                Text(detail(row))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            Spacer(minLength: 8)
            Text(agents > 0 ? "\(row.score)/\(agents)" : "\(row.score)")
                .font(SR.Text.figure(22))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
                .accessibilityLabel("\(row.score) agents found")
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("codenames-standings-\(row.id)")
    }

    private func detail(_ row: CodenamesStanding) -> String {
        var bits = [row.team?.label ?? "No team"]
        if row.spymaster { bits.append("spymaster") }
        if row.result == "left" { bits.append("left early") }
        return bits.joined(separator: " · ")
    }

    private func noteRecord() {
        guard record == nil, let mine = state?.standing(room.meId), mine.result != "left" else { return }
        let book = TableGameBestStore(gameId: GameKind.codenames.rawValue, persists: !SRDemo.isOn)
        record = book.note(variant: GameKind.codenames.rawValue, key: gameKey, won: mine.result == "won", score: mine.score)
    }
}
