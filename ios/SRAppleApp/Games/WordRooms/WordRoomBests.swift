import Foundation

// Wordle Race, Anagram Blitz and Boggle: the personal bests this phone keeps
// for each, and the small rules their screens share — what the word being
// built is worth right now, who is still playing, how hurried the clock is,
// how big a Wordle tile can be — as pure values, so each is a unit test.
//
// The server judges every word and every guess and keeps the family's high
// scores. These bests are only mine, only on this phone, and are there with
// or without a signal: the results card reads them the moment a round ends.

/// Which word room a book belongs to. The raw value is the game's wire id,
/// and so the prefix of the book's key.
enum WordRoomGame: String, CaseIterable {
    case wordle = "wordle-race"
    case anagram = "anagram-blitz"
    case boggle = "boggle"
}

/// One finished round, as the bests see it.
struct WordRoomRound: Equatable {
    /// Which round this was. The same round seen twice (the results page
    /// opened again, the stream re-sent) is counted once.
    var key: String
    /// Against somebody. A solo round is played, never won.
    var competitive: Bool
    var won: Bool
    /// Points: Anagram Blitz and Boggle.
    var score: Int = 0
    var words: Int = 0
    /// The longest word found, lower-case; empty for none.
    var longest: String = ""
    /// Wordle Race: solves in a row are a streak, and a miss ends it.
    var tracksStreak: Bool = false
    var solved: Bool = false
    var guesses: Int = 0
    var solveMs: Int? = nil

    /// "g_abc|1730000000000|grape": the room, when its round started, and
    /// what was dealt — "Play again" in the same room is a new round.
    static func key(roomId: String, startedAt: Double?, deal: String) -> String {
        let start = startedAt.map { String(Int64($0.rounded())) } ?? "0"
        return "\(roomId)|\(start)|\(deal)"
    }
}

/// What a round improved, for the results card's "New best" line. Nothing is
/// ever new on the first round counted: a best needs something to beat.
struct WordRoomNewBests: Equatable {
    var score = false
    var longest = false
    var guesses = false
    var time = false
    var streak = false

    var any: Bool { score || longest || guesses || time || streak }
}

/// My bests in one word room.
struct WordRoomBestBook: Codable, Equatable {
    var played = 0
    /// Rounds won against somebody.
    var won = 0
    var bestScore = 0
    var bestWords = 0
    /// Lower-case.
    var longest = ""
    // Wordle Race.
    var solved = 0
    /// Fewest guesses in a solve; 0 until something is solved.
    var fewestGuesses = 0
    /// Fastest solve; 0 until something is solved.
    var fastestMs = 0
    /// Solves in a row, and the best run of them.
    var streak = 0
    var bestStreak = 0
    /// Rounds already counted, newest last, so none is counted twice.
    var counted: [String] = []

    /// How many round keys are remembered.
    static let memory = 40

    init() {}

    /// Counts a finished round. Nil (and nothing changes) when it was
    /// already counted or has no key.
    @discardableResult
    mutating func record(_ round: WordRoomRound) -> WordRoomNewBests? {
        guard !round.key.isEmpty, !counted.contains(round.key) else { return nil }
        counted.append(round.key)
        if counted.count > Self.memory { counted.removeFirst(counted.count - Self.memory) }

        let veteran = played > 0
        var news = WordRoomNewBests()
        played += 1
        if round.competitive && round.won { won += 1 }

        if round.score > bestScore {
            news.score = veteran
            bestScore = round.score
        }
        bestWords = max(bestWords, round.words)
        if round.longest.count > longest.count {
            news.longest = veteran
            longest = round.longest.lowercased()
        }

        if round.solved {
            solved += 1
            streak += 1
            if streak > bestStreak {
                news.streak = veteran && bestStreak > 0
                bestStreak = streak
            }
            if round.guesses > 0, fewestGuesses == 0 || round.guesses < fewestGuesses {
                news.guesses = veteran && fewestGuesses > 0
                fewestGuesses = round.guesses
            }
            if let ms = round.solveMs, ms > 0, fastestMs == 0 || ms < fastestMs {
                news.time = veteran && fastestMs > 0
                fastestMs = ms
            }
        } else if round.tracksStreak {
            // A Wordle round not solved breaks the run.
            streak = 0
        }
        return news
    }

