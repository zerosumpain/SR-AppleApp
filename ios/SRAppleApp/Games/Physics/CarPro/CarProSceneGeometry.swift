import SwiftUI

// Car Racer+ circuits as paths to draw: built once per circuit (and the
// racing line once per car), in world metres, so a frame only transforms
// and fills them. The world has its own fixed palette per theme — tarmac
// and grass do not change with light and dark mode, the way a board game's
// board does not.

/// What a theme's circuit is painted with.
struct CarProPalette {
    /// Beyond the walls.
    let outside: Color
    /// The run-off between the tarmac and the walls.
    let runoff: Color
    /// The lighter band of the mown stripes.
    let mowing: Color
    let tarmac: Color
    let edgeLine: Color
    let kerb: Color
    let kerbStripe: Color
    let gravel: Color
    let gravelDot: Color
    let dirt: Color
    let wet: Color
    let wall: Color
    let wallTop: Color
    /// The scenery's four shades.
    let shades: [Color]
    let rubber: Color
    let rut: Color
    let smoke: Color
    let dust: Color
    let night: Bool

    static let red = Color(red: 0.84, green: 0.16, blue: 0.15)

    static func of(_ theme: CarProTrackTheme) -> CarProPalette {
        let tarmac = Color(red: 0.26, green: 0.27, blue: 0.29)
        let gravel = Color(red: 0.80, green: 0.74, blue: 0.60)
        let gravelDot = Color(red: 0.62, green: 0.56, blue: 0.44)
        let armco = Color(red: 0.66, green: 0.68, blue: 0.70)
        let smoke = Color(red: 0.93, green: 0.93, blue: 0.95)
        let dust = Color(red: 0.80, green: 0.69, blue: 0.52)
        let trees: [Color] = [Color(red: 0.16, green: 0.36, blue: 0.17), Color(red: 0.21, green: 0.43, blue: 0.19),
                              Color(red: 0.27, green: 0.47, blue: 0.20), Color(red: 0.36, green: 0.50, blue: 0.22)]
        switch theme {
        case .parkland:
            return CarProPalette(outside: Color(red: 0.30, green: 0.50, blue: 0.27),
                                 runoff: Color(red: 0.37, green: 0.59, blue: 0.31),
                                 mowing: Color(red: 0.41, green: 0.63, blue: 0.34), tarmac: tarmac, edgeLine: .white,
                                 kerb: red, kerbStripe: .white, gravel: gravel, gravelDot: gravelDot,
                                 dirt: Color(red: 0.55, green: 0.43, blue: 0.30), wet: Color(red: 0.20, green: 0.22, blue: 0.26),
                                 wall: armco, wallTop: .white, shades: trees, rubber: .black,
                                 rut: Color(red: 0.24, green: 0.30, blue: 0.16), smoke: smoke, dust: dust, night: false)
        case .speedway:
            return CarProPalette(outside: Color(red: 0.34, green: 0.53, blue: 0.29),
                                 runoff: Color(red: 0.40, green: 0.61, blue: 0.33),
                                 mowing: Color(red: 0.44, green: 0.65, blue: 0.36),
                                 tarmac: Color(red: 0.22, green: 0.23, blue: 0.25), edgeLine: .white,
                                 kerb: Color(red: 0.15, green: 0.35, blue: 0.80), kerbStripe: .white, gravel: gravel,
                                 gravelDot: gravelDot, dirt: Color(red: 0.55, green: 0.43, blue: 0.30),
                                 wet: Color(red: 0.18, green: 0.20, blue: 0.24),
                                 wall: Color(red: 0.90, green: 0.90, blue: 0.88), wallTop: Color(red: 0.84, green: 0.16, blue: 0.15),
                                 shades: [trees[0], trees[2], Color(red: 0.86, green: 0.86, blue: 0.84),
                                          Color(red: 0.75, green: 0.30, blue: 0.24)],
                                 rubber: .black, rut: Color(red: 0.24, green: 0.30, blue: 0.16), smoke: smoke, dust: dust,
                                 night: false)
        case .streets:
            return CarProPalette(outside: Color(red: 0.58, green: 0.56, blue: 0.53),
                                 runoff: Color(red: 0.48, green: 0.48, blue: 0.49),
                                 mowing: Color(red: 0.50, green: 0.50, blue: 0.51),
                                 tarmac: Color(red: 0.24, green: 0.24, blue: 0.26), edgeLine: Color(red: 0.98, green: 0.86, blue: 0.22),
                                 kerb: red, kerbStripe: .white, gravel: gravel, gravelDot: gravelDot,
                                 dirt: Color(red: 0.55, green: 0.43, blue: 0.30), wet: Color(red: 0.19, green: 0.20, blue: 0.24),
                                 wall: Color(red: 0.86, green: 0.86, blue: 0.83), wallTop: red,
                                 shades: [Color(red: 0.70, green: 0.36, blue: 0.27), Color(red: 0.40, green: 0.44, blue: 0.50),
                                          Color(red: 0.62, green: 0.58, blue: 0.50), Color(red: 0.50, green: 0.32, blue: 0.30)],
                                 rubber: .black, rut: Color(red: 0.30, green: 0.30, blue: 0.30), smoke: smoke, dust: dust,
                                 night: false)
        case .hills:
            return CarProPalette(outside: Color(red: 0.42, green: 0.53, blue: 0.29),
                                 runoff: Color(red: 0.44, green: 0.61, blue: 0.32),
                                 mowing: Color(red: 0.48, green: 0.65, blue: 0.35), tarmac: tarmac, edgeLine: .white,
                                 kerb: red, kerbStripe: .white, gravel: gravel, gravelDot: gravelDot,
                                 dirt: Color(red: 0.55, green: 0.43, blue: 0.30), wet: Color(red: 0.20, green: 0.22, blue: 0.26),
                                 wall: armco, wallTop: .white,
                                 shades: [trees[0], trees[1], Color(red: 0.55, green: 0.55, blue: 0.52),
                                          Color(red: 0.64, green: 0.62, blue: 0.58)],
                                 rubber: .black, rut: Color(red: 0.28, green: 0.30, blue: 0.16), smoke: smoke, dust: dust,
                                 night: false)
        case .coast:
            return CarProPalette(outside: Color(red: 0.87, green: 0.79, blue: 0.60),
                                 runoff: Color(red: 0.47, green: 0.63, blue: 0.38),
                                 mowing: Color(red: 0.51, green: 0.67, blue: 0.41), tarmac: tarmac, edgeLine: .white,
                                 kerb: red, kerbStripe: .white, gravel: Color(red: 0.88, green: 0.82, blue: 0.66),
                                 gravelDot: Color(red: 0.70, green: 0.63, blue: 0.48),
                                 dirt: Color(red: 0.62, green: 0.50, blue: 0.34), wet: Color(red: 0.18, green: 0.24, blue: 0.30),
                                 wall: armco, wallTop: Color(red: 0.15, green: 0.45, blue: 0.75),
                                 shades: [Color(red: 0.93, green: 0.85, blue: 0.64), Color(red: 0.25, green: 0.55, blue: 0.80),
                                          Color(red: 0.92, green: 0.40, blue: 0.35), Color(red: 0.55, green: 0.56, blue: 0.54)],
                                 rubber: .black, rut: Color(red: 0.42, green: 0.36, blue: 0.22), smoke: smoke, dust: dust,
                                 night: false)
        case .quarry:
            return CarProPalette(outside: Color(red: 0.62, green: 0.53, blue: 0.42),
                                 runoff: Color(red: 0.52, green: 0.55, blue: 0.36),
                                 mowing: Color(red: 0.55, green: 0.58, blue: 0.38), tarmac: tarmac, edgeLine: .white,
                                 kerb: Color(red: 0.95, green: 0.62, blue: 0.10), kerbStripe: Color(red: 0.12, green: 0.12, blue: 0.12),
                                 gravel: Color(red: 0.70, green: 0.64, blue: 0.54), gravelDot: Color(red: 0.52, green: 0.47, blue: 0.40),
                                 dirt: Color(red: 0.58, green: 0.44, blue: 0.30), wet: Color(red: 0.20, green: 0.22, blue: 0.26),
                                 wall: Color(red: 0.20, green: 0.20, blue: 0.22), wallTop: Color(red: 0.95, green: 0.62, blue: 0.10),
                                 shades: [Color(red: 0.55, green: 0.45, blue: 0.34), Color(red: 0.48, green: 0.46, blue: 0.44),
                                          Color(red: 0.66, green: 0.58, blue: 0.48), Color(red: 0.12, green: 0.12, blue: 0.13)],
                                 rubber: .black, rut: Color(red: 0.36, green: 0.27, blue: 0.18),
                                 smoke: Color(red: 0.90, green: 0.86, blue: 0.80), dust: dust, night: false)
        case .harbourNight:
            return CarProPalette(outside: Color(red: 0.24, green: 0.26, blue: 0.30),
                                 runoff: Color(red: 0.30, green: 0.32, blue: 0.36),
                                 mowing: Color(red: 0.32, green: 0.34, blue: 0.38),
                                 tarmac: Color(red: 0.17, green: 0.17, blue: 0.20), edgeLine: .white,
                                 kerb: red, kerbStripe: .white, gravel: Color(red: 0.62, green: 0.58, blue: 0.50),
                                 gravelDot: Color(red: 0.45, green: 0.42, blue: 0.36),
                                 dirt: Color(red: 0.45, green: 0.36, blue: 0.27), wet: Color(red: 0.12, green: 0.14, blue: 0.18),
                                 wall: Color(red: 0.60, green: 0.62, blue: 0.66), wallTop: Color(red: 0.98, green: 0.82, blue: 0.20),
                                 shades: [Color(red: 0.78, green: 0.24, blue: 0.20), Color(red: 0.20, green: 0.42, blue: 0.70),
                                          Color(red: 0.92, green: 0.55, blue: 0.15), Color(red: 0.22, green: 0.55, blue: 0.38)],
                                 rubber: .black, rut: Color(red: 0.22, green: 0.22, blue: 0.22), smoke: smoke, dust: dust,
                                 night: true)
        case .forest:
            return CarProPalette(outside: Color(red: 0.17, green: 0.31, blue: 0.17),
                                 runoff: Color(red: 0.30, green: 0.47, blue: 0.25),
                                 mowing: Color(red: 0.33, green: 0.51, blue: 0.27), tarmac: tarmac, edgeLine: .white,
                                 kerb: red, kerbStripe: .white, gravel: gravel, gravelDot: gravelDot,
                                 dirt: Color(red: 0.50, green: 0.40, blue: 0.28), wet: Color(red: 0.19, green: 0.21, blue: 0.25),
                                 wall: armco, wallTop: .white,
                                 shades: [Color(red: 0.10, green: 0.24, blue: 0.13), Color(red: 0.13, green: 0.29, blue: 0.15),
                                          Color(red: 0.17, green: 0.34, blue: 0.17), Color(red: 0.24, green: 0.40, blue: 0.20)],
                                 rubber: .black, rut: Color(red: 0.20, green: 0.24, blue: 0.13), smoke: smoke, dust: dust,
                                 night: false)
        }
    }
}

