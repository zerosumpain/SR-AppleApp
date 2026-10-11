import SwiftUI
import UIKit

/// The Strange Ramblings design system, as the app sees it.
///
/// ## The notes look (since 2026-10-11)
///
/// The app is the website's EXERCISE BOOK. Every page is cream paper ruled in
/// a faint petrol feint every 32pt, with a double red-orange margin rule down
/// the leading edge; labels are orange mono caps, headings Inter Display
/// ExtraBold, asides Fraunces italic; the numbers that matter are ringed,
/// double-underlined or tallied in seeded, hand-drawn ink; and the dense hero
/// bands are the book's ink COVER. The values below are the site's own tokens
/// (`sr-tokens.css` and the notes kit's `notes-paper.css`), copied, never
/// re-picked by eye. The marks themselves are in `SRNotes.swift`; the pen that
/// draws them, bit-identical to the site's, in `SRNotesPen.swift`.
///
/// Dark mode is the blog's NIGHT reading theme — the site's own dark notebook,
/// warm near-black paper and cream ink — rather than an inversion the app
/// invented. The ink cover, the sticky note and the drawing pin are fixed:
/// they look the same in both.
///
/// History, briefly: the app began as a literal port of the website (cream,
/// zero radius, ink bars), went to "paper under glass" for iOS 26 in October
/// 2026 (Liquid Glass panels over a cream atmosphere), and moved to notes when
/// the website did, so the phone and the site read as one book. System
/// furniture — tab bar, navigation bar, sheets, keyboard — is still the
/// system's glass, tinted; the PAGE is paper.
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
/// ## Ink is the cover, never the page
///
/// From the third round of the site rebuild, after "a little intense": a TALL
/// SOLID INK AREA READS AS INTENSITY, NOT AS EDITORIAL. In the notes look ink
/// is the book's cover — one hero band at the top of a screen (`SRInkBand`),
/// with its own faint cream feint and, edge to edge, a torn bottom edge over
/// the first page. The reading surface stays paper.
enum SR {

    // MARK: - Palette (`sr-tokens.css` `:root`, and the blog's night theme)
    //
    // ## Dark mode
    //
    // Every paper-register token below is a pair: the site's light value, and
    // its partner in the blog's NIGHT reading theme (`html[data-reading-theme=
    // night]`), which is the site's own dark notebook. Until 2026-10-11 the
    // dark partners were the app's own inversion; they now match the site, so
    // a screenshot of the phone at night and the blog at night are the same
    // inks. A fill of `SR.ink` carrying `SR.paper` type is still cream-on-ink
    // in light and ink-on-cream in dark, and holds its contrast both ways.
    //
    // The ink BAND does not invert. It is chrome, it is dark in both modes, and
    // anything on it asks `SRRegister.ink` (or `SR.band` / `SR.cream`) for its
    // colour — the fixed pair — never `SR.ink` / `SR.paper`.

    /// The page: warm cream `#ede4d4` (`--np-paper`). Night `#14100c`.
    static let paper = Color(uiColor: UI.paper)
    /// Card stock, `#f3ebdd` (`--np-card`): index cards, rows, figures. The
    /// opaque panel ground — never a tint, because `--card-bg` is 7% ink and
    /// reads as transparent the moment it sits over anything. Same value as
    /// `SR.Notes.card`; the old name stays for its call sites.
    static let surface = Color(uiColor: UI.card)
    /// `--text-primary`, the ink. Cream in dark mode. For the cover's ground,
    /// `SR.band`.
    static let ink = Color(uiColor: UI.ink)
    /// `--text-secondary`, soft ink: marginalia, ledes, excerpts.
    static let inkSecondary = Color(light: Fixed.inkSecondary, dark: 0xCDC2B2)
    /// `--text-muted` — 65% ink on paper (62% cream at night). PAPER ONLY.
    static let inkMuted = Color(uiColor: UI.inkMuted)
    /// `--text-ghost` — 45% (40% at night): faint pencil. PAPER ONLY.
    static let inkGhost = Color(light: Fixed.ink, 0.45, dark: Night.ink, 0.40)

    /// The ink band's ground, in BOTH modes. Chrome, not page.
    static let band = Color(hex: Fixed.ink)
    /// Cream type on the band, in BOTH modes.
    static let cream = Color(hex: Fixed.paper)

