import SwiftUI

/// The family task list: what needs doing, what is done, what is owed.
///
/// Anyone in the family adds a task, with an optional person, deadline and
/// reward. Whoever does it swipes it Done; a parent Confirms it (the reward is
/// then owed until a parent marks it paid) or Sends it back with a note. The
/// site pushes each step to whoever it concerns; this is where those land.
struct FamilyTasksScreen: View {
    @ObservedObject private var store = FamilyTasksStore.shared
    @AppStorage(TodayCards.tasks) private var onToday = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showing: Shelf = .open
    @State private var adding = false
    /// The task a parent is sending back, while the note is asked for.
    @State private var sendingBack: FamilyTask?
    @State private var sendBackNote = ""

    enum Shelf: String, CaseIterable, Identifiable {
        case open = "Open", completed = "Completed", owed = "Owed"
        var id: String { rawValue }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $showing) {
                    ForEach(Shelf.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("tasks-shelf")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            if let board = store.board {
                switch showing {
                case .open: openShelf(board)
                case .completed: completedShelf(board)
                case .owed: owedShelf(board)
                }
            } else if store.loaded {
                Section {
                    SREmpty(
                        title: "No tasks yet",
                        icon: "checklist",
                        message: store.message ?? "Add the first one with +. Anyone in the family can."
                    )
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ProgressView().tint(SR.accent).frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                .listRowBackground(Color.clear)
            }

            Section {
                FamilyShowOnToday(isOn: $onToday, what: "what's left to do and what's owed")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .srPaper()
        .accessibilityIdentifier("family-tasks-screen")
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { SRBarMark() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    SRHaptic.tap()
                    adding = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(store.board == nil)
                .accessibilityLabel("Add a task")
                .accessibilityIdentifier("tasks-add")
            }
        }
        .srRefreshable { await store.load() }
        .task { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.load() }
        }
        .overlay(alignment: .bottom) {
            if let message = store.message, store.board != nil { SRBanner(text: message, tone: SR.error) }
        }
        .sheet(isPresented: $adding) {
            FamilyTaskSheet(people: store.board?.people ?? [], me: store.board?.me) { body in
                await store.create(body)
            }
        }
        .alert(
            "Send it back?",
            isPresented: Binding(get: { sendingBack != nil }, set: { if !$0 { sendingBack = nil } }),
            presenting: sendingBack
        ) { task in
            TextField("What's left to do?", text: $sendBackNote)
            Button("Send back") {
                let note = sendBackNote.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await store.act(.sendBack, on: task, note: note.isEmpty ? nil : note) }
                sendBackNote = ""
            }
            Button("Cancel", role: .cancel) { sendBackNote = "" }
        } message: { task in
            Text("\"\(task.title)\" goes back on the list, with your note.")
        }
    }

    // MARK: - Open

