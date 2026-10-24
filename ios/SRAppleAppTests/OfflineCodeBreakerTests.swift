import XCTest
@testable import SRAppleApp

/// Code Breaker's rules: the secret, the marking, who may guess what, the
/// end of the race, the table, and — above all — that nobody's phone ever
/// holds the code or another player's guesses while the race runs.
final class OfflineCodeBreakerTests: XCTestCase {
    private typealias Rules = CodeBreakerRules

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

    /// A state with a known code.
    private func known(_ secret: [Int] = [0, 1, 2, 3], now: Double = 100) -> (Rules.State, OfflineRNG) {
        var (state, rng) = started(now: now)
        state.secret = secret
        return (state, rng)
    }

    /// `id`'s next guess.
    private func guess(_ state: inout Rules.State, _ rng: inout OfflineRNG, _ id: String, _ pegs: [Int], now: Double = 110) throws {
        let number = (state.guesses[id]?.count ?? 0) + 1
        try Rules.apply(.guess(number: number, pegs: pegs), by: id, to: &state, now: now, rng: &rng)
    }

    private func refusal(_ body: () throws -> Void) -> String? {
        do { try body() } catch { return (error as? OfflineRefusal)?.reason ?? "not a refusal" }
        return nil
    }

    // MARK: - Setup

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self, seed: 99), [])
        XCTAssertEqual(Rules.info.id, "code-breaker")
        XCTAssertEqual(Rules.info.category, .skill)
        XCTAssertEqual(Rules.info.minPlayers, 1)
        XCTAssertEqual(Rules.info.maxPlayers, 5)
        XCTAssertEqual(Rules.colourNames.count, Rules.colours)
        XCTAssertEqual(Rules.symbols.count, Rules.colours)
        XCTAssertEqual(Rules.shapeNames.count, Rules.colours)
    }

    func testARaceOpensWithOneSecretAndNoGuesses() {
        let (state, _) = started(now: 100)
        XCTAssertEqual(state.secret.count, Rules.codeLength)
        XCTAssertTrue(state.secret.allSatisfy { $0 >= 0 && $0 < Rules.colours })
        XCTAssertEqual(state.phase, .playing)
        XCTAssertEqual(state.startedAt, 100)
        XCTAssertEqual(state.endsAt, 100 + Rules.raceSeconds)
        XCTAssertEqual(state.guesses, ["a": [], "b": [], "c": []])
        XCTAssertTrue(state.solvedAt.isEmpty)
        XCTAssertFalse(Rules.isOver(state))
    }

    func testTheSeedDecidesTheCode() {
        XCTAssertEqual(started(seed: 4).0.secret, started(seed: 4).0.secret)
        let codes = Set((1...30).map { started(seed: UInt64($0)).0.secret })
        XCTAssertGreaterThan(codes.count, 20, "different seeds give different codes")
    }

    // MARK: - Marking

    func testMarking() {
        func m(_ g: [Int], _ s: [Int]) -> [Int] {
            let r = Rules.mark(g, against: s)
            return [r.black, r.white]
        }
        XCTAssertEqual(m([0, 1, 2, 3], [0, 1, 2, 3]), [4, 0])
        XCTAssertEqual(m([3, 2, 1, 0], [0, 1, 2, 3]), [0, 4])
        XCTAssertEqual(m([4, 4, 5, 5], [0, 1, 2, 3]), [0, 0])
        XCTAssertEqual(m([0, 0, 1, 1], [0, 1, 1, 1]), [3, 0])
        XCTAssertEqual(m([1, 1, 0, 0], [0, 0, 1, 2]), [0, 3])
        XCTAssertEqual(m([0, 0, 0, 0], [0, 1, 2, 3]), [1, 0], "one red in the code answers one red only")
        XCTAssertEqual(m([1, 0, 0, 0], [0, 1, 0, 2]), [1, 2])
        XCTAssertEqual(m([5, 5, 5, 2], [2, 5, 4, 4]), [1, 1])
    }

    // MARK: - Guessing

    func testAGuessIsMarkedAndCounted() throws {
        var (state, rng) = known([0, 1, 2, 3])
        try guess(&state, &rng, "a", [0, 2, 4, 4])
        XCTAssertEqual(state.guesses["a"], [Rules.Guess(pegs: [0, 2, 4, 4], black: 1, white: 1)])
        XCTAssertNil(state.solvedAt["a"])
        try guess(&state, &rng, "a", [0, 1, 2, 3], now: 145.5)
        XCTAssertEqual(state.guesses["a"]?.count, 2)
        XCTAssertEqual(state.solvedAt["a"], 145.5)
        XCTAssertEqual(state.phase, .playing, "Ben and Cat are still going")
    }

    func testPlayersGuessIndependentlyNotInTurns() throws {
        var (state, rng) = known()
        try guess(&state, &rng, "b", [5, 5, 5, 5])
        try guess(&state, &rng, "b", [4, 4, 4, 4])
        try guess(&state, &rng, "a", [0, 0, 0, 0])
        try guess(&state, &rng, "c", [1, 1, 1, 1])
        XCTAssertEqual(state.guesses["a"]?.count, 1)
        XCTAssertEqual(state.guesses["b"]?.count, 2)
        XCTAssertEqual(state.guesses["c"]?.count, 1)
    }

    func testBadGuessesAreRefused() throws {
        var (state, rng) = known()
        XCTAssertEqual(refusal { try Rules.apply(.guess(number: 1, pegs: [0, 1, 2, 3]), by: "zed", to: &state, now: 110, rng: &rng) },
                       "You are not in this game.")
        XCTAssertEqual(refusal { try Rules.apply(.guess(number: 1, pegs: [0, 1, 2]), by: "a", to: &state, now: 110, rng: &rng) },
                       "A code has 4 pegs.")
        XCTAssertEqual(refusal { try Rules.apply(.guess(number: 1, pegs: [0, 1, 2, 3, 4]), by: "a", to: &state, now: 110, rng: &rng) },
                       "A code has 4 pegs.")
        XCTAssertEqual(refusal { try Rules.apply(.guess(number: 1, pegs: [0, 1, 6, 3]), by: "a", to: &state, now: 110, rng: &rng) },
                       "That isn't one of the colours.")
        XCTAssertEqual(refusal { try Rules.apply(.guess(number: 1, pegs: [-1, 1, 2, 3]), by: "a", to: &state, now: 110, rng: &rng) },
                       "That isn't one of the colours.")
        XCTAssertEqual(refusal { try Rules.apply(.guess(number: 2, pegs: [0, 1, 2, 4]), by: "a", to: &state, now: 110, rng: &rng) },
                       "That guess is out of order.")
        XCTAssertEqual(refusal { try Rules.apply(.guess(number: 0, pegs: [0, 1, 2, 4]), by: "a", to: &state, now: 110, rng: &rng) },
                       "That guess is out of order.")
        XCTAssertEqual(state.guesses["a"], [], "nothing refused was counted")

        try Rules.apply(.guess(number: 1, pegs: [5, 5, 5, 5]), by: "a", to: &state, now: 110, rng: &rng)
        XCTAssertEqual(refusal { try Rules.apply(.guess(number: 1, pegs: [5, 5, 5, 5]), by: "a", to: &state, now: 111, rng: &rng) },
                       "That guess was already counted.", "a double send counts once")
        XCTAssertEqual(state.guesses["a"]?.count, 1)
    }

    func testNoGuessesAfterCrackingItOrRunningOut() throws {
        var (state, rng) = known([0, 1, 2, 3])
        try guess(&state, &rng, "a", [0, 1, 2, 3])
        XCTAssertEqual(refusal { try self.guess(&state, &rng, "a", [0, 1, 2, 3]) }, "You have already cracked it.")

        for _ in 0..<Rules.maxGuesses { try guess(&state, &rng, "b", [5, 5, 5, 5]) }
        XCTAssertEqual(refusal { try self.guess(&state, &rng, "b", [0, 1, 2, 3]) }, "You have used all 10 guesses.")
        XCTAssertNil(state.solvedAt["b"])
    }

    // MARK: - The end

    func testTheRaceEndsWhenEveryoneIsDoneThenTheCodeIsShown() throws {
        var (state, rng) = known([0, 1, 2, 3])
        try guess(&state, &rng, "a", [0, 1, 2, 3], now: 130)
        for _ in 0..<Rules.maxGuesses { try guess(&state, &rng, "b", [5, 5, 5, 5], now: 140) }
        XCTAssertEqual(state.phase, .playing)
        try guess(&state, &rng, "c", [4, 1, 2, 3], now: 150)
        try guess(&state, &rng, "c", [0, 1, 2, 3], now: 160)
        XCTAssertEqual(state.phase, .reveal)
        XCTAssertEqual(state.revealUntil, 160 + Rules.revealPause)
        XCTAssertFalse(Rules.isOver(state), "the code is up for a few seconds first")
        XCTAssertEqual(refusal { try self.guess(&state, &rng, "b", [0, 1, 2, 3], now: 161) }, "The race is over.")

        Rules.tick(&state, now: state.revealUntil - 0.1, rng: &rng)
        XCTAssertEqual(state.phase, .reveal)
        Rules.tick(&state, now: state.revealUntil, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
    }

    func testTheClockStopsTheRace() throws {
        var (state, rng) = known([0, 1, 2, 3], now: 100)
        try guess(&state, &rng, "a", [5, 5, 5, 5], now: 120)
        Rules.tick(&state, now: state.endsAt - 0.1, rng: &rng)
        XCTAssertEqual(state.phase, .playing)
        XCTAssertEqual(refusal { try self.guess(&state, &rng, "a", [0, 1, 2, 3], now: state.endsAt) }, "Time is up.")
        Rules.tick(&state, now: state.endsAt + 0.05, rng: &rng)
        XCTAssertEqual(state.phase, .reveal)
        let revealEnds = state.revealUntil
        Rules.tick(&state, now: state.endsAt + 0.05, rng: &rng)
        XCTAssertEqual(state.revealUntil, revealEnds, "a repeated tick changes nothing")
        Rules.tick(&state, now: revealEnds + 1, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))
    }

    func testFewestGuessesWinsThenTheQuicker() throws {
        var (state, rng) = known([0, 1, 2, 3])
        // Ann: three guesses, slow. Ben: three guesses, quick. Cat: two guesses, slowest of all.
        try guess(&state, &rng, "a", [5, 5, 5, 5], now: 110)
        try guess(&state, &rng, "a", [4, 4, 4, 4], now: 120)
        try guess(&state, &rng, "a", [0, 1, 2, 3], now: 190)
        try guess(&state, &rng, "b", [5, 5, 5, 5], now: 110)
        try guess(&state, &rng, "b", [4, 4, 4, 4], now: 120)
        try guess(&state, &rng, "b", [0, 1, 2, 3], now: 130)
        try guess(&state, &rng, "c", [5, 5, 5, 5], now: 110)
        try guess(&state, &rng, "c", [0, 1, 2, 3], now: 300)
        XCTAssertEqual(Rules.ranking(state), ["c", "b", "a"])
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["c", "b", "a"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 3])
        XCTAssertEqual(table.map(\.score), [3, 2, 1])
        XCTAssertEqual(table.first?.detail, "cracked in 2 guesses · 3:20")
        XCTAssertEqual(table.last?.detail, "cracked in 3 guesses · 1:30")
    }

    func testThoseWhoDidNotCrackItShareTheBottom() throws {
        var (state, rng) = known([0, 1, 2, 3])
        try guess(&state, &rng, "b", [0, 1, 2, 3])
        try guess(&state, &rng, "a", [5, 5, 5, 5])
        Rules.tick(&state, now: state.endsAt, rng: &rng)
        let table = Rules.standings(state)
        XCTAssertEqual(table.map(\.playerId), ["b", "a", "c"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 2])
        XCTAssertEqual(table[1].detail, "not cracked · 1 guess")
        XCTAssertEqual(table[2].detail, "not cracked · 0 guesses")
    }

    func testNobodyCrackedItIsAllLevel() throws {
        var (state, rng) = known()
        Rules.tick(&state, now: state.endsAt, rng: &rng)
        XCTAssertEqual(Rules.standings(state).map(\.rank), [1, 1, 1])
        XCTAssertEqual(Rules.view(of: state, for: "a").leaders, [])
    }

    // MARK: - Leaving

    func testAPlayerWhoLeavesIsNotWaitedFor() throws {
        var (state, rng) = known([0, 1, 2, 3])
        try guess(&state, &rng, "a", [0, 1, 2, 3])
        try guess(&state, &rng, "b", [0, 1, 2, 3])
        try guess(&state, &rng, "c", [5, 1, 2, 3])
        Rules.playerLeft("c", state: &state, now: 150, rng: &rng)
        XCTAssertEqual(state.phase, .reveal, "Cat was the only one still guessing")
        XCTAssertEqual(state.away, ["c"])
        Rules.playerLeft("c", state: &state, now: 151, rng: &rng)
        XCTAssertEqual(state.away, ["c"], "leaving twice is leaving once")
        Rules.playerLeft("zed", state: &state, now: 151, rng: &rng)
        XCTAssertEqual(state.away, ["c"])
        XCTAssertEqual(Rules.standings(state).last?.detail, "not cracked · 1 guess · left")
    }

    func testAPlayerWhoComesBackCanCarryOn() throws {
        var (state, rng) = known([0, 1, 2, 3])
        Rules.playerLeft("c", state: &state, now: 105, rng: &rng)
        XCTAssertEqual(state.phase, .playing)
        try guess(&state, &rng, "c", [0, 1, 2, 4])
        XCTAssertEqual(state.away, [], "a guess from Cat's phone means it is back")
        XCTAssertEqual(state.guesses["c"]?.count, 1)
    }

    // MARK: - Nothing leaks

    func testNobodySeesTheCodeOrAnotherPlayersGuessesWhileRacing() throws {
        var (state, rng) = known([0, 1, 2, 3])
        try guess(&state, &rng, "a", [0, 1, 4, 4], now: 105)
        try guess(&state, &rng, "a", [0, 1, 2, 3], now: 112)
        try guess(&state, &rng, "b", [3, 3, 3, 3], now: 107)

        let ben = Rules.view(of: state, for: "b")
        XCTAssertNil(ben.secret)
        XCTAssertEqual(ben.myGuesses.map(\.pegs), [[3, 3, 3, 3]], "Ben sees only his own")
        XCTAssertEqual(ben.leaders, [])
        let annRow = try XCTUnwrap(ben.rows.first { $0.id == "a" })
        XCTAssertEqual(annRow.used, 2)
        XCTAssertTrue(annRow.solved)
        XCTAssertNil(annRow.seconds, "not even how long Ann took")

        let watcher = Rules.view(of: state, for: nil)
        XCTAssertNil(watcher.secret)
        XCTAssertEqual(watcher.myGuesses, [])
        XCTAssertEqual(Rules.view(of: state, for: "zed").myGuesses, [], "an unknown id is a spectator")

        // Nothing in the encoded view for Ben or a spectator carries Ann's pegs.
        for id in [Optional("b"), Optional("c"), nil] {
            let text = String(decoding: try OfflineCoding.encode(Rules.view(of: state, for: id)), as: UTF8.self)
            XCTAssertFalse(text.contains("\"secret\":["), "no code for \(id ?? "a spectator")")
            XCTAssertFalse(text.contains("[0,1,4,4]"), "no guess of Ann's for \(id ?? "a spectator")")
            XCTAssertFalse(text.contains("[0,1,2,3]"), "no code or guess of Ann's for \(id ?? "a spectator")")
        }

        let ann = Rules.view(of: state, for: "a")
        let annText = String(decoding: try OfflineCoding.encode(ann), as: UTF8.self)
        XCTAssertTrue(annText.contains("[0,1,4,4]"), "the search above would have found it")
        XCTAssertEqual(ann.myGuesses.count, 2)
        XCTAssertEqual(ann.myGuesses.last?.black, 4)
    }

    /// Each viewer's encoded view, read back as plain JSON, holds only that
    /// viewer's own guesses and no code, whoever is looking.
    func testEveryViewersJSONHoldsOnlyTheirOwnGuesses() throws {
        var (state, rng) = known([5, 4, 3, 2])
        let mine: [String: [[Int]]] = ["a": [[0, 0, 1, 1]], "b": [[2, 2, 0, 0], [1, 0, 1, 0]], "c": [[0, 1, 0, 1]]]
        for id in ["a", "b", "c"] {
            for pegs in mine[id] ?? [] { try guess(&state, &rng, id, pegs) }
        }
        XCTAssertEqual(state.phase, .playing)
        for viewer in ["a", "b", "c", nil, "zed"] as [String?] {
            let data = try OfflineCoding.encode(Rules.view(of: state, for: viewer))
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNil(object["secret"], "no code for \(viewer ?? "a spectator")")
            let guesses = try XCTUnwrap(object["myGuesses"] as? [[String: Any]])
            let pegs = guesses.compactMap { $0["pegs"] as? [Int] }
            XCTAssertEqual(pegs, viewer.flatMap { mine[$0] } ?? [], "guesses sent to \(viewer ?? "a spectator")")
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(text.contains("[5,4,3,2]"))
            for (owner, theirs) in mine where owner != viewer {
                for guess in theirs {
                    let written = "[" + guess.map(String.init).joined(separator: ",") + "]"
                    XCTAssertFalse(text.contains(written), "\(owner)'s guess leaked to \(viewer ?? "a spectator")")
                }
            }
        }
    }

    func testEverythingIsShownOnceTheRaceIsOver() throws {
        var (state, rng) = known([0, 1, 2, 3])
        try guess(&state, &rng, "b", [0, 1, 2, 3], now: 165)
        Rules.tick(&state, now: state.endsAt, rng: &rng)
        let ann = Rules.view(of: state, for: "a")
        XCTAssertEqual(ann.phase, .reveal)
        XCTAssertEqual(ann.secret, [0, 1, 2, 3])
        XCTAssertEqual(ann.leaders, ["b"])
        XCTAssertEqual(ann.rows.first { $0.id == "b" }?.seconds, 65)
        XCTAssertEqual(Rules.view(of: state, for: nil).secret, [0, 1, 2, 3])
    }

    func testPegNames() {
        XCTAssertEqual(Rules.pegName(0), "red circle")
        XCTAssertEqual(Rules.pegName(5), "purple heart")
        XCTAssertEqual(Rules.pegName(9), "empty")
        XCTAssertEqual(Rules.clock(65), "1:05")
    }

    // MARK: - Whole matches

    /// Random play for many seeds and every player count: guesses come in
    /// any order, some players leave, and every match ends without a throw.
    func testRandomRacesAlwaysFinish() throws {
        for seed in 1...200 {
            let count = (Int(seed) % 5) + 1
            let seats = (1...count).map { OfflinePlayer(id: "p\($0)", name: "P\($0)") }
            var rng = OfflineRNG(seed: UInt64(seed))
            var state = Rules.start(players: seats, now: 0, rng: &rng)
            var driver = OfflineRNG(seed: UInt64(seed) &* 31 &+ 7)
            var now = 0.0
            var steps = 0
            while !Rules.isOver(state) && steps < 5_000 {
                steps += 1
                now += driver.double(in: 0.05...3)
                Rules.tick(&state, now: now, rng: &rng)
                guard state.phase == .playing else { continue }
                let who = seats[driver.int(below: seats.count)].id
                if driver.chance(0.01) {
                    Rules.playerLeft(who, state: &state, now: now, rng: &rng)
                    continue
                }
                let done = state.solvedAt[who] != nil || (state.guesses[who]?.count ?? 0) >= Rules.maxGuesses
                let pegs = driver.chance(0.1) ? state.secret : (0..<Rules.codeLength).map { _ in driver.int(below: Rules.colours) }
                let number = (state.guesses[who]?.count ?? 0) + 1
                if done || now >= state.endsAt {
                    XCTAssertThrowsError(try Rules.apply(.guess(number: number, pegs: pegs), by: who, to: &state, now: now, rng: &rng))
                } else {
                    try Rules.apply(.guess(number: number, pegs: pegs), by: who, to: &state, now: now, rng: &rng)
                }
                for seat in seats where state.phase == .playing {
                    XCTAssertNil(Rules.view(of: state, for: seat.id).secret)
                }
            }
            XCTAssertTrue(Rules.isOver(state), "seed \(seed) finished")
            let table = Rules.standings(state)
            XCTAssertEqual(Set(table.map(\.playerId)), Set(seats.map(\.id)))
            XCTAssertEqual(table.first?.rank, 1)
            if let best = Rules.ranking(state).first, state.solvedAt[best] != nil {
                XCTAssertEqual(table.first?.playerId, best)
            }
        }
    }

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("code-breaker")
        try room.start(seed: 8, now: 0)
        let first = room.outbox()
        let benPacket = try XCTUnwrap(first.compactMap { item -> OfflineViewPacket? in
            if item.to == "b", case .view(let packet) = item.message { return packet }
            return nil
        }.first)
        let view = try OfflineCoding.decode(Rules.PlayerView.self, from: benPacket.data)
        XCTAssertEqual(view.rows.map(\.name), ["Ann", "Ben"])
        XCTAssertNil(view.secret)

        // Ben brute-forces a little from all-reds; Ann guesses once and waits.
        try room.act(OfflineCoding.encode(Rules.Action.guess(number: 1, pegs: [5, 5, 5, 5])), by: "a", match: 1, now: 1)
        var now = 1.0
        var number = 0
        while room.phase == .playing && now < 1_000 {
            now += 1
            room.tick(now: now)
            let mine = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "b")))
            guard mine.phase == .playing, number < Rules.maxGuesses else { continue }
            number += 1
            let pegs = (0..<Rules.codeLength).map { (number + $0) % Rules.colours }
            try room.act(OfflineCoding.encode(Rules.Action.guess(number: number, pegs: pegs)), by: "b", match: 1, now: now)
        }
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.count, 2)
    }
}
