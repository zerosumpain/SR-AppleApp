import SwiftUI
import UIKit

/// Glass over a bright ground.
///
/// The app used to be the website's system carried over whole: a cream page,
/// zero radius, no shadows, ink as chrome. The first overhaul moved the
/// furniture to Apple's Liquid Glass; Prism (2026-10-18) changed what the
/// glass sits over and the voice it speaks in:
///
/// - **The furniture is glass.** Tab bar, navigation bar, buttons, the chat
///   composer, chips, the floating figures. On iOS 26 these are the system's
///   own `glassEffect`; on 17–25 they fall back to a material, so an older
///   phone gets frosted panels rather than a crash.
/// - **The ground is bright.** A cool near-white (midnight in dark mode) lit by
///   soft fields of the screen's feature hues — glass with nothing behind it
///   to bend is just a grey panel, and this is what it bends.
/// - **The band survives as smoked indigo glass.** The register rule still
///   holds: anything on it asks `SRRegister.ink` for its colour.
/// - **The voice is rounded.** SF Pro Rounded for figures, headlines and
///   labels, SF Pro for reading copy, electric violet for the one thing that
///   matters on a screen, the `sr.` mark in the bar.
///
/// Glass is continuous curvature or it is not glass, so surfaces take
/// `SR.Glass.radius` — the one corner the app uses.
extension SR {
    enum Glass {
        /// The corner every glass surface uses. Concentric with the phone's
        /// own corners at a 16pt inset, which is where the cards sit.
        static let radius: CGFloat = 26
        /// Rows, chips and inner panels inside a card.
        static let innerRadius: CGFloat = 16
        /// How far a hero slab sits in from the screen edge.
        static let bandInset: CGFloat = SR.gutter
        /// A white tint on glass over the ground, so a panel reads as a sheet
        /// lifted off the page rather than a hole in it.
        static let paperTint = Color(light: 0xFFFFFF, dark: 0x221F48, alpha: 0.62)
        /// The smoked slab. Indigo, not black.
        static let inkTint = Color(hex: SR.Fixed.ink, alpha: 0.86)
        /// A grouped list row over the atmosphere: frosted white, not opaque, so
        /// the ground shows through the sections the way it does through glass.
        static let rowFill = Color(light: 0xFFFFFF, dark: 0x1E1B40, alpha: 0.74)
        /// The accent, as glass wants it: saturated enough to read through.
        static let accentTint = Color(light: SR.Fixed.accent, dark: 0xA194FF, alpha: 0.88)
        /// The pre-26 fallback's highlight edge. A white rim on a dark page is
        /// a glare line, so it dims with the ground.
        static let rim = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.12) : UIColor(white: 1, alpha: 0.45) })
    }
}

// MARK: - The ground

/// Which way a screen's atmosphere leans.
///
/// One tab, one mood — the hue under the glass tells you where you are before
/// the title does, and never so strongly that it competes with the content.
enum SRMood {
    /// Home and Family: coral, sky and violet.
    case warm
    /// Chat: almost nothing. Reading copy wants a quiet ground.
    case quiet
    /// Health: green and lime, with a touch of the Move pink.
    case vital
    /// News: teal and blue.
    case wire

    /// The three hues the ground is lit with.
    var hues: [SR.Hue] {
        switch self {
        case .warm: return [.family, .trips, .daydream]
        case .quiet: return [.chat, .messages, .daydream]
        case .vital: return [.health, .move, .wildmind]
        case .wire: return [.news, .trips, .chat]
        }
    }

    /// How strongly. Reading screens stay faint.
    var strength: Double {
        switch self {
        case .warm, .vital, .wire: return 1
        case .quiet: return 0.45
        }
    }
}

/// The ground and the soft fields of hue the glass refracts.
///
/// No grain since Prism: the grain was paper's texture, and the ground is
/// not paper any more. Drawn once — see `SRPrismGround`.
struct SRAtmosphere: View {
    var mood: SRMood = .warm

    var body: some View {
        SRPrismGround(hues: mood.hues, scale: mood.strength)
    }
}

extension View {
    /// The screen's ground: paper with its atmosphere, under a scroll view or a
    /// list, edge to edge.
    func srGround(_ mood: SRMood = .warm) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { SRAtmosphere(mood: mood) }
    }
}