    @ViewBuilder
    private func openShelf(_ board: FamilyTasksBoard) -> some View {
        let awaiting = FamilyTaskRules.awaiting(board)
        let toDo = FamilyTaskRules.toDo(board)
        if !awaiting.isEmpty {
            Section {
                ForEach(awaiting) { task in row(task, board) }
            } header: {
                SRSectionLabel(
                    text: board.me.parent ? "Waiting for you" : "With a parent",
                    trailing: "\(awaiting.count)"
                )
            }
        }
        Section {
            if toDo.isEmpty {
                Text(awaiting.isEmpty ? "Nothing to do. Add something with +." : "Everything else is done.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .srGlassRow()
            }
            ForEach(toDo) { task in row(task, board) }
        } header: {
            SRSectionLabel(text: "To do", trailing: toDo.isEmpty ? nil : "\(toDo.count)")
        }
    }

    // MARK: - Completed

    @ViewBuilder
    private func completedShelf(_ board: FamilyTasksBoard) -> some View {
        Section {
            if board.completed.isEmpty {
                Text(board.me.parent ? "Nothing confirmed in the last 90 days." : "Nothing of yours confirmed in the last 90 days.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .srGlassRow()
            }
            ForEach(board.completed) { task in row(task, board) }
        } header: {
            SRSectionLabel(text: board.me.parent ? "Confirmed" : "Yours, confirmed", trailing: "90 days")
        }
    }

    // MARK: - Owed

    @ViewBuilder
    private func owedShelf(_ board: FamilyTasksBoard) -> some View {
        Section {
            FamilyOwedTotal(board: board)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
        if board.owed.items.isEmpty {
            Section {
                Text(board.me.parent ? "Nobody is owed anything." : "Nothing owed to you right now.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .srGlassRow()
            }
        } else if board.me.parent {
            ForEach(FamilyTaskRules.owedGroups(board)) { group in
                Section {
                    ForEach(group.items) { task in owedRow(task, board) }
                } header: {
                    SRSectionLabel(text: group.name, trailing: group.pence > 0 ? FamilyTaskRules.money(group.pence) : nil)
                }
            }
        } else {
            Section {
                ForEach(board.owed.items) { task in owedRow(task, board) }
            } header: {
                SRSectionLabel(text: "Owed to you")
            }
        }
    }

    private func owedRow(_ task: FamilyTask, _ board: FamilyTasksBoard) -> some View {
        HStack(spacing: 12) {
            Image(systemName: task.reward?.kindValue?.icon ?? "gift")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SR.good)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.reward?.label ?? "Reward")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(task.title)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if FamilyTaskRules.actions(for: task, me: board.me).contains(.paid) {
                Button {
                    SRHaptic.tap()
                    Task { await store.act(.paid, on: task) }
                } label: {
                    Text(store.busy == task.id ? "…" : "Mark paid")
                        .font(SR.Text.bodyMedium(14))
                }
                .buttonStyle(.bordered)
                .tint(SR.good)
                .disabled(store.busy != nil)
                .accessibilityIdentifier("task-paid-\(task.id)")
            }
        }
        .padding(.vertical, 6)
        .srGlassRow()
    }

    // MARK: - A row, and what it offers

    private func row(_ task: FamilyTask, _ board: FamilyTasksBoard) -> some View {
        let actions = FamilyTaskRules.actions(for: task, me: board.me)
        return FamilyTaskRow(task: task, board: board, busy: store.busy == task.id, primary: primary(actions)) { action in
            perform(action, on: task)
        }
        .srGlassRow()
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if actions.contains(.done) {
                Button { perform(.done, on: task) } label: { Label("Done", systemImage: "checkmark") }
                    .tint(SR.good)
            }
            if actions.contains(.confirm) {
                Button { perform(.confirm, on: task) } label: { Label("Confirm", systemImage: "checkmark.seal") }
                    .tint(SR.good)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if actions.contains(.delete) {
                Button(role: .destructive) { perform(.delete, on: task) } label: { Label("Delete", systemImage: "trash") }
            }
            if actions.contains(.sendBack) {
                Button { perform(.sendBack, on: task) } label: { Label("Send back", systemImage: "arrow.uturn.left") }
                    .tint(SR.warn)
            }
            if actions.contains(.undo) {
                Button { perform(.undo, on: task) } label: { Label("Not done", systemImage: "arrow.uturn.backward") }
                    .tint(SR.accentInk)
            }
        }
        .contextMenu {
            ForEach(actions, id: \.self) { action in
                Button(role: action == .delete ? .destructive : nil) {
                    perform(action, on: task)
                } label: {
                    Label(action.label, systemImage: action.icon)
                }
            }
        }
    }

    /// The one action a row's own button offers: Done, or — for a parent on
    /// a done task — Confirm. The rest are in the swipes and the menu.
    private func primary(_ actions: [FamilyTaskAction]) -> FamilyTaskAction? {
        if actions.contains(.confirm) { return .confirm }
        if actions.contains(.done) { return .done }
        return nil
    }

    private func perform(_ action: FamilyTaskAction, on task: FamilyTask) {
        if action == .sendBack {
            sendBackNote = ""
            sendingBack = task
            return
        }
        Task { await store.act(action, on: task) }
    }
}

/// One task: title, notes, who it is for, when, the reward, and where it is.
struct FamilyTaskRow: View {
    let task: FamilyTask
    let board: FamilyTasksBoard
    let busy: Bool
    let primary: FamilyTaskAction?
    let act: (FamilyTaskAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(statusTone)
                .frame(width: 26)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .strikethrough(task.isConfirmed, color: SR.inkGhost)
                    .fixedSize(horizontal: false, vertical: true)
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .lineLimit(3)
                }
                if task.isOpen, let note = task.sentBackNote, !note.isEmpty {
                    Label("Sent back: \(note)", systemImage: "arrow.uturn.left")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.error)
                }
                if let line = statusLine {
                    Text(line)
                        .font(SR.Text.mono())
                        .foregroundStyle(task.isAwaiting ? SR.accentDeep : SR.inkMuted)
                }
                HStack(spacing: 10) {
                    Text(forLine.uppercased())
                        .font(SR.Text.mono())
                        .tracking(0.6)
                        .foregroundStyle(SR.inkMuted)
                    if let due = dueLine {
                        Text(due.text.uppercased())
                            .font(SR.Text.mono())
                            .tracking(0.6)
                            .foregroundStyle(due.overdue ? SR.error : SR.inkMuted)
                    }
                }
                if let reward = task.reward {
                    Label(reward.label + (task.isConfirmed ? (reward.paid ? " · paid" : " · owed") : ""),
                          systemImage: reward.kindValue?.icon ?? "gift")
                        .font(SR.Text.bodyMedium(14))
                        .foregroundStyle(SR.good)
                }
            }
            Spacer(minLength: 6)
            if let primary {
                Button {
                    act(primary)
                } label: {
                    Image(systemName: busy ? "hourglass" : primary.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .tint(SR.good)
                .disabled(busy)
                .accessibilityLabel("\(primary.label): \(task.title)")
                .accessibilityIdentifier("task-\(primary.rawValue)-\(task.id)")
            }
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("task-row-\(task.id)")
    }

    private var statusIcon: String {
        switch task.status {
        case "done": return "checkmark.circle"
        case "confirmed": return "checkmark.seal.fill"
        default: return "circle"
        }
    }

    private var statusTone: Color {
        switch task.status {
        case "done": return SR.accent
        case "confirmed": return SR.good
        default: return SR.inkGhost
        }
    }

    private var forLine: String {
        guard let who = FamilyTaskRules.name(task.assignee, in: board) else { return "Anyone" }
        return who == "You" ? "For you" : "For \(who)"
    }

    private var dueLine: (text: String, overdue: Bool)? {
        guard task.isOpen, let deadline = task.deadline else { return nil }
        return FamilyTaskRules.deadline(deadline)
    }

    private var statusLine: String? {
        let doer = FamilyTaskRules.name(task.doneBy, in: board) ?? "Someone"
        switch task.status {
        case "done":
            return board.me.parent ? "\(doer) finished this — confirm or send back" : "\(doer == "You" ? "You" : doer) finished · waiting for a parent"
        case "confirmed":
            let by = FamilyTaskRules.name(task.confirmedBy, in: board) ?? "a parent"
            let when = task.confirmedAt.flatMap(isoDate).map { $0.formatted(.dateTime.day().month(.abbreviated)) }
            return ["Done by \(doer)", "confirmed by \(by == "You" ? "you" : by)", when].compactMap { $0 }.joined(separator: " · ")
        default:
            return nil
        }
    }
}

/// The Owed shelf's headline: the money, and the treats with no money in them.
struct FamilyOwedTotal: View {
    let board: FamilyTasksBoard

