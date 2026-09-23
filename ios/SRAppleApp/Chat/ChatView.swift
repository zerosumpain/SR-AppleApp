import SwiftUI

/// The thread library.
///
/// It used to open with the website's masthead — a lettered kicker, "PICK ONE
/// UP, / OR START AGAIN" set in Archivo Black across two hand-broken lines, and
/// a standfirst — and then a search box drawn by hand, and only then a thread.
/// On a 390×844 screen that is the whole of the first screenful spent on
/// furniture. A page can afford a masthead because a page is tall and a reader
/// arrived from somewhere else; a phone app is opened to do one thing, and here
/// that thing is "get me back into a conversation".
///
/// So: a large title the system draws and collapses on scroll, `.searchable` in
/// the bar, and rows from the first pixel of content.
struct ThreadListScreen: View {
    @StateObject private var store = ThreadListStore()
    @EnvironmentObject private var router: Router
    @State private var renaming: Conversation?
    @State private var renameDraft = ""
    @State private var deleting: Conversation?

    var body: some View {
        List {
            if store.query.isEmpty {
                SRPageHeader(kicker: "jkai", title: "Threads")
                    .srBareRow()
            }
            if !store.pinned.isEmpty && store.query.isEmpty {
                Section {
                    ForEach(store.pinned) { row($0) }
                } header: {
                    SRSectionLabel(text: "Pinned")
                }
            }

            Section {
                ForEach(store.unpinned) { conversation in
                    row(conversation)
                        .onAppear {
                            // Infinite scroll rather than an "Older threads"
                            // button. A button at the end of a list is a control
                            // you have to find; the list simply continuing is
                            // what every other iPhone list does.
                            if conversation.id == store.unpinned.last?.id { Task { await store.loadMore() } }
                        }
                }
                if store.loading && !store.conversations.isEmpty {
                    HStack { Spacer(); ProgressView().tint(SR.accent); Spacer() }
                        .srGlassRow().padding(.vertical, 12)
                }
            } header: {
                if !store.pinned.isEmpty && store.query.isEmpty {
                    SRSectionLabel(text: "Recent")
                }
            }
        }
        // Inset-grouped: on iOS 26 the sections are the rounded sheets the rest
        // of the system uses, and the atmosphere shows round their edges.
        .listStyle(.insetGrouped)
        .srGround(.quiet)
        .navigationTitle("Threads")
        // Inline, not large. A large title renders BLANK on this OS with this
        // appearance proxy — the bar lays out at full height and paints no text.
        // Verified in CI screenshots; inline titles in the same build draw in
        // Archivo Black correctly. A compact bar also gives a list more of the
        // screen, which on a phone is the thing actually being asked for.
        .navigationBarTitleDisplayMode(.inline)
        // Default placement: on iOS 26 that is the glass field the system puts
        // where the thumb is, rather than a drawer under the bar.
        .searchable(text: $store.query, prompt: "Search the archive")
        .onChange(of: store.query) { _, _ in store.search() }
        .srRefreshable { await store.load() }
        .toolbar {
            ToolbarItem(placement: .principal) { SRBarMark() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    SRHaptic.tap()
                    startThread()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New thread")
                .accessibilityIdentifier("thread-new")
            }
        }
        .overlay {
            if store.conversations.isEmpty && !store.loading {
                SREmpty(
                    title: store.query.isEmpty ? "No threads yet" : "Nothing matches that",
                    icon: store.query.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass",
                    message: store.query.isEmpty ? "Start one and it appears here, alongside everything that came in over WhatsApp." : nil,
                    actionLabel: store.query.isEmpty ? "New thread" : nil,
                    action: store.query.isEmpty ? startThread : nil
                )
            } else if store.loading && store.conversations.isEmpty {
                ProgressView().tint(SR.accent)
            }
        }
        .task { if store.conversations.isEmpty { await store.load() } }
        // `.id(...)` is load-bearing: `ChatScreen` builds its `StateObject` in
        // `init`, and a `StateObject` is created once per VIEW IDENTITY. Pushing
        // a second thread onto the same destination without this keeps the
        // first thread's store — the screen would show the wrong transcript.
        // The old code was a sheet, where identity changed for free.
        .navigationDestination(for: Conversation.self) { ChatScreen(conversation: $0).id($0.id) }
        .navigationDestination(for: ThreadReference.self) { ChatScreen(conversation: .placeholder(id: $0.id)).id($0.id) }
        // A question handed in by Siri, a Shortcut or the Home Screen's "Ask
        // jkai". It opens a NEW thread rather than the last one: a dictated
        // question has no context, and dropping it into whatever was last on
        // screen is how it ends up answered against the wrong conversation.
        .task(id: router.pendingQuestion) {
            guard router.pendingQuestion != nil, router.chat.isEmpty else { return }
            if let fresh = await store.create() { router.chat.append(fresh) }
        }
        .alert("Rename thread", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameDraft)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let target = renaming { Task { await store.rename(target, to: renameDraft) } }
                renaming = nil
            }
        }
        .confirmationDialog(
            "Delete this thread?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = deleting { Task { await store.delete(target) } }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("The whole conversation goes, on the website too. This cannot be undone.")
        }
        .overlay(alignment: .bottom) {
            if let message = store.message { SRBanner(text: message).padding(.bottom, 4) }
        }
    }

    /// Declared `-> Void` on purpose, and not written inline.
    ///
    /// A closure whose whole body is `Task { … }` INFERS its return type as
    /// `Task<(), Never>`, and coercing that into the `() -> Void` of an action
    /// tuple crashed swift-frontend outright — a stack dump, not a diagnostic,
    /// so the build failed with no file or line in the message. A function
    /// with a written return type never enters that inference.
    ///
    /// `swiftc -parse` cannot see this. It is a type-checker crash, and
    /// parsing resolves no types at all — which is the honest limit of the
    /// pre-flight check and the reason the macOS job is the real gate.
    private func startThread() {
        Task {
            if let fresh = await store.create() { router.chat.append(fresh) }
        }
    }

    @ViewBuilder
    private func row(_ conversation: Conversation) -> some View {
        NavigationLink(value: conversation) {
            ThreadRow(conversation: conversation)
        }
        .srGlassRow()
        .accessibilityIdentifier("thread-\(conversation.id)")
        // Leading swipe is the reversible one. Nothing destructive lives on a
        // swipe: a thread deleted by a thumb on the train is gone from the
        // website too, so that costs a long press and a confirmation.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                SRHaptic.select()
                Task { await store.togglePin(conversation) }
            } label: {
                Label(conversation.pinned ? "Unpin" : "Pin", systemImage: conversation.pinned ? "pin.slash" : "pin")
            }
            .tint(SR.accent)
        }
        .contextMenu {
            Button {
                renameDraft = conversation.displayTitle
                renaming = conversation
            } label: { Label("Rename", systemImage: "pencil") }
            Button {
                Task { await store.togglePin(conversation) }
            } label: { Label(conversation.pinned ? "Unpin" : "Pin", systemImage: "pin") }
            Link(destination: SiteClient.shared.webURL("jkai")) {
                Label("Open jkai on the web", systemImage: "safari")
            }
            Divider()
            Button(role: .destructive) { deleting = conversation } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// One thread. Title, a sub-line of provenance, and the last thing said.
struct ThreadRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The source, as a glyph in a disc: a thread that came in over
            // WhatsApp and one started here are different kinds of thing.
            Image(systemName: conversation.isWhatsApp ? "phone.bubble" : "sparkle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(conversation.isWhatsApp ? SR.good : SR.accent)
                .frame(width: 34, height: 34)
                .background((conversation.isWhatsApp ? SR.good : SR.accent).opacity(0.12), in: Circle())
                .padding(.top, 2)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                if conversation.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(SR.accent)
                }
                Text(conversation.displayTitle)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let updated = conversation.updatedAt {
                    Text(shortAgo(updated))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
            }

            if let preview = conversation.oneLinePreview {
                Text(preview)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            if conversation.isWhatsApp {
                Text("WhatsApp")
                    .font(SR.Text.mono())
                    .tracking(1)
                    .foregroundStyle(SR.good)
            }
        }
        }
        .padding(.vertical, 6)
        .frame(minHeight: SR.tapTarget, alignment: .leading)
    }
}

