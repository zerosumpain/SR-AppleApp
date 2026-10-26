import SwiftUI
import UIKit

/// One chess room, from lobby to mate.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the clock the host picked as the lobby's panel; Start waits for a
/// second player. Play is the other side's bar (name, pieces taken, clock),
/// the board the right way up for me, my bar, and Draw / Resign. On my move a
/// tap picks up a piece and lights every square it may go to; a second tap
/// moves it, and a pawn reaching the last rank asks what it becomes. The
/// finish is the result in a sentence, the table and the final board.
struct ChessScreen: View {
    let roomId: String
    @StateObject private var store: ChessStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: ChessStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Chess")
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
    }

    private var immersive: Bool {
        guard !store.ended, let room = store.room else { return false }
        return ChessScreenPhase.of(room) == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "chess-ended", done: { dismiss() })
        } else if let room = store.room {
            switch ChessScreenPhase.of(room) {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "chess", done: { dismiss() },
                          panel: AnyView(ChessTableCard(room: room)),
                          startBlocked: room.playing.count != 2)
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Blue (white) moves first. Your clock runs only on your move.",
                                  id: "chess-countdown")
            case .playing:
                ChessPlaying(room: room, store: store)
            case .finished:
                ChessFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "chess-ended", done: { dismiss() })
            }
        } else {
            ProgressView()
                .tint(SR.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .srPaper()
        }
    }
}

// MARK: - Each side's colour

extension ChessColour {
    /// The side's own colour, on its pieces, its bar and the board's edge on
    /// its move: blue and red read apart at a glance, where cream and ink
    /// left the family asking whose go it was. Fixed, never the palette's
    /// accent or alert colours, so a theme cannot make the two sides alike.
    var tint: Color {
        self == .white ? Color(light: 0x1D5FD6, dark: 0x6EA8FF) : Color(light: 0xC62828, dark: 0xFF7468)
    }

    /// "Blue" — the colour the pieces are drawn in, beside the rule's name.
    var tintName: String { self == .white ? "Blue" : "Red" }
}

// MARK: - Lobby

/// The clock the host picked, in the lobby — and, until exactly two are in,
/// that chess is for two.
struct ChessTableCard: View {
    let room: GameRoom

