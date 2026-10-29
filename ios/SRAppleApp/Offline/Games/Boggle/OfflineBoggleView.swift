import SwiftUI

/// Boggle on one phone: the clock, the dice, the word being traced, and
/// everyone's scores; at the end, every word found and the best ones missed,
/// any of which lights its path on the board.
///
/// The board is sized from the page's width, so four dice a row fit a
/// 375-point phone. A drag through touching dice traces a word and lifting
/// sends it; a touch that never leaves its die is a tap, which builds a word
/// one die at a time for Enter — and is what VoiceOver's double-tap does. The
/// trace itself stays on this phone: only the finished path travels, and the
/// host spells it, checks it and scores it.
///
/// The tracing pieces are the online Boggle's (`BoggleTrace`, `BoggleRules`'
/// tile maths), so a finger behaves the same on both boards — including Turn,
/// which gives the board a quarter turn on this phone only (a fresh look at
/// the same dice, as players turn the real tray). Each die is placed by its
/// turned position, so on a turn the dice glide to their new places.
///
/// The dice are rounded cubes in a plastic tray (`PlayTableLetterTile`); they
/// tumble in when the board is first shown, the trace glows through them, and
/// a word this phone already knows is wrong shakes the word bar.
struct OfflineBoggleView: View {
    let context: OfflineGameContext<OfflineBoggleRules>
    @State private var trace = BoggleTrace(size: OfflineBoggleRules.size)
    /// A drag's first die, until the finger moves to another.
    @State private var touchStart: Int?
    /// The finger has moved off its first die: a drag, not a tap.
    @State private var dragging = false
    /// The reveal's lit word, shown on the board.
    @State private var lit: String?
    /// A refusal this phone can say without asking the host.
    @State private var note: String?
    /// Quarter turns of the board, on this phone only.
    @State private var turns = 0
    /// Bumped to shake the word bar.
    @State private var shakes = 0
    @ObservedObject private var results = OfflineResultStore.shared

    private typealias Rules = OfflineBoggleRules
    private static let gap: CGFloat = 7

    private var view: Rules.PlayerView { context.view }
    private var revealed: Bool { view.phase == .reveal || view.phase == .over }
    private var interactive: Bool { view.phase == .playing && view.mine != nil }
    private var myScore: Int { view.board.first { $0.id == context.me }?.score ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SRPageHeader(kicker: kicker, title: title)
                    .accessibilityIdentifier("offline-boggle-header")
                clockBar
                if let grid = view.grid {
                    if interactive { wordRow(grid) }
                    board(grid)
                    if interactive {
                        controls
                        statusLine
                            .frame(maxWidth: .infinity)
                            .srAnimation(.spring(response: 0.35, dampingFraction: 0.6), value: view.mine?.first?.word)
                    } else if revealed {
                        Text(boardLine)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("offline-boggle-possible")
                    }
                } else {
                    waitingTray
                }
                if revealed {
                    reveal
                    if view.mine != nil {
                        PlayTableBestStrip(score: myScore, best: results.queue.tallies[Rules.info.id]?.best)
                    }
                } else if let mine = view.mine, !mine.isEmpty {
                    myWords(mine)
                }
                OfflineWordScores(title: view.board.count == 1 ? "Score" : "Scores", rows: rows, me: context.me,
                                  players: context.players, id: "offline-boggle-scores")
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        // A drag on the board must trace, not scroll the page.
        .scrollDisabled(interactive && !trace.isEmpty)
        .srGround(.warm)
        .onChange(of: view.mine?.count) { old, new in
            if (new ?? 0) > (old ?? 0) { SRHaptic.ok() }
        }
        .onChange(of: context.refusal) { _, new in
            if new != nil {
                SRHaptic.bad()
                shakes += 1
            }
        }
        .onChange(of: view.phase) { _, new in
            trace.clear()
            note = nil
            if new == .playing { SRHaptic.select() }
            if new == .reveal { SRHaptic.ok() }
        }
    }

    // MARK: - Words

    private var kicker: String {
        guard let mine = view.mine else { return "Boggle · 4×4 · watching" }
        return "Boggle · 4×4 · \(mine.count == 1 ? "1 word" : "\(mine.count) words")"
    }

    private var title: String {
        switch view.phase {
        case .countdown: return "Ready…"
        case .playing: return view.mine == nil ? "Tracing" : "\(myScore) points"
        case .reveal, .over:
            guard let top = view.board.first else { return "Time's up" }
            if view.board.count == 1 { return "\(top.score) points" }
            if view.board.filter({ $0.score == top.score }).count > 1 { return "A tie" }
            return top.id == context.me ? "You win" : "\(top.name) wins"
        }
    }

