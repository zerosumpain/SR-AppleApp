import Foundation

// MARK: - Demo Homestead
//
// `-SRDemo` rooms for Homestead. Synthetic throughout. Four rooms of a fixed
// standard island (Alex, Sam, Robin): placing a first cottage in setup; Alex's
// main step with an offer of Alex's out, a counter from Sam and Robin's "no
// thanks"; a 7 on the large island with five at the table, Alex owing four
// cards; and a finished game Sam won. The two durable lobby rows the durable
// branch lists (`g_demo_homestead_mine`, `g_demo_homestead_waiting`) answer
// here too: Alex's move over days, and one waiting on Sam to roll.
//
// The legal spots are worked out from the geometry so the fixture lights
// believable places. That is a FIXTURE convenience: the app itself never
// decides legality, it draws the server's `legal`.

extension SRDemoFixtures {

    static let demoHomesteadRoom = "g_demo_homestead"
    static let demoHomesteadSetupRoom = "g_demo_homestead_setup"
    static let demoHomesteadDiscardRoom = "g_demo_homestead_discard"
    static let demoHomesteadDoneRoom = "g_demo_homestead_done"
    /// The durable branch's two lobby rows (its constants live there).
    static let demoHomesteadAsyncIds = ["g_demo_homestead_mine", "g_demo_homestead_waiting"]

