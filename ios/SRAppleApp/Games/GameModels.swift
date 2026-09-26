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

/// Navigation value for one room, pushed on the Games tab's stack. `game` is
/// known from every list the room was picked from; a bare id (an old
/// notification) is resolved by `GameRoomScreen` reading the snapshot.
struct GameRoomRef: Hashable {
    let id: String
    var game: String? = nil
}

/// The games this version of the app can play. The wire carries a plain string
/// (`room.game`, `invite.game`), so a newer site's third game is a string this
/// enum does not know, never a decode failure.
enum GameKind: String, CaseIterable, Identifiable {
    case tapDuel = "tap-duel"
    case wordleRace = "wordle-race"
    case quizNight = "quiz-night"
    case anagramBlitz = "anagram-blitz"
    case mathsSprint = "maths-sprint"
    case sequenceMemory = "sequence-memory"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tapDuel: return "Tap Duel"
        case .wordleRace: return "Wordle Race"
        case .quizNight: return "Quiz Night"
        case .anagramBlitz: return "Anagram Blitz"
        case .mathsSprint: return "Quick Maths Sprint"
        case .sequenceMemory: return "Sequence Memory"
        }
    }

    /// One line for the new-game sheet's game picker.
    var line: String {
        switch self {
        case .tapDuel: return "Reaction race: wait for green, tap first."
        case .wordleRace: return "Same five-letter word, six guesses, race to solve."
        case .quizNight: return "jkai writes a quiz on any topic."
        case .anagramBlitz: return "Seven letters. Find as many words as you can."
        case .mathsSprint: return "Sixty seconds of mental arithmetic."
        case .sequenceMemory: return "Watch the tiles flash, then play them back."
        }
    }

    /// The shelf card's sentence.
    var blurb: String {
        switch self {
        case .tapDuel:
            return "Five rounds. Wait for green, then tap faster than everyone else. Tap early and the round is gone."
        case .wordleRace:
            return "Everyone gets the same five-letter word and six guesses. You see the others' colours, not their letters. Solve it first."
        case .quizNight:
            return "jkai writes ten questions on any topic you like. Four answers each; right scores, right and fast scores more."
        case .anagramBlitz:
            return "Everyone gets the same seven letters. Longer words score more, and a word only you found scores double."
        case .mathsSprint:
            return "Sixty seconds, the same problems for everyone. Right moves you on; every fifth in a row is a bonus."
        case .sequenceMemory:
            return "The tiles flash a sequence; tap it back. One more step each round. Miss and you are out."
        }
    }

    var icon: String {
        switch self {
        case .tapDuel: return "hand.tap.fill"
        case .wordleRace: return "character.textbox"
        case .quizNight: return "questionmark.bubble.fill"
        case .anagramBlitz: return "textformat.abc"
        case .mathsSprint: return "plus.forwardslash.minus"
        case .sequenceMemory: return "square.grid.3x3.fill"
        }
    }
}

