import Foundation

// Secret Mission's wire pieces and the little the phone works out itself —
// which team is complete, how a mission reads, what a role means — as pure
// values, so each is a unit test. The server deals the roles, counts every
// vote and card, and refuses a crew Sabotage; nothing here decides an outcome.
//
// The room's Secret Mission side is decoded whole into `MissionState`, read
// off the same JSON as `GameRoom` (`GameRoom.mission`). The wire is per phone:
// `secret` is mine alone, and nobody else's role arrives before the finish.

/// Where a Secret Mission room is. Read from the room's raw `phase`: the
/// shared `GamePhase` decodes `proposing`, `voting` and the rest as `.unknown`.
enum MissionPhase: String, Equatable {
    case lobby, countdown, roles, proposing, voting, tally, mission, outcome, hunt, finished, closed, unknown

    static func from(_ raw: String?) -> MissionPhase {
        guard let raw else { return .unknown }
        return MissionPhase(rawValue: raw) ?? .unknown
    }
}

enum MissionSide: String, Equatable {
    case crew, spies

    var title: String { self == .crew ? "The crew" : "The spies" }
}

enum MissionRole: String, Equatable {
    case crew, spy, lookout, tracker

    var side: MissionSide { self == .spy || self == .tracker ? .spies : .crew }

    var title: String {
        switch self {
        case .crew: return "Crew"
        case .spy: return "Spy"
        case .lookout: return "Lookout"
        case .tracker: return "Tracker"
        }
    }

    /// What the role card says under the name.
    var brief: String {
        switch self {
        case .crew:
            return "You are crew. Get three missions through. You don't know who the spies are — watch the votes and the results."
        case .spy:
            return "You are a spy. Sabotage three missions, or get five teams rejected in a row. Act like crew."
        case .lookout:
            return "You are crew, and you know who the spies are. Steer the table without giving yourself away: if the crew win, the Tracker gets one guess at you."
        case .tracker:
            return "You are a spy. If the crew win three missions, you get one guess at who the Lookout is — name them and the spies win."
        }
    }

    var icon: String {
        switch self {
        case .crew: return "person.fill"
        case .spy: return "eye.slash.fill"
        case .lookout: return "binoculars.fill"
        case .tracker: return "scope"
        }
    }
}

/// My own secret: only ever my phone's.
struct MissionSecret: Decodable, Equatable {
    let role: MissionRole
    /// The other spies (for a spy), or all of them (for the Lookout). Empty for the crew.
    let spies: [String]
    /// My vote while voting; nil until cast.
    let vote: Bool?
    /// My card on the mission: "succeed" | "sabotage"; nil until played.
    let card: String?

    var side: MissionSide { role.side }

    private enum CodingKeys: String, CodingKey { case role, spies, vote, card }

    init(role: MissionRole, spies: [String] = [], vote: Bool? = nil, card: String? = nil) {
        self.role = role; self.spies = spies; self.vote = vote; self.card = card
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .role)
        guard let role = MissionRole(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .role, in: c, debugDescription: "unknown role \(raw)")
        }
        self.role = role
        spies = (try? c.decodeIfPresent([String].self, forKey: .spies)) ?? []
        vote = (try? c.decodeIfPresent(Bool.self, forKey: .vote)) ?? nil
        card = (try? c.decodeIfPresent(String.self, forKey: .card)) ?? nil
    }
}

/// A player as Secret Mission sees them. Name and status are the shared `GamePlayer`'s.
struct MissionSeat: Decodable, Equatable, Identifiable {
    let id: String
    let seated: Bool
    let ready: Bool
    /// Has voted (while voting) — never how.
    let voted: Bool
    let onTeam: Bool
    /// Has played a card (on the mission) — never which.
    let played: Bool
    /// Null until the finish.
    let role: MissionRole?
    /// `spies` for a spy in the hunt; everyone's at the finish.
    let side: MissionSide?

    private enum CodingKeys: String, CodingKey { case id, seated, ready, voted, onTeam, played, role, side }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        seated = (try? c.decodeIfPresent(Bool.self, forKey: .seated)) ?? false
        ready = (try? c.decodeIfPresent(Bool.self, forKey: .ready)) ?? false
        voted = (try? c.decodeIfPresent(Bool.self, forKey: .voted)) ?? false
        onTeam = (try? c.decodeIfPresent(Bool.self, forKey: .onTeam)) ?? false
        played = (try? c.decodeIfPresent(Bool.self, forKey: .played)) ?? false
        role = ((try? c.decodeIfPresent(String.self, forKey: .role)) ?? nil).flatMap(MissionRole.init(rawValue:))
        side = ((try? c.decodeIfPresent(String.self, forKey: .side)) ?? nil).flatMap(MissionSide.init(rawValue:))
    }
}

