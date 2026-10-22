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
    /// GCSE: the spec heading it tested, once revealed.
    let topic: String?
    let picks: [QuizPick]

    private enum CodingKeys: String, CodingKey { case index, prompt, options, startsAt, answeredIds, myChoice, answerIndex, explain, topic, picks }

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
        topic = QuizText.clean((try? c.decodeIfPresent(String.self, forKey: .topic)) ?? nil)
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
    var mode: QuizMode = .general
    /// GCSE only.
    var subject: GcseSubject? = nil
    var board: GcseBoard = .any

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

    /// A GCSE quiz with no subject cannot be asked for: Start says so first.
    var complete: Bool { mode == .general || subject != nil }

    func createBody(invite: [String]) -> CreateGameBody {
        var body = CreateGameBody(
            game: GameKind.quizNight.rawValue,
            difficulty: difficulty.rawValue,
            invite: invite,
            topic: Self.clean(topic: topic),
            audience: audience.rawValue
        )
        if mode == .gcse, let subject {
            // The server pitches a GCSE quiz at the exam; no audience to send.
            body.audience = nil
            body.mode = QuizMode.gcse.rawValue
            body.subject = subject.id
            body.board = board.rawValue
        }
        return body
    }

    /// The settings a quiz room was made with. The host's TOPIC, not the
    /// title jkai wrote to: a quiz where jkai picked should pick afresh.
    init(room: GameRoom) {
        difficulty = GameDifficulty(rawValue: room.difficulty) ?? .easy
        topic = room.topic
        audience = QuizAudience.from(room.audience)
        if let gcse = room.quizGcse, let subject = GcseSubject.find(gcse.subject) {
            mode = .gcse
            self.subject = subject
            board = GcseBoard(rawValue: gcse.board) ?? .any
        }
    }

    init(difficulty: GameDifficulty, topic: String?, audience: QuizAudience,
         mode: QuizMode = .general, subject: GcseSubject? = nil, board: GcseBoard = .any) {
        self.difficulty = difficulty
        self.topic = topic
        self.audience = audience
        self.mode = mode
        self.subject = subject
        self.board = board
    }
}

/// Any topic for an audience, or exam-style revision on one GCSE subject.
enum QuizMode: String, CaseIterable, Identifiable {
    case general, gcse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "Any topic"
        case .gcse: return "GCSE revision"
        }
    }
}

enum GcseBoard: String, CaseIterable, Identifiable {
    case aqa, edexcel, ocr, eduqas, any

    var id: String { rawValue }

    var label: String {
        switch self {
        case .aqa: return "AQA"
        case .edexcel: return "Edexcel"
        case .ocr: return "OCR"
        case .eduqas: return "Eduqas"
        case .any: return "Any"
        }
    }
}

/// A GCSE subject the server knows (SR-Main `src/lib/games/gcse.ts`): the ids
/// must match it, or Start is refused. The topics are the spec's headings,
/// offered as one-tap suggestions; any other topic can still be typed.
struct GcseSubject: Identifiable, Equatable, Hashable {
    let id: String
    let label: String
    /// Foundation and Higher papers exist.
    let tiered: Bool
    let topics: [String]

    static func find(_ id: String?) -> GcseSubject? { all.first { $0.id == id } }

