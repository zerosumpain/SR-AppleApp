import Foundation

// Car Racer+ vehicle physics: a four-wheel model in the car's own frame.
//
// Each 1/240 s substep: the loads on the four tyres (static weight,
// downforce, weight moving forward under braking and across in a corner,
// kerb ripples), the engine (torque curve, turbo, rev limiter) through the
// clutch, gearbox and differential to the driven wheels, the brakes (bias,
// fade, ABS), each tyre's slip ratio and slip angle into the combined
// magic-formula force, each wheel's spin (stepped implicitly so a light
// wheel against a stiff tyre stays stable), aero drag and rolling
// resistance, the body's motion, and the walls. Tyres warm with sliding and
// wear; brakes heat and fade.

/// One wheel: how fast it spins, the state of its tyre, and what it did this
/// substep (for the drawing: skids, smoke, dust, the four-corner HUD).
struct CarProWheel: Equatable {
    /// Spin, rad/s (positive rolls the car forward).
    var omega: Double = 0
    /// Tread temperature, °C.
    var temperature: Double
    /// 0 new … 1 finished.
    var wear: Double = 0
    /// Vertical load, N.
    var load: Double = 0
    var slipRatio: Double = 0
    var slipAngle: Double = 0
    /// Combined normalised slip; past 1 the tyre is sliding.
    var combinedSlip: Double = 0
    var surface: CarProSurface = .tarmac
    /// Where the contact patch is, world metres.
    var position: CarProVec = .zero
    /// ABS let this brake off this substep.
    var absActive = false
    /// Sliding power, W, for heat and wear.
    var slipPower: Double = 0

    init(temperature: Double) { self.temperature = temperature }

    /// 0…1: how hard the tyre is sliding, for skid marks and smoke.
    var skid: Double { CarProMath.clamp((combinedSlip - 1.0) / 1.2, 0, 1) }
    /// Locked under braking.
    var locked: Bool { slipRatio < -0.5 }
}

/// One car's state: where it is, how it moves, its engine and gearbox,
/// and its four wheels (front left, front right, rear left, rear right).
struct CarProVehicle: Equatable {
    var position: CarProVec
    /// Radians; 0 points right, positive turns clockwise on screen.
    var heading: Double
    /// Speed along the car, m/s (negative reversing).
    var forwardSpeed: Double = 0
    /// Speed to the car's right, m/s.
    var lateralSpeed: Double = 0
    /// rad/s, positive turning right.
    var yawRate: Double = 0
    var wheels: [CarProWheel]
    /// The steering input after smoothing, −1…1.
    var steer: Double = 0
    /// The front wheels' angle, radians.
    var steerAngle: Double = 0
    /// −1 reverse, 0 neutral (mid-shift), 1… forward.
    var gear: Int = 1
    var pendingGear: Int = 1
    var shiftTimer: Double = 0
    var rpm: Double
    /// Turbo boost, 0…1.
    var boost: Double = 0
    /// The rev limiter is cutting the fuel.
    var revCut = false
    /// The clutch is slipping (pulling away).
    var clutchSlipping = false
    /// Front and rear brake temperatures, °C.
    var brakeTemperature: [Double] = [CarProPhysics.ambient, CarProPhysics.ambient]
    /// Smoothed accelerations along and across the car, m/s², which move the weight.
    var accelForward: Double = 0
    var accelRight: Double = 0
    /// Traction control is trimming the throttle; ABS is working.
    var tractionActive = false
    var absActive = false
    var tractionScale: Double = 1
    /// The pedals as the car used them (after reverse swapping and TC).
    var throttle: Double = 0
    var brake: Double = 0
    var reverseTimer: Double = 0
    /// Metres driven.
    var odometer: Double = 0
    /// The nearest centre-line sample, and where the car is against it.
    var trackIndex: Int = 0
    var trackDistance: Double = 0
    var trackOffset: Double = 0
    /// 0…1 shake from kerbs and rough ground, for a haptic.
    var rumble: Double = 0

