import Foundation

/// How Hop is steered. Bests are kept for each, so tilting and pressing are
/// never compared.
enum SkyHopperControl: String, CaseIterable, Codable, Identifiable {
    case tilt, buttons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tilt: return "Tilt"
        case .buttons: return "Buttons"
        }
    }

    var icon: String {
        switch self {
        case .tilt: return "rotate.right"
        case .buttons: return "arrow.left.arrow.right"
        }
    }

    var line: String {
        switch self {
        case .tilt: return "Lean the phone left and right."
        case .buttons: return "Hold the big arrows under the sky."
        }
    }
}

/// Hop's colours. The first is everyone's; the rest open as stars are
/// collected, across every game.
enum SkyHopperColour: String, CaseIterable, Codable, Identifiable {
    case sunny, mint, berry, ocean, rainbow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sunny: return "Sunny"
        case .mint: return "Mint"
        case .berry: return "Berry"
        case .ocean: return "Ocean"
        case .rainbow: return "Rainbow"
        }
    }

    /// Stars collected in all before this colour opens.
    var unlockStars: Int {
        switch self {
        case .sunny: return 0
        case .mint: return 50
        case .berry: return 150
        case .ocean: return 300
        case .rainbow: return 600
        }
    }
}

/// The best with one way of steering.
struct SkyHopperBest: Codable, Equatable {
    var score = 0
    var metres = 0
    var stars = 0
    var games = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        metres = (try? c.decodeIfPresent(Int.self, forKey: .metres)) ?? 0
        stars = (try? c.decodeIfPresent(Int.self, forKey: .stars)) ?? 0
        games = (try? c.decodeIfPresent(Int.self, forKey: .games)) ?? 0
    }
}

/// How one run went, for the results card.
struct SkyHopperRunResult: Equatable {
    let control: SkyHopperControl
    let score: Int
    let metres: Int
    let stars: Int
    let best: Int
    let bestMetres: Int
    let newBest: Bool
    let springs: Int
    let powerUps: Int
    let saves: Int
    let zone: SkyHopperZone
    let fall: SkyHopperFall
    /// Colours this run opened, in words: "Mint".
    let unlockedColours: [String]
}

/// Everything Sky Hopper keeps on this phone: a best for tilt and one for
/// buttons, the running star total that opens colours, and the last
/// settings used.
struct SkyHopperRecords: Codable, Equatable {
    var bests: [String: SkyHopperBest] = [:]
    var totalStars = 0
    var games = 0
    /// Nil until the player has chosen: the screen then picks tilt if the
    /// phone has a sensor.
    var control: SkyHopperControl?
    var colour: SkyHopperColour = .sunny

    init() {}

    /// Lenient: a field added in a later version leaves the rest readable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bests = (try? c.decodeIfPresent([String: SkyHopperBest].self, forKey: .bests)) ?? [:]
        totalStars = (try? c.decodeIfPresent(Int.self, forKey: .totalStars)) ?? 0
        games = (try? c.decodeIfPresent(Int.self, forKey: .games)) ?? 0
        control = (try? c.decodeIfPresent(SkyHopperControl.self, forKey: .control)) ?? nil
        colour = (try? c.decodeIfPresent(SkyHopperColour.self, forKey: .colour)) ?? .sunny
    }

    func best(_ control: SkyHopperControl) -> SkyHopperBest { bests[control.rawValue] ?? SkyHopperBest() }

    func isUnlocked(_ colour: SkyHopperColour) -> Bool { totalStars >= colour.unlockStars }

    /// The colour to draw: the one chosen if it is open, else the first.
    var activeColour: SkyHopperColour { isUnlocked(colour) ? colour : .sunny }

    /// The next colour still to open, if any.
    var nextColour: SkyHopperColour? { SkyHopperColour.allCases.first { !isUnlocked($0) } }

    /// The control to use: the one chosen, else tilt when there is a sensor.
    func control(tiltAvailable: Bool) -> SkyHopperControl {
        guard tiltAvailable else { return .buttons }
        return control ?? .tilt
    }

    /// A finished run. Files the best and the totals and says what it opened.
    mutating func record(_ game: SkyHopperGame, control: SkyHopperControl) -> SkyHopperRunResult {
        let before = Set(SkyHopperColour.allCases.filter { isUnlocked($0) })
        var entry = best(control)
        let score = game.score
        let newBest = score > entry.score
        entry.games += 1
        if newBest { entry.score = score }
        entry.metres = max(entry.metres, game.metres)
        entry.stars = max(entry.stars, game.stars)
        bests[control.rawValue] = entry
        totalStars += game.stars
        games += 1
        let opened = SkyHopperColour.allCases.filter { isUnlocked($0) && !before.contains($0) }.map(\.title)
        return SkyHopperRunResult(control: control, score: score, metres: game.metres, stars: game.stars,
                                  best: entry.score, bestMetres: entry.metres, newBest: newBest && score > 0,
                                  springs: game.springs, powerUps: game.powerUps, saves: game.saves,
                                  zone: game.zone, fall: game.fall ?? .missed, unlockedColours: opened)
    }
}

/// Where the records live: one small JSON value in UserDefaults.
struct SkyHopperRecordStore {
    var defaults: UserDefaults = .standard

    static let key = "sky-hopper.records.v1"

    func load() -> SkyHopperRecords {
        guard let data = defaults.data(forKey: Self.key),
              let records = try? JSONDecoder().decode(SkyHopperRecords.self, from: data) else { return SkyHopperRecords() }
        return records
    }

    func save(_ records: SkyHopperRecords) {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.key) }
    }
}
