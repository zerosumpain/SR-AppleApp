import Foundation

/// Knockout Whist: the trick-taking game where every hand is smaller and a
/// blank hand sends you home, for two to five phones round a table.
///
/// The first hand deals seven cards each and turns the next card up: its suit
/// is trumps. The player after the dealer (the host's seat) leads. You must
/// follow the suit that was led if you can; if you cannot, you may play
/// anything, a trump included. The highest trump takes the trick, or, with no
/// trump in it, the highest card of the suit led (aces high). Whoever takes a
/// trick leads the next.
///
/// When a hand's cards are all played, anyone who took no tricks is knocked
/// out. The player who took the most tricks (on a tie, whoever got there
/// first) looks at their new cards, names trumps for the next hand and leads
/// it. Each hand deals one card fewer — seven, six, five … one — so the game
/// can never run past the one-card hand, where the single trick decides it.
/// The last player standing wins.
///
/// The host holds every hand; a player's view carries only their own cards
/// and how many the others hold. Turns have a generous timer: when it runs
/// out the host plays the lowest card that may be played (or names the suit
/// the chooser holds most of), so a phone left face down cannot stall the table.
/// A player whose phone leaves is knocked out on the spot.
enum KnockoutWhistRules: OfflineGameRules {
    /// Cards each in the first hand; every later hand deals one fewer.
    static let firstHandSize = 7
    /// How long one turn may last before the host plays for you.
    static let turnSeconds: Double = 40
    /// How long the trump chooser has to name a suit.
    static let chooseSeconds: Double = 30
    /// How long a finished trick stays on the table before the next lead.
    static let trickPause: Double = 1.8
    /// How long a hand's result (and who was knocked out) stays up.
    static let resultPause: Double = 5