    /// A car standing (or rolling at `speed`) at `position`, pointing `heading`.
    init(params: CarProVehicleParams, position: CarProVec, heading: Double, speed: Double = 0) {
        self.position = position
        self.heading = heading
        forwardSpeed = speed
        let start = params.compound.startTemperature
        wheels = Array(repeating: CarProWheel(temperature: start), count: 4)
        for i in 0..<4 { wheels[i].omega = speed / params.wheelRadius }
        var g = 1
        if speed > 1 {
            while g < params.topGear, params.rpm(speed: speed, gear: g) > params.redline * 0.82 { g += 1 }
        }
        gear = g
        pendingGear = g
        rpm = max(params.idleRpm, params.rpm(speed: speed, gear: g))
        brakeTemperature = [CarProPhysics.ambient + 80, CarProPhysics.ambient + 80]
    }

    var forward: CarProVec { .heading(heading) }
    var right: CarProVec { forward.right }
    /// World velocity, m/s.
    var velocity: CarProVec { forward * forwardSpeed + right * lateralSpeed }
    var speed: Double { (forwardSpeed * forwardSpeed + lateralSpeed * lateralSpeed).squareRoot() }
    /// The gear to show: the one being shifted into while the clutch is out.
    var displayGear: Int { shiftTimer > 0 ? pendingGear : gear }
    /// "R", "N", "1"…
    var gearLabel: String {
        let g = displayGear
        return g < 0 ? "R" : (g == 0 ? "N" : "\(g)")
    }
    /// Body slip: the angle between where the car points and where it goes.
    var slipAngle: Double {
        guard speed > 2 else { return 0 }
        return atan2(lateralSpeed, abs(forwardSpeed))
    }
    /// 0…1 glow for the front and rear discs.
    var brakeGlow: (front: Double, rear: Double) {
        (CarProMath.clamp((brakeTemperature[0] - 380) / 400, 0, 1),
         CarProMath.clamp((brakeTemperature[1] - 380) / 400, 0, 1))
    }
    /// Any tyre on the racing surface.
    var onTrack: Bool { wheels.contains { $0.surface.isTrack } }
    /// Every tyre off the racing surface: off the track.
    var offTrack: Bool { !onTrack }
}

/// What one substep did that a screen or a session cares about.
struct CarProStepResult: Equatable {
    /// Speed into a wall, m/s; 0 for no hit.
    var wallImpact: Double = 0
    var shifted = false
}

/// A fixed-step accumulator: a frame of any length becomes whole 1/240 s substeps.
struct CarProStepClock: Equatable {
    private(set) var pending: Double = 0

    /// How many substeps `dt` seconds of frame make, carrying the remainder.
    /// A frame longer than a tenth of a second (a hitch) is cut short.
    mutating func substeps(for dt: Double) -> Int {
        guard dt > 0 else { return 0 }
        pending += min(dt, 0.1)
        let n = Int((pending + 1e-9) / CarProPhysics.dt)
        pending = max(0, pending - Double(n) * CarProPhysics.dt)
        return n
    }
}

enum CarProPhysics {
    /// The fixed substep.
    static let dt: Double = 1.0 / 240
    static let ambient: Double = 22
    /// Steering input smoothing, full lock per second.
    static let steerRate: Double = 7
    /// How fast the front wheels can turn, rad/s.
    static let steerSpeed: Double = 5
    /// Speed kept off a wall: the bounce and the scrub along it.
    static let wallBounce: Double = 0.25
    static let wallScrub: Double = 0.86

    /// Advances `car` by `dt` seconds (any length) in fixed substeps, with
    /// the same input throughout: for tests and simple screens. Returns the
    /// hardest wall hit.
    @discardableResult
    static func advance(_ car: inout CarProVehicle, params: CarProVehicleParams, input: CarProInput,
                        assists: CarProAssists, track: CarProTrack?, clock: inout CarProStepClock,
                        dt frame: Double) -> CarProStepResult {
        var total = CarProStepResult()
        let n = clock.substeps(for: frame)
        var current = input
        for _ in 0..<n {
            let r = step(&car, params: params, input: current, assists: assists, track: track)
            total.wallImpact = max(total.wallImpact, r.wallImpact)
            total.shifted = total.shifted || r.shifted
            current = current.held
        }
        return total
    }

