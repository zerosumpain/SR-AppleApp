import Foundation

// Chess's wire pieces and the little the phone works out for itself: the
// board from a FEN, which squares a tap may go to (the server sends every
// legal move for the side to move), the clocks ticking down from the server's
// figures, and the sentence for how a game ended. The server owns the rules;
// nothing here decides whether a move is legal.
//
// The room's chess side is decoded whole into `ChessState`, read off the same
// JSON as `GameRoom` (`GameRoom.chess`), as Liar's Dice and Marble Race do.

/// Where a chess room is. `playing` is also a shared `GamePhase`; this keeps
/// the game's screen switching over its own enum like the others'.
enum ChessPhase: String, Equatable {
    case lobby, countdown, playing, finished, closed, unknown

    static func from(_ raw: String?) -> ChessPhase {
        guard let raw else { return .unknown }
        return ChessPhase(rawValue: raw) ?? .unknown
    }
}

enum ChessColour: String, Decodable, Equatable, Hashable {
    case white = "w"
    case black = "b"

    var other: ChessColour { self == .white ? .black : .white }
    var name: String { self == .white ? "White" : "Black" }
}

enum ChessPieceKind: Character, Equatable, Hashable, CaseIterable {
    case pawn = "p"
    case knight = "n"
    case bishop = "b"
    case rook = "r"
    case queen = "q"
    case king = "k"

    var name: String {
        switch self {
        case .pawn: return "Pawn"
        case .knight: return "Knight"
        case .bishop: return "Bishop"
        case .rook: return "Rook"
        case .queen: return "Queen"
        case .king: return "King"
        }
    }

    /// The usual count, for the material balance beside a clock.
    var value: Int {
        switch self {
        case .pawn: return 1
        case .knight, .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 0
        }
    }

    /// The filled glyph, used for BOTH colours: the outlined white set reads
    /// thin on a coloured square, so the board colours the glyph itself.
    var glyph: String {
        switch self {
        // U+FE0E asks for the text glyph: iOS draws a bare ♟ as an emoji,
        // which ignores the colour and spills out of its square.
        case .pawn: return "♟\u{FE0E}"
        case .knight: return "♞\u{FE0E}"
        case .bishop: return "♝\u{FE0E}"
        case .rook: return "♜\u{FE0E}"
        case .queen: return "♛\u{FE0E}"
        case .king: return "♚\u{FE0E}"
        }
    }

    /// From one letter of the wire ("p", "N"); nil for anything else.
    static func from(_ raw: String) -> ChessPieceKind? {
        let lower = raw.lowercased()
        guard lower.count == 1, let ch = lower.first else { return nil }
        return ChessPieceKind(rawValue: ch)
    }
}

struct ChessPiece: Equatable, Hashable {
    let colour: ChessColour
    let kind: ChessPieceKind

    init(colour: ChessColour, kind: ChessPieceKind) {
        self.colour = colour
        self.kind = kind
    }

    /// From a FEN letter: upper-case white, lower-case black.
    init?(fen: Character) {
        guard let kind = ChessPieceKind.from(String(fen)) else { return nil }
        self.kind = kind
        self.colour = fen.isUppercase ? .white : .black
    }

    var spoken: String { "\(colour.name.lowercased()) \(kind.name.lowercased())" }
}

/// One square, by file (0 = a) and rank (0 = the first rank).
struct ChessSquare: Hashable, Equatable {
    static let files: [Character] = Array("abcdefgh")

    let file: Int
    let rank: Int

    init(file: Int, rank: Int) {
        self.file = file
        self.rank = rank
    }

    /// From "e4"; nil for anything that is not a square.
    init?(name: String) {
        let chars = Array(name)
        guard chars.count == 2,
              let f = Self.files.firstIndex(of: chars[0]),
              let r = chars[1].wholeNumberValue, (1...8).contains(r) else { return nil }
        file = f
        rank = r - 1
    }

    var name: String { String(Self.files[file]) + String(rank + 1) }
    /// a1 is dark.
    var isDark: Bool { (file + rank) % 2 == 0 }
    /// The site's index: a1 = 0, h8 = 63.
    var index: Int { rank * 8 + file }
}

/// The pieces on the board, from the FEN the site sends.
struct ChessBoard: Equatable {
    /// 64 squares, a1 first (index = rank * 8 + file).
    let squares: [ChessPiece?]

    static let empty = ChessBoard(squares: Array(repeating: nil, count: 64))

    init(squares: [ChessPiece?]) {
        self.squares = squares.count == 64 ? squares : Array(repeating: nil, count: 64)
    }

