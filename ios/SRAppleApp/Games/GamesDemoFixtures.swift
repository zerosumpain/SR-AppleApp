#if DEBUG
import Foundation

// MARK: - Demo games
//
// `-SRDemo` answers for `/api/native/games*`. Synthetic throughout — the
// repository is public. Two family members to invite (Sam, Robin), one
// invitation from Sam, and one lobby of John's own that Sam has joined and
// Robin has not answered. The room stream has no fixture and 404s, which is
// the fallback the room screen must survive: it re-reads the snapshot.

extension SRDemoFixtures {

    static let demoLobbyRoom = "g_demo_lobby"
    static let demoInviteRoom = "g_demo_invite"

    static func gamesRoute(method: String, parts: [String], body: Data?, clock: DemoClock) -> String? {
        // parts: ["api", "native", "games", ...]
        let rest = Array(parts.dropFirst(3))
        switch (method, rest.count) {
        case ("GET", 0):
            return gamesLobby(clock)
        case ("POST", 0):
            let invited = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["invite"] as? [String]) ?? []
            return "{\"room\": \(gameRoom(id: "g_demo_new", hostIsMe: true, meJoined: true, invited: invited, clock: clock))}"
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
         "rooms": [{"id": \(s(demoLobbyRoom)), "game": "tap-duel", "phase": "lobby", "hostName": "John"}],
         "serverNow": \(ms(now))}
        """
    }

    static func demoRoom(id: String, meJoined: Bool, clock: DemoClock) -> String {
        if id == demoInviteRoom {
            return gameRoom(id: id, hostIsMe: false, meJoined: meJoined, invited: [], clock: clock)
        }
        return gameRoom(id: id, hostIsMe: true, meJoined: true, invited: ["p_robin"], clock: clock)
    }

    /// A lobby. Hosted by John (Sam in, `invited` waiting), or by Sam with John
    /// invited or joined.
    static func gameRoom(id: String, hostIsMe: Bool, meJoined: Bool, invited: [String], clock: DemoClock) -> String {
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
        {"id": \(s(id)), "game": "tap-duel", "difficulty": \(s(hostIsMe ? "easy" : "medium")), "phase": "lobby",
         "hostId": \(s(hostIsMe ? "p_john" : "p_sam")), "meId": "p_john", "rounds": 5,
         "players": \(list(players)),
         "phaseEndsAt": \(ms(now.addingTimeInterval(160))), "round": null, "standings": null, "winnerIds": [],
         "serverNow": \(ms(now))}
        """
    }
}
#endif
