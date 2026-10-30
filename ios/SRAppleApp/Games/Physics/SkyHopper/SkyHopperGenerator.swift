import Foundation

/// Lays the sky out ahead of the camera from a seed.
///
/// The heart of it is the *path*: a chain of clouds each no more than
/// `SkyHopperRules.fairGap` above the last, never blinking, never two crumbly
/// ones running. A bounce from any cloud reaches the next path cloud above it
/// wherever it is across the sky (`SkyHopperRules.reach`), so there is always
/// a way up. Everything else — extra clouds, blinking ones, stars, springs
/// and power-ups — is laid around the path.
struct SkyHopperGenerator: Equatable {
    private var rng: SkyHopperRandom
    private(set) var nextId = 0
    /// The top path cloud so far.
    private(set) var pathY: Double = 0
    private(set) var pathX: Double = 50
    private(set) var pathCount = 0
    private var lastPathKind: SkyHopperCloudKind = .plain
    private var lastGap: Double = 0

    init(seed: UInt64) {
        rng = SkyHopperRandom(seed: seed)
    }

    /// The wide home cloud a run starts on, right across the sky.
    mutating func start(clouds: inout [SkyHopperCloud], pickups: inout [SkyHopperPickup]) {
        clouds.append(SkyHopperCloud(id: takeId(), kind: .plain, x: SkyHopperRules.width / 2, y: 0,
                                     halfWidth: SkyHopperRules.width / 2, onPath: true, home: true))
        pathY = 0
        pathX = SkyHopperRules.width / 2
    }

    /// Path clouds (and what goes with them) up to `top`. Bounded, so a
    /// propeller's climb can never make it run away.
    mutating func fill(upTo top: Double, clouds: inout [SkyHopperCloud], pickups: inout [SkyHopperPickup]) {
        var laid = 0
        while pathY < top && laid < 48 {
            layNext(clouds: &clouds, pickups: &pickups)
            laid += 1
        }
    }

    private mutating func takeId() -> Int {
        nextId += 1
        return nextId
    }

    private mutating func layNext(clouds: inout [SkyHopperCloud], pickups: inout [SkyHopperPickup]) {
        let d = SkyHopperRules.difficulty(climb: pathY)
        let index = pathCount + 1
        let special = index == SkyHopperRules.firstSpringIndex || index == SkyHopperRules.firstPropellerIndex

        var kind = SkyHopperCloudKind.plain
        let roll = rng.unit()
        if !special {
            if roll < SkyHopperRules.slideChance(difficulty: d) {
                kind = .sliding
            } else if roll < SkyHopperRules.slideChance(difficulty: d) + SkyHopperRules.crumblyChance(difficulty: d),
                      pathY >= SkyHopperRules.crumblyFrom, lastPathKind != .crumbly {
                kind = .crumbly
            }
        }

        var gap = min(SkyHopperRules.fairGap, rng.double(in: SkyHopperRules.gapRange(difficulty: d)))
        // A crumbly cloud is a short step, and the one after it is in reach
        // of the one before it: when it crumbles, the way up is still there.
        if kind == .crumbly { gap = min(gap, SkyHopperRules.crumblyGap) }
        if lastPathKind == .crumbly { gap = min(gap, SkyHopperRules.fairGap - lastGap) }
        let y = pathY + gap
        let half = SkyHopperRules.cloudHalfWidth(difficulty: d)
        let x = rng.double(in: half...(SkyHopperRules.width - half))
        pathCount = index

        let direction: Double = rng.chance(0.5) ? -1 : 1
        let vx = kind == .sliding ? direction * SkyHopperRules.slideSpeed(difficulty: d) : 0

        var spring: Double?
        let springRoll = rng.unit()
        if kind != .crumbly && index != SkyHopperRules.firstPropellerIndex
            && (index == SkyHopperRules.firstSpringIndex
                || (index > SkyHopperRules.firstSpringIndex && springRoll < SkyHopperRules.springChance(difficulty: d))) {
            spring = rng.double(in: -(half - 4)...(half - 4))
        }

        clouds.append(SkyHopperCloud(id: takeId(), kind: kind, x: x, y: y, halfWidth: half, vx: vx,
                                     spring: spring, onPath: true))

        if let s = spring, kind == .plain {
            // A column of stars up the line of the launch.
            for k in 1...3 {
                pickups.append(SkyHopperPickup(id: takeId(), kind: .star, x: SkyHopperRules.wrap(x + s),
                                               y: y + 34 + Double(k) * 26))
            }
        } else if index == SkyHopperRules.firstPropellerIndex {
            pickups.append(SkyHopperPickup(id: takeId(), kind: .propeller, x: x, y: y + 11))
        } else if spring == nil && kind != .sliding && index > SkyHopperRules.firstPropellerIndex
                    && rng.chance(SkyHopperRules.powerUpChance(difficulty: d)) {
            let kinds: [SkyHopperPickupKind] = [.propeller, .bubble, .magnet]
            pickups.append(SkyHopperPickup(id: takeId(), kind: kinds[rng.below(kinds.count)], x: x, y: y + 11))
        }

        if rng.chance(0.5) {
            pickups.append(SkyHopperPickup(id: takeId(), kind: .star, x: rng.double(in: 6...94),
                                           y: y - gap * rng.double(in: 0.3...0.7)))
        }

        if rng.chance(SkyHopperRules.extraChance(difficulty: d)) {
            layExtra(near: x, y: y, gap: gap, difficulty: d, clouds: &clouds)
        }

        pathY = y
        pathX = x
        lastPathKind = kind
        lastGap = gap
    }

    /// A cloud off the path, across the sky from it and a little lower.
    private mutating func layExtra(near pathX: Double, y: Double, gap: Double, difficulty d: Double,
                                   clouds: inout [SkyHopperCloud]) {
        let half = SkyHopperRules.cloudHalfWidth(difficulty: d) - 0.5
        let away = rng.double(in: 30...70)
        let x = min(SkyHopperRules.width - half, max(half, SkyHopperRules.wrap(pathX + away)))
        let ey = y - gap * rng.double(in: 0.25...0.75)
        let roll = rng.unit()
        var kind = SkyHopperCloudKind.plain
        if ey >= SkyHopperRules.blinkingFrom && roll < 0.2 + 0.2 * d {
            kind = .blinking
        } else if ey >= SkyHopperRules.crumblyFrom && roll < 0.35 + 0.3 * d {
            kind = .crumbly
        } else if roll < 0.5 + 0.3 * d {
            kind = .sliding
        }
        let direction: Double = rng.chance(0.5) ? -1 : 1
        let vx = kind == .sliding ? direction * SkyHopperRules.slideSpeed(difficulty: d) * 0.8 : 0
        let phase = rng.double(in: 0...SkyHopperRules.blinkPeriod)
        clouds.append(SkyHopperCloud(id: takeId(), kind: kind, x: x, y: ey, halfWidth: half, vx: vx, phase: phase))
    }
}
