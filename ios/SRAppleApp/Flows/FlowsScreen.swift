import SwiftUI

/// The site's workflows, from the phone.
///
/// Not the canvas. A canvas is a desk tool — a graph you arrange with a
/// pointer — and on a 390pt screen it would be a map you pinch at. What the
/// phone is for is the other half of owning a workflow: seeing which ones want
/// attention, running one, pausing a schedule, fixing the step that broke, and
/// asking jkai to change the rest. So it is a list, a column of steps, and
/// forms generated from the same field descriptions the web inspector uses.
struct FlowsScreen: View {
    @StateObject private var store = FlowListStore()
    @EnvironmentObject private var router: Router
    @State private var creating = false
    @State private var deleting: FlowSummary?

    var body: some View {
        List {
            if store.query.isEmpty {
                SRPageHeader(kicker: "Workflows", title: "Flows")
                    .srBareRow()
            }

            if !store.building.isEmpty {
                Section {
                    ForEach(store.building) { build in
                        FlowBuildingRow(build: build) { store.dismissBuild(build.slug) }
                            .srGlassRow()
                    }
                } header: {
                    SRSectionLabel(text: "Building")
                }
            }

            if !store.attention.isEmpty {
                Section {
                    ForEach(store.attention) { row($0) }
                } header: {
                    SRSectionLabel(text: "Needs attention", trailing: "\(store.attention.count)")
                }
            }

            if !store.rest.isEmpty {
                Section {
                    ForEach(store.rest) { row($0) }
                } header: {
                    if !store.attention.isEmpty { SRSectionLabel(text: "All workflows") }
                }
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.wire)
        .navigationTitle("Flows")
        // Inline, not large: a custom face in the large-title slot paints
        // nothing on iOS 26. See `SRChrome`.
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $store.query, prompt: "Search workflows")
        .srRefreshable { await store.load() }
        .task { if !store.loaded { await store.load() } }
        .toolbar {
            ToolbarItem(placement: .principal) { SRBarMark() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    SRHaptic.tap()
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New workflow")
                .accessibilityIdentifier("flow-new")
            }
        }
        .overlay {
            if store.loading && store.workflows.isEmpty {
                ProgressView().tint(SR.accent)
            } else if store.loaded && store.workflows.isEmpty && store.building.isEmpty {
                SREmpty(
                    title: store.query.isEmpty ? "No workflows yet" : "Nothing matches that",
                    icon: store.query.isEmpty ? "point.3.connected.trianglepath.dotted" : "magnifyingglass",
                    message: store.query.isEmpty ? "Describe one and jkai builds it, or start from a blank canvas." : nil,
                    actionLabel: store.query.isEmpty ? "New workflow" : nil,
                    action: store.query.isEmpty ? openNew : nil
                )
            }
        }
        .navigationDestination(for: FlowRef.self) { FlowDetailScreen(ref: $0).id($0.slug) }
        .navigationDestination(for: FlowRunRef.self) { FlowRunScreen(ref: $0).id($0.runId) }
        .sheet(isPresented: $creating) {
            FlowNewSheet(store: store) { created in
                creating = false
                if !created.building, !created.slug.isEmpty {
                    router.flows.append(FlowRef(slug: created.slug, title: "New workflow"))
                }
            }
        }
        .confirmationDialog(
            "Delete this workflow?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = deleting { Task { await store.delete(target) } }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Its steps, schedule and run history go, on the website too. This cannot be undone.")
        }
        .overlay(alignment: .bottom) {
            if let message = store.message { SRBanner(text: message).padding(.bottom, 4) }
        }
    }

    /// Declared `-> Void` and not written inline — a closure whose body is a
    /// bare `Task { }` infers `Task<(), Never>`, and coercing that crashed the
    /// compiler once (see `SREmpty`).
    private func openNew() {
        creating = true
    }

    private func runNow(_ flow: FlowSummary) {
        Task {
            if let runId = await store.run(flow) {
                router.flows.append(FlowRunRef(runId: runId, title: flow.title))
            }
        }
    }

    @ViewBuilder
    private func row(_ flow: FlowSummary) -> some View {
        NavigationLink(value: FlowRef(slug: flow.slug, title: flow.title)) {
            FlowRow(flow: flow, busy: store.busySlug == flow.slug)
        }
        .srGlassRow()
        .accessibilityIdentifier("flow-row-\(flow.slug)")
        // Run is the reversible verb; it lives on the swipe. Delete costs a
        // long press and a confirmation.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                SRHaptic.select()
                runNow(flow)
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .tint(SR.accent)
        }
        .contextMenu {
            Button { runNow(flow) } label: { Label("Run now", systemImage: "play") }
            if flow.trigger.kind == .cron {
                Button {
                    Task { await store.setEnabled(flow, !flow.trigger.enabled) }
                } label: {
                    Label(flow.trigger.enabled ? "Pause schedule" : "Resume schedule",
                          systemImage: flow.trigger.enabled ? "pause" : "clock.arrow.circlepath")
                }
            }
            Link(destination: SiteClient.shared.webURL("jkai/canvas/\(flow.slug)")) {
                Label("Open the canvas on the web", systemImage: "safari")
            }
            Divider()
            Button(role: .destructive) { deleting = flow } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// One workflow: what starts it, how it last went, and why it wants you.
struct FlowRow: View {
    let flow: FlowSummary
    var busy: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: flow.trigger.kind.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tone)
                .frame(width: 34, height: 34)
                .background(tone.opacity(0.12), in: Circle())
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(flow.title)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    if busy {
                        ProgressView().scaleEffect(0.7).tint(SR.accent)
                    } else if let run = flow.lastRun {
                        Image(systemName: run.state.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FlowTone.color(run.state))
                            .accessibilityLabel("Last run \(run.status)")
                    }
                }
                Text(triggerLine)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(2)
                if flow.needsAttention, let reason = flow.attentionReason {
                    Text(reason)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Text("\(flow.nodeCount) STEP\(flow.nodeCount == 1 ? "" : "S")")
                    if let run = flow.lastRun, let started = run.startedAt {
                        Text("RAN \(shortAgo(started).uppercased()) AGO")
                    }
                    if flow.trigger.kind == .cron && !flow.trigger.enabled {
                        Text("PAUSED").foregroundStyle(SR.warn)
                    }
                }
                .font(SR.Text.mono())
                .tracking(0.8)
                .foregroundStyle(SR.inkMuted)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: SR.tapTarget, alignment: .leading)
    }

    private var tone: Color { flow.needsAttention ? SR.error : SR.accentInk }

    private var triggerLine: String { flow.trigger.headline() }
}

