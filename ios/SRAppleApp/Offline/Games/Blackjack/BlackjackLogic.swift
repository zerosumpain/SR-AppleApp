import Foundation

/// Blackjack: everyone at the table against a dealer the host's rules play.
///
/// Each player starts with 100 chips. A round opens with a betting window:
/// stake 5 to 25 chips, or let the timer run out and sit the round out. Then
/// two cards each and two for the dealer, one face down. In seat order each
/// player hits, stands, doubles (one more card for twice the stake) or splits
/// a pair into two hands. The dealer turns the hole card over and draws to 16,
/// standing on every 17, soft or hard. A two-card 21 pays 3 to 2 (rounded down
/// to whole chips), a win pays even money, a tie gives the stake back.
///
/// The cards come from a six-deck shoe, reshuffled before the deal once three
/// quarters of it has gone. After eight rounds — or as soon as nobody can
/// cover the minimum bet — the most chips wins.
///
/// Player cards are dealt face up, as at a casino table, so they are public.
/// The one secret is the dealer's hole card (and the order of the shoe): no
/// view carries it until the dealer's turn turns it over.
enum BlackjackRules: OfflineGameRules {
    static let startingChips = 100
    static let minBet = 5
    static let maxBet = 25
    static let maxRounds = 8
    static let decks = 6
    /// Reshuffle before a deal once this share of the shoe has been dealt.
    static let penetration = 0.75
    /// How long the betting window stays open, seconds.
    static let bettingTime: Double = 15
    /// How long one hand's decision may take before it stands by itself.
    static let turnTime: Double = 20
    /// The pause between the dealer's cards, so everyone can watch them land.
    static let dealerStep: Double = 0.8
    /// How long a round's payouts stay up before the next betting window.
    static let resultPause: Double = 5

    static let info = OfflineGameInfo(
        id: "blackjack",
        title: "Blackjack",
        blurb: "Beat the dealer to 21 without going over, and finish with the most chips.",
        category: .card,
        minPlayers: 1,
        maxPlayers: 5,
        symbol: "suit.spade.fill",
        howToPlay: [
            "Everyone starts with \(startingChips) chips and bets \(minBet)–\(maxBet) a round.",
            "Get closer to 21 than the dealer without going over. Picture cards count 10, aces 1 or 11.",
            "Hit for a card, stand to stop, double for one card at twice the bet, split a pair into two hands.",
            "The dealer draws to 16 and stands on every 17.",
            "A two-card 21 pays 3 to 2; a win pays even money; a tie gives your bet back.",
            "After \(maxRounds) rounds, the most chips wins."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// Bets are open until `bettingEndsAt`.
        case betting
        /// Players act in seat order; `turnEndsAt` stands the current hand.
        case playing
        /// The hole card is up and the dealer draws at `dealerNextAt`.
        case dealer
        /// Payouts are on screen until `nextRoundAt`.
        case settled
        /// The match is decided.
        case over
    }

    /// How one hand ended against the dealer.
    enum Outcome: String, Codable, Equatable {
        /// A two-card 21 that the dealer did not match: paid 3 to 2.
        case blackjack
        case win
        case push
        case lose
        /// Went over 21.
        case bust
    }

    /// One hand on the table. Player cards are face up, so a hand is public.
    struct Hand: Codable, Equatable {
        var cards: [OfflineCard]
        /// The stake on this hand, already taken from the player's chips.
        var bet: Int
        var doubled = false
        /// One of the two hands of a split (a 21 there is not a blackjack).
        var fromSplit = false
        /// No more cards: stood, doubled, busted, 21, or ran out of time.
        var done = false
        var outcome: Outcome?
        /// Chips this hand handed back at the settle, stake included.
        var returned: Int?

        var total: Int { BlackjackRules.total(cards) }
        var soft: Bool { BlackjackRules.isSoft(cards) }
        var isBlackjack: Bool { !fromSplit && BlackjackRules.isBlackjack(cards) }
        var busted: Bool { total > 21 }
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left. They are not waited for: no bet in
        /// the window, and their hands stand when their turn comes.
        var away: [String] = []
        /// The shoe; cards are drawn off the END.
        var shoe: [OfflineCard] = []
        /// The shoe was shuffled afresh before this round's deal.
        var reshuffled = false
        /// Chips in front of each player, not counting what is on the table.
        var chips: [String: Int] = [:]
        var round = 0
        var phase: Phase = .betting
        var bettingEndsAt: Double = 0
        /// This round's stakes, by player id, before the deal.
        var bets: [String: Int] = [:]
        /// Each player's hands this round (two after a split).
        var hands: [String: [Hand]] = [:]
        /// Who plays this round, in seat order.
        var order: [String] = []
        /// Whose turn it is: an index into `order`, and which of their hands.
        var turnSeat = 0
        var turnHand = 0
        /// Counts every decision, so a doubled tap or a late answer is refused.
        var move = 0
        var turnEndsAt: Double = 0
        /// The dealer's cards; index 1 is the hole card.
        var dealer: [OfflineCard] = []
        var holeShown = false
        var dealerNextAt: Double = 0
        var nextRoundAt: Double = 0
        /// Each player's net win (or loss) over the round just settled.
        var lastNet: [String: Int] = [:]
        /// Hands that stood because the timer ran out, this match.
        var timeouts: [String: Int] = [:]
    }

    enum Action: Codable, Equatable {
        /// Stake `amount` chips on round `round`.
        case bet(round: Int, amount: Int)
        /// Take a card. `move` is the view's `move`, so a stale tap is refused.
        case hit(move: Int)
        case stand(move: Int)
        /// Double the stake, take exactly one card, and stop.
        case double(move: Int)
        /// Split a pair into two hands, each with the original stake.
        case split(move: Int)
    }

    // MARK: - What a player sees

    struct Seat: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let chips: Int
        /// The bet placed in the window (nil until placed, or when sitting out).
        let bet: Int?
        let hands: [Hand]
        let away: Bool
        /// Cannot cover the minimum bet any more.
        let broke: Bool
        /// The round just settled: chips won (positive) or lost (negative).
        let net: Int?
    }

