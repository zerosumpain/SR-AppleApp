import SwiftUI

/// The wood a board is made of. Each level picks one, so the campaign does
/// not look like forty copies of the same tray. The board is a thing, not a
/// page, so it keeps its colours in dark mode as wood does.
struct TiltMazeWood: Equatable {
    let floorLight: Color
    let floorDark: Color
    let grain: Color
    let wallLight: Color
    let wallDark: Color
    let frameLight: Color
    let frameDark: Color

    static let oak = TiltMazeWood(
        floorLight: Color(hex: 0xE9CFA0), floorDark: Color(hex: 0xD2AE74), grain: Color(hex: 0x9A6B33),
        wallLight: Color(hex: 0xA8743C), wallDark: Color(hex: 0x6E4520),
        frameLight: Color(hex: 0x8A5A2B), frameDark: Color(hex: 0x4A2C12))
    static let walnut = TiltMazeWood(
        floorLight: Color(hex: 0xD9B98C), floorDark: Color(hex: 0xBC9361), grain: Color(hex: 0x7A5028),
        wallLight: Color(hex: 0x7B5233), wallDark: Color(hex: 0x4A2E1A),
        frameLight: Color(hex: 0x5E3B22), frameDark: Color(hex: 0x2E1A0D))
    static let cherry = TiltMazeWood(
        floorLight: Color(hex: 0xEBC39B), floorDark: Color(hex: 0xCF9A6C), grain: Color(hex: 0x9C5A35),
        wallLight: Color(hex: 0xA65A38), wallDark: Color(hex: 0x6A3020),
        frameLight: Color(hex: 0x86412A), frameDark: Color(hex: 0x431C11))

    static func of(level number: Int) -> TiltMazeWood {
        switch ((number - 1) % 3 + 3) % 3 {
        case 0: return .oak
        case 1: return .walnut
        default: return .cherry
        }
    }
}

/// Where the board's cells land on screen: a cell's size in points and the
/// width of the wooden frame round the play area.
struct TiltMazeGeometry: Equatable {
    let cols: Int
    let rows: Int
    let cell: CGFloat
    let rim: CGFloat

    /// The biggest board of `cols` × `rows` cells that fits `space`.
    static func fit(cols: Int, rows: Int, in space: CGSize) -> TiltMazeGeometry {
        // The frame is 0.45 of a cell each side.
        let across = max(1, space.width) / (CGFloat(cols) + 0.9)
        let down = max(1, space.height) / (CGFloat(rows) + 0.9)
        let cell = max(4, min(across, down)).rounded(.down)
        return TiltMazeGeometry(cols: cols, rows: rows, cell: cell, rim: (cell * 0.45).rounded())
    }

    var size: CGSize {
        CGSize(width: cell * CGFloat(cols) + rim * 2, height: cell * CGFloat(rows) + rim * 2)
    }

    var floor: CGRect { CGRect(x: rim, y: rim, width: cell * CGFloat(cols), height: cell * CGFloat(rows)) }

    func point(_ v: TiltMazeVector) -> CGPoint {
        CGPoint(x: rim + CGFloat(v.x) * cell, y: rim + CGFloat(v.y) * cell)
    }

    func rect(_ box: TiltMazeBox) -> CGRect {
        CGRect(x: rim + CGFloat(box.minX) * cell, y: rim + CGFloat(box.minY) * cell,
               width: CGFloat(box.width) * cell, height: CGFloat(box.height) * cell)
    }

    func circle(_ centre: TiltMazeVector, radius: Double) -> CGRect {
        let p = point(centre)
        let r = CGFloat(radius) * cell
        return CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
    }
}

