import SwiftUI

/// "Tell the planner": the planning conversation, on the phone.
///
/// v8: what the planner answers with comes back as the same cards as the
/// rest of the trip — a group of proposals to preview and use, a question
/// to tap an answer to — never prose only. It opens at half height over the
/// plan (`presentationDetents([.medium, .large])`), so the plan stays in
/// view. Options from an older server show only when there are no proposals.
///
/// The plan is developed by talking to the planner (`POST …/converse`,
/// trips spec v2): "make the rest of today lighter", "swap the Vatican to
/// the morning", "we're running 20 minutes late". Its reply, what it changed
/// and its suggested follow-ups appear inline; the plan behind the sheet
/// refreshes from the result. Dictation is the keyboard's own microphone.
///
/// A conversation needs the planner, so offline NOTHING is queued: the
/// sheet says so and offers what the phone can do alone — running late,
/// skip, swap — through the local solver.
struct TripConverseSheet: View {
    let tripId: String
    let date: String
    /// Words to start from: "About “Dinner around 19:30”: ".
    var initialDraft: String? = nil
    /// Preview a proposal on its day's map: the presenter closes this sheet
    /// and shows it there (the map is not under a half-height sheet).
    var onPreview: ((TripProposal) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var network = TripNetwork.shared
    @State private var draft = ""
    /// The turn runs as a job (v6), kept by `TripJobs`: closing this sheet,
    /// or the app going to the background, does not lose the answer.
    @ObservedObject private var jobs = TripJobs.shared
    private var key: String { TripJobs.converseKey(tripId) }
    private var sending: Bool { jobs.isRunning(key) }
    private var last: ConverseResult? { jobs.conversed[key] }
    private var failure: String? {
        if case .failed(let why) = jobs.states[key] { return "Not sent: \(why) Nothing was saved to send later." }
        return nil
    }
    @State private var options: TripOptionsRequest?
    @State private var compare: TripShapePager.ComparePair?
    @State private var toast: TripChangeRecord?
    @FocusState private var typing: Bool

    /// What this person may do with the trip.
    private var can: TripAccess { store.bundles[tripId]?.can ?? .owner }

    /// Where the trip is: the starters follow it.
    private var phase: TripPhase {
        guard let trip = store.bundles[tripId]?.trip else { return .during }
        return TripPhase.of(start: trip.startDate, end: trip.endDate, today: TripClock(trip.timeZone).localDate(Date()))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            Text(can.canEdit
                                 ? "Tell the planner what to change. It answers here, and the plan updates behind this sheet."
                                 : "Ask the planner anything about the trip.")
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(messages) { message in
                            TripMessageBubble(message: message)
                                .id(message.id)
                        }
                        if let last, !last.changes.isEmpty || !last.rejected.isEmpty {
                            changes(last)
                        }
                        if let last { decisions(last) }
                        if jobs.isRunning(key) {
                            thinking.id("thinking")
                        }
                        // Offline "Running late" and friends: the phone's own
                        // options, inline — never a sheet over this sheet.
                        if let request = options {
                            TripOptionsPanel(request: request, close: { options = nil })
                                .id(request.id)
                        }
                        if let failure {
                            Label(failure, systemImage: "exclamationmark.triangle")
                                .font(SR.Text.secondary(13))
                                .foregroundStyle(SR.error)
                        }
                    }
                    .padding(SR.gutter)
                }
                .onChange(of: options?.id) { _, id in
                    if let id { withAnimation { scroller.scrollTo(id, anchor: .bottom) } }
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { scroller.scrollTo(messages.last?.id ?? "thinking", anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .srPaper()
            .navigationTitle(can.canEdit ? "Tell the planner" : "Ask the planner")
            .safeAreaInset(edge: .top) {
                // v5: someone who can't change this trip gets advice, said plainly.
                if !can.canEdit {
                    Label("Advice only — the plan is changed by whoever made the trip or a parent. To propose something, use “Make a suggestion” on a day.",
                          systemImage: "info.circle")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, SR.gutter)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                        .accessibilityIdentifier("trip-advice-only")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .navigationDestination(item: $compare) { pair in
                TripCompareView(left: pair.left, right: pair.right, tripId: tripId) { change in show(change) }
            }
            .overlay(alignment: .top) {
                if let toast {
                    TripChangesToast(change: toast)
                        .padding(.top, 4)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast?.id)
            .onAppear {
                if let initialDraft, draft.isEmpty {
                    draft = initialDraft
                    typing = true
                }
            }
        }
        .accessibilityIdentifier("trip-converse")
    }

    // MARK: What the planner answered with

    /// The turn's proposals as the same pager as everywhere, its questions as
    /// the same cards — and an older server's options only when it sent no
    /// proposals.
    @ViewBuilder
    private func decisions(_ result: ConverseResult) -> some View {
        let zone = TripClock(store.bundles[tripId]?.trip.timeZone ?? "UTC").zone
        let groups = TripDecisions.groups(result.proposals?.map(latestProposal), bundle: store.bundles[tripId], zone: zone)
        ForEach(groups) { group in
            TripProposalPager(
                group: group, tripId: tripId,
                onPreview: onPreview,
                onCompare: { a, b in compare = TripShapePager.ComparePair(left: a, right: b) },
                onChange: { show($0) }
            )
            .padding(.vertical, 4)
        }
        ForEach(decidedHere(result), id: \.self) { line in
            Label(line, systemImage: "checkmark.circle")
                .font(SR.Text.secondary(13))
                .foregroundStyle(TripPalette.confirmed)
        }
        let open = (result.questions ?? []).filter { q in store.decided[q.id] == nil && q.status == .open }
        ForEach(open) { question in
            TripQuestionCard(question: latestQuestion(question), tripId: tripId, onChange: { show($0) })
        }
        // v7: an open question answered with choices, each checked against its day.
        if (result.proposals ?? []).isEmpty, let options = result.options, !options.isEmpty, let bundle = store.bundles[tripId] {
            TripOptionCards(tripId: tripId, options: options, bundle: bundle)
        }
    }

    /// The trip's own copy of a proposal (re-checked, or decided) when it has one.
    private func latestProposal(_ p: TripProposal) -> TripProposal {
        if let kept = store.bundles[tripId]?.proposals?.first(where: { $0.id == p.id }) { return kept }
        var gone = p
        if store.decided[p.id] != nil { gone.status = .accepted }
        return gone
    }

    private func latestQuestion(_ q: TripQuestion) -> TripQuestion {
        store.bundles[tripId]?.questions?.first { $0.id == q.id } ?? q
    }

    /// "Used Palazzo Altemps", "You answered: carry on" — what this turn's
    /// cards became, so the conversation reads as it went.
    private func decidedHere(_ result: ConverseResult) -> [String] {
        let used = (result.proposals ?? []).filter { store.decided[$0.id] == "Used" }.map { "Used \($0.title)" }
        let answered = (result.questions ?? []).compactMap { store.decided[$0.id] }
        return used + answered
    }

    private func show(_ change: TripChangeRecord) {
        toast = change
        let id = change.id
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if toast?.id == id { toast = nil }
        }
    }

    /// Staged progress when the server reports it ("Looking for places near
    /// the stay"), else a calm line — never a seconds counter.
    private var thinking: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(jobs.stages[key]?.first { $0.state == .running }.map { $0.label + "…" } ?? "The planner is working on it…")
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Cancel") { jobs.cancel(key) }
                .font(SR.Text.title(14))
        }
        .accessibilityElement(children: .combine)
    }

