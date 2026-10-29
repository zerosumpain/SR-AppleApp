import Foundation

// The things Orbit draws that are not the rules: sparks from a crash or an
// arrival, the scattered starfield behind the play, and the rocks that make
// a belt look like a belt. Plain values made from a seed, so every phone
// draws the same sky and nothing here allocates once a level has started.

/// What colour a spark is, picked by the drawing.
enum OrbitSparkTone: Int {
    /// White-hot to orange: a crash or a burn-up.
    case fire
    /// Cyan and white: an arrival at a station.
    case dock
    /// Violet and pink: through a wormhole.
    case warp
    /// Gold: a star picked up.
    case gold
}

/// One spark: where it is, where it is going and how long it has left.
struct OrbitSpark: Equatable {
    var at: OrbitVec
    var velocity: OrbitVec
    /// Seconds left, and the seconds it started with.
    var life: Double
    var span: Double
    /// Radius in world units at the start of its life.
    var size: Double
    var tone: OrbitSparkTone

    /// 1 when new, 0 when spent.
    var fade: Double { span > 0 ? max(0, min(1, life / span)) : 0 }
}

/// Every spark on screen. A fixed cap keeps a frame's work bounded however
/// often things blow up.
struct OrbitSparks {
    static let cap = 320

    private(set) var items: [OrbitSpark] = []
    private var random = OrbitRandom(seed: 0x0_5EED)

    init() {
        items.reserveCapacity(Self.cap)
    }

    var isEmpty: Bool { items.isEmpty }

    /// `count` sparks flung out from `at`, up to `speed` units a second.
    mutating func burst(at: OrbitVec, count: Int, speed: Double, life: Double, size: Double, tone: OrbitSparkTone,
                        carry: OrbitVec = .zero) {
        let room = max(0, Self.cap - items.count)
        let n = min(count, room)
        guard n > 0 else { return }
        for _ in 0..<n {
            let angle = random.range(0, 2 * Double.pi)
            let v = OrbitVec.heading(angle) * (speed * (0.25 + 0.75 * random.unit())) + carry
            let span = life * (0.55 + 0.45 * random.unit())
            items.append(OrbitSpark(at: at, velocity: v, life: span, span: span,
                                    size: size * (0.6 + 0.8 * random.unit()), tone: tone))
        }
    }

    /// Moves every spark on and lets the spent ones go. Sparks slow as they
    /// fly, the way a puff of gas spreads and stops.
    mutating func step(_ dt: Double) {
        guard !items.isEmpty, dt > 0 else { return }
        let drag = max(0, 1 - 1.8 * dt)
        var i = 0
        while i < items.count {
            items[i].life -= dt
            if items[i].life <= 0 {
                items.swapAt(i, items.count - 1)
                items.removeLast()
                continue
            }
            items[i].at += items[i].velocity * dt
            items[i].velocity = items[i].velocity * drag
            i += 1
        }
    }

    mutating func clear() {
        items.removeAll(keepingCapacity: true)
    }
}

/// One star in the background sky.
struct OrbitSkyStar: Equatable {
    /// 0…1 across and down the sky tile.
    var x: Double
    var y: Double
    /// Radius in points.
    var size: Double
    /// 0…1.
    var brightness: Double
    /// Where in its twinkle it starts, radians.
    var twinkle: Double
    /// A few are faintly blue or warm rather than white.
    var tint: Int
}

/// A rock in a belt, placed once per level.
struct OrbitRock: Equatable {
    var at: OrbitVec
    var radius: Double
    /// Which of the rock shades it is.
    var shade: Int
    /// Turned by this much, radians, so the rocks are not all alike.
    var spin: Double
}

/// The sky behind the play: three layers of stars at different depths (the
/// far ones move least as the probe flies, which reads as depth) and the
/// rocks of every belt in the level.
struct OrbitSkyLayout: Equatable {
    /// Back to front. Each layer is a tile of stars that repeats.
    let layers: [[OrbitSkyStar]]
    /// How much each layer moves with the camera: 0 is fixed to the screen.
    static let depths: [Double] = [0.04, 0.10, 0.22]
    let rocks: [OrbitRock]

