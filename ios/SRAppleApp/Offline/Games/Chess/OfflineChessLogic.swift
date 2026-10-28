import Foundation

/// Chess for two phones, or for one phone against the computer.
///
/// The whole of the laws, worked out on the host: every legal move —
/// castling, en passant and promotion included — check, and every way a game
/// ends: checkmate, stalemate, a board neither side can ever mate on, fifty
/// moves with no capture or pawn move, the same position three times, a
/// resignation, a draw both sides agree, or a player who leaves. The move
/// generator is the site's (`src/lib/games/chess-engine.ts`) ported square
/// for square, and proved the same way: perft counts against the standard
/// test positions (`OfflineChessTests`), which no hand-written test of one
/// rule can match.
///
/// Who plays White is drawn from the seeded generator. There is no clock:
/// at a kitchen table a slow move is a conversation, not a forfeit. Nothing
/// is hidden either, so every phone sees the same board; only the side to
/// move is sent its legal moves, which light the squares a tapped piece may
/// go to. The host still checks every move against the position — whose
/// move it is, that the piece can go there, what a pawn becomes — and that
/// it was meant for this position and not one already played past.
///
/// The computer player (`OfflineChessBotLogic.swift`) plays at the level the
/// table picks (`Action.level`), and only through `apply`, like a person.
enum OfflineChessRules: OfflineGameRules {
    /// How long the final board stays up before the standings.
    static let resultPause: Double = 4

    static let info = OfflineGameInfo(
        id: "chess",
        title: "Chess",
        blurb: "The classic, with no internet: a friend across the table or the phone itself.",
        category: .skill,
        minPlayers: 2,
        maxPlayers: 2,
        symbol: "checkerboard.rectangle",
        howToPlay: [
            "Blue (White) moves first; who gets Blue is drawn at random.",
            "Tap one of your pieces, then a lit square to move it there.",
            "Checkmate wins. Stalemate, bare kings, fifty quiet moves or a position seen three times is a draw.",
            "You can offer a draw, or resign, at any time.",
            "Against the phone, pick Easy, Medium or Hard — you can change it mid-game.",
            "There is no clock: take as long as you like."
        ]
    )

    // MARK: - Pieces and squares

    /// Piece kinds on the board: positive for white, negative for black.
    static let pawn = 1
    static let knight = 2
    static let bishop = 3
    static let rook = 4
    static let queen = 5
    static let king = 6

    /// Castling rights, as bits of `Position.castling`.
    static let whiteKingside = 1
    static let whiteQueenside = 2
    static let blackKingside = 4
    static let blackQueenside = 8

    static let startFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    static let files = Array("abcdefgh")

    /// "e4" for 28 (a1 = 0, h8 = 63).
    static func squareName(_ square: Int) -> String {
        guard (0..<64).contains(square) else { return "-" }
        return String(files[square & 7]) + String((square >> 3) + 1)
    }

    /// 28 for "e4"; nil for anything that is not a square.
    static func squareIndex(_ name: String) -> Int? {
        let chars = Array(name)
        guard chars.count == 2, let file = files.firstIndex(of: chars[0]),
              let rank = chars[1].wholeNumberValue, (1...8).contains(rank) else { return nil }
        return (rank - 1) * 8 + file
    }

    /// The letter for a piece kind, upper-case as SAN writes it.
    static func letter(_ kind: Int) -> String {
        switch kind {
        case pawn: return "P"
        case knight: return "N"
        case bishop: return "B"
        case rook: return "R"
        case queen: return "Q"
        case king: return "K"
        default: return "?"
        }
    }

    /// What a pawn may become, as an action names it.
    enum Promotion: String, Codable, Equatable, CaseIterable {
        case queen = "q", rook = "r", bishop = "b", knight = "n"

        /// The piece kind it becomes.
        var kind: Int {
            switch self {
            case .queen: return OfflineChessRules.queen
            case .rook: return OfflineChessRules.rook
            case .bishop: return OfflineChessRules.bishop
            case .knight: return OfflineChessRules.knight
            }
        }
    }

    /// What is special about a move, beyond going from one square to another.
    enum Special: Int, Codable, Equatable {
        case none, double, enPassant, castleKingside, castleQueenside
    }