/// The board: the floor (wood, grain, holes, flags, the cup, the walls'
/// shadows) drawn once; the wall tops drawn once and slid a point or two with
/// the tilt, so they stand up off the floor; and the live layer — the marble
/// and the flourishes — drawn every frame.
struct TiltMazeBoardView: View {
    let engine: TiltMazeEngine
    /// Which maze this is; the drawn-once layers redraw only when it changes.
    let key: String
    let level: TiltMazeLevel
    let wood: TiltMazeWood
    let geometry: TiltMazeGeometry

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The board's own shadow on the table, drawn once.
            RoundedRectangle(cornerRadius: geometry.rim * 0.8, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .blur(radius: 14)
                .offset(y: 10)
            TiltMazeFloorLayer(key: key, level: level, wood: wood, geometry: geometry)
                .equatable()
            TiltMazeRaisedWalls(engine: engine, key: key, level: level, wood: wood, geometry: geometry)
            TiltMazeLiveLayer(engine: engine, geometry: geometry)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
}

/// The floor, drawn once per maze.
struct TiltMazeFloorLayer: View, Equatable {
    let key: String
    let level: TiltMazeLevel
    let wood: TiltMazeWood
    let geometry: TiltMazeGeometry

    static func == (a: TiltMazeFloorLayer, b: TiltMazeFloorLayer) -> Bool {
        a.key == b.key && a.geometry == b.geometry && a.wood == b.wood
    }

    var body: some View {
        let painter = TiltMazeFloorPainter(key: key, level: level, wood: wood, geometry: geometry)
        Canvas { context, _ in
            painter.draw(in: context)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .accessibilityHidden(true)
    }
}

/// Paints the floor: plain values, so it draws the same wherever it is asked.
struct TiltMazeFloorPainter {
    let key: String
    let level: TiltMazeLevel
    let wood: TiltMazeWood
    let geometry: TiltMazeGeometry

    func draw(in canvas: GraphicsContext) {
        var context = canvas
        drawFrame(&context)
        drawFloor(&context)
        drawGrain(&context)
        drawStart(&context)
        drawHoles(&context)
        drawFlags(&context)
        drawGoal(&context)
        drawWallShadows(&context)
    }

