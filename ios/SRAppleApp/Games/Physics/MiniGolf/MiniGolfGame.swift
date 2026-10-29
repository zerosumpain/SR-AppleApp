import SwiftUI
import UIKit

/// The aim while a finger drags back from the ball: which way the putt will
/// go, and how hard (0 to 1).
struct MiniGolfAim: Equatable {
    var angle: Double
    var power: Double
}

/// A scrap of confetti, a drop of water, a fleck of sand or a spark off a bumper.
struct MiniGolfParticle {
    enum Tone: Equatable {
        case confetti(Int)
        case gold
        case water
        case sand
        case spark
    }

    var at: MiniGolfVec
    var velocity: MiniGolfVec
    var life: Double
    let span: Double
    let size: Double
    let tone: Tone
    var spin: Double
    let spinRate: Double

    /// 1 when new, 0 when gone.
    var fade: Double { max(0, min(1, life / span)) }
}

/// A ring that grows and fades: on the water after a splash, round a bumper,
/// round the cup when a ball drops.
struct MiniGolfRipple {
    enum Tone: Equatable {
        case water
        case bumper
        case cup
    }

    let at: MiniGolfVec
    var age: Double
    let span: Double
    let radius: Double
    let tone: Tone

    var progress: Double { min(1, age / span) }
}

/// Everything the course view draws in one frame, as plain values.
struct MiniGolfSnapshot {
    var hole: MiniGolfHole
    var ball: MiniGolfVec
    /// 0 on the felt, 1 gone down the cup.
    var ballSink: Double = 0
    var showBall = true
    /// The course clock: windmills, water and the flag move with it.
    var clock: Double = 0
    var camera: MiniGolfCamera
    /// Where on the screen the hole is framed (inside the instruments).
    var playRect: CGRect
    var trail: [MiniGolfVec] = []
    var particles: [MiniGolfParticle] = []
    var ripples: [MiniGolfRipple] = []
    /// Per post: seconds of glow left after a hit.
    var flashes: [Double] = []
    var aim: MiniGolfAim?
    /// The player's colour.
    var seat = 0
}

/// What the course view watches: a new snapshot every frame, and the hole's
/// fixed shapes built once per hole. The instruments watch the game instead,
/// which changes only when a stroke or a stage does.
@MainActor
final class MiniGolfSceneModel: ObservableObject {
    @Published var snapshot: MiniGolfSnapshot
    private(set) var paths: MiniGolfHolePaths

    init(hole: MiniGolfHole, rect: CGRect) {
        let camera = MiniGolfCamera.framing(hole.bounds, width: Double(rect.width), height: Double(rect.height),
                                            focus: hole.tee, overview: true)
        snapshot = MiniGolfSnapshot(hole: hole, ball: hole.tee, camera: camera, playRect: rect)
        paths = MiniGolfHolePaths(hole)
    }

    func show(_ next: MiniGolfSnapshot) {
        if next.hole.number != paths.number { paths = MiniGolfHolePaths(next.hole) }
        snapshot = next
    }
}

/// Mini Golf's engine: a display link that steps the ball at a fixed rate,
/// turns the drag into a putt, keeps the scorecard and the bests, and hands
/// the course view a snapshot each frame. It stops the link whenever nothing
/// is moving — on a card, when paused, and after a while of nobody aiming.
@MainActor
final class MiniGolfGame: ObservableObject {
    enum Stage: Equatable {
        /// The card before a player tees off: the hole, its tip, whose turn.
        case tee
        case aiming
        case rolling
        /// In the cup (or picked up): the word for it, then on.
        case sunk
        /// Everyone has played the hole: its scores.
        case holeDone
        case finished
    }

