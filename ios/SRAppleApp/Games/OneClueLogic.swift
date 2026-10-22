import Foundation

// One Clue's wire pieces and the little the phone works out for itself: which
// page a room is on, the warning under a clue while it is typed, who the table
// is waiting on, whether I may veto a clue, the row of ten cards, and the
// sentences for an outcome. The server owns the rules — it checks every clue,
// counts the vetoes and marks the guess; nothing here decides any of that.
//
// The room's One Clue side is decoded whole into `OneClueState`, read off the
// same JSON as `GameRoom` (`GameRoom.oneClue`), as Chess and Liar's Dice do.
// See docs/superpowers/specs/2026-10-22-family-games-one-clue.md in SR-Main.

/// Where a One Clue room is. Its own enum: `clues` and `guess` are not shared
/// `GamePhase`s, and `review` / `reveal` mean something else in other games.
enum OneCluePhase: String, Equatable {
    case lobby, countdown, clues, review, guess, reveal, finished, closed, unknown

    static func from(_ raw: String?) -> OneCluePhase {
        guard let raw else { return .unknown }
        return OneCluePhase(rawValue: raw) ?? .unknown
    }

    /// A card is in play: somebody is writing, reviewing, guessing or reading the answer.
    var inPlay: Bool { self == .clues || self == .review || self == .guess || self == .reveal }
}

/// What I am on this card.
enum OneClueRole: String, Decodable, Equatable {
    case guesser
    case clue
    case watching
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OneClueRole(rawValue: raw) ?? .unknown
    }
}

/// How the server judged a clue.
enum OneClueStatus: String, Decodable, Equatable {
    case ok
    case duplicate
    case tooClose = "too-close"
    case notOneWord = "not-one-word"
    case vetoed
    case empty
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OneClueStatus(rawValue: raw) ?? .unknown
    }

    /// Reached the guesser.
    var survives: Bool { self == .ok }

    /// The tag beside a cancelled clue; nil for one that survived or was never written.
    var tag: String? {
        switch self {
        case .duplicate: return "SAME AS ANOTHER"
        case .tooClose: return "TOO CLOSE"
        case .notOneWord: return "NOT ONE WORD"
        case .vetoed: return "VETOED"
        case .ok, .empty, .unknown: return nil
        }
    }

    /// For VoiceOver.
    var spoken: String {
        switch self {
        case .ok: return "kept"
        case .duplicate: return "cancelled, the same as another clue"
        case .tooClose: return "cancelled, too close to the word"
        case .notOneWord: return "cancelled, not one word"
        case .vetoed: return "vetoed out"
        case .empty: return "no clue"
        case .unknown: return ""
        }
    }
}

/// How a card ended.
enum OneClueOutcome: String, Decodable, Equatable {
    case correct, passed, wrong, timeout, left, discarded, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OneClueOutcome(rawValue: raw) ?? .unknown
    }

    var won: Bool { self == .correct }

    /// The pip's short word.
    var short: String {
        switch self {
        case .correct: return "Right"
        case .passed: return "Passed"
        case .wrong: return "Wrong"
        case .timeout: return "Out of time"
        case .left: return "Guesser left"
        case .discarded: return "Discarded"
        case .unknown: return "Played"
        }
    }
}

/// One clue on the wire. `vetoes`, `strikeAt` and `vetoed` only in the review
/// (and to the clue-givers after it); zero otherwise.
struct OneClueClue: Decodable, Equatable, Identifiable {
    let playerId: String
    let text: String
    let status: OneClueStatus
    let vetoes: Int
    let strikeAt: Int
    /// I have vetoed it.
    let vetoed: Bool

    var id: String { playerId }

    init(playerId: String, text: String, status: OneClueStatus, vetoes: Int = 0, strikeAt: Int = 0, vetoed: Bool = false) {
        self.playerId = playerId
        self.text = text
        self.status = status
        self.vetoes = vetoes
        self.strikeAt = strikeAt
        self.vetoed = vetoed
    }

