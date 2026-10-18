import SwiftUI
import UIKit

/// The Strange Ramblings design system, as the app sees it.
///
/// ## Prism (2026-10-18)
///
/// The app used to wear the website: cream paper, burnt orange, an ink band,
/// mono kickers. John asked for the phone to be its own thing — "brightly
/// coloured", "simple", "significantly different" — so the palette below is
/// new and the website keeps its own. Light is a cool near-white with deep
/// indigo type; dark is a midnight ground with lifted, saturated partners.
/// One electric violet is THE accent; every feature also owns a vivid hue
/// (`SR.Hue`), and every family member owns one too (`SR.PersonHue`), because
/// the visualisations are colour-coded by who and by what.
///
/// Every text token below holds WCAG AA (4.5:1) on both the ground and the
/// surface, in both modes — measured, not eyeballed.
///
/// ## Two registers, because a paper token is invisible on ink
///
/// Still the hardest-won rule. A token chosen for the light ground is a smudge
/// on the dark slab, so each one has an `-on-dark` partner and `SRRegister`
/// hands a view the right one for the ground it sits on.
enum SR {

    // MARK: - Palette (Prism)
    //
    // ## Dark mode
    //
    // Every ground-register token below is a pair: the value for a light phone
    // and its partner for a dark one. Dark is the page INVERTED — the ground
    // goes to midnight and the ink goes to near-white — and every accent swaps
    // to a lifted, more saturated partner measured against the dark surface.
    // A fill of `SR.ink` carrying `SR.paper` type holds its contrast both ways.
    //
    // The BAND does not invert. It is a deep indigo slab in both modes, and
    // anything on it asks `SRRegister.ink` (or `SR.band` / `SR.cream`) for its
    // colour — the fixed pair — never `SR.ink` / `SR.paper`.

    /// The ground. A cool near-white; midnight in dark mode.
    static let paper = Color(uiColor: UI.paper)
    /// The opaque panel ground: white, or a lifted midnight.
    static let surface = Color(light: Fixed.surface, dark: 0x1A1838)
    /// Type. Deep indigo; near-white in dark mode. For the band, `SR.band`.
    static let ink = Color(uiColor: UI.ink)
    /// Supporting type. 8:1 on the ground in light, 11:1 in dark.
    static let inkSecondary = Color(light: Fixed.inkSecondary, dark: 0xC8C4EE)
    /// 65% ink. GROUND ONLY.
    static let inkMuted = Color(uiColor: UI.inkMuted)
    /// 45%. GROUND ONLY — decoration, never something to read.
    static let inkGhost = Color(light: Fixed.ink, dark: Fixed.paper, alpha: 0.45)

    /// The band's ground, in BOTH modes. Deep indigo.
    static let band = Color(hex: Fixed.ink)
    /// Near-white type on the band, in BOTH modes.
    static let cream = Color(hex: Fixed.paper)

    /// THE accent: electric violet. 6.2:1 on the ground. GROUND ONLY.
    static let accent = Color(uiColor: UI.accent)
    /// The accent one step deeper, for a FILL that carries white text — the
    /// Ask button, a selected chip. 8.4:1 under white. In dark mode the fill
    /// carries `SR.paper` (dark) type, so it lifts instead.
    static let accentDeep = Color(light: 0x4426D6, dark: 0xA194FF)
    /// The accent lifted for the band: 6.4:1 on indigo.
    static let accentOnDark = Color(hex: 0xA194FF)
    /// The counter-accent: deep teal; aqua in dark mode. GROUND ONLY.
    static let accentInk = Color(light: Fixed.accentInk, dark: 0x4FD8E0)
    /// The counter-accent on the band.
    static let accentInkOnDark = Color(hex: 0x4FD8E0)

    /// Green: the one hue meaning a number is going the right way.
    static let good = Color(light: Fixed.good, dark: 0x4ADE80)
    /// Green on the band.
    static let goodOnDark = Color(hex: 0x4ADE80)

    static let warn = Color(light: Fixed.warn, dark: 0xFFC24B)
    static let error = Color(light: Fixed.error, dark: 0xFF6B85)
    /// Error, lifted for the band.
    static let errorOnDark = Color(hex: 0xFF6B85)

    /// A card's border.
    static let line = Color(uiColor: UI.line)
    /// A rule between rows.
    static let divider = Color(light: Fixed.ink, dark: Fixed.paper, alpha: 0.08)
    /// The hairline on the band.
    static let lineOnDark = Color(hex: Fixed.paper, alpha: 0.14)
    /// Near-white at reading weight on the band.
    static let creamOnDark = Color(hex: Fixed.paper, alpha: 0.72)

