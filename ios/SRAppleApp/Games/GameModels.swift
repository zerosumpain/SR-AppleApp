import Foundation

// The wire shapes of `/api/native/games*`, exactly as the site sends them —
// see docs/superpowers/specs/2026-09-26-family-games-tap-duel.md in SR-Main.
//
// Every server time is EPOCH MILLISECONDS (a JSON number). They are decoded as
// `Double` so an integer and a fractional value both read, and are only ever
// turned into the phone's own time through `GameClock`, never through `Date`.
//
// Decoding is lenient where a missing field has an obvious meaning (no score
// yet is 0, no decoys is none) and strict where it does not: a room without an
// id or a phase is not a room.

/// Navigation value for one room, pushed on the Games tab's stack.
struct GameRoomRef: Hashable {
    let id: String
}

/// How hard a Tap Duel is. Picked by the host, for the whole game.
enum GameDifficulty: String, CaseIterable, Identifiable, Codable {
    case easy, medium, hard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        }
    }

    /// One line, from the spec's table.
    var line: String {
        switch self {
        case .easy: return "Green after 2–4 s. No decoys. 2 s to tap."
        case .medium: return "Green after 1.5–5 s. Maybe one decoy. 1.2 s to tap."
        case .hard: return "Green after 1–6 s. One or two decoys. 0.8 s to tap."
        }
    }

    /// A label for a difficulty string the app may not know yet.
    static func label(for raw: String) -> String {
        GameDifficulty(rawValue: raw)?.label ?? raw.capitalized
    }
}

/// Where a room is in its life.
enum GamePhase: String, Decodable {
    case lobby, countdown, armed, result, finished, closed
    /// A phase this version of the app has not heard of. Shown as "waiting",
    /// never a thrown decode — a newer site must not blank an open game.
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GamePhase(rawValue: raw) ?? .unknown
    }
}

/// Somebody the phone can invite, or the person holding it.
struct GamePerson: Decodable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
}

/// A pending invitation to somebody else's room.
struct GameInvite: Decodable, Equatable, Identifiable {
    let roomId: String
    let game: String
    let difficulty: String
    let hostName: String
    let players: [String]
    let expiresAt: Double?

    var id: String { roomId }

    private enum CodingKeys: String, CodingKey { case roomId, game, difficulty, hostName, players, expiresAt }

    init(roomId: String, game: String, difficulty: String, hostName: String, players: [String], expiresAt: Double?) {
        self.roomId = roomId; self.game = game; self.difficulty = difficulty
        self.hostName = hostName; self.players = players; self.expiresAt = expiresAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roomId = try c.decode(String.self, forKey: .roomId)
        game = (try? c.decodeIfPresent(String.self, forKey: .game)) ?? "tap-duel"
        difficulty = (try? c.decodeIfPresent(String.self, forKey: .difficulty)) ?? "easy"
        hostName = (try? c.decodeIfPresent(String.self, forKey: .hostName)) ?? "Someone"
        players = (try? c.decodeIfPresent([String].self, forKey: .players)) ?? []
        expiresAt = (try? c.decodeIfPresent(Double.self, forKey: .expiresAt)) ?? nil
    }

    /// The notification's title and body. Pure, so the copy is a test.
    var notificationTitle: String { "\(hostName) invited you to \(GameNames.title(game))" }

    var notificationBody: String {
        let level = GameDifficulty.label(for: difficulty)
        let others = players.filter { $0 != hostName }
        let who = others.isEmpty ? "with \(hostName)" : "with \(GameNames.list([hostName] + others))"
        return "\(level), \(who). Tap to join."
    }
}

/// A room I have joined and that has not closed.
struct GameRoomSummary: Decodable, Equatable, Identifiable {
    let id: String
    let game: String
    let phase: GamePhase
    let hostName: String
}

/// `GET /api/native/games` — the lobby poll.
struct GamesLobby: Decodable, Equatable {
    let me: GamePerson
    let players: [GamePerson]
    let invites: [GameInvite]
    let rooms: [GameRoomSummary]
    let serverNow: Double

    private enum CodingKeys: String, CodingKey { case me, players, invites, rooms, serverNow }

    init(me: GamePerson, players: [GamePerson], invites: [GameInvite], rooms: [GameRoomSummary], serverNow: Double) {
        self.me = me; self.players = players; self.invites = invites; self.rooms = rooms; self.serverNow = serverNow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        me = try c.decode(GamePerson.self, forKey: .me)
        players = (try? c.decodeIfPresent([GamePerson].self, forKey: .players)) ?? []
        invites = (try? c.decodeIfPresent([GameInvite].self, forKey: .invites)) ?? []
        rooms = (try? c.decodeIfPresent([GameRoomSummary].self, forKey: .rooms)) ?? []
        serverNow = (try? c.decodeIfPresent(Double.self, forKey: .serverNow)) ?? 0
    }
}

// MARK: - The room

struct GamePlayer: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    /// invited | joined | declined | left
    let status: String
    let score: Int
    let isHost: Bool

    private enum CodingKeys: String, CodingKey { case id, name, status, score, isHost }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Player"
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "joined"
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        isHost = (try? c.decodeIfPresent(Bool.self, forKey: .isHost)) ?? false
    }

    var joined: Bool { status == "joined" }
}

struct GameDecoy: Decodable, Equatable {
    /// When the flash starts, server epoch ms.
    let at: Double
    /// How long it lasts.
    let ms: Double
}

struct GameResponse: Decodable, Equatable {
    let playerId: String
    /// Null while the round is armed; filled in at the result.
    let reactionMs: Int?
    let early: Bool

