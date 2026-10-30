import Foundation

/// Something that happened in a frame, for the screen to answer with a
/// haptic, a burst of colour or a card.
enum OrbitRunEvent: Equatable {
    case launched
    /// The level's star `index` was picked up.
    case star(Int)
    /// The flight is over.
    case ended(OrbitEnd)
}

/// Where a go at a level is: aiming, a probe in the air, or the moment
/// after a flight has ended while the sparks settle and the sky winds back.
enum OrbitRunPhase: Equatable {
    case aiming
    case flying
    case ended(OrbitEnd)
}

/// One level being played on this phone: the aim, the probe in flight, the
/// path it has drawn and the path of the one before, the sparks, and the
/// clock that turns the moons. No drawing and no timers: the screen calls
/// `advance` once a display frame and draws what it finds.
///
/// Physics always moves in `OrbitPhysics.dt` steps, whatever the frame rate,
/// so a flight on a 120 Hz phone is the flight the aiming line promised on a
/// 60 Hz one.
struct OrbitRun {
    let level: OrbitLevel
    private(set) var attempt: OrbitAttempt
    private(set) var aim: OrbitShot
    private(set) var prediction: OrbitPrediction = .empty
    private(set) var phase: OrbitRunPhase = .aiming
    private(set) var flight: OrbitFlight?
    /// This flight's path, a point every `pathEvery` steps.
    private(set) var path: [OrbitVec] = []
    /// The last flight's path, drawn faintly so the next aim can learn from it.
    private(set) var lastPath: [OrbitVec] = []
    private(set) var sparks = OrbitSparks()
    /// Seconds the screen has been animating: twinkles, spins, the aiming ghost.
    private(set) var clock: Double = 0
    /// The moment the moons and moving stations are drawn at: the flight's
    /// own time while flying, winding back to the launch moment after.
    private(set) var skyTime: Double = 0
    /// A little shake after a crash, 0…1.
    private(set) var shake: Double = 0
    /// Seconds since the flight ended, while `phase` is `.ended`.
    private(set) var sinceEnd: Double = 0
    /// Flights run this many times faster than life: 1, or 2 with the fast button.
    var speed: Double = 1

    private var accumulator: Double = 0
    private var rewindFrom: Double = 0

    static let pathEvery = 4
    /// How long the sky holds still after a flight ends, then how long it
    /// takes to wind back to the moment of launch.
    static let holdAfterEnd = 0.45
    static let rewind = 0.6
    /// When the screen can offer the next launch (or the results) after a flight ends.
    static let settle = holdAfterEnd + rewind

    init(level: OrbitLevel, aim: OrbitShot? = nil) {
        self.level = level
        attempt = OrbitAttempt(level: level)
        let start = aim ?? OrbitShot(angle: level.pad.facing, power: 0.5)
        self.aim = OrbitShot(angle: level.pad.clamp(start.angle), power: min(max(start.power, 0), 1))
        path.reserveCapacity(1200)
        prediction = OrbitFlight.predict(level, shot: self.aim, seconds: level.preview, every: Self.predictEvery)
    }

    /// The aiming line keeps a point every this many steps (60 a second).
    static let predictEvery = 4

    /// Which stars are picked up: this attempt's, plus any the probe in the
    /// air has just collected.
    var collected: [Bool] {
        if let flight { return zip(flight.collected, attempt.collected).map { $0 || $1 } }
        return attempt.collected
    }

    var isAiming: Bool { phase == .aiming }
    var isFlying: Bool { phase == .flying }

    /// Battery left in the air, 0…1.
    var battery: Double {
        guard let flight else { return 1 }
        return max(0, 1 - flight.time / max(level.timeLimit, 0.1))
    }

    /// A new aim, kept inside what the pad allows, and the line redrawn.
    mutating func setAim(_ shot: OrbitShot) {
        let next = OrbitShot(angle: level.pad.clamp(shot.angle), power: min(max(shot.power, 0), 1))
        guard next != aim || prediction.points.isEmpty else { return }
        aim = next
        prediction = OrbitFlight.predict(level, shot: aim, seconds: level.preview, every: Self.predictEvery)
    }

    /// Turns the aim by `degrees` and changes the power by `power` (0…1 scale).
    mutating func nudge(degrees: Double = 0, power: Double = 0) {
        setAim(OrbitShot(angle: aim.angle + degrees * Double.pi / 180, power: aim.power + power))
    }

    /// Sends a probe off with the current aim. False when there is none left
    /// to send, or one is already in the air.
    @discardableResult
    mutating func launch() -> Bool {
        guard phase == .aiming, attempt.probesLeft > 0, !attempt.arrived else { return false }
        flight = OrbitFlight(level: level, shot: aim, collected: attempt.collected)
        if !path.isEmpty { lastPath = path }
        path.removeAll(keepingCapacity: true)
        path.append(level.pad.at)
        accumulator = 0
        skyTime = 0
        phase = .flying
        return true
    }