    /// One move, as the generator makes it.
    struct Move: Codable, Equatable, Hashable {
        let from: Int
        let to: Int
        /// The kind that moves (1…6).
        let piece: Int
        /// The kind it takes — the pawn, for en passant — or 0.
        let captured: Int
        /// The kind a pawn becomes (2…5), or 0.
        let promotion: Int
        let special: Special

        init(from: Int, to: Int, piece: Int, captured: Int = 0, promotion: Int = 0, special: Special = .none) {
            self.from = from
            self.to = to
            self.piece = piece
            self.captured = captured
            self.promotion = promotion
            self.special = special
        }
    }

    /// What `Position.make` needs to put the board back.
    struct Undo {
        let taken: Int
        let castling: Int
        let ep: Int
        let halfmove: Int
    }

    // MARK: - The position

    /// A position: the board, whose move, and the rights that history leaves
    /// behind. A value — copy it to look ahead; `make`/`unmake` move it in
    /// place for the engine's search.
    struct Position: Codable, Equatable {
        /// 64 squares, a1 first (`rank * 8 + file`): 0 for empty, 1…6 for a
        /// white pawn, knight, bishop, rook, queen, king, negative for black.
        var board: [Int]
        var whiteToMove: Bool
        /// `whiteKingside | whiteQueenside | blackKingside | blackQueenside`.
        var castling: Int
        /// The square a pawn just passed over with a double step, or −1.
        var ep: Int
        /// Half-moves since the last capture or pawn move (the fifty-move rule).
        var halfmove: Int
        /// Starts at 1 and counts up after Black's move.
        var fullmove: Int
        /// Where the kings stand (−1 when a test position has none).
        var whiteKing: Int
        var blackKing: Int

        static var start: Position { Position(fen: OfflineChessRules.startFen) ?? Position.empty }

        static var empty: Position {
            Position(board: Array(repeating: 0, count: 64), whiteToMove: true, castling: 0, ep: -1,
                     halfmove: 0, fullmove: 1, whiteKing: -1, blackKing: -1)
        }

        init(board: [Int], whiteToMove: Bool, castling: Int, ep: Int, halfmove: Int, fullmove: Int,
             whiteKing: Int, blackKing: Int) {
            self.board = board
            self.whiteToMove = whiteToMove
            self.castling = castling
            self.ep = ep
            self.halfmove = halfmove
            self.fullmove = fullmove
            self.whiteKing = whiteKing
            self.blackKing = blackKing
        }

        /// From a FEN; nil for anything malformed.
        init?(fen: String) {
            let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let placement = fields.first else { return nil }
            let rows = placement.split(separator: "/", omittingEmptySubsequences: false)
            guard rows.count == 8 else { return nil }
            var board = Array(repeating: 0, count: 64)
            var whiteKing = -1
            var blackKing = -1
            for (i, row) in rows.enumerated() {
                let rank = 7 - i
                var file = 0
                for ch in row {
                    if let n = ch.wholeNumberValue, (1...8).contains(n) {
                        file += n
                        continue
                    }
                    guard file < 8, let kind = OfflineChessRules.kind(of: ch) else { return nil }
                    let white = ch.isUppercase
                    board[rank * 8 + file] = white ? kind : -kind
                    if kind == OfflineChessRules.king {
                        if white { whiteKing = rank * 8 + file } else { blackKing = rank * 8 + file }
                    }
                    file += 1
                }
                guard file == 8 else { return nil }
            }
            let turn = fields.count > 1 ? fields[1] : "w"
            let rights = fields.count > 2 ? fields[2] : "-"
            var castling = 0
            if rights.contains("K") { castling |= OfflineChessRules.whiteKingside }
            if rights.contains("Q") { castling |= OfflineChessRules.whiteQueenside }
            if rights.contains("k") { castling |= OfflineChessRules.blackKingside }
            if rights.contains("q") { castling |= OfflineChessRules.blackQueenside }
            let ep = fields.count > 3 ? (OfflineChessRules.squareIndex(fields[3]) ?? -1) : -1
            let half = fields.count > 4 ? max(0, Int(fields[4]) ?? 0) : 0
            let full = fields.count > 5 ? max(1, Int(fields[5]) ?? 1) : 1
            self.init(board: board, whiteToMove: turn != "b", castling: castling, ep: ep,
                      halfmove: half, fullmove: full, whiteKing: whiteKing, blackKing: blackKing)
        }

