import SwiftUI

/// The family backlog: what somebody shared for the family to watch, read or
/// do together. A tap opens it — a YouTube or TikTok link in its own app when
/// that is installed. Swipe right when it's done; left when it's not for us.
///
/// Reached from More ("Backlog") and, for a member with no More, from the
/// Family tab's toolbar. Things arrive through "Share → SR" in any app, or +.
/// The dice picks one for tonight; a long press answers with an emoji or
/// turns an idea into a family task.
struct FamilyBacklogScreen: View {
    @ObservedObject private var store = FamilyBacklogStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage(TodayCards.backlog) private var onToday = false
    @State private var showing: FamilyBacklogShelf = .all
    @State private var adding = false
    @State private var picked: FamilyBacklogItem?

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $showing) {
                    ForEach(FamilyBacklogShelf.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("backlog-shelf")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            if let board = store.board {
                let items = showing.items(board)
                Section {
                    if items.isEmpty {
                        Text(showing.empty)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .srGlassRow()
                    }
                    ForEach(items) { item in row(item, board) }
                } header: {
                    SRSectionLabel(
                        text: showing == .done ? "Last 30 days" : "To watch, read and do",
                        trailing: items.isEmpty ? nil : "\(items.count)"
                    )
                }
            } else if store.loaded {
                Section {
                    SREmpty(
                        title: "Nothing here yet",
                        icon: "tray.full",
                        message: store.message ?? FamilyBacklogShelf.all.empty
                    )
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ProgressView().tint(SR.accent).frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                .listRowBackground(Color.clear)
            }

            if let board = store.board {
                Section {
                    digestSwitch(board)
                    FamilyShowOnToday(isOn: $onToday, what: "what's been shared for you and how much is waiting")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .srPaper()
        .accessibilityIdentifier("family-backlog-screen")
        .navigationTitle("Backlog")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { SRBarMark() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard let board = store.board else { return }
                    SRHaptic.tap()
                    picked = FamilyBacklogRules.pick(board)
                } label: {
                    Image(systemName: "dice")
                }
                .disabled(store.board?.items.isEmpty ?? true)
                .accessibilityLabel("Pick one for tonight")
                .accessibilityIdentifier("backlog-pick")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    SRHaptic.tap()
                    adding = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(store.board == nil)
                .accessibilityLabel("Add to the backlog")
                .accessibilityIdentifier("backlog-add")
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
        .sheet(item: $picked) { item in
            FamilyBacklogPickSheet(item: item, board: store.board) {
                guard let board = store.board else { return }
                picked = FamilyBacklogRules.pick(board, avoiding: item.id)
            } done: {
                picked = nil
                Task { await store.act(.done, on: item) }
            }
        }
        .sheet(isPresented: $adding) {
            FamilyBacklogAddSheet(people: store.board?.people ?? [], me: store.board?.me) { share in
                await store.add(share)
            }
        }
    }

    private func row(_ item: FamilyBacklogItem, _ board: FamilyBacklogBoard) -> some View {
        let link = item.url.flatMap(URL.init(string:))
        return Button {
            guard let link else { return }
            SRHaptic.tap()
            openURL(link)
        } label: {
            FamilyBacklogRow(item: item, board: board)
        }
        .buttonStyle(.plain)
        // Not disabled for an idea, which has nothing to open: a disabled row
        // loses its swipes too.
        .opacity(store.busy == item.id ? 0.5 : 1)
        .srGlassRow()
        .accessibilityIdentifier("backlog-item-\(item.id)")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if item.status == "new" {
                Button { act(.done, item) } label: { Label(item.kind == "video" ? "Watched" : "Done", systemImage: "checkmark") }
                    .tint(SR.good)
            } else {
                Button { act(.reopen, item) } label: { Label("Back on the list", systemImage: "arrow.uturn.backward") }
                    .tint(SR.accentInk)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if FamilyBacklogRules.mayDelete(item, board) {
                Button(role: .destructive) { act(.delete, item) } label: { Label("Delete", systemImage: "trash") }
            }
            if item.status == "new" {
                Button { act(.dismiss, item) } label: { Label("Not for us", systemImage: "hand.thumbsdown") }
                    .tint(SR.warn)
            }
        }
        .contextMenu {
            if !board.quickReactions.isEmpty {
                let mine = FamilyBacklogRules.myReaction(item, board)
                let quick = board.quickReactions
                ForEach(Array(stride(from: 0, to: quick.count, by: 3)), id: \.self) { start in
                    ControlGroup {
                        ForEach(quick[start..<min(start + 3, quick.count)], id: \.self) { emoji in
                            Button(mine == emoji ? "\(emoji) ✓" : emoji) {
                                Task { await store.react(emoji, on: item) }
                            }
                        }
                    }
                    .controlGroupStyle(.compactMenu)
                }
            }
            if let link {
                Button { openURL(link) } label: { Label("Open", systemImage: "arrow.up.right.square") }
                ShareLink(item: link) { Label("Share", systemImage: "square.and.arrow.up") }
                Button { UIPasteboard.general.url = link } label: { Label("Copy link", systemImage: "doc.on.doc") }
            }
            if item.status == "new" {
                Button { act(.done, item) } label: { Label(item.kind == "video" ? "Watched" : "Done", systemImage: "checkmark") }
                Button { act(.dismiss, item) } label: { Label("Not for us", systemImage: "hand.thumbsdown") }
                Button { act(.toTask, item) } label: { Label("Make it a task", systemImage: "checklist") }
            } else {
                Button { act(.reopen, item) } label: { Label("Back on the list", systemImage: "arrow.uturn.backward") }
            }
            if FamilyBacklogRules.mayDelete(item, board) {
                Button(role: .destructive) { act(.delete, item) } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private func act(_ action: FamilyBacklogAction, _ item: FamilyBacklogItem) {
        Task { await store.act(action, on: item) }
    }

    /// The evening round-up: off unless this person turns it on. The switch
    /// moves at once and goes back if the site says no.
    private func digestSwitch(_ board: FamilyBacklogBoard) -> some View {
        Toggle(isOn: Binding(
            get: { board.digest },
            set: { on in Task { await store.setDigest(on) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Evening round-up")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text("At 7pm, what the family added that day — nothing on a quiet day. Things shared for you always come straight away.")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(SR.accent)
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 12)
        .srGlassCard(.paper)
        .accessibilityIdentifier("backlog-digest")
    }
}

/// "Pick one for tonight": one thing, big, with Open, Watched and Another.
struct FamilyBacklogPickSheet: View {
    let item: FamilyBacklogItem
    let board: FamilyBacklogBoard?
    let another: () -> Void
    let done: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                picture
                Text(FamilyBacklogText.title(item))
                    .font(SR.Text.bodyMedium(20))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(SR.Text.secondary(15))
                        .foregroundStyle(SR.inkSecondary)
                }
                if let board {
                    Text(FamilyBacklogRules.byline(item, board))
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 0)
                if let raw = item.url, let link = URL(string: raw) {
                    Button {
                        SRHaptic.tap()
                        openURL(link)
                    } label: {
                        Label("Open", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("backlog-pick-open")
                }
                HStack {
                    Button("Pick another") { SRHaptic.tap(); another() }
                        .accessibilityIdentifier("backlog-pick-another")
                    Spacer()
                    Button(item.kind == "video" ? "Watched" : "Done") { done() }
                }
                .font(SR.Text.bodyMedium(15))
            }
            .padding(20)
            .srPaper()
            .navigationTitle("Tonight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .tint(SR.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("backlog-pick-sheet")
    }

    @ViewBuilder
    private var picture: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let glyph = Image(systemName: FamilyBacklogRules.symbol(item))
            .font(.system(size: 40, weight: .medium))
            .foregroundStyle(SR.accentInk)
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(shape.fill(SR.ink.opacity(0.06)))
        if let raw = item.thumbnailUrl, let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(16 / 9, contentMode: .fill)
                        .frame(maxWidth: .infinity).clipShape(shape)
                } else {
                    glyph
                }
            }
            .accessibilityHidden(true)
        } else {
            glyph.accessibilityHidden(true)
        }
    }
}

/// One thing on the list: its picture (or a glyph), its title, where it is
/// from and who shared it, and the note they added.
struct FamilyBacklogRow: View {
    let item: FamilyBacklogItem
    let board: FamilyBacklogBoard

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(FamilyBacklogText.title(item))
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(item.status == "new" ? SR.ink : SR.inkMuted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let site = item.siteName ?? FamilyBacklogText.host(item.url) {
                    Text(site)
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(1)
                }
                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) { Rectangle().fill(SR.accent.opacity(0.5)).frame(width: 2) }
                }
                Text(FamilyBacklogRules.byline(item, board))
                    .font(SR.Text.label())
                    .foregroundStyle(item.forId == board.me.id && item.status == "new" ? SR.accentDeep : SR.inkMuted)
                if let reactions = item.reactions, !reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(reactions, id: \.emoji) { r in
                            Text(r.by.count > 1 ? "\(r.emoji) \(r.by.count)" : r.emoji)
                                .font(SR.Text.secondary(13))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(r.by.contains(board.me.id) ? SR.accent.opacity(0.22) : SR.ink.opacity(0.06)))
                                .accessibilityLabel("\(r.emoji) from \(FamilyBacklogRules.names(r, board))")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let tile = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let glyph = Image(systemName: FamilyBacklogRules.symbol(item))
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(SR.accentInk)
            .frame(width: 64, height: 64)
            .background(tile.fill(SR.ink.opacity(0.06)))
        // A TikTok picture is a signed link that expires within days; the
        // glyph is what stands in when it has.
        if let raw = item.thumbnailUrl, let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill().frame(width: 64, height: 64).clipShape(tile)
                } else {
                    glyph
                }
            }
            .accessibilityHidden(true)
        } else {
            glyph.accessibilityHidden(true)
        }
    }
}

