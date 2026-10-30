import XCTest
@testable import SRAppleApp

final class SkyHopperRecordsTests: XCTestCase {
    /// A run that climbed `height` units, picked up `stars` stars at the
    /// top, and fell.
    private func finishedRun(height: Double, stars: Int) -> SkyHopperGame {
        let pickups = (0..<stars).map { SkyHopperPickup(id: 100 + $0, kind: .star, x: 50, y: height + 4.5) }
        var game = SkyHopperGame(hopper: SkyHopperHopper(x: 50, y: height), clouds: [], pickups: pickups)
        var n = 0
        while !game.isOver && n < 5000 {
            game.step(steer: 0)
            n += 1
        }
        return game
    }

    func testAFinishedRunScoresHeightAndStars() {
        let game = finishedRun(height: 500, stars: 3)
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.metres, 100)
        XCTAssertEqual(game.stars, 3)
        XCTAssertEqual(game.score, 100 + 3 * SkyHopperRules.starPoints)
    }

    func testTheBestIsKeptForEachControl() {
        var records = SkyHopperRecords()
        let first = records.record(finishedRun(height: 500, stars: 2), control: .tilt)
        XCTAssertTrue(first.newBest)
        XCTAssertEqual(first.best, 110)
        XCTAssertEqual(first.metres, 100)
        XCTAssertEqual(first.control, .tilt)

        let lower = records.record(finishedRun(height: 250, stars: 0), control: .tilt)
        XCTAssertFalse(lower.newBest)
        XCTAssertEqual(lower.best, 110)
        XCTAssertEqual(lower.bestMetres, 100)

        // Buttons have a best of their own: a lower score is still a first best there.
        let buttons = records.record(finishedRun(height: 250, stars: 0), control: .buttons)
        XCTAssertTrue(buttons.newBest)
        XCTAssertEqual(records.best(.buttons).score, 50)
        XCTAssertEqual(records.best(.tilt).score, 110)
        XCTAssertEqual(records.best(.tilt).games, 2)
        XCTAssertEqual(records.games, 3)
        XCTAssertEqual(records.totalStars, 2)
    }

    func testAnEmptyRunIsNeverANewBest() {
        var records = SkyHopperRecords()
        let result = records.record(finishedRun(height: 0, stars: 0), control: .buttons)
        XCTAssertEqual(result.score, 0)
        XCTAssertFalse(result.newBest)
        XCTAssertEqual(result.fall, .missed)
    }

    func testColoursOpenWithStarsInOrder() {
        let thresholds = SkyHopperColour.allCases.map(\.unlockStars)
        XCTAssertEqual(thresholds, thresholds.sorted())
        XCTAssertEqual(thresholds.first, 0)

        var records = SkyHopperRecords()
        XCTAssertEqual(records.nextColour, .mint)
        records.colour = .berry
        XCTAssertEqual(records.activeColour, .sunny, "a locked colour is not drawn")
        records.totalStars = 45
        let result = records.record(finishedRun(height: 100, stars: 6), control: .tilt)
        XCTAssertEqual(result.unlockedColours, ["Mint"])
        XCTAssertTrue(records.isUnlocked(.mint))
        XCTAssertFalse(records.isUnlocked(.berry))
        XCTAssertEqual(records.nextColour, .berry)
        records.totalStars = 10_000
        XCTAssertNil(records.nextColour)
        XCTAssertEqual(records.activeColour, .berry)
    }

    func testTiltIsTheDefaultOnlyWithASensor() {
        var records = SkyHopperRecords()
        XCTAssertEqual(records.control(tiltAvailable: true), .tilt)
        XCTAssertEqual(records.control(tiltAvailable: false), .buttons)
        records.control = .buttons
        XCTAssertEqual(records.control(tiltAvailable: true), .buttons)
        records.control = .tilt
        XCTAssertEqual(records.control(tiltAvailable: false), .buttons)
    }

    func testRecordsSurviveARoundTripAndAnOlderSave() throws {
        let suite = "sky-hopper-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SkyHopperRecordStore(defaults: defaults)
        XCTAssertEqual(store.load(), SkyHopperRecords())

        var records = store.load()
        _ = records.record(finishedRun(height: 400, stars: 1), control: .buttons)
        records.control = .buttons
        records.colour = .mint
        store.save(records)
        XCTAssertEqual(store.load(), records)

        // An older save with fewer fields still loads.
        defaults.set(Data(#"{"bests":{"tilt":{"score":40}},"totalStars":12}"#.utf8), forKey: SkyHopperRecordStore.key)
        let old = store.load()
        XCTAssertEqual(old.best(.tilt).score, 40)
        XCTAssertEqual(old.best(.tilt).metres, 0)
        XCTAssertEqual(old.totalStars, 12)
        XCTAssertNil(old.control)
        XCTAssertEqual(old.colour, .sunny)

        // Something unreadable is a fresh start, not a crash.
        defaults.set(Data("not json".utf8), forKey: SkyHopperRecordStore.key)
        XCTAssertEqual(store.load(), SkyHopperRecords())
    }

    func testEveryEndingHasWords() {
        for fall in [SkyHopperFall.missed, .crumbled, .blinked, .launched] {
            XCTAssertFalse(fall.sentence.isEmpty)
            XCTAssertFalse(fall.tip.isEmpty)
        }
        XCTAssertEqual(Set(SkyHopperControl.allCases.map(\.title)).count, 2)
        XCTAssertEqual(Set(SkyHopperColour.allCases.map(\.title)).count, SkyHopperColour.allCases.count)
    }
}
