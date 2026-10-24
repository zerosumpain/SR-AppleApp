import Foundation

/// Cheat (also called I Doubt It, or a rude name): the bluffing card game for
/// three to five phones.
///
/// The whole deck is dealt. Players take turns laying one to four cards face
/// down and saying they are the rank whose turn it is — aces first, then twos,
/// threes and so on up to kings, then round to aces again. Nobody has to tell
/// the truth: the cards stay face down and only the claim ("three sevens") is
/// public. After every play there is a short window in which anyone else may
/// shout "Cheat!". The first call turns the cards over: if any of them is not
/// the claimed rank the player who lied picks up the whole pile; if they were
/// all honest the caller picks it up instead. The first player to empty their
/// hand — and survive the window after that last play — wins.
///
/// Like every offline game, the host phone holds the only real state, and
/// each player is sent just their own hand plus everybody's card counts. The
/// cards in the pile, and the cards of the last play, are never sent to
/// anyone until a call turns the last play over.
enum CheatRules: OfflineGameRules {
    /// The most cards one play may claim — there are only four of a rank.
    static let maxCardsPerPlay = 4
    /// How long a player has to make a play before the host plays for them.
    static let turnSeconds: Double = 45
    /// How long everyone else has to call "Cheat!" after a play.
    static let challengeSeconds: Double = 5
    /// How long a call's turned-over cards stay on screen.
    static let revealSeconds: Double = 4
    /// How long "Ann went out" stays up before the table of standings.
    static let wonSeconds: Double = 3
    /// A safety net: after this many plays with nobody out, the fewest cards wins.
    static let maxPlays = 400

