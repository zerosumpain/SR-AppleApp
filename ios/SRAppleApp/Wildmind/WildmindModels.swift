import Foundation

// MARK: - Wildmind, as the site sends it
//
// `GET /api/native/wildmind?have=<terrainVersion>` (SR-Main, owner only):
// `{ state, ageSeconds, snapshot, terrain }`. The snapshot is Wildmind's own
// public snapshot after SR-Main's allow-list, without the terrain and with a
// fixed `doing` word on each person; the terrain is the raw explored grid,
// sent only when the phone does not already hold that version.
//
// Foundation only, on purpose, like the pen: the decoders are the part of
// this screen most likely to meet something new from the server, and the
// only part that can be compiled and RUN on Linux, where there is no Mac to
// build the app on. `WildmindGrid.swift` turns the grid into cells, and
// `WildmindWords.swift` turns the figures into the chapter's sentences.
//
// Tolerant throughout. Wildmind is a game that grows: a new weather, a new
// kind of structure or a new activity must read as "something" rather than
// throw the whole valley away. Every optional field is `decodeIfPresent`, every
// list drops the rows it cannot read and keeps the rest, and every enum has a
// place for a word it has not met.

/// What the valley is doing, as SR-Main reads it: `live`, `resting` (the minds
/// are out of today's budget and run on habit), `paused` (Wildmind's `halted`
/// too), `between-lives` (the main character is dead), `stale` (the last good
/// read is over two minutes old, still drawn, in the past tense) or `offline`
/// (nothing at all to draw).
enum WildmindState: String, Sendable, Equatable {
    case live
    case resting
    case paused
    case betweenLives = "between-lives"
    case stale
    case offline
    /// A state this build has not heard of: drawn, without a state line.
    case unknown

    init(raw: String?) {
        self = raw.flatMap(WildmindState.init(rawValue:)) ?? (raw == nil ? .offline : .unknown)
    }

    /// Seconds between asks while the screen is up. The web chapter's cadence:
    /// ten while they are awake, thirty while nothing much moves, a minute
    /// when the valley is not answering.
    var cadence: Int {
        switch self {
        case .live: return 10
        case .resting, .paused, .betweenLives: return 30
        case .stale, .offline, .unknown: return 60
        }
    }

    /// Whatever is on the map happened, rather than is happening.
    var pastTense: Bool { self == .stale || self == .paused }
}

/// The whole answer.
struct WildmindAnswer: Decodable, Sendable {
    var state: WildmindState
    var ageSeconds: Double?
    var snapshot: WildmindSnapshot?
    var terrain: WildmindTerrain?

    init(state: WildmindState, ageSeconds: Double? = nil, snapshot: WildmindSnapshot?, terrain: WildmindTerrain?) {
        self.state = state
        self.ageSeconds = ageSeconds
        self.snapshot = snapshot
        self.terrain = terrain
    }

    private enum CodingKeys: String, CodingKey { case state, ageSeconds, snapshot, terrain }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = WildmindState(raw: c.wmString(.state))
        ageSeconds = c.wmNumber(.ageSeconds)
        // A snapshot or a terrain that cannot be read is no snapshot or no
        // terrain — the screen says the valley is quiet, or draws the words
        // without a map — never a failed request.
        snapshot = try? c.decodeIfPresent(WildmindSnapshot.self, forKey: .snapshot)
        terrain = try? c.decodeIfPresent(WildmindTerrain.self, forKey: .terrain)
    }
}

/// The valley at one moment, without its terrain.
struct WildmindSnapshot: Decodable, Sendable {
    var status: String?
    /// The terrain version this snapshot was drawn on, sent back as `?have=`.
    var terrainVersion: String?
    var time: WildmindTime
    /// The main character first, then the companion. Normally two.
    var people: [WildmindPerson]
    /// The index table the animals point into.
    var species: [String]
    var animals: [WildmindAnimal]
    var structures: [WildmindStructure]
    /// Burning ground or trees on seen tiles.
    var fires: [WildmindPoint]
    var stats: WildmindStats

    init(status: String? = nil, terrainVersion: String? = nil, time: WildmindTime, people: [WildmindPerson],
         species: [String] = [], animals: [WildmindAnimal] = [], structures: [WildmindStructure] = [],
         fires: [WildmindPoint] = [], stats: WildmindStats) {
        self.status = status
        self.terrainVersion = terrainVersion
        self.time = time
        self.people = people
        self.species = species
        self.animals = animals
        self.structures = structures
        self.fires = fires
        self.stats = stats
    }