/// A circuit's centre line squeezed into a unit square (its shape kept), for
/// the minimap and the picker cards.
struct CarProMapShape {
    let points: [CGPoint]
    let minX: Double
    let minY: Double
    let scale: Double
    let padX: Double
    let padY: Double

    init(track: CarProTrack) {
        let raw = track.minimap(every: 3)
        var loX = Double.infinity, loY = Double.infinity, hiX = -Double.infinity, hiY = -Double.infinity
        for p in raw {
            loX = min(loX, p.x); loY = min(loY, p.y)
            hiX = max(hiX, p.x); hiY = max(hiY, p.y)
        }
        let w = max(1, hiX - loX), h = max(1, hiY - loY)
        let s = 1 / max(w, h)
        let px = (1 - w * s) / 2, py = (1 - h * s) / 2
        minX = loX
        minY = loY
        scale = s
        padX = px
        padY = py
        points = raw.map { CGPoint(x: ($0.x - loX) * s + px, y: ($0.y - loY) * s + py) }
    }

    /// A world point in the unit square.
    func unit(_ p: CarProVec) -> CGPoint {
        CGPoint(x: (p.x - minX) * scale + padX, y: (p.y - minY) * scale + padY)
    }

    /// The outline as a path in a square of side `side`, inset by `inset`.
    func path(side: Double, inset: Double) -> Path {
        var path = Path()
        let k = side - 2 * inset
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: inset + Double(first.x) * k, y: inset + Double(first.y) * k))
        for p in points.dropFirst() {
            path.addLine(to: CGPoint(x: inset + Double(p.x) * k, y: inset + Double(p.y) * k))
        }
        path.closeSubpath()
        return path
    }
}