    var body: some View {
        let others = FamilyTaskRules.owedOther(board)
        VStack(alignment: .leading, spacing: 6) {
            SRSectionLabel(text: board.me.parent ? "Owed, everyone" : "Owed to you")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(FamilyTaskRules.money(board.owed.totalPence))
                    .font(SR.Text.hero(44))
                    .foregroundStyle(board.owed.totalPence > 0 ? SR.good : SR.inkMuted)
                Text("owed")
                    .font(SR.Text.label(14))
                    .foregroundStyle(SR.inkMuted)
            }
            if !others.isEmpty {
                Text("And " + others.compactMap { $0.reward?.label }.joined(separator: ", ") + ".")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SR.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tasks-owed-total")
    }
}

/// Add a task: what, notes, when, for whom, and what it earns.
struct FamilyTaskSheet: View {
    let people: [FamilyTaskPerson]
    let me: FamilyTaskMe?
    /// Nil when it went; else the sentence to show.
    let save: (FamilyTaskCreateBody) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var draft = FamilyTaskDraft()
    @State private var saving = false
    @State private var refusal: String?
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing?", text: $draft.title)
                        .font(SR.Text.body())
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .accessibilityIdentifier("task-title")
                    TextField("Notes (optional)", text: $draft.notes, axis: .vertical)
                        .font(SR.Text.body())
                        .lineLimit(2...5)
                } header: {
                    SRSectionLabel(text: "Task")
                }

