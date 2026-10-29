import Foundation

/// The stars a level earns: one for arriving, one for every star picked up
/// (over all the launches it took), one for arriving within par.
enum OrbitRating {
    static func stars(arrived: Bool, allStars: Bool, launches: Int, par: Int) -> Int {
        guard arrived else { return 0 }
        return 1 + (allStars ? 1 : 0) + (launches <= par ? 1 : 0)
    }
}

/// One go at a level: the launches so far and the stars picked up by them.
/// Stars stay picked up from one launch to the next, so a probe that misses
/// the target but grabs a star has still done something.
struct OrbitAttempt: Equatable {
    let level: Int
    let par: Int
    private(set) var launches = 0
    private(set) var collected: [Bool]
    private(set) var arrived = false

    init(level: OrbitLevel) {
        self.level = level.number
        par = level.par
        collected = Array(repeating: false, count: level.stars.count)
    }

    var probesLeft: Int { max(0, OrbitPhysics.probes - launches) }
    /// Every probe is spent and none arrived.
    var outOfProbes: Bool { !arrived && launches >= OrbitPhysics.probes }
    var starsCollected: Int { collected.filter { $0 }.count }
    var allStars: Bool { !collected.contains(false) }
    var rating: Int { OrbitRating.stars(arrived: arrived, allStars: allStars, launches: launches, par: par) }

    /// A flight that has ended counts as one launch, and its stars are kept.
    mutating func record(_ flight: OrbitFlight) {
        guard !arrived, !outOfProbes else { return }
        launches += 1
        for (i, got) in flight.collected.enumerated() where got && collected.indices.contains(i) {
            collected[i] = true
        }
        if flight.end == .arrived { arrived = true }
    }
}

/// A level's best: its stars, and the fewest launches that ever reached it.
struct OrbitLevelBest: Codable, Equatable {
    var stars: Int
    var launches: Int
    var allStars: Bool
}

/// Orbit's bests on this phone: each level's stars and the fewest launches.
/// Levels open one at a time: finishing one opens the next.
struct OrbitProgress: Codable, Equatable {
    /// By level number, as a string (JSON object keys).
    var bests: [String: OrbitLevelBest] = [:]
    var arrivals = 0
    var launches = 0

    func best(_ level: Int) -> OrbitLevelBest? { bests[String(level)] }

    func stars(_ level: Int) -> Int { best(level)?.stars ?? 0 }

    func isOpen(_ level: Int) -> Bool {
        level <= 1 || best(level - 1) != nil
    }

    var totalStars: Int { bests.values.reduce(0) { $0 + $1.stars } }

    var finishedLevels: Int { bests.count }

    /// The level to offer first: the lowest open level not yet finished, or
    /// the last one when all are done.
    func nextLevel(of count: Int) -> Int {
        for n in 1...max(count, 1) where best(n) == nil && isOpen(n) { return n }
        return max(count, 1)
    }

    /// A launch that has ended, arrived or not.
    mutating func noteLaunch() {
        launches += 1
    }

    /// An arrival. True when it beats the level's best (more stars, or the
    /// same stars in fewer launches).
    @discardableResult
    mutating func record(_ attempt: OrbitAttempt) -> Bool {
        guard attempt.arrived else { return false }
        arrivals += 1
        let fresh = OrbitLevelBest(stars: attempt.rating, launches: attempt.launches, allStars: attempt.allStars)
        guard let old = best(attempt.level) else {
            bests[String(attempt.level)] = fresh
            return true
        }
        let better = fresh.stars > old.stars || (fresh.stars == old.stars && fresh.launches < old.launches)
        let merged = OrbitLevelBest(stars: max(old.stars, fresh.stars),
                                    launches: min(old.launches, fresh.launches),
                                    allStars: old.allStars || fresh.allStars)
        bests[String(attempt.level)] = merged
        return better
    }
}

/// Where the progress lives: a few hundred bytes of JSON in UserDefaults.
struct OrbitStore {
    var defaults: UserDefaults = .standard

    static let key = "orbit.progress.v1"

    func load() -> OrbitProgress {
        guard let data = defaults.data(forKey: Self.key),
              let progress = try? JSONDecoder().decode(OrbitProgress.self, from: data) else { return OrbitProgress() }
        return progress
    }

    func save(_ progress: OrbitProgress) {
        if let data = try? JSONEncoder().encode(progress) { defaults.set(data, forKey: Self.key) }
    }
}
