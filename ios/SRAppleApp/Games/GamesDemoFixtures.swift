#if DEBUG
import Foundation

// MARK: - Demo games
//
// `-SRDemo` answers for `/api/native/games*`. Synthetic throughout — the
// repository is public. Two family members to invite (Sam, Robin), one
// invitation from Sam, one lobby of John's own that Sam has joined and
// Robin has not answered, and one Wordle Race of Sam's half played — John
// three rows in, Sam two (colours only), Robin solved. Quiz Night: an invite
// from Robin (with its `about` line), one quiz of John's on a question and one
// of Sam's on a reveal, so both screens can be shot. The room stream has no
// fixture and 404s, which is the fallback the room screen must survive: it
// re-reads the snapshot.

extension SRDemoFixtures {

    static let demoLobbyRoom = "g_demo_lobby"
    static let demoInviteRoom = "g_demo_invite"
    static let demoWordleRoom = "g_demo_wordle"
    static let demoQuizRoom = "g_demo_quiz"
    static let demoQuizRevealRoom = "g_demo_quiz_reveal"
    static let demoQuizInviteRoom = "g_demo_quiz_invite"

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

    static func gamesLobby(_ clock: DemoClock) -> String {
        let now = clock.now
        return """
        {"me": {"id": "p_john", "name": "John"},
         "players": [{"id": "p_sam", "name": "Sam"}, {"id": "p_robin", "name": "Robin"}],
         "invites": [{"roomId": \(s(demoInviteRoom)), "game": "tap-duel", "difficulty": "medium", "hostName": "Sam",
                      "players": ["Sam", "Robin", "John"], "expiresAt": \(ms(now.addingTimeInterval(150))), "about": null},
                     {"roomId": \(s(demoQuizInviteRoom)), "game": "quiz-night", "difficulty": "easy", "hostName": "Robin",
                      "players": ["Robin", "John"], "expiresAt": \(ms(now.addingTimeInterval(170))),
                      "about": "The Solar System · for kids"}],
         "rooms": [{"id": \(s(demoLobbyRoom)), "game": "tap-duel", "phase": "lobby", "hostName": "John"},
                   {"id": \(s(demoWordleRoom)), "game": "wordle-race", "phase": "playing", "hostName": "Sam"},
                   {"id": \(s(demoQuizRoom)), "game": "quiz-night", "phase": "question", "hostName": "John"},
                   {"id": \(s(demoQuizRevealRoom)), "game": "quiz-night", "phase": "reveal", "hostName": "Sam"}],
         "serverNow": \(ms(now))}
        """
    }

    static func demoRoom(id: String, meJoined: Bool, clock: DemoClock) -> String {
        if id == demoWordleRoom { return wordleRoom(clock) }
        if id == demoQuizRoom { return quizRoom(reveal: false, clock: clock) }
        if id == demoQuizRevealRoom { return quizRoom(reveal: true, clock: clock) }
        if id == demoQuizInviteRoom {
            return quizLobby(id: id, fields: ["topic": "space", "audience": "kids", "difficulty": "easy"],
                             invited: [], hostIsMe: false, meJoined: meJoined, prep: "writing", clock: clock)
        }
        if id == demoInviteRoom {
            return gameRoom(id: id, hostIsMe: false, meJoined: meJoined, invited: [], clock: clock)
        }
        return gameRoom(id: id, hostIsMe: true, meJoined: true, invited: ["p_robin"], clock: clock)
    }

    /// A lobby. Hosted by John (Sam in, `invited` waiting), or by Sam with John
    /// invited or joined.
    static func gameRoom(id: String, hostIsMe: Bool, meJoined: Bool, invited: [String],
                         game: String = "tap-duel", clock: DemoClock) -> String {
        let now = clock.now
        let players: [String]
        if hostIsMe {
            var rows = [#"{"id": "p_john", "name": "John", "status": "joined", "score": 0, "isHost": true}"#]
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
                "{\"id\": \"p_john\", \"name\": \"John\", \"status\": \(s(meJoined ? "joined" : "invited")), \"score\": 0, \"isHost\": false}",
            ]
        }
        return """
        {"id": \(s(id)), "game": \(s(game)), "difficulty": \(s(hostIsMe ? "easy" : "medium")), "phase": "lobby",
         "hostId": \(s(hostIsMe ? "p_john" : "p_sam")), "meId": "p_john", "rounds": 5,
         "players": \(list(players)),
         "phaseEndsAt": \(ms(now.addingTimeInterval(160))), "round": null, "standings": null, "winnerIds": [],
         "serverNow": \(ms(now))}
        """
    }

