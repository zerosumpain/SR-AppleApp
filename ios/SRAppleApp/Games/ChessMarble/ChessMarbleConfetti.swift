import Foundation

/// A burst of confetti for a win, worked out once and then only read: each
/// piece's place at time `t` is a sum, so the view drawing it allocates
/// nothing a frame. The same seed gives the same burst.
///
/// Positions are fractions of the field (0...1 across, 0 at the top), so the
/// view scales them to whatever size it is.
struct ChessMarbleConfetti: Equatable {
    struct Piece: Equatable {
        /// Where it starts, across the field.
        let x: Double
        /// Where it starts, down the field (a little above the top).
        let y: Double
        /// Drift across, fractions of the width a second.
        let vx: Double
        /// Speed down at the start, fractions of the height a second (negative is up).
        let vy: Double
        /// Turns a second.
        let spin: Double
        /// Which of the view's colours.
        let colour: Int
        /// Its size, as a fraction of the field's width.
        let size: Double
        /// When it starts falling, seconds after the burst.
        let delay: Double
    }

    /// How long the burst lasts, seconds: every piece is past the bottom by then.
    static let duration: Double = 3.2
    /// Fractions of the height a second, a second.
    static let gravity: Double = 0.55

    let pieces: [Piece]

    static func make(count: Int, colours: Int, seed: UInt64) -> ChessMarbleConfetti {
        var state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        func next() -> Double {
            // xorshift64*: small, fast and the same everywhere.
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            let value = state &* 0x2545_F491_4F6C_DD1D
            return Double(value >> 11) / Double(1 << 53)
        }
        var out: [Piece] = []
        out.reserveCapacity(max(0, count))
        for _ in 0..<max(0, count) {
            out.append(Piece(
                x: next(),
                y: -0.05 - next() * 0.15,
                vx: (next() - 0.5) * 0.18,
                vy: -0.15 + next() * 0.35,
                spin: (next() - 0.5) * 4,
                colour: Int(next() * Double(max(1, colours))) % max(1, colours),
                size: 0.014 + next() * 0.014,
                delay: next() * 0.6
            ))
        }
        return ChessMarbleConfetti(pieces: out)
    }

    /// Where `piece` is at `t` seconds into the burst, as fractions of the
    /// field, and how far it has turned; nil before it starts.
    static func place(_ piece: Piece, at t: Double) -> (x: Double, y: Double, turn: Double)? {
        let s = t - piece.delay
        guard s >= 0 else { return nil }
        // A sway across as it falls, so it flutters rather than drops.
        let sway = sin(s * 3 + piece.spin) * 0.015
        let x = piece.x + piece.vx * s + sway
        let y = piece.y + piece.vy * s + 0.5 * gravity * s * s
        return (x, y, piece.spin * s)
    }
}