    /// The mode-following tokens UIKit's appearance proxies need as a
    /// `UIColor` — built here, once, so the proxy holds the dynamic colour
    /// itself rather than a conversion that may have resolved it.
    enum UI {
        static let paper = UIColor(light: Fixed.paper, dark: 0x0B0A1C)
        static let ink = UIColor(light: Fixed.ink, dark: Fixed.paper)
        static let inkMuted = UIColor(light: Fixed.ink, dark: Fixed.paper, alpha: 0.65)
        static let accent = UIColor(light: Fixed.accent, dark: 0xA194FF)
        static let line = UIColor(light: Fixed.ink, dark: Fixed.paper, alpha: 0.18)
    }

    /// The light values, raw. For the few surfaces that must look the same in
    /// both modes — a game's coloured tiles, a widget preview.
    enum Fixed {
        static let paper: UInt32 = 0xF4F3FB
        static let surface: UInt32 = 0xFFFFFF
        static let ink: UInt32 = 0x15123A
        static let inkSecondary: UInt32 = 0x45417A
        static let accent: UInt32 = 0x5233F0
        static let accentInk: UInt32 = 0x087078
        static let good: UInt32 = 0x0A8048
        static let warn: UInt32 = 0x9A5B00
        static let error: UInt32 = 0xD7193F
    }

    // MARK: - Type
    //
    // Prism reads in the phone's own faces: SF Pro for reading copy and SF Pro
    // ROUNDED for everything you glance at — headlines, figures, labels. Round
    // terminals at heavy weights are what make a bright dashboard read as
    // friendly rather than as a control panel, and the system faces carry
    // every Dynamic Type size and every language the bundled ones did not.
    //
    // The bundled faces stay for two jobs: the `sr.` mark (DM Mono) and code,
    // whose alignment carries meaning (JetBrains Mono, `SR.code`). Referenced by
    // PostScript name, not family — a family lookup with a weight asks UIKit to
    // pick, and for a three-cut family it picks wrong.

    enum Face {
        /// Inter Display ExtraBold. Headlines until Prism; still bundled for the
        /// widgets, which draw in their own process. Licence in `Fonts/OFL-Inter.txt`.
        static let display = "InterDisplay-ExtraBold"
        /// DM Mono. The 'sr.' brand mark and the wordmark.
        static let brand = "DMMono-Regular"
        static let brandMedium = "DMMono-Medium"
        /// DM Sans. Body copy until Prism; kept registered for the widgets.
        static let body = "DMSans-Regular"
        static let bodyMedium = "DMSans-Medium"
        static let bodyBold = "DMSans-Bold"
        /// JetBrains Mono. Code — content whose alignment carries meaning.
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
    static func display(_ size: CGFloat) -> Font { SRType.rounded(size, .heavy, .title1) }
    static func body(_ size: CGFloat = 16) -> Font { SRType.plain(size, .regular, .body) }
    static func bodyMedium(_ size: CGFloat = 16) -> Font { SRType.plain(size, .medium, .body) }
    static func bodyBold(_ size: CGFloat = 16) -> Font { SRType.plain(size, .bold, .body) }
    static func brand(_ size: CGFloat = 14) -> Font { .custom(Face.brand, size: size, relativeTo: .headline) }
    static func mono(_ size: CGFloat = 12) -> Font { SRType.rounded(max(size, labelFloor), .medium, .caption1).monospacedDigit() }
    static func monoMedium(_ size: CGFloat = 12) -> Font { SRType.rounded(max(size, labelFloor), .semibold, .caption1).monospacedDigit() }
    static func monoBold(_ size: CGFloat = 12) -> Font { SRType.rounded(max(size, labelFloor), .bold, .caption1).monospacedDigit() }
    /// Code: fenced blocks and inline `code` in chat. The one place a
    /// monospaced face is content rather than chrome.
    static func code(_ size: CGFloat = 13) -> Font { .custom(Face.mono, size: max(size, labelFloor), relativeTo: .caption) }

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

