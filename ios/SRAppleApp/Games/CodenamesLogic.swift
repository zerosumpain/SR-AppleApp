import Foundation

// Codenames' wire pieces and the little the phone works out itself — which
// page a room is on, what colour a card shows this phone, who the table is
// waiting on, the clue check a spymaster gets before sending, and the
// sentences for a turn and an ending — as pure values, so each is a unit
// test. The server deals the key, judges every clue and every touch and
// ends the game; nothing here decides any of that.
//
// The wire is SR-Main's `toWire` in `src/lib/games/codenames.ts` (spec
// docs/superpowers/specs/2026-11-01-family-games-tv-quiz-codenames.md). The
// key is the whole secret: a phone gets `key` only while its player is a
// spymaster (and everybody once the game is over). A face-down card's
// `kind` is null to everyone else, the TV board included — so the operative
// screen cannot show a colour it was never sent.
//
// `clueProblem` is a port of the server's, run before a clue is sent so the
// obvious refusals ("That is a word on the board.") come back at once. The
// server runs the same check again and stays the judge.
//
// Foundation only, so it runs in `scripts/home-check.sh` on Linux. The room's
// Codenames side is decoded whole into `CodenamesState`, read off the same
// JSON as `GameRoom` (`GameRoom.codenames`).

/// Where a Codenames room is. Its own enum: `clue` and `guess` are not
/// shared `GamePhase`s.
enum CodenamesPhase: String, Equatable {
    case lobby, countdown, clue, guess, finished, closed, unknown

    static func from(_ raw: String?) -> CodenamesPhase {
        guard let raw else { return .unknown }
        return CodenamesPhase(rawValue: raw) ?? .unknown
    }

    /// A turn is being played: a clue being thought of, or cards being touched.
    var inPlay: Bool { self == .clue || self == .guess }
}

/// The two teams. Co-op is everybody on red, against blue's own turns.
enum CodenamesTeam: String, CaseIterable, Identifiable, Equatable {
    case red, blue

    var id: String { rawValue }

    static func from(_ raw: String?) -> CodenamesTeam? {
        guard let raw else { return nil }
        return CodenamesTeam(rawValue: raw)
    }

    var other: CodenamesTeam { self == .red ? .blue : .red }

    var label: String { self == .red ? "Red" : "Blue" }
}

/// What a card is under its word: a team's agent, a bystander, or the assassin.
enum CodenamesKind: String, Equatable {
    case red, blue, neutral, assassin

    static func from(_ raw: String?) -> CodenamesKind? {
        guard let raw else { return nil }
        return CodenamesKind(rawValue: raw)
    }

    var team: CodenamesTeam? {
        switch self {
        case .red: return .red
        case .blue: return .blue
        case .neutral, .assassin: return nil
        }
    }

    /// "a red agent", "a bystander", "the assassin".
    var spoken: String {
        switch self {
        case .red: return "a red agent"
        case .blue: return "a blue agent"
        case .neutral: return "a bystander"
        case .assassin: return "the assassin"
        }
    }

    /// A mark printed on every coloured card, so nobody needs to tell red
    /// from blue by colour alone.
    var glyph: String {
        switch self {
        case .red: return "diamond.fill"
        case .blue: return "circle.fill"
        case .neutral: return "minus"
        case .assassin: return "xmark.octagon.fill"
        }
    }
}

/// Two teams of spymaster and operatives (four or more), or co-op (two or three).
enum CodenamesMode: String, Equatable {
    case teams, coop

    static func from(_ raw: String?) -> CodenamesMode { raw == "coop" ? .coop : .teams }
}

/// One of the 25 cards. `kind` only once it is turned over.
struct CodenamesCard: Decodable, Equatable, Identifiable {
    let i: Int
    let word: String
    /// Nil while face down.
    let kind: CodenamesKind?
    /// Who turned it: a player id, or `auto` (co-op's own turn). Nil while face down.
    let by: String?
    /// Which turn turned it.
    let turn: Int?

    var id: Int { i }
    var faceDown: Bool { by == nil }

    init(i: Int, word: String, kind: CodenamesKind? = nil, by: String? = nil, turn: Int? = nil) {
        self.i = i; self.word = word; self.kind = kind; self.by = by; self.turn = turn
    }

