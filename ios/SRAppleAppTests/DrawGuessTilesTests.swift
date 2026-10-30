import XCTest
import CoreGraphics
@testable import SRAppleApp

/// Draw & Guess's letter tiles: how the server's hint becomes a row of tiles,
/// and how wide each may be so the row always fits the phone.
final class DrawGuessTilesTests: XCTestCase {

    func testAHintBecomesBlanksLettersAndAGap() {
        let slots = DrawGuessTileSlot.slots("b__ _t")
        XCTAssertEqual(slots.count, 6)
        XCTAssertEqual(slots[0].letter, "b")
        XCTAssertNil(slots[1].letter)
        XCTAssertFalse(slots[1].gap)
        XCTAssertTrue(slots[3].gap)
        XCTAssertEqual(slots[5].letter, "t")
        XCTAssertEqual(Set(slots.map(\.id)).count, slots.count, "every tile has its own id")
    }

    func testTilesNeverGrowPastFortyPoints() {
        let slots = DrawGuessTileSlot.slots("____")
        XCTAssertEqual(DrawGuessTileSlot.side(slots, width: 335), 40)
    }

    func testALongWordShrinksToFitASmallPhone() {
        let slots = DrawGuessTileSlot.slots("______________ ______")
        let side = DrawGuessTileSlot.side(slots, width: 335)
        let gaps = DrawGuessTileSlot.spacing * CGFloat(slots.count - 1)
        let units = CGFloat(20) + 0.5
        XCTAssertLessThanOrEqual(side * units + gaps, 335.5)
        XCTAssertGreaterThanOrEqual(side, 8)
    }

    func testAnEmptyHintHasNoTiles() {
        XCTAssertTrue(DrawGuessTileSlot.slots("").isEmpty)
        XCTAssertEqual(DrawGuessTileSlot.side([], width: 335), 40)
    }

    func testTheEraserIsThePaper() {
        XCTAssertEqual(DrawGuessInk.color("white"), DrawGuessInk.paper)
        XCTAssertEqual(DrawGuessInk.spoken("white"), "eraser")
    }
}
