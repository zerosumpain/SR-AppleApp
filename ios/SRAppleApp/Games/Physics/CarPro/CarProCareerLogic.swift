import Foundation

// Car Racer+ career: four tiers (Club, National, GT, Pro), each a season of
// race weekends (a qualifying run sets the grid, then a race), a points
// table and prize money; a garage of cars bought with that money, upgraded
// stage by stage and tuned; time-trial bests; and the whole lot saved as
// versioned JSON on this phone (`CarProStore`).

/// How hard the AI drives, set by the player.
enum CarProDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy
    case normal
    case hard

    var id: String { rawValue }

    var name: String {
        switch self {
        case .easy: return "Easy"
        case .normal: return "Normal"
        case .hard: return "Hard"
        }
    }

    /// Added to every AI driver's skill.
    var skillShift: Double {
        switch self {
        case .easy: return -0.35
        case .normal: return 0
        case .hard: return 0.18
        }
    }
}

/// How the player steers (the screen's choice; kept with the career).
enum CarProSteeringMode: String, Codable, CaseIterable, Identifiable {
    case tilt
    case wheel
    case slider

    var id: String { rawValue }

    var name: String {
        switch self {
        case .tilt: return "Tilt"
        case .wheel: return "Wheel"
        case .slider: return "Slider"
        }
    }
}

/// The player's settings.
struct CarProSettings: Codable, Equatable {
    var assists = CarProAssists.full
    var steering = CarProSteeringMode.tilt
    var difficulty = CarProDifficulty.normal
    /// Speeds in mph rather than km/h.
    var mph = true
    var playerName = "You"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assists = try c.decodeIfPresent(CarProAssists.self, forKey: .assists) ?? .full
        steering = try c.decodeIfPresent(CarProSteeringMode.self, forKey: .steering) ?? .tilt
        difficulty = try c.decodeIfPresent(CarProDifficulty.self, forKey: .difficulty) ?? .normal
        mph = try c.decodeIfPresent(Bool.self, forKey: .mph) ?? true
        playerName = try c.decodeIfPresent(String.self, forKey: .playerName) ?? "You"
    }
}

/// The four tiers, in order.
enum CarProTier: String, Codable, CaseIterable, Identifiable {
    case club
    case national
    case gt
    case pro

    var id: String { rawValue }

    var name: String {
        switch self {
        case .club: return "Club Cup"
        case .national: return "National Series"
        case .gt: return "GT Championship"
        case .pro: return "Pro Championship"
        }
    }

    var line: String {
        switch self {
        case .club: return "Weekend racers in hatchbacks and roadsters. Learn the circuits."
        case .national: return "Quicker cars, longer races and drivers who brake late."
        case .gt: return "Grand tourers with downforce on the big circuits."
        case .pro: return "The best drivers in the fastest cars. Win this and you have won it all."
        }
    }

    /// The fastest car (by PI) allowed in.
    var piLimit: Int {
        switch self {
        case .club: return 400
        case .national: return 550
        case .gt: return 700
        case .pro: return 999
        }
    }

    /// The round-by-round circuits.
    var calendar: [String] {
        switch self {
        case .club: return ["brackenfield", "quarry-rx", "old-town", "kestrel-hill"]
        case .national: return ["thunder-bowl", "neon-harbour", "brackenfield", "saltcliff", "kestrel-hill"]
        case .gt: return ["saltcliff", "old-town", "neon-harbour", "thunder-bowl", "nordwald"]
        case .pro: return ["kestrel-hill", "quarry-rx", "saltcliff", "neon-harbour", "thunder-bowl", "nordwald"]
        }
    }

    /// About how far each race runs, m.
    var raceDistance: Double {
        switch self {
        case .club: return 5_000
        case .national: return 7_000
        case .gt: return 9_000
        case .pro: return 11_000
        }
    }

    /// Laps of `track` for a race in this tier.
    func laps(on track: CarProTrack) -> Int {
        Int(CarProMath.clamp((raceDistance / track.length).rounded(), 2, 8))
    }

    /// Prize money by finishing place, 1st to 8th.
    var prizes: [Int] {
        let base = [2_500, 1_800, 1_400, 1_100, 900, 700, 550, 400]
        return base.map { $0 * prizeScale }
    }

    /// Paid at the end of a season to the top three in the table.
    var seasonBonus: [Int] { [10_000, 6_000, 3_500].map { $0 * prizeScale } }

