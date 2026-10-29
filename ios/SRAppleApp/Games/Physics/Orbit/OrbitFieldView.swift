import SwiftUI

/// The field: space, the planets and everything else in the level, the aim
/// or the probe in flight, and the sparks. One Canvas, redrawn once a frame
/// from the scene; nothing in it is a SwiftUI view of its own.
///
/// Space is a fixed palette — deep blue-black in light mode and dark — the
/// way a game's board does not change with the phone's appearance.
struct OrbitFieldView: View {
    @ObservedObject var scene: OrbitScene
    /// Reduce Motion: no shake, no drifting sky.
    let calm: Bool
    /// VoiceOver's swipe up and down on the field: turn the aim a degree.
    let adjust: (Int) -> Void

    init(scene: OrbitScene, calm: Bool = false, adjust: @escaping (Int) -> Void = { _ in }) {
        self.scene = scene
        self.calm = calm
        self.adjust = adjust
    }

    var body: some View {
        let painter = OrbitPainter(run: scene.run, sky: scene.sky, focus: scene.focus, calm: calm)
        Canvas(rendersAsynchronously: false) { context, size in
            painter.draw(in: context, size: size)
        }
        .background(OrbitPaint.spaceDeep)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityHint("Swipe up or down to turn the aim. Drag and pull back to aim and set the power.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(1)
            case .decrement: adjust(-1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("orbit-field")
    }

    /// The field in words: the level, what is in it, the aim or the flight.
    private var label: String {
        let run = scene.run
        let lv = run.level
        let got = run.collected.filter { $0 }.count
        let target = lv.target.kind == .station ? "a space station" : "a wormhole"
        let names = lv.bodies.map(\.name).joined(separator: ", ")
        var words = "Level \(lv.number), \(lv.name). Fly to \(target)."
        if !names.isEmpty { words += " Pulling on the probe: \(names)." }
        words += " \(got) of \(lv.stars.count) stars picked up, \(run.attempt.probesLeft) probes left."
        if run.isAiming {
            words += " Aim \(OrbitAimWords.bearing(run.aim)), power \(run.aim.percent) percent."
            if run.prediction.end == .arrived {
                words += " The aiming line reaches the target."
            } else if let end = run.prediction.end {
                words += " The aiming line ends: \(end.sentence(in: lv))"
            }
        } else if run.isFlying {
            words += " Probe in flight."
        }
        return words
    }
}

/// The fixed colours of space.
enum OrbitPaint {
    static let spaceDeep = Color(red: 0.020, green: 0.027, blue: 0.075)
    static let spaceHigh = Color(red: 0.055, green: 0.050, blue: 0.150)
    static let starWhite = Color(red: 0.96, green: 0.97, blue: 1.0)
    static let starBlue = Color(red: 0.70, green: 0.82, blue: 1.0)
    static let starWarm = Color(red: 1.0, green: 0.86, blue: 0.70)
    static let gold = Color(red: 1.0, green: 0.82, blue: 0.28)
    static let goldDeep = Color(red: 0.95, green: 0.55, blue: 0.10)
    static let aim = Color(red: 0.55, green: 0.92, blue: 1.0)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.30)
    static let dock = Color(red: 0.40, green: 0.95, blue: 0.85)
    static let warp = Color(red: 0.78, green: 0.50, blue: 1.0)
    static let rock = [Color(red: 0.42, green: 0.36, blue: 0.33), Color(red: 0.52, green: 0.45, blue: 0.38),
                       Color(red: 0.34, green: 0.31, blue: 0.32)]

    /// A body's light side, middle, shadow side and the glow of its air.
    struct BodyTones {
        let light: Color
        let mid: Color
        let dark: Color
        let glow: Color
    }

    static func tones(_ look: OrbitLook) -> BodyTones {
        switch look {
        case .rocky:
            return BodyTones(light: rgb(0.80, 0.74, 0.68), mid: rgb(0.55, 0.48, 0.43), dark: rgb(0.20, 0.17, 0.17), glow: rgb(0.85, 0.75, 0.65))
        case .ocean:
            return BodyTones(light: rgb(0.55, 0.85, 1.0), mid: rgb(0.16, 0.45, 0.85), dark: rgb(0.04, 0.10, 0.30), glow: rgb(0.45, 0.75, 1.0))
        case .desert:
            return BodyTones(light: rgb(1.0, 0.85, 0.58), mid: rgb(0.85, 0.55, 0.28), dark: rgb(0.32, 0.17, 0.09), glow: rgb(1.0, 0.75, 0.45))
        case .ice:
            return BodyTones(light: rgb(0.95, 0.98, 1.0), mid: rgb(0.62, 0.80, 0.92), dark: rgb(0.18, 0.28, 0.42), glow: rgb(0.75, 0.92, 1.0))
        case .lava:
            return BodyTones(light: rgb(1.0, 0.62, 0.30), mid: rgb(0.62, 0.16, 0.08), dark: rgb(0.16, 0.04, 0.04), glow: rgb(1.0, 0.40, 0.18))
        case .jungle:
            return BodyTones(light: rgb(0.70, 0.95, 0.60), mid: rgb(0.20, 0.60, 0.35), dark: rgb(0.04, 0.18, 0.12), glow: rgb(0.55, 0.95, 0.70))
        case .amber:
            return BodyTones(light: rgb(1.0, 0.88, 0.62), mid: rgb(0.85, 0.58, 0.30), dark: rgb(0.30, 0.16, 0.08), glow: rgb(1.0, 0.80, 0.50))
        case .teal:
            return BodyTones(light: rgb(0.70, 1.0, 0.95), mid: rgb(0.20, 0.65, 0.68), dark: rgb(0.04, 0.18, 0.24), glow: rgb(0.50, 0.95, 0.90))
        case .violet:
            return BodyTones(light: rgb(0.88, 0.78, 1.0), mid: rgb(0.50, 0.36, 0.85), dark: rgb(0.13, 0.08, 0.30), glow: rgb(0.70, 0.58, 1.0))
        case .rose:
            return BodyTones(light: rgb(1.0, 0.80, 0.84), mid: rgb(0.85, 0.40, 0.52), dark: rgb(0.28, 0.08, 0.16), glow: rgb(1.0, 0.62, 0.72))
        case .moon:
            return BodyTones(light: rgb(0.88, 0.88, 0.90), mid: rgb(0.58, 0.58, 0.62), dark: rgb(0.18, 0.18, 0.22), glow: rgb(0.80, 0.80, 0.88))
        case .sun:
            return BodyTones(light: rgb(1.0, 0.99, 0.88), mid: rgb(1.0, 0.80, 0.30), dark: rgb(0.95, 0.40, 0.08), glow: rgb(1.0, 0.62, 0.18))
        case .blackHole:
            return BodyTones(light: rgb(1.0, 0.85, 0.55), mid: rgb(0.95, 0.45, 0.15), dark: rgb(0.0, 0.0, 0.0), glow: rgb(0.70, 0.40, 1.0))
        }
    }

    /// The faint clouds behind each system.
    static func nebula(_ system: OrbitSystem) -> (Color, Color) {
        switch system {
        case .inner: return (rgb(0.95, 0.45, 0.25), rgb(0.30, 0.35, 0.95))
        case .giants: return (rgb(0.15, 0.75, 0.70), rgb(0.95, 0.60, 0.25))
        case .deep: return (rgb(0.60, 0.25, 0.95), rgb(0.95, 0.25, 0.55))
        }
    }

    static func spark(_ tone: OrbitSparkTone) -> (Color, Color) {
        switch tone {
        case .fire: return (rgb(1.0, 0.92, 0.60), rgb(1.0, 0.40, 0.10))
        case .dock: return (rgb(0.90, 1.0, 1.0), dock)
        case .warp: return (rgb(1.0, 0.85, 1.0), warp)
        case .gold: return (rgb(1.0, 0.96, 0.75), gold)
        }
    }

    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r, green: g, blue: b)
    }
}

