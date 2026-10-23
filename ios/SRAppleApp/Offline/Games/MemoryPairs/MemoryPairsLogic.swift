import Foundation

/// Pairs: the memory game, for two to five phones round one table.
///
/// The host lays out a grid of face-down cards — twelve pairs for two or
/// three players, fifteen for four or five — each pair sharing one picture.
/// In turn, each player turns two cards over. A match is theirs to keep and
/// they go again; a miss stays face up on every screen for a moment so
/// everybody can try to remember it, then both cards turn back and the turn
/// passes on. When the last pair is taken, the most pairs wins.
///
/// Only the host knows where the pictures are. A `PlayerView` carries a
/// picture only for a card that is face up right now or already taken, so a
/// guest's phone never holds the layout.
enum MemoryPairsRules: OfflineGameRules {
    /// How long a missed pair stays face up for everyone, seconds.
    static let missPause: Double = 1.5
    /// How long a player has for one turn (both cards) before it passes on.
    static let turnTime: Double = 30
    /// How long the cleared table stays up before the standings.
    static let finalePause: Double = 2.5

    /// The pictures, as SF Symbol names. A match uses as many as it has pairs,
    /// picked afresh from this list each time. Every one exists on iOS 17.
    static let symbols: [String] = [
        "star.fill", "heart.fill", "moon.fill", "sun.max.fill", "cloud.fill",
        "bolt.fill", "leaf.fill", "flame.fill", "drop.fill", "snowflake",
        "bell.fill", "key.fill", "music.note", "crown.fill", "fish.fill",
        "pawprint.fill", "airplane", "gift.fill", "umbrella.fill", "car.fill",
    ]

    static let info = OfflineGameInfo(
        id: "memory-pairs",
        title: "Pairs",
        blurb: "Turn two cards a go and remember where every picture hides.",
        category: .skill,
        minPlayers: 2,
        maxPlayers: 5,
        symbol: "square.grid.2x2.fill",
        howToPlay: [
            "All the cards start face down; every picture is on exactly two of them.",
            "On your turn, tap two cards to turn them over.",
            "If they match, you keep the pair and go again.",
            "If not, everybody sees them for a moment, then they turn back.",
            "When the table is empty, the most pairs wins."
        ]
    )

    /// The SF Symbol for a picture index, safe for any number off the wire.
    static func symbolName(_ symbol: Int) -> String {
        symbols.indices.contains(symbol) ? symbols[symbol] : "questionmark"
    }

    /// A picture's spoken name, for VoiceOver and the "found a pair" line:
    /// "star", "sun", "music note".
    static func pictureName(_ symbol: Int) -> String {
        let name = symbolName(symbol)
        if name == "music.note" { return "music note" }
        return name.split(separator: ".").first.map(String.init) ?? name
    }

    /// Pairs on the table for a number of players.
    static func pairCount(players: Int) -> Int { players >= 4 ? 15 : 12 }

