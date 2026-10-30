import SwiftUI
import UIKit

/// The hole drawn from above: the garden round it, the felt with its mowing
/// stripes, slopes with drifting arrows, sand, rippling water and plank
/// bridges, timber walls and hedges, posts and bumpers, windmills turning,
/// the cup and its flag, and the ball with its trail, aim and particles.
///
/// The world has a fixed palette, like a real course — felt and timber do
/// not change with light and dark mode; only the garden behind dims. One
/// Canvas, redrawn from the scene's snapshot each frame.
struct MiniGolfCourseView: View {
    @ObservedObject var scene: MiniGolfSceneModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let snapshot = scene.snapshot
        let paths = scene.paths
        let dark = scheme == .dark
        let ballColour = OfflineSeatColour.of(snapshot.seat)
        Canvas(rendersAsynchronously: false) { context, size in
            MiniGolfPainter(snap: snapshot, paths: paths, dark: dark, ballColour: ballColour).draw(in: context, size: size)
        }
    }
}

/// A hole's shapes that never move, as paths in course units, built once per hole.
struct MiniGolfHolePaths {
    let number: Int
    let boundary: Path
    let blocks: Path
    /// The frame, the blocks' edges and the rails: everything stroked as timber.
    let walls: Path
    let rails: Path
    /// Every other mowing band across the felt.
    let stripes: Path
    let sand: [Path]
    let sandGrain: Path
    let water: [Path]
    let bridges: [Path]
    let planks: Path
    /// Leaves dotted on the hedges.
    let leaves: Path
    let slopeAreas: [Path]
    /// Per slope: a grid of chevrons for a tilt (drawn shifted along it), rings for a mound.
    let slopeMarks: [Path]
    /// The spacing of a tilt's chevrons, for the shift that tiles.
    static let chevronGap = 4.0