    static let all: [GcseSubject] = [
        GcseSubject(id: "maths", label: "Maths", tiered: true, topics: [
            "Number", "Algebra", "Ratio, proportion and rates of change", "Geometry and measures", "Probability", "Statistics",
        ]),
        GcseSubject(id: "biology", label: "Biology", tiered: true, topics: [
            "Cell biology", "Organisation", "Infection and response", "Bioenergetics", "Homeostasis and response",
            "Inheritance, variation and evolution", "Ecology",
        ]),
        GcseSubject(id: "chemistry", label: "Chemistry", tiered: true, topics: [
            "Atomic structure and the periodic table", "Bonding, structure and properties of matter", "Quantitative chemistry",
            "Chemical changes", "Energy changes", "Rates and equilibrium", "Organic chemistry", "Chemical analysis",
            "Chemistry of the atmosphere", "Using resources",
        ]),
        GcseSubject(id: "physics", label: "Physics", tiered: true, topics: [
            "Energy", "Electricity", "Particle model of matter", "Atomic structure", "Forces", "Waves",
            "Magnetism and electromagnetism", "Space physics",
        ]),
        GcseSubject(id: "combined-science", label: "Combined Science", tiered: true, topics: [
            "Biology: cells and organisation", "Biology: infection, homeostasis and inheritance", "Biology: ecology",
            "Chemistry: atoms, bonding and quantities", "Chemistry: reactions, energy and rates",
            "Chemistry: organic, analysis and the atmosphere", "Physics: energy and electricity",
            "Physics: particles, atoms and forces", "Physics: waves and magnetism",
        ]),
        GcseSubject(id: "english-literature", label: "English Literature", tiered: false, topics: [
            "Macbeth", "Romeo and Juliet", "A Christmas Carol", "The Strange Case of Dr Jekyll and Mr Hyde",
            "An Inspector Calls", "Blood Brothers", "Power and Conflict poetry", "Love and Relationships poetry",
            "Unseen poetry techniques",
        ]),
        GcseSubject(id: "english-language", label: "English Language", tiered: false, topics: [
            "Language techniques", "Structure and form", "Persuasive and rhetorical devices", "Sentence types and punctuation",
            "Word classes and grammar", "Spelling and commonly confused words",
        ]),
        GcseSubject(id: "history", label: "History", tiered: false, topics: [
            "Germany 1890–1945: Democracy and dictatorship", "America 1920–1973: Opportunity and inequality",
            "Conflict and tension 1918–1939", "Conflict and tension between East and West 1945–1972",
            "Health and the people c1000 to the present", "Medicine in Britain c1250 to the present",
            "Elizabethan England c1568–1603", "Norman England c1066–c1100", "Power and the people c1170 to the present",
        ]),
        GcseSubject(id: "geography", label: "Geography", tiered: false, topics: [
            "Natural hazards", "The living world", "Physical landscapes in the UK", "Urban issues and challenges",
            "The changing economic world", "The challenge of resource management", "Geographical skills",
        ]),
        GcseSubject(id: "computer-science", label: "Computer Science", tiered: false, topics: [
            "Algorithms", "Programming", "Data representation", "Computer systems", "Networks", "Cyber security",
            "Boolean logic", "Ethical, legal and environmental impacts",
        ]),
        GcseSubject(id: "religious-studies", label: "Religious Studies", tiered: false, topics: [
            "Christianity: beliefs and practices", "Islam: beliefs and practices", "Buddhism: beliefs and practices",
            "Relationships and families", "Religion and life", "Religion, peace and conflict", "Religion, crime and punishment",
        ]),
        GcseSubject(id: "french", label: "French", tiered: true, topics: languageTopics),
        GcseSubject(id: "spanish", label: "Spanish", tiered: true, topics: languageTopics),
        GcseSubject(id: "german", label: "German", tiered: true, topics: languageTopics),
        GcseSubject(id: "business", label: "Business", tiered: false, topics: [
            "Business in the real world", "Influences on business", "Business operations", "Human resources",
            "Marketing", "Finance",
        ]),
    ]

    private static let languageTopics = [
        "Vocabulary", "Verbs and tenses", "Grammar", "Reading comprehension", "Translation into English",
    ]
}

/// What a GCSE difficulty means: the same three buttons, read as grade bands.
enum GcseBand {
    static func label(_ level: GameDifficulty) -> String {
        switch level {
        case .easy: return "Grades 1–3"
        case .medium: return "Grades 4–5"
        case .hard: return "Grades 6–9"
        }
    }

    /// The line under each difficulty in the new-game sheet.
    static func line(_ level: GameDifficulty, tiered: Bool) -> String {
        switch (level, tiered) {
        case (.easy, true): return "Foundation tier: the opening questions of the paper. 25–45 s a question."
        case (.medium, true): return "The crossover questions on both Foundation and Higher. 30–60 s a question."
        case (.hard, true): return "Higher tier: the questions that sort the 7s from the 9s. 35–75 s a question."
        case (.easy, false): return "Core knowledge for a pass: key facts and terms. 25–45 s a question."
        case (.medium, false): return "Secure knowledge: explaining why, choosing the precise term. 30–60 s a question."
        case (.hard, false): return "Top-band detail: exact quotations, dates and causes. 35–75 s a question."
        }
    }
}

/// What a GCSE room says about itself (`gcse` on the wire).
struct QuizGcse: Decodable, Equatable {
    let subject: String
    let subjectLabel: String
    let board: String
    /// Nil for any board.
    let boardLabel: String?
    /// "Grades 4–5".
    let band: String
    /// "Foundation", "Higher", "Foundation and Higher"; nil for an untiered subject.
    let tier: String?

