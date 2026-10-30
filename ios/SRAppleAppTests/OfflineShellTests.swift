import XCTest
@testable import SRAppleApp

/// The Play nearby shell's words and layouts (`OfflineShell`) and the win
/// confetti (`OfflineConfettiField`): pure values, so they are held here
/// rather than found wrong on a phone at the kitchen table.
final class OfflineShellTests: XCTestCase {
    private func row(_ id: String, _ rank: Int, _ score: Int) -> OfflineStanding {
        OfflineStanding(playerId: id, name: id.capitalized, rank: rank, score: score, detail: nil)
    }

    // MARK: - Headline and outcome

    func testHeadlineNamesTheWinner() {
        let table = [row("sam", 1, 9), row("me", 2, 4)]
        XCTAssertEqual(OfflineShell.headline(table, me: "me", isSolo: false), "Sam wins")
        XCTAssertEqual(OfflineShell.headline(table, me: "sam", isSolo: false), "You win")
    }

    func testHeadlineForATieAndAnEmptyTable() {
        let two = [row("me", 1, 5), row("sam", 1, 5), row("ann", 3, 1)]
        XCTAssertEqual(OfflineShell.headline(two, me: "me", isSolo: false), "You and Sam tie")
        let three = [row("ann", 1, 5), row("bob", 1, 5), row("cat", 1, 5)]
        XCTAssertEqual(OfflineShell.headline(three, me: "me", isSolo: false), "Ann, Bob and Cat tie")
        XCTAssertEqual(OfflineShell.headline([], me: "me", isSolo: false), "Game over")
        // You lead a shared win wherever you sit in the table.
        let late = [row("sam", 1, 5), row("me", 1, 5)]
        XCTAssertEqual(OfflineShell.headline(late, me: "me", isSolo: false), "You and Sam tie")
    }

    func testSoloHeadlineIsTheScore() {
        XCTAssertEqual(OfflineShell.headline([row("me", 1, 42)], me: "me", isSolo: true), "42 points")
        XCTAssertEqual(OfflineShell.outcome([row("me", 1, 42)], me: "me", isSolo: true), .solo)
    }

    func testOutcomes() {
        let table = [row("sam", 1, 9), row("me", 2, 4), row("ann", 3, 1)]
        XCTAssertEqual(OfflineShell.outcome(table, me: "sam", isSolo: false), .won)
        XCTAssertEqual(OfflineShell.outcome(table, me: "me", isSolo: false), .placed(2))
        XCTAssertEqual(OfflineShell.outcome(table, me: "zed", isSolo: false), .watched)
        let tie = [row("sam", 1, 9), row("me", 1, 9)]
        XCTAssertEqual(OfflineShell.outcome(tie, me: "me", isSolo: false), .tied)
        // Solo with a bot is a table of two, not a lone score.
        let bot = [row("me", 1, 3), row("bot", 2, 1)]
        XCTAssertEqual(OfflineShell.outcome(bot, me: "me", isSolo: true), .won)
    }

    func testStrapSaysWhereYouCame() {
        XCTAssertEqual(OfflineShell.strap(.placed(3), best: nil, score: nil), "You came 3rd. Another round?")
        XCTAssertEqual(OfflineShell.strap(.solo, best: 40, score: 42), "Your best on this phone.")
        XCTAssertEqual(OfflineShell.strap(.solo, best: 50, score: 42), "Best on this phone: 50.")
        XCTAssertEqual(OfflineShell.strap(.solo, best: nil, score: 42), "Your first score on this phone.")
        XCTAssertEqual(OfflineShell.strap(.solo, best: 0, score: 0), "Best on this phone: 0.", "a nought is no best")
    }

    func testOrdinals() {
        let expected = [1: "1st", 2: "2nd", 3: "3rd", 4: "4th", 11: "11th", 12: "12th", 13: "13th", 21: "21st", 22: "22nd", 101: "101st", 111: "111th"]
        for (n, word) in expected { XCTAssertEqual(OfflineShell.ordinal(n), word, "\(n)") }
    }

    // MARK: - Podium

    func testPodiumPutsTheWinnerInTheMiddle() {
        let table = [row("a", 1, 9), row("b", 2, 5), row("c", 3, 2), row("d", 4, 1)]
        XCTAssertEqual(OfflineShell.podium(table).map(\.playerId), ["b", "a", "c"])
        XCTAssertEqual(OfflineShell.podium(Array(table.prefix(2))).map(\.playerId), ["b", "a"])
        XCTAssertEqual(OfflineShell.podium(Array(table.prefix(1))), [])
        XCTAssertEqual(OfflineShell.podium([]), [])
    }

    func testPodiumHeightsFallWithRank() {
        XCTAssertGreaterThan(OfflineShell.podiumHeight(rank: 1), OfflineShell.podiumHeight(rank: 2))
        XCTAssertGreaterThan(OfflineShell.podiumHeight(rank: 2), OfflineShell.podiumHeight(rank: 3))
        XCTAssertGreaterThan(OfflineShell.podiumHeight(rank: 3), 0)
    }

    // MARK: - Lobby

