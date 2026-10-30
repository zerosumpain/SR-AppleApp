import Foundation

/// The high-score table kept on this phone: the ten best games, with the
/// initials typed for each, like the card on an arcade machine.
///
/// Pinball is played offline, so a score is saved the moment the game ends
/// and is there next time with or without a signal.
struct PinballScoreBook: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        var id: String
        var initials: String
        var score: Int
        var date: Date
        /// How many of the four modes were finished.
        var modes: Int
    }

    static let size = 10
    static let defaultInitials = "YOU"

    var entries: [Entry] = []
    var games = 0
    /// The initials typed last time, offered first next time.
    var lastInitials = PinballScoreBook.defaultInitials

    var best: Int { entries.first?.score ?? 0 }

    /// A finished game. Returns its place on the table (1 is the top), or
    /// nil when it did not make the ten.
    @discardableResult
    mutating func record(score: Int, modes: Int, date: Date = Date(), id: String = UUID().uuidString) -> Int? {
        games += 1
        guard score > 0 else { return nil }
        let entry = Entry(id: id, initials: lastInitials, score: score, date: date, modes: modes)
        // A tie goes below the older score: the first to get there keeps the place.
        let at = entries.firstIndex { $0.score < score } ?? entries.count
        guard at < Self.size else { return nil }
        entries.insert(entry, at: at)
        if entries.count > Self.size { entries.removeLast(entries.count - Self.size) }
        return at + 1
    }

    /// Puts initials on an entry: up to three letters or digits, upper case.
    mutating func rename(_ id: String, to typed: String) {
        let clean = Self.clean(typed)
        guard !clean.isEmpty, let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].initials = clean
        lastInitials = clean
    }

    static func clean(_ typed: String) -> String {
        String(typed.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(3))
    }
}

/// Where the table lives: UserDefaults, under the game's own key.
struct PinballScoreStore {
    var defaults: UserDefaults = .standard

    static let key = "pinball.scores.v1"

    func load() -> PinballScoreBook {
        guard let data = defaults.data(forKey: Self.key),
              let book = try? JSONDecoder().decode(PinballScoreBook.self, from: data) else { return PinballScoreBook() }
        return book
    }

    func save(_ book: PinballScoreBook) {
        if let data = try? JSONEncoder().encode(book) { defaults.set(data, forKey: Self.key) }
    }
}
