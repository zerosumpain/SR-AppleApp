import XCTest
import CoreGraphics
@testable import SRAppleApp

/// Draw & Guess: the spec's wire contract, keeping the drawing in step with
/// the server's changes, putting a finger on the canvas, thinning and batching
/// its points, and the options the host picks.
final class DrawGuessTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    private func drawing(_ json: String) throws -> DrawGuessDrawingWire {
        try JSONDecoder().decode(DrawGuessDrawingWire.self, from: Data(json.utf8))
    }

    private func P(_ x: Int, _ y: Int) -> DrawGuessPoint { DrawGuessPoint(x, y) }

    // MARK: - The wire (the spec's JSON)

    private let guessingJSON = #"""
    { "id":"g_d", "game":"draw-guess", "difficulty":"easy", "phase":"drawing",
      "hostId":"p_a", "meId":"p_b", "turnsEach":2, "timeLimitMs":80000, "pickMs":10000, "revealMs":5000,
      "phaseEndsAt":1790000080000,
      "turn":{"index":1,"of":4,"drawerId":"p_a","startedAt":1790000000000,
              "choices":null,"word":null,"hint":"a___e",
              "solvers":[{"id":"p_c","points":5}],"drawerPoints":null,"ended":null,
              "feed":[{"n":3,"playerId":"p_b","name":"John","kind":"guess","text":"pear"},
                      {"n":4,"playerId":"p_c","name":"Kim","kind":"solved","text":null},
                      {"n":5,"playerId":"p_b","name":"John","kind":"close","text":"aple"}]},
      "drawing":{"revision":42,"since":null,
                 "strokes":[{"id":1,"color":"red","width":6,"points":[[10,20],[30.4,1200]]}],"ops":null},
      "palette":["black","red","orange","yellow","green","blue","purple","brown","white"], "widths":[6,14,32],
      "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"score":4,"solved":false,"isDrawing":true},
                 {"id":"p_b","name":"John","status":"joined","isHost":false,"score":0,"solved":false,"isDrawing":false},
                 {"id":"p_c","name":"Kim","status":"joined","isHost":false,"score":5,"solved":true,"isDrawing":false}],
      "standings":null, "winnerIds":[], "serverNow":1790000030000 }
    """#

    func testAGuessersRoomDecodesFromTheContract() throws {
        let room = try decode(guessingJSON)
        XCTAssertEqual(room.kind, .drawGuess)
        XCTAssertEqual(room.phase, .unknown, "the shared enum does not know `drawing`")
        let state = try XCTUnwrap(room.drawGuess)
        XCTAssertEqual(state.phase, .drawing)
        XCTAssertEqual(state.turnsEach, 2)
        XCTAssertEqual(state.pickMs, 10_000)
        XCTAssertEqual(room.timeLimitMs, 80_000)
        let turn = try XCTUnwrap(state.turn)
        XCTAssertEqual(turn.index, 1)
        XCTAssertEqual(turn.of, 4)
        XCTAssertEqual(turn.drawerId, "p_a")
        XCTAssertNil(turn.word, "a guesser never has the word")
        XCTAssertNil(turn.choices)
        XCTAssertEqual(turn.hint, "a___e")
        XCTAssertEqual(turn.solvers, [DrawGuessSolver(id: "p_c", points: 5)])
        XCTAssertEqual(turn.feed.map(\.kind), ["guess", "solved", "close"])
        XCTAssertNil(turn.feed[1].text, "a right answer is never shown")
        let wire = try XCTUnwrap(state.drawing)
        XCTAssertEqual(wire.revision, 42)
        XCTAssertNil(wire.since)
        XCTAssertEqual(wire.strokes?.first?.points, [P(10, 20), P(30, 1000)], "rounded and clamped")
        XCTAssertEqual(state.palette.last, "white")
        XCTAssertEqual(state.widths, [6, 14, 32])
        XCTAssertEqual(state.seat("p_a")?.isDrawing, true)
        XCTAssertEqual(state.seat("p_c")?.solved, true)
        XCTAssertEqual(room.players.first?.score, 4)
    }

    func testAnotherGamesRoomHasNoDrawGuess() throws {
        let room = try decode(#"{"id":"g","game":"boggle","difficulty":"easy","phase":"lobby","hostId":"a","meId":"a","serverNow":1}"#)
        XCTAssertNil(room.drawGuess)
    }

    func testAPickingRoomAndChangesDecodeLeniently() throws {
        let room = try decode(#"""
        { "id":"g_d", "game":"draw-guess", "difficulty":"hard", "phase":"picking", "hostId":"p_a", "meId":"p_a",
          "phaseEndsAt":1, "turn":{"index":0,"of":2,"drawerId":"p_a","choices":["kite","owl","hide and seek"]},
          "drawing":{"revision":7,"since":5,"strokes":null,
                     "ops":[{"seq":6,"op":"stroke","id":3,"color":"blue","width":14,"points":[[1,2]]},
                            {"seq":7,"op":"shimmer"}]},
          "serverNow":1 }
        """#)
        let state = try XCTUnwrap(room.drawGuess)
        XCTAssertEqual(state.phase, .picking)
        XCTAssertEqual(state.turn?.choices, ["kite", "owl", "hide and seek"])
        XCTAssertEqual(state.turn?.solvers, [])
        XCTAssertEqual(state.palette, DrawGuessPen.palette, "the defaults when the wire has none")
        XCTAssertEqual(state.drawing?.ops, [
            .stroke(seq: 6, DrawGuessStroke(id: 3, color: "blue", width: 14, points: [P(1, 2)])),
            .other(seq: 7),
        ])
        XCTAssertEqual(DrawGuessPhase.from("something-new"), .unknown)
    }

    // MARK: - The canvas, kept in step

    func testChangesApplyOnTopOfTheWholeDrawing() throws {
        var canvas = DrawGuessCanvas()
        XCTAssertEqual(canvas.apply(try drawing(#"{"revision":10,"since":10,"ops":[]}"#)), .gap,
                       "changes before any whole drawing cannot be placed")
        XCTAssertEqual(canvas.apply(try drawing(#"""
        {"revision":10,"since":null,"strokes":[{"id":1,"color":"red","width":6,"points":[[0,0]]}]}
        """#)), .applied)
        XCTAssertEqual(canvas.revision, 10)
        // A stroke's second batch appends; a new id is a new stroke; undo takes the last.
        XCTAssertEqual(canvas.apply(try drawing(#"""
        {"revision":13,"since":10,"ops":[
          {"seq":11,"op":"stroke","id":1,"color":"red","width":6,"points":[[5,5]]},
          {"seq":12,"op":"stroke","id":2,"color":"blue","width":32,"points":[[9,9]]},
          {"seq":13,"op":"stroke","id":3,"color":"green","width":6,"points":[[1,1]]}]}
        """#)), .applied)
        XCTAssertEqual(canvas.strokes.map(\.id), [1, 2, 3])
        XCTAssertEqual(canvas.strokes[0].points, [P(0, 0), P(5, 5)])
        // An answer to an older `since` overlapping what arrived: only the new ops.
        XCTAssertEqual(canvas.apply(try drawing(#"""
        {"revision":14,"since":12,"ops":[
          {"seq":13,"op":"stroke","id":3,"color":"green","width":6,"points":[[1,1]]},
          {"seq":14,"op":"undo"}]}
        """#)), .applied)
        XCTAssertEqual(canvas.strokes.map(\.id), [1, 2])
        XCTAssertEqual(canvas.revision, 14)
        // Old news is ignored; a jump is a gap.
        XCTAssertEqual(canvas.apply(try drawing(#"{"revision":13,"since":12,"ops":[]}"#)), .stale)
        XCTAssertEqual(canvas.apply(try drawing(#"{"revision":13,"since":null,"strokes":[]}"#)), .stale)
        XCTAssertEqual(canvas.apply(try drawing(#"{"revision":20,"since":18,"ops":[]}"#)), .gap)
        XCTAssertEqual(canvas.apply(try drawing(#"{"revision":15,"since":14,"ops":[{"seq":15,"op":"clear"}]}"#)), .applied)
        XCTAssertTrue(canvas.strokes.isEmpty)
        // A new drawing arrives whole.
        XCTAssertEqual(canvas.apply(try drawing(#"{"revision":16,"since":null,"strokes":[]}"#)), .applied)
        canvas.reset()
        XCTAssertNil(canvas.revision)
    }

    // MARK: - Geometry

    func testAFingerIsQuantisedOntoTheCanvas() {
        XCTAssertEqual(DrawGuessGeometry.quantise(CGPoint(x: 0, y: 0), size: 300), P(0, 0))
        XCTAssertEqual(DrawGuessGeometry.quantise(CGPoint(x: 150, y: 300), size: 300), P(500, 1000))
        XCTAssertEqual(DrawGuessGeometry.quantise(CGPoint(x: 100, y: 1), size: 300), P(333, 3))
        XCTAssertEqual(DrawGuessGeometry.quantise(CGPoint(x: -20, y: 400), size: 300), P(0, 1000), "clamped")
        XCTAssertEqual(DrawGuessGeometry.quantise(CGPoint(x: 10, y: 10), size: 0), P(0, 0))
        XCTAssertEqual(DrawGuessGeometry.place(P(500, 250), size: 300), CGPoint(x: 150, y: 75))
    }

    func testSimplifyKeepsTheShapeAndDropsTheStraight() {
        let straight = (0...100).map { P($0 * 10, 500) }
        XCTAssertEqual(DrawGuessGeometry.simplify(straight, tolerance: 1.5), [P(0, 500), P(1000, 500)])
        let corner = (0...50).map { P($0 * 10, 0) } + (1...50).map { P(500, $0 * 10) }
        XCTAssertEqual(DrawGuessGeometry.simplify(corner, tolerance: 1.5), [P(0, 0), P(500, 0), P(500, 500)])
        // A wobble within the tolerance goes; one past it stays.
        XCTAssertEqual(DrawGuessGeometry.simplify([P(0, 0), P(50, 1), P(100, 0)], tolerance: 1.5), [P(0, 0), P(100, 0)])
        XCTAssertEqual(DrawGuessGeometry.simplify([P(0, 0), P(50, 9), P(100, 0)], tolerance: 1.5).count, 3)
        XCTAssertEqual(DrawGuessGeometry.simplify([P(1, 1), P(2, 2)], tolerance: 1.5), [P(1, 1), P(2, 2)])
    }

    // MARK: - The pen's batches

    func testAStrokeStreamsInBatchesUnderOneId() throws {
        var pen = DrawGuessPen(firstId: 7)
        pen.color = "blue"
        pen.width = 32
        XCTAssertNil(pen.batch(), "nothing to send with the pen up")
        pen.down(at: P(0, 0))
        for x in 1...20 { pen.move(to: P(x * 10, 0)) }
        pen.move(to: P(200, 0))
        XCTAssertEqual(pen.live.count, 21, "a repeated point is dropped")

        let first = try XCTUnwrap(pen.batch())
        XCTAssertEqual(first.id, 7)
        XCTAssertEqual(first.points, [P(0, 0), P(200, 0)], "a straight run thins to its ends")
        XCTAssertNil(pen.batch(), "nothing new since")

        for y in 1...10 { pen.move(to: P(200, y * 10)) }
        let second = try XCTUnwrap(pen.batch())
        XCTAssertEqual(second.id, 7, "the same stroke: the server appends")
        XCTAssertEqual(second.points, [P(200, 100)], "thinned against the last point sent, which is not resent")

        pen.move(to: P(300, 100))
        let last = pen.up()
        XCTAssertEqual(last.map(\.points), [[P(300, 100)]])
        XCTAssertFalse(pen.isDown)

        pen.down(at: P(5, 5))
        XCTAssertEqual(pen.strokeId, 8, "the next stroke has the next id")
        let body = try XCTUnwrap(pen.up().first).body
        XCTAssertEqual(body.action, "stroke")
        XCTAssertEqual(body.id, 8)
        XCTAssertEqual(body.color, "blue")
        XCTAssertEqual(body.width, 32)
        XCTAssertEqual(body.points, [[5, 5], [5, 5]], "a tap is a dot: sent twice so it has length")
    }

    func testABigBatchIsSplitAtTheServersCap() throws {
        var pen = DrawGuessPen()
        pen.down(at: P(0, 0))
        // A zigzag nothing can thin.
        for i in 1...400 { pen.move(to: P(i, i % 2 == 0 ? 0 : 50)) }
        let first = try XCTUnwrap(pen.batch())
        XCTAssertEqual(first.points.count, DrawGuessPen.maxPostPoints)
        let rest = try XCTUnwrap(pen.batch())
        XCTAssertLessThanOrEqual(rest.points.count, DrawGuessPen.maxPostPoints)
        XCTAssertFalse(rest.points.contains(first.points.last!), "the join is not sent twice")
        XCTAssertEqual(rest.points.last, P(400, 0))
        XCTAssertNil(pen.batch())
    }

    func testCancelDropsWhatWasNotSent() {
        var pen = DrawGuessPen()
        pen.down(at: P(1, 1))
        pen.move(to: P(2, 2))
        pen.cancel()
        XCTAssertFalse(pen.isDown)
        XCTAssertTrue(pen.live.isEmpty)
        XCTAssertNil(pen.batch())
    }

    func testTheBodyEncodesTheWireKeys() throws {
        var body = GameActionBody(action: "guess")
        body.text = "apple"
        body.since = 12
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(json["action"] as? String, "guess")
        XCTAssertEqual(json["text"] as? String, "apple")
        XCTAssertEqual(json["since"] as? Int, 12)
        XCTAssertNil(json["points"], "nil fields are left out")
    }

    // MARK: - The host's options, and the words on screen

    func testTheHostsOptionsBecomeTheCreateBody() {
        let body = DrawGuessSettings(difficulty: .hard, turnsEach: 2, seconds: 100).createBody(invite: ["p_b"])
        XCTAssertEqual(body.game, "draw-guess")
        XCTAssertEqual(body.difficulty, "hard")
        XCTAssertEqual(body.turnsEach, 2)
        XCTAssertEqual(body.seconds, 100)
        XCTAssertEqual(DrawGuessSettings.turnsLabel(2), "Twice round")
        XCTAssertEqual(GameKind(rawValue: "draw-guess"), .drawGuess)
        XCTAssertEqual(GameKind.drawGuess.title, "Draw & Guess")
    }

    func testTheLobbyLineSaysTheClockAndTurns() throws {
        let room = try decode(guessingJSON)
        XCTAssertEqual(DrawGuessSettings.about(room), "80 s a drawing · twice round")
    }

    func testTheHintIsSpacedForReading() {
        XCTAssertEqual(DrawGuessText.spaced("a___e"), "a _ _ _ e")
        XCTAssertEqual(DrawGuessText.spaced("___ _____"), "_ _ _   _ _ _ _ _")
        XCTAssertEqual(DrawGuessText.letters("a___e"), "5 letters")
        XCTAssertEqual(DrawGuessText.letters("___ _____"), "3, 5 letters")
    }

    func testAGuessWaitsItsTurn() {
        XCTAssertTrue(DrawGuessText.canSend("apple", lastSentAt: nil, now: 0))
        XCTAssertFalse(DrawGuessText.canSend("   ", lastSentAt: nil, now: 0))
        XCTAssertFalse(DrawGuessText.canSend("apple", lastSentAt: 1_000, now: 1_500))
        XCTAssertTrue(DrawGuessText.canSend("apple", lastSentAt: 1_000, now: 1_700))
    }
}
