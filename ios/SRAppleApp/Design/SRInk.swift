import SwiftUI
import UIKit
import CoreImage

/// The /health hero, on a phone.
///
/// SR-Health is a paper page with full-width INK BANDS across its hero sections
/// — readiness and today's figures at the top, an activity's headline figures at
/// the top of an activity. Those bands are what make the page read as a
/// designed object rather than a form, and they are what the app was missing.
///
/// The rule from the site still holds, and it is why these are bands and not
/// the app's ground: a tall solid ink area reads as intensity, not editorial.
/// One band at the top of a screen, the page under it paper. Every colour on a
/// band is cream at a rung of `SR.onInk(_:)` or one of the lifted partners
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

/// The mono kicker on a band. Accent-on-dark, 0.18em — the one orange thing
/// above the headline.
struct SRInkKicker: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(SR.Text.label())
            .tracking(SR.inkKickerTracking)
            .foregroundStyle(SR.accentOnDark)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A full-width ink band.
///
/// Full width means full width: in a `List` it goes in a row with zero insets
/// and an ink row background (`srInkRow()`), in a `ScrollView` it sits outside
/// the gutter. An inset ink panel FLOATS — the site learned that twice.
struct SRInkBand<Content: View>: View {
    var kicker: String? = nil
    var meta: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
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
        .padding(.horizontal, SR.gutter)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .background {
            ZStack {
                SR.ink
                SRGrain(opacity: 0.05)
            }
        }
    }
}

/// An Archivo Black headline on ink, uppercase and tight.
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
        .background(SR.ink)
        .overlay(Rectangle().strokeBorder(selected ? SR.accentOnDark : SR.onInk(.hairline), lineWidth: 1))
        .contentShape(Rectangle())
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

/// Stat cells split by 1px cream hairlines — /health's `.stat-grid`.
///
/// A `Grid`, not a `LazyVGrid`: the hairlines are the grid's own background
/// showing through a 1pt gap, so every cell in a row must be the row's full
/// height or the gap under a short cell paints as a bar. `Grid` sizes a row to
/// its tallest cell. A short last row is padded with empty ink cells for the
/// same reason — an unfilled track would show as a block of hairline colour.
struct SRInkCellGrid: View {
    let figures: [SRInkFigure]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = typeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: figures.count, by: columns).map { start in
            Array(figures[start..<min(start + columns, figures.count)])
        }
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row) { figure in SRInkCell(figure: figure) }
                    if row.count < columns {
                        ForEach(0..<(columns - row.count), id: \.self) { _ in
                            SR.ink.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
        .background(SR.onInk(.hairline))
        .overlay(Rectangle().strokeBorder(SR.onInk(.hairline), lineWidth: 1))
    }
}

struct SRInkCell: View {
    let figure: SRInkFigure

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(figure.value)
                    .font(SR.Text.figure(26))
                    .tracking(-0.52)
                    .foregroundStyle(figure.lit ? SR.accentOnDark : SR.onInk(.primary))
                    .lineLimit(1)
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
        .background(SR.ink)
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

    var body: some View {
        ZStack {
            Circle()
                .stroke(SR.onInk(.track), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(SR.accentOnDark, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Text(score)
                .font(SR.Text.hero(34))
                .foregroundStyle(SR.onInk(.primary))
                .lineLimit(1)
        }
        // The stroke straddles the path, so half of it would sit outside the
        // frame without this.
        .padding(5)
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
        .background(SR.onInk(.fill))
        .overlay(Rectangle().strokeBorder(SR.onInk(.hairline), lineWidth: 1))
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
            .listRowBackground(SR.ink)
            .listRowSeparator(.hidden)
    }
}
