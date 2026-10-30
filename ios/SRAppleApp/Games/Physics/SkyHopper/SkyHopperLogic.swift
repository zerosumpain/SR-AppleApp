import Foundation

// Sky Hopper's rules, with nothing to draw: Hop, the clouds it bounces on,
// the springs, stars and power-ups, the camera that climbs with it and how a
// run ends. Foundation only, so every rule is unit-tested on the Linux job.
//
// The world is `SkyHopperRules.width` (100) units across, and y counts UP
// from the home cloud at 0. Hop's `y` is its feet. The window shows
// `viewHeight` units from `cameraY` upwards; the camera never comes down.

/// A small, fast, seeded generator (SplitMix64), so a seed always gives the
/// same sky: the tests rely on it, and so does the demo.
struct SkyHopperRandom: RandomNumberGenerator, Equatable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< 1, the same on every platform and Swift version.
    mutating func unit() -> Double {
        Double(next() >> 11) / 9_007_199_254_740_992.0
    }

    /// Somewhere in `range`.
    mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }

    /// 0 ..< n.
    mutating func below(_ n: Int) -> Int {
        guard n > 1 else { return 0 }
        let wide = next().multipliedFullWidth(by: UInt64(n))
        return Int(wide.high)
    }

    /// True `chance` of the time.
    mutating func chance(_ chance: Double) -> Bool { unit() < chance }
}

/// The numbers the game is made of.
enum SkyHopperRules {
    static let width = 100.0
    /// One fixed step of the rules, seconds.
    static let step = 1.0 / 120
    static let gravity = 300.0
    /// Up speed off a cloud: about 45 units high.
    static let bounce = 165.0
    /// Up speed off a spring: about 140 units high.
    static let springBounce = 290.0
    /// Fastest sideways, units a second, and how briskly Hop gets there.
    static let topSpeed = 120.0
    static let steerRate = 10.0
    static let hopperHalfWidth = 5.0
    static let hopperHeight = 9.0
    /// How far past a cloud's end Hop's middle can be and still land.
    static let landingSlack = 3.0
    /// How close to a spring Hop must land to be launched.
    static let springReach = 6.0
    static let propellerTime = 3.2
    static let propellerLift = 230.0
    static let magnetTime = 8.0
    static let magnetRadius = 40.0
    static let magnetPull = 170.0
    static let pickupRadius = 8.0
    static let unitsPerMetre = 5.0
    static let starPoints = 5
    /// The biggest gap the sky ever asks Hop to jump.
    static let fairGap = 40.0
    /// Where Hop is held in the window, from the bottom.
    static let cameraHold = 0.42
    /// How far below the window Hop has gone when the run is over.
    static let fallMargin = 4.0
    /// The difficulty reaches its top this high, in units (1,400 m).
    static let hardestAt = 7000.0
    static let viewHeights: ClosedRange<Double> = 110...220
    /// A blinking cloud's cycle: there, fading, gone, coming back.
    static let blinkPeriod = 3.0
    /// The path clouds that are always the same kind of fun.
    static let firstSpringIndex = 4
    static let firstPropellerIndex = 10
    /// No crumbly clouds this low (30 m): the start is gentle.
    static let crumblyFrom = 150.0
    /// A crumbly path cloud is never more than this above the last.
    static let crumblyGap = 18.0
    static let blinkingFrom = 100.0

    /// How high an ordinary bounce goes.
    static var bounceHeight: Double { bounce * bounce / (2 * gravity) }
    static var springHeight: Double { springBounce * springBounce / (2 * gravity) }

    /// 0 at the start to 1 at `hardestAt` and beyond.
    static func difficulty(climb: Double) -> Double {
        min(1, max(0, climb / hardestAt))
    }

    /// The gap from one path cloud to the next, at a difficulty.
    static func gapRange(difficulty d: Double) -> ClosedRange<Double> {
        let d = min(1, max(0, d))
        let low = 12 + 12 * d
        let high = min(fairGap, 22 + 17 * d)
        return low...high
    }

    /// Half a path cloud's width: 9 at the start, 7 at the top.
    static func cloudHalfWidth(difficulty d: Double) -> Double {
        9 - 2 * min(1, max(0, d))
    }

    static func slideChance(difficulty d: Double) -> Double { 0.05 + 0.30 * d }
    static func crumblyChance(difficulty d: Double) -> Double { 0.04 + 0.18 * d }
    static func extraChance(difficulty d: Double) -> Double { 0.6 - 0.35 * d }
    static func springChance(difficulty d: Double) -> Double { 0.12 - 0.05 * d }
    static func powerUpChance(difficulty d: Double) -> Double { 0.08 - 0.065 * d }
    /// A sliding cloud's speed, units a second.
    static func slideSpeed(difficulty d: Double) -> Double { 16 + 22 * d }

