import XCTest
@testable import SRAppleApp

final class PartyRoomBestsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "PartyRoomBestsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testFirstScoringGameIsABest() {
        var record = PartyRoomRecord()
        let note = record.record(7, token: "a")
        XCTAssertEqual(note, PartyRoomBestNote(previous: nil, best: 7, isNew: true))
        XCTAssertEqual(record.games, 1)
    }

    func testHigherBeatsAndLowerDoesNot() {
        var record = PartyRoomRecord()
        _ = record.record(5, token: "a")
        XCTAssertEqual(record.record(4, token: "b"), PartyRoomBestNote(previous: 5, best: 5, isNew: false))
        XCTAssertEqual(record.record(5, token: "c"), PartyRoomBestNote(previous: 5, best: 5, isNew: false))
        XCTAssertEqual(record.record(9, token: "d"), PartyRoomBestNote(previous: 5, best: 9, isNew: true))
        XCTAssertEqual(record.games, 4)
    }

    func testZeroIsPlayedButNeverABest() {
        var record = PartyRoomRecord()
        XCTAssertEqual(record.record(0, token: "a"), PartyRoomBestNote(previous: nil, best: nil, isNew: false))
        XCTAssertEqual(record.games, 1)
        XCTAssertNil(record.best)
    }

    func testTheSameGameShownTwiceAnswersTheSameWay() {
        var record = PartyRoomRecord()
        _ = record.record(3, token: "a")
        let first = record.record(8, token: "b")
        let again = record.record(8, token: "b")
        XCTAssertEqual(first, again)
        XCTAssertTrue(again.isNew)
        XCTAssertEqual(record.games, 2)
        // An older game seen again is not new, and says the current best.
        XCTAssertEqual(record.record(3, token: "a"), PartyRoomBestNote(previous: 8, best: 8, isNew: false))
    }

    func testSeenListIsBounded() {
        var record = PartyRoomRecord()
        for n in 0..<40 { _ = record.record(n, token: "t\(n)") }
        XCTAssertEqual(record.seen.count, PartyRoomRecord.remembered)
        XCTAssertEqual(record.games, 40)
        XCTAssertEqual(record.best, 39)
    }

    func testStoreSavesPerKindUnderTheGamesKey() {
        let defaults = freshDefaults()
        let store = PartyRoomBestStore(key: "categories.bests.v1", defaults: defaults)
        XCTAssertNil(store.best("8"))
        XCTAssertTrue(store.record(6, kind: "8", token: "r1").isNew)
        XCTAssertFalse(store.record(4, kind: "8", token: "r2").isNew)
        XCTAssertTrue(store.record(2, kind: "6", token: "r3").isNew)
        XCTAssertEqual(store.best("8"), 6)
        XCTAssertEqual(store.best("6"), 2)
        let reopened = PartyRoomBestStore(key: "categories.bests.v1", defaults: defaults)
        XCTAssertEqual(reopened.best("8"), 6)
    }

    func testKeysStartWithTheGameId() {
        XCTAssertTrue(PartyRoomBestStore.categories.key.hasPrefix("categories."))
        XCTAssertTrue(PartyRoomBestStore.quizNight.key.hasPrefix("quiz-night."))
        XCTAssertTrue(PartyRoomBestStore.oneClue.key.hasPrefix("one-clue."))
    }

    func testOrdinals() {
        XCTAssertEqual(["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "101st"],
                       [1, 2, 3, 4, 11, 12, 13, 21, 22, 101].map(PartyRoomMaths.ordinal))
    }

    func testPlacesShareTies() {
        let ids = ["a", "b", "c", "d"]
        let scores = [9, 9, 6, 1]
        XCTAssertEqual(PartyRoomMaths.place(of: "a", ids: ids, scores: scores), 1)
        XCTAssertEqual(PartyRoomMaths.place(of: "b", ids: ids, scores: scores), 1)
        XCTAssertEqual(PartyRoomMaths.place(of: "c", ids: ids, scores: scores), 3)
        XCTAssertEqual(PartyRoomMaths.place(of: "d", ids: ids, scores: scores), 4)
        XCTAssertNil(PartyRoomMaths.place(of: "z", ids: ids, scores: scores))
    }

    func testShareIsClamped() {
        XCTAssertEqual(PartyRoomMaths.share(3, of: 8), 0.375, accuracy: 1e-9)
        XCTAssertEqual(PartyRoomMaths.share(9, of: 8), 1)
        XCTAssertEqual(PartyRoomMaths.share(-1, of: 8), 0)
        XCTAssertEqual(PartyRoomMaths.share(3, of: 0), 0)
    }

    func testTiltAlternatesAndRepeats() {
        XCTAssertLessThan(PartyRoomMaths.tilt(0), 0)
        XCTAssertGreaterThan(PartyRoomMaths.tilt(1), 0)
        XCTAssertEqual(PartyRoomMaths.tilt(4), PartyRoomMaths.tilt(4))
        XCTAssertLessThanOrEqual(abs(PartyRoomMaths.tilt(3)), 3 * 1.4 + 1e-9)
    }

    func testUrgentAndTick() {
        XCTAssertFalse(PartyRoomMaths.urgent(secondsLeft: nil, warnAt: 10))
        XCTAssertFalse(PartyRoomMaths.urgent(secondsLeft: 11, warnAt: 10))
        XCTAssertTrue(PartyRoomMaths.urgent(secondsLeft: 10, warnAt: 10))
        XCTAssertFalse(PartyRoomMaths.urgent(secondsLeft: 0, warnAt: 10))
        XCTAssertTrue(PartyRoomMaths.tick(from: 11, to: 10, warnAt: 10))
        XCTAssertTrue(PartyRoomMaths.tick(from: 4, to: 3, warnAt: 10))
        XCTAssertFalse(PartyRoomMaths.tick(from: 3, to: 3, warnAt: 10))
        XCTAssertFalse(PartyRoomMaths.tick(from: 12, to: 11, warnAt: 10))
        XCTAssertFalse(PartyRoomMaths.tick(from: nil, to: 5, warnAt: 10))
        XCTAssertFalse(PartyRoomMaths.tick(from: 1, to: 0, warnAt: 10))
    }
}
