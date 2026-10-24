import Foundation

/// Crazy Eights: the shedding game, for two to five phones round a table.
///
/// Each hand deals seven cards apiece (five with four or five players) and
/// turns one up to start the discard pile. On your turn you play a card that
/// matches the top of the pile by suit or by rank; an eight is wild and you
/// name the suit the next player must follow. If you cannot — or would rather
/// not — play, you draw one card, and may play that card if it fits; otherwise
/// the turn moves on. When the stock runs out, the discard pile (all but its
/// top card) is shuffled to make a new one.
///
/// The first to empty their hand wins the hand. Everyone else scores penalty
/// points for what they still hold: an eight is 50, a picture card 10, an ace
/// 1, the rest their number. The match ends when someone reaches
/// `targetScore`, or after `maxHands` hands — lowest total wins — so a game
/// stays short enough for phones.
///
/// The host holds every hand; a player's view carries only their own cards
/// and how many the others hold. A turn has a generous timer, so a phone left
/// on the table cannot stall everyone: when it runs out the host draws for
/// that player and moves on.
enum CrazyEightsRules: OfflineGameRules {
    /// A penalty total that ends the match at the end of a hand.
    static let targetScore = 100
    /// Hands before the lowest total takes it, whatever the scores.
    static let maxHands = 5
    /// How long one turn may last before the host draws and passes for you.
    static let turnSeconds: Double = 45
    /// How long a hand's result stays up before the next deal.
    static let resultPause: Double = 6
    /// Penalty a player who has left scores for each hand they miss, so
    /// leaving is never the way to win.
    static let absentPenalty = 50

