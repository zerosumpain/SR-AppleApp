import SwiftUI

// Car Racer+ on the circuit, drawn from above each frame: the stretches of
// track the camera can see, the scenery, the skid marks, the racing line
// and braking boards when those aids are on, the walls, the ghost and every
// car, tyre smoke and dust, floodlights and headlights after dark, and the
// names over nearby rivals. Plain drawing from `CarProRaceWorld`, which the
// race controller moves on; nothing here changes the race.

/// Everything one race's picture is drawn from. A class so the controller
/// can move it on each frame without SwiftUI copying it, and so the canvas
/// reads it without going through the main actor.
final class CarProRaceWorld {
    private(set) var session: CarProSession
    var effects = CarProEffects()
    var camera: CarProCamera
    /// Seconds of driving, stopped while paused: the effects' clock.
    var clock: Double = 0
    let scene: CarProSceneGeometry
    let line: CarProLinePaths
    let showLine: Bool
    let showBoards: Bool

    init(config: CarProSessionConfig) {
        let session = CarProSession(config: config)
        self.session = session
        camera = CarProCamera(vehicle: session.player.vehicle)
        scene = CarProSceneGeometry.of(session.track)
        line = CarProLinePaths(track: session.track, profile: session.player.profile)
        showLine = config.assists.racingLine
        showBoards = config.assists.brakingMarkers
    }

    /// Moves the race on by a frame.
    func step(dt: Double, input: CarProInput) {
        session.step(dt: dt, input: input)
        clock += dt
        effects.update(racers: session.racers, time: clock, dt: dt)
        camera.follow(session.player.vehicle, dt: dt)
    }

    /// The player gives up.
    func retire() { session.retire() }

    /// Back to the start of the same session.
    func restart() {
        session = CarProSession(config: session.config)
        effects.reset()
        camera = CarProCamera(vehicle: session.player.vehicle)
        clock = 0
    }
}

enum CarProRenderer {
    /// How far down the screen the player's car sits: a little above the
    /// dashboard and pedals (about 350 points of the bottom of any phone),
    /// so a small phone shows the car and a tall one more road ahead.
    static func anchor(height: Double) -> Double {
        guard height > 1 else { return 0.6 }
        return CarProMath.clamp((height - 350) / height, 0.45, 0.66)
    }

