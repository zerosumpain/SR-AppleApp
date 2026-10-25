import SwiftUI

// v8.1: a day's route drawn small for the planning home's day rows — the
// stops as dots in their part of the day's colour, the stay as a square, the
// walk between them as a faint line, and the day's number in the corner.
// Drawn, not a map: no tiles to fetch, so it is there offline and costs
// nothing to scroll past. The geometry is TripDaySketchLogic's.

struct TripDaySketch: View {
    let points: [TripSketchPoint]
    let number: Int
    /// The tile's side; it grows with the reader's text size.
    @ScaledMetric(relativeTo: .headline) private var side: CGFloat = 56

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let place = { (p: TripSketchPoint) in CGPoint(x: p.x * size.width, y: p.y * size.height) }
                var route = Path()
                for (i, p) in points.enumerated() {
                    if i == 0 { route.move(to: place(p)) } else { route.addLine(to: place(p)) }
                }
                context.stroke(route, with: .color(TripPalette.day(number - 1).opacity(0.55)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                for p in points {
                    let c = place(p)
                    if p.isStay {
                        let r = CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)
                        context.fill(Path(r), with: .color(SR.ink.opacity(0.7)))
                    } else {
                        let colour = DayStage(rawValue: p.stage ?? "")?.color ?? SR.inkSecondary
                        let r = CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)
                        context.fill(Path(ellipseIn: r), with: .color(colour))
                    }
                }
            }
            Text("\(number)")
                .font(SR.Text.label(11).monospacedDigit())
                .foregroundStyle(Color.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(TripPalette.day(number - 1)))
                .padding(4)
        }
        .frame(width: side, height: side)
        .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).fill(SR.ink.opacity(0.05)))
        .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}
