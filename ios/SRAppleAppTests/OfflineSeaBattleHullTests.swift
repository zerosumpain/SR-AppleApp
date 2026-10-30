import XCTest
@testable import SRAppleApp

/// Sea Battle's hull drawing: which part of a ship each square is, which way
/// a ship lies, and the marks a whole fleet gives its grid.
final class OfflineSeaBattleHullTests: XCTestCase {
    func testPartsRunBowToStern() {
        XCTAssertEqual(SeaBattleHull.parts(count: 0), [])
        XCTAssertEqual(SeaBattleHull.parts(count: 1), [.single])
        XCTAssertEqual(SeaBattleHull.parts(count: 2), [.start, .end])
        XCTAssertEqual(SeaBattleHull.parts(count: 4), [.start, .middle, .middle, .end])
    }

    func testAcrossAndDown() {
        XCTAssertTrue(SeaBattleHull.liesAcross([9, 10, 11], size: 8))
        XCTAssertFalse(SeaBattleHull.liesAcross([3, 11, 19], size: 8))
        XCTAssertFalse(SeaBattleHull.liesAcross([7, 8], size: 8), "a wrap onto the next row is not across")
        XCTAssertTrue(SeaBattleHull.liesAcross([5], size: 8), "one square reads as across")
    }

    func testFleetMarks() {
        let marks = SeaBattleHull.marks(ships: [[0, 1, 2, 3], [10, 18]], size: 8)
        XCTAssertEqual(marks.count, 6)
        XCTAssertEqual(marks[0], SeaBattleHullMark(part: .start, across: true, ship: 0))
        XCTAssertEqual(marks[3], SeaBattleHullMark(part: .end, across: true, ship: 0))
        XCTAssertEqual(marks[10], SeaBattleHullMark(part: .start, across: false, ship: 1))
        XCTAssertEqual(marks[18], SeaBattleHullMark(part: .end, across: false, ship: 1))
        XCTAssertNil(marks[4])
    }

    func testAnOverlapKeepsTheFirstShip() {
        let marks = SeaBattleHull.marks(ships: [[0, 1], [1, 9]], size: 8)
        XCTAssertEqual(marks[1]?.ship, 0)
        XCTAssertEqual(marks[9]?.ship, 1)
    }
}