    private func drawFrame(_ context: inout GraphicsContext) {
        let outer = CGRect(origin: .zero, size: geometry.size)
        let shape = Path(roundedRect: outer, cornerRadius: geometry.rim * 0.8, style: .continuous)
        context.fill(shape, with: .linearGradient(Gradient(colors: [wood.frameLight, wood.frameDark]),
                                                  startPoint: .zero, endPoint: CGPoint(x: outer.maxX, y: outer.maxY)))
        // A bevel: light along the top-left edge, dark along the bottom-right.
        let bevel = Path(roundedRect: outer.insetBy(dx: 1.5, dy: 1.5), cornerRadius: geometry.rim * 0.7, style: .continuous)
        context.stroke(bevel, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.35), Color.black.opacity(0.35)]),
                                                    startPoint: .zero, endPoint: CGPoint(x: outer.maxX, y: outer.maxY)),
                       lineWidth: 1.5)
    }

    private func drawFloor(_ context: inout GraphicsContext) {
        let floor = geometry.floor
        context.fill(Path(floor), with: .linearGradient(Gradient(colors: [wood.floorLight, wood.floorDark]),
                                                        startPoint: CGPoint(x: floor.minX, y: floor.minY),
                                                        endPoint: CGPoint(x: floor.maxX * 0.6, y: floor.maxY)))
        // A soft pool of light towards the top left, as from a lamp.
        context.fill(Path(floor), with: .radialGradient(Gradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0)]),
                                                        center: CGPoint(x: floor.minX + floor.width * 0.3, y: floor.minY + floor.height * 0.25),
                                                        startRadius: 0, endRadius: max(floor.width, floor.height) * 0.7))
    }

    /// Long wavy lines along the board: the grain. The same maze always has
    /// the same grain.
    private func drawGrain(_ context: inout GraphicsContext) {
        let floor = geometry.floor
        var rng = TiltMazeRandom(seed: TiltMazeFloorPainter.stableSeed(key))
        var layer = context
        layer.clip(to: Path(floor))
        let lines = 18 + geometry.rows * 2
        for _ in 0..<lines {
            let y0 = floor.minY + CGFloat(rng.unit()) * floor.height
            let wobble = CGFloat(2 + rng.unit() * 6)
            let phase = CGFloat(rng.unit() * 6)
            var path = Path()
            path.move(to: CGPoint(x: floor.minX - 4, y: y0))
            let steps = 8
            for i in 1...steps {
                let x = floor.minX - 4 + (floor.width + 8) * CGFloat(i) / CGFloat(steps)
                let y = y0 + sin(CGFloat(i) * 0.9 + phase) * wobble
                let cx = x - (floor.width + 8) / CGFloat(steps * 2)
                path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: y + wobble * 0.6))
            }
            let alpha = 0.06 + rng.unit() * 0.12
            layer.stroke(path, with: .color(wood.grain.opacity(alpha)), lineWidth: CGFloat(0.6 + rng.unit() * 1.4))
        }
        // The edge of the floor sits in shadow under the frame.
        layer.stroke(Path(floor), with: .color(Color.black.opacity(0.35)), lineWidth: max(3, geometry.cell * 0.12))
    }

    private func drawStart(_ context: inout GraphicsContext) {
        let ring = Path(ellipseIn: geometry.circle(level.start.centre, radius: 0.32))
        context.stroke(ring, with: .color(Color.black.opacity(0.18)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
    }

    private func drawHoles(_ context: inout GraphicsContext) {
        for hole in level.holes {
            let rect = geometry.circle(hole.centre, radius: TiltMazeRules.holeRadius)
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            // A worn lip, lighter on the far side where the lamp catches it.
            context.fill(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)),
                         with: .linearGradient(Gradient(colors: [Color.black.opacity(0.25), Color.white.opacity(0.35)]),
                                               startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                               endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            context.fill(Path(ellipseIn: rect),
                         with: .radialGradient(Gradient(colors: [Color(hex: 0x050302), Color(hex: 0x1A0F07), Color(hex: 0x3B2412)]),
                                               center: CGPoint(x: centre.x + rect.width * 0.08, y: centre.y + rect.height * 0.1),
                                               startRadius: 0, endRadius: rect.width * 0.55))
        }
    }

    private func drawFlags(_ context: inout GraphicsContext) {
        let brass = Gradient(colors: [Color(hex: 0xF6DC8B), Color(hex: 0xC9962E), Color(hex: 0x8A6418)])
        for flag in level.checkpoints {
            let rect = geometry.circle(flag.centre, radius: 0.3)
            context.fill(Path(ellipseIn: rect), with: .linearGradient(brass, startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                                                      endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            context.stroke(Path(ellipseIn: rect), with: .color(Color.black.opacity(0.3)), lineWidth: 1)
            // A little pennant on a pole.
            let s = rect.width
            var pole = Path()
            pole.move(to: CGPoint(x: rect.midX - s * 0.12, y: rect.midY + s * 0.28))
            pole.addLine(to: CGPoint(x: rect.midX - s * 0.12, y: rect.midY - s * 0.3))
            context.stroke(pole, with: .color(Color(hex: 0x3B2412)), lineWidth: max(1, s * 0.07))
            var pennant = Path()
            pennant.move(to: CGPoint(x: rect.midX - s * 0.1, y: rect.midY - s * 0.3))
            pennant.addLine(to: CGPoint(x: rect.midX + s * 0.26, y: rect.midY - s * 0.17))
            pennant.addLine(to: CGPoint(x: rect.midX - s * 0.1, y: rect.midY - s * 0.04))
            pennant.closeSubpath()
            context.fill(pennant, with: .color(Color(hex: 0xC8372D)))
        }
    }

    private func drawGoal(_ context: inout GraphicsContext) {
        let outer = geometry.circle(level.goal.centre, radius: 0.42)
        let inner = geometry.circle(level.goal.centre, radius: 0.31)
        let brass = Gradient(colors: [Color(hex: 0xFFF0B8), Color(hex: 0xE0B040), Color(hex: 0x9C6D14), Color(hex: 0xE8C25A)])
        context.fill(Path(ellipseIn: outer), with: .linearGradient(brass, startPoint: CGPoint(x: outer.minX, y: outer.minY),
                                                                   endPoint: CGPoint(x: outer.maxX, y: outer.maxY)))
        context.fill(Path(ellipseIn: inner),
                     with: .radialGradient(Gradient(colors: [Color(hex: 0x0C0703), Color(hex: 0x2A1A08)]),
                                           center: CGPoint(x: inner.midX, y: inner.midY + inner.height * 0.12),
                                           startRadius: 0, endRadius: inner.width * 0.6))
        context.stroke(Path(ellipseIn: outer), with: .color(Color.black.opacity(0.35)), lineWidth: 1)
        // A glint on the rim.
        var glint = Path()
        glint.addArc(center: CGPoint(x: outer.midX, y: outer.midY), radius: outer.width * 0.44,
                     startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
        context.stroke(glint, with: .color(Color.white.opacity(0.8)), style: StrokeStyle(lineWidth: max(1, geometry.cell * 0.04), lineCap: .round))
    }

    /// Each wall's shadow falls down and to the right of it, softly.
    private func drawWallShadows(_ context: inout GraphicsContext) {
        let dx = geometry.cell * 0.07, dy = geometry.cell * 0.10
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: max(1.5, geometry.cell * 0.08)))
            var shadows = Path()
            for box in level.boxes {
                shadows.addRect(geometry.rect(box).offsetBy(dx: dx, dy: dy))
            }
            layer.fill(shadows, with: .color(Color.black.opacity(0.38)))
        }
    }

    /// The same number for the same key on every run (a `String`'s own hash
    /// changes from launch to launch).
    static func stableSeed(_ key: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

/// The wall tops, slid a little with the tilt so they stand up off the
/// floor: near things move more than far things when the phone turns.
struct TiltMazeRaisedWalls: View {
    @ObservedObject var engine: TiltMazeEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let key: String
    let level: TiltMazeLevel
    let wood: TiltMazeWood
    let geometry: TiltMazeGeometry

    var body: some View {
        TiltMazeWallLayer(key: key, level: level, wood: wood, geometry: geometry)
            .equatable()
            .offset(shift)
    }

    private var shift: CGSize {
        guard !reduceMotion else { return .zero }
        let reach = min(3, geometry.cell * 0.08)
        let x = CGFloat(max(-1, min(1, engine.tilt.x / 0.35))) * reach
        let y = CGFloat(max(-1, min(1, engine.tilt.y / 0.35))) * reach
        return CGSize(width: x, height: y)
    }
}

/// The wall tops, drawn once per maze.
struct TiltMazeWallLayer: View, Equatable {
    let key: String
    let level: TiltMazeLevel
    let wood: TiltMazeWood
    let geometry: TiltMazeGeometry

    static func == (a: TiltMazeWallLayer, b: TiltMazeWallLayer) -> Bool {
        a.key == b.key && a.geometry == b.geometry && a.wood == b.wood
    }

    var body: some View {
        let painter = TiltMazeWallPainter(level: level, wood: wood, geometry: geometry)
        Canvas { context, _ in
            painter.draw(in: context)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .accessibilityHidden(true)
    }
}

/// Paints the wall tops.
struct TiltMazeWallPainter {
    let level: TiltMazeLevel
    let wood: TiltMazeWood
    let geometry: TiltMazeGeometry

    func draw(in canvas: GraphicsContext) {
        let context = canvas
        let corner = max(1, geometry.cell * CGFloat(TiltMazeRules.wall) * 0.4)
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [wood.wallLight, wood.wallDark]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: geometry.size.width * 0.15, y: geometry.size.height))
        var tops = Path()
        var edges = Path()
        for box in level.boxes {
            let rect = geometry.rect(box)
            tops.addRoundedRect(in: rect, cornerSize: CGSize(width: corner, height: corner))
            // A highlight along each wall's top-left edge.
            edges.move(to: CGPoint(x: rect.minX + corner, y: rect.minY + 0.75))
            edges.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY + 0.75))
            edges.move(to: CGPoint(x: rect.minX + 0.75, y: rect.minY + corner))
            edges.addLine(to: CGPoint(x: rect.minX + 0.75, y: rect.maxY - corner))
        }
        context.fill(tops, with: shading)
        context.stroke(edges, with: .color(Color.white.opacity(0.28)), lineWidth: 1)
        context.stroke(tops, with: .color(Color.black.opacity(0.25)), lineWidth: 0.5)
    }
}

