import SwiftUI

/// Orbit: gravity-slingshot puzzles. The level list first; a level opens on
/// the field with its briefing, then the aim, the flight and a card at the
/// end. Pushed on the Games stack with the tab bar hidden, like Lander.
struct OrbitScreen: View {
    @StateObject private var game = OrbitGame()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .navigationTitle(GameKind.orbit.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .navigationBarBackButtonHidden(game.stage != .levels)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if game.stage != .levels {
                        Button {
                            SRHaptic.tap()
                            game.showLevels()
                        } label: {
                            Label("Levels", systemImage: "chevron.backward")
                                .labelStyle(.titleAndIcon)
                        }
                        .accessibilityIdentifier("orbit-levels")
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { game.foreground() } else { game.background() }
            }
            .onDisappear { game.background() }
            .accessibilityIdentifier("orbit-screen")
    }

    @ViewBuilder
    private var content: some View {
        if game.stage == .levels {
            OrbitLevelsView(game: game)
        } else {
            OrbitPlayView(game: game, calm: reduceMotion)
        }
    }
}

/// A level in play: the bar along the top, the field, the controls along
/// the bottom, and whatever card the stage calls for over them.
struct OrbitPlayView: View {
    @ObservedObject var game: OrbitGame
    let calm: Bool

    var body: some View {
        VStack(spacing: 0) {
            OrbitHUDBar(game: game)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 6)
            field
            controls
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .background(OrbitPaint.spaceDeep.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            // A long card (level 1's, or large text on a small phone)
            // scrolls rather than running off the top.
            ViewThatFits(in: .vertical) {
                paddedCard
                ScrollView {
                    paddedCard
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .animation(calm ? nil : .snappy(duration: 0.3), value: game.stage)
        .animation(calm ? nil : .snappy(duration: 0.25), value: game.paused)
    }

    // MARK: - Field

    private var field: some View {
        ZStack(alignment: .top) {
            OrbitFieldView(scene: game.scene, calm: calm) { step in
                game.nudge(degrees: Double(step))
            }
            .gesture(aimGesture)
            OrbitAimReadout(scene: game.scene)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .allowsHitTesting(false)
            if let toast = game.toast {
                OrbitToastView(toast: toast)
                    .padding(.top, 44)
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .id(toast.id)
                    .allowsHitTesting(false)
            }
        }
        .animation(calm ? nil : .snappy(duration: 0.25), value: game.toast)
        .clipped()
    }

    private var aimGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                game.pull(dx: Double(value.translation.width), dy: Double(value.translation.height))
            }
    }

    // MARK: - Controls

    private var playing: Bool { game.stage == .playing && !game.paused }

    @ViewBuilder
    private var controls: some View {
        ZStack {
            if playing && game.hud.flying {
                OrbitFlightControls(game: game)
            } else if playing {
                OrbitAimControls(game: game)
            } else {
                Color.clear
            }
        }
        .frame(height: 62)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    // MARK: - Cards

    private var paddedCard: some View {
        card
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
    }

    @ViewBuilder
    private var card: some View {
        if game.paused {
            OrbitPauseCard(game: game)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            switch game.stage {
            case .briefing:
                OrbitBriefingCard(game: game)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .outOfProbes:
                OrbitOutOfProbesCard(game: game)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .finished(let finish):
                OrbitResultsCard(game: game, finish: finish)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .levels, .playing:
                EmptyView()
            }
        }
    }
}

/// The bar over the field: which level, the probes left, the stars picked
/// up, and the pause button.
struct OrbitHUDBar: View {
    @ObservedObject var game: OrbitGame

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LEVEL \(game.levelNumber) · \(game.level.system.title.uppercased())")
                    .font(SR.Text.label())
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(OrbitPaint.aim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(game.level.name)
                    .font(SR.Text.title())
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                probes
                stars
            }
            pauseButton
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var probes: some View {
        HStack(spacing: 3) {
            ForEach(0..<OrbitPhysics.probes, id: \.self) { i in
                Capsule()
                    .fill(i < game.hud.probesLeft ? OrbitPaint.aim : Color.white.opacity(0.18))
                    .frame(width: 9, height: 14)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(game.hud.probesLeft) of \(OrbitPhysics.probes) probes left")
        .accessibilityIdentifier("orbit-probes")
    }

    private var stars: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(OrbitPaint.gold)
            Text("\(game.hud.starsGot)/\(game.hud.starsTotal)")
                .font(SR.Text.mono(13))
                .foregroundStyle(Color.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.hud.starsGot) of \(game.hud.starsTotal) stars picked up")
    }

    private var pauseButton: some View {
        Button {
            SRHaptic.tap()
            if game.paused { game.resume() } else { game.pause() }
        } label: {
            Image(systemName: game.paused ? "play.fill" : "pause.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(SRPressStyle())
        .disabled(game.stage != .playing)
        .opacity(game.stage == .playing ? 1 : 0.4)
        .accessibilityLabel(game.paused ? "Resume" : "Pause")
        .accessibilityIdentifier("orbit-pause")
    }
}

/// The aim, in numbers, over the corner of the field while aiming.
struct OrbitAimReadout: View {
    @ObservedObject var scene: OrbitScene

    var body: some View {
        if scene.run.isAiming {
            HStack(spacing: 10) {
                Label(OrbitAimWords.bearing(scene.run.aim), systemImage: "location.north.line.fill")
                Label("\(scene.run.aim.percent)%", systemImage: "bolt.fill")
            }
            .font(SR.Text.mono(13))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.4)))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityHidden(true)
        }
    }
}

/// The aim put into words for the read-out and for VoiceOver.
enum OrbitAimWords {
    /// Compass degrees on the screen, one decimal: 0 is straight up, 90 right.
    static func bearing(_ shot: OrbitShot) -> String {
        var d = (shot.angle + Double.pi / 2) * 180 / Double.pi
        d = d.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        if d >= 359.95 { d = 0 }
        return String(format: "%.1f°", d)
    }
}

/// A line over the field after a flight.
struct OrbitToastView: View {
    let toast: OrbitToast

    var body: some View {
        Text(toast.text)
            .font(SR.Text.bodyMedium(15))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill((toast.good ? OrbitPaint.dock : OrbitPaint.danger).opacity(0.32)))
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .overlay(Capsule().stroke((toast.good ? OrbitPaint.dock : OrbitPaint.danger).opacity(0.6), lineWidth: 1))
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .accessibilityIdentifier("orbit-toast")
    }
}

/// While aiming: turn and power, a step a press (held, they repeat), with
/// the launch between them.
struct OrbitAimControls: View {
    @ObservedObject var game: OrbitGame

