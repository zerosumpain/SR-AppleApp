import SwiftUI
import UIKit

/// The notes look's marks: everything the site draws in hand-wobbled ink.
///
/// ## Notes look: how to use the marks
///
/// The website's pages are an exercise book, and its numbers are marked up the
/// way a person marks up a page: the figure that matters is RINGED, a total is
/// DOUBLE-UNDERLINED, a count is TALLIED in five-bar gates, a date is STAMPED,
/// a tag gets a coloured PENCIL DOT. This file is those marks for SwiftUI. The
/// strokes come from `SRNotesPen.swift`, which is the site's pen ported bit for
/// bit, so a mark drawn here with seed 31 is the mark the site draws with 31.
///
/// The rules every mark follows, so a screen can use them without thinking:
///
/// - **A mark never carries meaning.** Every one is `accessibilityHidden`; the
///   figure or word beside it says what it says. A ringed "12" reads "12".
/// - **A mark never moves layout.** Rings and underlines are overlays
///   (`.srInkRing()`, `.srInkUnderline()`), sized from the view they mark and
///   drawn outside it. Leave room — a ring reaches `pad` points either side
///   and a third of the text's height above and below; an underline hangs
///   about 10pt under the text's foot.
/// - **Strokes do not scale.** A mark's path is built in its own viewBox
///   (120 × 80 for a ring, as on the site), stretched to the frame, and only
///   THEN stroked, so a ring round a wide figure is a wide loop in a 2pt line,
///   not a 2pt line stretched into a smear.
/// - **Ink draws in once.** A ring or an underline draws itself over 820ms the
///   first time it appears (`.timingCurve(0.3, 0.7, 0.2, 1)`, the site's
///   curve), never again on a refresh, and not at all under Reduce Motion.
///   Figures do not count up. Pass `animated: false` for a mark inside a row
///   that scrolls in and out, where a replay would read as a flicker.
/// - **Tones are the pens.** `SR.accent` (orange, the default), `SR.accentInk`
///   (petrol), `SR.good` (olive), `SR.Notes.ochre`, `SR.ink`. On the ink
///   cover, `SR.accentOnDark` / `SR.accentInkOnDark` / `SR.onInk(.note)`.
///
/// The list, with exact signatures, is in the notes-look MARKS-API file the
/// build agents work from; in brief: `SRInkRing`, `SRInkLoop`,
/// `SRInkUnderline`, `SRInkBox`, `SRInkTick`, `SRInkArrow` (Shapes);
/// `SRTally`, `SRDateStamp`, `SRPencilDot`, `SREndMark`, `SRTornEdge`, `SRPin`,
/// `SRTape`, `SRDottedLeader`, `SRScribbles`, `SRMoonDoodle`, `SRGraphPaper`,
/// `SRNoteLabel`, `SRFigure` (Views); `.srInkRing`, `.srInkUnderline`,
/// `.srStickyNote`, `.srGraphPaper`, `.srTaped`, `.srPinned` (modifiers).

// MARK: - Paths from strokes

extension Path {
    /// The pen's strokes as one path, in the strokes' own units.
    init(ink strokes: [InkStroke]) {
        self.init()
        for stroke in strokes { addInk(stroke) }
    }

    /// Adds one pen stroke: the nib goes down at its start, then follows it.
    mutating func addInk(_ stroke: InkStroke) {
        move(to: stroke.start)
        for piece in stroke.pieces {
            switch piece {
            case .line(let to):
                addLine(to: to)
            case .curve(let c1, let c2, let to):
                addCurve(to: to, control1: c1, control2: c2)
            }
        }
    }
}

/// The pen with SwiftUI paths, in the shape the site's `notes-ink.ts` has, for
/// a screen that draws its own figure (a Canvas, a chart's annotation).
/// Each draws from the generator it is handed, so several marks can share one
/// seed in the site's order.
enum Ink {
    static func smooth(_ p: [CGPoint], into path: inout Path) {
        path.addInk(InkGeometry.smooth(p))
    }