/// A decided proposal: who led, who went, every vote.
struct MissionTally: Decodable, Equatable {
    let mission: Int
    let attempt: Int
    let leaderId: String
    let team: [String]
    let approve: [String]
    let reject: [String]
    /// Voted for by the server (out of time, or gone).
    let auto: [String]
    let approved: Bool
    let autoTeam: Bool

    private enum CodingKeys: String, CodingKey { case mission, attempt, leaderId, team, approve, reject, auto, approved, autoTeam }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mission = (try? c.decodeIfPresent(Int.self, forKey: .mission)) ?? 1
        attempt = (try? c.decodeIfPresent(Int.self, forKey: .attempt)) ?? 1
        leaderId = (try? c.decodeIfPresent(String.self, forKey: .leaderId)) ?? ""
        team = (try? c.decodeIfPresent([String].self, forKey: .team)) ?? []
        approve = (try? c.decodeIfPresent([String].self, forKey: .approve)) ?? []
        reject = (try? c.decodeIfPresent([String].self, forKey: .reject)) ?? []
        auto = (try? c.decodeIfPresent([String].self, forKey: .auto)) ?? []
        approved = (try? c.decodeIfPresent(Bool.self, forKey: .approved)) ?? false
        autoTeam = (try? c.decodeIfPresent(Bool.self, forKey: .autoTeam)) ?? false
    }
}

/// A mission run: the count of Sabotage cards, never who played them.
struct MissionOutcome: Decodable, Equatable, Identifiable {
    let mission: Int
    let leaderId: String
    let team: [String]
    let needed: Int
    let sabotages: Int
    let succeeded: Bool

    var id: Int { mission }

    private enum CodingKeys: String, CodingKey { case mission, leaderId, team, needed, sabotages, succeeded }

    init(mission: Int, leaderId: String = "", team: [String] = [], needed: Int = 1, sabotages: Int, succeeded: Bool) {
        self.mission = mission; self.leaderId = leaderId; self.team = team
        self.needed = needed; self.sabotages = sabotages; self.succeeded = succeeded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mission = (try? c.decodeIfPresent(Int.self, forKey: .mission)) ?? 1
        leaderId = (try? c.decodeIfPresent(String.self, forKey: .leaderId)) ?? ""
        team = (try? c.decodeIfPresent([String].self, forKey: .team)) ?? []
        needed = max(1, (try? c.decodeIfPresent(Int.self, forKey: .needed)) ?? 1)
        sabotages = max(0, (try? c.decodeIfPresent(Int.self, forKey: .sabotages)) ?? 0)
        succeeded = (try? c.decodeIfPresent(Bool.self, forKey: .succeeded)) ?? (sabotages < needed)
    }
}

struct MissionResult: Decodable, Equatable {
    /// Nil when the game was abandoned.
    let winner: MissionSide?
    /// missions | sabotage | rejections | hunt | abandoned
    let reason: String
    let guessId: String?

    private enum CodingKeys: String, CodingKey { case winner, reason, guessId }

    init(winner: MissionSide?, reason: String, guessId: String? = nil) {
        self.winner = winner; self.reason = reason; self.guessId = guessId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        winner = ((try? c.decodeIfPresent(String.self, forKey: .winner)) ?? nil).flatMap(MissionSide.init(rawValue:))
        reason = (try? c.decodeIfPresent(String.self, forKey: .reason)) ?? "missions"
        guessId = (try? c.decodeIfPresent(String.self, forKey: .guessId)) ?? nil
    }
}

/// The room's Secret Mission side, decoded from the same JSON as `GameRoom`.
/// Lenient throughout: a lobby from the create call carries none of it.
struct MissionState: Decodable, Equatable {
    let phase: MissionPhase
    let rule: String?
    /// The Lookout and the Tracker are in play (medium, hard).
    let specials: Bool
    let minPlayers: Int
    let maxPlayers: Int
    /// Players dealt in; 0 before the deal.
    let seats: Int
    let spyCount: Int
    let teamSizes: [Int]
    let sabotagesNeeded: [Int]
    let proposeMs: Double
    let voteMs: Double
    let missionMs: Double
    let huntMs: Double
    /// 1-based.
    let mission: Int
    let attempt: Int
    let rejections: Int
    let maxRejections: Int
    let leaderId: String?
    /// The team proposed or sent; nil outside voting, tally, mission and outcome.
    let team: [String]?
    let autoTeam: Bool
    let crewScore: Int
    let spyScore: Int
    let secret: MissionSecret?
    let trackerId: String?
    let seatsById: [MissionSeat]
    let tallies: [MissionTally]
    let missions: [MissionOutcome]
    let result: MissionResult?

