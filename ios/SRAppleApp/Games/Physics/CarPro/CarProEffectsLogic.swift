import Foundation

// Car Racer+ effects, camera and controls: the parts of the race screen that
// are arithmetic rather than drawing, kept free of SwiftUI so they can be
// tested. The skid marks and puffs are a picture of what the tyres did and
// never feed back into the race; the camera and the control maths turn a
// finger or a tilt into the engine's −1…1 and 0…1.

/// A stretch of rubber (or a rut in the dirt) one tyre laid.
struct CarProSkidMark: Equatable {
    var from: CarProVec
    var to: CarProVec
    /// Effects-clock seconds it was laid.
    var born: Double
    /// 0…1: how dark it starts.
    var strength: Double
    /// A rut in grass, gravel or dirt rather than rubber on tarmac.
    var loose: Bool
}

/// What a puff is made of.
enum CarProParticleKind: Equatable {
    /// Tyre smoke off a sliding tyre on tarmac.
    case smoke
    /// Dust off dirt and gravel.
    case dust
    /// Clods off the grass.
    case grass
    /// Sparks off a wall or another car.
    case spark
}

/// One puff of smoke, dust, grass or a spark.
struct CarProParticle: Equatable {
    var position: CarProVec
    var velocity: CarProVec
    var born: Double
    var life: Double
    /// Radius at birth, m; smoke and dust swell as they age.
    var size: Double
    var kind: CarProParticleKind

    /// 0 just born … 1 gone.
    func age(at time: Double) -> Double { CarProMath.clamp((time - born) / max(life, 0.01), 0, 1) }
}

/// The skid marks and puffs of a session. Bounded both ways: the marks are
/// a ring that overwrites its oldest, the puffs drop their oldest, so a long
/// race never grows the picture without limit.
struct CarProEffects {
    /// How long a skid mark stays on the road, seconds.
    static let skidLife: Double = 45
    static let skidCapacity = 2400
    static let particleCapacity = 260

    private(set) var skids: [CarProSkidMark] = []
    private var skidHead = 0
    private(set) var particles: [CarProParticle] = []
    /// Each car's four contact patches when they last laid a mark.
    private var lastWheels: [[CarProVec?]] = []
    /// Fractions of a puff owed per tyre, so a puff rate is kept at any frame rate.
    private var emitDebt: [Double] = []
    private var random = CarProRandom(seed: 0xC0FF_EE11)

    init() {}

    /// Everything cleared (a restart).
    mutating func reset() { self = CarProEffects() }

    /// What the cars did over the last `dt` seconds, ending at `time`.
    mutating func update(racers: [CarProRacer], time: Double, dt: Double) {
        if lastWheels.count != racers.count {
            lastWheels = Array(repeating: [nil, nil, nil, nil], count: racers.count)
            emitDebt = Array(repeating: 0, count: racers.count * 4)
        }
        age(time: time, dt: dt)
        guard dt > 0 else { return }
        for c in racers.indices {
            let car = racers[c].vehicle
            let speed = car.speed
            let velocity = car.velocity
            let count = min(4, car.wheels.count)
            for w in 0..<count {
                let wheel = car.wheels[w]
                let loose = wheel.surface.isLoose
                let skid = wheel.locked ? max(wheel.skid, 0.7) : wheel.skid
                mark(car: c, wheel: w, at: wheel.position, loose: loose, skid: skid, speed: speed, time: time)
                emit(car: c, wheel: w, at: wheel.position, loose: loose, surface: wheel.surface, skid: skid,
                     speed: speed, velocity: velocity, time: time, dt: dt)
            }
        }
    }

    /// A shower of sparks where a car met a wall or another car.
    mutating func sparks(at point: CarProVec, impact: Double, time: Double) {
        let count = Int(CarProMath.clamp(impact * 1.5, 3, 14))
        for _ in 0..<count {
            let spread = CarProVec(x: random.signed(), y: random.signed())
            add(CarProParticle(position: point, velocity: spread * (4 + impact), born: time,
                               life: 0.22 + 0.25 * random.next(), size: 0.14, kind: .spark))
        }
    }

