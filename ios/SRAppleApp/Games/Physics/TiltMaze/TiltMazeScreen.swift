import SwiftUI

/// Tilt Maze: a wooden labyrinth you tilt to roll a steel ball into the
/// brass cup, round the holes. Ten levels drawn by hand, thirty generated
/// ones that grow, and an endless run. Played on this phone, offline.
struct TiltMazeScreen: View {
    @StateObject private var game = TiltMazeGame()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // One container, so leaving the screen is one disappearance, not
        // one for whichever of the two pages was showing.
        ZStack {
            if game.stage == .menu {
                TiltMazeMenu(game: game)
            } else {
                TiltMazePlayView(game: game)
            }
        }
        .navigationTitle(GameKind.tiltMaze.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        // The board sits on a dark table: the bar's title and back button
        // read light over it, and follow the phone again on the menu.
        .toolbarColorScheme(barScheme, for: .navigationBar)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.pause() }
        }
        .onDisappear { game.leave() }
    }

    private var barScheme: ColorScheme? {
        if game.stage == .menu { return nil }
        return .dark
    }
}

/// A maze on the table: the strip at the top, the board, the controls, and
/// a card over it all between goes.
struct TiltMazePlayView: View {
    @ObservedObject var game: TiltMazeGame
    /// Shown for a moment after the calibrate button: "Level set".
    @State private var levelled = false
    @State private var levelledTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            TiltMazeTable()
            GeometryReader { whole in
                VStack(spacing: 12) {
                    hud
                    board
                    controls(compact: whole.size.height < 620)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .frame(width: whole.size.width, height: whole.size.height)
            }
            if game.stage == .playing && !game.started { startHint }
            if levelled && game.stage == .playing { levelledBadge }
            if game.stage != .playing { cardLayer }
        }
        .animation(.snappy(duration: 0.25), value: game.stage)
        .animation(.easeOut(duration: 0.2), value: levelled)
        .onDisappear { levelledTask?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tilt-maze-play")
    }

    // MARK: - The strip, the board, the controls

    private var hud: some View {
        TiltMazeHUD(engine: game.engine, kicker: kicker, title: game.info.name,
                    par: game.isEndless ? nil : game.par, lives: game.isEndless ? game.lives : nil) {
            game.pause()
        }
    }

    private var kicker: String {
        if game.isEndless { return "ENDLESS · \(game.level.cols) × \(game.level.rows)" }
        return "LEVEL \(game.number) OF \(TiltMazeCatalogue.campaignCount)"
    }

    private var board: some View {
        GeometryReader { space in
            let geometry = TiltMazeGeometry.fit(cols: game.level.cols, rows: game.level.rows, in: space.size)
            TiltMazeBoardView(engine: game.engine, key: game.key, level: game.level, wood: game.wood, geometry: geometry)
                .position(x: space.size.width / 2, y: space.size.height / 2)
        }
        .accessibilityElement()
        .accessibilityLabel(boardLabel)
        .accessibilityIdentifier("tilt-maze-board")
    }

    private var boardLabel: String {
        let level = game.level
        let holes = level.holes.count == 1 ? "1 hole" : "\(level.holes.count) holes"
        return "\(game.info.name): a maze \(level.cols) cells across and \(level.rows) down, with \(holes). Roll the marble to the brass cup."
    }

    /// `compact`: a short phone, where the stick gives the board some room back.
    @ViewBuilder
    private func controls(compact: Bool) -> some View {
        if game.scripted {
            TiltMazeCapsule(text: "Autopilot")
                .frame(height: 58)
        } else if game.steersByTilt {
            HStack(spacing: 12) {
                TiltMazeRoundButton(icon: "scope", label: "Calibrate: make the way I'm holding the phone level",
                                    id: "tilt-maze-calibrate") {
                    calibrate()
                }
                Spacer(minLength: 0)
                TiltMazeCapsule(text: "Tilt to roll")
                Spacer(minLength: 0)
                restartButton
            }
        } else {
            HStack(alignment: .bottom, spacing: 12) {
                restartButton
                Spacer(minLength: 0)
                TiltMazeJoystick(size: compact ? TiltMazeJoystick.compactSize : TiltMazeJoystick.fullSize) { value in
                    game.engine.stick = value
                }
                Spacer(minLength: 0)
                // Balances the row so the stick sits in the middle.
                Color.clear.frame(width: 58, height: 58)
            }
        }
    }

    /// Start this maze again. Not in an endless run, where it would throw
    /// the run away: that is on the pause card, with a warning in its name.
    @ViewBuilder
    private var restartButton: some View {
        if game.isEndless {
            Color.clear.frame(width: 58, height: 58)
        } else {
            TiltMazeRoundButton(icon: "arrow.counterclockwise", label: "Start this maze again", id: "tilt-maze-restart") {
                game.restart()
            }
        }
    }

