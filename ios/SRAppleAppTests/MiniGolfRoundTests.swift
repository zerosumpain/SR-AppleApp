import XCTest
@testable import SRAppleApp

/// Mini Golf's scorecard, its words for a score, the bests kept on the phone,
/// and the camera.
final class MiniGolfRoundTests: XCTestCase {
    private func players(_ n: Int) -> [MiniGolfPlayer] {
        (0..<n).map { MiniGolfPlayer(id: $0, name: "P\($0 + 1)", seat: $0) }
    }

    func testScoreWords() {
        XCTAssertEqual(MiniGolfScoreWord.word(strokes: 1, par: 3), "Hole in one!")
        XCTAssertEqual(MiniGolfScoreWord.word(strokes: 1, par: 2), "Hole in one!")
        XCTAssertEqual(MiniGolfScoreWord.word(strokes: 2, par: 5), "Albatross!")
        XCTAssertEqual(MiniGolfScoreWord.word(strokes: 2, par: 4), "Eagle!")
        XCTAssertEqual(MiniGolfScoreWord.word(strokes: 2, par: 3), "Birdie")
        XCTAssertEqual(MiniGolfScoreWord.word(strokes: 3, par: 3), "Par")
        XCTAssertEqual(MiniGolfScoreWord.word(strokes: 4, par: 3), "Bogey")
        XCTAssertEqual(MiniGolfScoreWord.word(strokes: 5, par: 3), "Double bogey")
        XCTAssertEqual(MiniGolfScoreWord.word(strokes: 6, par: 3), "Triple bogey")
        XCTAssertEqual(MiniGolfScoreWord.word(strokes: 7, par: 3), "4 over")
        XCTAssertEqual(MiniGolfScoreWord.toPar(0), "E")
        XCTAssertEqual(MiniGolfScoreWord.toPar(3), "+3")
        XCTAssertEqual(MiniGolfScoreWord.toPar(-2), "\u{2212}2")
    }

    func testPlayersTakeTurnsThenTheNextHole() {
        var round = MiniGolfRound(loop: .front, players: players(3))
        XCTAssertEqual(round.hole.number, 1)
        XCTAssertEqual(round.turn, 0)
        round.record(strokes: 2)
        XCTAssertEqual(round.turn, 1)
        XCTAssertFalse(round.holeDone)
        XCTAssertFalse(round.nextHole(), "not until everyone has played")
        round.record(strokes: 3)
        round.record(strokes: 4)
        XCTAssertTrue(round.holeDone)
        XCTAssertTrue(round.nextHole())
        XCTAssertEqual(round.hole.number, 2)
        XCTAssertEqual(round.turn, 0)
        XCTAssertEqual(round.total(2), 4)
        XCTAssertEqual(round.toPar(0), 0)
        XCTAssertEqual(round.toPar(2), 2)
    }

    func testAScoreIsCappedAtTheMostAHoleTakes() {
        var round = MiniGolfRound(loop: .back, players: players(1))
        XCTAssertEqual(round.hole.number, 10)
        round.record(strokes: 40)
        XCTAssertEqual(round.strokes(player: 0, slot: 0), MiniGolfRules.maxStrokes(par: round.hole.par))
    }

    func testRoundEndsAndNamesAWinner() {
        var round = MiniGolfRound(loop: .front, players: players(2))
        for slot in 0..<9 {
            let par = round.hole(at: slot).par
            round.record(strokes: par)
            round.record(strokes: par + 1)
            if slot < 8 { XCTAssertTrue(round.nextHole()) }
        }
        XCTAssertTrue(round.isOver)
        XCTAssertFalse(round.nextHole())
        XCTAssertEqual(round.standings, [0, 1])
        XCTAssertEqual(round.winner, 0)
        XCTAssertEqual(round.total(0), MiniGolfLoop.front.par)
        XCTAssertEqual(round.toPar(1), 9)
    }

