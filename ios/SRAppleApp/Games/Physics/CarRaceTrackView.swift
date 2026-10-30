import SwiftUI

/// The race drawn from above: the ground (grass, water, sand, snow or city),
/// the scenery beside the road, the circuit with its kerbs, grid boxes and a
/// chequered line, the skid marks and tyre smoke the cars leave, the other
/// cars and my own, and a map of the whole lap in the corner.
///
/// The camera rides behind my car with the road pointing up the screen, so
/// tilting right always turns right whichever way the track runs. The world
/// is a fixed palette — tarmac and grass do not change with light and dark
/// mode, the way a game's board does not.
struct CarRaceTrackView: View {
    @ObservedObject var driver: CarRaceDriver
    /// Colours by seat.
    var colour: (Int) -> Color = { OfflineSeatColour.of($0) }
    /// My seat, for my car's colour.
    var seat = 0
    /// The marks and smoke my car leaves: kept between frames, never published.
    @State private var effects = CarRaceEffects()

    var body: some View {
        let scene = self.scene
        Canvas(rendersAsynchronously: false) { context, size in
            scene.draw(in: context, size: size)
        }
        .background(CarRaceScene.ground(driver.track.scenery))
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityIdentifier("car-race-track")
    }

    private var label: String {
        let lap = "Lap \(driver.counter.lap) of \(driver.laps)"
        let speed = "\(Int((driver.car.speed * 3.6).rounded())) kilometres an hour"
        return "\(driver.track.name). \(lap), \(speed)."
    }

    /// The rivals (faded unless my car can hit them), then my car on top.
    private var scene: CarRaceScene {
        var cars: [CarRaceScene.Car] = driver.rivals.compactMap { rival in
            guard let pose = driver.pose(of: rival) else { return nil }
            return CarRaceScene.Car(at: pose.at, heading: pose.heading, colour: colour(rival.seat),
                                    ghost: !driver.isSolid(rival))
        }
        let car = driver.car
        // Noted here, once a frame as the driver publishes: the marks are
        // a picture of where the car has been, not part of the race.
        effects.note("me", car: car, time: driver.raceTime)
        cars.append(CarRaceScene.Car(at: car.position, heading: car.heading, colour: colour(seat),
                                     smoke: car.drifting, boost: car.boosting, mine: true))
        return CarRaceScene(track: driver.track, road: driver.road, focus: car.position,
                            heading: driver.cameraHeading, cars: cars, effects: effects, time: driver.raceTime)
    }
}

/// What the cars leave behind them: black skid marks from the rear tyres
/// while they slide, and puffs of tyre smoke that swell and fade. A picture
/// only — nothing here touches the race — kept in a class so a frame can
/// add to it without SwiftUI redrawing because of it.
final class CarRaceEffects {
    /// One stretch of rubber laid by one tyre.
    struct Skid {
        let from: CarVec
        let to: CarVec
    }

    /// A puff of smoke, born at `born` (race seconds), drifting slowly.
    struct Puff {
        let at: CarVec
        let born: Double
        let drift: CarVec
    }

    /// How long a puff lives, seconds.
    static let puffLife = 0.9
    private static let skidLimit = 700

    private(set) var skids: [Skid] = []
    private(set) var puffs: [Puff] = []
    private var tyres: [String: (left: CarVec, right: CarVec)] = [:]
    private var lastPuff: [String: Double] = [:]
    private var lastTime = -Double.infinity

