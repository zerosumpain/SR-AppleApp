import SwiftUI
import UIKit

/// One Boggle room, from lobby to the reveal.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the round the host picked — grid, clock, scoring — and how to play as
/// the lobby's panel. Playing is the tray of dice, filling the width: drag a
/// finger through touching letters and lift to send the word, or tap the dice
/// one at a time and press Enter. The trace glows as it goes, the word above
/// says what it would score, and a word that lands flashes its path green and
/// floats its points away. Everyone else is a name, a word count and a score
/// until the finish reveals every word found, who found it, what was crossed
/// out, and the best words nobody saw — any of which lights its path on the
/// board — beside my bests for this size of board.
struct BoggleScreen: View {
    let roomId: String
    @StateObject private var store: BoggleStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: BoggleStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Boggle")
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
        guard !store.ended, let phase = store.room?.phase else { return false }
        return phase == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "boggle-ended", done: { dismiss() })
        } else if let room = store.room {
            switch room.phase {
            case .lobby, .unknown, .armed, .result, .question, .reveal, .show, .input, .review:
                GameLobby(room: room, store: store, prefix: "boggle", done: { dismiss() },
                          panel: AnyView(BoggleLobbyPanel(room: room)))
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Drag through touching letters. Lift to send the word.",
                                  id: "boggle-countdown")
            case .playing:
                BogglePlaying(room: room, store: store)
            case .finished:
                BoggleFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "boggle-ended", done: { dismiss() })
            }
        } else {
            ProgressView()
                .tint(SR.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .srPaper()
        }
    }
}

// MARK: - The dice, drawn

/// A Boggle die's paint. Fixed, not the mode-following tokens: dice are
/// cream plastic with dark letters on every phone, as the real ones are.
enum BoggleRoomPaint {
    static let face = Color(hex: 0xFBF5E6)
    static let faceLow = Color(hex: 0xEADFC6)
    static let lip = Color(hex: 0xB9A988)
    static let letter = Color(hex: 0x24202F)
    /// The tray, deep and a little warm, under the dice.
    static var tray: [Color] { [SR.accentDeep, SR.accentDeep.opacity(0.82)] }
}

/// One die. `lit` is in the word being traced (or the word picked at the
/// finish); `flash` is a word that just landed; `last` is under the finger.
struct BoggleRoomDie: View {
    let face: String
    let side: CGFloat
    var lit = false
    var flash = false
    var last = false
    /// The trace's colour: the accent while playing, the accent ink at the finish.
    var tone: Color = SR.accent

