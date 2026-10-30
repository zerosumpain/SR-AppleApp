import SwiftUI

/// The moving part of the board, redrawn every frame from the session's
/// clock: the apples, the snake gliding between cells, its eyes and tongue,
/// the sparks and the points rising from what it ate.
struct SnakeFieldView: View {
    @ObservedObject var clock: SnakeClock
    let session: SnakeSession
    let skin: SnakeSkinPaint
    let calm: Bool

    var body: some View {
        let scene = SnakeScene(game: session.game, fraction: session.fraction, now: clock.now,
                               sparks: session.sparks, pops: session.pops, foodBorn: session.foodBorn,
                               goldenBorn: session.goldenBorn, ateAt: session.ateAt, endedAt: session.endedAt,
                               skin: skin, calm: calm)
        Canvas(rendersAsynchronously: false) { context, size in
            scene.draw(in: context, size: size)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One frame of the board, as values: drawn, never kept.
struct SnakeScene {
    let game: SnakeGame
    let fraction: Double
    let now: Double
    let sparks: [SnakeSpark]
    let pops: [SnakePop]
    let foodBorn: Double
    let goldenBorn: Double
    let ateAt: Double
    let endedAt: Double?
    let skin: SnakeSkinPaint
    let calm: Bool

    /// Seconds since the crash (or the win), if it has happened.
    private var sinceEnd: Double? { endedAt.map { max(0, now - $0) } }

    func draw(in context: GraphicsContext, size: CGSize) {
        let cell = size.width / CGFloat(max(1, game.columns))
        var c = context
        c.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: SnakeLayout.radius))
        if let since = sinceEnd, game.death != nil, !calm, since < 0.4 {
            // A short, sharp shake as it hits.
            let fade = 1 - since / 0.4
            c.translateBy(x: CGFloat(sin(since * 70) * fade) * cell * 0.22,
                          y: CGFloat(cos(since * 55) * fade) * cell * 0.12)
        }
        if let food = game.food {
            drawApple(c, at: food, cell: cell, born: foodBorn, gold: false, remaining: 1)
        }
        if let gold = game.golden {
            drawApple(c, at: gold.at, cell: cell, born: goldenBorn, gold: true, remaining: gold.remaining)
        }
        drawSnake(c, cell: cell)
        drawSparks(c, cell: cell)
        drawPops(c, cell: cell)
        if let since = sinceEnd, game.death != nil, since < 0.45 {
            let flash = 0.3 * (1 - since / 0.45)
            c.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.red.opacity(flash)))
        }
    }

    private func point(_ v: SnakeVec, _ cell: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(v.x) * cell, y: CGFloat(v.y) * cell)
    }

    // MARK: - Apples

    private func drawApple(_ context: GraphicsContext, at spot: SnakePoint, cell: CGFloat, born: Double,
                           gold: Bool, remaining: Double) {
        let age = max(0, now - born)
        let appear = min(1, age / 0.35)
        // A pop in with a little overshoot.
        let u: Double = appear - 1
        let pop: Double = appear >= 1 ? 1 : 1 + 2.7 * u * u * u + 1.7 * u * u
        let bob = calm ? 0 : sin(now * 3.4 + Double(spot.x)) * 0.045
        let cx = (CGFloat(spot.x) + 0.5) * cell
        let cy = (CGFloat(spot.y) + 0.5 + CGFloat(bob)) * cell
        let r = cell * 0.36 * CGFloat(max(0.05, pop))
        var c = context
        if gold && remaining < 0.25 && !calm {
            // About to go: it flickers.
            c.opacity = 0.55 + 0.45 * abs(sin(now * 9))
        }

        let shadow = CGRect(x: cx - r * 0.8, y: (CGFloat(spot.y) + 0.5) * cell + r * 0.62, width: r * 1.6, height: r * 0.5)
        c.fill(Path(ellipseIn: shadow), with: .color(Color.black.opacity(0.2)))

        if gold { drawGoldenHalo(c, cx: cx, cy: cy, r: r, remaining: remaining) }

        let skinRect = CGRect(x: cx - r, y: cy - r * 0.94, width: r * 2, height: r * 1.94)
        let colours: [Color] = gold
            ? [SnakeInk.goldLight, SnakeInk.gold, SnakeInk.goldDeep]
            : [SnakeInk.appleLight, SnakeInk.apple, SnakeInk.appleDeep]
        c.fill(Path(ellipseIn: skinRect),
               with: .radialGradient(Gradient(colors: colours), center: CGPoint(x: cx - r * 0.35, y: cy - r * 0.4),
                                     startRadius: 0, endRadius: r * 1.7))

        var stem = Path()
        stem.move(to: CGPoint(x: cx, y: cy - r * 0.78))
        stem.addQuadCurve(to: CGPoint(x: cx + r * 0.18, y: cy - r * 1.28), control: CGPoint(x: cx - r * 0.02, y: cy - r * 1.1))
        c.stroke(stem, with: .color(SnakeInk.stem), style: StrokeStyle(lineWidth: max(1, r * 0.17), lineCap: .round))

        let leaf = Path(ellipseIn: CGRect(x: 0, y: -r * 0.17, width: r * 0.72, height: r * 0.34))
            .applying(CGAffineTransform(rotationAngle: -0.55))
            .applying(CGAffineTransform(translationX: cx + r * 0.1, y: cy - r * 0.98))
        c.fill(leaf, with: .color(SnakeInk.leaf))

        let shine = CGRect(x: cx - r * 0.62, y: cy - r * 0.6, width: r * 0.48, height: r * 0.34)
        c.fill(Path(ellipseIn: shine), with: .color(Color.white.opacity(0.6)))
    }

    /// Twinkling stars round the golden apple, and a ring showing how long is left.
    private func drawGoldenHalo(_ context: GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat, remaining: Double) {
        var ring = Path()
        let start = Angle(degrees: -90)
        ring.addArc(center: CGPoint(x: cx, y: cy), radius: r * 1.5, startAngle: start,
                    endAngle: Angle(degrees: -90 + 360 * max(0, min(1, remaining))), clockwise: false)
        context.stroke(Path(ellipseIn: CGRect(x: cx - r * 1.5, y: cy - r * 1.5, width: r * 3, height: r * 3)),
                       with: .color(Color.white.opacity(0.18)), lineWidth: max(1.5, r * 0.16))
        context.stroke(ring, with: .color(Color.white.opacity(0.9)),
                       style: StrokeStyle(lineWidth: max(1.5, r * 0.16), lineCap: .round))
        for k in 0..<3 {
            let angle = now * (calm ? 0.3 : 1.6) + Double(k) * 2 * Double.pi / 3
            let twinkle = 0.6 + 0.4 * sin(now * 5 + Double(k) * 2)
            let s = r * 0.42 * CGFloat(twinkle)
            let px = cx + CGFloat(cos(angle)) * r * 1.95
            let py = cy + CGFloat(sin(angle)) * r * 1.95
            context.fill(sparkle(CGPoint(x: px, y: py), s), with: .color(SnakeInk.goldLight))
        }
    }

    private func sparkle(_ centre: CGPoint, _ s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: centre.x, y: centre.y - s))
        p.addQuadCurve(to: CGPoint(x: centre.x + s, y: centre.y), control: centre)
        p.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y + s), control: centre)
        p.addQuadCurve(to: CGPoint(x: centre.x - s, y: centre.y), control: centre)
        p.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y - s), control: centre)
        p.closeSubpath()
        return p
    }

    // MARK: - The snake

    private func drawSnake(_ context: GraphicsContext, cell: CGFloat) {
        let centres = SnakePath.centres(body: game.body, vacated: game.isOver ? nil : game.vacated,
                                        fraction: game.isOver ? 1 : fraction,
                                        columns: game.columns, rows: game.rows)
        guard let head = centres.first else { return }
        let parts = SnakePath.split(centres, tail: 1.6, spacing: 0.2)
        let shifts: [SnakeVec] = game.mode.edgesKill
            ? [SnakeVec(0, 0)]
            : SnakePath.copies(of: centres, columns: game.columns, rows: game.rows)
        let width = cell * 0.74
        var c = context
        if let since = sinceEnd, game.death != nil {
            // Fades to a ghost as it breaks up.
            c.opacity = max(0.25, 1 - since * 0.9)
        }
        for shift in shifts {
            var copy = c
            copy.translateBy(x: CGFloat(shift.x) * cell, y: CGFloat(shift.y) * cell)
            drawBody(copy, parts: parts, cell: cell, width: width)
            drawHead(copy, at: point(head, cell), cell: cell, width: width)
        }
    }

    /// The line through the cells with the corners rounded: a curve through
    /// each cell's middle from the half-way points either side.
    private func smooth(_ points: [SnakeVec], _ cell: CGFloat) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: point(first, cell))
        if points.count == 1 { return path }
        if points.count == 2 {
            path.addLine(to: point(points[1], cell))
            return path
        }
        for i in 1..<(points.count - 1) {
            let mid = points[i].lerp(to: points[i + 1], 0.5)
            path.addQuadCurve(to: point(mid, cell), control: point(points[i], cell))
        }
        path.addLine(to: point(points[points.count - 1], cell))
        return path
    }

    private func drawBody(_ context: GraphicsContext, parts: (body: [SnakeVec], tail: [SnakeVec]),
                          cell: CGFloat, width: CGFloat) {
        let line = smooth(parts.body, cell)
        let round = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        let inner = StrokeStyle(lineWidth: width * 0.8, lineCap: .round, lineJoin: .round)
        let tail = parts.tail
        let tailCount = max(1, tail.count - 1)

        // The shadow on the grass.
        var shadow = context
        shadow.translateBy(x: cell * 0.06, y: cell * 0.16)
        shadow.stroke(line, with: .color(Color.black.opacity(0.2)), style: round)
        for (j, v) in tail.enumerated() {
            let rr = tailRadius(j, of: tailCount, width: width)
            shadow.fill(circle(point(v, cell), rr), with: .color(Color.black.opacity(0.2)))
        }

        // Outline, then the colour inside it.
        context.stroke(line, with: .color(skin.dark), style: round)
        for (j, v) in tail.enumerated() {
            context.fill(circle(point(v, cell), tailRadius(j, of: tailCount, width: width)), with: .color(skin.dark))
        }
        if skin.rainbow {
            drawRainbow(context, parts: parts, cell: cell, style: inner, width: width, tailCount: tailCount)
        } else {
            context.stroke(line, with: .color(skin.main), style: inner)
            for (j, v) in tail.enumerated() {
                let rr = tailRadius(j, of: tailCount, width: width) - width * 0.1
                context.fill(circle(point(v, cell), max(0.5, rr)), with: .color(skin.main))
            }
        }

        // Stripes that stay with the body as it moves (one a cell), and a shine.
        let phase = CGFloat(1 - min(1, max(0, game.isOver ? 1 : fraction))) * cell
        let stripes = StrokeStyle(lineWidth: width * 0.34, lineCap: .round, lineJoin: .round,
                                  dash: [cell * 0.22, cell * 0.78], dashPhase: phase)
        context.stroke(line, with: .color(skin.light.opacity(skin.rainbow ? 0.35 : 0.55)), style: stripes)
        var shine = context
        shine.translateBy(x: -width * 0.13, y: -width * 0.15)
        shine.stroke(line, with: .color(Color.white.opacity(0.24)),
                     style: StrokeStyle(lineWidth: width * 0.2, lineCap: .round, lineJoin: .round))
    }

    private func drawRainbow(_ context: GraphicsContext, parts: (body: [SnakeVec], tail: [SnakeVec]),
                             cell: CGFloat, style: StrokeStyle, width: CGFloat, tailCount: Int) {
        let body = parts.body
        if body.count >= 2 {
            for i in 1..<body.count {
                var segment = Path()
                segment.move(to: point(body[i - 1], cell))
                segment.addLine(to: point(body[i], cell))
                context.stroke(segment, with: .color(SnakeSkinPaint.rainbowColour(Double(i), now: now)), style: style)
            }
        }
        let base = Double(body.count)
        for (j, v) in parts.tail.enumerated() {
            let rr = tailRadius(j, of: tailCount, width: width) - width * 0.1
            let colour = SnakeSkinPaint.rainbowColour(base + Double(j) * 0.2, now: now)
            context.fill(circle(point(v, cell), max(0.5, rr)), with: .color(colour))
        }
    }

    private func tailRadius(_ j: Int, of count: Int, width: CGFloat) -> CGFloat {
        let k = CGFloat(j) / CGFloat(max(1, count))
        return width * 0.5 * (1 - 0.62 * k)
    }

    private func circle(_ centre: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
    }

    // MARK: - The head

    private func drawHead(_ context: GraphicsContext, at centre: CGPoint, cell: CGFloat, width: CGFloat) {
        let angle = game.isOver ? game.heading.angle
            : SnakePath.angle(from: game.previousHeading, to: game.heading, fraction: fraction)
        let sinceMeal = now - ateAt
        let gulp = (sinceMeal >= 0 && sinceMeal < 0.26 && !calm) ? 1 + 0.2 * sin(sinceMeal / 0.26 * Double.pi) : 1
        let r = width * 0.58 * CGFloat(gulp)
        var c = context
        c.translateBy(x: centre.x, y: centre.y)
        c.rotate(by: Angle(radians: angle))
        // In here +x is the way the head faces.
        if game.death == nil { drawTongue(c, r: r) }
        let mainColour = skin.rainbow ? SnakeSkinPaint.rainbowColour(0, now: now) : skin.main
        c.fill(circle(.zero, r), with: .color(skin.dark))
        c.fill(circle(.zero, r - width * 0.1), with: .color(mainColour))
        c.fill(Path(ellipseIn: CGRect(x: -r * 0.55, y: -r * 0.7, width: r * 0.6, height: r * 0.34)),
               with: .color(Color.white.opacity(0.22)))
        drawEyes(c, r: r)
    }

    /// A forked tongue that flicks out every couple of seconds.
    private func drawTongue(_ context: GraphicsContext, r: CGFloat) {
        let period = 2.3
        let phase = now - floor(now / period) * period
        let flick = 0.32
        guard phase < flick else { return }
        let out = CGFloat(sin(phase / flick * Double.pi))
        let base = CGPoint(x: r * 0.8, y: 0)
        let tip = CGPoint(x: r * (0.8 + 0.8 * out), y: 0)
        let fork = r * 0.28 * out
        var path = Path()
        path.move(to: base)
        path.addLine(to: tip)
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x + fork, y: -fork * 0.7))
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x + fork, y: fork * 0.7))
        context.stroke(path, with: .color(SnakeInk.tongue),
                       style: StrokeStyle(lineWidth: max(1, r * 0.13), lineCap: .round, lineJoin: .round))
    }

    /// Two eyes that look the way the snake is about to turn, blink now and
    /// then, and cross when it crashes.
    private func drawEyes(_ context: GraphicsContext, r: CGFloat) {
        let eyeR = r * 0.34
        let sides: [CGFloat] = [-1, 1]
        if game.death != nil {
            var cross = Path()
            for side in sides {
                let ex = r * 0.22, ey = side * r * 0.46
                let d = eyeR * 0.7
                cross.move(to: CGPoint(x: ex - d, y: ey - d))
                cross.addLine(to: CGPoint(x: ex + d, y: ey + d))
                cross.move(to: CGPoint(x: ex - d, y: ey + d))
                cross.addLine(to: CGPoint(x: ex + d, y: ey - d))
            }
            context.stroke(cross, with: .color(Color.white), style: StrokeStyle(lineWidth: max(1.2, r * 0.16), lineCap: .round))
            return
        }
        // The turn waiting, relative to the way the head points.
        var look = game.nextHeading.angle - game.heading.angle
        while look > Double.pi { look -= 2 * Double.pi }
        while look < -Double.pi { look += 2 * Double.pi }
        let lx = CGFloat(cos(look)) * eyeR * 0.38
        let ly = CGFloat(sin(look)) * eyeR * 0.38
        let blinkPhase = (now + 0.9) - floor((now + 0.9) / 3.7) * 3.7
        let squash: CGFloat = blinkPhase < 0.13 ? 0.18 : 1
        for side in sides {
            let ex = r * 0.22, ey = side * r * 0.46
            let white = CGRect(x: ex - eyeR * squash, y: ey - eyeR, width: eyeR * 2 * squash, height: eyeR * 2)
            context.fill(Path(ellipseIn: white), with: .color(Color.white))
            guard squash == 1 else { continue }
            let pr = eyeR * 0.55
            let pupil = CGRect(x: ex + lx - pr, y: ey + ly - pr, width: pr * 2, height: pr * 2)
            context.fill(Path(ellipseIn: pupil), with: .color(Color(hex: 0x141414)))
            let glint = CGRect(x: ex + lx - pr * 0.1, y: ey + ly - pr * 0.75, width: pr * 0.55, height: pr * 0.55)
            context.fill(Path(ellipseIn: glint), with: .color(Color.white.opacity(0.9)))
        }
    }

    // MARK: - Sparks and points

    private func drawSparks(_ context: GraphicsContext, cell: CGFloat) {
        let gravity = 7.0
        for spark in sparks {
            let age = now - spark.born
            guard age >= 0, age <= spark.life else { continue }
            let t = age / spark.life
            let x = spark.x + spark.vx * age
            let y = spark.y + spark.vy * age + 0.5 * gravity * age * age
            let r = CGFloat(spark.size * (1 - 0.6 * t)) * cell
            let colour = sparkColour(spark).opacity(1 - t * t)
            context.fill(circle(CGPoint(x: CGFloat(x) * cell, y: CGFloat(y) * cell), max(0.5, r)), with: .color(colour))
        }
    }

    private func sparkColour(_ spark: SnakeSpark) -> Color {
        switch spark.kind {
        case .apple: return spark.hue < 0.3 ? Color.white : SnakeInk.apple
        case .gold: return spark.hue < 0.35 ? Color.white : SnakeInk.gold
        case .leaf: return SnakeInk.leaf
        case .body: return skin.rainbow ? SnakeSkinPaint.rainbowColour(spark.hue / 0.055, now: now) : (spark.hue.truncatingRemainder(dividingBy: 0.11) < 0.055 ? skin.main : skin.dark)
        case .confetti: return Color(hue: spark.hue, saturation: 0.75, brightness: 1)
        }
    }

    private func drawPops(_ context: GraphicsContext, cell: CGFloat) {
        for pop in pops {
            let age = now - pop.born
            guard age >= 0, age < 0.9 else { continue }
            let t = age / 0.9
            let rise = 0.4 + 1.1 * (1 - (1 - t) * (1 - t))
            let at = CGPoint(x: CGFloat(pop.x) * cell, y: CGFloat(pop.y - rise) * cell)
            var c = context
            c.opacity = t < 0.6 ? 1 : 1 - (t - 0.6) / 0.4
            let size = cell * (pop.gold ? 0.78 : 0.62)
            let shadow = c.resolve(Text(pop.text).font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundColor(Color.black.opacity(0.35)))
            let label = c.resolve(Text(pop.text).font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundColor(pop.gold ? SnakeInk.goldLight : Color.white))
            c.draw(shadow, at: CGPoint(x: at.x + 1, y: at.y + 1.5), anchor: .center)
            c.draw(label, at: at, anchor: .center)
        }
    }
}
