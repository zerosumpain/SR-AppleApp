import Foundation

/// A point or a velocity in Orbit's world: units across and down, the way the
/// screen counts (y grows downwards). Plain doubles so the rules, the drawing
/// and the tests all share one small type.
struct OrbitVec: Equatable, Hashable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static let zero = OrbitVec(0, 0)

    /// The unit vector pointing `angle` radians round from +x (clockwise on screen).
    static func heading(_ angle: Double) -> OrbitVec {
        OrbitVec(cos(angle), sin(angle))
    }

    var lengthSquared: Double { x * x + y * y }
    var length: Double { lengthSquared.squareRoot() }
    /// The way it points, radians from +x.
    var angle: Double { atan2(y, x) }

    var normalised: OrbitVec {
        let l = length
        return l > 0 ? OrbitVec(x / l, y / l) : .zero
    }

    func dot(_ other: OrbitVec) -> Double { x * other.x + y * other.y }

    func distance(to other: OrbitVec) -> Double { (self - other).length }

    func distanceSquared(to other: OrbitVec) -> Double {
        let dx = x - other.x, dy = y - other.y
        return dx * dx + dy * dy
    }

    static func + (a: OrbitVec, b: OrbitVec) -> OrbitVec { OrbitVec(a.x + b.x, a.y + b.y) }
    static func - (a: OrbitVec, b: OrbitVec) -> OrbitVec { OrbitVec(a.x - b.x, a.y - b.y) }
    static func * (a: OrbitVec, k: Double) -> OrbitVec { OrbitVec(a.x * k, a.y * k) }
    static func * (k: Double, a: OrbitVec) -> OrbitVec { OrbitVec(a.x * k, a.y * k) }
    static func / (a: OrbitVec, k: Double) -> OrbitVec { OrbitVec(a.x / k, a.y / k) }
    static prefix func - (a: OrbitVec) -> OrbitVec { OrbitVec(-a.x, -a.y) }
    static func += (a: inout OrbitVec, b: OrbitVec) { a = a + b }
    static func -= (a: inout OrbitVec, b: OrbitVec) { a = a - b }
}

/// Angles, wrapped and compared the short way round.
enum OrbitAngle {
    /// `a` folded into −π…π.
    static func wrap(_ a: Double) -> Double {
        var v = a.truncatingRemainder(dividingBy: 2 * Double.pi)
        if v > Double.pi { v -= 2 * Double.pi }
        if v < -Double.pi { v += 2 * Double.pi }
        return v
    }

    /// How far `a` is from `b`, the short way, signed.
    static func delta(_ a: Double, from b: Double) -> Double { wrap(a - b) }

    /// Degrees on a compass the player reads: 0 is straight up the screen,
    /// 90 is to the right, counted clockwise.
    static func bearing(_ a: Double) -> Int {
        var d = (a + Double.pi / 2) * 180 / Double.pi
        d = d.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        let r = Int(d.rounded())
        return r == 360 ? 0 : r
    }
}

/// A small, fast, seeded random source, so the starfield and the asteroid
/// rocks land in the same places on every phone and every frame.
struct OrbitRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }

    /// 0 ..< 1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }

    mutating func range(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * unit()
    }
}
