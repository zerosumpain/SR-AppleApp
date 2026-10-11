import SwiftUI

/// "msg family": one line to everyone in the family, pushed to their phones,
/// and their answers under it — an emoji from the quick set, or a reply.
///
/// Reached from Chat ("msg family" beside "jkai"), from a tapped message
/// notification, and from Today's JkAi & Msgs tile for somebody without Chat.
/// Reads as a conversation: oldest at the top, the box to write in at the foot.
struct FamilyMessagesScreen: View {
    @ObservedObject private var store = FamilyMessagesStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    /// The message a text reply is being written to.
    @State private var replying: FamilyMessage?
    @State private var replyDraft = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
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
                        card(message).id(message.id)
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
        .safeAreaInset(edge: .bottom) { composer }
        .srPaper()
        .accessibilityIdentifier("family-messages-screen")
        .navigationTitle("msg family")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .srRefreshable { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.load() } }
        }
        .alert(
            replying.map { "Reply to \($0.fromName)" } ?? "Reply",
            isPresented: Binding(get: { replying != nil }, set: { if !$0 { replying = nil } })
        ) {
            TextField("Your reply", text: $replyDraft)
            Button("Send") {
                guard let message = replying else { return }
                let text = replyDraft
                replyDraft = ""
                Task { await store.reply(to: message.id, text) }
            }
            Button("Cancel", role: .cancel) { replyDraft = "" }
        }
    }

    // MARK: - A message

    /// One message, as short as it reads: name and time on one line, the
    /// words, then the answers in a line of chips. No row of buttons under
    /// each — a long press on the message is where an emoji or a reply is
    /// picked (John, 2026-10-05).
    private func card(_ message: FamilyMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(message.mine ? "You" : message.fromName)
                    .font(SR.Text.bodyMedium(14))
                    .foregroundStyle(message.mine ? SR.accentDeep : SR.ink)
                Text(FamilyMessages.when(message.at))
                    .font(SR.Text.label())
                    .foregroundStyle(SR.inkMuted)
                Spacer(minLength: 0)
                if message.mine && message.recipients > 0 {
                    Text("to \(message.recipients)")
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                }
            }
            Text(message.body)
                .font(SR.Text.body(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)

            let tally = message.tally
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

            ForEach(message.textReplies) { reply in
                (Text(reply.mine ? "You " : "\(reply.fromName) ").font(SR.Text.bodyMedium(13)).foregroundColor(SR.ink)
                    + Text(reply.body).font(SR.Text.secondary(13)).foregroundColor(SR.inkSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) { Rectangle().fill(SR.accent.opacity(0.5)).frame(width: 2) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .opacity(store.busy == message.id ? 0.5 : 1)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
        .contextMenu { answers(message) }
        .accessibilityIdentifier("family-message-\(message.id)")
        .accessibilityHint(message.mine ? "" : "Touch and hold to answer with an emoji or a reply.")
    }

    /// The long press: the quick emoji, three to a row, then Reply and Copy.
    @ViewBuilder
    private func answers(_ message: FamilyMessage) -> some View {
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
            Button {
                replyDraft = ""
                replying = message
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
        }
        Button {
            UIPasteboard.general.string = message.body
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
    }

    // MARK: - Composer

    private var sendable: Bool { FamilyMessages.sendable(draft) != nil && store.busy == nil }

    private var composer: some View {
        VStack(spacing: 6) {
            if let message = store.message, !store.thread.isEmpty {
                SRBanner(text: message, tone: SR.error)
            }
            SRGlassGroup(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Message the family", text: $draft, axis: .vertical)
                        .font(SR.Text.body())
                        .foregroundStyle(SR.ink)
                        .lineLimit(1...6)
                        .focused($composerFocused)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(minHeight: 48)
                        .srGlass(.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .accessibilityIdentifier("family-msg-composer")

                    Button {
                        let text = draft
                        SRHaptic.tap()
                        Task {
                            if await store.send(text) { draft = "" }
                        }
                    } label: {
                        Group {
                            if store.busy == "new" {
                                ProgressView().tint(SR.paper)
                            } else {
                                Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold))
                            }
                        }
                        .foregroundStyle(sendable ? SR.paper : SR.inkMuted)
                        .frame(width: 48, height: 48)
                        .srGlass(sendable || store.busy == "new" ? .accent : .paper, in: Circle(), interactive: true)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!sendable)
                    .accessibilityLabel("Send to the family")
                    .accessibilityIdentifier("family-msg-send")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
