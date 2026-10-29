import SwiftUI
import UIKit
import CoreMotion

/// Ticks once per drawn frame, so only the table redraws every frame and the
/// rest of the screen redraws only when something it shows changes.
@MainActor
final class PinballClock: ObservableObject {
    @Published var frame: UInt = 0
}

/// What the strip and the line under it show. Published only when it changes.
struct PinballHUD: Equatable {
    var score = 0
    var ball = 1
    var balls = 3
    var multiplier = 1
    var mode: PinballMode = .bumperBlitz
    var progress = 0
    var goal = 20
    var multiball = false
    var save = false
    var warnings = 0
    var tilted = false
    /// A ball waits on the plunger for the player.
    var waiting = false
    var dots = PinballDotFrame()
    /// Changes whenever the strip changes, so it can flash.
    var dotsKey = 0
}

/// How a finished game went, for the end card.
struct PinballResult: Equatable {
    var score: Int
    /// Its place on the high-score table, if it made it.
    var rank: Int?
    var entryID: String
    var stats: PinballStats
    var newBest: Bool
}

/// The phone's shake, read from Core Motion's user acceleration (the push
/// of the hand, gravity taken out). No permission is needed for it. On only
/// while a ball is in play; pulled each frame, no callbacks.
@MainActor
final class PinballShakeSensor {
    let available: Bool
    private var manager: CMMotionManager?
    private var lastNudge: Double = -1

    init() {
        available = PhysicsTilt.isAvailable
    }

    func start() {
        guard available else { return }
        let manager = self.manager ?? CMMotionManager()
        self.manager = manager
        guard !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates()
    }

    func stop() {
        if let manager, manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
    }

    /// A nudge when the phone has just been given a sharp shake (more than
    /// about a g), at most one every third of a second.
    func poll(now: Double) -> PinballVec? {
        guard let a = manager?.deviceMotion?.userAcceleration else { return nil }
        let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        guard magnitude > 1.1, now - lastNudge > 0.33 else { return nil }
        lastNudge = now
        // The ball goes the other way to the phone, as it would on a shoved table.
        let side = min(max(-a.x / max(magnitude, 0.001) * 1.6, -1), 1)
        return PinballVec(side, -1)
    }
}

/// Pinball's engine on this phone: a display link that turns touches and
/// shakes into `PinballInput`, plays the machine one frame at a time, and
/// turns its events into haptics, sparks and a jolt of the picture.
@MainActor
final class PinballEngine: ObservableObject {
    enum Stage: Equatable {
        case intro
        case playing
        case paused
        case over
    }

    @Published private(set) var stage: Stage = .intro
    @Published private(set) var hud = PinballHUD()
    @Published private(set) var book: PinballScoreBook
    @Published private(set) var result: PinballResult?

    let clock = PinballClock()
    private(set) var machine = PinballMachine(seed: 1)
    private(set) var sparks = PinballSparks()
    /// How far the picture is jolted, in table units, after a big hit.
    private(set) var jolt = PinballVec.zero
    /// The last few places each ball has been, by ball id, for the motion trail.
    private(set) var trails: [Int: [PinballVec]] = [:]
    /// Demo mode plays itself: no finger, no sensor, the screenshots still move.
    let scripted = SRDemo.isOn
    let shake = PinballShakeSensor()

    private var leftHeld = false
    private var rightHeld = false
    private var pull: Double = 0
    private var pendingLaunch: Double?
    private var pendingNudge: PinballVec?
    private var joltEnergy: Double = 0
    private var joltPhase: Double = 0
    private var lastHaptic: Double = 0
    private var ticker: FrameTicker?
    private var lastFrame: Double?
    private var dotsSerial = -1
    private var dotsScore = -1
    private var dotsKey = 0
    private var rng = PinballRandom(seed: UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFF_FFFF)
    private let store = PinballScoreStore()

    init() {
        book = PinballScoreStore().load()
        publish()
    }

    var plungerReady: Bool { stage == .playing && hud.waiting && !scripted }
    /// The plunger's pull, 0…1, as drawn.
    var plungerPull: Double { machine.pull }

    // MARK: - Game flow