    private enum CodingKeys: String, CodingKey {
        case phase, rule, specials, minPlayers, maxPlayers, seats, spyCount, teamSizes, sabotagesNeeded
        case proposeMs, voteMs, missionMs, huntMs, mission, attempt, rejections, maxRejections, leaderId, team, autoTeam
        case score, secret, trackerId, players, tallies, missions, result
    }

    private struct Score: Decodable { let crew: Int?; let spies: Int? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = MissionPhase.from((try? c.decodeIfPresent(String.self, forKey: .phase)) ?? nil)
        rule = (try? c.decodeIfPresent(String.self, forKey: .rule)) ?? nil
        specials = (try? c.decodeIfPresent(Bool.self, forKey: .specials)) ?? false
        minPlayers = (try? c.decodeIfPresent(Int.self, forKey: .minPlayers)) ?? MissionRules.minPlayers
        maxPlayers = (try? c.decodeIfPresent(Int.self, forKey: .maxPlayers)) ?? MissionRules.maxPlayers
        seats = (try? c.decodeIfPresent(Int.self, forKey: .seats)) ?? 0
        spyCount = (try? c.decodeIfPresent(Int.self, forKey: .spyCount)) ?? 0
        teamSizes = (try? c.decodeIfPresent([Int].self, forKey: .teamSizes)) ?? []
        sabotagesNeeded = (try? c.decodeIfPresent([Int].self, forKey: .sabotagesNeeded)) ?? []
        proposeMs = (try? c.decodeIfPresent(Double.self, forKey: .proposeMs)) ?? 90_000
        voteMs = (try? c.decodeIfPresent(Double.self, forKey: .voteMs)) ?? 45_000
        missionMs = (try? c.decodeIfPresent(Double.self, forKey: .missionMs)) ?? 30_000
        huntMs = (try? c.decodeIfPresent(Double.self, forKey: .huntMs)) ?? 90_000
        mission = max(0, (try? c.decodeIfPresent(Int.self, forKey: .mission)) ?? 0)
        attempt = (try? c.decodeIfPresent(Int.self, forKey: .attempt)) ?? 0
        rejections = (try? c.decodeIfPresent(Int.self, forKey: .rejections)) ?? 0
        maxRejections = (try? c.decodeIfPresent(Int.self, forKey: .maxRejections)) ?? 5
        leaderId = (try? c.decodeIfPresent(String.self, forKey: .leaderId)) ?? nil
        team = (try? c.decodeIfPresent([String].self, forKey: .team)) ?? nil
        autoTeam = (try? c.decodeIfPresent(Bool.self, forKey: .autoTeam)) ?? false
        let score = (try? c.decodeIfPresent(Score.self, forKey: .score)) ?? nil
        crewScore = score?.crew ?? 0
        spyScore = score?.spies ?? 0
        secret = (try? c.decodeIfPresent(MissionSecret.self, forKey: .secret)) ?? nil
        trackerId = (try? c.decodeIfPresent(String.self, forKey: .trackerId)) ?? nil
        seatsById = (try? c.decodeIfPresent([MissionSeat].self, forKey: .players)) ?? []
        tallies = (try? c.decodeIfPresent([MissionTally].self, forKey: .tallies)) ?? []
        missions = (try? c.decodeIfPresent([MissionOutcome].self, forKey: .missions)) ?? []
        result = (try? c.decodeIfPresent(MissionResult.self, forKey: .result)) ?? nil
    }

    func seat(_ id: String) -> MissionSeat? { seatsById.first { $0.id == id } }

    /// This mission's team size.
    var teamSize: Int { MissionRules.size(teamSizes, mission: mission) }

    /// Sabotage cards that fail this mission.
    var needed: Int {
        let i = mission - 1
        return sabotagesNeeded.indices.contains(i) ? sabotagesNeeded[i] : 1
    }

    var lastTally: MissionTally? { tallies.last }
    var lastOutcome: MissionOutcome? { missions.last }

    /// Players with a seat at the table, in seat order.
    var seatedIds: [String] { seatsById.filter(\.seated).map(\.id) }
}

// MARK: - The rules the phone uses

enum MissionRules {
    static let minPlayers = 5
    static let maxPlayers = 10
    static let missions = 5

    /// The team size for mission `mission` (1-based); 0 when unknown.
    static func size(_ sizes: [Int], mission: Int) -> Int {
        let i = max(0, mission - 1)
        return sizes.indices.contains(i) ? sizes[i] : 0
    }

    /// Spies at each table size: the standard counts, for the lobby.
    static func spies(for players: Int) -> Int {
        switch players {
        case ..<7: return 2
        case 7...9: return 3
        default: return 4
        }
    }

    /// Picking a team: tap to add, tap again to take off; full is full.
    static func toggle(_ id: String, in picked: [String], size: Int) -> [String] {
        if let at = picked.firstIndex(of: id) {
            var out = picked
            out.remove(at: at)
            return out
        }
        guard picked.count < size else { return picked }
        return picked + [id]
    }

