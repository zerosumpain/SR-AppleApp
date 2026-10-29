import Foundation

// Chess's side of this phone: the record kept here (won, drawn, lost, the
// winning streak), the move list cut into numbered pairs for the strip under
// the board, and how worried a clock should look. The server owns the game;
// none of this is sent anywhere.

/// Chess games finished on this phone, as a tally.
///
/// A finished page can be opened more than once (back, then in again), so
/// each game is counted once by its key — the room, how many moves were
/// played and how it ended — and the last few keys are kept to check against.
struct ChessRecordBook: Codable, Equatable {
    var wins = 0
    var draws = 0
    var losses = 0
    /// Wins in a row, now.
    var streak = 0
    var bestStreak = 0
    /// The fewest full moves a win has taken; nil until the first win.
    var quickestWin: Int?
    /// Keys of games already counted, oldest first.
    var seen: [String] = []

    /// How many keys are kept.
    static let seenLimit = 40

    enum Outcome: String, Codable {
        case won, drawn, lost
    }

    var played: Int { wins + draws + losses }

    /// "room|moves|outcome": the same game read twice gives the same key.
    static func key(room: String, moves: Int, outcome: String) -> String {
        "\(room)|\(moves)|\(outcome)"
    }

    /// Count a finished game once. `moves` is the number of half-moves played.
    @discardableResult
    mutating func record(key: String, outcome: Outcome, moves: Int) -> ChessRecordNews {
        guard !seen.contains(key) else { return ChessRecordNews(counted: false, newBestStreak: false, newQuickest: false) }
        seen.append(key)
        if seen.count > Self.seenLimit { seen.removeFirst(seen.count - Self.seenLimit) }
        var newBestStreak = false
        var newQuickest = false
        switch outcome {
        case .won:
            wins += 1
            streak += 1
            if streak > bestStreak {
                bestStreak = streak
                newBestStreak = streak > 1
            }
            let full = max(1, (moves + 1) / 2)
            if quickestWin.map({ full < $0 }) ?? true {
                newQuickest = quickestWin != nil
                quickestWin = full
            }
        case .drawn:
            draws += 1
            streak = 0
        case .lost:
            losses += 1
            streak = 0
        }
        return ChessRecordNews(counted: true, newBestStreak: newBestStreak, newQuickest: newQuickest)
    }

    /// "4 won · 1 drawn · 2 lost".
    var line: String {
        "\(wins) won · \(draws) drawn · \(losses) lost"
    }
}

/// What a recorded game changed, for the results card's flourish.
struct ChessRecordNews: Equatable {
    let counted: Bool
    let newBestStreak: Bool
    let newQuickest: Bool
}

/// Where the record lives: one small value in UserDefaults.
struct ChessRecordStore {
    var defaults: UserDefaults = .standard

    static let key = "chess.record.v1"

    func load() -> ChessRecordBook {
        guard let data = defaults.data(forKey: Self.key),
              let book = try? JSONDecoder().decode(ChessRecordBook.self, from: data) else { return ChessRecordBook() }
        return book
    }

    func save(_ book: ChessRecordBook) {
        if let data = try? JSONEncoder().encode(book) { defaults.set(data, forKey: Self.key) }
    }
}

/// One numbered move in the strip: "12. Nf3 Nc6", black's half missing while
/// it is still to come.
struct ChessMovePair: Equatable, Identifiable {
    let number: Int
    let white: String
    let black: String?

    var id: Int { number }

    var text: String { black.map { "\(number). \(white) \($0)" } ?? "\(number). \(white)" }
}

enum ChessMoveStrip {
    /// The moves (SAN, oldest first) as numbered pairs.
    static func pairs(_ moves: [String]) -> [ChessMovePair] {
        var out: [ChessMovePair] = []
        out.reserveCapacity(moves.count / 2 + 1)
        var i = 0
        while i < moves.count {
            let black: String? = i + 1 < moves.count ? moves[i + 1] : nil
            out.append(ChessMovePair(number: i / 2 + 1, white: moves[i], black: black))
            i += 2
        }
        return out
    }
}

/// How a running clock should look: calm, getting low, or nearly out.
enum ChessClockUrgency: Equatable {
    case calm, low, critical

    /// Under 30 seconds is low; under 10, critical.
    static func of(_ ms: Double) -> ChessClockUrgency {
        if ms < 10_000 { return .critical }
        if ms < 30_000 { return .low }
        return .calm
    }
}
