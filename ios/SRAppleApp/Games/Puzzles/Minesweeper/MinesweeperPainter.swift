import SwiftUI

/// The field's colours. A lawn of two greens to dig and two sands under it,
/// in both modes; the numbers keep their classic colours, lifted for dark.
/// The play field is its own surface, like a board on a table, so it does not
/// borrow the app's tokens — but every number is measured against its sand.
struct MinesweeperPalette {
    let grout: Color
    let grassA: Color
    let grassB: Color
    let grassLight: Color
    let grassShade: Color
    let grassPressed: Color
    let soilA: Color
    let soilB: Color
    let numbers: [Color]
    let mine: Color
    let mineShine: Color
    let blast: Color
    let blastGlow: Color
    let flagCloth: Color
    let flagPole: Color
    let cross: Color
    let ring: Color
    let hint: Color
    let jewels: [Color]
    let sparks: [Color]
    let turf: [Color]
    let confetti: [Color]

    init(dark: Bool) {
        if dark {
            grout = Color(hex: 0x1B2E14)
            grassA = Color(hex: 0x4E8A2E)
            grassB = Color(hex: 0x457D28)
            grassLight = Color(hex: 0x8FD45E, alpha: 0.35)
            grassShade = Color(hex: 0x0E1A08, alpha: 0.35)
            grassPressed = Color(hex: 0x33611D)
            soilA = Color(hex: 0x3A3027)
            soilB = Color(hex: 0x332A22)
            numbers = [.clear, Color(hex: 0x7CC0FF), Color(hex: 0x8EE08E), Color(hex: 0xFF8A80), Color(hex: 0xD9A2FF),
                       Color(hex: 0xFFC266), Color(hex: 0x5EE0EA), Color(hex: 0xF2F2F2), Color(hex: 0xC8C8C8)]
            mine = Color(hex: 0x10141A)
            mineShine = Color(hex: 0xFFFFFF, alpha: 0.55)
            blast = Color(hex: 0xE0453A)
            blastGlow = Color(hex: 0xFFB199, alpha: 0.55)
            flagCloth = Color(hex: 0xFF5A4E)
            flagPole = Color(hex: 0xE8E0D6)
            cross = Color(hex: 0xFFE14D)
            ring = Color(hex: 0xFFFFFF, alpha: 0.9)
            hint = Color(hex: 0xFFFFFF, alpha: 0.5)
        } else {
            grout = Color(hex: 0x6E9F3A)
            grassA = Color(hex: 0xAAD751)
            grassB = Color(hex: 0xA2D149)
            grassLight = Color(hex: 0xFFFFFF, alpha: 0.35)
            grassShade = Color(hex: 0x3F6A16, alpha: 0.28)
            grassPressed = Color(hex: 0x8DBA3B)
            soilA = Color(hex: 0xE5C29F)
            soilB = Color(hex: 0xD7B899)
            numbers = [.clear, Color(hex: 0x1565C0), Color(hex: 0x2E7D32), Color(hex: 0xC62828), Color(hex: 0x6A1B9A),
                       Color(hex: 0xA14A00), Color(hex: 0x00727F), Color(hex: 0x263238), Color(hex: 0x5A5A5A)]
            mine = Color(hex: 0x1C2228)
            mineShine = Color(hex: 0xFFFFFF, alpha: 0.6)
            blast = Color(hex: 0xE53935)
            blastGlow = Color(hex: 0xFFCDD2, alpha: 0.6)
            flagCloth = Color(hex: 0xE53935)
            flagPole = Color(hex: 0x37474F)
            cross = Color(hex: 0x1C2228)
            ring = Color(hex: 0xFFFFFF, alpha: 0.95)
            hint = Color(hex: 0xFFFFFF, alpha: 0.55)
        }
        jewels = [Color(hex: 0xDB3236), Color(hex: 0xF4840D), Color(hex: 0xF4C20D), Color(hex: 0x48E6F1),
                  Color(hex: 0x4885ED), Color(hex: 0xB648F2)]
        sparks = [Color(hex: 0xFFD54F), Color(hex: 0xFF7043), Color(hex: 0xFFF3E0)]
        turf = dark ? [Color(hex: 0x6FB042), Color(hex: 0x4E8A2E), Color(hex: 0x8A6E52)]
            : [Color(hex: 0x8CC63F), Color(hex: 0x6E9F3A), Color(hex: 0xB08A64)]
        confetti = [Color(hex: 0xFF4D6D), Color(hex: 0xFFB703), Color(hex: 0x3A86FF), Color(hex: 0x8338EC),
                    Color(hex: 0x06D6A0), Color(hex: 0xFB5607)]
    }
}