    @Published private(set) var round: MiniGolfRound
    @Published private(set) var stage: Stage = .tee
    /// Strokes so far on this hole for the player putting, penalties included.
    @Published private(set) var strokes = 0
    @Published private(set) var paused = false
    @Published private(set) var book: MiniGolfBook
    /// A line across the top for a moment: a splash, a lip-out.
    @Published private(set) var toast: String? = nil
    @Published private(set) var sunkWord = ""
    @Published private(set) var sunkStrokes = 0
    @Published private(set) var holeInOne = false
    @Published private(set) var newHoleBest = false
    @Published private(set) var newRoundBest = false
    /// Showing the whole hole rather than following the ball.
    @Published private(set) var overview = false
    /// The power meter while a finger is dragging.
    @Published private(set) var power: Double = 0
    @Published private(set) var dragging = false

    let scene: MiniGolfSceneModel
    private(set) var sim: MiniGolfBallSim
    private let store = MiniGolfStore()
    private var ticker: FrameTicker?
    private var lastFrame: Double?
    private var events: [MiniGolfEvent] = []
    private var camera: MiniGolfCamera
    private var playRect = CGRect(x: 0, y: 0, width: 375, height: 560)
    private var idleFor: Double = 0
    private var sunkTimer: Double = 0
    private var toastTimer: Double = 0
    private var sink: Double = 0
    private var particles: [MiniGolfParticle] = []
    private var ripples: [MiniGolfRipple] = []
    private var flashes: [Double] = []
    private var trail: [MiniGolfVec] = []
    private var aim: MiniGolfAim?
    /// The score just made, written on the card when the banner goes.
    private var pendingScore: Int?
    private var lastHaptic: Double = 0
    private var powerNotch = 0
    /// Reduce Motion is on: fewer particles, and the camera moves briskly rather than swooping.
    var calm = false
    /// The aim VoiceOver adjusts, step by step, instead of a drag.
    private(set) var assist = MiniGolfAim(angle: -.pi / 2, power: 0.5)

    /// Most particles alive at once.
    private static let particleCap = 180
    /// Seconds of nobody aiming before the course stops moving to save power.
    private static let idleAfter = 25.0

    init(loop: MiniGolfLoop, players: [MiniGolfPlayer]) {
        let round = MiniGolfRound(loop: loop, players: players)
        self.round = round
        book = MiniGolfStore().load()
        sim = MiniGolfBallSim(hole: round.hole)
        camera = MiniGolfCamera.framing(round.hole.bounds, width: 375, height: 560, focus: round.hole.tee, overview: true)
        scene = MiniGolfSceneModel(hole: round.hole, rect: CGRect(x: 0, y: 0, width: 375, height: 560))
        prepareTee()
    }

    var hole: MiniGolfHole { round.hole }
    var player: MiniGolfPlayer { round.player }
    var maxStrokes: Int { MiniGolfRules.maxStrokes(par: hole.par) }
    var isFirstTee: Bool { round.holeSlot == 0 && round.turn == 0 }

    // MARK: - Screen

    /// Where on the screen the hole is framed; the view says when it changes.
    func setPlayRect(_ rect: CGRect) {
        guard rect.width > 10, rect.height > 10, rect != playRect else { return }
        playRect = rect
        // While the link runs the camera eases to the new framing; when still, it jumps.
        if ticker == nil { camera = targetCamera() }
        publish()
    }

    /// Off screen, or the app going to the background.
    func stop() {
        ticker?.stop()
        ticker = nil
        lastFrame = nil
    }

    func pause() {
        guard !paused, stage == .aiming || stage == .rolling || stage == .sunk else { return }
        paused = true
        dragging = false
        aim = nil
        power = 0
        stop()
        publish()
    }

    func resume() {
        guard paused else { return }
        paused = false
        idleFor = 0
        wake()
    }

    /// The view is on screen again: carry on moving whatever was moving when it went.
    func appeared() {
        guard !paused else { return }
        idleFor = 0
        wake()
    }

    func toggleOverview() {
        overview.toggle()
        idleFor = 0
        wake()
    }

    // MARK: - Flow