    private enum CodingKeys: String, CodingKey {
        case status, terrainVersion, time, people, species, animals, structures, fires, stats
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = c.wmString(.status)
        terrainVersion = c.wmString(.terrainVersion)
        time = (try? c.decodeIfPresent(WildmindTime.self, forKey: .time)) ?? WildmindTime()
        people = c.wmList(.people)
        species = c.wmList(.species)
        animals = c.wmList(.animals)
        structures = c.wmList(.structures)
        fires = c.wmList(.fires)
        stats = (try? c.decodeIfPresent(WildmindStats.self, forKey: .stats)) ?? WildmindStats()
    }

    /// The main character, if the valley has one.
    var main: WildmindPerson? { people.first { $0.isMain } ?? people.first }
    /// The companion, if there is one.
    var companion: WildmindPerson? { people.first { !$0.isMain && $0.id != main?.id } }
}

/// Game time. Never a clock: the valley's day runs faster than ours.
struct WildmindTime: Decodable, Sendable, Equatable {
    var day: Int?
    var season: String?
    var dayOfSeason: Int?
    /// 0–24.
    var hour: Double?
    /// 0 at midnight, 1 at noon.
    var daylight: Double?
    var weather: String?
    var tempC: Double?

    init(day: Int? = nil, season: String? = nil, dayOfSeason: Int? = nil, hour: Double? = nil,
         daylight: Double? = nil, weather: String? = nil, tempC: Double? = nil) {
        self.day = day
        self.season = season
        self.dayOfSeason = dayOfSeason
        self.hour = hour
        self.daylight = daylight
        self.weather = weather
        self.tempC = tempC
    }

    private enum CodingKeys: String, CodingKey { case day, season, dayOfSeason, hour, daylight, weather, tempC }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = c.wmInt(.day)
        season = c.wmString(.season)
        dayOfSeason = c.wmInt(.dayOfSeason)
        hour = c.wmNumber(.hour)
        daylight = c.wmNumber(.daylight)
        weather = c.wmString(.weather)
        tempC = c.wmNumber(.tempC)
    }

    /// How dark it is, 0–1: `1 - daylight`, as SR-Main works it out.
    var night: Double { 1 - min(1, max(0, daylight ?? 1)) }
    /// The site draws the moon, and says "night", from half dark.
    var isNight: Bool { night >= 0.5 }
}

/// One of the two people in the valley.
struct WildmindPerson: Decodable, Sendable, Identifiable, Equatable {
    /// `main` or `companion`.
    var id: String
    var name: String
    /// World tiles: x runs east, z runs south.
    var x: Double
    var z: Double
    /// Radians; facing is `(sin h, cos h)` in (x, z).
    var heading: Double
    var activity: String?
    /// SR-Main's fixed word for the activity ("asleep", "at work", "busy").
    var doing: String
    var alive: Bool
    /// Deciding with the model just now, rather than running a habit.
    var thinking: Bool
    /// The nearest place they have seen, within 24 metres.
    var near: String?
    /// Where they have been lately, oldest first, at most twelve.
    var trail: [WildmindPoint]
    /// `good`, `getting-by` or `low`.
    var morale: String?

    init(id: String, name: String, x: Double, z: Double, heading: Double = 0, activity: String? = nil,
         doing: String = "busy", alive: Bool = true, thinking: Bool = false, near: String? = nil,
         trail: [WildmindPoint] = [], morale: String? = nil) {
        self.id = id
        self.name = name
        self.x = x
        self.z = z
        self.heading = heading
        self.activity = activity
        self.doing = doing
        self.alive = alive
        self.thinking = thinking
        self.near = near
        self.trail = trail
        self.morale = morale
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, x, z, heading, activity, doing, alive, thinking, near, trail, morale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.wmString(.id) ?? "main"
        // SR-Main's own fallbacks, so a bounded-out name never leaves a blank.
        let fallback = id == "main" ? "JKai" : "their companion"
        let named = c.wmString(.name)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        name = named.isEmpty ? fallback : named
        guard let x = c.wmNumber(.x), let z = c.wmNumber(.z) else {
            throw DecodingError.dataCorruptedError(forKey: .x, in: c, debugDescription: "a person with nowhere to stand")
        }
        self.x = x
        self.z = z
        heading = c.wmNumber(.heading) ?? 0
        activity = c.wmString(.activity)
        alive = c.wmBool(.alive) ?? true
        thinking = c.wmBool(.thinking) ?? false
        // The site's word when it sent one; otherwise the same mapping, here.
        doing = c.wmString(.doing) ?? WildmindPerson.doingWord(activity: activity, alive: alive)
        near = c.wmString(.near)
        trail = c.wmList(.trail)
        morale = c.wmString(.morale)
    }

