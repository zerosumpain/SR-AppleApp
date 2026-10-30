import SwiftUI
import UIKit

/// One chess room, from lobby to mate.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the clock the host picked and how to play as the lobby's panel; Start
/// waits for a second player. Play is a banner saying whose move it is, the
/// other side's bar (name, pieces taken, clock), the board the right way up for
/// me, my bar, and Draw / Resign. On my move a tap picks up a piece — it lifts
/// — and lights every square it may go to; a second tap moves it, and every
/// move slides across the board, mine and theirs. A pawn reaching the last
/// rank asks, with the four pieces drawn, what it becomes. The finish is the
/// result with a flourish (confetti for a win), the table, this phone's record
/// and the final board.
///
/// A room game cannot pause: both clocks are the server's, and the other
/// player is on another phone. The board is sized so both bars and the board
/// fit a small phone without scrolling; on the smallest (an SE) Draw / Resign
/// sit a short scroll below, as the board never shrinks under 300pt.
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
            ChessLoading()
        }
    }
}

/// Before the room has answered: a board's worth of squares, not a bare spinner.
struct ChessLoading: View {
    var body: some View {
        VStack(spacing: 16) {
            ChessMiniBoard(pieces: [.knight, .queen, .king], side: 46)
            ProgressView()
                .tint(SR.accent)
            Text("Setting up the board…")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srPaper()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setting up the board")
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

    /// The same colour, deep, in both modes: under white figures (a running
    /// clock, the turn emblem), where the dark-mode tint is too pale to read on.
    var deep: Color { self == .white ? Color(hex: 0x1D5FD6) : Color(hex: 0xC62828) }

    /// A piece's paint, lit from above. The board's woods are the same in
    /// light and dark mode, so the pieces on them are too.
    var pieceFill: LinearGradient {
        let colours: [Color] = self == .white
            ? [Color(hex: 0x7AAEFF), Color(hex: 0x1D5FD6), Color(hex: 0x0F3A8C)]
            : [Color(hex: 0xFF8A7E), Color(hex: 0xC62828), Color(hex: 0x7E1010)]
        return LinearGradient(colors: colours, startPoint: .top, endPoint: .bottom)
    }
}

/// The board's woods and marks. Fixed colours in both modes, a little
/// dimmer in dark mode so the board does not glare off a dark page.
enum ChessBoardPaint {
    static let light = Color(light: 0xF1DFBF, dark: 0xD9C39C)
    static let dark = Color(light: 0xB4835B, dark: 0x9A6E49)
    /// The last move's two squares.
    static let recent = Color(hex: 0xF7D44C)
    /// The frame round the board when nobody is to move.
    static let rim = Color(light: 0x6B4A2E, dark: 0x4A3220)
    /// Writing on the light wood (the promotion picker's names).
    static let ink = Color(hex: 0x2B1D12)
}

// MARK: - Pieces

/// A piece as the board draws it: the filled glyph in its side's colour, lit
/// from above, with a pale rim that keeps it off any square (a red king on
/// the red check square included) and a soft shadow on the wood. Lifted, it
/// rises and grows a little and its shadow spreads.
struct ChessPieceArt: View {
    let piece: ChessPiece
    let side: CGFloat
    var lifted: Bool = false

    var body: some View {
        ZStack {
            Ellipse()
                .fill(RadialGradient(colors: [Color.black.opacity(lifted ? 0.22 : 0.32), Color.black.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: side * 0.3))
                .frame(width: side * (lifted ? 0.7 : 0.6), height: side * 0.18)
                .offset(y: side * 0.32)
            glyph
        }
        .frame(width: side, height: side)
        .animation(.snappy(duration: 0.18), value: lifted)
    }

    private var glyph: some View {
        Text(piece.kind.glyph)
            .font(.system(size: side * 0.76))
            .foregroundStyle(piece.colour.pieceFill)
            .shadow(color: Color.white.opacity(0.95), radius: 0.6)
            .shadow(color: Color.white.opacity(0.6), radius: 1.4)
            .shadow(color: Color.black.opacity(0.3), radius: 1.2, x: 0, y: 1.2)
            .offset(y: lifted ? -side * 0.08 : 0)
            .scaleEffect(lifted ? 1.14 : 1)
    }
}

/// A strip of wood squares with a few pieces on them: the lobby's and the
/// loading page's picture of the game.
struct ChessMiniBoard: View {
    let pieces: [ChessPieceKind]
    var side: CGFloat = 40

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { index, kind in
                ZStack {
                    Rectangle().fill(index % 2 == 0 ? ChessBoardPaint.light : ChessBoardPaint.dark)
                    ChessPieceArt(piece: ChessPiece(colour: index % 2 == 0 ? .white : .black, kind: kind), side: side)
                }
                .frame(width: side, height: side)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ChessBoardPaint.rim))
        .accessibilityHidden(true)
    }
}

// MARK: - Lobby

/// The clock the host picked, in the lobby, how to play in three lines —
/// and, until exactly two are in, that chess is for two.
struct ChessTableCard: View {
    let room: GameRoom

