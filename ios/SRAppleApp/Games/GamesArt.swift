import SwiftUI

// The pictures the Games page and every room share: a game's badge (its
// icon on its shelf's colour), the motif drawn behind a tile, the backdrop a
// tile and the hero card are painted on, the medals of a final table, and the
// confetti thrown over a win. Drawn, not assets: SwiftUI shapes, SF Symbols
// and one `Canvas` each, all static except the confetti — which runs for under
// three seconds and then stops drawing altogether.

/// A game's colour and mark, by the wire's id.
enum GamesArt {
    /// Its shelf's colour: every game on a shelf shares one, as Home's tiles do.
    static func hue(_ game: String) -> SR.Hue { GameCategory.of(game).hue }

    static func icon(_ game: String) -> String {
        GameKind(rawValue: game)?.icon ?? "gamecontroller.fill"
    }
}

/// A game's icon on a rounded square of its colour — beside a room, an
/// invitation, a leaderboard's board, a lobby's header.
struct GameArtBadge: View {
    let game: String
    var side: CGFloat = 44

    var body: some View {
        TileArtBadge(symbol: GamesArt.icon(game), hue: GamesArt.hue(game), side: side)
    }
}

/// A mark on a rounded square of its hue, with a sheen: a game's badge, and
/// the logo on a More door.
struct TileArtBadge: View {
    let symbol: String
    let hue: SR.Hue
    var side: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: side * 0.42, weight: .bold))
            .foregroundStyle(hue.onFill)
            .frame(width: side, height: side)
            .background {
                ZStack {
                    shape.fill(hue.gradient)
                    shape.fill(RadialGradient(colors: [Color.white.opacity(0.32), Color.clear],
                                              center: .topLeading, startRadius: 0, endRadius: side))
                }
            }
            .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .shadow(color: hue.base.opacity(0.25), radius: 6, y: 3)
            .accessibilityHidden(true)
    }
}

/// What a tile, the hero card and a lobby's header are painted on: the
/// shelf's gradient, a sheen, the game's motif and its icon, large and faint.
struct GamesTileBackdrop: View {
    let game: String
    let hue: SR.Hue
    /// The faint icon's size: a tile's, or the hero card's bigger one.
    var symbolSide: CGFloat = 84

    var body: some View {
        TileArtBackdrop(motif: GamesTileMotif.of(game), hue: hue, symbol: GamesArt.icon(game), symbolSide: symbolSide)
    }
}

/// The same picture for anything, not only a game: a hue's gradient, a sheen
/// top-left, a motif, and a symbol large, faint and tilted at the trailing
/// edge. The Games page's tiles and the More page's doors are both painted on
/// it, so the two pages read as one family.
struct TileArtBackdrop: View {
    let motif: GamesTileMotif
    let hue: SR.Hue
    let symbol: String
    var symbolSide: CGFloat = 84

    var body: some View {
        ZStack(alignment: .trailing) {
            hue.gradient
            // A sheen top-left: the gradient alone reads as flat paint.
            RadialGradient(colors: [Color.white.opacity(0.28), Color.clear],
                           center: .topLeading, startRadius: 0, endRadius: 220)
            GamesTileMotifView(motif: motif, tint: hue.onFill)
            Image(systemName: symbol)
                .font(.system(size: symbolSide, weight: .bold))
                .foregroundStyle(hue.onFill.opacity(0.17))
                .rotationEffect(.degrees(-12))
                .offset(x: symbolSide * 0.22, y: -symbolSide * 0.08)
        }
        .accessibilityHidden(true)
    }
}

/// One game's motif, drawn once in a `Canvas` at a low strength of the
/// tile's type colour. Static: it redraws only when the tile's size does.
struct GamesTileMotifView: View {
    let motif: GamesTileMotif
    var tint: Color = .white

