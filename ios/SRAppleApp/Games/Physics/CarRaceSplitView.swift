import SwiftUI
import UIKit

/// A split-screen race on this phone: a display link that turns what each
/// player is holding into the rules' `CarSplitRace.step`, eases every
/// camera behind its car and says when the race is over. The demo's pilots
/// drive every car, and nobody's fingers count. A pause stops the clock for
/// everyone: the lights-out time moves on by however long it lasted, so the
/// race (and every ghost it records) carries on as if it had not happened.
@MainActor
final class CarSplitDriver: ObservableObject {
    enum Phase: Equatable {
        /// On the grid; the lights go out at `startsAt` (local uptime).
        case grid
        case racing
        case over
    }

    let track: CarTrack
    /// The track's middle line as a path, built once for the drawing.
    let road: Path
    let scripted: Bool
    /// Not `@Published`: stepped in place each frame (a published copy would
    /// copy every car's recorded run on each write); the frame announces the
    /// change itself.
    private(set) var race: CarSplitRace
    @Published private(set) var phase: Phase = .grid
    @Published private(set) var raceTime: Double = 0
    /// What each player is holding, by seat: for the steering and the hints.
    @Published private(set) var holds: [CarSplitHold]
    /// Each camera's heading, eased behind its car's so a twitch is not a lurch.
    private(set) var cameras: [Double]
    /// Local uptime the lights go out; moved on by each pause.
    private(set) var startsAt: Double
    /// The clock is stopped for everyone.
    @Published private(set) var paused = false
    /// The skid marks and smoke every car leaves, shared by every camera.
    let effects = CarRaceEffects()
    /// Called once, when the race is over (everyone home, the clock run out,
    /// or stopped).
    var onOver: (@MainActor (CarSplitRace) -> Void)?

    private var ticker: FrameTicker?
    private var lastFrame: Double?
    private var lastBump: Double = -1
    private var pausedAt: Double?

    init(track: CarTrack, laps: Int, names: [String], startsAt: Double) {
        self.track = track
        road = CarRaceScene.road(for: track)
        scripted = SRDemo.isOn
        let race = CarSplitRace(track: track, laps: laps, names: names)
        self.race = race
        holds = Array(repeating: CarSplitHold(), count: race.racers.count)
        cameras = race.racers.map(\.car.heading)
        self.startsAt = startsAt
    }

    /// Seconds until the lights go out (0 once racing); still while paused.
    var countdown: Double { max(0, startsAt - (pausedAt ?? OfflineUptime.now())) }

    func start() {
        guard ticker == nil, phase != .over, !paused else { return }
        lastFrame = nil
        let ticker = FrameTicker { [weak self] time in
            guard let self else { return false }
            return self.frame(time)
        }
        self.ticker = ticker
        ticker.start()
    }

    func stop() {
        ticker?.stop()
        ticker = nil
        lastFrame = nil
    }

    /// Stop the clock for everyone: nobody's car moves until `resume`.
    func pause() {
        guard phase != .over, !paused else { return }
        paused = true
        pausedAt = OfflineUptime.now()
        stop()
        holds = Array(repeating: CarSplitHold(), count: race.racers.count)
    }

    /// Carry on where the pause stopped: the lights-out time moves on by
    /// however long it lasted.
    func resume() {
        guard paused, phase != .over else { return }
        if let pausedAt { startsAt += OfflineUptime.now() - pausedAt }
        pausedAt = nil
        paused = false
        start()
    }

    /// Stop the race now: whoever is not home does not finish.
    func end() {
        guard phase != .over else { return }
        stop()
        objectWillChange.send()
        race.stop()
        finish()
    }

    /// Where the fingers are now, in the split view's own points.
    func touched(_ points: [CGPoint], panes: [CarSplitPane]) {
        guard !scripted, !paused else { return }
        let touches = points.map { CarVec(x: Double($0.x), y: Double($0.y)) }
        let next = CarSplitLayout.holds(touches: touches, panes: panes, players: race.racers.count)
        if next != holds { holds = next }
    }

    /// What seat `seat`'s camera sees, in a part of the screen `width` points
    /// wide: a narrow part zooms in a little, so a car is not a speck.
    func scene(for seat: Int, width: Double) -> CarRaceScene {
        var cars: [CarRaceScene.Car] = []
        var mine: CarRaceScene.Car?
        for racer in race.racers {
            let car = CarRaceScene.Car(at: racer.car.position, heading: racer.car.heading,
                                       colour: OfflineSeatColour.of(racer.id),
                                       ghost: racer.laps.finished && racer.id != seat,
                                       smoke: racer.car.drifting, boost: racer.car.boosting, mine: racer.id == seat)
            if racer.id == seat { mine = car } else { cars.append(car) }
        }
        if let mine { cars.append(mine) }
        let focus = race.racers.first { $0.id == seat }?.car.position ?? .zero
        return CarRaceScene(track: track, road: road, focus: focus,
                            heading: seat < cameras.count ? cameras[seat] : 0, cars: cars,
                            span: 64 * min(1, max(0.6, width / 390)), mapSize: min(92, max(0, width * 0.26)),
                            effects: effects, time: raceTime)
    }

