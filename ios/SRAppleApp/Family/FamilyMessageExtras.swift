import SwiftUI
import UserNotifications

// msg family's extras (2026-10-27), the views over `FamilyMessageTools`:
// a message's words with its @mentions picked out, polls and the sheet that
// writes one, the line of quick messages over the box, the day headings and
// the "New" line, and reminders. See `FamilyMessageTools` for the rules.

// MARK: - The words

/// A message's words with every "@Name" of the family in the accent, and an
/// "@" of this phone's own person in bold too.
struct FamilyMessageText: View {
    let body_: String
    let names: [String]
    let me: String?
    var size: CGFloat = 15

    init(_ body: String, names: [String], me: String?, size: CGFloat = 15) {
        body_ = body
        self.names = names
        self.me = me
        self.size = size
    }

    var body: some View {
        Text(Self.attributed(body_, names: names + [me].compactMap { $0 }, me: me))
            .font(SR.Text.body(size))
            .foregroundStyle(SR.ink)
    }

    static func attributed(_ text: String, names: [String], me: String?) -> AttributedString {
        var out = AttributedString(text)
        let lower = text.lowercased()
        for name in Set(names) where !name.isEmpty {
            let target = "@" + name.lowercased()
            var from = lower.startIndex
            while let found = lower.range(of: target, range: from..<lower.endIndex) {
                from = found.upperBound
                if found.upperBound < lower.endIndex, lower[found.upperBound].isLetter || lower[found.upperBound].isNumber { continue }
                // Counted in the lowercased copy it was found in: offsets in
                // characters, which lowercasing leaves alone.
                let start = lower.distance(from: lower.startIndex, to: found.lowerBound)
                let length = lower.distance(from: found.lowerBound, to: found.upperBound)
                guard start + length <= out.characters.count else { continue }
                let a = out.index(out.startIndex, offsetByCharacters: start)
                let b = out.index(a, offsetByCharacters: length)
                out[a..<b].swiftUI.foregroundColor = SR.accentDeep
                if name.caseInsensitiveCompare(me ?? "") == .orderedSame {
                    out[a..<b].swiftUI.font = SR.Text.bodyMedium(15).bold()
                }
            }
        }
        return out
    }
}

/// "Mentions you", on a thread that names this phone's person.
struct FamilyMentionTag: View {
    var body: some View {
        Label("Mentions you", systemImage: "at")
            .font(SR.Text.label(11))
            .foregroundStyle(SR.accentDeep)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(SR.accentDeep.opacity(0.12)))
            .accessibilityIdentifier("family-mentions-you")
    }
}

// MARK: - Polls

/// A poll as bars: each option, how many chose it and who, the reader's own
/// choice ticked. Interactive in the thread (`vote`), read-only on the list's
/// card, where a tap opens the thread.
struct FamilyPollView: View {
    let poll: FamilyPoll
    let counts: [FamilyPoll.Count]
    var vote: ((Int) -> Void)? = nil
    var busy = false

    var body: some View {
        let total = max(counts.map(\.votes).reduce(0, +), 1)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(SR.accentDeep)
                    .accessibilityHidden(true)
                Text(poll.question)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(counts) { count in
                option(count, share: Double(count.votes) / Double(total))
            }
            Text(summary)
                .font(SR.Text.mono(11))
                .foregroundStyle(SR.inkMuted)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("family-poll")
    }

    private var summary: String {
        let votes = counts.map(\.votes).reduce(0, +)
        let voted = votes == 1 ? "1 vote" : "\(votes) votes"
        return vote == nil ? voted : "\(voted) · tap to vote, tap again to take it back"
    }