    var body: some View {
        let state = room.chess
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 2) {
                ForEach(Array([ChessPieceKind.rook, .knight, .bishop].enumerated()), id: \.offset) { _, kind in
                    Text(kind.glyph)
                        .font(.system(size: 24))
                        .foregroundStyle(SR.ink)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text((state?.rule ?? GameDifficulty.label(for: room.difficulty)).uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text("A clock each")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text("Run out of time and you lose. Checkmate, stalemate and the usual draws end it by themselves; you can resign or offer a draw at any time.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if room.playing.count != 2 {
                    Text(room.playing.count < 2 ? "Needs one more player." : "Chess is for two: somebody will have to sit this out.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .accessibilityIdentifier("chess-needs-two")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chess-table")
    }
}

// MARK: - The board

/// Eight by eight, `bottom`'s side nearest the player. Pieces are the filled
/// glyphs in each side's colour (`ChessColour.tint`), and the board's edge
/// takes the colour of the side to move; a picked-up piece sits on an orange square, the
/// squares it may go to carry a dot (a ring over a piece it would take), the
/// last move is tinted, and a king in check sits on red.
struct ChessBoardView: View {
    let board: ChessBoard
    /// The colour nearest the player.
    let bottom: ChessColour
    var selected: ChessSquare? = nil
    var targets: Set<String> = []
    var lastMove: ChessLastMove? = nil
    var checked: ChessSquare? = nil
    /// The side to move, while the game is on: the edge is drawn in its colour.
    var turn: ChessColour? = nil
    var interactive: Bool = false
    var onTap: (ChessSquare) -> Void = { _ in }

    var body: some View {
        // The square is decided by the width offered, never by what is drawn
        // in it: a clear square takes the proposal and the board is laid
        // over it. A GeometryReader sized by `.aspectRatio` straight inside
        // the page's ScrollView could come out wider than the screen.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { squares }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(SR.ink.opacity(0.25), lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chess-board")
            // A frame round the board, outside the squares, in the colour of
            // the side to move; the same width when nobody is, so the board
            // never jumps.
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(turn?.tint ?? Color.clear))
            .animation(.easeInOut(duration: 0.2), value: turn)
    }

    private var squares: some View {
        GeometryReader { geo in
            let side = floor(min(geo.size.width, geo.size.height) / 8 * 2) / 2
            // Rows of squares, laid out — not 64 squares offset from one spot.
            // An offset moves the drawing but not the layout, so the stack
            // stayed one square big and its frame centred that square: the
            // whole board was drawn from the middle of the box and clipped,
            // leaving only its top-left quarter showing, bottom right.
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { col in
                            let i = row * 8 + col
                            let square = self.square(atVisual: i)
                            ChessSquareView(
                                square: square,
                                piece: board[square],
                                side: side,
                                selected: selected == square,
                                target: targets.contains(square.name),
                                recent: lastMove?.from == square.name || lastMove?.to == square.name,
                                checked: checked == square,
                                showsFile: row == 7,
                                showsRank: col == 0,
                                interactive: interactive,
                                onTap: { onTap(square) }
                            )
                            .frame(width: side, height: side)
                        }
                    }
                }
            }
            .frame(width: side * 8, height: side * 8)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// The square drawn at visual index `i` (0 = top left), for `bottom`'s view.
    private func square(atVisual i: Int) -> ChessSquare {
        let col = i % 8
        let row = i / 8
        return bottom == .white ? ChessSquare(file: col, rank: 7 - row) : ChessSquare(file: 7 - col, rank: row)
    }
}

struct ChessSquareView: View {
    let square: ChessSquare
    let piece: ChessPiece?
    let side: CGFloat
    let selected: Bool
    let target: Bool
    let recent: Bool
    let checked: Bool
    let showsFile: Bool
    let showsRank: Bool
    let interactive: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(square.isDark ? SR.accentInk.opacity(0.42) : SR.paper)
            if recent { Rectangle().fill(SR.warn.opacity(0.38)) }
            if selected { Rectangle().fill(SR.accent.opacity(0.55)) }
            if checked { Rectangle().fill(SR.error.opacity(0.6)) }
            if target {
                if piece != nil {
                    Circle()
                        .strokeBorder(SR.accent.opacity(0.9), lineWidth: max(3, side * 0.09))
                        .padding(side * 0.06)
                } else {
                    Circle()
                        .fill(SR.accent.opacity(0.85))
                        .frame(width: side * 0.3, height: side * 0.3)
                }
            }
            if let piece {
                Text(piece.kind.glyph)
                    .font(.system(size: side * 0.74))
                    .foregroundStyle(piece.colour.tint)
                    // A pale rim keeps either colour off the tinted squares —
                    // a red king on the red check square included.
                    .shadow(color: .white.opacity(0.9), radius: 0.6)
                    .shadow(color: .white.opacity(0.6), radius: 1.4)
            }
            if showsRank {
                Text(String(square.rank + 1))
                    .font(.system(size: max(8, side * 0.2), weight: .semibold))
                    .foregroundStyle(square.isDark ? SR.paper.opacity(0.8) : SR.ink.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(2)
                    .accessibilityHidden(true)
            }
            if showsFile {
                Text(String(ChessSquare.files[square.file]))
                    .font(.system(size: max(8, side * 0.2), weight: .semibold))
                    .foregroundStyle(square.isDark ? SR.paper.opacity(0.8) : SR.ink.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(2)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if interactive { onTap() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(interactive ? .isButton : [])
        .accessibilityIdentifier("chess-square-\(square.name)")
    }

    private var spoken: String {
        var bits = [square.name, piece?.spoken ?? "empty"]
        if selected { bits.append("picked up") }
        if target { bits.append(piece != nil ? "can take" : "can move here") }
        if checked { bits.append("in check") }
        return bits.joined(separator: ", ")
    }
}

// MARK: - A player's bar

/// Name, colour, what they have taken, and their clock — ticking while it is
/// their move, when the bar is edged and washed in their colour. Ticks, not an
/// animation (see `LiarsDiceTurnBar`).
struct ChessPlayerBar: View {
    let room: GameRoom
    let state: ChessState
    let colour: ChessColour
    let now: () -> Double?

    private var playerId: String? { state.player(of: colour) }
    private var name: String {
        guard let playerId else { return colour.name }
        return playerId == room.meId ? "You" : room.name(of: playerId)
    }
    private var running: Bool { state.phase == .playing && state.turn == colour }
    private var tally: [ChessTally] { state.captured.tally(by: colour) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: running ? 0.25 : 60)) { _ in
            let left = state.remaining(colour, now: now())
            HStack(alignment: .center, spacing: 12) {
                GameInitial(name: name, tone: colour.tint)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(SR.Text.title())
                            .foregroundStyle(SR.ink)
                            .lineLimit(1)
                        Text(colour.tintName.uppercased())
                            .font(SR.Text.label())
                            .tracking(1)
                            .foregroundStyle(colour.tint)
                            .accessibilityLabel("\(colour.tintName), playing \(colour.name.lowercased())")
                        if running {
                            Text("TO MOVE")
                                .font(SR.Text.label())
                                .tracking(1)
                                .foregroundStyle(SR.paper)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(colour.tint))
                        }
                    }
                    // One line that shrinks, then truncates: a row of separate
                    // glyphs could not, and with a dozen pieces taken it pushed
                    // the bar — and the page under it — past the screen's edge.
                    // Counted per kind ("♟×3"), in the colour of the side they
                    // were taken from.
                    HStack(spacing: 4) {
                        if !tally.isEmpty {
                            Text(tally.map { ChessRules.tallyText($0.kind, $0.count) }.joined(separator: " "))
                                .font(.system(size: 13))
                                .foregroundStyle(colour.other.tint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .truncationMode(.tail)
                        }
                        if let ahead = ChessRules.balanceText(state.captured.balance(for: colour)) {
                            Text(ahead)
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                        }
                        if tally.isEmpty, state.captured.balance(for: colour) <= 0 {
                            Text("Nothing taken yet")
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkGhost)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(takenSpoken)
                }
                Spacer(minLength: 8)
                Text(ChessRules.clockText(left))
                    .font(SR.Text.figure(26))
                    .foregroundStyle(running ? (left < 20_000 ? SR.error : colour.tint) : SR.ink)
                    .monospacedDigit()
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(running ? colour.tint.opacity(0.14) : Color.clear))
                    .accessibilityLabel("\(name), \(ChessRules.clockText(left)) left")
                    .accessibilityIdentifier("chess-clock-\(colour.rawValue)")
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous).fill(running ? colour.tint.opacity(0.1) : Color.clear))
            .srGlassCard(.paper)
            .overlay(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .strokeBorder(running ? colour.tint : Color.clear, lineWidth: 2.5))
            .accessibilityElement(children: .contain)
            .accessibilityValue(running ? "to move" : "")
            .accessibilityIdentifier("chess-bar-\(colour.rawValue)")
        }
    }

    private var takenSpoken: String {
        tally.isEmpty ? "\(name) has taken nothing yet" : "\(name) has taken \(ChessRules.tallySpoken(tally))"
    }
}

