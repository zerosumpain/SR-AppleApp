import SwiftUI

/// Talk: the valley's conversation, read like a chat thread, and the place
/// John whispers to JKai.
///
/// Oldest at the top, newest at the foot, as the Chat thread reads. Speech is
/// a bubble from JKai or Wren with the person spoken to in its byline; a
/// thought is a quieter italic line that opens to its goal and mood; a diary
/// is a card. John's whispers are his own bubbles on the right, each with what
/// became of it — waiting, heard, or pushed out — and, once heard, the thought
/// that heard it, which a tap scrolls to.
///
/// The composer is pinned by the safe area like Chat's: "Whisper to JKai…", a
/// 240-character count, send off while there is nothing to send, too much,
/// the valley cannot hear (offline, paused, between lives, JKai dead) or a
/// whisper is already going. Gone while the owner is viewing as someone else.
/// Older talk loads at the top; newer is fetched while the page is up
/// (`WildmindTalkStore`).
struct WildmindTalkScreen: View {
    /// Open with the composer focused (the Wildmind page's "Whisper to JKai").
    var compose = false

    @ObservedObject private var store = WildmindTalkStore.shared
    @ObservedObject private var valley = WildmindStore.shared
    @ObservedObject private var access = AccessStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    /// Thoughts opened to their goal and mood.
    @State private var expanded: Set<Int> = []
    /// The row just scrolled to from a whisper, lit for a moment.
    @State private var highlighted: Int?
    /// Set a beat after the page opens, so the "Earlier" row appearing in the
    /// first layout does not page the whole history in.
    @State private var settled = false

    private static let foot = "wildmind-talk-foot"

