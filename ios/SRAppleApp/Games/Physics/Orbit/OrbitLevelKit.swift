import Foundation

/// Short ways to write a level's bodies, so the thirty levels read as a list
/// of places rather than a wall of initialisers.
enum OrbitKit {
    static func deg(_ d: Double) -> Double { d * Double.pi / 180 }

    static func planet(_ name: String, _ look: OrbitLook, _ x: Double, _ y: Double,
                       radius: Double, mass: Double, ringed: Bool = false) -> OrbitBody {
        OrbitBody(name: name, look: look, at: OrbitVec(x, y), radius: radius, mass: mass, rail: nil, ringed: ringed)
    }

    /// A moon on a rail round (`cx`, `cy`): `distance` out, a lap every
    /// `period` seconds (negative for anticlockwise), starting `phase` degrees round.
    static func moon(_ name: String, around cx: Double, _ cy: Double, distance: Double, period: Double,
                     phase: Double, radius: Double, mass: Double, look: OrbitLook = .moon) -> OrbitBody {
        let rail = OrbitRail(centre: OrbitVec(cx, cy), radius: distance, period: period, phase: deg(phase))
        return OrbitBody(name: name, look: look, at: rail.position(at: 0), radius: radius, mass: mass, rail: rail, ringed: false)
    }

    static func sun(_ x: Double, _ y: Double, radius: Double, mass: Double, name: String = "the sun") -> OrbitBody {
        OrbitBody(name: name, look: .sun, at: OrbitVec(x, y), radius: radius, mass: mass, rail: nil, ringed: false)
    }

    static func hole(_ x: Double, _ y: Double, horizon: Double, mass: Double) -> OrbitBody {
        OrbitBody(name: "the black hole", look: .blackHole, at: OrbitVec(x, y), radius: horizon, mass: mass, rail: nil, ringed: false)
    }

    /// Part of a ring of rocks round (`cx`, `cy`), from `from` degrees for `span` degrees, clockwise.
    static func belt(_ cx: Double, _ cy: Double, inner: Double, outer: Double, from: Double, span: Double) -> OrbitBelt {
        OrbitBelt(centre: OrbitVec(cx, cy), inner: inner, outer: outer, start: deg(from), span: deg(span))
    }

    static func station(_ x: Double, _ y: Double, radius: Double = 24) -> OrbitTarget {
        OrbitTarget(kind: .station, at: OrbitVec(x, y), radius: radius, rail: nil)
    }

    static func wormhole(_ x: Double, _ y: Double, radius: Double = 26) -> OrbitTarget {
        OrbitTarget(kind: .wormhole, at: OrbitVec(x, y), radius: radius, rail: nil)
    }

    /// A station riding a rail round (`cx`, `cy`).
    static func orbitingStation(around cx: Double, _ cy: Double, distance: Double, period: Double,
                                phase: Double, radius: Double = 24) -> OrbitTarget {
        let rail = OrbitRail(centre: OrbitVec(cx, cy), radius: distance, period: period, phase: deg(phase))
        return OrbitTarget(kind: .station, at: rail.position(at: 0), radius: radius, rail: rail)
    }

    static func pad(on bodies: [OrbitBody], _ index: Int, at angle: Double) -> OrbitPad {
        OrbitPad.on(bodies, index, angle: deg(angle))
    }

    static func launcher(_ x: Double, _ y: Double) -> OrbitPad {
        OrbitPad.station(OrbitVec(x, y))
    }

    static func shot(_ degrees: Double, _ power: Double) -> OrbitShot {
        OrbitShot(angle: deg(degrees), power: power)
    }
}