    private var prizeScale: Int {
        switch self {
        case .club: return 1
        case .national: return 2
        case .gt: return 4
        case .pro: return 8
        }
    }

    /// The AI's skill, weakest to strongest in the field.
    var skillRange: ClosedRange<Double> {
        switch self {
        case .club: return 0.25...0.6
        case .national: return 0.4...0.75
        case .gt: return 0.55...0.88
        case .pro: return 0.7...1.0
        }
    }

    /// The cars the AI field races in.
    var fieldModels: [CarProCarModel] {
        switch self {
        case .club: return [.hatch, .roadster]
        case .national: return [.roadster, .touring, .rally]
        case .gt: return [.rally, .gt]
        case .pro: return [.gt, .prototype]
        }
    }

    var previous: CarProTier? {
        switch self {
        case .club: return nil
        case .national: return .club
        case .gt: return .national
        case .pro: return .gt
        }
    }

    var next: CarProTier? {
        switch self {
        case .club: return .national
        case .national: return .gt
        case .gt: return .pro
        case .pro: return nil
        }
    }

    /// Championship points by place, 1st to 8th; one more for the fastest lap.
    static let points = [25, 18, 15, 12, 10, 8, 6, 4]
}

/// A car in the player's garage.
struct CarProOwnedCar: Codable, Equatable, Identifiable {
    var id: String
    var setup: CarProCarSetup
    var races = 0
    var wins = 0

    init(id: String, setup: CarProCarSetup, races: Int = 0, wins: Int = 0) {
        self.id = id
        self.setup = setup
        self.races = races
        self.wins = wins
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        setup = try c.decode(CarProCarSetup.self, forKey: .setup)
        races = try c.decodeIfPresent(Int.self, forKey: .races) ?? 0
        wins = try c.decodeIfPresent(Int.self, forKey: .wins) ?? 0
    }

    var model: CarProCarModel { setup.model }
}

/// A line in a season's table.
struct CarProStanding: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var points = 0
    var wins = 0
    var podiums = 0
    var isPlayer = false
}

/// A season in progress (or just finished).
struct CarProSeason: Codable, Equatable {
    var tier: CarProTier
    /// The next round, 0-based; equal to the calendar's length when done.
    var round = 0
    /// The AI drivers and cars, fixed for the season.
    var field: [CarProEntrant]
    var standings: [CarProStanding]
    /// Each round's finishing order, by entrant id.
    var results: [[String]] = []
    var playerCarId: String

    var complete: Bool { round >= tier.calendar.count }

    /// The table, leader first (ties on wins, then name).
    var table: [CarProStanding] {
        standings.sorted { a, b in
            if a.points != b.points { return a.points > b.points }
            if a.wins != b.wins { return a.wins > b.wins }
            return a.name < b.name
        }
    }

    var playerPosition: Int { (table.firstIndex { $0.isPlayer } ?? 0) + 1 }
}

/// One championship round, ready to drive.
struct CarProWeekend: Equatable {
    var tier: CarProTier
    var round: Int
    var trackId: String
    var laps: Int
    var field: [CarProEntrant]
    var player: CarProEntrant
    var seed: UInt64

    var track: CarProTrack { CarProCircuits.track(trackId) ?? CarProCircuits.all[0] }

    /// The player's qualifying run.
    func qualifyingConfig(assists: CarProAssists, ghost: CarProGhost? = nil) -> CarProSessionConfig {
        CarProSessionConfig.qualifying(track: trackId, player: player, assists: assists, laps: 2, ghost: ghost)
    }

    /// Everyone's qualifying times, quickest first: the AI's from its car's
    /// pace and its driver's skill, the player's as driven (nil: no time,
    /// starts last).
    func qualifying(playerLap: Double?) -> [CarProQualifyingRow] {
        let track = self.track
        var rows: [CarProQualifyingRow] = field.map { entrant in
            CarProQualifyingRow(entrant: entrant, time: CarProQualifying.estimate(entrant, track: track, seed: seed))
        }
        rows.append(CarProQualifyingRow(entrant: player, time: playerLap))
        rows.sort { a, b in
            switch (a.time, b.time) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.entrant.id < b.entrant.id
            }
        }
        return rows
    }

    /// The grid from qualifying, pole first.
    func grid(playerLap: Double?) -> [CarProEntrant] { qualifying(playerLap: playerLap).map(\.entrant) }

    func raceConfig(grid: [CarProEntrant], assists: CarProAssists) -> CarProSessionConfig {
        CarProSessionConfig(kind: .championship, trackId: trackId, laps: laps, entrants: grid, assists: assists,
                            seed: seed)
    }
}

