import Foundation

// The Play nearby shell's decisions, as pure values: the words on the
// results card, who stands where on the podium, which seats are still empty,
// why a game cannot start with this many, the order of the Play alone shelf,
// and where each piece of the win confetti is at a given instant.
//
// They used to be worked out inside the views, where only a phone could show
// them wrong. Here a Linux test holds them to it (OfflineShellTests).

enum OfflineShell {
    // MARK: - Results

    /// How a finished match went for this phone, for the results card's tone,
    /// its haptic and whether the confetti falls.
    enum Outcome: Equatable {
        /// Alone, one row: a score, nobody to beat.
        case solo
        /// First outright.
        case won
        /// First, with somebody else on the same rank.
        case tied
        /// Somewhere below first: 2 is second.
        case placed(Int)
        /// Not in the table: a phone that joined mid-match and watched.
        case watched
    }

    static func outcome(_ standings: [OfflineStanding], me: String, isSolo: Bool) -> Outcome {
        if isSolo, standings.count == 1 { return .solo }
        guard let mine = standings.first(where: { $0.playerId == me }) else { return .watched }
        if mine.rank == 1 {
            return standings.filter { $0.rank == 1 }.count > 1 ? .tied : .won
        }
        return .placed(mine.rank)
    }

    /// The results card's headline: "You win", "Sam wins", "You and Sam
    /// tie", "42 points" alone, "Game over" with an empty table.
    static func headline(_ standings: [OfflineStanding], me: String, isSolo: Bool) -> String {
        if isSolo, standings.count == 1, let mine = standings.first {
            return "\(mine.score) points"
        }
        let winners = standings.filter { $0.rank == 1 }
        // "You" leads a shared win ("You and Sam tie", never "Sam and You
        // tie"); everyone else keeps the table's order.
        let mine = winners.filter { $0.playerId == me }.map { _ in "You" }
        let names = mine + winners.filter { $0.playerId != me }.map(\.name)
        switch names.count {
        case 0: return "Game over"
        case 1: return names[0] == "You" ? "You win" : "\(names[0]) wins"
        default: return names.dropLast().joined(separator: ", ") + " and \(names.last ?? "") tie"
        }
    }

    /// One line under the headline, in the voice of a friendly scorer.
    static func strap(_ outcome: Outcome, best: Int?, score: Int?) -> String {
        switch outcome {
        case .solo:
            // A nought is never a best worth announcing, even a first one.
            if let best, let score, score > 0, score >= best { return "Your best on this phone." }
            if let best { return "Best on this phone: \(best)." }
            return "Your first score on this phone."
        case .won: return "Top of the table. Nicely played."
        case .tied: return "Level at the top — a share of the win."
        case .placed(let rank): return "You came \(ordinal(rank)). Another round?"
        case .watched: return "You joined part-way, so this one is not on your record."
        }
    }

