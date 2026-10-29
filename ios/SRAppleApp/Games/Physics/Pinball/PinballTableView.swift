import SwiftUI

/// The table's fixed palette. A playfield is artwork, like a board: it does
/// not change with light and dark mode.
enum PinballGlow {
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.26)
    static let cyan = Color(red: 0.32, green: 0.90, blue: 1.0)
    static let magenta = Color(red: 1.0, green: 0.36, blue: 0.76)
    static let green = Color(red: 0.42, green: 1.0, blue: 0.56)
    static let red = Color(red: 1.0, green: 0.30, blue: 0.26)
    static let white = Color.white
    static let cabinet = Color(red: 0.05, green: 0.04, blue: 0.09)
    static let feltTop = Color(red: 0.13, green: 0.07, blue: 0.33)
    static let feltMiddle = Color(red: 0.06, green: 0.10, blue: 0.30)
    static let feltBottom = Color(red: 0.02, green: 0.17, blue: 0.27)
    static let chrome = Color(red: 0.80, green: 0.83, blue: 0.90)
    static let chromeDark = Color(red: 0.22, green: 0.23, blue: 0.30)
    static let rubber = Color(red: 0.97, green: 0.96, blue: 0.92)
    static let apron = Color(red: 0.10, green: 0.09, blue: 0.16)

    /// A spark's colour by its `hue`.
    static func hue(_ i: Int) -> Color {
        switch i {
        case 0: return gold
        case 1: return cyan
        case 2: return magenta
        case 3: return green
        case 5: return red
        default: return white
        }
    }
}

extension PinballVec {
    var cg: CGPoint { CGPoint(x: x, y: y) }
}

/// Paths for the table, in table units.
enum PinballPaths {
    static func line(_ points: [PinballVec], closed: Bool = false) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first.cg)
        for point in points.dropFirst() { path.addLine(to: point.cg) }
        if closed { path.closeSubpath() }
        return path
    }

    static func circle(_ c: PinballVec, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    static func segment(_ a: PinballVec, _ b: PinballVec) -> Path {
        var path = Path()
        path.move(to: a.cg)
        path.addLine(to: b.cg)
        return path
    }

    /// An arrow-shaped light pointing along `way`.
    static func arrow(at c: PinballVec, way: PinballVec, size: Double) -> Path {
        let d = way.normalized
        let n = PinballVec(-d.y, d.x)
        let tip = c + d * size
        let back = c - d * (size * 0.6)
        let notch = c - d * (size * 0.15)
        return line([tip, back + n * (size * 0.75), notch, back - n * (size * 0.75)], closed: true)
    }
}

// MARK: - The fixed artwork

/// Everything on the table that never moves: the cabinet, the playfield's
/// paint, the rails, the rubbers, the ramp's plastic and the apron. Drawn
/// once for a size, then left alone while the live layer redraws on top.
struct PinballTableArt: View, Equatable {
    static func == (lhs: PinballTableArt, rhs: PinballTableArt) -> Bool { true }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            var g = context
            let s = size.width / CGFloat(PinballTable.width)
            g.scaleBy(x: s, y: s)
            PinballArt.draw(g, table: .classic)
        }
        .accessibilityHidden(true)
    }
}

enum PinballArt {
    static func draw(_ g: GraphicsContext, table: PinballTable) {
        cabinet(g, table)
        felt(g, table)
        decorations(g, table)
        plungerLane(g, table)
        ramp(g, table)
        slings(g, table)
        walls(g, table)
        apron(g, table)
        labels(g)
    }

    private static func cabinet(_ g: GraphicsContext, _ table: PinballTable) {
        let rect = CGRect(x: 0, y: 0, width: PinballTable.width, height: PinballTable.height)
        g.fill(Path(rect), with: .color(PinballGlow.cabinet))
    }

    private static func felt(_ g: GraphicsContext, _ table: PinballTable) {
        let outline = PinballPaths.line(table.outline, closed: true)
        let gradient = Gradient(colors: [PinballGlow.feltTop, PinballGlow.feltMiddle, PinballGlow.feltBottom])
        g.fill(outline, with: .linearGradient(gradient, startPoint: CGPoint(x: 280, y: 0), endPoint: CGPoint(x: 280, y: 1000)))
        // A soft pool of light under the bumpers.
        let pool = Gradient(colors: [Color(red: 0.55, green: 0.25, blue: 0.85).opacity(0.38), Color.clear])
        g.fill(PinballPaths.circle(PinballVec(259, 245), 190),
               with: .radialGradient(pool, center: CGPoint(x: 259, y: 245), startRadius: 0, endRadius: 190))
        let lower = Gradient(colors: [Color(red: 0.10, green: 0.55, blue: 0.70).opacity(0.22), Color.clear])
        g.fill(PinballPaths.circle(PinballVec(259, 700), 230),
               with: .radialGradient(lower, center: CGPoint(x: 259, y: 700), startRadius: 0, endRadius: 230))
    }

