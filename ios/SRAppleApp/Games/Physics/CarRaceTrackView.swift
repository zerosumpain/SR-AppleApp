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

    /// Metres across the screen's width.
    private let span: Double = 64

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            draw(in: context, size: size)
        }
        .background(Self.grass)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityIdentifier("car-race-track")
    }

    private var label: String {
        let lap = "Lap \(driver.counter.lap) of \(driver.laps)"
        let speed = "\(Int((driver.car.speed * 3.6).rounded())) kilometres an hour"
        return "\(driver.track.name). \(lap), \(speed)."
    }

    // MARK: - Drawing

    private static let grass = Color(red: 0.33, green: 0.52, blue: 0.29)
    private static let tarmac = Color(red: 0.24, green: 0.25, blue: 0.27)
    private static let kerbRed = Color(red: 0.86, green: 0.18, blue: 0.16)

    private func draw(in context: GraphicsContext, size: CGSize) {
        let scale = Double(size.width) / span
        let car = driver.car
        var world = context
        // My car sits low on the screen, pointing up; the world turns round it.
        world.translateBy(x: size.width / 2, y: size.height * 0.68)
        world.rotate(by: .radians(-driver.cameraHeading - .pi / 2))
        world.scaleBy(x: scale, y: scale)
        world.translateBy(x: -car.x, y: -car.y)

        let road = driver.road
        let width = driver.track.width
        world.stroke(road, with: .color(.white), style: StrokeStyle(lineWidth: width + 2.4, lineJoin: .round))
        world.stroke(road, with: .color(Self.kerbRed),
                     style: StrokeStyle(lineWidth: width + 2.4, lineJoin: .round, dash: [3, 3]))
        world.stroke(road, with: .color(Self.tarmac), style: StrokeStyle(lineWidth: width, lineJoin: .round))
        world.stroke(road, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 0.3, dash: [4, 6]))
        drawLine(in: world)

        for rival in driver.rivals {
            guard let pose = driver.pose(of: rival) else { continue }
            drawCar(in: world, at: pose.at, heading: pose.heading, colour: colour(rival.seat), ghost: true, smoke: false)
        }
        drawCar(in: world, at: car.position, heading: car.heading, colour: colour(seat), ghost: false, smoke: car.drifting)

        drawMap(in: context, size: size)
    }

    /// The start and finish: a chequered strip across the road.
    private func drawLine(in context: GraphicsContext) {
        let start = driver.track.point(at: 0)
        var line = context
        line.translateBy(x: start.at.x, y: start.at.y)
        line.rotate(by: .radians(start.direction))
        let width = driver.track.width
        let cells = 8
        let cell = width / Double(cells)
        for row in 0..<2 {
            for i in 0..<cells {
                let rect = CGRect(x: Double(row) * cell - cell, y: -width / 2 + Double(i) * cell, width: cell, height: cell)
                line.fill(Path(rect), with: .color((i + row) % 2 == 0 ? .white : .black))
            }
        }
    }

    private func drawCar(in context: GraphicsContext, at p: CarVec, heading: Double, colour: Color, ghost: Bool, smoke: Bool) {
        var c = context
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(heading))
        if ghost { c.opacity = 0.55 }
        if smoke {
            for (dx, dy) in [(-2.8, -1.0), (-2.8, 1.0), (-4.2, 0.0)] {
                c.fill(Path(ellipseIn: CGRect(x: dx - 0.8, y: dy - 0.8, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.45)))
            }
        }
        // 4.4 m long, 2.2 wide, pointing along +x.
        let body = Path(roundedRect: CGRect(x: -2.2, y: -1.1, width: 4.4, height: 2.2), cornerRadius: 0.6)
        c.fill(Path(roundedRect: CGRect(x: -2.0, y: -0.9, width: 4.4, height: 2.2), cornerRadius: 0.6), with: .color(.black.opacity(0.25)))
        c.fill(body, with: .color(colour))
        c.stroke(body, with: .color(.white.opacity(0.8)), lineWidth: 0.15)
        c.fill(Path(roundedRect: CGRect(x: 0.2, y: -0.75, width: 0.9, height: 1.5), cornerRadius: 0.25), with: .color(.black.opacity(0.55)))
        c.fill(Path(CGRect(x: -2.1, y: -0.2, width: 3.9, height: 0.4)), with: .color(.white.opacity(0.5)))
    }

    /// The whole lap, small, top right, with a dot for every car.
    private func drawMap(in context: GraphicsContext, size: CGSize) {
        let box = CGRect(x: size.width - 104, y: 12, width: 92, height: 92)
        let b = driver.track.bounds
        let w = b.maxX - b.minX, h = b.maxY - b.minY
        guard w > 0, h > 0 else { return }
        let k = min(Double(box.width - 16) / w, Double(box.height - 16) / h)
        var map = context
        map.fill(Path(roundedRect: box, cornerRadius: 14), with: .color(.black.opacity(0.35)))
        map.translateBy(x: Double(box.midX) - (b.minX + w / 2) * k, y: Double(box.midY) - (b.minY + h / 2) * k)
        map.scaleBy(x: k, y: k)
        map.stroke(driver.road, with: .color(.white.opacity(0.85)), lineWidth: 3 / k)
        let dot = 5 / k
        for rival in driver.rivals {
            guard let pose = driver.pose(of: rival) else { continue }
            map.fill(Path(ellipseIn: CGRect(x: pose.at.x - dot / 2, y: pose.at.y - dot / 2, width: dot, height: dot)),
                     with: .color(colour(rival.seat)))
        }
        let me = driver.car.position
        let big = dot * 1.5
        map.fill(Path(ellipseIn: CGRect(x: me.x - big / 2, y: me.y - big / 2, width: big, height: big)), with: .color(.white))
        map.fill(Path(ellipseIn: CGRect(x: me.x - dot / 2, y: me.y - dot / 2, width: dot, height: dot)), with: .color(colour(seat)))
    }
}