    /// One fixed substep of `dt`. `held` keeps the car on the brakes with
    /// the clutch out (the grid before the lights go out): the throttle
    /// only revs the engine.
    @discardableResult
    static func step(_ car: inout CarProVehicle, params p: CarProVehicleParams, input: CarProInput,
                     assists: CarProAssists, track: CarProTrack?, held: Bool = false) -> CarProStepResult {
        let h = dt
        var result = CarProStepResult()
        let g = CarProVehicleParams.gravity
        let m = p.mass

        // Where the car is on the track: the hint follows it round.
        var bankForce = CarProVec.zero
        var spotNormal = CarProVec(x: 0, y: 1)
        var spotTangent = CarProVec(x: 1, y: 0)
        if let track {
            let spot = track.locate(car.position, hint: car.trackIndex)
            car.trackIndex = spot.index
            car.trackDistance = spot.distance
            car.trackOffset = spot.offset
            spotNormal = spot.normal
            spotTangent = spot.tangent
            let bank = track.samples[spot.index].bank
            if bank != 0 { bankForce = spot.normal * (m * g * sin(bank)) }
        }

        // Pedals and the gearbox.
        var throttle = CarProMath.clamp(input.throttle, 0, 1)
        var brake = CarProMath.clamp(input.brake, 0, 1)
        if !held { gearbox(&car, params: p, input: input, assists: assists, throttle: throttle, brake: brake, result: &result) }
        if car.gear < 0 || (car.shiftTimer > 0 && car.pendingGear < 0) { swap(&throttle, &brake) }
        if held { brake = 1 }

        let u = car.forwardSpeed, v = car.lateralSpeed, r = car.yawRate
        let a = p.toFront, b = p.toRear
        let halfTrack = p.trackWidth / 2

        // Steering. With the assist the input is a share of the front tyres'
        // grip, measured from the way the front axle is actually travelling —
        // so the wheels follow a slide by themselves (counter-steer).
        car.steer = CarProMath.approach(car.steer, CarProMath.clamp(input.steer, -1, 1), h * steerRate)
        let steerTarget = steeringAngle(for: car.steer, car: car, params: p, assisted: assists.steering)
        car.steerAngle = CarProMath.approach(car.steerAngle, steerTarget, h * steerSpeed)

        // Loads: weight, downforce, and weight moving with the acceleration.
        let L = p.wheelbase
        let down = p.downforce(u)
        let longShift = m * car.accelForward * p.comHeight / L
        let frontAxle = m * g * b / L + down * p.aeroFront - longShift
        let rearAxle = m * g * a / L + down * (1 - p.aeroFront) + longShift
        let latShift = m * car.accelRight * p.comHeight / p.trackWidth
        var loads: [Double] = [
            frontAxle / 2 + latShift * p.rollFront, frontAxle / 2 - latShift * p.rollFront,
            rearAxle / 2 + latShift * (1 - p.rollFront), rearAxle / 2 - latShift * (1 - p.rollFront),
        ]

        // The ground under each tyre, and kerb ripples on the load.
        let fwd = car.forward, rgt = car.right
        let lx: [Double] = [a, a, -b, -b]
        let ly: [Double] = [-halfTrack, halfTrack, -halfTrack, halfTrack]
        var rumble = 0.0
        for i in 0..<4 {
            let world = car.position + fwd * lx[i] + rgt * ly[i]
            car.wheels[i].position = world
            var surface = CarProSurface.tarmac
            if let track {
                let rel = world - car.position
                surface = track.surface(near: car.trackIndex, along: rel.dot(spotTangent),
                                        offset: car.trackOffset + rel.dot(spotNormal))
            }
            car.wheels[i].surface = surface
            let bump = surface.bump * p.bumpScale
            if bump > 0 {
                let wave = sin(car.odometer * 1.9 + Double(i) * 1.3)
                loads[i] *= 1 + bump * wave
                rumble = max(rumble, bump * abs(u) / 30)
            }
            loads[i] = max(0, loads[i])
        }
        car.rumble = min(1, rumble * 2)

        // The engine, clutch and turbo.
        let ratio = car.shiftTimer > 0 ? 0 : p.ratio(car.gear)
        let driven: [Int]
        switch p.drive {
        case .fwd: driven = [0, 1]
        case .rwd: driven = [2, 3]
        case .awd: driven = [0, 1, 2, 3]
        }
        var omegaSum = 0.0
        for i in driven { omegaSum += car.wheels[i].omega }
        let wheelRpm = omegaSum / Double(driven.count) * ratio * 60 / (2 * .pi)

        // Traction control: trim the throttle while a driven tyre spins up.
        var spinning = false
        let peakRatio = p.compound.peakSlipRatio
        for i in driven {
            let w = car.wheels[i]
            if w.slipRatio > peakRatio * 1.3 || (w.slipRatio > peakRatio * 0.4 && w.combinedSlip > 1.1) { spinning = true }
        }
        if assists.traction && spinning {
            car.tractionScale = max(0.1, car.tractionScale - h * 20)
        } else {
            car.tractionScale = min(1, car.tractionScale + h * 4)
        }
        car.tractionActive = assists.traction && car.tractionScale < 0.97 && throttle > 0.05
        var fuel = throttle * (assists.traction ? car.tractionScale : 1)

        if p.turboGain > 0 {
            let spool = CarProMath.clamp((car.rpm - 0.45 * p.torqueRpm) / (0.55 * p.torqueRpm), 0, 1)
            let target = throttle * spool
            let rate = target > car.boost ? 1 / p.turboLag : 3 / p.turboLag
            car.boost += (target - car.boost) * min(1, h * rate)
        }

        var clutchTorque = 0.0
        var engaged = false
        if ratio == 0 || held {
            // Clutch out: the engine revs freely (or falls to meet the next gear).
            let free: Double
            if car.shiftTimer > 0, car.pendingGear != 0 {
                free = max(p.idleRpm, p.rpm(speed: u, gear: car.pendingGear))
            } else {
                free = p.idleRpm + throttle * (p.redline - p.idleRpm) * 0.92
            }
            car.rpm = min(p.limiter, CarProMath.approach(car.rpm, free, h * 9000))
            car.clutchSlipping = false
            car.revCut = false
        } else {
            let slipTarget = max(p.idleRpm * 1.1, p.idleRpm + (p.launchRpm - p.idleRpm) * throttle)
            if wheelRpm < slipTarget {
                // Pulling away: the clutch slips with the engine held up.
                car.rpm = CarProMath.approach(car.rpm, slipTarget, h * 9000)
                car.clutchSlipping = true
                car.revCut = false
                clutchTorque = fuel > 0.02 ? max(0, p.engineTorque(rpm: car.rpm, throttle: fuel, boost: car.boost)) : 0
            } else {
                engaged = true
                car.clutchSlipping = false
                car.rpm = wheelRpm
                if car.rpm >= p.limiter { car.revCut = true } else if car.rpm < p.limiter - 300 { car.revCut = false }
                if car.revCut { fuel = 0 }
                clutchTorque = p.engineTorque(rpm: car.rpm, throttle: fuel, boost: car.boost)
            }
        }
        car.throttle = fuel
        car.brake = brake

        // Torque to each wheel: through the gearbox, then the centre split
        // (all-wheel drive) and each axle's differential (half each side).
        let R = p.wheelRadius
        var axleTorque = clutchTorque * ratio * p.efficiency
        // Traction control also caps the torque at what the driven tyres can
        // put down with the grip a corner leaves them, before they spin.
        if assists.traction && axleTorque * ratio > 0 {
            var grip = 0.0
            for i in driven { grip += loads[i] * p.compound.mu * car.wheels[i].surface.grip * (i < 2 ? 1 : p.rearGrip) }
            let cornering = CarProMath.clamp(abs(car.accelRight) / (p.compound.mu * g), 0, 0.95)
            let most = grip * (1 - cornering * cornering).squareRoot() * 1.0 * R
            if abs(axleTorque) > most {
                axleTorque = most * (axleTorque > 0 ? 1 : -1)
                car.tractionActive = true
            }
        }
        var driveTorque: [Double] = [0, 0, 0, 0]
        switch p.drive {
        case .fwd:
            driveTorque[0] = axleTorque / 2; driveTorque[1] = axleTorque / 2
        case .rwd:
            driveTorque[2] = axleTorque / 2; driveTorque[3] = axleTorque / 2
        case .awd:
            let front = axleTorque * p.frontDriveShare, rear = axleTorque - front
            driveTorque = [front / 2, front / 2, rear / 2, rear / 2]
        }
        let reflected = engaged ? p.engineInertia * ratio * ratio / Double(driven.count) : 0

        // Brakes: bias, fade when hot, ABS letting a locking wheel go.
        let fadeFront = 1 - 0.35 * CarProMath.clamp((car.brakeTemperature[0] - p.fadeStart) / 300, 0, 1)
        let fadeRear = 1 - 0.35 * CarProMath.clamp((car.brakeTemperature[1] - p.fadeStart) / 300, 0, 1)
        var brakeTorque: [Double] = [
            brake * p.brakeTorque * p.brakeBias / 2 * fadeFront, brake * p.brakeTorque * p.brakeBias / 2 * fadeFront,
            brake * p.brakeTorque * (1 - p.brakeBias) / 2 * fadeRear, brake * p.brakeTorque * (1 - p.brakeBias) / 2 * fadeRear,
        ]
        // ABS: each brake is held to what its tyre can take with the grip
        // its cornering leaves (so it brakes at the peak and still steers),
        // and let off if the wheel locks regardless.
        car.absActive = false
        let peakAngle = tan(p.compound.peakSlipAngle)
        for i in 0..<4 {
            car.wheels[i].absActive = false
            guard assists.abs, brake > 0.02, abs(u) > 2 else { continue }
            let w = car.wheels[i]
            let mu = p.compound.mu * w.surface.grip * p.gripBonus * (i < 2 ? 1 : p.rearGrip)
            let side = CarProMath.clamp(tan(CarProMath.clamp(w.slipAngle, -1.4, 1.4)) / peakAngle, -1, 1)
            // Just under the peak: held exactly at it, the force falls away past
            // it and the wheel locks anyway.
            let most = mu * loads[i] * 0.95 * (max(0.12, 1 - side * side)).squareRoot() * p.wheelRadius
            if brakeTorque[i] > most {
                brakeTorque[i] = most
                car.wheels[i].absActive = true
                car.absActive = true
            }
            if w.slipRatio < -p.compound.peakSlipRatio * 1.6 {
                brakeTorque[i] *= 0.3
                car.wheels[i].absActive = true
                car.absActive = true
            }
        }

        // The tyres.
        var fxTotal = 0.0, fyTotal = 0.0, mz = 0.0
        var newOmega: [Double] = [0, 0, 0, 0]
        var inertia: [Double] = [0, 0, 0, 0]
        var brakePower: [Double] = [0, 0]
        let cosd = cos(car.steerAngle), sind = sin(car.steerAngle)
        for i in 0..<4 {
            var wheel = car.wheels[i]
            let load = loads[i]
            let vx = u - r * ly[i]
            let vy = v + r * lx[i]
            let front = i < 2
            let c = front ? cosd : 1, s = front ? sind : 0
            let vxw = vx * c + vy * s
            let vyw = -vx * s + vy * c
            let denom = max(abs(vxw), CarProTyre.slipFloorSpeed)
            let slipRatio = (wheel.omega * R - vxw) / denom
            let slipAngle = atan(vyw / denom)
            let mu = p.compound.mu * wheel.surface.grip * p.gripBonus * (front ? 1 : p.rearGrip)
                * CarProTyre.temperatureGrip(wheel.temperature, compound: p.compound)
                * CarProTyre.wearGrip(wheel.wear) * CarProTyre.loadGrip(load, nominal: p.nominalLoad)
            let force = CarProTyre.force(slipRatio: slipRatio, slipAngle: slipAngle, load: load, mu: mu,
                                         compound: p.compound, curve: p.curve)

            // The wheel's spin, implicit in the tyre's grip: a stiff tyre on a
            // light wheel would ring at 240 Hz stepped explicitly.
            let isDriven = driven.contains(i)
            let inert = p.wheelInertia + (isDriven ? reflected : 0)
            let k = force.slipStiffness * R / denom
            let soften = 1 + h * R * k / inert
            var omega = wheel.omega + h * (driveTorque[i] - force.longitudinal * R) / inert / soften
            let brakeStep = h * brakeTorque[i] / inert / soften
            if abs(omega) <= brakeStep { omega = 0 } else { omega -= omega > 0 ? brakeStep : -brakeStep }
            newOmega[i] = omega
            inertia[i] = inert
            brakePower[front ? 0 : 1] += brakeTorque[i] * abs(omega)

            // Rolling resistance, smoothed through zero so a parked car is
            // still. Loose ground ploughs harder the faster it is hit, so a
            // car beached in gravel can still crawl out.
            let plough = wheel.surface.isLoose ? min(1, 0.25 + abs(vxw) / 8) : 1
            let rolling = -wheel.surface.rolling * plough * load * tanh(vxw / 0.3)
            let fxw = force.longitudinal + rolling
            let fyw = force.lateral
            let fx = fxw * c - fyw * s
            let fy = fxw * s + fyw * c
            fxTotal += fx
            fyTotal += fy
            mz += lx[i] * fy - ly[i] * fx

            // Heat and wear from the sliding.
            let slipPower = abs(force.longitudinal * (wheel.omega * R - vxw)) + abs(force.lateral * vyw)
            wheel.temperature = CarProTyre.heat(wheel.temperature, slipPower: slipPower, load: load,
                                                speed: abs(u), ambient: ambient, dt: h)
            wheel.wear = CarProTyre.wear(wheel.wear, slipPower: slipPower, compound: p.compound, dt: h)
            wheel.slipPower = slipPower
            wheel.load = load
            wheel.slipRatio = slipRatio
            wheel.slipAngle = slipAngle
            wheel.combinedSlip = force.combinedSlip
            car.wheels[i] = wheel
        }

        // Limited-slip: each driven axle's wheels pulled towards the same
        // speed, by at most the locking torque.
        if p.diffLock > 0 {
            let pairs: [(Int, Int)] = p.drive == .fwd ? [(0, 1)] : (p.drive == .rwd ? [(2, 3)] : [(0, 1), (2, 3)])
            for (l, rr) in pairs {
                let gap = (newOmega[rr] - newOmega[l]) / 2
                let lockTorque = p.diffLock * (abs(axleTorque) * 0.6 + 120)
                let most = h * lockTorque / max(inertia[l], inertia[rr])
                let shift = min(abs(gap) * min(1, h * 400 * p.diffLock), most) * (gap > 0 ? 1 : -1)
                newOmega[l] += shift
                newOmega[rr] -= shift
            }
        }
        for i in 0..<4 { car.wheels[i].omega = newOmega[i] }

        // Brake heat.
        for axle in 0..<2 {
            let t = car.brakeTemperature[axle]
            let cooling = (t - ambient) * (0.012 + 0.0022 * abs(u))
            car.brakeTemperature[axle] = t + (brakePower[axle] / 7000 - cooling) * h
        }

        // Aero drag and the banking, then the body.
        fxTotal -= p.drag(u) * (u >= 0 ? 1 : -1)
        if bankForce.x != 0 || bankForce.y != 0 {
            fxTotal += bankForce.dot(fwd)
            fyTotal += bankForce.dot(rgt)
        }
        let ax = fxTotal / m, ay = fyTotal / m
        var nu = u + (ax + v * r) * h
        var nv = v + (ay - u * r) * h
        var nr = r + mz / p.yawInertia * h
        // Parked: a car on the brakes that has all but stopped stops.
        if abs(nu) < 0.12, abs(nv) < 0.12, abs(nr) < 0.05, fuel < 0.02, brake > 0.1 {
            nu = 0; nv = 0; nr = 0
            for i in 0..<4 { car.wheels[i].omega = 0 }
        }
        let settle = min(1, h / 0.07)
        car.accelForward += (ax - car.accelForward) * settle
        car.accelRight += (ay - car.accelRight) * settle
        car.forwardSpeed = nu
        car.lateralSpeed = nv
        car.yawRate = nr
        let velocity = fwd * nu + rgt * nv
        car.position = car.position + velocity * h
        car.heading = CarProMath.wrap(car.heading + nr * h)
        car.odometer += abs(nu) * h

        if let track { result.wallImpact = wall(&car, params: p, track: track) }
        return result
    }