        /// The placement field of a FEN, rank 8 first.
        var placement: String {
            var rows: [String] = []
            for rank in stride(from: 7, through: 0, by: -1) {
                var row = ""
                var empty = 0
                for file in 0..<8 {
                    let p = board[rank * 8 + file]
                    if p == 0 {
                        empty += 1
                        continue
                    }
                    if empty > 0 {
                        row += String(empty)
                        empty = 0
                    }
                    let l = OfflineChessRules.letter(abs(p))
                    row += p > 0 ? l : l.lowercased()
                }
                if empty > 0 { row += String(empty) }
                rows.append(row)
            }
            return rows.joined(separator: "/")
        }

        var castlingText: String {
            var out = ""
            if castling & OfflineChessRules.whiteKingside != 0 { out += "K" }
            if castling & OfflineChessRules.whiteQueenside != 0 { out += "Q" }
            if castling & OfflineChessRules.blackKingside != 0 { out += "k" }
            if castling & OfflineChessRules.blackQueenside != 0 { out += "q" }
            return out.isEmpty ? "-" : out
        }

        var fen: String {
            let ep = self.ep >= 0 ? OfflineChessRules.squareName(self.ep) : "-"
            return "\(placement) \(whiteToMove ? "w" : "b") \(castlingText) \(ep) \(halfmove) \(fullmove)"
        }

        // MARK: Attacks

        /// Whether `white` (or black) attacks `square` — a king may not stand
        /// there, a castling king may not pass it.
        func attacked(_ square: Int, byWhite white: Bool) -> Bool {
            guard (0..<64).contains(square) else { return false }
            let s = white ? 1 : -1
            let f = square & 7
            let r = square >> 3
            if white {
                if r > 0 {
                    if f > 0 && board[square - 9] == OfflineChessRules.pawn { return true }
                    if f < 7 && board[square - 7] == OfflineChessRules.pawn { return true }
                }
            } else if r < 7 {
                if f > 0 && board[square + 7] == -OfflineChessRules.pawn { return true }
                if f < 7 && board[square + 9] == -OfflineChessRules.pawn { return true }
            }
            let knight = OfflineChessRules.knight * s
            for t in OfflineChessRules.knightTargets[square] where board[t] == knight { return true }
            let king = OfflineChessRules.king * s
            for t in OfflineChessRules.kingTargets[square] where board[t] == king { return true }
            let rook = OfflineChessRules.rook * s
            let bishop = OfflineChessRules.bishop * s
            let queen = OfflineChessRules.queen * s
            let rays = OfflineChessRules.rays
            for dir in 0..<8 {
                let straight = dir < 4
                for t in rays[square * 8 + dir] {
                    let p = board[t]
                    if p == 0 { continue }
                    if p == queen || p == (straight ? rook : bishop) { return true }
                    break
                }
            }
            return false
        }

        /// The side to move is in check.
        var inCheck: Bool {
            let k = whiteToMove ? whiteKing : blackKing
            return k >= 0 && attacked(k, byWhite: !whiteToMove)
        }

        // MARK: Moves

        /// Every move the side to move could make if its own king did not
        /// matter; `capturesOnly` for the engine's quiet-position search
        /// (captures and promotions).
        func pseudoMoves(capturesOnly: Bool = false) -> [Move] {
            var out: [Move] = []
            out.reserveCapacity(capturesOnly ? 12 : 48)
            let us = whiteToMove ? 1 : -1
            let rays = OfflineChessRules.rays
            for from in 0..<64 {
                let p = board[from] * us
                guard p > 0 else { continue }
                switch p {
                case OfflineChessRules.pawn:
                    pawnMoves(from: from, us: us, capturesOnly: capturesOnly, into: &out)
                case OfflineChessRules.knight:
                    for to in OfflineChessRules.knightTargets[from] {
                        let t = board[to] * us
                        if t > 0 || (capturesOnly && t == 0) { continue }
                        out.append(Move(from: from, to: to, piece: p, captured: -t))
                    }
                case OfflineChessRules.king:
                    for to in OfflineChessRules.kingTargets[from] {
                        let t = board[to] * us
                        if t > 0 || (capturesOnly && t == 0) { continue }
                        out.append(Move(from: from, to: to, piece: p, captured: -t))
                    }
                    if !capturesOnly { castles(from: from, us: us, into: &out) }
                default:
                    // Bishop: the diagonals (4…7); rook: the lines (0…3); queen: both.
                    let dirs = p == OfflineChessRules.bishop ? 4..<8 : p == OfflineChessRules.rook ? 0..<4 : 0..<8
                    for dir in dirs {
                        for to in rays[from * 8 + dir] {
                            let t = board[to] * us
                            if t > 0 { break }
                            if t < 0 {
                                out.append(Move(from: from, to: to, piece: p, captured: -t))
                                break
                            }
                            if !capturesOnly { out.append(Move(from: from, to: to, piece: p)) }
                        }
                    }
                }
            }
            return out
        }