/// One frame's picture of a run. A value made fresh each frame (the run's
/// arrays are shared, not copied), so the Canvas closure owns nothing.
struct OrbitPainter {
    let run: OrbitRun
    let sky: OrbitSkyLayout
    let focus: OrbitVec
    var calm = false

    private var level: OrbitLevel { run.level }
    private var t: Double { run.skyTime }
    private var clock: Double { calm ? 0 : run.clock }

    func draw(in context: GraphicsContext, size: CGSize) {
        let view = OrbitViewport(width: Double(size.width), height: Double(size.height))
        drawBackdrop(in: context, size: size, view: view)

        var world = context
        let shake = calm ? 0 : run.shake
        let sx = shake * 5 * sin(run.clock * 71), sy = shake * 5 * cos(run.clock * 53)
        world.translateBy(x: CGFloat(view.originX + sx), y: CGFloat(view.originY + sy))
        world.scaleBy(x: CGFloat(view.scale), y: CGFloat(view.scale))
        let px = 1 / view.scale

        drawRails(in: world, px: px)
        drawBelts(in: world, px: px)
        drawLastPath(in: world, px: px)
        for body in level.bodies { drawBody(body, in: world, px: px) }
        drawPad(in: world, px: px)
        drawStars(in: world, px: px)
        drawTarget(in: world, px: px)
        if run.isAiming {
            drawAim(in: world, px: px)
        } else {
            drawTrail(in: world, px: px)
            drawProbe(in: world, px: px)
        }
        drawSparks(in: world, px: px)
        drawEdgeMarker(in: context, view: view)
    }

    // MARK: - Space