/// A line of the qualifying sheet.
struct CarProQualifyingRow: Equatable, Identifiable {
    var entrant: CarProEntrant
    /// Nil: no lap set.
    var time: Double?
    var id: String { entrant.id }
}

/// What a championship race paid.
struct CarProRaceReward: Equatable {
    var position: Int
    var points: Int
    var prize: Int
    var fastestLap: Bool
    var championshipPosition: Int
    var seasonComplete: Bool
    var seasonBonus: Int
    /// A tier opened by this season's result.
    var unlocked: CarProTier?
    var title: Bool
}

/// Things the career refuses.
enum CarProCareerError: Error, Equatable {
    case notEnoughMoney(needed: Int)
    case alreadyOwned
    case unknownCar
    case maxedOut
    case tierLocked
    case notEligible(pi: Int, limit: Int)
    case noSeason
}

/// A time-trial best.
struct CarProBestLap: Codable, Equatable {
    var trackId: String
    var model: CarProCarModel
    var time: Double
}

/// Lifetime numbers for the career screen.
struct CarProCareerStats: Codable, Equatable {
    var races = 0
    var wins = 0
    var podiums = 0
    var earnings = 0
    var poles = 0
}

/// The whole career, saved as one JSON document.
struct CarProCareer: Codable, Equatable {
    static let currentVersion = 1
    static let startingMoney = 3_000

    var version = CarProCareer.currentVersion
    var money: Int
    var garage: [CarProOwnedCar]
    var selectedCarId: String
    var unlocked: [CarProTier]
    var titles: [CarProTier] = []
    var season: CarProSeason?
    var settings = CarProSettings()
    var bests: [CarProBestLap] = []
    var stats = CarProCareerStats()
    var seasonsStarted = 0
    var nextCarNumber = 2

    /// A fresh career: a little money and the hatchback.
    static func newCareer() -> CarProCareer {
        let car = CarProOwnedCar(id: "car-1", setup: CarProCarSetup(model: .hatch))
        return CarProCareer(money: startingMoney, garage: [car], selectedCarId: car.id, unlocked: [.club])
    }

    init(money: Int, garage: [CarProOwnedCar], selectedCarId: String, unlocked: [CarProTier]) {
        self.money = money
        self.garage = garage
        self.selectedCarId = selectedCarId
        self.unlocked = unlocked
    }

    init(from decoder: Decoder) throws {
        // Every field optional, so a save from an older build (missing what a
        // newer one added) still opens.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        money = try c.decodeIfPresent(Int.self, forKey: .money) ?? Self.startingMoney
        garage = try c.decodeIfPresent([CarProOwnedCar].self, forKey: .garage) ?? []
        if garage.isEmpty { garage = [CarProOwnedCar(id: "car-1", setup: CarProCarSetup(model: .hatch))] }
        selectedCarId = try c.decodeIfPresent(String.self, forKey: .selectedCarId) ?? garage[0].id
        unlocked = try c.decodeIfPresent([CarProTier].self, forKey: .unlocked) ?? [.club]
        titles = try c.decodeIfPresent([CarProTier].self, forKey: .titles) ?? []
        season = try c.decodeIfPresent(CarProSeason.self, forKey: .season)
        settings = try c.decodeIfPresent(CarProSettings.self, forKey: .settings) ?? CarProSettings()
        bests = try c.decodeIfPresent([CarProBestLap].self, forKey: .bests) ?? []
        stats = try c.decodeIfPresent(CarProCareerStats.self, forKey: .stats) ?? CarProCareerStats()
        seasonsStarted = try c.decodeIfPresent(Int.self, forKey: .seasonsStarted) ?? 0
        nextCarNumber = try c.decodeIfPresent(Int.self, forKey: .nextCarNumber) ?? garage.count + 1
        if !garage.contains(where: { $0.id == selectedCarId }) { selectedCarId = garage[0].id }
        if !unlocked.contains(.club) { unlocked.insert(.club, at: 0) }
    }

    // MARK: - Garage

    func car(_ id: String) -> CarProOwnedCar? { garage.first { $0.id == id } }

