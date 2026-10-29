import XCTest
@testable import SRAppleApp

/// The quick room games' phone-side extras: personal bests, places, the
/// reaction rating, the clocks' shares and where a memory attempt went wrong.
final class QuickRoomLogicTests: XCTestCase {

    // MARK: - Records

    func testTheFirstCountedGameIsABest() {
        var record = QuickRoomRecord()
        let note = record.record(240, token: "g1", higherIsBetter: false)
        XCTAssertEqual(note, QuickRoomBestNote(previous: nil, best: 240, isNew: true))
        XCTAssertEqual(record.games, 1)
    }

    func testLowerWinsForATime() {
        var record = QuickRoomRecord()
        _ = record.record(240, token: "g1", higherIsBetter: false)
        XCTAssertFalse(record.record(260, token: "g2", higherIsBetter: false).isNew)
        let note = record.record(199, token: "g3", higherIsBetter: false)
        XCTAssertEqual(note, QuickRoomBestNote(previous: 240, best: 199, isNew: true))
        XCTAssertEqual(record.games, 3)
    }

    func testHigherWinsForPoints() {
        var record = QuickRoomRecord()
        _ = record.record(12, token: "g1", higherIsBetter: true)
        XCTAssertFalse(record.record(12, token: "g2", higherIsBetter: true).isNew, "a tie is not a new best")
        XCTAssertTrue(record.record(13, token: "g3", higherIsBetter: true).isNew)
        XCTAssertEqual(record.best, 13)
    }

    func testNothingToCountIsNeverABest() {
        var record = QuickRoomRecord()
        XCTAssertFalse(record.record(nil, token: "g1", higherIsBetter: false).isNew)
        XCTAssertFalse(record.record(0, token: "g2", higherIsBetter: true).isNew)
        XCTAssertNil(record.best)
        XCTAssertEqual(record.games, 2, "still a game played")
    }

    func testTheSameGameShownAgainAnswersTheSameWay() {
        var record = QuickRoomRecord()
        _ = record.record(300, token: "g1", higherIsBetter: false)
        let first = record.record(250, token: "g2", higherIsBetter: false)
        let again = record.record(250, token: "g2", higherIsBetter: false)
        XCTAssertEqual(first, again)
        XCTAssertTrue(again.isNew)
        XCTAssertEqual(record.games, 2, "not counted twice")
        let older = record.record(300, token: "g1", higherIsBetter: false)
        XCTAssertFalse(older.isNew)
        XCTAssertEqual(older.best, 250)
    }

    func testOnlyTheLastFewGamesAreRemembered() {
        var record = QuickRoomRecord()
        for i in 0..<(QuickRoomRecord.remembered + 5) {
            _ = record.record(i + 1, token: "g\(i)", higherIsBetter: true)
        }
        XCTAssertEqual(record.seen.count, QuickRoomRecord.remembered)
        XCTAssertEqual(record.seen.last, "g\(QuickRoomRecord.remembered + 4)")
    }

    func testTheStoreKeepsEachDifficultyApartAndSurvivesAReload() throws {
        let suite = "quickroom.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var store = QuickRoomBestStore.sprint
        store.defaults = defaults
        XCTAssertTrue(store.record(18, difficulty: "easy", token: "a").isNew)
        XCTAssertTrue(store.record(9, difficulty: "hard", token: "b").isNew)
        XCTAssertFalse(store.record(15, difficulty: "easy", token: "c").isNew)
        var again = QuickRoomBestStore.sprint
        again.defaults = defaults
        XCTAssertEqual(again.best(difficulty: "easy"), 18)
        XCTAssertEqual(again.best(difficulty: "hard"), 9)
        XCTAssertNil(again.best(difficulty: "medium"))
        XCTAssertEqual(again.gamesPlayed(), 3)
    }

    func testEachGameHasItsOwnKey() {
        XCTAssertTrue(QuickRoomBestStore.tapDuel.key.hasPrefix("tapduel."))
        XCTAssertTrue(QuickRoomBestStore.sprint.key.hasPrefix("sprint."))
        XCTAssertTrue(QuickRoomBestStore.memory.key.hasPrefix("memory."))
        XCTAssertFalse(QuickRoomBestStore.tapDuel.higherIsBetter)
        XCTAssertTrue(QuickRoomBestStore.sprint.higherIsBetter)
        XCTAssertTrue(QuickRoomBestStore.memory.higherIsBetter)
    }

    // MARK: - Places

