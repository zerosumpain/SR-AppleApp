import XCTest
@testable import SRAppleApp

/// The Games widget: the snapshot of a lobby, the thin lobby a widget reads
/// for itself, its words, timeline and link.
///
/// Foundation only: `scripts/home-check.sh` runs this file on Linux too.
final class GamesWidgetTests: XCTestCase {

    /// Tuesday 27 October 2026, 10:00 in London (GMT).
    private let ten = Date(timeIntervalSince1970: 1_793_095_200)
    private var ms: Double { ten.timeIntervalSince1970 * 1000 }
    private let titles = ["chess": "Chess", "quiz-night": "Quiz Night", "wordle-race": "Wordle Race", "homestead": "Homestead"]

    private typealias Invite = GamesWidgetFeed.Invite
    private typealias Room = GamesWidgetFeed.Room

    private var feed: GamesWidgetFeed {
        GamesWidgetFeed(
            invites: [
                Invite(roomId: "i1", game: "quiz-night", hostName: "Robin Lee", expiresAt: ms + 9 * 60_000),
                Invite(roomId: "i2", game: "chess", hostName: "Kit", expiresAt: ms - 60_000),
            ],
            rooms: [
                Room(id: "r1", game: "homestead", phase: "playing", hostName: "Sam", myTurn: true),
                Room(id: "r2", game: "chess", phase: "playing", hostName: "Kit", myTurn: true, dueAt: ms + 21 * 3_600_000),
                Room(id: "r3", game: "wordle-race", phase: "finished", hostName: "Sam", updatedAt: ms - 3 * 3_600_000),
                Room(id: "r4", game: "chess", phase: "finished", hostName: "Robin", updatedAt: ms - 26 * 3_600_000),
                Room(id: "r5", game: "space-race", phase: "playing", hostName: "Robin", waitingFor: ["Robin"]),
                Room(id: "r6", game: "chess", phase: "lobby", hostName: "You"),
                Room(id: "r7", game: "chess", phase: "closed", hostName: "Robin"),
            ],
            serverNow: ms
        )
    }

    // MARK: - Snapshot

    func testALapsedInviteIsLeftOut() {
        let s = GamesWidget.snapshot(feed, titles: titles, now: ten)
        XCTAssertEqual(s.invites.map(\.roomId), ["i1"])
        XCTAssertEqual(s.invites.first?.title, "Quiz Night")
        XCTAssertEqual(s.invites.first?.at, ten.addingTimeInterval(9 * 60))
    }

    func testMovesAreSoonestDeadlineFirst() {
        let s = GamesWidget.snapshot(feed, titles: titles, now: ten)
        XCTAssertEqual(s.moves.map(\.roomId), ["r2", "r1"], "a deadline before none")
        XCTAssertEqual(s.playing, 1, "a game on the go not waiting on me; lobbies and closed rooms are not")
    }

    func testTheLastResultIsTheNewestFinished() {
        let s = GamesWidget.snapshot(feed, titles: titles, now: ten)
        XCTAssertEqual(s.last?.roomId, "r3")
        XCTAssertEqual(s.last?.kind, .result)
    }

    func testTheServersClockIsPutOnThePhones() {
        // The site's clock runs two minutes ahead of this phone's: an invite
        // lapsing nine minutes after the site's now lapses seven after ours.
        var skewed = feed
        skewed.serverNow = ms + 120_000
        let s = GamesWidget.snapshot(skewed, titles: titles, now: ten)
        XCTAssertEqual(s.invites.first?.at, ten.addingTimeInterval(7 * 60))
    }

    func testTimesAreRoundedSoJitterIsNoChange() {
        var a = feed, b = feed
        a.serverNow = ms + 120
        b.serverNow = ms + 480
        XCTAssertTrue(GamesWidget.snapshot(a, titles: titles, now: ten)
            .sameContent(as: GamesWidget.snapshot(b, titles: titles, now: ten.addingTimeInterval(1))))
    }

    func testAnUnknownGameIsNamedFromItsKind() {
        XCTAssertEqual(GamesWidget.title("space-race", titles: titles), "Space Race")
        XCTAssertEqual(GamesWidget.title("chess", titles: titles), "Chess")
    }

    func testTheShelfKeepsOnlyTheTitlesItNames() {
        let s = GamesWidget.snapshot(feed, titles: titles.merging(["boggle": "Boggle"]) { a, _ in a }, now: ten)
        XCTAssertNil(s.titles["boggle"])
        XCTAssertEqual(s.titles["quiz-night"], "Quiz Night")
    }