    var selectedCar: CarProOwnedCar { car(selectedCarId) ?? garage[0] }

    func owns(_ model: CarProCarModel) -> Bool { garage.contains { $0.model == model } }

    /// Buys a new `model` and selects it.
    @discardableResult
    mutating func buy(_ model: CarProCarModel) throws -> CarProOwnedCar {
        guard !owns(model) else { throw CarProCareerError.alreadyOwned }
        guard money >= model.price else { throw CarProCareerError.notEnoughMoney(needed: model.price - money) }
        money -= model.price
        let car = CarProOwnedCar(id: "car-\(nextCarNumber)", setup: CarProCarSetup(model: model))
        nextCarNumber += 1
        garage.append(car)
        selectedCarId = car.id
        return car
    }

    /// Fits the next stage of `kind` to the car. Returns what it cost.
    @discardableResult
    mutating func buyUpgrade(carId: String, kind: CarProUpgradeKind) throws -> Int {
        guard let index = garage.firstIndex(where: { $0.id == carId }) else { throw CarProCareerError.unknownCar }
        guard let cost = garage[index].setup.upgradeCost(kind), let next = garage[index].setup.withUpgrade(kind) else {
            throw CarProCareerError.maxedOut
        }
        guard money >= cost else { throw CarProCareerError.notEnoughMoney(needed: cost - money) }
        money -= cost
        garage[index].setup = next
        return cost
    }

    mutating func setTuning(carId: String, _ tuning: CarProTuning) throws {
        guard let index = garage.firstIndex(where: { $0.id == carId }) else { throw CarProCareerError.unknownCar }
        garage[index].setup.tuning = tuning.clamped
    }

    mutating func select(carId: String) throws {
        guard car(carId) != nil else { throw CarProCareerError.unknownCar }
        selectedCarId = carId
    }

    // MARK: - Seasons

    func isUnlocked(_ tier: CarProTier) -> Bool { unlocked.contains(tier) }

    /// The car may enter the tier: its PI is within the limit.
    func isEligible(carId: String, for tier: CarProTier) -> Bool {
        guard let car = car(carId) else { return false }
        return car.setup.stats.pi <= tier.piLimit
    }

    /// Starts (or restarts) a season of `tier` with car `carId`.
    mutating func startSeason(_ tier: CarProTier, carId: String) throws {
        guard isUnlocked(tier) else { throw CarProCareerError.tierLocked }
        guard let car = car(carId) else { throw CarProCareerError.unknownCar }
        let pi = car.setup.stats.pi
        guard pi <= tier.piLimit else { throw CarProCareerError.notEligible(pi: pi, limit: tier.piLimit) }
        seasonsStarted += 1
        let field = CarProField.season(tier, difficulty: settings.difficulty,
                                       seed: CarProRandom.seed(tier.rawValue, salt: UInt64(seasonsStarted)))
        var standings = field.map { CarProStanding(id: $0.id, name: $0.name) }
        standings.append(CarProStanding(id: CarProEntrant.playerId, name: settings.playerName, isPlayer: true))
        season = CarProSeason(tier: tier, field: field, standings: standings, playerCarId: carId)
    }

    mutating func abandonSeason() { season = nil }

    /// The next round of the season in progress, or nil.
    func nextWeekend() -> CarProWeekend? {
        guard let season, !season.complete, let car = car(season.playerCarId) else { return nil }
        let trackId = season.tier.calendar[season.round]
        guard let track = CarProCircuits.track(trackId) else { return nil }
        let player = CarProEntrant.player(name: settings.playerName, setup: car.setup)
        let seed = CarProRandom.seed(trackId, salt: UInt64(seasonsStarted * 31 + season.round))
        return CarProWeekend(tier: season.tier, round: season.round, trackId: trackId, laps: season.tier.laps(on: track),
                             field: season.field, player: player, seed: seed)
    }