    /// Lock at speed for an un-assisted wheel: a phone's tilt is coarse, so
    /// the rack slows as the car speeds up.
    static func lock(speed: Double, params p: CarProVehicleParams) -> Double {
        p.maxLock / (1 + abs(speed) / 14)
    }

    /// The front wheels' angle for steering input `steer` (−1…1).
    ///
    /// Assisted, the input is a share of the front tyres' grip measured from
    /// the way the front axle is actually travelling, so the wheels follow a
    /// slide by themselves (counter-steer) and never ask the tyres for more
    /// than they have. Un-assisted it is a share of the speed-sensitive
    /// lock, with extra reach towards a slide so a driver can still catch one.
    static func steeringAngle(for steer: Double, car: CarProVehicle, params p: CarProVehicleParams,
                              assisted: Bool) -> Double {
        let u = car.forwardSpeed
        let lock = self.lock(speed: u, params: p)
        let travel = u > 3 ? atan((car.lateralSpeed + p.toFront * car.yawRate) / u) : 0
        var angle: Double
        if assisted && u > 3 {
            angle = travel + (steer - catchSlide(car: car, params: p)) * assistReach(speed: u, params: p)
        } else {
            let into = steer * travel > 0 ? abs(travel) : 0
            angle = steer * (lock + into)
        }
        return CarProMath.clamp(angle, -p.maxLock, p.maxLock)
    }

