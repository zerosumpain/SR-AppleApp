import SwiftUI

/// The win's confetti, laid over a results page: one burst drawn in a Canvas
/// on the display's own clock, then gone — nothing keeps ticking after it.
/// Under Reduce Motion there is none. It never takes a touch, and VoiceOver
/// does not see it.
struct ChessMarbleConfettiView: View {
    /// A different seed gives a different burst; the same, the same.
    var seed: UInt64 = 7
    var count: Int = 90

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var finished = false
    @State private var field = ChessMarbleConfetti(pieces: [])

    private static let colours: [Color] = [
        Color(hex: 0xE6194B), Color(hex: 0x4363D8), Color(hex: 0xFFE119), Color(hex: 0x3CB44B),
        Color(hex: 0xF58231), Color(hex: 0x9B4DCA), Color(hex: 0x42D4F4), Color(hex: 0xF032E6),
    ]

    var body: some View {
        // A real container, never an empty Group: an empty one has nothing for
        // `.onAppear` to fire on, and the burst would never start.
        ZStack {
            Color.clear
            if !reduceMotion && !finished, let start {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        draw(in: &context, size: size, t: timeline.date.timeIntervalSince(start))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion, start == nil else { return }
            field = ChessMarbleConfetti.make(count: count, colours: Self.colours.count, seed: seed)
            start = Date()
        }
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(nanoseconds: UInt64(ChessMarbleConfetti.duration * 1_000_000_000))
            if !Task.isCancelled { finished = true }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let width = Double(size.width)
        let height = Double(size.height)
        for piece in field.pieces {
            guard let at = ChessMarbleConfetti.place(piece, at: t) else { continue }
            let y = at.y * height
            if y > height + 20 { continue }
            let w = CGFloat(piece.size * width)
            // A flat paper strip turning over: its height swings with the turn.
            let h = w * CGFloat(0.45 + 0.55 * abs(cos(at.turn)))
            let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            var copy = context
            copy.translateBy(x: CGFloat(at.x * width), y: CGFloat(y))
            copy.rotate(by: Angle(radians: at.turn))
            copy.fill(Path(roundedRect: rect, cornerRadius: w * 0.2), with: .color(Self.colours[piece.colour % Self.colours.count]))
        }
    }
}
