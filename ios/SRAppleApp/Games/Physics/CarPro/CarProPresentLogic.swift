import Foundation

// Car Racer+ words and numbers for the screens: speeds in the player's
// units, the banners a race throws up (sectors, laps, track limits,
// places), the gaps in a results table, where each tier of the career
// stands, and the checks the garage makes before it fits an upgrade.
// Foundation only, so every line a player reads can be tested.

/// How a banner or a figure should read.
enum CarProTone: Equatable {
    case neutral
    /// Quicker than before.
    case good
    /// A personal best.
    case best
    /// Slower than before.
    case warning
    /// Something that cost the player: a lap deleted, a penalty.
    case bad
}

/// A banner over the race for a couple of seconds.
struct CarProBanner: Equatable {
    var title: String
    var detail: String?
    var tone: CarProTone
    /// An SF Symbol.
    var icon: String
    /// A higher one replaces a lower one still showing.
    var priority: Int
    var duration: Double = 2.2
}

/// Where a tier of the career stands for the player.
enum CarProTierState: Equatable {
    case locked
    case open
    /// A season of it is under way.
    case current
    /// Won outright at least once.
    case champion
}

enum CarProPresent {
    // MARK: - Units

    /// A speed in m/s as the speedometer shows it.
    static func speed(_ metresPerSecond: Double, mph: Bool) -> Int {
        Int((abs(metresPerSecond) * (mph ? CarProMath.mph : CarProMath.kmh)).rounded())
    }

    static func speedUnit(mph: Bool) -> String { mph ? "MPH" : "KM/H" }

    static func spokenUnit(mph: Bool) -> String { mph ? "miles an hour" : "kilometres an hour" }

    /// "142 mph".
    static func speedText(_ metresPerSecond: Double, mph: Bool) -> String {
        "\(speed(metresPerSecond, mph: mph)) \(mph ? "mph" : "km/h")"
    }

    /// Brake horsepower from kilowatts.
    static func horsepower(kilowatts: Double) -> Int { Int((kilowatts * 1.341).rounded()) }

    /// "1,080 kg".
    static func mass(_ kilograms: Double) -> String {
        CarProFormat.money(Int(kilograms.rounded())).replacingOccurrences(of: "£", with: "") + " kg"
    }

    /// "62%" of a 0…1 share.
    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

    /// A tyre's temperature against its window: −1 cold … 0 just right … 1 too hot.
    static func tyreHeat(_ temperature: Double, compound: CarProTyreCompound) -> Double {
        CarProMath.clamp((temperature - compound.optimalTemperature) / compound.window, -1, 1)
    }

    /// The final drive tuning as words: shorter gears pull harder, longer go faster.
    static func finalDriveWords(_ value: Double) -> String {
        if value > 1.015 { return "Short: quicker away, lower top speed" }
        if value < 0.985 { return "Long: higher top speed, slower away" }
        return "Factory gearing"
    }

    /// The wing tuning as words.
    static func wingWords(_ value: Double) -> String {
        if value > 0.66 { return "Steep: more grip in the bends, more drag" }
        if value < 0.34 { return "Flat: less drag on the straights, less grip" }
        return "Balanced"
    }

    /// The brake bias as words.
    static func brakeBiasWords(_ value: Double) -> String {
        if value > 0.7 { return "Front-heavy: stable, but the fronts lock first" }
        if value < 0.6 { return "Rear-heavy: turns in, but the rear can step out" }
        return "Balanced"
    }

    // MARK: - Banners