    /// The rooms for the lobby's "Your games", left out of the store shots as
    /// Categories' are.
    static let homesteadLobbyRows = #"""
    {"id": "g_demo_homestead", "game": "homestead", "phase": "playing", "hostName": "Alex"},
                       {"id": "g_demo_homestead_setup", "game": "homestead", "phase": "playing", "hostName": "Sam"},
                       {"id": "g_demo_homestead_discard", "game": "homestead", "phase": "playing", "hostName": "Kit"},
                       {"id": "g_demo_homestead_done", "game": "homestead", "phase": "finished", "hostName": "Sam"},
    """#

    /// The room for `id`, or nil when it is not one of Homestead's.
    static func homesteadRoom(id: String, clock: DemoClock) -> String? {
        switch id {
        case demoHomesteadRoom: return homesteadMain(id: id, clock: clock, pace: "live")
        case "g_demo_homestead_mine": return homesteadMain(id: id, clock: clock, pace: "async")
        case "g_demo_homestead_waiting": return homesteadWaiting(id: id, clock: clock)
        case demoHomesteadSetupRoom: return homesteadSetup(clock: clock)
        case demoHomesteadDiscardRoom: return homesteadDiscard(clock: clock)
        case demoHomesteadDoneRoom: return homesteadDone(clock: clock)
        default: return nil
        }
    }

    // MARK: The islands

    /// The fixed standard island: tiles and tokens over the 19 hexes in id
    /// order (rows top to bottom). No two 6/8s touch; the dunes are in the middle.
    static let homesteadStandardLayout: [(HomesteadTile, Int?)] = [
        (.woods, 10), (.meadow, 2), (.fields, 9),
        (.claypit, 12), (.quarry, 6), (.fields, 4), (.woods, 10),
        (.meadow, 9), (.woods, 11), (.dunes, nil), (.claypit, 3), (.meadow, 8),
        (.fields, 8), (.quarry, 3), (.woods, 4), (.meadow, 5),
        (.claypit, 5), (.fields, 6), (.quarry, 11),
    ]

    static var homesteadStandardHexes: [HomesteadHex] {
        zip(HomesteadIsland.standard.hexes, homesteadStandardLayout).map { coord, spot in
            HomesteadHex(coord: coord, tile: spot.0, token: spot.1)
        }
    }

    /// The large island: a seeded shuffle that keeps the 6s and 8s apart.
    static let homesteadLargeHexes: [HomesteadHex] = {
        var tiles: [HomesteadTile] = []
        for (tile, n) in [(HomesteadTile.woods, 6), (.claypit, 5), (.meadow, 6), (.fields, 6), (.quarry, 5), (.dunes, 3)] {
            tiles += Array(repeating: tile, count: n)
        }
        var tokens: [Int] = []
        for (token, n) in [(2, 2), (3, 3), (4, 3), (5, 3), (6, 3), (8, 3), (9, 3), (10, 3), (11, 3), (12, 2)] {
            tokens += Array(repeating: token, count: n)
        }
        let coords = HomesteadIsland.large.hexes
        var seed: UInt64 = 0x5EED_4F0C
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(truncatingIfNeeded: seed >> 33)
        }
        func shuffled<T>(_ items: [T]) -> [T] {
            var out = items
            for i in stride(from: out.count - 1, to: 0, by: -1) {
                out.swapAt(i, abs(next()) % (i + 1))
            }
            return out
        }
        var best: [HomesteadHex] = []
        for _ in 0..<2000 {
            let t = shuffled(tiles)
            var k = shuffled(tokens).makeIterator()
            let hexes = zip(coords, t).map { coord, tile in
                HomesteadHex(coord: coord, tile: tile, token: tile == .dunes ? nil : k.next())
            }
            best = hexes
            let hot = Set(hexes.filter(\.hot).map(\.coord))
            if !hot.contains(where: { h in h.neighbours.contains { hot.contains($0) } }) { break }
        }
        return best
    }()

    /// Harbours where the server would put them: coastal sides in clockwise
    /// order from straight up, spaced evenly, kinds dealt round.
    static func homesteadHarbours(_ hexes: [HomesteadHex], kinds: [String]) -> [[String: Any]] {
        let board = HomesteadBoard(hexes: hexes, harbours: [])
        let coast = board.coastIds.compactMap(HomesteadEdge.init(id:)).sorted { a, b in
            angle(HomesteadPixels.midpoint(a, size: 1)) < angle(HomesteadPixels.midpoint(b, size: 1))
        }
        return kinds.enumerated().map { i, kind in
            let edge = coast[i * coast.count / kinds.count]
            return ["edge": edge.id, "kind": kind, "rate": kind == "any" ? 3 : 2]
        }
    }

    private static func angle(_ p: CGPoint) -> Double {
        let a = atan2(Double(p.x), -Double(p.y))
        return a < 0 ? a + 2 * .pi : a
    }

    static let homesteadStandardHarbourKinds = ["any", "wool", "any", "timber", "clay", "any", "grain", "stone", "any"]
    static let homesteadLargeHarbourKinds = ["any", "wool", "any", "timber", "any", "clay", "grain", "any", "stone", "any", "any"]

    // MARK: Legal spots (fixture only)

    struct HomesteadDemoPieces {
        var buildings: [(at: String, owner: String, piece: HomesteadPiece)] = []
        var roads: [(at: String, owner: String)] = []

        func owner(of vertex: String) -> String? { buildings.first { $0.at == vertex }?.owner }
        func taken(_ edge: String) -> Bool { roads.contains { $0.at == edge } }
    }

    /// Corners that keep the distance rule.
    static func homesteadOpenCorners(_ board: HomesteadBoard, _ pieces: HomesteadDemoPieces) -> [String] {
        board.vertexIds.sorted().filter { id in
            guard pieces.owner(of: id) == nil, let v = HomesteadVertex(id: id) else { return false }
            return !v.neighbours.contains { pieces.owner(of: $0.id) != nil }
        }
    }

    /// Roads and cottages `me` could build, as the server would list them.
    static func homesteadLegal(_ board: HomesteadBoard, _ pieces: HomesteadDemoPieces, me: String,
                               road: Bool, cottage: Bool) -> (roads: [String], cottages: [String]) {
        var reach = Set(pieces.buildings.filter { $0.owner == me }.map(\.at))
        for r in pieces.roads where r.owner == me {
            guard let e = HomesteadEdge(id: r.at) else { continue }
            let (a, b) = e.ends
            for v in [a, b] where pieces.owner(of: v.id) == nil || pieces.owner(of: v.id) == me { reach.insert(v.id) }
        }
        var roads = Set<String>()
        for vid in reach {
            guard let v = HomesteadVertex(id: vid) else { continue }
            for e in v.edges where board.isEdge(e.id) && !pieces.taken(e.id) { roads.insert(e.id) }
        }
        let open = Set(homesteadOpenCorners(board, pieces))
        let onRoad = Set(pieces.roads.filter { $0.owner == me }.flatMap { r -> [String] in
            guard let e = HomesteadEdge(id: r.at) else { return [] }
            return [e.ends.0.id, e.ends.1.id]
        })
        return (road ? roads.sorted() : [], cottage ? open.intersection(onRoad).sorted() : [])
    }

    static func homesteadRates(_ board: HomesteadBoard, _ pieces: HomesteadDemoPieces, me: String) -> [String: Int] {
        var any = false
        var two = Set<String>()
        for b in pieces.buildings where b.owner == me {
            guard let harbour = board.harbour(at: b.at) else { continue }
            if harbour.kind == "any" { any = true } else { two.insert(harbour.kind) }
        }
        var out: [String: Int] = [:]
        for r in HomesteadResource.allCases { out[r.rawValue] = two.contains(r.rawValue) ? 2 : (any ? 3 : 4) }
        return out
    }

    // MARK: Building blocks

    static let homesteadCosts: [String: Any] = [
        "road": ["timber": 1, "clay": 1], "cottage": ["timber": 1, "clay": 1, "wool": 1, "grain": 1],
        "town": ["grain": 2, "stone": 3], "card": ["wool": 1, "grain": 1, "stone": 1],
    ]

    static func homesteadHexJSON(_ hexes: [HomesteadHex]) -> [[String: Any]] {
        hexes.map { h in
            var row: [String: Any] = ["id": h.id, "q": h.coord.q, "r": h.coord.r, "kind": h.tile.rawValue,
                                      "token": nsNull(h.token), "pips": h.pips]
            if let r = h.resource { row["resource"] = r.rawValue }
            return row
        }
    }

    static func homesteadPlayer(_ id: String, _ name: String, seat: Int, host: Bool, hand: Int, cards: Int,
                                vp: Int, rangers: Int = 0, trail: Int = 0, longest: Bool = false, chief: Bool = false,
                                pieces: (Int, Int, Int), finished: (heirlooms: Int, vp: Int)? = nil) -> [String: Any] {
        var row: [String: Any] = [
            "id": id, "name": name, "status": "joined", "isHost": host, "seat": seat,
            "colour": HomesteadColour.allCases[seat].rawValue, "handCount": hand, "cardCount": cards,
            "rangersPlayed": rangers, "publicVp": vp, "trail": trail, "longestTrail": longest, "chiefRanger": chief,
            "pieces": ["road": pieces.0, "cottage": pieces.1, "town": pieces.2], "away": false, "sawInvite": true,
            "score": vp,
        ]
        if let finished {
            row["heirlooms"] = finished.heirlooms
            row["vp"] = finished.vp
        }
        return row
    }

    static func homesteadLog(_ lines: [(String, String?, String)], at: Date) -> [[String: Any]] {
        lines.enumerated().map { i, line in
            ["n": 100 + i, "at": Int64(at.addingTimeInterval(Double(i - lines.count) * 20).timeIntervalSince1970 * 1000),
             "kind": line.0, "by": nsNull(line.1), "text": line.2, "auto": false]
        }
    }

    static func homesteadJSON(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    static func nsNull(_ value: Any?) -> Any { value ?? NSNull() }

    /// Everything every Homestead room says, with `extra` laid over it.
    static func homesteadBase(id: String, difficulty: String, host: String, hexes: [HomesteadHex], harbourKinds: [String],
                              pieces: HomesteadDemoPieces, players: [[String: Any]], seats: [String], clock: DemoClock,
                              extra: [String: Any]) -> String {
        let now = clock.now
        var room: [String: Any] = [
            "id": id, "game": "homestead", "difficulty": difficulty, "phase": "playing", "hostId": host, "meId": "p_alex",
            "pace": "live", "deadlineHours": NSNull(), "vpTarget": difficulty == "easy" ? 8 : 10,
            "island": hexes.count > 19 ? "large" : "standard",
            "rule": difficulty == "easy" ? "8 points wins · friendly fox · hints on" : "10 points wins",
            "turn": 9, "activeId": "p_alex",
            "phaseEndsAt": ms(now.addingTimeInterval(95)).asNumber, "startedAt": ms(now.addingTimeInterval(-1500)).asNumber,
            "board": ["hexes": homesteadHexJSON(hexes), "harbours": homesteadHarbours(hexes, kinds: harbourKinds)],
            "fox": hexes.first { $0.tile == .dunes }?.id ?? "0,0",
            "buildings": pieces.buildings.map { ["at": $0.at, "owner": $0.owner, "piece": $0.piece.rawValue] },
            "roads": pieces.roads.map { ["at": $0.at, "owner": $0.owner] },
            "seats": seats,
            "dice": ["a": 4, "b": 5, "total": 9, "by": "p_alex", "at": ms(now.addingTimeInterval(-40)).asNumber],
            "setup": NSNull(), "freeRoads": 0, "discardOwed": [String: Int](),
            "legal": ["road": [String](), "cottage": [String](), "town": [String](), "fox": [String](),
                      "victims": [String: [String]](), "canRoll": false, "canBuy": false, "canEnd": false,
                      "playable": [String](), "canTrade": false],
            "players": players,
            "bank": ["timber": 12, "clay": 14, "wool": 13, "grain": 9, "stone": 15],
            "deckCount": 17, "costs": homesteadCosts, "showCosts": difficulty != "hard",
            "offers": [[String: Any]](), "hints": NSNull(), "log": [[String: Any]](),
            "result": NSNull(), "standings": NSNull(), "winnerIds": [String](), "serverNow": ms(now).asNumber,
        ]
        for (key, value) in extra { room[key] = value }
        return homesteadJSON(room)
    }

    /// Alex, Sam and Robin on the standard island, nine turns in.
    static var homesteadMidGame: HomesteadDemoPieces {
        var p = HomesteadDemoPieces()
        p.buildings = [
            ("0,0,N", "p_alex", .town), ("-2,1,S", "p_alex", .cottage),
            ("1,0,S", "p_sam", .cottage), ("-1,-1,N", "p_sam", .town),
            ("2,-2,S", "p_robin", .cottage), ("-1,2,N", "p_robin", .cottage),
        ]
        p.roads = [
            ("0,0,NE", "p_alex"), ("1,-1,W", "p_alex"), ("-2,2,NW", "p_alex"), ("-2,2,NE", "p_alex"),
            ("1,1,NW", "p_sam"), ("0,1,NE", "p_sam"), ("-1,-1,NE", "p_sam"),
            ("2,-1,NW", "p_robin"), ("-1,2,NE", "p_robin"), ("0,1,W", "p_robin"),
        ]
        return p
    }

    static var homesteadMidPlayers: [[String: Any]] {
        [homesteadPlayer("p_alex", "Alex", seat: 0, host: true, hand: 9, cards: 2, vp: 3, rangers: 1, trail: 2, pieces: (11, 4, 3)),
         homesteadPlayer("p_sam", "Sam", seat: 1, host: false, hand: 4, cards: 1, vp: 3, rangers: 0, trail: 2, pieces: (12, 4, 3)),
         homesteadPlayer("p_robin", "Robin", seat: 2, host: false, hand: 6, cards: 0, vp: 2, trail: 2, pieces: (12, 3, 4))]
    }

    // MARK: Rooms

    /// Alex's main step: a road or a cottage to build, an almanac card to buy,
    /// a ranger to play, an offer out with a counter from Sam.
    static func homesteadMain(id: String, clock: DemoClock, pace: String) -> String {
        let now = clock.now
        let hexes = homesteadStandardHexes
        let pieces = homesteadMidGame
        let harbours = homesteadHarbours(hexes, kinds: homesteadStandardHarbourKinds).map { row in
            HomesteadHarbour(edge: row["edge"] as? String ?? "", kind: row["kind"] as? String ?? "any", rate: row["rate"] as? Int ?? 3)
        }
        let board = HomesteadBoard(hexes: hexes, harbours: harbours)
        let legal = homesteadLegal(board, pieces, me: "p_alex", road: true, cottage: true)
        let async = pace == "async"
        let offers: [[String: Any]] = [
            ["id": "o7", "from": "p_alex", "to": NSNull(), "give": ["grain": 1], "want": ["stone": 1], "status": "open",
             "refusedBy": ["p_robin"], "counterTo": NSNull(), "acceptedBy": NSNull(), "at": ms(now.addingTimeInterval(-30)).asNumber],
            ["id": "o8", "from": "p_sam", "to": ["p_alex"], "give": ["stone": 1], "want": ["grain": 2], "status": "open",
             "refusedBy": [String](), "counterTo": "o7", "acceptedBy": NSNull(), "at": ms(now.addingTimeInterval(-12)).asNumber],
        ]
        return homesteadBase(
            id: id, difficulty: "easy", host: "p_alex", hexes: hexes, harbourKinds: homesteadStandardHarbourKinds,
            pieces: pieces, players: homesteadMidPlayers, seats: ["p_alex", "p_sam", "p_robin"], clock: clock,
            extra: [
                "step": "main", "pace": pace, "deadlineHours": nsNull(async ? 24 : nil),
                "phaseEndsAt": ms(now.addingTimeInterval(async ? 21 * 3600 + 600 : 95)).asNumber,
                "me": ["hand": ["timber": 2, "clay": 1, "wool": 2, "grain": 3, "stone": 1],
                       "cards": [["kind": "ranger", "new": false], ["kind": "heirloom", "new": true]],
                       "vp": 4, "playedCardThisTurn": false, "rates": homesteadRates(board, pieces, me: "p_alex")],
                "legal": ["road": legal.roads, "cottage": legal.cottages, "town": [String](), "fox": [String](),
                          "victims": [String: [String]](), "canRoll": false, "canBuy": true, "canEnd": true,
                          "playable": ["ranger"], "canTrade": true],
                "offers": offers,
                "hints": ["affordable": ["road", "cottage", "card"],
                          "trades": [["give": "wool", "count": 4, "get": "stone", "for": "town"]],
                          "tip": "A town makes two of everything its cottage made."],
                "log": homesteadLog([
                    ("turn", "p_alex", "Your turn."),
                    ("roll", "p_alex", "You rolled 9."),
                    ("produce", nil, "9: you +1 grain, Sam +1 wool."),
                    ("offer", "p_alex", "You offered 1 grain for 1 stone."),
                    ("offer", "p_sam", "Sam countered: 1 stone for 2 grain."),
                ], at: now),
            ])
    }

    /// Over days, waiting on Sam to roll: nothing for Alex to do but look.
    static func homesteadWaiting(id: String, clock: DemoClock) -> String {
        let now = clock.now
        let hexes = homesteadStandardHexes
        return homesteadBase(
            id: id, difficulty: "medium", host: "p_alex", hexes: hexes, harbourKinds: homesteadStandardHarbourKinds,
            pieces: homesteadMidGame, players: homesteadMidPlayers, seats: ["p_alex", "p_sam", "p_robin"], clock: clock,
            extra: [
                "step": "roll", "pace": "async", "deadlineHours": 24, "activeId": "p_sam", "turn": 10,
                "phaseEndsAt": ms(now.addingTimeInterval(30 * 3600)).asNumber,
                "me": ["hand": ["timber": 1, "clay": 0, "wool": 2, "grain": 1, "stone": 2], "cards": [[String: Any]](),
                       "vp": 3, "playedCardThisTurn": false,
                       "rates": ["timber": 4, "clay": 4, "wool": 4, "grain": 4, "stone": 4]],
                "hints": ["affordable": [String](), "trades": [[String: Any]](), "tip": NSNull()],
                "log": homesteadLog([
                    ("build", "p_alex", "You built a road."),
                    ("turn", "p_sam", "Sam's turn."),
                ], at: now),
            ])
    }

    /// Round one of setup: Sam and Robin have placed; Alex picks a corner.
    static func homesteadSetup(clock: DemoClock) -> String {
        let hexes = homesteadStandardHexes
        var pieces = HomesteadDemoPieces()
        pieces.buildings = [("1,-1,N", "p_sam", .cottage), ("-1,1,S", "p_robin", .cottage)]
        pieces.roads = [("1,-1,NE", "p_sam"), ("-1,2,NW", "p_robin")]
        let board = HomesteadBoard(hexes: hexes, harbours: [])
        let players = [
            homesteadPlayer("p_sam", "Sam", seat: 0, host: true, hand: 0, cards: 0, vp: 1, pieces: (14, 4, 4)),
            homesteadPlayer("p_robin", "Robin", seat: 1, host: false, hand: 0, cards: 0, vp: 1, pieces: (14, 4, 4)),
            homesteadPlayer("p_alex", "Alex", seat: 2, host: false, hand: 0, cards: 0, vp: 0, pieces: (15, 5, 4)),
        ]
        return homesteadBase(
            id: demoHomesteadSetupRoom, difficulty: "medium", host: "p_sam", hexes: hexes,
            harbourKinds: homesteadStandardHarbourKinds, pieces: pieces, players: players,
            seats: ["p_sam", "p_robin", "p_alex"], clock: clock,
            extra: [
                "step": "setup", "turn": 0, "dice": NSNull(),
                "setup": ["round": 1, "need": "cottage", "cottage": NSNull()],
                "me": ["hand": [String: Int](), "cards": [[String: Any]](), "vp": 0, "playedCardThisTurn": false,
                       "rates": ["timber": 4, "clay": 4, "wool": 4, "grain": 4, "stone": 4]],
                "legal": ["road": [String](), "cottage": homesteadOpenCorners(board, pieces), "town": [String](),
                          "fox": [String](), "victims": [String: [String]](), "canRoll": false, "canBuy": false,
                          "canEnd": false, "playable": [String](), "canTrade": false],
                "hints": ["affordable": [String](), "trades": [[String: Any]](), "tip": NSNull()],
                "log": homesteadLog([
                    ("setup", "p_sam", "Sam placed a cottage and a road."),
                    ("setup", "p_robin", "Robin placed a cottage and a road."),
                ], at: clock.now),
            ])
    }

    /// A 7 on the large island with five playing: Alex and Sam owe four each.
    static func homesteadDiscard(clock: DemoClock) -> String {
        let hexes = homesteadLargeHexes
        let board = HomesteadBoard(hexes: hexes, harbours: [])
        // Ten buildings two apart, spread over the island, two each.
        let ids = ["p_kit", "p_sam", "p_robin", "p_jo", "p_alex"]
        var pieces = HomesteadDemoPieces()
        var used = 0
        for vertex in homesteadOpenCorners(board, pieces) where used < 10 {
            guard let v = HomesteadVertex(id: vertex), board.land(around: v).count == 3 else { continue }
            if pieces.buildings.contains(where: { $0.at == vertex }) { continue }
            if v.neighbours.contains(where: { n in pieces.buildings.contains { $0.at == n.id } }) { continue }
            pieces.buildings.append((vertex, ids[used % 5], used >= 8 ? .town : .cottage))
            if let edge = v.edges.first(where: { board.isEdge($0.id) }) { pieces.roads.append((edge.id, ids[used % 5])) }
            used += 1
        }
        let players = [
            homesteadPlayer("p_kit", "Kit", seat: 0, host: true, hand: 5, cards: 1, vp: 2, pieces: (13, 3, 4)),
            homesteadPlayer("p_sam", "Sam", seat: 1, host: false, hand: 8, cards: 0, vp: 2, pieces: (13, 3, 4)),
            homesteadPlayer("p_robin", "Robin", seat: 2, host: false, hand: 3, cards: 2, vp: 2, pieces: (13, 3, 4)),
            homesteadPlayer("p_jo", "Jo", seat: 3, host: false, hand: 6, cards: 0, vp: 3, pieces: (13, 4, 3)),
            homesteadPlayer("p_alex", "Alex", seat: 4, host: false, hand: 9, cards: 0, vp: 3, pieces: (13, 4, 3)),
        ]
        return homesteadBase(
            id: demoHomesteadDiscardRoom, difficulty: "medium", host: "p_kit", hexes: hexes,
            harbourKinds: homesteadLargeHarbourKinds, pieces: pieces, players: players, seats: ids, clock: clock,
            extra: [
                "step": "discard", "activeId": "p_kit", "turn": 14,
                "phaseEndsAt": ms(clock.now.addingTimeInterval(52)).asNumber,
                "dice": ["a": 3, "b": 4, "total": 7, "by": "p_kit", "at": ms(clock.now.addingTimeInterval(-8)).asNumber],
                "discardOwed": ["p_alex": 4, "p_sam": 4],
                "me": ["hand": ["timber": 3, "clay": 1, "wool": 2, "grain": 2, "stone": 1], "cards": [[String: Any]](),
                       "vp": 3, "playedCardThisTurn": false,
                       "rates": ["timber": 4, "clay": 4, "wool": 4, "grain": 4, "stone": 4]],
                "bank": ["timber": 15, "clay": 18, "wool": 16, "grain": 14, "stone": 19], "deckCount": 28,
                "hints": ["affordable": ["road", "cottage"], "trades": [[String: Any]](), "tip": NSNull()],
                "log": homesteadLog([
                    ("turn", "p_kit", "Kit's turn."),
                    ("roll", "p_kit", "Kit rolled 7."),
                    ("discard", nil, "A 7: you and Sam put back 4 each."),
                ], at: clock.now),
            ])
    }

    /// Sam won with 10; Alex 8; Robin 6. Heirlooms shown.
    static func homesteadDone(clock: DemoClock) -> String {
        let hexes = homesteadStandardHexes
        let players = [
            homesteadPlayer("p_sam", "Sam", seat: 0, host: true, hand: 3, cards: 1, vp: 9, rangers: 3, trail: 7, longest: true,
                            chief: true, pieces: (5, 2, 1), finished: (1, 10)),
            homesteadPlayer("p_alex", "Alex", seat: 1, host: false, hand: 5, cards: 1, vp: 7, rangers: 1, trail: 4,
                            pieces: (8, 3, 2), finished: (1, 8)),
            homesteadPlayer("p_robin", "Robin", seat: 2, host: false, hand: 2, cards: 0, vp: 6, trail: 3,
                            pieces: (9, 2, 3), finished: (0, 6)),
        ]
        var pieces = homesteadMidGame
        pieces.buildings = pieces.buildings.map { b in
            (b.at, b.owner == "p_alex" ? "p_sam" : b.owner == "p_sam" ? "p_alex" : b.owner, b.piece)
        }
        let standings: [[String: Any]] = [
            ["id": "p_sam", "name": "Sam", "place": 1, "score": 10, "vp": 10, "heirlooms": 1, "cottages": 2, "towns": 3,
             "trail": 7, "longestTrail": true, "chiefRanger": true, "result": "won", "left": false],
            ["id": "p_alex", "name": "Alex", "place": 2, "score": 8, "vp": 8, "heirlooms": 1, "cottages": 2, "towns": 2,
             "trail": 4, "longestTrail": false, "chiefRanger": false, "result": "lost", "left": false],
            ["id": "p_robin", "name": "Robin", "place": 3, "score": 6, "vp": 6, "heirlooms": 0, "cottages": 4, "towns": 1,
             "trail": 3, "longestTrail": false, "chiefRanger": false, "result": "lost", "left": false],
        ]
        return homesteadBase(
            id: demoHomesteadDoneRoom, difficulty: "medium", host: "p_sam", hexes: hexes,
            harbourKinds: homesteadStandardHarbourKinds, pieces: pieces, players: players,
            seats: ["p_sam", "p_alex", "p_robin"], clock: clock,
            extra: [
                "phase": "finished", "step": NSNull(), "activeId": NSNull(), "turn": 41, "phaseEndsAt": NSNull(),
                "me": ["hand": ["timber": 1, "clay": 1, "wool": 1, "grain": 2, "stone": 0],
                       "cards": [["kind": "heirloom", "new": false]], "vp": 8, "playedCardThisTurn": false,
                       "rates": ["timber": 4, "clay": 4, "wool": 4, "grain": 4, "stone": 4]],
                "result": ["winnerId": "p_sam", "reason": "points"],
                "standings": standings, "winnerIds": ["p_sam"],
                "log": homesteadLog([
                    ("build", "p_sam", "Sam built a town."),
                    ("award", "p_sam", "Sam has the Longest Trail."),
                    ("finish", "p_sam", "Sam reached 10 points and wins."),
                ], at: clock.now),
            ])
    }
}

private extension String {
    /// A fixture's epoch-ms string as a JSON number.
    var asNumber: Int64 { Int64(self) ?? 0 }
}
