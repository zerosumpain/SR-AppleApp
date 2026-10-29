import SwiftUI
import UIKit

/// One Draw & Guess room, from lobby to the final standings.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the host's options and how to play as the lobby's panel; Start waits
/// for a second player. Then, turn by turn: the drawer picks one of three
/// words, draws it on a sheet of sketchbook paper taped to the screen (their
/// own line appears under the finger at once and streams to the others as it
/// goes), while everyone else watches it appear, reads the letter tiles and
/// types guesses. The word is revealed between drawings, and the finish shows
/// my score, my place, my best on this phone and the last drawing framed.
///
/// The room runs on the server's clock for everyone, so there is no pause:
/// the "?" in the bar opens how to play over the game instead.
struct DrawGuessScreen: View {
    let roomId: String
    @StateObject private var store: DrawGuessStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingHowTo = false

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
            .toolbar {
                if showsHelp {
                    ToolbarItem(placement: .topBarTrailing) {
                        TableHelpButton(id: "drawguess-help") { showingHowTo = true }
                    }
                }
            }
            .sheet(isPresented: $showingHowTo) {
                TableHowToSheet(game: "Draw & Guess", steps: DrawGuessHowTo.steps,
                                note: TableHowToNote.live, id: "drawguess-how-to")
            }
    }

    private var immersive: Bool {
        guard !store.ended, store.room != nil else { return false }
        return store.phase == .countdown
    }

    private var showsHelp: Bool {
        guard !store.ended, store.room != nil else { return false }
        switch store.phase {
        case .picking, .drawing, .reveal: return true
        default: return false
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "drawguess-ended", done: { dismiss() })
        } else if let room = store.room {
            switch store.phase {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "drawguess", done: { dismiss() },
                          panel: AnyView(DrawGuessLobbyPanel(room: room)),
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
            DrawGuessLoading()
        }
    }
}

/// While the room is first read: the sketchbook, still, and one line. No
/// spinner — a spinner never lets the app go idle.
struct DrawGuessLoading: View {
    var body: some View {
        VStack(spacing: 14) {
            DrawGuessEaselArt(side: 96)
            Text("Opening the sketchbook…")
                .font(SR.Text.bodyMedium(16))
                .foregroundStyle(SR.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srGround(.warm)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("drawguess-loading")
    }
}

// MARK: - How to play

enum DrawGuessHowTo {
    static let steps: [TableHowToStep] = [
        TableHowToStep(icon: "pencil.tip", title: "Take turns to draw",
                       text: "When it's your go, pick one of three words and draw it. No letters or numbers!"),
        TableHowToStep(icon: "character.cursor.ibeam", title: "Everyone else guesses",
                       text: "Type guesses as the drawing appears. The tiles show how many letters there are."),
        TableHowToStep(icon: "bolt.fill", title: "Sooner scores more",
                       text: "The quicker you get it, the more you score. The drawer scores for every right guess."),
        TableHowToStep(icon: "flame.fill", title: "Close counts — a bit",
                       text: "A guess that is nearly right says \"close!\", and only you see it."),
    ]
}

// MARK: - Lobby

/// The lobby's panel: the host's options, and how to play.
struct DrawGuessLobbyPanel: View {
    let room: GameRoom

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            DrawGuessOptionsCard(room: room)
            VStack(alignment: .leading, spacing: 14) {
                SRSectionLabel(text: "How to play")
                TableHowToList(steps: DrawGuessHowTo.steps, tint: DrawGuessInk.color("blue"))
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("drawguess-howto")
        }
    }
}

/// The host's options, in the lobby — and why Start waits.
struct DrawGuessOptionsCard: View {
    let room: GameRoom

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            DrawGuessEaselArt(side: 72)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(DrawGuessSettings.about(room).uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text("Everyone draws \(room.drawGuess?.turnsEach == 2 ? "twice" : "once")")
                    .font(SR.Text.title(19))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(room.playing.count < 2
                     ? "Needs two players at least — ask someone in."
                     : "Guess sooner to score more. The drawer scores for every right guess.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(room.playing.count < 2 ? SR.error : SR.inkMuted)
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

/// The game's picture: a sheet of paper on an easel with a scribble and a
/// pencil across it. Shapes only, so it is the same in both themes.
struct DrawGuessEaselArt: View {
    var side: CGFloat = 72

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let wood = Color(hex: 0x9A6A3A)
            // The legs.
            var legs = Path()
            legs.move(to: CGPoint(x: s * 0.30, y: s * 0.30))
            legs.addLine(to: CGPoint(x: s * 0.14, y: s * 0.98))
            legs.move(to: CGPoint(x: s * 0.70, y: s * 0.30))
            legs.addLine(to: CGPoint(x: s * 0.86, y: s * 0.98))
            legs.move(to: CGPoint(x: s * 0.50, y: s * 0.30))
            legs.addLine(to: CGPoint(x: s * 0.50, y: s * 0.98))
            context.stroke(legs, with: .color(wood), style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round))
            // The sheet.
            let sheet = CGRect(x: s * 0.12, y: s * 0.06, width: s * 0.76, height: s * 0.62)
            context.fill(Path(roundedRect: sheet, cornerRadius: s * 0.05), with: .color(DrawGuessInk.paper))
            context.stroke(Path(roundedRect: sheet, cornerRadius: s * 0.05), with: .color(Color(hex: 0x1F1B16, alpha: 0.18)),
                           lineWidth: max(1, s * 0.012))
            // A sun and a hill, scribbled.
            let sun = CGRect(x: s * 0.58, y: s * 0.14, width: s * 0.16, height: s * 0.16)
            context.fill(Path(ellipseIn: sun), with: .color(DrawGuessInk.color("yellow")))
            var hill = Path()
            hill.move(to: CGPoint(x: s * 0.18, y: s * 0.58))
            hill.addQuadCurve(to: CGPoint(x: s * 0.82, y: s * 0.56), control: CGPoint(x: s * 0.45, y: s * 0.22))
            context.stroke(hill, with: .color(DrawGuessInk.color("green")),
                           style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round, lineJoin: .round))
            // The ledge.
            let ledge = CGRect(x: s * 0.06, y: s * 0.68, width: s * 0.88, height: s * 0.07)
            context.fill(Path(roundedRect: ledge, cornerRadius: s * 0.03), with: .color(wood))
            // A pencil resting on it.
            var pencil = Path()
            pencil.move(to: CGPoint(x: s * 0.20, y: s * 0.66))
            pencil.addLine(to: CGPoint(x: s * 0.62, y: s * 0.66))
            context.stroke(pencil, with: .color(DrawGuessInk.color("red")), style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round))
        }
        .frame(width: side, height: side)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DrawGuessInk.color("blue").opacity(0.14)))
    }
}