    // MARK: - The frame

    private func frame(_ time: Double) -> Bool {
        let dt = lastFrame.map { min(max(0, time - $0), 1.0 / 20) } ?? 0
        lastFrame = time
        let now = OfflineUptime.now()
        raceTime = now - startsAt
        switch phase {
        case .grid:
            if now >= startsAt {
                phase = .racing
                SRHaptic.tap()
            }
        case .racing:
            objectWillChange.send()
            let events = race.step(holds: holds, autopilot: scripted, dt: dt, time: raceTime)
            for racer in race.racers { effects.note("\(racer.id)", car: racer.car, time: raceTime) }
            if events.hardest > 4, now - lastBump > 0.3 {
                lastBump = now
                SRHaptic.tap()
            }
            if !events.finished.isEmpty {
                SRHaptic.ok()
            } else if !events.lapped.isEmpty {
                SRHaptic.select()
            }
            if race.over {
                // The link stops itself when this returns false; `stop` drops it later.
                finish()
                return false
            }
        case .over:
            return false
        }
        for index in cameras.indices where index < race.racers.count {
            cameras[index] = Self.ease(cameras[index], towards: race.racers[index].car.heading, by: min(1, dt * 6))
        }
        return true
    }

    private func finish() {
        phase = .over
        onOver?(race)
    }

    private static func ease(_ angle: Double, towards target: Double, by share: Double) -> Double {
        var turn = target - angle
        while turn > .pi { turn -= 2 * .pi }
        while turn < -.pi { turn += 2 * .pi }
        return angle + turn * share
    }
}

