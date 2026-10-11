import SwiftUI
import UIKit
import CoreImage

/// The /health hero, on a phone: the exercise book's INK COVER.
///
/// SR-Health is a paper page with full-width ink bands across its hero sections
/// — readiness and today's figures at the top, an activity's headline figures at
/// the top of an activity. In the notes look those bands are the book's cover,
/// as the website's landing hero is: near-black `#1a1008`, a faint cream feint
/// every 32pt, marked up in orange and petrol, and — edge to edge — a torn
/// bottom edge where the cover lies over the first page.
///
/// The rule from the site still holds, and it is why these are bands and not
/// the app's ground: a tall solid ink area reads as intensity, not editorial.
/// One cover at the top of a screen, the page under it paper. Every colour on
/// a cover is cream at a rung of `SR.onInk(_:)` or one of the lifted partners
/// (`accentOnDark`, `goodOnDark`) — never a paper token, which is the mistake
/// every relighting bug on the website came from.

// MARK: - Grain

/// The fractal-noise grain /health lays over everything, at 3%.
///
/// Generated ONCE, in code, and tiled. A 200px noise tile is the web's own
/// technique (an SVG `feTurbulence` data URL), and the phone equivalent is one
/// Core Image render cached for the life of the process — an image tile is a
/// single layer to the compositor, so it costs nothing on scroll. If Core Image
/// cannot produce it the grain is simply absent; it is texture, not content.
enum SRNoise {
    static let tile: UIImage? = {
        guard let random = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        let mono = random.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0,
            kCIInputContrastKey: 1.2,
        ])
        let context = CIContext()
        guard let image = context.createCGImage(mono, from: CGRect(x: 0, y: 0, width: 200, height: 200)) else { return nil }
        // Redrawn into a plain bitmap once, so the tile owns its pixels outright
        // rather than holding whatever Core Image backed it with.
        let format = UIGraphicsImageRendererFormat()
        // Scale 2: a 100pt tile of 200px noise, so the grain is one physical
        // pixel pair rather than a visible checker.
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { _ in
            UIImage(cgImage: image).draw(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        }
    }()
}

struct SRGrain: View {
    var opacity: Double = 0.03