    private enum CodingKeys: String, CodingKey { case playerId, reactionMs, early }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(String.self, forKey: .playerId)
        if let whole = try? c.decodeIfPresent(Int.self, forKey: .reactionMs) {
            reactionMs = whole
        } else if let fraction = try? c.decodeIfPresent(Double.self, forKey: .reactionMs) {
            reactionMs = Int(fraction.rounded())
        } else {
            reactionMs = nil
        }
        early = (try? c.decodeIfPresent(Bool.self, forKey: .early)) ?? false
    }
}

struct GameRound: Decodable, Equatable {
    let number: Int
    /// The instant every phone turns green, server epoch ms.
    let goAt: Double
    let windowMs: Double
    let closesAt: Double?
    let decoys: [GameDecoy]
    let responses: [GameResponse]
    let winnerId: String?

    private enum CodingKeys: String, CodingKey { case number, goAt, windowMs, closesAt, decoys, responses, winnerId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decode(Int.self, forKey: .number)
        goAt = try c.decode(Double.self, forKey: .goAt)
        windowMs = (try? c.decodeIfPresent(Double.self, forKey: .windowMs)) ?? 2000
        closesAt = (try? c.decodeIfPresent(Double.self, forKey: .closesAt)) ?? nil
        decoys = (try? c.decodeIfPresent([GameDecoy].self, forKey: .decoys)) ?? []
        responses = (try? c.decodeIfPresent([GameResponse].self, forKey: .responses)) ?? []
        winnerId = (try? c.decodeIfPresent(String.self, forKey: .winnerId)) ?? nil
    }

    func response(for playerId: String) -> GameResponse? {
        responses.first { $0.playerId == playerId }
    }
}

struct GameStanding: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let score: Int
    let bestMs: Int?
    let avgMs: Int?
    let falseStarts: Int

    private enum CodingKeys: String, CodingKey { case id, name, score, bestMs, avgMs, falseStarts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Player"
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        func ms(_ key: CodingKeys) -> Int? {
            ((try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil).map { Int($0.rounded()) }
        }
        bestMs = ms(.bestMs)
        avgMs = ms(.avgMs)
        falseStarts = (try? c.decodeIfPresent(Int.self, forKey: .falseStarts)) ?? 0
    }
}

/// One room: the body of `{ room }` and of every stream frame.
struct GameRoom: Decodable, Equatable, Identifiable {
    let id: String
    let game: String
    let difficulty: String
    let phase: GamePhase
    let hostId: String
    let meId: String
    let rounds: Int
    let players: [GamePlayer]
    /// Countdown end, result end, lobby expiry. Nil when open-ended.
    let phaseEndsAt: Double?
    let round: GameRound?
    let standings: [GameStanding]?
    let winnerIds: [String]
    let serverNow: Double

    private enum CodingKeys: String, CodingKey {
        case id, game, difficulty, phase, hostId, meId, rounds, players, phaseEndsAt, round, standings, winnerIds, serverNow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        phase = try c.decode(GamePhase.self, forKey: .phase)
        game = (try? c.decodeIfPresent(String.self, forKey: .game)) ?? "tap-duel"
        difficulty = (try? c.decodeIfPresent(String.self, forKey: .difficulty)) ?? "easy"
        hostId = (try? c.decodeIfPresent(String.self, forKey: .hostId)) ?? ""
        meId = (try? c.decodeIfPresent(String.self, forKey: .meId)) ?? ""
        rounds = (try? c.decodeIfPresent(Int.self, forKey: .rounds)) ?? 5
        players = (try? c.decodeIfPresent([GamePlayer].self, forKey: .players)) ?? []
        phaseEndsAt = (try? c.decodeIfPresent(Double.self, forKey: .phaseEndsAt)) ?? nil
        round = (try? c.decodeIfPresent(GameRound.self, forKey: .round)) ?? nil
        standings = (try? c.decodeIfPresent([GameStanding].self, forKey: .standings)) ?? nil
        winnerIds = (try? c.decodeIfPresent([String].self, forKey: .winnerIds)) ?? []
        serverNow = try c.decode(Double.self, forKey: .serverNow)
    }

    var isHost: Bool { !meId.isEmpty && meId == hostId }
    var me: GamePlayer? { players.first { $0.id == meId } }
    var host: GamePlayer? { players.first { $0.id == hostId } }
    /// Everyone still in: joined players, host included.
    var playing: [GamePlayer] { players.filter(\.joined) }
    var solo: Bool { players.count <= 1 }

    func name(of id: String) -> String {
        players.first { $0.id == id }?.name ?? standings?.first { $0.id == id }?.name ?? "Someone"
    }
}

/// `{ room }` — the answer to a create, an action or a snapshot.
struct GameRoomEnvelope: Decodable {
    let room: GameRoom
}

/// A stream frame. Only `room` frames are acted on.
struct GameStreamFrame: Decodable {
    let type: String
    let room: GameRoom?
}

// MARK: - Request bodies

struct CreateGameBody: Encodable {
    var game: String = "tap-duel"
    let difficulty: String
    let invite: [String]
}

/// `POST /api/native/games/<id>`. Nil fields are left out of the JSON.
struct GameActionBody: Encodable {
    let action: String
    var round: Int? = nil
    var reactionMs: Int? = nil
    var early: Bool? = nil
}

enum GameNames {
    static func title(_ game: String) -> String {
        game == "tap-duel" ? "Tap Duel" : game.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// "Sam", "Sam and Robin", "John, Sam and Robin".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}
