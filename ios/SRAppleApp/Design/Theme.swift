import SwiftUI

/// The Strange Ramblings design system, as the app sees it.
///
/// Ported from `src/app.css` in SR-Main and from the four components that ARE
/// the /health methodology — `SectionHead`, `HealthShell`, `RankedMoves`,
/// `TripwireTable`. Values are copied from the tokens, never re-picked by eye.
///
/// ## Two registers, because a paper token is invisible on ink
///
/// This is the single hardest-won rule in the system. `--text-muted`,
/// `--accent`, `--error` and the rest were all chosen against cream; on the
/// `#1a1008` bands they are ink on ink. The site's answer is a second value for
/// each — `--accent-on-dark`, `--good-on-dark`, `--accent-ink-on-dark` — and the
/// relighting checklist says to grep the component rather than eyeball the
/// render. Here that becomes `SRRegister`: a view asks its register for a
/// colour and cannot accidentally reach for the paper one.
///
/// ## Ink is chrome and thin bands
///
/// From the third round of the site rebuild, after "a little intense": a TALL
/// SOLID INK AREA READS AS INTENSITY, NOT AS EDITORIAL. Ink belongs to the bar
/// the page hangs from, the footer strip, and at most one dense ledger. The
/// reading surface stays paper. The app follows that — `SRShell` paints an ink
/// bar at the top edge so everything docks under it, and the content scrolls on
/// cream beneath.
enum SR {

    // MARK: - Palette (src/app.css `:root`)

    /// Warm cream. `--bg`.
    static let paper = Color(hex: 0xEDE4D4)
    /// `--surface-elevated` — the opaque panel ground. Never a tint: `--card-bg`
    /// is 7% ink and reads as transparent the moment it sits over anything.
    static let surface = Color(hex: 0xE8DECE)
    /// `--text-primary`, and the ink band's ground.
    static let ink = Color(hex: 0x1A1008)
    /// `--text-secondary`.
    static let inkSecondary = Color(hex: 0x3D2E1A)
    /// `--text-muted` — 65% ink on paper. PAPER ONLY.
    static let inkMuted = Color(hex: 0x1A1008, alpha: 0.65)
    /// `--text-ghost` — 45%. PAPER ONLY.
    static let inkGhost = Color(hex: 0x1A1008, alpha: 0.45)

    /// `--accent`, burnt orange. Punchy, not regal. PAPER ONLY.
    static let accent = Color(hex: 0xC4570A)
    /// `--accent-on-dark`. `--accent` scores 2.6:1 on `#1a1008`, under the
    /// floor; this is its partner, not a second accent.
    static let accentOnDark = Color(hex: 0xE8863A)
    /// `--accent-ink`, deep petrol. The counter-accent, and PAPER ONLY — it has
    /// no role on an ink band, which is why petrol left the vitals rail.
    static let accentInk = Color(hex: 0x0E5B66)
    /// `--accent-ink-on-dark`.
    static let accentInkOnDark = Color(hex: 0x7FB8C0)

    /// `--good`, olive. The one hue meaning a number is going the right way.
    static let good = Color(hex: 0x55663A)
    /// `--good-on-dark`. Measured off the dashboard reference; the handoff's
    /// token table names #6b7f4a but every appearance of that shade is on paper.
    static let goodOnDark = Color(hex: 0x8A9A5B)

    static let warn = Color(hex: 0xB0892A)
    static let error = Color(hex: 0xCC4444)
    /// Error, lifted for ink. The paper value is a smudge on `#1a1008`.
    static let errorOnDark = Color(hex: 0xE08B8B)

    /// `--card-border`.
    static let line = Color(hex: 0x1A1008, alpha: 0.18)
    /// `--divider`.
    static let divider = Color(hex: 0x1A1008, alpha: 0.08)
    /// The hairline on an ink band. `--line-hair` is invisible there.
    static let lineOnDark = Color(hex: 0xEDE4D4, alpha: 0.14)
    /// Cream at reading weight on ink.
    static let creamOnDark = Color(hex: 0xEDE4D4, alpha: 0.70)

    // MARK: - Type
    //
    // Referenced by PostScript name, not family — a family lookup with a weight
    // asks UIKit to pick, and for a three-cut family it picks wrong. The names
    // are stamped into the files by the build step that instanced DM Sans out of
    // its variable original; `Fonts/` holds the faces and their OFL licences.