    /// Marks still on the road at `time`, with how dark each is now.
    func visibleSkids(at time: Double, near focus: CarProVec, reach: Double) -> [(mark: CarProSkidMark, alpha: Double)] {
        var out: [(mark: CarProSkidMark, alpha: Double)] = []
        for mark in skids {
            let age = time - mark.born
            guard age < Self.skidLife else { continue }
            let d = mark.to - focus
            guard abs(d.x) < reach, abs(d.y) < reach else { continue }
            let fade = 1 - age / Self.skidLife
            out.append((mark, mark.strength * fade))
        }
        return out
    }

    // MARK: - Inside

    private mutating func age(time: Double, dt: Double) {
        guard !particles.isEmpty else { return }
        particles.removeAll { time - $0.born >= $0.life }
        let drag = max(0, 1 - 2.4 * dt)
        for i in particles.indices {
            particles[i].position = particles[i].position + particles[i].velocity * dt
            particles[i].velocity = particles[i].velocity * drag
        }
    }

    private mutating func mark(car c: Int, wheel w: Int, at position: CarProVec, loose: Bool, skid: Double,
                               speed: Double, time: Double) {
        // Rubber on the road while a tyre slides; a rut on anything loose
        // whenever the car is properly moving over it.
        let marking = loose ? speed > 4 : (speed > 2 && skid > 0.18)
        guard marking else {
            lastWheels[c][w] = nil
            return
        }
        guard let last = lastWheels[c][w] else {
            lastWheels[c][w] = position
            return
        }
        let moved = (position - last).length
        if moved > 6 {
            // A jump (a restart, a wall putting the car back): no line across the road.
            lastWheels[c][w] = position
        } else if moved > 0.7 {
            let strength = loose ? CarProMath.clamp(0.3 + skid, 0.3, 0.75) : CarProMath.clamp(skid * 1.1, 0.25, 1)
            let skidMark = CarProSkidMark(from: last, to: position, born: time, strength: strength, loose: loose)
            if skids.count < Self.skidCapacity {
                skids.append(skidMark)
            } else {
                skids[skidHead] = skidMark
                skidHead = (skidHead + 1) % Self.skidCapacity
            }
            lastWheels[c][w] = position
        }
    }

    private mutating func emit(car c: Int, wheel w: Int, at position: CarProVec, loose: Bool, surface: CarProSurface,
                               skid: Double, speed: Double, velocity: CarProVec, time: Double, dt: Double) {
        var rate = 0.0
        var kind = CarProParticleKind.smoke
        if loose && speed > 4 {
            rate = min(26, speed * 0.5 + skid * 26)
            kind = surface == .grass ? .grass : .dust
        } else if !loose && skid > 0.3 {
            rate = 8 + 40 * skid
        }
        let k = c * 4 + w
        guard rate > 0, k < emitDebt.count else {
            if k < emitDebt.count { emitDebt[k] = 0 }
            return
        }
        emitDebt[k] += rate * dt
        while emitDebt[k] >= 1 {
            emitDebt[k] -= 1
            let spread = CarProVec(x: random.signed(), y: random.signed())
            let life: Double, size: Double, v: CarProVec
            switch kind {
            case .smoke:
                v = velocity * 0.1 + spread * 1.5
                life = 1.0 + 0.7 * random.next()
                size = 0.6 + 0.4 * random.next()
            case .dust:
                v = velocity * 0.22 + spread * 2.2
                life = 0.9 + 0.8 * random.next()
                size = 0.8 + 0.6 * random.next()
            case .grass:
                v = velocity * 0.3 + spread * 2.0
                life = 0.45 + 0.3 * random.next()
                size = 0.3 + 0.2 * random.next()
            case .spark:
                v = spread * 8
                life = 0.3
                size = 0.14
            }
            add(CarProParticle(position: position + spread * 0.3, velocity: v, born: time, life: life, size: size,
                               kind: kind))
        }
    }

    private mutating func add(_ particle: CarProParticle) {
        if particles.count >= Self.particleCapacity { particles.removeFirst(particles.count - Self.particleCapacity + 1) }
        particles.append(particle)
    }
}

