import Foundation

/// Old Maid: the pairing game with one queen too many, for two to five phones.
///
/// One queen (the queen of clubs) comes out of the deck, so the other three
/// can never all pair up. The 51 cards are dealt out completely and every
/// pair in every hand goes straight onto the table, face up. Then, in turn,
/// each player draws one card blind from the next player who still holds
/// cards — picking it by its position in their face-down fan — and puts down
/// any pair it makes. A player whose hand runs out is safe. The last player
/// left holding a card holds the odd queen: the Old Maid, who loses.
///
/// After every draw both hands are shuffled, so nobody at the table can
/// follow where the queen went. A player who takes too long has a card drawn
/// for them at random, and a phone that leaves keeps its hand on the table:
/// it never draws again, but the others go on drawing from it.
enum OldMaidRules: OfflineGameRules {
    /// Seconds a player has to pick a card before one is picked for them.
    static let turnSeconds: Double = 30
    /// How long the unmasked Old Maid stays on screen before the standings.
    static let finalePause: Double = 4
    /// The queen taken out before the deal, so the other three cannot all pair.
    static let removedQueen = OfflineCard(12, .clubs)

    static let info = OfflineGameInfo(
        id: "old-maid",
        title: "Old Maid",
        blurb: "Pair off your cards and don't get stuck with the last queen.",
        category: .card,
        minPlayers: 2,
        maxPlayers: 5,
        symbol: "crown.fill",
        howToPlay: [
            "One queen is taken out, then every card is dealt and pairs go down at once.",
            "On your turn, draw one face-down card from the next player who still has cards.",
            "If it pairs with a card you hold, the pair goes down automatically.",
            "Run out of cards and you are safe.",
            "Whoever is left holding the odd queen is the Old Maid.",
            "Take longer than \(Int(turnSeconds)) seconds and a card is drawn for you."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// Drawing in turn.
        case playing
        /// The Old Maid is unmasked on screen until `finaleUntil`.
        case finale
        /// The match is decided.
        case over
    }

    /// The last card that changed hands.
    struct Draw: Codable, Equatable {
        let drawer: String
        let from: String
        /// The card itself — secret unless it made a pair.
        let card: OfflineCard
        /// The pair it made and that went onto the table, if any.
        let pair: [OfflineCard]?
        /// Drawn for the player when their time ran out.
        let automatic: Bool
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Each player's hand, by id, in the face-down fan's order.
        var hands: [String: [OfflineCard]] = [:]
        /// Players whose phones have left. Their hands stay to be drawn from.
        var away: [String] = []
        /// Players who have run out of cards, in the order they went out.
        var safe: [String] = []
        var phase: Phase = .playing
        /// Who draws next; nil once the game is decided.
        var turn: String?
        /// Counts draws, so a pick meant for an earlier turn is refused.
        var turnNumber = 1
        /// When the current player's time runs out, host clock.
        var turnEndsAt: Double = 0
        /// When the finale gives way to the standings, host clock.
        var finaleUntil: Double = 0
        /// Cards on the table in pairs (the deal's pairs included).
        var discarded = 0
        var lastDraw: Draw?
        /// The Old Maid, once the game is decided.
        var loser: String?
        /// Each player's pairs put down, deal included.
        var pairs: [String: Int] = [:]
    }

    enum Action: Codable, Equatable {
        /// Draw the card at `position` (0 = leftmost) of the target's fan.
        case draw(turn: Int, position: Int)
    }

    // MARK: - What a player sees

    struct Seat: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let cards: Int
        let pairs: Int
        let safe: Bool
        let away: Bool
        /// 1 for the first out, 2 for the next…; nil while still holding cards.
        let place: Int?
    }

