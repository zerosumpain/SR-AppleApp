import SwiftUI
import CoreLocation

// v5: trips for the whole family — a new trip by talking to the planner,
// "Make a suggestion" in each stage of a day, suggestions waiting for a
// parent, and every leg in the mode you would rather take.

// MARK: - A new trip, in a sentence

/// "Type instead": the planner's opening question, and the first message
/// makes the trip (`POST /api/native/trips`). It opens as soon as it exists,
/// with the conversation carrying on. v8: the guided start (`TripStartFlow`)
/// is the main way in; this is its "or just tell the planner", pushed inside
/// that sheet's navigation — never a sheet of its own.
struct TripStartTextView: View {
    let onCreated: (String) -> Void
    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var network = TripNetwork.shared
    /// Making a trip asks the planner: a job (v6), kept by `TripJobs`.
    @ObservedObject private var jobs = TripJobs.shared
    @State private var draft = ""
    @FocusState private var typing: Bool

    private var key: String { TripJobs.createKey }
    private var sending: Bool { jobs.isRunning(key) }
    private var failure: String? {
        if case .failed(let why) = jobs.states[key] { return "Not made: \(why)" }
        return nil
    }

    static let starters = [
        "A long weekend in Rome at the end of October",
        "Half term somewhere warm with the kids",
        "Edinburgh for two nights, by train",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TripMessageBubble(message: TripMessage(
                    id: "new-trip-ask", role: .assistant,
                    text: "Where to, when, and who's coming? Say it however it comes — I'll assume what I need to and show you, look up the journey, and draft a plan you can change.",
                    ops: [], planVersion: nil, surface: "phone", createdAt: ""
                ))
                if case .running(_, let asked) = jobs.states[key] {
                    TripMessageBubble(message: TripMessage(
                        id: "new-trip-said", role: .user, text: asked ?? "", ops: [], planVersion: nil, surface: "phone", createdAt: ""
                    ))
                    // Staged progress when the server reports it; never a seconds counter.
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(jobs.stages[key]?.first { $0.state == .running }?.label.appending("…") ?? "Making the trip…")
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.inkMuted)
                        Spacer(minLength: 4)
                        Button("Cancel") { jobs.cancel(key) }.font(SR.Text.title(14))
                    }
                }
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.error)
                }
            }
            .padding(SR.gutter)
        }
        .safeAreaInset(edge: .bottom) { composer }
        .srPaper()
        .navigationTitle("Tell the planner")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { typing = true }
        // Made: open it (also when it finished while this was away).
        .onChange(of: jobs.created[key]) { _, id in
            guard let id else { return }
            jobs.clear(key)
            onCreated(id)
        }
        .accessibilityIdentifier("trip-new")
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if network.online || SRDemo.isOn {
                TripFlow(spacing: 8, lineSpacing: 8) {
                    ForEach(Self.starters, id: \.self) { starter in
                        Button { draft = starter } label: { TripChip(starter, style: .tradeoff) }
                            .buttonStyle(.plain)
                    }
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Rome, 27–30 Oct, staying near Campo de' Fiori…", text: $draft, axis: .vertical)
                        .font(SR.Text.body(16))
                        .lineLimit(1...6)
                        .focused($typing)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .srGlass(.paper, in: RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
                        .accessibilityIdentifier("trip-new-field")
                    Button { send() } label: {
                        Image(systemName: "arrow.up.circle.fill").font(SR.Text.display(30))
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                    .accessibilityLabel("Start the trip")
                }
            } else {
                Label("Starting a trip needs a connection.", systemImage: "wifi.slash")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
            }
        }
        .padding(.horizontal, SR.gutter)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        SRHaptic.tap()
        draft = ""
        jobs.create(text)
    }
}

// MARK: - A stage's suggestions and ideas

/// Under each stage of a day: what the family has suggested for it (a
/// parent approves or rejects right here), and "Make a suggestion" — ideas
/// that fit this slot, from the planner, without opening the chat.
struct TripSlotPanel: View {
    let tripId: String
    let day: PlannedDay
    let stage: DayStage
    let indexes: [Int]
    let bundle: TripBundle
    /// Its own "Make a suggestion" button. The read-only day keeps one menu
    /// for the whole day instead (`TripDayIdeasMenu`); the panel still shows
    /// what the family suggested and the ideas that came back for this part.
    var showsAsk = true
    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var network = TripNetwork.shared
    @ObservedObject private var jobs = TripJobs.shared
    @Environment(\.tripOnDark) private var onDark
    @State private var busy: String?
    @State private var message: String?