    private enum CodingKeys: String, CodingKey { case playerId, text, status, vetoes, strikeAt, vetoed }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(String.self, forKey: .playerId)
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        status = (try? c.decodeIfPresent(OneClueStatus.self, forKey: .status)) ?? .unknown
        vetoes = (try? c.decodeIfPresent(Int.self, forKey: .vetoes)) ?? 0
        strikeAt = (try? c.decodeIfPresent(Int.self, forKey: .strikeAt)) ?? 0
        vetoed = (try? c.decodeIfPresent(Bool.self, forKey: .vetoed)) ?? false
    }
}

/// A card that is over — public to everyone.
struct OneClueCard: Decodable, Equatable, Identifiable {
    let index: Int
    let word: String
    /// Nil for a discarded card (nobody guessed it).
    let guesserId: String?
    let outcome: OneClueOutcome
    let guess: String?
    let tookBack: Bool
    let clues: [OneClueClue]

    var id: Int { index }

    private enum CodingKeys: String, CodingKey { case index, word, guesserId, outcome, guess, tookBack, clues }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decode(Int.self, forKey: .index)
        word = (try? c.decodeIfPresent(String.self, forKey: .word)) ?? ""
        guesserId = (try? c.decodeIfPresent(String.self, forKey: .guesserId)) ?? nil
        outcome = (try? c.decodeIfPresent(OneClueOutcome.self, forKey: .outcome)) ?? .unknown
        guess = (try? c.decodeIfPresent(String.self, forKey: .guess)) ?? nil
        tookBack = (try? c.decodeIfPresent(Bool.self, forKey: .tookBack)) ?? false
        clues = (try? c.decodeIfPresent([OneClueClue].self, forKey: .clues)) ?? []
    }
}

/// A player's One Clue side (`players[]` on the wire).
struct OneClueSeat: Decodable, Equatable, Identifiable {
    let id: String
    let role: OneClueRole?
    /// Has written a clue for this card (while writing only).
    let submitted: Bool
    /// Seen enough (review) / ready for the next card (reveal).
    let done: Bool

    private enum CodingKeys: String, CodingKey { case id, role, submitted, done }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        role = (try? c.decodeIfPresent(OneClueRole.self, forKey: .role)) ?? nil
        submitted = (try? c.decodeIfPresent(Bool.self, forKey: .submitted)) ?? false
        done = (try? c.decodeIfPresent(Bool.self, forKey: .done)) ?? false
    }
}

/// One row of the final table: the TEAM score, the same for everyone.
struct OneClueStanding: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let score: Int
    let guessed: Int
    let clues: Int

    private enum CodingKeys: String, CodingKey { case id, name, score, guessed, clues }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Player"
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        guessed = (try? c.decodeIfPresent(Int.self, forKey: .guessed)) ?? 0
        clues = (try? c.decodeIfPresent(Int.self, forKey: .clues)) ?? 0
    }
}

/// The room's One Clue side, from the same JSON as `GameRoom`.
struct OneClueState: Decodable, Equatable {
    let phase: OneCluePhase
    let cardCount: Int
    let minPlayers: Int
    let maxPlayers: Int
    let clueMs: Double
    let reviewMs: Double
    let guessMs: Double
    let revealMs: Double
    let maxClue: Int
    let maxGuess: Int
    /// The team's score so far.
    let score: Int
    /// The card in play, 0-based; nil outside play.
    let cardIndex: Int?
    let guesserId: String?
    let role: OneClueRole?
    /// The secret: mine while I give a clue, everyone's from the reveal. Never the guesser's before it.
    let word: String?
    /// My own clue while writing.
    let myClue: String?
    /// What this phone may see of the clues (the guesser: survivors only).
    let clues: [OneClueClue]?
    /// To the guesser while guessing: how many were cancelled (never which).
    let cancelledCount: Int?
    let guess: String?
    let outcome: OneClueOutcome?
    let tookBack: Bool
    /// Every card that is over, discarded ones too.
    let cards: [OneClueCard]
    let seats: [OneClueSeat]
    let standings: [OneClueStanding]?
    let verdict: String?