    /// Scores a finished championship race: points, prize money, and at the
    /// end of the season the bonus, a title and the next tier.
    @discardableResult
    mutating func recordRace(_ results: [CarProResult], pole: Bool = false) -> CarProRaceReward? {
        guard var season, !season.complete else { return nil }
        let tier = season.tier
        let classified = results.filter { $0.time != nil }
        let fastest = classified.filter { $0.bestLap != nil }.min { ($0.bestLap ?? .infinity) < ($1.bestLap ?? .infinity) }
        var reward = CarProRaceReward(position: results.count, points: 0, prize: 0, fastestLap: false,
                                      championshipPosition: 0, seasonComplete: false, seasonBonus: 0,
                                      unlocked: nil, title: false)
        for result in results {
            guard let index = season.standings.firstIndex(where: { $0.id == result.id }) else { continue }
            var points = 0
            if result.time != nil, result.position <= CarProTier.points.count {
                points = CarProTier.points[result.position - 1]
                if fastest?.id == result.id { points += 1 }
            }
            season.standings[index].points += points
            if result.time != nil && result.position == 1 { season.standings[index].wins += 1 }
            if result.time != nil && result.position <= 3 { season.standings[index].podiums += 1 }
            if result.isPlayer {
                let prize = result.time != nil && result.position <= tier.prizes.count ? tier.prizes[result.position - 1] : 0
                reward.position = result.time == nil ? results.count : result.position
                reward.points = points
                reward.prize = prize
                reward.fastestLap = fastest?.id == result.id && result.time != nil
                money += prize
                stats.earnings += prize
                stats.races += 1
                if result.time != nil && result.position == 1 { stats.wins += 1 }
                if result.time != nil && result.position <= 3 { stats.podiums += 1 }
                if pole { stats.poles += 1 }
                if let car = garage.firstIndex(where: { $0.id == season.playerCarId }) {
                    garage[car].races += 1
                    if result.time != nil && result.position == 1 { garage[car].wins += 1 }
                }
            }
        }
        season.results.append(results.map(\.id))
        season.round += 1
        reward.championshipPosition = season.playerPosition
        if season.complete {
            reward.seasonComplete = true
            let place = season.playerPosition
            if place <= tier.seasonBonus.count {
                reward.seasonBonus = tier.seasonBonus[place - 1]
                money += reward.seasonBonus
                stats.earnings += reward.seasonBonus
            }
            if place == 1 {
                reward.title = true
                if !titles.contains(tier) { titles.append(tier) }
            }
            if place <= 3, let next = tier.next, !unlocked.contains(next) {
                unlocked.append(next)
                reward.unlocked = next
            }
        }
        self.season = season
        return reward
    }

    // MARK: - Time trial

    func best(track: String, model: CarProCarModel) -> Double? {
        bests.first { $0.trackId == track && $0.model == model }?.time
    }

    /// A time-trial lap. True when it is a new best for the track and car.
    @discardableResult
    mutating func recordTimeTrial(track: String, model: CarProCarModel, lap: Double) -> Bool {
        if let index = bests.firstIndex(where: { $0.trackId == track && $0.model == model }) {
            guard lap < bests[index].time else { return false }
            bests[index].time = lap
            return true
        }
        bests.append(CarProBestLap(trackId: track, model: model, time: lap))
        return true
    }

    // MARK: - Saving

    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    /// A career from saved bytes; nil when they are not one, or come from a
    /// newer build than this one (left alone rather than overwritten).
    static func decode(_ data: Data) -> CarProCareer? {
        struct Header: Decodable { var version: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { return nil }
        guard (header.version ?? 1) <= currentVersion else { return nil }
        guard var career = try? JSONDecoder().decode(CarProCareer.self, from: data) else { return nil }
        career.version = currentVersion
        return career
    }
}

/// The AI's qualifying laps: worked out, not driven, so a weekend does not
/// wait for seven cars to lap.
enum CarProQualifying {
    /// About how much slower than the speed profile's perfect lap the AI
    /// really laps at full pace (measured in the tests).
    static let realism = 1.025

    static func estimate(_ entrant: CarProEntrant, track: CarProTrack, seed: UInt64) -> Double {
        let profile = CarProSpeedProfile(track: track, performance: CarProPerformance(params: entrant.setup.params))
        let pace = entrant.driver?.pace ?? 0.95
        var random = CarProRandom(seed: seed ^ CarProRandom.seed(entrant.id))
        let jitter = 1 + 0.006 * random.signed()
        return profile.lapTime * realism / pace * jitter
    }
}

/// AI fields: drivers with names and temperaments, in cars upgraded up to a PI.
enum CarProField {
    static let names = ["Ava Marsh", "Tom Hale", "Priya Shah", "Leo Fenwick", "Maya Okafor", "Sam Rowe",
                        "Isla Grant", "Noah Price", "Zara Quinn", "Ben Carter", "Ruby Lane", "Kai Morgan",
                        "Erin Doyle", "Omar Haddad", "Lily Chen", "Finn Walsh"]

