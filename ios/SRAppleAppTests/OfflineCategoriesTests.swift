import XCTest
@testable import SRAppleApp

final class OfflineCategoriesTests: XCTestCase {
    private typealias Rules = OfflineCategoriesRules
    private let players = [OfflinePlayer(id: "a", name: "Ann"), OfflinePlayer(id: "b", name: "Ben"),
                           OfflinePlayer(id: "c", name: "Cat")]

    /// Letter B, a card of three.
    private func playing(_ who: [OfflinePlayer]? = nil) -> Rules.State {
        let seated = who ?? players
        var answers: [String: [String]] = [:]
        for player in seated { answers[player.id] = ["", "", ""] }
        var state = Rules.State(players: seated, letter: "b", categories: ["An animal", "A food", "A colour"],
                                answers: answers, startsAt: 0, endsAt: 120)
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

    private func statuses(_ state: Rules.State, _ index: Int) -> [Rules.Status] {
        Rules.judge(state, for: nil)[index].map(\.status)
    }

    // MARK: - The audit and the deal

    func testTheOnlineGamesTileOpensThisOne() {
        XCTAssertEqual(OfflinePlayModes.offlineId(for: "categories"), Rules.info.id)
        XCTAssertTrue(OfflinePlayModes.canPlaySolo(Rules.info, hasBot: false))
        XCTAssertTrue(OfflinePlayModes.canPlayNearby(Rules.info))
    }

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self, seed: 2026), [])
    }

    func testTheCardIsTheSitesDistinctList() {
        XCTAssertGreaterThan(Rules.card.count, 150)
        XCTAssertEqual(Set(Rules.card).count, Rules.card.count, "no category twice")
        XCTAssertTrue(Rules.card.allSatisfy { !$0.isEmpty && !$0.hasSuffix(".") })
    }

    func testTheDealIsOneLetterAndEightDifferentCategories() {
        for seed: UInt64 in [1, 2, 3, 99] {
            var rng = OfflineRNG(seed: seed)
            let state = Rules.start(players: players, now: 0, rng: &rng)
            XCTAssertTrue(Rules.letters.contains(state.letter))
            XCTAssertEqual(state.categories.count, Rules.cardSize)
            XCTAssertEqual(Set(state.categories).count, Rules.cardSize)
            XCTAssertTrue(state.categories.allSatisfy(Rules.card.contains))
            XCTAssertEqual(state.answers["b"], Array(repeating: "", count: Rules.cardSize))
        }
        var one = OfflineRNG(seed: 1), two = OfflineRNG(seed: 2)
        XCTAssertNotEqual(Rules.start(players: players, now: 0, rng: &one).categories,
                          Rules.start(players: players, now: 0, rng: &two).categories)
    }

    // MARK: - Reading answers

    func testAnswersAreReadTheSitesWay() {
        XCTAssertEqual(Rules.normalise("The Beatles"), "beatles")
        XCTAssertEqual(Rules.normalise("an Owl"), "owl")
        XCTAssertEqual(Rules.normalise("The"), "the", "a bare article stays")
        XCTAssertEqual(Rules.normalise("  Éclair  "), "eclair")
        XCTAssertEqual(Rules.normalise("Rock'n'roll"), "rocknroll")
        XCTAssertEqual(Rules.normalise("Mr. Bean"), "mr bean")
        XCTAssertTrue(Rules.startsWith("The Beatles", letter: "B"))
        XCTAssertTrue(Rules.startsWith("brie", letter: "b"))
        XCTAssertFalse(Rules.startsWith("A banana", letter: "a"), "the article goes")
        XCTAssertFalse(Rules.startsWith("", letter: "b"))
        XCTAssertEqual(Rules.sameKey("Blue Whale"), Rules.sameKey("bluewhale"))
    }

    func testAnAnswerIsTidiedAndCut() {
        XCTAssertEqual(Rules.clean("  big   bad\n wolf\t"), "big bad wolf")
        XCTAssertEqual(Rules.clean(String(repeating: "b", count: 60)).count, Rules.maxAnswer)
        XCTAssertEqual(Rules.clean("   "), "")
    }

    // MARK: - Playing

    func testAnswersAreWrittenOverAndClearedByEmpty() throws {
        var state = playing()
        try act(.answer(index: 0, text: "Badger"), by: "a", in: &state)
        try act(.answer(index: 0, text: "Bear "), by: "a", in: &state)
        try act(.answer(index: 2, text: "Blue"), by: "a", in: &state)
        try act(.answer(index: 2, text: ""), by: "a", in: &state)
        XCTAssertEqual(state.answers["a"], ["Bear", "", ""])
        XCTAssertEqual(Rules.view(of: state, for: "b").board.first { $0.id == "a" }?.filled, 1)
    }

    func testEveryRefusalSaysWhy() {
        var state = playing()
        XCTAssertEqual(refusal(.answer(index: 3, text: "Bob"), by: "a", in: state), "That category isn't on the card.")
        XCTAssertEqual(refusal(.answer(index: 0, text: "Bob"), by: "z", in: state), "You are not in this game.")
        XCTAssertEqual(refusal(.answer(index: 0, text: "Bob"), by: "a", in: state, now: 121), "Time's up.")
        XCTAssertNil(refusal(.answer(index: 0, text: "Bob"), by: "a", in: state, now: 120.5))
        XCTAssertEqual(refusal(.veto(owner: "b", index: 0, on: true), by: "a", in: state), "Vetoes come after the clock.")
        XCTAssertEqual(refusal(.done, by: "a", in: state), "Not yet.")
        state.phase = .countdown
        XCTAssertEqual(refusal(.answer(index: 0, text: "Bob"), by: "a", in: state), "Wait for the start.")
        state.phase = .review
        state.answers["b"] = ["Bat", "", ""]
        XCTAssertEqual(refusal(.answer(index: 0, text: "Bob"), by: "a", in: state), "Time's up.")
        XCTAssertEqual(refusal(.veto(owner: "a", index: 0, on: true), by: "a", in: state), "You can't veto your own answer.")
        XCTAssertEqual(refusal(.veto(owner: "b", index: 1, on: true), by: "a", in: state), "There is nothing there to veto.")
        XCTAssertEqual(refusal(.veto(owner: "q", index: 0, on: true), by: "a", in: state), "They are not in this game.")
        XCTAssertNil(refusal(.veto(owner: "b", index: 0, on: true), by: "a", in: state))
    }

    // MARK: - Judging

    func testRightLetterScoresSameAnswerSharesWrongLetterAndBlankDoNot() throws {
        var state = playing()
        try act(.answer(index: 0, text: "Badger"), by: "a", in: &state)
        try act(.answer(index: 0, text: "the badger"), by: "b", in: &state)
        try act(.answer(index: 0, text: "Cat"), by: "c", in: &state)
        try act(.answer(index: 1, text: "Bread"), by: "a", in: &state)
        try act(.answer(index: 1, text: "Banana"), by: "b", in: &state)
        state.phase = .review
        XCTAssertEqual(statuses(state, 0), [.shared, .shared, .wrongLetter])
        XCTAssertEqual(statuses(state, 1), [.ok, .ok, .empty])
        XCTAssertEqual(statuses(state, 2), [.empty, .empty, .empty])
        XCTAssertEqual(Rules.standings(state).map(\.score), [1, 1, 0])
        XCTAssertEqual(Rules.standings(state).last?.detail, "1 of 3 answered")
    }

    func testAloneEveryRightLetterCounts() throws {
        var state = playing([players[0]])
        try act(.answer(index: 0, text: "Badger"), by: "a", in: &state)
        try act(.answer(index: 1, text: "Apple"), by: "a", in: &state)
        var rng = OfflineRNG(seed: 1)
        Rules.tick(&state, now: 121, rng: &rng)
        XCTAssertEqual(state.phase, .review)
        XCTAssertEqual(state.reviewUntil, 121 + Rules.soloReviewSeconds)
        XCTAssertEqual(Rules.strikeAt(state, owner: "a"), 0, "nobody to veto")
        XCTAssertEqual(Rules.standings(state).first?.score, 1)
        XCTAssertFalse(Rules.view(of: state, for: "a").together)
        try act(.done, by: "a", in: &state, now: 130)
        XCTAssertTrue(Rules.isOver(state))
    }

    func testHalfTheOthersVetoingStrikesAnAnswer() throws {
        var state = playing()
        state.answers["a"] = ["Bob", "", ""]
        state.phase = .review
        XCTAssertEqual(Rules.strikeAt(state, owner: "a"), 1, "two others: one veto")
        try act(.veto(owner: "a", index: 0, on: true), by: "b", in: &state)
        try act(.veto(owner: "a", index: 0, on: true), by: "b", in: &state)
        XCTAssertEqual(state.vetoes[Rules.vetoKey("a", 0)], ["b"], "a veto twice is one veto")
        XCTAssertEqual(statuses(state, 0).first, .struck)
        let view = Rules.view(of: state, for: "b")
        XCTAssertEqual(view.review?[0].first?.vetoedByMe, true)
        XCTAssertEqual(Rules.view(of: state, for: "c").review?[0].first?.vetoedByMe, false)
        try act(.veto(owner: "a", index: 0, on: false), by: "b", in: &state)
        XCTAssertNil(state.vetoes[Rules.vetoKey("a", 0)])
        XCTAssertEqual(statuses(state, 0).first, .ok)

        // Five at the table: four others, two vetoes; a veto from someone who
        // has gone no longer counts, and their going lowers the bar.
        var five = playing(players + [OfflinePlayer(id: "d", name: "Dan"), OfflinePlayer(id: "e", name: "Eve")])
        five.answers["a"] = ["Bob", "", ""]
        five.phase = .review
        XCTAssertEqual(Rules.strikeAt(five, owner: "a"), 2)
        try act(.veto(owner: "a", index: 0, on: true), by: "b", in: &five)
        XCTAssertEqual(statuses(five, 0).first, .ok)
        try act(.veto(owner: "a", index: 0, on: true), by: "c", in: &five)
        XCTAssertEqual(statuses(five, 0).first, .struck)
        var rng = OfflineRNG(seed: 1)
        Rules.playerLeft("c", state: &five, now: 20, rng: &rng)
        Rules.playerLeft("d", state: &five, now: 20, rng: &rng)
        XCTAssertEqual(Rules.strikeAt(five, owner: "a"), 1)
        XCTAssertEqual(statuses(five, 0).first, .struck, "Ben's veto alone is now enough")
    }

    func testTheReviewEndsWhenEveryoneStillHereIsDone() throws {
        var rng = OfflineRNG(seed: 9)
        var state = Rules.start(players: players, now: 0, rng: &rng)
        XCTAssertNil(Rules.view(of: state, for: "a").letter, "hidden in the countdown")
        XCTAssertEqual(Rules.view(of: state, for: "a").categories, [])
        Rules.tick(&state, now: 3, rng: &rng)
        XCTAssertEqual(state.phase, .playing)
        Rules.tick(&state, now: state.endsAt + Rules.grace, rng: &rng)
        XCTAssertEqual(state.phase, .review)
        XCTAssertEqual(state.reviewUntil, state.endsAt + Rules.grace + Rules.reviewSeconds)
        try act(.done, by: "a", in: &state, now: 130)
        try act(.done, by: "b", in: &state, now: 130)
        XCTAssertEqual(state.phase, .review)
        Rules.playerLeft("c", state: &state, now: 131, rng: &rng)
        XCTAssertTrue(Rules.isOver(state))

        var slow = Rules.start(players: players, now: 0, rng: &rng)
        Rules.tick(&slow, now: 3, rng: &rng)
        Rules.tick(&slow, now: 200, rng: &rng)
        Rules.tick(&slow, now: 200 + Rules.reviewSeconds, rng: &rng)
        XCTAssertTrue(Rules.isOver(slow))
    }

    // MARK: - Secrets

    func testNobodySeesAnotherPlayersAnswersUntilTheReview() throws {
        var state = playing()
        try act(.answer(index: 0, text: "Bumblebee"), by: "a", in: &state)
        let ben = Rules.view(of: state, for: "b")
        XCTAssertEqual(ben.mine, ["", "", ""])
        XCTAssertNil(ben.review)
        XCTAssertFalse(String(decoding: try OfflineCoding.encode(ben), as: UTF8.self).contains("Bumblebee"))
        let spectator = Rules.view(of: state, for: nil)
        XCTAssertNil(spectator.mine)
        XCTAssertFalse(String(decoding: try OfflineCoding.encode(spectator), as: UTF8.self).contains("Bumblebee"))
        state.phase = .review
        XCTAssertEqual(Rules.view(of: state, for: "b").review?[0].first?.text, "Bumblebee")
    }

    // MARK: - Through the room

    func testAWholeMatchThroughTheRoom() throws {
        var room = OfflineRoom(host: players[0], roomName: "Ann's room", games: [OfflineGameEntry(Rules.self)])
        try room.join(players[1], version: OfflineEnvelope.version)
        try room.choose("categories")
        try room.start(seed: 13, now: 0)
        var now = 0.0
        var answered = false
        var vetoed = false
        while room.phase == .playing && now < 400 {
            now += 0.5
            room.tick(now: now)
            let view = try OfflineCoding.decode(Rules.PlayerView.self, from: XCTUnwrap(room.currentView(for: "a")))
            if view.phase == .playing, !answered, let letter = view.letter {
                // Ann fills two lines, Ben one the same as Ann's and one wrong.
                let first = letter.uppercased() + "anana"
                try room.act(OfflineCoding.encode(Rules.Action.answer(index: 0, text: first)), by: "a", match: 1, now: now)
                try room.act(OfflineCoding.encode(Rules.Action.answer(index: 1, text: letter + "lob")), by: "a", match: 1, now: now)
                try room.act(OfflineCoding.encode(Rules.Action.answer(index: 0, text: first.lowercased())), by: "b", match: 1, now: now)
                try room.act(OfflineCoding.encode(Rules.Action.answer(index: 2, text: "Zzz")), by: "b", match: 1, now: now)
                answered = true
            }
            if view.phase == .review, !vetoed {
                XCTAssertEqual(view.review?[0].map(\.status), [.shared, .shared])
                try room.act(OfflineCoding.encode(Rules.Action.veto(owner: "a", index: 1, on: true)), by: "b", match: 1, now: now)
                for id in ["a", "b"] { try room.act(OfflineCoding.encode(Rules.Action.done), by: id, match: 1, now: now) }
                vetoed = true
            }
        }
        XCTAssertTrue(answered && vetoed)
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.map(\.score), [0, 0], "Ann's one point was vetoed; the shared one scores nothing")
    }
}
