import XCTest
@testable import SRAppleApp

/// Manhunt's play-screen sums: where the last ping is from me, how much of a
/// clock is left, the line that says what to do, and the record kept on this
/// phone (counted once per game, however often the results page is shown).
final class ManhuntPlayKitTests: XCTestCase {
    // MARK: Distance and direction

    func testMetresMatchesAKnownDistance() {
        // One thousandth of a degree of latitude is about 111 m.
        let m = ManhuntPlayKit.metres(fromLat: 51.5, fromLng: -0.12, toLat: 51.501, toLng: -0.12)
        XCTAssertEqual(m, 111.2, accuracy: 0.5)
        XCTAssertEqual(ManhuntPlayKit.metres(fromLat: 51.5, fromLng: -0.12, toLat: 51.5, toLng: -0.12), 0, accuracy: 0.001)
        XCTAssertTrue(ManhuntPlayKit.metres(fromLat: .nan, fromLng: 0, toLat: 0, toLng: 0).isNaN)
    }

    func testBearingPointsTheRightWay() {
        XCTAssertEqual(ManhuntPlayKit.bearing(fromLat: 51.5, fromLng: 0, toLat: 51.51, toLng: 0), 0, accuracy: 0.5)
        XCTAssertEqual(ManhuntPlayKit.bearing(fromLat: 51.5, fromLng: 0, toLat: 51.5, toLng: 0.01), 90, accuracy: 0.5)
        XCTAssertEqual(ManhuntPlayKit.bearing(fromLat: 51.5, fromLng: 0, toLat: 51.49, toLng: 0), 180, accuracy: 0.5)
        XCTAssertEqual(ManhuntPlayKit.bearing(fromLat: 51.5, fromLng: 0, toLat: 51.5, toLng: -0.01), 270, accuracy: 0.5)
        // The same point has no direction: north, not NaN.
        XCTAssertEqual(ManhuntPlayKit.bearing(fromLat: 51.5, fromLng: 0, toLat: 51.5, toLng: 0), 0)
    }

    func testCompassWordsRoundToTheNearestPoint() {
        XCTAssertEqual(ManhuntPlayKit.compass(0), "north")
        XCTAssertEqual(ManhuntPlayKit.compass(359), "north")
        XCTAssertEqual(ManhuntPlayKit.compass(44), "north-east")
        XCTAssertEqual(ManhuntPlayKit.compass(100), "east")
        XCTAssertEqual(ManhuntPlayKit.compass(200), "south")
        XCTAssertEqual(ManhuntPlayKit.compass(225), "south-west")
        XCTAssertEqual(ManhuntPlayKit.compass(-90), "west")
        XCTAssertEqual(ManhuntPlayKit.compass(.nan), "")
    }

    func testDistanceRoundsToTensUnderAKilometre() {
        XCTAssertEqual(ManhuntPlayKit.distance(7.4), "7 m")
        XCTAssertEqual(ManhuntPlayKit.distance(25), "30 m")
        XCTAssertEqual(ManhuntPlayKit.distance(143), "140 m")
        XCTAssertEqual(ManhuntPlayKit.distance(994), "990 m")
        XCTAssertEqual(ManhuntPlayKit.distance(1_000), "1 km")
        XCTAssertEqual(ManhuntPlayKit.distance(1_240), "1.2 km")
        XCTAssertEqual(ManhuntPlayKit.distance(-1), "–")
        XCTAssertEqual(ManhuntPlayKit.distance(.infinity), "–")
    }

    func testReachIsToTheMetre() {
        XCTAssertEqual(ManhuntPlayKit.reach(25), "25 m")
        XCTAssertEqual(ManhuntPlayKit.reach(24.6), "25 m")
        XCTAssertEqual(ManhuntPlayKit.reach(1_500), "1.5 km")
        XCTAssertEqual(ManhuntPlayKit.reach(.nan), "–")
    }

    func testWhereaboutsSaysRightByYouWhenClose() {
        XCTAssertEqual(ManhuntPlayKit.whereabouts(metres: 9, bearing: 90), "right by you")
        XCTAssertEqual(ManhuntPlayKit.whereabouts(metres: 140, bearing: 45), "140 m north-east")
        XCTAssertEqual(ManhuntPlayKit.whereabouts(metres: .nan, bearing: 45), "")
    }

    // MARK: Clocks

    func testFractionIsClampedAndSafe() {
        XCTAssertEqual(ManhuntPlayKit.fraction(left: 90_000, total: 180_000), 0.5)
        XCTAssertEqual(ManhuntPlayKit.fraction(left: 400_000, total: 180_000), 1)
        XCTAssertEqual(ManhuntPlayKit.fraction(left: -5, total: 180_000), 0)
        XCTAssertEqual(ManhuntPlayKit.fraction(left: nil, total: 180_000), 0)
        XCTAssertEqual(ManhuntPlayKit.fraction(left: 10, total: 0), 0)
    }

