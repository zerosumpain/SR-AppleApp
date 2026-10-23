import Foundation

// Fireworks' wire pieces and the little the phone works out itself — which
// cards a hint would point at, which hints are possible, what a card is known
// to be, the log in sentences — as pure values, so each is a unit test. The
// server deals, judges every move and keeps the deck; nothing here decides
// whether a play lands.
//
// HIDDEN INFORMATION lives on the server: my own cards arrive with `colour`
// and `rank` null and only what hints said (`knows`). The phone never has my
// cards to leak.
//
// The room's Fireworks side is decoded whole into `FireworksState`, read off
// the same JSON as `GameRoom` (`GameRoom.fireworks`).

/// Where a Fireworks room is. `playing` is in the shared `GamePhase` too.
enum FireworksPhase: String, Equatable {
    case lobby, countdown, playing, finished, closed, unknown

    static func from(_ raw: String?) -> FireworksPhase {
        guard let raw else { return .unknown }
        return FireworksPhase(rawValue: raw) ?? .unknown
    }
}

/// What the hints say a card can be: the colours and numbers still possible.
struct FireworksKnowledge: Decodable, Equatable {
    let colours: [String]
    let ranks: [Int]
    /// A hint has pointed at it.
    let hinted: Bool

    init(colours: [String], ranks: [Int], hinted: Bool) {
        self.colours = colours
        self.ranks = ranks
        self.hinted = hinted
    }

    private enum CodingKeys: String, CodingKey { case colours, ranks, hinted }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colours = (try? c.decodeIfPresent([String].self, forKey: .colours)) ?? []
        ranks = (try? c.decodeIfPresent([Int].self, forKey: .ranks)) ?? []
        hinted = (try? c.decodeIfPresent(Bool.self, forKey: .hinted)) ?? false
    }

    /// The one colour it must be, if the hints have narrowed it that far.
    var colour: String? { colours.count == 1 ? colours[0] : nil }
    /// The one number it must be.
    var rank: Int? { ranks.count == 1 ? ranks[0] : nil }
}

/// One card in a hand (or on the discards). `colour` and `rank` are nil for
/// my own cards until the show is over.
struct FireworksCard: Decodable, Equatable, Identifiable {
    let id: Int
    let colour: String?
    let rank: Int?
    let knows: FireworksKnowledge?
    /// Easy only, my own cards: `knows` narrowed by the copies I can see.
    let could: FireworksKnowledge?

    init(id: Int, colour: String?, rank: Int?, knows: FireworksKnowledge? = nil, could: FireworksKnowledge? = nil) {
        self.id = id
        self.colour = colour
        self.rank = rank
        self.knows = knows
        self.could = could
    }

    private enum CodingKeys: String, CodingKey { case id, colour, rank, knows, could }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        colour = (try? c.decodeIfPresent(String.self, forKey: .colour)) ?? nil
        rank = ((try? c.decodeIfPresent(Int.self, forKey: .rank)) ?? nil).map { min(5, max(1, $0)) }
        knows = (try? c.decodeIfPresent(FireworksKnowledge.self, forKey: .knows)) ?? nil
        could = (try? c.decodeIfPresent(FireworksKnowledge.self, forKey: .could)) ?? nil
    }

    /// Face up: I can see what it is.
    var visible: Bool { colour != nil && rank != nil }
}

/// A player at the table, as Fireworks sees them.
struct FireworksSeat: Decodable, Equatable, Identifiable {
    let id: String
    let seated: Bool
    /// Oldest first.
    let hand: [FireworksCard]

    private enum CodingKeys: String, CodingKey { case id, seated, hand }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        seated = (try? c.decodeIfPresent(Bool.self, forKey: .seated)) ?? false
        hand = (try? c.decodeIfPresent([FireworksCard].self, forKey: .hand)) ?? []
    }
}

/// One thing that happened: a hint, a play or a drop.
struct FireworksLogEntry: Decodable, Equatable {
    enum Kind: String { case hint, play, discard, unknown }

    let kind: Kind
    let by: String
    /// A hint's player.
    let to: String?
    /// A hint's colour or number.
    let colour: String?
    let rank: Int?
    /// The ids a hint pointed at.
    let cards: [Int]
    /// A play landed on its firework.
    let ok: Bool?
    /// The turn clock ran out and the server dropped a card.
    let auto: Bool
    /// The card played or dropped, face up.
    let card: FireworksCard?

