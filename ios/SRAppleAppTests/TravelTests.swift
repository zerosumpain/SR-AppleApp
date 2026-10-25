import XCTest
import CoreLocation
@testable import SRAppleApp

/// The Travel kit's arithmetic: money typed either way, the round-up, the
/// bearing the way-back arrow turns to, and the distances it says.
@MainActor
final class TravelTests: XCTestCase {

    func testAmountsTypedWithACommaOrAPoint() {
        XCTAssertEqual(TravelMoneyScreen.number("12,50"), 12.5)
        XCTAssertEqual(TravelMoneyScreen.number("12.50"), 12.5)
        XCTAssertEqual(TravelMoneyScreen.number("€ 7"), 7)
        XCTAssertNil(TravelMoneyScreen.number(""))
        XCTAssertNil(TravelMoneyScreen.number("1.2.3"))
    }

    func testTipAndRoundUp() {
        XCTAssertEqual(TravelMoneyScreen.withTip(100, 0), 100)
        XCTAssertEqual(TravelMoneyScreen.withTip(100, 10), 110, accuracy: 0.0001)
        XCTAssertEqual(TravelMoneyScreen.withTip(83.4, -1), 85)
        XCTAssertEqual(TravelMoneyScreen.withTip(85, -1), 85, "a bill already on €5 is left alone")
    }

    func testBearingPointsTheRightWay() {
        let colosseum = CLLocationCoordinate2D(latitude: 41.8902, longitude: 12.4922)
        let north = CLLocationCoordinate2D(latitude: 41.9902, longitude: 12.4922)
        let east = CLLocationCoordinate2D(latitude: 41.8902, longitude: 12.5922)
        let south = CLLocationCoordinate2D(latitude: 41.7902, longitude: 12.4922)
        XCTAssertEqual(TravelCompass.bearing(from: colosseum, to: north), 0, accuracy: 0.5)
        XCTAssertEqual(TravelCompass.bearing(from: colosseum, to: east), 90, accuracy: 0.5)
        XCTAssertEqual(TravelCompass.bearing(from: colosseum, to: south), 180, accuracy: 0.5)
    }

    func testDistancesAndWalks() {
        XCTAssertEqual(TravelCompass.describe(347), "350 m")
        XCTAssertEqual(TravelCompass.describe(2_340), "2.3 km")
        XCTAssertEqual(TravelCompass.walk(750), "10 min")
        XCTAssertEqual(TravelCompass.walk(6_000), "1 h 20 min")
    }

    func testEveryLanguageHasItsOwnName() {
        XCTAssertEqual(TravelLanguage.find("it"), .italian)
        XCTAssertEqual(TravelLanguage.find("nope"), .italian, "an unknown id falls back to Italian")
        XCTAssertEqual(Set(TravelLanguage.theirs.map(\.id)).count, TravelLanguage.theirs.count)
    }

    func testPhrasebookHasNoEmptyLines() {
        for section in TravelPhrases.sections where section.id != TravelPhrases.ownSection {
            XCTAssertFalse(section.phrases.isEmpty, section.title)
            for phrase in section.phrases {
                XCTAssertFalse(phrase.english.isEmpty)
                XCTAssertFalse(phrase.italian.isEmpty)
            }
        }
    }
}