    /// Share of rounds won against somebody, 0...100.
    var winPercent: Int {
        played > 0 ? Int((Double(won) / Double(played) * 100).rounded()) : 0
    }

    // Decoded field by field so a book written by an older build, or one
    // missing a field a newer build added, still opens.
    private enum CodingKeys: String, CodingKey {
        case played, won, bestScore, bestWords, longest, solved, fewestGuesses, fastestMs
        case streak, bestStreak, counted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        played = (try? c.decodeIfPresent(Int.self, forKey: .played)) ?? 0
        won = (try? c.decodeIfPresent(Int.self, forKey: .won)) ?? 0
        bestScore = (try? c.decodeIfPresent(Int.self, forKey: .bestScore)) ?? 0
        bestWords = (try? c.decodeIfPresent(Int.self, forKey: .bestWords)) ?? 0
        longest = (try? c.decodeIfPresent(String.self, forKey: .longest)) ?? ""
        solved = (try? c.decodeIfPresent(Int.self, forKey: .solved)) ?? 0
        fewestGuesses = (try? c.decodeIfPresent(Int.self, forKey: .fewestGuesses)) ?? 0
        fastestMs = (try? c.decodeIfPresent(Int.self, forKey: .fastestMs)) ?? 0
        streak = (try? c.decodeIfPresent(Int.self, forKey: .streak)) ?? 0
        bestStreak = (try? c.decodeIfPresent(Int.self, forKey: .bestStreak)) ?? 0
        counted = (try? c.decodeIfPresent([String].self, forKey: .counted)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(played, forKey: .played)
        try c.encode(won, forKey: .won)
        try c.encode(bestScore, forKey: .bestScore)
        try c.encode(bestWords, forKey: .bestWords)
        try c.encode(longest, forKey: .longest)
        try c.encode(solved, forKey: .solved)
        try c.encode(fewestGuesses, forKey: .fewestGuesses)
        try c.encode(fastestMs, forKey: .fastestMs)
        try c.encode(streak, forKey: .streak)
        try c.encode(bestStreak, forKey: .bestStreak)
        try c.encode(counted, forKey: .counted)
    }
}

/// Where a book lives: UserDefaults, under the game's id. Boggle keeps one
/// book per board size (`variant` "4x4"), since a 6×6 score dwarfs a 4×4's.
struct WordRoomBestStore {
    var defaults: UserDefaults = .standard
    let game: WordRoomGame
    var variant: String = ""

    /// "wordle-race.bests.v1", "boggle.bests.5x5.v1".
    var key: String {
        variant.isEmpty ? "\(game.rawValue).bests.v1" : "\(game.rawValue).bests.\(variant).v1"
    }

    func load() -> WordRoomBestBook {
        guard let data = defaults.data(forKey: key),
              let book = try? JSONDecoder().decode(WordRoomBestBook.self, from: data) else { return WordRoomBestBook() }
        return book
    }

    func save(_ book: WordRoomBestBook) {
        if let data = try? JSONEncoder().encode(book) { defaults.set(data, forKey: key) }
    }

    /// Loads, counts the round, saves. `persist` false (the demo) counts it
    /// in memory only. The news is nil when the round was already counted.
    @discardableResult
    func record(_ round: WordRoomRound, persist: Bool = true) -> (book: WordRoomBestBook, news: WordRoomNewBests?) {
        var book = load()
        let news = book.record(round)
        if news != nil, persist { save(book) }
        return (book, news)
    }
}

// MARK: - The rules the screens share

/// What the word being built is worth right now, for the chip beside it.
enum WordRoomWordState: Equatable {
    /// Nothing built yet.
    case empty
    /// Short of the minimum by this many letters.
    case short(Int)
    /// Already one of mine.
    case have
    /// Would score this many points.
    case worth(Int)