    /// Calls the probe in the air off; it counts as a launch.
    mutating func abort() -> [OrbitRunEvent] {
        guard phase == .flying, var f = flight else { return [] }
        f.abort()
        flight = f
        return finish(f)
    }

    /// A new go at the same level: every probe back, no stars, the aim kept.
    mutating func restart() {
        let keep = aim
        let ghost = path.isEmpty ? lastPath : path
        self = OrbitRun(level: level, aim: keep)
        lastPath = ghost
    }

    /// After a flight has ended and settled: back to aiming for the next probe.
    mutating func ready() {
        guard case .ended = phase else { return }
        flight = nil
        phase = .aiming
        skyTime = 0
        shake = 0
        sinceEnd = 0
    }

    /// One display frame of `dt` seconds.
    mutating func advance(_ dt: Double) -> [OrbitRunEvent] {
        let frame = min(max(dt, 0), 1.0 / 20)
        clock += frame
        sparks.step(frame)
        shake = max(0, shake - frame * 2.4)
        var events: [OrbitRunEvent] = []
        switch phase {
        case .aiming:
            break
        case .flying:
            events = fly(frame * speed)
        case .ended:
            sinceEnd += frame
            // Hold, then wind the moons back to where they were at launch.
            if sinceEnd > Self.holdAfterEnd {
                let k = min(1, (sinceEnd - Self.holdAfterEnd) / Self.rewind)
                let eased = k * k * (3 - 2 * k)
                skyTime = rewindFrom * (1 - eased)
            }
        }
        return events
    }

    private mutating func fly(_ dt: Double) -> [OrbitRunEvent] {
        guard var f = flight else { return [] }
        var events: [OrbitRunEvent] = []
        accumulator += dt
        while accumulator >= OrbitPhysics.dt && f.flying {
            accumulator -= OrbitPhysics.dt
            let result = f.step()
            if f.steps % Self.pathEvery == 0 { path.append(f.position) }
            if let star = result.star {
                events.append(.star(star))
                if level.stars.indices.contains(star) {
                    sparks.burst(at: level.stars[star], count: 22, speed: 90, life: 0.7, size: 2.6, tone: .gold)
                }
            }
        }
        flight = f
        skyTime = f.time
        if !f.flying {
            path.append(f.position)
            events.append(contentsOf: finish(f))
        }
        return events
    }

    /// Books an ended flight into the attempt and sets the sparks going.
    private mutating func finish(_ f: OrbitFlight) -> [OrbitRunEvent] {
        guard let end = f.end else { return [] }
        attempt.record(f)
        rewindFrom = f.time
        skyTime = f.time
        sinceEnd = 0
        phase = .ended(end)
        let carry = f.velocity * 0.15
        switch end {
        case .arrived:
            let at = level.target.position(at: f.time)
            sparks.burst(at: at, count: 90, speed: 170, life: 1.3, size: 3.2,
                         tone: level.target.kind == .station ? .dock : .warp)
            sparks.burst(at: at, count: 30, speed: 60, life: 1.6, size: 2.2, tone: .gold)
        case .crashed, .asteroids:
            sparks.burst(at: f.position, count: 70, speed: 150, life: 0.9, size: 3, tone: .fire, carry: carry)
            shake = 1
        case .burned:
            sparks.burst(at: f.position, count: 60, speed: 110, life: 0.8, size: 3.4, tone: .fire)
            shake = 0.6
        case .swallowed:
            sparks.burst(at: f.position, count: 40, speed: 50, life: 0.9, size: 2.2, tone: .warp)
        case .flat:
            sparks.burst(at: f.position, count: 18, speed: 30, life: 0.8, size: 2, tone: .dock)
        case .lost, .aborted:
            break
        }
        return [.ended(end)]
    }

    /// While aiming: where a ghost probe is along the aiming line, looping,
    /// so a player can see how its timing meets the moons. Nil when the line
    /// is too short to bother.
    var ghostTime: Double? {
        guard phase == .aiming, prediction.points.count > 6 else { return nil }
        let shown = Double(prediction.points.count - 1) * Double(Self.predictEvery) * OrbitPhysics.dt
        let loop = shown + 0.8
        let t = clock.truncatingRemainder(dividingBy: loop)
        return min(t, shown)
    }

    /// The ghost probe's place on the aiming line at `t` seconds after launch.
    func ghostPoint(at t: Double) -> OrbitVec? {
        guard !prediction.points.isEmpty else { return nil }
        let per = Double(Self.predictEvery) * OrbitPhysics.dt
        let index = min(prediction.points.count - 1, max(0, Int(t / per)))
        return prediction.points[index]
    }
}
