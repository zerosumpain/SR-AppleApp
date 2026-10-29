import Foundation

/// The physics constants. Table units are about a third of a millimetre on a
/// real table; the numbers are chosen for feel, not copied from one.
enum PinballPhysics {
    /// One substep. A ball at the top speed moves 6.7 units a substep, well
    /// under its own radius (11), so it can never pass through a wall.
    static let substep: Double = 1.0 / 480
    /// The table's slope pulling the ball towards the flippers.
    static let gravity: Double = 1250
    static let maxSpeed: Double = 3200
    /// Slower than this into a wall and the ball does not bounce at all (it settles).
    static let restingSpeed: Double = 34
    /// Sliding friction along a wall, as a share of the push into it.
    static let friction: Double = 0.08
    /// Pop bumpers and slingshots throw the ball out at least this fast.
    static let bumperKick: Double = 1050
    static let slingKick: Double = 950
    /// A sling only fires when the ball comes in at least this fast.
    static let slingTrigger: Double = 90
    static let launchMin: Double = 1450
    static let launchMax: Double = 1950
    /// A nudge's shove, at full strength.
    static let nudgeSide: Double = 230
    static let nudgeLift: Double = 300
}

/// One ball.
struct PinballBall: Equatable {
    var id: Int
    var p: PinballVec
    var v: PinballVec = .zero
    /// Riding the ramp: how far along it.
    var ramp: Double?
    /// The rollover lane the ball is over, so one pass scores once.
    var lane: Int?
    /// Has left the plunger lane since it was served.
    var inPlay = false
    /// Ball search: where it was, and how long it has hardly moved.
    var anchor: PinballVec
    var still: Double = 0

    init(id: Int, p: PinballVec, v: PinballVec = .zero) {
        self.id = id
        self.p = p
        self.v = v
        anchor = p
    }

    var speed: Double { v.length }
}

/// A flipper as it moves: the angle, how fast it is turning (which the ball
/// picks up — the classic feel), and whether its button is held.
struct PinballFlipper: Equatable {
    let spec: PinballFlipperSpec
    var angle: Double
    /// d(angle)/dt, radians a second; negative while swinging up.
    var omega: Double = 0
    var held = false

    init(spec: PinballFlipperSpec) {
        self.spec = spec
        angle = spec.restAngle
    }

    var direction: PinballVec { PinballVec(spec.side.sign * cos(angle), sin(angle)) }
    var tip: PinballVec { spec.pivot + direction * spec.length }
    /// 0 at rest, 1 fully up.
    var raised: Double { (spec.restAngle - angle) / (spec.restAngle - spec.upAngle) }

    mutating func step(_ dt: Double) {
        let target = held ? spec.upAngle : spec.restAngle
        let speed = held ? spec.upSpeed : spec.downSpeed
        let diff = target - angle
        let most = speed * dt
        if abs(diff) <= most {
            omega = dt > 0 ? diff / dt : 0
            angle = target
        } else {
            omega = diff > 0 ? speed : -speed
            angle += omega * dt
        }
    }

    /// How fast the flipper's surface is moving at `point`.
    func velocity(at point: PinballVec) -> PinballVec {
        let r = point - spec.pivot
        let k: Double = omega * spec.side.sign
        return PinballVec(x: -r.y * k, y: r.x * k)
    }
}

/// What a contact did, for scoring and feedback.
struct PinballContact {
    /// How hard the ball came in, along the normal.
    var impact: Double
    var normal: PinballVec
    /// How far along the segment (0…1).
    var t: Double
}

extension PinballPhysics {
    /// Keeps `ball` outside a capsule round `a`–`b` (radius `radius`) and
    /// bounces it off. Nil when they are not touching.
    static func collide(_ ball: inout PinballBall, a: PinballVec, b: PinballVec, radius: Double,
                        bounce: Double, oneWay: Bool = false) -> PinballContact? {
        let reach = PinballTable.ballRadius + radius
        let near = PinballGeometry.closest(ball.p, a, b)
        let delta = ball.p - near.point
        let d2 = delta.lengthSquared
        guard d2 < reach * reach else { return nil }
        var n: PinballVec
        let d = d2.squareRoot()
        if d > 1e-9 {
            n = delta / d
        } else {
            n = (b - a).front.normalized
        }
        if oneWay {
            let front = (b - a).front.normalized
            // Only a ball in front of the gate, moving into it, is stopped.
            guard (ball.p - a).dot(front) > 0, ball.v.dot(front) < 0 else { return nil }
            if n.dot(front) < 0 { n = front }
        }
        ball.p = near.point + n * reach
        let vn = ball.v.dot(n)
        guard vn < 0 else { return PinballContact(impact: 0, normal: n, t: near.t) }
        ball.v = reflect(ball.v, n: n, vn: vn, bounce: bounce)
        return PinballContact(impact: -vn, normal: n, t: near.t)
    }