    @ViewBuilder
    private func option(_ count: FamilyPoll.Count, share: Double) -> some View {
        let row = HStack(spacing: 8) {
            Image(systemName: count.mine ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(count.mine ? SR.accentDeep : SR.inkGhost)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(count.label)
                        .font(SR.Text.bodyMedium(14))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text("\(count.votes)")
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(SR.ink.opacity(0.07))
                        Capsule().fill(count.mine ? SR.accentDeep : SR.accent.opacity(0.55))
                            .frame(width: max(count.votes > 0 ? 6 : 0, geo.size.width * share))
                    }
                }
                .frame(height: 6)
                if !count.names.isEmpty {
                    Text(count.names.joined(separator: ", "))
                        .font(SR.Text.secondary(12))
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        if let vote {
            Button {
                SRHaptic.tap()
                vote(count.option)
            } label: { row }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityLabel("\(count.label), \(count.votes) \(count.votes == 1 ? "vote" : "votes")\(count.mine ? ", your choice" : "")")
                .accessibilityIdentifier("family-poll-option-\(count.option)")
        } else {
            row
                .accessibilityElement(children: .combine)
        }
    }
}

/// A poll as the sheet opens on it: blank from the Poll chip over the box, or
/// written out by a suggestion on msg family's landing ("Dinner tonight?").
struct FamilyPollDraft: Identifiable {
    let id = UUID()
    var question = ""
    var options: [String] = []
}

/// The sheet that writes a poll: a question and two to four answers.
struct FamilyPollComposer: View {
    let send: (FamilyPoll) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var question: String
    @State private var options: [Answer]
    @State private var sending = false

    /// One answer's box. Identified, so taking one away never leaves a box
    /// bound to an index that has gone.
    struct Answer: Identifiable {
        let id = UUID()
        var text = ""
    }

    /// Opened on `question` and `options` when a suggestion wrote them; every
    /// word can still be changed before Send. Always two boxes at least.
    init(question: String = "", options: [String] = [], send: @escaping (FamilyPoll) async -> Bool) {
        self.send = send
        let written = options.prefix(FamilyPoll.maxOptions).map { Answer(text: $0) }
        _question = State(initialValue: question)
        _options = State(initialValue: written + (0..<max(0, 2 - written.count)).map { _ in Answer() })
    }