    struct PlayerView: Codable, Equatable {
        let round: Int
        let maxRounds: Int
        let phase: Phase
        let minBet: Int
        let maxBet: Int
        let bettingEndsAt: Double
        let turnEndsAt: Double
        let nextRoundAt: Double
        let seats: [Seat]
        /// The dealer's cards face up; while the hole card is down it is left
        /// out here and counted in `dealerHidden`.
        let dealerCards: [OfflineCard]
        let dealerHidden: Int
        /// The total of the dealer's face-up cards.
        let dealerTotal: Int
        let turnPlayer: String?
        let turnHand: Int
        let move: Int
        let shoeLeft: Int
        let reshuffled: Bool
        /// What I may do now (all false when it is not my turn).
        let canHit: Bool
        let canStand: Bool
        let canDouble: Bool
        let canSplit: Bool
        /// The most I may bet now (0 when I cannot bet).
        let myMaxBet: Int
        let champions: [String]
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var state = State(players: players)
        for player in players { state.chips[player.id] = startingChips }
        state.shoe = OfflineCard.shuffledDeck(&rng, decks: decks)
        beginRound(&state, now: now)
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard state.players.contains(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not at this table.")
        }
        guard !state.away.contains(playerId) else { throw OfflineRefusal("You have left this table.") }