/// How hard a game is. Picked by the host, for the whole game.
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

    /// One line, from the spec's table — Tap Duel's.
    var line: String { line(for: .tapDuel) }

    /// One line per game, from the spec's tables.
    func line(for game: GameKind) -> String {
        switch (game, self) {
        case (.tapDuel, .easy): return "Green after 2–4 s. No decoys. 2 s to tap."
        case (.tapDuel, .medium): return "Green after 1.5–5 s. Maybe one decoy. 1.2 s to tap."
        case (.tapDuel, .hard): return "Green after 1–6 s. One or two decoys. 0.8 s to tap."
        case (.wordleRace, .easy): return "The 500 commonest words. 5 minutes."
        case (.wordleRace, .medium): return "The 1,000 commonest words. 4 minutes."
        case (.wordleRace, .hard): return "Any of 1,405 words. 3 minutes. Hard mode: greens stay put, found letters stay in."
        case (.quizNight, .easy): return "20 seconds a question."
        case (.quizNight, .medium): return "15 seconds a question."
        case (.quizNight, .hard): return "10 seconds a question."
        case (.anagramBlitz, .easy): return "Common seed words. 2½ minutes. Words of 3 letters or more."
        case (.anagramBlitz, .medium): return "Less common seed words. 2 minutes. 3 letters or more."
        case (.anagramBlitz, .hard): return "Any seed word. 90 seconds. 4 letters or more."
        case (.mathsSprint, .easy): return "Adding and taking away up to 20. 60 seconds."
        case (.mathsSprint, .medium): return "+ and − up to 100, times tables to 10. 60 seconds."
        case (.mathsSprint, .hard): return "Up to 1,000, times to 12, exact division, two-step sums. 60 seconds."
        case (.sequenceMemory, .easy): return "4 tiles. Slow flashes."
        case (.sequenceMemory, .medium): return "6 tiles. Quicker flashes."
        case (.sequenceMemory, .hard): return "9 tiles. Fast flashes."
        }
    }

    /// A label for a difficulty string the app may not know yet.
    static func label(for raw: String) -> String {
        GameDifficulty(rawValue: raw)?.label ?? raw.capitalized
    }
}

/// Where a room is in its life.
enum GamePhase: String, Decodable {
    /// `armed` and `result` are Tap Duel's (`result` Sequence Memory's too);
    /// `playing` is Wordle Race's, Anagram Blitz's and Quick Maths Sprint's;
    /// `question` and `reveal` are Quiz Night's; `show` and `input` are
    /// Sequence Memory's.
    case lobby, countdown, armed, result, playing, question, reveal, show, input, finished, closed
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
    /// One line on what the game is, when it has something to say — Quiz
    /// Night's "The Solar System · for kids". Null (or absent, from an older
    /// site) for games with nothing to add.
    let about: String?

    var id: String { roomId }

    private enum CodingKeys: String, CodingKey { case roomId, game, difficulty, hostName, players, expiresAt, about }