/// One conversation.
///
/// Pushed, not presented as a sheet. A sheet cannot be swiped back from its
/// left edge, so the only way out was a bar button — and a modal over a tab bar
/// is what an iPhone uses for a task you finish and dismiss, not for a place you
/// go. Reading a thread is a place.
struct ChatScreen: View {
    let conversation: Conversation
    @StateObject private var store: ChatStore
    @EnvironmentObject private var router: Router
    @State private var draft = ""
    @State private var atBottom = true
    @FocusState private var composerFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(conversation: Conversation) {
        self.conversation = conversation
        _store = StateObject(wrappedValue: ChatStore(conversationId: conversation.id))
    }

    private var bottomAnchor: String { "sr-transcript-foot" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if store.hasOlder {
                        Button {
                            Task { await store.loadOlder() }
                        } label: {
                            Text(store.loading ? "Loading…" : "Earlier turns")
                                .font(SR.Text.label())
                                .tracking(1.2)
                                .foregroundStyle(SR.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.loading)
                    }

                    ForEach(store.messages) { message in
                        ChatBubble(message: message).id(message.id)
                    }

                    if !store.activity.isEmpty {
                        TurnActivityPanel(activity: store.activity)
                    }

                    if let blocked = store.blocked {
                        BlockedTurnCard(blocked: blocked)
                    }

                    // A zero-height anchor at the foot, so "scroll to the
                    // bottom" means the bottom of the transcript and not the
                    // top of the last bubble. Scrolling to `messages.last`
                    // parks a long answer's first line at the bottom of the
                    // screen with the rest of it below the fold, which reads as
                    // the app having stopped.
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.horizontal, SR.gutter)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .srGround(.quiet)
            .scrollDismissesKeyboard(.interactively)
            // Dragging up means "I am reading something", and an answer that
            // keeps arriving must not snatch the view back. `atBottom` goes
            // false on any drag and true again when the reader sends, taps the
            // jump pill, or opens the thread.
            .simultaneousGesture(DragGesture().onChanged { value in
                if value.translation.height > 6 { atBottom = false }
            })
            // The stream appends CHARACTERS to the last bubble, not messages to
            // the array, so following `messages.count` follows nothing once the
            // answer has started. `streamTick` moves on every frame.
            .onChange(of: store.streamTick) { _, _ in follow(proxy) }
            .onChange(of: store.messages.count) { _, _ in follow(proxy, animated: true) }
            .onChange(of: composerFocused) { _, focused in if focused { follow(proxy, animated: true) } }
            .task {
                if let question = router.pendingQuestion {
                    // Seeded, not sent. See AskJkaiIntent for why.
                    draft = question
                    router.pendingQuestion = nil
                    composerFocused = true
                }
                await store.load()
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .overlay(alignment: .bottom) {
            if !atBottom && store.sending {
                Button {
                    SRHaptic.tap()
                    atBottom = true
                } label: {
                    Label("Latest", systemImage: "arrow.down")
                        .font(SR.Text.label())
                        .tracking(1.1)
                        .foregroundStyle(SR.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .srGlass(.paper, in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 84)
                .transition(.opacity)
            }
        }
        .navigationTitle(store.title ?? conversation.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        // A thread is the composer's screen. The tab bar under it was a second
        // floating bar competing for the thumb.
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Link(destination: SiteClient.shared.webURL("jkai")) {
                        Label("Open jkai on the web", systemImage: "safari")
                    }
                    Button {
                        Task { await store.load() }
                    } label: { Label("Reload", systemImage: "arrow.clockwise") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Thread actions")
            }
        }
        // Handoff: the same thread, open on the desk. `isEligibleForHandoff`
        // is what puts it on the Mac's dock, and the web URL is what the Mac
        // opens — there is no Mac app to hand off to.
        .userActivity("com.strangeramblings.com.appleapp.thread") { activity in
            activity.title = store.title ?? conversation.displayTitle
            activity.webpageURL = SiteClient.shared.webURL("jkai")
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
        }
        // Dropping the stream on disappear is SHEET-shaped thinking. In a
        // navigation stack this also fires when the reader switches tabs, so a
        // turn in flight lost its connection the moment you glanced at Today.
        // The turn itself keeps running server-side — that part was always
        // true — but the transcript stopped filling in and only a reload
        // recovered it. So: drop the socket to save the battery, and pick the
        // same job up from its last sequence number on the way back.
        .onDisappear { store.stop() }
        .onAppear { store.resume() }
    }

    private func follow(_ proxy: ScrollViewProxy, animated: Bool = false) {
        guard atBottom else { return }
        // A transcript that animates itself downward thirty times a second is
        // motion, and a reader who has asked for less of it has asked about
        // exactly this. The view still follows; it just arrives.
        if animated && !reduceMotion {
            withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
        } else {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    /// The composer, pinned above the keyboard by the safe area rather than
    /// stacked under the scroll view.
    ///
    /// In a `VStack` the composer is laid out once and the keyboard pushes the
    /// whole screen, which on a short phone pushes the navigation bar off the
    /// top. `safeAreaInset` is the arrangement iOS itself uses: the scroll view
    /// keeps its full height and simply insets its content, so the last turn
    /// stays visible with the keyboard up.
    private var composer: some View {
        VStack(spacing: 8) {
            // The banner sits INSIDE the composer's stack rather than as an
            // overlay pushed up by a guessed 70 points. The composer grows with
            // the draft — one to six lines — and with the reader's text size, so
            // any fixed offset is wrong for most of its range.
            if let message = store.message {
                SRBanner(text: message, tone: SR.error)
            }
            // A floating glass capsule, the shape iOS 26 gives every composer:
            // the transcript runs on underneath it, and nothing hard-edged
            // separates the two.
            SRGlassGroup(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Message jkai", text: $draft, axis: .vertical)
                        .font(SR.Text.body())
                        .foregroundStyle(SR.ink)
                        .lineLimit(1...6)
                        .focused($composerFocused)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(minHeight: 48)
                        .srGlass(.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .accessibilityIdentifier("chat-composer")

                    Button {
                        if store.sending {
                            SRHaptic.tap()
                            Task { await store.cancel() }
                        } else {
                            let text = draft
                            draft = ""
                            atBottom = true
                            SRHaptic.tap()
                            Task { await store.send(text) }
                        }
                    } label: {
                        Image(systemName: store.sending ? "stop.fill" : "arrow.up")
                            .font(.system(size: store.sending ? 14 : 17, weight: .bold))
                            .foregroundStyle(sendable || store.sending ? SR.paper : SR.inkMuted)
                            .frame(width: 48, height: 48)
                            .srGlass(sendable || store.sending ? .accent : .paper, in: Circle(), interactive: true)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!sendable && !store.sending)
                    .accessibilityLabel(store.sending ? "Stop" : "Send")
                    .accessibilityIdentifier("chat-send")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private var sendable: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
