import Foundation

// Pass the Plate's wire pieces and the little the phone works out itself —
// which cards a tap has chosen, the turn clock, the sentences — as pure values,
// so each is a unit test. The server deals, judges every pick, passes the
// plates and scores every round; nothing here decides a point.
//
// The room's side is decoded whole into `PassThePlateState`, read off the same
// JSON as `GameRoom` (`GameRoom.passThePlate`). Spec: SR-Main
// docs/superpowers/specs/2026-10-22-family-games-pass-the-plate.md.

/// Where a Pass the Plate room is. Read from the raw `phase`, so the shared
/// `GamePhase` needs no new case: `picking` and `scoring` decode there as
/// `.unknown`, and here as themselves.
enum PassThePlatePhase: String, Equatable {
    case lobby, countdown, picking, scoring, finished, closed, unknown

    static func from(_ raw: String?) -> PassThePlatePhase {
        guard let raw else { return .unknown }
        return PassThePlatePhase(rawValue: raw) ?? .unknown
    }
}

/// What the room shows to help, by difficulty: per-card gains (easy), a
/// running total (medium), nothing (hard).
enum PassThePlateHints: String, Equatable {
    case gains, total, none
}

/// One kind of card, as the room's reference card describes it.
struct PlateKind: Decodable, Equatable, Identifiable {
    let kind: String
    let name: String
    let emoji: String
    /// pair | triple | sliding | majority | pie | multiplier | takeTwo | dessert
    let family: String
    let count: Int
    /// Berries on the card, or a pie's points.
    let value: Int
    let rule: String

    var id: String { kind }

    init(kind: String, name: String, emoji: String, family: String, count: Int = 0, value: Int = 0, rule: String) {
        self.kind = kind; self.name = name; self.emoji = emoji; self.family = family
        self.count = count; self.value = value; self.rule = rule
    }

    private enum CodingKeys: String, CodingKey { case kind, name, emoji, family, count, value, rule }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        let known = PlateDeck.fallback(kind)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? known.name
        emoji = (try? c.decodeIfPresent(String.self, forKey: .emoji)) ?? known.emoji
        family = (try? c.decodeIfPresent(String.self, forKey: .family)) ?? known.family
        count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        value = (try? c.decodeIfPresent(Int.self, forKey: .value)) ?? 0
        rule = (try? c.decodeIfPresent(String.self, forKey: .rule)) ?? known.rule
    }
}

/// A card on my plate: `gain` is what it would add right now (easy only).
struct PlateCard: Decodable, Equatable, Identifiable {
    let uid: Int
    let kind: String
    let gain: Int?

    var id: Int { uid }

    init(uid: Int, kind: String, gain: Int? = nil) {
        self.uid = uid; self.kind = kind; self.gain = gain
    }

    private enum CodingKeys: String, CodingKey { case uid, kind, gain }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decode(Int.self, forKey: .uid)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        gain = (try? c.decodeIfPresent(Int.self, forKey: .gain)) ?? nil
    }
}

/// A card on somebody's table, in the order taken.
struct PlatePlayed: Decodable, Equatable, Identifiable {
    let uid: Int
    let kind: String
    /// A pie a gravy jug doubled.
    let boosted: Bool
    /// A gravy jug a pie has used.
    let spent: Bool

    var id: Int { uid }

    private enum CodingKeys: String, CodingKey { case uid, kind, boosted, spent }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decode(Int.self, forKey: .uid)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        boosted = (try? c.decodeIfPresent(Bool.self, forKey: .boosted)) ?? false
        spent = (try? c.decodeIfPresent(Bool.self, forKey: .spent)) ?? false
    }
}

/// A player at the table, as Pass the Plate sees them. Name and status are the
/// shared `GamePlayer`'s.
struct PlateSeat: Decodable, Equatable, Identifiable {
    let id: String
    let seated: Bool
    let handCount: Int
    /// Has chosen this turn — never what.
    let picked: Bool
    let played: [PlatePlayed]
    let iceCream: Int
    let berries: Int
    /// Finished rounds, plus ice cream once the game is over.
    let score: Int
    /// This round's pairs, pizzas, popcorn and pies so far; nil on hard.
    let roundSoFar: Int?
    let left: Bool

