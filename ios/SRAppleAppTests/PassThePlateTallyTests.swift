import XCTest
@testable import SRAppleApp

/// Pass the Plate's tables, grouped for the eye: sets, popcorn, pies, berries.
final class PassThePlateTallyTests: XCTestCase {
    private typealias Card = PassThePlateTally.Card

    func testPopcornSlides() {
        XCTAssertEqual((0...8).map(PassThePlateTally.popcorn), [0, 1, 3, 6, 10, 14, 18, 18, 18])
    }

    func testCardsGroupInTheOrderTheyArrived() {
        let groups = PassThePlateTally.groups([
            Card(kind: "pizza", family: "triple"),
            Card(kind: "berry1", family: "majority", value: 1),
            Card(kind: "pizza", family: "triple"),
            Card(kind: "berry3", family: "majority", value: 3),
            Card(kind: "spoon", family: "takeTwo"),
        ])
        XCTAssertEqual(groups.map(\.key), ["pizza", "berries", "spoon"])
        XCTAssertEqual(groups[0].count, 2)
        XCTAssertEqual(groups[0].towardsNext, 2)
        XCTAssertEqual(groups[0].sets, 0)
        XCTAssertEqual(groups[1].figure, 4)
        XCTAssertEqual(groups[1].sample, "berry1")
        XCTAssertNil(groups[2].figure)
    }

    func testPiesDoubleWhenBoostedAndGravyWaits() {
        let groups = PassThePlateTally.groups([
            Card(kind: "gravy", family: "multiplier", spent: true),
            Card(kind: "pie3", family: "pie", value: 3, boosted: true),
            Card(kind: "pie2", family: "pie", value: 2),
            Card(kind: "gravy", family: "multiplier"),
        ])
        let pies = groups.first { $0.key == "pies" }
        let gravy = groups.first { $0.key == "gravy" }
        XCTAssertEqual(pies?.figure, 8)
        XCTAssertEqual(gravy?.figure, 1)
        XCTAssertEqual(gravy.flatMap(PassThePlateTally.caption), "next pie doubles")
    }

    func testCaptionsSaySetsAndProgress() {
        func caption(_ cards: [Card]) -> String? { PassThePlateTally.groups(cards).first.flatMap(PassThePlateTally.caption) }
        let pancake = Card(kind: "pancake", family: "pair")
        let pizza = Card(kind: "pizza", family: "triple")
        XCTAssertEqual(caption([pancake]), "1 of 2 for a pair")
        XCTAssertEqual(caption([pancake, pancake]), "1 pair")
        XCTAssertEqual(caption([pancake, pancake, pancake]), "1 pair, 1 of 2")
        XCTAssertEqual(caption([pizza, pizza]), "2 of 3 for a pizza")
        XCTAssertEqual(caption([pizza, pizza, pizza]), "1 whole pizza")
        XCTAssertEqual(caption([pizza, pizza, pizza, pizza]), "1 whole pizza, 1 of 3")
        XCTAssertEqual(caption([Card(kind: "popcorn", family: "sliding"), Card(kind: "popcorn", family: "sliding")]), "3 points")
        XCTAssertEqual(caption([Card(kind: "berry1", family: "majority", value: 1)]), "1 berry")
        XCTAssertNil(caption([Card(kind: "icecream", family: "dessert")]))
    }
}
