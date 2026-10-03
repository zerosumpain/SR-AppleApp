import SwiftUI
import UIKit

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

    // MARK: - Palette (SR-Infra `design/tokens.json`)
    //
    // Every value comes from `SRTokens` (`Shared/SRTokens.swift`), generated
    // from the same file the website's `sr-tokens.css` is. The only literals
    // left are the app's own two, `accentDeep` and `errorOnDark`, which the
    // site has no token for. When a token moves, regenerate in SR-Infra
    // (`npm run tokens`), copy `design/dist/SRTokens.swift` over the one in
    // `Shared/`, and the app follows.
    //
    // ## Dark mode
    //
    // Every paper-register token below is a pair: the site's value for a light
    // phone, and its night value for a dark one. Since 2026-10-03 the night
    // values are the website's own (`#14100c` ground, `#e07b2a` accent,
    // `#3fa3b0` petrol), by John's decision, rather than the app's first
    // inversion. A fill of `SR.ink` carrying `SR.paper` type is cream-on-ink in
    // light and ink-on-cream in dark, and holds its contrast both ways.
    //
    // The ink BAND does not invert. It is chrome, it is dark in both modes, and
    // anything on it asks `SRRegister.ink` (or `SR.band` / `SR.cream`) for its
    // colour, never `SR.ink` / `SR.paper`. On a dark phone it goes one step
    // deeper (`--chrome-bg`), as the site's does, so it still reads as a band.
    private typealias T = SRTokens.Colour

    /// Warm cream. `--bg`. Deep warm brown in dark mode.
    static let paper = Color(uiColor: UI.paper)
    /// `--surface-elevated` — the opaque panel ground. Never a tint: `--card-bg`
    /// is 7% ink and reads as transparent the moment it sits over anything.
    static let surface = Color(token: T.surfaceElevated)
    /// `--text-primary`. Cream in dark mode. For the band's ground, `SR.band`.
    static let ink = Color(uiColor: UI.ink)
    /// `--text-secondary`.
    static let inkSecondary = Color(token: T.textSecondary)
    /// `--text-muted` — 65% ink on paper. PAPER ONLY.
    static let inkMuted = Color(uiColor: UI.inkMuted)
    /// `--text-ghost` — 45%. PAPER ONLY.
    static let inkGhost = Color(token: T.textGhost)

    /// The ink band's ground, in BOTH modes. Chrome, not page. `--chrome-bg`.
    static let band = Color(token: T.chromeBg)
    /// Cream type on the band, in BOTH modes. `--chrome-ink`.
    static let cream = Color(token: T.chromeInk)

    /// `--accent`, burnt orange. Punchy, not regal. PAPER ONLY.
    static let accent = Color(uiColor: UI.accent)
    /// The accent one step deeper, for a FILL that carries cream text — the
    /// Ask button, a selected tab's label. `--accent` under cream measures
    /// 3.5:1; this holds 5.5:1, and 4.8:1 as text on paper. Not a second
    /// accent: use it only where the accent itself would fail the text.
    /// The app's own value, not a site token. In dark mode the fill carries
    /// `SR.paper` (dark) type, so it is the night accent itself.
    static let accentDeep = Color(light: 0xA8470A, dark: T.accent.dark.hex)
    /// `--accent-on-dark`. `--accent` scores 2.6:1 on `#1a1008`, under the
    /// floor; this is its partner, not a second accent.
    static let accentOnDark = Color(token: T.accentOnDark.light)
    /// `--accent-ink`, deep petrol. The counter-accent, and PAPER ONLY — it has
    /// no role on an ink band, which is why petrol left the vitals rail.
    static let accentInk = Color(token: T.accentInk)
    /// `--accent-ink-on-dark`.
    static let accentInkOnDark = Color(token: T.accentInkOnDark.light)

    /// `--good`, olive. The one hue meaning a number is going the right way.
    /// The site keeps `--good` in its night theme, where it measures 3.0:1 on
    /// the ground, so a dark phone takes `--good-on-dark` (6.5:1) instead.
    static let good = Color(light: T.good.light.hex, dark: T.goodOnDark.dark.hex)
    /// `--good-on-dark`. Measured off the dashboard reference; the handoff's
    /// token table names #6b7f4a but every appearance of that shade is on paper.
    static let goodOnDark = Color(token: T.goodOnDark.light)

    static let warn = Color(token: T.warn)
    static let error = Color(token: T.error)
    /// Error, lifted for ink. The paper value is a smudge on `#1a1008`. The
    /// app's own value: the site has no `--error-on-dark`.
    static let errorOnDark = Color(hex: 0xE08B8B)

    /// `--card-border`.
    static let line = Color(uiColor: UI.line)
    /// `--divider`.
    static let divider = Color(token: T.divider)
    /// The hairline on an ink band. `--line-hair` is invisible there.
    static let lineOnDark = Color(token: T.onInk14.light)
    /// Cream at reading weight on ink.
    static let creamOnDark = Color(token: T.onInk70.light)

    /// The mode-following tokens UIKit's appearance proxies need as a
    /// `UIColor` — built here, once, so the proxy holds the dynamic colour
    /// itself rather than a conversion that may have resolved it.
    enum UI {
        static let paper = UIColor(token: T.bg)
        static let ink = UIColor(token: T.textPrimary)
        static let inkMuted = UIColor(token: T.textMuted)
        static let accent = UIColor(token: T.accent)
        static let line = UIColor(token: T.cardBorder)
    }

    /// The site's light values, raw. For the few surfaces that must look the
    /// same in both modes — a game's coloured tiles, a widget preview.
    enum Fixed {
        static let paper = T.bg.light.hex
        static let surface = T.surfaceElevated.light.hex
        static let ink = T.textPrimary.light.hex
        static let inkSecondary = T.textSecondary.light.hex
        static let accent = T.accent.light.hex
        static let accentInk = T.accentInk.light.hex
        static let good = T.good.light.hex
        static let warn = T.warn.light.hex
        static let error = T.error.light.hex
    }

    // MARK: - Type
    //
    // Referenced by PostScript name, not family — a family lookup with a weight
    // asks UIKit to pick, and for a three-cut family it picks wrong. The names
    // are stamped into the files by the build step that instanced DM Sans out of
    // its variable original; `Fonts/` holds the faces and their OFL licences.

    enum Face {
        /// Inter Display ExtraBold. Headlines and figures. The app's choice
        /// since 2026-10-02 — John asked for something more modern on the
        /// phone, a neo-grotesque that sits beside SF rather than fighting it —
        /// and the whole site's since 2026-10-03, when the website moved off
        /// Archivo Black to match. A static instance, so no variable-font
        /// instancing trap; licence in `Fonts/OFL-Inter.txt`.
        static let display = "InterDisplay-ExtraBold"
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
    static let gutter = CGFloat(SRTokens.Space.gutter)
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
    var muted: Color { self == .paper ? SR.inkMuted : Color(token: SRTokens.Colour.onInk55.light) }
    var accent: Color { self == .paper ? SR.accent : SR.accentOnDark }
    var counter: Color { self == .paper ? SR.accentInk : SR.accentInkOnDark }
    var good: Color { self == .paper ? SR.good : SR.goodOnDark }
    var danger: Color { self == .paper ? SR.error : SR.errorOnDark }
    var hairline: Color { self == .paper ? SR.line : SR.lineOnDark }
    var divider: Color { self == .paper ? SR.divider : Color(token: SRTokens.Colour.onInk12.light) }
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

    /// A token that follows the phone's appearance: `light` on a light phone,
    /// `dark` on a dark one. Backed by a dynamic `UIColor`, so UIKit's
    /// appearance proxies resolve it per trait too.
    init(light: UInt32, dark: UInt32, alpha: Double = 1) {
        self.init(uiColor: UIColor(light: light, dark: dark, alpha: alpha))
    }

    /// A shared token, following the phone's appearance.
    init(token: SRTokenColour) {
        self.init(uiColor: UIColor(token: token))
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

    /// A shared token, following the phone's appearance. Each side keeps its
    /// own alpha: the night ladder is not always the day one.
    convenience init(token: SRTokenColour) {
        let light = UIColor(hex: token.light.hex, alpha: token.light.alpha)
        let dark = UIColor(hex: token.dark.hex, alpha: token.dark.alpha)
        self.init { $0.userInterfaceStyle == .dark ? dark : light }
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
        /// The one big figure on a screen. Inter Display.
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
    static func onInk(_ rung: InkRung) -> Color { Color(hex: SRTokens.Colour.chromeInk.light.hex, alpha: rung.rawValue) }

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

    /// Mono kicker tracking on the band — `--tracking-kicker` of a 12pt face.
    static let inkKickerTracking = CGFloat(SRTokens.Tracking.trackingKicker * 12)
    /// Tile label tracking — `--tracking-label` of a 12pt face.
    static let inkLabelTracking = CGFloat(SRTokens.Tracking.trackingLabel * 12)
    /// Inside an ink tile. `--tile-pad`.
    static let inkTilePadding = CGFloat(SRTokens.Space.tilePad)
}