    init(roomId: String, game: String, difficulty: String, hostName: String, players: [String], expiresAt: Double?,
         about: String? = nil) {
        self.roomId = roomId; self.game = game; self.difficulty = difficulty
        self.hostName = hostName; self.players = players; self.expiresAt = expiresAt
        self.about = about
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roomId = try c.decode(String.self, forKey: .roomId)
        game = (try? c.decodeIfPresent(String.self, forKey: .game)) ?? "tap-duel"
        difficulty = (try? c.decodeIfPresent(String.self, forKey: .difficulty)) ?? "easy"
        hostName = (try? c.decodeIfPresent(String.self, forKey: .hostName)) ?? "Someone"
        players = (try? c.decodeIfPresent([String].self, forKey: .players)) ?? []
        expiresAt = (try? c.decodeIfPresent(Double.self, forKey: .expiresAt)) ?? nil
        let line = ((try? c.decodeIfPresent(String.self, forKey: .about)) ?? nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        about = (line?.isEmpty ?? true) ? nil : line
    }

    /// The notification's title and body. Pure, so the copy is a test.
    /// "Sam invited you to Quiz Night — The Solar System · for kids" when the
    /// invite says what the game is about.
    var notificationTitle: String {
        let base = "\(hostName) invited you to \(GameNames.title(game))"
        guard let about else { return base }
        return "\(base) — \(about)"
    }

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
    /// Tap Duel: rounds won.
    let score: Int
    let isHost: Bool

    // Wordle Race. Absent (and so empty/zero) in a Tap Duel room.
    let guessCount: Int
    let solved: Bool
    /// Solved, out of guesses, or out of time: this player has nothing left to play.
    let done: Bool
    let solveMs: Int?
    /// Letters for me always, for the others only once the game is finished.
    let rows: [WordleRow]

    // Anagram Blitz. `score` is points.
    let wordCount: Int
    /// Mine always, everyone's once finished; nil for another player mid-game.
    let words: [AnagramWord]?

    // Quick Maths Sprint. `score` is points; `answered` is problems solved.
    let answered: Int

    // Sequence Memory.
    /// Seated when round 1 was dealt (`playing` on the wire — `GameRoom`
    /// already has a `playing`, the joined players).
    let seated: Bool
    let alive: Bool
    /// Longest sequence repeated correctly.
    let best: Int
    let roundsSurvived: Int
    let outRound: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, status, score, isHost, guessCount, solved, done, solveMs, rows
        case wordCount, words, answered
        case playing, alive, best, roundsSurvived, outRound
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Player"
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "joined"
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        isHost = (try? c.decodeIfPresent(Bool.self, forKey: .isHost)) ?? false
        rows = (try? c.decodeIfPresent([WordleRow].self, forKey: .rows)) ?? []
        guessCount = (try? c.decodeIfPresent(Int.self, forKey: .guessCount)) ?? rows.count
        solved = (try? c.decodeIfPresent(Bool.self, forKey: .solved)) ?? false
        done = (try? c.decodeIfPresent(Bool.self, forKey: .done)) ?? false
        solveMs = ((try? c.decodeIfPresent(Double.self, forKey: .solveMs)) ?? nil).map { Int($0.rounded()) }
        words = (try? c.decodeIfPresent([AnagramWord].self, forKey: .words)) ?? nil
        wordCount = (try? c.decodeIfPresent(Int.self, forKey: .wordCount)) ?? words?.count ?? 0
        answered = (try? c.decodeIfPresent(Int.self, forKey: .answered)) ?? 0
        seated = (try? c.decodeIfPresent(Bool.self, forKey: .playing)) ?? false
        alive = (try? c.decodeIfPresent(Bool.self, forKey: .alive)) ?? false
        best = (try? c.decodeIfPresent(Int.self, forKey: .best)) ?? 0
        roundsSurvived = (try? c.decodeIfPresent(Int.self, forKey: .roundsSurvived)) ?? 0
        outRound = (try? c.decodeIfPresent(Int.self, forKey: .outRound)) ?? nil
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
    // Tap Duel.
    let score: Int
    let bestMs: Int?
    let avgMs: Int?
    let falseStarts: Int
    // Wordle Race.
    let solved: Bool
    let guesses: Int?
    let solveMs: Int?
    // Quiz Night: questions answered right (`score` is points, `avgMs` the
    // average time of the right ones). Quick Maths Sprint: problems solved.
    let correct: Int
    // Anagram Blitz: how many words, and the longest.
    let words: Int
    let longest: String?
    // Quick Maths Sprint.
    let misses: Int
    let bestStreak: Int
    // Sequence Memory.
    let best: Int
    let roundsSurvived: Int
    let outRound: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, score, bestMs, avgMs, falseStarts, solved, guesses, solveMs, correct
        case words, longest, misses, bestStreak, best, roundsSurvived, outRound
    }

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
        solved = (try? c.decodeIfPresent(Bool.self, forKey: .solved)) ?? false
        guesses = (try? c.decodeIfPresent(Int.self, forKey: .guesses)) ?? nil
        solveMs = ms(.solveMs)
        correct = (try? c.decodeIfPresent(Int.self, forKey: .correct)) ?? 0
        words = (try? c.decodeIfPresent(Int.self, forKey: .words)) ?? 0
        longest = (try? c.decodeIfPresent(String.self, forKey: .longest)) ?? nil
        misses = (try? c.decodeIfPresent(Int.self, forKey: .misses)) ?? 0
        bestStreak = (try? c.decodeIfPresent(Int.self, forKey: .bestStreak)) ?? 0
        best = (try? c.decodeIfPresent(Int.self, forKey: .best)) ?? 0
        roundsSurvived = (try? c.decodeIfPresent(Int.self, forKey: .roundsSurvived)) ?? 0
        outRound = (try? c.decodeIfPresent(Int.self, forKey: .outRound)) ?? nil
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