    /// The last draw as one player may see it.
    struct DrawNote: Codable, Equatable {
        let drawer: String
        let from: String
        /// Only for the drawer and the one drawn from — or for everyone if it paired.
        let card: OfflineCard?
        let pair: [OfflineCard]?
        let automatic: Bool
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let turn: String?
        /// Who the current player draws from.
        let target: String?
        /// How many cards the target holds — the fan to pick from.
        let targetCards: Int
        let turnNumber: Int
        let turnEndsAt: Double
        let finaleUntil: Double
        let seats: [Seat]
        /// My own hand, sorted for reading; nil for a spectator.
        let myHand: [OfflineCard]?
        let discarded: Int
        let lastDraw: DrawNote?
        /// The Old Maid, once decided.
        let loser: String?
        /// The odd queen, shown to everyone once the game is decided.
        let oldMaidCard: OfflineCard?
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var state = State(players: players)
        var deck = OfflineCard.shuffledDeck(&rng).filter { $0 != removedQueen }
        var hands: [[OfflineCard]] = Array(repeating: [], count: players.count)
        var seat = 0
        while let card = deck.popLast(), !players.isEmpty {
            hands[seat].append(card)
            seat = (seat + 1) % players.count
        }
        for (index, player) in players.enumerated() {
            let (kept, pairs) = discardPairs(hands[index])
            state.hands[player.id] = kept
            state.pairs[player.id] = pairs
            state.discarded += pairs * 2
        }
        for player in players where (state.hands[player.id] ?? []).isEmpty {
            state.safe.append(player.id)
        }
        // A random first drawer, then the first one from there who holds cards.
        let first = players.isEmpty ? 0 : rng.int(below: players.count)
        state.turn = nextDrawer(state, after: first - 1)
        state.turnEndsAt = now + turnSeconds
        settle(&state, now: now)
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard state.players.contains(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not in this game.")
        }
        guard !state.away.contains(playerId) else { throw OfflineRefusal("You have left this game.") }
        guard state.phase == .playing else { throw OfflineRefusal("The game is over.") }
        guard state.turn == playerId else {
            if state.safe.contains(playerId) { throw OfflineRefusal("You are safe — you have no cards left.") }
            throw OfflineRefusal("It's \(name(of: state.turn, in: state))'s turn.")
        }
        switch action {
        case .draw(let turn, let position):
            guard turn == state.turnNumber else { throw OfflineRefusal("That pick was for an earlier turn.") }
            guard let from = target(state) else { throw OfflineRefusal("There is nobody to draw from.") }
            let count = state.hands[from]?.count ?? 0
            guard position >= 0, position < count else { throw OfflineRefusal("That card isn't there.") }
            draw(&state, by: playerId, from: from, position: position, automatic: false, now: now, rng: &rng)
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .playing:
            guard now >= state.turnEndsAt, let drawer = state.turn, let from = target(state) else { return }
            let count = state.hands[from]?.count ?? 0
            guard count > 0 else { return }
            draw(&state, by: drawer, from: from, position: rng.int(below: count), automatic: true, now: now, rng: &rng)
        case .finale:
            if now >= state.finaleUntil { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        guard state.phase == .playing else { return }
        if state.turn == playerId {
            let seat = state.players.firstIndex { $0.id == playerId } ?? 0
            state.turn = nextDrawer(state, after: seat)
            state.turnNumber += 1
            state.turnEndsAt = now + turnSeconds
        }
        settle(&state, now: now)
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let seats = state.players.map { player -> Seat in
            let place = state.safe.firstIndex(of: player.id).map { $0 + 1 }
            return Seat(id: player.id, name: player.name, cards: state.hands[player.id]?.count ?? 0,
                        pairs: state.pairs[player.id] ?? 0, safe: place != nil,
                        away: state.away.contains(player.id), place: place)
        }
        let isPlayer = playerId.map { id in state.players.contains { $0.id == id } } ?? false
        let myHand = isPlayer ? playerId.map { OfflineCard.sortedForHand(state.hands[$0] ?? []) } : nil
        let note = state.lastDraw.map { draw -> DrawNote in
            let involved = playerId != nil && (playerId == draw.drawer || playerId == draw.from)
            let shown = involved || draw.pair != nil
            return DrawNote(drawer: draw.drawer, from: draw.from, card: shown ? draw.card : nil,
                            pair: draw.pair, automatic: draw.automatic)
        }
        let target = state.phase == .playing ? target(state) : nil
        let decided = state.phase != .playing
        return PlayerView(
            phase: state.phase, turn: state.phase == .playing ? state.turn : nil, target: target,
            targetCards: target.flatMap { state.hands[$0]?.count } ?? 0,
            turnNumber: state.turnNumber, turnEndsAt: state.turnEndsAt, finaleUntil: state.finaleUntil,
            seats: seats, myHand: myHand, discarded: state.discarded, lastDraw: note,
            loser: decided ? state.loser : nil,
            oldMaidCard: decided ? state.loser.flatMap { id in state.hands[id]?.first { $0.rank == 12 } } : nil
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    /// Fewest cards left is best: everyone safe on 0, the Old Maid on 1. A
    /// match cut short ranks whoever still holds cards by how many.
    ///
    /// Anyone who left ranks below everyone still at the table. A player who
    /// has gone never draws again — so never draws the queen — while the
    /// others empty their hand for them: without this, walking out while not
    /// holding the queen would be a sure way to end up safe.
    static func standings(_ state: State) -> [OfflineStanding] {
        let present = state.players.filter { !state.away.contains($0.id) }
        let gone = state.players.filter { state.away.contains($0.id) }
        let bottom = ranked(gone, in: state)
            .map { OfflineStanding(playerId: $0.playerId, name: $0.name, rank: $0.rank + present.count,
                                   score: $0.score, detail: $0.detail) }
        return ranked(present, in: state) + bottom
    }

    private static func ranked(_ players: [OfflinePlayer], in state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(players, score: { state.hands[$0.id]?.count ?? 0 }, detail: { player in
            var parts: [String] = []
            if let place = state.safe.firstIndex(of: player.id) {
                parts.append("safe · \(ordinal(place + 1)) out")
            } else if state.loser == player.id {
                parts.append("the Old Maid")
            }
            let pairs = state.pairs[player.id] ?? 0
            parts.append(pairs == 1 ? "1 pair" : "\(pairs) pairs")
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        }, lowerIsBetter: true)
    }

    // MARK: - Helpers

    /// Who the current player draws from: the next player round the table,
    /// after them, who still holds cards — away or not.
    static func target(_ state: State) -> String? {
        guard let drawer = state.turn, let seat = state.players.firstIndex(where: { $0.id == drawer }) else { return nil }
        let n = state.players.count
        for step in 1..<max(n, 1) {
            let id = state.players[(seat + step) % n].id
            if !(state.hands[id] ?? []).isEmpty { return id }
        }
        return nil
    }

    /// The next player who may draw — still here, still holding cards — in
    /// seat order after `seat`, coming round to `seat` itself last.
    private static func nextDrawer(_ state: State, after seat: Int) -> String? {
        let n = state.players.count
        guard n > 0 else { return nil }
        for step in 1...n {
            let id = state.players[((seat + step) % n + n) % n].id
            if !state.away.contains(id), !(state.hands[id] ?? []).isEmpty { return id }
        }
        return nil
    }

    /// Take the card at `position` from `from`'s fan into `drawer`'s hand,
    /// put down any pair, shuffle both hands, then pass the turn on.
    private static func draw(_ state: inout State, by drawer: String, from: String, position: Int,
                             automatic: Bool, now: Double, rng: inout OfflineRNG) {
        var source = state.hands[from] ?? []
        let card = source.remove(at: position)
        var hand = state.hands[drawer] ?? []
        var pair: [OfflineCard]?
        if let match = hand.firstIndex(where: { $0.rank == card.rank }) {
            pair = [hand.remove(at: match), card]
            state.pairs[drawer, default: 0] += 1
            state.discarded += 2
        } else {
            hand.append(card)
        }
        rng.shuffle(&hand)
        rng.shuffle(&source)
        state.hands[drawer] = hand
        state.hands[from] = source
        state.lastDraw = Draw(drawer: drawer, from: from, card: card, pair: pair, automatic: automatic)
        for id in [drawer, from] where (state.hands[id] ?? []).isEmpty && !state.safe.contains(id) {
            state.safe.append(id)
        }
        let seat = state.players.firstIndex { $0.id == drawer } ?? 0
        state.turn = nextDrawer(state, after: seat)
        state.turnNumber += 1
        state.turnEndsAt = now + turnSeconds
        settle(&state, now: now)
    }

    /// End the game once at most one hand holds cards, or once nobody still
    /// here can draw: whoever holds the odd queen is the Old Maid.
    private static func settle(_ state: inout State, now: Double) {
        guard state.phase == .playing else { return }
        let holders = state.players.filter { !(state.hands[$0.id] ?? []).isEmpty }
        guard holders.count <= 1 || state.turn == nil || target(state) == nil else { return }
        state.loser = holders.first { hand in (state.hands[hand.id] ?? []).contains { $0.rank == 12 } }?.id
            ?? holders.first?.id
        state.turn = nil
        state.phase = .finale
        state.finaleUntil = now + finalePause
    }

    /// A hand with every pair taken out, and how many pairs went.
    static func discardPairs(_ cards: [OfflineCard]) -> (kept: [OfflineCard], pairs: Int) {
        var kept: [OfflineCard] = []
        var pairs = 0
        for card in cards {
            if let match = kept.firstIndex(where: { $0.rank == card.rank }) {
                kept.remove(at: match)
                pairs += 1
            } else {
                kept.append(card)
            }
        }
        return (kept, pairs)
    }

    private static func name(of id: String?, in state: State) -> String {
        guard let id else { return "nobody" }
        return state.players.first { $0.id == id }?.name ?? "someone else"
    }

    static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }
}