    private enum CodingKeys: String, CodingKey { case kind, by, to, colour, rank, cards, ok, auto, card }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = Kind(rawValue: (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "") ?? .unknown
        by = (try? c.decodeIfPresent(String.self, forKey: .by)) ?? ""
        to = (try? c.decodeIfPresent(String.self, forKey: .to)) ?? nil
        colour = (try? c.decodeIfPresent(String.self, forKey: .colour)) ?? nil
        rank = (try? c.decodeIfPresent(Int.self, forKey: .rank)) ?? nil
        cards = (try? c.decodeIfPresent([Int].self, forKey: .cards)) ?? []
        ok = (try? c.decodeIfPresent(Bool.self, forKey: .ok)) ?? nil
        auto = (try? c.decodeIfPresent(Bool.self, forKey: .auto)) ?? false
        card = (try? c.decodeIfPresent(FireworksCard.self, forKey: .card)) ?? nil
    }
}

/// A row of the final table: everyone shares the team's score.
struct FireworksStanding: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let score: Int
    let maxScore: Int
    let left: Bool

    private enum CodingKeys: String, CodingKey { case id, name, score, maxScore, left }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Player"
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        maxScore = (try? c.decodeIfPresent(Int.self, forKey: .maxScore)) ?? 25
        left = (try? c.decodeIfPresent(Bool.self, forKey: .left)) ?? false
    }
}

/// The room's Fireworks side, decoded from the same JSON as `GameRoom`.
/// Lenient throughout: a lobby from the create call carries little of it.
struct FireworksState: Decodable, Equatable {
    let phase: FireworksPhase
    let rule: String?
    /// The suits in play, prism last on hard.
    let colours: [String]
    /// The five a hint may name.
    let hintColours: [String]
    let turnMs: Double
    let turnId: String?
    let turn: Int
    let hints: Int
    let maxHints: Int
    let misfires: Int
    let maxMisfires: Int
    /// Cards left to draw (a count: the deck itself never leaves the server).
    let deck: Int
    /// Turns left once the last card is drawn; nil while the deck lasts.
    let finalTurns: Int?
    /// Each firework's top number, 0 for none yet.
    let stacks: [String: Int]
    let score: Int
    let maxScore: Int
    let discards: [FireworksCard]
    let log: [FireworksLogEntry]
    let seats: [FireworksSeat]
    /// perfect | misfires | deck | left, once finished.
    let ending: String?
    let standings: [FireworksStanding]?

    private enum CodingKeys: String, CodingKey {
        case phase, rule, colours, hintColours, turnMs, turnId, turn, hints, maxHints, misfires, maxMisfires
        case deck, finalTurns, stacks, score, maxScore, discards, log, players, ending, standings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = FireworksPhase.from((try? c.decodeIfPresent(String.self, forKey: .phase)) ?? nil)
        rule = (try? c.decodeIfPresent(String.self, forKey: .rule)) ?? nil
        hintColours = (try? c.decodeIfPresent([String].self, forKey: .hintColours)) ?? FireworksRules.baseColours
        colours = (try? c.decodeIfPresent([String].self, forKey: .colours)) ?? hintColours
        turnMs = (try? c.decodeIfPresent(Double.self, forKey: .turnMs)) ?? 75_000
        turnId = (try? c.decodeIfPresent(String.self, forKey: .turnId)) ?? nil
        turn = (try? c.decodeIfPresent(Int.self, forKey: .turn)) ?? 0
        hints = (try? c.decodeIfPresent(Int.self, forKey: .hints)) ?? 8
        maxHints = (try? c.decodeIfPresent(Int.self, forKey: .maxHints)) ?? 8
        misfires = (try? c.decodeIfPresent(Int.self, forKey: .misfires)) ?? 0
        maxMisfires = max(1, (try? c.decodeIfPresent(Int.self, forKey: .maxMisfires)) ?? 3)
        deck = (try? c.decodeIfPresent(Int.self, forKey: .deck)) ?? 0
        finalTurns = (try? c.decodeIfPresent(Int.self, forKey: .finalTurns)) ?? nil
        stacks = (try? c.decodeIfPresent([String: Int].self, forKey: .stacks)) ?? [:]
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        maxScore = (try? c.decodeIfPresent(Int.self, forKey: .maxScore)) ?? 25
        discards = (try? c.decodeIfPresent([FireworksCard].self, forKey: .discards)) ?? []
        log = (try? c.decodeIfPresent([FireworksLogEntry].self, forKey: .log)) ?? []
        seats = (try? c.decodeIfPresent([FireworksSeat].self, forKey: .players)) ?? []
        ending = (try? c.decodeIfPresent(String.self, forKey: .ending)) ?? nil
        standings = (try? c.decodeIfPresent([FireworksStanding].self, forKey: .standings)) ?? nil
    }

