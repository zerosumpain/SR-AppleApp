import XCTest
@testable import SRAppleApp

/// Categories: the spec's wire contract, and the rules the phone applies
/// itself — the letter warning, who may veto what, the round the host picks.
final class CategoriesTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    // MARK: - The wire (the spec's JSON)

    private let playingJSON = #"""
    { "id":"g_c", "game":"categories", "difficulty":"easy", "phase":"playing",
      "hostId":"p_a", "meId":"p_b",
      "categoryCount":3, "timeLimitMs":90000, "reviewMs":60000, "maxAnswer":40,
      "startedAt":1790000000000, "phaseEndsAt":1790000090000,
      "letter":"B", "categories":["An animal","A food","A country"],
      "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"filled":2,"done":false,"score":0,"answers":null},
                 {"id":"p_b","name":"John","status":"joined","isHost":false,"filled":1,"done":false,"score":0,
                  "answers":[{"index":0,"text":"Badger","status":null,"points":0,"vetoes":0,"strikeAt":0,"vetoed":false},
                             {"index":1,"text":"","status":null,"points":0,"vetoes":0,"strikeAt":0,"vetoed":false},
                             {"index":2,"text":"","status":null,"points":0,"vetoes":0,"strikeAt":0,"vetoed":false}]}],
      "standings": null, "winnerIds": [], "serverNow":1790000030000 }
    """#

    func testAPlayingRoomDecodesFromTheContract() throws {
        let room = try decode(playingJSON)
        XCTAssertEqual(room.kind, .categories)
        XCTAssertEqual(room.phase, .playing)
        XCTAssertEqual(room.categoryCount, 3)
        XCTAssertEqual(room.timeLimitMs, 90_000)
        XCTAssertEqual(room.reviewMs, 60_000)
        XCTAssertEqual(room.maxAnswer, 40)
        XCTAssertEqual(room.letter, "b", "the letter is lower-cased")
        XCTAssertEqual(room.categories, ["An animal", "A food", "A country"])

        let me = try XCTUnwrap(room.me)
        XCTAssertEqual(me.filled, 1)
        XCTAssertEqual(me.categoryAnswers?.count, 3)
        XCTAssertEqual(me.categoryAnswers?.first, CategoriesAnswer(index: 0, text: "Badger"))
        XCTAssertNil(me.categoryAnswers?.first?.status, "no judgement while playing")
        let sam = try XCTUnwrap(room.others.first)
        XCTAssertEqual(sam.filled, 2)
        XCTAssertNil(sam.categoryAnswers, "another player's answers are a count until the review")
    }

    func testAReviewRoomRevealsEveryAnswerJudged() throws {
        let json = #"""
        { "id":"g_c", "game":"categories", "difficulty":"hard", "phase":"review",
          "hostId":"p_a", "meId":"p_a", "categoryCount":2, "timeLimitMs":120000, "reviewMs":60000,
          "phaseEndsAt":1790000180000, "letter":"b", "categories":["An animal","A food"],
          "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"filled":2,"done":true,"score":1,
                      "answers":[{"index":0,"text":"Bear","status":"shared","points":0,"vetoes":0,"strikeAt":1,"vetoed":false},
                                 {"index":1,"text":"Bagel","status":"ok","points":1,"vetoes":0,"strikeAt":1,"vetoed":false}]},
                     {"id":"p_b","name":"John","status":"joined","isHost":false,"filled":2,"done":false,"score":0,
                      "answers":[{"index":0,"text":"the bear","status":"shared","points":0,"vetoes":0,"strikeAt":1,"vetoed":false},
                                 {"index":1,"text":"Bogus","status":"struck","points":0,"vetoes":1,"strikeAt":1,"vetoed":true}]}],
          "standings": null, "winnerIds": [], "serverNow":1790000130000 }
        """#
        let room = try decode(json)
        XCTAssertEqual(room.phase, .review)
        XCTAssertEqual(CategoriesRules.contenders(room).map(\.id), ["p_a", "p_b"])
        XCTAssertEqual(room.me?.done, true)
        let john = try XCTUnwrap(room.others.first?.categoryAnswers)
        XCTAssertEqual(john[0].status, .shared)
        XCTAssertEqual(john[1], CategoriesAnswer(index: 1, text: "Bogus", status: .struck, points: 0,
                                                 vetoes: 1, strikeAt: 1, vetoed: true))
        XCTAssertEqual(CategoriesRules.waitingOn(room).map(\.id), ["p_b"])
    }

    func testAFinishedRoomDecodesStandings() throws {
        let json = #"""
        { "id":"g_c", "game":"categories", "phase":"finished", "hostId":"p_a", "meId":"p_a",
          "letter":"t", "categories":["A sport"],
          "players":[{"id":"p_a","name":"Sam","status":"joined","filled":1,"score":1,
                      "answers":[{"index":0,"text":"Tennis","status":"ok","points":1}]}],
          "standings":[{"id":"p_a","name":"Sam","score":1,"filled":1}], "winnerIds":[], "serverNow":1 }
        """#
        let room = try decode(json)
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.first?.score, 1)
        XCTAssertEqual(room.categoryCount, 8, "a missing count reads as the default")
    }

    func testTheReviewPhaseIsKnownAndOddStatusesDoNotThrow() throws {
        XCTAssertEqual(GamePhase(rawValue: "review"), .review)
        let answer = try JSONDecoder().decode(CategoriesAnswer.self,
                                              from: Data(#"{"index":2,"status":"brand-new"}"#.utf8))
        XCTAssertEqual(answer.status, .unknown)
        XCTAssertEqual(answer.text, "")
        XCTAssertEqual(answer.vetoes, 0)
        XCTAssertEqual(CategoriesStatus.wrongLetter.rawValue, "wrong-letter")
    }

    func testFilledFallsBackToCountingAnswers() throws {
        let player = try JSONDecoder().decode(GamePlayer.self, from: Data(#"""
        {"id":"p","answers":[{"index":0,"text":"Bat"},{"index":1,"text":""},{"index":2,"text":"Bun"}]}
        """#.utf8))
        XCTAssertEqual(player.filled, 2)
    }

    // MARK: - The rules

    func testNormalisingReadsPastCaseAccentsPunctuationAndArticles() {
        XCTAssertEqual(CategoriesRules.normalise("  The   Beatles! "), "beatles")
        XCTAssertEqual(CategoriesRules.normalise("an Owl"), "owl")
        XCTAssertEqual(CategoriesRules.normalise("Éclair"), "eclair")
        XCTAssertEqual(CategoriesRules.normalise("The"), "the")
        XCTAssertEqual(CategoriesRules.normalise("Rock 'n' roll"), "rock n roll")
    }

    func testTheLetterWarningOnlyShowsForAWrittenWrongAnswer() {
        XCTAssertTrue(CategoriesRules.startsWith("The Beatles", letter: "b"))
        XCTAssertTrue(CategoriesRules.startsWith("a banana", letter: "B"))
        XCTAssertFalse(CategoriesRules.startsWith("Apple", letter: "b"))
        XCTAssertNil(CategoriesRules.warning("", letter: "b"))
        XCTAssertNil(CategoriesRules.warning("   ", letter: "b"))
        XCTAssertNil(CategoriesRules.warning("Badger", letter: "b"))
        XCTAssertNil(CategoriesRules.warning("Dog", letter: nil))
        XCTAssertEqual(CategoriesRules.warning("Dog", letter: "b"), "Doesn't start with B")
    }

    func testADraftIsCappedAndFlattened() {
        XCTAssertEqual(CategoriesRules.cap("Big\nBen", max: 40), "Big Ben")
        XCTAssertEqual(CategoriesRules.cap(String(repeating: "b", count: 50), max: 40).count, 40)
    }

    func testOnlySomebodyElsesWrittenAnswerCanBeVetoedInTheReview() throws {
        let json = #"""
        { "id":"g_c", "game":"categories", "phase":"review", "hostId":"p_a", "meId":"p_a",
          "letter":"b", "categories":["An animal"],
          "players":[{"id":"p_a","name":"Sam","status":"joined"},{"id":"p_b","name":"John","status":"joined"}],
          "serverNow":1 }
        """#
        let room = try decode(json)
        let written = CategoriesAnswer(index: 0, text: "Bat", status: .ok)
        let blank = CategoriesAnswer(index: 0, text: "", status: .empty)
        XCTAssertTrue(CategoriesRules.canVeto(written, ownerId: "p_b", room: room))
        XCTAssertFalse(CategoriesRules.canVeto(written, ownerId: "p_a", room: room), "not my own")
        XCTAssertFalse(CategoriesRules.canVeto(blank, ownerId: "p_b", room: room), "not an empty slot")

        let finished = try decode(json.replacingOccurrences(of: #""phase":"review""#, with: #""phase":"finished""#))
        XCTAssertFalse(CategoriesRules.canVeto(written, ownerId: "p_b", room: finished), "not after the review")
    }

    func testTheVetoLine() {
        XCTAssertNil(CategoriesRules.vetoLine(CategoriesAnswer(index: 0, text: "Bat", vetoes: 0, strikeAt: 2)))
        XCTAssertEqual(CategoriesRules.vetoLine(CategoriesAnswer(index: 0, text: "Bat", vetoes: 1, strikeAt: 2)),
                       "1 of 2 vetoes")
        XCTAssertEqual(CategoriesRules.vetoLine(CategoriesAnswer(index: 0, text: "Bat", vetoes: 1, strikeAt: 1)),
                       "1 of 1 veto")
    }

    func testStatusTags() {
        XCTAssertEqual(CategoriesStatus.struck.tag, "VETOED")
        XCTAssertEqual(CategoriesStatus.shared.tag, "SHARED")
        XCTAssertNil(CategoriesStatus.ok.tag)
        XCTAssertTrue(CategoriesStatus.wrongLetter.crossed)
        XCTAssertFalse(CategoriesStatus.empty.crossed)
    }

    // MARK: - The round and the bodies

    func testTheCreateBodyCarriesTheRound() throws {
        let body = CategoriesSettings(difficulty: .medium, count: 10, seconds: 180).createBody(invite: ["p_b"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(json["game"] as? String, "categories")
        XCTAssertEqual(json["difficulty"] as? String, "medium")
        XCTAssertEqual(json["categoryCount"] as? Int, 10)
        XCTAssertEqual(json["seconds"] as? Int, 180)
        XCTAssertNil(json["size"], "Boggle's fields are left out")
        XCTAssertEqual(CategoriesSettings.line(count: 8, seconds: 120),
                       "8 categories in 2 min — about 15 seconds an answer.")
    }

    func testActionBodies() throws {
        let answer = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            GameActionBody(action: "answer", index: 2, text: "Bat"))) as? [String: Any])
        XCTAssertEqual(answer["action"] as? String, "answer")
        XCTAssertEqual(answer["index"] as? Int, 2)
        XCTAssertEqual(answer["text"] as? String, "Bat")
        let veto = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            GameActionBody(action: "veto", index: 0, playerId: "p_b"))) as? [String: Any])
        XCTAssertEqual(veto["playerId"] as? String, "p_b")
        XCTAssertNil(veto["text"])
    }

    func testTheLobbyLineAndTheGameKind() throws {
        XCTAssertEqual(GameKind(rawValue: "categories"), .categories)
        XCTAssertEqual(GameKind.categories.title, "Categories")
        let room = try decode(playingJSON)
        XCTAssertEqual(CategoriesSettings.about(room), "3 categories · 90 s")
    }
}