// MARK: - A turn

struct DrawGuessPlaying: View {
    let room: GameRoom
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DrawGuessHeader(room: room, store: store)
                DrawGuessTimeBar(room: room, store: store)
                DrawGuessSeats(room: room, store: store)
                DrawGuessWordRow(store: store)
                stage
                actionArea
                DrawGuessNoteLine(room: room, store: store)
                DrawGuessFeed(room: room, store: store)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
            .srAnimation(.snappy(duration: 0.3), value: store.phase)
            .srAnimation(.snappy(duration: 0.3), value: store.solved)
        }
        // A finger on the canvas draws; it must not scroll the page.
        .scrollDisabled(store.pen.isDown)
        .scrollDismissesKeyboard(.interactively)
        .srGround(.warm)
        .accessibilityIdentifier("drawguess-playing")
        .onChange(of: store.shakes) { _, _ in
            if let note = store.note { UIAccessibility.post(notification: .announcement, argument: note) }
        }
        .onChange(of: store.phase) { _, phase in
            if phase == .reveal, let word = store.turn?.word {
                UIAccessibility.post(notification: .announcement, argument: "It was \(word)")
            }
        }
    }

    /// The paper, or the drawer's three words in its place while they choose.
    @ViewBuilder
    private var stage: some View {
        if store.phase == .picking && store.isDrawer {
            DrawGuessPicker(store: store)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else {
            DrawGuessCanvasView(store: store)
        }
    }

    /// Under the paper: the drawer's pens, a guesser's box (or their win), or
    /// who got it at the reveal.
    @ViewBuilder
    private var actionArea: some View {
        if store.phase == .drawing && store.isDrawer {
            DrawGuessTools(store: store)
        } else if store.phase == .drawing && store.solved {
            DrawGuessSolvedCard(room: room, store: store)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else if store.phase == .drawing {
            DrawGuessGuessBox(store: store)
        } else if store.phase == .reveal {
            DrawGuessRevealCard(room: room, store: store)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Turn N of M, what is happening in a few words, and the clock.
struct DrawGuessHeader: View {
    let room: GameRoom
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DrawGuessRoleBadge(store: store)
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker)
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
        case .drawing:
            if store.isDrawer { return "You're drawing" }
            return store.solved ? "You got it!" : "\(store.drawerName) is drawing"
        case .reveal: return "It was…"
        default: return "Draw & Guess"
        }
    }
}

/// A round badge by the title: a pencil when I draw, a speech bubble when I
/// guess, a tick once I have it, an eye at the reveal. Tells me at a glance
/// what my job is right now.
struct DrawGuessRoleBadge: View {
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        Image(systemName: icon)
            .font(SR.Text.title(20))
            .foregroundStyle(Color.white)
            .frame(width: 46, height: 46)
            .background(Circle().fill(tone))
            .accessibilityHidden(true)
    }

    private var icon: String {
        switch store.phase {
        case .picking: return store.isDrawer ? "hand.point.up.left.fill" : "hourglass"
        case .drawing:
            if store.isDrawer { return "pencil.tip" }
            return store.solved ? "checkmark" : "text.bubble.fill"
        case .reveal: return "eye.fill"
        default: return "scribble.variable"
        }
    }

    private var tone: Color {
        if store.phase == .drawing && store.solved { return DrawGuessInk.color("green") }
        if store.isDrawer { return DrawGuessInk.color("orange") }
        return DrawGuessInk.color("blue")
    }
}

