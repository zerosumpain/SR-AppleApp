import Foundation

/// How often each door on the hub (⊞) is opened, so the hub can put the most
/// used first (John, 2026-10-27: "buttons ordered by frequency of use").
///
/// A count that fades: each open adds one, and what was there halves every
/// fourteen days. A door used a lot last month gives way to one used every day
/// now, and no single tap reorders everything. Doors never opened keep the
/// hub's own order, after the ones that have been.
///
/// Foundation only: the Linux harness tests it (`scripts/home-check.sh`).
struct HubUsage: Codable, Equatable {
    struct Mark: Codable, Equatable {
        var score: Double
        var at: Date
    }

    var marks: [String: Mark] = [:]

    static let halfLifeDays = 14.0
    static let key = "hub-usage"

    /// The faded count for a door, as of `now`.
    func score(_ id: String, now: Date) -> Double {
        guard let mark = marks[id] else { return 0 }
        let days = max(0, now.timeIntervalSince(mark.at)) / 86_400
        return mark.score * pow(0.5, days / Self.halfLifeDays)
    }

    mutating func record(_ id: String, now: Date) {
        marks[id] = Mark(score: score(id, now: now) + 1, at: now)
    }

    /// `ids`, most used first; equal scores keep the order they came in.
    func ordered(_ ids: [String], now: Date) -> [String] {
        ids.enumerated()
            .map { (index: $0.offset, id: $0.element, score: score($0.element, now: now)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .map(\.id)
    }

    // MARK: Stored

    static func load(_ defaults: UserDefaults = .standard) -> HubUsage {
        guard let data = defaults.data(forKey: key), let usage = try? JSONDecoder().decode(HubUsage.self, from: data) else {
            return HubUsage()
        }
        return usage
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    /// One open, counted and kept.
    static func opened(_ id: String, now: Date = Date(), defaults: UserDefaults = .standard) {
        var usage = load(defaults)
        usage.record(id, now: now)
        usage.save(defaults)
    }
}
