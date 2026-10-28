import Foundation

/// Fireworks — the co-operative card game — for two to five phones, or one
/// phone and computer partners.
///
/// The site's rules (`src/lib/games/fireworks.ts`, medium: five colours,
/// three misfires), played on the host. The table builds five fireworks
/// together, one per colour, each from 1 up to 5 in order. The twist: you
/// hold your cards facing AWAY from you. Every phone shows everyone else's
/// cards, and of its own only what the team's hints have said. On your turn
/// you give a hint (one colour or one number, pointing at every matching
/// card in one other player's hand; costs a hint token), drop a card (wins a
/// token back; not while all eight are in), or play one: the next number
/// for its colour joins the firework, anything else is a misfire. Finishing
/// a firework with its 5 wins a token back. The third misfire ends the show;
/// so does a perfect 25, and once the last card is drawn everyone has one
/// more turn. The team scores the top of every firework.
///
/// A deck of fifty: in each colour three 1s, two each of 2–4 and one 5.
/// Hands are five cards for two or three players, four for four or five.
/// Card ids are numbered AFTER the shuffle, so an id says nothing about the
/// card. A turn lasts ninety seconds; a player who lets it run out drops
/// their oldest card no hint has touched. A player who leaves puts their
/// cards on the discards and the team plays on; one player left ends it.
///
/// HIDDEN INFORMATION: a player's own cards never go into their own view,
/// only what hints said — and a spectator, who might be sitting next to a
/// player, sees no hand at all. The deck is a count everywhere.
enum OfflineFireworksRules: OfflineGameRules {
    static let colours = ["red", "yellow", "green", "blue", "white"]
    static let ranks = [1, 2, 3, 4, 5]
    /// Copies of each number in one colour (index = rank).
    static let copies = [0, 3, 2, 2, 2, 1]
    static let maxHints = 8
    static let maxMisfires = 3
    static var maxScore: Int { colours.count * 5 }
    /// Seconds a turn lasts before the host drops a card for the player.
    static let turnSeconds: Double = 90
    /// How long the final table stays up before the standings.
    static let resultPause: Double = 6
    /// Log lines a view carries.
    static let logShown = 6

    static let info = OfflineGameInfo(
        id: "fireworks",
        title: "Fireworks",
        blurb: "Build the show together. You can see every hand but your own.",
        category: .card,
        minPlayers: 2,
        maxPlayers: 5,
        symbol: "sparkles",
        howToPlay: [
            "Build five fireworks together, one per colour, from 1 up to 5 in order.",
            "You see everyone's cards but your own; hints tell you about yours.",
            "On your turn: hint one colour or number to a player (costs a token), drop a card (wins one back) or play one.",
            "A card that is not next for its colour is a misfire. The third misfire ends the show.",
            "Once the deck runs out, everyone has one more turn. The score is the top of every firework.",
            "Computer partners play a card once hints make it near certain, hint your playable cards, and drop their oldest unhinted card."
        ],
        soloOpponents: 2
    )

    /// Cards in a hand for a table of `players`.
    static func handSize(players: Int) -> Int { players <= 3 ? 5 : 4 }

    // MARK: - Cards

    struct Card: Codable, Equatable, Identifiable {
        let id: Int
        let colour: String
        let rank: Int
    }

    /// What the team's hints have said about one card in a hand. Public.
    struct Knowledge: Codable, Equatable {
        /// Colour hints that pointed at it (at most one, five colours).
        var colours: [String] = []
        /// Colour hints given to this hand that did not.
        var notColours: [String] = []
        /// The number a hint pointed at it with.
        var rank: Int?
        /// Number hints given to this hand that did not.
        var notRanks: [Int] = []

        /// The colours it can still be, from the hints alone.
        var possibleColours: [String] {
            if let c = colours.first { return [c] }
            return OfflineFireworksRules.colours.filter { !notColours.contains($0) }
        }

        /// The numbers it can still be, from the hints alone.
        var possibleRanks: [Int] {
            if let rank { return [rank] }
            return OfflineFireworksRules.ranks.filter { !notRanks.contains($0) }
        }

        /// A hint has pointed at it.
        var touched: Bool { !colours.isEmpty || rank != nil }
    }