    func testEmptySeats() {
        XCTAssertEqual(OfflineShell.emptySeats(seated: 2, capacity: 5, maxPlayers: nil), 3)
        XCTAssertEqual(OfflineShell.emptySeats(seated: 2, capacity: 5, maxPlayers: 2), 0)
        XCTAssertEqual(OfflineShell.emptySeats(seated: 1, capacity: 5, maxPlayers: 4), 3)
        XCTAssertEqual(OfflineShell.emptySeats(seated: 5, capacity: 5, maxPlayers: 2), 0, "never negative")
    }

    func testFitNote() {
        XCTAssertNil(OfflineShell.fitNote(minPlayers: 2, maxPlayers: 5, count: 3))
        XCTAssertEqual(OfflineShell.fitNote(minPlayers: 2, maxPlayers: 5, count: 1), "Needs 1 more player")
        XCTAssertEqual(OfflineShell.fitNote(minPlayers: 3, maxPlayers: 5, count: 1), "Needs 2 more players")
        XCTAssertEqual(OfflineShell.fitNote(minPlayers: 2, maxPlayers: 2, count: 4), "Up to 2 players")
        XCTAssertEqual(OfflineShell.fitNote(minPlayers: 1, maxPlayers: 1, count: 2), "Just 1 player")
    }

    // MARK: - Shelves

    func testShelfOrderPutsMostPlayedFirst() {
        let ids = ["a", "b", "c", "d"]
        XCTAssertEqual(OfflineShell.shelfOrder(ids, mostPlayed: ["c", "a"]), ["c", "a", "b", "d"])
        XCTAssertEqual(OfflineShell.shelfOrder(ids, mostPlayed: []), ids)
        XCTAssertEqual(OfflineShell.shelfOrder(ids, mostPlayed: ["zzz", "d"]), ["d", "a", "b", "c"])
    }

    func testOpponentAndModeWords() {
        XCTAssertEqual(OfflineShell.opponentLine(bots: 0), "Just you")
        XCTAssertEqual(OfflineShell.opponentLine(bots: 1), "You v the phone")
        XCTAssertEqual(OfflineShell.opponentLine(bots: 3), "You v 3 bots")
        XCTAssertEqual(OfflineShell.modeTags(canPlaySolo: true, bots: 1, playersLabel: "2–5 players"),
                       ["Solo v bots", "Nearby", "2–5 players"])
        XCTAssertEqual(OfflineShell.modeTags(canPlaySolo: true, bots: 0, playersLabel: "1–4 players"),
                       ["Solo", "Nearby", "1–4 players"])
        XCTAssertEqual(OfflineShell.modeTags(canPlaySolo: false, bots: 0, playersLabel: "2 players"),
                       ["Nearby", "2 players"])
        XCTAssertNil(OfflineShell.playedLine(0))
        XCTAssertEqual(OfflineShell.playedLine(1), "Played once")
        XCTAssertEqual(OfflineShell.playedLine(7), "Played 7×")
    }

    func testUrgency() {
        XCTAssertFalse(OfflineShell.isUrgent(secondsLeft: 0))
        XCTAssertTrue(OfflineShell.isUrgent(secondsLeft: 1))
        XCTAssertTrue(OfflineShell.isUrgent(secondsLeft: 3))
        XCTAssertFalse(OfflineShell.isUrgent(secondsLeft: 4))
    }

    // MARK: - Confetti

    func testConfettiIsRepeatableFromASeed() {
        let a = OfflineConfettiField.pieces(count: 40, seed: 7, colours: 5)
        let b = OfflineConfettiField.pieces(count: 40, seed: 7, colours: 5)
        let c = OfflineConfettiField.pieces(count: 40, seed: 8, colours: 5)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(a.count, 40)
        XCTAssertTrue(a.allSatisfy { (0...1).contains($0.x) && $0.colour >= 0 && $0.colour < 5 })
        XCTAssertEqual(OfflineConfettiField.pieces(count: 0, seed: 1, colours: 3), [])
        XCTAssertEqual(OfflineConfettiField.pieces(count: 3, seed: 0, colours: 0).map(\.colour), [0, 0, 0])
    }

    func testConfettiFallsAndIsGoneByTheEnd() {
        let pieces = OfflineConfettiField.pieces(count: 120, seed: 42, colours: 6)
        for piece in pieces {
            let start = OfflineConfettiField.spot(piece, at: 0, width: 375, height: 700)
            XCTAssertLessThanOrEqual(start.y, 0, "starts above the top")
            let later = OfflineConfettiField.spot(piece, at: piece.delay + 0.5, width: 375, height: 700)
            XCTAssertGreaterThan(later.y, start.y, "falls")
            let end = OfflineConfettiField.spot(piece, at: OfflineConfettiField.duration + 0.01, width: 375, height: 700)
            XCTAssertFalse(end.visible, "every piece is done when the shower is")
        }
    }

    func testConfettiHasLandedBeforeTheTimelinePauses() {
        // The slowest piece, starting last, must clear the bottom edge by the
        // end of the shower — otherwise it would vanish mid-air on screen.
        let pieces = OfflineConfettiField.pieces(count: 200, seed: 99, colours: 4)
        for piece in pieces {
            let spot = OfflineConfettiField.spot(piece, at: OfflineConfettiField.duration, width: 375, height: 700)
            XCTAssertGreaterThanOrEqual(spot.y, 700, "a piece still on screen when the shower ends")
        }
    }
}
