import SwiftUI

// The cards between games: how to play and the board picker, the pause, the
// win and the end. Each reads the session and calls back into it; none of
// them keeps state of its own.

/// A card's button: a big, full-width capsule (56pt or more with its insets).
struct Merge2048CardButton: View {
    let title: String
    let icon: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        if prominent {
            button.srButton(.prominent)
        } else {
            button.srButton(.regular)
        }
    }

    private var button: some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            // 44 plus the large control's insets keeps every card button at
            // 56pt or taller, on the capsule style and on iOS 26's glass.
            SRButtonLabel(title: title, icon: icon, fill: true)
                .frame(minHeight: 44)
        }
        .controlSize(.large)
    }
}

/// Centres a card in the space it is given, and scrolls it when the text is
/// set large enough that it no longer fits.
struct Merge2048CardHost<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// A card's eyebrow.
struct Merge2048Kicker: View {
    let text: String
    var tone: Color = SR.accent

    var body: some View {
        Text(text.uppercased())
            .font(SR.Text.label())
            .tracking(SR.inkKickerTracking)
            .foregroundStyle(tone)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A bullet line of how-to-play.
struct Merge2048Rule: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(SR.accent)
        }
    }
}

// MARK: - Intro

struct Merge2048IntroCard: View {
    @ObservedObject var session: Merge2048Session

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            rules
            SRSectionLabel(text: "Board")
            Merge2048SizePicker(selected: session.size, book: session.book, saved: session.saved) { option in
                withAnimation(.snappy) { session.choose(option) }
            }
            Text(session.size.line)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Merge2048Milestones(target: session.size.target, biggest: session.record.biggestTile)
            Text(statsLine)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            buttons
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("merge-2048-intro")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Merge2048Kicker(text: "2048")
            Text("Slide. Merge. Make \(String(session.size.target)).")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 6) {
            Merge2048Rule(text: "Swipe the board, or press the arrows, to slide every tile at once.")
            Merge2048Rule(text: "Two tiles with the same number merge into one worth double. Each merge adds to your score.")
            Merge2048Rule(text: "A new 2 or 4 appears after every move. When no move is left, the game ends.")
            Merge2048Rule(text: "Undo takes back your last move. Tip: keep your biggest tile in a corner.")
        }
    }

    private var statsLine: String {
        let record = session.record
        guard record.games > 0 || record.bestScore > 0 else { return "No games yet on this board. Your bests are kept on this phone." }
        let played = record.games == 1 ? "1 game" : "\(record.games) games"
        let won = record.wins == 1 ? "1 win" : "\(record.wins) wins"
        return "\(played) · \(won) · best \(record.bestScore.formatted()) · biggest tile \(record.biggestTile.formatted())"
    }

    @ViewBuilder
    private var buttons: some View {
        if session.hasSavedGame {
            Merge2048CardButton(title: "Carry on", icon: "play.fill", prominent: true) {
                withAnimation(.snappy) { session.play() }
            }
            .accessibilityIdentifier("merge-2048-continue")
            Merge2048CardButton(title: "New game", icon: "arrow.counterclockwise") {
                withAnimation(.snappy) { session.newGame() }
            }
            .accessibilityIdentifier("merge-2048-new")
        } else {
            Merge2048CardButton(title: "Play", icon: "play.fill", prominent: true) {
                withAnimation(.snappy) { session.play() }
            }
            .accessibilityIdentifier("merge-2048-start")
        }
    }
}