    /// `--accent`, the orange pen: rings, underlines, ticks, a stamp's box.
    /// Punchy, not regal. PAPER ONLY. For small orange WRITING (kickers,
    /// units) use `SR.Notes.pen`, a step darker so it holds as text.
    static let accent = Color(uiColor: UI.accent)
    /// The accent one step deeper, for a FILL that carries cream text — the
    /// Ask button, a selected tab's label. `--accent` under cream measures
    /// 3.5:1; this holds 5.5:1, and 4.8:1 as text on paper. Not a second
    /// accent: use it only where the accent itself would fail the text.
    /// In dark mode the fill carries `SR.paper` (dark) type, so it lifts.
    static let accentDeep = Color(light: 0xA8470A, dark: 0xE8863A)
    /// `--accent-on-dark`. `--accent` scores 2.6:1 on `#1a1008`, under the
    /// floor; this is its partner, not a second accent.
    static let accentOnDark = Color(hex: 0xE8863A)
    /// `--accent-ink`, the petrol pen: labels over a reading, structure,
    /// links, the second person. PAPER ONLY — on the cover it is
    /// `accentInkOnDark`.
    static let accentInk = Color(light: Fixed.accentInk, dark: 0x3FA3B0)
    /// `--accent-ink-on-dark`.
    static let accentInkOnDark = Color(hex: 0x7FB8C0)

    /// `--good`, the olive pencil. The one hue meaning a number is going the
    /// right way. Night keeps the app's lifted olive rather than the site's
    /// unchanged `#55663a`, which is a smudge on night paper.
    static let good = Color(light: Fixed.good, dark: 0x8A9A5B)
    /// `--good-on-dark`. Measured off the dashboard reference; the handoff's
    /// token table names #6b7f4a but every appearance of that shade is on paper.
    static let goodOnDark = Color(hex: 0x8A9A5B)

    static let warn = Color(light: Fixed.warn, dark: 0xD4AE4E)
    static let error = Color(light: Fixed.error, dark: 0xE08B8B)
    /// Error, lifted for ink. The paper value is a smudge on `#1a1008`.
    static let errorOnDark = Color(hex: 0xE08B8B)

    /// `--line-strong`: a card's border, a table's row line. 16% ink (20%
    /// cream at night).
    static let line = Color(uiColor: UI.line)
    /// `--divider`, the faintest rule.
    static let divider = Color(light: Fixed.ink, 0.08, dark: Night.ink, 0.10)
    /// The hairline on an ink band. `--line-hair` is invisible there.
    static let lineOnDark = Color(hex: 0xEDE4D4, alpha: 0.14)
    /// Cream at reading weight on ink.
    static let creamOnDark = Color(hex: 0xEDE4D4, alpha: 0.70)

    /// The mode-following tokens UIKit's appearance proxies need as a
    /// `UIColor` — built here, once, so the proxy holds the dynamic colour
    /// itself rather than a conversion that may have resolved it.
    enum UI {
        static let paper = UIColor(light: Fixed.paper, dark: Night.paper)
        static let card = UIColor(light: Fixed.card, dark: Night.card)
        static let ink = UIColor(light: Fixed.ink, dark: Night.ink)
        static let inkMuted = UIColor(light: Fixed.ink, 0.65, dark: Night.ink, 0.62)
        static let accent = UIColor(light: Fixed.accent, dark: Night.accent)
        static let line = UIColor(light: Fixed.ink, 0.16, dark: Night.ink, 0.20)
        /// The feint, for the ruled-paper tile (`SRNotebookPaper`), which is
        /// drawn by UIKit once per appearance.
        static let rule = UIColor(light: Fixed.accentInk, 0.16, dark: 0x7FB8C0, 0.13)
        static let marginA = UIColor(light: Fixed.accent, 0.55, dark: Night.accent, 0.50)
        static let marginB = UIColor(light: Fixed.accent, 0.35, dark: Night.accent, 0.30)
    }

    /// The site's light values, raw. For the few surfaces that must look the
    /// same in both modes — a game's coloured tiles, a widget preview.
    enum Fixed {
        static let paper: UInt32 = 0xEDE4D4
        static let surface: UInt32 = 0xE8DECE
        /// Card stock, `--surface-card`.
        static let card: UInt32 = 0xF3EBDD
        static let ink: UInt32 = 0x1A1008
        static let inkSecondary: UInt32 = 0x3D2E1A
        static let accent: UInt32 = 0xC4570A
        static let accentInk: UInt32 = 0x0E5B66
        static let good: UInt32 = 0x55663A
        static let warn: UInt32 = 0xB0892A
        static let error: UInt32 = 0xCC4444
    }

