import Foundation

// The Games page's decisions that are not drawing: which game the hero card
// offers, which tiles say NEW, what a quick filter leaves, how many players
// a game needs (the tile's chip, the lobby's "needs 1 more"), the motif drawn
// behind each tile, the leaderboard's podium, and the confetti a win throws.
//
// Foundation only, keyed by the wire's plain game id rather than `GameKind`,
// so the Linux harness can test it beside `GamesShelf.swift`.

/// The picture drawn behind a game's tile, the hero card and the lobby's
/// header: one per game, so a shelf of eleven tiles in the same colour still
/// reads as eleven games before a name is read.
enum GamesTileMotif: String, CaseIterable {
    /// A board of letter squares: Wordle, Boggle, Sequence Memory.
    case grid
    /// A chessboard's corner.
    case checker
    /// Concentric rings: a target, a bumper, a planet's pull.
    case rings
    /// A racing line with its dashes.
    case track
    /// Bursts of light.
    case sparkles
    /// A fan of cards.
    case cards
    /// Two dice and their pips.
    case dice
    /// Speech bubbles: questions and clues.
    case bubbles
    /// A maze's walls.
    case maze
    /// Numbered blocks, stacked.
    case blocks
    /// A snake's body and its apple.
    case snake
    /// Hills and a flag.
    case hills
    /// Contour lines and a pin.
    case map
    /// Scribbled lines: drawing games.
    case scribble
    /// Scattered dots: anything else.
    case dots

    /// The motif for a game id. An id this file has never heard of gets dots.
    static func of(_ game: String) -> GamesTileMotif {
        known[game] ?? .dots
    }

    private static let known: [String: GamesTileMotif] = [
        "tap-duel": .rings,
        "wordle-race": .grid,
        "quiz-night": .bubbles,
        "anagram-blitz": .blocks,
        "maths-sprint": .sparkles,
        "sequence-memory": .grid,
        "boggle": .grid,
        "categories": .bubbles,
        "liars-dice": .dice,
        "draw-guess": .scribble,
        "marble-race": .track,
        "chess": .checker,
        "mission": .dots,
        "one-clue": .bubbles,
        "fake-artist": .scribble,
        "pass-the-plate": .cards,
        "fireworks": .sparkles,
        "manhunt": .map,
        "homestead": .map,
        "hometowns": .map,
        "lander": .hills,
        "car-race": .track,
        "car-racer-plus": .track,
        "mini-golf": .hills,
        "pinball": .rings,
        "tilt-maze": .maze,
        "orbit": .rings,
        "solitaire": .cards,
        "merge-2048": .blocks,
        "minesweeper": .checker,
        "snake": .snake,
        "sky-hopper": .bubbles,
    ]
}

/// Why the hero card offers the game it does — its kicker.
enum GamesSpotlightReason: Equatable {
    /// The game this phone plays most.
    case favourite
    /// One of the new games, not yet played here.
    case new
    /// Nothing played and nothing new: the catalogue's first.
    case pick

    var kicker: String {
        switch self {
        case .favourite: return "Jump back in"
        case .new: return "New on this phone"
        case .pick: return "Try this one"
        }
    }
}

enum GamesPagePlan {
    /// The quick filters the page adds to `GamesShelf`'s: games this phone
    /// plays by itself, and games played in a room with the family.
    static let phoneFilter = "phone"
    static let familyFilter = "family"

    /// The games added to the phone in the autumn 2026 overhaul. Each says
    /// NEW on its tile until it is first played, or until February.
    static let newGames: Set<String> = [
        "car-racer-plus", "mini-golf", "pinball", "tilt-maze", "orbit",
        "solitaire", "merge-2048", "minesweeper", "snake", "sky-hopper",
    ]

    /// 2027-02-01 00:00 UTC: a NEW badge older than this is no longer news.
    static let newUntil = Date(timeIntervalSince1970: 1_801_440_000)

