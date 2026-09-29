import Foundation

// MARK: - Demo games
//
// `-SRDemo` answers for `/api/native/games*`. Synthetic throughout — the
// repository is public. Two family members to invite (Sam, Robin), one
// invitation from Sam, one lobby of Alex's own that Sam has joined and
// Robin has not answered, and one Wordle Race of Sam's half played — Alex
// three rows in, Sam two (colours only), Robin solved. Quiz Night: an invite
// from Robin (with its `about` line), one quiz of Alex's on a question and one
// of Sam's on a reveal, so both screens can be shot. Anagram Blitz, Quick
// Maths Sprint and Sequence Memory: one room each, mid-play — Alex's word list
// and the tiles, Alex's problem and keypad on a bonus streak, and a Sequence
// Memory round waiting on Alex's taps with Robin already out. Boggle: a 4×4
// mid-play with a word half traced, and one finished with a shared word
// crossed out and a missed word lit. Categories: a card of eight mid-play
// with a half-typed answer on the wrong letter, and a review with a shared
// answer, a wrong letter and an answer Alex has vetoed out. The room stream has no
// fixture and 404s, which is the fallback the room screen must survive: it
// re-reads the snapshot.

extension SRDemoFixtures {

    static let demoLobbyRoom = "g_demo_lobby"
    static let demoInviteRoom = "g_demo_invite"
    static let demoWordleRoom = "g_demo_wordle"
    static let demoQuizRoom = "g_demo_quiz"
    static let demoQuizRevealRoom = "g_demo_quiz_reveal"
    static let demoQuizInviteRoom = "g_demo_quiz_invite"
    static let demoAnagramRoom = "g_demo_anagram"
    static let demoSprintRoom = "g_demo_sprint"
    static let demoMemoryRoom = "g_demo_memory"
    static let demoBoggleRoom = "g_demo_boggle"
    static let demoBoggleDoneRoom = "g_demo_boggle_done"
    static let demoCategoriesRoom = "g_demo_categories"
    static let demoCategoriesReviewRoom = "g_demo_categories_review"

    static func gamesRoute(method: String, parts: [String], body: Data?, clock: DemoClock) -> String? {
        // parts: ["api", "native", "games", ...]
        let rest = Array(parts.dropFirst(3))
        switch (method, rest.count) {
        case ("GET", 0):
            return gamesLobby(clock)
        case ("POST", 0):
            let fields = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let invited = (fields?["invite"] as? [String]) ?? []
            let game = (fields?["game"] as? String) ?? "tap-duel"
            if game == "quiz-night" {
                return "{\"room\": \(quizLobby(id: "g_demo_new", fields: fields ?? [:], invited: invited, clock: clock))}"
            }
            return "{\"room\": \(gameRoom(id: "g_demo_new", hostIsMe: true, meJoined: true, invited: invited, game: game, clock: clock))}"
        case ("GET", 1):
            return "{\"room\": \(demoRoom(id: rest[0], meJoined: true, clock: clock))}"
        case ("POST", 1):
            // Every action answers with the room as if it took: joined.
            return "{\"room\": \(demoRoom(id: rest[0], meJoined: true, clock: clock))}"
        default:
            // `/stream` included: a 404, on purpose.
            return nil
        }
    }

    static func ms(_ date: Date) -> String { String(Int64(date.timeIntervalSince1970 * 1000)) }

