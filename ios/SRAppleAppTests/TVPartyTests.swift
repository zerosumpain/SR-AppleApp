import XCTest
@testable import SRAppleApp

/// sr. tv: the QR's deep link, the party as the site sends it, and what the
/// waiting screen does with it.
final class TVPartyTests: XCTestCase {

    // MARK: The link

    func testAJoinLinkCarriesItsCode() {
        XCTAssertEqual(TVPartyLink.from(url: URL(string: "sr://games/join/BCDF")!), .join(code: "BCDF"))
        XCTAssertEqual(TVPartyLink.from(url: URL(string: "sr://games/join/xzqt")!), .join(code: "XZQT"), "lower case is the same code")
        XCTAssertEqual(TVPartyLink.from(url: URL(string: "SR://Games/Join/HJKL")!), .join(code: "HJKL"))
    }

    func testABadCodeIsNotAJoin() {
        for raw in ["sr://games/join/ABCD",   // a vowel
                    "sr://games/join/BCD",    // too short
                    "sr://games/join/BCDFG",  // too long
                    "sr://games/join/BC1F",   // a digit
                    "sr://games/join/BCYF",   // Y is not in the alphabet
                    "sr://games/join",
                    "sr://games/join/BCDF/extra",
                    "https://strangeramblings.com/games/join/BCDF",
                    "sr://family/join/BCDF"] {
            XCTAssertNil(TVPartyLink.from(url: URL(string: raw)!), raw)
        }
    }

    func testAJoinShapedLinkIsNeverReadAsARoom() {
        let bad = URL(string: "sr://games/join/ABCD")!
        XCTAssertTrue(TVPartyLink.isJoinShaped(bad))
        XCTAssertTrue(TVPartyLink.isJoinShaped(URL(string: "sr://games/join/BCDF")!))
        XCTAssertFalse(TVPartyLink.isJoinShaped(URL(string: "sr://games/g_abc123")!))
        XCTAssertFalse(TVPartyLink.isJoinShaped(URL(string: "sr://games")!))
        // A room link is still a room link.
        XCTAssertEqual(GlanceLink.from(url: URL(string: "sr://games/g_abc123?game=azul")!), .games(room: "g_abc123", game: "azul"))
    }

    func testTheCodeShape() {
        XCTAssertEqual(TVPartyLink.code(" bcdf "), "BCDF")
        XCTAssertNil(TVPartyLink.code("../x"))
        XCTAssertNil(TVPartyLink.code(""))
        XCTAssertEqual(TVPartyLink.webPath(code: "BCDF"), "games/join/BCDF")
    }

    // MARK: The party