    private var can: TripAccess { bundle.can }
    /// The ask runs as a job (v6), kept by `TripJobs`: it survives this
    /// view going away, the app going to the background, or a relaunch.
    private var key: String { TripJobs.ideasKey(tripId, day.date, stage) }
    private var reply: TripIdeasReply? { jobs.ideas[key] }
    private var muted: Color { onDark ? SR.creamOnDark : SR.inkMuted }

    private var pending: [TripSuggestion] {
        (bundle.suggestions ?? []).filter { $0.pending && $0.date == day.date && $0.stage == stage.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(pending) { suggestion in
                TripSuggestionCard(suggestion: suggestion, canApprove: can.canApprove, busy: busy == suggestion.id) { action in
                    decide(suggestion, action)
                }
            }
            if let reply {
                ForEach(reply.ideas.prefix(3)) { idea in
                    TripIdeaCard(idea: idea, actionLabel: can.canEdit || can.canApprove ? "Add this" : "Suggest this",
                                 busy: busy == idea.id) { take(idea) }
                }
                if reply.ideas.isEmpty {
                    nothingFitted(reply)
                } else {
                    if let note = reply.note {
                        Text(note).font(SR.Text.secondary(13)).foregroundStyle(muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 14) {
                        Button("Other ideas") { ask() }
                        Button("Put the ideas away") { jobs.clear(key) }
                    }
                    .font(SR.Text.label(12))
                    .foregroundStyle(muted)
                }
            } else if case .running(let since, _) = jobs.states[key] {
                // Elapsed seconds, so a long think reads as progress, not a hang.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Looking for something that fits… \(max(0, Int(context.date.timeIntervalSince(since)))) s")
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(muted)
                            .monospacedDigit()
                        Spacer(minLength: 4)
                        Button("Cancel") { jobs.cancel(key) }
                            .font(SR.Text.label(12))
                            .foregroundStyle(onDark ? SR.accentOnDark : SR.accentDeep)
                    }
                }
                .accessibilityIdentifier("trip-suggest-running")
            } else if case .failed(let why) = jobs.states[key] {
                VStack(alignment: .leading, spacing: 6) {
                    Text(why).font(SR.Text.secondary(13)).foregroundStyle(onDark ? SR.errorOnDark : SR.error)
                        .fixedSize(horizontal: false, vertical: true)
                    tryAgain
                }
            } else if showsAsk && (can.canSuggest || can.canEdit) {
                Button { ask() } label: {
                    Label("Make a suggestion", systemImage: "sparkles")
                        .font(SR.Text.label(12))
                        .foregroundStyle(onDark ? SR.accentOnDark : SR.accentDeep)
                }
                .buttonStyle(.plain)
                .disabled(!(network.online || SRDemo.isOn))
                .accessibilityHint(network.online ? "Ideas for \(stage.label.lowercased()) that fit the plan" : "Needs a connection")
                .accessibilityIdentifier("trip-suggest-\(stage.rawValue)")
            }
            if let message {
                Text(message).font(SR.Text.secondary(12)).foregroundStyle(onDark ? SR.errorOnDark : SR.error)
            }
        }
        .padding(.vertical, 6)
    }

    /// Nothing fitted: the server's note and each idea it turned down, with
    /// why, then "Try again".
    private func nothingFitted(_ reply: TripIdeasReply) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(reply.note ?? "Nothing found that fits this slot.")
                .font(SR.Text.secondary(13))
                .foregroundStyle(onDark ? SR.cream : SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(reply.rejected ?? [], id: \.self) { turned in
                Text("\(turned.title) — \(turned.reason)")
                    .font(SR.Text.secondary(12))
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            tryAgain
        }
        .accessibilityIdentifier("trip-suggest-nothing")
    }

    private var tryAgain: some View {
        Button { ask() } label: { TripButtonLabel("Try again", icon: "arrow.clockwise") }
            .srButton(.regular)
            .controlSize(.small)
            .disabled(!(network.online || SRDemo.isOn))
            .accessibilityIdentifier("trip-suggest-retry")
    }

    private func ask() {
        SRHaptic.tap()
        message = nil
        Self.ask(tripId: tripId, day: day, stage: stage, indexes: indexes)
    }

    /// Ideas for one part of the day: the stops either side of it go with
    /// the ask, so the planner knows the gap.
    static func ask(tripId: String, day: PlannedDay, stage: DayStage, indexes: [Int]) {
        var after: String?
        var before: String?
        if let first = indexes.first, let last = indexes.last {
            after = first > 0 ? day.stops[first - 1].id : nil
            before = last + 1 < day.stops.count ? day.stops[last + 1].id : nil
        }
        TripJobs.shared.askIdeas(tripId: tripId, date: day.date, stage: stage, after: after, before: before)
    }

    private func take(_ idea: TripIdea) {
        busy = idea.id
        Task {
            let failure: String?
            if can.canEdit || can.canApprove {
                failure = await store.add(idea, tripId: tripId, date: day.date, stage: stage)
            } else {
                failure = await store.suggest(idea.wish, tripId: tripId, date: day.date, stage: stage, note: idea.why, fitText: idea.fit)
            }
            busy = nil
            if let failure {
                SRHaptic.bad()
                message = failure
            } else {
                SRHaptic.ok()
                jobs.clear(key)
                message = can.canEdit || can.canApprove ? nil : "Suggested — a parent will see it."
            }
        }
    }

    private func decide(_ suggestion: TripSuggestion, _ action: String) {
        busy = suggestion.id
        Task {
            let failure = await store.decide(suggestion, action: action, tripId: tripId)
            busy = nil
            if let failure { SRHaptic.bad(); message = failure } else { SRHaptic.ok() }
        }
    }
}

