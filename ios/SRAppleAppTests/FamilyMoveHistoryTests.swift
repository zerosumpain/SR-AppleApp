import XCTest
@testable import SRAppleApp

/// One person's moves looked back over: the wire, and the words drawn from it.
final class FamilyMoveHistoryTests: XCTestCase {
    func testTheWireDecodesAndAShortPatternIsPaddedToAWeekOfHours() throws {
        let json = """
        {"subject":"sam","name":"Sam","days":28,"generatedAt":"2026-10-21T12:00:00Z",
         "totals":{"trips":12,"places":3,"minutes":190,"perWeek":3},
         "places":[{"name":"School","trips":8,"share":0.66}],
         "routes":[{"id":"r1","from":"Home","to":"School","mode":"active","trips":8,"median":15,"low":12,"high":19,
                    "departure":"08:24","recentMedian":13,"earlierMedian":16,"lastAt":"2026-10-20T07:24:00Z"}],
         "routines":[{"id":"r1:weekday","from":"Home","to":"School","dayType":"weekday","departure":"08:24",
                      "window":[497,510],"days":8,"of":10,"punctuality":{"early":1,"onTime":6,"late":1}}],
         "trips":[{"from":"Home","to":"School","start":"2026-10-20T07:24:00Z","minutes":14,"mode":"active","broken":false}],
         "pattern":[[0,0,0,0,0,0,0,0,5]]}
        """
        let h = try JSONDecoder().decode(FamilyMoveHistory.self, from: Data(json.utf8))
        XCTAssertEqual(h.name, "Sam")
        XCTAssertEqual(h.pattern.count, 7)
        XCTAssertTrue(h.pattern.allSatisfy { $0.count == 24 })
        XCTAssertEqual(h.pattern[0][8], 5)
        XCTAssertEqual(h.routines.first?.punctuality?.total, 8)
        XCTAssertFalse(h.isEmpty)
    }

    func testAnOlderOrThinnerAnswerStillReads() throws {
        let h = try JSONDecoder().decode(FamilyMoveHistory.self, from: Data(#"{"subject":"kit"}"#.utf8))
        XCTAssertEqual(h.name, "Kit")
        XCTAssertTrue(h.isEmpty)
        XCTAssertEqual(h.totals.trips, 0)
    }

    func testTheTrendSaysQuickerOrSlowerOnlyPastAMinute() throws {
        func route(_ recent: Double?, _ earlier: Double?) -> FamilyMoveHistory.Route {
            let json = """
            {"id":"r","from":"Home","to":"School","mode":"active","trips":8,"median":15,"low":12,"high":19,"departure":"08:24",
             "recentMedian":\(recent.map { "\($0)" } ?? "null"),"earlierMedian":\(earlier.map { "\($0)" } ?? "null"),"lastAt":null}
            """
            return try! JSONDecoder().decode(FamilyMoveHistory.Route.self, from: Data(json.utf8))
        }
        XCTAssertEqual(MoveHistoryWords.trend(route(13, 16))?.text, "Quicker lately: 16 → 13 min")
        XCTAssertEqual(MoveHistoryWords.trend(route(18, 16))?.quicker, false)
        XCTAssertNil(MoveHistoryWords.trend(route(15.5, 16)))
        XCTAssertNil(MoveHistoryWords.trend(route(nil, 16)))
    }

    func testTheFiguresReadAsSentences() {
        XCTAssertEqual(MoveHistoryWords.perWeek(4.24), "4.2 a week")
        XCTAssertEqual(MoveHistoryWords.perWeek(3), "3 a week")
        XCTAssertEqual(MoveHistoryWords.perWeek(0.4), "under 1 a week")
        XCTAssertEqual(MoveHistoryWords.duration(45), "45 min")
        XCTAssertEqual(MoveHistoryWords.duration(1860), "31 h")
        let p = try! JSONDecoder().decode(FamilyMoveHistory.Punctuality.self, from: Data(#"{"early":1,"onTime":9,"late":2}"#.utf8))
        XCTAssertEqual(MoveHistoryWords.punctuality(p), "On time 9 of 12 · 2 late · 1 early")
    }

    func testTheBusiestHourIsSaidForVoiceOver() {
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        grid[2][8] = 6
        XCTAssertEqual(FamilyMoveHistoryScreen.patternSummary(grid), "Most often leaves on Wednesdays around 08:00, 6 times.")
        XCTAssertEqual(FamilyMoveHistoryScreen.patternSummary(Array(repeating: Array(repeating: 0, count: 24), count: 7)),
                       "No departures in this stretch.")
    }
}