    /// The banner for `event`, or nil for one the player need not see.
    /// `player` is the player's racer index; `laps` the race length (0 unlimited).
    static func banner(for event: CarProEvent, player: Int, kind: CarProSessionKind, laps: Int) -> CarProBanner? {
        switch event {
        case let .sector(racer, sector, time, delta):
            guard racer == player else { return nil }
            var detail = CarProFormat.time(time)
            var tone = CarProTone.neutral
            if let delta {
                detail += "  " + CarProFormat.delta(delta)
                tone = delta < 0 ? .good : .warning
            }
            return CarProBanner(title: "Sector \(sector + 1)", detail: detail, tone: tone, icon: "timer", priority: 1,
                                duration: 1.8)
        case let .lap(racer, lap, time, valid, personalBest):
            guard racer == player else { return nil }
            if kind.isRace && laps > 0 && lap >= laps { return nil }
            if !valid {
                return CarProBanner(title: "Lap \(lap) deleted", detail: "Track limits: \(CarProFormat.time(time))",
                                    tone: .bad, icon: "xmark.octagon.fill", priority: 3)
            }
            if kind.isRace && laps > 1 && lap == laps - 1 {
                return CarProBanner(title: "Final lap", detail: "Last lap \(CarProFormat.time(time))",
                                    tone: personalBest ? .best : .neutral, icon: "flag.checkered", priority: 3,
                                    duration: 2.6)
            }
            if personalBest {
                return CarProBanner(title: "Lap \(lap) · personal best", detail: CarProFormat.time(time), tone: .best,
                                    icon: "stopwatch.fill", priority: 3, duration: 2.6)
            }
            return CarProBanner(title: "Lap \(lap)", detail: CarProFormat.time(time), tone: .neutral,
                                icon: "stopwatch", priority: 2)
        case let .trackLimits(racer, strikes):
            guard racer == player else { return nil }
            if kind.isRace {
                let strike = (strikes - 1) % 3 + 1
                return CarProBanner(title: "Track limits", detail: "Warning \(strike) of 3: the third is 5 seconds",
                                    tone: .warning, icon: "exclamationmark.triangle.fill", priority: 4)
            }
            return CarProBanner(title: "Track limits", detail: "Four wheels off: this lap won't count",
                                tone: .warning, icon: "exclamationmark.triangle.fill", priority: 4)
        case let .penalty(racer, seconds):
            guard racer == player else { return nil }
            return CarProBanner(title: "\(Int(seconds.rounded())) second penalty", detail: "Added to your race time",
                                tone: .bad, icon: "clock.badge.exclamationmark.fill", priority: 5, duration: 3)
        case let .position(from, to):
            guard to != from else { return nil }
            if to < from {
                return CarProBanner(title: "Up to P\(to)", detail: nil, tone: .good, icon: "arrow.up.circle.fill",
                                    priority: 1, duration: 1.4)
            }
            return CarProBanner(title: "Down to P\(to)", detail: nil, tone: .warning, icon: "arrow.down.circle.fill",
                                priority: 1, duration: 1.4)
        case let .finished(racer, position):
            guard racer == player else { return nil }
            if kind.isRace {
                return CarProBanner(title: "Chequered flag", detail: "You finished \(CarProFormat.ordinal(position))",
                                    tone: position <= 3 ? .best : .neutral, icon: "flag.checkered", priority: 6,
                                    duration: 4)
            }
            return CarProBanner(title: "Session over", detail: nil, tone: .neutral, icon: "flag.checkered",
                                priority: 6, duration: 4)
        case .lightsOut:
            return CarProBanner(title: "Go!", detail: nil, tone: .good, icon: "flag.fill", priority: 2, duration: 1)
        default:
            return nil
        }
    }

    // MARK: - Results

    /// The time column of a results row: the winner's race time, everyone
    /// else's gap to them ("+4.215", "+1 lap"), "DNF" without a time.
    static func gap(_ result: CarProResult, leader: CarProResult?) -> String {
        guard let time = result.time else { return "DNF" }
        guard let leader, let leaderTime = leader.time, leader.id != result.id else { return CarProFormat.time(time) }
        let down = leader.laps - result.laps
        if down > 0 { return "+\(down) lap\(down == 1 ? "" : "s")" }
        return "+" + CarProFormat.time(max(0, time - leaderTime))
    }

    /// The points a place scores (fastest lap aside).
    static func points(forPosition position: Int) -> Int {
        guard position >= 1, position <= CarProTier.points.count else { return 0 }
        return CarProTier.points[position - 1]
    }

    // MARK: - Career

    static func state(of tier: CarProTier, in career: CarProCareer) -> CarProTierState {
        if let season = career.season, season.tier == tier, !season.complete { return .current }
        if career.titles.contains(tier) { return .champion }
        return career.isUnlocked(tier) ? .open : .locked
    }

    /// How to open a locked tier.
    static func unlockHint(_ tier: CarProTier) -> String {
        guard let previous = tier.previous else { return "Open from the start." }
        return "Finish a \(previous.name) season in the top three to open it."
    }

