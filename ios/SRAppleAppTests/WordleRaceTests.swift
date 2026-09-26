import XCTest
@testable import SRAppleApp

/// Wordle Race: the spec's wire contract, and the rules the phone applies
/// itself — typing, the keyboard's colours, the clock.
final class WordleRaceTests: XCTestCase {

    // MARK: - The wire (the spec's JSON)

    private let playingJSON = #"""
    { "id":"g_w", "game":"wordle-race", "difficulty":"hard",
      "phase":"playing",
      "hostId":"p_a", "meId":"p_b",
      "wordLength":5, "maxGuesses":6, "timeLimitMs":180000, "hardMode":true,
      "startedAt": 1790000000000,
      "phaseEndsAt": 1790000180000,
      "players":[{ "id":"p_a","name":"Sam","status":"joined","isHost":true,
                   "guessCount":2,"solved":false,"done":false,"solveMs":null,
                   "rows":[{"word":null,"marks":["absent","present","correct","absent","absent"]},
                           {"word":null,"marks":["correct","correct","correct","absent","absent"]}] },
                 { "id":"p_b","name":"John","status":"joined","isHost":false,
                   "guessCount":1,"solved":false,"done":false,"solveMs":null,
                   "rows":[{"word":"CRANE","marks":["absent","present","correct","absent","absent"]}] },
                 { "id":"p_c","name":"Robin","status":"declined","isHost":false,
                   "guessCount":0,"solved":false,"done":false,"solveMs":null,"rows":[] }],
      "keyboard": {"a":"correct","r":"present","c":"absent","n":"absent","e":"absent"},
      "secret": null,
      "standings": null,
      "winnerIds": [],
      "serverNow": 1790000000000 }
    """#

    func testAPlayingRoomDecodesFromTheContract() throws {
        let room = try JSONDecoder().decode(GameRoom.self, from: Data(playingJSON.utf8))
        XCTAssertEqual(room.game, "wordle-race")
        XCTAssertEqual(room.kind, .wordleRace)
        XCTAssertEqual(room.phase, .playing)
        XCTAssertEqual(room.wordLength, 5)
        XCTAssertEqual(room.maxGuesses, 6)
        XCTAssertEqual(room.timeLimitMs, 180_000)
        XCTAssertTrue(room.hardMode)
        XCTAssertEqual(room.startedAt, 1_790_000_000_000)
        XCTAssertEqual(room.phaseEndsAt, 1_790_000_180_000, "while playing, phaseEndsAt is the time limit")
        XCTAssertNil(room.secret)
        XCTAssertNil(room.standings)
        XCTAssertEqual(room.keyboard["r"], .present)
        XCTAssertEqual(room.keyboard["a"], .correct)

        let me = try XCTUnwrap(room.me)
        XCTAssertEqual(me.name, "John")
        XCTAssertEqual(me.guessCount, 1)
        XCTAssertEqual(me.rows.first?.word, "crane", "my letters travel, lower-cased")
        XCTAssertEqual(me.rows.first?.letters, Array("CRANE"))

        XCTAssertEqual(room.others.map(\.name), ["Sam"], "the strip is everyone else still in")
        let sam = room.others[0]
        XCTAssertEqual(sam.rows.count, 2)
        XCTAssertNil(sam.rows[0].word, "another player's row is colours only")
        XCTAssertNil(sam.rows[0].letters)
        XCTAssertEqual(sam.rows[1].marks, [.correct, .correct, .correct, .absent, .absent])
    }

    func testAFinishedRoomRevealsTheWordAndStandings() throws {
        let json = #"""
        { "id":"g_w", "game":"wordle-race", "difficulty":"easy", "phase":"finished",
          "hostId":"p_a", "meId":"p_a", "wordLength":5, "maxGuesses":6, "timeLimitMs":300000, "hardMode":false,
          "startedAt":1790000000000, "phaseEndsAt":1790000900000,
          "players":[{ "id":"p_a","name":"John","status":"joined","isHost":true,
                       "guessCount":4,"solved":true,"done":true,"solveMs":83000,
                       "rows":[{"word":"grape","marks":["correct","correct","correct","correct","correct"]}] },
                     { "id":"p_b","name":"Sam","status":"joined","isHost":false,
                       "guessCount":6,"solved":false,"done":true,"solveMs":null,
                       "rows":[{"word":"stone","marks":["absent","absent","absent","absent","correct"]}] }],
          "keyboard": {}, "secret":"grape",
          "standings":[{"id":"p_a","name":"John","solved":true,"guesses":4,"solveMs":83000},
                       {"id":"p_b","name":"Sam","solved":false,"guesses":6,"solveMs":null}],
          "winnerIds":["p_a"], "serverNow":1790000300000 }
        """#
        let room = try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.secret, "grape")
        XCTAssertEqual(room.winnerIds, ["p_a"])
        let standings = try XCTUnwrap(room.standings)
        XCTAssertTrue(standings[0].solved)
        XCTAssertEqual(standings[0].guesses, 4)
        XCTAssertEqual(standings[0].solveMs, 83_000)
        XCTAssertFalse(standings[1].solved)
        XCTAssertNil(standings[1].solveMs)
        XCTAssertEqual(room.players[1].rows.first?.word, "stone", "finished: everyone's letters")
        XCTAssertTrue(room.players[0].rows[0].solved)
        XCTAssertTrue(room.players[1].done)
    }

    func testATapDuelRoomStillDecodesWithWordleDefaults() throws {
        let json = #"{"id":"g_t","game":"tap-duel","phase":"lobby","serverNow":1,"players":[{"id":"p_a","name":"John","status":"joined","score":2,"isHost":true}]}"#
        let room = try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
        XCTAssertEqual(room.kind, .tapDuel)
        XCTAssertEqual(room.wordLength, 5)
        XCTAssertEqual(room.maxGuesses, 6)
        XCTAssertEqual(room.keyboard, [:])
        XCTAssertEqual(room.players[0].score, 2)
        XCTAssertEqual(room.players[0].rows, [])
        XCTAssertEqual(room.players[0].guessCount, 0)
    }

    func testAnUnknownMarkIsNotAThrow() throws {
        let row = try JSONDecoder().decode(WordleRow.self, from: Data(#"{"word":null,"marks":["correct","sparkly"]}"#.utf8))
        XCTAssertEqual(row.marks, [.correct, .unknown])
        XCTAssertFalse(row.solved)
    }

    func testTheGuessBodyIsActionAndWord() throws {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(GameActionBody(action: "guess", word: "crane"))) as? [String: Any]
        XCTAssertEqual(body?.count, 2)
        XCTAssertEqual(body?["action"] as? String, "guess")
        XCTAssertEqual(body?["word"] as? String, "crane")
    }

    func testCreatingAWordleRaceNamesTheGame() throws {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            CreateGameBody(game: GameKind.wordleRace.rawValue, difficulty: "medium", invite: ["p_b"]))) as? [String: Any]
        XCTAssertEqual(body?["game"] as? String, "wordle-race")
        XCTAssertEqual(body?["difficulty"] as? String, "medium")
    }

    func testTheInviteNotificationNamesWordleRace() {
        let invite = GameInvite(roomId: "g_w", game: "wordle-race", difficulty: "hard", hostName: "Sam",
                                players: ["Sam", "John"], expiresAt: nil)
        XCTAssertEqual(invite.notificationTitle, "Sam invited you to Wordle Race")
        XCTAssertEqual(invite.notificationBody, "Hard, with Sam and John. Tap to join.")
        let request = GamesStore.request(for: invite)
        XCTAssertEqual(request.content.userInfo["roomId"] as? String, "g_w")
        XCTAssertEqual(request.content.userInfo["game"] as? String, "wordle-race", "the tap opens the right screen")
    }

    func testEachGameHasItsOwnDifficultyLines() {
        XCTAssertEqual(GameDifficulty.easy.line(for: .wordleRace), "The 500 commonest words. 5 minutes.")
        XCTAssertEqual(GameDifficulty.medium.line(for: .wordleRace), "The 1,000 commonest words. 4 minutes.")
        XCTAssertTrue(GameDifficulty.hard.line(for: .wordleRace).contains("3 minutes"))
        XCTAssertTrue(GameDifficulty.hard.line(for: .wordleRace).contains("Hard mode"))
        XCTAssertEqual(GameDifficulty.easy.line, GameDifficulty.easy.line(for: .tapDuel), "Tap Duel's lines are unchanged")
        XCTAssertEqual(GameNames.title("wordle-race"), "Wordle Race")
        XCTAssertEqual(GameNames.title("tap-duel"), "Tap Duel")
        XCTAssertEqual(GameNames.title("quiz-night"), "Quiz Night", "a game this app does not know still has a name")
    }

    // MARK: - Typing

    func testInputTakesLettersOnlyUpToTheLength() {
        var input = WordleInput(length: 5)
        XCTAssertTrue(input.add("C"))
        XCTAssertFalse(input.add("1"))
        XCTAssertFalse(input.add(" "))
        XCTAssertFalse(input.add("-"))
        XCTAssertFalse(input.add("é"), "A–Z only: the word list is plain English")
        for letter in "rane" { input.add(letter) }
        XCTAssertEqual(input.word, "crane", "lower-case on the wire")
        XCTAssertTrue(input.isComplete)
        XCTAssertFalse(input.add("s"), "a full row takes nothing more")
        XCTAssertEqual(input.word, "crane")
    }

    func testDeleteRemovesTheLastLetterAndStopsAtEmpty() {
        var input = WordleInput(length: 5)
        for letter in "ab" { input.add(letter) }
        XCTAssertTrue(input.delete())
        XCTAssertEqual(input.word, "a")
        XCTAssertTrue(input.delete())
        XCTAssertTrue(input.isEmpty)
        XCTAssertFalse(input.delete())
        XCTAssertEqual(input.word, "")
    }

    func testClearEmptiesTheRow() {
        var input = WordleInput(length: 5)
        for letter in "grape" { input.add(letter) }
        input.clear()
        XCTAssertTrue(input.isEmpty)
        XCTAssertFalse(input.isComplete)
    }

    // MARK: - The keyboard

    func testTheLayoutIsQwertyWithEveryLetterOnce() {
        XCTAssertEqual(WordleKeyboard.rows.map { String($0) }, ["qwertyuiop", "asdfghjkl", "zxcvbnm"])
        XCTAssertEqual(Set(WordleKeyboard.rows.joined()).count, 26)
    }

    func testCorrectBeatsPresentBeatsAbsent() {
        XCTAssertEqual(WordleKeyboard.best(.absent, .present), .present)
        XCTAssertEqual(WordleKeyboard.best(.present, .absent), .present)
        XCTAssertEqual(WordleKeyboard.best(.present, .correct), .correct)
        XCTAssertEqual(WordleKeyboard.best(.correct, .absent), .correct)
        XCTAssertEqual(WordleKeyboard.best(nil, .absent), .absent)
        XCTAssertEqual(WordleKeyboard.best(.unknown, .absent), .absent)
        XCTAssertNil(WordleKeyboard.best(nil, nil))
    }

    func testAKeyTakesTheBestMarkAcrossRows() {
        // SPEED against a secret with one E: the first E is in place, the
        // second is not in the word again. The key is still green.
        let rows = [
            WordleRow(word: "speed", marks: [.absent, .absent, .correct, .absent, .absent]),
            WordleRow(word: "erase", marks: [.present, .absent, .absent, .absent, .absent]),
        ]
        let marks = WordleKeyboard.marks(server: [:], rows: rows)
        XCTAssertEqual(marks["e"], .correct)
        XCTAssertEqual(marks["s"], .absent)
        XCTAssertEqual(marks["r"], .absent)
        XCTAssertNil(marks["q"], "a letter never tried has no mark")
    }

    func testAServerKeyboardAndALaggingOneMerge() {
        // The server's keyboard has not caught up with my last row yet.
        let server: [String: WordleMark] = ["R": .present, "a": .absent, "zz": .correct, "x": .unknown]
        let rows = [WordleRow(word: "grape", marks: [.absent, .correct, .correct, .absent, .absent])]
        let marks = WordleKeyboard.marks(server: server, rows: rows)
        XCTAssertEqual(marks["r"], .correct, "a row is never undone by a stale keyboard; keys are case-folded")
        XCTAssertEqual(marks["a"], .correct)
        XCTAssertEqual(marks["g"], .absent)
        XCTAssertNil(marks["z"], "a key that is not one letter is ignored")
        XCTAssertNil(marks["x"], "unknown is no information")
    }

    func testOthersRowsNeverColourMyKeyboard() {
        let rows = [WordleRow(word: nil, marks: [.correct, .correct, .correct, .correct, .correct])]
        XCTAssertTrue(WordleKeyboard.marks(server: [:], rows: rows).isEmpty)
    }

    // MARK: - The clock and the words

    func testTheClockRoundsUpToWholeSeconds() {
        XCTAssertEqual(WordleClock.text(msLeft: 300_000), "5:00")
        XCTAssertEqual(WordleClock.text(msLeft: 299_001), "5:00")
        XCTAssertEqual(WordleClock.text(msLeft: 65_000), "1:05")
        XCTAssertEqual(WordleClock.text(msLeft: 1), "0:01")
        XCTAssertEqual(WordleClock.text(msLeft: 0), "0:00")
        XCTAssertEqual(WordleClock.text(msLeft: -4_000), "0:00")
        XCTAssertEqual(WordleClock.duration(ms: 83_000), "1:23")
    }

    func testARowIsSpokenWithoutColour() {
        let mine = WordleRow(word: "crane", marks: [.absent, .present, .correct, .absent, .absent])
        XCTAssertEqual(WordleSpeech.row(mine, number: 1),
                       "Guess 1, CRANE: C not in the word, R in the word, wrong place, A in place, N not in the word, E not in the word")
        let theirs = WordleRow(word: nil, marks: [.correct, .present, .absent, .absent, .correct])
        XCTAssertEqual(WordleSpeech.row(theirs, number: 2), "Guess 2: 2 in place, 1 elsewhere")
        XCTAssertEqual(WordleSpeech.summary([.correct, .correct]), "solved")
        XCTAssertEqual(WordleSpeech.summary([.absent, .absent]), "nothing")
    }

    // MARK: - Demo

    #if DEBUG
    func testTheDemoWordleRoomIsMidGame() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let lobbyJSON = try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/games", query: [:], body: nil, clock: clock))
        let lobby = try JSONDecoder().decode(GamesLobby.self, from: Data(lobbyJSON.utf8))
        XCTAssertTrue(lobby.rooms.contains { $0.id == "g_demo_wordle" && $0.game == "wordle-race" && $0.phase == .playing })

        let json = try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/games/g_demo_wordle", query: [:], body: nil, clock: clock))
        let room = try JSONDecoder().decode(GameRoomEnvelope.self, from: Data(json.utf8)).room
        XCTAssertEqual(room.kind, .wordleRace)
        XCTAssertEqual(room.phase, .playing)
        XCTAssertEqual(room.me?.rows.count, 3, "my three rows")
        XCTAssertEqual(room.me?.rows.compactMap(\.word), ["pearl", "crepe", "drape"])
        XCTAssertEqual(room.others.map(\.name), ["Sam", "Robin"])
        XCTAssertTrue(room.others.allSatisfy { $0.rows.allSatisfy { $0.word == nil } }, "others are colours only")
        XCTAssertTrue(room.others.contains { $0.solved })
        XCTAssertFalse(room.keyboard.isEmpty)
        XCTAssertNil(room.secret)
        XCTAssertGreaterThan(try XCTUnwrap(room.phaseEndsAt), room.serverNow, "time is left on the clock")

        let created = try XCTUnwrap(SRDemoFixtures.route(method: "POST", path: "/api/native/games", query: [:],
                                                         body: Data(#"{"game":"wordle-race","difficulty":"easy","invite":[]}"#.utf8), clock: clock))
        XCTAssertEqual(try JSONDecoder().decode(GameRoomEnvelope.self, from: Data(created.utf8)).room.game, "wordle-race")
    }
    #endif
}