    var body: some View {
        let state = room.chess
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ChessMiniBoard(pieces: [.rook, .knight, .bishop], side: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text((state?.rule ?? GameDifficulty.label(for: room.difficulty)).uppercased())
                        .font(SR.Text.label())
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(SR.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A clock each")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 10) {
                step(1, "Tap one of your pieces: every square it can go to lights up.")
                step(2, "Tap a lit square to move there. Blue (white) moves first.")
                step(3, "Your clock runs only on your move. Checkmate wins; run out of time and you lose.")
            }
            Text("Stalemate and the usual draws end it by themselves; you can resign or offer a draw at any time.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            if room.playing.count != 2 {
                Label(room.playing.count < 2 ? "Needs one more player." : "Chess is for two: somebody will have to sit this out.",
                      systemImage: "person.2.fill")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.accentInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(SR.accent.opacity(0.14)))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chess-needs-two")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chess-table")
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(SR.Text.label(13))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(SR.accent))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.body(15))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - The board

/// Eight by eight, `bottom`'s side nearest the player, in light and dark
/// wood. The pieces are drawn over the squares (`ChessPieceArt`), so a piece
/// sliding to its new square passes over the others: every move, mine and
/// theirs, slides from where it was. The frame round the board takes the
/// colour of the side to move; a picked-up piece lifts off an orange square,
/// the squares it may go to carry a dot (a ring round a piece it would take),
/// the last move is washed yellow, and a king in check glows red.
///
/// The squares are the board's accessibility elements and take the taps; the
/// pieces' layer is pictures only.
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The move sliding in, and how far it has come (0 at the start, 1 home).
    @State private var slide: ChessLastMove?
    @State private var slideProgress: CGFloat = 1

    var body: some View {
        // The square is decided by the width offered, never by what is drawn
        // in it: a clear square takes the proposal and the board is laid
        // over it. A GeometryReader sized by `.aspectRatio` straight inside
        // the page's ScrollView could come out wider than the screen.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { layers }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chess-board")
            // A frame round the board, outside the squares, in the colour of
            // the side to move (wood when nobody is); the same width always,
            // so the board never jumps.
            .padding(5)
            .background(frame)
            .onChange(of: lastMove) { _, move in startSlide(move) }
    }