    /// Stars, rings and the lane stripes painted on the playfield.
    private static func decorations(_ g: GraphicsContext, _ table: PinballTable) {
        var rng = PinballRandom(seed: 99)
        var stars = Path()
        for _ in 0..<70 {
            let p = PinballVec(rng.range(30, 490), rng.range(60, 860))
            guard PinballGeometry.inside(p, table.outline) else { continue }
            let r = rng.range(0.8, 2.2)
            stars.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        g.fill(stars, with: .color(Color.white.opacity(0.35)))

        let ringStyle = StrokeStyle(lineWidth: 2, dash: [6, 8])
        g.stroke(PinballPaths.circle(PinballVec(259, 640), 92), with: .color(PinballGlow.cyan.opacity(0.18)), style: ringStyle)
        g.stroke(PinballPaths.circle(PinballVec(259, 640), 128), with: .color(PinballGlow.magenta.opacity(0.12)), style: ringStyle)

        // Lane stripes between the top guides.
        for lane in table.lanes {
            let stripe = CGRect(x: lane.x - 14, y: 70, width: 28, height: 56)
            g.fill(Path(roundedRect: stripe, cornerRadius: 10), with: .color(Color.white.opacity(0.05)))
        }
    }

    private static func plungerLane(_ g: GraphicsContext, _ table: PinballTable) {
        let lane = CGRect(x: table.plungerLeft, y: 290, width: table.plungerRight - table.plungerLeft, height: 710)
        let gradient = Gradient(colors: [Color.black.opacity(0.15), Color.black.opacity(0.45)])
        g.fill(Path(lane), with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 300), endPoint: CGPoint(x: 0, y: 1000)))
        // Chevrons up the lane.
        var chevrons = Path()
        let mid = (table.plungerLeft + table.plungerRight) / 2
        for i in 0..<5 {
            let y = 860.0 - Double(i) * 70
            chevrons.move(to: CGPoint(x: mid - 9, y: y + 8))
            chevrons.addLine(to: CGPoint(x: mid, y: y))
            chevrons.addLine(to: CGPoint(x: mid + 9, y: y + 8))
        }
        g.stroke(chevrons, with: .color(PinballGlow.gold.opacity(0.28)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }

    /// The ramp's clear plastic, with its two edges.
    private static func ramp(_ g: GraphicsContext, _ table: PinballTable) {
        let path = PinballPaths.line(table.ramp.path)
        g.stroke(path, with: .color(Color.black.opacity(0.35)),
                 style: StrokeStyle(lineWidth: 46, lineCap: .round, lineJoin: .round))
        g.stroke(path, with: .color(PinballGlow.cyan.opacity(0.16)),
                 style: StrokeStyle(lineWidth: 38, lineCap: .round, lineJoin: .round))
        g.stroke(path, with: .color(PinballGlow.cyan.opacity(0.55)),
                 style: StrokeStyle(lineWidth: 40, lineCap: .round, lineJoin: .round, dash: [2, 10]))
        g.stroke(path, with: .color(Color.white.opacity(0.10)),
                 style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }

    private static func slings(_ g: GraphicsContext, _ table: PinballTable) {
        for sling in table.slings {
            let triangle = PinballPaths.line(sling.triangle, closed: true)
            let gradient = Gradient(colors: [PinballGlow.magenta.opacity(0.85), Color(red: 0.35, green: 0.08, blue: 0.40)])
            g.fill(triangle, with: .linearGradient(gradient, startPoint: sling.a.cg, endPoint: sling.back.cg))
            g.stroke(triangle, with: .color(Color.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }

    private static func walls(_ g: GraphicsContext, _ table: PinballTable) {
        // The outer rails: a dark edge and a chrome top.
        for rail in table.rails {
            let path = PinballPaths.line(rail)
            g.stroke(path, with: .color(PinballGlow.chromeDark), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            g.stroke(path, with: .color(PinballGlow.chrome), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
        }
        for wall in table.walls where wall.radius > 0 {
            let path = PinballPaths.segment(wall.a, wall.b)
            let width = CGFloat(wall.radius * 2)
            if wall.rubber {
                g.stroke(path, with: .color(Color.black.opacity(0.5)), style: StrokeStyle(lineWidth: width + 3, lineCap: .round))
                g.stroke(path, with: .color(PinballGlow.rubber), style: StrokeStyle(lineWidth: width, lineCap: .round))
            } else {
                g.stroke(path, with: .color(PinballGlow.chromeDark), style: StrokeStyle(lineWidth: width + 2, lineCap: .round))
                g.stroke(path, with: .color(PinballGlow.chrome.opacity(0.9)), style: StrokeStyle(lineWidth: width - 2, lineCap: .round))
            }
        }
        // The plunger lane's gate.
        if let gate = table.walls.first(where: { $0.oneWay }) {
            g.stroke(PinballPaths.segment(gate.a, gate.b), with: .color(PinballGlow.chrome.opacity(0.7)),
                     style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 4]))
        }
        // The spinner's two posts.
        for post in [table.spinner.a, table.spinner.b] {
            g.fill(PinballPaths.circle(post, 4), with: .color(PinballGlow.chrome))
        }
    }

    /// The apron under the flippers, and the cabinet's steel over the right outlane.
    private static func apron(_ g: GraphicsContext, _ table: PinballTable) {
        let m = PinballTable.mirror
        let left: [PinballVec] = [PinballVec(53, 856), PinballVec(166, 906), PinballVec(198, 1000), PinballVec(53, 1000)]
        let right = left.map { $0.mirrored(m) }
        let gradient = Gradient(colors: [PinballGlow.apron, Color.black])
        for piece in [left, right] {
            let path = PinballPaths.line(piece, closed: true)
            g.fill(path, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 860), endPoint: CGPoint(x: 0, y: 1000)))
        }
        for solid in table.solids.prefix(2) {
            g.fill(PinballPaths.line(solid, closed: true), with: .color(PinballGlow.apron))
        }
    }

    private static func labels(_ g: GraphicsContext) {
        let jackpot: Text = Text("RAMP").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(PinballGlow.cyan.opacity(0.8))
        g.draw(jackpot, at: CGPoint(x: 396, y: 553))
        let orbit: Text = Text("ORBIT").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(PinballGlow.magenta.opacity(0.8))
        g.draw(orbit, at: CGPoint(x: 112, y: 517))
        let title: Text = Text("STARLIGHT").font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(Color.white.opacity(0.18))
        g.draw(title, at: CGPoint(x: 259, y: 800))
    }
}

/// The words printed over the lights (the multiplier's 2× to 5×, Shoot
/// Again): fixed, so drawn once on a layer of their own above the live one,
/// and no text is laid out per frame.
struct PinballTableLabels: View, Equatable {
    static func == (lhs: PinballTableLabels, rhs: PinballTableLabels) -> Bool { true }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            var g = context
            let s = size.width / CGFloat(PinballTable.width)
            g.scaleBy(x: s, y: s)
            PinballTableLabels.draw(g)
        }
        .accessibilityHidden(true)
    }

    private static func draw(_ g: GraphicsContext) {
        for n in 2...5 {
            let c = CGPoint(x: 214 + Double(n - 2) * 30, y: 588)
            let shade: Text = Text("\(n)×").font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.7))
            let label: Text = Text("\(n)×").font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
            g.draw(shade, at: CGPoint(x: c.x + 0.8, y: c.y + 0.8))
            g.draw(label, at: c)
        }
        let shoot: Text = Text("SHOOT AGAIN").font(.system(size: 7, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.75))
        g.draw(shoot, at: CGPoint(x: 259, y: 986))
    }
}

