import SwiftUI

/// "msg family": one line to everyone in the family, pushed to their phones,
/// and their answers — an emoji from the quick set, or a reply.
///
/// Reached from Chat ("msg family" on its Family side), from a tapped message
/// notification, and from the hub for somebody without Chat.
///
/// Read like WhatsApp since 2026-10-27 (John: "the messaging pages need
/// tidying up … organising like WhatsApp so it's easy to distinguish replies
/// and your own messages. It should also focus on recent messages showing the
/// latest on open"). The site still keeps threads — a message and the replies
/// under it — but the screen draws them as one conversation in time order
/// (`FamilyChatStream`): your own lines on the right in your colour, everyone
/// else's on the left with their name and circle, a run from one person
/// grouped under one name, and a reply with the message it answers quoted
/// over it. It opens at the newest line and follows new ones in.
///
/// Kept from before: the "New" line over what came in since this phone last
/// had it open, day headings, search, pins (now a bar along the top), polls,
/// @mentions, the emoji, "Remind me later" and Share on the long press, and
/// the box's quick messages, "where I am", counter and saved draft. A tap on
/// a line opens its thread (`FamilyThreadScreen`); "Reply" on the long press
/// quotes it in the box instead. "Family now" — who is where, the quick lines
/// and the bat phone, and the suggestions (`FamilyChatLanding`) — moved from
/// under the newest thread, where it pushed the newest lines off the screen,
/// to a button in the bar.
struct FamilyMessagesScreen: View {
    @ObservedObject private var store = FamilyMessagesStore.shared
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = FamilyMessagesStore.draft("new")
    /// A message of mine, waiting on "Delete?".
    @State private var deleting: FamilyThreadDeleting?
    @State private var query = ""
    /// The poll sheet, blank or written out by a suggestion.
    @State private var pollDraft: FamilyPollDraft?
    /// Bumped to bring the keyboard up: something has just put words in the
    /// box, or "Reply" was chosen.
    @State private var focusRequest = 0
    /// A person's page, opened from "Family now".
    @State private var personPage: FamilyPersonRoute?
    /// When msg family was last read, as it stood when this screen opened:
    /// the "New" line stays where it was for the whole visit.
    @State private var openedReadAt: Date?
    @State private var opened = false
    /// The line being answered from the box: its thread gets the reply.
    @State private var replyingTo: FamilyChatStream.Line?
    @State private var showingNow = false
    /// Where to scroll next: a line's id, "new-line" or "bottom".
    @State private var scrollTarget: String?

