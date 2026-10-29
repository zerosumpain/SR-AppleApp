import Foundation

/// A point on the board in cells (not pixels): the middle of cell (2, 3) is
/// (2.5, 3.5). Its own type so the drawing maths stays Foundation-only.
struct SnakeVec: Equatable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    func lerp(to other: SnakeVec, _ t: Double) -> SnakeVec {
        SnakeVec(x + (other.x - x) * t, y + (other.y - y) * t)
    }

    func distance(to other: SnakeVec) -> Double {
        let dx = other.x - x, dy = other.y - y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// The line the snake's body is drawn along, between steps.
///
/// The cells only change once a step, but the body is drawn every frame: the
/// head slides from the cell behind it into its new cell, and the tail slides
/// out of the cell it is leaving, so the snake glides rather than hops. At
/// `fraction` 0 the drawing is exactly the last step's at 1, so nothing jumps.
enum SnakePath {
    /// Cell centres from the head to the tail tip, unwrapped: across a
    /// wrapping edge the line carries on past the board (x = -0.5, 15.5)
    /// rather than leaping across it, so neighbours are never more than one
    /// cell apart. The drawing repeats it one board over to show both halves.
    static func centres(body: [SnakePoint], vacated: SnakePoint?, fraction: Double,
                        columns: Int, rows: Int) -> [SnakeVec] {
        guard let first = body.first else { return [] }
        let t = min(1, max(0, fraction))
        var unwrapped: [SnakeVec] = []
        unwrapped.reserveCapacity(body.count + 1)
        var at = SnakeVec(Double(first.x) + 0.5, Double(first.y) + 0.5)
        unwrapped.append(at)
        var previous = first
        for cell in body.dropFirst() {
            at = step(from: at, previous, to: cell, columns: columns, rows: rows)
            unwrapped.append(at)
            previous = cell
        }
        var out: [SnakeVec] = []
        out.reserveCapacity(unwrapped.count + 1)
        if unwrapped.count >= 2 {
            out.append(unwrapped[1].lerp(to: unwrapped[0], t))
            out.append(contentsOf: unwrapped.dropFirst())
        } else {
            out.append(unwrapped[0])
        }
        if let vacated, let last = body.last, t < 1 {
            let tip = step(from: at, last, to: vacated, columns: columns, rows: rows)
            out.append(tip.lerp(to: at, t))
        }
        return out
    }

    /// Where `to` is, one cell from `from` (at `point`), without wrapping.
    private static func step(from point: SnakeVec, _ from: SnakePoint, to: SnakePoint,
                             columns: Int, rows: Int) -> SnakeVec {
        var dx = to.x - from.x
        var dy = to.y - from.y
        if dx > 1 { dx -= columns }
        if dx < -1 { dx += columns }
        if dy > 1 { dy -= rows }
        if dy < -1 { dy += rows }
        return SnakeVec(point.x + Double(dx), point.y + Double(dy))
    }

    /// The board-sized shifts the line must also be drawn at so the part past
    /// an edge shows on the other side: always (0, 0) first, plus every whole
    /// board's shift that brings some of the line back over the board. A long
    /// snake that has gone off the same edge twice (a staircase across a
    /// wrapping board) unwraps more than one board away, so it needs two.
    static func copies(of points: [SnakeVec], columns: Int, rows: Int, margin: Double = 0.6) -> [SnakeVec] {
        guard !points.isEmpty, columns > 0, rows > 0 else { return [] }
        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        guard minX.isFinite, maxX.isFinite, minY.isFinite, maxY.isFinite else { return [SnakeVec(0, 0)] }
        let xs = shifts(low: minX, high: maxX, span: Double(columns), margin: margin)
        let ys = shifts(low: minY, high: maxY, span: Double(rows), margin: margin)
        var out: [SnakeVec] = []
        out.reserveCapacity(xs.count * ys.count)
        for x in xs {
            for y in ys { out.append(SnakeVec(x, y)) }
        }
        return out
    }

    /// 0 first, then each multiple of `span` that moves `low...high` so it
    /// overlaps the board (0...span, widened by `margin`).
    private static func shifts(low: Double, high: Double, span: Double, margin: Double) -> [Double] {
        var out: [Double] = [0]
        // A snake is at most a board's worth of cells long, so a few boards is plenty.
        let reach = min(8, Int(((high - low) / span).rounded(.up)) + 1)
        guard reach >= 1 else { return out }
        for k in 1...reach {
            for shift in [Double(k) * span, -Double(k) * span] {
                if low + shift < span + margin && high + shift > -margin { out.append(shift) }
            }
        }
        return out
    }

    /// Splits the line `tail` cells from its end: the body to stroke at full
    /// width, and the tail as evenly spaced points (tip last) to draw as
    /// shrinking circles.
    static func split(_ points: [SnakeVec], tail: Double, spacing: Double) -> (body: [SnakeVec], tail: [SnakeVec]) {
        guard points.count >= 2, tail > 0, spacing > 0 else { return (points, []) }
        var remaining = tail
        var index = points.count - 1
        // Walk back from the tip until `tail` cells of line are behind us.
        while index > 0 {
            let length = points[index].distance(to: points[index - 1])
            if length >= remaining { break }
            remaining -= length
            index -= 1
        }
        guard index > 0 else { return (points, []) }
        let a = points[index - 1], b = points[index]
        let length = a.distance(to: b)
        let cut = length > 0 ? b.lerp(to: a, remaining / length) : b
        var body = Array(points[0..<index])
        body.append(cut)
        // Sample the tail from the cut to the tip.
        var tailLine: [SnakeVec] = [cut]
        tailLine.append(contentsOf: points[index...])
        var samples: [SnakeVec] = []
        var carry = 0.0
        for i in 1..<tailLine.count {
            let p = tailLine[i - 1], q = tailLine[i]
            let d = p.distance(to: q)
            guard d > 0 else { continue }
            var s = carry
            while s <= d {
                samples.append(p.lerp(to: q, s / d))
                s += spacing
            }
            carry = s - d
        }
        if let tip = tailLine.last, samples.last != tip { samples.append(tip) }
        return (body, samples)
    }

    /// Total length of a line, in cells.
    static func length(_ points: [SnakeVec]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<points.count { total += points[i].distance(to: points[i - 1]) }
        return total
    }

    /// The head's angle between two headings, eased through a turn: the
    /// shortest way round, so left-to-up turns a quarter, not three.
    static func angle(from: SnakeDirection, to: SnakeDirection, fraction: Double) -> Double {
        let t = min(1, max(0, fraction))
        let eased = 1 - (1 - t) * (1 - t)
        var delta = to.angle - from.angle
        while delta > Double.pi { delta -= 2 * Double.pi }
        while delta < -Double.pi { delta += 2 * Double.pi }
        return from.angle + delta * eased
    }
}
