import Foundation

/// Which flipper, sling or outlane.
enum PinballSide: Int, Codable, CaseIterable {
    case left, right

    /// +1 on the left, −1 on the right: the mirror the right-hand parts are built with.
    var sign: Double { self == .left ? 1 : -1 }
}

/// A wall the ball bounces off: a segment, or a capsule when it has a
/// radius (a rubber post, a lane guide). A one-way wall (the gate at the top
/// of the plunger lane) only stops a ball on its front side moving into it.
struct PinballWall: Equatable {
    var a: PinballVec
    var b: PinballVec
    var radius: Double = 0
    var bounce: Double = 0.45
    var oneWay = false
    /// Rubber: drawn as a rubber band rather than a rail.
    var rubber = false

    /// For a one-way wall, the side that blocks (up the table for a segment drawn left to right).
    var front: PinballVec { (b - a).front.normalized }
}

/// A pop bumper: a round cap that kicks the ball away on any touch.
struct PinballBumper: Equatable {
    var centre: PinballVec
    var radius: Double
}

/// A slingshot: the rubber face above a flipper that kicks the ball across.
/// The two other sides of its triangle are ordinary walls.
struct PinballSling: Equatable {
    var side: PinballSide
    /// The kicking face.
    var a: PinballVec
    var b: PinballVec
    /// The triangle's third corner, behind the face.
    var back: PinballVec
    /// The way the face kicks: away from `back`.
    var normal: PinballVec {
        var n = (b - a).front.normalized
        if n.dot(back - a) > 0 { n = -n }
        return n
    }
    var triangle: [PinballVec] { [a, b, back] }
}

/// One drop target: solid until hit, then down until the bank resets.
struct PinballTarget: Equatable {
    var a: PinballVec
    var b: PinballVec
    var centre: PinballVec { (a + b) / 2 }
}

/// A flipper's build: where it turns, how long, how thick at each end and
/// how far it swings. Angles are from the horizontal, positive pointing DOWN
/// the table; the right flipper is the left one in the mirror.
struct PinballFlipperSpec: Equatable {
    var side: PinballSide
    var pivot: PinballVec
    var length: Double = 80
    var baseRadius: Double = 12
    var tipRadius: Double = 7
    /// Resting, pointing down towards the drain.
    var restAngle: Double = 0.40
    /// Held up.
    var upAngle: Double = -0.44
    /// Radians a second, going up and falling back.
    var upSpeed: Double = 30
    var downSpeed: Double = 20
    var bounce: Double = 0.32
}

/// The ramp: a mouth the ball must be shot up hard enough to climb, and the
/// path it then rides above the table before dropping into the left inlane.
struct PinballRamp: Equatable {
    /// The back of the mouth: crossing it going in, fast enough, is a ramp shot.
    var backA: PinballVec
    var backB: PinballVec
    /// Into the ramp.
    var direction: PinballVec
    /// The slowest a ball may cross the back and still climb.
    var minSpeed: Double = 260
    /// The ride, from the back of the mouth to the drop into the inlane.
    var path: [PinballVec]
    var rideSpeed: Double = 1100
    /// How the ball leaves the end of the ride.
    var exitVelocity: PinballVec = PinballVec(0, 320)

    var backCentre: PinballVec { (backA + backB) / 2 }
    var length: Double { PinballGeometry.length(path) }
}

/// The spinner: a flag across the left orbit lane that spins as the ball goes through.
struct PinballSpinner: Equatable {
    var a: PinballVec
    var b: PinballVec
    var centre: PinballVec { (a + b) / 2 }
}

/// The whole table: every wall, toy and sensor, in table units.
///
/// The ball is 22 across; every gap a ball must pass through is wider than
/// that, every pocket it could come to rest in is either meant (the flipper
/// cradle, the plunger) or rescued by the ball search in `PinballMachine`.
struct PinballTable: Equatable {
    static let width: Double = 560
    static let height: Double = 1000
    static let ballRadius: Double = 11
    /// Below this the ball has gone down a drain.
    static let drainY: Double = 1030
    /// The middle of the playfield (the plunger lane is to its right); the
    /// right-hand flipper, sling and lanes are the left ones mirrored here.
    static let mirror: Double = 259