    private enum CodingKeys: String, CodingKey {
        case phase, cardCount, minPlayers, maxPlayers, clueMs, reviewMs, guessMs, revealMs, maxClue, maxGuess
        case score, cardIndex, guesserId, role, word, myClue, clues, cancelledCount, guess, outcome, tookBack
        case cards, players, standings, verdict
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = OneCluePhase.from((try? c.decodeIfPresent(String.self, forKey: .phase)) ?? nil)
        cardCount = max(1, (try? c.decodeIfPresent(Int.self, forKey: .cardCount)) ?? 10)
        minPlayers = (try? c.decodeIfPresent(Int.self, forKey: .minPlayers)) ?? 3
        maxPlayers = (try? c.decodeIfPresent(Int.self, forKey: .maxPlayers)) ?? 7
        clueMs = (try? c.decodeIfPresent(Double.self, forKey: .clueMs)) ?? 75_000
        reviewMs = (try? c.decodeIfPresent(Double.self, forKey: .reviewMs)) ?? 30_000
        guessMs = (try? c.decodeIfPresent(Double.self, forKey: .guessMs)) ?? 60_000
        revealMs = (try? c.decodeIfPresent(Double.self, forKey: .revealMs)) ?? 12_000
        maxClue = max(1, (try? c.decodeIfPresent(Int.self, forKey: .maxClue)) ?? 30)
        maxGuess = max(1, (try? c.decodeIfPresent(Int.self, forKey: .maxGuess)) ?? 40)
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        cardIndex = (try? c.decodeIfPresent(Int.self, forKey: .cardIndex)) ?? nil
        guesserId = (try? c.decodeIfPresent(String.self, forKey: .guesserId)) ?? nil
        role = (try? c.decodeIfPresent(OneClueRole.self, forKey: .role)) ?? nil
        word = (try? c.decodeIfPresent(String.self, forKey: .word)) ?? nil
        myClue = (try? c.decodeIfPresent(String.self, forKey: .myClue)) ?? nil
        clues = (try? c.decodeIfPresent([OneClueClue].self, forKey: .clues)) ?? nil
        cancelledCount = (try? c.decodeIfPresent(Int.self, forKey: .cancelledCount)) ?? nil
        guess = (try? c.decodeIfPresent(String.self, forKey: .guess)) ?? nil
        outcome = (try? c.decodeIfPresent(OneClueOutcome.self, forKey: .outcome)) ?? nil
        tookBack = (try? c.decodeIfPresent(Bool.self, forKey: .tookBack)) ?? false
        cards = (try? c.decodeIfPresent([OneClueCard].self, forKey: .cards)) ?? []
        seats = (try? c.decodeIfPresent([OneClueSeat].self, forKey: .players)) ?? []
        standings = (try? c.decodeIfPresent([OneClueStanding].self, forKey: .standings)) ?? nil
        verdict = (try? c.decodeIfPresent(String.self, forKey: .verdict)) ?? nil
    }

    func seat(_ id: String) -> OneClueSeat? { seats.first { $0.id == id } }

    /// The clue-givers on this card.
    var giverIds: [String] { seats.filter { $0.role == .clue }.map(\.id) }

    /// The card just settled (in the reveal), from the public list.
    var lastCard: OneClueCard? {
        guard let index = cardIndex else { return nil }
        return cards.first { $0.index == index }
    }
}

// MARK: - The rules the phone applies itself

/// How one of the ten cards stands, for the row of pips.
enum OneCluePip: Equatable {
    case won
    case lost
    case discarded
    case current
    case toCome
}

enum OneClueRules {
    /// Which page the room is on: One Clue's own phase when the room carries
    /// it, else the shared phase (a lobby from an older answer).
    static func phase(_ room: GameRoom) -> OneCluePhase {
        if let phase = room.oneClue?.phase, phase != .unknown { return phase }
        switch room.phase {
        case .lobby: return .lobby
        case .countdown: return .countdown
        case .review: return .review
        case .reveal: return .reveal
        case .finished: return .finished
        case .closed: return .closed
        default: return .unknown
        }
    }

    /// Lower case, accents off, anything but letters and digits a space,
    /// spaces single, a leading article dropped — as the server reads a clue.
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

    /// The warning under the clue field while typing, or nil. A warning only:
    /// the server's checks decide, and a warned clue is still sent.
    static func warning(_ draft: String, word: String?) -> String? {
        let clue = normalise(draft)
        guard !clue.isEmpty else { return nil }
        if clue.contains(" ") { return "One word only — this one would be cancelled." }
        if let word {
            let secret = normalise(word).replacingOccurrences(of: " ", with: "")
            if !secret.isEmpty, clue == secret || clue.contains(secret) || (clue.count >= 3 && secret.contains(clue)) {
                return "Too close to the word — this one would be cancelled."
            }
        }
        return nil
    }