    private enum CodingKeys: String, CodingKey { case id, seated, handCount, picked, played, iceCream, berries, score, roundSoFar, left }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        seated = (try? c.decodeIfPresent(Bool.self, forKey: .seated)) ?? false
        handCount = max(0, (try? c.decodeIfPresent(Int.self, forKey: .handCount)) ?? 0)
        picked = (try? c.decodeIfPresent(Bool.self, forKey: .picked)) ?? false
        played = (try? c.decodeIfPresent([PlatePlayed].self, forKey: .played)) ?? []
        iceCream = (try? c.decodeIfPresent(Int.self, forKey: .iceCream)) ?? 0
        berries = (try? c.decodeIfPresent(Int.self, forKey: .berries)) ?? 0
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        roundSoFar = (try? c.decodeIfPresent(Int.self, forKey: .roundSoFar)) ?? nil
        left = (try? c.decodeIfPresent(Bool.self, forKey: .left)) ?? false
    }
}

/// What one player took at the last reveal.
struct PlateTurnPlay: Decodable, Equatable, Identifiable {
    let playerId: String
    let cards: [PlateCard]
    /// The turn clock ran out and the server took a card for them.
    let auto: Bool

    var id: String { playerId }

    private enum CodingKeys: String, CodingKey { case playerId, cards, auto }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = (try? c.decodeIfPresent(String.self, forKey: .playerId)) ?? ""
        cards = (try? c.decodeIfPresent([PlateCard].self, forKey: .cards)) ?? []
        auto = (try? c.decodeIfPresent(Bool.self, forKey: .auto)) ?? false
    }
}

/// One player's round, scored.
struct PlateRoundRow: Decodable, Equatable, Identifiable {
    let playerId: String
    let pancakes: Int
    let pizza: Int
    let popcorn: Int
    let pies: Int
    let berryCount: Int
    let berries: Int
    let scoops: Int
    let total: Int

    var id: String { playerId }

    private enum CodingKeys: String, CodingKey { case playerId, pancakes, pizza, popcorn, pies, berryCount, berries, scoops, total }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func n(_ k: CodingKeys) -> Int { (try? c.decodeIfPresent(Int.self, forKey: k)) ?? 0 }
        playerId = (try? c.decodeIfPresent(String.self, forKey: .playerId)) ?? ""
        pancakes = n(.pancakes); pizza = n(.pizza); popcorn = n(.popcorn); pies = n(.pies)
        berryCount = n(.berryCount); berries = n(.berries); scoops = n(.scoops); total = n(.total)
    }

    /// The breakdown as the spec adds it: everything but the ice cream.
    var sum: Int { pancakes + pizza + popcorn + pies + berries }
}

struct PlateRoundResult: Decodable, Equatable, Identifiable {
    let round: Int
    let rows: [PlateRoundRow]

    var id: Int { round }

    private enum CodingKeys: String, CodingKey { case round, rows }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        round = (try? c.decodeIfPresent(Int.self, forKey: .round)) ?? 0
        rows = (try? c.decodeIfPresent([PlateRoundRow].self, forKey: .rows)) ?? []
    }
}

struct PlateDessertRow: Decodable, Equatable, Identifiable {
    let playerId: String
    let scoops: Int
    let points: Int

    var id: String { playerId }
}

struct PlateStanding: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let place: Int
    let score: Int
    let scoops: Int
    let left: Bool

    private enum CodingKeys: String, CodingKey { case id, name, place, score, scoops, left }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Player"
        place = (try? c.decodeIfPresent(Int.self, forKey: .place)) ?? 0
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        scoops = (try? c.decodeIfPresent(Int.self, forKey: .scoops)) ?? 0
        left = (try? c.decodeIfPresent(Bool.self, forKey: .left)) ?? false
    }
}

/// The room's Pass the Plate side, decoded from the same JSON as `GameRoom`.
/// Lenient throughout: a lobby from the create call carries little of it.
struct PassThePlateState: Decodable, Equatable {
    let phase: PassThePlatePhase
    let rounds: Int
    let round: Int
    let turn: Int
    let handSize: Int
    /// left | right
    let direction: String
    let passTo: String?
    let passFrom: String?
    let turnMs: Double
    let scoringMs: Double
    let hints: PassThePlateHints
    let kinds: [PlateKind]
    /// My plate — nobody else's is ever sent.
    let hand: [PlateCard]
    /// What I have chosen this turn.
    let myPick: [Int]
    let canTakeTwo: Bool
    let seats: [PlateSeat]
    let lastTurn: [PlateTurnPlay]?
    let results: [PlateRoundResult]
    let dessert: [PlateDessertRow]?
    let standings: [PlateStanding]?

