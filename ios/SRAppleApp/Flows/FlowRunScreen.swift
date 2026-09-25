import SwiftUI

/// One run: each step, how it went, how long it took, and what it said.
///
/// Followed live while it is running — re-read every two seconds, stopped by
/// leaving the screen — because the reason to open a run from the phone is
/// usually that you just pressed Run.
struct FlowRunScreen: View {
    let ref: FlowRunRef
    @StateObject private var store: FlowRunStore

    init(ref: FlowRunRef) {
        self.ref = ref
        _store = StateObject(wrappedValue: FlowRunStore(runId: ref.runId))
    }

    var body: some View {
        List {
            if let detail = store.detail {
                Section { summary(detail.run) }
                    .srGlassRow()
                Section {
                    if detail.steps.isEmpty {
                        Text(detail.run.state.isFinished ? "No steps recorded." : "Waiting for the first step…")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                    }
                    ForEach(detail.steps) { step in
                        FlowRunStepRow(step: step)
                    }
                } header: {
                    SRSectionLabel(text: "Steps", trailing: "\(detail.steps.count)")
                }
                .srGlassRow()
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.wire)
        .navigationTitle(ref.title)
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable { await store.load() }
        .task { await store.follow() }
        .overlay {
            if store.detail == nil {
                if let message = store.message {
                    SREmpty(title: "Could not load the run", icon: "exclamationmark.triangle", message: message)
                } else {
                    ProgressView().tint(SR.accent)
                }
            }
        }
    }

    private func summary(_ run: FlowRunSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if run.state == .running {
                    ProgressView().tint(SR.accentInk)
                } else {
                    Image(systemName: run.state.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FlowTone.color(run.state))
                }
                Text(flowStatusLabel(run.status))
                    .font(SR.Text.display(20))
                    .foregroundStyle(SR.ink)
                Spacer()
                if let duration = flowDuration(run.durationMs) {
                    Text(duration)
                        .font(SR.Text.mono(14))
                        .foregroundStyle(SR.inkSecondary)
                }
            }
            HStack(spacing: 10) {
                if let trigger = run.trigger { Text(trigger.uppercased()) }
                if let started = run.startedAt, let date = isoDate(started) {
                    Text(date.formatted(date: .abbreviated, time: .shortened).uppercased())
                }
            }
            .font(SR.Text.mono())
            .tracking(0.8)
            .foregroundStyle(SR.inkMuted)
            if let error = run.error {
                Text(error)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("flow-run-summary")
    }
}

struct FlowRunStepRow: View {
    let step: FlowRunStep
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: step.state.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FlowTone.color(step.state))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.label)
                        .font(SR.Text.title(16))
                        .foregroundStyle(SR.ink)
                    Text(meta)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 4)
                if let duration = flowDuration(step.durationMs) {
                    Text(duration)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkSecondary)
                }
            }
            if let error = step.error {
                Text(error)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.leading, 28)
            }
            if let output = step.output, !output.isEmpty {
                DisclosureGroup(isExpanded: $expanded) {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(output)
                            .font(SR.Text.mono(12))
                            .foregroundStyle(SR.inkSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true)
                            .padding(10)
                    }
                    .background(SR.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } label: {
                    Text(expanded ? "Output" : outputPreview(output))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(1)
                }
                .tint(SR.accent)
                .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("flow-run-step-\(step.nodeId)")
    }

    private var meta: String {
        var parts = [flowStatusLabel(step.status).uppercased()]
        if !step.type.isEmpty { parts.append(step.type) }
        if let rows = step.rows { parts.append("\(rows) row\(rows == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private func outputPreview(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
        return flat.count > 80 ? String(flat.prefix(80)) + "…" : flat
    }
}
