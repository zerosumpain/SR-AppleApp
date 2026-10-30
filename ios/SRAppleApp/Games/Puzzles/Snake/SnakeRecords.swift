import Foundation

/// The snake's colours. The first is everyone's; the rest open as you eat
/// apples, across every game in every mode.
enum SnakeSkin: String, CaseIterable, Codable, Identifiable {
    case sky, grape, sunset, midnight, rainbow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sky: return "Sky"
        case .grape: return "Grape"
        case .sunset: return "Sunset"
        case .midnight: return "Midnight"
        case .rainbow: return "Rainbow"
        }
    }

    /// Apples eaten in all before this colour opens.
    var unlockApples: Int {
        switch self {
        case .sky: return 0
        case .grape: return 30
        case .sunset: return 80
        case .midnight: return 150
        case .rainbow: return 300
        }
    }
}

/// The best in one mode (or one maze).
struct SnakeBest: Codable, Equatable {
    var score = 0
    var length = 0
    var games = 0
}

/// How one game went, for the results card.
struct SnakeRunResult: Equatable {
    let mode: SnakeMode
    /// The maze's name in Maze mode.
    let place: String?
    let score: Int
    let best: Int
    let newBest: Bool
    let length: Int
    let apples: Int
    let goldens: Int
    let death: SnakeDeath?
    let filled: Bool
    /// Mazes and colours this game opened, in words: "Crossroads", "Grape".
    let unlockedMazes: [String]
    let unlockedSkins: [String]
}

/// Everything Snake keeps on this phone: the best in each mode and maze, the
/// running totals that open colours, and the last settings used.
struct SnakeRecords: Codable, Equatable {
    var bests: [String: SnakeBest] = [:]
    var apples = 0
    var goldens = 0
    var games = 0
    var mode: SnakeMode = .classic
    var mazeId: String = SnakeMaze.all[0].id
    var skin: SnakeSkin = .sky
    /// The big on-screen arrows, for younger players.
    var pad = false

    init() {}

    /// Lenient: a field added in a later version leaves the rest readable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bests = (try? c.decodeIfPresent([String: SnakeBest].self, forKey: .bests)) ?? [:]
        apples = (try? c.decodeIfPresent(Int.self, forKey: .apples)) ?? 0
        goldens = (try? c.decodeIfPresent(Int.self, forKey: .goldens)) ?? 0
        games = (try? c.decodeIfPresent(Int.self, forKey: .games)) ?? 0
        mode = (try? c.decodeIfPresent(SnakeMode.self, forKey: .mode)) ?? .classic
        mazeId = (try? c.decodeIfPresent(String.self, forKey: .mazeId)) ?? SnakeMaze.all[0].id
        skin = (try? c.decodeIfPresent(SnakeSkin.self, forKey: .skin)) ?? .sky
        pad = (try? c.decodeIfPresent(Bool.self, forKey: .pad)) ?? false
    }

    /// Where a mode's best is filed: "classic", "wrap", "maze.pillars".
    static func key(mode: SnakeMode, maze: SnakeMaze?) -> String {
        guard mode == .maze else { return mode.rawValue }
        return "maze." + (maze ?? SnakeMaze.all[0]).id
    }

    func best(_ key: String) -> SnakeBest { bests[key] ?? SnakeBest() }

    func best(mode: SnakeMode, maze: SnakeMaze?) -> SnakeBest {
        best(Self.key(mode: mode, maze: maze))
    }

    /// The first maze is always open; each other opens with a score on the one before.
    func isUnlocked(_ maze: SnakeMaze) -> Bool {
        guard let previous = maze.previous else { return true }
        return best(mode: .maze, maze: previous).score >= maze.unlockScore
    }

    func isUnlocked(_ skin: SnakeSkin) -> Bool { apples >= skin.unlockApples }

    var unlockedMazes: [SnakeMaze] { SnakeMaze.all.filter { isUnlocked($0) } }

    /// The maze to play: the one last chosen if it is open, else the first.
    var maze: SnakeMaze {
        let chosen = SnakeMaze.named(mazeId)
        return isUnlocked(chosen) ? chosen : SnakeMaze.all[0]
    }

    /// The colour to draw: the one chosen if it is open, else the first.
    var activeSkin: SnakeSkin { isUnlocked(skin) ? skin : .sky }

    /// The next colour still to open, if any.
    var nextSkin: SnakeSkin? { SnakeSkin.allCases.first { !isUnlocked($0) } }

    /// A finished game. Files the best and the totals and says what it opened.
    mutating func record(_ game: SnakeGame, maze: SnakeMaze?) -> SnakeRunResult {
        let key = Self.key(mode: game.mode, maze: maze)
        let mazesBefore = Set(unlockedMazes.map(\.id))
        let skinsBefore = Set(SnakeSkin.allCases.filter { isUnlocked($0) })

        var entry = best(key)
        let newBest = game.score > entry.score
        entry.games += 1
        if newBest { entry.score = game.score }
        entry.length = max(entry.length, game.length)
        bests[key] = entry
        apples += game.eaten
        goldens += game.goldenEaten
        games += 1

        let opened = unlockedMazes.filter { !mazesBefore.contains($0.id) }.map(\.name)
        let coloured = SnakeSkin.allCases.filter { isUnlocked($0) && !skinsBefore.contains($0) }.map(\.title)
        return SnakeRunResult(mode: game.mode, place: game.mode == .maze ? (maze ?? SnakeMaze.all[0]).name : nil,
                              score: game.score, best: entry.score, newBest: newBest && game.score > 0,
                              length: game.length, apples: game.eaten, goldens: game.goldenEaten,
                              death: game.death, filled: game.filled,
                              unlockedMazes: opened, unlockedSkins: coloured)
    }
}

/// Where the records live: one small JSON value in UserDefaults.
struct SnakeRecordStore {
    var defaults: UserDefaults = .standard

    static let key = "snake.records.v1"

    func load() -> SnakeRecords {
        guard let data = defaults.data(forKey: Self.key),
              let records = try? JSONDecoder().decode(SnakeRecords.self, from: data) else { return SnakeRecords() }
        return records
    }

    func save(_ records: SnakeRecords) {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.key) }
    }
}