    var isMain: Bool { id == "main" }

    /// SR-Main's `DOING`: the fixed word for an activity. Free text never
    /// crosses; an activity this build does not know reads "busy".
    static func doingWord(activity: String?, alive: Bool) -> String {
        guard alive else { return "dead" }
        switch activity {
        case "idle": return "standing about"
        case "walking": return "walking"
        case "working": return "at work"
        case "sleeping": return "asleep"
        case "thinking": return "thinking it over"
        case "talking": return "talking"
        case "eating": return "eating"
        case "riding": return "riding"
        case "dead": return "dead"
        default: return "busy"
        }
    }
}

/// A point in world tiles, sent as `[x, z]`.
struct WildmindPoint: Decodable, Sendable, Equatable {
    var x: Double
    var z: Double

    init(x: Double, z: Double) {
        self.x = x
        self.z = z
    }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        z = try c.decode(Double.self)
        guard x.isFinite, z.isFinite else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a place")
        }
    }
}

/// An animal, sent as `[speciesIndex, x, z, tame]`.
struct WildmindAnimal: Decodable, Sendable, Equatable {
    var species: Int
    var x: Double
    var z: Double
    var tame: Bool

    init(species: Int, x: Double, z: Double, tame: Bool = false) {
        self.species = species
        self.x = x
        self.z = z
        self.tame = tame
    }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let index = try c.decode(Double.self)
        guard index >= 0, index < 1e6 else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "no such species")
        }
        species = Int(index)
        x = try c.decode(Double.self)
        z = try c.decode(Double.self)
        tame = c.isAtEnd ? false : WildmindFlag.next(&c)
    }
}

/// What a structure is FOR, worked out from what it does — never its name.
enum WildmindStructureKind: String, Sendable, Equatable {
    case shelter, store, fire, pen, other

    init(raw: String?) { self = raw.flatMap(WildmindStructureKind.init(rawValue:)) ?? .other }
}

/// A structure, sent as `[x, z, complete, lit, class]`.
struct WildmindStructure: Decodable, Sendable, Equatable {
    var x: Double
    var z: Double
    var complete: Bool
    var lit: Bool
    var kind: WildmindStructureKind

    init(x: Double, z: Double, complete: Bool = true, lit: Bool = false, kind: WildmindStructureKind = .shelter) {
        self.x = x
        self.z = z
        self.complete = complete
        self.lit = lit
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        z = try c.decode(Double.self)
        complete = c.isAtEnd ? true : WildmindFlag.next(&c)
        lit = c.isAtEnd ? false : WildmindFlag.next(&c)
        var raw: String?
        if !c.isAtEnd { raw = try? c.decode(String.self) }
        kind = WildmindStructureKind(raw: raw)
    }
}

/// The figures under the map.
struct WildmindStats: Decodable, Sendable, Equatable {
    /// Which life of the line this is: 1 for the first.
    var generation: Int?
    /// Newest first, at most twelve.
    var earlierLives: [WildmindLife]
    var invented: Int?
    /// The newest inventions, newest first, at most three.
    var latest: [WildmindInvention]
    /// Ideas the referee threw out.
    var refused: Int?
    var placesFound: Int?
    var exploredTiles: Int?
    var built: WildmindBuilt
    var tamed: Int?
    /// `nil` when the site did not say.
    var met: Bool?
    var habit: WildmindHabit?
    var models: WildmindModels

    init(generation: Int? = nil, earlierLives: [WildmindLife] = [], invented: Int? = nil,
         latest: [WildmindInvention] = [], refused: Int? = nil, placesFound: Int? = nil,
         exploredTiles: Int? = nil, built: WildmindBuilt = WildmindBuilt(), tamed: Int? = nil,
         met: Bool? = nil, habit: WildmindHabit? = nil, models: WildmindModels = WildmindModels()) {
        self.generation = generation
        self.earlierLives = earlierLives
        self.invented = invented
        self.latest = latest
        self.refused = refused
        self.placesFound = placesFound
        self.exploredTiles = exploredTiles
        self.built = built
        self.tamed = tamed
        self.met = met
        self.habit = habit
        self.models = models
    }

