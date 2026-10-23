import Foundation
import SwiftUI

// Odd Artist Out's wire pieces and the rules the phone applies itself — which
// ink is whose, whether it is my turn to draw, what a vote or a lift posts,
// the sentences of a reveal, the host's options — as pure values, so each is a
// unit test. The picture is Draw & Guess's (`DrawGuessCanvas`, the same stroke
// ops); the server judges the vote and the guess and keeps the score.
//
// Hidden information stays on the server: this phone is only ever sent the
// word if it is an artist's, and who the fake is only if it is the fake's own
// or the vote has caught them. Nothing here works either out.

/// Where a Odd Artist Out room is. Its own enum, not `GamePhase`: `reading`,
/// `drawing`, `voting` and `guessing` are this game's alone.
enum FakeArtistPhase: String, Equatable {
    case lobby, countdown, reading, drawing, voting, guessing, reveal, finished, closed, unknown

    static func from(_ raw: String?) -> FakeArtistPhase {
        raw.flatMap(FakeArtistPhase.init(rawValue:)) ?? .unknown
    }

    /// A round is being played (the picture and the card are up).
    var inRound: Bool { [.reading, .drawing, .voting, .guessing, .reveal].contains(self) }
}

/// How a round ended.
enum FakeArtistOutcome: String, Equatable {
    /// Nobody had more votes than everyone else alone.
    case escaped
    /// Caught, and named the word.
    case guessed
    /// Caught, and missed it.
    case caught
    /// The fake left mid-round.
    case fakeLeft = "fake-left"
    case unknown

    static func from(_ raw: String?) -> FakeArtistOutcome? {
        guard let raw else { return nil }
        return FakeArtistOutcome(rawValue: raw) ?? .unknown
    }

    var fakeWins: Bool { self == .escaped || self == .guessed }
}

/// The round in play, as this phone is allowed to see it.
struct FakeArtistRound: Decodable, Equatable {
    let number: Int
    let category: String
    /// artist | fake | watching.
    let role: String
    /// Mine as an artist; everyone's at the reveal. Nil for the fake.
    let word: String?
    /// Only the fake's own, the caught fake's, or at the reveal.
    let fakeId: String?
    /// Player ids in drawing order, both laps.
    let turns: [String]
    /// Position in `turns` while drawing.
    let turn: Int?
    let artistId: String?
    let turnStartedAt: Double?
    let skipped: [Int]
    /// Who has voted (never for whom, until the reveal).
    let voted: [String]
    let myVote: String?
    /// Voter → choice, at the reveal.
    let votes: [String: String]?
    let counts: [String: Int]?
    let accusedId: String?
    let guess: String?
    let outcome: FakeArtistOutcome?
    let awarded: [String: Int]?

    var isFake: Bool { role == "fake" }
    var isArtist: Bool { role == "artist" }

    private enum CodingKeys: String, CodingKey {
        case number, category, role, word, fakeId, turns, turn, artistId, turnStartedAt, skipped
        case voted, myVote, votes, counts, accusedId, guess, outcome, awarded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = max(1, (try? c.decodeIfPresent(Int.self, forKey: .number)) ?? 1)
        category = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? ""
        role = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? "watching"
        word = (try? c.decodeIfPresent(String.self, forKey: .word)) ?? nil
        fakeId = (try? c.decodeIfPresent(String.self, forKey: .fakeId)) ?? nil
        turns = (try? c.decodeIfPresent([String].self, forKey: .turns)) ?? []
        turn = (try? c.decodeIfPresent(Int.self, forKey: .turn)) ?? nil
        artistId = (try? c.decodeIfPresent(String.self, forKey: .artistId)) ?? nil
        turnStartedAt = (try? c.decodeIfPresent(Double.self, forKey: .turnStartedAt)) ?? nil
        skipped = (try? c.decodeIfPresent([Int].self, forKey: .skipped)) ?? []
        voted = (try? c.decodeIfPresent([String].self, forKey: .voted)) ?? []
        myVote = (try? c.decodeIfPresent(String.self, forKey: .myVote)) ?? nil
        votes = (try? c.decodeIfPresent([String: String].self, forKey: .votes)) ?? nil
        counts = (try? c.decodeIfPresent([String: Int].self, forKey: .counts)) ?? nil
        accusedId = (try? c.decodeIfPresent(String.self, forKey: .accusedId)) ?? nil
        guess = (try? c.decodeIfPresent(String.self, forKey: .guess)) ?? nil
        outcome = FakeArtistOutcome.from((try? c.decodeIfPresent(String.self, forKey: .outcome)) ?? nil)
        awarded = (try? c.decodeIfPresent([String: Int].self, forKey: .awarded)) ?? nil
    }
}