    /// Columns in the grid for a number of cards: four for 24, five for 30.
    static func columns(cards: Int) -> Int { cards >= 30 ? 5 : 4 }

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// The turn player is choosing cards (none or one turned so far).
        case choosing
        /// Two cards that do not match are face up for everyone until `hideAt`.
        case showing
        /// The last pair has gone; the cleared table stays up until `finaleUntil`.
        case finale
        /// The match is decided.
        case over
    }

    /// The last thing that happened at the table, for the line under the title.
    struct Last: Codable, Equatable {
        enum Kind: String, Codable, Equatable {
            case matched, missed, timedOut
        }
        let kind: Kind
        let playerId: String
        /// The picture index of a matched pair, so the line can name it.
        let symbol: Int?
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left; their turns are skipped until `.back`.
        var away: [String] = []
        /// The secret: card position → picture index into `symbols`.
        var layout: [Int]
        /// Card position → who took it, or nil while it is still on the table.
        var owner: [String?]
        /// Cards face up this turn, in the order they were turned (0, 1 or 2).
        var flipped: [Int] = []
        var phase: Phase = .choosing
        /// Whose turn it is.
        var turnPlayer: String
        /// Bumped on every turn and every extra go, so a late tap is refused.
        var turn = 1
        /// The current turn runs out at this host time.
        var turnEndsAt: Double
        /// A missed pair turns back at this host time.
        var hideAt: Double = 0
        /// The standings show at this host time, once the table is empty.
        var finaleUntil: Double = 0
        var pairs: [String: Int] = [:]
        /// The longest run of pairs found in one turn, per player.
        var bestRun: [String: Int] = [:]
        /// Pairs found so far in the current turn.
        var run = 0
        var last: Last?
    }

    enum Action: Codable, Equatable {
        /// Turn over the card at `index`, during turn number `turn`.
        case flip(turn: Int, index: Int)
        /// A player marked away whose phone has come back takes their seat
        /// again. The view sends it by itself when it sees itself marked away
        /// (a view only reaches a phone that is connected).
        case back
    }

    // MARK: - What a player sees

    /// One card position. `symbol` is nil while it is face down.
    struct Card: Codable, Equatable, Identifiable {
        let index: Int
        let symbol: Int?
        /// Who took it, once it is taken.
        let owner: String?
        /// Turned over this turn (not yet taken).
        let up: Bool

        var id: Int { index }
    }

    struct Seat: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let pairs: Int
        let away: Bool
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let turnPlayer: String
        let turn: Int
        let columns: Int
        let cards: [Card]
        let seats: [Seat]
        let turnEndsAt: Double
        let hideAt: Double
        let finaleUntil: Double
        let pairsLeft: Int
        let last: Last?
        /// The match winners, once the table is empty (several on a tie).
        let champions: [String]
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        let count = pairCount(players: players.count)
        let chosen = Array(rng.shuffled(Array(symbols.indices)).prefix(count))
        var layout = chosen + chosen
        rng.shuffle(&layout)
        var state = State(players: players, layout: layout,
                          owner: Array(repeating: nil, count: layout.count),
                          turnPlayer: players.first?.id ?? "", turnEndsAt: now + turnTime)
        for player in players {
            state.pairs[player.id] = 0
            state.bestRun[player.id] = 0
        }
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard state.players.contains(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not playing this game.")
        }
        if case .back = action {
            guard state.phase == .choosing || state.phase == .showing else {
                throw OfflineRefusal("The game is over.")
            }
            guard let index = state.away.firstIndex(of: playerId) else {
                throw OfflineRefusal("You are already in this game.")
            }
            // Back in the turn order from the next turn on; their pairs stay theirs.
            state.away.remove(at: index)
            return
        }
        guard !state.away.contains(playerId) else { throw OfflineRefusal("You have left this game.") }
        switch state.phase {
        case .choosing: break
        case .showing: throw OfflineRefusal("Wait — those cards are turning back.")
        case .finale, .over: throw OfflineRefusal("The game is over.")
        }
        guard state.turnPlayer == playerId else {
            throw OfflineRefusal("It's \(name(of: state.turnPlayer, in: state))'s turn.")
        }

        switch action {
        case .back:
            return
        case .flip(let turn, let index):
            guard turn == state.turn else { throw OfflineRefusal("That tap was for an earlier turn.") }
            guard state.layout.indices.contains(index) else { throw OfflineRefusal("There is no card there.") }
            guard state.owner[index] == nil else { throw OfflineRefusal("That pair has already been taken.") }
            guard !state.flipped.contains(index) else { throw OfflineRefusal("That card is already face up.") }
            guard state.flipped.count < 2 else { throw OfflineRefusal("You have turned two cards already.") }

            state.flipped.append(index)
            guard state.flipped.count == 2 else { return }

            let first = state.flipped[0]
            let second = state.flipped[1]
            if state.layout[first] == state.layout[second] {
                state.owner[first] = playerId
                state.owner[second] = playerId
                state.pairs[playerId, default: 0] += 1
                state.run += 1
                state.bestRun[playerId] = max(state.bestRun[playerId] ?? 0, state.run)
                state.flipped = []
                state.last = Last(kind: .matched, playerId: playerId, symbol: state.layout[first])
                if pairsLeft(state) == 0 {
                    state.phase = .finale
                    state.finaleUntil = now + finalePause
                } else {
                    // Another go for the same player, with a fresh clock.
                    state.turn += 1
                    state.turnEndsAt = now + turnTime
                }
            } else {
                state.phase = .showing
                state.hideAt = now + missPause
                state.last = Last(kind: .missed, playerId: playerId, symbol: nil)
            }
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .choosing:
            guard now >= state.turnEndsAt else { return }
            state.last = Last(kind: .timedOut, playerId: state.turnPlayer, symbol: nil)
            passTurn(&state, now: now)
        case .showing:
            guard now >= state.hideAt else { return }
            passTurn(&state, now: now)
        case .finale:
            if now >= state.finaleUntil { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        // A miss already on show passes on by itself when it turns back.
        if state.phase == .choosing, state.turnPlayer == playerId { passTurn(&state, now: now) }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let cards = state.layout.indices.map { index -> Card in
            let owner = state.owner[index]
            let up = state.flipped.contains(index)
            // The picture travels only for a card everybody can see.
            return Card(index: index, symbol: (owner != nil || up) ? state.layout[index] : nil,
                        owner: owner, up: up)
        }
        let seats = state.players.map {
            Seat(id: $0.id, name: $0.name, pairs: state.pairs[$0.id] ?? 0, away: state.away.contains($0.id))
        }
        let done = state.phase == .finale || state.phase == .over
        return PlayerView(
            phase: state.phase, turnPlayer: state.turnPlayer, turn: state.turn,
            columns: columns(cards: state.layout.count), cards: cards, seats: seats,
            turnEndsAt: state.turnEndsAt, hideAt: state.hideAt, finaleUntil: state.finaleUntil,
            pairsLeft: pairsLeft(state), last: state.last,
            champions: done ? champions(state) : []
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(state.players, score: { state.pairs[$0.id] ?? 0 }, detail: { player in
            var parts: [String] = []
            let run = state.bestRun[player.id] ?? 0
            if run > 1 { parts.append("\(run) in a row") }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        })
    }

    // MARK: - Helpers

    /// Pairs still on the table.
    static func pairsLeft(_ state: State) -> Int {
        state.owner.filter { $0 == nil }.count / 2
    }

    /// The most pairs (several on a tie); nobody if nobody found one.
    static func champions(_ state: State) -> [String] {
        let top = state.pairs.values.max() ?? 0
        guard top > 0 else { return [] }
        return state.players.map(\.id).filter { state.pairs[$0] == top }
    }

    private static func name(of id: String, in state: State) -> String {
        state.players.first { $0.id == id }?.name ?? "someone else"
    }

    /// Turn any face-up cards back and hand the turn to the next player still
    /// here, in seat order. With nobody left to play, the match ends.
    private static func passTurn(_ state: inout State, now: Double) {
        state.flipped = []
        state.run = 0
        state.turn += 1
        state.phase = .choosing
        state.turnEndsAt = now + turnTime
        let ids = state.players.map(\.id)
        guard !ids.isEmpty else {
            state.phase = .over
            return
        }
        let start = ids.firstIndex(of: state.turnPlayer) ?? -1
        for step in 1...ids.count {
            let candidate = ids[((start + step) % ids.count + ids.count) % ids.count]
            if !state.away.contains(candidate) {
                state.turnPlayer = candidate
                return
            }
        }
        state.phase = .over
    }
}
