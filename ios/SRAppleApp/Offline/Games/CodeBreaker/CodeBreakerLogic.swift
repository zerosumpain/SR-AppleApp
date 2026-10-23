import Foundation

/// Code Breaker: a Mastermind race for one to five phones.
///
/// The host picks one secret code — four pegs from six colours, repeats
/// allowed — and every player cracks the SAME code on their own phone, at
/// their own pace. Each guess comes back marked by the host: a black peg for
/// each peg of the right colour in the right place, a white peg for each
/// other peg of a right colour in the wrong place. Ten guesses each.
///
/// Whoever cracks it in the fewest guesses wins; equal guesses go to the
/// quicker. Nobody sees anybody else's guesses — only how many each player
/// has used and whether they have cracked it — so watching a neighbour's
/// screen across the room is the only way to cheat. The code is shown to
/// everyone once every player has finished (or the clock runs out), for a
/// few seconds before the table.
///
/// Each colour also has its own shape (`symbols`), so the pegs read without
/// colour, and VoiceOver says both ("red circle").
enum CodeBreakerRules: OfflineGameRules {
    /// Pegs in the code.
    static let codeLength = 4
    /// Colours a peg can be.
    static let colours = 6
    /// Guesses each player gets.
    static let maxGuesses = 10
    /// The whole race, seconds: a stuck or absent player cannot hold the
    /// others up for longer than this.
    static let raceSeconds: Double = 360
    /// How long the code stays up for everyone before the table, seconds.
    static let revealPause: Double = 6

    /// Colour names, by peg value — for VoiceOver and sentences.
    static let colourNames = ["red", "orange", "yellow", "green", "blue", "purple"]
    /// SF Symbols, by peg value: a different shape per colour, so a code
    /// reads for a colour-blind player too.
    static let symbols = ["circle.fill", "triangle.fill", "star.fill", "square.fill", "diamond.fill", "heart.fill"]
    /// Shape names, by peg value, matching `symbols`.
    static let shapeNames = ["circle", "triangle", "star", "square", "diamond", "heart"]

    static let info = OfflineGameInfo(
        id: "code-breaker",
        title: "Code Breaker",
        blurb: "Everyone races to crack the same secret four-peg code.",
        category: .skill,
        minPlayers: 1,
        maxPlayers: 5,
        symbol: "lock.open.fill",
        howToPlay: [
            "The host's phone hides a code of \(codeLength) pegs from \(colours) colours. Colours can repeat.",
            "Everyone guesses the same code on their own phone, at their own pace.",
            "A black peg: right colour, right place. A white peg: right colour, wrong place.",
            "You have \(maxGuesses) guesses. Nobody sees your guesses — only how many you've used.",
            "Fewest guesses wins; on a tie, the quicker crack wins."
        ]
    )

