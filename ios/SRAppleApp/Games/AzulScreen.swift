import SwiftUI
import UIKit

/// One Azul room, from lobby to the final wall.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the table the host picked as the lobby's panel — and, when they picked
/// the TV board, "Show on TV" leading it. The TV is optional: every phone
/// shows the whole table either way.
///
/// Play is the table across the top — the factories as clay plates and the
/// centre, with the first-player marker while it is there — then my board,
/// then everyone else's. On my turn a tap on a tile picks every tile of its
/// colour at that source (they lift), my lines that may take it light up, and
/// a row of choices under the table says what each would do ("3 fit, 1 to the
/// floor"); a tap on a lit line, the floor or a choice sends it. A tap
/// anywhere else puts the tiles back. Tiles are keyed by their ids for the
/// whole game and share one namespace, so a take flies from the factory to
/// the line and the rest slide into the centre.
///
/// The scoring pause shows each tile going up on the wall with what it
/// scored, the floor's cost and the score rolling on. The finish is the table
/// with the bonuses broken down (rows ×2, columns ×7, colours ×10).
///
/// A banner says whose turn it is, with the clock (a dial when live, hours
/// left over days). The "?" opens how to play over a table that carries on.
struct AzulScreen: View {
    let roomId: String
    @StateObject private var store: AzulStore
    @EnvironmentObject private var games: GamesStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingHowTo = false
    @State private var showingTV = false

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: AzulStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Azul")
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
                TableHowToSheet(game: "Azul", steps: AzulHowTo.steps, note: howToNote, id: "azul-how-to")
            }
            .sheet(isPresented: $showingTV) {
                GameScreenPairingSheet(roomId: roomId, game: GameKind.azul.rawValue, prefix: "azul")
            }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if offersTV {
            ToolbarItem(placement: .topBarTrailing) {
                GameShowOnTVToolbarButton(prefix: "azul") { showingTV = true }
            }
        }
        if showsHelp {
            ToolbarItem(placement: .topBarTrailing) {
                TableHelpButton(id: "azul-help") { showingHowTo = true }
            }
        }
    }

    private var phase: AzulPhase? {
        guard !store.ended, let room = store.room else { return nil }
        return AzulScreenPhase.of(room)
    }

    private var immersive: Bool { phase == .countdown }

    private var showsHelp: Bool { phase == .playing || phase == .scoring }

    /// "Show on TV" while there is a table to show: the lobby, play and the
    /// scoring pause — for a game the site has a TV board for.
    private var offersTV: Bool {
        guard let phase, phase == .lobby || phase == .playing || phase == .scoring else { return false }
        return GameScreenPairing.offered(GameKind.azul.rawValue, lobby: games.lobby)
    }

    /// Opens the TV sheet, when there is one to offer.
    private var tvAction: (() -> Void)? {
        guard offersTV else { return nil }
        return { showingTV = true }
    }

    private var howToNote: String {
        store.state?.isAsync == true
            ? "Played over days: each turn has the host's hours. If they run out, the game moves for you."
            : TableHowToNote.live
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "azul-ended", done: { dismiss() })
        } else if let room = store.room {
            switch AzulScreenPhase.of(room) {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "azul", done: { dismiss() },
                          panel: AnyView(AzulTableCard(room: room, showTV: tvAction)),
                          startBlocked: room.playing.count < AzulRules.minPlayers)
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Take every tile of one colour. What doesn't fit falls to the floor.",
                                  id: "azul-countdown")
            case .playing, .scoring:
                AzulPlaying(room: room, store: store, done: { dismiss() })
            case .finished:
                AzulFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "azul-ended", done: { dismiss() })
            }
        } else {
            AzulSettingUp()
        }
    }
}

/// The wait for the first room: a row of tiles and a spinner.
private struct AzulSettingUp: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(AzulRules.colours, id: \.self) { colour in
                    AzulTileFace(colour: colour).frame(width: 34)
                }
            }
            ProgressView().tint(SR.accent)
            Text("Laying out the tiles…")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srPaper()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Laying out the tiles")
    }
}

