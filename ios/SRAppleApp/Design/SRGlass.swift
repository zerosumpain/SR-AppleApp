import SwiftUI

/// Paper under glass.
///
/// The app used to be the website's system carried over whole: a cream page,
/// zero radius, no shadows, ink as chrome. That was right for a desk and it
/// read, on iOS 26, as an app that had not noticed the phone it was on — every
/// bar opaque, every control flat, nothing refracting anything.
///
/// The overhaul biases towards Apple's Liquid Glass and keeps Strange Ramblings
/// as the MATERIAL the glass sits over and the voice it speaks in:
///
/// - **The furniture is glass.** Tab bar, navigation bar, buttons, the chat
///   composer, chips, the floating figures. On iOS 26 these are the system's
///   own `glassEffect`; on 17–25 they fall back to a material, so an older
///   phone gets frosted panels rather than a crash.
/// - **The ground is paper.** Cream, grain, and two faint fields of the accent
///   and the counter-accent drifting under the content — glass with nothing
///   behind it to bend is just a grey panel, and this is what it bends.
/// - **Ink survives as smoked glass.** /health's ink band becomes a dark slab
///   tinted `#1a1008`. The register rule still holds: anything on it asks
///   `SRRegister.ink` for its colour.
/// - **The voice is SR.** Archivo Black for figures and headlines, JetBrains
///   Mono kickers, DM Sans reading copy, burnt orange for the one thing that
///   matters on a screen, the `sr.` mark in the bar.
///
/// What gave way: the zero radius. Glass is continuous curvature or it is not
/// glass, so surfaces take `SR.Glass.radius` — the one corner the app uses.
extension SR {
    enum Glass {
        /// The corner every glass surface uses. Concentric with the phone's
        /// own corners at a 16pt inset, which is where the cards sit.
        static let radius: CGFloat = 26
        /// Rows, chips and inner panels inside a card.
        static let innerRadius: CGFloat = 16
        /// How far a hero slab sits in from the screen edge.
        static let bandInset: CGFloat = SR.gutter
        /// A cream tint on glass over paper, so a panel reads as a sheet of the
        /// page lifted rather than a hole in it.
        static let paperTint = Color(hex: 0xF6EFE3, alpha: 0.55)
        /// The smoked slab. Ink, not black — the brown is the SR part.
        static let inkTint = Color(hex: 0x1A1008, alpha: 0.82)
        /// A grouped list row over the atmosphere: frosted cream, not opaque, so
        /// the ground shows through the sections the way it does through glass.
        static let rowFill = Color(hex: 0xFBF6EE, alpha: 0.62)
        /// The accent, as glass wants it: saturated enough to read through.
        static let accentTint = Color(hex: 0xC4570A, alpha: 0.85)
    }
}

// MARK: - The ground

/// Which way a screen's atmosphere leans.
///
/// One tab, one mood — the hue under the glass tells you where you are before
/// the title does, and never so strongly that it competes with the content.
enum SRMood {
    /// Today: the accent, warm.
    case warm
    /// Chat: almost nothing. Reading copy wants a quiet ground.
    case quiet
    /// Health: olive and accent — the good direction and the bad.
    case vital
    /// News: petrol, the counter-accent.
    case wire

    fileprivate var fields: [(Color, UnitPoint, CGFloat)] {
        switch self {
        case .warm:
            return [(SR.accent.opacity(0.22), UnitPoint(x: 0.95, y: 0.02), 420),
                    (SR.warn.opacity(0.16), UnitPoint(x: 0.0, y: 0.45), 360),
                    (SR.accentInk.opacity(0.08), UnitPoint(x: 0.9, y: 0.95), 380)]
        case .quiet:
            return [(SR.accent.opacity(0.08), UnitPoint(x: 1.0, y: 0.0), 380),
                    (SR.accentInk.opacity(0.05), UnitPoint(x: 0.0, y: 1.0), 380)]
        case .vital:
            return [(SR.good.opacity(0.20), UnitPoint(x: 0.0, y: 0.05), 420),
                    (SR.accent.opacity(0.14), UnitPoint(x: 1.0, y: 0.35), 360),
                    (SR.good.opacity(0.10), UnitPoint(x: 0.6, y: 1.0), 380)]
        case .wire:
            return [(SR.accentInk.opacity(0.18), UnitPoint(x: 1.0, y: 0.0), 420),
                    (SR.accent.opacity(0.10), UnitPoint(x: 0.0, y: 0.55), 340),
                    (SR.accentInk.opacity(0.08), UnitPoint(x: 0.5, y: 1.0), 380)]
        }
    }
}

/// Cream, the grain, and the soft fields the glass refracts.
///
/// Radial gradients rather than blurred shapes: a blur is re-rendered every
/// frame a scroll view moves over it, a gradient is drawn once.
struct SRAtmosphere: View {
    var mood: SRMood = .warm

    var body: some View {
        ZStack {
            SR.paper
            ForEach(Array(mood.fields.enumerated()), id: \.offset) { _, field in
                RadialGradient(
                    colors: [field.0, field.0.opacity(0)],
                    center: field.1,
                    startRadius: 0,
                    endRadius: field.2
                )
            }
            SRGrain(opacity: 0.035)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
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
            .overlay { shape.stroke(Color.white.opacity(kind == .ink ? 0.10 : 0.45), lineWidth: 0.75) }
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
    case .paper: return Color(hex: 0xF6EFE3, alpha: 0.6)
    case .ink: return Color(hex: 0x1A1008, alpha: 0.9)
    case .accent: return SR.accent
    case .clear: return Color.white.opacity(0.2)
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

/// The top of a tab: a mono kicker, then the title in Archivo Black.
///
/// It lives IN the scroll rather than in the navigation bar. A custom face in
/// the large-title slot paints nothing at all on iOS 26 (see the note in
/// `SRChrome`), and the bar's job under Liquid Glass is to float, not to carry
/// a headline. The bar holds the `sr.` mark; the page holds the title.
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

/// The `sr.` mark for the navigation bar's centre.
struct SRBarMark: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("sr").foregroundStyle(SR.ink)
            Text(".").foregroundStyle(SR.accent)
        }
        .font(SR.Text.brand(17))
        .accessibilityLabel("Strange Ramblings")
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
