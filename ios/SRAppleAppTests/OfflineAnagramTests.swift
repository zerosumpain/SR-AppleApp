import XCTest
@testable import SRAppleApp

final class OfflineAnagramTests: XCTestCase {
    private typealias Rules = OfflineAnagramRules
    private let players = [OfflinePlayer(id: "a", name: "Ann"), OfflinePlayer(id: "b", name: "Ben")]
    /// "because", shuffled.
    private let letters = ["s", "e", "c", "a", "u", "b", "e"]

    override func setUp() {
        super.setUp()
        OfflineWordsTests.install()
    }

    private func playing(_ who: [OfflinePlayer]? = nil) -> Rules.State {
        let seated = who ?? players
        var found: [String: [String]] = [:]
        for player in seated { found[player.id] = [] }
        var state = Rules.State(players: seated, seed: "because", letters: letters,
                                possible: Rules.possible(letters, list: OfflineWords.shared.list),
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

    func testTheOnlineGamesTileOpensThisOne() {
        XCTAssertEqual(OfflinePlayModes.offlineId(for: "anagram-blitz"), Rules.info.id)
        XCTAssertTrue(OfflinePlayModes.canPlaySolo(Rules.info, hasBot: false))
        XCTAssertTrue(OfflinePlayModes.canPlayNearby(Rules.info))
    }

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self, seed: 2026), [])
    }

    func testTheLettersAreACommonSevenLetterWordShuffled() {
        let pool = Array(OfflineWords.shared.list.seeds.prefix(Rules.pool))
        for seed: UInt64 in [1, 2, 3, 42, 99] {
            var rng = OfflineRNG(seed: seed)
            let state = Rules.start(players: players, now: 0, rng: &rng)
            XCTAssertTrue(pool.contains(state.seed), state.seed)
            XCTAssertEqual(state.letters.count, Rules.letterCount)
            XCTAssertEqual(state.letters.sorted(), state.seed.map { String($0) }.sorted())
            XCTAssertNotEqual(state.letters.joined(), state.seed, "never spelled out")
            XCTAssertEqual(state.possible.first?.word.count, 7, "a seven-letter answer exists")
            XCTAssertTrue(state.possible.contains { $0.word == state.seed })
        }
    }

    func testThePossibleWordsAllFitAndAreListed() {
        let possible = Rules.possible(letters, list: OfflineWords.shared.list)
        let words = possible.map(\.word)
        for word in ["because", "cause", "abuse", "sea", "cab", "bee"] { XCTAssertTrue(words.contains(word), word) }
        XCTAssertFalse(words.contains("seas"), "one S")
        for word in words {
            XCTAssertTrue(Rules.fits(word, letters), word)
            XCTAssertTrue(OfflineWords.shared.list.contains(word), word)
            XCTAssertGreaterThanOrEqual(word.count, Rules.minLength)
        }
        XCTAssertEqual(words, Rules.order(words), "longest first")
    }

    func testFitsCountsEachTile() {
        XCTAssertTrue(Rules.fits("bee", letters), "two Es on the rack")
        XCTAssertFalse(Rules.fits("beee", letters))
        XCTAssertFalse(Rules.fits("box", letters))
        XCTAssertFalse(Rules.fits("", letters))
    }

    // MARK: - Words

    func testLongerWordsScoreMore() throws {
        var state = playing()
        try act(.word("sea"), by: "a", in: &state)
        try act(.word(" Cause "), by: "a", in: &state)
        try act(.word("because"), by: "a", in: &state)
        XCTAssertEqual(state.found["a"], ["sea", "cause", "because"])
        XCTAssertEqual([3, 4, 5, 6, 7].map { Rules.points(String(repeating: "a", count: $0)) }, [1, 2, 4, 6, 10])
        let view = Rules.view(of: state, for: "a")
        XCTAssertEqual(view.mine?.map(\.word), ["because", "cause", "sea"], "newest first")
        XCTAssertEqual(view.board.first?.score, 15)
    }

    func testEveryRefusalSaysWhy() {
        var state = playing()
        XCTAssertEqual(refusal(.word("seas"), by: "a", in: state), "Use only the letters you have.")
        XCTAssertEqual(refusal(.word("box"), by: "a", in: state), "Use only the letters you have.")
        XCTAssertEqual(refusal(.word("be"), by: "a", in: state), "Words need at least 3 letters.")
        XCTAssertEqual(refusal(.word(""), by: "a", in: state), "Words need at least 3 letters.")
        XCTAssertEqual(refusal(.word("ecb"), by: "a", in: state), "Not in the word list.")
        XCTAssertEqual(refusal(.word("sea"), by: "z", in: state), "You are not in this game.")
        XCTAssertEqual(refusal(.ready, by: "a", in: state), "Not yet.")
        state.found["a"] = ["sea"]
        XCTAssertEqual(refusal(.word("sea"), by: "a", in: state), "You already have that one.")
        XCTAssertEqual(refusal(.word("sea"), by: "b", in: state, now: 121), "Time's up.")
        XCTAssertNil(refusal(.word("sea"), by: "b", in: state, now: 120.5))
        state.phase = .countdown
        XCTAssertEqual(refusal(.word("sea"), by: "b", in: state), "Wait for the start.")
    }

    // MARK: - The reveal

    func testAWordOnlyOnePlayerFoundScoresDoubleWithOthers() throws {
        var state = playing()
        try act(.word("cause"), by: "a", in: &state)
        try act(.word("sea"), by: "a", in: &state)
        try act(.word("sea"), by: "b", in: &state)
        XCTAssertEqual(Rules.view(of: state, for: "a").board.map(\.score), [5, 1], "raw while playing")
        state.phase = .reveal
        let view = Rules.view(of: state, for: "a")
        XCTAssertEqual(view.board.map(\.score), [9, 1])
        XCTAssertEqual(view.mine?.first { $0.word == "cause" }?.unique, true)
        XCTAssertEqual(view.mine?.first { $0.word == "cause" }?.points, 8)
        XCTAssertEqual(view.found?.map(\.word), ["cause", "sea"])
        XCTAssertEqual(view.found?.last?.finders, ["a", "b"])
        XCTAssertEqual(view.seed, "because")
        let missed = try XCTUnwrap(view.missed)
        XCTAssertEqual(missed.first, "because", "the seed leads when nobody found it")
        XCTAssertFalse(missed.contains("cause"))
        XCTAssertLessThanOrEqual(missed.count, Rules.missedShown)
        XCTAssertEqual(Rules.standings(state).map(\.score), [9, 1])
        XCTAssertEqual(Rules.standings(state).first?.detail, "2 words")

        var solo = playing([players[0]])
        try act(.word("cause"), by: "a", in: &solo)
        try act(.word("because"), by: "a", in: &solo)
        solo.phase = .reveal
        XCTAssertEqual(Rules.standings(solo).first?.score, 14, "alone, nothing doubles")
        XCTAssertEqual(Rules.standings(solo).first?.detail, "2 words · found BECAUSE")
    }

    func testTheRevealEndsWhenEveryoneTapsOnOrTheClockDoes() throws {
        var rng = OfflineRNG(seed: 4)
        var state = Rules.start(players: players, now: 0, rng: &rng)
        XCTAssertNil(Rules.view(of: state, for: "a").letters, "hidden in the countdown")
        Rules.tick(&state, now: Rules.countdown, rng: &rng)
        XCTAssertEqual(Rules.view(of: state, for: "a").letters?.count, 7)
        Rules.tick(&state, now: state.endsAt + Rules.grace, rng: &rng)
        XCTAssertEqual(state.phase, .reveal)
        try act(.ready, by: "a", in: &state)
        XCTAssertEqual(state.phase, .reveal)
        Rules.playerLeft("b", state: &state, now: 200, rng: &rng)
        XCTAssertTrue(Rules.isOver(state), "the one still here has tapped on")

        var waiting = Rules.start(players: players, now: 0, rng: &rng)
        Rules.tick(&waiting, now: 3, rng: &rng)
        Rules.tick(&waiting, now: 200, rng: &rng)
        Rules.tick(&waiting, now: 200 + Rules.revealSeconds, rng: &rng)
        XCTAssertTrue(Rules.isOver(waiting))
    }

    // MARK: - Secrets

    func testNobodySeesAnotherPlayersWordsOrTheSeedUntilTheReveal() throws {
        var state = playing()
        try act(.word("abuse"), by: "a", in: &state)
        let ben = Rules.view(of: state, for: "b")
        XCTAssertEqual(ben.mine, [])
        XCTAssertNil(ben.seed)
        XCTAssertNil(ben.found)
        XCTAssertNil(ben.missed)
        let text = String(decoding: try OfflineCoding.encode(ben), as: UTF8.self)
        XCTAssertFalse(text.contains("abuse"))
        XCTAssertFalse(text.contains("because"))
        let spectator = String(decoding: try OfflineCoding.encode(Rules.view(of: state, for: nil)), as: UTF8.self)
        XCTAssertFalse(spectator.contains("abuse"))
        XCTAssertFalse(spectator.contains("because"))
    }

    // MARK: - Through the room

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("anagram-blitz")
        try room.start(seed: 12, now: 0)
        var now = 0.0
        var played = false
        while room.phase == .playing && now < 400 {
            now += 0.5
            room.tick(now: now)
            let view = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "b")))
            if view.phase == .playing, !played, let letters = view.letters {
                // Ben finds the seven-letter word; Ann tries one that doesn't fit.
                let best = try XCTUnwrap(Rules.possible(letters, list: OfflineWords.shared.list).first)
                try room.act(OfflineCoding.encode(Rules.Action.word(best.word)), by: "b", match: 1, now: now)
                XCTAssertThrowsError(try room.act(OfflineCoding.encode(Rules.Action.word("zzz")), by: "a", match: 1, now: now))
                played = true
            }
            if view.phase == .reveal {
                for id in ["a", "b"] { try room.act(OfflineCoding.encode(Rules.Action.ready), by: id, match: 1, now: now) }
            }
        }
        XCTAssertTrue(played)
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.first?.playerId, "b")
        XCTAssertEqual(room.standings?.first?.score, 20, "seven letters, nobody else: 10 doubled")
    }
}
