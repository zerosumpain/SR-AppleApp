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
    @State private var sending = false
    /// This session's turns, until the refreshed bundle carries them.
    @State private var session: [TripMessage] = []
    @State private var last: ConverseResult?
    @State private var failure: String?
    @State private var options: TripOptionsRequest?
    @FocusState private var typing: Bool

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
                            Text("Tell the planner what to change. It answers here, and the plan updates behind this sheet.")
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
                        if sending {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("The planner is thinking…").font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted)
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
            .navigationTitle("Edit plan")
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

    private var messages: [TripMessage] {
        let saved = (store.bundles[tripId]?.messages ?? []).sorted { $0.createdAt < $1.createdAt }
        let ids = Set(saved.map(\.id))
        return saved + session.filter { !ids.contains($0.id) }
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
        let replies = (last?.quickReplies.isEmpty == false ? last?.quickReplies : nil) ?? Self.starters
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
        failure = nil
        let now = TripStore.iso(Date())
        session.append(TripMessage(id: "local-\(UUID().uuidString)", role: .user, text: said, ops: [], planVersion: nil, surface: "phone", createdAt: now))
        sending = true
        Task {
            defer { sending = false }
            do {
                let result = try await TripsAPI.converse(said, trip: tripId)
                last = result
                session.append(TripMessage(
                    id: "local-\(UUID().uuidString)", role: .assistant, text: result.reply, ops: result.applied,
                    planVersion: result.planVersion, surface: "phone", createdAt: TripStore.iso(Date())
                ))
                SRHaptic.ok()
                // The planner changed the plan: show the server's version now.
                if result.planVersion != nil || !result.applied.isEmpty {
                    await store.adoptServerPlan(tripId)
                }
            } catch {
                SRHaptic.bad()
                failure = (error as? TripsAPI.Failure) == .ownerOnly
                    ? "Trips are owner-only for now."
                    : "Not sent: \(error.localizedDescription). Nothing was saved to send later."
            }
        }
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