    /// Where car `id` is now. A sliding car lays rubber from where its rear
    /// tyres were to where they are, and puffs smoke every few hundredths.
    func note(_ id: String, car: CarState, time: Double) {
        // A new race (the clock went back): start clean.
        if time < lastTime - 1 { clear() }
        lastTime = max(lastTime, time)
        if !puffs.isEmpty { puffs.removeAll { time - $0.born > Self.puffLife || $0.born > time + 0.5 } }

        let forward = CarVec.heading(car.heading)
        let right = CarVec(x: -forward.y, y: forward.x)
        let rear = car.position - forward * 1.35
        let left = rear - right * 0.85, rightTyre = rear + right * 0.85
        guard car.drifting else {
            tyres[id] = nil
            return
        }
        if let last = tyres[id] {
            let moved = (left - last.left).length
            if moved > 6 {
                // A jump, not a slide (a restart, a lost link): no line across the map.
                tyres[id] = (left, rightTyre)
            } else if moved > 0.3 {
                skids.append(Skid(from: last.left, to: left))
                skids.append(Skid(from: last.right, to: rightTyre))
                tyres[id] = (left, rightTyre)
                if skids.count > Self.skidLimit { skids.removeFirst(skids.count - Self.skidLimit + 100) }
            }
        } else {
            tyres[id] = (left, rightTyre)
        }
        if time - (lastPuff[id] ?? -1) >= 0.05 {
            lastPuff[id] = time
            let drift = car.velocity * -0.08
            puffs.append(Puff(at: left, born: time, drift: drift + right * -0.6))
            puffs.append(Puff(at: rightTyre, born: time, drift: drift + right * 0.6))
            if puffs.count > 90 { puffs.removeFirst(puffs.count - 90) }
        }
    }

    func clear() {
        skids.removeAll()
        puffs.removeAll()
        tyres.removeAll()
        lastPuff.removeAll()
        lastTime = -Double.infinity
    }
}

/// One camera's picture of the race: the track turned round the car it
/// follows, every car, and the lap map. Plain values, so a race on one phone,
/// a nearby race and each part of a split screen draw the same way.
struct CarRaceScene {
    struct Car {
        var at: CarVec
        var heading: Double
        var colour: Color
        /// Drawn see-through: a ghost, or a car out of reach.
        var ghost = false
        /// Tyre smoke: the car is drifting.
        var smoke = false
        /// Flames from the exhaust: the car is boosting.
        var boost = false
        /// The camera's own car: ringed on the map.
        var mine = false
    }

    let track: CarTrack
    /// The track's middle line as a path (`road(for:)`).
    let road: Path
    /// The point the camera follows, and the way it faces.
    let focus: CarVec
    let heading: Double
    /// Drawn in order: the camera's own car last, on top.
    let cars: [Car]
    /// Metres across the picture's width.
    var span: Double = 64
    /// The lap map's side, points.
    var mapSize: Double = 92
    /// Skid marks and smoke, if this picture shows them.
    var effects: CarRaceEffects? = nil
    /// Race seconds: the smoke's age and the flames' flicker.
    var time: Double = 0

    static let grass = Color(red: 0.33, green: 0.52, blue: 0.29)
    /// The boost: the flames, and the Boost pad lit.
    static let flame = Color(red: 1.0, green: 0.55, blue: 0.12)
    private static let flameCore = Color(red: 1.0, green: 0.88, blue: 0.35)
    private static let tyre = Color(red: 0.08, green: 0.08, blue: 0.09)
    private static let glass = Color(red: 0.10, green: 0.14, blue: 0.20)
    private static let lamp = Color(red: 1.0, green: 0.96, blue: 0.78)

    /// What the world is painted with on a scenery's track.
    struct Palette {
        let ground: Color
        let tarmac: Color
        /// The kerb's two colours, alternating.
        let kerb: Color
        let kerbStripe: Color
        /// A band either side of the road, under the kerb: sand, a pavement. Nil for none.
        let verge: Color?
        /// The scenery's shades, picked by each prop's `shade`.
        let props: [Color]
    }