        private func pawnMoves(from: Int, us: Int, capturesOnly: Bool, into out: inout [Move]) {
            let step = 8 * us
            let rank = from >> 3
            let file = from & 7
            let home = us > 0 ? 1 : 6
            let last = us > 0 ? 7 : 0
            let one = from + step
            guard (0..<64).contains(one) else { return }
            func add(_ to: Int, captured: Int) {
                if to >> 3 == last {
                    for kind in [OfflineChessRules.queen, OfflineChessRules.rook, OfflineChessRules.bishop, OfflineChessRules.knight] {
                        out.append(Move(from: from, to: to, piece: OfflineChessRules.pawn, captured: captured, promotion: kind))
                    }
                } else {
                    out.append(Move(from: from, to: to, piece: OfflineChessRules.pawn, captured: captured))
                }
            }
            if board[one] == 0 {
                if !capturesOnly || one >> 3 == last { add(one, captured: 0) }
                if !capturesOnly, rank == home, board[one + step] == 0 {
                    out.append(Move(from: from, to: one + step, piece: OfflineChessRules.pawn, special: .double))
                }
            }
            for df in [-1, 1] {
                let f = file + df
                guard f >= 0, f <= 7 else { continue }
                let to = one + df
                let t = board[to] * us
                if t < 0 {
                    add(to, captured: -t)
                } else if t == 0, to == ep {
                    out.append(Move(from: from, to: to, piece: OfflineChessRules.pawn, captured: OfflineChessRules.pawn,
                                    special: .enPassant))
                }
            }
        }

        private func castles(from: Int, us: Int, into out: inout [Move]) {
            let home = us > 0 ? 0 : 56
            guard from == home + 4 else { return }
            let white = us > 0
            let kingside = castling & (white ? OfflineChessRules.whiteKingside : OfflineChessRules.blackKingside) != 0
            let queenside = castling & (white ? OfflineChessRules.whiteQueenside : OfflineChessRules.blackQueenside) != 0
            let rook = OfflineChessRules.rook * us
            if kingside, board[home + 5] == 0, board[home + 6] == 0, board[home + 7] == rook,
               !attacked(home + 4, byWhite: !white), !attacked(home + 5, byWhite: !white), !attacked(home + 6, byWhite: !white) {
                out.append(Move(from: from, to: home + 6, piece: OfflineChessRules.king, special: .castleKingside))
            }
            if queenside, board[home + 3] == 0, board[home + 2] == 0, board[home + 1] == 0, board[home] == rook,
               !attacked(home + 4, byWhite: !white), !attacked(home + 3, byWhite: !white), !attacked(home + 2, byWhite: !white) {
                out.append(Move(from: from, to: home + 2, piece: OfflineChessRules.king, special: .castleQueenside))
            }
        }

