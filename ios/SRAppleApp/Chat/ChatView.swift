import SwiftUI
import PhotosUI

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

            // A search answers in relevance order, which dates would scramble:
            // one section. Otherwise the unpinned threads by when they were
            // last touched — see `ThreadSections`.
            if store.query.isEmpty {
                ForEach(store.sections) { group in
                    Section {
                        ForEach(group.threads) { conversation in listed(conversation) }
                    } header: {
                        SRSectionLabel(text: group.title, trailing: "\(group.threads.count)")
                    }
                }
            } else {
                Section {
                    ForEach(store.unpinned) { conversation in listed(conversation) }
                } header: {
                    if !store.unpinned.isEmpty {
                        SRSectionLabel(text: "Results", trailing: "\(store.unpinned.count)")
                    }
                }
            }
            if store.loading && !store.conversations.isEmpty {
                HStack { Spacer(); ProgressView().tint(SR.accent); Spacer() }
                    .srGlassRow().padding(.vertical, 12)
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
        // Files shared in from another app get a new thread for the same
        // reason: they arrive with no context, and the last thread on screen is
        // not where "what is this?" should be asked.
        .task(id: router.pendingFiles) {
            guard !router.pendingFiles.isEmpty, router.chat.isEmpty else { return }
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

    /// A row that pages the list on: infinite scroll rather than an "Older
    /// threads" button. A button at the end of a list is a control you have to
    /// find; the list simply continuing is what every other iPhone list does.
    private func listed(_ conversation: Conversation) -> some View {
        row(conversation)
            .onAppear {
                if conversation.id == store.unpinned.last?.id { Task { await store.loadMore() } }
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

            // Only when it says something the title does not: a thread the
            // site has not named yet is TITLED by its last line already.
            if let preview = conversation.oneLinePreview,
               Conversation.clip(preview) != conversation.displayTitle {
                Text(preview)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
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
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var choosingPhotos = false
    @State private var choosingFiles = false
    @State private var takingPhoto = false
    @State private var showingModel = false
    /// A member's thread runs on what the site chose (the model route answers
    /// `locked`), takes no voice notes (the upload lane refuses audio) and
    /// attaches images, PDFs, documents and text only. The owner's is as it was.
    @ObservedObject private var access = AccessStore.shared
    @StateObject private var recorder = VoiceRecorder()
    /// Whether a thumb is still on the mic. Plain state, read by the async
    /// start: a release that lands before the recorder is up must still stop it.
    @State private var holdingMic = false
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

                    if let plan = store.plan {
                        PlanCard(plan: plan, answering: store.answering) { decision, adjustment in
                            atBottom = true
                            Task { await store.answerPlan(decision, adjustment: adjustment) }
                        }
                    }

                    if let clarify = store.clarify {
                        ClarifyCard(gate: clarify, answering: store.answering) { answers in
                            atBottom = true
                            Task { await store.answerClarify(answers) }
                        }
                    }

                    if showsStarters {
                        StarterPrompts { prompt in
                            atBottom = true
                            Task { await store.send(prompt) }
                        }
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
                // Files handed in from another app's Share sheet ("Open in").
                if !router.pendingFiles.isEmpty {
                    let urls = router.pendingFiles
                    router.pendingFiles = []
                    for url in urls { attachFile(url) }
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
                    if access.current.owner {
                        Button {
                            showingModel = true
                        } label: { Label("Model & thinking", systemImage: "cpu") }
                    }
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
        .sheet(isPresented: $showingModel) {
            ThreadModelSheet(conversationId: conversation.id)
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
        pickers(VStack(spacing: 8) {
            // The banner sits INSIDE the composer's stack rather than as an
            // overlay pushed up by a guessed 70 points. The composer grows with
            // the draft — one to six lines — and with the reader's text size, so
            // any fixed offset is wrong for most of its range.
            if let message = store.message {
                SRBanner(text: message, tone: SR.error)
            }
            if !store.pending.isEmpty {
                PendingAttachmentStrip(items: store.pending) { store.removePending($0) }
            }
            // A floating glass capsule, the shape iOS 26 gives every composer:
            // the transcript runs on underneath it, and nothing hard-edged
            // separates the two.
            SRGlassGroup(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    attachMenu

                    if recorder.recording {
                        recordingPill
                    } else if store.transcribing {
                        transcribingPill
                    } else {
                        TextField(store.pending.isEmpty ? "Message jkai" : "Say something about it", text: $draft, axis: .vertical)
                            .font(SR.Text.body())
                            .foregroundStyle(SR.ink)
                            .lineLimit(1...6)
                            .focused($composerFocused)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .frame(minHeight: 48)
                            .srGlass(.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .accessibilityIdentifier("chat-composer")
                    }

                    if showsMic { micButton } else { sendButton }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        })
    }

    /// Send, or Stop while a turn runs.
    private var sendButton: some View {
        Button {
            if store.sending {
                SRHaptic.tap()
                Task { await store.cancel() }
            } else {
                let text = draft
                clearDraft()
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

    /// A thread with nothing in it yet, and nothing on its way.
    private var showsStarters: Bool {
        store.messages.isEmpty && !store.loading && !store.sending
            && store.blocked == nil && store.plan == nil && store.clarify == nil
    }

    // MARK: - Voice

    /// The mic takes the send button's place while there is nothing to send —
    /// Messages' arrangement, so one circle does one job at a time.
    ///
    /// Owner only: a member's upload lane takes no audio, so a voice note is
    /// never offered rather than recorded and refused.
    private var showsMic: Bool {
        access.current.owner
            && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && store.pending.isEmpty && !store.sending
    }

    private var micButton: some View {
        Image(systemName: recorder.recording ? "waveform" : "mic.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(recorder.recording ? SR.paper : SR.ink)
            .frame(width: 48, height: 48)
            .srGlass(recorder.recording ? .accent : .paper, in: Circle(), interactive: true)
            .contentShape(Circle())
            // Pressing starts, lifting sends. `onPressingChanged` fires on touch
            // down, which is when a hold-to-talk control has to start listening.
            .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 80, perform: {}, onPressingChanged: { pressing in
                pressing ? beginRecording() : endRecording()
            })
            .accessibilityLabel("Hold to record a voice note")
            .accessibilityIdentifier("chat-mic")
    }

    private var recordingPill: some View {
        HStack(spacing: 10) {
            Circle().fill(SR.error).frame(width: 8, height: 8)
            Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern: .minuteSecond)))
                .font(SR.Text.mono(14))
                .foregroundStyle(SR.ink)
            Text("Release to send")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 48)
        .srGlass(.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Between letting go of the mic and the turn going out: the phone is
    /// reading the recording. Usually about a second.
    private var transcribingPill: some View {
        HStack(spacing: 10) {
            ProgressView().tint(SR.accent)
            Text("Transcribing…")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 48)
        .srGlass(.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat-transcribing")
    }

    private func beginRecording() {
        holdingMic = true
        SRHaptic.tap()
        Task {
            do {
                try await recorder.start()
                // Lifted while the recorder was still starting.
                if !holdingMic { recorder.cancel() }
            } catch VoiceRecorder.Failure.denied {
                store.message = "Microphone access is off for this app. Settings → SR → Microphone."
            } catch {
                store.message = "The microphone could not start."
            }
        }
    }

    private func endRecording() {
        holdingMic = false
        guard recorder.recording else { return }
        if let data = recorder.stop() {
            SRHaptic.ok()
            atBottom = true
            Task { await store.sendVoiceNote(data) }
        } else {
            store.message = "Hold the mic to record a voice note."
        }
    }

    /// The photo, file and camera pickers the attach menu opens. Split out of
    /// `composer` so neither is a single expression big enough to stall the
    /// type checker.
    private func pickers<Content: View>(_ content: Content) -> some View {
        content
        .photosPicker(
            isPresented: $choosingPhotos,
            selection: $photoItems,
            maxSelectionCount: max(1, ChatStore.maxAttachments - store.pending.count),
            matching: .images
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            // Emptied first so picking the same photo twice still changes it.
            photoItems = []
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        store.attachPhoto(image)
                    } else {
                        store.message = "That photo could not be read."
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $choosingFiles,
            allowedContentTypes: ChatUpload.documentTypes,
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            for url in urls { attachFile(url) }
        }
        .fullScreenCover(isPresented: $takingPhoto) {
            CameraPicker { store.attachPhoto($0) }
                .ignoresSafeArea()
        }
    }

    /// Photo, camera, file — one button, the way Messages does it.
    ///
    /// A menu rather than three icons: the composer is a capsule a thumb has to
    /// hit, and three more targets beside the field would halve it.
    private var attachMenu: some View {
        Menu {
            Button { choosingPhotos = true } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
            if CameraPicker.isAvailable {
                Button { takingPhoto = true } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
            Button { choosingFiles = true } label: {
                Label("Choose File", systemImage: "doc")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SR.ink)
                .frame(width: 48, height: 48)
                .srGlass(.paper, in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .disabled(store.sending || !store.canAttachMore)
        .accessibilityLabel("Attach")
        .accessibilityIdentifier("chat-attach")
    }

    /// A file from the Files picker. Photos go through the photo path so they
    /// are resized and re-encoded like any other.
    private func attachFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            // A file shared in from another app is a COPY the system dropped in
            // Documents/Inbox. Once read it is in the upload; leaving it would
            // grow a folder nobody can see.
            if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
        }
        guard let data = try? Data(contentsOf: url) else {
            store.message = "\(url.lastPathComponent) could not be read."
            return
        }
        let mime = ChatUpload.mimeType(for: url)
        // The Files picker already offers only allowed types; a file shared in
        // from another app has not been through it.
        guard ChatUpload.allowed(mime: mime, owner: access.current.owner) else {
            store.message = "\(url.lastPathComponent) can't be sent from this iPhone."
            return
        }
        if mime.hasPrefix("image/"), let image = UIImage(data: data) {
            store.attachPhoto(image)
        } else {
            store.attach(data, filename: url.lastPathComponent, mimeType: mime)
        }
    }

    /// Empty the composer after a send — and then do it again a moment later.
    ///
    /// Setting the binding once was the whole of the old code, and on a phone
    /// the sent text stayed in the box. The vertical `TextField` is a
    /// `UITextView`, and the keyboard can still be holding input the binding
    /// never saw — an inline prediction, an autocorrection waiting on the next
    /// space, a dictation segment. The clear lands, the text view then commits
    /// that pending input, and the whole draft is written back through the
    /// binding. That is the diagnosis the symptom fits; it was not reproduced,
    /// because the simulator has no predictive keyboard to hold anything.
    ///
    /// The second clear lands after that commit. Nobody types a character in
    /// the gap, so it can only ever remove the sent text.
    private func clearDraft() {
        draft = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { draft = "" }
    }

    private var sendable: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.uploading
    }
}
