import SwiftUI
import UIKit

/// Lander's engine on this phone: a display link that turns tilt and touch
/// into `LanderInput`, flies the rules one frame at a time and hands the
/// flight to the 3D scene. The run, the best and the end of each flight are
/// published for the screen; the scene is moved directly, not through SwiftUI.
@MainActor
final class LanderGame: ObservableObject {
    enum Stage: Equatable {
        /// Before the first flight: the briefing.
        case briefing
        case flying
        /// Down safely; the next level waits for a tap.
        case landed(LanderLanding)
        case crashed(LanderCrash)
    }

    @Published private(set) var run = LanderRun(seed: 1)
    @Published private(set) var stage: Stage = .briefing
    @Published private(set) var book: PhysicsScoreBook
    /// The run that just ended beat the best.
    @Published private(set) var newBest = false
    /// Mid-flight with the clock stopped: the pause card is up.
    @Published private(set) var paused = false
    /// A finger is on the screen: the engine burns.
    var thrustHeld = false
    /// Without a tilt sensor: −1, 0 or 1 from the lean buttons.
    var leanHeld: Double = 0

    let scene = LanderSceneController()
    let tilt = PhysicsTilt()
    /// Demo mode flies itself: no sensor, no finger, the screenshots still move.
    let scripted = SRDemo.isOn
    private let store = PhysicsScoreStore()
    private var ticker: FrameTicker?
    private var lastFrame: Double?
    /// The lean the player is asking for, eased so a shaky hand is not a shaky craft.
    private var lean: Double = 0
    /// The warnings last frame, so a new one buzzes once rather than every frame.
    private var warned: Set<LanderWarning> = []

    init() {
        book = PhysicsScoreStore().load()
        scene.update(run.flight)
    }

    var steersByTilt: Bool { tilt.available && !scripted }

    /// A new run from level 1, on new ground.
    func begin() {
        run = LanderRun(seed: scripted ? 7 : UInt64.random(in: 1...UInt64(UInt32.max)))
        newBest = false
        fly()
    }

    /// After a landing: the next level.
    func nextLevel() {
        run.nextLevel()
        fly()
    }

    private func fly() {
        paused = false
        scene.setPaused(false)
        stage = .flying
        lean = 0
        warned = []
        thrustHeld = false
        scene.update(run.flight)
        startClock()
    }

    private func startClock() {
        lastFrame = nil
        tilt.start()
        guard ticker == nil else { return }
        let ticker = FrameTicker { [weak self] time in
            guard let self else { return false }
            return self.frame(time)
        }
        self.ticker = ticker
        ticker.start()
    }

    /// Mid-flight: stop the clock, the sensor and the scene's particles.
    func pause() {
        guard stage == .flying, !paused else { return }
        paused = true
        thrustHeld = false
        leanHeld = 0
        ticker?.stop()
        ticker = nil
        lastFrame = nil
        tilt.stop()
        scene.setPaused(true)
    }

    /// Back to the flight exactly where it stopped.
    func resume() {
        guard stage == .flying, paused else { return }
        paused = false
        scene.setPaused(false)
        SRHaptic.tap()
        startClock()
    }

    /// Off screen, or the flight is over: the display link and the sensor stop.
    func stop() {
        pause()
        ticker?.stop()
        ticker = nil
        lastFrame = nil
        tilt.stop()
    }

    /// One display frame. False stops the link.
    private func frame(_ time: Double) -> Bool {
        // A frame after a pause (a call, the app in the background) flies one
        // short step, not the whole gap.
        let dt = lastFrame.map { min(max(0, time - $0), 1.0 / 20) } ?? 0
        lastFrame = time
        run.step(input(), dt: dt)
        scene.update(run.flight)
        switch run.flight.outcome {
        case .flying:
            buzzForNewWarnings()
            return true
        case .landed(let landing):
            SRHaptic.ok()
            if book.noteLander(score: run.score, level: run.level) {
                newBest = true
                store.save(book)
            }
            stage = .landed(landing)
        case .crashed(let crash):
            SRHaptic.bad()
            book.recordLander(score: run.score, level: run.level)
            store.save(book)
            stage = .crashed(crash)
        }
        ticker = nil
        tilt.stop()
        return false
    }