    init(_ hole: MiniGolfHole) {
        number = hole.number
        boundary = Self.polygon(hole.boundary)
        var blocks = Path()
        for block in hole.blocks { blocks.addPath(Self.polygon(block)) }
        self.blocks = blocks
        var rails = Path()
        for rail in hole.rails { rails.addPath(Self.polyline(rail)) }
        self.rails = rails
        var walls = boundary
        walls.addPath(blocks)
        walls.addPath(rails)
        self.walls = walls

        let b = hole.bounds
        var stripes = Path()
        var y = b.minY
        var band = 0
        while y < b.maxY {
            if band % 2 == 0 { stripes.addRect(CGRect(x: b.minX - 1, y: y, width: b.width + 2, height: 5)) }
            y += 5
            band += 1
        }
        self.stripes = stripes

        sand = hole.sand.map { Self.polygon($0.points) }
        var grain = Path()
        var seed: UInt64 = UInt64(hole.number) &* 2_654_435_761 &+ 17
        for area in hole.sand {
            let count = Int(area.box.width * area.box.height * 0.9)
            for _ in 0..<count {
                let x = area.box.minX + Self.random(&seed) * area.box.width
                let y = area.box.minY + Self.random(&seed) * area.box.height
                let p = MiniGolfVec(x, y)
                guard area.contains(p) else { continue }
                let r = 0.08 + Self.random(&seed) * 0.1
                grain.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        sandGrain = grain

        water = hole.water.map { Self.polygon($0.points) }
        bridges = hole.bridges.map { Self.polygon($0.points) }
        var planks = Path()
        for bridge in hole.bridges {
            let box = bridge.box
            if box.height >= box.width {
                var py = box.minY + 0.5
                while py < box.maxY {
                    planks.move(to: CGPoint(x: box.minX, y: py))
                    planks.addLine(to: CGPoint(x: box.maxX, y: py))
                    py += 1.1
                }
            } else {
                var px = box.minX + 0.5
                while px < box.maxX {
                    planks.move(to: CGPoint(x: px, y: box.minY))
                    planks.addLine(to: CGPoint(x: px, y: box.maxY))
                    px += 1.1
                }
            }
        }
        self.planks = planks

        var leaves = Path()
        for block in hole.blocks {
            let box = MiniGolfBox(around: block)
            let count = Int(box.width * box.height * 0.5)
            for _ in 0..<count {
                let x = box.minX + Self.random(&seed) * box.width
                let y = box.minY + Self.random(&seed) * box.height
                guard MiniGolfGeo.contains(block, MiniGolfVec(x, y)) else { continue }
                let r = 0.25 + Self.random(&seed) * 0.35
                leaves.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        self.leaves = leaves

        slopeAreas = hole.slopes.map { Self.polygon($0.area.points) }
        slopeMarks = hole.slopes.map { Self.marks(for: $0) }
    }

    private static func marks(for slope: MiniGolfSlope) -> Path {
        var path = Path()
        let box = slope.area.box
        switch slope.shape {
        case .tilt(let push):
            // Chevrons pointing downhill on a grid along and across the push.
            let d = push.unit
            let n = d.perp
            let reach = (box.width * box.width + box.height * box.height).squareRoot() / 2 + chevronGap * 2
            let steps = Int((reach / chevronGap).rounded(.up))
            for i in -steps...steps {
                for j in -steps...steps {
                    let along: Double = Double(i) * chevronGap
                    let stagger: Double = i % 2 == 0 ? 0 : 1.6
                    let across: Double = Double(j) * 3.2 + stagger
                    let c: MiniGolfVec = box.centre + d * along + n * across
                    let back: MiniGolfVec = c - d * 0.55
                    let tail1: MiniGolfVec = back + n * 0.85
                    let tail2: MiniGolfVec = back - n * 0.85
                    let tip: MiniGolfVec = c + d * 0.45
                    path.move(to: CGPoint(x: tail1.x, y: tail1.y))
                    path.addLine(to: CGPoint(x: tip.x, y: tip.y))
                    path.addLine(to: CGPoint(x: tail2.x, y: tail2.y))
                }
            }
        case .mound(let centre, _):
            // Contour rings, like a map's.
            let outer = max(box.width, box.height) / 2
            var r = 1.6
            while r < outer {
                path.addEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
                r += 1.8
            }
        }
        return path
    }

    static func polygon(_ points: [MiniGolfVec]) -> Path {
        var path = polyline(points)
        if points.count > 2 { path.closeSubpath() }
        return path
    }

    static func polyline(_ points: [MiniGolfVec]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
        return path
    }

    /// A small fixed generator, so the sand and hedges look the same every time.
    private static func random(_ seed: inout UInt64) -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(seed >> 11) / Double(UInt64(1) << 53)
    }
}

/// The colours of the course.
enum MiniGolfPaint {
    static let feltLight = Color(red: 0.36, green: 0.72, blue: 0.36)
    static let feltDark = Color(red: 0.20, green: 0.55, blue: 0.27)
    static let timber = Color(red: 0.55, green: 0.35, blue: 0.19)
    static let timberLight = Color(red: 0.80, green: 0.60, blue: 0.38)
    static let timberDark = Color(red: 0.32, green: 0.19, blue: 0.10)
    static let hedge = Color(red: 0.12, green: 0.36, blue: 0.17)
    static let hedgeLeaf = Color(red: 0.24, green: 0.52, blue: 0.24)
    static let sand = Color(red: 0.93, green: 0.82, blue: 0.58)
    static let sandDark = Color(red: 0.78, green: 0.64, blue: 0.40)
    static let waterLight = Color(red: 0.36, green: 0.70, blue: 0.93)
    static let waterDeep = Color(red: 0.10, green: 0.38, blue: 0.70)
    static let plank = Color(red: 0.72, green: 0.52, blue: 0.32)
    static let stone = Color(red: 0.70, green: 0.70, blue: 0.72)
    static let stoneDark = Color(red: 0.42, green: 0.42, blue: 0.46)
    static let bumper = Color(red: 0.90, green: 0.19, blue: 0.21)
    static let sail = Color(red: 0.97, green: 0.95, blue: 0.90)
    static let flag = Color(red: 0.95, green: 0.22, blue: 0.20)
    static let gold = Color(red: 1.0, green: 0.82, blue: 0.25)
    /// Gold for words on a light card, dark enough to read.
    static let goldInk = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1.0, green: 0.82, blue: 0.30, alpha: 1)
        : UIColor(red: 0.72, green: 0.48, blue: 0.0, alpha: 1) })
    static let confetti: [Color] = [
        Color(red: 0.98, green: 0.30, blue: 0.35), Color(red: 1.0, green: 0.80, blue: 0.20),
        Color(red: 0.25, green: 0.60, blue: 1.0), Color(red: 0.40, green: 0.85, blue: 0.45),
        Color(red: 0.95, green: 0.45, blue: 0.85), Color(red: 1.0, green: 0.55, blue: 0.15),
    ]

