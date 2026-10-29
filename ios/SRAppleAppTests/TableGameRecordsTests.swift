import XCTest
@testable import SRAppleApp

/// The table games' keepsakes: a record that counts each finished game once,
/// the turn clock's figures and nudges, and the celebration's sparks.
final class TableGameRecordsTests: XCTestCase {

    // MARK: - Records

    func testAGameCountsOnceAndStreaksBreakOnALoss() {
        var record = TableGameRecord()
        XCTAssertTrue(record.record(key: "g1|1", won: true, score: nil))
        XCTAssertFalse(record.record(key: "g1|1", won: true, score: nil), "the same finish seen twice")
        XCTAssertTrue(record.record(key: "g1|2", won: true, score: nil))
        XCTAssertEqual(record.played, 2)
        XCTAssertEqual(record.wins, 2)
        XCTAssertEqual(record.streak, 2)
        XCTAssertTrue(record.record(key: "g2|1", won: false, score: nil))
        XCTAssertEqual(record.streak, 0)
        XCTAssertEqual(record.bestStreak, 2)
        XCTAssertEqual(record.played, 3)
        XCTAssertFalse(record.record(key: "", won: true, score: 3), "no key, no count")
        XCTAssertEqual(record.played, 3)
    }

    func testTheFirstScoreIsTheBestButNotANewBest() {
        var record = TableGameRecord()
        record.record(key: "a", won: false, score: 31)
        XCTAssertEqual(record.best, 31)
        XCTAssertTrue(record.isBest("a"))
        XCTAssertFalse(record.beatBest("a"), "a first score has nothing to beat")
        record.record(key: "b", won: false, score: 31)
        XCTAssertTrue(record.isBest("a"), "a tie keeps the older best")
        XCTAssertFalse(record.isBest("b"))
        record.record(key: "c", won: true, score: 40)
        XCTAssertTrue(record.beatBest("c"))
        XCTAssertEqual(record.bestBefore, 31)
        XCTAssertEqual(record.best, 40)
        record.record(key: "d", won: false, score: 12)
        XCTAssertEqual(record.best, 40)
        XCTAssertTrue(record.isBest("c"))
    }

    func testOnlyTheLatestGamesAreRemembered() {
        var record = TableGameRecord()
        for i in 0..<(TableGameRecord.remembered + 5) { record.record(key: "k\(i)", won: false, score: nil) }
        XCTAssertEqual(record.counted.count, TableGameRecord.remembered)
        XCTAssertEqual(record.counted.last, "k\(TableGameRecord.remembered + 4)")
        XCTAssertEqual(record.played, TableGameRecord.remembered + 5)
    }

    func testABookKeepsVariantsApart() {
        var book = TableGameBook()
        book.note(variant: "fireworks-25", key: "a", won: false, score: 20)
        book.note(variant: "fireworks-30", key: "b", won: false, score: 22)
        XCTAssertEqual(book.record("fireworks-25").best, 20)
        XCTAssertEqual(book.record("fireworks-30").best, 22)
        XCTAssertEqual(book.record("nothing").played, 0)
    }

    func testTheStoreSavesUnderTheGamesOwnKeyAndNotInTheDemo() throws {
        let suite = "table-game-records-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = TableGameBestStore(gameId: "pass-the-plate", defaults: defaults)
        XCTAssertEqual(store.key, "pass-the-plate.bests.v1")
        let first = store.note(variant: "pass-the-plate", key: "g|1", won: true, score: 77)
        XCTAssertEqual(first.best, 77)
        XCTAssertEqual(store.load().record("pass-the-plate").played, 1)
        let again = store.note(variant: "pass-the-plate", key: "g|1", won: true, score: 77)
        XCTAssertEqual(again.played, 1, "reopening a finish does not count it twice")

        let demo = TableGameBestStore(gameId: "liars-dice", defaults: defaults, persists: false)
        let shown = demo.note(variant: "liars-dice", key: "d|1", won: true, score: nil)
        XCTAssertEqual(shown.wins, 1, "the demo still shows a record")
        XCTAssertNil(defaults.data(forKey: demo.key), "but never keeps one")
        defaults.removePersistentDomain(forName: suite)
    }

    func testAFinishedGamesKeyIsTheRoomAndItsStart() {
        XCTAssertEqual(TableGameKey.finished(roomId: "g_x", startedAt: 1_790_000_000_000), "g_x|1790000000000")
        XCTAssertEqual(TableGameKey.finished(roomId: "g_x", startedAt: nil), "g_x|0")
        XCTAssertEqual(TableGameKey.finished(roomId: "", startedAt: 5), "")
    }

