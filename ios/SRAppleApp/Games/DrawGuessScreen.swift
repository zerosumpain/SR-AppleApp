import SwiftUI
import UIKit

/// One Draw & Guess room, from lobby to the final standings.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the host's options as the lobby's panel; Start waits for a second
/// player. Then, turn by turn: the drawer picks one of three words, draws it on
/// a square of paper (their own line appears under the finger at once and
/// streams to the others as it goes), while everyone else watches it appear,
/// reads the blanks and types guesses. The word is revealed between drawings.
struct DrawGuessScreen: View {
    let roomId: String
    @StateObject private var store: DrawGuessStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: DrawGuessStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Draw & Guess")
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
        guard !store.ended, store.room != nil else { return false }
        return store.phase == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "drawguess-ended", done: { dismiss() })
        } else if let room = store.room {
            switch store.phase {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "drawguess", done: { dismiss() },
                          panel: AnyView(DrawGuessOptionsCard(room: room)),
                          startBlocked: room.playing.count < 2)
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Take turns to draw. Guess the others' drawings — sooner scores more.",
                                  id: "drawguess-countdown")
            case .picking, .drawing, .reveal:
                DrawGuessPlaying(room: room, store: store)
            case .finished:
                DrawGuessFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "drawguess-ended", done: { dismiss() })
            }
        } else {
            ProgressView()
                .tint(SR.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .srPaper()
        }
    }
}

// MARK: - Lobby

/// The host's options, in the lobby — and why Start waits.
struct DrawGuessOptionsCard: View {
    let room: GameRoom

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "scribble.variable")
                .font(SR.Text.display(26))
                .foregroundStyle(SR.paper)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(SR.accentInk))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(DrawGuessSettings.about(room).uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text("Everyone draws \(room.drawGuess?.turnsEach == 2 ? "twice" : "once")")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(room.playing.count < 2
                     ? "Needs two players at least — ask someone in."
                     : "Guess sooner to score more. The drawer scores for every right guess.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("drawguess-options")
    }
}

// MARK: - A turn

struct DrawGuessPlaying: View {
    let room: GameRoom
    @ObservedObject var store: DrawGuessStore
    @FocusState private var typing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                DrawGuessTimeBar(room: room, store: store)
                DrawGuessSeats(room: room, store: store)
                wordRow
                if store.phase == .picking && store.isDrawer {
                    DrawGuessPicker(store: store)
                } else {
                    DrawGuessCanvasView(store: store)
                }
                if store.phase == .drawing && store.isDrawer {
                    DrawGuessTools(store: store)
                } else if store.phase == .drawing {
                    guessBox
                }
                if store.phase == .reveal { DrawGuessRevealCard(room: room, store: store) }
                noteLine
                DrawGuessFeed(room: room, store: store)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        // A finger on the canvas draws; it must not scroll the page.
        .scrollDisabled(store.pen.isDown)
        .scrollDismissesKeyboard(.interactively)
        .srGround(.warm)
        .accessibilityIdentifier("drawguess-playing")
        .onChange(of: store.shakes) { _, _ in
            if let note = store.note { UIAccessibility.post(notification: .announcement, argument: note) }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker)
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text(title)
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("drawguess-title")
            }
            Spacer(minLength: 8)
            WordleTimer(room: room, store: store, id: "drawguess-timer")
        }
    }

    private var kicker: String {
        let turn = store.turn.map { "TURN \($0.index + 1) OF \($0.of)" } ?? "DRAW & GUESS"
        return "\(turn) · \(GameDifficulty.label(for: room.difficulty).uppercased())"
    }

    private var title: String {
        switch store.phase {
        case .picking: return store.isDrawer ? "Pick a word to draw" : "\(store.drawerName) is picking a word"
        case .drawing: return store.isDrawer ? "You're drawing" : "\(store.drawerName) is drawing"
        case .reveal: return "It was…"
        default: return "Draw & Guess"
        }
    }

    /// The drawer's word, a guesser's blanks, or the word at the reveal.
    @ViewBuilder
    private var wordRow: some View {
        let turn = store.turn
        VStack(spacing: 6) {
            if let word = turn?.word, store.phase != .picking {
                Text(word.uppercased())
                    .font(SR.Text.hero(34))
                    .tracking(2)
                    .foregroundStyle(store.phase == .reveal ? SR.accent : SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .accessibilityLabel(store.isDrawer && store.phase == .drawing ? "Your word, \(word)" : "The word, \(word)")
            } else if let hint = turn?.hint, store.phase == .drawing {
                Text(DrawGuessText.spaced(hint).uppercased())
                    .font(SR.Text.hero(30))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .accessibilityLabel("The word: \(DrawGuessText.letters(hint))")
                Text(DrawGuessText.letters(hint).uppercased())
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityHidden(true)
            } else {
                Text(" ")
                    .font(SR.Text.hero(30))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("drawguess-word")
    }

    private var guessBox: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $store.guessText)
                .font(SR.Text.body(17))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .focused($typing)
                .onSubmit {
                    store.sendGuess()
                    typing = true
                }
                .disabled(!store.canGuess)
                .padding(.horizontal, 14)
                .frame(minHeight: SR.tapTarget + 4)
                .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
                .accessibilityIdentifier("drawguess-guess-field")
            Button { store.sendGuess() } label: {
                SRButtonLabel(title: "Guess", icon: "paperplane.fill")
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(!store.canSendGuess)
            .accessibilityIdentifier("drawguess-guess-send")
        }
        .modifier(WordleShake(animatableData: CGFloat(reduceMotion ? 0 : store.shakes)))
        .animation(.linear(duration: 0.4), value: store.shakes)
    }

    private var placeholder: String { store.solved ? "You got it!" : "Your guess" }

    @ViewBuilder
    private var noteLine: some View {
        if let note = store.note {
            Label(note, systemImage: "exclamationmark.circle")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.error)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("drawguess-note")
        } else if store.solved && store.phase == .drawing {
            Label("You got it! Waiting for the others.", systemImage: "checkmark.circle.fill")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.good)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("drawguess-solved")
        } else if room.me?.joined != true {
            Text("You are not playing in this one.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .frame(maxWidth: .infinity)
        }
    }
}

