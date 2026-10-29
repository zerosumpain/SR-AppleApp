import Foundation

// One game of Solitaire with its undo, and what the phone remembers between
// games: the stats, the settings and a game left half-played. Foundation
// only, so it is tested on Linux (`SolitaireTests`).

/// A game in progress: the deal it came from, the table now, and every table
/// before it, so undo goes all the way back.
struct SolitaireSession: Codable, Equatable {
    let seed: UInt64
    let drawMode: SolitaireDrawMode
    /// The solver found a win from this deal.
    let proven: Bool
    private(set) var state: SolitaireState
    /// Every table before this one, oldest first. Unlimited undo.
    private(set) var history: [SolitaireState] = []
    private(set) var moves = 0
    private(set) var undos = 0
    var hintsUsed = 0
    /// Seconds played, not counting paused or put-away time.
    var elapsed: Double = 0
    /// Already counted as a game played in the stats.
    var counted = false

    init(seed: UInt64, drawMode: SolitaireDrawMode, proven: Bool = false) {
        self.seed = seed
        self.drawMode = drawMode
        self.proven = proven
        self.state = SolitaireState.deal(seed: seed, drawMode: drawMode)
    }

    var started: Bool { moves > 0 }
    var won: Bool { state.isWon }
    var canUndo: Bool { !history.isEmpty && !won }

    /// Plays `action`. False, and nothing changes, when it is not allowed.
    @discardableResult
    mutating func perform(_ action: SolitaireAction) -> Bool {
        guard !won else { return false }
        var next = state
        guard next.apply(action) else { return false }
        history.append(state)
        state = next
        moves += 1
        return true
    }

    /// Back one table, exactly as it was.
    @discardableResult
    mutating func undo() -> Bool {
        guard canUndo, let previous = history.popLast() else { return false }
        state = previous
        undos += 1
        return true
    }

    /// The same deal from the start. Still the same game for the stats.
    mutating func restart() {
        state = SolitaireState.deal(seed: seed, drawMode: drawMode)
        history.removeAll()
        moves = 0
        undos = 0
        hintsUsed = 0
        elapsed = 0
    }
}

/// "3:07", or "1:02:09" past the hour.
enum SolitaireClock {
    static func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// "3 minutes 7 seconds", for VoiceOver.
    static func spoken(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60, s = total % 60
        let secs = s == 1 ? "1 second" : "\(s) seconds"
        if m == 0 { return secs }
        let mins = m == 1 ? "1 minute" : "\(m) minutes"
        return "\(mins) \(secs)"
    }
}

/// What a win set.
struct SolitaireRecord: Equatable {
    var bestTime = false
    var fewestMoves = false
    var bestStreak = false
}

/// Games played and won, the streak, and the bests for each draw.
struct SolitaireStats: Codable, Equatable {
    var played = 0
    var won = 0
    /// Wins in a row; a game given up on ends it.
    var streak = 0
    var bestStreak = 0
    /// Fastest win, seconds, by `SolitaireDrawMode.key`.
    var bestTime: [String: Double] = [:]
    var fewestMoves: [String: Int] = [:]
    var wins: [String: Int] = [:]

    init() {}

    var winRate: Int { played == 0 ? 0 : Int((Double(won) / Double(played) * 100).rounded()) }

    func bestTime(_ mode: SolitaireDrawMode) -> Double? { bestTime[mode.key] }
    func fewestMoves(_ mode: SolitaireDrawMode) -> Int? { fewestMoves[mode.key] }

    /// The first move of a new game.
    mutating func recordStart() {
        played += 1
    }

    /// A started game left for a new deal.
    mutating func recordAbandon() {
        streak = 0
    }

    mutating func recordWin(mode: SolitaireDrawMode, time: Double, moves: Int) -> SolitaireRecord {
        var record = SolitaireRecord()
        won += 1
        streak += 1
        wins[mode.key, default: 0] += 1
        if streak > bestStreak {
            record.bestStreak = bestStreak > 0
            bestStreak = streak
        }
        if time < (bestTime[mode.key] ?? .infinity) {
            record.bestTime = bestTime[mode.key] != nil
            bestTime[mode.key] = time
        }
        if moves < (fewestMoves[mode.key] ?? .max) {
            record.fewestMoves = fewestMoves[mode.key] != nil
            fewestMoves[mode.key] = moves
        }
        return record
    }

    // Every field optional on the way in, so a field added later never
    // throws away a family's record.
    private enum CodingKeys: String, CodingKey {
        case played, won, streak, bestStreak, bestTime, fewestMoves, wins
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        played = try c.decodeIfPresent(Int.self, forKey: .played) ?? 0
        won = try c.decodeIfPresent(Int.self, forKey: .won) ?? 0
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
        bestStreak = try c.decodeIfPresent(Int.self, forKey: .bestStreak) ?? 0
        bestTime = try c.decodeIfPresent([String: Double].self, forKey: .bestTime) ?? [:]
        fewestMoves = try c.decodeIfPresent([String: Int].self, forKey: .fewestMoves) ?? [:]
        wins = try c.decodeIfPresent([String: Int].self, forKey: .wins) ?? [:]
    }
}

/// The table's cloth.
enum SolitaireFelt: String, Codable, CaseIterable, Hashable {
    case baize, midnight, plum

    var title: String {
        switch self {
        case .baize: return "Green baize"
        case .midnight: return "Midnight"
        case .plum: return "Plum"
        }
    }
}

struct SolitaireSettings: Codable, Equatable {
    var drawMode: SolitaireDrawMode = .one
    /// Ask the solver for a deal it can win.
    var winnableOnly = true
    /// Four-colour suits and firmer outlines, for telling cards apart at a glance.
    var fourColour = false
    var felt: SolitaireFelt = .baize

    init() {}

    private enum CodingKeys: String, CodingKey {
        case drawMode, winnableOnly, fourColour, felt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        drawMode = (try? c.decodeIfPresent(SolitaireDrawMode.self, forKey: .drawMode)) ?? .one
        winnableOnly = (try? c.decodeIfPresent(Bool.self, forKey: .winnableOnly)) ?? true
        fourColour = (try? c.decodeIfPresent(Bool.self, forKey: .fourColour)) ?? false
        felt = (try? c.decodeIfPresent(SolitaireFelt.self, forKey: .felt)) ?? .baize
    }
}

/// Where Solitaire keeps things on this phone: all in UserDefaults, under
/// keys that start with the game's id.
struct SolitaireStore {
    var defaults: UserDefaults = .standard

    static let statsKey = "solitaire.stats.v1"
    static let settingsKey = "solitaire.settings.v1"
    static let gameKey = "solitaire.game.v1"

    func loadStats() -> SolitaireStats { load(SolitaireStats.self, Self.statsKey) ?? SolitaireStats() }
    func save(_ stats: SolitaireStats) { store(stats, Self.statsKey) }

    func loadSettings() -> SolitaireSettings { load(SolitaireSettings.self, Self.settingsKey) ?? SolitaireSettings() }
    func save(_ settings: SolitaireSettings) { store(settings, Self.settingsKey) }

    /// A game left half-played, if there is one.
    func loadGame() -> SolitaireSession? {
        guard let session = load(SolitaireSession.self, Self.gameKey), !session.won else { return nil }
        return session
    }

    func saveGame(_ session: SolitaireSession) { store(session, Self.gameKey) }
    func clearGame() { defaults.removeObject(forKey: Self.gameKey) }

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func store<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
