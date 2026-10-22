import XCTest
@testable import SRAppleApp

/// Homestead: the shared coordinate scheme (corner and side ids, neighbours,
/// ends, board counts), board-space pixels and the tap that maps back to a
/// spot, that a tap only ever lands on a spot the server listed, and decoding
/// the spec's wire and every demo fixture.
final class HomesteadTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    private func board(_ island: HomesteadIsland) -> HomesteadBoard {
        HomesteadBoard(hexes: island.hexes.map { HomesteadHex(coord: $0, tile: .fields, token: 5) }, harbours: [])
    }

    // MARK: - Geometry

    func testTheSixCornersOfAHexClockwiseFromTheTop() {
        let ids = HexCoord(0, 0).corners.map(\.id)
        XCTAssertEqual(ids, ["0,0,N", "1,-1,S", "0,1,N", "0,0,S", "-1,1,N", "0,-1,S"])
        XCTAssertEqual(HexCoord(-2, 1).corners.map(\.id), ["-2,1,N", "-1,0,S", "-2,2,N", "-2,1,S", "-3,2,N", "-2,0,S"])
    }

    func testTheSixSidesOfAHexClockwiseFromTheUpperRight() {
        XCTAssertEqual(HexCoord(0, 0).sides.map(\.id), ["0,0,NE", "1,0,W", "0,1,NW", "-1,1,NE", "0,0,W", "0,0,NW"])
    }

    func testEdgeEndsAreTheSpecTable() {
        func ends(_ id: String) -> [String] {
            let (a, b) = HomesteadEdge(id: id)!.ends
            return [a.id, b.id]
        }
        XCTAssertEqual(ends("2,-1,NE"), ["2,-1,N", "3,-2,S"])
        XCTAssertEqual(ends("2,-1,NW"), ["2,-2,S", "2,-1,N"])
        XCTAssertEqual(ends("2,-1,W"), ["1,0,N", "2,-2,S"])
    }

    func testEverySideJoinsTwoCornersOfEachHexItTouches() {
        for hex in HomesteadIsland.large.hexes {
            let corners = Set(hex.corners.map(\.id))
            let sides = hex.sides
            XCTAssertEqual(Set(sides.map(\.id)).count, 6)
            for side in sides {
                let (a, b) = side.ends
                XCTAssertTrue(corners.contains(a.id), "\(side.id) end \(a.id) is not a corner of \(hex.id)")
                XCTAssertTrue(corners.contains(b.id), "\(side.id) end \(b.id) is not a corner of \(hex.id)")
                XCTAssertTrue(side.hexes.contains(hex), "\(side.id) does not name \(hex.id) as a side")
            }
        }
    }

    func testCornerNeighboursAreOneSideAwayBothWays() {
        let s = 10.0
        for hex in HomesteadIsland.standard.hexes {
            for corner in hex.corners {
                XCTAssertEqual(corner.neighbours.count, 3)
                for n in corner.neighbours {
                    XCTAssertTrue(n.neighbours.contains(corner), "\(n.id) does not see \(corner.id)")
                    XCTAssertEqual(HomesteadPixels.distance(HomesteadPixels.point(corner, size: s), HomesteadPixels.point(n, size: s)),
                                   s, accuracy: 1e-9)
                }
                // The three sides that meet here each end here.
                for edge in corner.edges {
                    let (a, b) = edge.ends
                    XCTAssertTrue(a == corner || b == corner, "\(edge.id) does not end at \(corner.id)")
                }
                // And it is a corner of the three hexes that meet here.
                for h in corner.hexes { XCTAssertTrue(h.corners.contains(corner)) }
            }
        }
    }

    func testHexNeighboursAreTheSixAxialSteps() {
        XCTAssertEqual(Set(HexCoord(0, 0).neighbours.map(\.id)), ["1,0", "-1,0", "1,-1", "0,-1", "0,1", "-1,1"])
    }

    func testBoardCountsForBothIslands() {
        let standard = board(.standard)
        XCTAssertEqual(standard.hexes.count, 19)
        XCTAssertEqual(standard.vertexIds.count, 54)
        XCTAssertEqual(standard.edgeIds.count, 72)
        XCTAssertEqual(standard.coastIds.count, 30)
        let large = board(.large)
        XCTAssertEqual(large.hexes.count, 31)
        XCTAssertEqual(large.vertexIds.count, 84)
        XCTAssertEqual(large.edgeIds.count, 114)
        XCTAssertEqual(large.coastIds.count, 42)
    }

    func testACoastalCornerMayNameASeaHex() {
        let standard = board(.standard)
        // The upper-right corner of hex 2,-2 is the bottom corner of 3,-3, which is sea.
        XCTAssertTrue(standard.isVertex("3,-3,S"))
        XCTAssertNil(standard.hex("3,-3"))
        XCTAssertFalse(standard.isVertex("5,5,N"))
    }

    func testIdsParseOnlyInTheirCanonicalForm() {
        XCTAssertEqual(HexCoord(id: "-2,1"), HexCoord(-2, 1))
        XCTAssertNil(HexCoord(id: "+1,0"))
        XCTAssertNil(HexCoord(id: "-0,0"))
        XCTAssertNil(HexCoord(id: "1, 0"))
        XCTAssertNil(HexCoord(id: "01,0"))
        XCTAssertEqual(HomesteadVertex(id: "1,-1,S"), HomesteadVertex(1, -1, .s))
        XCTAssertNil(HomesteadVertex(id: "1,-1,E"))
        XCTAssertEqual(HomesteadEdge(id: "0,0,NW"), HomesteadEdge(0, 0, .nw))
        XCTAssertNil(HomesteadEdge(id: "0,0,SE"))
        XCTAssertEqual(HomesteadEdge(0, -3, .w).id, "0,-3,W")
    }

    func testPixelsFollowTheSpec() {
        let s = 20.0
        let c = HomesteadPixels.centre(HexCoord(1, -1), size: s)
        XCTAssertEqual(Double(c.x), s * 3.0.squareRoot() * 0.5, accuracy: 1e-9)
        XCTAssertEqual(Double(c.y), -1.5 * s, accuracy: 1e-9)
        let n = HomesteadPixels.point(HomesteadVertex(1, -1, .n), size: s)
        XCTAssertEqual(Double(n.y), Double(c.y) - s, accuracy: 1e-9)
    }

    func testIdToPointToNearestIdRoundTrips() {
        let standard = board(.standard)
        let s = HomesteadBoardView.unit
        let corners = standard.vertexIds.map { HomesteadTarget(tool: .cottage, id: $0) }
        for target in corners {
            let p = HomesteadTargets.point(target, size: s)!
            XCTAssertEqual(HomesteadTargets.hit(p, among: corners, size: s, reach: s * 0.4), target)
        }
        let sides = standard.edgeIds.map { HomesteadTarget(tool: .road, id: $0) }
        for target in sides {
            let p = HomesteadTargets.point(target, size: s)!
            XCTAssertEqual(HomesteadTargets.hit(p, among: sides, size: s, reach: s * 0.4), target)
        }
    }

    func testTheViewportRoundTripsAtAnyZoomAndPan() {
        let bounds = board(.large).bounds(size: 40)
        var v = HomesteadViewport(bounds: bounds, viewSize: CGSize(width: 390, height: 420))
        for (zoom, pan) in [(1.0, CGSize.zero), (2.5, CGSize(width: 40, height: -30)), (0.6, CGSize(width: -12, height: 9))] {
            v.zoom = zoom
            v.pan = pan
            let p = CGPoint(x: 33.5, y: -71.25)
            let back = v.toBoard(v.toScreen(p))
            XCTAssertEqual(Double(back.x), Double(p.x), accuracy: 1e-6)
            XCTAssertEqual(Double(back.y), Double(p.y), accuracy: 1e-6)
        }
        XCTAssertEqual(HomesteadViewport.clampZoom(5), 3)
        XCTAssertEqual(HomesteadViewport.clampZoom(0.1), 0.6)
    }

    // MARK: - Lit targets come from the legal lists

    func testATapOnlyEverReturnsALitSpot() throws {
        let room = try decode(SRDemoFixtures.homesteadRoom(id: SRDemoFixtures.demoHomesteadRoom, clock: .init(now: Date()))!)
        let state = try XCTUnwrap(room.homestead)
        let lit = HomesteadTargets.lit(state, picked: nil)
        let allowed = Set(state.legal.road.map { HomesteadTarget(tool: .road, id: $0) }
            + state.legal.cottage.map { HomesteadTarget(tool: .cottage, id: $0) }
            + state.legal.town.map { HomesteadTarget(tool: .town, id: $0) })
        XCTAssertFalse(lit.isEmpty)
        XCTAssertTrue(Set(lit).isSubset(of: allowed))
        // Tap every corner and side of the island: each answer is lit, or nothing.
        let s = HomesteadBoardView.unit
        var hits = 0
        for id in state.board.vertexIds {
            let p = HomesteadPixels.point(HomesteadVertex(id: id)!, size: s)
            if let hit = HomesteadTargets.hit(p, among: lit, size: s, reach: s * 0.5) {
                XCTAssertTrue(allowed.contains(hit))
                hits += 1
            }
        }
        for id in state.board.edgeIds {
            let p = HomesteadPixels.midpoint(HomesteadEdge(id: id)!, size: s)
            if let hit = HomesteadTargets.hit(p, among: lit, size: s, reach: s * 0.3) { XCTAssertTrue(allowed.contains(hit)) }
        }
        XCTAssertGreaterThan(hits, 0)
        // A tap far out at sea hits nothing.
        XCTAssertNil(HomesteadTargets.hit(CGPoint(x: 9999, y: 9999), among: lit, size: s, reach: s))
    }

    func testAPickedPieceLightsOnlyItsOwnSpots() throws {
        let state = try XCTUnwrap(try decode(SRDemoFixtures.homesteadRoom(id: SRDemoFixtures.demoHomesteadRoom, clock: .init(now: Date()))!).homestead)
        let roads = HomesteadTargets.lit(state, picked: .road)
        XCTAssertEqual(Set(roads.map(\.id)), Set(state.legal.road))
        XCTAssertTrue(roads.allSatisfy { $0.tool == .road })
        XCTAssertTrue(HomesteadTargets.lit(state, picked: .town).isEmpty, "no town is affordable in the fixture")
    }

    func testASpotTheBoardDoesNotHoldIsNeverLit() throws {
        var json = SRDemoFixtures.homesteadRoom(id: SRDemoFixtures.demoHomesteadSetupRoom, clock: .init(now: Date()))!
        json = json.replacingOccurrences(of: "\"cottage\":[", with: "\"cottage\":[\"9,9,N\",\"nonsense\",")
        let state = try XCTUnwrap(try decode(json).homestead)
        let lit = HomesteadTargets.lit(state, picked: nil)
        XCTAssertFalse(lit.isEmpty)
        XCTAssertFalse(lit.contains { $0.id == "9,9,N" || $0.id == "nonsense" })
    }

    func testHardLightsNothingUntilAPieceIsPicked() throws {
        var json = SRDemoFixtures.homesteadRoom(id: SRDemoFixtures.demoHomesteadRoom, clock: .init(now: Date()))!
        json = json.replacingOccurrences(of: "\"difficulty\":\"easy\"", with: "\"difficulty\":\"hard\"")
        let state = try XCTUnwrap(try decode(json).homestead)
        XCTAssertTrue(state.hard)
        XCTAssertTrue(HomesteadTargets.lit(state, picked: nil).isEmpty)
        XCTAssertFalse(HomesteadTargets.lit(state, picked: .road).isEmpty)
    }

    func testSetupLightsWhatItNeedsWhateverIsPicked() throws {
        let state = try XCTUnwrap(try decode(SRDemoFixtures.homesteadRoom(id: SRDemoFixtures.demoHomesteadSetupRoom, clock: .init(now: Date()))!).homestead)
        XCTAssertEqual(state.step, .setup)
        XCTAssertEqual(state.setup?.need, .cottage)
        let lit = HomesteadTargets.lit(state, picked: .road)
        XCTAssertEqual(Set(lit.map(\.id)), Set(state.legal.cottage))
        XCTAssertTrue(lit.allSatisfy { $0.tool == .cottage })
        // The distance rule holds in what the fixture offers.
        XCTAssertFalse(state.legal.cottage.contains("1,-1,N"))
        XCTAssertFalse(state.legal.cottage.contains("1,-2,S"), "next to Sam's cottage")
    }

    func testTheSpokenLabelNamesTheHexesAndTheirNumbers() throws {
        let state = try XCTUnwrap(try decode(SRDemoFixtures.homesteadRoom(id: SRDemoFixtures.demoHomesteadSetupRoom, clock: .init(now: Date()))!).homestead)
        // 0,0,N touches 0,0 (dunes), 0,-1 (quarry 6) and 1,-1 (fields 4).
        let line = HomesteadTargets.spoken(HomesteadTarget(tool: .cottage, id: "0,0,N"), in: state)
        XCTAssertTrue(line.hasPrefix("Cottage spot, "), line)
        XCTAssertTrue(line.contains("quarry 6"), line)
        XCTAssertTrue(line.contains("fields 4"), line)
        XCTAssertTrue(line.contains("dunes"), line)
    }

    // MARK: - The wire (the spec's JSON)

    private let specJSON = #"""
    {
      "id": "g_4be1c2d09a7f", "game": "homestead", "difficulty": "easy", "phase": "playing",
      "step": "main", "hostId": "p_a1", "meId": "p_a1", "pace": "async", "durable": true, "version": 212,
      "deadlineHours": 24, "vpTarget": 8, "island": "standard", "turn": 17, "activeId": "p_a1",
      "phaseEndsAt": 1761300000000, "startedAt": 1761200000000,
      "board": {
        "hexes": [
          { "id": "0,0", "q": 0, "r": 0, "kind": "dunes", "token": null, "pips": 0 },
          { "id": "1,-1", "q": 1, "r": -1, "kind": "fields", "resource": "grain", "token": 8, "pips": 5 }
        ],
        "harbours": [ { "edge": "1,-2,NE", "kind": "any", "rate": 3 }, { "edge": "2,-2,W", "kind": "wool", "rate": 2 } ]
      },
      "fox": "0,0",
      "buildings": [ { "at": "1,-1,N", "owner": "p_a1", "piece": "cottage" }, { "at": "0,1,S", "owner": "p_b2", "piece": "town" } ],
      "roads": [ { "at": "1,-1,NE", "owner": "p_a1" } ],
      "seats": ["p_a1", "p_b2", "p_c3"],
      "dice": { "a": 4, "b": 5, "total": 9, "by": "p_a1", "at": 1761213000000 },
      "setup": null,
      "freeRoads": 0,
      "discardOwed": {},
      "me": {
        "hand": { "timber": 2, "clay": 1, "wool": 0, "grain": 3, "stone": 1 },
        "cards": [ { "kind": "ranger", "new": false }, { "kind": "heirloom", "new": true } ],
        "vp": 6, "playedCardThisTurn": false,
        "rates": { "timber": 4, "clay": 4, "wool": 2, "grain": 4, "stone": 4 }
      },
      "legal": {
        "road": ["1,-1,NW", "2,-2,W"], "cottage": [], "town": ["1,-1,N"], "fox": [], "victims": {},
        "canRoll": false, "canBuy": true, "canEnd": true, "playable": ["ranger"], "canTrade": true
      },
      "players": [
        { "id": "p_a1", "name": "John", "status": "joined", "isHost": true, "seat": 0, "colour": "red",
          "handCount": 7, "cardCount": 2, "rangersPlayed": 1, "publicVp": 5, "trail": 4,
          "longestTrail": false, "chiefRanger": false, "pieces": { "road": 9, "cottage": 2, "town": 3 },
          "away": false, "sawInvite": true },
        { "id": "p_b2", "name": "Robin", "status": "joined", "isHost": false, "seat": 1, "colour": "blue",
          "handCount": 4, "cardCount": 1, "rangersPlayed": 3, "publicVp": 6, "trail": 5,
          "longestTrail": true, "chiefRanger": true, "pieces": { "road": 7, "cottage": 3, "town": 3 },
          "away": false, "sawInvite": true }
      ],
      "bank": { "timber": 12, "clay": 14, "wool": 15, "grain": 9, "stone": 13 },
      "deckCount": 17,
      "costs": { "road": { "timber": 1, "clay": 1 }, "cottage": { "timber": 1, "clay": 1, "wool": 1, "grain": 1 },
                 "town": { "grain": 2, "stone": 3 }, "card": { "wool": 1, "grain": 1, "stone": 1 } },
      "showCosts": true,
      "offers": [
        { "id": "o7", "from": "p_a1", "to": null, "give": { "grain": 1 }, "want": { "stone": 1 },
          "status": "open", "refusedBy": ["p_c3"], "counterTo": null, "at": 1761213100000 },
        { "id": "o8", "from": "p_b2", "to": ["p_a1"], "give": { "stone": 1 }, "want": { "grain": 2 },
          "status": "open", "refusedBy": [], "counterTo": "o7", "at": 1761213150000 }
      ],
      "hints": {
        "affordable": ["road", "town", "card"],
        "trades": [ { "give": "wool", "count": 2, "get": "stone", "for": "town" } ],
        "tip": "A town makes two of everything its cottage made."
      },
      "log": [
        { "n": 140, "at": 1761213000000, "kind": "roll", "by": "p_a1", "text": "John rolled 9.", "auto": false },
        { "n": 141, "at": 1761213000000, "kind": "produce", "by": null, "text": "9: John +1 grain, Robin +2 stone.", "auto": false },
        { "n": 139, "at": 1761212000000, "kind": "steal", "by": "p_b2", "text": "Robin's fox took a wool from you.", "auto": false }
      ],
      "result": null, "standings": null, "winnerIds": [], "serverNow": 1761213200000
    }
    """#

    func testTheSpecRoomDecodes() throws {
        let room = try decode(specJSON)
        XCTAssertEqual(room.kind, .homestead)
        XCTAssertEqual(HomesteadScreenPhase.of(room), .playing)
        let state = try XCTUnwrap(room.homestead)
        XCTAssertEqual(state.step, .main)
        XCTAssertEqual(state.pace, "async")
        XCTAssertTrue(state.isAsync)
        XCTAssertEqual(state.deadlineHours, 24)
        XCTAssertEqual(state.vpTarget, 8)
        XCTAssertEqual(state.island, .standard)
        XCTAssertEqual(state.turn, 17)
        XCTAssertTrue(state.isMyTurn)
        XCTAssertEqual(state.board.hexes.count, 2)
        XCTAssertEqual(state.board.hex("1,-1")?.tile, .fields)
        XCTAssertEqual(state.board.hex("1,-1")?.resource, .grain)
        XCTAssertEqual(state.board.hex("1,-1")?.hot, true)
        XCTAssertNil(state.board.hex("0,0")?.token)
        XCTAssertEqual(state.board.harbours.map(\.label), ["3:1", "2:1 wool"])
        XCTAssertEqual(state.fox, "0,0")
        XCTAssertEqual(state.building(at: "0,1,S")?.piece, .town)
        XCTAssertEqual(state.roads.first?.owner, "p_a1")
        XCTAssertEqual(state.dice?.total, 9)
        XCTAssertNil(state.setup)
        let me = try XCTUnwrap(state.me)
        XCTAssertEqual(me.hand[.grain], 3)
        XCTAssertEqual(me.hand.total, 7)
        XCTAssertEqual(me.cards.map(\.kind), [.ranger, .heirloom])
        XCTAssertEqual(me.cards.last?.new, true)
        XCTAssertEqual(me.vp, 6)
        XCTAssertEqual(me.rate(.wool), 2)
        XCTAssertEqual(state.legal.road, ["1,-1,NW", "2,-2,W"])
        XCTAssertEqual(state.legal.town, ["1,-1,N"])
        XCTAssertEqual(state.legal.playable, [.ranger])
        XCTAssertTrue(state.legal.canBuy && state.legal.canEnd && state.legal.canTrade)
        XCTAssertFalse(state.legal.canRoll)
        XCTAssertEqual(state.players.count, 2)
        let robin = try XCTUnwrap(state.player("p_b2"))
        XCTAssertEqual(robin.colour, .blue)
        XCTAssertEqual(robin.colour?.mark, .square)
        XCTAssertTrue(robin.longestTrail && robin.chiefRanger)
        XCTAssertEqual(robin.pieces[.road], 7)
        XCTAssertEqual(state.bank[.grain], 9)
        XCTAssertEqual(state.deckCount, 17)
        XCTAssertEqual(state.cost("town"), HomesteadCounts([.grain: 2, .stone: 3]))
        XCTAssertEqual(state.offers.count, 2)
        XCTAssertNil(state.offers[0].to)
        XCTAssertEqual(state.offers[1].counterTo, "o7")
        XCTAssertEqual(state.hints?.affordable, ["road", "town", "card"])
        XCTAssertEqual(state.hints?.trades.first?.forWhat, "town")
        XCTAssertEqual(state.log.count, 3)
        XCTAssertNil(state.result)
        XCTAssertNil(state.standings)
        // The shared room still reads around it.
        XCTAssertEqual(room.players.count, 2)
        XCTAssertNil(room.chess)
    }

    func testOfferRolesFromWhereEachPlayerSits() throws {
        let state = try XCTUnwrap(try decode(specJSON).homestead)
        // John is active: his own offer can be withdrawn; Robin's counter accepted.
        let mine = state.role(in: state.offers[0])
        XCTAssertTrue(mine.mine && mine.canCancel)
        XCTAssertFalse(mine.canAccept)
        let counter = state.role(in: state.offers[1])
        XCTAssertTrue(counter.canAccept, "John holds 3 grain, the counter wants 2")
        XCTAssertTrue(counter.canRefuse)
        XCTAssertFalse(counter.canCounter, "a counter cannot be countered")
        // As Robin, John's open offer can be accepted (Robin holds stone?) — her
        // hand is hidden, so the role uses her own `me`; from the room as Robin:
        let robinJSON = specJSON
            .replacingOccurrences(of: "\"meId\": \"p_a1\"", with: "\"meId\": \"p_b2\"")
            .replacingOccurrences(of: "\"hand\": { \"timber\": 2, \"clay\": 1, \"wool\": 0, \"grain\": 3, \"stone\": 1 }",
                                  with: "\"hand\": { \"stone\": 2 }")
        let asRobin = try XCTUnwrap(try decode(robinJSON).homestead)
        let robinsView = asRobin.role(in: asRobin.offers[0])
        XCTAssertTrue(robinsView.canAccept)
        XCTAssertFalse(robinsView.canCounter, "she already has an open counter to it")
        XCTAssertTrue(robinsView.canRefuse)
        let ownCounter = asRobin.role(in: asRobin.offers[1])
        XCTAssertTrue(ownCounter.canCancel)
        XCTAssertFalse(ownCounter.canAccept)
    }

    func testAWireMissingOptionalFieldsStillDecodes() throws {
        let room = try decode(#"{"id":"g_h","game":"homestead","phase":"lobby","serverNow":1}"#)
        let state = try XCTUnwrap(room.homestead)
        XCTAssertEqual(state.phase, .lobby)
        XCTAssertNil(state.step)
        XCTAssertTrue(state.board.hexes.isEmpty)
        XCTAssertEqual(state.legal, .nothing)
        XCTAssertEqual(state.vpTarget, 10)
        XCTAssertEqual(state.pace, "live")
        XCTAssertNil(state.me)
        XCTAssertEqual(state.cost("road"), HomesteadCounts([.timber: 1, .clay: 1]), "the spec's prices when none are sent")
        XCTAssertTrue(HomesteadTargets.lit(state, picked: .road).isEmpty)
    }

    func testUnknownKindsDecodeWithoutBlankingTheRoom() throws {
        let json = #"""
        {"id":"g_h","game":"homestead","phase":"playing","step":"harbour-party","serverNow":1,
         "board":{"hexes":[{"id":"0,0","q":0,"r":0,"kind":"volcano","token":null},{"q":"bad"}],"harbours":[]},
         "me":{"hand":{"timber":1,"gold":4},"cards":[{"kind":"telescope","new":false}]},
         "log":[{"n":1,"at":1,"kind":"fireworks","by":null,"text":"Something new.","auto":false}],
         "offers":[{"id":"o1"}],
         "legal":{"playable":["telescope"]}}
        """#
        let state = try XCTUnwrap(try decode(json).homestead)
        XCTAssertEqual(state.step, .unknown)
        XCTAssertEqual(state.board.hexes.count, 1, "the malformed hex drops out")
        XCTAssertEqual(state.board.hexes.first?.tile, .unknown)
        XCTAssertEqual(state.me?.hand.total, 1, "an unknown resource is ignored")
        XCTAssertEqual(state.me?.cards.first?.kind, .other("telescope"))
        XCTAssertEqual(state.log.first?.kind, "fireworks")
        XCTAssertEqual(state.log.first?.text, "Something new.")
        XCTAssertTrue(state.offers.isEmpty, "an offer without from drops out")
    }

    func testTheFinishedWireReadsStandingsAndHeirlooms() throws {
        let room = try decode(SRDemoFixtures.homesteadRoom(id: SRDemoFixtures.demoHomesteadDoneRoom, clock: .init(now: Date()))!)
        XCTAssertEqual(HomesteadScreenPhase.of(room), .finished)
        let state = try XCTUnwrap(room.homestead)
        XCTAssertEqual(state.result?.reason, "points")
        XCTAssertEqual(state.standings?.map(\.id), ["p_sam", "p_alex", "p_robin"])
        XCTAssertEqual(state.standings?.first?.vp, 10)
        XCTAssertEqual(state.player("p_sam")?.heirlooms, 1)
        XCTAssertEqual(room.standings?.first?.score, 10, "the shared standings carry score = final points")
        XCTAssertEqual(room.winnerIds, ["p_sam"])
        XCTAssertEqual(HomesteadText.outcome(state, name: { $0 == "p_alex" ? "You" : state.player($0)?.name ?? "" }),
                       "Sam reached 10 points first.")
    }

    // MARK: - Every demo fixture

    func testEveryDemoFixtureDecodes() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let ids = [SRDemoFixtures.demoHomesteadRoom, SRDemoFixtures.demoHomesteadSetupRoom,
                   SRDemoFixtures.demoHomesteadDiscardRoom, SRDemoFixtures.demoHomesteadDoneRoom]
            + SRDemoFixtures.demoHomesteadAsyncIds
        for id in ids {
            let json = try XCTUnwrap(SRDemoFixtures.homesteadRoom(id: id, clock: clock), id)
            let room = try decode(json)
            XCTAssertEqual(room.id, id)
            let state = try XCTUnwrap(room.homestead, id)
            XCTAssertFalse(state.board.hexes.isEmpty, id)
            XCTAssertEqual(state.board.harbours.count, state.board.hexes.count > 19 ? 11 : 9, id)
            for b in state.buildings { XCTAssertTrue(state.board.isVertex(b.at), "\(id): \(b.at)") }
            for r in state.roads { XCTAssertTrue(state.board.isEdge(r.at), "\(id): \(r.at)") }
            for h in state.board.harbours { XCTAssertTrue(state.board.coastIds.contains(h.edge), "\(id): \(h.edge)") }
            // The fixture's routing answers it too.
            let routed = SRDemoFixtures.demoRoom(id: id, meJoined: true, clock: clock)
            XCTAssertEqual(try decode(routed).homestead?.phase, state.phase, id)
        }
    }

    func testTheDemoLobbyListsTheHomesteadRooms() throws {
        let lobby = try JSONDecoder().decode(GamesLobby.self, from: Data(SRDemoFixtures.gamesLobby(.init(now: Date())).utf8))
        let rooms = lobby.rooms.filter { $0.game == "homestead" }.map(\.id)
        XCTAssertEqual(rooms, [SRDemoFixtures.demoHomesteadRoom, SRDemoFixtures.demoHomesteadSetupRoom,
                               SRDemoFixtures.demoHomesteadDiscardRoom, SRDemoFixtures.demoHomesteadDoneRoom])
    }

    func testTheFixtureIslandsHaveTheSpecCounts() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let main = try XCTUnwrap(try decode(SRDemoFixtures.homesteadRoom(id: SRDemoFixtures.demoHomesteadRoom, clock: clock)!).homestead)
        XCTAssertEqual(main.board.vertexIds.count, 54)
        XCTAssertEqual(main.board.edgeIds.count, 72)
        let discard = try XCTUnwrap(try decode(SRDemoFixtures.homesteadRoom(id: SRDemoFixtures.demoHomesteadDiscardRoom, clock: clock)!).homestead)
        XCTAssertEqual(discard.board.hexes.count, 31)
        XCTAssertEqual(discard.board.vertexIds.count, 84)
        XCTAssertEqual(discard.board.edgeIds.count, 114)
        // No two harbours share a corner.
        for state in [main, discard] {
            var seen = Set<String>()
            for h in state.board.harbours {
                let (a, b) = HomesteadEdge(id: h.edge)!.ends
                XCTAssertFalse(seen.contains(a.id) || seen.contains(b.id), h.edge)
                seen.insert(a.id); seen.insert(b.id)
            }
            // No two 6/8s touch.
            let hot = Set(state.board.hexes.filter(\.hot).map(\.coord))
            for h in hot { XCTAssertFalse(h.neighbours.contains { hot.contains($0) }, h.id) }
        }
    }

    func testTheDiscardFixtureOwesMeFour() throws {
        let state = try XCTUnwrap(try decode(SRDemoFixtures.homesteadRoom(id: SRDemoFixtures.demoHomesteadDiscardRoom, clock: .init(now: Date()))!).homestead)
        XCTAssertEqual(state.step, .discard)
        XCTAssertEqual(state.myDiscard, 4)
        XCTAssertEqual(Set(state.waitingOn), ["p_alex", "p_sam"])
        XCTAssertEqual(state.seated.count, 5)
    }

    // MARK: - Drafts and bodies

    func testTheDiscardDraftTakesExactlyWhatIsOwed() {
        let hand = HomesteadCounts([.timber: 3, .wool: 1])
        var draft = HomesteadDiscardDraft()
        draft.add(.wool, owed: 2, hand: hand)
        draft.add(.wool, owed: 2, hand: hand)
        XCTAssertEqual(draft.cards[.wool], 1, "only one wool is held")
        XCTAssertFalse(draft.ready(owed: 2, hand: hand))
        draft.add(.timber, owed: 2, hand: hand)
        draft.add(.timber, owed: 2, hand: hand)
        XCTAssertEqual(draft.cards.total, 2, "never more than owed")
        XCTAssertTrue(draft.ready(owed: 2, hand: hand))
    }

    func testATradeDraftNamesItsProblem() {
        let hand = HomesteadCounts([.grain: 2])
        XCTAssertEqual(HomesteadTradeDraft().problem(hand: hand), "Pick something to give.")
        XCTAssertEqual(HomesteadTradeDraft(give: HomesteadCounts([.grain: 1])).problem(hand: hand), "Pick something you want.")
        XCTAssertEqual(HomesteadTradeDraft(give: HomesteadCounts([.grain: 1]), want: HomesteadCounts([.grain: 1])).problem(hand: hand),
                       "A resource can't be on both sides.")
        XCTAssertEqual(HomesteadTradeDraft(give: HomesteadCounts([.grain: 3]), want: HomesteadCounts([.stone: 1])).problem(hand: hand),
                       "You don't have those cards.")
        XCTAssertNil(HomesteadTradeDraft(give: HomesteadCounts([.grain: 2]), want: HomesteadCounts([.stone: 1])).problem(hand: hand))
    }

    private func json(_ move: HomesteadMove) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(move)) as? [String: Any])
    }

    func testMoveBodiesMatchTheSpec() throws {
        XCTAssertEqual(try json(.roll) as NSDictionary, ["action": "roll"])
        XCTAssertEqual(try json(.build(.cottage, at: "1,-1,N")) as NSDictionary, ["action": "build", "piece": "cottage", "at": "1,-1,N"])
        XCTAssertEqual(try json(.play(.harvest, take: [.wool, .wool])) as NSDictionary, ["action": "play", "card": "harvest", "take": ["wool", "wool"]])
        XCTAssertEqual(try json(.play(.market, resource: .grain)) as NSDictionary, ["action": "play", "card": "market", "resource": "grain"])
        XCTAssertEqual(try json(.fox("0,0", victim: "p_b2")) as NSDictionary, ["action": "fox", "hex": "0,0", "victim": "p_b2"])
        XCTAssertEqual(try json(.fox("0,0", victim: nil)) as NSDictionary, ["action": "fox", "hex": "0,0"])
        XCTAssertEqual(try json(.discard(HomesteadCounts([.timber: 2, .wool: 0]))) as NSDictionary, ["action": "discard", "cards": ["timber": 2]])
        XCTAssertEqual(try json(.bank(give: .wool, get: .stone)) as NSDictionary, ["action": "bank", "give": "wool", "get": "stone"])
        let everyone = try json(.offer(give: HomesteadCounts([.grain: 1]), want: HomesteadCounts([.stone: 1]), to: nil))
        XCTAssertTrue(everyone["to"] is NSNull, "everyone is an explicit null")
        XCTAssertEqual(everyone["give"] as? [String: Int], ["grain": 1])
        XCTAssertEqual(try json(.offer(give: HomesteadCounts([.grain: 1]), want: HomesteadCounts([.stone: 1]), to: ["p_b2"]))["to"] as? [String], ["p_b2"])
        XCTAssertEqual(try json(.counter("o7", give: HomesteadCounts([.stone: 1]), want: HomesteadCounts([.grain: 2]))) as NSDictionary,
                       ["action": "counter", "offerId": "o7", "give": ["stone": 1], "want": ["grain": 2]])
        XCTAssertEqual(try json(.accept("o8")) as NSDictionary, ["action": "accept", "offerId": "o8"])
        XCTAssertEqual(try json(.refuse("o8")) as NSDictionary, ["action": "refuse", "offerId": "o8"])
        XCTAssertEqual(try json(.cancel("o7")) as NSDictionary, ["action": "cancel", "offerId": "o7"])
        XCTAssertEqual(try json(.skip) as NSDictionary, ["action": "skip"])
        XCTAssertEqual(try json(.end) as NSDictionary, ["action": "end"])
    }

    func testTheNewGameSheetSendsTheIsland() throws {
        let body = HomesteadSettings(difficulty: .medium, island: .large).createBody(invite: ["p_b"])
        XCTAssertEqual(body.game, "homestead")
        XCTAssertEqual(body.island, "large")
        XCTAssertEqual(HomesteadSettings.island(at: 9), .auto)
        XCTAssertEqual(GameKind(rawValue: "homestead"), .homestead)
        XCTAssertEqual(GameKind.homestead.title, "Homestead")
        XCTAssertEqual(GameKind.homestead.line, "Settle an island. Trade, build, race to the points.")
    }

    // MARK: - Sentences

    func testFiguresAndSentences() {
        XCTAssertEqual(HomesteadText.pips(6), 5)
        XCTAssertEqual(HomesteadText.pips(12), 1)
        XCTAssertEqual(HomesteadText.pips(7), 0)
        XCTAssertEqual(HomesteadText.pips(nil), 0)
        XCTAssertEqual(HomesteadText.timeLeft(42_000), "0:42")
        XCTAssertEqual(HomesteadText.timeLeft(25 * 60_000), "25 min")
        XCTAssertEqual(HomesteadText.timeLeft(21.5 * 3_600_000), "21 h")
        XCTAssertEqual(HomesteadCounts([.timber: 1, .clay: 1]).text(), "1 timber, 1 clay")
        XCTAssertEqual(HomesteadCounts().text(), "nothing")
        XCTAssertTrue(HomesteadCounts([.grain: 2, .stone: 3]).covers(HomesteadCounts([.grain: 2])))
        XCTAssertFalse(HomesteadCounts([.grain: 1]).covers(HomesteadCounts([.grain: 2])))
    }

    /// Original names only: none of the classic game's terms may reach a
    /// player. Checked over everything the app says about Homestead.
    func testNoBorrowedNamesInTheCopy() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        var copy = [GameKind.homestead.title, GameKind.homestead.line, GameKind.homestead.blurb]
        copy += GameDifficulty.allCases.map { $0.line(for: .homestead) }
        copy += [HomesteadCard.ranger, .heirloom, .pathfinders, .harvest, .market].flatMap { [$0.title, $0.line] }
        copy += HomesteadIslandChoice.allCases.map { HomesteadSettings.line(island: $0) }
        copy += [SRDemoFixtures.demoHomesteadRoom, SRDemoFixtures.demoHomesteadSetupRoom, SRDemoFixtures.demoHomesteadDiscardRoom,
                 SRDemoFixtures.demoHomesteadDoneRoom].compactMap { SRDemoFixtures.homesteadRoom(id: $0, clock: clock) }
        let text = copy.joined(separator: " ").lowercased()
        for banned in ["catan", "settler", "robber", "knight", "brick", "lumber", "sheep", "wheat", "ore",
                       "longest road", "largest army", "monopoly", "year of plenty", "road building", "victory point"] {
            let word = "\\b" + banned + "s?\\b"
            XCTAssertNil(text.range(of: word, options: .regularExpression), "\"\(banned)\" in the copy")
        }
    }
}
