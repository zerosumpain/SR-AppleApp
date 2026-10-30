import XCTest
@testable import SRAppleApp

/// The table art's arithmetic (`PlayTableMath`): timers, chips, fans, piles,
/// the boxes beside a line, a disc's fall and a rolling letter die.
final class PlayTableMathTests: XCTestCase {
    // MARK: - Clocks

    func testDrainRunsFromOneToZeroAndClamps() {
        XCTAssertEqual(PlayTableMath.drainFraction(secondsLeft: 30, total: 30), 1)
        XCTAssertEqual(PlayTableMath.drainFraction(secondsLeft: 15, total: 30), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PlayTableMath.drainFraction(secondsLeft: 0, total: 30), 0)
        XCTAssertEqual(PlayTableMath.drainFraction(secondsLeft: -4, total: 30), 0)
        // A clock a touch ahead of the host must not overfill the ring.
        XCTAssertEqual(PlayTableMath.drainFraction(secondsLeft: 31, total: 30), 1)
        XCTAssertEqual(PlayTableMath.drainFraction(secondsLeft: 5, total: 0), 0)
        XCTAssertEqual(PlayTableMath.drainFraction(secondsLeft: .infinity, total: 30), 0)
    }

    func testUrgencyFollowsTheLengthOfTheTimer() {
        // A 30 s turn: urgent in the last 5, hurrying in the last 12.
        XCTAssertEqual(PlayTableMath.urgency(secondsLeft: 20, total: 30), .calm)
        XCTAssertEqual(PlayTableMath.urgency(secondsLeft: 12, total: 30), .hurry)
        XCTAssertEqual(PlayTableMath.urgency(secondsLeft: 5, total: 30), .urgent)
        // Cheat's 5 s challenge: only the last second is urgent.
        XCTAssertEqual(PlayTableMath.urgency(secondsLeft: 4, total: 5), .calm)
        XCTAssertEqual(PlayTableMath.urgency(secondsLeft: 2, total: 5), .hurry)
        XCTAssertEqual(PlayTableMath.urgency(secondsLeft: 1, total: 5), .urgent)
        XCTAssertEqual(PlayTableMath.urgency(secondsLeft: 1, total: 0), .calm)
    }

    func testShownSecondsRoundUpAndStopAtZero() {
        XCTAssertEqual(PlayTableMath.shownSeconds(0.2), 1)
        XCTAssertEqual(PlayTableMath.shownSeconds(4.0), 4)
        XCTAssertEqual(PlayTableMath.shownSeconds(4.01), 5)
        XCTAssertEqual(PlayTableMath.shownSeconds(0), 0)
        XCTAssertEqual(PlayTableMath.shownSeconds(-3), 0)
        XCTAssertEqual(PlayTableMath.shownSeconds(.nan), 0)
    }

    // MARK: - Chips

    func testChipsMakeTheStakeWithTheFewestChips() {
        let chips = PlayTableMath.chips(for: 37)
        XCTAssertEqual(chips, [PlayTableMath.Chip(value: 25, count: 1),
                               PlayTableMath.Chip(value: 10, count: 1),
                               PlayTableMath.Chip(value: 1, count: 2)])
        XCTAssertEqual(chips.reduce(0) { $0 + $1.value * $1.count }, 37)
        XCTAssertEqual(PlayTableMath.chips(for: 100), [PlayTableMath.Chip(value: 100, count: 1)])
        XCTAssertEqual(PlayTableMath.chips(for: 0), [])
        XCTAssertEqual(PlayTableMath.chips(for: -5), [])
    }

    func testTallStacksAreCappedForTheArt() {
        let chips = PlayTableMath.chips(for: 900, maxPerStack: 4)
        XCTAssertEqual(chips, [PlayTableMath.Chip(value: 100, count: 4)])
        XCTAssertEqual(PlayTableMath.chips(for: 3, maxPerStack: 0), [PlayTableMath.Chip(value: 1, count: 1)])
    }

    // MARK: - Fans and piles

    func testFanIsCentredAndSpansTheSpread() {
        XCTAssertEqual(PlayTableMath.fanAngle(index: 0, count: 1, spread: 40), 0)
        XCTAssertEqual(PlayTableMath.fanAngle(index: 0, count: 5, spread: 40), -20, accuracy: 1e-9)
        XCTAssertEqual(PlayTableMath.fanAngle(index: 2, count: 5, spread: 40), 0, accuracy: 1e-9)
        XCTAssertEqual(PlayTableMath.fanAngle(index: 4, count: 5, spread: 40), 20, accuracy: 1e-9)
        // Out of range indices clamp to the ends.
        XCTAssertEqual(PlayTableMath.fanAngle(index: 9, count: 5, spread: 40), 20, accuracy: 1e-9)
    }

    func testFanArchesInTheMiddle() {
        XCTAssertEqual(PlayTableMath.fanLift(index: 0, count: 5), 0, accuracy: 1e-9)
        XCTAssertEqual(PlayTableMath.fanLift(index: 2, count: 5), 1, accuracy: 1e-9)
        XCTAssertEqual(PlayTableMath.fanLift(index: 4, count: 5), 0, accuracy: 1e-9)
        XCTAssertEqual(PlayTableMath.fanLift(index: 0, count: 2), 0)
    }

