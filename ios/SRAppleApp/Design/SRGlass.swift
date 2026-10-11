import SwiftUI
import UIKit

/// Paper, with glass only where the phone puts it.
///
/// The notes look (2026-10-11): every screen is a page of the site's exercise
/// book. This file holds the pieces nearly every screen reaches for, so that
/// re-skinning them here re-skinned the app without touching its call sites:
///
/// - **The ground is ruled paper.** `srGround` / `srPaper` lay cream paper with
///   a faint petrol feint every 32pt and a double red-orange margin rule down
///   the leading edge (`SRNotebookPaper`). On iOS 18 and later the feint scrolls
///   with the page, as lines on a page do; on 17 it stays put.
/// - **Cards are index-card stock.** `srGlass(.paper)` / `srGlassCard(.paper)`
///   are opaque card (`SR.Notes.card`), a 1pt `SR.line` border and a cut
///   card's 3pt corner. No material, no shadow, no tilt.
/// - **The hero is the ink cover.** `.ink` surfaces are the book's near-black
///   cover with its own faint cream feint. The register rule still holds:
///   anything on it asks `SRRegister.ink` for its colour.
/// - **Buttons are pen and card.** The one action a screen is for is a solid
///   orange block with a cream mono label; everything else is card stock in a
///   hand-drawn ink box.
/// - **The furniture stays glass.** Tab bar, navigation bar, sheets, keyboard
///   and anything floating over a map (`.clear`) are the system's own Liquid
///   Glass, tinted. Glass over a page is how the phone works; the page is ours.
///
/// History: from October 2026 to this change the app was "paper under glass"
/// — Liquid Glass cards and buttons over a cream ground with soft coloured
/// fields per tab (the `SRMood`s), radius 26 everywhere. The website then
/// moved its landing and blog to notes, and the app followed so the two read
/// as one book. The glass names (`srGlass`, `SRGlassChip`, `SR.Glass`) stayed
/// because over a thousand call sites use them; the names are history, the
/// look is paper.
extension SR {
    enum Glass {
        /// The corner every card uses: a cut card's, 3pt. (Was 26, concentric
        /// with the phone's corners, when cards were glass.)
        static let radius: CGFloat = 3
        /// Rows, chips and inner panels inside a card. DESIGN D4 asks for 2;
        /// it is 4 because call sites derive radii from it
        /// (`innerRadius - 4` in the Daydream filter, `innerRadius + 4`
        /// widely), and a negative corner radius is undefined. Cards drawn
        /// through `srGlassCard` are clamped to `radius` anyway.
        static let innerRadius: CGFloat = 4
        /// How far a hero slab sits in from the screen edge.
        static let bandInset: CGFloat = SR.gutter
        /// The tint the system's glass FURNITURE takes over paper — the
        /// floating `.clear` surfaces still use system glass.
        static let paperTint = Color(light: 0xF6EFE3, dark: 0x2A2118, alpha: 0.55)
        /// The cover's ground as a tint, for glass that must read as ink.
        static let inkTint = Color(hex: 0x1A1008, alpha: 0.82)
        /// A grouped list row: card stock, opaque. (Was frosted cream at 62%.)
        /// Kept for the call sites that fill a capsule or a chip with it.
        static let rowFill = SR.Notes.card
        /// The accent, as glass wants it: saturated enough to read through.
        static let accentTint = Color(light: 0xC4570A, dark: 0xE07B2A, alpha: 0.85)
        /// The pre-26 glass fallback's highlight edge. A white rim on a dark
        /// page is a glare line, so it dims with the ground.
        static let rim = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.12) : UIColor(white: 1, alpha: 0.45) })
    }
}

// MARK: - The ground

/// Which tab a screen belongs to.
///
/// Under glass each mood was a soft field of colour behind the content. The
/// ruled page is the same page everywhere — an exercise book does not change
/// colour between chapters — so the ground ignores it now, and the area's
/// identity comes from its kickers and its marks. The cases stay so the 64
/// `srGround(_:)` call sites still say where they are.
enum SRMood {
    /// Today.
    case warm
    /// Chat, settings.
    case quiet
    /// Health.
    case vital
    /// News, Flows, Daydream.
    case wire
}