/// An idea from the planner: what, why, how it fits, and one button.
struct TripIdeaCard: View {
    let idea: TripIdea
    let actionLabel: String
    let busy: Bool
    let action: () -> Void
    @Environment(\.tripOnDark) private var onDark

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(idea.title).font(SR.Text.title(15)).foregroundStyle(onDark ? SR.cream : SR.ink)
                if idea.nearby {
                    // Found on the map around the gap, not by the planner.
                    Text("Nearby")
                        .font(SR.Text.label(12))
                        .foregroundStyle(onDark ? SR.creamOnDark : SR.inkMuted)
                        .accessibilityLabel("Found nearby")
                }
            }
            Text(idea.why).font(SR.Text.secondary(13)).foregroundStyle(onDark ? SR.creamOnDark : SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(idea.fit).font(SR.Text.mono(12)).foregroundStyle(onDark ? SR.creamOnDark : SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let out = idea.verdict?.pushesOut, !out.isEmpty {
                Text("Would push out " + out.joined(separator: ", "))
                    .font(SR.Text.secondary(12)).foregroundStyle(onDark ? SR.errorOnDark : SR.warn)
            }
            Button(action: action) {
                if busy { ProgressView() } else { TripButtonLabel(actionLabel, icon: "plus") }
            }
            .srButton(.prominent)
            .controlSize(.small)
            .disabled(busy)
            .accessibilityIdentifier("trip-idea-take")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((onDark ? Color.white : SR.ink).opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// "Sam suggests gelato" — waiting for a parent, who decides here.
struct TripSuggestionCard: View {
    let suggestion: TripSuggestion
    let canApprove: Bool
    let busy: Bool
    let decide: (String) -> Void
    @Environment(\.tripOnDark) private var onDark

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(suggestion.byName) suggests \(suggestion.wish.title)", systemImage: "hand.raised")
                .font(SR.Text.title(15))
                .foregroundStyle(onDark ? SR.accentOnDark : SR.accentDeep)
            if let note = suggestion.note ?? suggestion.fitText {
                Text(note).font(SR.Text.secondary(13)).foregroundStyle(onDark ? SR.creamOnDark : SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if canApprove {
                HStack(spacing: 8) {
                    Button { decide("approve") } label: { TripButtonLabel("Approve", icon: "checkmark") }
                        .srButton(.prominent)
                        .accessibilityIdentifier("trip-suggestion-approve")
                    Button { decide("reject") } label: { TripButtonLabel("Reject", icon: "xmark") }
                        .srButton(.regular)
                    if busy { ProgressView() }
                }
                .controlSize(.small)
                .disabled(busy)
            } else {
                Text("Waiting for a parent").font(SR.Text.mono(12)).foregroundStyle(onDark ? SR.creamOnDark : SR.inkMuted)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(onDark ? SR.accentOnDark : SR.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-suggestion")
    }
}

// MARK: - Every leg, in the mode you'd rather

/// The leg into a stop: a small route map, and Walk · Taxi · Transit with
/// each one's minutes. Picking another mode redraws the route from the
/// server (`…/route`) — display only; the plan keeps its own mode.
struct TripLegPicker: View {
    let tripId: String
    let date: String
    let leg: PlannedLeg
    let from: PlannedStop
    let to: PlannedStop
    @ObservedObject private var network = TripNetwork.shared
    @State private var mode: TravelMode
    @State private var drawn: [TravelMode: TripRoute] = [:]
    @State private var loading = false
    @State private var failure: String?

    init(tripId: String, date: String, leg: PlannedLeg, from: PlannedStop, to: PlannedStop) {
        self.tripId = tripId
        self.date = date
        self.leg = leg
        self.from = from
        self.to = to
        _mode = State(initialValue: leg.mode)
    }

    struct ModeOption: Hashable {
        let mode: TravelMode
        let minutes: Int
        let estimated: Bool
    }

    /// The modes to offer: the plan's own first, then the alternatives.
    private var options: [ModeOption] {
        var out = [ModeOption(mode: leg.mode, minutes: Int((leg.durationSec / 60).rounded()), estimated: leg.estimated)]
        for alt in leg.alternatives ?? [] where alt.mode != leg.mode && alt.mode != .unknown && !out.contains(where: { $0.mode == alt.mode }) {
            out.append(ModeOption(mode: alt.mode, minutes: Int((alt.durationSec / 60).rounded()), estimated: alt.estimated))
        }
        return out
    }

    private var line: [CLLocationCoordinate2D] {
        if mode != leg.mode, let route = drawn[mode], route.line.count > 1 {
            return route.line.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        }
        if let l = leg.line, l.count > 1 { return l.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } }
        return [from.location, to.location].compactMap { $0 }.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("How", selection: $mode) {
                ForEach(options, id: \.mode) { option in
                    Text("\(Self.name(option.mode)) \(option.minutes)′").tag(option.mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("trip-leg-modes")
            if line.count > 1 {
                SRRouteMap(route: line, interactive: false)
                    .id(mode)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
                    .accessibilityLabel("Route from \(from.title) to \(to.title), \(Self.name(mode))")
            }
            Text(caption)
                .font(SR.Text.mono(12))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            if mode != leg.mode, let guidance = drawn[mode]?.guidance {
                Text(guidance.summary).font(SR.Text.secondary(13)).foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: mode) { _, picked in load(picked) }
        .accessibilityIdentifier("trip-leg-picker")
    }

    private var caption: String {
        if loading { return "Drawing the \(Self.name(mode).lowercased()) route…" }
        if let failure { return failure }
        let minutes = options.first { $0.mode == mode }?.minutes ?? 0
        let est = (options.first { $0.mode == mode }?.estimated ?? true) ? " · approximate" : ""
        let plan = mode == leg.mode ? " · as planned" : " · just to look: the plan keeps \(Self.name(leg.mode).lowercased())"
        return "From \(from.title) · about \(minutes) min\(est)\(plan)"
    }

    private func load(_ picked: TravelMode) {
        guard picked != leg.mode, drawn[picked] == nil else { failure = nil; return }
        guard network.online || SRDemo.isOn else { failure = "Another route needs a connection — the times above still stand."; return }
        loading = true
        failure = nil
        Task {
            do {
                drawn[picked] = try await TripsAPI.route(trip: tripId, date: date, from: from.id, to: to.id, mode: picked)
            } catch {
                failure = "Couldn't draw that route: \(error.localizedDescription)"
            }
            loading = false
        }
    }

    static func name(_ mode: TravelMode) -> String {
        switch mode {
        case .walk: return "Walk"
        case .taxi: return "Taxi"
        case .transit: return "Transit"
        case .drive: return "Drive"
        case .cycle: return "Cycle"
        case .unknown: return "Other"
        }
    }
}

/// "Ideas for this day": one menu under the whole day, a part of the day to
/// ask about — instead of a "Make a suggestion" button in every part, which
/// made the read-only plan read as a form.
struct TripDayIdeasMenu: View {
    let tripId: String
    let day: PlannedDay
    let bundle: TripBundle
    @ObservedObject private var network = TripNetwork.shared

    var body: some View {
        if bundle.can.canSuggest || bundle.can.canEdit {
            let groups = TripStages.groups(day, wishes: bundle.wishes)
            Menu {
                ForEach(groups, id: \.stage) { group in
                    Button {
                        SRHaptic.tap()
                        TripSlotPanel.ask(tripId: tripId, day: day, stage: group.stage, indexes: group.indexes)
                    } label: {
                        Label(group.indexes.isEmpty ? "\(group.stage.label) — free" : group.stage.label, systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("trip-suggest-\(group.stage.rawValue)")
                }
            } label: {
                TripButtonLabel(bundle.can.canEdit ? "Ideas for this day" : "Make a suggestion", icon: "sparkles")
            }
            .srButton(.regular)
            .disabled(!(network.online || SRDemo.isOn))
            .accessibilityHint(network.online ? "Ideas that fit a part of the day" : "Needs a connection")
            .accessibilityIdentifier("trip-suggest-menu")
        }
    }
}
