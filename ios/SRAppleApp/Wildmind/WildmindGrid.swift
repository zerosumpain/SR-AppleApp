import Foundation

// MARK: - The explored grid, decoded
//
// The terrain arrives as two byte planes in base64, `w × h` each, row-major
// (cell (i, j) at `j * w + i`, i east, j south). `t` is 0 for a cell nobody
// has seen, else an index into `terrains` plus one; `height` is 0 unseen,
// else `height = byte / 10 - 2` (a byte of 55 or more is high ground).
//
// The map does not draw fifteen terrains. It draws the seven grounds the
// site's notes map draws — open ground, shore, fresh water, sea, wood, wet and
// high — in inks mixed from the page's own, so the valley looks drawn on the
// paper rather than pasted onto it.
//
// Foundation only, like the models: decoding, the world-to-cell sum, the
// outlines and the picture's pixels are all plain arithmetic, and are run on
// Linux against hand-made grids, where nobody can build the app itself.

/// The seven grounds of the notes map (`TERRAIN_CLASS` on the site).
enum WildmindGround: UInt8, CaseIterable, Sendable {
    case unseen = 0
    case open
    case shore
    case fresh
    case sea
    case wood
    case wet
    case high

    /// The ground a Wildmind terrain is drawn as. A terrain this build has not
    /// met is open ground: plain paper, which is the least wrong guess.
    init(terrain: String) {
        switch terrain {
        case "deep_sea", "shallow_sea": self = .sea
        case "deep_fresh", "shallow_fresh": self = .fresh
        case "sand": self = .shore
        case "forest", "jungle": self = .wood
        case "marsh": self = .wet
        case "rock", "snow", "tundra", "volcanic": self = .high
        default: self = .open
        }
    }

    var isWater: Bool { self == .sea || self == .fresh }
    var isSeen: Bool { self != .unseen }
}

/// The grid, ready to draw: one ground and one height per cell.
struct WildmindGrid: Sendable, Equatable {
    /// The terrain version this grid is for.
    let version: String
    let w: Int
    let h: Int
    let originX: Int
    let originZ: Int
    let step: Int
    /// `WildmindGround` raw values, row-major.
    let ground: [UInt8]
    /// The raw height bytes, row-major; 0 unseen.
    let heights: [UInt8]
    let regions: [WildmindRegion]

    /// The site's high-ground line: a byte of 55, a height of 3.5.
    static let highByte: UInt8 = 55

    /// `nil` when the planes are not `w × h` bytes of base64 — a grid that
    /// does not add up is not drawn rather than drawn wrong.
    init?(terrain: WildmindTerrain, version: String) {
        let count = terrain.w * terrain.h
        guard count > 0,
              let t = WildmindGrid.bytes(base64: terrain.t), t.count == count else { return nil }
        // A missing or short height plane is flat ground, not a refusal: the
        // map is still right, only without its relief.
        let raw = WildmindGrid.bytes(base64: terrain.height) ?? []
        let lookup = terrain.terrains.map { WildmindGround(terrain: $0).rawValue }
        var ground = [UInt8](repeating: 0, count: count)
        var heights = [UInt8](repeating: 0, count: count)
        for k in 0..<count {
            let index = Int(t[k])
            guard index > 0 else { continue }
            ground[k] = index - 1 < lookup.count ? lookup[index - 1] : WildmindGround.open.rawValue
            heights[k] = raw.count == count ? raw[k] : 20
        }
        self.init(version: version, w: terrain.w, h: terrain.h, originX: terrain.originX, originZ: terrain.originZ,
                  step: terrain.step, ground: ground, heights: heights, regions: terrain.regions)
    }

    init(version: String, w: Int, h: Int, originX: Int, originZ: Int, step: Int, ground: [UInt8], heights: [UInt8],
         regions: [WildmindRegion]) {
        self.version = version
        self.w = w
        self.h = h
        self.originX = originX
        self.originZ = originZ
        self.step = max(1, step)
        self.ground = ground
        self.heights = heights
        self.regions = regions
    }

