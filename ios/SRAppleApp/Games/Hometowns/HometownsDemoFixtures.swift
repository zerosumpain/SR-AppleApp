import Foundation

// MARK: - Demo Hometowns
//
// `-SRDemo` rooms for Hometowns, for the CI screenshots of the Town screen, the
// founding sheet and the county. Synthetic throughout — the repository is
// public: Alex's hamlet "Sunnyvale" in its first year (two preset name
// halves, never a family name), with wants, Bramble's and Mo's cards, the
// needs ladders and Town Talk; and a second county where Alex has not founded
// a town yet. The frames are shaped like SR-Main's wire (§10.7) but carry only
// what the shell reads: the map is the drawn stand-in in a demo, so no planes
// travel. The real frames are the XCTest fixtures.
//
// The rooms themselves are DEBUG-only (the demo-guard rule for anything that
// exists for a screenshot); a Release build answers nil and no rows, so the
// App Review demo never meets a county.

extension SRDemoFixtures {

    static let demoHometownsRoom = "g_demo_hometowns"
    static let demoHometownsFoundRoom = "g_demo_hometowns_found"

    /// The rows for "Your games", or nothing in Release and the store shots.
    static func hometownsLobbyRows(_ now: Date) -> String {
        #if DEBUG
        guard !SRDemo.isStoreShots else { return "" }
        return """
        {"id": \(s(demoHometownsRoom)), "game": "hometowns", "phase": "running", "hostName": "Alex",
                        "durable": true, "pace": "async", "myTurn": true, "waitingFor": ["Alex"],
                        "summary": "Sunnyvale · Hamlet · 186 people",
                        "updatedAt": \(ms(now.addingTimeInterval(-40 * 60)))},
                       {"id": \(s(demoHometownsFoundRoom)), "game": "hometowns", "phase": "running", "hostName": "Sam",
                        "durable": true, "pace": "async", "myTurn": false, "waitingFor": [],
                        "summary": "Brookford County · found your town",
                        "updatedAt": \(ms(now.addingTimeInterval(-5 * 3600)))},
        """
        #else
        return ""
        #endif
    }

    /// The room for `id`, or nil when it is not one of Hometowns'.
    static func hometownsRoom(id: String, clock: DemoClock) -> String? {
        #if DEBUG
        switch id {
        case demoHometownsRoom: return hometownsTown(clock: clock)
        case demoHometownsFoundRoom: return hometownsFounding(clock: clock)
        default: return nil
        }
        #else
        return nil
        #endif
    }