    private var clockBar: some View {
        switch view.phase {
        case .countdown:
            return OfflineWordClock(clock: context.clock, label: "Starting in", until: view.startsAt, tone: SR.accent)
        case .playing:
            return OfflineWordClock(clock: context.clock, label: "Time left", until: view.endsAt,
                                    chip: view.crossing ? "shared words cross out" : nil)
        case .reveal, .over:
            return OfflineWordClock(clock: context.clock, label: "Time's up", until: nil)
        }
    }

    /// Before the dice are rolled: the empty tray and what is coming.
    private var waitingTray: some View {
        VStack(spacing: 14) {
            OfflineBoggleTray(cornerRadius: 22) {
                Image(systemName: "die.face.5.fill")
                    .font(SR.Text.hero(44))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 140)
            }
            .accessibilityHidden(true)
            Text("The dice are rolling. Get ready to trace.")
                .font(SR.Text.body())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The word being traced

    private func wordRow(_ grid: [String]) -> some View {
        let word = BoggleRules.word(trace.path, grid: grid)
        let had = view.mine?.contains { $0.word == word } ?? false
        return HStack(alignment: .center, spacing: 10) {
            Text(word.isEmpty ? "TRACE A WORD" : word.uppercased())
                .font(word.isEmpty ? SR.Text.label(14) : SR.Text.hero(32))
                .tracking(word.isEmpty ? 1.6 : 3)
                .foregroundStyle(word.isEmpty ? Color.white.opacity(0.6) : (had ? Color.white.opacity(0.5) : Color.white))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity)
            if word.count >= Rules.minLength && !had {
                Text("+\(Rules.points(word))")
                    .font(SR.Text.figure(20))
                    .foregroundStyle(PlayTablePaint.gold)
                    .transition(.scale.combined(with: .opacity))
            } else if had {
                Text("HAVE IT")
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x8C5A33), Color(hex: 0x5E3A1E)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 3)
        )
        .modifier(PlayTableShake(animatableData: CGFloat(shakes)))
        .srAnimation(.linear(duration: 0.4), value: shakes)
        .srAnimation(.snappy(duration: 0.18), value: word)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word.isEmpty ? "Your word, empty" : "Your word, \(word)")
        .accessibilityIdentifier("offline-boggle-word")
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                SRHaptic.select()
                turns = (turns + 1) % 4
            } label: {
                Image(systemName: "rotate.right")
                    .font(SR.Text.title(20))
                    .frame(width: PlayTableMetrics.bigLabel, height: PlayTableMetrics.bigLabel)
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(!trace.isEmpty)
            .accessibilityLabel("Turn the board")
            .accessibilityHint("Gives the dice a quarter turn on your phone, for a fresh look.")
            .accessibilityIdentifier("offline-boggle-turn")
            PlayTableButton(title: "Delete", icon: "delete.left", weight: .regular, haptic: .select) {
                trace.delete()
            }
            .disabled(trace.isEmpty)
            .accessibilityIdentifier("offline-boggle-delete")
            PlayTableButton(title: "Enter", icon: "return", haptic: .none) {
                submit()
            }
            .disabled(trace.path.count < 2)
            .accessibilityIdentifier("offline-boggle-enter")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let note {
            Label(note, systemImage: "exclamationmark.circle")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.error)
                .multilineTextAlignment(.center)
        } else if let last = view.mine?.first {
            Label("\(last.word.uppercased()) +\(last.points)", systemImage: "checkmark.circle.fill")
                .font(SR.Text.title(16))
                .foregroundStyle(SR.good)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(SR.good.opacity(0.14)))
                .id(last.word)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityIdentifier("offline-boggle-landed")
        } else {
            Text("Drag through touching letters, then lift. \(Rules.minLength)+ letters, a point a letter past two.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Sends the trace, unless this phone already knows the answer.
    private func submit() {
        guard let grid = view.grid else { return }
        let path = trace.path
        trace.clear()
        guard interactive, !path.isEmpty else { return }
        let word = BoggleRules.word(path, grid: grid)
        if word.count < Rules.minLength {
            note = "Words need at least \(Rules.minLength) letters."
            refuse()
            return
        }
        if view.mine?.contains(where: { $0.word == word }) == true {
            note = "You already have that one."
            refuse()
            return
        }
        SRHaptic.tap()
        note = nil
        context.send(.word(path: path))
    }

    private func refuse() {
        SRHaptic.bad()
        shakes += 1
    }

    // MARK: - The board

    /// The path drawn on the board: my trace while playing, the lit word after.
    private var path: [Int] {
        if interactive { return trace.path }
        guard let lit else { return [] }
        if let found = view.found?.first(where: { $0.word == lit }) { return found.path }
        if let missed = view.missed?.first(where: { $0.word == lit }) { return missed.path }
        return view.mine?.first { $0.word == lit }?.path ?? []
    }

    private func board(_ grid: [String]) -> some View {
        GeometryReader { geo in
            let side = BoggleRules.tileSide(width: geo.size.width - 24, size: Rules.size, gap: Self.gap)
            let boardSide = side * CGFloat(Rules.size) + Self.gap * CGFloat(Rules.size - 1)
            OfflineBoggleTray(cornerRadius: 22) {
                dice(grid, side: side)
                    .frame(width: boardSide, height: boardSide)
                    .padding(12)
            }
            .frame(maxWidth: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-boggle-board")
    }

    private func dice(_ grid: [String], side: CGFloat) -> some View {
        let n = Rules.size
        return ZStack(alignment: .topLeading) {
            ForEach(0..<(n * n), id: \.self) { tile in
                die(tile, face: tile < grid.count ? grid[tile] : "", side: side)
                    .position(centre(of: tile, side: side))
            }
            traceLine(side: side)
                .allowsHitTesting(false)
        }
        .srAnimation(.spring(response: 0.45, dampingFraction: 0.8), value: turns)
        .contentShape(Rectangle())
        .highPriorityGesture(drag(side: side), including: interactive ? .all : .subviews)
    }

    /// Where a die sits now: its place after this phone's quarter turns.
    private func centre(of tile: Int, side: CGFloat) -> CGPoint {
        let shown = BoggleRules.displayed(tile, size: Rules.size, turns: turns)
        let (row, column) = BoggleRules.cell(shown, size: Rules.size)
        let pitch = side + Self.gap
        return CGPoint(x: CGFloat(column) * pitch + side / 2, y: CGFloat(row) * pitch + side / 2)
    }

    /// The die under a point, by what is drawn there.
    private func tile(at point: CGPoint, side: CGFloat, reach: CGFloat = 0.42) -> Int? {
        guard let shown = BoggleRules.tile(at: point, size: Rules.size, side: side, gap: Self.gap, reach: reach) else {
            return nil
        }
        return BoggleRules.tile(atDisplay: shown, size: Rules.size, turns: turns)
    }

    /// The trace, as a glowing line through the centres of its dice, with a
    /// bead on each die it passes.
    private func traceLine(side: CGFloat) -> some View {
        let points = path.map { centre(of: $0, side: side) }
        let tone = interactive ? Color(hex: 0xB79BFF) : Color(hex: 0x6FE3DF)
        let width = max(8, side * 0.2)
        let line = Path { line in
            guard let first = points.first else { return }
            line.move(to: first)
            for point in points.dropFirst() { line.addLine(to: point) }
        }
        return ZStack {
            line.stroke(tone.opacity(0.35), style: StrokeStyle(lineWidth: width * 1.9, lineCap: .round, lineJoin: .round))
            line.stroke(tone.opacity(0.85), style: StrokeStyle(lineWidth: width * 0.7, lineCap: .round, lineJoin: .round))
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: width * 0.6, height: width * 0.6)
                    .position(point)
            }
        }
    }

    private func die(_ tile: Int, face: String, side: CGFloat) -> some View {
        let at = path.firstIndex(of: tile)
        let isLit = at != nil
        let last = interactive && tile == path.last
        let text = BoggleRules.display(face)
        let state: PlayTableTileState = isLit ? (interactive ? (last ? .tracedLast : .traced) : .shown) : .ready
        return OfflineBoggleDieRoll(index: tile) {
            PlayTableLetterTile(letter: text, side: side * 0.93, state: state, die: true)
        }
        .frame(width: side, height: side)
        .srAnimation(.snappy(duration: 0.12), value: state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(at.map { "\(text), letter \($0 + 1) of your word" } ?? text)
        .accessibilityAddTraits(interactive ? .isButton : [])
        .accessibilityAddTraits(isLit ? .isSelected : [])
        .accessibilityAction {
            if interactive {
                note = nil
                trace.tap(tile)
            }
        }
        .accessibilityIdentifier("offline-boggle-tile-\(tile)")
    }

    private func drag(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard interactive else { return }
                if touchStart == nil {
                    // The first touch must land on a die; a wider reach, so a
                    // fingertip on its edge still counts.
                    touchStart = tile(at: value.startLocation, side: side, reach: 0.72)
                }
                guard let start = touchStart,
                      let tile = tile(at: value.location, side: side),
                      tile != start || dragging else { return }
                if !dragging {
                    dragging = true
                    note = nil
                    // Carry on from a word built by taps if this drag began on
                    // its last die; otherwise the drag is a new word.
                    if trace.last != start {
                        trace.clear()
                        trace.drag(to: start)
                    }
                }
                if trace.drag(to: tile) { SRHaptic.select() }
            }
            .onEnded { _ in
                defer {
                    touchStart = nil
                    dragging = false
                }
                guard interactive, let start = touchStart else { return }
                if dragging {
                    submit()
                } else {
                    note = nil
                    trace.tap(start)
                    SRHaptic.select()
                }
            }
    }

    // MARK: - My words while playing

    private func myWords(_ mine: [Rules.Word]) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Your words", trailing: "\(mine.count)")
            OfflineWordChips(chips: mine.map {
                OfflineWordChip(id: $0.word, text: $0.word.uppercased(), points: $0.points,
                                spoken: "\($0.word), \($0.points) \($0.points == 1 ? "point" : "points")")
            })
            .accessibilityIdentifier("offline-boggle-mine")
        }
    }

    // MARK: - The reveal

    private var boardLine: String {
        let found = view.found?.count ?? 0
        let who = view.board.count == 1 ? "You" : "Between you, you"
        let tail = lit == nil ? "Tap a word to see it on the board." : "Tap it again to clear."
        guard view.possibleWords > 0 else { return tail }
        return "\(who) found \(found) of \(view.possibleWords) words on this board. \(tail)"
    }

    @ViewBuilder
    private var reveal: some View {
        if let found = view.found, !found.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Every word found", trailing: "\(found.count)")
                OfflineWordChips(chips: found.map { word in
                    OfflineWordChip(id: word.word, text: word.word.uppercased(), points: word.points,
                                    crossed: word.crossed, lit: lit == word.word,
                                    spoken: spoken(word))
                }, pick: pick)
                .accessibilityIdentifier("offline-boggle-found")
            }
        } else {
            Text("Nobody found a word this time.")
                .font(SR.Text.body())
                .foregroundStyle(SR.inkSecondary)
        }
        if let missed = view.missed, !missed.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Nobody found")
                OfflineWordChips(chips: missed.map { word in
                    OfflineWordChip(id: word.word, text: word.word.uppercased(), points: word.points, lit: lit == word.word,
                                    spoken: "\(word.word), \(word.points) points, nobody found it")
                }, pick: pick)
                .accessibilityIdentifier("offline-boggle-missed")
            }
        }
        if view.mine != nil, view.phase == .reveal {
            OfflineWordContinue(ready: view.board.first { $0.id == context.me }?.ready ?? false,
                                waitingOn: view.board.filter { !$0.ready && !$0.away && $0.id != context.me }.map(\.name),
                                id: "offline-boggle-continue") {
                context.send(.ready)
            }
        }
    }

    private func pick(_ word: String) {
        SRHaptic.select()
        lit = lit == word ? nil : word
    }

    private func spoken(_ word: Rules.Reveal) -> String {
        let names = word.finders.map { $0 == context.me ? "you" : context.name(of: $0) }
        let crossed = word.crossed ? ", shared, crossed out" : ""
        return "\(word.word), found by \(names.joined(separator: " and "))\(crossed), \(word.points) points"
    }

    // MARK: - Scores

    private var rows: [OfflineWordScoreRow] {
        view.board.map { row in
            OfflineWordScoreRow(id: row.id, name: row.name, detail: row.words == 1 ? "1 word" : "\(row.words) words",
                                score: row.score, away: row.away, ready: revealed && row.ready)
        }
    }
}

