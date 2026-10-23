import XCTest
@testable import SRAppleApp

/// Swipe Says' rules: the sequence, judging swipes (plain, red, circle),
/// scoring by speed, refusals, the shrinking windows, the end of the match,
/// players leaving, and what each phone is allowed to see.
final class OfflineSwipeSaysTests: XCTestCase {
    private typealias Rules = SwipeSaysRules

    private let players = [
        OfflinePlayer(id: "a", name: "Ann"),
        OfflinePlayer(id: "b", name: "Ben"),
        OfflinePlayer(id: "c", name: "Cat"),
    ]

    private func started(seed: UInt64 = 1, now: Double = 100) -> (Rules.State, OfflineRNG) {
        var rng = OfflineRNG(seed: seed)
        let state = Rules.start(players: players, now: now, rng: &rng)
        return (state, rng)
    }

    /// The open prompt.
    private func prompt(_ state: Rules.State) -> Rules.Prompt { state.prompts[state.index] }

    /// The swipe that scores on the open prompt (any arrow's answer for a circle).
    private func rightWay(_ state: Rules.State) -> Rules.Direction { prompt(state).expected ?? .up }

    private func wrongWay(_ state: Rules.State) -> Rules.Direction {
        prompt(state).expected?.opposite ?? .left
    }

    /// A swipe reported `ms` after the open prompt showed, arriving just after.
    private func swipe(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ id: String,
                       _ direction: Rules.Direction, ms: Int) throws {
        try Rules.apply(.swipe(prompt: state.index + 1, direction: direction, ms: ms), by: id, to: &state,
                        now: state.showAt + Double(ms) / 1000 + 0.05, rng: &rng)
    }

