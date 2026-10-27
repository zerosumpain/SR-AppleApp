import SwiftUI

/// The strip of chips under the bar on Family, Games and Health — the same
/// furniture on each, so the top of every tab reads the same way (John,
/// 2026-10-21: "one layout for all").
///
/// What a chip does is the page's business: on Family a chip is a favourite
/// place, and choosing it frames the map there; on Games and Health it opens
/// a section. A chip that is a place to GO (`selected` never set) reads as a
/// door; one that filters the page stays lit while it holds.
struct SRChip: Identifiable, Equatable {
    let id: String
    let title: String
    var icon: String? = nil
    /// A small figure after the title — people at a place, invites waiting.
    var count: Int? = nil
}

struct SRChipStrip: View {
    let chips: [SRChip]
    /// The chip holding the page, if any.
    var selected: String? = nil
    var identifier = "chip-strip"
    let choose: (SRChip) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    let on = chip.id == selected
                    Button {
                        SRHaptic.select()
                        choose(chip)
                    } label: {
                        HStack(spacing: 5) {
                            if let icon = chip.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .accessibilityHidden(true)
                            }
                            Text(chip.title)
                                .font(SR.Text.title(14))
                                .lineLimit(1)
                            if let count = chip.count, count > 0 {
                                Text("\(count)")
                                    .font(SR.monoMedium(12))
                                    .foregroundStyle(on ? SR.paper.opacity(0.85) : SR.inkMuted)
                            }
                        }
                        .foregroundStyle(on ? SR.paper : SR.ink)
                        .padding(.horizontal, 13)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(on ? SR.accentDeep : SR.surface))
                        .overlay(Capsule().strokeBorder(on ? Color.clear : SR.line, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chip.count.map { "\(chip.title), \($0)" } ?? chip.title)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("\(identifier)-\(chip.id)")
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 6)
        }
        // A horizontal scroll view in a stack grows to fill what it is
        // offered; its own height is the chips'.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

extension View {
    /// A strip pinned under the bar with the page scrolling behind both, as
    /// every tab's page scrolls behind the `sr.` mark. On iOS 26 the bar's
    /// scroll-edge blur reaches down under the strip (`safeAreaBar`); before
    /// it, a plain inset.
    @ViewBuilder
    func srPinnedStrip<Strip: View>(@ViewBuilder _ strip: () -> Strip) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top, spacing: 0) { strip() }
        } else {
            safeAreaInset(edge: .top, spacing: 0) { strip() }
        }
    }

    /// The top of a tab's first page, the same on every tab: the hub on the
    /// left, the `sr.` mark in the middle. The page adds its own trailing items.
    func srTabBar() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) { SRHubButton() }
            ToolbarItem(placement: .principal) { SRBarMark() }
        }
    }
}
