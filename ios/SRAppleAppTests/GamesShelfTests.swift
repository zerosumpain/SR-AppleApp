import XCTest
@testable import SRAppleApp

final class GamesShelfTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)
    private let games = ["tap-duel", "wordle-race", "chess", "draw-guess", "boggle", "manhunt", "marble-race"]
    private let text = [
        "tap-duel": "Tap Duel wait for green",
        "wordle-race": "Wordle Race five-letter word",
        "chess": "Chess the classic",
        "draw-guess": "Draw & Guess drawing",
        "boggle": "Boggle letter dice",
        "manhunt": "Manhunt hide and seek outdoors",
        "marble-race": "Marble Race back a marble",
    ]

    // MARK: Categories

    func testKnownGamesHaveTheirShelf() {
        XCTAssertEqual(GameCategory.of("wordle-race"), .word)
        XCTAssertEqual(GameCategory.of("fake-artist"), .party)
        XCTAssertEqual(GameCategory.of("homestead"), .strategy)
        XCTAssertEqual(GameCategory.of("tap-duel"), .quick)
        XCTAssertEqual(GameCategory.of("marble-race"), .physics)
        XCTAssertEqual(GameCategory.of("manhunt"), .outdoor)
    }

    /// A game this build has never heard of still lands on a shelf.
    func testAnUnknownGameHasASensibleShelf() {
        XCTAssertEqual(GameCategory.of("moon-lander"), .physics)
        XCTAssertEqual(GameCategory.of("kart-race"), .physics)
        XCTAssertEqual(GameCategory.of("tilt-maze"), .physics)
        XCTAssertEqual(GameCategory.of("snap"), .quick)
    }

    func testTheFilterChipsAreOnlyShelvesWithGames() {
        XCTAssertEqual(GamesShelf.categories(["chess", "tap-duel"]), [.quick, .strategy])
    }

    // MARK: Shelves

    func testEveryGameIsOnExactlyOneShelf() {
        let sections = GamesShelf.sections(games: games, text: text, usage: HubUsage(), now: now, filter: nil, query: "")
        XCTAssertEqual(sections.flatMap(\.games).sorted(), games.sorted())
        XCTAssertEqual(sections.map(\.id), ["quick", "word", "party", "physics", "strategy", "outdoor"])
    }

    func testTheMostPlayedLeadsItsShelfAndTheFavourites() {
        var usage = HubUsage()
        usage.record("boggle", now: now)
        usage.record("boggle", now: now)
        usage.record("chess", now: now)
        let sections = GamesShelf.sections(games: games, text: text, usage: usage, now: now, filter: nil, query: "")
        XCTAssertEqual(sections.first { $0.id == "word" }?.games, ["boggle", "wordle-race"])
        XCTAssertEqual(GamesShelf.favourites(games, usage: usage, now: now), ["boggle", "chess"])
        XCTAssertEqual(GamesShelf.favourites(games, usage: HubUsage(), now: now), [])
    }

    func testAFilterLeavesOneShelf() {
        let sections = GamesShelf.sections(games: games, text: text, usage: HubUsage(), now: now, filter: "party", query: "")
        XCTAssertEqual(sections.map(\.id), ["party"])
        XCTAssertEqual(sections.first?.games, ["draw-guess"])

        var usage = HubUsage()
        usage.record("manhunt", now: now)
        let top = GamesShelf.sections(games: games, text: text, usage: usage, now: now, filter: GamesShelf.favouritesFilter, query: "")
        XCTAssertEqual(top.first?.games, ["manhunt"])
        XCTAssertTrue(GamesShelf.sections(games: games, text: text, usage: HubUsage(), now: now,
                                          filter: GamesShelf.favouritesFilter, query: "").isEmpty)
    }

    /// A search reads every game, whatever the filter, every word.
    func testASearchIgnoresTheFilter() {
        let hits = GamesShelf.sections(games: games, text: text, usage: HubUsage(), now: now, filter: "party", query: " RACE ")
        XCTAssertEqual(hits.first?.games, ["wordle-race", "marble-race"])
        let both = GamesShelf.sections(games: games, text: text, usage: HubUsage(), now: now, filter: nil, query: "marble back")
        XCTAssertEqual(both.first?.games, ["marble-race"])
        let shelf = GamesShelf.sections(games: games, text: text, usage: HubUsage(), now: now, filter: nil, query: "outdoor")
        XCTAssertEqual(shelf.first?.games, ["manhunt"])
        XCTAssertTrue(GamesShelf.sections(games: games, text: text, usage: HubUsage(), now: now, filter: nil, query: "zzz").isEmpty)
    }

    func testUsageKeepsUnderItsOwnKey() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "games-usage-test"))
        defaults.removePersistentDomain(forName: "games-usage-test")
        var usage = GameUsage.load(defaults)
        usage.record("chess", now: now)
        GameUsage.save(usage, defaults)
        XCTAssertEqual(GameUsage.load(defaults), usage)
        XCTAssertNil(defaults.data(forKey: HubUsage.key))
    }

    // MARK: The banner

    private func invite(_ id: String, ends: Double? = nil) -> LobbyBannerCandidate {
        LobbyBannerCandidate(roomId: id, game: "chess", gameTitle: "Chess", hostName: "Sam", kind: .invite, expiresAt: ends)
    }

    private func waiting(_ id: String, mine: Bool = false) -> LobbyBannerCandidate {
        LobbyBannerCandidate(roomId: id, game: "boggle", gameTitle: "Boggle", hostName: "Robin", kind: .waiting, mine: mine)
    }

    func testAnInviteComesBeforeALobbyImIn() {
        let pick = LobbyBannerPick.pick([waiting("w"), invite("a", ends: 900), invite("b", ends: 500)], dismissed: [], serverNow: 100)
        XCTAssertEqual(pick?.roomId, "b")
    }

    func testDismissedAndExpiredAreNotOffered() {
        XCTAssertEqual(LobbyBannerPick.pick([invite("a", ends: 50), invite("b"), waiting("w")], dismissed: ["b"], serverNow: 100)?.roomId, "w")
        XCTAssertNil(LobbyBannerPick.pick([invite("a")], dismissed: ["a"], serverNow: nil))
        // No server clock yet: nothing can be called expired.
        XCTAssertEqual(LobbyBannerPick.pick([invite("a", ends: 50)], dismissed: [], serverNow: nil)?.roomId, "a")
    }

    func testTheBannerSaysWhose() {
        XCTAssertEqual(invite("a").line, "Sam invited you to Chess")
        XCTAssertEqual(invite("a").action, "Join")
        XCTAssertEqual(waiting("w").line, "Robin’s Boggle is waiting to start")
        XCTAssertEqual(waiting("w", mine: true).line, "Your Boggle lobby is open")
        XCTAssertEqual(LobbyBannerPick.closedLine(by: "Dad", game: "Chess"), "Dad closed the Chess lobby.")
        XCTAssertEqual(LobbyBannerPick.closedLine(by: nil, game: "Chess"), "The Chess lobby was closed.")
    }

    // MARK: Wire

    func testTheSuggestionsDecodeLeniently() throws {
        let json = #"{"suggestions":[{"id":"s_1","name":"Moon lander","by":"Sam","votes":3,"voted":true},{"name":"no id"}],"parent":true}"#
        let list = try JSONDecoder().decode(GameSuggestionList.self, from: Data(json.utf8))
        // One malformed row drops the array to empty rather than throwing.
        XCTAssertTrue(list.parent)
        let one = try JSONDecoder().decode(GameSuggestion.self, from: Data(#"{"id":"s_1","name":"Moon lander","by":"Sam","votes":3,"voted":true}"#.utf8))
        XCTAssertEqual(one.byline, "Suggested by Sam · 3 want it")
        XCTAssertEqual(one.note, "")
        XCTAssertFalse(one.mine)
    }

    func testAnOpenLobbyDecodes() throws {
        let json = #"{"id":"g_1","game":"chess","hostName":"Sam","players":["Sam"],"invited":["Robin"],"expiresAt":123,"mine":false}"#
        let lobby = try JSONDecoder().decode(GameOpenLobby.self, from: Data(json.utf8))
        XCTAssertEqual(lobby, GameOpenLobby(id: "g_1", game: "chess", hostName: "Sam", players: ["Sam"], invited: ["Robin"], expiresAt: 123))
    }

    func testADraftIsReadyOnlyWithAName() {
        var draft = GameSuggestionDraft()
        XCTAssertFalse(draft.isReady)
        draft.name = "  Moon \n  lander  "
        XCTAssertTrue(draft.isReady)
        XCTAssertEqual(draft.cleanName, "Moon lander")
        draft.name = String(repeating: "a", count: 100)
        XCTAssertEqual(draft.cleanName.count, GameSuggestionDraft.maxName)
    }
}