    static func line(_ r: inout InkRNG, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                     amp: Double = 0.6, bow: Double = 0.015, into path: inout Path) {
        path.addInk(InkGeometry.line(&r, x1, y1, x2, y2, amp: amp, bow: bow))
    }

    static func ring(_ r: inout InkRNG, cx: Double, cy: Double, rx: Double, ry: Double,
                     turns: Double = 1.1, wob: Double = 0.045, into path: inout Path) {
        path.addInk(InkGeometry.ring(&r, cx: cx, cy: cy, rx: rx, ry: ry, turns: turns, wob: wob))
    }

    static func box(_ r: inout InkRNG, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                    amp: Double = 0.6, into path: inout Path) {
        for stroke in InkGeometry.box(&r, x, y, w, h, amp: amp) { path.addInk(stroke) }
    }

    static func tick(_ r: inout InkRNG, _ x: Double, _ y: Double, s: Double = 14, into path: inout Path) {
        path.addInk(InkGeometry.tick(&r, x, y, s: s))
    }

    static func arrow(_ r: inout InkRNG, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                      bow: Double = 0.18, into path: inout Path) {
        let arrow = InkGeometry.arrow(&r, x1, y1, x2, y2, bow: bow)
        path.addInk(arrow.shaft)
        for wing in arrow.head { path.addInk(wing) }
    }

    static let gatePitch = InkGeometry.gatePitch

    /// Five-bar gates in a `w` × `h` box, in points.
    static func tally(count: Int, w: Double, h: Double, seed: Int) -> (path: Path, more: Int, moreX: Double) {
        let tally = InkGeometry.tally(count: count, w: w, h: h, seed: seed)
        return (Path(ink: tally.strokes), tally.more, tally.moreX)
    }
}

/// The round stroke every pen mark uses.
extension StrokeStyle {
    static func ink(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

// MARK: - Shapes

/// A path drawn in a viewBox, stretched to whatever frame it is given.
///
/// The site's SVGs use `preserveAspectRatio="none"` and a non-scaling stroke;
/// this is that. Stroke it AFTER it is placed (`.stroke(_:style:)`) so the line
/// keeps its width however far the box is stretched.
struct SRInkPath: Shape {
    var ink: Path
    var viewBox: CGSize

    func path(in rect: CGRect) -> Path {
        guard viewBox.width > 0, viewBox.height > 0 else { return Path() }
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / viewBox.width, y: rect.height / viewBox.height)
        return ink.applying(transform)
    }
}

/// The ink ring round a figure (`InkRing.svelte`): a loop a little over one
/// turn in a 120 × 80 viewBox, stretched to the frame. Seed 31 is the site's.
struct SRInkRing: Shape {
    var seed: Int = 31

    func path(in rect: CGRect) -> Path {
        var r = InkRNG(seed)
        let ring = InkGeometry.ring(&r, cx: 60, cy: 40, rx: 56, ry: 35, turns: 1.12, wob: 0.04)
        return SRInkPath(ink: Path(ink: [ring]), viewBox: CGSize(width: 120, height: 80)).path(in: rect)
    }
}

/// A round hand-drawn loop, for an icon or a donut rather than a figure: the
/// pen's ring in a square 100 × 100 viewBox, kept a little inside its frame
/// so the overshoot is not clipped.
struct SRInkLoop: Shape {
    var seed: Int = 23
    var turns: Double = 1.08
    var wobble: Double = 0.03

    func path(in rect: CGRect) -> Path {
        var r = InkRNG(seed)
        let ring = InkGeometry.ring(&r, cx: 50, cy: 50, rx: 44, ry: 44, turns: turns, wob: wobble)
        return SRInkPath(ink: Path(ink: [ring]), viewBox: CGSize(width: 100, height: 100)).path(in: rect)
    }
}

/// The double underline a total gets: two strokes in a 100 × 12 viewBox, the
/// second shorter and inset. Seeds `seed` and `seed + 1`.
struct SRInkUnderline: Shape {
    var seed: Int = 5