    /// A peg as a sentence: "red circle".
    static func pegName(_ peg: Int) -> String {
        guard peg >= 0, peg < colours else { return "empty" }
        return "\(colourNames[peg]) \(shapeNames[peg])"
    }

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// The race is on.
        case playing
        /// Everyone has finished (or time ran out); the code is up for
        /// everyone until `revealUntil`.
        case reveal
        /// The match is decided.
        case over
    }

    /// One marked guess.
    struct Guess: Codable, Equatable {
        /// Peg values, `0..<colours`, `codeLength` of them.
        let pegs: [Int]
        /// Right colour, right place.
        let black: Int
        /// Right colour, wrong place.
        let white: Int
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left. A guess from one of them means
        /// their phone is back, and it takes them off this list.
        var away: [String] = []
        /// THE SECRET. Never copied into a view while the race runs.
        var secret: [Int]
        var phase: Phase = .playing
        /// Host clock: when the race began, and when it stops regardless.
        var startedAt: Double
        var endsAt: Double
        /// Host clock: when the reveal gives way to the table.
        var revealUntil: Double = 0
        /// Every player's guesses so far, in order. Each player sees only
        /// their own.
        var guesses: [String: [Guess]] = [:]
        /// Host time each solver cracked it.
        var solvedAt: [String: Double] = [:]
    }

    enum Action: Codable, Equatable {
        /// Guess `number` (1 for the first) is `pegs`. The number makes a
        /// repeated send harmless: the host refuses a guess it has counted.
        case guess(number: Int, pegs: [Int])
    }

    // MARK: - What a player sees

    /// One player as everybody may see them: a count, never the guesses.
    struct Row: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        /// Guesses used.
        let used: Int
        let solved: Bool
        /// Used every guess without cracking it.
        let outOfGuesses: Bool
        let away: Bool
        /// Seconds from the start to the crack — only once the race is over.
        let seconds: Int?
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let startedAt: Double
        let endsAt: Double
        let revealUntil: Double
        let codeLength: Int
        let colours: Int
        let maxGuesses: Int
        /// Everyone, in seat order.
        let rows: [Row]
        /// My own guesses with their marks; empty for a spectator.
        let myGuesses: [Guess]
        /// The code — only once the race is over.
        let secret: [Int]?
        /// The players who cracked it, best first — only once the race is over.
        let leaders: [String]
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        let secret = (0..<codeLength).map { _ in rng.int(below: colours) }
        var state = State(players: players, secret: secret, startedAt: now, endsAt: now + raceSeconds)
        for player in players { state.guesses[player.id] = [] }
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard state.players.contains(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not in this game.")
        }
        guard state.phase == .playing else { throw OfflineRefusal("The race is over.") }
        guard now < state.endsAt else { throw OfflineRefusal("Time is up.") }

        switch action {
        case .guess(let number, let pegs):
            let mine = state.guesses[playerId] ?? []
            if number >= 1, number <= mine.count { throw OfflineRefusal("That guess was already counted.") }
            if state.solvedAt[playerId] != nil { throw OfflineRefusal("You have already cracked it.") }
            if mine.count >= maxGuesses { throw OfflineRefusal("You have used all \(maxGuesses) guesses.") }
            if number != mine.count + 1 { throw OfflineRefusal("That guess is out of order.") }
            guard pegs.count == codeLength else { throw OfflineRefusal("A code has \(codeLength) pegs.") }
            guard pegs.allSatisfy({ $0 >= 0 && $0 < colours }) else {
                throw OfflineRefusal("That isn't one of the colours.")
            }

            // A guess from a phone marked away means it has come back.
            state.away.removeAll { $0 == playerId }
            let marks = mark(pegs, against: state.secret)
            state.guesses[playerId] = mine + [Guess(pegs: pegs, black: marks.black, white: marks.white)]
            if marks.black == codeLength { state.solvedAt[playerId] = now }
        }
        if everyoneIsDone(state) { finishRace(&state, now: now) }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .playing:
            if now >= state.endsAt || everyoneIsDone(state) { finishRace(&state, now: now) }
        case .reveal:
            if now >= state.revealUntil { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        if state.phase == .playing, everyoneIsDone(state) { finishRace(&state, now: now) }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let revealed = state.phase != .playing
        let rows = state.players.map { player -> Row in
            let used = state.guesses[player.id]?.count ?? 0
            let solvedAt = state.solvedAt[player.id]
            return Row(
                id: player.id, name: player.name, used: used, solved: solvedAt != nil,
                outOfGuesses: solvedAt == nil && used >= maxGuesses,
                away: state.away.contains(player.id),
                seconds: revealed ? solvedAt.map { seconds(from: state.startedAt, to: $0) } : nil
            )
        }
        let mine: [Guess]
        if let playerId, state.players.contains(where: { $0.id == playerId }) {
            mine = state.guesses[playerId] ?? []
        } else {
            mine = []
        }
        return PlayerView(
            phase: state.phase, startedAt: state.startedAt, endsAt: state.endsAt, revealUntil: state.revealUntil,
            codeLength: codeLength, colours: colours, maxGuesses: maxGuesses,
            rows: rows, myGuesses: mine,
            secret: revealed ? state.secret : nil,
            leaders: revealed ? ranking(state).filter { state.solvedAt[$0] != nil } : []
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    /// Ranked by place: the score is how many players finished behind you
    /// plus one, so the winner of a five-player race scores 5 and everyone
    /// who didn't crack it shares the bottom.
    static func standings(_ state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(state.players, score: { player in
            let mine = sortKey(state, player.id)
            return 1 + state.players.filter { isBetter(mine, than: sortKey(state, $0.id)) }.count
        }, detail: { player in
            let used = state.guesses[player.id]?.count ?? 0
            var parts: [String] = []
            if let at = state.solvedAt[player.id] {
                parts.append(used == 1 ? "cracked in 1 guess" : "cracked in \(used) guesses")
                parts.append(clock(seconds(from: state.startedAt, to: at)))
            } else {
                parts.append("not cracked")
                parts.append(used == 1 ? "1 guess" : "\(used) guesses")
            }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Marking

    /// Black pegs (right colour, right place) and white pegs (right colour,
    /// wrong place) for `guess` against `secret`. Each secret peg answers at
    /// most one guess peg.
    static func mark(_ guess: [Int], against secret: [Int]) -> (black: Int, white: Int) {
        var black = 0
        var guessCounts = Array(repeating: 0, count: colours)
        var secretCounts = Array(repeating: 0, count: colours)
        for (g, s) in zip(guess, secret) {
            if g == s {
                black += 1
            } else {
                if g >= 0 && g < colours { guessCounts[g] += 1 }
                if s >= 0 && s < colours { secretCounts[s] += 1 }
            }
        }
        let white = zip(guessCounts, secretCounts).reduce(0) { $0 + min($1.0, $1.1) }
        return (black, white)
    }

    // MARK: - Helpers

    /// Whole seconds between two host times, never negative.
    static func seconds(from start: Double, to end: Double) -> Int {
        max(0, Int((end - start).rounded(.down)))
    }

    /// "1:05".
    static func clock(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    /// A player has nothing left to do: cracked it, out of guesses, or gone.
    private static func isDone(_ state: State, _ playerId: String) -> Bool {
        state.solvedAt[playerId] != nil
            || (state.guesses[playerId]?.count ?? 0) >= maxGuesses
            || state.away.contains(playerId)
    }

    private static func everyoneIsDone(_ state: State) -> Bool {
        state.players.allSatisfy { isDone(state, $0.id) }
    }

    /// Stop the race and put the code up for everyone.
    private static func finishRace(_ state: inout State, now: Double) {
        state.phase = .reveal
        state.revealUntil = now + revealPause
    }

    /// Comparable place key: solvers first (fewest guesses, then soonest),
    /// everyone else after, all level with each other.
    private struct Key: Equatable {
        let solved: Bool
        let guesses: Int
        let time: Double
    }

    private static func sortKey(_ state: State, _ playerId: String) -> Key {
        if let at = state.solvedAt[playerId] {
            return Key(solved: true, guesses: state.guesses[playerId]?.count ?? 0, time: at)
        }
        return Key(solved: false, guesses: 0, time: 0)
    }

    /// Whether `a` places strictly above `b`.
    private static func isBetter(_ a: Key, than b: Key) -> Bool {
        if a.solved != b.solved { return a.solved }
        guard a.solved else { return false }
        if a.guesses != b.guesses { return a.guesses < b.guesses }
        return a.time < b.time
    }

    /// Player ids, best place first (seat order among equals).
    static func ranking(_ state: State) -> [String] {
        let keyed = state.players.enumerated().map { (seat: $0.offset, id: $0.element.id, key: sortKey(state, $0.element.id)) }
        return keyed.sorted { a, b in
            if isBetter(a.key, than: b.key) { return true }
            if isBetter(b.key, than: a.key) { return false }
            return a.seat < b.seat
        }.map(\.id)
    }
}
