import Foundation

/// The word list the offline word games judge by: about seventy thousand
/// English words of three to nine letters, bundled as `offline-words.txt`
/// (Offline/Words/), so Boggle and Anagram Blitz can say "not a word" on a
/// plane. The words are the site's own Boggle and Anagram Blitz lists, cut to
/// nine letters (scripts/build-offline-words.mjs says where they come from
/// and carries the licence), so a word counts offline exactly when it would
/// count online.
///
/// The words are packed end to end in one byte array, sorted, and found by
/// binary search: a lookup and the Boggle solver's "does any word start like
/// this?" are the same search, and seventy thousand words cost about 600 KB
/// rather than the several megabytes a `Set<String>` and a trie would.
struct OfflineWordList: Equatable {
    /// Every word, lower-case a–z, sorted by byte, end to end.
    private let bytes: [UInt8]
    /// Where each word starts in `bytes`, and one past the last word's end.
    private let starts: [Int32]
    /// Whether each word is a common one — a word the games may show as one
    /// "nobody found". Rare words still count when somebody finds them.
    private let common: [Bool]
    /// Seven-letter common words a rack of letters is dealt from, commonest first.
    let seeds: [String]

    static let empty = OfflineWordList(bytes: [], starts: [0], common: [], seeds: [])

    private init(bytes: [UInt8], starts: [Int32], common: [Bool], seeds: [String]) {
        self.bytes = bytes
        self.starts = starts
        self.common = common
        self.seeds = seeds
    }

    var count: Int { common.count }
    var isEmpty: Bool { common.isEmpty }

