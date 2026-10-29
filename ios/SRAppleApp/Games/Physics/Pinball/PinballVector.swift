import Foundation

/// A point or a velocity on the pinball table, in table units (the table is
/// 560 wide and 1000 tall), with y growing DOWN the table as it does on the
/// screen, so gravity is +y and "up the table" is −y.
struct PinballVec: Equatable, Codable {
    var x: Double
    var y: Double

    static let zero = PinballVec(x: 0, y: 0)

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static func + (l: PinballVec, r: PinballVec) -> PinballVec { PinballVec(l.x + r.x, l.y + r.y) }
    static func - (l: PinballVec, r: PinballVec) -> PinballVec { PinballVec(l.x - r.x, l.y - r.y) }
    static func * (l: PinballVec, k: Double) -> PinballVec { PinballVec(l.x * k, l.y * k) }
    static func / (l: PinballVec, k: Double) -> PinballVec { PinballVec(l.x / k, l.y / k) }
    static prefix func - (v: PinballVec) -> PinballVec { PinballVec(-v.x, -v.y) }
    static func += (l: inout PinballVec, r: PinballVec) { l = l + r }
    static func -= (l: inout PinballVec, r: PinballVec) { l = l - r }

    func dot(_ o: PinballVec) -> Double { x * o.x + y * o.y }
    var lengthSquared: Double { x * x + y * y }
    var length: Double { lengthSquared.squareRoot() }

    /// The unit vector this way, or zero for zero.
    var normalized: PinballVec {
        let l = length
        return l > 1e-12 ? PinballVec(x / l, y / l) : .zero
    }

    /// Turned a quarter: for a segment drawn left to right this points UP the table.
    var front: PinballVec { PinballVec(y, -x) }

    /// The same point seen in the mirror line `x = axis` (the right-hand half
    /// of the lower table is the left-hand half, mirrored).
    func mirrored(_ axis: Double) -> PinballVec { PinballVec(2 * axis - x, y) }

    var isFinite: Bool { x.isFinite && y.isFinite }
}

enum PinballGeometry {
    /// The nearest point to `p` on the segment `a`–`b`, and how far along it is (0…1).
    static func closest(_ p: PinballVec, _ a: PinballVec, _ b: PinballVec) -> (point: PinballVec, t: Double) {
        let ab = b - a
        let len2 = ab.lengthSquared
        guard len2 > 1e-12 else { return (a, 0) }
        let t = min(max((p - a).dot(ab) / len2, 0), 1)
        return (a + ab * t, t)
    }

    /// Whether the path `p0`→`p1` crosses the segment `a`–`b`.
    static func crosses(_ p0: PinballVec, _ p1: PinballVec, _ a: PinballVec, _ b: PinballVec) -> Bool {
        func side(_ o: PinballVec, _ u: PinballVec, _ w: PinballVec) -> Double {
            (u.x - o.x) * (w.y - o.y) - (u.y - o.y) * (w.x - o.x)
        }
        let d1 = side(a, b, p0), d2 = side(a, b, p1)
        let d3 = side(p0, p1, a), d4 = side(p0, p1, b)
        return ((d1 > 0 && d2 <= 0) || (d1 < 0 && d2 >= 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }

    /// Even–odd test: is `p` inside the closed polygon?
    static func inside(_ p: PinballVec, _ polygon: [PinballVec]) -> Bool {
        guard polygon.count > 2 else { return false }
        var result = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < x { result.toggle() }
            }
            j = i
        }
        return result
    }

    /// The length of a path through `points`.
    static func length(_ points: [PinballVec]) -> Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<points.count { total += (points[i] - points[i - 1]).length }
        return total
    }

    /// The point `distance` along a path, and the way the path runs there.
    static func along(_ points: [PinballVec], _ distance: Double) -> (point: PinballVec, heading: PinballVec) {
        guard let first = points.first else { return (.zero, PinballVec(0, -1)) }
        guard points.count > 1 else { return (first, PinballVec(0, -1)) }
        var left = max(0, distance)
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let seg = (b - a).length
            if left <= seg || i == points.count - 1 {
                let t = seg > 1e-9 ? min(left / seg, 1) : 1
                return (a + (b - a) * t, (b - a).normalized)
            }
            left -= seg
        }
        let n = points.count
        return (points[n - 1], (points[n - 1] - points[n - 2]).normalized)
    }
}

/// A small seeded generator (SplitMix64), so a test can replay a game exactly.
struct PinballRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< 1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func range(_ low: Double, _ high: Double) -> Double { low + (high - low) * unit() }

    mutating func int(_ count: Int) -> Int { count <= 1 ? 0 : Int(next() % UInt64(count)) }
}