    func seat(_ id: String) -> FireworksSeat? { seats.first { $0.id == id } }

    /// The firework's top number for a colour.
    func top(_ colour: String) -> Int { stacks[colour] ?? 0 }
}

// MARK: - The rules the phone applies

/// A hint being put together: a colour or a number, for one player.
enum FireworksHint: Equatable, Hashable {
    case colour(String)
    case rank(Int)

    var spoken: String {
        switch self {
        case .colour(let c): return FireworksRules.colourName(c)
        case .rank(let r): return "\(r)"
        }
    }
}

enum FireworksRules {
    static let baseColours = ["red", "yellow", "green", "blue", "white"]
    static let prism = "prism"
    static let ranks = [1, 2, 3, 4, 5]

    static func colourName(_ colour: String) -> String {
        colour == prism ? "Prism" : colour.capitalized
    }

    /// Whether a hint points at a card I can see. A colour hint points at its
    /// own colour and at every prism card.
    static func touches(_ hint: FireworksHint, _ card: FireworksCard) -> Bool {
        guard let colour = card.colour, let rank = card.rank else { return false }
        switch hint {
        case .colour(let c): return colour == c || colour == prism
        case .rank(let r): return rank == r
        }
    }

    /// The ids in a hand that a hint would point at.
    static func touched(_ hint: FireworksHint, in hand: [FireworksCard]) -> [Int] {
        hand.filter { touches(hint, $0) }.map(\.id)
    }

    /// Every hint that would point at something in this hand: colours first
    /// (in the order hints may name them), then numbers.
    static func possibleHints(for hand: [FireworksCard], colours: [String] = baseColours) -> [FireworksHint] {
        let byColour = colours.map(FireworksHint.colour).filter { !touched($0, in: hand).isEmpty }
        let byRank = ranks.map(FireworksHint.rank).filter { !touched($0, in: hand).isEmpty }
        return byColour + byRank
    }

    /// Whether this card would land if played now.
    static func playable(_ card: FireworksCard, stacks: [String: Int]) -> Bool {
        guard let colour = card.colour, let rank = card.rank else { return false }
        return (stacks[colour] ?? 0) == rank - 1
    }

    /// What I know of one of my cards, in a few words: "Red 3", "Red or prism",
    /// "A 4", "Not 1 or 5", "Nothing yet".
    static func knownText(_ knows: FireworksKnowledge?, allColours: [String]) -> String {
        guard let knows else { return "Nothing yet" }
        let colour: String?
        if let c = knows.colour {
            colour = colourName(c)
        } else if knows.colours.count > 1, knows.colours.count < allColours.count {
            colour = knows.colours.count <= 2
                ? knows.colours.map(colourName).joined(separator: " or ")
                : nil
        } else {
            colour = nil
        }
        let rank = knows.rank
        switch (colour, rank) {
        case let (c?, r?): return "\(c) \(r)"
        case let (c?, nil): return c
        case let (nil, r?): return "A \(r)"
        default:
            let ruledOut = ranks.filter { !knows.ranks.contains($0) }
            if !ruledOut.isEmpty, ruledOut.count < ranks.count {
                return "Not " + GameNames.list(ruledOut.map(String.init)).replacingOccurrences(of: " and ", with: " or ")
            }
            let ruledColours = allColours.filter { !knows.colours.contains($0) }
            if !ruledColours.isEmpty, ruledColours.count < allColours.count {
                return "Not " + ruledColours.map { colourName($0).lowercased() }.joined(separator: ", ")
            }
            return "Nothing yet"
        }
    }

    /// Easy's "could be" line: "Could be: red, blue · 1, 2".
    static func couldText(_ could: FireworksKnowledge?) -> String? {
        guard let could, !could.colours.isEmpty || !could.ranks.isEmpty else { return nil }
        let colours = could.colours.map { colourName($0).lowercased() }.joined(separator: ", ")
        let ranks = could.ranks.map(String.init).joined(separator: ", ")
        return "Could be \(colours) · \(ranks)"
    }