    var body: some View {
        if let tile = SRNoise.tile {
            Image(uiImage: tile)
                .resizable(resizingMode: .tile)
                .opacity(opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - The band

/// The kicker on the cover: the paper kicker's recipe (mono 12 caps, 0.14em)
/// in orange-on-dark — the one orange thing above the headline.
struct SRInkKicker: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(SR.Text.kicker())
            .tracking(SR.Notes.kickerTracking)
            .foregroundStyle(SR.accentOnDark)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The ink cover.
///
/// Solid `SR.band`, its own cream feint every 32pt (13pt into each pitch, as
/// the site's hero is ruled), a 3pt corner and a cream hairline at 8% so its
/// edge still shows on night paper. Edge to edge (`inset: 0`, a grouped list's
/// already-inset row) it is square and, by default, TORN along its foot: the
/// teeth and the shade of the cover lifting off the page under it. Inset from
/// a screen edge it is a card of cover board, untorn.
///
/// In a `List` it goes in a row with zero insets (`srInkRow()`); in a
/// `ScrollView` it sits outside the gutter. Children see a dark colour scheme
/// and ask `SRRegister.ink` for their colours.
struct SRInkBand<Content: View>: View {
    var kicker: String? = nil
    var meta: String? = nil
    /// How far the cover sits in from its container's edge. A screen edge
    /// wants the gutter; a grouped list's row has already been inset.
    var inset: CGFloat = SR.Glass.bandInset
    /// The torn foot. `nil` tears a full-width cover (`inset == 0`) and leaves
    /// an inset one whole.
    var torn: Bool? = nil
    @ViewBuilder var content: Content

    private var tears: Bool { torn ?? (inset == 0) }

    var body: some View {
        VStack(spacing: 0) {
            cover
            if tears {
                // Under the cover, in the layout: a list row's neighbour
                // would paint over anything hung outside it.
                SRTornEdge().padding(.horizontal, inset)
            }
        }
    }

    private var cover: some View {
        VStack(alignment: .leading, spacing: 16) {
            if kicker != nil || meta != nil {
                // Stacked, not side by side: a long kicker wraps, and a meta line
                // pushed to the right of a two-line kicker floats in mid-air.
                VStack(alignment: .leading, spacing: 5) {
                    if let kicker { SRInkKicker(text: kicker) }
                    if let meta {
                        Text(meta.uppercased())
                            .font(SR.Text.mono())
                            .tracking(1)
                            .foregroundStyle(SR.onInk(.unit))
                            .lineLimit(1)
                    }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .background {
            SRGrain(opacity: 0.04)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
        .srGlassCard(.ink, radius: corner)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, inset)
        .padding(.top, 6)
        .padding(.bottom, tears ? 0 : 6)
    }

    /// Square when torn — paper tears, it does not round — and a cut card's
    /// corner otherwise.
    private var corner: CGFloat { tears || inset == 0 ? 0 : SR.Glass.radius }
}

/// An Inter Display headline on ink, uppercase and tight.
struct SRInkTitle: View {
    let text: String
    var size: CGFloat = 34

    var body: some View {
        Text(text.uppercased())
            .font(SR.Text.hero(size))
            .tracking(-size * 0.02)
            .foregroundStyle(SR.onInk(.primary))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Tiles

/// One figure on the band. /health's `.hero-tile`.
///
/// The fill is the band's own ink and only the hairline marks the tile — a
/// lighter fill would be a card floating on the band, which is the inset-panel
/// mistake again at a smaller size.
struct SRInkTile: View {
    let label: String
    let value: String
    var unit: String? = nil
    var spark: [Double]? = nil
    var foot: String? = nil
    /// Colour the foot as the good direction for THIS metric. The server says
    /// which way is good; a resting heart rate going down is recovery.
    var footGood: Bool? = nil
    var footIcon: String? = nil
    var selected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(SR.Text.label())
                .tracking(SR.inkLabelTracking)
                .foregroundStyle(SR.onInk(.label))
                .lineLimit(1)

            // A step down rather than a truncation: "7h 24m" at 32 does not fit
            // a half-width tile and came out as "7h 2…". Both steps scale with
            // the reader's text setting, so this is not `minimumScaleFactor`
            // quietly undoing it.
            ViewThatFits(in: .horizontal) {
                figureLine(32)
                figureLine(26)
                figureLine(21)
            }

            if let spark, spark.count > 1 {
                SRSparkline(values: spark, register: .ink)
                    .frame(height: 26)
            }

            if let foot {
                HStack(spacing: 4) {
                    if let footIcon {
                        Image(systemName: footIcon).font(.system(size: 9, weight: .bold))
                    }
                    Text(foot.uppercased())
                        .font(SR.Text.mono())
                        .tracking(1)
                }
                .foregroundStyle(footTone)
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SR.inkTilePadding)
        .frame(minHeight: 112, alignment: .topLeading)
        .background(SR.onInk(.fill), in: RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .strokeBorder(selected ? SR.accentOnDark : SR.onInk(.hairline), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
    }

    private func figureLine(_ size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(SR.Text.figure(size))
                .tracking(-size * 0.02)
                .foregroundStyle(SR.onInk(.primary))
                .lineLimit(1)
                .fixedSize()
            if let unit {
                Text(unit)
                    .font(SR.Text.mono(13))
                    .foregroundStyle(SR.onInk(.unit))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private var footTone: Color {
        switch footGood {
        case .some(true): return SR.goodOnDark
        case .some(false): return SR.accentOnDark
        case .none: return SR.onInk(.unit)
        }
    }
}

/// One stat in an activity or segment hero.
struct SRInkFigure: Identifiable, Hashable {
    let label: String
    let value: String
    var unit: String? = nil
    /// The headline figure of the hero, lit in accent-on-dark. One per grid.
    var lit: Bool = false

    var id: String { label }
}

/// Stat cells as a ruled ledger on the cover — /health's `.stat-grid`, in
/// the notes look: cream hairlines between the cells and along the top and
/// foot, no box round it, and the `lit` figure RINGED in orange-on-dark
/// rather than only coloured.
///
/// A `Grid`, not a `LazyVGrid`: each cell draws its own leading and top rule,
/// so every cell in a row must be the row's full height or a short cell's rule
/// stops partway down. `Grid` sizes a row to its tallest cell. A short last
/// row is padded with empty cells for the same reason.
struct SRInkCellGrid: View {
    let figures: [SRInkFigure]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = typeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: figures.count, by: columns).map { start in
            Array(figures[start..<min(start + columns, figures.count)])
        }
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.element.id) { column, figure in
                        SRInkCell(figure: figure)
                            .overlay(alignment: .leading) {
                                if column > 0 { SR.onInk(.hairline).frame(width: 1) }
                            }
                            .overlay(alignment: .top) {
                                if rowIndex > 0 { SR.onInk(.hairline).frame(height: 1) }
                            }
                    }
                    if row.count < columns {
                        ForEach(0..<(columns - row.count), id: \.self) { _ in
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .overlay(alignment: .leading) { SR.onInk(.hairline).frame(width: 1) }
                                .overlay(alignment: .top) {
                                    if rowIndex > 0 { SR.onInk(.hairline).frame(height: 1) }
                                }
                        }
                    }
                }
            }
        }
        .overlay(alignment: .top) { SR.onInk(.hairline).frame(height: 1) }
        .overlay(alignment: .bottom) { SR.onInk(.hairline).frame(height: 1) }
    }
}

struct SRInkCell: View {
    let figure: SRInkFigure

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(figure.value)
                    .font(SR.Text.figure(26))
                    .tracking(-26 * 0.03)
                    .monospacedDigit()
                    .foregroundStyle(figure.lit ? SR.accentOnDark : SR.onInk(.primary))
                    .lineLimit(1)
                    .srInkRing(tone: SR.accentOnDark, seed: 31, pad: 6, visible: figure.lit)
                if let unit = figure.unit {
                    Text(unit)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.onInk(.unit))
                        .lineLimit(1)
                }
            }
            Text(figure.label.uppercased())
                .font(SR.Text.label())
                .tracking(SR.inkLabelTracking)
                .foregroundStyle(SR.onInk(.label))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(figure.label): \(figure.value) \(figure.unit ?? "")")
    }
}

// MARK: - Readiness

/// The readiness donut. Cream track, accent-on-dark arc, the score in the hole.
struct SRInkDonut: View {
    /// 0...1.
    let fraction: Double
    let score: String
    /// The ring and the numeral, scaled together. Today's strip draws the
    /// donut at half the size /health does, and a 34pt numeral in a 56pt ring
    /// is a numeral with a ring round it.
    var lineWidth: CGFloat = 10
    var scoreSize: CGFloat = 34
    /// The notes look's overstroke: a hand-drawn loop in orange-on-dark round
    /// the donut, as the site loops its pulse figure. The geometry underneath
    /// is unchanged; a screen opts in.
    var inkRing: Bool = false
    var ringSeed: Int = 31

    var body: some View {
        ZStack {
            if inkRing {
                SRInkStroke(shape: SRInkLoop(seed: ringSeed, turns: 1.1, wobble: 0.035),
                            tone: SR.accentOnDark, lineWidth: 2)
                    .padding(-lineWidth * 0.9)
            }
            Circle()
                .stroke(SR.onInk(.track), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(
                    AngularGradient(colors: [SR.accent, SR.accentOnDark, Color(hex: 0xF2B27A)], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(score)
                .font(SR.Text.hero(scoreSize))
                .foregroundStyle(SR.onInk(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        // The stroke straddles the path, so half of it would sit outside the
        // frame without this.
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness \(score)")
    }
}

/// /health's readiness card, on the band: donut, verdict, what to do about it.
struct SRInkReadiness: View {
    let readiness: HealthReadiness
    var donut: CGFloat = 108

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            SRInkDonut(
                fraction: readiness.score / 100,
                score: "\(Int(readiness.score.rounded()))"
            )
            .frame(width: donut, height: donut)

            VStack(alignment: .leading, spacing: 6) {
                Text("READINESS")
                    .font(SR.Text.label())
                    .tracking(SR.inkLabelTracking)
                    .foregroundStyle(SR.onInk(.label))
                Text(readiness.label.uppercased())
                    .font(SR.Text.display(21))
                    .foregroundStyle(SR.onInk(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                Text(readiness.recommendation)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.onInk(.note))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(SR.onInk(.fill), in: RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .strokeBorder(SR.onInk(.hairline), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Placement

extension View {
    /// A `List` row that is an ink band edge to edge: no insets, no separator,
    /// ink behind it so the row's own ground never shows as a cream sliver.
    func srInkRow() -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
