import Foundation

// The four letters a TV board shows, as the phone handles them — see
// SR-Main's `src/lib/games/screens.ts` (`CODE_ALPHABET`, `normaliseCode`).
//
// A game with a TV board (`lobby.screens`: Azul, Quiz Night and Codenames)
// is shown on a TV by opening strangeramblings.com/games/<game> there: the
// page shows a code, a player types it into the room's "Show on TV" sheet,
// and the site sends the TV a ticket for the room. The site decides whether
// a code is real; the phone only keeps the field to letters that could be one.
//
// Foundation only, so it runs in `scripts/home-check.sh` on Linux.

enum GameScreenCode {
    /// Consonants only, as the site's: no vowel means no word, and nothing
    /// that reads as 0/O or 1/I.
    static let alphabet = "BCDFGHJKLMNPQRSTVWXZ"
    static let length = 4

    /// What the field holds as somebody types: upper case, letters the site
    /// could have shown, at most four. "b-c d f" → "BCDF"; "bad" → "BD".
    static func typing(_ raw: String) -> String {
        String(raw.uppercased().filter { alphabet.contains($0) }.prefix(length))
    }

    /// A whole code, or nil if what was typed cannot be one.
    static func normalise(_ raw: String) -> String? {
        let code = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard code.count == length, code.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return code
    }

    /// Where the TV opens the board, as said to a person: no scheme.
    static func address(_ game: String) -> String { "strangeramblings.com/games/\(game)" }

    /// The sheet's instruction.
    static func instruction(_ game: String) -> String {
        "Open \(address(game)) on the TV, then type the four letters it shows."
    }
}
