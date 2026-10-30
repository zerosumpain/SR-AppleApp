import SwiftUI

/// A round under way: the hole full screen, the instruments over the top,
/// the aim controls at the bottom, and a card between turns.
struct MiniGolfPlayView: View {
    @ObservedObject var game: MiniGolfGame
    let again: () -> Void
    let leave: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hudHeight: CGFloat = 96
    @State private var footHeight: CGFloat = 72
    @State private var showScorecard = false
    /// The scorecard paused a putt in play, so closing it carries on.
    @State private var resumeAfterCard = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                MiniGolfCourseView(scene: game.scene)
                aimLayer
                overlay
                if game.paused { pausedLayer }
            }
            .onAppear {
                game.calm = reduceMotion
                game.setPlayRect(playRect(geo.size))
                game.appeared()
            }
            .onChange(of: geo.size) { _, size in game.setPlayRect(playRect(size)) }
            .onChange(of: hudHeight) { _, _ in game.setPlayRect(playRect(geo.size)) }
            .onChange(of: footHeight) { _, _ in game.setPlayRect(playRect(geo.size)) }
        }
        .background(garden.ignoresSafeArea())
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: game.stage)
        .animation(.easeInOut(duration: 0.2), value: game.paused)
        .animation(.easeInOut(duration: 0.25), value: game.toast)
        .onDisappear { game.stop() }
        .onChange(of: reduceMotion) { _, calm in game.calm = calm }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.pause() }
        }
        .sheet(isPresented: $showScorecard, onDismiss: closedScorecard) {
            NavigationStack {
                MiniGolfScorecardView(round: game.round)
                    .navigationTitle("Scorecard")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showScorecard = false }
                                .accessibilityIdentifier("mini-golf-scorecard-done")
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mini-golf-play")
    }

    /// The garden colour round the screen's edges, matching the course view's ground.
    private var garden: Color {
        scheme == .dark ? Color(red: 0.03, green: 0.09, blue: 0.06) : Color(red: 0.17, green: 0.38, blue: 0.22)
    }

    /// Where the hole is framed: between the instruments and the controls.
    private func playRect(_ size: CGSize) -> CGRect {
        let top = hudHeight + 20
        let bottom = footHeight + 20
        let height = max(120, size.height - top - bottom)
        return CGRect(x: 0, y: top, width: size.width, height: height)
    }

    private func openScorecard() {
        let inPlay = game.stage == .aiming || game.stage == .rolling || game.stage == .sunk
        if inPlay && !game.paused {
            game.pause()
            resumeAfterCard = true
        }
        showScorecard = true
    }

    /// Opened from the controls mid-putt: closing the card goes straight back to the hole.
    /// Opened from the pause card, it stays paused.
    private func closedScorecard() {
        guard resumeAfterCard else { return }
        resumeAfterCard = false
        game.resume()
    }

    // MARK: - Aiming

    /// The whole screen takes the drag: put a finger anywhere and pull back.
    private var aimLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in game.drag(value.translation) }
                    .onEnded { value in game.release(value.translation) }
            )
            .accessibilityElement()
            .accessibilityLabel(courseLabel)
            .accessibilityValue(game.stage == .aiming ? game.assistLine : "")
            .accessibilityHint(game.stage == .aiming ? "Use the actions to aim, set the power and putt." : "")
            .accessibilityAction(named: "Putt") { game.assistPutt() }
            .accessibilityAction(named: "Aim at the cup") { game.assistAimAtCup() }
            .accessibilityAction(named: "Aim left a little") { game.assistTurn(-.pi / 18) }
            .accessibilityAction(named: "Aim right a little") { game.assistTurn(.pi / 18) }
            .accessibilityAction(named: "More power") { game.assistPower(0.1) }
            .accessibilityAction(named: "Less power") { game.assistPower(-0.1) }
            .accessibilityIdentifier("mini-golf-course")
    }

    private var courseLabel: String {
        let hole = game.hole
        let stroke = game.strokes == 1 ? "1 stroke" : "\(game.strokes) strokes"
        return "Hole \(hole.number), \(hole.name), par \(hole.par). \(game.player.name), \(stroke) so far."
    }

    // MARK: - Over the hole

    private var overlay: some View {
        VStack(spacing: 10) {
            MiniGolfHUD(game: game, pause: { game.pause() })
                .background(MiniGolfHeightReader(height: $hudHeight))
            if let toast = game.toast {
                MiniGolfToast(text: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if game.stage == .sunk {
                MiniGolfSunkBanner(game: game)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            // First call on the height, so a card that fits is never squeezed
            // into its scrolling form by the spacer above it.
            foot
                .layoutPriority(1)
                .background(MiniGolfHeightReader(height: $footHeight))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var foot: some View {
        switch game.stage {
        case .tee:
            MiniGolfFitting {
                MiniGolfTeeCard(game: game)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .aiming, .rolling, .sunk:
            MiniGolfControls(game: game, scorecard: openScorecard)
        case .holeDone:
            MiniGolfFitting {
                MiniGolfHoleDoneCard(game: game, scorecard: openScorecard)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .finished:
            MiniGolfFitting {
                MiniGolfFinishedCard(game: game, scorecard: openScorecard, again: again, leave: leave)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var pausedLayer: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            MiniGolfFitting {
                MiniGolfPausedCard(resume: { game.resume() }, scorecard: openScorecard, leave: leave)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: 480)
        }
        .transition(.opacity)
    }
}

/// A card that scrolls rather than running off a small phone at a large text size.
struct MiniGolfFitting<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Reports the height of whatever it is the background of.
struct MiniGolfHeightReader: View {
    @Binding var height: CGFloat

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { height = geo.size.height }
                .onChange(of: geo.size.height) { _, value in height = value }
        }
    }
}

// MARK: - Instruments

/// The top bar: the hole, par, whose turn, the strokes, and the pause button.
struct MiniGolfHUD: View {
    @ObservedObject var game: MiniGolfGame
    let pause: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kicker)
                    .font(SR.Text.label())
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(SR.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(game.hole.name)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !game.round.isSolo {
                    HStack(spacing: 6) {
                        MiniGolfBallBadge(seat: game.player.seat, size: 14)
                        Text(game.player.name)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            strokesFigure
            pauseButton
        }
        .padding(.leading, SR.cardPadding)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mini-golf-hud")
    }

    private var kicker: String {
        let round = game.round
        return "HOLE \(round.holeSlot + 1) OF \(round.holeCount) · PAR \(game.hole.par)"
    }

    private var strokesFigure: some View {
        let over = game.strokes > game.hole.par
        return VStack(alignment: .trailing, spacing: 1) {
            Text("\(game.strokes)")
                .font(SR.Text.figure(30))
                .foregroundStyle(over ? SR.warn : SR.ink)
                .contentTransition(.numericText())
                .animation(.snappy, value: game.strokes)
            Text(game.strokes == 1 ? "STROKE" : "STROKES")
                .font(SR.Text.label(11))
                .foregroundStyle(SR.inkMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.strokes) of \(game.maxStrokes) strokes")
    }

    private var pauseButton: some View {
        Button {
            SRHaptic.tap()
            pause()
        } label: {
            Image(systemName: "pause.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(SR.ink)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .srGlass(.clear, in: Circle(), interactive: true)
        .disabled(!(game.stage == .aiming || game.stage == .rolling || game.stage == .sunk))
        .opacity(game.stage == .aiming || game.stage == .rolling || game.stage == .sunk ? 1 : 0.35)
        .accessibilityLabel("Pause")
        .accessibilityIdentifier("mini-golf-pause")
    }
}

/// A line across the top for a moment.
struct MiniGolfToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SR.Text.bodyMedium(15))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.62)))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("mini-golf-toast")
    }
}

/// While putting: the whole-hole button, the hint or the power meter, and the scorecard.
struct MiniGolfControls: View {
    @ObservedObject var game: MiniGolfGame
    let scorecard: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MiniGolfRoundButton(icon: game.overview ? "scope" : "arrow.up.left.and.arrow.down.right",
                                label: game.overview ? "Follow the ball" : "Show the whole hole") {
                game.toggleOverview()
            }
            .accessibilityIdentifier("mini-golf-overview")
            middle
                .frame(maxWidth: .infinity)
            MiniGolfRoundButton(icon: "list.number", label: "Scorecard", action: scorecard)
                .accessibilityIdentifier("mini-golf-scorecard")
        }
    }

    @ViewBuilder
    private var middle: some View {
        if game.dragging {
            MiniGolfPowerMeter(power: game.power)
                .allowsHitTesting(false)
        } else {
            Text(hint)
                .font(SR.Text.secondary(14))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 56)
                .background(Capsule().fill(Color.black.opacity(0.4)))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var hint: String {
        switch game.stage {
        case .rolling: return "Rolling…"
        case .sunk: return game.sunkWord
        default: return game.strokes == 0 ? "Drag back from the ball, let go to putt" : "Drag back to putt again"
        }
    }
}

/// A big round glass button for the controls.
struct MiniGolfRoundButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SR.ink)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .srGlass(.paper, in: Circle(), interactive: true)
        .accessibilityLabel(label)
    }
}

