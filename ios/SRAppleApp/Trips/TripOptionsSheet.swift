import SwiftUI

/// Why the options were asked for.
enum TripOptionsReason: Hashable {
    /// Arrival detection says the day is behind.
    case behind
    /// "I'm running late" by this many minutes.
    case late(Int)
    /// This stop was just skipped.
    case skipped(String)
    /// Swap the visits at these two stop indexes.
    case swap(Int, Int)
}

struct TripOptionsRequest: Identifiable, Hashable {
    let id = UUID()
    let tripId: String
    let date: String
    let reason: TripOptionsReason
    /// Local minutes to re-plan from; nil = now.
    let nowMin: Double?
    let position: TripLatLng?
}

/// Up to three ways to carry on, worked out on the phone (no signal
/// needed), and the server's own when there is signal. One tap applies one.
struct TripOptionsSheet: View {
    let request: TripOptionsRequest
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var network = TripNetwork.shared
    @State private var local: [ReplanOption] = []
    @State private var server: [ReplanOption] = []
    @State private var serverState: ServerState = .idle

    private enum ServerState: Equatable { case idle, asking, answered, failed(String) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if local.isEmpty {
                        Text("Nothing to re-plan — the rest of the day is already done or fixed.")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .srPlainRow()
                    }
                    ForEach(local) { option in row(option) }
                } header: {
                    SRSectionLabel(text: "On this phone")
                }
                serverSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .srPaper()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
            }
        }
        .task {
            local = TripReplanning.localOptions(request, store: store)
            await askServer()
        }
        .accessibilityIdentifier("trip-options")
    }

    private var title: String {
        switch request.reason {
        case .behind: return "Catch up"
        case .late(let m): return "\(m) min late"
        case .skipped(let name): return "Skipped \(name)"
        case .swap: return "Swap"
        }
    }

    @ViewBuilder
    private var serverSection: some View {
        switch serverState {
        case .idle:
            EmptyView()
        case .asking:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Asking the site for more…").font(SR.Text.secondary()).foregroundStyle(SR.inkMuted)
                }
                .srPlainRow()
            } header: { SRSectionLabel(text: "From the site") }
        case .answered:
            if !server.isEmpty {
                Section {
                    ForEach(server) { option in row(option) }
                } header: { SRSectionLabel(text: "From the site") }
            }
        case .failed(let why):
            Section {
                Text(why).font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted).srPlainRow()
            } header: { SRSectionLabel(text: "From the site") }
        }
    }

    private func row(_ option: ReplanOption) -> some View {
        Button {
            SRHaptic.ok()
            store.apply(option, tripId: request.tripId)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(option.label)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(TripReplanning.endsLine(option))
                    .font(SR.Text.mono(12))
                    .foregroundStyle(SR.inkMuted)
                ForEach(TripReplanning.preview(option, request: request, store: store), id: \.self) { line in
                    Text(line)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                }
                if !option.dropped.isEmpty {
                    Text("Leaves out " + option.dropped.map { store.bundles[request.tripId]?.wish($0)?.title ?? $0 }.joined(separator: ", "))
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.warn)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .srPlainRow()
        .accessibilityHint("Applies this to the rest of the day")
        .accessibilityIdentifier("trip-option-\(option.id)")
    }

    private func askServer() async {
        guard network.online, !SRDemo.isOn, let body = TripReplanning.serverBody(request, store: store) else { return }
        serverState = .asking
        do {
            let answer = try await TripsAPI.replan(body, trip: request.tripId)
            let seen = Set(local.map { TripReplanning.key($0.day) })
            server = answer.filter { !seen.contains(TripReplanning.key($0.day)) }
            serverState = .answered
        } catch {
            serverState = .failed("The site could not be asked: \(error.localizedDescription)")
        }
    }
}

/// The glue between the Day screen and the solver port: inputs from the
/// store, options out, and how they are described.
@MainActor
enum TripReplanning {
    struct Inputs {
        let bundle: TripBundle
        let day: PlannedDay
        let progress: TripProgress
        let nowMin: Double
        let clock: TripClock
    }

