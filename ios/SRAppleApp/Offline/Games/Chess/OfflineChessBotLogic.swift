import Foundation

/// Chess's computer player, for solo play and a spare seat.
///
/// A small engine: an alpha-beta search over the rules' own move generator,
/// deepened one ply at a time, with a capture search at the leaves so it
/// never stops looking in the middle of an exchange, judging positions by
/// material, where each piece stands (the well-known "simplified evaluation"
/// tables) and how many squares its pieces reach. Three levels:
///
/// - Easy looks one move ahead and adds a good handful of noise to its
///   scores, so it keeps its pieces safe but drifts and misses plans.
/// - Medium looks two moves ahead with a little noise.
/// - Hard looks three moves ahead with almost none, and a fourth when the
///   time allows.
///
/// Every level takes a mate it can see. Each search is time-boxed (Easy
/// 0.3 s, Medium 0.6 s, Hard 0.9 s): a deeper pass that runs out of time is
/// thrown away and the last finished one stands. In a Release build three
/// moves ahead takes well under a tenth of a second on a middle game, and
/// four from a tenth to about a second.
///
/// The search runs OFF THE MAIN THREAD. The room asks a bot for its move on
/// the host's ten-a-second tick, on the main actor, and a search must not
/// freeze the board while it thinks; so `botActions` hands the position to
/// `OfflineChessThinker`, which searches on a background queue and answers
/// "nothing yet" until the move is ready. The room looks again shortly
/// (`OfflineRoom.botRetry`), finds the answer, and plays it through `apply`
/// like any other move.
extension OfflineChessRules: OfflineBotRules {
    static func botActions(_ state: State, for playerId: String, rng: inout OfflineRNG) -> [Action] {
        guard state.phase == .playing, playerId == state.white || playerId == state.black else { return [] }
        let white = playerId == state.white
        // An offer on the table is answered first, on or off its move.
        if let offer = state.drawOfferBy, offer != playerId {
            return [Engine.wantsDraw(state.position, asWhite: white) ? .offerDraw : .declineDraw]
        }
        guard state.position.whiteToMove == white else { return [] }
        let request = OfflineChessThinker.Request(
            position: state.position,
            level: state.level,
            seed: rng.next(),
            avoid: Set(state.seen.filter { $0.value >= 2 }.keys)
        )
        guard let best = OfflineChessThinker.shared.answer(request) else { return [] }
        return candidates(best, state: state)
    }

    /// The engine's move first, then every other legal move, so a bot whose
    /// answer is somehow refused still moves rather than stalling the game.
    static func candidates(_ best: Move, state: State) -> [Action] {
        let ply = state.moves.count
        let others = state.position.legalMoves().filter { $0 != best }
        return ([best] + others).map { move in
            .move(ply: ply, from: move.from, to: move.to, promotion: promotion(for: move.promotion))
        }
    }

    static func promotion(for kind: Int) -> Promotion? {
        Promotion.allCases.first { $0.kind == kind }
    }

    /// The engine's move for `state` straight away, on this thread — for
    /// tests, and a reference for what the thinker does.
    static func botMove(_ state: State, seed: UInt64, nodeLimit: Int = 150_000) -> Move? {
        Engine.bestMove(state.position, level: state.level, seed: seed,
                        avoid: Set(state.seen.filter { $0.value >= 2 }.keys), nodeLimit: nodeLimit)
    }

    // MARK: - The engine

    enum Engine {
        /// A mate's score, less the plies it takes (a nearer mate is better).
        static let mate = 100_000
        static let infinity = 1_000_000

        /// How deep each level may search, how much noise it adds to the
        /// root's scores (centipawns, either way) and how long it may take.
        static func depth(_ level: Level) -> Int {
            switch level {
            case .easy: return 1
            case .medium: return 2
            case .hard: return 4
            }
        }

        static func noise(_ level: Level) -> Int {
            switch level {
            case .easy: return 120
            case .medium: return 30
            case .hard: return 6
            }
        }

        static func seconds(_ level: Level) -> Double {
            switch level {
            case .easy: return 0.3
            case .medium: return 0.6
            case .hard: return 0.9
            }
        }

