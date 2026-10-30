import Foundation

/// One spark thrown off a hit: it flies, slows and fades.
struct PinballSpark: Equatable {
    var p: PinballVec
    var v: PinballVec
    var life: Double
    var span: Double
    /// Which colour (`PinballGlow` picks it).
    var hue: Int
    var size: Double

    /// 1 when new, 0 when gone.
    var fade: Double { span > 0 ? max(0, life / span) : 0 }
}

/// The sparks on the table, in a pool that never grows past `cap`, so a
/// busy multiball does not pile up work for the frame.
struct PinballSparks {
    static let cap = 240
    private(set) var items: [PinballSpark] = []

    init() { items.reserveCapacity(Self.cap) }

    var isEmpty: Bool { items.isEmpty }

    /// `count` sparks from `p`, flung out at about `speed`.
    mutating func burst(at p: PinballVec, count: Int, speed: Double, hue: Int, rng: inout PinballRandom) {
        for _ in 0..<count {
            if items.count >= Self.cap { items.removeFirst() }
            let angle = rng.range(0, 2 * Double.pi)
            let s = speed * rng.range(0.35, 1)
            let span = rng.range(0.25, 0.6)
            items.append(PinballSpark(p: p, v: PinballVec(cos(angle) * s, sin(angle) * s),
                                      life: span, span: span, hue: hue, size: rng.range(2, 4.5)))
        }
    }

    mutating func step(_ dt: Double) {
        guard !items.isEmpty else { return }
        let drag = max(0, 1 - 3.2 * dt)
        var kept = 0
        for i in items.indices {
            var spark = items[i]
            spark.life -= dt
            guard spark.life > 0 else { continue }
            spark.v = spark.v * drag + PinballVec(0, 300 * dt)
            spark.p += spark.v * dt
            items[kept] = spark
            kept += 1
        }
        if kept < items.count { items.removeLast(items.count - kept) }
    }

    mutating func clear() { items.removeAll(keepingCapacity: true) }
}

/// Plays the table by itself: the demo and the screenshots. It flips a
/// flipper when a ball comes down onto it and launches gently.
enum PinballAutopilot {
    static func input(for machine: PinballMachine) -> PinballInput {
        var input = PinballInput()
        if machine.ballWaiting { input.launch = 0.42 }
        for ball in machine.balls where ball.ramp == nil && ball.inPlay {
            for flipper in machine.flippers {
                let pivot = flipper.spec.pivot
                let reach = flipper.spec.length + 18
                let dx = (ball.p.x - pivot.x) * flipper.spec.side.sign
                let near = dx > 10 && dx < reach && ball.p.y > pivot.y - 60 && ball.p.y < pivot.y + 40
                if near && ball.v.y > 40 {
                    if flipper.spec.side == .left { input.left = true } else { input.right = true }
                }
            }
        }
        return input
    }
}