    /// The placement field of a FEN. Anything malformed is an empty board —
    /// a blank, never a crash, for a site newer than the app.
    init(fen: String) {
        var out: [ChessPiece?] = Array(repeating: nil, count: 64)
        let placement = fen.split(separator: " ").first.map(String.init) ?? ""
        let rows = placement.split(separator: "/", omittingEmptySubsequences: false)
        guard rows.count == 8 else {
            squares = out
            return
        }
        for (i, row) in rows.enumerated() {
            let rank = 7 - i
            var file = 0
            for ch in row {
                if let n = ch.wholeNumberValue, (1...8).contains(n) {
                    file += n
                } else if let piece = ChessPiece(fen: ch), file < 8 {
                    out[rank * 8 + file] = piece
                    file += 1
                } else {
                    squares = Array(repeating: nil, count: 64)
                    return
                }
            }
            guard file == 8 else {
                squares = Array(repeating: nil, count: 64)
                return
            }
        }
        squares = out
    }

    subscript(_ square: ChessSquare) -> ChessPiece? { squares[square.index] }

    func king(_ colour: ChessColour) -> ChessSquare? {
        guard let i = squares.firstIndex(where: { $0 == ChessPiece(colour: colour, kind: .king) }) else { return nil }
        return ChessSquare(file: i % 8, rank: i / 8)
    }

    var pieceCount: Int { squares.compactMap { $0 }.count }
}

/// One of the moves open to the side to move: where from, where to, and
/// whether the phone must ask which piece the pawn becomes.
struct ChessLegalMove: Decodable, Equatable {
    let from: String
    let to: String
    let promotes: Bool

    init(from: String, to: String, promotes: Bool = false) {
        self.from = from
        self.to = to
        self.promotes = promotes
    }

    private enum CodingKeys: String, CodingKey { case from, to, promotes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = (try? c.decodeIfPresent(String.self, forKey: .from)) ?? ""
        to = (try? c.decodeIfPresent(String.self, forKey: .to)) ?? ""
        promotes = (try? c.decodeIfPresent(Bool.self, forKey: .promotes)) ?? false
    }
}

struct ChessLastMove: Decodable, Equatable {
    let from: String
    let to: String

    private enum CodingKeys: String, CodingKey { case from, to }

    init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = (try? c.decodeIfPresent(String.self, forKey: .from)) ?? ""
        to = (try? c.decodeIfPresent(String.self, forKey: .to)) ?? ""
    }
}

/// How the game ended. `outcome` is the server's word: checkmate, stalemate,
/// insufficient, fifty-moves, repetition, resigned, timeout, agreed, left.
struct ChessResult: Decodable, Equatable {
    let outcome: String
    /// Nil for a draw.
    let winnerId: String?

    init(outcome: String, winnerId: String?) {
        self.outcome = outcome
        self.winnerId = winnerId
    }

    private enum CodingKeys: String, CodingKey { case outcome, winnerId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        outcome = (try? c.decodeIfPresent(String.self, forKey: .outcome)) ?? ""
        winnerId = (try? c.decodeIfPresent(String.self, forKey: .winnerId)) ?? nil
    }

    var drawn: Bool { winnerId == nil }
}

/// A player at the board, as chess sees them. Name and status are the shared `GamePlayer`'s.
struct ChessSeat: Decodable, Equatable, Identifiable {
    let id: String
    let seated: Bool
    let colour: ChessColour?
    /// Time left when their current turn began (ms).
    let clockMs: Double

    private enum CodingKeys: String, CodingKey { case id, seated, colour, clockMs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        seated = (try? c.decodeIfPresent(Bool.self, forKey: .seated)) ?? false
        colour = (try? c.decodeIfPresent(ChessColour.self, forKey: .colour)) ?? nil
        clockMs = (try? c.decodeIfPresent(Double.self, forKey: .clockMs)) ?? 0
    }
}

/// A row of the final table: the winner first; both at place 1 in a draw.
struct ChessStanding: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let place: Int
    let colour: ChessColour?
    /// won | lost | drew
    let result: String
    let clockMs: Double

    private enum CodingKeys: String, CodingKey { case id, name, place, colour, result, clockMs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Player"
        place = (try? c.decodeIfPresent(Int.self, forKey: .place)) ?? 0
        colour = (try? c.decodeIfPresent(ChessColour.self, forKey: .colour)) ?? nil
        result = (try? c.decodeIfPresent(String.self, forKey: .result)) ?? ""
        clockMs = (try? c.decodeIfPresent(Double.self, forKey: .clockMs)) ?? 0
    }
}

/// The two clocks as the server last fixed them (ms), keyed w / b on the wire.
struct ChessClocks: Decodable, Equatable {
    let white: Double
    let black: Double

    init(white: Double, black: Double) {
        self.white = white
        self.black = black
    }