        /// The move to play, or nil when there is none. `avoid` holds the
        /// repetition keys already seen twice: a move into one is scored a
        /// draw. With `deadline` and `clock`, a deeper pass that runs past
        /// the deadline is abandoned (the first pass always finishes);
        /// `nodeLimit` caps the work regardless, so a test is repeatable.
        static func bestMove(_ position: Position, level: Level, seed: UInt64, avoid: Set<String> = [],
                             deadline: Double? = nil, clock: (() -> Double)? = nil,
                             nodeLimit: Int = 2_000_000) -> Move? {
            let legal = position.legalMoves()
            guard legal.count > 1 else { return legal.first }
            var rng = OfflineRNG(seed: seed)
            let spread = noise(level)
            // Each root move with its noise and whether it walks into a third repetition.
            var root: [(move: Move, noise: Int, repeats: Bool)] = legal.map { move in
                let next = position.playing(move)
                return (move, spread > 0 ? rng.int(in: -spread...spread) : 0,
                        !avoid.isEmpty && avoid.contains(next.repetitionKey()))
            }
            root.sort { orderKey($0.move) > orderKey($1.move) }

            let search = Search(position: position, nodeLimit: nodeLimit, deadline: deadline, clock: clock)
            var finished: [Int]?
            for d in 1...depth(level) {
                // Only the first pass is sure to finish.
                search.mayStop = d > 1
                var scores = Array(repeating: -infinity, count: root.count)
                var alpha = -infinity
                for (i, entry) in root.enumerated() {
                    // Moves within twice the noise of the best are scored
                    // exactly, so the noise can choose between them; the
                    // rest only need proving worse.
                    let floor = alpha == -infinity ? -infinity : alpha - 2 * spread - 1
                    let score: Int
                    if entry.repeats {
                        score = 0
                    } else {
                        let undo = search.position.make(entry.move)
                        score = -search.negamax(depth: d - 1, alpha: -infinity, beta: -floor, ply: 1)
                        search.position.unmake(entry.move, undo)
                    }
                    if search.stopped { break }
                    scores[i] = score
                    alpha = max(alpha, score)
                }
                if search.stopped { break }
                // Best first for the next pass: better cut-offs.
                let order = scores.indices.sorted { scores[$0] > scores[$1] }
                root = order.map { root[$0] }
                finished = order.map { scores[$0] }
            }
            guard let scores = finished else { return root.first?.move }
            var pick = 0
            for i in root.indices where scores[i] + root[i].noise > scores[pick] + root[pick].noise {
                pick = i
            }
            return root[pick].move
        }

        /// Whether the side `asWhite` names would take a draw here: when it
        /// is clearly behind on the board.
        static func wantsDraw(_ position: Position, asWhite white: Bool) -> Bool {
            var view = position
            view.whiteToMove = white
            return evaluate(view) <= -150
        }

        /// Captures first, most valuable victim by least valuable attacker,
        /// then promotions, then everything else.
        static func orderKey(_ move: Move) -> Int {
            if move.captured != 0 { return 10_000 + value[move.captured] * 10 - value[move.piece] / 10 }
            if move.promotion != 0 { return 9_000 + value[move.promotion] }
            return 0
        }

        /// The search's working state: one position, made and unmade in place.
        final class Search {
            var position: Position
            var nodes = 0
            var stopped = false
            var mayStop = false
            let nodeLimit: Int
            let deadline: Double?
            let clock: (() -> Double)?

            init(position: Position, nodeLimit: Int, deadline: Double?, clock: (() -> Double)?) {
                self.position = position
                self.nodeLimit = nodeLimit
                self.deadline = deadline
                self.clock = clock
            }

            /// Count a node; stop once the budget or the time is spent.
            private func tick() {
                nodes += 1
                guard mayStop, !stopped else { return }
                if nodes >= nodeLimit { stopped = true }
                if nodes & 1023 == 0, let deadline, let clock, clock() >= deadline { stopped = true }
            }

            func negamax(depth: Int, alpha alphaIn: Int, beta: Int, ply: Int) -> Int {
                tick()
                if stopped { return 0 }
                let check = position.inCheck
                // At the horizon, a quiet look at the captures — unless in
                // check, where every way out is searched so mate is seen.
                if depth <= 0 && !check { return quiesce(alpha: alphaIn, beta: beta, ply: ply) }
                if ply >= 48 { return Engine.evaluate(position) }
                var alpha = alphaIn
                let white = position.whiteToMove
                var any = false
                for move in position.pseudoMoves().sorted(by: { Engine.orderKey($0) > Engine.orderKey($1) }) {
                    let undo = position.make(move)
                    let k = white ? position.whiteKing : position.blackKing
                    if k >= 0 && position.attacked(k, byWhite: !white) {
                        position.unmake(move, undo)
                        continue
                    }
                    any = true
                    let score = -negamax(depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1)
                    position.unmake(move, undo)
                    if stopped { return 0 }
                    if score >= beta { return beta }
                    if score > alpha { alpha = score }
                }
                if !any { return check ? -(Engine.mate - ply) : 0 }
                return alpha
            }

