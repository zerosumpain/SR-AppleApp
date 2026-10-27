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
        stage = .flying
        lean = 0
        lastFrame = nil
        scene.update(run.flight)
        tilt.start()
        guard ticker == nil else { return }
        let ticker = FrameTicker { [weak self] time in
            guard let self else { return false }
            return self.frame(time)
        }
        self.ticker = ticker
        ticker.start()
    }

    /// Off screen, or the flight is over: the display link and the sensor stop.
    func stop() {
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
            return true
        case .landed(let landing):
            SRHaptic.ok()
            stage = .landed(landing)
        case .crashed(let crash):
            SRHaptic.bad()
            newBest = book.recordLander(score: run.score, level: run.level)
            store.save(book)
            stage = .crashed(crash)
        }
        ticker = nil
        tilt.stop()
        return false
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

    var body: some View {
        ZStack {
            LanderSceneView(controller: game.scene)
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel(sceneLabel)
                .accessibilityIdentifier("lander-scene")
            // Hold anywhere on the sky to burn.
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !touching { touching = true; game.thrustHeld = true }
                        }
                        .onEnded { _ in
                            touching = false
                            game.thrustHeld = false
                        }
                )
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                LanderInstruments(run: game.run, best: game.book.landerBest)
                Spacer(minLength: 0)
                switch game.stage {
                case .briefing: briefing
                case .flying: controls
                case .landed(let landing): landedCard(landing)
                case .crashed(let crash): crashedCard(crash)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black)
        .navigationTitle(GameKind.lander.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear { game.stop() }
        .accessibilityIdentifier("lander-screen")
    }

    private var sceneLabel: String {
        let c = game.run.flight.craft
        let height = max(0, Int(game.run.flight.altitude.rounded()))
        return "Lander, level \(game.run.level). \(height) metres up, falling at \(String(format: "%.1f", max(0, -c.vy))) metres a second, \(Int(c.fuel.rounded())) fuel."
    }

    // MARK: - Cards

    private var briefing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LANDER")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text("Land softly on the lit pad.")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                rule(game.scripted ? "Demo: the autopilot flies." : game.steersByTilt
                     ? "Tilt the phone left and right to lean the craft." : "Hold the arrows to lean the craft.")
                rule("Hold a finger anywhere on the sky to fire the engine.")
                rule("Touch down under \(String(format: "%.1f", LanderRules.safeVertical)) m/s, nearly upright, both feet on the pad.")
                rule("Fuel left over scores. Each landing opens a harder level.")
            }
            Button {
                SRHaptic.tap()
                game.begin()
            } label: {
                SRButtonLabel(title: "Launch", icon: "arrow.down.to.line", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("lander-start")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
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

    /// While flying: the lean buttons (no tilt sensor) or a recentre, and a
    /// reminder that holding the sky burns.
    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            if !game.scripted && !game.steersByTilt {
                LanderHoldButton(icon: "arrow.counterclockwise", label: "Lean left") { game.leanHeld = $0 ? -1 : 0 }
                    .accessibilityIdentifier("lander-lean-left")
            }
            Spacer(minLength: 0)
            Text(game.scripted ? "Autopilot" : "Hold the sky to burn")
                .font(SR.Text.mono())
                .foregroundStyle(Color.white.opacity(0.75))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.35)))
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
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: SR.tapTarget, height: SR.tapTarget)
                }
                .srButton(.regular)
                .accessibilityLabel("Make the way I'm holding the phone level")
                .accessibilityIdentifier("lander-recentre")
            }
        }
    }

    private func landedCard(_ landing: LanderLanding) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(landing.gentle ? "THE EAGLE HAS LANDED" : "SAFELY DOWN")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.good)
            Text("+\(landing.points)")
                .font(SR.Text.figure(34))
                .foregroundStyle(SR.ink)
            Text(landedLine(landing))
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                SRHaptic.tap()
                game.nextLevel()
            } label: {
                SRButtonLabel(title: "Level \(game.run.level + 1): \(LanderLevel.make(game.run.level + 1).place)", icon: "arrow.right", fill: true)
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
        let bonus = landing.gentle ? " — a gentle one, +50" : ""
        return "Down at \(speed) m/s, \(offset) m from the middle, \(fuel) fuel left\(bonus)."
    }

    private var crashedLine: String {
        let run = game.run
        let landings = run.landings == 1 ? "1 landing" : "\(run.landings) landings"
        return "Run over on level \(run.level): \(run.score) points from \(landings). Best \(game.book.landerBest)."
    }

    private func crashedCard(_ crash: LanderCrash) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(game.newBest ? "NEW BEST" : "CRASHED")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(game.newBest ? SR.good : SR.error)
            Text(crash.sentence)
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(crashedLine)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                SRHaptic.tap()
                game.begin()
            } label: {
                SRButtonLabel(title: "Fly again", icon: "arrow.counterclockwise", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("lander-again")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("lander-crashed")
    }
}

/// The instruments: level, score, height, the two speeds (red when too fast
/// to land), fuel, and which way the pad is.
struct LanderInstruments: View {
    let run: LanderRun
    let best: Int

    var body: some View {
        let flight = run.flight
        let c = flight.craft
        let dx = flight.terrain.padCentre - c.x
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
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .monospacedDigit()
                    .accessibilityLabel("Score \(run.score), best \(best)")
            }
            HStack(spacing: 14) {
                gauge("HEIGHT", "\(max(0, Int(flight.altitude.rounded()))) m", tone: SR.ink)
                gauge("DOWN", String(format: "%.1f", max(0, -c.vy)), tone: -c.vy > LanderRules.safeVertical ? SR.error : SR.good)
                gauge("ACROSS", String(format: "%.1f", abs(c.vx)), tone: abs(c.vx) > LanderRules.safeHorizontal ? SR.error : SR.good)
                Spacer(minLength: 0)
                padPointer(dx)
            }
            fuelBar(c.fuel / max(1, flight.level.fuel))
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 10)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lander-instruments")
    }

    private func gauge(_ label: String, _ value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SR.Text.label(11))
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            Text(value)
                .font(SR.Text.mono(15))
                .foregroundStyle(tone)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// An arrow towards the pad and how far, or "below" once over it.
    private func padPointer(_ dx: Double) -> some View {
        let over = abs(dx) < run.flight.terrain.padWidth / 2
        return HStack(spacing: 4) {
            Image(systemName: over ? "arrow.down" : (dx > 0 ? "arrow.right" : "arrow.left"))
                .font(.system(size: 13, weight: .bold))
            Text(over ? "PAD" : "\(Int(abs(dx).rounded())) m")
                .font(SR.Text.mono(13))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(over ? SR.good : SR.accentInk)
        .accessibilityLabel(over ? "Over the pad" : "Pad \(Int(abs(dx).rounded())) metres to the \(dx > 0 ? "right" : "left")")
    }

    private func fuelBar(_ share: Double) -> some View {
        HStack(spacing: 8) {
            Text("FUEL")
                .font(SR.Text.label(11))
                .foregroundStyle(SR.inkMuted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.ink.opacity(0.1))
                    Capsule()
                        .fill(share < 0.2 ? SR.error : SR.accent)
                        .frame(width: geo.size.width * CGFloat(min(max(share, 0), 1)))
                }
            }
            .frame(height: 6)
        }
        .accessibilityLabel("Fuel \(Int((share * 100).rounded())) percent")
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
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(SR.ink)
            .frame(width: 64, height: 64)
            .srGlassCard(.paper, radius: 32)
            .scaleEffect(held ? 0.92 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !held { held = true; changed(true) }
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
