import Foundation

// One crazy-golf hole as data: the timber frame round it, the hedges and rails
// inside, and everything on the felt that changes how a ball rolls — slopes,
// sand, water and its bridges, posts, bumpers and windmills. The holes
// themselves are in `MiniGolfCourse.swift`; how a ball moves over them is in
// `MiniGolfPhysics.swift`.

/// The numbers the ball obeys. Course units: a ball is 1 in radius, and a full
/// putt starts at 60 units a second and carries about 68 on flat felt.
enum MiniGolfRules {
    static let ballRadius = 1.0
    static let cupRadius = 1.75
    /// Half a timber wall's thickness. The ball touches a wall when its centre
    /// is this plus its own radius from the wall's middle line.
    static let wallHalf = 0.45
    static var wallContact: Double { ballRadius + wallHalf }
    /// Half a windmill sail's thickness.
    static let armHalf = 0.4

    /// The physics step: 240 a second, whatever the screen's frame rate.
    static let step = 1.0 / 240
    /// No more steps than this in one frame, so a slow frame never snowballs.
    static let maxStepsPerFrame = 24

    /// A putt at full power, and the gentlest tap. A full putt carries about
    /// 68 units on flat felt.
    static let maxShot = 60.0
    static let minShot = 2.5
    /// Bumpers can add speed; nothing goes faster than this.
    static let maxSpeed = 75.0

    /// Rolling resistance on the felt and in sand, units/s², and a little air drag per second.
    static let feltFriction = 22.0
    static let sandFriction = 110.0
    static let drag = 0.12

    static let wallRestitution = 0.72
    static let postRestitution = 0.62
    /// A bumper gives back more than it is given.
    static let bumperRestitution = 1.3
    static let armRestitution = 0.55
    /// Below this speed into a surface the ball does not bounce off it, it just stops going in.
    static let bounceFloor = 1.2

    /// The cup: a ball slower than this over it drops; a faster one lips out.
    static let lipSpeed = 16.0
    /// How hard the cup's edge curls a ball towards the middle, units/s².
    static let cupPull = 150.0
    /// The ball drops once its centre is this far inside the rim (and slow enough).
    static let dropDepth = 0.25

    /// Slower than this for `restTime` seconds and the ball has stopped.
    static let restSpeed = 0.4
    static let restTime = 0.25
    /// A shot still rolling after this long is stopped where it is. Never
    /// reached on these holes (the tests say so); a guard, not a rule.
    static let maxShotTime = 45.0

    /// The most strokes a hole takes: after these the ball is picked up.
    static func maxStrokes(par: Int) -> Int { par + 4 }

    /// The putt's starting speed for a power between 0 and 1.
    static func shotSpeed(power: Double) -> Double {
        let p = min(max(power, 0), 1)
        return minShot + (maxShot - minShot) * p
    }
}

/// A round post, or a springy bumper that kicks the ball back harder.
struct MiniGolfPost: Equatable {
    enum Kind: Equatable {
        case post
        case bumper
    }

    let centre: MiniGolfVec
    let radius: Double
    let kind: Kind

    init(_ centre: MiniGolfVec, _ radius: Double, _ kind: Kind = .post) {
        self.centre = centre
        self.radius = radius
        self.kind = kind
    }

    var restitution: Double { kind == .bumper ? MiniGolfRules.bumperRestitution : MiniGolfRules.postRestitution }
}

/// A patch of felt that is not level.
struct MiniGolfSlope {
    enum Shape {
        /// The whole patch tips one way: the push, units/s², downhill.
        case tilt(MiniGolfVec)
        /// Round a point: a positive strength is a hill (pushing outwards, a
        /// banked bend or a volcano), a negative one a bowl.
        case mound(centre: MiniGolfVec, strength: Double)
    }

    let area: MiniGolfArea
    let shape: Shape

    init(_ points: [MiniGolfVec], _ shape: Shape) {
        area = MiniGolfArea(points)
        self.shape = shape
    }

    /// The push on a ball at `p`, which is inside the patch.
    func push(at p: MiniGolfVec) -> MiniGolfVec {
        switch shape {
        case .tilt(let push):
            return push
        case .mound(let centre, let strength):
            let d = p - centre
            let dist = d.length
            guard dist > 1e-9 else { return .zero }
            // The very top (or bottom) is rounded off, so there is no knife edge.
            return d * (strength * min(1, dist / 1.5) / dist)
        }
    }

    /// Which way is downhill at `p`, for the arrows drawn on the felt.
    func downhill(at p: MiniGolfVec) -> MiniGolfVec { push(at: p).unit }
}

/// A windmill: sails turning round a hub, sweeping across the way through.
struct MiniGolfWindmill: Equatable {
    let pivot: MiniGolfVec
    /// From the pivot to a sail's tip.
    let arm: Double
    let arms: Int
    /// Radians a second; positive turns clockwise on the screen.
    let speed: Double
    let phase: Double
    /// The round cap the sails are fixed to.
    let hub: Double