    private enum CodingKeys: String, CodingKey {
        case generation, earlierLives, invented, latest, refused, placesFound, exploredTiles, built, tamed
        case milestones, choices, models
    }

    private enum MilestoneKeys: String, CodingKey { case met }
    private enum ChoiceKeys: String, CodingKey { case thought, habit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generation = c.wmInt(.generation)
        earlierLives = c.wmList(.earlierLives)
        invented = c.wmInt(.invented)
        latest = c.wmList(.latest)
        refused = c.wmInt(.refused)
        placesFound = c.wmInt(.placesFound)
        exploredTiles = c.wmInt(.exploredTiles)
        built = (try? c.decodeIfPresent(WildmindBuilt.self, forKey: .built)) ?? WildmindBuilt()
        tamed = c.wmInt(.tamed)
        if let milestones = try? c.nestedContainer(keyedBy: MilestoneKeys.self, forKey: .milestones) {
            met = milestones.wmBool(.met)
        }
        if let choices = try? c.nestedContainer(keyedBy: ChoiceKeys.self, forKey: .choices) {
            habit = WildmindHabit(thought: choices.wmInt(.thought) ?? 0, habit: choices.wmInt(.habit) ?? 0)
        }
        models = (try? c.decodeIfPresent(WildmindModels.self, forKey: .models)) ?? WildmindModels()
    }
}

/// An earlier life of the line.
struct WildmindLife: Decodable, Sendable, Equatable {
    /// Its place in the line; `nil` when the site could not number them.
    var n: Int?
    var days: Double
    /// `starvation`, `thirst`, `cold`, `exhaustion`, `injuries`, or `nil`.
    var cause: String?

    init(n: Int?, days: Double, cause: String?) {
        self.n = n
        self.days = days
        self.cause = cause
    }

    private enum CodingKeys: String, CodingKey { case n, days, cause }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = c.wmInt(.n)
        days = max(0, c.wmNumber(.days) ?? 0)
        cause = c.wmString(.cause)
    }
}

/// Something they made up and the referee let through.
struct WildmindInvention: Decodable, Sendable, Equatable {
    var name: String
    var kind: String?
    var day: Int?
    /// `main` or `companion`.
    var by: String?

    init(name: String, kind: String? = nil, day: Int? = nil, by: String? = nil) {
        self.name = name
        self.kind = kind
        self.day = day
        self.by = by
    }

    private enum CodingKeys: String, CodingKey { case name, kind, day, by }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let name = c.wmString(.name)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .name, in: c, debugDescription: "an invention with no name")
        }
        self.name = name
        kind = c.wmString(.kind)
        day = c.wmInt(.day)
        by = c.wmString(.by)
    }
}

/// Complete structures anywhere in the valley, by what they are for.
struct WildmindBuilt: Decodable, Sendable, Equatable {
    var shelter = 0
    var store = 0
    var fire = 0
    var pen = 0
    var other = 0

    init(shelter: Int = 0, store: Int = 0, fire: Int = 0, pen: Int = 0, other: Int = 0) {
        self.shelter = shelter
        self.store = store
        self.fire = fire
        self.pen = pen
        self.other = other
    }

    private enum CodingKeys: String, CodingKey { case shelter, store, fire, pen, other }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shelter = max(0, c.wmInt(.shelter) ?? 0)
        store = max(0, c.wmInt(.store) ?? 0)
        fire = max(0, c.wmInt(.fire) ?? 0)
        pen = max(0, c.wmInt(.pen) ?? 0)
        other = max(0, c.wmInt(.other) ?? 0)
    }

    var total: Int { shelter + store + fire + pen + other }
}

/// How much of what they do is habit rather than a fresh thought, in the
/// site's three bands (`habitShare`): over 60% "most", 40% or more "about
/// half", otherwise "some".
enum WildmindHabit: String, Sendable, Equatable {
    case most
    case aboutHalf = "about-half"
    case some

    init?(thought: Int, habit: Int) {
        let all = thought + habit
        guard all > 0 else { return nil }
        let share = Double(habit) / Double(all)
        self = share > 0.6 ? .most : share >= 0.4 ? .aboutHalf : .some
    }
}

