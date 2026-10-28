import SwiftUI
import AVFoundation

/// One capture: listen, read it by speaker, say who the speakers were, fix
/// the app the screenshot came from, decide each follow-up, or delete it.
///
/// Nothing on this page runs anything by itself. A follow-up runs on the
/// site only when Approve is tapped on it (`POST …/actions/:id`), and only
/// that one.
struct CaptureDetailScreen: View {
    let ref: CaptureRef

    @ObservedObject private var store = CaptureStore.shared
    @StateObject private var player = CapturePlayer()
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var capture: Capture?
    @State private var error: String?
    @State private var working: String?
    @State private var naming: CaptureSpeaker?
    @State private var nameDraft = ""
    @State private var correctingApp = false
    @State private var appDraft = ""
    @State private var editing: CaptureAction?
    @State private var confirmDelete = false
    @State private var screenImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                if let capture {
                    header(capture)
                    if let error { SRBanner(text: error, tone: SR.error) }
                    playerCard(capture)
                    if !capture.actions.isEmpty { actions(capture) }
                    speakers(capture)
                    transcript(capture)
                    if !capture.flow.isEmpty { flow(capture) }
                    if capture.screen != nil || capture.screenUrl != nil { screen(capture) }
                    if !capture.entities.isEmpty { mentions(capture) }
                    deleteButton
                } else if let error {
                    SREmpty(title: "This capture didn't load", icon: "wifi.exclamationmark", message: error,
                            actionLabel: "Try again", action: { Task { await load() } })
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .srPaper()
        .navigationTitle(capture?.title ?? "Capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Hand this recording to jkai by id (a `capture` ref): the turn
            // reads its summary itself, labelled as other people's words.
            if let capture, AccessStore.shared.allows(.chat) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        SRHaptic.tap()
                        router.ask("About “\(capture.title ?? "this recording")”: ", refs: [.capture(capture.id)])
                    } label: { Label("Ask jkai", systemImage: "sparkle") }
                    .accessibilityIdentifier("capture-ask-jkai")
                }
            }
        }
        // Polled while the site is still reading it, and only while the page
        // is in front: every 5 s for five minutes, then not at all.
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await load()
            var waited = 0
            while let status = capture?.statusValue, status == .received || status == .analysing, waited < 60 {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { return }
                waited += 1
                await load()
            }
        }
        .srRefreshable { await load() }
        .onDisappear { player.stop() }
        .alert("Who is this?", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $nameDraft)
            Button("Save") {
                if let speaker = naming { Task { await confirm(speaker, name: nameDraft, entityId: nil) } }
                naming = nil
            }
            Button("Cancel", role: .cancel) { naming = nil }
        } message: {
            Text("The name is linked to the person in your graph, and helps the next guess.")
        }
        .alert("Which app was it?", isPresented: $correctingApp) {
            TextField("App name", text: $appDraft)
            Button("Save") { Task { await correctApp(appDraft) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this capture?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text("The recording, the screenshot, the follow-ups and what it added to your graph are removed.")
        }
        .sheet(item: $editing) { action in
            CaptureActionEditor(action: action) { params in
                editing = nil
                Task { await decide(action, .approve(params: params)) }
            }
        }
        .accessibilityIdentifier("capture-detail")
    }

    // MARK: - Sections

    private func header(_ capture: Capture) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRPageHeader(
                kicker: kicker(capture),
                title: capture.title?.isEmpty == false ? capture.title! : "Untitled capture",
                strap: capture.summary
            )
            HStack(spacing: 8) {
                SRGlassChip(text: capture.statusValue.label, tone: capture.statusValue == .failed ? SR.error : SR.accent)
                if let app = capture.screen?.appName { SRGlassChip(text: app, icon: "app") }
                if capture.transcriptSource == "server" { SRGlassChip(text: "Transcribed by the site") }
            }
            if capture.statusValue == .failed, let reason = capture.error {
                Text(reason).font(SR.Text.secondary()).foregroundStyle(SR.error)
            }
        }
    }

    private func kicker(_ capture: Capture) -> String {
        var parts: [String] = []
        if let date = capture.started { parts.append(date.formatted(.dateTime.weekday(.wide).day().month().hour().minute())) }
        if let duration = capture.durationS { parts.append(CaptureClock.duration(duration)) }
        return parts.joined(separator: " · ")
    }

    private func playerCard(_ capture: Capture) -> some View {
        SRCard {
            HStack(spacing: 14) {
                Button {
                    SRHaptic.tap()
                    Task { await player.toggle(captureId: capture.id) }
                } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 48, height: 48)
                        .foregroundStyle(SR.paper)
                        .background(Circle().fill(SR.accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.playing ? "Pause" : "Play")
                .disabled(capture.audioUrl == nil && !SRDemo.isOn)
                VStack(alignment: .leading, spacing: 4) {
                    Text(capture.audioUrl == nil ? "No recording kept" : "The recording")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Text(player.problem ?? "\(CaptureClock.duration(player.position)) of \(CaptureClock.duration(player.duration ?? capture.durationS ?? 0))")
                        .font(SR.Text.mono())
                        .foregroundStyle(player.problem == nil ? SR.inkMuted : SR.error)
                }
                Spacer()
                if player.loading { ProgressView() }
            }
        }
    }

    private func speakers(_ capture: Capture) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Who spoke", trailing: capture.speakers.isEmpty ? "One voice" : "\(capture.speakers.count)")
            if capture.speakers.isEmpty {
                Text("The phone heard one voice, or could not tell voices apart.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            ForEach(capture.speakers) { speaker in
                SRCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(speaker.displayName)
                                .font(SR.Text.title())
                                .foregroundStyle(SR.ink)
                            Spacer()
                            Text(speaker.label).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                        }
                        if let line = guessLine(speaker) {
                            Text(line)
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if speaker.confirmed == nil && !speaker.isOwner {
                            HStack(spacing: 10) {
                                if let guess = speaker.guess, !guess.name.isEmpty {
                                    Button {
                                        SRHaptic.ok()
                                        Task { await confirm(speaker, name: guess.name, entityId: guess.entityId) }
                                    } label: { SRButtonLabel(title: "It's \(guess.name)", icon: "checkmark") }
                                    .srButton(.prominent)
                                }
                                Button {
                                    SRHaptic.tap()
                                    nameDraft = ""
                                    naming = speaker
                                } label: { SRButtonLabel(title: speaker.guess == nil ? "Name them" : "Someone else") }
                                .srButton(.regular)
                            }
                            .disabled(working != nil)
                        }
                    }
                }
            }
        }
    }

    /// "Probably Sam · 82% · calendar, named twice" — a guess, said as one.
    private func guessLine(_ speaker: CaptureSpeaker) -> String? {
        if speaker.isOwner { return "Your voice" }
        if let confirmed = speaker.confirmed { return confirmed.entityId == nil ? "Named by you" : "Named by you · in your graph" }
        guard let guess = speaker.guess, !guess.name.isEmpty else { return nil }
        var line = "Probably \(guess.name) · \(Int((guess.confidence * 100).rounded()))%"
        if !guess.evidence.isEmpty { line += " · " + guess.evidence.joined(separator: ", ") }
        return line
    }

    private func transcript(_ capture: Capture) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "What was said")
            let turns = capture.shownTurns
            if turns.isEmpty {
                Text(capture.statusValue == .ready ? "No words were heard." : "The words arrive once it has been read.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            ForEach(Array(turns.enumerated()), id: \.offset) { _, turn in
                Button {
                    SRHaptic.tap()
                    Task { await player.play(captureId: capture.id, from: turn.start) }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text((capture.speaker(turn.speaker)?.displayName ?? turn.speaker).uppercased())
                                .font(SR.Text.label())
                                .tracking(1)
                                .foregroundStyle(tone(for: turn.speaker, in: capture))
                            Text(CaptureClock.duration(turn.start))
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkGhost)
                        }
                        Text(turn.text)
                            .font(SR.Text.body())
                            .foregroundStyle(SR.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Plays from here")
            }
        }
    }

    private func tone(for label: String, in capture: Capture) -> Color {
        if capture.speaker(label)?.isOwner == true { return SR.accent }
        let palette = [SR.accentInk, SR.good, SR.accentDeep, SR.warn, SR.inkSecondary]
        let index = Int(label.filter(\.isNumber)) ?? 0
        return palette[abs(index) % palette.count]
    }

    private func flow(_ capture: Capture) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "How it went")
            SRCard {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(capture.flow.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(CaptureClock.duration(item.fromS))
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                                .frame(minWidth: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.topic).font(SR.Text.bodyMedium()).foregroundStyle(SR.ink)
                                if !item.speakers.isEmpty {
                                    Text(item.speakers.map { capture.speaker($0)?.displayName ?? $0 }.joined(separator: ", "))
                                        .font(SR.Text.secondary(13))
                                        .foregroundStyle(SR.inkMuted)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func screen(_ capture: Capture) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "On screen")
            SRCard {
                VStack(alignment: .leading, spacing: 10) {
                    if capture.screen?.denied == true {
                        Label("The screenshot stayed on the phone: its app is on your deny list, or it showed something private.", systemImage: "eye.slash")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                    } else if let screenImage {
                        Image(uiImage: screenImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
                            .accessibilityLabel("The screenshot")
                    } else if capture.screenUrl != nil {
                        ProgressView().frame(maxWidth: .infinity)
                            .task { screenImage = (try? await store.screen(capture.id)).flatMap(UIImage.init(data:)) }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(capture.screen?.appName ?? "App not known")
                                .font(SR.Text.title())
                                .foregroundStyle(SR.ink)
                            if let app = capture.screen?.app, capture.screen?.corrected == nil {
                                Text("Read from the screenshot · \(Int((app.confidence * 100).rounded()))% sure")
                                    .font(SR.Text.mono())
                                    .foregroundStyle(SR.inkMuted)
                            } else if capture.screen?.corrected != nil {
                                Text("Corrected by you").font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                            }
                        }
                        Spacer()
                        Button {
                            SRHaptic.tap()
                            appDraft = capture.screen?.appName ?? ""
                            correctingApp = true
                        } label: { SRButtonLabel(title: "Correct") }
                        .srButton(.regular)
                        .disabled(working != nil)
                    }
                    if let summary = capture.screen?.summary, !summary.isEmpty {
                        Text(summary)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func actions(_ capture: Capture) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Follow-ups", trailing: capture.openActions > 0 ? "\(capture.openActions) to decide" : nil)
            ForEach(capture.actions) { action in
                CaptureActionCard(
                    action: action,
                    speakerName: action.who.flatMap { capture.speaker($0)?.displayName } ?? action.who,
                    busy: working == action.id,
                    approve: {
                        // Edit first when there is something to edit; a
                        // calendar entry always shows what it will write.
                        if !action.params.isEmpty || action.kindValue == .calendar {
                            editing = action
                        } else {
                            Task { await decide(action, .approve()) }
                        }
                    },
                    dismiss: { Task { await decide(action, .dismiss) } }
                )
            }
        }
    }

    private func mentions(_ capture: Capture) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Mentioned")
            CaptureFlowLayout(spacing: 8) {
                ForEach(Array(capture.entities.enumerated()), id: \.offset) { _, entity in
                    SRGlassChip(text: entity.name, icon: CaptureEntityKind.symbol(entity.type), tone: SR.ink)
                        .accessibilityLabel("\(entity.name), \(entity.type)")
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            SRHaptic.tap()
            confirmDelete = true
        } label: {
            SRButtonLabel(title: "Delete capture", icon: "trash", fill: true)
        }
        .srButton(.regular)
        .tint(SR.error)
        .disabled(working != nil)
        .accessibilityIdentifier("capture-delete")
    }

    // MARK: - Doing

    private func load() async {
        do {
            let fresh = try await store.capture(ref.id)
            capture = fresh
            store.refreshRow(from: fresh)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func confirm(_ speaker: CaptureSpeaker, name: String, entityId: String?) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let capture else { return }
        working = speaker.label
        defer { working = nil }
        do {
            self.capture = try await store.patch(capture.id, CapturePatch(
                speakers: [.init(label: speaker.label, confirmed: CaptureSpeakerName(name: trimmed, entityId: entityId))]
            ))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func correctApp(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let capture else { return }
        working = "screen"
        defer { working = nil }
        do {
            self.capture = try await store.patch(capture.id, CapturePatch(screenApp: trimmed))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func decide(_ action: CaptureAction, _ decision: CaptureDecision) async {
        guard var capture else { return }
        working = action.id
        defer { working = nil }
        do {
            let updated = try await store.decide(capture.id, action.id, decision)
            if let index = capture.actions.firstIndex(where: { $0.id == action.id }) {
                capture.actions[index] = updated
            }
            self.capture = capture
            store.refreshRow(from: capture)
            error = nil
            if updated.stateValue == .failed { SRHaptic.bad() } else { SRHaptic.ok() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() async {
        working = "delete"
        defer { working = nil }
        do {
            player.stop()
            try await store.delete(ref.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// One follow-up: what, for whom, when, and what approving does.
struct CaptureActionCard: View {
    let action: CaptureAction
    let speakerName: String?
    let busy: Bool
    let approve: () -> Void
    let dismiss: () -> Void

    var body: some View {
        SRCard(accented: action.stateValue.open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: action.kindValue?.symbol ?? "questionmark.circle")
                        .foregroundStyle(SR.accent)
                        .accessibilityHidden(true)
                    Text((action.kindValue?.label ?? action.kind).uppercased())
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                    Spacer()
                    SRGlassChip(text: action.stateValue.label, tone: tone)
                }
                Text(action.title)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = action.detail, !detail.isEmpty {
                    Text(detail)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let line = whoWhen {
                    Text(line).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                }
                if let error = action.error, action.stateValue == .failed || action.stateValue == .refused {
                    Text(error).font(SR.Text.secondary(13)).foregroundStyle(SR.error)
                }
                if action.stateValue.open {
                    if let kind = action.kindValue {
                        Text(kind.approveLine)
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.inkMuted)
                        HStack(spacing: 10) {
                            Button {
                                SRHaptic.tap()
                                approve()
                            } label: { SRButtonLabel(title: "Approve", icon: "checkmark") }
                            .srButton(.prominent)
                            Button {
                                SRHaptic.tap()
                                dismiss()
                            } label: { SRButtonLabel(title: "Dismiss") }
                            .srButton(.regular)
                            if busy { ProgressView() }
                        }
                        .disabled(busy)
                    } else {
                        Text("This version of the app can't run this kind of follow-up. Update the app, or dismiss it.")
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.inkMuted)
                        Button { dismiss() } label: { SRButtonLabel(title: "Dismiss") }
                            .srButton(.regular)
                            .disabled(busy)
                    }
                }
            }
        }
        .accessibilityIdentifier("capture-action-\(action.id)")
    }

    private var tone: Color {
        switch action.stateValue {
        case .done: return SR.good
        case .failed, .refused: return SR.error
        case .dismissed: return SR.inkMuted
        default: return SR.accent
        }
    }

    private var whoWhen: String? {
        var parts: [String] = []
        if let speakerName, !speakerName.isEmpty { parts.append(speakerName) }
        if let due = action.dueAt.flatMap(CaptureClock.parse) {
            parts.append(due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Approve with the details in front of you — and changeable. A calendar
/// entry always comes here first, because it writes to a calendar.
struct CaptureActionEditor: View {
    let action: CaptureAction
    /// The edited params, or nil when nothing was changed.
    let approve: ([String: CaptureParamValue]?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]

    private var keys: [String] {
        let order = ["title", "question", "message", "fact", "entity", "start", "end", "when", "location", "attendees", "draft", "calendar"]
        return action.params.keys.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(action.title).font(SR.Text.title()).foregroundStyle(SR.ink)
                    if let kind = action.kindValue {
                        Text(kind.approveLine).font(SR.Text.secondary()).foregroundStyle(SR.inkMuted)
                    }
                }
                if !keys.isEmpty {
                    Section {
                        ForEach(keys, id: \.self) { key in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(label(key).uppercased()).font(SR.Text.label()).foregroundStyle(SR.inkMuted)
                                TextField(label(key), text: Binding(
                                    get: { values[key] ?? action.params[key] ?? "" },
                                    set: { values[key] = $0 }
                                ), axis: .vertical)
                                .font(SR.Text.body())
                            }
                        }
                    } header: {
                        SRSectionLabel(text: "Details")
                    } footer: {
                        if keys.contains("start") || keys.contains("when") {
                            Text("Times are as the site wrote them (ISO, with the zone).").font(SR.Text.secondary(13))
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .srPaper()
            .navigationTitle(action.kindValue?.label ?? "Follow-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Approve") {
                        SRHaptic.ok()
                        var merged = action.params
                        for (key, value) in values { merged[key] = value }
                        // Only send params back when something changed.
                        approve(merged == action.params ? nil : CaptureParamValue.from(merged))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func label(_ key: String) -> String {
        switch key {
        case "question": return "Question"
        case "title": return "Title"
        case "start": return "Starts"
        case "end": return "Ends"
        case "when": return "When"
        case "message": return "Message"
        case "fact": return "Fact"
        case "entity": return "About"
        case "location": return "Where"
        case "attendees": return "With (comma separated)"
        case "draft": return "Draft"
        case "calendar": return "Calendar"
        default: return key.capitalized
        }
    }
}

/// The capture's recording, fetched on the first Play and kept in memory
/// while the page is open.
@MainActor
final class CapturePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playing = false
    @Published private(set) var loading = false
    @Published private(set) var duration: TimeInterval?
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var problem: String?

    private var player: AVAudioPlayer?
    private var ticker: Timer?

    func toggle(captureId: String) async {
        if let player, player.isPlaying {
            pause()
            return
        }
        await play(captureId: captureId, from: nil)
    }

    func play(captureId: String, from time: TimeInterval?) async {
        if player == nil {
            loading = true
            defer { loading = false }
            do {
                let data = try await CaptureStore.shared.audio(captureId)
                let made = try AVAudioPlayer(data: data)
                made.delegate = self
                player = made
                duration = made.duration
                problem = nil
            } catch {
                problem = "The recording didn't load."
                return
            }
        }
        guard let player else { return }
        if let time { player.currentTime = min(max(0, time), player.duration) }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        playing = player.play()
        startTicking()
    }

    func pause() {
        player?.pause()
        playing = false
        stopTicking()
    }

    func stop() {
        player?.stop()
        playing = false
        stopTicking()
    }

    /// Four times a second, and only while playing.
    private func startTicking() {
        stopTicking()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.position = self?.player?.currentTime ?? 0 }
        }
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
        position = player?.currentTime ?? position
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playing = false
            self.stopTicking()
        }
    }
}

/// Chips that wrap onto as many lines as they need.
struct CaptureFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += line + spacing
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += line + spacing
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