    func begin() {
        let seed = scripted ? 7 : rng.next()
        machine = PinballMachine(seed: seed)
        sparks.clear()
        trails = [:]
        result = nil
        resetInput()
        stage = .playing
        publish()
        run()
    }

    func pause() {
        guard stage == .playing else { return }
        stage = .paused
        halt()
        resetInput()
    }

    func resume() {
        guard stage == .paused else { return }
        stage = .playing
        run()
    }

    /// Off screen: everything stops; a game in progress waits, paused.
    func stop() {
        if stage == .playing { stage = .paused }
        halt()
        resetInput()
    }

    func rename(to initials: String) {
        guard let id = result?.entryID else { return }
        book.rename(id, to: initials)
        store.save(book)
    }

    private func run() {
        lastFrame = nil
        shake.start()
        guard ticker == nil else { return }
        let ticker = FrameTicker { [weak self] time in
            guard let self else { return false }
            return self.frame(time)
        }
        self.ticker = ticker
        ticker.start()
    }

    private func halt() {
        ticker?.stop()
        ticker = nil
        lastFrame = nil
        shake.stop()
    }

    private func resetInput() {
        leftHeld = false
        rightHeld = false
        pull = 0
        pendingLaunch = nil
        pendingNudge = nil
    }

    // MARK: - Controls

    func setFlippers(left: Bool, right: Bool) {
        leftHeld = left
        rightHeld = right
    }

    func setPull(_ amount: Double) {
        pull = min(max(amount, 0), 1)
    }

    /// Let go of the plunger. A tap with hardly any pull sends a gentle ball
    /// into the top lanes, so the youngest players can just tap.
    func releasePlunger() {
        pendingLaunch = pull < 0.06 ? 0.42 : pull
        pull = 0
    }