    /// With the steering assist, how much input is taken back while the rear
    /// slides wide of the turn (oversteer): past the rear tyres' peak slip
    /// the front lets go of the turn too, and then steers into the slide.
    static func catchSlide(car: CarProVehicle, params p: CarProVehicleParams) -> Double {
        let u = car.forwardSpeed
        guard u > 3 else { return 0 }
        let rear = atan((car.lateralSpeed - p.toRear * car.yawRate) / u)
        // Oversteer: the rear moving out of the turn the car is yawing into.
        guard rear * car.yawRate < 0 else { return 0 }
        let peak = p.compound.peakSlipAngle
        let over = CarProMath.clamp((abs(rear) - peak * 0.9) / peak, 0, 1.6)
        return over * (car.yawRate > 0 ? 1 : -1)
    }

    /// With the steering assist, how far full input turns the wheels beyond
    /// the front axle's travel: the tyres' peak slip, and more at a crawl.
    static func assistReach(speed: Double, params p: CarProVehicleParams) -> Double {
        let grip = p.compound.peakSlipAngle * 1.05
        let lowSpeed = CarProMath.clamp(1 - (speed - 3) / 12, 0, 1)
        return max(grip, lock(speed: speed, params: p) * lowSpeed)
    }

    /// The steering input that asks for front-wheel angle `angle`: the
    /// inverse of `steeringAngle` for a car that is not sliding (the assist
    /// still catches a slide on top), for the AI.
    static func steerInput(forAngle angle: Double, car: CarProVehicle, params p: CarProVehicleParams,
                           assisted: Bool) -> Double {
        let u = car.forwardSpeed
        let travel = u > 3 ? atan((car.lateralSpeed + p.toFront * car.yawRate) / u) : 0
        if assisted && u > 3 {
            return CarProMath.clamp((angle - travel) / assistReach(speed: u, params: p), -1, 1)
        }
        let lock = self.lock(speed: u, params: p)
        let into = angle * travel > 0 ? abs(travel) : 0
        return CarProMath.clamp(angle / (lock + into), -1, 1)
    }

