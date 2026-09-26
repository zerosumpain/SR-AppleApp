import Foundation

// jkai Quiz Night's wire pieces and the rules the phone applies itself, as
// pure values — so the play-again request and "one answer per question" are
// unit tests, not something only a family round the table can check.
//
// The server marks everything: a right answer is 500 plus up to 500 for speed
// (timed on the server's clock from when the question opened), a wrong one 0,
// and scores move only at the reveal. The phone never decides who was right.

/// Where the questions are: jkai writes them once, while the lobby fills.
enum QuizPrep: String, Decodable, Equatable {
    case writing, ready, failed

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // An unknown state is treated as ready: the server refuses Start if it
        // is not, with a sentence, which beats a lobby wedged on a word.
        self = QuizPrep(rawValue: raw) ?? .ready
    }
}

/// One player's answer, shown at the reveal.
struct QuizPick: Decodable, Equatable {
    let playerId: String
    let choice: Int
    let points: Int
    let ms: Int?

    private enum CodingKeys: String, CodingKey { case playerId, choice, points, ms }

    init(playerId: String, choice: Int, points: Int, ms: Int?) {
        self.playerId = playerId; self.choice = choice; self.points = points; self.ms = ms
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(String.self, forKey: .playerId)
        choice = try c.decode(Int.self, forKey: .choice)
        points = (try? c.decodeIfPresent(Int.self, forKey: .points)) ?? 0
        ms = ((try? c.decodeIfPresent(Double.self, forKey: .ms)) ?? nil).map { Int($0.rounded()) }
    }

    var right: Bool { points > 0 }
}

/// The question on screen. While it is open the room says WHO has answered,
/// never what; `answerIndex`, `explain` and `picks` arrive with the reveal.
struct QuizQuestion: Decodable, Equatable {
    /// 0-based.
    let index: Int
    let prompt: String
    let options: [String]
    let startsAt: Double?
    let answeredIds: [String]
    /// What I picked, once the server has it.
    let myChoice: Int?
    let answerIndex: Int?
    let explain: String?
    let picks: [QuizPick]

    private enum CodingKeys: String, CodingKey { case index, prompt, options, startsAt, answeredIds, myChoice, answerIndex, explain, picks }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decode(Int.self, forKey: .index)
        prompt = (try? c.decodeIfPresent(String.self, forKey: .prompt)) ?? ""
        options = (try? c.decodeIfPresent([String].self, forKey: .options)) ?? []
        startsAt = (try? c.decodeIfPresent(Double.self, forKey: .startsAt)) ?? nil
        answeredIds = (try? c.decodeIfPresent([String].self, forKey: .answeredIds)) ?? []
        myChoice = (try? c.decodeIfPresent(Int.self, forKey: .myChoice)) ?? nil
        answerIndex = (try? c.decodeIfPresent(Int.self, forKey: .answerIndex)) ?? nil
        let note = ((try? c.decodeIfPresent(String.self, forKey: .explain)) ?? nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        explain = (note?.isEmpty ?? true) ? nil : note
        picks = (try? c.decodeIfPresent([QuizPick].self, forKey: .picks)) ?? []
    }

    func pick(of playerId: String) -> QuizPick? { picks.first { $0.playerId == playerId } }

    /// Everyone who chose option `choice`, in the order they are listed.
    func pickers(of choice: Int) -> [String] { picks.filter { $0.choice == choice }.map(\.playerId) }
}

/// Who the questions are written for.
enum QuizAudience: String, CaseIterable, Identifiable {
    case kids, family, adults

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kids: return "Kids"
        case .family: return "Family"
        case .adults: return "Adults"
        }
    }

    var line: String {
        switch self {
        case .kids: return "Ages about 7 to 11."
        case .family: return "Everyone at the table, young and old."
        case .adults: return "Harder facts, grown-up general knowledge."
        }
    }

    /// "for kids" — the room's own phrase, for a room that has not said `about`.
    var phrase: String {
        switch self {
        case .kids: return "for kids"
        case .family: return "for the family"
        case .adults: return "for adults"
        }
    }

    static func from(_ raw: String?) -> QuizAudience {
        raw.flatMap(QuizAudience.init(rawValue:)) ?? .family
    }
}

/// What the host picked for a quiz: the new-game sheet's answers, and the
/// same settings read back off a finished room for "Play again".
struct QuizNightSettings: Equatable {
    static let topicLimit = 60