    /// Zero the tilt, and say so for a second.
    private func calibrate() {
        game.calibrate()
        levelled = true
        levelledTask?.cancel()
        levelledTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            if !Task.isCancelled { levelled = false }
        }
    }

    private var levelledBadge: some View {
        VStack {
            TiltMazeCapsule(text: "Level set")
                .padding(.top, 84)
            Spacer()
        }
        .allowsHitTesting(false)
        .transition(.opacity)
        .accessibilityHidden(true)
    }

    private var startHint: some View {
        VStack {
            Spacer()
            TiltMazeCapsule(text: game.steersByTilt ? "Tilt to start the clock" : "Drag the stick to start the clock")
            Spacer()
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: - Cards between goes

    /// The card sits at the foot of the screen. At the largest text sizes on
    /// a small phone it can be taller than the screen, so it scrolls rather
    /// than push its buttons out of reach.
    private var cardLayer: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            GeometryReader { space in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        card
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .padding(.top, 8)
                    }
                    .frame(minHeight: space.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var card: some View {
        switch game.stage {
        case .briefing:
            TiltMazeBriefingCard(game: game)
        case .paused:
            TiltMazePauseCard(game: game)
        case .cleared:
            if game.isEndless { TiltMazeEndlessClearedCard(game: game) } else { TiltMazeClearedCard(game: game) }
        case .over:
            TiltMazeOverCard(game: game)
        case .menu, .playing:
            EmptyView()
        }
    }
}

/// The table under the board: dark, warm, a little light in the middle.
struct TiltMazeTable: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2A1E16), Color(hex: 0x120C08)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: 0x5A4030).opacity(0.55), Color.clear], center: .center,
                           startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A small dark pill of text over the table.
struct TiltMazeCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SR.Text.mono(13))
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// A card's mono kicker.
struct TiltMazeKicker: View {
    let text: String
    var colour: Color = SR.accent

    var body: some View {
        Text(text.uppercased())
            .font(SR.Text.label())
            .tracking(SR.inkKickerTracking)
            .foregroundStyle(colour)
    }
}

/// The card's big action, full width.
struct TiltMazeMainButton: View {
    let title: String
    let icon: String
    let id: String
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            SRButtonLabel(title: title, icon: icon, fill: true)
                .frame(minHeight: 56)
        }
        .srButton(.prominent)
        .controlSize(.large)
        .accessibilityIdentifier(id)
    }
}

/// A card's smaller action, sharing a row.
struct TiltMazeSideButton: View {
    let title: String
    let icon: String
    let id: String
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            SRButtonLabel(title: title, icon: icon, fill: true)
                .frame(minHeight: 50)
        }
        .srButton(.regular)
        .controlSize(.large)
        .accessibilityIdentifier(id)
    }
}

/// Before a maze: its name, a tip, the times to beat, and Roll.
struct TiltMazeBriefingCard: View {
    @ObservedObject var game: TiltMazeGame

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TiltMazeKicker(text: game.isEndless ? "Endless · maze \(game.cleared + 1)" :
                            "Level \(game.number) of \(TiltMazeCatalogue.campaignCount)")
            Text(game.info.name)
                .font(SR.Text.display(24))
                .foregroundStyle(SR.ink)
            Text(game.info.tip)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            targets
            Text(steering)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            TiltMazeMainButton(title: "Roll", icon: "play.fill", id: "tilt-maze-roll") { game.roll() }
            TiltMazeSideButton(title: game.isEndless ? "Menu" : "Levels", icon: "square.grid.3x3", id: "tilt-maze-levels") {
                game.toMenu()
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tilt-maze-briefing")
    }

    @ViewBuilder
    private var targets: some View {
        if game.isEndless {
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(SR.inkMuted)
                Text(game.lives == 1 ? "1 marble left" : "\(game.lives) marbles left")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                if game.book.endlessBest > 0 {
                    Text("· best \(game.book.endlessBest) mazes")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    TiltMazeStars(lit: 3, size: 13)
                    Text("under \(Int(game.par.three)) s")
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.ink)
                    TiltMazeStars(lit: 2, size: 13)
                    Text("under \(Int(game.par.two)) s")
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.ink)
                }
                if let best = game.book.bestTime(for: game.number) {
                    Text("Your best: \(TiltMazeFormat.time(best)) s")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var steering: String {
        if game.scripted { return "Demo: the autopilot rolls." }
        if game.steersByTilt { return "Hold the phone how you like: that becomes level when you tap Roll." }
        return "Drag the joystick the way you want the marble to roll."
    }
}

/// Paused: carry on, start again, or back to the levels.
struct TiltMazePauseCard: View {
    @ObservedObject var game: TiltMazeGame

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TiltMazeKicker(text: "Paused")
            Text(game.info.name)
                .font(SR.Text.display(24))
                .foregroundStyle(SR.ink)
            Text("\(TiltMazeFormat.time(game.engine.run.time)) s so far · \(falls)")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
            if game.tiltAvailable && !game.scripted {
                Toggle(isOn: $game.useStick) {
                    Text("Use the joystick")
                        .font(SR.Text.bodyMedium())
                        .foregroundStyle(SR.ink)
                }
                .tint(SR.accent)
                .accessibilityIdentifier("tilt-maze-pause-stick")
            }
            TiltMazeMainButton(title: "Carry on", icon: "play.fill", id: "tilt-maze-resume") { game.resume() }
            HStack(spacing: 10) {
                TiltMazeSideButton(title: game.isEndless ? "New run" : "Restart", icon: "arrow.counterclockwise",
                                   id: "tilt-maze-pause-restart") { game.restart() }
                TiltMazeSideButton(title: game.isEndless ? "Menu" : "Levels", icon: "square.grid.3x3",
                                   id: "tilt-maze-pause-levels") { game.toMenu() }
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tilt-maze-paused")
    }