    static func palette(_ scenery: CarScenery) -> Palette {
        let tarmac = Color(red: 0.24, green: 0.25, blue: 0.27)
        let red = Color(red: 0.86, green: 0.18, blue: 0.16)
        switch scenery {
        case .meadow:
            return Palette(ground: grass, tarmac: tarmac, kerb: red, kerbStripe: .white, verge: nil, props: [])
        case .harbour:
            return Palette(ground: Color(red: 0.16, green: 0.42, blue: 0.60), tarmac: tarmac, kerb: red, kerbStripe: .white,
                           verge: Color(red: 0.86, green: 0.78, blue: 0.58),
                           props: [.white, Color(red: 0.95, green: 0.93, blue: 0.86), Color(red: 0.86, green: 0.26, blue: 0.20)])
        case .forest:
            return Palette(ground: Color(red: 0.22, green: 0.38, blue: 0.20), tarmac: tarmac, kerb: red, kerbStripe: .white,
                           verge: nil,
                           props: [Color(red: 0.11, green: 0.27, blue: 0.13), Color(red: 0.15, green: 0.33, blue: 0.15),
                                   Color(red: 0.20, green: 0.40, blue: 0.17)])
        case .desert:
            return Palette(ground: Color(red: 0.84, green: 0.66, blue: 0.43), tarmac: Color(red: 0.30, green: 0.28, blue: 0.27),
                           kerb: Color(red: 0.93, green: 0.45, blue: 0.13), kerbStripe: .white, verge: nil,
                           props: [Color(red: 0.62, green: 0.42, blue: 0.27), Color(red: 0.70, green: 0.50, blue: 0.32),
                                   Color(red: 0.36, green: 0.52, blue: 0.29)])
        case .snow:
            return Palette(ground: Color(red: 0.93, green: 0.95, blue: 0.97), tarmac: Color(red: 0.30, green: 0.32, blue: 0.36),
                           kerb: Color(red: 0.18, green: 0.40, blue: 0.80), kerbStripe: .white, verge: nil,
                           props: [Color(red: 0.12, green: 0.30, blue: 0.22), Color(red: 0.16, green: 0.36, blue: 0.26)])
        case .city:
            return Palette(ground: Color(red: 0.20, green: 0.21, blue: 0.24), tarmac: Color(red: 0.16, green: 0.16, blue: 0.18),
                           kerb: Color(red: 0.96, green: 0.80, blue: 0.14), kerbStripe: Color(red: 0.12, green: 0.12, blue: 0.12),
                           verge: Color(red: 0.50, green: 0.50, blue: 0.52),
                           props: [Color(red: 0.42, green: 0.36, blue: 0.40), Color(red: 0.55, green: 0.33, blue: 0.27),
                                   Color(red: 0.36, green: 0.42, blue: 0.50), Color(red: 0.62, green: 0.58, blue: 0.50)])
        }
    }

    /// The ground behind everything, for the view's background.
    static func ground(_ scenery: CarScenery) -> Color { palette(scenery).ground }

    /// Tyre smoke's colour on each ground: dust on sand, spray on snow.
    private static func smoke(_ scenery: CarScenery) -> Color {
        switch scenery {
        case .desert: return Color(red: 0.93, green: 0.84, blue: 0.68)
        case .snow: return Color(red: 0.96, green: 0.98, blue: 1.0)
        default: return Color(red: 0.92, green: 0.92, blue: 0.94)
        }
    }

    /// The track's middle line as a closed path, built once per race.
    static func road(for track: CarTrack) -> Path {
        var road = Path()
        if let first = track.points.first {
            road.move(to: CGPoint(x: first.x, y: first.y))
            for p in track.points.dropFirst() { road.addLine(to: CGPoint(x: p.x, y: p.y)) }
            road.closeSubpath()
        }
        return road
    }