// MARK: - Glass, with a floor

/// How much glass a surface asks for.
enum SRGlassKind {
    /// A sheet of the page, lifted. Cards, tiles, list groups.
    case paper
    /// The smoked slab. Hero bands. Pair with `SRRegister.ink`.
    case ink
    /// The accent as glass. The one primary action on a screen.
    case accent
    /// Untinted, for controls floating over content.
    case clear
}

extension View {
    /// Liquid Glass in `shape` on iOS 26, a tinted material before it.
    ///
    /// Every glass surface in the app goes through here, so the fallback is
    /// decided once. `interactive` is for things you press: the glass flexes
    /// and lights under the finger, which is the feedback a flat button never
    /// had.
    @ViewBuilder
    func srGlass<S: Shape>(_ kind: SRGlassKind = .paper, in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(srGlassValue(kind, interactive: interactive), in: shape)
        } else {
            self.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(srFallbackTint(kind))
                }
            }
            .overlay { shape.stroke(kind == .ink ? Color.white.opacity(0.10) : SR.Glass.rim, lineWidth: 0.75) }
        }
    }

    /// The common case: a rounded glass sheet at the app's one radius.
    func srGlassCard(_ kind: SRGlassKind = .paper, radius: CGFloat = SR.Glass.radius, interactive: Bool = false) -> some View {
        srGlass(kind, in: RoundedRectangle(cornerRadius: radius, style: .continuous), interactive: interactive)
    }

}

@available(iOS 26.0, *)
private func srGlassValue(_ kind: SRGlassKind, interactive: Bool) -> Glass {
    let base: Glass
    switch kind {
    case .paper: base = Glass.regular.tint(SR.Glass.paperTint)
    case .ink: base = Glass.regular.tint(SR.Glass.inkTint)
    case .accent: base = Glass.regular.tint(SR.Glass.accentTint)
    case .clear: base = Glass.regular
    }
    return base.interactive(interactive)
}

private func srFallbackTint(_ kind: SRGlassKind) -> Color {
    switch kind {
    case .paper: return Color(light: 0xFFFFFF, dark: 0x221F48, alpha: 0.66)
    case .ink: return Color(hex: SR.Fixed.ink, alpha: 0.92)
    case .accent: return SR.accent
    case .clear: return Color(light: 0xFFFFFF, dark: 0x000000, alpha: 0.2)
    }
}

/// Glass that should merge when close — chips, a row of buttons.
///
/// On iOS 26 this is `GlassEffectContainer`, which lets neighbouring glass
/// shapes blend into one another as they move. Before 26 it is a plain stack's
/// worth of nothing.
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

/// The app's buttons, as glass.
///
/// `.prominent` is the one action a screen is for — accent glass, cream label.
/// `.regular` is everything else. On iOS 26 both are the system's own glass
/// button styles, so they press, flex and morph exactly like every other app
/// on the phone; before 26 they are capsules.
enum SRButtonWeight { case prominent, regular }

extension View {
    @ViewBuilder
    func srButton(_ weight: SRButtonWeight = .regular) -> some View {
        if #available(iOS 26.0, *) {
            switch weight {
            case .prominent: self.buttonStyle(.glassProminent).tint(SR.accent)
            case .regular: self.buttonStyle(.glass).tint(SR.ink)
            }
        } else {
            switch weight {
            case .prominent: self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(SR.accent)
            case .regular: self.buttonStyle(.bordered).buttonBorderShape(.capsule).tint(SR.ink)
            }
        }
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
/// round, a workflow's name. A mono kicker, then the title in Inter Display.
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
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.accent)
            Text(title)
                .font(SR.Text.hero(38))
                .tracking(-0.8)
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let strap {
                Text(strap)
                    .font(SR.Text.secondary())
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

/// A capsule of glass holding a short mono label. Status, not action.
struct SRGlassChip: View {
    let text: String
    var icon: String? = nil
    var tone: Color = SR.inkSecondary

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text.uppercased()).font(SR.Text.mono()).tracking(0.8)
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .srGlass(.paper, in: Capsule())
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
    /// A row in an inset-grouped list over the atmosphere.
    func srGlassRow() -> some View {
        self
            .listRowBackground(SR.Glass.rowFill)
            .listRowSeparatorTint(SR.divider)
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