    var body: some View {
        HStack(spacing: 6) {
            OrbitRepeatButton(icon: "arrow.counterclockwise", caption: "TURN", label: "Turn left") {
                game.nudge(degrees: -0.5)
            }
            .accessibilityIdentifier("orbit-turn-left")
            OrbitRepeatButton(icon: "arrow.clockwise", caption: "TURN", label: "Turn right") {
                game.nudge(degrees: 0.5)
            }
            .accessibilityIdentifier("orbit-turn-right")
            launchButton
            OrbitRepeatButton(icon: "minus", caption: "POWER", label: "Less power") {
                game.nudge(power: -0.01)
            }
            .accessibilityIdentifier("orbit-power-down")
            OrbitRepeatButton(icon: "plus", caption: "POWER", label: "More power") {
                game.nudge(power: 0.01)
            }
            .accessibilityIdentifier("orbit-power-up")
        }
        // Between a flight ending and the next probe being ready.
        .opacity(game.canAim ? 1 : 0.45)
        .allowsHitTesting(game.canAim)
    }

    private var launchButton: some View {
        Button {
            game.launch()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "paperplane.fill")
                Text("LAUNCH")
                    .font(SR.Text.label(15))
                    .tracking(1.2)
            }
            .font(.body.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                Capsule().fill(LinearGradient(colors: [OrbitPaint.goldDeep, OrbitPaint.rgb(0.92, 0.30, 0.45)],
                                              startPoint: .leading, endPoint: .trailing))
            )
            .shadow(color: OrbitPaint.goldDeep.opacity(0.45), radius: 10, x: 0, y: 2)
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel("Launch")
        .accessibilityHint("\(game.hud.probesLeft) probes left")
        .accessibilityIdentifier("orbit-launch")
    }
}

