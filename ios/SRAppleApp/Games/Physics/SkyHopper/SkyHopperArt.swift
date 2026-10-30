import SwiftUI

/// The clouds, drawn: a row of soft bumps on a rounded base, with the top
/// of the bumps on the line Hop lands on. Each kind has its own look —
/// sliding clouds trail wind streaks, crumbly ones are cracked and wobble,
/// blinking ones fade to a dashed outline and back.
enum SkyHopperCloudArt {
    static func draw(_ context: GraphicsContext, cloud: SkyHopperCloud, frame: SkyHopperFrame,
                     time: Double, now: Double, calm: Bool) {
        let u = frame.unit
        var top = frame.point(cloud.x, cloud.y)
        let half = CGFloat(cloud.halfWidth) * u
        var c = context
        if let gone = cloud.crumbledAt {
            let age = max(0, time - gone)
            guard age < 1.2 else { return }
            c.opacity = max(0, 1 - age / 1.0)
            top.y += CGFloat(36 * age * age) * u
        } else if cloud.kind == .crumbly && !calm {
            top.x += CGFloat(sin(now * 7 + Double(cloud.id))) * u * 0.25
        }

        let colours = palette(cloud.kind)
        if cloud.kind == .blinking {
            let alpha = cloud.alpha(at: time)
            outline(c, top: top, half: half, u: u, seed: cloud.id)
            c.opacity = 0.85 * alpha
        }
        if cloud.kind == .sliding && cloud.crumbledAt == nil { streaks(c, top: top, half: half, u: u, vx: cloud.vx) }

        if let gone = cloud.crumbledAt {
            // Broken in two, each half tipping away.
            let age = max(0, time - gone)
            for side in [-1.0, 1.0] {
                var piece = c
                piece.translateBy(x: CGFloat(side * age * 10) * u, y: 0)
                piece.clip(to: Path(CGRect(x: side < 0 ? top.x - half * 2 : top.x, y: top.y - u * 10,
                                           width: half * 2, height: u * 20)))
                body(piece, top: top, half: half, u: u, seed: cloud.id, colours: colours)
            }
            return
        }
        body(c, top: top, half: half, u: u, seed: cloud.id, colours: colours)
        if cloud.kind == .crumbly { cracks(c, top: top, half: half, u: u) }
        if let spring = cloud.spring {
            let fired = cloud.springAt.map { time - $0 < 0.16 } ?? false
            drawSpring(c, base: CGPoint(x: top.x + CGFloat(spring) * u, y: top.y), u: u, squashed: fired)
        }
    }

    private static func palette(_ kind: SkyHopperCloudKind) -> (main: Color, shade: Color) {
        switch kind {
        case .plain: return (SkyHopperInk.cloud, SkyHopperInk.cloudShade)
        case .sliding: return (SkyHopperInk.slide, SkyHopperInk.slideShade)
        case .crumbly: return (SkyHopperInk.crumb, SkyHopperInk.crumbShade)
        case .blinking: return (SkyHopperInk.blink, SkyHopperInk.cloudShade)
        }
    }

    /// The bumps and the base, as one path.
    static func shape(top: CGPoint, half: CGFloat, u: CGFloat, seed: Int) -> Path {
        var path = Path()
        let base = CGRect(x: top.x - half, y: top.y + u * 1.6, width: half * 2, height: u * 4.2)
        path.addRoundedRect(in: base, cornerSize: CGSize(width: u * 2.1, height: u * 2.1))
        let count = max(3, Int(half * 2 / (u * 5.5)))
        for k in 0..<count {
            let f = (CGFloat(k) + 0.5) / CGFloat(count)
            let wobble = CGFloat(SkyHopperBackdrop.noise(seed, k + 11))
            let r = u * (2.1 + 1.1 * wobble) * (k == 0 || k == count - 1 ? 0.8 : 1)
            let cx = top.x - half + half * 2 * f
            let cy = top.y + r
            path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }
        return path
    }

