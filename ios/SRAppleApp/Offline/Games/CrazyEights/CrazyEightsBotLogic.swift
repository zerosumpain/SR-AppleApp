import Foundation

/// Crazy Eights' computer player, for solo play and spare seats.
///
/// It sheds its most expensive card that fits, keeps its eights for when
/// nothing else will go (and then names the suit it holds most of), draws
/// when it must and plays the drawn card when it can. It never peeks: every
/// choice is made from its own hand and the top of the pile.
extension CrazyEightsRules: OfflineBotRules {
    static func botActions(_ state: State, for playerId: String, rng: inout OfflineRNG) -> [Action] {
        guard state.phase == .playing, !state.away.contains(playerId),
              let seat = state.players.firstIndex(where: { $0.id == playerId }),
              seat == state.turn else { return [] }
        let turn = state.turnNumber
        let hand = state.hands[playerId] ?? []
        if let drawn = state.drawn {
            guard fits(drawn, state: state) else { return [.pass(turn: turn)] }
            let named = drawn.rank == 8 ? favouriteSuit(hand.filter { $0 != drawn }, fallback: state.suit) : nil
            return [.play(turn: turn, card: drawn, suit: named), .pass(turn: turn)]
        }
        if state.hasDrawn { return [.pass(turn: turn)] }
        let playable = hand.filter { fits($0, state: state) }
        let plain = playable.filter { $0.rank != 8 }
            .sorted { penalty($0) == penalty($1) ? $0.id < $1.id : penalty($0) > penalty($1) }
        var out: [Action] = plain.map { .play(turn: turn, card: $0, suit: nil) }
        for eight in playable where eight.rank == 8 {
            out.append(.play(turn: turn, card: eight, suit: favouriteSuit(hand.filter { $0 != eight }, fallback: state.suit)))
        }
        out.append(.draw(turn: turn))
        out.append(.pass(turn: turn))
        return out
    }

    /// The suit `cards` hold most of, eights aside; `fallback` for none.
    static func favouriteSuit(_ cards: [OfflineCard], fallback: OfflineSuit) -> OfflineSuit {
        var counts: [OfflineSuit: Int] = [:]
        for card in cards where card.rank != 8 { counts[card.suit, default: 0] += 1 }
        let best = OfflineSuit.allCases.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
        guard let best, (counts[best] ?? 0) > 0 else { return fallback }
        return best
    }
}