    private var frame: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(turn?.tint ?? ChessBoardPaint.rim)
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            // Only the frame eases to the new side's colour: the pieces have
            // their own slide, and a fade on top of it would double them.
            .animation(.easeInOut(duration: 0.2), value: turn)
    }

    private var layers: some View {
        GeometryReader { geo in
            let side = floor(min(geo.size.width, geo.size.height) / 8 * 2) / 2
            // Rows of squares, laid out — not 64 squares offset from one spot.
            // An offset moves the drawing but not the layout, so the stack
            // stayed one square big and its frame centred that square: the
            // whole board was drawn from the middle of the box and clipped,
            // leaving only its top-left quarter showing, bottom right.
            ZStack(alignment: .topLeading) {
                squares(side)
                pieces(side)
            }
            .frame(width: side * 8, height: side * 8)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func squares(_ side: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { col in
                        squareView(row: row, col: col, side: side)
                    }
                }
            }
        }
    }

    private func squareView(row: Int, col: Int, side: CGFloat) -> some View {
        let square = self.square(row: row, col: col)
        return ChessSquareView(
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

    private func pieces(_ side: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<64, id: \.self) { i in
                pieceView(i, side: side)
            }
        }
        .frame(width: side * 8, height: side * 8, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func pieceView(_ i: Int, side: CGFloat) -> some View {
        let square = self.square(row: i / 8, col: i % 8)
        if let piece = board[square] {
            let moving = slide?.to == square.name
            let lifted = selected == square
            ChessPieceArt(piece: piece, side: side, lifted: lifted)
                .offset(moving ? slideOffset(side) : CGSize.zero)
                .position(x: (CGFloat(i % 8) + 0.5) * side, y: (CGFloat(i / 8) + 0.5) * side)
                .zIndex(moving || lifted ? 1 : 0)
        }
    }

    /// How far the arriving piece still is from its square.
    private func slideOffset(_ side: CGFloat) -> CGSize {
        guard let slide, let from = ChessSquare(name: slide.from), let to = ChessSquare(name: slide.to) else { return .zero }
        let a = visual(from)
        let b = visual(to)
        let left = 1 - slideProgress
        return CGSize(width: CGFloat(a.col - b.col) * side * left, height: CGFloat(a.row - b.row) * side * left)
    }

    /// A new last move: put the piece back where it came from, then let it slide home.
    private func startSlide(_ move: ChessLastMove?) {
        guard !reduceMotion, let move, ChessSquare(name: move.from) != nil, ChessSquare(name: move.to) != nil else {
            slide = nil
            slideProgress = 1
            return
        }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            slide = move
            slideProgress = 0
        }
        // The next turn of the run loop, so the start is drawn before the slide.
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { slideProgress = 1 }
        }
    }

    /// The square drawn at row `row`, column `col` (0, 0 = top left), for `bottom`'s view.
    private func square(row: Int, col: Int) -> ChessSquare {
        bottom == .white ? ChessSquare(file: col, rank: 7 - row) : ChessSquare(file: 7 - col, rank: row)
    }

    /// Where `square` is drawn: the inverse of `square(row:col:)`.
    private func visual(_ square: ChessSquare) -> (row: Int, col: Int) {
        if bottom == .white { return (row: 7 - square.rank, col: square.file) }
        return (row: square.rank, col: 7 - square.file)
    }
}

