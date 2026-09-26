import Foundation

// Anagram Blitz's wire pieces and the rules the phone applies itself —
// building a word from the seven tiles, the tile order a shuffle gives — as
// pure values, so each is a unit test. The server judges every word; nothing
// here decides whether one counts or what it scores.

/// One of my words, as scored. `unique` is null until the game finishes;
/// then true for a word nobody else found (which scored double).
struct AnagramWord: Decodable, Equatable, Identifiable {
    let word: String
    let points: Int
    let unique: Bool?

    var id: String { word }

    init(word: String, points: Int, unique: Bool? = nil) {
        self.word = word
        self.points = points
        self.unique = unique
    }

    private enum CodingKeys: String, CodingKey { case word, points, unique }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = try c.decode(String.self, forKey: .word).lowercased()
        points = (try? c.decodeIfPresent(Int.self, forKey: .points)) ?? 0
        unique = (try? c.decodeIfPresent(Bool.self, forKey: .unique)) ?? nil
    }
}

/// A word somebody found, at the finish. `points` is the length's base
/// points; a `unique` word scored double for its one finder.
struct AnagramFound: Decodable, Equatable, Identifiable {
    let word: String
    let points: Int
    let finderIds: [String]
    let unique: Bool

    var id: String { word }

    private enum CodingKeys: String, CodingKey { case word, points, finderIds, unique }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = try c.decode(String.self, forKey: .word).lowercased()
        points = (try? c.decodeIfPresent(Int.self, forKey: .points)) ?? 0
        finderIds = (try? c.decodeIfPresent([String].self, forKey: .finderIds)) ?? []
        unique = (try? c.decodeIfPresent(Bool.self, forKey: .unique)) ?? false
    }

    /// What it scored its finder: double when nobody else found it.
    var scored: Int { unique ? points * 2 : points }
}

/// The word being built from the tiles.
///
/// A tile is picked by its POSITION in the dealt letters, not by its letter,
/// so a word can use a letter only as often as the tiles hold it: two Es on
/// the board, two Es in a word, never three. Tapping a picked tile takes that
/// tile back out; Delete takes the last one.
struct AnagramInput: Equatable {
    /// The dealt letters, lower-case, one per tile.
    let letters: [Character]
    /// Indices into `letters`, in the order picked.
    private(set) var picked: [Int] = []

    init(letters: [Character] = []) {
        self.letters = letters.map { Character($0.lowercased()) }
    }

    /// From the wire's `letters` (one-letter strings).
    init(tiles: [String]) {
        self.init(letters: tiles.compactMap(\.first))
    }

    var word: String { String(picked.map { letters[$0] }) }
    var isEmpty: Bool { picked.isEmpty }
    var count: Int { picked.count }

    func isPicked(_ tile: Int) -> Bool { picked.contains(tile) }

    /// Tap a tile: in if it is free, out if it is already in the word.
    /// False for a tile that does not exist.
    @discardableResult
    mutating func tap(_ tile: Int) -> Bool {
        guard tile >= 0, tile < letters.count else { return false }
        if let at = picked.firstIndex(of: tile) {
            picked.remove(at: at)
        } else {
            picked.append(tile)
        }
        return true
    }

    /// Add a letter by name (a hardware keyboard, a test): the first free tile
    /// that holds it. False when every tile with that letter is already used.
    @discardableResult
    mutating func add(_ character: Character) -> Bool {
        let lower = Character(character.lowercased())
        guard let tile = letters.indices.first(where: { letters[$0] == lower && !picked.contains($0) }) else {
            return false
        }
        picked.append(tile)
        return true
    }

    /// Removes the last tile picked. False when there was none.
    @discardableResult
    mutating func delete() -> Bool {
        guard !picked.isEmpty else { return false }
        picked.removeLast()
        return true
    }

    mutating func clear() { picked.removeAll() }
}

enum AnagramRules {
    /// The spec's points by length, for a room that did not send them.
    static let fallbackPoints: [Int: Int] = [3: 1, 4: 2, 5: 4, 6: 6, 7: 10]

    /// A word's base points, from the room's table.
    static func points(for word: String, table: [String: Int]) -> Int {
        table[String(word.count)] ?? fallbackPoints[word.count] ?? 0
    }

    /// Checked on the phone before a word is sent, in the server's order, so
    /// the obvious refusals answer at once. Nil when the word should go.
    static func localRefusal(word: String, minLength: Int, mine: [String]) -> String? {
        if word.count < minLength {
            return minLength > 3 ? "Words need at least \(minLength) letters on hard." : "Words need at least \(minLength) letters."
        }
        if mine.contains(word) { return "You already have that one." }
        return nil
    }

    /// A new order for the tiles: a permutation of `0..<count` that is not the
    /// one on screen (when there is any other). `random` picks; tests pass a
    /// seeded one.
    static func shuffled<G: RandomNumberGenerator>(_ order: [Int], using random: inout G) -> [Int] {
        guard order.count > 1 else { return order }
        var next = order
        for _ in 0..<8 {
            next.shuffle(using: &random)
            if next != order { return next }
        }
        // Eight shuffles that all landed where they started: rotate instead.
        return Array(order.dropFirst()) + [order[0]]
    }

    /// My words, newest first, for the list under the tiles.
    static func newestFirst(_ words: [AnagramWord]) -> [AnagramWord] { words.reversed() }
}