    func testATieHasNoWinner() {
        var round = MiniGolfRound(loop: .front, players: players(2))
        for slot in 0..<9 {
            round.record(strokes: 3)
            round.record(strokes: 3)
            if slot < 8 { round.nextHole() }
        }
        XCTAssertTrue(round.isOver)
        XCTAssertNil(round.winner)
    }

    func testAtMostFourPlayersAndNeverNone() {
        XCTAssertEqual(MiniGolfRound(loop: .full, players: players(6)).players.count, 4)
        XCTAssertEqual(MiniGolfRound(loop: .full, players: []).players.count, 1)
        XCTAssertEqual(MiniGolfRound(loop: .full, players: []).holeCount, 18)
    }

    func testBookKeepsBestsAndHolesInOne() {
        var book = MiniGolfBook()
        XCTAssertTrue(book.noteHole(3, strokes: 4))
        XCTAssertFalse(book.noteHole(3, strokes: 5))
        XCTAssertTrue(book.noteHole(3, strokes: 1))
        XCTAssertEqual(book.best(hole: 3), 1)
        XCTAssertEqual(book.holesInOne, 1)
        XCTAssertTrue(book.noteRound(.front, strokes: 30))
        XCTAssertFalse(book.noteRound(.front, strokes: 31))
        XCTAssertTrue(book.noteRound(.back, strokes: 40))
        XCTAssertEqual(book.best(loop: .front), 30)
        XCTAssertNil(book.best(loop: .full))
        XCTAssertEqual(book.rounds, 3)
    }

    func testStoreRoundTrips() throws {
        let suite = "mini-golf-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MiniGolfStore(defaults: defaults)
        XCTAssertEqual(store.load(), MiniGolfBook())
        var book = MiniGolfBook()
        book.noteHole(7, strokes: 2)
        book.noteRound(.full, strokes: 61)
        store.save(book)
        XCTAssertEqual(store.load(), book)
        XCTAssertTrue(MiniGolfStore.key.hasPrefix("mini-golf"))
    }

    func testCameraFitsASmallHoleAndFollowsOnALongOne() {
        let small = MiniGolfCourse.firstPutt
        // A big phone's play area: the whole of hole 1 fits comfortably.
        let fitted = MiniGolfCamera.framing(small.bounds, width: 400, height: 700, focus: small.tee)
        XCTAssertEqual(fitted.centre.x, small.bounds.centre.x, accuracy: 1e-9)
        XCTAssertEqual(fitted.centre.y, small.bounds.centre.y, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(fitted.scale, MiniGolfCamera.closest)

        let long = MiniGolfCourse.grandFinale
        let atTee = MiniGolfCamera.framing(long.bounds, width: 340, height: 520, focus: long.tee)
        let atCup = MiniGolfCamera.framing(long.bounds, width: 340, height: 520, focus: long.cup)
        XCTAssertGreaterThan(atTee.centre.y, atCup.centre.y, "the camera follows the ball up the hole")
        // Close enough to see the ball: the width of the hole fills the picture.
        XCTAssertEqual(atTee.scale, 340 / (long.bounds.width + 4), accuracy: 1e-9)
        // It never shows beyond the frame's end.
        let halfH = 520 / 2 / atTee.scale
        XCTAssertLessThanOrEqual(atTee.centre.y + halfH, long.bounds.maxY + 2 + 1e-9)

        let overview = MiniGolfCamera.framing(long.bounds, width: 340, height: 520, focus: long.tee, overview: true)
        XCTAssertLessThan(overview.scale, atTee.scale)
        XCTAssertEqual(overview.centre.y, long.bounds.centre.y, accuracy: 1e-9)
    }

    func testShotSpeedRunsFromATapToFullPower() {
        XCTAssertEqual(MiniGolfRules.shotSpeed(power: 0), MiniGolfRules.minShot)
        XCTAssertEqual(MiniGolfRules.shotSpeed(power: 1), MiniGolfRules.maxShot)
        XCTAssertEqual(MiniGolfRules.shotSpeed(power: 7), MiniGolfRules.maxShot)
    }
}