    /// Whether a game's tile says NEW: one of the new games, never played on
    /// this phone, before the badges retire.
    static func isNew(_ game: String, usage: HubUsage, now: Date) -> Bool {
        newGames.contains(game) && now < newUntil && usage.score(game, now: now) <= 0
    }

    /// The hero card's game and why: the favourite if there is one, else a
    /// new game not yet played (a different one each day, so the card is not
    /// the same picture for a week), else the first game offered. Nil only
    /// when nothing is offered at all.
    static func spotlight(games: [String], favourites: [String], usage: HubUsage,
                          now: Date) -> (game: String, reason: GamesSpotlightReason)? {
        if let top = favourites.first(where: games.contains) { return (top, .favourite) }
        let fresh = games.filter { isNew($0, usage: usage, now: now) }
        if !fresh.isEmpty {
            let day = max(0, Int((now.timeIntervalSince1970 / 86_400).rounded(.down)))
            return (fresh[day % fresh.count], .new)
        }
        guard let first = games.first else { return nil }
        return (first, .pick)
    }

    /// The shelves with only the games in `keep`; a shelf left empty goes.
    static func narrow(_ sections: [GamesShelf.Section], keep: Set<String>) -> [GamesShelf.Section] {
        sections.compactMap { section in
            let games = section.games.filter(keep.contains)
            guard !games.isEmpty else { return nil }
            return GamesShelf.Section(id: section.id, title: section.title, line: section.line, games: games)
        }
    }

    // MARK: - Players

    /// The fewest and most players a room game takes; nil for a game that
    /// can be played alone with no upper limit worth saying.
    static func players(_ game: String) -> (min: Int, max: Int?)? {
        switch game {
        case "chess": return (2, 2)
        case "mission": return (5, 10)
        case "one-clue": return (3, 7)
        case "fake-artist": return (4, 10)
        case "pass-the-plate": return (2, 5)
        case "fireworks": return (2, 5)
        case "manhunt": return (3, 8)
        case "homestead": return (3, 5)
        case "hometowns": return (1, 6)
        case "liars-dice": return (2, 5)
        case "draw-guess": return (2, 5)
        default: return nil
        }
    }

    /// The tile's chip, short: "2–5", "2", "1–6", "1+".
    static func playersChip(_ game: String, onPhone: Bool) -> String {
        if onPhone { return "Phone" }
        guard let range = players(game) else { return "1+" }
        guard let most = range.max else { return "\(range.min)+" }
        return most == range.min ? "\(most)" : "\(range.min)–\(most)"
    }

    /// The same, said in full: for VoiceOver and the new-game sheet.
    static func playersLine(_ game: String, onPhone: Bool) -> String {
        if onPhone { return "Played on this phone, no signal needed" }
        guard let range = players(game) else { return "Solo, or with the family" }
        guard let most = range.max else { return "\(range.min) or more players" }
        if most == range.min { return "\(most) players" }
        if range.min == 1 { return "Solo, or up to \(most) players" }
        return "\(range.min) to \(most) players"
    }

    /// The lobby's line on whether there are enough: "Needs 1 more player",
    /// "Room for 3 more", or nil when it has nothing to add.
    static func seatsLine(_ game: String, joined: Int) -> String? {
        guard let range = players(game) else { return nil }
        if joined < range.min {
            let short = range.min - joined
            return short == 1 ? "Needs 1 more player" : "Needs \(short) more players"
        }
        guard let most = range.max else { return nil }
        if joined > most { return "Too many: \(most) at most" }
        let room = most - joined
        if room == 0 { return "Full" }
        return room == 1 ? "Room for 1 more" : "Room for \(room) more"
    }

    /// How many empty seats the lobby draws after the players: the ones
    /// still needed to start, at least, and never more than four.
    static func emptySeats(_ game: String, joined: Int) -> Int {
        guard let range = players(game) else { return 0 }
        return min(4, max(0, range.min - joined))
    }

