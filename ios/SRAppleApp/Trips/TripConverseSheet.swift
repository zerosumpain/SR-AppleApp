import SwiftUI

/// "Edit plan": the planning conversation, on the phone.
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
    @FocusState private var typing: Bool

    /// What this person may do with the trip.
    private var can: TripAccess { store.bundles[tripId]?.can ?? .owner }

    /// For someone who can ask but not change.
    static let adviceStarters = [
        "What's good near here for kids?",
        "Is there time for an ice cream this afternoon?",
        "What should I pack for tomorrow?",
    ]

    /// What to say when there is nothing yet to follow up.
    static let starters = [
        "We're running about 20 minutes late",
        "Skip the next stop",
        "Swap the next two",
        "Make the rest of today lighter",
    ]

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
                        if case .running(let since, _) = jobs.states[key] {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("The planner is thinking… \(max(0, Int(context.date.timeIntervalSince(since)))) s")
                                        .font(SR.Text.secondary(13))
                                        .foregroundStyle(SR.inkMuted)
                                        .monospacedDigit()
                                    Spacer(minLength: 4)
                                    Button("Cancel") { jobs.cancel(key) }
                                        .font(SR.Text.label(12))
                                }
                            }
                            .id("thinking")
                        }
                        if let failure {
                            Label(failure, systemImage: "exclamationmark.triangle")
                                .font(SR.Text.secondary(13))
                                .foregroundStyle(SR.error)
                        }
                    }
                    .padding(SR.gutter)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { scroller.scrollTo(messages.last?.id ?? "thinking", anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .srPaper()
            .navigationTitle(can.canEdit ? "Edit plan" : "Ask the planner")
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
            .sheet(item: $options) { request in
                TripOptionsSheet(request: request)
                    .presentationDetents([.medium, .large])
            }
        }
        .accessibilityIdentifier("trip-converse")
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
                        .srGlass(.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityIdentifier("trip-converse-field")
                    Button { send(draft) } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
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
            ?? (can.canEdit ? Self.starters : Self.adviceStarters)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(replies, id: \.self) { reply in
                    Button { send(reply) } label: {
                        Text(reply).font(SR.Text.secondary(13)).lineLimit(1)
                    }
                    .srButton(.regular)
                    .controlSize(.small)
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
                } label: { SRButtonLabel(title: "Running late", icon: "clock") }
                Menu {
                    ForEach(skippable, id: \.id) { stop in
                        Button(stop.title) { skip(stop) }
                    }
                } label: { SRButtonLabel(title: "Skip", icon: "forward") }
                .disabled(skippable.isEmpty)
                Button { swap() } label: { SRButtonLabel(title: "Swap", icon: "arrow.up.arrow.down") }
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
                    .srGlass(.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                .srGlass(.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