    var body: some View {
        let radius = side * 0.2
        let text = BoggleRules.display(face)
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(lit || flash ? Color.black.opacity(0.25) : BoggleRoomPaint.lip)
                .offset(y: max(2, side * 0.05))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(last ? Color.white : Color.white.opacity(0.5), lineWidth: last ? 3 : 1)
            Text(text.isEmpty ? " " : text)
                // The play field keeps its own size: a die is a die.
                .font(.system(size: text.count > 1 ? side * 0.4 : side * 0.54, weight: .heavy, design: .rounded))
                .foregroundStyle(lit || flash ? Color.white : BoggleRoomPaint.letter)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 3)
        }
        .frame(width: side, height: side)
    }

    private var fill: LinearGradient {
        if flash {
            return LinearGradient(colors: [SR.good.opacity(0.85), SR.good], startPoint: .top, endPoint: .bottom)
        }
        if lit {
            return LinearGradient(colors: [tone.opacity(0.85), tone], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [BoggleRoomPaint.face, BoggleRoomPaint.faceLow], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Lobby

/// The lobby's panel: the round the host picked, then how to play.
struct BoggleLobbyPanel: View {
    let room: GameRoom
    @State private var book = WordRoomBestBook()

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            BoggleRoundCard(room: room)
            WordRoomHowToCard(title: "How to play", steps: steps, best: best, id: "boggle-howto") {
                HStack(spacing: 5) {
                    ForEach(Array(["B", "O", "G", "G", "L", "E"].enumerated()), id: \.offset) { item in
                        BoggleRoomDie(face: item.element, side: 40, lit: item.offset < 3, last: item.offset == 2)
                    }
                }
            }
        }
        .onAppear { book = WordRoomBestStore(game: .boggle, variant: "\(room.size)x\(room.size)").load() }
    }

    private var steps: [WordRoomStep] {
        var list = [
            WordRoomStep(icon: "hand.draw.fill", text: "Drag through letters that touch — across, up, down or diagonally — and lift to send the word."),
            WordRoomStep(icon: "hand.tap.fill", text: "Or tap the letters one by one, then press Enter. Each die once per word."),
            WordRoomStep(icon: "rotate.right", text: "Turn the board for a fresh look at the same dice."),
        ]
        if BoggleScoring.from(room.scoring) == .classic {
            list.append(WordRoomStep(icon: "xmark.circle.fill", text: "Classic scoring: a word someone else also finds is crossed out. Hunt the odd ones."))
        } else {
            list.append(WordRoomStep(icon: "checkmark.circle.fill", text: "Every word counts for whoever finds it."))
        }
        return list
    }

    private var best: String? {
        guard book.played > 0 else { return nil }
        var parts = ["Your best on \(BoggleSettings.sizeLabel(room.size)): \(book.bestScore) points"]
        if !book.longest.isEmpty { parts.append("longest \(BoggleRules.display(book.longest).uppercased())") }
        return parts.joined(separator: " · ")
    }
}

/// The round the host picked, in the lobby: a little tray of the right size,
/// a few dice face up, beside grid, clock and scoring.
struct BoggleRoundCard: View {
    let room: GameRoom

    static let sample = Array("BOGGLEWORDSFUNQXTRAPSENDLIMEAHORSE").map { String($0) }

    var body: some View {
        let scoring = BoggleScoring.from(room.scoring)
        HStack(alignment: .center, spacing: 16) {
            tray
            VStack(alignment: .leading, spacing: 4) {
                Text(BoggleSettings.about(room).uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text(scoring.label)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(scoring.line)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(room.minLength)+ letters")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Round: \(BoggleSettings.about(room)). \(scoring.label). \(scoring.line) Words of \(room.minLength) letters or more.")
        .accessibilityIdentifier("boggle-round")
    }

    private var tray: some View {
        let n = max(room.size, 1)
        let side: CGFloat = 84
        let gap: CGFloat = 3
        let cell = (side - gap * CGFloat(n - 1)) / CGFloat(n)
        return VStack(spacing: gap) {
            ForEach(0..<n, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<n, id: \.self) { column in
                        BoggleRoomDie(face: Self.sample[(row * n + column) % Self.sample.count], side: cell)
                    }
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: BoggleRoomPaint.tray, startPoint: .top, endPoint: .bottom))
        )
        .accessibilityHidden(true)
    }
}

// MARK: - Playing

struct BogglePlaying: View {
    let room: GameRoom
    @ObservedObject var store: BoggleStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The path of the word that just landed, lit green for a moment.
    @State private var flash: [Int] = []
    @State private var landedToken = 0
    @State private var floatText = ""
    /// Bumped for a long word (six letters or more): the board bursts.
    @State private var bigWord = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                WordRoomTimeBar(room: room, store: store)
                if !room.others.isEmpty {
                    AnagramOthersStrip(room: room, prefix: "boggle")
                }
                wordRow
                BoggleBoard(room: room, store: store, interactive: true, flash: flash)
                    .overlay { WordRoomBurst(token: bigWord) }
                controls
                statusLine
                    .frame(maxWidth: .infinity, minHeight: 36)
                BoggleMyWords(words: store.mine)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        // A drag on the board must trace, not scroll the page.
        .scrollDisabled(!store.trace.isEmpty)
        .srGround(.warm)
        .accessibilityIdentifier("boggle-playing")
        .onChange(of: store.shakes) { _, _ in
            if let refusal = store.refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
        .onChange(of: store.landed) { _, word in
            guard let word else { return }
            landed(word)
        }
    }

    private func landed(_ word: BoggleWord) {
        floatText = "+\(word.points)"
        landedToken += 1
        if word.word.count >= 6 { bigWord += 1 }
        UIAccessibility.post(notification: .announcement, argument: "\(word.word), \(word.points) points")
        guard !reduceMotion, !word.path.isEmpty else { return }
        flash = word.path
        let path = word.path
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            if flash == path {
                withAnimation(.easeOut(duration: 0.35)) { flash = [] }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BOGGLE · \(BoggleSettings.sizeLabel(room.size)) · \(GameDifficulty.label(for: room.difficulty).uppercased())")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(room.me?.score ?? 0)")
                        .font(SR.Text.display(30))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                        .srNumeric(Double(room.me?.score ?? 0))
                    Text(GameResults.count(room.me?.wordCount ?? 0, "word", "words").uppercased())
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your score, \(room.me?.score ?? 0) points, \(GameResults.count(room.me?.wordCount ?? 0, "word", "words"))")
                .accessibilityIdentifier("boggle-my-score")
            }
            Spacer(minLength: 8)
            WordRoomClock(room: room, store: store, id: "boggle-timer")
        }
    }

    private var wordState: WordRoomWordState {
        let word = store.word
        return WordRoomWordState.of(word: word, minLength: room.minLength, mine: store.mine.map(\.word),
                                    points: BoggleRules.points(for: word, table: room.points))
    }

    /// The word being traced, with what it would score, over a rule.
    private var wordRow: some View {
        let word = store.word
        let shown = BoggleRules.display(word)
        let state = wordState
        let had = state == .have
        return VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(word.isEmpty ? " " : shown.uppercased())
                    .font(SR.Text.hero(36))
                    .tracking(3)
                    .foregroundStyle(had ? SR.inkGhost : SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                chip(state)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            Capsule()
                .fill(state.ready ? SR.accent : SR.line)
                .frame(height: state.ready ? 3 : 1.5)
                .srAnimation(.snappy, value: state.ready)
        }
        .modifier(WordleShake(animatableData: CGFloat(reduceMotion ? 0 : store.shakes)))
        .animation(.linear(duration: 0.4), value: store.shakes)
        .overlay { WordRoomFloatUp(text: floatText, token: landedToken, tone: SR.good) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word.isEmpty ? "Your word, empty" : "Your word, \(word)")
        .accessibilityValue(state.text)
        .accessibilityIdentifier("boggle-word")
    }

    @ViewBuilder
    private func chip(_ state: WordRoomWordState) -> some View {
        switch state {
        case .empty:
            EmptyView()
        case .short:
            Text(state.text.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
        case .have:
            Text("HAVE IT")
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
        case .worth(let points):
            Text("+\(points)")
                .font(SR.Text.figure(20))
                .foregroundStyle(SR.accent)
                .monospacedDigit()
                .transition(.opacity)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { store.rotate() } label: {
                Image(systemName: "rotate.right.fill")
                    .font(.title3.weight(.semibold))
            }
            .buttonStyle(WordRoomButtonStyle(tone: .soft))
            .frame(width: 76)
            .accessibilityLabel("Turn the board")
            .accessibilityIdentifier("boggle-rotate")

            Button { store.delete() } label: {
                Image(systemName: "delete.left.fill")
                    .font(.title3.weight(.semibold))
            }
            .buttonStyle(WordRoomButtonStyle(tone: .soft))
            .frame(width: 76)
            .disabled(store.trace.isEmpty)
            .accessibilityLabel("Delete letter")
            .accessibilityIdentifier("boggle-delete")

            Button { store.submit() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "return")
                        .font(.headline.weight(.bold))
                    Text("ENTER")
                }
            }
            .buttonStyle(WordRoomButtonStyle(tone: wordState.ready ? .go : .firm))
            .disabled(store.trace.path.count < 2)
            .accessibilityLabel("Enter")
            .accessibilityIdentifier("boggle-enter")
        }
        .disabled(!store.canPlay)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let refusal = store.refusal {
            WordRoomPill(text: refusal, icon: "exclamationmark.circle.fill", tone: SR.error)
                .accessibilityIdentifier("boggle-refusal")
        } else if let landed = store.landed {
            WordRoomPill(text: "\(BoggleRules.display(landed.word).uppercased()) +\(landed.points)", icon: "checkmark.circle.fill", tone: SR.good, filled: true)
                .accessibilityIdentifier("boggle-landed")
        } else if room.me?.joined != true {
            WordRoomPill(text: "You are not playing in this one.", icon: "eye", tone: SR.inkMuted)
        } else {
            Text(rulesLine)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .multilineTextAlignment(.center)
        }
    }

    /// "3+ letters · 3→1 4→2 5→3 6→4 … · shared words cross out".
    private var rulesLine: String {
        let t = { (n: Int) in BoggleRules.points(for: String(repeating: "a", count: n), table: room.points) }
        let first = max(room.minLength, 3)
        let table = (first..<first + 4).map { "\($0)→\(t($0))" }
        var line = "\(room.minLength)+ letters · " + table.joined(separator: " ") + " …"
        if BoggleScoring.from(room.scoring) == .classic, !room.solo { line += " · shared words cross out" }
        return line
    }
}