    /// Wordle Race, medium, 88 seconds in. The word is GRAPE, which the room
    /// does not say (`secret` is null until finished). John: PEARL, CREPE,
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
         "hostId": "p_sam", "meId": "p_john",
         "wordLength": 5, "maxGuesses": 6, "timeLimitMs": 240000, "hardMode": false,
         "startedAt": \(ms(now.addingTimeInterval(-88))),
         "phaseEndsAt": \(ms(now.addingTimeInterval(152))),
         "players": [
           {"id": "p_sam", "name": "Sam", "status": "joined", "isHost": true,
            "guessCount": 2, "solved": false, "done": false, "solveMs": null, "rows": \(list(sam))},
           {"id": "p_john", "name": "John", "status": "joined", "isHost": false,
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

    /// A quiz lobby — a new one of John's (questions ready), or Robin's
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
            players = [quizPlayer("p_john", "John", score: 0, host: true)]
            for person in invited {
                let name = person == "p_sam" ? "Sam" : person == "p_robin" ? "Robin" : "Kit"
                players.append(quizPlayer(person, name, status: "invited", score: 0, host: false))
            }
        } else {
            players = [quizPlayer("p_robin", "Robin", score: 0, host: true),
                       quizPlayer("p_john", "John", status: meJoined ? "joined" : "invited", score: 0, host: false)]
        }
        return """
        {"id": \(s(id)), "game": "quiz-night", "difficulty": \(s(difficulty)), "audience": \(s(audience)),
         "topic": \(s(topic)), "title": \(s(title)), "phase": "lobby", "prep": \(s(prep)), "prepError": null,
         "hostId": \(s(hostIsMe ? "p_john" : "p_robin")), "meId": "p_john", "questionCount": 10, "timeMs": \(seconds * 1000),
         "players": \(list(players)),
         "phaseEndsAt": \(ms(now.addingTimeInterval(170))), "question": null, "standings": null, "winnerIds": [],
         "serverNow": \(ms(now))}
        """
    }

    /// The Solar System, for kids, easy. On a question (John's quiz, question
    /// 3, Sam has answered, John has not) or on a reveal (Sam's quiz,
    /// question 4, everybody's picks and the explanation).
    static func quizRoom(reveal: Bool, clock: DemoClock) -> String {
        let now = clock.now
        let question: String
        let players: [String]
        if reveal {
            players = [quizPlayer("p_sam", "Sam", score: 1480, host: true),
                       quizPlayer("p_john", "John", score: 2930, host: false),
                       quizPlayer("p_robin", "Robin", score: 2210, host: false)]
            question = """
            {"index": 3, "prompt": "Which planet is known as the Red Planet?",
             "options": ["Venus", "Mars", "Jupiter", "Mercury"], "startsAt": \(ms(now.addingTimeInterval(-9))),
             "answeredIds": ["p_sam", "p_john", "p_robin"], "myChoice": 1, "answerIndex": 1,
             "explain": "Iron oxide — rust — in its dust and rocks gives Mars its colour.",
             "picks": [{"playerId": "p_sam", "choice": 0, "points": 0, "ms": 6100},
                       {"playerId": "p_john", "choice": 1, "points": 812, "ms": 3760},
                       {"playerId": "p_robin", "choice": 1, "points": 655, "ms": 6900}]}
            """
        } else {
            players = [quizPlayer("p_john", "John", score: 1420, host: true),
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
         "hostId": \(s(reveal ? "p_sam" : "p_john")), "meId": "p_john", "questionCount": 10, "timeMs": 20000,
         "players": \(list(players)),
         "phaseEndsAt": \(ms(now.addingTimeInterval(reveal ? 3 : 12))),
         "question": \(question),
         "standings": null, "winnerIds": [],
         "serverNow": \(ms(now))}
        """
    }
}
#endif
