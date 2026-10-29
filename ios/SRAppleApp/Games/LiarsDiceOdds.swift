import Foundation

/// How likely a Liar's Dice bid is, as this phone can see it: my own dice are
/// known, and every die under somebody else's cup is a one-in-six chance of
/// showing a face (one-in-three when ones are wild, since a one counts too).
///
/// A guide beside the picker on easy and medium, never a rule: the server
/// rolls and settles every call. Self-contained (it repeats the one-line
/// "which dice count" rule rather than reaching for `LiarsDiceRules`) so it is
/// a unit test on its own.
enum LiarsDiceOdds {
    /// The chance one unseen die counts towards `face`.
    static func perDie(face: Int, wild: Bool) -> Double {
        (wild && face != 1) ? 2.0 / 6.0 : 1.0 / 6.0
    }

    /// My dice that count towards `face`.
    static func mine(_ dice: [Int], face: Int, wild: Bool) -> Int {
        dice.filter { $0 == face || (wild && $0 == 1) }.count
    }

    /// How many dice showing `face` the table holds, on average.
    static func expected(face: Int, mine dice: [Int], unseen: Int, wild: Bool) -> Double {
        Double(mine(dice, face: face, wild: wild)) + Double(max(0, unseen)) * perDie(face: face, wild: wild)
    }

    /// The chance at least `quantity` dice show `face`: my counting dice, plus
    /// enough of the `unseen` ones.
    static func chance(quantity: Int, face: Int, mine dice: [Int], unseen: Int, wild: Bool) -> Double {
        let need = quantity - mine(dice, face: face, wild: wild)
        if need <= 0 { return 1 }
        let hidden = max(0, unseen)
        if need > hidden { return 0 }
        let p = perDie(face: face, wild: wild)
        var total = 0.0
        for k in need...hidden {
            total += choose(hidden, k) * pow(p, Double(k)) * pow(1 - p, Double(hidden - k))
        }
        return min(1, max(0, total))
    }

    /// n choose k, as a Double (tables are small; no overflow at 30 dice).
    static func choose(_ n: Int, _ k: Int) -> Double {
        guard k >= 0, k <= n else { return 0 }
        let k = min(k, n - k)
        var result = 1.0
        if k > 0 {
            for i in 1...k { result = result * Double(n - k + i) / Double(i) }
        }
        return result
    }

    /// How a chance reads at a glance.
    enum Feel: Equatable { case sure, likely, coinToss, unlikely, longShot, impossible }

    static func feel(_ chance: Double) -> Feel {
        if chance >= 0.999 { return .sure }
        if chance <= 0.001 { return .impossible }
        if chance >= 0.7 { return .likely }
        if chance >= 0.4 { return .coinToss }
        if chance >= 0.15 { return .unlikely }
        return .longShot
    }

    static func word(_ feel: Feel) -> String {
        switch feel {
        case .sure: return "Certain"
        case .likely: return "Likely"
        case .coinToss: return "A coin toss"
        case .unlikely: return "Unlikely"
        case .longShot: return "A long shot"
        case .impossible: return "Impossible"
        }
    }

    /// "Likely · about 70%", "Certain — you hold them", "Impossible".
    static func line(_ chance: Double) -> String {
        let f = feel(chance)
        switch f {
        case .sure: return "Certain: you can see them all"
        case .impossible: return "Impossible: not enough dice left"
        default:
            let rounded = Int((chance * 20).rounded()) * 5
            let percent = min(95, max(5, rounded))
            return "\(word(f)) · about \(percent)%"
        }
    }
}