    /// VoiceOver's flip: up for a moment, then down.
    func tapFlipper(_ side: PinballSide) {
        if side == .left { leftHeld = true } else { rightHeld = true }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            if side == .left { self?.leftHeld = false } else { self?.rightHeld = false }
        }
    }

    func nudge() {
        pendingNudge = PinballVec(rng.range(-1, 1), -1)
    }

    // MARK: - The frame

    private func frame(_ time: Double) -> Bool {
        // A frame after a pause (a call, a notification) plays one short
        // step, not the whole gap.
        let dt = lastFrame.map { min(max(0, time - $0), 1.0 / 20) } ?? (1.0 / 60)
        lastFrame = time
        var input: PinballInput
        if scripted {
            input = PinballAutopilot.input(for: machine)
        } else {
            input = PinballInput(left: leftHeld, right: rightHeld, pull: pull)
            input.launch = pendingLaunch
            input.nudge = pendingNudge ?? shake.poll(now: time)
        }
        pendingLaunch = nil
        pendingNudge = nil
        machine.step(input, dt: dt)
        react(to: machine.takeEvents(), at: time)
        sparks.step(dt)
        settleJolt(dt)
        followBalls()
        publish()
        clock.frame &+= 1
        if machine.isOver {
            finish()
            return false
        }
        return true
    }

    private func finish() {
        ticker = nil
        lastFrame = nil
        shake.stop()
        resetInput()
        let previousBest = book.best
        let id = UUID().uuidString
        let rank = book.record(score: machine.score, modes: machine.stats.modes, id: id)
        store.save(book)
        result = PinballResult(score: machine.score, rank: rank, entryID: id, stats: machine.stats,
                               newBest: machine.score > previousBest)
        stage = .over
    }

    private func followBalls() {
        var seen = Set<Int>()
        for ball in machine.balls {
            seen.insert(ball.id)
            var trail = trails[ball.id] ?? []
            trail.append(ball.p)
            if trail.count > 6 { trail.removeFirst(trail.count - 6) }
            trails[ball.id] = trail
        }
        if trails.count > seen.count {
            for key in Array(trails.keys) where !seen.contains(key) { trails[key] = nil }
        }
    }

    private func settleJolt(_ dt: Double) {
        guard joltEnergy > 0.05 else {
            joltEnergy = 0
            jolt = .zero
            return
        }
        joltPhase += dt * 55
        joltEnergy *= max(0, 1 - 9 * dt)
        jolt = PinballVec(sin(joltPhase) * joltEnergy, cos(joltPhase * 1.3) * joltEnergy * 0.6)
    }

    private func kick(_ amount: Double) { joltEnergy = max(joltEnergy, amount) }

    /// Haptics are kept to one every 45 ms, so a ball rattling between the
    /// bumpers buzzes rather than hums.
    private func buzz(_ time: Double, _ strong: Bool = false) {
        guard time - lastHaptic > 0.045 else { return }
        lastHaptic = time
        if strong { SRHaptic.ok() } else { SRHaptic.tap() }
    }

    private func react(to events: [PinballEvent], at time: Double) {
        guard !events.isEmpty else { return }
        let table = machine.table
        for event in events {
            switch event {
            case .flipper:
                buzz(time)
            case .bumper(let i):
                buzz(time)
                kick(2.5)
                sparks.burst(at: table.bumpers[i].centre, count: 12, speed: 520, hue: 0, rng: &rng)
            case .sling(let side):
                let sling = table.slings[side.rawValue]
                kick(1.5)
                sparks.burst(at: (sling.a + sling.b) / 2, count: 8, speed: 420, hue: 1, rng: &rng)
            case .target(let i):
                SRHaptic.select()
                sparks.burst(at: table.targets[i].centre, count: 10, speed: 380, hue: 2, rng: &rng)
            case .bankCleared:
                buzz(time, true)
                for target in table.targets {
                    sparks.burst(at: target.centre, count: 14, speed: 520, hue: 2, rng: &rng)
                }
            case .lane(let i):
                SRHaptic.select()
                sparks.burst(at: table.lanes[i], count: 6, speed: 260, hue: 3, rng: &rng)
            case .lanesComplete:
                buzz(time, true)
                for lane in table.lanes { sparks.burst(at: lane, count: 10, speed: 360, hue: 3, rng: &rng) }
            case .spinner:
                SRHaptic.select()
            case .orbit:
                sparks.burst(at: table.spinner.centre, count: 12, speed: 420, hue: 2, rng: &rng)
            case .ramp:
                SRHaptic.select()
                sparks.burst(at: table.ramp.backCentre, count: 14, speed: 480, hue: 1, rng: &rng)
            case .jackpot:
                buzz(time, true)
                kick(7)
                sparks.burst(at: PinballVec(259, 420), count: 60, speed: 900, hue: 0, rng: &rng)
            case .skillShot:
                buzz(time, true)
                sparks.burst(at: table.lanes[machine.skillLane], count: 30, speed: 600, hue: 4, rng: &rng)
            case .launch:
                SRHaptic.tap()
            case .drain:
                kick(3)
            case .ballSaved:
                buzz(time, true)
            case .multiball:
                buzz(time, true)
                kick(6)
                sparks.burst(at: PinballVec(259, 500), count: 50, speed: 800, hue: 4, rng: &rng)
            case .modeComplete:
                buzz(time, true)
            case .extraBall:
                buzz(time, true)
            case .tiltWarning:
                SRHaptic.bad()
                kick(4)
            case .tilt:
                SRHaptic.bad()
                kick(10)
            case .ballOver:
                SRHaptic.bad()
            case .gameOver:
                break
            }
        }
    }

    private func publish() {
        let m = machine
        var next = hud
        next.score = m.score
        next.ball = m.ballNumber
        next.balls = m.totalBalls
        next.multiplier = m.multiplier
        next.mode = m.mode
        next.progress = m.modeProgress
        next.goal = m.modeGoal
        next.multiball = m.multiball
        next.save = m.saveActive && m.phase == .playing
        next.warnings = m.tiltWarnings
        next.tilted = m.tilted
        next.waiting = m.ballWaiting
        // The strip is drawn again only when its message or the score changes.
        let showing = m.showing
        let serial = showing?.serial ?? 0
        let score = showing == nil ? m.score : -2
        if serial != dotsSerial || score != dotsScore {
            dotsSerial = serial
            dotsScore = score
            dotsKey += 1
            if let showing {
                next.dots = PinballDotFrame.message(showing.top, showing.bottom)
            } else {
                next.dots = PinballDotFrame.score(m.score)
            }
            next.dotsKey = dotsKey
        }
        if next != hud { hud = next }
    }
}
