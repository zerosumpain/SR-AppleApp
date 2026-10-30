import SwiftUI
import UIKit

/// What a spark is, so the drawing picks its colour and shape.
enum SkyHopperSparkKind {
    case puff, star, crumb, bubble, power
}

/// One spark, in world units: flung from a point, falling as it fades.
struct SkyHopperSpark {
    let x: Double
    let y: Double
    /// Units a second; up is +.
    let vx: Double
    let vy: Double
    /// Play time it was born at, seconds.
    let born: Double
    let life: Double
    /// Radius in units.
    let size: Double
    let kind: SkyHopperSparkKind
}

/// "+5" rising from a star; "Saved" off a bubble.
struct SkyHopperPop {
    let text: String
    let x: Double
    let y: Double
    let born: Double
    let gold: Bool
}

/// The power-ups running, rounded so the HUD changes once a second, not
/// every frame.
struct SkyHopperPowers: Equatable {
    var propeller = 0
    var magnet = 0
    var bubble = false

    var isEmpty: Bool { propeller == 0 && magnet == 0 && !bubble }
}

/// The beat the sky is drawn to. Only the board's canvas watches it, so a
/// frame redraws the sky and nothing else on the screen.
@MainActor
final class SkyHopperClock: ObservableObject {
    /// Play time in seconds: it stops while paused, so nothing jumps on resume.
    @Published var now: Double = 0
}

/// Sky Hopper's engine on this phone: a display link that reads the tilt
/// (or the buttons, or the demo's pilot) once a frame, steps the rules on a
/// fixed beat, keeps the sparks, and publishes only what the HUD and cards
/// show. The link and the sensor run while Hop is moving and stop the
/// moment it is not.
@MainActor
final class SkyHopperSession: ObservableObject {
    enum Stage: Equatable {
        /// The card with how to play and the settings.
        case intro
        /// In the sky, waiting for a tap.
        case ready
        case playing
        case paused
        /// Hop has fallen; a moment before the card.
        case falling
        case over
    }

    @Published private(set) var stage: Stage = .intro
    @Published private(set) var score = 0
    @Published private(set) var metres = 0
    @Published private(set) var stars = 0
    @Published private(set) var zone: SkyHopperZone = .meadow
    @Published private(set) var powers = SkyHopperPowers()
    @Published private(set) var records: SkyHopperRecords
    @Published private(set) var result: SkyHopperRunResult?
    /// A short line over the sky: a new zone, a colour opened.
    @Published private(set) var toast: String?
    /// Waiting after a pause rather than before a new run.
    @Published private(set) var resuming = false

    let clock = SkyHopperClock()
    let tilt = PhysicsTilt()
    /// Demo mode flies itself: no sensor, no finger, the screenshots still move.
    let scripted = SRDemo.isOn

    private(set) var game: SkyHopperGame
    /// How far into the next step, 0 to 1, for drawing between steps.
    private(set) var fraction: Double = 0
    private(set) var sparks: [SkyHopperSpark] = []
    private(set) var pops: [SkyHopperPop] = []
    private(set) var endedAt: Double?
    private(set) var savedAt: Double = -10

    private var playTime: Double = 0
    private var ticker: FrameTicker?
    private var lastFrame: Double?
    private var accumulator: Double = 0
    private var readySince: Double = 0
    private var leftHeld = false
    private var rightHeld = false
    /// A VoiceOver press steers for a moment.
    private var nudgeWay: Double = 0
    private var nudgeUntil: Double = -1
    /// The tilt, eased so a shaky hand is not a shaky Hop.
    private var lean: Double = 0
    private var viewHeight: Double = 160
    private var runControl: SkyHopperControl = .buttons
    private var toastTask: Task<Void, Never>?
    private var announced: Set<String> = []
    private let store = SkyHopperRecordStore()
    /// The demo's runs are not this phone's own, so they are not kept.
    private var persists: Bool { !scripted }

    /// The demo climbs this long, then lets Hop fall so the card is seen.
    static let demoClimb = 20.0

    init() {
        records = SkyHopperRecordStore().load()
        game = SkyHopperGame(seed: 1)
    }

    // MARK: - What the screen reads

    var control: SkyHopperControl { records.control(tiltAvailable: tilt.available) }
    /// VoiceOver cannot tilt-and-listen: the arrows are always on for it.
    private(set) var forceButtons = false
    /// The arrows are on screen: chosen, no sensor, or VoiceOver.
    var showsButtons: Bool { !scripted && (control == .buttons || forceButtons) }
    var steersByTilt: Bool { control == .tilt && tilt.available && !scripted && !forceButtons }
    var colour: SkyHopperColour { records.activeColour }
    /// The way this run is steered, and so whose best it is.
    var effectiveControl: SkyHopperControl { forceButtons ? .buttons : control }
    var best: Int { records.best(effectiveControl).score }
    var isSteering: Bool { stage == .ready || stage == .playing }

    // MARK: - Settings, on the intro card

