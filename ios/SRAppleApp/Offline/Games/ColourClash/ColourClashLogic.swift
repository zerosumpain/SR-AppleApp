import Foundation

/// Colour Clash: a Stroop test for two to five phones.
///
/// Thirty cards go by, one every 1.2 seconds, at host-clock times every phone
/// shares. Each card is a colour WORD printed in an ink colour. Tap only when
/// the word names its own ink. On a matching card the quickest correct tap
/// (timed on the tapping phone, from the frame that showed the card) scores
/// two, every other correct tap one; tapping a card that does not match costs
/// a point. A tap too quick to be a reaction to a match scores nothing. Most
/// points after the last card wins.
///
/// Built like Quick Draw: the host schedules the cards, phones report how long
/// after the card appeared they tapped, and a card is scored once everyone
/// still here has tapped it or a short grace after it has gone, so Bluetooth
/// latency never decides who was quickest. Cards still to come are never in a
/// player's view, nor is anybody else's tap on a card not yet scored.
enum ColourClashRules: OfflineGameRules {
    /// Cards in a match.
    static let cardCount = 30
    /// How many of them match (word names its ink). Fixed, so every match is
    /// equally generous; their positions are shuffled.
    static let matchCount = 12
    /// Seconds each card is up.
    static let interval: Double = 1.2
    /// Seconds from the start to the first card.
    static let leadIn: Double = 3
    /// Seconds after a card leaves that a late-arriving tap still counts.
    static let grace: Double = 0.8
    /// Seconds the final scores stay up before the match ends.
    static let resultPause: Double = 4
    /// Points for the quickest correct tap on a match.
    static let firstPoints = 2
    /// Points for any other correct tap on a match.
    static let correctPoints = 1
    /// Points for tapping a card that does not match.
    static let wrongPoints = -1
    /// A reported time above this cannot be right.
    static let maxMs = 5_000

    static let info = OfflineGameInfo(
        id: "colour-clash",
        title: "Colour Clash",
        blurb: "Tap only when the word names the colour it is printed in.",
        category: .reaction,
        minPlayers: 2,
        maxPlayers: 5,
        symbol: "paintpalette.fill",
        howToPlay: [
            "A colour word appears every second or so, printed in a coloured ink.",
            "Tap only when the word names its own ink — RED in red.",
            "Each ink has its own shape too, so you can match by shape.",
            "Quickest correct tap scores \(firstPoints); any other correct tap scores \(correctPoints).",
            "Tapping a card that doesn't match costs a point.",
            "\(cardCount) cards; the most points wins."
        ]
    )

    // MARK: - State

    /// The five inks. Each has its own word, colour and shape (in the view),
    /// so nobody needs to tell red from green by colour alone.
    enum Hue: String, Codable, Equatable, CaseIterable {
        case red, blue, green, orange, purple

        /// The word as printed on a card.
        var word: String { rawValue.uppercased() }
    }

    /// One card: a word printed in an ink.
    struct Card: Codable, Equatable {
        let word: Hue
        let ink: Hue
        var isMatch: Bool { word == ink }
    }

    enum Phase: String, Codable, Equatable {
        /// The lead-in; the first card shows at `firstAt`.
        case ready
        /// Cards are going by.
        case running
        /// The last card is scored; the table is up until `resultUntil`.
        case result
        /// The match is decided.
        case over
    }

    /// One player's tap on one card.
    struct Mark: Codable, Equatable {
        let card: Int
        let player: String
        /// Milliseconds from the card shown to the touch, on the tapping phone.
        let ms: Int
    }

    /// What the last scored card did.
    struct Scored: Codable, Equatable {
        /// 0-based card index.
        let card: Int
        let match: Bool
        /// Points each player who tapped it got (players who did not tap are absent).
        let points: [String: Int]
        /// Who scored the quickest-tap bonus (several on an exact tie).
        let quickest: [String]
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left; they are not waited for.
        var away: [String] = []
        var phase: Phase = .ready
        /// The whole deck, decided at the start. Never sent ahead of time.
        var cards: [Card] = []
        /// When card 0 shows, host clock. Card i shows at `showAt(i)`.
        var firstAt: Double = 0
        /// The card on screen: -1 before the first, `cardCount` after the last.
        var current = -1
        /// Every card up to and including this one has been scored.
        var scoredThrough = -1
        var marks: [Mark] = []
        var points: [String: Int] = [:]
        var right: [String: Int] = [:]
        var wrong: [String: Int] = [:]
        var quickests: [String: Int] = [:]
        /// Each player's best correct time, ms.
        var best: [String: Int] = [:]
        var last: Scored?
        var resultUntil: Double = 0
    }