    /// The walls beyond the run-off: the car is put back inside and bounced.
    /// Returns the speed into the wall, 0 for none.
    static func wall(_ car: inout CarProVehicle, params p: CarProVehicleParams, track: CarProTrack) -> Double {
        let spot = track.locate(car.position, hint: car.trackIndex)
        car.trackIndex = spot.index
        car.trackDistance = spot.distance
        car.trackOffset = spot.offset
        let sample = track.samples[spot.index]
        let side: Double = spot.offset >= 0 ? 1 : -1
        let wallAt = sample.halfWidth + (side > 0 ? sample.runoffRight : sample.runoffLeft)
        let n = spot.normal * side
        // How far the body reaches towards the wall, from its centre.
        let reach = abs(car.forward.dot(n)) * p.length / 2 + abs(car.right.dot(n)) * p.width / 2
        let over = abs(spot.offset) + reach - wallAt
        guard over > 0 else { return 0 }
        car.position = car.position - n * over
        let velocity = car.velocity
        let into = velocity.dot(n)
        guard into > 0 else { return 0 }
        let along = velocity - n * into
        let next = along * wallScrub - n * (into * wallBounce)
        car.forwardSpeed = next.dot(car.forward)
        car.lateralSpeed = next.dot(car.right)
        car.yawRate *= 0.55
        return into
    }

