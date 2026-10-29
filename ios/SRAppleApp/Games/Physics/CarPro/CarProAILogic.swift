import Foundation

// Car Racer+ AI drivers. Each drives a real car through the same physics
// as the player, with the electronic aids on: it follows the circuit's
// racing line by pure pursuit, holds the car's speed profile scaled by its
// skill, brakes where the profile says (late or early by temperament),
// moves off the line to overtake or to avoid a car alongside, makes the
// odd mistake when its skill is low, and backs out of a wall if it is stuck.

/// Who is driving an AI car.
struct CarProDriverProfile: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    /// 0…1: how close to the car's limit it drives and how rarely it errs.
    var skill: Double
    /// 0…1: how readily it dives for a gap and how late it brakes.
    var aggression: Double
    /// Race number on the car.
    var number: Int
    /// Livery hue, 0…1.
    var hue: Double

    init(id: String, name: String, skill: Double, aggression: Double, number: Int, hue: Double) {
        self.id = id
        self.name = name
        self.skill = CarProMath.clamp(skill, 0, 1)
        self.aggression = CarProMath.clamp(aggression, 0, 1)
        self.number = number
        self.hue = hue
    }

    /// Share of the speed profile it drives at.
    var pace: Double { 0.85 + 0.11 * skill }
}

/// Another car as an AI driver sees it.
struct CarProTraffic: Equatable {
    /// Metres round the circuit, and right of the centre line.
    var distance: Double
    var offset: Double
    var speed: Double
}

/// One AI driver's state through a race.
struct CarProAI: Equatable {
    var profile: CarProDriverProfile
    private(set) var random: CarProRandom
    /// Metres off the racing line it is aiming for, and where it is now.
    private(set) var laneTarget: Double = 0
    private(set) var lane: Double = 0
    /// A mistake in progress: seconds left, and what it is.
    private(set) var mistakeTime: Double = 0
    private(set) var mistakeOverspeed = false
    private(set) var stuckTime: Double = 0
    private(set) var reverseTime: Double = 0
    private var wasBraking = false

    init(profile: CarProDriverProfile, seed: UInt64) {
        self.profile = profile
        random = CarProRandom(seed: seed ^ CarProRandom.seed(profile.id))
    }

