import SwiftUI

/// "msg family": one line to everyone in the family, pushed to their phones,
/// and their answers under it — an emoji from the quick set, or a reply.
///
/// Reached from Chat ("msg family" beside "jkai"), from a tapped message
/// notification, and from the hub for somebody without Chat.
///
/// Threads (John, 2026-10-21): each message is a card with the sender's
/// circle, the words, the emoji, and who answered — their circles and the
/// newest reply. A tap opens the thread (`FamilyThreadScreen`), where the
/// replies hang under the message, indented, each with its person's circle.
/// The thread that moved last is at the foot, by the box to start a new one.
///
/// 2026-10-27 (John: "at least 10 new features"): a "New" line over what
/// came in since this phone last had it open, and a dot on those threads;
/// day headings; search; threads pinned to the top on this phone; polls;
/// @mentions picked out, with "Mentions you" on a thread that names you;
/// "Remind me later" and Share on the long press; quick messages, "where I
/// am" and a counter over the box; and the box keeps an unsent draft.
struct FamilyMessagesScreen: View {
    @ObservedObject private var store = FamilyMessagesStore.shared
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = FamilyMessagesStore.draft("new")
    /// A message of mine, waiting on "Delete?".
    @State private var deleting: FamilyThreadDeleting?
    @State private var query = ""
    @State private var writingPoll = false
    /// When msg family was last read, as it stood when this screen opened:
    /// the "New" line stays where it was for the whole visit.
    @State private var openedReadAt: Date?
    @State private var opened = false

