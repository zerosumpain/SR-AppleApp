import Foundation

/// Minesweeper's bests, kept on this phone: the five fastest clears of each
/// field, how many games were finished and won, and the winning streak. A
/// custom field and a no-guessing field each keep their own (see
/// `MinesweeperSetup.recordKey`).
struct MinesweeperRecords: Codable, Equatable, Sendable {
    /// The fastest clears per field, quickest first, at most `kept`.
    var times: [String: [Double]] = [:]
    var played: [String: Int] = [:]
    var won: [String: Int] = [:]
    var streak: [String: Int] = [:]
    var bestStreak: [String: Int] = [:]

    static let kept = 5

    init() {}

    /// Reads whatever an older save holds and defaults the rest, so a new
    /// field in a later version never wipes the bests.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        times = try c.decodeIfPresent([String: [Double]].self, forKey: .times) ?? [:]
        played = try c.decodeIfPresent([String: Int].self, forKey: .played) ?? [:]
        won = try c.decodeIfPresent([String: Int].self, forKey: .won) ?? [:]
        streak = try c.decodeIfPresent([String: Int].self, forKey: .streak) ?? [:]
        bestStreak = try c.decodeIfPresent([String: Int].self, forKey: .bestStreak) ?? [:]
    }

    func best(_ key: String) -> Double? { times[key]?.first }
    func top(_ key: String) -> [Double] { times[key] ?? [] }
    func playedCount(_ key: String) -> Int { played[key] ?? 0 }
    func wonCount(_ key: String) -> Int { won[key] ?? 0 }
    func streakCount(_ key: String) -> Int { streak[key] ?? 0 }
    func bestStreakCount(_ key: String) -> Int { bestStreak[key] ?? 0 }

    /// A cleared field in `time` seconds. Returns its place in the top five
    /// (1 is a new best), or nil when it is not among them.
    @discardableResult
    mutating func recordWin(key: String, time: Double) -> Int? {
        played[key, default: 0] += 1
        won[key, default: 0] += 1
        let run = (streak[key] ?? 0) + 1
        streak[key] = run
        bestStreak[key] = max(bestStreak[key] ?? 0, run)
        guard time.isFinite, time >= 0 else { return nil }
        var list = times[key] ?? []
        let place = list.firstIndex(where: { time < $0 }) ?? list.count
        guard place < Self.kept else { return nil }
        list.insert(time, at: place)
        times[key] = Array(list.prefix(Self.kept))
        return place + 1
    }

    /// A mine went off: the game counts, the streak ends.
    mutating func recordLoss(key: String) {
        played[key, default: 0] += 1
        streak[key] = 0
    }
}

/// Where the records and the last choices live: UserDefaults, both small.
struct MinesweeperRecordStore {
    var defaults: UserDefaults = .standard

    static let recordsKey = "minesweeper.records.v1"
    static let setupKey = "minesweeper.setup.v1"

    func load() -> MinesweeperRecords {
        guard let data = defaults.data(forKey: Self.recordsKey),
              let records = try? JSONDecoder().decode(MinesweeperRecords.self, from: data) else { return MinesweeperRecords() }
        return records
    }

    func save(_ records: MinesweeperRecords) {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.recordsKey) }
    }

    func loadSetup() -> MinesweeperSetup {
        guard let data = defaults.data(forKey: Self.setupKey),
              var setup = try? JSONDecoder().decode(MinesweeperSetup.self, from: data) else { return MinesweeperSetup() }
        setup.tidyCustom()
        return setup
    }

    func saveSetup(_ setup: MinesweeperSetup) {
        if let data = try? JSONEncoder().encode(setup) { defaults.set(data, forKey: Self.setupKey) }
    }
}

/// Times as the screen says them.
enum MinesweeperFormat {
    /// The running clock: "0:07", "1:23", "12:05". Whole seconds.
    static func clock(_ seconds: Double) -> String {
        let s = max(0, min(5999, Int(seconds.isFinite ? seconds : 0)))
        let tail = s % 60 < 10 ? "0\(s % 60)" : "\(s % 60)"
        return "\(s / 60):\(tail)"
    }

    /// A finished time, to the tenth: "7.4 s", "1:23.0".
    static func precise(_ seconds: Double) -> String {
        let tenths = max(0, Int((seconds.isFinite ? seconds : 0) * 10))
        let whole = tenths / 10, tenth = tenths % 10
        if whole < 60 { return "\(whole).\(tenth) s" }
        let secs = whole % 60
        return "\(whole / 60):\(secs < 10 ? "0" : "")\(secs).\(tenth)"
    }

    /// Words for VoiceOver: "1 minute 23 seconds".
    static func spoken(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.isFinite ? seconds : 0))
        let m = s / 60, r = s % 60
        let secs = r == 1 ? "1 second" : "\(r) seconds"
        if m == 0 { return secs }
        return (m == 1 ? "1 minute " : "\(m) minutes ") + secs
    }
}
