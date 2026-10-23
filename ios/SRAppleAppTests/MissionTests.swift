import XCTest
@testable import SRAppleApp

/// Secret Mission: the spec's wire contract (SR-Main
/// docs/superpowers/specs/2026-10-22-family-games-mission.md), and the little
/// the phone works out itself — team picking, the sentences, the lobby line.
final class MissionTests: XCTestCase {

    private func decode(_ json: String) throws -> GameRoom {
        try JSONDecoder().decode(GameRoom.self, from: Data(json.utf8))
    }

    // MARK: - The game list

    func testTheGameIsKnownByTheServersId() {
        XCTAssertEqual(GameKind(rawValue: "mission"), .mission)
        XCTAssertEqual(GameKind.mission.title, "Secret Mission")
        XCTAssertEqual(GameNames.title("mission"), "Secret Mission")
        XCTAssertTrue(GameKind.allCases.contains(.mission))
        XCTAssertEqual(MissionRules.minPlayers, 5)
        XCTAssertEqual(MissionRules.maxPlayers, 10)
    }

    func testTheCreateBodyNamesTheGame() throws {
        let body = MissionSettings(difficulty: .medium).createBody(invite: ["p_a", "p_b"])
        XCTAssertEqual(body.game, "mission")
        XCTAssertEqual(body.difficulty, "medium")
        XCTAssertEqual(body.invite, ["p_a", "p_b"])
        XCTAssertEqual(MissionSettings.about("easy"), "Crew and spies only")
        XCTAssertEqual(MissionSettings.about("hard"), "With a Lookout and a Tracker")
    }