    /// The Wordle Race room, left out of the lobby for the App Store
    /// screenshots (`-SRStoreShots`): "Wordle" is another company's mark.
    static var storeShotsSkipsWordle: Bool { SRDemo.isStoreShots }
    static let wordleLobbyRow = #"{"id": "g_demo_wordle", "game": "wordle-race", "phase": "playing", "hostName": "Sam"},"#
    /// Boggle's two rooms, left out of the store shots for the same reason
    /// ("Boggle" is Hasbro's). First in the list, so the showcase reaches them.
    static let boggleLobbyRows = #"""
    {"id": "g_demo_boggle", "game": "boggle", "phase": "playing", "hostName": "Alex"},
                       {"id": "g_demo_boggle_done", "game": "boggle", "phase": "finished", "hostName": "Sam"},
    """#

    /// Categories' two rooms, left out of the store shots so those stay as
    /// they were approved. First in the list, so the showcase reaches them.
    static let categoriesLobbyRows = #"""
    {"id": "g_demo_categories", "game": "categories", "phase": "playing", "hostName": "Alex"},
                       {"id": "g_demo_categories_review", "game": "categories", "phase": "review", "hostName": "Sam"},
    """#

    static func gamesLobby(_ clock: DemoClock) -> String {
        let now = clock.now
        return """
        {"me": {"id": "p_alex", "name": "Alex"},
         "players": [{"id": "p_sam", "name": "Sam"}, {"id": "p_robin", "name": "Robin"}],
         "invites": [{"roomId": \(s(demoInviteRoom)), "game": "tap-duel", "difficulty": "medium", "hostName": "Sam",
                      "players": ["Sam", "Robin", "Alex"], "expiresAt": \(ms(now.addingTimeInterval(150))), "about": null},
                     {"roomId": \(s(demoQuizInviteRoom)), "game": "quiz-night", "difficulty": "easy", "hostName": "Robin",
                      "players": ["Robin", "Alex"], "expiresAt": \(ms(now.addingTimeInterval(170))),
                      "about": "The Solar System · for kids"}],
         "rooms": [\(storeShotsSkipsWordle ? "" : categoriesLobbyRows)
                   \(storeShotsSkipsWordle ? "" : boggleLobbyRows)
                   {"id": \(s(demoLobbyRoom)), "game": "tap-duel", "phase": "lobby", "hostName": "Alex"},
                   \(storeShotsSkipsWordle ? "" : wordleLobbyRow)
                   {"id": \(s(demoQuizRoom)), "game": "quiz-night", "phase": "question", "hostName": "Alex"},
                   {"id": \(s(demoQuizRevealRoom)), "game": "quiz-night", "phase": "reveal", "hostName": "Sam"},
                   {"id": \(s(demoAnagramRoom)), "game": "anagram-blitz", "phase": "playing", "hostName": "Alex"},
                   {"id": \(s(demoSprintRoom)), "game": "maths-sprint", "phase": "playing", "hostName": "Robin"},
                   {"id": \(s(demoMemoryRoom)), "game": "sequence-memory", "phase": "input", "hostName": "Sam"}],
         "serverNow": \(ms(now))}
        """
    }

    static func demoRoom(id: String, meJoined: Bool, clock: DemoClock) -> String {
        if id == demoWordleRoom { return wordleRoom(clock) }
        if id == demoQuizRoom { return quizRoom(reveal: false, clock: clock) }
        if id == demoQuizRevealRoom { return quizRoom(reveal: true, clock: clock) }
        if id == demoAnagramRoom { return anagramRoom(clock) }
        if id == demoSprintRoom { return sprintRoom(clock) }
        if id == demoMemoryRoom { return memoryRoom(clock) }
        if id == demoBoggleRoom { return boggleRoom(finished: false, clock: clock) }
        if id == demoBoggleDoneRoom { return boggleRoom(finished: true, clock: clock) }
        if id == demoCategoriesRoom { return categoriesRoom(review: false, clock: clock) }
        if id == demoCategoriesReviewRoom { return categoriesRoom(review: true, clock: clock) }
        if id == demoQuizInviteRoom {
            return quizLobby(id: id, fields: ["topic": "space", "audience": "kids", "difficulty": "easy"],
                             invited: [], hostIsMe: false, meJoined: meJoined, prep: "writing", clock: clock)
        }
        if id == demoInviteRoom {
            return gameRoom(id: id, hostIsMe: false, meJoined: meJoined, invited: [], clock: clock)
        }
        return gameRoom(id: id, hostIsMe: true, meJoined: true, invited: ["p_robin"], clock: clock)
    }

    /// A lobby. Hosted by Alex (Sam in, `invited` waiting), or by Sam with Alex
    /// invited or joined.
    static func gameRoom(id: String, hostIsMe: Bool, meJoined: Bool, invited: [String],
                         game: String = "tap-duel", clock: DemoClock) -> String {
        let now = clock.now
        let players: [String]
        if hostIsMe {
            var rows = [#"{"id": "p_alex", "name": "Alex", "status": "joined", "score": 0, "isHost": true}"#]
            if id == demoLobbyRoom {
                rows.append(#"{"id": "p_sam", "name": "Sam", "status": "joined", "score": 0, "isHost": false}"#)
            }
            for person in invited {
                let name = person == "p_sam" ? "Sam" : person == "p_robin" ? "Robin" : "Kit"
                rows.append("{\"id\": \(s(person)), \"name\": \(s(name)), \"status\": \"invited\", \"score\": 0, \"isHost\": false}")
            }
            players = rows
        } else {
            players = [
                #"{"id": "p_sam", "name": "Sam", "status": "joined", "score": 0, "isHost": true}"#,
                #"{"id": "p_robin", "name": "Robin", "status": "invited", "score": 0, "isHost": false}"#,
                "{\"id\": \"p_alex\", \"name\": \"Alex\", \"status\": \(s(meJoined ? "joined" : "invited")), \"score\": 0, \"isHost\": false}",
            ]
        }
        return """
        {"id": \(s(id)), "game": \(s(game)), "difficulty": \(s(hostIsMe ? "easy" : "medium")), "phase": "lobby",
         "hostId": \(s(hostIsMe ? "p_alex" : "p_sam")), "meId": "p_alex", "rounds": 5,
         "players": \(list(players)),
         "phaseEndsAt": \(ms(now.addingTimeInterval(160))), "round": null, "standings": null, "winnerIds": [],
         "serverNow": \(ms(now))}
        """
    }

    /// Wordle Race, medium, 88 seconds in. The word is GRAPE, which the room
    /// does not say (`secret` is null until finished). Alex: PEARL, CREPE,
    /// DRAPE. Sam: two rows, colours only. Robin: solved in four.
    static func wordleRoom(_ clock: DemoClock) -> String {
        let now = clock.now
        func row(_ word: String?, _ marks: String) -> String {
            let names = marks.map { mark -> String in
                switch mark {
                case "g": return "\"correct\""
                case "y": return "\"present\""
                default: return "\"absent\""
                }
            }
            return "{\"word\": \(s(word)), \"marks\": \(list(names))}"
        }
        let john = [row("pearl", "yygyx"), row("crepe", "xgxgg"), row("drape", "xgggg")]
        let sam = [row(nil, "xyxxg"), row(nil, "ggxxg")]
        let robin = [row(nil, "xxyxg"), row(nil, "xgyxg"), row(nil, "xggxg"), row(nil, "ggggg")]
        return """
        {"id": \(s(demoWordleRoom)), "game": "wordle-race", "difficulty": "medium", "phase": "playing",
         "hostId": "p_sam", "meId": "p_alex",
         "wordLength": 5, "maxGuesses": 6, "timeLimitMs": 240000, "hardMode": false,
         "startedAt": \(ms(now.addingTimeInterval(-88))),
         "phaseEndsAt": \(ms(now.addingTimeInterval(152))),
         "players": [
           {"id": "p_sam", "name": "Sam", "status": "joined", "isHost": true,
            "guessCount": 2, "solved": false, "done": false, "solveMs": null, "rows": \(list(sam))},
           {"id": "p_alex", "name": "Alex", "status": "joined", "isHost": false,
            "guessCount": 3, "solved": false, "done": false, "solveMs": null, "rows": \(list(john))},
           {"id": "p_robin", "name": "Robin", "status": "joined", "isHost": false,
            "guessCount": 4, "solved": true, "done": true, "solveMs": 83000, "rows": \(list(robin))}
         ],
         "keyboard": {"p": "correct", "e": "correct", "a": "correct", "r": "correct",
                      "l": "absent", "c": "absent", "d": "absent"},
         "secret": null, "standings": null, "winnerIds": [],
         "serverNow": \(ms(now))}
        """
    }

    // MARK: Quiz Night

    static func quizPlayer(_ id: String, _ name: String, status: String = "joined", score: Int, host: Bool) -> String {
        "{\"id\": \(s(id)), \"name\": \(s(name)), \"status\": \(s(status)), \"score\": \(score), \"isHost\": \(host)}"
    }

    /// A quiz lobby — a new one of Alex's (questions ready), or Robin's
    /// invitation with jkai still writing.
    static func quizLobby(id: String, fields: [String: Any], invited: [String], hostIsMe: Bool = true,
                          meJoined: Bool = true, prep: String = "ready", clock: DemoClock) -> String {
        let now = clock.now
        let topic = (fields["topic"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let audience = (fields["audience"] as? String) ?? "family"
        let difficulty = (fields["difficulty"] as? String) ?? "easy"
        let seconds = difficulty == "hard" ? 10 : difficulty == "medium" ? 15 : 20
        let title: String? = prep == "ready" ? (topic.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Famous Bridges") : nil
        var players: [String]
        if hostIsMe {
            players = [quizPlayer("p_alex", "Alex", score: 0, host: true)]
            for person in invited {
                let name = person == "p_sam" ? "Sam" : person == "p_robin" ? "Robin" : "Kit"
                players.append(quizPlayer(person, name, status: "invited", score: 0, host: false))
            }
        } else {
            players = [quizPlayer("p_robin", "Robin", score: 0, host: true),
                       quizPlayer("p_alex", "Alex", status: meJoined ? "joined" : "invited", score: 0, host: false)]
        }
        return """
        {"id": \(s(id)), "game": "quiz-night", "difficulty": \(s(difficulty)), "audience": \(s(audience)),
         "topic": \(s(topic)), "title": \(s(title)), "phase": "lobby", "prep": \(s(prep)), "prepError": null,
         "hostId": \(s(hostIsMe ? "p_alex" : "p_robin")), "meId": "p_alex", "questionCount": 10, "timeMs": \(seconds * 1000),
         "players": \(list(players)),
         "phaseEndsAt": \(ms(now.addingTimeInterval(170))), "question": null, "standings": null, "winnerIds": [],
         "serverNow": \(ms(now))}
        """
    }

    /// The Solar System, for kids, easy. On a question (Alex's quiz, question
    /// 3, Sam has answered, Alex has not) or on a reveal (Sam's quiz,
    /// question 4, everybody's picks and the explanation).
    static func quizRoom(reveal: Bool, clock: DemoClock) -> String {
        let now = clock.now
        let question: String
        let players: [String]
        if reveal {
            players = [quizPlayer("p_sam", "Sam", score: 1480, host: true),
                       quizPlayer("p_alex", "Alex", score: 2930, host: false),
                       quizPlayer("p_robin", "Robin", score: 2210, host: false)]
            question = """
            {"index": 3, "prompt": "Which planet is known as the Red Planet?",
             "options": ["Venus", "Mars", "Jupiter", "Mercury"], "startsAt": \(ms(now.addingTimeInterval(-9))),
             "answeredIds": ["p_sam", "p_alex", "p_robin"], "myChoice": 1, "answerIndex": 1,
             "explain": "Iron oxide — rust — in its dust and rocks gives Mars its colour.",
             "picks": [{"playerId": "p_sam", "choice": 0, "points": 0, "ms": 6100},
                       {"playerId": "p_alex", "choice": 1, "points": 812, "ms": 3760},
                       {"playerId": "p_robin", "choice": 1, "points": 655, "ms": 6900}]}
            """
        } else {
            players = [quizPlayer("p_alex", "Alex", score: 1420, host: true),
                       quizPlayer("p_sam", "Sam", score: 910, host: false),
                       quizPlayer("p_robin", "Robin", score: 1265, host: false)]
            question = """
            {"index": 2, "prompt": "How many planets are there in our solar system?",
             "options": ["Seven", "Eight", "Nine", "Ten"], "startsAt": \(ms(now.addingTimeInterval(-8))),
             "answeredIds": ["p_sam"], "myChoice": null, "answerIndex": null, "explain": null, "picks": []}
            """
        }
        return """
        {"id": \(s(reveal ? demoQuizRevealRoom : demoQuizRoom)), "game": "quiz-night", "difficulty": "easy",
         "audience": "kids", "topic": "space", "title": "The Solar System",
         "phase": \(s(reveal ? "reveal" : "question")), "prep": "ready", "prepError": null,
         "hostId": \(s(reveal ? "p_sam" : "p_alex")), "meId": "p_alex", "questionCount": 10, "timeMs": 20000,
         "players": \(list(players)),
         "phaseEndsAt": \(ms(now.addingTimeInterval(reveal ? 3 : 12))),
         "question": \(question),
         "standings": null, "winnerIds": [],
         "serverNow": \(ms(now))}
        """
    }

    // MARK: Anagram Blitz, Quick Maths Sprint, Sequence Memory

    /// Anagram Blitz, medium, 46 seconds in. The letters are PAINTER's,
    /// shuffled; the room does not say so (`seed` is null until finished).
    /// Alex has five words; Sam and Robin are a count and a score.
    static func anagramRoom(_ clock: DemoClock) -> String {
        let now = clock.now
        func word(_ w: String, _ points: Int) -> String { "{\"word\": \(s(w)), \"points\": \(points), \"unique\": null}" }
        let john = [word("paint", 4), word("rate", 2), word("pier", 2), word("train", 4), word("nip", 1)]
        return """
        {"id": \(s(demoAnagramRoom)), "game": "anagram-blitz", "difficulty": "medium", "phase": "playing",
         "hostId": "p_alex", "meId": "p_alex",
         "letterCount": 7, "minLength": 3, "points": {"3": 1, "4": 2, "5": 4, "6": 6, "7": 10},
         "timeLimitMs": 120000, "startedAt": \(ms(now.addingTimeInterval(-46))),
         "phaseEndsAt": \(ms(now.addingTimeInterval(74))),
         "letters": ["t", "r", "e", "n", "i", "a", "p"],
         "players": [
           {"id": "p_alex", "name": "Alex", "status": "joined", "isHost": true, "wordCount": 5, "score": 13,
            "words": \(list(john))},
           {"id": "p_sam", "name": "Sam", "status": "joined", "isHost": false, "wordCount": 3, "score": 7, "words": null},
           {"id": "p_robin", "name": "Robin", "status": "joined", "isHost": false, "wordCount": 6, "score": 12, "words": null}
         ],
         "seed": null, "found": null, "missed": null, "standings": null, "winnerIds": [],
         "serverNow": \(ms(now))}
        """
    }

    /// Quick Maths Sprint, medium, 23 seconds in. Alex is on problem 9 with
    /// five right in a row — the bonus cue — one miss behind him.
    static func sprintRoom(_ clock: DemoClock) -> String {
        let now = clock.now
        return """
        {"id": \(s(demoSprintRoom)), "game": "maths-sprint", "difficulty": "medium", "phase": "playing",
         "hostId": "p_robin", "meId": "p_alex",
         "timeLimitMs": 60000, "problemCount": 200, "streakBonus": 5,
         "startedAt": \(ms(now.addingTimeInterval(-23))), "phaseEndsAt": \(ms(now.addingTimeInterval(37))),
         "players": [
           {"id": "p_robin", "name": "Robin", "status": "joined", "isHost": true, "score": 6, "answered": 6},
           {"id": "p_alex", "name": "Alex", "status": "joined", "isHost": false, "score": 9, "answered": 8},
           {"id": "p_sam", "name": "Sam", "status": "joined", "isHost": false, "score": 11, "answered": 10}
         ],
         "me": {"problem": {"index": 8, "text": "7 × 8"}, "score": 9, "correct": 8, "misses": 1,
                "streak": 5, "bestStreak": 5},
         "standings": null, "winnerIds": [], "recaps": null,
         "serverNow": \(ms(now))}
        """
    }

    /// Sequence Memory, medium (six tiles), round 3 of five steps, the input
    /// window a second old. Sam has sent; Robin went out in round 2.
    static func memoryRoom(_ clock: DemoClock) -> String {
        let now = clock.now
        let inputAt = now.addingTimeInterval(-1)
        let showAt = inputAt.addingTimeInterval(-3.35)
        let inputEndsAt = inputAt.addingTimeInterval(6)
        return """
        {"id": \(s(demoMemoryRoom)), "game": "sequence-memory", "difficulty": "medium", "phase": "input",
         "hostId": "p_sam", "meId": "p_alex",
         "tiles": 6, "startLength": 3, "maxLength": 20, "phaseEndsAt": \(ms(inputEndsAt)),
         "players": [
           {"id": "p_sam", "name": "Sam", "status": "joined", "isHost": true, "playing": true, "alive": true,
            "best": 4, "roundsSurvived": 2, "outRound": null},
           {"id": "p_alex", "name": "Alex", "status": "joined", "isHost": false, "playing": true, "alive": true,
            "best": 4, "roundsSurvived": 2, "outRound": null},
           {"id": "p_robin", "name": "Robin", "status": "joined", "isHost": false, "playing": true, "alive": false,
            "best": 3, "roundsSurvived": 1, "outRound": 2}
         ],
         "round": {"number": 3, "length": 5, "showAt": \(ms(showAt)), "stepMs": 550, "gapMs": 150,
                   "steps": null, "inputAt": \(ms(inputAt)), "windowMs": 6000,
                   "inputEndsAt": \(ms(inputEndsAt)), "closesAt": \(ms(inputEndsAt.addingTimeInterval(1))),
                   "answeredIds": ["p_sam"], "attempts": null, "survivorIds": null},
         "standings": null, "winnerIds": [],
         "serverNow": \(ms(now))}
        """
    }

    // MARK: Boggle

    /// Boggle, 4×4, medium, classic scoring. Playing: 52 seconds in, Alex has
    /// five words and is halfway through tracing another. Finished (Sam's
    /// game): TRAP was found by both and crossed out; ALIEN is lit, one of the
    /// words nobody found.
    static func boggleRoom(finished: Bool, clock: DemoClock) -> String {
        let now = clock.now
        let grid = #"["t","r","a","p","s","e","n","d","l","i","o","qu","a","m","e","s"]"#
        func word(_ w: String, _ points: Int, _ path: [Int], shared: String = "null") -> String {
            "{\"word\": \(s(w)), \"points\": \(points), \"shared\": \(shared), \"path\": \(path)}"
        }
        let points = #"{"3": 1, "4": 1, "5": 2, "6": 3, "7": 5, "8": 11}"#
        if !finished {
            let alex = [word("send", 1, [4, 5, 6, 7]), word("trap", 1, [0, 1, 2, 3]), word("tern", 1, [0, 1, 5, 6]),
                        word("lime", 1, [8, 9, 13, 14]), word("noise", 2, [6, 10, 9, 4, 5])]
            return """
            {"id": \(s(demoBoggleRoom)), "game": "boggle", "difficulty": "medium", "phase": "playing",
             "hostId": "p_alex", "meId": "p_alex", "size": 4, "scoring": "classic", "minLength": 3,
             "points": \(points), "timeLimitMs": 120000,
             "startedAt": \(ms(now.addingTimeInterval(-52))), "phaseEndsAt": \(ms(now.addingTimeInterval(68))),
             "grid": \(grid),
             "players": [
               {"id": "p_alex", "name": "Alex", "status": "joined", "isHost": true, "wordCount": 5, "score": 6,
                "words": \(list(alex))},
               {"id": "p_sam", "name": "Sam", "status": "joined", "isHost": false, "wordCount": 4, "score": 5, "words": null},
               {"id": "p_robin", "name": "Robin", "status": "joined", "isHost": false, "wordCount": 7, "score": 8, "words": null}
             ],
             "found": null, "missed": null, "possible": null, "standings": null, "winnerIds": [],
             "serverNow": \(ms(now))}
            """
        }
        let alex = [word("trap", 0, [0, 1, 2, 3], shared: "true"), word("noise", 2, [6, 10, 9, 4, 5], shared: "false"),
                    word("lime", 1, [8, 9, 13, 14], shared: "false")]
        let sam = [word("trap", 0, [0, 1, 2, 3], shared: "true"), word("send", 1, [4, 5, 6, 7], shared: "false")]
        return """
        {"id": \(s(demoBoggleDoneRoom)), "game": "boggle", "difficulty": "medium", "phase": "finished",
         "hostId": "p_sam", "meId": "p_alex", "size": 4, "scoring": "classic", "minLength": 3,
         "points": \(points), "timeLimitMs": 120000,
         "startedAt": \(ms(now.addingTimeInterval(-160))), "phaseEndsAt": \(ms(now.addingTimeInterval(560))),
         "grid": \(grid),
         "players": [
           {"id": "p_sam", "name": "Sam", "status": "joined", "isHost": true, "wordCount": 2, "score": 1,
            "words": \(list(sam))},
           {"id": "p_alex", "name": "Alex", "status": "joined", "isHost": false, "wordCount": 3, "score": 3,
            "words": \(list(alex))}
         ],
         "found": [
           {"word": "noise", "points": 2, "finderIds": ["p_alex"], "shared": false, "path": [6, 10, 9, 4, 5]},
           {"word": "lime", "points": 1, "finderIds": ["p_alex"], "shared": false, "path": [8, 9, 13, 14]},
           {"word": "send", "points": 1, "finderIds": ["p_sam"], "shared": false, "path": [4, 5, 6, 7]},
           {"word": "trap", "points": 0, "finderIds": ["p_alex", "p_sam"], "shared": true, "path": [0, 1, 2, 3]}
         ],
         "missed": [
           {"word": "alien", "points": 2, "path": [12, 8, 9, 5, 6]},
           {"word": "mien", "points": 1, "path": [13, 9, 5, 6]},
           {"word": "rend", "points": 1, "path": [1, 5, 6, 7]}
         ],
         "possible": {"words": 38, "points": 49},
         "standings": [{"id": "p_alex", "name": "Alex", "score": 3, "words": 3, "longest": "noise"},
                       {"id": "p_sam", "name": "Sam", "score": 1, "words": 2, "longest": "trap"}],
         "winnerIds": ["p_alex"],
         "serverNow": \(ms(now))}
        """
    }

    // MARK: Categories

    /// Categories, letter B, eight categories, easy. Playing: 40 seconds in,
    /// Alex has four answers (the screen adds a half-typed "Pumpkin" on the
    /// last line, so its warning shows). Review (Sam's game): BEAR is shared by
    /// Alex and Sam, Robin's "Dog" is the wrong letter, and Robin's "Bogey"
    /// has Alex's veto — one of two others, so it is struck.
    static func categoriesRoom(review: Bool, clock: DemoClock) -> String {
        let now = clock.now
        let card = ["An animal", "A food", "A country", "A girl's name", "Something in a kitchen",
                    "A sport", "Something cold", "A TV show"]
        func answer(_ index: Int, _ text: String, _ status: String = "null", points: Int = 0,
                    vetoes: Int = 0, strikeAt: Int = 0, vetoed: Bool = false) -> String {
            "{\"index\": \(index), \"text\": \(s(text)), \"status\": \(status), \"points\": \(points), "
                + "\"vetoes\": \(vetoes), \"strikeAt\": \(strikeAt), \"vetoed\": \(vetoed)}"
        }
        func q(_ status: String) -> String { "\"\(status)\"" }
        let categories = list(card.map { s($0) })
        if !review {
            let alex = [answer(0, "Badger"), answer(1, "Bagel"), answer(2, "Brazil"), answer(3, "Bella"),
                        answer(4, ""), answer(5, ""), answer(6, ""), answer(7, "")]
            return """
            {"id": \(s(demoCategoriesRoom)), "game": "categories", "difficulty": "easy", "phase": "playing",
             "hostId": "p_alex", "meId": "p_alex", "categoryCount": 8, "timeLimitMs": 120000, "reviewMs": 60000,
             "maxAnswer": 40, "startedAt": \(ms(now.addingTimeInterval(-40))), "phaseEndsAt": \(ms(now.addingTimeInterval(80))),
             "letter": "b", "categories": \(categories),
             "players": [
               {"id": "p_alex", "name": "Alex", "status": "joined", "isHost": true, "filled": 4, "done": false,
                "score": 0, "answers": \(list(alex))},
               {"id": "p_sam", "name": "Sam", "status": "joined", "isHost": false, "filled": 5, "done": false,
                "score": 0, "answers": null},
               {"id": "p_robin", "name": "Robin", "status": "joined", "isHost": false, "filled": 3, "done": false,
                "score": 0, "answers": null}
             ],
             "standings": null, "winnerIds": [], "serverNow": \(ms(now))}
            """
        }
        let empty = (0..<8).map { $0 }
        func row(_ given: [Int: String]) -> [String] {
            empty.map { given[$0] ?? answer($0, "", q("empty"), strikeAt: 1) }
        }
        let alex = row([0: answer(0, "Bear", q("shared"), strikeAt: 1),
                        1: answer(1, "Banana bread", q("ok"), points: 1, strikeAt: 1),
                        2: answer(2, "Belgium", q("ok"), points: 1, strikeAt: 1),
                        3: answer(3, "Bella", q("ok"), points: 1, strikeAt: 1),
                        5: answer(5, "Badminton", q("ok"), points: 1, strikeAt: 1)])
        let sam = row([0: answer(0, "the bear", q("shared"), strikeAt: 1),
                       1: answer(1, "Burrito", q("ok"), points: 1, strikeAt: 1),
                       4: answer(4, "Blender", q("ok"), points: 1, strikeAt: 1),
                       6: answer(6, "Blizzard", q("ok"), points: 1, strikeAt: 1)])
        let robin = row([0: answer(0, "Dog", q("wrong-letter"), strikeAt: 1),
                         2: answer(2, "Bhutan", q("ok"), points: 1, strikeAt: 1),
                         7: answer(7, "Bogey", q("struck"), vetoes: 1, strikeAt: 1, vetoed: true)])
        return """
        {"id": \(s(demoCategoriesReviewRoom)), "game": "categories", "difficulty": "easy", "phase": "review",
         "hostId": "p_sam", "meId": "p_alex", "categoryCount": 8, "timeLimitMs": 120000, "reviewMs": 60000,
         "maxAnswer": 40, "startedAt": \(ms(now.addingTimeInterval(-150))), "phaseEndsAt": \(ms(now.addingTimeInterval(30))),
         "letter": "b", "categories": \(categories),
         "players": [
           {"id": "p_sam", "name": "Sam", "status": "joined", "isHost": true, "filled": 4, "done": true,
            "score": 3, "answers": \(list(sam))},
           {"id": "p_alex", "name": "Alex", "status": "joined", "isHost": false, "filled": 5, "done": false,
            "score": 4, "answers": \(list(alex))},
           {"id": "p_robin", "name": "Robin", "status": "joined", "isHost": false, "filled": 3, "done": false,
            "score": 1, "answers": \(list(robin))}
         ],
         "standings": null, "winnerIds": [], "serverNow": \(ms(now))}
        """
    }
}
