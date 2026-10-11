import SwiftUI
import WidgetKit
import ActivityKit

// The family journey, drawn. Nothing here fetches: every word and figure
// arrives in the push (`JourneyAttributes.ContentState`), and the site decides
// what they say. See SR-Main `$lib/home/presence/live-journey`.
//
// The same extension carries the family's Home Screen widgets — the step
// board and the task list (`FamilyWidgets.swift`) — so they ride on the
// profile CI already mints for it rather than needing a target of their own.

@main
struct SRLiveBundle: WidgetBundle {
    var body: some Widget {
        JourneyLiveActivity()
        FamilyStepsWidget()
        FamilyTasksWidget()
    }
}

// The notebook's palette (`Theme.swift`), repeated: an extension cannot see
// the app. The Lock Screen card is a slip of the site's notes paper in both
// appearances — cream, ruled in petrol, with the double margin rule — the way
// a page torn from the exercise book would look on any wallpaper; the Dynamic
// Island stays the system's black, so it keeps the ink cover's pens.
private enum Ink {
    static let paper = rgb(0xEDE4D4)
    static let ink = rgb(0x1A1008)
    static let muted = rgb(0x1A1008, 0.65)
    /// The orange pen: underlines, ticks, the journey line.
    static let accent = rgb(0xC4570A)
    /// The orange that writes small words (kickers, units): a shade darker
    /// than the pen so twelve-point caps still read on cream.
    static let pen = rgb(0xA84808)
    static let accentOnDark = rgb(0xE8863A)
    static let cream = rgb(0xEDE4D4)
    static let creamMuted = rgb(0xEDE4D4, 0.7)
    static let good = rgb(0x55663A)
    static let goodOnDark = rgb(0x8A9A5B)
    static let line = rgb(0x1A1008, 0.16)
    /// The feint the writing sits on, and the two lines of the margin rule.
    static let feint = rgb(0x0E5B66, 0.16)
    static let marginA = rgb(0xC4570A, 0.55)
    static let marginB = rgb(0xC4570A, 0.35)

    private static func rgb(_ hex: UInt32, _ alpha: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: alpha)
    }
}

/// The paper's geometry, the site's own: a rule every 32pt, 23pt down each
/// pitch, writing a point above it, and the margin rule's two lines at 11 and
/// 14pt from the leading edge.
private enum Ruling {
    static let pitch: CGFloat = 32
    static let ruleY: CGFloat = 23
    static let baseline: CGFloat = 22
    static let marginA: CGFloat = 11
    static let marginB: CGFloat = 14
    /// Where the writing starts: clear of the margin rule, as the site's body
    /// text keeps its distance from the red lines.
    static let textInset: CGFloat = 26
    /// The site's kicker tracking, 0.14em of 12pt.
    static let kickerTracking: CGFloat = 1.68
    /// DM Sans's line box, ascent plus descent, as a share of its size: what
    /// is left of a pitch after one line is the gap that puts the next line
    /// on the next rule.
    static let captionLine: CGFloat = 1.302
}

private extension Font {
    /// Inter Display: the headline face. Falls back to a heavy system font if
    /// the file did not register, which reads close enough.
    static func display(_ size: CGFloat) -> Font { .custom("InterDisplay-ExtraBold", size: size, relativeTo: .headline) }
    /// JetBrains Mono: labels and figures in the Dynamic Island.
    static func mono(_ size: CGFloat) -> Font { .custom("JetBrainsMono-Medium", size: size, relativeTo: .caption) }
    /// The site's kicker face: JetBrains Mono at its regular weight.
    static func kicker(_ size: CGFloat = 12) -> Font { .custom("JetBrainsMono-Regular", size: size, relativeTo: .caption) }
    /// DM Sans, the site's caption face, for the sentence under the headline.
    static func sans(_ size: CGFloat) -> Font { .custom("DMSans-Medium", size: size, relativeTo: .footnote) }
}

private extension View {
    /// Sets a line of writing on the paper the way the site does: its first
    /// baseline a point above the rule, in a row one pitch tall. A second line
    /// of the same text reaches the next rule by its own `lineSpacing`; it
    /// only ever comes last, so its overhang lands in the card's foot.
    func onRule() -> some View {
        alignmentGuide(.top) { $0[.firstTextBaseline] - Ruling.baseline }
            .frame(maxWidth: .infinity, minHeight: Ruling.pitch, alignment: .topLeading)
    }
}

