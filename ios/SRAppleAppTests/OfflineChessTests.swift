import XCTest
@testable import SRAppleApp

/// Offline chess: the laws (proved by perft against the published counts,
/// as the site's engine is), the endings, the rules' refusals, and the
/// computer player — that it takes a mate in one at every level, wins
/// material it is offered, answers draw offers sensibly, and plays through
/// the room off the main thread.
final class OfflineChessTests: XCTestCase {
    private typealias Rules = OfflineChessRules
    private typealias Position = OfflineChessRules.Position
    private let players = [OfflinePlayer(id: "a", name: "Ann"), OfflinePlayer(id: "b", name: "Ben")]

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
    }

    // MARK: - Perft

    private func position(_ fen: String) throws -> Position {
        try XCTUnwrap(Position(fen: fen), fen)
    }

    func testPerftFromTheStart() throws {
        let start = Position.start
        XCTAssertEqual(start.perft(1), 20)
        XCTAssertEqual(start.perft(2), 400)
        XCTAssertEqual(start.perft(3), 8_902)
        XCTAssertEqual(start.perft(4), 197_281)
    }

    func testPerftKiwipete() throws {
        // Castling both ways, en passant, promotions, pins and checks.
        let kiwipete = try position("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        XCTAssertEqual(kiwipete.perft(1), 48)
        XCTAssertEqual(kiwipete.perft(2), 2_039)
        XCTAssertEqual(kiwipete.perft(3), 97_862)
    }

    func testPerftPinsAndEnPassantIntoCheck() throws {
        let three = try position("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1")
        XCTAssertEqual(three.perft(1), 14)
        XCTAssertEqual(three.perft(2), 191)
        XCTAssertEqual(three.perft(3), 2_812)
        XCTAssertEqual(three.perft(4), 43_238)
    }

    func testPerftPromotionsAndCastlingThroughAttack() throws {
        let four = try position("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1")
        XCTAssertEqual(four.perft(1), 6)
        XCTAssertEqual(four.perft(2), 264)
        XCTAssertEqual(four.perft(3), 9_467)
        let five = try position("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8")
        XCTAssertEqual(five.perft(1), 44)
        XCTAssertEqual(five.perft(2), 1_486)
        XCTAssertEqual(five.perft(3), 62_379)
    }

    func testMakeAndUnmakeLeaveThePositionAsItWas() throws {
        let kiwipete = try position("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        var copy = kiwipete
        for move in kiwipete.pseudoMoves() {
            let undo = copy.make(move)
            copy.unmake(move, undo)
            XCTAssertEqual(copy, kiwipete, "\(Rules.squareName(move.from))-\(Rules.squareName(move.to))")
        }
    }

    func testFenRoundTrips() throws {
        for fen in [Rules.startFen, "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
                    "rnbqkbnr/pppp1ppp/8/4pP2/8/8/PPPPP1PP/RNBQKBNR w KQkq e6 0 3"] {
            XCTAssertEqual(try position(fen).fen, fen)
        }
        XCTAssertNil(Position(fen: "rnbqkbnr/pppppppp/8/8 w"))
        XCTAssertNil(Position(fen: "rnbqkbnr/ppppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"))
    }

    // MARK: - Notation and endings

    private func move(_ position: Position, _ from: String, _ to: String, promotion: Int = 0) throws -> Rules.Move {
        let f = try XCTUnwrap(Rules.squareIndex(from))
        let t = try XCTUnwrap(Rules.squareIndex(to))
        return try XCTUnwrap(position.legalMoves().first { $0.from == f && $0.to == t && $0.promotion == promotion },
                             "\(from)-\(to)")
    }

    func testNotation() throws {
        let start = Position.start
        XCTAssertEqual(start.san(try move(start, "e2", "e4")), "e4")
        let castle = try position("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        XCTAssertEqual(castle.san(try move(castle, "e1", "g1")), "O-O")
        XCTAssertEqual(castle.san(try move(castle, "e1", "c1")), "O-O-O")
        let promo = try position("7k/P7/8/8/8/8/8/K7 w - - 0 1")
        XCTAssertEqual(promo.san(try move(promo, "a7", "a8", promotion: Rules.queen)), "a8=Q+")
        let fools = try position("rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2")
        XCTAssertEqual(fools.san(try move(fools, "d8", "h4")), "Qh4#")
        let rooks = try position("4k3/8/8/8/8/8/6K1/R6R w - - 0 1")
        XCTAssertEqual(rooks.san(try move(rooks, "a1", "d1")), "Rad1")
        let stack = try position("4k3/8/8/R7/8/8/8/R3K3 w - - 0 1")
        XCTAssertEqual(stack.san(try move(stack, "a1", "a3")), "R1a3")
        let queens = try position("6k1/8/8/8/Q7/8/8/Q2Q3K w - - 0 1")
        XCTAssertEqual(queens.san(try move(queens, "a1", "d4")), "Qa1d4")
        XCTAssertEqual(queens.san(try move(queens, "a4", "d4")), "Q4d4")
        XCTAssertEqual(queens.san(try move(queens, "d1", "d4")), "Qdd4")
    }

    func testEndings() throws {
        let mate = try position("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3")
        XCTAssertEqual(mate.ending(legal: mate.legalMoves(), repetitions: 1), .checkmate)
        let stalemate = try position("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        XCTAssertEqual(stalemate.ending(legal: stalemate.legalMoves(), repetitions: 1), .stalemate)
        let bare = try position("7k/8/6K1/8/8/8/8/5N2 w - - 0 1")
        XCTAssertEqual(bare.ending(legal: bare.legalMoves(), repetitions: 1), .insufficient)
        XCTAssertTrue(try position("7k/8/6K1/8/8/4B3/8/2B5 w - - 0 1").insufficientMaterial, "bishops on one colour")
        XCTAssertFalse(try position("7k/8/6K1/8/8/8/8/2B2B2 w - - 0 1").insufficientMaterial)
        let fifty = try position("7k/8/6K1/8/8/8/8/R7 w - - 100 80")
        XCTAssertEqual(fifty.ending(legal: fifty.legalMoves(), repetitions: 1), .fiftyMoves)
        XCTAssertEqual(Position.start.ending(legal: Position.start.legalMoves(), repetitions: 3), .repetition)
        XCTAssertNil(Position.start.ending(legal: Position.start.legalMoves(), repetitions: 2))
    }

    func testAPinnedPieceStaysPut() throws {
        let pinned = try position("4k3/8/8/b7/8/8/3N4/4K3 w - - 0 1")
        XCTAssertTrue(pinned.legalMoves().allSatisfy { $0.from != Rules.squareIndex("d2") })
    }

    // MARK: - The rules

    private func start(seed: UInt64 = 1) -> (Rules.State, OfflineRNG) {
        var rng = OfflineRNG(seed: seed)
        let state = Rules.start(players: players, now: 0, rng: &rng)
        return (state, rng)
    }

    private func play(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ from: String, _ to: String,
                      promotion: Rules.Promotion? = nil, now: Double = 1) throws {
        let mover = state.position.whiteToMove ? state.white : state.black
        try Rules.apply(.move(ply: state.moves.count, from: XCTUnwrap(Rules.squareIndex(from)),
                              to: XCTUnwrap(Rules.squareIndex(to)), promotion: promotion),
                        by: mover, to: &state, now: now, rng: &rng)
    }

    private func refusal(_ action: Rules.Action, by id: String, _ state: Rules.State) -> String? {
        var copy = state
        var rng = OfflineRNG(seed: 0)
        do {
            try Rules.apply(action, by: id, to: &copy, now: 1, rng: &rng)
            return nil
        } catch {
            return (error as? OfflineRefusal)?.reason
        }
    }

    func testTheStartSeatsBothSidesAndDrawsColours() {
        var whites: Set<String> = []
        for seed in 1...12 {
            let (state, _) = start(seed: UInt64(seed))
            XCTAssertEqual(Set([state.white, state.black]), ["a", "b"])
            XCTAssertEqual(state.position, Position.start)
            whites.insert(state.white)
        }
        XCTAssertEqual(whites, ["a", "b"], "either player can draw White")
    }

    func testFoolsMateThroughTheRules() throws {
        var (state, rng) = start()
        try play(&state, &rng, "f2", "f3")
        try play(&state, &rng, "e7", "e5")
        try play(&state, &rng, "g2", "g4")
        try play(&state, &rng, "d8", "h4", now: 5)
        XCTAssertEqual(state.moves, ["f3", "e5", "g4", "Qh4#"])
        XCTAssertEqual(state.phase, .done)
        XCTAssertEqual(state.ending, .checkmate)
        XCTAssertEqual(state.winner, state.black)
        XCTAssertFalse(Rules.isOver(state))
        Rules.tick(&state, now: 5 + Rules.resultPause, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), [state.black, state.white])
        XCTAssertEqual(table.map(\.rank), [1, 2])
        XCTAssertEqual(table.first?.detail, "Red (Black) · checkmate · 2 moves")
    }

    func testRefusals() throws {
        var (state, rng) = start()
        let white = state.white
        let black = state.black
        let e2 = Rules.squareIndex("e2")!
        XCTAssertEqual(refusal(.move(ply: 0, from: e2, to: Rules.squareIndex("e4")!, promotion: nil), by: black, state),
                       "It's \(white == "a" ? "Ann" : "Ben")'s move.")
        XCTAssertEqual(refusal(.move(ply: 0, from: e2, to: Rules.squareIndex("e5")!, promotion: nil), by: white, state),
                       "That piece can't move there.")
        XCTAssertEqual(refusal(.move(ply: 3, from: e2, to: Rules.squareIndex("e4")!, promotion: nil), by: white, state),
                       "That move was for an earlier position.")
        XCTAssertEqual(refusal(.resign, by: "z", state), "You are watching this game.")
        XCTAssertEqual(refusal(.declineDraw, by: white, state), "There is no draw on offer.")

        // A pawn on the seventh must be told what to become.
        state.position = try position("7k/P7/8/8/8/8/8/K7 w - - 0 1")
        let a7 = Rules.squareIndex("a7")!
        let a8 = Rules.squareIndex("a8")!
        XCTAssertEqual(refusal(.move(ply: 0, from: a7, to: a8, promotion: nil), by: white, state), "Choose what the pawn becomes.")
        try play(&state, &rng, "a7", "a8", promotion: .knight)
        XCTAssertEqual(state.position.board[a8], Rules.knight)
        XCTAssertEqual(state.moves.last, "a8=N")
    }

    func testDrawOffersStandUntilTheOtherSideMoves() throws {
        var (state, rng) = start()
        let white = state.white
        let black = state.black
        try Rules.apply(.offerDraw, by: white, to: &state, now: 1, rng: &rng)
        XCTAssertEqual(state.drawOfferBy, white)
        XCTAssertEqual(refusal(.offerDraw, by: white, state), "You have already offered a draw.")
        try play(&state, &rng, "e2", "e4")
        XCTAssertEqual(state.drawOfferBy, white, "the offerer's own move keeps it")
        try play(&state, &rng, "e7", "e5")
        XCTAssertNil(state.drawOfferBy, "the other side moving turns it down")

        try Rules.apply(.offerDraw, by: black, to: &state, now: 2, rng: &rng)
        try Rules.apply(.declineDraw, by: white, to: &state, now: 2, rng: &rng)
        XCTAssertNil(state.drawOfferBy)
        try Rules.apply(.offerDraw, by: black, to: &state, now: 3, rng: &rng)
        try Rules.apply(.offerDraw, by: white, to: &state, now: 3, rng: &rng)
        XCTAssertEqual(state.ending, .agreed)
        XCTAssertNil(state.winner)
        XCTAssertEqual(Rules.standings(state).map(\.rank), [1, 1], "a draw shares first")
    }

    func testRepetitionDraws() throws {
        var (state, rng) = start()
        for _ in 0..<2 {
            try play(&state, &rng, "g1", "f3")
            try play(&state, &rng, "g8", "f6")
            try play(&state, &rng, "f3", "g1")
            try play(&state, &rng, "f6", "g8")
        }
        XCTAssertEqual(state.ending, .repetition)
        XCTAssertEqual(state.phase, .done)
    }

    func testResignAndLeaving() throws {
        var (state, rng) = start()
        let white = state.white
        try Rules.apply(.resign, by: white, to: &state, now: 1, rng: &rng)
        XCTAssertEqual(state.ending, .resigned)
        XCTAssertEqual(state.winner, state.black)

        var (other, rng2) = start()
        Rules.playerLeft(other.black, state: &other, now: 1, rng: &rng2)
        XCTAssertEqual(other.ending, .left)
        XCTAssertEqual(other.winner, other.white)
        XCTAssertEqual(Rules.standings(other).first?.detail, "Blue (White) · won by default · 0 moves")
    }

    func testOnlyTheMoverIsSentTheirMoves() throws {
        let (state, _) = start()
        let mine = Rules.view(of: state, for: state.white)
        XCTAssertEqual(mine.targets.count, 20)
        XCTAssertEqual(mine.toMove, state.white)
        XCTAssertTrue(Rules.view(of: state, for: state.black).targets.isEmpty)
        XCTAssertTrue(Rules.view(of: state, for: nil).targets.isEmpty)
        // A promotion square is listed once, marked.
        var promo = state
        promo.position = try position("7k/P7/8/8/8/8/8/K7 w - - 0 1")
        let targets = Rules.view(of: promo, for: promo.white).targets
        XCTAssertEqual(targets.filter { $0.from == Rules.squareIndex("a7") }.count, 1)
        XCTAssertTrue(targets.first { $0.from == Rules.squareIndex("a7") }?.promotes == true)
    }

    // MARK: - The computer player

    private func state(fen: String, level: Rules.Level, botIsWhite: Bool = true) throws -> Rules.State {
        var (state, _) = start()
        state.white = botIsWhite ? "bot" : "a"
        state.black = botIsWhite ? "a" : "bot"
        state.players = [OfflinePlayer(id: "a", name: "Ann"), OfflinePlayer(id: "bot", name: "Robo")]
        state.position = try position(fen)
        state.level = level
        return state
    }

    func testEveryLevelTakesAMateInOne() throws {
        let mates = [
            ("6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "a1", "a8"),                               // back rank
            ("r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4", "h5", "f7"), // scholar's
        ]
        for (fen, from, to) in mates {
            for level in Rules.Level.allCases {
                for seed in [UInt64(1), 2, 3] {
                    let s = try state(fen: fen, level: level)
                    let move = Rules.botMove(s, seed: seed)
                    XCTAssertEqual(move.map { Rules.squareName($0.from) + Rules.squareName($0.to) }, from + to,
                                   "\(level) seed \(seed): \(fen)")
                }
            }
        }
    }

    func testItTakesAHangingQueenAndKeepsItsOwn() throws {
        // Black's queen on d4 hangs to the knight on f3.
        let hanging = try state(fen: "rnb1kbnr/pppp1ppp/8/4p3/3q4/5N2/PPPPPPPP/RNBQKB1R w KQkq - 0 3", level: .medium)
        let take = Rules.botMove(hanging, seed: 1)
        XCTAssertEqual(take.map { Rules.squareName($0.from) + Rules.squareName($0.to) }, "f3d4")
        // White's queen on h5 is attacked by the knight on f6: Hard moves it.
        let attacked = try state(fen: "rnbqkb1r/pppp1ppp/5n2/4p2Q/4P3/8/PPPP1PPP/RNB1KBNR w KQkq - 2 3", level: .hard)
        let away = try XCTUnwrap(Rules.botMove(attacked, seed: 1))
        XCTAssertEqual(Rules.squareName(away.from), "h5", "the queen steps out of the knight's reach")
    }

    func testTheBotOnlyMovesOnItsTurnAndAnswersDrawOffers() throws {
        var s = try state(fen: Rules.startFen, level: .easy, botIsWhite: false)
        var rng = OfflineRNG(seed: 4)
        XCTAssertTrue(Rules.botActions(s, for: "bot", rng: &rng).isEmpty, "White (Ann) to move")
        XCTAssertTrue(Rules.botActions(s, for: "zed", rng: &rng).isEmpty)
        s.drawOfferBy = "a"
        XCTAssertEqual(Rules.botActions(s, for: "bot", rng: &rng), [.declineDraw], "level: no draw")
        // A rook down, it takes the draw.
        s.position = try position("4k3/8/8/8/8/8/8/R3K3 w - - 0 1")
        XCTAssertEqual(Rules.botActions(s, for: "bot", rng: &rng), [.offerDraw])
    }

    func testTheThinkerAnswersOffTheCallersThread() throws {
        let s = try state(fen: "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", level: .hard)
        let request = OfflineChessThinker.Request(position: s.position, level: .hard, seed: 9, avoid: [])
        let move = OfflineChessThinker.shared.waitForAnswer(request)
        XCTAssertEqual(move.map { Rules.squareName($0.from) + Rules.squareName($0.to) }, "a1a8")
        // Asked again, the answer is ready at once.
        XCTAssertEqual(OfflineChessThinker.shared.answer(request), move)
    }

    func testAWholeGameAgainstTheComputerThroughTheRoom() throws {
        var room = OfflineRoom(host: OfflinePlayer(id: "h", name: "Hana"), roomName: "Solo",
                               games: [OfflineGameEntry(withBot: Rules.self)])
        try room.choose("chess")
        let bot = try room.addBot()
        try room.start(seed: 3, now: 1_000)
        var now = 1_000.0
        var botMoves = 0
        var turns = 0
        // The host plays its first legal move each time; the bot thinks off
        // this thread, so give it real time between ticks.
        while room.phase == .playing && turns < 30 {
            turns += 1
            let view = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "h")))
            if view.toMove == "h", let target = view.targets.first {
                let action = Rules.Action.move(ply: view.ply, from: target.from, to: target.to,
                                               promotion: target.promotes ? .queen : nil)
                try room.act(OfflineCoding.encode(action), by: "h", match: room.matchNumber, now: now)
            } else if view.toMove == bot {
                let deadline = Date().addingTimeInterval(10)
                while room.phase == .playing, Date() < deadline {
                    now += OfflineRoom.botRetry
                    room.tick(now: now)
                    guard let data = room.currentView(for: "h") else { break }
                    let after = try OfflineCoding.decode(Rules.PlayerView.self, from: data)
                    if after.ply > view.ply {
                        botMoves += 1
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.02)
                }
            } else {
                break
            }
        }
        XCTAssertGreaterThanOrEqual(botMoves, 3, "the bot moved through the room's ticks")
    }
}