    /// The lobby's line: how many more are needed, or the split once there are enough.
    static func tableLine(players: Int) -> String {
        if players < minPlayers {
            let more = minPlayers - players
            return "Needs \(more) more \(more == 1 ? "player" : "players") — five to ten."
        }
        let spies = spies(for: min(players, maxPlayers))
        return "\(players) players: \(players - spies) crew, \(spies) spies."
    }

    /// "2 sabotages", "1 sabotage".
    static func sabotages(_ n: Int) -> String { n == 1 ? "1 sabotage" : "\(n) sabotages" }

    /// The outcome in a sentence: "Mission 2 succeeded — no sabotage." /
    /// "Mission 3 was sabotaged — 2 sabotages."
    static func outcomeLine(_ o: MissionOutcome) -> String {
        if o.succeeded {
            if o.sabotages == 0 { return "Mission \(o.mission) succeeded — no sabotage." }
            return "Mission \(o.mission) succeeded — \(sabotages(o.sabotages)), but it needed \(o.needed) to fail."
        }
        return "Mission \(o.mission) was sabotaged — \(sabotages(o.sabotages))."
    }

    /// The tally in a sentence: "Approved, 4 to 1." / "Rejected, 2 to 3."
    static func tallyLine(_ t: MissionTally) -> String {
        "\(t.approved ? "Approved" : "Rejected"), \(t.approve.count) to \(t.reject.count)."
    }

    /// The finish headline, from my side's view.
    static func headline(_ result: MissionResult?, mySide: MissionSide?) -> String {
        guard let result, let winner = result.winner else { return "Nobody won" }
        if let mySide { return mySide == winner ? "Your side wins" : "\(winner.title) win" }
        return "\(winner.title) win"
    }

    /// Why it ended, in a sentence.
    static func reasonLine(_ result: MissionResult?, name: (String) -> String) -> String {
        guard let result else { return "" }
        switch result.reason {
        case "sabotage": return "Three missions were sabotaged."
        case "rejections": return "Five teams were turned down in a row."
        case "hunt":
            let who = result.guessId.map(name) ?? "the Lookout"
            return "The crew won three missions, but the Tracker found the Lookout: \(who)."
        case "abandoned": return "Too many people left to carry on."
        default:
            if let guess = result.guessId { return "Three missions went through, and the Tracker guessed wrong (\(name(guess)))." }
            return "Three missions went through."
        }
    }

    /// The mission card footnote. One line for every team member: a crew phone
    /// and a spy phone must look the same from across the table.
    static let missionFootnote = "Nobody will see which you played — only how many sabotages there were. The crew can only succeed: Sabotage does nothing for them."

    /// Who is still at the table. A leaver's vote and card are played by the
    /// server, so nobody waits on them.
    static func stillHere(_ room: GameRoom) -> Set<String> {
        Set(room.players.filter(\.joined).map(\.id))
    }

    /// Votes still to come from people at the table.
    static func stillToVote(_ room: GameRoom) -> Int {
        let here = stillHere(room)
        return (room.mission?.seatsById ?? []).filter { $0.seated && !$0.voted && here.contains($0.id) }.count
    }

    /// Mission cards in, out of the team members still at the table.
    static func cardsIn(_ room: GameRoom) -> (played: Int, of: Int) {
        let here = stillHere(room)
        let team = (room.mission?.team ?? []).filter(here.contains)
        return (team.filter { room.mission?.seat($0)?.played == true }.count, team.count)
    }

    /// The fraction of a clock left, 0…1 (1 when it is unknown).
    static func timeLeft(endsAt: Double?, totalMs: Double, now: Double?) -> Double {
        guard let endsAt, let now, totalMs > 0 else { return 1 }
        return min(1, max(0, (endsAt - now) / totalMs))
    }
}

// MARK: - The host's choices

struct MissionSettings: Equatable {
    var difficulty: GameDifficulty

    func createBody(invite: [String]) -> CreateGameBody {
        CreateGameBody(game: GameKind.mission.rawValue, difficulty: difficulty.rawValue, invite: invite)
    }

    /// "With a Lookout and a Tracker", for the lobby — as the server's `about`.
    static func about(_ difficulty: String) -> String {
        difficulty == "easy" ? "Crew and spies only" : "With a Lookout and a Tracker"
    }
}

/// Which of the screen's pages a room is on: the game's own phase when the
/// room carries it, else the shared one (a lobby from an older answer).
enum MissionScreenPhase {
    static func of(_ room: GameRoom) -> MissionPhase {
        if let phase = room.mission?.phase, phase != .unknown { return phase }
        switch room.phase {
        case .lobby: return .lobby
        case .countdown: return .countdown
        case .finished: return .finished
        case .closed: return .closed
        default: return .unknown
        }
    }
}
