import SwiftUI

/// The sky, redrawn every frame from the session's clock: the backdrop,
/// the clouds, the stars and power-ups, Hop, and the sparks.
struct SkyHopperSkyView: View {
    @ObservedObject var clock: SkyHopperClock
    let session: SkyHopperSession
    let hop: SkyHopperHopPaint
    let dark: Bool
    let calm: Bool

    var body: some View {
        let scene = SkyHopperScene(game: session.game, fraction: session.fraction, now: clock.now,
                                   sparks: session.sparks, pops: session.pops, endedAt: session.endedAt,
                                   savedAt: session.savedAt, waiting: session.stage != .playing,
                                   hop: hop, dark: dark, calm: calm)
        Canvas(rendersAsynchronously: false) { context, size in
            scene.draw(in: context, size: size)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// From the world (100 units across, y up) to the board (points, y down).
struct SkyHopperFrame {
    let size: CGSize
    let unit: CGFloat
    let camera: Double

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x) * unit, y: size.height - CGFloat(y - camera) * unit)
    }

    func visible(_ y: Double, margin: Double = 20) -> Bool {
        let screen = size.height - CGFloat(y - camera) * unit
        let pad = CGFloat(margin) * unit
        return screen > -pad && screen < size.height + pad
    }
}

/// One frame of the sky, as values: drawn, never kept.
struct SkyHopperScene {
    let game: SkyHopperGame
    let fraction: Double
    let now: Double
    let sparks: [SkyHopperSpark]
    let pops: [SkyHopperPop]
    let endedAt: Double?
    let savedAt: Double
    /// Not under way: Hop breathes on the spot.
    let waiting: Bool
    let hop: SkyHopperHopPaint
    let dark: Bool
    let calm: Bool

    static let radius: CGFloat = 22

    private var sinceEnd: Double? { endedAt.map { max(0, now - $0) } }