    /// Seconds after a bounce until Hop, falling, is back down to `height`
    /// above the cloud it left. Nil if a bounce never gets that high.
    static func airTime(height: Double, launch: Double = bounce) -> Double? {
        let disc = launch * launch - 2 * gravity * height
        guard disc >= 0 else { return nil }
        return (launch + disc.squareRoot()) / gravity
    }

    /// How far sideways Hop is sure to get in `time`, starting at full
    /// speed the wrong way: the worst case.
    static func reach(time: Double) -> Double {
        guard time > 0 else { return 0 }
        return topSpeed * time - 2 * topSpeed * (1 - exp(-steerRate * time)) / steerRate
    }

    static func metres(climb: Double) -> Int { Int(max(0, climb) / unitsPerMetre) }

    static func score(metres: Int, stars: Int) -> Int { metres + stars * starPoints }

    /// From `a` to `b` the short way round the wrapping sky, −50…50.
    static func wrapDelta(from a: Double, to b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: width)
        if d > width / 2 { d -= width }
        if d < -width / 2 { d += width }
        return d
    }

    /// Back inside 0 ..< width.
    static func wrap(_ x: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: width)
        return r < 0 ? r + width : r
    }

    /// How see-through a blinking cloud is, 0 (gone) to 1 (there).
    static func blinkAlpha(time: Double, phase: Double) -> Double {
        let raw = (time + phase).truncatingRemainder(dividingBy: blinkPeriod)
        let t = raw < 0 ? raw + blinkPeriod : raw
        if t < 1.9 { return 1 }
        if t < 2.3 { return 1 - (t - 1.9) / 0.4 }
        if t < 2.7 { return 0 }
        return (t - 2.7) / 0.3
    }
}

/// The kinds of cloud.
enum SkyHopperCloudKind: String, CaseIterable, Codable {
    /// White and dependable.
    case plain
    /// Glides from side to side.
    case sliding
    /// One bounce, then it crumbles away.
    case crumbly
    /// Fades out and back: solid only while it shows.
    case blinking

    var word: String {
        switch self {
        case .plain: return "cloud"
        case .sliding: return "sliding cloud"
        case .crumbly: return "crumbly cloud"
        case .blinking: return "blinking cloud"
        }
    }
}

/// One cloud in the sky.
struct SkyHopperCloud: Equatable, Identifiable {
    let id: Int
    let kind: SkyHopperCloudKind
    var x: Double
    let y: Double
    let halfWidth: Double
    /// Sideways speed of a sliding cloud.
    var vx: Double = 0
    /// Where a blinking cloud starts in its cycle, seconds.
    var phase: Double = 0
    /// A spring, as an offset from the middle.
    var spring: Double?
    /// Game time the spring last fired.
    var springAt: Double?
    /// Game time a crumbly cloud gave way.
    var crumbledAt: Double?
    /// Game time Hop last bounced here.
    var landedAt: Double?
    /// One of the clouds the way up is guaranteed through.
    var onPath = false
    /// The wide cloud a run starts on.
    var home = false

    func alpha(at time: Double) -> Double {
        kind == .blinking ? SkyHopperRules.blinkAlpha(time: time, phase: phase) : 1
    }

    /// Can be landed on at `time`.
    func isSolid(at time: Double) -> Bool {
        crumbledAt == nil && alpha(at: time) >= 0.5
    }

    /// Where a sliding cloud will be `seconds` from now, bouncing off the sides.
    func x(after seconds: Double) -> Double {
        guard vx != 0, seconds > 0 else { return x }
        let low = halfWidth, high = SkyHopperRules.width - halfWidth
        let span = high - low
        guard span > 0 else { return x }
        let travelled = (x - low) + vx * seconds
        let period = 2 * span
        var t = travelled.truncatingRemainder(dividingBy: period)
        if t < 0 { t += period }
        return low + (t <= span ? t : period - t)
    }
}

/// Things to collect.
enum SkyHopperPickupKind: String, CaseIterable, Codable {
    case star
    /// A propeller cap: steady lift for a few seconds.
    case propeller
    /// A bubble: saves one fall.
    case bubble
    /// A magnet: stars fly to Hop.
    case magnet