    var body: some View {
        Canvas { context, size in
            GamesTileMotifView.draw(motif, context: context, size: size, tint: tint)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func draw(_ motif: GamesTileMotif, context: GraphicsContext, size: CGSize, tint: Color) {
        let w = size.width
        let h = size.height
        guard w > 1, h > 1 else { return }
        let unit = min(w, h)
        switch motif {
        case .grid: grid(context, w: w, h: h, unit: unit, tint: tint)
        case .checker: checker(context, w: w, h: h, unit: unit, tint: tint)
        case .rings: rings(context, w: w, h: h, unit: unit, tint: tint)
        case .track: track(context, w: w, h: h, unit: unit, tint: tint)
        case .sparkles: sparkles(context, w: w, h: h, unit: unit, tint: tint)
        case .cards: cards(context, w: w, h: h, unit: unit, tint: tint)
        case .dice: dice(context, w: w, h: h, unit: unit, tint: tint)
        case .bubbles: bubbles(context, w: w, h: h, unit: unit, tint: tint)
        case .maze: maze(context, w: w, h: h, unit: unit, tint: tint)
        case .blocks: blocks(context, w: w, h: h, unit: unit, tint: tint)
        case .snake: snake(context, w: w, h: h, unit: unit, tint: tint)
        case .hills: hills(context, w: w, h: h, unit: unit, tint: tint)
        case .map: contours(context, w: w, h: h, unit: unit, tint: tint)
        case .scribble: scribble(context, w: w, h: h, unit: unit, tint: tint)
        case .dots: dots(context, w: w, h: h, unit: unit, tint: tint)
        case .lines: lines(context, w: w, h: h, unit: unit, tint: tint)
        case .waveform: waveform(context, w: w, h: h, unit: unit, tint: tint)
        case .sliders: sliders(context, w: w, h: h, unit: unit, tint: tint)
        case .checks: checks(context, w: w, h: h, unit: unit, tint: tint)
        case .hexes: hexes(context, w: w, h: h, unit: unit, tint: tint)
        case .nodes: nodes(context, w: w, h: h, unit: unit, tint: tint)
        case .arc: arc(context, w: w, h: h, unit: unit, tint: tint)
        }
    }

    // MARK: The motifs

    private static func grid(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        let cell = unit * 0.15
        let gap = cell * 0.24
        let x0 = w * 0.5
        let y0 = h * 0.16
        for row in 0..<4 {
            for col in 0..<4 {
                let rect = CGRect(x: x0 + CGFloat(col) * (cell + gap), y: y0 + CGFloat(row) * (cell + gap),
                                  width: cell, height: cell)
                let strong = (row * 3 + col * 2) % 5 == 0
                c.fill(Path(roundedRect: rect, cornerRadius: cell * 0.24), with: .color(tint.opacity(strong ? 0.3 : 0.12)))
            }
        }
    }

    private static func checker(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        let cell = unit * 0.13
        let x0 = w * 0.5
        let y0 = h * 0.22
        for row in 0..<7 {
            for col in 0..<7 where (row + col) % 2 == 0 {
                let rect = CGRect(x: x0 + CGFloat(col) * cell, y: y0 + CGFloat(row) * cell, width: cell, height: cell)
                c.fill(Path(rect), with: .color(tint.opacity(0.15)))
            }
        }
    }

    private static func rings(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        let centre = CGPoint(x: w * 0.86, y: h * 0.36)
        for index in 1...4 {
            let r = unit * 0.14 * CGFloat(index)
            let rect = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)
            c.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.26 - Double(index) * 0.04)), lineWidth: unit * 0.035)
        }
        let dot = unit * 0.06
        c.fill(Path(ellipseIn: CGRect(x: centre.x - dot, y: centre.y - dot, width: dot * 2, height: dot * 2)),
               with: .color(tint.opacity(0.3)))
    }

    private static func track(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        var path = Path()
        path.move(to: CGPoint(x: w * 0.2, y: h * 1.05))
        path.addCurve(to: CGPoint(x: w * 1.05, y: h * 0.2),
                      control1: CGPoint(x: w * 0.95, y: h * 1.0),
                      control2: CGPoint(x: w * 0.4, y: h * 0.25))
        c.stroke(path, with: .color(tint.opacity(0.16)), style: StrokeStyle(lineWidth: unit * 0.17, lineCap: .round))
        c.stroke(path, with: .color(tint.opacity(0.4)),
                 style: StrokeStyle(lineWidth: unit * 0.02, lineCap: .round, dash: [unit * 0.05, unit * 0.05]))
    }

    private static func sparkles(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        let bursts: [(CGFloat, CGFloat, CGFloat)] = [(0.78, 0.3, 0.2), (0.6, 0.62, 0.12), (0.92, 0.72, 0.14)]
        for burst in bursts {
            let centre = CGPoint(x: w * burst.0, y: h * burst.1)
            let reach = unit * burst.2
            var rays = Path()
            for index in 0..<8 {
                let angle = Double(index) * Double.pi / 4
                let dx = CGFloat(cos(angle))
                let dy = CGFloat(sin(angle))
                rays.move(to: CGPoint(x: centre.x + dx * reach * 0.35, y: centre.y + dy * reach * 0.35))
                rays.addLine(to: CGPoint(x: centre.x + dx * reach, y: centre.y + dy * reach))
            }
            c.stroke(rays, with: .color(tint.opacity(0.3)), style: StrokeStyle(lineWidth: unit * 0.025, lineCap: .round))
        }
    }

    private static func cards(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        let cw = unit * 0.32
        let ch = unit * 0.44
        let angles: [Double] = [-22, -4, 14]
        for angle in angles {
            var card = c
            card.translateBy(x: w * 0.8, y: h * 1.0)
            card.rotate(by: .degrees(angle))
            let rect = CGRect(x: -cw / 2, y: -ch * 1.25, width: cw, height: ch)
            let shape = Path(roundedRect: rect, cornerRadius: cw * 0.14)
            card.fill(shape, with: .color(tint.opacity(0.13)))
            card.stroke(shape, with: .color(tint.opacity(0.34)), lineWidth: unit * 0.015)
        }
    }

    private static func dice(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        let side = unit * 0.32
        let faces: [(CGFloat, CGFloat, Double, [CGPoint])] = [
            (0.62, 0.34, -12, [CGPoint(x: 0.25, y: 0.25), CGPoint(x: 0.75, y: 0.25), CGPoint(x: 0.5, y: 0.5),
                                CGPoint(x: 0.25, y: 0.75), CGPoint(x: 0.75, y: 0.75)]),
            (0.86, 0.66, 16, [CGPoint(x: 0.25, y: 0.25), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.75, y: 0.75)]),
        ]
        for face in faces {
            var die = c
            die.translateBy(x: w * face.0, y: h * face.1)
            die.rotate(by: .degrees(face.2))
            let rect = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
            die.fill(Path(roundedRect: rect, cornerRadius: side * 0.22), with: .color(tint.opacity(0.16)))
            let pip = side * 0.1
            for spot in face.3 {
                let p = CGRect(x: rect.minX + spot.x * side - pip, y: rect.minY + spot.y * side - pip, width: pip * 2, height: pip * 2)
                die.fill(Path(ellipseIn: p), with: .color(tint.opacity(0.4)))
            }
        }
    }

    private static func bubbles(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        let big = CGRect(x: w * 0.5, y: h * 0.18, width: unit * 0.46, height: unit * 0.28)
        var first = Path(roundedRect: big, cornerRadius: unit * 0.1)
        first.move(to: CGPoint(x: big.minX + big.width * 0.2, y: big.maxY - 1))
        first.addLine(to: CGPoint(x: big.minX + big.width * 0.12, y: big.maxY + unit * 0.09))
        first.addLine(to: CGPoint(x: big.minX + big.width * 0.38, y: big.maxY - 1))
        c.fill(first, with: .color(tint.opacity(0.16)))
        let small = CGRect(x: w * 0.68, y: h * 0.56, width: unit * 0.34, height: unit * 0.22)
        c.fill(Path(roundedRect: small, cornerRadius: unit * 0.08), with: .color(tint.opacity(0.24)))
        let dot = unit * 0.025
        for index in 0..<3 {
            let x = small.minX + small.width * (0.3 + 0.2 * CGFloat(index))
            c.fill(Path(ellipseIn: CGRect(x: x - dot, y: small.midY - dot, width: dot * 2, height: dot * 2)),
                   with: .color(tint.opacity(0.45)))
        }
    }

    private static func maze(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        let cell = unit * 0.13
        let x0 = w * 0.46
        let y0 = h * 0.18
        var walls = Path()
        for row in 0..<6 {
            for col in 0..<6 {
                let x = x0 + CGFloat(col) * cell
                let y = y0 + CGFloat(row) * cell
                switch (row * 7 + col * 3) % 4 {
                case 0:
                    walls.move(to: CGPoint(x: x, y: y))
                    walls.addLine(to: CGPoint(x: x + cell, y: y))
                case 1:
                    walls.move(to: CGPoint(x: x, y: y))
                    walls.addLine(to: CGPoint(x: x, y: y + cell))
                default:
                    break
                }
            }
        }
        c.stroke(walls, with: .color(tint.opacity(0.3)), style: StrokeStyle(lineWidth: unit * 0.025, lineCap: .round))
        let ball = cell * 0.32
        let centre = CGPoint(x: x0 + cell * 2.5, y: y0 + cell * 3.5)
        c.fill(Path(ellipseIn: CGRect(x: centre.x - ball, y: centre.y - ball, width: ball * 2, height: ball * 2)),
               with: .color(tint.opacity(0.45)))
    }

    private static func blocks(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        let cell = unit * 0.19
        let gap = cell * 0.18
        let x0 = w * 0.48
        let y0 = h * 0.2
        let strengths: [Double] = [0.1, 0.2, 0.34, 0.14, 0.28, 0.1, 0.22, 0.12, 0.3]
        for index in 0..<9 {
            let row = index / 3
            let col = index % 3
            let rect = CGRect(x: x0 + CGFloat(col) * (cell + gap), y: y0 + CGFloat(row) * (cell + gap), width: cell, height: cell)
            c.fill(Path(roundedRect: rect, cornerRadius: cell * 0.2), with: .color(tint.opacity(strengths[index])))
        }
    }

    private static func snake(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        var trail = Path()
        trail.move(to: CGPoint(x: w * 0.5, y: h * 0.88))
        trail.addLine(to: CGPoint(x: w * 0.5, y: h * 0.62))
        trail.addLine(to: CGPoint(x: w * 0.72, y: h * 0.62))
        trail.addLine(to: CGPoint(x: w * 0.72, y: h * 0.38))
        trail.addLine(to: CGPoint(x: w * 0.92, y: h * 0.38))
        c.stroke(trail, with: .color(tint.opacity(0.24)),
                 style: StrokeStyle(lineWidth: unit * 0.1, lineCap: .round, lineJoin: .round))
        let apple = unit * 0.05
        let spot = CGPoint(x: w * 0.92, y: h * 0.18)
        c.fill(Path(ellipseIn: CGRect(x: spot.x - apple, y: spot.y - apple, width: apple * 2, height: apple * 2)),
               with: .color(tint.opacity(0.42)))
    }

    private static func hills(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        var back = Path()
        back.move(to: CGPoint(x: w * 0.3, y: h))
        back.addQuadCurve(to: CGPoint(x: w * 1.1, y: h * 0.6), control: CGPoint(x: w * 0.7, y: h * 0.28))
        back.addLine(to: CGPoint(x: w * 1.1, y: h))
        back.closeSubpath()
        c.fill(back, with: .color(tint.opacity(0.12)))
        var front = Path()
        front.move(to: CGPoint(x: w * 0.45, y: h))
        front.addQuadCurve(to: CGPoint(x: w * 1.1, y: h * 0.8), control: CGPoint(x: w * 0.82, y: h * 0.56))
        front.addLine(to: CGPoint(x: w * 1.1, y: h))
        front.closeSubpath()
        c.fill(front, with: .color(tint.opacity(0.16)))
        // A flag on the far hill.
        let foot = CGPoint(x: w * 0.72, y: h * 0.46)
        var pole = Path()
        pole.move(to: foot)
        pole.addLine(to: CGPoint(x: foot.x, y: foot.y - unit * 0.24))
        c.stroke(pole, with: .color(tint.opacity(0.4)), lineWidth: unit * 0.018)
        var flag = Path()
        flag.move(to: CGPoint(x: foot.x, y: foot.y - unit * 0.24))
        flag.addLine(to: CGPoint(x: foot.x + unit * 0.13, y: foot.y - unit * 0.19))
        flag.addLine(to: CGPoint(x: foot.x, y: foot.y - unit * 0.14))
        flag.closeSubpath()
        c.fill(flag, with: .color(tint.opacity(0.4)))
    }

    private static func contours(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        let centre = CGPoint(x: w * 0.8, y: h * 0.5)
        for index in 1...4 {
            let rx = unit * 0.12 * CGFloat(index)
            let ry = rx * 0.72
            let rect = CGRect(x: centre.x - rx + CGFloat(index) * unit * 0.02, y: centre.y - ry, width: rx * 2, height: ry * 2)
            c.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.2)), lineWidth: unit * 0.016)
        }
        // The pin.
        let head = unit * 0.07
        let pin = CGPoint(x: centre.x - unit * 0.02, y: centre.y - unit * 0.1)
        var drop = Path()
        drop.addEllipse(in: CGRect(x: pin.x - head, y: pin.y - head, width: head * 2, height: head * 2))
        drop.move(to: CGPoint(x: pin.x - head * 0.7, y: pin.y + head * 0.6))
        drop.addLine(to: CGPoint(x: pin.x, y: pin.y + head * 2.1))
        drop.addLine(to: CGPoint(x: pin.x + head * 0.7, y: pin.y + head * 0.6))
        drop.closeSubpath()
        c.fill(drop, with: .color(tint.opacity(0.42)))
    }

    private static func scribble(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        var line = Path()
        line.move(to: CGPoint(x: w * 0.5, y: h * 0.7))
        line.addCurve(to: CGPoint(x: w * 0.78, y: h * 0.3), control1: CGPoint(x: w * 0.45, y: h * 0.2),
                      control2: CGPoint(x: w * 0.7, y: h * 0.1))
        line.addCurve(to: CGPoint(x: w * 0.7, y: h * 0.75), control1: CGPoint(x: w * 0.9, y: h * 0.5),
                      control2: CGPoint(x: w * 0.6, y: h * 0.6))
        line.addCurve(to: CGPoint(x: w * 1.02, y: h * 0.6), control1: CGPoint(x: w * 0.8, y: h * 0.95),
                      control2: CGPoint(x: w * 0.95, y: h * 0.8))
        c.stroke(line, with: .color(tint.opacity(0.34)),
                 style: StrokeStyle(lineWidth: unit * 0.03, lineCap: .round, lineJoin: .round))
    }

    private static func dots(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        let spots: [(CGFloat, CGFloat, CGFloat, Double)] = [
            (0.7, 0.24, 0.07, 0.24), (0.88, 0.4, 0.11, 0.14), (0.6, 0.52, 0.05, 0.3),
            (0.8, 0.7, 0.08, 0.2), (0.95, 0.88, 0.06, 0.26), (0.66, 0.84, 0.04, 0.32),
        ]
        for spot in spots {
            let r = unit * spot.2
            let rect = CGRect(x: w * spot.0 - r, y: h * spot.1 - r, width: r * 2, height: r * 2)
            c.fill(Path(ellipseIn: rect), with: .color(tint.opacity(spot.3)))
        }
    }

    // MARK: The More page's motifs

    private static func lines(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        // A headline, then the column under it: short and long lines, as type falls.
        let x0 = w * 0.5
        let span = w * 0.44
        let bar = unit * 0.07
        let head = CGRect(x: x0, y: h * 0.18, width: span, height: bar * 1.6)
        c.fill(Path(roundedRect: head, cornerRadius: bar * 0.8), with: .color(tint.opacity(0.3)))
        let widths: [CGFloat] = [0.92, 0.7, 0.85, 0.55, 0.78]
        for (index, width) in widths.enumerated() {
            let y = head.maxY + bar * 1.2 + CGFloat(index) * bar * 1.9
            guard y + bar < h * 0.96 else { break }
            let rect = CGRect(x: x0, y: y, width: span * width, height: bar)
            c.fill(Path(roundedRect: rect, cornerRadius: bar / 2), with: .color(tint.opacity(index == 0 ? 0.22 : 0.14)))
        }
    }

    private static func waveform(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        // A recording's bars, loudest in the middle, across the trailing half.
        let heights: [CGFloat] = [0.18, 0.4, 0.66, 0.9, 0.56, 0.98, 0.72, 0.44, 0.62, 0.3, 0.16]
        let x0 = w * 0.42
        let step = (w * 0.56) / CGFloat(heights.count)
        let reach = min(unit * 0.62, h * 0.8)
        var bars = Path()
        for (index, height) in heights.enumerated() {
            let x = x0 + step * (CGFloat(index) + 0.5)
            let half = reach * height / 2
            bars.move(to: CGPoint(x: x, y: h * 0.5 - half))
            bars.addLine(to: CGPoint(x: x, y: h * 0.5 + half))
        }
        c.stroke(bars, with: .color(tint.opacity(0.28)), style: StrokeStyle(lineWidth: step * 0.5, lineCap: .round))
    }

    private static func sliders(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        // Three sliders, each knob somewhere else on its track.
        let x0 = w * 0.5
        let x1 = w * 0.94
        let knobs: [CGFloat] = [0.3, 0.78, 0.52]
        let knob = unit * 0.065
        for (index, at) in knobs.enumerated() {
            let y = h * (0.28 + 0.22 * CGFloat(index))
            var track = Path()
            track.move(to: CGPoint(x: x0, y: y))
            track.addLine(to: CGPoint(x: x1, y: y))
            c.stroke(track, with: .color(tint.opacity(0.18)), style: StrokeStyle(lineWidth: unit * 0.03, lineCap: .round))
            var lit = Path()
            let kx = x0 + (x1 - x0) * at
            lit.move(to: CGPoint(x: x0, y: y))
            lit.addLine(to: CGPoint(x: kx, y: y))
            c.stroke(lit, with: .color(tint.opacity(0.32)), style: StrokeStyle(lineWidth: unit * 0.03, lineCap: .round))
            c.fill(Path(ellipseIn: CGRect(x: kx - knob, y: y - knob, width: knob * 2, height: knob * 2)),
                   with: .color(tint.opacity(0.42)))
        }
    }

    private static func checks(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        // A list: two jobs ticked, one still to do.
        let box = unit * 0.14
        let x0 = w * 0.52
        for row in 0..<3 {
            let y = h * 0.2 + CGFloat(row) * box * 1.7
            guard y + box < h * 0.98 else { break }
            let rect = CGRect(x: x0, y: y, width: box, height: box)
            let shape = Path(roundedRect: rect, cornerRadius: box * 0.28)
            c.stroke(shape, with: .color(tint.opacity(0.34)), lineWidth: unit * 0.018)
            if row < 2 {
                c.fill(shape, with: .color(tint.opacity(0.14)))
                var tick = Path()
                tick.move(to: CGPoint(x: rect.minX + box * 0.22, y: rect.midY))
                tick.addLine(to: CGPoint(x: rect.minX + box * 0.44, y: rect.maxY - box * 0.24))
                tick.addLine(to: CGPoint(x: rect.maxX - box * 0.2, y: rect.minY + box * 0.24))
                c.stroke(tick, with: .color(tint.opacity(0.46)),
                         style: StrokeStyle(lineWidth: unit * 0.022, lineCap: .round, lineJoin: .round))
            }
            let line = CGRect(x: rect.maxX + box * 0.4, y: rect.midY - box * 0.16, width: w * 0.94 - rect.maxX - box * 0.4,
                              height: box * 0.32)
            c.fill(Path(roundedRect: line, cornerRadius: box * 0.16), with: .color(tint.opacity(0.16)))
        }
    }

    private static func hexes(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        // A patch of claimed ground: hexagons, some taken more strongly.
        let r = unit * 0.1
        let dx = r * sqrt(3)
        let dy = r * 1.5
        let x0 = w * 0.56
        let y0 = h * 0.24
        let strengths: [Double] = [0.12, 0.3, 0.16, 0.22, 0.12, 0.34, 0.14, 0.2, 0.26]
        for index in 0..<9 {
            let row = index / 3
            let col = index % 3
            let centre = CGPoint(x: x0 + CGFloat(col) * dx + (row % 2 == 1 ? dx / 2 : 0), y: y0 + CGFloat(row) * dy)
            var hex = Path()
            for corner in 0..<6 {
                let angle = Double(corner) * Double.pi / 3 - Double.pi / 2
                let point = CGPoint(x: centre.x + r * 0.92 * CGFloat(cos(angle)), y: centre.y + r * 0.92 * CGFloat(sin(angle)))
                if corner == 0 { hex.move(to: point) } else { hex.addLine(to: point) }
            }
            hex.closeSubpath()
            c.fill(hex, with: .color(tint.opacity(strengths[index])))
        }
    }

    private static func nodes(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        // A small workflow: steps joined one to the next, one branching.
        let points: [CGPoint] = [
            CGPoint(x: w * 0.56, y: h * 0.26), CGPoint(x: w * 0.82, y: h * 0.2), CGPoint(x: w * 0.7, y: h * 0.52),
            CGPoint(x: w * 0.93, y: h * 0.64), CGPoint(x: w * 0.6, y: h * 0.8),
        ]
        let edges = [(0, 1), (0, 2), (1, 2), (2, 3), (2, 4)]
        var links = Path()
        for edge in edges {
            links.move(to: points[edge.0])
            links.addLine(to: points[edge.1])
        }
        c.stroke(links, with: .color(tint.opacity(0.24)), style: StrokeStyle(lineWidth: unit * 0.022, lineCap: .round))
        for (index, point) in points.enumerated() {
            let r = unit * (index == 2 ? 0.075 : 0.05)
            c.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                   with: .color(tint.opacity(index == 2 ? 0.4 : 0.3)))
        }
    }

    private static func arc(_ c: GraphicsContext, w: CGFloat, h: CGFloat, unit: CGFloat, tint: Color) {
        // A flight's dashed arc from here to there, a ring at each end.
        let from = CGPoint(x: w * 0.48, y: h * 0.82)
        let to = CGPoint(x: w * 0.92, y: h * 0.3)
        var path = Path()
        path.move(to: from)
        path.addQuadCurve(to: to, control: CGPoint(x: w * 0.56, y: h * 0.12))
        c.stroke(path, with: .color(tint.opacity(0.36)),
                 style: StrokeStyle(lineWidth: unit * 0.022, lineCap: .round, dash: [unit * 0.05, unit * 0.045]))
        for (point, r) in [(from, unit * 0.045), (to, unit * 0.07)] {
            c.stroke(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                     with: .color(tint.opacity(0.4)), lineWidth: unit * 0.022)
        }
        let dot = unit * 0.03
        c.fill(Path(ellipseIn: CGRect(x: to.x - dot, y: to.y - dot, width: dot * 2, height: dot * 2)), with: .color(tint.opacity(0.46)))
    }
}

