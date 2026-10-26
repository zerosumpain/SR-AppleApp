import XCTest
@testable import SRAppleApp

/// Chess: the spec's wire contract, the board from a FEN, and the little the
/// phone works out itself — where a tap may go, the clocks, the sentence for
/// how a game ended.
final class ChessTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    // MARK: - The wire (the spec's JSON)

    private let playingJSON = #"""
    { "id":"g_c", "game":"chess", "difficulty":"medium", "phase":"playing",
      "hostId":"p_a", "meId":"p_b", "mainMs":600000, "incrementMs":5000, "rule":"10 min each · +5 s a move",
      "startedAt":1790000000000, "phaseEndsAt":1790000590000,
      "fen":"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
      "turn":"b", "turnId":"p_b", "turnStartedAt":1790000010000, "check":false,
      "whiteId":"p_a", "blackId":"p_b", "clocks":{"w":603000,"b":600000},
      "moves":["e4"], "lastMove":{"from":"e2","to":"e4"},
      "captured":{"w":[],"b":[]},
      "legal":[{"from":"e7","to":"e5","promotes":false},{"from":"e7","to":"e6","promotes":false},{"from":"g8","to":"f6","promotes":false}],
      "drawOfferBy":null, "result":null,
      "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"seated":true,"colour":"w","clockMs":603000},
                 {"id":"p_b","name":"John","status":"joined","isHost":false,"seated":true,"colour":"b","clockMs":600000}],
      "standings":null, "winnerIds":[], "serverNow":1790000014000 }
    """#

    func testAPlayingRoomDecodesFromTheContract() throws {
        let room = try decode(playingJSON)
        XCTAssertEqual(room.kind, .chess)
        XCTAssertEqual(room.phase, .playing)
        XCTAssertEqual(ChessScreenPhase.of(room), .playing)
        let state = try XCTUnwrap(room.chess)
        XCTAssertEqual(state.phase, .playing)
        XCTAssertEqual(state.mainMs, 600_000)
        XCTAssertEqual(state.incrementMs, 5_000)
        XCTAssertEqual(state.turn, .black)
        XCTAssertEqual(state.turnId, "p_b")
        XCTAssertEqual(state.whiteId, "p_a")
        XCTAssertEqual(state.colour(of: "p_b"), .black)
        XCTAssertEqual(state.moves, ["e4"])
        XCTAssertEqual(state.lastMove, ChessLastMove(from: "e2", to: "e4"))
        XCTAssertEqual(state.legal.count, 3)
        XCTAssertEqual(state.board[ChessSquare(name: "e4")!], ChessPiece(colour: .white, kind: .pawn))
        XCTAssertNil(state.board[ChessSquare(name: "e2")!])
        XCTAssertEqual(state.board.pieceCount, 32)
        XCTAssertEqual(state.seat("p_a")?.clockMs, 603_000)
        XCTAssertNil(state.result)
        XCTAssertNil(state.checkedKing)
    }

    func testTheClocksRunOnlyForTheSideToMove() throws {
        let state = try XCTUnwrap(try decode(playingJSON).chess)
        // Black's turn began at 10 s; at 14 s four seconds have gone.
        XCTAssertEqual(state.remaining(.black, now: 1_790_000_014_000), 596_000)
        XCTAssertEqual(state.remaining(.white, now: 1_790_000_014_000), 603_000, "white's clock is stopped")
        XCTAssertEqual(state.remaining(.black, now: nil), 600_000, "no clock yet: the server's figure")
        XCTAssertEqual(state.remaining(.black, now: 1_790_001_000_000), 0, "never below zero")
    }

    func testTargetsComeFromTheLegalList() throws {
        let state = try XCTUnwrap(try decode(playingJSON).chess)
        XCTAssertEqual(state.targets(from: ChessSquare(name: "e7")!).map(\.to), ["e5", "e6"])
        XCTAssertEqual(state.targets(from: ChessSquare(name: "a7")!).count, 0)
        XCTAssertEqual(state.movable, ["e7", "g8"])
    }

    private let finishedJSON = #"""
    { "id":"g_d", "game":"chess", "difficulty":"hard", "phase":"finished",
      "hostId":"p_a", "meId":"p_a", "mainMs":300000, "incrementMs":3000,
      "fen":"rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3",
      "turn":"w", "turnId":null, "turnStartedAt":null, "check":true,
      "whiteId":"p_a", "blackId":"p_b", "clocks":{"w":280000,"b":291000},
      "moves":["f3","e5","g4","Qh4#"], "lastMove":{"from":"d8","to":"h4"},
      "captured":{"w":[],"b":[]}, "legal":[], "drawOfferBy":null,
      "result":{"outcome":"checkmate","winnerId":"p_b"},
      "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"seated":true,"colour":"w","clockMs":280000},
                 {"id":"p_b","name":"John","status":"joined","isHost":false,"seated":true,"colour":"b","clockMs":291000}],
      "standings":[{"id":"p_b","name":"John","place":1,"colour":"b","result":"won","clockMs":291000},
                   {"id":"p_a","name":"Sam","place":2,"colour":"w","result":"lost","clockMs":280000}],
      "winnerIds":["p_b"], "serverNow":1790000100000 }
    """#

    func testAFinishDecodesWithTheResultAndTheMatedKing() throws {
        let room = try decode(finishedJSON)
        XCTAssertEqual(ChessScreenPhase.of(room), .finished)
        XCTAssertEqual(room.winnerIds, ["p_b"])
        XCTAssertEqual(room.standings?.map(\.id), ["p_b", "p_a"])
        let state = try XCTUnwrap(room.chess)
        XCTAssertEqual(state.result, ChessResult(outcome: "checkmate", winnerId: "p_b"))
        XCTAssertTrue(state.check)
        XCTAssertEqual(state.checkedKing, ChessSquare(name: "e1"))
        XCTAssertEqual(state.loserId, "p_a")
        XCTAssertEqual(state.outcomeLine { $0 == "p_a" ? "You" : "John" }, "Checkmate — John wins.")
        XCTAssertEqual(state.standings?.first?.result, "won")
    }

    func testAnotherGamesRoomCarriesNoChess() throws {
        let room = try decode(#"{"id":"g_t","game":"tap-duel","phase":"lobby","serverNow":1}"#)
        XCTAssertNil(room.chess)
    }

    // MARK: - The board

    func testTheStartPositionReadsFromItsFEN() {
        let board = ChessBoard(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        XCTAssertEqual(board.pieceCount, 32)
        XCTAssertEqual(board[ChessSquare(name: "a1")!], ChessPiece(colour: .white, kind: .rook))
        XCTAssertEqual(board[ChessSquare(name: "e8")!], ChessPiece(colour: .black, kind: .king))
        XCTAssertEqual(board[ChessSquare(name: "d1")!], ChessPiece(colour: .white, kind: .queen))
        XCTAssertNil(board[ChessSquare(name: "e4")!])
        XCTAssertEqual(board.king(.white), ChessSquare(name: "e1"))
        XCTAssertEqual(board.king(.black), ChessSquare(name: "e8"))
    }

    func testAMalformedFENIsAnEmptyBoardNotACrash() {
        XCTAssertEqual(ChessBoard(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1").pieceCount, 0)
        XCTAssertEqual(ChessBoard(fen: "rnbqkbnr/pppppppx/8/8/8/8/PPPPPPPP/RNBQKBNR w").pieceCount, 0)
        XCTAssertEqual(ChessBoard(fen: "rnbqkbnr/ppppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w").pieceCount, 0)
        XCTAssertEqual(ChessBoard(fen: "").pieceCount, 0)
    }

    func testSquaresNameThemselves() {
        XCTAssertEqual(ChessSquare(name: "a1")?.index, 0)
        XCTAssertEqual(ChessSquare(name: "h8")?.index, 63)
        XCTAssertEqual(ChessSquare(file: 4, rank: 3).name, "e4")
        XCTAssertTrue(ChessSquare(name: "a1")!.isDark)
        XCTAssertFalse(ChessSquare(name: "h1")!.isDark)
        XCTAssertNil(ChessSquare(name: "i1"))
        XCTAssertNil(ChessSquare(name: "a9"))
        XCTAssertNil(ChessSquare(name: "e"))
    }

    func testPiecesReadFromFENLetters() {
        XCTAssertEqual(ChessPiece(fen: "N"), ChessPiece(colour: .white, kind: .knight))
        XCTAssertEqual(ChessPiece(fen: "q"), ChessPiece(colour: .black, kind: .queen))
        XCTAssertNil(ChessPiece(fen: "x"))
        XCTAssertEqual(ChessPieceKind.from("R"), .rook)
        XCTAssertNil(ChessPieceKind.from("rr"))
    }

    // MARK: - What the phone says

    func testTheClockReads() {
        XCTAssertEqual(ChessRules.clockText(600_000), "10:00")
        XCTAssertEqual(ChessRules.clockText(581_400), "9:41")
        XCTAssertEqual(ChessRules.clockText(59_999), "0:59")
        XCTAssertEqual(ChessRules.clockText(9_460), "0:09.4")
        XCTAssertEqual(ChessRules.clockText(0), "0:00.0")
        XCTAssertEqual(ChessRules.clockText(-5), "0:00.0")
    }

    func testTheMoveListPairsUp() {
        XCTAssertEqual(ChessRules.moveList([]), "")
        XCTAssertEqual(ChessRules.moveList(["e4"]), "1. e4")
        XCTAssertEqual(ChessRules.moveList(["e4", "e5", "Nf3"]), "1. e4 e5  2. Nf3")
        XCTAssertEqual(ChessRules.moveNumber([]), 1)
        XCTAssertEqual(ChessRules.moveNumber(["e4", "e5"]), 2)
        XCTAssertEqual(ChessRules.moveNumber(["e4", "e5", "Nf3"]), 2)
    }

    func testTheOutcomeLines() {
        XCTAssertEqual(ChessRules.outcomeLine("checkmate", winner: "You", loser: "Sam"), "Checkmate — You win.")
        XCTAssertEqual(ChessRules.outcomeLine("resigned", winner: "Sam", loser: "You"), "You resigned — Sam wins.")
        XCTAssertEqual(ChessRules.outcomeLine("timeout", winner: "Sam", loser: "You"), "You ran out of time — Sam wins.")
        XCTAssertEqual(ChessRules.outcomeLine("timeout", winner: nil, loser: "Sam"),
                       "Sam ran out of time, but there was nothing left to mate with — a draw.")
        XCTAssertEqual(ChessRules.outcomeLine("stalemate", winner: nil, loser: nil), "Stalemate — a draw.")
        XCTAssertEqual(ChessRules.outcomeLine("agreed", winner: nil, loser: nil), "A draw, agreed.")
        XCTAssertEqual(ChessRules.outcomeLine("left", winner: "You", loser: "Sam"), "Sam left the game — You win.")
        XCTAssertEqual(ChessRules.outcomeLine("whatever", winner: nil, loser: nil), "Game over.")
    }

    func testMaterialBalance() {
        let taken = ChessCaptured(white: [.queen, .pawn], black: [.rook])
        XCTAssertEqual(taken.balance(for: .white), 5)
        XCTAssertEqual(taken.balance(for: .black), -5)
        XCTAssertEqual(ChessRules.balanceText(5), "+5")
        XCTAssertNil(ChessRules.balanceText(0))
        XCTAssertNil(ChessRules.balanceText(-3))
    }

    func testTheCapturedSummaryCountsEachKindMostValuableFirst() {
        let taken = ChessCaptured(white: [.pawn, .knight, .pawn, .queen, .pawn], black: [])
        let tally = taken.tally(by: .white)
        XCTAssertEqual(tally.map(\.kind), [.queen, .knight, .pawn])
        XCTAssertEqual(tally.map(\.count), [1, 1, 3])
        XCTAssertTrue(taken.tally(by: .black).isEmpty)
        XCTAssertEqual(taken.points(by: .white), 15)
        XCTAssertEqual(taken.points(by: .black), 0)
        XCTAssertEqual(ChessRules.tallyText(.pawn, 3), "\(ChessPieceKind.pawn.glyph)×3")
        XCTAssertEqual(ChessRules.tallyText(.queen, 1), ChessPieceKind.queen.glyph)
        XCTAssertEqual(ChessRules.tallySpoken(tally), "a queen, a knight and 3 pawns")
        XCTAssertEqual(ChessRules.tallySpoken([ChessTally(kind: .rook, count: 2)]), "2 rooks")
        XCTAssertEqual(ChessRules.tallySpoken([]), "nothing")
    }

    func testTheNewGameSheetSendsTheGameAndLevel() {
        let body = ChessSettings(difficulty: .hard).createBody(invite: ["p_b"])
        XCTAssertEqual(body.game, "chess")
        XCTAssertEqual(body.difficulty, "hard")
        XCTAssertEqual(body.invite, ["p_b"])
    }

    func testAMoveBodyNamesTheSquares() throws {
        let body = GameActionBody(action: "move", from: "e7", to: "e8", promotion: "q")
        let json = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        XCTAssertTrue(json.contains(#""from":"e7""#))
        XCTAssertTrue(json.contains(#""to":"e8""#))
        XCTAssertTrue(json.contains(#""promotion":"q""#))
        XCTAssertFalse(json.contains("quantity"), "nil fields stay out")
    }
}