    /// What the server keeps of a draft: no line breaks, at most `max` characters.
    static func cap(_ text: String, max: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > max ? String(flat.prefix(max)) : flat
    }

    /// Whether I may veto (or un-veto) this clue: the review, I am a
    /// clue-giver, it is somebody else's, and it passed the checks.
    static func canVeto(_ clue: OneClueClue, room: GameRoom) -> Bool {
        guard let state = room.oneClue, phase(room) == .review, state.role == .clue, room.me?.joined == true else { return false }
        return clue.playerId != room.meId && (clue.status == .ok || clue.status == .vetoed)
    }

    /// "1 of 2 vetoes" — once anybody has vetoed.
    static func vetoLine(_ clue: OneClueClue) -> String? {
        guard clue.vetoes > 0 else { return nil }
        let bar = max(clue.strikeAt, 1)
        return "\(clue.vetoes) of \(bar) \(bar == 1 ? "veto" : "vetoes")"
    }

    /// Who the table is waiting on: clue-givers yet to write, clue-givers yet
    /// to say done, the guesser, or anybody not yet ready for the next card.
    static func waitingOn(_ room: GameRoom) -> [GamePlayer] {
        guard let state = room.oneClue else { return [] }
        let joined = room.playing
        switch phase(room) {
        case .clues:
            return joined.filter { state.seat($0.id)?.role == .clue && state.seat($0.id)?.submitted != true }
        case .review:
            return joined.filter { state.seat($0.id)?.role == .clue && state.seat($0.id)?.done != true }
        case .guess:
            return joined.filter { $0.id == state.guesserId }
        case .reveal:
            return joined.filter { state.seat($0.id)?.done != true }
        default:
            return []
        }
    }

    /// "Sam, Robin and you", with me as "you".
    static func names(_ players: [GamePlayer], me: String) -> String {
        GameNames.list(players.map { $0.id == me ? "you" : $0.name })
    }

    /// The row of ten: won, lost, discarded, this one, still to come.
    static func pips(_ state: OneClueState) -> [OneCluePip] {
        (0..<state.cardCount).map { index -> OneCluePip in
            if let card = state.cards.first(where: { $0.index == index }) {
                if card.outcome == .discarded { return .discarded }
                return card.outcome.won ? .won : .lost
            }
            return index == state.cardIndex ? .current : .toCome
        }
    }

    /// "Card 3 of 10".
    static func cardLine(_ state: OneClueState) -> String {
        guard let index = state.cardIndex else { return "\(state.cardCount) cards" }
        return "Card \(index + 1) of \(state.cardCount)"
    }

    /// The reveal's headline, for whoever is reading it.
    static func outcomeLine(_ outcome: OneClueOutcome?, guesser: String, isMe: Bool, tookBack: Bool) -> String {
        let who = isMe ? "You" : guesser
        switch outcome {
        case .correct?: return "\(who) got it!"
        case .passed?: return "\(who) passed — the card is lost."
        case .wrong?:
            return tookBack
                ? "Not quite — and a card already won goes back."
                : "Not quite — this card and the next are lost."
        case .timeout?: return "Out of time — the card is lost."
        case .left?: return "The guesser left — the card is lost."
        default: return "The card is over."
        }
    }

    /// "7 out of 10" for the finish.
    static func scoreLine(_ score: Int, of count: Int) -> String { "\(score) out of \(count)" }

    /// The finish's sentence, when the server sent none.
    static func verdict(_ score: Int) -> String {
        if score >= 10 { return "Perfect: ten out of ten!" }
        if score >= 8 { return "Brilliant teamwork." }
        if score >= 6 { return "A good game." }
        if score >= 4 { return "Not bad at all." }
        return "Tricky words — try again!"
    }

    /// The lobby's line on who can start: three to seven.
    static func lobbyLine(playing: Int, min: Int, max: Int) -> String? {
        if playing < min { return "Needs at least \(min) players — \(min - playing) more to start." }
        if playing > max { return "Up to \(max) players." }
        return nil
    }
}