    static let info = OfflineGameInfo(
        id: "crazy-eights",
        title: "Crazy Eights",
        blurb: "Match the suit or the number; eights are wild.",
        category: .card,
        minPlayers: 2,
        maxPlayers: 5,
        symbol: "suit.club.fill",
        howToPlay: [
            "Play a card that matches the top card's suit or number.",
            "Eights are wild: play one any time and name the next suit.",
            "Can't or won't play? Draw one card — you may play it if it fits.",
            "Empty your hand first to win the hand.",
            "Cards left cost points: eights 50, pictures 10, others their number.",
            "Lowest total after \(maxHands) hands, or when someone reaches \(targetScore), wins."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// A hand is being played; `turn` is whose go it is.
        case playing
        /// The hand is over and its penalties are on screen until `nextHandAt`.
        case handOver
        /// The match is decided.
        case over
    }

    /// The last thing that happened at the table, for the "what just
    /// happened" line. A drawn card is never named here — only that someone drew.
    struct Move: Codable, Equatable {
        enum Kind: String, Codable, Equatable {
            case played, drew, passed, timedOut
        }
        let playerId: String
        let kind: Kind
        /// The card played (public: it is on the pile).
        var card: OfflineCard?
        /// The suit named with an eight.
        var named: OfflineSuit?
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left; skipped, their cards folded.
        var away: [String] = []
        var phase: Phase = .playing
        /// 1-based hand number.
        var hand = 0
        /// Every hand, by player id. Secret: each player sees only their own.
        var hands: [String: [OfflineCard]] = [:]
        /// Face down; cards are drawn from the END.
        var stock: [OfflineCard] = []
        /// Face up; the LAST card is the top of the pile.
        var discard: [OfflineCard] = []
        /// The suit to follow: the top card's, or the one an eight named.
        var suit: OfflineSuit = .clubs
        /// Seat index of the player whose turn it is.
        var turn = 0
        /// Counts every turn of the match, so a late action is spotted.
        var turnNumber = 0
        var turnEndsAt: Double = 0
        /// The card the current player drew this turn; only it may be played now.
        var drawn: OfflineCard?
        /// The current player has drawn (even if nothing was left to draw).
        var hasDrawn = false
        /// Turns in a row that ended without a card played, with nothing left
        /// to draw — enough of them and the hand is blocked.
        var idleTurns = 0
        var lastMove: Move?
        /// Penalty totals for the match.
        var scores: [String: Int] = [:]
        /// Each player's penalty for the hand just finished.
        var handPenalty: [String: Int] = [:]
        /// Who emptied their hand (nil: the hand was blocked).
        var handWinner: String?
        /// Hands each player has won.
        var handsWon: [String: Int] = [:]
        var nextHandAt: Double = 0
    }

    enum Action: Codable, Equatable {
        /// Play `card`; `suit` names the next suit when the card is an eight.
        case play(turn: Int, card: OfflineCard, suit: OfflineSuit?)
        /// Draw one card from the stock.
        case draw(turn: Int)
        /// End the turn without playing (only after drawing, or when there is
        /// nothing to draw).
        case pass(turn: Int)
    }

    // MARK: - What a player sees

    struct Seat: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        /// How many cards they hold — never which.
        let cards: Int
        let score: Int
        let away: Bool
        /// Their penalty for the hand just finished (while the result shows).
        let lastPenalty: Int?
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let hand: Int
        let maxHands: Int
        let targetScore: Int
        let seats: [Seat]
        /// My own cards, sorted; empty for a spectator.
        let myCards: [OfflineCard]
        /// Ids of my cards I may play now (empty when it is not my turn).
        let playable: [String]
        let top: OfflineCard?
        let suit: OfflineSuit
        let stockCount: Int
        /// Whose turn it is, while a hand is being played.
        let turnPlayer: String?
        let turnNumber: Int
        let turnEndsAt: Double
        /// It is my turn and I may draw.
        let canDraw: Bool
        /// It is my turn and I may end it without playing.
        let canPass: Bool
        /// The card I just drew this turn — mine only.
        let drawn: OfflineCard?
        let lastMove: Move?
        let handWinner: String?
        let nextHandAt: Double
        /// The lowest totals, once the match is over (several on a tie).
        let champions: [String]
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var state = State(players: players)
        for player in players {
            state.scores[player.id] = 0
            state.handsWon[player.id] = 0
        }
        deal(&state, now: now, rng: &rng)
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard let seat = state.players.firstIndex(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not in this game.")
        }
        guard !state.away.contains(playerId) else { throw OfflineRefusal("You have left this game.") }
        switch state.phase {
        case .playing: break
        case .handOver: throw OfflineRefusal("This hand is over — the next deal is coming.")
        case .over: throw OfflineRefusal("The game is over.")
        }
        guard seat == state.turn else {
            throw OfflineRefusal("It's \(state.players[state.turn].name)'s turn.")
        }
        let turn: Int
        switch action {
        case .play(let t, _, _), .draw(let t), .pass(let t): turn = t
        }
        guard turn == state.turnNumber else { throw OfflineRefusal("That move was for an earlier turn.") }

        switch action {
        case .play(_, let card, let named):
            var hand = state.hands[playerId] ?? []
            guard let index = hand.firstIndex(of: card) else { throw OfflineRefusal("You don't have that card.") }
            if let drawn = state.drawn, drawn != card {
                throw OfflineRefusal("After drawing you may only play the card you drew.")
            }
            guard fits(card, state: state) else { throw OfflineRefusal(mismatchReason(state)) }
            if card.rank == 8 {
                guard named != nil else { throw OfflineRefusal("Name a suit for your eight.") }
            } else if named != nil {
                throw OfflineRefusal("Only an eight can name a suit.")
            }
            hand.remove(at: index)
            state.hands[playerId] = hand
            state.discard.append(card)
            state.suit = named ?? card.suit
            state.idleTurns = 0
            state.lastMove = Move(playerId: playerId, kind: .played, card: card, named: named)
            if hand.isEmpty {
                endHand(&state, winner: playerId, now: now)
            } else {
                nextTurn(&state, now: now)
            }

        case .draw:
            guard !state.hasDrawn else { throw OfflineRefusal("You have already drawn this turn.") }
            refillStock(&state, rng: &rng)
            guard let card = state.stock.popLast() else {
                throw OfflineRefusal("There is nothing left to draw — pass instead.")
            }
            state.hands[playerId, default: []].append(card)
            state.hasDrawn = true
            state.lastMove = Move(playerId: playerId, kind: .drew)
            if fits(card, state: state) {
                // They may play it, or pass.
                state.drawn = card
            } else {
                state.idleTurns = 0
                nextTurn(&state, now: now)
            }

        case .pass:
            guard state.hasDrawn || !canDraw(state) else {
                throw OfflineRefusal("Draw a card first, or play one.")
            }
            let drewSomething = state.drawn != nil
            state.lastMove = Move(playerId: playerId, kind: .passed)
            finishIdleTurn(&state, drewSomething: drewSomething, now: now)
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .playing:
            guard now >= state.turnEndsAt else { return }
            // Out of time: draw for them if they have not, then move on.
            let player = state.players[state.turn].id
            var drewSomething = state.drawn != nil
            if !state.hasDrawn {
                refillStock(&state, rng: &rng)
                if let card = state.stock.popLast() {
                    state.hands[player, default: []].append(card)
                    drewSomething = true
                }
            }
            state.lastMove = Move(playerId: player, kind: .timedOut)
            finishIdleTurn(&state, drewSomething: drewSomething, now: now)
        case .handOver:
            guard now >= state.nextHandAt else { return }
            if decided(state) {
                state.phase = .over
            } else {
                deal(&state, now: now, rng: &rng)
            }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard let seat = state.players.firstIndex(where: { $0.id == playerId }),
              !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        // Fold their cards under the stock, so the deck stays whole.
        if let cards = state.hands[playerId], !cards.isEmpty {
            state.stock.insert(contentsOf: cards, at: 0)
        }
        state.hands[playerId] = []
        if activeIds(state).count < info.minPlayers {
            if state.phase == .playing {
                // Nobody left to play against: the hand goes to whoever remains.
                endHand(&state, winner: activeIds(state).first, now: now)
            }
            state.phase = .over
            return
        }
        if state.phase == .playing, seat == state.turn {
            state.idleTurns = 0
            nextTurn(&state, now: now)
        }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let showResult = state.phase != .playing
        let seats = state.players.map { player -> Seat in
            Seat(id: player.id, name: player.name, cards: state.hands[player.id]?.count ?? 0,
                 score: state.scores[player.id] ?? 0, away: state.away.contains(player.id),
                 lastPenalty: showResult ? state.handPenalty[player.id] : nil)
        }
        let isMyTurn = state.phase == .playing && playerId != nil && state.players[state.turn].id == playerId
        let mine = playerId.flatMap { state.hands[$0] } ?? []
        var playable: [String] = []
        if isMyTurn {
            if let drawn = state.drawn {
                playable = [drawn.id]
            } else {
                playable = mine.filter { fits($0, state: state) }.map(\.id)
            }
        }
        return PlayerView(
            phase: state.phase, hand: state.hand, maxHands: maxHands, targetScore: targetScore,
            seats: seats, myCards: OfflineCard.sortedForHand(mine), playable: playable,
            top: state.discard.last, suit: state.suit, stockCount: state.stock.count,
            turnPlayer: state.phase == .playing ? state.players[state.turn].id : nil,
            turnNumber: state.turnNumber, turnEndsAt: state.turnEndsAt,
            canDraw: isMyTurn && !state.hasDrawn && canDraw(state),
            canPass: isMyTurn && (state.hasDrawn || !canDraw(state)),
            drawn: isMyTurn ? state.drawn : nil,
            lastMove: state.lastMove, handWinner: showResult ? state.handWinner : nil,
            nextHandAt: state.nextHandAt,
            champions: state.phase == .over ? champions(state) : []
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    /// Lowest total first among the players still here; anyone who left is
    /// ranked below all of them, whatever their total, so leaving early with a
    /// low score is never a way to win.
    static func standings(_ state: State) -> [OfflineStanding] {
        let detail: (OfflinePlayer) -> String? = { player in
            var parts: [String] = []
            let won = state.handsWon[player.id] ?? 0
            if won > 0 { parts.append(won == 1 ? "won 1 hand" : "won \(won) hands") }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        let present = state.players.filter { !state.away.contains($0.id) }
        let gone = state.players.filter { state.away.contains($0.id) }
        let top = OfflineStanding.ranked(present, score: { state.scores[$0.id] ?? 0 }, detail: detail, lowerIsBetter: true)
        let bottom = OfflineStanding.ranked(gone, score: { state.scores[$0.id] ?? 0 }, detail: detail, lowerIsBetter: true)
            .map { OfflineStanding(playerId: $0.playerId, name: $0.name, rank: $0.rank + present.count,
                                   score: $0.score, detail: $0.detail) }
        return top + bottom
    }

    // MARK: - Scoring

    /// What a card left in hand costs: eight 50, picture 10, ace 1, else its number.
    static func penalty(_ card: OfflineCard) -> Int {
        if card.rank == 8 { return 50 }
        if card.isFace { return 10 }
        return card.rank
    }

    static func penalty(_ cards: [OfflineCard]) -> Int {
        cards.reduce(0) { $0 + penalty($1) }
    }

    /// Whether `card` may go on the pile now: an eight always; otherwise the
    /// suit to follow, or the top card's rank.
    static func fits(_ card: OfflineCard, state: State) -> Bool {
        if card.rank == 8 { return true }
        guard let top = state.discard.last else { return true }
        return card.suit == state.suit || card.rank == top.rank
    }

    /// Someone still at the table has reached the target, or the hands have
    /// run out. A player who left piles up `absentPenalty` every hand; their
    /// total must not cut the game short for the people still playing.
    static func decided(_ state: State) -> Bool {
        state.hand >= maxHands || activeIds(state).contains { (state.scores[$0] ?? 0) >= targetScore }
    }

    /// The lowest totals among players still here (everyone, if all left).
    static func champions(_ state: State) -> [String] {
        let present = state.players.map(\.id).filter { !state.away.contains($0) }
        let pool = present.isEmpty ? state.players.map(\.id) : present
        guard let best = pool.compactMap({ state.scores[$0] }).min() else { return [] }
        return pool.filter { state.scores[$0] == best }
    }

    // MARK: - Helpers

    private static func activeIds(_ state: State) -> [String] {
        state.players.map(\.id).filter { !state.away.contains($0) }
    }

    /// A new hand: fresh deck, deal, turn up a starter. The deal and the first
    /// turn move one seat round the table each hand.
    private static func deal(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        state.hand += 1
        state.phase = .playing
        state.handWinner = nil
        state.handPenalty = [:]
        state.lastMove = nil
        state.idleTurns = 0
        var deck = OfflineCard.shuffledDeck(&rng)
        let active = activeIds(state)
        let size = active.count >= 4 ? 5 : 7
        let dealt = OfflineCard.deal(size, to: active.count, from: &deck)
        state.hands = [:]
        for player in state.players { state.hands[player.id] = [] }
        for (index, id) in active.enumerated() { state.hands[id] = dealt[index] }
        // The starter is never an eight: an eight goes back into the middle of the stock.
        var starter = deck.removeLast()
        while starter.rank == 8 {
            deck.insert(starter, at: rng.int(below: deck.count + 1))
            starter = deck.removeLast()
        }
        state.discard = [starter]
        state.suit = starter.suit
        state.stock = deck
        // First turn: the seat after this hand's dealer, skipping anyone away.
        let count = state.players.count
        var seat = (state.hand - 1) % count
        for _ in 0..<count where state.away.contains(state.players[seat].id) {
            seat = (seat + 1) % count
        }
        state.turn = seat
        beginTurn(&state, now: now)
    }

    private static func beginTurn(_ state: inout State, now: Double) {
        state.turnNumber += 1
        state.turnEndsAt = now + turnSeconds
        state.drawn = nil
        state.hasDrawn = false
    }

    /// Hand the turn to the next player still here.
    private static func nextTurn(_ state: inout State, now: Double) {
        let count = state.players.count
        var seat = state.turn
        for _ in 0..<count {
            seat = (seat + 1) % count
            if !state.away.contains(state.players[seat].id) { break }
        }
        state.turn = seat
        beginTurn(&state, now: now)
    }

    /// A turn ended without a card played. If nobody can draw and nobody has
    /// played for a whole round of the table, the hand is blocked.
    private static func finishIdleTurn(_ state: inout State, drewSomething: Bool, now: Double) {
        if drewSomething || canDraw(state) {
            state.idleTurns = 0
        } else {
            state.idleTurns += 1
        }
        if state.idleTurns >= activeIds(state).count {
            endHand(&state, winner: nil, now: now)
        } else {
            nextTurn(&state, now: now)
        }
    }

    /// Whether a card could be drawn: the stock, or a pile to reshuffle into it.
    private static func canDraw(_ state: State) -> Bool {
        !state.stock.isEmpty || state.discard.count > 1
    }

    /// An empty stock takes the pile under the top card, shuffled.
    private static func refillStock(_ state: inout State, rng: inout OfflineRNG) {
        guard state.stock.isEmpty, state.discard.count > 1 else { return }
        let top = state.discard.removeLast()
        var cards = state.discard
        rng.shuffle(&cards)
        state.stock = cards
        state.discard = [top]
    }

    /// Score the hand: everyone but the winner pays for their cards; a player
    /// who has left pays `absentPenalty`.
    private static func endHand(_ state: inout State, winner: String?, now: Double) {
        state.handWinner = winner
        if let winner { state.handsWon[winner, default: 0] += 1 }
        for player in state.players {
            let points: Int
            if state.away.contains(player.id) {
                points = absentPenalty
            } else if player.id == winner {
                // Usually an empty hand; when the others all left, the one
                // still here takes the hand without paying for its cards.
                points = 0
            } else {
                points = penalty(state.hands[player.id] ?? [])
            }
            state.handPenalty[player.id] = points
            state.scores[player.id, default: 0] += points
        }
        state.phase = .handOver
        state.nextHandAt = now + resultPause
        state.drawn = nil
        state.hasDrawn = false
    }

    private static func mismatchReason(_ state: State) -> String {
        guard let top = state.discard.last else { return "That card doesn't fit." }
        if top.rank == 8 {
            return "Follow \(state.suit.name), or play an eight."
        }
        return "Follow \(state.suit.name) or play \(rankWord(top.rank)) — or an eight."
    }

    /// "an ace", "a queen", "a 7" — for the refusal sentence.
    private static func rankWord(_ rank: Int) -> String {
        switch rank {
        case 1: return "an ace"
        case 11: return "a jack"
        case 12: return "a queen"
        case 13: return "a king"
        default: return "a \(rank)"
        }
    }
}
