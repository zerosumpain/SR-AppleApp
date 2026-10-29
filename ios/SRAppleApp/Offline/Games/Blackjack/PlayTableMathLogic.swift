import Foundation

// The arithmetic behind the table art the nearby card, word and board games
// share (`PlayTableArt.swift`, `PlayTableLetterTile.swift`): how much of a
// turn's clock is left, which chips make a stake, how a little fan of cards
// spreads, the small fixed wobble that makes a pile look dropped rather than
// stacked, the boxes either side of a line, the letters a die flicks through
// before it lands.
//
// Foundation only, so it is unit-tested on Linux (`PlayTableMathTests`). It
// decides nothing about any game: every rule stays in the games' own Logic
// files, which travel between phones.
enum PlayTableMath {
    // MARK: - Clocks

    /// How much of a timer is left: 1 at the start, 0 when it runs out.
    static func drainFraction(secondsLeft: Double, total: Double) -> Double {
        guard total > 0, secondsLeft.isFinite else { return 0 }
        return min(1, max(0, secondsLeft / total))
    }

    /// How a timer should look: calm, getting on, or nearly gone.
    enum Urgency: Equatable {
        case calm, hurry, urgent
    }

    /// Urgent in the last fifth (never more than the last five seconds, never
    /// less than the last one), hurrying in the last two fifths.
    static func urgency(secondsLeft: Double, total: Double) -> Urgency {
        guard total > 0 else { return .calm }
        let urgentAt = max(1, min(5, total * 0.2))
        if secondsLeft <= urgentAt { return .urgent }
        if secondsLeft <= total * 0.4 { return .hurry }
        return .calm
    }

    /// Whole seconds to show for a timer: rounded up, so "1" shows until the
    /// very end and "0" only once it has run out.
    static func shownSeconds(_ secondsLeft: Double) -> Int {
        guard secondsLeft.isFinite, secondsLeft > 0 else { return 0 }
        return Int(secondsLeft.rounded(.up))
    }

    // MARK: - Chips

    /// One stack of chips of one value.
    struct Chip: Equatable {
        let value: Int
        let count: Int
    }

    /// The chip values on the table, biggest first.
    static let chipValues: [Int] = [100, 25, 10, 5, 1]

    /// The fewest chips that make `amount`, biggest value first, each stack
    /// drawn no taller than `maxPerStack` (the art, not the sum).
    static func chips(for amount: Int, maxPerStack: Int = 6) -> [Chip] {
        guard amount > 0 else { return [] }
        var left = amount
        var out: [Chip] = []
        for value in chipValues {
            let count = left / value
            guard count > 0 else { continue }
            left -= count * value
            out.append(Chip(value: value, count: min(count, max(1, maxPerStack))))
        }
        return out
    }

    // MARK: - Fans and piles

    /// The turn of card `index` of `count` in a fan `spread` degrees wide,
    /// centred on upright.
    static func fanAngle(index: Int, count: Int, spread: Double) -> Double {
        guard count > 1 else { return 0 }
        let t = Double(min(max(index, 0), count - 1)) / Double(count - 1)
        return -spread / 2 + spread * t
    }

    /// How far card `index` sits above the fan's ends: 1 in the middle, 0 at
    /// either end, so a fan arches the way one held in a hand does.
    static func fanLift(index: Int, count: Int) -> Double {
        guard count > 2 else { return 0 }
        let t = Double(min(max(index, 0), count - 1)) / Double(count - 1) * 2 - 1
        return 1 - t * t
    }

    /// A fixed wobble for item `seed`, in `-range...range`: the same seed
    /// always turns the same way, so a pile does not shuffle on every redraw.
    static func tilt(_ seed: Int, range: Double) -> Double {
        var x = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        let unit = Double(x % 10_001) / 10_000
        return (unit * 2 - 1) * range
    }

    /// How many cards of a pile of `count` to draw: enough to read as a
    /// pile, never so many it costs anything.
    static func pileShown(_ count: Int, cap: Int = 5) -> Int {
        max(0, min(count, cap))
    }

    /// The delay before item `index` of a staggered entrance starts.
    static func stagger(index: Int, step: Double, cap: Double) -> Double {
        min(cap, max(0, Double(index)) * step)
    }

    // MARK: - Boards

    /// The boxes (row × cols + col) either side of a line on a dots-and-boxes
    /// board of `rows` × `cols` boxes. A horizontal line at (row, col) runs
    /// along the top of box (row, col); a vertical one down its left side.
    static func boxesBeside(horizontal: Bool, row: Int, col: Int, rows: Int, cols: Int) -> [Int] {
        var out: [Int] = []
        func add(_ r: Int, _ c: Int) {
            if r >= 0, r < rows, c >= 0, c < cols { out.append(r * cols + c) }
        }
        if horizontal {
            add(row - 1, col)
            add(row, col)
        } else {
            add(row, col - 1)
            add(row, col)
        }
        return out
    }

    /// How long a disc takes to fall `rows` spaces: a dropped thing's time
    /// goes with the square root of the drop, so a short fall is snappy and
    /// a long one still lands within a beat.
    static func dropSeconds(rows: Int) -> Double {
        let distance = Double(max(0, rows)) + 1
        return min(0.55, max(0.18, 0.12 * distance.squareRoot()))
    }

    /// Material a side is ahead by, from the piece values each has taken.
    static func materialLead(taken mine: [Int], lost theirs: [Int]) -> Int {
        mine.reduce(0, +) - theirs.reduce(0, +)
    }

    // MARK: - Dice

    /// The faces a letter die shows as it rolls, ending on `final`: `count`
    /// faces in all, none the same as the one before and none `final` until
    /// the last, so the landing always reads as a landing.
    static func rollFaces(final: String, count: Int, seed: Int) -> [String] {
        let alphabet = (65...90).compactMap { UnicodeScalar($0).map { String(Character($0)) } }
        let target = final.uppercased()
        guard count > 1 else { return [target] }
        var out: [String] = []
        var step = 0
        // The step cap is checked before every pick, so a run of skipped faces
        // can never spin forever.
        while out.count < count - 1, step <= count * 40 {
            let pick = Int((tilt(seed &+ step, range: 1) + 1) / 2 * Double(alphabet.count - 1))
            step += 1
            let face = alphabet[min(max(pick, 0), alphabet.count - 1)]
            if face == target || face == out.last { continue }
            out.append(face)
        }
        out.append(target)
        return out
    }

    // MARK: - Progress

    /// Dots for a run of `count` steps with `done` finished, at most `cap`
    /// dots: a long run is shown in proportion.
    static func progressDots(done: Int, count: Int, cap: Int) -> (filled: Int, total: Int) {
        guard count > 0, cap > 0 else { return (0, 0) }
        let total = min(count, cap)
        let clamped = min(max(done, 0), count)
        if count <= cap { return (clamped, total) }
        let filled = Int((Double(clamped) / Double(count) * Double(total)).rounded(.down))
        return (min(filled, total), total)
    }
}