// MARK: - What each side has taken

/// The captures summed up: a row per side, each kind it has taken with how
/// many (drawn in the colour of the side that lost them), and the points.
/// `top` is listed first, as on the board.
struct ChessCapturedCard: View {
    let room: GameRoom
    let state: ChessState
    let top: ChessColour

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Captured", trailing: lead)
            VStack(spacing: 0) {
                row(top)
                Divider().overlay(SR.divider)
                row(top.other)
            }
            .padding(.horizontal, SR.cardPadding)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chess-captured")
    }

    /// "Blue +4", or "Level".
    private var lead: String {
        let white = state.captured.balance(for: .white)
        if white == 0 { return "Level" }
        let ahead: ChessColour = white > 0 ? .white : .black
        return "\(name(ahead)) +\(abs(white))"
    }

    private func name(_ colour: ChessColour) -> String {
        guard let id = state.player(of: colour) else { return colour.tintName }
        return id == room.meId ? "You" : room.name(of: id)
    }

    private func row(_ colour: ChessColour) -> some View {
        let tally = state.captured.tally(by: colour)
        let points = state.captured.points(by: colour)
        return HStack(alignment: .center, spacing: 10) {
            GameInitial(name: name(colour), tone: colour.tint, side: 22)
            Text(name(colour))
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .frame(minWidth: 44, alignment: .leading)
            if tally.isEmpty {
                Text("Nothing yet")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkGhost)
            } else {
                // Five kinds at most: one line, shrinking a little if it must.
                HStack(spacing: 8) {
                    ForEach(tally, id: \.kind) { item in
                        HStack(spacing: 1) {
                            Text(item.kind.glyph)
                                .font(.system(size: 20))
                                .foregroundStyle(colour.other.tint)
                            if item.count > 1 {
                                Text("×\(item.count)")
                                    .font(SR.Text.mono(13))
                                    .foregroundStyle(SR.ink)
                            }
                        }
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            Text(points == 1 ? "1 pt" : "\(points) pts")
                .font(SR.Text.mono())
                .foregroundStyle(points > 0 ? SR.ink : SR.inkGhost)
                .monospacedDigit()
                .fixedSize()
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name(colour)) took \(ChessRules.tallySpoken(tally)), \(points) points")
        .accessibilityIdentifier("chess-captured-\(colour.rawValue)")
    }
}

// MARK: - Playing

struct ChessPlaying: View {
    let room: GameRoom
    @ObservedObject var store: ChessStore

    private var state: ChessState? { room.chess }
    /// The colour nearest me: mine at the board, white when watching.
    private var bottom: ChessColour { store.myColour ?? .white }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let state {
                    ChessPlayerBar(room: room, state: state, colour: bottom.other, now: { store.serverNow() })
                    ChessBoardView(
                        board: state.board,
                        bottom: bottom,
                        selected: store.selected,
                        targets: store.targetNames,
                        lastMove: state.lastMove,
                        checked: state.checkedKing,
                        turn: state.phase == .playing ? state.turn : nil,
                        interactive: store.myTurn && !store.sending,
                        onTap: { store.tap($0) }
                    )
                    .padding(.horizontal, 2)
                    ChessPlayerBar(room: room, state: state, colour: bottom, now: { store.serverNow() })
                    statusLine
                        .frame(maxWidth: .infinity)
                    if store.seated { actions }
                    ChessCapturedCard(room: room, state: state, top: bottom.other)
                    if !state.moves.isEmpty { moveList(state.moves) }
                    if let rule = state.rule {
                        Text(rule)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("chess-rule")
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("chess-playing")
        .onChange(of: store.refusal) { _, refusal in
            if let refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
        .confirmationDialog("Resign this game?", isPresented: $store.confirmingResign, titleVisibility: .visible) {
            Button("Resign", role: .destructive) { store.resign() }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("The other side wins it.")
        }
        .confirmationDialog(
            "The pawn becomes…",
            isPresented: Binding(get: { store.promotion != nil }, set: { if !$0 { store.cancelPromotion() } }),
            titleVisibility: .visible
        ) {
            ForEach(ChessRules.promotionChoices, id: \.self) { kind in
                Button("\(kind.glyph) \(kind.name)") { store.promote(to: kind) }
            }
            Button("Cancel", role: .cancel) { store.cancelPromotion() }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CHESS · MOVE \(ChessRules.moveNumber(state?.moves ?? [])) · \(GameDifficulty.label(for: room.difficulty).uppercased())")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text(headline)
                    .font(SR.Text.display(24))
                    .foregroundStyle(state?.check == true ? SR.error : (state?.turn.tint ?? SR.ink))
                    .accessibilityIdentifier("chess-headline")
            }
            Spacer(minLength: 8)
        }
    }

    private var headline: String {
        guard let state else { return "Setting up…" }
        let check = state.check ? " — check!" : ""
        if store.myTurn {
            if store.selected != nil { return "Now tap where it goes" }
            return "Your move\(check)"
        }
        guard let turn = state.turnId else { return "Waiting…" }
        return "\(room.name(of: turn)) to move\(check)"
    }

    @ViewBuilder
    private var statusLine: some View {
        if let refusal = store.refusal {
            Label(refusal, systemImage: "exclamationmark.circle")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.error)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("chess-refusal")
        } else if store.drawOfferedToMe, let by = state?.drawOfferBy {
            Label("\(room.name(of: by)) offers a draw.", systemImage: "hand.raised")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.accentInk)
                .accessibilityIdentifier("chess-draw-offered")
        } else if store.drawOfferedByMe {
            Text("Draw offered — it stands until they move.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .accessibilityIdentifier("chess-draw-mine")
        } else if store.myTurn {
            Text(store.selected == nil ? "Tap a piece to pick it up." : "Tap a lit square, or the piece to put it down.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .accessibilityIdentifier("chess-hint")
        } else if !store.seated {
            Text("You are watching this one.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { store.draw() } label: {
                SRButtonLabel(title: store.drawOfferedToMe ? "Accept the draw" : store.drawOfferedByMe ? "Draw offered" : "Offer a draw",
                              icon: "hand.raised.fill", fill: true)
            }
            .srButton(store.drawOfferedToMe ? .prominent : .regular)
            .controlSize(.large)
            .disabled(store.sending || store.drawOfferedByMe)
            .accessibilityIdentifier("chess-draw")
            Button {
                SRHaptic.select()
                store.confirmingResign = true
            } label: {
                SRButtonLabel(title: "Resign", icon: "flag.fill", fill: true)
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(store.sending)
            .accessibilityIdentifier("chess-resign")
        }
    }

    private func moveList(_ moves: [String]) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Moves", trailing: GameResults.count(moves.count, "move", "moves"))
            Text(ChessRules.moveList(moves))
                .font(SR.Text.mono(13))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SR.cardPadding)
                .srGlassCard(.paper)
                .accessibilityIdentifier("chess-moves")
        }
    }
}