    func setVoiceOver(_ on: Bool) {
        guard forceButtons != on else { return }
        objectWillChange.send()
        forceButtons = on
        if on { tilt.stop() } else if stage == .playing && steersByTilt { tilt.start() }
    }

    func choose(_ control: SkyHopperControl) {
        guard stage == .intro else { return }
        if control == .tilt && !tilt.available { return }
        records.control = control
        save()
    }

    func choose(colour: SkyHopperColour) {
        guard records.isUnlocked(colour), records.colour != colour else { return }
        records.colour = colour
        save()
    }

    /// The board's shape, as world units of sky above its width of 100.
    func fit(width: Double, height: Double) {
        guard width > 1, height > 1 else { return }
        let wanted = height / width * SkyHopperRules.width
        guard abs(wanted - viewHeight) > 0.5 else { return }
        viewHeight = wanted
        game.resize(viewHeight: wanted)
    }

    // MARK: - Playing

    /// A new run, Hop on the home cloud waiting for a tap.
    func play() {
        let seed: UInt64 = scripted ? 7 : UInt64.random(in: 1...UInt64.max)
        game = SkyHopperGame(seed: seed, viewHeight: viewHeight)
        runControl = effectiveControl
        sparks.removeAll()
        pops.removeAll()
        fraction = 0
        accumulator = 0
        endedAt = nil
        savedAt = -10
        result = nil
        announced = []
        lean = 0
        releaseButtons()
        resuming = false
        sync()
        readySince = playTime
        stage = .ready
        startClock()
        if scripted { go() }
    }

    /// A tap on the sky, or a press of an arrow: off we go.
    func start() {
        guard stage == .ready else { return }
        SRHaptic.tap()
        go()
    }

    private func go() {
        resuming = false
        stage = .playing
        if steersByTilt { tilt.start() }
        lean = 0
        startClock()
    }

    func pause() {
        guard stage == .playing || stage == .ready else { return }
        stage = .paused
        releaseButtons()
        tilt.stop()
        stopClock()
    }

    /// Back in the sky, waiting for a tap to carry on.
    func resume() {
        guard stage == .paused else { return }
        SRHaptic.tap()
        if scripted {
            go()
            return
        }
        resuming = true
        readySince = playTime
        stage = .ready
        startClock()
    }

    /// Back to the card with the settings.
    func menu() {
        stopClock()
        tilt.stop()
        result = nil
        stage = .intro
        game = SkyHopperGame(seed: 1, viewHeight: viewHeight)
        sparks.removeAll()
        pops.removeAll()
        endedAt = nil
        sync()
        clock.now = playTime
    }

    /// The scene went to the background.
    func sleep() {
        pause()
    }

    /// Off screen: stop everything. A fall mid-animation still gets its card.
    func leave() {
        pause()
        if stage == .falling { finish() }
        stopClock()
        tilt.stop()
        toastTask?.cancel()
    }

    // MARK: - Steering

    func hold(left: Bool, down: Bool) {
        if left { leftHeld = down } else { rightHeld = down }
        if down && stage == .ready { start() }
    }

    /// VoiceOver's press of an arrow: a short steer that way.
    func nudge(left: Bool) {
        if stage == .ready { start() }
        guard stage == .playing else { return }
        nudgeWay = left ? -1 : 1
        nudgeUntil = playTime + 0.35
    }

    func recentre() {
        tilt.recentre()
        lean = 0
    }

    private func releaseButtons() {
        leftHeld = false
        rightHeld = false
        nudgeUntil = -1
    }

    /// Where Hop is steered this frame, −1…1. Read once a frame.
    private func steer() -> Double {
        if scripted { return SkyHopperAutopilot.steer(for: game, giveUpAfter: Self.demoClimb) }
        if steersByTilt {
            // A third of a g is the full lean; a little in the middle is nothing.
            let raw = tilt.lean() ?? 0
            let live = abs(raw) < 0.03 ? 0 : raw
            let wanted = min(1, max(-1, live / 0.30))
            lean += (wanted - lean) * 0.5
            return lean
        }
        if playTime < nudgeUntil { return nudgeWay }
        var way = 0.0
        if rightHeld { way += 1 }
        if leftHeld { way -= 1 }
        return way
    }

    // MARK: - The clock

    private func startClock() {
        guard ticker == nil else { return }
        lastFrame = nil
        let ticker = FrameTicker { [weak self] time in
            guard let self else { return false }
            return self.frame(time)
        }
        self.ticker = ticker
        ticker.start()
    }

    private func stopClock() {
        ticker?.stop()
        ticker = nil
        lastFrame = nil
    }

