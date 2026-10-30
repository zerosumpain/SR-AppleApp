import Foundation

/// The demo's pilot: it picks the highest cloud Hop can still come down on
/// and steers to arrive over it just in time, springs first. With
/// `giveUpAfter` it climbs that many seconds and then steers for clear sky,
/// so a demo run ends and its results card is seen.
enum SkyHopperAutopilot {
    static func steer(for game: SkyHopperGame, giveUpAfter: Double? = nil) -> Double {
        if let limit = giveUpAfter, game.time >= limit { return dodge(game) }
        let hop = game.hopper
        guard let aim = target(for: game) else {
            // Nothing in reach: slow down and wait for one.
            return max(-1, min(1, -hop.vx / SkyHopperRules.topSpeed))
        }
        let dx = SkyHopperRules.wrapDelta(from: hop.x, to: aim.x)
        let wanted = dx / max(0.12, aim.time * 0.8)
        return max(-1, min(1, wanted / SkyHopperRules.topSpeed))
    }

    /// Where to be, and how long until Hop is down at that height.
    struct Aim: Equatable {
        let x: Double
        let time: Double
        let cloudId: Int
    }

    static func target(for game: SkyHopperGame) -> Aim? {
        let hop = game.hopper
        let g = SkyHopperRules.gravity
        if game.propellerLeft > 0 { return nil }
        var best: Aim?
        var bestY = -Double.infinity
        var bestSpring = false
        for cloud in game.clouds where cloud.crumbledAt == nil {
            // Later root of y + vy·t − g·t²/2 = cloud.y: on the way down.
            let disc = hop.vy * hop.vy + 2 * g * (hop.y - cloud.y)
            guard disc >= 0 else { continue }
            let t = (hop.vy + disc.squareRoot()) / g
            guard t > 0.02, t < 3 else { continue }
            // Already below Hop's feet and falling past: only clouds still beneath.
            if hop.vy <= 0 && cloud.y > hop.y { continue }
            if cloud.kind == .blinking && !cloud.isSolid(at: game.time + t) { continue }
            let at = cloud.x(after: t)
            let springX = cloud.spring.map { SkyHopperRules.wrap(at + $0) }
            let x = springX ?? at
            let dx = abs(SkyHopperRules.wrapDelta(from: hop.x, to: x))
            let room = springX == nil ? cloud.halfWidth : SkyHopperRules.springReach - 1
            guard dx <= reachable(time: t, hop: hop, toward: x) + room else { continue }
            let spring = springX != nil
            // The highest wins; a spring beats a plain cloud not far above it.
            let score = cloud.y + (spring ? 25 : 0)
            let bestScore = bestY + (bestSpring ? 25 : 0)
            if score > bestScore {
                best = Aim(x: x, time: t, cloudId: cloud.id)
                bestY = cloud.y
                bestSpring = spring
            }
        }
        return best
    }

    /// How far Hop can get sideways in `time` from the way it is moving.
    private static func reachable(time: Double, hop: SkyHopperHopper, toward x: Double) -> Double {
        let k = SkyHopperRules.steerRate
        let top = SkyHopperRules.topSpeed
        let dx = SkyHopperRules.wrapDelta(from: hop.x, to: x)
        let v0 = dx >= 0 ? hop.vx : -hop.vx
        // Full speed towards it from v0: x(t) = top·t + (v0 − top)(1 − e^(−kt))/k.
        let gone = top * time + (v0 - top) * (1 - exp(-k * time)) / k
        return max(0, gone * 0.9)
    }

    /// Steer for the widest stretch of open sky below Hop.
    private static func dodge(_ game: SkyHopperGame) -> Double {
        let hop = game.hopper
        var bestX = hop.x
        var bestGap = -1.0
        var sample = 0.0
        while sample < SkyHopperRules.width {
            var nearest = SkyHopperRules.width
            for cloud in game.clouds where cloud.crumbledAt == nil && cloud.y < hop.y + 60 && cloud.y > hop.y - 120 {
                let gap = abs(SkyHopperRules.wrapDelta(from: cloud.x, to: sample)) - cloud.halfWidth
                nearest = min(nearest, gap)
            }
            if nearest > bestGap {
                bestGap = nearest
                bestX = sample
            }
            sample += 5
        }
        let dx = SkyHopperRules.wrapDelta(from: hop.x, to: bestX)
        return max(-1, min(1, dx / 10))
    }
}
