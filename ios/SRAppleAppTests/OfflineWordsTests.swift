import XCTest
@testable import SRAppleApp

/// The word list the offline Boggle and Anagram Blitz judge by: that the
/// bundled file reads as the site's list (sorted, a–z, three to nine letters,
/// common words marked, seven-letter seeds), and that the lookups the games
/// make — is it a word, does any word start like this, which words fit a rack —
/// answer as they should.
final class OfflineWordsTests: XCTestCase {

    /// Point `OfflineWords.shared` at the list in the source tree, unless it
    /// already has one (the app bundle on CI, or an earlier test). Linux has
    /// no app bundle; scripts/offline-check.sh copies the file to the same
    /// place relative to the tests, so walking up from this file finds it.
    static func install(file: StaticString = #filePath) {
        if !OfflineWords.shared.list.isEmpty { return }
        var directory = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        while directory.path.count > 1 {
            let candidate = directory.appendingPathComponent("SRAppleApp/Offline/Words/offline-words.txt")
            if FileManager.default.fileExists(atPath: candidate.path) {
                XCTAssertNoThrow(try OfflineWords.shared.use(contentsOf: candidate))
                return
            }
            directory.deleteLastPathComponent()
        }
        XCTFail("offline-words.txt is neither in the bundle nor beside the tests")
    }

    private var list: OfflineWordList { OfflineWords.shared.list }

    override func setUp() {
        super.setUp()
        Self.install()
    }

    func testTheListIsTheSitesThreeToNineLetterWords() {
        XCTAssertGreaterThan(list.count, 60_000)
        XCTAssertLessThan(list.count, 90_000)
        for word in ["cat", "dog", "quit", "colour", "color", "centre", "grey", "pyjamas", "tyres", "aardvark", "abandoned"] {
            XCTAssertTrue(list.contains(word), word)
        }
        for word in ["", "ca", "xyzzyq", "Cat", "cat's", "abandonment"] {
            XCTAssertFalse(list.contains(word), word)
        }
    }

    func testEveryWordIsLowerCaseAToZAndInOrder() {
        var previous = ""
        for index in 0..<list.count {
            let word = list.word(at: index)
            XCTAssertTrue((3...9).contains(word.count), word)
            XCTAssertTrue(word.unicodeScalars.allSatisfy { (97...122).contains($0.value) }, word)
            XCTAssertLessThan(previous, word)
            XCTAssertEqual(list.length(at: index), word.count)
            previous = word
        }
    }

    func testCommonWordsAreMarked() {
        XCTAssertTrue(list.isCommon("house"))
        XCTAssertTrue(list.isCommon("because"))
        XCTAssertTrue(list.contains("aalii"))
        XCTAssertFalse(list.isCommon("aalii"), "a word the site never shows as missed")
        XCTAssertFalse(list.isCommon("notaword"))
    }

    func testTheSeedsAreCommonSevenLetterWordsCommonestFirst() {
        XCTAssertEqual(list.seeds.count, 700)
        XCTAssertEqual(Array(list.seeds.prefix(3)), ["because", "nothing", "someone"])
        for seed in list.seeds {
            XCTAssertEqual(seed.count, 7, seed)
            XCTAssertTrue(list.isCommon(seed), seed)
        }
        XCTAssertEqual(Set(list.seeds).count, list.seeds.count)
    }

    func testPrefixesAreWhatTheBoggleSolverPrunesBy() {
        XCTAssertTrue(list.hasPrefix(Array("aardv".utf8)))
        XCTAssertTrue(list.hasPrefix(Array("cat".utf8)), "a word is its own prefix")
        XCTAssertTrue(list.hasPrefix([]))
        XCTAssertFalse(list.hasPrefix(Array("xq".utf8)))
        XCTAssertFalse(list.hasPrefix(Array("zzzzzzzzzz".utf8)))
    }

    func testWhichWordsFitARack() throws {
        var counts = Array(repeating: 0, count: 26)
        for scalar in "eat".unicodeScalars { counts[Int(scalar.value) - 97] += 1 }
        XCTAssertTrue(list.fits(at: try XCTUnwrap(list.index(of: Array("tea".utf8))), counts: counts))
        XCTAssertFalse(list.fits(at: try XCTUnwrap(list.index(of: Array("teat".utf8))), counts: counts),
                       "one T on the rack, two in the word")
    }

    // MARK: - Reading the format

    func testTheFormatIsReadForgivingly() {
        let text = """
        # a comment
        @words
        Cat
        ant
        bee

        Ant
        Bé
        x1
        @seeds
        because
        Ignored
        @other
        zebra
        """
        let small = OfflineWordList(data: Data(text.utf8))
        // Out of order, so it was sorted; "ant" twice, kept once and common
        // (the capital wins); junk lines skipped.
        XCTAssertEqual((0..<small.count).map(small.word(at:)), ["ant", "bee", "cat"])
        XCTAssertTrue(small.isCommon("ant"))
        XCTAssertTrue(small.isCommon("cat"))
        XCTAssertFalse(small.isCommon("bee"))
        XCTAssertEqual(small.seeds, ["because"])
        XCTAssertFalse(small.contains("zebra"))
    }

    func testAnEmptyListAnswersNo() {
        let empty = OfflineWordList.empty
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(empty.contains("cat"))
        XCTAssertFalse(empty.hasPrefix(Array("c".utf8)))
        XCTAssertEqual(empty.seeds, [])
    }

    #if os(iOS)
    /// The list ships in the app: XcodeGen puts the .txt in the resources
    /// phase. Without it the word games fall back to accepting anything.
    func testTheAppBundlesTheList() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: OfflineWords.resource,
                                                withExtension: OfflineWords.resourceExtension))
        let bundled = OfflineWordList(data: try Data(contentsOf: url))
        XCTAssertGreaterThan(bundled.count, 60_000)
    }
    #endif
}
