import SwiftUI

/// People (§9.11): the five faces with their stars and happiness, what the
/// town wants, the needs ladders as checklists, and Town Talk.
///
/// This is the Mood and Why layers (§9.6) as M1 has them: faces, stars in
/// halves, "Families need: School ✓ Park ✓ Safety ✗", and what residents say
/// with the share who say it. Graphs and family comparisons follow with the
/// county (M2).
struct PeopleSheet: View {
    @ObservedObject var store: HometownsStore
    @Environment(\.dismiss) private var dismiss

    static let faces = ["workers", "professionals", "families", "retirees", "students"]
    static let stars = ["jobs", "homes", "tax", "schools", "health", "safety", "fun", "culture", "nature", "around", "buzz"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    if let town = store.town, let me = store.wire?.me {
                        facesSection(town)
                        wantsSection(me.derived)
                        if me.derived.pipelineHomes > 0 || me.derived.pipelineMovers > 0 { pipeline(me.derived) }
                        starsSection
                        needsSection(me.derived)
                        talkSection(me.derived)
                    }
                }
                .padding(.horizontal, SR.gutter)
                .padding(.vertical, 12)
            }
            .srGround(.warm)
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("hometowns-people-sheet")
    }

    // MARK: Faces

    private func facesSection(_ town: HometownsTown) -> some View {
        let counts = store.wire?.myCard?.faces ?? []
        let happy = HometownsText.faceHappiness(town)
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Who lives here", trailing: "\(HometownsText.people(town.population)) people")
            VStack(spacing: 0) {
                ForEach(Array(Self.faces.enumerated()), id: \.offset) { index, face in
                    let n = counts.indices.contains(index) ? counts[index] : 0
                    if n > 0 || index != 4 {
                        if index > 0 { Divider().overlay(SR.divider) }
                        HStack(spacing: 12) {
                            Image(systemName: HometownsText.moodSymbol(happy[index]))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(happy[index] >= 45 ? SR.good : SR.inkMuted)
                                .frame(width: 26)
                            Text(store.say("face.\(face)"))
                                .font(SR.Text.title())
                                .foregroundStyle(SR.ink)
                            Spacer(minLength: 8)
                            Text(HometownsText.people(n))
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkSecondary)
                            if store.level == .adult {
                                Text("\(Int(happy[index].rounded())) happy")
                                    .font(SR.Text.mono())
                                    .foregroundStyle(SR.inkMuted)
                            }
                        }
                        .frame(minHeight: SR.tapTarget)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("hometowns-face-\(face)")
                    }
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
        }
    }

    // MARK: Wants

    private func wantsSection(_ d: HometownsDerived) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: store.say("wants.title"))
            if d.wants.isEmpty {
                Text(store.say("wants.none"))
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            } else {
                ForEach(d.wants) { want in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: want.hatched ? "circle.dashed" : "bubble.left.fill")
                            .foregroundStyle(want.hatched ? SR.inkMuted : SR.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.say("want.\(want.key)"))
                                .font(SR.Text.bodyMedium(15))
                                .foregroundStyle(SR.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if want.hatched {
                                Text(store.say("meter.hatched"))
                                    .font(SR.Text.secondary())
                                    .foregroundStyle(SR.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("hometowns-want-row-\(want.key)")
                }
            }
        }
    }

    /// Delays are always visible (§9.8): results arrive later.
    private func pipeline(_ d: HometownsDerived) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if d.pipelineHomes > 0 {
                Label(store.say("forecast.homesBuilding", ["n": .number(Double(d.pipelineHomes))]), systemImage: "hammer")
            }
            if d.pipelineMovers > 0 {
                Label(store.say("forecast.movers", ["n": .number(Double(d.pipelineMovers))]), systemImage: "figure.walk")
            }
        }
        .font(SR.Text.secondary())
        .foregroundStyle(SR.inkSecondary)
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityIdentifier("hometowns-pipeline")
    }

    // MARK: Stars

    private var starsSection: some View {
        let stars = store.wire?.me?.derived.stars ?? []
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: store.level == .kid ? "How people rate the town" : "Stars")
            VStack(spacing: 0) {
                ForEach(Array(Self.stars.enumerated()), id: \.offset) { index, key in
                    if stars.indices.contains(index) {
                        if index > 0 { Divider().overlay(SR.divider) }
                        HStack(spacing: 12) {
                            Text(store.say("star.\(key)"))
                                .font(SR.Text.title())
                                .foregroundStyle(SR.ink)
                            Spacer(minLength: 8)
                            HometownsStars(halves: HometownsText.starHalves(stars[index]))
                        }
                        .frame(minHeight: SR.tapTarget)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(store.say("star.\(key)")): \(HometownsNumber.oneDecimal(HometownsText.starHalves(stars[index]))) stars out of 5")
                    }
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
        }
    }

    // MARK: Needs ladders

    private func needsSection(_ d: HometownsDerived) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: store.level == .kid ? "What families need" : "Needs ladders")
            ForEach(d.needs) { row in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(store.say("wealth.\(row.tier)")) \(store.say("face.families"))")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    HometownsFlow(spacing: 6) {
                        ForEach(row.items) { item in
                            let met = item.met >= 0.5
                            Label(store.say("need.\(item.key)"), systemImage: met ? "checkmark.circle.fill" : "circle")
                                .font(SR.Text.secondary())
                                .foregroundStyle(met ? SR.good : (item.buildable ? SR.ink : SR.inkMuted))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(SR.line.opacity(0.5)))
                                .accessibilityLabel("\(store.say("need.\(item.key)")): \(met ? "met" : "not yet")")
                        }
                    }
                }
                .padding(SR.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .srGlassCard(.paper)
                .accessibilityIdentifier("hometowns-needs-\(row.tier)")
            }
        }
    }

    // MARK: Town Talk

    private func talkSection(_ d: HometownsDerived) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Town Talk")
            if d.townTalk.isEmpty {
                Text(store.say("wants.none"))
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            ForEach(d.townTalk) { talk in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(store.say("talk.say", ["pct": .number(talk.pct / 100)]))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.accentInk)
                    Text(store.say("talk.\(talk.key)"))
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { store.readAloud(store.say("talk.\(talk.key)")) } label: { Image(systemName: "speaker.wave.2") }
                        .buttonStyle(.plain)
                        .foregroundStyle(SR.inkMuted)
                        .accessibilityLabel("Read aloud")
                }
                .accessibilityIdentifier("hometowns-talk-\(talk.key)")
            }
        }
    }
}

/// Stars as halves out of five.
struct HometownsStars: View {
    let halves: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                let v = halves - Double(i)
                Image(systemName: v >= 1 ? "star.fill" : v >= 0.5 ? "star.leadinghalf.filled" : "star")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SR.accent)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Chips that wrap onto as many lines as they need.
struct HometownsFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += line + spacing
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(width, widest), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += line + spacing
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
