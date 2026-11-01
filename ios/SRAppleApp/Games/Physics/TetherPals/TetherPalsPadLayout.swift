import Foundation

/// A button on a player's strip.
enum TetherPalsKey: Equatable {
    case left, right, jump, swap
}

/// Where a button sits on the pad, in the pad's own points.
struct TetherPalsPadButton: Equatable {
    let player: Int
    let key: TetherPalsKey
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// What one player is holding.
struct TetherPalsHold: Equatable {
    var left = false
    var right = false
    var jump = false

    var input: TetherPalsInput { TetherPalsInput(left: left, right: right, jump: jump) }
}

/// The pad along the bottom: a strip per player, one above the other (Pip's
/// on top). Each strip is cut into zones with no dead space between them, so
/// a thumb that lands between two drawn buttons still presses one: ◀ ▶ on
/// the left, Jump on the right and, playing solo, Swap in the middle.
enum TetherPalsPadLayout {
    /// Where each zone of a strip ends, as a share of its width.
    static func zones(solo: Bool) -> [(key: TetherPalsKey, end: Double)] {
        solo
            ? [(.left, 0.25), (.right, 0.5), (.swap, 0.68), (.jump, 1)]
            : [(.left, 0.27), (.right, 0.54), (.jump, 1)]
    }

    /// The key under a point `x` across a strip `width` wide.
    static func key(atX x: Double, width: Double, solo: Bool) -> TetherPalsKey {
        let share = width > 0 ? x / width : 0
        for zone in zones(solo: solo) where share < zone.end { return zone.key }
        return .jump
    }

    /// The player and key under a point, or nil off the pad.
    static func hit(x: Double, y: Double, width: Double, height: Double, strips: Int, solo: Bool) -> (player: Int, key: TetherPalsKey)? {
        guard strips > 0, width > 0, height > 0, x >= 0, y >= 0, x <= width, y <= height else { return nil }
        let row = min(strips - 1, Int(y / (height / Double(strips))))
        return (row, key(atX: x, width: width, solo: solo))
    }

    /// The drawn buttons: each zone, inset a little so they read as separate keys.
    static func buttons(width: Double, height: Double, strips: Int, solo: Bool, gap: Double = 4) -> [TetherPalsPadButton] {
        guard strips > 0, width > 0, height > 0 else { return [] }
        let rowHeight = height / Double(strips)
        var out: [TetherPalsPadButton] = []
        for row in 0..<strips {
            var start = 0.0
            for zone in zones(solo: solo) {
                let x0 = start * width + gap / 2, x1 = zone.end * width - gap / 2
                out.append(TetherPalsPadButton(player: row, key: zone.key, x: x0, y: Double(row) * rowHeight + gap / 2,
                                               width: max(0, x1 - x0), height: max(0, rowHeight - gap)))
                start = zone.end
            }
        }
        return out
    }

    /// The holds of every player from the keys their fingers are on.
    static func holds(_ touches: [(player: Int, key: TetherPalsKey)], strips: Int) -> [TetherPalsHold] {
        var holds = Array(repeating: TetherPalsHold(), count: max(0, strips))
        for touch in touches where touch.player >= 0 && touch.player < holds.count {
            switch touch.key {
            case .left: holds[touch.player].left = true
            case .right: holds[touch.player].right = true
            case .jump: holds[touch.player].jump = true
            case .swap: break
            }
        }
        return holds
    }
}

/// How times read on the HUD and cards.
enum TetherPalsFormat {
    /// "0:07.4", "1:02.0"; a dash for no time yet.
    static func time(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "–" }
        let tenths = Int((seconds * 10).rounded(.down))
        let minutes = tenths / 600
        let rest = tenths % 600
        let secs = rest / 10
        return "\(minutes):\(secs < 10 ? "0" : "")\(secs).\(rest % 10)"
    }

    /// A par: whole seconds, "0:40".
    static func par(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "–" }
        let whole = Int(seconds.rounded(.up))
        return "\(whole / 60):\(whole % 60 < 10 ? "0" : "")\(whole % 60)"
    }

    /// "1 pop", "3 pops", "no pops".
    static func pops(_ count: Int) -> String {
        count == 0 ? "no pops" : count == 1 ? "1 pop" : "\(count) pops"
    }
}

/// SplitMix64: the sparks' own random source, so a burst is the same every
/// time it is drawn from the same seed.
struct TetherPalsRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< 1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func range(_ low: Double, _ high: Double) -> Double { low + (high - low) * unit() }
}