struct JourneyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneyAttributes.self) { context in
            LockScreenJourney(attributes: context.attributes, state: context.state, stale: context.isStale)
                .activityBackgroundTint(Ink.paper)
                .activitySystemActionForegroundColor(Ink.ink)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: state.symbol)
                        .font(.title2)
                        .foregroundStyle(state.arrived ? Ink.goodOnDark : Ink.accentOnDark)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let eta = state.etaMinutes {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("~\(eta)").font(.display(22)).foregroundStyle(Ink.cream)
                            Text("MIN").font(.mono(10)).foregroundStyle(Ink.creamMuted)
                        }
                        .padding(.trailing, 4)
                    } else if let distance = state.shortDistance {
                        Text(distance).font(.mono(15)).foregroundStyle(Ink.cream).padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.headline)
                        .font(.display(15))
                        .foregroundStyle(Ink.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.detail)
                            .font(.mono(12))
                            .foregroundStyle(Ink.creamMuted)
                            .lineLimit(2)
                        if let progress = state.progress {
                            JourneyBar(progress: progress, fill: state.arrived ? Ink.goodOnDark : Ink.accentOnDark, track: Ink.cream.opacity(0.18))
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: state.symbol)
                    .foregroundStyle(state.arrived ? Ink.goodOnDark : Ink.accentOnDark)
            } compactTrailing: {
                Text(state.arrived ? "Home" : (state.etaMinutes.map { "~\($0)m" } ?? state.shortDistance ?? context.attributes.name))
                    .font(.mono(12))
                    .foregroundStyle(Ink.cream)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: state.symbol)
                    .foregroundStyle(state.arrived ? Ink.goodOnDark : Ink.accentOnDark)
            }
            .keylineTint(Ink.accentOnDark)
        }
    }
}

/// The Lock Screen card: who and where from, how it is going, and a line
/// home — written on a slip of the notebook's ruled paper, one thing to a
/// rule. The one mark is the pen's: the minutes still to go double-underlined
/// as the site underlines a total, or, once they are home, a tick.
struct LockScreenJourney: View {
    let attributes: JourneyAttributes
    let state: JourneyAttributes.ContentState
    let stale: Bool

    /// The caption's size as the reader's text setting scales it, so the gap
    /// that puts its second line on the next rule scales with it.
    @ScaledMetric(relativeTo: .footnote) private var captionSize: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.arrived ? "ARRIVED" : (state.moving ? "ON THE WAY" : "JOURNEY"))
                    .font(.kicker())
                    .tracking(Ruling.kickerTracking)
                    .foregroundStyle(state.arrived ? Ink.good : Ink.pen)
                Spacer()
                Text(state.updated, style: .time)
                    .font(.kicker())
                    .tracking(0.72)
                    .foregroundStyle(Ink.muted)
            }
            .onRule()

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: state.symbol)
                    .font(.title3)
                    .foregroundStyle(state.arrived ? Ink.good : Ink.accent)
                    .frame(width: 28)
                Text(state.headline)
                    .font(.display(20))
                    .tracking(-0.4)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                if let eta = state.etaMinutes, state.moving {
                    etaFigure(eta)
                } else if state.arrived {
                    JourneyTick()
                        .stroke(Ink.good, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
            }
            .onRule()

            if let progress = state.progress {
                // The line home is inked along a rule of the paper, not
                // floated between two.
                JourneyBar(progress: progress, fill: state.arrived ? Ink.good : Ink.accent, track: Ink.line)
                    .padding(.top, Ruling.ruleY - JourneyBar.height / 2)
                    .frame(height: Ruling.pitch, alignment: .top)
            }

            Text(stale ? "\(state.detail) · not updated lately" : state.detail)
                .font(.sans(14))
                .lineSpacing(max(0, Ruling.pitch - captionSize * Ruling.captionLine))
                .foregroundStyle(Ink.muted)
                .lineLimit(2)
                .onRule()
        }
        .padding(.leading, Ruling.textInset)
        .padding(.trailing, 16)
        .padding(.bottom, 10)
        .opacity(stale ? 0.7 : 1)
        // The card is at most 160pt tall and its lines keep to a 32pt rule,
        // so the largest text sizes would push the foot off the card.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .background { JourneyPaper() }
    }

    /// "~12 MIN": the figure in the headline face, double-underlined in the
    /// orange pen, its unit in the kicker's mono caps beside its feet.
    private func etaFigure(_ minutes: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("~\(minutes)")
                .font(.display(26))
                .tracking(-0.78)
                .monospacedDigit()
                .foregroundStyle(Ink.ink)
                .overlay(alignment: .bottom) {
                    JourneyUnderline()
                        .stroke(Ink.accent, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                        .frame(height: 8)
                        .offset(y: 3)
                        .accessibilityHidden(true)
                }
            Text("MIN")
                .font(.kicker())
                .tracking(Ruling.kickerTracking)
                .foregroundStyle(Ink.pen)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The slip of paper under the Lock Screen card: cream, the petrol feint every
/// pitch and the double margin rule down the leading edge. Shapes rather than
/// a `Canvas`, which every widget renderer is certain to draw.
struct JourneyPaper: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Ink.paper
            JourneyFeint().fill(Ink.feint)
            Rectangle().fill(Ink.marginA).frame(width: 1).padding(.leading, Ruling.marginA)
            Rectangle().fill(Ink.marginB).frame(width: 1).padding(.leading, Ruling.marginB)
        }
        .accessibilityHidden(true)
    }
}

