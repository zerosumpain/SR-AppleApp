import Foundation

/// The pen: every hand-drawn stroke in the notes look, as plain geometry.
///
/// A port of SR-Main's `notes-ink.ts` and `showcase-notes.ts`, line for line.
/// Nothing wobbles at runtime: every stroke's wobble comes from a seeded
/// generator, so the same seed draws the same mark on the phone as it does on
/// the website — a ring round a figure is the SAME ring in both places, not a
/// similar one. That only holds if the generator is bit-identical, which is why
/// `InkRNG` is mulberry32 written out in wrapping `UInt32` arithmetic rather
/// than "a seeded random", and why `NotesPenTests` pins its first outputs to
/// the values the site's own `rng(31)` produces.
///
/// This file is Foundation only, on purpose. It holds no SwiftUI, so it can be
/// compiled and RUN on Linux against the site's numbers, which is the only way
/// to prove the port without a Mac. `SRNotes.swift` turns these strokes into
/// `Path`s and the marks the screens use.
///
/// Coordinates are in the mark's own units (its SVG viewBox on the site), y
/// down. The site rounds every coordinate to 0.1px when it writes the path
/// string; the strokes here keep full precision, which changes nothing anyone
/// can see.

/// mulberry32, bit-identical to `rng()` in `notes-ink.ts`, so seeds match the
/// site.
struct InkRNG {
    private var a: UInt32

    init(_ seed: Int) { a = UInt32(truncatingIfNeeded: seed) }

    /// The next value in [0, 1).
    mutating func next() -> Double {
        a = a &+ 0x6D2B_79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296.0
    }

    /// A nudge of up to `amp` either way: `jit()` on the site. The ORDER of
    /// these calls is part of the drawing — swap two and every mark after
    /// them changes shape.
    mutating func jit(_ amp: Double) -> Double { (next() * 2 - 1) * amp }
}

/// One stroke of the pen: where the nib went down, then each piece after it.
struct InkStroke: Equatable {
    enum Piece: Equatable {
        case line(CGPoint)
        /// A cubic Bézier: two control points, then the end.
        case curve(CGPoint, CGPoint, CGPoint)
    }

    var start: CGPoint
    var pieces: [Piece] = []
}

/// The site's pen recipes. Every function draws from the generator it is
/// handed in exactly the site's order.
enum InkGeometry {
    private static func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    /// Catmull-Rom through the points as cubic Béziers (`smooth()`); fewer
    /// than three points are joined with straight lines (`poly()`).
    static func smooth(_ p: [CGPoint]) -> InkStroke {
        guard let first = p.first else { return InkStroke(start: .zero) }
        var stroke = InkStroke(start: first)
        guard p.count >= 3 else {
            stroke.pieces = p.dropFirst().map { .line($0) }
            return stroke
        }
        for i in 0..<(p.count - 1) {
            let a = i > 0 ? p[i - 1] : p[i]
            let b = p[i]
            let c = p[i + 1]
            let e = i + 2 < p.count ? p[i + 2] : c
            stroke.pieces.append(.curve(
                pt(Double(b.x + (c.x - a.x) / 6), Double(b.y + (c.y - a.y) / 6)),
                pt(Double(c.x - (e.x - b.x) / 6), Double(c.y - (e.y - b.y) / 6)),
                c
            ))
        }
        return stroke
    }

    /// A straight stroke drawn by hand: both ends nudged, a slight bow in the
    /// middle (`inkLine`).
    static func line(_ r: inout InkRNG, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                     amp: Double = 0.6, bow: Double = 0.015) -> InkStroke {
        let dx = x2 - x1, dy = y2 - y1
        let h = hypot(dx, dy)
        let len = h == 0 ? 1 : h
        let b = r.jit(len * bow)
        let p0x = x1 + r.jit(amp)
        let p0y = y1 + r.jit(amp)
        let mid = pt(x1 + dx / 2 - (dy / len) * b, y1 + dy / 2 + (dx / len) * b)
        let p2x = x2 + r.jit(amp)
        let p2y = y2 + r.jit(amp)
        return smooth([pt(p0x, p0y), mid, pt(p2x, p2y)])
    }