    private enum CodingKeys: String, CodingKey { case i, word, kind, by, turn }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        i = try c.decode(Int.self, forKey: .i)
        word = (try? c.decodeIfPresent(String.self, forKey: .word)) ?? ""
        kind = CodenamesKind.from((try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil)
        by = (try? c.decodeIfPresent(String.self, forKey: .by)) ?? nil
        turn = (try? c.decodeIfPresent(Int.self, forKey: .turn)) ?? nil
    }
}

/// A clue: this turn's (with the guesses left) or one from the history.
struct CodenamesClue: Decodable, Equatable, Identifiable {
    let team: CodenamesTeam
    let by: String
    /// Upper case, as the server keeps it.
    let word: String
    let count: Int
    /// The cards turned over on it, in order.
    let cards: [Int]
    let at: Double
    /// This turn's clue only: touches left (the number plus one, less those made).
    let guessesLeft: Int?

    var id: String { "\(Int64(at))-\(word)" }

    private enum CodingKeys: String, CodingKey { case team, by, word, count, cards, at, guessesLeft }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        team = CodenamesTeam.from((try? c.decodeIfPresent(String.self, forKey: .team)) ?? nil) ?? .red
        by = (try? c.decodeIfPresent(String.self, forKey: .by)) ?? ""
        word = ((try? c.decodeIfPresent(String.self, forKey: .word)) ?? nil)?.uppercased() ?? ""
        count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 1
        cards = (try? c.decodeIfPresent([Int].self, forKey: .cards)) ?? []
        at = (try? c.decodeIfPresent(Double.self, forKey: .at)) ?? 0
        guessesLeft = (try? c.decodeIfPresent(Int.self, forKey: .guessesLeft)) ?? nil
    }
}

/// A team's side of the table: agents in all, still face down, and its spymaster.
struct CodenamesSide: Decodable, Equatable, Identifiable {
    let team: CodenamesTeam
    let agents: Int
    let left: Int
    /// Nil before the deal, and always for co-op's blue.
    let spymasterId: String?

    var id: String { team.rawValue }
    var found: Int { max(0, agents - left) }

    private enum CodingKeys: String, CodingKey { case team, agents, left, spymasterId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        team = CodenamesTeam.from((try? c.decodeIfPresent(String.self, forKey: .team)) ?? nil) ?? .red
        agents = (try? c.decodeIfPresent(Int.self, forKey: .agents)) ?? 0
        left = (try? c.decodeIfPresent(Int.self, forKey: .left)) ?? 0
        spymasterId = (try? c.decodeIfPresent(String.self, forKey: .spymasterId)) ?? nil
    }
}

/// The last card turned, for the grid's highlight and the haptic.
struct CodenamesLast: Decodable, Equatable {
    let card: Int
    let kind: CodenamesKind
    /// The team whose turn turned it.
    let team: CodenamesTeam
    /// A player id, or `auto`.
    let by: String
    let at: Double

    var auto: Bool { by == CodenamesRules.auto }

    private enum CodingKeys: String, CodingKey { case card, kind, team, by, at }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        card = try c.decode(Int.self, forKey: .card)
        kind = CodenamesKind.from((try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil) ?? .neutral
        team = CodenamesTeam.from((try? c.decodeIfPresent(String.self, forKey: .team)) ?? nil) ?? .red
        by = (try? c.decodeIfPresent(String.self, forKey: .by)) ?? ""
        at = (try? c.decodeIfPresent(Double.self, forKey: .at)) ?? 0
    }
}

/// A player's Codenames side (`players[]` on the wire).
struct CodenamesSeat: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    /// invited | joined | declined | left
    let status: String
    let isHost: Bool
    /// The lobby's pick (nil = anywhere), fixed at the start.
    let team: CodenamesTeam?
    /// Asked to give the clues (lobby), or does (in play).
    let spymaster: Bool

    var joined: Bool { status == "joined" }

    private enum CodingKeys: String, CodingKey { case id, name, status, isHost, team, spymaster }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Player"
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "joined"
        isHost = (try? c.decodeIfPresent(Bool.self, forKey: .isHost)) ?? false
        team = CodenamesTeam.from((try? c.decodeIfPresent(String.self, forKey: .team)) ?? nil)
        spymaster = (try? c.decodeIfPresent(Bool.self, forKey: .spymaster)) ?? false
    }
}