            /// Captures (and promotions) only, until the position is quiet:
            /// the side to move may always stop and take the position as it is.
            func quiesce(alpha alphaIn: Int, beta: Int, ply: Int) -> Int {
                tick()
                if stopped { return 0 }
                let stand = Engine.evaluate(position)
                if stand >= beta { return beta }
                if ply >= 24 { return stand }
                var alpha = max(alphaIn, stand)
                let white = position.whiteToMove
                for move in position.pseudoMoves(capturesOnly: true).sorted(by: { Engine.orderKey($0) > Engine.orderKey($1) }) {
                    let undo = position.make(move)
                    let k = white ? position.whiteKing : position.blackKing
                    if k >= 0 && position.attacked(k, byWhite: !white) {
                        position.unmake(move, undo)
                        continue
                    }
                    let score: Int
                    if position.inCheck {
                        // A capture that gives check: see the replies in full.
                        score = -negamax(depth: 0, alpha: -beta, beta: -alpha, ply: ply + 1)
                    } else {
                        score = -quiesce(alpha: -beta, beta: -alpha, ply: ply + 1)
                    }
                    position.unmake(move, undo)
                    if stopped { return 0 }
                    if score >= beta { return beta }
                    if score > alpha { alpha = score }
                }
                return alpha
            }
        }

        // MARK: Judging a position

        /// Centipawns by kind (index 1…6).
        static let value = [0, 100, 320, 330, 500, 900, 0]

        /// The position's worth to the side to move, in centipawns.
        static func evaluate(_ position: Position) -> Int {
            let board = position.board
            var score = 0
            // Pieces other than pawns and kings, each side: few means an endgame.
            var whitePieces = 0
            var blackPieces = 0
            var whiteBishops = 0
            var blackBishops = 0
            for square in 0..<64 {
                let p = board[square]
                guard p != 0, abs(p) != OfflineChessRules.king, abs(p) != OfflineChessRules.pawn else { continue }
                if p > 0 { whitePieces += value[p] } else { blackPieces += value[-p] }
                if p == OfflineChessRules.bishop { whiteBishops += 1 }
                if p == -OfflineChessRules.bishop { blackBishops += 1 }
            }
            let endgame = whitePieces <= 1_300 && blackPieces <= 1_300
            let rays = OfflineChessRules.rays
            for square in 0..<64 {
                let p = board[square]
                guard p != 0 else { continue }
                let kind = abs(p)
                let white = p > 0
                // The tables are drawn from White's side, rank 8 on top.
                let index = white ? (7 - (square >> 3)) * 8 + (square & 7) : square
                var here = value[kind]
                switch kind {
                case OfflineChessRules.pawn: here += pawnTable[index]
                case OfflineChessRules.knight:
                    here += knightTable[index]
                    var reach = 0
                    for t in OfflineChessRules.knightTargets[square] where board[t] == 0 || (board[t] > 0) != white { reach += 1 }
                    here += reach * 4
                case OfflineChessRules.bishop, OfflineChessRules.rook, OfflineChessRules.queen:
                    here += kind == OfflineChessRules.bishop ? bishopTable[index]
                        : kind == OfflineChessRules.rook ? rookTable[index] : queenTable[index]
                    let dirs = kind == OfflineChessRules.bishop ? 4..<8 : kind == OfflineChessRules.rook ? 0..<4 : 0..<8
                    var reach = 0
                    for dir in dirs {
                        for t in rays[square * 8 + dir] {
                            let q = board[t]
                            if q == 0 {
                                reach += 1
                                continue
                            }
                            if (q > 0) != white { reach += 1 }
                            break
                        }
                    }
                    here += reach * (kind == OfflineChessRules.bishop ? 4 : kind == OfflineChessRules.rook ? 2 : 1)
                default:
                    here += endgame ? kingEndTable[index] : kingTable[index]
                }
                score += white ? here : -here
            }
            if whiteBishops >= 2 { score += 30 }
            if blackBishops >= 2 { score -= 30 }
            return position.whiteToMove ? score : -score
        }