    func testMovesEncodeTheirFieldsAndNothingElse() throws {
        func json(_ body: GameActionBody) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        }
        let propose = try json(GameActionBody(action: "propose", team: ["p_a", "p_b"]))
        XCTAssertEqual(propose["team"] as? [String], ["p_a", "p_b"])
        XCTAssertEqual(propose.count, 2)
        let vote = try json(GameActionBody(action: "vote", approve: false))
        XCTAssertEqual(vote["approve"] as? Bool, false)
        let play = try json(GameActionBody(action: "play", card: "sabotage"))
        XCTAssertEqual(play["card"] as? String, "sabotage")
    }

    // MARK: - The wire

    private let votingJSON = #"""
    { "id":"g_m", "game":"mission", "difficulty":"medium", "phase":"voting",
      "hostId":"p_a", "meId":"p_b", "rule":"The Lookout knows the spies.", "specials":true,
      "minPlayers":5, "maxPlayers":10, "seats":5, "spyCount":2,
      "teamSizes":[2,3,2,3,3], "sabotagesNeeded":[1,1,1,1,1],
      "proposeMs":90000, "voteMs":45000, "missionMs":30000, "huntMs":90000,
      "mission":2, "attempt":3, "rejections":2, "maxRejections":5,
      "leaderId":"p_c", "team":["p_a","p_b","p_c"], "autoTeam":true,
      "score":{"crew":1,"spies":0},
      "secret":{"role":"tracker","side":"spies","spies":["p_e"],"vote":true,"card":null},
      "trackerId":null, "startedAt":1790000000000, "phaseEndsAt":1790000045000,
      "players":[
        {"id":"p_a","name":"Sam","status":"joined","isHost":true,"seated":true,"ready":true,"voted":false,"onTeam":true,"played":false,"role":null,"side":null},
        {"id":"p_b","name":"John","status":"joined","isHost":false,"seated":true,"ready":true,"voted":true,"onTeam":true,"played":false,"role":null,"side":null},
        {"id":"p_c","name":"Kim","status":"joined","isHost":false,"seated":true,"ready":true,"voted":true,"onTeam":true,"played":false,"role":null,"side":null},
        {"id":"p_d","name":"Robin","status":"left","isHost":false,"seated":true,"ready":true,"voted":false,"onTeam":false,"played":false,"role":null,"side":null},
        {"id":"p_e","name":"Alex","status":"joined","isHost":false,"seated":true,"ready":true,"voted":false,"onTeam":false,"played":false,"role":null,"side":null}],
      "tallies":[{"mission":1,"attempt":1,"leaderId":"p_a","team":["p_a","p_e"],"approve":["p_a","p_b","p_c","p_d","p_e"],"reject":[],"auto":["p_d"],"approved":true,"autoTeam":false}],
      "missions":[{"mission":1,"leaderId":"p_a","team":["p_a","p_e"],"needed":1,"sabotages":0,"succeeded":true}],
      "result":null, "standings":null, "winnerIds":[], "serverNow":1790000010000 }
    """#

    func testAVotingRoomDecodesFromTheContract() throws {
        let room = try decode(votingJSON)
        XCTAssertEqual(room.kind, .mission)
        XCTAssertEqual(room.phase, .unknown, "the shared phase has no `voting`")
        XCTAssertEqual(MissionScreenPhase.of(room), .voting)
        let state = try XCTUnwrap(room.mission)
        XCTAssertTrue(state.specials)
        XCTAssertEqual(state.seats, 5)
        XCTAssertEqual(state.mission, 2)
        XCTAssertEqual(state.teamSize, 3)
        XCTAssertEqual(state.needed, 1)
        XCTAssertEqual(state.rejections, 2)
        XCTAssertEqual(state.leaderId, "p_c")
        XCTAssertEqual(state.team, ["p_a", "p_b", "p_c"])
        XCTAssertTrue(state.autoTeam)
        XCTAssertEqual(state.crewScore, 1)
        XCTAssertEqual(state.spyScore, 0)
        let secret = try XCTUnwrap(state.secret)
        XCTAssertEqual(secret.role, .tracker)
        XCTAssertEqual(secret.side, .spies)
        XCTAssertEqual(secret.spies, ["p_e"])
        XCTAssertEqual(secret.vote, true)
        XCTAssertNil(secret.card)
        XCTAssertEqual(state.seat("p_b")?.voted, true)
        XCTAssertNil(state.seat("p_a")?.role, "another player's role never arrives mid-game")
        XCTAssertEqual(state.tallies.first?.auto, ["p_d"])
        XCTAssertEqual(state.missions.first?.succeeded, true)
        XCTAssertEqual(state.seatedIds.count, 5)
        XCTAssertNil(room.liarsDice)
        XCTAssertNil(room.chess)
    }

    func testCountsWaitOnlyOnPeopleStillAtTheTable() throws {
        // Robin (p_d) has left: the server votes for him, so the phone does not wait on him.
        let room = try decode(votingJSON)
        XCTAssertEqual(MissionRules.stillToVote(room), 2, "Sam and Alex, not Robin")
        XCTAssertEqual(MissionRules.cardsIn(room).of, 3)
    }

    func testAMissionCardsTeamLeaveIsNotCountedAsStillToPlay() throws {
        let json = #"""
        { "id":"g_m", "game":"mission", "difficulty":"easy", "phase":"mission", "hostId":"p_a", "meId":"p_a",
          "seats":5, "mission":1, "team":["p_a","p_b"],
          "players":[{"id":"p_a","name":"Sam","status":"joined","seated":true,"onTeam":true,"played":true},
                     {"id":"p_b","name":"Robin","status":"left","seated":true,"onTeam":true,"played":false}],
          "serverNow":1 }
        """#
        let cards = MissionRules.cardsIn(try decode(json))
        XCTAssertEqual(cards.played, 1)
        XCTAssertEqual(cards.of, 1, "the leaver's card is the server's to play")
    }

    func testTheMissionFootnoteIsTheSameForEitherSide() {
        // One constant, no side in it: a crew phone and a spy phone read alike.
        XCTAssertTrue(MissionRules.missionFootnote.contains("Sabotage"))
    }

    func testAFinishedRoomShowsEveryRoleAndTheResult() throws {
        let json = #"""
        { "id":"g_m", "game":"mission", "difficulty":"hard", "phase":"finished", "hostId":"p_a", "meId":"p_a",
          "seats":5, "mission":4, "score":{"crew":3,"spies":1}, "trackerId":"p_e",
          "secret":{"role":"lookout","side":"crew","spies":["p_d","p_e"],"vote":null,"card":null},
          "players":[{"id":"p_a","name":"Sam","status":"joined","seated":true,"role":"lookout","side":"crew"},
                     {"id":"p_d","name":"Robin","status":"left","seated":true,"role":"spy","side":"spies"},
                     {"id":"p_e","name":"Alex","status":"joined","seated":true,"role":"tracker","side":"spies"}],
          "result":{"winner":"spies","reason":"hunt","guessId":"p_a"},
          "standings":[{"id":"p_e","name":"Alex","place":1,"role":"tracker","side":"spies","won":true,"left":false},
                       {"id":"p_d","name":"Robin","place":2,"role":"spy","side":"spies","won":false,"left":true},
                       {"id":"p_a","name":"Sam","place":2,"role":"lookout","side":"crew","won":false,"left":false}],
          "winnerIds":["p_e"], "serverNow":1790000010000 }
        """#
        let room = try decode(json)
        XCTAssertEqual(room.phase, .finished)
        let state = try XCTUnwrap(room.mission)
        XCTAssertEqual(state.seat("p_e")?.role, .tracker)
        XCTAssertEqual(state.seat("p_d")?.side, .spies)
        XCTAssertEqual(state.result, MissionResult(winner: .spies, reason: "hunt", guessId: "p_a"))
        XCTAssertEqual(room.standings?.map(\.id), ["p_e", "p_d", "p_a"], "the shared standings read the same rows")
        XCTAssertEqual(MissionRules.headline(state.result, mySide: .crew), "The spies win")
        XCTAssertEqual(MissionRules.headline(state.result, mySide: .spies), "Your side wins")
        XCTAssertEqual(MissionRules.reasonLine(state.result) { $0 == "p_a" ? "you" : "Sam" },
                       "The crew won three missions, but the Tracker found the Lookout: you.")
    }

    func testALobbyWithNoneOfItStillDecodes() throws {
        let json = #"{"id":"g_m","game":"mission","difficulty":"easy","phase":"lobby","hostId":"p_a","meId":"p_a","players":[{"id":"p_a","name":"Sam","status":"joined"}],"serverNow":1}"#
        let room = try decode(json)
        XCTAssertEqual(MissionScreenPhase.of(room), .lobby)
        let state = try XCTUnwrap(room.mission)
        XCTAssertNil(state.secret)
        XCTAssertEqual(state.teamSize, 0)
        XCTAssertEqual(state.maxPlayers, 10)
    }

    func testAnUnknownRoleIsNoSecretRatherThanAWrongOne() throws {
        let json = #"{"id":"g_m","game":"mission","phase":"roles","secret":{"role":"jester","side":"crew"},"serverNow":1}"#
        let state = try XCTUnwrap(try decode(json).mission)
        XCTAssertNil(state.secret)
        XCTAssertEqual(state.phase, .roles)
    }

    // MARK: - The rules the phone uses

    func testPickingATeamStopsAtItsSize() {
        var picked: [String] = []
        picked = MissionRules.toggle("a", in: picked, size: 2)
        picked = MissionRules.toggle("b", in: picked, size: 2)
        XCTAssertEqual(MissionRules.toggle("c", in: picked, size: 2), ["a", "b"], "full is full")
        XCTAssertEqual(MissionRules.toggle("a", in: picked, size: 2), ["b"])
    }

    func testTheLobbyLineCountsWhoIsMissing() {
        XCTAssertEqual(MissionRules.tableLine(players: 3), "Needs 2 more players — five to ten.")
        XCTAssertEqual(MissionRules.tableLine(players: 4), "Needs 1 more player — five to ten.")
        XCTAssertEqual(MissionRules.tableLine(players: 5), "5 players: 3 crew, 2 spies.")
        XCTAssertEqual(MissionRules.tableLine(players: 7), "7 players: 4 crew, 3 spies.")
        XCTAssertEqual(MissionRules.tableLine(players: 10), "10 players: 6 crew, 4 spies.")
    }

    func testOutcomesAndTalliesReadAsSentences() {
        XCTAssertEqual(MissionRules.outcomeLine(MissionOutcome(mission: 1, sabotages: 0, succeeded: true)),
                       "Mission 1 succeeded — no sabotage.")
        XCTAssertEqual(MissionRules.outcomeLine(MissionOutcome(mission: 4, needed: 2, sabotages: 1, succeeded: true)),
                       "Mission 4 succeeded — 1 sabotage, but it needed 2 to fail.")
        XCTAssertEqual(MissionRules.outcomeLine(MissionOutcome(mission: 3, sabotages: 2, succeeded: false)),
                       "Mission 3 was sabotaged — 2 sabotages.")
        XCTAssertEqual(MissionRules.headline(nil, mySide: .crew), "Nobody won")
        XCTAssertEqual(MissionRules.headline(MissionResult(winner: nil, reason: "abandoned"), mySide: nil), "Nobody won")
        XCTAssertEqual(MissionRules.reasonLine(MissionResult(winner: .spies, reason: "rejections")) { $0 },
                       "Five teams were turned down in a row.")
    }

    func testTheClockBarNeverLeavesZeroToOne() {
        XCTAssertEqual(MissionRules.timeLeft(endsAt: 10_000, totalMs: 10_000, now: 5_000), 0.5)
        XCTAssertEqual(MissionRules.timeLeft(endsAt: 10_000, totalMs: 10_000, now: 20_000), 0)
        XCTAssertEqual(MissionRules.timeLeft(endsAt: 10_000, totalMs: 10_000, now: -50_000), 1)
        XCTAssertEqual(MissionRules.timeLeft(endsAt: nil, totalMs: 10_000, now: 1), 1)
        XCTAssertEqual(MissionRules.timeLeft(endsAt: 1, totalMs: 0, now: 1), 1)
    }

    func testOnlyASpyRoleIsOnTheSpiesSide() {
        XCTAssertEqual(MissionRole.spy.side, .spies)
        XCTAssertEqual(MissionRole.tracker.side, .spies)
        XCTAssertEqual(MissionRole.lookout.side, .crew)
        XCTAssertEqual(MissionRole.crew.side, .crew)
    }

    func testEveryDifficultyHasItsOwnLine() {
        let lines = GameDifficulty.allCases.map { $0.line(for: .mission) }
        XCTAssertEqual(Set(lines).count, 3)
    }
}