    /// A short buzz the moment a warning appears: too fast near the ground,
    /// or the tank running low. Not again until it clears.
    private func buzzForNewWarnings() {
        let now = Set(run.flight.warnings)
        if now != warned {
            if now.subtracting(warned).contains(where: { $0 == .tooFast || $0 == .lowFuel }) {
                SRHaptic.select()
            }
            warned = now
        }
    }

    private func input() -> LanderInput {
        if scripted { return LanderAutopilot.input(for: run.flight) }
        let wanted: Double
        if steersByTilt {
            // A quarter-g of tilt is the full lean; a little in the middle is nothing.
            let raw = tilt.lean() ?? 0
            let live = abs(raw) < 0.03 ? 0 : raw
            wanted = min(max(live / 0.25, -1), 1) * LanderRules.maxTilt
        } else {
            wanted = leanHeld * LanderRules.maxTilt
        }
        lean += (wanted - lean) * 0.25
        return LanderInput(targetAngle: lean, throttle: thrustHeld ? 1 : 0)
    }
}

/// Lander: the 3D scene full screen, the instruments over it, and a card
/// between flights.
struct LanderScreen: View {
    @StateObject private var game = LanderGame()
    @State private var touching = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            LanderSceneView(controller: game.scene, active: game.stage != .briefing && !game.paused)
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel(sceneLabel)
                .accessibilityIdentifier("lander-scene")
            thrustLayer
            VStack(spacing: 8) {
                top
                Spacer(minLength: 0)
                bottom
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black)
        .navigationTitle(GameKind.lander.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: game.stage)
        .animation(.easeInOut(duration: 0.2), value: game.paused)
        .onDisappear { game.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.pause() }
        }
        .onChange(of: game.stage) { _, stage in announce(stage) }
        .accessibilityIdentifier("lander-screen")
    }

    /// Hold anywhere on the sky to burn.
    private var thrustLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !touching else { return }
                        touching = true
                        game.thrustHeld = true
                        if game.stage == .flying && !game.paused { SRHaptic.tap() }
                    }
                    .onEnded { _ in
                        touching = false
                        game.thrustHeld = false
                    }
            )
            .accessibilityHidden(true)
    }

    /// The instruments while a flight is under way. Between flights the
    /// card has the whole screen: on a small phone it needs it.
    @ViewBuilder
    private var top: some View {
        if game.stage == .flying {
            HStack(alignment: .top, spacing: 8) {
                LanderInstruments(run: game.run, best: game.book.landerBest)
                if !game.paused {
                    pauseButton
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            LanderFlightChips(flight: game.run.flight)
        }
    }

    @ViewBuilder
    private var bottom: some View {
        if game.paused {
            LanderCardHolder { pausedCard }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            switch game.stage {
            case .briefing:
                LanderCardHolder { briefing }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .flying:
                controls
            case .landed(let landing):
                LanderCardHolder { landedCard(landing) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .crashed(let crash):
                LanderCardHolder { crashedCard(crash) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var sceneLabel: String {
        let c = game.run.flight.craft
        let height = max(0, Int(game.run.flight.altitude.rounded()))
        return "Lander, level \(game.run.level). \(height) metres up, falling at \(String(format: "%.1f", max(0, -c.vy))) metres a second, \(Int(c.fuel.rounded())) fuel."
    }

    /// VoiceOver hears how each flight ended without hunting for the card.
    private func announce(_ stage: LanderGame.Stage) {
        let words: String
        switch stage {
        case .landed(let landing): words = "Landed. \(landing.points) points."
        case .crashed(let crash): words = "Crashed. \(crash.sentence)"
        case .flying: words = "Level \(game.run.level). Flying."
        case .briefing: return
        }
        UIAccessibility.post(notification: .announcement, argument: words)
    }

    private var pauseButton: some View {
        Button {
            SRHaptic.tap()
            game.pause()
        } label: {
            Image(systemName: "pause.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(SR.ink)
                .frame(width: 56, height: 56)
                .srGlassCard(.paper, radius: 28)
                .contentShape(Circle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel("Pause")
        .accessibilityIdentifier("lander-pause")
    }

    // MARK: - Cards

    private var briefing: some View {
        VStack(alignment: .leading, spacing: 14) {
            LanderBriefingArt()
                .frame(height: 118)
                .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("LANDER")
                    .font(SR.Text.label())
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(SR.accent)
                Text("Land softly on the lit pad.")
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 10) {
                LanderHowRow(icon: steeringIcon, text: steeringLine)
                LanderHowRow(icon: "flame.fill", text: "Hold a finger anywhere on the sky to fire the engine.")
                LanderHowRow(icon: "arrow.down.to.line",
                             text: "Touch down under \(String(format: "%.1f", LanderRules.safeVertical)) m/s, nearly upright, both feet on the pad.")
                LanderHowRow(icon: "star.fill", text: "Fuel left over scores. Each landing opens a harder level.")
            }
            if game.book.landerBest > 0 {
                HStack(spacing: 8) {
                    LanderStatChip(label: "BEST", value: game.book.landerBest.formatted())
                    LanderStatChip(label: "LEVEL", value: "\(game.book.landerBestLevel)")
                    LanderStatChip(label: "RUNS", value: "\(game.book.landerRuns)")
                }
            }
            Button {
                SRHaptic.tap()
                game.begin()
            } label: {
                SRButtonLabel(title: "Launch", icon: "arrow.down.to.line", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("lander-start")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private var steeringIcon: String {
        if game.scripted { return "airplane" }
        return game.steersByTilt ? "iphone" : "arrow.left.arrow.right"
    }

    private var steeringLine: String {
        if game.scripted { return "Demo: the autopilot flies." }
        return game.steersByTilt ? "Tilt the phone left and right to lean the craft." : "Hold the arrows to lean the craft."
    }

    private var pausedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PAUSED")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text("Level \(game.run.level) · \(game.run.flight.level.place)")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("The craft hangs where you left it. Touch down under \(String(format: "%.1f", LanderRules.safeVertical)) m/s, upright, on the pad.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                game.resume()
            } label: {
                SRButtonLabel(title: "Resume", icon: "play.fill", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("lander-resume")
            Button {
                SRHaptic.tap()
                game.begin()
            } label: {
                SRButtonLabel(title: "Start a new run", icon: "arrow.counterclockwise", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("lander-restart")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("lander-paused")
    }

    /// While flying: the lean buttons (no tilt sensor) or a recentre, and
    /// the engine light that says holding the sky burns.
    @ViewBuilder
    private var controls: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if !game.scripted && !game.steersByTilt {
                LanderHoldButton(icon: "arrow.counterclockwise", label: "Lean left") { game.leanHeld = $0 ? -1 : 0 }
                    .accessibilityIdentifier("lander-lean-left")
            }
            Spacer(minLength: 0)
            LanderEngineLight(burning: game.run.flight.craft.burning > 0.01, scripted: game.scripted,
                              empty: game.run.flight.craft.fuel <= 0)
            Spacer(minLength: 0)
            if !game.scripted && !game.steersByTilt {
                LanderHoldButton(icon: "arrow.clockwise", label: "Lean right") { game.leanHeld = $0 ? 1 : 0 }
                    .accessibilityIdentifier("lander-lean-right")
            } else if game.steersByTilt {
                Button {
                    SRHaptic.tap()
                    game.tilt.recentre()
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(SR.ink)
                        .frame(width: 56, height: 56)
                        .srGlassCard(.paper, radius: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(SRPressStyle())
                .accessibilityLabel("Make the way I'm holding the phone level")
                .accessibilityIdentifier("lander-recentre")
            }
        }
    }

    private func landedCard(_ landing: LanderLanding) -> some View {
        let parts = landing.breakdown(level: game.run.level, padHalfWidth: game.run.flight.terrain.padWidth / 2)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(landing.gentle ? "THE EAGLE HAS LANDED" : "SAFELY DOWN")
                        .font(SR.Text.label())
                        .tracking(SR.inkKickerTracking)
                        .foregroundStyle(SR.good)
                    Text("+\(landing.points)")
                        .font(SR.Text.figure(38))
                        .foregroundStyle(SR.ink)
                }
                Spacer(minLength: 8)
                LanderStars(count: parts.stars)
            }
            LanderBreakdown(parts: parts, level: game.run.level)
            Text(landedLine(landing))
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if game.newBest {
                Label("New best run: \(game.run.score.formatted())", systemImage: "trophy.fill")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.good)
            }
            LanderNextLevel(level: LanderLevel.make(game.run.level + 1))
            Button {
                SRHaptic.tap()
                game.nextLevel()
            } label: {
                SRButtonLabel(title: "Level \(game.run.level + 1): \(LanderLevel.make(game.run.level + 1).place)", icon: "arrow.right", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("lander-next")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("lander-landed")
    }

    private func landedLine(_ landing: LanderLanding) -> String {
        let speed = String(format: "%.1f", landing.vertical)
        let offset = Int(landing.offset.rounded()), fuel = Int(landing.fuelLeft.rounded())
        let run = game.run
        let landings = run.landings == 1 ? "1 landing" : "\(run.landings) landings"
        return "Down at \(speed) m/s, \(offset) m from the middle, \(fuel) fuel left. Run: \(run.score.formatted()) from \(landings)."
    }

    private func crashedCard(_ crash: LanderCrash) -> some View {
        let run = game.run
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: game.newBest ? "trophy.fill" : "xmark.octagon.fill")
                    .font(.system(size: 18, weight: .bold))
                    .accessibilityHidden(true)
                Text(game.newBest ? "NEW BEST" : "CRASHED")
                    .font(SR.Text.label())
                    .tracking(SR.inkKickerTracking)
            }
            .foregroundStyle(game.newBest ? SR.good : SR.error)
            Text(crash.sentence)
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(crashTip(crash))
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                LanderStatChip(label: "SCORE", value: run.score.formatted())
                LanderStatChip(label: "LEVEL", value: "\(run.level)")
                LanderStatChip(label: "BEST", value: game.book.landerBest.formatted())
            }
            Text(crashedLine)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                SRHaptic.tap()
                game.begin()
            } label: {
                SRButtonLabel(title: "Fly again", icon: "arrow.counterclockwise", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("lander-again")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("lander-crashed")
    }

    private var crashedLine: String {
        let run = game.run
        let landings = run.landings == 1 ? "1 landing" : "\(run.landings) landings"
        return "Run over on level \(run.level): \(run.score) points from \(landings). Best \(game.book.landerBest)."
    }

    /// One line on how to get it right next time.
    private func crashTip(_ crash: LanderCrash) -> String {
        switch crash {
        case .offPad: return "Follow the arrow to the pad, and the green beacon above it."
        case .tilted: return "Straighten up before the last few metres: the lean gauge goes green."
        case .tooFast: return "Burn in short bursts on the way down so the descent gauge stays green."
        case .sliding: return "Lean against the drift to stop moving sideways before you touch."
        }
    }
}

/// Keeps a card on screen whatever the text size: as it is when it fits,
/// scrolling when the reader's setting makes it taller than the room left.
struct LanderCardHolder<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
    }
}

/// One line of how to play: an icon in a tinted circle and the words.
struct LanderHowRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(SR.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(SR.accent.opacity(0.14)))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A small figure with its label: the best, the level reached.
struct LanderStatChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            Text(value)
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).fill(SR.ink.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

/// One to three stars for a landing, popping in one after another.
struct LanderStars: View {
    let count: Int
    @State private var shown = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                star(index)
            }
        }
        .onAppear {
            shown = 0
            let count = self.count
            Task { @MainActor in
                for index in 0..<count {
                    try? await Task.sleep(nanoseconds: index == 0 ? 250_000_000 : 220_000_000)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { shown = index + 1 }
                    SRHaptic.select()
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(count) of 3 stars")
    }

    private func star(_ index: Int) -> some View {
        let lit = index < shown
        return Image(systemName: lit ? "star.fill" : "star")
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(lit ? Color(red: 1, green: 0.78, blue: 0.2) : SR.inkGhost)
            .scaleEffect(lit ? 1 : 0.8)
    }
}

/// Where a landing's points came from, row by row.
struct LanderBreakdown: View {
    let parts: LanderScore
    let level: Int

    var body: some View {
        VStack(spacing: 6) {
            row("Landing on level \(level)", parts.base)
            row("Fuel kept", parts.fuel)
            row("Close to the middle", parts.precision)
            if parts.gentle > 0 { row("Gentle touch", parts.gentle) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).fill(SR.ink.opacity(0.06)))
    }

    private func row(_ title: String, _ points: Int) -> some View {
        HStack {
            Text(title)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
            Spacer(minLength: 8)
            Text("+\(points)")
                .font(SR.Text.title(15))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// What the next level holds: its gravity, its wind and its pad.
struct LanderNextLevel: View {
    let level: LanderLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NEXT · \(level.place.uppercased())")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 8) {
                LanderStatChip(label: "GRAVITY", value: String(format: "%.2f", level.gravity))
                LanderStatChip(label: "WIND", value: LanderWords.wind(level.wind))
                LanderStatChip(label: "PAD", value: "\(Int(level.padWidth.rounded())) m")
            }
        }
    }
}

/// Plain words for the numbers the screens share.
enum LanderWords {
    /// "None", or how strong and which way: "Light →".
    static func wind(_ wind: Double) -> String {
        guard wind != 0 else { return "None" }
        let strength = abs(wind) < 0.15 ? "Light" : abs(wind) < 0.24 ? "Steady" : "Strong"
        return "\(strength) \(wind > 0 ? "→" : "←")"
    }

    static func windLabel(_ wind: Double) -> String {
        guard wind != 0 else { return "No wind" }
        let strength = abs(wind) < 0.15 ? "Light" : abs(wind) < 0.24 ? "Steady" : "Strong"
        return "\(strength) wind blowing to the \(wind > 0 ? "right" : "left")"
    }
}

/// The instruments: level, score, and the three things that decide a
/// landing — how fast it is coming down, how fast it is drifting and how
/// far it leans — each green when safe to touch down, red when not, with a
/// word as well as a colour; then the height and the fuel.
struct LanderInstruments: View {
    let run: LanderRun
    let best: Int

    var body: some View {
        let flight = run.flight
        let c = flight.craft
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("LEVEL \(run.level) · \(flight.level.place.uppercased())")
                    .font(SR.Text.label())
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(SR.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text("\(run.score)")
                    .font(SR.Text.title(20))
                    .foregroundStyle(SR.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("Score \(run.score), best \(best)")
            }
            HStack(alignment: .top, spacing: 10) {
                LanderGauge(label: "DOWN", value: String(format: "%.1f", max(0, -c.vy)), unit: "m/s",
                            share: max(0, -c.vy) / (LanderRules.safeVertical * 2), safe: -c.vy <= LanderRules.safeVertical)
                LanderGauge(label: "DRIFT", value: String(format: "%.1f", abs(c.vx)), unit: "m/s",
                            share: abs(c.vx) / (LanderRules.safeHorizontal * 2), safe: abs(c.vx) <= LanderRules.safeHorizontal)
                LanderAttitude(angle: c.angle)
                LanderGauge(label: "HEIGHT", value: "\(max(0, Int(flight.altitude.rounded())))", unit: "m",
                            share: nil, safe: true)
            }
            LanderFuelBar(share: flight.fuelShare)
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 10)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lander-instruments")
    }
}

/// One instrument: a label, a number and its unit, and (for the speeds) a
/// short meter with the safe half marked, so a glance says "fine" or "too fast".
struct LanderGauge: View {
    let label: String
    let value: String
    let unit: String
    /// How far along the meter, where 0.5 is the safe limit; nil for no meter.
    let share: Double?
    let safe: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(label)
                    .font(SR.Text.label())
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
                if share != nil && !safe {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SR.error)
                        .accessibilityHidden(true)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(SR.Text.title(18))
                    .foregroundStyle(share == nil ? SR.ink : (safe ? SR.good : SR.error))
                    .monospacedDigit()
                Text(unit)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            if let share {
                meter(share)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        let verdict = share == nil ? "" : (safe ? ", safe" : ", too fast")
        return "\(label.capitalized) \(value) \(unit)\(verdict)"
    }

    private func meter(_ share: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(SR.ink.opacity(0.12))
                Capsule().fill(SR.good.opacity(0.35)).frame(width: w * 0.5)
                Capsule()
                    .fill(safe ? SR.good : SR.error)
                    .frame(width: max(4, w * CGFloat(min(1, max(0, share)))))
            }
        }
        .frame(height: 5)
    }
}

/// The craft's lean, drawn: a little lander glyph turned as the craft is,
/// green while it is upright enough to land.
struct LanderAttitude: View {
    let angle: Double

    var body: some View {
        let safe = abs(angle) <= LanderRules.safeAngle
        VStack(alignment: .leading, spacing: 3) {
            Text("LEAN")
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            ZStack {
                Circle().stroke(SR.ink.opacity(0.15), lineWidth: 2)
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(safe ? SR.good : SR.error)
                    .rotationEffect(.radians(angle))
            }
            .frame(width: 28, height: 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        guard abs(angle) > LanderRules.safeAngle else { return "Upright" }
        let degrees = Int((abs(angle) * 180 / Double.pi).rounded())
        let side = angle > 0 ? "right" : "left"
        return "Leaning \(degrees) degrees to the \(side)"
    }
}

/// The tank: a thick bar, its percentage, and LOW when under a fifth.
struct LanderFuelBar: View {
    let share: Double

    var body: some View {
        let low = share < LanderRules.lowFuelShare
        HStack(spacing: 8) {
            Image(systemName: "fuelpump.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(low ? SR.error : SR.inkMuted)
                .accessibilityHidden(true)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.ink.opacity(0.12))
                    Capsule()
                        .fill(low ? SR.error : SR.accent)
                        .frame(width: geo.size.width * CGFloat(min(max(share, 0), 1)))
                }
            }
            .frame(height: 10)
            Text(verbatim: low ? "LOW \(percent)%" : "\(percent)%")
                .font(SR.Text.mono())
                .foregroundStyle(low ? SR.error : SR.inkSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(low ? "Fuel \(percent) percent, low" : "Fuel \(percent) percent")
    }

    private var percent: Int { Int((min(max(share, 0), 1) * 100).rounded()) }
}

/// Under the instruments while flying: which way the pad is, the wind, and
/// the most urgent warning, if any.
struct LanderFlightChips: View {
    let flight: LanderFlight

    var body: some View {
        // One row when it fits; on a small phone or at a large text size the
        // warning drops under the pad and wind chips rather than squeezing them.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                padChip
                windChip
                Spacer(minLength: 0)
                warningChip
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    padChip
                    windChip
                }
                warningChip
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private var padOffset: Double { flight.terrain.padCentre - flight.craft.x }
    private var overPad: Bool { abs(padOffset) < flight.terrain.padWidth / 2 }

    private var padChip: some View {
        let dx = padOffset
        let over = overPad
        let metres = Int(abs(dx).rounded())
        let icon: String = over ? "arrow.down" : (dx > 0 ? "arrow.right" : "arrow.left")
        let text: String = over ? "PAD BELOW" : "PAD \(metres) m"
        let spoken: String = over ? "Over the pad" : "Pad \(metres) metres to the \(dx > 0 ? "right" : "left")"
        return chip(icon: icon, text: text, tone: over ? SR.good : SR.accentInk)
            .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private var windChip: some View {
        if flight.level.wind != 0 {
            chip(icon: "wind", text: LanderWords.wind(flight.level.wind).uppercased(), tone: SR.inkSecondary)
                .accessibilityLabel(LanderWords.windLabel(flight.level.wind))
        }
    }

    @ViewBuilder
    private var warningChip: some View {
        if let warning = flight.warnings.first {
            LanderWarningChip(warning: warning)
        }
    }

    private func chip(icon: String, text: String, tone: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(SR.Text.label())
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .srGlassCard(.paper, radius: 16)
    }
}

/// The most urgent warning, pulsing gently so it is seen without a stare.
struct LanderWarningChip: View {
    let warning: LanderWarning
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: warning.symbol)
                .font(.system(size: 12, weight: .bold))
            Text(warning.words.uppercased())
                .font(SR.Text.label())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(warning == .lowFuel ? SR.warn : SR.error))
        .opacity(pulse ? 0.75 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(warning.words)
        .accessibilityIdentifier("lander-warning")
    }
}

/// The engine's light: lit orange while it burns, and the reminder of how.
struct LanderEngineLight: View {
    let burning: Bool
    let scripted: Bool
    let empty: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: empty ? "exclamationmark.triangle.fill" : "flame.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(burning ? Color.white : Color.white.opacity(0.75))
                .accessibilityHidden(true)
            Text(words)
                .font(SR.Text.title(15))
                .foregroundStyle(Color.white.opacity(burning ? 1 : 0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(Capsule().fill(burning ? Color(red: 0.95, green: 0.45, blue: 0.1).opacity(0.9) : Color.black.opacity(0.45)))
        .scaleEffect(burning ? 1.05 : 1)
        .animation(.easeOut(duration: 0.12), value: burning)
        .accessibilityElement(children: .combine)
    }

    private var words: String {
        if scripted { return "Autopilot" }
        if empty { return "Out of fuel" }
        return burning ? "Engine on" : "Hold the sky to burn"
    }
}

/// The briefing's picture: a night sky, the ridge, the lit pad and the
/// craft coming down on a dotted path, its flame flickering.
struct LanderBriefingArt: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                LanderBriefingArt.draw(in: context, size: size, time: t)
            }
        }
    }

    private static let sky = Color(red: 0.04, green: 0.05, blue: 0.13)
    private static let rock = Color(red: 0.55, green: 0.53, blue: 0.50)
    private static let rim = Color(red: 0.82, green: 0.80, blue: 0.75)
    private static let green = Color(red: 0.35, green: 1, blue: 0.5)

    static func draw(in context: GraphicsContext, size: CGSize, time: Double) {
        let w = Double(size.width), h = Double(size.height)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(sky))
        var rng = LanderRandom(seed: 11)
        for _ in 0..<60 {
            let x = rng.double(in: 0...w), y = rng.double(in: 0...(h * 0.7))
            let r = rng.double(in: 0.5...1.6)
            let twinkle = 0.5 + 0.5 * sin(time * 2 + x)
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(.white.opacity(0.35 + 0.5 * twinkle * rng.unit())))
        }
        // The Earth, top right.
        let earth = CGRect(x: w - 52, y: 12, width: 28, height: 28)
        context.fill(Path(ellipseIn: earth.insetBy(dx: -3, dy: -3)), with: .color(Color(red: 0.4, green: 0.6, blue: 1).opacity(0.25)))
        context.fill(Path(ellipseIn: earth), with: .color(Color(red: 0.25, green: 0.5, blue: 0.95)))

        // The ridge, with a flat pad two thirds across.
        let padStart = w * 0.58, padEnd = w * 0.8, padY = h * 0.78
        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: h))
        let heights: [Double] = [0.70, 0.62, 0.74, 0.66, 0.72, 0.78, 0.78, 0.78, 0.68, 0.6, 0.7]
        for (i, f) in heights.enumerated() {
            let x = w * Double(i) / Double(heights.count - 1)
            let y = (x >= padStart && x <= padEnd) ? padY : h * f
            ground.addLine(to: CGPoint(x: x, y: y))
        }
        ground.addLine(to: CGPoint(x: w, y: h))
        ground.closeSubpath()
        context.fill(ground, with: .linearGradient(Gradient(colors: [rim, rock, Color(red: 0.15, green: 0.15, blue: 0.18)]),
                                                   startPoint: CGPoint(x: 0, y: h * 0.6), endPoint: CGPoint(x: 0, y: h)))
        context.fill(Path(CGRect(x: padStart, y: padY - 2, width: padEnd - padStart, height: 3)), with: .color(.white.opacity(0.9)))
        let blink = 0.5 + 0.5 * sin(time * 4)
        for x in [padStart, padEnd] {
            context.fill(Path(CGRect(x: x - 0.75, y: padY - 12, width: 1.5, height: 10)), with: .color(.gray))
            context.fill(Path(ellipseIn: CGRect(x: x - 3, y: padY - 16, width: 6, height: 6)), with: .color(green.opacity(0.4 + 0.6 * blink)))
        }

        // The path in, dotted, and the craft on it, bobbing.
        let padMid = (padStart + padEnd) / 2
        var route = Path()
        route.move(to: CGPoint(x: w * 0.12, y: h * 0.18))
        route.addQuadCurve(to: CGPoint(x: padMid, y: padY - 10), control: CGPoint(x: padMid, y: h * 0.12))
        context.stroke(route, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))
        let bob = sin(time * 1.6) * 3
        let craft = CGPoint(x: padMid - w * 0.06, y: h * 0.36 + bob)
        drawCraft(in: context, at: craft, flicker: 0.8 + 0.2 * sin(time * 30))
    }

    private static func drawCraft(in context: GraphicsContext, at p: CGPoint, flicker: Double) {
        var c = context
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(0.12))
        // The flame, under everything.
        var flame = Path()
        flame.move(to: CGPoint(x: -4, y: 9))
        flame.addLine(to: CGPoint(x: 4, y: 9))
        flame.addLine(to: CGPoint(x: 0, y: 9 + 16 * flicker))
        flame.closeSubpath()
        c.fill(flame, with: .color(Color(red: 1, green: 0.6, blue: 0.2)))
        var core = Path()
        core.move(to: CGPoint(x: -2, y: 9))
        core.addLine(to: CGPoint(x: 2, y: 9))
        core.addLine(to: CGPoint(x: 0, y: 9 + 8 * flicker))
        core.closeSubpath()
        c.fill(core, with: .color(Color(red: 1, green: 0.95, blue: 0.7)))
        // Legs, the gold stage, the silver cabin and its window.
        var legs = Path()
        legs.move(to: CGPoint(x: -6, y: 4)); legs.addLine(to: CGPoint(x: -10, y: 12))
        legs.move(to: CGPoint(x: 6, y: 4)); legs.addLine(to: CGPoint(x: 10, y: 12))
        c.stroke(legs, with: .color(.gray), lineWidth: 1.5)
        c.fill(Path(roundedRect: CGRect(x: -8, y: 0, width: 16, height: 8), cornerRadius: 1.5),
               with: .color(Color(red: 0.85, green: 0.65, blue: 0.22)))
        c.fill(Path(ellipseIn: CGRect(x: -6.5, y: -11, width: 13, height: 13)), with: .color(Color(white: 0.86)))
        c.fill(Path(ellipseIn: CGRect(x: -2.5, y: -7, width: 5, height: 5)), with: .color(Color(red: 0.5, green: 0.85, blue: 1)))
    }
}

/// A button that is "on" while a finger holds it: the lean arrows when the
/// phone has no tilt sensor.
struct LanderHoldButton: View {
    let icon: String
    let label: String
    let changed: (Bool) -> Void
    @State private var held = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(held ? SR.paper : SR.ink)
            .frame(width: 84, height: 84)
            .background(Circle().fill(held ? SR.accentDeep : Color.clear))
            .srGlassCard(.paper, radius: 42)
            .scaleEffect(held ? 0.92 : 1)
            .animation(.easeOut(duration: 0.1), value: held)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !held {
                            held = true
                            SRHaptic.select()
                            changed(true)
                        }
                    }
                    .onEnded { _ in
                        held = false
                        changed(false)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }
}