                Section {
                    Picker("For", selection: $draft.assigneeId) {
                        Text("Anyone").tag(String?.none)
                        ForEach(people) { person in
                            Text(person.id == me?.id ? "\(person.name) (you)" : person.name).tag(Optional(person.id))
                        }
                    }
                    .accessibilityIdentifier("task-assignee")
                    Toggle("Deadline", isOn: $draft.hasDeadline.animation())
                        .tint(SR.accent)
                    if draft.hasDeadline {
                        DatePicker("Due", selection: $draft.deadline, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                    }
                } header: {
                    SRSectionLabel(text: "Who and when")
                }

                Section {
                    Toggle("Reward", isOn: $draft.hasReward.animation())
                        .tint(SR.accent)
                        .accessibilityIdentifier("task-reward")
                    if draft.hasReward {
                        Picker("Kind", selection: $draft.kind) {
                            ForEach(FamilyRewardKind.allCases) { kind in
                                Label(kind.label, systemImage: kind.icon).tag(kind)
                            }
                        }
                        HStack(spacing: 6) {
                            Text("£")
                                .font(SR.Text.figure(18))
                                .foregroundStyle(SR.inkMuted)
                            TextField(draft.kind == .cash ? "Amount" : "Amount (optional)", text: $draft.pounds)
                                .keyboardType(.decimalPad)
                                .font(SR.Text.body())
                                .accessibilityIdentifier("task-pounds")
                        }
                        TextField("Note (optional)", text: $draft.rewardNote)
                            .font(SR.Text.body())
                    }
                } header: {
                    SRSectionLabel(text: "Reward")
                } footer: {
                    if draft.hasReward {
                        Text("Cash needs an amount. A reward is owed once a parent confirms the task, until they mark it paid.")
                            .font(SR.Text.secondary(13))
                    }
                }

                if let message = refusal ?? (draft.title.isEmpty ? nil : draft.problem) {
                    Section {
                        Text(message)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.error)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .srPaper()
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Add") {
                        guard let body = draft.body() else { return }
                        saving = true
                        Task {
                            let refused = await save(body)
                            saving = false
                            if let refused { refusal = refused } else { dismiss() }
                        }
                    }
                    .disabled(saving || draft.problem != nil)
                    .accessibilityIdentifier("task-save")
                }
            }
            .onChange(of: draft) { _, _ in refusal = nil }
            .onAppear { titleFocused = true }
        }
        .presentationDragIndicator(.visible)
    }
}

/// Today's task card: what is left, what is waiting, what is owed.
struct TodayTasksCard: View {
    @ObservedObject private var store = FamilyTasksStore.shared
    let open: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            open()
        } label: {
            SRCard(interactive: true) {
                VStack(alignment: .leading, spacing: 12) {
                    SRSectionLabel(text: "Family tasks", trailing: store.summary?.owedLine)
                    if let summary = store.summary {
                        HStack(alignment: .firstTextBaseline, spacing: 22) {
                            figure("\(summary.toDo)", "to do")
                            if summary.parent {
                                figure("\(summary.awaiting)", "to confirm", tone: summary.awaiting > 0 ? SR.accent : SR.ink)
                            } else if summary.awaiting > 0 {
                                figure("\(summary.awaiting)", "with a parent")
                            }
                            if summary.owedPence > 0 {
                                figure(FamilyTaskRules.money(summary.owedPence), "owed", tone: SR.good)
                            }
                        }
                        if !summary.next.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(summary.next.prefix(2)) { line in
                                    HStack(spacing: 8) {
                                        Image(systemName: "circle")
                                            .font(.system(size: 11))
                                            .foregroundStyle(SR.inkGhost)
                                            .accessibilityHidden(true)
                                        Text(line.title)
                                            .font(SR.Text.bodyMedium(15))
                                            .foregroundStyle(SR.ink)
                                            .lineLimit(1)
                                        Spacer(minLength: 6)
                                        if let due = line.due {
                                            Text(due)
                                                .font(SR.Text.mono())
                                                .foregroundStyle(line.overdue ? SR.error : SR.inkMuted)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Text(store.loaded ? (store.message ?? "No tasks yet.") : "Reading the list…")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the task list")
        .accessibilityIdentifier("today-tasks")
    }

    private func figure(_ value: String, _ label: String, tone: Color = SR.ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(SR.Text.figure(26))
                .foregroundStyle(tone)
            Text(label.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
        }
    }
}
