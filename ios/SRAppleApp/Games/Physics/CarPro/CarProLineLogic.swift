import Foundation

// Car Racer+ speed profiles: how fast a particular car can take every metre
// of a circuit's racing line. The friction limit sets a top speed for each
// bend (with downforce growing as v² and banking helping); a pass forwards
// adds how quickly the car can accelerate out of each bend, and a pass
// backwards how hard it can brake into it, both inside a friction ellipse.
// The AI drives to it, the braking boards come from it, and qualifying
// times for the AI are its lap time.

/// What a speed profile needs to know about a car: how hard it can corner,
/// brake and accelerate at each speed, worked out from its axle loads (with
/// the weight that moves across and along the car, downforce, and tyres
/// that grip a little less per newton the harder they are pressed), so a
/// front-heavy hatchback's understeer and a light prototype's downforce are
/// both in the plan.
struct CarProPerformance: Equatable {
    let mass: Double
    /// Drag per kilogram per (m/s)².
    let drag: Double
    let rolling: Double
    let topSpeed: Double
    /// Each table is at whole multiples of `tableStep` m/s.
    let lateralTable: [Double]
    let brakeTable: [Double]
    let accelTable: [Double]
    static let tableStep = 4.0

    /// `grip` is the share of the tyres' limit the line is planned for.
    init(params p: CarProVehicleParams, grip: Double = 0.92) {
        mass = p.mass
        drag = 0.5 * CarProVehicleParams.airDensity * p.dragArea / p.mass
        rolling = CarProSurface.tarmac.rolling * CarProVehicleParams.gravity
        topSpeed = p.topSpeed
        var lateral: [Double] = [], brake: [Double] = [], accel: [Double] = []
        var v = 0.0
        while v <= 100 {
            lateral.append(Self.lateralCapacity(p, speed: v) * grip)
            brake.append(Self.brakeCapacity(p, speed: v) * grip)
            let traction = Self.tractionCapacity(p, speed: v) * grip
            accel.append(min(Self.driveAccel(p, speed: max(1, v)), traction))
            v += Self.tableStep
        }
        lateralTable = lateral
        brakeTable = brake
        accelTable = accel
    }

    private func read(_ table: [Double], _ v: Double) -> Double {
        let x = CarProMath.clamp(v / Self.tableStep, 0, Double(table.count - 1))
        let i = min(table.count - 2, Int(x))
        return CarProMath.lerp(table[i], table[i + 1], x - Double(i))
    }

    /// Grip of one tyre under `load`, N of force it can make.
    private static func tyre(_ p: CarProVehicleParams, _ load: Double, rear: Bool = false) -> Double {
        let l = max(0, load)
        // Tyres a few degrees off their best through a race.
        return p.compound.mu * p.gripBonus * 0.97 * (rear ? p.rearGrip : 1) * CarProTyre.loadGrip(l, nominal: p.nominalLoad) * l
    }

    /// The most sideways acceleration both axles can hold at `speed`, m/s².
    static func lateralCapacity(_ p: CarProVehicleParams, speed: Double) -> Double {
        let m = p.mass, g = CarProVehicleParams.gravity, L = p.wheelbase
        let down = p.downforce(speed)
        let front = m * g * p.toRear / L + down * p.aeroFront
        let rear = m * g * p.toFront / L + down * (1 - p.aeroFront)
        var lo = 0.0, hi = 40.0
        for _ in 0..<30 {
            let ay = (lo + hi) / 2
            let shift = m * ay * p.comHeight / p.trackWidth
            let fShift = shift * p.rollFront, rShift = shift * (1 - p.rollFront)
            let frontCap = tyre(p, front / 2 + fShift) + tyre(p, front / 2 - fShift)
            let rearCap = tyre(p, rear / 2 + rShift, rear: true) + tyre(p, rear / 2 - rShift, rear: true)
            let ok = m * ay * p.toRear / L <= frontCap && m * ay * p.toFront / L <= rearCap
            if ok { lo = ay } else { hi = ay }
        }
        return lo
    }