    /// The player whose turn it is steps up: off the card and aiming.
    func teeOff() {
        guard stage == .tee else { return }
        SRHaptic.tap()
        stage = .aiming
        idleFor = 0
        overview = false
        assist = MiniGolfAim(angle: (hole.cup - sim.position).angle, power: 0.5)
        wake()
    }

    /// After the hole's scores: the next hole, or the end of the round.
    func nextHole() {
        guard stage == .holeDone else { return }
        if round.nextHole() {
            SRHaptic.tap()
            sim = MiniGolfBallSim(hole: round.hole)
            prepareTee()
        } else {
            finish()
        }
    }

    private func prepareTee() {
        sim.place(at: hole.tee)
        strokes = 0
        sink = 0
        pendingScore = nil
        trail = []
        flashes = Array(repeating: 0, count: hole.posts.count)
        aim = nil
        power = 0
        dragging = false
        newHoleBest = false
        holeInOne = false
        stage = .tee
        // The tee card shows the whole hole; teeing off swoops in on the ball.
        camera = MiniGolfCamera.framing(hole.bounds, width: Double(playRect.width), height: Double(playRect.height),
                                        focus: hole.tee, overview: true)
        publish()
    }

    // MARK: - Aiming

    /// Points of drag for a full-power putt.
    private var fullPull: Double { min(max(Double(min(playRect.width, playRect.height)) * 0.42, 120), 220) }

    /// A finger dragging: `translation` from where it went down, in points.
    /// The putt goes the opposite way, like a catapult.
    func drag(_ translation: CGSize) {
        guard stage == .aiming, !paused else { return }
        if !dragging {
            dragging = true
            powerNotch = 0
            SRHaptic.tap()
            wake()
        }
        idleFor = 0
        let dx = -Double(translation.width), dy = -Double(translation.height)
        let pull = (dx * dx + dy * dy).squareRoot()
        let dead = 8.0
        let p = min(1, max(0, (pull - dead) / fullPull))
        if pull > dead {
            aim = MiniGolfAim(angle: atan2(dy, dx), power: p)
        } else {
            aim = nil
        }
        // A tick every fifth of the way, a firmer one at full.
        let notch = Int(p * 5)
        if notch != powerNotch {
            if notch == 5 { SRHaptic.tap() } else { SRHaptic.select() }
            powerNotch = notch
        }
        power = p
    }

    /// The finger lifts: putt, unless it barely moved.
    func release(_ translation: CGSize) {
        guard dragging else { return }
        drag(translation)
        dragging = false
        let shot = aim
        aim = nil
        power = 0
        guard let shot, shot.power >= 0.03 else {
            publish()
            return
        }
        putt(shot)
    }

    /// The finger left the screen some other way (a call, the app closing).
    func cancelDrag() {
        guard dragging || aim != nil else { return }
        dragging = false
        aim = nil
        power = 0
        publish()
    }

    private func putt(_ shot: MiniGolfAim) {
        guard stage == .aiming, sim.putt(angle: shot.angle, power: shot.power) else { return }
        strokes += 1
        stage = .rolling
        overview = false
        trail = []
        SRHaptic.tap()
        wake()
    }

    // MARK: - VoiceOver aiming

    func assistTurn(_ radians: Double) {
        guard stage == .aiming else { return }
        assist.angle += radians
        showAssist()
    }

    func assistPower(_ change: Double) {
        guard stage == .aiming else { return }
        assist.power = min(1, max(0.05, assist.power + change))
        showAssist()
    }

    func assistAimAtCup() {
        guard stage == .aiming else { return }
        assist.angle = (hole.cup - sim.position).angle
        showAssist()
    }

    func assistPutt() {
        guard stage == .aiming else { return }
        aim = nil
        putt(assist)
    }

    private func showAssist() {
        aim = assist
        idleFor = 0
        wake()
    }

