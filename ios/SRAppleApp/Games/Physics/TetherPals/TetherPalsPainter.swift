import SwiftUI

/// Tether Pals' own world colours: a pastel day, and a softer dusk for dark
/// mode. The HUD, cards and buttons around it are SR's.
struct TetherPalsPalette {
    let skyTop: Color
    let skyBottom: Color
    let hill: Color
    let cloud: Color
    let soil: Color
    let soilDot: Color
    let grass: Color
    let grassDark: Color
    let prickle: Color
    let prickleEdge: Color
    let rope: Color
    let pole: Color
    let cloth: Color

    static func of(dark: Bool) -> TetherPalsPalette {
        dark
            ? TetherPalsPalette(skyTop: Color(red: 0.16, green: 0.17, blue: 0.33), skyBottom: Color(red: 0.36, green: 0.29, blue: 0.45),
                                hill: Color(red: 0.25, green: 0.27, blue: 0.42), cloud: Color.white.opacity(0.14),
                                soil: Color(red: 0.42, green: 0.33, blue: 0.36), soilDot: Color(red: 0.34, green: 0.26, blue: 0.30),
                                grass: Color(red: 0.42, green: 0.70, blue: 0.52), grassDark: Color(red: 0.30, green: 0.55, blue: 0.42),
                                prickle: Color(red: 0.93, green: 0.55, blue: 0.70), prickleEdge: Color(red: 0.62, green: 0.28, blue: 0.45),
                                rope: Color(red: 0.95, green: 0.84, blue: 0.62), pole: Color(red: 0.85, green: 0.85, blue: 0.90),
                                cloth: Color(red: 1.0, green: 0.78, blue: 0.35))
            : TetherPalsPalette(skyTop: Color(red: 0.70, green: 0.86, blue: 0.98), skyBottom: Color(red: 1.0, green: 0.90, blue: 0.84),
                                hill: Color(red: 0.78, green: 0.90, blue: 0.80), cloud: Color.white.opacity(0.85),
                                soil: Color(red: 0.80, green: 0.62, blue: 0.52), soilDot: Color(red: 0.72, green: 0.53, blue: 0.45),
                                grass: Color(red: 0.55, green: 0.84, blue: 0.55), grassDark: Color(red: 0.40, green: 0.70, blue: 0.45),
                                prickle: Color(red: 0.98, green: 0.62, blue: 0.76), prickleEdge: Color(red: 0.78, green: 0.35, blue: 0.55),
                                rope: Color(red: 0.62, green: 0.45, blue: 0.30), pole: Color(red: 0.45, green: 0.42, blue: 0.50),
                                cloth: Color(red: 1.0, green: 0.55, blue: 0.30))
    }

    /// Pip coral, Bo sky blue, Kit mint: the same in light and dark, so a
    /// strip of buttons always matches its pal.
    static func pal(_ index: Int) -> Color {
        switch index {
        case 0: return Color(red: 1.0, green: 0.55, blue: 0.48)
        case 1: return Color(red: 0.42, green: 0.74, blue: 1.0)
        default: return Color(red: 0.45, green: 0.85, blue: 0.62)
        }
    }

    /// A darker shade of a pal's colour, for outlines and pressed keys.
    static func palDeep(_ index: Int) -> Color {
        switch index {
        case 0: return Color(red: 0.80, green: 0.32, blue: 0.30)
        case 1: return Color(red: 0.20, green: 0.50, blue: 0.82)
        default: return Color(red: 0.22, green: 0.62, blue: 0.42)
        }
    }

    /// Ink on the pastel pals and keys, the same in light and dark.
    static let ink = Color(red: 0.17, green: 0.14, blue: 0.25)

    static func channel(_ channel: TetherPalsChannel) -> Color {
        channel == .gold ? Color(red: 1.0, green: 0.77, blue: 0.25) : Color(red: 0.62, green: 0.52, blue: 1.0)
    }

    static func channelDeep(_ channel: TetherPalsChannel) -> Color {
        channel == .gold ? Color(red: 0.78, green: 0.53, blue: 0.08) : Color(red: 0.40, green: 0.30, blue: 0.80)
    }
}

/// Draws one frame of a level from the world as it is: sky, tiles, gates,
/// the flag, ropes, pals and sparks. A value type, made fresh each frame.
struct TetherPalsPainter {
    let world: TetherPalsWorld
    let sparks: [TetherPalsSpark]
    let time: Double
    let marked: Int?
    let swappedAt: Double
    let palette: TetherPalsPalette
    let calm: Bool
    let cell: CGFloat