/// A round already revealed.
struct FakeArtistPastRound: Decodable, Equatable, Identifiable {
    let number: Int
    let category: String
    let word: String
    let fakeId: String
    let outcome: FakeArtistOutcome

    var id: Int { number }

    private enum CodingKeys: String, CodingKey { case number, category, word, fakeId, outcome }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = (try? c.decodeIfPresent(Int.self, forKey: .number)) ?? 0
        category = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? ""
        word = (try? c.decodeIfPresent(String.self, forKey: .word)) ?? ""
        fakeId = (try? c.decodeIfPresent(String.self, forKey: .fakeId)) ?? ""
        outcome = FakeArtistOutcome.from((try? c.decodeIfPresent(String.self, forKey: .outcome)) ?? nil) ?? .unknown
    }
}

/// A player's Odd Artist Out flags (the rest is `GamePlayer`).
struct FakeArtistSeat: Decodable, Equatable {
    let id: String
    /// A palette name; nil before the start.
    let color: String?
    let isDrawing: Bool

    private enum CodingKeys: String, CodingKey { case id, color, isDrawing }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? nil
        isDrawing = (try? c.decodeIfPresent(Bool.self, forKey: .isDrawing)) ?? false
    }
}

/// The finished table's extras beside `GameStanding`'s score.
struct FakeArtistStanding: Decodable, Equatable {
    let id: String
    let timesFake: Int
    let winsAsFake: Int

    private enum CodingKeys: String, CodingKey { case id, timesFake, winsAsFake }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        timesFake = (try? c.decodeIfPresent(Int.self, forKey: .timesFake)) ?? 0
        winsAsFake = (try? c.decodeIfPresent(Int.self, forKey: .winsAsFake)) ?? 0
    }
}

/// Everything Odd Artist Out adds to a room, read from the same JSON as
/// `GameRoom` (`GameRoom.fakeArtist`).
struct FakeArtistState: Decodable, Equatable {
    let phase: FakeArtistPhase
    let laps: Int
    let turnMs: Double
    let readMs: Double
    let voteMs: Double
    let guessMs: Double
    let revealMs: Double
    let current: FakeArtistRound?
    let history: [FakeArtistPastRound]
    let drawing: DrawGuessDrawingWire?
    let palette: [String]
    let seats: [FakeArtistSeat]
    let extras: [FakeArtistStanding]