/// How the game ended. `winner` nil: co-op lost.
struct CodenamesResult: Decodable, Equatable {
    let winner: CodenamesTeam?
    /// agents | assassin | left
    let reason: String

    private enum CodingKeys: String, CodingKey { case winner, reason }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        winner = CodenamesTeam.from((try? c.decodeIfPresent(String.self, forKey: .winner)) ?? nil)
        reason = (try? c.decodeIfPresent(String.self, forKey: .reason)) ?? "agents"
    }
}

/// A row of the final table: place 1 for the winning team, 2 otherwise, and
/// the agents the player's team found.
struct CodenamesStanding: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let team: CodenamesTeam?
    let spymaster: Bool
    let score: Int
    let place: Int
    /// won | lost | left
    let result: String

    private enum CodingKeys: String, CodingKey { case id, name, team, spymaster, score, place, result }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Player"
        team = CodenamesTeam.from((try? c.decodeIfPresent(String.self, forKey: .team)) ?? nil)
        spymaster = (try? c.decodeIfPresent(Bool.self, forKey: .spymaster)) ?? false
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        place = (try? c.decodeIfPresent(Int.self, forKey: .place)) ?? 2
        result = (try? c.decodeIfPresent(String.self, forKey: .result)) ?? "lost"
    }
}

/// The room's Codenames side, decoded from the same JSON as `GameRoom`.
/// Lenient throughout: a lobby from the create call carries little of it.
struct CodenamesState: Decodable, Equatable {
    let phase: CodenamesPhase
    let meId: String
    let hostId: String
    /// In the lobby, what the joined count would play.
    let mode: CodenamesMode
    let clueMs: Double
    let guessMs: Double
    let startedAt: Double?
    let phaseEndsAt: Double?
    let starting: CodenamesTeam
    let turnTeam: CodenamesTeam
    let turns: Int
    let cards: [CodenamesCard]
    /// Every card's kind, for a spymaster (and everyone once finished). Nil otherwise.
    let key: [CodenamesKind]?
    let clue: CodenamesClue?
    let clues: [CodenamesClue]
    /// Red then blue.
    let teams: [CodenamesSide]
    let last: CodenamesLast?
    let canGuess: Bool
    let canClue: Bool
    let seats: [CodenamesSeat]
    let result: CodenamesResult?
    let standings: [CodenamesStanding]?
    let winnerIds: [String]

    private enum CodingKeys: String, CodingKey {
        case phase, meId, hostId, mode, clueMs, guessMs, startedAt, phaseEndsAt, starting, turnTeam, turns
        case cards, key, clue, clues, teams, last, canGuess, canClue, players, result, standings, winnerIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = CodenamesPhase.from((try? c.decodeIfPresent(String.self, forKey: .phase)) ?? nil)
        meId = (try? c.decodeIfPresent(String.self, forKey: .meId)) ?? ""
        hostId = (try? c.decodeIfPresent(String.self, forKey: .hostId)) ?? ""
        mode = CodenamesMode.from((try? c.decodeIfPresent(String.self, forKey: .mode)) ?? nil)
        clueMs = (try? c.decodeIfPresent(Double.self, forKey: .clueMs)) ?? 150_000
        guessMs = (try? c.decodeIfPresent(Double.self, forKey: .guessMs)) ?? 150_000
        startedAt = (try? c.decodeIfPresent(Double.self, forKey: .startedAt)) ?? nil
        phaseEndsAt = (try? c.decodeIfPresent(Double.self, forKey: .phaseEndsAt)) ?? nil
        starting = CodenamesTeam.from((try? c.decodeIfPresent(String.self, forKey: .starting)) ?? nil) ?? .red
        turnTeam = CodenamesTeam.from((try? c.decodeIfPresent(String.self, forKey: .turnTeam)) ?? nil) ?? .red
        turns = (try? c.decodeIfPresent(Int.self, forKey: .turns)) ?? 0
        cards = ((try? c.decodeIfPresent([CodenamesCard].self, forKey: .cards)) ?? []).sorted { $0.i < $1.i }
        // A key that is not one kind a card is no key at all.
        let rawKey = (try? c.decodeIfPresent([String].self, forKey: .key)) ?? nil
        let kinds = rawKey?.compactMap { CodenamesKind(rawValue: $0) }
        key = kinds.flatMap { $0.count == rawKey?.count && !$0.isEmpty ? $0 : nil }
        clue = (try? c.decodeIfPresent(CodenamesClue.self, forKey: .clue)) ?? nil
        clues = (try? c.decodeIfPresent([CodenamesClue].self, forKey: .clues)) ?? []
        teams = (try? c.decodeIfPresent([CodenamesSide].self, forKey: .teams)) ?? []
        last = (try? c.decodeIfPresent(CodenamesLast.self, forKey: .last)) ?? nil
        canGuess = (try? c.decodeIfPresent(Bool.self, forKey: .canGuess)) ?? false
        canClue = (try? c.decodeIfPresent(Bool.self, forKey: .canClue)) ?? false
        seats = (try? c.decodeIfPresent([CodenamesSeat].self, forKey: .players)) ?? []
        result = (try? c.decodeIfPresent(CodenamesResult.self, forKey: .result)) ?? nil
        standings = (try? c.decodeIfPresent([CodenamesStanding].self, forKey: .standings)) ?? nil
        winnerIds = (try? c.decodeIfPresent([String].self, forKey: .winnerIds)) ?? []
    }