/// The clock for whatever is running — the pick, the drawing, the reveal — as
/// a bar that empties and warms as it goes. A tap at ten seconds and at five
/// for whoever still has something to do.
struct DrawGuessTimeBar: View {
    let room: GameRoom
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        // Ticks, not an animation: a bar that is always animating keeps the app
        // from ever going idle, and UI tests then cannot read the screen.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            DrawGuessClockTrack(fraction: fraction, seconds: seconds, nudges: nudges)
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

    private var fraction: Double {
        guard let limit = length else { return 1 }
        return TableClock.fraction(endsAt: room.phaseEndsAt, turnMs: limit, now: store.serverNow())
    }

    private var seconds: Int? { TableClock.secondsLeft(endsAt: room.phaseEndsAt, now: store.serverNow()) }

    /// Only someone with a move to make is nudged.
    private var nudges: Bool {
        switch store.phase {
        case .picking: return store.isDrawer
        case .drawing: return store.canDraw || store.canGuess
        default: return false
        }
    }
}

/// The bar itself, drawn from one tick's numbers.
struct DrawGuessClockTrack: View {
    let fraction: Double
    let seconds: Int?
    let nudges: Bool

    var body: some View {
        let urgency = TableClock.urgency(fraction: fraction, seconds: seconds)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SR.line)
                Capsule()
                    .fill(colour(urgency))
                    .frame(width: max(0, geo.size.width * CGFloat(fraction)))
            }
        }
        .frame(height: 8)
        .onChange(of: seconds) { old, new in
            if nudges, TableClock.nudge(from: old, to: new) { SRHaptic.tap() }
        }
    }

    private func colour(_ urgency: TableClock.Urgency) -> Color {
        switch urgency {
        case .calm: return SR.good
        case .hurry: return SR.warn
        case .last: return SR.error
        }
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
                    seat(player)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("drawguess-seats")
    }

    private func seat(_ player: GamePlayer) -> some View {
        let state = store.state?.seat(player.id)
        let drawing = state?.isDrawing == true
        let solved = state?.solved == true
        let me = player.id == room.meId
        let tone: Color = drawing ? DrawGuessInk.color("orange") : solved ? DrawGuessInk.color("green") : SR.accentInk
        return HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                GameInitial(name: player.name, filled: drawing || solved || me, tone: tone, side: 30)
                if drawing || solved {
                    Image(systemName: drawing ? "pencil" : "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(tone))
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                        .offset(x: 4, y: 4)
                }
            }
            Text(me ? "You" : player.name)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
            Text("\(player.score)")
                .font(SR.Text.figure(17))
                .foregroundStyle(SR.inkSecondary)
                .monospacedDigit()
                .srNumeric(Double(player.score))
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background {
            if drawing || solved {
                Capsule().fill(tone.opacity(0.14))
            }
        }
        .srGlass(.paper, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(player, drawing: drawing, solved: solved))
        .accessibilityIdentifier("drawguess-seat-\(player.id)")
    }

    private func spoken(_ player: GamePlayer, drawing: Bool, solved: Bool) -> String {
        let name = player.id == room.meId ? "You" : player.name
        let doing = drawing ? ", drawing" : solved ? ", got it" : ""
        return "\(name)\(doing), \(player.score) points"
    }
}

// MARK: - The word

