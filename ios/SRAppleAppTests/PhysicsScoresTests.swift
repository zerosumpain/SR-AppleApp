import XCTest
@testable import SRAppleApp

final class PhysicsScoresTests: XCTestCase {
    func testLanderKeepsTheBestRun() {
        var book = PhysicsScoreBook()
        XCTAssertTrue(book.recordLander(score: 400, level: 2))
        XCTAssertFalse(book.recordLander(score: 300, level: 3))
        XCTAssertTrue(book.recordLander(score: 900, level: 4))
        XCTAssertEqual(book.landerBest, 900)
        XCTAssertEqual(book.landerBestLevel, 4)
        XCTAssertEqual(book.landerRuns, 3)
        XCTAssertFalse(PhysicsScoreBook().landerBest > 0)
    }

    func testRacesKeepTheBestTimeAndLapPerTrack() {
        var book = PhysicsScoreBook()
        XCTAssertTrue(book.recordRace(track: "paddock", time: 70, bestLap: 22))
        XCTAssertFalse(book.recordRace(track: "paddock", time: 75, bestLap: 21))
        XCTAssertTrue(book.recordRace(track: "quarry", time: 90, bestLap: nil))
        XCTAssertEqual(book.carBest, ["paddock": 70, "quarry": 90])
        XCTAssertEqual(book.carBestLap, ["paddock": 21])
        XCTAssertEqual(book.carRaces, 3)
    }

    func testTheBookAndGhostsKeep() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "physics-scores-test"))
        defaults.removePersistentDomain(forName: "physics-scores-test")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("physics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PhysicsScoreStore(defaults: defaults, folder: folder)
        XCTAssertEqual(store.load(), PhysicsScoreBook())
        var book = PhysicsScoreBook()
        book.recordLander(score: 500, level: 3)
        store.save(book)
        XCTAssertEqual(store.load(), book)

        XCTAssertNil(store.ghost(track: "paddock", laps: 3))
        var ghost = CarGhost(trackId: "paddock", laps: 3, name: "Me")
        ghost.record(CarState(x: 1, y: 2, heading: 0), at: 0)
        ghost.time = 61
        store.saveGhost(ghost)
        XCTAssertEqual(store.ghost(track: "paddock", laps: 3), ghost)
        XCTAssertNil(store.ghost(track: "paddock", laps: 2))
        XCTAssertNil(store.ghost(track: "../etc", laps: 3))
    }
}