    /// A state whose open prompt is exactly `prompt`.
    private func withPrompt(_ prompt: Rules.Prompt, seed: UInt64 = 1) -> (Rules.State, OfflineRNG) {
        var (state, rng) = started(seed: seed)
        state.prompts[state.index] = prompt
        return (state, rng)
    }

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self, seed: 99), [])
        XCTAssertEqual(Rules.info.id, "swipe-says")
        XCTAssertEqual(Rules.info.category, .reaction)
        XCTAssertEqual(Rules.info.minPlayers, 2)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
    }

    func testAMatchOpensWithAPlainArrowAfterTheLeadIn() {
        for seed in UInt64(1)...40 {
            let (state, _) = started(seed: seed, now: 100)
            XCTAssertEqual(state.prompts.count, 25)
            XCTAssertEqual(state.index, 0)
            XCTAssertEqual(state.phase, .playing)
            XCTAssertEqual(state.showAt, 100 + Rules.leadIn)
            XCTAssertEqual(state.closesAt, state.showAt + 1.5, accuracy: 1e-9)
            XCTAssertNotNil(state.prompts[0].direction, "the first is never a circle")
            XCTAssertFalse(state.prompts[0].red, "nor red")
            XCTAssertEqual(state.scores, ["a": 0, "b": 0, "c": 0])
            XCTAssertFalse(Rules.isOver(state))
        }
    }

    func testTheSeedDecidesTheSequenceAndItMixesAllThreeKinds() {
        XCTAssertEqual(started(seed: 4).0.prompts, started(seed: 4).0.prompts)
        XCTAssertNotEqual(started(seed: 4).0.prompts, started(seed: 5).0.prompts)
        var circles = 0, reds = 0, plain = 0
        for seed in UInt64(1)...20 {
            for prompt in started(seed: seed).0.prompts {
                if prompt.isCircle { circles += 1 } else if prompt.red { reds += 1 } else { plain += 1 }
            }
        }
        XCTAssertGreaterThan(circles, 20)
        XCTAssertGreaterThan(reds, 50)
        XCTAssertGreaterThan(plain, 150)
    }

    func testPromptsMeanWhatTheySay() {
        XCTAssertEqual(Rules.Prompt(direction: .left, red: false).expected, .left)
        XCTAssertEqual(Rules.Prompt(direction: .left, red: true).expected, .right)
        XCTAssertEqual(Rules.Prompt(direction: .up, red: true).expected, .down)
        XCTAssertNil(Rules.Prompt.circle.expected)
        XCTAssertEqual(Rules.Prompt(direction: .up, red: true).instruction, "Red up: swipe down")
        XCTAssertEqual(Rules.Prompt.circle.instruction, "Circle: hold still")
    }

    func testWindowsShrinkFromOneAndAHalfSecondsToNineTenths() {
        XCTAssertEqual(Rules.windowFor(0), 1.5, accuracy: 1e-9)
        XCTAssertEqual(Rules.windowFor(24), 0.9, accuracy: 1e-9)
        XCTAssertEqual(Rules.windowMs(12), 1200)
        for index in 1..<25 { XCTAssertLessThan(Rules.windowFor(index), Rules.windowFor(index - 1)) }
    }

    func testPointsFallWithTimeButNeverBelowTen() {
        XCTAssertEqual(Rules.points(forMs: 0), 100)
        XCTAssertEqual(Rules.points(forMs: 300), 80)
        XCTAssertEqual(Rules.points(forMs: 450), 70)
        XCTAssertEqual(Rules.points(forMs: 1349), 11)
        XCTAssertEqual(Rules.points(forMs: 1400), 10)
    }

    func testAPlainArrowScoresTheRightWayBySpeed() throws {
        var (state, rng) = withPrompt(Rules.Prompt(direction: .left, red: false))
        try swipe(&state, &rng, "a", .left, ms: 300)
        try swipe(&state, &rng, "b", .right, ms: 250)
        XCTAssertEqual(state.answers["a"], Rules.Answer(direction: .left, ms: 300, verdict: .right, points: 80))
        XCTAssertEqual(state.answers["b"]?.verdict, .wrong)
        XCTAssertEqual(state.scores, ["a": 80, "b": 0, "c": 0])
        XCTAssertEqual(state.best["a"], 300)
        XCTAssertEqual(state.rights["a"], 1)
        XCTAssertEqual(state.index, 0, "still waiting for Cat")
    }

    func testARedArrowWantsTheOppositeWay() throws {
        var (state, rng) = withPrompt(Rules.Prompt(direction: .up, red: true))
        try swipe(&state, &rng, "a", .up, ms: 300)
        try swipe(&state, &rng, "b", .down, ms: 450)
        XCTAssertEqual(state.answers["a"]?.verdict, .wrong)
        XCTAssertEqual(state.answers["b"]?.verdict, .right)
        XCTAssertEqual(state.scores["b"], 70)
    }

    func testACircleRewardsHoldingStillAndPunishesAnySwipe() throws {
        var (state, rng) = withPrompt(.circle)
        try swipe(&state, &rng, "a", .left, ms: 400)
        XCTAssertEqual(state.answers["a"]?.verdict, .wrong)
        // Ben and Cat hold still: the prompt runs to its close.
        Rules.tick(&state, now: state.closesAt + Rules.lateGrace - 0.01, rng: &rng)
        XCTAssertEqual(state.index, 0)
        Rules.tick(&state, now: state.closesAt + Rules.lateGrace, rng: &rng)
        XCTAssertEqual(state.index, 1)
        XCTAssertEqual(state.lastIndex, 0)
        XCTAssertEqual(state.lastAnswers["a"]?.verdict, .wrong)
        XCTAssertEqual(state.lastAnswers["b"]?.verdict, .held)
        XCTAssertEqual(state.lastAnswers["c"]?.points, Rules.holdPoints)
        XCTAssertEqual(state.scores, ["a": 0, "b": 50, "c": 50])
        XCTAssertEqual(state.rights["b"], 1)
    }

    func testAMissedArrowScoresNothing() throws {
        var (state, rng) = withPrompt(Rules.Prompt(direction: .right, red: false))
        try swipe(&state, &rng, "a", .right, ms: 200)
        Rules.tick(&state, now: state.closesAt + Rules.lateGrace, rng: &rng)
        XCTAssertEqual(state.lastAnswers["b"], Rules.Answer(direction: nil, ms: nil, verdict: .missed, points: 0))
        XCTAssertEqual(state.scores["b"], 0)
        XCTAssertEqual(state.scores["a"], 87)
    }

    func testTooSoonAndTooSlowScoreNothing() throws {
        var (state, rng) = withPrompt(Rules.Prompt(direction: .down, red: false))
        // Under the anticipation floor: a guess.
        try swipe(&state, &rng, "a", .down, ms: 60)
        XCTAssertEqual(state.answers["a"]?.verdict, .tooSoon)
        // Right way, but slower than the 1.5 s window.
        try swipe(&state, &rng, "b", .down, ms: 1600)
        XCTAssertEqual(state.answers["b"]?.verdict, .tooSlow)
        // The phone saw no prompt yet.
        try Rules.apply(.early(prompt: 1, direction: .down), by: "c", to: &state, now: state.showAt - 0.2, rng: &rng)
        XCTAssertEqual(state.lastAnswers["c"]?.verdict, .tooSoon, "everyone answered, so it closed")
        XCTAssertEqual(state.scores, ["a": 0, "b": 0, "c": 0])
        XCTAssertEqual(state.index, 1)
    }

    func testASwipeArrivingLongBeforeThePromptIsTooSoon() throws {
        var (state, rng) = withPrompt(Rules.Prompt(direction: .left, red: false))
        try Rules.apply(.swipe(prompt: 1, direction: .left, ms: 300), by: "a", to: &state,
                        now: state.showAt - 1, rng: &rng)
        XCTAssertEqual(state.answers["a"]?.verdict, .tooSoon)
    }

    func testBadSwipesAreRefused() throws {
        var (state, rng) = withPrompt(Rules.Prompt(direction: .left, red: false))
        let at = state.showAt + 0.3
        func refused(_ action: Rules.Action, by id: String, _ reason: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertThrowsError(try Rules.apply(action, by: id, to: &state, now: at, rng: &rng), file: file, line: line) { error in
                XCTAssertEqual((error as? OfflineRefusal)?.reason, reason, file: file, line: line)
            }
        }
        refused(.swipe(prompt: 1, direction: .left, ms: 300), by: "zed", "You are not in this game.")
        refused(.swipe(prompt: 2, direction: .left, ms: 300), by: "a", "That prompt hasn't come up yet.")
        refused(.swipe(prompt: 0, direction: .left, ms: 300), by: "a", "There is no such prompt.")
        refused(.swipe(prompt: 26, direction: .left, ms: 300), by: "a", "There is no such prompt.")
        refused(.swipe(prompt: 1, direction: .left, ms: -1), by: "a", "That time cannot be right.")
        refused(.swipe(prompt: 1, direction: .left, ms: 70_000), by: "a", "That time cannot be right.")
        try swipe(&state, &rng, "a", .left, ms: 300)
        refused(.swipe(prompt: 1, direction: .left, ms: 200), by: "a", "You have already answered this one.")
        refused(.early(prompt: 1, direction: .left), by: "a", "You have already answered this one.")

        Rules.playerLeft("c", state: &state, now: at, rng: &rng)
        refused(.swipe(prompt: 1, direction: .left, ms: 300), by: "c", "You have left this game.")

        try swipe(&state, &rng, "b", .left, ms: 400)
        XCTAssertEqual(state.index, 1, "Ann and Ben both answered; Cat is away")
        refused(.swipe(prompt: 1, direction: .left, ms: 300), by: "b", "That prompt has closed.")
        XCTAssertEqual(state.scores["a"], 80, "refusals changed nothing")
    }

    func testTheNextPromptFollowsAfterAGap() throws {
        var (state, rng) = started()
        let closedAt = state.showAt + 0.3 + 0.05
        for id in ["a", "b", "c"] { try swipe(&state, &rng, id, rightWay(state), ms: 300) }
        XCTAssertEqual(state.index, 1)
        XCTAssertEqual(state.lastIndex, 0)
        XCTAssertTrue(state.answers.isEmpty)
        XCTAssertGreaterThanOrEqual(state.showAt, closedAt + Rules.gapRange.lowerBound - 1e-9)
        XCTAssertLessThanOrEqual(state.showAt, closedAt + Rules.gapRange.upperBound + 1e-9)
        XCTAssertEqual(state.closesAt - state.showAt, Rules.windowFor(1), accuracy: 1e-9)
    }

    func testTickIsIdempotentAndCopesWithLateness() {
        var (state, rng) = started()
        Rules.tick(&state, now: state.showAt + 0.2, rng: &rng)
        XCTAssertEqual(state.index, 0)
        let late = state.closesAt + Rules.lateGrace + 3
        Rules.tick(&state, now: late, rng: &rng)
        XCTAssertEqual(state.index, 1)
        let once = state
        Rules.tick(&state, now: late, rng: &rng)
        XCTAssertEqual(state, once)
    }

    func testTwentyFivePromptsEndTheMatchAndTheHighestTotalWins() throws {
        var (state, rng) = started(seed: 3)
        var prompts = 0
        while state.phase == .playing {
            prompts += 1
            if prompt(state).isCircle {
                try swipe(&state, &rng, "c", .up, ms: 300) // Cat always swipes.
                Rules.tick(&state, now: state.closesAt + Rules.lateGrace, rng: &rng)
            } else {
                try swipe(&state, &rng, "a", rightWay(state), ms: 200)
                try swipe(&state, &rng, "b", rightWay(state), ms: 500)
                try swipe(&state, &rng, "c", wrongWay(state), ms: 300)
            }
        }
        XCTAssertEqual(prompts, 25)
        XCTAssertEqual(state.phase, .finished)
        XCTAssertFalse(Rules.isOver(state), "the final scores show first")
        XCTAssertEqual(Rules.champions(state), ["a"])
        XCTAssertEqual(Rules.view(of: state, for: "b").champions, ["a"])
        XCTAssertNil(Rules.view(of: state, for: "b").prompt)
        Rules.tick(&state, now: state.endsAt - 0.1, rng: &rng)
        XCTAssertFalse(Rules.isOver(state))
        Rules.tick(&state, now: state.endsAt, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))

        let circles = state.prompts.filter(\.isCircle).count
        XCTAssertEqual(state.scores["a"], (25 - circles) * 87 + circles * 50)
        XCTAssertEqual(state.scores["b"], (25 - circles) * 67 + circles * 50)
        XCTAssertEqual(state.scores["c"], 0)
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["a", "b", "c"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(table.first?.detail, "25 of 25 right · best 200 ms")
        XCTAssertEqual(table.last?.detail, "0 of 25 right")
        XCTAssertThrowsError(try Rules.apply(.swipe(prompt: 25, direction: .up, ms: 300), by: "a", to: &state, now: state.endsAt, rng: &rng))
    }

    func testTiesShareARank() throws {
        var (state, rng) = started()
        state.scores = ["a": 120, "b": 120, "c": 40]
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.rank), [1, 1, 3])
        state.phase = .finished
        XCTAssertEqual(Rules.champions(state), ["a", "b"])
        state.scores = ["a": 0, "b": 0, "c": 0]
        XCTAssertEqual(Rules.champions(state), [])
        _ = rng.next()
    }

    func testAPlayerWhoLeavesIsNotWaitedFor() throws {
        var (state, rng) = withPrompt(Rules.Prompt(direction: .up, red: false))
        try swipe(&state, &rng, "a", .up, ms: 300)
        try swipe(&state, &rng, "b", .up, ms: 300)
        Rules.playerLeft("c", state: &state, now: state.showAt + 0.4, rng: &rng)
        XCTAssertEqual(state.index, 1, "Cat was the only one left to swipe")
        XCTAssertNil(state.lastAnswers["c"], "an absent player is not marked as missing")
        Rules.playerLeft("c", state: &state, now: state.showAt, rng: &rng)
        XCTAssertEqual(state.away, ["c"], "leaving twice is the same as once")
        Rules.playerLeft("zed", state: &state, now: state.showAt, rng: &rng)
        XCTAssertEqual(state.away, ["c"])

        // A circle with Cat away: only Ann and Ben are credited for holding still.
        state.prompts[state.index] = .circle
        Rules.tick(&state, now: state.closesAt + Rules.lateGrace, rng: &rng)
        XCTAssertEqual(state.scores, ["a": 130, "b": 130, "c": 0])
        XCTAssertEqual(Rules.standings(state).last?.detail, "0 of 25 right · left")
    }

    func testOthersAnswersAndFuturePromptsStayHidden() throws {
        var (state, rng) = withPrompt(Rules.Prompt(direction: .left, red: true))
        try swipe(&state, &rng, "a", .right, ms: 250)
        let ben = Rules.view(of: state, for: "b")
        XCTAssertNil(ben.myAnswer)
        let annRow = try XCTUnwrap(ben.rows.first { $0.id == "a" })
        XCTAssertTrue(annRow.answered)
        XCTAssertNil(annRow.last, "Ben cannot see how Ann did yet")
        XCTAssertEqual(annRow.score, 0, "Ann's points on an open prompt would give her away")
        XCTAssertEqual(Rules.view(of: state, for: "a").rows.first { $0.id == "a" }?.score, 84,
                       "Ann's own total moves at once")
        XCTAssertEqual(Rules.view(of: state, for: nil).rows.map(\.score), [0, 0, 0])
        XCTAssertEqual(Rules.view(of: state, for: "a").myAnswer?.ms, 250, "Ann sees her own")
        let spectator = Rules.view(of: state, for: nil)
        XCTAssertNil(spectator.myAnswer)
        XCTAssertNil(spectator.myLast)

        // Only the open prompt travels; the rest of the sequence never does.
        for id: String? in ["a", "b", nil] {
            let data = try OfflineCoding.encode(Rules.view(of: state, for: id))
            let json = try XCTUnwrap(String(data: data, encoding: .utf8))
            XCTAssertFalse(json.contains("prompts"))
            XCTAssertEqual(Rules.view(of: state, for: id).prompt, state.prompts[0])
        }

        try swipe(&state, &rng, "b", .left, ms: 300)
        try swipe(&state, &rng, "c", .right, ms: 450)
        let after = Rules.view(of: state, for: "b")
        XCTAssertEqual(after.rows.map(\.last), [.right, .wrong, .right])
        XCTAssertEqual(after.rows.map(\.lastPoints), [84, 0, 70])
        XCTAssertEqual(after.lastNumber, 1)
        XCTAssertEqual(after.lastPrompt, Rules.Prompt(direction: .left, red: true))
        XCTAssertEqual(after.myLast?.verdict, .wrong)
        XCTAssertEqual(after.number, 2)
        XCTAssertEqual(after.prompt, state.prompts[1])
        XCTAssertFalse(after.rows.contains { $0.answered })
    }

    func testRandomPlayoutsAlwaysFinish() throws {
        let directions = Rules.Direction.allCases
        for seed in UInt64(1)...60 {
            var rng = OfflineRNG(seed: seed)
            var chooser = OfflineRNG(seed: seed &+ 1_000)
            let count = 2 + Int(seed % 4)
            let table = (0..<count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            var state = Rules.start(players: table, now: 0, rng: &rng)
            var now = 0.0
            var steps = 0
            while !Rules.isOver(state) && steps < 20_000 {
                steps += 1
                now += 0.1
                for player in table where state.phase == .playing && state.answers[player.id] == nil {
                    if seed % 7 == 0, player.id == "p1", now > 20 { Rules.playerLeft("p1", state: &state, now: now, rng: &rng) }
                    guard !state.away.contains(player.id), now >= state.showAt, chooser.chance(0.3) else { continue }
                    let ms = Int((now - state.showAt) * 1000)
                    let direction = chooser.pick(directions) ?? .up
                    try Rules.apply(.swipe(prompt: state.index + 1, direction: direction, ms: ms),
                                    by: player.id, to: &state, now: now, rng: &rng)
                }
                Rules.tick(&state, now: now, rng: &rng)
            }
            XCTAssertTrue(Rules.isOver(state), "seed \(seed) did not finish")
            XCTAssertEqual(Rules.standings(state).count, count)
            for player in table {
                XCTAssertGreaterThanOrEqual(state.scores[player.id] ?? -1, 0)
                XCTAssertLessThanOrEqual(state.scores[player.id] ?? 0, 25 * 100)
            }
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("swipe-says")
        try room.start(seed: 8, now: 0)
        let first = room.outbox()
        let annPacket = try XCTUnwrap(first.compactMap { item -> OfflineViewPacket? in
            if item.to == "a", case .view(let packet) = item.message { return packet }
            return nil
        }.first)
        let view = try OfflineCoding.decode(Rules.PlayerView.self, from: annPacket.data)
        XCTAssertEqual(view.rows.map(\.name), ["Ann", "Ben"])
        XCTAssertEqual(view.number, 1)

        var now = 0.0
        while room.phase == .playing && now < 600 {
            now += 0.1
            room.tick(now: now)
            guard room.phase == .playing else { break }
            let due = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "b")))
            if due.phase == .playing, now >= due.showAt, due.myAnswer == nil, let prompt = due.prompt,
               let expected = prompt.expected {
                // Ben is always right and quick; Ann is always right and slow.
                try room.act(OfflineCoding.encode(Rules.Action.swipe(prompt: due.number, direction: expected, ms: 210)),
                             by: "b", match: 1, now: now)
                try room.act(OfflineCoding.encode(Rules.Action.swipe(prompt: due.number, direction: expected, ms: 600)),
                             by: "a", match: 1, now: now)
            }
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.first?.playerId, "b")
        XCTAssertEqual(room.standings?.count, 2)
    }

    // MARK: - Review additions

    func testNoViewDependsOnAnotherPlayersSecrets() throws {
        var (state, rng) = withPrompt(Rules.Prompt(direction: .up, red: false))
        try swipe(&state, &rng, "a", .up, ms: 250)
        try swipe(&state, &rng, "b", .down, ms: 320)
        XCTAssertEqual(state.index, 0, "Cat has not answered, so the prompt is open")

        for viewer in ["a", "b", "c", nil] as [String?] {
            // Every prompt still to come changed, and every other player's
            // answer to the open prompt swapped for a different one (still
            // answered): what this phone is sent must not move.
            var other = state
            for index in other.prompts.indices where index > other.index {
                other.prompts[index] = .circle
            }
            for (id, answer) in other.answers where id != viewer {
                let flipped = Rules.Answer(direction: .left, ms: 999, verdict: .wrong, points: 0)
                other.scores[id, default: 0] += flipped.points - answer.points
                other.answers[id] = flipped
            }
            XCTAssertEqual(Rules.view(of: other, for: viewer), Rules.view(of: state, for: viewer),
                           "\(viewer ?? "a spectator") can see someone else's answer")
        }
    }
}