/// One square: its wood, its marks, its coordinate, and the tap. The piece on
/// it is drawn by the board's layer above; this says it to VoiceOver.
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
            Rectangle().fill(square.isDark ? ChessBoardPaint.dark : ChessBoardPaint.light)
            if recent { Rectangle().fill(ChessBoardPaint.recent.opacity(0.5)) }
            if selected { Rectangle().fill(SR.accent.opacity(0.6)) }
            if checked {
                Rectangle().fill(RadialGradient(colors: [Color(hex: 0xFF3B30), Color(hex: 0xFF3B30).opacity(0)],
                                                center: .center, startRadius: side * 0.05, endRadius: side * 0.72))
            }
            if target { targetMark }
            if showsRank { coordinate(String(square.rank + 1), alignment: .topLeading) }
            if showsFile { coordinate(String(ChessSquare.files[square.file]), alignment: .bottomTrailing) }
        }
        .contentShape(Rectangle())
        .onTapGesture { if interactive { onTap() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(interactive ? .isButton : [])
        .accessibilityIdentifier("chess-square-\(square.name)")
    }

    @ViewBuilder
    private var targetMark: some View {
        if piece != nil {
            Circle()
                .strokeBorder(SR.accent.opacity(0.9), lineWidth: max(3, side * 0.09))
                .padding(side * 0.04)
        } else {
            Circle()
                .fill(SR.accent.opacity(0.88))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
                .frame(width: side * 0.32, height: side * 0.32)
        }
    }

    private func coordinate(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: max(8, side * 0.2), weight: .bold))
            .foregroundStyle(square.isDark ? ChessBoardPaint.light : ChessBoardPaint.dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(2)
            .accessibilityHidden(true)
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
/// their move, when the bar is edged and washed in their colour and the clock
/// is a lit capsule: amber-edged under 30 seconds, amber with a warning under
/// 10. Ticks, not an animation (see `LiarsDiceTurnBar`).
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
            bar(left: state.remaining(colour, now: now()))
        }
    }

    private func bar(left: Double) -> some View {
        HStack(alignment: .center, spacing: 12) {
            GameInitial(name: name, tone: colour.tint, side: 36)
                .overlay(Circle().strokeBorder(running ? colour.tint.opacity(0.45) : Color.clear, lineWidth: 3).padding(-4))
            VStack(alignment: .leading, spacing: 3) {
                nameLine
                takenLine
            }
            Spacer(minLength: 8)
            ChessClockFace(text: ChessRules.clockText(left), running: running,
                           urgency: ChessClockUrgency.of(left), colour: colour)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name), \(ChessRules.clockText(left)) left")
                .accessibilityIdentifier("chess-clock-\(colour.rawValue)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous).fill(running ? colour.tint.opacity(0.12) : Color.clear))
        .srGlassCard(.paper)
        .overlay(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
            .strokeBorder(running ? colour.tint : Color.clear, lineWidth: 2.5))
        .accessibilityElement(children: .contain)
        .accessibilityValue(running ? "to move" : "")
        .accessibilityIdentifier("chess-bar-\(colour.rawValue)")
    }

    private var nameLine: some View {
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
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(colour.deep))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// One line that shrinks, then truncates: a row of separate glyphs could
    /// not, and with a dozen pieces taken it pushed the bar — and the page
    /// under it — past the screen's edge. Counted per kind ("♟×3"), in the
    /// colour of the side they were taken from.
    private var takenLine: some View {
        HStack(spacing: 4) {
            if !tally.isEmpty {
                Text(tally.map { ChessRules.tallyText($0.kind, $0.count) }.joined(separator: " "))
                    .font(.system(size: 15))
                    .foregroundStyle(colour.other.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .truncationMode(.tail)
            }
            if let ahead = ChessRules.balanceText(state.captured.balance(for: colour)) {
                Text(ahead)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.good)
            }
            if tally.isEmpty, state.captured.balance(for: colour) <= 0 {
                Text("Nothing taken yet")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkGhost)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tally.isEmpty ? "\(name) has taken nothing yet" : "\(name) has taken \(ChessRules.tallySpoken(tally))")
    }
}

/// A side's clock as a chess clock's face: plain when it is not their move,
/// lit in their colour while it runs, amber-edged when low and amber with a
/// warning when nearly out — amber, so it never reads as the red side's colour.
struct ChessClockFace: View {
    let text: String
    let running: Bool
    let urgency: ChessClockUrgency
    let colour: ChessColour

    private static let amber = Color(hex: 0xFFB300)

    var body: some View {
        HStack(spacing: 5) {
            if running {
                Image(systemName: urgency == .critical ? "exclamationmark.triangle.fill" : "timer")
                    .font(.system(size: 13, weight: .bold))
            }
            Text(text)
                .font(SR.Text.figure(24))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(stroke, lineWidth: running ? 3 : 1))
    }

    private var fill: Color {
        guard running else { return Color.clear }
        return urgency == .critical ? Self.amber : colour.deep
    }

    private var stroke: Color {
        guard running else { return SR.line }
        return urgency == .low ? Self.amber : Color.clear
    }