    /// Shifting: the driver's paddles or the automatic box, and reverse.
    private static func gearbox(_ car: inout CarProVehicle, params p: CarProVehicleParams, input: CarProInput,
                                assists: CarProAssists, throttle: Double, brake: Double,
                                result: inout CarProStepResult) {
        if car.shiftTimer > 0 {
            car.shiftTimer -= dt
            if car.shiftTimer <= 0 {
                car.shiftTimer = 0
                car.gear = car.pendingGear
                result.shifted = true
            }
            return
        }
        let u = car.forwardSpeed
        func begin(_ next: Int) {
            guard next != car.gear else { return }
            let reversing = next < 0 || car.gear < 0
            car.pendingGear = next
            car.shiftTimer = reversing ? 0.35 : p.shiftTime
            car.gear = 0
        }

        // Reverse: hold the brake at a standstill; the throttle takes it out again.
        if car.gear >= 1 && u < 0.8 && brake > 0.4 && throttle < 0.05 {
            car.reverseTimer += dt
            if car.reverseTimer > 0.6 { car.reverseTimer = 0; begin(-1); return }
        } else if car.gear < 0 && throttle > 0.3 && u > -0.8 {
            car.reverseTimer = 0
            begin(1)
            return
        } else {
            car.reverseTimer = 0
        }

        if input.shiftUp && car.gear < p.topGear {
            begin(car.gear < 0 ? 1 : car.gear + 1)
            return
        }
        if input.shiftDown {
            if car.gear > 1 {
                // The box refuses a downshift that would over-rev the engine.
                if p.rpm(speed: u, gear: car.gear - 1) < p.limiter + 200 { begin(car.gear - 1) }
            } else if car.gear == 1 && abs(u) < 1 {
                begin(-1)
            }
            return
        }
        guard assists.autoGears, car.gear >= 1 else { return }
        if car.gear < p.topGear && car.rpm > p.redline - 60 && throttle > 0.05 && !car.clutchSlipping {
            begin(car.gear + 1)
        } else if car.gear > 1 {
            let lower = p.rpm(speed: u, gear: car.gear - 1)
            let braking = brake > 0.2 && lower < p.redline - 700
            let lugging = car.rpm < p.torqueRpm * 0.8 && lower < p.redline - 1100 && throttle > 0.5
            let idling = car.rpm < p.idleRpm * 1.4
            if braking || lugging || idling { begin(car.gear - 1) }
        }
    }
}
