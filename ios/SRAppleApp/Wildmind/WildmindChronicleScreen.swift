import SwiftUI

/// Chronicle: one life so far, JKai's or Wren's.
///
/// A segmented JKai | Wren at the top; then who they are, a "Now" card (goal,
/// mood, last thought, ambitions), the timeline newest first with its icon and
/// valley day and time (filterable by kind), and their diary.
///
/// `GET api/native/wildmind/chronicle?id=` through `WildmindFeeds`, one feed a
/// person, polled every half minute while the page is up.
struct WildmindChronicleScreen: View {
    @ObservedObject private var valley = WildmindStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var person: WildmindTalkFilter.Who = .main

    private var mainName: String { valley.answer?.snapshot?.main?.name ?? "JKai" }
    private var companionName: String { valley.answer?.snapshot?.companion?.name ?? "Wren" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                VStack(alignment: .leading, spacing: 16) {
                    SRPageHeader(kicker: "wildmind", title: "Chronicle")
                    Picker("Whose life", selection: $person) {
                        Text(mainName).tag(WildmindTalkFilter.Who.main)
                        Text(companionName).tag(WildmindTalkFilter.Who.companion)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("wildmind-chronicle-person")
                }
                WildmindChronicleBody(feed: WildmindFeeds.chronicle(person))
                    .id(person)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("wildmind-chronicle-screen")
        .srGround(.wire)
        .navigationTitle("Chronicle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SRBarMark() } }
        .task(id: "\(person.rawValue)-\(scenePhase == .active)") {
            guard scenePhase == .active else { return }
            await WildmindFeeds.chronicle(person).poll(every: .seconds(30))
        }
        .srRefreshable { await WildmindFeeds.chronicle(person).load() }
    }
}

/// One person's chronicle, from its feed.
struct WildmindChronicleBody: View {
    @ObservedObject var feed: WildmindFeed<WildmindChronicle>
    /// The timeline kind shown, or every kind.
    @State private var kind: String?
    /// How many timeline rows are drawn; a long life is hundreds.
    @State private var shown = 40

    var body: some View {
        if feed.phase == .ready, let chronicle = feed.value {
            content(chronicle)
        } else {
            WildmindLaneStateView(phase: feed.phase, what: "The chronicle") {
                Task { await feed.load() }
            }
        }
    }

    private func content(_ chronicle: WildmindChronicle) -> some View {
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            if feed.stale { WildmindStaleNote() }
            if let who = chronicle.who { whoCard(who) }
            if let now = chronicle.now {
                nowCard(now, name: chronicle.who?.name ?? "They", clock: chronicle.valley?.clock)
            }
            timeline(chronicle)
            diary(chronicle)
        }
    }

    // MARK: Who

    private func whoCard(_ who: WildmindChronicle.Who) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(WildmindTone.of(who: who.id))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(who.name)
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if who.alive {
                    SRGlassChip(text: "alive", icon: "heart.fill", tone: SR.good)
                } else {
                    SRGlassChip(text: who.causeOfDeath.map { "died: \($0)" } ?? "died", icon: "leaf", tone: SR.error)
                }
            }
            if let persona = who.persona {
                Text(persona)
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Now

    private func nowCard(_ now: WildmindChronicle.Now, name: String, clock: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Now", trailing: clock)
            SRCard(accented: true) {
                VStack(alignment: .leading, spacing: 14) {
                    if let goal = now.goal {
                        VStack(alignment: .leading, spacing: 4) {
                            label("Goal")
                            Text(goal)
                                .font(SR.Text.title(18))
                                .foregroundStyle(SR.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let mood = now.mood {
                        HStack(spacing: 10) {
                            label("Mood")
                            SRGlassChip(text: mood, tone: SR.accent)
                        }
                    }
                    if let thought = now.lastThought {
                        VStack(alignment: .leading, spacing: 4) {
                            label("Last thought")
                            Text("\u{201C}\(thought)\u{201D}")
                                .font(SR.Text.secondary(15))
                                .italic()
                                .foregroundStyle(SR.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !now.ambitions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            label("Ambitions")
                            ForEach(now.ambitions, id: \.self) { ambition in
                                ambitionRow(ambition)
                            }
                        }
                    }
                    if now.goal == nil && now.mood == nil && now.lastThought == nil && now.ambitions.isEmpty {
                        Text("\(name) hasn\u{2019}t settled on anything yet.")
                            .font(SR.Text.secondary(15))
                            .foregroundStyle(SR.inkMuted)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wildmind-chronicle-now")
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(SR.Text.label())
            .tracking(SR.kickerTracking)
            .foregroundStyle(SR.inkMuted)
    }

    private func ambitionRow(_ ambition: WildmindChronicle.Ambition) -> some View {
        let (icon, tone): (String, Color) = {
            switch ambition.status {
            case "done"?: return ("checkmark.circle.fill", SR.good)
            case "abandoned"?: return ("xmark.circle", SR.inkGhost)
            default: return ("circle", SR.accent)
            }
        }()
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone)
                .accessibilityHidden(true)
            Text(ambition.text)
                .font(SR.Text.body(15))
                .foregroundStyle(ambition.status == "abandoned" ? SR.inkMuted : SR.ink)
                .strikethrough(ambition.status == "abandoned")
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(ambition.status ?? "active")
    }

    // MARK: Timeline

    private func timeline(_ chronicle: WildmindChronicle) -> some View {
        let events = chronicle.timeline.filter { kind == nil || $0.kind == kind }
        return VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Timeline", trailing: "\(chronicle.timeline.count)")
            if chronicle.kinds.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        WildmindChip(label: "All", selected: kind == nil, identifier: "wildmind-chronicle-kind-all") {
                            kind = nil
                            shown = 40
                        }
                        ForEach(chronicle.kinds.prefix(8), id: \.self) { item in
                            WildmindChip(label: item, selected: kind == item, identifier: "wildmind-chronicle-kind-\(item)") {
                                kind = kind == item ? nil : item
                                shown = 40
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
            if events.isEmpty {
                Text("Nothing in the timeline yet.")
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(SR.inkMuted)
            } else {
                SRCard {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(events.prefix(shown).enumerated()), id: \.offset) { _, event in
                            eventRow(event)
                        }
                    }
                }
                if events.count > shown {
                    Button {
                        SRHaptic.tap()
                        shown += 80
                    } label: {
                        SRButtonLabel(title: "Show older (\(events.count - shown))", icon: "chevron.down")
                    }
                    .srButton()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("wildmind-chronicle-more")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wildmind-chronicle-timeline")
    }

    private func eventRow(_ event: WildmindChronicle.Event) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.icon ?? "\u{2022}")
                .font(.body)
                .frame(width: 34, height: 34)
                .srGlass(.paper, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.text)
                    .font(SR.Text.body(15))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text((event.when ?? event.day.map { "Day \($0)" } ?? event.kind).uppercased())
                    .font(SR.Text.mono())
                    .tracking(0.6)
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Diary

    private func diary(_ chronicle: WildmindChronicle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Diary")
            if chronicle.diary.isEmpty {
                Text("No diary yet. They write one each night.")
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(SR.inkMuted)
            } else {
                ForEach(Array(chronicle.diary.enumerated()), id: \.offset) { _, page in
                    SRCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(page.day.map { "Day \($0)" }?.uppercased() ?? "UNDATED")
                                .font(SR.Text.label())
                                .tracking(SR.kickerTracking)
                                .foregroundStyle(SR.accent)
                            Text(WildmindTalkWords.diaryBody(page.text))
                                .font(SR.Text.body(16))
                                .foregroundStyle(SR.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wildmind-chronicle-diary")
    }
}