    private var foreground: Color {
        guard running else { return SR.ink }
        return urgency == .critical ? Color.black : Color.white
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
            GameInitial(name: name(colour), tone: colour.tint, side: 24)
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
                tallyRow(tally, colour: colour)
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

    /// Five kinds at most: one line, shrinking a little if it must.
    private func tallyRow(_ tally: [ChessTally], colour: ChessColour) -> some View {
        HStack(spacing: 8) {
            ForEach(tally, id: \.kind) { item in
                HStack(spacing: 1) {
                    Text(item.kind.glyph)
                        .font(.system(size: 22))
                        .foregroundStyle(colour.other.pieceFill)
                        .shadow(color: Color.white.opacity(0.6), radius: 0.8)
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
}

// MARK: - The moves so far

/// The moves as a strip of numbered pairs that scrolls sideways, the latest
/// lit and kept in view. VoiceOver reads the whole list as one line.
struct ChessMoveStripView: View {
    let moves: [String]

    var body: some View {
        let pairs = ChessMoveStrip.pairs(moves)
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Moves", trailing: GameResults.count(moves.count, "move", "moves"))
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pairs) { pair in
                            chip(pair, latest: pair.id == pairs.last?.id)
                                .id(pair.id)
                        }
                    }
                    .padding(.horizontal, SR.cardPadding)
                    .padding(.vertical, 12)
                }
                .onAppear { proxy.scrollTo(Self.lastId(moves.count), anchor: .trailing) }
                .onChange(of: moves.count) { _, count in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(Self.lastId(count), anchor: .trailing) }
                }
            }
            .srGlassCard(.paper)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ChessRules.moveList(moves))
            .accessibilityIdentifier("chess-moves")
        }
    }

    /// The number of the last pair for `count` half-moves.
    private static func lastId(_ count: Int) -> Int { max(1, (count + 1) / 2) }

    private func chip(_ pair: ChessMovePair, latest: Bool) -> some View {
        Text(pair.text)
            .font(SR.Text.mono(14))
            .foregroundStyle(latest ? Color.white : SR.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(latest ? SR.accent : SR.ink.opacity(0.07)))
    }
}

// MARK: - Promotion

