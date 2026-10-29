import XCTest
@testable import SRAppleApp

/// The records Chess and the marble races keep on this phone, the move strip,
/// the clock's worry, the podium and the confetti's sums.
final class ChessMarbleRecordsTests: XCTestCase {
    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Chess record

    func testAChessGameIsCountedOnceHoweverOftenItsPageIsOpened() {
        var book = ChessRecordBook()
        let key = ChessRecordBook.key(room: "g_1", moves: 4, outcome: "checkmate")
        XCTAssertTrue(book.record(key: key, outcome: .won, moves: 4).counted)
        XCTAssertFalse(book.record(key: key, outcome: .won, moves: 4).counted)
        XCTAssertEqual(book.wins, 1)
        XCTAssertEqual(book.played, 1)
    }

    func testTheStreakGrowsWithWinsAndADrawOrALossEndsIt() {
        var book = ChessRecordBook()
        book.record(key: "a", outcome: .won, moves: 40)
        let second = book.record(key: "b", outcome: .won, moves: 30)
        XCTAssertTrue(second.newBestStreak, "two in a row is a new best streak")
        XCTAssertEqual(book.streak, 2)
        book.record(key: "c", outcome: .drawn, moves: 60)
        XCTAssertEqual(book.streak, 0)
        XCTAssertEqual(book.bestStreak, 2)
        book.record(key: "d", outcome: .lost, moves: 20)
        XCTAssertEqual(book.line, "2 won · 1 drawn · 1 lost")
    }

    func testTheQuickestWinIsInFullMoves() {
        var book = ChessRecordBook()
        let first = book.record(key: "a", outcome: .won, moves: 40)
        XCTAssertFalse(first.newQuickest, "the first win is no record to beat")
        XCTAssertEqual(book.quickestWin, 20)
        let faster = book.record(key: "b", outcome: .won, moves: 7)
        XCTAssertTrue(faster.newQuickest)
        XCTAssertEqual(book.quickestWin, 4)
        book.record(key: "c", outcome: .won, moves: 50)
        XCTAssertEqual(book.quickestWin, 4)
    }

    func testOnlyTheLastFewKeysAreKept() {
        var book = ChessRecordBook()
        for i in 0..<(ChessRecordBook.seenLimit + 5) { book.record(key: "k\(i)", outcome: .drawn, moves: 10) }
        XCTAssertEqual(book.seen.count, ChessRecordBook.seenLimit)
        XCTAssertEqual(book.seen.last, "k\(ChessRecordBook.seenLimit + 4)")
    }

    func testTheChessRecordSurvivesASaveAndALoad() {
        let defaults = freshDefaults("ChessMarbleRecordsTests.chess")
        let store = ChessRecordStore(defaults: defaults)
        XCTAssertEqual(store.load(), ChessRecordBook())
        var book = store.load()
        book.record(key: "a", outcome: .won, moves: 9)
        store.save(book)
        XCTAssertEqual(store.load(), book)
        XCTAssertEqual(ChessRecordStore.key, "chess.record.v1")
    }

    // MARK: - Move strip and clock