    var title: String {
        switch self {
        case .star: return "Star"
        case .propeller: return "Propeller cap"
        case .bubble: return "Bubble"
        case .magnet: return "Star magnet"
        }
    }
}

struct SkyHopperPickup: Equatable, Identifiable {
    let id: Int
    let kind: SkyHopperPickupKind
    var x: Double
    var y: Double
}

/// Hop: feet at `y`.
struct SkyHopperHopper: Equatable {
    var x: Double = 50
    var y: Double = 0
    var vx: Double = 0
    var vy: Double = 0
    /// Game time of the last bounce, for the squash.
    var landedAt: Double = -10
}

/// The sky's height bands, each a little harder and a different colour.
enum SkyHopperZone: Int, CaseIterable, Codable {
    case meadow, breeze, sunset, twilight, starlight, space

    var name: String {
        switch self {
        case .meadow: return "Meadow sky"
        case .breeze: return "High breeze"
        case .sunset: return "Sunset"
        case .twilight: return "Twilight"
        case .starlight: return "Starlight"
        case .space: return "Edge of space"
        }
    }

    /// Where it begins, in metres.
    var metres: Int {
        switch self {
        case .meadow: return 0
        case .breeze: return 150
        case .sunset: return 400
        case .twilight: return 800
        case .starlight: return 1300
        case .space: return 2000
        }
    }

    static func at(metres: Int) -> SkyHopperZone {
        allCases.last { metres >= $0.metres } ?? .meadow
    }

    var next: SkyHopperZone? { SkyHopperZone(rawValue: rawValue + 1) }
}

/// How a run ended, for the results card.
enum SkyHopperFall: String, Codable, Equatable {
    case missed, crumbled, blinked, launched

    var sentence: String {
        switch self {
        case .missed: return "Hop missed a cloud and dropped out of the sky."
        case .crumbled: return "A crumbly cloud gave way, with nothing underneath."
        case .blinked: return "A blinking cloud faded just as Hop arrived."
        case .launched: return "Hop came down from a big launch and missed."
        }
    }

    var tip: String {
        switch self {
        case .missed: return "Lean early: the next cloud is often across the sky, and the sides wrap round."
        case .crumbled: return "Crumbly clouds take one bounce. Pick the next cloud before you land."
        case .blinked: return "See-through clouds come and go. Wait for them to fill in."
        case .launched: return "After a spring, look down for a cloud before you start to fall."
        }
    }
}

/// Where something happened.
struct SkyHopperGrab: Equatable {
    let kind: SkyHopperPickupKind
    let x: Double
    let y: Double
}

struct SkyHopperLanding: Equatable {
    let kind: SkyHopperCloudKind
    let x: Double
    let y: Double
    let spring: Bool
}

/// What one step did, for the haptics and the sparks.
struct SkyHopperEvents: Equatable {
    var landings: [SkyHopperLanding] = []
    var grabs: [SkyHopperGrab] = []
    /// A bubble caught a fall.
    var saved = false
    var fell = false
    var propellerEnded = false
    var zone: SkyHopperZone?

    var isEmpty: Bool {
        landings.isEmpty && grabs.isEmpty && !saved && !fell && !propellerEnded && zone == nil
    }

    mutating func merge(_ other: SkyHopperEvents) {
        landings += other.landings
        grabs += other.grabs
        saved = saved || other.saved
        fell = fell || other.fell
        propellerEnded = propellerEnded || other.propellerEnded
        if let zone = other.zone { self.zone = zone }
    }
}

/// One run up the sky.
struct SkyHopperGame: Equatable {
    let seed: UInt64
    private(set) var hopper = SkyHopperHopper()
    private(set) var clouds: [SkyHopperCloud] = []
    private(set) var pickups: [SkyHopperPickup] = []
    /// The bottom of the window, in world units.
    private(set) var cameraY: Double = 0
    private(set) var viewHeight: Double
    /// Seconds of play.
    private(set) var time: Double = 0
    /// The highest Hop's feet have been.
    private(set) var climb: Double = 0
    private(set) var stars = 0
    private(set) var bounces = 0
    private(set) var springs = 0
    private(set) var powerUps = 0
    private(set) var saves = 0
    private(set) var propellerLeft: Double = 0
    private(set) var magnetLeft: Double = 0
    private(set) var hasBubble = false
    private(set) var isOver = false
    private(set) var fall: SkyHopperFall?
    private(set) var zone: SkyHopperZone = .meadow
    /// Where Hop and the camera were before the last step, for drawing
    /// between steps.
    private(set) var previousX: Double = 50
    private(set) var previousY: Double = 0
    private(set) var previousCamera: Double = 0