        // Piece-square tables, from White's side with rank 8 on the top row.
        static let pawnTable = [
            0, 0, 0, 0, 0, 0, 0, 0,
            50, 50, 50, 50, 50, 50, 50, 50,
            10, 10, 20, 30, 30, 20, 10, 10,
            5, 5, 10, 25, 25, 10, 5, 5,
            0, 0, 0, 20, 20, 0, 0, 0,
            5, -5, -10, 0, 0, -10, -5, 5,
            5, 10, 10, -20, -20, 10, 10, 5,
            0, 0, 0, 0, 0, 0, 0, 0,
        ]
        static let knightTable = [
            -50, -40, -30, -30, -30, -30, -40, -50,
            -40, -20, 0, 0, 0, 0, -20, -40,
            -30, 0, 10, 15, 15, 10, 0, -30,
            -30, 5, 15, 20, 20, 15, 5, -30,
            -30, 0, 15, 20, 20, 15, 0, -30,
            -30, 5, 10, 15, 15, 10, 5, -30,
            -40, -20, 0, 5, 5, 0, -20, -40,
            -50, -40, -30, -30, -30, -30, -40, -50,
        ]
        static let bishopTable = [
            -20, -10, -10, -10, -10, -10, -10, -20,
            -10, 0, 0, 0, 0, 0, 0, -10,
            -10, 0, 5, 10, 10, 5, 0, -10,
            -10, 5, 5, 10, 10, 5, 5, -10,
            -10, 0, 10, 10, 10, 10, 0, -10,
            -10, 10, 10, 10, 10, 10, 10, -10,
            -10, 5, 0, 0, 0, 0, 5, -10,
            -20, -10, -10, -10, -10, -10, -10, -20,
        ]
        static let rookTable = [
            0, 0, 0, 0, 0, 0, 0, 0,
            5, 10, 10, 10, 10, 10, 10, 5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            0, 0, 0, 5, 5, 0, 0, 0,
        ]
        static let queenTable = [
            -20, -10, -10, -5, -5, -10, -10, -20,
            -10, 0, 0, 0, 0, 0, 0, -10,
            -10, 0, 5, 5, 5, 5, 0, -10,
            -5, 0, 5, 5, 5, 5, 0, -5,
            0, 0, 5, 5, 5, 5, 0, -5,
            -10, 5, 5, 5, 5, 5, 0, -10,
            -10, 0, 5, 0, 0, 0, 0, -10,
            -20, -10, -10, -5, -5, -10, -10, -20,
        ]
        static let kingTable = [
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -20, -30, -30, -40, -40, -30, -30, -20,
            -10, -20, -20, -20, -20, -20, -20, -10,
            20, 20, 0, 0, 0, 0, 20, 20,
            20, 30, 10, 0, 0, 10, 30, 20,
        ]
        static let kingEndTable = [
            -50, -40, -30, -20, -20, -30, -40, -50,
            -30, -20, -10, 0, 0, -10, -20, -30,
            -30, -10, 20, 30, 30, 20, -10, -30,
            -30, -10, 30, 40, 40, 30, -10, -30,
            -30, -10, 30, 40, 40, 30, -10, -30,
            -30, -10, 20, 30, 30, 20, -10, -30,
            -30, -30, 0, 0, 0, 0, -30, -30,
            -50, -30, -30, -30, -30, -30, -30, -50,
        ]
    }
}

/// Runs the chess engine on a background queue, so the host's main thread —
/// which ticks the room and draws the board — never waits on a search.
///
/// `answer` is called on every look the room's bot takes. The first look at
/// a position starts its search and answers nil; later looks answer nil while
/// it runs and the move once it is done. Answers are kept by position and
/// level (a handful, the newest), so asking again is free and a stale search
/// finishing late cannot be played into a different position.
final class OfflineChessThinker: @unchecked Sendable {
    static let shared = OfflineChessThinker()

    /// One position to think about.
    struct Request {
        let position: OfflineChessRules.Position
        let level: OfflineChessRules.Level
        /// For the level's noise: a different game each time.
        let seed: UInt64
        /// Repetition keys already seen twice (a third time is a draw).
        let avoid: Set<String>

        var key: String { "\(level.rawValue) \(position.fen)" }
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "offline-chess-engine", qos: .userInitiated)
    private var running: Set<String> = []
    private var answers: [String: OfflineChessRules.Move] = [:]
    private var order: [String] = []

    /// The move for `request` if its search has finished; otherwise nil,
    /// starting the search if it is not already running.
    func answer(_ request: Request) -> OfflineChessRules.Move? {
        let key = request.key
        lock.lock()
        defer { lock.unlock() }
        if let move = answers[key] { return move }
        guard !running.contains(key) else { return nil }
        running.insert(key)
        queue.async { [self] in
            let clock = { ProcessInfo.processInfo.systemUptime }
            let move = OfflineChessRules.Engine.bestMove(
                request.position, level: request.level, seed: request.seed, avoid: request.avoid,
                deadline: clock() + OfflineChessRules.Engine.seconds(request.level), clock: clock
            )
            self.store(move, for: key)
        }
        return nil
    }

    /// Wait (off the main thread only — tests) until `request` has an answer.
    func waitForAnswer(_ request: Request, timeout: Double = 10) -> OfflineChessRules.Move? {
        let until = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < until {
            if let move = answer(request) { return move }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }

    private func store(_ move: OfflineChessRules.Move?, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        running.remove(key)
        guard let move else { return }
        answers[key] = move
        order.append(key)
        while order.count > 8 {
            answers[order.removeFirst()] = nil
        }
    }
}