    static func draw(_ world: CarProRaceWorld, in context: inout GraphicsContext, size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        guard w > 1, h > 1 else { return }
        let scene = world.scene
        let paint = scene.palette
        let camera = world.camera
        let scale = w / camera.span
        // The farthest a visible point can be from the car: the top corners.
        let reach = max(w, h) / scale * 0.78 + 12
        var shakeX = 0.0, shakeY = 0.0
        if camera.shake > 0.01 {
            shakeX = sin(world.clock * 71) * camera.shake * 5
            shakeY = cos(world.clock * 53) * camera.shake * 5
        }
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paint.outside))

        var g = context
        g.translateBy(x: w / 2 + shakeX, y: h * anchor(height: h) + shakeY)
        g.rotate(by: .radians(-camera.heading - .pi / 2))
        g.scaleBy(x: scale, y: scale)
        g.translateBy(x: -camera.focus.x, y: -camera.focus.y)

        let visible = scene.chunks.filter { ($0.centre - camera.focus).length < reach + $0.radius }
        drawGround(g, visible, paint: paint, scene: scene)
        drawProps(g, scene, focus: camera.focus, reach: reach)
        drawMarks(g, world, reach: reach)
        if world.showLine { drawLine(g, world.line) }
        if world.showBoards { drawBoards(g, world.line, focus: camera.focus, reach: reach) }
        drawWalls(g, visible, paint: paint)

        if paint.night { drawNight(context, g, scene: scene, size: size, focus: camera.focus, reach: reach) }
        drawCars(g, world, reach: reach)
        if paint.night { drawHeadlights(g, world, reach: reach) }
        drawParticles(g, world, paint: paint)
        drawTags(context, world, size: size)
    }

    // MARK: - The circuit

    private static func drawGround(_ g: GraphicsContext, _ chunks: [CarProSceneChunk], paint: CarProPalette,
                                   scene: CarProSceneGeometry) {
        for c in chunks { g.fill(c.runoff, with: .color(paint.runoff)) }
        for c in chunks { g.fill(c.mowing, with: .color(paint.mowing)) }
        for c in chunks {
            g.fill(c.gravel, with: .color(paint.gravel))
            g.fill(c.gravelDots, with: .color(paint.gravelDot))
        }
        for c in chunks { g.fill(c.tarmac, with: .color(paint.tarmac)) }
        for c in chunks {
            g.fill(c.dirt, with: .color(paint.dirt))
            g.fill(c.wet, with: .color(paint.wet))
            g.stroke(c.wet, with: .color(Color.white.opacity(0.08)), lineWidth: 0.6)
        }
        for c in chunks {
            g.stroke(c.groove, with: .color(Color.black.opacity(0.13)), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
        }
        for c in chunks {
            g.fill(c.kerbs, with: .color(paint.kerb))
            g.fill(c.kerbStripes, with: .color(paint.kerbStripe))
            g.stroke(c.edges, with: .color(paint.edgeLine.opacity(0.9)), lineWidth: 0.22)
        }
        g.fill(scene.chequerWhite, with: .color(.white))
        g.fill(scene.chequerBlack, with: .color(Color(white: 0.08)))
        g.stroke(scene.gridBoxes, with: .color(Color.white.opacity(0.7)), lineWidth: 0.2)
    }

    private static func drawWalls(_ g: GraphicsContext, _ chunks: [CarProSceneChunk], paint: CarProPalette) {
        for c in chunks {
            g.stroke(c.walls, with: .color(Color.black.opacity(0.25)), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
            g.stroke(c.walls, with: .color(paint.wall), style: StrokeStyle(lineWidth: 0.8, lineJoin: .round))
            g.stroke(c.walls, with: .color(paint.wallTop.opacity(0.85)),
                     style: StrokeStyle(lineWidth: 0.3, lineJoin: .round, dash: [2.5, 2.5]))
        }
    }

    private static func drawLine(_ g: GraphicsContext, _ line: CarProLinePaths) {
        let style = StrokeStyle(lineWidth: 0.85, lineCap: .round, lineJoin: .round)
        g.stroke(line.accelerate, with: .color(Color(red: 0.25, green: 0.88, blue: 0.40).opacity(0.55)), style: style)
        g.stroke(line.hold, with: .color(Color(red: 1.0, green: 0.80, blue: 0.20).opacity(0.6)), style: style)
        g.stroke(line.brake, with: .color(Color(red: 1.0, green: 0.22, blue: 0.20).opacity(0.7)), style: style)
    }

    private static func drawBoards(_ g: GraphicsContext, _ line: CarProLinePaths, focus: CarProVec, reach: Double) {
        g.fill(line.bars, with: .color(Color(red: 1.0, green: 0.2, blue: 0.18).opacity(0.28)))
        for board in line.boards where (board.position - focus).length < reach {
            var b = g
            b.translateBy(x: board.position.x, y: board.position.y)
            b.rotate(by: .radians(board.direction))
            b.fill(Path(CGRect(x: -0.25, y: -0.85, width: 0.5, height: 1.7)), with: .color(.white))
            for k in 0..<board.count {
                let y = -0.7 + Double(k) * 0.5
                b.fill(Path(CGRect(x: -0.2, y: y, width: 0.4, height: 0.32)), with: .color(CarProPalette.red))
            }
        }
    }

    // MARK: - Marks and scenery

    private static func drawMarks(_ g: GraphicsContext, _ world: CarProRaceWorld, reach: Double) {
        let marks = world.effects.visibleSkids(at: world.clock, near: world.camera.focus, reach: reach)
        guard !marks.isEmpty else { return }
        var rubber = [Path(), Path(), Path(), Path()]
        var ruts = [Path(), Path(), Path(), Path()]
        for (mark, alpha) in marks {
            let bucket = min(3, max(0, Int(alpha * 4)))
            if mark.loose {
                ruts[bucket].move(to: CarProSceneGeometry.cg(mark.from))
                ruts[bucket].addLine(to: CarProSceneGeometry.cg(mark.to))
            } else {
                rubber[bucket].move(to: CarProSceneGeometry.cg(mark.from))
                rubber[bucket].addLine(to: CarProSceneGeometry.cg(mark.to))
            }
        }
        let paint = world.scene.palette
        for k in 0..<4 {
            let strength = (Double(k) + 0.5) / 4
            g.stroke(rubber[k], with: .color(paint.rubber.opacity(0.6 * strength)),
                     style: StrokeStyle(lineWidth: 0.3, lineCap: .round))
            g.stroke(ruts[k], with: .color(paint.rut.opacity(0.7 * strength)),
                     style: StrokeStyle(lineWidth: 0.38, lineCap: .round))
        }
    }

    private static func drawProps(_ g: GraphicsContext, _ scene: CarProSceneGeometry, focus: CarProVec, reach: Double) {
        let paint = scene.palette
        for prop in scene.props {
            guard (prop.position - focus).length < reach + prop.size else { continue }
            drawProp(g, prop, paint: paint)
        }
    }

    private static func drawProp(_ g: GraphicsContext, _ prop: CarProProp, paint: CarProPalette) {
        let shade = paint.shades[prop.shade % max(1, paint.shades.count)]
        let r = prop.size
        var p = g
        p.translateBy(x: prop.position.x, y: prop.position.y)
        let shadow = Color.black.opacity(0.22)
        switch prop.kind {
        case .tree, .pine, .bush:
            p.fill(circle(x: 0.6, y: 0.9, r: r), with: .color(shadow))
            p.fill(circle(x: 0, y: 0, r: r), with: .color(shade))
            if prop.kind == .pine {
                p.fill(circle(x: 0, y: 0, r: r * 0.55), with: .color(Color.black.opacity(0.14)))
                p.fill(circle(x: 0, y: 0, r: r * 0.18), with: .color(Color.black.opacity(0.2)))
            } else {
                p.fill(circle(x: -r * 0.28, y: -r * 0.28, r: r * 0.5), with: .color(Color.white.opacity(0.12)))
            }
        case .rock:
            p.rotate(by: .radians(prop.angle))
            p.fill(Path(ellipseIn: CGRect(x: -r + 0.4, y: -r * 0.7 + 0.5, width: r * 2, height: r * 1.4)), with: .color(shadow))
            p.fill(Path(ellipseIn: CGRect(x: -r, y: -r * 0.7, width: r * 2, height: r * 1.4)),
                   with: .color(Color(white: 0.5 + 0.06 * Double(prop.shade))))
            p.fill(Path(ellipseIn: CGRect(x: -r * 0.6, y: -r * 0.55, width: r, height: r * 0.6)),
                   with: .color(Color.white.opacity(0.14)))
        case .building, .hut:
            p.rotate(by: .radians(prop.angle))
            let rect = CGRect(x: -r, y: -r * 0.7, width: r * 2, height: r * 1.4)
            p.fill(Path(rect.offsetBy(dx: 1.2, dy: 1.5)), with: .color(shadow))
            p.fill(Path(rect), with: .color(shade))
            var ridge = Path()
            ridge.move(to: CGPoint(x: -r, y: 0))
            ridge.addLine(to: CGPoint(x: r, y: 0))
            p.stroke(ridge, with: .color(Color.black.opacity(0.25)), lineWidth: 0.3)
            p.fill(Path(CGRect(x: -r, y: -r * 0.7, width: r * 2, height: r * 0.7)), with: .color(Color.white.opacity(0.08)))
        case .container:
            p.rotate(by: .radians(prop.angle))
            let rect = CGRect(x: -3.05, y: -1.22, width: 6.1, height: 2.44)
            p.fill(Path(rect.offsetBy(dx: 0.6, dy: 0.8)), with: .color(shadow))
            p.fill(Path(rect), with: .color(shade))
            var ribs = Path()
            for k in 1..<8 {
                let x = -3.05 + Double(k) * 6.1 / 8
                ribs.move(to: CGPoint(x: x, y: -1.22))
                ribs.addLine(to: CGPoint(x: x, y: 1.22))
            }
            p.stroke(ribs, with: .color(Color.black.opacity(0.2)), lineWidth: 0.12)
        case .crane:
            p.rotate(by: .radians(prop.angle))
            p.fill(Path(CGRect(x: -3, y: -3, width: 6, height: 6)), with: .color(Color(white: 0.3)))
            p.fill(Path(CGRect(x: -r * 0.3, y: -0.7, width: r * 1.3, height: 1.4)),
                   with: .color(Color(red: 0.95, green: 0.72, blue: 0.12)))
        case .grandstand:
            p.rotate(by: .radians(prop.angle))
            let rect = CGRect(x: -r, y: -5, width: r * 2, height: 10)
            p.fill(Path(rect.offsetBy(dx: 1.5, dy: 2)), with: .color(shadow))
            p.fill(Path(rect), with: .color(Color(white: 0.78)))
            for row in 0..<4 {
                let colours: [Color] = [CarProPalette.red, Color(red: 0.2, green: 0.4, blue: 0.85), .white,
                                        Color(red: 0.95, green: 0.75, blue: 0.2)]
                p.fill(Path(CGRect(x: -r + 1, y: -4 + Double(row) * 2.1, width: r * 2 - 2, height: 1.1)),
                       with: .color(colours[(row + prop.shade) % colours.count].opacity(0.85)))
            }
        case .floodlight:
            p.fill(Path(CGRect(x: -0.6, y: -0.6, width: 1.2, height: 1.2)), with: .color(Color(white: 0.2)))
            p.fill(circle(x: 0, y: 0, r: 0.35), with: .color(Color(red: 1, green: 0.95, blue: 0.75)))
        case .tyres:
            for (x, y) in [(-0.9, 0.0), (0.9, 0.0), (0.0, -0.9)] {
                p.fill(circle(x: x, y: y, r: 0.6), with: .color(Color(white: 0.08)))
                p.fill(circle(x: x, y: y, r: 0.25), with: .color(Color(white: 0.3)))
            }
        case .dune:
            p.rotate(by: .radians(prop.angle))
            p.fill(Path(ellipseIn: CGRect(x: -r, y: -r * 0.55, width: r * 2, height: r * 1.1)),
                   with: .color(Color(red: 0.93, green: 0.85, blue: 0.66)))
            p.fill(Path(ellipseIn: CGRect(x: -r * 0.7, y: -r * 0.45, width: r * 1.2, height: r * 0.5)),
                   with: .color(Color.white.opacity(0.18)))
        case .heap:
            p.fill(circle(x: 1, y: 1.4, r: r), with: .color(shadow))
            p.fill(circle(x: 0, y: 0, r: r), with: .color(shade))
            p.fill(circle(x: -r * 0.15, y: -r * 0.15, r: r * 0.62), with: .color(Color.white.opacity(0.1)))
            p.fill(circle(x: -r * 0.25, y: -r * 0.25, r: r * 0.28), with: .color(Color.white.opacity(0.1)))
        }
    }

    private static func circle(x: Double, y: Double, r: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    // MARK: - Cars

    private static func drawCars(_ g: GraphicsContext, _ world: CarProRaceWorld, reach: Double) {
        let session = world.session
        let focus = world.camera.focus
        let player = session.playerIndex
        if let ghost = session.ghostPose, (ghost.position - focus).length < reach {
            var look = CarProCarLook(racer: session.player)
            look.ghost = true
            look.steerAngle = 0
            look.brake = 0
            var c = g
            c.translateBy(x: ghost.position.x, y: ghost.position.y)
            c.rotate(by: .radians(ghost.heading))
            CarProCarArt.draw(in: &c, look: look)
        }
        for (i, racer) in session.racers.enumerated() where i != player {
            drawCar(g, racer, focus: focus, reach: reach)
        }
        drawCar(g, session.player, focus: focus, reach: reach)
    }

    private static func drawCar(_ g: GraphicsContext, _ racer: CarProRacer, focus: CarProVec, reach: Double) {
        let v = racer.vehicle
        guard (v.position - focus).length < reach + 6 else { return }
        let look = CarProCarLook(racer: racer)
        var shadow = g
        shadow.translateBy(x: v.position.x + 0.35, y: v.position.y + 0.55)
        shadow.rotate(by: .radians(v.heading))
        shadow.fill(CarProCarArt.shadow(look), with: .color(Color.black.opacity(0.3)))
        var c = g
        c.translateBy(x: v.position.x, y: v.position.y)
        c.rotate(by: .radians(v.heading))
        CarProCarArt.draw(in: &c, look: look)
    }

    // MARK: - Smoke, dust and sparks

    private static func drawParticles(_ g: GraphicsContext, _ world: CarProRaceWorld, paint: CarProPalette) {
        let particles = world.effects.particles
        guard !particles.isEmpty else { return }
        var smoke = [Path(), Path(), Path()]
        var dust = [Path(), Path(), Path()]
        var grass = Path()
        var sparks = Path()
        let now = world.clock
        for p in particles {
            let age = p.age(at: now)
            let bucket = min(2, max(0, Int((1 - age) * 3)))
            switch p.kind {
            case .smoke:
                let r = p.size * (1 + age * 2.4)
                smoke[bucket].addEllipse(in: CGRect(x: p.position.x - r, y: p.position.y - r, width: r * 2, height: r * 2))
            case .dust:
                let r = p.size * (1 + age * 2.8)
                dust[bucket].addEllipse(in: CGRect(x: p.position.x - r, y: p.position.y - r, width: r * 2, height: r * 2))
            case .grass:
                let r = p.size
                grass.addRect(CGRect(x: p.position.x - r, y: p.position.y - r, width: r * 2, height: r * 2))
            case .spark:
                let r = p.size * (1 - age * 0.5)
                sparks.addEllipse(in: CGRect(x: p.position.x - r, y: p.position.y - r, width: r * 2, height: r * 2))
            }
        }
        for k in 0..<3 {
            let strength = (Double(k) + 0.5) / 3
            g.fill(smoke[k], with: .color(paint.smoke.opacity(0.42 * strength)))
            g.fill(dust[k], with: .color(paint.dust.opacity(0.5 * strength)))
        }
        g.fill(grass, with: .color(Color(red: 0.25, green: 0.42, blue: 0.18).opacity(0.85)))
        g.fill(sparks, with: .color(Color(red: 1, green: 0.85, blue: 0.35)))
    }

    // MARK: - After dark

    private static func drawNight(_ screen: GraphicsContext, _ g: GraphicsContext, scene: CarProSceneGeometry,
                                  size: CGSize, focus: CarProVec, reach: Double) {
        screen.fill(Path(CGRect(origin: .zero, size: size)),
                    with: .color(Color(red: 0.02, green: 0.03, blue: 0.10).opacity(0.55)))
        var lit = g
        lit.blendMode = .plusLighter
        let warm = Color(red: 1.0, green: 0.90, blue: 0.70)
        let pool = Gradient(colors: [warm.opacity(0.34), warm.opacity(0.12), warm.opacity(0)])
        for light in scene.lights where (light - focus).length < reach + 26 {
            let centre = CarProSceneGeometry.cg(light)
            lit.fill(circle(x: light.x, y: light.y, r: 26),
                     with: .radialGradient(pool, center: centre, startRadius: 0, endRadius: 26))
        }
    }

    private static func drawHeadlights(_ g: GraphicsContext, _ world: CarProRaceWorld, reach: Double) {
        var lit = g
        lit.blendMode = .plusLighter
        let focus = world.camera.focus
        let beam = Gradient(colors: [Color.white.opacity(0.34), Color.white.opacity(0)])
        for racer in world.session.racers {
            let v = racer.vehicle
            guard (v.position - focus).length < reach + 30 else { continue }
            let hl = racer.params.length / 2
            var c = lit
            c.translateBy(x: v.position.x, y: v.position.y)
            c.rotate(by: .radians(v.heading))
            var cone = Path()
            cone.addLines([CGPoint(x: hl, y: -0.7), CGPoint(x: hl + 30, y: -8), CGPoint(x: hl + 30, y: 8),
                           CGPoint(x: hl, y: 0.7)])
            cone.closeSubpath()
            c.fill(cone, with: .linearGradient(beam, startPoint: CGPoint(x: hl, y: 0), endPoint: CGPoint(x: hl + 30, y: 0)))
        }
    }

    // MARK: - Names

    /// "P3 Marsh" over each rival close to the player, upright on the screen.
    private static func drawTags(_ screen: GraphicsContext, _ world: CarProRaceWorld, size: CGSize) {
        let session = world.session
        guard session.config.kind.isRace else { return }
        let w = Double(size.width), h = Double(size.height)
        let focus = world.camera.focus
        for (i, racer) in session.racers.enumerated() where i != session.playerIndex {
            let p = racer.vehicle.position
            guard (p - focus).length < 42 else { continue }
            let at = world.camera.screen(p, width: w, height: h, anchor: anchor(height: h))
            let surname = racer.entrant.name.split(separator: " ").last.map(String.init) ?? racer.entrant.name
            let text = Text("P\(racer.position) \(surname)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            let resolved = screen.resolve(text)
            let measured = resolved.measure(in: CGSize(width: 200, height: 40))
            let box = CGRect(x: at.x - Double(measured.width) / 2 - 6, y: at.y - 34,
                             width: Double(measured.width) + 12, height: Double(measured.height) + 6)
            screen.fill(Path(roundedRect: box, cornerRadius: box.height / 2),
                        with: .color(CarProCarArt.liveryDark(racer.entrant.hue).opacity(0.85)))
            screen.draw(resolved, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
        }
    }
}
