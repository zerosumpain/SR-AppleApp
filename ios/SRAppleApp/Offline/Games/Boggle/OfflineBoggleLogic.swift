import Foundation

/// Boggle with no internet: sixteen letter dice and two minutes, alone or
/// against up to four phones in the room.
///
/// The site's Boggle judges words on the server; this one judges them on the
/// host phone, against the word list bundled with the app (`OfflineWords`),
/// which is the site's own list cut to nine letters — so a word counts here
/// when it would count there. Everyone traces on the same roll. The board is
/// solved when it is rolled: a poor roll (fewer than `floor` common words) is
/// rolled again, and the reveal can show the best words nobody found.
///
/// Scoring is the site's: a point a letter past two ("qu" is two letters).
/// With more than one player, a word two or more of them found is crossed out
/// for all of them, so it pays to hunt the odd ones; alone, every word counts
/// and the score is a personal best to beat.
///
/// While the clock runs a player's view carries only their own words; the
/// others are a count and a score. When time is up everything is revealed and
/// stays up until everyone taps on (or `revealSeconds` pass).
enum OfflineBoggleRules: OfflineGameRules {
    static let size = 4
    static let seconds: Double = 120
    /// Seconds of "3, 2, 1" before the dice show.
    static let countdown: Double = 3
    /// After the clock, how long a word already in the air may still land.
    static let grace: Double = 1
    /// How long the reveal stays up if somebody never taps on.
    static let revealSeconds: Double = 90
    static let minLength = 3
    /// How many of the best words nobody found the reveal shows.
    static let missedShown = 10
    /// Common words a roll must hold. The site measured medium's 40 as turning
    /// away the poorest quarter of 4×4 rolls.
    static let floor = 40
    /// Rolls tried before the richest one so far is taken anyway.
    static let maxRolls = 12

    /// The 1987 set of sixteen dice, six faces each; "qu" is one face.
    static let dice: [[String]] = [
        "a a e e g n", "a b b j o o", "a c h o p s", "a f f k p s",
        "a o o t t w", "c i m o t u", "d e i l r x", "d e l r v y",
        "d i s t t y", "e e g h n w", "e e i n s u", "e h r t v w",
        "e i o s s t", "e l r t t y", "h i m n qu u", "h l n n r z",
    ].map { $0.split(separator: " ").map(String.init) }