    private enum CodingKeys: String, CodingKey { case w, b }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        white = (try? c.decodeIfPresent(Double.self, forKey: .w)) ?? 0
        black = (try? c.decodeIfPresent(Double.self, forKey: .b)) ?? 0
    }

    func of(_ colour: ChessColour) -> Double { colour == .white ? white : black }
}

/// What each side has taken, in the order taken, keyed w / b on the wire.
struct ChessCaptured: Decodable, Equatable {
    let white: [ChessPieceKind]
    let black: [ChessPieceKind]

    static let none = ChessCaptured(white: [], black: [])

    init(white: [ChessPieceKind], black: [ChessPieceKind]) {
        self.white = white
        self.black = black
    }

    private enum CodingKeys: String, CodingKey { case w, b }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        white = ((try? c.decodeIfPresent([String].self, forKey: .w)) ?? []).compactMap(ChessPieceKind.from)
        black = ((try? c.decodeIfPresent([String].self, forKey: .b)) ?? []).compactMap(ChessPieceKind.from)
    }

    /// Pieces this colour has taken.
    func by(_ colour: ChessColour) -> [ChessPieceKind] { colour == .white ? white : black }

    /// Material in hand for `colour` against the other side, in points; 0 when level.
    func balance(for colour: ChessColour) -> Int {
        by(colour).reduce(0) { $0 + $1.value } - by(colour.other).reduce(0) { $0 + $1.value }
    }
}

/// The room's chess side, decoded from the same JSON as `GameRoom`. Lenient
/// throughout: a lobby from the create call carries only the clock rule.
struct ChessState: Decodable, Equatable {
    let phase: ChessPhase
    let mainMs: Double
    let incrementMs: Double
    /// The time control in a sentence, from the server.
    let rule: String?
    let fen: String
    let board: ChessBoard
    /// The side to move.
    let turn: ChessColour
    /// Whose move it is while playing; nil otherwise.
    let turnId: String?
    /// When the running clock started, server epoch ms.
    let turnStartedAt: Double?
    /// The side to move is in check.
    let check: Bool
    let whiteId: String?
    let blackId: String?
    let clocks: ChessClocks
    /// SAN, oldest first.
    let moves: [String]
    let lastMove: ChessLastMove?
    let captured: ChessCaptured
    /// Every move open to me — sent only when it is my move; empty otherwise.
    let legal: [ChessLegalMove]
    let drawOfferBy: String?
    let result: ChessResult?
    let seats: [ChessSeat]
    let standings: [ChessStanding]?

    private enum CodingKeys: String, CodingKey {
        case phase, mainMs, incrementMs, rule, fen, turn, turnId, turnStartedAt, check, whiteId, blackId
        case clocks, moves, lastMove, captured, legal, drawOfferBy, result, players, standings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = ChessPhase.from((try? c.decodeIfPresent(String.self, forKey: .phase)) ?? nil)
        mainMs = (try? c.decodeIfPresent(Double.self, forKey: .mainMs)) ?? 600_000
        incrementMs = (try? c.decodeIfPresent(Double.self, forKey: .incrementMs)) ?? 0
        rule = (try? c.decodeIfPresent(String.self, forKey: .rule)) ?? nil
        fen = (try? c.decodeIfPresent(String.self, forKey: .fen)) ?? ""
        board = ChessBoard(fen: fen)
        turn = (try? c.decodeIfPresent(ChessColour.self, forKey: .turn)) ?? .white
        turnId = (try? c.decodeIfPresent(String.self, forKey: .turnId)) ?? nil
        turnStartedAt = (try? c.decodeIfPresent(Double.self, forKey: .turnStartedAt)) ?? nil
        check = (try? c.decodeIfPresent(Bool.self, forKey: .check)) ?? false
        whiteId = (try? c.decodeIfPresent(String.self, forKey: .whiteId)) ?? nil
        blackId = (try? c.decodeIfPresent(String.self, forKey: .blackId)) ?? nil
        clocks = (try? c.decodeIfPresent(ChessClocks.self, forKey: .clocks)) ?? ChessClocks(white: 0, black: 0)
        moves = (try? c.decodeIfPresent([String].self, forKey: .moves)) ?? []
        lastMove = (try? c.decodeIfPresent(ChessLastMove.self, forKey: .lastMove)) ?? nil
        captured = (try? c.decodeIfPresent(ChessCaptured.self, forKey: .captured)) ?? .none
        legal = (try? c.decodeIfPresent([ChessLegalMove].self, forKey: .legal)) ?? []
        drawOfferBy = (try? c.decodeIfPresent(String.self, forKey: .drawOfferBy)) ?? nil
        result = (try? c.decodeIfPresent(ChessResult.self, forKey: .result)) ?? nil
        seats = (try? c.decodeIfPresent([ChessSeat].self, forKey: .players)) ?? []
        standings = (try? c.decodeIfPresent([ChessStanding].self, forKey: .standings)) ?? nil
    }