    var walls: [PinballWall]
    var bumpers: [PinballBumper]
    var slings: [PinballSling]
    var targets: [PinballTarget]
    /// Rollover sensors at the foot of the three top lanes.
    var lanes: [PinballVec]
    var laneRadius: Double = 14
    var spinner: PinballSpinner
    var ramp: PinballRamp
    var flippers: [PinballFlipperSpec]
    /// The plunger lane, between these two x's.
    var plungerLeft: Double = 508
    var plungerRight: Double = 550
    /// Where the plunger's tip rests; pulled back it drops `plungerTravel`.
    var plungerRest: Double = 980
    var plungerTravel: Double = 34
    /// Where a new ball sits on the plunger.
    var serve: PinballVec { PinballVec((plungerLeft + plungerRight) / 2, plungerRest - Self.ballRadius) }
    /// The playfield's outline, for drawing and for the tests.
    var outline: [PinballVec]
    /// Solid pieces inside the outline the ball must never be in.
    var solids: [[PinballVec]]
    /// The rails drawn as one line (the outer wall, the plunger lane).
    var rails: [[PinballVec]]

    var plungerLaneX: ClosedRange<Double> { plungerLeft...plungerRight }

    static let classic = PinballTable.make()

    static func make() -> PinballTable {
        var walls: [PinballWall] = []
        func chain(_ points: [PinballVec], radius: Double = 0, bounce: Double = 0.45, rubber: Bool = false) {
            guard points.count > 1 else { return }
            for i in 1..<points.count {
                walls.append(PinballWall(a: points[i - 1], b: points[i], radius: radius, bounce: bounce, rubber: rubber))
            }
        }
        let m = mirror

        // The top arch: half an ellipse from the left wall over to the right.
        var arch: [PinballVec] = []
        let steps = 48
        for i in 0...steps {
            let theta = Double.pi + Double.pi * Double(i) / Double(steps)
            arch.append(PinballVec(280 + 270 * cos(theta), 260 + 240 * sin(theta)))
        }
        // The left side: the outlane wall, the orbit return's curve (it
        // throws a ball coming down the orbit back into the middle), the
        // left wall, then the arch and the right wall down the plunger lane.
        let leftLower: [PinballVec] = [
            PinballVec(18, 1000), PinballVec(18, 640), PinballVec(80, 525),
            PinballVec(46, 508), PinballVec(26, 485), PinballVec(14, 455), PinballVec(10, 420),
        ]
        let outer = leftLower + arch + [PinballVec(550, 1000)]
        chain(outer)

        // The plunger lane's inner wall, and the one-way gate at its top
        // (it lets a launched ball out, and turns one coming round the arch
        // back into the playfield).
        chain([PinballVec(508, 1000), PinballVec(508, 340)])
        walls.append(PinballWall(a: PinballVec(508, 340), b: PinballVec(550, 300), bounce: 0.3, oneWay: true))

        // The right-hand deflector over the right outlane.
        let rightLower: [PinballVec] = [PinballVec(508, 490), PinballVec(438, 550), PinballVec(500, 660), PinballVec(500, 1000)]
        chain(rightLower)

        // Outlane dividers and inlane guides down to each flipper.
        for side in PinballSide.allCases {
            func at(_ x: Double, _ y: Double) -> PinballVec {
                side == .left ? PinballVec(x, y) : PinballVec(x, y).mirrored(m)
            }
            chain([at(58, 720), at(58, 1000)], radius: 5, bounce: 0.5, rubber: true)
            // The guide's top is tangent to the flipper's pivot, so a ball
            // rolls straight on over the pivot: no notch to stop in.
            chain([at(58, 850), at(167.9, 898.4)], radius: 5, bounce: 0.3)
            // The sling's two quiet sides.
            chain([at(100, 715), at(100, 815), at(150, 843)], radius: 3, bounce: 0.5, rubber: true)
        }

        // The left orbit lane's inner guide, splayed at the foot so the right
        // flipper's long shot finds the way in.
        chain([PinballVec(64, 230), PinballVec(98, 410)], radius: 5, bounce: 0.5, rubber: true)
        // The top lanes' guides.
        for x in [184.0, 234, 284, 334] {
            chain([PinballVec(x, 78), PinballVec(x, 118)], radius: 4, bounce: 0.5, rubber: true)
        }
        // The ramp's mouth: two rails, steep, facing the left flipper.
        let rampDir = PinballVec(0.42, -0.907)
        let across = PinballVec(0.907, 0.42)
        let mouth = PinballVec(425, 470)
        let back = mouth + rampDir * 50
        let half = 32.0
        chain([mouth - across * half, back - across * half], radius: 4, bounce: 0.35)
        chain([mouth + across * half, back + across * half], radius: 4, bounce: 0.35)

        let bumpers = [
            PinballBumper(centre: PinballVec(205, 210), radius: 25),
            PinballBumper(centre: PinballVec(313, 210), radius: 25),
            PinballBumper(centre: PinballVec(259, 292), radius: 25),
        ]

        var slings: [PinballSling] = []
        for side in PinballSide.allCases {
            func at(_ x: Double, _ y: Double) -> PinballVec {
                side == .left ? PinballVec(x, y) : PinballVec(x, y).mirrored(m)
            }
            slings.append(PinballSling(side: side, a: at(100, 715), b: at(150, 843), back: at(100, 815)))
        }

        // Three drop targets on a slant, facing the right flipper.
        let bankFrom = PinballVec(228, 437), bankTo = PinballVec(142, 463)
        var targets: [PinballTarget] = []
        for i in 0..<3 {
            let t0 = Double(i) / 3 + 0.025, t1 = Double(i + 1) / 3 - 0.025
            targets.append(PinballTarget(a: bankFrom + (bankTo - bankFrom) * t0, b: bankFrom + (bankTo - bankFrom) * t1))
        }

        let ramp = PinballRamp(
            backA: back - across * (half - 4), backB: back + across * (half - 4), direction: rampDir,
            path: [
                back, PinballVec(474, 330), PinballVec(480, 250), PinballVec(466, 185), PinballVec(430, 150),
                PinballVec(380, 138), PinballVec(300, 146), PinballVec(200, 160), PinballVec(132, 186),
                PinballVec(96, 232), PinballVec(84, 300), PinballVec(82, 400), PinballVec(80, 520),
                PinballVec(79, 620), PinballVec(79, 690),
            ]
        )

        let flippers = [
            PinballFlipperSpec(side: .left, pivot: PinballVec(165, 905)),
            PinballFlipperSpec(side: .right, pivot: PinballVec(165, 905).mirrored(m)),
        ]

        let outline = leftLower + arch + [PinballVec(550, 1000)]
        let wedge = rightLower + [PinballVec(508, 1000)]
        var solids: [[PinballVec]] = [wedge, [PinballVec(500, 1000), PinballVec(500, 340), PinballVec(508, 340), PinballVec(508, 1000)]]
        for sling in slings { solids.append(sling.triangle) }

        return PinballTable(
            walls: walls,
            bumpers: bumpers,
            slings: slings,
            targets: targets,
            lanes: [PinballVec(209, 98), PinballVec(259, 98), PinballVec(309, 98)],
            spinner: PinballSpinner(a: PinballVec(10, 330), b: PinballVec(78, 330)),
            ramp: ramp,
            flippers: flippers,
            outline: outline,
            solids: solids,
            rails: [outer, [PinballVec(508, 1000), PinballVec(508, 340)], rightLower]
        )
    }
}
