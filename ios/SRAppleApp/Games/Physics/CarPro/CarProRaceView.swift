import SwiftUI

/// The circuit, drawn each frame from the race's world.
struct CarProTrackCanvas: View {
    let world: CarProRaceWorld
    /// The frame count: a new one redraws the canvas.
    let tick: Int

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            CarProRenderer.draw(world, in: &context, size: size)
        }
    }
}

/// A session on the circuit: the track full screen, the instruments and the
/// controls over it, the intro card before the start, the pause card, and
/// the flag. What the result means is the caller's (`onFinish` on the
/// controller); this only ever leaves through `leave`.
struct CarProRaceView: View {
    @ObservedObject var race: CarProRaceController
    /// The session's name for the cards: "Round 2 · Old Town Streets".
    let title: String
    /// One line under it on the intro card.
    let line: String
    /// Back out before the start, or after retiring.
    let leave: () -> Void
    @State private var confirmRetire = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            CarProTrackCanvas(world: race.world, tick: race.tick)
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel(sceneLabel)
                .accessibilityIdentifier("car-pro-track")
            if race.stage == .running {
                playLayer
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .transition(.opacity)
            }
            if race.stage == .ready {
                CarProCardScrim {
                    CarProReadyCard(race: race, title: title, line: line, start: { race.begin() }, back: leave)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if race.paused {
                CarProCardScrim {
                    pauseCard
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.black)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: race.stage)
        .animation(.easeInOut(duration: 0.2), value: race.paused)
        .onDisappear { race.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { race.pause() }
        }
        .confirmationDialog(retireTitle, isPresented: $confirmRetire, titleVisibility: .visible) {
            Button(retireButton, role: .destructive) {
                race.retire()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text(retireMessage)
        }
        .accessibilityIdentifier("car-pro-race")
    }

    private var sceneLabel: String {
        let hud = race.hud
        var words = "\(race.session.track.name). "
        if race.config.kind.isRace { words += "Position \(hud.position) of \(hud.cars). " }
        words += "\(CarProPresent.speed(hud.speed, mph: race.mph)) \(CarProPresent.spokenUnit(mph: race.mph))."
        return words
    }

    // MARK: - Driving

    private var playLayer: some View {
        VStack(spacing: 8) {
            top
            bannerSlot
            Spacer(minLength: 0)
            middle
            Spacer(minLength: 0)
            CarProDashboard(hud: race.hud, mph: race.mph, assists: race.config.assists,
                            compound: race.session.player.params.compound, tick: race.tick)
            CarProControlDeck(race: race)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var top: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 8) {
                roundButton(icon: "pause.fill", label: "Pause", id: "car-pro-pause") { race.pause() }
                    .disabled(race.sinceFlag != nil)
                if race.steering == .tilt && !race.scripted {
                    roundButton(icon: "scope", label: "Make the way I'm holding the phone straight ahead",
                                id: "car-pro-recentre") { race.recentre() }
                }
            }
            CarProTimingPanel(hud: race.hud, isRace: race.config.kind.isRace)
            CarProMinimap(world: race.world, tick: race.tick)
                .frame(width: 92, height: 92)
        }
    }

    @ViewBuilder
    private var bannerSlot: some View {
        ZStack {
            if let banner = race.banner {
                CarProBannerView(banner: banner)
                    .id(banner.title + (banner.detail ?? ""))
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(height: 52)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: race.banner)
    }

    /// The lights on the grid, and the flag at the end.
    @ViewBuilder
    private var middle: some View {
        let session = race.session
        if countingDown {
            CarProStartLights(lit: session.lightsLit, out: false)
                .transition(.scale.combined(with: .opacity))
        } else if session.config.kind.isRace && session.time < 0.8 && race.sinceFlag == nil {
            CarProStartLights(lit: 5, out: true)
                .transition(.opacity)
        } else if race.sinceFlag != nil {
            CarProFlagBadge(place: session.config.kind.isRace ? session.player.position : nil,
                            time: session.player.lastLap)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }

    private var countingDown: Bool {
        if case .countdown = race.session.phase { return true }
        return false
    }

    private func roundButton(icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(SR.Text.title(19))
                .foregroundStyle(Color.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(CarProHUDStyle.panel))
                .overlay(Circle().stroke(CarProHUDStyle.rim, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    // MARK: - Paused

    private var pauseCard: some View {
        let hud = race.hud
        return VStack(alignment: .leading, spacing: 16) {
            SRPageHeader(kicker: "\(race.purpose.title) · \(race.session.track.name)", title: "Paused",
                         strap: pausedLine(hud))
            if race.purpose == .timeTrial, let last = race.session.lastTelemetry, !last.speeds.isEmpty {
                CarProTelemetryChart(last: last, best: race.session.bestTelemetry, track: race.session.track, mph: race.mph)
            }
            VStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    race.resume()
                } label: {
                    SRButtonLabel(title: "Carry on", icon: "play.fill", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("car-pro-resume")
                Button {
                    SRHaptic.tap()
                    race.restart()
                } label: {
                    SRButtonLabel(title: race.config.kind.isRace ? "Restart from the grid" : "Start again", icon: "arrow.counterclockwise",
                                  fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("car-pro-restart")
                Button(role: .destructive) {
                    confirmRetire = true
                } label: {
                    SRButtonLabel(title: retireButton, icon: "flag.slash.fill", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("car-pro-retire")
            }
        }
    }

    private func pausedLine(_ hud: CarProHUD) -> String {
        var words = hud.laps > 0 ? "Lap \(hud.lap) of \(hud.laps)" : "Lap \(hud.lap)"
        if race.config.kind.isRace { words += ", running \(CarProFormat.ordinal(hud.position))" }
        if let best = hud.bestLap { words += ". Best lap \(CarProFormat.time(best))" }
        return words + "."
    }

    private var retireButton: String {
        switch race.purpose {
        case .championship, .quickRace: return "Retire"
        case .qualifying: return "End qualifying"
        case .timeTrial: return "End session"
        }
    }

    private var retireTitle: String {
        switch race.purpose {
        case .championship, .quickRace: return "Retire from the race?"
        case .qualifying: return "End qualifying now?"
        case .timeTrial: return "End the session?"
        }
    }

    private var retireMessage: String {
        switch race.purpose {
        case .championship: return "You'll be classified as not finishing and score no points this round."
        case .quickRace: return "The race ends here with no result for you."
        case .qualifying: return "Your best lap so far sets your grid place. No lap: you start from the back."
        case .timeTrial: return "Your laps and any new best are kept."
        }
    }
}

/// A dark wash over the circuit with a card rising from the bottom.
struct CarProCardScrim<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            ScrollView {
                content
                    .padding(SR.cardPadding + 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .srGlassCard(.paper)
                    .padding(.horizontal, 16)
                    .padding(.top, 60)
                    .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.bottom)
        }
    }
}

/// The intro card: what this session is, how to drive, and Start.
struct CarProReadyCard: View {
    @ObservedObject var race: CarProRaceController
    let title: String
    let line: String
    let start: () -> Void
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SRPageHeader(kicker: "\(race.purpose.title) · \(race.session.track.name)", title: title, strap: line)
            CarProHowToDrive(steering: race.steering, assists: race.config.assists, isRace: race.config.kind.isRace)
            VStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    start()
                } label: {
                    SRButtonLabel(title: race.config.kind.isRace ? "To the grid" : "Go", icon: "flag.checkered", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("car-pro-start")
                Button {
                    back()
                } label: {
                    SRButtonLabel(title: "Back", icon: "chevron.backward", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("car-pro-back")
            }
        }
    }
}

/// How to drive, one line per control, for the chosen steering and aids.
struct CarProHowToDrive: View {
    let steering: CarProSteeringMode
    let assists: CarProAssists
    let isRace: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(steerIcon, steerLine)
            row("dial.high.fill", "The throttle and brake are pedals: press higher up a pedal to press it harder.")
            if assists.autoGears {
                row("gearshape.2.fill", "The gears change themselves. Hold the brake at a standstill to reverse.")
            } else {
                row("plus.forwardslash.minus", "You change gear with Up and Down. Change up as the lights over the revs fill.")
            }
            row("exclamationmark.triangle.fill", "Four wheels off the track deletes the lap\(isRace ? ". Three warnings is a 5 second penalty" : "").")
            if assists.racingLine {
                row("point.topleft.down.to.point.bottomright.curvepath.fill", "Follow the line: green is throttle, amber hold your speed, red brake.")
            }
            row("thermometer.medium", "Tyres grip best warm (green). Sliding heats them and wears them out.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var steerIcon: String {
        switch steering {
        case .tilt: return "iphone.gen3.radiowaves.left.and.right"
        case .wheel: return "steeringwheel"
        case .slider: return "arrow.left.and.right"
        }
    }

    private var steerLine: String {
        switch steering {
        case .tilt: return "Tilt to steer, like holding a wheel. The target button straightens it up."
        case .wheel: return "Turn the wheel with your left thumb. Let go and it centres."
        case .slider: return "Slide your left thumb left and right to steer. Let go to straighten."
        }
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(SR.Text.title(15))
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

/// The chequered flag in the middle of the screen as the session ends.
struct CarProFlagBadge: View {
    let place: Int?
    let time: Double?
    @State private var shown = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .font(SR.Text.title(24))
                Text(place.map { "P\($0)" } ?? "FINISH")
                    .font(SR.Text.display(28))
                    .tracking(1.5)
            }
            if let time {
                Text("Last lap \(CarProFormat.time(time))")
                    .font(SR.Text.mono(14))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.75)))
        .overlay(alignment: .top) {
            CarProChequer()
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .padding(.horizontal, 16)
        }
        .scaleEffect(shown ? 1 : 0.5)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { shown = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(place.map { "Chequered flag. You finished \(CarProFormat.ordinal($0))" } ?? "Session over")
    }
}

/// A strip of black and white squares.
struct CarProChequer: View {
    var body: some View {
        Canvas { context, size in
            let cell = max(2, Double(size.height) / 2)
            let columns = Int(Double(size.width) / cell) + 1
            for column in 0..<columns {
                for row in 0..<2 {
                    let rect = CGRect(x: Double(column) * cell, y: Double(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color((column + row) % 2 == 0 ? .white : .black))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