// MARK: - How to play

enum AzulHowTo {
    static let steps = [
        TableHowToStep(icon: "square.grid.3x3.topleft.filled", title: "Tile your wall",
                       text: "Everyone has a wall of 25 squares, one of each colour in every row and column. Fill it well to score."),
        TableHowToStep(icon: "hand.tap.fill", title: "Take one colour",
                       text: "On your turn take every tile of one colour from a factory (the rest slide to the centre) or from the centre."),
        TableHowToStep(icon: "line.3.horizontal", title: "Fill a line",
                       text: "Lay them on one line. Line 1 holds one, line 5 holds five, one colour a line. What doesn't fit falls to the floor."),
        TableHowToStep(icon: "arrow.up.square.fill", title: "Up on the wall",
                       text: "When the tiles are gone, each full line puts a tile on the wall: a point, or one for every tile it joins in its row and column."),
        TableHowToStep(icon: "exclamationmark.triangle.fill", title: "Mind the floor",
                       text: "Floor tiles cost 1, 1, 2, 2, 2, 3 and 3. The first to take from the centre gets the marker on their floor too, and starts next round."),
        TableHowToStep(icon: "flag.checkered", title: "The end",
                       text: "The round someone finishes a row is the last. Bonuses: 2 a complete row, 7 a column, 10 for all five of a colour."),
    ]
}

// MARK: - Lobby

/// The table the host picked, in the lobby, under a row of tiles — how to
/// play, "Show on TV" for a game set up for the TV, and, until two are in,
/// that it needs two.
struct AzulTableCard: View {
    let room: GameRoom
    /// Opens the TV sheet; nil when the site has no TV board to offer.
    let showTV: (() -> Void)?

