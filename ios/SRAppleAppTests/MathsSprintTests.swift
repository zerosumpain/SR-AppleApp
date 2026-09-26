import XCTest
@testable import SRAppleApp

/// Quick Maths Sprint: the spec's wire contract, and the rules the phone
/// applies itself — the keypad, and reading right or wrong from the room.
final class MathsSprintTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    // MARK: - The wire (the spec's JSON)

    private let playingJSON = #"""
    { "id":"g_m", "game":"maths-sprint", "difficulty":"medium",
      "phase":"playing", "hostId":"p_a", "meId":"p_b",
      "timeLimitMs":60000, "problemCount":200, "streakBonus":5,
      "startedAt":1790000000000, "phaseEndsAt":1790000060000,
      "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"score":8,"answered":7},
                 {"id":"p_b","name":"John","status":"joined","isHost":false,"score":3,"answered":3}],
      "me": {"problem": {"index":3,"text":"7 × 8"}, "score":3, "correct":3, "misses":1, "streak":2, "bestStreak":2},
      "standings": null, "winnerIds": [], "recaps": null, "serverNow":1790000020000 }
    """#

    func testAPlayingRoomDecodesFromTheContract() throws {
        let room = try decode(playingJSON)
        XCTAssertEqual(room.kind, .mathsSprint)
        XCTAssertEqual(room.phase, .playing)
        XCTAssertEqual(room.timeLimitMs, 60_000)
        XCTAssertEqual(room.problemCount, 200)
        XCTAssertEqual(room.streakBonus, 5)
        XCTAssertEqual(room.phaseEndsAt, 1_790_000_060_000)
        XCTAssertEqual(room.others.first?.score, 8)
        XCTAssertEqual(room.others.first?.answered, 7)

        let me = try XCTUnwrap(room.sprint, "`me` on the wire is my sprint")
        XCTAssertEqual(me.problem, SprintProblem(index: 3, text: "7 × 8"), "the text exactly as sent")
        XCTAssertEqual(me.score, 3)
        XCTAssertEqual(me.correct, 3)
        XCTAssertEqual(me.misses, 1)
        XCTAssertEqual(me.streak, 2)
        XCTAssertEqual(me.bestStreak, 2)
        XCTAssertEqual(room.me?.name, "John", "`GameRoom.me` is still my player row")
        XCTAssertNil(room.recaps)
    }

    func testAFinishedRoomCarriesStandingsAndRecaps() throws {
        let json = #"""
        { "id":"g_m", "game":"maths-sprint", "difficulty":"hard", "phase":"finished",
          "hostId":"p_a", "meId":"p_a",
          "timeLimitMs":60000, "problemCount":200, "streakBonus":5,
          "startedAt":1790000000000, "phaseEndsAt":1790000660000,
          "players":[{"id":"p_a","name":"John","status":"joined","isHost":true,"score":13,"answered":11},
                     {"id":"p_b","name":"Sam","status":"joined","isHost":false,"score":9,"answered":8}],
          "me": {"problem": null, "score":13, "correct":11, "misses":2, "streak":0, "bestStreak":7},
          "standings":[{"id":"p_a","name":"John","score":13,"correct":11,"misses":2,"bestStreak":7},
                       {"id":"p_b","name":"Sam","score":9,"correct":8,"misses":0,"bestStreak":5}],
          "winnerIds":["p_a"],
          "recaps":[{"playerId":"p_a","problems":[{"index":10,"text":"84 ÷ 7","answer":12,"solved":true,"wrongTries":0},
                                                  {"index":11,"text":"6 × 9 − 14","answer":40,"solved":false,"wrongTries":2}]},
                    {"playerId":"p_b","problems":[]}],
          "serverNow":1790000061000 }
        """#
        let room = try decode(json)
        XCTAssertEqual(room.phase, .finished)
        XCTAssertNil(room.sprint?.problem, "no problem once the time is up")
        let standings = try XCTUnwrap(room.standings)
        XCTAssertEqual(standings[0].correct, 11)
        XCTAssertEqual(standings[0].misses, 2)
        XCTAssertEqual(standings[0].bestStreak, 7)
        XCTAssertEqual(standings[1].misses, 0)
        let recaps = try XCTUnwrap(room.recaps)
        XCTAssertEqual(recaps.map(\.playerId), ["p_a", "p_b"])
        XCTAssertEqual(recaps[0].problems[1].text, "6 × 9 − 14")
        XCTAssertEqual(recaps[0].problems[1].answer, 40)
        XCTAssertFalse(recaps[0].problems[1].solved)
        XCTAssertEqual(recaps[0].problems[1].wrongTries, 2)
        XCTAssertTrue(recaps[1].problems.isEmpty)
    }

    func testAnAnswerBodyIsIndexAndValue() throws {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MathsSprint.body(index: 3, value: 56))) as? [String: Any]
        XCTAssertEqual(body?.count, 3)
        XCTAssertEqual(body?["action"] as? String, "answer")
        XCTAssertEqual(body?["index"] as? Int, 3)
        XCTAssertEqual(body?["value"] as? Int, 56)
    }

    // MARK: - The keypad

    func testDigitsBuildAWholeNumber() {
        var input = SprintInput()
        XCTAssertNil(input.value, "no digits, nothing to send")
        XCTAssertTrue(input.isEmpty)
        input.press(5)
        input.press(6)
        XCTAssertEqual(input.value, 56)
        XCTAssertEqual(input.display, "56")
        XCTAssertFalse(input.press(10), "not a digit")
        XCTAssertFalse(input.press(-1))
        XCTAssertEqual(input.value, 56)
    }

    func testALeadingZeroIsReplaced() {
        var input = SprintInput()
        input.press(0)
        XCTAssertEqual(input.value, 0, "zero is an answer")
        input.press(7)
        XCTAssertEqual(input.display, "7")
        input.press(0)
        XCTAssertEqual(input.value, 70)
    }

    func testMinusTogglesAndDeleteTakesDigitsThenTheSign() {
        var input = SprintInput()
        input.toggleSign()
        XCTAssertEqual(input.display, "−")
        XCTAssertNil(input.value, "a sign alone is not an answer")
        XCTAssertFalse(input.isEmpty)
        input.press(4)
        input.press(2)
        XCTAssertEqual(input.value, -42)
        input.toggleSign()
        XCTAssertEqual(input.value, 42)
        input.toggleSign()
        XCTAssertTrue(input.delete())
        XCTAssertEqual(input.value, -4)
        XCTAssertTrue(input.delete())
        XCTAssertEqual(input.display, "−")
        XCTAssertTrue(input.delete())
        XCTAssertTrue(input.isEmpty)
        XCTAssertFalse(input.delete())
    }

    func testTheAnswerIsCappedInLength() {
        var input = SprintInput()
        for _ in 0..<SprintInput.maxDigits { XCTAssertTrue(input.press(9)) }
        XCTAssertFalse(input.press(9))
        XCTAssertEqual(input.value, 999_999)
        input.clear()
        XCTAssertTrue(input.isEmpty)
    }

    // MARK: - Right or wrong

    func testAnAnswerThatMovesMeOnWasRight() {
        let before = SprintMe(problem: SprintProblem(index: 3, text: "7 × 8"), score: 3, correct: 3, misses: 1, streak: 2)
        let after = SprintMe(problem: SprintProblem(index: 4, text: "9 + 5"), score: 4, correct: 4, misses: 1, streak: 3)
        XCTAssertEqual(SprintVerdict.judge(sentIndex: 3, before: before, after: after), .right)
    }

    func testAMissOnTheSameProblemWasWrong() {
        let before = SprintMe(problem: SprintProblem(index: 3, text: "7 × 8"), score: 3, correct: 3, misses: 1, streak: 2)
        let after = SprintMe(problem: SprintProblem(index: 3, text: "7 × 8"), score: 3, correct: 3, misses: 2, streak: 0)
        XCTAssertEqual(SprintVerdict.judge(sentIndex: 3, before: before, after: after), .wrong)
    }

    func testAStaleRoomSaysNothing() {
        let same = SprintMe(problem: SprintProblem(index: 3, text: "7 × 8"), score: 3, correct: 3, misses: 1, streak: 2)
        XCTAssertEqual(SprintVerdict.judge(sentIndex: 3, before: same, after: same), .unknown)
        XCTAssertEqual(SprintVerdict.judge(sentIndex: 3, before: same, after: nil), .unknown)
    }

    func testTheLastProblemRightLeavesNoProblem() {
        let after = SprintMe(problem: nil, score: 240, correct: 200, misses: 0, streak: 200)
        XCTAssertEqual(SprintVerdict.judge(sentIndex: 199, before: nil, after: after), .right)
    }

    func testTheStreakCueFallsOnEveryFifth() {
        XCTAssertFalse(MathsSprint.onBonus(streak: 0, every: 5))
        XCTAssertFalse(MathsSprint.onBonus(streak: 4, every: 5))
        XCTAssertTrue(MathsSprint.onBonus(streak: 5, every: 5))
        XCTAssertFalse(MathsSprint.onBonus(streak: 6, every: 5))
        XCTAssertTrue(MathsSprint.onBonus(streak: 10, every: 5))
        XCTAssertEqual(MathsSprint.toBonus(streak: 0, every: 5), 5)
        XCTAssertEqual(MathsSprint.toBonus(streak: 3, every: 5), 2)
        XCTAssertEqual(MathsSprint.toBonus(streak: 5, every: 5), 5)
    }

    func testVoiceOverReadsTheSymbols() {
        XCTAssertEqual(SprintSpeech.problem("6 × 9 − 14"), "6 times 9 minus 14")
        XCTAssertEqual(SprintSpeech.problem("84 ÷ 7"), "84 divided by 7")
        XCTAssertEqual(SprintSpeech.problem("12 + 7"), "12 plus 7")
    }

    func testTheGameIsKnown() {
        XCTAssertEqual(GameNames.title("maths-sprint"), "Quick Maths Sprint")
        XCTAssertTrue(GameDifficulty.easy.line(for: .mathsSprint).contains("20"))
    }
}