    /// A loop a little more than one turn, overshooting where it comes back
    /// (`inkRing`).
    static func ring(_ r: inout InkRNG, cx: Double, cy: Double, rx: Double, ry: Double,
                     turns: Double = 1.1, wob: Double = 0.045) -> InkStroke {
        let a0 = -2.2 + r.jit(0.35)
        var pts: [CGPoint] = []
        for i in 0...16 {
            let t = Double(i) / 16
            let a = a0 + t * Double.pi * 2 * turns
            // The second pass drifts outwards, as a hand's does.
            let k = 1 + r.jit(wob) + (t > 0.9 ? 0.04 : 0)
            pts.append(pt(cx + cos(a) * rx * k, cy + sin(a) * ry * k))
        }
        return smooth(pts)
    }

    /// A box drawn by hand: four strokes, the corners a touch over or under
    /// (`inkBox`).
    static func box(_ r: inout InkRNG, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                    amp: Double = 0.6) -> [InkStroke] {
        [
            line(&r, x, y, x + w, y, amp: amp, bow: 0.004),
            line(&r, x + w, y, x + w, y + h, amp: amp, bow: 0.008),
            line(&r, x + w, y + h, x, y + h, amp: amp, bow: 0.004),
            line(&r, x, y + h, x, y, amp: amp, bow: 0.008),
        ]
    }

    /// The date stamp's box, in its 100 × 40 viewBox: four strokes, each from
    /// its own generator (`seed` … `seed + 3`), as `DateStamp.svelte` draws it.
    static func stampBox(seed: Int) -> [InkStroke] {
        var a = InkRNG(seed), b = InkRNG(seed + 1), c = InkRNG(seed + 2), d = InkRNG(seed + 3)
        return [
            line(&a, 2, 2, 98, 2.5, amp: 0.3, bow: 0.004),
            line(&b, 98, 2, 97.5, 38, amp: 0.3, bow: 0.01),
            line(&c, 98, 38, 2, 37.5, amp: 0.3, bow: 0.004),
            line(&d, 2, 38, 2.5, 2, amp: 0.3, bow: 0.01),
        ]
    }

    /// The double underline a total gets, in its 100 × 12 viewBox: the second
    /// stroke shorter and inset.
    static func underline(seed: Int) -> [InkStroke] {
        var a = InkRNG(seed), b = InkRNG(seed + 1)
        return [
            line(&a, 1, 3, 99, 4.6, amp: 0.4, bow: 0.012),
            line(&b, 6, 9, 95, 10, amp: 0.4, bow: 0.012),
        ]
    }

    /// A tick: short down-stroke, long up-stroke (`inkTick`).
    static func tick(_ r: inout InkRNG, _ x: Double, _ y: Double, s: Double = 14) -> InkStroke {
        let ax = x + r.jit(0.4)
        let ay = y + s * 0.5 + r.jit(0.4)
        let cx = x + s * 1.05 + r.jit(0.6)
        let cy = y - s * 0.15 + r.jit(0.6)
        return smooth([pt(ax, ay), pt(x + s * 0.36, y + s * 0.9), pt(cx, cy)])
    }

    /// A hand-drawn arrow, bowed, with a two-stroke head (`inkArrow`).
    static func arrow(_ r: inout InkRNG, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                      bow: Double = 0.18) -> (shaft: InkStroke, head: [InkStroke]) {
        let dx = x2 - x1, dy = y2 - y1
        let h = hypot(dx, dy)
        let len = h == 0 ? 1 : h
        let b = len * bow
        let mid = pt(x1 + dx / 2 - (dy / len) * b, y1 + dy / 2 + (dx / len) * b)
        let ex = x2 + r.jit(0.4)
        let ey = y2 + r.jit(0.4)
        let shaft = smooth([pt(x1, y1), mid, pt(ex, ey)])
        let a = atan2(y2 - Double(mid.y), x2 - Double(mid.x))
        let s = min(9, len * 0.3)
        func wing(_ t: Double) -> InkStroke {
            InkStroke(start: pt(x2 + cos(a + Double.pi - t) * s, y2 + sin(a + Double.pi - t) * s),
                      pieces: [.line(pt(x2, y2))])
        }
        let w1 = wing(0.45 + r.jit(0.05))
        let w2 = wing(-0.45 + r.jit(0.05))
        return (shaft, [w1, w2])
    }