/// The ruled feint as tiles, drawn once each by UIKit and tiled by the
/// compositor — the `SRNoise` technique. A page of rules is one image layer,
/// so it costs nothing on scroll, where a full-screen `Canvas` would redraw
/// every frame the page moved.
enum SRPaperTile {
    /// The page's feint in a light appearance: an 8 × 32pt tile, clear but for
    /// one 1pt rule at `SR.Notes.ruleY`.
    static let light = feint(SR.UI.rule.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)), at: SR.Notes.ruleY)
    /// The same in dark (the night theme's petrol at 13%).
    static let dark = feint(SR.UI.rule.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)), at: SR.Notes.ruleY)
    /// The cover's feint: cream at 5% (`SR.onInk(.fill)`), the rule 13pt into
    /// each pitch, as the site's hero rules its ink.
    static let cover = feint(UIColor(hex: 0xEDE4D4, alpha: 0.05), at: 13)

    static func feint(for scheme: ColorScheme) -> UIImage { scheme == .dark ? dark : light }

    private static func feint(_ colour: UIColor, at y: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let size = CGSize(width: 8, height: SR.Notes.pitch)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            colour.setFill()
            context.fill(CGRect(x: 0, y: y, width: size.width, height: 1))
        }
    }
}

/// The double margin rule: two 1pt verticals, the stronger at x = 11 and the
/// fainter at x = 14 from the leading edge, in the 20pt gutter so no row or
/// heading crosses them.
struct SRMarginRule: View {
    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: SR.Notes.marginX.a)
            SR.Notes.marginA.frame(width: 1)
            Color.clear.frame(width: SR.Notes.marginX.b - SR.Notes.marginX.a - 1)
            SR.Notes.marginB.frame(width: 1)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The page: cream, the petrol feint every 32pt, the double margin rule, and a
/// trace of grain.
struct SRNotebookPaper: View {
    /// How far the page has scrolled, modulo the pitch. `srGround` feeds it on
    /// iOS 18 and later so the rules travel with the writing; 0 holds them.
    var phase: CGFloat = 0

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            SR.paper
            GeometryReader { geometry in
                Image(uiImage: SRPaperTile.feint(for: scheme))
                    .resizable(resizingMode: .tile)
                    // One pitch taller than the page, so lifting it by up to a
                    // pitch never shows a bare strip at the foot.
                    .frame(width: geometry.size.width, height: geometry.size.height + SR.Notes.pitch)
                    .offset(y: -phase)
            }
            .clipped()
            SRMarginRule()
            SRGrain(opacity: scheme == .dark ? 0.015 : 0.03)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The scroll maths behind the travelling rules. A plain enum rather than a
/// member of the view, so the scroll-geometry callback (which SwiftUI may run
/// off the main actor) can call it without crossing into a view's isolation.
enum SRRuledScroll {
    /// The rules' travel for a scroll position: how far into the current pitch
    /// the content has moved. `nil` for a scroll view that does not scroll
    /// vertically — a carousel inside the page must not drag the rules about.
    @available(iOS 18.0, *)
    static func phase(of geometry: ScrollGeometry) -> CGFloat? {
        guard geometry.contentSize.height > geometry.containerSize.height else { return nil }
        return phase(travelled: geometry.contentOffset.y + geometry.contentInsets.top)
    }

    /// `travelled` modulo the pitch, in [0, pitch) — overscroll at the top
    /// (negative travel) included.
    static func phase(travelled: CGFloat) -> CGFloat {
        let into = travelled.truncatingRemainder(dividingBy: SR.Notes.pitch)
        return into < 0 ? into + SR.Notes.pitch : into
    }
}

/// The old name for the ground. Kept so nothing outside this file changes; the
/// mood is accepted and ignored.
struct SRAtmosphere: View {
    var mood: SRMood = .warm

    var body: some View {
        SRNotebookPaper()
    }
}

/// Hangs the ruled page behind a scroll view and, from iOS 18, moves its rules
/// with the scroll.
private struct SRGround: ViewModifier {
    @State private var phase: CGFloat = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        let page = content
            .scrollContentBackground(.hidden)
            .background { SRNotebookPaper(phase: phase) }
        if #available(iOS 18.0, *) {
            page.onScrollGeometryChange(for: Optional<CGFloat>.self) { geometry in
                SRRuledScroll.phase(of: geometry)
            } action: { _, next in
                if let next { phase = next }
            }
        } else {
            page
        }
    }
}

extension View {
    /// The screen's ground: ruled paper under a scroll view or a list, edge to
    /// edge. The mood names the area and no longer changes the paper.
    func srGround(_ mood: SRMood = .warm) -> some View {
        modifier(SRGround())
    }
}

// MARK: - Surfaces

/// What a surface is made of. The names are the glass era's; the materials
/// are the notebook's.
enum SRGlassKind {
    /// Index-card stock. Cards, tiles, list groups.
    case paper
    /// The ink cover. Hero bands. Pair with `SRRegister.ink`.
    case ink
    /// Solid orange. The one primary action on a screen.
    case accent
    /// System glass, for controls floating over content (a map, a photo).
    case clear
}

