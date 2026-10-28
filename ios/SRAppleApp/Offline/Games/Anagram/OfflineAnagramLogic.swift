import Foundation

/// Anagram Blitz with no internet: seven letters and two minutes to find as
/// many words in them as you can, alone or against up to four phones nearby.
///
/// The site deals the letters from a common seven-letter word, shuffled, so a
/// seven-letter answer always exists; this deals the same way, from the same
/// seeds, bundled with the word list (`OfflineWords`). The host phone judges
/// every word against that list — the site's own — and works out at the deal
/// every word the rack makes, for the reveal.
///
/// Points follow the site: 3 letters 1, 4 letters 2, 5 letters 4, 6 letters 6
/// and all seven 10. With more than one player a word only one of them found
/// scores double; alone there is nobody to be unique against, and the score
/// is a personal best to beat.
///
/// While the clock runs a player sees only their own words and everyone's
/// count and score. When time is up every word is revealed with who found
/// it, the seed word, and the longest common words nobody saw.
enum OfflineAnagramRules: OfflineGameRules {
    static let seconds: Double = 120
    static let countdown: Double = 3
    /// After the clock, how long a word already in the air may still land.
    static let grace: Double = 1
    /// How long the reveal stays up if somebody never taps on.
    static let revealSeconds: Double = 90
    static let letterCount = 7
    static let minLength = 3
    /// The seeds are drawn from the commonest this many (the site's medium).
    static let pool = 400
    /// How many of the longest common words nobody found the reveal shows.
    static let missedShown = 5
    /// Points by length in letters.
    static let pointsTable = [3: 1, 4: 2, 5: 4, 6: 6, 7: 10]
    /// Seeds for a phone whose word list failed to load: the site's commonest.
    static let fallbackSeeds = ["because", "nothing", "someone", "through", "another", "already", "brother",
                                "tonight", "problem", "against", "husband", "trouble", "brought", "outside",
                                "country", "captain", "promise", "perfect", "special", "picture"]

    static let info = OfflineGameInfo(
        id: "anagram-blitz",
        title: "Anagram Blitz",
        blurb: "Seven letters, two minutes. Find as many words in them as you can.",
        category: .skill,
        minPlayers: 1,
        maxPlayers: 5,
        symbol: "textformat.abc",
        howToPlay: [
            "Tap letters to spell a word, then Enter. Each tile once per word.",
            "Words need at least \(minLength) letters. All seven always make a word.",
            "3 letters score 1, 4 score 2, 5 score 4, 6 score 6 and 7 score 10.",
            "With others, a word nobody else found scores double.",
            "Highest score after two minutes wins. Play alone to beat your best."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// "3, 2, 1" until `startsAt`; the letters are hidden.
        case countdown
        case playing
        /// Time is up: every word is shown until everyone taps on.
        case reveal
        case over
    }

    /// A word the rack makes, from the deal.
    struct Possible: Codable, Equatable {
        let word: String
        let common: Bool
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        var away: [String] = []
        /// The seven-letter word the letters were dealt from.
        var seed: String
        /// One lower-case letter a tile.
        var letters: [String]
        /// Every listed word the letters make, longest first then A to Z.
        var possible: [Possible]
        /// Each player's words, in the order found.
        var found: [String: [String]]
        var phase: Phase = .countdown
        var startsAt: Double
        var endsAt: Double
        var revealUntil: Double = 0
        var ready: [String] = []
    }

    enum Action: Codable, Equatable {
        case word(String)
        /// I have seen the reveal.
        case ready
    }

    // MARK: - What a player sees

    struct Word: Codable, Equatable, Identifiable {
        let word: String
        let points: Int
        /// Nobody else found it — only shown at the reveal, with others.
        let unique: Bool

        var id: String { word }
    }

    struct Row: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let words: Int
        let score: Int
        let away: Bool
        let ready: Bool
    }

    struct Reveal: Codable, Equatable, Identifiable {
        let word: String
        /// What it scored each finder: doubled when unique.
        let points: Int
        let finders: [String]
        let unique: Bool

