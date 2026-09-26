import XCTest
@testable import SRAppleApp

/// Anagram Blitz: the spec's wire contract, and the rules the phone applies
/// itself — building a word from the tiles, shuffling them, the obvious refusals.
final class AnagramBlitzTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    // MARK: - The wire (the spec's JSON)

    private let playingJSON = #"""
    { "id":"g_a", "game":"anagram-blitz", "difficulty":"easy",
      "phase":"playing", "hostId":"p_a", "meId":"p_b",
      "letterCount":7, "minLength":3, "points":{"3":1,"4":2,"5":4,"6":6,"7":10},
      "timeLimitMs":150000, "startedAt":1790000000000, "phaseEndsAt":1790000150000,
      "letters":["t","r","e","n","i","a","p"],
      "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"wordCount":3,"score":7,"words":null},
                 {"id":"p_b","name":"John","status":"joined","isHost":false,"wordCount":1,"score":4,
                  "words":[{"word":"paint","points":4,"unique":null}]}],
      "seed": null, "found": null, "missed": null,
      "standings": null, "winnerIds": [], "serverNow":1790000030000 }
    """#

    func testAPlayingRoomDecodesFromTheContract() throws {
        let room = try decode(playingJSON)
        XCTAssertEqual(room.kind, .anagramBlitz)
        XCTAssertEqual(room.phase, .playing)
        XCTAssertEqual(room.letterCount, 7)
        XCTAssertEqual(room.minLength, 3)
        XCTAssertEqual(room.points["7"], 10)
        XCTAssertEqual(room.timeLimitMs, 150_000)
        XCTAssertEqual(room.startedAt, 1_790_000_000_000)
        XCTAssertEqual(room.phaseEndsAt, 1_790_000_150_000, "while playing, phaseEndsAt is the time limit")
        XCTAssertEqual(room.letters, ["t", "r", "e", "n", "i", "a", "p"])
        XCTAssertNil(room.seed, "the seed waits for the finish")
        XCTAssertNil(room.found)
        XCTAssertNil(room.missed)

        let me = try XCTUnwrap(room.me)
        XCTAssertEqual(me.wordCount, 1)
        XCTAssertEqual(me.score, 4)
        XCTAssertEqual(me.words, [AnagramWord(word: "paint", points: 4, unique: nil)])

        let sam = try XCTUnwrap(room.others.first)
        XCTAssertEqual(sam.wordCount, 3)
        XCTAssertEqual(sam.score, 7)
        XCTAssertNil(sam.words, "another player's words are a count until the finish")
        XCTAssertNil(room.round, "no Tap Duel round in an anagram room")
        XCTAssertNil(room.memory)
    }

    func testAFinishedRoomRevealsEverything() throws {
        let json = #"""
        { "id":"g_a", "game":"anagram-blitz", "difficulty":"hard", "phase":"finished",
          "hostId":"p_a", "meId":"p_a",
          "letterCount":7, "minLength":4, "points":{"3":1,"4":2,"5":4,"6":6,"7":10},
          "timeLimitMs":90000, "startedAt":1790000000000, "phaseEndsAt":1790000690000,
          "letters":["t","r","e","n","i","a","p"],
          "players":[{"id":"p_a","name":"John","status":"joined","isHost":true,"wordCount":2,"score":12,
                      "words":[{"word":"paint","points":8,"unique":true},{"word":"rate","points":2,"unique":false}]},
                     {"id":"p_b","name":"Sam","status":"joined","isHost":false,"wordCount":1,"score":2,
                      "words":[{"word":"rate","points":2,"unique":false}]}],
          "seed":"painter",
          "found":[{"word":"paint","points":4,"finderIds":["p_a"],"unique":true},
                   {"word":"rate","points":2,"finderIds":["p_a","p_b"],"unique":false}],
          "missed":["painter","pertain","repaint"],
          "standings":[{"id":"p_a","name":"John","score":12,"words":2,"longest":"paint"},
                       {"id":"p_b","name":"Sam","score":2,"words":1,"longest":"rate"}],
          "winnerIds":["p_a"], "serverNow":1790000100000 }
        """#
        let room = try decode(json)
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.minLength, 4)
        XCTAssertEqual(room.seed, "painter")
        XCTAssertEqual(room.missed, ["painter", "pertain", "repaint"])
        let found = try XCTUnwrap(room.found)
        XCTAssertEqual(found.map(\.word), ["paint", "rate"])
        XCTAssertTrue(found[0].unique)
        XCTAssertEqual(found[0].points, 4, "the base points")
        XCTAssertEqual(found[0].scored, 8, "a unique word scores double")
        XCTAssertEqual(found[1].finderIds, ["p_a", "p_b"])
        XCTAssertEqual(found[1].scored, 2)
        let standings = try XCTUnwrap(room.standings)
        XCTAssertEqual(standings[0].words, 2)
        XCTAssertEqual(standings[0].longest, "paint")
        XCTAssertEqual(standings[0].score, 12)
        XCTAssertEqual(room.winnerIds, ["p_a"])
        XCTAssertEqual(room.players[1].words?.first?.unique, false)
    }

    func testAWordBodyIsJustTheWord() throws {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(GameActionBody(action: "word", word: "paint"))) as? [String: Any]
        XCTAssertEqual(body?.count, 2)
        XCTAssertEqual(body?["action"] as? String, "word")
        XCTAssertEqual(body?["word"] as? String, "paint")
    }

    // MARK: - Building a word

    func testTilesAreUsedOnceEach() {
        var input = AnagramInput(tiles: ["t", "r", "e", "n", "i", "a", "p"])
        XCTAssertTrue(input.add("p"))
        XCTAssertTrue(input.add("a"))
        XCTAssertTrue(input.add("t"))
        XCTAssertFalse(input.add("t"), "one T on the board, one T in the word")
        XCTAssertFalse(input.add("z"), "a letter not on the board")
        XCTAssertEqual(input.word, "pat")
    }

    func testARepeatedLetterCanBeUsedAsOftenAsTheTilesHoldIt() {
        var input = AnagramInput(tiles: ["l", "e", "t", "t", "e", "r", "s"])
        XCTAssertTrue(input.add("e"))
        XCTAssertTrue(input.add("e"))
        XCTAssertFalse(input.add("e"), "two Es on the board")
        XCTAssertTrue(input.add("t"))
        XCTAssertTrue(input.add("t"))
        XCTAssertFalse(input.add("t"))
        XCTAssertEqual(input.word, "eett")
        XCTAssertEqual(Set(input.picked).count, input.picked.count, "no tile picked twice")
    }

    func testTappingAPickedTileTakesItBackOut() {
        var input = AnagramInput(tiles: ["t", "r", "e", "n", "i", "a", "p"])
        input.tap(6) // p
        input.tap(5) // a
        input.tap(4) // i
        XCTAssertEqual(input.word, "pai")
        XCTAssertTrue(input.isPicked(5))
        input.tap(5)
        XCTAssertEqual(input.word, "pi", "the middle letter comes out; the rest keep their order")
        XCTAssertFalse(input.isPicked(5))
        XCTAssertFalse(input.tap(9), "no such tile")
        XCTAssertTrue(input.delete())
        XCTAssertEqual(input.word, "p")
        input.clear()
        XCTAssertTrue(input.isEmpty)
        XCTAssertFalse(input.delete())
    }

    func testTwoTilesWithTheSameLetterAreDifferentTiles() {
        var input = AnagramInput(tiles: ["e", "e", "r"])
        input.tap(0)
        input.tap(1)
        XCTAssertEqual(input.word, "ee")
        input.tap(0)
        XCTAssertEqual(input.picked, [1], "the tapped tile comes out, not the first E")
    }

    func testShuffleIsAPermutationThatMoves() {
        var random = SeededRandom(seed: 7)
        let order = Array(0..<7)
        for _ in 0..<50 {
            let next = AnagramRules.shuffled(order, using: &random)
            XCTAssertEqual(next.sorted(), order, "every tile, once")
            XCTAssertNotEqual(next, order, "a shuffle that changes nothing looks broken")
        }
        XCTAssertEqual(AnagramRules.shuffled([3], using: &random), [3])
    }

    func testTheObviousRefusalsAnswerOnThePhone() {
        XCTAssertEqual(AnagramRules.localRefusal(word: "at", minLength: 3, mine: []), "Words need at least 3 letters.")
        XCTAssertEqual(AnagramRules.localRefusal(word: "pat", minLength: 4, mine: []), "Words need at least 4 letters on hard.")
        XCTAssertEqual(AnagramRules.localRefusal(word: "paint", minLength: 3, mine: ["paint"]), "You already have that one.")
        XCTAssertNil(AnagramRules.localRefusal(word: "paint", minLength: 3, mine: ["rate"]))
    }

    func testPointsComeFromTheRoomsTable() {
        let table = ["3": 1, "4": 2, "5": 4, "6": 6, "7": 10]
        XCTAssertEqual(AnagramRules.points(for: "painter", table: table), 10)
        XCTAssertEqual(AnagramRules.points(for: "pat", table: [:]), 1, "the spec's table when the room sent none")
    }

    func testTheNewGameSheetKnowsTheGame() {
        XCTAssertEqual(GameKind(rawValue: "anagram-blitz"), .anagramBlitz)
        XCTAssertEqual(GameNames.title("anagram-blitz"), "Anagram Blitz")
        XCTAssertTrue(GameDifficulty.hard.line(for: .anagramBlitz).contains("90 seconds"))
        let invite = GameInvite(roomId: "g_1", game: "anagram-blitz", difficulty: "easy", hostName: "Sam",
                                players: ["Sam", "John"], expiresAt: nil)
        XCTAssertEqual(invite.notificationTitle, "Sam invited you to Anagram Blitz")
    }
}

/// A deterministic generator for shuffle tests (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