    private var level: TetherPalsLevel { world.level }

    func draw(_ context: inout GraphicsContext, size: CGSize) {
        sky(&context, size: size)
        homeMat(&context)
        for row in 0..<level.rows {
            for col in 0..<level.columns { tile(&context, col: col, row: row) }
        }
        flag(&context)
        if level.tied { ropes(&context) }
        let order = world.pals.indices.sorted { world.pals[$0].bottom > world.pals[$1].bottom }
        for index in order { pal(&context, index) }
        drawSparks(&context)
    }

    // MARK: - Geometry

    private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: CGFloat(w) * cell, height: CGFloat(h) * cell)
    }

    private func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x) * cell, y: CGFloat(y) * cell)
    }

    // MARK: - Sky

    private func sky(_ context: inout GraphicsContext, size: CGSize) {
        let whole = CGRect(origin: .zero, size: size)
        context.fill(Path(whole), with: .linearGradient(Gradient(colors: [palette.skyTop, palette.skyBottom]),
                                                         startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let hills: [(Double, Double, Double)] = [(3, 9.6, 5.5), (11.5, 9.9, 7)]
        for hill in hills {
            context.fill(Path(ellipseIn: rect(hill.0 - hill.2 / 2, hill.1 - 2.4, hill.2, 4.8)), with: .color(palette.hill))
        }
        let drift = calm ? 0 : time * 0.12
        let clouds: [(Double, Double, Double)] = [(2.5, 1.4, 1.0), (8.5, 0.8, 0.8), (13.5, 2.2, 1.2)]
        for cloud in clouds {
            let span = Double(level.columns) + 4
            let x = (cloud.0 + drift).truncatingRemainder(dividingBy: span) - 2
            let s = cloud.2
            for puff in [(0.0, 0.0, 0.7), (0.55, -0.2, 0.85), (1.1, 0.0, 0.65)] {
                let r = puff.2 * s
                context.fill(Path(ellipseIn: rect(x + puff.0 * s - r / 2, cloud.1 + puff.1 * s - r / 2, r, r * 0.8)),
                             with: .color(palette.cloud))
            }
        }
    }

    /// A soft strip on the ground at the flag: where everyone has to stand.
    private func homeMat(_ context: inout GraphicsContext) {
        let f = level.flag
        let glow = world.homeCount > 0 ? 0.55 : 0.3
        let mat = rect(Double(f.col) - 1 + 0.05, Double(f.row) + 0.82, 2.9, 0.18)
        context.fill(Path(roundedRect: mat, cornerRadius: mat.height / 2), with: .color(palette.cloth.opacity(glow)))
    }

    // MARK: - Tiles

    private func tile(_ context: inout GraphicsContext, col: Int, row: Int) {
        let x = Double(col), y = Double(row)
        switch level.tile(col: col, row: row) {
        case .empty:
            break
        case .ground:
            ground(&context, col: col, row: row)
        case .prickles:
            prickles(&context, x: x, y: y)
        case .button(let channel):
            button(&context, x: x, y: y, channel: channel)
        case .door(let channel):
            door(&context, x: x, y: y, channel: channel, shown: shown(col, row))
        case .bridge(let channel):
            bridge(&context, x: x, y: y, channel: channel, shown: shown(col, row))
        }
    }

    private func shown(_ col: Int, _ row: Int) -> Double {
        guard let index = level.gateIndex[TetherPalsCell(col: col, row: row)], index < world.gateShown.count else { return 0 }
        return world.gateShown[index]
    }

    private func ground(_ context: inout GraphicsContext, col: Int, row: Int) {
        let x = Double(col), y = Double(row)
        context.fill(Path(rect(x, y, 1.02, 1.02)), with: .color(palette.soil))
        // A few pebbles, the same every frame.
        let seed = (col &* 73 &+ row &* 151) % 7
        if seed < 4 {
            let px = x + 0.2 + Double(seed) * 0.15, py = y + 0.45 + Double(seed % 2) * 0.25
            context.fill(Path(ellipseIn: rect(px, py, 0.16, 0.11)), with: .color(palette.soilDot))
        }
        let above = level.tile(col: col, row: row - 1)
        guard row == 0 || above != .ground else { return }
        let cap = rect(x - 0.01, y, 1.04, 0.3)
        context.fill(Path(roundedRect: cap, cornerRadius: cap.height * 0.35), with: .color(palette.grass))
        for bump in 0..<3 {
            let bx = x + 0.12 + Double(bump) * 0.3
            context.fill(Path(ellipseIn: rect(bx, y + 0.18, 0.22, 0.2)), with: .color(palette.grass))
        }
        context.fill(Path(rect(x, y + 0.25, 1.02, 0.04)), with: .color(palette.grassDark.opacity(0.5)))
    }

    private func prickles(_ context: inout GraphicsContext, x: Double, y: Double) {
        for i in 0..<3 {
            let left = x + 0.1 + Double(i) * 0.27
            var spike = Path()
            spike.move(to: point(left, y + 1))
            spike.addQuadCurve(to: point(left + 0.13, y + 0.5), control: point(left + 0.02, y + 0.7))
            spike.addQuadCurve(to: point(left + 0.26, y + 1), control: point(left + 0.24, y + 0.7))
            spike.closeSubpath()
            context.fill(spike, with: .color(palette.prickle))
            context.stroke(spike, with: .color(palette.prickleEdge), lineWidth: max(1, cell * 0.04))
        }
    }

    private func button(_ context: inout GraphicsContext, x: Double, y: Double, channel: TetherPalsChannel) {
        let down = world.isPressed(channel)
        let height = down ? 0.1 : 0.2
        let base = rect(x + 0.08, y + 0.92, 0.84, 0.08)
        context.fill(Path(roundedRect: base, cornerRadius: base.height / 2), with: .color(TetherPalsPalette.channelDeep(channel)))
        let cap = rect(x + 0.18, y + 0.94 - height, 0.64, height)
        context.fill(Path(roundedRect: cap, cornerRadius: cap.height / 2), with: .color(TetherPalsPalette.channel(channel)))
        if down {
            context.fill(Path(ellipseIn: rect(x + 0.05, y + 0.55, 0.9, 0.5)),
                         with: .color(TetherPalsPalette.channel(channel).opacity(0.3)))
        }
    }

    private func door(_ context: inout GraphicsContext, x: Double, y: Double, channel: TetherPalsChannel, shown: Double) {
        let colour = TetherPalsPalette.channel(channel)
        let outline = rect(x + 0.1, y + 0.02, 0.8, 0.96)
        if shown < 0.99 {
            context.stroke(Path(roundedRect: outline, cornerRadius: cell * 0.12), with: .color(colour.opacity(0.55)),
                           style: StrokeStyle(lineWidth: max(1, cell * 0.05), dash: [cell * 0.12, cell * 0.1]))
        }
        guard shown > 0.01 else { return }
        // The panel slides up into the top of its tile as it opens.
        let panel = rect(x + 0.1, y + 0.02, 0.8, 0.96 * shown)
        context.fill(Path(roundedRect: panel, cornerRadius: cell * 0.12), with: .color(colour))
        context.stroke(Path(roundedRect: panel, cornerRadius: cell * 0.12),
                       with: .color(TetherPalsPalette.channelDeep(channel)), lineWidth: max(1, cell * 0.05))
        if shown > 0.6 {
            context.fill(Path(rect(x + 0.2, y + 0.3, 0.6, 0.06)), with: .color(TetherPalsPalette.channelDeep(channel).opacity(0.5)))
            context.fill(Path(rect(x + 0.2, y + 0.62, 0.6, 0.06)), with: .color(TetherPalsPalette.channelDeep(channel).opacity(0.5)))
        }
    }

    private func bridge(_ context: inout GraphicsContext, x: Double, y: Double, channel: TetherPalsChannel, shown: Double) {
        let colour = TetherPalsPalette.channel(channel)
        let plank = rect(x + 0.02, y, 0.96, 0.42)
        if shown < 0.99 {
            context.stroke(Path(roundedRect: plank, cornerRadius: cell * 0.1), with: .color(colour.opacity(0.6)),
                           style: StrokeStyle(lineWidth: max(1, cell * 0.05), dash: [cell * 0.12, cell * 0.1]))
        }
        guard shown > 0.01 else { return }
        var faded = context
        faded.opacity = shown
        faded.fill(Path(roundedRect: plank, cornerRadius: cell * 0.1), with: .color(colour))
        faded.stroke(Path(roundedRect: plank, cornerRadius: cell * 0.1),
                     with: .color(TetherPalsPalette.channelDeep(channel)), lineWidth: max(1, cell * 0.05))
        faded.fill(Path(rect(x + 0.48, y + 0.06, 0.04, 0.3)), with: .color(TetherPalsPalette.channelDeep(channel).opacity(0.6)))
    }

    // MARK: - Flag

    private func flag(_ context: inout GraphicsContext) {
        let f = level.flag
        let x = Double(f.col) + 0.3, foot = Double(f.row) + 1, top = foot - 1.9
        context.fill(Path(roundedRect: rect(x - 0.04, top, 0.08, 1.9), cornerRadius: cell * 0.04), with: .color(palette.pole))
        context.fill(Path(ellipseIn: rect(x - 0.09, top - 0.1, 0.18, 0.18)), with: .color(palette.cloth))
        let wave = calm ? 0 : sin(time * 4) * 0.1
        var cloth = Path()
        cloth.move(to: point(x + 0.04, top + 0.05))
        cloth.addQuadCurve(to: point(x + 0.95, top + 0.32 + wave), control: point(x + 0.5, top + 0.05 + wave))
        cloth.addQuadCurve(to: point(x + 0.04, top + 0.68), control: point(x + 0.5, top + 0.6 - wave))
        cloth.closeSubpath()
        context.fill(cloth, with: .color(palette.cloth))
    }

    // MARK: - Ropes

    private func ropes(_ context: inout GraphicsContext) {
        for first in 0..<(world.team - 1) {
            let a = world.pals[first], b = world.pals[first + 1]
            guard a.active, b.active else { continue }
            let distance = world.ropeLength(first, first + 1)
            let slack = max(0, TetherPalsRules.rope - distance)
            let sag = slack * 0.45
            let mid = point((a.centreX + b.centreX) / 2, (a.centreY + b.centreY) / 2 + sag)
            var line = Path()
            line.move(to: point(a.centreX, a.centreY + 0.1))
            line.addQuadCurve(to: point(b.centreX, b.centreY + 0.1), control: mid)
            context.stroke(line, with: .color(palette.rope), style: StrokeStyle(lineWidth: max(2, cell * 0.11), lineCap: .round))
            context.stroke(line, with: .color(Color.white.opacity(0.35)),
                           style: StrokeStyle(lineWidth: max(1, cell * 0.04), lineCap: .round, dash: [cell * 0.14, cell * 0.14]))
        }
    }

    // MARK: - Pals

    private func pal(_ context: inout GraphicsContext, _ index: Int) {
        let pal = world.pals[index]
        guard pal.active else { return }
        let stretch = calm ? 0 : max(-0.12, min(0.12, abs(pal.vy) / 90))
        let w = pal.size * (1 - stretch), h = pal.size * (1 + stretch)
        let x = pal.centreX - w / 2, y = pal.bottom - h
        let body = rect(x, y, w, h)
        let colour = TetherPalsPalette.pal(index)
        let deep = TetherPalsPalette.palDeep(index)
        // Feet first, under the body.
        let moving = pal.support.standing && abs(pal.vx) > 0.1 && !calm
        let step = moving ? sin(pal.x * 9) * 0.06 : 0
        for side in [-1.0, 1.0] {
            let fx = pal.centreX + side * 0.2 - 0.12 + (side < 0 ? step : -step)
            context.fill(Path(ellipseIn: rect(fx, pal.bottom - 0.1, 0.24, 0.13)), with: .color(deep))
        }
        context.fill(Path(roundedRect: body, cornerRadius: CGFloat(w * 0.42) * cell), with: .color(colour))
        context.stroke(Path(roundedRect: body, cornerRadius: CGFloat(w * 0.42) * cell), with: .color(deep), lineWidth: max(1, cell * 0.05))
        context.fill(Path(ellipseIn: rect(x + w * 0.16, y + h * 0.1, w * 0.3, h * 0.2)), with: .color(Color.white.opacity(0.4)))
        face(&context, pal: pal, index: index, top: y, height: h)
        if world.home.indices.contains(index), world.home[index] { star(&context, x: pal.centreX, y: y - 0.3, size: 0.22) }
        if marked == index { marker(&context, pal: pal, top: y) }
    }

    private func face(_ context: inout GraphicsContext, pal: TetherPalsPal, index: Int, top: Double, height: Double) {
        let look = Double(pal.facing) * 0.06
        let blink = !calm && (time + Double(index) * 1.3).truncatingRemainder(dividingBy: 4) < 0.12
        let eyeH = blink ? 0.04 : 0.2
        for side in [-1.0, 1.0] {
            let ex = pal.centreX + side * 0.15 + look
            context.fill(Path(ellipseIn: rect(ex - 0.08, top + height * 0.38 - eyeH / 2, 0.16, eyeH)), with: .color(.white))
            if !blink {
                context.fill(Path(ellipseIn: rect(ex - 0.045 + look * 0.4, top + height * 0.38 - 0.04, 0.09, 0.1)),
                             with: .color(TetherPalsPalette.ink))
            }
        }
        let mx = pal.centreX + look, my = top + height * 0.66
        if pal.support.standing {
            var smile = Path()
            let wide = world.home.indices.contains(index) && world.home[index] ? 0.14 : 0.09
            smile.move(to: point(mx - wide, my))
            smile.addQuadCurve(to: point(mx + wide, my), control: point(mx, my + 0.1))
            context.stroke(smile, with: .color(TetherPalsPalette.ink), style: StrokeStyle(lineWidth: max(1, cell * 0.045), lineCap: .round))
        } else {
            context.fill(Path(ellipseIn: rect(mx - 0.05, my - 0.03, 0.1, 0.11)), with: .color(TetherPalsPalette.ink))
        }
        for side in [-1.0, 1.0] {
            context.fill(Path(ellipseIn: rect(pal.centreX + side * 0.27 - 0.06, my - 0.08, 0.12, 0.07)),
                         with: .color(Color(red: 1, green: 0.45, blue: 0.55).opacity(0.45)))
        }
    }

    /// The pointer over the pal the buttons drive (solo).
    private func marker(_ context: inout GraphicsContext, pal: TetherPalsPal, top: Double) {
        let since = time - swappedAt
        let hop = calm ? 0 : (since < 0.4 ? sin(since / 0.4 * Double.pi) * 0.25 : sin(time * 3) * 0.05)
        let y = top - 0.42 - hop
        var arrow = Path()
        arrow.move(to: point(pal.centreX - 0.17, y))
        arrow.addLine(to: point(pal.centreX + 0.17, y))
        arrow.addLine(to: point(pal.centreX, y + 0.22))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(.white))
        context.stroke(arrow, with: .color(TetherPalsPalette.ink), lineWidth: max(1, cell * 0.05))
    }

    private func star(_ context: inout GraphicsContext, x: Double, y: Double, size: Double) {
        var path = Path()
        for i in 0..<10 {
            let r = i % 2 == 0 ? size : size * 0.45
            let angle = -Double.pi / 2 + Double(i) * Double.pi / 5
            let p = point(x + cos(angle) * r, y + sin(angle) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        context.fill(path, with: .color(Color(red: 1, green: 0.85, blue: 0.3)))
        context.stroke(path, with: .color(Color(red: 0.85, green: 0.6, blue: 0.1)), lineWidth: max(1, cell * 0.03))
    }

    // MARK: - Sparks

    private func drawSparks(_ context: inout GraphicsContext) {
        for spark in sparks {
            let age = time - spark.born
            guard age >= 0, age <= spark.life else { continue }
            let fade = 1 - age / spark.life
            let fall = spark.kind == .confetti || spark.kind == .dust ? 9.0 : 2.0
            let x = spark.x + spark.vx * age
            let y = spark.y + spark.vy * age + 0.5 * fall * age * age
            let r = spark.size * (spark.kind == .poof ? 1 + age * 1.5 : 1)
            let colour: Color
            switch spark.kind {
            case .dust: colour = palette.soilDot
            case .poof: colour = TetherPalsPalette.pal(Int(spark.tint))
            case .boost: colour = Color(red: 1, green: 0.85, blue: 0.3)
            case .star: colour = Color.white
            case .confetti: colour = Color(hue: spark.tint, saturation: 0.6, brightness: 1)
            }
            if spark.kind == .star || spark.kind == .boost {
                star(&context, x: x, y: y, size: r * 1.4 * fade + 0.02)
            } else {
                context.fill(Path(ellipseIn: rect(x - r, y - r, r * 2, r * 2)), with: .color(colour.opacity(fade)))
            }
        }
    }
}

/// The level on the board, redrawn on each beat of the session's clock.
struct TetherPalsBoardView: View {
    @ObservedObject var clock: TetherPalsClock
    let session: TetherPalsSession
    let dark: Bool
    let calm: Bool

    var body: some View {
        let now = clock.now
        return Canvas(rendersAsynchronously: false) { context, size in
            let cell = min(size.width / CGFloat(session.level.columns), size.height / CGFloat(session.level.rows))
            let painter = TetherPalsPainter(world: session.world, sparks: calm ? [] : session.sparks, time: now,
                                            marked: session.markedPal, swappedAt: session.swappedAt,
                                            palette: TetherPalsPalette.of(dark: dark), calm: calm, cell: cell)
            painter.draw(&context, size: size)
        }
    }
}