    init(_ pivot: MiniGolfVec, arm: Double = 7, arms: Int = 4, speed: Double = 1.0, phase: Double = 0, hub: Double = 2.2) {
        self.pivot = pivot
        self.arm = arm
        self.arms = max(1, arms)
        self.speed = speed
        self.phase = phase
        self.hub = hub
    }

    /// Sail `k`'s angle at course time `t`.
    func angle(_ k: Int, at t: Double) -> Double {
        phase + speed * t + Double(k) * 2 * .pi / Double(arms)
    }

    /// How close a ball's centre can come before a sail tip reaches it.
    var reach: Double { arm + MiniGolfRules.armHalf + MiniGolfRules.ballRadius }
}

/// A straight piece of wall, with the box a ball must be in to touch it.
struct MiniGolfWall: Equatable {
    let a: MiniGolfVec
    let b: MiniGolfVec
    let box: MiniGolfBox

    init(_ a: MiniGolfVec, _ b: MiniGolfVec) {
        self.a = a
        self.b = b
        box = MiniGolfBox(around: [a, b]).outset(MiniGolfRules.wallContact + 0.05)
    }
}

/// One hole of the course.
struct MiniGolfHole {
    /// 1 to 18.
    let number: Int
    let name: String
    /// A line of advice on the tee card.
    let tip: String
    let par: Int
    let tee: MiniGolfVec
    let cup: MiniGolfVec
    /// The timber frame, a closed polygon: the ball stays inside it.
    let boundary: [MiniGolfVec]
    /// Solid islands inside the frame (hedges, a windmill's base), closed polygons.
    let blocks: [[MiniGolfVec]]
    /// Free-standing rails, open polylines.
    let rails: [[MiniGolfVec]]
    let posts: [MiniGolfPost]
    let sand: [MiniGolfArea]
    let water: [MiniGolfArea]
    /// Planks over the water: a ball on a bridge is dry.
    let bridges: [MiniGolfArea]
    let slopes: [MiniGolfSlope]
    let windmills: [MiniGolfWindmill]
    /// Every straight piece of wall: the frame, the blocks' sides and the rails.
    let walls: [MiniGolfWall]
    let bounds: MiniGolfBox

    init(number: Int, name: String, tip: String, par: Int, tee: MiniGolfVec, cup: MiniGolfVec,
         boundary: [MiniGolfVec], blocks: [[MiniGolfVec]] = [], rails: [[MiniGolfVec]] = [],
         posts: [MiniGolfPost] = [], sand: [[MiniGolfVec]] = [], water: [[MiniGolfVec]] = [],
         bridges: [[MiniGolfVec]] = [], slopes: [MiniGolfSlope] = [], windmills: [MiniGolfWindmill] = []) {
        self.number = number
        self.name = name
        self.tip = tip
        self.par = par
        self.tee = tee
        self.cup = cup
        self.boundary = boundary
        self.blocks = blocks
        self.rails = rails
        self.posts = posts
        self.sand = sand.map { MiniGolfArea($0) }
        self.water = water.map { MiniGolfArea($0) }
        self.bridges = bridges.map { MiniGolfArea($0) }
        self.slopes = slopes
        self.windmills = windmills
        var walls: [MiniGolfWall] = []
        for loop in [boundary] + blocks where loop.count >= 2 {
            for i in 0..<loop.count {
                let a = loop[i], b = loop[(i + 1) % loop.count]
                if a.distance(to: b) > 1e-6 { walls.append(MiniGolfWall(a, b)) }
            }
        }
        for rail in rails where rail.count >= 2 {
            for i in 0..<(rail.count - 1) where rail[i].distance(to: rail[i + 1]) > 1e-6 {
                walls.append(MiniGolfWall(rail[i], rail[i + 1]))
            }
        }
        self.walls = walls
        bounds = MiniGolfBox(around: boundary)
    }

    /// On the felt: inside the frame and not inside a block.
    func isOpen(_ p: MiniGolfVec) -> Bool {
        guard bounds.contains(p), MiniGolfGeo.contains(boundary, p) else { return false }
        for block in blocks where MiniGolfGeo.contains(block, p) { return false }
        return true
    }

    func inSand(_ p: MiniGolfVec) -> Bool {
        for area in sand where area.contains(p) { return true }
        return false
    }

    /// In the water and not on a bridge.
    func inWater(_ p: MiniGolfVec) -> Bool {
        var wet = false
        for area in water where area.contains(p) {
            wet = true
            break
        }
        guard wet else { return false }
        for bridge in bridges where bridge.contains(p) { return false }
        return true
    }

    /// The slopes' total push on a ball at `p`.
    func slopePush(at p: MiniGolfVec) -> MiniGolfVec {
        var push = MiniGolfVec.zero
        for slope in slopes where slope.area.contains(p) { push += slope.push(at: p) }
        return push
    }

    /// Close enough to a windmill for a sail to reach it.
    func inSweep(_ p: MiniGolfVec) -> Bool {
        for mill in windmills where p.distance(to: mill.pivot) < mill.reach { return true }
        return false
    }

    /// Par for the hole in words, for the tee card and VoiceOver.
    var parLine: String { "Par \(par)" }
}
