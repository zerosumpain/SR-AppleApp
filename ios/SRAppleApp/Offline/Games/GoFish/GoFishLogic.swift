import Foundation

/// Go Fish for two to five phones.
///
/// Each player is dealt seven cards (five when four or five play). On your
/// turn you pick another player and ask for a rank you already hold. If they
/// have any, they hand over every one and you go again; if not, they say
/// "Go fish" and you draw from the pond — and if the card you draw is the rank
/// you asked for, you show it and go again. Four of a kind is a book and goes
/// down on the table at once. A player whose hand runs dry draws five (or what
/// is left) at the start of their turn. When all thirteen books are down, the
/// most books wins.
///
/// Everyone sees every ask and answer (the log), the size of every hand and
/// the books on the table; only your own phone ever holds your cards. A card
/// fished from the pond stays private unless it was the rank asked for.
///
/// A player who leaves puts their cards back into the pond (shuffled), keeps
/// the books they made, and is skipped from then on. A turn that sits idle
/// for `turnSeconds` is played for the player: they ask the next person with
/// cards for the rank they hold most of, so one phone left on a table cannot
/// stall the game.
enum GoFishRules: OfflineGameRules {
    /// Cards dealt to each player with two or three at the table.
    static let dealSmall = 7
    /// Cards dealt to each player with four or five.
    static let dealLarge = 5
    /// Cards drawn by a player whose hand has run dry.
    static let refill = 5
    /// How long a turn may sit before the host asks for the player.
    static let turnSeconds: Double = 45
    /// How many log lines the views carry (the newest last).
    static let logLength = 8
    /// Thirteen ranks, so thirteen books end the game.
    static let totalBooks = 13

