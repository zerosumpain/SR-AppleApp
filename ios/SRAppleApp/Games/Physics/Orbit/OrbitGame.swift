import SwiftUI
import UIKit

/// A display link for Orbit that can be asked to run fast (a probe in the
/// air, up to 120 Hz) or gently (aiming, 60 Hz). It only runs while
/// something on screen is moving. `onFrame` answers false when there is no
/// one left to draw for (the game has gone), and the link stops itself.
@MainActor
final class OrbitTicker: NSObject {
    private var link: CADisplayLink?
    private let onFrame: @MainActor (Double) -> Bool
    private var fast = false

    init(onFrame: @escaping @MainActor (Double) -> Bool) {
        self.onFrame = onFrame
    }

    var running: Bool { link != nil }

    func start(fast: Bool) {
        if let link {
            if fast != self.fast {
                self.fast = fast
                link.preferredFrameRateRange = Self.range(fast: fast)
            }
            return
        }
        self.fast = fast
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = Self.range(fast: fast)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    private static func range(fast: Bool) -> CAFrameRateRange {
        fast ? CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            : CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
    }

    @objc private func tick(_ link: CADisplayLink) {
        if !onFrame(link.targetTimestamp) { stop() }
    }
}

/// What the field draws, moved once a frame. Only the field and the small
/// read-outs on it watch this, so a frame redraws them and nothing else.
@MainActor
final class OrbitScene: ObservableObject {
    @Published private(set) var frame = 0
    var run: OrbitRun
    private(set) var sky: OrbitSkyLayout
    /// Where the camera's parallax is centred: eased towards the probe.
    private(set) var focus: OrbitVec

    init(level: OrbitLevel) {
        run = OrbitRun(level: level)
        sky = OrbitSkyLayout(level: level)
        focus = level.pad.at
    }

    func load(_ level: OrbitLevel, aim: OrbitShot?) {
        run = OrbitRun(level: level, aim: aim)
        sky = OrbitSkyLayout(level: level)
        focus = level.pad.at
        redraw()
    }

    /// Eases the camera towards the probe (or back to the pad).
    func follow(_ dt: Double) {
        let want = run.flight?.position ?? run.level.pad.at
        let k = min(1, dt * 3)
        focus = focus + (want - focus) * k
    }

    func redraw() {
        frame &+= 1
    }
}

/// The few numbers the heads-up bar shows. They change on events (a launch,
/// a star, an end), never every frame.
struct OrbitHUD: Equatable {
    var probesLeft = OrbitPhysics.probes
    var starsGot = 0
    var starsTotal = 0
    var flying = false
}

/// A level done: what the results card says.
struct OrbitFinish: Equatable {
    let level: Int
    let stars: Int
    let launches: Int
    let par: Int
    let starsGot: Int
    let starsTotal: Int
    /// Stars this level had before, and whether this go beat it.
    let bestStars: Int
    let newBest: Bool
}

/// A line over the field after a flight: what happened, and whether it was good.
struct OrbitToast: Equatable {
    let id: Int
    let text: String
    let good: Bool
}

/// Orbit's engine on this phone: the level being played, the display link
/// that flies it, the progress kept on the phone, and the stage the screen
/// shows (the level list, a level's briefing, play, or a card at the end).
@MainActor
final class OrbitGame: ObservableObject {
    enum Stage: Equatable {
        case levels
        case briefing
        case playing
        case outOfProbes
        case finished(OrbitFinish)
    }

    @Published private(set) var stage: Stage = .levels
    @Published private(set) var progress: OrbitProgress
    @Published private(set) var levelNumber = 1
    @Published private(set) var hud = OrbitHUD()
    @Published private(set) var paused = false
    @Published private(set) var toast: OrbitToast?
    /// Flights run at double speed.
    @Published var fast = false {
        didSet { scene.run.speed = fast ? 2 : 1 }
    }

    let scene: OrbitScene
    /// Demo mode aims for you, so the screenshots fly a good line.
    let scripted = SRDemo.isOn
    private let store = OrbitStore()
    private var ticker: OrbitTicker?
    private var lastFrame: Double?
    private var lastTouch: Double = 0
    private var toastUntil: Double = 0
    private var toastCount = 0
    /// The power read-out last ticked at, in tenths, for the haptic.
    private var powerTick = -1