enum FlowTone {
    static func color(_ state: FlowRunState) -> Color {
        switch state {
        case .running: return SR.accentInk
        case .succeeded: return SR.good
        case .partial: return SR.warn
        case .failed: return SR.error
        case .waiting: return SR.warn
        case .other: return SR.inkGhost
        }
    }
}

/// A workflow jkai is still putting together.
struct FlowBuildingRow: View {
    let build: FlowListStore.PendingBuild
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if build.error == nil {
                ProgressView().tint(SR.accent).frame(width: 34, height: 34)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SR.error)
                    .frame(width: 34, height: 34)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(build.title)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(build.error ?? "jkai is building it — this takes a minute or so.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(build.error == nil ? SR.inkMuted : SR.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if build.error != nil {
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityLabel("Dismiss")
            }
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("flow-building-\(build.slug)")
    }
}

/// New: describe it, or start blank.
struct FlowNewSheet: View {
    @ObservedObject var store: FlowListStore
    let done: (FlowCreated) -> Void
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case describe, blank
        var id: String { rawValue }
        var label: String { self == .describe ? "Describe it" : "Blank" }
    }

    @State private var mode: Mode = .describe
    @State private var title = ""
    @State private var prompt = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Start from", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if mode == .describe {
                    Section {
                        TextEditor(text: $prompt)
                            .font(SR.Text.body())
                            .frame(minHeight: 140)
                            .accessibilityIdentifier("flow-new-prompt")
                    } header: {
                        SRSectionLabel(text: "What should it do?")
                    } footer: {
                        Text("For example: “Every weekday at 7, read my calendar and the weather and WhatsApp me a one-paragraph brief.” jkai builds the steps; you can change any of them after.")
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.inkMuted)
                    }
                    .srGlassRow()
                }
                Section {
                    TextField(mode == .describe ? "Optional — jkai names it otherwise" : "Name", text: $title)
                        .font(SR.Text.body())
                        .accessibilityIdentifier("flow-new-title")
                } header: {
                    SRSectionLabel(text: "Title")
                }
                .srGlassRow()
            }
            .srGround(.wire)
            .navigationTitle("New workflow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView().tint(SR.accent)
                    } else {
                        Button(mode == .describe ? "Build" : "Create") { submit() }
                            .disabled(!canSubmit)
                            .accessibilityIdentifier("flow-new-submit")
                    }
                }
            }
        }
    }

    private var canSubmit: Bool {
        mode == .describe
            ? !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        sending = true
        Task {
            let created = await store.create(title: title, prompt: mode == .describe ? prompt : nil)
            sending = false
            if let created { done(created) }
        }
    }
}