// MARK: - The live layer

/// One frame of the table to draw: copied out of the engine so the drawing
/// never reads the engine while it moves.
struct PinballSnapshot {
    let machine: PinballMachine
    let sparks: [PinballSpark]
    let trails: [Int: [PinballVec]]
}

/// The moving parts, redrawn every frame: lights, bumpers, targets, the
/// spinner, flippers, plunger, balls and sparks.
struct PinballTableLive: View {
    let engine: PinballEngine
    @ObservedObject var clock: PinballClock

    var body: some View {
        let snap = PinballSnapshot(machine: engine.machine, sparks: engine.sparks.items, trails: engine.trails)
        Canvas(rendersAsynchronously: false) { context, size in
            var g = context
            let s = size.width / CGFloat(PinballTable.width)
            g.scaleBy(x: s, y: s)
            PinballLive.draw(g, snap)
        }
        .accessibilityHidden(true)
    }
}

enum PinballLive {
    static func draw(_ g: GraphicsContext, _ snap: PinballSnapshot) {
        let m = snap.machine
        lanes(g, m)
        inserts(g, m)
        targets(g, m)
        bumpers(g, m)
        slings(g, m)
        spinner(g, m)
        plunger(g, m)
        flippers(g, m)
        balls(g, m, snap.trails)
        sparks(g, snap.sparks)
        washes(g, m)
    }