    /// Seconds of aiming with no touch before the sky stops moving.
    static let idleAfter = 8.0
    /// Points of pull for a full-power launch.
    static let fullPull = 150.0

    init() {
        let progress = OrbitStore().load()
        self.progress = progress
        let first = OrbitLevels.level(progress.nextLevel(of: OrbitLevels.count))
        scene = OrbitScene(level: first)
        levelNumber = first.number
    }

    var level: OrbitLevel { scene.run.level }

    // MARK: - Moving between stages

    /// Opens a level on its briefing card.
    func open(_ number: Int) {
        guard progress.isOpen(number) else { return }
        stop()
        let lv = OrbitLevels.level(number)
        levelNumber = lv.number
        scene.load(lv, aim: scripted ? lv.demo : nil)
        paused = false
        toast = nil
        fast = false
        refreshHUD()
        stage = .briefing
    }

    /// From the briefing: hands the aim to the player.
    func begin() {
        stage = .playing
        paused = false
        touched()
    }

    /// Every probe back for another go at the same level.
    func retry() {
        stop()
        scene.run.restart()
        scene.run.speed = fast ? 2 : 1
        toast = nil
        paused = false
        refreshHUD()
        stage = .playing
        touched()
        scene.redraw()
    }

    func nextLevel() {
        let next = levelNumber + 1
        if next <= OrbitLevels.count && progress.isOpen(next) {
            open(next)
        } else {
            showLevels()
        }
    }

    func showLevels() {
        stop()
        paused = false
        toast = nil
        stage = .levels
    }

    // MARK: - Pause

    func pause() {
        guard stage == .playing, !paused else { return }
        paused = true
        stop()
    }

    func resume() {
        guard paused else { return }
        paused = false
        touched()
    }

    /// The app or the screen went away (a call, the home screen, another
    /// tab): stop everything, and a level in play waits under the pause card.
    /// Without the pause a probe in flight would sit frozen with no way to
    /// start it again, since nothing on the flight controls restarts the link.
    func background() {
        if stage == .playing { paused = true }
        stop()
    }

    /// Back on screen: a card with sparks still bursting finishes them. A
    /// paused level stays paused; a briefing or the list has nothing moving.
    func foreground() {
        switch stage {
        case .finished, .outOfProbes:
            if !scene.run.sparks.isEmpty { startTicker() }
        case .levels, .briefing, .playing:
            break
        }
    }

    /// The screen went away.
    func stop() {
        ticker?.stop()
        ticker = nil
        lastFrame = nil
    }

    // MARK: - Aiming

    /// A drag on the field, slingshot style: pull back from where the finger
    /// went down and the probe will fly the other way, harder the further
    /// the pull.
    func pull(dx: Double, dy: Double) {
        guard canAim else { return }
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 10 else { return }
        let angle = atan2(-dy, -dx)
        let power = min(1, length / Self.fullPull)
        scene.run.setAim(OrbitShot(angle: angle, power: power))
        tickPower()
        touched()
    }

    /// The fine-tuning buttons: turn by `degrees`, change power by `power`.
    func nudge(degrees: Double = 0, power: Double = 0) {
        guard canAim else { return }
        scene.run.nudge(degrees: degrees, power: power)
        tickPower()
        touched()
    }

    var canAim: Bool { stage == .playing && !paused && scene.run.isAiming }

    func launch() {
        guard canAim, scene.run.launch() else { return }
        SRHaptic.tap()
        toast = nil
        refreshHUD()
        touched()
    }

    /// Calls off the probe in the air.
    func callOff() {
        guard stage == .playing, !paused else { return }
        let events = scene.run.abort()
        handle(events)
        scene.redraw()
    }

    private func tickPower() {
        let tenth = Int(scene.run.aim.power * 10)
        if tenth != powerTick {
            if powerTick >= 0 { SRHaptic.select() }
            powerTick = tenth
        }
        scene.redraw()
    }