/// The clock for whatever is running — the pick, the drawing, the reveal — as
/// a bar that empties and warms as it goes. Boggle's, measured against the
/// phase's own length.
struct DrawGuessTimeBar: View {
    let room: GameRoom
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        // Ticks, not an animation: a bar that is always animating keeps the app
        // from ever going idle, and UI tests then cannot read the screen.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let left = fraction
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.line)
                    Capsule()
                        .fill(left < 0.17 ? SR.error : left < 0.34 ? SR.accent : SR.good)
                        .frame(width: geo.size.width * left)
                }
            }
            .frame(height: 5)
        }
        .accessibilityHidden(true)
    }

    private var length: Double? {
        switch store.phase {
        case .picking: return store.state?.pickMs
        case .drawing: return room.timeLimitMs
        case .reveal: return store.state?.revealMs
        default: return nil
        }
    }

    private var fraction: CGFloat {
        guard let end = room.phaseEndsAt, let limit = length, limit > 0,
              let now = store.serverNow() else { return 1 }
        return CGFloat(min(1, max(0, (end - now) / limit)))
    }
}

/// Everyone: who is drawing, who has it, the score.
struct DrawGuessSeats: View {
    let room: GameRoom
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(room.playing) { player in
                    let seat = store.state?.seat(player.id)
                    let drawing = seat?.isDrawing == true
                    let solved = seat?.solved == true
                    HStack(spacing: 6) {
                        Image(systemName: drawing ? "pencil.tip" : solved ? "checkmark.circle.fill" : "circle.dashed")
                            .font(SR.Text.label())
                            .foregroundStyle(drawing ? SR.accent : solved ? SR.good : SR.inkGhost)
                        Text(player.id == room.meId ? "You" : player.name)
                            .font(SR.Text.bodyMedium(14))
                            .foregroundStyle(SR.ink)
                            .lineLimit(1)
                        Text("\(player.score)")
                            .font(SR.Text.label())
                            .foregroundStyle(SR.inkMuted)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken(player, drawing: drawing, solved: solved))
                    .accessibilityIdentifier("drawguess-seat-\(player.id)")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("drawguess-seats")
    }

    private func spoken(_ player: GamePlayer, drawing: Bool, solved: Bool) -> String {
        let name = player.id == room.meId ? "You" : player.name
        let doing = drawing ? ", drawing" : solved ? ", got it" : ""
        return "\(name)\(doing), \(player.score) points"
    }
}

// MARK: - The canvas

/// Palette names as ink. `white` is the eraser: the paper's own colour.
enum DrawGuessInk {
    /// The canvas: light paper in both themes, so every ink reads on it.
    static let paper = Color(hex: 0xFBF7EF)

    static func color(_ name: String) -> Color {
        switch name {
        case "black": return SR.ink
        case "red": return SR.error
        case "orange": return SR.accent
        case "yellow": return Color(hex: 0xE3B22B)
        case "green": return SR.good
        case "blue": return Color(hex: 0x2F5FA8)
        case "purple": return Color(hex: 0x6B4A9B)
        case "brown": return Color(hex: 0x7A4A22)
        case "white": return paper
        default: return SR.ink
        }
    }

