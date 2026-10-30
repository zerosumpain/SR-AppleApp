import Foundation

/// Tilt Maze's bests, kept on this phone: the stars and best time on each
/// campaign level, the longest endless run, and a few totals. Played offline,
/// so a best is saved the moment it is set.
struct TiltMazeBook: Codable, Equatable {
    /// Stars on each campaign level, keyed by the level number as text.
    var stars: [String: Int] = [:]
    /// Best time on each campaign level, seconds.
    var bestTimes: [String: Double] = [:]
    /// The most mazes cleared in one endless run.
    var endlessBest = 0
    var endlessRuns = 0
    var mazesCleared = 0
    var falls = 0

    init() {}

    /// A book from an older or newer app still opens: a missing field is its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stars = try c.decodeIfPresent([String: Int].self, forKey: .stars) ?? [:]
        bestTimes = try c.decodeIfPresent([String: Double].self, forKey: .bestTimes) ?? [:]
        endlessBest = try c.decodeIfPresent(Int.self, forKey: .endlessBest) ?? 0
        endlessRuns = try c.decodeIfPresent(Int.self, forKey: .endlessRuns) ?? 0
        mazesCleared = try c.decodeIfPresent(Int.self, forKey: .mazesCleared) ?? 0
        falls = try c.decodeIfPresent(Int.self, forKey: .falls) ?? 0
    }

    func stars(for level: Int) -> Int { min(3, max(0, stars[String(level)] ?? 0)) }

    func bestTime(for level: Int) -> Double? { bestTimes[String(level)] }

    var totalStars: Int { (1...TiltMazeCatalogue.campaignCount).reduce(0) { $0 + stars(for: $1) } }

    /// The furthest level open to play: one past the furthest cleared, so
    /// levels open in order.
    var unlocked: Int {
        var furthest = 0
        for n in 1...TiltMazeCatalogue.campaignCount where stars(for: n) > 0 { furthest = n }
        return min(TiltMazeCatalogue.campaignCount, furthest + 1)
    }

    func isOpen(_ level: Int) -> Bool { level >= 1 && level <= unlocked }

    /// What a finish changed.
    struct Clear: Equatable {
        var stars: Int
        var newBestTime: Bool
        var newStars: Bool
    }

    /// A campaign level finished in `time`, earning `earned` stars.
    @discardableResult
    mutating func recordClear(level: Int, time: Double, stars earned: Int) -> Clear {
        let key = String(level)
        let before = stars(for: level)
        let previous = bestTimes[key]
        let isBest = previous.map { time < $0 } ?? true
        if isBest { bestTimes[key] = time }
        if earned > before { stars[key] = min(3, earned) }
        mazesCleared += 1
        return Clear(stars: earned, newBestTime: isBest && previous != nil, newStars: earned > before)
    }

    /// A drop down a hole, counted as it happens.
    mutating func recordFall() { falls += 1 }

    /// An endless maze cleared mid-run.
    mutating func noteEndlessMaze() { mazesCleared += 1 }

    /// An endless run over after `mazes` mazes. True when it is a new best.
    @discardableResult
    mutating func recordEndless(mazes: Int) -> Bool {
        endlessRuns += 1
        guard mazes > endlessBest else { return false }
        endlessBest = mazes
        return true
    }
}

/// Where the book lives: UserDefaults, under Tilt Maze's own key.
struct TiltMazeStore {
    var defaults: UserDefaults = .standard

    static let key = "tilt-maze.book.v1"

    func load() -> TiltMazeBook {
        guard let data = defaults.data(forKey: Self.key),
              let book = try? JSONDecoder().decode(TiltMazeBook.self, from: data) else { return TiltMazeBook() }
        return book
    }

    func save(_ book: TiltMazeBook) {
        if let data = try? JSONEncoder().encode(book) { defaults.set(data, forKey: Self.key) }
    }
}