/// Split screen: each player's part of the screen with its own camera, one
/// layer over them all that reads every finger, and a pause button where the
/// parts meet. With the phone flat between players sitting opposite, the far
/// players' parts are turned round to face them (`facing`).
struct CarSplitView: View {
    @ObservedObject var driver: CarSplitDriver
    let facing: Bool
    /// Stop the race for everyone.
    let stop: () -> Void
    @State private var confirmStop = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let panes = CarSplitLayout.panes(players: driver.race.racers.count, width: Double(size.width),
                                             height: Double(size.height), facing: facing)
            ZStack(alignment: .topLeading) {
                ForEach(panes, id: \.seat) { pane in
                    CarSplitPaneView(driver: driver, seat: pane.seat, width: pane.width)
                        .frame(width: CGFloat(pane.width), height: CGFloat(pane.height))
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
                        .rotationEffect(.degrees(pane.turned ? 180 : 0))
                        .offset(x: CGFloat(pane.x), y: CGFloat(pane.y))
                }
                CarSplitTouchPad { points in driver.touched(points, panes: panes) }
                    .frame(width: size.width, height: size.height)
                    .accessibilityHidden(true)
                if driver.phase != .over {
                    stopButton
                        .position(x: size.width / 2, y: size.height / 2)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        // An edge swipe mid-race should not throw everyone out to the home screen.
        .defersSystemGestures(on: .all)
        .onAppear { driver.start() }
        .onDisappear { driver.stop() }
        // A call or the home screen pauses everyone, and the pause card is waiting.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && driver.phase != .over {
                driver.pause()
                confirmStop = true
            }
        }
        .onChange(of: confirmStop) { _, showing in
            if !showing { driver.resume() }
        }
        .confirmationDialog("Paused", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Keep racing", role: .cancel) {}
            Button("Stop the race", role: .destructive) { stop() }
        } message: {
            Text("The clock is stopped for everyone. Stop the race and anyone not home yet won't get a time.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("car-race-split")
    }

    private var stopButton: some View {
        Button {
            SRHaptic.tap()
            driver.pause()
            confirmStop = true
        } label: {
            Image(systemName: "pause.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.black.opacity(0.72)))
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel("Pause the race")
        .accessibilityIdentifier("car-race-split-stop")
    }
}

/// One player's part of a split screen: their camera, their lap, place and
/// clock, the start lights, a banner on each new lap and at the finish, and
/// where to hold to steer.
struct CarSplitPaneView: View {
    @ObservedObject var driver: CarSplitDriver
    let seat: Int
    /// The part's width, points: it sets the zoom and the map's size.
    let width: Double

    var body: some View {
        let scene = driver.scene(for: seat, width: width)
        ZStack {
            Canvas(rendersAsynchronously: false) { context, size in
                scene.draw(in: context, size: size)
            }
            VStack(spacing: 8) {
                instruments
                    .padding(.trailing, CGFloat(scene.mapSize) + 4)
                Spacer(minLength: 0)
                middle
                Spacer(minLength: 0)
                pedals
            }
            .padding(10)
        }
        .background(CarRaceScene.ground(driver.track.scenery))
        .clipped()
        // The layer above reads the fingers; this part only shows them.
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("car-race-split-pane-\(seat)")
    }

    private var racer: CarSplitRace.Racer? { driver.race.racers.first { $0.id == seat } }

    private var label: String {
        guard let racer else { return "" }
        if let time = racer.laps.finishTime {
            return "\(racer.name): home in \(CarRaceFormat.time(time)), place \(driver.race.place(of: seat))."
        }
        return "\(racer.name): lap \(racer.laps.lap) of \(racer.laps.laps), place \(driver.race.place(of: seat))."
    }

    private var instruments: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("P\(driver.race.place(of: seat))")
                .font(SR.Text.title(17))
                .foregroundStyle(Color.white)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(OfflineSeatColour.of(seat)))
            VStack(alignment: .leading, spacing: 0) {
                Text(racer?.name ?? "")
                    .font(SR.Text.label())
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                if let racer {
                    Text(racer.laps.finishTime.map { CarRaceFormat.time($0) } ?? "Lap \(racer.laps.lap)/\(racer.laps.laps)")
                        .font(SR.Text.mono())
                        .foregroundStyle(racer.laps.finished ? SR.good : SR.inkSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .srGlassCard(.paper, radius: 18)
    }

    /// The middle of the part: the lights on the grid, then a banner on each
    /// new lap and when this player is home.
    @ViewBuilder
    private var middle: some View {
        if let racer, let time = racer.laps.finishTime {
            CarRaceFinishBanner(time: time, place: driver.race.place(of: seat), newBest: false, compact: true)
        } else if driver.phase == .grid || driver.raceTime < 1 {
            CarRaceStartLights(countdown: driver.countdown, sinceStart: driver.raceTime, compact: true)
        } else if let racer, let banner = CarRaceLapBanner.words(laps: racer.laps, raceTime: driver.raceTime) {
            CarRaceLapBanner(text: banner, compact: true)
        }
    }

    /// Where to hold: left, right, both together to brake, and the boost
    /// down the middle with its tank. Lit while held; laid out in the same
    /// shares as `CarSplitLayout.holds` reads the fingers.
    @ViewBuilder
    private var pedals: some View {
        if driver.scripted {
            Text("Autopilot")
                .font(SR.Text.mono())
                .foregroundStyle(Color.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.35)))
        } else {
            let held = seat < driver.holds.count ? driver.holds[seat] : CarSplitHold()
            let braking = held.left && held.right
            VStack(spacing: 6) {
                if racer?.laps.finished != true, driver.phase == .grid {
                    Text("Hold both arrows to brake · the middle to boost")
                        .font(SR.Text.mono())
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                }
                HStack(spacing: 8) {
                    pedal(icon: "arrow.left", lit: held.left, braking: braking)
                    boostPedal(lit: held.boost && !braking)
                        .frame(width: CGFloat(max(0, width - 20) * (1 - 2 * CarSplitLayout.steerShare)))
                    pedal(icon: "arrow.right", lit: held.right, braking: braking)
                }
            }
        }
    }

    private func pedal(icon: String, lit: Bool, braking: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Image(systemName: braking ? "exclamationmark.octagon.fill" : icon)
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(lit ? Color.white : Color.white.opacity(0.75))
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(shape.fill(braking ? SR.error.opacity(0.8) : Color.black.opacity(lit ? 0.5 : 0.22)))
            .overlay(shape.stroke(Color.white.opacity(lit ? 0.7 : 0.25), lineWidth: lit ? 2 : 1))
            .scaleEffect(lit ? 0.96 : 1)
    }

    /// The boost: lit while held, and its tank as a level rising behind it.
    private func boostPedal(lit: Bool) -> some View {
        let tank = racer?.car.boost ?? 0
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Image(systemName: "bolt.fill")
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(lit ? Color.white : Color.white.opacity(0.85))
            .frame(maxWidth: .infinity, minHeight: 72)
            .background {
                ZStack(alignment: .bottom) {
                    shape.fill(lit ? CarRaceScene.flame : Color.black.opacity(0.22))
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle()
                                .fill(CarRaceScene.flame.opacity(lit ? 0 : 0.5))
                                .frame(height: geo.size.height * min(1, max(0, tank)))
                        }
                    }
                }
                .clipShape(shape)
            }
            .overlay(shape.stroke(Color.white.opacity(lit ? 0.7 : 0.25), lineWidth: lit ? 2 : 1))
    }
}

/// A clear layer over the whole split screen that reports where every finger
/// is, each time one lands, moves or lifts. A SwiftUI gesture follows one
/// finger per view; two to four players need eight at once.
struct CarSplitTouchPad: UIViewRepresentable {
    let changed: @MainActor ([CGPoint]) -> Void

    func makeUIView(context: Context) -> CarSplitTouchView {
        let view = CarSplitTouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: CarSplitTouchView, context: Context) {
        view.changed = changed
    }
}

final class CarSplitTouchView: UIView {
    var changed: (@MainActor ([CGPoint]) -> Void)?
    private var fingers: [ObjectIdentifier: CGPoint] = [:]

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { fingers[ObjectIdentifier(touch)] = touch.location(in: self) }
        report()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { fingers[ObjectIdentifier(touch)] = touch.location(in: self) }
        report()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { fingers[ObjectIdentifier(touch)] = nil }
        report()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { fingers[ObjectIdentifier(touch)] = nil }
        report()
    }

    private func report() {
        changed?(Array(fingers.values))
    }
}
