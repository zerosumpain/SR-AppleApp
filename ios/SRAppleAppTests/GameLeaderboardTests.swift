import XCTest
@testable import SRAppleApp

/// The games leaderboard: the wire (`GET api/native/games/leaderboard`), the
/// demo fixture, and the "new high score" line a finished room shows.
final class GameLeaderboardTests: XCTestCase {

    // MARK: - The wire, as SR-Main sends it

    private let boardJSON = #"""
    {"me": {"id": "p_b"}, "window": "week", "from": "2026-09-27T23:00:00.000Z",
     "overall": [
       {"rank": 1, "playerId": "p_a", "name": "John", "wins": 3, "played": 5},
       {"rank": 2, "playerId": "p_b", "name": "Sam", "wins": 1, "played": 5}
     ],
     "games": [
       {"game": "boggle", "title": "Boggle", "scored": true, "rows": [
         {"rank": 1, "playerId": "p_b", "name": "Sam", "best": 31, "bestLabel": "6×6 · 3 minutes · hard", "wins": 1, "played": 2},
         {"rank": 2, "playerId": "p_a", "name": "John", "best": 30, "bestLabel": null, "wins": 1, "played": 2}
       ]},
       {"game": "liars-dice", "title": "Liar's Dice", "scored": false, "rows": [
         {"rank": 1, "playerId": "p_a", "name": "John", "best": null, "bestLabel": "5 dice each · ones wild · hard", "wins": 2, "played": 3}
       ]}
     ]}
    """#

    func testABoardDecodesFromTheContract() throws {
        let board = try JSONDecoder().decode(GameLeaderboard.self, from: Data(boardJSON.utf8))
        XCTAssertEqual(board.meId, "p_b")
        XCTAssertEqual(board.window, "week")
        XCTAssertFalse(board.isEmpty)
        XCTAssertEqual(board.overall.map(\.name), ["John", "Sam"])
        XCTAssertEqual(board.overall.first?.wins, 3)
        XCTAssertEqual(board.overall.first?.played, 5)

        XCTAssertEqual(board.games.map(\.id), ["boggle", "liars-dice"])
        let boggle = try XCTUnwrap(board.games.first)
        XCTAssertTrue(boggle.scored)
        XCTAssertEqual(boggle.title, "Boggle")
        XCTAssertEqual(boggle.rows.map(\.best), [31, 30])
        XCTAssertEqual(boggle.rows.first?.bestLabel, "6×6 · 3 minutes · hard")
        XCTAssertNil(boggle.rows.last?.bestLabel)

        // A game with no score ranks by wins and has no best.
        let dice = try XCTUnwrap(board.games.last)
        XCTAssertFalse(dice.scored)
        XCTAssertNil(dice.rows.first?.best)
        XCTAssertEqual(dice.rows.first?.wins, 2)
        // A game this version does not know keeps the site's name.
        XCTAssertEqual(dice.title, "Liar's Dice")
    }

    func testAnEmptyWindowAndMissingFieldsDecode() throws {
        let empty = try JSONDecoder().decode(GameLeaderboard.self, from: Data(#"{"window":"day","overall":[],"games":[]}"#.utf8))
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.meId, "")

        // Only the player id is required of a row.
        let game = try JSONDecoder().decode(
            LeaderboardGame.self,
            from: Data(#"{"game":"tap-duel","rows":[{"playerId":"p_x"}]}"#.utf8)
        )
        XCTAssertEqual(game.title, "Tap Duel", "the app's own name for a game it knows")
        XCTAssertFalse(game.scored)
        XCTAssertEqual(game.rows.first?.name, "Someone")
        XCTAssertEqual(game.rows.first?.wins, 0)
        XCTAssertNil(game.rows.first?.best)
    }

    func testTheDemoBoardDecodesInEveryWindow() throws {
        for window in LeaderboardWindow.allCases {
            let json = SRDemoFixtures.gamesLeaderboard(window: window.rawValue)
            let board = try JSONDecoder().decode(GameLeaderboard.self, from: Data(json.utf8))
            XCTAssertEqual(board.window, window.rawValue)
            XCTAssertEqual(board.meId, "p_alex")
            XCTAssertEqual(board.overall.count, 3)
            XCTAssertFalse(board.games.isEmpty, "no games in \(window)")
        }
    }

    func testTheWindowsAreDayWeekAll() {
        XCTAssertEqual(LeaderboardWindow.allCases.map(\.rawValue), ["day", "week", "all"])
        XCTAssertEqual(LeaderboardWindow.allCases.map(\.label), ["Day", "Week", "All"])
    }

    // MARK: - A new high score on a finished room

    private func finished(records: String) throws -> GameRoom {
        let json = """
        {"id":"g_1","game":"boggle","difficulty":"easy","phase":"finished","hostId":"p_a","meId":"p_a",
         "players":[{"id":"p_a","name":"John","status":"joined","score":9,"isHost":true},
                    {"id":"p_b","name":"Sam","status":"joined","score":4,"isHost":false}],
         "standings":[{"id":"p_a","name":"John","score":9},{"id":"p_b","name":"Sam","score":4}],
         "winnerIds":["p_a"],\(records)"serverNow":1790000000000}
        """
        return try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    func testAFinishedRoomSaysWhoSetARecord() throws {
        let none = try finished(records: "")
        XCTAssertEqual(none.records, [:])
        XCTAssertNil(GameRecordLine.text(none))

        let mine = try finished(records: #""records":{"p_a":"week"},"#)
        XCTAssertEqual(mine.records, ["p_a": "week"])
        XCTAssertEqual(GameRecordLine.text(mine), "New high score this week!")

        let theirs = try finished(records: #""records":{"p_b":"all"},"#)
        XCTAssertEqual(GameRecordLine.text(theirs), "New high score ever — Sam")

        let today = try finished(records: #""records":{"p_a":"day","p_b":"day"},"#)
        XCTAssertEqual(GameRecordLine.text(today), "New high score today — You and Sam")
    }

    func testARoomWithoutRecordsStillDecodes() throws {
        // A malformed `records` is ignored, never a failed room.
        let odd = try finished(records: #""records":[1,2],"#)
        XCTAssertEqual(odd.records, [:])
    }
}