    enum Action: Codable, Equatable {
        /// A tap on card `card` (0-based), `ms` milliseconds after it showed on
        /// the tapping phone.
        case tap(card: Int, ms: Int)
    }

    // MARK: - What a player sees

    struct Row: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let points: Int
        let away: Bool
        /// What the last scored card gave them; nil if they did not tap it.
        let lastPoints: Int?
        /// They had the quickest correct tap on the last scored card.
        let quickest: Bool
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let firstAt: Double
        /// 0-based index of the card on screen (-1 before, `cardCount` after).
        let index: Int
        let cardCount: Int
        /// The card on screen now, or nil before the first and after the last.
        let card: Card?
        /// When it showed, host clock.
        let shownAt: Double
        /// My reported time on the card on screen, if I have tapped it.
        let myMs: Int?
        /// The last scored card's card and outcome.
        let lastCard: Card?
        let last: Scored?
        let rows: [Row]
        let resultUntil: Double
        /// The winners once the cards are done (several on a tie).
        let champions: [String]
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var state = State(players: players)
        state.cards = deal(&rng)
        state.firstAt = now + leadIn
        for player in players { state.points[player.id] = 0 }
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard state.players.contains(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not in this game.")
        }
        guard !state.away.contains(playerId) else { throw OfflineRefusal("You have left this game.") }
        // Catch the schedule up to `now` first. The host ticks about ten times a
        // second, so a tap on a card that is already due can arrive before the
        // tick that puts it up; judged against the stale card it would be
        // refused as "not up yet". (A throw below discards this along with the
        // tap — the host applies to a copy — and the next tick redoes it.)
        if state.phase == .ready, now >= state.firstAt { state.phase = .running }
        settle(&state, now: now)
        switch state.phase {
        case .ready: throw OfflineRefusal("Wait for the first card.")
        case .result, .over: throw OfflineRefusal("The cards are done.")
        case .running: break
        }
        switch action {
        case .tap(let card, let ms):
            guard card >= 0, card < state.cards.count else { throw OfflineRefusal("There is no such card.") }
            guard card <= state.current else { throw OfflineRefusal("That card isn't up yet.") }
            guard card > state.scoredThrough else { throw OfflineRefusal("Too late for that card.") }
            guard !state.marks.contains(where: { $0.card == card && $0.player == playerId }) else {
                throw OfflineRefusal("You already tapped that card.")
            }
            guard ms >= 0, ms <= maxMs else { throw OfflineRefusal("That time cannot be right.") }
            state.marks.append(Mark(card: card, player: playerId, ms: ms))
        }
        settle(&state, now: now)
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .ready:
            guard now >= state.firstAt else { return }
            state.phase = .running
            settle(&state, now: now)
        case .running:
            settle(&state, now: now)
        case .result:
            if now >= state.resultUntil { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        if state.phase == .running { settle(&state, now: now) }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let onScreen = state.current >= 0 && state.current < state.cards.count && state.phase == .running
        let myMs: Int? = playerId.flatMap { id in
            state.marks.first { $0.card == state.current && $0.player == id }?.ms
        }
        let rows = state.players.map { player -> Row in
            Row(id: player.id, name: player.name, points: state.points[player.id] ?? 0,
                away: state.away.contains(player.id),
                lastPoints: state.last?.points[player.id],
                quickest: state.last?.quickest.contains(player.id) ?? false)
        }
        return PlayerView(
            phase: state.phase,
            firstAt: state.firstAt,
            index: state.current,
            cardCount: state.cards.count,
            card: onScreen ? state.cards[state.current] : nil,
            shownAt: showAt(max(state.current, 0), state),
            myMs: onScreen ? myMs : nil,
            lastCard: state.last.map { state.cards[$0.card] },
            last: state.last,
            rows: rows,
            resultUntil: state.resultUntil,
            champions: (state.phase == .result || state.phase == .over) ? champions(state) : []
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(state.players, score: { state.points[$0.id] ?? 0 }, detail: { player in
            var parts: [String] = []
            parts.append("\(state.right[player.id] ?? 0) right")
            let wrong = state.wrong[player.id] ?? 0
            if wrong > 0 { parts.append("\(wrong) wrong") }
            if let best = state.best[player.id] { parts.append("best \(best) ms") }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Helpers

    /// When card `index` shows, host clock. `showAt(cardCount)` is when the
    /// last card leaves.
    static func showAt(_ index: Int, _ state: State) -> Double {
        state.firstAt + Double(index) * interval
    }

    /// When card `index` stops taking taps and is scored, at the latest.
    static func closesAt(_ index: Int, _ state: State) -> Double {
        showAt(index + 1, state) + grace
    }

    /// Thirty cards, `matchCount` of them matches in shuffled places, and no
    /// card the same as the one before it (so every change is visible).
    private static func deal(_ rng: inout OfflineRNG) -> [Card] {
        var matches = Array(repeating: true, count: matchCount)
            + Array(repeating: false, count: cardCount - matchCount)
        rng.shuffle(&matches)
        let hues = Hue.allCases
        var cards: [Card] = []
        for match in matches {
            var card = draw(match: match, hues: hues, rng: &rng)
            var tries = 0
            while card == cards.last && tries < 8 {
                card = draw(match: match, hues: hues, rng: &rng)
                tries += 1
            }
            if card == cards.last {
                // Vanishingly unlikely; step the word on so the card still changes.
                let word = hues[(hues.firstIndex(of: card.word)! + 1) % hues.count]
                let ink = match ? word : (card.ink == word ? card.word : card.ink)
                card = Card(word: word, ink: ink)
            }
            cards.append(card)
        }
        return cards
    }

    private static func draw(match: Bool, hues: [Hue], rng: inout OfflineRNG) -> Card {
        let word = rng.int(below: hues.count)
        let ink = match ? word : (word + 1 + rng.int(below: hues.count - 1)) % hues.count
        return Card(word: hues[word], ink: hues[ink])
    }

    /// Move the card on to the one due at `now`, score every card whose time
    /// is up (or that everyone still here has tapped), and finish once the
    /// last card is scored. Safe to call twice at one instant.
    private static func settle(_ state: inout State, now: Double) {
        guard state.phase == .running else { return }
        let count = state.cards.count
        while state.current < count && now >= showAt(state.current + 1, state) {
            state.current += 1
        }
        while state.scoredThrough + 1 < count {
            let next = state.scoredThrough + 1
            guard next <= state.current else { break }
            let due = now >= closesAt(next, state)
            guard due || everyoneTapped(next, state) else { break }
            score(next, &state)
        }
        if state.scoredThrough >= count - 1 {
            state.phase = .result
            state.resultUntil = now + resultPause
        }
    }

    private static func everyoneTapped(_ card: Int, _ state: State) -> Bool {
        state.players.allSatisfy { player in
            state.away.contains(player.id) || state.marks.contains { $0.card == card && $0.player == player.id }
        }
    }

    /// Score one card: on a match the quickest real reaction takes the bonus
    /// and the other real reactions a point; on a mismatch every tap loses one.
    private static func score(_ index: Int, _ state: inout State) {
        let card = state.cards[index]
        // Seat order, so the table reads the same on every phone.
        let taps = state.players.compactMap { player in
            state.marks.first { $0.card == index && $0.player == player.id }
        }
        var gained: [String: Int] = [:]
        var quickest: [String] = []
        if card.isMatch {
            let real = taps.filter { OfflineReaction.counts($0.ms) }
            let top = real.map(\.ms).min()
            for tap in taps {
                guard OfflineReaction.counts(tap.ms) else {
                    gained[tap.player] = 0
                    continue
                }
                let first = tap.ms == top
                gained[tap.player] = first ? firstPoints : correctPoints
                if first {
                    quickest.append(tap.player)
                    state.quickests[tap.player, default: 0] += 1
                }
                state.right[tap.player, default: 0] += 1
                state.best[tap.player] = min(state.best[tap.player] ?? Int.max, tap.ms)
            }
        } else {
            for tap in taps {
                gained[tap.player] = wrongPoints
                state.wrong[tap.player, default: 0] += 1
            }
        }
        for (player, points) in gained { state.points[player, default: 0] += points }
        state.last = Scored(card: index, match: card.isMatch, points: gained, quickest: quickest)
        state.scoredThrough = index
        // Taps on scored cards are no longer needed.
        state.marks.removeAll { $0.card <= index }
    }

    /// The most points (several on a tie).
    static func champions(_ state: State) -> [String] {
        let present = state.players.map(\.id)
        guard let top = present.map({ state.points[$0] ?? 0 }).max() else { return [] }
        return present.filter { (state.points[$0] ?? 0) == top }
    }
}
