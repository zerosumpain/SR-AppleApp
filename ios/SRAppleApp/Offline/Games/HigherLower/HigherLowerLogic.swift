import Foundation

/// Higher or Lower: one card face up for the whole table, and everyone calls
/// the next one at the same time.
///
/// Each round every player still at the table secretly calls whether the next
/// card off the deck will be higher or lower than the one showing, within six
/// seconds. Nobody sees anyone else's call until the card turns over; then the
/// reveal shows every call at once. Aces are high, and a card of the same rank
/// counts as wrong for everyone — so a 2 or an ace is a gift, a 7 a gamble.
///
/// A right call scores a point and grows your streak, and a streak pays more:
/// two in a row is worth 2, three or more in a row 3 each. A wrong call — or
/// no call before the timer runs out — breaks the streak. Fifteen cards are
/// called; the most points wins.
///
/// What stays secret: the next card and the rest of the deck (only how many are
/// left), and the other players' calls until the reveal (only that they have
/// called). The cards already turned are public, so counting them is fair.
enum HigherLowerRules: OfflineGameRules {
    /// How many cards are called in a match.
    static let rounds = 15
    /// How long everyone has to call, seconds.
    static let callWindow: Double = 6
    /// How long the reveal stays up before the next card, seconds.
    static let revealPause: Double = 3.5
    /// The most a single right call can score (a long streak's rate).
    static let maxGain = 3

    static let info = OfflineGameInfo(
        id: "higher-lower",
        title: "Higher or Lower",
        blurb: "Everyone calls the next card at once; streaks score more.",
        category: .card,
        minPlayers: 1,
        maxPlayers: 5,
        symbol: "arrow.up.arrow.down",
        howToPlay: [
            "Everyone sees the same card. Call whether the next one is higher or lower.",
            "Calls are secret and you have \(Int(callWindow)) seconds — no call counts as wrong.",
            "Aces are high. The same rank again is wrong for everyone.",
            "A right call scores 1; two in a row scores 2, three or more scores \(maxGain) each.",
            "A wrong call breaks your streak. Most points after \(rounds) cards wins."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// Everyone is calling; the timer ends at `callEndsAt`.
        case calling
        /// The next card is up with everyone's calls, until `revealUntil`.
        case reveal
        /// The match is decided.
        case over
    }

    enum Call: String, Codable, Equatable {
        case higher, lower
    }

    /// How the turned card compared with the one before it.
    enum Outcome: String, Codable, Equatable {
        case higher, lower, same
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left; they are not waited for and score nothing.
        var away: [String] = []
        /// The card being called against, face up.
        var current: OfflineCard
        /// The card that will turn over: secret until the reveal.
        var upcoming: OfflineCard
        /// The rest of the deck, drawn from the end. Secret.
        var deck: [OfflineCard]
        /// Every card already turned, in order, `current` last. Public.
        var seen: [OfflineCard]
        var round = 1
        var phase: Phase = .calling
        /// Host clock: the calls close here.
        var callEndsAt: Double = 0
        /// Host clock: the reveal gives way to the next card here.
        var revealUntil: Double = 0
        /// This round's calls. Secret until the reveal.
        var calls: [String: Call] = [:]
        /// The last reveal's comparison (nil while calling).
        var outcome: Outcome?
        /// Points each player scored at the last reveal.
        var gained: [String: Int] = [:]
        var scores: [String: Int] = [:]
        var streaks: [String: Int] = [:]
        var bestStreaks: [String: Int] = [:]
        var rightCalls: [String: Int] = [:]
    }

    enum Action: Codable, Equatable {
        /// My call for round `round`.
        case call(round: Int, call: Call)
    }

    // MARK: - What a player sees

    struct Row: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let score: Int
        let streak: Int
        let away: Bool
        /// Has called this round (true for everyone in the reveal who did).
        let called: Bool
        /// Their call — only once the card has turned.
        let call: Call?
        /// Points from the last reveal — only in the reveal.
        let gained: Int?
    }