    func seat(_ id: String) -> CodenamesSeat? { seats.first { $0.id == id } }

    var mySeat: CodenamesSeat? { seat(meId) }

    /// My team, once I have one (picked in the lobby, or dealt).
    var myTeam: CodenamesTeam? { mySeat?.team }

    /// This phone holds the key: I am a spymaster in play (or the game is over).
    var seesKey: Bool { key != nil }

    /// I give my team's clues.
    var amSpymaster: Bool { mySeat?.joined == true && mySeat?.spymaster == true && phase != .lobby }

    func side(_ team: CodenamesTeam) -> CodenamesSide? { teams.first { $0.team == team } }

    /// The kind this phone may show for a card: its own once turned, else the
    /// key's when this phone holds it, else nothing.
    func shownKind(_ i: Int) -> CodenamesKind? {
        if let card = cards.first(where: { $0.i == i }), let kind = card.kind { return kind }
        guard let key, key.indices.contains(i) else { return nil }
        return key[i]
    }

    /// The words still face down — what a clue may not be.
    var faceDownWords: [String] { cards.filter(\.faceDown).map(\.word) }

    /// A team's players still in, spymaster first.
    func members(_ team: CodenamesTeam) -> [CodenamesSeat] {
        let mine = seats.filter { $0.joined && $0.team == team }
        return mine.filter(\.spymaster) + mine.filter { !$0.spymaster }
    }

    /// The team's spymaster, as the table has it.
    func spymaster(_ team: CodenamesTeam) -> CodenamesSeat? {
        if let id = side(team)?.spymasterId { return seat(id) }
        return seats.first { $0.joined && $0.team == team && $0.spymaster }
    }

    /// Joined players who have not picked a side yet (lobby).
    var anywhere: [CodenamesSeat] { seats.filter { $0.joined && $0.team == nil } }

    func standing(_ id: String) -> CodenamesStanding? { standings?.first { $0.id == id } }

    /// The cards turned on this turn's clue, newest last.
    var touched: [Int] { clue?.cards ?? [] }

    /// The guesses left on this turn's clue.
    var guessesLeft: Int {
        guard let clue else { return 0 }
        return clue.guessesLeft ?? max(0, clue.count + 1 - clue.cards.count)
    }

    /// End turn is allowed once a card is turned on this clue.
    var canPass: Bool { canGuess && !touched.isEmpty }
}

// MARK: - Request bodies

/// `POST /api/native/games/<id>` for a Codenames move. Its own body (not
/// `GameActionBody`): `team` is one colour or null here, where Secret
/// Mission's `team` is a list of player ids.
struct CodenamesMove: Encodable, Equatable {
    let action: String
    var team: CodenamesTeam? = nil
    var spymaster: Bool? = nil
    var word: String? = nil
    var count: Int? = nil
    var card: Int? = nil

