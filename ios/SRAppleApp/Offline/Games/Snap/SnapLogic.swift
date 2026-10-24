import Foundation

/// Snap: the nursery card game, for two to five phones.
///
/// The whole deck is dealt face down, one stack each. The host turns the top
/// of each player's stack over onto that player's own face-up pile, one
/// player after another, at a steady beat that quickens as the game goes on.
/// Whenever two of the face-up tops share a rank, the first to tap SNAP wins
/// every pile in the pair, onto the bottom of their stack.
///
/// "First" is judged the Quick Draw way, not by arrival order: each phone
/// times its owner from the display frame that showed the newest card to the
/// touch, and reports the figure. When a turned card makes a pair the host
/// holds the next card back for a short window, collects everyone's reported
/// times, and the lowest takes the piles — so Bluetooth latency never decides
/// a snap.
///
/// Snap when there is no pair (or so quickly nobody could have seen the card)
/// and you pay one card to each other player. A player whose stack runs out
/// turns their own pile over and keeps going; a player with no stack and no
/// pile is out. The last player with cards wins — or, after three minutes,
/// whoever holds the most.
enum SnapRules: OfflineGameRules {
    /// How long a match runs before the most cards wins, seconds.
    static let matchLength: Double = 180
    /// The pause before the first card, seconds.
    static let firstFlipDelay: Double = 2
    /// The beat between cards at the start, seconds.
    static let startInterval: Double = 1.1
    /// The quickest the beat ever gets, seconds.
    static let fastestInterval: Double = 0.6
    /// How much quicker the beat gets with every card, seconds.
    static let quickening: Double = 0.01
    /// After a card makes a pair, how long the host collects snaps before
    /// judging, seconds from the card being turned. Long enough for a
    /// Bluetooth round trip and a slow reaction; a phone that never answers
    /// cannot hold the game up beyond it.
    static let snapWindow: Double = 1.6
    /// How long the result of a snap stays up before the next card.
    static let resultPause: Double = 1.4
    /// How long a false snap's notice stays up.
    static let noticeLength: Double = 2
    /// How long the final result shows before the match ends.
    static let endingPause: Double = 2.5
    /// A reported reaction over this cannot be right.
    static let slowestMs = 60_000