    /// Green at a gentle putt, amber in the middle, red at full.
    static func power(_ p: Double) -> Color {
        let t = min(max(p, 0), 1)
        if t < 0.5 {
            let k = t / 0.5
            return Color(red: 0.30 + 0.70 * k, green: 0.85, blue: 0.35 - 0.20 * k)
        }
        let k = (t - 0.5) / 0.5
        return Color(red: 1.0, green: 0.85 - 0.60 * k, blue: 0.15)
    }
}

/// Draws one snapshot. Plain values in, nothing kept.
struct MiniGolfPainter {
    let snap: MiniGolfSnapshot
    let paths: MiniGolfHolePaths
    let dark: Bool
    /// The putting player's colour, for the band round the ball.
    let ballColour: Color

    private var hole: MiniGolfHole { snap.hole }

    func draw(in context: GraphicsContext, size: CGSize) {
        drawGarden(in: context, size: size)
        var world = context
        let cam = snap.camera
        world.translateBy(x: snap.playRect.midX, y: snap.playRect.midY)
        world.scaleBy(x: CGFloat(cam.scale), y: CGFloat(cam.scale))
        world.translateBy(x: CGFloat(-cam.centre.x), y: CGFloat(-cam.centre.y))

        drawFelt(in: world)
        drawSlopes(in: world)
        drawSand(in: world)
        drawWater(in: world)
        drawBridges(in: world)
        drawCup(in: world)
        drawBlocks(in: world)
        drawWalls(in: world)
        drawPosts(in: world)
        drawWindmills(in: world)
        drawAim(in: world)
        drawBall(in: world)
        drawFlag(in: world)
        drawRipples(in: world)
        drawParticles(in: world)
    }

    private func point(_ v: MiniGolfVec) -> CGPoint { CGPoint(x: v.x, y: v.y) }

    private func circle(_ c: MiniGolfVec, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    // MARK: - Ground

    private func drawGarden(in context: GraphicsContext, size: CGSize) {
        let top = dark ? Color(red: 0.05, green: 0.13, blue: 0.09) : Color(red: 0.24, green: 0.46, blue: 0.27)
        let bottom = dark ? Color(red: 0.02, green: 0.07, blue: 0.05) : Color(red: 0.13, green: 0.32, blue: 0.18)
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .linearGradient(Gradient(colors: [top, bottom]),
                                                       startPoint: CGPoint(x: 0, y: 0),
                                                       endPoint: CGPoint(x: size.width * 0.3, y: size.height)))
    }