    func testOrdinals() {
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111].map(QuickRoomPlace.ordinal),
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd", "101st", "111th"])
    }

    func testTiesShareAPlace() {
        let scores: [(id: String, score: Int)] = [("a", 9), ("b", 9), ("c", 6)]
        XCTAssertEqual(QuickRoomPlace.place(of: "a", scores: scores), 1)
        XCTAssertEqual(QuickRoomPlace.place(of: "b", scores: scores), 1)
        XCTAssertEqual(QuickRoomPlace.place(of: "c", scores: scores), 3)
        XCTAssertNil(QuickRoomPlace.place(of: "z", scores: scores))
    }

    // MARK: - Tap Duel

    func testReactionWords() {
        XCTAssertEqual(TapDuelRating.label(ms: 80), "Too quick to count")
        XCTAssertEqual(TapDuelRating.label(ms: 180), "Lightning")
        XCTAssertEqual(TapDuelRating.label(ms: 230), "Rapid")
        XCTAssertEqual(TapDuelRating.label(ms: 290), "Sharp")
        XCTAssertEqual(TapDuelRating.label(ms: 350), "Quick")
        XCTAssertEqual(TapDuelRating.label(ms: 500), "Steady")
        XCTAssertEqual(TapDuelRating.label(ms: 900), "Sleepy")
    }

    func testTheMeterIsClamped() {
        XCTAssertEqual(TapDuelRating.meter(ms: 50), 0)
        XCTAssertEqual(TapDuelRating.meter(ms: 350), 0.5, accuracy: 0.0001)
        XCTAssertEqual(TapDuelRating.meter(ms: 2000), 1)
    }

    func testTheTimeAxis() {
        XCTAssertEqual(TapDuelRating.axisMs(times: []), 400)
        XCTAssertEqual(TapDuelRating.axisMs(times: [180, 220]), 400, "never shorter than 400")
        XCTAssertEqual(TapDuelRating.axisMs(times: [210, 520]), 600)
        XCTAssertEqual(TapDuelRating.share(ms: 300, axis: 600), 0.5, accuracy: 0.0001)
        XCTAssertEqual(TapDuelRating.share(ms: 900, axis: 600), 1)
        XCTAssertEqual(TapDuelRating.share(ms: 10, axis: 0), 0)
    }

    // MARK: - Quick Maths Sprint

    func testTheClockShare() {
        XCTAssertEqual(SprintGauge.timeShare(msLeft: 30_000, totalMs: 60_000), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SprintGauge.timeShare(msLeft: -5, totalMs: 60_000), 0)
        XCTAssertEqual(SprintGauge.timeShare(msLeft: 90_000, totalMs: 60_000), 1)
        XCTAssertEqual(SprintGauge.timeShare(msLeft: 10, totalMs: 0), 1, "an unknown limit reads full")
    }

    func testAccuracy() {
        XCTAssertNil(SprintGauge.accuracy(correct: 0, misses: 0))
        XCTAssertEqual(SprintGauge.accuracy(correct: 8, misses: 1), 89)
        XCTAssertEqual(SprintGauge.accuracy(correct: 0, misses: 3), 0)
        XCTAssertEqual(SprintGauge.accuracy(correct: 5, misses: 0), 100)
    }

    func testStreakPips() {
        XCTAssertEqual(SprintGauge.lit(streak: 0, every: 5), 0)
        XCTAssertEqual(SprintGauge.lit(streak: 3, every: 5), 3)
        XCTAssertEqual(SprintGauge.lit(streak: 5, every: 5), 5, "on a bonus, all lit")
        XCTAssertEqual(SprintGauge.lit(streak: 7, every: 5), 2)
        XCTAssertEqual(SprintGauge.lit(streak: 4, every: 0), 0)
    }

    // MARK: - Sequence Memory

    func testMarksAndTheFirstMistake() {
        XCTAssertEqual(SequenceCompare.marks(sequence: [2, 0, 3], taps: [2, 0, 3]), [true, true, true])
        XCTAssertNil(SequenceCompare.firstMistake(sequence: [2, 0, 3], taps: [2, 0, 3]))
        XCTAssertEqual(SequenceCompare.marks(sequence: [2, 0, 3], taps: [2, 1, 3]), [true, false, true])
        XCTAssertEqual(SequenceCompare.firstMistake(sequence: [2, 0, 3], taps: [2, 1, 3]), 1)
        XCTAssertEqual(SequenceCompare.marks(sequence: [2], taps: [2, 2]), [true, false], "past the end is wrong")
        XCTAssertEqual(SequenceCompare.marks(sequence: [2, 0], taps: []), [])
    }

    func testTheWindowShare() {
        XCTAssertEqual(SequenceCompare.windowShare(msLeft: 3000, windowMs: 6000), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SequenceCompare.windowShare(msLeft: -1, windowMs: 6000), 0)
        XCTAssertEqual(SequenceCompare.windowShare(msLeft: 100, windowMs: 0), 0)
    }
}