    private var generator: SkyHopperGenerator
    private let generates: Bool
    private var lastLanded: SkyHopperCloudKind?
    /// The last bounce was a spring, or a propeller just ran out.
    private var launched = false
    private var blinkMissAt: Double = -10

    init(seed: UInt64, viewHeight: Double = 160) {
        self.seed = seed
        self.viewHeight = Self.clampView(viewHeight)
        generator = SkyHopperGenerator(seed: seed)
        generates = true
        generator.start(clouds: &clouds, pickups: &pickups)
        generator.fill(upTo: self.viewHeight + 80, clouds: &clouds, pickups: &pickups)
    }

    /// A sky laid out by hand, for the tests: nothing more is generated.
    init(seed: UInt64 = 1, viewHeight: Double = 160, hopper: SkyHopperHopper,
         clouds: [SkyHopperCloud], pickups: [SkyHopperPickup] = []) {
        self.seed = seed
        self.viewHeight = Self.clampView(viewHeight)
        generator = SkyHopperGenerator(seed: seed)
        generates = false
        self.hopper = hopper
        self.clouds = clouds
        self.pickups = pickups
        previousX = hopper.x
        previousY = hopper.y
        climb = max(0, hopper.y)
    }

    private static func clampView(_ h: Double) -> Double {
        min(SkyHopperRules.viewHeights.upperBound, max(SkyHopperRules.viewHeights.lowerBound, h))
    }

    var metres: Int { SkyHopperRules.metres(climb: climb) }
    var score: Int { SkyHopperRules.score(metres: metres, stars: stars) }
    var difficulty: Double { SkyHopperRules.difficulty(climb: climb) }
    /// How many path clouds have been laid: the generator's progress.
    var pathLaid: Int { generator.pathCount }

    /// The board changed shape: show more or less sky.
    mutating func resize(viewHeight: Double) {
        self.viewHeight = Self.clampView(viewHeight)
        if generates { generator.fill(upTo: cameraY + self.viewHeight + 80, clouds: &clouds, pickups: &pickups) }
    }

    /// Give Hop a power-up directly (the tests, and nothing else).
    mutating func grant(_ kind: SkyHopperPickupKind) {
        apply(kind)
    }

    /// One step. `steer` is −1 (full left) … 1 (full right).
    @discardableResult
    mutating func step(steer raw: Double, dt: Double = SkyHopperRules.step) -> SkyHopperEvents {
        var events = SkyHopperEvents()
        guard !isOver, dt > 0 else { return events }
        let dt = min(dt, 0.05)
        previousX = hopper.x
        previousY = hopper.y
        previousCamera = cameraY
        time += dt

        let steer = raw.isFinite ? min(1, max(-1, raw)) : 0
        let wanted = steer * SkyHopperRules.topSpeed
        hopper.vx += (wanted - hopper.vx) * (1 - exp(-SkyHopperRules.steerRate * dt))
        hopper.x = SkyHopperRules.wrap(hopper.x + hopper.vx * dt)

        moveClouds(dt)

        let feetBefore = hopper.y
        if propellerLeft > 0 {
            propellerLeft = max(0, propellerLeft - dt)
            hopper.vy = SkyHopperRules.propellerLift
            if propellerLeft == 0 {
                events.propellerEnded = true
                launched = true
            }
        } else {
            hopper.vy -= SkyHopperRules.gravity * dt
        }
        hopper.y += hopper.vy * dt
        if hopper.vy < 0 && propellerLeft == 0 { land(from: feetBefore, events: &events) }

        magnetLeft = max(0, magnetLeft - dt)
        collect(dt, events: &events)

        climb = max(climb, hopper.y)
        cameraY = max(cameraY, hopper.y - viewHeight * SkyHopperRules.cameraHold)
        let reached = SkyHopperZone.at(metres: metres)
        if reached.rawValue > zone.rawValue {
            zone = reached
            events.zone = reached
        }

        if hopper.y + SkyHopperRules.hopperHeight < cameraY - SkyHopperRules.fallMargin {
            if hasBubble {
                hasBubble = false
                saves += 1
                launched = true
                hopper.y = cameraY - SkyHopperRules.hopperHeight
                hopper.vy = SkyHopperRules.springBounce
                events.saved = true
            } else {
                isOver = true
                fall = cause
                events.fell = true
                return events
            }
        }

        tidy()
        if generates {
            generator.fill(upTo: cameraY + viewHeight + 80, clouds: &clouds, pickups: &pickups)
        }
        return events
    }