    /// "Red 3".
    static func cardText(_ card: FireworksCard) -> String {
        guard let colour = card.colour, let rank = card.rank else { return "A hidden card" }
        return "\(colourName(colour)) \(rank)"
    }

    /// One log line. Names come from `name` (`You` for me).
    static func logLine(_ entry: FireworksLogEntry, name: (String) -> String) -> String {
        let who = name(entry.by)
        switch entry.kind {
        case .hint:
            let target = entry.to.map(name) ?? "someone"
            let count = entry.cards.count
            let what: String
            if let colour = entry.colour {
                what = count == 1 ? "a \(colourName(colour).lowercased()) card" : "\(count) \(colourName(colour).lowercased()) cards"
            } else {
                let r = entry.rank ?? 0
                what = count == 1 ? "a \(r)" : "\(count) × \(r)"
            }
            let possessive = target == "You" ? "your" : "\(target)’s"
            return "\(who) pointed at \(what) in \(possessive) hand."
        case .play:
            let card = entry.card.map(cardText) ?? "a card"
            return entry.ok == true ? "\(who) played the \(card). Bang!" : "\(who) played the \(card) — a misfire."
        case .discard:
            let card = entry.card.map(cardText) ?? "a card"
            return entry.auto ? "\(who) ran out of time: the \(card) was dropped." : "\(who) dropped the \(card)."
        case .unknown:
            return "\(who) moved."
        }
    }

    /// How the show ended, in a sentence.
    static func endingLine(_ state: FireworksState) -> String {
        let of = "\(state.score) of \(state.maxScore)"
        switch state.ending {
        case "perfect": return "A perfect show: every firework went up. \(of)."
        case "misfires": return "Too many misfires — the show stopped at \(of)."
        case "deck": return "The last card was played out. The team scored \(of)."
        case "left": return "Not enough players left to carry on. The team scored \(of)."
        default: return "The team scored \(of)."
        }
    }

    // The new-game sheet: Fireworks is a team game for two to five, so it is
    // never offered as a solo game (the server refuses to start one).
    static let minPlayers = 2
    static let maxPlayers = 5
    static let sheetTrailing = "2 to 5"
    static let sheetNobody = "Nobody else in the family can play yet, and Fireworks needs two to five. The lobby can wait for somebody to pair a phone."
    static let sheetPick = "Fireworks needs two to five: ask at least one person. Nothing starts yet: the lobby waits for people to join. Invites reach phones with the app open."

    /// Leaving mid-show, for the confirm: what happens to the team, given how
    /// many others are still at the table (the server ends a table of one).
    static func leaveWarning(staying: Int) -> String {
        staying < minPlayers
            ? "Your cards go on the discards, and with only one player left the show ends here."
            : "Your cards go on the discards and the rest of the team plays on without you."
    }

    /// A row of the team's result: no place, everyone shares it.
    static func teamDetail(left: Bool) -> String {
        left ? "Left early" : "Played to the end"
    }

    /// A word for how good the score was, out of the maximum.
    static func verdict(score: Int, max: Int) -> String {
        guard max > 0 else { return "" }
        let f = Double(score) / Double(max)
        switch f {
        case 1: return "Legendary"
        case 0.84...: return "Dazzling"
        case 0.64...: return "Brilliant"
        case 0.44...: return "Good show"
        case 0.24...: return "A few sparks"
        default: return "Damp squib"
        }
    }

    /// The fraction of the turn left, 0…1 (1 when the clock is unknown).
    static func turnLeft(endsAt: Double?, turnMs: Double, now: Double?) -> Double {
        guard let endsAt, let now, turnMs > 0 else { return 1 }
        return min(1, max(0, (endsAt - now) / turnMs))
    }
}

/// Which of the screen's pages a room is on: Fireworks' own phase when the
/// room carries it, else the shared phase.
enum FireworksScreenPhase {
    static func of(_ room: GameRoom) -> FireworksPhase {
        if let phase = room.fireworks?.phase, phase != .unknown { return phase }
        switch room.phase {
        case .lobby: return .lobby
        case .countdown: return .countdown
        case .playing: return .playing
        case .finished: return .finished
        case .closed: return .closed
        default: return .unknown
        }
    }
}
