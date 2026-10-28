import Foundation

/// Liar's Dice's computer player, for solo play and spare seats.
///
/// It reasons from its own cup and the count of dice on the table, never
/// anybody else's: each unseen die shows a given face (or a wild one) one
/// time in three, so it can work out how likely any bid is to stand. It
/// gives the bidder a little credit too — people tend to bid what they hold.
///
/// On its turn it compares calling (right when the standing bid is a lie)
/// with its best raise (right when that bid is true), and takes the likelier.
/// It opens on the face it holds most of, a little under what it expects the
/// table to hold. Now and then — one turn in seven — it bluffs: a raise on a
/// face it is not strong in, as long as the bid is not absurd. Its moves are
/// candidates for the rules like anyone's, best first.
extension OfflineLiarsDiceRules: OfflineBotRules {
    /// How often it bluffs when it raises.
    static let bluffChance = 0.15

    static func botActions(_ state: State, for playerId: String, rng: inout OfflineRNG) -> [Action] {
        guard state.phase == .bidding, state.turn == playerId, isAlive(playerId, state) else { return [] }
        // Only what the bot may see: its own dice and the table's counts.
        let view = view(of: state, for: playerId)
        return botChoices(mine: view.myDice, total: view.totalDice, standing: view.bids.last,
                          turn: view.turnNumber, rng: &rng)
    }

    /// The bot's moves, best first, from its own dice, the dice in play and
    /// the standing bid.
    static func botChoices(mine: [Int], total: Int, standing: Bid?, turn: Int, rng: inout OfflineRNG) -> [Action] {
        let unseen = max(0, total - mine.count)
        // A little personality each turn: some bots call sooner than others.
        let nerve = rng.double(in: -0.08...0.08)
        guard let standing else {
            let face = favouriteFace(mine)
            let expected = Double(matching(mine, face: face)) + Double(unseen) / 3
            let quantity = max(1, min(total, Int(expected.rounded(.down)) - rng.int(in: 0...1)))
            var out: [Action] = [.bid(turn: turn, quantity: quantity, face: face)]
            if quantity != 1 || face != lowestFace { out.append(.bid(turn: turn, quantity: 1, face: lowestFace)) }
            return out
        }
        let stands = credited(standing, mine: mine, unseen: unseen)
        let raises = legalRaises(standing, total: total).map { raise in
            (raise: raise, chance: chance(atLeast: raise.quantity - matching(mine, face: raise.face), of: unseen),
             own: matching(mine, face: raise.face))
        }
        let best = raises.max { a, b in
            if abs(a.chance - b.chance) > 0.0001 { return a.chance < b.chance }
            if a.raise.quantity != b.raise.quantity { return a.raise.quantity > b.raise.quantity }
            if a.own != b.own { return a.own < b.own }
            return a.raise.face < b.raise.face
        }
        let liar = Action.liar(turn: turn)
        guard let best else { return [liar] }
        // Calling wins when the bid is a lie; raising, when the raise is true.
        if 1 - stands > best.chance + nerve { return [liar, raiseAction(best.raise, turn)] }
        var pick = best.raise
        if rng.chance(bluffChance) {
            let bluffs = raises.filter { $0.chance >= 0.3 && $0.raise != best.raise }.map(\.raise)
            if let bluff = rng.pick(bluffs) { pick = bluff }
        }
        var out = [raiseAction(pick, turn)]
        if pick != best.raise { out.append(raiseAction(best.raise, turn)) }
        out.append(liar)
        return out
    }

    /// How likely the standing bid is to stand, giving the bidder credit for
    /// holding some of what they bid: as if they hold one, more often than not.
    static func credited(_ bid: Bid, mine: [Int], unseen: Int) -> Double {
        let need = bid.quantity - matching(mine, face: bid.face)
        let plain = chance(atLeast: need, of: unseen)
        let trusting = unseen > 0 ? chance(atLeast: need - 1, of: unseen - 1) : plain
        return 0.4 * plain + 0.6 * trusting
    }

    /// The chance that at least `k` of `n` unseen dice show a face or a one
    /// (one in three each).
    static func chance(atLeast k: Int, of n: Int) -> Double {
        if k <= 0 { return 1 }
        if k > n { return 0 }
        let p = 1.0 / 3
        var total = 0.0
        var term = pow(1 - p, Double(n))   // P(0)
        for i in 0...n {
            if i >= k { total += term }
            // P(i + 1) from P(i).
            term *= Double(n - i) / Double(i + 1) * p / (1 - p)
        }
        return min(1, max(0, total))
    }

    /// Every legal raise up to three dice above the standing bid.
    static func legalRaises(_ standing: Bid, total: Int) -> [(quantity: Int, face: Int)] {
        var out: [(quantity: Int, face: Int)] = []
        let top = min(total, standing.quantity + 3)
        guard standing.quantity <= top else { return out }
        for quantity in standing.quantity...top {
            for face in lowestFace...faces where problem(quantity: quantity, face: face, standing: standing, total: total) == nil {
                out.append((quantity, face))
            }
        }
        return out
    }

    private static func raiseAction(_ raise: (quantity: Int, face: Int), _ turn: Int) -> Action {
        .bid(turn: turn, quantity: raise.quantity, face: raise.face)
    }
}
