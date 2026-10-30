import SwiftUI
import UIKit

/// A `CADisplayLink` as a closure, held at 60 Hz: every frame redraws the
/// whole race view (HUD, controls, minimap), and 120 Hz doubles that for a
/// phone that already runs warm in a long race. Physics steps at 240 Hz
/// whatever the screen does. The closure returns false to stop.
@MainActor
final class CarProFrameLink: NSObject {
    private var link: CADisplayLink?
    private let onFrame: @MainActor (Double) -> Bool

    init(onFrame: @escaping @MainActor (Double) -> Bool) {
        self.onFrame = onFrame
    }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        if !onFrame(link.targetTimestamp) { stop() }
    }
}

/// One lap the player completed, for the time-trial sheet.
struct CarProLapLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let valid: Bool
}

/// One session on the circuit: a display link drives the engine in its
/// fixed substeps, reads the pedals, the wheel or the tilt, turns what
/// happened into haptics and banners, and stops the moment the race is
/// paused, finished or off the screen. Nothing ticks while idle.
@MainActor
final class CarProRaceController: ObservableObject {
    /// What the session is for: the card around it and what its result means.
    enum Purpose: Equatable {
        case qualifying
        case championship
        case quickRace
        case timeTrial

        var title: String {
            switch self {
            case .qualifying: return "Qualifying"
            case .championship: return "Race"
            case .quickRace: return "Quick race"
            case .timeTrial: return "Time trial"
            }
        }
    }

    enum Stage: Equatable {
        /// The intro card is up; nothing is moving.
        case ready
        case running
        case finished
    }

    let purpose: Purpose
    let config: CarProSessionConfig
    let world: CarProRaceWorld
    /// How the player steers here: tilt only where the phone has the sensor.
    let steering: CarProSteeringMode
    let mph: Bool
    /// The demo: the player's car drives itself.
    let scripted: Bool
    @Published private(set) var stage: Stage = .ready
    @Published private(set) var paused = false
    /// Counts frames: every view that draws the race redraws on it.
    @Published private(set) var tick = 0
    private(set) var hud: CarProHUD
    private(set) var banner: CarProBanner?
    /// The classification, from the moment the flag fell (or the player stopped).
    private(set) var results: [CarProResult] = []
    /// Seconds since the flag, while the field finishes its lap.
    private(set) var sinceFlag: Double?
    private(set) var laps: [CarProLapLine] = []

    /// The pedals, 0…1, and the on-screen steering, −1…1, as the controls set them.
    var throttle: Double = 0
    var brake: Double = 0
    var touchSteer: Double = 0
    let tilt = PhysicsTilt()

    /// A lap done by the player: its time and whether it stood.
    var onLap: (@MainActor (CarProRaceController, Double, Bool) -> Void)?
    /// The session is over and its card should follow.
    var onFinish: (@MainActor (CarProRaceController) -> Void)?

    private var steer: Double = 0
    private var shiftUpQueued = false
    private var shiftDownQueued = false
    private var link: CarProFrameLink?
    private var lastFrame: Double?
    /// Seconds of driving, for banners and haptic spacing.
    private var clock: Double = 0
    private var bannerUntil: Double = 0
    private var lastKnock: Double = -10
    private var lastRumble: Double = -10

    init(purpose: Purpose, config: CarProSessionConfig, steering: CarProSteeringMode, mph: Bool) {
        var config = config
        let scripted = SRDemo.isOn
        if scripted { config.autopilot = true }
        self.purpose = purpose
        self.config = config
        self.scripted = scripted
        self.steering = steering == .tilt && !PhysicsTilt.isAvailable ? .slider : steering
        self.mph = mph
        let world = CarProRaceWorld(config: config)
        self.world = world
        hud = world.session.hud
    }

    var session: CarProSession { world.session }

    /// How long the race keeps running after the flag, for the slowing-down lap.
    private var celebration: Double { config.kind.isRace ? 3.2 : 1.6 }

    // MARK: - Running

    /// Off the intro card: the lights (or the rolling start) begin.
    func begin() {
        guard stage == .ready else { return }
        stage = .running
        startTicking()
    }

    func pause() {
        guard stage == .running, !paused, sinceFlag == nil else { return }
        paused = true
        throttle = 0
        brake = 0
        touchSteer = 0
        stopTicking()
    }

    func resume() {
        guard paused else { return }
        paused = false
        startTicking()
    }

    /// The screen has gone: nothing keeps running behind it.
    func stop() {
        stopTicking()
    }

    /// The same session again from the start.
    func restart() {
        world.restart()
        results = []
        sinceFlag = nil
        banner = nil
        laps = []
        steer = 0
        throttle = 0
        brake = 0
        touchSteer = 0
        hud = world.session.hud
        paused = false
        stage = .running
        startTicking()
        tick &+= 1
    }

    /// The player stops: a retirement in a race, the end of the session
    /// (keeping its laps) in qualifying or a time trial.
    func retire() {
        guard stage != .finished else { return }
        world.retire()
        results = world.session.results
        finish()
    }

