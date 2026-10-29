import Foundation

// Car Race: a top-down race round a closed track, steered by tilting the
// phone (or by touch), alone against your own best lap's ghost, passed round
// one phone, two to four at once on one split screen, or phone to phone nearby.
//
// Everything that decides a race lives here, free of SwiftUI and Core Motion:
// the tracks and their scenery, the car's physics (speed, drag, grip, a drift
// when the tyres let go, and a boost that drifting refills), the walls, cars knocking into each other, lap counting, the ghost a
// run leaves behind and the pilot that drives demo mode. The screen turns tilt and touch into a
// `CarInput`, calls `CarPhysics.step` once a frame and draws what comes back.
//
// Units are METRES and SECONDS. The world is screen-shaped: x runs right and
// y runs DOWN, so a heading of 0 points right and a positive turn is clockwise
// on the screen — tilt right, turn right.

/// A point or a direction in the plane.
struct CarVec: Codable, Equatable {
    var x: Double
    var y: Double

    static let zero = CarVec(x: 0, y: 0)

    static func + (a: CarVec, b: CarVec) -> CarVec { CarVec(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CarVec, b: CarVec) -> CarVec { CarVec(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CarVec, k: Double) -> CarVec { CarVec(x: a.x * k, y: a.y * k) }
    func dot(_ b: CarVec) -> Double { x * b.x + y * b.y }
    var length: Double { (x * x + y * y).squareRoot() }

    /// Turned `angle` radians clockwise on the screen (y runs down).
    func rotated(by angle: Double) -> CarVec {
        let c = cos(angle), s = sin(angle)
        return CarVec(x: x * c - y * s, y: x * s + y * c)
    }

    /// The unit vector at `angle` radians.
    static func heading(_ angle: Double) -> CarVec { CarVec(x: cos(angle), y: sin(angle)) }
}

/// Where a point sits against a track: how far round it is, and how far off
/// the middle line.
struct CarTrackSpot: Equatable {
    /// Metres round from the start line, 0..<length.
    let distance: Double
    /// Metres from the middle line; positive is to the driver's right.
    let offset: Double
    /// The nearest point on the middle line.
    let centre: CarVec
    /// The track's direction there, radians.
    let direction: Double
}

/// What a circuit is built through: the ground the screen paints, and what
/// stands on it beside the road.
enum CarScenery: String, Codable, CaseIterable {
    /// Grass, and nothing on it: the first three tracks.
    case meadow
    /// Open water either side of a sandy causeway, boats moored off it.
    case harbour
    case forest
    case desert
    case snow
    /// City blocks either side of the streets.
    case city
}

/// Something beside the road, for the drawing only: a tree, a rock, a boat,
/// a building. Never on the road and never solid — it is scenery.
struct CarProp: Equatable {
    let at: CarVec
    /// Its radius (half a side for a building), metres.
    let size: Double
    /// Which way it lies, radians.
    let turn: Double
    /// 0..<1, for picking among a scenery's shades.
    let shade: Double
}

/// A closed circuit: its middle line as points close enough together to read
/// as a curve, its width, and its scenery.
struct CarTrack: Identifiable, Equatable {
    let id: String
    let name: String
    /// One sentence for the picker.
    let line: String
    let width: Double
    let scenery: CarScenery
    /// What stands beside the road, placed once when the track is built.
    private(set) var props: [CarProp] = []
    /// The middle line, in racing order; the last point joins back to the first.
    let points: [CarVec]
    /// Metres round to each point.
    let distances: [Double]
    let length: Double

    /// A track through `control` points, smoothed into a curve (Catmull-Rom,
    /// `samples` points per span) and closed.
    init(id: String, name: String, line: String, width: Double, scenery: CarScenery = .meadow,
         control: [(Double, Double)], samples: Int = 14) {
        self.id = id
        self.name = name
        self.line = line
        self.width = width
        self.scenery = scenery
        let c = control.map { CarVec(x: $0.0, y: $0.1) }
        var points: [CarVec] = []
        let n = c.count
        for i in 0..<n {
            let p0 = c[(i - 1 + n) % n], p1 = c[i], p2 = c[(i + 1) % n], p3 = c[(i + 2) % n]
            for k in 0..<samples {
                let t = Double(k) / Double(samples)
                let t2 = t * t, t3 = t2 * t
                func blend(_ a: Double, _ b: Double, _ cc: Double, _ d: Double) -> Double {
                    0.5 * (2 * b + (-a + cc) * t + (2 * a - 5 * b + 4 * cc - d) * t2 + (-a + 3 * b - 3 * cc + d) * t3)
                }
                points.append(CarVec(x: blend(p0.x, p1.x, p2.x, p3.x), y: blend(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        self.points = points
        var distances: [Double] = []
        var run = 0.0
        for i in 0..<points.count {
            distances.append(run)
            run += (points[(i + 1) % points.count] - points[i]).length
        }
        self.distances = distances
        length = run
        props = Self.place(scenery, around: self)
    }

    static func == (a: CarTrack, b: CarTrack) -> Bool { a.id == b.id }

    /// The point `distance` metres round (wrapping), and the track's direction there.
    func point(at distance: Double) -> (at: CarVec, direction: Double) {
        guard length > 0, points.count > 1 else { return (points.first ?? .zero, 0) }
        var d = distance.truncatingRemainder(dividingBy: length)
        if d < 0 { d += length }
        // Binary search for the span holding `d`.
        var lo = 0, hi = distances.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if distances[mid] <= d { lo = mid } else { hi = mid - 1 }
        }
        let a = points[lo], b = points[(lo + 1) % points.count]
        let span = (b - a).length
        let t = span > 0 ? (d - distances[lo]) / span : 0
        return (a + (b - a) * t, atan2(b.y - a.y, b.x - a.x))
    }

    /// Where `p` sits against the track: the nearest point on the middle line.
    func spot(of p: CarVec) -> CarTrackSpot {
        var best = Double.infinity
        var result = CarTrackSpot(distance: 0, offset: 0, centre: points.first ?? .zero, direction: 0)
        let count = points.count
        for i in 0..<count {
            let a = points[i], b = points[(i + 1) % count]
            let ab = b - a
            let span2 = ab.dot(ab)
            let t = span2 > 0 ? min(max((p - a).dot(ab) / span2, 0), 1) : 0
            let q = a + ab * t
            let d2 = (p - q).dot(p - q)
            if d2 < best {
                best = d2
                let span = span2.squareRoot()
                // Right of the direction of travel, in a y-down world: (-dy, dx).
                let right = span > 0 ? CarVec(x: -ab.y / span, y: ab.x / span) : .zero
                result = CarTrackSpot(distance: distances[i] + span * t, offset: (p - q).dot(right),
                                      centre: q, direction: atan2(ab.y, ab.x))
            }
        }
        return result
    }

    /// Where car `slot` (0-based) lines up: two abreast, behind the line.
    func grid(_ slot: Int) -> (at: CarVec, heading: Double) {
        let row = Double(slot / 2), side = slot % 2 == 0 ? -1.0 : 1.0
        let start = point(at: -6 - row * 9)
        let right = CarVec(x: -sin(start.direction), y: cos(start.direction))
        return (start.at + right * (side * width * 0.22), start.direction)
    }

    /// The box the track fits in, with its width: for the mini-map.
    var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let xs = points.map(\.x), ys = points.map(\.y), pad = width / 2
        return ((xs.min() ?? 0) - pad, (ys.min() ?? 0) - pad, (xs.max() ?? 0) + pad, (ys.max() ?? 0) + pad)
    }

    /// Metres of verge beside the kerb that scenery keeps off: the sand of a
    /// causeway, a city's pavement, or just room to run wide.
    var verge: Double {
        switch scenery {
        case .harbour: return 5
        case .city: return 4
        default: return 2.5
        }
    }

    /// Scenery for `scenery` round `track`: a jittered grid over the ground
    /// near the road, each spot kept only if the whole prop clears the road
    /// and its verge. Seeded by the track's id, so it is the same every race.
    private static func place(_ scenery: CarScenery, around track: CarTrack) -> [CarProp] {
        let (spacing, smallest, largest, reach): (Double, Double, Double, Double)
        switch scenery {
        case .meadow: return []
        case .harbour: (spacing, smallest, largest, reach) = (26, 1.4, 2.6, 60)
        case .forest: (spacing, smallest, largest, reach) = (9, 2.2, 4.2, 45)
        case .desert: (spacing, smallest, largest, reach) = (17, 1.0, 3.2, 50)
        case .snow: (spacing, smallest, largest, reach) = (10, 1.6, 3.0, 40)
        case .city: (spacing, smallest, largest, reach) = (17, 5.5, 7.5, 40)
        }
        // A splitmix64 seeded by the id's bytes: no Foundation randomness, so
        // the same scenery on every phone and in every test.
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for byte in track.id.utf8 { seed = (seed ^ UInt64(byte)) &* 0x1000_0000_01B3 }
        func next() -> Double {
            seed &+= 0x9E37_79B9_7F4A_7C15
            var z = seed
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
        let b = track.bounds
        let clear = track.width / 2 + track.verge
        var props: [CarProp] = []
        var y = b.minY - reach
        while y <= b.maxY + reach {
            var x = b.minX - reach
            while x <= b.maxX + reach {
                let at = CarVec(x: x + (next() - 0.5) * spacing * 0.8, y: y + (next() - 0.5) * spacing * 0.8)
                let size = smallest + (largest - smallest) * next()
                let turn = scenery == .city ? 0 : next() * 2 * .pi
                let shade = next()
                // A building's corner reaches further than its side.
                let footprint = scenery == .city ? size * 1.42 : size
                let off = abs(track.spot(of: at).offset)
                if off > clear + footprint, off < clear + reach {
                    props.append(CarProp(at: at, size: size, turn: turn, shade: shade))
                }
                x += spacing
            }
            y += spacing
        }
        return props
    }

    // MARK: - The circuits

    static let paddock = CarTrack(
        id: "paddock", name: "Paddock Oval", line: "Two long straights and two fast bends. Flat out.",
        width: 16,
        control: [(0, 0), (90, 0), (180, 0), (225, 45), (180, 95), (90, 95), (0, 95), (-45, 45)])

    static let riverside = CarTrack(
        id: "riverside", name: "Riverside", line: "A kink, a hairpin and a sweeping run home.",
        width: 15,
        control: [(0, 0), (110, -10), (190, 30), (200, 100), (150, 120), (110, 80), (60, 120),
                  (0, 150), (-50, 110), (-50, 40)])

    static let quarry = CarTrack(
        id: "quarry", name: "The Quarry", line: "Tight and twisty. Brake, drift, repeat.",
        width: 14,
        control: [(0, 0), (80, -20), (150, 10), (150, 70), (100, 80), (90, 130), (150, 160),
                  (130, 220), (40, 210), (20, 150), (-40, 140), (-60, 70)])

    static let harbour = CarTrack(
        id: "harbour", name: "Harbour Wall", line: "Along the sea wall, out to the end of the pier and back.",
        width: 15, scenery: .harbour,
        control: [(0, 0), (100, 0), (200, 0), (255, 25), (255, 85), (245, 170), (222, 200), (196, 175),
                  (194, 100), (150, 70), (95, 95), (45, 120), (-20, 110), (-50, 55)])

    static let forest = CarTrack(
        id: "forest", name: "Pinewood Esses", line: "Left, right, left through the trees. Find a rhythm.",
        width: 14, scenery: .forest,
        control: [(0, 0), (60, -30), (120, 5), (185, -35), (255, -5), (300, 55), (270, 125), (205, 110),
                  (165, 155), (105, 120), (50, 160), (-10, 135), (-55, 90), (-45, 35)])

    static let canyon = CarTrack(
        id: "canyon", name: "Canyon Run", line: "Wide and fast, with one hairpin to catch you out. Boost the straights.",
        width: 18, scenery: .desert,
        control: [(0, 0), (160, -20), (320, -5), (410, 50), (420, 130), (360, 175), (285, 160), (262, 105),
                  (258, 62), (235, 40), (210, 62), (205, 120), (160, 185), (60, 195), (-30, 170), (-70, 100),
                  (-50, 30)])

    static let alpine = CarTrack(
        id: "alpine", name: "Alpine Pass", line: "Narrow switchbacks up the mountain and a long run down.",
        width: 13, scenery: .snow,
        control: [(0, 0), (120, 0), (158, 22), (140, 50), (40, 58), (18, 85), (40, 110), (140, 115),
                  (160, 142), (138, 170), (-30, 170), (-62, 130), (-62, 40), (-38, 8)])

    /// Square corners round city blocks: points every 25 m or so down each
    /// street and two either side of each corner, so the curve turns sharply
    /// there and runs straight between.
    static let city = CarTrack(
        id: "city", name: "Night Streets", line: "Right-angle corners round the blocks. Brake late, turn hard.",
        width: 13, scenery: .city,
        control: [(28, 0), (52, 0), (75, 0), (98, 0), (110, -12), (110, -33), (122, -45), (147, -45),
                  (173, -45), (198, -45), (210, -33), (210, -5), (210, 22), (210, 50), (210, 78), (198, 90),
                  (176, 90), (155, 90), (134, 90), (112, 90), (100, 102), (100, 125), (100, 148), (88, 160),
                  (62, 160), (35, 160), (8, 160), (-18, 160), (-30, 148), (-30, 121), (-30, 94), (-30, 66),
                  (-30, 39), (-30, 12), (-18, 0), (5, 0)],
        samples: 6)

    static let all: [CarTrack] = [.paddock, .riverside, .quarry, .harbour, .forest, .canyon, .alpine, .city]

    /// The tracks a race nearby draws from: only those every phone in the
    /// room knows. A phone a build behind would not find a newer track by
    /// its id and would race a different one, so a track joins this list
    /// only once every phone has had a build with it.
    static let nearby: [CarTrack] = [.paddock, .riverside, .quarry]

    static func named(_ id: String) -> CarTrack? { all.first { $0.id == id } }
}

/// One car: where it is, which way it points, how it moves.
struct CarState: Codable, Equatable {
    var x: Double
    var y: Double
    /// Radians; 0 points right, positive turns clockwise on screen.
    var heading: Double
    var vx: Double = 0
    var vy: Double = 0
    /// The tyres have let go: the car is sliding sideways. For the screen's smoke.
    var drifting = false
    /// The boost tank, 0…1: full on the grid, drained while boosting,
    /// refilled while driving, and faster while drifting.
    var boost: Double = 1
    /// Boosting this step: for the flames.
    var boosting = false

    init(x: Double, y: Double, heading: Double) {
        self.x = x
        self.y = y
        self.heading = heading
    }

    var position: CarVec { CarVec(x: x, y: y) }
    var velocity: CarVec { CarVec(x: vx, y: vy) }
    var speed: Double { velocity.length }
    /// Speed along the way the car points; negative when reversing.
    var forwardSpeed: Double { velocity.dot(.heading(heading)) }
    /// The car as another car meets it.
    var body: CarBody { CarBody(at: position, heading: heading, velocity: velocity) }
}

/// What the driver asks for this frame.
struct CarInput: Equatable {
    /// −1 brakes (and then reverses), 1 is full throttle.
    var throttle: Double = 0
    /// −1 full left, 1 full right.
    var steer: Double = 0
    /// The boost is held: extra thrust while the tank lasts.
    var boost = false
}

/// A knock against the wall this step: how hard, for a haptic.
struct CarWallHit: Equatable {
    /// Speed into the wall, m/s.
    let impact: Double
}

/// The car's handling and the walls.
enum CarPhysics {
    /// Full throttle, m/s².
    static let engine: Double = 15
    static let brake: Double = 24
    static let reverse: Double = 5
    /// Air drag: top speed is where it matches the engine (about 41 m/s).
    static let drag: Double = 0.0088
    /// Rolling resistance, per second.
    static let rolling: Double = 0.25
    /// Full lock, radians a second, at a speed that lets the car turn properly.
    static let steerRate: Double = 2.6
    /// Below this the wheels turn the car less: no spinning on the spot.
    static let turnInSpeed: Double = 8
    /// How quickly sideways sliding dies away, per second: gripping, and drifting.
    static let grip: Double = 9
    static let driftGrip: Double = 2.2
    /// Sideways speed at which the tyres let go, m/s, and grip back below.
    static let breakaway: Double = 5.5
    static let regrip: Double = 2.5
    /// Half the car's width, for the walls.
    static let halfWidth: Double = 1.0
    /// Speed kept off a wall: the bounce, and the scrub along it.
    static let bounce: Double = 0.3
    static let scrub: Double = 0.82
    /// The longest step taken at once; a slow frame is split into these.
    static let maxStep: Double = 1.0 / 120
    /// Boost: thrust on top of the engine, m/s², while the tank lasts. With
    /// it held the top speed climbs from about 29 m/s towards 44.
    static let boostThrust: Double = 13
    /// A full tank lasts this long, held down, seconds.
    static let boostBurn: Double = 2.2
    /// An empty tank refills in this long, driving, seconds — and in
    /// `driftRefill` while drifting, so a good drift pays for a boost out of it.
    static let boostRefill: Double = 14
    static let driftRefill: Double = 4

    /// Drive for `dt` seconds. Returns the hardest wall hit, if any.
    @discardableResult
    static func step(_ car: inout CarState, input: CarInput, track: CarTrack, dt: Double) -> CarWallHit? {
        guard dt > 0 else { return nil }
        var left = min(dt, 0.25)
        var hardest: CarWallHit?
        while left > 1e-9 {
            let h = min(left, maxStep)
            if let hit = substep(&car, input: input, track: track, h: h), hit.impact > (hardest?.impact ?? 0) {
                hardest = hit
            }
            left -= h
        }
        return hardest
    }

    private static func substep(_ car: inout CarState, input: CarInput, track: CarTrack, h: Double) -> CarWallHit? {
        let throttle = min(max(input.throttle, -1), 1)
        let steer = min(max(input.steer, -1), 1)
        let forward = CarVec.heading(car.heading)
        let right = CarVec(x: -forward.y, y: forward.x)
        var along = car.velocity.dot(forward)
        var across = car.velocity.dot(right)

        // Boost: on top of the engine, for as long as the tank lasts. Holding
        // it with the tank empty does nothing, and refills nothing.
        car.boosting = input.boost && throttle >= 0 && car.boost > 0
        if car.boosting {
            along += boostThrust * h
            car.boost = max(0, car.boost - h / boostBurn)
        } else if !input.boost {
            car.boost = min(1, car.boost + h / (car.drifting ? driftRefill : boostRefill))
        }

        // Engine, brakes and reverse.
        if throttle >= 0 {
            along += engine * throttle * h
        } else if along > 0.5 {
            along = max(0, along + brake * throttle * h)
        } else {
            along += reverse * throttle * h
        }
        along -= (drag * along * abs(along) + rolling * along) * h

        // Steering: a bicycle's turn, weaker at a crawl and a little weaker flat out.
        let speedFactor = min(1, abs(along) / turnInSpeed) / (1 + abs(along) / 60)
        let turn = steer * steerRate * speedFactor * (along >= 0 ? 1 : -1)
        car.heading += turn * h

        // Grip: sideways speed dies away, slowly once the tyres have let go.
        if abs(across) > breakaway { car.drifting = true } else if abs(across) < regrip { car.drifting = false }
        across *= exp(-(car.drifting ? driftGrip : grip) * h)

        // The old velocity stays pointing where it was, so a turn leaves some
        // of it sideways: that is where the drift comes from.
        let velocity = forward * along + right * across
        car.vx = velocity.x
        car.vy = velocity.y
        car.x += car.vx * h
        car.y += car.vy * h

        // The walls: past the edge, put back and bounced off.
        let spot = track.spot(of: car.position)
        let limit = track.width / 2 - halfWidth
        guard abs(spot.offset) > limit else { return nil }
        let side = spot.offset > 0 ? 1.0 : -1.0
        let normal = CarVec(x: -sin(spot.direction), y: cos(spot.direction)) * side
        let push = abs(spot.offset) - limit
        car.x -= normal.x * push
        car.y -= normal.y * push
        let into = car.velocity.dot(normal)
        guard into > 0 else { return nil }
        let along2 = car.velocity - normal * into
        let next = along2 * scrub - normal * (into * bounce)
        car.vx = next.x
        car.vy = next.y
        return CarWallHit(impact: into)
    }
}

// MARK: - Car against car

/// Another car as this one meets it: where it is, which way it points and
/// how fast it is going.
struct CarBody: Equatable {
    var at: CarVec
    var heading: Double
    var velocity: CarVec = .zero
}

/// Where two shapes overlap: which way to push the first one out, and how far.
struct CarContact: Equatable {
    /// A unit vector, from the second shape towards the first.
    let normal: CarVec
    /// Metres the shapes overlap.
    let depth: Double
}

/// A knock against another car: how hard, for a haptic, and what it did.
struct CarBump: Equatable {
    /// Closing speed along the line of the hit, m/s.
    let impact: Double
    /// The change to this car's velocity.
    let kick: CarVec
}

/// Cars that touch: their shapes, where they overlap and the bounce.
///
/// For a hit, MY car is its box (4.4 m by 2.2, as drawn) and the other car is
/// two circles, nose and tail, that fill its box lengthways: box against box
/// is a lot of maths for no difference a player could feel.
///
/// The bounce is an impulse along the line of the hit with some restitution,
/// and each car takes its `share` of it: two cars of the same weight take half
/// each. On one phone both halves are applied at once (`pair`). Phone to phone,
/// each phone applies ITS OWN half to ITS OWN car only, against where it last
/// heard the other car was, carried on at its speed (`CarGhost.predict`) —
/// and the other phone does the same from its side. Nobody's phone ever moves
/// somebody else's car, so a slow link can make a knock a moment late or a
/// little soft, but never teleports a car the other phone has not seen hit.
/// A short cooldown per car stops one knock bouncing twice while the other
/// car's news catches up.
enum CarCollision {
    static let halfLength: Double = 2.2
    static let halfWidth: Double = 1.1
    /// How much of the closing speed comes back out of a hit: bumper cars,
    /// not billiard balls.
    static let restitution: Double = 0.4
    /// After a bounce off a car, no second bounce off the same car for this
    /// long, seconds.
    static let cooldown: Double = 0.3
    /// A nearby car is carried on from its last report at most this far,
    /// seconds, and is solid only while that report is no older than this.
    static let horizon: Double = 0.5

    /// Circle `a` against circle `b`: the push that moves `a` out of `b`.
    static func circles(_ a: CarVec, _ ra: Double, _ b: CarVec, _ rb: Double) -> CarContact? {
        let d = a - b
        let distance = d.length
        guard distance < ra + rb else { return nil }
        // Dead on top of each other: any way out will do.
        let normal = distance > 1e-9 ? d * (1 / distance) : CarVec(x: 1, y: 0)
        return CarContact(normal: normal, depth: ra + rb - distance)
    }

    /// A box (centre, heading, half its length and width) against a circle:
    /// the push that moves the box out of the circle.
    static func box(at centre: CarVec, heading: Double, halfLength: Double, halfWidth: Double,
                    circle: CarVec, radius: Double) -> CarContact? {
        let forward = CarVec.heading(heading)
        let right = CarVec(x: -forward.y, y: forward.x)
        let d = circle - centre
        let lx = d.dot(forward), ly = d.dot(right)
        // The point of the box nearest the circle's centre, in the box's own frame.
        let qx = min(max(lx, -halfLength), halfLength)
        let qy = min(max(ly, -halfWidth), halfWidth)
        let gap = CarVec(x: lx - qx, y: ly - qy)
        let distance = gap.length
        if distance > 1e-9 {
            guard distance < radius else { return nil }
            // Away from the circle: the box moves opposite the way to it.
            let local = gap * (-1 / distance)
            return CarContact(normal: forward * local.x + right * local.y, depth: radius - distance)
        }
        // The circle's centre is inside the box: out by the shallowest side.
        let overX = halfLength - abs(lx), overY = halfWidth - abs(ly)
        if overX < overY {
            return CarContact(normal: forward * (lx > 0 ? -1 : 1), depth: overX + radius)
        }
        return CarContact(normal: right * (ly > 0 ? -1 : 1), depth: overY + radius)
    }

    /// The other car's nose and tail circles.
    static func circles(of car: CarBody) -> [CarVec] {
        let along = CarVec.heading(car.heading) * (halfLength - halfWidth)
        return [car.at + along, car.at - along]
    }

    /// My car's box against the other car's circles: the deepest overlap.
    static func contact(_ me: CarBody, _ other: CarBody) -> CarContact? {
        // Too far apart to touch: skip the maths.
        let reach = 2 * (halfLength + halfWidth)
        guard (me.at - other.at).dot(me.at - other.at) < reach * reach else { return nil }
        var deepest: CarContact?
        for c in circles(of: other) {
            // A micron of overlap is rounding, not a touch.
            if let hit = box(at: me.at, heading: me.heading, halfLength: halfLength, halfWidth: halfWidth,
                             circle: c, radius: halfWidth),
               hit.depth > max(deepest?.depth ?? 0, 1e-6) {
                deepest = hit
            }
        }
        return deepest
    }

    /// The bounce for a car moving at `mine` off one moving at `theirs`, along
    /// `normal` (from them to me): this car's `share` of the impulse. Nil when
    /// they are already moving apart.
    static func bounce(_ mine: CarVec, off theirs: CarVec, normal: CarVec, share: Double = 0.5) -> CarBump? {
        let closing = (mine - theirs).dot(normal)
        guard closing < 0 else { return nil }
        return CarBump(impact: -closing, kick: normal * (-(1 + restitution) * closing * share))
    }

    /// My car against the other cars as last heard of: pushed out of any it
    /// overlaps by its share of the overlap, and bounced off one it is closing
    /// on unless it bounced off that one within the cooldown. Only `car`
    /// changes. Returns the hardest bounce.
    @discardableResult
    static func collide(_ car: inout CarState, with others: [(id: String, body: CarBody)],
                        clock: inout CarBumpClock, at time: Double, share: Double = 0.5) -> CarBump? {
        var hardest: CarBump?
        for other in others {
            guard let hit = contact(car.body, other.body) else { continue }
            car.x += hit.normal.x * hit.depth * share
            car.y += hit.normal.y * hit.depth * share
            guard clock.ready(other.id, at: time),
                  let bump = bounce(car.velocity, off: other.body.velocity, normal: hit.normal, share: share) else { continue }
            clock.note(other.id, at: time)
            car.vx += bump.kick.x
            car.vy += bump.kick.y
            if bump.impact > (hardest?.impact ?? 0) { hardest = bump }
        }
        return hardest
    }

    /// Two cars in the same simulation (split screen): pushed apart half each
    /// and bounced off each other, both at once. Returns `a`'s bounce.
    @discardableResult
    static func pair(_ a: inout CarState, _ b: inout CarState) -> CarBump? {
        guard let hit = contact(a.body, b.body) else { return nil }
        let push = hit.normal * (hit.depth / 2)
        a.x += push.x
        a.y += push.y
        b.x -= push.x
        b.y -= push.y
        guard let bump = bounce(a.velocity, off: b.velocity, normal: hit.normal) else { return nil }
        a.vx += bump.kick.x
        a.vy += bump.kick.y
        b.vx -= bump.kick.x
        b.vy -= bump.kick.y
        return bump
    }
}

/// When my car last bounced off each other car, for the cooldown.
struct CarBumpClock: Equatable {
    private(set) var last: [String: Double] = [:]

    func ready(_ id: String, at time: Double) -> Bool {
        guard let then = last[id] else { return true }
        return time - then >= CarCollision.cooldown || time < then
    }

    mutating func note(_ id: String, at time: Double) { last[id] = time }
}

/// Counts laps by distance actually driven round the track, so driving
/// backwards over the line, or cutting across, never counts.
struct CarLapCounter: Codable, Equatable {
    let length: Double
    let laps: Int
    /// Metres driven round, from the start line; negative on the grid behind it.
    private(set) var raced: Double
    private(set) var lastDistance: Double
    /// Race seconds at which each lap was completed.
    private(set) var splits: [Double] = []

    init(length: Double, laps: Int, startDistance: Double) {
        self.length = length
        self.laps = max(1, laps)
        lastDistance = startDistance
        raced = startDistance > length / 2 ? startDistance - length : startDistance
    }

    var finished: Bool { splits.count >= laps }
    /// The lap being driven, 1-based, at most `laps`.
    var lap: Int { min(laps, splits.count + 1) }
    /// The finish time, race seconds.
    var finishTime: Double? { finished ? splits.last : nil }
    /// Each lap's own time.
    var lapTimes: [Double] { zip(splits, [0] + splits).map { $0 - $1 } }
    var bestLap: Double? { lapTimes.min() }
    /// Laps done as a fraction of the race, 0…1.
    var progress: Double { min(1, max(0, raced / (length * Double(laps)))) }

    /// The car is now `distance` round the track, `time` seconds into the race.
    mutating func update(distance: Double, time: Double) {
        guard !finished else { return }
        var step = distance - lastDistance
        // Across the line one way or the other: the shorter way round is the truth.
        if step < -length / 2 { step += length }
        if step > length / 2 { step -= length }
        lastDistance = distance
        let before = raced
        raced += step
        let done = Int((raced / length).rounded(.down))
        if raced > before, done > splits.count, done >= 1 {
            splits.append(time)
        }
    }
}

/// A ghost: a run recorded ten times a second, to race against later.
struct CarGhost: Codable, Equatable {
    struct Sample: Codable, Equatable {
        let t: Double
        let x: Double
        let y: Double
        let heading: Double
        /// Metres raced round by then (`CarLapCounter.raced`), to compare runs.
        var raced: Double = 0
    }

    var trackId: String
    var laps: Int
    var name: String
    var samples: [Sample] = []
    /// The run's finish time, seconds; nil while it is still being recorded.
    var time: Double?

    static let interval = 0.1

    /// Keep a sample if a tenth has passed since the last.
    mutating func record(_ car: CarState, raced: Double = 0, at t: Double) {
        if let last = samples.last, t - last.t < CarGhost.interval - 1e-9 { return }
        samples.append(Sample(t: t, x: car.x, y: car.y, heading: car.heading, raced: raced))
    }

    /// How far round the ghost had raced `t` seconds in.
    func raced(at t: Double) -> Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if t <= first.t { return first.raced }
        if t >= last.t { return last.raced }
        let (a, b, f) = bracket(t)
        return a.raced + (b.raced - a.raced) * f
    }

    /// The moment the ghost first got `raced` metres round, or nil if it never did.
    /// "You are 1.2 s behind your best" is the race clock minus this.
    func time(atRaced raced: Double) -> Double? {
        guard let index = samples.firstIndex(where: { $0.raced >= raced }) else { return nil }
        guard index > 0 else { return samples[0].t }
        let a = samples[index - 1], b = samples[index]
        let f = b.raced > a.raced ? (raced - a.raced) / (b.raced - a.raced) : 0
        return a.t + (b.t - a.t) * f
    }

    /// The two samples either side of `t`, and how far between them it is.
    private func bracket(_ t: Double) -> (Sample, Sample, Double) {
        var lo = 0, hi = samples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].t <= t { lo = mid } else { hi = mid }
        }
        let a = samples[lo], b = samples[hi]
        return (a, b, b.t > a.t ? (t - a.t) / (b.t - a.t) : 0)
    }

    /// Add a sample heard from elsewhere (a nearby phone's report). One no
    /// newer than the last is dropped: reports can arrive out of order.
    mutating func append(_ sample: Sample) {
        if let last = samples.last, sample.t <= last.t { return }
        samples.append(sample)
        // A rival's trail only needs its last few seconds.
        if samples.count > 120 { samples.removeFirst(samples.count - 120) }
    }

    /// Where a car heard of now and then (a nearby phone's) is at `t`: past
    /// its last sample, carried on at its last speed and turn for at most
    /// `horizon` seconds, then held there. Before the last sample it is simply
    /// where it was. The speed and turn are read off the last two samples;
    /// with only one, or two far apart, the car is taken to be standing still.
    func predict(at t: Double, horizon: Double = CarCollision.horizon) -> CarBody? {
        guard let last = samples.last else { return nil }
        var velocity = CarVec.zero
        var turnRate = 0.0
        if samples.count >= 2 {
            let before = samples[samples.count - 2]
            let gap = last.t - before.t
            if gap > 1e-3, gap <= 1 {
                velocity = CarVec(x: (last.x - before.x) / gap, y: (last.y - before.y) / gap)
                var turn = last.heading - before.heading
                while turn > .pi { turn -= 2 * .pi }
                while turn < -.pi { turn += 2 * .pi }
                // No car turns faster than this; more is a glitch in the samples.
                turnRate = min(max(turn / gap, -3), 3)
            }
        }
        if t <= last.t, let pose = pose(at: t) {
            return CarBody(at: pose.at, heading: pose.heading, velocity: velocity)
        }
        let ahead = min(max(0, t - last.t), max(0, horizon))
        let swing = turnRate * ahead
        // Along the chord of the arc: the velocity turned half way.
        let run = velocity.rotated(by: swing / 2) * ahead
        return CarBody(at: CarVec(x: last.x, y: last.y) + run, heading: last.heading + swing,
                       velocity: velocity.rotated(by: swing))
    }

    /// Where the ghost was `t` seconds into its run, between two samples.
    func pose(at t: Double) -> (at: CarVec, heading: Double)? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if t <= first.t { return (CarVec(x: first.x, y: first.y), first.heading) }
        if t >= last.t { return (CarVec(x: last.x, y: last.y), last.heading) }
        let (a, b, f) = bracket(t)
        var turn = b.heading - a.heading
        while turn > .pi { turn -= 2 * .pi }
        while turn < -.pi { turn += 2 * .pi }
        return (CarVec(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f), a.heading + turn * f)
    }
}

/// The pilot that drives demo mode and the tests: aim at a point ahead on the
/// middle line, and lift off for the bends it can see coming.
enum CarAutopilot {
    /// `lane` is metres right of the middle line to drive along (left when
    /// negative), so several pilots on one track keep out of each other's way.
    static func input(for car: CarState, on track: CarTrack, lane: Double = 0) -> CarInput {
        let spot = track.spot(of: car.position)
        let speed = car.forwardSpeed
        let ahead = track.point(at: spot.distance + 7 + max(0, speed) * 0.35)
        let room = max(0, track.width / 2 - 2.5)
        let side = min(max(lane, -room), room)
        let aim = ahead.at + CarVec(x: -sin(ahead.direction), y: cos(ahead.direction)) * side
        let want = atan2(aim.y - car.y, aim.x - car.x)
        var error = want - car.heading
        while error > .pi { error -= 2 * .pi }
        while error < -.pi { error += 2 * .pi }
        // How sharply the track turns over the next stretch sets a safe speed.
        let far = track.point(at: spot.distance + 18 + max(0, speed) * 0.9)
        var bend = far.direction - spot.direction
        while bend > .pi { bend -= 2 * .pi }
        while bend < -.pi { bend += 2 * .pi }
        let safe = max(12, 40 - abs(bend) * 30)
        let throttle: Double = speed > safe + 3 ? -0.6 : (speed > safe ? 0 : 1)
        // Boost down a straight it can see the end of, with a tank worth using.
        let boost = throttle == 1 && abs(bend) < 0.12 && (car.boosting || car.boost > 0.3)
        return CarInput(throttle: throttle, steer: min(max(error * 2.4, -1), 1), boost: boost)
    }
}

/// One race's result for a driver, for the table after a race on one phone.
struct CarRaceEntry: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    /// Finish time, seconds; nil for a driver who did not finish.
    let time: Double?
    let bestLap: Double?

    /// Fastest first; anyone who did not finish after everyone who did.
    static func ranked(_ entries: [CarRaceEntry]) -> [CarRaceEntry] {
        entries.enumerated().sorted { a, b in
            switch (a.element.time, b.element.time) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }
}

/// "1:02.37", or "48.20" under a minute.
enum CarRaceFormat {
    static func time(_ seconds: Double) -> String {
        let hundredths = Int((max(0, seconds) * 100).rounded())
        let minutes = hundredths / 6000, rest = hundredths % 6000
        let secs = rest / 100, frac = rest % 100
        let tail = String(format: "%02d.%02d", secs, frac)
        return minutes > 0 ? "\(minutes):\(tail)" : String(format: "%d.%02d", secs, frac)
    }
}