    private static func body(_ c: GraphicsContext, top: CGPoint, half: CGFloat, u: CGFloat, seed: Int,
                             colours: (main: Color, shade: Color)) {
        let path = shape(top: top, half: half, u: u, seed: seed)
        c.fill(path.offsetBy(dx: 0, dy: u * 0.9), with: .color(colours.shade))
        c.fill(path, with: .color(colours.main))
        let shine = CGRect(x: top.x - half * 0.55, y: top.y + u * 0.9, width: half * 0.5, height: u * 1.1)
        c.fill(Path(ellipseIn: shine), with: .color(Color.white.opacity(0.7)))
    }

    private static func outline(_ c: GraphicsContext, top: CGPoint, half: CGFloat, u: CGFloat, seed: Int) {
        let path = shape(top: top, half: half, u: u, seed: seed)
        c.stroke(path, with: .color(Color.white.opacity(0.55)),
                 style: StrokeStyle(lineWidth: max(1, u * 0.45), lineCap: .round, dash: [u * 1.2, u * 1.1]))
    }

    private static func streaks(_ c: GraphicsContext, top: CGPoint, half: CGFloat, u: CGFloat, vx: Double) {
        let behind: CGFloat = vx >= 0 ? -1 : 1
        for k in 0..<3 {
            let y = top.y + u * (1.6 + CGFloat(k) * 1.5)
            let start = top.x + behind * (half + u * 1.2)
            let length = u * (5 - CGFloat(k))
            var line = Path()
            line.move(to: CGPoint(x: start, y: y))
            line.addLine(to: CGPoint(x: start + behind * length, y: y))
            c.stroke(line, with: .color(SkyHopperInk.streak.opacity(0.9)),
                     style: StrokeStyle(lineWidth: max(1, u * 0.55), lineCap: .round))
        }
    }

    private static func cracks(_ c: GraphicsContext, top: CGPoint, half: CGFloat, u: CGFloat) {
        var crack = Path()
        crack.move(to: CGPoint(x: top.x - half * 0.15, y: top.y + u * 0.8))
        crack.addLine(to: CGPoint(x: top.x + half * 0.02, y: top.y + u * 2.4))
        crack.addLine(to: CGPoint(x: top.x - half * 0.1, y: top.y + u * 3.6))
        crack.addLine(to: CGPoint(x: top.x + half * 0.06, y: top.y + u * 5.2))
        crack.move(to: CGPoint(x: top.x + half * 0.5, y: top.y + u * 1.6))
        crack.addLine(to: CGPoint(x: top.x + half * 0.62, y: top.y + u * 3))
        crack.move(to: CGPoint(x: top.x - half * 0.62, y: top.y + u * 2))
        crack.addLine(to: CGPoint(x: top.x - half * 0.5, y: top.y + u * 3.4))
        c.stroke(crack, with: .color(SkyHopperInk.crack),
                 style: StrokeStyle(lineWidth: max(1, u * 0.4), lineCap: .round, lineJoin: .round))
    }

    /// A coil with a red pad on top, flattened for a moment when it fires.
    private static func drawSpring(_ c: GraphicsContext, base: CGPoint, u: CGFloat, squashed: Bool) {
        let height = u * (squashed ? 2.2 : 4.4)
        let width = u * 2.4
        var coil = Path()
        coil.move(to: CGPoint(x: base.x, y: base.y + u * 0.6))
        let turns = 4
        for k in 1...turns {
            let side: CGFloat = k % 2 == 0 ? -1 : 1
            coil.addLine(to: CGPoint(x: base.x + side * width / 2,
                                     y: base.y + u * 0.6 - height * CGFloat(k) / CGFloat(turns + 1)))
        }
        coil.addLine(to: CGPoint(x: base.x, y: base.y + u * 0.6 - height))
        c.stroke(coil, with: .color(SkyHopperInk.spring),
                 style: StrokeStyle(lineWidth: max(1.2, u * 0.6), lineCap: .round, lineJoin: .round))
        let pad = CGRect(x: base.x - u * 2.3, y: base.y + u * 0.6 - height - u * 1.2, width: u * 4.6, height: u * 1.4)
        c.fill(Path(roundedRect: pad, cornerRadius: u * 0.7), with: .color(SkyHopperInk.springTop))
    }
}