    func testLiveDropsInvitesThatLapseLater() {
        let s = GamesWidget.snapshot(feed, titles: titles, now: ten)
        XCTAssertEqual(GamesWidget.live(s, now: ten.addingTimeInterval(10 * 60)).invites.count, 0)
        XCTAssertEqual(GamesWidget.live(s, now: ten).invites.count, 1)
    }

    // MARK: - The wire

    func testTheFeedDecodesLeniently() throws {
        let json = """
        {"me":{"id":"p1","name":"Sam"},"serverNow":1793095200000,
         "invites":[{"roomId":"i1","game":"chess","hostName":"Kit","expiresAt":1793095800000},{"game":"no-room"}],
         "rooms":[{"id":"r1","game":"chess","phase":"playing","hostName":"Kit","myTurn":true,"summary":"  "},
                  {"id":"r2","phase":"racing"}],
         "paces":{"chess":["live","async"]}}
        """
        let feed = try JSONDecoder().decode(GamesWidgetFeed.self, from: Data(json.utf8))
        XCTAssertEqual(feed.invites.map(\.roomId), ["i1"], "one bad invite costs that invite")
        XCTAssertEqual(feed.rooms.count, 2)
        XCTAssertNil(feed.rooms[0].summary, "a blank summary is none")
        XCTAssertEqual(feed.rooms[1].game, "game")
        XCTAssertEqual(feed.serverNow, 1_793_095_200_000)
    }

    func testAnEmptyLobbyDecodes() throws {
        let feed = try JSONDecoder().decode(GamesWidgetFeed.self, from: Data("{}".utf8))
        XCTAssertTrue(feed.invites.isEmpty && feed.rooms.isEmpty)
        XCTAssertEqual(feed.serverNow, 0)
    }

    // MARK: - Words

    func testHeadlines() {
        let s = GamesWidget.snapshot(feed, titles: titles, now: ten)
        XCTAssertEqual(GamesWidget.headline(s), "1 invite")
        var moves = s
        moves.invites = []
        XCTAssertEqual(GamesWidget.headline(moves), "2 waiting on you")
        moves.moves.removeLast()
        XCTAssertEqual(GamesWidget.headline(moves), "Your move")
        moves.moves = []
        XCTAssertEqual(GamesWidget.headline(moves), "All quiet")
        XCTAssertEqual(GamesWidget.waiting(s), 3)
    }

    func testRowDetails() throws {
        let s = GamesWidget.snapshot(feed, titles: titles, now: ten)
        XCTAssertEqual(GamesWidget.detail(try XCTUnwrap(s.invites.first), now: ten), "From Robin")
        XCTAssertEqual(GamesWidget.detail(try XCTUnwrap(s.moves.first), now: ten), "Your move · 21 h left")
        XCTAssertEqual(GamesWidget.detail(try XCTUnwrap(s.moves.last), now: ten), "Your move")
        XCTAssertEqual(GamesWidget.detail(try XCTUnwrap(s.last), now: ten), "Finished · 3h")
    }

    func testTimeLeft() {
        XCTAssertEqual(GamesWidget.left(until: ten.addingTimeInterval(50 * 3600), now: ten), "2 days left")
        XCTAssertEqual(GamesWidget.left(until: ten.addingTimeInterval(21.9 * 3600), now: ten), "21 h left")
        XCTAssertEqual(GamesWidget.left(until: ten.addingTimeInterval(61), now: ten), "2 min left")
        XCTAssertEqual(GamesWidget.left(until: ten.addingTimeInterval(-1), now: ten), "Time's up")
    }

    func testRowsArePressingFirst() {
        let s = GamesWidget.snapshot(feed, titles: titles, now: ten)
        XCTAssertEqual(GamesWidget.rows(s, limit: 3).map(\.kind), [.invite, .move, .move])
        XCTAssertEqual(GamesWidget.rows(s, limit: 9).last?.kind, .result)
    }

    // MARK: - Link and timeline

    func testOneThingToDoOpensItsRoom() {
        var s = GamesWidget.snapshot(feed, titles: titles, now: ten)
        XCTAssertEqual(GamesWidget.url(s), GlanceLink.gamesURL)
        s.moves = []
        XCTAssertEqual(GamesWidget.url(s).absoluteString, "sr://games/i1?game=quiz-night")
        XCTAssertEqual(GamesWidget.url(nil), GlanceLink.gamesURL)
    }

    func testTheTimelineChangesAsInvitesLapse() {
        let s = GamesWidget.snapshot(feed, titles: titles, now: ten)
        let dates = GamesWidget.timeline(s, now: ten)
        XCTAssertEqual(dates.first, ten)
        XCTAssertTrue(dates.contains(ten.addingTimeInterval(9 * 60)))
        XCTAssertTrue(dates.contains(ten.addingTimeInterval(21 * 3600)))
    }
}