/// The drawer's word, a guesser's letter tiles, or the word at the reveal.
struct DrawGuessWordRow: View {
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityIdentifier("drawguess-word")
    }

    @ViewBuilder
    private var content: some View {
        let turn = store.turn
        if let word = turn?.word, store.phase == .drawing, store.isDrawer {
            mine(word)
        } else if let word = turn?.word, store.phase == .reveal || store.phase == .drawing {
            // At the reveal, or as soon as I have guessed it: the server sends a
            // solver the word, and they should see it filled in, not the blanks.
            DrawGuessTiles(text: word, revealed: true)
                .tablePopIn()
        } else if let hint = turn?.hint, store.phase == .drawing {
            VStack(spacing: 6) {
                DrawGuessTiles(text: hint, revealed: false)
                Text(DrawGuessText.letters(hint).uppercased())
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(SR.inkMuted)
            }
        } else {
            Color.clear.frame(height: 8)
        }
    }

    /// My word, on a ribbon only I can see.
    private func mine(_ word: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.slash.fill")
                .font(SR.Text.title())
                .foregroundStyle(Color.white.opacity(0.85))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("YOUR WORD · KEEP IT SECRET")
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(word.uppercased())
                    .font(SR.Text.hero(30))
                    .tracking(2)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 2, style: .continuous)
                .fill(LinearGradient(colors: [DrawGuessInk.color("orange"), DrawGuessInk.color("red")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }

    private var spoken: String {
        let turn = store.turn
        if let word = turn?.word, store.phase != .picking {
            return store.isDrawer && store.phase == .drawing ? "Your word, \(word)" : "The word, \(word)"
        }
        if let hint = turn?.hint, store.phase == .drawing { return "The word: \(DrawGuessText.letters(hint))" }
        return ""
    }
}

/// One square per letter. A blank is an empty tile with a line under it; a
/// letter the server has given away sits in its tile. A gap between words is
/// half a tile wide. The tiles shrink to fit the width, never wrap.
struct DrawGuessTiles: View {
    let text: String
    /// The real word, at the reveal: every tile filled and lit.
    let revealed: Bool

    var body: some View {
        GeometryReader { geo in
            let slots = DrawGuessTileSlot.slots(text)
            let side = DrawGuessTileSlot.side(slots, width: geo.size.width)
            HStack(spacing: DrawGuessTileSlot.spacing) {
                ForEach(slots) { slot in
                    tile(slot, side: side)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 52)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tile(_ slot: DrawGuessTileSlot, side: CGFloat) -> some View {
        if slot.gap {
            Color.clear.frame(width: side * 0.5, height: side)
        } else {
            let height = min(52, side * 1.2)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: max(4, side * 0.18), style: .continuous)
                    .fill(revealed ? DrawGuessInk.color("green") : SR.surface)
                RoundedRectangle(cornerRadius: max(4, side * 0.18), style: .continuous)
                    .strokeBorder(revealed ? Color.clear : SR.line, lineWidth: 1)
                if let letter = slot.letter {
                    Text(letter.uppercased())
                        .font(.system(size: max(10, side * 0.58), weight: .heavy, design: .rounded))
                        .foregroundStyle(revealed ? Color.white : SR.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Capsule()
                        .fill(SR.inkMuted)
                        .frame(width: side * 0.5, height: 3)
                        .padding(.bottom, height * 0.18)
                }
            }
            .frame(width: side, height: height)
        }
    }
}

/// A tile in the row: a letter, a blank, or the gap between two words.
struct DrawGuessTileSlot: Identifiable {
    let id: Int
    let letter: String?
    let gap: Bool

    static let spacing: CGFloat = 4

    /// "b___ __t" → b, blank, blank, blank, gap, blank, blank, t.
    static func slots(_ text: String) -> [DrawGuessTileSlot] {
        var out: [DrawGuessTileSlot] = []
        for (index, ch) in text.enumerated() {
            if ch == " " {
                out.append(DrawGuessTileSlot(id: index, letter: nil, gap: true))
            } else if ch == "_" {
                out.append(DrawGuessTileSlot(id: index, letter: nil, gap: false))
            } else {
                out.append(DrawGuessTileSlot(id: index, letter: String(ch), gap: false))
            }
        }
        return out
    }

    /// The tile's width so the whole row fits `width`, up to 40pt.
    static func side(_ slots: [DrawGuessTileSlot], width: CGFloat) -> CGFloat {
        guard !slots.isEmpty else { return 40 }
        let units = slots.reduce(CGFloat(0)) { $0 + ($1.gap ? 0.5 : 1) }
        let gaps = spacing * CGFloat(max(0, slots.count - 1))
        let fit = (width - gaps) / max(1, units)
        return max(8, min(40, fit))
    }
}

// MARK: - The canvas

/// Palette names as ink. `white` is the eraser: the paper's own colour.
///
/// Fixed colours, not theme tokens: the paper is light in both themes, and a
/// line must be the same colour on the drawer's phone as on everyone else's
/// (a token's dark-mode "black" is near white, and vanished on the paper).
enum DrawGuessInk {
    /// The canvas: light paper in both themes, so every ink reads on it.
    static let paper = Color(hex: 0xFBF7EF)
    /// Words written on the paper itself.
    static let onPaper = Color(hex: 0x1F1B16)
    static let onPaperMuted = Color(hex: 0x6E665A)
    /// The paper's faint dot grid.
    static let grid = Color(hex: 0x2F5FA8, alpha: 0.10)
    /// Masking tape at the corners.
    static let tape = Color(hex: 0xE9D9A6, alpha: 0.85)

    static func color(_ name: String) -> Color {
        switch name {
        case "black": return Color(hex: 0x1F1B16)
        case "red": return Color(hex: 0xC8372D)
        case "orange": return Color(hex: 0xE07A1F)
        case "yellow": return Color(hex: 0xE3B22B)
        case "green": return Color(hex: 0x2E8540)
        case "blue": return Color(hex: 0x2F5FA8)
        case "purple": return Color(hex: 0x6B4A9B)
        case "brown": return Color(hex: 0x7A4A22)
        case "white": return paper
        default: return Color(hex: 0x1F1B16)
        }
    }

    static func spoken(_ name: String) -> String { name == "white" ? "eraser" : name }
}

/// Drawing on the paper, shared by Draw & Guess and Odd Artist Out.
enum DrawGuessArt {
    /// A faint dot grid, as one path: a sketchbook page, not a blank screen.
    static func paperGrid(in context: inout GraphicsContext, size: CGSize) {
        let step = size.width / 12
        guard step > 4 else { return }
        let r: CGFloat = max(0.8, size.width / 400)
        var dots = Path()
        var y = step
        while y < size.height - 1 {
            var x = step
            while x < size.width - 1 {
                dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                x += step
            }
            y += step
        }
        context.fill(dots, with: .color(DrawGuessInk.grid))
    }

    /// One stroke in `ink`: a round dot for a tap, a round-capped line for the rest.
    static func draw(_ stroke: DrawGuessStroke, ink: Color, in context: inout GraphicsContext, side: CGFloat) {
        guard let first = stroke.points.first else { return }
        let width = CGFloat(stroke.width) * side / CGFloat(DrawGuessGeometry.side)
        if stroke.points.count == 1 || stroke.points.allSatisfy({ $0 == first }) {
            let p = DrawGuessGeometry.place(first, size: side)
            let dot = CGRect(x: p.x - width / 2, y: p.y - width / 2, width: width, height: width)
            context.fill(Path(ellipseIn: dot), with: .color(ink))
            return
        }
        context.stroke(path(stroke, side: side), with: .color(ink),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// A soft halo under a stroke: the newest line, so watchers see what changed.
    static func halo(_ stroke: DrawGuessStroke, ink: Color, in context: inout GraphicsContext, side: CGFloat) {
        guard stroke.points.count > 1 else { return }
        let width = CGFloat(stroke.width) * side / CGFloat(DrawGuessGeometry.side)
        context.stroke(path(stroke, side: side), with: .color(ink.opacity(0.22)),
                       style: StrokeStyle(lineWidth: width + max(8, side * 0.02), lineCap: .round, lineJoin: .round))
    }

    static func path(_ stroke: DrawGuessStroke, side: CGFloat) -> Path {
        var path = Path()
        guard let first = stroke.points.first else { return path }
        path.move(to: DrawGuessGeometry.place(first, size: side))
        for point in stroke.points.dropFirst() { path.addLine(to: DrawGuessGeometry.place(point, size: side)) }
        return path
    }
}

/// Two strips of masking tape holding the paper at its top corners.
struct DrawGuessTape: View {
    var body: some View {
        GeometryReader { geo in
            let w = max(44, geo.size.width * 0.16)
            ZStack {
                Rectangle()
                    .fill(DrawGuessInk.tape)
                    .frame(width: w, height: 16)
                    .rotationEffect(.degrees(-38))
                    .position(x: w * 0.32, y: 10)
                Rectangle()
                    .fill(DrawGuessInk.tape)
                    .frame(width: w, height: 16)
                    .rotationEffect(.degrees(38))
                    .position(x: geo.size.width - w * 0.32, y: 10)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The square of paper. It draws the store's strokes (the server's, with the
/// drawer's own over them); for the drawer a finger on it draws.
struct DrawGuessCanvasView: View {
    @ObservedObject var store: DrawGuessStore
    /// The finished page's copy: a picture to look at, never to draw on.
    var framed = false

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let strokes = store.strokes
            Canvas { context, size in
                DrawGuessArt.paperGrid(in: &context, size: size)
                for stroke in strokes {
                    DrawGuessArt.draw(stroke, ink: DrawGuessInk.color(stroke.color), in: &context, side: size.width)
                }
            }
            .frame(width: side, height: side)
            .background(DrawGuessInk.paper)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColour, lineWidth: borderWidth))
            .overlay { waiting(strokes.isEmpty) }
            .overlay(alignment: .topLeading) { artistTag }
            .overlay { DrawGuessTape() }
            .contentShape(Rectangle())
            .gesture(drag(side: side), including: store.canDraw && !framed ? .all : .subviews)
        }
        .aspectRatio(1, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DrawGuessInk.paper)
                .shadow(color: Color.black.opacity(0.14), radius: 12, x: 0, y: 6)
        )
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("drawguess-canvas")
    }

    /// The drawer's paper is rimmed in the pen's colour, so the pen in hand is
    /// seen without looking down at the palette.
    private var borderColour: Color {
        guard store.canDraw, !framed else { return SR.line }
        let name: String = store.pen.color == "white" ? "black" : store.pen.color
        return DrawGuessInk.color(name)
    }

    private var borderWidth: CGFloat { store.canDraw && !framed ? 3 : 1 }

    /// Words on the paper itself: always the paper's dark ink, in both themes.
    @ViewBuilder
    private func waiting(_ empty: Bool) -> some View {
        if framed {
            EmptyView()
        } else if store.phase == .picking {
            VStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .font(SR.Text.hero(40))
                    .foregroundStyle(DrawGuessInk.color("orange"))
                Text("\(store.drawerName) is choosing a word…")
                    .font(SR.Text.title())
                    .foregroundStyle(DrawGuessInk.onPaper)
                    .multilineTextAlignment(.center)
                Text("Get ready to guess!")
                    .font(SR.Text.secondary())
                    .foregroundStyle(DrawGuessInk.onPaperMuted)
            }
            .padding(20)
            .allowsHitTesting(false)
        } else if store.canDraw && empty {
            VStack(spacing: 8) {
                Image(systemName: "hand.draw.fill")
                    .font(SR.Text.hero(40))
                    .foregroundStyle(DrawGuessInk.onPaperMuted.opacity(0.7))
                Text("Draw here with your finger")
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(DrawGuessInk.onPaperMuted)
            }
            .allowsHitTesting(false)
        }
    }

    /// Whose drawing it is, pinned to the paper for the guessers.
    @ViewBuilder
    private var artistTag: some View {
        if !framed, !store.isDrawer, store.phase == .drawing {
            Label(store.drawerName, systemImage: "pencil.tip")
                .font(SR.Text.label(13))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(DrawGuessInk.color("orange")))
                .padding(.top, 24)
                .padding(.leading, 12)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var spoken: String {
        let n = store.strokes.count
        if store.canDraw && !framed { return "Your drawing, \(GameResults.count(n, "line", "lines")). Drag to draw." }
        return "\(store.drawerName)'s drawing, \(GameResults.count(n, "line", "lines"))"
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

// MARK: - The drawer's pens

/// The drawer's pens: the palette, three widths, undo and clear — every one a
/// 56pt target. Clear asks first: one stray tap used to wipe a whole drawing.
struct DrawGuessTools: View {
    @ObservedObject var store: DrawGuessStore
    @State private var confirmingClear = false

    private let columns = [GridItem(.adaptive(minimum: 52, maximum: 64), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(palette, id: \.self) { name in
                    swatch(name)
                }
            }
            HStack(spacing: 6) {
                ForEach(widths, id: \.self) { width in
                    widthButton(width)
                }
                Spacer(minLength: 0)
                toolButton(title: "Undo", icon: "arrow.uturn.backward", id: "drawguess-undo") { store.undo() }
                toolButton(title: "Clear", icon: "trash", id: "drawguess-clear") {
                    SRHaptic.select()
                    confirmingClear = true
                }
            }
        }
        .padding(12)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 6)
        .disabled(!store.canDraw)
        .accessibilityIdentifier("drawguess-tools")
        .confirmationDialog("Clear the whole drawing?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear it", role: .destructive) { store.clear() }
            Button("Keep drawing", role: .cancel) {}
        }
    }

    private var palette: [String] {
        let list = store.state?.palette ?? []
        return list.isEmpty ? DrawGuessPen.palette : list
    }

    private var widths: [Int] {
        let list = store.state?.widths ?? []
        return list.isEmpty ? DrawGuessPen.widths : list
    }

    private func swatch(_ name: String) -> some View {
        let on = store.pen.color == name
        return Button { store.pickColor(name) } label: {
            ZStack {
                Circle().fill(DrawGuessInk.color(name))
                // A ring that reads on both grounds: the black pen must not
                // vanish on a dark phone.
                Circle().strokeBorder(SR.inkGhost, lineWidth: 1.5)
                if name == "white" {
                    Image(systemName: "eraser.fill")
                        .font(SR.Text.title())
                        .foregroundStyle(DrawGuessInk.onPaperMuted)
                }
                if on {
                    Circle()
                        .strokeBorder(SR.ink, lineWidth: 3)
                        .padding(-5)
                }
            }
            .frame(width: 42, height: 42)
            .scaleEffect(on ? 1.08 : 1)
            .frame(minWidth: 56, minHeight: 56)
            .contentShape(Rectangle())
            .srAnimation(.snappy(duration: 0.2), value: on)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DrawGuessInk.spoken(name))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("drawguess-color-\(name)")
    }

    private func widthButton(_ width: Int) -> some View {
        let on = store.pen.width == width
        let ink = store.pen.color == "white" ? DrawGuessInk.onPaperMuted : DrawGuessInk.color(store.pen.color)
        return Button { store.pickWidth(width) } label: {
            Circle()
                .fill(ink)
                .frame(width: dot(width), height: dot(width))
                .frame(width: 56, height: 56)
                // The paper itself behind the dot, so every ink (black too) shows
                // in both themes, at the width it will draw.
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DrawGuessInk.paper)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(on ? SR.accent : SR.line, lineWidth: on ? 3 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(widthName(width))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("drawguess-width-\(width)")
    }

    private func toolButton(title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(SR.Text.title(18))
                Text(title.uppercased())
                    .font(SR.Text.label())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(SR.ink)
            .frame(width: 56, height: 56)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(SR.surface.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(SR.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    private func dot(_ width: Int) -> CGFloat {
        let rank = widths.firstIndex(of: width) ?? 0
        return 8 + CGFloat(rank) * 9
    }

    private func widthName(_ width: Int) -> String {
        switch widths.firstIndex(of: width) ?? 0 {
        case 0: return "Thin pen"
        case 1: return "Medium pen"
        default: return "Thick pen"
        }
    }
}

// MARK: - Guessing

/// The guess box: a big field and a big send button. It shakes on a refusal.
struct DrawGuessGuessBox: View {
    @ObservedObject var store: DrawGuessStore
    @FocusState private var typing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $store.guessText)
                .font(SR.Text.body(18))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .focused($typing)
                .onSubmit {
                    store.sendGuess()
                    typing = true
                }
                .disabled(!store.canGuess)
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SR.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(typing ? SR.accent : SR.line, lineWidth: typing ? 2 : 1)
                )
                .accessibilityIdentifier("drawguess-guess-field")
            Button { store.sendGuess() } label: {
                Image(systemName: "paperplane.fill")
                    .font(SR.Text.title(20))
                    .foregroundStyle(Color.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(store.canSendGuess ? SR.accent : SR.inkGhost))
                    .contentShape(Circle())
            }
            .buttonStyle(SRPressStyle())
            .disabled(!store.canSendGuess)
            .accessibilityLabel("Guess")
            .accessibilityIdentifier("drawguess-guess-send")
        }
        .modifier(WordleShake(animatableData: CGFloat(reduceMotion ? 0 : store.shakes)))
        .animation(.linear(duration: 0.4), value: store.shakes)
    }

    private var placeholder: String { store.solved ? "You got it!" : "Type your guess" }
}

/// In place of the guess box once I have it: what it scored, and the wait.
struct DrawGuessSolvedCard: View {
    let room: GameRoom
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(SR.Text.hero(26))
                .foregroundStyle(Color.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(DrawGuessInk.color("green")))
                .tablePopIn()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("You got it!")
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                Text("Waiting for the others to guess.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
            }
            Spacer(minLength: 8)
            if let points = mine {
                Text("+\(points)")
                    .font(SR.Text.figure(30))
                    .foregroundStyle(SR.good)
                    .monospacedDigit()
                    .tablePopIn(delay: 0.15)
            }
        }
        .padding(SR.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .fill(DrawGuessInk.color("green").opacity(0.14))
        )
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("drawguess-solved")
    }

    private var mine: Int? { store.turn?.solvers.first { $0.id == room.meId }?.points }
}

/// A refusal under the box for a moment, or why I am only watching.
struct DrawGuessNoteLine: View {
    let room: GameRoom
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        if let note = store.note {
            Label(note, systemImage: "exclamationmark.circle.fill")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.error)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("drawguess-note")
        } else if room.me?.joined != true {
            Label("You are not playing in this one.", systemImage: "eye")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Picking

/// The drawer's three words, in place of the canvas while they choose.
struct DrawGuessPicker: View {
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            HStack(spacing: 8) {
                Image(systemName: "eye.slash.fill")
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityHidden(true)
                SRSectionLabel(text: "Only you can see these")
            }
            ForEach(Array((store.turn?.choices ?? []).enumerated()), id: \.offset) { index, word in
                choice(index, word)
            }
            Label("Not picked in time? The first one is yours.", systemImage: "clock")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawguess-picker")
    }

    private func choice(_ index: Int, _ word: String) -> some View {
        let tint = DrawGuessInk.color(index == 0 ? "blue" : index == 1 ? "purple" : "orange")
        return Button { store.pick(index) } label: {
            HStack(spacing: 14) {
                Text("\(index + 1)")
                    .font(SR.Text.figure(22))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(tint))
                Text(word.uppercased())
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 8)
                Image(systemName: "pencil.tip.crop.circle.fill")
                    .font(SR.Text.hero(30))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, SR.cardPadding)
            .frame(minHeight: 76)
            .srGlassCard(.paper, interactive: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .disabled(store.busy)
        .tablePopIn(delay: 0.06 * Double(index))
        .accessibilityLabel("Draw \(word)")
        .accessibilityIdentifier("drawguess-choice-\(index)")
    }
}

// MARK: - The reveal

/// Between drawings: who got it, and what it scored.
struct DrawGuessRevealCard: View {
    let room: GameRoom
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        let turn = store.turn
        VStack(alignment: .leading, spacing: 10) {
            if let solvers = turn?.solvers, !solvers.isEmpty {
                SRSectionLabel(text: "Got it", trailing: "\(solvers.count) of \(max(1, room.playing.count - 1))")
                ForEach(Array(solvers.enumerated()), id: \.element.id) { index, solver in
                    row(solver.id == room.meId ? "You" : room.name(of: solver.id), points: solver.points,
                        place: index + 1, tone: DrawGuessInk.color("green"))
                        .tablePopIn(delay: 0.08 * Double(index))
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: turn?.ended == "left" ? "door.left.hand.open" : "questionmark.bubble.fill")
                        .font(SR.Text.title(20))
                        .foregroundStyle(SR.inkMuted)
                        .accessibilityHidden(true)
                    Text(turn?.ended == "left" ? "\(store.drawerName) left before the end." : "Nobody got it this time.")
                        .font(SR.Text.bodyMedium(16))
                        .foregroundStyle(SR.inkSecondary)
                }
            }
            if let points = turn?.drawerPoints {
                Divider().overlay(SR.divider)
                row("\(store.drawerName) (drawing)", points: points, place: nil, tone: DrawGuessInk.color("orange"))
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("drawguess-reveal")
    }

    private func row(_ name: String, points: Int, place: Int?, tone: Color) -> some View {
        HStack(spacing: 10) {
            if let place {
                GameMedal(place: place, side: 30)
            } else {
                Image(systemName: "pencil.tip")
                    .font(SR.Text.title())
                    .foregroundStyle(Color.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tone))
                    .accessibilityHidden(true)
            }
            Text(name)
                .font(SR.Text.title(16))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("+\(points)")
                .font(SR.Text.figure(22))
                .foregroundStyle(tone)
                .monospacedDigit()
        }
        .frame(minHeight: 40)
    }
}