    #if DEBUG
    private static func hometownsCommon(id: String, rev: Int, host: String, clock: DemoClock) -> String {
        let now = clock.now
        let next = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 1800).rounded(.up) * 1800)
        return """
        "id": \(s(id)), "game": "hometowns", "phase": "running", "serverNow": \(ms(now)), "rev": \(rev), "base": null,
        "hostId": \(s(host)), "meId": "p_alex", "difficulty": "easy", "durable": true, "pace": "async", "version": \(rev),
        "client": {"engineHash": "demo0000demo", "page": "/projects/hometowns/demo0000demo/mobile.html", "bridge": 1},
        "clock": {"gridTick": 96, "tickMs": 1800000, "nextTickAt": \(ms(next)), "nextRegionalDayAt": \(ms(now.addingTimeInterval(5 * 3600))),
                  "nextGazetteAt": \(ms(now.addingTimeInterval(3 * 86400))), "paused": false, "napping": false,
                  "season": {"n": 1, "theme": "founders", "day": 2, "daysLeft": 40}}
        """
    }

    private static let hometownsSites = """
    [{"index": 0, "kind": "coast", "terrainSeed": 11, "owner": 0}, {"index": 1, "kind": "river", "terrainSeed": 12, "owner": null},
     {"index": 2, "kind": "forest", "terrainSeed": 13, "owner": null}, {"index": 3, "kind": "hills", "terrainSeed": 14, "owner": null},
     {"index": 4, "kind": "flatland", "terrainSeed": 15, "owner": null}, {"index": 5, "kind": "coast", "terrainSeed": 16, "owner": null}]
    """

    private static let kingsportCard = """
    {"seat": "kingsport", "name": "Kingsport", "avatar": "kingsport", "flag": 0, "tier": 4, "pop": 40000, "faces": [],
     "stars": [60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60], "holiday": false, "archived": false, "inFortnight": false,
     "skyline": "", "mayor": "", "linked": []}
    """

    /// Alex's hamlet a game year in: on the grid, a Village checklist to aim for.
    private static func hometownsTown(clock: DemoClock) -> String {
        """
        {\(hometownsCommon(id: demoHometownsRoom, rev: 41, host: "p_alex", clock: clock)),
         "players": [{"id": "p_alex", "name": "Alex", "status": "joined", "seat": "s1"}],
         "towns": [{"seat": "s1", "name": "Sunnyvale", "avatar": "badger", "flag": 3, "tier": 0, "pop": 186,
                    "faces": [58, 0, 96, 32, 0], "stars": [42, 55, 64, 18, 22, 70, 30, 12, 78, 88, 40],
                    "holiday": false, "archived": false, "inFortnight": false, "skyline": "", "mayor": "Alex", "linked": []}],
         "county": {"name": "Kingsport County", "sites": \(hometownsSites), "kingsport": \(kingsportCard),
                    "links": [], "offers": [], "contracts": [], "pacts": [], "fund": 0,
                    "bulletin": [{"key": "bulletin.grew", "data": {"n": 38, "pop": 186}},
                                 {"key": "bulletin.homesComing", "data": {"n": 12}}]},
         "visiting": null,
         "me": {"seat": "s1", "profile": "adult", "isParent": true, "townHash": "demo",
                "town": {"seat": "s1", "name": "Sunnyvale", "avatar": "badger", "flag": 3, "site": 0, "siteKind": "coast",
                         "tick": 52, "sprintLeft": 0, "sprintAt": 0, "sprintAuto": false, "gridBase": 12, "archived": false,
                         "tier": 0, "parcelRights": 0,
                         "people": [44, 0, 0, 30, 2, 0, 26, 2, 0, 30, 2, 0, 0],
                         "happy": [58, 62, 66, 0, 70, 64, 0, 0, 0, 0], "approval": 61,
                         "money": {"reserves": 84250, "loan": null, "bonds": [], "rating": 2, "helper": null},
                         "taxes": {"town": 800, "homes": [800, 800, 800], "business": 400, "sales": 200, "hotel": 500},
                         "funding": [1, 1, 1, 1, 1, 1, 1, 1, 1],
                         "orders": [{"kind": "budgetHealthy", "on": true, "args": [2, 200]}, {"kind": "buyUtilities", "on": true, "args": []},
                                    {"kind": "fixDamaged", "on": true, "args": []}, {"kind": "awayZoning", "on": false, "args": [12, 60, 3]}],
                         "initiatives": 1, "policies": [], "undo": [{"planId": "pdemo1", "day": 2, "atTick": 50, "cost": 6000}],
                         "lastSeenTick": 52, "books": {"dayLines": [9200, 1800, -4100, -1200]},
                         "construction": [2210, 1, 2211, 1], "holiday": {"until": null, "usedDays": 0}},
                "derived": {"stars": [42, 55, 64, 18, 22, 70, 30, 12, 78, 88, 40], "meters": [62, 18, 0, 48, 0, 12, 0, 24],
                            "wants": [{"key": "shops", "severity": 70, "tile": -1, "hatched": false},
                                      {"key": "talk.schools", "severity": 40, "tile": -1, "hatched": false}],
                            "advisors": [{"advisor": "bramble", "key": "bramble.shops", "data": {"action": "zone:shops"}},
                                         {"advisor": "mo", "key": "mo.schools", "data": {"action": "build:school"}}],
                            "needs": [{"cohort": 1, "tier": 0, "items": [{"key": "water", "met": 1, "buildable": true},
                                       {"key": "power", "met": 1, "buildable": true}, {"key": "shop", "met": 0.4, "buildable": true},
                                       {"key": "green", "met": 0, "buildable": true}, {"key": "primary", "met": 0, "buildable": true}]}],
                            "pipeline": {"homes": 12, "movers": 40},
                            "townTalk": [["schools", 38], ["fun", 27], ["jobs", 21], ["homes", 14]]},
                "affordances": {"unlocked": ["well", "windmill", "schoolHouse", "villageGreen", "pocketPark", "road:lane",
                                             "zone:homes", "zone:shops", "zone:industry", "zone:farms"],
                                "costs": {"well": 1500, "windmill": 12000, "schoolHouse": 12000, "villageGreen": 2000, "pocketPark": 3000,
                                          "generator": 20000, "surgery": 30000, "playground": 5000, "road:lane": 1500, "road:street": 4000},
                                "initiatives": 1, "slots": 1, "canUndo": ["pdemo1"]},
                "inbox": [{"id": "deputy.buyUtilities.2", "kind": "deputy.buyUtilities", "day": 2, "from": null,
                           "data": {"power": 120, "water": 80, "cost": 1400}}],
                "welcomeBack": [], "moves": []}}
        """
    }

    /// A county Sam started, where Alex has yet to found a town.
    private static func hometownsFounding(clock: DemoClock) -> String {
        """
        {\(hometownsCommon(id: demoHometownsFoundRoom, rev: 3, host: "p_sam", clock: clock)),
         "players": [{"id": "p_sam", "name": "Sam", "status": "joined", "seat": "s1"},
                     {"id": "p_alex", "name": "Alex", "status": "joined", "seat": "s2"}],
         "towns": [{"seat": "s1", "name": "Oakridge", "avatar": "owl", "flag": 2, "tier": 0, "pop": 64, "faces": [20, 0, 34, 10, 0],
                    "stars": [40, 50, 60, 20, 20, 60, 30, 10, 70, 80, 40], "holiday": false, "archived": false,
                    "inFortnight": true, "skyline": "", "mayor": "Sam", "linked": []}],
         "county": {"name": "Brookford County", "sites": \(hometownsSites), "kingsport": \(kingsportCard),
                    "links": [], "offers": [], "contracts": [], "pacts": [], "fund": 0, "bulletin": []},
         "visiting": null,
         "me": {"seat": "s2", "profile": "kid", "isParent": false, "townHash": "",
                "derived": {"stars": [], "meters": [], "wants": [], "advisors": [], "needs": [], "pipeline": {"homes": 0, "movers": 0}, "townTalk": []},
                "affordances": {"unlocked": [], "costs": {}, "initiatives": 0, "slots": 0, "canUndo": []},
                "inbox": [], "welcomeBack": [], "moves": []}}
        """
    }
    #endif
}
