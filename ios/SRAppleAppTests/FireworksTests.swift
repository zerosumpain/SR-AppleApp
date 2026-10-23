import XCTest
@testable import SRAppleApp

/// Fireworks: the spec's wire contract (SR-Main `fireworks.ts` `toWire`), and
/// the little the phone works out itself — which cards a hint points at, what
/// a card is known to be, the log and the finish in sentences.
final class FireworksTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    // MARK: - The wire

    private let playingJSON = #"""
    { "id":"g_f", "game":"fireworks", "difficulty":"hard", "phase":"playing",
      "hostId":"p_a", "meId":"p_b", "rule":"Six colours.",
      "colours":["red","yellow","green","blue","white","prism"], "hintColours":["red","yellow","green","blue","white"],
      "turnMs":60000, "startedAt":1790000000000, "phaseEndsAt":1790000060000,
      "turnId":"p_b", "turn":3, "hints":6, "maxHints":8, "misfires":1, "maxMisfires":3,
      "deck":44, "finalTurns":null,
      "stacks":{"red":1,"yellow":0,"green":0,"blue":0,"white":0,"prism":0}, "score":1, "maxScore":30,
      "discards":[{"id":4,"colour":"blue","rank":3}],
      "log":[{"kind":"hint","by":"p_a","to":"p_b","colour":"red","rank":null,"cards":[7,9],"ok":null,"auto":false,"card":null},
             {"kind":"play","by":"p_a","to":null,"colour":null,"rank":null,"cards":[],"ok":true,"auto":false,"card":{"id":1,"colour":"red","rank":1}},
             {"kind":"discard","by":"p_b","to":null,"colour":null,"rank":null,"cards":[],"ok":null,"auto":true,"card":{"id":4,"colour":"blue","rank":3}}],
      "players":[
        {"id":"p_a","name":"Sam","status":"joined","isHost":true,"seated":true,
         "hand":[{"id":2,"colour":"prism","rank":2,"knows":{"colours":["red","yellow","green","blue","white","prism"],"ranks":[1,2,3,4,5],"hinted":false},"could":null},
                 {"id":3,"colour":"green","rank":2,"knows":{"colours":["red","yellow","green","blue","white","prism"],"ranks":[1,2,3,4,5],"hinted":false},"could":null},
                 {"id":5,"colour":"red","rank":5,"knows":{"colours":["red","yellow","green","blue","white","prism"],"ranks":[5],"hinted":true},"could":null}]},
        {"id":"p_b","name":"John","status":"joined","isHost":false,"seated":true,
         "hand":[{"id":7,"colour":null,"rank":null,"knows":{"colours":["red","prism"],"ranks":[1,2,3,4,5],"hinted":true},"could":null},
                 {"id":8,"colour":null,"rank":null,"knows":{"colours":["yellow","green","blue","white"],"ranks":[1,2,3,4,5],"hinted":false},"could":null},
                 {"id":9,"colour":null,"rank":null,"knows":{"colours":["red","prism"],"ranks":[3],"hinted":true},"could":null}]}],
      "ending":null, "standings":null, "winnerIds":[], "serverNow":1790000010000 }
    """#

    func testAPlayingRoomDecodesFromTheContract() throws {
        let room = try decode(playingJSON)
        XCTAssertEqual(room.kind, .fireworks)
        XCTAssertEqual(room.phase, .playing)
        XCTAssertEqual(FireworksScreenPhase.of(room), .playing)
        let state = try XCTUnwrap(room.fireworks)
        XCTAssertEqual(state.colours.count, 6)
        XCTAssertEqual(state.hintColours.count, 5)
        XCTAssertEqual(state.hints, 6)
        XCTAssertEqual(state.misfires, 1)
        XCTAssertEqual(state.maxMisfires, 3)
        XCTAssertEqual(state.deck, 44)
        XCTAssertNil(state.finalTurns)
        XCTAssertEqual(state.top("red"), 1)
        XCTAssertEqual(state.top("prism"), 0)
        XCTAssertEqual(state.score, 1)
        XCTAssertEqual(state.maxScore, 30)
        XCTAssertEqual(state.discards.map(\.id), [4])
        XCTAssertEqual(state.log.map(\.kind), [.hint, .play, .discard])
        XCTAssertEqual(state.log[0].cards, [7, 9])
        XCTAssertTrue(state.log[2].auto)
        XCTAssertEqual(state.seat("p_a")?.hand.count, 3)
    }

    func testMyOwnCardsArriveAsKnowledgeOnly() throws {
        let state = try XCTUnwrap(try decode(playingJSON).fireworks)
        let mine = try XCTUnwrap(state.seat("p_b")).hand
        XCTAssertTrue(mine.allSatisfy { !$0.visible }, "my own cards are never face up")
        XCTAssertEqual(mine[0].knows?.colours, ["red", "prism"])
        XCTAssertEqual(mine[2].knows?.rank, 3)
        XCTAssertNil(mine[1].knows?.rank)
        let theirs = try XCTUnwrap(state.seat("p_a")).hand
        XCTAssertTrue(theirs.allSatisfy(\.visible))
    }

    func testAnotherGamesRoomCarriesNoFireworks() throws {
        let room = try decode(#"{"id":"g","game":"tap-duel","phase":"lobby","serverNow":1}"#)
        XCTAssertNil(room.fireworks)
    }

    func testALobbyWithNoneOfItStillDecodes() throws {
        let room = try decode(#"{"id":"g","game":"fireworks","difficulty":"easy","phase":"lobby","serverNow":1,"players":[]}"#)
        XCTAssertEqual(FireworksScreenPhase.of(room), .lobby)
        XCTAssertEqual(room.fireworks?.hints, 8)
        XCTAssertEqual(room.fireworks?.colours, FireworksRules.baseColours)
    }

    // MARK: - Hints

    func testAColourHintPointsAtItsColourAndEveryPrism() throws {
        let hand = try XCTUnwrap(try decode(playingJSON).fireworks?.seat("p_a")).hand
        XCTAssertEqual(FireworksRules.touched(.colour("red"), in: hand), [2, 5])
        XCTAssertEqual(FireworksRules.touched(.colour("green"), in: hand), [2, 3])
        XCTAssertEqual(FireworksRules.touched(.rank(2), in: hand), [2, 3])
        XCTAssertEqual(FireworksRules.touched(.rank(4), in: hand), [])
    }

    func testOnlyHintsThatPointAtSomethingAreOffered() throws {
        let hand = [FireworksCard(id: 1, colour: "red", rank: 1), FireworksCard(id: 2, colour: "blue", rank: 4)]
        XCTAssertEqual(FireworksRules.possibleHints(for: hand),
                       [.colour("red"), .colour("blue"), .rank(1), .rank(4)])
        // Prism is never named, but every colour hint lights it.
        let prism = [FireworksCard(id: 3, colour: "prism", rank: 2)]
        XCTAssertEqual(FireworksRules.possibleHints(for: prism).count, 6)
        XCTAssertFalse(FireworksRules.possibleHints(for: prism).contains(.colour("prism")))
        XCTAssertEqual(FireworksRules.possibleHints(for: [FireworksCard(id: 9, colour: nil, rank: nil)]), [])
    }

    func testPlayableReadsTheStacks() {
        let stacks = ["red": 2, "blue": 0]
        XCTAssertTrue(FireworksRules.playable(FireworksCard(id: 1, colour: "red", rank: 3), stacks: stacks))
        XCTAssertFalse(FireworksRules.playable(FireworksCard(id: 2, colour: "red", rank: 2), stacks: stacks))
        XCTAssertTrue(FireworksRules.playable(FireworksCard(id: 3, colour: "blue", rank: 1), stacks: stacks))
        XCTAssertFalse(FireworksRules.playable(FireworksCard(id: 4, colour: nil, rank: nil), stacks: stacks))
    }

    // MARK: - Words

    func testWhatACardIsKnownToBe() {
        let five = FireworksRules.baseColours
        let six = five + ["prism"]
        func k(_ c: [String], _ r: [Int]) -> FireworksKnowledge { FireworksKnowledge(colours: c, ranks: r, hinted: true) }
        XCTAssertEqual(FireworksRules.knownText(k(["red"], [3]), allColours: five), "Red 3")
        XCTAssertEqual(FireworksRules.knownText(k(["red", "prism"], [1, 2, 3, 4, 5]), allColours: six), "Red or Prism")
        XCTAssertEqual(FireworksRules.knownText(k(five, [4]), allColours: five), "A 4")
        XCTAssertEqual(FireworksRules.knownText(k(five, [2, 3, 4]), allColours: five), "Not 1 or 5")
        XCTAssertEqual(FireworksRules.knownText(k(["yellow", "green", "blue", "white"], [1, 2, 3, 4, 5]), allColours: five), "Not red")
        XCTAssertEqual(FireworksRules.knownText(k(five, [1, 2, 3, 4, 5]), allColours: five), "Nothing yet")
        XCTAssertEqual(FireworksRules.knownText(nil, allColours: five), "Nothing yet")
    }

    func testEasyCouldBeLine() {
        XCTAssertEqual(FireworksRules.couldText(FireworksKnowledge(colours: ["red", "blue"], ranks: [1, 2], hinted: false)),
                       "Could be red, blue · 1, 2")
        XCTAssertNil(FireworksRules.couldText(nil))
    }

    func testTheLogReadsAsSentences() throws {
        let room = try decode(playingJSON)
        let state = try XCTUnwrap(room.fireworks)
        let name: (String) -> String = { $0 == room.meId ? "You" : room.name(of: $0) }
        XCTAssertEqual(FireworksRules.logLine(state.log[0], name: name), "Sam pointed at 2 red cards in your hand.")
        XCTAssertEqual(FireworksRules.logLine(state.log[1], name: name), "Sam played the Red 1. Bang!")
        XCTAssertEqual(FireworksRules.logLine(state.log[2], name: name), "You ran out of time: the Blue 3 was dropped.")
    }

    func testTheFinishInWords() throws {
        let json = #"""
        {"id":"g","game":"fireworks","phase":"finished","serverNow":1,"score":25,"maxScore":25,"ending":"perfect",
         "standings":[{"id":"p_a","name":"Sam","place":1,"score":25,"maxScore":25,"left":false}],"winnerIds":["p_a"]}
        """#
        let state = try XCTUnwrap(try decode(json).fireworks)
        XCTAssertEqual(FireworksRules.endingLine(state), "A perfect show: every firework went up. 25 of 25.")
        XCTAssertEqual(state.standings?.first?.score, 25)
        XCTAssertEqual(FireworksRules.verdict(score: 25, max: 25), "Legendary")
        XCTAssertEqual(FireworksRules.verdict(score: 0, max: 25), "Damp squib")
    }

    func testTheLevelsCountMisfiresTheWayTheServerDoes() {
        // Server: MISFIRES = easy 4, medium 3, hard 3, and the show ends ON that misfire.
        XCTAssertTrue(GameDifficulty.easy.line(for: .fireworks).contains("fourth misfire ends"))
        XCTAssertTrue(GameDifficulty.medium.line(for: .fireworks).contains("third misfire ends"))
        XCTAssertTrue(GameDifficulty.hard.line(for: .fireworks).contains("third misfire ends"))
        for level in GameDifficulty.allCases {
            XCTAssertFalse(level.line(for: .fireworks).contains("allowed"), "a misfire count is a limit, not an allowance")
        }
        XCTAssertFalse(GameKind.fireworks.blurb.contains("three misfires"), "the description is the same for every level")
    }

    func testTheNewGameSheetNeverCallsItSolo() {
        XCTAssertEqual(FireworksRules.minPlayers, 2)
        XCTAssertEqual(FireworksRules.maxPlayers, 5)
        for line in [FireworksRules.sheetTrailing, FireworksRules.sheetNobody, FireworksRules.sheetPick] {
            XCTAssertFalse(line.lowercased().contains("solo"), line)
        }
        XCTAssertTrue(FireworksRules.sheetNobody.contains("two to five"))
    }

    func testLeavingSaysWhetherTheShowGoesOn() {
        XCTAssertTrue(FireworksRules.leaveWarning(staying: 1).contains("show ends"))
        XCTAssertTrue(FireworksRules.leaveWarning(staying: 2).contains("plays on"))
    }

    func testTheTeamTableHasNoPlaces() {
        XCTAssertEqual(FireworksRules.teamDetail(left: true), "Left early")
        XCTAssertEqual(FireworksRules.teamDetail(left: false), "Played to the end")
    }

    func testTheTurnBarEmpties() {
        XCTAssertEqual(FireworksRules.turnLeft(endsAt: 1_000, turnMs: 1_000, now: 500), 0.5)
        XCTAssertEqual(FireworksRules.turnLeft(endsAt: 1_000, turnMs: 1_000, now: 5_000), 0)
        XCTAssertEqual(FireworksRules.turnLeft(endsAt: nil, turnMs: 1_000, now: 5_000), 1)
    }

    // MARK: - What the phone sends

    func testMoveBodies() throws {
        var hint = GameActionBody(action: "hint")
        hint.to = "p_a"
        hint.colour = "red"
        let hintJSON = String(decoding: try JSONEncoder().encode(hint), as: UTF8.self)
        XCTAssertTrue(hintJSON.contains(#""to":"p_a""#))
        XCTAssertTrue(hintJSON.contains(#""colour":"red""#))
        XCTAssertFalse(hintJSON.contains("rank"), "nil fields stay out")
        var play = GameActionBody(action: "play")
        play.card = 17
        let playJSON = String(decoding: try JSONEncoder().encode(play), as: UTF8.self)
        XCTAssertTrue(playJSON.contains(#""card":17"#))
    }

    func testTheGameIsOnTheShelfUnderTheServersId() {
        XCTAssertEqual(GameKind(rawValue: "fireworks"), .fireworks)
        XCTAssertTrue(GameKind.allCases.contains(.fireworks))
        XCTAssertEqual(GameKind.fireworks.title, "Fireworks")
        let body = CreateGameBody(game: GameKind.fireworks.rawValue, difficulty: "hard", invite: ["p_b"])
        XCTAssertEqual(body.game, "fireworks")
    }

    // MARK: - The demo rooms

    func testTheDemoRoomsDecodeAndHideMyCards() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let playing = try decode(SRDemoFixtures.fireworksRoom(finished: false, clock: clock))
        let state = try XCTUnwrap(playing.fireworks)
        XCTAssertEqual(FireworksScreenPhase.of(playing), .playing)
        XCTAssertEqual(state.turnId, playing.meId)
        XCTAssertEqual(state.seats.count, 3)
        let mine = try XCTUnwrap(state.seat(playing.meId)).hand
        XCTAssertEqual(mine.count, 5)
        XCTAssertTrue(mine.allSatisfy { !$0.visible })
        XCTAssertNotNil(mine[0].could, "easy says what each card could be")
        let done = try decode(SRDemoFixtures.fireworksRoom(finished: true, clock: clock))
        XCTAssertEqual(FireworksScreenPhase.of(done), .finished)
        XCTAssertEqual(done.fireworks?.score, 22)
        XCTAssertEqual(done.standings?.count, 3)
    }
}
