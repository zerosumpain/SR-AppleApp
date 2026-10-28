import SwiftUI

/// The race drawn from above: grass, the circuit with red-and-white kerbs and
/// a chequered line, the other cars and my own, and a map of the whole lap in
/// the corner.
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
        .background(CarRaceScene.grass)
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
                                     smoke: car.drifting, mine: true))
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
    private static let tarmac = Color(red: 0.24, green: 0.25, blue: 0.27)
    private static let kerbRed = Color(red: 0.86, green: 0.18, blue: 0.16)

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
        world.stroke(road, with: .color(.white), style: StrokeStyle(lineWidth: width + 2.4, lineJoin: .round))
        world.stroke(road, with: .color(Self.kerbRed),
                     style: StrokeStyle(lineWidth: width + 2.4, lineJoin: .round, dash: [3, 3]))
        world.stroke(road, with: .color(Self.tarmac), style: StrokeStyle(lineWidth: width, lineJoin: .round))
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

    private func drawCar(in context: GraphicsContext, _ car: Car) {
        var c = context
        c.translateBy(x: car.at.x, y: car.at.y)
        c.rotate(by: .radians(car.heading))
        if car.ghost { c.opacity = 0.55 }
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
