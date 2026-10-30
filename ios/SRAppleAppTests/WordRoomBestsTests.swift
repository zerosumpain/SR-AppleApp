import XCTest
@testable import SRAppleApp

final class WordRoomBestsTests: XCTestCase {
    private func round(_ key: String, score: Int = 0, words: Int = 0, longest: String = "",
                       competitive: Bool = true, won: Bool = false) -> WordRoomRound {
        WordRoomRound(key: key, competitive: competitive, won: won, score: score, words: words, longest: longest)
    }

    private func wordle(_ key: String, solved: Bool, guesses: Int, ms: Int?, won: Bool = false) -> WordRoomRound {
        WordRoomRound(key: key, competitive: true, won: won, tracksStreak: true,
                      solved: solved, guesses: guesses, solveMs: ms)
    }

    func testTheFirstRoundSetsBestsButNothingIsNewYet() throws {
        var book = WordRoomBestBook()
        let news = try XCTUnwrap(book.record(round("a", score: 13, words: 5, longest: "Paint", won: true)))
        XCTAssertFalse(news.any, "a best needs something to beat")
        XCTAssertEqual(book.played, 1)
        XCTAssertEqual(book.won, 1)
        XCTAssertEqual(book.bestScore, 13)
        XCTAssertEqual(book.bestWords, 5)
        XCTAssertEqual(book.longest, "paint")
    }

    func testABetterRoundIsNewAndAWorseOneIsNot() throws {
        var book = WordRoomBestBook()
        book.record(round("a", score: 13, longest: "paint"))
        let better = try XCTUnwrap(book.record(round("b", score: 20, longest: "painter")))
        XCTAssertTrue(better.score)
        XCTAssertTrue(better.longest)
        let worse = try XCTUnwrap(book.record(round("c", score: 4, longest: "pain")))
        XCTAssertFalse(worse.any)
        XCTAssertEqual(book.bestScore, 20)
        XCTAssertEqual(book.longest, "painter")
        // A longest word of the same length does not replace the old one.
        book.record(round("d", longest: "trainer"))
        XCTAssertEqual(book.longest, "painter")
    }

    func testTheSameRoundIsCountedOnce() {
        var book = WordRoomBestBook()
        XCTAssertNotNil(book.record(round("g_1|100|grape", score: 5)))
        XCTAssertNil(book.record(round("g_1|100|grape", score: 50)))
        XCTAssertNil(book.record(round("", score: 50)), "no key, no count")
        XCTAssertEqual(book.played, 1)
        XCTAssertEqual(book.bestScore, 5)
    }

    func testOnlyTheRecentRoundsAreRemembered() {
        var book = WordRoomBestBook()
        for n in 0..<(WordRoomBestBook.memory + 5) { book.record(round("r\(n)")) }
        XCTAssertEqual(book.counted.count, WordRoomBestBook.memory)
        XCTAssertEqual(book.counted.last, "r\(WordRoomBestBook.memory + 4)")
        XCTAssertFalse(book.counted.contains("r0"))
    }

    func testASoloRoundIsPlayedNeverWon() {
        var book = WordRoomBestBook()
        book.record(round("a", score: 9, competitive: false, won: true))
        XCTAssertEqual(book.played, 1)
        XCTAssertEqual(book.won, 0)
        XCTAssertEqual(book.winPercent, 0)
        book.record(round("b", won: true))
        XCTAssertEqual(book.winPercent, 50)
    }

    func testWordleKeepsFewestGuessesFastestSolveAndTheStreak() throws {
        var book = WordRoomBestBook()
        book.record(wordle("a", solved: true, guesses: 4, ms: 90_000))
        let second = try XCTUnwrap(book.record(wordle("b", solved: true, guesses: 3, ms: 120_000)))
        XCTAssertTrue(second.guesses)
        XCTAssertFalse(second.time)
        XCTAssertTrue(second.streak, "two in a row beats one")
        XCTAssertEqual(book.fewestGuesses, 3)
        XCTAssertEqual(book.fastestMs, 90_000)
        XCTAssertEqual(book.streak, 2)
        let third = try XCTUnwrap(book.record(wordle("c", solved: true, guesses: 5, ms: 60_000)))
        XCTAssertTrue(third.time)
        XCTAssertEqual(book.fastestMs, 60_000)
        XCTAssertEqual(book.solved, 3)

        book.record(wordle("d", solved: false, guesses: 6, ms: nil))
        XCTAssertEqual(book.streak, 0, "a miss ends the run")
        XCTAssertEqual(book.bestStreak, 3)
        let back = try XCTUnwrap(book.record(wordle("e", solved: true, guesses: 4, ms: 70_000)))
        XCTAssertFalse(back.streak, "one in a row is not a new best run")
        XCTAssertEqual(book.streak, 1)
    }

