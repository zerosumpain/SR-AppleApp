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
/// tile maths), so a finger behaves the same on both boards.
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

    private typealias Rules = OfflineBoggleRules
    private static let gap: CGFloat = 6

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
                    } else if revealed {
                        Text(boardLine)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("offline-boggle-possible")
                    }
                } else {
                    Text("The dice are rolling. Get ready to trace.")
                        .font(SR.Text.body())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if revealed {
                    reveal
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
            if new != nil { SRHaptic.bad() }
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

    // MARK: - The word being traced

    private func wordRow(_ grid: [String]) -> some View {
        let word = BoggleRules.word(trace.path, grid: grid)
        let had = view.mine?.contains { $0.word == word } ?? false
        return VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(word.isEmpty ? " " : word.uppercased())
                    .font(SR.Text.hero(34))
                    .tracking(3)
                    .foregroundStyle(had ? SR.inkGhost : SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                if word.count >= Rules.minLength && !had {
                    Text("+\(Rules.points(word))")
                        .font(SR.Text.figure(20))
                        .foregroundStyle(SR.accent)
                } else if had {
                    Text("HAVE IT")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            Rectangle().fill(SR.line).frame(height: 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word.isEmpty ? "Your word, empty" : "Your word, \(word)")
        .accessibilityIdentifier("offline-boggle-word")
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                trace.delete()
                SRHaptic.select()
            } label: {
                SRButtonLabel(title: "Delete", icon: "delete.left", fill: true)
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(trace.isEmpty)
            .accessibilityIdentifier("offline-boggle-delete")
            Button {
                submit()
            } label: {
                SRButtonLabel(title: "Enter", icon: "return", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
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
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.good)
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
            SRHaptic.bad()
            return
        }
        if view.mine?.contains(where: { $0.word == word }) == true {
            note = "You already have that one."
            SRHaptic.bad()
            return
        }
        note = nil
        context.send(.word(path: path))
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
            let side = BoggleRules.tileSide(width: geo.size.width - 12, size: Rules.size, gap: Self.gap)
            let boardSide = side * CGFloat(Rules.size) + Self.gap * CGFloat(Rules.size - 1)
            dice(grid, side: side)
                .frame(width: boardSide, height: boardSide)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(SR.accentDeep)
                        .shadow(color: SR.ink.opacity(0.18), radius: 8, y: 4)
                )
                .frame(maxWidth: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-boggle-board")
    }

    private func dice(_ grid: [String], side: CGFloat) -> some View {
        let n = Rules.size
        return ZStack(alignment: .topLeading) {
            VStack(spacing: Self.gap) {
                ForEach(0..<n, id: \.self) { row in
                    HStack(spacing: Self.gap) {
                        ForEach(0..<n, id: \.self) { column in
                            let tile = row * n + column
                            die(tile, face: tile < grid.count ? grid[tile] : "", side: side)
                        }
                    }
                }
            }
            traceLine(side: side)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(drag(side: side), including: interactive ? .all : .subviews)
    }

    private func centre(of tile: Int, side: CGFloat) -> CGPoint {
        let (row, column) = BoggleRules.cell(tile, size: Rules.size)
        let pitch = side + Self.gap
        return CGPoint(x: CGFloat(column) * pitch + side / 2, y: CGFloat(row) * pitch + side / 2)
    }

    /// The trace, as one line through the centres of its dice.
    private func traceLine(side: CGFloat) -> some View {
        let points = path.map { centre(of: $0, side: side) }
        return Path { line in
            guard let first = points.first else { return }
            line.move(to: first)
            for point in points.dropFirst() { line.addLine(to: point) }
        }
        .stroke(interactive ? SR.accent.opacity(0.55) : SR.accentInk.opacity(0.6),
                style: StrokeStyle(lineWidth: max(8, side * 0.22), lineCap: .round, lineJoin: .round))
    }

    private func die(_ tile: Int, face: String, side: CGFloat) -> some View {
        let at = path.firstIndex(of: tile)
        let isLit = at != nil
        let last = interactive && tile == path.last
        let text = BoggleRules.display(face)
        return ZStack {
            RoundedRectangle(cornerRadius: side * 0.2, style: .continuous)
                .fill(isLit ? (interactive ? SR.accent : SR.accentInk) : SR.paper)
                .shadow(color: SR.ink.opacity(isLit ? 0 : 0.22), radius: 0, x: 0, y: 2)
            RoundedRectangle(cornerRadius: side * 0.2, style: .continuous)
                .strokeBorder(last ? SR.paper : SR.ink.opacity(0.08), lineWidth: last ? 3 : 1)
            Text(text.isEmpty ? " " : text)
                .font(SR.Text.display(text.count > 1 ? side * 0.4 : side * 0.52))
                .foregroundStyle(isLit ? SR.paper : SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 3)
        }
        .frame(width: side, height: side)
        .scaleEffect(last ? 1.06 : 1)
        .animation(.snappy(duration: 0.12), value: last)
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
                    touchStart = BoggleRules.tile(at: value.startLocation, size: Rules.size, side: side,
                                                  gap: Self.gap, reach: 0.72)
                }
                guard let start = touchStart,
                      let tile = BoggleRules.tile(at: value.location, size: Rules.size, side: side, gap: Self.gap),
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