    var body: some View {
        let faces = FamilyFaces()
        // Before the screen has appeared, the mark it is about to take — so
        // the first frame already draws the "New" line where it stays.
        let since = opened ? openedReadAt : store.readAt
        let all = store.stream
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let shown = searching ? all.filter(matches) : all
        let firstNew = searching ? nil : FamilyChatStream.firstNew(shown, since: since)
        let newCount = FamilyChatStream.newCount(shown, since: since)
        let me = store.myName
        let names = store.mentionNames
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if all.isEmpty {
                        if store.loaded {
                            SREmpty(
                                title: "No messages yet",
                                icon: "bubble.left.and.text.bubble.right",
                                message: store.message ?? "Write one below. It goes to everyone in the family as a notification."
                            )
                            .padding(.top, 24)
                            // Nothing to read yet, so the family as it is now
                            // is the page — not a button away.
                            landing(since: since, jumpToNew: nil)
                        } else {
                            ProgressView().tint(SR.accent).frame(maxWidth: .infinity).padding(.vertical, 60)
                        }
                    } else if shown.isEmpty {
                        SREmpty(title: "Nothing matches", icon: "magnifyingglass", message: "Search looks through every message, reply and name.")
                            .padding(.top, 40)
                    }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, line in
                        if let day = searching ? searchDay(index, in: shown) : line.day {
                            FamilyDayHeading(title: day)
                        }
                        if index == firstNew {
                            FamilyNewLine(count: newCount).id("new-line")
                        }
                        row(line, first: searching || line.startsGroup, last: searching || line.endsGroup,
                            faces: faces, names: names, me: me)
                            .id(line.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            // Opens at the foot, where the newest line is.
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: all.last?.id) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            // The feed arriving after the first frame (a cold open) lays the
            // page out again: put the foot back in view once it has.
            .onChange(of: store.loaded) { _, _ in
                Task { @MainActor in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.snappy) { proxy.scrollTo(target, anchor: target == "bottom" ? .bottom : .center) }
                scrollTarget = nil
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search messages")
        .safeAreaInset(edge: .top, spacing: 0) {
            if !searching { pinnedBar }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                if let notice = store.notice {
                    SRBanner(text: notice)
                        .padding(.horizontal, 12)
                        .task(id: notice) {
                            try? await Task.sleep(for: .seconds(3))
                            if store.notice == notice { store.notice = nil }
                        }
                }
                if let replyingTo {
                    FamilyReplyingBar(line: replyingTo, faces: faces) { self.replyingTo = nil }
                }
                FamilyComposerAccessories(draft: $draft, names: names) { pollDraft = FamilyPollDraft() }
                FamilyMessageComposer(
                    draft: $draft,
                    placeholder: replyingTo.map { "Reply to \($0.mine ? "yourself" : FamilyMessagesStore.first($0.name))" }
                        ?? "Message the family",
                    busy: store.isBusy(replyingTo?.thread ?? "new"),
                    error: all.isEmpty ? nil : store.message,
                    identifier: "family-msg",
                    focusRequest: focusRequest
                ) {
                    send()
                }
            }
        }
        .srPaper()
        .accessibilityIdentifier("family-messages-screen")
        .navigationTitle("msg family")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    SRHaptic.tap()
                    showingNow = true
                } label: {
                    Image(systemName: "person.2.circle")
                }
                .accessibilityLabel("Family now")
                .accessibilityHint("Who is where, the one-tap messages, the bat phone and ideas")
                .accessibilityIdentifier("family-now")
            }
        }
        .task { await store.load() }
        .task { await FamilyPhotos.shared.load() }
        .task { await FamilyChatLanding.refresh() }
        .srRefreshable { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.load() }
            Task { await FamilyChatLanding.refresh() }
        }
        .onAppear {
            // The "New" line is drawn against when it was last read; reading it
            // now moves the mark for next time.
            if !opened { openedReadAt = store.readAt; opened = true }
            store.markRead()
        }
        .onChange(of: store.lastActivityISO) { _, _ in store.markRead() }
        .onDisappear { store.markRead() }
        .onChange(of: draft) { _, text in FamilyMessagesStore.saveDraft(text, for: "new") }
        .sheet(item: $pollDraft) { written in
            FamilyPollComposer(question: written.question, options: written.options) { poll in await store.send(poll.body) }
        }
        .navigationDestination(item: $personPage) { route in
            FamilyChatPersonPage(subject: route.subject)
        }
        .familyThreadDelete($deleting, store: store)
        .background {
            // On a view of its own: one sheet per view (see `Router.sheet`).
            Color.clear.sheet(isPresented: $showingNow) { nowSheet(since: since, jumpToNew: firstNew == nil ? nil : "new-line") }
        }
    }

    // MARK: - Sending

    /// The box: a reply to the quoted line's thread, or a new message.
    private func send() {
        let text = draft
        if let target = replyingTo {
            Task {
                if await store.reply(to: target.thread, text) {
                    draft = ""
                    replyingTo = nil
                }
            }
        } else {
            Task { if await store.send(text) { draft = "" } }
        }
    }

    /// Words into the box, after whatever is there already — nothing unsent
    /// is lost — with the keyboard up.
    private func addToBox(_ words: String) {
        let kept = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = kept.isEmpty ? words : kept + " " + words
        focusRequest += 1
    }

    private func replyTo(_ line: FamilyChatStream.Line) {
        SRHaptic.select()
        replyingTo = line
        focusRequest += 1
    }

    private func matches(_ line: FamilyChatStream.Line) -> Bool {
        FamilyMessageTools.matches(query, in: [line.body, line.name, line.quote?.text ?? ""])
    }

    /// A day heading among search results, which skip days.
    private func searchDay(_ index: Int, in lines: [FamilyChatStream.Line]) -> String? {
        guard let at = lines[index].at else { return nil }
        let day = FamilyMessageTools.dayTitle(at, now: Date())
        if index > 0, let before = lines[index - 1].at, FamilyMessageTools.dayTitle(before, now: Date()) == day { return nil }
        return day
    }

    private func openThread(_ id: String) {
        SRHaptic.tap()
        router.push(FamilyThreadRef(id: id), on: router.tab)
    }

    // MARK: - A line

    /// One bubble. A tap opens its thread; the long press replies, reacts,
    /// pins, reminds, copies, shares and deletes.
    private func row(_ line: FamilyChatStream.Line, first: Bool, last: Bool, faces: FamilyFaces,
                     names: [String], me: String?) -> some View {
        let message = store.threadMessage(line.thread)
        let poll = line.reply ? nil : FamilyPoll.parse(line.body)
        return FamilyChatBubble(
            line: line, message: line.reply ? nil : message, first: first, last: last, faces: faces,
            names: names, me: me, pinned: !line.reply && store.pinned.contains(line.id),
            quoteTapped: { scrollTarget = line.thread }
        )
        .opacity(store.isBusy(line.id) ? 0.5 : 1)
        .onTapGesture { openThread(line.thread) }
        .contextMenu {
            Button {
                replyTo(line)
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
            if let message, !line.reply {
                FamilyMessageAnswers(message: message, store: store, deleting: $deleting) { openThread(line.thread) }
            } else {
                Button {
                    openThread(line.thread)
                } label: {
                    Label("Open the thread", systemImage: "bubble.left.and.bubble.right")
                }
                FamilyReplyActions(body: line.body, name: line.name, mine: line.mine) {
                    deleting = FamilyThreadDeleting(id: line.id, title: "Delete your reply?", detail: "“\(line.body)” goes for everyone.")
                }
            }
        }
        // A poll's options are read out on their own; anything else as one.
        .accessibilityElement(children: poll == nil ? .combine : .contain)
        .accessibilityLabel(poll == nil ? Text(FamilyChatBubble.spoken(line)) : Text(""))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the thread. Touch and hold to reply or react.")
        .accessibilityAction(named: "Reply") { replyTo(line) }
        .accessibilityIdentifier(line.reply ? "family-reply-\(line.id)" : "family-message-\(line.id)")
    }

    // MARK: - Pins

    /// Pinned messages, on this phone only: a bar along the top, as WhatsApp
    /// pins one. The newest pinned is shown; a menu lists the rest.
    @ViewBuilder
    private var pinnedBar: some View {
        let pinned = store.thread.filter { store.pinned.contains($0.id) }.reversed()
        if let top = pinned.first {
            let label = HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SR.accentDeep)
                    .accessibilityHidden(true)
                Text("\(top.mine ? "You" : FamilyMessagesStore.first(top.fromName)): \(FamilyChatStream.quoteText(top.body))")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if pinned.count > 1 {
                    Text("\(pinned.count)")
                        .font(SR.Text.mono(11))
                        .foregroundStyle(SR.inkMuted)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SR.inkGhost)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
            .contentShape(Rectangle())
            Group {
                if pinned.count > 1 {
                    Menu {
                        ForEach(Array(pinned)) { message in
                            Button("\(message.mine ? "You" : FamilyMessagesStore.first(message.fromName)): \(FamilyChatStream.quoteText(message.body, limit: 40))") {
                                openThread(message.id)
                            }
                        }
                    } label: { label }
                } else {
                    Button { openThread(top.id) } label: { label }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pinned: \(top.body)")
            .accessibilityIdentifier("family-pinned")
        }
    }

    // MARK: - Family now

    private func landing(since: Date?, jumpToNew: (() -> Void)?) -> some View {
        FamilyChatLanding(
            since: since,
            fill: { addToBox($0) },
            poll: { pollDraft = $0 },
            openThread: { openThread($0) },
            openPerson: { personPage = FamilyPersonRoute(subject: $0) },
            jumpToNew: jumpToNew
        )
    }

    /// "Family now", over the conversation. Whatever it starts closes it
    /// first: a second sheet cannot open over it, and the box is behind it.
    private func nowSheet(since: Date?, jumpToNew target: String?) -> some View {
        NavigationStack {
            ScrollView {
                FamilyChatLanding(
                    since: since,
                    fill: { words in showingNow = false; addToBox(words) },
                    poll: { written in pollAfterSheet(written) },
                    openThread: { id in showingNow = false; openThread(id) },
                    openPerson: { subject in showingNow = false; personPage = FamilyPersonRoute(subject: subject) },
                    jumpToNew: target.map { id -> (() -> Void) in { showingNow = false; scrollTarget = id } }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .srPaper()
            .navigationTitle("Family now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingNow = false }
                        .accessibilityIdentifier("family-now-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// The poll sheet, once "Family now" has gone: a second sheet cannot
    /// open over the first.
    private func pollAfterSheet(_ written: FamilyPollDraft) {
        showingNow = false
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            pollDraft = written
        }
    }
}

/// A thread, by its message: what `FamilyMessagesScreen` and a tapped message
/// notification push.
struct FamilyThreadRef: Hashable {
    let id: String
}

/// One thread: the message, then every reply to it, read like the
/// conversation — your own on the right, everyone else's on the left with
/// their name and circle — opening at the newest. Here every reply answers
/// the same message, so none is quoted; the message itself leads the page.
struct FamilyThreadScreen: View {
    let ref: FamilyThreadRef
    @ObservedObject private var store = FamilyMessagesStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var deleting: FamilyThreadDeleting?
    @State private var draftLoaded = false

    var body: some View {
        let faces = FamilyFaces()
        Group {
            if let message = store.threadMessage(ref.id) {
                thread(message, faces: faces)
            } else if store.loaded {
                SREmpty(title: "This thread has gone", icon: "bubble.left.and.exclamationmark.bubble.right",
                        message: "Its sender deleted it.")
                    .frame(maxHeight: .infinity)
            } else {
                ProgressView().tint(SR.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .srPaper()
        .accessibilityIdentifier("family-thread-screen")
        .navigationTitle(store.threadMessage(ref.id).map { $0.mine ? "Your thread" : "\($0.fromName)'s thread" } ?? "Thread")
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.threadMessage(ref.id) == nil { await store.load() } }
        .srRefreshable { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.load() } }
        }
        .familyThreadDelete($deleting, store: store) { id in
            // The thread itself went: there is nothing left to stand on.
            if id == ref.id { dismiss() }
        }
        .onAppear {
            if !draftLoaded { draft = FamilyMessagesStore.draft(ref.id); draftLoaded = true }
            store.markRead()
        }
        .onChange(of: draft) { _, text in FamilyMessagesStore.saveDraft(text, for: ref.id) }
        .onChange(of: store.lastActivityISO) { _, _ in store.markRead() }
    }

    /// Written out with a `Void` return, not as a closure that is only a
    /// `Task`: see `ThreadListScreen.startThread` for why.
    private func vote(_ option: Int, in message: FamilyMessage, poll: FamilyPoll) {
        Task { await store.vote(option, in: message, poll: poll) }
    }

    private func thread(_ message: FamilyMessage, faces: FamilyFaces) -> some View {
        let lines = FamilyChatStream.lines([FamilyMessagesStore.streamed(message)], now: Date())
        let names = store.mentionNames
        let me = store.myName
        let poll = FamilyPoll.parse(message.body)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        if let day = line.day { FamilyDayHeading(title: day) }
                        if index == 1 {
                            repliesHeading(lines.count - 1)
                        }
                        if line.reply {
                            // The first answer says whose it is, even from the
                            // message's own sender a minute later.
                            replyRow(line, first: index == 1 || line.startsGroup, faces: faces, names: names, me: me)
                        } else {
                            FamilyChatBubble(
                                line: line, message: message, first: true, last: true, faces: faces, names: names, me: me,
                                pinned: store.pinned.contains(message.id), showQuote: false,
                                vote: poll.map { p -> (Int) -> Void in { option in vote(option, in: message, poll: p) } },
                                busy: store.isBusy(message.id),
                                selectable: true
                            )
                            .contextMenu { FamilyMessageAnswers(message: message, store: store, deleting: $deleting, open: nil) }
                            // A poll's options are buttons of their own; anything else reads as one.
                            .accessibilityElement(children: poll == nil ? .combine : .contain)
                            .accessibilityIdentifier("family-thread-message")
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: lines.last?.id) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                if let notice = store.notice {
                    SRBanner(text: notice)
                        .padding(.horizontal, 12)
                        .task(id: notice) {
                            try? await Task.sleep(for: .seconds(3))
                            if store.notice == notice { store.notice = nil }
                        }
                }
                // The quick emoji, for a message somebody else sent: one tap,
                // as from the notification.
                if !message.mine {
                    reactionsBar(message)
                }
                FamilyComposerAccessories(draft: $draft, names: names)
                FamilyMessageComposer(
                    draft: $draft,
                    placeholder: message.mine ? "Add to your thread" : "Reply to \(FamilyMessagesStore.first(message.fromName))",
                    busy: store.isBusy(message.id),
                    error: store.message,
                    identifier: "family-thread"
                ) {
                    let text = draft
                    Task { if await store.reply(to: message.id, text) { draft = "" } }
                }
            }
        }
    }

    /// "3 replies" between the message and its answers.
    private func repliesHeading(_ count: Int) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(SR.line).frame(height: 1)
            Text(count == 1 ? "1 REPLY" : "\(count) REPLIES")
                .font(SR.Text.label(11))
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
                .fixedSize()
            Rectangle().fill(SR.line).frame(height: 1)
        }
        .padding(.top, 14)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - A reply

    private func replyRow(_ line: FamilyChatStream.Line, first: Bool, faces: FamilyFaces, names: [String], me: String?) -> some View {
        FamilyChatBubble(line: line, message: nil, first: first, last: line.endsGroup, faces: faces,
                         names: names, me: me, showQuote: false, selectable: true)
            .contextMenu {
                FamilyReplyActions(body: line.body, name: line.name, mine: line.mine) {
                    deleting = FamilyThreadDeleting(id: line.id, title: "Delete your reply?", detail: "“\(line.body)” goes for everyone.")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(FamilyChatBubble.spoken(line))
            .accessibilityIdentifier("family-reply-\(line.id)")
    }

    private func reactionsBar(_ message: FamilyMessage) -> some View {
        HStack(spacing: 6) {
            ForEach(store.reactions, id: \.self) { emoji in
                let given = message.replies.contains { $0.reaction && $0.mine && $0.body == emoji }
                Button {
                    SRHaptic.tap()
                    Task {
                        if given, let mine = message.replies.first(where: { $0.reaction && $0.mine && $0.body == emoji }) {
                            await store.delete(mine.id)
                        } else {
                            await store.reply(to: message.id, emoji)
                        }
                    }
                } label: {
                    Text(emoji)
                        .font(.system(size: 20))
                        .frame(width: 40, height: 36)
                        .background(Capsule().fill(given ? SR.accent.opacity(0.22) : SR.surface))
                        .overlay(Capsule().strokeBorder(SR.line, lineWidth: given ? 0 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(given ? "Take back \(emoji)" : "Reply \(emoji)")
            }
        }
        .padding(.horizontal, 12)
        .disabled(store.isBusy(message.id))
        .accessibilityIdentifier("family-thread-reactions")
    }
}

// MARK: - The bubble

/// One line of msg family as a chat bubble: yours on the right in your own
/// colour (the one your circle and map pin wear), everybody else's on the
/// left on the page's surface, with their circle and name at the top of a
/// run. A reply carries the message it answers, quoted, at its top. A bat
/// phone is drawn in the error colour with its map as a button. The time is
/// in the bubble's corner; the emoji answers sit under a message.
struct FamilyChatBubble: View {
    let line: FamilyChatStream.Line
    /// The message itself, for its emoji and a poll's votes; nil for a reply.
    let message: FamilyMessage?
    let first: Bool
    let last: Bool
    let faces: FamilyFaces
    let names: [String]
    let me: String?
    var pinned = false
    var showQuote = true
    /// Voting, in a thread; nil draws a poll read-only.
    var vote: ((Int) -> Void)? = nil
    var busy = false
    /// The words can be selected — in a thread, where a tap does nothing else.
    var selectable = false
    /// A tap on the quote: up to the message it answers.
    var quoteTapped: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 30

    private var colour: Color { faces.colour(subject: line.subject, id: line.from) }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if line.mine {
                Spacer(minLength: 44)
            } else if first {
                FamilyFace(subject: line.subject, id: line.from, name: line.name, size: min(circle, 44), faces: faces)
                    .padding(.top, 2)
            } else {
                Color.clear.frame(width: min(circle, 44), height: 1)
            }
            VStack(alignment: line.mine ? .trailing : .leading, spacing: 3) {
                bubble
                if let message, !message.tally.isEmpty {
                    FamilyMessageTally(tally: message.tally)
                        .padding(.horizontal, 6)
                }
            }
            if !line.mine { Spacer(minLength: 44) }
        }
        .padding(.top, first ? 10 : 2)
        .padding(.bottom, last ? 2 : 0)
    }

    private var shape: UnevenRoundedRectangle {
        // The corner nearest the sender squared off on a run's first bubble:
        // the "tail" that says whose it is.
        let tail: CGFloat = first ? 5 : 18
        return UnevenRoundedRectangle(
            topLeadingRadius: line.mine ? 18 : tail, bottomLeadingRadius: 18,
            bottomTrailingRadius: 18, topTrailingRadius: line.mine ? tail : 18, style: .continuous
        )
    }

    private var isBat: Bool { BatPhoneWords.isBatPhone(line.body) }

    private var fill: Color {
        if isBat { return SR.error.opacity(0.13) }
        return line.mine ? colour.opacity(0.2) : SR.surface
    }

    private var border: Color {
        if isBat { return SR.error.opacity(0.6) }
        return line.mine ? colour.opacity(0.45) : SR.line
    }

    /// The words on the left, the time under them on the right. No spacers:
    /// a bubble is as wide as what it says, and the time keeps to its edge.
    private var bubble: some View {
        VStack(alignment: .trailing, spacing: 4) {
            VStack(alignment: .leading, spacing: 5) {
                if first && !line.mine {
                    Text(line.name)
                        .font(SR.Text.bodyMedium(13))
                        .foregroundStyle(colour)
                        .lineLimit(1)
                }
                if showQuote, let quote = line.quote {
                    quoteView(quote)
                }
                content
                if !line.mine, let me, FamilyMessageTools.mentions(line.body, name: me) {
                    FamilyMentionTag()
                }
            }
            footer
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(shape.fill(fill))
        .overlay(shape.stroke(border, lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
        if !line.reply, let poll = FamilyPoll.parse(line.body), let message {
            FamilyPollView(poll: poll, counts: poll.tally(FamilyMessagesStore.votes(message)), vote: vote, busy: busy)
                .frame(minWidth: 220)
        } else if isBat {
            batPhone
        } else {
            words(FamilyMessageText(line.body, names: names, me: me, size: 16))
        }
    }

    @ViewBuilder
    private func words(_ text: FamilyMessageText) -> some View {
        if selectable {
            text.fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        } else {
            text.fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The bat phone's words without its link, and the link as a button.
    private var batPhone: some View {
        let parts = line.body.split(separator: "\n").map(String.init)
        let link = parts.first { $0.hasPrefix("https://") }.flatMap { URL(string: $0) }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parts.filter { !$0.hasPrefix("https://") }.enumerated()), id: \.offset) { index, text in
                Text(text)
                    .font(index == 0 ? SR.Text.title(16) : SR.Text.body(15))
                    .foregroundStyle(index == 0 ? SR.error : SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let link {
                Link(destination: link) {
                    Label("Open the map", systemImage: "map")
                        .font(SR.Text.bodyMedium(14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(SR.error))
                }
                .accessibilityIdentifier("family-bat-map-\(line.id)")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(SR.accentDeep)
                    .accessibilityLabel("Pinned")
            }
            if let at = line.at {
                Text(at.formatted(date: .omitted, time: .shortened))
                    .font(SR.Text.mono(11))
                    .foregroundStyle(SR.inkSecondary)
            }
            if line.mine, let message, message.recipients > 0 {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SR.inkSecondary)
                    .accessibilityLabel("Sent to \(message.recipients)")
            }
        }
    }

    /// The message a reply answers: a bar in its writer's colour, their name
    /// and its first line. A tap goes up to it.
    private func quoteView(_ quote: FamilyChatStream.Quote) -> some View {
        let tint = faces.colour(subject: quote.subject, id: quote.from)
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(quote.mine ? "You" : FamilyMessagesStore.first(quote.name))
                    .font(SR.Text.bodyMedium(12))
                    .foregroundStyle(tint)
                Text(quote.text)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 5)
        .padding(.trailing, 10)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SR.ink.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { quoteTapped?() }
    }

    /// "Robin, replying to You: Pepperoni please!, 12:40".
    static func spoken(_ line: FamilyChatStream.Line) -> String {
        let who = line.mine ? "You" : line.name
        let to = line.quote.map { ", replying to \($0.mine ? "you" : $0.name)" } ?? ""
        let at = line.at.map { ", \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        return "\(who)\(to): \(line.body)\(at)"
    }
}

/// Over the box while a reply is being written: whose line, and its words,
/// with a cross to write a new message instead.
struct FamilyReplyingBar: View {
    let line: FamilyChatStream.Line
    let faces: FamilyFaces
    let cancel: () -> Void

    var body: some View {
        let tint = faces.colour(subject: line.subject, id: line.from)
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Replying to \(line.mine ? "yourself" : FamilyMessagesStore.first(line.name))")
                    .font(SR.Text.bodyMedium(12))
                    .foregroundStyle(tint)
                Text(FamilyChatStream.quoteText(line.body))
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: cancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(SR.inkMuted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel the reply")
            .accessibilityIdentifier("family-replying-cancel")
        }
        .padding(.leading, 12)
        .fixedSize(horizontal: false, vertical: true)
        .srGlassCard(.paper)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("family-replying")
    }
}

/// The long press on a reply: Copy, Share, and taking back my own.
struct FamilyReplyActions: View {
    let body_: String
    let name: String
    let mine: Bool
    let delete: () -> Void

    init(body: String, name: String, mine: Bool, delete: @escaping () -> Void) {
        body_ = body
        self.name = name
        self.mine = mine
        self.delete = delete
    }

    var body: some View {
        Button {
            UIPasteboard.general.string = body_
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        ShareLink(item: "\(mine ? "Me" : name): \(body_)") {
            Label("Share…", systemImage: "square.and.arrow.up")
        }
        if mine {
            Button(role: .destructive, action: delete) {
                Label("Delete my reply", systemImage: "trash")
            }
        }
    }
}

// MARK: - Shared pieces

/// The emoji answers in a line of chips: each once, with how many.
struct FamilyMessageTally: View {
    let tally: [FamilyMessages.Tally]

    var body: some View {
        if !tally.isEmpty {
            HStack(spacing: 4) {
                ForEach(tally) { t in
                    Text(t.count > 1 ? "\(t.emoji) \(t.count)" : t.emoji)
                        .font(SR.Text.secondary(13))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(t.mine ? SR.accent.opacity(0.22) : SR.ink.opacity(0.06)))
                        .accessibilityLabel("\(t.emoji) from \(t.names.joined(separator: ", "))")
                }
            }
        }
    }
}

/// The long press on a message: the quick emoji, three to a row, then a
/// poll's votes, Open the thread, Pin, Remind, Copy, Share, and taking back
/// what is mine. msg family puts its own Reply (quote it in the box) first.
struct FamilyMessageAnswers: View {
    let message: FamilyMessage
    @ObservedObject var store: FamilyMessagesStore
    @Binding var deleting: FamilyThreadDeleting?
    /// Opens the thread to reply in; nil inside the thread, where the box is.
    let open: (() -> Void)?

    var body: some View {
        if !message.mine {
            let reactions = store.reactions
            ForEach(Array(stride(from: 0, to: reactions.count, by: 3)), id: \.self) { start in
                ControlGroup {
                    ForEach(reactions[start..<min(start + 3, reactions.count)], id: \.self) { emoji in
                        Button(emoji) {
                            SRHaptic.tap()
                            Task { await store.reply(to: message.id, emoji) }
                        }
                        .accessibilityLabel("Reply \(emoji)")
                    }
                }
                .controlGroupStyle(.compactMenu)
            }
        }
        // A poll's answers, to vote from the long press without opening it.
        if let poll = FamilyPoll.parse(message.body) {
            let counts = poll.tally(FamilyMessagesStore.votes(message))
            ForEach(counts) { count in
                Button {
                    Task { await store.vote(count.option, in: message, poll: poll) }
                } label: {
                    Label("\(count.mine ? "Take back" : "Vote") \(count.label)", systemImage: count.mine ? "checkmark.circle.fill" : "circle")
                }
            }
        }
        if let open {
            Button(action: open) {
                Label("Open the thread", systemImage: "bubble.left.and.bubble.right")
            }
        }
        Button {
            store.togglePin(message.id)
        } label: {
            Label(store.pinned.contains(message.id) ? "Unpin" : "Pin to the top", systemImage: store.pinned.contains(message.id) ? "pin.slash" : "pin")
        }
        FamilyRemindMenu(message: message, store: store)
        Button {
            UIPasteboard.general.string = message.body
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        ShareLink(item: "\(message.mine ? "Me" : message.fromName): \(message.body)") {
            Label("Share…", systemImage: "square.and.arrow.up")
        }
        // What this person sent, and only that: their own emoji go at once,
        // the message itself asks first.
        ForEach(message.replies.filter { $0.mine && $0.reaction }) { reply in
            Button(role: .destructive) {
                Task { await store.delete(reply.id) }
            } label: {
                Label("Remove my \(reply.body)", systemImage: "minus.circle")
            }
        }
        if message.mine {
            Button(role: .destructive) {
                deleting = FamilyThreadDeleting(
                    id: message.id,
                    title: "Delete this message?",
                    detail: "It goes for everyone, with its replies. A notification someone already has stays on their phone."
                )
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("family-message-delete")
        }
    }
}

/// A message or reply of mine, waiting on "Delete?".
struct FamilyThreadDeleting: Identifiable {
    let id: String
    let title: String
    let detail: String
}

extension View {
    /// The "Delete?" a message or a reply of mine asks first.
    func familyThreadDelete(_ target: Binding<FamilyThreadDeleting?>, store: FamilyMessagesStore,
                            deleted: @escaping (String) -> Void = { _ in }) -> some View {
        confirmationDialog(
            target.wrappedValue?.title ?? "Delete?",
            isPresented: Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: target.wrappedValue
        ) { item in
            Button("Delete", role: .destructive) {
                Task { if await store.delete(item.id) { deleted(item.id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(item.detail)
        }
    }
}

/// The box at the foot of msg family and of a thread.
struct FamilyMessageComposer: View {
    @Binding var draft: String
    let placeholder: String
    let busy: Bool
    let error: String?
    let identifier: String
    /// Bumped by the screen to bring the keyboard up: a person or a
    /// suggestion on the landing has just put words in the box.
    var focusRequest = 0
    let send: () -> Void
    @FocusState private var focused: Bool

    private var sendable: Bool { FamilyMessages.sendable(draft) != nil && !busy }

    var body: some View {
        VStack(spacing: 6) {
            if let error {
                SRBanner(text: error, tone: SR.error)
            }
            // How much room is left, once it is nearly gone.
            if let left = FamilyMessageTools.remaining(draft) {
                Text(left >= 0 ? "\(left) characters left" : "\(-left) too many — trim it to send")
                    .font(SR.Text.mono(12))
                    .foregroundStyle(left >= 0 ? SR.inkMuted : SR.error)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("\(identifier)-counter")
            }
            SRGlassGroup(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField(placeholder, text: $draft, axis: .vertical)
                        .font(SR.Text.body())
                        .foregroundStyle(SR.ink)
                        .lineLimit(1...6)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(minHeight: 48)
                        .srGlass(.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .focused($focused)
                        .accessibilityIdentifier("\(identifier)-composer")

                    Button {
                        SRHaptic.tap()
                        send()
                    } label: {
                        Group {
                            if busy {
                                ProgressView().tint(SR.paper)
                            } else {
                                Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold))
                            }
                        }
                        .foregroundStyle(sendable ? SR.paper : SR.inkMuted)
                        .frame(width: 48, height: 48)
                        .srGlass(sendable || busy ? .accent : .paper, in: Circle(), interactive: true)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!sendable)
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("\(identifier)-send")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onChange(of: focusRequest) { _, _ in focused = true }
    }
}