    func path(in rect: CGRect) -> Path {
        SRInkPath(ink: Path(ink: InkGeometry.underline(seed: seed)), viewBox: CGSize(width: 100, height: 12)).path(in: rect)
    }
}

/// A box drawn by hand round its frame, in POINTS rather than a viewBox, so a
/// wide button's box wobbles as much as a narrow one's. `inset` keeps the
/// stroke inside the frame.
struct SRInkBox: Shape {
    var seed: Int = 43
    var amp: Double = 0.6
    var inset: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: inset, dy: inset)
        guard box.width > 0, box.height > 0 else { return Path() }
        var r = InkRNG(seed)
        return Path(ink: InkGeometry.box(&r, Double(box.minX), Double(box.minY), Double(box.width), Double(box.height), amp: amp))
    }
}

/// The date stamp's box: four strokes in a 100 × 40 viewBox, each from its own
/// generator, stretched to the stamp. Seed 43 is the site's.
struct SRStampBox: Shape {
    var seed: Int = 43

    func path(in rect: CGRect) -> Path {
        SRInkPath(ink: Path(ink: InkGeometry.stampBox(seed: seed)), viewBox: CGSize(width: 100, height: 40)).path(in: rect)
    }
}

/// A tick: a short down-stroke and a long up-stroke, in a 22 × 22 viewBox (the
/// checklist's box). Stroke it 2.4 in orange, as the site does.
struct SRInkTick: Shape {
    var seed: Int = 9

    func path(in rect: CGRect) -> Path {
        var r = InkRNG(seed)
        let tick = InkGeometry.tick(&r, 3, 2, s: 17)
        return SRInkPath(ink: Path(ink: [tick]), viewBox: CGSize(width: 22, height: 22)).path(in: rect)
    }
}

/// A hand-drawn arrow, bowed, with a two-stroke head. Defaults are the site's
/// first coda arrow: seed 401 in a 64 × 50 box from (6, 6) to (58, 44).
/// A negative `bow` bends it the other way.
struct SRInkArrow: Shape {
    var seed: Int = 401
    var from: CGPoint = CGPoint(x: 6, y: 6)
    var to: CGPoint = CGPoint(x: 58, y: 44)
    var bow: Double = 0.32
    var viewBox: CGSize = CGSize(width: 64, height: 50)

    func path(in rect: CGRect) -> Path {
        var r = InkRNG(seed)
        let arrow = InkGeometry.arrow(&r, Double(from.x), Double(from.y), Double(to.x), Double(to.y), bow: bow)
        return SRInkPath(ink: Path(ink: [arrow.shaft] + arrow.head), viewBox: viewBox).path(in: rect)
    }
}

/// The cover's torn bottom edge: ink teeth hanging down, 12 wide and 6 deep,
/// the first apex at x = 6. Fill it; it draws past its frame on the right only
/// to finish the last tooth, so clip it.
struct SRTornTeeth: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        var x = rect.minX
        while x < rect.maxX {
            path.addLine(to: CGPoint(x: x + 6, y: rect.minY + 6))
            path.addLine(to: CGPoint(x: x + 12, y: rect.minY))
            x += 12
        }
        path.closeSubpath()
        return path
    }
}

/// Dots of 1pt radius every 9pt along the middle of the frame: the contents
/// row's leader from a title to its number.
struct SRLeaderDots: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX + 4.5
        while x + 1 <= rect.maxX {
            path.addEllipse(in: CGRect(x: x - 1, y: rect.midY - 1, width: 2, height: 2))
            x += 9
        }
        return path
    }
}

// MARK: - Drawing in

