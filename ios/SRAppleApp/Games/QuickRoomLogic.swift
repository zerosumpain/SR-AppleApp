import Foundation

// The quick room games' phone-side extras — Tap Duel, Quick Maths Sprint and
// Sequence Memory: personal bests kept on this phone, and the small sums their
// screens draw from (a reaction's rating, a place in the table, how much of the
// clock is left, where an attempt went wrong). Pure values, so each is a unit
// test; nothing here travels to the site or changes what the server decides.

// MARK: - Personal bests

/// What a finished game did to a personal best.
struct QuickRoomBestNote: Equatable {
    /// The best before this game, if there was one.
    let previous: Int?
    /// The best now.
    let best: Int?
    /// This game set it.
    let isNew: Bool
}

/// One game's personal best at one difficulty, with enough history to answer
/// the same way when the results page is shown twice for the same game.
struct QuickRoomRecord: Codable, Equatable {
    var best: Int?
    /// The best before the game that set `best`.
    var previous: Int?
    /// The game that set `best`.
    var bestToken: String?
    var games = 0
    /// The last few games recorded, so a results page that appears again
    /// (back from the background, a fresh frame) does not count twice.
    var seen: [String] = []

    static let remembered = 24

    /// Records a finished game's figure. `higherIsBetter` false is a time,
    /// where lower wins. A figure of zero or less is "nothing to count" (no
    /// valid tap, no points, no sequence repeated) and never a best.
    mutating func record(_ value: Int?, token: String, higherIsBetter: Bool) -> QuickRoomBestNote {
        if seen.contains(token) {
            let isNew = bestToken == token
            return QuickRoomBestNote(previous: isNew ? previous : best, best: best, isNew: isNew)
        }
        seen.append(token)
        if seen.count > Self.remembered { seen.removeFirst(seen.count - Self.remembered) }
        games += 1
        guard let value, value > 0 else {
            return QuickRoomBestNote(previous: best, best: best, isNew: false)
        }
        let better: Bool
        if let current = best {
            better = higherIsBetter ? value > current : value < current
        } else {
            better = true
        }
        guard better else { return QuickRoomBestNote(previous: best, best: best, isNew: false) }
        previous = best
        best = value
        bestToken = token
        return QuickRoomBestNote(previous: previous, best: value, isNew: true)
    }
}

/// Where one game's bests live: a small JSON map of difficulty to record in
/// UserDefaults, under a key that starts with the game's id.
struct QuickRoomBestStore {
    let key: String
    /// Lower wins (a reaction time) or higher wins (points, a length).
    let higherIsBetter: Bool
    var defaults: UserDefaults = .standard

    static let tapDuel = QuickRoomBestStore(key: "tapduel.bests.v1", higherIsBetter: false)
    static let sprint = QuickRoomBestStore(key: "sprint.bests.v1", higherIsBetter: true)
    static let memory = QuickRoomBestStore(key: "memory.bests.v1", higherIsBetter: true)

    func load() -> [String: QuickRoomRecord] {
        guard let data = defaults.data(forKey: key),
              let book = try? JSONDecoder().decode([String: QuickRoomRecord].self, from: data) else { return [:] }
        return book
    }

    func save(_ book: [String: QuickRoomRecord]) {
        if let data = try? JSONEncoder().encode(book) { defaults.set(data, forKey: key) }
    }

    /// The best at a difficulty, or nil before the first counted game.
    func best(difficulty: String) -> Int? {
        load()[difficulty]?.best
    }

    /// Games recorded on this phone, every difficulty together — the lobby
    /// folds its rules away for somebody who has played a few.
    func gamesPlayed() -> Int {
        load().values.reduce(0) { $0 + $1.games }
    }

    /// Records a finished game and saves at once.
    @discardableResult
    func record(_ value: Int?, difficulty: String, token: String) -> QuickRoomBestNote {
        var book = load()
        var entry = book[difficulty] ?? QuickRoomRecord()
        let note = entry.record(value, token: token, higherIsBetter: higherIsBetter)
        book[difficulty] = entry
        save(book)
        return note
    }
}