    private enum CodingKeys: String, CodingKey {
        case phase, rounds, round, turn, handSize, direction, passTo, passFrom, turnMs, scoringMs, hints, kinds
        case hand, myPick, canTakeTwo, players, lastTurn, results, dessert, standings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = PassThePlatePhase.from((try? c.decodeIfPresent(String.self, forKey: .phase)) ?? nil)
        rounds = max(1, (try? c.decodeIfPresent(Int.self, forKey: .rounds)) ?? 3)
        round = (try? c.decodeIfPresent(Int.self, forKey: .round)) ?? 0
        turn = (try? c.decodeIfPresent(Int.self, forKey: .turn)) ?? 0
        handSize = (try? c.decodeIfPresent(Int.self, forKey: .handSize)) ?? 0
        direction = (try? c.decodeIfPresent(String.self, forKey: .direction)) ?? "left"
        passTo = (try? c.decodeIfPresent(String.self, forKey: .passTo)) ?? nil
        passFrom = (try? c.decodeIfPresent(String.self, forKey: .passFrom)) ?? nil
        turnMs = (try? c.decodeIfPresent(Double.self, forKey: .turnMs)) ?? 30_000
        scoringMs = (try? c.decodeIfPresent(Double.self, forKey: .scoringMs)) ?? 8_000
        hints = PassThePlateHints(rawValue: (try? c.decodeIfPresent(String.self, forKey: .hints)) ?? "") ?? PassThePlateHints.none
        kinds = (try? c.decodeIfPresent([PlateKind].self, forKey: .kinds)) ?? []
        hand = (try? c.decodeIfPresent([PlateCard].self, forKey: .hand)) ?? []
        myPick = (try? c.decodeIfPresent([Int].self, forKey: .myPick)) ?? []
        canTakeTwo = (try? c.decodeIfPresent(Bool.self, forKey: .canTakeTwo)) ?? false
        seats = (try? c.decodeIfPresent([PlateSeat].self, forKey: .players)) ?? []
        lastTurn = (try? c.decodeIfPresent([PlateTurnPlay].self, forKey: .lastTurn)) ?? nil
        results = (try? c.decodeIfPresent([PlateRoundResult].self, forKey: .results)) ?? []
        dessert = (try? c.decodeIfPresent([PlateDessertRow].self, forKey: .dessert)) ?? nil
        standings = (try? c.decodeIfPresent([PlateStanding].self, forKey: .standings)) ?? nil
    }

    func seat(_ id: String) -> PlateSeat? { seats.first { $0.id == id } }

    /// The reference card's entry for a kind, or the app's own when the room
    /// did not send one.
    func info(_ kind: String) -> PlateKind {
        kinds.first { $0.kind == kind } ?? PlateDeck.fallback(kind)
    }
}

// MARK: - The deck the app knows

enum PlateDeck {
    /// The server's `KINDS`, in its order. Pinned by a test on each side.
    static let kinds = ["pancake", "pizza", "popcorn", "berry1", "berry2", "berry3",
                        "pie2", "pie3", "pie4", "gravy", "spoon", "icecream"]

    /// The app's own copy of a card, for a room that sent no reference card.
    static func fallback(_ kind: String) -> PlateKind {
        switch kind {
        case "pancake": return PlateKind(kind: kind, name: "Pancake Stack", emoji: "🥞", family: "pair", rule: "Every two make a pair worth 6.")
        case "pizza": return PlateKind(kind: kind, name: "Pizza Slice", emoji: "🍕", family: "triple", rule: "Every three make a whole pizza worth 12.")
        case "popcorn": return PlateKind(kind: kind, name: "Popcorn", emoji: "🍿", family: "sliding", rule: "1, 3, 6, 10, 14, then 18 for six or more.")
        case "berry1": return PlateKind(kind: kind, name: "One Strawberry", emoji: "🍓", family: "majority", value: 1, rule: "Most berries 7, second 3.")
        case "berry2": return PlateKind(kind: kind, name: "Two Strawberries", emoji: "🍓", family: "majority", value: 2, rule: "Most berries 7, second 3.")
        case "berry3": return PlateKind(kind: kind, name: "Three Strawberries", emoji: "🍓", family: "majority", value: 3, rule: "Most berries 7, second 3.")
        case "pie2": return PlateKind(kind: kind, name: "Mini Pie", emoji: "🥧", family: "pie", value: 2, rule: "Worth 2.")
        case "pie3": return PlateKind(kind: kind, name: "Pie", emoji: "🥧", family: "pie", value: 3, rule: "Worth 3.")
        case "pie4": return PlateKind(kind: kind, name: "Family Pie", emoji: "🥧", family: "pie", value: 4, rule: "Worth 4.")
        case "gravy": return PlateKind(kind: kind, name: "Gravy Jug", emoji: "🫗", family: "multiplier", rule: "Your next pie is worth double.")
        case "spoon": return PlateKind(kind: kind, name: "Serving Spoon", emoji: "🥄", family: "takeTwo", rule: "Later, take two cards at once.")
        case "icecream": return PlateKind(kind: kind, name: "Ice Cream", emoji: "🍨", family: "dessert", rule: "Most scoops at the end scores 5.")
        default: return PlateKind(kind: kind, name: "A card", emoji: "🍽️", family: "", rule: "")
        }
    }
}