/// A pawn on the last rank: the four pieces it may become, drawn big in my
/// colour on wood, over a dimmed board. A tap outside, or Cancel, puts the
/// pawn back.
struct ChessPromotionPicker: View {
    let colour: ChessColour
    let choose: (ChessPieceKind) -> Void
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { cancel() }
                .accessibilityHidden(true)
            card
        }
    }

    private var card: some View {
        VStack(spacing: 16) {
            Text("The pawn becomes…")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                ForEach(ChessRules.promotionChoices, id: \.self) { kind in
                    choice(kind)
                }
            }
            Button(role: .cancel) {
                SRHaptic.select()
                cancel()
            } label: {
                SRButtonLabel(title: "Cancel", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("chess-promote-cancel")
        }
        .padding(20)
        .srGlassCard(.paper)
        .padding(.horizontal, SR.gutter)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func choice(_ kind: ChessPieceKind) -> some View {
        Button {
            choose(kind)
        } label: {
            VStack(spacing: 2) {
                ChessPieceArt(piece: ChessPiece(colour: colour, kind: kind), side: 56)
                Text(kind.name)
                    .font(SR.Text.mono())
                    .foregroundStyle(ChessBoardPaint.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ChessBoardPaint.light))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colour.tint, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(kind.name)
        .accessibilityIdentifier("chess-promote-\(String(kind.rawValue))")
    }
}

// MARK: - Playing

struct ChessPlaying: View {
    let room: GameRoom
    @ObservedObject var store: ChessStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The banner's little jump when the move comes round to me.
    @State private var pop = false

    private var state: ChessState? { room.chess }
    /// The colour nearest me: mine at the board, white when watching.
    private var bottom: ChessColour { store.myColour ?? .white }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                page(boardCap: boardCap(geo.size))
            }
            .srGround(.warm)
            .accessibilityIdentifier("chess-playing")
        }
        .onChange(of: store.refusal) { _, refusal in
            if let refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
        .onChange(of: store.myTurn) { _, mine in
            if mine { bounce() }
        }
        .confirmationDialog("Resign this game?", isPresented: $store.confirmingResign, titleVisibility: .visible) {
            Button("Resign", role: .destructive) { store.resign() }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("The other side wins it.")
        }
        .overlay {
            if store.promotion != nil {
                ChessPromotionPicker(colour: bottom, choose: { store.promote(to: $0) }, cancel: { store.cancelPromotion() })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: store.promotion)
    }

    /// The widest the board may be: the width, unless that would push my bar
    /// and the buttons off a short screen — never so small a finger misses.
    private func boardCap(_ size: CGSize) -> CGFloat {
        let byWidth = size.width - SR.gutter * 2
        let byHeight = size.height - 320
        return max(300, min(byWidth, byHeight))
    }

    private func page(boardCap: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let state {
                ChessPlayerBar(room: room, state: state, colour: bottom.other, now: { store.serverNow() })
                board(state)
                    .frame(maxWidth: boardCap)
                    .frame(maxWidth: .infinity)
                ChessPlayerBar(room: room, state: state, colour: bottom, now: { store.serverNow() })
                statusLine
                    .frame(maxWidth: .infinity)
                if store.seated { actions }
                ChessCapturedCard(room: room, state: state, top: bottom.other)
                    .padding(.top, 8)
                if !state.moves.isEmpty { ChessMoveStripView(moves: state.moves) }
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

    private func board(_ state: ChessState) -> some View {
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
    }

    // MARK: Whose move

    /// The side to move's emblem, then the kicker and the headline, on a
    /// banner washed in that side's colour — red-edged in check.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            emblem
            VStack(alignment: .leading, spacing: 3) {
                Text("CHESS · MOVE \(ChessRules.moveNumber(state?.moves ?? [])) · \(GameDifficulty.label(for: room.difficulty).uppercased())")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(headline)
                    .font(SR.Text.display(24))
                    .foregroundStyle(headlineColour)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chess-headline")
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(bannerWash))
        .srGlassCard(.paper, radius: 22)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(state?.check == true ? SR.error : Color.clear, lineWidth: 2.5))
        .scaleEffect(pop ? 1.03 : 1)
    }

    private var emblem: some View {
        let turn = state?.turn ?? .white
        let inCheck = state?.check == true
        return ZStack {
            Circle().fill(inCheck ? SR.error : turn.deep)
            Text(ChessPieceKind.king.glyph)
                .font(.system(size: 26))
                .foregroundStyle(Color.white)
        }
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
    }

    private var bannerWash: Color {
        guard let state, state.phase == .playing else { return Color.clear }
        return store.myTurn ? state.turn.tint.opacity(0.16) : state.turn.tint.opacity(0.06)
    }

    private var headlineColour: Color {
        guard let state else { return SR.ink }
        return state.check ? SR.error : state.turn.tint
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

    /// The banner jumps a little when the move comes round to me.
    private func bounce() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { pop = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pop = false }
        }
    }

    // MARK: What to do now

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
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(SR.accent.opacity(0.14)))
                .accessibilityIdentifier("chess-draw-offered")
        } else if store.sending {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(SR.accent)
                Text("Sending your move…")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            .accessibilityElement(children: .combine)
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

    private var drawTitle: String {
        if store.drawOfferedToMe { return "Accept the draw" }
        return store.drawOfferedByMe ? "Draw offered" : "Offer a draw"
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { store.draw() } label: {
                SRButtonLabel(title: drawTitle, icon: "hand.raised.fill", fill: true)
                    .frame(minHeight: 44)
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
                    .frame(minHeight: 44)
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(store.sending)
            .accessibilityIdentifier("chess-resign")
        }
    }
}

// MARK: - Finished

struct ChessFinished: View {
    let room: GameRoom
    @ObservedObject var store: ChessStore
    let done: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var book = ChessRecordBook()
    @State private var news: ChessRecordNews?

    private var state: ChessState? { room.chess }
    private var bottom: ChessColour { store.myColour ?? .white }

    /// How the game went for me.
    private enum Mine { case won, drawn, lost, watched }