    /// The aim, for VoiceOver: which way, how hard, and where the cup is.
    var assistLine: String {
        let degrees = Self.compass(assist.angle)
        let toCup = hole.cup - sim.position
        let cupDegrees = Self.compass(toCup.angle)
        return "Aiming \(degrees) degrees at \(Int((assist.power * 100).rounded())) percent power. The cup is \(cupDegrees) degrees, \(Int(toCup.length.rounded())) units away."
    }

    /// An angle as whole degrees clockwise from straight up the screen, 0 to 359,
    /// however many times VoiceOver has turned the aim round.
    private static func compass(_ angle: Double) -> Int {
        guard angle.isFinite else { return 0 }
        var degrees = (angle * 180 / .pi + 90).truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        return Int(degrees.rounded()) % 360
    }

    // MARK: - The frame

    /// Start the display link if it is not running.
    private func wake() {
        guard ticker == nil, !paused else { return }
        lastFrame = nil
        let ticker = FrameTicker { [weak self] time in
            guard let self else { return false }
            return self.frame(time)
        }
        self.ticker = ticker
        ticker.start()
    }

    /// One display frame. False stops the link.
    private func frame(_ time: Double) -> Bool {
        // After a pause (a call, the app in the background) one short step, not the whole gap.
        let dt = lastFrame.map { min(max(0, time - $0), 1.0 / 20) } ?? 0
        lastFrame = time
        guard !paused else {
            ticker = nil
            return false
        }
        events.removeAll(keepingCapacity: true)
        let wasRolling = sim.state == .rolling
        sim.advance(dt, events: &events)
        for event in events { react(to: event) }
        if wasRolling && sim.state != .rolling { shotEnded() }
        animate(dt)
        publish()
        if keepTicking(dt) { return true }
        ticker = nil
        lastFrame = nil
        return false
    }

    private func keepTicking(_ dt: Double) -> Bool {
        let busy = !particles.isEmpty || !ripples.isEmpty || (sink > 0 && sink < 1)
        switch stage {
        case .rolling, .sunk:
            return true
        case .aiming:
            // Every drag event and VoiceOver step resets `idleFor`, so a finger
            // held still keeps the course moving; but a drag the system took
            // away without a lift (no onEnded) or a VoiceOver aim left showing
            // does not keep the display link running for ever.
            idleFor += dt
            if idleFor < Self.idleAfter || busy { return true }
            if dragging { cancelDrag() }
            return false
        case .tee, .holeDone, .finished:
            let target = targetCamera()
            let settled = abs(target.scale - camera.scale) < 0.01 && target.centre.distance(to: camera.centre) < 0.05
            return busy || !settled
        }
    }

    private func animate(_ dt: Double) {
        if sim.state == .rolling && sim.speed > 5 {
            trail.append(sim.position)
            if trail.count > 14 { trail.removeFirst(trail.count - 14) }
        } else if !trail.isEmpty {
            trail.removeFirst()
        }
        if sim.state == .holed { sink = min(1, sink + dt * 4) }

        var alive = 0
        for i in particles.indices {
            var p = particles[i]
            p.life -= dt
            guard p.life > 0 else { continue }
            p.at += p.velocity * dt
            // Confetti floats and slows; drops and flecks slow fast.
            let damping: Double = (p.tone == .water || p.tone == .sand) ? 4.0 : 1.6
            p.velocity = p.velocity * max(0, 1 - damping * dt)
            p.spin += p.spinRate * dt
            particles[alive] = p
            alive += 1
        }
        particles.removeLast(particles.count - alive)

        var kept = 0
        for i in ripples.indices {
            var r = ripples[i]
            r.age += dt
            guard r.age < r.span else { continue }
            ripples[kept] = r
            kept += 1
        }
        ripples.removeLast(ripples.count - kept)

        for i in flashes.indices where flashes[i] > 0 { flashes[i] = max(0, flashes[i] - dt) }

        if toast != nil {
            toastTimer -= dt
            if toastTimer <= 0 { toast = nil }
        }
        if stage == .sunk {
            sunkTimer -= dt
            if sunkTimer <= 0 { afterSunk() }
        }
        let rate: Double = stage == .rolling ? 4 : 2.5
        camera = camera.eased(towards: targetCamera(), dt: dt, rate: calm ? rate * 3 : rate)
    }