// MARK: - The rules the phone applies

enum PassThePlateRules {
    /// Which cards a tap leaves chosen. One at a time normally: a tap chooses
    /// that card (the same card again keeps it). With the spoon in use, up to
    /// two: a tap adds a card, or takes a chosen one back off.
    static func toggle(_ uid: Int, in chosen: [Int], takeTwo: Bool) -> [Int] {
        guard takeTwo else { return [uid] }
        if chosen.contains(uid) { return chosen.filter { $0 != uid } }
        return Array((chosen + [uid]).suffix(2))
    }

    /// Whether a choice is ready to send: one card, or two with the spoon.
    static func ready(_ chosen: [Int], takeTwo: Bool) -> Bool {
        takeTwo ? chosen.count == 2 : chosen.count == 1
    }

    /// The fraction of the turn left, 0…1 (1 when the clock is unknown).
    static func turnLeft(endsAt: Double?, turnMs: Double, now: Double?) -> Double {
        guard let endsAt, let now, turnMs > 0 else { return 1 }
        return min(1, max(0, (endsAt - now) / turnMs))
    }

    /// "+6", "+0"; nil when the room sends no gain.
    static func gainText(_ gain: Int?) -> String? {
        guard let gain else { return nil }
        return gain >= 0 ? "+\(gain)" : "\(gain)"
    }

    /// "Plates go left, to Sam." — or right; "you" never appears, a plate is
    /// always passed to somebody else.
    static func passLine(direction: String, to name: String?) -> String {
        let way = direction == "right" ? "right" : "left"
        guard let name else { return "Plates go \(way)." }
        return "Plates go \(way), to \(name)."
    }

    /// "Waiting for Sam and Kim…", or nil when nobody is left to choose.
    static func waitingLine(_ names: [String]) -> String? {
        names.isEmpty ? nil : "Waiting for \(GameNames.list(names))…"
    }

    /// One card for VoiceOver: "Pancake Stack. Adds 6 points." or with no hint just the name.
    static func spoken(_ info: PlateKind, gain: Int?, chosen: Bool) -> String {
        var parts = [info.name]
        if let gain { parts.append(gain == 1 ? "Adds 1 point" : "Adds \(gain) points") }
        if chosen { parts.append("Chosen") }
        return parts.joined(separator: ". ")
    }

    /// The round's breakdown as a line: "Pancakes 6 · Pizza 12 · Berries 7".
    static func breakdownLine(_ row: PlateRoundRow) -> String {
        let bits: [(String, Int)] = [("Pancakes", row.pancakes), ("Pizza", row.pizza), ("Popcorn", row.popcorn),
                                     ("Pies", row.pies), ("Berries", row.berries)]
        let shown = bits.filter { $0.1 != 0 }.map { "\($0.0) \($0.1)" }
        return shown.isEmpty ? "Nothing scored" : shown.joined(separator: " · ")
    }
}

// MARK: - The table the host picks

/// The invite line for the lobby, the same words the server's `about` uses.
enum PassThePlateSettings {
    static func about(difficulty: String) -> String {
        switch difficulty {
        case "easy": return "Three rounds · simple deck · hints on"
        case "medium": return "Three rounds · full deck"
        default: return "Three rounds · full deck · no hints"
        }
    }
}