    private var mine: Mine {
        guard let state, let result = state.result else { return .watched }
        if result.winnerId == room.meId { return .won }
        guard state.colour(of: room.meId) != nil else { return .watched }
        return result.winnerId == nil ? .drawn : .lost
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                hero

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

                if book.played > 0 { recordCard }

                if let state {
                    ChessCapturedCard(room: room, state: state, top: bottom.other)
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "The final position", trailing: GameResults.count(state.moves.count, "move", "moves"))
                        ChessBoardView(board: state.board, bottom: bottom, lastMove: state.lastMove, checked: state.checkedKing)
                    }
                    if !state.moves.isEmpty { ChessMoveStripView(moves: state.moves) }
                }

                GameFinishedButtons(room: room, store: store, prefix: "chess", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("chess-finished")
        .overlay {
            if mine == .won {
                ChessMarbleConfettiView(seed: UInt64(truncatingIfNeeded: (state?.moves.count ?? 0) &+ 11))
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            if room.winnerIds.contains(room.meId) { SRHaptic.ok() }
            recordResult()
            withAnimation(reduceMotion ? nil : Animation.spring(response: 0.45, dampingFraction: 0.6)) { appeared = true }
        }
    }

    // MARK: The result

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                emblem
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chess · \(state?.rule ?? GameDifficulty.label(for: room.difficulty)) · final".uppercased())
                        .font(SR.Text.label())
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(SR.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(GameResults.title(room, solo: "Game over", none: "A draw"))
                        .font(SR.Text.hero(34))
                        .tracking(-0.6)
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 0)
            }
            if let line = state?.outcomeLine(name: { $0 == room.meId ? "You" : room.name(of: $0) }) {
                Text(line)
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chess-outcome")
            }
            if let strap = GameResults.strap(room) {
                Text(strap)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SR.cardPadding)
        .background(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous).fill(tone.opacity(0.12)))
        .srGlassCard(.paper)
        .overlay(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous).strokeBorder(tone.opacity(0.5), lineWidth: 1.5))
    }

    private var emblem: some View {
        ZStack {
            Circle().fill(tone)
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .frame(width: 60, height: 60)
        .scaleEffect(appeared ? 1 : 0.5)
        .rotationEffect(.degrees(appeared ? 0 : -20))
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch mine {
        case .won: return "crown.fill"
        case .drawn: return "equal"
        case .lost: return "flag.fill"
        case .watched: return "checkerboard.rectangle"
        }
    }

    private var tone: Color {
        switch mine {
        case .won: return SR.accent
        case .drawn: return SR.inkSecondary
        case .lost: return (state?.colour(of: room.meId) ?? .white).deep
        case .watched: return SR.accentInk
        }
    }

    // MARK: This phone's record

    private var recordCard: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Your chess on this phone", trailing: book.played == 1 ? "1 game" : "\(book.played) games")
            HStack(spacing: 0) {
                figure("\(book.wins)", "Won", tone: SR.good)
                figure("\(book.draws)", "Drawn", tone: SR.inkSecondary)
                figure("\(book.losses)", "Lost", tone: SR.error)
                figure("\(book.bestStreak)", "Best run", tone: SR.accent)
            }
            .padding(.vertical, 14)
            .srGlassCard(.paper)
            if let flourish {
                Label(flourish, systemImage: "sparkles")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.accentInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chess-record")
    }

    private func figure(_ value: String, _ label: String, tone: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(SR.Text.figure(26))
                .foregroundStyle(tone)
                .monospacedDigit()
            Text(label.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var flourish: String? {
        guard let news, news.counted else { return nil }
        if news.newBestStreak { return "\(book.bestStreak) wins in a row — your best run yet." }
        if news.newQuickest, let quickest = book.quickestWin { return "Your quickest win: \(quickest) moves." }
        if mine == .won, book.streak > 1 { return "\(book.streak) wins in a row." }
        return nil
    }

    /// Count this game in the phone's record, once — never the demo's.
    private func recordResult() {
        let records = ChessRecordStore()
        var loaded = records.load()
        if !SRDemo.isOn, let state, let result = state.result, state.colour(of: room.meId) != nil {
            let outcome: ChessRecordBook.Outcome
            if result.winnerId == room.meId {
                outcome = .won
            } else if result.winnerId == nil {
                outcome = .drawn
            } else {
                outcome = .lost
            }
            // The room and when the last turn began: a rematch in the same
            // room with the same length and ending (two Fool's mates) is
            // still a game of its own.
            let game = "\(room.id)@\(Int((state.turnStartedAt ?? 0).rounded()))"
            let key = ChessRecordBook.key(room: game, moves: state.moves.count, outcome: result.outcome)
            let made = loaded.record(key: key, outcome: outcome, moves: state.moves.count)
            if made.counted { records.save(loaded) }
            news = made
        }
        book = loaded
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
