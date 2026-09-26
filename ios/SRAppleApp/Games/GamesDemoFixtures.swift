#if DEBUG
import Foundation

// MARK: - Demo games
//
// `-SRDemo` answers for `/api/native/games*`. Synthetic throughout — the
// repository is public. Two family members to invite (Sam, Robin), one
// invitation from Sam, one lobby of John's own that Sam has joined and
// Robin has not answered, and one Wordle Race of Sam's half played — John
// three rows in, Sam two (colours only), Robin solved. The room stream has no
// fixture and 404s, which is the fallback the room screen must survive: it
// re-reads the snapshot.

extension SRDemoFixtures {

    static let demoLobbyRoom = "g_demo_lobby"
    static let demoInviteRoom = "g_demo_invite"
    static let demoWordleRoom = "g_demo_wordle"

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
                      "players": ["Sam", "Robin", "John"], "expiresAt": \(ms(now.addingTimeInterval(150)))}],
         "rooms": [{"id": \(s(demoLobbyRoom)), "game": "tap-duel", "phase": "lobby", "hostName": "John"},
                   {"id": \(s(demoWordleRoom)), "game": "wordle-race", "phase": "playing", "hostName": "Sam"}],
         "serverNow": \(ms(now))}
        """
    }

    static func demoRoom(id: String, meJoined: Bool, clock: DemoClock) -> String {
        if id == demoWordleRoom { return wordleRoom(clock) }
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
}
#endif
