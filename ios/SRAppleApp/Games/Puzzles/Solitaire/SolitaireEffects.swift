import SwiftUI

/// Sparks over a foundation as a card lands on it, bigger for a king.
///
/// Each spark's path is worked out from the burst's age alone (no state that
/// steps from frame to frame), and the timeline only runs while there is a
/// burst to draw: the board takes this view away when the last one fades.
struct SolitaireSparks: View {
    static let life: Double = 0.75

    let bursts: [SolitaireBurst]
    let layout: SolitaireLayout

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: bursts.isEmpty)) { timeline in
            Canvas { context, _ in
                let now = timeline.date
                let colours = [SolitaireInk.hint, Color.white, SR.Hue.games.glow, Color(hex: 0xFF8A5B)]
                for burst in bursts {
                    draw(burst, at: now, colours: colours, in: &context)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ burst: SolitaireBurst, at now: Date, colours: [Color], in context: inout GraphicsContext) {
        let t = now.timeIntervalSince(burst.born)
        guard t >= 0, t < Self.life else { return }
        let origin = layout.foundationCenter(burst.foundation)
        let progress = t / Self.life
        let count = burst.big ? 24 : 12
        let reach: Double = burst.big ? 240 : 150
        for i in 0..<count {
            var random = SolitaireRandom(seed: UInt64(burst.id) &* 131 &+ UInt64(i))
            let angle = Double(i) / Double(count) * 2 * Double.pi + random.unit() * 0.5
            let speed = reach * (0.55 + random.unit() * 0.6)
            let x = Double(origin.x) + cos(angle) * speed * t
            let y = Double(origin.y) + sin(angle) * speed * t + 0.5 * 520 * t * t
            let r = (burst.big ? 3.4 : 2.6) * (1 - progress * 0.6)
            let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
            let colour = colours[i % colours.count].opacity(1 - progress)
            context.fill(Path(ellipseIn: rect), with: .color(colour))
        }
    }
}

/// Steps the cascade from one display frame to the next. A class held in
/// `@State`, because a frame's drawing moves it on and SwiftUI state may not
/// be changed while a view is drawing.
final class SolitaireCascadeDriver {
    private(set) var cascade: SolitaireCascade?
    private var last: Date?

    func advance(to date: Date, layout: SolitaireLayout) -> SolitaireCascade {
        if cascade == nil {
            let starts = (0..<4).map { f -> SolitaireCascadePoint in
                let c = layout.foundationCenter(f)
                return SolitaireCascadePoint(x: Double(c.x), y: Double(c.y))
            }
            cascade = SolitaireCascade(width: Double(layout.size.width), floor: Double(layout.size.height),
                                       cardWidth: Double(layout.cardWidth), cardHeight: Double(layout.cardHeight),
                                       starts: starts, seed: SolitaireRandom.freshSeed())
        }
        let dt = last.map { date.timeIntervalSince($0) } ?? 0
        last = date
        var next = cascade ?? SolitaireCascade(width: 0, floor: 0, cardWidth: 0, cardHeight: 0, starts: [])
        next.advance(by: dt)
        cascade = next
        return next
    }

    var finished: Bool { cascade?.finished ?? false }
}

/// The win: every card leaps off the foundations, kings first, bouncing
/// across the table and leaving a trail of itself, as the old desktop game
/// did. The cards are drawn once as Canvas symbols and stamped each frame;
/// the timeline stops when the last card has gone.
struct SolitaireCascadeView: View {
    let layout: SolitaireLayout
    let fourColour: Bool
    @State private var driver = SolitaireCascadeDriver()
    @State private var done = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: done)) { timeline in
            Canvas { context, _ in
                let cascade = driver.advance(to: timeline.date, layout: layout)
                stamp(cascade, in: &context)
            } symbols: {
                ForEach(0..<52, id: \.self) { id in
                    SolitaireCardFace(card: SolitaireCard(id: id), width: layout.cardWidth, fourColour: fourColour)
                        .tag(id)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            // Checked twice a second, only while the cascade is on screen.
            while !done && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if driver.finished { done = true }
            }
        }
    }

    private func stamp(_ cascade: SolitaireCascade, in context: inout GraphicsContext) {
        for f in 0..<4 {
            guard let id = cascade.waiting(f), let symbol = context.resolveSymbol(id: id) else { continue }
            context.draw(symbol, at: layout.foundationCenter(f))
        }
        for flyer in cascade.flyers {
            guard let symbol = context.resolveSymbol(id: flyer.card) else { continue }
            let count = flyer.trail.count
            for (k, point) in flyer.trail.enumerated() {
                var faded = context
                faded.opacity = 0.2 + 0.6 * Double(k + 1) / Double(count + 1)
                faded.draw(symbol, at: CGPoint(x: point.x, y: point.y))
            }
            context.draw(symbol, at: CGPoint(x: flyer.x, y: flyer.y))
        }
    }
}