    private enum CodingKeys: String, CodingKey { case subject, subjectLabel, board, boardLabel, band, tier }

    init(subject: String, subjectLabel: String, board: String, boardLabel: String?, band: String, tier: String?) {
        self.subject = subject; self.subjectLabel = subjectLabel; self.board = board
        self.boardLabel = boardLabel; self.band = band; self.tier = tier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subject = try c.decode(String.self, forKey: .subject)
        subjectLabel = (try? c.decodeIfPresent(String.self, forKey: .subjectLabel)) ?? subject
        board = (try? c.decodeIfPresent(String.self, forKey: .board)) ?? "any"
        boardLabel = QuizText.clean((try? c.decodeIfPresent(String.self, forKey: .boardLabel)) ?? nil)
        band = (try? c.decodeIfPresent(String.self, forKey: .band)) ?? ""
        tier = QuizText.clean((try? c.decodeIfPresent(String.self, forKey: .tier)) ?? nil)
    }

    /// "GCSE Biology · AQA · Grades 4–5".
    var line: String {
        ["GCSE \(subjectLabel)", boardLabel, band].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// One question again, once the game is over (`review` on a finished room).
struct QuizReviewItem: Decodable, Equatable, Identifiable {
    let index: Int
    let prompt: String
    let options: [String]
    let answerIndex: Int
    let explain: String?
    let topic: String?
    /// What I picked; nil if I did not answer.
    let myChoice: Int?
    let rightCount: Int
    let playerCount: Int

    var id: Int { index }
    var gotIt: Bool { myChoice == answerIndex }
    var answer: String { options.indices.contains(answerIndex) ? options[answerIndex] : "" }

    private enum CodingKeys: String, CodingKey { case index, prompt, options, answerIndex, explain, topic, myChoice, rightCount, playerCount }

    init(index: Int, prompt: String, options: [String], answerIndex: Int, explain: String?, topic: String?,
         myChoice: Int?, rightCount: Int, playerCount: Int) {
        self.index = index; self.prompt = prompt; self.options = options; self.answerIndex = answerIndex
        self.explain = explain; self.topic = topic; self.myChoice = myChoice
        self.rightCount = rightCount; self.playerCount = playerCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decode(Int.self, forKey: .index)
        prompt = (try? c.decodeIfPresent(String.self, forKey: .prompt)) ?? ""
        options = (try? c.decodeIfPresent([String].self, forKey: .options)) ?? []
        answerIndex = (try? c.decodeIfPresent(Int.self, forKey: .answerIndex)) ?? 0
        explain = QuizText.clean((try? c.decodeIfPresent(String.self, forKey: .explain)) ?? nil)
        topic = QuizText.clean((try? c.decodeIfPresent(String.self, forKey: .topic)) ?? nil)
        myChoice = (try? c.decodeIfPresent(Int.self, forKey: .myChoice)) ?? nil
        rightCount = (try? c.decodeIfPresent(Int.self, forKey: .rightCount)) ?? 0
        playerCount = (try? c.decodeIfPresent(Int.self, forKey: .playerCount)) ?? 0
    }
}

enum QuizText {
    /// Trimmed, or nil when blank.
    static func clean(_ raw: String?) -> String? {
        let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t?.isEmpty ?? true) ? nil : t
    }
}

/// The review, sorted for revision: what I missed first, then the rest, each
/// in the order asked; and the spec headings I missed most, for "revise next".
enum QuizReview {
    static func ordered(_ items: [QuizReviewItem]) -> [QuizReviewItem] {
        items.filter { !$0.gotIt } + items.filter(\.gotIt)
    }

    /// Topics of the questions I missed, most-missed first, ties in first-seen order.
    static func reviseNext(_ items: [QuizReviewItem]) -> [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for item in items where !item.gotIt {
            guard let topic = item.topic else { continue }
            if counts[topic] == nil { order.append(topic) }
            counts[topic, default: 0] += 1
        }
        return order.enumerated()
            .sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }
            .map(\.element)
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

    /// "The Solar System · for kids", or "GCSE Biology · AQA · Grades 4–5" —
    /// what the quiz is, from the room.
    static func about(_ room: GameRoom) -> String {
        if let gcse = room.quizGcse { return gcse.line }
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