    /// The player's finishing place in each round of `season` so far (nil
    /// for rounds still to come).
    static func playerPlaces(_ season: CarProSeason) -> [Int?] {
        season.tier.calendar.indices.map { round in
            guard round < season.results.count,
                  let index = season.results[round].firstIndex(of: CarProEntrant.playerId) else { return nil }
            return index + 1
        }
    }

    /// The car's PI is over the limit of the season it is racing in: the
    /// tier it would be thrown out of, or nil when it is fine.
    static func seasonLimitBreached(career: CarProCareer, carId: String, pi: Int) -> CarProTier? {
        guard let season = career.season, !season.complete, season.playerCarId == carId,
              pi > season.tier.piLimit else { return nil }
        return season.tier
    }

    /// The tiers `pi` can race in, lowest first.
    static func eligibleTiers(pi: Int) -> [CarProTier] {
        CarProTier.allCases.filter { pi <= $0.piLimit }
    }

    /// "Club Cup and up" or "Pro Championship only" for a car card.
    static func tierLine(pi: Int) -> String {
        let tiers = eligibleTiers(pi: pi)
        guard let first = tiers.first else { return "Too quick for any tier" }
        if tiers.count == 1 { return "\(first.name) only" }
        return "\(first.name) and up"
    }

    /// What the career said no to, as a sentence.
    static func words(for error: CarProCareerError) -> String {
        switch error {
        case let .notEnoughMoney(needed): return "You need \(CarProFormat.money(needed)) more for that."
        case .alreadyOwned: return "That car is already in your garage."
        case .unknownCar: return "That car isn't in your garage."
        case .maxedOut: return "That's already at its top stage."
        case .tierLocked: return "That championship isn't open yet."
        case let .notEligible(pi, limit): return "This car's PI is \(pi), over the limit of \(limit)."
        case .noSeason: return "There's no season running."
        }
    }

    /// A season's prize money if the player won every round, for the tier card.
    static func seasonPurse(_ tier: CarProTier) -> Int {
        (tier.prizes.first ?? 0) * tier.calendar.count + (tier.seasonBonus.first ?? 0)
    }
}

/// Where the player lines up for a quick race.
enum CarProGridStart: String, Codable, CaseIterable, Identifiable {
    case pole
    case middle
    case back

    var id: String { rawValue }

    var name: String {
        switch self {
        case .pole: return "Pole"
        case .middle: return "Middle"
        case .back: return "Back"
        }
    }

    /// The grid slot (0 is pole) in a field of `opponents` plus the player.
    func slot(opponents: Int) -> Int {
        switch self {
        case .pole: return 0
        case .middle: return max(0, opponents) / 2
        case .back: return max(0, opponents)
        }
    }
}

/// The player's last quick-race and time-trial choices, kept between visits.
struct CarProQuickSetup: Codable, Equatable {
    static let key = "car-racer-plus.quick"
    static let lapChoices = [2, 3, 5, 8]
    static let fieldChoices = [3, 5, 7]

    var trackId = CarProCircuits.ids.first ?? "brackenfield"
    var laps = 3
    var opponents = 5
    var start = CarProGridStart.back
    var trialTrackId = CarProCircuits.ids.first ?? "brackenfield"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = CarProCircuits.ids.first ?? "brackenfield"
        let track = try c.decodeIfPresent(String.self, forKey: .trackId) ?? fallback
        trackId = CarProCircuits.ids.contains(track) ? track : fallback
        let savedLaps = try c.decodeIfPresent(Int.self, forKey: .laps) ?? 3
        let savedField = try c.decodeIfPresent(Int.self, forKey: .opponents) ?? 5
        laps = min(max(savedLaps, 1), 10)
        opponents = min(max(savedField, 1), 7)
        start = try c.decodeIfPresent(CarProGridStart.self, forKey: .start) ?? .back
        let trial = try c.decodeIfPresent(String.self, forKey: .trialTrackId) ?? fallback
        trialTrackId = CarProCircuits.ids.contains(trial) ? trial : fallback
    }

    static func load(_ defaults: UserDefaults = .standard) -> CarProQuickSetup {
        guard let data = defaults.data(forKey: key),
              let setup = try? JSONDecoder().decode(CarProQuickSetup.self, from: data) else { return CarProQuickSetup() }
        return setup
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}