/// The chase camera: on the player's car, turned with it so the road ahead
/// always points up the screen, pulled back as the speed builds, and given
/// a shake by a hard knock.
struct CarProCamera: Equatable {
    var focus: CarProVec
    /// The way up the screen faces, radians.
    var heading: Double
    /// Metres across the screen's width.
    var span: Double
    /// 0…1: how hard the picture is shaking.
    var shake: Double = 0

    static let nearSpan: Double = 54
    static let farSpan: Double = 118

    init(vehicle: CarProVehicle) {
        focus = vehicle.position
        heading = vehicle.heading
        span = Self.span(for: vehicle.speed)
    }

    /// How much road fits across the screen at `speed` m/s.
    static func span(for speed: Double) -> Double {
        CarProMath.clamp(nearSpan + abs(speed) * 0.95, nearSpan, farSpan)
    }

    /// Follows `vehicle` over `dt` seconds: the turn eased so a twitch is not
    /// a lurch, looking a little along a slide, the zoom eased slower still.
    mutating func follow(_ vehicle: CarProVehicle, dt: Double) {
        focus = vehicle.position
        let slide = CarProMath.clamp(vehicle.slipAngle, -0.7, 0.7)
        let target = vehicle.heading + slide * 0.5
        let turn = CarProMath.wrap(target - heading)
        heading = CarProMath.wrap(heading + turn * (1 - exp(-dt * 6)))
        span += (Self.span(for: vehicle.speed) - span) * (1 - exp(-dt * 1.3))
        shake *= exp(-dt * 7)
    }

    /// A knock of `impact` m/s shakes the picture.
    mutating func bump(_ impact: Double) {
        shake = min(1, max(shake, impact * 0.07))
    }

    /// Where `point` lands on a screen `width` × `height`, the camera's
    /// focus sitting `anchor` of the way down: the same sum the drawing
    /// does with its transforms, for labels drawn upright over the world.
    func screen(_ point: CarProVec, width: Double, height: Double, anchor: Double) -> (x: Double, y: Double) {
        let scale = width / span
        let turned = (point - focus).rotated(by: -heading - .pi / 2)
        return (width / 2 + turned.x * scale, height * anchor + turned.y * scale)
    }
}

/// Fingers and tilt into the engine's inputs.
enum CarProControlMath {
    /// A pedal's amount from where the finger is on it, 0 at the top of the
    /// pedal and `height` at its foot: light at the foot, full in its top third.
    static func pedal(touchY: Double, height: Double) -> Double {
        guard height > 0 else { return 1 }
        let up = 1 - CarProMath.clamp(touchY / height, 0, 1)
        return CarProMath.clamp(0.15 + up * 1.25, 0.15, 1)
    }

    /// Steering from the phone's tilt in g: a small dead zone, then a curve
    /// that is fine near the middle and reaches full lock at `fullLean`.
    static func tilt(_ lean: Double, fullLean: Double = 0.24) -> Double {
        let dead = 0.015
        let size = abs(lean)
        guard size > dead, fullLean > dead else { return 0 }
        let x = CarProMath.clamp((size - dead) / (fullLean - dead), 0, 1)
        let curved = 0.4 * x + 0.6 * x * x
        return lean < 0 ? -curved : curved
    }

    /// How far the on-screen wheel turns for full lock, radians.
    static let wheelLock: Double = .pi * 0.7

    /// Steering from the on-screen wheel turned `turn` radians (clockwise positive).
    static func wheel(turn: Double) -> Double { CarProMath.clamp(turn / wheelLock, -1, 1) }

    /// The change between two touch angles round the wheel, folded so a
    /// drag across the bottom of the wheel does not jump a whole turn.
    static func angleChange(from a: Double, to b: Double) -> Double { CarProMath.wrap(b - a) }

    /// Steering from the slider: the finger `offset` points from the middle
    /// of a strip `width` wide, full lock a little short of its ends.
    static func slider(offset: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return CarProMath.clamp(offset / (width * 0.42), -1, 1)
    }

    /// `value` eased towards `target` at `rate` per second over `dt`.
    static func ease(_ value: Double, to target: Double, rate: Double, dt: Double) -> Double {
        value + (target - value) * (1 - exp(-rate * max(0, dt)))
    }
}
