import Foundation

// MARK: - Demo Azul
//
// `-SRDemo` rooms for Azul. Synthetic throughout. Two rooms of three (Alex,
// Sam, Robin) on phones only: round 3 mid-way, Alex's turn with 62 seconds
// left, five factories still full, the centre holding the first-player
// marker, and a few tiles on every wall — Robin away after a take the clock
// made for them; and a finished game Sam won on a complete row, with the
// bonuses broken down.
//
// `canPlace` is worked out by hand from Alex's board, as the server would
// send it. That is a FIXTURE convenience: the app itself never decides
// which lines are legal, it lights the server's.

extension SRDemoFixtures {

    static let demoAzulRoom = "g_demo_azul"
    static let demoAzulDoneRoom = "g_demo_azul_done"

    /// The rooms for the lobby's "Your games", left out of the store shots as
    /// Categories' are.
    static let azulLobbyRows = #"""
    {"id": "g_demo_azul", "game": "azul", "phase": "playing", "hostName": "Alex", "durable": true, "pace": "live"},
                       {"id": "g_demo_azul_done", "game": "azul", "phase": "finished", "hostName": "Sam", "durable": true, "pace": "live"},
    """#

    /// The room for `id`, or nil when it is not one of Azul's.
    static func azulRoom(id: String, clock: DemoClock) -> String? {
        switch id {
        case demoAzulRoom: return azulPlaying(clock: clock)
        case demoAzulDoneRoom: return azulDone(clock: clock)
        default: return nil
        }
    }

    private static func azulTile(_ id: Int) -> String {
        "{\"id\": \(id), \"c\": \(s(AzulRules.colours[min(4, id / 20)]))}"
    }

    private static func azulTiles(_ ids: [Int]) -> String {
        "[" + ids.map(azulTile).joined(separator: ", ") + "]"
    }

    /// Five lines of tile ids.
    private static func azulLines(_ lines: [[Int]]) -> String {
        "[" + lines.map(azulTiles).joined(separator: ", ") + "]"
    }

    /// A wall from rows of tile ids, nil for an empty square.
    private static func azulWall(_ rows: [[Int?]]) -> String {
        "[" + rows.map { row in "[" + row.map { $0.map(String.init) ?? "null" }.joined(separator: ", ") + "]" }
            .joined(separator: ", ") + "]"
    }

    /// A wall from five strings, `x` where a tile is: each tile's id is its
    /// colour's block plus its row plus `offset`, so walls never share an id.
    private static func azulWall(marks: [String], offset: Int) -> String {
        let rows: [[Int?]] = marks.enumerated().map { row, mark in
            Array(mark).enumerated().map { col, ch in
                guard ch == "x" else { return nil }
                let colour = AzulRules.wallColour(row: row, col: col)
                return (AzulRules.colours.firstIndex(of: colour) ?? 0) * 20 + row + offset
            }
        }
        return azulWall(rows)
    }

    private static func azulBoard(_ id: String, _ name: String, host: Bool, seat: Int, score: Int, away: Bool = false,
                                  lines: String, wall: String, floor: [Int] = [], penalty: Int = 0, rows: Int = 0) -> String {
        "{\"id\": \(s(id)), \"name\": \(s(name)), \"status\": \"joined\", \"isHost\": \(host), \"seat\": \(seat), "
            + "\"score\": \(score), \"away\": \(away), \"lines\": \(lines), \"wall\": \(wall), \"floor\": \(azulTiles(floor)), "
            + "\"floorPenalty\": \(penalty), \"rows\": \(rows), \"hasFirst\": false, \"sawInvite\": true}"
    }

    private static func azulLog(_ n: Int, by: String?, _ text: String, auto: Bool = false, at: Date) -> String {
        "{\"n\": \(n), \"at\": \(ms(at)), \"by\": \(s(by)), \"text\": \(s(text)), \"auto\": \(auto)}"
    }

    static func azulPlaying(clock: DemoClock) -> String {
        let now = clock.now
        let alex = azulBoard("p_alex", "Alex", host: true, seat: 1, score: 14,
                             lines: azulLines([[], [21], [], [61, 62], [41, 42, 43]]),
                             wall: azulWall([[1, 22, nil, nil, nil], [nil, nil, nil, 44, nil], [nil, nil, 2, nil, nil],
                                             [nil, nil, nil, nil, nil], [nil, nil, nil, 80, nil]]))
        let sam = azulBoard("p_sam", "Sam", host: false, seat: 0, score: 18,
                            lines: azulLines([[9], [], [81, 82], [], [29]]),
                            wall: azulWall([[nil, 23, nil, nil, nil], [nil, 3, nil, nil, nil], [nil, nil, nil, nil, 50],
                                            [51, 63, nil, nil, nil], [nil, nil, nil, nil, nil]]),
                            floor: [52], penalty: 1)
        let robin = azulBoard("p_robin", "Robin", host: false, seat: 2, score: 11, away: true,
                              lines: azulLines([[], [64, 65], [], [10], []]),
                              wall: azulWall([[4, nil, nil, nil, 84], [nil, nil, nil, nil, nil], [nil, 91, nil, nil, nil],
                                              [nil, nil, nil, nil, nil], [30, nil, nil, nil, nil]]))
        let factories = [[], [5, 6, 45, 85], [24, 25, 26, 66], [], [46, 47, 67, 86], [7, 27, 68, 69], [87, 88, 48, 8]]
            .map(azulTiles).joined(separator: ", ")
        let log = [
            azulLog(21, by: nil, "Round 3. Sam to start.", at: now.addingTimeInterval(-140)),
            azulLog(22, by: "p_sam", "Sam took 1 yellow from factory 1 → line 5.", at: now.addingTimeInterval(-110)),
            azulLog(23, by: "p_alex", "Alex took 2 red from factory 4 → line 5.", at: now.addingTimeInterval(-80)),
            azulLog(24, by: "p_robin", "Robin took 2 black from factory 4 → line 2.", auto: true, at: now.addingTimeInterval(-28)),
        ].joined(separator: ", ")
        return """
        {"id": \(s(demoAzulRoom)), "game": "azul", "difficulty": "medium", "phase": "playing",
         "hostId": "p_alex", "meId": "p_alex", "table": "phones", "turnMs": 90000, "deadlineHours": null,
         "startedAt": \(ms(now.addingTimeInterval(-900))), "phaseEndsAt": \(ms(now.addingTimeInterval(62))),
         "round": 3, "lastRound": false, "turnId": "p_alex", "turnStartedAt": \(ms(now.addingTimeInterval(-28))),
         "colours": ["blue", "yellow", "red", "black", "white"],
         "factories": [\(factories)],
         "centre": \(azulTiles([28, 70, 89, 90, 49])), "firstInCentre": true, "bag": 31, "lid": 4,
         "canPlace": {"blue": [], "yellow": [1, 2], "red": [0, 2, 4], "black": [0, 2, 3], "white": [0, 2]},
         "last": {"by": "p_robin", "source": 3, "colour": "black", "tiles": [64, 65], "line": 1, "overflow": 0,
                  "toCentre": [70, 90], "tookFirst": false, "auto": true, "at": \(ms(now.addingTimeInterval(-28)))},
         "roundScores": null, "log": [\(log)],
         "players": [\(sam), \(alex), \(robin)],
         "result": null, "standings": null, "winnerIds": [],
         "durable": true, "pace": "live", "version": 41, "serverNow": \(ms(now))}
        """
    }

    static func azulDone(clock: DemoClock) -> String {
        let now = clock.now
        let empty = azulLines([[], [], [], [], []])
        let sam = azulBoard("p_sam", "Sam", host: true, seat: 0, score: 58, lines: empty,
                            wall: azulWall(marks: ["xxxxx", "xx.x.", "x.x..", ".x..x", "..x.x"], offset: 0), rows: 1)
        let alex = azulBoard("p_alex", "Alex", host: false, seat: 1, score: 51, lines: empty,
                             wall: azulWall(marks: ["xx.x.", "xxx.x", "x.xx.", "xx...", "x..x."], offset: 5))
        let robin = azulBoard("p_robin", "Robin", host: false, seat: 2, score: 34, lines: empty,
                              wall: azulWall(marks: ["x...x", ".x.x.", "..x..", "x..x.", ".x..."], offset: 10))
        return """
        {"id": \(s(demoAzulDoneRoom)), "game": "azul", "difficulty": "easy", "phase": "finished",
         "hostId": "p_sam", "meId": "p_alex", "table": "tv", "turnMs": 180000, "deadlineHours": null,
         "startedAt": \(ms(now.addingTimeInterval(-2400))), "phaseEndsAt": \(ms(now.addingTimeInterval(540))),
         "round": 6, "lastRound": true, "turnId": null, "turnStartedAt": null,
         "colours": ["blue", "yellow", "red", "black", "white"],
         "factories": [[], [], [], [], [], [], []], "centre": [], "firstInCentre": false, "bag": 9, "lid": 12,
         "canPlace": {}, "last": null, "roundScores": null,
         "log": [\(azulLog(88, by: nil, "Sam wins it.", at: now.addingTimeInterval(-20)))],
         "players": [\(sam), \(alex), \(robin)],
         "result": {"winnerIds": ["p_sam"], "reason": "wall"},
         "standings": [
           {"id": "p_sam", "name": "Sam", "place": 1, "score": 58, "rows": 1, "bonus": {"rows": 1, "columns": 0, "colours": 0, "points": 2}, "result": "won"},
           {"id": "p_alex", "name": "Alex", "place": 2, "score": 51, "rows": 0, "bonus": {"rows": 0, "columns": 1, "colours": 0, "points": 7}, "result": "lost"},
           {"id": "p_robin", "name": "Robin", "place": 3, "score": 34, "rows": 0, "bonus": {"rows": 0, "columns": 0, "colours": 0, "points": 0}, "result": "lost"}],
         "winnerIds": ["p_sam"], "durable": true, "pace": "live", "version": 212, "serverNow": \(ms(now))}
        """
    }
}