/// What moves: the marble, its shadow and trail, the flags once reached, the
/// cup's glow and the flourishes. Redrawn every frame from the engine.
struct TiltMazeLiveLayer: View {
    @ObservedObject var engine: TiltMazeEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let geometry: TiltMazeGeometry

    var body: some View {
        let painter = TiltMazeLivePainter(run: engine.run, tilt: engine.tilt, clock: engine.clock, bursts: engine.bursts,
                                          trail: engine.trail, geometry: geometry, reduceMotion: reduceMotion)
        Canvas { context, _ in
            painter.draw(in: context)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .allowsHitTesting(false)
    }
}

/// Paints one frame of what moves, from a snapshot of the engine.
struct TiltMazeLivePainter {
    let run: TiltMazeRun
    let tilt: TiltMazeVector
    let clock: Double
    let bursts: [TiltMazeBurst]
    let trail: [TiltMazeVector]
    let geometry: TiltMazeGeometry
    let reduceMotion: Bool

    func draw(in canvas: GraphicsContext) {
        var context = canvas
        drawGoalGlow(&context, run: run)
        drawReachedFlags(&context, run: run)
        drawTrail(&context)
        drawBursts(&context)
        drawMarble(&context, run: run)
    }

    private func drawGoalGlow(_ context: inout GraphicsContext, run: TiltMazeRun) {
        let pulse = reduceMotion ? 0.5 : 0.5 + 0.5 * sin(clock * 3)
        let rect = geometry.circle(run.level.goal.centre, radius: 0.5 + 0.06 * pulse)
        context.stroke(Path(ellipseIn: rect), with: .color(Color(hex: 0xFFE08A).opacity(0.25 + 0.35 * pulse)),
                       lineWidth: max(1, geometry.cell * 0.05))
    }