    func testAWordGameRoundLeavesTheWordleStreakAlone() {
        var book = WordRoomBestBook()
        book.record(wordle("a", solved: true, guesses: 4, ms: 90_000))
        book.record(round("b", score: 3))
        XCTAssertEqual(book.streak, 1)
    }

    func testTheRoundKeyNamesTheRoomTheStartAndTheDeal() {
        XCTAssertEqual(WordRoomRound.key(roomId: "g_w", startedAt: 1_730_000_000_000.4, deal: "grape"),
                       "g_w|1730000000000|grape")
        XCTAssertEqual(WordRoomRound.key(roomId: "g_w", startedAt: nil, deal: ""), "g_w|0|")
    }

    func testTheStoreKeepsABookPerGameAndBoardSize() throws {
        let suite = "word-room-bests-test"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let anagram = WordRoomBestStore(defaults: defaults, game: .anagram)
        let boggle4 = WordRoomBestStore(defaults: defaults, game: .boggle, variant: "4x4")
        XCTAssertEqual(anagram.key, "anagram-blitz.bests.v1")
        XCTAssertEqual(boggle4.key, "boggle.bests.4x4.v1")

        let first = anagram.record(round("a", score: 12))
        XCTAssertEqual(first.book.bestScore, 12)
        XCTAssertNotNil(first.news)
        XCTAssertEqual(anagram.load().bestScore, 12)
        XCTAssertNil(anagram.record(round("a", score: 99)).news)
        XCTAssertEqual(boggle4.load(), WordRoomBestBook(), "another game's book is its own")

        // The demo counts a round in memory and writes nothing.
        let demo = WordRoomBestStore(defaults: defaults, game: .wordle)
        XCTAssertEqual(demo.record(wordle("z", solved: true, guesses: 3, ms: 1000), persist: false).book.solved, 1)
        XCTAssertEqual(demo.load().solved, 0)
        defaults.removePersistentDomain(forName: suite)
    }

