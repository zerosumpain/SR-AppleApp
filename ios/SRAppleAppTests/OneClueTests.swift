import XCTest
@testable import SRAppleApp

/// One Clue: the spec's wire contract for each seat at the table, and the
/// little the phone works out itself — the page, the typing warning, the veto
/// rule's reach, who the table waits on, the row of ten, the sentences.
final class OneClueTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    private let players = #"""
      "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"role":"guesser","submitted":false,"done":false},
                 {"id":"p_b","name":"John","status":"joined","isHost":false,"role":"clue","submitted":true,"done":false},
                 {"id":"p_c","name":"Kim","status":"joined","isHost":false,"role":"clue","submitted":false,"done":true}]
    """#

    private func room(_ fields: String, me: String = "p_b") -> String {
        """
        { "id":"g_o", "game":"one-clue", "difficulty":"medium", "hostId":"p_a", "meId":"\(me)",
          "cardCount":10, "minPlayers":3, "maxPlayers":7, "clueMs":75000, "reviewMs":30000, "guessMs":60000,
          "revealMs":12000, "maxClue":30, "maxGuess":40, "startedAt":1790000000000, "phaseEndsAt":1790000075000,
          "score":2, "cardIndex":3, "guesserId":"p_a", "cancelledCount":null, "guess":null, "outcome":null,
          "tookBack":false, "standings":null, "verdict":null, "winnerIds":[], "serverNow":1790000010000,
          "cards":[{"index":0,"word":"castle","guesserId":"p_b","outcome":"correct","guess":"castle","tookBack":false,
                    "clues":[{"playerId":"p_a","text":"Knight","status":"ok"},{"playerId":"p_c","text":"knights","status":"duplicate"}]},
                   {"index":1,"word":"fox","guesserId":"p_c","outcome":"wrong","guess":"wolf","tookBack":false,"clues":[]},
                   {"index":2,"word":"violin","guesserId":null,"outcome":"discarded","guess":null,"tookBack":false,"clues":[]}],
          \(players),
          \(fields) }
        """
    }

    // MARK: - The wire, seat by seat

    func testAClueGiverWhileWritingHasTheWordAndOnlyTheirOwnClue() throws {
        let r = try decode(room(#""phase":"clues", "role":"clue", "word":"lighthouse", "myClue":"Beam", "clues":null"#))
        XCTAssertEqual(r.kind, .oneClue)
        XCTAssertEqual(r.phase, .unknown, "clues is One Clue's own phase")
        XCTAssertEqual(OneClueRules.phase(r), .clues)
        let state = try XCTUnwrap(r.oneClue)
        XCTAssertEqual(state.role, .clue)
        XCTAssertEqual(state.word, "lighthouse")
        XCTAssertEqual(state.myClue, "Beam")
        XCTAssertNil(state.clues)
        XCTAssertEqual(state.score, 2)
        XCTAssertEqual(state.cardIndex, 3)
        XCTAssertEqual(state.giverIds, ["p_b", "p_c"])
        XCTAssertEqual(state.cards.map(\.outcome), [.correct, .wrong, .discarded])
        XCTAssertNil(state.cards[2].guesserId)
        XCTAssertEqual(OneClueRules.waitingOn(r).map(\.id), ["p_c"], "Kim has not written yet")
    }

    func testTheGuesserWhileGuessingHasSurvivorsAndACountOnly() throws {
        let r = try decode(room(#"""
        "phase":"guess", "role":"guesser", "word":null, "myClue":null, "cancelledCount":2,
        "clues":[{"playerId":"p_b","text":"Beam","status":"ok","vetoes":0,"strikeAt":0,"vetoed":false}]
        """#, me: "p_a"))
        let state = try XCTUnwrap(r.oneClue)
        XCTAssertEqual(OneClueRules.phase(r), .guess)
        XCTAssertNil(state.word)
        XCTAssertEqual(state.clues?.map(\.text), ["Beam"])
        XCTAssertEqual(state.cancelledCount, 2)
        XCTAssertEqual(OneClueRules.waitingOn(r).map(\.id), ["p_a"])
    }

    func testTheReviewShowsVetoesAndOnlyAnotherClueGiverMayVeto() throws {
        let clues = #"""
        "clues":[{"playerId":"p_b","text":"Beam","status":"ok","vetoes":0,"strikeAt":1,"vetoed":false},
                 {"playerId":"p_c","text":"Lamp","status":"vetoed","vetoes":1,"strikeAt":1,"vetoed":true},
                 {"playerId":"p_d","text":"lights","status":"too-close","vetoes":0,"strikeAt":1,"vetoed":false}]
        """#
        let mine = try decode(room(#""phase":"review", "role":"clue", "word":"lighthouse", "#  + clues))
        let state = try XCTUnwrap(mine.oneClue)
        XCTAssertEqual(state.clues?.map(\.status), [.ok, .vetoed, .tooClose])
        XCTAssertFalse(OneClueRules.canVeto(state.clues![0], room: mine), "not my own")
        XCTAssertTrue(OneClueRules.canVeto(state.clues![1], room: mine), "a vetoed clue can be un-vetoed")
        XCTAssertFalse(OneClueRules.canVeto(state.clues![2], room: mine), "the checks already took it out")
        XCTAssertEqual(OneClueRules.vetoLine(state.clues![1]), "1 of 1 veto")
        XCTAssertNil(OneClueRules.vetoLine(state.clues![0]))
        XCTAssertEqual(OneClueRules.waitingOn(mine).map(\.id), ["p_b"], "Kim is done")

        let guesser = try decode(room(#""phase":"review", "role":"guesser", "word":null, "clues":null"#, me: "p_a"))
        XCTAssertNil(guesser.oneClue?.clues)
        XCTAssertNil(guesser.oneClue?.word)
    }

    func testAnUnknownStatusOrRoleDoesNotBlankTheRoom() throws {
        let r = try decode(room(#"""
        "phase":"reveal", "role":"spectator", "word":"lighthouse", "outcome":"something-new",
        "clues":[{"playerId":"p_b","text":"Beam","status":"brand-new"}]
        """#))
        let state = try XCTUnwrap(r.oneClue)
        XCTAssertEqual(state.role, .unknown)
        XCTAssertEqual(state.outcome, .unknown)
        XCTAssertEqual(state.clues?.first?.status, .unknown)
    }

    func testOtherGamesHaveNoOneClueSide() throws {
        let json = #"{"id":"g","game":"categories","phase":"review","serverNow":1,"clues":[]}"#
        XCTAssertNil(try decode(json).oneClue)
    }

    // MARK: - The phone's own rules

    func testTheWarningWhileTyping() {
        XCTAssertNil(OneClueRules.warning("", word: "lighthouse"))
        XCTAssertNil(OneClueRules.warning("Beam", word: "lighthouse"))
        XCTAssertNil(OneClueRules.warning("  the beam ", word: "lighthouse"), "an article is dropped")
        XCTAssertNotNil(OneClueRules.warning("bright beam", word: "lighthouse"))
        XCTAssertNotNil(OneClueRules.warning("Lighthouses", word: "lighthouse"))
        XCTAssertNotNil(OneClueRules.warning("light", word: "lighthouse"))
        XCTAssertNil(OneClueRules.warning("Beam", word: nil))
        XCTAssertEqual(OneClueRules.cap("abcdef\nxyz", max: 5), "abcde")
    }

    func testThePipsAndLines() throws {
        let state = try XCTUnwrap(try decode(room(#""phase":"clues", "role":"clue", "word":"x""#)).oneClue)
        XCTAssertEqual(Array(OneClueRules.pips(state).prefix(5)), [.won, .lost, .discarded, .current, .toCome])
        XCTAssertEqual(OneClueRules.pips(state).count, 10)
        XCTAssertEqual(OneClueRules.cardLine(state), "Card 4 of 10")
        XCTAssertEqual(OneClueRules.outcomeLine(.correct, guesser: "Sam", isMe: false, tookBack: false), "Sam got it!")
        XCTAssertEqual(OneClueRules.outcomeLine(.correct, guesser: "Sam", isMe: true, tookBack: false), "You got it!")
        XCTAssertTrue(OneClueRules.outcomeLine(.wrong, guesser: "Sam", isMe: false, tookBack: false).contains("next"))
        XCTAssertTrue(OneClueRules.outcomeLine(.wrong, guesser: "Sam", isMe: false, tookBack: true).contains("goes back"))
        XCTAssertEqual(OneClueRules.scoreLine(7, of: 10), "7 out of 10")
        XCTAssertEqual(OneClueRules.verdict(10), "Perfect: ten out of ten!")
        XCTAssertEqual(OneClueRules.lobbyLine(playing: 2, min: 3, max: 7), "Needs at least 3 players — 1 more to start.")
        XCTAssertNil(OneClueRules.lobbyLine(playing: 5, min: 3, max: 7))
    }

    // MARK: - Pinned to the site

    func testTheGameIdAndTitleMatchTheSite() {
        // SR-Main: `catalogue.ts` GAME_IDS has "one-clue"; `invite-push.server.ts` TITLES says "One Clue".
        XCTAssertEqual(GameKind(rawValue: "one-clue"), .oneClue)
        XCTAssertEqual(GameKind.oneClue.title, "One Clue")
        XCTAssertEqual(GameNames.title("one-clue"), "One Clue")
        for level in GameDifficulty.allCases { XCTAssertFalse(level.line(for: .oneClue).isEmpty) }
    }

    // MARK: - Demo rooms

    func testTheDemoRoomsDecode() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date(timeIntervalSince1970: 1_791_200_000))
        let writing = try decode(try XCTUnwrap(SRDemoFixtures.oneClueDemoRoom(id: SRDemoFixtures.demoOneClueRoom, clock: clock)))
        XCTAssertEqual(OneClueRules.phase(writing), .clues)
        XCTAssertEqual(writing.oneClue?.word, "lighthouse")
        XCTAssertEqual(writing.oneClue?.cards.count, 3)

        let guessing = try decode(try XCTUnwrap(SRDemoFixtures.oneClueDemoRoom(id: SRDemoFixtures.demoOneClueGuessRoom, clock: clock)))
        XCTAssertEqual(OneClueRules.phase(guessing), .guess)
        XCTAssertNil(guessing.oneClue?.word, "a guesser's wire has no word")
        XCTAssertEqual(guessing.oneClue?.clues?.allSatisfy { $0.status == .ok }, true)
        XCTAssertEqual(guessing.oneClue?.cancelledCount, 2)

        let done = try decode(try XCTUnwrap(SRDemoFixtures.oneClueDemoRoom(id: SRDemoFixtures.demoOneClueDoneRoom, clock: clock)))
        XCTAssertEqual(OneClueRules.phase(done), .finished)
        XCTAssertEqual(done.oneClue?.score, 7)
        XCTAssertEqual(done.oneClue?.cards.count, 10)
        XCTAssertEqual(done.oneClue?.cards.filter { $0.outcome == .correct }.count, 7)
        XCTAssertEqual(done.standings?.map(\.score), [7, 7, 7])

        XCTAssertNil(SRDemoFixtures.oneClueDemoRoom(id: "g_demo_chess", clock: clock))
    }
}
