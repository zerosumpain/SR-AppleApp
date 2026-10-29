import XCTest
@testable import SRAppleApp

final class CarRaceNearbyTests: XCTestCase {
    private typealias Rules = CarRaceNearbyRules
    private let players = [OfflinePlayer(id: "a", name: "Ann"), OfflinePlayer(id: "b", name: "Bo"), OfflinePlayer(id: "c", name: "Cy")]

    private func started(now: Double = 100) -> (Rules.State, OfflineRNG) {
        var rng = OfflineRNG(seed: 3)
        let state = Rules.start(players: players, now: now, rng: &rng)
        return (state, rng)
    }

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
    }

    /// A phone a build behind knows only the first three tracks: a race
    /// nearby must never draw a newer one.
    func testARaceNearbyIsOnATrackEveryPhoneKnows() {
        XCTAssertEqual(CarTrack.nearby.map(\.id), ["paddock", "riverside", "quarry"])
        for seed in 0..<40 {
            var rng = OfflineRNG(seed: UInt64(seed))
            let state = CarRaceNearbyRules.start(players: [OfflinePlayer(id: "a", name: "A")], now: 0, rng: &rng)
            XCTAssertTrue(CarTrack.nearby.contains { $0.id == state.trackId }, state.trackId)
        }
    }

    func testARaceStartsOnTheGridAfterACountdown() throws {
        var (state, rng) = started()
        let track = try XCTUnwrap(CarTrack.named(state.trackId))
        XCTAssertEqual(state.phase, .countdown)
        XCTAssertEqual(state.startsAt, 100 + Rules.countdown)
        XCTAssertEqual(state.racers.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(state.racers[1].x, track.grid(1).at.x, accuracy: 1e-9)
        Rules.tick(&state, now: 104, rng: &rng)
        XCTAssertEqual(state.phase, .countdown)
        Rules.tick(&state, now: 105, rng: &rng)
        XCTAssertEqual(state.phase, .racing)
    }

    func testPositionsKeepOnlyTheLatest() throws {
        var (state, rng) = started()
        Rules.tick(&state, now: 106, rng: &rng)
        try Rules.apply(.position(x: 1, y: 2, heading: 0.5, raced: 30, lap: 1, at: 0.8), by: "b", to: &state, now: 106, rng: &rng)
        XCTAssertEqual(state.racers[1].raced, 30)
        // An older report arriving late changes nothing.
        try Rules.apply(.position(x: 9, y: 9, heading: 0, raced: 10, lap: 1, at: 0.5), by: "b", to: &state, now: 106, rng: &rng)
        XCTAssertEqual(state.racers[1].x, 1)
        // A report from the future is ignored too.
        try Rules.apply(.position(x: 9, y: 9, heading: 0, raced: 10, lap: 1, at: 60), by: "b", to: &state, now: 106, rng: &rng)
        XCTAssertEqual(state.racers[1].x, 1)
        XCTAssertThrowsError(try Rules.apply(.position(x: 0, y: 0, heading: 0, raced: 0, lap: 1, at: 1), by: "z", to: &state, now: 106, rng: &rng))
    }

    func testFinishesAreCheckedAndStartTheGraceClock() throws {
        var (state, rng) = started()
        let length = try XCTUnwrap(CarTrack.named(state.trackId)).length
        Rules.tick(&state, now: 105, rng: &rng)
        // Too quick to be true, and in the future.
        XCTAssertThrowsError(try Rules.apply(.finish(time: 2, bestLap: nil), by: "a", to: &state, now: 200, rng: &rng))
        XCTAssertThrowsError(try Rules.apply(.finish(time: 150, bestLap: nil), by: "a", to: &state, now: 200, rng: &rng))
        let time = length * 3 / 30
        try Rules.apply(.finish(time: time, bestLap: time / 3), by: "a", to: &state, now: 105 + time + 0.2, rng: &rng)
        XCTAssertEqual(state.racers[0].finish, time)
        XCTAssertEqual(state.endsAt, 105 + time + 0.2 + Rules.finishGrace, accuracy: 1e-9)
        XCTAssertEqual(state.phase, .racing)
        // A second finish does not move the clock again.
        try Rules.apply(.finish(time: time + 4, bestLap: nil), by: "b", to: &state, now: 105 + time + 4.2, rng: &rng)
        XCTAssertEqual(state.endsAt, 105 + time + 0.2 + Rules.finishGrace, accuracy: 1e-9)
        // The grace runs out: over, with Cy unplaced.
        Rules.tick(&state, now: state.endsAt, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "b", "c"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(table[0].score, 3)
        XCTAssertTrue(table[2].detail?.hasPrefix("Did not finish") ?? false)
        XCTAssertThrowsError(try Rules.apply(.finish(time: time + 9, bestLap: nil), by: "c", to: &state, now: state.endsAt + 1, rng: &rng))
    }

    func testTheRaceEndsWhenEveryoneStillRacingIsHome() throws {
        var (state, rng) = started()
        let length = try XCTUnwrap(CarTrack.named(state.trackId)).length
        Rules.tick(&state, now: 105, rng: &rng)
        Rules.playerLeft("c", state: &state, now: 110, rng: &rng)
        XCTAssertTrue(state.racers[2].away)
        let time = length * 3 / 30
        try Rules.apply(.finish(time: time, bestLap: nil), by: "b", to: &state, now: 105 + time + 1, rng: &rng)
        XCTAssertEqual(state.phase, .racing)
        try Rules.apply(.finish(time: time + 1, bestLap: nil), by: "a", to: &state, now: 105 + time + 2, rng: &rng)
        XCTAssertEqual(state.phase, .over)
        XCTAssertEqual(Rules.standings(state).map(\.playerId), ["b", "a", "c"])
        XCTAssertEqual(Rules.standings(state).last?.detail, "Left the race")
    }

    func testTheLongestRaceEndsAnyway() {
        var (state, rng) = started()
        Rules.tick(&state, now: 105, rng: &rng)
        Rules.tick(&state, now: 105 + Rules.longest, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
    }
}
