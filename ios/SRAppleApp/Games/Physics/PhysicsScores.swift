import Foundation

/// The physics games' bests, kept on this phone: Lander's best run and Car
/// Race's best time on each track, with the ghost of that run to race.
///
/// They are played offline, so nothing here waits for the site: a best is
/// saved the moment it is set, and is there next time with or without a
/// signal.
struct PhysicsScoreBook: Codable, Equatable {
    var landerBest = 0
    /// The level the best run reached.
    var landerBestLevel = 0
    var landerRuns = 0
    /// Best race time on each track (`CarTrack.id`), seconds.
    var carBest: [String: Double] = [:]
    var carBestLap: [String: Double] = [:]
    var carRaces = 0

    /// A finished Lander run. True when it is a new best.
    @discardableResult
    mutating func recordLander(score: Int, level: Int) -> Bool {
        landerRuns += 1
        guard score > landerBest else { return false }
        landerBest = score
        landerBestLevel = level
        return true
    }

    /// A finished race on `track`. True when the time is a new best there.
    @discardableResult
    mutating func recordRace(track: String, time: Double, bestLap: Double?) -> Bool {
        carRaces += 1
        if let lap = bestLap, lap < (carBestLap[track] ?? .infinity) { carBestLap[track] = lap }
        guard time < (carBest[track] ?? .infinity) else { return false }
        carBest[track] = time
        return true
    }
}

/// Where the book and the ghosts live: the book in UserDefaults (small), each
/// track's ghost as a file in Application Support (a few hundred samples a lap).
struct PhysicsScoreStore {
    var defaults: UserDefaults = .standard
    var folder: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("PhysicsGhosts", isDirectory: true)

    static let key = "physics.scores.v1"

    func load() -> PhysicsScoreBook {
        guard let data = defaults.data(forKey: Self.key),
              let book = try? JSONDecoder().decode(PhysicsScoreBook.self, from: data) else { return PhysicsScoreBook() }
        return book
    }

    func save(_ book: PhysicsScoreBook) {
        if let data = try? JSONEncoder().encode(book) { defaults.set(data, forKey: Self.key) }
    }

    /// The best run's ghost on a track over `laps` laps, if one has been driven.
    func ghost(track: String, laps: Int) -> CarGhost? {
        guard let url = ghostURL(track: track, laps: laps), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CarGhost.self, from: data)
    }

    func saveGhost(_ ghost: CarGhost) {
        guard let url = ghostURL(track: ghost.trackId, laps: ghost.laps), let folder,
              let data = try? JSONEncoder().encode(ghost) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func ghostURL(track: String, laps: Int) -> URL? {
        // Track ids are the app's own kebab-case words; anything else is no file.
        guard track.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return folder?.appendingPathComponent("\(track)-\(laps).json")
    }
}