    private var viewingAs: Bool { access.viewingAs != nil }
    private var mainName: String { valley.answer?.snapshot?.main?.name ?? "JKai" }
    private var companionName: String { valley.answer?.snapshot?.companion?.name ?? "Wren" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    thread(proxy)
                    Color.clear
                        .frame(height: 1)
                        .id(Self.foot)
                }
                .padding(.horizontal, SR.gutter)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("wildmind-talk-screen")
            .onChange(of: store.footTick) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(Self.foot, anchor: .bottom) }
            }
            .onChange(of: composerFocused) { _, focused in
                if focused { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(Self.foot, anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { filters }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewingAs { viewingAsNote } else { composer }
        }
        .srGround(.wire)
        .navigationTitle("Talk")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SRBarMark() } }
        .onAppear {
            // A refusal from an earlier visit has been seen; and a page opened
            // to whisper shows the whispers.
            store.acknowledgeFailure()
            if compose && !viewingAs { store.showWhispers() }
        }
        .onChange(of: draft) { _, _ in store.acknowledgeFailure() }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await store.poll()
        }
        .task {
            if compose && !viewingAs {
                // Focus once the push has finished, or the keyboard fights it.
                try? await Task.sleep(for: .milliseconds(450))
                composerFocused = true
            }
            try? await Task.sleep(for: .seconds(1))
            settled = true
        }
        .srRefreshable { await store.refreshAll() }
    }

    // MARK: - Filters

    /// All · Said · Thought · Whispers · Diaries, then Both · JKai · Wren.
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WildmindTalkFilter.Kinds.allCases, id: \.self) { kinds in
                    WildmindChip(label: kinds.label, selected: store.filter.kinds == kinds,
                                 identifier: "wildmind-talk-kind-\(kinds.rawValue)") {
                        var next = store.filter
                        next.kinds = kinds
                        store.setFilter(next)
                    }
                }
                Rectangle()
                    .fill(SR.line)
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 4)
                    .accessibilityHidden(true)
                ForEach(WildmindTalkFilter.Who.allCases, id: \.self) { who in
                    WildmindChip(label: whoLabel(who), selected: store.filter.who == who,
                                 identifier: "wildmind-talk-who-\(who.rawValue)") {
                        var next = store.filter
                        next.who = who
                        store.setFilter(next)
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
        // Its own height and no more: a horizontal scroll view offered the
        // whole inset grows to fill it, and the chips floated mid-thread.
        .fixedSize(horizontal: false, vertical: true)
        // The thread scrolls up beneath the chips, so they sit on a fade of
        // the page's own paper rather than over the words.
        .background {
            LinearGradient(stops: [.init(color: SR.paper, location: 0.55),
                                   .init(color: SR.paper.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
                .accessibilityHidden(true)
        }
    }

    private func whoLabel(_ who: WildmindTalkFilter.Who) -> String {
        switch who {
        case .both: return "Both"
        case .main: return mainName
        case .companion: return companionName
        }
    }

    // MARK: - The thread

    @ViewBuilder
    private func thread(_ proxy: ScrollViewProxy) -> some View {
        switch store.phase {
        case .ready:
            if store.hasOlder {
                olderRow(proxy)
            } else if !store.entries.isEmpty {
                Text("The start of what the valley has kept.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            if store.stale {
                WildmindStaleNote()
            }
            if store.entries.isEmpty {
                SREmpty(title: "Nothing yet", icon: "text.bubble", message: emptyMessage)
            }
            ForEach(rows) { row in
                if let day = row.day {
                    dayRule(day)
                }
                entryView(row.entry, proxy: proxy)
                    .id(row.entry.id)
                    .background {
                        if highlighted == row.entry.id {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(SR.accent.opacity(0.12))
                                .padding(-8)
                                .transition(.opacity)
                        }
                    }
            }
        default:
            WildmindLaneStateView(phase: store.phase, what: "Talk") {
                Task { await store.refresh() }
            }
        }
    }

    private var emptyMessage: String {
        store.filter == WildmindTalkFilter()
            ? "Nobody\u{2019}s said anything in this valley yet."
            : "Nothing like that yet. Try another filter."
    }

    /// An entry, with the valley day it starts when it is a new one.
    private struct Row: Identifiable {
        let entry: WildmindTalkEntry
        let day: Int?
        var id: Int { entry.id }
    }

    private var rows: [Row] {
        var last: Int?
        return store.entries.map { entry in
            let day = WildmindTalkWords.day(entry)
            defer { if day != nil { last = day } }
            return Row(entry: entry, day: day != nil && day != last ? day : nil)
        }
    }

    private func dayRule(_ day: Int) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(SR.line).frame(height: 1)
            Text("DAY \(day)")
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.inkMuted)
                .fixedSize()
            Rectangle().fill(SR.line).frame(height: 1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day \(day)")
        .accessibilityAddTraits(.isHeader)
    }

    private func olderRow(_ proxy: ScrollViewProxy) -> some View {
        Button {
            loadOlder(proxy)
        } label: {
            HStack(spacing: 8) {
                if store.loadingOlder {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text("EARLIER")
                    .font(SR.Text.label())
                    .tracking(1.2)
            }
            .foregroundStyle(SR.inkSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .srGlass(.paper, in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Load earlier talk")
        .accessibilityIdentifier("wildmind-talk-earlier")
        .onAppear {
            if settled { loadOlder(proxy) }
        }
    }

    private func loadOlder(_ proxy: ScrollViewProxy) {
        guard !store.loadingOlder else { return }
        let anchor = store.entries.first?.id
        Task {
            await store.loadOlder()
            // Keep the reader where they were rather than at the new top.
            if let anchor { proxy.scrollTo(anchor, anchor: .top) }
        }
    }

    @ViewBuilder
    private func entryView(_ entry: WildmindTalkEntry, proxy: ScrollViewProxy) -> some View {
        switch entry.kind {
        case .speech: speech(entry)
        case .thought: thought(entry)
        case .diary: diary(entry)
        case .whisper: whisper(entry, proxy: proxy)
        case .unknown:
            Text(entry.text)
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func name(_ entry: WildmindTalkEntry) -> String {
        entry.name ?? (entry.who == "companion" ? companionName : mainName)
    }

    // MARK: Speech

    private func speech(_ entry: WildmindTalkEntry) -> some View {
        let tone = WildmindTone.of(who: entry.who)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(tone).frame(width: 7, height: 7)
                Text(WildmindTalkWords.speechByline(entry).uppercased())
                    .font(SR.Text.mono())
                    .tracking(0.8)
                    .foregroundStyle(SR.inkMuted)
            }
            Text(entry.text)
                .font(SR.Text.body(16))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 16)
                .padding(.trailing, 14)
                .padding(.vertical, 10)
                .overlay(alignment: .leading) {
                    Capsule().fill(tone).frame(width: 3).padding(.vertical, 10).padding(.leading, 6)
                }
                .srGlass(.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.trailing, 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(speechLabel(entry))
    }

    private func speechLabel(_ entry: WildmindTalkEntry) -> String {
        var label = name(entry)
        if let to = entry.toName ?? entry.to { label += " to \(to)" }
        label += ": \(entry.text)"
        if let when = entry.when { label += ", \(when)" }
        return label
    }

    // MARK: Thought

    private func thought(_ entry: WildmindTalkEntry) -> some View {
        let tone = WildmindTone.of(who: entry.who)
        let open = expanded.contains(entry.id)
        let answering = store.answered(by: entry) != nil
        let hasDetail = entry.goal != nil || entry.mood != nil
        return Button {
            guard hasDetail else { return }
            SRHaptic.select()
            withAnimation(.easeOut(duration: 0.2)) {
                if open { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "thought.bubble")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(tone.opacity(0.85))
                    .frame(width: 20)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(thoughtByline(entry).uppercased())
                        .font(SR.Text.mono())
                        .tracking(0.8)
                        .foregroundStyle(SR.inkMuted)
                    Text(entry.text)
                        .font(SR.Text.secondary(15))
                        .italic()
                        .foregroundStyle(SR.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if open {
                        VStack(alignment: .leading, spacing: 4) {
                            detailRow("Goal", entry.goal)
                            detailRow("Mood", entry.mood)
                        }
                        .padding(.top, 4)
                        .transition(.opacity)
                    }
                    if answering {
                        Label("Answering your whisper", systemImage: "ear")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.accent)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                if hasDetail {
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SR.inkGhost)
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(hasDetail ? (open ? "Hides the goal and mood" : "Shows the goal and mood") as String : ""))
        .accessibilityIdentifier("wildmind-talk-thought")
    }

    private func thoughtByline(_ entry: WildmindTalkEntry) -> String {
        var line = "\(name(entry)) thought"
        if let time = WildmindTalkWords.time(of: entry.when) { line += " \u{00B7} \(time)" }
        return line
    }

    private func detailRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.inkMuted)
                .frame(width: 52, alignment: .leading)
            Text(value ?? "\u{2014}")
                .font(SR.Text.body(15))
                .foregroundStyle(value == nil ? SR.inkMuted : SR.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Diary

    private func diary(_ entry: WildmindTalkEntry) -> some View {
        let day = WildmindTalkWords.diaryDay(entry.text) ?? WildmindTalkWords.day(entry)
        return SRCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WildmindTone.of(who: entry.who))
                        .accessibilityHidden(true)
                    Text("\(name(entry))\u{2019}s diary\(day.map { " \u{00B7} day \($0)" } ?? "")".uppercased())
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(SR.inkMuted)
                }
                Text(WildmindTalkWords.diaryBody(entry.text))
                    .font(SR.Text.body(16))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wildmind-talk-diary")
    }

    // MARK: Whisper

    private func whisper(_ entry: WildmindTalkEntry, proxy: ScrollViewProxy) -> some View {
        let known = store.whisper(for: entry)
        let mine = known != nil || store.flow.sentIds.contains(entry.id)
        return VStack(alignment: .trailing, spacing: 5) {
            Text("You \u{2192} \(mainName)\(WildmindTalkWords.time(of: entry.when).map { " \u{00B7} \($0)" } ?? "")".uppercased())
                .font(SR.Text.mono())
                .tracking(0.8)
                .foregroundStyle(SR.inkMuted)
            Text(entry.text)
                .font(SR.Text.body(16))
                .foregroundStyle(SR.paper)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .srGlass(.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityLabel("You whispered: \(entry.text)")
            if mine {
                whisperStatus(known)
            }
            if let answer = known?.answer, let thought = answer.thought {
                Button {
                    jump(to: answer.logId, proxy: proxy)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("\u{201C}\(thought)\u{201D}")
                            .font(SR.Text.secondary(14))
                            .italic()
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                    .foregroundStyle(SR.inkSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mainName) thought: \(thought)")
                .accessibilityHint("Shows the thought in the thread")
            }
        }
        .padding(.leading, 44)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wildmind-talk-whisper")
    }

    @ViewBuilder
    private func whisperStatus(_ whisper: WildmindWhisper?) -> some View {
        let text = WildmindWhisperWords.status(whisper, main: mainName)
        HStack(spacing: 5) {
            switch whisper?.status {
            case .heard?:
                Image(systemName: "ear").font(.system(size: 11, weight: .semibold))
            case .dropped?:
                Image(systemName: "exclamationmark.circle").font(.system(size: 11, weight: .semibold))
            case .pending?, .unknown?, nil:
                if store.flow.isWatching(now: Date()) {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "clock").font(.system(size: 11, weight: .semibold))
                }
            }
            Text(text)
                .font(SR.Text.mono())
                .accessibilityIdentifier("wildmind-whisper-status")
        }
        .foregroundStyle(statusTone(whisper))
    }

    private func statusTone(_ whisper: WildmindWhisper?) -> Color {
        switch whisper?.status {
        case .heard?: return SR.good
        case .dropped?: return SR.warn
        default: return SR.inkMuted
        }
    }

    private func jump(to id: Int?, proxy: ScrollViewProxy) {
        guard let id, store.entries.contains(where: { $0.id == id }) else { return }
        SRHaptic.select()
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(id, anchor: .center)
            highlighted = id
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if highlighted == id { withAnimation { highlighted = nil } }
        }
    }

    // MARK: - The composer

    private var block: WildmindWhisperFailure? {
        store.sendBlock(valleyState: valley.answer == nil ? nil : valley.state,
                        mainAlive: valley.answer?.snapshot?.main?.alive)
    }

    /// Pinned above the keyboard by the safe area, as Chat's is.
    private var composer: some View {
        let block = self.block
        let count = WildmindWhisperText.count(draft)
        return VStack(spacing: 6) {
            composerNote(block)
            SRGlassGroup(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Whisper to \(mainName)\u{2026}", text: $draft, axis: .vertical)
                        .font(SR.Text.body())
                        .foregroundStyle(SR.ink)
                        .lineLimit(1...4)
                        .focused($composerFocused)
                        .disabled(store.flow.isSending)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(minHeight: 48)
                        .srGlass(.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .accessibilityIdentifier("wildmind-whisper-field")
                    sendButton(block)
                }
            }
            if count > 0 {
                Text("\(count)/\(WildmindWhisperText.limit)")
                    .font(SR.Text.mono())
                    .monospacedDigit()
                    .foregroundStyle(count > WildmindWhisperText.limit ? SR.error : SR.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 70)
                    .accessibilityLabel("\(count) of \(WildmindWhisperText.limit) characters")
                    .accessibilityIdentifier("wildmind-whisper-count")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    /// One line over the composer: the last refusal, why nobody can hear a
    /// whisper now, or whether one will be heard soon.
    @ViewBuilder
    private func composerNote(_ block: WildmindWhisperFailure?) -> some View {
        if let failure = store.flow.banner(now: Date()) {
            if case .slowDown = failure {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let left = store.flow.coolingSeconds(now: context.date) {
                        SRBanner(text: WildmindWhisperFailure.slowDown(retryAfter: left).message, tone: SR.error)
                    }
                }
            } else {
                SRBanner(text: failure.message, tone: SR.error)
            }
        } else if let block {
            note(block.blockMessage, icon: "moon.zzz")
        } else if let dropped = store.lastAccepted?.dropped, store.flow.isWatching(now: Date()) {
            note("That pushed out \u{201C}\(dropped)\u{201D}, which \(mainName) hadn\u{2019}t heard yet.", icon: "arrow.uturn.down")
        } else if let line = WildmindWhisperWords.readiness(
            store.whispers,
            asleep: store.lastAccepted?.asleep == true && store.flow.isWatching(now: Date()),
            main: mainName
        ) {
            note(line, icon: "info.circle")
        }
    }

    private func note(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(SR.Text.secondary(14))
            .foregroundStyle(SR.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .accessibilityIdentifier("wildmind-whisper-note")
    }

    private func sendButton(_ block: WildmindWhisperFailure?) -> some View {
        let ready = store.flow.canSend(draft, blocked: block != nil, now: Date())
        return Button {
            send()
        } label: {
            ZStack {
                if store.flow.isSending {
                    ProgressView().tint(SR.inkMuted)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .foregroundStyle(ready ? SR.paper : SR.inkMuted)
            .frame(width: 48, height: 48)
            .srGlass(ready ? .accent : .paper, in: Circle(), interactive: true)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .accessibilityLabel("Whisper")
        .accessibilityIdentifier("wildmind-whisper-send")
    }

    private func send() {
        let text = draft
        SRHaptic.tap()
        Task {
            if await store.send(text) {
                clearDraft()
                composerFocused = false
                SRHaptic.ok()
            } else {
                SRHaptic.bad()
            }
        }
    }

    /// Empty the composer, then again a moment later: the keyboard can still
    /// be holding a prediction it commits after the first clear (see Chat).
    private func clearDraft() {
        draft = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { draft = "" }
    }

    private var viewingAsNote: some View {
        Label("Viewing as someone else, so whispering is off.", systemImage: "eye")
            .font(SR.Text.secondary(14))
            .foregroundStyle(SR.inkMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, SR.gutter)
            .srGlass(.paper, in: Capsule())
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }
}
