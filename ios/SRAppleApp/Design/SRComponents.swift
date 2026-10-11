import SwiftUI

/// The masthead every section opens with.
///
/// Began as a port of `src/lib/components/shell/SectionHead.svelte` (a lettered
/// mono kicker over an uppercase headline). In the notes look it is the page
/// head `SRPageHeader` draws: the kicker in the writing orange, the headline in
/// Inter ExtraBold at 34 in SENTENCE case — the site's notes pages never shout
/// — and the standfirst as Fraunces italic marginalia.
///
/// The headline arrives as an ARRAY OF LINES, exactly as it does on the web, and
/// for the same reason — where "EIGHT ANALYTICS / ALREADY RUNNING" folds is a
/// typographic decision, not something to leave to the width of a phone. On a
/// 390pt screen that matters more than it does on the desk, not less.
struct SectionHead: View {
    /// `C / FORECAST · 90 DAYS` — the letter is part of the copy.
    let kicker: String
    /// One entry per rendered line.
    let title: [String]
    var strap: String? = nil
    var register: SRRegister = .paper

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kicker.uppercased())
                .font(SR.Text.kicker())
                .tracking(SR.Notes.kickerTracking)
                .foregroundStyle(register == .ink ? SR.accentOnDark : SR.Notes.pen)
                .padding(.bottom, 10)

            // line-height 0.94 on the web. SwiftUI adds leading rather than
            // setting it, so the negative spacing is what buys the same tight
            // stack; without it a two-line headline reads as two headlines.
            VStack(alignment: .leading, spacing: -4) {
                ForEach(Array(title.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(SR.Text.hero(34))
                        .tracking(-34 * 0.035)
                        .foregroundStyle(register.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if let strap {
                Text(strap)
                    .font(SR.Text.marginalia(17))
                    .lineSpacing(2)
                    .foregroundStyle(register.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, SR.sectionGap)
    }
}

/// The brand mark on the ink top bar: `SRMark` at its compact size, which
/// fits the 52-point bar with room above and below.
struct Monogram: View {
    var register: SRRegister = .ink
    var size: CGFloat = SRMark.compactSize

    var body: some View {
        SRMark(register: register, size: size)
    }
}

/// The ink bar the app hangs from.
///
/// The site's third round settled this: ink as an inset panel floats no matter
/// how good the panel is, and ink as the page's TOP EDGE docks everything under
/// it. One declaration is the whole site's masthead ground. This is that bar.
///
/// It is deliberately thin. A tall solid ink area reads as intensity rather than
/// editorial, which is why the pulse band went back to cream after "a little
/// intense" — the bar, the footer strip and one ledger are ink, and the reading
/// surface is not.
struct SRTopBar<Trailing: View>: View {
    let path: String
    var kicker: String? = nil
    var back: (label: String, action: () -> Void)? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let back {
                Button(action: back.action) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        Text(back.label.uppercased())
                            .font(SR.monoMedium(12))
                            .tracking(1.2)
                    }
                    .foregroundStyle(SR.accentOnDark)
                }
                .accessibilityIdentifier("sr-back")
            } else {
                Monogram(register: .ink)
            }

            Text(path)
                .font(SR.brand(13))
                .foregroundStyle(SR.creamOnDark)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let kicker {
                Text(kicker.uppercased())
                    .font(SR.mono(12))
                    .tracking(1.2)
                    .foregroundStyle(Color(hex: 0xEDE4D4, alpha: 0.55))
                    .lineLimit(1)
            }
            trailing
        }
        .padding(.horizontal, SR.gutter)
        .frame(height: 52)
        .background(SR.band)
    }
}

extension SRTopBar where Trailing == EmptyView {
    init(path: String, kicker: String? = nil, back: (label: String, action: () -> Void)? = nil) {
        self.init(path: path, kicker: kicker, back: back) { EmptyView() }
    }
}