/// While a probe is in the air: call it off, its battery, and double speed.
struct OrbitFlightControls: View {
    @ObservedObject var game: OrbitGame

    var body: some View {
        HStack(spacing: 10) {
            OrbitRoundButton(icon: "xmark", caption: "CALL OFF", label: "Call the probe off") {
                game.callOff()
            }
            .accessibilityIdentifier("orbit-call-off")
            OrbitFlightGauge(scene: game.scene)
            OrbitRoundButton(icon: game.fast ? "forward.fill" : "play.fill", caption: game.fast ? "FAST" : "NORMAL",
                             label: game.fast ? "Fly at normal speed" : "Fly at double speed", lit: game.fast) {
                game.fast.toggle()
            }
            .accessibilityIdentifier("orbit-fast")
        }
    }
}

/// The probe's battery, draining as it flies.
struct OrbitFlightGauge: View {
    @ObservedObject var scene: OrbitScene

    var body: some View {
        let left = scene.run.battery
        let tone: Color = left < 0.25 ? OrbitPaint.danger : OrbitPaint.dock
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("BATTERY")
                    .font(SR.Text.label())
                    .foregroundStyle(Color.white.opacity(0.7))
                Spacer(minLength: 4)
                Text("\(Int((left * scene.run.level.timeLimit).rounded(.up))) s")
                    .font(SR.Text.mono(13))
                    .foregroundStyle(Color.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(tone)
                        .frame(width: max(6, geo.size.width * CGFloat(left)))
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(Int((left * 100).rounded())) percent")
    }
}

/// A round control with a caption, for the flight row.
struct OrbitRoundButton: View {
    let icon: String
    let caption: String
    let label: String
    var lit = false
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            OrbitControlFace(icon: icon, caption: caption, lit: lit, held: false)
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(label)
    }
}

/// What the small controls look like: an icon over a caption in a soft tile.
struct OrbitControlFace: View {
    let icon: String
    let caption: String
    var lit = false
    var held = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
            Text(caption)
                .font(SR.Text.label(10))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .foregroundStyle(lit ? OrbitPaint.spaceDeep : Color.white)
        .frame(width: 58, height: 58)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(lit ? OrbitPaint.dock : Color.white.opacity(held ? 0.26 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .scaleEffect(held ? 0.94 : 1)
    }
}

/// A control that fires once when pressed and then keeps firing while it is
/// held, for fine aiming. The repeat lives only as long as the finger does.
struct OrbitRepeatButton: View {
    let icon: String
    let caption: String
    let label: String
    let action: () -> Void
    @State private var held = false
    @State private var repeater: Task<Void, Never>?
    /// True only while the finger is down. Unlike `onEnded`, it also goes
    /// back to false when the system cancels the touch (a call, an alert, a
    /// control switched off under the finger), so the repeat cannot run on.
    @GestureState private var pressing = false

    var body: some View {
        OrbitControlFace(icon: icon, caption: caption, held: held)
            .contentShape(Rectangle())
            .gesture(press)
            .onChange(of: pressing) { _, down in
                if !down {
                    held = false
                    stopRepeating()
                }
            }
            .onDisappear { stopRepeating() }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($pressing) { _, state, _ in state = true }
            .onChanged { _ in
                guard !held else { return }
                held = true
                SRHaptic.select()
                action()
                startRepeating()
            }
            .onEnded { _ in
                held = false
                stopRepeating()
            }
    }

    private func startRepeating() {
        repeater?.cancel()
        let fire = action
        repeater = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 380_000_000)
            while !Task.isCancelled {
                fire()
                try? await Task.sleep(nanoseconds: 70_000_000)
            }
        }
    }

    private func stopRepeating() {
        repeater?.cancel()
        repeater = nil
    }
}