    static func spoken(_ name: String) -> String { name == "white" ? "eraser" : name }
}

/// The square of paper. It draws the store's strokes (the server's, with the
/// drawer's own over them); for the drawer a finger on it draws.
struct DrawGuessCanvasView: View {
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            Canvas { context, size in
                for stroke in store.strokes { draw(stroke, in: &context, side: size.width) }
            }
            .frame(width: side, height: side)
            .background(DrawGuessInk.paper)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(SR.line, lineWidth: 1))
            .overlay { waiting }
            .contentShape(Rectangle())
            .gesture(drag(side: side), including: store.canDraw ? .all : .subviews)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("drawguess-canvas")
    }

    @ViewBuilder
    private var waiting: some View {
        if store.phase == .picking {
            Text("\(store.drawerName) is choosing…")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
        } else if store.canDraw && store.strokes.isEmpty {
            Text("Draw here")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkGhost)
                .allowsHitTesting(false)
        }
    }

    private var spoken: String {
        let n = store.strokes.count
        if store.canDraw { return "Your drawing, \(GameResults.count(n, "line", "lines")). Drag to draw." }
        return "\(store.drawerName)'s drawing, \(GameResults.count(n, "line", "lines"))"
    }

    private func draw(_ stroke: DrawGuessStroke, in context: inout GraphicsContext, side: CGFloat) {
        guard let first = stroke.points.first else { return }
        let width = CGFloat(stroke.width) * side / CGFloat(DrawGuessGeometry.side)
        let ink = DrawGuessInk.color(stroke.color)
        if stroke.points.count == 1 || stroke.points.allSatisfy({ $0 == first }) {
            let p = DrawGuessGeometry.place(first, size: side)
            let dot = CGRect(x: p.x - width / 2, y: p.y - width / 2, width: width, height: width)
            context.fill(Path(ellipseIn: dot), with: .color(ink))
            return
        }
        var path = Path()
        path.move(to: DrawGuessGeometry.place(first, size: side))
        for point in stroke.points.dropFirst() { path.addLine(to: DrawGuessGeometry.place(point, size: side)) }
        context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func drag(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = DrawGuessGeometry.quantise(value.location, size: side)
                if store.pen.isDown {
                    store.move(to: point)
                } else {
                    store.down(at: point)
                }
            }
            .onEnded { _ in store.up() }
    }
}

/// The drawer's pens: the palette, three widths, undo and clear.
struct DrawGuessTools: View {
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.state?.palette ?? DrawGuessPen.palette, id: \.self) { name in
                        let on = store.pen.color == name
                        Button { store.pickColor(name) } label: {
                            ZStack {
                                Circle().fill(DrawGuessInk.color(name))
                                Circle().strokeBorder(on ? SR.ink : SR.line, lineWidth: on ? 3 : 1)
                                if name == "white" {
                                    Image(systemName: "eraser.fill")
                                        .font(SR.Text.label())
                                        .foregroundStyle(SR.inkMuted)
                                }
                            }
                            .frame(width: SR.tapTarget - 6, height: SR.tapTarget - 6)
                            .frame(minWidth: SR.tapTarget, minHeight: SR.tapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(DrawGuessInk.spoken(name))
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("drawguess-color-\(name)")
                    }
                }
            }
            .scrollClipDisabled()

            HStack(spacing: 10) {
                ForEach(store.state?.widths ?? DrawGuessPen.widths, id: \.self) { width in
                    let on = store.pen.width == width
                    Button { store.pickWidth(width) } label: {
                        Circle()
                            .fill(on ? SR.ink : SR.inkMuted)
                            .frame(width: dot(width), height: dot(width))
                            .frame(minWidth: SR.tapTarget, minHeight: SR.tapTarget)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(on ? SR.accent.opacity(0.18) : Color.clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(widthName(width))
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("drawguess-width-\(width)")
                }
                Spacer(minLength: 8)
                Button { store.undo() } label: {
                    SRButtonLabel(title: "Undo", icon: "arrow.uturn.backward", fill: false)
                }
                .srButton(.regular)
                .accessibilityIdentifier("drawguess-undo")
                Button { store.clear() } label: {
                    SRButtonLabel(title: "Clear", icon: "trash", fill: false)
                }
                .srButton(.regular)
                .accessibilityIdentifier("drawguess-clear")
            }
        }
        .disabled(!store.canDraw)
        .accessibilityIdentifier("drawguess-tools")
    }

    private func dot(_ width: Int) -> CGFloat {
        let widths = store.state?.widths ?? DrawGuessPen.widths
        let rank = widths.firstIndex(of: width) ?? 0
        return 8 + CGFloat(rank) * 7
    }

    private func widthName(_ width: Int) -> String {
        let widths = store.state?.widths ?? DrawGuessPen.widths
        switch widths.firstIndex(of: width) ?? 0 {
        case 0: return "Thin pen"
        case 1: return "Medium pen"
        default: return "Thick pen"
        }
    }
}