extension MinesweeperPalette {
    /// Built once each: the field asks for its colours every frame.
    static let lightSet = MinesweeperPalette(dark: false)
    static let darkSet = MinesweeperPalette(dark: true)

    static func shared(dark: Bool) -> MinesweeperPalette { dark ? darkSet : lightSet }
}

/// Everything one frame of the field needs, captured before the Canvas runs.
struct MinesweeperScene {
    var board: MinesweeperBoard
    var fx: MinesweeperEffects
    var viewport: MinesweeperViewport
    var now: Double
    var press: MinesweeperPress?
    /// Paused: the field is covered so it cannot be studied off the clock.
    var veiled: Bool
    /// Reduce Motion: no shake, no sparks, no confetti, squares open at once.
    var calm: Bool
}

/// Draws the field into a Canvas. Squares of one kind are gathered into one
/// path and filled once, only the squares in the window are drawn, and the
/// eight number glyphs are resolved once a frame, so Expert's 480 squares at
/// 120 frames a second stay cheap.
struct MinesweeperPainter {
    let palette: MinesweeperPalette

    /// How long a held finger takes to plant a flag; the ring fills over it.
    static let holdTime = 0.35

    func draw(_ scene: MinesweeperScene, in context: inout GraphicsContext, size: CGSize) {
        let v = scene.viewport
        let cell = CGFloat(v.cell)
        guard cell > 0.5 else { return }
        var ox = CGFloat(v.offsetX)
        var oy = CGFloat(v.offsetY)
        if !scene.calm {
            let t = scene.now - scene.fx.shakeAt
            if t >= 0 && t < MinesweeperEffects.shakeTime {
                let k = 1 - t / MinesweeperEffects.shakeTime
                ox += CGFloat(sin(t * 70) * 7 * k * k)
                oy += CGFloat(cos(t * 53) * 5 * k * k)
            }
        }
        let board = scene.board
        drawFrame(board, ox: ox, oy: oy, cell: cell, in: &context)

        let c0 = max(0, Int(floor(-ox / cell)))
        let c1 = min(board.width - 1, Int(floor((size.width - ox) / cell)))
        let r0 = max(0, Int(floor(-oy / cell)))
        let r1 = min(board.height - 1, Int(floor((size.height - oy) / cell)))
        if c0 <= c1 && r0 <= r1 {
            drawCells(scene, cols: c0...c1, rows: r0...r1, ox: ox, oy: oy, cell: cell, in: &context)
        }
        if !scene.calm && !scene.veiled {
            drawParticles(scene, ox: ox, oy: oy, cell: cell, size: size, in: &context)
        }
    }

    // MARK: - The frame

    private func drawFrame(_ board: MinesweeperBoard, ox: CGFloat, oy: CGFloat, cell: CGFloat, in context: inout GraphicsContext) {
        let field = CGRect(x: ox, y: oy, width: cell * CGFloat(board.width), height: cell * CGFloat(board.height))
        let radius = max(6, min(18, cell * 0.35))
        // A soft shadow from three widening, fading rims: cheaper than a blur every frame.
        for step in 1...3 {
            let grow = CGFloat(step) * 3
            let shadow = Path(roundedRect: field.insetBy(dx: -grow, dy: -grow).offsetBy(dx: 0, dy: grow * 0.8),
                              cornerRadius: radius + grow)
            context.fill(shadow, with: .color(Color.black.opacity(0.07)))
        }
        context.fill(Path(roundedRect: field.insetBy(dx: -4, dy: -4), cornerRadius: radius), with: .color(palette.grout))
    }

