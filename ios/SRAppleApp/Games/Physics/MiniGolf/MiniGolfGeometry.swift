import Foundation

// Mini Golf's plane geometry: points, boxes and polygons on a hole, in course
// units. A ball is one unit in radius; a hole is roughly thirty units across.
// x runs right and y runs DOWN the screen, so the tee sits at a large y and the
// cup near the top, and an angle of −π/2 points straight up the hole.

/// A point or a direction on a mini golf hole.
struct MiniGolfVec: Equatable, Hashable, Codable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static let zero = MiniGolfVec(0, 0)

    static func + (a: MiniGolfVec, b: MiniGolfVec) -> MiniGolfVec { MiniGolfVec(a.x + b.x, a.y + b.y) }
    static func - (a: MiniGolfVec, b: MiniGolfVec) -> MiniGolfVec { MiniGolfVec(a.x - b.x, a.y - b.y) }
    static func * (a: MiniGolfVec, k: Double) -> MiniGolfVec { MiniGolfVec(a.x * k, a.y * k) }
    static prefix func - (a: MiniGolfVec) -> MiniGolfVec { MiniGolfVec(-a.x, -a.y) }
    static func += (a: inout MiniGolfVec, b: MiniGolfVec) { a = a + b }

    func dot(_ o: MiniGolfVec) -> Double { x * o.x + y * o.y }
    var lengthSquared: Double { x * x + y * y }
    var length: Double { lengthSquared.squareRoot() }

    /// The same direction, one unit long; zero stays zero.
    var unit: MiniGolfVec {
        let l = length
        return l > 1e-12 ? MiniGolfVec(x / l, y / l) : .zero
    }

    /// A quarter turn: the velocity of this point on something spinning at one radian a second.
    var perp: MiniGolfVec { MiniGolfVec(-y, x) }

    func distance(to o: MiniGolfVec) -> Double { (self - o).length }

    func rotated(by angle: Double) -> MiniGolfVec {
        let c = cos(angle), s = sin(angle)
        return MiniGolfVec(x * c - y * s, x * s + y * c)
    }

    /// The unit vector at `angle` radians.
    static func heading(_ angle: Double) -> MiniGolfVec { MiniGolfVec(cos(angle), sin(angle)) }

    /// The angle this direction points at.
    var angle: Double { atan2(y, x) }
}

/// An axis-aligned box, for quick rejection before the exact test.
struct MiniGolfBox: Equatable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    /// The box round `points`; an empty list is an empty box at the origin.
    init(around points: [MiniGolfVec]) {
        guard let first = points.first else {
            self.init(minX: 0, minY: 0, maxX: 0, maxY: 0)
            return
        }
        var box = MiniGolfBox(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        for p in points.dropFirst() {
            box.minX = min(box.minX, p.x)
            box.minY = min(box.minY, p.y)
            box.maxX = max(box.maxX, p.x)
            box.maxY = max(box.maxY, p.y)
        }
        self = box
    }

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var centre: MiniGolfVec { MiniGolfVec((minX + maxX) / 2, (minY + maxY) / 2) }

    func contains(_ p: MiniGolfVec) -> Bool { p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY }

    /// Grown by `d` on every side.
    func outset(_ d: Double) -> MiniGolfBox {
        MiniGolfBox(minX: minX - d, minY: minY - d, maxX: maxX + d, maxY: maxY + d)
    }
}

/// A closed polygon with its box, for regions: sand, water, a bridge, a slope.
struct MiniGolfArea {
    let points: [MiniGolfVec]
    let box: MiniGolfBox

    init(_ points: [MiniGolfVec]) {
        self.points = points
        box = MiniGolfBox(around: points)
    }

    func contains(_ p: MiniGolfVec) -> Bool {
        box.contains(p) && MiniGolfGeo.contains(points, p)
    }
}

/// The shapes holes are drawn from, and the two exact tests the physics needs.
enum MiniGolfGeo {
    /// Whether `p` lies inside the closed polygon `poly` (even–odd rule).
    static func contains(_ poly: [MiniGolfVec], _ p: MiniGolfVec) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let crossX = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
                if p.x < crossX { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// The point on the segment `a`–`b` closest to `p`.
    static func closest(_ a: MiniGolfVec, _ b: MiniGolfVec, to p: MiniGolfVec) -> MiniGolfVec {
        let ab = b - a
        let len2 = ab.lengthSquared
        guard len2 > 1e-12 else { return a }
        let t = min(max((p - a).dot(ab) / len2, 0), 1)
        return a + ab * t
    }

    /// A rectangle, corner first, going round.
    static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> [MiniGolfVec] {
        [MiniGolfVec(x, y), MiniGolfVec(x + w, y), MiniGolfVec(x + w, y + h), MiniGolfVec(x, y + h)]
    }

    /// A rectangle with its four corners cut off at 45°, `cut` units in: a
    /// hole's usual frame, so no ball ever sits in a square corner.
    static func frame(_ x: Double, _ y: Double, _ w: Double, _ h: Double, cut: Double = 3) -> [MiniGolfVec] {
        [
            MiniGolfVec(x + cut, y), MiniGolfVec(x + w - cut, y), MiniGolfVec(x + w, y + cut),
            MiniGolfVec(x + w, y + h - cut), MiniGolfVec(x + w - cut, y + h), MiniGolfVec(x + cut, y + h),
            MiniGolfVec(x, y + h - cut), MiniGolfVec(x, y + cut),
        ]
    }

    /// Points along a circular arc from `from` to `to` radians, both ends included.
    static func arc(_ centre: MiniGolfVec, _ radius: Double, from: Double, to: Double, steps: Int) -> [MiniGolfVec] {
        let n = max(1, steps)
        return (0...n).map { i in
            let a = from + (to - from) * Double(i) / Double(n)
            return centre + MiniGolfVec.heading(a) * radius
        }
    }

    /// A circle as a polygon of `sides` sides.
    static func disc(_ centre: MiniGolfVec, _ radius: Double, sides: Int = 24) -> [MiniGolfVec] {
        let n = max(3, sides)
        return (0..<n).map { i in centre + MiniGolfVec.heading(Double(i) / Double(n) * 2 * .pi) * radius }
    }

    /// The shortest distance from `p` to the closed polygon's edges.
    static func edgeDistance(_ poly: [MiniGolfVec], _ p: MiniGolfVec) -> Double {
        guard poly.count >= 2 else { return .infinity }
        var best = Double.infinity
        for i in 0..<poly.count {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            best = min(best, closest(a, b, to: p).distance(to: p))
        }
        return best
    }
}