    private func answer(game: String?, roomId: String?, notice: String? = nil) throws -> TVPartyJoinAnswer {
        let gameJSON = game.map { "\"\($0)\"" } ?? "null"
        let roomJSON = roomId.map { "\"\($0)\"" } ?? "null"
        let noticeJSON = notice.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"party": {"id": "pt_0123456789ab", "code": "BCDF", "tvName": "Living room", "phase": "\(roomId == nil ? "lobby" : "playing")",
                   "locked": false, "game": \(gameJSON), "options": {"difficulty": "medium"},
                   "members": [{"id": "p_aaaaaaaaaaaa", "name": "Sam", "kind": "family", "online": true},
                               {"id": "v_bbbbbbbbbbbb", "name": "Nan", "kind": "guest", "online": false}],
                   "roomId": \(roomJSON), "notice": \(noticeJSON),
                   "games": [{"id": "snap-happy", "title": "Snap Happy", "min": 2, "max": 8},
                             {"id": "boggle", "title": "Kelloggle", "min": 1, "max": 8},
                             {"id": "iron-roads", "title": "Iron Roads", "min": 2, "max": 5}],
                   "joinPath": "/games/join/BCDF", "serverNow": 1793000000000},
         "me": {"id": "p_aaaaaaaaaaaa"}}
        """
        return try JSONDecoder().decode(TVPartyJoinAnswer.self, from: Data(json.utf8))
    }

    func testThePartyDecodes() throws {
        let a = try answer(game: "boggle", roomId: nil, notice: "Two more for Codenames.")
        XCTAssertEqual(a.me.id, "p_aaaaaaaaaaaa")
        XCTAssertNil(a.seat, "today's site sends no seat")
        XCTAssertEqual(a.party.code, "BCDF")
        XCTAssertEqual(a.party.tvName, "Living room")
        XCTAssertEqual(a.party.members.map(\.name), ["Sam", "Nan"])
        XCTAssertEqual(a.party.members.last?.kind, "guest")
        XCTAssertEqual(a.party.members.last?.online, false)
        XCTAssertEqual(a.party.notice, "Two more for Codenames.")
        XCTAssertNil(a.party.roomId)
        XCTAssertEqual(a.party.gameTitle, "Kelloggle")
        XCTAssertEqual(a.party.whoIsIn, "Sam and Nan")
    }

    func testAnUnknownGameStillDecodes() throws {
        let a = try answer(game: "biscuit-tower", roomId: "g_xyz")
        XCTAssertEqual(a.party.game, "biscuit-tower")
        XCTAssertEqual(a.party.roomId, "g_xyz")
        // Not in the TV's list either: the id, capitalised.
        XCTAssertEqual(a.party.gameTitle, "Biscuit Tower")
        let snap = try answer(game: "snap-happy", roomId: "g_xyz")
        XCTAssertEqual(snap.party.gameTitle, "Snap Happy", "the site's own name")
    }

    func testAPartyMissingWhatItCanDoWithout() throws {
        let json = #"{"party": {"id": "pt_1", "code": "BCDF", "notice": "  ", "roomId": ""}, "me": {"id": "p_1"}, "seat": "s"}"#
        let a = try JSONDecoder().decode(TVPartyJoinAnswer.self, from: Data(json.utf8))
        XCTAssertEqual(a.party.tvName, "the TV")
        XCTAssertEqual(a.party.phase, "lobby")
        XCTAssertNil(a.party.roomId, "an empty room id is no room")
        XCTAssertNil(a.party.notice, "a blank notice is none")
        XCTAssertTrue(a.party.members.isEmpty)
        XCTAssertEqual(a.seat, "s")
    }

    // MARK: What happens next

    func testWaitingUntilTheTVStarts() throws {
        XCTAssertEqual(TVPartyStep.next(try answer(game: "boggle", roomId: nil).party, opened: nil), .wait)
    }

    func testAKnownGameOpensItsRoom() throws {
        for game in ["boggle", "quiz-night", "codenames", "azul"] {
            XCTAssertEqual(TVPartyStep.next(try answer(game: game, roomId: "g_1").party, opened: nil),
                           .openRoom(id: "g_1", game: game), game)
        }
    }

    func testAGameThisAppCannotPlayOpensThePage() throws {
        for game in ["snap-happy", "biscuit-tower", "iron-roads", "lander"] {
            XCTAssertEqual(TVPartyStep.next(try answer(game: game, roomId: "g_1").party, opened: nil),
                           .openWeb(game: game), game)
        }
    }

    func testBackFromARunningGameDoesNotReopenIt() throws {
        let party = try answer(game: "azul", roomId: "g_1").party
        XCTAssertEqual(TVPartyStep.next(party, opened: "g_1"), .wait)
        let next = try answer(game: "codenames", roomId: "g_2").party
        XCTAssertEqual(TVPartyStep.next(next, opened: "g_1"), .openRoom(id: "g_2", game: "codenames"), "the TV's next game opens")
    }

    // MARK: Rooms and names remembered

    func testARoomRemembersItsParty() {
        let defaults = UserDefaults(suiteName: "TVPartyTests-\(UUID().uuidString)")!
        XCTAssertNil(TVPartyRooms.code(for: "g_1", defaults: defaults))
        TVPartyRooms.remember(room: "g_1", code: "BCDF", defaults: defaults)
        TVPartyRooms.remember(room: "g_1", code: "BCDF", defaults: defaults)
        XCTAssertEqual(TVPartyRooms.code(for: "g_1", defaults: defaults), "BCDF")
        for i in 0..<40 { TVPartyRooms.remember(room: "g_x\(i)", code: "HJKL", defaults: defaults) }
        XCTAssertNil(TVPartyRooms.code(for: "g_1", defaults: defaults), "only recent rooms are kept")
    }

    func testTheSiteNamesAGameThisAppDoesNotKnow() throws {
        let defaults = UserDefaults(suiteName: "TVPartyTests-\(UUID().uuidString)")!
        let party = try answer(game: nil, roomId: nil).party
        TVPartyTitles.learn(party.games, defaults: defaults)
        XCTAssertEqual(TVPartyTitles.title("snap-happy", defaults: defaults), "Snap Happy")
        XCTAssertNil(TVPartyTitles.title("boggle", defaults: defaults), "a game the app knows keeps the app's name")
        XCTAssertEqual(GameNames.capitalised("iron-roads"), "Iron Roads")
    }

    // MARK: The web view

    func testTheSeatCookieIsThePagesOwn() throws {
        let cookie = try XCTUnwrap(TVPartyWebSeat.cookie(seat: "pt_0123456789ab.p_aaaaaaaaaaaa.1793000000.abc",
                                                         partyId: "pt_0123456789ab", host: "strangeramblings.com", secure: true))
        XCTAssertEqual(cookie.name, "sr_seat_pt_0123456789ab")
        XCTAssertEqual(cookie.path, "/")
        XCTAssertTrue(cookie.isSecure)
        XCTAssertTrue(cookie.isHTTPOnly)
        XCTAssertNil(TVPartyWebSeat.cookie(seat: "x", partyId: "pt_1; Domain=evil", host: "strangeramblings.com", secure: true))
    }

    func testOnlyTheSitesPagesLoad() {
        let page = URL(string: "https://strangeramblings.com/games/join/BCDF")!
        XCTAssertTrue(TVPartyWebPolicy.allows(URL(string: "https://strangeramblings.com/games/join/BCDF")!, page: page))
        XCTAssertTrue(TVPartyWebPolicy.allows(URL(string: "https://strangeramblings.com/api/games/party/BCDF/join")!, page: page))
        XCTAssertFalse(TVPartyWebPolicy.allows(URL(string: "sr://games/join/BCDF")!, page: page), "the page's hand-off to the app")
        XCTAssertFalse(TVPartyWebPolicy.allows(URL(string: "https://example.com/")!, page: page))
        XCTAssertFalse(TVPartyWebPolicy.allows(URL(string: "http://strangeramblings.com/games/join/BCDF")!, page: page))
    }
}

/// Boggle's family name.
final class KelloggleTitleTests: XCTestCase {
    func testBoggleIsCalledKelloggle() {
        XCTAssertEqual(GameKind.boggle.title, "Kelloggle")
        XCTAssertEqual(GameKind.boggle.rawValue, "boggle", "rooms and scores still key on boggle")
        XCTAssertEqual(GameNames.title("boggle"), "Kelloggle")
        XCTAssertEqual(OfflineBoggleRules.info.title, "Kelloggle")
    }
}