/// + on the page: paste a link or write an idea, for everyone or somebody.
struct FamilyBacklogAddSheet: View {
    let people: [FamilyTaskPerson]
    let me: FamilyTaskMe?
    /// Nil when it went; else the sentence to show.
    let save: (FamilyBacklogShare) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var note = ""
    @State private var forId: String?
    @State private var saving = false
    @State private var refusal: String?
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("A link, or an idea", text: $text, axis: .vertical)
                        .font(SR.Text.body())
                        .lineLimit(1...4)
                        .focused($focused)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("backlog-text")
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .font(SR.Text.body())
                        .lineLimit(1...4)
                } header: {
                    SRSectionLabel(text: "Add")
                } footer: {
                    Text("From another app, Share → SR does the same.")
                        .font(SR.Text.secondary(13))
                }
                Section {
                    Picker("For", selection: $forId) {
                        Text("Everyone").tag(String?.none)
                        ForEach(people) { person in
                            Text(person.id == me?.id ? "\(person.name) (you)" : person.name).tag(Optional(person.id))
                        }
                    }
                    .accessibilityIdentifier("backlog-for")
                }
                if let refusal {
                    Section {
                        Text(refusal)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.error)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .srPaper()
            .navigationTitle("Add to the backlog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Add") {
                        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        let share = FamilyBacklogShare(url: nil, text: trimmed, note: note.isEmpty ? nil : note, forId: forId)
                        saving = true
                        Task {
                            let refused = await save(share)
                            saving = false
                            if let refused { refusal = refused } else { dismiss() }
                        }
                    }
                    .disabled(saving || trimmed.isEmpty)
                    .accessibilityIdentifier("backlog-save")
                }
            }
            .onChange(of: text) { _, _ in refusal = nil }
            // No reading the clipboard to fill this in: iOS asks "Allow
            // paste?" every time an app does, which is worse than a long press.
            .onAppear { focused = true }
        }
        .presentationDragIndicator(.visible)
    }
}