    /// The pedals and steering for this substep. `traffic` is every car in
    /// the session; `skip` is this car's own index in it.
    mutating func drive(_ car: CarProVehicle, params p: CarProVehicleParams, track: CarProTrack,
                        profile speeds: CarProSpeedProfile, traffic: [CarProTraffic], skip: Int = -1,
                        dt: Double) -> CarProInput {
        let n = track.samples.count
        let i = car.trackIndex
        let here = track.samples[i]
        let v = car.forwardSpeed
        let speed = max(v, 0)

        // Stuck against something: back out, then carry on.
        if reverseTime > 0 {
            reverseTime -= dt
            let away = here.direction - car.heading
            let steer: Double = CarProMath.wrap(away) > 0 ? -1 : 1
            return CarProInput(throttle: 0, brake: 1, steer: steer)
        }
        if speed < 1.5 && car.gear >= 0 {
            stuckTime += dt
            if stuckTime > 2.5 { stuckTime = 0; reverseTime = 1.6 }
        } else {
            stuckTime = 0
        }

        // Pointing the wrong way: turn back towards the road's direction, slowly.
        let facing = CarProMath.wrap(here.direction - car.heading)
        if abs(facing) > 1.9 {
            return CarProInput(throttle: 0.6, brake: 0, steer: facing > 0 ? 1 : -1)
        }

        // Traffic: pass a slower car ahead, keep clear of one alongside.
        var cap = Double.infinity
        let lineHere = here.lineOffset
        let room = here.halfWidth - 1.3
        var target = 0.0
        var nearestAhead = Double.infinity
        for (k, other) in traffic.enumerated() where k != skip {
            let gap = track.gap(from: car.trackDistance, to: other.distance)
            let side = other.offset - car.trackOffset
            if gap > 2 && gap < 34 && abs(side) < 2.9 {
                guard gap < nearestAhead else { continue }
                nearestAhead = gap
                let faster = speed > other.speed + 0.8 - profile.aggression * 1.2
                if faster {
                    // The side with more room, from where they are.
                    let leftRoom = other.offset + here.halfWidth
                    let rightRoom = here.halfWidth - other.offset
                    let dir: Double = rightRoom > leftRoom ? 1 : -1
                    let want = CarProMath.clamp(other.offset + dir * 3.4, -room, room)
                    if abs(want - other.offset) > 2.6 {
                        target = want - lineHere
                    } else if gap < 14 {
                        cap = min(cap, other.speed + 0.5)
                    }
                } else if gap < 16 - profile.aggression * 6 {
                    cap = min(cap, other.speed + 0.3)
                }
            } else if abs(gap) <= 2 + p.length && abs(side) < 2.6 {
                // Alongside: lean away.
                let away: Double = side > 0 ? -1 : 1
                target = CarProMath.clamp(car.trackOffset + away * 2.8, -room, room) - lineHere
            }
        }
        laneTarget = target
        lane = CarProMath.approach(lane, laneTarget, dt * (2.2 + profile.aggression))

        // Steering: pure pursuit of a point on the (shifted) line ahead.
        let look = 5 + 0.42 * speed
        let j = track.index(i, plus: Int(look / track.spacing))
        let s = track.samples[j]
        // Fast, it leaves itself more room to the edge.
        let edge = max(0.5, s.halfWidth - 1.1 - 0.015 * speed)
        let aim = s.point(CarProMath.clamp(s.lineOffset + lane, -edge, edge))
        let d = aim - car.position
        let localX = d.dot(car.forward), localY = d.dot(car.right)
        let distance = max(2, (localX * localX + localY * localY).squareRoot())
        let alpha = atan2(localY, max(localX, 0.1))
        let delta = atan(2 * p.wheelbase * sin(alpha) / distance)
        let steer = CarProPhysics.steerInput(forAngle: delta, car: car, params: p, assisted: true)

        // Speed: the profile at this driver's pace, a touch ahead for reaction.
        if mistakeTime > 0 { mistakeTime -= dt }
        let overspeed = mistakeTime > 0 && mistakeOverspeed ? 1.07 : 1.0
        let off = car.offTrack ? 0.75 : 1.0
        let wide = abs(car.trackOffset - (here.lineOffset + lane)) > 3 ? 0.96 : 1.0
        let pace = profile.pace * overspeed * off * wide
        let reaction = track.index(i, plus: Int((2 + speed * 0.12) / track.spacing))
        let want = min(speeds.speed(at: reaction) * pace, cap)
        // The braking the plan needs from here: the hardest slowing to any
        // point in the next 200 m, against what full pedal gives.
        let full = (0.86 + 0.09 * profile.skill + 0.05 * profile.aggression)
            * speeds.performance.brakeLimit(speed, grip: here.surface.grip, used: 0)
        var need = 0.0
        var k = 1
        while k <= 50 && k < n {
            let ahead = min(speeds.speed(at: i + k) * pace, Double(k) * track.spacing < 40 ? cap : .infinity)
            if ahead < speed {
                let dist = Double(k) * track.spacing
                need = max(need, (speed * speed - ahead * ahead) / (2 * dist))
            }
            k += k < 12 ? 1 : 3
        }
        var throttle = 0.0, brake = 0.0
        // The grip the bend asks for is not there to brake or accelerate
        // with: measured from the line's curve, not from what the car is
        // managing, which collapses exactly when it is braking too hard.
        let limit = max(1, speeds.performance.lateralLimit(speed, grip: here.surface.grip))
        let lateral = max(abs(car.accelRight), speed * speed * abs(here.lineCurvature)) / limit
        let gripRoom = CarProMath.clamp(1.15 - lateral * lateral, 0.25, 1)
        // Once on the brakes, stay on them until the plan says let go.
        let threshold = wasBraking ? 0.3 : 0.55
        if need > full * threshold || speed > want + 0.6 {
            // The pedal is a share of the brakes' torque, which on most cars
            // is more than the tyres can use: press only as hard as needed.
            let pedalDecel = p.brakeTorque / (p.wheelRadius * p.mass)
            let ask = min(need, full) / max(pedalDecel, 1) * 1.08 + max(0, speed - want) * 0.06
            brake = CarProMath.clamp(ask, 0, max(0.3, gripRoom))
        } else {
            throttle = CarProMath.clamp((want - speed) * 0.45 + 0.3, 0, gripRoom)
        }
        if mistakeTime > 0 && !mistakeOverspeed { brake *= 0.25 }

        // The rear stepping out: ease off both pedals while the steering
        // assist catches it.
        let sliding = abs(CarProPhysics.catchSlide(car: car, params: p))
        if sliding > 0 && speed > 8 {
            brake = min(brake, 0.35)
            throttle = min(throttle, max(0.1, 0.8 - sliding * 1.2))
        }

        // A mistake is rolled each time it starts to brake for a bend.
        let braking = brake > 0.2
        if braking && !wasBraking && mistakeTime <= 0 {
            let chance = (1 - profile.skill) * 0.3
            if random.next() < chance {
                mistakeOverspeed = random.next() < 0.5
                mistakeTime = mistakeOverspeed ? 1.6 : 0.35 + 0.3 * random.next()
            }
        }
        wasBraking = braking
        return CarProInput(throttle: throttle, brake: brake, steer: steer)
    }
}