    private func drawReachedFlags(_ context: inout GraphicsContext, run: TiltMazeRun) {
        for flag in run.reached {
            let rect = geometry.circle(flag.centre, radius: 0.38)
            context.fill(Path(ellipseIn: rect),
                         with: .radialGradient(Gradient(colors: [Color(hex: 0x7CF29A).opacity(0.55), Color(hex: 0x7CF29A).opacity(0)]),
                                               center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: rect.width * 0.6))
        }
    }

    private func drawTrail(_ context: inout GraphicsContext) {
        guard trail.count > 1, !reduceMotion else { return }
        let r = CGFloat(TiltMazeRules.radius) * geometry.cell
        for (i, point) in trail.enumerated() {
            let k = CGFloat(i + 1) / CGFloat(trail.count)
            let p = geometry.point(point)
            let size = r * (0.3 + 0.5 * k)
            context.fill(Path(ellipseIn: CGRect(x: p.x - size, y: p.y - size, width: size * 2, height: size * 2)),
                         with: .color(Color.white.opacity(Double(0.10 * k))))
        }
    }

    private func drawBursts(_ context: inout GraphicsContext) {
        let now = clock
        for burst in bursts {
            let age = now - burst.born
            guard age >= 0, age <= burst.lifetime else { continue }
            let t = age / burst.lifetime
            let centre = geometry.point(burst.at)
            switch burst.kind {
            case .goal:
                drawSparkles(&context, centre: centre, t: t, age: age)
                ring(&context, centre: centre, radius: 0.4 + 1.4 * t, colour: Color(hex: 0xFFE08A), alpha: 0.8 * (1 - t), width: 3)
            case .flag:
                ring(&context, centre: centre, radius: 0.3 + 1.0 * t, colour: Color(hex: 0x7CF29A), alpha: 0.9 * (1 - t), width: 3)
            case .fall:
                ring(&context, centre: centre, radius: 0.7 * (1 - t) + 0.2, colour: Color.black, alpha: 0.5 * (1 - t), width: 2)
            case .knock:
                ring(&context, centre: centre, radius: 0.3 + 0.4 * t, colour: Color.white, alpha: 0.45 * (1 - t), width: 1.5)
            }
        }
    }