        /// Play `move` (one of `pseudoMoves()`) in place; `unmake` with the
        /// answer puts everything back.
        @discardableResult
        mutating func make(_ move: Move) -> Undo {
            let us = whiteToMove ? 1 : -1
            let moving = board[move.from]
            var taken = board[move.to]
            board[move.from] = 0
            if move.special == .enPassant {
                let square = move.to - 8 * us
                taken = board[square]
                board[square] = 0
            }
            let saved = Undo(taken: taken, castling: castling, ep: ep, halfmove: halfmove)
            board[move.to] = move.promotion != 0 ? move.promotion * us : moving
            let home = us > 0 ? 0 : 56
            if move.special == .castleKingside {
                board[home + 5] = board[home + 7]
                board[home + 7] = 0
            } else if move.special == .castleQueenside {
                board[home + 3] = board[home]
                board[home] = 0
            }
            if move.piece == OfflineChessRules.king {
                if us > 0 {
                    whiteKing = move.to
                    castling &= ~(OfflineChessRules.whiteKingside | OfflineChessRules.whiteQueenside)
                } else {
                    blackKing = move.to
                    castling &= ~(OfflineChessRules.blackKingside | OfflineChessRules.blackQueenside)
                }
            }
            // A rook that moves, or is taken, on its home square ends that castling.
            for square in [move.from, move.to] {
                switch square {
                case 0: castling &= ~OfflineChessRules.whiteQueenside
                case 7: castling &= ~OfflineChessRules.whiteKingside
                case 56: castling &= ~OfflineChessRules.blackQueenside
                case 63: castling &= ~OfflineChessRules.blackKingside
                default: break
                }
            }
            ep = move.special == .double ? (move.from + move.to) / 2 : -1
            halfmove = move.piece == OfflineChessRules.pawn || saved.taken != 0 ? 0 : halfmove + 1
            if us < 0 { fullmove += 1 }
            whiteToMove.toggle()
            return saved
        }

        mutating func unmake(_ move: Move, _ undo: Undo) {
            whiteToMove.toggle()
            let us = whiteToMove ? 1 : -1
            if us < 0 { fullmove -= 1 }
            board[move.from] = move.promotion != 0 ? OfflineChessRules.pawn * us : board[move.to]
            if move.special == .enPassant {
                board[move.to] = 0
                board[move.to - 8 * us] = undo.taken
            } else {
                board[move.to] = undo.taken
            }
            let home = us > 0 ? 0 : 56
            if move.special == .castleKingside {
                board[home + 7] = board[home + 5]
                board[home + 5] = 0
            } else if move.special == .castleQueenside {
                board[home] = board[home + 3]
                board[home + 3] = 0
            }
            if move.piece == OfflineChessRules.king {
                if us > 0 { whiteKing = move.from } else { blackKing = move.from }
            }
            castling = undo.castling
            ep = undo.ep
            halfmove = undo.halfmove
        }

        /// Every move the side to move may make. Empty is mate or stalemate.
        func legalMoves() -> [Move] {
            var copy = self
            let white = whiteToMove
            return pseudoMoves().filter { move in
                let undo = copy.make(move)
                defer { copy.unmake(move, undo) }
                let k = white ? copy.whiteKing : copy.blackKing
                return k < 0 || !copy.attacked(k, byWhite: !white)
            }
        }

        /// The position after `move`.
        func playing(_ move: Move) -> Position {
            var next = self
            next.make(move)
            return next
        }

        /// Leaf positions `depth` moves on — the generator's proof against
        /// the published counts.
        func perft(_ depth: Int) -> Int {
            let legal = legalMoves()
            if depth <= 1 { return legal.count }
            var copy = self
            var n = 0
            for move in legal {
                let undo = copy.make(move)
                n += copy.perft(depth - 1)
                copy.unmake(move, undo)
            }
            return n
        }

        // MARK: Notation and endings

        /// Standard algebraic notation: "Nf3", "exd5", "O-O", "e8=Q+", "Qh7#".
        func san(_ move: Move, legal: [Move]? = nil) -> String {
            let legal = legal ?? legalMoves()
            var s: String
            switch move.special {
            case .castleKingside: s = "O-O"
            case .castleQueenside: s = "O-O-O"
            default:
                if move.piece == OfflineChessRules.pawn {
                    s = move.captured != 0
                        ? "\(OfflineChessRules.files[move.from & 7])x\(OfflineChessRules.squareName(move.to))"
                        : OfflineChessRules.squareName(move.to)
                    if move.promotion != 0 { s += "=" + OfflineChessRules.letter(move.promotion) }
                } else {
                    s = OfflineChessRules.letter(move.piece)
                    // Another piece of the same kind could reach the same square: say which.
                    let others = legal.filter { $0.to == move.to && $0.from != move.from && $0.piece == move.piece }
                    if !others.isEmpty {
                        let sameFile = others.contains { $0.from & 7 == move.from & 7 }
                        let sameRank = others.contains { $0.from >> 3 == move.from >> 3 }
                        if !sameFile {
                            s += String(OfflineChessRules.files[move.from & 7])
                        } else if !sameRank {
                            s += String((move.from >> 3) + 1)
                        } else {
                            s += OfflineChessRules.squareName(move.from)
                        }
                    }
                    if move.captured != 0 { s += "x" }
                    s += OfflineChessRules.squareName(move.to)
                }
            }
            let next = playing(move)
            if next.inCheck { s += next.legalMoves().isEmpty ? "#" : "+" }
            return s
        }