/// The three boards, side by side (stacked when the text is large), each with
/// its best and whether a game is waiting on it.
struct Merge2048SizePicker: View {
    let selected: Merge2048Size
    let book: Merge2048Book
    let saved: Set<Merge2048Size>
    let pick: (Merge2048Size) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { options }
            VStack(spacing: 8) { options }
        }
    }

    private var options: some View {
        ForEach(Merge2048Size.allCases) { option in
            choice(option)
        }
    }

    private func choice(_ option: Merge2048Size) -> some View {
        let on = option == selected
        let best = book.record(option).bestScore
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button {
            SRHaptic.select()
            pick(option)
        } label: {
            VStack(spacing: 4) {
                Merge2048GridGlyph(side: option.side, tint: on ? SR.accent : SR.inkMuted)
                Text(option.dimension)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                Text(option.title.uppercased())
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(on ? SR.accent : SR.inkMuted)
                    .lineLimit(1)
                Text(caption(option, best: best))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(shape.fill(on ? SR.accent.opacity(0.14) : Color.clear))
            .overlay(shape.strokeBorder(on ? SR.accent : SR.line, lineWidth: on ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(accessibility(option, best: best))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("merge-2048-size-\(option.side)")
    }

    private func caption(_ option: Merge2048Size, best: Int) -> String {
        if saved.contains(option) { return "In play" }
        return best > 0 ? "Best \(best.formatted())" : "New"
    }

    private func accessibility(_ option: Merge2048Size, best: Int) -> String {
        var words = "\(option.title), \(option.side) by \(option.side)"
        if best > 0 { words += ", best \(best)" }
        if saved.contains(option) { words += ", game in play" }
        return words
    }
}

/// A board's shape in miniature.
struct Merge2048GridGlyph: View {
    let side: Int
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 2
            let n = CGFloat(max(side, 1))
            let cell = (size.width - gap * (n - 1)) / n
            for r in 0..<side {
                for c in 0..<side {
                    let rect = CGRect(x: CGFloat(c) * (cell + gap), y: CGFloat(r) * (cell + gap), width: cell, height: cell)
                    let shade: Double = (r + c) % 2 == 0 ? 0.9 : 0.5
                    context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.28), with: .color(tint.opacity(shade)))
                }
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

/// The tiles worth making on a board, lit up to the biggest made so far.
struct Merge2048Milestones: View {
    let target: Int
    let biggest: Int

    var body: some View {
        let steps = Merge2048Ladder.milestones(target: target)
        HStack(spacing: 6) {
            ForEach(steps, id: \.self) { value in
                chip(value)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(steps))
    }

    private func chip(_ value: Int) -> some View {
        let made = biggest >= value
        return Merge2048TileFace(value: value, cell: 36)
            .frame(width: 36, height: 36)
            .saturation(made ? 1 : 0)
            .opacity(made ? 1 : 0.32)
    }

    private func label(_ steps: [Int]) -> String {
        guard let next = steps.first(where: { $0 > biggest }) else { return "Every milestone made, up to \(steps.last ?? target)." }
        let names: [String] = steps.map { String($0) }
        if biggest < (steps.first ?? 0) { return "Milestones: \(names.joined(separator: ", ")). Next: \(next)." }
        return "Biggest tile \(biggest). Next milestone: \(next)."
    }
}

// MARK: - Pause

struct Merge2048PausedCard: View {
    @ObservedObject var session: Merge2048Session

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Merge2048Kicker(text: "Paused")
            Text("Your board will wait.")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(line)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Merge2048CardButton(title: "Resume", icon: "play.fill", prominent: true) {
                withAnimation(.snappy) { session.resume() }
            }
            .accessibilityIdentifier("merge-2048-resume")
            Merge2048CardButton(title: "New game", icon: "arrow.counterclockwise") {
                withAnimation(.snappy) { session.newGame() }
            }
            .accessibilityIdentifier("merge-2048-paused-new")
            Merge2048CardButton(title: "Change board", icon: "square.grid.3x3") {
                withAnimation(.snappy) { session.changeBoard() }
            }
            .accessibilityIdentifier("merge-2048-paused-board")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("merge-2048-paused")
    }

    private var line: String {
        let state = session.state
        let moves = state.moves == 1 ? "1 move" : "\(state.moves) moves"
        return "Score \(state.score.formatted()), biggest tile \(state.biggest), \(moves). It is saved on this phone, so you can come back to it any time."
    }
}

// MARK: - Win

struct Merge2048WonCard: View {
    @ObservedObject var session: Merge2048Session

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Merge2048TileFace(value: session.state.target, cell: 76)
                    .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Merge2048Kicker(text: "You made \(String(session.state.target))", tone: SR.good)
                    Text("Brilliant!")
                        .font(SR.Text.display(24))
                        .foregroundStyle(SR.ink)
                }
            }
            Text(line)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Merge2048CardButton(title: session.state.isOver ? "See your score" : "Keep going",
                                icon: "arrow.right", prominent: true) {
                withAnimation(.snappy) { session.keepGoing() }
            }
            .accessibilityIdentifier("merge-2048-keep-going")
            Merge2048CardButton(title: "New game", icon: "arrow.counterclockwise") {
                withAnimation(.snappy) { session.newGame() }
            }
            .accessibilityIdentifier("merge-2048-won-new")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("merge-2048-won")
    }

    private var line: String {
        let state = session.state
        let score = "Score \(state.score.formatted()) in \(state.moves) moves."
        if state.isOver {
            return "\(score) That was the last move the board had room for, so this game is finished."
        }
        return "\(score) Keep going for \(String(state.target * 2)) on this board, or start a fresh one."
    }
}

// MARK: - Game over

struct Merge2048OverCard: View {
    @ObservedObject var session: Merge2048Session

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Merge2048Kicker(text: session.newBest ? "New best" : "No moves left",
                            tone: session.newBest ? SR.good : SR.error)
            Text(session.state.score.formatted())
                .font(SR.Text.figure(40))
                .foregroundStyle(SR.ink)
                .accessibilityLabel("Score \(session.state.score)")
            Text(line)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Merge2048CardButton(title: "Play again", icon: "arrow.counterclockwise", prominent: true) {
                withAnimation(.snappy) { session.newGame() }
            }
            .accessibilityIdentifier("merge-2048-again")
            if session.canUndo {
                Merge2048CardButton(title: "Undo last move", icon: "arrow.uturn.backward") {
                    withAnimation(.easeOut(duration: Merge2048Motion.slide)) { session.undo() }
                }
                .accessibilityIdentifier("merge-2048-over-undo")
            }
            Merge2048CardButton(title: "Change board", icon: "square.grid.3x3") {
                withAnimation(.snappy) { session.changeBoard() }
            }
            .accessibilityIdentifier("merge-2048-over-board")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("merge-2048-over")
    }

    private var line: String {
        let state = session.state
        let moves = state.moves == 1 ? "1 move" : "\(state.moves) moves"
        let size = session.size
        return "Biggest tile \(state.biggest) after \(moves). Best on \(size.title) \(size.dimension): \(session.best.formatted())."
    }
}