    static let info = OfflineGameInfo(
        id: "boggle",
        title: "Boggle",
        blurb: "Sixteen letter dice, two minutes. Trace words through touching letters.",
        category: .skill,
        minPlayers: 1,
        maxPlayers: 5,
        symbol: "square.grid.4x3.fill",
        howToPlay: [
            "Drag through touching letters — sideways, up, down or diagonal — and lift to send the word.",
            "Each die once per word. Words need at least \(minLength) letters.",
            "A point for every letter past two: CAT 1, TRAIN 3, PLANTS 4.",
            "With others, a word somebody else also found is crossed out for both of you.",
            "Highest score after two minutes wins. Play alone to beat your best."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// "3, 2, 1" until `startsAt`; the dice are hidden.
        case countdown
        case playing
        /// Time is up: every word is shown until everyone taps on.
        case reveal
        case over
    }

    /// A word on the board, and one way to trace it.
    struct Traced: Codable, Equatable {
        let word: String
        let path: [Int]
        let common: Bool
    }

    struct Found: Codable, Equatable {
        let word: String
        let path: [Int]
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        var away: [String] = []
        /// Faces, row by row: "a", "qu".
        var grid: [String]
        /// Every listed word the board holds, longest first then A to Z.
        var solution: [Traced]
        /// Each player's words, in the order found.
        var found: [String: [Found]]
        var phase: Phase = .countdown
        var startsAt: Double
        var endsAt: Double
        var revealUntil: Double = 0
        /// Who has tapped on from the reveal.
        var ready: [String] = []
    }

    enum Action: Codable, Equatable {
        /// The tiles I traced, in order.
        case word(path: [Int])
        /// I have seen the reveal.
        case ready
    }

    // MARK: - What a player sees

    struct Word: Codable, Equatable, Identifiable {
        let word: String
        /// What it scores me: 0 once crossed out.
        let points: Int
        let path: [Int]
        /// Somebody else found it too — only shown at the reveal.
        let shared: Bool

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

    /// One word somebody found, at the reveal.
    struct Reveal: Codable, Equatable, Identifiable {
        let word: String
        let points: Int
        let finders: [String]
        /// Crossed out: more than one player found it.
        let crossed: Bool
        let path: [Int]

        var id: String { word }
    }

    struct Missed: Codable, Equatable, Identifiable {
        let word: String
        let points: Int
        let path: [Int]

        var id: String { word }
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let startsAt: Double
        let endsAt: Double
        let revealUntil: Double
        /// Nil until the dice are rolled out of the countdown.
        let grid: [String]?
        /// My words, newest first; nil for a spectator.
        let mine: [Word]?
        /// Everyone, best score first.
        let board: [Row]
        /// The reveal: every word found, best first. Nil while playing.
        let found: [Reveal]?
        let missed: [Missed]?
        /// How many words, and points, the board held.
        let possibleWords: Int
        let possiblePoints: Int
        /// More than one player: shared words cross out.
        let crossing: Bool
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        let list = OfflineWords.shared.list
        var best: (grid: [String], solution: [Traced], rich: Int)?
        for _ in 0..<maxRolls {
            let grid = roll(&rng)
            let solution = solve(grid, list: list)
            let rich = solution.filter(\.common).count
            if best == nil || rich > best!.rich { best = (grid, solution, rich) }
            if rich >= floor { break }
        }
        var found: [String: [Found]] = [:]
        for player in players { found[player.id] = [] }
        return State(players: players, grid: best!.grid, solution: best!.solution, found: found,
                     startsAt: now + countdown, endsAt: now + countdown + seconds)
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard var mine = state.found[playerId] else { throw OfflineRefusal("You are not in this game.") }
        switch action {
        case .word(let path):
            guard state.phase == .playing, now < state.endsAt + grace else {
                throw OfflineRefusal(state.phase == .countdown ? "Wait for the start." : "Time's up.")
            }
            guard isPath(path) else { throw OfflineRefusal("That word isn't on the board.") }
            let word = path.map { state.grid[$0] }.joined()
            guard word.count >= minLength else { throw OfflineRefusal("Words need at least \(minLength) letters.") }
            guard !mine.contains(where: { $0.word == word }) else { throw OfflineRefusal("You already have that one.") }
            guard isWord(word, in: state) else { throw OfflineRefusal("Not in the word list.") }
            mine.append(Found(word: word, path: path))
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
        let crossing = state.players.count > 1
        let finders = finders(state)
        let board = state.players
            .map { player -> Row in
                let words = state.found[player.id] ?? []
                return Row(id: player.id, name: player.name, words: words.count,
                           score: score(player.id, in: state, finders: revealed ? finders : nil),
                           away: state.away.contains(player.id), ready: state.ready.contains(player.id))
            }
            .enumerated()
            .sorted { $0.element.score == $1.element.score ? $0.offset < $1.offset : $0.element.score > $1.element.score }
            .map(\.element)
        var mine: [Word]?
        if let playerId, let words = state.found[playerId] {
            mine = words.reversed().map { found in
                let shared = revealed && crossing && (finders[found.word]?.count ?? 0) > 1
                return Word(word: found.word, points: shared ? 0 : points(found.word), path: found.path, shared: shared)
            }
        }
        var reveal: [Reveal]?
        var missed: [Missed]?
        if revealed {
            reveal = order(Array(finders.keys)).map { word in
                let who = finders[word] ?? []
                let path = state.players.lazy.compactMap { player in
                    state.found[player.id]?.first(where: { $0.word == word })?.path
                }.first ?? []
                return Reveal(word: word, points: points(word), finders: who, crossed: crossing && who.count > 1, path: path)
            }
            missed = Array(state.solution.lazy.filter { $0.common && finders[$0.word] == nil }.prefix(missedShown))
                .map { Missed(word: $0.word, points: points($0.word), path: $0.path) }
        }
        return PlayerView(
            phase: state.phase, startsAt: state.startsAt, endsAt: state.endsAt, revealUntil: state.revealUntil,
            grid: state.phase == .countdown ? nil : state.grid,
            mine: mine, board: board, found: reveal, missed: missed,
            possibleWords: revealed ? state.solution.count : 0,
            possiblePoints: revealed ? state.solution.reduce(0) { $0 + points($1.word) } : 0,
            crossing: crossing
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        let finders = finders(state)
        return OfflineStanding.ranked(state.players, score: { score($0.id, in: state, finders: finders) }, detail: { player in
            let words = state.found[player.id] ?? []
            var parts = [words.count == 1 ? "1 word" : "\(words.count) words"]
            if let longest = longest(words) { parts.append("longest \(longest.uppercased())") }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Scoring

    /// A point a letter past two; "qu" counts as the two letters it is.
    static func points(_ word: String) -> Int { max(0, word.count - 2) }

    /// Who found each word, in seat order.
    static func finders(_ state: State) -> [String: [String]] {
        var by: [String: [String]] = [:]
        for player in state.players {
            for found in state.found[player.id] ?? [] { by[found.word, default: []].append(player.id) }
        }
        return by
    }

    /// A player's score: the raw points while playing (`finders` nil), and
    /// with shared words crossed out once there is a reveal and other players.
    static func score(_ playerId: String, in state: State, finders: [String: [String]]?) -> Int {
        let crossing = state.players.count > 1
        return (state.found[playerId] ?? []).reduce(0) { sum, found in
            if crossing, let finders, (finders[found.word]?.count ?? 0) > 1 { return sum }
            return sum + points(found.word)
        }
    }

    /// The first-found of the longest words.
    static func longest(_ words: [Found]) -> String? {
        var best: String?
        for found in words where found.word.count > (best?.count ?? 0) { best = found.word }
        return best
    }

    /// Longest first, then A to Z — the order the site lists words in.
    static func order(_ words: [String]) -> [String] {
        words.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
    }

    private static func everyoneReady(_ state: State) -> Bool {
        state.players.allSatisfy { state.ready.contains($0.id) || state.away.contains($0.id) }
    }

    /// In the list — or, on a phone whose list failed to load, on the board
    /// is enough: a game that accepts too much beats one that accepts nothing.
    private static func isWord(_ word: String, in state: State) -> Bool {
        if state.solution.contains(where: { $0.word == word }) { return true }
        let list = OfflineWords.shared.list
        return list.isEmpty || list.contains(word)
    }

    // MARK: - The board

    /// Every die in a random place showing a random face.
    static func roll(_ rng: inout OfflineRNG) -> [String] {
        var order = dice
        rng.shuffle(&order)
        return order.map { rng.pick($0) ?? "e" }
    }

    /// The tiles touching `tile`, diagonals included, in reading order.
    static func neighbours(_ tile: Int) -> [Int] {
        let row = tile / size, column = tile % size
        var out: [Int] = []
        for dr in -1...1 {
            for dc in -1...1 where dr != 0 || dc != 0 {
                let r = row + dr, c = column + dc
                if r >= 0, r < size, c >= 0, c < size { out.append(r * size + c) }
            }
        }
        return out
    }

    /// A trace the rules accept: tiles on the board, each once, each touching
    /// the one before.
    static func isPath(_ path: [Int]) -> Bool {
        guard !path.isEmpty, Set(path).count == path.count,
              path.allSatisfy({ $0 >= 0 && $0 < size * size }) else { return false }
        return zip(path, path.dropFirst()).allSatisfy { neighbours($0).contains($1) }
    }

    /// Every listed word of `minLength` letters or more on this board, with
    /// the first path found for each, longest first then A to Z.
    static func solve(_ grid: [String], list: OfflineWordList) -> [Traced] {
        guard !list.isEmpty, grid.count == size * size else { return [] }
        let faces = grid.map { Array($0.utf8) }
        let adjacent = (0..<grid.count).map(neighbours)
        var found: [String: Traced] = [:]
        var used = Array(repeating: false, count: grid.count)
        var letters: [UInt8] = []
        var path: [Int] = []

        func walk(_ tile: Int) {
            letters.append(contentsOf: faces[tile])
            defer { letters.removeLast(faces[tile].count) }
            guard letters.count <= OfflineWordList.longest, list.hasPrefix(letters) else { return }
            used[tile] = true
            path.append(tile)
            defer {
                used[tile] = false
                path.removeLast()
            }
            if letters.count >= minLength, let index = list.index(of: letters) {
                let word = list.word(at: index)
                if found[word] == nil { found[word] = Traced(word: word, path: path, common: list.isCommon(at: index)) }
            }
            for next in adjacent[tile] where !used[next] { walk(next) }
        }

        for tile in 0..<grid.count { walk(tile) }
        return order(Array(found.keys)).compactMap { found[$0] }
    }
}