    /// Reads the bundled format: `#` comment lines, then `@words` — one word
    /// a line, sorted, a capital first letter marking a common word — then
    /// `@seeds`. Anything that is not a–z is skipped rather than trusted.
    init(data: Data) {
        let raw = [UInt8](data)
        var words: [(start: Int, end: Int, common: Bool)] = []
        var seeds: [String] = []
        var section = ""
        var sorted = true
        var lineStart = 0
        for index in 0...raw.count {
            guard index == raw.count || raw[index] == 10 else { continue }
            var end = index
            if end > lineStart, raw[end - 1] == 13 { end -= 1 }
            defer { lineStart = index + 1 }
            guard end > lineStart else { continue }
            let first = raw[lineStart]
            if first == 35 { continue } // "#"
            if first == 64 { // "@"
                section = String(decoding: raw[(lineStart + 1)..<end], as: UTF8.self)
                continue
            }
            let isCapital = first >= 65 && first <= 90
            let rest = raw[(lineStart + 1)..<end]
            guard isCapital || (first >= 97 && first <= 122), rest.allSatisfy({ $0 >= 97 && $0 <= 122 }),
                  end - lineStart <= OfflineWordList.longest else { continue }
            switch section {
            case "words":
                if let last = words.last,
                   Self.order(raw, last.start, last.end, raw, lineStart, end, foldFirst: true) >= 0 {
                    sorted = false
                }
                words.append((lineStart, end, isCapital))
            case "seeds":
                if !isCapital { seeds.append(String(decoding: raw[lineStart..<end], as: UTF8.self)) }
            default:
                continue
            }
        }
        if !sorted {
            // Not the generator's output: sort it here, and keep the first of
            // any word listed twice (a common marking wins).
            words.sort { a, b in
                let order = Self.order(raw, a.start, a.end, raw, b.start, b.end, foldFirst: true)
                return order != 0 ? order < 0 : (a.common && !b.common)
            }
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(raw.count)
        var starts: [Int32] = [0]
        var common: [Bool] = []
        starts.reserveCapacity(words.count + 1)
        common.reserveCapacity(words.count)
        var previous: (start: Int, end: Int)?
        for word in words {
            if let previous, Self.order(raw, previous.start, previous.end, raw, word.start, word.end, foldFirst: true) == 0 {
                continue
            }
            previous = (word.start, word.end)
            bytes.append(raw[word.start] | 0x20) // lower-case the marker capital
            bytes.append(contentsOf: raw[(word.start + 1)..<word.end])
            starts.append(Int32(bytes.count))
            common.append(word.common)
        }
        self.init(bytes: bytes, starts: starts, common: common, seeds: seeds)
    }

    /// The longest word the list holds. Longer words are never looked up.
    static let longest = 16

    // MARK: - Asking

    /// Whether `word` (lower-case a–z) is in the list.
    func contains(_ word: String) -> Bool { index(of: Array(word.utf8)) != nil }

    /// Whether `word` is in the list and common.
    func isCommon(_ word: String) -> Bool { index(of: Array(word.utf8)).map { common[$0] } ?? false }

    /// The word's place in the list, or nil.
    func index(of word: [UInt8]) -> Int? {
        let at = lowerBound(word)
        guard at < count, compare(at, word) == 0 else { return nil }
        return at
    }

    /// Whether any word starts with `prefix` — the Boggle solver's pruning.
    func hasPrefix(_ prefix: [UInt8]) -> Bool {
        let at = lowerBound(prefix)
        guard at < count else { return false }
        let start = Int(starts[at]), end = Int(starts[at + 1])
        guard end - start >= prefix.count else { return false }
        for offset in 0..<prefix.count where bytes[start + offset] != prefix[offset] { return false }
        return true
    }

    func word(at index: Int) -> String {
        String(decoding: bytes[Int(starts[index])..<Int(starts[index + 1])], as: UTF8.self)
    }

    func isCommon(at index: Int) -> Bool { common[index] }

    /// The length in letters of the word at `index`, without making a String.
    func length(at index: Int) -> Int { Int(starts[index + 1] - starts[index]) }

    /// Whether the word at `index` can be spelled from `counts` (how many of
    /// each letter a–z are free), each letter used no more often than that.
    func fits(at index: Int, counts: [Int]) -> Bool {
        var left = counts
        for offset in Int(starts[index])..<Int(starts[index + 1]) {
            let letter = Int(bytes[offset]) - 97
            guard letter >= 0, letter < 26, left[letter] > 0 else { return false }
            left[letter] -= 1
        }
        return true
    }

    // MARK: - Searching

    /// The first index whose word is not below `key`.
    private func lowerBound(_ key: [UInt8]) -> Int {
        var low = 0, high = count
        while low < high {
            let mid = (low + high) / 2
            if compare(mid, key) < 0 { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// The word at `index` against `key`: below zero, zero or above, by byte.
    private func compare(_ index: Int, _ key: [UInt8]) -> Int {
        let start = Int(starts[index]), end = Int(starts[index + 1])
        let length = end - start
        for offset in 0..<min(length, key.count) {
            let a = bytes[start + offset], b = key[offset]
            if a != b { return a < b ? -1 : 1 }
        }
        return length == key.count ? 0 : (length < key.count ? -1 : 1)
    }

    /// Two runs of bytes by byte order, the first byte of each lower-cased
    /// (the file's capital marks a common word, not a different word).
    private static func order(_ a: [UInt8], _ aStart: Int, _ aEnd: Int,
                              _ b: [UInt8], _ bStart: Int, _ bEnd: Int, foldFirst: Bool) -> Int {
        let length = min(aEnd - aStart, bEnd - bStart)
        for offset in 0..<length {
            var x = a[aStart + offset], y = b[bStart + offset]
            if foldFirst && offset == 0 {
                x |= 0x20
                y |= 0x20
            }
            if x != y { return x < y ? -1 : 1 }
        }
        let la = aEnd - aStart, lb = bEnd - bStart
        return la == lb ? 0 : (la < lb ? -1 : 1)
    }
}

/// The phone's one word list, read from the app bundle the first time a word
/// game needs it (a few tens of milliseconds) and kept.
///
/// Rules call `OfflineWords.shared.list`; tests on Linux, where there is no
/// app bundle, hand it the file from the source tree with `use(contentsOf:)`.
/// If the bundle has no list — it always should — the list is empty and the
/// games fall back to accepting any word that fits the board or the rack,
/// so a broken build still plays rather than refusing everything.
final class OfflineWords: @unchecked Sendable {
    static let shared = OfflineWords()

    static let resource = "offline-words"
    static let resourceExtension = "txt"

    private let lock = NSLock()
    private var loaded: OfflineWordList?

    var list: OfflineWordList {
        lock.lock()
        defer { lock.unlock() }
        if let loaded { return loaded }
        let list = Self.bundled() ?? .empty
        loaded = list
        return list
    }

    /// Use the list in this file from now on, instead of the bundle's.
    func use(contentsOf url: URL) throws {
        let list = OfflineWordList(data: try Data(contentsOf: url))
        lock.lock()
        loaded = list
        lock.unlock()
    }

    private static func bundled() -> OfflineWordList? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: resourceExtension),
              let data = try? Data(contentsOf: url) else { return nil }
        return OfflineWordList(data: data)
    }
}
