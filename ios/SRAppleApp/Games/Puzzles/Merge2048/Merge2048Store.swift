import Foundation

/// One board size's record on this phone.
struct Merge2048Record: Codable, Equatable {
    var bestScore = 0
    var biggestTile = 0
    /// Games finished or given up on (a board with at least one move).
    var games = 0
    /// Games that made the winning tile.
    var wins = 0
}

/// 2048's bests, kept on this phone: the best score and the biggest tile for
/// each board size. Played offline, so a best is saved the moment it is set.
struct Merge2048Book: Codable, Equatable {
    /// By `Merge2048Size.rawValue`, as text (JSON keys are text).
    var records: [String: Merge2048Record] = [:]

    func record(_ size: Merge2048Size) -> Merge2048Record {
        records[String(size.rawValue)] ?? Merge2048Record()
    }

    /// A score and a biggest tile seen during a game. True when the score is
    /// a new best for this size.
    @discardableResult
    mutating func note(size: Merge2048Size, score: Int, biggest: Int) -> Bool {
        var record = self.record(size)
        let best = score > record.bestScore
        if best { record.bestScore = score }
        if biggest > record.biggestTile { record.biggestTile = biggest }
        records[String(size.rawValue)] = record
        return best
    }

    /// A game over, or a game set aside for a new one.
    mutating func finish(size: Merge2048Size, won: Bool) {
        var record = self.record(size)
        record.games += 1
        if won { record.wins += 1 }
        records[String(size.rawValue)] = record
    }
}

/// Where the book and the game in progress live: UserDefaults, both small
/// (a 5×5 board is 25 tiles at most).
struct Merge2048Store {
    var defaults: UserDefaults = .standard

    static let bookKey = "merge-2048.book.v1"
    static let sizeKey = "merge-2048.size.v1"

    static func gameKey(_ size: Merge2048Size) -> String { "merge-2048.game.v1.\(size.rawValue)" }

    func loadBook() -> Merge2048Book {
        guard let data = defaults.data(forKey: Self.bookKey),
              let book = try? JSONDecoder().decode(Merge2048Book.self, from: data) else { return Merge2048Book() }
        return book
    }

    func saveBook(_ book: Merge2048Book) {
        if let data = try? JSONEncoder().encode(book) { defaults.set(data, forKey: Self.bookKey) }
    }

    /// The game left on this size's board, if one is still going.
    func loadGame(_ size: Merge2048Size) -> Merge2048State? {
        guard let data = defaults.data(forKey: Self.gameKey(size)),
              let state = try? JSONDecoder().decode(Merge2048State.self, from: data),
              state.side == size.side, !state.isOver else { return nil }
        return state
    }

    func saveGame(_ state: Merge2048State, size: Merge2048Size) {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.gameKey(size)) }
    }

    func clearGame(_ size: Merge2048Size) {
        defaults.removeObject(forKey: Self.gameKey(size))
    }

    /// The board size last played.
    func loadSize() -> Merge2048Size {
        Merge2048Size(rawValue: defaults.integer(forKey: Self.sizeKey)) ?? .classic
    }

    func saveSize(_ size: Merge2048Size) {
        defaults.set(size.rawValue, forKey: Self.sizeKey)
    }
}