    var background: Color { self == .paper ? SR.paper : SR.band }
    var primary: Color { self == .paper ? SR.ink : SR.cream }
    var secondary: Color { self == .paper ? SR.inkSecondary : SR.creamOnDark }
    var muted: Color { self == .paper ? SR.inkMuted : Color(hex: SR.Fixed.paper, alpha: 0.6) }
    var accent: Color { self == .paper ? SR.accent : SR.accentOnDark }
    var counter: Color { self == .paper ? SR.accentInk : SR.accentInkOnDark }
    var good: Color { self == .paper ? SR.good : SR.goodOnDark }
    var danger: Color { self == .paper ? SR.error : SR.errorOnDark }
    var hairline: Color { self == .paper ? SR.line : SR.lineOnDark }
    var divider: Color { self == .paper ? SR.divider : Color(hex: SR.Fixed.paper, alpha: 0.12) }
}

extension Color {
    /// `0xF4F3FB` reads like the token it came from; three doubles do not.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// A token that follows the phone's appearance: `light` on a light phone,
    /// `dark` on a dark one. Backed by a dynamic `UIColor`, so UIKit's
    /// appearance proxies resolve it per trait too.
    init(light: UInt32, dark: UInt32, alpha: Double = 1) {
        self.init(uiColor: UIColor(light: light, dark: dark, alpha: alpha))
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    convenience init(light: UInt32, dark: UInt32, alpha: Double = 1) {
        let light = UIColor(hex: light, alpha: alpha)
        let dark = UIColor(hex: dark, alpha: alpha)
        self.init { $0.userInterfaceStyle == .dark ? dark : light }
    }
}

// MARK: - Dynamic Type
//
// (Prism: the ramp below is SF Pro and SF Pro Rounded through `SRType`, which
// scales through `UIFontMetrics` — the UIKit half of `relativeTo:`. The rule
// is unchanged: every size is measured against a TextStyle.)
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
        /// The one big figure on a screen. Rounded, heavy.
        static func hero(_ size: CGFloat = 34) -> Font { SRType.rounded(size, .heavy, .largeTitle) }
        /// A section's headline.
        static func display(_ size: CGFloat = 22) -> Font { SRType.rounded(size, .bold, .title2) }
        /// A row's or card's title.
        static func title(_ size: CGFloat = 17) -> Font { SRType.rounded(size, .semibold, .headline) }
        /// Reading copy. SF Pro: rounded type is for glancing, not for reading.
        static func body(_ size: CGFloat = 16) -> Font { SRType.plain(size, .regular, .body) }
        static func bodyMedium(_ size: CGFloat = 16) -> Font { SRType.plain(size, .medium, .body) }
        /// Supporting copy under a title.
        static func secondary(_ size: CGFloat = 14) -> Font { SRType.plain(size, .regular, .subheadline) }
        /// A figure. Rounded heavy with tabular digits, so a number that
        /// ticks does not shuffle the row it sits in.
        static func figure(_ size: CGFloat = 28) -> Font { SRType.rounded(size, .heavy, .title1).monospacedDigit() }
        /// The eyebrow. Never below the 12pt floor before scaling.
        static func label(_ size: CGFloat = 12) -> Font { SRType.rounded(max(size, labelFloor), .bold, .caption1) }
        /// Meta lines: times, counts, freshness. Tabular digits.
        static func mono(_ size: CGFloat = 12) -> Font { SRType.rounded(max(size, labelFloor), .medium, .caption1).monospacedDigit() }
        /// A section's title where it heads a card on its own, as on Home.
        static func sectionTitle(_ size: CGFloat = 15) -> Font { SRType.rounded(size, .bold, .subheadline) }
        /// DM Mono at the reading weight: the top bar's path, a thread's source.
        static func brand(_ size: CGFloat = 15) -> Font { .custom(Face.brand, size: size, relativeTo: .headline) }
        /// The `sr` of the mark itself: DM Mono MEDIUM. The regular cut read
        /// as a caption beside the bar's glass buttons; the mark is the one
        /// piece of type on a screen that is the brand, so it gets the weight.
        static func mark(_ size: CGFloat = SRMark.barSize) -> Font { .custom(Face.brandMedium, size: size, relativeTo: .headline) }
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
    static func onInk(_ rung: InkRung) -> Color { Color(hex: Fixed.paper, alpha: rung.rawValue) }

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

/// The system faces at an exact size that still answers the reader's text
/// setting.
///
/// `Font.system(size:)` is fixed, exactly as `Font.custom(name:size:)` is, and
/// `Font.system(.title)` scales but only at the style's own size. A bright
/// dashboard needs both — a 56pt figure that still grows — so the font is
/// built in UIKit, scaled by `UIFontMetrics` for its TextStyle, and handed to
/// SwiftUI. It is resolved when the view's body runs, so a text-size change
/// lands on the next redraw rather than mid-frame; every screen redraws on the
/// trait change that carries it.
enum SRType {
    static func rounded(_ size: CGFloat, _ weight: UIFont.Weight, _ style: UIFont.TextStyle) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let face = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: face) as CTFont)
    }

    static func plain(_ size: CGFloat, _ weight: UIFont.Weight, _ style: UIFont.TextStyle) -> Font {
        Font(UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: weight)) as CTFont)
    }

    /// The same, as a `UIFont`, for the appearance proxies.
    static func roundedUI(_ size: CGFloat, _ weight: UIFont.Weight, _ style: UIFont.TextStyle) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let face = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        return UIFontMetrics(forTextStyle: style).scaledFont(for: face)
    }
}
