import XCTest
@testable import SRAppleApp

/// The picture caches' arithmetic: decode sizes, memory cost, disk trimming,
/// cache names and the at-most-N fetch gate.
///
/// Foundation only: `scripts/home-check.sh` runs this file on Linux too.
final class SRImageLogicTests: XCTestCase {

    func testPixelsAreThePointSizeTimesTheScaleRoundedUp() {
        XCTAssertEqual(SRImageLogic.pixels(points: 140, scale: 3), 420)
        XCTAssertEqual(SRImageLogic.pixels(points: 32.4, scale: 2), 65)
        XCTAssertEqual(SRImageLogic.pixels(points: 0, scale: 3), 1)
        XCTAssertEqual(SRImageLogic.pixels(points: .nan, scale: 3), 1)
    }

    func testNoDecodeIsAskedForMoreThanTheCap() {
        XCTAssertEqual(SRImageLogic.pixels(points: 5000, scale: 3), SRImageLogic.maxPixels)
    }

    func testCostIsFourBytesAPixel() {
        XCTAssertEqual(SRImageLogic.decodedCost(width: 360, height: 270), 388_800)
        XCTAssertEqual(SRImageLogic.decodedCost(width: 0, height: 10), 0)
        XCTAssertEqual(SRImageLogic.decodedCost(width: Int.max, height: 2), Int.max, "an overflow is the most, never negative")
    }

    func testTrimDoesNothingWithinTheBudget() {
        let entries = [SRImageLogic.DiskEntry(name: "a", bytes: 50, modified: Date(timeIntervalSince1970: 1))]
        XCTAssertEqual(SRImageLogic.trimPlan(entries, budget: 100), [])
    }

    func testTrimRemovesTheOldestUntilEightyPercentOfTheBudget() {
        let entries = [
            SRImageLogic.DiskEntry(name: "new", bytes: 40, modified: Date(timeIntervalSince1970: 30)),
            SRImageLogic.DiskEntry(name: "old", bytes: 40, modified: Date(timeIntervalSince1970: 10)),
            SRImageLogic.DiskEntry(name: "mid", bytes: 40, modified: Date(timeIntervalSince1970: 20)),
        ]
        // 120 held, 100 allowed, down to 80: only the oldest goes.
        XCTAssertEqual(SRImageLogic.trimPlan(entries, budget: 100), ["old"])
        // Down to 40: the two oldest.
        XCTAssertEqual(SRImageLogic.trimPlan(entries, budget: 50), ["old", "mid"])
    }

    func testFileNamesKeepPlainIdsAndEscapeEverythingElse() {
        XCTAssertEqual(SRImageLogic.fileName(["6f1c-2a9e", "12-2026", "thumb"], ext: "jpg"), "6f1c-2a9e_12-2026_thumb.jpg")
        XCTAssertFalse(SRImageLogic.fileName(["../x", "v"], ext: "jpg").contains("/"))
        XCTAssertFalse(SRImageLogic.fileName(["..", "v"], ext: "jpg").hasPrefix("."))
        XCTAssertNotEqual(SRImageLogic.fileName(["a_b", "c"], ext: "jpg"), SRImageLogic.fileName(["a", "b_c"], ext: "jpg"),
                          "the separator is escaped inside a part, so two keys never share a file")
    }

    func testTheGateRunsUpToTheLimitAndQueuesTheRest() {
        var slots = SRFetchSlots(limit: 2)
        XCTAssertTrue(slots.request(1))
        XCTAssertTrue(slots.request(2))
        XCTAssertFalse(slots.request(3))
        XCTAssertFalse(slots.request(4))
        XCTAssertEqual(slots.waiting, [3, 4])
        XCTAssertEqual(slots.finish(), 3, "the first waiting takes the freed slot")
        XCTAssertEqual(slots.running, 2)
        XCTAssertEqual(slots.finish(), 4)
        XCTAssertNil(slots.finish())
        XCTAssertEqual(slots.running, 1)
    }

    func testAWithdrawnTicketNeverRuns() {
        var slots = SRFetchSlots(limit: 1)
        XCTAssertTrue(slots.request(1))
        XCTAssertFalse(slots.request(2))
        XCTAssertFalse(slots.request(3))
        XCTAssertTrue(slots.withdraw(2))
        XCTAssertFalse(slots.withdraw(2), "only once")
        XCTAssertFalse(slots.withdraw(1), "a running ticket is not waiting")
        XCTAssertEqual(slots.finish(), 3)
    }

    func testALimitBelowOneIsOne() {
        var slots = SRFetchSlots(limit: 0)
        XCTAssertTrue(slots.request(1))
        XCTAssertFalse(slots.request(2))
    }
}