    func testAnOlderBookWithMissingFieldsStillOpens() throws {
        let data = Data(#"{"played": 4, "bestScore": 21}"#.utf8)
        let book = try JSONDecoder().decode(WordRoomBestBook.self, from: data)
        XCTAssertEqual(book.played, 4)
        XCTAssertEqual(book.bestScore, 21)
        XCTAssertEqual(book.longest, "")
        XCTAssertEqual(book.counted, [])
        let again = try JSONDecoder().decode(WordRoomBestBook.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(again, book)
    }

    func testTheWordStateSaysWhatTheWordIsWorth() {
        XCTAssertEqual(WordRoomWordState.of(word: "", minLength: 3, mine: [], points: 0), .empty)
        XCTAssertEqual(WordRoomWordState.of(word: "pa", minLength: 3, mine: [], points: 0), .short(1))
        XCTAssertEqual(WordRoomWordState.of(word: "p", minLength: 4, mine: [], points: 0), .short(3))
        XCTAssertEqual(WordRoomWordState.of(word: "Paint", minLength: 3, mine: ["paint"], points: 4), .have)
        XCTAssertEqual(WordRoomWordState.of(word: "paint", minLength: 3, mine: ["pain"], points: 4), .worth(4))
        XCTAssertEqual(WordRoomWordState.short(1).text, "1 more letter")
        XCTAssertEqual(WordRoomWordState.short(2).text, "2 more letters")
        XCTAssertEqual(WordRoomWordState.worth(10).text, "+10")
        XCTAssertEqual(WordRoomWordState.have.text, "Have it")
        XCTAssertTrue(WordRoomWordState.worth(1).ready)
        XCTAssertFalse(WordRoomWordState.have.ready)
    }

    func testTheClockHurriesThenWarnsOnce() {
        XCTAssertEqual(WordRoomUrgency.of(msLeft: nil, limitMs: 120_000), .calm)
        XCTAssertEqual(WordRoomUrgency.of(msLeft: 100_000, limitMs: 120_000), .calm)
        XCTAssertEqual(WordRoomUrgency.of(msLeft: 29_000, limitMs: 300_000), .hurry)
        XCTAssertEqual(WordRoomUrgency.of(msLeft: 60_000, limitMs: 300_000), .hurry, "a quarter of five minutes")
        XCTAssertEqual(WordRoomUrgency.of(msLeft: 10_000, limitMs: 120_000), .last)
        XCTAssertEqual(WordRoomUrgency.of(msLeft: 0, limitMs: nil), .last)
        XCTAssertTrue(WordRoomUrgency.calm < WordRoomUrgency.last)
    }

    func testNamesAndHints() {
        XCTAssertEqual(WordRoomText.list([]), "")
        XCTAssertEqual(WordRoomText.list(["Sam"]), "Sam")
        XCTAssertEqual(WordRoomText.list(["Sam", "Robin"]), "Sam and Robin")
        XCTAssertEqual(WordRoomText.list(["Sam", "Robin", "Kit"]), "Sam, Robin and Kit")
        XCTAssertEqual(WordRoomText.number(5), "five")
        XCTAssertEqual(WordRoomText.number(14), "14")
        XCTAssertEqual(WordRoomText.wordleHint(typed: 0, length: 5, guessNumber: 1), "Type any five-letter word to start")
        XCTAssertEqual(WordRoomText.wordleHint(typed: 3, length: 5, guessNumber: 2), "2 more letters")
        XCTAssertEqual(WordRoomText.wordleHint(typed: 4, length: 5, guessNumber: 2), "1 more letter")
        XCTAssertEqual(WordRoomText.wordleHint(typed: 5, length: 5, guessNumber: 2), "Press Enter to guess")
        XCTAssertEqual(WordRoomText.wordleHint(typed: 0, length: 5, guessNumber: 3), "Use the colours: green stays, yellow moves")
        XCTAssertEqual(WordRoomText.clock(ms: 83_400), "1:23")
        XCTAssertEqual(WordRoomText.clock(ms: 0), "–")
    }

    func testTheOthersReadLikeALeaderboard() {
        let entries = [
            WordRoomRanking.Entry(id: "p_sam", name: "Sam", score: 7),
            WordRoomRanking.Entry(id: "p_robin", name: "Robin", score: 12),
            WordRoomRanking.Entry(id: "p_kit", name: "Kit", score: 7),
        ]
        XCTAssertEqual(WordRoomRanking.order(entries), ["p_robin", "p_kit", "p_sam"])
        XCTAssertEqual(WordRoomRanking.leader(entries), "p_robin")
        XCTAssertNil(WordRoomRanking.leader([entries[0], entries[2]]), "a tie at the top has no leader")
        XCTAssertNil(WordRoomRanking.leader([WordRoomRanking.Entry(id: "a", name: "A", score: 0)]))
    }

    func testTheWordleTileFitsTheSmallerOfWidthAndHeight() {
        // A 375pt phone's width, plenty of height: the width decides.
        XCTAssertEqual(WordRoomLayout.wordleTileSide(width: 360, height: 600, wordLength: 5, maxGuesses: 6), 62)
        XCTAssertEqual(WordRoomLayout.wordleTileSide(width: 300, height: 600, wordLength: 5, maxGuesses: 6), 54)
        // A short phone with the keyboard up: the height decides.
        XCTAssertEqual(WordRoomLayout.wordleTileSide(width: 335, height: 240, wordLength: 5, maxGuesses: 6), 36)
        // Never smaller than the floor; the page scrolls instead.
        XCTAssertEqual(WordRoomLayout.wordleTileSide(width: 335, height: 80, wordLength: 5, maxGuesses: 6), 30)
    }
}
