import SwiftUI

// MARK: - The start card

/// Before a game: how to play, which field, no-guessing, and the bests.
struct MinesweeperIntroView: View {
    @ObservedObject var game: MinesweeperGame

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                picker
                if game.setup.level == .custom { customCard }
                noGuessCard
                stats
                startButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("minesweeper-intro")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            MinesweeperIntroArt()
                .frame(height: 124)
                .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("MINESWEEPER")
                    .font(SR.Text.label())
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(SR.accent)
                Text("Clear the field without digging up a mine.")
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 10) {
                MinesweeperHowRow(icon: "hand.tap.fill", text: "Tap a square to dig. Your first dig is always safe.")
                MinesweeperHowRow(icon: "number", text: "A number says how many mines touch that square, corners included.")
                MinesweeperHowRow(icon: "flag.fill", text: "Hold a square, or switch to Flag, to plant a flag where a mine must be.",
                                  tint: Color(hex: 0xD32F2F))
                MinesweeperHowRow(icon: "bolt.fill", text: "Tap a number with all its flags in place to dig round it in one go.")
                MinesweeperHowRow(icon: "arrow.up.left.and.arrow.down.right",
                                  text: "On a big field, pinch to zoom and drag to look around.")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FIELD")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.inkMuted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(MinesweeperLevel.allCases) { level in
                    levelButton(level)
                }
            }
        }
    }

    private func setup(for level: MinesweeperLevel) -> MinesweeperSetup {
        var s = game.setup
        s.level = level
        return s
    }

    private func levelButton(_ level: MinesweeperLevel) -> some View {
        let s = setup(for: level)
        let selected = game.setup.level == level
        let best = game.records.best(s.recordKey)
        let shape = RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
        return Button {
            SRHaptic.select()
            game.changeSetup { $0.level = level }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: level.icon)
                    Spacer(minLength: 4)
                    if selected { Image(systemName: "checkmark.circle.fill") }
                }
                .font(SR.Text.title(16))
                .foregroundStyle(selected ? SR.accent : SR.inkMuted)
                Text(level.title)
                    .font(SR.Text.title(17))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(s.width) × \(s.height) · \(s.mines) mines")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(best.map { "Best \(MinesweeperFormat.precise($0))" } ?? "No best yet")
                    .font(SR.Text.mono())
                    .foregroundStyle(best == nil ? SR.inkMuted : SR.good)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(12)
            .background(shape.fill(selected ? SR.accent.opacity(0.14) : SR.ink.opacity(0.05)))
            .overlay(shape.stroke(selected ? SR.accent : SR.line, lineWidth: selected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(levelSpoken(level, setup: s, best: best))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("minesweeper-level-\(level.rawValue)")
    }

    private func levelSpoken(_ level: MinesweeperLevel, setup s: MinesweeperSetup, best: Double?) -> String {
        let base: String = "\(level.title), \(s.width) by \(s.height), \(s.mines) mines"
        guard let best else { return base }
        return base + ", best " + MinesweeperFormat.spoken(best)
    }

    // MARK: Custom

    private var widthBinding: Binding<Int> {
        Binding(get: { game.setup.customWidth }, set: { value in game.changeSetup { $0.customWidth = value } })
    }

    private var heightBinding: Binding<Int> {
        Binding(get: { game.setup.customHeight }, set: { value in game.changeSetup { $0.customHeight = value } })
    }

    private var minesBinding: Binding<Int> {
        Binding(get: { game.setup.customMines }, set: { value in game.changeSetup { $0.customMines = value } })
    }

    private var customCard: some View {
        let s = game.setup
        let most = MinesweeperSetup.mostMines(width: s.width, height: s.height)
        return VStack(alignment: .leading, spacing: 12) {
            Text("YOUR OWN FIELD")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Stepper(value: widthBinding, in: MinesweeperSetup.sides) {
                stepperLabel("Across", "\(s.width) squares")
            }
            .accessibilityIdentifier("minesweeper-custom-width")
            Stepper(value: heightBinding, in: MinesweeperSetup.sides) {
                stepperLabel("Down", "\(s.height) squares")
            }
            .accessibilityIdentifier("minesweeper-custom-height")
            Stepper(value: minesBinding, in: 1...most) {
                stepperLabel("Mines", "\(s.mines) of \(most)")
            }
            .accessibilityIdentifier("minesweeper-custom-mines")
            HStack(spacing: 8) {
                densityButton("Light", 0.10)
                densityButton("Medium", 0.15)
                densityButton("Heavy", 0.21)
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private func stepperLabel(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(SR.Text.title(16))
                .foregroundStyle(SR.ink)
            Text(value)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkSecondary)
        }
    }

    private func densityButton(_ title: String, _ share: Double) -> some View {
        let s = game.setup
        let mines = max(1, Int((Double(s.width * s.height) * share).rounded()))
        let on = s.mines == min(mines, MinesweeperSetup.mostMines(width: s.width, height: s.height))
        return Button {
            SRHaptic.select()
            game.changeSetup { $0.customMines = mines }
        } label: {
            Text(title)
                .font(SR.Text.title(15))
                .foregroundStyle(on ? SR.paper : SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Capsule().fill(on ? SR.accentDeep : SR.ink.opacity(0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel("\(title): \(mines) mines")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: No guessing

    private var noGuessBinding: Binding<Bool> {
        Binding(get: { game.setup.noGuess }, set: { value in game.changeSetup { $0.noGuess = value } })
    }

    private var noGuessCard: some View {
        Toggle(isOn: noGuessBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("No guessing")
                    .font(SR.Text.title(17))
                    .foregroundStyle(SR.ink)
                Text("Every field can be cleared by thinking, from the first dig. No coin tosses at the end.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(SR.accent)
        .padding(SR.cardPadding)
        .frame(minHeight: 64)
        .srGlassCard(.paper)
        .accessibilityIdentifier("minesweeper-no-guess")
    }

    // MARK: Bests and start

    @ViewBuilder
    private var stats: some View {
        let key = game.setup.recordKey
        let played = game.records.playedCount(key)
        if played > 0 {
            HStack(spacing: 8) {
                MinesweeperStatChip(label: "BEST", value: game.records.best(key).map { MinesweeperFormat.precise($0) } ?? "–")
                MinesweeperStatChip(label: "WON", value: "\(game.records.wonCount(key)) of \(played)")
                MinesweeperStatChip(label: "BEST RUN", value: "\(game.records.bestStreakCount(key))")
            }
        }
    }

    private var startButton: some View {
        Button {
            SRHaptic.tap()
            game.begin()
        } label: {
            SRButtonLabel(title: "Start digging", icon: "flag.fill", fill: true)
                .frame(minHeight: 48)
        }
        .srButton(.prominent)
        .controlSize(.large)
        .accessibilityIdentifier("minesweeper-start")
    }
}

// MARK: - Paused

struct MinesweeperPausedCard: View {
    @ObservedObject var game: MinesweeperGame

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PAUSED")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text("\(game.setup.level.title) · \(game.board.width) × \(game.board.height)")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("The field is covered while the clock is stopped. \(game.board.minesLeft) mines left to find.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                SRHaptic.tap()
                game.resume()
            } label: {
                SRButtonLabel(title: "Resume", icon: "play.fill", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("minesweeper-resume")
            HStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    game.restart()
                } label: {
                    SRButtonLabel(title: "New field", icon: "arrow.counterclockwise", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("minesweeper-restart")
                Button {
                    SRHaptic.tap()
                    game.toIntro()
                } label: {
                    SRButtonLabel(title: "Change", icon: "square.grid.3x3", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("minesweeper-change")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("minesweeper-paused")
    }
}

// MARK: - The end

/// Won or lost: the time, the bests, and the way back in.
struct MinesweeperResultCard: View {
    @ObservedObject var game: MinesweeperGame
    let onTuck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if game.stage == .won { wonBody } else { lostBody }
            chips
            buttons
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier(game.stage == .won ? "minesweeper-won" : "minesweeper-lost")
    }

    private var won: Bool { game.stage == .won }
    private var newBest: Bool { won && game.place == 1 }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: newBest ? "trophy.fill" : (won ? "checkmark.seal.fill" : "burst.fill"))
                .font(SR.Text.title(18))
                .accessibilityHidden(true)
            Text(newBest ? "NEW BEST" : (won ? "FIELD CLEARED" : "BOOM"))
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
            Spacer(minLength: 8)
            Button {
                SRHaptic.tap()
                onTuck()
            } label: {
                Image(systemName: "chevron.down")
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.inkSecondary)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(SR.ink.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(SRPressStyle())
            .accessibilityLabel("Hide this card to look at the field")
            .accessibilityIdentifier("minesweeper-tuck")
        }
        .foregroundStyle(won ? SR.good : SR.error)
    }

    private var wonBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(MinesweeperFormat.precise(game.finalTime))
                .font(SR.Text.hero(40))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
                .accessibilityLabel(MinesweeperFormat.spoken(game.finalTime))
            Text(wonLine)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            topFive
        }
    }

    private var fieldName: String {
        game.setup.level == .custom ? "this size of field" : game.setup.level.title
    }

    private var wonLine: String {
        let logic = game.logicalField ? " Solved on logic alone." : ""
        switch game.place {
        case 1?:
            return game.records.top(game.playingKey).count == 1
                ? "Your first clear on \(fieldName). Now beat it.\(logic)"
                : "Your fastest ever on \(fieldName).\(logic)"
        case let place?:
            return "Your \(Self.ordinal(place)) fastest on \(fieldName).\(logic)"
        case nil:
            let best = game.bestForGame.map { MinesweeperFormat.precise($0) } ?? "–"
            return "Not in your top five this time. Your best is \(best).\(logic)"
        }
    }

    static func ordinal(_ n: Int) -> String {
        switch n {
        case 2: return "second"
        case 3: return "third"
        case 4: return "fourth"
        case 5: return "fifth"
        default: return "\(n)th"
        }
    }

    @ViewBuilder
    private var topFive: some View {
        let times = game.records.top(game.playingKey)
        if times.count > 1 {
            HStack(spacing: 6) {
                ForEach(Array(times.enumerated()), id: \.offset) { pair in
                    topTime(rank: pair.offset + 1, time: pair.element, mine: game.place == pair.offset + 1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Top times: " + times.map { MinesweeperFormat.precise($0) }.joined(separator: ", "))
        }
    }

    private func topTime(rank: Int, time: Double, mine: Bool) -> some View {
        VStack(spacing: 1) {
            Text("\(rank)")
                .font(SR.Text.label())
                .foregroundStyle(mine ? SR.paper : SR.inkMuted)
            Text(MinesweeperFormat.precise(time))
                .font(SR.Text.mono())
                .foregroundStyle(mine ? SR.paper : SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(mine ? SR.accentDeep : SR.ink.opacity(0.06)))
    }

    private var lostBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You dug up a mine.")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(lostLine)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(tip)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lostLine: String {
        let share = Int((game.cleared * 100).rounded(.down))
        return "You'd cleared \(share)% of the field in \(MinesweeperFormat.clock(game.finalTime))."
    }

    private static let tips = [
        "Look for a 1 touching just one covered square: that square is a mine.",
        "When a number already has all its flags, every other square round it is safe.",
        "A 1-2-1 along a wall means mines under the ones and none under the two.",
        "Turn on No guessing and every field can be solved without luck.",
        "Flag the mines you are sure of, then tap the number to clear round it.",
        "Start a new game by tapping the face at the top.",
    ]

    private var tip: String {
        let seed = game.board.exploded ?? 0
        return "Tip: " + Self.tips[seed % Self.tips.count]
    }

    private var chips: some View {
        let key = game.playingKey
        return HStack(spacing: 8) {
            MinesweeperStatChip(label: "BEST", value: game.records.best(key).map { MinesweeperFormat.precise($0) } ?? "–")
            MinesweeperStatChip(label: "WON", value: "\(game.records.wonCount(key)) of \(game.records.playedCount(key))")
            MinesweeperStatChip(label: won ? "STREAK" : "BEST RUN",
                                value: "\(won ? game.records.streakCount(key) : game.records.bestStreakCount(key))")
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button {
                SRHaptic.tap()
                game.toIntro()
            } label: {
                SRButtonLabel(title: "Change", icon: "square.grid.3x3", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("minesweeper-change")
            Button {
                SRHaptic.tap()
                game.restart()
            } label: {
                SRButtonLabel(title: "Play again", icon: "arrow.counterclockwise", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("minesweeper-again")
        }
    }
}