    /// `word` lower-case; `points` what it would score if it counts.
    static func of(word: String, minLength: Int, mine: [String], points: Int) -> WordRoomWordState {
        if word.isEmpty { return .empty }
        if word.count < minLength { return .short(minLength - word.count) }
        if mine.contains(word.lowercased()) { return .have }
        return .worth(points)
    }

    /// "+4", "Have it", "2 more letters", "".
    var text: String {
        switch self {
        case .empty: return ""
        case .short(let n): return n == 1 ? "1 more letter" : "\(n) more letters"
        case .have: return "Have it"
        case .worth(let points): return "+\(points)"
        }
    }

    var ready: Bool {
        if case .worth = self { return true }
        return false
    }
}

/// How hurried the clock is, for its colour and the one tap at the end.
enum WordRoomUrgency: Int, Comparable {
    case calm, hurry, last

    /// `last` in the final ten seconds; `hurry` in the final 30 seconds or
    /// quarter of the limit, whichever comes first.
    static func of(msLeft: Double?, limitMs: Double?) -> WordRoomUrgency {
        guard let left = msLeft else { return .calm }
        if left <= 10_000 { return .last }
        if left <= 30_000 { return .hurry }
        if let limit = limitMs, limit > 0, left / limit <= 0.25 { return .hurry }
        return .calm
    }

    static func < (a: WordRoomUrgency, b: WordRoomUrgency) -> Bool { a.rawValue < b.rawValue }
}

enum WordRoomText {
    /// "Sam", "Sam and Robin", "Sam, Robin and Kit"; "" for nobody.
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }

    /// "five", for "a five-letter word"; digits past twelve.
    static func number(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
        return n >= 0 && n < words.count ? words[n] : "\(n)"
    }

    /// The one line that says what to do next in Wordle Race.
    static func wordleHint(typed: Int, length: Int, guessNumber: Int) -> String {
        if typed >= length { return "Press Enter to guess" }
        if typed > 0 {
            let left = length - typed
            return left == 1 ? "1 more letter" : "\(left) more letters"
        }
        if guessNumber <= 1 { return "Type any \(number(length))-letter word to start" }
        return "Use the colours: green stays, yellow moves"
    }

    /// "1:23" from milliseconds; "–" for none.
    static func clock(ms: Int) -> String {
        guard ms > 0 else { return "–" }
        let seconds = ms / 1000
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

/// Everyone else in score order: most points first, then by name, so the
/// strip reads like a leaderboard and never jumps between equal scores.
enum WordRoomRanking {
    struct Entry: Equatable {
        let id: String
        let name: String
        let score: Int
    }

    static func order(_ entries: [Entry]) -> [String] {
        entries.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.name != b.name { return a.name < b.name }
            return a.id < b.id
        }
        .map(\.id)
    }

    /// The leader's id, or nil when nobody has scored or the top is a tie.
    static func leader(_ entries: [Entry]) -> String? {
        let top = entries.map(\.score).max() ?? 0
        guard top > 0 else { return nil }
        let leaders = entries.filter { $0.score == top }
        return leaders.count == 1 ? leaders[0].id : nil
    }
}

/// How big a Wordle tile can be in the space the screen has for the grid.
enum WordRoomLayout {
    /// Gap between tiles, as a share of a tile's side.
    static let gapRatio = 0.12

    /// The largest side for which `wordLength` tiles fit `width` and
    /// `maxGuesses` rows fit `height`, gaps included; never below `floor`
    /// (the page scrolls instead) nor above `cap`.
    static func wordleTileSide(width: Double, height: Double, wordLength: Int, maxGuesses: Int,
                               floor: Double = 30, cap: Double = 62) -> Double {
        let n = Double(max(wordLength, 1))
        let rows = Double(max(maxGuesses, 1))
        let across = width / (n + gapRatio * (n - 1))
        let down = height / (rows + gapRatio * (rows - 1))
        let side = min(across, down).rounded(.down)
        return max(floor, min(cap, side))
    }
}