    func draw(in context: GraphicsContext, size: CGSize) {
        let scale = Double(size.width) / span
        var world = context
        // The followed car sits low on the screen, pointing up; the world turns round it.
        world.translateBy(x: size.width / 2, y: size.height * 0.68)
        world.rotate(by: .radians(-heading - .pi / 2))
        world.scaleBy(x: scale, y: scale)
        world.translateBy(x: -focus.x, y: -focus.y)

        let width = track.width
        let paint = Self.palette(track.scenery)
        if let verge = paint.verge {
            world.stroke(road, with: .color(verge), style: StrokeStyle(lineWidth: width + track.verge * 2, lineJoin: .round))
        }
        drawProps(in: world, paint: paint, size: size, scale: scale)
        world.stroke(road, with: .color(paint.kerbStripe), style: StrokeStyle(lineWidth: width + 2.4, lineJoin: .round))
        world.stroke(road, with: .color(paint.kerb),
                     style: StrokeStyle(lineWidth: width + 2.4, lineJoin: .round, dash: [3, 3]))
        world.stroke(road, with: .color(paint.tarmac), style: StrokeStyle(lineWidth: width, lineJoin: .round))
        // The racing line, worn a shade darker, and the dashed centre line.
        world.stroke(road, with: .color(.black.opacity(0.10)), style: StrokeStyle(lineWidth: width * 0.35, lineJoin: .round))
        world.stroke(road, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 0.3, dash: [4, 6]))
        drawGrid(in: world)
        drawLine(in: world)
        drawSkids(in: world)
        drawSmoke(in: world, paint: track.scenery)

        for (index, car) in cars.enumerated() {
            drawCar(in: world, car, flicker: index)
        }