    private var table: AzulTable { room.azul?.table ?? .phones }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(AzulRules.colours, id: \.self) { colour in
                    AzulTileFace(colour: colour).frame(maxWidth: 44)
                }
            }
            .accessibilityHidden(true)
            Text("\(table.label) · \(GameDifficulty.label(for: room.difficulty))".uppercased())
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.accent)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tile the palace wall")
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
            Text("Take every tile of one colour, fill your lines, and move them up onto your wall at the end of each round. Every tile scores for the ones it touches; the floor costs you.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            TableHowToList(steps: Array(AzulHowTo.steps.dropFirst().prefix(3)))
            tv
            if room.playing.count < AzulRules.minPlayers {
                Label("Needs one more player.", systemImage: "person.2.fill")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityIdentifier("azul-needs-two")
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("azul-table")
    }

    @ViewBuilder
    private var tv: some View {
        if let showTV {
            if table == .tv {
                VStack(alignment: .leading, spacing: 8) {
                    GameShowOnTVButton(prefix: "azul", action: showTV)
                    Text("Open \(GameScreenCode.address(GameKind.azul.rawValue)) on the TV first. Every phone still shows the whole table.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label("Every phone shows the whole table. To put it on a TV too, tap the TV at the top.", systemImage: "iphone")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Playing

struct AzulPlaying: View {
    let room: GameRoom
    @ObservedObject var store: AzulStore
    /// Back to the games list, after leaving.
    let done: () -> Void
    @Namespace private var tiles
    @State private var confirmingLeave = false
    /// On a TV table, the others' boards wait behind this.
    @State private var showsEveryone = false

    private var state: AzulState? { room.azul }
    private var scoring: Bool { state?.phase == .scoring }

    /// Changes with every take and every round: the table's moves animate on it.
    private var motion: String {
        "\(state?.round ?? 0)-\(state?.log.last?.n ?? 0)-\(state?.phase.rawValue ?? "")"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AzulBanner(room: room, store: store)
                if let state {
                    if scoring {
                        AzulScoringCard(room: room, state: state)
                    } else {
                        AzulTableView(state: state, store: store, space: tiles)
                    }
                    AzulGuide(store: store)
                    if let mine = store.myBoard, store.seated {
                        AzulBoardCard(room: room, state: state, board: mine, store: store, space: tiles, mine: true)
                    }
                    others(state)
                    if !state.log.isEmpty { AzulLogStrip(state: state) }
                    if store.seated { leaveButton }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
            // A tap anywhere but a tile, a lit line or a choice puts picked
            // tiles back: those are buttons, and a button takes its own tap.
            .contentShape(Rectangle())
            .onTapGesture { store.cancel() }
            .srAnimation(.spring(response: 0.55, dampingFraction: 0.82), value: motion)
        }
        .srGround(.warm)
        .accessibilityIdentifier("azul-playing")
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
            Text(AzulRules.leaveWarning(staying: store.others.filter(\.joined).count))
        }
    }

    /// Everyone else's boards: open on a phones table, behind "Me / Everyone"
    /// on a TV table (where they are on the screen too). Somebody watching
    /// sees them all.
    @ViewBuilder
    private func others(_ state: AzulState) -> some View {
        let boards = store.seated ? store.others : state.seated
        if !boards.isEmpty {
            if state.table == .tv && store.seated {
                Picker("Boards", selection: $showsEveryone) {
                    Text("Me").tag(false)
                    Text("Everyone").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("azul-boards-switch")
            }
            if state.table == .phones || showsEveryone || !store.seated {
                ForEach(boards) { board in
                    AzulBoardCard(room: room, state: state, board: board, store: store, space: tiles, mine: false)
                }
            }
        }
    }

    private var leaveButton: some View {
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
        .accessibilityIdentifier("azul-leave")
    }
}

// MARK: The banner

/// Whose turn it is, said big, with the clock: a dial when live, the hours
/// left over days. In the scoring pause, the round being tiled.
struct AzulBanner: View {
    let room: GameRoom
    @ObservedObject var store: AzulStore

    private var state: AzulState? { room.azul }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TableTurnBanner(mine: store.myTurn) {
                TableTurnWords(mine: store.myTurn, kicker: kicker, title: headline, detail: detail, titleId: "azul-headline")
            } clock: {
                if let state, state.phase == .playing, state.turnId != nil, !state.isAsync {
                    TableTurnClock(store: store, endsAt: state.phaseEndsAt, turnMs: state.turnMs, mine: store.myTurn)
                        .accessibilityIdentifier("azul-turn-clock")
                }
            }
            if let state, state.phase == .playing, state.isAsync {
                AzulDeadline(state: state, room: room, now: { store.serverNow() })
            }
            if state?.lastRound == true, state?.phase == .playing {
                Label("A wall row is complete: this is the last round.", systemImage: "flag.checkered")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("azul-last-round")
            }
        }
    }

    private var kicker: String {
        var bits = ["Azul", "round \(max(1, state?.round ?? 1))"]
        if state?.isAsync == true { bits.append("over days") } else { bits.append(GameDifficulty.label(for: room.difficulty)) }
        return bits.joined(separator: " · ")
    }

    private var headline: String {
        guard let state else { return "Setting up…" }
        if state.phase == .scoring { return "Round \(state.round) is tiled" }
        if store.myTurn { return "Your turn" }
        guard let turn = state.turnId else { return "Waiting…" }
        return "\(room.name(of: turn))’s turn"
    }

    private var detail: String? {
        guard let state else { return nil }
        if state.phase == .scoring {
            return state.lastRound ? "That was the last round. Bonuses next." : "Full lines go up on the wall. Next round in a moment."
        }
        if store.myTurn {
            return store.pickedColour == nil
                ? "Tap a tile in a factory or the centre: you take every tile of its colour there."
                : "Tap a lit line or the floor, or tap anywhere else to put them back."
        }
        if let turn = state.turnId, state.board(turn)?.away == true {
            return "\(room.name(of: turn)) is away: the game moves for them when the clock runs out."
        }
        if !store.seated { return "You are watching this one." }
        return "Watch the factories: what they take changes what is left for you."
    }
}

/// "Your move · 21 h left" for a game over days, ticking.
struct AzulDeadline: View {
    let state: AzulState
    let room: GameRoom
    let now: () -> Double?

    var body: some View {
        if let end = state.phaseEndsAt {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                if let now = now() {
                    Label(text(end: end, now: now), systemImage: "timer")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("azul-deadline")
                }
            }
        }
    }

    private func text(end: Double, now: Double) -> String {
        let who: String
        if state.turnId == room.meId { who = "Your move" } else { who = state.turnId.map { room.name(of: $0) } ?? "Everyone" }
        return "\(who) · \(GameDeadline.left(until: end, atServer: now))"
    }
}

// MARK: The table

/// The factories, three to a row, then the centre.
struct AzulTableView: View {
    let state: AzulState
    @ObservedObject var store: AzulStore
    let space: Namespace.ID

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Self.columns, spacing: 10) {
                ForEach(Array(state.factories.enumerated()), id: \.offset) { index, tiles in
                    factory(index, tiles)
                }
            }
            AzulCentreView(tiles: state.centre, marker: state.firstInCentre, picked: store.pickedIds,
                           active: store.pickedSource == .centre, space: space, enabled: store.canTake) { colour in
                store.pick(.centre, colour: colour)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("azul-factories")
    }

    private func factory(_ index: Int, _ tiles: [AzulTile]) -> some View {
        AzulFactoryView(index: index, tiles: tiles, picked: store.pickedIds,
                        active: store.pickedSource == .factory(index), space: space, enabled: store.canTake) { colour in
            store.pick(.factory(index), colour: colour)
        }
    }
}

// MARK: The guide and the choices

/// Under the table: what to do now, why a take was refused, and — with tiles
/// picked — a choice for each place they may go, with what would happen there.
struct AzulGuide: View {
    @ObservedObject var store: AzulStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let refusal = store.refusal {
                Label(refusal, systemImage: "exclamationmark.circle")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("azul-refusal")
            }
            if store.myTurn, let colour = store.pickedColour, !store.picked.isEmpty {
                pickedLine(colour)
                choices
            }
        }
    }

    private func pickedLine(_ colour: String) -> some View {
        HStack(spacing: 10) {
            AzulTileFace(colour: colour).frame(width: 26)
            Text("\(store.picked.count) \(AzulRules.colourName(colour).lowercased()) from \(store.pickedSource?.spoken ?? "the table")"
                 + (store.takesMarker ? ", and the first-player marker" : ""))
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Put back") { store.cancel() }
                .font(SR.Text.label(13))
                .accessibilityIdentifier("azul-put-back")
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("azul-picked")
    }

    private var choices: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
            ForEach(store.destinations) { destination in
                AzulChoice(destination: destination, enabled: !store.sending) { store.place(destination.line) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("azul-choices")
    }
}

/// One place the picked tiles may go: "Line 3 · 2 fit, 1 to the floor · −1 point".
struct AzulChoice: View {
    let destination: AzulDestination
    let enabled: Bool
    let action: () -> Void

    private var title: String {
        switch destination.line {
        case .line(let i): return "Line \(i + 1)"
        case .floor: return "Floor"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(SR.Text.label(13))
                    .tracking(1)
                    .foregroundStyle(SR.accentInk)
                Text(AzulRules.previewText(destination.spill))
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let cost = AzulRules.costText(destination.spill) {
                    Text(cost)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.error)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: SR.tapTarget + 12, alignment: .leading)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4, interactive: true)
            .overlay(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                    .strokeBorder(SR.accent.opacity(0.6), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .disabled(!enabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("azul-choice-\(destination.id)")
    }

    private var spoken: String {
        var bits = ["Put them on \(destination.line.spoken)", AzulRules.previewText(destination.spill)]
        if let cost = AzulRules.costText(destination.spill) { bits.append(cost) }
        return bits.joined(separator: ", ")
    }
}

// MARK: A board, with its player

/// A player's board in a card: who, the score (rolling on as it changes),
/// whose turn, away, the marker — then the board itself.
struct AzulBoardCard: View {
    let room: GameRoom
    let state: AzulState
    let board: AzulBoard
    @ObservedObject var store: AzulStore
    let space: Namespace.ID
    let mine: Bool

    private var isTurn: Bool { state.phase == .playing && state.turnId == board.id }

    /// My board on my turn, with tiles picked: a lit line or the floor takes them.
    private var placing: ((AzulLine) -> Void)? {
        guard mine, store.myTurn, store.pickedColour != nil else { return nil }
        let store = store
        return { line in store.place(line) }
    }

    /// The round's wall tiles and their points, during the scoring pause.
    private var scored: [Int: Int] {
        guard state.phase == .scoring, let round = state.roundScore(board.id) else { return [:] }
        return Dictionary(round.placements.map { ($0.tile, $0.points) }, uniquingKeysWith: { a, _ in a })
    }

    /// What the last take put here, ringed on everyone else's boards.
    private var recent: Set<Int> {
        guard !mine, let last = state.last, last.by == board.id else { return [] }
        return Set(last.tiles + (last.tookFirst ? [AzulRules.markerId] : []))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: mine ? 12 : 8) {
            header
            AzulBoardView(board: board, compact: !mine, lit: mine ? store.litLines : [],
                          floorLit: mine && store.pickedColour != nil, scored: scored, recent: recent, space: space,
                          place: placing)
        }
        .padding(mine ? SR.cardPadding : 12)
        .srGlassCard(.paper)
        .overlay {
            if isTurn {
                RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                    .strokeBorder(SR.accent, lineWidth: 2)
            }
        }
        .opacity(board.joined ? 1 : 0.6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(mine ? "azul-my-board" : "azul-board-\(board.id)")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            GameInitial(name: board.name, tone: isTurn ? SR.accent : SR.accentInk, side: mine ? 30 : 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(mine ? "Your board" : board.name)
                    .font(SR.Text.title(mine ? 17 : 15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                chips
            }
            Spacer(minLength: 4)
            score
        }
    }

    @ViewBuilder
    private var chips: some View {
        let words = chipWords
        if !words.isEmpty {
            Text(words.joined(separator: " · ").uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(isTurn ? SR.accent : SR.inkMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chipWords: [String] {
        var words: [String] = []
        if isTurn { words.append(mine ? "Your turn" : "Playing") }
        if board.away { words.append("Away") }
        if !board.joined { words.append("Left") }
        if board.hasFirst { words.append("Starts next round") }
        if board.rows > 0 { words.append(GameResults.count(board.rows, "row", "rows")) }
        return words
    }

    private var score: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(board.score)")
                .font(SR.Text.figure(mine ? 30 : 22))
                .foregroundStyle(SR.ink)
                .srNumeric(Double(board.score))
            if let round = state.phase == .scoring ? state.roundScore(board.id) : nil {
                Text(AzulRules.deltaText(round.delta))
                    .font(SR.Text.label(13))
                    .foregroundStyle(round.delta >= 0 ? SR.good : SR.error)
                    .tablePopIn(delay: 0.9)
            } else {
                Text("POINTS")
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(board.score) points")
        .accessibilityIdentifier("azul-score-\(board.id)")
    }
}

// MARK: The scoring pause

/// The round's tiles going up: each player's wall tiles and what they
/// scored, the floor's cost, and before → after.
struct AzulScoringCard: View {
    let room: GameRoom
    let state: AzulState

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Round \(state.round)", trailing: state.lastRound ? "the last" : nil)
            VStack(spacing: 0) {
                ForEach(Array((state.roundScores ?? []).enumerated()), id: \.element.id) { index, round in
                    if index > 0 { Divider().overlay(SR.divider) }
                    row(round, index: index)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("azul-scoring")
    }

    private func row(_ round: AzulRoundScore, index: Int) -> some View {
        let name = round.id == room.meId ? "You" : room.name(of: round.id)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
                Text(breakdown(round))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text("\(round.before) → \(round.after)")
                .font(SR.Text.figure(18))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
            Text(AzulRules.deltaText(round.delta))
                .font(SR.Text.label(13))
                .foregroundStyle(SR.paper)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(round.delta >= 0 ? SR.good : SR.error))
                .tablePopIn(delay: 0.4 + 0.15 * Double(index))
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("azul-scoring-\(round.id)")
    }

    private func breakdown(_ round: AzulRoundScore) -> String {
        let tiles = round.placements.count
        var bits = [tiles == 0 ? "No full lines" : "\(GameResults.count(tiles, "tile", "tiles")) up, +\(round.gained)"]
        if round.floor > 0 { bits.append("floor −\(round.floor)") }
        return bits.joined(separator: " · ")
    }
}

// MARK: What happened

/// The last few lines of the table's log, newest first.
struct AzulLogStrip: View {
    let state: AzulState

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "What happened")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(state.log.suffix(4).reversed())) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: entry.auto ? "timer" : entry.by == nil ? "circle.grid.2x2" : "square.fill")
                            .font(SR.Text.title(13))
                            .foregroundStyle(entry.auto ? SR.warn : SR.accent)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(entry.text)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityIdentifier("azul-log")
        }
    }
}

// MARK: - Finished

struct AzulFinished: View {
    let room: GameRoom
    @ObservedObject var store: AzulStore
    let done: () -> Void
    @State private var record: TableGameRecord?

    private var state: AzulState? { room.azul }
    private var gameKey: String { TableGameKey.finished(roomId: room.id, startedAt: room.startedAt) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Azul · \(GameDifficulty.label(for: room.difficulty)) · final",
                             title: GameResults.title(room, solo: "Game over", none: "Game over"),
                             strap: GameResults.strap(room))

                Text(AzulRules.endingLine(state?.result))
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("azul-outcome")

                GameStandingsCard(room: room, label: "Final scores", id: "azul-standings", detail: detail) { row in
                    (text: "\(row.score)", spoken: "\(row.score) points")
                }

                if let record {
                    TableRecordCard(record: record, gameKey: gameKey, bestLabel: "Best score", id: "azul-record")
                }

                if let state { walls(state) }

                GameFinishedButtons(room: room, store: store, prefix: "azul", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("azul-finished")
        .onAppear(perform: noteRecord)
    }

    /// A row's line: the wall's score and each bonus. "Left early" for a leaver.
    private func detail(_ row: GameStanding) -> String {
        guard let standing = state?.standing(row.id) else { return "" }
        if standing.result == "left" { return "Left early" }
        guard let bonus = standing.bonus else { return GameResults.count(standing.rows, "complete row", "complete rows") }
        return "Wall \(standing.score - bonus.points) · " + AzulRules.bonusLine(bonus)
    }

    /// Everyone's final wall, mine first.
    private func walls(_ state: AzulState) -> some View {
        let order = state.seated.filter { $0.id == room.meId } + state.seated.filter { $0.id != room.meId }
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "The walls")
            ForEach(order) { board in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(board.id == room.meId ? "You" : board.name)
                            .font(SR.Text.title(15))
                            .foregroundStyle(SR.ink)
                        Spacer(minLength: 8)
                        Text("\(board.score)")
                            .font(SR.Text.figure(20))
                            .foregroundStyle(SR.ink)
                    }
                    AzulBoardView(board: board, compact: true)
                }
                .padding(12)
                .srGlassCard(.paper)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("azul-final-\(board.id)")
            }
        }
    }

    private func noteRecord() {
        guard let state, let mine = state.standing(room.meId), mine.result != "left" else { return }
        let book = TableGameBestStore(gameId: GameKind.azul.rawValue, persists: !SRDemo.isOn)
        record = book.note(variant: GameKind.azul.rawValue, key: gameKey, won: mine.result == "won", score: mine.score)
    }
}