    /// The velocity after a bounce off a surface with normal `n`, with
    /// sliding friction; a slow touch does not bounce, so balls settle.
    static func reflect(_ v: PinballVec, n: PinballVec, vn: Double, bounce: Double) -> PinballVec {
        let e = -vn < restingSpeed ? 0 : bounce
        var out = v - n * (vn * (1 + e))
        let tangent = out - n * out.dot(n)
        let tl = tangent.length
        if tl > 1e-9 {
            let cut = min(tl, friction * -vn * (1 + e))
            out -= tangent * (cut / tl)
        }
        return out
    }

    /// A pop bumper: pushes the ball out and throws it away at `bumperKick`.
    static func bump(_ ball: inout PinballBall, _ bumper: PinballBumper) -> PinballContact? {
        let reach = PinballTable.ballRadius + bumper.radius
        let delta = ball.p - bumper.centre
        let d2 = delta.lengthSquared
        guard d2 < reach * reach else { return nil }
        let d = d2.squareRoot()
        let n = d > 1e-9 ? delta / d : PinballVec(0, -1)
        ball.p = bumper.centre + n * reach
        let vn = ball.v.dot(n)
        let tangent = ball.v - n * vn
        let out = max(bumperKick, abs(vn) * 0.8)
        ball.v = tangent * 0.9 + n * out
        return PinballContact(impact: abs(vn), normal: n, t: 0)
    }

    /// The flipper as a tapered capsule that moves: the ball bounces off it
    /// relative to the surface, then carries the surface's speed away.
    static func flip(_ ball: inout PinballBall, _ flipper: PinballFlipper) -> PinballContact? {
        let spec = flipper.spec
        let tip = flipper.tip
        let near = PinballGeometry.closest(ball.p, spec.pivot, tip)
        let rr = spec.baseRadius + (spec.tipRadius - spec.baseRadius) * near.t
        let reach = PinballTable.ballRadius + rr
        let delta = ball.p - near.point
        let d2 = delta.lengthSquared
        guard d2 < reach * reach else { return nil }
        let d = d2.squareRoot()
        let n = d > 1e-9 ? delta / d : PinballVec(0, -1)
        ball.p = near.point + n * reach
        let surface = flipper.velocity(at: near.point + n * rr)
        var rel = ball.v - surface
        let vn = rel.dot(n)
        guard vn < 0 else { return PinballContact(impact: 0, normal: n, t: near.t) }
        rel = reflect(rel, n: n, vn: vn, bounce: spec.bounce)
        ball.v = rel + surface
        return PinballContact(impact: -vn, normal: n, t: near.t)
    }

    /// Two balls in multiball: an equal-mass bounce.
    static func knock(_ one: inout PinballBall, _ two: inout PinballBall) -> Bool {
        let reach = PinballTable.ballRadius * 2
        let delta = two.p - one.p
        let d2 = delta.lengthSquared
        guard d2 < reach * reach, d2 > 1e-9 else { return false }
        let d = d2.squareRoot()
        let n = delta / d
        let push = (reach - d) / 2
        one.p -= n * push
        two.p += n * push
        let closing = (one.v - two.v).dot(n)
        guard closing > 0 else { return true }
        let j = closing * (1 + 0.9) / 2
        one.v -= n * j
        two.v += n * j
        return true
    }

    static func clampSpeed(_ v: PinballVec) -> PinballVec {
        let s2 = v.lengthSquared
        guard s2 > maxSpeed * maxSpeed else { return v }
        return v * (maxSpeed / s2.squareRoot())
    }
}
