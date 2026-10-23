import XCTest
import CoreLocation
@testable import SRAppleApp

/// Manhunt: the spec's wire contract (SR-Main `manhunt.ts` `toWire`), what the
/// map draws for each role, when the phone sends a fix, and the sentences.
final class ManhuntTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    // MARK: - The wire (the spec's JSON)

    /// A hunter's view, three minutes into the hunt: the other hunter live,
    /// the runner only at the ping.
    private let hunterJSON = #"""
    { "id":"g_m", "game":"manhunt", "difficulty":"medium", "phase":"hunt",
      "hostId":"p_a", "meId":"p_a", "myRole":"hunter",
      "area":{"lat":51.5,"lng":-0.12,"radiusM":500}, "radius":500, "minutes":30,
      "rule":"The runner shows up every 3 min.", "pingMs":180000, "headStartMs":120000,
      "catchM":25, "catchSlackM":25, "claimMs":20000, "outsideLiveMs":30000, "fixMinGapMs":3000,
      "runnerPick":null, "runnerId":"p_r", "startedAt":1000, "huntStartedAt":121000, "endsAt":1921000,
      "nextPingAt":481000, "phaseEndsAt":1921000, "runnerLiveUntil":null, "runnerQuiet":false,
      "claim":null, "catchCooldownUntil":null,
      "pings":[{"at":301000,"runner":{"lat":51.501,"lng":-0.121,"accuracy":5,"at":300500,"outside":false},"hunters":[]}],
      "players":[
        {"id":"p_a","name":"Alex","status":"joined","isHost":true,"seated":true,"role":"hunter",
         "fix":{"lat":51.4995,"lng":-0.1201,"accuracy":4,"at":310000,"outside":false}},
        {"id":"p_r","name":"Sam","status":"joined","isHost":false,"seated":true,"role":"runner","fix":null},
        {"id":"p_k","name":"Kit","status":"joined","isHost":false,"seated":true,"role":"hunter",
         "fix":{"lat":51.502,"lng":-0.118,"accuracy":8,"at":309000,"outside":false}}
      ],
      "result":null, "standings":null, "winnerIds":[], "serverNow":311000 }
    """#

    private let runnerJSON = #"""
    { "id":"g_m", "game":"manhunt", "difficulty":"hard", "phase":"hunt",
      "hostId":"p_a", "meId":"p_r", "myRole":"runner",
      "area":{"lat":51.5,"lng":-0.12,"radiusM":500}, "radius":500, "minutes":30, "pingMs":120000,
      "runnerId":"p_r", "endsAt":1921000, "nextPingAt":361000, "runnerLiveUntil":331000, "runnerQuiet":false,
      "claim":{"hunterId":"p_k","deadline":330000,"quiet":false},
      "pings":[{"at":241000,"runner":null,"hunters":[
        {"id":"p_a","fix":{"lat":51.4991,"lng":-0.1203,"accuracy":5,"at":240000,"outside":false}},
        {"id":"p_k","fix":null}]}],
      "players":[
        {"id":"p_a","name":"Alex","status":"joined","isHost":true,"seated":true,"role":"hunter","fix":null},
        {"id":"p_r","name":"Sam","status":"joined","isHost":false,"seated":true,"role":"runner",
         "fix":{"lat":51.5052,"lng":-0.12,"accuracy":5,"at":310000,"outside":true}},
        {"id":"p_k","name":"Kit","status":"joined","isHost":false,"seated":true,"role":"hunter","fix":null}
      ],
      "result":null, "standings":null, "winnerIds":[], "serverNow":311000 }
    """#

    private let finishedJSON = #"""
    { "id":"g_d", "game":"manhunt", "difficulty":"easy", "phase":"finished",
      "hostId":"p_a", "meId":"p_a", "myRole":"hunter", "runnerId":"p_r", "pings":[],
      "players":[
        {"id":"p_a","name":"Alex","status":"joined","isHost":true,"seated":true,"role":"hunter","fix":null},
        {"id":"p_r","name":"Sam","status":"joined","isHost":false,"seated":true,"role":"runner","fix":null},
        {"id":"p_k","name":"Kit","status":"joined","isHost":false,"seated":true,"role":"hunter","fix":null}
      ],
      "result":{"outcome":"caught","catcherId":"p_k","confirmed":false},
      "standings":[
        {"id":"p_k","name":"Kit","place":1,"role":"hunter","result":"won","left":false},
        {"id":"p_a","name":"Alex","place":2,"role":"hunter","result":"team","left":false},
        {"id":"p_r","name":"Sam","place":3,"role":"runner","result":"lost","left":false}
      ],
      "winnerIds":["p_k"], "serverNow":2000000 }
    """#

    func testAHuntersRoomDecodes() throws {
        let room = try decode(hunterJSON)
        XCTAssertEqual(room.kind, .manhunt)
        let state = try XCTUnwrap(room.manhunt)
        XCTAssertEqual(state.phase, .hunt)
        XCTAssertEqual(state.myRole, .hunter)
        XCTAssertEqual(state.area, ManhuntArea(lat: 51.5, lng: -0.12, radiusM: 500))
        XCTAssertEqual(state.runnerId, "p_r")
        XCTAssertEqual(state.pingMs, 180_000)
        XCTAssertEqual(state.nextPingAt, 481_000)
        XCTAssertEqual(state.pings.count, 1)
        XCTAssertEqual(state.lastPing?.runner?.lat, 51.501)
        XCTAssertEqual(state.hunters.map(\.id), ["p_a", "p_k"])
        XCTAssertNil(state.seat("p_r")?.fix, "the runner is not live between pings")
        XCTAssertTrue(state.phase.collectsPositions)
    }

    func testAHunterMapsTheOtherHuntersLiveAndTheRunnerAtThePing() throws {
        let state = try XCTUnwrap(try decode(hunterJSON).manhunt)
        let marks = state.marks(meId: "p_a")
        XCTAssertEqual(Set(marks.map(\.kind)), [.me, .hunter, .runnerPing])
        XCTAssertEqual(marks.first { $0.kind == .runnerPing }?.name, "Sam")
        XCTAssertEqual(marks.first { $0.kind == .hunter }?.id, "p_k")
        XCTAssertFalse(marks.contains { $0.kind == .hunterPing }, "a hunter's phone has no hunter pings")
    }

    func testTheRunnerMapsOnlyHimselfAndTheHuntersAtThePing() throws {
        let room = try decode(runnerJSON)
        let state = try XCTUnwrap(room.manhunt)
        XCTAssertEqual(state.myRole, .runner)
        let marks = state.marks(meId: "p_r")
        XCTAssertEqual(marks.filter { $0.kind == .me }.count, 1)
        XCTAssertEqual(marks.filter { $0.kind == .hunterPing }.map(\.name), ["Alex"], "Kit had no fix at the ping")
        XCTAssertFalse(marks.contains { $0.kind == .hunter || $0.kind == .runnerLive || $0.kind == .runnerPing })
        XCTAssertEqual(state.claim, ManhuntClaim(hunterId: "p_k", deadline: 330_000, quiet: false))
        XCTAssertEqual(state.runnerLiveUntil, 331_000)
        XCTAssertTrue(state.seat("p_r")?.fix?.outside == true)
    }

    func testAFinishedHuntSaysWhoCaughtWhom() throws {
        let room = try decode(finishedJSON)
        let state = try XCTUnwrap(room.manhunt)
        XCTAssertFalse(state.phase.collectsPositions)
        XCTAssertEqual(state.standings?.map(\.result), ["won", "team", "lost"])
        XCTAssertEqual(state.outcomeLine { $0 == "p_a" ? "You" : room.name(of: $0) },
                       "Kit caught Sam — the catch stood after 20 seconds.")
        XCTAssertTrue(state.marks(meId: "p_a").isEmpty, "a finished room holds no positions")
    }

    func testAnotherGamesRoomCarriesNoManhunt() throws {
        let room = try decode(#"{"id":"g_t","game":"tap-duel","phase":"lobby","serverNow":1}"#)
        XCTAssertNil(room.manhunt)
    }

    func testAnUnknownPhaseIsNotACrash() throws {
        let room = try decode(#"{"id":"g_x","game":"manhunt","phase":"overtime","serverNow":1}"#)
        XCTAssertEqual(room.manhunt?.phase, .unknown)
        XCTAssertFalse(ManhuntPhase.unknown.collectsPositions)
        XCTAssertEqual(ManhuntScreenPhase.of(room), .unknown)
    }

    // MARK: - Only during the game

    func testPositionsAreCollectedOnlyInTheHeadStartAndTheHunt() {
        XCTAssertEqual(
            [ManhuntPhase.lobby, .countdown, .headstart, .hunt, .finished, .closed, .unknown].filter(\.collectsPositions),
            [.headstart, .hunt]
        )
    }

    func testTheLocationSessionStartsAtTheCountdownButSendsNothingThere() {
        XCTAssertEqual(
            [ManhuntPhase.lobby, .countdown, .headstart, .hunt, .finished, .closed, .unknown].filter(\.runsLocation),
            [.countdown, .headstart, .hunt]
        )
        XCTAssertFalse(ManhuntPhase.countdown.collectsPositions)
    }

    func testAFixIsSentOnlyWhenFreshSharpAndNotTooSoon() {
        XCTAssertTrue(ManhuntRules.shouldSend(accuracy: 5, ageSeconds: 1, sinceLastSentMs: nil, minGapMs: 3_000))
        XCTAssertTrue(ManhuntRules.shouldSend(accuracy: 5, ageSeconds: 1, sinceLastSentMs: 3_000, minGapMs: 3_000))
        XCTAssertFalse(ManhuntRules.shouldSend(accuracy: 5, ageSeconds: 1, sinceLastSentMs: 2_999, minGapMs: 3_000))
        XCTAssertFalse(ManhuntRules.shouldSend(accuracy: -1, ageSeconds: 1, sinceLastSentMs: nil, minGapMs: 3_000),
                       "iOS's negative accuracy is no fix")
        // A rough fix (Approximate Location is ~1-3 km) is still sent: silence
        // would make a runner "quiet" and catchable from anywhere.
        XCTAssertTrue(ManhuntRules.shouldSend(accuracy: 500, ageSeconds: 1, sinceLastSentMs: nil, minGapMs: 3_000))
        XCTAssertTrue(ManhuntRules.shouldSend(accuracy: 3_000, ageSeconds: 1, sinceLastSentMs: nil, minGapMs: 3_000))
        XCTAssertFalse(ManhuntRules.shouldSend(accuracy: 20_000, ageSeconds: 1, sinceLastSentMs: nil, minGapMs: 3_000))
        XCTAssertFalse(ManhuntRules.shouldSend(accuracy: .infinity, ageSeconds: 1, sinceLastSentMs: nil, minGapMs: 3_000))
        XCTAssertFalse(ManhuntRules.shouldSend(accuracy: 5, ageSeconds: 45, sinceLastSentMs: nil, minGapMs: 3_000))
        XCTAssertFalse(ManhuntRules.shouldSend(accuracy: .nan, ageSeconds: 1, sinceLastSentMs: nil, minGapMs: 3_000))
        XCTAssertFalse(ManhuntRules.shouldSend(accuracy: 5, ageSeconds: .nan, sinceLastSentMs: nil, minGapMs: 3_000))
    }

    func testAPositionBodyCarriesTheFixAndNothingElse() throws {
        let body = GameActionBody(action: "position", lat: 51.5, lng: -0.12, accuracy: 5, at: 1_000)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["action", "lat", "lng", "accuracy", "at"])
    }

    // MARK: - The new-game sheet

    func testTheNewGameSheetSendsTheSizeAndLengthButNoCentre() throws {
        let body = ManhuntSettings(difficulty: .hard, radius: 1_000, minutes: 45).createBody(invite: ["p_b", "p_c"])
        XCTAssertEqual(body.game, "manhunt")
        XCTAssertEqual(body.difficulty, "hard")
        XCTAssertEqual(body.radius, 1_000)
        XCTAssertEqual(body.minutes, 45)
        let json = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        XCTAssertFalse(json.contains("lat"), "the centre comes from the lobby, where the host stands")
    }

    func testTheSheetsChoicesSitInsideTheServersLimits() {
        XCTAssertTrue(ManhuntSettings.radii.allSatisfy { (250...2_000).contains($0) })
        XCTAssertTrue(ManhuntSettings.lengths.allSatisfy { (15...60).contains($0) })
        XCTAssertTrue(ManhuntSettings.radii.contains(ManhuntSettings.defaultRadius))
        XCTAssertTrue(ManhuntSettings.lengths.contains(ManhuntSettings.defaultMinutes))
    }

    /// The app's id is the site's catalogue id (`GAME_IDS` in SR-Main).
    func testTheGameIdMatchesTheSite() {
        XCTAssertEqual(GameKind(rawValue: "manhunt"), .manhunt)
        XCTAssertEqual(GameKind.manhunt.title, "Manhunt")
        XCTAssertTrue(GameKind.allCases.contains(.manhunt))
    }

    // MARK: - What the phone says

    func testDistancesAndClocksRead() {
        XCTAssertEqual(ManhuntRules.distance(250), "250 m")
        XCTAssertEqual(ManhuntRules.distance(1_000), "1 km")
        XCTAssertEqual(ManhuntRules.distance(1_500), "1.5 km")
        XCTAssertEqual(ManhuntRules.distance(.nan), "–")
        XCTAssertEqual(ManhuntRules.clock(245_000), "4:05")
        XCTAssertEqual(ManhuntRules.clock(9_999), "0:09")
        XCTAssertEqual(ManhuntRules.clock(-5), "0:00")
        XCTAssertEqual(ManhuntRules.clock(.nan), "0:00")
        XCTAssertEqual(ManhuntRules.left(until: 10_000, now: 4_000), 6_000)
        XCTAssertEqual(ManhuntRules.left(until: 1_000, now: 4_000), 0)
        XCTAssertNil(ManhuntRules.left(until: nil, now: 4_000))
        XCTAssertNil(ManhuntRules.left(until: .nan, now: 4_000))
    }

    func testTheBoundaryIsAClosedRingAtTheRadius() {
        let centre = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12)
        let ring = ManhuntRules.circle(centre: centre, radiusM: 500, points: 36)
        XCTAssertEqual(ring.count, 37)
        XCTAssertEqual(ring.first?.latitude, ring.last?.latitude)
        for point in ring { XCTAssertEqual(ManhuntRules.metres(centre, point), 500, accuracy: 3) }
        XCTAssertTrue(ManhuntRules.circle(centre: centre, radiusM: .nan).isEmpty)
    }

    func testTheOutcomeLines() {
        XCTAssertEqual(ManhuntRules.outcomeLine("caught", runner: "Sam", catcher: "Kit", confirmed: true), "Kit caught Sam.")
        XCTAssertEqual(ManhuntRules.outcomeLine("caught", runner: "You", catcher: "Kit", confirmed: true), "Kit caught you.")
        XCTAssertEqual(ManhuntRules.outcomeLine("time", runner: "Sam", catcher: nil, confirmed: false), "Time's up — Sam got away.")
        XCTAssertEqual(ManhuntRules.outcomeLine("runner-left", runner: "Sam", catcher: nil, confirmed: false),
                       "Sam left the game — the hunters win it.")
        XCTAssertEqual(ManhuntRules.outcomeLine("hunters-left", runner: "You", catcher: nil, confirmed: false),
                       "Every hunter left — You win it.")
        XCTAssertEqual(ManhuntRules.outcomeLine("hunters-left", runner: "Sam", catcher: nil, confirmed: false),
                       "Every hunter left — Sam wins it.")
        XCTAssertEqual(ManhuntRules.outcomeLine("??", runner: "Sam", catcher: nil, confirmed: false), "Game over.")
    }

    func testTheHeadlineFollowsTheRole() {
        XCTAssertEqual(ManhuntRules.headline(role: .runner, live: false, claimByMe: false, claimOnMe: false), "Stay hidden")
        XCTAssertEqual(ManhuntRules.headline(role: .runner, live: true, claimByMe: false, claimOnMe: false), "They can see you!")
        XCTAssertEqual(ManhuntRules.headline(role: .runner, live: false, claimByMe: false, claimOnMe: true), "Caught? Own up!")
        XCTAssertEqual(ManhuntRules.headline(role: .hunter, live: false, claimByMe: false, claimOnMe: false), "Hunt them down")
        XCTAssertEqual(ManhuntRules.headline(role: .hunter, live: false, claimByMe: true, claimOnMe: false), "Catch claimed")
    }
}
