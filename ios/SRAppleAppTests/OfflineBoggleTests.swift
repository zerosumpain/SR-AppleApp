import XCTest
@testable import SRAppleApp

final class OfflineBoggleTests: XCTestCase {
    private typealias Rules = OfflineBoggleRules
    private let players = [OfflinePlayer(id: "a", name: "Ann"), OfflinePlayer(id: "b", name: "Ben")]

    /// A board with known words on it:
    ///
    ///     C  A  T  S
    ///     X  O  G  X
    ///     Z  V  J  K
    ///     Qu I  T  X
    private let grid = ["c", "a", "t", "s", "x", "o", "g", "x", "z", "v", "j", "k", "qu", "i", "t", "x"]

    override func setUp() {
        super.setUp()
        OfflineWordsTests.install()
    }

    private func playing(_ who: [OfflinePlayer]? = nil) -> Rules.State {
        let seated = who ?? players
        var found: [String: [Rules.Found]] = [:]
        for player in seated { found[player.id] = [] }
        var state = Rules.State(players: seated, grid: grid, solution: Rules.solve(grid, list: OfflineWords.shared.list),
                                found: found, startsAt: 0, endsAt: 120)
        state.phase = .playing
        return state
    }

    private func refusal(_ action: Rules.Action, by id: String, in state: Rules.State, now: Double = 10) -> String? {
        var copy = state
        var rng = OfflineRNG(seed: 1)
        do {
            try Rules.apply(action, by: id, to: &copy, now: now, rng: &rng)
            return nil
        } catch {
            return (error as? OfflineRefusal)?.reason ?? "\(error)"
        }
    }

    private func act(_ action: Rules.Action, by id: String, in state: inout Rules.State, now: Double = 10) throws {
        var rng = OfflineRNG(seed: 1)
        try Rules.apply(action, by: id, to: &state, now: now, rng: &rng)
    }