    private var cause: SkyHopperFall {
        if time - blinkMissAt < 1.5 { return .blinked }
        if launched { return .launched }
        if lastLanded == .crumbly { return .crumbled }
        return .missed
    }

    private mutating func moveClouds(_ dt: Double) {
        let width = SkyHopperRules.width
        for i in clouds.indices where clouds[i].vx != 0 && clouds[i].crumbledAt == nil {
            var c = clouds[i]
            c.x += c.vx * dt
            if c.x < c.halfWidth {
                c.x = c.halfWidth
                c.vx = abs(c.vx)
            } else if c.x > width - c.halfWidth {
                c.x = width - c.halfWidth
                c.vx = -abs(c.vx)
            }
            clouds[i] = c
        }
    }

    /// Falling through a cloud's top edge is a bounce: the highest one
    /// crossed this step.
    private mutating func land(from feetBefore: Double, events: inout SkyHopperEvents) {
        var best: Int?
        for i in clouds.indices {
            let c = clouds[i]
            guard c.crumbledAt == nil, feetBefore >= c.y - 0.001, hopper.y <= c.y else { continue }
            guard abs(SkyHopperRules.wrapDelta(from: c.x, to: hopper.x)) <= c.halfWidth + SkyHopperRules.landingSlack else { continue }
            if !c.isSolid(at: time) {
                blinkMissAt = time
                continue
            }
            if let b = best, clouds[b].y >= c.y { continue }
            best = i
        }
        guard let i = best else { return }
        let c = clouds[i]
        let onSpring = c.spring.map {
            abs(SkyHopperRules.wrapDelta(from: c.x + $0, to: hopper.x)) <= SkyHopperRules.springReach
        } ?? false
        hopper.y = c.y
        hopper.vy = onSpring ? SkyHopperRules.springBounce : SkyHopperRules.bounce
        hopper.landedAt = time
        bounces += 1
        launched = onSpring
        if onSpring {
            springs += 1
            clouds[i].springAt = time
        }
        if c.kind == .crumbly { clouds[i].crumbledAt = time }
        clouds[i].landedAt = time
        lastLanded = c.kind
        events.landings.append(SkyHopperLanding(kind: c.kind, x: hopper.x, y: c.y, spring: onSpring))
    }

    /// Stars and power-ups Hop touches; the magnet pulls stars in first.
    private mutating func collect(_ dt: Double, events: inout SkyHopperEvents) {
        guard !pickups.isEmpty else { return }
        let cx = hopper.x
        let cy = hopper.y + SkyHopperRules.hopperHeight / 2
        var i = pickups.count - 1
        while i >= 0 {
            var p = pickups[i]
            var dx = SkyHopperRules.wrapDelta(from: p.x, to: cx)
            var dy = cy - p.y
            var distance = (dx * dx + dy * dy).squareRoot()
            if p.kind == .star && magnetLeft > 0 && distance < SkyHopperRules.magnetRadius && distance > 0 {
                let move = min(distance, SkyHopperRules.magnetPull * dt)
                p.x = SkyHopperRules.wrap(p.x + dx / distance * move)
                p.y += dy / distance * move
                pickups[i] = p
                dx = SkyHopperRules.wrapDelta(from: p.x, to: cx)
                dy = cy - p.y
                distance = (dx * dx + dy * dy).squareRoot()
            }
            if distance <= SkyHopperRules.pickupRadius {
                pickups.remove(at: i)
                apply(p.kind)
                events.grabs.append(SkyHopperGrab(kind: p.kind, x: p.x, y: p.y))
            }
            i -= 1
        }
    }

    private mutating func apply(_ kind: SkyHopperPickupKind) {
        switch kind {
        case .star:
            stars += 1
        case .propeller:
            powerUps += 1
            propellerLeft = SkyHopperRules.propellerTime
            launched = false
        case .bubble:
            powerUps += 1
            hasBubble = true
        case .magnet:
            powerUps += 1
            magnetLeft = SkyHopperRules.magnetTime
        }
    }

    /// Forget what has gone out of sight below, and clouds that crumbled a
    /// while ago.
    private mutating func tidy() {
        let floor = cameraY - 40
        let now = time
        if clouds.contains(where: { $0.y < floor || ($0.crumbledAt.map { now - $0 > 1.2 } ?? false) }) {
            clouds.removeAll { $0.y < floor || ($0.crumbledAt.map { now - $0 > 1.2 } ?? false) }
        }
        if pickups.contains(where: { $0.y < floor }) {
            pickups.removeAll { $0.y < floor }
        }
    }
}
