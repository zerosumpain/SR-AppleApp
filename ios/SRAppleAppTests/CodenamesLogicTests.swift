import XCTest
@testable import SRAppleApp

/// Codenames: the spec's wire contract (SR-Main `codenames.ts` `toWire`), the
/// clue check ported from the server's `clueProblem` (its own cases, kept in
/// step), the move bodies, and the sentences the phone says. Pure: these run
/// on Linux in `home-check.sh`.
final class CodenamesLogicTests: XCTestCase {

    private func decode(_ json: String) throws -> CodenamesState {
        try JSONDecoder().decode(CodenamesState.self, from: Data(json.utf8))
    }

    private func object(_ body: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// 25 cards, three turned over; `key` stands in for the spymaster's.
    private static func cards(turned: [Int: (String, String)] = [:]) -> String {
        let words = ["bank", "snowman", "running", "apple", "bridge", "castle", "cloud", "dragon", "engine",
                     "forest", "garden", "hammer", "island", "jacket", "kettle", "ladder", "magnet", "needle",
                     "orange", "pirate", "rocket", "saddle", "tunnel", "violin", "window"]
        return "[" + words.enumerated().map { i, w in
            if let (kind, by) = turned[i] {
                return #"{"i":\#(i),"word":"\#(w)","kind":"\#(kind)","by":"\#(by)","turn":1}"#
            }
            return #"{"i":\#(i),"word":"\#(w)","kind":null,"by":null,"turn":null}"#
        }.joined(separator: ",") + "]"
    }

    private static let key = #"["red","red","red","red","red","red","red","red","red","blue","blue","blue","blue","blue","blue","blue","blue","neutral","neutral","neutral","neutral","neutral","neutral","neutral","assassin"]"#

    private static func room(me: String, key: Bool, phase: String = "guess", canGuess: Bool = false,
                             canClue: Bool = false) -> String {
        """
        { "id":"g_c", "game":"codenames", "difficulty":"medium", "phase":"\(phase)", "hostId":"p_a", "meId":"\(me)",
          "mode":"teams", "clueMs":150000, "guessMs":150000, "startedAt":1790000000000, "phaseEndsAt":1790000150000,
          "starting":"red", "turnTeam":"red", "turns":3,
          "cards": \(cards(turned: [0: ("red", "p_b"), 9: ("blue", "p_d"), 17: ("neutral", "p_b")])),
          "key": \(key ? Self.key : "null"),
          "clue": {"team":"red","by":"p_a","word":"OCEAN","count":2,"cards":[0],"at":1790000100000,"guessesLeft":2},
          "clues": [{"team":"red","by":"p_a","word":"TREE","count":2,"cards":[17],"at":1790000010000},
                    {"team":"blue","by":"p_c","word":"MUSIC","count":1,"cards":[9],"at":1790000050000},
                    {"team":"red","by":"p_a","word":"OCEAN","count":2,"cards":[0],"at":1790000100000}],
          "teams": [{"team":"red","agents":9,"left":8,"spymasterId":"p_a"},{"team":"blue","agents":8,"left":7,"spymasterId":"p_c"}],
          "last": {"card":0,"kind":"red","team":"red","by":"p_b","at":1790000110000},
          "canGuess": \(canGuess), "canClue": \(canClue),
          "players": [{"id":"p_a","name":"Sam","status":"joined","isHost":true,"team":"red","spymaster":true},
                      {"id":"p_b","name":"John","status":"joined","isHost":false,"team":"red","spymaster":false},
                      {"id":"p_c","name":"Kit","status":"joined","isHost":false,"team":"blue","spymaster":true},
                      {"id":"p_d","name":"Ali","status":"joined","isHost":false,"team":"blue","spymaster":false}],
          "result": null, "standings": null, "winnerIds": [], "serverNow":1790000120000 }
        """
    }

    // MARK: - The wire

    func testAnOperativeSeesOnlyTheTurnedCards() throws {
        let state = try decode(Self.room(me: "p_b", key: false, canGuess: true))
        XCTAssertEqual(state.phase, .guess)
        XCTAssertEqual(state.mode, .teams)
        XCTAssertEqual(state.cards.count, 25)
        XCTAssertNil(state.key)
        XCTAssertFalse(state.seesKey)
        XCTAssertEqual(state.shownKind(0), .red)
        XCTAssertEqual(state.shownKind(17), .neutral)
        XCTAssertNil(state.shownKind(24), "the assassin is never sent to an operative")
        XCTAssertEqual(state.faceDownWords.count, 22)
        XCTAssertFalse(state.faceDownWords.contains("bank"))
        XCTAssertEqual(state.myTeam, .red)
        XCTAssertFalse(state.amSpymaster)
        XCTAssertTrue(state.canGuess)
        XCTAssertTrue(state.canPass, "a card is turned on this clue")
        XCTAssertEqual(state.guessesLeft, 2)
        XCTAssertEqual(state.clue?.word, "OCEAN")
        XCTAssertEqual(state.clues.count, 3)
        XCTAssertEqual(state.side(.red)?.found, 1)
        XCTAssertEqual(state.side(.blue)?.left, 7)
        XCTAssertEqual(state.spymaster(.blue)?.name, "Kit")
        XCTAssertEqual(state.members(.red).map(\.id), ["p_a", "p_b"], "spymaster first")
        XCTAssertEqual(state.last?.card, 0)
        XCTAssertFalse(state.last?.auto ?? true)
    }

    func testASpymasterHoldsTheKey() throws {
        let state = try decode(Self.room(me: "p_a", key: true, phase: "clue", canClue: true))
        XCTAssertEqual(state.key?.count, 25)
        XCTAssertTrue(state.seesKey)
        XCTAssertTrue(state.amSpymaster)
        XCTAssertEqual(state.shownKind(24), .assassin)
        XCTAssertEqual(state.shownKind(10), .blue)
        XCTAssertTrue(state.canClue)
        XCTAssertFalse(state.canPass)
        XCTAssertEqual(CodenamesRules.headline(state), "Your clue")
    }

    func testAKeyThatIsNotOneIsIgnored() throws {
        let json = Self.room(me: "p_a", key: false).replacingOccurrences(of: #""key": null"#, with: #""key": ["red","purple"]"#)
        XCTAssertNil(try decode(json).key)
    }

    func testTheLobbyPreviewsTheModeAndThePicks() throws {
        let state = try decode(#"""
        {"id":"g_c","game":"codenames","phase":"lobby","hostId":"p_a","meId":"p_b","mode":"coop","cards":[],"key":null,
         "clue":null,"clues":[],"teams":[{"team":"red","agents":0,"left":0,"spymasterId":null},{"team":"blue","agents":0,"left":0,"spymasterId":null}],
         "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"team":"blue","spymaster":true},
                    {"id":"p_b","name":"John","status":"joined","isHost":false,"team":null,"spymaster":false},
                    {"id":"p_c","name":"Kit","status":"invited","isHost":false,"team":null,"spymaster":false}],
         "serverNow":1}
        """#)
        XCTAssertEqual(state.phase, .lobby)
        XCTAssertEqual(state.mode, .coop)
        XCTAssertEqual(state.anywhere.map(\.id), ["p_b"], "only joined players count as anywhere")
        XCTAssertEqual(state.members(.blue).first?.id, "p_a")
        XCTAssertTrue(state.seat("p_a")?.spymaster == true)
        XCTAssertFalse(state.amSpymaster, "a lobby ask is not the role")
        XCTAssertEqual(CodenamesRules.modeHint(.coop, joined: 2), "2 more players and it's two teams.")
        XCTAssertEqual(CodenamesRules.modeHint(.coop, joined: 3), "One more player and it's two teams.")
        XCTAssertNil(CodenamesRules.modeHint(.teams, joined: 5))
    }

    func testTheFinishShowsTheKeyAndTheTable() throws {
        let json = Self.room(me: "p_b", key: true, phase: "finished")
            .replacingOccurrences(of: #""result": null"#, with: #""result": {"winner":null,"reason":"agents"}"#)
            .replacingOccurrences(of: #""standings": null"#, with: #"""
            "standings": [{"id":"p_a","name":"Sam","team":"red","spymaster":true,"score":6,"place":2,"result":"lost"},
                          {"id":"p_b","name":"John","team":"red","spymaster":false,"score":6,"place":2,"result":"left"}]
            """#)
        let state = try decode(json)
        XCTAssertEqual(state.phase, .finished)
        XCTAssertNotNil(state.result)
        XCTAssertNil(state.result?.winner, "co-op lost")
        XCTAssertEqual(state.standing("p_b")?.result, "left")
        XCTAssertEqual(state.standing("p_a")?.score, 6)
        XCTAssertEqual(state.shownKind(24), .assassin)
        XCTAssertEqual(CodenamesRules.endingTitle(state.result, mode: .coop, myTeam: .red), "Blue got there first")
    }

    func testAnOddCardAndPhaseReadLeniently() throws {
        let card = try JSONDecoder().decode(CodenamesCard.self, from: Data(#"{"i":3,"word":"kite","kind":"plaid"}"#.utf8))
        XCTAssertNil(card.kind)
        XCTAssertTrue(card.faceDown)
        XCTAssertEqual(CodenamesPhase.from("vote"), .unknown)
        XCTAssertTrue(CodenamesPhase.guess.inPlay)
        XCTAssertFalse(CodenamesPhase.lobby.inPlay)
    }

    // MARK: - The clue check (the server's cases)

    func testAClueOnTheBoardIsRefused() {
        let board = ["bank", "snowman", "running"]
        XCTAssertEqual(CodenamesRules.clueProblem("Bank", faceDown: board), "That is a word on the board.")
        XCTAssertEqual(CodenamesRules.clueProblem("banks", faceDown: board), "That is a word on the board.")
        XCTAssertEqual(CodenamesRules.clueProblem("snow", faceDown: board), "Too close to SNOWMAN.")
        XCTAssertEqual(CodenamesRules.clueProblem("bankrupt", faceDown: board), "Too close to BANK.")
        XCTAssertEqual(CodenamesRules.clueProblem("run", faceDown: board), "That is a word on the board.")
        XCTAssertEqual(CodenamesRules.clueProblem("two words", faceDown: board), "One word, letters only.")
        XCTAssertEqual(CodenamesRules.clueProblem("r2d2", faceDown: board), "One word, letters only.")
        XCTAssertEqual(CodenamesRules.clueProblem("", faceDown: board), "Type a clue.")
        XCTAssertEqual(CodenamesRules.clueProblem("   ", faceDown: board), "Type a clue.")
        XCTAssertNil(CodenamesRules.clueProblem("ocean", faceDown: board))
        XCTAssertNil(CodenamesRules.clueProblem("planet", faceDown: ["net"]))
        XCTAssertNil(CodenamesRules.clueProblem("education", faceDown: ["cat"]))
        XCTAssertEqual(CodenamesRules.clueProblem("catfish", faceDown: ["cat"]), "Too close to CAT.")
        XCTAssertEqual(CodenamesRules.clueProblem("man", faceDown: board), "Too close to SNOWMAN.")
        XCTAssertNil(CodenamesRules.clueProblem("o'clock", faceDown: board))
        XCTAssertNil(CodenamesRules.clueProblem("well-known", faceDown: board))
        XCTAssertNil(CodenamesRules.clueProblem("Café", faceDown: board))
        XCTAssertEqual(CodenamesRules.clueProblem("-ocean", faceDown: board), "One word, letters only.")
        XCTAssertEqual(CodenamesRules.clueProblem(String(repeating: "a", count: 25), faceDown: board), "Keep it under 24 letters.")
    }

    func testAWordTurnedOverMayBeAClue() {
        XCTAssertNil(CodenamesRules.clueProblem("bank", faceDown: ["snowman"]))
    }

    func testTheStemsMatchTheServers() {
        XCTAssertEqual(Set(CodenamesRules.stems("running")), ["running", "runn", "runne", "run"])
        XCTAssertTrue(CodenamesRules.sameStem("baked", "bake"))
        XCTAssertTrue(CodenamesRules.sameStem("baking", "bakes"))
        XCTAssertFalse(CodenamesRules.sameStem("kite", "kit"))
        XCTAssertFalse(CodenamesRules.sameStem("speed", "spe"))
        XCTAssertEqual(CodenamesRules.singulars("berries"), ["berries", "berry", "berrie"])
        XCTAssertEqual(CodenamesRules.singulars("boxes"), ["boxes", "box", "boxe"])
        XCTAssertEqual(CodenamesRules.singulars("glass"), ["glass"])
        XCTAssertEqual(CodenamesRules.normalise("The Café"), "cafe")
        XCTAssertEqual(CodenamesRules.normalise("o’clock"), "oclock")
    }

    func testTheClueFieldKeepsOneWord() {
        XCTAssertEqual(CodenamesRules.typing("sea side"), "seaside")
        XCTAssertEqual(CodenamesRules.typing(String(repeating: "b", count: 30)).count, 24)
        XCTAssertEqual(CodenamesRules.clampCount(0), 1)
        XCTAssertEqual(CodenamesRules.clampCount(12), 9)
    }

    // MARK: - The moves

    func testTheMovesSendTheirFields() throws {
        let red = try object(CodenamesMove.pick(.red, spymaster: true))
        XCTAssertEqual(red["action"] as? String, "team")
        XCTAssertEqual(red["team"] as? String, "red")
        XCTAssertEqual(red["spymaster"] as? Bool, true)
        let anywhere = try object(CodenamesMove.pick(nil, spymaster: false))
        XCTAssertTrue(anywhere["team"] is NSNull, "anywhere is an explicit null")
        XCTAssertEqual(anywhere["spymaster"] as? Bool, false)
        let clue = try object(CodenamesMove.clue("ocean", count: 2))
        XCTAssertEqual(clue["action"] as? String, "clue")
        XCTAssertEqual(clue["word"] as? String, "ocean")
        XCTAssertEqual(clue["count"] as? Int, 2)
        XCTAssertNil(clue["team"])
        let guess = try object(CodenamesMove.guess(7))
        XCTAssertEqual(guess["card"] as? Int, 7)
        XCTAssertNil(guess["spymaster"])
        XCTAssertEqual(try object(CodenamesMove.pass).count, 1)
    }

    // MARK: - Words

    func testTheBannerSaysWhoIsUp() throws {
        let watching = try decode(Self.room(me: "p_d", key: false))
        XCTAssertEqual(CodenamesRules.headline(watching), "Red are guessing")
        let thinking = try decode(Self.room(me: "p_d", key: false, phase: "clue"))
        XCTAssertEqual(CodenamesRules.headline(thinking), "Red’s spymaster is thinking")
        XCTAssertEqual(CodenamesRules.waitingOn(thinking).map(\.id), ["p_a"])
        let guessing = try decode(Self.room(me: "p_b", key: false, canGuess: true))
        XCTAssertEqual(CodenamesRules.headline(guessing), "Your team’s guess")
        XCTAssertEqual(CodenamesRules.waitingOn(guessing).map(\.id), ["p_b"], "the operatives, not the spymaster")
        XCTAssertEqual(CodenamesRules.guessesLine(1), "1 guess left")
        XCTAssertEqual(CodenamesRules.guessesLine(0), "No guesses left")
    }

    func testARevealFeelsRightForMyTeam() throws {
        let state = try decode(Self.room(me: "p_b", key: false))
        let last = try XCTUnwrap(state.last)
        XCTAssertEqual(CodenamesRules.feel(last, myTeam: .red), .good)
        XCTAssertEqual(CodenamesRules.feel(last, myTeam: .blue), .bad)
        XCTAssertEqual(CodenamesRules.feel(last, myTeam: nil), .plain)
        XCTAssertEqual(CodenamesRules.revealLine(last, word: "bank", mode: .teams), "BANK was one of theirs.")
    }

    func testTheEndingIsSaid() throws {
        let won = try JSONDecoder().decode(CodenamesResult.self, from: Data(#"{"winner":"blue","reason":"assassin"}"#.utf8))
        XCTAssertEqual(CodenamesRules.endingTitle(won, mode: .teams, myTeam: .blue), "Your team wins")
        XCTAssertEqual(CodenamesRules.endingTitle(won, mode: .teams, myTeam: .red), "Blue win")
        XCTAssertEqual(CodenamesRules.endingTitle(won, mode: .teams, myTeam: nil), "Blue win")
        XCTAssertTrue(CodenamesRules.endingLine(won, mode: .teams, last: nil).contains("Red touched the assassin"))
        let coop = try JSONDecoder().decode(CodenamesResult.self, from: Data(#"{"winner":"red","reason":"agents"}"#.utf8))
        XCTAssertEqual(CodenamesRules.endingTitle(coop, mode: .coop, myTeam: .red), "You found them all")
    }
}