/// A braking board beside the road: `count` bars, three to one.
struct CarProBoardSpot {
    let position: CarProVec
    let direction: Double
    let count: Int
}

/// A stretch of a circuit's surfaces, about 160 m of it, with the circle
/// it fits in: a frame draws only the stretches the camera can see.
struct CarProSceneChunk {
    var centre: CarProVec
    var radius: Double
    /// The run-off between the walls, and its mown stripes over it.
    var runoff = Path()
    var mowing = Path()
    var tarmac = Path()
    /// The darker groove the cars have rubbered in along the racing line.
    var groove = Path()
    var edges = Path()
    var walls = Path()
    var gravel = Path()
    var gravelDots = Path()
    var dirt = Path()
    var wet = Path()
    var kerbs = Path()
    var kerbStripes = Path()

    init(centre: CarProVec, radius: Double) {
        self.centre = centre
        self.radius = radius
    }
}

/// One circuit, ready to draw: every surface as paths in world metres, cut
/// into stretches, plus the start line, the grid, the scenery and the map.
final class CarProSceneGeometry {
    let track: CarProTrack
    let palette: CarProPalette
    let chunks: [CarProSceneChunk]
    let chequerWhite: Path
    let chequerBlack: Path
    let gridBoxes: Path
    let props: [CarProProp]
    let lights: [CarProVec]
    let map: CarProMapShape