    // MARK: - The clock

    func testSecondsLeftRoundUp() {
        XCTAssertEqual(TableClock.secondsLeft(endsAt: 10_000, now: 0), 10)
        XCTAssertEqual(TableClock.secondsLeft(endsAt: 10_000, now: 9_100), 1)
        XCTAssertEqual(TableClock.secondsLeft(endsAt: 10_000, now: 10_500), 0)
        XCTAssertNil(TableClock.secondsLeft(endsAt: nil, now: 1))
        XCTAssertNil(TableClock.secondsLeft(endsAt: 1, now: nil))
        XCTAssertEqual(TableClock.fraction(endsAt: 15_000, turnMs: 30_000, now: 0), 0.5, accuracy: 0.0001)
        XCTAssertEqual(TableClock.fraction(endsAt: nil, turnMs: 30_000, now: 0), 1)
        XCTAssertEqual(TableClock.fraction(endsAt: 0, turnMs: 30_000, now: 5_000), 0)
    }

    func testUrgencyWarmsAsTheClockRunsDown() {
        XCTAssertEqual(TableClock.urgency(fraction: 0.9, seconds: 40), .calm)
        XCTAssertEqual(TableClock.urgency(fraction: 0.3, seconds: 20), .hurry)
        XCTAssertEqual(TableClock.urgency(fraction: 0.5, seconds: 9), .hurry)
        XCTAssertEqual(TableClock.urgency(fraction: 0.5, seconds: 4), .last)
        XCTAssertEqual(TableClock.urgency(fraction: 0.1, seconds: nil), .last)
    }

    func testNudgesFireOnceAtTenAndFive() {
        XCTAssertTrue(TableClock.nudge(from: 11, to: 10))
        XCTAssertFalse(TableClock.nudge(from: 10, to: 9))
        XCTAssertTrue(TableClock.nudge(from: 7, to: 5))
        XCTAssertTrue(TableClock.nudge(from: 12, to: 4), "a skipped tick still nudges")
        XCTAssertFalse(TableClock.nudge(from: 3, to: 45), "a new turn is not a nudge")
        XCTAssertFalse(TableClock.nudge(from: nil, to: 5))
        XCTAssertFalse(TableClock.nudge(from: 30, to: 29))
    }

    // MARK: - Sparks

    func testAShowSpreadsItsBurstsAndEndsOnTime() {
        let show = TableSparks.show(count: 5, duration: 4, seed: 7)
        XCTAssertEqual(show.count, 5)
        XCTAssertEqual(show.first?.start, 0)
        XCTAssertEqual(show.last?.start ?? 0, 4 - TableSparks.life, accuracy: 0.0001)
        for burst in show {
            XCTAssertTrue((0...1).contains(burst.x))
            XCTAssertTrue((0...1).contains(burst.y))
        }
        XCTAssertEqual(show, TableSparks.show(count: 5, duration: 4, seed: 7), "the same seed, the same show")
        XCTAssertTrue(TableSparks.show(count: 0, duration: 4, seed: 7).isEmpty)
    }

    func testASparkFliesOutAndFades() throws {
        let burst = TableSparks.Burst(x: 0.5, y: 0.5, start: 1, hue: 0, reach: 0.3)
        XCTAssertNil(TableSparks.spark(0, of: 12, burst: burst, at: 0.5), "before it goes off")
        XCTAssertNil(TableSparks.spark(0, of: 12, burst: burst, at: 1 + TableSparks.life), "once it has faded")
        let start = try XCTUnwrap(TableSparks.spark(3, of: 12, burst: burst, at: 1))
        XCTAssertEqual(start.alpha, 1, accuracy: 0.0001)
        XCTAssertEqual(hypot(start.dx, start.dy), 0, accuracy: 0.0001)
        let later = try XCTUnwrap(TableSparks.spark(3, of: 12, burst: burst, at: 1.7))
        XCTAssertLessThan(later.alpha, start.alpha)
        XCTAssertGreaterThan(hypot(later.dx, later.dy), 0.05)
        XCTAssertNil(TableSparks.spark(0, of: 0, burst: burst, at: 1.2))
    }

    func testUnitIsAlwaysBetweenZeroAndOne() {
        for a in -20..<20 {
            for b in 0..<20 {
                let u = TableSparks.unit(a, b)
                XCTAssertGreaterThanOrEqual(u, 0)
                XCTAssertLessThan(u, 1)
            }
        }
    }
}
