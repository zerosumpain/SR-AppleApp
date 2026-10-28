import Foundation

/// Fireworks' computer partner, for solo play and spare seats.
///
/// It plays from exactly what a player in its seat would see — its own
/// view, built by the rules: everyone else's cards, the fireworks, the
/// discards, and of its own hand only what hints have said. It never peeks.
/// From that it counts, for each of its cards, which cards it could still be
/// (the copies it can see elsewhere are not in its hand), and follows a
/// simple, honest convention, in this order:
///
/// 1. Play a card it KNOWS will land (every card it could be is next on its
///    firework). A hinted card it is fairly sure of (three in five) it plays
///    too, unless one more misfire would end the show.
/// 2. With a token, hint a partner's playable card — the hint that tells
///    them it is playable outright if there is one, else the one that tells
///    them most about it — or save a 5 or a last copy that is next to be
///    dropped. The partner next in turn comes first.
/// 3. Drop a card: one it knows is no longer needed, else its oldest card no
///    hint has touched, else a hinted one — keeping a card it knows is the
///    last of its kind (a known 5) to the very end.
///
/// Every candidate goes through `apply` like a person's move, best first,
/// and the list always ends with something legal, so a partner never stalls.
extension OfflineFireworksRules: OfflineBotRules {
    /// The chance a hinted card must have of landing before the bot plays it.
    static let likelyPlay = 0.6

    static func botActions(_ state: State, for playerId: String, rng: inout OfflineRNG) -> [Action] {
        guard state.phase == .playing, state.players.indices.contains(state.turn),
              state.players[state.turn].id == playerId, !state.left.contains(playerId) else { return [] }
        return botPlan(view(of: state, for: playerId), me: playerId)
    }

    /// The partner's moves, best first, from `me`'s view alone.
    static func botPlan(_ view: PlayerView, me: String) -> [Action] {
        guard view.phase == .playing, view.turnPlayer == me,
              let mine = view.seats.first(where: { $0.id == me }) else { return [] }
        let turn = view.turnNumber
        let unseen = unseenCopies(view)
        let stacks = view.stacks
        var out: [Action] = []

        // 1. Plays: certain first (a 5 before anything, for its token), then likely.
        let chances = mine.hand.map { (card: $0, chance: playChance($0, unseen: unseen, stacks: stacks)) }
        for entry in chances.filter({ $0.chance >= 1 }).sorted(by: { maxRank($0.card) > maxRank($1.card) }) {
            out.append(.play(turn: turn, card: entry.card.id))
        }
        if view.misfires < maxMisfires - 1 {
            for entry in chances.filter({ $0.card.touched && $0.chance >= likelyPlay && $0.chance < 1 })
                .sorted(by: { $0.chance > $1.chance }) {
                out.append(.play(turn: turn, card: entry.card.id))
            }
        }

        // 2. Hints.
        var hints: [(action: Action, score: Int)] = []
        if view.hints > 0 {
            hints = scoredHints(view, me: me)
            for hint in hints where hint.score >= 40 { out.append(hint.action) }
        }

        // 3. Drops (not while every token is in).
        if view.hints < maxHints {
            for card in discardOrder(mine.hand, unseen: unseen, stacks: stacks, discards: view.discards) {
                out.append(.discard(turn: turn, card: card.id))
            }
        }

        // Whatever hint is left: with every token in, a hint is the only way on.
        for hint in hints where hint.score < 40 { out.append(hint.action) }
        if view.hints > 0 {
            for seat in view.seats where seat.id != me && !seat.left {
                for choice in possibleHintChoices(for: seat.hand) {
                    switch choice {
                    case .colour(let c): out.append(.hintColour(turn: turn, to: seat.id, colour: c))
                    case .rank(let r): out.append(.hintRank(turn: turn, to: seat.id, rank: r))
                    }
                }
            }
        }
        // A last resort that is always legal: play the oldest card.
        if let oldest = mine.hand.first { out.append(.play(turn: turn, card: oldest.id)) }
        return out
    }

    // MARK: - Counting cards

    /// Copies of each card (`[colour][rank]`) that `me` cannot see: the deck
    /// and their own hand between them.
    static func unseenCopies(_ view: PlayerView) -> [[Int]] {
        var left = colours.map { _ in copies }
        func see(_ colour: String?, _ rank: Int?) {
            guard let colour, let rank, let c = colourIndex(colour), ranks.contains(rank) else { return }
            left[c][rank] = max(0, left[c][rank] - 1)
        }
        for (c, top) in view.stacks.enumerated() where top > 0 {
            for rank in 1...top { see(colours[c], rank) }
        }
        for card in view.discards { see(card.colour, card.rank) }
        for seat in view.seats {
            for card in seat.hand where card.colour != nil { see(card.colour, card.rank) }
        }
        return left
    }

    /// What one of my cards could be: each identity the hints allow, with the
    /// unseen copies of it.
    static func candidates(_ card: CardView, unseen: [[Int]]) -> [(colour: Int, rank: Int, copies: Int)] {
        var out: [(colour: Int, rank: Int, copies: Int)] = []
        for colour in card.colours {
            guard let c = colourIndex(colour) else { continue }
            for rank in card.ranks where unseen[c][rank] > 0 { out.append((c, rank, unseen[c][rank])) }
        }
        return out
    }

