import SwiftUI

/// One step, as a form.
///
/// The form is not written here: it is generated from the `form` the server
/// sends — the same field descriptions the web inspector renders — so a node
/// type added on the site is editable on the phone without a release. A kind
/// the phone does not know arrives as `json` and gets the raw editor, which
/// can hold anything without losing it.
struct FlowStepEditor: View {
    let step: FlowStep
    let detail: FlowDetail
    @ObservedObject var store: FlowDetailStore
    /// Hand the sheet over to "add a step after this one".
    let onAddAfter: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var label: String
    @State private var values: [String: JSONValue]
    /// The text of every JSON-shaped field, as typed. Parsed on each change;
    /// the last good parse is what `values` holds.
    @State private var jsonText: [String: String]
    @State private var jsonErrors: [String: String] = [:]
    /// The whole config as JSON, once the reader has opened and edited it.
    /// When set and valid it wins over the form.
    @State private var rawText: String?
    @State private var rawError: String?
    @State private var fieldErrors: [String: String] = [:]
    @State private var generalError: String?
    @State private var chipDrafts: [String: String] = [:]
    @State private var confirmingDelete = false
    @State private var showAdvanced = false

    init(step: FlowStep, detail: FlowDetail, store: FlowDetailStore, onAddAfter: @escaping (String?) -> Void) {
        self.step = step
        self.detail = detail
        self.store = store
        self.onAddAfter = onAddAfter
        _label = State(initialValue: step.label)
        _values = State(initialValue: step.config)
        var texts: [String: String] = [:]
        for field in step.form where Self.editsAsJSON(field, step.config[field.key]) {
            texts[field.key] = step.config[field.key].map { $0.isNull ? "" : $0.pretty } ?? ""
        }
        _jsonText = State(initialValue: texts)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $label)
                        .font(SR.Text.title())
                        .accessibilityIdentifier("flow-step-name")
                    Text(step.type)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                    if step.legacy {
                        Text("A legacy step type. It still runs; new workflows use its replacement.")
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.warn)
                    }
                } header: {
                    SRSectionLabel(text: "Step")
                }
                .srGlassRow()

                ForEach(basicGroups, id: \.title) { group in
                    Section {
                        ForEach(group.fields) { fieldView($0) }
                    } header: {
                        SRSectionLabel(text: group.title)
                    }
                    .srGlassRow()
                }

                Section {
                    DisclosureGroup(isExpanded: $showAdvanced) {
                        ForEach(advancedFields) { fieldView($0) }
                        rawEditor
                    } label: {
                        Text(step.form.isEmpty ? "Configuration (JSON)" : "Advanced")
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.ink)
                    }
                    .tint(SR.accent)
                }
                .srGlassRow()

                if let generalError {
                    Section {
                        Text(generalError)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.error)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .srGlassRow()
                }

                Section {
                    Button {
                        onAddAfter(step.id)
                    } label: {
                        Label("Add a step after this", systemImage: "plus.circle")
                    }
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete step", systemImage: "trash")
                    }
                }
                .srGlassRow()
            }
            .srGround(.wire)
            .navigationTitle(step.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if store.saving {
                        ProgressView().tint(SR.accent)
                    } else {
                        Button("Save") { save() }
                            .disabled(!canSave)
                            .accessibilityIdentifier("flow-step-save")
                    }
                }
            }
            .onAppear { if step.form.isEmpty { showAdvanced = true } }
            .confirmationDialog("Delete this step?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete step", role: .destructive) { deleteStep() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its connections go with it. The steps either side are not rejoined.")
            }
        }
    }

    // MARK: - Layout of the form

    private struct FieldGroup {
        let title: String
        let fields: [FlowField]
    }

    /// Basic fields, grouped by their `section` in the order they arrive.
    private var basicGroups: [FieldGroup] {
        var groups: [FieldGroup] = []
        for field in step.form where !field.advanced {
            let title = field.section ?? "Settings"
            if let index = groups.firstIndex(where: { $0.title == title }) {
                groups[index] = FieldGroup(title: title, fields: groups[index].fields + [field])
            } else {
                groups.append(FieldGroup(title: title, fields: [field]))
            }
        }
        return groups
    }

    private var advancedFields: [FlowField] { step.form.filter(\.advanced) }

    private var canSave: Bool {
        jsonErrors.isEmpty && rawError == nil && !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func editsAsJSON(_ field: FlowField, _ value: JSONValue?) -> Bool {
        switch field.kind {
        case .json: return true
        case .code:
            // Code is a string. A code field holding an object is JSON by
            // another name, and the string editor would flatten it.
            if let value, value.string == nil, !value.isNull { return true }
            return false
        default: return false
        }
    }

    // MARK: - One field

    @ViewBuilder
    private func fieldView(_ field: FlowField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if field.kind != .toggle {
                Text(field.label)
                    .font(SR.Text.bodyMedium(14))
                    .foregroundStyle(SR.inkSecondary)
            }
            control(field)
            if let help = field.help, !help.isEmpty {
                Text(help)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = fieldErrors[field.key] ?? jsonErrors[field.key] {
                Text(error)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("flow-field-\(field.key)")
    }

    @ViewBuilder
    private func control(_ field: FlowField) -> some View {
        if Self.editsAsJSON(field, step.config[field.key]) {
            jsonEditor(field)
        } else {
            switch field.kind {
            case .text:
                TextField(field.placeholder ?? "", text: stringBinding(field.key))
                    .font(SR.Text.body())
            case .phone:
                TextField(field.placeholder ?? "+44…", text: stringBinding(field.key))
                    .font(SR.Text.body())
                    .keyboardType(.phonePad)
            case .textarea:
                multiline(field, mono: false)
            case .template:
                multiline(field, mono: false)
                templateHint
            case .code:
                multiline(field, mono: true)
            case .number:
                numberControl(field)
            case .toggle:
                Toggle(field.label, isOn: boolBinding(field.key))
                    .font(SR.Text.body())
                    .tint(SR.accent)
            case .dropdown:
                dropdown(field)
            case .chips:
                chips(field)
            case .json:
                jsonEditor(field)
            }
        }
    }

    private func multiline(_ field: FlowField, mono: Bool) -> some View {
        TextEditor(text: stringBinding(field.key))
            .font(mono ? SR.Text.mono(13) : SR.Text.body(15))
            .textInputAutocapitalization(mono ? TextInputAutocapitalization.never : TextInputAutocapitalization.sentences)
            .autocorrectionDisabled(mono)
            .frame(minHeight: mono ? 140 : 90)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(SR.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Which earlier steps a template can draw on.
    @ViewBuilder
    private var templateHint: some View {
        let upstream = FlowLayout.upstream(of: step.id, in: detail.steps)
        if !upstream.isEmpty {
            Text("Use {{…}} to insert from an earlier step: " + upstream.map(\.label).joined(separator: ", ") + ".")
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.accentInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func numberControl(_ field: FlowField) -> some View {
        let binding = numberBinding(field)
        HStack {
            TextField(field.placeholder ?? "", value: binding, format: .number)
                .font(SR.Text.mono(15))
                .keyboardType(.decimalPad)
            if let step = field.step {
                Stepper("", value: binding, in: Self.range(field), step: step)
                    .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func dropdown(_ field: FlowField) -> some View {
        if field.options.isEmpty {
            TextField(field.placeholder ?? "", text: stringBinding(field.key))
                .font(SR.Text.body())
        } else {
            let current = values[field.key] ?? .null
            Picker(field.label, selection: Binding<JSONValue>(
                get: { values[field.key] ?? .null },
                set: { values[field.key] = $0.isNull ? nil : $0 }
            )) {
                if !field.options.contains(where: { $0.value == current }) {
                    Text(current.isNull ? "Not set" : current.display).tag(current)
                }
                ForEach(field.options, id: \.self) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .tint(SR.accent)
        }
    }

    @ViewBuilder
    private func chips(_ field: FlowField) -> some View {
        let items = (values[field.key]?.array ?? []).map(\.display)
        VStack(alignment: .leading, spacing: 8) {
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            Button {
                                removeChip(field.key, at: index)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(item).font(SR.Text.mono())
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                }
                                .foregroundStyle(SR.inkSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(SR.accentInk.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(item)")
                        }
                    }
                }
            }
            TextField(field.placeholder ?? "Add…", text: Binding<String>(
                get: { chipDrafts[field.key] ?? "" },
                set: { chipDrafts[field.key] = $0 }
            ))
            .font(SR.Text.body())
            .textInputAutocapitalization(.never)
            .onSubmit { addChip(field.key) }
        }
    }

    private func jsonEditor(_ field: FlowField) -> some View {
        TextEditor(text: Binding<String>(
            get: { jsonText[field.key] ?? "" },
            set: { text in
                jsonText[field.key] = text
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    values[field.key] = nil
                    jsonErrors[field.key] = nil
                } else if let parsed = JSONValue.parse(trimmed) {
                    values[field.key] = parsed
                    jsonErrors[field.key] = nil
                } else {
                    jsonErrors[field.key] = "Not valid JSON yet."
                }
            }
        ))
        .font(SR.Text.mono(13))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .frame(minHeight: 120)
        .scrollContentBackground(.hidden)
        .padding(6)
        .background(SR.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// The whole config as JSON — the escape hatch for anything the form
    /// does not describe.
    @ViewBuilder
    private var rawEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Raw configuration")
                .font(SR.Text.bodyMedium(14))
                .foregroundStyle(SR.inkSecondary)
            TextEditor(text: Binding<String>(
                get: { rawText ?? JSONValue.object(currentFormConfig).pretty },
                set: { text in
                    rawText = text
                    if let parsed = JSONValue.parse(text), parsed.object != nil {
                        rawError = nil
                    } else {
                        rawError = "The configuration must be one JSON object."
                    }
                }
            ))
            .font(SR.Text.mono(12))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(minHeight: 180)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(SR.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityIdentifier("flow-step-raw")
            if let rawError {
                Text(rawError).font(SR.Text.secondary(13)).foregroundStyle(SR.error)
            } else if rawText != nil {
                Text("Editing the raw JSON replaces the form's values when you save.")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .padding(.vertical, 4)
    }

    /// The stepper's bounds, never inverted — a server that sent min > max
    /// must not crash the sheet.
    static func range(_ field: FlowField) -> ClosedRange<Double> {
        let low = field.min ?? -1_000_000_000
        let high = field.max ?? 1_000_000_000
        return low <= high ? low...high : high...low
    }

    // MARK: - Bindings

    private func stringBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { values[key]?.string ?? values[key].map { $0.isNull ? "" : $0.display } ?? "" },
            set: { values[key] = .string($0) }
        )
    }

    private func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { values[key]?.bool ?? false },
            set: { values[key] = .bool($0) }
        )
    }

    private func numberBinding(_ field: FlowField) -> Binding<Double> {
        Binding(
            get: { values[field.key]?.number ?? Double(values[field.key]?.string ?? "") ?? field.min ?? 0 },
            set: { values[field.key] = .number($0) }
        )
    }

    private func addChip(_ key: String) {
        let draft = (chipDrafts[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }
        var items = values[key]?.array ?? []
        for part in draft.split(separator: ",") {
            let item = part.trimmingCharacters(in: .whitespaces)
            if !item.isEmpty { items.append(.string(item)) }
        }
        values[key] = .array(items)
        chipDrafts[key] = ""
    }

    private func removeChip(_ key: String, at index: Int) {
        var items = values[key]?.array ?? []
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        values[key] = .array(items)
    }

    // MARK: - Save

    private var currentFormConfig: [String: JSONValue] { values }

    /// What the reader wants the config to be now.
    private func editedConfig() -> [String: JSONValue] {
        if let rawText, rawError == nil, let parsed = JSONValue.parse(rawText)?.object {
            return parsed
        }
        return values
    }

    private func save() {
        generalError = nil
        fieldErrors = [:]
        let (patch, removed) = FlowOps.diff(from: step.config, to: editedConfig())
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let newLabel = trimmed != step.label ? trimmed : nil
        if patch.isEmpty && removed.isEmpty && newLabel == nil {
            dismiss()
            return
        }
        let op = FlowOps.updateNode(step.id, config: patch, removeKeys: removed, label: newLabel)
        Task {
            let result = await store.amend([op])
            switch result {
            case .saved:
                dismiss()
            case .conflict:
                generalError = "This workflow was changed somewhere else first and has been reloaded. Nothing was saved — check the step and save again."
            case .invalid(let field, let text):
                if let field, step.form.contains(where: { $0.key == field }) {
                    fieldErrors[field] = text
                    if step.form.first(where: { $0.key == field })?.advanced == true { showAdvanced = true }
                } else {
                    generalError = text
                }
            case .failed(let text):
                generalError = text
            }
        }
    }

    private func deleteStep() {
        Task {
            let result = await store.amend([FlowOps.removeNode(step.id)])
            switch result {
            case .saved: dismiss()
            case .conflict: generalError = "The workflow changed elsewhere and has been reloaded. Try again."
            case .invalid(_, let text), .failed(let text): generalError = text
            }
        }
    }
}

// MARK: - Add a step

/// The node catalogue, grouped by category and searchable. Picking a type
/// inserts it after the chosen step straight away, with the type's defaults;
/// the new step is then edited like any other.
struct FlowAddStepSheet: View {
    let after: FlowStep
    @ObservedObject var store: FlowDetailStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var adding: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Goes after “\(after.label)”" + (after.next.isEmpty ? "." : ", before what comes next."))
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }
                .srGlassRow()
                if let error {
                    Section {
                        Text(error).font(SR.Text.secondary()).foregroundStyle(SR.error)
                    }
                    .srGlassRow()
                }
                ForEach(categories) { category in
                    Section {
                        ForEach(category.types) { type in
                            Button { add(type) } label: { typeRow(type) }
                                .buttonStyle(.plain)
                                .disabled(adding != nil)
                                .accessibilityIdentifier("flow-type-\(type.type)")
                        }
                    } header: {
                        SRSectionLabel(text: category.label)
                    }
                    .srGlassRow()
                }
            }
            .listStyle(.insetGrouped)
            .srGround(.wire)
            .navigationTitle("Add a step")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search steps")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .overlay {
                if store.catalogue == nil { ProgressView().tint(SR.accent) }
            }
            .task { await store.loadCatalogue() }
        }
    }

    private struct Filtered: Identifiable {
        let id: String
        let label: String
        let types: [FlowNodeType]
    }

    private var categories: [Filtered] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (store.catalogue?.categories ?? []).compactMap { category in
            let types = term.isEmpty ? category.types : category.types.filter {
                $0.label.lowercased().contains(term)
                    || $0.description.lowercased().contains(term)
                    || $0.type.lowercased().contains(term)
            }
            return types.isEmpty ? nil : Filtered(id: category.id, label: category.label, types: types)
        }
    }

    private func typeRow(_ type: FlowNodeType) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(type.label)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                if !type.description.isEmpty {
                    Text(type.description)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 6)
            if adding == type.type {
                ProgressView().tint(SR.accent)
            } else {
                Image(systemName: "plus.circle.fill").foregroundStyle(SR.accent)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func add(_ type: FlowNodeType) {
        adding = type.type
        error = nil
        let ops = FlowOps.insertStep(after: after, type: type.type, label: type.label, config: type.defaultConfig)
        Task {
            let result = await store.amend(ops)
            adding = nil
            switch result {
            case .saved: dismiss()
            case .conflict: error = "The workflow changed elsewhere and has been reloaded. Pick the step again."
            case .invalid(_, let text), .failed(let text): error = text
            }
        }
    }
}