    init(level: OrbitLevel?, seed: UInt64 = 7) {
        var random = OrbitRandom(seed: seed)
        var layers: [[OrbitSkyStar]] = []
        let counts = [110, 60, 26]
        for (layer, count) in counts.enumerated() {
            var stars: [OrbitSkyStar] = []
            stars.reserveCapacity(count)
            for _ in 0..<count {
                let base = 0.35 + 0.35 * Double(layer)
                stars.append(OrbitSkyStar(x: random.unit(), y: random.unit(),
                                          size: (0.45 + random.unit() * 0.6) * (1 + 0.55 * Double(layer)),
                                          brightness: min(1, base + random.unit() * 0.45),
                                          twinkle: random.range(0, 2 * Double.pi),
                                          tint: random.unit() < 0.18 ? (random.unit() < 0.5 ? 1 : 2) : 0))
            }
            layers.append(stars)
        }
        self.layers = layers
        rocks = level.map { Self.rocks(for: $0.belts, seed: seed &+ UInt64($0.number)) } ?? []
    }

    /// Rocks scattered through each belt: enough to read as solid, only
    /// where they could ever be seen (a wall drawn as part of a huge ring
    /// keeps its rocks on the field).
    static func rocks(for belts: [OrbitBelt], seed: UInt64) -> [OrbitRock] {
        var random = OrbitRandom(seed: seed)
        var out: [OrbitRock] = []
        for belt in belts {
            let middle = (belt.inner + belt.outer) / 2
            let thickness = belt.outer - belt.inner
            let length = middle * min(belt.span, 2 * Double.pi)
            let count = min(260, max(8, Int(length * thickness / 260)))
            var placed = 0, tries = 0
            while placed < count && tries < count * 4 {
                tries += 1
                let a = belt.start + random.unit() * min(belt.span, 2 * Double.pi)
                let r = belt.inner + thickness * (0.08 + 0.84 * random.unit())
                let p = OrbitVec(belt.centre.x + r * cos(a), belt.centre.y + r * sin(a))
                guard OrbitField.holds(p) else { continue }
                out.append(OrbitRock(at: p, radius: 2.5 + random.unit() * min(7, thickness * 0.22),
                                     shade: Int(random.unit() * 3), spin: random.range(0, 2 * Double.pi)))
                placed += 1
            }
        }
        return out
    }
}

/// Where the 600 by 900 field sits on a screen of any size: scaled to fit
/// whole, centred, and the sums both ways for drawing and for touches.
struct OrbitViewport: Equatable {
    let width: Double
    let height: Double
    let scale: Double
    let originX: Double
    let originY: Double

    init(width: Double, height: Double) {
        self.width = max(width, 1)
        self.height = max(height, 1)
        scale = min(self.width / OrbitField.width, self.height / OrbitField.height)
        originX = (self.width - OrbitField.width * scale) / 2
        originY = (self.height - OrbitField.height * scale) / 2
    }

    /// A world point on the screen.
    func screen(_ p: OrbitVec) -> OrbitVec {
        OrbitVec(originX + p.x * scale, originY + p.y * scale)
    }

    /// A screen point in the world.
    func world(_ x: Double, _ y: Double) -> OrbitVec {
        OrbitVec((x - originX) / scale, (y - originY) / scale)
    }

    /// The part of the world the screen shows, which is more than the field
    /// itself on a phone wider or taller than two by three.
    var visibleWorld: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let a = world(0, 0), b = world(width, height)
        return (a.x, a.y, b.x, b.y)
    }

    /// Where an arrow at the edge of the screen should point to a probe that
    /// has swung out of sight, inset by `inset` points; nil while it is in view.
    func edgeMarker(for p: OrbitVec, inset: Double) -> OrbitVec? {
        let s = screen(p)
        if s.x >= 0 && s.x <= width && s.y >= 0 && s.y <= height { return nil }
        return OrbitVec(min(max(s.x, inset), width - inset), min(max(s.y, inset), height - inset))
    }
}