    static func inputs(_ request: TripOptionsRequest, store: TripStore, now: Date = Date()) -> Inputs? {
        guard let bundle = store.bundles[request.tripId],
              let day = store.day(request.tripId, request.date),
              let clock = store.clock(request.tripId) else { return nil }
        let nowMin = request.nowMin ?? clock.minutes(now)
        let progress = TripProgress.of(day: day, marks: store.marks(request.tripId), nowMin: clock.minutes(now), clock: clock)
        return Inputs(bundle: bundle, day: day, progress: progress, nowMin: nowMin, clock: clock)
    }

    static func context(_ bundle: TripBundle, date: String) -> TripReplan.Context {
        TripReplan.Context(
            trip: bundle.trip, stays: bundle.stays, wishes: bundle.wishes, bookings: bundle.bookings,
            matrix: bundle.matrices[date] ?? TravelMatrix(points: [], seconds: [:], metres: [:], estimated: [:]),
            transport: bundle.segments
        )
    }

    static func localOptions(_ request: TripOptionsRequest, store: TripStore) -> [ReplanOption] {
        guard let i = inputs(request, store: store) else { return [] }
        let context = context(i.bundle, date: request.date)
        var out: [ReplanOption] = []
        if case .swap(let a, let b) = request.reason, a < i.day.stops.count, b < i.day.stops.count {
            var swapped = i.day
            swapped.stops.swapAt(a, b)
            let from = min(a, b)
            // Setting off for the first of the pair: from the stop you are
            // at when its time comes, or now when already on the way.
            let start: Double
            if case .at(let here) = i.progress.phase, here < from {
                start = max(i.nowMin, i.day.stops[here].departMin)
            } else {
                start = i.nowMin
            }
            let retimed = TripReplan.retimeDay(swapped, fromIndex: from, startMin: start, context: context)
            out.append(ReplanOption(
                id: "swap:\(i.day.stops[a].id),\(i.day.stops[b].id)",
                label: "Swap \(i.day.stops[a].title) and \(i.day.stops[b].title)",
                kind: .swap, day: retimed, dropped: [],
                endsLaterMin: (retimed.stops.last?.departMin ?? 0) - (i.day.stops.last?.departMin ?? 0)
            ))
        }
        let replanned = TripReplan.replanDay(TripReplan.Input(
            context: context, day: i.day, nowMin: i.nowMin, position: request.position,
            atStopId: i.progress.atStopId, doneStopIds: i.progress.doneStopIds
        ))
        let seen = Set(out.map { key($0.day) })
        out += replanned.filter { !seen.contains(key($0.day)) }
        return Array(out.prefix(3))
    }

    static func serverBody(_ request: TripOptionsRequest, store: TripStore) -> TripReplanBody? {
        guard let i = inputs(request, store: store) else { return nil }
        return TripReplanBody(
            date: request.date, nowMin: i.nowMin.rounded(), position: request.position,
            atStopId: i.progress.atStopId, doneStopIds: i.progress.doneStopIds
        )
    }

    /// The same day said twice is offered once.
    static func key(_ day: PlannedDay) -> String {
        day.stops.map { "\($0.id)@\($0.arriveMin)-\($0.departMin)" }.joined(separator: "|")
    }

    /// "Back at 18:40 · 25 min later".
    nonisolated static func endsLine(_ option: ReplanOption) -> String {
        let end = option.day.stops.last.map { TripFormat.time($0.arriveMin) } ?? "—"
        let delta = Int(option.endsLaterMin.rounded())
        let change = delta == 0 ? "same as planned" : delta > 0 ? "\(delta) min later" : "\(-delta) min earlier"
        return "Back at \(end) · \(change)"
    }

    /// The next three stops as the option has them: "14:35 Pantheon".
    static func preview(_ option: ReplanOption, request: TripOptionsRequest, store: TripStore) -> [String] {
        let done = Set(store.progress(request.tripId, request.date)?.doneStopIds ?? [])
        let nowMin = request.nowMin ?? store.clock(request.tripId).map { $0.minutes(Date()) } ?? 0
        return option.day.stops
            .filter { $0.kind != .stay && !done.contains($0.id) && $0.departMin >= nowMin }
            .prefix(3)
            .map { "\(TripFormat.time($0.arriveMin))  \($0.title)" }
    }
}
