import SwiftUI

/// The inspector (§9.5): a long-pressed tile or building, as the page worked
/// it out — what it is, its level and wealth tier, who lives or works there
/// and how they feel, its wants, the top terms of its land value, and "What
/// would make it grow?", which drops a one-tap ghost plan on the map.
struct InspectorSheet: View {
    @ObservedObject var store: HometownsStore
    let card: HometownsInspect
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    SRPageHeader(kicker: kicker, title: card.title, strap: card.who)
                    if let mood = card.mood {
                        Label(mood, systemImage: "face.smiling")
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.inkSecondary)
                    }
                    if !card.wants.isEmpty {
                        VStack(alignment: .leading, spacing: SR.cardGap) {
                            SRSectionLabel(text: store.say("wants.title"))
                            ForEach(card.wants, id: \.self) { want in
                                Label(want, systemImage: "bubble.left.fill")
                                    .font(SR.Text.secondary())
                                    .foregroundStyle(SR.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if let value = card.landValue {
                        landValue(value)
                    }
                    if let line = card.growLine {
                        grow(line)
                    }
                }
                .padding(.horizontal, SR.gutter)
                .padding(.vertical, 12)
            }
            .srGround(.warm)
            .navigationTitle(store.level == .kid ? "Look closer" : "Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("hometowns-inspector")
    }

    /// "Homes · level 2 · ££".
    private var kicker: String {
        var parts = [HometownsCatalogue.humanised(card.kind)]
        if let level = card.level { parts.append("level \(level)") }
        if let tier = card.tier { parts.append(store.say("wealth.\(tier)")) }
        return parts.joined(separator: " · ")
    }

    private func landValue(_ value: Double) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: store.level == .kid ? "Why the land costs this" : "Land value",
                           trailing: HometownsNumber.group(HometownsNumber.round(value)))
            VStack(spacing: 0) {
                ForEach(Array(card.landTerms.enumerated()), id: \.offset) { index, term in
                    if index > 0 { Divider().overlay(SR.divider) }
                    HStack {
                        Image(systemName: term.1 >= 0 ? "arrow.up" : "arrow.down")
                            .foregroundStyle(term.1 >= 0 ? SR.good : SR.warn)
                            .accessibilityHidden(true)
                        Text(term.0)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.ink)
                        Spacer(minLength: 8)
                        if store.level == .adult {
                            Text(HometownsNumber.signed(term.1))
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkSecondary)
                        }
                    }
                    .frame(minHeight: 36)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
        }
    }

    private func grow(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.level == .kid ? "What would help it grow?" : "What would make it grow?")
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
            Text(line)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let plan = card.growPlan, !plan.isEmpty {
                Button {
                    store.dropGhost(plan)
                    dismiss()
                } label: {
                    SRButtonLabel(title: store.level == .kid ? "Show me" : "Plan it", icon: "wand.and.stars")
                }
                .srButton(.prominent)
                .accessibilityIdentifier("hometowns-inspect-grow")
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
    }
}