        /// The position for the repetition rule: the pieces, whose move, the
        /// castling rights, and an en passant square only when a capture
        /// there is actually possible.
        func repetitionKey(legal: [Move]? = nil) -> String {
            let legal = legal ?? legalMoves()
            let ep = legal.contains { $0.special == .enPassant } ? OfflineChessRules.squareName(self.ep) : "-"
            return "\(placement) \(whiteToMove ? "w" : "b") \(castlingText) \(ep)"
        }

        /// Neither side can ever mate: bare kings, a king and one minor
        /// piece, or bishops only, all on squares of one colour.
        var insufficientMaterial: Bool {
            var minors: [(kind: Int, dark: Bool)] = []
            for square in 0..<64 {
                let kind = abs(board[square])
                if kind == 0 || kind == OfflineChessRules.king { continue }
                if kind == OfflineChessRules.pawn || kind == OfflineChessRules.rook || kind == OfflineChessRules.queen {
                    return false
                }
                minors.append((kind, ((square & 7) + (square >> 3)) % 2 == 0))
            }
            if minors.count <= 1 { return true }
            return minors.allSatisfy { $0.kind == OfflineChessRules.bishop && $0.dark == minors[0].dark }
        }

        /// How the game has ended here, or nil while it goes on.
        /// `repetitions` counts this position's appearances, this one included.
        func ending(legal: [Move], repetitions: Int) -> Ending? {
            if legal.isEmpty { return inCheck ? .checkmate : .stalemate }
            if insufficientMaterial { return .insufficient }
            if halfmove >= 100 { return .fiftyMoves }
            if repetitions >= 3 { return .repetition }
            return nil
        }
    }

    /// The kind for a FEN letter, either case; nil for anything else.
    static func kind(of letter: Character) -> Int? {
        switch letter.lowercased() {
        case "p": return pawn
        case "n": return knight
        case "b": return bishop
        case "r": return rook
        case "q": return queen
        case "k": return king
        default: return nil
        }
    }

    // MARK: - Move tables

    /// Squares a knight on each square reaches.
    static let knightTargets: [[Int]] = steps([(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)])
    /// Squares a king on each square reaches (castling aside).
    static let kingTargets: [[Int]] = steps([(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)])
    /// `rays[square * 8 + direction]`: the squares outwards from `square`,
    /// nearest first. Directions 0…3 are the lines, 4…7 the diagonals.
    static let rays: [[Int]] = {
        let dirs = [(0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, 1), (1, -1), (-1, -1)]
        var out: [[Int]] = []
        for square in 0..<64 {
            for (df, dr) in dirs {
                var ray: [Int] = []
                var f = (square & 7) + df
                var r = (square >> 3) + dr
                while (0..<8).contains(f), (0..<8).contains(r) {
                    ray.append(r * 8 + f)
                    f += df
                    r += dr
                }
                out.append(ray)
            }
        }
        return out
    }()