/// The two Claude models: one thinks for them, one designs what they invent.
struct WildmindModels: Decodable, Sendable, Equatable {
    /// Display names ("Haiku"), or `nil` when unknown.
    var mind: String?
    var designer: String?

    init(mind: String? = nil, designer: String? = nil) {
        self.mind = mind
        self.designer = designer
    }

    private enum CodingKeys: String, CodingKey { case mind, designer }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mind = WildmindModels.displayName(c.wmString(.mind))
        designer = WildmindModels.displayName(c.wmString(.designer))
    }

    /// Model ids are not mapped by the site: "claude-haiku-5-5" is "Haiku",
    /// and so on; anything else Claude-shaped is "a Claude model". Empty or
    /// "unknown" is nothing at all — the sentence leaves that half out.
    static func displayName(_ id: String?) -> String? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
              id.lowercased() != "unknown" else { return nil }
        let lower = id.lowercased()
        if lower.contains("haiku") { return "Haiku" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("opus") { return "Opus" }
        return "a Claude model"
    }
}

/// A named place, at rounded world tiles.
struct WildmindRegion: Decodable, Sendable, Equatable {
    var name: String
    /// `l` landmark, `h` habitat, `r` anything else.
    var kind: String
    var x: Double
    var z: Double

    init(name: String, kind: String, x: Double, z: Double) {
        self.name = name
        self.kind = kind
        self.x = x
        self.z = z
    }

    private enum CodingKeys: String, CodingKey { case n, k, x, z }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let name = c.wmString(.n)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
              let x = c.wmNumber(.x), let z = c.wmNumber(.z) else {
            throw DecodingError.dataCorruptedError(forKey: .n, in: c, debugDescription: "a place with no name")
        }
        self.name = name
        kind = c.wmString(.k) ?? "r"
        self.x = x
        self.z = z
    }

    var isLandmark: Bool { kind == "l" }
}

/// The explored grid, as sent: two base64 byte planes and an index table.
/// `WildmindGrid` decodes it.
struct WildmindTerrain: Decodable, Sendable, Equatable {
    /// World tile of cell (0, 0).
    var originX: Int
    var originZ: Int
    /// World tiles per cell, along each axis.
    var step: Int
    var w: Int
    var h: Int
    /// `t` byte k > 0 means `terrains[k - 1]`.
    var terrains: [String]
    /// Base64, `w * h` bytes, row-major: cell (i, j) at `j * w + i`; 0 unseen.
    var t: String
    /// Base64, `w * h` bytes; 0 unseen, else height `byte / 10 - 2`.
    var height: String
    var regions: [WildmindRegion]

    init(originX: Int, originZ: Int, step: Int, w: Int, h: Int, terrains: [String], t: String, height: String,
         regions: [WildmindRegion] = []) {
        self.originX = originX
        self.originZ = originZ
        self.step = step
        self.w = w
        self.h = h
        self.terrains = terrains
        self.t = t
        self.height = height
        self.regions = regions
    }

    private enum CodingKeys: String, CodingKey { case origin, step, w, h, terrains, t, height, regions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let origin: [Double] = c.wmList(.origin)
        guard let w = c.wmInt(.w), let h = c.wmInt(.h), w >= 0, h >= 0, w <= 512, h <= 512,
              let t = c.wmString(.t) else {
            throw DecodingError.dataCorruptedError(forKey: .w, in: c, debugDescription: "no grid")
        }
        // Wildmind bounds coordinates to ±70 000; anything wilder is not a grid.
        guard origin.allSatisfy({ abs($0) < 1e7 }) else {
            throw DecodingError.dataCorruptedError(forKey: .origin, in: c, debugDescription: "no such place")
        }
        originX = origin.count > 0 ? Int(origin[0].rounded()) : 0
        originZ = origin.count > 1 ? Int(origin[1].rounded()) : 0
        step = max(1, c.wmInt(.step) ?? 1)
        self.w = w
        self.h = h
        terrains = c.wmList(.terrains)
        self.t = t
        height = c.wmString(.height) ?? ""
        regions = c.wmList(.regions)
    }
}

// MARK: - The public chapter, for a site without the native route