    /// Base64 as Node writes it, forgiving of a missing pad or the URL-safe
    /// alphabet. `nil` for anything that is not base64.
    static func bytes(base64 raw: String) -> [UInt8]? {
        var text = String(raw.filter { !$0.isWhitespace })
        text = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let over = text.count % 4
        if over == 1 { return nil }
        if over > 0 { text += String(repeating: "=", count: 4 - over) }
        guard let data = Data(base64Encoded: text) else { return nil }
        return [UInt8](data)
    }

    func ground(_ i: Int, _ j: Int) -> WildmindGround {
        guard i >= 0, j >= 0, i < w, j < h else { return .unseen }
        return WildmindGround(rawValue: ground[j * w + i]) ?? .open
    }

    /// The height in world units, or `nil` for a cell nobody has seen.
    func height(_ i: Int, _ j: Int) -> Double? {
        guard i >= 0, j >= 0, i < w, j < h else { return nil }
        let byte = heights[j * w + i]
        guard byte > 0, ground[j * w + i] != 0 else { return nil }
        return Double(byte) / 10 - 2
    }

    /// High ground that is not water: the site's relief band.
    func isHigh(_ i: Int, _ j: Int) -> Bool {
        guard i >= 0, j >= 0, i < w, j < h else { return false }
        let k = j * w + i
        let g = WildmindGround(rawValue: ground[k]) ?? .open
        return g.isSeen && !g.isWater && heights[k] >= WildmindGrid.highByte
    }

    /// World tiles to continuous cell units: tile centres sit at the middle
    /// of their cell, `((x - x0 + 0.5) / step, (z - z0 + 0.5) / step)` — the
    /// site's `toMap`.
    func cell(x: Double, z: Double) -> (x: Double, y: Double) {
        ((x - Double(originX) + 0.5) / Double(step), (z - Double(originZ) + 0.5) / Double(step))
    }

    var seenCells: Int { ground.reduce(0) { $0 + ($1 == 0 ? 0 : 1) } }

    /// Metres across one cell: a tile is two metres.
    var metresPerCell: Double { 2 * Double(step) }
}

// MARK: - The frame the grid is drawn in

/// Where a cell lands on the page. A map half as tall again as it is wide fits
/// a phone; one much wider than tall would be a strip, so — as the site does
/// on a phone — it is turned a quarter, west at the top, north on the right.
/// Words stay upright; only the drawing turns.
struct WildmindMapShape: Sendable, Equatable {
    let w: Int
    let h: Int
    let turned: Bool

    init(w: Int, h: Int, turned: Bool? = nil) {
        self.w = w
        self.h = h
        self.turned = turned ?? WildmindMapShape.turns(w: w, h: h)
    }

    /// The site turns a map whose width is 1.2 times its height or more.
    static func turns(w: Int, h: Int) -> Bool {
        h > 0 && Double(w) / Double(h) >= 1.2
    }

    /// The drawing's size in cells, as it sits on the page.
    var width: Int { turned ? h : w }
    var height: Int { turned ? w : h }

    /// A point in continuous cell units, as it sits on the page (still in
    /// cells). Turned: x' = h - y, y' = x.
    func place(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
        turned ? (Double(h) - y, x) : (x, y)
    }

    /// The grid cell under a cell of the drawing.
    func source(_ i: Int, _ j: Int) -> (i: Int, j: Int) {
        turned ? (j, h - 1 - i) : (i, j)
    }

    /// A heading (radians, facing `(sin h, cos h)` in x and z) as a direction
    /// on the page.
    func direction(heading: Double) -> (dx: Double, dy: Double) {
        let dx = sin(heading)
        let dz = cos(heading)
        return turned ? (-dz, dx) : (dx, dz)
    }
}

// MARK: - Outlines

/// A straight run along cell edges, in grid cells (not turned).
struct WildmindSegment: Sendable, Equatable {
    var x0: Double
    var y0: Double
    var x1: Double
    var y1: Double
}