    struct PlayerView: Codable, Equatable {
        let round: Int
        let rounds: Int
        let phase: Phase
        /// The card being called against; in the reveal, the one it was compared with.
        let current: OfflineCard
        /// The card that turned — only in the reveal.
        let revealed: OfflineCard?
        let outcome: Outcome?
        let callEndsAt: Double
        let revealUntil: Double
        /// Cards turned before `current`, oldest first (public: counting is fair).
        let history: [OfflineCard]
        let cardsLeft: Int
        let rows: [Row]
        /// My own call this round, even before the reveal.
        let myCall: Call?
        /// The match winners, once it is over (several on a tie).
        let champions: [String]
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var deck = OfflineCard.shuffledDeck(&rng)
        // 52 cards cover the opening card and all fifteen calls.
        let current = deck.removeLast()
        let upcoming = deck.removeLast()
        var state = State(players: players, current: current, upcoming: upcoming, deck: deck, seen: [current])
        for player in players {
            state.scores[player.id] = 0
            state.streaks[player.id] = 0
        }
        state.callEndsAt = now + callWindow
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard state.players.contains(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not in this game.")
        }
        guard !state.away.contains(playerId) else { throw OfflineRefusal("You have left this game.") }
        switch action {
        case .call(let round, let call):
            guard state.phase == .calling else {
                throw OfflineRefusal(state.phase == .over ? "The game is over." : "The card has already turned.")
            }
            guard round == state.round else { throw OfflineRefusal("That call was for another card.") }
            guard now < state.callEndsAt + 0.25 else { throw OfflineRefusal("Time is up for this card.") }
            guard state.calls[playerId] == nil else { throw OfflineRefusal("You have already called this card.") }
            state.calls[playerId] = call
        }
        if everyoneHasCalled(state) { reveal(&state, now: now) }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .calling:
            if now >= state.callEndsAt || everyoneHasCalled(state) { reveal(&state, now: now) }
        case .reveal:
            guard now >= state.revealUntil else { return }
            if state.round >= rounds || everyoneHasGone(state) {
                state.phase = .over
            } else {
                nextCard(&state, now: now)
            }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        state.calls[playerId] = nil
        if everyoneHasGone(state) {
            state.phase = .over
        } else if state.phase == .calling, everyoneHasCalled(state) {
            reveal(&state, now: now)
        }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let revealed = state.phase != .calling
        let rows = state.players.map { player -> Row in
            let call = state.calls[player.id]
            return Row(id: player.id, name: player.name, score: state.scores[player.id] ?? 0,
                       streak: state.streaks[player.id] ?? 0, away: state.away.contains(player.id),
                       called: call != nil, call: revealed ? call : nil,
                       gained: revealed ? (state.gained[player.id] ?? 0) : nil)
        }
        let myCall = playerId.flatMap { id in state.players.contains { $0.id == id } ? state.calls[id] : nil }
        // While calling, `seen` ends with `current`; in the reveal the turned
        // card is `upcoming` and `current` is still the one it beat or lost to.
        return PlayerView(
            round: state.round, rounds: rounds, phase: state.phase,
            current: state.current,
            revealed: revealed ? state.upcoming : nil,
            outcome: revealed ? state.outcome : nil,
            callEndsAt: state.callEndsAt, revealUntil: state.revealUntil,
            history: Array(state.seen.dropLast()),
            cardsLeft: state.deck.count + (revealed ? 0 : 1),
            rows: rows, myCall: myCall,
            champions: state.phase == .over ? champions(state) : []
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(state.players, score: { state.scores[$0.id] ?? 0 }, detail: { player in
            var parts: [String] = []
            let right = state.rightCalls[player.id] ?? 0
            parts.append(right == 1 ? "1 right call" : "\(right) right calls")
            let best = state.bestStreaks[player.id] ?? 0
            if best > 1 { parts.append("best streak \(best)") }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Helpers

    /// How `next` compares with `current`, aces high.
    static func compare(_ next: OfflineCard, to current: OfflineCard) -> Outcome {
        if next.highRank > current.highRank { return .higher }
        if next.highRank < current.highRank { return .lower }
        return .same
    }

    /// What a right call scores with `streak` right calls in a row, this one included.
    static func gain(forStreak streak: Int) -> Int { min(max(streak, 1), maxGain) }

    /// Everyone still here has called.
    private static func everyoneHasCalled(_ state: State) -> Bool {
        state.players.allSatisfy { state.away.contains($0.id) || state.calls[$0.id] != nil }
    }

    private static func everyoneHasGone(_ state: State) -> Bool {
        state.players.allSatisfy { state.away.contains($0.id) }
    }

    /// Turn the card over and score every call.
    private static func reveal(_ state: inout State, now: Double) {
        let outcome = compare(state.upcoming, to: state.current)
        state.outcome = outcome
        state.gained = [:]
        for player in state.players where !state.away.contains(player.id) {
            let id = player.id
            let right: Bool
            switch (state.calls[id], outcome) {
            case (.higher?, .higher), (.lower?, .lower): right = true
            default: right = false
            }
            if right {
                let streak = (state.streaks[id] ?? 0) + 1
                state.streaks[id] = streak
                state.bestStreaks[id] = max(state.bestStreaks[id] ?? 0, streak)
                state.rightCalls[id, default: 0] += 1
                let points = gain(forStreak: streak)
                state.scores[id, default: 0] += points
                state.gained[id] = points
            } else {
                state.streaks[id] = 0
                state.gained[id] = 0
            }
        }
        state.phase = .reveal
        state.revealUntil = now + revealPause
    }

    /// The turned card becomes the one to call against; the next is drawn.
    private static func nextCard(_ state: inout State, now: Double) {
        state.current = state.upcoming
        state.seen.append(state.upcoming)
        // Never empty within fifteen rounds (52 cards), but refill rather than trap.
        if state.deck.isEmpty { state.deck = OfflineCard.deck().filter { $0 != state.current } }
        state.upcoming = state.deck.removeLast()
        state.round += 1
        state.phase = .calling
        state.calls = [:]
        state.gained = [:]
        state.outcome = nil
        state.callEndsAt = now + callWindow
    }

    /// The most points (several on a tie); nobody if nobody scored.
    static func champions(_ state: State) -> [String] {
        let top = state.players.map { state.scores[$0.id] ?? 0 }.max() ?? 0
        guard top > 0 else { return [] }
        return state.players.map(\.id).filter { state.scores[$0] == top }
    }
}