extension View {
    /// A surface in `shape`: card stock, the ink cover, solid orange, or —
    /// for `.clear` only — the system's Liquid Glass (a material before 26).
    ///
    /// `interactive` no longer changes the surface: paper does not flex. The
    /// press feedback comes from the button the surface is the label of
    /// (`.plain` dims on touch); the parameter stays for its call sites.
    @ViewBuilder
    func srGlass<S: Shape>(_ kind: SRGlassKind = .paper, in shape: S, interactive: Bool = false) -> some View {
        switch kind {
        case .paper:
            self
                .background { shape.fill(SR.Notes.card) }
                .overlay { shape.stroke(SR.line, lineWidth: 1) }
        case .ink:
            self
                .background {
                    ZStack {
                        shape.fill(SR.band)
                        Image(uiImage: SRPaperTile.cover)
                            .resizable(resizingMode: .tile)
                            .clipShape(shape)
                    }
                }
                // Cream at 8%: invisible on day paper, and the only thing that
                // shows the cover's edge on night paper, which is nearly ink.
                .overlay { shape.stroke(SR.cream.opacity(0.08), lineWidth: 1) }
        case .accent:
            self.background { shape.fill(SR.accentDeep) }
        case .clear:
            if #available(iOS 26.0, *) {
                self.glassEffect(Glass.regular.interactive(interactive), in: shape)
            } else {
                self.background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(Color(light: 0xFFFFFF, dark: 0x000000, alpha: 0.2))
                    }
                }
                .overlay { shape.stroke(SR.Glass.rim, lineWidth: 0.75) }
            }
        }
    }

    /// The common case: a card at the app's one corner. Paper, ink and accent
    /// surfaces are clamped to `SR.Glass.radius` whatever a call site asks
    /// for — paper is cut square, and the radii call sites pass (6, 16, 22)
    /// were sized for glass. Glass (`.clear`) keeps the radius it is given.
    func srGlassCard(_ kind: SRGlassKind = .paper, radius: CGFloat = SR.Glass.radius, interactive: Bool = false) -> some View {
        let corner = kind == .clear ? radius : min(radius, SR.Glass.radius)
        return srGlass(kind, in: RoundedRectangle(cornerRadius: corner, style: .continuous), interactive: interactive)
    }
}

/// Glass that should merge when close — chips, a row of buttons.
///
/// On iOS 26 this is `GlassEffectContainer`, which lets neighbouring glass
/// shapes blend into one another as they move. Paper does not merge, so it
/// matters only to `.clear` surfaces now; it is harmless around anything else.
struct SRGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Buttons

/// The app's buttons, in pen and card.
///
/// `.prominent` is the one action a screen is for: a solid orange block
/// (`SR.accentDeep`, which holds 5.5:1 under cream) with the cream mono label.
/// `.regular` is everything else: card stock inside a hand-drawn ink box, an
/// ink label. Both are at least 44pt tall, dim to 80% under the finger and to
/// 45% when disabled.
enum SRButtonWeight { case prominent, regular }

extension View {
    /// Style a `Button` (or `ShareLink`, or anything that takes a button
    /// style) as one of the app's two buttons. `seed` picks the wobble of a
    /// regular button's box; `SRButton` passes `seedFor(title)` so a button
    /// keeps its box.
    func srButton(_ weight: SRButtonWeight = .regular, seed: Int = 47) -> some View {
        buttonStyle(SRNotesButtonStyle(weight: weight, seed: seed))
    }
}

/// The button style behind `srButton`.
struct SRNotesButtonStyle: ButtonStyle {
    var weight: SRButtonWeight = .regular
    var seed: Int = 47

    func makeBody(configuration: Configuration) -> some View {
        SRNotesButtonBody(configuration: configuration, weight: weight, seed: seed)
    }
}

/// A view rather than the style's body, so it can read the environment.
private struct SRNotesButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let weight: SRButtonWeight
    let seed: Int

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let corner = RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
        configuration.label
            .font(SR.Text.label(13))
            .foregroundStyle(weight == .prominent ? SR.paper : SR.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: SR.tapTarget)
            .background {
                if weight == .prominent {
                    corner.fill(SR.accentDeep)
                } else {
                    ZStack {
                        corner.fill(SR.Notes.card)
                        SRInkBox(seed: seed, amp: 0.6, inset: 1)
                            .stroke(SR.inkSecondary, style: .ink(1.3))
                    }
                }
            }
            .contentShape(corner)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A button's label in the app's voice: mono, uppercase, tracked.
struct SRButtonLabel: View {
    let title: String
    var icon: String? = nil
    var fill: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
            }
            Text(title.uppercased())
                .font(SR.Text.label(13))
                .tracking(1.2)
                .lineLimit(1)
        }
        .frame(maxWidth: fill ? .infinity : nil)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}

// MARK: - Headers