    // MARK: - The frame loop

    /// Something moved or was touched: make sure the sky is running.
    private func touched() {
        lastTouch = CACurrentMediaTime()
        startTicker()
    }

    private func startTicker() {
        guard !paused else { return }
        let fast = scene.run.isFlying
        if let ticker {
            ticker.start(fast: fast)
            return
        }
        // The display link holds the ticker, not the game: a game that has
        // gone without a stop() ends the link on its next frame.
        let ticker = OrbitTicker { [weak self] time in
            guard let self else { return false }
            self.frame(time)
            return true
        }
        self.ticker = ticker
        lastFrame = nil
        ticker.start(fast: fast)
    }

    private func frame(_ time: Double) {
        // A frame after a gap (a call, the app away) moves one short step,
        // not the whole gap.
        let dt = lastFrame.map { min(max(0, time - $0), 1.0 / 20) } ?? 0
        lastFrame = time
        let events = scene.run.advance(dt)
        handle(events)
        scene.follow(dt)
        if case .ended(let end) = scene.run.phase, scene.run.sinceEnd >= OrbitRun.settle, stage == .playing {
            settled(end)
        }
        if toast != nil, CACurrentMediaTime() > toastUntil {
            toast = nil
        }
        scene.redraw()
        if shouldIdle(time) { stop() }
    }

    /// Nothing left to animate: the display link can rest.
    private func shouldIdle(_ time: Double) -> Bool {
        switch stage {
        case .playing:
            guard scene.run.isAiming, scene.run.sparks.isEmpty else { return false }
            if scripted { return false }
            return CACurrentMediaTime() - lastTouch > Self.idleAfter && toast == nil
        case .finished, .outOfProbes:
            return scene.run.sparks.isEmpty
        case .levels, .briefing:
            return true
        }
    }

    private func handle(_ events: [OrbitRunEvent]) {
        for event in events {
            switch event {
            case .launched:
                break
            case .star:
                SRHaptic.select()
                refreshHUD()
            case .ended(let end):
                ended(end)
            }
        }
    }

    private func ended(_ end: OrbitEnd) {
        progress.noteLaunch()
        store.save(progress)
        refreshHUD()
        switch end {
        case .arrived:
            SRHaptic.ok()
            say(end.sentence(in: level), good: true)
        case .aborted, .lost, .flat:
            SRHaptic.tap()
            say(missLine(end), good: false)
        default:
            SRHaptic.bad()
            say(missLine(end), good: false)
        }
        // Slow the link back down once nothing is flying.
        ticker?.start(fast: false)
    }

    private func missLine(_ end: OrbitEnd) -> String {
        let left = scene.run.attempt.probesLeft
        let probes = left == 1 ? "1 probe left." : (left == 0 ? "No probes left." : "\(left) probes left.")
        return "\(end.sentence(in: level)) \(probes)"
    }

    private func say(_ text: String, good: Bool) {
        toastCount += 1
        toast = OrbitToast(id: toastCount, text: text, good: good)
        toastUntil = CACurrentMediaTime() + 2.6
    }

    /// A flight has ended and the sky has wound back.
    private func settled(_ end: OrbitEnd) {
        let attempt = scene.run.attempt
        if attempt.arrived {
            let before = progress.stars(attempt.level)
            let better = progress.record(attempt)
            store.save(progress)
            stage = .finished(OrbitFinish(level: attempt.level, stars: attempt.rating, launches: attempt.launches,
                                          par: attempt.par, starsGot: attempt.starsCollected,
                                          starsTotal: level.stars.count, bestStars: max(before, attempt.rating),
                                          newBest: better))
            toast = nil
        } else if attempt.outOfProbes {
            stage = .outOfProbes
        } else {
            scene.run.ready()
            refreshHUD()
            lastTouch = CACurrentMediaTime()
        }
    }

    private func refreshHUD() {
        let run = scene.run
        hud = OrbitHUD(probesLeft: run.attempt.probesLeft,
                       starsGot: run.collected.filter { $0 }.count,
                       starsTotal: run.level.stars.count,
                       flying: run.isFlying)
    }
}