// MARK: - Places

enum QuickRoomPlace {
    /// "1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st".
    static func ordinal(_ n: Int) -> String {
        let tens = (n / 10) % 10
        let unit = n % 10
        if tens == 1 { return "\(n)th" }
        switch unit {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    /// A player's place by score, highest first. Ties share a place: two on
    /// 9 points ahead of one on 6 are both 1st, and the 6 is 3rd. Nil for an
    /// id that is not in the list.
    static func place(of id: String, scores: [(id: String, score: Int)]) -> Int? {
        guard let mine = scores.first(where: { $0.id == id }) else { return nil }
        return 1 + scores.filter { $0.score > mine.score }.count
    }
}

// MARK: - Tap Duel

enum TapDuelRating {
    /// A word for a reaction, quickest first. Under the anticipation floor the
    /// server calls it a false start, and so does this.
    static func label(ms: Int, floor: Int = 100) -> String {
        if ms < floor { return "Too quick to count" }
        if ms < 200 { return "Lightning" }
        if ms < 250 { return "Rapid" }
        if ms < 300 { return "Sharp" }
        if ms < 400 { return "Quick" }
        if ms < 550 { return "Steady" }
        return "Sleepy"
    }

    /// Where a reaction sits on the meter, 0 (the floor) to 1 (`slowest`).
    static func meter(ms: Int, floor: Int = 100, slowest: Int = 600) -> Double {
        guard slowest > floor else { return 0 }
        let share = Double(ms - floor) / Double(slowest - floor)
        return min(1, max(0, share))
    }

    /// The right-hand end of the round's time axis: a little past the slowest
    /// valid tap, rounded up to 100 ms, and never under 400 ms so one quick
    /// round does not look slow.
    static func axisMs(times: [Int]) -> Int {
        guard let slowest = times.max() else { return 400 }
        let padded = Double(slowest) * 1.15
        let rounded = Int((padded / 100).rounded(.up)) * 100
        return max(400, rounded)
    }

    /// Where a time sits on that axis, 0...1.
    static func share(ms: Int, axis: Int) -> Double {
        guard axis > 0 else { return 0 }
        return min(1, max(0, Double(ms) / Double(axis)))
    }
}

// MARK: - Quick Maths Sprint

enum SprintGauge {
    /// How much of the clock is left, 0...1. A total of zero or less is unknown
    /// and reads as full, so a missing limit never shows an empty bar.
    static func timeShare(msLeft: Double, totalMs: Double) -> Double {
        guard totalMs > 0 else { return 1 }
        return min(1, max(0, msLeft / totalMs))
    }

    /// Right answers out of every answer, as a whole percentage. Nil before
    /// the first answer.
    static func accuracy(correct: Int, misses: Int) -> Int? {
        let total = correct + misses
        guard total > 0 else { return nil }
        return Int((Double(correct) * 100 / Double(total)).rounded())
    }

    /// The streak's pips towards the next bonus: how many are lit of `every`.
    /// A streak sitting on a bonus lights them all.
    static func lit(streak: Int, every: Int) -> Int {
        guard every > 0, streak > 0 else { return 0 }
        let into = streak % every
        return into == 0 ? every : into
    }
}

// MARK: - Sequence Memory

enum SequenceCompare {
    /// Position by position, whether a tap matched the sequence. As long as
    /// the taps; a tap past the end of the sequence is wrong.
    static func marks(sequence: [Int], taps: [Int]) -> [Bool] {
        taps.enumerated().map { index, tile in index < sequence.count && sequence[index] == tile }
    }

    /// The first step that went wrong, or nil when every tap matched (a short
    /// attempt with nothing wrong in it has no first mistake either).
    static func firstMistake(sequence: [Int], taps: [Int]) -> Int? {
        marks(sequence: sequence, taps: taps).firstIndex(of: false)
    }

    /// How much of the input window is left, 0...1.
    static func windowShare(msLeft: Double, windowMs: Double) -> Double {
        guard windowMs > 0 else { return 0 }
        return min(1, max(0, msLeft / windowMs))
    }
}