    private var falls: String {
        let n = game.engine.run.falls
        return n == 1 ? "1 fall" : "\(n) falls"
    }
}

/// A campaign maze done: the stars, the time, the best, and on.
struct TiltMazeClearedCard: View {
    @ObservedObject var game: TiltMazeGame

    var body: some View {
        let finish = game.finish ?? TiltMazeGame.Finish(time: 0, stars: 1, falls: 0, newBestTime: false, newStars: false, bestTime: nil)
        return VStack(alignment: .leading, spacing: 12) {
            TiltMazeKicker(text: headline(finish), colour: SR.good)
            HStack(alignment: .center) {
                TiltMazeStars(lit: finish.stars, size: 34, celebrate: true)
                Spacer(minLength: 8)
                Text("\(TiltMazeFormat.time(finish.time)) s")
                    .font(SR.Text.figure(34))
                    .foregroundStyle(SR.ink)
                    .accessibilityLabel(TiltMazeFormat.spoken(finish.time))
            }
            Text(line(finish))
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if game.number < TiltMazeCatalogue.campaignCount {
                TiltMazeMainButton(title: "Level \(game.number + 1): \(TiltMazeCatalogue.info(game.number + 1).name)",
                                   icon: "arrow.right", id: "tilt-maze-next") { game.next() }
            } else {
                TiltMazeMainButton(title: "All forty done", icon: "checkmark", id: "tilt-maze-next") { game.next() }
            }
            HStack(spacing: 10) {
                TiltMazeSideButton(title: "Play again", icon: "arrow.counterclockwise", id: "tilt-maze-again") { game.restart() }
                TiltMazeSideButton(title: "Levels", icon: "square.grid.3x3", id: "tilt-maze-cleared-levels") { game.toMenu() }
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tilt-maze-cleared")
    }

    private func headline(_ finish: TiltMazeGame.Finish) -> String {
        if finish.newBestTime { return "New best time" }
        if finish.newStars && finish.stars == 3 { return "Three stars" }
        return "Level \(game.number) cleared"
    }

    private func line(_ finish: TiltMazeGame.Finish) -> String {
        let falls = finish.falls == 0 ? "No falls" : (finish.falls == 1 ? "1 fall" : "\(finish.falls) falls")
        var parts = [falls]
        if let best = finish.bestTime { parts.append("best \(TiltMazeFormat.time(best)) s") }
        if finish.stars < 3 { parts.append("three stars under \(Int(game.par.three)) s") }
        return parts.joined(separator: " · ") + "."
    }
}

/// An endless maze done: on to the next, or stop here.
struct TiltMazeEndlessClearedCard: View {
    @ObservedObject var game: TiltMazeGame

    var body: some View {
        let time = game.finish?.time ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            TiltMazeKicker(text: "Maze \(game.cleared) done", colour: SR.good)
            HStack(alignment: .firstTextBaseline) {
                Text("\(game.cleared)")
                    .font(SR.Text.figure(40))
                    .foregroundStyle(SR.ink)
                Text(game.cleared == 1 ? "maze" : "mazes")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.inkSecondary)
                Spacer(minLength: 8)
                Text("\(TiltMazeFormat.time(time)) s")
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.inkSecondary)
            }
            Text(game.lives == 1 ? "1 marble left. The next maze is a little bigger." :
                    "\(game.lives) marbles left. The next maze is a little bigger.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TiltMazeMainButton(title: "Next maze", icon: "arrow.right", id: "tilt-maze-next") { game.next() }
            TiltMazeSideButton(title: "Stop here", icon: "flag.checkered", id: "tilt-maze-stop") { game.endRun() }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tilt-maze-cleared")
    }
}

/// An endless run over: how many mazes, and the best.
struct TiltMazeOverCard: View {
    @ObservedObject var game: TiltMazeGame

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TiltMazeKicker(text: game.endlessNewBest ? "New best" : (game.lives <= 0 ? "Out of marbles" : "Run over"),
                           colour: game.endlessNewBest ? SR.good : SR.error)
            HStack(alignment: .firstTextBaseline) {
                Text("\(game.cleared)")
                    .font(SR.Text.figure(40))
                    .foregroundStyle(SR.ink)
                Text(game.cleared == 1 ? "maze cleared" : "mazes cleared")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.inkSecondary)
            }
            Text("Your best run: \(game.book.endlessBest) \(game.book.endlessBest == 1 ? "maze" : "mazes").")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
            TiltMazeMainButton(title: "Play again", icon: "arrow.counterclockwise", id: "tilt-maze-again") { game.playEndless() }
            TiltMazeSideButton(title: "Menu", icon: "square.grid.3x3", id: "tilt-maze-over-menu") { game.toMenu() }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tilt-maze-over")
    }
}