    /// Samples per stretch.
    static let chunkSize = 40

    init(track: CarProTrack) {
        self.track = track
        palette = CarProPalette.of(track.theme)
        let samples = track.samples
        let count = samples.count

        var built: [CarProSceneChunk] = []
        var start = 0
        while start < count {
            let end = min(start + CarProSceneGeometry.chunkSize, count)
            // One sample past the end (wrapping), so neighbouring stretches overlap and no seam shows.
            built.append(CarProSceneGeometry.chunk(track, indices: Array(start...end)))
            start = end
        }
        chunks = built

        // The start line: two rows of chequers across the road.
        var white = Path(), black = Path()
        let s0 = samples[0]
        let cells = 10
        let cell = s0.halfWidth * 2 / Double(cells)
        for row in 0..<2 {
            for i in 0..<cells {
                let across = -s0.halfWidth + Double(i) * cell
                let along = Double(row) * cell - cell
                let a = s0.centre + s0.tangent * along + s0.normal * across
                let quad = CarProSceneGeometry.quad(a, s0.tangent * cell, s0.normal * cell)
                if (i + row) % 2 == 0 { white.addPath(quad) } else { black.addPath(quad) }
            }
        }
        chequerWhite = white
        chequerBlack = black

        // Eight grid boxes: an open-backed box for each slot.
        var boxes = Path()
        for slot in 0..<8 {
            let g = track.grid(slot)
            let f = CarProVec.heading(g.heading), r = f.right
            let p = g.position
            let a = p + f * 2.8 - r * 1.3, b = p + f * 2.8 + r * 1.3
            let c = p - f * 2.4 + r * 1.3, d = p - f * 2.4 - r * 1.3
            boxes.move(to: CarProSceneGeometry.cg(d))
            boxes.addLine(to: CarProSceneGeometry.cg(a))
            boxes.addLine(to: CarProSceneGeometry.cg(b))
            boxes.addLine(to: CarProSceneGeometry.cg(c))
        }
        gridBoxes = boxes

        let scenery = CarProScenery.props(for: track)
        props = scenery
        lights = scenery.filter { $0.kind == .floodlight }.map(\.position)
        map = CarProMapShape(track: track)
    }

    // MARK: - A stretch