    private enum CodingKeys: String, CodingKey {
        case phase, laps, turnMs, readMs, voteMs, guessMs, revealMs, current, history, drawing, palette, players, standings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = FakeArtistPhase.from((try? c.decodeIfPresent(String.self, forKey: .phase)) ?? nil)
        laps = max(1, (try? c.decodeIfPresent(Int.self, forKey: .laps)) ?? 2)
        turnMs = (try? c.decodeIfPresent(Double.self, forKey: .turnMs)) ?? 20_000
        readMs = (try? c.decodeIfPresent(Double.self, forKey: .readMs)) ?? 8_000
        voteMs = (try? c.decodeIfPresent(Double.self, forKey: .voteMs)) ?? 60_000
        guessMs = (try? c.decodeIfPresent(Double.self, forKey: .guessMs)) ?? 30_000
        revealMs = (try? c.decodeIfPresent(Double.self, forKey: .revealMs)) ?? 10_000
        current = (try? c.decodeIfPresent(FakeArtistRound.self, forKey: .current)) ?? nil
        history = (try? c.decodeIfPresent([FakeArtistPastRound].self, forKey: .history)) ?? []
        drawing = (try? c.decodeIfPresent(DrawGuessDrawingWire.self, forKey: .drawing)) ?? nil
        let palette = ((try? c.decodeIfPresent([String].self, forKey: .palette)) ?? nil) ?? []
        self.palette = palette.isEmpty ? FakeArtistInk.palette : palette
        seats = (try? c.decodeIfPresent([FakeArtistSeat].self, forKey: .players)) ?? []
        extras = ((try? c.decodeIfPresent([FakeArtistStanding].self, forKey: .standings)) ?? nil) ?? []
    }

    func seat(_ id: String) -> FakeArtistSeat? { seats.first { $0.id == id } }
    func extra(_ id: String) -> FakeArtistStanding? { extras.first { $0.id == id } }

    /// The phase's whole length, for the time bar.
    var phaseLength: Double? {
        switch phase {
        case .reading: return readMs
        case .drawing: return turnMs
        case .voting: return voteMs
        case .guessing: return guessMs
        case .reveal: return revealMs
        default: return nil
        }
    }

    /// It is my turn to draw.
    func myTurn(_ meId: String) -> Bool {
        phase == .drawing && !meId.isEmpty && current?.artistId == meId
    }

    /// The line id the server gives the turn in hand: its index, from 1.
    var lineId: Int? { current?.turn.map { $0 + 1 } }

    /// Whom I may vote for: everyone dealt in and still playing, but me.
    func candidates(in room: GameRoom) -> [GamePlayer] {
        let dealt = Set(current?.turns ?? [])
        return room.playing.filter { $0.id != room.meId && dealt.contains($0.id) }
    }
}

// MARK: - Ink

/// Each seat's colour. The canvas is the light paper Draw & Guess uses, in
/// both themes, so every ink reads on it.
enum FakeArtistInk {
    static let palette = ["red", "blue", "green", "orange", "purple", "brown", "pink", "teal", "black", "gold"]
    /// Every line is the same pen.
    static let width = 14

    static func color(_ name: String?) -> Color {
        switch name {
        case "red": return Color(hex: 0xC8372D)
        case "blue": return Color(hex: 0x2F5FA8)
        case "green": return Color(hex: 0x2E8540)
        case "orange": return Color(hex: 0xE07A1F)
        case "purple": return Color(hex: 0x6B4A9B)
        case "brown": return Color(hex: 0x7A4A22)
        case "pink": return Color(hex: 0xD6478A)
        case "teal": return Color(hex: 0x16857F)
        case "black": return Color(hex: 0x1F1B16)
        case "gold": return Color(hex: 0xC99A1A)
        default: return Color(hex: 0x1F1B16)
        }
    }
}

// MARK: - Posts

enum FakeArtistPosts {
    /// The server's cap on one turn's line (`MAX_LINE_POINTS` in fake-artist.ts).
    static let maxLinePoints = 1500
    /// Times a lift that failed on the network is sent again, bare.
    static let liftRetries = 2

    /// The pen's posts trimmed so the line holds at most `maxLinePoints`, given
    /// `sent` points already queued this turn. `full` means the line is at the
    /// cap and the finger should lift (the server lifts it there too).
    static func capped(_ posts: [DrawGuessStrokePost], sent: Int) -> (posts: [DrawGuessStrokePost], sent: Int, full: Bool) {
        var out: [DrawGuessStrokePost] = []
        var total = max(0, sent)
        for post in posts {
            let space = maxLinePoints - total
            guard space > 0 else { break }
            let points = Array(post.points.prefix(space))
            guard !points.isEmpty else { continue }
            out.append(DrawGuessStrokePost(id: post.id, color: post.color, width: post.width, points: points))
            total += points.count
        }
        return (out, total, total >= maxLinePoints)
    }