/// A headline for a screen whose headline IS the content: a game's result, a
/// round, a workflow's name. The notes page head: an orange mono kicker, the
/// title in Inter ExtraBold at 34 in sentence case, and the strap as
/// marginalia — Fraunces italic in the soft ink.
///
/// NOT for a tab's root. Tab roots carry no page title: the tab bar already
/// says where you are, the bar carries the `sr.` mark (and, on Today, the
/// date), and the first thing under the bar is the thing the tab is opened
/// for. A title there cost a phone a fifth of its first screen to repeat the
/// tab's name.
///
/// It lives IN the scroll rather than in the navigation bar. A custom face in
/// the large-title slot paints nothing at all on iOS 26 (see the note in
/// `SRChrome`), and the bar's job under Liquid Glass is to float, not to carry
/// a headline.
struct SRPageHeader: View {
    let kicker: String
    let title: String
    var strap: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker.uppercased())
                .font(SR.Text.kicker())
                .tracking(SR.Notes.kickerTracking)
                .foregroundStyle(SR.Notes.pen)
            Text(title)
                .font(SR.Text.hero(34))
                .tracking(-34 * 0.035)
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let strap {
                Text(strap)
                    .font(SR.Text.marginalia(17))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The brand mark: `sr` in DM Mono Medium, tightly set, then a DRAWN accent
/// dot with a soft halo where the full stop was.
///
/// The typed `.` was a glyph the face decided the size and weight of, and at
/// bar size it read as punctuation rather than as the mark. Drawn, it is a
/// shape the system controls: 0.3 of the letter size, sitting on the baseline,
/// a ring of the same accent at low strength round it. Every measure is a
/// proportion of `size` and scales with the reader's text setting, so the dot
/// never ends up the wrong size for the letters beside it.
///
/// Matches the design system's Monogram card, which is the reference.
struct SRMark: View {
    /// The navigation bar's size. The ink top bar uses `compactSize`.
    static let barSize: CGFloat = 26
    static let compactSize: CGFloat = 20

    var register: SRRegister = .paper
    var size: CGFloat = SRMark.barSize
    /// 1 at the default text size; the reader's setting moves it, and the dot,
    /// the halo and the tracking move with the letters.
    @ScaledMetric(relativeTo: .headline) private var scale: CGFloat = 1

    var body: some View {
        let unit = size * scale
        HStack(alignment: .firstTextBaseline, spacing: unit * 0.08) {
            Text("sr")
                .font(SR.Text.mark(size))
                .tracking(-unit * 0.054)
                .foregroundStyle(register.primary)
            Circle()
                .fill(register.accent)
                .frame(width: unit * 0.3, height: unit * 0.3)
                .padding(unit * 0.115)
                .background(Circle().fill(register.accent.opacity(register == .ink ? 0.22 : 0.16)))
                // The dot's foot on the baseline: the ring hangs below it, as
                // the halo does on the site.
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - unit * 0.115 }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Strange Ramblings")
    }
}

/// The mark in the navigation bar's centre.
struct SRBarMark: View {
    var body: some View {
        SRMark()
    }
}

// MARK: - Small furniture

/// A rubber stamp holding a short mono label. Status, not action.
///
/// Was a glass capsule; now the notes look's stamp: mono caps tracked 0.16em in
/// the tone, a hand-drawn box in the same tone at 75%, the box's wobble seeded
/// from the words so a status keeps its box. Tilted −2° standing on its own;
/// pass `tilt: 0` for a chip packed into a dense row, where a slant reads as
/// a mistake.
struct SRGlassChip: View {
    let text: String
    var icon: String? = nil
    var tone: Color = SR.inkSecondary
    var tilt: Double = -2

    var body: some View {
        SRStamp(text: text, icon: icon, tone: tone, tilt: tilt)
    }
}

/// The stamp both `SRGlassChip` and `SRPill` draw.
struct SRStamp: View {
    let text: String
    var icon: String? = nil
    var tone: Color = SR.inkSecondary
    var tilt: Double = 0

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text.uppercased())
                .font(SR.Text.kicker())
                .tracking(SR.Notes.stampTracking)
                .lineLimit(1)
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .overlay {
            SRStampBox(seed: seedFor(text))
                .stroke(tone.opacity(0.75), style: .ink(1.3))
                .accessibilityHidden(true)
        }
        .rotationEffect(.degrees(tilt))
    }
}

/// The circular glass icon button — the size of a tab-bar glyph, for a toolbar
/// or a floating control.
struct SRGlassIconButton: View {
    let icon: String
    let label: String
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .srButton(prominent ? .prominent : .regular)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }
}

extension View {
    /// A row in an inset-grouped list on the ruled page: card stock, with a
    /// petrol feint between rows — the ledger look. The section keeps the
    /// system's corner and the page's rules show between sections.
    func srGlassRow() -> some View {
        self
            .listRowBackground(SR.Notes.card)
            .listRowSeparatorTint(SR.Notes.rule)
    }

    /// A header row in a grouped list that is not a row at all — the page
    /// headline, sitting on the ground above the first section.
    func srBareRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))
    }
}