    enum Face {
        /// Archivo Black. Headlines. The live site DELIBERATELY keeps this —
        /// the design repo says Zilla Slab; do not "fix" it.
        static let display = "ArchivoBlack-Regular"
        /// DM Mono. The 'sr.' brand mark and the wordmark.
        static let brand = "DMMono-Regular"
        static let brandMedium = "DMMono-Medium"
        /// DM Sans. Body copy.
        static let body = "DMSans-Regular"
        static let bodyMedium = "DMSans-Medium"
        static let bodyBold = "DMSans-Bold"
        /// JetBrains Mono. Labels, nav, figures.
        static let mono = "JetBrainsMono-Regular"
        static let monoMedium = "JetBrainsMono-Medium"
        static let monoBold = "JetBrainsMono-Bold"
    }

    /// The 12pt floor. `check-font-sizes` gates 12px sitewide and the health
    /// rebuild mapped the reference's 8–11px labels onto it rather than keeping
    /// them; the same floor applies here, where the screen is smaller and the
    /// argument for small type is weaker, not stronger.
    static let labelFloor: CGFloat = 12

    // EVERY ONE OF THESE SCALES.
    //
    // They did not. `Font.custom(name:size:)` returns a fixed size and ignores
    // the reader's text setting completely, so a phone set to Larger Text — or
    // to any accessibility size — rendered this app at exactly the same points
    // as a phone set to the smallest. On the web the same values are `rem` and
    // scale for free, which is how the property got lost in the port: nobody
    // removed it, it simply did not survive being retyped.
    //
    // The fix is here rather than at the call sites. There were 104 of them,
    // and a new `SR.Text` ramp beside an old fixed one would have meant
    // converting them by hand and leaving the fixed API in the file for the
    // next person to reach for. Teaching the old names to scale fixes every
    // screen at once, including the ones nobody is editing this week.
    //
    // The TextStyle each is measured against is not decorative. A headline
    // pinned to `.caption` barely moves; a 12pt label pinned to `.largeTitle`
    // doubles and breaks the row it sits in.
    static func display(_ size: CGFloat) -> Font { .custom(Face.display, size: size, relativeTo: .title) }
    static func body(_ size: CGFloat = 16) -> Font { .custom(Face.body, size: size, relativeTo: .body) }
    static func bodyMedium(_ size: CGFloat = 16) -> Font { .custom(Face.bodyMedium, size: size, relativeTo: .body) }
    static func bodyBold(_ size: CGFloat = 16) -> Font { .custom(Face.bodyBold, size: size, relativeTo: .body) }
    static func brand(_ size: CGFloat = 14) -> Font { .custom(Face.brand, size: size, relativeTo: .headline) }
    static func mono(_ size: CGFloat = 12) -> Font { .custom(Face.mono, size: max(size, labelFloor), relativeTo: .caption) }
    static func monoMedium(_ size: CGFloat = 12) -> Font { .custom(Face.monoMedium, size: max(size, labelFloor), relativeTo: .caption) }
    static func monoBold(_ size: CGFloat = 12) -> Font { .custom(Face.monoBold, size: max(size, labelFloor), relativeTo: .caption) }

    // MARK: - Metrics
    //
    // Radii are 0 throughout. The only exceptions are the live dot and any pill,
    // at 100; the system deliberately skips the 8/12/16 middle. There are no
    // shadows either, except the live dot's glow — which is a glow, not
    // elevation.
    enum Radius {
        static let none: CGFloat = 0
        static let hair: CGFloat = 2
        static let soft: CGFloat = 4
        static let pill: CGFloat = 100
    }

    /// The page gutter. `clamp(20px, 3vw, 44px)` on the web; a phone is always
    /// at the floor of that.
    static let gutter: CGFloat = 20
    /// The gap between sections inside one screen.
    static let sectionGap: CGFloat = 28
    /// Mono label tracking — `.sr-label-tight` runs 0.18em on a kicker.
    static let kickerTracking: CGFloat = 1.6
}

/// Which ground a view is painting on.
///
/// Exists so a component cannot reach for a paper token while sitting on ink.
/// Every trap in the site's relighting checklist was that one mistake, found by
/// eye after the fact; asking the register for the colour makes it unavailable.
enum SRRegister {
    case paper
    case ink

    var background: Color { self == .paper ? SR.paper : SR.ink }
    var primary: Color { self == .paper ? SR.ink : SR.paper }
    var secondary: Color { self == .paper ? SR.inkSecondary : SR.creamOnDark }
    var muted: Color { self == .paper ? SR.inkMuted : Color(hex: 0xEDE4D4, alpha: 0.55) }
    var accent: Color { self == .paper ? SR.accent : SR.accentOnDark }
    var counter: Color { self == .paper ? SR.accentInk : SR.accentInkOnDark }
    var good: Color { self == .paper ? SR.good : SR.goodOnDark }
    var danger: Color { self == .paper ? SR.error : SR.errorOnDark }
    var hairline: Color { self == .paper ? SR.line : SR.lineOnDark }
    var divider: Color { self == .paper ? SR.divider : Color(hex: 0xEDE4D4, alpha: 0.12) }
}