    /// 1 just after `at`, fading to 0 over `span` seconds.
    private static func glow(_ m: PinballMachine, _ at: Double, _ span: Double = 0.3) -> Double {
        let age = m.time - at
        return age >= 0 && age < span ? 1 - age / span : 0
    }

    private static func blink(_ m: PinballMachine, _ rate: Double) -> Bool {
        sin(m.time * rate * 2 * Double.pi) > 0
    }

    /// A light that flashes while `on`: bright, dim, bright.
    private static func pulse(_ m: PinballMachine, _ on: Bool, _ rate: Double) -> Double {
        guard on else { return 0 }
        return blink(m, rate) ? 1 : 0.2
    }

    /// A round light: a dim lens, lit bright with a halo.
    private static func light(_ g: GraphicsContext, at c: PinballVec, radius r: Double, colour: Color, lit: Double) {
        g.fill(PinballPaths.circle(c, r), with: .color(colour.opacity(0.18 + 0.1 * lit)))
        guard lit > 0.01 else { return }
        var add = g
        add.blendMode = .plusLighter
        let halo = Gradient(colors: [colour.opacity(0.75 * lit), Color.clear])
        add.fill(PinballPaths.circle(c, r * 2.6), with: .radialGradient(halo, center: c.cg, startRadius: 0, endRadius: CGFloat(r * 2.6)))
        add.fill(PinballPaths.circle(c, r * 0.8), with: .color(colour.opacity(lit)))
    }

    private static func lanes(_ g: GraphicsContext, _ m: PinballMachine) {
        let skillShowing = m.ballWaiting || m.skillArmedUntil != nil
        let allFlash = glow(m, m.flashes.lanesAll, 0.9)
        for (i, lane) in m.table.lanes.enumerated() {
            var lit = m.lanesLit[i] ? 1.0 : glow(m, m.flashes.lanes[i], 0.4)
            if allFlash > 0 { lit = blink(m, 8) ? 1 : 0.2 }
            light(g, at: lane + PinballVec(0, 2), radius: 9, colour: PinballGlow.green, lit: lit)
            if skillShowing && i == m.skillLane {
                light(g, at: lane + PinballVec(0, -26), radius: 6, colour: PinballGlow.gold, lit: blink(m, 3) ? 1 : 0.15)
            }
        }
    }

    /// The painted lights: bonus multiplier, the four modes, the arrows to
    /// the shot that matters now, and Shoot Again.
    private static func inserts(_ g: GraphicsContext, _ m: PinballMachine) {
        for n in 2...5 {
            let c = PinballVec(214 + Double(n - 2) * 30, 588)
            light(g, at: c, radius: 11, colour: PinballGlow.gold, lit: m.multiplier >= n ? 1 : 0)
        }
        let modeColours: [Color] = [PinballGlow.gold, PinballGlow.cyan, PinballGlow.magenta, PinballGlow.green]
        for mode in PinballMode.allCases {
            let c = PinballVec(214 + Double(mode.rawValue) * 30, 680)
            let lit: Double
            if mode.rawValue < m.mode.rawValue {
                lit = 1
            } else if mode == m.mode {
                lit = blink(m, 1.6) ? 0.9 : 0.25
            } else {
                lit = 0
            }
            let diamond = PinballPaths.line([c + PinballVec(0, -10), c + PinballVec(9, 0), c + PinballVec(0, 10), c + PinballVec(-9, 0)], closed: true)
            g.fill(diamond, with: .color(modeColours[mode.rawValue].opacity(0.2 + 0.8 * lit)))
        }
        let rampHot = m.mode == .rampRush || m.multiball
        arrow(g, at: PinballVec(402, 522), way: m.table.ramp.direction, colour: PinballGlow.cyan,
              lit: max(pulse(m, rampHot, m.multiball ? 4 : 2), glow(m, m.flashes.ramp, 0.6)))
        arrow(g, at: PinballVec(106, 488), way: PinballVec(-0.68, -0.73), colour: PinballGlow.magenta,
              lit: max(pulse(m, m.mode == .orbitRun, 2), glow(m, m.flashes.orbit, 0.6)))
        arrow(g, at: PinballVec(172, 503), way: PinballVec(-0.29, -0.96), colour: PinballGlow.gold,
              lit: max(pulse(m, m.mode == .targetPractice, 2), glow(m, m.flashes.bank, 0.8)))
        // Shoot Again: lit while the ball saver is on, flashing as it runs out.
        var save = glow(m, m.flashes.save, 1)
        if m.saveActive { save = m.saveUntil - m.time < 2 ? pulse(m, true, 5) : 1 }
        light(g, at: PinballVec(259, 968), radius: 7, colour: PinballGlow.red, lit: save)
    }