// MARK: - The feed

/// The guesses so far, newest first. A right answer reads "got it!" and never
/// shows what was typed; a "close!" is only ever mine.
struct DrawGuessFeed: View {
    let room: GameRoom
    @ObservedObject var store: DrawGuessStore

    var body: some View {
        let feed = Array((store.turn?.feed ?? []).reversed())
        if !feed.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Guesses", trailing: "\(feed.count)")
                VStack(spacing: 6) {
                    ForEach(feed) { entry in
                        row(entry)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("drawguess-feed")
        }
    }

    private func row(_ entry: DrawGuessFeedEntry) -> some View {
        let me = entry.playerId == room.meId
        let who = me ? "You" : entry.name
        let tone: Color = entry.kind == "solved" ? DrawGuessInk.color("green")
            : entry.kind == "close" ? DrawGuessInk.color("orange") : SR.accentInk
        return HStack(spacing: 10) {
            GameInitial(name: entry.name, filled: entry.kind != "guess", tone: tone, side: 30)
            line(entry, who: who)
            Spacer(minLength: 0)
            if entry.kind == "solved" {
                Image(systemName: "checkmark.circle.fill")
                    .font(SR.Text.title())
                    .foregroundStyle(tone)
                    .accessibilityHidden(true)
            } else if entry.kind == "close" {
                Image(systemName: "flame.fill")
                    .font(SR.Text.title())
                    .foregroundStyle(tone)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .fill(entry.kind == "guess" ? Color.clear : tone.opacity(0.12))
        )
        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("drawguess-feed-\(entry.n)")
    }

    @ViewBuilder
    private func line(_ entry: DrawGuessFeedEntry, who: String) -> some View {
        switch entry.kind {
        case "solved":
            Text("\(who) got it!")
                .font(SR.Text.title(16))
                .foregroundStyle(SR.good)
        case "close":
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.text ?? "")
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                Text("So close!")
                    .font(SR.Text.label())
                    .foregroundStyle(SR.warn)
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                Text(who)
                    .font(SR.Text.label())
                    .foregroundStyle(SR.inkMuted)
                Text(entry.text ?? "")
                    .font(SR.Text.body(16))
                    .foregroundStyle(SR.ink)
            }
        }
    }
}