enum WildmindOutline {
    /// The coast — where water meets seen land — and the edge of the known,
    /// where anything seen meets the unseen (or the grid's own border).
    /// Collinear edges are joined into runs, so a dashed edge keeps its
    /// rhythm along a straight stretch.
    static func lines(_ grid: WildmindGrid) -> (coast: [WildmindSegment], edge: [WildmindSegment]) {
        var coast: [WildmindSegment] = []
        var edge: [WildmindSegment] = []

        /// What the edge between two cells is.
        func kind(_ a: WildmindGround, _ b: WildmindGround) -> Int {
            if a.isSeen != b.isSeen { return 2 }
            if a.isSeen && a.isWater != b.isWater { return 1 }
            return 0
        }

        func flush(_ type: Int, _ segment: WildmindSegment) {
            if type == 1 { coast.append(segment) } else if type == 2 { edge.append(segment) }
        }

        // Horizontal edges: the line y = j, between rows j - 1 and j.
        if grid.w > 0 && grid.h > 0 {
            for j in 0...grid.h {
                var runType = 0
                var runStart = 0
                for i in 0...grid.w {
                    let type = i < grid.w ? kind(grid.ground(i, j - 1), grid.ground(i, j)) : 0
                    if type != runType {
                        flush(runType, WildmindSegment(x0: Double(runStart), y0: Double(j), x1: Double(i), y1: Double(j)))
                        runType = type
                        runStart = i
                    }
                }
            }
            // Vertical edges: the line x = i, between columns i - 1 and i.
            for i in 0...grid.w {
                var runType = 0
                var runStart = 0
                for j in 0...grid.h {
                    let type = j < grid.h ? kind(grid.ground(i - 1, j), grid.ground(i, j)) : 0
                    if type != runType {
                        flush(runType, WildmindSegment(x0: Double(i), y0: Double(runStart), x1: Double(i), y1: Double(j)))
                        runType = type
                        runStart = j
                    }
                }
            }
        }
        return (coast, edge)
    }
}

// MARK: - The picture

/// The notes map's inks, resolved (`SnWildmindSheet.svelte`), light and night.
/// Each ground is a page ink mixed into the paper: olive into card stock for
/// open ground, orange into paper for sand, petrol for water, and so on.
struct WildmindPalette: Sendable, Equatable {
    /// RGB per `WildmindGround` raw value (index 0, unseen, is never drawn).
    var grounds: [UInt32]
    /// The woods' 45° hatch: olive.
    var hatch: UInt32
    var hatchAlpha: Double
    /// The high ground's crosshatch: ink.
    var cross: UInt32
    var crossAlpha: Double
    /// The marsh's reeds: olive.
    var reed: UInt32
    var reedAlpha: Double

    static let light = WildmindPalette(
        grounds: [0, 0xE2DCCB, 0xE7D0B8, 0xBCC6BC, 0xAABBB3, 0xBFBEA6, 0xB5BBA9, 0xD4CBBC],
        hatch: 0x55663A, hatchAlpha: 0.55,
        cross: 0x1A1008, crossAlpha: 0.35,
        reed: 0x55663A, reedAlpha: 0.6
    )

    /// Night: the same mixes on the night paper. The olive pencil is the
    /// app's lifted night olive, as `SR.good` is — the site's unchanged
    /// `#55663a` is a smudge on night paper.
    static let night = WildmindPalette(
        grounds: [0, 0x28251A, 0x311F10, 0x1D3030, 0x213C3D, 0x282A1A, 0x253228, 0x2E2924],
        hatch: 0x8A9A5B, hatchAlpha: 0.4,
        cross: 0xECE3D6, crossAlpha: 0.22,
        reed: 0x8A9A5B, reedAlpha: 0.5
    )
}

/// An RGBA picture, premultiplied, four bytes a pixel.
struct WildmindPixels: Sendable, Equatable {
    let width: Int
    let height: Int
    let rgba: [UInt8]
}

enum WildmindRaster {
    /// Pixels per cell: enough for the hatching to read as pen lines, and a
    /// picture no larger than about 1200 pixels on its long side.
    static func pixelsPerCell(_ shape: WildmindMapShape) -> Int {
        max(4, min(12, 1200 / max(1, max(shape.width, shape.height))))
    }