    /// Seven AI entrants for a season of `tier`.
    static func season(_ tier: CarProTier, difficulty: CarProDifficulty, seed: UInt64, count: Int = 7) -> [CarProEntrant] {
        var random = CarProRandom(seed: seed)
        var pool = names
        var field: [CarProEntrant] = []
        let models = tier.fieldModels
        for i in 0..<count {
            let pick = Int(random.next() * Double(pool.count)) % pool.count
            let name = pool.remove(at: pick)
            let spread = count > 1 ? Double(i) / Double(count - 1) : 0.5
            let base = tier.skillRange.lowerBound + (tier.skillRange.upperBound - tier.skillRange.lowerBound) * spread
            let skill = CarProMath.clamp(base + difficulty.skillShift + 0.04 * random.signed(), 0, 1)
            let aggression = CarProMath.clamp(0.2 + 0.6 * random.next(), 0, 1)
            let model = models[Int(random.next() * Double(models.count)) % models.count]
            let target = Int(Double(tier.piLimit) * (0.9 + 0.1 * random.next()))
            let setup = build(model, targetPI: target)
            let id = "ai-" + name.lowercased().replacingOccurrences(of: " ", with: "-")
            let driver = CarProDriverProfile(id: id, name: name, skill: skill, aggression: aggression,
                                             number: 2 + i * 3 % 97, hue: Double((i * 37) % 100) / 100)
            field.append(.ai(driver, setup: setup))
        }
        return field
    }

    /// Opponents for a quick race, in cars near the player's PI.
    static func quickRace(for setup: CarProCarSetup, count: Int, difficulty: CarProDifficulty,
                          seed: UInt64) -> [CarProEntrant] {
        let pi = setup.stats.pi
        let tier = CarProTier.allCases.first { pi <= $0.piLimit } ?? .pro
        var field = season(tier, difficulty: difficulty, seed: seed, count: max(0, min(count, 7)))
        for i in field.indices {
            let model = CarProCarModel.allCases.last { CarProCarSetup(model: $0).stats.pi <= pi + 10 } ?? .hatch
            let candidates: [CarProCarModel] = [setup.model, model]
            let pickModel = candidates[i % candidates.count]
            field[i].setup = build(pickModel, targetPI: pi + (i % 3) * 8 - 8)
        }
        return field
    }

    /// `model` with upgrades added, the biggest PI gain first, while it stays
    /// at or under `targetPI`.
    static func build(_ model: CarProCarModel, targetPI: Int) -> CarProCarSetup {
        var setup = CarProCarSetup(model: model)
        while true {
            var best: (CarProCarSetup, Int)?
            for kind in CarProUpgradeKind.allCases {
                guard let next = setup.withUpgrade(kind) else { continue }
                let pi = next.stats.pi
                if pi <= targetPI && pi > (best?.1 ?? setup.stats.pi) { best = (next, pi) }
            }
            guard let found = best else { break }
            setup = found.0
        }
        return setup
    }
}

/// Where the career and the ghosts live: the career in UserDefaults (small,
/// versioned JSON), each best lap's ghost as a file in Application Support.
struct CarProStore {
    var defaults: UserDefaults = .standard
    var folder: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("CarProGhosts", isDirectory: true)

    static let key = "car-racer-plus.career"

    func load() -> CarProCareer {
        guard let data = defaults.data(forKey: Self.key), let career = CarProCareer.decode(data) else {
            return .newCareer()
        }
        return career
    }

    func save(_ career: CarProCareer) {
        if let data = career.encoded() { defaults.set(data, forKey: Self.key) }
    }

    func ghost(track: String, model: CarProCarModel) -> CarProGhost? {
        guard let url = ghostURL(track: track, model: model), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CarProGhost.self, from: data)
    }

    func saveGhost(_ ghost: CarProGhost) {
        guard let folder, let url = ghostURL(track: ghost.trackId, model: ghost.model),
              let data = try? JSONEncoder().encode(ghost) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func ghostURL(track: String, model: CarProCarModel) -> URL? {
        // Track ids are the app's own kebab-case words; anything else is no file.
        guard let folder, track.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "-" }), !track.isEmpty else {
            return nil
        }
        return folder.appendingPathComponent("car-racer-plus-\(track)-\(model.rawValue).json")
    }
}