/// The drawer's three words, in place of the canvas while they choose.
struct DrawGuessPicker: View {
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Only you can see these")
            ForEach(Array((store.turn?.choices ?? []).enumerated()), id: \.offset) { index, word in
                Button { store.pick(index) } label: {
                    HStack {
                        Text(word.uppercased())
                            .font(SR.Text.display(24))
                            .foregroundStyle(SR.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Spacer(minLength: 8)
                        Image(systemName: "pencil.tip")
                            .font(SR.Text.title())
                            .foregroundStyle(SR.accent)
                    }
                    .padding(SR.cardPadding)
                    .frame(minHeight: SR.tapTarget + 12)
                    .srGlassCard(.paper, interactive: true)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.busy)
                .accessibilityLabel("Draw \(word)")
                .accessibilityIdentifier("drawguess-choice-\(index)")
            }
            Text("Not picked in time? The first one is yours.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawguess-picker")
    }
}

/// Between drawings: who got it, and what it scored.
struct DrawGuessRevealCard: View {
    let room: GameRoom
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        let turn = store.turn
        VStack(alignment: .leading, spacing: 8) {
            if let solvers = turn?.solvers, !solvers.isEmpty {
                ForEach(solvers) { solver in
                    row(solver.id == room.meId ? "You" : room.name(of: solver.id), points: solver.points,
                        icon: "checkmark.circle.fill", tone: SR.good)
                }
            } else {
                Text(turn?.ended == "left" ? "\(store.drawerName) left before the end." : "Nobody got it this time.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            if let points = turn?.drawerPoints {
                row("\(store.drawerName) (drawing)", points: points, icon: "pencil.tip", tone: SR.accent)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("drawguess-reveal")
    }

    private func row(_ name: String, points: Int, icon: String, tone: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(SR.Text.label())
                .foregroundStyle(tone)
            Text(name)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
            Spacer(minLength: 8)
            Text("+\(points)")
                .font(SR.Text.figure(18))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
        }
    }
}

/// The guesses so far, newest first. A right answer reads "got it!" and never
/// shows what was typed; a "close!" is only ever mine.
struct DrawGuessFeed: View {
    let room: GameRoom
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        let feed = (store.turn?.feed ?? []).reversed()
        if !feed.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Guesses", trailing: "\(feed.count)")
                VStack(spacing: 0) {
                    ForEach(Array(feed.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().overlay(SR.divider) }
                        row(entry)
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 4)
                .srGlassCard(.paper)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("drawguess-feed")
        }
    }

    private func row(_ entry: DrawGuessFeedEntry) -> some View {
        let who = entry.playerId == room.meId ? "You" : entry.name
        return HStack(spacing: 8) {
            switch entry.kind {
            case "solved":
                Image(systemName: "checkmark.circle.fill").foregroundStyle(SR.good)
                Text("\(who) got it!")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.good)
            case "close":
                Image(systemName: "flame.fill").foregroundStyle(SR.accent)
                Text("\(entry.text ?? "") — close!")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.accent)
            default:
                Text(who)
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.inkSecondary)
                Text(entry.text ?? "")
                    .font(SR.Text.body(15))
                    .foregroundStyle(SR.ink)
            }
            Spacer(minLength: 0)
        }
        .font(SR.Text.label())
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("drawguess-feed-\(entry.n)")
    }
}

// MARK: - Finished

struct DrawGuessFinished: View {
    let room: GameRoom
    @ObservedObject var store: DrawGuessStore
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Draw & Guess · \(DrawGuessSettings.about(room)) · final",
                             title: GameResults.title(room, solo: "You scored \(room.me?.score ?? 0)", none: "Nobody scored"),
                             strap: GameResults.strap(room))

                GameStandingsCard(
                    room: room,
                    label: "Standings",
                    id: "drawguess-standings",
                    detail: { _ in "" },
                    figure: { (text: "\($0.score)", spoken: "\($0.score) points") }
                )

                if !store.strokes.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "The last drawing", trailing: store.turn?.word)
                        DrawGuessCanvasView(store: store)
                    }
                }

                GameFinishedButtons(room: room, store: store, prefix: "drawguess", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("drawguess-finished")
        .onAppear { if room.winnerIds.contains(room.meId) { SRHaptic.ok() } }
    }
}