    func draw(in context: GraphicsContext, size: CGSize) {
        let unit = size.width / CGFloat(SkyHopperRules.width)
        let camera = game.previousCamera + (game.cameraY - game.previousCamera) * fraction
        let frame = SkyHopperFrame(size: size, unit: unit, camera: camera)
        var c = context
        c.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: Self.radius))
        let paint = SkyHopperSkyPaint.at(metres: camera / SkyHopperRules.unitsPerMetre, dark: dark)
        c.fill(Path(CGRect(origin: .zero, size: size)),
               with: .linearGradient(Gradient(colors: [paint.top, paint.bottom]),
                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        if let since = sinceEnd, !calm, since < 0.35 {
            let fade = 1 - since / 0.35
            c.translateBy(x: CGFloat(sin(since * 60) * fade) * unit * 0.9, y: 0)
        }
        SkyHopperBackdrop.draw(c, frame: frame, paint: paint, now: now, dark: dark, calm: calm)
        for cloud in game.clouds where frame.visible(cloud.y) {
            SkyHopperCloudArt.draw(c, cloud: cloud, frame: frame, time: game.time, now: now, calm: calm)
        }
        for pickup in game.pickups where frame.visible(pickup.y) {
            SkyHopperPickupArt.draw(c, kind: pickup.kind, at: frame.point(pickup.x, pickup.y),
                                    unit: unit, now: now, calm: calm, seed: pickup.id)
        }
        drawHop(c, frame: frame)
        drawSparks(c, frame: frame)
        drawPops(c, frame: frame)
        drawEnding(c, size: size)
    }

    // MARK: - Hop

    private func drawHop(_ context: GraphicsContext, frame: SkyHopperFrame) {
        let h = game.hopper
        let x = SkyHopperRules.wrap(game.previousX + SkyHopperRules.wrapDelta(from: game.previousX, to: h.x) * fraction)
        let y = game.previousY + (h.y - game.previousY) * fraction
        let pose = SkyHopperHopPose(game: game, now: now, waiting: waiting, calm: calm)
        let art = SkyHopperHopArt(paint: hop, pose: pose, now: now, calm: calm)
        art.draw(context, feet: frame.point(x, y), unit: frame.unit)
        // Halfway off one side, Hop is also coming in on the other.
        if x < 7 { art.draw(context, feet: frame.point(x + SkyHopperRules.width, y), unit: frame.unit) }
        if x > SkyHopperRules.width - 7 { art.draw(context, feet: frame.point(x - SkyHopperRules.width, y), unit: frame.unit) }
        let saved = now - savedAt
        if saved >= 0 && saved < 0.6 {
            let r = frame.unit * CGFloat(8 + saved * 40)
            let centre = frame.point(x, y + SkyHopperRules.hopperHeight / 2)
            var c = context
            c.opacity = 1 - saved / 0.6
            c.stroke(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)),
                     with: .color(SkyHopperInk.bubble), lineWidth: frame.unit * 1.2)
        }
    }

    // MARK: - Sparks and pops

    private func drawSparks(_ context: GraphicsContext, frame: SkyHopperFrame) {
        for spark in sparks {
            let age = now - spark.born
            guard age >= 0, age < spark.life else { continue }
            let t = age / spark.life
            let x = spark.x + spark.vx * age
            let y = spark.y + spark.vy * age - 30 * age * age
            let at = frame.point(x, y)
            let r = frame.unit * CGFloat(spark.size * (1 - t * 0.5))
            var c = context
            c.opacity = 1 - t
            let rect = CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2)
            switch spark.kind {
            case .puff:
                c.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.9)))
            case .crumb:
                c.fill(Path(rect), with: .color(SkyHopperInk.crumbShade))
            case .star:
                c.fill(SkyHopperPickupArt.starPath(centre: at, radius: r * 1.3), with: .color(SkyHopperInk.star))
            case .bubble:
                c.stroke(Path(ellipseIn: rect), with: .color(SkyHopperInk.bubble), lineWidth: max(1, r * 0.4))
            case .power:
                c.fill(Path(ellipseIn: rect), with: .color(Color(hue: (spark.size * 0.37).truncatingRemainder(dividingBy: 1),
                                                                 saturation: 0.6, brightness: 1)))
            }
        }
    }

    private func drawPops(_ context: GraphicsContext, frame: SkyHopperFrame) {
        for pop in pops {
            let age = now - pop.born
            guard age >= 0, age < 0.9 else { continue }
            let t = age / 0.9
            let rise = 3 + 9 * (1 - (1 - t) * (1 - t))
            let at = frame.point(pop.x, pop.y + rise)
            var c = context
            c.opacity = t < 0.6 ? 1 : 1 - (t - 0.6) / 0.4
            let size = frame.unit * (pop.gold ? 4.6 : 3.8)
            let shadow = c.resolve(Text(pop.text).font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundColor(Color.black.opacity(0.35)))
            let label = c.resolve(Text(pop.text).font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundColor(pop.gold ? SkyHopperInk.star : Color.white))
            c.draw(shadow, at: CGPoint(x: at.x + 1, y: at.y + 1.5), anchor: .center)
            c.draw(label, at: at, anchor: .center)
        }
    }

    /// After the fall: the bottom of the sky dims for a moment.
    private func drawEnding(_ context: GraphicsContext, size: CGSize) {
        guard let since = sinceEnd else { return }
        let strength = 0.35 * max(0, 1 - since / 1.1)
        guard strength > 0 else { return }
        let rect = CGRect(x: 0, y: size.height * 0.55, width: size.width, height: size.height * 0.45)
        context.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color.black.opacity(0), Color.black.opacity(strength)]),
                                                       startPoint: CGPoint(x: 0, y: rect.minY),
                                                       endPoint: CGPoint(x: 0, y: rect.maxY)))
    }
}

/// Far away and slow: the sun, the hills at the start, soft clouds, and
/// stars as the sky darkens. Each layer moves at its own fraction of the
/// camera, so the sky has depth.
enum SkyHopperBackdrop {
    /// 0 ..< 1 from two whole numbers, the same every frame.
    static func noise(_ i: Int, _ salt: Int) -> Double {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return v - floor(v)
    }

