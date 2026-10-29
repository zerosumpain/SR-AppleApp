import SwiftUI

/// The race drawn from above: the ground (grass, water, sand, snow or city),
/// the scenery beside the road, the circuit with its kerbs and a chequered
/// line, the other cars and my own, and a map of the whole lap in the corner.
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
        cars.append(CarRaceScene.Car(at: car.position, heading: car.heading, colour: colour(seat),
                                     smoke: car.drifting, boost: car.boosting, mine: true))
        return CarRaceScene(track: driver.track, road: driver.road, focus: car.position,
                            heading: driver.cameraHeading, cars: cars)
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

    static let grass = Color(red: 0.33, green: 0.52, blue: 0.29)
    /// The boost: the flames, and the Boost pad lit.
    static let flame = Color(red: 1.0, green: 0.55, blue: 0.12)
    private static let flameCore = Color(red: 1.0, green: 0.88, blue: 0.35)

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
        world.stroke(road, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 0.3, dash: [4, 6]))
        drawLine(in: world)

        for car in cars {
            drawCar(in: world, car)
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

    private func drawCar(in context: GraphicsContext, _ car: Car) {
        var c = context
        c.translateBy(x: car.at.x, y: car.at.y)
        c.rotate(by: .radians(car.heading))
        if car.ghost { c.opacity = 0.55 }
        if car.boost {
            // Two flames out of the back, a bright core in each.
            for dy in [-0.5, 0.5] {
                c.fill(Path(ellipseIn: CGRect(x: -4.4, y: dy - 0.42, width: 2.6, height: 0.84)), with: .color(Self.flame))
                c.fill(Path(ellipseIn: CGRect(x: -3.5, y: dy - 0.22, width: 1.5, height: 0.44)), with: .color(Self.flameCore))
            }
        }
        if car.smoke {
            for (dx, dy) in [(-2.8, -1.0), (-2.8, 1.0), (-4.2, 0.0)] {
                c.fill(Path(ellipseIn: CGRect(x: dx - 0.8, y: dy - 0.8, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.45)))
            }
        }
        // 4.4 m long, 2.2 wide, pointing along +x.
        let body = Path(roundedRect: CGRect(x: -2.2, y: -1.1, width: 4.4, height: 2.2), cornerRadius: 0.6)
        c.fill(Path(roundedRect: CGRect(x: -2.0, y: -0.9, width: 4.4, height: 2.2), cornerRadius: 0.6), with: .color(.black.opacity(0.25)))
        c.fill(body, with: .color(car.colour))
        c.stroke(body, with: .color(.white.opacity(0.8)), lineWidth: 0.15)
        c.fill(Path(roundedRect: CGRect(x: 0.2, y: -0.75, width: 0.9, height: 1.5), cornerRadius: 0.25), with: .color(.black.opacity(0.55)))
        c.fill(Path(CGRect(x: -2.1, y: -0.2, width: 3.9, height: 0.4)), with: .color(.white.opacity(0.5)))
    }

    /// The whole lap, small, top right, with a dot for every car.
    private func drawMap(in context: GraphicsContext, size: CGSize) {
        let side = CGFloat(mapSize)
        let box = CGRect(x: size.width - side - 12, y: 12, width: side, height: side)
        let b = track.bounds
        let w = b.maxX - b.minX, h = b.maxY - b.minY
        guard w > 0, h > 0, side > 16 else { return }
        let k = min(Double(box.width - 16) / w, Double(box.height - 16) / h)
        var map = context
        map.fill(Path(roundedRect: box, cornerRadius: side * 0.15), with: .color(.black.opacity(0.35)))
        map.translateBy(x: Double(box.midX) - (b.minX + w / 2) * k, y: Double(box.midY) - (b.minY + h / 2) * k)
        map.scaleBy(x: k, y: k)
        map.stroke(road, with: .color(.white.opacity(0.85)), lineWidth: 3 / k)
        let dot = 5 / k
        for car in cars where !car.mine {
            map.fill(Path(ellipseIn: CGRect(x: car.at.x - dot / 2, y: car.at.y - dot / 2, width: dot, height: dot)),
                     with: .color(car.colour))
        }
        let big = dot * 1.5
        for car in cars where car.mine {
            map.fill(Path(ellipseIn: CGRect(x: car.at.x - big / 2, y: car.at.y - big / 2, width: big, height: big)), with: .color(.white))
            map.fill(Path(ellipseIn: CGRect(x: car.at.x - dot / 2, y: car.at.y - dot / 2, width: dot, height: dot)), with: .color(car.colour))
        }
    }
}
