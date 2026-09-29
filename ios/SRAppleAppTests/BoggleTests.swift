import XCTest
import CoreGraphics
@testable import SRAppleApp

/// Boggle: the spec's wire contract, and the rules the phone applies itself —
/// which tiles touch, tracing and untracing a word, turning the board, the
/// round the host picks.
final class BoggleTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    private let grid = ["t", "qu", "e", "a", "s", "i", "n", "d", "l", "e", "o", "r", "a", "m", "th", "s"]

    // MARK: - The wire (the spec's JSON)

    private let playingJSON = #"""
    { "id":"g_b", "game":"boggle", "difficulty":"medium", "phase":"playing",
      "hostId":"p_a", "meId":"p_b",
      "size":4, "scoring":"classic", "minLength":3,
      "points":{"3":1,"4":2,"5":3,"6":4,"7":5,"8":6},
      "timeLimitMs":120000, "startedAt":1790000000000, "phaseEndsAt":1790000120000,
      "grid":["t","QU","e","a","s","i","n","d","l","e","o","r","a","m","th","s"],
      "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"wordCount":3,"score":4,"words":null},
                 {"id":"p_b","name":"John","status":"joined","isHost":false,"wordCount":1,"score":2,
                  "words":[{"word":"quiet","points":2,"shared":null,"path":[1,5,9,0]}]}],
      "found": null, "missed": null, "possible": null,
      "standings": null, "winnerIds": [], "serverNow":1790000030000 }
    """#

    func testAPlayingRoomDecodesFromTheContract() throws {
        let room = try decode(playingJSON)
        XCTAssertEqual(room.kind, .boggle)
        XCTAssertEqual(room.phase, .playing)
        XCTAssertEqual(room.size, 4)
        XCTAssertEqual(room.scoring, "classic")
        XCTAssertEqual(room.minLength, 3)
        XCTAssertEqual(room.points["8"], 6)
        XCTAssertEqual(room.timeLimitMs, 120_000)
        XCTAssertEqual(room.grid?.count, 16)
        XCTAssertEqual(room.grid?[1], "qu", "faces are lower-cased")
        XCTAssertNil(room.boggleFound)
        XCTAssertNil(room.boggleMissed)
        XCTAssertNil(room.possible)

        let me = try XCTUnwrap(room.me)
        XCTAssertEqual(me.wordCount, 1)
        XCTAssertEqual(me.boggleWords, [BoggleWord(word: "quiet", points: 2, shared: nil, path: [1, 5, 9, 0])])
        let sam = try XCTUnwrap(room.others.first)
        XCTAssertEqual(sam.wordCount, 3)
        XCTAssertNil(sam.boggleWords, "another player's words are a count until the finish")
    }

    func testAFinishedRoomRevealsEverythingWithPaths() throws {
        let json = #"""
        { "id":"g_b", "game":"boggle", "difficulty":"hard", "phase":"finished",
          "hostId":"p_a", "meId":"p_a", "size":5, "scoring":"classic", "minLength":4,
          "points":{"3":1,"4":2,"5":3,"6":4,"7":5,"8":6},
          "timeLimitMs":90000, "startedAt":1790000000000, "phaseEndsAt":1790000690000,
          "grid":["t","r","a","p","s","e","n","d","l","i","o","qu","a","m","e","s","a","b","c","d","e","f","g","h","i"],
          "players":[{"id":"p_a","name":"John","status":"joined","isHost":true,"wordCount":2,"score":1,
                      "words":[{"word":"trap","points":0,"shared":true,"path":[0,1,2,3]},
                               {"word":"lime","points":1,"shared":false,"path":[8,9,13,14]}]},
                     {"id":"p_b","name":"Sam","status":"joined","isHost":false,"wordCount":1,"score":0,
                      "words":[{"word":"trap","points":0,"shared":true,"path":[0,1,2,3]}]}],
          "found":[{"word":"lime","points":1,"finderIds":["p_a"],"shared":false,"path":[8,9,13,14]},
                   {"word":"trap","points":0,"finderIds":["p_a","p_b"],"shared":true,"path":[0,1,2,3]}],
          "missed":[{"word":"alien","points":2,"path":[12,8,9,5,6]}],
          "possible":{"words":187,"points":260},
          "standings":[{"id":"p_a","name":"John","score":1,"words":2,"longest":"lime"},
                       {"id":"p_b","name":"Sam","score":0,"words":1,"longest":"trap"}],
          "winnerIds":["p_a"], "serverNow":1790000100000 }
        """#
        let room = try decode(json)
        XCTAssertEqual(room.size, 5)
        XCTAssertEqual(room.grid?.count, 25)
        let found = try XCTUnwrap(room.boggleFound)
        XCTAssertEqual(found.map(\.word), ["lime", "trap"])
        XCTAssertEqual(found[1].shared, true)
        XCTAssertEqual(found[1].points, 0, "a crossed-out word scored nothing")
        XCTAssertEqual(found[1].finderIds, ["p_a", "p_b"])
        XCTAssertEqual(found[0].path, [8, 9, 13, 14])
        let missed = try XCTUnwrap(room.boggleMissed)
        XCTAssertEqual(missed.first?.word, "alien")
        XCTAssertEqual(missed.first?.path, [12, 8, 9, 5, 6])
        XCTAssertNil(room.missed, "Anagram Blitz's plain-string missed does not read Boggle's objects")
        XCTAssertEqual(room.possible, BogglePossible(words: 187, points: 260))
        XCTAssertEqual(room.me?.boggleWords?.first?.shared, true)
        XCTAssertEqual(room.winnerIds, ["p_a"])
    }

    func testAnAnagramRoomStillReadsItsOwnMissedAndDefaultsBoggleFields() throws {
        let json = #"""
        { "id":"g_a", "game":"anagram-blitz", "phase":"finished", "serverNow":1,
          "missed":["painter"], "letters":["p"] }
        """#
        let room = try decode(json)
        XCTAssertEqual(room.missed, ["painter"])
        XCTAssertNil(room.boggleMissed)
        XCTAssertNil(room.grid)
        XCTAssertEqual(room.size, 4)
    }

    // MARK: - The board

    func testTilesTouchSideAndCornerButNotAcrossTheEdge() {
        XCTAssertTrue(BoggleRules.adjacent(0, 1, size: 4))
        XCTAssertTrue(BoggleRules.adjacent(0, 5, size: 4), "diagonal")
        XCTAssertTrue(BoggleRules.adjacent(5, 10, size: 4))
        XCTAssertFalse(BoggleRules.adjacent(3, 4, size: 4), "end of one row is not the start of the next")
        XCTAssertFalse(BoggleRules.adjacent(0, 2, size: 4))
        XCTAssertFalse(BoggleRules.adjacent(5, 5, size: 4), "a tile does not touch itself")
        XCTAssertFalse(BoggleRules.adjacent(15, 16, size: 4), "off the board")
        XCTAssertTrue(BoggleRules.adjacent(6, 12, size: 6), "(1,0)-(2,0) on a 6×6")
    }

    func testAPathSpellsItsWordWithTwoLetterFaces() {
        XCTAssertEqual(BoggleRules.word([1, 5, 9, 0], grid: grid), "quiet")
        XCTAssertEqual(BoggleRules.word([14, 15], grid: grid), "ths")
        XCTAssertEqual(BoggleRules.word([99], grid: grid), "")
        XCTAssertTrue(BoggleRules.isPath([1, 5, 9], size: 4))
        XCTAssertFalse(BoggleRules.isPath([1, 5, 1], size: 4), "each tile once")
        XCTAssertFalse(BoggleRules.isPath([0, 2], size: 4), "must touch")
        XCTAssertFalse(BoggleRules.isPath([], size: 4))
    }

    func testFacesShowWithOneCapital() {
        XCTAssertEqual(BoggleRules.display("qu"), "Qu")
        XCTAssertEqual(BoggleRules.display("TH"), "Th")
        XCTAssertEqual(BoggleRules.display("a"), "A")
        XCTAssertEqual(BoggleRules.display(""), "")
    }

    func testPointsAreAPointALetterPastTwo() {
        let table = Dictionary(uniqueKeysWithValues: (3...16).map { (String($0), $0 - 2) })
        XCTAssertEqual(BoggleRules.points(for: "tea", table: table), 1)
        XCTAssertEqual(BoggleRules.points(for: "team", table: table), 2)
        XCTAssertEqual(BoggleRules.points(for: "quiet", table: table), 3, "qu counts as two letters")
        XCTAssertEqual(BoggleRules.points(for: "strangers", table: table), 7, "no cap at eight")
        XCTAssertEqual(BoggleRules.points(for: "internationally", table: [:]), 13, "fallback rule")
        XCTAssertEqual(BoggleRules.points(for: "at", table: table), 0)
    }

    // MARK: - Tracing

    func testADragAddsNeighboursAndRetracingTakesThemOff() {
        var trace = BoggleTrace(size: 4)
        XCTAssertTrue(trace.drag(to: 0))
        XCTAssertTrue(trace.drag(to: 5))
        XCTAssertFalse(trace.drag(to: 7), "not next to the last tile")
        XCTAssertTrue(trace.drag(to: 6))
        XCTAssertEqual(trace.path, [0, 5, 6])
        XCTAssertTrue(trace.drag(to: 5), "back onto the tile before undoes the last")
        XCTAssertEqual(trace.path, [0, 5])
        XCTAssertFalse(trace.drag(to: 5), "staying put changes nothing")
    }

    func testTapsBuildUndoAndRestartAWord() {
        var trace = BoggleTrace(size: 4)
        trace.tap(0)
        trace.tap(1)
        trace.tap(6)
        XCTAssertEqual(trace.path, [0, 1, 6])
        trace.tap(6)
        XCTAssertEqual(trace.path, [0, 1], "the last tile again takes it off")
        trace.tap(6)
        trace.tap(0)
        XCTAssertEqual(trace.path, [0], "an earlier tile cuts back to it")
        trace.tap(15)
        XCTAssertEqual(trace.path, [15], "a tile that touches nothing starts again there")
        XCTAssertTrue(trace.canExtend(to: 10))
        XCTAssertFalse(trace.canExtend(to: 0))
        trace.delete()
        XCTAssertTrue(trace.isEmpty)
        XCTAssertFalse(trace.delete())
    }

    func testTheFingerMustBeNearATilesCentre() {
        // 4×4, tiles 60 wide, 6 apart: pitch 66, centres at 30, 96, 162, 228.
        XCTAssertEqual(BoggleRules.tile(at: CGPoint(x: 30, y: 30), size: 4, side: 60, gap: 6), 0)
        XCTAssertEqual(BoggleRules.tile(at: CGPoint(x: 96, y: 162), size: 4, side: 60, gap: 6), 9)
        XCTAssertNil(BoggleRules.tile(at: CGPoint(x: 62, y: 62), size: 4, side: 60, gap: 6),
                     "the corner between four tiles picks up none of them")
        XCTAssertNil(BoggleRules.tile(at: CGPoint(x: 300, y: 30), size: 4, side: 60, gap: 6), "off the board")
        XCTAssertNil(BoggleRules.tile(at: CGPoint(x: -5, y: 30), size: 4, side: 60, gap: 6))
    }

    func testTurningTheBoardMovesWhereTilesAreDrawnAndBack() {
        // One quarter clockwise: the top-left corner goes to the top-right.
        XCTAssertEqual(BoggleRules.displayed(0, size: 4, turns: 1), 3)
        XCTAssertEqual(BoggleRules.displayed(3, size: 4, turns: 1), 15)
        XCTAssertEqual(BoggleRules.displayed(0, size: 4, turns: 2), 15)
        XCTAssertEqual(BoggleRules.displayed(7, size: 5, turns: 4), 7, "four turns is none")
        for size in 4...6 {
            for turns in 0..<4 {
                for tile in 0..<(size * size) {
                    let shown = BoggleRules.displayed(tile, size: size, turns: turns)
                    XCTAssertEqual(BoggleRules.tile(atDisplay: shown, size: size, turns: turns), tile)
                }
            }
        }
    }

    func testASixBySixFitsASmallPhone() {
        // iPhone SE: 375 wide, less the gutters and the tray's padding.
        let side = BoggleRules.tileSide(width: 375 - 40 - 12, size: 6, gap: 6)
        XCTAssertGreaterThanOrEqual(side, 44, "still a thumb's worth")
        XCTAssertLessThanOrEqual(side * 6 + 30, 375 - 40 - 12)
        XCTAssertEqual(BoggleRules.tileSide(width: 1000, size: 4, gap: 6), 84, "capped on a big screen")
    }

    // MARK: - Refusals and the round

    func testObviousRefusalsAnswerOnThePhone() {
        XCTAssertEqual(BoggleRules.localRefusal(word: "at", minLength: 3, mine: []), "Words need at least 3 letters.")
        XCTAssertEqual(BoggleRules.localRefusal(word: "tea", minLength: 4, mine: []), "Words need at least 4 letters.")
        XCTAssertEqual(BoggleRules.localRefusal(word: "tea", minLength: 3, mine: ["tea"]), "You already have that one.")
        XCTAssertNil(BoggleRules.localRefusal(word: "tea", minLength: 3, mine: ["eat"]))
    }

    func testTheRoundTheHostPicksGoesInTheCreateBody() throws {
        let body = BoggleSettings(difficulty: .hard, size: 6, seconds: 30, scoring: .every).createBody(invite: ["p_b"])
        XCTAssertEqual(body.game, "boggle")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        XCTAssertEqual(json?["size"] as? Int, 6)
        XCTAssertEqual(json?["seconds"] as? Int, 30)
        XCTAssertEqual(json?["scoring"] as? String, "every")
        XCTAssertEqual(json?["difficulty"] as? String, "hard")
        XCTAssertNil(json?["topic"], "nil fields are left out")

        let tap = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            GameActionBody(action: "word", word: "quiet", path: [1, 5, 9, 0]))) as? [String: Any]
        XCTAssertEqual(tap?["path"] as? [Int], [1, 5, 9, 0])
    }

    func testDefaultsAndLabels() {
        let settings = BoggleSettings(difficulty: .easy)
        XCTAssertEqual(settings.size, 4)
        XCTAssertEqual(settings.seconds, 120)
        XCTAssertEqual(settings.scoring, .classic)
        XCTAssertEqual(BoggleSettings.times.map(BoggleSettings.timeLabel), ["30 s", "90 s", "2 min", "3 min"])
        XCTAssertEqual(BoggleSettings.sizeLabel(5), "5×5")
        XCTAssertEqual(BoggleScoring.from("every"), .every)
        XCTAssertEqual(BoggleScoring.from("nonsense"), .classic)
        XCTAssertEqual(BoggleScoring.from(nil), .classic)
    }

    func testTheLobbyNamesTheRound() throws {
        let room = try decode(#"""
        { "id":"g_b", "game":"boggle", "phase":"lobby", "size":5, "scoring":"every",
          "timeLimitMs":120000, "serverNow":1 }
        """#)
        XCTAssertEqual(BoggleSettings.about(room), "5×5 · 2 min · every word counts")
    }

    func testThePossibleLine() {
        XCTAssertEqual(BoggleRules.possibleLine(found: 23, possible: BogglePossible(words: 187, points: 260), solo: true),
                       "You found 23 of 187 words on this board.")
        XCTAssertEqual(BoggleRules.possibleLine(found: 23, possible: BogglePossible(words: 187, points: 260), solo: false),
                       "Between you, you found 23 of 187 words on this board.")
        XCTAssertNil(BoggleRules.possibleLine(found: 0, possible: nil, solo: true))
    }

    func testBoggleIsAGameThisAppKnows() {
        XCTAssertEqual(GameKind(rawValue: "boggle"), .boggle)
        XCTAssertEqual(GameNames.title("boggle"), "Boggle")
        XCTAssertEqual(GameDifficulty.hard.line(for: .boggle), "The dice as they fall. 4 letters or more.")
    }
}