    private func drawBackdrop(in context: GraphicsContext, size: CGSize, view: OrbitViewport) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .linearGradient(Gradient(colors: [OrbitPaint.spaceHigh, OrbitPaint.spaceDeep]),
                                                       startPoint: CGPoint(x: size.width * 0.3, y: 0),
                                                       endPoint: CGPoint(x: size.width * 0.7, y: size.height)))
        // Two soft clouds in the system's colours, drifting a little with the camera.
        let (a, b) = OrbitPaint.nebula(level.system)
        let shiftX = (focus.x - OrbitField.width / 2) * 0.06 * view.scale
        let shiftY = (focus.y - OrbitField.height / 2) * 0.06 * view.scale
        let w = Double(size.width), h = Double(size.height)
        let seedX = Double((level.number * 37) % 100) / 100
        let c1 = CGPoint(x: w * (0.2 + 0.5 * seedX) - shiftX, y: h * 0.28 - shiftY)
        let c2 = CGPoint(x: w * (0.85 - 0.5 * seedX) - shiftX, y: h * 0.72 - shiftY)
        let r = CGFloat(max(w, h) * 0.55)
        context.fill(Path(ellipseIn: CGRect(x: c1.x - r, y: c1.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [a.opacity(0.20), a.opacity(0)]), center: c1, startRadius: 0, endRadius: r))
        context.fill(Path(ellipseIn: CGRect(x: c2.x - r, y: c2.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [b.opacity(0.16), b.opacity(0)]), center: c2, startRadius: 0, endRadius: r))

        // The starfield, three layers deep. Each layer is a tile that repeats,
        // shifted against the camera by its depth.
        for (index, stars) in sky.layers.enumerated() {
            let depth = OrbitSkyLayout.depths[index]
            let drift = calm ? 0 : run.clock * 2 * Double(index + 1)
            let ox = -(focus.x - OrbitField.width / 2) * depth * view.scale + drift
            let oy = -(focus.y - OrbitField.height / 2) * depth * view.scale + drift * 0.3
            for star in stars {
                var x = (star.x * w + ox).truncatingRemainder(dividingBy: w)
                if x < 0 { x += w }
                var y = (star.y * h + oy).truncatingRemainder(dividingBy: h)
                if y < 0 { y += h }
                let twinkle = calm ? 1 : 0.7 + 0.3 * sin(run.clock * (1.3 + Double(index) * 0.6) + star.twinkle)
                let colour: Color = star.tint == 1 ? OrbitPaint.starBlue : (star.tint == 2 ? OrbitPaint.starWarm : OrbitPaint.starWhite)
                let s = star.size
                context.fill(Path(ellipseIn: CGRect(x: x - s, y: y - s, width: s * 2, height: s * 2)),
                             with: .color(colour.opacity(star.brightness * twinkle)))
            }
        }
    }

    // MARK: - Rails and belts

    private func drawRails(in context: GraphicsContext, px: Double) {
        var rails: [OrbitRail] = level.bodies.compactMap { $0.rail }
        if let rail = level.target.rail { rails.append(rail) }
        for rail in rails {
            let r = rail.radius
            let rect = CGRect(x: rail.centre.x - r, y: rail.centre.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.16)),
                           style: StrokeStyle(lineWidth: CGFloat(1.2 * px), dash: [CGFloat(3 * px), CGFloat(7 * px)]))
        }
    }

    /// A band as a closed shape: the outer edge one way, the inner edge back.
    private func bandPath(_ belt: OrbitBelt) -> Path {
        let span = min(belt.span, 2 * Double.pi)
        let steps = max(12, Int(span * belt.outer / 12))
        var path = Path()
        for i in 0...steps {
            let a = belt.start + span * Double(i) / Double(steps)
            let p = CGPoint(x: belt.centre.x + belt.outer * cos(a), y: belt.centre.y + belt.outer * sin(a))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        for i in stride(from: steps, through: 0, by: -1) {
            let a = belt.start + span * Double(i) / Double(steps)
            path.addLine(to: CGPoint(x: belt.centre.x + belt.inner * cos(a), y: belt.centre.y + belt.inner * sin(a)))
        }
        path.closeSubpath()
        return path
    }

    private func drawBelts(in context: GraphicsContext, px: Double) {
        guard !level.belts.isEmpty else { return }
        for belt in level.belts {
            let band = bandPath(belt)
            context.fill(band, with: .color(Color(red: 0.55, green: 0.42, blue: 0.32).opacity(0.16)))
            context.stroke(band, with: .color(OrbitPaint.danger.opacity(0.22)), lineWidth: CGFloat(1 * px))
        }
        for rock in sky.rocks {
            let r = rock.radius
            let shade = OrbitPaint.rock[rock.shade % OrbitPaint.rock.count]
            let wobble = 0.82 + 0.18 * cos(rock.spin * 3)
            let rect = CGRect(x: rock.at.x - r, y: rock.at.y - r * wobble, width: r * 2, height: r * 2 * wobble)
            context.fill(Path(ellipseIn: rect), with: .color(shade))
            let hr = r * 0.45
            context.fill(Path(ellipseIn: CGRect(x: rock.at.x - r * 0.45 - hr / 2, y: rock.at.y - r * 0.45 - hr / 2, width: hr, height: hr)),
                         with: .color(Color.white.opacity(0.18)))
        }
    }

    private func drawLastPath(in context: GraphicsContext, px: Double) {
        let points = run.lastPath
        guard points.count > 2, run.isAiming else { return }
        var path = Path()
        path.move(to: CGPoint(x: points[0].x, y: points[0].y))
        for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
        context.stroke(path, with: .color(Color.white.opacity(0.13)),
                       style: StrokeStyle(lineWidth: CGFloat(1.5 * px), lineCap: .round, lineJoin: .round, dash: [CGFloat(5 * px), CGFloat(6 * px)]))
    }

    // MARK: - Bodies

    private func circle(_ c: OrbitVec, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    private func drawBody(_ body: OrbitBody, in context: GraphicsContext, px: Double) {
        let c = body.position(at: t)
        switch body.look {
        case .sun: drawSun(body, at: c, in: context)
        case .blackHole: drawHole(body, at: c, in: context, px: px)
        default: drawPlanet(body, at: c, in: context, px: px)
        }
    }

    private func drawPlanet(_ body: OrbitBody, at c: OrbitVec, in context: GraphicsContext, px: Double) {
        let r = body.radius
        let tone = OrbitPaint.tones(body.look)
        let centre = CGPoint(x: c.x, y: c.y)
        // The air: a soft glow just past the surface.
        let air = r * (body.look == .moon ? 1.25 : 1.55)
        context.fill(circle(c, air), with: .radialGradient(Gradient(stops: [
            .init(color: tone.glow.opacity(0.42), location: 0),
            .init(color: tone.glow.opacity(0.14), location: 0.45),
            .init(color: tone.glow.opacity(0), location: 1),
        ]), center: centre, startRadius: CGFloat(r * 0.9), endRadius: CGFloat(air)))

        if body.ringed { drawRing(r: r, at: c, tone: tone, in: context, front: false) }

        // The globe, lit from the upper left.
        let light = CGPoint(x: c.x - r * 0.38, y: c.y - r * 0.42)
        context.fill(circle(c, r), with: .radialGradient(Gradient(stops: [
            .init(color: tone.light, location: 0),
            .init(color: tone.mid, location: 0.48),
            .init(color: tone.dark, location: 1),
        ]), center: light, startRadius: 0, endRadius: CGFloat(r * 1.45)))

        var face = context
        face.clip(to: circle(c, r))
        if body.look.isGiant {
            // Bands of cloud across the face, slowly turning.
            let drift = (clock * 4).truncatingRemainder(dividingBy: r)
            for i in 0..<7 {
                let y = c.y - r + Double(i) * r * 0.31 + 0.12 * r
                let h = r * (i % 2 == 0 ? 0.16 : 0.10)
                let band = CGRect(x: c.x - r * 1.4 + drift - r * 0.2, y: y, width: r * 2.8, height: h)
                face.fill(Path(ellipseIn: band), with: .color((i % 2 == 0 ? tone.dark : tone.light).opacity(0.22)))
            }
            // A storm.
            let storm = CGRect(x: c.x + r * 0.15, y: c.y + r * 0.18, width: r * 0.42, height: r * 0.22)
            face.fill(Path(ellipseIn: storm), with: .color(tone.dark.opacity(0.35)))
        } else if body.look == .moon || body.look == .rocky {
            // Craters.
            let spots: [(Double, Double, Double)] = [(-0.35, -0.10, 0.22), (0.25, 0.30, 0.16), (0.30, -0.38, 0.12), (-0.10, 0.45, 0.10)]
            for (dx, dy, s) in spots {
                let cr = r * s
                face.fill(circle(OrbitVec(c.x + dx * r, c.y + dy * r), cr), with: .color(tone.dark.opacity(0.32)))
                face.fill(circle(OrbitVec(c.x + dx * r - cr * 0.2, c.y + dy * r - cr * 0.2), cr * 0.7),
                          with: .color(tone.light.opacity(0.10)))
            }
        } else {
            // Land or ice: a few soft patches.
            let patches: [(Double, Double, Double, Double)] = [(-0.45, -0.05, 0.55, 0.30), (0.10, 0.35, 0.60, 0.22), (0.20, -0.45, 0.40, 0.18)]
            let patch = body.look == .ocean ? OrbitPaint.rgb(0.30, 0.70, 0.40) : tone.light
            for (dx, dy, w, h) in patches {
                let rect = CGRect(x: c.x + dx * r, y: c.y + dy * r, width: w * r, height: h * r)
                face.fill(Path(ellipseIn: rect), with: .color(patch.opacity(body.look == .ocean ? 0.55 : 0.22)))
            }
        }
        // Night side.
        face.fill(circle(c, r), with: .radialGradient(Gradient(colors: [Color.black.opacity(0), Color.black.opacity(0.45)]),
                                                     center: light, startRadius: CGFloat(r * 0.9), endRadius: CGFloat(r * 2.0)))
        // Rim light.
        context.stroke(circle(c, r), with: .color(tone.light.opacity(0.28)), lineWidth: CGFloat(max(1 * px, r * 0.04)))

        if body.ringed { drawRing(r: r, at: c, tone: tone, in: context, front: true) }
    }

    /// A giant's ring, tipped over: the half behind the planet, or the half in front.
    private func drawRing(r: Double, at c: OrbitVec, tone: OrbitPaint.BodyTones, in context: GraphicsContext, front: Bool) {
        var ring = context
        ring.translateBy(x: CGFloat(c.x), y: CGFloat(c.y))
        ring.rotate(by: .degrees(-16))
        let half = r * 2.4
        let clip = front ? CGRect(x: -half, y: 0, width: half * 2, height: half) : CGRect(x: -half, y: -half, width: half * 2, height: half)
        ring.clip(to: Path(clip))
        let outer = CGRect(x: -r * 2.0, y: -r * 0.52, width: r * 4.0, height: r * 1.04)
        let inner = CGRect(x: -r * 1.62, y: -r * 0.40, width: r * 3.24, height: r * 0.80)
        ring.stroke(Path(ellipseIn: outer), with: .color(tone.light.opacity(0.55)), lineWidth: CGFloat(r * 0.16))
        ring.stroke(Path(ellipseIn: inner), with: .color(tone.mid.opacity(0.55)), lineWidth: CGFloat(r * 0.10))
    }

    private func drawSun(_ body: OrbitBody, at c: OrbitVec, in context: GraphicsContext) {
        let r = body.radius
        let tone = OrbitPaint.tones(.sun)
        let centre = CGPoint(x: c.x, y: c.y)
        let pulse = 1 + 0.05 * sin(clock * 2.2)
        let corona = r * 2.6 * pulse
        var glow = context
        glow.blendMode = .plusLighter
        glow.fill(circle(c, corona), with: .radialGradient(Gradient(stops: [
            .init(color: tone.mid.opacity(0.55), location: 0),
            .init(color: tone.dark.opacity(0.22), location: 0.45),
            .init(color: tone.dark.opacity(0), location: 1),
        ]), center: centre, startRadius: CGFloat(r * 0.8), endRadius: CGFloat(corona)))
        // Slow rays.
        var rays = glow
        rays.translateBy(x: CGFloat(c.x), y: CGFloat(c.y))
        rays.rotate(by: .radians(clock * 0.15))
        for i in 0..<8 {
            var ray = rays
            ray.rotate(by: .radians(Double(i) * Double.pi / 4))
            let len = r * (1.7 + 0.25 * sin(clock * 1.7 + Double(i)))
            var p = Path()
            p.move(to: CGPoint(x: r * 0.7, y: -r * 0.10))
            p.addLine(to: CGPoint(x: len, y: 0))
            p.addLine(to: CGPoint(x: r * 0.7, y: r * 0.10))
            p.closeSubpath()
            ray.fill(p, with: .color(tone.mid.opacity(0.22)))
        }
        context.fill(circle(c, r), with: .radialGradient(Gradient(stops: [
            .init(color: tone.light, location: 0),
            .init(color: tone.mid, location: 0.55),
            .init(color: tone.dark, location: 1),
        ]), center: CGPoint(x: c.x - r * 0.2, y: c.y - r * 0.2), startRadius: 0, endRadius: CGFloat(r * 1.15)))
        // Sunspots drifting across.
        var face = context
        face.clip(to: circle(c, r))
        let spin = (clock * 6).truncatingRemainder(dividingBy: r * 2.4)
        for (dy, s) in [(-0.30, 0.10), (0.25, 0.07), (0.05, 0.05)] {
            let x = c.x - r * 1.2 + spin + dy * r
            face.fill(circle(OrbitVec(x, c.y + dy * r), r * s), with: .color(tone.dark.opacity(0.35)))
        }
    }

    private func drawHole(_ body: OrbitBody, at c: OrbitVec, in context: GraphicsContext, px: Double) {
        let r = body.radius
        let tone = OrbitPaint.tones(.blackHole)
        let centre = CGPoint(x: c.x, y: c.y)
        var glow = context
        glow.blendMode = .plusLighter
        // Light bent round the hole.
        glow.fill(circle(c, r * 5), with: .radialGradient(Gradient(stops: [
            .init(color: tone.glow.opacity(0.45), location: 0),
            .init(color: tone.glow.opacity(0.12), location: 0.35),
            .init(color: tone.glow.opacity(0), location: 1),
        ]), center: centre, startRadius: CGFloat(r), endRadius: CGFloat(r * 5)))
        // The disc of gas falling in, seen edge-on and turning.
        var disc = glow
        disc.translateBy(x: CGFloat(c.x), y: CGFloat(c.y))
        disc.rotate(by: .degrees(-12))
        disc.scaleBy(x: 1, y: 0.32)
        let dr = r * 2.6
        let gradient = Gradient(colors: [tone.light.opacity(0.95), tone.mid.opacity(0.5), tone.mid.opacity(0.05),
                                         tone.mid.opacity(0.5), tone.light.opacity(0.95)])
        disc.stroke(Path(ellipseIn: CGRect(x: -dr, y: -dr, width: dr * 2, height: dr * 2)),
                    with: .conicGradient(gradient, center: .zero, angle: .radians(clock * 1.6)),
                    lineWidth: CGFloat(r * 1.3))
        context.fill(circle(c, r), with: .color(.black))
        context.stroke(circle(c, r * 1.08), with: .color(tone.light.opacity(0.85)), lineWidth: CGFloat(max(1.2 * px, r * 0.10)))
    }

    // MARK: - Pad, stars and target

    private func drawPad(in context: GraphicsContext, px: Double) {
        let pad = level.pad
        var g = context
        g.translateBy(x: CGFloat(pad.at.x), y: CGFloat(pad.at.y))
        if pad.body != nil {
            // A gantry on the ground, pointing out from the planet.
            g.rotate(by: .radians(pad.facing + Double.pi / 2))
            let base = CGRect(x: -11, y: 3, width: 22, height: 5)
            g.fill(Path(roundedRect: base, cornerRadius: 1.5), with: .color(OrbitPaint.rgb(0.75, 0.78, 0.84)))
            g.fill(Path(CGRect(x: 7, y: -12, width: 3, height: 16)), with: .color(OrbitPaint.rgb(0.60, 0.64, 0.70)))
            let blink = sin(run.clock * 4) > 0 ? 0.95 : 0.35
            g.fill(circle(OrbitVec(8.5, -13), 1.8), with: .color(OrbitPaint.danger.opacity(blink)))
        } else {
            // A launch ring floating in space.
            g.rotate(by: .radians(run.clock * 0.4))
            let ring = Path(ellipseIn: CGRect(x: -13, y: -13, width: 26, height: 26))
            g.stroke(ring, with: .color(OrbitPaint.aim.opacity(0.55)), style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
            g.fill(Path(ellipseIn: CGRect(x: -7, y: -7, width: 14, height: 14)), with: .color(OrbitPaint.rgb(0.20, 0.26, 0.36)))
        }
    }

    /// A five-pointed star, `r` to its points.
    private func starShape(at c: OrbitVec, r: Double, turn: Double) -> Path {
        var p = Path()
        for i in 0..<10 {
            let a = turn - Double.pi / 2 + Double(i) * Double.pi / 5
            let rr = i % 2 == 0 ? r : r * 0.45
            let q = CGPoint(x: c.x + rr * cos(a), y: c.y + rr * sin(a))
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        return p
    }

    private func drawStars(in context: GraphicsContext, px: Double) {
        let got = run.collected
        var glow = context
        glow.blendMode = .plusLighter
        for (i, s) in level.stars.enumerated() where !(got.indices.contains(i) && got[i]) {
            let bob = 1 + 0.08 * sin(clock * 3 + Double(i) * 1.7)
            glow.fill(circle(s, 22 * bob), with: .radialGradient(Gradient(colors: [OrbitPaint.gold.opacity(0.45), OrbitPaint.gold.opacity(0)]),
                                                               center: CGPoint(x: s.x, y: s.y), startRadius: 0, endRadius: CGFloat(22 * bob)))
            let shape = starShape(at: s, r: 10 * bob, turn: clock * 0.6 + Double(i))
            context.fill(shape, with: .linearGradient(Gradient(colors: [OrbitPaint.rgb(1.0, 0.96, 0.70), OrbitPaint.goldDeep]),
                                                      startPoint: CGPoint(x: s.x, y: s.y - 10), endPoint: CGPoint(x: s.x, y: s.y + 10)))
            context.stroke(shape, with: .color(Color.white.opacity(0.6)), lineWidth: CGFloat(0.8 * px))
        }
    }

    private func drawTarget(in context: GraphicsContext, px: Double) {
        let target = level.target
        let c = target.position(at: t)
        if target.kind == .station {
            drawStation(at: c, radius: target.radius, in: context, px: px)
        } else {
            drawWormhole(at: c, radius: target.radius, in: context)
        }
    }

    private func drawStation(at c: OrbitVec, radius: Double, in context: GraphicsContext, px: Double) {
        // The docking zone, breathing.
        let pulse = 1 + 0.06 * sin(clock * 3)
        var glow = context
        glow.blendMode = .plusLighter
        glow.fill(circle(c, radius * 1.4), with: .radialGradient(Gradient(colors: [OrbitPaint.dock.opacity(0.28), OrbitPaint.dock.opacity(0)]),
                                                                 center: CGPoint(x: c.x, y: c.y), startRadius: CGFloat(radius * 0.3),
                                                                 endRadius: CGFloat(radius * 1.4)))
        context.stroke(circle(c, radius * pulse), with: .color(OrbitPaint.dock.opacity(0.7)),
                       style: StrokeStyle(lineWidth: CGFloat(1.6 * px), dash: [CGFloat(6 * px), CGFloat(5 * px)]))
        var g = context
        g.translateBy(x: CGFloat(c.x), y: CGFloat(c.y))
        g.rotate(by: .radians(clock * 0.5))
        let panel = OrbitPaint.rgb(0.25, 0.45, 0.85)
        for side in [-1.0, 1.0] {
            let rect = CGRect(x: side < 0 ? -radius * 0.95 : radius * 0.32, y: -radius * 0.16, width: radius * 0.63, height: radius * 0.32)
            g.fill(Path(rect), with: .linearGradient(Gradient(colors: [panel, OrbitPaint.rgb(0.10, 0.20, 0.50)]),
                                                     startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            g.stroke(Path(rect), with: .color(Color.white.opacity(0.35)), lineWidth: CGFloat(0.8 * px))
        }
        g.fill(Path(CGRect(x: -radius * 0.34, y: -radius * 0.05, width: radius * 0.68, height: radius * 0.1)),
               with: .color(OrbitPaint.rgb(0.70, 0.74, 0.80)))
        let hub = radius * 0.3
        g.fill(Path(ellipseIn: CGRect(x: -hub, y: -hub, width: hub * 2, height: hub * 2)),
               with: .radialGradient(Gradient(colors: [Color.white, OrbitPaint.rgb(0.55, 0.60, 0.68)]),
                                     center: CGPoint(x: -hub * 0.3, y: -hub * 0.3), startRadius: 0, endRadius: CGFloat(hub * 1.3)))
        let blink = sin(clock * 5) > 0.3 ? 1.0 : 0.25
        g.fill(Path(ellipseIn: CGRect(x: -2.2, y: -hub - 3.2, width: 4.4, height: 4.4)), with: .color(OrbitPaint.dock.opacity(blink)))
    }

    private func drawWormhole(at c: OrbitVec, radius: Double, in context: GraphicsContext) {
        var glow = context
        glow.blendMode = .plusLighter
        let centre = CGPoint(x: c.x, y: c.y)
        glow.fill(circle(c, radius * 1.7), with: .radialGradient(Gradient(colors: [OrbitPaint.warp.opacity(0.40), OrbitPaint.warp.opacity(0)]),
                                                                 center: centre, startRadius: CGFloat(radius * 0.5), endRadius: CGFloat(radius * 1.7)))
        var swirl = glow
        swirl.translateBy(x: centre.x, y: centre.y)
        for i in 0..<4 {
            let rr = radius * (1.0 - Double(i) * 0.2)
            let spin = clock * (1.2 + Double(i) * 0.5) * (i % 2 == 0 ? 1 : -1)
            let gradient = Gradient(colors: [OrbitPaint.warp.opacity(0.9), OrbitPaint.aim.opacity(0.1), OrbitPaint.warp.opacity(0.9)])
            swirl.stroke(Path(ellipseIn: CGRect(x: -rr, y: -rr, width: rr * 2, height: rr * 2)),
                         with: .conicGradient(gradient, center: .zero, angle: .radians(spin)),
                         lineWidth: CGFloat(radius * 0.12))
        }
        context.fill(circle(c, radius * 0.32), with: .radialGradient(Gradient(colors: [Color.black, OrbitPaint.warp.opacity(0.4)]),
                                                                     center: centre, startRadius: 0, endRadius: CGFloat(radius * 0.32)))
    }

    // MARK: - Aim

    private func drawAim(in context: GraphicsContext, px: Double) {
        let pad = level.pad
        let aim = run.aim
        // The arc of directions the pad allows, when it does not allow every way.
        if pad.arc < Double.pi {
            var arc = Path()
            let steps = 24
            for i in 0...steps {
                let a = pad.facing - pad.arc + 2 * pad.arc * Double(i) / Double(steps)
                let q = CGPoint(x: pad.at.x + 34 * cos(a), y: pad.at.y + 34 * sin(a))
                if i == 0 { arc.move(to: q) } else { arc.addLine(to: q) }
            }
            context.stroke(arc, with: .color(OrbitPaint.aim.opacity(0.22)), lineWidth: CGFloat(2 * px))
        }
        // The arrow: longer for more power.
        let dir = OrbitVec.heading(aim.angle)
        let tail = pad.at + dir * 12
        let tip = pad.at + dir * (24 + 46 * aim.power)
        var shaft = Path()
        shaft.move(to: CGPoint(x: tail.x, y: tail.y))
        shaft.addLine(to: CGPoint(x: tip.x, y: tip.y))
        let hot = OrbitPaint.rgb(1.0, 0.55 + 0.4 * (1 - aim.power), 0.3)
        context.stroke(shaft, with: .linearGradient(Gradient(colors: [OrbitPaint.aim.opacity(0.3), hot]),
                                                    startPoint: CGPoint(x: tail.x, y: tail.y), endPoint: CGPoint(x: tip.x, y: tip.y)),
                       style: StrokeStyle(lineWidth: 4, lineCap: .round))
        let side = OrbitVec(-dir.y, dir.x)
        var head = Path()
        let back = tip - dir * 9
        head.move(to: CGPoint(x: (tip + dir * 3).x, y: (tip + dir * 3).y))
        head.addLine(to: CGPoint(x: (back + side * 6).x, y: (back + side * 6).y))
        head.addLine(to: CGPoint(x: (back - side * 6).x, y: (back - side * 6).y))
        head.closeSubpath()
        context.fill(head, with: .color(hot))

        // The aiming line: dots that fade as the prediction runs out.
        let points = run.prediction.points
        if points.count > 1 {
            let n = points.count
            var i = 3
            while i < n {
                let k = Double(i) / Double(n)
                let p = points[i]
                let s = 2.4 * (1 - 0.5 * k)
                context.fill(circle(p, s), with: .color(OrbitPaint.aim.opacity(0.9 * (1 - k) + 0.1)))
                i += 4
            }
            if let end = run.prediction.end, let last = points.last, end != .arrived {
                drawCross(at: last, in: context)
            } else if run.prediction.end == .arrived, let last = points.last {
                context.stroke(circle(last, 9), with: .color(OrbitPaint.dock), lineWidth: CGFloat(2 * px))
            }
        }

        // The ghost: a probe running down the line while the moons move on
        // their rails, so the timing can be seen before the launch.
        if let ghostT = run.ghostTime, let g = run.ghostPoint(at: ghostT) {
            for body in level.bodies where body.rail != nil {
                let at = body.position(at: ghostT)
                context.stroke(circle(at, body.radius), with: .color(Color.white.opacity(0.28)),
                               style: StrokeStyle(lineWidth: CGFloat(1.2 * px), dash: [CGFloat(3 * px), CGFloat(3 * px)]))
            }
            if level.target.rail != nil {
                let at = level.target.position(at: ghostT)
                context.stroke(circle(at, level.target.radius), with: .color(OrbitPaint.dock.opacity(0.35)),
                               style: StrokeStyle(lineWidth: CGFloat(1.2 * px), dash: [CGFloat(3 * px), CGFloat(3 * px)]))
            }
            context.stroke(circle(g, 5), with: .color(Color.white.opacity(0.75)), lineWidth: CGFloat(1.5 * px))
        }

        // The probe waiting on the pad.
        drawProbeBody(at: pad.at, heading: aim.angle, in: context)
    }

    private func drawCross(at p: OrbitVec, in context: GraphicsContext) {
        var x = Path()
        x.move(to: CGPoint(x: p.x - 6, y: p.y - 6))
        x.addLine(to: CGPoint(x: p.x + 6, y: p.y + 6))
        x.move(to: CGPoint(x: p.x + 6, y: p.y - 6))
        x.addLine(to: CGPoint(x: p.x - 6, y: p.y + 6))
        context.stroke(x, with: .color(OrbitPaint.danger), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
    }

    // MARK: - Probe

    /// The last stretch of the path, fading behind the probe: drawn as a few
    /// runs of segments, each fainter and thinner than the one in front.
    private func drawTrail(in context: GraphicsContext, px: Double) {
        let points = run.path
        guard points.count > 1 else { return }
        let keep = min(points.count, 110)
        let start = points.count - keep
        let runs = 10
        let per = max(1, keep / runs)
        var glow = context
        glow.blendMode = .plusLighter
        var from = start
        while from < points.count - 1 {
            let to = min(points.count - 1, from + per)
            var seg = Path()
            seg.move(to: CGPoint(x: points[from].x, y: points[from].y))
            var j = from + 1
            while j <= to {
                seg.addLine(to: CGPoint(x: points[j].x, y: points[j].y))
                j += 1
            }
            let k = Double(to - start) / Double(max(keep - 1, 1))
            glow.stroke(seg, with: .color(OrbitPaint.aim.opacity(0.08 + 0.55 * k)),
                        style: StrokeStyle(lineWidth: CGFloat(1 + 3.2 * k), lineCap: .round, lineJoin: .round))
            from = to
        }
    }

    private func drawProbe(in context: GraphicsContext, px: Double) {
        guard let flight = run.flight else { return }
        switch run.phase {
        case .ended(let end):
            // Gone in a crash; a docked probe is inside the station.
            if end != .flat && end != .aborted { return }
        default:
            break
        }
        drawProbeBody(at: flight.position, heading: flight.velocity.angle, in: context)
    }

    private func drawProbeBody(at p: OrbitVec, heading: Double, in context: GraphicsContext) {
        var glow = context
        glow.blendMode = .plusLighter
        glow.fill(circle(p, 13), with: .radialGradient(Gradient(colors: [OrbitPaint.aim.opacity(0.55), OrbitPaint.aim.opacity(0)]),
                                                      center: CGPoint(x: p.x, y: p.y), startRadius: 0, endRadius: 13))
        var g = context
        g.translateBy(x: CGFloat(p.x), y: CGFloat(p.y))
        g.rotate(by: .radians(heading))
        var body = Path()
        body.move(to: CGPoint(x: 7, y: 0))
        body.addLine(to: CGPoint(x: -4, y: -4.2))
        body.addLine(to: CGPoint(x: -2, y: 0))
        body.addLine(to: CGPoint(x: -4, y: 4.2))
        body.closeSubpath()
        g.fill(body, with: .color(Color.white))
        g.fill(Path(ellipseIn: CGRect(x: 0.5, y: -1.4, width: 2.8, height: 2.8)), with: .color(OrbitPaint.aim))
    }

    // MARK: - Sparks

    private func drawSparks(in context: GraphicsContext, px: Double) {
        guard !run.sparks.isEmpty else { return }
        var glow = context
        glow.blendMode = .plusLighter
        for spark in run.sparks.items {
            let f = spark.fade
            let (hot, cool) = OrbitPaint.spark(spark.tone)
            let s = spark.size * (0.4 + 0.6 * f)
            glow.fill(circle(spark.at, s * 2.2), with: .color(cool.opacity(0.25 * f)))
            glow.fill(circle(spark.at, s), with: .color((f > 0.5 ? hot : cool).opacity(min(1, f * 1.3))))
        }
    }

    /// A probe swung out of sight: an arrow at the screen's edge pointing to it.
    private func drawEdgeMarker(in context: GraphicsContext, view: OrbitViewport) {
        guard run.isFlying, let flight = run.flight,
              let at = view.edgeMarker(for: flight.position, inset: 18) else { return }
        let s = view.screen(flight.position)
        let angle = atan2(s.y - at.y, s.x - at.x)
        var g = context
        g.translateBy(x: CGFloat(at.x), y: CGFloat(at.y))
        g.rotate(by: .radians(angle))
        var arrow = Path()
        arrow.move(to: CGPoint(x: 10, y: 0))
        arrow.addLine(to: CGPoint(x: -6, y: -7))
        arrow.addLine(to: CGPoint(x: -2, y: 0))
        arrow.addLine(to: CGPoint(x: -6, y: 7))
        arrow.closeSubpath()
        g.fill(arrow, with: .color(OrbitPaint.aim))
    }
}
