import SwiftUI
import UIKit

/// A flourish on the board: sparkles from the cup, a ring off a flag, dust
/// round a hole, a puff off a hard knock. Kept as where and when it began;
/// the drawing works out the rest from its age, so nothing is stored per
/// particle.
struct TiltMazeBurst: Equatable {
    enum Kind: Equatable { case goal, flag, fall, knock }

    let kind: Kind
    let at: TiltMazeVector
    /// `TiltMazeEngine.clock` when it began.
    let born: Double

    var lifetime: Double {
        switch kind {
        case .goal: return 1.4
        case .flag: return 0.8
        case .fall: return 0.6
        case .knock: return 0.3
        }
    }
}

/// Tilt Maze's engine on this phone: a display link that reads the tilt (or
/// the on-screen stick), eases it so a shaky hand is not a shaky marble,
/// rolls the run on in fixed steps, and turns what happened into haptics and
/// flourishes. It publishes one tick a frame for the live layer of the board
/// and nothing else; the screen hears about the moments that matter through
/// `onEvents`.
///
/// It runs only while a maze is being played: the link and the sensor stop
/// on pause, at the cup, in the background and when the screen goes.
@MainActor
final class TiltMazeEngine: ObservableObject {
    /// Bumped once a frame: the live layer redraws.
    @Published private(set) var frame = 0
    private(set) var run: TiltMazeRun
    /// The way through, for the demo's autopilot.
    private(set) var path: [TiltMazeCell]
    let motion = TiltMazeMotion()
    /// Demo mode rolls itself: no sensor, no finger, the screenshots still move.
    let scripted = SRDemo.isOn
    /// Steer with the on-screen stick rather than by tilting.
    var useStick = false
    /// The stick, −1…1 each way.
    var stick = TiltMazeVector.zero
    /// The tilt the marble feels, eased: also tilts the shadow and the walls.
    private(set) var tilt = TiltMazeVector.zero
    /// Seconds of play on this maze, for the flourishes.
    private(set) var clock = 0.0
    private(set) var bursts: [TiltMazeBurst] = []
    /// The marble's last few places, newest last, for a faint trail.
    private(set) var trail: [TiltMazeVector] = []
    var onEvents: ((TiltMazeEvents) -> Void)?

    private var ticker: FrameTicker?
    private var lastFrame: Double?
    private var lastKnock = -1.0
    private var trailCount = 0
    private let knocker = UIImpactFeedbackGenerator(style: .medium)

    /// The full stick is this much tilt, in g: brisk, not wild.
    static let stickTilt = 0.38
    static let trailLength = 10

    init(level: TiltMazeLevel) {
        run = TiltMazeRun(level: level)
        path = level.solution ?? []
        bursts.reserveCapacity(8)
        trail.reserveCapacity(Self.trailLength)
    }

    var steersByTilt: Bool { motion.available && !useStick && !scripted }
    var isRunning: Bool { ticker != nil }

    /// A new maze, or the same one again from the start.
    func load(_ level: TiltMazeLevel) {
        stop()
        run = TiltMazeRun(level: level)
        path = level.solution ?? []
        bursts.removeAll(keepingCapacity: true)
        trail.removeAll(keepingCapacity: true)
        clock = 0
        tilt = .zero
        stick = .zero
        frame &+= 1
    }

    func start() {
        guard ticker == nil, !run.isOver else { return }
        if steersByTilt { motion.start() }
        knocker.prepare()
        lastFrame = nil
        let ticker = FrameTicker { [weak self] time in
            guard let self else { return false }
            return self.step(time)
        }
        self.ticker = ticker
        ticker.start()
    }

    func stop() {
        ticker?.stop()
        ticker = nil
        lastFrame = nil
        motion.stop()
        stick = .zero
    }

    /// The way the phone is held now becomes level.
    func calibrate() {
        motion.recentre()
        tilt = .zero
    }

    /// One display frame. False stops the link.
    private func step(_ time: Double) -> Bool {
        let dt = lastFrame.map { min(max(0, time - $0), TiltMazeRules.longestFrame) } ?? 0
        lastFrame = time
        clock += dt
        let wanted = input()
        // Ease towards the wanted tilt over a few hundredths of a second.
        let k = 1 - exp(-dt * 16)
        tilt = TiltMazeVector(x: tilt.x + (wanted.x - tilt.x) * k, y: tilt.y + (wanted.y - tilt.y) * k)
        let events = run.advance(tilt: scripted ? wanted : tilt, dt: dt)
        react(events)
        remember()
        if !bursts.isEmpty {
            let now = clock
            bursts.removeAll { now - $0.born > $0.lifetime }
        }
        frame &+= 1
        guard !run.isOver else {
            ticker = nil
            motion.stop()
            return false
        }
        return true
    }

    private func input() -> TiltMazeVector {
        if scripted { return TiltMazeAutopilot.tilt(for: run, path: path) }
        if steersByTilt { return motion.lean() ?? .zero }
        return TiltMazeVector(x: stick.x * Self.stickTilt, y: stick.y * Self.stickTilt)
    }

    private func react(_ events: TiltMazeEvents) {
        if events.knock > 1.1 && clock - lastKnock > 0.07 {
            lastKnock = clock
            knocker.impactOccurred(intensity: CGFloat(min(1, events.knock / 5)))
            knocker.prepare()
            if events.knock > 2.6 { burst(.knock, at: run.ball.position) }
        }
        if events.fell {
            SRHaptic.bad()
            if case .falling(let hole, _) = run.phase { burst(.fall, at: hole.centre) }
            trail.removeAll(keepingCapacity: true)
        }
        if events.respawned { trail.removeAll(keepingCapacity: true) }
        if let flag = events.checkpoint {
            SRHaptic.select()
            burst(.flag, at: flag.centre)
        }
        if events.reachedGoal {
            SRHaptic.ok()
            burst(.goal, at: run.level.goal.centre)
        }
        let matters = events.started || events.fell || events.respawned || events.checkpoint != nil
            || events.reachedGoal || events.cleared
        if matters { onEvents?(events) }
    }

    private func burst(_ kind: TiltMazeBurst.Kind, at point: TiltMazeVector) {
        if bursts.count >= 8 { bursts.removeFirst() }
        bursts.append(TiltMazeBurst(kind: kind, at: point, born: clock))
    }

    /// Every other frame, the marble's place joins the trail.
    private func remember() {
        trailCount &+= 1
        guard trailCount % 2 == 0, run.steerable else { return }
        if trail.count >= Self.trailLength { trail.removeFirst() }
        trail.append(run.ball.position)
    }
}