/// How hard the putt will be while the finger is down.
struct MiniGolfPowerMeter: View {
    let power: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("POWER")
                    .font(SR.Text.label(11))
                    .foregroundStyle(Color.white.opacity(0.8))
                Spacer(minLength: 4)
                Text("\(Int((power * 100).rounded()))%")
                    .font(SR.Text.mono(13))
                    .foregroundStyle(Color.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(LinearGradient(colors: [MiniGolfPaint.power(0), MiniGolfPaint.power(max(0.01, power))],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * CGFloat(min(max(power, 0), 1))))
                }
            }
            .frame(height: 10)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power \(Int((power * 100).rounded())) percent")
        .accessibilityIdentifier("mini-golf-power")
    }
}

// MARK: - Cards

/// The shared look of the game's cards.
struct MiniGolfCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
    }
}

/// Before a player tees off: the hole, its tip, and whose turn it is.
struct MiniGolfTeeCard: View {
    @ObservedObject var game: MiniGolfGame

    var body: some View {
        MiniGolfCard {
            Text("HOLE \(game.hole.number) · PAR \(game.hole.par)")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text(game.hole.name)
                .font(SR.Text.display(24))
                .foregroundStyle(SR.ink)
            Text(game.hole.tip)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if game.isFirstTee {
                VStack(alignment: .leading, spacing: 6) {
                    MiniGolfRuleLine(text: "Drag back from anywhere, away from where you want to go. Further is harder.")
                    MiniGolfRuleLine(text: "Let go to putt. Gentle at the cup: a fast ball lips out.")
                }
            }
            if !game.round.isSolo {
                HStack(spacing: 8) {
                    MiniGolfBallBadge(seat: game.player.seat, size: 20)
                    Text(turnLine)
                        .font(SR.Text.bodyMedium())
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            if let best = game.book.best(hole: game.hole.number) {
                Text("Best on this hole: \(best). \(MiniGolfScoreWord.word(strokes: best, par: game.hole.par)).")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            Button {
                game.teeOff()
            } label: {
                SRButtonLabel(title: game.round.isSolo ? "Tee off" : "\(game.player.name) tees off", icon: "figure.golf", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("mini-golf-tee")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mini-golf-tee-card")
    }

    private var turnLine: String {
        game.round.turn == 0 && game.round.holeSlot == 0
            ? "\(game.player.name) goes first."
            : "Pass the phone to \(game.player.name)."
    }
}

/// In the cup: the word for it, big.
struct MiniGolfSunkBanner: View {
    @ObservedObject var game: MiniGolfGame

    var body: some View {
        VStack(spacing: 4) {
            Text(game.holeInOne ? "HOLE IN ONE!" : game.sunkWord)
                .font(SR.Text.hero(game.holeInOne ? 40 : 34))
                .foregroundStyle(game.holeInOne ? MiniGolfPaint.goldInk : SR.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(line)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .multilineTextAlignment(.center)
            if game.newHoleBest && game.sunkWord != "Picked up" {
                Text("NEW BEST ON THIS HOLE")
                    .font(SR.Text.label())
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(SR.good)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mini-golf-sunk")
    }

    private var line: String {
        let strokes = game.sunkStrokes == 1 ? "1 stroke" : "\(game.sunkStrokes) strokes"
        let who = game.round.isSolo ? "" : "\(game.player.name): "
        return "\(who)\(strokes) on a par \(game.hole.par)"
    }
}

/// Everyone has played the hole: how each did, and the running totals.
struct MiniGolfHoleDoneCard: View {
    @ObservedObject var game: MiniGolfGame
    let scorecard: () -> Void

    var body: some View {
        MiniGolfCard {
            Text("HOLE \(game.hole.number) · PAR \(game.hole.par)")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text(game.round.isSolo ? soloTitle : "\(game.hole.name) done")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                ForEach(Array(game.round.players.indices), id: \.self) { index in
                    MiniGolfScoreRow(round: game.round, index: index, slot: game.round.holeSlot)
                }
            }
            HStack(spacing: 10) {
                Button(action: scorecard) {
                    SRButtonLabel(title: "Card", icon: "list.number")
                        .frame(minHeight: 44)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("mini-golf-hole-scorecard")
                Button {
                    game.nextHole()
                } label: {
                    SRButtonLabel(title: nextTitle, icon: lastHole ? "flag.checkered" : "arrow.right", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("mini-golf-next")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mini-golf-hole-done")
    }

    private var lastHole: Bool { game.round.holeSlot + 1 >= game.round.holeCount }

    private var nextTitle: String {
        guard !lastHole else { return "Results" }
        return "Hole \(game.round.hole(at: game.round.holeSlot + 1).number)"
    }

    private var soloTitle: String {
        let strokes = game.round.strokes(player: 0, slot: game.round.holeSlot) ?? 0
        return "\(MiniGolfScoreWord.word(strokes: strokes, par: game.hole.par)) on \(game.hole.name)"
    }
}

/// One player's line on a card: their ball, name, this hole and the round so far.
struct MiniGolfScoreRow: View {
    let round: MiniGolfRound
    let index: Int
    let slot: Int

    var body: some View {
        let player = round.players[index]
        let strokes = round.strokes(player: index, slot: slot)
        let par = round.hole(at: slot).par
        return HStack(spacing: 10) {
            MiniGolfBallBadge(seat: player.seat, size: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.name)
                    .font(SR.Text.bodyMedium())
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                Text(strokes.map { MiniGolfScoreWord.word(strokes: $0, par: par) } ?? "Still to play")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(strokes.map { "\($0)" } ?? "–")
                .font(SR.Text.figure(22))
                .foregroundStyle(MiniGolfScorecardView.tone(strokes, par: par))
            Text(MiniGolfScoreWord.toPar(round.toPar(index)))
                .font(SR.Text.mono(13))
                .foregroundStyle(SR.inkSecondary)
                .frame(minWidth: 34, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
        .accessibilityElement(children: .combine)
    }
}

/// The end of the round: who won, the totals, the best, and again.
struct MiniGolfFinishedCard: View {
    @ObservedObject var game: MiniGolfGame
    let scorecard: () -> Void
    let again: () -> Void
    let leave: () -> Void

    var body: some View {
        MiniGolfCard {
            Text(game.newRoundBest ? "NEW BEST ROUND" : "ROUND OVER · \(game.round.loop.title.uppercased())")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(game.newRoundBest ? SR.good : SR.accent)
            Text(title)
                .font(SR.Text.display(24))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                ForEach(Array(game.round.standings.enumerated()), id: \.element) { place, index in
                    standing(place: place, index: index)
                }
            }
            Text(bestLine)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                SRHaptic.tap()
                again()
            } label: {
                SRButtonLabel(title: "Play again", icon: "arrow.counterclockwise", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("mini-golf-again")
            HStack(spacing: 10) {
                Button(action: scorecard) {
                    SRButtonLabel(title: "Card", icon: "list.number", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("mini-golf-final-scorecard")
                Button {
                    SRHaptic.tap()
                    leave()
                } label: {
                    SRButtonLabel(title: "New round", icon: "person.2", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("mini-golf-new-round")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mini-golf-finished")
    }

    private var title: String {
        let round = game.round
        if round.isSolo {
            let total = round.total(0)
            return "\(total) strokes, \(toParWords(round.toPar(0)))."
        }
        guard let winner = round.winner else { return "It's a tie at the top!" }
        return "\(round.players[winner].name) wins!"
    }

    private func toParWords(_ diff: Int) -> String {
        if diff == 0 { return "level par" }
        return diff < 0 ? "\(-diff) under par" : "\(diff) over par"
    }

    private var bestLine: String {
        let loop = game.round.loop
        guard let best = game.book.best(loop: loop) else { return "Par for the \(loop.title.lowercased()) is \(loop.par)." }
        return "Best \(loop.title.lowercased()) on this phone: \(best) (\(MiniGolfScoreWord.toPar(best - loop.par))). Par \(loop.par)."
    }

    private func standing(place: Int, index: Int) -> some View {
        let round = game.round
        let player = round.players[index]
        return HStack(spacing: 10) {
            Text("\(place + 1)")
                .font(SR.Text.figure(18))
                .foregroundStyle(place == 0 ? MiniGolfPaint.goldInk : SR.inkMuted)
                .frame(width: 22)
            MiniGolfBallBadge(seat: player.seat, size: 18)
            Text(player.name)
                .font(SR.Text.bodyMedium())
                .foregroundStyle(SR.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("\(round.total(index))")
                .font(SR.Text.figure(22))
                .foregroundStyle(SR.ink)
            Text(MiniGolfScoreWord.toPar(round.toPar(index)))
                .font(SR.Text.mono(13))
                .foregroundStyle(SR.inkSecondary)
                .frame(minWidth: 34, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
        .accessibilityElement(children: .combine)
    }
}

/// Paused: carry on, look at the card, or leave the round.
struct MiniGolfPausedCard: View {
    let resume: () -> Void
    let scorecard: () -> Void
    let leave: () -> Void

    var body: some View {
        MiniGolfCard {
            Text("PAUSED")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text("Take a breather.")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
            Button {
                SRHaptic.tap()
                resume()
            } label: {
                SRButtonLabel(title: "Carry on", icon: "play.fill", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("mini-golf-resume")
            Button(action: scorecard) {
                SRButtonLabel(title: "Scorecard", icon: "list.number", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("mini-golf-paused-scorecard")
            Button {
                SRHaptic.tap()
                leave()
            } label: {
                SRButtonLabel(title: "Leave the round", icon: "xmark", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("mini-golf-leave")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mini-golf-paused")
    }
}