/// `GET /api/landing/wildmind`: the public landing chapter's answer, read for
/// its WORDS only when the native route is not on the site yet (a 404). It
/// carries no world coordinates and no grid, so there is no map from it; what
/// it does carry becomes a snapshot the readings can be written from.
struct WildmindPublicChapter: Decodable, Sendable {
    var state: WildmindState
    var snapshot: WildmindSnapshot?

    private enum CodingKeys: String, CodingKey {
        case state, day, season, weather, night, people, invented, latest, refused, placesFound
        case exploredTiles, generation, earlierLives, habitShare, models, met
    }

    private struct Person: Decodable {
        var person: WildmindPerson

        private enum CodingKeys: String, CodingKey { case id, name, doing, alive, thinking, near }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let id = c.wmString(.id) ?? "main"
            let alive = c.wmBool(.alive) ?? true
            person = WildmindPerson(
                id: id,
                name: c.wmString(.name) ?? (id == "main" ? "JKai" : "their companion"),
                x: 0, z: 0,
                doing: c.wmString(.doing) ?? (alive ? "busy" : "dead"),
                alive: alive,
                thinking: c.wmBool(.thinking) ?? false,
                near: c.wmString(.near)
            )
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = WildmindState(raw: c.wmString(.state))
        guard state != .offline else {
            snapshot = nil
            return
        }
        let night = c.wmNumber(.night)
        let people: [Person] = c.wmList(.people)
        let names: [String] = c.wmList(.latest)
        let models = try? c.decodeIfPresent(WildmindModels.self, forKey: .models)
        snapshot = WildmindSnapshot(
            time: WildmindTime(day: c.wmInt(.day), season: c.wmString(.season),
                               daylight: night.map { 1 - $0 }, weather: c.wmString(.weather)),
            people: people.map(\.person),
            stats: WildmindStats(
                generation: c.wmInt(.generation),
                earlierLives: c.wmList(.earlierLives),
                invented: c.wmInt(.invented),
                latest: names.map { WildmindInvention(name: $0) },
                refused: c.wmInt(.refused),
                placesFound: c.wmInt(.placesFound),
                exploredTiles: c.wmInt(.exploredTiles),
                met: c.wmBool(.met),
                habit: c.wmString(.habitShare).flatMap(WildmindHabit.init(rawValue:)),
                models: models ?? WildmindModels()
            )
        )
    }
}

// MARK: - Tolerant decoding

/// A list that keeps the rows it can read and steps over the rest.
struct WildmindLossyList<T: Decodable>: Decodable {
    var items: [T] = []

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        while !c.isAtEnd {
            let before = c.currentIndex
            if let item = try? c.decode(T.self) {
                items.append(item)
                continue
            }
            // Step over the row that would not read. A failed decode does not
            // move the container on, so skip it explicitly — and if even that
            // cannot move it, stop rather than spin.
            if (try? c.decodeNil()) != true {
                _ = try? c.decode(WildmindSkip.self)
            }
            if c.currentIndex == before { break }
        }
    }
}

/// Reads any JSON value and keeps nothing.
private struct WildmindSkip: Decodable {
    init(from decoder: Decoder) throws {}
}

/// A 0/1 flag inside a tuple row, also accepted as a JSON boolean.
enum WildmindFlag {
    static func next(_ c: inout UnkeyedDecodingContainer) -> Bool {
        if let number = try? c.decode(Double.self) { return number != 0 }
        if let flag = try? c.decode(Bool.self) { return flag }
        _ = try? c.decodeNil()
        return false
    }
}

extension KeyedDecodingContainer {
    /// A number, or `nil` when it is missing, `null`, not a number or not finite.
    func wmNumber(_ key: Key) -> Double? {
        guard let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite else { return nil }
        return value
    }

    /// A whole number, accepting `3.0` as 3.
    func wmInt(_ key: Key) -> Int? {
        guard let value = wmNumber(key), abs(value) < 1e15 else { return nil }
        return Int(value.rounded())
    }

    func wmString(_ key: Key) -> String? {
        try? decodeIfPresent(String.self, forKey: key)
    }

    func wmBool(_ key: Key) -> Bool? {
        if let flag = try? decodeIfPresent(Bool.self, forKey: key) { return flag }
        return wmNumber(key).map { $0 != 0 }
    }

    /// The readable rows of a list; empty when the list is missing or is not one.
    func wmList<T: Decodable>(_ key: Key) -> [T] {
        (try? decodeIfPresent(WildmindLossyList<T>.self, forKey: key))?.items ?? []
    }
}