        var id: String { word }
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let startsAt: Double
        let endsAt: Double
        let revealUntil: Double
        /// Nil until the countdown ends.
        let letters: [String]?
        /// My words, newest first; nil for a spectator.
        let mine: [Word]?
        let board: [Row]
        /// The reveal: the seed, every word found, and the best ones missed.
        let seed: String?
        let found: [Reveal]?
        let missed: [String]?
        let possibleWords: Int
        /// More than one player: unique words score double.
        let doubling: Bool
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        let list = OfflineWords.shared.list
        let seeds = list.seeds.isEmpty ? fallbackSeeds : list.seeds
        let seed = seeds[rng.int(below: min(pool, seeds.count))]
        var letters = seed.map { String($0) }
        rng.shuffle(&letters)
        // Never the seed spelled out in order.
        if letters.joined() == seed { letters.append(letters.removeFirst()) }
        var found: [String: [String]] = [:]
        for player in players { found[player.id] = [] }
        return State(players: players, seed: seed, letters: letters, possible: possible(letters, list: list),
                     found: found, startsAt: now + countdown, endsAt: now + countdown + seconds)
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard var mine = state.found[playerId] else { throw OfflineRefusal("You are not in this game.") }
        switch action {
        case .word(let sent):
            guard state.phase == .playing, now < state.endsAt + grace else {
                throw OfflineRefusal(state.phase == .countdown ? "Wait for the start." : "Time's up.")
            }
            let word = sent.trimmingCharacters(in: .whitespaces).lowercased()
            guard word.isEmpty || fits(word, state.letters) else { throw OfflineRefusal("Use only the letters you have.") }
            guard word.count >= minLength else { throw OfflineRefusal("Words need at least \(minLength) letters.") }
            guard !mine.contains(word) else { throw OfflineRefusal("You already have that one.") }
            guard isWord(word, in: state) else { throw OfflineRefusal("Not in the word list.") }
            mine.append(word)
            state.found[playerId] = mine
        case .ready:
            guard state.phase == .reveal else { throw OfflineRefusal("Not yet.") }
            if !state.ready.contains(playerId) { state.ready.append(playerId) }
            if everyoneReady(state) { state.phase = .over }
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .countdown:
            if now >= state.startsAt { state.phase = .playing }
        case .playing:
            if now >= state.endsAt + grace {
                state.phase = .reveal
                state.revealUntil = now + revealSeconds
            }
        case .reveal:
            if now >= state.revealUntil { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        if !state.away.contains(playerId) { state.away.append(playerId) }
        if state.phase == .reveal, everyoneReady(state) { state.phase = .over }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let revealed = state.phase == .reveal || state.phase == .over
        let doubling = state.players.count > 1
        let finders = finders(state)
        let board = state.players
            .map { player -> Row in
                Row(id: player.id, name: player.name, words: state.found[player.id]?.count ?? 0,
                    score: score(player.id, in: state, finders: revealed ? finders : nil),
                    away: state.away.contains(player.id), ready: state.ready.contains(player.id))
            }
            .enumerated()
            .sorted { $0.element.score == $1.element.score ? $0.offset < $1.offset : $0.element.score > $1.element.score }
            .map(\.element)
        var mine: [Word]?
        if let playerId, let words = state.found[playerId] {
            mine = words.reversed().map { word in
                let unique = revealed && doubling && finders[word]?.count == 1
                return Word(word: word, points: points(word) * (unique ? 2 : 1), unique: unique)
            }
        }
        var reveal: [Reveal]?
        var missed: [String]?
        if revealed {
            reveal = order(Array(finders.keys)).map { word in
                let who = finders[word] ?? []
                let unique = doubling && who.count == 1
                return Reveal(word: word, points: points(word) * (unique ? 2 : 1), finders: who, unique: unique)
            }
            missed = Array(state.possible.lazy.filter { $0.common && finders[$0.word] == nil }.map(\.word).prefix(missedShown))
        }
        return PlayerView(
            phase: state.phase, startsAt: state.startsAt, endsAt: state.endsAt, revealUntil: state.revealUntil,
            letters: state.phase == .countdown ? nil : state.letters,
            mine: mine, board: board,
            seed: revealed ? state.seed : nil, found: reveal, missed: missed,
            possibleWords: revealed ? state.possible.count : 0,
            doubling: doubling
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        let finders = finders(state)
        return OfflineStanding.ranked(state.players, score: { score($0.id, in: state, finders: finders) }, detail: { player in
            let words = state.found[player.id] ?? []
            var parts = [words.count == 1 ? "1 word" : "\(words.count) words"]
            if words.contains(state.seed) { parts.append("found \(state.seed.uppercased())") }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Words

    static func points(_ word: String) -> Int { pointsTable[word.count] ?? 0 }

    /// Every letter of `word` used no more often than the tiles hold it.
    static func fits(_ word: String, _ letters: [String]) -> Bool {
        guard !word.isEmpty else { return false }
        var left: [Character: Int] = [:]
        for letter in letters { for character in letter { left[character, default: 0] += 1 } }
        for character in word {
            guard let count = left[character], count > 0 else { return false }
            left[character] = count - 1
        }
        return true
    }

    /// Every listed word of `minLength` to seven letters the tiles make,
    /// longest first then A to Z.
    static func possible(_ letters: [String], list: OfflineWordList) -> [Possible] {
        var counts = Array(repeating: 0, count: 26)
        for scalar in letters.joined().unicodeScalars {
            let index = Int(scalar.value) - 97
            if index >= 0, index < 26 { counts[index] += 1 }
        }
        var out: [Possible] = []
        for index in 0..<list.count {
            let length = list.length(at: index)
            guard length >= minLength, length <= letters.count, list.fits(at: index, counts: counts) else { continue }
            out.append(Possible(word: list.word(at: index), common: list.isCommon(at: index)))
        }
        return out.sorted { $0.word.count == $1.word.count ? $0.word < $1.word : $0.word.count > $1.word.count }
    }

    /// Who found each word, in seat order.
    static func finders(_ state: State) -> [String: [String]] {
        var by: [String: [String]] = [:]
        for player in state.players {
            for word in state.found[player.id] ?? [] { by[word, default: []].append(player.id) }
        }
        return by
    }

    /// Raw points while playing (`finders` nil); with others, unique words
    /// doubled once there is a reveal.
    static func score(_ playerId: String, in state: State, finders: [String: [String]]?) -> Int {
        let doubling = state.players.count > 1
        return (state.found[playerId] ?? []).reduce(0) { sum, word in
            let unique = doubling && finders?[word]?.count == 1
            return sum + points(word) * (unique ? 2 : 1)
        }
    }

    /// Longest first, then A to Z.
    static func order(_ words: [String]) -> [String] {
        words.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
    }

    private static func everyoneReady(_ state: State) -> Bool {
        state.players.allSatisfy { state.ready.contains($0.id) || state.away.contains($0.id) }
    }

    /// In the list — or, on a phone whose list failed to load, fitting the
    /// tiles is enough: a game that accepts too much beats one that accepts nothing.
    private static func isWord(_ word: String, in state: State) -> Bool {
        if word == state.seed || state.possible.contains(where: { $0.word == word }) { return true }
        let list = OfflineWords.shared.list
        return list.isEmpty || list.contains(word)
    }
}