    private enum CodingKeys: String, CodingKey { case action, team, spymaster, word, count, card }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(action, forKey: .action)
        if action == "team" {
            // Anywhere is an explicit null, as the spec writes it.
            if let team { try c.encode(team.rawValue, forKey: .team) } else { try c.encodeNil(forKey: .team) }
            try c.encode(spymaster ?? false, forKey: .spymaster)
        }
        try c.encodeIfPresent(word, forKey: .word)
        try c.encodeIfPresent(count, forKey: .count)
        try c.encodeIfPresent(card, forKey: .card)
    }

    /// The lobby's pick: a team (nil = anywhere) and whether I'd give the clues.
    static func pick(_ team: CodenamesTeam?, spymaster: Bool) -> CodenamesMove {
        CodenamesMove(action: "team", team: team, spymaster: spymaster)
    }

    static func clue(_ word: String, count: Int) -> CodenamesMove {
        CodenamesMove(action: "clue", word: word, count: count)
    }

    static func guess(_ card: Int) -> CodenamesMove {
        CodenamesMove(action: "guess", card: card)
    }

    static let pass = CodenamesMove(action: "pass")
}

// MARK: - The rules the phone applies

enum CodenamesRules {
    static let minPlayers = 2
    static let maxPlayers = 8
    /// Fewest for two teams; under this the table plays co-op.
    static let teamsMin = 4
    static let cards = 25
    static let maxClue = 24
    static let maxCount = 9
    /// Who turns co-op's blue agents over.
    static let auto = "auto"

    static let sheetTrailing = "2 to 8"
    static let sheetNobody = "Nobody else in the family can play yet, and Codenames needs two to eight. The lobby can wait for somebody to pair a phone."
    static let sheetPick = "Codenames is for two to eight: invite at least one. Four or more play as two teams, two or three play together against the clock. Best with the grid on the TV."

    /// The lobby's preview of what the table will play.
    static func modeLine(_ mode: CodenamesMode) -> String {
        switch mode {
        case .teams: return "Two teams, red and blue, each with a spymaster giving one-word clues."
        case .coop: return "Co-op: you're all on red with one spymaster, and a blue agent turns itself over after every turn."
        }
    }

    /// "Two teams" / "Co-op", for the lobby's kicker.
    static func modeLabel(_ mode: CodenamesMode) -> String { mode == .teams ? "Two teams" : "Co-op" }

    /// The cue under the mode, while it could still change: who would tip it.
    static func modeHint(_ mode: CodenamesMode, joined: Int) -> String? {
        switch mode {
        case .coop:
            let short = max(0, teamsMin - joined)
            return short == 0 ? nil : (short == 1 ? "One more player and it's two teams." : "\(short) more players and it's two teams.")
        case .teams:
            return nil
        }
    }

    // MARK: The clue check (a port of SR-Main's `clueProblem`)

