import Foundation

/// Orbit's physics: softened inverse-square gravity from every body, stepped
/// with velocity Verlet (kick, drift, kick) at a fixed small timestep. The
/// scheme is symplectic, so an orbit keeps its energy for as long as you
/// watch it instead of spiralling in or out, and the same launch always flies
/// the same path — on the aiming line, on the screen and in the tests.
enum OrbitPhysics {
    /// One physics step, seconds. The screen runs as many as the frame needs.
    static let dt = 1.0 / 240
    /// Gravity is softened over this distance so a near miss does not fling
    /// the probe to infinity.
    static let softening = 6.0
    /// Launch speeds at no power and full power, units a second.
    static let minSpeed = 40.0
    static let maxSpeed = 280.0
    static let probeRadius = 4.0
    /// A star is picked up within this distance of its middle.
    static let starReach = 18.0
    /// How far above the ground a planet's pad holds the probe.
    static let padLift = 7.0
    /// Probes for a level; run out before arriving and the level starts again.
    static let probes = 5

    /// The pull on a probe at `p`, `t` seconds after launch.
    static func acceleration(at p: OrbitVec, bodies: [OrbitBody], time t: Double) -> OrbitVec {
        let e2 = softening * softening
        var ax = 0.0, ay = 0.0
        for body in bodies {
            let c = body.position(at: t)
            let dx = c.x - p.x, dy = c.y - p.y
            let r2 = dx * dx + dy * dy + e2
            let inv = 1 / (r2 * r2.squareRoot())
            ax += body.mass * dx * inv
            ay += body.mass * dy * inv
        }
        return OrbitVec(ax, ay)
    }

    /// The potential energy per unit mass at `p`: the other half of the
    /// energy the integrator must keep.
    static func potential(at p: OrbitVec, bodies: [OrbitBody], time t: Double) -> Double {
        let e2 = softening * softening
        var phi = 0.0
        for body in bodies {
            let r2 = p.distanceSquared(to: body.position(at: t))
            phi -= body.mass / (r2 + e2).squareRoot()
        }
        return phi
    }

    /// The speed of a circular orbit `radius` from a body of `mass`, with the
    /// softening allowed for. Levels use it to place things; tests use it too.
    static func circularSpeed(mass: Double, radius: Double) -> Double {
        let r2 = radius * radius + softening * softening
        return (mass * radius * radius / (r2 * r2.squareRoot())).squareRoot()
    }
}

/// How a flight ended.
enum OrbitEnd: Equatable {
    case arrived
    /// Hit `bodies[index]`.
    case crashed(Int)
    /// Flew into the sun at `bodies[index]`.
    case burned(Int)
    /// Fell into the black hole at `bodies[index]`.
    case swallowed(Int)
    case asteroids
    /// Drifted out past the edge of the map.
    case lost
    /// The battery ran out before it arrived.
    case flat
    /// The player called it off.
    case aborted

    var arrived: Bool { self == .arrived }

    /// A short line for the toast after a launch that did not make it.
    func sentence(in level: OrbitLevel) -> String {
        func name(_ i: Int) -> String { level.bodies.indices.contains(i) ? level.bodies[i].name : "a planet" }
        switch self {
        case .arrived: return level.target.kind == .station ? "Docked!" : "Through the wormhole!"
        case .crashed(let i): return "Crashed into \(name(i))."
        case .burned: return "Burned up in the sun."
        case .swallowed: return "Swallowed by the black hole."
        case .asteroids: return "Smashed in the asteroids."
        case .lost: return "Lost in deep space."
        case .flat: return "The battery ran out."
        case .aborted: return "Probe called off."
        }
    }
}

/// What one step did, beyond moving: a star picked up, or the end of the flight.
struct OrbitStepResult: Equatable {
    var star: Int?
    var end: OrbitEnd?
}

/// One probe in flight, from the pad to whatever ends it.
struct OrbitFlight {
    let level: OrbitLevel
    private(set) var position: OrbitVec
    private(set) var velocity: OrbitVec
    /// Seconds since launch; moons and moving targets are placed by it.
    private(set) var time: Double = 0
    private(set) var steps = 0
    /// Which of the level's stars are picked up, this flight and any before it.
    private(set) var collected: [Bool]
    private(set) var end: OrbitEnd?
    /// The pull at `position`, carried from one step to the next (the second
    /// kick of one step is the first of the next).
    private var accel: OrbitVec

