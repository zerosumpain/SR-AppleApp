import Foundation

// Categories' wire pieces and the rules the phone applies itself — the letter
// test, what a veto would do, the round the host picks — as pure values, so
// each is a unit test. The server judges every answer; nothing here decides
// whether one counts or what it scores. The phone's letter test only warns
// while typing.

/// How the server judged an answer, from the review on. Nil while playing.
enum CategoriesStatus: String, Decodable, Equatable {
    /// Right letter, nobody else wrote it, not struck: a point.
    case ok
    /// Somebody else wrote the same for this category: nothing, for both.
    case shared
    /// Doesn't start with the letter.
    case wrongLetter = "wrong-letter"
    /// Vetoed out by the others.
    case struck
    /// Left blank.
    case empty
    /// A status this version of the app has not heard of.
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CategoriesStatus(rawValue: raw) ?? .unknown
    }

    /// The tag beside a crossed-out answer; nil for one that scores or is blank.
    var tag: String? {
        switch self {
        case .shared: return "SHARED"
        case .wrongLetter: return "WRONG LETTER"
        case .struck: return "VETOED"
        case .ok, .empty, .unknown: return nil
        }
    }

    /// Drawn struck through: it was written, and it scores nothing.
    var crossed: Bool { self == .shared || self == .wrongLetter || self == .struck }
}

/// One slot of a player's card: what they wrote for category `index`, and —
/// from the review on — how it was judged and who is vetoing it.
struct CategoriesAnswer: Decodable, Equatable, Identifiable {
    let index: Int
    let text: String
    let status: CategoriesStatus?
    let points: Int
    /// Vetoes against it that count, and how many strike it.
    let vetoes: Int
    let strikeAt: Int
    /// I have vetoed it.
    let vetoed: Bool

    var id: Int { index }

    init(index: Int, text: String, status: CategoriesStatus? = nil, points: Int = 0,
         vetoes: Int = 0, strikeAt: Int = 0, vetoed: Bool = false) {
        self.index = index
        self.text = text
        self.status = status
        self.points = points
        self.vetoes = vetoes
        self.strikeAt = strikeAt
        self.vetoed = vetoed
    }

    private enum CodingKeys: String, CodingKey { case index, text, status, points, vetoes, strikeAt, vetoed }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decode(Int.self, forKey: .index)
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        status = (try? c.decodeIfPresent(CategoriesStatus.self, forKey: .status)) ?? nil
        points = (try? c.decodeIfPresent(Int.self, forKey: .points)) ?? 0
        vetoes = (try? c.decodeIfPresent(Int.self, forKey: .vetoes)) ?? 0
        strikeAt = (try? c.decodeIfPresent(Int.self, forKey: .strikeAt)) ?? 0
        vetoed = (try? c.decodeIfPresent(Bool.self, forKey: .vetoed)) ?? false
    }
}

// MARK: - The round the host picks

/// Card size and clock — Categories' own choices on the new-game sheet.
struct CategoriesSettings: Equatable {
    static let counts = [6, 8, 10]
    static let times = [90, 120, 180]
    static let defaultCount = 8
    static let defaultSeconds = 120

    var difficulty: GameDifficulty
    var count: Int = CategoriesSettings.defaultCount
    var seconds: Int = CategoriesSettings.defaultSeconds

    func createBody(invite: [String]) -> CreateGameBody {
        CreateGameBody(
            game: GameKind.categories.rawValue,
            difficulty: difficulty.rawValue,
            invite: invite,
            seconds: seconds,
            categoryCount: count
        )
    }

    /// One line under the pickers: how long an answer that is.
    static func line(count: Int, seconds: Int) -> String {
        let each = Double(seconds) / Double(max(count, 1))
        return "\(count) categories in \(BoggleSettings.timeLabel(seconds)) — about \(Int(each.rounded())) seconds an answer."
    }

    /// "8 categories · 2 min", for the lobby.
    static func about(_ room: GameRoom) -> String {
        var parts = ["\(room.categoryCount) categories"]
        if let limit = room.timeLimitMs { parts.append(BoggleSettings.timeLabel(Int((limit / 1000).rounded()))) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - The rules

enum CategoriesRules {
    /// An answer as the server's checks read it: lower case, accents off,
    /// punctuation gone, spaces single, a leading "a", "an" or "the" dropped.
    static func normalise(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        var words: [String] = []
        var current = ""
        for scalar in folded.unicodeScalars {
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

    /// Whether an answer starts with the round's letter, once normalised.
    static func startsWith(_ text: String, letter: String) -> Bool {
        guard let first = normalise(text).first, let wanted = letter.lowercased().first else { return false }
        return first == wanted
    }

    /// The warning under a field while typing, or nil: written, and not the letter.
    static func warning(_ text: String, letter: String?) -> String? {
        guard let letter, !letter.isEmpty, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return startsWith(text, letter: letter) ? nil : "Doesn't start with \(letter.uppercased())"
    }

    /// What the server keeps of a draft: no line breaks, at most `max` characters.
    static func cap(_ text: String, max: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > max ? String(flat.prefix(max)) : flat
    }

    /// Whether I may veto this answer: the review, I'm in, it's someone
    /// else's, and there is something written there.
    static func canVeto(_ answer: CategoriesAnswer, ownerId: String, room: GameRoom) -> Bool {
        room.phase == .review && room.me?.joined == true && ownerId != room.meId
            && !answer.text.isEmpty && answer.status != .empty
    }

    /// "1 of 2 vetoes" — shown once anybody has vetoed.
    static func vetoLine(_ answer: CategoriesAnswer) -> String? {
        guard answer.vetoes > 0 else { return nil }
        let bar = max(answer.strikeAt, 1)
        return "\(answer.vetoes) of \(bar) \(bar == 1 ? "veto" : "vetoes")"
    }

    /// "3 of 8" — slots filled.
    static func filledLine(_ filled: Int, of count: Int) -> String { "\(filled) of \(count)" }

    /// Contenders for the review: everyone with answers on the wire.
    static func contenders(_ room: GameRoom) -> [GamePlayer] {
        room.players.filter { $0.categoryAnswers != nil }
    }

    /// Who hasn't said done yet, for the review's footer.
    static func waitingOn(_ room: GameRoom) -> [GamePlayer] {
        room.playing.filter { !$0.done }
    }
}
