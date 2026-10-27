import Foundation

// Car Race: a top-down race round a closed track, steered by tilting the
// phone (or by touch), alone against your own best lap's ghost, passed round
// one phone, or phone to phone nearby.
//
// Everything that decides a race lives here, free of SwiftUI and Core Motion:
// the tracks, the car's physics (speed, drag, grip and a drift when the tyres
// let go), the walls, lap counting, the ghost a run leaves behind and the
// pilot that drives demo mode. The screen turns tilt and touch into a
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

/// A closed circuit: its middle line as points close enough together to read
/// as a curve, and its width.
struct CarTrack: Identifiable, Equatable {
    let id: String
    let name: String
    /// One sentence for the picker.
    let line: String
    let width: Double
    /// The middle line, in racing order; the last point joins back to the first.
    let points: [CarVec]
    /// Metres round to each point.
    let distances: [Double]
    let length: Double

    /// A track through `control` points, smoothed into a curve (Catmull-Rom,
    /// `samples` points per span) and closed.
    init(id: String, name: String, line: String, width: Double, control: [(Double, Double)], samples: Int = 14) {
        self.id = id
        self.name = name
        self.line = line
        self.width = width
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

    static let all: [CarTrack] = [.paddock, .riverside, .quarry]

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
}

/// What the driver asks for this frame.
struct CarInput: Equatable {
    /// −1 brakes (and then reverses), 1 is full throttle.
    var throttle: Double = 0
    /// −1 full left, 1 full right.
    var steer: Double = 0
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
    static func input(for car: CarState, on track: CarTrack) -> CarInput {
        let spot = track.spot(of: car.position)
        let speed = car.forwardSpeed
        let aim = track.point(at: spot.distance + 7 + max(0, speed) * 0.35)
        let want = atan2(aim.at.y - car.y, aim.at.x - car.x)
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
        return CarInput(throttle: throttle, steer: min(max(error * 2.4, -1), 1))
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
