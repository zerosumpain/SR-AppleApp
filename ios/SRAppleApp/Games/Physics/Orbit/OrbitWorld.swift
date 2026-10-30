import Foundation

// Orbit's levels as plain values: the bodies that pull, the hazards that end
// a flight, the pad it starts from and the target it is aiming for. The world
// is a fixed 600 by 900 field (portrait, y down) that the screen scales to
// fit; nothing here knows about points or colours beyond a body's look.

/// The size of every level's field, in world units.
enum OrbitField {
    static let width = 600.0
    static let height = 900.0
    /// How far past the edge a probe may swing before it is lost.
    static let margin = 220.0

    static var centre: OrbitVec { OrbitVec(width / 2, height / 2) }

    /// Still inside the space a probe can come back from.
    static func holds(_ p: OrbitVec) -> Bool {
        p.x > -margin && p.x < width + margin && p.y > -margin && p.y < height + margin
    }

    /// On the visible field itself.
    static func shows(_ p: OrbitVec) -> Bool {
        p.x >= 0 && p.x <= width && p.y >= 0 && p.y <= height
    }
}

/// A circle a moon (or a moving target) follows exactly, whatever the probe
/// does: nothing pulls a body off its rail, so every launch sees the same sky.
struct OrbitRail: Equatable {
    var centre: OrbitVec
    var radius: Double
    /// Seconds for one lap; negative runs anticlockwise on screen.
    var period: Double
    /// Where on the circle it is at the moment of launch, radians from +x.
    var phase: Double

    func angle(at t: Double) -> Double {
        phase + 2 * Double.pi * t / period
    }

    func position(at t: Double) -> OrbitVec {
        let a = angle(at: t)
        return OrbitVec(centre.x + radius * cos(a), centre.y + radius * sin(a))
    }
}

/// How a body is drawn, and for the sun and the black hole how it ends a flight.
enum OrbitLook: String, CaseIterable {
    case rocky, ocean, desert, ice, lava, jungle
    case amber, teal, violet, rose
    case moon
    case sun
    case blackHole

    /// A gas giant's banded face.
    var isGiant: Bool {
        switch self {
        case .amber, .teal, .violet, .rose: return true
        default: return false
        }
    }
}

/// A planet, moon, sun or black hole: a mass that pulls and a surface the
/// probe must not touch.
struct OrbitBody: Equatable {
    var name: String
    var look: OrbitLook
    /// Where it sits; ignored when it rides a rail.
    var at: OrbitVec
    var radius: Double
    /// Pull strength (the gravitational constant is folded in): units³/s².
    var mass: Double
    var rail: OrbitRail? = nil
    /// Drawn with a ring round it. Only for the look; rings do not collide.
    var ringed = false

    func position(at t: Double) -> OrbitVec {
        rail?.position(at: t) ?? at
    }

    /// Touching the surface ends the flight; for a black hole the surface is
    /// the event horizon.
    var burns: Bool { look == .sun }
    var swallows: Bool { look == .blackHole }
}

/// A band of rocks: part of a ring round a point. Flying into the band ends
/// the flight; the rocks themselves are drawn for show.
struct OrbitBelt: Equatable {
    var centre: OrbitVec
    var inner: Double
    var outer: Double
    /// Where the band starts, radians from +x, running clockwise on screen.
    var start: Double
    /// How much of the ring it covers, radians (2π for a full ring).
    var span: Double

    func contains(_ p: OrbitVec) -> Bool {
        let d2 = p.distanceSquared(to: centre)
        guard d2 >= inner * inner, d2 <= outer * outer else { return false }
        if span >= 2 * Double.pi { return true }
        var a = atan2(p.y - centre.y, p.x - centre.x) - start
        a = a.truncatingRemainder(dividingBy: 2 * Double.pi)
        if a < 0 { a += 2 * Double.pi }
        return a <= span
    }
}

/// Where the probe is going: a space station to dock with or a wormhole.
struct OrbitTarget: Equatable {
    enum Kind: String { case station, wormhole }