// MARK: - Finished

struct ChessFinished: View {
    let room: GameRoom
    @ObservedObject var store: ChessStore
    let done: () -> Void

    private var state: ChessState? { room.chess }
    private var bottom: ChessColour { store.myColour ?? .white }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Chess · \(state?.rule ?? GameDifficulty.label(for: room.difficulty)) · final",
                             title: GameResults.title(room, solo: "Game over", none: "A draw"),
                             strap: GameResults.strap(room))

                if let line = state?.outcomeLine(name: { $0 == room.meId ? "You" : room.name(of: $0) }) {
                    Text(line)
                        .font(SR.Text.bodyMedium(16))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("chess-outcome")
                }

                GameStandingsCard(
                    room: room,
                    label: "Result",
                    id: "chess-standings",
                    detail: detail,
                    figure: { row in
                        guard let s = standing(row.id) else { return nil }
                        let text = ChessRules.clockText(s.clockMs)
                        return (text: text, spoken: "\(text) left on the clock")
                    }
                )

                if let state {
                    ChessCapturedCard(room: room, state: state, top: bottom.other)
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "The final position", trailing: GameResults.count(state.moves.count, "move", "moves"))
                        ChessBoardView(board: state.board, bottom: bottom, lastMove: state.lastMove, checked: state.checkedKing)
                        if !state.moves.isEmpty {
                            Text(ChessRules.moveList(state.moves))
                                .font(SR.Text.mono(13))
                                .foregroundStyle(SR.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(SR.cardPadding)
                                .srGlassCard(.paper)
                                .accessibilityIdentifier("chess-moves")
                        }
                    }
                }

                GameFinishedButtons(room: room, store: store, prefix: "chess", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("chess-finished")
        .onAppear { if room.winnerIds.contains(room.meId) { SRHaptic.ok() } }
    }

    private func standing(_ id: String) -> ChessStanding? {
        state?.standings?.first { $0.id == id }
    }

    private func detail(_ row: GameStanding) -> String {
        guard let s = standing(row.id) else { return "" }
        let colour = s.colour?.name ?? ""
        switch s.result {
        case "won": return "\(colour) · won"
        case "lost": return "\(colour) · lost"
        default: return "\(colour) · draw"
        }
    }
}