/// One 1pt rule every pitch, 23pt down it, the full width of the slip.
struct JourneyFeint: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var y = rect.minY + Ruling.ruleY
        while y < rect.maxY {
            path.addRect(CGRect(x: rect.minX, y: y, width: rect.width, height: 1))
            y += Ruling.pitch
        }
        return path
    }
}

/// The pen's double underline (`InkGeometry.underline(seed: 5)` in the app,
/// the site's `inkLine` pair). The extension cannot see the pen, so its two
/// strokes are written down here as the pen draws them, in the same 100 × 12
/// viewBox, and stretched to the figure; the stroke is applied afterwards, so
/// its width stays in points.
struct JourneyUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 1.22, y: 2.78))
        path.addCurve(to: CGPoint(x: 49.99, y: 4.25), control1: CGPoint(x: 9.35, y: 3.02), control2: CGPoint(x: 33.68, y: 4.00))
        path.addCurve(to: CGPoint(x: 99.10, y: 4.27), control1: CGPoint(x: 66.31, y: 4.50), control2: CGPoint(x: 90.91, y: 4.26))
        path.move(to: CGPoint(x: 5.60, y: 9.13))
        path.addCurve(to: CGPoint(x: 50.50, y: 9.55), control1: CGPoint(x: 13.08, y: 9.20), control2: CGPoint(x: 35.64, y: 9.40))
        path.addCurve(to: CGPoint(x: 94.76, y: 10.03), control1: CGPoint(x: 65.36, y: 9.71), control2: CGPoint(x: 87.38, y: 9.95))
        return path.applying(journeyViewBox(CGSize(width: 100, height: 12), in: rect))
    }
}

/// The pen's tick (`SRInkTick`, seed 9: short down-stroke, long up-stroke) in
/// its 22 × 22 viewBox, written down for the same reason as the underline.
struct JourneyTick: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 2.76, y: 10.78))
        path.addCurve(to: CGPoint(x: 9.12, y: 17.30), control1: CGPoint(x: 3.82, y: 11.87), control2: CGPoint(x: 6.18, y: 19.12))
        path.addCurve(to: CGPoint(x: 20.42, y: -0.16), control1: CGPoint(x: 12.06, y: 15.48), control2: CGPoint(x: 18.54, y: 2.75))
        return path.applying(journeyViewBox(CGSize(width: 22, height: 22), in: rect))
    }
}

/// Maps a viewBox onto a frame, as an SVG without `preserveAspectRatio` does.
private func journeyViewBox(_ box: CGSize, in rect: CGRect) -> CGAffineTransform {
    CGAffineTransform(translationX: rect.minX, y: rect.minY)
        .scaledBy(x: rect.width / box.width, y: rect.height / box.height)
}

/// From where they left to home, as far as they have got: a pencil line the
/// whole way, the pen's line over the part travelled, and the nib where they
/// are now. The same drawing in the Dynamic Island, in the cover's pens.
struct JourneyBar: View {
    let progress: Double
    let fill: Color
    let track: Color

    static let height: CGFloat = 8

    private var done: Double { min(max(progress, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            let reach = max(Self.height, geo.size.width * done)
            ZStack(alignment: .leading) {
                Rectangle().fill(track).frame(height: 1)
                Capsule().fill(fill).frame(width: reach, height: 3)
                Circle().fill(fill).frame(width: Self.height, height: Self.height).offset(x: reach - Self.height)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel("Progress home")
        .accessibilityValue("\(Int(done * 100)) percent")
    }
}
