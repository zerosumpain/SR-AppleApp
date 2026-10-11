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
                    .font(SR.Text.marginalia(16))
                    .foregroundStyle(SR.inkSecondary)
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
                    .font(SR.Text.marginalia(16))
                    .foregroundStyle(SR.inkSecondary)
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
                    .font(SR.Text.marginalia(16))
                    .foregroundStyle(SR.inkSecondary)
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
                    // Boxed by hand in the olive pen. Borderless, not
                    // `srButton`: in a List only the borderless styles keep
                    // a tap on the rest of the row from pressing it.
                    Text(store.busy == task.id ? "…" : "Mark paid")
                        .font(SR.Text.label(13))
                        .foregroundStyle(SR.good)
                        .padding(.horizontal, 12)
                        .frame(minHeight: SR.tapTarget)
                        .background(SR.Notes.card)
                        .overlay {
                            SRInkBox(seed: seedFor(task.id)).stroke(SR.good.opacity(0.8), style: .ink(1.3))
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .opacity(store.busy != nil ? 0.45 : 1)
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
            FamilyTaskBox(seed: seedFor(task.id), ticked: task.status == "done" || task.status == "confirmed",
                          tone: statusTone)
                .frame(width: 26)
                .padding(.top, 1)
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
                        .font(SR.Text.kicker())
                        .tracking(SR.Notes.kickerTracking)
                        .foregroundStyle(SR.inkMuted)
                    if let due = dueLine {
                        Text(due.text.uppercased())
                            .font(SR.Text.kicker())
                            .tracking(SR.Notes.kickerTracking)
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
                    // The action's mark in the olive pen, plain.
                    // Borderless, so only this — not the row — presses it.
                    Image(systemName: busy ? "hourglass" : primary.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SR.good)
                        .frame(width: 38, height: 38)
                        .frame(width: SR.tapTarget, height: SR.tapTarget)
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
                .opacity(busy ? 0.45 : 1)
                .disabled(busy)
                .accessibilityLabel("\(primary.label): \(task.title)")
                .accessibilityIdentifier("task-\(primary.rawValue)-\(task.id)")
            }
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("task-row-\(task.id)")
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

/// A task's box on the list, drawn by hand: empty while it is to do, ticked
/// in orange once somebody says it is done, in olive once a parent confirms
/// it (the title is struck through then too). Decorative: the row's words
/// say where the task is.
struct FamilyTaskBox: View {
    let seed: Int
    let ticked: Bool
    let tone: Color

    var body: some View {
        ZStack {
            SRInkBox(seed: seed, amp: 0.5)
                .stroke(ticked ? tone : SR.inkMuted, style: .ink(1.3))
                .frame(width: 18, height: 18)
            if ticked {
                // The tick runs out of its box, as a quick pen's does.
                SRInkTick(seed: seed + 1)
                    .stroke(tone, style: .ink(2.2))
                    .frame(width: 22, height: 22)
                    .offset(x: 3, y: -3)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}

/// The Owed shelf's headline: the money, and the treats with no money in them.
struct FamilyOwedTotal: View {
    let board: FamilyTasksBoard

    var body: some View {
        let others = FamilyTaskRules.owedOther(board)
        VStack(alignment: .leading, spacing: 6) {
            SRSectionLabel(text: board.me.parent ? "Owed, everyone" : "Owed to you")
            // The total, double-underlined in the orange pen as a sum is in
            // an exercise book — when there is one. Nothing owed is written
            // plainly, in muted ink.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if board.owed.totalPence > 0 {
                    Text(FamilyTaskRules.money(board.owed.totalPence))
                        .font(SR.Text.hero(44))
                        .tracking(-44 * 0.03)
                        .monospacedDigit()
                        .foregroundStyle(SR.good)
                        .srInkUnderline(lineWidth: 2.6)
                        .padding(.bottom, 10)
                } else {
                    Text(FamilyTaskRules.money(board.owed.totalPence))
                        .font(SR.Text.hero(44))
                        .tracking(-44 * 0.03)
                        .monospacedDigit()
                        .foregroundStyle(SR.inkMuted)
                }
                Text("OWED")
                    .font(SR.Text.kicker())
                    .tracking(SR.Notes.kickerTracking)
                    .foregroundStyle(SR.Notes.pen)
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
                .srGlassRow()

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
                .srGlassRow()

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
                            .font(SR.Text.marginalia(15))
                            .foregroundStyle(SR.inkSecondary)
                    }
                }
                .srGlassRow()

                if let message = refusal ?? (draft.title.isEmpty ? nil : draft.problem) {
                    Section {
                        Text(message)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.error)
                    }
                    .srGlassRow()
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
///
/// Drawn only while something is outstanding. An empty list is not news, and a
/// card saying "nothing to do" on the first screen is a card to scroll past.
/// Nothing is drawn while the list is still loading either, so a clear list
/// never flashes up and disappears.
struct TodayTasksCard: View {
    @ObservedObject private var store = FamilyTasksStore.shared
    let open: () -> Void

    var body: some View {
        if store.summary?.outstanding == true {
            card
        }
    }

    private var card: some View {
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
                                        SRInkBox(seed: seedFor(line.id), amp: 0.5)
                                            .stroke(SR.inkMuted, style: .ink(1.2))
                                            .frame(width: 13, height: 13)
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
                            .font(SR.Text.marginalia(15))
                            .foregroundStyle(SR.inkSecondary)
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

    /// A count over its petrol label, as the site labels a reading.
    private func figure(_ value: String, _ label: String, tone: Color = SR.ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(SR.Text.figure(26))
                .tracking(-26 * 0.03)
                .monospacedDigit()
                .foregroundStyle(tone)
            Text(label.uppercased())
                .font(SR.Text.kicker())
                .tracking(SR.Notes.kickerTracking)
                .foregroundStyle(SR.accentInk)
        }
    }
}
