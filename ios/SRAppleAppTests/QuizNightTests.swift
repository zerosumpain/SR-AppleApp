import XCTest
@testable import SRAppleApp

/// jkai Quiz Night: the spec's wire contract, and the rules the phone applies
/// itself — one answer per question, and "Play again" as a new quiz.
final class QuizNightTests: XCTestCase {

    // MARK: - The wire (the spec's JSON)

    private let questionJSON = #"""
    { "id":"g_q", "game":"quiz-night", "difficulty":"medium",
      "audience":"kids", "topic":"space", "title":"The Solar System",
      "phase":"question",
      "prep":"ready", "prepError": null,
      "hostId":"p_a", "meId":"p_b", "questionCount":10, "timeMs":15000,
      "players":[{"id":"p_a","name":"Sam","status":"joined","score":1450,"isHost":true},
                 {"id":"p_b","name":"John","status":"joined","score":900,"isHost":false},
                 {"id":"p_c","name":"Robin","status":"invited","score":0,"isHost":false}],
      "phaseEndsAt": 1790000015000,
      "question": {
         "index":2, "prompt":"How many planets are there?", "options":["Seven","Eight","Nine","Ten"],
         "startsAt":1790000000000,
         "answeredIds":["p_a"],
         "myChoice": null,
         "answerIndex": null,
         "explain": null,
         "picks": [] },
      "standings": null,
      "winnerIds": [], "serverNow": 1790000003000 }
    """#

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    func testAnOpenQuestionDecodesFromTheContract() throws {
        let room = try decode(questionJSON)
        XCTAssertEqual(room.kind, .quizNight)
        XCTAssertEqual(room.phase, .question)
        XCTAssertEqual(room.audience, "kids")
        XCTAssertEqual(room.topic, "space")
        XCTAssertEqual(room.title, "The Solar System")
        XCTAssertEqual(room.prep, .ready)
        XCTAssertNil(room.prepError)
        XCTAssertEqual(room.questionCount, 10)
        XCTAssertEqual(room.timeMs, 15_000)
        XCTAssertEqual(room.phaseEndsAt, 1_790_000_015_000, "on a question, phaseEndsAt is its clock")
        XCTAssertEqual(room.me?.score, 900)

        let q = try XCTUnwrap(room.question)
        XCTAssertEqual(q.index, 2)
        XCTAssertEqual(q.options, ["Seven", "Eight", "Nine", "Ten"])
        XCTAssertEqual(q.answeredIds, ["p_a"], "who has answered, never what")
        XCTAssertNil(q.myChoice)
        XCTAssertNil(q.answerIndex)
        XCTAssertNil(q.explain)
        XCTAssertTrue(q.picks.isEmpty)
    }

    func testARevealCarriesTheAnswerAndEveryonesPicks() throws {
        let json = questionJSON
            .replacingOccurrences(of: #""phase":"question""#, with: #""phase":"reveal""#)
            .replacingOccurrences(of: #""myChoice": null"#, with: #""myChoice": 1"#)
            .replacingOccurrences(of: #""answerIndex": null"#, with: #""answerIndex": 1"#)
            .replacingOccurrences(of: #""explain": null"#, with: #""explain": "  Pluto was reclassified in 2006. ""#)
            .replacingOccurrences(of: #""picks": []"#, with: #"""
            "picks": [{"playerId":"p_a","choice":2,"points":0,"ms":4100},
                      {"playerId":"p_b","choice":1,"points":812,"ms":3760.4}]
            """#)
        let room = try decode(json)
        XCTAssertEqual(room.phase, .reveal)
        let q = try XCTUnwrap(room.question)
        XCTAssertEqual(q.answerIndex, 1)
        XCTAssertEqual(q.myChoice, 1)
        XCTAssertEqual(q.explain, "Pluto was reclassified in 2006.", "trimmed")
        XCTAssertEqual(q.pick(of: "p_b"), QuizPick(playerId: "p_b", choice: 1, points: 812, ms: 3760))
        XCTAssertFalse(try XCTUnwrap(q.pick(of: "p_a")).right)
        XCTAssertTrue(try XCTUnwrap(q.pick(of: "p_b")).right)
        XCTAssertEqual(q.pickers(of: 1), ["p_b"])
        XCTAssertEqual(q.pickers(of: 3), [])
    }

    func testALobbyWhileJkaiWritesAndWhenItFails() throws {
        let writing = try decode(#"""
        {"id":"g_q","game":"quiz-night","difficulty":"easy","audience":"family","topic":null,"title":null,
         "phase":"lobby","prep":"writing","prepError":null,"hostId":"p_a","meId":"p_a","questionCount":0,"timeMs":20000,
         "players":[{"id":"p_a","name":"John","status":"joined","score":0,"isHost":true}],
         "phaseEndsAt":1790000180000,"question":null,"standings":null,"winnerIds":[],"serverNow":1790000000000}
        """#)
        XCTAssertEqual(writing.prep, .writing)
        XCTAssertNil(writing.topic, "blank: jkai picks")
        XCTAssertNil(writing.title)
        XCTAssertNil(writing.question)

        let failed = try decode(#"""
        {"id":"g_q","game":"quiz-night","phase":"lobby","prep":"failed",
         "prepError":"jkai could not write a quiz on that. Try another topic.","serverNow":1}
        """#)
        XCTAssertEqual(failed.prep, .failed)
        XCTAssertEqual(failed.prepError, "jkai could not write a quiz on that. Try another topic.")

        let unknown = try decode(#"{"id":"g_q","game":"quiz-night","phase":"lobby","prep":"polishing","serverNow":1}"#)
        XCTAssertEqual(unknown.prep, .ready, "an unknown prep leaves Start to the server")

        let tapDuel = try decode(#"{"id":"g_t","game":"tap-duel","phase":"lobby","serverNow":1}"#)
        XCTAssertEqual(tapDuel.prep, .ready, "other games have nothing to prepare")
        XCTAssertNil(tapDuel.question)
    }

    func testAFinishedQuizDecodesStandings() throws {
        let room = try decode(#"""
        {"id":"g_q","game":"quiz-night","difficulty":"hard","audience":"adults","topic":null,"title":"Famous Bridges",
         "phase":"finished","prep":"ready","prepError":null,"hostId":"p_a","meId":"p_a","questionCount":10,"timeMs":10000,
         "players":[{"id":"p_a","name":"John","status":"joined","score":6200,"isHost":true},
                    {"id":"p_b","name":"Sam","status":"joined","score":6200,"isHost":false}],
         "phaseEndsAt":1790000600000,"question":null,
         "standings":[{"id":"p_a","name":"John","score":6200,"correct":8,"avgMs":4210.6},
                      {"id":"p_b","name":"Sam","score":6200,"correct":7,"avgMs":null}],
         "winnerIds":["p_a","p_b"],"serverNow":1790000000000}
        """#)
        XCTAssertEqual(room.phase, .finished)
        let standings = try XCTUnwrap(room.standings)
        XCTAssertEqual(standings[0].score, 6200)
        XCTAssertEqual(standings[0].correct, 8)
        XCTAssertEqual(standings[0].avgMs, 4211)
        XCTAssertNil(standings[1].avgMs)
        XCTAssertEqual(room.winnerIds, ["p_a", "p_b"])
    }

    // MARK: - Invites and `about`

    func testTheLobbyPollDecodesInvitesWithAndWithoutAbout() throws {
        let json = #"""
        { "me": {"id":"p_a","name":"John"},
          "players": [{"id":"p_b","name":"Sam"}],
          "invites": [{"roomId":"g_1","game":"quiz-night","difficulty":"easy","about":"The Solar System · for kids",
                       "hostName":"Sam","players":["Sam","John"],"expiresAt":1790000000000},
                      {"roomId":"g_2","game":"tap-duel","difficulty":"hard","about":null,
                       "hostName":"Sam","players":["Sam","John"],"expiresAt":1790000000000},
                      {"roomId":"g_3","game":"wordle-race","difficulty":"medium",
                       "hostName":"Robin","players":["Robin","John"],"expiresAt":1790000000000}],
          "rooms": [{"id":"g_4","game":"quiz-night","phase":"reveal","hostName":"John"}],
          "serverNow": 1790000000000 }
        """#
        let lobby = try JSONDecoder().decode(GamesLobby.self, from: Data(json.utf8))
        XCTAssertEqual(lobby.invites.count, 3)
        XCTAssertEqual(lobby.invites[0].about, "The Solar System · for kids")
        XCTAssertNil(lobby.invites[1].about, "null")
        XCTAssertNil(lobby.invites[2].about, "absent: an older site")
        XCTAssertEqual(lobby.rooms.first?.phase, .reveal)
    }

    func testAnInviteSaysWhatTheQuizIsAbout() {
        let quiz = GameInvite(roomId: "g_q", game: "quiz-night", difficulty: "easy", hostName: "Sam",
                              players: ["Sam", "John"], expiresAt: nil, about: "The Solar System · for kids")
        XCTAssertEqual(quiz.notificationTitle, "Sam invited you to Quiz Night — The Solar System · for kids")
        XCTAssertEqual(quiz.notificationBody, "Easy, with Sam and John. Tap to join.")
        let request = GamesStore.request(for: quiz)
        XCTAssertEqual(request.content.title, "Sam invited you to Quiz Night — The Solar System · for kids")
        XCTAssertEqual(request.content.userInfo["game"] as? String, "quiz-night")

        let plain = GameInvite(roomId: "g_t", game: "tap-duel", difficulty: "easy", hostName: "Sam",
                               players: ["Sam", "John"], expiresAt: nil)
        XCTAssertEqual(plain.notificationTitle, "Sam invited you to Tap Duel", "no about, no dash")
    }

    // MARK: - Creating

    func testTheCreateBodyCarriesTopicAndAudience() throws {
        let settings = QuizNightSettings(difficulty: .hard, topic: "  90s   pop\n", audience: .adults)
        let body = settings.createBody(invite: ["p_b"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(json["game"] as? String, "quiz-night")
        XCTAssertEqual(json["difficulty"] as? String, "hard")
        XCTAssertEqual(json["invite"] as? [String], ["p_b"])
        XCTAssertEqual(json["topic"] as? String, "90s pop", "one line, trimmed")
        XCTAssertEqual(json["audience"] as? String, "adults")

        let blank = QuizNightSettings(difficulty: .easy, topic: "   ", audience: .family).createBody(invite: [])
        let blankJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(blank)) as? [String: Any])
        XCTAssertNil(blankJSON["topic"], "blank: jkai picks, and the key is left out")
        XCTAssertEqual(blankJSON["audience"] as? String, "family")

        let tapDuel = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            CreateGameBody(difficulty: "easy", invite: []))) as? [String: Any])
        XCTAssertNil(tapDuel["topic"])
        XCTAssertNil(tapDuel["audience"], "other games send neither")
    }

    func testATopicIsCappedAtSixtyCharacters() {
        let long = String(repeating: "a", count: 75)
        XCTAssertEqual(QuizNightSettings.limit(long).count, 60)
        XCTAssertEqual(QuizNightSettings.limit("dinosaurs"), "dinosaurs")
        XCTAssertEqual(QuizNightSettings.clean(topic: long)?.count, 60)
        XCTAssertNil(QuizNightSettings.clean(topic: nil))
        XCTAssertNil(QuizNightSettings.clean(topic: " \n "))
    }

    // MARK: - Play again

    private let finishedJSON = #"""
    {"id":"g_q","game":"quiz-night","difficulty":"medium","audience":"kids","topic":null,"title":"Volcanoes",
     "phase":"finished","prep":"ready","hostId":"p_a","meId":"p_a","questionCount":10,"timeMs":15000,
     "players":[{"id":"p_a","name":"John","status":"joined","score":5000,"isHost":true},
                {"id":"p_b","name":"Sam","status":"joined","score":4000,"isHost":false},
                {"id":"p_c","name":"Robin","status":"left","score":800,"isHost":false},
                {"id":"p_d","name":"Kit","status":"declined","score":0,"isHost":false}],
     "phaseEndsAt":1790000600000,"question":null,"standings":[],"winnerIds":["p_a"],"serverNow":1790000000000}
    """#

    func testPlayAgainIsANewQuizWithTheSameSettingsAndPlayers() throws {
        let room = try decode(finishedJSON)
        let body = QuizNight.playAgain(from: room)
        XCTAssertEqual(body, CreateGameBody(game: "quiz-night", difficulty: "medium", invite: ["p_b"],
                                            topic: nil, audience: "kids"),
                       "same settings; everyone who played bar me; not the title jkai picked")

        let asked = try decode(finishedJSON.replacingOccurrences(of: #""topic":null"#, with: #""topic":"volcanoes""#))
        XCTAssertEqual(QuizNight.playAgain(from: asked).topic, "volcanoes", "the host's topic, as asked")
    }

    func testANewQuizFromAFailedLobbyTakesTheInvitedToo() throws {
        let room = try decode(#"""
        {"id":"g_q","game":"quiz-night","difficulty":"easy","audience":null,"topic":"knots",
         "phase":"lobby","prep":"failed","prepError":"No.","hostId":"p_a","meId":"p_a",
         "players":[{"id":"p_a","name":"John","status":"joined","isHost":true},
                    {"id":"p_b","name":"Sam","status":"invited"},
                    {"id":"p_c","name":"Robin","status":"joined"},
                    {"id":"p_d","name":"Kit","status":"declined"}],
         "serverNow":1}
        """#)
        let body = QuizNight.playAgain(from: room)
        XCTAssertEqual(body.invite, ["p_b", "p_c"])
        XCTAssertEqual(body.audience, "family", "a missing audience is the default")
        XCTAssertEqual(body.topic, "knots")
        XCTAssertEqual(body.difficulty, "easy")
    }

    // MARK: - Answering

    func testAnAnswerLocksOncePerQuestion() throws {
        let room = try decode(questionJSON)
        var lock = QuizAnswerLock()
        XCTAssertTrue(lock.canAnswer(in: room))
        XCTAssertTrue(lock.lock(question: 2, choice: 1))
        XCTAssertFalse(lock.lock(question: 2, choice: 3), "a second tap never counts")
        XCTAssertEqual(lock.choice(for: 2), 1, "the first answer stands")
        XCTAssertFalse(lock.canAnswer(in: room))
        XCTAssertEqual(lock.choice(for: try XCTUnwrap(room.question)), 1)

        XCTAssertTrue(lock.lock(question: 3, choice: 0), "the next question is a fresh answer")

        lock.release(question: 2)
        XCTAssertTrue(lock.canAnswer(in: room), "a POST that never arrived hands the question back")
    }

    func testTheServersChoiceLocksTooAndOnlyOpenQuestionsTakeAnswers() throws {
        let answered = try decode(questionJSON.replacingOccurrences(of: #""myChoice": null"#, with: #""myChoice": 0"#))
        let lock = QuizAnswerLock()
        XCTAssertFalse(lock.canAnswer(in: answered), "answered on another launch")
        XCTAssertEqual(lock.choice(for: try XCTUnwrap(answered.question)), 0)

        let revealed = try decode(questionJSON.replacingOccurrences(of: #""phase":"question""#, with: #""phase":"reveal""#))
        XCTAssertFalse(lock.canAnswer(in: revealed))

        let watching = try decode(questionJSON.replacingOccurrences(of: #""meId":"p_b""#, with: #""meId":"p_c""#))
        XCTAssertFalse(lock.canAnswer(in: watching), "an invitee who never joined only watches")
    }

    func testTheAnswerBody() throws {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            QuizAnswerLock.body(question: 4, choice: 2))) as? [String: Any])
        XCTAssertEqual(body.count, 3)
        XCTAssertEqual(body["action"] as? String, "answer")
        XCTAssertEqual(body["question"] as? Int, 4)
        XCTAssertEqual(body["choice"] as? Int, 2)
    }

    func testTheTimeBarAndLabels() {
        XCTAssertEqual(QuizNight.fractionLeft(endsAt: 10_000, timeMs: 20_000, atServer: 0), 0.5)
        XCTAssertEqual(QuizNight.fractionLeft(endsAt: 10_000, timeMs: 20_000, atServer: 12_000), 0)
        XCTAssertEqual(QuizNight.fractionLeft(endsAt: 30_000, timeMs: 20_000, atServer: 0), 1)
        XCTAssertEqual(QuizNight.letter(0), "A")
        XCTAssertEqual(QuizNight.letter(3), "D")
        XCTAssertEqual(QuizNight.points(870), "+870")
        XCTAssertEqual(QuizNight.points(0), "0")
        XCTAssertEqual(GameDifficulty.hard.line(for: .quizNight), "10 seconds a question.")
        XCTAssertEqual(GameNames.title("quiz-night"), "Quiz Night")
    }

    // MARK: - Demo

    #if DEBUG
    func testTheDemoQuizRoomsAreOnAQuestionAndAReveal() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let lobbyJSON = try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/games", query: [:], body: nil, clock: clock))
        let lobby = try JSONDecoder().decode(GamesLobby.self, from: Data(lobbyJSON.utf8))
        XCTAssertTrue(lobby.rooms.contains { $0.id == "g_demo_quiz" && $0.phase == .question })
        XCTAssertTrue(lobby.rooms.contains { $0.id == "g_demo_quiz_reveal" && $0.phase == .reveal })
        XCTAssertEqual(lobby.invites.first { $0.game == "quiz-night" }?.about, "The Solar System · for kids")

        func get(_ id: String) throws -> GameRoom {
            let json = try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/games/\(id)", query: [:], body: nil, clock: clock))
            return try JSONDecoder().decode(GameRoomEnvelope.self, from: Data(json.utf8)).room
        }
        let open = try get("g_demo_quiz")
        XCTAssertEqual(open.phase, .question)
        XCTAssertEqual(open.question?.options.count, 4)
        XCTAssertTrue(QuizAnswerLock().canAnswer(in: open), "John has not answered yet")
        XCTAssertGreaterThan(try XCTUnwrap(open.phaseEndsAt), open.serverNow)

        let reveal = try get("g_demo_quiz_reveal")
        XCTAssertEqual(reveal.phase, .reveal)
        XCTAssertEqual(reveal.question?.answerIndex, 1)
        XCTAssertEqual(reveal.question?.picks.count, 3)
        XCTAssertNotNil(reveal.question?.explain)

        let invite = try get("g_demo_quiz_invite")
        XCTAssertEqual(invite.prep, .writing)

        let created = try XCTUnwrap(SRDemoFixtures.route(
            method: "POST", path: "/api/native/games", query: [:],
            body: Data(#"{"game":"quiz-night","difficulty":"medium","invite":["p_sam"],"topic":"dinosaurs","audience":"kids"}"#.utf8),
            clock: clock))
        let room = try JSONDecoder().decode(GameRoomEnvelope.self, from: Data(created.utf8)).room
        XCTAssertEqual(room.kind, .quizNight)
        XCTAssertEqual(room.prep, .ready)
        XCTAssertEqual(room.title, "Dinosaurs")
        XCTAssertEqual(room.timeMs, 15_000)
    }
    #endif
}