    static let info = OfflineGameInfo(
        id: "knockout-whist",
        title: "Knockout Whist",
        blurb: "Take a trick every hand or you're out; last one standing wins.",
        category: .card,
        minPlayers: 2,
        maxPlayers: 5,
        symbol: "suit.spade.fill",
        howToPlay: [
            "Seven cards each to start; the turned-up card's suit is trumps.",
            "Follow the suit led if you can; otherwise play anything.",
            "Highest trump wins the trick, else the highest card of the suit led.",
            "Take no tricks in a hand and you're knocked out.",
            "Most tricks picks trumps for the next hand and leads it.",
            "Each hand has one card fewer; the last player standing wins."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// The player who took most tricks last hand is naming trumps.
        case choosingTrump
        /// Cards are being played; `turn` is whose go it is.
        case playing
        /// A trick is complete and stays on the table until `pauseUntil`.
        case trickWon
        /// A hand is over; its result shows until `pauseUntil`.
        case handOver
        /// The match is decided.
        case over
    }

    /// One card on the table and who played it.
    struct Played: Codable, Equatable {
        let playerId: String
        let card: OfflineCard
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left (they are knocked out too).
        var away: [String] = []
        /// Knocked out, with the hand they went out in.
        var outInHand: [String: Int] = [:]
        /// The order of knock-outs: players out in the same event share a
        /// number, and a higher number outlasted a lower one.
        var outEvent: [String: Int] = [:]
        var events = 0
        var phase: Phase = .playing
        /// 1-based hand number.
        var hand = 0
        /// Cards dealt to each player this hand.
        var handSize = 0
        /// Every hand, by player id. Secret: each player sees only their own.
        var hands: [String: [OfflineCard]] = [:]
        var trump: OfflineSuit?
        /// The face-up card that set trumps in the first hand.
        var trumpCard: OfflineCard?
        /// Who is naming trumps (`choosingTrump` only).
        var chooser: String?
        /// The trick on the table, in the order played.
        var trick: [Played] = []
        /// Seat index of the player whose turn it is.
        var turn = 0
        /// Counts every turn and choice of the match, so a late action is spotted.
        var turnNumber = 0
        var turnEndsAt: Double = 0
        /// Seat that leads the next trick (the last trick's winner).
        var leader = 0
        /// Who took the trick on the table (`trickWon`), or the hand's last one.
        var trickWinner: String?
        /// Tricks taken this hand, by id.
        var tricks: [String: Int] = [:]
        /// Every trick winner this hand, in order — breaks a tie for "most".
        var trickWinners: [String] = []
        /// Tricks taken over the whole match, for the table afterwards.
        var totalTricks: [String: Int] = [:]
        /// Knocked out at the end of the hand just played (`handOver`).
        var knockedOut: [String] = []
        /// Who names trumps next hand.
        var nextChooser: String?
        /// The last player standing, once decided.
        var champion: String?
        /// When a trick or a hand's result gives way, host clock.
        var pauseUntil: Double = 0
    }

    enum Action: Codable, Equatable {
        /// Name trumps for `hand`.
        case chooseTrump(hand: Int, suit: OfflineSuit)
        /// Play `card` on turn `turn`.
        case play(turn: Int, card: OfflineCard)
    }

    // MARK: - What a player sees

    struct Seat: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        /// How many cards they hold — never which.
        let cards: Int
        /// Tricks taken this hand.
        let tricks: Int
        let out: Bool
        let away: Bool
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let hand: Int
        let handSize: Int
        let seats: [Seat]
        /// My own cards, sorted; empty for a spectator or a player who is out.
        let myCards: [OfflineCard]
        /// Ids of my cards I may play now (empty when it is not my turn).
        let playable: [String]
        let trump: OfflineSuit?
        let trumpCard: OfflineCard?
        let chooser: String?
        let trick: [Played]
        /// The suit of the first card in the trick.
        let ledSuit: OfflineSuit?
        let turnPlayer: String?
        let turnNumber: Int
        let turnEndsAt: Double
        let trickWinner: String?
        let knockedOut: [String]
        let nextChooser: String?
        let champion: String?
        let pauseUntil: Double
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var state = State(players: players)
        for player in players {
            state.tricks[player.id] = 0
            state.totalTricks[player.id] = 0
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
        case .over: throw OfflineRefusal("The game is over.")
        case .handOver: throw OfflineRefusal("This hand is over — the next deal is coming.")
        case .trickWon: throw OfflineRefusal("Wait a moment — the next trick is about to start.")
        case .choosingTrump, .playing: break
        }
        guard state.outInHand[playerId] == nil else {
            throw OfflineRefusal("You've been knocked out — watch the rest.")
        }

        switch action {
        case .chooseTrump(let hand, let suit):
            guard state.phase == .choosingTrump else { throw OfflineRefusal("Trumps are already set for this hand.") }
            guard hand == state.hand else { throw OfflineRefusal("That choice was for an earlier hand.") }
            guard let chooser = state.chooser, chooser == playerId else {
                throw OfflineRefusal("It's \(name(of: state.chooser, in: state))'s choice of trumps.")
            }
            setTrump(&state, suit: suit, now: now)

        case .play(let turn, let card):
            guard state.phase == .playing else {
                throw OfflineRefusal("Wait for \(name(of: state.chooser, in: state)) to choose trumps.")
            }
            guard seat == state.turn else {
                throw OfflineRefusal("It's \(state.players[state.turn].name)'s turn.")
            }
            guard turn == state.turnNumber else { throw OfflineRefusal("That move was for an earlier turn.") }
            let hand = state.hands[playerId] ?? []
            guard hand.contains(card) else { throw OfflineRefusal("You don't have that card.") }
            if let led = ledSuit(state), card.suit != led, hand.contains(where: { $0.suit == led }) {
                throw OfflineRefusal("You have \(led.name), so you must follow suit.")
            }
            play(card, by: playerId, state: &state, now: now)
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .choosingTrump:
            guard now >= state.turnEndsAt, let chooser = state.chooser else { return }
            setTrump(&state, suit: favouriteSuit(state.hands[chooser] ?? []), now: now)
        case .playing:
            guard now >= state.turnEndsAt else { return }
            let id = state.players[state.turn].id
            guard let card = autoCard(state.hands[id] ?? [], state: state) else { return }
            play(card, by: id, state: &state, now: now)
        case .trickWon:
            guard now >= state.pauseUntil else { return }
            state.trick = []
            state.trickWinner = nil
            state.phase = .playing
            state.turn = state.leader
            state.turnNumber += 1
            state.turnEndsAt = now + turnSeconds
        case .handOver:
            guard now >= state.pauseUntil else { return }
            if state.champion != nil {
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
        // A decided match stands, even if the champion's phone leaves during the result.
        guard state.phase != .over, state.champion == nil else { return }
        let wasIn = state.outInHand[playerId] == nil
        state.hands[playerId] = []
        guard wasIn else { return }
        // Leaving knocks you out, in an event of your own.
        state.events += 1
        state.outEvent[playerId] = state.events
        state.outInHand[playerId] = state.phase == .handOver ? state.hand + 1 : state.hand
        state.knockedOut.removeAll { $0 == playerId }

        let active = activeIds(state)
        if active.count <= 1 {
            state.champion = active.first
            state.phase = .over
            return
        }
        switch state.phase {
        case .choosingTrump:
            if state.chooser == playerId {
                state.chooser = nextActiveId(after: seat, state: state)
                state.turnNumber += 1
                state.turnEndsAt = now + chooseSeconds
            }
        case .playing:
            let theirTurn = seat == state.turn
            state.trick.removeAll { $0.playerId == playerId }
            if theirTurn {
                if !state.trick.isEmpty && state.trick.count == active.count {
                    finishTrick(&state, now: now)
                } else {
                    state.turn = nextActiveSeat(after: seat, state: state)
                    state.turnNumber += 1
                    state.turnEndsAt = now + turnSeconds
                }
            }
        case .trickWon:
            if state.leader == seat { state.leader = nextActiveSeat(after: seat, state: state) }
        case .handOver:
            if state.nextChooser == playerId { state.nextChooser = nextActiveId(after: seat, state: state) }
        case .over:
            break
        }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let seats = state.players.map { player -> Seat in
            Seat(id: player.id, name: player.name, cards: state.hands[player.id]?.count ?? 0,
                 tricks: state.tricks[player.id] ?? 0, out: state.outInHand[player.id] != nil,
                 away: state.away.contains(player.id))
        }
        let turnPlayer = state.phase == .playing ? state.players[state.turn].id : nil
        let mine = playerId.flatMap { state.hands[$0] } ?? []
        let playable = turnPlayer != nil && turnPlayer == playerId ? legalCards(mine, state: state).map(\.id) : []
        return PlayerView(
            phase: state.phase, hand: state.hand, handSize: state.handSize, seats: seats,
            myCards: OfflineCard.sortedForHand(mine), playable: playable,
            trump: state.trump, trumpCard: state.trumpCard,
            chooser: state.phase == .choosingTrump ? state.chooser : nil,
            trick: state.trick, ledSuit: ledSuit(state), turnPlayer: turnPlayer,
            turnNumber: state.turnNumber, turnEndsAt: state.turnEndsAt,
            trickWinner: state.trickWinner, knockedOut: state.knockedOut,
            nextChooser: state.phase == .handOver ? state.nextChooser : nil,
            champion: state.champion, pauseUntil: state.pauseUntil
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    /// Ranked by how many players each outlasted: the champion beat everyone,
    /// players knocked out together tie.
    static func standings(_ state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(state.players, score: { outlasted($0.id, state: state) }, detail: { player in
            var parts: [String] = []
            if state.champion == player.id {
                parts.append("last one standing")
            } else if let hand = state.outInHand[player.id] {
                parts.append(state.away.contains(player.id) ? "left in hand \(hand)" : "out in hand \(hand)")
            }
            let taken = state.totalTricks[player.id] ?? 0
            parts.append(taken == 1 ? "1 trick" : "\(taken) tricks")
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Judging

    /// The suit led to the trick on the table, if any card is down.
    static func ledSuit(_ state: State) -> OfflineSuit? {
        state.trick.first?.card.suit
    }

    /// The cards in `hand` that may be played now: the suit led if any are
    /// held, otherwise all of them.
    static func legalCards(_ hand: [OfflineCard], state: State) -> [OfflineCard] {
        guard let led = ledSuit(state) else { return hand }
        let following = hand.filter { $0.suit == led }
        return following.isEmpty ? hand : following
    }

    /// Who takes `trick`: the highest trump, else the highest card of the suit led.
    static func winner(of trick: [Played], trump: OfflineSuit?) -> String? {
        guard let led = trick.first?.card.suit else { return nil }
        var best: Played?
        for played in trick {
            guard let current = best else { best = played; continue }
            if beats(played.card, current.card, led: led, trump: trump) { best = played }
        }
        return best?.playerId
    }

    /// `a` beats `b` in a trick led with `led`.
    static func beats(_ a: OfflineCard, _ b: OfflineCard, led: OfflineSuit, trump: OfflineSuit?) -> Bool {
        let aTrump = a.suit == trump, bTrump = b.suit == trump
        if aTrump != bTrump { return aTrump }
        if aTrump { return a.highRank > b.highRank }
        let aLed = a.suit == led, bLed = b.suit == led
        if aLed != bLed { return aLed }
        return aLed && a.highRank > b.highRank
    }

    /// How many players `id` outlasted.
    static func outlasted(_ id: String, state: State) -> Int {
        let mine = state.outEvent[id] ?? Int.max
        return state.players.filter { other in
            guard other.id != id, let theirs = state.outEvent[other.id] else { return false }
            return theirs < mine
        }.count
    }

    // MARK: - Helpers

    private static func name(of id: String?, in state: State) -> String {
        guard let id else { return "someone" }
        return state.players.first { $0.id == id }?.name ?? "someone"
    }

    /// Still in the game: neither knocked out nor gone.
    private static func activeIds(_ state: State) -> [String] {
        state.players.map(\.id).filter { state.outInHand[$0] == nil && !state.away.contains($0) }
    }

    private static func isActive(_ seat: Int, state: State) -> Bool {
        let id = state.players[seat].id
        return state.outInHand[id] == nil && !state.away.contains(id)
    }

    /// The next seat round the table after `seat` that is still in the game.
    private static func nextActiveSeat(after seat: Int, state: State) -> Int {
        let count = state.players.count
        var next = seat
        for _ in 0..<count {
            next = (next + 1) % count
            if isActive(next, state: state) { return next }
        }
        return seat
    }

    private static func nextActiveId(after seat: Int, state: State) -> String {
        state.players[nextActiveSeat(after: seat, state: state)].id
    }

    /// A new hand: fresh deck, one card fewer than last time, to everyone
    /// still in. The first hand turns up trumps; later ones wait for the chooser.
    private static func deal(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        state.hand += 1
        state.handSize = max(1, firstHandSize + 1 - state.hand)
        state.trick = []
        state.trickWinner = nil
        state.trickWinners = []
        state.knockedOut = []
        state.trumpCard = nil
        state.trump = nil
        state.chooser = nil
        for player in state.players { state.tricks[player.id] = 0 }
        var deck = OfflineCard.shuffledDeck(&rng)
        let active = activeIds(state)
        let dealt = OfflineCard.deal(state.handSize, to: active.count, from: &deck)
        state.hands = [:]
        for player in state.players { state.hands[player.id] = [] }
        for (index, id) in active.enumerated() { state.hands[id] = dealt[index] }
        state.turnNumber += 1

        if state.hand == 1 {
            // The host's seat deals; the next player leads; the next card sets trumps.
            let card = deck.removeLast()
            state.trumpCard = card
            state.trump = card.suit
            state.leader = nextActiveSeat(after: 0, state: state)
            state.turn = state.leader
            state.phase = .playing
            state.turnEndsAt = now + turnSeconds
        } else {
            var chooser = state.nextChooser ?? active[0]
            if !active.contains(chooser), let seat = state.players.firstIndex(where: { $0.id == chooser }) {
                chooser = nextActiveId(after: seat, state: state)
            }
            state.chooser = chooser
            state.phase = .choosingTrump
            state.turnEndsAt = now + chooseSeconds
        }
        state.nextChooser = nil
    }

    /// Trumps are named: the chooser leads the first trick.
    private static func setTrump(_ state: inout State, suit: OfflineSuit, now: Double) {
        state.trump = suit
        if let chooser = state.chooser, let seat = state.players.firstIndex(where: { $0.id == chooser }) {
            state.leader = seat
        }
        state.chooser = nil
        state.turn = state.leader
        state.phase = .playing
        state.turnNumber += 1
        state.turnEndsAt = now + turnSeconds
    }

    /// Put `card` on the trick (already checked legal) and move the turn on.
    private static func play(_ card: OfflineCard, by playerId: String, state: inout State, now: Double) {
        var hand = state.hands[playerId] ?? []
        if let index = hand.firstIndex(of: card) { hand.remove(at: index) }
        state.hands[playerId] = hand
        state.trick.append(Played(playerId: playerId, card: card))
        if state.trick.count >= activeIds(state).count {
            finishTrick(&state, now: now)
        } else {
            state.turn = nextActiveSeat(after: state.turn, state: state)
            state.turnNumber += 1
            state.turnEndsAt = now + turnSeconds
        }
    }

    /// The trick is complete: score it, and either pause before the next
    /// lead or, with no cards left, end the hand.
    private static func finishTrick(_ state: inout State, now: Double) {
        guard let winnerId = winner(of: state.trick, trump: state.trump) else { return }
        state.tricks[winnerId, default: 0] += 1
        state.totalTricks[winnerId, default: 0] += 1
        state.trickWinners.append(winnerId)
        state.trickWinner = winnerId
        if let seat = state.players.firstIndex(where: { $0.id == winnerId }) { state.leader = seat }
        state.turnNumber += 1
        let cardsLeft = activeIds(state).contains { !(state.hands[$0] ?? []).isEmpty }
        if cardsLeft {
            state.phase = .trickWon
            state.pauseUntil = now + trickPause
        } else {
            endHand(&state, now: now)
        }
    }

    /// Knock out everyone who took no tricks; crown the last one standing,
    /// or find who names trumps next.
    private static func endHand(_ state: inout State, now: Double) {
        let active = activeIds(state)
        var blank = active.filter { (state.tricks[$0] ?? 0) == 0 }
        // Only possible when the tricks went to someone who has since left:
        // nobody still playing earned a seat, so nobody loses one.
        if blank.count == active.count { blank = [] }
        if !blank.isEmpty {
            state.events += 1
            for id in blank {
                state.outInHand[id] = state.hand
                state.outEvent[id] = state.events
            }
        }
        state.knockedOut = blank
        let standing = activeIds(state)
        if standing.count <= 1 || state.handSize <= 1 {
            state.champion = mostTricks(state, among: standing)
        } else {
            state.nextChooser = mostTricks(state, among: standing)
        }
        state.phase = .handOver
        state.pauseUntil = now + resultPause
    }

    /// Most tricks this hand among `ids`; a tie goes to whoever reached that
    /// many first.
    private static func mostTricks(_ state: State, among ids: [String]) -> String? {
        let top = ids.map { state.tricks[$0] ?? 0 }.max() ?? 0
        var counts: [String: Int] = [:]
        for id in state.trickWinners {
            counts[id, default: 0] += 1
            if counts[id] == top, ids.contains(id) { return id }
        }
        return ids.first
    }

    /// The suit the chooser holds most of (clubs, diamonds, hearts, spades on a tie).
    private static func favouriteSuit(_ hand: [OfflineCard]) -> OfflineSuit {
        var best = OfflineSuit.clubs
        var bestCount = -1
        for suit in OfflineSuit.allCases {
            let count = hand.filter { $0.suit == suit }.count
            if count > bestCount { best = suit; bestCount = count }
        }
        return best
    }

    /// What the host plays for a player whose time ran out: the lowest legal
    /// card, keeping trumps back where it can.
    private static func autoCard(_ hand: [OfflineCard], state: State) -> OfflineCard? {
        let legal = legalCards(hand, state: state)
        let plain = legal.filter { $0.suit != state.trump }
        let pool = plain.isEmpty ? legal : plain
        return pool.min { a, b in
            a.highRank != b.highRank ? a.highRank < b.highRank : a.suit.rawValue < b.suit.rawValue
        }
    }
}
