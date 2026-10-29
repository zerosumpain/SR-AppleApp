import XCTest
@testable import SRAppleApp

/// The Games page's plan: the hero card, NEW badges, quick filters, player
/// counts, the podium and the confetti.
final class GamesPagePlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000) // late Oct 2026
    private let games = ["tap-duel", "wordle-race", "pinball", "snake", "chess"]

    private func played(_ ids: [String]) -> HubUsage {
        var usage = HubUsage()
        for id in ids { usage.record(id, now: now) }
        return usage
    }

    func testNewBadgeOnlyForNewUnplayedGamesBeforeFebruary() {
        let none = HubUsage()
        XCTAssertTrue(GamesPagePlan.isNew("pinball", usage: none, now: now))
        XCTAssertFalse(GamesPagePlan.isNew("tap-duel", usage: none, now: now), "an old game is not new")
        XCTAssertFalse(GamesPagePlan.isNew("pinball", usage: played(["pinball"]), now: now), "played once, no longer news")
        let later = Date(timeIntervalSince1970: 1_801_440_000)
        XCTAssertFalse(GamesPagePlan.isNew("pinball", usage: none, now: later), "the badges retire in February")
    }

    func testSpotlightPrefersTheFavourite() {
        let pick = GamesPagePlan.spotlight(games: games, favourites: ["chess", "tap-duel"], usage: played(["chess"]), now: now)
        XCTAssertEqual(pick?.game, "chess")
        XCTAssertEqual(pick?.reason, .favourite)
    }

    func testSpotlightOffersANewGameAndChangesByDay() {
        let first = GamesPagePlan.spotlight(games: games, favourites: [], usage: HubUsage(), now: now)
        XCTAssertEqual(first?.reason, .new)
        XCTAssertTrue(["pinball", "snake"].contains(first?.game ?? ""))
        let next = GamesPagePlan.spotlight(games: games, favourites: [], usage: HubUsage(), now: now.addingTimeInterval(86_400))
        XCTAssertNotEqual(first?.game, next?.game, "two new games alternate day by day")
    }

    func testSpotlightFallsBackToTheFirstGame() {
        let pick = GamesPagePlan.spotlight(games: ["tap-duel", "chess"], favourites: [], usage: HubUsage(), now: now)
        XCTAssertEqual(pick?.game, "tap-duel")
        XCTAssertEqual(pick?.reason, .pick)
        XCTAssertNil(GamesPagePlan.spotlight(games: [], favourites: [], usage: HubUsage(), now: now))
    }

    func testSpotlightIgnoresAFavouriteNotOffered() {
        let pick = GamesPagePlan.spotlight(games: ["tap-duel"], favourites: ["hometowns"], usage: HubUsage(), now: now)
        XCTAssertEqual(pick?.game, "tap-duel")
    }

    func testNarrowKeepsOnlyTheGamesAskedForAndDropsEmptyShelves() {
        let sections = [
            GamesShelf.Section(id: "quick", title: "Quick", line: "Fast", games: ["tap-duel", "snake"]),
            GamesShelf.Section(id: "strategy", title: "Strategy", games: ["chess"]),
        ]
        let narrowed = GamesPagePlan.narrow(sections, keep: ["snake"])
        XCTAssertEqual(narrowed.map(\.id), ["quick"])
        XCTAssertEqual(narrowed.first?.games, ["snake"])
        XCTAssertEqual(narrowed.first?.line, "Fast", "a narrowed shelf keeps its line")
    }

    func testPlayersChipAndLine() {
        XCTAssertEqual(GamesPagePlan.playersChip("chess", onPhone: false), "2")
        XCTAssertEqual(GamesPagePlan.playersChip("mission", onPhone: false), "5–10")
        XCTAssertEqual(GamesPagePlan.playersChip("tap-duel", onPhone: false), "1+")
        XCTAssertEqual(GamesPagePlan.playersChip("snake", onPhone: true), "Phone")
        XCTAssertEqual(GamesPagePlan.playersLine("hometowns", onPhone: false), "Solo, or up to 6 players")
        XCTAssertEqual(GamesPagePlan.playersLine("liars-dice", onPhone: false), "2 to 5 players")
        XCTAssertEqual(GamesPagePlan.playersLine("chess", onPhone: false), "2 players")
        XCTAssertEqual(GamesPagePlan.playersLine("boggle", onPhone: false), "Solo, or with the family")
    }

    func testSeatsLine() {
        XCTAssertEqual(GamesPagePlan.seatsLine("homestead", joined: 1), "Needs 2 more players")
        XCTAssertEqual(GamesPagePlan.seatsLine("homestead", joined: 2), "Needs 1 more player")
        XCTAssertEqual(GamesPagePlan.seatsLine("homestead", joined: 4), "Room for 1 more")
        XCTAssertEqual(GamesPagePlan.seatsLine("chess", joined: 2), "Full")
        XCTAssertEqual(GamesPagePlan.seatsLine("chess", joined: 3), "Too many: 2 at most")
        XCTAssertNil(GamesPagePlan.seatsLine("tap-duel", joined: 1))
        XCTAssertEqual(GamesPagePlan.emptySeats("mission", joined: 0), 4, "never more than four empty seats drawn")
        XCTAssertEqual(GamesPagePlan.emptySeats("homestead", joined: 2), 1)
        XCTAssertEqual(GamesPagePlan.emptySeats("tap-duel", joined: 1), 0)
    }

    func testClocks() {
        XCTAssertEqual(GamesPagePlan.clock(161), "2:41")
        XCTAssertEqual(GamesPagePlan.clock(7), "0:07")
        XCTAssertEqual(GamesPagePlan.clock(-3), "0:00")
        XCTAssertEqual(GamesPagePlan.closesLine(secondsLeft: 161), "Closes in 2:41")
        XCTAssertEqual(GamesPagePlan.closesLine(secondsLeft: 0), "Closing…")
    }

    func testPodium() {
        let one = GamesPagePlan.podium(["a"])
        XCTAssertEqual(one.top, [])
        XCTAssertEqual(one.rest, ["a"])
        let five = GamesPagePlan.podium(["a", "b", "c", "d", "e"])
        XCTAssertEqual(five.top, ["a", "b", "c"])
        XCTAssertEqual(five.rest, ["d", "e"])
        let two = GamesPagePlan.podium(["a", "b"])
        XCTAssertEqual(two.top, ["a", "b"])
        XCTAssertEqual(GamesPagePlan.podiumOrder(3), [1, 0, 2])
        XCTAssertEqual(GamesPagePlan.podiumOrder(2), [1, 0])
        XCTAssertEqual(GamesPagePlan.podiumOrder(0), [])
    }

    func testEveryGameHasAMotifAndUnknownGetsDots() {
        XCTAssertEqual(GamesTileMotif.of("chess"), .checker)
        XCTAssertEqual(GamesTileMotif.of("snake"), .snake)
        XCTAssertEqual(GamesTileMotif.of("something-new"), .dots)
    }

    func testConfettiIsDeterministicAndInBounds() {
        let a = GameConfetti.pieces(count: 40, seed: 7)
        let b = GameConfetti.pieces(count: 40, seed: 7)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, GameConfetti.pieces(count: 40, seed: 8))
        for piece in a {
            XCTAssertTrue((0...1).contains(piece.x))
            XCTAssertTrue((0..<GameConfetti.colours).contains(piece.colour))
            XCTAssertTrue(piece.delay >= 0 && piece.delay <= 0.55)
        }
    }

    func testConfettiPoseOverTime() {
        let piece = GameConfettiPiece(x: 0.5, drift: 0.1, speed: 0.5, delay: 0.2, spin: 1, size: 6, colour: 0, shape: 0, phase: 0)
        XCTAssertNil(GameConfetti.pose(piece, at: 0.1), "not yet thrown")
        let early = GameConfetti.pose(piece, at: 0.5)
        let later = GameConfetti.pose(piece, at: 1.2)
        XCTAssertNotNil(early)
        XCTAssertNotNil(later)
        XCTAssertGreaterThan(later?.y ?? 0, early?.y ?? 0, "confetti falls")
        XCTAssertEqual(early?.opacity, 1)
        XCTAssertNil(GameConfetti.pose(piece, at: GameConfetti.duration), "the burst is over")
        let fading = GameConfetti.pose(GameConfettiPiece(x: 0.5, drift: 0, speed: 0.01, delay: 0, spin: 0, size: 6, colour: 0, shape: 1, phase: 0),
                                       at: GameConfetti.duration - 0.3)
        XCTAssertNotNil(fading)
        XCTAssertLessThan(fading?.opacity ?? 1, 1, "it fades at the end")
    }
}
