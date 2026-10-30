import XCTest
@testable import SRAppleApp

/// The Play nearby games' own bests on this phone (fastest draw, best score),
/// the countdown ring's arithmetic, and the finite timeline that stops once
/// a clock runs out.
final class OfflineNearbyPlayBestsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "NearbyPlayBestsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testAnythingBeatsNothing() {
        XCTAssertTrue(NearbyPlayBestMath.isBetter(500, than: nil, rule: .lower))
        XCTAssertTrue(NearbyPlayBestMath.isBetter(0, than: nil, rule: .higher))
    }

    func testLowerIsBetterForTimes() {
        XCTAssertTrue(NearbyPlayBestMath.isBetter(210, than: 250, rule: .lower))
        XCTAssertFalse(NearbyPlayBestMath.isBetter(250, than: 250, rule: .lower), "a tie is not a new best")
        XCTAssertFalse(NearbyPlayBestMath.isBetter(300, than: 250, rule: .lower))
    }

    func testHigherIsBetterForScores() {
        XCTAssertTrue(NearbyPlayBestMath.isBetter(12, than: 11, rule: .higher))
        XCTAssertFalse(NearbyPlayBestMath.isBetter(11, than: 11, rule: .higher))
        XCTAssertFalse(NearbyPlayBestMath.isBetter(-2, than: 0, rule: .higher))
    }

    func testMergeKeepsTheBestAndCountsEveryPlay() {
        var record: NearbyPlayBest?
        var outcomes: [NearbyPlayBestOutcome] = []
        for value in [300, 280, 320, 280] {
            let merged = NearbyPlayBestMath.merge(record, value: value, rule: .lower)
            record = merged.record
            outcomes.append(merged.outcome)
        }
        XCTAssertEqual(record, NearbyPlayBest(value: 280, plays: 4))
        XCTAssertEqual(outcomes.map(\.improved), [true, true, false, false])
        XCTAssertEqual(outcomes.map(\.previous), [nil, 300, 280, 280])
        XCTAssertEqual(outcomes.map(\.best), [300, 280, 280, 280])
    }

    func testOnlyABeatenOldBestIsAFanfare() {
        let first = NearbyPlayBestMath.merge(nil, value: 10, rule: .higher).outcome
        XCTAssertTrue(first.improved)
        XCTAssertFalse(first.beatAnOldBest, "the first game is a best, but there was nothing to beat")
        let second = NearbyPlayBestMath.merge(NearbyPlayBest(value: 10, plays: 1), value: 11, rule: .higher).outcome
        XCTAssertTrue(second.beatAnOldBest)
    }

    func testKeysStartWithTheGameId() {
        XCTAssertEqual(NearbyPlayBestMath.key(for: "quick-draw"), "quick-draw.nearby-best.v1")
        XCTAssertNotEqual(NearbyPlayBestMath.key(for: "snap"), NearbyPlayBestMath.key(for: "sprint"))
    }

    func testStoreRoundTripsPerGame() {
        let store = NearbyPlayBestStore(defaults: freshDefaults())
        XCTAssertNil(store.best("whack-a-mole"))
        XCTAssertTrue(store.record("whack-a-mole", value: 14, rule: .higher).improved)
        XCTAssertFalse(store.record("whack-a-mole", value: 9, rule: .higher).improved)
        store.record("quick-draw", value: 240, rule: .lower)
        XCTAssertEqual(store.best("whack-a-mole"), NearbyPlayBest(value: 14, plays: 2))
        XCTAssertEqual(store.best("quick-draw"), NearbyPlayBest(value: 240, plays: 1))
    }

    func testFormatting() {
        XCTAssertEqual(NearbyPlayBestMath.milliseconds(231), "231 ms")
        XCTAssertEqual(NearbyPlayBestMath.milliseconds(-5), "0 ms")
        XCTAssertEqual(NearbyPlayBestMath.seconds(fromMs: 4_820), "4.8 s")
        XCTAssertEqual(NearbyPlayBestMath.seconds(fromMs: 12_960), "13.0 s")
    }

    // MARK: - Clocks

    func testRingFractionIsClamped() {
        XCTAssertEqual(NearbyPlayClockMath.fraction(left: 15, total: 30), 0.5, accuracy: 1e-9)
        XCTAssertEqual(NearbyPlayClockMath.fraction(left: 45, total: 30), 1, "another build's longer window reads full")
        XCTAssertEqual(NearbyPlayClockMath.fraction(left: -1, total: 30), 0)
        XCTAssertEqual(NearbyPlayClockMath.fraction(left: 5, total: 0), 0)
        XCTAssertEqual(NearbyPlayClockMath.fraction(left: .nan, total: 30), 0)
    }

    func testShownSecondsRoundUp() {
        XCTAssertEqual(NearbyPlayClockMath.shownSeconds(left: 0.2), 1)
        XCTAssertEqual(NearbyPlayClockMath.shownSeconds(left: 3), 3)
        XCTAssertEqual(NearbyPlayClockMath.shownSeconds(left: 0), 0)
        XCTAssertEqual(NearbyPlayClockMath.shownSeconds(left: -2), 0)
    }

    func testFiniteTicksEndAtTheEnd() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let end = start.addingTimeInterval(1)
        let ticks = NearbyPlayClockMath.ticks(from: start, to: end, step: 0.25)
        XCTAssertEqual(ticks.count, 5)
        XCTAssertEqual(ticks.first, start)
        XCTAssertEqual(ticks.last, end)
        XCTAssertEqual(ticks, ticks.sorted(), "a timeline's instants run forwards")
    }

    func testFiniteTicksForAClockAlreadyOut() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        XCTAssertEqual(NearbyPlayClockMath.ticks(from: start, to: start.addingTimeInterval(-3), step: 0.1), [start])
        XCTAssertEqual(NearbyPlayClockMath.ticks(from: start, to: start.addingTimeInterval(5), step: 0), [start])
    }

    func testALongClockRunsToItsEnd() {
        // Snap's three-minute match clock: every frame up to the end, and
        // the end itself, with no cap cutting the ring off early.
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(180)
        var count = 0
        var last: Date?
        for t in NearbyPlayTicks(from: start, to: end, step: NearbyPlayClockMath.ringStep(total: 180)) {
            count += 1
            last = t
        }
        XCTAssertEqual(last, end)
        XCTAssertEqual(count, 721)
    }

    func testRingStepFollowsTheWindow() {
        XCTAssertEqual(NearbyPlayClockMath.ringStep(total: 6), 1.0 / 30.0, accuracy: 1e-9)
        XCTAssertEqual(NearbyPlayClockMath.ringStep(total: 60), 0.1, accuracy: 1e-9)
        XCTAssertEqual(NearbyPlayClockMath.ringStep(total: 180), 0.25, accuracy: 1e-9)
        XCTAssertEqual(NearbyPlayClockMath.ringStep(total: 0), 1.0 / 30.0, accuracy: 1e-9)
        XCTAssertEqual(NearbyPlayClockMath.ringStep(total: .nan), 1.0 / 30.0, accuracy: 1e-9)
    }

    func testFiniteTicksAreCapped() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let ticks = NearbyPlayClockMath.ticks(from: start, to: start.addingTimeInterval(10_000), step: 0.01, limit: 100)
        XCTAssertEqual(ticks.count, 101, "the cap, then the end")
    }
}
