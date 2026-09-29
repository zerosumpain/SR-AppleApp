import XCTest
@testable import SRAppleApp

/// Liar's Dice: the spec's wire contract, and the rules the phone applies
/// itself — which bids are legal, the smallest raise, which dice count.
final class LiarsDiceTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    // MARK: - The wire (the spec's JSON)

    private let biddingJSON = #"""
    { "id":"g_l", "game":"liars-dice", "difficulty":"medium", "phase":"bidding",
      "hostId":"p_a", "meId":"p_b",
      "dicePerPlayer":5, "wildOnes":true, "rule":"Ones are wild.", "minFace":2, "turnMs":45000,
      "round":2, "starterId":"p_a", "turnId":"p_b", "totalDice":9,
      "startedAt":1790000000000, "phaseEndsAt":1790000045000,
      "bid":{"playerId":"p_a","quantity":3,"face":4,"auto":true},
      "bids":[{"playerId":"p_a","quantity":3,"face":4,"auto":true}],
      "players":[{"id":"p_a","name":"Sam","status":"joined","isHost":true,"seated":true,"diceCount":4,"out":false,"dice":null},
                 {"id":"p_b","name":"John","status":"joined","isHost":false,"seated":true,"diceCount":5,"out":false,
                  "dice":[1,4,4,6,2]}],
      "reveal":null, "standings":null, "winnerIds":[], "serverNow":1790000010000 }
    """#

    func testABiddingRoomDecodesFromTheContract() throws {
        let room = try decode(biddingJSON)
        XCTAssertEqual(room.kind, .liarsDice)
        XCTAssertEqual(room.phase, .unknown, "the shared phase has no `bidding`")
        XCTAssertEqual(LiarsDiceScreenPhase.of(room), .bidding)
        let state = try XCTUnwrap(room.liarsDice)
        XCTAssertEqual(state.phase, .bidding)
        XCTAssertEqual(state.dicePerPlayer, 5)
        XCTAssertTrue(state.wildOnes)
        XCTAssertEqual(state.minFace, 2)
        XCTAssertEqual(state.turnMs, 45_000)
        XCTAssertEqual(state.round, 2)
        XCTAssertEqual(state.turnId, "p_b")
        XCTAssertEqual(state.totalDice, 9)
        XCTAssertEqual(state.bid, LiarsDiceBid(playerId: "p_a", quantity: 3, face: 4, auto: true))
        XCTAssertEqual(state.bids.count, 1)
        XCTAssertNil(state.reveal)
        XCTAssertEqual(state.seat("p_b")?.dice, [1, 4, 4, 6, 2])
        XCTAssertNil(state.seat("p_a")?.dice, "another player's cup stays down")
        XCTAssertEqual(state.seat("p_a")?.diceCount, 4)
    }

    func testARevealAndAFinishDecode() throws {
        let json = #"""
        { "id":"g_l", "game":"liars-dice", "difficulty":"easy", "phase":"finished",
          "hostId":"p_a", "meId":"p_a", "wildOnes":false, "totalDice":2,
          "players":[{"id":"p_a","name":"Sam","status":"joined","seated":true,"diceCount":2,"out":false,"dice":[4,6]},
                     {"id":"p_b","name":"John","status":"left","seated":true,"diceCount":0,"out":true,"dice":[]}],
          "reveal":{"bid":{"playerId":"p_b","quantity":2,"face":4,"auto":false},"challengerId":"p_a","auto":true,
                    "count":1,"loserId":"p_b","eliminated":true,
                    "dice":[{"playerId":"p_a","dice":[4,6]},{"playerId":"p_b","dice":[5]}]},
          "standings":[{"id":"p_a","name":"Sam","place":1,"dice":2,"outRound":null,"left":false},
                       {"id":"p_b","name":"John","place":2,"dice":0,"outRound":4,"left":true}],
          "winnerIds":["p_a"], "serverNow":1790000010000 }
        """#
        let room = try decode(json)
        XCTAssertEqual(room.phase, .finished)
        let state = try XCTUnwrap(room.liarsDice)
        XCTAssertFalse(state.wildOnes)
        XCTAssertEqual(state.minFace, 1, "no wilds: ones may be bid")
        let reveal = try XCTUnwrap(state.reveal)
        XCTAssertTrue(reveal.auto)
        XCTAssertFalse(reveal.bidStood)
        XCTAssertTrue(reveal.eliminated)
        XCTAssertEqual(reveal.dice.map(\.playerId), ["p_a", "p_b"])
        XCTAssertEqual(state.standings?.map(\.place), [1, 2])
        XCTAssertEqual(state.standings?.last?.left, true)
        XCTAssertEqual(state.standings?.last?.outRound, 4)
        XCTAssertEqual(room.standings?.map(\.id), ["p_a", "p_b"], "the shared standings read the same rows")
        XCTAssertEqual(room.winnerIds, ["p_a"])
    }

    func testALobbyWithNoneOfItStillDecodes() throws {
        let json = #"""
        { "id":"g_l", "game":"liars-dice", "difficulty":"hard", "phase":"lobby",
          "hostId":"p_a", "meId":"p_a", "players":[{"id":"p_a","name":"Sam","status":"joined"}],
          "serverNow":1790000010000 }
        """#
        let room = try decode(json)
        XCTAssertEqual(LiarsDiceScreenPhase.of(room), .lobby)
        let state = try XCTUnwrap(room.liarsDice)
        XCTAssertEqual(state.dicePerPlayer, 5)
        XCTAssertNil(state.bid)
        XCTAssertEqual(state.bids, [])
    }

    func testOtherGamesCarryNoLiarsDice() throws {
        let json = #"{ "id":"g_t", "game":"tap-duel", "phase":"lobby", "serverNow":1 }"#
        XCTAssertNil(try decode(json).liarsDice)
    }

    func testAPhaseCalledPlayingIsBidding() {
        XCTAssertEqual(LiarsDicePhase.from("playing"), .bidding)
        XCTAssertEqual(LiarsDicePhase.from("reveal"), .reveal)
        XCTAssertEqual(LiarsDicePhase.from("something-new"), .unknown)
        XCTAssertEqual(LiarsDicePhase.from(nil), .unknown)
    }

    // MARK: - Bids

    private func bid(_ q: Int, _ f: Int) -> LiarsDiceBid { LiarsDiceBid(playerId: "p_a", quantity: q, face: f) }

    func testABidMustBeStrictlyHigher() {
        let standing = bid(3, 4)
        XCTAssertTrue(LiarsDiceRules.isLegal(quantity: 4, face: 2, standing: standing, total: 10, wild: true), "more dice, any face")
        XCTAssertTrue(LiarsDiceRules.isLegal(quantity: 3, face: 5, standing: standing, total: 10, wild: true), "same dice, higher face")
        XCTAssertFalse(LiarsDiceRules.isLegal(quantity: 3, face: 4, standing: standing, total: 10, wild: true), "the same bid")
        XCTAssertFalse(LiarsDiceRules.isLegal(quantity: 3, face: 3, standing: standing, total: 10, wild: true), "lower face")
        XCTAssertFalse(LiarsDiceRules.isLegal(quantity: 2, face: 6, standing: standing, total: 10, wild: true), "fewer dice")
        XCTAssertEqual(LiarsDiceRules.problem(quantity: 3, face: 4, standing: standing, total: 10, wild: true),
                       "Bid more dice, or the same number of a higher face.")
    }

    func testOnesAndTheCap() {
        XCTAssertEqual(LiarsDiceRules.problem(quantity: 1, face: 1, standing: nil, total: 10, wild: true),
                       "Ones are wild — bid on 2 to 6.")
        XCTAssertTrue(LiarsDiceRules.isLegal(quantity: 1, face: 1, standing: nil, total: 10, wild: false))
        XCTAssertEqual(LiarsDiceRules.problem(quantity: 11, face: 3, standing: nil, total: 10, wild: false),
                       "There are only 10 dice in play.")
        XCTAssertEqual(LiarsDiceRules.problem(quantity: 0, face: 3, standing: nil, total: 10, wild: false),
                       "Bid at least one die.")
        XCTAssertEqual(LiarsDiceRules.problem(quantity: 1, face: 7, standing: nil, total: 10, wild: false),
                       "Pick a face from 1 to 6.")
        XCTAssertEqual(LiarsDiceRules.biddableFaces(wild: true), 2...6)
        XCTAssertEqual(LiarsDiceRules.biddableFaces(wild: false), 1...6)
    }

    func testThePickerOnlyOffersLegalBids() {
        let standing = bid(3, 4)
        XCTAssertEqual(LiarsDiceRules.minQuantity(standing: standing, total: 10, wild: true), 3)
        XCTAssertEqual(LiarsDiceRules.legalFaces(quantity: 3, standing: standing, total: 10, wild: true), [5, 6])
        XCTAssertEqual(LiarsDiceRules.legalFaces(quantity: 4, standing: standing, total: 10, wild: true), [2, 3, 4, 5, 6])
        XCTAssertEqual(LiarsDiceRules.legalFaces(quantity: 2, standing: standing, total: 10, wild: true), [])
        // A standing bid on sixes can only be raised by count.
        XCTAssertEqual(LiarsDiceRules.minQuantity(standing: bid(3, 6), total: 10, wild: true), 4)
        // Nothing past the table's dice: the only move left is a call.
        XCTAssertNil(LiarsDiceRules.minQuantity(standing: bid(10, 6), total: 10, wild: true))
        XCTAssertNil(LiarsDiceRules.startingBid(standing: bid(10, 6), total: 10, wild: true))
        XCTAssertEqual(LiarsDiceRules.fitFace(4, quantity: 3, standing: standing, total: 10, wild: true), 5)
        XCTAssertEqual(LiarsDiceRules.fitFace(6, quantity: 3, standing: standing, total: 10, wild: true), 6)
        XCTAssertNil(LiarsDiceRules.fitFace(4, quantity: 2, standing: standing, total: 10, wild: true))
    }

    func testTheStartingBidIsTheSmallestRaise() {
        let raise = LiarsDiceRules.startingBid(standing: bid(3, 4), total: 10, wild: true)
        XCTAssertEqual(raise?.quantity, 4)
        XCTAssertEqual(raise?.face, 4)
        // One more of the same face would pass the cap; a higher face at the same count does not.
        let squeeze = LiarsDiceRules.startingBid(standing: bid(10, 4), total: 10, wild: true)
        XCTAssertEqual(squeeze?.quantity, 10)
        XCTAssertEqual(squeeze?.face, 5)
        // Opening: one of my best face, clamped to what may be bid.
        let open = LiarsDiceRules.startingBid(standing: nil, total: 10, wild: true, preferred: 1)
        XCTAssertEqual(open?.quantity, 1)
        XCTAssertEqual(open?.face, 2)
    }

    // MARK: - Counting

    func testWildOnesCountTowardsEveryFace() {
        let cups = [[1, 4, 4, 6, 2], [3, 1, 4]]
        XCTAssertEqual(LiarsDiceRules.tally(cups, face: 4, wild: true), 5)
        XCTAssertEqual(LiarsDiceRules.tally(cups, face: 4, wild: false), 3)
        XCTAssertEqual(LiarsDiceRules.tally(cups, face: 1, wild: false), 2)
        XCTAssertTrue(LiarsDiceRules.counts(1, towards: 6, wild: true))
        XCTAssertFalse(LiarsDiceRules.counts(1, towards: 6, wild: false))
    }

    func testMyMostCommonFaceIgnoresOnesAndPrefersHigh() {
        XCTAssertEqual(LiarsDiceRules.mostCommonFace([2, 2, 5, 5, 1], wild: true), 5)
        XCTAssertEqual(LiarsDiceRules.mostCommonFace([3, 3, 3, 6], wild: false), 3)
        XCTAssertNil(LiarsDiceRules.mostCommonFace([], wild: true))
    }

    // MARK: - Copy

    func testBidsAndRevealsReadAsSentences() throws {
        XCTAssertEqual(LiarsDiceRules.bidText(quantity: 1, face: 4), "one 4")
        XCTAssertEqual(LiarsDiceRules.bidText(quantity: 3, face: 6), "three 6s")
        XCTAssertEqual(LiarsDiceRules.bidText(quantity: 14, face: 5), "14 5s")
        let room = try decode(biddingJSON.replacingOccurrences(of: #""reveal":null"#, with: #"""
        "reveal":{"bid":{"playerId":"p_a","quantity":3,"face":4},"challengerId":"p_b","count":2,"loserId":"p_a","eliminated":false,"dice":[]}
        """#))
        let reveal = try XCTUnwrap(room.liarsDice?.reveal)
        let line = LiarsDiceRules.revealLine(reveal) { $0 == "p_b" ? "You" : "Sam" }
        XCTAssertEqual(line, "You called Sam’s three 4s. There were 2 — Sam loses a die.")
        XCTAssertEqual(GameKind.liarsDice.title, "Liar's Dice")
        XCTAssertEqual(GameDifficulty.hard.line(for: .liarsDice), "Ones are wild. 30 seconds a turn.")
    }

    func testTheNewGameSheetSendsDiceEach() {
        let body = LiarsDiceSettings(difficulty: .medium, dice: 3).createBody(invite: ["p_b"])
        XCTAssertEqual(body.game, "liars-dice")
        XCTAssertEqual(body.dice, 3)
        XCTAssertEqual(body.invite, ["p_b"])
    }

    func testTheTurnBarEmpties() {
        XCTAssertEqual(LiarsDiceRules.turnLeft(endsAt: 1_000_045_000, turnMs: 45_000, now: 1_000_000_000), 1)
        XCTAssertEqual(LiarsDiceRules.turnLeft(endsAt: 1_000_045_000, turnMs: 45_000, now: 1_000_022_500), 0.5, accuracy: 0.001)
        XCTAssertEqual(LiarsDiceRules.turnLeft(endsAt: 1_000_045_000, turnMs: 45_000, now: 1_000_050_000), 0)
        XCTAssertEqual(LiarsDiceRules.turnLeft(endsAt: nil, turnMs: 45_000, now: 1), 1)
    }
}