    private static func chunk(_ track: CarProTrack, indices: [Int]) -> CarProSceneChunk {
        let n = track.samples.count
        let samples = indices.map { track.samples[$0 % n] }
        var sum = CarProVec.zero
        for s in samples { sum = sum + s.centre }
        let centre = sum * (1 / Double(max(1, samples.count)))
        var radius = 0.0
        for s in samples {
            radius = max(radius, (s.point(s.wallLeft) - centre).length, (s.point(s.wallRight) - centre).length)
        }
        var c = CarProSceneChunk(centre: centre, radius: radius + 4)

        band(&c.runoff, samples, inner: { $0.wallLeft }, outer: { $0.wallRight })
        for k in 0..<(samples.count - 1) where ((indices[k] % n) / 2) % 2 == 0 {
            band(&c.mowing, [samples[k], samples[k + 1]], inner: { $0.wallLeft }, outer: { $0.wallRight })
        }
        band(&c.tarmac, samples, inner: { -$0.halfWidth }, outer: { $0.halfWidth })
        polyline(&c.groove, samples) { $0.lineOffset }
        polyline(&c.edges, samples) { -$0.halfWidth }
        polyline(&c.edges, samples) { $0.halfWidth }
        polyline(&c.walls, samples) { $0.wallLeft }
        polyline(&c.walls, samples) { $0.wallRight }

        // Gravel traps beyond the first strip of grass, with a speckle.
        let gravelStart = CarProTrack.kerbWidth + CarProTrack.grassBand
        for run in runs(samples, { $0.gravelRight }) {
            band(&c.gravel, run, inner: { $0.halfWidth + gravelStart }, outer: { $0.wallRight })
            dots(&c.gravelDots, run) { s, f in s.halfWidth + gravelStart + (s.runoffRight - gravelStart) * f }
        }
        for run in runs(samples, { $0.gravelLeft }) {
            band(&c.gravel, run, inner: { -($0.halfWidth + gravelStart) }, outer: { $0.wallLeft })
            dots(&c.gravelDots, run) { s, f in -(s.halfWidth + gravelStart + (s.runoffLeft - gravelStart) * f) }
        }
        // Loose dirt and damp patches across the whole width.
        for run in runs(samples, { $0.surface == .dirt }) {
            band(&c.dirt, run, inner: { -$0.halfWidth }, outer: { $0.halfWidth })
        }
        for run in runs(samples, { $0.surface == .wet }) {
            band(&c.wet, run, inner: { -$0.halfWidth }, outer: { $0.halfWidth })
        }
        // Kerbs: the strip beyond the white line, striped every two metres.
        let kw = CarProTrack.kerbWidth
        for run in runs(samples, { $0.kerbRight }) {
            band(&c.kerbs, run, inner: { $0.halfWidth }, outer: { $0.halfWidth + kw })
            stripes(&c.kerbStripes, run, inner: { $0.halfWidth }, outer: { $0.halfWidth + kw })
        }
        for run in runs(samples, { $0.kerbLeft }) {
            band(&c.kerbs, run, inner: { -$0.halfWidth }, outer: { -($0.halfWidth + kw) })
            stripes(&c.kerbStripes, run, inner: { -$0.halfWidth }, outer: { -($0.halfWidth + kw) })
        }
        return c
    }

    /// The runs of consecutive samples where `test` holds, each with the
    /// sample after it so the band reaches the next one.
    private static func runs(_ samples: [CarProTrackSample],
                             _ test: (CarProTrackSample) -> Bool) -> [[CarProTrackSample]] {
        var out: [[CarProTrackSample]] = []
        var current: [CarProTrackSample] = []
        for k in samples.indices {
            if test(samples[k]) {
                current.append(samples[k])
            } else if !current.isEmpty {
                current.append(samples[k])
                out.append(current)
                current = []
            }
        }
        if current.count > 1 { out.append(current) }
        return out
    }

    // MARK: - Building blocks

    static func cg(_ p: CarProVec) -> CGPoint { CGPoint(x: p.x, y: p.y) }

    /// An offset pulled in on the inside of a bend tighter than it, where the
    /// line would otherwise fold back over itself.
    static func drawnOffset(_ s: CarProTrackSample, _ offset: Double) -> Double {
        let k = s.curvature
        guard abs(k) > 1e-4 else { return offset }
        let inner = k > 0 ? offset > 0 : offset < 0
        guard inner else { return offset }
        let limit = 0.92 / abs(k)
        return offset > 0 ? min(offset, limit) : max(offset, -limit)
    }

    /// A band along `samples` between two offsets, added to `path`.
    static func band(_ path: inout Path, _ samples: [CarProTrackSample],
                     inner: (CarProTrackSample) -> Double, outer: (CarProTrackSample) -> Double) {
        guard samples.count > 1 else { return }
        var a: [CGPoint] = [], b: [CGPoint] = []
        a.reserveCapacity(samples.count)
        b.reserveCapacity(samples.count)
        for s in samples {
            a.append(cg(s.point(drawnOffset(s, inner(s)))))
            b.append(cg(s.point(drawnOffset(s, outer(s)))))
        }
        path.addLines(a + b.reversed())
        path.closeSubpath()
    }

    /// An open line along `samples`, added to `path`.
    static func polyline(_ path: inout Path, _ samples: [CarProTrackSample], offset: (CarProTrackSample) -> Double) {
        guard samples.count > 1 else { return }
        path.addLines(samples.map { s in cg(s.point(drawnOffset(s, offset(s)))) })
    }