    // MARK: - Squares

    private func drawCells(_ scene: MinesweeperScene, cols: ClosedRange<Int>, rows: ClosedRange<Int>,
                           ox: CGFloat, oy: CGFloat, cell: CGFloat, in context: inout GraphicsContext) {
        let board = scene.board
        let fx = scene.fx
        let now = scene.now
        let lost = board.status == .lost
        let gap = max(0.75, cell * 0.045)
        let corner = cell * 0.2
        let cornerSize = CGSize(width: corner, height: corner)

        var soilA = Path(), soilB = Path()
        var grassA = Path(), grassB = Path(), pressed = Path()
        var lights = Path(), shades = Path()
        var numbers: [Int] = []
        var uncovering: [Int] = []
        var flags: [Int] = []
        var mines: [Int] = []

        for r in rows {
            for c in cols {
                let i = r * board.width + c
                let rect = CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell, width: cell, height: cell)
                let even = (r + c) % 2 == 0
                var covered = board.cells[i] != .revealed || scene.veiled
                if !covered {
                    let p = scene.calm ? 1 : (now - fx.uncoverAt[i]) / MinesweeperEffects.uncoverTime
                    if p < 0 {
                        covered = true
                    } else {
                        if even { soilA.addRect(rect) } else { soilB.addRect(rect) }
                        if p < 1 { uncovering.append(i) }
                        if board.mines[i] {
                            mines.append(i)
                        } else if board.counts[i] > 0 {
                            numbers.append(i)
                        }
                    }
                }
                guard covered else { continue }
                let tile = rect.insetBy(dx: gap, dy: gap)
                if scene.press?.cell == i && !scene.veiled {
                    pressed.addRoundedRect(in: tile.offsetBy(dx: 0, dy: cell * 0.03), cornerSize: cornerSize)
                } else {
                    if even {
                        grassA.addRoundedRect(in: tile, cornerSize: cornerSize)
                    } else {
                        grassB.addRoundedRect(in: tile, cornerSize: cornerSize)
                    }
                    let band = max(1, tile.height * 0.16)
                    lights.addRoundedRect(in: CGRect(x: tile.minX + band * 0.6, y: tile.minY + band * 0.35,
                                                     width: tile.width - band * 1.2, height: band),
                                          cornerSize: CGSize(width: band / 2, height: band / 2))
                    shades.addRoundedRect(in: CGRect(x: tile.minX, y: tile.maxY - band, width: tile.width, height: band),
                                          cornerSize: CGSize(width: band / 2, height: band / 2))
                }
                guard !scene.veiled else { continue }
                if board.cells[i] == .flagged {
                    flags.append(i)
                } else if lost && board.mines[i] {
                    mines.append(i)
                }
            }
        }

        context.fill(soilA, with: .color(palette.soilA))
        context.fill(soilB, with: .color(palette.soilB))
        context.fill(grassA, with: .color(palette.grassA))
        context.fill(grassB, with: .color(palette.grassB))
        context.fill(shades, with: .color(palette.grassShade))
        context.fill(lights, with: .color(palette.grassLight))
        context.fill(pressed, with: .color(palette.grassPressed))