    static let info = OfflineGameInfo(
        id: "snap",
        title: "Snap",
        blurb: "Watch the piles and slap SNAP the moment two cards match.",
        category: .reaction,
        minPlayers: 2,
        maxPlayers: 5,
        symbol: "rectangle.on.rectangle.angled",
        howToPlay: [
            "Everyone gets a face-down stack; the cards turn over one player at a time.",
            "When two face-up cards share a rank, tap SNAP — the quickest wins both piles.",
            "Snap when there is no pair and you pay a card to every other player.",
            "Run out of stack and your own pile turns over; run out of both and you are out.",
            "Last player with cards wins, or the most cards after three minutes."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// Cards are turning (or a pair's snaps are being collected).
        case playing
        /// The match is decided; the result shows until `endingUntil`.
        case ending
        /// Finished.
        case over
    }

    /// One player's cards. Index 0 is the bottom of each; the last element is
    /// the top (the next card to turn, the face-up card on show).
    struct Seat: Codable, Equatable {
        var stack: [OfflineCard] = []
        var pile: [OfflineCard] = []

        var total: Int { stack.count + pile.count }
    }

    /// The snaps being collected for a card that made a pair.
    struct Window: Codable, Equatable {
        /// The flip that made the pair.
        var flip: Int
        /// Host time the window closes.
        var closesAt: Double
        /// Reported reaction per player, ms, in arrival order.
        var claims: [Claim] = []
    }

    struct Claim: Codable, Equatable {
        var playerId: String
        var ms: Int
    }

    /// What just happened, shown on every screen for a moment.
    struct Notice: Codable, Equatable {
        enum Kind: String, Codable, Equatable {
            /// `playerId` won `cards` cards with a snap of `ms`.
            case won
            /// A pair went unsnapped.
            case missed
            /// `playerId` snapped wrongly and paid `cards` cards.
            case falseSnap
            /// `playerId` turned their pile over to make a new stack.
            case turnedOver
        }
        var kind: Kind
        var playerId: String?
        var cards: Int = 0
        var ms: Int?
        /// Host time it comes down.
        var until: Double
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        var seats: [Seat]
        var phase: Phase = .playing
        /// Players whose phones have left. Their pile stays on the table; their
        /// stack is out of play.
        var away: [String] = []
        /// Players knocked out, in the order they went.
        var out: [String] = []
        /// Seat index of the player whose card turns next.
        var turn = 0
        /// Cards turned so far; the number a snap refers to.
        var flip = 0
        /// Host time the latest card was turned.
        var flipAt: Double = 0
        /// Seat whose pile took the latest card.
        var lastFlipSeat: Int?
        /// Host time the next card turns (ignored while a window is open).
        var nextFlipAt: Double = 0
        var window: Window?
        /// The flip whose window has been judged; late snaps for it are
        /// refused without a penalty.
        var judgedFlip = 0
        /// Per player, the last flip they false-snapped at — one penalty a card.
        var fouledAt: [String: Int] = [:]
        var notice: Notice?
        var startedAt: Double = 0
        var endsAt: Double = 0
        var endingUntil: Double = 0
        var snapsWon: [String: Int] = [:]
        var falseSnaps: [String: Int] = [:]
        /// Each player's quickest winning snap, ms.
        var best: [String: Int] = [:]
    }

    enum Action: Codable, Equatable {
        /// A tap on SNAP, `ms` milliseconds after card number `flip` showed on
        /// the tapping phone.
        case snap(flip: Int, ms: Int)
    }

    // MARK: - What a player sees

    struct PileRow: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        /// Face-down cards (the order is never sent).
        let stack: Int
        /// Face-up cards under and including the top.
        let pile: Int
        let top: OfflineCard?
        let isTurn: Bool
        let out: Bool
        let away: Bool
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let piles: [PileRow]
        let flip: Int
        /// Host clock: when the newest card was turned.
        let flipAt: Double
        /// Whose pile took the newest card.
        let lastFlipper: String?
        /// My own snap at the card being judged, ms — never anyone else's
        /// until the snap is decided.
        let mySnap: Int?
        let notice: Notice?
        let endsAt: Double
        /// The winners, once the match is decided (several on a tie).
        let champions: [String]
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        let deck = OfflineCard.shuffledDeck(&rng)
        var seats = Array(repeating: Seat(), count: players.count)
        for (index, card) in deck.enumerated() where !players.isEmpty {
            seats[index % players.count].stack.append(card)
        }
        var state = State(players: players, seats: seats)
        state.startedAt = now
        state.nextFlipAt = now + firstFlipDelay
        state.endsAt = now + firstFlipDelay + matchLength
        for player in players { state.snapsWon[player.id] = 0 }
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard let seat = state.players.firstIndex(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not in this game.")
        }
        guard !state.away.contains(playerId) else { throw OfflineRefusal("You have left this game.") }
        guard !state.out.contains(playerId) else { throw OfflineRefusal("You are out — no more snapping.") }
        guard state.phase == .playing else { throw OfflineRefusal("The game is over.") }

        switch action {
        case .snap(let flip, let ms):
            guard ms >= 0, ms <= slowestMs else { throw OfflineRefusal("That time cannot be right.") }
            guard flip >= 1 else { throw OfflineRefusal("Wait for the first card.") }
            guard flip <= state.flip else { throw OfflineRefusal("That card has not been turned yet.") }
            guard flip >= state.flip - 1 else { throw OfflineRefusal("Too late — the cards have moved on.") }

            if var window = state.window, window.flip == flip {
                guard !window.claims.contains(where: { $0.playerId == playerId }) else {
                    throw OfflineRefusal("You have already snapped.")
                }
                if OfflineReaction.counts(ms) {
                    window.claims.append(Claim(playerId: playerId, ms: ms))
                    state.window = window
                    if everyoneHasSnapped(state) { judge(&state, now: now) }
                } else {
                    // Too quick to have seen the card: a guess, and it pays.
                    window.claims.append(Claim(playerId: playerId, ms: -1))
                    state.window = window
                    foul(&state, seat: seat, flip: flip, now: now)
                    if state.phase == .playing, everyoneHasSnapped(state) { judge(&state, now: now) }
                }
                return
            }
            guard flip != state.judgedFlip else { throw OfflineRefusal("Too slow — that snap is over.") }
            guard state.fouledAt[playerId] != flip else { throw OfflineRefusal("You have already snapped at this card.") }
            foul(&state, seat: seat, flip: flip, now: now)
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        if let notice = state.notice, now >= notice.until { state.notice = nil }
        switch state.phase {
        case .playing:
            if now >= state.endsAt {
                if state.window != nil { judge(&state, now: now) }
                if state.phase == .playing { finish(&state, now: now) }
                return
            }
            if let window = state.window {
                if now >= window.closesAt { judge(&state, now: now) }
            } else if now >= state.nextFlipAt {
                turnCard(&state, now: now)
            }
        case .ending:
            if now >= state.endingUntil { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        guard state.phase == .playing else { return }
        if state.window != nil, everyoneHasSnapped(state) { judge(&state, now: now) }
        if state.phase == .playing, activeSeats(state).count <= 1 { finish(&state, now: now) }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let turnSeat = state.phase == .playing ? nextSeat(state, from: state.turn) : nil
        let piles = state.players.enumerated().map { index, player -> PileRow in
            let seat = state.seats[index]
            return PileRow(id: player.id, name: player.name, stack: seat.stack.count, pile: seat.pile.count,
                           top: seat.pile.last, isTurn: index == turnSeat,
                           out: state.out.contains(player.id), away: state.away.contains(player.id))
        }
        var mine: Int?
        if let playerId, let window = state.window {
            mine = window.claims.first { $0.playerId == playerId }?.ms
        }
        return PlayerView(
            phase: state.phase, piles: piles, flip: state.flip, flipAt: state.flipAt,
            lastFlipper: state.lastFlipSeat.map { state.players[$0].id },
            mySnap: mine, notice: state.notice, endsAt: state.endsAt,
            champions: state.phase == .playing ? [] : champions(state)
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(state.players, score: { score(state, $0.id) }, detail: { player in
            var parts: [String] = []
            let won = state.snapsWon[player.id] ?? 0
            parts.append(won == 1 ? "1 snap" : "\(won) snaps")
            if let best = state.best[player.id] { parts.append("best \(best) ms") }
            let fouls = state.falseSnaps[player.id] ?? 0
            if fouls > 0 { parts.append(fouls == 1 ? "1 false snap" : "\(fouls) false snaps") }
            if state.away.contains(player.id) {
                parts.append("left")
            } else if state.out.contains(player.id) {
                parts.append("out")
            }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Helpers

    /// Cards a player holds for the table: none once they have left.
    static func score(_ state: State, _ playerId: String) -> Int {
        guard let index = state.players.firstIndex(where: { $0.id == playerId }),
              !state.away.contains(playerId) else { return 0 }
        return state.seats[index].total
    }

    /// Seats still turning cards: not out, not away.
    static func activeSeats(_ state: State) -> [Int] {
        state.players.indices.filter { index in
            let id = state.players[index].id
            return !state.out.contains(id) && !state.away.contains(id)
        }
    }

    /// The first active seat at or after `from`, going round the table.
    private static func nextSeat(_ state: State, from: Int) -> Int? {
        let count = state.players.count
        guard count > 0 else { return nil }
        let active = activeSeats(state)
        for step in 0..<count {
            let index = (from + step) % count
            if active.contains(index) { return index }
        }
        return nil
    }

    /// Everyone still in has snapped at the open window.
    private static func everyoneHasSnapped(_ state: State) -> Bool {
        guard let window = state.window else { return false }
        return activeSeats(state).allSatisfy { index in
            window.claims.contains { $0.playerId == state.players[index].id }
        }
    }

    /// Ranks that show on two or more face-up tops.
    private static func pairedRanks(_ state: State) -> [Int] {
        var counts: [Int: Int] = [:]
        for seat in state.seats {
            if let top = seat.pile.last { counts[top.rank, default: 0] += 1 }
        }
        return (1...13).filter { (counts[$0] ?? 0) >= 2 }
    }

    /// The beat between cards after `flips` cards.
    static func interval(after flips: Int) -> Double {
        max(fastestInterval, startInterval - quickening * Double(flips))
    }

    /// Turn the next player's top card; open a window if it makes a pair.
    private static func turnCard(_ state: inout State, now: Double) {
        guard let seat = nextSeat(state, from: state.turn) else {
            finish(&state, now: now)
            return
        }
        if state.seats[seat].stack.isEmpty {
            // Out of stack: the pile turns over and becomes the new stack, so
            // its bottom card is the next to show.
            state.seats[seat].stack = state.seats[seat].pile.reversed()
            state.seats[seat].pile = []
            state.notice = Notice(kind: .turnedOver, playerId: state.players[seat].id, until: now + noticeLength)
        }
        guard let card = state.seats[seat].stack.popLast() else {
            // Nothing at all: should already be out, but make sure.
            knockOut(&state, seat: seat)
            state.turn = (seat + 1) % state.players.count
            if activeSeats(state).count <= 1 { finish(&state, now: now) }
            return
        }
        state.seats[seat].pile.append(card)
        state.flip += 1
        state.flipAt = now
        state.lastFlipSeat = seat
        state.turn = (seat + 1) % state.players.count
        state.nextFlipAt = now + interval(after: state.flip)
        if !pairedRanks(state).isEmpty {
            state.window = Window(flip: state.flip, closesAt: now + snapWindow)
        }
    }

    /// Decide the open window: the lowest honest time takes every pile in a
    /// pair (seat order breaks an exact tie).
    private static func judge(_ state: inout State, now: Double) {
        guard let window = state.window else { return }
        state.window = nil
        state.judgedFlip = window.flip
        state.nextFlipAt = now + resultPause

        var winner: Claim?
        for player in state.players {
            guard !state.away.contains(player.id), !state.out.contains(player.id),
                  let claim = window.claims.first(where: { $0.playerId == player.id }), claim.ms >= 0 else { continue }
            if winner == nil || claim.ms < winner!.ms { winner = claim }
        }
        guard let winner, let winnerSeat = state.players.firstIndex(where: { $0.id == winner.playerId }) else {
            state.notice = Notice(kind: .missed, until: now + resultPause)
            return
        }
        let ranks = pairedRanks(state)
        var won: [OfflineCard] = []
        for index in state.seats.indices {
            guard let top = state.seats[index].pile.last, ranks.contains(top.rank) else { continue }
            won.append(contentsOf: state.seats[index].pile)
            state.seats[index].pile = []
        }
        guard !won.isEmpty else {
            // The pair broke up inside the window — a false snap paid away the
            // only card of a one-card pile — so there is nothing left to win.
            state.notice = Notice(kind: .missed, until: now + resultPause)
            return
        }
        // The winnings go under the winner's stack.
        state.seats[winnerSeat].stack = won + state.seats[winnerSeat].stack
        state.snapsWon[winner.playerId, default: 0] += 1
        if let best = state.best[winner.playerId] {
            state.best[winner.playerId] = min(best, winner.ms)
        } else {
            state.best[winner.playerId] = winner.ms
        }
        state.notice = Notice(kind: .won, playerId: winner.playerId, cards: won.count, ms: winner.ms, until: now + resultPause)
        knockOutEmpty(&state)
        if activeSeats(state).count <= 1 { finish(&state, now: now) }
    }

    /// A false snap: one card to each other player still in, while they last.
    private static func foul(_ state: inout State, seat: Int, flip: Int, now: Double) {
        let id = state.players[seat].id
        state.fouledAt[id] = flip
        state.falseSnaps[id, default: 0] += 1
        var paid = 0
        for other in activeSeats(state) where other != seat {
            guard let card = takeCard(from: &state.seats[seat]) else { break }
            state.seats[other].stack.insert(card, at: 0)
            paid += 1
        }
        state.notice = Notice(kind: .falseSnap, playerId: id, cards: paid, until: now + noticeLength)
        knockOutEmpty(&state)
        if activeSeats(state).count <= 1 { finish(&state, now: now) }
    }

    /// A card to pay with: off the stack, else from under the face-up pile so
    /// the top on show stays put.
    private static func takeCard(from seat: inout Seat) -> OfflineCard? {
        if let card = seat.stack.popLast() { return card }
        guard !seat.pile.isEmpty else { return nil }
        return seat.pile.removeFirst()
    }

    private static func knockOutEmpty(_ state: inout State) {
        for index in activeSeats(state) where state.seats[index].total == 0 {
            knockOut(&state, seat: index)
        }
    }

    private static func knockOut(_ state: inout State, seat: Int) {
        let id = state.players[seat].id
        if !state.out.contains(id) { state.out.append(id) }
    }

    private static func finish(_ state: inout State, now: Double) {
        state.window = nil
        state.phase = .ending
        state.endingUntil = now + endingPause
    }

    /// The most cards (several on a tie); nobody if nobody holds any.
    static func champions(_ state: State) -> [String] {
        let top = state.players.map { score(state, $0.id) }.max() ?? 0
        guard top > 0 else { return [] }
        return state.players.map(\.id).filter { score(state, $0) == top }
    }
}