    func testPingSoonIsTheLastTenSeconds() {
        XCTAssertFalse(ManhuntPlayKit.pingSoon(nil))
        XCTAssertFalse(ManhuntPlayKit.pingSoon(0))
        XCTAssertTrue(ManhuntPlayKit.pingSoon(1))
        XCTAssertTrue(ManhuntPlayKit.pingSoon(10_000))
        XCTAssertFalse(ManhuntPlayKit.pingSoon(10_001))
    }

    func testSecondsRoundUp() {
        XCTAssertEqual(ManhuntPlayKit.secondsUp(4_100), 5)
        XCTAssertEqual(ManhuntPlayKit.secondsUp(4_000), 4)
        XCTAssertEqual(ManhuntPlayKit.secondsUp(0), 0)
        XCTAssertEqual(ManhuntPlayKit.secondsUp(nil), 0)
    }

    // MARK: What to do now

    func testNowLineFollowsTheMoment() {
        func line(headstart: Bool = false, _ seat: ManhuntPlayKit.Seat, live: Bool = false, byMe: Bool = false,
                  onMe: Bool = false, lead: String? = nil) -> String {
            ManhuntPlayKit.nowLine(headstart: headstart, seat: seat, live: live, claimByMe: byMe, claimOnMe: onMe,
                                   runnerName: "Sam", lead: lead, catchM: 25)
        }
        XCTAssertTrue(line(headstart: true, .runner).hasPrefix("Go!"))
        XCTAssertTrue(line(headstart: true, .hunter).contains("fair start"))
        XCTAssertTrue(line(.runner, onMe: true).contains("own up"))
        XCTAssertTrue(line(.hunter, byMe: true).contains("Waiting for Sam"))
        XCTAssertTrue(line(.runner, live: true).contains("outside the circle"))
        XCTAssertTrue(line(.hunter, live: true).contains("right now"))
        XCTAssertEqual(line(.hunter, lead: "140 m north-east"),
                       "Sam was last seen 140 m north-east. Get within 25 m, then tap Catch.")
        XCTAssertTrue(line(.hunter).contains("within 25 m"))
        XCTAssertTrue(line(.hunter).contains("first ping"))
        XCTAssertEqual(line(.watching), "You're watching this one.")
    }

    // MARK: The record

    func testRecordCountsEachGameOnce() {
        var record = ManhuntRecord()
        let first = record.record(token: "g1-1", runner: true, won: true, madeCatch: false)
        XCTAssertEqual(first.headline, "Your first escape!")
        XCTAssertEqual(record.games, 1)
        XCTAssertEqual(record.escapes, 1)
        // The same page again: nothing more counted, the same words.
        let again = record.record(token: "g1-1", runner: true, won: true, madeCatch: false)
        XCTAssertEqual(again.headline, "Your first escape!")
        XCTAssertEqual(record.games, 1)
    }

    func testRecordCountsCatchesTeamWinsAndStreaks() {
        var record = ManhuntRecord()
        _ = record.record(token: "a", runner: false, won: true, madeCatch: false)
        let catchNote = record.record(token: "b", runner: false, won: true, madeCatch: true)
        XCTAssertEqual(catchNote.headline, "Your first catch!")
        let streak = record.record(token: "c", runner: false, won: true, madeCatch: false)
        XCTAssertEqual(streak.headline, "New best: 3 wins in a row")
        XCTAssertEqual(record.teamWins, 3)
        XCTAssertEqual(record.catches, 1)
        XCTAssertEqual(record.bestStreak, 3)
        _ = record.record(token: "d", runner: true, won: false, madeCatch: false)
        XCTAssertEqual(record.streak, 0)
        XCTAssertEqual(record.bestStreak, 3)
        XCTAssertEqual(record.runs, 1)
        XCTAssertEqual(record.wins, 3)
        XCTAssertEqual(record.games, 4)
    }

    func testRecordForgetsOldTokensButKeepsCounts() {
        var record = ManhuntRecord()
        for i in 0..<(ManhuntRecord.remembered + 5) {
            _ = record.record(token: "t\(i)", runner: false, won: false, madeCatch: false)
        }
        XCTAssertEqual(record.seen.count, ManhuntRecord.remembered)
        XCTAssertEqual(record.games, ManhuntRecord.remembered + 5)
    }

    func testStoreKeepsTheRecordUnderTheGamesKey() throws {
        let suite = "manhunt-record-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ManhuntRecordStore(defaults: defaults)
        XCTAssertTrue(store.key.hasPrefix("manhunt"))
        XCTAssertEqual(store.load(), ManhuntRecord())
        store.record(token: "x", runner: false, won: true, madeCatch: true)
        store.record(token: "x", runner: false, won: true, madeCatch: true)
        let back = store.load()
        XCTAssertEqual(back.games, 1)
        XCTAssertEqual(back.catches, 1)
    }
}
