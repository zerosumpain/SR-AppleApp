import Foundation

// A phone's own bests for the Play nearby games, kept on this phone only.
//
// The room's results page keeps a game's best SCORE (`OfflineResultStore`),
// but the figure a player is proud of is often not the score: a reaction
// game's fastest draw in milliseconds, a race's quickest run. Those live
// here, one small Codable record per game, under a key that starts with the
// game's own id (`quick-draw.nearby-best.v1`), so two games never share one.
//
// Nothing here is sent anywhere, and nothing here touches the rules: the
// views record a figure when their own match ends and show it beside the
// result. Foundation only, so the rules of "better" are unit-tested on Linux.

/// Which way a figure improves.
enum NearbyPlayBestRule: String, Codable, Equatable {
    /// Points: more is better.
    case higher
    /// Milliseconds: less is better.
    case lower
}

/// One game's best on this phone.
struct NearbyPlayBest: Codable, Equatable {
    /// The best figure so far.
    var value: Int
    /// How many figures have been recorded, best or not.
    var plays: Int
}

/// What recording a figure did.
struct NearbyPlayBestOutcome: Equatable {
    /// The best after recording (the new figure, when it improved).
    let best: Int
    /// The best before, nil on the first record.
    let previous: Int?
    /// The figure beat the previous best (the first record counts).
    let improved: Bool
    /// Figures recorded so far, this one included.
    let plays: Int

    /// "New best" is only worth a fanfare when there was a best to beat.
    var beatAnOldBest: Bool { improved && previous != nil }
}

enum NearbyPlayBestMath {
    /// Whether `value` beats `old` under `rule`; anything beats nothing.
    static func isBetter(_ value: Int, than old: Int?, rule: NearbyPlayBestRule) -> Bool {
        guard let old else { return true }
        switch rule {
        case .higher: return value > old
        case .lower: return value < old
        }
    }

    /// The record after `value` is added to `old`.
    static func merge(_ old: NearbyPlayBest?, value: Int, rule: NearbyPlayBestRule) -> (record: NearbyPlayBest, outcome: NearbyPlayBestOutcome) {
        let plays = (old?.plays ?? 0) + 1
        let improved = isBetter(value, than: old?.value, rule: rule)
        let best = improved ? value : (old?.value ?? value)
        let record = NearbyPlayBest(value: best, plays: plays)
        let outcome = NearbyPlayBestOutcome(best: best, previous: old?.value, improved: improved, plays: plays)
        return (record, outcome)
    }

    /// The defaults key for a game's record: the game's id first.
    static func key(for gameId: String) -> String {
        "\(gameId).nearby-best.v1"
    }

    /// "231 ms" / "4.82 s" / "1,240 pts" — how a best reads beside a result.
    static func milliseconds(_ ms: Int) -> String {
        "\(max(0, ms)) ms"
    }

    /// Tenths of a second from milliseconds, as "4.8 s".
    static func seconds(fromMs ms: Int) -> String {
        let tenths = Int((Double(max(0, ms)) / 100).rounded())
        return "\(tenths / 10).\(tenths % 10) s"
    }
}

/// The records in UserDefaults. Reads and writes are small and rare (once a
/// match), so there is no cache.
struct NearbyPlayBestStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func best(_ gameId: String) -> NearbyPlayBest? {
        guard let data = defaults.data(forKey: NearbyPlayBestMath.key(for: gameId)) else { return nil }
        return try? JSONDecoder().decode(NearbyPlayBest.self, from: data)
    }

    /// Add a figure; returns what it did.
    @discardableResult
    func record(_ gameId: String, value: Int, rule: NearbyPlayBestRule) -> NearbyPlayBestOutcome {
        let merged = NearbyPlayBestMath.merge(best(gameId), value: value, rule: rule)
        if let data = try? JSONEncoder().encode(merged.record) {
            defaults.set(data, forKey: NearbyPlayBestMath.key(for: gameId))
        }
        return merged.outcome
    }
}

/// The share of a countdown still to run, 0…1, for a ring or a bar. A
/// window this phone's build thinks is shorter than what is left (another
/// build's rules) reads as full rather than over-full.
enum NearbyPlayClockMath {
    static func fraction(left: Double, total: Double) -> Double {
        guard total > 0, left.isFinite else { return 0 }
        return min(1, max(0, left / total))
    }

    /// Whole seconds shown on a ring: 0.2 s left still reads "1".
    static func shownSeconds(left: Double) -> Int {
        guard left > 0, left.isFinite else { return 0 }
        return Int(left.rounded(.up))
    }

    /// The instants a finite timeline draws: every `step` from `start` up
    /// to `end`, then `end` itself, so the last frame shows zero and the
    /// timeline then stops — no frames once a clock has run out. The array
    /// form (capped at `limit`, then `end`) is for tests; a timeline walks
    /// `NearbyPlayTicks` itself, lazily, so a three-minute clock never
    /// builds thousands of dates and never runs out of entries early.
    static func ticks(from start: Date, to end: Date, step: TimeInterval, limit: Int = 2400) -> [Date] {
        var out: [Date] = []
        var walk = NearbyPlayTicks(from: start, to: end, step: step)
        while let t = walk.next() {
            if out.count >= limit {
                out.append(end)
                break
            }
            out.append(t)
        }
        return out
    }

    /// How often a countdown ring needs a frame: a short window drains fast
    /// and wants a smooth 30 a second; a three-minute match clock moves a
    /// hair a second, and four frames a second is plenty.
    static func ringStep(total: Double) -> TimeInterval {
        guard total.isFinite, total > 0 else { return 1.0 / 30.0 }
        return min(0.25, max(1.0 / 30.0, total / 600))
    }
}

/// The instants of a finite timeline, made one at a time: `start`, then
/// every `step` while before `end`, then `end` once, then nothing. A window
/// already over (or a step of zero) gives `start` alone.
struct NearbyPlayTicks: Sequence, IteratorProtocol {
    private var upcoming: Date?
    private let end: Date
    private let step: TimeInterval
    private let finite: Bool

    init(from start: Date, to end: Date, step: TimeInterval) {
        self.upcoming = start
        self.end = end
        self.step = step
        self.finite = end > start && step > 0 && step.isFinite
    }

    mutating func next() -> Date? {
        guard let current = upcoming else { return nil }
        guard finite else {
            upcoming = nil
            return current
        }
        if current < end {
            let following = current.addingTimeInterval(step)
            upcoming = following < end ? following : end
            return current
        }
        upcoming = nil
        return end
    }
}