// MARK: - Finished

struct DrawGuessFinished: View {
    let room: GameRoom
    @ObservedObject var store: DrawGuessStore
    let done: () -> Void
    /// This phone's record for the game, counted once on appearing.
    @State private var record: TableGameRecord?

    /// Draw & Guess rooms send no `startedAt`, so the finish's own clock (set
    /// once, when the game ends) tells one game in this room from the next:
    /// without it, Play again would never be counted.
    private var gameKey: String {
        TableGameKey.finished(roomId: room.id, startedAt: room.startedAt ?? room.phaseEndsAt)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Draw & Guess · \(DrawGuessSettings.about(room)) · final",
                             title: GameResults.title(room, solo: "You scored \(myScore)", none: "Nobody scored"),
                             strap: GameResults.strap(room))

                if room.me?.joined == true {
                    DrawGuessResultHero(room: room, score: myScore, place: place, won: room.winnerIds.contains(room.meId))
                }

                // The standings card cheers (confetti and a tap) when I won.
                GameStandingsCard(
                    room: room,
                    label: "Standings",
                    id: "drawguess-standings",
                    detail: { _ in "" },
                    figure: { (text: "\($0.score)", spoken: "\($0.score) points") }
                )

                GameFinishedButtons(room: room, store: store, prefix: "drawguess", done: done)