/// The plastic tray the dice sit in: a deep violet moulding with a lighter
/// rim and a shadow inside, so the dice look sunk into it.
struct OfflineBoggleTray<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                ZStack {
                    shape.fill(LinearGradient(colors: [Color(hex: 0x4A2FA8), Color(hex: 0x25145E)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                    shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 2)
                    shape.inset(by: 6).stroke(Color.black.opacity(0.25), lineWidth: 4)
                }
                .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
            )
    }
}

/// A die tumbling into the tray the first time the board is shown: a short,
/// staggered drop and turn, once. Under Reduce Motion it is simply there.
struct OfflineBoggleDieRoll<Content: View>: View {
    let index: Int
    let content: Content
    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(index: Int, @ViewBuilder content: () -> Content) {
        self.index = index
        self.content = content()
    }

    var body: some View {
        let down = settled || reduceMotion
        return content
            .scaleEffect(down ? 1 : 0.45)
            .rotationEffect(.degrees(down ? 0 : PlayTableMath.tilt(index, range: 40)))
            .opacity(down ? 1 : 0)
            .onAppear {
                guard !reduceMotion, !settled else { return }
                let delay = PlayTableMath.stagger(index: index, step: 0.035, cap: 0.6)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.62).delay(delay)) { settled = true }
            }
    }
}