        switch action {
        case .bet(let round, let amount):
            guard state.phase == .betting else { throw OfflineRefusal("Betting is closed for this round.") }
            guard round == state.round else { throw OfflineRefusal("That bet was for another round.") }
            guard state.bets[playerId] == nil else { throw OfflineRefusal("You have already bet this round.") }
            let chips = state.chips[playerId] ?? 0
            guard chips >= minBet else { throw OfflineRefusal("You don't have enough chips to bet.") }
            guard amount >= minBet, amount <= maxBet else {
                throw OfflineRefusal("Bets are \(minBet) to \(maxBet) chips.")
            }
            guard amount <= chips else { throw OfflineRefusal("You only have \(chips) chips.") }
            state.bets[playerId] = amount
            state.chips[playerId] = chips - amount
            if everyoneHasBet(state) { deal(&state, now: now, rng: &rng) }

        case .hit(let move), .stand(let move), .double(let move), .split(let move):
            guard state.phase == .playing else { throw OfflineRefusal("Nobody is playing a hand right now.") }
            guard let turn = turnPlayer(state) else { throw OfflineRefusal("Nobody is playing a hand right now.") }
            guard turn == playerId else { throw OfflineRefusal("It's \(name(of: turn, in: state))'s turn.") }
            guard move == state.move else { throw OfflineRefusal("The table has moved on since then.") }
            guard var hands = state.hands[playerId], state.turnHand < hands.count else {
                throw OfflineRefusal("You have no hand to play.")
            }
            var hand = hands[state.turnHand]
            guard !hand.done else { throw OfflineRefusal("That hand is finished.") }

            switch action {
            case .hit:
                hand.cards.append(draw(&state, rng: &rng))
                if hand.total >= 21 { hand.done = true }
                hands[state.turnHand] = hand
            case .stand:
                hand.done = true
                hands[state.turnHand] = hand
            case .double:
                guard hand.cards.count == 2 else { throw OfflineRefusal("You can only double on your first two cards.") }
                let chips = state.chips[playerId] ?? 0
                guard chips >= hand.bet else { throw OfflineRefusal("You need \(hand.bet) more chips to double.") }
                state.chips[playerId] = chips - hand.bet
                hand.bet *= 2
                hand.doubled = true
                hand.cards.append(draw(&state, rng: &rng))
                hand.done = true
                hands[state.turnHand] = hand
            case .split:
                guard canSplit(hand, handCount: hands.count) else {
                    throw OfflineRefusal(hands.count > 1 ? "You can only split once." : "You can only split a pair.")
                }
                let chips = state.chips[playerId] ?? 0
                guard chips >= hand.bet else { throw OfflineRefusal("You need \(hand.bet) more chips to split.") }
                state.chips[playerId] = chips - hand.bet
                var first = Hand(cards: [hand.cards[0]], bet: hand.bet, fromSplit: true)
                var second = Hand(cards: [hand.cards[1]], bet: hand.bet, fromSplit: true)
                first.cards.append(draw(&state, rng: &rng))
                second.cards.append(draw(&state, rng: &rng))
                // Split aces take one card each and stop, as at most tables.
                let aces = hand.cards[0].rank == 1
                first.done = aces || first.total >= 21
                second.done = aces || second.total >= 21
                hands = [first, second]
            case .bet:
                break
            }
            state.hands[playerId] = hands
            state.move += 1
            state.turnEndsAt = now + turnTime
            advance(&state, now: now, rng: &rng)
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .betting:
            if now >= state.bettingEndsAt || everyoneHasBet(state) { deal(&state, now: now, rng: &rng) }
        case .playing:
            guard now >= state.turnEndsAt, let turn = turnPlayer(state) else { return }
            // Out of time: the hand stands as it is.
            if var hands = state.hands[turn], state.turnHand < hands.count {
                hands[state.turnHand].done = true
                state.hands[turn] = hands
                state.timeouts[turn, default: 0] += 1
            }
            state.move += 1
            state.turnEndsAt = now + turnTime
            advance(&state, now: now, rng: &rng)
        case .dealer:
            guard now >= state.dealerNextAt else { return }
            if dealerDraws(state) {
                let next = draw(&state, rng: &rng)
                state.dealer.append(next)
                state.dealerNextAt = now + dealerStep
            } else {
                settle(&state, now: now)
            }
        case .settled:
            guard now >= state.nextRoundAt else { return }
            if state.round >= maxRounds || !anyoneCanBet(state) {
                state.phase = .over
            } else {
                beginRound(&state, now: now)
            }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        switch state.phase {
        case .betting:
            if everyoneHasBet(state) { deal(&state, now: now, rng: &rng) }
        case .playing:
            // Their stake stays on the table; their hands simply stand.
            if var hands = state.hands[playerId] {
                for index in hands.indices { hands[index].done = true }
                state.hands[playerId] = hands
            }
            if turnPlayer(state) == playerId {
                state.move += 1
                state.turnEndsAt = now + turnTime
            }
            advance(&state, now: now, rng: &rng)
        case .dealer, .settled, .over:
            break
        }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let seats = state.players.map { player -> Seat in
            let chips = state.chips[player.id] ?? 0
            return Seat(
                id: player.id, name: player.name, chips: chips,
                bet: state.bets[player.id],
                hands: state.hands[player.id] ?? [],
                away: state.away.contains(player.id),
                broke: worth(of: player.id, in: state) < minBet,
                net: state.phase == .settled || state.phase == .over ? state.lastNet[player.id] : nil
            )
        }
        let visible = state.holeShown ? state.dealer : Array(state.dealer.prefix(1))
        let hidden = state.dealer.count - visible.count

        let turn = turnPlayer(state)
        let mine = playerId != nil && turn == playerId && state.phase == .playing
        var hand: Hand?
        var handCount = 0
        if mine, let id = playerId, let hands = state.hands[id], state.turnHand < hands.count {
            hand = hands[state.turnHand]
            handCount = hands.count
        }
        let myChips = playerId.flatMap { state.chips[$0] } ?? 0
        let live = hand.map { !$0.done } ?? false
        let canDouble = live && hand?.cards.count == 2 && myChips >= (hand?.bet ?? Int.max)
        let canSplitNow = live && hand.map { canSplit($0, handCount: handCount) && myChips >= $0.bet } ?? false

        var myMaxBet = 0
        if let id = playerId, state.phase == .betting, state.bets[id] == nil, !state.away.contains(id),
           state.players.contains(where: { $0.id == id }), myChips >= minBet {
            myMaxBet = min(maxBet, myChips)
        }

        return PlayerView(
            round: state.round, maxRounds: maxRounds, phase: state.phase,
            minBet: minBet, maxBet: maxBet,
            bettingEndsAt: state.bettingEndsAt, turnEndsAt: state.turnEndsAt, nextRoundAt: state.nextRoundAt,
            seats: seats, dealerCards: visible, dealerHidden: hidden, dealerTotal: total(visible),
            turnPlayer: state.phase == .playing ? turn : nil, turnHand: state.turnHand, move: state.move,
            shoeLeft: state.shoe.count, reshuffled: state.reshuffled,
            canHit: live, canStand: live, canDouble: canDouble, canSplit: canSplitNow,
            myMaxBet: myMaxBet,
            champions: state.phase == .over ? champions(state) : []
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    /// Most chips first among the players still at the table. Anyone who
    /// left ranks below all of them: walking out freezes your chips, so
    /// leaving while ahead must not be a way to bank the win.
    static func standings(_ state: State) -> [OfflineStanding] {
        let detail: (OfflinePlayer) -> String? = { player in
            var parts: [String] = []
            let worth = worth(of: player.id, in: state)
            let change = worth - startingChips
            parts.append(change >= 0 ? "+\(change) chips" : "\(change) chips")
            if worth < minBet { parts.append("broke") }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        }
        let present = state.players.filter { !state.away.contains($0.id) }
        let gone = state.players.filter { state.away.contains($0.id) }
        let top = OfflineStanding.ranked(present, score: { worth(of: $0.id, in: state) }, detail: detail)
        let bottom = OfflineStanding.ranked(gone, score: { worth(of: $0.id, in: state) }, detail: detail)
            .map { OfflineStanding(playerId: $0.playerId, name: $0.name, rank: $0.rank + present.count,
                                   score: $0.score, detail: $0.detail) }
        return top + bottom
    }

    // MARK: - Counting cards

    /// A card's blackjack value with the ace as 1.
    static func value(_ card: OfflineCard) -> Int { min(card.rank, 10) }

    /// The best total: an ace counts 11 when that does not bust the hand.
    static func total(_ cards: [OfflineCard]) -> Int {
        let hard = cards.reduce(0) { $0 + value($1) }
        let hasAce = cards.contains { $0.rank == 1 }
        return hasAce && hard + 10 <= 21 ? hard + 10 : hard
    }

    /// An ace is counting as 11.
    static func isSoft(_ cards: [OfflineCard]) -> Bool {
        let hard = cards.reduce(0) { $0 + value($1) }
        return cards.contains { $0.rank == 1 } && hard + 10 <= 21
    }

    static func isBlackjack(_ cards: [OfflineCard]) -> Bool {
        cards.count == 2 && total(cards) == 21
    }

    /// A pair of the same rank, on its first two cards, not already split.
    static func canSplit(_ hand: Hand, handCount: Int) -> Bool {
        handCount == 1 && !hand.done && hand.cards.count == 2 && hand.cards[0].rank == hand.cards[1].rank
    }

    // MARK: - Helpers

    private static func name(of id: String, in state: State) -> String {
        state.players.first { $0.id == id }?.name ?? "Someone"
    }

    /// Chips in front plus chips on the table this round.
    static func worth(of id: String, in state: State) -> Int {
        let chips = state.chips[id] ?? 0
        switch state.phase {
        case .betting:
            return chips + (state.bets[id] ?? 0)
        case .playing, .dealer:
            return chips + (state.hands[id] ?? []).reduce(0) { $0 + $1.bet }
        case .settled, .over:
            return chips
        }
    }

    private static func beginRound(_ state: inout State, now: Double) {
        state.round += 1
        state.phase = .betting
        state.bettingEndsAt = now + bettingTime
        state.bets = [:]
        state.hands = [:]
        state.order = []
        state.turnSeat = 0
        state.turnHand = 0
        state.dealer = []
        state.holeShown = false
        state.lastNet = [:]
        state.reshuffled = false
    }

    /// Everyone here who can bet has bet.
    private static func everyoneHasBet(_ state: State) -> Bool {
        let eligible = state.players.filter { !state.away.contains($0.id) && (state.chips[$0.id] ?? 0) >= minBet }
        let bettors = state.players.filter { state.bets[$0.id] != nil }
        guard !bettors.isEmpty || !eligible.isEmpty else { return true }
        return eligible.allSatisfy { state.bets[$0.id] != nil }
    }

    /// Someone still at the table can cover the minimum bet.
    private static func anyoneCanBet(_ state: State) -> Bool {
        state.players.contains { !state.away.contains($0.id) && (state.chips[$0.id] ?? 0) >= minBet }
    }

    /// One card off the shoe; a fresh shoe if it has somehow run dry.
    private static func draw(_ state: inout State, rng: inout OfflineRNG) -> OfflineCard {
        if state.shoe.isEmpty { state.shoe = OfflineCard.shuffledDeck(&rng, decks: decks) }
        return state.shoe.removeLast()
    }

    /// Close betting and deal: two cards to each bettor and to the dealer.
    private static func deal(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        let shoeSize = decks * 52
        if Double(state.shoe.count) <= Double(shoeSize) * (1 - penetration) {
            state.shoe = OfflineCard.shuffledDeck(&rng, decks: decks)
            state.reshuffled = true
        }
        state.order = state.players.map(\.id).filter { state.bets[$0] != nil }
        state.turnSeat = 0
        state.turnHand = 0
        state.move += 1
        guard !state.order.isEmpty else {
            // Nobody bet: the round passes without a deal.
            state.phase = .settled
            state.nextRoundAt = now + resultPause
            return
        }
        for id in state.order { state.hands[id] = [Hand(cards: [], bet: state.bets[id] ?? minBet)] }
        for _ in 0..<2 {
            for id in state.order {
                let next = draw(&state, rng: &rng)
                state.hands[id]?[0].cards.append(next)
            }
            let next = draw(&state, rng: &rng)
            state.dealer.append(next)
        }
        for id in state.order {
            if let hand = state.hands[id]?[0], hand.total >= 21 || state.away.contains(id) {
                state.hands[id]?[0].done = true
            }
        }
        // The dealer peeks under an ace or a ten: a dealer blackjack ends the
        // round before anybody doubles into it.
        if isBlackjack(state.dealer) {
            state.holeShown = true
            settle(&state, now: now)
            return
        }
        state.phase = .playing
        state.turnEndsAt = now + turnTime
        advance(&state, now: now, rng: &rng)
    }

    /// The player whose turn it is, while players act.
    private static func turnPlayer(_ state: State) -> String? {
        guard state.phase == .playing, state.turnSeat < state.order.count else { return nil }
        return state.order[state.turnSeat]
    }

    /// Move the turn to the next unfinished hand (standing those of players
    /// who have left), or hand over to the dealer when every hand is done.
    private static func advance(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.phase == .playing else { return }
        let before = (state.turnSeat, state.turnHand)
        while state.turnSeat < state.order.count {
            let id = state.order[state.turnSeat]
            var hands = state.hands[id] ?? []
            if state.away.contains(id) {
                for index in hands.indices { hands[index].done = true }
                state.hands[id] = hands
            }
            if state.turnHand < hands.count {
                if !hands[state.turnHand].done { break }
                state.turnHand += 1
            } else {
                state.turnSeat += 1
                state.turnHand = 0
            }
        }
        if (state.turnSeat, state.turnHand) != before { state.turnEndsAt = now + turnTime }
        guard state.turnSeat >= state.order.count else { return }
        state.phase = .dealer
        state.holeShown = true
        state.dealerNextAt = now + dealerStep
    }

    /// The dealer keeps drawing while anyone has a hand still standing that
    /// is not already a blackjack — and only while under 17.
    private static func dealerDraws(_ state: State) -> Bool {
        let contest = state.order.contains { id in
            (state.hands[id] ?? []).contains { !$0.busted && !$0.isBlackjack }
        }
        return contest && total(state.dealer) <= 16
    }

    /// Pay every hand against the dealer's final total.
    private static func settle(_ state: inout State, now: Double) {
        state.holeShown = true
        let dealerTotal = total(state.dealer)
        let dealerBlackjack = isBlackjack(state.dealer)
        for id in state.order {
            var hands = state.hands[id] ?? []
            var net = 0
            for index in hands.indices {
                var hand = hands[index]
                hand.done = true
                let outcome: Outcome
                let back: Int
                if hand.busted {
                    outcome = .bust; back = 0
                } else if hand.isBlackjack {
                    if dealerBlackjack { outcome = .push; back = hand.bet } else { outcome = .blackjack; back = hand.bet + hand.bet * 3 / 2 }
                } else if dealerBlackjack {
                    outcome = .lose; back = 0
                } else if dealerTotal > 21 || hand.total > dealerTotal {
                    outcome = .win; back = hand.bet * 2
                } else if hand.total == dealerTotal {
                    outcome = .push; back = hand.bet
                } else {
                    outcome = .lose; back = 0
                }
                hand.outcome = outcome
                hand.returned = back
                net += back - hand.bet
                state.chips[id, default: 0] += back
                hands[index] = hand
            }
            state.hands[id] = hands
            state.lastNet[id] = net
        }
        state.phase = .settled
        state.nextRoundAt = now + resultPause
    }

    /// The most chips among the players still here (several on a tie);
    /// everyone, if all of them left.
    static func champions(_ state: State) -> [String] {
        let present = state.players.map(\.id).filter { !state.away.contains($0) }
        let pool = present.isEmpty ? state.players.map(\.id) : present
        let top = pool.map { worth(of: $0, in: state) }.max() ?? 0
        return pool.filter { worth(of: $0, in: state) == top }
    }
}
