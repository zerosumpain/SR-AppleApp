import Foundation

/// Who is playing: one player swapping between two pals, or a strip each.
enum TetherPalsPlayers: Int, Codable, CaseIterable, Identifiable {
    case solo = 1
    case two = 2
    case three = 3

    var id: Int { rawValue }

    /// How many pals are on the level.
    var team: Int { self == .solo ? 2 : rawValue }

    /// Strips of buttons along the bottom.
    var strips: Int { self == .solo ? 1 : rawValue }

    var title: String {
        switch self {
        case .solo: return "Solo"
        case .two: return "2 players"
        case .three: return "3 players"
        }
    }

    var icon: String {
        switch self {
        case .solo: return "person.fill"
        case .two: return "person.2.fill"
        case .three: return "person.3.fill"
        }
    }

    var line: String {
        switch self {
        case .solo: return "Drive both pals yourself. The middle button swaps which one you move."
        case .two: return "Two pals, a strip of buttons each. Hold the phone between you."
        case .three: return "Three pals, a strip each. Squeeze in close."
        }
    }
}

/// What finishing a level changed, for the results card.
struct TetherPalsResult: Equatable {
    let level: Int
    let name: String
    let time: Double
    let best: Double
    let par: Double
    let newBest: Bool
    /// The best is under par.
    let star: Bool
    /// The star was won just now.
    let newStar: Bool
    /// A level opened by this clear.
    let opened: Int?
    let pops: Int
    let players: TetherPalsPlayers
    /// Every level has now been cleared at least once.
    let allCleared: Bool
}

/// Tether Pals' bests, kept on this phone: the best team time on each level
/// (a star when it is under par), the last level and players chosen, and a
/// few totals. Levels open in order.
struct TetherPalsRecords: Codable, Equatable {
    /// Best time on each level, seconds, keyed by the level number as text.
    var bestTimes: [String: Double] = [:]
    /// The level the start card opens on.
    var level = 1
    var players: TetherPalsPlayers = .solo
    var clears = 0
    var pops = 0

    init() {}

    /// Lenient: a field added in a later version leaves the rest readable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bestTimes = (try? c.decodeIfPresent([String: Double].self, forKey: .bestTimes)) ?? [:]
        level = (try? c.decodeIfPresent(Int.self, forKey: .level)) ?? 1
        players = (try? c.decodeIfPresent(TetherPalsPlayers.self, forKey: .players)) ?? .solo
        clears = (try? c.decodeIfPresent(Int.self, forKey: .clears)) ?? 0
        pops = (try? c.decodeIfPresent(Int.self, forKey: .pops)) ?? 0
    }

    func best(_ level: Int) -> Double? { bestTimes[String(level)] }

    func isCleared(_ level: Int) -> Bool { best(level) != nil }

    func hasStar(_ level: Int) -> Bool {
        guard let best = best(level) else { return false }
        return best <= TetherPalsCatalogue.level(level).par
    }

    var stars: Int { (1...TetherPalsCatalogue.count).filter(hasStar).count }

    var clearedCount: Int { (1...TetherPalsCatalogue.count).filter(isCleared).count }

    /// The furthest level open: one past the furthest cleared.
    var unlocked: Int {
        var furthest = 0
        for n in 1...TetherPalsCatalogue.count where isCleared(n) { furthest = n }
        return min(TetherPalsCatalogue.count, furthest + 1)
    }

    func isOpen(_ level: Int) -> Bool { level >= 1 && level <= unlocked }

    /// The level to open on: the last chosen, if it is open.
    var startLevel: Int { isOpen(level) ? level : unlocked }

    /// A level finished in `time` seconds with `pops` pops on the way.
    @discardableResult
    mutating func record(level: Int, time: Double, pops: Int, players: TetherPalsPlayers) -> TetherPalsResult {
        let number = min(max(1, level), TetherPalsCatalogue.count)
        let info = TetherPalsCatalogue.level(number)
        let key = String(number)
        let openBefore = unlocked
        let hadStar = hasStar(number)
        let previous = bestTimes[key]
        let isBest = previous.map { time < $0 } ?? true
        if isBest { bestTimes[key] = time }
        clears += 1
        self.pops += max(0, pops)
        let best = bestTimes[key] ?? time
        let opened = unlocked > openBefore ? unlocked : nil
        return TetherPalsResult(level: number, name: info.name, time: time, best: best, par: info.par,
                                newBest: isBest && previous != nil, star: best <= info.par,
                                newStar: !hadStar && best <= info.par, opened: opened, pops: pops,
                                players: players, allCleared: clearedCount == TetherPalsCatalogue.count)
    }
}

/// Where the records live: one small JSON value in UserDefaults.
struct TetherPalsRecordStore {
    var defaults: UserDefaults = .standard

    static let key = "tether-pals.records.v1"

    func load() -> TetherPalsRecords {
        guard let data = defaults.data(forKey: Self.key),
              let records = try? JSONDecoder().decode(TetherPalsRecords.self, from: data) else { return TetherPalsRecords() }
        return records
    }

    func save(_ records: TetherPalsRecords) {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.key) }
    }
}