    static let info = OfflineGameInfo(
        id: "go-fish",
        title: "Go Fish",
        blurb: "Ask for the cards you need; collect the most sets of four.",
        category: .card,
        minPlayers: 2,
        maxPlayers: 5,
        symbol: "fish.fill",
        howToPlay: [
            "On your turn, ask one player for a rank you already hold.",
            "If they have any, they hand them all over and you go again.",
            "If not, go fish: draw one. Draw the rank you asked for and you go again.",
            "Four of a kind is a book and goes straight down on the table.",
            "Run out of cards and you draw five at the start of your turn.",
            "When all 13 books are down, the most books wins."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// Someone is asking.
        case playing
        /// Every book is down (or nobody can play on).
        case over
    }

    /// One ask and its answer, as everyone at the table saw it.
    struct LogEntry: Codable, Equatable, Identifiable {
        /// Increases by one per ask; unique within a match.
        let id: Int
        let asker: String
        let target: String
        /// 1 = ace … 13 = king.
        let rank: Int
        /// How many cards the target handed over; 0 is "Go fish".
        let got: Int
        /// The asker drew from the pond (it was not empty).
        let fished: Bool
        /// The fished card was the rank asked for — shown to everyone.
        let luckyDraw: Bool
        /// Books the asker laid down after this ask, by rank.
        let books: [Int]
        /// The host asked for an idle player.
        let timedOut: Bool
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left; skipped, their cards back in the pond.
        var away: [String] = []
        var phase: Phase = .playing
        /// Every player's hand. Never sent whole.
        var hands: [String: [OfflineCard]] = [:]
        /// The pond, drawn from the end.
        var stock: [OfflineCard] = []
        /// Ranks each player has booked, in the order they were made.
        var books: [String: [Int]] = [:]
        /// Seat index of the player asking.
        var turnIndex = 0
        /// Increases with every ask, so a late or doubled ask is refused.
        var turnNumber = 1
        /// Host time an idle turn is played for its player.
        var turnEndsAt: Double = 0
        /// The newest asks, oldest first, at most `logLength`.
        var log: [LogEntry] = []
        /// The count of asks so far (the next log id).
        var asks = 0
        /// The last card each player fished — private to that player.
        var lastFished: [String: OfflineCard] = [:]
    }

    enum Action: Codable, Equatable {
        /// Ask `target` for every card of `rank`. `turn` is the view's `turnNumber`.
        case ask(turn: Int, target: String, rank: Int)
    }

    // MARK: - What a player sees

    /// One seat at the table: public facts only.
    struct Seat: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        /// How many cards they hold — never which.
        let cards: Int
        /// Their books, by rank.
        let books: [Int]
        let away: Bool
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        /// The player asking now (nil once it is over).
        let turn: String?
        let turnNumber: Int
        let turnEndsAt: Double
        let seats: [Seat]
        /// My cards, sorted by rank; nil for a spectator.
        let myHand: [OfflineCard]?
        /// The card I last fished, while it is still news (my turn, or just after).
        let myFished: OfflineCard?
        let stockCount: Int
        let log: [LogEntry]
        /// Who may be asked right now (on my turn), in seat order.
        let askable: [String]
        /// The most books (several on a tie), once it is over.
        let champions: [String]
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var state = State(players: players)
        var deck = OfflineCard.shuffledDeck(&rng)
        let each = players.count >= 4 ? dealLarge : dealSmall
        let dealt = OfflineCard.deal(each, to: players.count, from: &deck)
        for (seat, player) in players.enumerated() {
            state.hands[player.id] = seat < dealt.count ? dealt[seat] : []
            state.books[player.id] = []
            _ = layBooks(&state, for: player.id)
        }
        state.stock = deck
        beginTurn(&state, from: 0, now: now)
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard let seat = state.players.firstIndex(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not in this game.")
        }
        guard !state.away.contains(playerId) else { throw OfflineRefusal("You have left this game.") }
        guard state.phase == .playing else { throw OfflineRefusal("The game is over.") }

        switch action {
        case .ask(let turn, let target, let rank):
            guard turn == state.turnNumber else { throw OfflineRefusal("That ask was for an earlier turn.") }
            guard seat == state.turnIndex else {
                throw OfflineRefusal("It's \(state.players[state.turnIndex].name)'s turn.")
            }
            guard (1...13).contains(rank) else { throw OfflineRefusal("That is not a card rank.") }
            guard target != playerId else { throw OfflineRefusal("Ask someone else.") }
            guard let other = state.players.first(where: { $0.id == target }) else {
                throw OfflineRefusal("That player is not in this game.")
            }
            guard !state.away.contains(target) else { throw OfflineRefusal("\(other.name) has left the game.") }
            guard askable(state).contains(target) else {
                throw OfflineRefusal("\(other.name) has no cards. Ask someone who does.")
            }
            guard (state.hands[playerId] ?? []).contains(where: { $0.rank == rank }) else {
                throw OfflineRefusal("You can only ask for a rank you hold.")
            }
            perform(&state, asker: playerId, target: target, rank: rank, now: now, timedOut: false)
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.phase == .playing, now >= state.turnEndsAt else { return }
        let asker = state.players[state.turnIndex].id
        guard let target = askable(state).first, let rank = favouriteRank(state.hands[asker] ?? []) else {
            // Nothing sensible to ask: move on rather than stall.
            state.turnNumber += 1
            beginTurn(&state, from: state.turnIndex + 1, now: now)
            return
        }
        perform(&state, asker: asker, target: target, rank: rank, now: now, timedOut: true)
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        // Their cards go back into the pond, so every book can still be made.
        state.stock.append(contentsOf: state.hands[playerId] ?? [])
        state.hands[playerId] = []
        rng.shuffle(&state.stock)
        state.lastFished[playerId] = nil
        guard state.phase == .playing else { return }
        if state.players.filter({ !state.away.contains($0.id) }).count < 2 {
            state.phase = .over
            return
        }
        if state.players[state.turnIndex].id == playerId {
            state.turnNumber += 1
            beginTurn(&state, from: state.turnIndex + 1, now: now)
        }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let seats = state.players.map { player in
            Seat(id: player.id, name: player.name, cards: state.hands[player.id]?.count ?? 0,
                 books: state.books[player.id] ?? [], away: state.away.contains(player.id))
        }
        let inGame = playerId.flatMap { id in state.players.contains { $0.id == id } ? id : nil }
        let turn = state.phase == .playing ? state.players[state.turnIndex].id : nil
        let myTurn = inGame != nil && inGame == turn
        return PlayerView(
            phase: state.phase,
            turn: turn,
            turnNumber: state.turnNumber,
            turnEndsAt: state.turnEndsAt,
            seats: seats,
            myHand: inGame.map { sortedByRank(state.hands[$0] ?? []) },
            myFished: inGame.flatMap { state.lastFished[$0] },
            stockCount: state.stock.count,
            log: state.log,
            askable: myTurn ? askable(state) : [],
            champions: state.phase == .over ? champions(state) : []
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    /// Most books first among the players still at the table. Anyone who
    /// left ranks below all of them, whatever they had booked: otherwise the
    /// player ahead in a two-player game could walk out (which ends the match)
    /// to stop the other catching up.
    static func standings(_ state: State) -> [OfflineStanding] {
        let detail: (OfflinePlayer) -> String? = { player in
            var parts: [String] = []
            let books = state.books[player.id] ?? []
            if !books.isEmpty { parts.append(books.sorted().map { rankName($0, plural: true) }.joined(separator: ", ")) }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        let present = state.players.filter { !state.away.contains($0.id) }
        let gone = state.players.filter { state.away.contains($0.id) }
        let top = OfflineStanding.ranked(present, score: { state.books[$0.id]?.count ?? 0 }, detail: detail)
        let bottom = OfflineStanding.ranked(gone, score: { state.books[$0.id]?.count ?? 0 }, detail: detail)
            .map { OfflineStanding(playerId: $0.playerId, name: $0.name, rank: $0.rank + present.count,
                                   score: $0.score, detail: $0.detail) }
        return top + bottom
    }

    // MARK: - Words

    /// "A", "7", "Q" — the rank as printed on a card.
    static func rankText(_ rank: Int) -> String {
        switch rank {
        case 1: return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return "\(rank)"
        }
    }

    /// "ace" / "aces", "seven" / "sevens", "six" / "sixes" — for sentences and VoiceOver.
    static func rankName(_ rank: Int, plural: Bool) -> String {
        let names = ["ace", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                     "jack", "queen", "king"]
        guard (1...13).contains(rank) else { return "\(rank)" }
        let word = names[rank - 1]
        guard plural else { return word }
        return word == "six" ? "sixes" : word + "s"
    }

    // MARK: - Helpers

    /// The ask itself, once it is known to be legal: hand over or go fish,
    /// lay books, and decide whose turn it is next.
    private static func perform(_ state: inout State, asker: String, target: String, rank: Int,
                                now: Double, timedOut: Bool) {
        state.lastFished[asker] = nil
        var targetHand = state.hands[target] ?? []
        let handed = targetHand.filter { $0.rank == rank }
        targetHand.removeAll { $0.rank == rank }
        state.hands[target] = targetHand

        var goAgain = false
        var fished = false
        var lucky = false
        if !handed.isEmpty {
            state.hands[asker, default: []].append(contentsOf: handed)
            goAgain = true
        } else if let card = state.stock.popLast() {
            fished = true
            state.hands[asker, default: []].append(card)
            state.lastFished[asker] = card
            if card.rank == rank {
                lucky = true
                goAgain = true
            }
        }
        let books = layBooks(&state, for: asker)

        state.asks += 1
        state.log.append(LogEntry(id: state.asks, asker: asker, target: target, rank: rank, got: handed.count,
                                  fished: fished, luckyDraw: lucky, books: books, timedOut: timedOut))
        if state.log.count > logLength { state.log.removeFirst(state.log.count - logLength) }

        state.turnNumber += 1
        if allBooked(state) {
            state.phase = .over
            return
        }
        beginTurn(&state, from: goAgain ? state.turnIndex : state.turnIndex + 1, now: now)
    }

    /// Hand the turn to the first player from seat `from` (wrapping) who is
    /// still here and holds cards — refilling an empty hand from the pond on
    /// the way. Nobody able to play ends the game.
    private static func beginTurn(_ state: inout State, from: Int, now: Double) {
        let count = state.players.count
        guard count > 0, !allBooked(state) else {
            state.phase = .over
            return
        }
        for step in 0..<count {
            let seat = ((from + step) % count + count) % count
            let id = state.players[seat].id
            guard !state.away.contains(id) else { continue }
            // An empty hand draws five (or what is left); books made by the
            // draw go down, which can empty the hand again.
            while (state.hands[id] ?? []).isEmpty && !state.stock.isEmpty {
                for _ in 0..<refill {
                    guard let card = state.stock.popLast() else { break }
                    state.hands[id, default: []].append(card)
                }
                _ = layBooks(&state, for: id)
            }
            if allBooked(state) {
                state.phase = .over
                return
            }
            if !(state.hands[id] ?? []).isEmpty {
                state.turnIndex = seat
                state.turnEndsAt = now + turnSeconds
                return
            }
        }
        state.phase = .over
    }

    /// Lay down every four of a kind in `id`'s hand; the ranks laid, lowest first.
    @discardableResult
    private static func layBooks(_ state: inout State, for id: String) -> [Int] {
        var hand = state.hands[id] ?? []
        var made: [Int] = []
        for rank in 1...13 where hand.filter({ $0.rank == rank }).count == 4 {
            hand.removeAll { $0.rank == rank }
            made.append(rank)
        }
        guard !made.isEmpty else { return [] }
        state.hands[id] = hand
        state.books[id, default: []].append(contentsOf: made)
        return made
    }

    /// Who the player whose turn it is may ask: everyone else still here with
    /// cards — or, if nobody else holds a card, anyone else still here (the
    /// ask is then a plain go fish).
    static func askable(_ state: State) -> [String] {
        guard state.phase == .playing, state.players.indices.contains(state.turnIndex) else { return [] }
        let me = state.players[state.turnIndex].id
        let others = state.players.map(\.id).filter { $0 != me && !state.away.contains($0) }
        let holding = others.filter { !(state.hands[$0] ?? []).isEmpty }
        return holding.isEmpty ? others : holding
    }

    /// The rank a hand holds most of (lowest on a tie) — what an idle turn asks for.
    static func favouriteRank(_ hand: [OfflineCard]) -> Int? {
        var best: (rank: Int, count: Int)?
        for rank in 1...13 {
            let count = hand.filter { $0.rank == rank }.count
            if count > 0, best == nil || count > best!.count { best = (rank, count) }
        }
        return best?.rank
    }

    /// A hand by rank (aces low), then suit, so pairs sit together.
    static func sortedByRank(_ cards: [OfflineCard]) -> [OfflineCard] {
        let suitOrder: [OfflineSuit] = [.clubs, .diamonds, .hearts, .spades]
        return cards.sorted { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            return (suitOrder.firstIndex(of: a.suit) ?? 0) < (suitOrder.firstIndex(of: b.suit) ?? 0)
        }
    }

    private static func allBooked(_ state: State) -> Bool {
        state.books.values.reduce(0) { $0 + $1.count } >= totalBooks
    }

    /// The most books among the players still here (several on a tie);
    /// everyone, if all of them left.
    static func champions(_ state: State) -> [String] {
        let present = state.players.map(\.id).filter { !state.away.contains($0) }
        let pool = present.isEmpty ? state.players.map(\.id) : present
        let top = pool.map { state.books[$0]?.count ?? 0 }.max() ?? 0
        guard top > 0 else { return [] }
        return pool.filter { (state.books[$0]?.count ?? 0) == top }
    }
}
