import Foundation

// The party room games' phone-side extras — Categories, Quiz Night and One
// Clue: a personal best kept on this phone, and the few small sums their
// screens draw from (a place in the table, a share of a bar, a sticky note's
// tilt, when the clock turns urgent). Pure values, so each is a unit test.
// Nothing here travels to the site or changes what the server decides: the
// server still judges every answer and owns every score.

// MARK: - Personal bests

/// What a finished game did to a personal best.
struct PartyRoomBestNote: Equatable {
    /// The best before this game, if there was one.
    let previous: Int?
    /// The best now.
    let best: Int?
    /// This game set it.
    let isNew: Bool
}

/// One game's personal best for one kind of round (a card size, a
/// difficulty), with enough memory to answer the same way when the results
/// page is shown twice for the same game.
struct PartyRoomRecord: Codable, Equatable {
    var best: Int?
    /// The best before the game that set `best`.
    var previous: Int?
    /// The game that set `best`.
    var bestToken: String?
    var games = 0
    /// The last few games recorded, so a page that appears again (back from
    /// the background, a fresh frame from the stream) does not count twice.
    var seen: [String] = []

    static let remembered = 24

    /// Records a finished game's figure; higher is better. Zero or less is
    /// "nothing scored" and never a best, but the game still counts as played.
    mutating func record(_ value: Int, token: String) -> PartyRoomBestNote {
        if seen.contains(token) {
            let isNew = bestToken == token
            return PartyRoomBestNote(previous: isNew ? previous : best, best: best, isNew: isNew)
        }
        seen.append(token)
        if seen.count > Self.remembered { seen.removeFirst(seen.count - Self.remembered) }
        games += 1
        guard value > 0 else { return PartyRoomBestNote(previous: best, best: best, isNew: false) }
        if let current = best, value <= current {
            return PartyRoomBestNote(previous: best, best: best, isNew: false)
        }
        previous = best
        best = value
        bestToken = token
        return PartyRoomBestNote(previous: previous, best: value, isNew: true)
    }
}

/// Where one game's bests live: a small JSON map of round kind to record in
/// UserDefaults, under a key that starts with the game's id.
struct PartyRoomBestStore {
    let key: String
    var defaults: UserDefaults = .standard

    // Computed, not stored: a static holding a UserDefaults would be shared
    // mutable state as far as strict concurrency is concerned.
    static var categories: PartyRoomBestStore { PartyRoomBestStore(key: "categories.bests.v1") }
    static var quizNight: PartyRoomBestStore { PartyRoomBestStore(key: "quiz-night.bests.v1") }
    static var oneClue: PartyRoomBestStore { PartyRoomBestStore(key: "one-clue.bests.v1") }

    func load() -> [String: PartyRoomRecord] {
        guard let data = defaults.data(forKey: key),
              let book = try? JSONDecoder().decode([String: PartyRoomRecord].self, from: data) else { return [:] }
        return book
    }

    func save(_ book: [String: PartyRoomRecord]) {
        if let data = try? JSONEncoder().encode(book) { defaults.set(data, forKey: key) }
    }

    /// The best for a kind of round, or nil before the first scoring game.
    func best(_ kind: String) -> Int? { load()[kind]?.best }

    /// Records a finished game and saves at once.
    @discardableResult
    func record(_ value: Int, kind: String, token: String) -> PartyRoomBestNote {
        var book = load()
        var entry = book[kind] ?? PartyRoomRecord()
        let note = entry.record(value, token: token)
        book[kind] = entry
        save(book)
        return note
    }
}

// MARK: - Small sums the screens draw from

enum PartyRoomMaths {
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
    /// 9 ahead of one on 6 are both 1st, and the 6 is 3rd. Nil for an id not
    /// in the list.
    static func place(of id: String, ids: [String], scores: [Int]) -> Int? {
        guard let index = ids.firstIndex(of: id), index < scores.count else { return nil }
        let mine = scores[index]
        return 1 + scores.prefix(ids.count).filter { $0 > mine }.count
    }

    /// `part` of `whole`, from 0 to 1; 0 when there is no whole.
    static func share(_ part: Int, of whole: Int) -> Double {
        guard whole > 0 else { return 0 }
        return min(1, max(0, Double(part) / Double(whole)))
    }

    /// A sticky note's tilt in degrees, the same for the same note every time
    /// it is drawn: alternating sides, a little more for every third.
    static func tilt(_ index: Int, spread: Double = 3) -> Double {
        let side: Double = index % 2 == 0 ? -1 : 1
        let lift: Double = index % 3 == 0 ? 1.4 : 1
        return side * spread * lift
    }

    /// Whether the clock has turned urgent: something left, and no more than
    /// `warnAt` seconds of it.
    static func urgent(secondsLeft: Int?, warnAt: Int) -> Bool {
        guard let secondsLeft else { return false }
        return secondsLeft > 0 && secondsLeft <= warnAt
    }

    /// The moment a count-down crosses into the last `warnAt` seconds, or
    /// ticks inside them: the haptic's cue. Once per second, never twice.
    static func tick(from old: Int?, to new: Int?, warnAt: Int) -> Bool {
        guard let new, urgent(secondsLeft: new, warnAt: warnAt) else { return false }
        guard let old else { return false }
        return new < old
    }
}