    private static func steps(_ deltas: [(Int, Int)]) -> [[Int]] {
        (0..<64).map { square in
            deltas.compactMap { df, dr in
                let f = (square & 7) + df
                let r = (square >> 3) + dr
                return (0..<8).contains(f) && (0..<8).contains(r) ? r * 8 + f : nil
            }
        }
    }

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// Moves are being made.
        case playing
        /// The game is decided; the final board shows until `resultUntil`.
        case done
        /// The room shows the standings.
        case over
    }

    /// How a game ended. The raw values are the site's words, so the screen
    /// can use the online game's sentences.
    enum Ending: String, Codable, Equatable {
        case checkmate, stalemate, insufficient
        case fiftyMoves = "fifty-moves"
        case repetition, resigned, agreed, left

        var isDraw: Bool {
            switch self {
            case .stalemate, .insufficient, .fiftyMoves, .repetition, .agreed: return true
            case .checkmate, .resigned, .left: return false
            }
        }
    }

    /// How hard the computer player tries. Only matters with one at the table.
    enum Level: String, Codable, Equatable, CaseIterable {
        case easy, medium, hard

        var title: String {
            switch self {
            case .easy: return "Easy"
            case .medium: return "Medium"
            case .hard: return "Hard"
            }
        }
    }

    /// The last move, for every screen to mark.
    struct LastMove: Codable, Equatable {
        let from: Int
        let to: Int
        let san: String
        let by: String
    }

    struct State: Codable, Equatable {
        /// Seat order, as the room gave them.
        var players: [OfflinePlayer]
        /// Player ids: who plays White (drawn Blue) and Black (Red).
        var white: String
        var black: String
        var position: Position
        /// SAN, oldest first. Its count is the ply an action must name.
        var moves: [String] = []
        var lastMove: LastMove?
        /// How often each position has stood (`Position.repetitionKey`).
        var seen: [String: Int] = [:]
        var phase: Phase = .playing
        var resultUntil: Double = 0
        var ending: Ending?
        /// Nil for a draw.
        var winner: String?
        /// A draw offer stands until the other side moves.
        var drawOfferBy: String?
        var level: Level = .medium
        /// Piece kinds each side has taken, in the order taken.
        var takenByWhite: [Int] = []
        var takenByBlack: [Int] = []
    }

    enum Action: Codable, Equatable {
        /// Move the piece on `from` to `to` (0 = a1 … 63 = h8) at ply `ply`
        /// (the view's `ply`); `promotion` when a pawn reaches the last rank.
        case move(ply: Int, from: Int, to: Int, promotion: Promotion?)
        /// Offer a draw — or accept the one the other side is offering.
        case offerDraw
        /// Turn down the other side's offer.
        case declineDraw
        case resign
        /// How hard the computer plays.
        case level(Level)
    }

    // MARK: - What a player sees

    /// A square a piece may go to, for lighting the board. One entry per
    /// from/to pair, whatever a pawn may become there.
    struct Target: Codable, Equatable {
        let from: Int
        let to: Int
        let promotes: Bool
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        /// The board as a FEN (the screen draws it with the online board).
        let fen: String
        let white: String
        let black: String
        let whiteToMove: Bool
        /// Whose move it is while playing.
        let toMove: String?
        let check: Bool
        /// Moves made so far; an action names it.
        let ply: Int
        let moves: [String]
        let lastMove: LastMove?
        /// My legal moves when it is my move; empty otherwise.
        let targets: [Target]
        let ending: Ending?
        let winner: String?
        let drawOfferBy: String?
        let level: Level
        let takenByWhite: [Int]
        let takenByBlack: [Int]
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        let swap = rng.chance(0.5)
        let first = players.first?.id ?? ""
        let second = players.count > 1 ? players[1].id : first
        let position = Position.start
        var state = State(players: players, white: swap ? second : first, black: swap ? first : second, position: position)
        state.seen[position.repetitionKey()] = 1
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard playerId == state.white || playerId == state.black else {
            throw OfflineRefusal("You are watching this game.")
        }
        guard state.phase == .playing else { throw OfflineRefusal("The game is over.") }
        let other = playerId == state.white ? state.black : state.white
        switch action {
        case .move(let ply, let from, let to, let promotion):
            guard ply == state.moves.count else { throw OfflineRefusal("That move was for an earlier position.") }
            guard state.position.whiteToMove == (playerId == state.white) else {
                throw OfflineRefusal("It's \(name(other, in: state))'s move.")
            }
            let legal = state.position.legalMoves()
            let matches = legal.filter { $0.from == from && $0.to == to }
            guard let first = matches.first else { throw OfflineRefusal("That piece can't move there.") }
            var move = first
            if first.promotion != 0 {
                guard let promotion else { throw OfflineRefusal("Choose what the pawn becomes.") }
                guard let chosen = matches.first(where: { $0.promotion == promotion.kind }) else {
                    throw OfflineRefusal("A pawn can't become that.")
                }
                move = chosen
            }
            play(move, legal: legal, by: playerId, in: &state, now: now)
        case .offerDraw:
            if state.drawOfferBy == other {
                finish(&state, ending: .agreed, winner: nil, now: now)
            } else if state.drawOfferBy == playerId {
                throw OfflineRefusal("You have already offered a draw.")
            } else {
                state.drawOfferBy = playerId
            }
        case .declineDraw:
            guard state.drawOfferBy == other else { throw OfflineRefusal("There is no draw on offer.") }
            state.drawOfferBy = nil
        case .resign:
            finish(&state, ending: .resigned, winner: other, now: now)
        case .level(let level):
            state.level = level
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        if state.phase == .done, now >= state.resultUntil { state.phase = .over }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.phase == .playing, playerId == state.white || playerId == state.black else { return }
        finish(&state, ending: .left, winner: playerId == state.white ? state.black : state.white, now: now)
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let toMove = state.phase == .playing ? (state.position.whiteToMove ? state.white : state.black) : nil
        var targets: [Target] = []
        if let toMove, playerId == toMove {
            for move in state.position.legalMoves() where !targets.contains(where: { $0.from == move.from && $0.to == move.to }) {
                targets.append(Target(from: move.from, to: move.to, promotes: move.promotion != 0))
            }
        }
        return PlayerView(
            phase: state.phase,
            fen: state.position.fen,
            white: state.white,
            black: state.black,
            whiteToMove: state.position.whiteToMove,
            toMove: toMove,
            check: state.position.inCheck,
            ply: state.moves.count,
            moves: state.moves,
            lastMove: state.lastMove,
            targets: targets,
            ending: state.ending,
            winner: state.winner,
            drawOfferBy: state.drawOfferBy,
            level: state.level,
            takenByWhite: state.takenByWhite,
            takenByBlack: state.takenByBlack
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(state.players, score: { player in
            // A win is worth 2 and a draw 1 each, as a chess table counts
            // halves; mid-game (a drop) everyone still level shares first.
            guard let ending = state.ending else { return 1 }
            if ending.isDraw { return 1 }
            return player.id == state.winner ? 2 : 0
        }, detail: { player in
            var parts: [String] = [player.id == state.white ? "Blue (White)" : "Red (Black)"]
            if let ending = state.ending {
                if ending.isDraw {
                    parts.append(drawWord(ending))
                } else if player.id == state.winner {
                    parts.append(ending == .checkmate ? "checkmate" : ending == .resigned ? "won on resignation" : "won by default")
                } else {
                    parts.append(ending == .checkmate ? "checkmated" : ending == .resigned ? "resigned" : "left")
                }
            }
            let full = (state.moves.count + 1) / 2
            parts.append(full == 1 ? "1 move" : "\(full) moves")
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Helpers

    private static func drawWord(_ ending: Ending) -> String {
        switch ending {
        case .stalemate: return "draw by stalemate"
        case .insufficient: return "draw, bare board"
        case .fiftyMoves: return "draw, fifty moves"
        case .repetition: return "draw by repetition"
        default: return "draw agreed"
        }
    }

    private static func name(_ id: String, in state: State) -> String {
        state.players.first { $0.id == id }?.name ?? "the other player"
    }

    /// Play a checked move: the notation, the board, what was taken, and
    /// whether that ends the game.
    private static func play(_ move: Move, legal: [Move], by playerId: String, in state: inout State, now: Double) {
        let san = state.position.san(move, legal: legal)
        if move.captured != 0 {
            if state.position.whiteToMove { state.takenByWhite.append(move.captured) } else { state.takenByBlack.append(move.captured) }
        }
        state.position.make(move)
        state.moves.append(san)
        state.lastMove = LastMove(from: move.from, to: move.to, san: san, by: playerId)
        // Moving answers the other side's draw offer with a no.
        if let offer = state.drawOfferBy, offer != playerId { state.drawOfferBy = nil }
        let next = state.position.legalMoves()
        let key = state.position.repetitionKey(legal: next)
        state.seen[key, default: 0] += 1
        if let ending = state.position.ending(legal: next, repetitions: state.seen[key] ?? 1) {
            finish(&state, ending: ending, winner: ending == .checkmate ? playerId : nil, now: now)
        }
    }

    private static func finish(_ state: inout State, ending: Ending, winner: String?, now: Double) {
        state.ending = ending
        state.winner = winner
        state.drawOfferBy = nil
        state.phase = .done
        state.resultUntil = now + resultPause
    }
}