    private func targetCamera() -> MiniGolfCamera {
        let w = Double(playRect.width), h = Double(playRect.height)
        let showAll = overview || stage == .tee || stage == .holeDone || stage == .finished
        let ball = sim.position
        // While aiming, look a little towards the cup so the target is in view.
        let focus = stage == .aiming ? ball + (hole.cup - ball) * 0.3 : ball
        return MiniGolfCamera.framing(hole.bounds, width: w, height: h, focus: focus, overview: showAll)
    }

    private func publish() {
        var snap = MiniGolfSnapshot(hole: hole, ball: sim.position, camera: camera, playRect: playRect)
        snap.ballSink = sink
        snap.showBall = sink < 1
        snap.clock = sim.clock
        snap.trail = trail
        snap.particles = particles
        snap.ripples = ripples
        snap.flashes = flashes
        snap.aim = aim
        snap.seat = player.seat
        scene.show(snap)
    }

    // MARK: - What happened

    private func react(to event: MiniGolfEvent) {
        switch event {
        case .wall(let at, let speed):
            if speed > 9 { buzz { SRHaptic.select() } }
            if speed > 20 { burst(at, count: 4, tone: .spark, speed: 8) }
        case .post(let at, let speed):
            if speed > 6 { buzz { SRHaptic.select() } }
            if speed > 16 { burst(at, count: 3, tone: .spark, speed: 7) }
        case .bumper(let index, let at, _):
            if flashes.indices.contains(index) { flashes[index] = 0.35 }
            let post = hole.posts[index]
            ripples.append(MiniGolfRipple(at: post.centre, age: 0, span: 0.35, radius: post.radius + 1.6, tone: .bumper))
            burst(at, count: 8, tone: .spark, speed: 14)
            buzz { SRHaptic.tap() }
        case .sail(let at, _):
            burst(at, count: 5, tone: .spark, speed: 9)
            buzz { SRHaptic.tap() }
        case .sand(let at):
            burst(at, count: 12, tone: .sand, speed: 10)
            buzz { SRHaptic.select() }
        case .splash(let at):
            burst(at, count: 22, tone: .water, speed: 16)
            ripples.append(MiniGolfRipple(at: at, age: 0, span: 0.9, radius: 4.5, tone: .water))
            ripples.append(MiniGolfRipple(at: at, age: -0.2, span: 0.9, radius: 3, tone: .water))
        case .lipOut:
            // Only a near miss is news: a full-power putt racing over the cup is not.
            if sim.speed < MiniGolfRules.lipSpeed * 2.2 {
                show("Lipped out! Too quick to drop.")
                buzz { SRHaptic.select() }
            }
        case .holed:
            ripples.append(MiniGolfRipple(at: hole.cup, age: 0, span: 0.6, radius: 4, tone: .cup))
        case .stopped:
            break
        }
    }

    /// A haptic, but never two within a fraction of a second.
    private func buzz(_ fire: () -> Void) {
        let now = sim.clock
        guard now - lastHaptic > 0.07 || now < lastHaptic else { return }
        lastHaptic = now
        fire()
    }

    private func show(_ line: String) {
        toast = line
        toastTimer = 2.2
    }