    /// The tally's gate pitch: four uprights 3 apart and the slash, then the
    /// next gate 15 along.
    static let gatePitch = 15.0

    /// Five-bar gates in a `w` × `h` box; when they do not all fit, the last
    /// gate's room is left for a "+n" (`inkTally`). `more` is how many strokes
    /// were not drawn and `moreX` where the "+n" goes.
    static func tally(count: Int, w: Double, h: Double, seed: Int) -> (strokes: [InkStroke], more: Int, moreX: Double) {
        var r = InkRNG(seed)
        let n = max(0, count)
        let groups = (n + 4) / 5
        let fit = max(1, Int(((w + 4) / gatePitch).rounded(.down)))
        let shown = groups <= fit ? n : (fit - 1) * 5
        let y0 = h - 1, y1 = 1.5
        var strokes: [InkStroke] = []
        var g = 0
        while g * 5 < shown {
            let gx = Double(g) * gatePitch + 2
            let k = min(5, shown - g * 5)
            for s in 0..<min(4, k) {
                let x = gx + Double(s) * 3
                let ax = x + r.jit(0.3)
                let ay = y0 + r.jit(0.4)
                let bx = x + r.jit(0.5)
                let by = y1 + r.jit(0.5)
                strokes.append(InkStroke(start: pt(ax, ay), pieces: [.line(pt(bx, by))]))
            }
            if k == 5 {
                let ay = y0 - 2 + r.jit(0.5)
                let by = y1 + 2 + r.jit(0.5)
                strokes.append(InkStroke(start: pt(gx - 1.5, ay), pieces: [.line(pt(gx + 10.5, by))]))
            }
            g += 1
        }
        return (strokes, n - shown, Double(fit - 1) * gatePitch)
    }

    /// The width a tally of `count` needs so that nothing folds into "+n":
    /// one pitch a gate, as the site sizes its SVG.
    static func tallyWidth(count: Int) -> Double { Double((max(0, count) + 4) / 5) * gatePitch }

    /// Struck-out claims: a cursive scribble per claim, each crossed through
    /// by a zigzag (`scribbles`). Rows 18 apart from y = 9; up to 166 wide.
    static func scribbles(_ n: Int, max: Int = 5, seed: Int = 61) -> (lines: [InkStroke], strikes: [InkStroke]) {
        guard n > 0 else { return ([], []) }
        var lines: [InkStroke] = []
        var strikes: [InkStroke] = []
        for i in 0..<Swift.min(n, max) {
            var r = InkRNG(seed + i * 7)
            let y = 9 + Double(i) * 18
            let w = 96 + r.next() * 70
            var pts: [CGPoint] = []
            var x = 4.0
            while x <= w {
                let up = pts.count % 2 == 1 ? 2.5 : -2.5
                let tall = r.next() > 0.85 ? 2.0 : 1.0
                pts.append(pt(x, y + up * tall + r.jit(0.8)))
                x += 5
            }
            lines.append(smooth(pts))
            var z: [CGPoint] = []
            x = 2
            while x <= w + 4 {
                let zx = x + r.jit(1)
                let zy = y + (z.count % 2 == 1 ? 3.5 : -3.5) + r.jit(0.8)
                z.append(pt(zx, zy))
                x += 7
            }
            strikes.append(smooth(z))
        }
        return (lines, strikes)
    }