        drawMap(in: context, size: size)
    }

    /// The start and finish: a chequered strip across the road.
    private func drawLine(in context: GraphicsContext) {
        let start = track.point(at: 0)
        var line = context
        line.translateBy(x: start.at.x, y: start.at.y)
        line.rotate(by: .radians(start.direction))
        let width = track.width
        let cells = 8
        let cell = width / Double(cells)
        for row in 0..<2 {
            for i in 0..<cells {
                let rect = CGRect(x: Double(row) * cell - cell, y: -width / 2 + Double(i) * cell, width: cell, height: cell)
                line.fill(Path(rect), with: .color((i + row) % 2 == 0 ? .white : .black))
            }
        }
    }

    /// The grid: a painted box for each of the first four places behind the line.
    private func drawGrid(in context: GraphicsContext) {
        for slot in 0..<4 {
            let spot = track.grid(slot)
            var box = context
            box.translateBy(x: spot.at.x, y: spot.at.y)
            box.rotate(by: .radians(spot.heading))
            var mark = Path()
            // An open-backed box: the front bar and two sides.
            mark.move(to: CGPoint(x: -2.8, y: -1.6))
            mark.addLine(to: CGPoint(x: 2.8, y: -1.6))
            mark.addLine(to: CGPoint(x: 2.8, y: 1.6))
            mark.addLine(to: CGPoint(x: -2.8, y: 1.6))
            box.stroke(mark, with: .color(.white.opacity(0.55)), lineWidth: 0.25)
        }
    }

    /// The rubber the cars have laid while sliding, near the camera only.
    private func drawSkids(in context: GraphicsContext) {
        guard let effects, !effects.skids.isEmpty else { return }
        let reach = span * 1.3
        var marks = Path()
        for skid in effects.skids {
            let d = skid.to - focus
            guard abs(d.x) < reach, abs(d.y) < reach else { continue }
            marks.move(to: CGPoint(x: skid.from.x, y: skid.from.y))
            marks.addLine(to: CGPoint(x: skid.to.x, y: skid.to.y))
        }
        context.stroke(marks, with: .color(.black.opacity(track.scenery == .city ? 0.45 : 0.32)),
                       style: StrokeStyle(lineWidth: 0.42, lineCap: .round))
    }

    /// Tyre smoke: each puff swells and fades over its short life.
    private func drawSmoke(in context: GraphicsContext, paint scenery: CarScenery) {
        guard let effects, !effects.puffs.isEmpty else { return }
        let colour = Self.smoke(scenery)
        for puff in effects.puffs {
            let age = min(1, max(0, (time - puff.born) / CarRaceEffects.puffLife))
            let r = 0.6 + 1.8 * age
            let at = puff.at + puff.drift * (age * CarRaceEffects.puffLife)
            context.fill(Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2)),
                         with: .color(colour.opacity(0.55 * (1 - age))))
        }
    }

    /// The scenery near the camera: trees, rocks, pines, boats or buildings,
    /// each with a soft shadow to the lower right so it stands off the ground.
    private func drawProps(in context: GraphicsContext, paint: Palette, size: CGSize, scale: Double) {
        guard !paint.props.isEmpty, scale > 0 else { return }
        let shadow = Color.black.opacity(0.22)
        // Only what the camera can see: each prop turned into the picture's
        // own frame (metres right of and below the car) and kept if it is in it.
        let halfWide = Double(size.width) / 2 / scale
        let above = Double(size.height) * 0.68 / scale, below = Double(size.height) * 0.32 / scale
        let turn = -heading - .pi / 2
        for prop in track.props {
            let seen = (prop.at - focus).rotated(by: turn)
            let r0 = prop.size * 1.5
            guard abs(seen.x) < halfWide + r0, seen.y > -above - r0, seen.y < below + r0 else { continue }
            let colour = paint.props[min(paint.props.count - 1, Int(prop.shade * Double(paint.props.count)))]
            let r = prop.size
            switch track.scenery {
            case .meadow:
                break
            case .forest, .snow:
                // A tree from above: a canopy and a lighter crown — on snow, a cap of snow.
                let canopy = Path(ellipseIn: CGRect(x: prop.at.x - r, y: prop.at.y - r, width: r * 2, height: r * 2))
                context.fill(canopy.offsetBy(dx: r * 0.3, dy: r * 0.3), with: .color(shadow))
                context.fill(canopy, with: .color(colour))
                let crown = r * 0.45
                context.fill(Path(ellipseIn: CGRect(x: prop.at.x - crown - r * 0.15, y: prop.at.y - crown - r * 0.15,
                                                    width: crown * 2, height: crown * 2)),
                             with: .color(track.scenery == .snow ? .white.opacity(0.85) : .white.opacity(0.12)))
            case .desert:
                // A rock, squashed along its own `turn`; the last shade, green,
                // is a round scrubby bush instead.
                var c = context
                c.translateBy(x: prop.at.x, y: prop.at.y)
                c.rotate(by: .radians(prop.turn))
                let bush = prop.shade * Double(paint.props.count) >= Double(paint.props.count - 1)
                let rock = Path(ellipseIn: bush ? CGRect(x: -r * 0.7, y: -r * 0.7, width: r * 1.4, height: r * 1.4)
                                                : CGRect(x: -r, y: -r * 0.7, width: r * 2, height: r * 1.4))
                c.fill(rock.offsetBy(dx: r * 0.25, dy: r * 0.25), with: .color(shadow))
                c.fill(rock, with: .color(colour))
            case .harbour:
                // A boat at anchor: a hull pointing along `turn`, and a deck.
                var c = context
                c.translateBy(x: prop.at.x, y: prop.at.y)
                c.rotate(by: .radians(prop.turn))
                let hull = Path(roundedRect: CGRect(x: -r * 1.6, y: -r * 0.6, width: r * 3.2, height: r * 1.2),
                                cornerRadius: r * 0.55)
                c.fill(hull.offsetBy(dx: r * 0.2, dy: r * 0.3), with: .color(shadow))
                c.fill(hull, with: .color(colour))
                c.fill(Path(roundedRect: CGRect(x: -r * 0.6, y: -r * 0.35, width: r * 1.1, height: r * 0.7),
                            cornerRadius: r * 0.15), with: .color(Color(red: 0.55, green: 0.40, blue: 0.28)))
            case .city:
                // A block from above: its roof, a shadow, and a skylight.
                let roof = Path(CGRect(x: prop.at.x - r, y: prop.at.y - r, width: r * 2, height: r * 2))
                context.fill(roof.offsetBy(dx: r * 0.25, dy: r * 0.25), with: .color(.black.opacity(0.35)))
                context.fill(roof, with: .color(colour))
                context.stroke(roof, with: .color(.white.opacity(0.15)), lineWidth: 0.3)
                context.fill(Path(CGRect(x: prop.at.x - r * 0.35, y: prop.at.y - r * 0.35, width: r * 0.7, height: r * 0.7)),
                             with: .color(Color(red: 1.0, green: 0.85, blue: 0.45).opacity(prop.shade < 0.5 ? 0.7 : 0.25)))
            }
        }
    }

    /// A little racing car from above, 4.4 m long and 2.2 wide, pointing
    /// along +x: tyres poking out at the corners, a tapered body in the
    /// driver's colour with a stripe, a cockpit, a rear wing and headlamps.
    private func drawCar(in context: GraphicsContext, _ car: Car, flicker: Int) {
        var c = context
        c.translateBy(x: car.at.x, y: car.at.y)
        c.rotate(by: .radians(car.heading))
        if car.ghost { c.opacity = 0.5 }
        if track.scenery == .city && !car.ghost {
            // Night Streets: the headlamps throw a soft beam up the road.
            var beam = Path()
            beam.move(to: CGPoint(x: 2.1, y: -0.6))
            beam.addLine(to: CGPoint(x: 11, y: -2.6))
            beam.addLine(to: CGPoint(x: 11, y: 2.6))
            beam.addLine(to: CGPoint(x: 2.1, y: 0.6))
            beam.closeSubpath()
            c.fill(beam, with: .linearGradient(Gradient(colors: [Self.lamp.opacity(0.35), Self.lamp.opacity(0)]),
                                               startPoint: CGPoint(x: 2, y: 0), endPoint: CGPoint(x: 11, y: 0)))
        }
        if car.boost {
            // Two flames out of the back, a bright core in each, flickering.
            let flare = 0.8 + 0.25 * sin(time * 47 + Double(flicker) * 1.7)
            for dy in [-0.5, 0.5] {
                let long = 2.8 * flare
                c.fill(Path(ellipseIn: CGRect(x: -2.2 - long, y: dy - 0.45, width: long + 0.4, height: 0.9)), with: .color(Self.flame))
                c.fill(Path(ellipseIn: CGRect(x: -2.2 - long * 0.55, y: dy - 0.22, width: long * 0.55 + 0.3, height: 0.44)),
                       with: .color(Self.flameCore))
            }
        }
        // Shadow, then the tyres, then the body over their inner halves.
        c.fill(Path(roundedRect: CGRect(x: -2.0, y: -0.85, width: 4.5, height: 2.2), cornerRadius: 0.7), with: .color(.black.opacity(0.28)))
        for (x, y) in [(1.15, -1.12), (1.15, 0.62), (-1.65, -1.15), (-1.65, 0.6)] {
            c.fill(Path(roundedRect: CGRect(x: x, y: y, width: 1.0, height: 0.55), cornerRadius: 0.18), with: .color(Self.tyre))
        }
        let body = Self.carBody
        c.fill(body, with: .color(car.colour))
        // A sheen down one side, so the body reads as rounded.
        c.fill(Path(roundedRect: CGRect(x: -1.8, y: -0.95, width: 3.4, height: 0.4), cornerRadius: 0.2), with: .color(.white.opacity(0.18)))
        // The stripe, the cockpit, the rear wing.
        c.fill(Path(CGRect(x: -2.1, y: -0.17, width: 4.1, height: 0.34)), with: .color(.white.opacity(0.75)))
        c.fill(Path(roundedRect: CGRect(x: -0.2, y: -0.62, width: 1.25, height: 1.24), cornerRadius: 0.4), with: .color(Self.glass))
        c.fill(Path(roundedRect: CGRect(x: 0.55, y: -0.5, width: 0.35, height: 1.0), cornerRadius: 0.15), with: .color(.white.opacity(0.22)))
        c.fill(Path(roundedRect: CGRect(x: -2.35, y: -1.08, width: 0.42, height: 2.16), cornerRadius: 0.12), with: .color(Self.tyre))
        c.stroke(body, with: .color(.white.opacity(car.ghost ? 0.9 : 0.7)),
                 style: StrokeStyle(lineWidth: 0.14, dash: car.ghost ? [0.5, 0.4] : []))
        // Headlamps on the nose.
        for y in [-0.42, 0.42] {
            c.fill(Path(ellipseIn: CGRect(x: 1.85, y: y - 0.16, width: 0.32, height: 0.32)), with: .color(Self.lamp))
        }
    }

    /// The car's body: square-shouldered at the back, tapering to a rounded nose.
    private static let carBody: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -2.1, y: -0.95))
        p.addLine(to: CGPoint(x: 0.6, y: -1.02))
        p.addQuadCurve(to: CGPoint(x: 2.2, y: -0.35), control: CGPoint(x: 2.0, y: -0.95))
        p.addQuadCurve(to: CGPoint(x: 2.2, y: 0.35), control: CGPoint(x: 2.35, y: 0))
        p.addQuadCurve(to: CGPoint(x: 0.6, y: 1.02), control: CGPoint(x: 2.0, y: 0.95))
        p.addLine(to: CGPoint(x: -2.1, y: 0.95))
        p.addQuadCurve(to: CGPoint(x: -2.1, y: -0.95), control: CGPoint(x: -2.4, y: 0))
        p.closeSubpath()
        return p
    }()

    /// The whole lap, small, top right, with a dot for every car.
    private func drawMap(in context: GraphicsContext, size: CGSize) {
        let side = CGFloat(mapSize)
        let box = CGRect(x: size.width - side - 12, y: 12, width: side, height: side)
        let b = track.bounds
        let w = b.maxX - b.minX, h = b.maxY - b.minY
        guard w > 0, h > 0, side > 16 else { return }
        let k = min(Double(box.width - 16) / w, Double(box.height - 16) / h)
        var map = context
        map.fill(Path(roundedRect: box, cornerRadius: side * 0.15), with: .color(.black.opacity(0.42)))
        map.stroke(Path(roundedRect: box, cornerRadius: side * 0.15), with: .color(.white.opacity(0.18)), lineWidth: 1)
        map.translateBy(x: Double(box.midX) - (b.minX + w / 2) * k, y: Double(box.midY) - (b.minY + h / 2) * k)
        map.scaleBy(x: k, y: k)
        map.stroke(road, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 3 / k, lineJoin: .round))
        // The start line, a short bar across the road.
        let start = track.point(at: 0)
        let across = CarVec(x: -sin(start.direction), y: cos(start.direction)) * (6 / k)
        var bar = Path()
        bar.move(to: CGPoint(x: start.at.x - across.x, y: start.at.y - across.y))
        bar.addLine(to: CGPoint(x: start.at.x + across.x, y: start.at.y + across.y))
        map.stroke(bar, with: .color(Self.flameCore), lineWidth: 2 / k)
        let dot = 5 / k
        for car in cars where !car.mine {
            map.fill(Path(ellipseIn: CGRect(x: car.at.x - dot / 2, y: car.at.y - dot / 2, width: dot, height: dot)),
                     with: .color(car.colour))
        }
        let big = dot * 1.6
        for car in cars where car.mine {
            map.fill(Path(ellipseIn: CGRect(x: car.at.x - big / 2, y: car.at.y - big / 2, width: big, height: big)), with: .color(.white))
            map.fill(Path(ellipseIn: CGRect(x: car.at.x - dot / 2, y: car.at.y - dot / 2, width: dot, height: dot)), with: .color(car.colour))
        }
    }
}