    /// "1st", "2nd", "3rd", "4th", "11th", "21st".
    static func ordinal(_ n: Int) -> String {
        let tens = (n / 10) % 10
        let suffix: String
        if tens == 1 {
            suffix = "th"
        } else {
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    /// The podium, left to right: second, first, third — the classic shape,
    /// tallest in the middle. Only the first three rows of the table stand
    /// on it, and only when two or more played.
    static func podium(_ standings: [OfflineStanding]) -> [OfflineStanding] {
        guard standings.count >= 2 else { return [] }
        let top = Array(standings.prefix(3))
        if top.count == 2 { return [top[1], top[0]] }
        return [top[1], top[0], top[2]]
    }

    /// Height share (0...1) of a podium block for a rank: first tallest.
    static func podiumHeight(rank: Int) -> Double {
        switch rank {
        case 1: return 1
        case 2: return 0.72
        case 3: return 0.52
        default: return 0.4
        }
    }

    // MARK: - The lobby

    /// Empty seats to draw in the lobby: up to the chosen game's most, or
    /// the room's capacity when nothing is chosen. Never negative.
    static func emptySeats(seated: Int, capacity: Int, maxPlayers: Int?) -> Int {
        let limit = min(capacity, maxPlayers ?? capacity)
        return max(0, limit - seated)
    }

    /// Why a game cannot start with `count` players, in a few words for its
    /// row in the picker; nil when it fits.
    static func fitNote(minPlayers: Int, maxPlayers: Int, count: Int) -> String? {
        if count < minPlayers {
            let more = minPlayers - count
            return more == 1 ? "Needs 1 more player" : "Needs \(more) more players"
        }
        if count > maxPlayers {
            return maxPlayers == 1 ? "Just 1 player" : "Up to \(maxPlayers) players"
        }
        return nil
    }

    // MARK: - The shelves

    /// The Play alone shelf: the most played here first, the rest in
    /// catalogue order.
    static func shelfOrder(_ ids: [String], mostPlayed: [String]) -> [String] {
        ids.enumerated().sorted { a, b in
            let x = mostPlayed.firstIndex(of: a.element) ?? Int.max
            let y = mostPlayed.firstIndex(of: b.element) ?? Int.max
            return x == y ? a.offset < b.offset : x < y
        }.map(\.element)
    }

    /// Who a solo game is against.
    static func opponentLine(bots: Int) -> String {
        switch bots {
        case 0: return "Just you"
        case 1: return "You v the phone"
        default: return "You v \(bots) bots"
        }
    }

    /// The short tags on a game's card: "Solo v bots", "Nearby", "2–5 players".
    static func modeTags(canPlaySolo: Bool, bots: Int, playersLabel: String) -> [String] {
        var tags: [String] = []
        if canPlaySolo { tags.append(bots > 0 ? "Solo v bots" : "Solo") }
        tags.append("Nearby")
        tags.append(playersLabel)
        return tags
    }

    /// "Played once", "Played 3×"; nil before the first game.
    static func playedLine(_ played: Int) -> String? {
        guard played > 0 else { return nil }
        return played == 1 ? "Played once" : "Played \(played)×"
    }

    // MARK: - Time

    /// The last few seconds of a countdown, when it should pulse.
    static func isUrgent(secondsLeft: Int) -> Bool {
        secondsLeft > 0 && secondsLeft <= 3
    }
}

// MARK: - Confetti

/// One piece of the win confetti: where it starts, how it falls, spins and
/// sways. Fractions of the space it falls through, so one field fits any phone.
struct OfflineConfettiPiece: Equatable {
    /// Start across the width, 0...1.
    let x: Double
    /// Seconds before it starts to fall.
    let delay: Double
    /// Fall speed, heights a second.
    let speed: Double
    /// Turns a second.
    let spin: Double
    /// Sideways sway, a share of the width.
    let sway: Double
    /// Sway phase, radians.
    let phase: Double
    /// Points across.
    let size: Double
    /// Which colour of the field's palette.
    let colour: Int
}

/// Where a piece is at an instant: in points, and whether it is still on screen.
struct OfflineConfettiSpot: Equatable {
    let x: Double
    let y: Double
    /// Radians.
    let angle: Double
    let visible: Bool
}

/// A short, finite shower: every piece lands within `duration`, so the view
/// can stop drawing (and its timeline can pause) once it is over.
enum OfflineConfettiField {
    static let duration: Double = 2.8

    /// `count` pieces from `seed`: the same seed draws the same shower.
    static func pieces(count: Int, seed: UInt64, colours: Int) -> [OfflineConfettiPiece] {
        var state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        func next() -> Double {
            // SplitMix64: tiny, fast and good enough for paper.
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(UInt64(1) << 53)
        }
        let palette = max(1, colours)
        return (0..<max(0, count)).map { index in
            OfflineConfettiPiece(
                x: next(),
                delay: next() * 0.5,
                speed: 0.55 + next() * 0.5,
                spin: (next() - 0.5) * 3,
                sway: 0.02 + next() * 0.05,
                phase: next() * 2 * Double.pi,
                size: 6 + next() * 6,
                colour: index % palette
            )
        }
    }

    /// `piece` at `time` seconds into the shower, falling through a space
    /// `width` × `height` points from just above its top edge.
    static func spot(_ piece: OfflineConfettiPiece, at time: Double, width: Double, height: Double) -> OfflineConfettiSpot {
        let t = time - piece.delay
        guard t >= 0 else {
            return OfflineConfettiSpot(x: piece.x * width, y: -piece.size, angle: 0, visible: false)
        }
        let y = -piece.size + t * piece.speed * height
        let x = piece.x * width + sin(piece.phase + t * 4) * piece.sway * width
        let angle = piece.phase + t * piece.spin * 2 * Double.pi
        let visible = y < height + piece.size && t <= duration
        return OfflineConfettiSpot(x: x, y: y, angle: angle, visible: visible)
    }
}