    // Wordle Race. Defaults in a Tap Duel room.
    let wordLength: Int
    let maxGuesses: Int
    let timeLimitMs: Double?
    let hardMode: Bool
    /// When play began, server epoch ms. Nil before play.
    let startedAt: Double?
    /// My best mark per letter, lower-case keys.
    let keyboard: [String: WordleMark]
    /// The word, once finished.
    let secret: String?

    // Quiz Night. Nil (and `prep` ready) in the other games' rooms.
    /// kids | family | adults.
    let audience: String?
    /// What the host asked for; nil when jkai picks.
    let topic: String?
    /// What jkai wrote about — the topic, or the one it picked. Nil while writing.
    let title: String?
    let prep: QuizPrep
    /// Why the questions could not be written — a sentence for the players.
    let prepError: String?
    let questionCount: Int
    /// Seconds a question, in ms.
    let timeMs: Double?
    /// The open (or revealed) question.
    let question: QuizQuestion?

    // Anagram Blitz. `timeLimitMs`, `startedAt` as Wordle Race's.
    let letterCount: Int
    /// Shortest word accepted: 3, or 4 on hard.
    let minLength: Int
    /// Points by word length ("3" → 1 … "7" → 10).
    let points: [String: Int]
    /// The shuffled letters, lower-case. Nil before play.
    let letters: [String]?
    /// The word the letters came from, once finished.
    let seed: String?
    /// Every word anyone found, once finished.
    let found: [AnagramFound]?
    /// The longest words nobody found, once finished.
    let missed: [String]?

    // Quick Maths Sprint.
    let problemCount: Int
    let streakBonus: Int
    /// My own side (`me` on the wire — `GameRoom.me` is already my player
    /// row): my current problem, score, misses and streak.
    let sprint: SprintMe?
    /// Each player's last few problems with answers, once finished.
    let recaps: [SprintRecap]?

    // Sequence Memory.
    let tiles: Int
    let startLength: Int
    let maxLength: Int
    /// The round (`round` on the wire — Tap Duel's round is a different shape).
    let memory: SequenceRound?