    init(level: OrbitLevel, shot: OrbitShot, collected: [Bool]? = nil) {
        self.level = level
        let aimed = OrbitShot(angle: level.pad.clamp(shot.angle), power: shot.power)
        position = level.pad.at
        velocity = aimed.velocity
        accel = OrbitPhysics.acceleration(at: level.pad.at, bodies: level.bodies, time: 0)
        if let collected, collected.count == level.stars.count {
            self.collected = collected
        } else {
            self.collected = Array(repeating: false, count: level.stars.count)
        }
    }

    var flying: Bool { end == nil }

    /// Energy per unit mass: kinetic plus potential. Constant (very nearly)
    /// when nothing moves but the probe.
    var energy: Double {
        0.5 * velocity.lengthSquared + OrbitPhysics.potential(at: position, bodies: level.bodies, time: time)
    }

    /// One fixed step of physics, then the checks.
    @discardableResult
    mutating func step() -> OrbitStepResult {
        guard end == nil else { return OrbitStepResult(star: nil, end: end) }
        let h = OrbitPhysics.dt
        velocity += accel * (0.5 * h)
        position += velocity * h
        time += h
        steps += 1
        accel = OrbitPhysics.acceleration(at: position, bodies: level.bodies, time: time)
        velocity += accel * (0.5 * h)
        return judge()
    }

    /// Ends the flight early, as the player asked.
    mutating func abort() {
        if end == nil { end = .aborted }
    }

    /// Steps until the flight ends (or `maxSteps`, as a guard). For the tests
    /// and the level checks.
    mutating func run(maxSteps: Int = 200_000) {
        var n = 0
        while end == nil && n < maxSteps {
            step()
            n += 1
        }
    }

    private mutating func judge() -> OrbitStepResult {
        let p = position
        for (i, body) in level.bodies.enumerated() {
            let reach = body.radius + OrbitPhysics.probeRadius
            if p.distanceSquared(to: body.position(at: time)) < reach * reach {
                let ended: OrbitEnd = body.burns ? .burned(i) : (body.swallows ? .swallowed(i) : .crashed(i))
                end = ended
                return OrbitStepResult(star: nil, end: ended)
            }
        }
        for belt in level.belts where belt.contains(p) {
            end = .asteroids
            return OrbitStepResult(star: nil, end: .asteroids)
        }
        var star: Int?
        let reach2 = OrbitPhysics.starReach * OrbitPhysics.starReach
        for (i, s) in level.stars.enumerated() where !collected[i] && p.distanceSquared(to: s) < reach2 {
            collected[i] = true
            star = i
            break
        }
        let target = level.target
        if p.distanceSquared(to: target.position(at: time)) < target.radius * target.radius {
            end = .arrived
        } else if !OrbitField.holds(p) {
            end = .lost
        } else if time >= level.timeLimit {
            end = .flat
        }
        return OrbitStepResult(star: star, end: end)
    }

    /// The first `seconds` of the flight `shot` would make, as points every
    /// `every` steps, for the aiming line. Stops early where the flight would end.
    static func predict(_ level: OrbitLevel, shot: OrbitShot, seconds: Double, every: Int = 4) -> OrbitPrediction {
        var flight = OrbitFlight(level: level, shot: shot)
        let steps = Int((seconds / OrbitPhysics.dt).rounded())
        var points: [OrbitVec] = [flight.position]
        points.reserveCapacity(steps / max(every, 1) + 2)
        var n = 0
        while n < steps && flight.end == nil {
            flight.step()
            n += 1
            if n % max(every, 1) == 0 || flight.end != nil { points.append(flight.position) }
        }
        return OrbitPrediction(points: points, end: flight.end)
    }

    /// The whole flight `shot` would make, for the tests and the demo.
    static func outcome(_ level: OrbitLevel, shot: OrbitShot) -> OrbitFlight {
        var flight = OrbitFlight(level: level, shot: shot)
        flight.run()
        return flight
    }
}

/// The aiming line: where the probe goes first, and how, if that first part
/// already ends the flight, it ends (a crash is marked on the line).
struct OrbitPrediction: Equatable {
    var points: [OrbitVec]
    var end: OrbitEnd?

    static let empty = OrbitPrediction(points: [], end: nil)
}