/// Today's backlog card: what was shared for you, how much is waiting, and
/// the newest two. Drawn only when there is something on the list — an empty
/// backlog is not news — and not while it is still loading.
struct TodayBacklogCard: View {
    @ObservedObject private var store = FamilyBacklogStore.shared
    let open: () -> Void

    var body: some View {
        if let board = store.board, !board.items.isEmpty {
            card(board)
        }
    }

    private func card(_ board: FamilyBacklogBoard) -> some View {
        let line = FamilyBacklogRules.todayLine(board)
        return Button {
            SRHaptic.tap()
            open()
        } label: {
            SRCard(interactive: true) {
                VStack(alignment: .leading, spacing: 12) {
                    SRSectionLabel(text: "Family backlog", trailing: line.forYou > 0 ? "\(line.forYou) for you" : nil, prominent: true)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(line.newest) { item in
                            HStack(spacing: 8) {
                                Image(systemName: FamilyBacklogRules.symbol(item))
                                    .font(.system(size: 13))
                                    .foregroundStyle(item.forId == board.me.id ? SR.accent : SR.inkMuted)
                                    .accessibilityHidden(true)
                                Text(FamilyBacklogText.title(item))
                                    .font(SR.Text.bodyMedium(15))
                                    .foregroundStyle(SR.ink)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Text(line.waiting == 1 ? "1 thing on the list" : "\(line.waiting) things on the list")
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the backlog")
        .accessibilityIdentifier("today-backlog")
    }
}