    static let info = OfflineGameInfo(
        id: "cheat",
        title: "Cheat",
        blurb: "Play cards face down, claim they are the right rank, and call out the liars.",
        category: .card,
        minPlayers: 3,
        maxPlayers: 5,
        symbol: "theatermasks.fill",
        howToPlay: [
            "The whole deck is dealt out.",
            "On your turn lay one to four cards face down and claim they are the rank shown — aces, then twos, up to kings and round again.",
            "You may lie. Only the claim and the number of cards are public.",
            "After each play anyone else has \(Int(challengeSeconds)) seconds to call Cheat! — the first call turns the cards over.",
            "Caught lying: you pick up the pile. Called wrongly: the caller picks it up.",
            "First to empty their hand, and survive the call after it, wins."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// `turnPlayer` is choosing cards to lay; the host plays for them at `turnEndsAt`.
        case play
        /// The last play is face down; anyone else may call until `challengeEndsAt`.
        case challenge
        /// A call has turned the last play over; the table carries on at `revealUntil`.
        case reveal
        /// Someone has gone out; standings follow at `wonUntil`.
        case won
        /// The match is decided.
        case over
    }

    /// A play as everyone sees it: who, how many, and what they said they were.
    struct Play: Codable, Equatable {
        let playerId: String
        let count: Int
        /// The rank claimed, 1 (ace) … 13 (king).
        let rank: Int
        /// The play's turn number; a call names it so a late call cannot hit the next play.
        let turn: Int
        /// The host played for them because their time ran out.
        let timedOut: Bool
    }

    /// The result of a call: the turned-over cards, and who picked up the pile.
    struct Reveal: Codable, Equatable {
        let callerId: String
        let playerId: String
        /// The cards of the play that was called — public once called.
        let cards: [OfflineCard]
        let rank: Int
        /// Every card was the claimed rank.
        let truthful: Bool
        /// Who took the pile (the liar, or the wrong caller).
        let pickedUpBy: String
        /// How many cards they took.
        let pileSize: Int
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left; their turns are skipped and their hands frozen.
        var away: [String] = []
        /// Everyone's hand. Secret: a view shows each player only their own.
        var hands: [String: [OfflineCard]] = [:]
        /// The face-down pile. Secret: only its size is ever shown.
        var pile: [OfflineCard] = []
        var phase: Phase = .play
        /// Counts plays: the current turn while choosing, the last play's while it can be called.
        var turn = 1
        /// The rank the current (or last) play must claim, 1 … 13.
        var rank = 1
        var turnPlayer: String
        var turnEndsAt: Double = 0
        var challengeEndsAt: Double = 0
        var revealUntil: Double = 0
        var wonUntil: Double = 0
        var lastPlay: Play?
        /// The real cards of `lastPlay`. Secret until called.
        var lastCards: [OfflineCard] = []
        /// Players who let the last play stand; when all have, the window shuts early.
        var passed: [String] = []
        var reveal: Reveal?
        var winner: String?
        /// Bookkeeping for the table afterwards: calls that caught a lie,
        /// and lies that were caught.
        var callsRight: [String: Int] = [:]
        var lies: [String: Int] = [:]
    }

    enum Action: Codable, Equatable {
        /// Lay `cards` face down as the current rank. `turn` must be the current turn.
        case play(turn: Int, cards: [OfflineCard])
        /// Call "Cheat!" on the play of `turn`.
        case call(turn: Int)
        /// Let the play of `turn` stand.
        case pass(turn: Int)
        /// A player marked away whose phone has come back takes their seat again.
        case back
    }

    // MARK: - What a player sees

    /// One player at the table, as everyone may see them.
    struct Seat: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let cards: Int
        let away: Bool
        /// Has let the last play stand.
        let passed: Bool
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let turn: Int
        /// The rank to claim now (or that the last play claimed, while it can be called).
        let rank: Int
        let turnPlayer: String
        let turnEndsAt: Double
        let challengeEndsAt: Double
        let revealUntil: Double
        let wonUntil: Double
        let seats: [Seat]
        let pileCount: Int
        let lastPlay: Play?
        /// The last call's turned-over cards — public once called.
        let reveal: Reveal?
        /// My hand, sorted A … K. Empty for a spectator.
        let myCards: [OfflineCard]
        /// I may call Cheat! on the last play now.
        let canCall: Bool
        let winner: String?
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        let deck = OfflineCard.shuffledDeck(&rng)
        let first = players.isEmpty ? "" : players[rng.int(below: players.count)].id
        var state = State(players: players, turnPlayer: first)
        var hands: [[OfflineCard]] = Array(repeating: [], count: players.count)
        if !players.isEmpty {
            for (index, card) in deck.enumerated() { hands[index % players.count].append(card) }
        }
        for (index, player) in players.enumerated() {
            state.hands[player.id] = sorted(hands[index])
        }
        state.turnEndsAt = now + turnSeconds
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard state.players.contains(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not in this game.")
        }
        guard state.phase != .won, state.phase != .over else { throw OfflineRefusal("The game is over.") }

        if case .back = action {
            guard let index = state.away.firstIndex(of: playerId) else {
                throw OfflineRefusal("You are already at the table.")
            }
            state.away.remove(at: index)
            return
        }
        guard !state.away.contains(playerId) else {
            throw OfflineRefusal("You left this game — rejoin to play.")
        }

        switch action {
        case .play(let turn, let cards):
            guard state.phase == .play else {
                throw OfflineRefusal("Wait — the last play can still be called.")
            }
            guard turn == state.turn else { throw OfflineRefusal("That play was for an earlier turn.") }
            guard state.turnPlayer == playerId else {
                throw OfflineRefusal("It's \(name(of: state.turnPlayer, in: state))'s turn.")
            }
            guard !cards.isEmpty else { throw OfflineRefusal("Pick at least one card.") }
            guard cards.count <= maxCardsPerPlay else {
                throw OfflineRefusal("You can play at most \(maxCardsPerPlay) cards.")
            }
            guard Set(cards.map(\.id)).count == cards.count else {
                throw OfflineRefusal("You picked the same card twice.")
            }
            let hand = state.hands[playerId] ?? []
            guard cards.allSatisfy({ card in hand.contains(card) }) else {
                throw OfflineRefusal("You don't have that card.")
            }
            lay(cards, by: playerId, timedOut: false, in: &state, now: now)

        case .call(let turn):
            guard let last = state.lastPlay, turn == last.turn else {
                throw OfflineRefusal("That play has already been settled.")
            }
            if state.phase == .reveal, let reveal = state.reveal {
                throw OfflineRefusal("\(name(of: reveal.callerId, in: state)) called it first.")
            }
            // The window is judged on the host's clock, even if its tick has
            // not closed it yet.
            guard state.phase == .challenge, now <= state.challengeEndsAt else {
                throw OfflineRefusal("Too late to call that one.")
            }
            guard last.playerId != playerId else { throw OfflineRefusal("You can't call your own play.") }
            guard !state.passed.contains(playerId) else { throw OfflineRefusal("You already let that one go.") }
            settleCall(by: playerId, in: &state, now: now)

        case .pass(let turn):
            guard let last = state.lastPlay, turn == last.turn, state.phase == .challenge else {
                throw OfflineRefusal("That play has already been settled.")
            }
            guard last.playerId != playerId else { throw OfflineRefusal("It's your own play.") }
            guard !state.passed.contains(playerId) else { throw OfflineRefusal("You already let that one go.") }
            state.passed.append(playerId)
            if everyoneHasPassed(state) { closeWindow(&state, now: now) }

        case .back:
            break
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .play:
            guard now >= state.turnEndsAt else { return }
            // Out of time: the host lays one card for them — an honest one
            // when they have it, else their first card (a lie, open to a call).
            let hand = state.hands[state.turnPlayer] ?? []
            guard let card = hand.first(where: { $0.rank == state.rank }) ?? hand.first else {
                advance(&state, from: state.turnPlayer, now: now)
                return
            }
            lay([card], by: state.turnPlayer, timedOut: true, in: &state, now: now)
        case .challenge:
            if now >= state.challengeEndsAt || everyoneHasPassed(state) { closeWindow(&state, now: now) }
        case .reveal:
            guard now >= state.revealUntil else { return }
            if let last = state.lastPlay, (state.hands[last.playerId] ?? []).isEmpty {
                win(last.playerId, in: &state, now: now)
            } else if let last = state.lastPlay {
                nextTurn(&state, after: last.playerId, now: now)
            }
        case .won:
            if now >= state.wonUntil { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        guard state.phase != .won, state.phase != .over else { return }
        if present(state).count < 2 {
            // Nobody left to play against: fewest cards takes it.
            state.phase = .over
            return
        }
        switch state.phase {
        case .play:
            if state.turnPlayer == playerId { advance(&state, from: playerId, now: now) }
        case .challenge:
            if everyoneHasPassed(state) { closeWindow(&state, now: now) }
        case .reveal, .won, .over:
            break
        }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let seats = state.players.map { player in
            Seat(id: player.id, name: player.name, cards: state.hands[player.id]?.count ?? 0,
                 away: state.away.contains(player.id), passed: state.passed.contains(player.id))
        }
        var canCall = false
        if let me = playerId, state.phase == .challenge, let last = state.lastPlay {
            canCall = last.playerId != me && !state.away.contains(me) && !state.passed.contains(me)
                && state.players.contains { $0.id == me }
        }
        return PlayerView(
            phase: state.phase, turn: state.turn, rank: state.rank, turnPlayer: state.turnPlayer,
            turnEndsAt: state.turnEndsAt, challengeEndsAt: state.challengeEndsAt,
            revealUntil: state.revealUntil, wonUntil: state.wonUntil,
            seats: seats, pileCount: state.pile.count, lastPlay: state.lastPlay, reveal: state.reveal,
            myCards: playerId.flatMap { state.hands[$0] } ?? [],
            canCall: canCall, winner: state.winner
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    /// Fewest cards left is best; whoever went out has none and ranks first.
    /// Anyone who left ranks below everyone still at the table: their hand
    /// is frozen, so walking out holding few cards (which can end a
    /// three-player match) must not be a way to win.
    static func standings(_ state: State) -> [OfflineStanding] {
        let present = state.players.filter { !state.away.contains($0.id) || $0.id == state.winner }
        let gone = state.players.filter { state.away.contains($0.id) && $0.id != state.winner }
        let bottom = ranked(gone, in: state)
            .map { OfflineStanding(playerId: $0.playerId, name: $0.name, rank: $0.rank + present.count,
                                   score: $0.score, detail: $0.detail) }
        return ranked(present, in: state) + bottom
    }

    private static func ranked(_ players: [OfflinePlayer], in state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(players, score: { state.hands[$0.id]?.count ?? 0 }, detail: { player in
            var parts: [String] = []
            if player.id == state.winner {
                parts.append("went out")
            } else {
                let count = state.hands[player.id]?.count ?? 0
                parts.append(count == 1 ? "1 card left" : "\(count) cards left")
            }
            let right = state.callsRight[player.id] ?? 0
            if right > 0 { parts.append(right == 1 ? "1 good call" : "\(right) good calls") }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        }, lowerIsBetter: true)
    }

    // MARK: - Helpers

    /// "aces", "twos" … "kings": how a claim is said.
    static func rankName(_ rank: Int, plural: Bool = true) -> String {
        let names = ["ace", "two", "three", "four", "five", "six", "seven",
                     "eight", "nine", "ten", "jack", "queen", "king"]
        guard rank >= 1, rank <= 13 else { return "?" }
        let word = names[rank - 1]
        return plural ? (word == "six" ? "sixes" : word + "s") : word
    }

    /// "A", "2" … "K".
    static func rankText(_ rank: Int) -> String {
        switch rank {
        case 1: return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return "\(rank)"
        }
    }

    /// The players still at the table, in seat order.
    static func present(_ state: State) -> [OfflinePlayer] {
        state.players.filter { !state.away.contains($0.id) }
    }

    private static func name(of id: String, in state: State) -> String {
        state.players.first { $0.id == id }?.name ?? "Someone"
    }

    private static func sorted(_ cards: [OfflineCard]) -> [OfflineCard] {
        OfflineCard.sortedForHand(cards, acesHigh: false)
    }

    /// Lay cards face down as the current rank, and open the window to call it.
    private static func lay(_ cards: [OfflineCard], by playerId: String, timedOut: Bool, in state: inout State, now: Double) {
        var hand = state.hands[playerId] ?? []
        for card in cards {
            if let index = hand.firstIndex(of: card) { hand.remove(at: index) }
        }
        state.hands[playerId] = hand
        state.pile.append(contentsOf: cards)
        state.lastCards = cards
        state.lastPlay = Play(playerId: playerId, count: cards.count, rank: state.rank, turn: state.turn, timedOut: timedOut)
        state.reveal = nil
        state.passed = []
        state.phase = .challenge
        state.challengeEndsAt = now + challengeSeconds
        if everyoneHasPassed(state) { closeWindow(&state, now: now) }
    }

    /// Everyone who may call the last play has let it stand (or nobody can call it).
    private static func everyoneHasPassed(_ state: State) -> Bool {
        guard let last = state.lastPlay else { return true }
        return present(state).allSatisfy { $0.id == last.playerId || state.passed.contains($0.id) }
    }

    /// The first call: turn the last play over and hand the pile to the loser.
    private static func settleCall(by callerId: String, in state: inout State, now: Double) {
        guard let last = state.lastPlay else { return }
        let truthful = state.lastCards.allSatisfy { $0.rank == last.rank }
        let loser = truthful ? callerId : last.playerId
        if !truthful {
            state.lies[last.playerId, default: 0] += 1
            state.callsRight[callerId, default: 0] += 1
        }
        let size = state.pile.count
        state.hands[loser] = sorted((state.hands[loser] ?? []) + state.pile)
        state.pile = []
        state.reveal = Reveal(callerId: callerId, playerId: last.playerId, cards: state.lastCards, rank: last.rank,
                              truthful: truthful, pickedUpBy: loser, pileSize: size)
        state.phase = .reveal
        state.revealUntil = now + revealSeconds
    }

    /// Nobody called (or everyone let it go): the play stands.
    private static func closeWindow(_ state: inout State, now: Double) {
        guard state.phase == .challenge, let last = state.lastPlay else { return }
        if (state.hands[last.playerId] ?? []).isEmpty {
            win(last.playerId, in: &state, now: now)
        } else {
            nextTurn(&state, after: last.playerId, now: now)
        }
    }

    /// The next present player after `playerId` takes a fresh turn, one rank up.
    private static func nextTurn(_ state: inout State, after playerId: String, now: Double) {
        state.turn += 1
        state.rank = state.rank % 13 + 1
        if state.turn > maxPlays {
            state.phase = .over
            return
        }
        advance(&state, from: playerId, now: now)
    }

    /// Hand the current turn to the next present player after `playerId`
    /// (the rank and turn number stay as they are).
    private static func advance(_ state: inout State, from playerId: String, now: Double) {
        let count = state.players.count
        guard count > 0 else { state.phase = .over; return }
        let start = state.players.firstIndex { $0.id == playerId } ?? 0
        for step in 1...count {
            let candidate = state.players[(start + step) % count].id
            if !state.away.contains(candidate) {
                state.turnPlayer = candidate
                state.phase = .play
                state.passed = []
                state.turnEndsAt = now + turnSeconds
                return
            }
        }
        state.phase = .over
    }

    private static func win(_ playerId: String, in state: inout State, now: Double) {
        state.winner = playerId
        state.phase = .won
        state.wonUntil = now + wonSeconds
    }
}