                if let record {
                    TableRecordCard(record: record, gameKey: gameKey, bestLabel: "Best score", id: "drawguess-record")
                }

                if !store.strokes.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "The last drawing", trailing: store.turn?.word)
                        DrawGuessCanvasView(store: store, framed: true)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color(hex: 0x9A6A3A))
                            )
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("drawguess-finished")
        .onAppear { noteRecord() }
    }

    private var myScore: Int {
        room.standings?.first { $0.id == room.meId }?.score ?? room.me?.score ?? 0
    }

    private var place: Int? {
        guard !room.solo, let rows = room.standings, !rows.isEmpty else { return nil }
        return PartyRoomMaths.place(of: room.meId, ids: rows.map(\.id), scores: rows.map(\.score))
    }

    private func noteRecord() {
        guard record == nil, room.me?.joined == true else { return }
        let book = TableGameBestStore(gameId: GameKind.drawGuess.rawValue, persists: !SRDemo.isOn)
        let won = room.winnerIds.contains(room.meId)
        let kept = book.note(variant: GameKind.drawGuess.rawValue, key: gameKey, won: won, score: myScore)
        record = kept
        // A win is felt by the standings card; a new best without one is felt here.
        if kept.beatBest(gameKey), !won { SRHaptic.ok() }
    }
}

/// My game in one card: a trophy or a palette, my score and my place.
struct DrawGuessResultHero: View {
    let room: GameRoom
    let score: Int
    let place: Int?
    let won: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(won ? DrawGuessInk.color("yellow") : DrawGuessInk.color("blue").opacity(0.16))
                    .frame(width: 76, height: 76)
                Image(systemName: won ? "trophy.fill" : "paintpalette.fill")
                    .font(SR.Text.hero(34))
                    .foregroundStyle(won ? Color.white : DrawGuessInk.color("blue"))
            }
            .tablePopIn()
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(score)")
                        .font(SR.Text.hero(44))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                    Text(score == 1 ? "point" : "points")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.inkSecondary)
                }
                if let place {
                    Text("\(PartyRoomMaths.ordinal(place)) of \(room.standings?.count ?? room.playing.count)")
                        .font(SR.Text.title(15))
                        .foregroundStyle(place == 1 ? SR.accent : SR.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("drawguess-result")
    }
}