    /// The blog's night reading theme, raw: the dark partners above.
    enum Night {
        static let paper: UInt32 = 0x14100C
        static let card: UInt32 = 0x1E1913
        static let ink: UInt32 = 0xECE3D6
        static let accent: UInt32 = 0xE07B2A
    }

    // MARK: - Type
    //
    // Referenced by PostScript name, not family — a family lookup with a weight
    // asks UIKit to pick, and for a three-cut family it picks wrong. The names
    // are stamped into the files by the build step that instanced DM Sans out of
    // its variable original; `Fonts/` holds the faces and their OFL licences.

    enum Face {
        /// Inter Display ExtraBold. Headlines and figures. The app's own
        /// choice since 2026-10-02, not the site's: the website keeps Archivo
        /// Black, and John asked for something more modern on the phone — a
        /// neo-grotesque in the Arial/Helvetica family that sits beside SF
        /// rather than fighting it. A static instance, so no variable-font
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
        /// Fraunces, upright. Contents excerpts, a story's opening lines.
        /// Static instances at wght 400 and opsz 17 — the site sets Fraunces
        /// with `font-optical-sizing: auto` and its marginalia are 15–18px, so
        /// one cut at 17 is what the reader actually sees there. Licence in
        /// `Fonts/OFL-Fraunces.txt`.
        static let serif = "Fraunces-Regular"
        /// Fraunces Italic: the notes look's marginalia — asides, straps, an
        /// empty page's line. Already italic: never add `.italic()` to it.
        static let serifItalic = "Fraunces-Italic"
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
    // Paper is sharp: cards take `SR.Glass.radius` (3, a cut card's corner) and
    // nothing in the notes look goes softer than that except a pill or a dot.
    // There are no shadows either, except the sticky slip's lift and the torn
    // cover's shade — paper on paper, not elevation.
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
    /// Mono label tracking. The notes kicker runs 0.14em of 12pt —
    /// `SR.Notes.kickerTracking`, 1.68 — and this older 1.6 is close enough
    /// that the call sites still using it read as the same voice.
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

    /// A token that follows the phone's appearance: `light` on a light phone,
    /// `dark` on a dark one. Backed by a dynamic `UIColor`, so UIKit's
    /// appearance proxies resolve it per trait too.
    init(light: UInt32, dark: UInt32, alpha: Double = 1) {
        self.init(uiColor: UIColor(light: light, dark: dark, alpha: alpha))
    }

    /// The same, with its own alpha in each mode: the night theme sets its
    /// muted inks and feints at different strengths from the day's
    /// (`rgba(236,227,214,.62)` against `rgba(26,16,8,.65)`).
    init(light: UInt32, _ lightAlpha: Double, dark: UInt32, _ darkAlpha: Double) {
        self.init(uiColor: UIColor(light: light, lightAlpha, dark: dark, darkAlpha))
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

    convenience init(light: UInt32, _ lightAlpha: Double, dark: UInt32, _ darkAlpha: Double) {
        let light = UIColor(hex: light, alpha: lightAlpha)
        let dark = UIColor(hex: dark, alpha: darkAlpha)
        self.init { $0.userInterfaceStyle == .dark ? dark : light }
    }
}

// MARK: - The notes kit's own tokens (`notes-paper.css`)
//
// Light is the kit's `.np-paper`, dark the blog's night theme. Everything the
// marks in `SRNotes.swift` draw with comes from here or from the base palette.
extension SR {
    enum Notes {
        /// The desk the paper lies on, seen past its edges. `#e0d4bf`.
        static let desk = Color(light: 0xE0D4BF, dark: 0x0E0B08)
        /// Card stock: index cards, list rows, figures, code. `#f3ebdd`.
        static let card = Color(uiColor: UI.card)
        /// The feint: petrol at 16% (`--np-rule`), one 1pt line every 32pt.
        static let rule = Color(uiColor: UI.rule)
        /// The feint made opaque, for a block that paints its own band of
        /// paper over the sheet so the rule is not doubled. `#c9cec2`.
        static let ruleSolid = Color(light: 0xC9CEC2, dark: 0x222623)
        /// The margin rule's stronger, left line.
        static let marginA = Color(uiColor: UI.marginA)
        /// The margin rule's fainter, right line.
        static let marginB = Color(uiColor: UI.marginB)
        /// The orange that WRITES: kickers, units, "more" links, a stamp's
        /// date (`--accent-hover`, `#a84808`). `SR.accent` is the orange that
        /// DRAWS; at 12pt it is a shade too light to hold as text on cream.
        static let pen = Color(light: 0xA84808, dark: Night.accent)
        /// The ochre pencil, the fourth of the pencil-dot colours.
        static let ochre = Color(light: 0x8C6A12, dark: 0xC9A445)
        /// Masking tape.
        static let tape = Color(light: 0xD6C4A0, 0.72, dark: 0xECE3D6, 0.16)
        /// Graph paper, every 80pt and every 16pt.
        static let graphMajor = Color(light: Fixed.accentInk, 0.14, dark: 0x7FB8C0, 0.14)
        static let graphMinor = Color(light: Fixed.accentInk, 0.06, dark: 0x7FB8C0, 0.06)
        /// The red pencil (`--status-fail`): a low recovery, a refused idea.
        static let redPencil = Color(light: 0xB3261E, dark: 0xE08B8B)

