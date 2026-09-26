import Foundation

// Wordle Race's wire values and the rules the phone applies itself — typing,
// the keyboard's colours, the clock — as pure values, so each is a unit test.
// The server judges every guess; nothing here decides a mark.

/// One letter's verdict. `unknown` is a mark this version of the app has not
/// heard of: drawn blank, never a thrown decode.
enum WordleMark: String, Decodable, Equatable {
    case correct, present, absent, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WordleMark(rawValue: raw) ?? .unknown
    }

    /// Which verdict wins when one letter has several: a letter in place beats
    /// a letter elsewhere beats a letter not there.
    var rank: Int {
        switch self {
        case .correct: return 3
        case .present: return 2
        case .absent: return 1
        case .unknown: return 0
        }
    }

    /// Spoken, for VoiceOver — colour is never the only carrier.
    var spoken: String {
        switch self {
        case .correct: return "in place"
        case .present: return "in the word, wrong place"
        case .absent: return "not in the word"
        case .unknown: return "not scored"
        }
    }
}

/// One submitted guess. `word` is the letters for me always, and for somebody
/// else only once the game has finished; before then their row is colours only.
struct WordleRow: Decodable, Equatable {
    let word: String?
    let marks: [WordleMark]

    init(word: String?, marks: [WordleMark]) {
        self.word = word
        self.marks = marks
    }

    private enum CodingKeys: String, CodingKey { case word, marks }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = ((try? c.decodeIfPresent(String.self, forKey: .word)) ?? nil)?.lowercased()
        marks = (try? c.decodeIfPresent([WordleMark].self, forKey: .marks)) ?? []
    }

    /// The letters, upper-case for display, or nil for a colours-only row.
    var letters: [Character]? {
        word.map { Array($0.uppercased()) }
    }

    var solved: Bool { !marks.isEmpty && marks.allSatisfy { $0 == .correct } }
}

/// The row being typed. Letters only (A–Z), at most `length`, lower-case on
/// the wire.
struct WordleInput: Equatable {
    let length: Int
    private(set) var letters: [Character] = []

    init(length: Int = 5) {
        self.length = max(1, length)
    }

    var word: String { String(letters) }
    var isComplete: Bool { letters.count == length }
    var isEmpty: Bool { letters.isEmpty }

    /// Adds a letter. False (and nothing changes) for a non-letter or a full row.
    @discardableResult
    mutating func add(_ character: Character) -> Bool {
        guard letters.count < length else { return false }
        let folded = character.lowercased()
        guard folded.count == 1, let lower = folded.first,
              let ascii = lower.asciiValue, ascii >= 97, ascii <= 122 else { return false }
        letters.append(lower)
        return true
    }

    /// Removes the last letter. False when there was none.
    @discardableResult
    mutating func delete() -> Bool {
        guard !letters.isEmpty else { return false }
        letters.removeLast()
        return true
    }

    mutating func clear() {
        letters.removeAll()
    }
}

/// The on-screen keyboard: its layout, and each key's colour.
enum WordleKeyboard {
    /// QWERTY. Enter and Delete flank the bottom row.
    static let rows: [[Character]] = [
        Array("qwertyuiop"),
        Array("asdfghjkl"),
        Array("zxcvbnm"),
    ]

    /// The better of two verdicts for one letter.
    static func best(_ a: WordleMark?, _ b: WordleMark?) -> WordleMark? {
        switch (a, b) {
        case (nil, nil): return nil
        case (let x?, nil): return x
        case (nil, let y?): return y
        case (let x?, let y?): return y.rank > x.rank ? y : x
        }
    }

    /// Each letter's best verdict: the server's `keyboard`, and my own rows
    /// read again so a frame that lags a guess never shows a key worse than
    /// the grid above it. `unknown` is no information and is dropped.
    static func marks(server: [String: WordleMark], rows: [WordleRow]) -> [Character: WordleMark] {
        var out: [Character: WordleMark] = [:]
        func note(_ letter: Character, _ mark: WordleMark) {
            guard mark != .unknown else { return }
            out[letter] = best(out[letter], mark)
        }
        for (key, mark) in server {
            guard let letter = key.lowercased().first, key.count == 1 else { continue }
            note(letter, mark)
        }
        for row in rows {
            guard let word = row.word else { continue }
            for (letter, mark) in zip(Array(word.lowercased()), row.marks) { note(letter, mark) }
        }
        return out
    }
}

/// The time limit, as the player reads it.
enum WordleClock {
    /// "4:59", "0:07", "0:00". Whole seconds, rounded UP, so the clock shows
    /// 0:00 only once the time has actually gone.
    static func text(msLeft: Double) -> String {
        let seconds = max(0, Int((msLeft / 1000).rounded(.up)))
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    /// "1:23" for a solve time; "83 s" would read as a reaction.
    static func duration(ms: Int) -> String {
        let seconds = max(0, ms / 1000)
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}