    func testTiltIsFixedPerSeedAndInRange() {
        for seed in -20...200 {
            let a = PlayTableMath.tilt(seed, range: 6)
            XCTAssertEqual(a, PlayTableMath.tilt(seed, range: 6))
            XCTAssertLessThanOrEqual(abs(a), 6)
        }
        let spread = Set((0..<20).map { Int(PlayTableMath.tilt($0, range: 6) * 10) })
        XCTAssertGreaterThan(spread.count, 10, "neighbouring seeds should not all turn alike")
    }

    func testPileAndStaggerStayBounded() {
        XCTAssertEqual(PlayTableMath.pileShown(0), 0)
        XCTAssertEqual(PlayTableMath.pileShown(3), 3)
        XCTAssertEqual(PlayTableMath.pileShown(40), 5)
        XCTAssertEqual(PlayTableMath.pileShown(-2), 0)
        XCTAssertEqual(PlayTableMath.stagger(index: 0, step: 0.05, cap: 0.3), 0)
        XCTAssertEqual(PlayTableMath.stagger(index: 3, step: 0.05, cap: 0.3), 0.15, accuracy: 1e-9)
        XCTAssertEqual(PlayTableMath.stagger(index: 30, step: 0.05, cap: 0.3), 0.3, accuracy: 1e-9)
    }

    // MARK: - Boards

    func testBoxesBesideALine() {
        // A 2 × 3 board. The top edge touches one box; an inner horizontal two.
        XCTAssertEqual(PlayTableMath.boxesBeside(horizontal: true, row: 0, col: 1, rows: 2, cols: 3), [1])
        XCTAssertEqual(PlayTableMath.boxesBeside(horizontal: true, row: 1, col: 1, rows: 2, cols: 3), [1, 4])
        XCTAssertEqual(PlayTableMath.boxesBeside(horizontal: true, row: 2, col: 2, rows: 2, cols: 3), [5])
        // The left edge, an inner vertical, the right edge.
        XCTAssertEqual(PlayTableMath.boxesBeside(horizontal: false, row: 1, col: 0, rows: 2, cols: 3), [3])
        XCTAssertEqual(PlayTableMath.boxesBeside(horizontal: false, row: 0, col: 2, rows: 2, cols: 3), [1, 2])
        XCTAssertEqual(PlayTableMath.boxesBeside(horizontal: false, row: 0, col: 3, rows: 2, cols: 3), [2])
    }

    func testDropTimeGrowsWithTheFallButStaysQuick() {
        let short = PlayTableMath.dropSeconds(rows: 0)
        let long = PlayTableMath.dropSeconds(rows: 8)
        XCTAssertLessThan(short, long)
        XCTAssertGreaterThanOrEqual(short, 0.18)
        XCTAssertLessThanOrEqual(long, 0.55)
        XCTAssertEqual(PlayTableMath.dropSeconds(rows: -3), PlayTableMath.dropSeconds(rows: 0))
    }

    func testMaterialLead() {
        XCTAssertEqual(PlayTableMath.materialLead(taken: [9, 1, 1], lost: [5, 3]), 3)
        XCTAssertEqual(PlayTableMath.materialLead(taken: [], lost: [1]), -1)
        XCTAssertEqual(PlayTableMath.materialLead(taken: [], lost: []), 0)
    }

    // MARK: - Dice

    func testRollLandsOnTheLetterAndNeverShowsItEarly() {
        for seed in 0..<40 {
            let faces = PlayTableMath.rollFaces(final: "m", count: 9, seed: seed)
            XCTAssertEqual(faces.count, 9)
            XCTAssertEqual(faces.last, "M")
            XCTAssertFalse(faces.dropLast().contains("M"))
            for (a, b) in zip(faces, faces.dropFirst()) { XCTAssertNotEqual(a, b) }
            XCTAssertEqual(faces, PlayTableMath.rollFaces(final: "M", count: 9, seed: seed))
        }
        XCTAssertEqual(PlayTableMath.rollFaces(final: "q", count: 1, seed: 3), ["Q"])
        XCTAssertEqual(PlayTableMath.rollFaces(final: "q", count: 0, seed: 3), ["Q"])
    }

    // MARK: - Progress

    func testProgressDotsScaleALongRun() {
        XCTAssertTrue(PlayTableMath.progressDots(done: 3, count: 10, cap: 20) == (3, 10))
        XCTAssertTrue(PlayTableMath.progressDots(done: 15, count: 30, cap: 10) == (5, 10))
        XCTAssertTrue(PlayTableMath.progressDots(done: 30, count: 30, cap: 10) == (10, 10))
        XCTAssertTrue(PlayTableMath.progressDots(done: -1, count: 4, cap: 10) == (0, 4))
        XCTAssertTrue(PlayTableMath.progressDots(done: 2, count: 0, cap: 10) == (0, 0))
    }
}