    // MARK: - Clocks

    /// "2:41", "0:07".
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    /// An invitation's clock: "Closes in 2:41", or "Closing…" at zero.
    static func closesLine(secondsLeft: Int) -> String {
        secondsLeft <= 0 ? "Closing…" : "Closes in \(clock(secondsLeft))"
    }

    // MARK: - The leaderboard's podium

    /// The first three on a podium and the rest in the list beneath — but
    /// only when there are two or more; one person alone is just a list.
    static func podium<Row>(_ rows: [Row], size: Int = 3) -> (top: [Row], rest: [Row]) {
        guard rows.count >= 2 else { return ([], rows) }
        let cut = min(size, rows.count)
        return (Array(rows.prefix(cut)), Array(rows.dropFirst(cut)))
    }

    /// The order the podium's steps stand in, left to right, as indexes into
    /// its rows: second, first, third — the winner in the middle.
    static func podiumOrder(_ count: Int) -> [Int] {
        switch count {
        case ..<1: return []
        case 1: return [0]
        case 2: return [1, 0]
        default: return [1, 0, 2]
        }
    }
}

// MARK: - Confetti

/// One piece of a win's confetti: where it starts, how it falls, how it
/// turns. Everything about its flight is worked out from the time alone, so
/// a frame allocates nothing and holds no state.
struct GameConfettiPiece: Equatable {
    /// Start, as a fraction of the field's width.
    let x: Double
    /// Sideways travel over the whole fall, in widths.
    let drift: Double
    /// Heights fallen a second.
    let speed: Double
    /// Seconds before it appears.
    let delay: Double
    /// Radians a second.
    let spin: Double
    /// Points across.
    let size: Double
    /// Which of the palette's colours.
    let colour: Int
    /// 0 a strip, 1 a disc.
    let shape: Int
    /// The sway's phase.
    let phase: Double
}

/// Where a piece is, as fractions of the field, and how it is turned and faded.
struct GameConfettiPose: Equatable {
    let x: Double
    let y: Double
    let angle: Double
    let opacity: Double
}

enum GameConfetti {
    /// How long a burst lasts, seconds. The view stops drawing after it.
    static let duration: Double = 2.8
    static let colours = 6

    /// `count` pieces from `seed`: the same seed, the same burst.
    static func pieces(count: Int, seed: UInt64) -> [GameConfettiPiece] {
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            // SplitMix64: small, fast, the same on every platform.
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            return Double(z >> 11) / Double(1 << 53)
        }
        return (0..<max(0, count)).map { _ in
            GameConfettiPiece(
                x: next(),
                drift: next() * 0.4 - 0.2,
                speed: 0.38 + next() * 0.4,
                delay: next() * 0.55,
                spin: (next() * 2 - 1) * 7,
                size: 5 + next() * 6,
                colour: Int(next() * Double(colours)) % colours,
                shape: next() < 0.65 ? 0 : 1,
                phase: next() * 6.283
            )
        }
    }

    /// The piece at `t` seconds into the burst, or nil before it appears and
    /// once it has fallen out of the field or the burst is over.
    static func pose(_ piece: GameConfettiPiece, at t: Double) -> GameConfettiPose? {
        let age = t - piece.delay
        guard age >= 0, t < duration else { return nil }
        // A little gravity on top of its own speed, from just above the top.
        let y = -0.06 + piece.speed * age + 0.12 * age * age
        guard y <= 1.08 else { return nil }
        let x = piece.x + piece.drift * min(1, age / 2) + 0.025 * sin(age * 5 + piece.phase)
        let fadeStart = duration - 0.6
        let opacity = t <= fadeStart ? 1 : max(0, (duration - t) / 0.6)
        return GameConfettiPose(x: x, y: y, angle: piece.phase + piece.spin * age, opacity: opacity)
    }
}