    func seat(_ id: String) -> ChessSeat? { seats.first { $0.id == id } }

    func colour(of id: String) -> ChessColour? {
        if id == whiteId { return .white }
        if id == blackId { return .black }
        return nil
    }

    func player(of colour: ChessColour) -> String? { colour == .white ? whiteId : blackId }

    /// Time left for `colour` at server time `now`: the server's figure, less
    /// what has run since the turn began while it is that side's move.
    func remaining(_ colour: ChessColour, now: Double?) -> Double {
        let base = max(0, clocks.of(colour))
        guard phase == .playing, turn == colour, let started = turnStartedAt, let now else { return base }
        return max(0, base - max(0, now - started))
    }

    /// The square a tap on `from` may go to, by name.
    func targets(from square: ChessSquare) -> [ChessLegalMove] {
        legal.filter { $0.from == square.name }
    }

    /// Squares with a piece I may move.
    var movable: Set<String> { Set(legal.map(\.from)) }

    /// The king in check, for the board's red square.
    var checkedKing: ChessSquare? { check ? board.king(turn) : nil }

    /// Who lost it, by id: the other seat from the winner's, or in a draw on
    /// time the side whose clock ran out. Nil for the other draws.
    var loserId: String? {
        guard let result else { return nil }
        if let winner = result.winnerId { return seats.first { $0.seated && $0.id != winner }?.id }
        return result.outcome == "timeout" ? player(of: turn) : nil
    }

    /// How it ended, in a sentence; `name` turns an id into "You" or a name.
    func outcomeLine(name: (String) -> String) -> String? {
        guard let result else { return nil }
        return ChessRules.outcomeLine(result.outcome, winner: result.winnerId.map(name), loser: loserId.map(name))
    }
}

// MARK: - The game the host picks

/// Chess has no choice beyond the clock, which is the difficulty.
struct ChessSettings: Equatable {
    var difficulty: GameDifficulty

    func createBody(invite: [String]) -> CreateGameBody {
        CreateGameBody(game: GameKind.chess.rawValue, difficulty: difficulty.rawValue, invite: invite)
    }
}

// MARK: - What the phone works out

enum ChessRules {
    /// The pieces a pawn may become, as the picker lists them.
    static let promotionChoices: [ChessPieceKind] = [.queen, .rook, .bishop, .knight]

    /// "9:41"; under ten seconds, tenths: "0:07.3".
    static func clockText(_ ms: Double) -> String {
        let seconds = max(0, ms) / 1000
        if seconds < 10 { return String(format: "0:%04.1f", (seconds * 10).rounded(.down) / 10) }
        let whole = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// "1. e4 e5  2. Nf3 Nc6  3. Bb5" — the move list as one line.
    static func moveList(_ moves: [String]) -> String {
        var out: [String] = []
        var i = 0
        while i < moves.count {
            let number = i / 2 + 1
            let white = moves[i]
            let black = i + 1 < moves.count ? " " + moves[i + 1] : ""
            out.append("\(number). \(white)\(black)")
            i += 2
        }
        return out.joined(separator: "  ")
    }

    /// "Move 12" — the full move about to be played, from the list so far.
    static func moveNumber(_ moves: [String]) -> Int { moves.count / 2 + 1 }

    /// How the game ended, in a sentence, with "You" where the caller says so.
    static func outcomeLine(_ outcome: String, winner: String?, loser: String?) -> String {
        let w = winner ?? "Nobody"
        let l = loser ?? "Nobody"
        func wins(_ who: String) -> String { who == "You" ? "You win" : "\(who) wins" }
        switch outcome {
        case "checkmate": return "Checkmate — \(wins(w))."
        case "stalemate": return "Stalemate — a draw."
        case "insufficient": return "Neither side can mate — a draw."
        case "fifty-moves": return "Fifty moves without a capture or a pawn move — a draw."
        case "repetition": return "The same position three times — a draw."
        case "resigned": return "\(l) resigned — \(wins(w))."
        case "timeout":
            if winner == nil { return "\(l) ran out of time, but there was nothing left to mate with — a draw." }
            return "\(l) ran out of time — \(wins(w))."
        case "agreed": return "A draw, agreed."
        case "left": return "\(l) left the game — \(wins(w))."
        default: return "Game over."
        }
    }

    /// "+3" for the side ahead on material; nil when level or behind.
    static func balanceText(_ balance: Int) -> String? { balance > 0 ? "+\(balance)" : nil }
}
