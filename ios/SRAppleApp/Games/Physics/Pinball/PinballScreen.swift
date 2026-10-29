import SwiftUI

/// Pinball: the dot-matrix strip and the ball count over a full portrait
/// table, the flipper halves under the player's thumbs, and a card before,
/// between and after games.
struct PinballScreen: View {
    @StateObject private var game = PinballEngine()
    @Environment(\.scenePhase) private var scenePhase
    @State private var initials = ""
    @State private var showScores = false
    @FocusState private var typingInitials: Bool

    var body: some View {
        ZStack {
            PinballBackdrop()
            VStack(spacing: 8) {
                PinballHeader(hud: game.hud, canPause: game.stage == .playing) { game.pause() }
                playArea
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
            cardLayer
        }
        .navigationTitle(GameKind.pinball.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onDisappear { game.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.pause() }
        }
        .onChange(of: game.result) { _, result in
            if result != nil { initials = game.book.lastInitials }
        }
        .accessibilityIdentifier("pinball-screen")
    }

    // MARK: - The table

    private var playArea: some View {
        ZStack(alignment: .bottom) {
            PinballTouchPad(engine: game)
            PinballTableStack(engine: game, clock: game.clock)
                .aspectRatio(CGFloat(PinballTable.width / PinballTable.height), contentMode: .fit)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if game.stage == .playing && game.hud.waiting && !game.scripted {
                launchHint
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pinball-table")
    }

    private var launchHint: some View {
        HStack(spacing: 10) {
            hintChip(icon: "hand.tap.fill", text: "Hold left or right to flip")
            Spacer(minLength: 0)
            hintChip(icon: "arrow.down", text: "Pull down here to launch")
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    private func hintChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
            Text(text)
                .font(SR.Text.label())
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.black.opacity(0.62)))
        .frame(maxWidth: 170)
    }

    // MARK: - Cards

    @ViewBuilder
    private var cardLayer: some View {
        switch game.stage {
        case .intro:
            cardShade { introCard }
        case .paused:
            cardShade { pausedCard }
        case .over:
            cardShade { overCard }
        case .playing:
            EmptyView()
        }
    }

    private func cardShade<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            ScrollView {
                content()
                    .frame(maxWidth: 480)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PINBALL")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text("Flip, nudge and light up the table.")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            PinballHowToPlay(canShake: game.shake.available, scripted: game.scripted)
            if game.book.best > 0 {
                Text("Best on this phone: \(PinballScoring.digits(game.book.best))")
                    .font(SR.Text.mono(13))
                    .foregroundStyle(SR.inkSecondary)
            }
            if showScores {
                PinballScoreList(book: game.book, highlight: nil)
            }
            Button {
                SRHaptic.tap()
                game.begin()
            } label: {
                SRButtonLabel(title: "Play", icon: "play.fill", fill: true)
                    .frame(minHeight: 52)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("pinball-start")
            if !game.book.entries.isEmpty {
                Button {
                    SRHaptic.select()
                    withAnimation(.easeInOut(duration: 0.2)) { showScores.toggle() }
                } label: {
                    SRButtonLabel(title: showScores ? "Hide high scores" : "High scores", icon: "list.number", fill: true)
                        .frame(minHeight: 52)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("pinball-scores")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("pinball-intro")
    }

    private var pausedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PAUSED")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text("\(PinballScoring.digits(game.hud.score)) on ball \(game.hud.ball) of \(game.hud.balls)")
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text("Mode: \(PinballHeader.modeName(game.hud.mode)) — \(game.hud.mode.instruction.lowercased()), \(game.hud.progress) of \(game.hud.goal).")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PinballHowToPlay(canShake: game.shake.available, scripted: game.scripted)
            Button {
                SRHaptic.tap()
                game.resume()
            } label: {
                SRButtonLabel(title: "Carry on", icon: "play.fill", fill: true)
                    .frame(minHeight: 52)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("pinball-resume")
            Button {
                SRHaptic.tap()
                game.begin()
            } label: {
                SRButtonLabel(title: "Start again", icon: "arrow.counterclockwise", fill: true)
                    .frame(minHeight: 52)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("pinball-restart")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("pinball-paused")
    }

    @ViewBuilder
    private var overCard: some View {
        if let result = game.result {
            VStack(alignment: .leading, spacing: 12) {
                Text(overKicker(result))
                    .font(SR.Text.label())
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(result.newBest ? SR.good : SR.accent)
                Text(PinballScoring.digits(result.score))
                    .font(SR.Text.figure(38))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel("\(result.score) points")
                Text(statsLine(result.stats))
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if result.rank != nil { initialsRow }
                PinballScoreList(book: game.book, highlight: result.entryID)
                Button {
                    SRHaptic.tap()
                    saveInitials()
                    game.begin()
                } label: {
                    SRButtonLabel(title: "Play again", icon: "arrow.counterclockwise", fill: true)
                        .frame(minHeight: 52)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("pinball-again")
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityIdentifier("pinball-over")
        }
    }

    private var initialsRow: some View {
        HStack(spacing: 10) {
            TextField("Your initials", text: $initials)
                .font(SR.Text.title())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($typingInitials)
                .onSubmit { saveInitials() }
                .onChange(of: initials) { _, typed in
                    let clean = PinballScoreBook.clean(typed)
                    if clean != typed { initials = clean }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SR.ink.opacity(0.06)))
                .accessibilityIdentifier("pinball-initials")
            Button {
                SRHaptic.select()
                saveInitials()
            } label: {
                SRButtonLabel(title: "Save", icon: "checkmark")
                    .frame(minHeight: 52)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("pinball-save-initials")
        }
    }

    private func saveInitials() {
        typingInitials = false
        guard !PinballScoreBook.clean(initials).isEmpty else { return }
        game.rename(to: initials)
    }

    private func overKicker(_ result: PinballResult) -> String {
        if result.newBest { return "NEW HIGH SCORE" }
        if let rank = result.rank { return "GAME OVER · NUMBER \(rank) ON THE TABLE" }
        return "GAME OVER"
    }

    private func statsLine(_ stats: PinballStats) -> String {
        func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
        let parts = [
            count(stats.ramps, "ramp", "ramps"),
            count(stats.orbits, "orbit", "orbits"),
            count(stats.jackpots, "jackpot", "jackpots"),
            count(stats.modes, "mode", "modes"),
        ]
        let shots = stats.skillShots > 0 ? " Skill shots: \(stats.skillShots)." : ""
        return parts.joined(separator: ", ") + "." + shots
    }
}

// MARK: - Pieces

/// The cabinet's dark ground behind everything.
struct PinballBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.07, green: 0.05, blue: 0.14), Color(red: 0.01, green: 0.01, blue: 0.03)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// The table and its moving parts, jolted together after a big hit.
struct PinballTableStack: View {
    let engine: PinballEngine
    @ObservedObject var clock: PinballClock

    var body: some View {
        let jolt = engine.jolt
        ZStack {
            PinballTableArt()
                .equatable()
            PinballTableLive(engine: engine, clock: clock)
            PinballTableLabels()
                .equatable()
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .offset(x: CGFloat(jolt.x), y: CGFloat(jolt.y))
    }
}

/// The strip, the pause button, and a line of what matters this ball.
struct PinballHeader: View {
    let hud: PinballHUD
    let canPause: Bool
    let pause: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                PinballDotMatrixView(dots: hud.dots, key: hud.dotsKey)
                    .equatable()
                    .frame(maxWidth: .infinity)
                    .accessibilityElement()
                    .accessibilityLabel("Score \(hud.score)")
                    .accessibilityIdentifier("pinball-score")
                pauseButton
            }
            statusRow
        }
    }

    private var pauseButton: some View {
        Button {
            SRHaptic.tap()
            pause()
        } label: {
            Image(systemName: "pause.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(PinballPressStyle())
        .disabled(!canPause)
        .opacity(canPause ? 1 : 0.4)
        .accessibilityLabel("Pause")
        .accessibilityIdentifier("pinball-pause")
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            chip("BALL \(hud.ball)/\(hud.balls)", tone: Color.white)
            chip("\(hud.multiplier)× BONUS", tone: hud.multiplier > 1 ? PinballGlow.gold : Color.white)
            if hud.tilted {
                chip("TILT", tone: PinballGlow.red)
            } else if hud.warnings > 0 {
                chip("DANGER \(hud.warnings)", tone: PinballGlow.red)
            } else if hud.multiball {
                chip("MULTIBALL", tone: PinballGlow.cyan)
            } else if hud.save {
                chip("BALL SAVE", tone: PinballGlow.green)
            }
            Spacer(minLength: 0)
            Text("\(Self.modeName(hud.mode)) \(hud.progress)/\(hud.goal)")
                .font(SR.Text.mono(12))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusLabel)
        .accessibilityIdentifier("pinball-status")
    }

    private func chip(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(SR.Text.label(11))
            .tracking(0.8)
            .foregroundStyle(tone)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.1)))
    }

    static func modeName(_ mode: PinballMode) -> String {
        switch mode {
        case .bumperBlitz: return "Bumper blitz"
        case .rampRush: return "Ramp rush"
        case .targetPractice: return "Target practice"
        case .orbitRun: return "Orbit run"
        }
    }

    private var statusLabel: String {
        var words = "Ball \(hud.ball) of \(hud.balls). Bonus times \(hud.multiplier)."
        if hud.tilted { words += " Tilted." } else if hud.warnings > 0 { words += " Tilt warning \(hud.warnings)." }
        if hud.multiball { words += " Multiball." }
        if hud.save { words += " Ball save on." }
        words += " \(Self.modeName(hud.mode)): \(hud.progress) of \(hud.goal)."
        return words
    }
}

/// A press that shrinks a little under the thumb.
struct PinballPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// How to play, in plain words.
struct PinballHowToPlay: View {
    let canShake: Bool
    let scripted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if scripted { rule("Demo: the table plays itself.") }
            rule("Touch the left or right side of the screen to flip. Both at once works too.")
            rule("Pull down on the right-hand side to draw the plunger back, then let go. A quick tap sends a gentle ball.")
            rule(canShake ? "Shake the phone to nudge the ball. Shake too much and the table tilts: no flippers, no bonus."
                 : "Nudging needs a phone with a motion sensor.")
            rule("Light all three top lanes to raise the bonus multiplier. The flippers move the lit lanes along.")
            rule("Finish a mode — bumpers, ramp, targets, orbit — to start multiball. The ramp scores jackpots.")
            rule("Three balls, with a ball saver for the first \(Int(PinballScoring.ballSave)) seconds of each.")
        }
    }

    private func rule(_ text: String) -> some View {
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

/// The high-score table, best first.
struct PinballScoreList: View {
    let book: PinballScoreBook
    /// The game just played, picked out.
    let highlight: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HIGH SCORES")
                .font(SR.Text.label(11))
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.inkMuted)
            if book.entries.isEmpty {
                Text("No games yet.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
            }
            ForEach(Array(book.entries.enumerated()), id: \.element.id) { index, entry in
                row(index + 1, entry)
            }
        }
        .accessibilityIdentifier("pinball-score-list")
    }

    private func row(_ rank: Int, _ entry: PinballScoreBook.Entry) -> some View {
        let mine = entry.id == highlight
        return HStack(spacing: 10) {
            Text("\(rank)")
                .font(SR.Text.mono(13))
                .foregroundStyle(SR.inkMuted)
                .frame(minWidth: 22, alignment: .trailing)
            Text(entry.initials)
                .font(SR.Text.title(15))
                .foregroundStyle(mine ? SR.accent : SR.ink)
            Spacer(minLength: 8)
            Text(PinballScoring.digits(entry.score))
                .font(SR.Text.mono(14))
                .foregroundStyle(mine ? SR.accent : SR.ink)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank). \(entry.initials), \(entry.score) points")
    }
}