    private func burst(_ at: MiniGolfVec, count: Int, tone: MiniGolfParticle.Tone, speed: Double) {
        let room = Self.particleCap - particles.count
        let wanted = calm ? max(1, count / 4) : count
        guard room > 0 else { return }
        for i in 0..<min(wanted, room) {
            let angle = Double.random(in: 0..<(2 * .pi))
            let v = MiniGolfVec.heading(angle) * (speed * Double.random(in: 0.35...1))
            let span: Double
            let size: Double
            let colour: MiniGolfParticle.Tone
            switch tone {
            case .confetti:
                span = Double.random(in: 1.4...2.4)
                size = Double.random(in: 0.45...0.8)
                colour = .confetti(i % 6)
            case .gold:
                span = Double.random(in: 1.6...2.8)
                size = Double.random(in: 0.3...0.55)
                colour = .gold
            case .water:
                span = Double.random(in: 0.45...0.8)
                size = Double.random(in: 0.25...0.5)
                colour = .water
            case .sand:
                span = Double.random(in: 0.35...0.6)
                size = Double.random(in: 0.18...0.35)
                colour = .sand
            case .spark:
                span = Double.random(in: 0.2...0.4)
                size = Double.random(in: 0.15...0.3)
                colour = .spark
            }
            particles.append(MiniGolfParticle(at: at, velocity: v, life: span, span: span, size: size, tone: colour,
                                              spin: angle, spinRate: Double.random(in: -8...8)))
        }
    }

    private func shotEnded() {
        switch sim.state {
        case .holed:
            holed()
        case .splashed:
            SRHaptic.bad()
            strokes += 1
            show("Splash! One stroke added, back to where you putted from.")
            sim.returnToLastSpot()
            outOfStrokesOrAim()
        case .resting:
            outOfStrokesOrAim()
        case .rolling:
            break
        }
    }

    private func outOfStrokesOrAim() {
        if strokes >= maxStrokes {
            // Enough: picked up, and the most the hole takes goes on the card.
            sunkWord = "Picked up"
            sunkStrokes = maxStrokes
            record(maxStrokes)
            sink = 1
            sunkTimer = 1.8
            stage = .sunk
        } else {
            stage = .aiming
            idleFor = 0
            assist = MiniGolfAim(angle: (hole.cup - sim.position).angle, power: assist.power)
        }
    }

    private func holed() {
        let score = min(strokes, maxStrokes)
        holeInOne = score == 1
        sunkWord = MiniGolfScoreWord.word(strokes: score, par: hole.par)
        sunkStrokes = score
        record(score)
        sink = 0.01
        sunkTimer = holeInOne ? 3.2 : 2.0
        stage = .sunk
        SRHaptic.ok()
        if holeInOne {
            burst(hole.cup, count: 90, tone: .confetti(0), speed: 26)
            burst(hole.cup, count: 40, tone: .gold, speed: 20)
        } else if score < hole.par {
            burst(hole.cup, count: 46, tone: .confetti(0), speed: 20)
        } else {
            burst(hole.cup, count: 12, tone: .confetti(0), speed: 10)
        }
    }

    /// The hole's best is kept at once (so an app closed now still has it);
    /// the scorecard gets the score when the banner goes, so the instruments
    /// keep showing the player who just finished until then.
    private func record(_ score: Int) {
        var book = self.book
        newHoleBest = book.noteHole(hole.number, strokes: score)
        store.save(book)
        self.book = book
        pendingScore = score
    }

    private func afterSunk() {
        if let pending = pendingScore {
            round.record(strokes: pending)
            pendingScore = nil
        }
        if round.holeDone {
            stage = .holeDone
        } else {
            // The next player to the tee.
            sim.place(at: hole.tee)
            strokes = 0
            sink = 0
            trail = []
            newHoleBest = false
            holeInOne = false
            stage = .tee
        }
    }

    private func finish() {
        let best = round.players.indices.map { round.total($0) }.min() ?? 0
        var book = self.book
        newRoundBest = book.noteRound(round.loop, strokes: best)
        store.save(book)
        self.book = book
        stage = .finished
        SRHaptic.ok()
        burst(hole.cup, count: 60, tone: .confetti(0), speed: 22)
        wake()
    }
}
