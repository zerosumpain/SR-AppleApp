import SwiftUI

/// One spark of a merge: born at a point on the board and flung outward,
/// falling a little as it fades. Board space is 0…1 across and down, so the
/// session can make sparks without knowing how big the board is drawn: a
/// cell's centre is `(col + 0.5) / side`, and the layer maps that onto the
/// drawn board inside half a gap of its edge, which lands it on the tile.
struct Merge2048Spark {
    let x: Double
    let y: Double
    /// Board widths a second.
    let vx: Double
    let vy: Double
    /// `timeIntervalSinceReferenceDate`.
    let born: Double
    let life: Double
    /// Board widths.
    let radius: Double
    let colour: Color
    /// A ring that spreads from the cell rather than a dot that flies.
    let ring: Bool
}

enum Merge2048SparkMaker {
    /// Downward pull, board widths a second squared.
    static let gravity: Double = 0.9

    /// The sparks of a merge making `value` at `cell` on a board `side` wide.
    /// Small merges fizz; 128 and up add a ring; the bigger the tile, the
    /// bigger the burst.
    static func merge(row: Int, col: Int, side: Int, value: Int, colour: Color, at now: Double) -> [Merge2048Spark] {
        let step = Merge2048Ladder.step(value)
        guard step >= 3 else { return [] }
        let unit = 1 / Double(max(side, 1))
        let cx = (Double(col) + 0.5) * unit
        let cy = (Double(row) + 0.5) * unit
        let count = min(6 + (step - 3) * 3, 30)
        let speed = 0.28 + Double(step) * 0.025
        var out: [Merge2048Spark] = []
        out.reserveCapacity(count + 1)
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * Double.pi + Double.random(in: -0.25...0.25)
            let v = speed * Double.random(in: 0.55...1.0)
            out.append(Merge2048Spark(x: cx, y: cy, vx: cos(angle) * v, vy: sin(angle) * v - 0.12,
                                      born: now, life: Double.random(in: 0.38...0.62),
                                      radius: unit * Double.random(in: 0.035...0.07),
                                      colour: colour, ring: false))
        }
        if step >= 7 {
            out.append(Merge2048Spark(x: cx, y: cy, vx: 0, vy: 0, born: now, life: 0.45,
                                      radius: unit * 0.9, colour: colour, ring: true))
        }
        return out
    }

    /// Confetti for a win: a fountain from the middle in the ramp's colours.
    static func celebration(at now: Double) -> [Merge2048Spark] {
        let colours: [Color] = [8, 32, 128, 256, 512, 1024, 2048].map { Merge2048Palette.swatch($0).glow }
        var out: [Merge2048Spark] = []
        out.reserveCapacity(90)
        for i in 0..<90 {
            let angle = -Double.pi / 2 + Double.random(in: -1.25...1.25)
            let v = Double.random(in: 0.5...1.15)
            out.append(Merge2048Spark(x: 0.5, y: 0.6, vx: cos(angle) * v, vy: sin(angle) * v,
                                      born: now + Double.random(in: 0...0.25), life: Double.random(in: 1.0...1.6),
                                      radius: Double.random(in: 0.008...0.016),
                                      colour: colours[i % colours.count], ring: false))
        }
        return out
    }
}

/// The sparks over the board. Its timeline runs only while a burst is alive;
/// between moves the layer is a still, empty canvas.
struct Merge2048SparksLayer: View {
    let sparks: [Merge2048Spark]
    let live: Bool
    /// Half the board's gap, in points.
    var inset: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !live)) { timeline in
            let now: Double = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                Merge2048SparksLayer.draw(sparks, now: now, inset: Double(inset), in: &context, size: size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func draw(_ sparks: [Merge2048Spark], now: Double, inset: Double,
                     in context: inout GraphicsContext, size: CGSize) {
        let o = max(0, inset)
        let w = max(1, Double(size.width) - 2 * o)
        for spark in sparks {
            let age = now - spark.born
            guard age >= 0, age <= spark.life else { continue }
            let t = age / spark.life
            let fade = 1 - t * t
            if spark.ring {
                let r = spark.radius * w * (0.35 + 0.65 * t)
                let rect = CGRect(x: o + spark.x * w - r, y: o + spark.y * w - r, width: r * 2, height: r * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(spark.colour.opacity(0.7 * fade)),
                               lineWidth: CGFloat(max(1.0, 6 * (1 - t))))
            } else {
                let px = o + (spark.x + spark.vx * age) * w
                let py = o + (spark.y + spark.vy * age + 0.5 * Merge2048SparkMaker.gravity * age * age) * w
                let r = spark.radius * w * (1 - 0.5 * t)
                let rect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(spark.colour.opacity(fade)))
            }
        }
    }
}