    /// The chance my card lands if played now, by unseen copies.
    static func playChance(_ card: CardView, unseen: [[Int]], stacks: [Int]) -> Double {
        let options = candidates(card, unseen: unseen)
        let total = options.reduce(0) { $0 + $1.copies }
        guard total > 0 else { return 0 }
        let good = options.filter { stacks[$0.colour] == $0.rank - 1 }.reduce(0) { $0 + $1.copies }
        return Double(good) / Double(total)
    }

    private static func maxRank(_ card: CardView) -> Int { card.ranks.max() ?? 0 }

    /// My cards in the order to drop them: certainly useless first, then the
    /// untouched, oldest first, then the hinted, then any it knows is the last
    /// of its kind; never one certain to land.
    static func discardOrder(_ hand: [CardView], unseen: [[Int]], stacks: [Int], discards: [Card]) -> [CardView] {
        func useless(_ card: CardView) -> Bool {
            let options = candidates(card, unseen: unseen)
            return !options.isEmpty && options.allSatisfy { $0.rank <= stacks[$0.colour] }
        }
        /// Every card it could be is still needed and the last copy left.
        func last(_ card: CardView) -> Bool {
            let options = candidates(card, unseen: unseen)
            return !options.isEmpty && options.allSatisfy { option in
                guard option.rank > stacks[option.colour] else { return false }
                let gone = discards.filter { colourIndex($0.colour) == option.colour && $0.rank == option.rank }.count
                return copies[option.rank] - gone <= 1
            }
        }
        let sure = hand.filter { playChance($0, unseen: unseen, stacks: stacks) >= 1 }.map(\.id)
        let pool = hand.filter { !sure.contains($0.id) }
        var order = pool.filter(useless)
        order += pool.filter { !$0.touched && !useless($0) && !last($0) }
        order += pool.filter { $0.touched && !useless($0) && !last($0) }
        order += pool.filter { !useless($0) && last($0) }
        return order
    }

    // MARK: - Hints

    /// Every hint worth giving, best first, with a score: 100 and up tells a
    /// partner a card is playable outright, 60 saves a 5 or a last copy about
    /// to be dropped (a number hint a little ahead of a colour), 40 tells them
    /// something about a playable card, below that only adds information.
    /// Hints are true, so none can make a card that will not land look
    /// certain to.
    static func scoredHints(_ view: PlayerView, me: String) -> [(action: Action, score: Int)] {
        guard let at = view.seats.firstIndex(where: { $0.id == me }) else { return [] }
        let stacks = view.stacks
        var scored: [(action: Action, score: Int)] = []
        for step in 1..<max(1, view.seats.count) {
            let seat = view.seats[(at + step) % view.seats.count]
            guard !seat.left, seat.id != me, !seat.hand.isEmpty else { continue }
            let nearer = (view.seats.count - step) * 2
            for choice in possibleHintChoices(for: seat.hand) {
                let touched = touched(by: choice, in: seat.hand)
                var score = 0
                for card in seat.hand {
                    guard let colour = card.colour, let rank = card.rank else { continue }
                    let on = touched.contains(card.id)
                    let after = knowledge(card, after: choice, touched: on)
                    let looksSure = !after.colours.isEmpty && !after.ranks.isEmpty
                        && after.colours.allSatisfy { c in after.ranks.allSatisfy { r in playable(colour: c, rank: r, stacks: stacks) } }
                    let isPlayable = playable(colour: colour, rank: rank, stacks: stacks)
                    let knewSure = card.colours.allSatisfy { c in card.ranks.allSatisfy { r in playable(colour: c, rank: r, stacks: stacks) } }
                    guard on else { continue }
                    let learns = after.colours.count < card.colours.count || after.ranks.count < card.ranks.count
                    if isPlayable && !knewSure {
                        score = max(score, looksSure ? 100 : learns ? 40 : 0)
                    } else if learns {
                        let top = colourIndex(colour).map { stacks[$0] } ?? 0
                        let chop = seat.hand.first { !$0.touched }?.id == card.id
                        if chop, rank > top, rank == 5 || copies[rank] - discarded(colour, rank, view.discards) <= 1 {
                            if case .rank = choice { score = max(score, 65) } else { score = max(score, 60) }
                        } else if rank > top {
                            score = max(score, 1)
                        }
                    }
                }
                guard score > 0 else { continue }
                let total = score + (score >= 40 ? nearer : 0)
                let action: Action
                switch choice {
                case .colour(let c): action = .hintColour(turn: view.turnNumber, to: seat.id, colour: c)
                case .rank(let r): action = .hintRank(turn: view.turnNumber, to: seat.id, rank: r)
                }
                scored.append((action, total))
            }
        }
        // Stable: equal scores keep seat order, colours before numbers.
        return scored.enumerated().sorted { a, b in
            a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset
        }.map(\.element)
    }

    /// What a card's owner would know after a hint, from the hints alone.
    static func knowledge(_ card: CardView, after choice: HintChoice, touched on: Bool) -> (colours: [String], ranks: [Int]) {
        switch choice {
        case .colour(let c):
            return (on ? card.colours.filter { $0 == c } : card.colours.filter { $0 != c }, card.ranks)
        case .rank(let r):
            return (card.colours, on ? card.ranks.filter { $0 == r } : card.ranks.filter { $0 != r })
        }
    }

    private static func discarded(_ colour: String, _ rank: Int, _ discards: [Card]) -> Int {
        discards.filter { $0.colour == colour && $0.rank == rank }.count
    }
}