    /// A tap of a shift paddle, spent on the next frame.
    func shift(up: Bool) {
        if up { shiftUpQueued = true } else { shiftDownQueued = true }
        SRHaptic.select()
    }

    /// Make the way the phone is held now straight ahead.
    func recentre() {
        tilt.recentre()
        SRHaptic.tap()
    }

    private func startTicking() {
        if steering == .tilt { tilt.start() }
        lastFrame = nil
        if link == nil {
            link = CarProFrameLink { [weak self] time in
                guard let self else { return false }
                return self.frame(time)
            }
        }
        link?.start()
    }

    private func stopTicking() {
        link?.stop()
        lastFrame = nil
        tilt.stop()
    }

    private func finish() {
        if results.isEmpty { results = world.session.results }
        stage = .finished
        paused = false
        stopTicking()
        tick &+= 1
        onFinish?(self)
    }

    // MARK: - A frame

    private func frame(_ time: Double) -> Bool {
        let dt = lastFrame.map { CarProMath.clamp(time - $0, 0, 0.05) } ?? 0
        lastFrame = time
        guard stage == .running, !paused else { return false }
        clock += dt
        let wasFinished = world.session.phase == .finished
        world.step(dt: dt, input: input(dt: dt))
        react(to: world.session.events)
        hud = world.session.hud
        if banner != nil && clock > bannerUntil { banner = nil }
        if world.session.phase == .finished {
            if !wasFinished { flag() }
            let since = (sinceFlag ?? 0) + dt
            sinceFlag = since
            if since >= celebration {
                finish()
                return false
            }
        }
        tick &+= 1
        return true
    }

    private func input(dt: Double) -> CarProInput {
        let wanted: Double
        if steering == .tilt {
            wanted = CarProControlMath.tilt(tilt.lean() ?? 0)
        } else {
            wanted = touchSteer
        }
        // Tilt is noisy and wants a little more smoothing than a finger.
        steer = CarProControlMath.ease(steer, to: wanted, rate: steering == .tilt ? 16 : 24, dt: dt)
        let up = shiftUpQueued, down = shiftDownQueued
        shiftUpQueued = false
        shiftDownQueued = false
        return CarProInput(throttle: throttle, brake: brake, steer: steer, shiftUp: up, shiftDown: down)
    }

    /// The flag has fallen for the player: the classification as it stands,
    /// and the controls let go while the car drives itself home.
    private func flag() {
        results = world.session.results
        throttle = 0
        brake = 0
        tilt.stop()
        SRHaptic.ok()
    }

    private func react(to events: [CarProEvent]) {
        let me = world.session.playerIndex
        for event in events {
            switch event {
            case .light:
                SRHaptic.select()
            case .lightsOut:
                SRHaptic.tap()
            case let .wallHit(racer, impact):
                let at = world.session.racers[racer].vehicle.position
                world.effects.sparks(at: at, impact: impact, time: world.clock)
                if racer == me {
                    world.camera.bump(impact)
                    knock(impact)
                }
            case let .contact(a, b, impact):
                let pa = world.session.racers[a].vehicle.position, pb = world.session.racers[b].vehicle.position
                world.effects.sparks(at: (pa + pb) * 0.5, impact: impact, time: world.clock)
                if a == me || b == me {
                    world.camera.bump(impact * 0.6)
                    knock(impact)
                }
            case let .lap(racer, lap, time, valid, personalBest):
                if racer == me {
                    laps.append(CarProLapLine(id: lap, time: time, valid: valid))
                    onLap?(self, time, valid)
                    if valid && personalBest { SRHaptic.ok() }
                }
            case let .trackLimits(racer, _):
                if racer == me { SRHaptic.bad() }
            case let .penalty(racer, _):
                if racer == me { SRHaptic.bad() }
            case let .position(from, to):
                if to < from { SRHaptic.select() }
            default:
                break
            }
            if let next = CarProPresent.banner(for: event, player: me, kind: config.kind, laps: config.laps) {
                show(next)
            }
        }
        rumble()
    }

    private func show(_ next: CarProBanner) {
        if let current = banner, clock < bannerUntil, next.priority < current.priority { return }
        banner = next
        bannerUntil = clock + next.duration
        if next.priority >= 3 && UIAccessibility.isVoiceOverRunning {
            let words = [next.title, next.detail ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
            UIAccessibility.post(notification: .announcement, argument: words)
        }
    }

    /// A knock you can feel, spaced so a scrape along a wall is not a buzz.
    private func knock(_ impact: Double) {
        guard impact > 2, clock - lastKnock > 0.25 else { return }
        lastKnock = clock
        SRHaptic.tap()
    }

    /// The kerbs' ripple under the wheels.
    private func rumble() {
        let car = world.session.player.vehicle
        guard car.rumble > 0.3, car.speed > 6, clock - lastRumble > 0.12, sinceFlag == nil else { return }
        lastRumble = clock
        SRHaptic.select()
    }
}
