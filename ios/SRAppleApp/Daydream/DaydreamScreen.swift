import SwiftUI

/// Daydream: one process in four steps, the same four `/jkai/daydreams` draws.
///
///   01 Spotted — jkai writes down anything worth your attention, citing what it read.
///   02 Your call — keep it, have the facts checked again, or say it is not for you.
///   03 In motion — anything you approved runs on its own.
///   04 Result — the report comes back; your verdicts are the score it learns from.
///
/// The page opens on what is waiting for your call. Opened from Today's tile
/// and from More; a deep link to a double-check opens "All", so the note it
/// belongs to is on screen whichever list it sits in.
struct DaydreamScreen: View {
    @ObservedObject private var store = DaydreamStore.shared
    @ObservedObject private var feedback = NoticedFeedback.shared
    @ObservedObject private var commissions = CommissionStore.shared
    /// The four-step explanation shows until it is folded away once.
    @AppStorage("daydream.howItWorks.seen") private var seenHowItWorks = false
    @State private var reopenedHowItWorks = false
    @State private var filter: DaydreamFilter = .decide

    var body: some View {
        ScrollView {
            // A plain stack: forty cards at most, and the UI tests look for a
            // control on a card below the fold.
            VStack(alignment: .leading, spacing: SR.cardGap) {
                header

                if !seenHowItWorks || reopenedHowItWorks {
                    DaydreamHowItWorks {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            seenHowItWorks = true
                            reopenedHowItWorks = false
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                DaydreamPipelineStrip(
                    spotted: store.notes.count,
                    counts: store.counts(feedback: feedback, commissions: commissions),
                    selected: filter
                ) { chosen in
                    withAnimation(.easeInOut(duration: 0.2)) { filter = chosen }
                }

                Picker("Show", selection: $filter) {
                    ForEach(DaydreamFilter.allCases, id: \.self) { option in
                        Text("\(option.label) \(count(option))").tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("daydream-filter")
                .padding(.vertical, 2)

                if let error = commissions.error {
                    Text(error)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }

                list

                if let impact = store.impact {
                    DaydreamImpactCard(impact: impact)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("daydream-screen")
        .srGround(.quiet)
        .navigationTitle("Daydream")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SRBarMark() } }
        .onAppear { takeRequestedFilter() }
        .onChange(of: store.requestedFilter) { _, _ in takeRequestedFilter() }
        .task { await store.load(); await commissions.load() }
        .srRefreshable { await store.load(); await commissions.load() }
        .sheet(item: $commissions.destination) { destination in
            NavigationStack { CommissionDetailScreen(id: destination.id) }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("DAYDREAM")
                    .font(SR.Text.label())
                    .tracking(1.4)
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if seenHowItWorks && !reopenedHowItWorks {
                    Button {
                        SRHaptic.tap()
                        withAnimation(.easeInOut(duration: 0.25)) { reopenedHowItWorks = true }
                    } label: {
                        Label("How it works", systemImage: "questionmark.circle")
                            .font(SR.Text.label())
                            .foregroundStyle(SR.accentInk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("daydream-how-it-works-open")
                }
            }
            Text("What jkai spotted in your days, and your call on each.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    // MARK: - The list

    @ViewBuilder
    private var list: some View {
        let notes = visibleNotes
        let others = visibleOrphans
        if store.notes.isEmpty && commissions.commissions.isEmpty {
            if store.loaded {
                SREmpty(
                    title: "Nothing noticed yet",
                    icon: "sparkles",
                    message: "jkai writes a note or two every 45 minutes, when it has something worth saying. They land here."
                )
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
            }
        } else if notes.isEmpty && others.isEmpty {
            empty
        } else {
            ForEach(notes) { note in
                DaydreamNoteCard(note: note)
                    .transition(.opacity)
            }
            if !others.isEmpty {
                SRSectionLabel(text: "Other double-checks", trailing: "\(others.count)")
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                ForEach(others) { commission in
                    DaydreamCommissionRow(commission: commission)
                }
            }
        }
    }

    @ViewBuilder
    private var empty: some View {
        switch filter {
        case .decide:
            SREmpty(
                title: "You're all caught up",
                icon: "checkmark.circle",
                message: "Nothing is waiting for your call. New notes land here as jkai spots them."
            )
            .accessibilityIdentifier("daydream-caught-up")
        case .motion:
            SREmpty(
                title: "Nothing running",
                icon: "hourglass",
                message: "When you approve a double-check, it shows here while it re-reads the sources."
            )
        case .done:
            SREmpty(
                title: "Nothing finished yet",
                icon: "tray",
                message: "Notes you have answered, and reports that came back, collect here."
            )
        case .all:
            SREmpty(title: "Nothing noticed yet", icon: "sparkles")
        }
    }

    private var visibleNotes: [DaydreamNote] {
        guard let bucket = filter.bucket else { return store.notes }
        return store.notes.filter { store.bucket(for: $0, feedback: feedback, commissions: commissions) == bucket }
    }

    /// Double-checks whose note is not among the forty the phone holds.
    /// They still need a way in, so they list under the notes.
    private var orphans: [DaydreamCommission] {
        let ids = Set(store.notes.map(\.id))
        let named = Set(store.notes.compactMap(\.commissionId))
        return commissions.commissions.filter { !ids.contains($0.thoughtId) && !named.contains($0.id) }
    }

    private var visibleOrphans: [DaydreamCommission] {
        guard let bucket = filter.bucket else { return orphans }
        return orphans.filter { Self.bucket(of: $0) == bucket }
    }

    private static func bucket(of commission: DaydreamCommission) -> DaydreamBucket {
        switch commission.state {
        case "awaiting_approval", "deferred": return .decide
        case "queued", "running", "needs_attention": return .motion
        default: return .done
        }
    }

    /// What each segment says: the notes the phone holds in that list.
    private func count(_ option: DaydreamFilter) -> Int {
        let notes: Int
        if let bucket = option.bucket {
            notes = store.notes.filter { store.bucket(for: $0, feedback: feedback, commissions: commissions) == bucket }.count
        } else {
            notes = store.notes.count
        }
        let others = option.bucket.map { bucket in orphans.filter { Self.bucket(of: $0) == bucket }.count } ?? orphans.count
        return notes + others
    }

    private func takeRequestedFilter() {
        guard let requested = store.requestedFilter else { return }
        filter = requested
        store.requestedFilter = nil
    }
}

// MARK: - How it works

/// The four sentences, once, until "Got it" — then behind "How it works".
struct DaydreamHowItWorks: View {
    let done: () -> Void

    var body: some View {
        SRCard(accented: true) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HOW IT WORKS")
                        .font(SR.Text.label())
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(SR.accent)
                    Text("One process, four steps")
                        .font(SR.Text.display(20))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(DaydreamStage.allCases, id: \.self) { stage in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(String(format: "%02ld", stage.number))
                            .font(SR.Text.label(13))
                            .foregroundStyle(SR.accentInk)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stage.label)
                                .font(SR.Text.bodyMedium(16))
                                .foregroundStyle(SR.ink)
                            Text(stage.explanation)
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Step \(stage.number), \(stage.label). \(stage.explanation)")
                }
                Button {
                    SRHaptic.tap()
                    done()
                } label: {
                    SRButtonLabel(title: "Got it", icon: "checkmark")
                }
                .srButton(.prominent)
                .accessibilityIdentifier("daydream-how-it-works-done")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("daydream-how-it-works")
    }
}

// MARK: - The strip

/// 01 Spotted · 02 Your call · 03 In motion · 04 Result, with the live count
/// under each. A step is also a way to its list. Counts other than Spotted
/// come from the site; an older server sends none, and they are left off
/// rather than shown as a guess.
struct DaydreamPipelineStrip: View {
    let spotted: Int
    let counts: DaydreamPipeline?
    let selected: DaydreamFilter
    let select: (DaydreamFilter) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 4))
        layout {
            ForEach(DaydreamStage.allCases, id: \.self) { stage in
                cell(stage)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("daydream-pipeline")
    }

    private func cell(_ stage: DaydreamStage) -> some View {
        let target = Self.filter(for: stage)
        let on = target == selected
        let number = count(for: stage)
        return Button {
            SRHaptic.select()
            select(target)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%02ld", stage.number))
                    .font(SR.Text.mono())
                    .foregroundStyle(on ? SR.accent : SR.inkMuted)
                Text(stage.label.uppercased())
                    .font(SR.Text.label())
                    .tracking(0.6)
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let number {
                    Text("\(number)")
                        .font(SR.Text.figure(22))
                        .foregroundStyle(on ? SR.accentInk : SR.ink)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius - 4, style: .continuous)
                    .fill(on ? SR.accentInk.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(stage, number))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(on ? AccessibilityTraits.isSelected : [])
        .accessibilityIdentifier("daydream-stage-\(stage.rawValue)")
    }

    private func count(for stage: DaydreamStage) -> Int? {
        switch stage {
        case .spotted: return spotted
        case .decide: return counts?.decide
        case .motion: return counts?.motion
        case .result: return counts?.done
        }
    }

    private func accessibilityText(_ stage: DaydreamStage, _ number: Int?) -> String {
        let base = "Step \(stage.number), \(stage.label)"
        guard let number else { return base }
        return "\(base), \(number)"
    }

    static func filter(for stage: DaydreamStage) -> DaydreamFilter {
        switch stage {
        case .spotted: return .all
        case .decide: return .decide
        case .motion: return .motion
        case .result: return .done
        }
    }
}

// MARK: - A double-check without its note

/// A double-check whose note is older than the list the phone holds: its
/// title and state, opening the sign-off sheet.
struct DaydreamCommissionRow: View {
    let commission: DaydreamCommission
    @ObservedObject private var store = CommissionStore.shared

    var body: some View {
        Button {
            SRHaptic.tap()
            store.destination = CommissionDestination(id: commission.id)
        } label: {
            SRCard(interactive: true) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: DaydreamCommissionStatus.icon(for: commission.state))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DaydreamCommissionStatus.tone(for: commission.state))
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(commission.label.uppercased())
                            .font(SR.Text.label())
                            .tracking(1)
                            .foregroundStyle(DaydreamCommissionStatus.tone(for: commission.state))
                        Text(commission.spec.title)
                            .font(SR.Text.bodyMedium(16))
                            .foregroundStyle(SR.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SR.inkMuted)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the sign-off sheet")
        .accessibilityIdentifier("commission-\(commission.id)")
    }
}
