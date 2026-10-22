import XCTest
@testable import SRAppleApp

/// Fake Artist: the spec's wire contract (SR-Main
/// `docs/superpowers/specs/2026-10-22-family-games-fake-artist.md`), what each
/// role is shown, the posts a line, a vote and a guess make, and the options.
final class FakeArtistTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    private func players(drawing: String? = nil) -> String {
        let seats = [("p_a", "Sam", "red"), ("p_b", "John", "blue"), ("p_c", "Kim", "green"), ("p_d", "Ada", "orange")]
        return "[" + seats.map { id, name, color in
            #"{"id":"\#(id)","name":"\#(name)","status":"joined","isHost":\#(id == "p_a"),"score":1,"color":"\#(color)","isDrawing":\#(id == drawing)}"#
        }.joined(separator: ",") + "]"
    }

    private func roomJSON(phase: String, current: String, meId: String = "p_b", drawing: String? = nil,
                      standings: String = "null") -> String {
        #"""
        { "id":"g_f", "game":"fake-artist", "difficulty":"medium", "phase":"\#(phase)",
          "hostId":"p_a", "meId":"\#(meId)", "rounds":5, "laps":2,
          "turnMs":20000, "readMs":8000, "voteMs":60000, "guessMs":30000, "revealMs":10000,
          "phaseEndsAt":1790000020000, "current":\#(current),
          "history":[{"number":1,"category":"Animals","word":"penguin","fakeId":"p_c","outcome":"escaped"}],
          "drawing":{"revision":12,"since":null,"strokes":[{"id":1,"color":"red","width":14,"points":[[10,20],[30,40]]}],"ops":null},
          "palette":["red","blue","green","orange","purple","brown","pink","teal","black","gold"],
          "players":\#(players(drawing: drawing)), "standings":\#(standings), "winnerIds":[], "serverNow":1790000005000 }
        """#
    }

    private let turns = #"["p_a","p_b","p_c","p_d","p_a","p_b","p_c","p_d"]"#

    // MARK: - The wire

    func testAnArtistsTurnDecodesFromTheContract() throws {
        let current = #"""
        {"number":2,"category":"Places","role":"artist","word":"lighthouse","fakeId":null,
         "turns":\#(turns),"turn":1,"artistId":"p_b","turnStartedAt":1790000000000,"skipped":[0],
         "voted":[],"myVote":null,"votes":null,"counts":null,"accusedId":null,"guess":null,"outcome":null,"awarded":null}
        """#
        let room = try decode(roomJSON(phase: "drawing", current: current, drawing: "p_b"))
        XCTAssertEqual(room.kind, .fakeArtist)
        XCTAssertEqual(room.phase, .unknown, "the shared enum does not know `drawing`")
        XCTAssertEqual(room.rounds, 5)
        let state = try XCTUnwrap(room.fakeArtist)
        XCTAssertEqual(state.phase, .drawing)
        XCTAssertEqual(state.turnMs, 20_000)
        XCTAssertEqual(state.phaseLength, 20_000)
        let round = try XCTUnwrap(state.current)
        XCTAssertTrue(round.isArtist)
        XCTAssertEqual(round.word, "lighthouse")
        XCTAssertNil(round.fakeId, "an artist is never told who the fake is")
        XCTAssertEqual(round.turns.count, 8)
        XCTAssertEqual(round.skipped, [0])
        XCTAssertTrue(state.myTurn("p_b"))
        XCTAssertFalse(state.myTurn("p_a"))
        XCTAssertEqual(state.lineId, 2, "the server numbers the line turn + 1")
        XCTAssertEqual(state.seat("p_b")?.color, "blue")
        XCTAssertEqual(state.seat("p_b")?.isDrawing, true)
        XCTAssertEqual(state.history.first?.outcome, .escaped)
        XCTAssertEqual(state.drawing?.strokes?.first?.points, [DrawGuessPoint(10, 20), DrawGuessPoint(30, 40)])
        XCTAssertEqual(FakeArtistText.turnLabel(round), "Turn 2 of 8")
        XCTAssertEqual(FakeArtistText.card(round).title, "lighthouse")
        XCTAssertEqual(FakeArtistSettings.about(room), "5 rounds · 20 s a line")
    }

    func testTheFakesCardHasNoWordUntilTheReveal() throws {
        let current = #"""
        {"number":1,"category":"Food","role":"fake","word":null,"fakeId":"p_b",
         "turns":\#(turns),"turn":null,"artistId":null,"voted":["p_a"],"myVote":null}
        """#
        let reading = try XCTUnwrap(try decode(roomJSON(phase: "reading", current: current)).fakeArtist)
        XCTAssertEqual(reading.phase, .reading)
        let round = try XCTUnwrap(reading.current)
        XCTAssertTrue(round.isFake)
        XCTAssertNil(round.word)
        XCTAssertEqual(FakeArtistText.card(round).kicker, "You're the fake")
        XCTAssertFalse(reading.myTurn("p_b"))

        let revealed = #"""
        {"number":1,"category":"Food","role":"fake","word":"pancake","fakeId":"p_b","turns":\#(turns),
         "voted":["p_a","p_b","p_c","p_d"],"myVote":"p_a","votes":{"p_a":"p_b","p_b":"p_a","p_c":"p_b","p_d":"p_b"},
         "counts":{"p_b":3,"p_a":1},"accusedId":"p_b","guess":"waffle","outcome":"caught","awarded":{"p_a":1,"p_c":1,"p_d":1}}
        """#
        let reveal = try XCTUnwrap(try decode(roomJSON(phase: "reveal", current: revealed)).fakeArtist?.current)
        XCTAssertEqual(FakeArtistText.card(reveal).title, "pancake")
        XCTAssertEqual(reveal.outcome, .caught)
        XCTAssertEqual(reveal.counts?["p_b"], 3)
        XCTAssertEqual(reveal.awarded?["p_b"], nil)
        XCTAssertEqual(FakeArtistText.outcome(.caught, fake: "John", meIsFake: true), "Caught! The artists win.")
        XCTAssertEqual(FakeArtistText.outcome(.escaped, fake: "John", meIsFake: false), "John got away with it!")
        XCTAssertEqual(FakeArtistText.outcome(.guessed, fake: "John", meIsFake: false), "John was caught — but named the word!")
    }

    func testTheVoteOffersEveryoneDealtInButMe() throws {
        let current = #"{"number":1,"category":"Toys","role":"artist","word":"kite","turns":\#(turns),"voted":["p_c"]}"#
        let room = try decode(roomJSON(phase: "voting", current: current))
        let state = try XCTUnwrap(room.fakeArtist)
        XCTAssertEqual(state.phase, .voting)
        XCTAssertEqual(state.candidates(in: room).map(\.id), ["p_a", "p_c", "p_d"])
        XCTAssertEqual(state.current?.voted, ["p_c"])
        XCTAssertNil(state.current?.votes, "nobody's choice is sent before the reveal")
        XCTAssertEqual(FakeArtistText.votedLine(voted: 1, of: 4), "1 of 4 voted")
    }

    func testAnUnknownPhaseOrOutcomeNeverFailsTheRoom() throws {
        let current = #"{"number":1,"category":"Toys","role":"watching","outcome":"something-new"}"#
        let state = try XCTUnwrap(try decode(roomJSON(phase: "intermission", current: current)).fakeArtist)
        XCTAssertEqual(state.phase, .unknown)
        XCTAssertEqual(state.current?.outcome, .unknown)
        XCTAssertEqual(FakeArtistText.card(state.current).kicker, "Watching")
    }

    func testAnotherGamesRoomHasNoFakeArtist() throws {
        let room = try decode(#"{"id":"g","game":"draw-guess","difficulty":"easy","phase":"lobby","hostId":"a","meId":"a","serverNow":1}"#)
        XCTAssertNil(room.fakeArtist)
    }

    func testTheFinishedTableCarriesTimesAsTheFake() throws {
        let table = #"[{"id":"p_a","name":"Sam","score":4,"timesFake":2,"winsAsFake":2}]"#
        let room = try decode(roomJSON(phase: "finished", current: "null", standings: table))
        XCTAssertEqual(room.fakeArtist?.phase, .finished)
        XCTAssertEqual(room.standings?.first?.score, 4)
        XCTAssertEqual(room.fakeArtist?.extra("p_a")?.timesFake, 2)
    }

    // MARK: - Posts

    private func json(_ body: GameActionBody) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
    }

    func testALiftMarksTheLastPostAsTheEnd() throws {
        var pen = DrawGuessPen(firstId: 3)
        pen.color = "teal"
        pen.down(at: DrawGuessPoint(10, 10))
        pen.move(to: DrawGuessPoint(50, 50))
        pen.move(to: DrawGuessPoint(90, 10))
        let bodies = FakeArtistPosts.lift(pen.up())
        XCTAssertFalse(bodies.isEmpty)
        let last = try json(bodies[bodies.count - 1])
        XCTAssertEqual(last["action"] as? String, "stroke")
        XCTAssertEqual(last["end"] as? Bool, true)
        XCTAssertEqual(last["id"] as? Int, 3)
        XCTAssertNotNil(last["points"])
        for body in bodies.dropLast() { XCTAssertNil(try json(body)["end"]) }

        // Everything already streamed: the lift alone.
        let bare = FakeArtistPosts.lift([])
        XCTAssertEqual(bare.count, 1)
        let only = try json(bare[0])
        XCTAssertEqual(only["end"] as? Bool, true)
        XCTAssertNil(only["points"])
    }

    func testAVoteAndAGuess() throws {
        let vote = try json(FakeArtistPosts.vote("p_c"))
        XCTAssertEqual(vote["action"] as? String, "vote")
        XCTAssertEqual(vote["playerId"] as? String, "p_c")
        XCTAssertNil(FakeArtistPosts.guess("   "))
        XCTAssertNil(FakeArtistPosts.guess(String(repeating: "a", count: 41)))
        let guess = try json(try XCTUnwrap(FakeArtistPosts.guess("  light house ")))
        XCTAssertEqual(guess["text"] as? String, "light house")
    }

    // MARK: - The host's options and the game list

    func testTheCreateBodyAndTheStartBlock() throws {
        let body = FakeArtistSettings(difficulty: .hard, rounds: 5).createBody(invite: ["p_a", "p_b", "p_c"])
        let fields = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(fields["game"] as? String, "fake-artist")
        XCTAssertEqual(fields["difficulty"] as? String, "hard")
        XCTAssertEqual(fields["rounds"] as? Int, 5)
        XCTAssertEqual(FakeArtistSettings.roundChoices, [3, 5], "the server's ROUNDS")
        XCTAssertEqual(FakeArtistSettings.startBlock(joined: 2), "Needs four players at least — ask 2 more in.")
        XCTAssertNil(FakeArtistSettings.startBlock(joined: 4))
    }

    func testTheGameKindAndItsInks() {
        XCTAssertEqual(GameKind(rawValue: "fake-artist"), .fakeArtist)
        XCTAssertEqual(GameKind.fakeArtist.title, "Fake Artist")
        XCTAssertTrue(GameKind.allCases.contains(.fakeArtist))
        XCTAssertFalse(GameDifficulty.easy.line(for: .fakeArtist).isEmpty)
        // The server's seat colours, in seat order (`COLORS` in fake-artist.ts).
        XCTAssertEqual(FakeArtistInk.palette,
                       ["red", "blue", "green", "orange", "purple", "brown", "pink", "teal", "black", "gold"])
        XCTAssertEqual(FakeArtistInk.width, 14)
    }
}
