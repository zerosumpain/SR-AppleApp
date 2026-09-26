import Foundation

// Quick Maths Sprint's wire pieces and the rules the phone applies itself —
// building an answer on the keypad, reading whether it was right from the
// room that comes back — as pure values, so each is a unit test. Answers
// never travel while the game runs; the server marks every one.

/// The problem in front of me. `text` is the server's own (` + `, ` − `,
/// ` × `, ` ÷ `) and is shown as it comes.
struct SprintProblem: Decodable, Equatable {
    let index: Int
    let text: String
}

/// My side of the race: `me` on the wire.
struct SprintMe: Decodable, Equatable {
    /// Nil before play, once the time is up, or once I have answered them all.
    let problem: SprintProblem?
    let score: Int
    let correct: Int
    let misses: Int
    let streak: Int
    let bestStreak: Int

    init(problem: SprintProblem?, score: Int = 0, correct: Int = 0, misses: Int = 0, streak: Int = 0, bestStreak: Int = 0) {
        self.problem = problem
        self.score = score; self.correct = correct; self.misses = misses
        self.streak = streak; self.bestStreak = bestStreak
    }

    private enum CodingKeys: String, CodingKey { case problem, score, correct, misses, streak, bestStreak }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        problem = (try? c.decodeIfPresent(SprintProblem.self, forKey: .problem)) ?? nil
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        correct = (try? c.decodeIfPresent(Int.self, forKey: .correct)) ?? 0
        misses = (try? c.decodeIfPresent(Int.self, forKey: .misses)) ?? 0
        streak = (try? c.decodeIfPresent(Int.self, forKey: .streak)) ?? 0
        bestStreak = (try? c.decodeIfPresent(Int.self, forKey: .bestStreak)) ?? 0
    }
}

/// One problem of a player's recap, at the finish, with its answer.
struct SprintRecapRow: Decodable, Equatable, Identifiable {
    let index: Int
    let text: String
    let answer: Int
    /// False for the one they were stuck on when time ran out.
    let solved: Bool
    let wrongTries: Int

    var id: Int { index }

    private enum CodingKeys: String, CodingKey { case index, text, answer, solved, wrongTries }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decode(Int.self, forKey: .index)
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        answer = (try? c.decodeIfPresent(Int.self, forKey: .answer)) ?? 0
        solved = (try? c.decodeIfPresent(Bool.self, forKey: .solved)) ?? false
        wrongTries = (try? c.decodeIfPresent(Int.self, forKey: .wrongTries)) ?? 0
    }
}

/// A player's last few problems.
struct SprintRecap: Decodable, Equatable, Identifiable {
    let playerId: String
    let problems: [SprintRecapRow]

    var id: String { playerId }

    private enum CodingKeys: String, CodingKey { case playerId, problems }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(String.self, forKey: .playerId)
        problems = (try? c.decodeIfPresent([SprintRecapRow].self, forKey: .problems)) ?? []
    }
}

/// The answer being typed on the keypad: digits, and a sign.
///
/// At most `maxDigits` digits, no leading zeros ("0" then "7" is "7"), and a
/// minus that toggles. Delete takes the last digit, then the sign. An answer
/// with no digits has no value and is never sent.
struct SprintInput: Equatable {
    static let maxDigits = 6

    private(set) var digits: String = ""
    private(set) var negative = false

    var isEmpty: Bool { digits.isEmpty && !negative }

    /// What the keypad shows: "−42", "−", "".
    var display: String { (negative ? "−" : "") + digits }

    /// The whole number to send, or nil with no digits yet.
    var value: Int? {
        guard !digits.isEmpty, let magnitude = Int(digits) else { return nil }
        return negative ? -magnitude : magnitude
    }

    /// A digit 0–9. False (nothing changes) for anything else or a full answer.
    @discardableResult
    mutating func press(_ digit: Int) -> Bool {
        guard (0...9).contains(digit) else { return false }
        if digits == "0" {
            // A leading zero is replaced, never extended.
            digits = String(digit)
            return true
        }
        guard digits.count < Self.maxDigits else { return false }
        digits += String(digit)
        return true
    }

    /// Flip the sign.
    mutating func toggleSign() { negative.toggle() }

    /// Removes the last digit, or the sign once the digits are gone.
    @discardableResult
    mutating func delete() -> Bool {
        if !digits.isEmpty {
            digits.removeLast()
            return true
        }
        if negative {
            negative = false
            return true
        }
        return false
    }

    mutating func clear() {
        digits = ""
        negative = false
    }
}

/// How an answer went, read from the room the server answered with — it never
/// says "right" or "wrong", but a right answer moves me on and a wrong one
/// counts a miss and leaves the same problem.
enum SprintVerdict: Equatable {
    case right
    case wrong
    /// Nothing in the room says (a stale frame, the time ran out).
    case unknown

    static func judge(sentIndex: Int, before: SprintMe?, after: SprintMe?) -> SprintVerdict {
        guard let after else { return .unknown }
        if after.correct > sentIndex || (after.problem.map { $0.index > sentIndex } ?? false) { return .right }
        if after.problem?.index == sentIndex, after.misses > (before?.misses ?? 0) { return .wrong }
        return .unknown
    }
}

enum MathsSprint {
    /// The streak cue: a streak that has just reached a multiple of the bonus.
    static func onBonus(streak: Int, every: Int) -> Bool {
        every > 0 && streak > 0 && streak % every == 0
    }

    /// Right answers still wanted for the next bonus.
    static func toBonus(streak: Int, every: Int) -> Int {
        guard every > 0 else { return 0 }
        return every - (streak % every)
    }

    /// The body to POST: `{action:"answer", index, value}`.
    static func body(index: Int, value: Int) -> GameActionBody {
        GameActionBody(action: "answer", index: index, value: value)
    }
}

/// What VoiceOver says for a problem: the symbols, read as words.
enum SprintSpeech {
    static func problem(_ text: String) -> String {
        text.replacingOccurrences(of: " − ", with: " minus ")
            .replacingOccurrences(of: " × ", with: " times ")
            .replacingOccurrences(of: " ÷ ", with: " divided by ")
            .replacingOccurrences(of: " + ", with: " plus ")
    }
}