    /// One display frame. False stops the link.
    private func frame(_ time: Double) -> Bool {
        // After a stall (a call, a notification pulled down) step a short
        // moment, not the whole gap.
        let dt = lastFrame.map { min(max(0, time - $0), 1.0 / 15) } ?? 0
        lastFrame = time
        playTime += dt
        switch stage {
        case .playing:
            advance(dt)
        case .falling:
            if let at = endedAt, playTime - at >= 1.1 { finish() }
        default:
            break
        }
        if !sparks.isEmpty { sparks.removeAll { playTime - $0.born > $0.life } }
        if !pops.isEmpty { pops.removeAll { playTime - $0.born > 0.9 } }
        clock.now = playTime
        let running: Bool
        switch stage {
        case .playing, .falling: running = true
        // Waiting for a tap: Hop breathes a while, then the sky holds still.
        case .ready: running = playTime - readySince < 25
        default: running = false
        }
        if !running {
            ticker = nil
            lastFrame = nil
        }
        return running
    }

    /// The steps owed since the last frame, at most eight (one fifteenth of
    /// a second), then where between steps Hop is drawn.
    private func advance(_ dt: Double) {
        accumulator += dt
        let direction = steer()
        var events = SkyHopperEvents()
        var steps = 0
        while accumulator >= SkyHopperRules.step && steps < 8 {
            accumulator -= SkyHopperRules.step
            steps += 1
            events.merge(game.step(steer: direction))
            if game.isOver { break }
        }
        if steps == 8 { accumulator = min(accumulator, SkyHopperRules.step) }
        fraction = min(1, max(0, accumulator / SkyHopperRules.step))
        if !events.isEmpty { react(to: events) }
        if stage == .playing { sync() }
    }

    private func react(to events: SkyHopperEvents) {
        for landing in events.landings {
            if landing.spring {
                SRHaptic.select()
                burst(x: landing.x, y: landing.y, kind: .star, count: 10, speed: 40)
            }
            burst(x: landing.x, y: landing.y, kind: landing.kind == .crumbly ? .crumb : .puff, count: 6, speed: 18)
        }
        for grab in events.grabs {
            switch grab.kind {
            case .star:
                SRHaptic.tap()
                burst(x: grab.x, y: grab.y, kind: .star, count: 8, speed: 30)
                pops.append(SkyHopperPop(text: "+\(SkyHopperRules.starPoints)", x: grab.x, y: grab.y, born: playTime, gold: true))
            case .propeller, .bubble, .magnet:
                SRHaptic.ok()
                burst(x: grab.x, y: grab.y, kind: .power, count: 14, speed: 36)
                pops.append(SkyHopperPop(text: grab.kind.title, x: grab.x, y: grab.y, born: playTime, gold: false))
            }
        }
        if events.saved {
            SRHaptic.ok()
            savedAt = playTime
            let hop = game.hopper
            burst(x: hop.x, y: hop.y + SkyHopperRules.hopperHeight / 2, kind: .bubble, count: 16, speed: 34)
            pops.append(SkyHopperPop(text: "Saved by the bubble", x: hop.x, y: hop.y + 14, born: playTime, gold: false))
        }
        if let zone = events.zone {
            SRHaptic.select()
            show("\(zone.name) · \(zone.metres) m")
        }
        if events.fell { end() }
    }

    /// The HUD's numbers, published only when they change.
    private func sync() {
        if score != game.score { score = game.score }
        if metres != game.metres { metres = game.metres }
        if stars != game.stars {
            stars = game.stars
            noteColours()
        }
        if zone != game.zone { zone = game.zone }
        let now = SkyHopperPowers(propeller: Int(game.propellerLeft.rounded(.up)),
                                  magnet: Int(game.magnetLeft.rounded(.up)), bubble: game.hasBubble)
        if powers != now { powers = now }
    }

    /// Mid-run: say so the moment the stars open a colour.
    private func noteColours() {
        guard let next = records.nextColour, records.totalStars + game.stars >= next.unlockStars,
              !announced.contains(next.rawValue) else { return }
        announced.insert(next.rawValue)
        show("New colour: \(next.title)")
        SRHaptic.ok()
    }

    private func show(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    /// Hop fell. The record is kept now, in case the screen is left before
    /// the card comes up.
    private func end() {
        sync()
        endedAt = playTime
        stage = .falling
        releaseButtons()
        tilt.stop()
        SRHaptic.bad()
        result = records.record(game, control: runControl)
        save()
    }

    private func finish() {
        guard stage == .falling else { return }
        stage = .over
        stopClock()
        if result?.newBest == true { SRHaptic.ok() }
    }

    private func save() {
        guard persists else { return }
        store.save(records)
    }

    // MARK: - Sparks

    private func burst(x: Double, y: Double, kind: SkyHopperSparkKind, count: Int, speed: Double) {
        guard sparks.count < 160 else { return }
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * Double.pi + Double.random(in: -0.3...0.3)
            let v = speed * Double.random(in: 0.45...1.0)
            let lift = kind == .puff || kind == .crumb ? 0.3 : 1.0
            sparks.append(SkyHopperSpark(x: x, y: y, vx: cos(angle) * v, vy: abs(sin(angle)) * v * lift,
                                         born: playTime, life: Double.random(in: 0.35...0.7),
                                         size: Double.random(in: 0.8...1.8), kind: kind))
        }
    }
}