    var kind: Kind
    var at: OrbitVec
    /// Reaching within this distance of the middle counts as arriving.
    var radius: Double
    var rail: OrbitRail? = nil

    func position(at t: Double) -> OrbitVec {
        rail?.position(at: t) ?? at
    }
}

/// The launch pad: a point the probe leaves from and the directions it may
/// leave in. On a planet the probe can only go up and away from the ground;
/// from a station in open space it can go any way.
struct OrbitPad: Equatable {
    var at: OrbitVec
    /// The middle of the directions allowed, radians.
    var facing: Double
    /// How far either side of `facing` a launch may point, radians; π is any way.
    var arc: Double
    /// The body the pad stands on, for the drawing.
    var body: Int?

    /// A pad on the surface of `bodies[index]`, `angle` radians round from +x.
    static func on(_ bodies: [OrbitBody], _ index: Int, angle: Double) -> OrbitPad {
        let b = bodies[index]
        let out = OrbitVec.heading(angle)
        return OrbitPad(at: b.at + out * (b.radius + OrbitPhysics.padLift), facing: angle,
                        arc: 80 * Double.pi / 180, body: index)
    }

    /// A free-floating launch station.
    static func station(_ at: OrbitVec, facing: Double = -Double.pi / 2) -> OrbitPad {
        OrbitPad(at: at, facing: facing, arc: Double.pi, body: nil)
    }

    /// `angle`, turned back inside the allowed directions.
    func clamp(_ angle: Double) -> Double {
        guard arc < Double.pi else { return OrbitAngle.wrap(angle) }
        let d = OrbitAngle.delta(angle, from: facing)
        return OrbitAngle.wrap(facing + min(max(d, -arc), arc))
    }
}

/// The three systems the thirty levels sit in, ten each.
enum OrbitSystem: Int, CaseIterable, Identifiable {
    case inner, giants, deep

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .inner: return "Inner System"
        case .giants: return "Gas Giants"
        case .deep: return "Deep Space"
        }
    }

    var line: String {
        switch self {
        case .inner: return "Rocky worlds, a hot sun and your first slingshots."
        case .giants: return "Huge planets, rings and moons that will not wait for you."
        case .deep: return "Black holes, rock belts and wormholes, with less help aiming."
        }
    }

    /// The levels it holds, 1-based.
    var levels: ClosedRange<Int> { (rawValue * 10 + 1)...(rawValue * 10 + 10) }

    static func of(level: Int) -> OrbitSystem {
        OrbitSystem(rawValue: min(max((level - 1) / 10, 0), 2)) ?? .inner
    }
}

/// A launch: which way and how hard.
struct OrbitShot: Equatable, Codable {
    /// Radians from +x, clockwise on screen.
    var angle: Double
    /// 0 to 1, from the slowest launch to the fastest.
    var power: Double

    var speed: Double {
        OrbitPhysics.minSpeed + min(max(power, 0), 1) * (OrbitPhysics.maxSpeed - OrbitPhysics.minSpeed)
    }

    var velocity: OrbitVec { OrbitVec.heading(angle) * speed }

    /// Percent, for the read-out.
    var percent: Int { Int((min(max(power, 0), 1) * 100).rounded()) }
}

/// One level: everything a flight needs, and the numbers its stars are judged on.
struct OrbitLevel: Identifiable, Equatable {
    /// 1 to 30.
    let number: Int
    var name: String
    /// One line on the level card: what this level teaches or asks.
    var hint: String
    var pad: OrbitPad
    var bodies: [OrbitBody]
    var belts: [OrbitBelt] = []
    var target: OrbitTarget
    /// Stars to pick up on the way; each is caught within `OrbitPhysics.starReach`.
    var stars: [OrbitVec]
    /// Launches for the third star.
    var par: Int
    /// Seconds of flight the aiming line shows.
    var preview: Double
    /// Seconds of flight before the probe's battery runs out.
    var timeLimit: Double
    /// A launch that arrives with every star: the demo flies it, and the tests
    /// prove the level can be done with it.
    var demo: OrbitShot

    var id: Int { number }
    var system: OrbitSystem { OrbitSystem.of(level: number) }
}