    var difficulty: GameDifficulty
    /// Nil or blank: jkai picks.
    var topic: String?
    var audience: QuizAudience

    /// The topic as it will be sent: one line, trimmed, at most 60 characters,
    /// nil when blank. The server cleans it too; this keeps the counter honest.
    static func clean(topic raw: String?) -> String? {
        guard let raw else { return nil }
        let line = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let capped = String(line.prefix(topicLimit)).trimmingCharacters(in: .whitespaces)
        return capped.isEmpty ? nil : capped
    }

    /// A typed topic cut to the limit, as the text field shows it.
    static func limit(_ typed: String) -> String {
        typed.count > topicLimit ? String(typed.prefix(topicLimit)) : typed
    }

    func createBody(invite: [String]) -> CreateGameBody {
        CreateGameBody(
            game: GameKind.quizNight.rawValue,
            difficulty: difficulty.rawValue,
            invite: invite,
            topic: Self.clean(topic: topic),
            audience: audience.rawValue
        )
    }

    /// The settings a quiz room was made with. The host's TOPIC, not the
    /// title jkai wrote to: a quiz where jkai picked should pick afresh.
    init(room: GameRoom) {
        difficulty = GameDifficulty(rawValue: room.difficulty) ?? .easy
        topic = room.topic
        audience = QuizAudience.from(room.audience)
    }

    init(difficulty: GameDifficulty, topic: String?, audience: QuizAudience) {
        self.difficulty = difficulty
        self.topic = topic
        self.audience = audience
    }
}

enum QuizNight {
    /// "Play again" is a NEW quiz — the server answers `again` with 409, since
    /// the same questions twice would be a memory test. Same settings, and the
    /// same people: everyone who played, bar me. A lobby whose questions could
    /// not be written also takes back anyone still invited.
    static func playAgain(from room: GameRoom) -> CreateGameBody {
        let people: [GamePlayer]
        if room.phase == .lobby {
            people = room.players.filter { $0.status == "joined" || $0.status == "invited" }
        } else {
            people = room.playing
        }
        let invite = people.map(\.id).filter { $0 != room.meId }
        return QuizNightSettings(room: room).createBody(invite: invite)
    }

    /// "The Solar System · for kids" — what the quiz is, from the room.
    static func about(_ room: GameRoom) -> String {
        let topic = room.title ?? room.topic ?? "jkai picks the topic"
        return "\(topic) · \(QuizAudience.from(room.audience).phrase)"
    }

    /// "A", "B", "C", "D".
    static func letter(_ index: Int) -> String {
        let letters = ["A", "B", "C", "D", "E", "F"]
        return index >= 0 && index < letters.count ? letters[index] : "\(index + 1)"
    }

    /// The share of a question's time still left, 0…1.
    static func fractionLeft(endsAt end: Double, timeMs: Double, atServer now: Double) -> Double {
        guard timeMs > 0 else { return 0 }
        return min(1, max(0, (end - now) / timeMs))
    }

    /// "+870" or "0".
    static func points(_ value: Int) -> String { value > 0 ? "+\(value)" : "0" }
}

/// One answer per question. Locked the moment it is tapped — before the
/// server has it — so a second tap, or a tap on a question that has moved on,
/// never reaches the wire.
struct QuizAnswerLock: Equatable {
    /// question index → choice.
    private(set) var choices: [Int: Int] = [:]

    /// Claims the question's answer. False if one was already given.
    mutating func lock(question: Int, choice: Int) -> Bool {
        guard choices[question] == nil else { return false }
        choices[question] = choice
        return true
    }

    /// Hands a question back — the POST never arrived, so the player may try
    /// again.
    mutating func release(question: Int) {
        choices[question] = nil
    }

    func choice(for question: Int) -> Int? { choices[question] }

    /// What I picked for this question, the server's word first.
    func choice(for question: QuizQuestion) -> Int? {
        question.myChoice ?? choices[question.index]
    }

    /// True while an answer to this question could still be sent: it is open,
    /// I am playing, and neither the server nor this phone has one.
    func canAnswer(in room: GameRoom) -> Bool {
        guard room.phase == .question, let question = room.question, room.me?.joined == true else { return false }
        return choice(for: question) == nil
    }

    /// The body to POST: `{action:"answer", question, choice}`.
    static func body(question: Int, choice: Int) -> GameActionBody {
        GameActionBody(action: "answer", question: question, choice: choice)
    }
}
