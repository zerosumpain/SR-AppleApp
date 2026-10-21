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
struct FamilyMessagesScreen: View {
    @ObservedObject private var store = FamilyMessagesStore.shared
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = ""
    /// A message of mine, waiting on "Delete?".
    @State private var deleting: FamilyThreadDeleting?

    var body: some View {
        let faces = FamilyFaces()
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
                    }
                    ForEach(store.thread) { message in
                        card(message, faces: faces).id(message.id)
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
        .safeAreaInset(edge: .bottom) {
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
        .srPaper()
        .accessibilityIdentifier("family-messages-screen")
        .navigationTitle("msg family")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .srRefreshable { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.load() } }
        }
        .familyThreadDelete($deleting, store: store)
    }

    private func open(_ message: FamilyMessage) {
        SRHaptic.tap()
        router.push(FamilyThreadRef(id: message.id), on: router.tab)
    }

    // MARK: - A thread's card

    /// The sender's circle beside their words; the emoji in a line of chips;
    /// then who answered — their circles, overlapped, and the newest reply.
    /// The whole card opens the thread; a long press still answers in place.
    private func card(_ message: FamilyMessage, faces: FamilyFaces) -> some View {
        Button { open(message) } label: {
            HStack(alignment: .top, spacing: 10) {
                FamilyFace(subject: message.fromSubject, id: message.fromId, name: message.fromName, size: 36, faces: faces)
                VStack(alignment: .leading, spacing: 4) {
                    FamilyMessageByline(name: message.mine ? "You" : message.fromName, at: message.at,
                                        mine: message.mine, trailing: message.mine && message.recipients > 0 ? "to \(message.recipients)" : nil)
                    Text(message.body)
                        .font(SR.Text.body(15))
                        .foregroundStyle(SR.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    FamilyMessageTally(tally: message.tally)
                    if let last = message.textReplies.last {
                        repliesLine(message, last: last, faces: faces)
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
        .accessibilityHint("Opens the thread. Touch and hold to answer with an emoji.")
    }

    /// "3 replies · Robin: Pepperoni please!" under the circles of who said them.
    private func repliesLine(_ message: FamilyMessage, last: FamilyMessageReply, faces: FamilyFaces) -> some View {
        let count = message.textReplies.count
        return HStack(spacing: 8) {
            HStack(spacing: -8) {
                ForEach(message.repliers.prefix(4)) { reply in
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
    }

    private func thread(_ message: FamilyMessage, faces: FamilyFaces) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    root(message, faces: faces)
                    ForEach(Array(message.textReplies.enumerated()), id: \.element.id) { index, reply in
                        replyRow(reply, in: message, last: index == message.textReplies.count - 1, faces: faces)
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
                // The quick emoji, for a message somebody else sent: one tap,
                // as from the notification.
                if !message.mine {
                    reactionsBar(message)
                }
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
                Text(message.body)
                    .font(SR.Text.body(17))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                FamilyMessageTally(tally: message.tally)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .srGlassCard(.paper)
        .contextMenu { FamilyMessageAnswers(message: message, store: store, deleting: $deleting, open: nil) }
        .accessibilityElement(children: .combine)
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
                Text(reply.body)
                    .font(SR.Text.body(15))
                    .foregroundStyle(SR.ink)
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
        if let open {
            Button(action: open) {
                Label(message.mine ? "Open the thread" : "Reply", systemImage: "arrowshape.turn.up.left")
            }
        }
        Button {
            UIPasteboard.general.string = message.body
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
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