/// The things to collect, drawn round a centre point.
enum SkyHopperPickupArt {
    static func starPath(centre: CGPoint, radius: CGFloat, turn: Double = 0) -> Path {
        var path = Path()
        for k in 0..<10 {
            let r = k % 2 == 0 ? radius : radius * 0.46
            let a = turn - Double.pi / 2 + Double(k) * Double.pi / 5
            let p = CGPoint(x: centre.x + CGFloat(cos(a)) * r, y: centre.y + CGFloat(sin(a)) * r)
            if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    static func draw(_ context: GraphicsContext, kind: SkyHopperPickupKind, at point: CGPoint, unit u: CGFloat,
                     now: Double, calm: Bool, seed: Int) {
        let bob = calm ? 0 : CGFloat(sin(now * 3 + Double(seed))) * u * 0.6
        let centre = CGPoint(x: point.x, y: point.y + bob)
        let glow = u * (kind == .star ? 4.6 : 6.4)
        context.fill(Path(ellipseIn: CGRect(x: centre.x - glow, y: centre.y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)]),
                                           center: centre, startRadius: 0, endRadius: glow))
        switch kind {
        case .star:
            let turn = calm ? 0 : sin(now * 1.6 + Double(seed)) * 0.25
            let star = starPath(centre: centre, radius: u * 3.1, turn: turn)
            context.fill(star, with: .color(SkyHopperInk.star))
            context.stroke(star, with: .color(SkyHopperInk.starDeep), style: StrokeStyle(lineWidth: max(1, u * 0.4), lineJoin: .round))
        case .propeller:
            propeller(context, centre: centre, u: u, now: now, calm: calm)
        case .bubble:
            bubble(context, centre: centre, r: u * 4.2)
        case .magnet:
            magnet(context, centre: centre, u: u)
        }
    }