    private func drawFelt(in world: GraphicsContext) {
        let b = hole.bounds
        // The course stands off the garden: a soft shadow under the whole frame.
        world.fill(paths.boundary.offsetBy(dx: 0.7, dy: 1.1), with: .color(.black.opacity(0.32)))
        world.fill(paths.boundary.offsetBy(dx: 0.35, dy: 0.55), with: .color(.black.opacity(0.18)))
        world.fill(paths.boundary, with: .linearGradient(
            Gradient(colors: [MiniGolfPaint.feltLight, MiniGolfPaint.feltDark]),
            startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.maxX, y: b.maxY)))
        var felt = world
        felt.clip(to: paths.boundary)
        felt.fill(paths.stripes, with: .color(.white.opacity(0.05)))
    }

    private func drawSlopes(in world: GraphicsContext) {
        for (index, slope) in hole.slopes.enumerated() where index < paths.slopeAreas.count {
            var c = world
            c.clip(to: paths.boundary)
            c.clip(to: paths.slopeAreas[index])
            switch slope.shape {
            case .tilt(let push):
                // Shaded darker downhill, with arrows drifting down the slope.
                let box = slope.area.box
                let d = push.unit
                let from = box.centre - d * (max(box.width, box.height) / 2)
                let to = box.centre + d * (max(box.width, box.height) / 2)
                c.fill(paths.slopeAreas[index], with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0.10), Color.black.opacity(0.12)]),
                    startPoint: point(from), endPoint: point(to)))
                let gap = MiniGolfHolePaths.chevronGap
                let shift = (snap.clock * min(3, push.length / 10)).truncatingRemainder(dividingBy: gap)
                var marks = c
                marks.translateBy(x: CGFloat(d.x * shift), y: CGFloat(d.y * shift))
                marks.stroke(paths.slopeMarks[index], with: .color(.white.opacity(0.22)),
                             style: StrokeStyle(lineWidth: 0.28, lineCap: .round, lineJoin: .round))
            case .mound(let centre, let strength):
                let radius = max(slope.area.box.width, slope.area.box.height) / 2
                let hill = strength > 0
                c.fill(paths.slopeAreas[index], with: .radialGradient(
                    Gradient(colors: hill ? [Color.white.opacity(0.22), Color.black.opacity(0.10)]
                                          : [Color.black.opacity(0.26), Color.white.opacity(0.06)]),
                    center: point(centre), startRadius: 0, endRadius: CGFloat(radius)))
                c.stroke(paths.slopeMarks[index], with: .color(.white.opacity(0.14)), lineWidth: 0.18)
                drawRadialArrows(in: c, centre: centre, radius: radius, outward: hill)
            }
        }
    }

    /// Eight little arrows creeping out from (or in to) a mound's middle.
    private func drawRadialArrows(in c: GraphicsContext, centre: MiniGolfVec, radius: Double, outward: Bool) {
        let travel = max(1, radius * 0.5)
        let phase = (snap.clock * 1.4).truncatingRemainder(dividingBy: travel)
        let r = outward ? radius * 0.35 + phase : radius * 0.85 - phase
        var arrows = Path()
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi + 0.2
            let d = MiniGolfVec.heading(a) * (outward ? 1 : -1)
            let n = d.perp
            let at = centre + MiniGolfVec.heading(a) * r
            let back: MiniGolfVec = at - d * 0.5
            let tail1: MiniGolfVec = back + n * 0.7
            let tail2: MiniGolfVec = back - n * 0.7
            let tip: MiniGolfVec = at + d * 0.4
            arrows.move(to: point(tail1))
            arrows.addLine(to: point(tip))
            arrows.addLine(to: point(tail2))
        }
        let fade = 1 - abs(phase / travel - 0.5) * 2
        c.stroke(arrows, with: .color(.white.opacity(0.12 + 0.2 * fade)),
                 style: StrokeStyle(lineWidth: 0.28, lineCap: .round, lineJoin: .round))
    }

    private func drawSand(in world: GraphicsContext) {
        guard !paths.sand.isEmpty else { return }
        var c = world
        c.clip(to: paths.boundary)
        for (index, area) in paths.sand.enumerated() {
            let box = hole.sand[index].box
            c.fill(area, with: .radialGradient(Gradient(colors: [MiniGolfPaint.sand, MiniGolfPaint.sandDark]),
                                               center: point(box.centre), startRadius: 0,
                                               endRadius: CGFloat(max(box.width, box.height) * 0.7)))
            c.stroke(area, with: .color(MiniGolfPaint.sandDark.opacity(0.8)), lineWidth: 0.25)
        }
        c.fill(paths.sandGrain, with: .color(MiniGolfPaint.sandDark.opacity(0.55)))
    }

    private func drawWater(in world: GraphicsContext) {
        guard !paths.water.isEmpty else { return }
        var c = world
        c.clip(to: paths.boundary)
        for (index, area) in paths.water.enumerated() {
            let box = hole.water[index].box
            c.fill(area, with: .linearGradient(Gradient(colors: [MiniGolfPaint.waterLight, MiniGolfPaint.waterDeep]),
                                               startPoint: CGPoint(x: box.minX, y: box.minY),
                                               endPoint: CGPoint(x: box.maxX, y: box.maxY)))
            // Ripples drifting across.
            var waves = Path()
            var y = box.minY + 1.2
            var row = 0
            while y < box.maxY {
                var x = box.minX
                let lift = Double(row) * 1.7
                waves.move(to: CGPoint(x: x, y: y + 0.3 * sin(x * 0.7 + snap.clock * 1.8 + lift)))
                while x < box.maxX {
                    x += 1.2
                    waves.addLine(to: CGPoint(x: x, y: y + 0.3 * sin(x * 0.7 + snap.clock * 1.8 + lift)))
                }
                y += 2.4
                row += 1
            }
            var inside = c
            inside.clip(to: area)
            inside.stroke(waves, with: .color(.white.opacity(0.2)), lineWidth: 0.18)
            // A bank of foam round the edge.
            c.stroke(area, with: .color(.white.opacity(0.35)), lineWidth: 0.3)
        }
    }

    private func drawBridges(in world: GraphicsContext) {
        guard !paths.bridges.isEmpty else { return }
        var c = world
        c.clip(to: paths.boundary)
        for area in paths.bridges {
            c.fill(area.offsetBy(dx: 0.3, dy: 0.45), with: .color(.black.opacity(0.3)))
            c.fill(area, with: .color(MiniGolfPaint.plank))
            var planks = c
            planks.clip(to: area)
            planks.stroke(paths.planks, with: .color(MiniGolfPaint.timberDark.opacity(0.45)), lineWidth: 0.12)
            c.stroke(area, with: .color(MiniGolfPaint.timberLight), lineWidth: 0.22)
        }
    }

    private func drawCup(in world: GraphicsContext) {
        let r = MiniGolfRules.cupRadius
        world.fill(circle(hole.cup, r + 0.25), with: .color(.white.opacity(0.85)))
        world.fill(circle(hole.cup, r), with: .radialGradient(
            Gradient(colors: [Color.black, Color(red: 0.10, green: 0.16, blue: 0.10)]),
            center: point(hole.cup + MiniGolfVec(0.35, 0.45)), startRadius: 0, endRadius: CGFloat(r)))
    }

    private func drawBlocks(in world: GraphicsContext) {
        guard !hole.blocks.isEmpty else { return }
        world.fill(paths.blocks.offsetBy(dx: 0.5, dy: 0.8), with: .color(.black.opacity(0.3)))
        world.fill(paths.blocks, with: .color(MiniGolfPaint.hedge))
        var c = world
        c.clip(to: paths.blocks)
        c.fill(paths.leaves, with: .color(MiniGolfPaint.hedgeLeaf.opacity(0.8)))
        c.fill(paths.leaves.offsetBy(dx: -0.12, dy: -0.15), with: .color(.white.opacity(0.06)))
    }

    private func drawWalls(in world: GraphicsContext) {
        let wide = MiniGolfRules.wallHalf * 2
        let round = StrokeStyle(lineWidth: CGFloat(wide), lineCap: .round, lineJoin: .round)
        world.stroke(paths.walls.offsetBy(dx: 0.3, dy: 0.45), with: .color(.black.opacity(0.32)),
                     style: StrokeStyle(lineWidth: CGFloat(wide + 0.25), lineCap: .round, lineJoin: .round))
        world.stroke(paths.walls, with: .color(MiniGolfPaint.timber), style: round)
        world.stroke(paths.walls.offsetBy(dx: -0.12, dy: -0.14), with: .color(MiniGolfPaint.timberLight.opacity(0.8)),
                     style: StrokeStyle(lineWidth: 0.22, lineCap: .round, lineJoin: .round))
    }

    private func drawPosts(in world: GraphicsContext) {
        for (index, post) in hole.posts.enumerated() {
            let c = post.centre, r = post.radius
            world.fill(circle(c + MiniGolfVec(0.35, 0.5), r), with: .color(.black.opacity(0.3)))
            switch post.kind {
            case .post:
                world.fill(circle(c, r), with: .radialGradient(
                    Gradient(colors: [MiniGolfPaint.stone, MiniGolfPaint.stoneDark]),
                    center: point(c - MiniGolfVec(r * 0.35, r * 0.35)), startRadius: 0, endRadius: CGFloat(r * 1.3)))
            case .bumper:
                let flash = index < snap.flashes.count ? snap.flashes[index] / 0.35 : 0
                let grow = r * (1 + 0.12 * flash)
                world.fill(circle(c, grow), with: .color(MiniGolfPaint.bumper))
                world.fill(circle(c, grow * 0.72), with: .color(.white))
                world.fill(circle(c, grow * 0.5), with: .radialGradient(
                    Gradient(colors: [Color(red: 1, green: 0.45, blue: 0.45), MiniGolfPaint.bumper]),
                    center: point(c - MiniGolfVec(r * 0.15, r * 0.15)), startRadius: 0, endRadius: CGFloat(r * 0.5)))
                if flash > 0 {
                    world.fill(circle(c, grow * 1.15), with: .color(.white.opacity(0.45 * flash)))
                }
            }
        }
    }

    private func drawWindmills(in world: GraphicsContext) {
        for mill in hole.windmills {
            // The sweep, faintly, so you can see where the sails will be.
            world.stroke(circle(mill.pivot, mill.arm), with: .color(.white.opacity(0.10)),
                         style: StrokeStyle(lineWidth: 0.2, dash: [0.6, 0.8]))
            for k in 0..<mill.arms {
                var c = world
                c.translateBy(x: CGFloat(mill.pivot.x), y: CGFloat(mill.pivot.y))
                c.rotate(by: .radians(mill.angle(k, at: snap.clock)))
                let length = mill.arm - mill.hub
                let half = MiniGolfRules.armHalf
                let spar = Path(roundedRect: CGRect(x: mill.hub - 0.3, y: -half, width: length + 0.3, height: half * 2),
                                cornerRadius: CGFloat(half))
                let cloth = Path(CGRect(x: mill.hub + 0.8, y: -half - 0.45, width: length - 1.2, height: half * 2 + 0.45))
                c.fill(cloth.offsetBy(dx: 0.35, dy: 0.6), with: .color(.black.opacity(0.22)))
                c.fill(spar.offsetBy(dx: 0.35, dy: 0.6), with: .color(.black.opacity(0.22)))
                c.fill(cloth, with: .color(MiniGolfPaint.sail))
                var lattice = Path()
                var x = mill.hub + 1.6
                while x < mill.arm - 0.4 {
                    lattice.move(to: CGPoint(x: x, y: -half - 0.45))
                    lattice.addLine(to: CGPoint(x: x, y: half))
                    x += 1.3
                }
                c.stroke(lattice, with: .color(MiniGolfPaint.timber.opacity(0.5)), lineWidth: 0.1)
                c.fill(spar, with: .color(MiniGolfPaint.timberDark))
            }
            world.fill(circle(mill.pivot + MiniGolfVec(0.4, 0.6), mill.hub), with: .color(.black.opacity(0.3)))
            world.fill(circle(mill.pivot, mill.hub), with: .radialGradient(
                Gradient(colors: [Color(red: 0.85, green: 0.45, blue: 0.30), Color(red: 0.50, green: 0.20, blue: 0.14)]),
                center: point(mill.pivot - MiniGolfVec(0.6, 0.6)), startRadius: 0, endRadius: CGFloat(mill.hub * 1.2)))
            world.stroke(circle(mill.pivot, mill.hub), with: .color(MiniGolfPaint.timberDark), lineWidth: 0.2)
            world.fill(circle(mill.pivot, 0.45), with: .color(MiniGolfPaint.timberDark))
        }
    }

    // MARK: - The ball

    private func drawAim(in world: GraphicsContext) {
        guard let aim = snap.aim, snap.showBall else { return }
        let dir = MiniGolfVec.heading(aim.angle)
        let colour = MiniGolfPaint.power(aim.power)
        let r = MiniGolfRules.ballRadius
        // The catapult's band, back towards the finger.
        let back = snap.ball - dir * (r + 1 + aim.power * 4.5)
        var band = Path()
        band.move(to: point(snap.ball - dir * r))
        band.addLine(to: point(back))
        world.stroke(band, with: .color(.white.opacity(0.35)),
                     style: StrokeStyle(lineWidth: 0.25, lineCap: .round, dash: [0.35, 0.45]))
        // A short dotted line the way the putt starts, longer for a harder one.
        let length = 3 + aim.power * 9
        var d = r + 0.9
        var dots = Path()
        while d < r + length {
            let fade = 1 - (d - r) / (length + 1)
            let dot = 0.18 + 0.14 * fade
            let at = snap.ball + dir * d
            dots.addEllipse(in: CGRect(x: at.x - dot, y: at.y - dot, width: dot * 2, height: dot * 2))
            d += 0.95
        }
        world.fill(dots, with: .color(.white.opacity(0.9)))
        // The power ring round the ball.
        var ring = Path()
        ring.addArc(center: point(snap.ball), radius: CGFloat(r + 0.75), startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * max(0.02, aim.power)), clockwise: false)
        world.stroke(circle(snap.ball, r + 0.75), with: .color(.black.opacity(0.25)), lineWidth: 0.35)
        world.stroke(ring, with: .color(colour), style: StrokeStyle(lineWidth: 0.35, lineCap: .round))
    }

    private func drawBall(in world: GraphicsContext) {
        guard snap.showBall else { return }
        let r = MiniGolfRules.ballRadius
        let count = snap.trail.count
        for (i, at) in snap.trail.enumerated() {
            let k = Double(i + 1) / Double(max(1, count))
            world.fill(circle(at, r * (0.35 + 0.5 * k)), with: .color(.white.opacity(0.18 * k)))
        }
        let shrink = 1 - snap.ballSink * 0.65
        let size = r * shrink
        var c = world
        c.opacity = 1 - snap.ballSink * 0.8
        c.fill(circle(snap.ball + MiniGolfVec(0.28, 0.4) * shrink, size * 1.02), with: .color(.black.opacity(0.35)))
        c.fill(circle(snap.ball, size), with: .radialGradient(
            Gradient(colors: [Color.white, Color(red: 0.86, green: 0.87, blue: 0.90)]),
            center: point(snap.ball - MiniGolfVec(size * 0.35, size * 0.4)), startRadius: 0, endRadius: CGFloat(size * 1.4)))
        // The player's colour as a band round the ball.
        c.stroke(circle(snap.ball, size * 0.62), with: .color(ballColour), lineWidth: CGFloat(size * 0.22))
        c.fill(circle(snap.ball - MiniGolfVec(size * 0.38, size * 0.42), size * 0.2), with: .color(.white.opacity(0.9)))
    }

    private func drawFlag(in world: GraphicsContext) {
        let near = snap.ball.distance(to: hole.cup)
        var c = world
        // Out of the way when the ball is close, so you can see it drop.
        c.opacity = near < 6 ? 0.25 + 0.75 * max(0, near - 2) / 4 : 1
        let base = hole.cup
        let top = base + MiniGolfVec(1.1, -6.8)
        var shadow = Path()
        shadow.move(to: point(base))
        shadow.addLine(to: point(base + MiniGolfVec(4.2, 2.2)))
        c.stroke(shadow, with: .color(.black.opacity(0.22)), style: StrokeStyle(lineWidth: 0.25, lineCap: .round))
        var pole = Path()
        pole.move(to: point(base))
        pole.addLine(to: point(top))
        c.stroke(pole, with: .color(.white), style: StrokeStyle(lineWidth: 0.22, lineCap: .round))
        let wave = sin(snap.clock * 5.5) * 0.35
        let wave2 = sin(snap.clock * 5.5 + 1.3) * 0.3
        var flag = Path()
        flag.move(to: point(top))
        flag.addQuadCurve(to: point(top + MiniGolfVec(3.4, 1.0 + wave)), control: point(top + MiniGolfVec(1.7, wave2 - 0.2)))
        flag.addQuadCurve(to: point(top + MiniGolfVec(0.08, 2.1)), control: point(top + MiniGolfVec(1.6, 1.9 + wave2)))
        flag.closeSubpath()
        c.fill(flag, with: .color(MiniGolfPaint.flag))
        c.fill(circle(top, 0.2), with: .color(MiniGolfPaint.gold))
    }

    private func drawRipples(in world: GraphicsContext) {
        for ripple in snap.ripples where ripple.age > 0 {
            let k = ripple.progress
            let colour: Color
            switch ripple.tone {
            case .water: colour = .white
            case .bumper: colour = Color(red: 1, green: 0.6, blue: 0.55)
            case .cup: colour = MiniGolfPaint.gold
            }
            world.stroke(circle(ripple.at, ripple.radius * (0.3 + 0.7 * k)), with: .color(colour.opacity(0.7 * (1 - k))),
                         lineWidth: CGFloat(0.35 * (1 - k) + 0.08))
        }
    }

    private func drawParticles(in world: GraphicsContext) {
        for p in snap.particles {
            let fade = p.fade
            switch p.tone {
            case .confetti(let index):
                var c = world
                c.translateBy(x: CGFloat(p.at.x), y: CGFloat(p.at.y))
                c.rotate(by: .radians(p.spin))
                // A scrap turning over: it narrows and widens as it spins.
                let width = p.size * (0.35 + 0.65 * abs(sin(p.spin * 1.7)))
                let colour = MiniGolfPaint.confetti[index % MiniGolfPaint.confetti.count]
                c.fill(Path(CGRect(x: -p.size / 2, y: -width / 2, width: p.size, height: width)),
                       with: .color(colour.opacity(min(1, fade * 1.6))))
            case .gold:
                world.fill(circle(p.at, p.size * (0.6 + 0.4 * fade)), with: .color(MiniGolfPaint.gold.opacity(fade)))
            case .water:
                world.fill(circle(p.at, p.size), with: .color(Color(red: 0.80, green: 0.92, blue: 1.0).opacity(fade)))
            case .sand:
                world.fill(circle(p.at, p.size), with: .color(MiniGolfPaint.sandDark.opacity(fade)))
            case .spark:
                world.fill(circle(p.at, p.size), with: .color(Color(red: 1, green: 0.95, blue: 0.7).opacity(fade)))
            }
        }
    }
}