    struct Held: Codable, Equatable {
        let card: Card
        var knows = Knowledge()
    }

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        case playing
        /// The show is over; the final table shows until `resultUntil`.
        case done
        /// The room shows the standings.
        case over
    }

    /// How the show ended — the site's words.
    enum Ending: String, Codable, Equatable {
        case perfect, misfires, deck, left
    }

    /// One thing that happened, for the log.
    struct LogEntry: Codable, Equatable {
        enum Kind: String, Codable, Equatable { case hint, play, discard }

        let kind: Kind
        let by: String
        /// A hint's player.
        var to: String?
        /// A hint's colour or number.
        var colour: String?
        var rank: Int?
        /// The ids a hint pointed at.
        var cards: [Int] = []
        /// The card played or dropped.
        var card: Card?
        /// A play landed.
        var ok: Bool?
        /// The turn ran out and the host dropped a card.
        var auto = false
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Each player's hand, oldest card first.
        var hands: [String: [Held]]
        /// Undealt cards, top last. Only ever a count on the wire.
        var deck: [Card]
        /// Each firework's top number, in `colours` order (0 = not started).
        var stacks: [Int]
        var discards: [Card] = []
        var hints = OfflineFireworksRules.maxHints
        var misfires = 0
        /// Seat whose turn it is.
        var turn = 0
        /// Goes up with every turn: a late action is refused, not misapplied.
        var turnNumber = 1
        var turnEndsAt: Double
        /// Once the last card is drawn, who still has their last turn; nil
        /// while the deck lasts.
        var finalTurns: [String]?
        var log: [LogEntry] = []
        var phase: Phase = .playing
        var ending: Ending?
        var resultUntil: Double = 0
        /// Players who left; their cards went to the discards.
        var left: [String] = []
    }

    enum Action: Codable, Equatable {
        /// Play card `card` (an id in my hand) on turn `turn`.
        case play(turn: Int, card: Int)
        /// Drop card `card` for a hint token.
        case discard(turn: Int, card: Int)
        /// Point at every `colour` card in `to`'s hand.
        case hintColour(turn: Int, to: String, colour: String)
        /// Point at every `rank` card in `to`'s hand.
        case hintRank(turn: Int, to: String, rank: Int)
    }

    // MARK: - What a player sees

    /// One card in a hand as a viewer sees it: face up (`colour` and `rank`)
    /// unless it is the viewer's own, and always what the hints have said.
    struct CardView: Codable, Equatable, Identifiable {
        let id: Int
        let colour: String?
        let rank: Int?
        /// What the hints allow it to be.
        let colours: [String]
        let ranks: [Int]
        let touched: Bool
    }

    struct Seat: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        /// Oldest first. Empty for a spectator's view.
        let hand: [CardView]
        let left: Bool
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let turnPlayer: String?
        let turnNumber: Int
        let turnEndsAt: Double
        let hints: Int
        let misfires: Int
        let deck: Int
        /// Turns left once the deck is empty; nil while it lasts.
        let finalTurns: Int?
        /// Each firework's top number, in `colours` order.
        let stacks: [Int]
        let score: Int
        let discards: [Card]
        /// The latest few things that happened, oldest first.
        let log: [LogEntry]
        let seats: [Seat]
        let ending: Ending?
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var cards: [(colour: String, rank: Int)] = []
        for colour in colours {
            for rank in ranks {
                for _ in 0..<copies[rank] { cards.append((colour, rank)) }
            }
        }
        rng.shuffle(&cards)
        // Numbered after the shuffle: an id is no clue to what the card is.
        var deck = cards.enumerated().map { Card(id: $0.offset + 1, colour: $0.element.colour, rank: $0.element.rank) }
        deck.reverse()
        var hands: [String: [Held]] = [:]
        for player in players { hands[player.id] = [] }
        for _ in 0..<handSize(players: players.count) {
            for player in players {
                if let card = deck.popLast() { hands[player.id, default: []].append(Held(card: card)) }
            }
        }
        return State(players: players, hands: hands, deck: deck, stacks: Array(repeating: 0, count: colours.count),
                     turnEndsAt: now + turnSeconds)
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard let seat = state.players.firstIndex(where: { $0.id == playerId }), !state.left.contains(playerId) else {
            throw OfflineRefusal("You are not playing this game.")
        }
        guard state.phase == .playing else { throw OfflineRefusal("The show is over.") }
        let turn: Int
        switch action {
        case .play(let t, _), .discard(let t, _), .hintColour(let t, _, _), .hintRank(let t, _, _): turn = t
        }
        guard turn == state.turnNumber else { throw OfflineRefusal("That was for an earlier turn.") }
        guard seat == state.turn else { throw OfflineRefusal("It's \(state.players[state.turn].name)'s turn.") }
        let hand = state.hands[playerId] ?? []
        switch action {
        case .play(_, let id):
            guard let index = hand.firstIndex(where: { $0.card.id == id }) else {
                throw OfflineRefusal("That card is not in your hand.")
            }
            play(index, by: playerId, auto: false, in: &state, now: now)
        case .discard(_, let id):
            guard let index = hand.firstIndex(where: { $0.card.id == id }) else {
                throw OfflineRefusal("That card is not in your hand.")
            }
            guard state.hints < maxHints else {
                throw OfflineRefusal("All \(maxHints) hint tokens are in — give a hint or play a card.")
            }
            discard(index, by: playerId, auto: false, in: &state, now: now)
        case .hintColour(_, let to, let colour):
            guard colours.contains(colour) else { throw OfflineRefusal("Hint one of: \(colours.joined(separator: ", ")).") }
            try hint(by: playerId, to: to, colour: colour, rank: nil, in: &state, now: now)
        case .hintRank(_, let to, let rank):
            guard ranks.contains(rank) else { throw OfflineRefusal("Hint a number from 1 to 5.") }
            try hint(by: playerId, to: to, colour: nil, rank: rank, in: &state, now: now)
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .playing:
            guard now >= state.turnEndsAt else { return }
            let player = state.players[state.turn].id
            let hand = state.hands[player] ?? []
            guard !state.left.contains(player), !hand.isEmpty else {
                // Nobody to move, or nothing to drop: hand it on rather than stall.
                state.finalTurns?.removeAll { $0 == player }
                if state.finalTurns?.isEmpty == true {
                    finish(&state, .deck, now: now)
                } else {
                    advance(&state, from: player, now: now)
                }
                return
            }
            // The oldest card no hint has touched, else the oldest.
            let index = hand.firstIndex { !$0.knows.touched } ?? 0
            discard(index, by: player, auto: true, in: &state, now: now)
        case .done:
            if now >= state.resultUntil { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.left.contains(playerId) else { return }
        state.left.append(playerId)
        state.discards.append(contentsOf: (state.hands[playerId] ?? []).map(\.card))
        state.hands[playerId] = []
        guard state.phase == .playing else { return }
        state.finalTurns?.removeAll { $0 == playerId }
        if active(state).count < 2 {
            finish(&state, .left, now: now)
            return
        }
        if state.finalTurns?.isEmpty == true {
            finish(&state, .deck, now: now)
            return
        }
        if state.players[state.turn].id == playerId { advance(&state, from: playerId, now: now) }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let seated = playerId.map { id in state.players.contains { $0.id == id } } ?? false
        let seats = state.players.map { player -> Seat in
            let own = player.id == playerId
            // A spectator may be sitting beside a player: no hands at all.
            let hand = seated ? (state.hands[player.id] ?? []).map { held in
                CardView(id: held.card.id, colour: own ? nil : held.card.colour, rank: own ? nil : held.card.rank,
                         colours: held.knows.possibleColours, ranks: held.knows.possibleRanks, touched: held.knows.touched)
            } : []
            return Seat(id: player.id, name: player.name, hand: hand, left: state.left.contains(player.id))
        }
        return PlayerView(
            phase: state.phase,
            turnPlayer: state.phase == .playing ? state.players[state.turn].id : nil,
            turnNumber: state.turnNumber,
            turnEndsAt: state.turnEndsAt,
            hints: state.hints,
            misfires: state.misfires,
            deck: state.deck.count,
            finalTurns: state.finalTurns?.count,
            stacks: state.stacks,
            score: score(state),
            discards: state.discards,
            log: Array(state.log.suffix(logShown)),
            seats: seats,
            ending: state.ending
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        let total = score(state)
        return OfflineStanding.ranked(state.players, score: { _ in total }, detail: { player in
            var parts = ["team score \(total) of \(maxScore)"]
            if state.misfires > 0 { parts.append(state.misfires == 1 ? "1 misfire" : "\(state.misfires) misfires") }
            if state.left.contains(player.id) { parts.append("left early") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - The table

    static func score(_ state: State) -> Int { state.stacks.reduce(0, +) }

    /// Players still at the table, seat order.
    static func active(_ state: State) -> [OfflinePlayer] {
        state.players.filter { !state.left.contains($0.id) }
    }

    /// The index of `colour` in `colours`.
    static func colourIndex(_ colour: String) -> Int? { colours.firstIndex(of: colour) }

    /// Whether `card` would land now on `stacks`.
    static func playable(colour: String, rank: Int, stacks: [Int]) -> Bool {
        guard let i = colourIndex(colour), stacks.indices.contains(i) else { return false }
        return stacks[i] == rank - 1
    }

    /// A hint as a choice, before it is addressed.
    enum HintChoice: Codable, Equatable, Hashable {
        case colour(String)
        case rank(Int)

        var spoken: String {
            switch self {
            case .colour(let c): return c.capitalized
            case .rank(let r): return "\(r)"
            }
        }
    }

    /// Every hint that would point at something in `hand`: colours first,
    /// then numbers. Face-down cards point at nothing.
    static func possibleHintChoices(for hand: [CardView]) -> [HintChoice] {
        let byColour = colours.filter { c in hand.contains { $0.colour == c } }.map(HintChoice.colour)
        let byRank = ranks.filter { r in hand.contains { $0.rank == r } }.map(HintChoice.rank)
        return byColour + byRank
    }

    /// The ids in `hand` a hint would point at.
    static func touched(by choice: HintChoice, in hand: [CardView]) -> [Int] {
        hand.filter { card in
            switch choice {
            case .colour(let c): return card.colour == c
            case .rank(let r): return card.rank == r
            }
        }.map(\.id)
    }

    /// "Red 3".
    static func cardText(_ card: Card) -> String { "\(card.colour.capitalized) \(card.rank)" }

    /// One log line; names from `name` ("You" for me).
    static func logLine(_ entry: LogEntry, name: (String) -> String) -> String {
        let who = name(entry.by)
        switch entry.kind {
        case .hint:
            let target = entry.to.map(name) ?? "someone"
            let count = entry.cards.count
            let what: String
            if let colour = entry.colour {
                what = count == 1 ? "a \(colour) card" : "\(count) \(colour) cards"
            } else {
                let r = entry.rank ?? 0
                what = count == 1 ? "a \(r)" : "\(count) × \(r)"
            }
            let possessive = target == "You" ? "your" : "\(target)\u{2019}s"
            return "\(who) pointed at \(what) in \(possessive) hand."
        case .play:
            let card = entry.card.map(cardText) ?? "a card"
            return entry.ok == true ? "\(who) played the \(card). Bang!" : "\(who) played the \(card) — a misfire."
        case .discard:
            let card = entry.card.map(cardText) ?? "a card"
            return entry.auto ? "\(who) ran out of time: the \(card) was dropped." : "\(who) dropped the \(card)."
        }
    }

    /// How the show ended, in a sentence.
    static func endingLine(_ ending: Ending?, score: Int) -> String {
        let of = "\(score) of \(maxScore)"
        switch ending {
        case .perfect?: return "A perfect show: every firework went up. \(of)."
        case .misfires?: return "Too many misfires — the show stopped at \(of)."
        case .deck?: return "The last card was played out. The team scored \(of)."
        case .left?: return "Not enough players left to carry on. The team scored \(of)."
        case nil: return "The team scored \(of)."
        }
    }

    // MARK: - Helpers

    private static func hint(by playerId: String, to target: String, colour: String?, rank: Int?,
                             in state: inout State, now: Double) throws {
        guard state.hints > 0 else { throw OfflineRefusal("No hint tokens left — play or drop a card.") }
        guard target != playerId, let player = state.players.first(where: { $0.id == target }),
              !state.left.contains(target) else {
            throw OfflineRefusal("Pick another player at the table to hint.")
        }
        var hand = state.hands[target] ?? []
        let hit = hand.filter { colour != nil ? $0.card.colour == colour : $0.card.rank == rank }.map(\.card.id)
        guard !hit.isEmpty else { throw OfflineRefusal("\(player.name) has no card that hint points at.") }
        for i in hand.indices {
            let on = hit.contains(hand[i].card.id)
            if let colour {
                if on, !hand[i].knows.colours.contains(colour) { hand[i].knows.colours.append(colour) }
                if !on, !hand[i].knows.notColours.contains(colour) { hand[i].knows.notColours.append(colour) }
            } else if let rank {
                if on { hand[i].knows.rank = rank } else if !hand[i].knows.notRanks.contains(rank) { hand[i].knows.notRanks.append(rank) }
            }
        }
        state.hands[target] = hand
        state.hints -= 1
        state.log.append(LogEntry(kind: .hint, by: playerId, to: target, colour: colour, rank: rank, cards: hit))
        endTurn(&state, playerId: playerId, now: now, drewBeforeLap: false)
    }

    private static func play(_ index: Int, by playerId: String, auto: Bool, in state: inout State, now: Double) {
        let lap = state.finalTurns != nil
        guard let card = state.hands[playerId]?.remove(at: index).card else { return }
        let ok = playable(colour: card.colour, rank: card.rank, stacks: state.stacks)
        if ok, let i = colourIndex(card.colour) {
            state.stacks[i] = card.rank
            // Finishing a firework wins a token back.
            if card.rank == 5 && state.hints < maxHints { state.hints += 1 }
        } else {
            state.misfires += 1
            state.discards.append(card)
        }
        state.log.append(LogEntry(kind: .play, by: playerId, card: card, ok: ok, auto: auto))
        draw(&state, playerId: playerId)
        endTurn(&state, playerId: playerId, now: now, drewBeforeLap: !lap)
    }

    private static func discard(_ index: Int, by playerId: String, auto: Bool, in state: inout State, now: Double) {
        let lap = state.finalTurns != nil
        guard let card = state.hands[playerId]?.remove(at: index).card else { return }
        state.discards.append(card)
        if state.hints < maxHints { state.hints += 1 }
        state.log.append(LogEntry(kind: .discard, by: playerId, card: card, auto: auto))
        draw(&state, playerId: playerId)
        endTurn(&state, playerId: playerId, now: now, drewBeforeLap: !lap)
    }

    /// After a play or a drop: the top card, if there is one. The last card
    /// out gives everyone, this player included, one more turn.
    private static func draw(_ state: inout State, playerId: String) {
        if let next = state.deck.popLast() { state.hands[playerId, default: []].append(Held(card: next)) }
        if state.deck.isEmpty && state.finalTurns == nil { state.finalTurns = active(state).map(\.id) }
    }

    /// A turn is over: end the show if it is, else hand the turn on.
    private static func endTurn(_ state: inout State, playerId: String, now: Double, drewBeforeLap: Bool) {
        if score(state) == maxScore { return finish(&state, .perfect, now: now) }
        if state.misfires >= maxMisfires { return finish(&state, .misfires, now: now) }
        // The turn that drew the last card is not the player's last turn: it started the lap.
        if !drewBeforeLap { state.finalTurns?.removeAll { $0 == playerId } }
        if state.finalTurns?.isEmpty == true { return finish(&state, .deck, now: now) }
        advance(&state, from: playerId, now: now)
    }

    /// The next player still at the table after `playerId`, with a fresh clock.
    private static func advance(_ state: inout State, from playerId: String, now: Double) {
        let count = state.players.count
        guard count > 0 else { return }
        let at = state.players.firstIndex { $0.id == playerId } ?? state.turn
        for step in 1...count {
            let next = (at + step) % count
            if !state.left.contains(state.players[next].id) {
                state.turn = next
                break
            }
        }
        state.turnNumber += 1
        state.turnEndsAt = now + turnSeconds
    }

    private static func finish(_ state: inout State, _ ending: Ending, now: Double) {
        state.ending = ending
        state.phase = .done
        state.turnNumber += 1
        state.resultUntil = now + resultPause
    }
}