        for i in uncovering { drawUncovering(i, scene: scene, ox: ox, oy: oy, cell: cell, gap: gap, in: &context) }
        if !numbers.isEmpty { drawNumbers(numbers, scene: scene, ox: ox, oy: oy, cell: cell, in: &context) }
        for i in mines { drawMine(i, scene: scene, ox: ox, oy: oy, cell: cell, in: &context) }
        for i in flags { drawFlag(i, scene: scene, ox: ox, oy: oy, cell: cell, in: &context) }
        if !scene.veiled {
            drawHint(scene, ox: ox, oy: oy, cell: cell, in: &context)
            drawPressRing(scene, ox: ox, oy: oy, cell: cell, in: &context)
        }
    }

    private func origin(_ i: Int, _ board: MinesweeperBoard, ox: CGFloat, oy: CGFloat, cell: CGFloat) -> CGRect {
        CGRect(x: ox + CGFloat(i % board.width) * cell, y: oy + CGFloat(i / board.width) * cell, width: cell, height: cell)
    }

    /// A tile of turf lifting off and shrinking away as the square is dug.
    private func drawUncovering(_ i: Int, scene: MinesweeperScene, ox: CGFloat, oy: CGFloat, cell: CGFloat, gap: CGFloat,
                                in context: inout GraphicsContext) {
        let p = (scene.now - scene.fx.uncoverAt[i]) / MinesweeperEffects.uncoverTime
        guard p >= 0 && p < 1 else { return }
        let rect = origin(i, scene.board, ox: ox, oy: oy, cell: cell)
        let eased = CGFloat(p * p)
        let shrink = (rect.width - gap * 2) * (1 - eased)
        let lift = cell * 0.35 * CGFloat(sin(p * Double.pi * 0.5))
        let tile = CGRect(x: rect.midX - shrink / 2, y: rect.midY - shrink / 2 - lift, width: shrink, height: shrink)
        let even = (i % scene.board.width + i / scene.board.width) % 2 == 0
        let colour = even ? palette.grassA : palette.grassB
        context.fill(Path(roundedRect: tile, cornerRadius: cell * 0.2 * (1 - eased)),
                     with: .color(colour.opacity(1 - Double(eased) * 0.6)))
    }

    private func drawNumbers(_ cells: [Int], scene: MinesweeperScene, ox: CGFloat, oy: CGFloat, cell: CGFloat,
                             in context: inout GraphicsContext) {
        let font = Font.system(size: max(6, cell * 0.6), weight: .heavy, design: .rounded)
        var glyphs: [GraphicsContext.ResolvedText?] = Array(repeating: nil, count: 9)
        for i in cells {
            let n = scene.board.counts[i]
            guard n > 0 && n < 9 else { continue }
            let glyph: GraphicsContext.ResolvedText
            if let made = glyphs[n] {
                glyph = made
            } else {
                var made = context.resolve(Text("\(n)").font(font))
                made.shading = .color(palette.numbers[n])
                glyphs[n] = made
                glyph = made
            }
            let rect = origin(i, scene.board, ox: ox, oy: oy, cell: cell)
            let centre = CGPoint(x: rect.midX, y: rect.midY + cell * 0.02)
            let p = scene.calm ? 1 : (scene.now - scene.fx.uncoverAt[i]) / MinesweeperEffects.uncoverTime
            if p >= 1 {
                context.draw(glyph, at: centre, anchor: .center)
            } else if p > 0.35 {
                var faded = context
                faded.opacity = min(1, (p - 0.35) / 0.65)
                faded.draw(glyph, at: centre, anchor: .center)
            }
        }
    }

    /// The easing a pop uses: overshoots a little, then settles at 1.
    private func pop(_ t: Double) -> CGFloat {
        if t >= 1 { return 1 }
        if t <= 0 { return 0 }
        let c1 = 1.70158, c3 = c1 + 1
        let u = t - 1
        return CGFloat(1 + c3 * u * u * u + c1 * u * u)
    }

    private func drawMine(_ i: Int, scene: MinesweeperScene, ox: CGFloat, oy: CGFloat, cell: CGFloat,
                          in context: inout GraphicsContext) {
        let board = scene.board
        let at = scene.fx.rippleAt[i]
        let t = scene.calm ? 1 : (scene.now - at) / MinesweeperEffects.popTime
        let exploded = board.exploded == i
        guard exploded || t >= 0 else { return }
        let rect = origin(i, board, ox: ox, oy: oy, cell: cell)
        let s = exploded ? max(pop(t), 0.001) : pop(t)
        guard s > 0.001 else { return }
        let tile = rect.insetBy(dx: cell * 0.06, dy: cell * 0.06)
        if exploded {
            let glowT = max(0, min(1, (scene.now - at) / 0.8))
            let glow = rect.insetBy(dx: -cell * 0.5 * CGFloat(1 - glowT), dy: -cell * 0.5 * CGFloat(1 - glowT))
            context.fill(Path(ellipseIn: glow), with: .color(palette.blastGlow.opacity(1 - glowT)))
            context.fill(Path(roundedRect: tile, cornerRadius: cell * 0.18), with: .color(palette.blast))
        } else {
            let jewel = palette.jewels[i % palette.jewels.count]
            let sized = CGRect(x: tile.midX - tile.width * s / 2, y: tile.midY - tile.height * s / 2,
                               width: tile.width * s, height: tile.height * s)
            context.fill(Path(roundedRect: sized, cornerRadius: cell * 0.18 * s), with: .color(jewel))
        }
        drawBomb(centre: CGPoint(x: rect.midX, y: rect.midY), radius: cell * 0.22 * s, in: &context)
    }

    private func drawBomb(centre: CGPoint, radius: CGFloat, in context: inout GraphicsContext) {
        var spikes = Path()
        let reach = radius * 1.45
        for k in 0..<4 {
            let a = Double(k) * Double.pi / 4
            let dx = CGFloat(cos(a)) * reach, dy = CGFloat(sin(a)) * reach
            spikes.move(to: CGPoint(x: centre.x - dx, y: centre.y - dy))
            spikes.addLine(to: CGPoint(x: centre.x + dx, y: centre.y + dy))
        }
        context.stroke(spikes, with: .color(palette.mine),
                       style: StrokeStyle(lineWidth: max(1, radius * 0.32), lineCap: .round))
        context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                     with: .color(palette.mine))
        let shine = radius * 0.38
        context.fill(Path(ellipseIn: CGRect(x: centre.x - radius * 0.5, y: centre.y - radius * 0.55, width: shine, height: shine)),
                     with: .color(palette.mineShine))
    }

    private func drawFlag(_ i: Int, scene: MinesweeperScene, ox: CGFloat, oy: CGFloat, cell: CGFloat,
                          in context: inout GraphicsContext) {
        let board = scene.board
        let planted = board.status == .won ? max(scene.fx.flagAt[i], scene.fx.rippleAt[i]) : scene.fx.flagAt[i]
        let t = scene.calm ? 1 : (scene.now - planted) / MinesweeperEffects.popTime
        let s = pop(t)
        guard s > 0.001 else { return }
        let rect = origin(i, board, ox: ox, oy: oy, cell: cell)
        // Planted from the base, so the pop grows up out of the ground.
        let baseX = rect.midX, baseY = rect.midY + cell * 0.3
        let unit = cell * s
        let poleX = baseX - unit * 0.1
        var pole = Path()
        pole.move(to: CGPoint(x: poleX, y: baseY))
        pole.addLine(to: CGPoint(x: poleX, y: baseY - unit * 0.6))
        context.stroke(pole, with: .color(palette.flagPole), style: StrokeStyle(lineWidth: max(1, unit * 0.07), lineCap: .round))
        var cloth = Path()
        cloth.move(to: CGPoint(x: poleX, y: baseY - unit * 0.62))
        cloth.addLine(to: CGPoint(x: poleX + unit * 0.38, y: baseY - unit * 0.45))
        cloth.addLine(to: CGPoint(x: poleX, y: baseY - unit * 0.27))
        cloth.closeSubpath()
        context.fill(cloth, with: .color(palette.flagCloth))
        let foot = CGRect(x: baseX - unit * 0.26, y: baseY - unit * 0.035, width: unit * 0.36, height: unit * 0.07)
        context.fill(Path(roundedRect: foot, cornerRadius: unit * 0.035), with: .color(palette.flagPole))

        // A flag on a square with no mine, crossed out once the ripple has passed.
        if board.status == .lost && !board.mines[i] && scene.now >= scene.fx.settlesAt - 1.0 {
            var cross = Path()
            let k = cell * 0.24
            cross.move(to: CGPoint(x: rect.midX - k, y: rect.midY - k))
            cross.addLine(to: CGPoint(x: rect.midX + k, y: rect.midY + k))
            cross.move(to: CGPoint(x: rect.midX + k, y: rect.midY - k))
            cross.addLine(to: CGPoint(x: rect.midX - k, y: rect.midY + k))
            context.stroke(cross, with: .color(palette.cross), style: StrokeStyle(lineWidth: max(1.5, cell * 0.08), lineCap: .round))
        }
    }

    /// The squares a number is counting blink when it is tapped without the right flags.
    private func drawHint(_ scene: MinesweeperScene, ox: CGFloat, oy: CGFloat, cell: CGFloat, in context: inout GraphicsContext) {
        let t = scene.now - scene.fx.hintAt
        guard t >= 0 && t < MinesweeperEffects.hintTime else { return }
        let strength = sin(t / MinesweeperEffects.hintTime * Double.pi * 2) * 0.5 + 0.5
        var path = Path()
        for i in scene.fx.hintCells where i >= 0 && i < scene.board.size {
            let rect = origin(i, scene.board, ox: ox, oy: oy, cell: cell).insetBy(dx: cell * 0.06, dy: cell * 0.06)
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: cell * 0.2, height: cell * 0.2))
        }
        context.fill(path, with: .color(palette.hint.opacity(strength)))
    }

    /// A ring that fills round a held square; when it closes, the flag goes in.
    private func drawPressRing(_ scene: MinesweeperScene, ox: CGFloat, oy: CGFloat, cell: CGFloat, in context: inout GraphicsContext) {
        guard let press = scene.press, press.cell >= 0, press.cell < scene.board.size,
              scene.board.cells[press.cell] != .revealed else { return }
        let t = (scene.now - press.since - 0.08) / (Self.holdTime - 0.08)
        guard t > 0 && t < 1 else { return }
        let rect = origin(press.cell, scene.board, ox: ox, oy: oy, cell: cell)
        let radius = max(cell * 0.62, 26)
        var ring = Path()
        ring.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius, startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * t), clockwise: false)
        context.stroke(ring, with: .color(Color.black.opacity(0.25)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        context.stroke(ring, with: .color(palette.ring), style: StrokeStyle(lineWidth: 4, lineCap: .round))
    }

    // MARK: - Particles

    private func drawParticles(_ scene: MinesweeperScene, ox: CGFloat, oy: CGFloat, cell: CGFloat, size: CGSize,
                               in context: inout GraphicsContext) {
        let now = scene.now
        for p in scene.fx.particles {
            let fade = p.fade(at: now)
            guard fade > 0.01 else { continue }
            let at = p.position(at: now)
            switch p.kind {
            case .turf:
                let x = ox + CGFloat(at.x) * cell, y = oy + CGFloat(at.y) * cell
                let s = CGFloat(p.size) * cell
                let rect = CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
                context.fill(Path(roundedRect: rect, cornerRadius: s * 0.3),
                             with: .color(palette.turf[p.tint % palette.turf.count].opacity(fade)))
            case .spark:
                let x = ox + CGFloat(at.x) * cell, y = oy + CGFloat(at.y) * cell
                let s = CGFloat(p.size) * cell
                context.fill(Path(ellipseIn: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)),
                             with: .color(palette.sparks[p.tint % palette.sparks.count].opacity(fade)))
            case .confetti:
                guard now >= p.born else { continue }
                let x = CGFloat(at.x) * size.width, y = CGFloat(at.y) * size.height
                let angle = p.spin * (now - p.born)
                let w = CGFloat(p.size), h = CGFloat(p.size) * 0.55 * CGFloat(abs(cos(angle * 0.7)) + 0.2)
                let ca = CGFloat(cos(angle)), sa = CGFloat(sin(angle))
                // The piece's two half-axes, turned by its spin.
                let ax: CGFloat = w / 2 * ca, ay: CGFloat = w / 2 * sa
                let bx: CGFloat = -h / 2 * sa, by: CGFloat = h / 2 * ca
                var piece = Path()
                piece.move(to: CGPoint(x: x - ax - bx, y: y - ay - by))
                piece.addLine(to: CGPoint(x: x + ax - bx, y: y + ay - by))
                piece.addLine(to: CGPoint(x: x + ax + bx, y: y + ay + by))
                piece.addLine(to: CGPoint(x: x - ax + bx, y: y - ay + by))
                piece.closeSubpath()
                context.fill(piece, with: .color(palette.confetti[p.tint % palette.confetti.count].opacity(min(1, fade * 1.6))))
            }
        }
    }
}