extension Color {
    /// `0xEDE4D4` reads like the token it came from; three doubles do not.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Dynamic Type
//
// `Font.custom(name:size:)` returns a FIXED size. It ignores the reader's text
// setting entirely, so an app built on it is the same nine points whether the
// slider is at extra-small or at accessibility-extra-extra-extra-large. On the
// web the same values are `rem`, which do scale, so the port quietly dropped a
// property the page had.
//
// `Font.custom(_:size:relativeTo:)` is the fix, and it needs a TextStyle to
// scale against — the metric is "this size, growing the way `.body` grows". The
// pairing matters: a headline pinned to `.caption` barely moves, and a 12pt
// label pinned to `.largeTitle` doubles and breaks the row it sits in.
extension SR {
    /// Type scaled to the reader's setting. Every new surface uses these.
    enum Text {
        /// The one big figure on a screen. Archivo Black.
        static func hero(_ size: CGFloat = 34) -> Font { .custom(Face.display, size: size, relativeTo: .largeTitle) }
        /// A section's headline.
        static func display(_ size: CGFloat = 22) -> Font { .custom(Face.display, size: size, relativeTo: .title2) }
        /// A row's or card's title.
        static func title(_ size: CGFloat = 17) -> Font { .custom(Face.bodyMedium, size: size, relativeTo: .headline) }
        /// Reading copy.
        static func body(_ size: CGFloat = 16) -> Font { .custom(Face.body, size: size, relativeTo: .body) }
        static func bodyMedium(_ size: CGFloat = 16) -> Font { .custom(Face.bodyMedium, size: size, relativeTo: .body) }
        /// Supporting copy under a title.
        static func secondary(_ size: CGFloat = 14) -> Font { .custom(Face.body, size: size, relativeTo: .subheadline) }
        /// A figure. JetBrains Mono, because a number wants tabular stems.
        static func figure(_ size: CGFloat = 28) -> Font { .custom(Face.display, size: size, relativeTo: .title) }
        /// The mono eyebrow. Never below the 12pt floor before scaling.
        static func label(_ size: CGFloat = 12) -> Font { .custom(Face.monoMedium, size: max(size, labelFloor), relativeTo: .caption) }
        static func mono(_ size: CGFloat = 12) -> Font { .custom(Face.mono, size: max(size, labelFloor), relativeTo: .caption) }
        /// The brand mark.
        static func brand(_ size: CGFloat = 15) -> Font { .custom(Face.brand, size: size, relativeTo: .headline) }
    }

    // MARK: - Phone metrics
    //
    // The web gutter is `clamp(20px, 3vw, 44px)` and a phone is always at the
    // floor, so 20 stays. The rest are new: a page has no rows, and a list of
    // rows needs a rhythm the page never had to name.

    /// The smallest thing a thumb can reliably hit. Apple's floor, and the one
    /// number in here that is not a taste decision.
    static let tapTarget: CGFloat = 44
    /// A list row's vertical padding. 12 top and bottom around a 17pt title
    /// clears 44 without measuring.
    static let rowPadding: CGFloat = 12
    /// Between cards in a stack.
    static let cardGap: CGFloat = 12
    /// Inside a card.
    static let cardPadding: CGFloat = 16
}

// MARK: - The ink band
//
// /health's hero sections are full-width ink bands on the paper page, and every
// colour on them is cream at a strength rather than a second palette. That is
// the whole trick: one hue, stepped, so nothing on the band can be a paper token
// by mistake. The ladder below is copied from the SR-Health stylesheet, rung for
// rung — `rgba(237, 228, 212, a)`.
extension SR {
    /// Cream on ink at a named strength. Ask for a rung, not an opacity.
    static func onInk(_ rung: InkRung) -> Color { Color(hex: 0xEDE4D4, alpha: rung.rawValue) }

    enum InkRung: Double {
        /// A card's fill on the band.
        case fill = 0.05
        /// A donut's or bar's empty track.
        case track = 0.14
        /// The band's hairline. The only rule weight on ink.
        case hairline = 0.16
        /// Ghosted, inactive.
        case ghost = 0.3
        /// A unit or a meta line.
        case unit = 0.45
        /// A mono label.
        case label = 0.55
        /// A note in body copy.
        case note = 0.7
        /// A date under a title.
        case date = 0.75
        /// Primary cream.
        case primary = 1
    }

    /// Mono kicker tracking on the band — 0.18em of a 12pt face.
    static let inkKickerTracking: CGFloat = 2.16
    /// Tile label tracking — 0.15em.
    static let inkLabelTracking: CGFloat = 1.8
    /// Inside an ink tile.
    static let inkTilePadding: CGFloat = 18
}