    /// A little cap with a propeller on top; worn by Hop while it lifts.
    static func propeller(_ c: GraphicsContext, centre: CGPoint, u: CGFloat, now: Double, calm: Bool) {
        var dome = Path()
        dome.addArc(center: CGPoint(x: centre.x, y: centre.y + u * 1.6), radius: u * 3.4,
                    startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        dome.closeSubpath()
        c.fill(dome, with: .color(SkyHopperInk.cap))
        c.fill(Path(CGRect(x: centre.x - u * 3.4, y: centre.y + u * 0.9, width: u * 6.8, height: u * 0.9)),
               with: .color(SkyHopperInk.capBand))
        let hub = CGPoint(x: centre.x, y: centre.y - u * 2.2)
        c.fill(Path(CGRect(x: hub.x - u * 0.3, y: hub.y, width: u * 0.6, height: u * 0.6)), with: .color(SkyHopperInk.spring))
        let spin = calm ? 0.4 : now * 14
        let reach = u * 3.6 * CGFloat(abs(cos(spin)))
        var blades = Path()
        blades.addEllipse(in: CGRect(x: hub.x - reach, y: hub.y - u * 0.6, width: reach * 2, height: u * 1.2))
        c.fill(blades, with: .color(SkyHopperInk.blade))
        c.fill(Path(ellipseIn: CGRect(x: hub.x - u * 0.7, y: hub.y - u * 0.7, width: u * 1.4, height: u * 1.4)),
               with: .color(SkyHopperInk.capBand))
    }

    static func bubble(_ c: GraphicsContext, centre: CGPoint, r: CGFloat) {
        let rect = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)
        c.fill(Path(ellipseIn: rect), with: .color(SkyHopperInk.bubble.opacity(0.22)))
        c.stroke(Path(ellipseIn: rect), with: .color(SkyHopperInk.bubble), lineWidth: max(1, r * 0.12))
        var shine = Path()
        shine.addArc(center: centre, radius: r * 0.68, startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
        c.stroke(shine, with: .color(Color.white.opacity(0.9)), style: StrokeStyle(lineWidth: max(1, r * 0.14), lineCap: .round))
    }

    private static func magnet(_ c: GraphicsContext, centre: CGPoint, u: CGFloat) {
        var arch = Path()
        arch.addArc(center: CGPoint(x: centre.x, y: centre.y), radius: u * 2.4,
                    startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        c.stroke(arch, with: .color(SkyHopperInk.magnet), style: StrokeStyle(lineWidth: u * 1.6, lineCap: .butt))
        for side in [-1.0, 1.0] {
            let x = centre.x + CGFloat(side) * u * 2.4
            c.fill(Path(CGRect(x: x - u * 0.8, y: centre.y - u * 2.6, width: u * 1.6, height: u * 2.6)),
                   with: .color(SkyHopperInk.magnet))
            c.fill(Path(CGRect(x: x - u * 0.8, y: centre.y - u * 3.6, width: u * 1.6, height: u * 1.1)),
                   with: .color(SkyHopperInk.magnetTip))
        }
    }
}

/// How Hop looks this frame: squashed on landing, stretched by speed,
/// eyes towards where it is going.
struct SkyHopperHopPose {
    let squashX: CGFloat
    let squashY: CGFloat
    /// −1 (looking left) … 1 (right).
    let look: CGFloat
    /// −1 (looking down) … 1 (up).
    let lookUp: CGFloat
    let surprised: Bool
    let propeller: Bool
    let bubble: Bool
    let magnet: Bool

    init(game: SkyHopperGame, now: Double, waiting: Bool, calm: Bool) {
        let h = game.hopper
        let since = game.time - h.landedAt
        var squash: CGFloat = 0
        if since >= 0 && since < 0.16 {
            let strength: CGFloat = calm ? 0.5 : 1
            squash = CGFloat(1 - since / 0.16) * strength
        }
        let speed = CGFloat(min(1, max(-1, h.vy / SkyHopperRules.springBounce)))
        let pace: CGFloat = abs(speed)
        var sx: CGFloat = 1 + 0.22 * squash - 0.06 * pace
        var sy: CGFloat = 1 - 0.26 * squash + 0.1 * pace
        if waiting && game.time == 0 && !calm {
            let breath = CGFloat(sin(now * 3)) * 0.035
            sx -= breath
            sy += breath
        }
        squashX = sx
        squashY = sy
        look = CGFloat(min(1, max(-1, h.vx / SkyHopperRules.topSpeed)))
        lookUp = speed
        surprised = h.vy < -200 || game.isOver
        propeller = game.propellerLeft > 0
        bubble = game.hasBubble
        magnet = game.magnetLeft > 0
    }
}

/// Hop, drawn standing on `feet`: a round puffball with big eyes, rosy
/// cheeks and two small feet.
struct SkyHopperHopArt {
    let paint: SkyHopperHopPaint
    let pose: SkyHopperHopPose
    let now: Double
    let calm: Bool

    func draw(_ context: GraphicsContext, feet: CGPoint, unit u: CGFloat) {
        let w = u * 10 * pose.squashX
        let h = u * 9 * pose.squashY
        let rect = CGRect(x: feet.x - w / 2, y: feet.y - h, width: w, height: h)
        let main = paint.rainbow ? SkyHopperHopPaint.rainbowColour(now: now) : paint.main
        if pose.magnet { magnetRing(context, centre: CGPoint(x: rect.midX, y: rect.midY), u: u) }

        // Feet, then the body over them.
        for side in [-1.0, 1.0] {
            let foot = CGRect(x: feet.x + CGFloat(side) * u * 2.2 - u * 1.5, y: feet.y - u * 1.1, width: u * 3, height: u * 1.5)
            context.fill(Path(ellipseIn: foot), with: .color(paint.dark))
        }
        context.fill(Path(ellipseIn: rect.offsetBy(dx: 0, dy: u * 0.5)), with: .color(paint.dark))
        context.fill(Path(ellipseIn: rect),
                     with: .radialGradient(Gradient(colors: [paint.light, main, main]),
                                           center: CGPoint(x: rect.minX + w * 0.35, y: rect.minY + h * 0.3),
                                           startRadius: 0, endRadius: w * 0.8))
        let belly = CGRect(x: rect.midX - w * 0.28, y: rect.minY + h * 0.55, width: w * 0.56, height: h * 0.34)
        context.fill(Path(ellipseIn: belly), with: .color(paint.light.opacity(0.75)))
        tuft(context, top: CGPoint(x: rect.midX, y: rect.minY), u: u, colour: paint.dark)
        face(context, rect: rect, u: u)
        if pose.propeller {
            SkyHopperPickupArt.propeller(context, centre: CGPoint(x: rect.midX, y: rect.minY - u * 0.9),
                                         u: u * 0.85, now: now, calm: calm)
        }
        if pose.bubble {
            let r = max(w, h) * 0.82
            SkyHopperPickupArt.bubble(context, centre: CGPoint(x: rect.midX, y: rect.midY), r: r)
        }
    }

    private func face(_ c: GraphicsContext, rect: CGRect, u: CGFloat) {
        let eyeY = rect.minY + rect.height * 0.4
        let dx = pose.look * u * 0.7
        let dy = -pose.lookUp * u * 0.5
        for side in [-1.0, 1.0] {
            let ex = rect.midX + CGFloat(side) * u * 1.9 + dx * 0.4
            let eye = CGRect(x: ex - u * 1.4, y: eyeY - u * 1.6, width: u * 2.8, height: u * 3.2)
            c.fill(Path(ellipseIn: eye), with: .color(Color.white))
            let px = ex + dx
            let py = eyeY + dy
            c.fill(Path(ellipseIn: CGRect(x: px - u * 0.8, y: py - u * 0.9, width: u * 1.6, height: u * 1.8)),
                   with: .color(SkyHopperInk.eye))
            c.fill(Path(ellipseIn: CGRect(x: px - u * 0.45, y: py - u * 0.7, width: u * 0.6, height: u * 0.6)),
                   with: .color(Color.white))
            let cheek = CGRect(x: rect.midX + CGFloat(side) * u * 3.3 - u * 0.9, y: eyeY + u * 1.6, width: u * 1.8, height: u * 1.1)
            c.fill(Path(ellipseIn: cheek), with: .color(SkyHopperInk.cheek.opacity(0.75)))
        }
        let mouthY = eyeY + u * 2.4
        if pose.surprised {
            c.fill(Path(ellipseIn: CGRect(x: rect.midX + dx * 0.3 - u * 0.6, y: mouthY - u * 0.4, width: u * 1.2, height: u * 1.3)),
                   with: .color(SkyHopperInk.eye))
        } else {
            var smile = Path()
            smile.move(to: CGPoint(x: rect.midX + dx * 0.3 - u * 1.0, y: mouthY))
            smile.addQuadCurve(to: CGPoint(x: rect.midX + dx * 0.3 + u * 1.0, y: mouthY),
                               control: CGPoint(x: rect.midX + dx * 0.3, y: mouthY + u * 1.1))
            c.stroke(smile, with: .color(SkyHopperInk.eye), style: StrokeStyle(lineWidth: max(1, u * 0.4), lineCap: .round))
        }
    }

    private func tuft(_ c: GraphicsContext, top: CGPoint, u: CGFloat, colour: Color) {
        var hair = Path()
        for k in -1...1 {
            let x = top.x + CGFloat(k) * u * 0.8
            hair.move(to: CGPoint(x: x, y: top.y + u * 0.4))
            hair.addQuadCurve(to: CGPoint(x: x + CGFloat(k) * u * 0.9, y: top.y - u * 1.4),
                              control: CGPoint(x: x - u * 0.5, y: top.y - u * 0.6))
        }
        c.stroke(hair, with: .color(colour), style: StrokeStyle(lineWidth: max(1, u * 0.45), lineCap: .round))
    }

    private func magnetRing(_ c: GraphicsContext, centre: CGPoint, u: CGFloat) {
        let pulse = calm ? 0 : CGFloat(sin(now * 5)) * u * 0.8
        let r = u * 9 + pulse
        c.stroke(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)),
                 with: .color(SkyHopperInk.magnet.opacity(0.55)),
                 style: StrokeStyle(lineWidth: max(1, u * 0.45), dash: [u * 1.4, u * 1.2]))
    }
}