// MARK: - Medals

/// A place in a final table or on a leaderboard: gold, silver and bronze
/// discs for the first three, a plain figure after them.
struct GameMedal: View {
    let place: Int
    var side: CGFloat = 32
    /// Scales with the text beside it, so the disc never crops its figure.
    @ScaledMetric(relativeTo: .headline) private var scale: CGFloat = 1

    var body: some View {
        let size = side * scale
        if let colours = Self.colours(place) {
            Text("\(place)")
                .font(SR.Text.figure(side * 0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // Fixed dark type: the discs are the same metal in both modes.
                .foregroundStyle(Color(hex: 0x2A2340))
                .frame(width: size, height: size)
                .background(Circle().fill(LinearGradient(colors: colours, startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
                .shadow(color: colours[1].opacity(0.45), radius: 4, y: 2)
                .accessibilityLabel(Self.spoken(place))
        } else {
            Text("\(place)")
                .font(SR.Text.figure(side * 0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(SR.inkMuted)
                .frame(width: size, height: size)
                .accessibilityLabel(Self.spoken(place))
        }
    }

    /// The disc's two stops for a podium place; nil after third.
    static func colours(_ place: Int) -> [Color]? {
        switch place {
        case 1: return [Color(hex: 0xFFE07A), Color(hex: 0xE9A800)]
        case 2: return [Color(hex: 0xF1F4F8), Color(hex: 0xAEB8C6)]
        case 3: return [Color(hex: 0xF6C29A), Color(hex: 0xC97A3D)]
        default: return nil
        }
    }

    static func spoken(_ place: Int) -> String {
        switch place {
        case 1: return "First"
        case 2: return "Second"
        case 3: return "Third"
        default: return "Place \(place)"
        }
    }
}

// MARK: - Confetti

/// A burst of confetti over a win: drawn from the time alone
/// (`GameConfetti.pose`), on the display's own clock, for under three seconds
/// — then the view stops drawing for good. Nothing under Reduce Motion.
struct GameConfettiView: View {
    var seed: UInt64 = 1
    var count: Int = 70

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var pieces: [GameConfettiPiece] = []
    @State private var finished = false

    private let colours: [Color] = GameConfettiView.palette()

    var body: some View {
        Group {
            if reduceMotion || finished {
                Color.clear
            } else {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSince(start ?? timeline.date)
                        GameConfettiView.draw(pieces, colours: colours, t: t, context: context, size: size)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            if pieces.isEmpty { pieces = GameConfetti.pieces(count: count, seed: seed) }
            if start == nil { start = Date() }
        }
        .task {
            try? await Task.sleep(nanoseconds: UInt64(GameConfetti.duration * 1_000_000_000))
            finished = true
        }
    }

    static func palette() -> [Color] {
        [SR.Hue.games.glow, SR.Hue.family.glow, SR.Hue.trips.glow, SR.Hue.daydream.glow,
         SR.accent, Color(hex: 0xFFD54A)]
    }

    static func draw(_ pieces: [GameConfettiPiece], colours: [Color], t: Double,
                     context: GraphicsContext, size: CGSize) {
        guard !colours.isEmpty else { return }
        for piece in pieces {
            guard let pose = GameConfetti.pose(piece, at: t) else { continue }
            var ctx = context
            ctx.opacity = pose.opacity
            ctx.translateBy(x: CGFloat(pose.x) * size.width, y: CGFloat(pose.y) * size.height)
            ctx.rotate(by: .radians(pose.angle))
            let s = CGFloat(piece.size)
            let colour = colours[piece.colour % colours.count]
            if piece.shape == 0 {
                ctx.fill(Path(CGRect(x: -s / 2, y: -s / 4, width: s, height: s / 2)), with: .color(colour))
            } else {
                let d = s * 0.75
                ctx.fill(Path(ellipseIn: CGRect(x: -d / 2, y: -d / 2, width: d, height: d)), with: .color(colour))
            }
        }
    }
}