    /// The hardest braking at `speed` with anti-lock brakes, m/s² (tyres only).
    static func brakeCapacity(_ p: CarProVehicleParams, speed: Double) -> Double {
        let m = p.mass, g = CarProVehicleParams.gravity, L = p.wheelbase
        let down = p.downforce(speed)
        var lo = 0.0, hi = 50.0
        for _ in 0..<30 {
            let d = (lo + hi) / 2
            let shift = m * d * p.comHeight / L
            let front = m * g * p.toRear / L + down * p.aeroFront + shift
            let rear = m * g * p.toFront / L + down * (1 - p.aeroFront) - shift
            let frontCap = 2 * tyre(p, front / 2) * 1.05
            let rearCap = 2 * tyre(p, rear / 2, rear: true) * 1.05
            // Each axle brakes up to its share of the pedal or its grip.
            let frontForce = min(p.brakeBias * m * d * 1.15, frontCap)
            let rearForce = min((1 - p.brakeBias) * m * d * 1.15, rearCap)
            let ok = frontForce + rearForce >= m * d && m * d <= p.brakeTorque / p.wheelRadius
            if ok { lo = d } else { hi = d }
        }
        return lo
    }

    /// Flat out in the best gear at `speed`, m/s²: the engine also has to
    /// spin up itself and the wheels, which in the low gears is like a fifth
    /// more car. Shifts cost a little too.
    static func driveAccel(_ p: CarProVehicleParams, speed: Double) -> Double {
        var best = 0.0
        let wheels = 4 * p.wheelInertia
        for g in 1...p.topGear {
            let ratio = p.ratio(g)
            let spinning = (wheels + p.engineInertia * ratio * ratio) / (p.wheelRadius * p.wheelRadius)
            best = max(best, p.driveForce(speed: speed, gear: g) / (p.mass + spinning))
        }
        return best * (1 - 0.25 * p.shiftTime)
    }

    /// The most acceleration the driven tyres can put down at `speed`, m/s².
    static func tractionCapacity(_ p: CarProVehicleParams, speed: Double) -> Double {
        let m = p.mass, g = CarProVehicleParams.gravity, L = p.wheelbase
        let down = p.downforce(speed)
        var lo = 0.0, hi = 40.0
        for _ in 0..<30 {
            let d = (lo + hi) / 2
            let shift = m * d * p.comHeight / L
            let front = m * g * p.toRear / L + down * p.aeroFront - shift
            let rear = m * g * p.toFront / L + down * (1 - p.aeroFront) + shift
            let cap: Double
            switch p.drive {
            case .fwd: cap = 2 * tyre(p, front / 2)
            case .rwd: cap = 2 * tyre(p, rear / 2, rear: true)
            case .awd: cap = 2 * tyre(p, front / 2) + 2 * tyre(p, rear / 2, rear: true)
            }
            if m * d <= cap * 1.05 { lo = d } else { hi = d }
        }
        return lo
    }

    /// Most sideways grip at `v` on ground of `grip`, m/s².
    func lateralLimit(_ v: Double, grip: Double) -> Double { read(lateralTable, v) * grip }

    /// Hardest braking at `v` with `used` of the sideways grip already spoken for.
    func brakeLimit(_ v: Double, grip: Double, used: Double) -> Double {
        // Planned well inside the friction ellipse: braking hard while the
        // tyres are also turning is how a car runs wide.
        read(brakeTable, v) * grip * max(0, 1 - used * used) + drag * v * v + rolling
    }

    /// Hardest acceleration at `v` with `used` of the sideways grip spoken for.
    func accelLimit(_ v: Double, grip: Double, used: Double) -> Double {
        let traction = read(accelTable, v)
        return min(traction, traction * grip) * (max(0, 1 - used * used)).squareRoot() - drag * v * v - rolling
    }

    /// The fastest a bend of curvature `k` (and banking help `bank`, m/s²)
    /// can be taken on ground of `grip`.
    func cornerSpeed(curvature k: Double, grip: Double, bank: Double) -> Double {
        guard k > 1e-6 else { return topSpeed }
        // The grip table is straight lines between its speeds, so walk it to
        // the first speed the bend is too tight for, then solve the
        // quadratic k·v² = a + b·v (+ banking) on that stretch.
        let step = Self.tableStep
        var previous = 0.0
        for j in 1..<lateralTable.count {
            let v = Double(j) * step
            if k * v * v > lateralTable[j] * grip + bank {
                let a0 = lateralTable[j - 1] * grip, a1 = lateralTable[j] * grip
                let slope = (a1 - a0) / step
                let intercept = a0 - slope * previous + bank
                let disc = slope * slope + 4 * k * intercept
                let root = (slope + max(0, disc).squareRoot()) / (2 * k)
                return min(topSpeed, max(1, root))
            }
            previous = v
        }
        return topSpeed
    }
}

