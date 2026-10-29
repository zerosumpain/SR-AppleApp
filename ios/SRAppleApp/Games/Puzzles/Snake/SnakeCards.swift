import SwiftUI

/// Before a game: how to play, the mode (and maze), the snake's colour and
/// the big-arrows setting, then Play.
struct SnakeIntroCard: View {
    @ObservedObject var session: SnakeSession
    let dark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SnakeCardHolder {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    howTo
                    modes
                    if session.mode == .maze { mazes }
                    skins
                    padToggle
                }
            }
            playButton
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("snake-intro")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SNAKE")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text("Eat the apples. Don't bite your tail.")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 10) {
            SnakeHowRow(icon: "hand.draw.fill",
                        text: session.records.pad
                            ? "Press the arrows, or swipe anywhere, to turn. Two quick turns make a U-turn."
                            : "Swipe anywhere to turn. Two quick swipes make a U-turn.")
            SnakeHowRow(icon: "circle.fill",
                        text: "Each apple scores \(SnakeRules.applePoints), makes you one longer and a little faster.",
                        tint: SnakeInk.apple)
            SnakeHowRow(icon: "star.fill",
                        text: "Catch a golden apple before it fades for \(SnakeRules.goldenPoints).",
                        tint: SnakeInk.goldDeep)
        }
    }

    private var modes: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(SnakeMode.allCases) { mode in
                    SnakeModeTile(mode: mode, selected: session.mode == mode) {
                        session.choose(mode)
                    }
                }
            }
            Text(modeLine)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeLine: String {
        let best = session.best
        let line = session.mode == .maze ? session.records.maze.line : session.mode.line
        return best > 0 ? "\(line) Best: \(best)." : line
    }

    private var mazes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SnakeMaze.all) { maze in
                    SnakeMazeChip(maze: maze, open: session.records.isUnlocked(maze),
                                  selected: session.records.maze.id == maze.id,
                                  best: session.records.best(mode: .maze, maze: maze).score, dark: dark) {
                        session.choose(maze: maze)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var skins: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COLOUR")
                .font(SR.Text.label())
                .tracking(SR.inkLabelTracking)
                .foregroundStyle(SR.inkMuted)
            HStack(spacing: 4) {
                ForEach(SnakeSkin.allCases) { skin in
                    SnakeSkinSwatch(skin: skin, open: session.records.isUnlocked(skin),
                                    selected: session.skin == skin) {
                        session.choose(skin: skin)
                    }
                }
            }
            Text(skinLine)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var skinLine: String {
        let apples = session.records.apples
        let eaten = apples == 1 ? "1 apple eaten" : "\(apples) apples eaten"
        guard let next = session.records.nextSkin else { return "\(eaten). Every colour is yours." }
        return "\(eaten). \(next.title) opens at \(next.unlockApples)."
    }

    private var padToggle: some View {
        Toggle(isOn: Binding(get: { session.records.pad }, set: { session.setPad($0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Big arrow buttons")
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                Text("Easier for small hands. Swiping still works.")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(SR.accent)
        .frame(minHeight: 56)
        .accessibilityIdentifier("snake-pad-toggle")
    }

    private var playButton: some View {
        Button {
            SRHaptic.tap()
            session.play()
        } label: {
            SRButtonLabel(title: playTitle, icon: "play.fill", fill: true)
                .frame(minHeight: 48)
        }
        .srButton(.prominent)
        .controlSize(.large)
        .accessibilityIdentifier("snake-start")
    }

    private var playTitle: String {
        session.mode == .maze ? "Play \(session.records.maze.name)" : "Play \(session.mode.title)"
    }
}

/// Mid-game, the clock stopped.
struct SnakePauseCard: View {
    @ObservedObject var session: SnakeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PAUSED")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text("\(session.score) points, \(session.length) long")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("\(session.place). The snake waits where you left it: swipe to carry on.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                session.resume()
            } label: {
                SRButtonLabel(title: "Resume", icon: "play.fill", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("snake-resume")
            HStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    session.play()
                } label: {
                    SRButtonLabel(title: "Restart", icon: "arrow.counterclockwise", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("snake-restart")
                Button {
                    SRHaptic.tap()
                    session.menu()
                } label: {
                    SRButtonLabel(title: "Modes", icon: "slider.horizontal.3", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("snake-menu")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("snake-paused")
    }
}

/// The end of a game: how it ended, the score against the best, and
/// anything it opened.
struct SnakeOverCard: View {
    let result: SnakeRunResult
    let onAgain: () -> Void
    let onMenu: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SnakeCardHolder {
                VStack(alignment: .leading, spacing: 12) {
                    kicker
                    Text(title)
                        .font(SR.Text.display(22))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(tip)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        SnakeStatChip(label: "SCORE", value: "\(result.score)")
                        SnakeStatChip(label: "BEST", value: "\(result.best)")
                        SnakeStatChip(label: "LENGTH", value: "\(result.length)")
                    }
                    Text(tally)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    openings
                }
            }
            HStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    onAgain()
                } label: {
                    SRButtonLabel(title: "Play again", icon: "arrow.counterclockwise", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("snake-again")
                Button {
                    SRHaptic.tap()
                    onMenu()
                } label: {
                    SRButtonLabel(title: "Modes", icon: "slider.horizontal.3", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("snake-over-menu")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("snake-over")
    }

    private var kicker: some View {
        HStack(spacing: 8) {
            Image(systemName: result.newBest || result.filled ? "trophy.fill" : "xmark.octagon.fill")
                .font(.system(size: 18, weight: .bold))
                .accessibilityHidden(true)
            Text(kickerText)
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
        }
        .foregroundStyle(result.newBest || result.filled ? SR.good : SR.error)
    }

    private var kickerText: String {
        if result.filled { return "YOU FILLED THE BOARD" }
        return result.newBest ? "NEW BEST" : "GAME OVER"
    }

    private var title: String {
        if result.filled { return "The whole board is snake. Brilliant!" }
        return result.death?.sentence ?? "Game over."
    }

    private var tip: String {
        if result.filled { return "There's nowhere left to go. Try another mode." }
        if result.newBest { return "Your best yet in \(placeName). Can you beat it?" }
        return result.death?.tip ?? ""
    }

    private var placeName: String {
        result.place ?? result.mode.title
    }

    private var tally: String {
        let apples = result.apples == 1 ? "1 apple" : "\(result.apples) apples"
        let golden = result.goldens == 0 ? "" : result.goldens == 1 ? ", 1 golden" : ", \(result.goldens) golden"
        return "\(placeName): \(apples)\(golden)."
    }

    @ViewBuilder
    private var openings: some View {
        if !result.unlockedMazes.isEmpty || !result.unlockedSkins.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(result.unlockedMazes, id: \.self) { name in
                    SnakeHowRow(icon: "lock.open.fill", text: "New maze: \(name).", tint: SR.good)
                }
                ForEach(result.unlockedSkins, id: \.self) { name in
                    SnakeHowRow(icon: "paintpalette.fill", text: "New colour: \(name). Pick it on the Modes card.", tint: SR.good)
                }
            }
        }
    }
}