    /// Specks of stone across a gravel trap: three rows, at each sample and halfway between.
    static func dots(_ path: inout Path, _ samples: [CarProTrackSample],
                     offset: (CarProTrackSample, Double) -> Double) {
        guard samples.count > 1 else { return }
        for k in 0..<(samples.count - 1) {
            let s = samples[k], t = samples[k + 1]
            for (row, f) in [0.22, 0.52, 0.82].enumerated() {
                let a = s.point(drawnOffset(s, offset(s, f))), b = t.point(drawnOffset(t, offset(t, f)))
                let shift = row % 2 == 0 ? 0.0 : 0.5
                for step in [0.0, 0.5] {
                    let p = a + (b - a) * (step + shift * 0.5)
                    path.addRect(CGRect(x: p.x - 0.16, y: p.y - 0.16, width: 0.32, height: 0.32))
                }
            }
        }
    }

    /// The kerb's stripes: the first half of every sample's stretch.
    static func stripes(_ path: inout Path, _ samples: [CarProTrackSample],
                        inner: (CarProTrackSample) -> Double, outer: (CarProTrackSample) -> Double) {
        guard samples.count > 1 else { return }
        for k in 0..<(samples.count - 1) {
            let s = samples[k], t = samples[k + 1]
            let i0 = s.point(drawnOffset(s, inner(s))), o0 = s.point(drawnOffset(s, outer(s)))
            let i1 = t.point(drawnOffset(t, inner(t))), o1 = t.point(drawnOffset(t, outer(t)))
            let im = i0 + (i1 - i0) * 0.5, om = o0 + (o1 - o0) * 0.5
            path.addLines([cg(i0), cg(im), cg(om), cg(o0)])
            path.closeSubpath()
        }
    }

    /// The parallelogram from `a` along `u` and `v`.
    static func quad(_ a: CarProVec, _ u: CarProVec, _ v: CarProVec) -> Path {
        var path = Path()
        path.addLines([cg(a), cg(a + u), cg(a + u + v), cg(a + v)])
        path.closeSubpath()
        return path
    }

    // MARK: - Cache

    /// Built geometry by circuit id: a circuit is only worked out once a launch.
    private static var cache: [String: CarProSceneGeometry] = [:]

    static func of(_ track: CarProTrack) -> CarProSceneGeometry {
        if let built = cache[track.id] { return built }
        let built = CarProSceneGeometry(track: track)
        cache[track.id] = built
        return built
    }
}

/// The racing line for one car, coloured by what the car does along it —
/// green accelerating, amber holding speed, red braking — and its braking
/// boards and bars.
struct CarProLinePaths {
    let accelerate: Path
    let hold: Path
    let brake: Path
    let bars: Path
    let boards: [CarProBoardSpot]

    init(track: CarProTrack, profile: CarProSpeedProfile) {
        let samples = track.samples
        let n = samples.count
        var paths = [Path(), Path(), Path()]
        var current = -1
        for i in 0..<n {
            let j = (i + 1) % n
            let dv = profile.speeds[j] - profile.speeds[i]
            let kind = dv < -0.05 ? 2 : (dv > 0.05 ? 0 : 1)
            if kind != current {
                paths[kind].move(to: CarProSceneGeometry.cg(samples[i].linePoint))
                current = kind
            }
            paths[kind].addLine(to: CarProSceneGeometry.cg(samples[j].linePoint))
        }
        accelerate = paths[0]
        hold = paths[1]
        brake = paths[2]

        var bars = Path()
        var boards: [CarProBoardSpot] = []
        for marker in profile.brakeMarkers {
            let i = track.index(at: marker.distance)
            let s = samples[i]
            bars.addPath(CarProSceneGeometry.quad(s.point(-s.halfWidth), s.tangent * 1.2, s.normal * (s.halfWidth * 2)))
            // The boards stand on the outside of the bend coming.
            let apex = samples[track.index(at: marker.apexDistance)]
            let side: Double = apex.lineCurvature >= 0 ? -1 : 1
            for (k, back) in [50.0, 25.0, 0.0].enumerated() {
                let b = samples[track.index(at: marker.distance - back)]
                let room = side < 0 ? b.runoffLeft : b.runoffRight
                let out = b.halfWidth + min(2.4, max(0.6, room - 0.5))
                boards.append(CarProBoardSpot(position: b.point(side * out), direction: b.direction, count: 3 - k))
            }
        }
        self.bars = bars
        self.boards = boards
    }
}