    private enum CodingKeys: String, CodingKey {
        case id, game, difficulty, phase, hostId, meId, rounds, players, phaseEndsAt, round, standings, winnerIds, serverNow
        case wordLength, maxGuesses, timeLimitMs, hardMode, startedAt, keyboard, secret
        case audience, topic, title, prep, prepError, questionCount, timeMs, question
        case letterCount, minLength, points, letters, seed, found, missed
        case problemCount, streakBonus, me, recaps
        case tiles, startLength, maxLength
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
        wordLength = max(1, (try? c.decodeIfPresent(Int.self, forKey: .wordLength)) ?? 5)
        maxGuesses = max(1, (try? c.decodeIfPresent(Int.self, forKey: .maxGuesses)) ?? 6)
        timeLimitMs = (try? c.decodeIfPresent(Double.self, forKey: .timeLimitMs)) ?? nil
        hardMode = (try? c.decodeIfPresent(Bool.self, forKey: .hardMode)) ?? false
        startedAt = (try? c.decodeIfPresent(Double.self, forKey: .startedAt)) ?? nil
        keyboard = (try? c.decodeIfPresent([String: WordleMark].self, forKey: .keyboard)) ?? [:]
        secret = (try? c.decodeIfPresent(String.self, forKey: .secret)) ?? nil
        audience = (try? c.decodeIfPresent(String.self, forKey: .audience)) ?? nil
        topic = (try? c.decodeIfPresent(String.self, forKey: .topic)) ?? nil
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil
        // No `prep` is a room with nothing to prepare; the server decides Start.
        prep = (try? c.decodeIfPresent(QuizPrep.self, forKey: .prep)) ?? .ready
        prepError = (try? c.decodeIfPresent(String.self, forKey: .prepError)) ?? nil
        questionCount = (try? c.decodeIfPresent(Int.self, forKey: .questionCount)) ?? 10
        timeMs = (try? c.decodeIfPresent(Double.self, forKey: .timeMs)) ?? nil
        question = (try? c.decodeIfPresent(QuizQuestion.self, forKey: .question)) ?? nil
        letterCount = (try? c.decodeIfPresent(Int.self, forKey: .letterCount)) ?? 7
        minLength = (try? c.decodeIfPresent(Int.self, forKey: .minLength)) ?? 3
        points = (try? c.decodeIfPresent([String: Int].self, forKey: .points)) ?? [:]
        letters = ((try? c.decodeIfPresent([String].self, forKey: .letters)) ?? nil)?.map { $0.lowercased() }
        seed = ((try? c.decodeIfPresent(String.self, forKey: .seed)) ?? nil)?.lowercased()
        found = (try? c.decodeIfPresent([AnagramFound].self, forKey: .found)) ?? nil
        missed = (try? c.decodeIfPresent([String].self, forKey: .missed)) ?? nil
        problemCount = (try? c.decodeIfPresent(Int.self, forKey: .problemCount)) ?? 200
        streakBonus = max(1, (try? c.decodeIfPresent(Int.self, forKey: .streakBonus)) ?? 5)
        sprint = (try? c.decodeIfPresent(SprintMe.self, forKey: .me)) ?? nil
        recaps = (try? c.decodeIfPresent([SprintRecap].self, forKey: .recaps)) ?? nil
        tiles = max(1, (try? c.decodeIfPresent(Int.self, forKey: .tiles)) ?? 4)
        startLength = (try? c.decodeIfPresent(Int.self, forKey: .startLength)) ?? 3
        maxLength = (try? c.decodeIfPresent(Int.self, forKey: .maxLength)) ?? 20
        memory = (try? c.decodeIfPresent(SequenceRound.self, forKey: .round)) ?? nil
    }

    var isHost: Bool { !meId.isEmpty && meId == hostId }
    var me: GamePlayer? { players.first { $0.id == meId } }
    var host: GamePlayer? { players.first { $0.id == hostId } }
    /// Everyone still in: joined players, host included.
    var playing: [GamePlayer] { players.filter(\.joined) }
    var solo: Bool { players.count <= 1 }
    /// Everyone else still in — Wordle's strip of other players.
    var others: [GamePlayer] { playing.filter { $0.id != meId } }
    var kind: GameKind? { GameKind(rawValue: game) }

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

/// `POST /api/native/games`. Nil fields are left out of the JSON.
struct CreateGameBody: Encodable, Equatable {
    var game: String = "tap-duel"
    let difficulty: String
    let invite: [String]
    /// Quiz Night: what about (nil = jkai picks), and who for.
    var topic: String? = nil
    var audience: String? = nil
}

/// `POST /api/native/games/<id>`. Nil fields are left out of the JSON.
struct GameActionBody: Encodable {
    let action: String
    var round: Int? = nil
    var reactionMs: Int? = nil
    var early: Bool? = nil
    /// Wordle Race: `{action:"guess", word}`.
    var word: String? = nil
    /// Quiz Night: `{action:"answer", question:<index>, choice:0-3}`.
    var question: Int? = nil
    var choice: Int? = nil
    /// Quick Maths Sprint: `{action:"answer", index:<my current>, value:<int>}`.
    var index: Int? = nil
    var value: Int? = nil
    /// Sequence Memory: `{action:"attempt", round, taps:[tile,…]}`.
    var taps: [Int]? = nil
}

enum GameNames {
    static func title(_ game: String) -> String {
        GameKind(rawValue: game)?.title ?? game.replacingOccurrences(of: "-", with: " ").capitalized
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