/// The dice. While playing it takes a finger: a drag through touching tiles
/// traces a word and lifting sends it; a touch that never leaves its tile is a
/// tap, which builds a word one tile at a time. Finished, it is still, and
/// lights the path of whichever word was picked below.
///
/// Every tile is also an accessibility button (a VoiceOver double-tap is a
/// tap), labelled with its letter and where it sits in the word.
struct BoggleBoard: View {
    let room: GameRoom
    @ObservedObject var store: BoggleStore
    let interactive: Bool
    /// The path of a word that just landed, lit green.
    var flash: [Int] = []

    /// Space between dice.
    static let gap: CGFloat = 6
    /// A drag's first tile, until the finger moves to another.
    @State private var touchStart: Int?
    /// The finger has moved off its first tile: this is a drag, not a tap.
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let side = BoggleRules.tileSide(width: geo.size.width - 16, size: room.size, gap: Self.gap)
            let boardSide = side * CGFloat(room.size) + Self.gap * CGFloat(room.size - 1)
            board(side: side)
                .frame(width: boardSide, height: boardSide)
                .padding(8)
                .background(tray)
                .frame(maxWidth: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("boggle-board")
    }

    private var tray: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: BoggleRoomPaint.tray, startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1.5)
            )
            .shadow(color: SR.ink.opacity(0.2), radius: 10, y: 5)
    }

    private var path: [Int] { interactive ? store.trace.path : store.highlightedPath }

    private func board(side: CGFloat) -> some View {
        let n = room.size
        let grid = room.grid ?? Array(repeating: "", count: n * n)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: Self.gap) {
                ForEach(0..<n, id: \.self) { row in
                    HStack(spacing: Self.gap) {
                        ForEach(0..<n, id: \.self) { column in
                            let tile = BoggleRules.tile(atDisplay: row * n + column, size: n, turns: store.turns)
                            die(tile, face: tile < grid.count ? grid[tile] : "", side: side)
                        }
                    }
                }
            }
            traceLine(side: side)
                .allowsHitTesting(false)
        }
        .animation(.snappy(duration: 0.3), value: store.turns)
        .contentShape(Rectangle())
        .highPriorityGesture(drag(side: side), including: interactive ? .all : .subviews)
    }

    private func centre(of tile: Int, side: CGFloat) -> CGPoint {
        let shown = BoggleRules.displayed(tile, size: room.size, turns: store.turns)
        let (row, column) = BoggleRules.cell(shown, size: room.size)
        let pitch = side + Self.gap
        return CGPoint(x: CGFloat(column) * pitch + side / 2, y: CGFloat(row) * pitch + side / 2)
    }

    private var lineTone: Color { interactive ? SR.accent : SR.accentInk }

    /// The trace, as a glowing line through the centres of its tiles, with a
    /// bead on each.
    private func traceLine(side: CGFloat) -> some View {
        let points = path.map { centre(of: $0, side: side) }
        let line = Path { trace in
            guard let first = points.first else { return }
            trace.move(to: first)
            for point in points.dropFirst() { trace.addLine(to: point) }
        }
        let bead = max(6, side * 0.14)
        return ZStack(alignment: .topLeading) {
            line.stroke(lineTone.opacity(0.28),
                        style: StrokeStyle(lineWidth: max(14, side * 0.38), lineCap: .round, lineJoin: .round))
            line.stroke(lineTone.opacity(0.8),
                        style: StrokeStyle(lineWidth: max(5, side * 0.12), lineCap: .round, lineJoin: .round))
            ForEach(0..<points.count, id: \.self) { index in
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(lineTone, lineWidth: 2))
                    .frame(width: bead, height: bead)
                    .position(points[index])
            }
        }
    }

    private func die(_ tile: Int, face: String, side: CGFloat) -> some View {
        let at = path.firstIndex(of: tile)
        let lit = at != nil
        let last = interactive && tile == path.last
        let pressed = interactive && touchStart == tile && !dragging && !lit
        let flashing = interactive && flash.contains(tile) && !lit
        let text = BoggleRules.display(face)
        return ZStack {
            BoggleRoomDie(face: face, side: side, lit: lit, flash: flashing, last: last, tone: lineTone)
                .brightness(pressed ? -0.06 : 0)
            if let at, !interactive || path.count > 1 {
                Text("\(at + 1)")
                    .font(.system(size: max(9, side * 0.16), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(side * 0.08)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side)
        .scaleEffect(last ? 1.08 : (pressed ? 0.94 : 1))
        .animation(.snappy(duration: 0.12), value: last)
        .animation(.snappy(duration: 0.12), value: pressed)
        .animation(.easeOut(duration: 0.2), value: flashing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(text, at: at))
        .accessibilityAddTraits(interactive ? .isButton : [])
        .accessibilityAddTraits(lit ? .isSelected : [])
        .accessibilityHint(interactive ? (tile == path.last ? "Takes it back off" : "Adds it to your word") : "")
        .accessibilityAction { if interactive { store.tap(tile: tile) } }
        .accessibilityIdentifier("boggle-tile-\(tile)")
    }

    private func spoken(_ face: String, at: Int?) -> String {
        guard let at else { return face }
        return "\(face), letter \(at + 1) of your word"
    }

    private func drag(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let hit = { (point: CGPoint) -> Int? in
                    BoggleRules.tile(at: point, size: room.size, side: side, gap: Self.gap).map {
                        BoggleRules.tile(atDisplay: $0, size: room.size, turns: store.turns)
                    }
                }
                if touchStart == nil {
                    // The first touch must land squarely on a tile; a wider
                    // reach so a fingertip on its edge still counts.
                    touchStart = BoggleRules.tile(at: value.startLocation, size: room.size, side: side,
                                                  gap: Self.gap, reach: 0.72)
                        .map { BoggleRules.tile(atDisplay: $0, size: room.size, turns: store.turns) }
                }
                guard let start = touchStart, let tile = hit(value.location), tile != start || dragging else { return }
                if !dragging {
                    dragging = true
                    // Carry on from a word built by taps if this drag began on
                    // its last tile; otherwise the drag is a new word.
                    if store.trace.last != start {
                        store.clearTrace()
                        store.drag(to: start)
                    }
                }
                store.drag(to: tile)
            }
            .onEnded { _ in
                defer {
                    touchStart = nil
                    dragging = false
                }
                guard let start = touchStart else { return }
                if dragging {
                    store.submit()
                } else {
                    store.tap(tile: start)
                }
            }
    }
}

/// My words, newest first, with their points.
struct BoggleMyWords: View {
    let words: [BoggleWord]

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Your words", trailing: words.isEmpty ? nil : "\(words.count)")
            if words.isEmpty {
                Text("Drag through touching letters and lift to send. Or tap them one by one, then Enter.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(BoggleRules.newestFirst(words)) { word in
                        chip(word)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .srAnimation(.snappy, value: words.count)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("boggle-my-words")
    }

    private func chip(_ word: BoggleWord) -> some View {
        HStack(spacing: 6) {
            Text(BoggleRules.display(word.word).uppercased())
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            Text("+\(word.points)")
                .font(SR.Text.label())
                .foregroundStyle(SR.accentInk)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(SR.accent.opacity(0.14)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(word.word), \(word.points) points")
    }
}

// MARK: - Finished

struct BoggleFinished: View {
    let room: GameRoom
    @ObservedObject var store: BoggleStore
    let done: () -> Void

    @State private var book: WordRoomBestBook?
    @State private var news = WordRoomNewBests()

    private var classic: Bool { BoggleScoring.from(room.scoring) == .classic && !room.solo }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    SRPageHeader(kicker: "Boggle · \(BoggleSettings.about(room)) · final",
                                 title: GameResults.title(room, solo: "You scored \(room.me?.score ?? 0)", none: "Nobody scored"),
                                 strap: GameResults.strap(room))

                    GameStandingsCard(
                        room: room,
                        label: room.solo ? "Your game" : "Standings",
                        id: "boggle-standings",
                        detail: detail,
                        figure: { (text: "\($0.score)", spoken: "\($0.score) points") }
                    )

                    if let book {
                        WordRoomBestsCard(items: bestItems(book), id: "boggle-bests")
                    }

                    boardSection
                        .id("board")

                    if let found = room.boggleFound, !found.isEmpty {
                        VStack(alignment: .leading, spacing: SR.cardGap) {
                            SRSectionLabel(text: "Every word found", trailing: "\(found.count)")
                            VStack(spacing: 0) {
                                ForEach(Array(found.enumerated()), id: \.element.id) { index, word in
                                    if index > 0 { Divider().overlay(SR.divider) }
                                    foundRow(word) { show(word.word, reader) }
                                }
                            }
                            .padding(.horizontal, SR.cardPadding)
                            .padding(.vertical, 6)
                            .srGlassCard(.paper)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("boggle-found")
                        }
                    }

                    if let missed = room.boggleMissed, !missed.isEmpty {
                        VStack(alignment: .leading, spacing: SR.cardGap) {
                            SRSectionLabel(text: "Nobody found", trailing: "\(missed.count)")
                            FlowChips(missed: missed, lit: store.highlighted) { show($0, reader) }
                                .accessibilityIdentifier("boggle-missed")
                        }
                    }

                    GameFinishedButtons(room: room, store: store, prefix: "boggle", done: done)
                }
                .padding(.horizontal, SR.gutter)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .srGround(.warm)
        .accessibilityIdentifier("boggle-finished")
        .onAppear { recordBests() }
    }

    private var boardSection: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "The board", trailing: caption)
            BoggleBoard(room: room, store: store, interactive: false)
            possibleMeter
            Text(boardLine)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("boggle-possible")
        }
    }

    /// How much of the board the family found, as a bar.
    @ViewBuilder
    private var possibleMeter: some View {
        if let possible = room.possible, possible.words > 0 {
            let found = room.boggleFound?.count ?? 0
            let share = CGFloat(min(1, Double(found) / Double(possible.words)))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.line)
                    Capsule()
                        .fill(LinearGradient(colors: [SR.accent.opacity(0.7), SR.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * share))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
    }

    /// The lit word, over the board.
    private var caption: String? {
        store.highlighted.map { BoggleRules.display($0).uppercased() }
    }

    private var boardLine: String {
        let found = room.boggleFound?.count ?? 0
        let tail = store.highlighted == nil ? "Tap a word below to see it on the board." : "Tap it again to clear."
        guard let line = BoggleRules.possibleLine(found: found, possible: room.possible, solo: room.solo) else { return tail }
        return "\(line) \(tail)"
    }

    private func show(_ word: String, _ reader: ScrollViewProxy) {
        store.highlight(word)
        if store.highlighted != nil {
            withAnimation(.snappy) { reader.scrollTo("board", anchor: .top) }
        }
    }

    private func detail(_ row: GameStanding) -> String {
        let words = GameResults.count(row.words, "word", "words")
        guard let longest = row.longest, !longest.isEmpty else { return words }
        return "\(words) · longest \(BoggleRules.display(longest).uppercased())"
    }

    private func foundRow(_ word: BoggleFound, action: @escaping () -> Void) -> some View {
        let crossed = classic && word.shared
        let lit = store.highlighted == word.word
        return Button(action: action) {
            HStack(spacing: 10) {
                Text(BoggleRules.display(word.word).uppercased())
                    .font(SR.Text.title())
                    .foregroundStyle(crossed ? SR.inkGhost : SR.ink)
                    .strikethrough(crossed, color: SR.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if crossed {
                    Text("SHARED")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(SR.line, lineWidth: 1))
                }
                Spacer(minLength: 8)
                HStack(spacing: -6) {
                    ForEach(word.finderIds, id: \.self) { id in
                        GameInitial(name: id == room.meId ? "You" : room.name(of: id),
                                    tone: id == room.meId ? SR.accent : SR.accentInk)
                            .overlay(Circle().strokeBorder(SR.paper, lineWidth: 1.5))
                    }
                }
                Text("\(word.points)")
                    .font(SR.Text.figure(18))
                    .foregroundStyle(crossed ? SR.inkGhost : SR.ink)
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
                Image(systemName: lit ? "eye.fill" : "eye")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(lit ? SR.accentInk : SR.inkGhost)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: SR.tapTarget)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(lit ? SR.accentInk.opacity(0.12) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(word, crossed: crossed))
        .accessibilityHint("Shows it on the board")
        .accessibilityAddTraits(lit ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("boggle-found-\(word.word)")
    }

    private func spoken(_ word: BoggleFound, crossed: Bool) -> String {
        let who = GameNames.list(word.finderIds.map { $0 == room.meId ? "you" : room.name(of: $0) })
        let shared = crossed ? ", shared, crossed out" : ""
        return "\(word.word), found by \(who)\(shared), \(word.points) points"
    }

    // MARK: Bests

    private func recordBests() {
        guard book == nil, let me = room.me, me.joined else { return }
        let mine = room.standings?.first { $0.id == room.meId }
        let myWords = me.boggleWords ?? []
        let mineLongest: String = myWords.map(\.word).max(by: { $0.count < $1.count }) ?? ""
        let longest: String = mine?.longest ?? mineLongest
        let round = WordRoomRound(
            key: WordRoomRound.key(roomId: room.id, startedAt: room.startedAt, deal: (room.grid ?? []).joined()),
            competitive: !room.solo,
            won: room.winnerIds.contains(room.meId),
            score: mine?.score ?? me.score,
            words: mine?.words ?? me.wordCount,
            longest: longest
        )
        let result = WordRoomBestStore(game: .boggle, variant: "\(room.size)x\(room.size)").record(round, persist: !SRDemo.isOn)
        book = result.book
        news = result.news ?? WordRoomNewBests()
        if news.any, !room.winnerIds.contains(room.meId) { SRHaptic.ok() }
    }

    private func bestItems(_ book: WordRoomBestBook) -> [WordRoomBestItem] {
        var items = [
            WordRoomBestItem(label: "Best on \(BoggleSettings.sizeLabel(room.size))", value: "\(book.bestScore)", fresh: news.score),
            WordRoomBestItem(label: "Longest word", value: book.longest.isEmpty ? "–" : BoggleRules.display(book.longest).uppercased(), fresh: news.longest),
            WordRoomBestItem(label: "Most words", value: "\(book.bestWords)"),
            WordRoomBestItem(label: "Played", value: "\(book.played)"),
        ]
        if book.won > 0 { items.append(WordRoomBestItem(label: "Won", value: "\(book.won) · \(book.winPercent)%")) }
        return items
    }
}

/// The best words nobody found, as chips that wrap; each lights its path.
private struct FlowChips: View {
    let missed: [BoggleMissed]
    let lit: String?
    let pick: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(missed) { word in
                chip(word)
            }
        }
    }

    private func chip(_ word: BoggleMissed) -> some View {
        let on = lit == word.word
        return Button {
            pick(word.word)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "eye.fill" : "eye")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(on ? SR.paper : SR.inkGhost)
                    .accessibilityHidden(true)
                Text(BoggleRules.display(word.word).uppercased())
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(on ? SR.paper : SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                Text("\(word.points)")
                    .font(SR.Text.label())
                    .foregroundStyle(on ? SR.paper : SR.accent)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: SR.tapTarget)
            .background(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 2, style: .continuous)
                    .fill(on ? SR.accentInk : Color.clear)
            )
            .srGlassCard(on ? .clear : .paper, radius: SR.Glass.innerRadius + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(word.word), \(word.points) points, nobody found it")
        .accessibilityHint("Shows it on the board")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("boggle-missed-\(word.word)")
    }
}