/// A braking zone on the racing line, for the boards and the HUD.
struct CarProBrakeMarker: Equatable, Identifiable {
    /// Where to brake, metres round.
    let distance: Double
    /// Where the braking ends (the slowest point), metres round.
    let apexDistance: Double
    let entrySpeed: Double
    let apexSpeed: Double
    var id: Double { distance }
}

/// How fast one car can go round the racing line of one circuit.
struct CarProSpeedProfile: Equatable {
    /// m/s at each centre-line sample.
    let speeds: [Double]
    /// Seconds for a flying lap at these speeds.
    let lapTime: Double
    let brakeMarkers: [CarProBrakeMarker]
    /// The car's limits it was planned with.
    let performance: CarProPerformance

    init(track: CarProTrack, performance perf: CarProPerformance) {
        performance = perf
        let samples = track.samples
        let n = samples.count
        let g = CarProVehicleParams.gravity
        var segment = [Double](repeating: track.spacing, count: n)
        for i in 0..<n {
            segment[i] = max(0.5, (samples[(i + 1) % n].linePoint - samples[i].linePoint).length)
        }
        // The fastest each sample's bend allows.
        var corner = [Double](repeating: perf.topSpeed, count: n)
        for i in 0..<n {
            let s = samples[i]
            let bank = g * sin(abs(s.bank)) * (s.bank * s.lineCurvature >= 0 ? 1 : -1)
            corner[i] = perf.cornerSpeed(curvature: abs(s.lineCurvature), grip: s.surface.grip, bank: bank)
        }
        func used(_ v: Double, _ i: Int) -> Double {
            let s = samples[i]
            let limit = perf.lateralLimit(v, grip: s.surface.grip)
            return CarProMath.clamp(v * v * abs(s.lineCurvature) / max(limit, 0.1), 0, 1)
        }
        // Accelerating out of each bend, round twice so the lap closes.
        var ahead = corner
        for pass in 0..<(2 * n) {
            let i = pass % n, next = (i + 1) % n
            let v = ahead[i]
            let a = perf.accelLimit(v, grip: samples[i].surface.grip, used: used(v, i))
            let reach = (max(0, v * v + 2 * a * segment[i])).squareRoot()
            if reach < ahead[next] { ahead[next] = max(reach, 1) }
        }
        // Braking into each bend, backwards round twice.
        var behind = corner
        for pass in 0..<(2 * n) {
            let i = (2 * n - 1 - pass) % n, prev = (i - 1 + n) % n
            let v = behind[i]
            let a = perf.brakeLimit(v, grip: samples[prev].surface.grip, used: used(v, prev))
            let reach = (v * v + 2 * a * segment[prev]).squareRoot()
            if reach < behind[prev] { behind[prev] = reach }
        }
        var speeds = [Double](repeating: 0, count: n)
        var time = 0.0
        for i in 0..<n {
            speeds[i] = max(2, min(corner[i], ahead[i], behind[i]))
        }
        for i in 0..<n {
            let v = 0.5 * (speeds[i] + speeds[(i + 1) % n])
            time += segment[i] / v
        }
        self.speeds = speeds
        lapTime = time

        // Braking zones: where the speed falls by real braking, kept when the
        // drop is worth a board.
        var markers: [CarProBrakeMarker] = []
        var braking = [Bool](repeating: false, count: n)
        for i in 0..<n { braking[i] = speeds[(i + 1) % n] < speeds[i] - 0.04 && behind[i] <= ahead[i] }
        if let firstOff = braking.firstIndex(of: false) {
            var k = 0
            while k < n {
                let i = (firstOff + k) % n
                if braking[i] && !braking[(i - 1 + n) % n] {
                    var j = i
                    var steps = 0
                    while braking[j] && steps < n { j = (j + 1) % n; steps += 1 }
                    let entry = speeds[i], apex = speeds[j]
                    if entry - apex > 6 {
                        markers.append(CarProBrakeMarker(distance: samples[i].distance, apexDistance: samples[j].distance,
                                                         entrySpeed: entry, apexSpeed: apex))
                    }
                    k += max(1, steps)
                } else {
                    k += 1
                }
            }
        }
        brakeMarkers = markers.sorted { $0.distance < $1.distance }
    }

    /// The planned speed at sample `index` (wrapping).
    func speed(at index: Int) -> Double { speeds[((index % speeds.count) + speeds.count) % speeds.count] }
}