    // MARK: - The audit and the deal

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self, seed: 2026), [])
    }

    func testARollUsesEveryDieOnce() {
        for seed: UInt64 in [5, 6, 7] {
            var rng = OfflineRNG(seed: seed)
            let roll = Rules.roll(&rng)
            XCTAssertEqual(roll.count, 16)
            XCTAssertTrue(matches(roll[...], Rules.dice), "each face on a different die that has it: \(roll)")
        }
    }

    /// Whether every face can be put on its own die that shows it.
    private func matches(_ faces: ArraySlice<String>, _ dice: [[String]]) -> Bool {
        guard let face = faces.first else { return true }
        for (index, die) in dice.enumerated() where die.contains(face) {
            var rest = dice
            rest.remove(at: index)
            if matches(faces.dropFirst(), rest) { return true }
        }
        return false
    }

    func testTheDealIsRichAndSolved() {
        for seed: UInt64 in [1, 7, 42] {
            var rng = OfflineRNG(seed: seed)
            let state = Rules.start(players: players, now: 100, rng: &rng)
            XCTAssertEqual(state.phase, .countdown)
            XCTAssertEqual(state.startsAt, 100 + Rules.countdown)
            XCTAssertEqual(state.endsAt, 100 + Rules.countdown + Rules.seconds)
            XCTAssertGreaterThanOrEqual(state.solution.filter(\.common).count, Rules.floor, "seed \(seed)")
            for traced in state.solution {
                XCTAssertTrue(Rules.isPath(traced.path), traced.word)
                XCTAssertEqual(traced.path.map { state.grid[$0] }.joined(), traced.word)
                XCTAssertTrue(OfflineWords.shared.list.contains(traced.word), traced.word)
            }
            XCTAssertEqual(state.solution.map(\.word), Rules.order(state.solution.map(\.word)), "longest first")
        }
    }

    func testTheSolverFindsTheKnownWords() {
        let words = Rules.solve(grid, list: OfflineWords.shared.list).map(\.word)
        for word in ["cat", "cats", "cog", "quit"] { XCTAssertTrue(words.contains(word), word) }
        XCTAssertFalse(words.contains("ca"))
        XCTAssertEqual(Rules.solve(grid, list: .empty), [], "no list, nothing to solve by")
    }

    func testAdjacencyIncludesDiagonals() {
        XCTAssertEqual(Rules.neighbours(0), [1, 4, 5])
        XCTAssertEqual(Rules.neighbours(5), [0, 1, 2, 4, 6, 8, 9, 10])
        XCTAssertTrue(Rules.isPath([0, 5, 10, 15]))
        XCTAssertFalse(Rules.isPath([0, 2]), "not touching")
        XCTAssertFalse(Rules.isPath([0, 1, 0]), "a die twice")
        XCTAssertFalse(Rules.isPath([15, 16]), "off the board")
        XCTAssertFalse(Rules.isPath([]))
    }

    // MARK: - Words

    func testAWordScoresAPointALetterPastTwo() throws {
        var state = playing()
        try act(.word(path: [0, 1, 2]), by: "a", in: &state)
        try act(.word(path: [0, 1, 2, 3]), by: "a", in: &state)
        try act(.word(path: [12, 13, 14]), by: "a", in: &state)
        XCTAssertEqual(state.found["a"]?.map(\.word), ["cat", "cats", "quit"])
        XCTAssertEqual(Rules.points("cat"), 1)
        XCTAssertEqual(Rules.points("quit"), 2, "qu is two letters")
        let view = Rules.view(of: state, for: "a")
        XCTAssertEqual(view.mine?.map(\.word), ["quit", "cats", "cat"], "newest first")
        XCTAssertEqual(view.board.first?.score, 5)
    }

    func testEveryRefusalSaysWhy() {
        var state = playing()
        XCTAssertEqual(refusal(.word(path: [0, 2, 3]), by: "a", in: state), "That word isn't on the board.")
        XCTAssertEqual(refusal(.word(path: [0, 1]), by: "a", in: state), "Words need at least 3 letters.")
        XCTAssertEqual(refusal(.word(path: [8, 9, 10]), by: "a", in: state), "Not in the word list.")
        XCTAssertEqual(refusal(.word(path: [0, 1, 2]), by: "z", in: state), "You are not in this game.")
        XCTAssertEqual(refusal(.ready, by: "a", in: state), "Not yet.")
        state.found["a"] = [Rules.Found(word: "cat", path: [0, 1, 2])]
        XCTAssertEqual(refusal(.word(path: [0, 1, 2]), by: "a", in: state), "You already have that one.")
        XCTAssertEqual(refusal(.word(path: [0, 1, 2]), by: "b", in: state, now: 121.5), "Time's up.")
        XCTAssertNil(refusal(.word(path: [0, 1, 2]), by: "b", in: state, now: 120.5), "a word in the air still lands")
        state.phase = .countdown
        XCTAssertEqual(refusal(.word(path: [0, 1, 2]), by: "b", in: state), "Wait for the start.")
    }

    // MARK: - The clock and the reveal

    func testTheClockRunsCountdownPlayRevealOver() {
        var rng = OfflineRNG(seed: 3)
        var state = Rules.start(players: players, now: 0, rng: &rng)
        XCTAssertNil(Rules.view(of: state, for: "a").grid, "no dice in the countdown")
        Rules.tick(&state, now: Rules.countdown, rng: &rng)
        XCTAssertEqual(state.phase, .playing)
        XCTAssertEqual(Rules.view(of: state, for: "a").grid?.count, 16)
        Rules.tick(&state, now: state.endsAt + 0.5, rng: &rng)
        XCTAssertEqual(state.phase, .playing, "still in its grace")
        Rules.tick(&state, now: state.endsAt + Rules.grace, rng: &rng)
        XCTAssertEqual(state.phase, .reveal)
        let until = state.revealUntil
        Rules.tick(&state, now: until - 1, rng: &rng)
        XCTAssertEqual(state.phase, .reveal)
        Rules.tick(&state, now: until, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
    }

    func testTheRevealEndsWhenEveryoneStillHereTapsOn() throws {
        var state = playing(players + [OfflinePlayer(id: "c", name: "Cat")])
        state.phase = .reveal
        state.revealUntil = 500
        try act(.ready, by: "a", in: &state)
        try act(.ready, by: "a", in: &state)
        XCTAssertEqual(state.phase, .reveal)
        var rng = OfflineRNG(seed: 1)
        Rules.playerLeft("c", state: &state, now: 20, rng: &rng)
        XCTAssertEqual(state.phase, .reveal)
        try act(.ready, by: "b", in: &state)
        XCTAssertTrue(Rules.isOver(state))
    }

    func testSharedWordsCrossOutWithOthersButNeverAlone() throws {
        var state = playing()
        try act(.word(path: [0, 1, 2]), by: "a", in: &state)
        try act(.word(path: [0, 1, 2, 3]), by: "a", in: &state)
        try act(.word(path: [0, 1, 2]), by: "b", in: &state)
        // While playing, raw points.
        XCTAssertEqual(Rules.view(of: state, for: "b").board.map(\.score), [3, 1])
        state.phase = .reveal
        let view = Rules.view(of: state, for: "a")
        XCTAssertEqual(view.mine?.first { $0.word == "cat" }?.points, 0)
        XCTAssertEqual(view.mine?.first { $0.word == "cat" }?.shared, true)
        XCTAssertEqual(view.board.map(\.score), [2, 0])
        XCTAssertEqual(view.found?.map(\.word), ["cats", "cat"])
        XCTAssertEqual(view.found?.last?.finders, ["a", "b"])
        XCTAssertEqual(view.found?.last?.crossed, true)
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "b"])
        XCTAssertEqual(table.map(\.score), [2, 0])
        XCTAssertEqual(table.first?.detail, "2 words · longest CATS")

        var solo = playing([players[0]])
        try act(.word(path: [0, 1, 2]), by: "a", in: &solo)
        solo.phase = .reveal
        XCTAssertEqual(Rules.standings(solo).first?.score, 1)
        XCTAssertFalse(Rules.view(of: solo, for: "a").crossing)
    }

    func testTheRevealShowsTheBestCommonWordsNobodyFound() throws {
        var state = playing()
        try act(.word(path: [0, 1, 2]), by: "a", in: &state)
        state.phase = .reveal
        let view = Rules.view(of: state, for: "a")
        let missed = try XCTUnwrap(view.missed)
        XCTAssertFalse(missed.contains { $0.word == "cat" })
        XCTAssertLessThanOrEqual(missed.count, Rules.missedShown)
        for word in missed { XCTAssertTrue(OfflineWords.shared.list.isCommon(word.word), word.word) }
        XCTAssertEqual(view.possibleWords, state.solution.count)
    }

    // MARK: - Secrets

    func testNobodySeesAnotherPlayersWordsUntilTheReveal() throws {
        var state = playing()
        try act(.word(path: [0, 1, 2, 3]), by: "a", in: &state)
        let ben = Rules.view(of: state, for: "b")
        XCTAssertEqual(ben.mine, [])
        XCTAssertNil(ben.found)
        XCTAssertNil(ben.missed)
        XCTAssertEqual(ben.possibleWords, 0)
        XCTAssertEqual(ben.board.first { $0.id == "a" }?.words, 1, "a count, not the word")
        let data = try OfflineCoding.encode(ben)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("cats"))
        let spectator = Rules.view(of: state, for: nil)
        XCTAssertNil(spectator.mine)
        XCTAssertFalse(String(decoding: try OfflineCoding.encode(spectator), as: UTF8.self).contains("cats"))
    }

    // MARK: - Through the room

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("boggle")
        try room.start(seed: 11, now: 0)
        var now = 0.0
        var played = false
        while room.phase == .playing && now < 400 {
            now += 0.5
            room.tick(now: now)
            let view = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "a")))
            if view.phase == .playing, !played, let grid = view.grid {
                // Ann sends the board's longest word; Ben sends a non-word, refused.
                let best = try XCTUnwrap(Rules.solve(grid, list: OfflineWords.shared.list).first)
                try room.act(OfflineCoding.encode(Rules.Action.word(path: best.path)), by: "a", match: 1, now: now)
                XCTAssertThrowsError(try room.act(OfflineCoding.encode(Rules.Action.word(path: [0])), by: "b", match: 1, now: now))
                played = true
            }
            if view.phase == .reveal {
                for id in ["a", "b"] {
                    try room.act(OfflineCoding.encode(Rules.Action.ready), by: id, match: 1, now: now)
                }
            }
        }
        XCTAssertTrue(played)
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.first?.playerId, "a")
        XCTAssertGreaterThan(room.standings?.first?.score ?? 0, 0)
    }
}
