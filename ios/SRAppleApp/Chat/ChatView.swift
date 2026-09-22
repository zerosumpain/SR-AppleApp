import SwiftUI

/// The thread library.
///
/// Built on the TRIPWIRE LEDGER — the one /health pattern for dense rows: 14pt
/// top-aligned cells, a two-line signal cell (the name, then a sub-label), and
/// the explaining sentence in BODY font rather than mono. It is the shape that
/// fixes a cramped surface, and a list of 400 threads is exactly that.
///
/// It sits on ink, which is where the tripwire table sits, and is the app's one
/// dense ledger. Everything else stays paper — a tall solid ink area reads as
/// intensity, not editorial.
struct ThreadListScreen: View {
    @StateObject private var store = ThreadListStore()
    @State private var open: Conversation?

    var body: some View {
        SRShell(
            path: "/jkai",
            kicker: store.conversations.isEmpty ? nil : "\(store.conversations.count) threads"
        ) {
            SRSection {
                SectionHead(
                    kicker: "A / Threads",
                    title: ["Pick one up,", "or start again"],
                    strap: "Every conversation from the desk and from WhatsApp, newest first. Search reaches the whole archive, not just this page."
                )
                searchField
            }

            SRSection(tinted: true, isLast: true) {
                if store.loading && store.conversations.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().tint(SR.accent)
                        Text("Reading the archive…").font(SR.body(14)).foregroundStyle(SR.inkMuted)
                    }
                    .padding(.vertical, 20)
                } else if store.conversations.isEmpty {
                    Text(store.query.isEmpty ? "No threads yet." : "Nothing matches that.")
                        .font(SR.body(15))
                        .foregroundStyle(SR.inkMuted)
                        .padding(.vertical, 20)
                } else {
                    SRLedger {
                        ForEach(store.conversations) { conversation in
                            ThreadRow(conversation: conversation) { open = conversation }
                        }
                    }
                    if store.hasMore {
                        SRButton(title: store.loading ? "Loading…" : "Older threads", disabled: store.loading) {
                            Task { await store.loadMore() }
                        }
                        .padding(.top, 16)
                    }
                }
            }
        }
        .task { if store.conversations.isEmpty { await store.load() } }
        .refreshable { await store.load() }
        .overlay(alignment: .bottom) {
            if let message = store.message { SRToast(text: message) }
        }
        .sheet(item: $open) { conversation in
            ChatScreen(conversation: conversation)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(SR.inkMuted)
            TextField("Search the archive", text: $store.query)
                .font(SR.body(15))
                .foregroundStyle(SR.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: store.query) { _, _ in store.search() }
                .onSubmit { Task { await store.load() } }
                .accessibilityIdentifier("thread-search")
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                    Task { await store.load() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SR.inkGhost)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
    }
}

/// One row: a two-line signal cell, then the sentence in body font.
struct ThreadRow: View {
    let conversation: Conversation
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if conversation.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(SR.accent)
                        }
                        Text(conversation.displayTitle)
                            .font(SR.bodyMedium(16))
                            .foregroundStyle(SR.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // The sub-label under the name — the second line of the
                    // signal cell.
                    HStack(spacing: 8) {
                        if conversation.isWhatsApp {
                            SRPill(text: "WhatsApp", tone: SR.good)
                        }
                        Text("\(conversation.messageCount) turn\(conversation.messageCount == 1 ? "" : "s")")
                            .font(SR.mono(12))
                            .foregroundStyle(SR.inkGhost)
                        if let updated = conversation.updatedAt {
                            Text(shortAgo(updated))
                                .font(SR.mono(12))
                                .foregroundStyle(SR.inkGhost)
                        }
                    }

                    if let preview = conversation.oneLinePreview {
                        Text(preview)
                            .font(SR.body(14))
                            .foregroundStyle(SR.inkSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SR.inkGhost)
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SR.paper)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("thread-\(conversation.id)")
    }
}

/// One conversation.
struct ChatScreen: View {
    let conversation: Conversation
    @StateObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    init(conversation: Conversation) {
        self.conversation = conversation
        _store = StateObject(wrappedValue: ChatStore(conversationId: conversation.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            SRTopBar(
                path: "/jkai",
                kicker: store.title ?? conversation.displayTitle,
                back: (label: "Threads", action: { dismiss() })
            )

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if store.hasOlder {
                            SRButton(title: store.loading ? "Loading…" : "Earlier turns", disabled: store.loading) {
                                Task { await store.loadOlder() }
                            }
                            .padding(.bottom, 4)
                        }

                        ForEach(store.messages) { message in
                            ChatBubble(message: message).id(message.id)
                        }

                        if !store.activity.isEmpty {
                            TurnActivityPanel(activity: store.activity).id("activity")
                        }

                        if let blocked = store.blocked {
                            BlockedTurnCard(blocked: blocked)
                        }
                    }
                    .padding(.horizontal, SR.gutter)
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(SR.paper)
                .onChange(of: store.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(store.messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: store.activity) { _, _ in
                    withAnimation { proxy.scrollTo("activity", anchor: .bottom) }
                }
            }

            composer
        }
        .background(SR.paper)
        .task { await store.load() }
        .overlay(alignment: .bottom) {
            if let message = store.message { SRToast(text: message) }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(SR.line).frame(height: 1)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Say something", text: $draft, axis: .vertical)
                    .font(SR.body(16))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
                    .accessibilityIdentifier("chat-composer")

                if store.sending {
                    Button {
                        Task { await store.cancel() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(SR.paper)
                            .frame(width: 44, height: 42)
                            .background(SR.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop")
                } else {
                    Button {
                        let text = draft
                        draft = ""
                        Task { await store.send(text) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(SR.paper)
                            .frame(width: 44, height: 42)
                            .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? SR.inkGhost : SR.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("chat-send")
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 12)
            .background(SR.paper)
        }
    }
}