        /// The sticky note, in BOTH modes: a note stuck on the page is the
        /// same paper at night. Ink on it is `stickyInk`, never `SR.ink`.
        static let stickyTop = Color(hex: 0xF7D9B4)
        static let stickyBottom = Color(hex: 0xF2C99A)
        static let stickyInk = Color(hex: 0x1A1008)
        /// The drawing pin's three stops, in both modes.
        static let pinLight = Color(hex: 0xF6B37A)
        static let pinMid = Color(hex: 0xE8863A)
        static let pinDark = Color(hex: 0xB2561A)

        /// The rule pitch: every line of the page is 32pt apart.
        static let pitch: CGFloat = 32
        /// Where the feint sits in each pitch, from its top: just under a
        /// 16pt line's baseline, as the landing's pages rule it.
        static let ruleY: CGFloat = 23
        /// The margin rule's two lines, from the page's leading edge. Both
        /// inside the 20pt gutter, so no row or heading text ever crosses them.
        static let marginX: (a: CGFloat, b: CGFloat) = (11, 14)
        /// The kicker's tracking: 0.14em of 12pt.
        static let kickerTracking: CGFloat = 1.68
        /// A stamp's tracking: 0.16em of 12pt.
        static let stampTracking: CGFloat = 1.92

        /// The four pencils, in `pencilIndex` order: orange, petrol, olive,
        /// ochre.
        static let pencils: [Color] = [SR.accent, SR.accentInk, SR.good, ochre]
        /// The pencil a word always gets (`pencilFor` on the site).
        static func pencil(for word: String) -> Color { pencils[pencilIndex(word)] }
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
        /// A section's title where it heads a card on its own, as on Today:
        /// the mono eyebrow, a step larger and bold.
        static func sectionTitle(_ size: CGFloat = 15) -> Font { .custom(Face.monoBold, size: size, relativeTo: .subheadline) }
        /// DM Mono at the reading weight: the top bar's path, a thread's source.
        static func brand(_ size: CGFloat = 15) -> Font { .custom(Face.brand, size: size, relativeTo: .headline) }
        /// The `sr` of the mark itself: DM Mono MEDIUM. The regular cut read
        /// as a caption beside the bar's glass buttons; the mark is the one
        /// piece of type on a screen that is the brand, so it gets the weight.
        static func mark(_ size: CGFloat = SRMark.barSize) -> Font { .custom(Face.brandMedium, size: size, relativeTo: .headline) }
        /// Marginalia: Fraunces italic, in a softer ink (`SR.inkSecondary`).
        /// Asides, straps, captions that are commentary, an empty page's
        /// "nothing here yet". The site writes these with a lower-case first
        /// letter; that is a COPY rule for new words, not a reason to rewrite
        /// old ones.
        static func marginalia(_ size: CGFloat = 16) -> Font { .custom(Face.serifItalic, size: size, relativeTo: .body) }
        /// Fraunces upright: contents excerpts, a lede set as reading copy.
        static func serif(_ size: CGFloat = 17) -> Font { .custom(Face.serif, size: size, relativeTo: .body) }
        /// A kicker or a label: JetBrains Mono at 12, set in caps and tracked
        /// `SR.Notes.kickerTracking` by the caller (`SRSectionLabel` does).
        static func kicker(_ size: CGFloat = 12) -> Font { .custom(Face.mono, size: max(size, labelFloor), relativeTo: .caption) }
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