    func testTheMovesPairUpWithBlacksHalfMissingUntilPlayed() {
        let pairs = ChessMoveStrip.pairs(["e4", "e5", "Nf3"])
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].text, "1. e4 e5")
        XCTAssertEqual(pairs[1].text, "2. Nf3")
        XCTAssertNil(pairs[1].black)
        XCTAssertEqual(ChessMoveStrip.pairs([]), [])
    }

    func testAClockWorriesUnderThirtySecondsAndPanicsUnderTen() {
        XCTAssertEqual(ChessClockUrgency.of(600_000), .calm)
        XCTAssertEqual(ChessClockUrgency.of(30_000), .calm)
        XCTAssertEqual(ChessClockUrgency.of(29_999), .low)
        XCTAssertEqual(ChessClockUrgency.of(9_999), .critical)
        XCTAssertEqual(ChessClockUrgency.of(0), .critical)
    }

    // MARK: - Marble race record

    func testAMarbleRaceIsCountedOnceAndKeepsTheBestPlace() {
        var book = MarbleRaceRecordBook()
        XCTAssertTrue(book.record(key: "g_1|7", place: 4).newBest)
        XCTAssertFalse(book.record(key: "g_1|7", place: 1).counted, "the same race twice counts once")
        XCTAssertEqual(book.races, 1)
        XCTAssertEqual(book.bestPlace, 4)
        XCTAssertEqual(book.podiums, 0)
        let win = book.record(key: "g_1|8", place: 1)
        XCTAssertTrue(win.newBest)
        XCTAssertEqual(book.wins, 1)
        XCTAssertEqual(book.podiums, 1)
        XCTAssertEqual(book.line, "2 races · 1 win · best 1st")
    }

    func testASoloRaceCountsWithoutAKeyAndARaceWithNoPlaceStillCounts() {
        var book = MarbleRaceRecordBook()
        book.record(key: nil, place: 2)
        book.record(key: nil, place: 2)
        book.record(key: nil, place: nil)
        XCTAssertEqual(book.races, 3)
        XCTAssertEqual(book.podiums, 2)
        XCTAssertEqual(book.bestPlace, 2)
        XCTAssertTrue(book.seen.isEmpty)
    }

    func testTheTwoMarbleBooksKeepToTheirOwnKeys() {
        let defaults = freshDefaults("ChessMarbleRecordsTests.marble")
        let room = MarbleRaceRecordStore(defaults: defaults, key: MarbleRaceRecordStore.roomKey)
        let solo = MarbleRaceRecordStore(defaults: defaults, key: MarbleRaceRecordStore.soloKey)
        var book = room.load()
        book.record(key: "r", place: 1)
        room.save(book)
        XCTAssertEqual(room.load().wins, 1)
        XCTAssertEqual(solo.load(), MarbleRaceRecordBook())
        XCTAssertTrue(MarbleRaceRecordStore.roomKey.hasPrefix("marblerace."))
        XCTAssertTrue(MarbleRaceRecordStore.soloKey.hasPrefix("marbler."))
    }

    func testOrdinalsReadAsSpoken() {
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111].map(MarbleRaceOrdinal.text),
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd", "101st", "111th"])
        XCTAssertEqual(MarbleRaceOrdinal.spoken(2), "second")
        XCTAssertEqual(MarbleRaceOrdinal.spoken(5), "5th")
    }

    func testThePodiumStandsSecondFirstThird() {
        XCTAssertEqual(MarbleRacePodium.standing([7, 3, 9, 1]).map(\.place), [2, 1, 3])
        XCTAssertEqual(MarbleRacePodium.standing([7, 3, 9, 1]).map(\.marble), [3, 7, 9])
        XCTAssertEqual(MarbleRacePodium.standing([5]).map(\.marble), [5])
        XCTAssertEqual(MarbleRacePodium.standing([5, 6]).map(\.place), [2, 1])
        XCTAssertTrue(MarbleRacePodium.standing([]).isEmpty)
    }

    func testThePickingClockIsAFractionOfTheMostSeen() {
        XCTAssertEqual(MarbleRacePickClock.fraction(left: 5, total: 10), 0.5, accuracy: 0.0001)
        XCTAssertEqual(MarbleRacePickClock.fraction(left: 12, total: 10), 1)
        XCTAssertEqual(MarbleRacePickClock.fraction(left: -1, total: 10), 0)
        XCTAssertEqual(MarbleRacePickClock.fraction(left: 3, total: 0), 0)
    }

    // MARK: - Confetti

    func testTheSameSeedGivesTheSameBurstAndEveryPieceFallsOutOfSight() {
        let a = ChessMarbleConfetti.make(count: 60, colours: 8, seed: 42)
        let b = ChessMarbleConfetti.make(count: 60, colours: 8, seed: 42)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, ChessMarbleConfetti.make(count: 60, colours: 8, seed: 43))
        XCTAssertEqual(a.pieces.count, 60)
        for piece in a.pieces {
            XCTAssertTrue((0..<8).contains(piece.colour))
            XCTAssertTrue((0...1).contains(piece.x))
            let end = ChessMarbleConfetti.place(piece, at: ChessMarbleConfetti.duration)
            XCTAssertNotNil(end)
            XCTAssertGreaterThan(end?.y ?? 0, 1, "a piece is still on screen when the burst ends")
        }
    }

    func testAPieceIsNowhereBeforeItsDelay() {
        let piece = ChessMarbleConfetti.Piece(x: 0.5, y: 0, vx: 0, vy: 0, spin: 0, colour: 0, size: 0.02, delay: 0.5)
        XCTAssertNil(ChessMarbleConfetti.place(piece, at: 0.2))
        XCTAssertEqual(ChessMarbleConfetti.place(piece, at: 0.5)?.y ?? -1, 0, accuracy: 0.0001)
    }
}
