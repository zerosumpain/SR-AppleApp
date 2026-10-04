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
                LazyVStack(alignment: .leading, spacing: 14) {
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

    private func card(_ message: FamilyMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(message.mine ? "You" : message.fromName)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Spacer()
                Text(FamilyMessages.when(message.at))
                    .font(SR.Text.label())
                    .foregroundStyle(SR.inkMuted)
            }
            Text(message.body)
                .font(SR.Text.body())
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if message.mine && message.recipients > 0 {
                Text(message.recipients == 1 ? "Sent to 1 person" : "Sent to \(message.recipients) people")
                    .font(SR.Text.label())
                    .foregroundStyle(SR.inkMuted)
            }

            let tally = message.tally
            if !tally.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tally) { t in
                        Text(t.count > 1 ? "\(t.emoji) \(t.count)" : t.emoji)
                            .font(SR.Text.secondary())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(t.mine ? SR.accent.opacity(0.22) : SR.ink.opacity(0.06)))
                            .accessibilityLabel("\(t.emoji) from \(t.names.joined(separator: ", "))")
                    }
                }
            }

            ForEach(message.textReplies) { reply in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(reply.mine ? "You" : reply.fromName)
                        .font(SR.Text.bodyMedium(14))
                        .foregroundStyle(SR.ink)
                    Text(reply.body)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(SR.accent.opacity(0.5)).frame(width: 2) }
            }

            if !message.mine { answerRow(message) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityIdentifier("family-message-\(message.id)")
    }

    /// The quick replies and Reply. Somebody's own message is not answered.
    private func answerRow(_ message: FamilyMessage) -> some View {
        HStack(spacing: 4) {
            ForEach(store.reactions, id: \.self) { emoji in
                Button {
                    SRHaptic.tap()
                    Task { await store.reply(to: message.id, emoji) }
                } label: {
                    Text(emoji)
                        .font(.system(size: 20))
                        .frame(minWidth: 36, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reply \(emoji)")
            }
            Spacer(minLength: 4)
            Button {
                SRHaptic.tap()
                replyDraft = ""
                replying = message
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SR.accentDeep)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reply with text")
        }
        .disabled(store.busy != nil)
        .opacity(store.busy == message.id ? 0.5 : 1)
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