/// A pen mark stroked in its tone, drawing itself in the first time it is
/// seen. Every animated mark goes through here, so the motion rules live in
/// one place: 820ms on the site's curve, once, and never under Reduce Motion.
struct SRInkStroke<S: Shape>: View {
    let shape: S
    var tone: Color = SR.accent
    var lineWidth: CGFloat = 2
    var animated: Bool = true
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        shape
            .trim(from: 0, to: (drawn || !animated || reduceMotion) ? 1 : 0)
            .stroke(tone, style: .ink(lineWidth))
            .onAppear {
                guard animated, !reduceMotion, !drawn else { return }
                withAnimation(.timingCurve(0.3, 0.7, 0.2, 1, duration: 0.82).delay(delay)) { drawn = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Ring this view in ink, the way the site rings the figure that matters.
    ///
    /// An overlay: the ring is sized from the view (wider by `pad` each side,
    /// about a third taller) and does not move layout, so leave it room.
    ///
    /// `visible: false` leaves the view unmarked, for a list where only one
    /// figure is ringed.
    func srInkRing(tone: Color = SR.accent, seed: Int = 31, pad: CGFloat = 8,
                   lineWidth: CGFloat = 2, animated: Bool = true, visible: Bool = true) -> some View {
        overlay {
            if visible {
                GeometryReader { geometry in
                    SRInkStroke(shape: SRInkRing(seed: seed), tone: tone, lineWidth: lineWidth, animated: animated)
                        .frame(width: geometry.size.width + pad * 2, height: geometry.size.height * 1.32)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                .allowsHitTesting(false)
            }
        }
    }

    /// Double-underline this view in ink, as a total is underlined.
    ///
    /// Hangs just under the text's foot: the strokes start a little above the
    /// bottom of the text's box (in the descender's room) and reach about
    /// 10pt below it. Use `lineWidth: 2.6` on a headline figure, as the site
    /// does; the strip deepens to match.
    func srInkUnderline(seed: Int = 5, tone: Color = SR.accent, lineWidth: CGFloat = 2,
                        animated: Bool = true) -> some View {
        let heavy = lineWidth > 2.2
        let depth: CGFloat = heavy ? 14 : 12
        let reach: CGFloat = heavy ? 3 : 2
        return overlay {
            GeometryReader { geometry in
                SRInkStroke(shape: SRInkUnderline(seed: seed), tone: tone, lineWidth: lineWidth, animated: animated)
                    .frame(width: geometry.size.width + reach * 2, height: depth)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.85 + depth / 2)
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Tally

/// A count in five-bar gates (`inkTally`): four uprights and a slash a gate,
/// 15pt a gate, and "+n" in mono when the gates do not all fit `maxWidth`.
///
/// Decorative like every mark: put the number beside it, or give the parent an
/// accessibility label (`SRMeter` does).
struct SRTally: View {
    let count: Int
    var height: CGFloat = 16
    var tone: Color = SR.ink
    var seed: Int = 7
    /// Room for the gates. `nil` draws every gate, one pitch each.
    var maxWidth: CGFloat? = nil
    var lineWidth: CGFloat = 1.5
    /// The "+n" when the gates do not fit.
    var moreTone: Color = SR.Notes.pen

    var body: some View {
        let natural = CGFloat(InkGeometry.tallyWidth(count: count))
        let room = max(CGFloat(InkGeometry.gatePitch), min(natural, maxWidth ?? natural))
        let tally = InkGeometry.tally(count: count, w: Double(room), h: Double(height), seed: seed)
        let drawn = tally.more > 0 ? CGFloat(tally.moreX) : room
        HStack(alignment: .center, spacing: 2) {
            if drawn > 0 {
                SRInkPath(ink: Path(ink: tally.strokes), viewBox: CGSize(width: drawn, height: height))
                    .stroke(tone, style: .ink(lineWidth))
                    .frame(width: drawn, height: height)
            }
            if tally.more > 0 {
                Text("+\(tally.more)")
                    .font(SR.Text.mono(13))
                    .foregroundStyle(moreTone)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Stamps, dots and small marks

/// The date stamp (`DateStamp.svelte`): a hand-drawn box at 75%, the date in
/// Inter ExtraBold caps in the writing orange, an optional mono sub-line (the
/// weekday, a place), tilted. On ruled paper it carries its own paper so the
/// rules do not cross it.
///
/// The text is read by VoiceOver; the box is not.
struct SRDateStamp: View {
    let text: String
    var sub: String? = nil
    var tilt: Double = -4
    var seed: Int = 43
    /// `.ink` for a stamp on the cover: orange-on-dark, box at 70%, ink ground.
    var register: SRRegister = .paper
    /// What the stamp is pressed onto. It paints its ground so the feint does
    /// not run through the box; on a card or a row that ground is card
    /// stock, and the page's paper there would show as a darker patch. Nil
    /// for the register's own ground: paper, or the cover's ink.
    var ground: Color? = nil
    /// The Wildmind map's stamp: the first line in mono 15 (medium, the
    /// nearest cut to the site's 600) tracked .16em, rather than the page
    /// stamp's Inter ExtraBold 16.
    var mono: Bool = false

    var body: some View {
        let onInk = register == .ink
        let ink = onInk ? SR.accentOnDark : SR.Notes.pen
        VStack(spacing: 1) {
            Text(text.uppercased())
                .font(mono ? SR.Text.label(15) : SR.Text.display(16))
                .tracking(mono ? 15 * 0.16 : 0.32)
                .foregroundStyle(ink)
                .lineLimit(1)
                .fixedSize()
            if let sub {
                Text(sub.uppercased())
                    .font(SR.Text.kicker())
                    .tracking(SR.Notes.stampTracking)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.top, 5)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .background(ground ?? (onInk ? SR.band : SR.paper))
        .overlay {
            SRStampBox(seed: seed)
                .stroke((onInk ? SR.accentOnDark : SR.accent).opacity(onInk ? 0.7 : 0.75), style: .ink(1.5))
                .accessibilityHidden(true)
        }
        .rotationEffect(.degrees(tilt))
        .accessibilityElement(children: .combine)
    }
}

/// A word's pencil dot (`PencilDot.svelte`): a filled dot and a looser ring in
/// the pencil the word always gets — orange, petrol, olive or ochre, by an
/// FNV-1a hash of the word, so a tag is the same colour everywhere.
struct SRPencilDot: View {
    let word: String
    var size: CGFloat = 12

    var body: some View {
        let tone = SR.Notes.pencil(for: word)
        var r = InkRNG(seedFor(word))
        let ring = InkGeometry.ring(&r, cx: 7, cy: 7, rx: 5.6, ry: 5.2, turns: 1.15, wob: 0.08)
        let box = CGSize(width: 14, height: 14)
        return ZStack {
            SRInkPath(ink: Path(ellipseIn: CGRect(x: 3.4, y: 3.4, width: 7.2, height: 7.2)), viewBox: box)
                .fill(tone.opacity(0.85))
            SRInkPath(ink: Path(ink: [ring]), viewBox: box)
                .stroke(tone, style: .ink(1.2))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The end mark (`EndMark.svelte`): a dot inside a loose ring, centred on two
/// rules at the end of a piece. 28 × 28, orange pen.
struct SREndMark: View {
    var seed: Int = 71
    var tone: Color = SR.accent

    var body: some View {
        var r = InkRNG(seed)
        let ring = InkGeometry.ring(&r, cx: 14, cy: 14, rx: 9, ry: 8.5, turns: 1.18, wob: 0.06)
        let box = CGSize(width: 28, height: 28)
        return ZStack {
            SRInkPath(ink: Path(ellipseIn: CGRect(x: 11, y: 11, width: 6, height: 6)), viewBox: box)
                .fill(tone)
            SRInkPath(ink: Path(ink: [ring]), viewBox: box)
                .stroke(tone, style: .ink(1.6))
        }
        .frame(width: 28, height: 28)
        .frame(maxWidth: .infinity, minHeight: SR.Notes.pitch * 2)
        .accessibilityHidden(true)
    }
}

/// The ink cover's torn bottom edge over the first page: the teeth, and under
/// them the shade where the cover lifts (18% ink fading out over 26pt). Put it
/// directly under a cover, at the cover's width.
struct SRTornEdge: View {
    /// The cover's ink. `SR.band` in both modes, as the site forces it.
    var ink: Color = SR.band
    /// The lift's shade under the teeth. Off, the strip is only the 6pt teeth.
    var shade: Bool = true

    var body: some View {
        ZStack(alignment: .top) {
            if shade {
                LinearGradient(colors: [Color(hex: 0x1A1008, alpha: 0.18), Color(hex: 0x1A1008, alpha: 0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 26)
            }
            SRTornTeeth()
                .fill(ink)
                .frame(height: 6)
        }
        .frame(maxWidth: .infinity, minHeight: shade ? 26 : 6, maxHeight: shade ? 26 : 6, alignment: .top)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A drawing pin: a 13pt head lit from the top left.
struct SRPin: View {
    var size: CGFloat = 13

    var body: some View {
        // `radial-gradient(circle at 35% 35%, #f6b37a 0 2px, #e8863a 3px,
        // #b2561a 100%)`: the gradient runs to the farthest corner, 0.92 of
        // the size from that centre, so the 2px and 3px stops are fractions
        // of that.
        let reach = size * 0.919
        Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: SR.Notes.pinLight, location: 0),
                    .init(color: SR.Notes.pinLight, location: 2 / reach),
                    .init(color: SR.Notes.pinMid, location: 3 / reach),
                    .init(color: SR.Notes.pinDark, location: 1),
                ],
                center: UnitPoint(x: 0.35, y: 0.35),
                startRadius: 0,
                endRadius: reach
            ))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A strip of masking tape, 22pt deep, tilted −2°.
struct SRTape: View {
    var width: CGFloat = 120
    var height: CGFloat = 22
    var tilt: Double = -2

    var body: some View {
        Rectangle()
            .fill(SR.Notes.tape)
            .frame(width: width, height: height)
            .rotationEffect(.degrees(tilt))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The contents row's dotted leader: muted dots every 9pt, 4pt tall, filling
/// the width it is given.
struct SRDottedLeader: View {
    var tone: Color = SR.inkMuted

    var body: some View {
        SRLeaderDots()
            .fill(tone.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 4, maxHeight: 4)
            .accessibilityHidden(true)
    }
}

/// Struck-out claims (`scribbles`): one cursive scribble per claim, each
/// crossed through with an orange zigzag — the ideas a referee turned down.
/// Up to `max` rows, 18pt apart, in a 170pt column. Say the count beside it
/// ("× 4" in Inter ExtraBold, `SR.Notes.pen`).
struct SRScribbles: View {
    let count: Int
    var max: Int = 5
    var seed: Int = 61

    var body: some View {
        let shown = Swift.min(Swift.max(count, 0), max)
        let marks = InkGeometry.scribbles(count, max: max, seed: seed)
        let box = CGSize(width: 170, height: CGFloat(shown) * 18 + 2)
        return ZStack {
            SRInkPath(ink: Path(ink: marks.lines), viewBox: box)
                .stroke(SR.ink.opacity(0.55), style: .ink(1.3))
            SRInkPath(ink: Path(ink: marks.strikes), viewBox: box)
                .stroke(SR.accent, style: .ink(2))
        }
        .frame(width: box.width, height: box.height)
        .accessibilityHidden(true)
    }
}

/// The crescent moon doodle and three cross stars (80 × 64): petrol outline
/// at 1.8 with a 14% petrol wash, orange stars. For a night on the page.
struct SRMoonDoodle: View {
    var seed: Int = 171
    var width: CGFloat = 80

    var body: some View {
        let moon = InkGeometry.moon(seed: seed)
        let box = CGSize(width: 80, height: 64)
        return ZStack {
            SRInkPath(ink: Path(ink: [moon.body]), viewBox: box)
                .fill(SR.accentInk.opacity(0.14))
            SRInkPath(ink: Path(ink: [moon.body]), viewBox: box)
                .stroke(SR.accentInk, style: .ink(1.8))
            SRInkPath(ink: Path(ink: moon.stars), viewBox: box)
                .stroke(SR.accent, style: .ink(1.4))
        }
        .frame(width: width, height: width * 0.8)
        .accessibilityHidden(true)
    }
}

/// Graph paper (`.np-graph`): card stock with a petrol grid, faint every 16pt
/// and stronger every 80pt. Drawn once per size, not per frame — it is a
/// bounded inset behind a chart, never a page.
struct SRGraphPaper: View {
    var body: some View {
        Canvas { context, size in
            for (step, tone) in [(CGFloat(16), SR.Notes.graphMinor), (CGFloat(80), SR.Notes.graphMajor)] {
                var lines = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    lines.addRect(CGRect(x: x, y: 0, width: 1, height: size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y <= size.height {
                    lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                    y += step
                }
                context.fill(lines, with: .color(tone))
            }
        }
        .background(SR.Notes.card)
        .accessibilityHidden(true)
    }
}

// MARK: - Paper furniture as modifiers

extension View {
    /// A sticky note: the warm gradient, ink type, a −2.2° tilt, no shadow.
    /// The note is the same paper at night, so everything on it is resolved in
    /// the light palette — `SR.ink` on it is the day's ink, not night cream.
    func srStickyNote(tilt: Double = -2.2) -> some View {
        self
            .padding(EdgeInsets(top: 18, leading: 18, bottom: 22, trailing: 18))
            .foregroundStyle(SR.Notes.stickyInk)
            .background(
                LinearGradient(colors: [SR.Notes.stickyTop, SR.Notes.stickyBottom],
                               startPoint: UnitPoint(x: 0.33, y: 0.03),
                               endPoint: UnitPoint(x: 0.67, y: 0.97))
            )
            .environment(\.colorScheme, .light)
            .rotationEffect(.degrees(tilt))
    }

    /// Lay this view on graph paper, with the inset's petrol border.
    func srGraphPaper() -> some View {
        self
            .background { SRGraphPaper() }
            .overlay { Rectangle().stroke(SR.accentInk.opacity(0.3), lineWidth: 1) }
    }

    /// A strip of masking tape across the top edge, centred, half on and half
    /// off.
    func srTaped(width: CGFloat = 120, tilt: Double = -2) -> some View {
        overlay(alignment: .top) {
            SRTape(width: width, tilt: tilt).offset(y: -11)
        }
    }

    /// A drawing pin at the top centre, as an index card is pinned.
    func srPinned() -> some View {
        overlay(alignment: .top) {
            SRPin().offset(y: -6)
        }
    }
}

// MARK: - Type marks

/// A label over a reading or a chart (`.np-label`): mono caps, 0.14em, in the
/// petrol pen. The kicker's sibling — a kicker names a section, a label names
/// a figure.
struct SRNoteLabel: View {
    let text: String
    var register: SRRegister = .paper

    var body: some View {
        Text(text.uppercased())
            .font(SR.Text.kicker())
            .tracking(SR.Notes.kickerTracking)
            .foregroundStyle(register == .ink ? SR.accentInkOnDark : SR.accentInk)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A reading: the figure in Inter ExtraBold, tabular, tight, with its unit in
/// mono caps in the writing orange beside its feet.
///
/// A missing number is not 0. It is a Fraunces em dash in muted ink, and
/// VoiceOver hears `missing` ("no reading yet" unless the screen says better).
struct SRFigure: View {
    let value: String?
    var unit: String? = nil
    var size: CGFloat = 28
    /// What VoiceOver says when there is no value.
    var missing: String = "no reading yet"
    var register: SRRegister = .paper

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let value {
                Text(value)
                    .font(SR.Text.figure(size))
                    .tracking(-size * 0.03)
                    .monospacedDigit()
                    .foregroundStyle(register.primary)
                    .lineLimit(1)
            } else {
                Text("\u{2014}")
                    .font(SR.Text.serif(size * 0.8))
                    .foregroundStyle(register.muted)
            }
            if let unit {
                Text(unit.uppercased())
                    .font(SR.Text.kicker())
                    .tracking(SR.Notes.kickerTracking)
                    .foregroundStyle(register == .ink ? SR.accentOnDark : SR.Notes.pen)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { [$0, unit].compactMap { $0 }.joined(separator: " ") } ?? missing)
    }
}