    /// Points along a circle from `a0` to `a1`, the inner ones nudged.
    private static func arc(_ r: inout InkRNG, _ cx: Double, _ cy: Double, _ rad: Double,
                            _ a0: Double, _ a1: Double, _ n: Int, _ amp: Double) -> [CGPoint] {
        (0...n).map { i in
            let a = a0 + ((a1 - a0) * Double(i)) / Double(n)
            let inner = i > 0 && i < n
            let x = cx + cos(a) * rad + (inner ? r.jit(amp) : 0)
            let y = cy + sin(a) * rad + (inner ? r.jit(amp) : 0)
            return pt(x, y)
        }
    }

    /// The crescent moon doodle and three cross stars, in an 80 × 64 viewBox
    /// (`moon`): the disc with a second disc bitten out of it, one pass.
    static func moon(seed: Int = 171) -> (body: InkStroke, stars: [InkStroke]) {
        var r = InkRNG(seed)
        let (x1, y1, R) = (32.0, 34.0, 24.0)
        let (x2, y2, rr) = (44.0, 26.0, 21.0)
        let dx = x2 - x1, dy = y2 - y1
        let d = hypot(dx, dy)
        let a = (R * R - rr * rr + d * d) / (2 * d)
        let h = (Swift.max(0, R * R - a * a)).squareRoot()
        let px = x1 + (a * dx) / d, py = y1 + (a * dy) / d
        let A = (px + (h * dy) / d, py - (h * dx) / d)
        let B = (px - (h * dy) / d, py + (h * dx) / d)
        func ang(_ cx: Double, _ cy: Double, _ p: (Double, Double)) -> Double { atan2(p.1 - cy, p.0 - cx) }
        func norm(_ t: Double) -> Double {
            let m = 2 * Double.pi
            return (t.truncatingRemainder(dividingBy: m) + m).truncatingRemainder(dividingBy: m)
        }
        func ccwHas(_ from: Double, _ to: Double, _ t: Double) -> Bool { norm(t - from) < norm(to - from) }
        let oa = ang(x1, y1, A)
        var ob = ang(x1, y1, B)
        let toBite = atan2(dy, dx)
        ob = ccwHas(oa, ob, toBite) ? oa - norm(oa - ob) : oa + norm(ob - oa)
        let ia = ang(x2, y2, B)
        var ib = ang(x2, y2, A)
        let toMoon = toBite + Double.pi
        ib = ccwHas(ia, ib, toMoon) ? ia + norm(ib - ia) : ia - norm(ia - ib)
        var pts = arc(&r, x1, y1, R, oa, ob, 14, 0.5)
        pts += arc(&r, x2, y2, rr, ia, ib, 8, 0.4).dropFirst()
        pts.append(pt(A.0 + 1.5, A.1 + 1.2))
        func star(_ x: Double, _ y: Double, _ s: Double) -> [InkStroke] {
            let ay = y + r.jit(0.3)
            let by = y + r.jit(0.3)
            let cx = x + r.jit(0.3)
            let dx = x + r.jit(0.3)
            return [InkStroke(start: pt(x - s, ay), pieces: [.line(pt(x + s, by))]),
                    InkStroke(start: pt(cx, y - s), pieces: [.line(pt(dx, y + s))])]
        }
        let body = smooth(pts)
        let stars = star(66, 12, 3.5) + star(74, 34, 2.5) + star(62, 52, 2)
        return (body, stars)
    }
}

/// `pencilFor` in `paper.ts` (FNV-1a): a stable pencil for a word, so a tag
/// keeps its colour everywhere. 0 orange, 1 petrol, 2 olive, 3 ochre.
func pencilIndex(_ word: String) -> Int {
    var h: UInt32 = 2_166_136_261
    for u in word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().unicodeScalars {
        h ^= u.value
        h = h &* 16_777_619
    }
    return Int(h % 4)
}

/// `seedFor` in `paper.ts`: a seed for the pen's wobble from a word, case
/// aside, so each word's mark is drawn once and drawn the same.
func seedFor(_ word: String) -> Int {
    var h: Int32 = 7
    for u in word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().unicodeScalars {
        h = h &* 31 &+ Int32(bitPattern: u.value)
    }
    let v = abs(Int(h))
    return v == 0 ? 1 : v
}