    /// Lower case, accents off, apostrophes dropped, anything but letters and
    /// digits a space, spaces single, a leading article dropped from a phrase
    /// — as the server's `normalise` (One Clue's) reads a word.
    static func normalise(_ text: String) -> String {
        let decomposed = text.decomposedStringWithCompatibilityMapping
        var plain = ""
        for scalar in decomposed.unicodeScalars where !(0x300...0x36F).contains(scalar.value) {
            plain.unicodeScalars.append(scalar)
        }
        let lowered = plain.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        var words: [String] = []
        var current = ""
        for scalar in lowered.unicodeScalars {
            let v = scalar.value
            if (97...122).contains(v) || (48...57).contains(v) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        if words.count > 1, ["a", "an", "the"].contains(words[0]) { words.removeFirst() }
        return words.joined(separator: " ")
    }

    /// The word and what it may be without a plural ending: kites → kite;
    /// boxes → box (or boxe); berries → berry (or berrie).
    static func singulars(_ w: String) -> [String] {
        if w.count > 4, w.hasSuffix("ies") { return [w, String(w.dropLast(3)) + "y", String(w.dropLast())] }
        if w.count > 4, ["ses", "xes", "zes", "ches", "shes"].contains(where: { w.hasSuffix($0) }) {
            return [w, String(w.dropLast(2)), String(w.dropLast())]
        }
        if w.count > 3, w.hasSuffix("s"), !["ss", "us", "is"].contains(where: { w.hasSuffix($0) }) {
            return [w, String(w.dropLast())]
        }
        return [w]
    }

    /// The roots a word may have: itself, its singular, and — only when an
    /// "-ing" or "-ed" really came off — that root as written, with an "e"
    /// back on, and with a doubled last letter undone.
    static func stems(_ word: String) -> [String] {
        var out: [String] = []
        func add(_ s: String) { if !out.contains(s) { out.append(s) } }
        for w in singulars(word) {
            add(w)
            var root: String?
            if w.count > 5, w.hasSuffix("ing") {
                root = String(w.dropLast(3))
            } else if w.count > 4, w.hasSuffix("ed"), !w.hasSuffix("eed") {
                root = String(w.dropLast(2))
            }
            guard let root, root.contains(where: { "aeiouy".contains($0) }) else { continue }
            add(root)
            add(root + "e")
            let tail = Array(root.suffix(2))
            if tail.count == 2, tail[0] == tail[1], "bcdfghjklmnpqrstvwxz".contains(tail[1]) {
                add(String(root.dropLast()))
            }
        }
        return out
    }

    /// Whether two words share a root (see `stems`).
    static func sameStem(_ a: String, _ b: String) -> Bool {
        let roots = stems(a)
        return stems(b).contains { roots.contains($0) }
    }

    /// A letter, as `\p{L}` reads one.
    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
        default: return false
        }
    }

    /// Whether a clue may be given with these words face down: one word of
    /// letters (a hyphen or apostrophe inside is fine), no longer than
    /// `maxClue`, and not a face-down word, nor sharing its root, nor
    /// starting or ending it or starting or ending with it. The server's
    /// sentence for the spymaster, or nil when it is fine.
    static func clueProblem(_ text: String, faceDown: [String]) -> String? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "Type a clue." }
        if raw.utf16.count > maxClue { return "Keep it under \(maxClue) letters." }
        let scalars = Array(raw.unicodeScalars)
        let joiners: Set<UInt32> = [0x27, 0x2019, 0x2D]
        guard let first = scalars.first, isLetter(first),
              scalars.dropFirst().allSatisfy({ isLetter($0) || joiners.contains($0.value) }) else {
            return "One word, letters only."
        }
        let c = normalise(raw).replacingOccurrences(of: " ", with: "")
        if c.isEmpty { return "One word, letters only." }
        for word in faceDown {
            let w = normalise(word)
            if c == w || sameStem(c, w) { return "That is a word on the board." }
            // A compound or a part: snowman for SNOW, bank for BANKRUPT. Only at
            // an end — planet is a fair clue with NET on the board, education with CAT.
            let holds = w.count >= 4 ? c.hasPrefix(w) || c.hasSuffix(w) : w.count == 3 && c.hasPrefix(w)
            let inside = c.count >= 3 && (w.hasPrefix(c) || w.hasSuffix(c))
            if holds || inside { return "Too close to \(word.uppercased())." }
        }
        return nil
    }

    /// What the clue field keeps as somebody types: no spaces or line breaks
    /// (a clue is one word), at most `maxClue` characters.
    static func typing(_ raw: String) -> String {
        String(raw.filter { !$0.isWhitespace }.prefix(maxClue))
    }

    /// The number stepper's range.
    static func clampCount(_ n: Int) -> Int { min(maxCount, max(1, n)) }

    // MARK: Words for the table

    /// "OCEAN · 2".
    static func clueText(_ clue: CodenamesClue) -> String { "\(clue.word) · \(clue.count)" }

    /// "2 guesses left", "1 guess left", "No guesses left".
    static func guessesLine(_ n: Int) -> String {
        n <= 0 ? "No guesses left" : n == 1 ? "1 guess left" : "\(n) guesses left"
    }

    /// "4 of 9 found".
    static func agentsLine(_ side: CodenamesSide) -> String { "\(side.found) of \(side.agents) found" }

    /// The banner's headline, for this phone, in play.
    static func headline(_ state: CodenamesState) -> String {
        let team = state.turnTeam
        switch state.phase {
        case .clue:
            if state.canClue { return "Your clue" }
            return state.mode == .coop ? "The spymaster is thinking" : "\(team.label)’s spymaster is thinking"
        case .guess:
            if state.canGuess { return state.mode == .coop ? "Your guess" : "Your team’s guess" }
            return "\(team.label) are guessing"
        default:
            return "Setting up…"
        }
    }

    /// The banner's line under the headline: what to do, or what is happening.
    static func detail(_ state: CodenamesState, name: (String) -> String) -> String? {
        let team = state.turnTeam
        switch state.phase {
        case .clue:
            if state.canClue { return "One word and a number: how many of your agents it points to." }
            if state.myTeam == team {
                let who = state.spymaster(team).map { name($0.id) } ?? "Your spymaster"
                return "\(who) is choosing a clue for your team."
            }
            return state.myTeam == nil ? "You are watching this one." : "Your turn comes next."
        case .guess:
            if state.canGuess {
                return state.touched.isEmpty
                    ? "Tap a card to lift it, tap it again to turn it over."
                    : "Keep going, or end the turn while you're ahead."
            }
            if state.amSpymaster, state.myTeam == team { return "Your team is guessing. Not a word." }
            return state.myTeam == nil ? "You are watching this one." : "Watch the grid: each card they turn tells you something."
        default:
            return nil
        }
    }

    /// The table is waiting on: the spymaster for a clue, the operatives to guess.
    static func waitingOn(_ state: CodenamesState) -> [CodenamesSeat] {
        let team = state.turnTeam
        switch state.phase {
        case .clue:
            return state.spymaster(team).map { [$0] } ?? []
        case .guess:
            let members = state.members(team)
            let operatives = members.filter { !$0.spymaster }
            return operatives.isEmpty ? members : operatives
        default:
            return []
        }
    }

    /// What a turned card did, said after it lands: "Bystander. Blue's turn." —
    /// for VoiceOver, and under the grid for a moment.
    static func revealLine(_ last: CodenamesLast, word: String, mode: CodenamesMode) -> String {
        let card = word.uppercased()
        if last.auto { return "\(card) turned itself over: a blue agent." }
        switch last.kind {
        case .assassin: return "\(card) was the assassin."
        case .neutral: return "\(card) was a bystander."
        default:
            if last.kind.team == last.team { return "\(card) was one of theirs." }
            return mode == .coop ? "\(card) was a blue agent." : "\(card) was \(last.kind.spoken), for the other team."
        }
    }

    /// What the reveal should feel like on this phone: good for my team, bad
    /// for the assassin or the other side's agent, a tick otherwise.
    enum Feel: Equatable { case good, bad, plain }

    static func feel(_ last: CodenamesLast, myTeam: CodenamesTeam?) -> Feel {
        if last.kind == .assassin { return .bad }
        guard let myTeam, let owner = last.kind.team else { return .plain }
        return owner == myTeam ? .good : .bad
    }

    /// The finished page's headline, for this phone.
    static func endingTitle(_ result: CodenamesResult?, mode: CodenamesMode, myTeam: CodenamesTeam?) -> String {
        guard let result else { return "Game over" }
        if mode == .coop { return result.winner == nil ? "Blue got there first" : "You found them all" }
        guard let winner = result.winner else { return "Game over" }
        if let myTeam { return winner == myTeam ? "Your team wins" : "\(winner.label) win" }
        return "\(winner.label) win"
    }

    /// How the game ended, in a sentence.
    static func endingLine(_ result: CodenamesResult?, mode: CodenamesMode, last: CodenamesLast?) -> String {
        guard let result else { return "The game is over." }
        switch (mode, result.reason) {
        case (.coop, "assassin"): return "The assassin. The team is out, and the rest of the key is on the board."
        case (.coop, "left"): return "Not enough players left to carry on."
        case (.coop, _):
            return result.winner == nil
                ? "Blue's eight agents all turned themselves over before red found nine."
                : "All nine red agents found before blue's ran out."
        case (_, "assassin"):
            let loser = last?.team ?? result.winner?.other
            return "\(loser?.label ?? "A team") touched the assassin, so \(result.winner?.label ?? "the other team") win."
        case (_, "left"):
            return "Everybody on \(result.winner?.other.label ?? "the other team") left, so \(result.winner?.label ?? "the others") win."
        default:
            return "\(result.winner?.label ?? "A team") found every one of their agents first."
        }
    }

    /// Leaving mid-game, for the confirm.
    static func leaveWarning(spymaster: Bool, mates: Int) -> String {
        if mates == 0 { return "You're the last of your team: leaving loses the game for them." }
        return spymaster
            ? "A team-mate takes over the clues. The game carries on."
            : "Your team carries on without you."
    }
}
