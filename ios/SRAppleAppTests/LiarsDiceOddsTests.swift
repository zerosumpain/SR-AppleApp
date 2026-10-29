import XCTest
@testable import SRAppleApp

/// Liar's Dice's guide to a bid: my dice are known, the rest are chances.
final class LiarsDiceOddsTests: XCTestCase {

    func testOnesCountWhenWild() {
        XCTAssertEqual(LiarsDiceOdds.mine([3, 1, 5, 3], face: 3, wild: true), 3)
        XCTAssertEqual(LiarsDiceOdds.mine([3, 1, 5, 3], face: 3, wild: false), 2)
        XCTAssertEqual(LiarsDiceOdds.perDie(face: 5, wild: true), 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(LiarsDiceOdds.perDie(face: 5, wild: false), 1.0 / 6.0, accuracy: 1e-9)
    }

    func testABidMyOwnDiceCoverIsCertain() {
        XCTAssertEqual(LiarsDiceOdds.chance(quantity: 3, face: 3, mine: [3, 1, 5, 3], unseen: 3, wild: true), 1)
        XCTAssertEqual(LiarsDiceOdds.feel(1), .sure)
    }

    func testABidPastEveryDieIsImpossible() {
        XCTAssertEqual(LiarsDiceOdds.chance(quantity: 8, face: 5, mine: [3, 1, 5, 3], unseen: 3, wild: true), 0)
        XCTAssertEqual(LiarsDiceOdds.feel(0), .impossible)
    }

    func testTheChanceIsABinomialTail() {
        // Need one more 5 from three unseen dice at 1/3 each: 1 - (2/3)^3.
        let p = LiarsDiceOdds.chance(quantity: 3, face: 5, mine: [5, 1], unseen: 3, wild: true)
        XCTAssertEqual(p, 1 - pow(2.0 / 3.0, 3), accuracy: 1e-9)
        // Need all three: (1/3)^3.
        let q = LiarsDiceOdds.chance(quantity: 5, face: 5, mine: [5, 1], unseen: 3, wild: true)
        XCTAssertEqual(q, pow(1.0 / 3.0, 3), accuracy: 1e-9)
    }

    func testMoreDiceIsNeverMoreLikely() {
        var last = 1.0
        for q in 1...12 {
            let p = LiarsDiceOdds.chance(quantity: q, face: 4, mine: [4, 2, 6], unseen: 9, wild: false)
            XCTAssertLessThanOrEqual(p, last + 1e-12)
            last = p
        }
    }

    func testTheExpectedCount() {
        XCTAssertEqual(LiarsDiceOdds.expected(face: 3, mine: [3, 1, 5, 3], unseen: 3, wild: true), 4, accuracy: 1e-9)
        XCTAssertEqual(LiarsDiceOdds.expected(face: 3, mine: [], unseen: 6, wild: false), 1, accuracy: 1e-9)
    }

    func testChoose() {
        XCTAssertEqual(LiarsDiceOdds.choose(5, 2), 10)
        XCTAssertEqual(LiarsDiceOdds.choose(30, 15), 155_117_520)
        XCTAssertEqual(LiarsDiceOdds.choose(3, 0), 1)
        XCTAssertEqual(LiarsDiceOdds.choose(3, 4), 0)
    }

    func testTheLineRoundsToFives() {
        XCTAssertEqual(LiarsDiceOdds.line(0.62), "A coin toss · about 60%")
        XCTAssertEqual(LiarsDiceOdds.line(0.73), "Likely · about 75%")
        XCTAssertEqual(LiarsDiceOdds.line(0.01), "A long shot · about 5%")
        XCTAssertEqual(LiarsDiceOdds.line(0.2), "Unlikely · about 20%")
        XCTAssertEqual(LiarsDiceOdds.line(1), "Certain: you can see them all")
        XCTAssertEqual(LiarsDiceOdds.line(0), "Impossible: not enough dice left")
    }
}