    static func draw(_ c: GraphicsContext, frame: SkyHopperFrame, paint: SkyHopperSkyPaint, now: Double,
                     dark: Bool, calm: Bool) {
        let w = frame.size.width, h = frame.size.height
        let lift = CGFloat(frame.camera) * frame.unit
        if paint.starlight > 0 { stars(c, w: w, h: h, lift: lift, light: paint.starlight, now: now, calm: calm) }
        if paint.sun > 0 {
            let r = w * 0.12
            let centre = CGPoint(x: w * 0.8, y: h * 0.16 + lift * 0.12)
            if centre.y - r * 2.4 < h {
                var s = c
                s.opacity = paint.sun
                s.fill(Path(ellipseIn: CGRect(x: centre.x - r * 2.4, y: centre.y - r * 2.4, width: r * 4.8, height: r * 4.8)),
                       with: .radialGradient(Gradient(colors: [SkyHopperInk.sun.opacity(0.55), SkyHopperInk.sun.opacity(0)]),
                                             center: centre, startRadius: r * 0.6, endRadius: r * 2.4))
                s.fill(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)),
                       with: .color(SkyHopperInk.sun))
            }
        }
        farClouds(c, w: w, h: h, lift: lift, dark: dark)
        hills(c, w: w, h: h, lift: lift, dark: dark)
    }

    private static func stars(_ c: GraphicsContext, w: CGFloat, h: CGFloat, lift: CGFloat, light: Double,
                              now: Double, calm: Bool) {
        let band = h + 40
        for i in 0..<46 {
            let x = CGFloat(noise(i, 1)) * w
            var y = (CGFloat(noise(i, 2)) * band + lift * 0.06).truncatingRemainder(dividingBy: band)
            if y < 0 { y += band }
            y -= 20
            let twinkle = calm ? 0.8 : 0.55 + 0.45 * sin(now * 2.2 + Double(i))
            let r = CGFloat(0.7 + noise(i, 3) * 1.1)
            var s = c
            s.opacity = light * twinkle
            s.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(Color.white))
        }
    }

    private static func farClouds(_ c: GraphicsContext, w: CGFloat, h: CGFloat, lift: CGFloat, dark: Bool) {
        let band = h + 160
        var s = c
        s.opacity = dark ? 0.14 : 0.3
        for k in 0..<6 {
            let cx = CGFloat(noise(k, 4)) * w
            var y = (CGFloat(noise(k, 5)) * band + lift * 0.3).truncatingRemainder(dividingBy: band)
            if y < 0 { y += band }
            y -= 80
            let span = w * CGFloat(0.22 + noise(k, 6) * 0.14)
            var path = Path()
            path.addEllipse(in: CGRect(x: cx - span, y: y - span * 0.18, width: span * 2, height: span * 0.42))
            path.addEllipse(in: CGRect(x: cx - span * 0.55, y: y - span * 0.42, width: span * 0.9, height: span * 0.6))
            path.addEllipse(in: CGRect(x: cx - span * 0.05, y: y - span * 0.34, width: span * 0.75, height: span * 0.5))
            s.fill(path, with: .color(Color.white))
        }
    }

    /// Rolling hills under the home cloud, sinking away as Hop climbs.
    private static func hills(_ c: GraphicsContext, w: CGFloat, h: CGFloat, lift: CGFloat, dark: Bool) {
        let farTop = h - w * 0.2 + lift * 0.35
        let nearTop = h - w * 0.1 + lift * 0.55
        guard farTop < h || nearTop < h else { return }
        let dim = dark ? 0.75 : 1.0
        var far = Path()
        far.addEllipse(in: CGRect(x: -w * 0.3, y: farTop, width: w * 0.95, height: w * 0.6))
        far.addEllipse(in: CGRect(x: w * 0.4, y: farTop + w * 0.04, width: w * 0.95, height: w * 0.6))
        var s = c
        s.opacity = dim
        s.fill(far, with: .color(SkyHopperInk.hillFar))
        var near = Path()
        near.addEllipse(in: CGRect(x: -w * 0.1, y: nearTop, width: w * 0.7, height: w * 0.5))
        near.addEllipse(in: CGRect(x: w * 0.45, y: nearTop - w * 0.02, width: w * 0.8, height: w * 0.5))
        s.fill(near, with: .color(SkyHopperInk.hill))
    }
}