    /// What the server has stored, then — until the re-read trip carries
    /// them — the words just sent and the planner's answer.
    private var messages: [TripMessage] {
        let saved = (store.bundles[tripId]?.messages ?? []).sorted { $0.createdAt < $1.createdAt }
        var out = saved
        if case .running(let since, let asked?) = jobs.states[key], !saved.contains(where: { $0.role == .user && $0.text == asked }) {
            out.append(TripMessage(id: "pending-ask", role: .user, text: asked, ops: [], planVersion: nil, surface: "phone",
                                   createdAt: TripStore.iso(since)))
        }
        if let last, !saved.contains(where: { $0.role == .assistant && $0.text == last.reply }) {
            out.append(TripMessage(id: "pending-reply", role: .assistant, text: last.reply, ops: last.applied,
                                   planVersion: last.planVersion, surface: "phone", createdAt: "", research: last.research))
        }
        return out
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if network.online || SRDemo.isOn {
                quickReplies
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Say what to change — or use the keyboard's microphone", text: $draft, axis: .vertical)
                        .font(SR.Text.body(16))
                        .lineLimit(1...5)
                        .focused($typing)
                        .submitLabel(.send)
                        .onSubmit { send(draft) }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .srGlass(.paper, in: RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
                        .accessibilityIdentifier("trip-converse-field")
                    Button { send(draft) } label: {
                        Image(systemName: "arrow.up.circle.fill").font(SR.Text.display(30))
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                    .accessibilityLabel("Send")
                }
            } else {
                offline
            }
        }
        .padding(.horizontal, SR.gutter)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var quickReplies: some View {
        let replies = (last?.quickReplies.isEmpty == false ? last?.quickReplies : nil)
            ?? TripDecisions.starters(phase: phase, canEdit: can.canEdit)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(replies, id: \.self) { reply in
                    Button { send(reply) } label: {
                        TripChip(reply, style: .nudge)
                    }
                    .buttonStyle(.plain)
                    .disabled(sending)
                }
            }
        }
        .accessibilityIdentifier("trip-quick-replies")
    }

    /// No signal: nothing is queued, and the phone's own re-plans are offered.
    private var offline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Changing the plan with the planner needs a connection. Nothing is saved to send later.", systemImage: "wifi.slash")
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if can.canEdit {
            Text("On this phone, now:").font(SR.Text.label()).foregroundStyle(SR.inkMuted)
            HStack(spacing: 8) {
                Menu {
                    ForEach([10, 20, 30, 45], id: \.self) { minutes in
                        Button("\(minutes) min") { late(minutes) }
                    }
                } label: { TripButtonLabel("Running late", icon: "clock") }
                Menu {
                    ForEach(skippable, id: \.id) { stop in
                        Button(stop.title) { skip(stop) }
                    }
                } label: { TripButtonLabel("Skip", icon: "forward") }
                .disabled(skippable.isEmpty)
                Button { swap() } label: { TripButtonLabel("Swap", icon: "arrow.up.arrow.down") }
                    .disabled(swappable == nil)
            }
            .srButton(.regular)
            .controlSize(.small)
            }
        }
        .accessibilityIdentifier("trip-converse-offline")
    }

    private func changes(_ result: ConverseResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(result.changes, id: \.self) { change in
                Label(change, systemImage: "checkmark.circle").font(SR.Text.secondary(13)).foregroundStyle(SR.good)
            }
            ForEach(Array(result.rejected.enumerated()), id: \.offset) { _, rejected in
                Label("Not done: \(rejected.reason)", systemImage: "xmark.circle").font(SR.Text.secondary(13)).foregroundStyle(SR.warn)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Talking

    private func send(_ text: String) {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty, !sending else { return }
        SRHaptic.tap()
        draft = ""
        jobs.converse(said, tripId: tripId)
    }

    // MARK: Offline quick actions (the local solver)

    private var context: (day: PlannedDay, progress: TripProgress, clock: TripClock)? {
        guard let day = store.day(tripId, date), let clock = store.clock(tripId),
              let progress = store.progress(tripId, date) else { return nil }
        return (day, progress, clock)
    }

    private var skippable: [PlannedStop] {
        guard let c = context else { return [] }
        let done = Set(c.progress.doneStopIds)
        return c.day.stops.filter { $0.kind == .wish && !done.contains($0.id) && !$0.locked }
    }

    /// The next two visits, when neither is locked.
    private var swappable: (Int, Int)? {
        guard let c = context, let from = c.progress.retimeFrom else { return nil }
        let done = Set(c.progress.doneStopIds)
        let open = c.day.stops.indices.filter { $0 >= from && c.day.stops[$0].kind == .wish && !done.contains(c.day.stops[$0].id) }
        guard open.count >= 2, !c.day.stops[open[0]].locked, !c.day.stops[open[1]].locked else { return nil }
        return (open[0], open[1])
    }

    private func late(_ minutes: Int) {
        guard let c = context else { return }
        let stop = c.progress.atStopId.flatMap { id in c.day.stops.first { $0.id == id } }
        store.record(.delayed, tripId: tripId, stop: stop, detail: ["seconds": .number(Double(minutes * 60))])
        options = TripOptionsRequest(
            tripId: tripId, date: date, reason: .late(minutes),
            nowMin: c.clock.minutes(Date()) + Double(minutes), position: TripPosition.latest
        )
    }

    private func skip(_ stop: PlannedStop) {
        store.record(.skipped, tripId: tripId, stop: stop)
        TripArrivals.shared.refresh()
        options = TripOptionsRequest(tripId: tripId, date: date, reason: .skipped(stop.title), nowMin: nil, position: TripPosition.latest)
    }

    private func swap() {
        guard let pair = swappable else { return }
        options = TripOptionsRequest(tripId: tripId, date: date, reason: .swap(pair.0, pair.1), nowMin: nil, position: TripPosition.latest)
    }
}

/// One turn: the person's on the right, the planner's on the left, and a
/// form edit made on the site as a quiet line in the middle.
struct TripMessageBubble: View {
    let message: TripMessage

    var body: some View {
        switch message.role {
        case .event:
            Text(message.text)
                .font(SR.Text.mono(12))
                .foregroundStyle(SR.inkMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(SR.Text.body(15))
                    .foregroundStyle(SR.cream)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .srGlass(.ink, in: RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
            }
            .accessibilityLabel("You: \(message.text)")
        case .assistant:
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.text)
                        .font(SR.Text.body(15))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !message.ops.isEmpty {
                        Text(message.ops.count == 1 ? "Changed 1 thing" : "Changed \(message.ops.count) things")
                            .font(SR.Text.mono(11))
                            .foregroundStyle(SR.inkMuted)
                    }
                    if let research = message.research, !research.isEmpty {
                        TripResearchList(steps: research)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .srGlass(.paper, in: RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
                Spacer(minLength: 48)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// "What I looked up": the planner's research for a reply, folded away
/// until asked for, each step with its sources.
struct TripResearchList: View {
    let steps: [ResearchStep]
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.summary)
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(TripLinkButtons.sourceLinks(step.sources), id: \.url) { link in
                            Link(link.title, destination: link.url)
                                .font(SR.Text.mono(12))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Text(steps.count == 1 ? "What I looked up" : "What I looked up (\(steps.count))")
                .font(SR.Text.label(12))
                .foregroundStyle(SR.inkMuted)
        }
        .tint(SR.inkMuted)
        .accessibilityIdentifier("trip-research")
    }
}

/// The planner's options for an open question, as cards: what it is and why
/// (the planner's), what it does to the day (the solver's), indoor or out,
/// children, price — and one button that adds it (or suggests it).
struct TripOptionCards: View {
    let tripId: String
    let options: [PlanOption]
    let bundle: TripBundle
    @ObservedObject private var store = TripStore.shared
    @State private var busy: String?
    @State private var done: Set<String> = []
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose one — each is checked against your day")
                .font(SR.Text.label(12))
                .foregroundStyle(SR.inkMuted)
            ForEach(options) { option in card(option) }
            if let message {
                Text(message).font(SR.Text.secondary(12)).foregroundStyle(SR.inkSecondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-options-cards")
    }

    private var editor: Bool { bundle.can.canEdit || bundle.can.canApprove }

    private func card(_ option: PlanOption) -> some View {
        let stage = DayStage(rawValue: option.stage) ?? .afternoon
        let zone = TripClock(bundle.trip.timeZone).zone
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(stage.color).frame(width: 8, height: 8).accessibilityHidden(true)
                Text("\(TripFormat.day(option.date, zone: zone)) · \(stage.label)")
                    .font(SR.Text.mono(11))
                    .foregroundStyle(SR.inkMuted)
            }
            Text(option.title).font(SR.Text.title(16)).foregroundStyle(SR.ink)
            if !option.why.isEmpty {
                Text(option.why).font(SR.Text.secondary(13)).foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(option.fit)
                .font(SR.Text.mono(12))
                .foregroundStyle(option.verdict.fits ? SR.inkSecondary : SR.warn)
                .fixedSize(horizontal: false, vertical: true)
            let chips = [
                option.indoor.map { $0 ? "Indoors" : "Outdoors" },
                option.kidFriendly.map { $0 ? "Good with children" : "Better for adults" },
                option.costText,
            ].compactMap { $0 }
            if !chips.isEmpty {
                Text(chips.joined(separator: " · ")).font(SR.Text.secondary(12)).foregroundStyle(SR.inkMuted)
            }
            Button { choose(option, stage: stage) } label: {
                if busy == option.id { ProgressView() } else if done.contains(option.id) {
                    TripButtonLabel(editor ? "Added" : "Suggested", icon: "checkmark")
                } else {
                    TripButtonLabel(editor ? "Add this" : "Suggest this", icon: "plus", fill: true)
                }
            }
            .srButton(.prominent)
            .controlSize(.small)
            .disabled(busy != nil || done.contains(option.id))
            .accessibilityIdentifier("trip-option-choose")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Capsule().fill(stage.color).frame(width: 3).padding(.vertical, 10) }
        .srGlassCard(.paper)
    }

    private func choose(_ option: PlanOption, stage: DayStage) {
        busy = option.id
        message = nil
        let idea = TripIdea(title: option.title, why: option.why, fit: option.fit, wish: option.wish, verdict: option.verdict, source: "planner")
        Task {
            let failure: String?
            if editor {
                failure = await store.add(idea, tripId: tripId, date: option.date, stage: stage)
            } else {
                failure = await store.suggest(option.wish, tripId: tripId, date: option.date, stage: stage, note: option.why, fitText: option.fit)
            }
            busy = nil
            if let failure {
                SRHaptic.bad()
                message = failure
            } else {
                SRHaptic.ok()
                done.insert(option.id)
                if !editor { message = "Suggested — a parent will see it." }
            }
        }
    }
}
