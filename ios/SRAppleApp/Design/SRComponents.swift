import SwiftUI

/// The masthead every section opens with.
///
/// A direct port of `src/lib/components/shell/SectionHead.svelte`: a lettered
/// mono kicker, an uppercase Archivo Black headline, and one standfirst.
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
                .font(SR.monoMedium(12))
                .tracking(SR.kickerTracking)
                .foregroundStyle(register == .ink ? SR.accentOnDark : SR.inkSecondary)
                .padding(.bottom, 14)

            // line-height 0.94 on the web. SwiftUI adds leading rather than
            // setting it, so the negative spacing is what buys the same tight
            // stack; without it a two-line headline reads as two headlines.
            VStack(alignment: .leading, spacing: -4) {
                ForEach(Array(title.enumerated()), id: \.offset) { _, line in
                    Text(line.uppercased())
                        .font(SR.display(30))
                        .tracking(-0.6)
                        .foregroundStyle(register.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if let strap {
                Text(strap)
                    .font(SR.body(14))
                    .lineSpacing(3)
                    .foregroundStyle(register.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, SR.sectionGap)
    }
}

/// The brand mark. DM Mono, lowercase, with the accent full stop.
struct Monogram: View {
    var register: SRRegister = .ink
    var size: CGFloat = 17

    var body: some View {
        HStack(spacing: 0) {
            Text("sr")
                .font(SR.brand(size))
                .foregroundStyle(register.primary)
            Text(".")
                .font(SR.brand(size))
                .foregroundStyle(register.accent)
        }
        .accessibilityLabel("Strange Ramblings")
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
        .background(SR.ink)
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
        .background(SR.ink)
        .padding(.top, 36)
    }
}

/// A paper section with the system's bottom rule.
///
/// `section:last-of-type { border-bottom: none }` on the web — a section's rule
/// separates it from the NEXT section, so on the last one it draws a stray line
/// across whatever empty space is left. `isLast` is that rule.
struct SRSection<Content: View>: View {
    var tinted: Bool = false
    var isLast: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 34)
            .background(tinted ? SR.ink.opacity(0.04) : Color.clear)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(SR.ink.opacity(0.12)).frame(height: 2)
                }
            }
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

/// The five-bar meter. `leverage` out of five, with a label saying what it
/// measures — "4 of 5" on its own is a number without a unit.
struct SRMeter: View {
    let filled: Int
    var total: Int = 5
    var label: String
    var register: SRRegister = .paper

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(Array(0..<total), id: \.self) { index in
                    Rectangle()
                        .fill(index < filled ? register.accent : register.hairline)
                        .frame(height: 6)
                }
            }
            Text(label.uppercased())
                .font(SR.mono(12))
                .tracking(1)
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
        // Glass now, like every other button in the app. `register` still
        // decides the label's colour for the outlined weight on an ink band.
        Button(action: action) {
            SRButtonLabel(title: title, fill: true)
                .foregroundStyle(filled ? SR.paper : register.primary)
        }
        .srButton(filled ? .prominent : .regular)
        .controlSize(.large)
        .disabled(disabled)
    }
}

/// A mono pill. Radius 100 — one of the two exceptions to radius 0.
struct SRPill: View {
    let text: String
    var tone: Color
    var register: SRRegister = .paper

    var body: some View {
        Text(text.uppercased())
            .font(SR.monoMedium(12))
            .tracking(1)
            .foregroundStyle(tone)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: SR.Radius.pill).strokeBorder(tone.opacity(0.5), lineWidth: 1))
    }
}

/// A mono eyebrow. `.sr-label-tight`.
struct SRLabel: View {
    let text: String
    var register: SRRegister = .paper

    var body: some View {
        Text(text.uppercased())
            .font(SR.monoMedium(12))
            .tracking(1.4)
            .foregroundStyle(register.muted)
    }
}