    /// A bare lift: what is sent again when the lift itself failed to arrive.
    static func bareLift() -> GameActionBody {
        var body = GameActionBody(action: "stroke")
        body.end = true
        return body
    }

    /// The pen's posts for one turn's line with the last marked as the lift.
    /// No points left to send is a bare lift, for a line already streamed.
    static func lift(_ posts: [DrawGuessStrokePost]) -> [GameActionBody] {
        var bodies = posts.map(\.body)
        if bodies.isEmpty { return [bareLift()] }
        bodies[bodies.count - 1].end = true
        return bodies
    }

    static func vote(_ playerId: String) -> GameActionBody {
        var body = GameActionBody(action: "vote")
        body.playerId = playerId
        return body
    }

    static func guess(_ text: String) -> GameActionBody? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return nil }
        var body = GameActionBody(action: "guess")
        body.text = trimmed
        return body
    }
}

// MARK: - The game the host picks

struct FakeArtistSettings: Equatable {
    static let roundChoices = [3, 5]
    static let minPlayers = 4
    static let maxPlayers = 10

    var difficulty: GameDifficulty
    var rounds: Int = 3

    func createBody(invite: [String]) -> CreateGameBody {
        var body = CreateGameBody(game: GameKind.fakeArtist.rawValue, difficulty: difficulty.rawValue, invite: invite)
        body.rounds = rounds
        return body
    }

    /// "3 rounds".
    static func roundsLabel(_ n: Int) -> String { "\(n) rounds" }

    /// "3 rounds · 20 s a line", for the lobby.
    static func about(_ room: GameRoom) -> String {
        let seconds = Int(((room.fakeArtist?.turnMs ?? 20_000) / 1000).rounded())
        return "\(roundsLabel(room.rounds)) · \(seconds) s a line"
    }

    /// Why Start waits, or nil when it need not.
    static func startBlock(joined: Int) -> String? {
        joined < minPlayers ? "Needs four players at least — ask \(minPlayers - joined) more in." : nil
    }
}

// MARK: - What the screen says

enum FakeArtistText {
    /// The reveal's headline.
    static func outcome(_ outcome: FakeArtistOutcome?, fake: String, meIsFake: Bool) -> String {
        let who = meIsFake ? "You" : fake
        switch outcome {
        case .escaped?: return "\(who) got away with it!"
        case .guessed?: return meIsFake ? "Caught — but you named the word!" : "\(fake) was caught — but named the word!"
        case .caught?: return meIsFake ? "Caught! The artists win." : "Caught! \(fake) was the fake."
        case .fakeLeft?: return "\(fake) was the fake, and left."
        default: return "The round is over."
        }
    }

    /// "Turn 3 of 10".
    static func turnLabel(_ round: FakeArtistRound?) -> String? {
        guard let round, let turn = round.turn, !round.turns.isEmpty else { return nil }
        return "Turn \(turn + 1) of \(round.turns.count)"
    }

    /// What I am told on the card: the word, or the bad news.
    static func card(_ round: FakeArtistRound?) -> (kicker: String, title: String) {
        guard let round else { return ("", "") }
        // The word reaches the fake only at the reveal.
        if round.isFake, let word = round.word { return ("You were the fake. The word was", word) }
        if round.isFake { return ("You're the fake", "Blend in") }
        if let word = round.word { return ("The word is", word) }
        return ("Watching", "Only the artists know")
    }

    /// The vote's state for the table, without ever saying who chose whom.
    static func votedLine(voted: Int, of total: Int) -> String {
        "\(voted) of \(total) voted"
    }
}