/// A track's whole lap as a little picture, in its own scenery's colours:
/// for the track cards and the grid. Drawn once; it does not move.
struct CarRaceTrackMap: View {
    let track: CarTrack
    /// Show the scenery's props as specks around the road.
    var detailed = true

    var body: some View {
        let track = self.track
        let detailed = self.detailed
        Canvas { context, size in
            CarRaceTrackMap.draw(track, detailed: detailed, in: context, size: size)
        }
        .background(CarRaceScene.ground(track.scenery))
        .accessibilityHidden(true)
    }

    static func draw(_ track: CarTrack, detailed: Bool, in context: GraphicsContext, size: CGSize) {
        let b = track.bounds
        let w = b.maxX - b.minX, h = b.maxY - b.minY
        let inset = 10.0
        guard w > 0, h > 0, Double(size.width) > inset * 2, Double(size.height) > inset * 2 else { return }
        let k = min((Double(size.width) - inset * 2) / w, (Double(size.height) - inset * 2) / h)
        var map = context
        map.translateBy(x: Double(size.width) / 2 - (b.minX + w / 2) * k, y: Double(size.height) / 2 - (b.minY + h / 2) * k)
        map.scaleBy(x: k, y: k)
        let paint = CarRaceScene.palette(track.scenery)
        let road = CarRaceScene.road(for: track)
        if detailed, !paint.props.isEmpty {
            for (i, prop) in track.props.enumerated() where i % 2 == 0 {
                let colour = paint.props[min(paint.props.count - 1, Int(prop.shade * Double(paint.props.count)))]
                let r = max(prop.size, 2.2 / k)
                map.fill(Path(ellipseIn: CGRect(x: prop.at.x - r, y: prop.at.y - r, width: r * 2, height: r * 2)),
                         with: .color(colour.opacity(0.9)))
            }
        }
        let roadWidth = max(track.width, 4 / k)
        if let verge = paint.verge {
            map.stroke(road, with: .color(verge), style: StrokeStyle(lineWidth: roadWidth + max(track.verge * 2, 2 / k), lineJoin: .round))
        }
        map.stroke(road, with: .color(paint.kerb), style: StrokeStyle(lineWidth: roadWidth + 2 / k, lineJoin: .round))
        map.stroke(road, with: .color(paint.tarmac), style: StrokeStyle(lineWidth: roadWidth, lineJoin: .round))
        // The start, chequered, and an arrow just after it the way the lap runs.
        let start = track.point(at: 0)
        var line = map
        line.translateBy(x: start.at.x, y: start.at.y)
        line.rotate(by: .radians(start.direction))
        let cell = roadWidth / 4
        for row in 0..<2 {
            for i in 0..<4 {
                let rect = CGRect(x: Double(row) * cell - cell, y: -roadWidth / 2 + Double(i) * cell, width: cell, height: cell)
                line.fill(Path(rect), with: .color((i + row) % 2 == 0 ? .white : .black))
            }
        }
        let ahead = track.point(at: min(track.length * 0.1, 40))
        var arrow = map
        arrow.translateBy(x: ahead.at.x, y: ahead.at.y)
        arrow.rotate(by: .radians(ahead.direction))
        let a = roadWidth * 0.45
        var tip = Path()
        tip.move(to: CGPoint(x: a, y: 0))
        tip.addLine(to: CGPoint(x: -a * 0.7, y: -a * 0.75))
        tip.addLine(to: CGPoint(x: -a * 0.7, y: a * 0.75))
        tip.closeSubpath()
        arrow.fill(tip, with: .color(.white.opacity(0.9)))
    }
}

extension CarScenery {
    /// The scenery in a word or two, for a track card.
    var carRaceTitle: String {
        switch self {
        case .meadow: return "Meadow"
        case .harbour: return "Seaside"
        case .forest: return "Forest"
        case .desert: return "Desert"
        case .snow: return "Snow"
        case .city: return "City at night"
        }
    }

    /// An SF Symbol for the scenery.
    var carRaceSymbol: String {
        switch self {
        case .meadow: return "leaf.fill"
        case .harbour: return "water.waves"
        case .forest: return "tree.fill"
        case .desert: return "sun.max.fill"
        case .snow: return "snowflake"
        case .city: return "building.2.fill"
        }
    }
}