    /// The seen ground, as it sits on the page: each cell in its ground's
    /// ink, shaded by the slope (light from the north-west, as the game's own
    /// map lights it, but gently — this is pencil, not a relief model), with
    /// the woods hatched, the marsh in reeds and the high ground crosshatched.
    /// Unseen cells are left clear, so the paper and its rules show through.
    static func render(_ grid: WildmindGrid, shape: WildmindMapShape, palette: WildmindPalette,
                       pixelsPerCell ppc: Int) -> WildmindPixels {
        let width = shape.width * ppc
        let height = shape.height * ppc
        guard width > 0, height > 0, grid.w == shape.w, grid.h == shape.h else {
            return WildmindPixels(width: 0, height: 0, rgba: [])
        }

        // One shade per cell, from its neighbours' heights.
        var shade = [Double](repeating: 1, count: grid.w * grid.h)
        for j in 0..<grid.h {
            for i in 0..<grid.w {
                let g = grid.ground(i, j)
                guard g.isSeen, !g.isWater, let here = grid.height(i, j) else { continue }
                let hx = (grid.height(i + 1, j) ?? here) - (grid.height(i - 1, j) ?? here)
                let hz = (grid.height(i, j + 1) ?? here) - (grid.height(i, j - 1) ?? here)
                shade[j * grid.w + i] = min(1.14, max(0.82, 1 - (hx + hz) * 0.25))
            }
        }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let scale = Double(ppc)
        let root2 = 2.0.squareRoot()

        /// How much of a pen line of half-width `half` (in cells) covers a
        /// pixel `distance` cells from its centre line: anti-aliased over one
        /// pixel.
        func cover(_ distance: Double, _ half: Double) -> Double {
            min(1, max(0, (half - distance) * scale + 0.5))
        }

        /// Distance (in cells) from `value` to the nearest multiple of `pitch`.
        func off(_ value: Double, _ pitch: Double) -> Double {
            var m = value.truncatingRemainder(dividingBy: pitch)
            if m < 0 { m += pitch }
            return min(m, pitch - m)
        }

        for y in 0..<height {
            let v = (Double(y) + 0.5) / scale
            let cellJ = y / ppc
            for x in 0..<width {
                let cellI = x / ppc
                let source = shape.source(cellI, cellJ)
                let g = grid.ground(source.i, source.j)
                guard g.isSeen else { continue }
                let u = (Double(x) + 0.5) / scale
                let base = palette.grounds[Int(g.rawValue)]
                let s = shade[source.j * grid.w + source.i]
                var r = min(255, Double((base >> 16) & 0xFF) * s)
                var gr = min(255, Double((base >> 8) & 0xFF) * s)
                var b = min(255, Double(base & 0xFF) * s)

                func blend(_ colour: UInt32, _ alpha: Double) {
                    guard alpha > 0 else { return }
                    r = r * (1 - alpha) + Double((colour >> 16) & 0xFF) * alpha
                    gr = gr * (1 - alpha) + Double((colour >> 8) & 0xFF) * alpha
                    b = b * (1 - alpha) + Double(colour & 0xFF) * alpha
                }

                switch g {
                case .wood:
                    // A 45° hatch, 1.4 cells apart, 0.2 wide.
                    blend(palette.hatch, cover(off(u + v, 1.4) / root2, 0.1) * palette.hatchAlpha)
                case .wet:
                    // Reeds: a short upright tick in each cell, every other
                    // row shifted half a cell so they do not stand in ranks.
                    let shift = (Int(v.rounded(.down)) % 2 == 0) ? 0 : 0.5
                    var fu = (u + shift).truncatingRemainder(dividingBy: 1)
                    if fu < 0 { fu += 1 }
                    var fv = v.truncatingRemainder(dividingBy: 1)
                    if fv < 0 { fv += 1 }
                    if fv > 0.28 && fv < 0.72 {
                        blend(palette.reed, cover(abs(fu - 0.5), 0.09) * palette.reedAlpha)
                    }
                default:
                    break
                }
                if g == .high || grid.isHigh(source.i, source.j) {
                    // A crosshatch, 1.6 cells apart, 0.12 wide, both ways.
                    let one = cover(off(u + v, 1.6) / root2, 0.06)
                    let two = cover(off(u - v, 1.6) / root2, 0.06)
                    blend(palette.cross, max(one, two) * palette.crossAlpha)
                }

                let k = (y * width + x) * 4
                rgba[k] = UInt8(max(0, min(255, r.rounded())))
                rgba[k + 1] = UInt8(max(0, min(255, gr.rounded())))
                rgba[k + 2] = UInt8(max(0, min(255, b.rounded())))
                rgba[k + 3] = 255
            }
        }
        return WildmindPixels(width: width, height: height, rgba: rgba)
    }
}