    private var poll: FamilyPoll? { FamilyPoll.make(question: question, options: options.map(\.text)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What are you asking?", text: $question, axis: .vertical)
                        .accessibilityIdentifier("family-poll-question")
                } header: {
                    SRSectionLabel(text: "Question")
                }
                Section {
                    ForEach($options) { $answer in
                        let index = options.firstIndex { $0.id == answer.id } ?? 0
                        HStack {
                            Text(FamilyPoll.markers[min(index, FamilyPoll.markers.count - 1)]).accessibilityHidden(true)
                            TextField("Answer \(index + 1)", text: $answer.text)
                                .accessibilityIdentifier("family-poll-answer-\(index)")
                            if options.count > 2 {
                                Button {
                                    options.removeAll { $0.id == answer.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(SR.inkMuted)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove answer \(index + 1)")
                            }
                        }
                    }
                    if options.count < FamilyPoll.maxOptions {
                        Button {
                            options.append(Answer())
                        } label: {
                            Label("Add an answer", systemImage: "plus.circle")
                        }
                        .accessibilityIdentifier("family-poll-add")
                    }
                } header: {
                    SRSectionLabel(text: "Answers")
                } footer: {
                    Text("Everyone gets it as a message and votes with a tap. On an older app it reads as numbered answers.")
                        .font(SR.Text.secondary(13))
                }
            }
            .navigationTitle("New poll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let poll else { return }
                        sending = true
                        Task {
                            if await send(poll) { dismiss() }
                            sending = false
                        }
                    } label: {
                        if sending { ProgressView() } else { Text("Send") }
                    }
                    .disabled(sending || FamilyMessages.sendable(poll?.body ?? "") == nil)
                    .accessibilityIdentifier("family-poll-send")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Over the box

/// Over the box: who an "@" could mean while one is being typed; otherwise
/// a poll, "where I am" and the quick messages. One tap fills the box —
/// nothing is sent until Send.
struct FamilyComposerAccessories: View {
    @Binding var draft: String
    let names: [String]
    var poll: (() -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let query = FamilyMessageTools.mentionQuery(draft) {
                    let candidates = FamilyMessageTools.mentionCandidates(query, names: names)
                    ForEach(candidates, id: \.self) { name in
                        chip("@\(name)", icon: nil, id: "family-mention-\(name)") {
                            draft = FamilyMessageTools.complete(draft, with: name)
                        }
                    }
                    if candidates.isEmpty {
                        Text("No one called that")
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.inkMuted)
                            .padding(.horizontal, 6)
                    }
                } else {
                    if let poll {
                        chip("Poll", icon: "chart.bar", id: "family-poll-new") { poll() }
                    }
                    if let here = Self.whereIAm() {
                        chip("Where I am", icon: "location.fill", id: "family-where") { append(here) }
                    }
                    ForEach(FamilyMessageTools.quick, id: \.self) { line in
                        chip(line, icon: nil, id: "family-quick-\(line)") { append(line) }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("family-composer-accessories")
    }

    private func append(_ text: String) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = trimmed.isEmpty ? text : trimmed + " " + text
    }

    private func chip(_ title: String, icon: String?, id: String, action: @escaping () -> Void) -> some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).imageScale(.small).accessibilityHidden(true) }
                Text(title).lineLimit(1)
            }
            .font(SR.Text.bodyMedium(13))
            .foregroundStyle(SR.ink)
            .padding(.horizontal, 11)
            .frame(minHeight: 32)
            .background(Capsule().fill(SR.surface))
            .overlay(Capsule().strokeBorder(SR.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// This phone's own place, from the family view it was last sent.
    @MainActor
    static func whereIAm() -> String? {
        guard let view = FamilyStore.current?.view,
              let me = FamilyOrbitModel.make(view: view, watch: view.watch)?.people.first(where: \.isSelf) else { return nil }
        return FamilyMessageTools.whereIAm(atHome: me.atHome, place: me.place, km: me.km)
    }
}

// MARK: - Headings

/// "Today", "Yesterday", "Mon 26 Oct" between the threads.
struct FamilyDayHeading: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(SR.Text.label(11))
            .tracking(1)
            .foregroundStyle(SR.inkMuted)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The line above what came in since msg family was last open.
struct FamilyNewLine: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(SR.accentDeep.opacity(0.5)).frame(height: 1)
            Text(count == 1 ? "1 NEW" : "\(count) NEW")
                .font(SR.Text.label(11))
                .foregroundStyle(SR.accentDeep)
                .fixedSize()
            Rectangle().fill(SR.accentDeep.opacity(0.5)).frame(height: 1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("family-new-line")
    }
}

// MARK: - Reminders

/// "Remind me later" on a message: a notification on this phone at the
/// chosen time that opens the thread, like the site's own message pushes.
enum FamilyMessageReminders {
    /// Set it. The time it is set for, or nil when notifications are off.
    static func schedule(_ message: FamilyMessage, _ choice: FamilyMessageTools.Remind, now: Date = Date()) async -> Date? {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return nil }
        let at = FamilyMessageTools.remindAt(choice, now: now)
        let content = UNMutableNotificationContent()
        content.title = "msg family"
        content.body = "\(message.mine ? "Your message" : FamilyMessagesStore.first(message.fromName)): \(message.body)"
        content.sound = .default
        content.threadIdentifier = AlertActions.familyMessageCategory
        content.userInfo = ["category": AlertActions.familyMessageCategory, "messageId": message.id]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, at.timeIntervalSince(now)), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: "msg-remind-\(message.id)", content: content, trigger: trigger))
            return at
        } catch {
            return nil
        }
    }
}

/// "Remind me later", as a menu inside a message's long press.
struct FamilyRemindMenu: View {
    let message: FamilyMessage
    @ObservedObject var store: FamilyMessagesStore

    var body: some View {
        Menu {
            ForEach(FamilyMessageTools.Remind.allCases) { choice in
                Button(choice.title) {
                    Task {
                        if let at = await FamilyMessageReminders.schedule(message, choice) {
                            SRHaptic.ok()
                            store.notice = "Reminder set for \(at.formatted(date: Calendar.current.isDateInToday(at) ? .omitted : .abbreviated, time: .shortened))"
                        } else {
                            SRHaptic.bad()
                            store.notice = "Turn on notifications for SR in Settings to be reminded."
                        }
                    }
                }
            }
        } label: {
            Label("Remind me later", systemImage: "bell.badge")
        }
    }
}
