import SwiftUI

/// One workflow: what starts it, its steps in the order they run, and how it
/// has gone lately.
struct FlowDetailScreen: View {
    let ref: FlowRef
    @StateObject private var store: FlowDetailStore
    @EnvironmentObject private var router: Router
    @State private var sheet: DetailSheet?
    @State private var renaming = false
    @State private var renameDraft = ""
    @State private var deletingWorkflow = false
    @State private var deletingStep: FlowStep?
    @State private var starting = false

    /// ONE sheet modifier, switched on this — SwiftUI honours one sheet per
    /// view, and a second `.sheet` silently does nothing (see `Router.sheet`).
    enum DetailSheet: Identifiable {
        case step(String)
        case trigger
        case ask
        case add(after: String)

        var id: String {
            switch self {
            case .step(let id): return "step-\(id)"
            case .trigger: return "trigger"
            case .ask: return "ask"
            case .add(let id): return "add-\(id)"
            }
        }
    }

    init(ref: FlowRef) {
        self.ref = ref
        _store = StateObject(wrappedValue: FlowDetailStore(slug: ref.slug))
    }

    var body: some View {
        List {
            header.srBareRow()
            if let detail = store.detail {
                if detail.building || detail.buildError != nil {
                    buildingSection(detail)
                }
                ForEach(store.fixProposals) { proposal in
                    Section { FlowFixBanner(proposal: proposal, store: store) }
                        .srGlassRow()
                }
                triggerSection(detail)
                stepsSection(detail)
                runsSection(detail)
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.wire)
        .navigationTitle(store.detail?.title ?? ref.title)
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable { await store.load() }
        .task {
            if store.detail == nil { await store.load() }
            if store.detail?.trigger.kind == .event { await store.loadEventTypes() }
        }
        .overlay {
            if store.loading && store.detail == nil { ProgressView().tint(SR.accent) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
        .sheet(item: $sheet) { which in
            sheetContent(which)
        }
        .alert("Rename workflow", isPresented: $renaming) {
            TextField("Title", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await store.rename(to: renameDraft) } }
        }
        .confirmationDialog("Delete this workflow?", isPresented: $deletingWorkflow, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteWorkflow() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its steps, schedule and run history go, on the website too. This cannot be undone.")
        }
        .confirmationDialog(
            "Delete this step?",
            isPresented: Binding(get: { deletingStep != nil }, set: { if !$0 { deletingStep = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete step", role: .destructive) {
                if let step = deletingStep { removeStep(step) }
                deletingStep = nil
            }
            Button("Cancel", role: .cancel) { deletingStep = nil }
        } message: {
            Text("Its connections go with it. The steps either side are not rejoined.")
        }
        .overlay(alignment: .bottom) {
            if let message = store.message { SRBanner(text: message).padding(.bottom, 4) }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            SRPageHeader(
                kicker: "Workflow",
                title: store.detail?.title ?? ref.title,
                strap: store.detail?.description.flatMap { $0.isEmpty ? nil : $0 }
            )
            SRGlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    Button { runNow() } label: {
                        if starting {
                            ProgressView().tint(SR.paper)
                        } else {
                            SRButtonLabel(title: "Run now", icon: "play.fill")
                        }
                    }
                    .srButton(.prominent)
                    .disabled(starting || store.detail?.building == true)
                    .accessibilityIdentifier("flow-run")

                    Button { SRHaptic.tap(); sheet = .ask } label: {
                        SRButtonLabel(title: "Ask jkai", icon: "sparkle")
                    }
                    .srButton(.regular)
                    .disabled(store.detail == nil)
                    .accessibilityIdentifier("flow-ask")
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private var menu: some View {
        Menu {
            Button { runNow() } label: { Label("Run now", systemImage: "play") }
            Button { sheet = .ask } label: { Label("Ask jkai to change it", systemImage: "sparkle") }
            Button {
                renameDraft = store.detail?.title ?? ref.title
                renaming = true
            } label: { Label("Rename", systemImage: "pencil") }
            Link(destination: SiteClient.shared.webURL("jkai/canvas/\(ref.slug)")) {
                Label("Open the canvas on the web", systemImage: "safari")
            }
            Divider()
            Button(role: .destructive) { deletingWorkflow = true } label: {
                Label("Delete workflow", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Workflow actions")
    }

    // MARK: - Sections

    @ViewBuilder
    private func buildingSection(_ detail: FlowDetail) -> some View {
        Section {
            HStack(spacing: 12) {
                if detail.buildError == nil {
                    ProgressView().tint(SR.accent)
                    Text("jkai is still building this workflow. It fills in here when it is done.")
                } else {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(SR.error)
                    Text(detail.buildError ?? "")
                }
            }
            .font(SR.Text.secondary())
            .foregroundStyle(SR.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .srGlassRow()
    }

    @ViewBuilder
    private func triggerSection(_ detail: FlowDetail) -> some View {
        Section {
            if detail.trigger.isEditableOnPhone {
                Button { SRHaptic.tap(); sheet = .trigger } label: {
                    FlowTriggerCard(trigger: detail.trigger, eventLabel: nil, editable: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("flow-trigger")
            } else {
                // Read-only: `PUT /trigger` takes manual or a schedule only,
                // so an event, webhook or inbox trigger is set on the web.
                FlowTriggerCard(trigger: detail.trigger, eventLabel: store.eventLabel(detail.trigger.eventType), editable: false)
                    .accessibilityIdentifier("flow-trigger")
            }

            if detail.trigger.kind == .cron {
                Toggle(isOn: Binding<Bool>(
                    get: { detail.trigger.enabled },
                    set: { value in Task { await store.toggleEnabled(value) } }
                )) {
                    Text("Schedule on")
                        .font(SR.Text.body())
                        .foregroundStyle(SR.ink)
                }
                .tint(SR.accent)
                .disabled(store.saving)
            }
        } header: {
            SRSectionLabel(text: "Starts")
        }
        .srGlassRow()
    }

    @ViewBuilder
    private func stepsSection(_ detail: FlowDetail) -> some View {
        Section {
            if detail.steps.isEmpty && !detail.building {
                Text("No steps yet. Add one, or ask jkai to build it out.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            ForEach(store.layout) { row in
                layoutRow(row, detail: detail)
            }
            if let last = lastStep(detail) {
                Button {
                    SRHaptic.tap()
                    sheet = .add(after: last.id)
                } label: {
                    Label("Add a step at the end", systemImage: "plus.circle")
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.accent)
                }
                .accessibilityIdentifier("flow-add-step")
            }
        } header: {
            SRSectionLabel(text: "Steps", trailing: detail.steps.isEmpty ? nil : "\(detail.steps.count)")
        }
        .srGlassRow()
    }

    @ViewBuilder
    private func layoutRow(_ row: FlowLayoutRow, detail: FlowDetail) -> some View {
        switch row.kind {
        case .branch(let label):
            FlowBranchLabel(label: label, depth: row.depth)
        case .passthrough:
            Text("Straight on")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkGhost)
                .padding(.leading, indent(row.depth) + 14)
        case .step(let id):
            if let step = detail.step(id) {
                Button {
                    SRHaptic.tap()
                    sheet = .step(step.id)
                } label: {
                    FlowStepRow(step: step, isTrigger: detail.steps.first?.id == step.id)
                        .padding(.leading, indent(row.depth))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("flow-step-\(step.id)")
                .contextMenu {
                    Button { sheet = .step(step.id) } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                    Button { sheet = .add(after: step.id) } label: { Label("Add a step after", systemImage: "plus") }
                    Divider()
                    Button(role: .destructive) { deletingStep = step } label: {
                        Label("Delete step", systemImage: "trash")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func runsSection(_ detail: FlowDetail) -> some View {
        Section {
            if detail.recentRuns.isEmpty {
                Text("Not run yet.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            ForEach(detail.recentRuns) { run in
                NavigationLink(value: FlowRunRef(runId: run.id, title: detail.title)) {
                    FlowRunRow(run: run)
                }
                .accessibilityIdentifier("flow-run-\(run.id)")
            }
        } header: {
            SRSectionLabel(text: "Recent runs")
        }
        .srGlassRow()
    }

    @ViewBuilder
    private func sheetContent(_ which: DetailSheet) -> some View {
        switch which {
        case .step(let id):
            if let detail = store.detail, let step = detail.step(id) {
                FlowStepEditor(step: step, detail: detail, store: store) { next in
                    sheet = next.map { DetailSheet.add(after: $0) }
                }
            }
        case .trigger:
            if let detail = store.detail {
                FlowTriggerEditor(trigger: detail.trigger, store: store)
            }
        case .ask:
            if let detail = store.detail {
                FlowAskSheet(detail: detail, store: store)
            }
        case .add(let after):
            if let detail = store.detail, let step = detail.step(after) {
                FlowAddStepSheet(after: step, store: store)
            }
        }
    }

    // MARK: - Actions

    private func indent(_ depth: Int) -> CGFloat { CGFloat(min(depth, 4)) * 18 }

    /// The last step in reading order that has no way out — where "add at the
    /// end" means. Falls back to the last listed step.
    private func lastStep(_ detail: FlowDetail) -> FlowStep? {
        let ordered = store.layout.compactMap { row -> FlowStep? in
            if case .step(let id) = row.kind { return detail.step(id) }
            return nil
        }
        return ordered.last(where: { $0.next.isEmpty }) ?? ordered.last
    }

    private func runNow() {
        guard !starting else { return }
        starting = true
        Task {
            let runId = await store.run()
            starting = false
            if let runId {
                router.flows.append(FlowRunRef(runId: runId, title: store.detail?.title ?? ref.title))
            }
        }
    }

    private func deleteWorkflow() {
        Task {
            if await store.delete(), !router.flows.isEmpty {
                router.flows.removeLast()
            }
        }
    }

    private func removeStep(_ step: FlowStep) {
        Task {
            let result = await store.amend([FlowOps.removeNode(step.id)])
            switch result {
            case .invalid(_, let text), .failed(let text): store.message = text
            case .saved, .conflict: break
            }
        }
    }
}

// MARK: - Pieces

struct FlowTriggerCard: View {
    let trigger: FlowTrigger
    var eventLabel: String? = nil
    var editable: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: trigger.kind.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SR.accent)
                .frame(width: 34, height: 34)
                .background(SR.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(trigger.kind.label.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.inkMuted)
                Text(trigger.headline(eventLabel: eventLabel))
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !trigger.filter.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(trigger.filter, id: \.self) { clause in
                            Text("ONLY IF " + clause.sentence)
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkSecondary)
                        }
                    }
                }
                if !editable {
                    Text(trigger.kind == .event && !trigger.enabled
                         ? "Off. Change what starts it on the web canvas."
                         : "Change what starts it on the web canvas.")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                }
                if trigger.kind == .cron && !trigger.enabled {
                    Text("Paused — nothing runs on schedule.")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.warn)
                } else if !trigger.nextRuns.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(trigger.nextRuns.prefix(3), id: \.self) { iso in
                            Text(nextRunLine(iso))
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkSecondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 6)
            if editable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SR.inkGhost)
                    .padding(.top, 10)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// In the SCHEDULE's zone, not the phone's: "07:00" on a London
    /// schedule must read 07:00 even from a phone set to New York.
    private func nextRunLine(_ iso: String) -> String {
        guard let date = isoDate(iso) else { return iso }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_GB")
        format.timeZone = trigger.timezone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: FlowDefaults.timezone)
        format.dateFormat = "EEE d MMM, HH:mm"
        return "NEXT " + format.string(from: date).uppercased()
    }
}

struct FlowStepRow: View {
    let step: FlowStep
    var isTrigger: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isTrigger ? SR.accent : SR.accentInk)
                .frame(width: 30, height: 30)
                .background((isTrigger ? SR.accent : SR.accentInk).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(step.label)
                        .font(SR.Text.title(16))
                        .foregroundStyle(SR.ink)
                        .multilineTextAlignment(.leading)
                    if step.legacy {
                        SRPill(text: "Legacy", tone: SR.warn)
                    }
                }
                if !step.summary.isEmpty {
                    Text(step.summary)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
        .frame(minHeight: SR.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The label over one arm of a branch — the handle, in mono, on a rule.
struct FlowBranchLabel: View {
    let label: String
    let depth: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 11, weight: .bold))
            Text(label.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
        }
        .foregroundStyle(SR.accent)
        .padding(.leading, CGFloat(max(depth - 1, 0)) * 18 + 6)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Branch: \(label)")
    }
}

struct FlowRunRow: View {
    let run: FlowRunSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: run.state.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FlowTone.color(run.state))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(flowStatusLabel(run.status) + (run.trigger.map { " · \($0)" } ?? ""))
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                if let error = run.error {
                    Text(error)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.error)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                if let started = run.startedAt {
                    Text(shortAgo(started))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
                if let duration = flowDuration(run.durationMs) {
                    Text(duration)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// "Apply this fix permanently?" — a heal that worked, offered, never applied
/// behind the owner's back.
struct FlowFixBanner: View {
    let proposal: FlowFixProposal
    @ObservedObject var store: FlowDetailStore
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(SR.accent)
                Text("A FIX FOR “\(proposal.nodeLabel.uppercased())”")
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.accent)
            }
            Text(proposal.description)
                .font(SR.Text.body(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !proposal.changedKeys.isEmpty {
                Text("CHANGES " + proposal.changedKeys.joined(separator: ", ").uppercased())
                    .font(SR.Text.mono())
                    .tracking(0.8)
                    .foregroundStyle(SR.accentInk)
            }
            Text(retryLine)
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkMuted)
            HStack(spacing: 10) {
                Button { resolve(true) } label: { SRButtonLabel(title: "Apply", icon: "checkmark") }
                    .srButton(.prominent)
                Button { resolve(false) } label: { SRButtonLabel(title: "Dismiss") }
                    .srButton(.regular)
                if busy { ProgressView().tint(SR.accent) }
            }
            .disabled(busy)
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("flow-fix-\(proposal.id)")
    }

    private var retryLine: String {
        if let times = proposal.occurrences, times > 1 {
            return "It rescued \(times) failing runs on a retry. Apply it permanently?"
        }
        return "It worked on a retry. Apply it permanently?"
    }

    private func resolve(_ accept: Bool) {
        busy = true
        Task {
            await store.resolve(proposal, accept: accept)
            busy = false
        }
    }
}

// MARK: - Trigger editor

struct FlowTriggerEditor: View {
    let trigger: FlowTrigger
    @ObservedObject var store: FlowDetailStore
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case manual, schedule
        var id: String { rawValue }
        var label: String { self == .manual ? "Manual" : "Schedule" }
    }

    @State private var mode: Mode
    @State private var preset: CronPreset
    @State private var custom: String
    @State private var timezone: String
    @State private var enabled: Bool
    @State private var error: String?

    init(trigger: FlowTrigger, store: FlowDetailStore) {
        self.trigger = trigger
        self.store = store
        let cron = trigger.cron ?? "0 9 * * *"
        _mode = State(initialValue: trigger.kind == .cron ? .schedule : .manual)
        _preset = State(initialValue: CronPreset.parse(cron))
        _custom = State(initialValue: cron)
        _timezone = State(initialValue: trigger.timezone ?? FlowDefaults.timezone)
        _enabled = State(initialValue: trigger.enabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditableKind {
                    Section {
                        Text("This workflow starts from \(trigger.kind.label.lowercased()): \(trigger.description). The phone can switch it to manual or a schedule; other starts are set on the web canvas.")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                    }
                    .srGlassRow()
                }
                Section {
                    Picker("Starts", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if mode == .schedule {
                    scheduleSection
                    Section {
                        Picker("Time zone", selection: $timezone) {
                            ForEach(zones, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.navigationLink)
                        Toggle("Schedule on", isOn: $enabled).tint(SR.accent)
                    } footer: {
                        Text("Cron: \(expression)")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                    }
                    .srGlassRow()
                } else {
                    Section {
                        Text("Runs only when you start it — from here, the web, or jkai.")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                    }
                    .srGlassRow()
                }
                if let error {
                    Section {
                        Text(error)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.error)
                    }
                    .srGlassRow()
                }
            }
            .srGround(.wire)
            .navigationTitle("When it runs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if store.saving {
                        ProgressView().tint(SR.accent)
                    } else {
                        Button("Save") { save() }
                            .disabled(mode == .schedule && !CronPreset.looksValid(expression))
                    }
                }
            }
        }
    }

    private var isEditableKind: Bool { trigger.kind == .cron || trigger.kind == .manual }

    private var expression: String {
        preset.kind == .custom ? custom.trimmingCharacters(in: .whitespacesAndNewlines) : preset.expression
    }

    /// London first — it is the default and the one the owner lives in — then
    /// UTC, then everything, so the picker is never missing the saved zone.
    private var zones: [String] {
        var out = [FlowDefaults.timezone, "UTC"]
        if !out.contains(timezone) { out.append(timezone) }
        out += TimeZone.knownTimeZoneIdentifiers.filter { !out.contains($0) }
        return out
    }

    @ViewBuilder
    private var scheduleSection: some View {
        Section {
            Picker("Repeat", selection: Binding<CronPreset.Kind>(
                get: { preset.kind },
                set: { kind in
                    if kind == .custom { custom = preset.expression }
                    preset = kind == .custom ? .custom(custom) : preset.converted(to: kind)
                }
            )) {
                ForEach(CronPreset.Kind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)

            switch preset.kind {
            case .hourly:
                Stepper(value: Binding<Int>(
                    get: { preset.minute },
                    set: { preset = .hourly(minute: $0) }
                ), in: 0...59, step: 5) {
                    Text(String(format: "At :%02d past each hour", preset.minute))
                        .font(SR.Text.body())
                }
            case .daily, .weekdays, .weekly:
                if preset.kind == .weekly {
                    Picker("Day", selection: Binding<Int>(
                        get: { preset.weekday },
                        set: { preset = .weekly(weekday: $0, hour: preset.hour, minute: preset.minute) }
                    )) {
                        ForEach(0..<7, id: \.self) { Text(CronPreset.weekdayNames[$0]).tag($0) }
                    }
                }
                DatePicker("At", selection: timeBinding, displayedComponents: .hourAndMinute)
            case .custom:
                TextField("m h dom mon dow", text: $custom)
                    .font(SR.Text.mono(14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !CronPreset.looksValid(custom) {
                    Text("Five fields: minute, hour, day of month, month, day of week.")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.error)
                }
            }
        } header: {
            SRSectionLabel(text: "Schedule")
        }
        .srGlassRow()
    }

    /// Hour and minute as a Date for the wheel, in the phone's calendar — only
    /// the two components are read back, so the day it lands on is irrelevant.
    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: preset.hour, minute: preset.minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                let h = parts.hour ?? 9
                let m = parts.minute ?? 0
                switch preset.kind {
                case .daily: preset = .daily(hour: h, minute: m)
                case .weekdays: preset = .weekdays(hour: h, minute: m)
                case .weekly: preset = .weekly(weekday: preset.weekday, hour: h, minute: m)
                default: break
                }
            }
        )
    }

    private func save() {
        error = nil
        Task {
            let result = await store.setTrigger(
                kind: mode == .schedule ? .cron : .manual,
                cron: mode == .schedule ? expression : nil,
                timezone: timezone,
                enabled: mode == .schedule ? enabled : true
            )
            switch result {
            case .saved: dismiss()
            case .conflict: dismiss()
            case .invalid(_, let text), .failed(let text): error = text
            }
        }
    }
}

// MARK: - Ask jkai

struct FlowAskSheet: View {
    let detail: FlowDetail
    @ObservedObject var store: FlowDetailStore
    @Environment(\.dismiss) private var dismiss

    @State private var instruction = ""
    @State private var asking = false
    @State private var proposal: FlowProposal?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let proposal {
                    proposalSections(proposal)
                } else {
                    Section {
                        TextEditor(text: $instruction)
                            .font(SR.Text.body())
                            .frame(minHeight: 120)
                            .accessibilityIdentifier("flow-ask-instruction")
                    } header: {
                        SRSectionLabel(text: "What should change?")
                    } footer: {
                        Text("jkai proposes the changes; nothing is saved until you apply them.")
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.inkMuted)
                    }
                    .srGlassRow()
                }
                if let error {
                    Section {
                        Text(error).font(SR.Text.secondary()).foregroundStyle(SR.error)
                    }
                    .srGlassRow()
                }
            }
            .srGround(.wire)
            .navigationTitle(proposal == nil ? "Ask jkai" : "Proposed changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if asking || store.saving {
                        ProgressView().tint(SR.accent)
                    } else if let proposal {
                        Button("Apply") { apply(proposal) }
                            .disabled(proposal.ops.isEmpty)
                            .accessibilityIdentifier("flow-ask-apply")
                    } else {
                        Button("Ask") { ask() }
                            .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func proposalSections(_ proposal: FlowProposal) -> some View {
        Section {
            Text(proposal.summary.isEmpty ? "jkai proposed \(proposal.ops.count) change\(proposal.ops.count == 1 ? "" : "s")." : proposal.summary)
                .font(SR.Text.body())
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SRSectionLabel(text: "Summary")
        }
        .srGlassRow()
        Section {
            if proposal.ops.isEmpty {
                Text("No changes proposed.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            ForEach(Array(proposal.ops.enumerated()), id: \.offset) { index, op in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(SR.Text.display(16))
                        .foregroundStyle(SR.accent)
                        .frame(width: 22, alignment: .leading)
                    Text(FlowOps.describe(op, steps: detail.steps))
                        .font(SR.Text.body(15))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            SRSectionLabel(text: "Changes", trailing: "\(proposal.ops.count)")
        }
        .srGlassRow()
        if !proposal.warnings.isEmpty {
            Section {
                ForEach(proposal.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.warn)
                }
            } header: {
                SRSectionLabel(text: "Warnings")
            }
            .srGlassRow()
        }
    }

    private func ask() {
        asking = true
        error = nil
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                proposal = try await store.ask(text)
            } catch {
                self.error = error.localizedDescription
            }
            asking = false
        }
    }

    private func apply(_ proposal: FlowProposal) {
        error = nil
        Task {
            let result = await store.amend(proposal.ops)
            switch result {
            case .saved: dismiss()
            case .conflict:
                error = "The workflow changed while jkai was thinking. Ask again against the new version."
                self.proposal = nil
            case .invalid(_, let text), .failed(let text):
                error = text
            }
        }
    }
}