    var body: some View {
        let faces = FamilyFaces()
        let shown = store.thread.filter { matches($0) }
        let pinned = query.isEmpty ? shown.filter { store.pinned.contains($0.id) } : []
        let rest = shown.filter { !pinned.contains($0) }
        let firstNew = rest.firstIndex { store.isUnread($0, since: openedReadAt) }
        let newCount = rest.filter { store.isUnread($0, since: openedReadAt) }.count
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if store.thread.isEmpty {
                        if store.loaded {
                            SREmpty(
                                title: "No messages yet",
                                icon: "bubble.left.and.text.bubble.right",
                                message: store.message ?? "Write one below. It goes to everyone in the family as a notification."
                            )
                            .padding(.top, 40)
                        } else {
                            ProgressView().tint(SR.accent).frame(maxWidth: .infinity).padding(.vertical, 60)
                        }
                    } else if shown.isEmpty {
                        SREmpty(title: "Nothing matches", icon: "magnifyingglass", message: "Search looks through every message, reply and name.")
                            .padding(.top, 40)
                    }
                    if !pinned.isEmpty {
                        FamilyDayHeading(title: "Pinned")
                        ForEach(pinned) { message in
                            card(message, faces: faces, unread: store.isUnread(message, since: openedReadAt)).id("pin-\(message.id)")
                        }
                    }
                    ForEach(Array(rest.enumerated()), id: \.element.id) { index, message in
                        let day = dayTitle(message)
                        if index == 0 || dayTitle(rest[index - 1]) != day {
                            FamilyDayHeading(title: day)
                        }
                        if index == firstNew, query.isEmpty {
                            FamilyNewLine(count: newCount)
                        }
                        card(message, faces: faces, unread: store.isUnread(message, since: openedReadAt)).id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.thread.last?.id) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search messages")
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
                FamilyComposerAccessories(draft: $draft, names: store.mentionNames) { writingPoll = true }
                FamilyMessageComposer(
                    draft: $draft,
                    placeholder: "Start a thread for the family",
                    busy: store.busy == "new",
                    error: store.thread.isEmpty ? nil : store.message,
                    identifier: "family-msg"
                ) {
                    let text = draft
                    Task { if await store.send(text) { draft = "" } }
                }
            }
        }
        .srPaper()
        .accessibilityIdentifier("family-messages-screen")
        .navigationTitle("msg family")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .task { await FamilyPhotos.shared.load() }
        .srRefreshable { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.load() } }
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
        .sheet(isPresented: $writingPoll) {
            FamilyPollComposer { poll in await store.send(poll.body) }
        }
        .familyThreadDelete($deleting, store: store)
    }

    private func matches(_ message: FamilyMessage) -> Bool {
        FamilyMessageTools.matches(query, in: [message.body, message.fromName] + message.replies.flatMap { [$0.body, $0.fromName] })
    }

    private func dayTitle(_ message: FamilyMessage) -> String {
        FamilyMessageTools.dayTitle(message.lastActivity ?? parseTimestamp(message.at) ?? Date(), now: Date())
    }

    private func open(_ message: FamilyMessage) {
        SRHaptic.tap()
        router.push(FamilyThreadRef(id: message.id), on: router.tab)
    }

    // MARK: - A thread's card

    /// The sender's circle beside their words; the emoji in a line of chips;
    /// then who answered — their circles, overlapped, and the newest reply.
    /// The whole card opens the thread; a long press still answers in place.
    private func card(_ message: FamilyMessage, faces: FamilyFaces, unread: Bool) -> some View {
        let poll = FamilyPoll.parse(message.body)
        let me = store.myName
        let mentioned = me.map { name in
            (!message.mine && FamilyMessageTools.mentions(message.body, name: name))
                || message.replies.contains { !$0.mine && FamilyMessageTools.mentions($0.body, name: name) }
        } ?? false
        return Button { open(message) } label: {
            HStack(alignment: .top, spacing: 10) {
                FamilyFace(subject: message.fromSubject, id: message.fromId, name: message.fromName, size: 36, faces: faces)
                    .overlay(alignment: .topTrailing) {
                        if unread {
                            Circle().fill(SR.accentDeep)
                                .frame(width: 11, height: 11)
                                .overlay(Circle().stroke(SR.paper, lineWidth: 2))
                                .offset(x: 3, y: -3)
                                .accessibilityLabel("New")
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    FamilyMessageByline(name: message.mine ? "You" : message.fromName, at: message.at,
                                        mine: message.mine, trailing: message.mine && message.recipients > 0 ? "to \(message.recipients)" : nil)
                    if let poll {
                        FamilyPollView(poll: poll, counts: poll.tally(FamilyMessagesStore.votes(message)))
                    } else {
                        FamilyMessageText(message.body, names: store.mentionNames, me: me)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 6) {
                        if store.pinned.contains(message.id) {
                            Image(systemName: "pin.fill")
                                .font(SR.Text.label(10))
                                .foregroundStyle(SR.accentDeep)
                                .accessibilityLabel("Pinned")
                        }
                        if mentioned { FamilyMentionTag() }
                        FamilyMessageTally(tally: message.tally)
                    }
                    // A poll's votes are its bars, not replies.
                    let words = poll.map { p in message.textReplies.filter { p.option(of: $0.body) == nil } } ?? message.textReplies
                    if let last = words.last {
                        repliesLine(words, last: last, faces: faces)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srGlassCard(.paper)
            .contentShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(store.busy == message.id ? 0.5 : 1)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
        .contextMenu {
            FamilyMessageAnswers(message: message, store: store, deleting: $deleting) { open(message) }
        }
        .accessibilityIdentifier("family-message-\(message.id)")
        .accessibilityValue(unread ? "New" : "")
        .accessibilityHint("Opens the thread. Touch and hold to answer with an emoji.")
    }

    /// "3 replies · Robin: Pepperoni please!" under the circles of who said them.
    private func repliesLine(_ replies: [FamilyMessageReply], last: FamilyMessageReply, faces: FamilyFaces) -> some View {
        let count = replies.count
        var seen = Set<String>()
        let repliers = replies.filter { seen.insert($0.fromId.isEmpty ? $0.fromName : $0.fromId).inserted }
        return HStack(spacing: 8) {
            HStack(spacing: -8) {
                ForEach(repliers.prefix(4)) { reply in
                    FamilyFace(subject: reply.fromSubject, id: reply.fromId, name: reply.fromName, size: 22, faces: faces)
                }
            }
            (Text(count == 1 ? "1 reply" : "\(count) replies").font(SR.Text.bodyMedium(13)).foregroundColor(SR.accentDeep)
                + Text(" · \(last.mine ? "You" : last.fromName): \(last.body)").font(SR.Text.secondary(13)).foregroundColor(SR.inkSecondary))
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SR.inkGhost)
                .accessibilityHidden(true)
        }
        .padding(.top, 4)
    }
}

/// A thread, by its message: what `FamilyMessagesScreen` and a tapped message
/// notification push.
struct FamilyThreadRef: Hashable {
    let id: String
}

/// One thread: the message at the top with its sender's circle, then every
/// reply under it. The sender's own follow-ups sit in line with the message;
/// everybody else's are indented under it, joined by the thread's line — so
/// who started it and who answered is plain at a glance.
struct FamilyThreadScreen: View {
    let ref: FamilyThreadRef
    @ObservedObject private var store = FamilyMessagesStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var deleting: FamilyThreadDeleting?
    @State private var draftLoaded = false

    /// How far an answer from somebody else sits in from the message.
    static let indent: CGFloat = 30

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

    /// The replies in words: a poll's votes are drawn as its bars instead.
    private func words(_ message: FamilyMessage) -> [FamilyMessageReply] {
        guard let poll = FamilyPoll.parse(message.body) else { return message.textReplies }
        return message.textReplies.filter { poll.option(of: $0.body) == nil }
    }

    private func thread(_ message: FamilyMessage, faces: FamilyFaces) -> some View {
        let replies = words(message)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    root(message, faces: faces)
                    ForEach(Array(replies.enumerated()), id: \.element.id) { index, reply in
                        replyRow(reply, in: message, last: index == replies.count - 1, faces: faces)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: message.textReplies.last?.id) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
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
                FamilyComposerAccessories(draft: $draft, names: store.mentionNames)
                FamilyMessageComposer(
                    draft: $draft,
                    placeholder: message.mine ? "Add to your thread" : "Reply to \(message.fromName)",
                    busy: store.busy == message.id,
                    error: store.message,
                    identifier: "family-thread"
                ) {
                    let text = draft
                    Task { if await store.reply(to: message.id, text) { draft = "" } }
                }
            }
        }
    }

    // MARK: - The message

    private func root(_ message: FamilyMessage, faces: FamilyFaces) -> some View {
        HStack(alignment: .top, spacing: 10) {
            FamilyFace(subject: message.fromSubject, id: message.fromId, name: message.fromName, size: 40, faces: faces)
            VStack(alignment: .leading, spacing: 6) {
                FamilyMessageByline(name: message.mine ? "You" : message.fromName, at: message.at, mine: message.mine,
                                    trailing: message.mine && message.recipients > 0 ? "to \(message.recipients)" : nil)
                if let poll = FamilyPoll.parse(message.body) {
                    FamilyPollView(poll: poll, counts: poll.tally(FamilyMessagesStore.votes(message)),
                                   vote: { vote($0, in: message, poll: poll) },
                                   busy: store.busy != nil)
                } else {
                    FamilyMessageText(message.body, names: store.mentionNames, me: store.myName, size: 17)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                FamilyMessageTally(tally: message.tally)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .srGlassCard(.paper)
        .contextMenu { FamilyMessageAnswers(message: message, store: store, deleting: $deleting, open: nil) }
        // A poll's options are buttons of their own; anything else reads as one.
        .accessibilityElement(children: FamilyPoll.parse(message.body) == nil ? .combine : .contain)
        .accessibilityIdentifier("family-thread-message")
    }

    // MARK: - A reply

    /// The thread's line runs down the left from the message's circle; an
    /// answer from somebody else steps in from it, the sender's own stays on it.
    private func replyRow(_ reply: FamilyMessageReply, in message: FamilyMessage, last: Bool, faces: FamilyFaces) -> some View {
        let fromSender = message.isFromSender(reply)
        let tint = faces.colour(subject: reply.fromSubject, id: reply.fromId)
        return HStack(alignment: .top, spacing: 8) {
            FamilyFace(subject: reply.fromSubject, id: reply.fromId, name: reply.fromName, size: fromSender ? 32 : 28, faces: faces)
            VStack(alignment: .leading, spacing: 3) {
                FamilyMessageByline(name: reply.mine ? "You" : reply.fromName, at: reply.at, mine: reply.mine, trailing: nil)
                FamilyMessageText(reply.body, names: store.mentionNames, me: store.myName)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(fromSender ? 0.10 : 0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
        }
        .padding(.leading, fromSender ? 4 : Self.indent)
        .padding(.top, 10)
        // The thread: a line from the message down past every answer.
        .background(alignment: .topLeading) {
            Rectangle()
                .fill(SR.line)
                .frame(width: 2)
                .frame(maxHeight: last ? 26 : .infinity, alignment: .top)
                .padding(.leading, 20 - 1)
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = reply.body
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            ShareLink(item: "\(reply.mine ? "Me" : reply.fromName): \(reply.body)") {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            if reply.mine {
                Button(role: .destructive) {
                    deleting = FamilyThreadDeleting(id: reply.id, title: "Delete your reply?", detail: "“\(reply.body)” goes for everyone.")
                } label: {
                    Label("Delete my reply", systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(reply.mine ? "You" : reply.fromName)\(fromSender ? "" : ", replying"): \(reply.body)")
        .accessibilityIdentifier("family-reply-\(reply.id)")
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
        .disabled(store.busy != nil)
        .accessibilityIdentifier("family-thread-reactions")
    }
}

// MARK: - Shared pieces

/// "Robin · 5m", the name in the person's weight, the time quiet.
struct FamilyMessageByline: View {
    let name: String
    let at: String
    let mine: Bool
    let trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(name)
                .font(SR.Text.bodyMedium(14))
                .foregroundStyle(mine ? SR.accentDeep : SR.ink)
            Text(FamilyMessages.when(at))
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(SR.Text.label())
                    .foregroundStyle(SR.inkMuted)
            }
        }
    }
}

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

/// The long press on a message: the quick emoji, three to a row, then Reply
/// (open the thread), Copy, and taking back what is mine.
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
                Label(message.mine ? "Open the thread" : "Reply", systemImage: "arrowshape.turn.up.left")
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
    let send: () -> Void

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
    }
}