    private func ring(_ context: inout GraphicsContext, centre: CGPoint, radius: Double, colour: Color, alpha: Double, width: CGFloat) {
        let r = CGFloat(radius) * geometry.cell
        context.stroke(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)),
                       with: .color(colour.opacity(max(0, alpha))), lineWidth: width)
    }

    /// Brass sparkles thrown out of the cup, slowing as they go. Worked out
    /// from their age alone: nothing is stored per sparkle.
    private func drawSparkles(_ context: inout GraphicsContext, centre: CGPoint, t: Double, age: Double) {
        let count = reduceMotion ? 8 : 22
        let fade = max(0, 1 - t)
        for i in 0..<count {
            let jitter = Self.jitter(i)
            let angle = Double(i) / Double(count) * 2 * Double.pi + jitter * 0.5
            let speed = 1.4 + 1.6 * Self.jitter(i + 97)
            let travel = speed * age * max(0, 1 - age / 2.2)
            let x = centre.x + CGFloat(cos(angle) * travel) * geometry.cell
            let y = centre.y + CGFloat(sin(angle) * travel) * geometry.cell + CGFloat(age * age * 0.6) * geometry.cell
            let size = geometry.cell * CGFloat(0.05 + 0.05 * jitter) * CGFloat(0.6 + 0.4 * fade)
            let colour = i % 3 == 0 ? Color.white : Color(hex: 0xFFD45C)
            context.fill(Path(ellipseIn: CGRect(x: x - size, y: y - size, width: size * 2, height: size * 2)),
                         with: .color(colour.opacity(fade)))
        }
    }

    /// A steel ball bearing: a shadow that leans with the tilt, a body lit
    /// from the top left, the warm floor caught underneath, and a sharp
    /// highlight that slides with the tilt.
    private func drawMarble(_ context: inout GraphicsContext, run: TiltMazeRun) {
        let drawn = run.drawn
        let centre = geometry.point(drawn.position)
        let r = CGFloat(TiltMazeRules.radius) * geometry.cell * CGFloat(drawn.scale)
        guard r > 0.5 else { return }
        let depth = CGFloat(drawn.depth)
        let tx = CGFloat(max(-1, min(1, tilt.x / 0.35)))
        let ty = CGFloat(max(-1, min(1, tilt.y / 0.35)))

        // The shadow, gone once the marble is down a hole.
        if depth < 0.6 {
            let sx = centre.x + r * (0.28 + 0.3 * tx), sy = centre.y + r * (0.38 + 0.3 * ty)
            let shadow = CGRect(x: sx - r * 1.05, y: sy - r * 0.9, width: r * 2.1, height: r * 1.8)
            context.fill(Path(ellipseIn: shadow),
                         with: .radialGradient(Gradient(colors: [Color.black.opacity(Double(0.5 * (1 - depth))), Color.black.opacity(0)]),
                                               center: CGPoint(x: shadow.midX, y: shadow.midY), startRadius: 0, endRadius: r * 1.05))
        }

        let body = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)
        let light = CGPoint(x: centre.x - r * (0.35 + 0.2 * tx), y: centre.y - r * (0.4 + 0.2 * ty))
        context.fill(Path(ellipseIn: body),
                     with: .radialGradient(Gradient(colors: [Color(hex: 0xFAFBFD), Color(hex: 0xB9C0CA), Color(hex: 0x5A626E), Color(hex: 0x23272E)]),
                                           center: light, startRadius: 0, endRadius: r * 2.1))
        // The wood reflected in the lower half.
        var reflection = context
        reflection.clip(to: Path(ellipseIn: body))
        reflection.fill(Path(ellipseIn: CGRect(x: centre.x - r * 0.9, y: centre.y + r * 0.25, width: r * 1.8, height: r * 1.0)),
                        with: .color(Color(hex: 0xC8935A).opacity(0.35)))
        // The highlight.
        let spot = r * 0.32
        context.fill(Path(ellipseIn: CGRect(x: light.x - spot, y: light.y - spot * 0.8, width: spot * 2, height: spot * 1.6)),
                     with: .radialGradient(Gradient(colors: [Color.white, Color.white.opacity(0)]),
                                           center: light, startRadius: 0, endRadius: spot))
        context.stroke(Path(ellipseIn: body), with: .color(Color.black.opacity(0.35)), lineWidth: 0.5)
        // Down a hole or in the cup it darkens as it goes.
        if depth > 0 {
            context.fill(Path(ellipseIn: body), with: .color(Color.black.opacity(Double(0.75 * depth))))
        }
    }

    /// A steady 0..<1 for each `i`: the same sparkle always flies the same way.
    private static func jitter(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898) * 43758.5453
        return x - x.rounded(.down)
    }
}
