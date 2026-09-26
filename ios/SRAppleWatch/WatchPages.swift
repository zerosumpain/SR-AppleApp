import SwiftUI

// MARK: - Today

/// Three rings — Move (read here), Recovery and Readiness (from the phone) —
/// then the figures /health leads with, and a way to start a question.
struct WatchTodayPage: View {
    @EnvironmentObject private var model: WatchModel
    @EnvironmentObject private var move: WatchMove

    private var snapshot: WatchSnapshot { model.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ring(label: "MOVE", fraction: move.reading?.fraction,
                         value: move.reading.map { "\(Int(($0.fraction * 100).rounded()))" } ?? "—",
                         tint: WatchInk.accent)
                    ring(label: "RECOV", fraction: snapshot.recovery?.fraction,
                         value: snapshot.recovery?.display ?? "—", tint: WatchInk.good)
                    ring(label: "READY", fraction: snapshot.readiness?.fraction,
                         value: snapshot.readiness?.display ?? "—", tint: WatchInk.warn)
                }

                if let readiness = snapshot.readiness {
                    Text(readiness.label.uppercased())
                        .font(WatchInk.label())
                        .foregroundStyle(WatchInk.accent)
                        .lineLimit(1)
                }

                if move.needsPermission {
                    Button("Show my Move ring") {
                        Task { await move.requestPermission() }
                    }
                    .font(WatchInk.mono(12))
                }

                ForEach(snapshot.figures) { figure in
                    HStack(alignment: .firstTextBaseline) {
                        Text(figure.label.uppercased())
                            .font(WatchInk.label())
                            .foregroundStyle(WatchInk.creamFaint)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(figure.display)
                            .font(WatchInk.figure(15))
                            .foregroundStyle(WatchInk.cream)
                        if let unit = figure.unit {
                            Text(unit).font(WatchInk.mono(11)).foregroundStyle(WatchInk.creamFaint)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                if snapshot.canAsk {
                    // Dictated here, sent to the phone's composer UNSENT: a turn
                    // sent where you cannot watch it go wrong is not sent for you.
                    TextFieldLink(prompt: Text("Ask jkai")) {
                        Label("Ask jkai", systemImage: "sparkle")
                            .font(WatchInk.mono(13))
                    } onSubmit: { question in
                        model.send(.ask(question: question), key: "ask")
                    }
                    .tint(WatchInk.accent)
                }

                Text(freshness)
                    .font(WatchInk.mono(11))
                    .foregroundStyle(model.isStale ? WatchInk.warn : WatchInk.creamFaint)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Today")
    }

    private func ring(label: String, fraction: Double?, value: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            WatchRing(fraction: fraction, value: value, tint: tint)
                .frame(width: 44, height: 44)
            Text(label)
                .font(WatchInk.label(10))
                .foregroundStyle(WatchInk.creamFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.capitalized) \(value)")
    }

    private var freshness: String {
        if snapshot.generatedAt == .distantPast { return "Open the iPhone app to connect" }
        return "From iPhone · \(watchAgo(snapshot.generatedAt)) ago"
    }
}

// MARK: - Alerts

/// Today's uncleared alerts. Swipe to mark read or clear; the phone does it.
struct WatchAlertsPage: View {
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        List {
            if model.snapshot.connectionNeedsFixing {
                Label("A connection needs fixing on your iPhone", systemImage: "key.slash")
                    .font(WatchInk.mono(12))
                    .foregroundStyle(WatchInk.bad)
            }
            if model.snapshot.alerts.isEmpty {
                Text("Nothing to report.")
                    .font(WatchInk.mono(13))
                    .foregroundStyle(WatchInk.creamFaint)
            }
            ForEach(model.snapshot.alerts) { alert in
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(WatchInk.severity(alert.severity)).frame(width: 6, height: 6).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.title)
                            .font(.system(.footnote))
                            .foregroundStyle(WatchInk.cream)
                            .lineLimit(3)
                        Text(watchAgo(alert.createdAt))
                            .font(WatchInk.mono(11))
                            .foregroundStyle(WatchInk.creamFaint)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button { model.clear(alert) } label: { Label("Clear", systemImage: "xmark") }
                        .tint(WatchInk.creamFaint)
                    Button { model.markRead(alert) } label: { Label("Read", systemImage: "checkmark") }
                        .tint(WatchInk.good)
                }
            }
        }
        .navigationTitle(model.snapshot.unread > 0 ? "Alerts · \(model.snapshot.unread)" : "Alerts")
    }
}

// MARK: - Pinned workflows

/// Up to three workflows the owner pinned on the phone. Each run asks first:
/// a tap on a wrist is too easy to make by accident for a side effect.
struct WatchFlowsPage: View {
    @EnvironmentObject private var model: WatchModel
    @State private var confirming: WatchSnapshot.PinnedFlow?

    var body: some View {
        List(model.snapshot.pinnedFlows) { flow in
            Button {
                confirming = flow
            } label: {
                HStack {
                    Text(flow.title)
                        .font(.system(.footnote))
                        .foregroundStyle(WatchInk.cream)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if model.busy.contains("run-\(flow.slug)") {
                        ProgressView()
                    } else {
                        Image(systemName: "play.fill").foregroundStyle(WatchInk.accent)
                    }
                }
            }
            .disabled(model.busy.contains("run-\(flow.slug)"))
        }
        .navigationTitle("Workflows")
        .confirmationDialog(
            confirming.map { "Run \($0.title)?" } ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            if let flow = confirming {
                Button("Run") { model.send(.runFlow(slug: flow.slug), key: "run-\(flow.slug)") }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Status

/// "An app that switches its own sensor off has to be watchable." The upload
/// queue, the last upload, the motion gate, and Sync now.
struct WatchStatusPage: View {
    @EnvironmentObject private var model: WatchModel

    private var sync: WatchSnapshot.Sync { model.snapshot.sync }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                row("QUEUED", sync.queued == 0 ? "Nothing" : "\(sync.queued)")
                row("LAST UPLOAD", sync.lastUpload.map { "\(watchAgo($0)) ago" } ?? "—")
                row("LOCATION", gateLine)

                Button {
                    model.send(.syncNow, key: "sync")
                } label: {
                    if model.busy.contains("sync") {
                        ProgressView()
                    } else {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(model.busy.contains("sync"))
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("iPhone")
    }

    private var gateLine: String {
        guard let gate = sync.gate else { return "Off" }
        switch gate {
        case "tracking": return "Tracking"
        case "armed": return "Asleep until you move"
        default: return gate.capitalized
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(WatchInk.label(10)).foregroundStyle(WatchInk.creamFaint)
            Text(value).font(WatchInk.mono(14)).foregroundStyle(WatchInk.cream)
        }
        .accessibilityElement(children: .combine)
    }
}