    private static func arrow(_ g: GraphicsContext, at c: PinballVec, way: PinballVec, colour: Color, lit: Double) {
        let path = PinballPaths.arrow(at: c, way: way, size: 16)
        g.fill(path, with: .color(colour.opacity(0.2 + 0.2 * lit)))
        guard lit > 0.01 else { return }
        var add = g
        add.blendMode = .plusLighter
        add.fill(path, with: .color(colour.opacity(0.8 * lit)))
        let halo = Gradient(colors: [colour.opacity(0.45 * lit), Color.clear])
        add.fill(PinballPaths.circle(c, 34), with: .radialGradient(halo, center: c.cg, startRadius: 0, endRadius: 34))
    }

    private static func targets(_ g: GraphicsContext, _ m: PinballMachine) {
        for (i, target) in m.table.targets.enumerated() {
            let path = PinballPaths.segment(target.a, target.b)
            if m.targetsUp[i] {
                g.stroke(path, with: .color(Color.black.opacity(0.5)), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                g.stroke(path, with: .color(PinballGlow.gold), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                g.stroke(path, with: .color(Color.white.opacity(0.6)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            } else {
                g.stroke(path, with: .color(Color.black.opacity(0.55)), style: StrokeStyle(lineWidth: 6, lineCap: .butt, dash: [3, 3]))
            }
            let flash = glow(m, m.flashes.targets[i], 0.35)
            if flash > 0 {
                var add = g
                add.blendMode = .plusLighter
                add.stroke(path, with: .color(PinballGlow.gold.opacity(flash)), style: StrokeStyle(lineWidth: 18, lineCap: .round))
            }
        }
    }

    private static func bumpers(_ g: GraphicsContext, _ m: PinballMachine) {
        let blitz = m.mode == .bumperBlitz && !m.tilted
        for (i, bumper) in m.table.bumpers.enumerated() {
            let c = bumper.centre, r = bumper.radius
            let hit = glow(m, m.flashes.bumpers[i], 0.25)
            g.fill(PinballPaths.circle(c + PinballVec(3, 5), r + 5), with: .color(Color.black.opacity(0.45)))
            g.fill(PinballPaths.circle(c, r + 5), with: .color(PinballGlow.chromeDark))
            let ring = blitz && blink(m, 1.2) ? PinballGlow.gold : PinballGlow.rubber
            g.stroke(PinballPaths.circle(c, r + 1), with: .color(ring), lineWidth: 3)
            let cap = Gradient(colors: [Color(red: 1, green: 0.62 + 0.38 * hit, blue: 0.45 + 0.55 * hit), PinballGlow.red,
                                        Color(red: 0.45, green: 0.05, blue: 0.10)])
            let top = c + PinballVec(-7, -8)
            g.fill(PinballPaths.circle(c, r - 4), with: .radialGradient(cap, center: top.cg, startRadius: 0, endRadius: CGFloat(r + 4)))
            g.fill(PinballPaths.circle(c, 6), with: .color(Color.white.opacity(0.85)))
            if hit > 0 {
                var add = g
                add.blendMode = .plusLighter
                let halo = Gradient(colors: [PinballGlow.gold.opacity(0.9 * hit), Color.clear])
                add.fill(PinballPaths.circle(c, r * 2.4), with: .radialGradient(halo, center: c.cg, startRadius: CGFloat(r * 0.6), endRadius: CGFloat(r * 2.4)))
            }
        }
    }

    private static func slings(_ g: GraphicsContext, _ m: PinballMachine) {
        for (i, sling) in m.table.slings.enumerated() {
            let hit = glow(m, m.flashes.slings[i], 0.2)
            // The rubber bows out for a moment as it kicks.
            let bow = sling.normal * (6 * hit)
            let mid = (sling.a + sling.b) / 2 + bow
            var band = Path()
            band.move(to: sling.a.cg)
            band.addQuadCurve(to: sling.b.cg, control: mid.cg)
            g.stroke(band, with: .color(Color.black.opacity(0.5)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
            g.stroke(band, with: .color(PinballGlow.rubber), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            if hit > 0 {
                var add = g
                add.blendMode = .plusLighter
                add.stroke(band, with: .color(PinballGlow.cyan.opacity(hit)), style: StrokeStyle(lineWidth: 16, lineCap: .round))
            }
        }
    }

    /// The spinner's flag, seen edge-on as it turns.
    private static func spinner(_ g: GraphicsContext, _ m: PinballMachine) {
        let s = m.table.spinner
        let depth = 3 + 7 * abs(cos(m.spinnerAngle))
        let rect = CGRect(x: s.a.x + 4, y: s.centre.y - depth / 2, width: s.b.x - s.a.x - 8, height: depth)
        let face = cos(m.spinnerAngle) > 0 ? PinballGlow.chrome : Color(red: 0.55, green: 0.58, blue: 0.66)
        g.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(face))
        g.stroke(PinballPaths.segment(s.a, s.b), with: .color(Color.black.opacity(0.6)), lineWidth: 1.5)
    }

    private static func plunger(_ g: GraphicsContext, _ m: PinballMachine) {
        let t = m.table
        let mid = (t.plungerLeft + t.plungerRight) / 2
        let top = m.plungerY
        // The spring, squashed as it is pulled.
        var spring = Path()
        let coils = 7
        let springTop = top + 14
        let span = max(10, 1000 - springTop)
        for i in 0...(coils * 2) {
            let y = springTop + span * Double(i) / Double(coils * 2)
            let x = mid + (i % 2 == 0 ? -10 : 10)
            if i == 0 { spring.move(to: CGPoint(x: x, y: y)) } else { spring.addLine(to: CGPoint(x: x, y: y)) }
        }
        g.stroke(spring, with: .color(PinballGlow.chrome.opacity(0.8)), lineWidth: 2)
        let rod = CGRect(x: mid - 4, y: top, width: 8, height: 1000 - top)
        g.fill(Path(rod), with: .color(PinballGlow.chromeDark))
        let tip = CGRect(x: mid - 14, y: top, width: 28, height: 12)
        let gradient = Gradient(colors: [PinballGlow.red, Color(red: 0.5, green: 0.08, blue: 0.08)])
        g.fill(Path(roundedRect: tip, cornerRadius: 4), with: .linearGradient(gradient, startPoint: CGPoint(x: mid, y: top), endPoint: CGPoint(x: mid, y: top + 12)))
        if m.pull > 0.01 {
            // A power bar beside the lane.
            let full = CGRect(x: t.plungerLeft - 12, y: 820, width: 6, height: 150)
            g.fill(Path(roundedRect: full, cornerRadius: 3), with: .color(Color.black.opacity(0.5)))
            let h = 150 * m.pull
            let bar = CGRect(x: t.plungerLeft - 12, y: 970 - h, width: 6, height: h)
            let power = Gradient(colors: [PinballGlow.green, PinballGlow.gold, PinballGlow.red])
            g.fill(Path(roundedRect: bar, cornerRadius: 3), with: .linearGradient(power, startPoint: CGPoint(x: 0, y: 970), endPoint: CGPoint(x: 0, y: 820)))
        }
    }

    private static func flippers(_ g: GraphicsContext, _ m: PinballMachine) {
        for flipper in m.flippers {
            let spec = flipper.spec
            let p = spec.pivot, tip = flipper.tip
            let d = (tip - p).normalized
            let n = PinballVec(-d.y, d.x)
            let shadow = PinballVec(3, 5)
            fillFlipper(g, p + shadow, tip + shadow, n, spec.baseRadius, spec.tipRadius, .color(Color.black.opacity(0.4)))
            fillFlipper(g, p, tip, n, spec.baseRadius, spec.tipRadius, .color(PinballGlow.red))
            let body = Gradient(colors: [Color.white, Color(red: 0.82, green: 0.84, blue: 0.9)])
            let shade = GraphicsContext.Shading.linearGradient(body, startPoint: (p - n * spec.baseRadius).cg, endPoint: (p + n * spec.baseRadius).cg)
            fillFlipper(g, p, tip, n, spec.baseRadius - 3, spec.tipRadius - 2.5, shade)
            g.fill(PinballPaths.circle(p, 4), with: .color(PinballGlow.chromeDark))
        }
    }

    /// A tapered capsule: two circles and the band between them.
    private static func fillFlipper(_ g: GraphicsContext, _ p: PinballVec, _ tip: PinballVec, _ n: PinballVec,
                                    _ rb: Double, _ rt: Double, _ shading: GraphicsContext.Shading) {
        g.fill(PinballPaths.circle(p, rb), with: shading)
        g.fill(PinballPaths.circle(tip, rt), with: shading)
        g.fill(PinballPaths.line([p + n * rb, tip + n * rt, tip - n * rt, p - n * rb], closed: true), with: shading)
    }

    private static func balls(_ g: GraphicsContext, _ m: PinballMachine, _ trails: [Int: [PinballVec]]) {
        let r = PinballTable.ballRadius
        for ball in m.balls {
            let lifted = ball.ramp != nil
            let size = lifted ? r * 1.15 : r
            // The motion trail, only when the ball is really moving.
            if ball.speed > 900, let trail = trails[ball.id], trail.count > 1 {
                var add = g
                add.blendMode = .plusLighter
                for (k, point) in trail.dropLast().enumerated() {
                    let share = Double(k + 1) / Double(trail.count)
                    add.fill(PinballPaths.circle(point, size * (0.45 + 0.45 * share)), with: .color(PinballGlow.cyan.opacity(0.16 * share)))
                }
            }
            let drop = lifted ? PinballVec(7, 10) : PinballVec(3, 4)
            g.fill(PinballPaths.circle(ball.p + drop, size), with: .color(Color.black.opacity(lifted ? 0.3 : 0.4)))
            let steel = Gradient(colors: [Color.white, Color(red: 0.78, green: 0.80, blue: 0.86), Color(red: 0.26, green: 0.28, blue: 0.34)])
            let light = ball.p + PinballVec(-size * 0.35, -size * 0.4)
            g.fill(PinballPaths.circle(ball.p, size), with: .radialGradient(steel, center: light.cg, startRadius: 0, endRadius: CGFloat(size * 1.5)))
            g.fill(PinballPaths.circle(light, size * 0.25), with: .color(Color.white.opacity(0.9)))
        }
    }

    /// The sparks, in a few batches by colour and age, not one fill each.
    private static func sparks(_ g: GraphicsContext, _ sparks: [PinballSpark]) {
        guard !sparks.isEmpty else { return }
        var add = g
        add.blendMode = .plusLighter
        for hue in 0...5 {
            for band in 0..<3 {
                var path = Path()
                var any = false
                for spark in sparks where spark.hue == hue && min(2, Int(spark.fade * 3)) == band {
                    let s = spark.size
                    path.addEllipse(in: CGRect(x: spark.p.x - s, y: spark.p.y - s, width: s * 2, height: s * 2))
                    any = true
                }
                if any {
                    add.fill(path, with: .color(PinballGlow.hue(hue).opacity(0.35 + 0.3 * Double(band))))
                }
            }
        }
    }

    /// Whole-table washes: white for the big moments, red for a tilt.
    private static func washes(_ g: GraphicsContext, _ m: PinballMachine) {
        let rect = Path(CGRect(x: 0, y: 0, width: PinballTable.width, height: PinballTable.height))
        let big = max(glow(m, m.flashes.jackpot, 0.5), glow(m, m.flashes.mode, 0.6))
        if big > 0 {
            var add = g
            add.blendMode = .plusLighter
            add.fill(rect, with: .color(Color.white.opacity(0.22 * big)))
        }
        if m.tilted {
            g.fill(rect, with: .color(PinballGlow.red.opacity(blink(m, 1.5) ? 0.16 : 0.06)))
        }
    }
}