/// A screen: the ink bar at the top edge, paper beneath, a mono strip at the
/// foot. The app's answer to `HealthShell`.
///
/// `HealthShell` had to be taught `min-height: 100dvh` because a short page put
/// its ink footer halfway up with cream below it — nine sections always
/// overflowed, so four consumers shipped before anything showed it. A phone
/// screen is short by definition, so the footer here is pinned to the bottom of
/// the scroll content and the paper fills the rest regardless.
struct SRShell<Content: View>: View {
    let path: String
    var kicker: String? = nil
    var back: (label: String, action: () -> Void)? = nil
    var footer: [String] = []
    /// The settings cog, or anything else that belongs on the bar's right edge.
    /// A closure rather than a snippet so a caller can pass nothing at all.
    var action: (icon: String, label: String, run: () -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            SRTopBar(path: path, kicker: kicker, back: back) {
                if let action {
                    Button(action: action.run) {
                        Image(systemName: action.icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(SR.accentOnDark)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.label)
                    .accessibilityIdentifier("sr-bar-action")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                    if !footer.isEmpty {
                        SRFooterStrip(items: footer)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(SR.paper)
        }
        .background(SR.paper)
    }
}

/// The mono footer strip. Three items on the designs.
struct SRFooterStrip: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item.uppercased())
                    .font(SR.mono(12))
                    .tracking(1.1)
                    .foregroundStyle(Color(hex: 0xEDE4D4, alpha: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SR.gutter)
        .padding(.vertical, 22)
        .background(SR.band)
        .padding(.top, 36)
    }
}

/// A section of a ruled page.
///
/// Was the web port's slab: a 4% ink wash for `tinted` and a 2pt ink bar
/// under every section but the last. On ruled paper both cut through the
/// petrol feint and the margin rule, so in the notes look a section is
/// whitespace in whole rules (32pt), and `tinted` is a slip of card stock
/// laid on the page with the petrol bar the blog gives its callouts. The
/// slip sits inside the gutter, so the double margin rule stays visible.
///
/// `isLast` is kept so the call sites read as before; with no rule under a
/// section there is nothing for it to leave off.
struct SRSection<Content: View>: View {
    var tinted: Bool = false
    var isLast: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, tinted ? 18 : 0)
            .padding(.leading, tinted ? 19 : 0)
            .padding(.trailing, tinted ? 16 : 0)
            .background {
                if tinted {
                    RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                        .fill(SR.Notes.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                                .strokeBorder(SR.line, lineWidth: 1)
                        )
                        .overlay(alignment: .leading) {
                            Rectangle().fill(SR.accentInk).frame(width: 3)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 32)
    }
}

/// The hairline ledger from `RankedMoves`.
///
/// One hairline between rows, drawn as the container's own background showing
/// through a 1px gap. Safe here for the same reason it is safe there — this is a
/// fixed single column, not an `auto-fit` grid where unfilled tracks paint as
/// blocks, which is the trap the handoff's own note flags.
struct SRLedger<Row: View>: View {
    var register: SRRegister = .paper
    @ViewBuilder var rows: Row

    var body: some View {
        VStack(spacing: 1) { rows }
            .background(register.hairline)
            .overlay(Rectangle().strokeBorder(register.hairline, lineWidth: 1))
    }
}

/// The five-bar meter, as a tally. `leverage` out of five, with a label
/// saying what it measures — "4 of 5" on its own is a number without a unit.
///
/// Was five filled bars; in the notes look it is the count in hand-drawn
/// strokes, a full five being one closed gate. VoiceOver still hears
/// "label: n of total".
struct SRMeter: View {
    let filled: Int
    var total: Int = 5
    var label: String
    var register: SRRegister = .paper

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if filled > 0 {
                SRTally(count: min(filled, total), height: 16, tone: register.accent, seed: seedFor(label))
            } else {
                // Nothing to tally: a faint pencil stroke, so the row does not
                // look as if the meter failed to draw.
                Capsule().fill(register.muted.opacity(0.4)).frame(width: 12, height: 1.5).frame(height: 16)
            }
            Text(label.uppercased())
                .font(SR.Text.kicker())
                .tracking(SR.Notes.kickerTracking)
                .foregroundStyle(register.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(filled) of \(total)")
    }
}

/// The system's one button shape: hairline box, mono label, no radius.
/// Copied from `hd-method`/`d-go` rather than invented — the page already had
/// exactly one button and it looked like this.
struct SRButton: View {
    let title: String
    var filled: Bool = false
    var register: SRRegister = .paper
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        // The app's pen-and-card button, like every other. `register` still
        // decides the label's colour for the outlined weight on an ink band.
        Button(action: action) {
            SRButtonLabel(title: title, fill: true)
                .foregroundStyle(filled ? SR.paper : register.primary)
        }
        .srButton(filled ? .prominent : .regular, seed: seedFor(title))
        .controlSize(.large)
        .disabled(disabled)
    }
}

/// A small status stamp in a row ("Saved", "Selected"): the notes look's
/// rubber stamp, square to the row (`tilt` 0) because it sits among other
/// words. Was an outlined mono pill.
struct SRPill: View {
    let text: String
    var tone: Color
    var register: SRRegister = .paper
    var tilt: Double = 0

    var body: some View {
        SRStamp(text: text, tone: tone, tilt: tilt)
    }
}

/// A kicker: mono caps in the writing orange, 0.14em — the same recipe as
/// `SRSectionLabel`, without the header row. On the cover it writes in
/// orange-on-dark.
struct SRLabel: View {
    let text: String
    var register: SRRegister = .paper

    var body: some View {
        Text(text.uppercased())
            .font(SR.Text.kicker())
            .tracking(SR.Notes.kickerTracking)
            .foregroundStyle(register == .ink ? SR.accentOnDark : SR.Notes.pen)
    }
}
