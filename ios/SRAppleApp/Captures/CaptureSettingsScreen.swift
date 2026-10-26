import SwiftUI
import AVFoundation

/// The words Settings → Captures shows for setting up capture from anywhere.
/// Kept as data so the page and anything that quotes it say the same thing.
enum CaptureShortcutRecipe {
    static let title = "Capture what's on screen too"

    static let steps: [String] = [
        "Tap Open Shortcuts below. It opens on a new, empty shortcut.",
        "Add the Take Screenshot action.",
        "Add Start capture (SR Companion). Tap its Screenshot field and choose the Screenshot from the step above.",
        "Name it \u{201C}Capture this\u{201D} and tap Done.",
        buttonStep,
    ]

    static let buttonStep = "Put it on a button: Settings → Action Button → Shortcut → Capture this, or Settings → Accessibility → Touch → Back Tap → Double Tap → Capture this."

    static let footer = "Press once to start and again to stop — the timer and a Stop button are on the Lock Screen while it records. Made it already? In Shortcuts, long-press Capture this → Share → Copy iCloud Link, and paste it above: from then on this page adds it in one tap, after a reinstall too. The screenshot is read on this phone first: if its app is on your deny list below, or it shows a password, a code or a card number, only the app's name is sent."
}

/// The ways to start a capture that need no setup beyond the app itself.
/// Kept as data so the page and anything that quotes it say the same thing.
enum CaptureQuickStart {
    struct Way { let title: String; let how: String; let icon: String }

    static let title = "Start a capture fast"

    static let ways: [Way] = [
        Way(title: "From the app icon", how: "Long-press SR Companion → New capture", icon: "app.badge"),
        Way(title: "By voice", how: "\u{201C}New capture in SR Companion\u{201D}", icon: "waveform"),
        Way(title: "Control Center or Lock Screen", how: "Edit → Add a Control → search SR → Capture", icon: "switch.2"),
        Way(title: "Action Button", how: "Settings → Action Button → Controls → Capture", icon: "button.horizontal.top.press"),
        Way(title: "In the app", how: "⊞ → Captures → Record", icon: "mic.fill"),
    ]

    static let footer = "Press again to stop — the same button, the Stop on the Lock Screen, or Stop in Captures. Control Center, the Lock Screen and the Action Button record without opening the app; they need iOS 18."
}

/// Settings → Captures: the speaker models, the owner's voice, the
/// screenshot deny list, and how to capture from anywhere.
struct CaptureSettingsScreen: View {
    @ObservedObject private var models = CaptureModelsStore.shared
    @StateObject private var enrolment = OwnerVoiceEnrolment()

    @State private var diarize = CaptureSettings.diarize
    @State private var cellular = CaptureSettings.modelsOnCellular
    @State private var sensitive = CaptureSettings.denySensitive
    @State private var denyList = CaptureSettings.denyList
    @State private var newName = ""
    @State private var askCellular = false
    @State private var enrolledAt = OwnerVoice.madeAt
    @State private var shortcutLink = CaptureShortcutLink.current()
    @State private var pastedLink = ""
    @State private var linkRefused = false

    var body: some View {
        List {
            Section {
                ForEach(CaptureQuickStart.ways, id: \.title) { way in
                    SRRow(title: way.title, subtitle: way.how, icon: way.icon)
                        .srGlassRow()
                }
            } header: {
                SRSectionLabel(text: CaptureQuickStart.title)
            } footer: {
                Text(CaptureQuickStart.footer).font(SR.Text.secondary(13))
            }

            Section {
                if let link = shortcutLink {
                    Link(destination: link) {
                        SRRow(title: "Add \u{201C}Capture this\u{201D}", subtitle: "Opens Shortcuts with it ready — tap Add Shortcut", icon: "plus.square.on.square")
                    }
                    .srGlassRow()
                    stepRow(1, CaptureShortcutRecipe.buttonStep)
                } else {
                    ForEach(Array(CaptureShortcutRecipe.steps.enumerated()), id: \.offset) { index, step in
                        stepRow(index + 1, step)
                    }
                    if let shortcuts = URL(string: "shortcuts://create-shortcut") {
                        Link(destination: shortcuts) {
                            SRRow(title: "Open Shortcuts", subtitle: "On a new, empty shortcut", icon: "square.on.square")
                        }
                        .srGlassRow()
                    }
                }
                HStack {
                    TextField("Paste its iCloud link", text: $pastedLink)
                        .font(SR.Text.body())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.done)
                        .onSubmit(keepLink)
                    Button("Keep", action: keepLink)
                        .disabled(pastedLink.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .srGlassRow()
                if linkRefused {
                    Text("That isn't a Shortcuts iCloud link. In Shortcuts, long-press Capture this → Share → Copy iCloud Link.")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.error)
                        .srGlassRow()
                }
                if CaptureShortcutLink.current() != CaptureShortcutLink.published {
                    Button("Forget the pasted link") {
                        CaptureShortcutLink.forget()
                        shortcutLink = CaptureShortcutLink.current()
                    }
                    .font(SR.Text.secondary())
                    .srGlassRow()
                }
            } header: {
                SRSectionLabel(text: CaptureShortcutRecipe.title)
            } footer: {
                Text(CaptureShortcutRecipe.footer).font(SR.Text.secondary(13))
            }

            Section {
                Toggle(isOn: $diarize) {
                    SRRow(title: "Tell voices apart", subtitle: "On this phone. Off: everything is one speaker.", icon: "person.2.wave.2")
                }
                .tint(SR.accent)
                .srGlassRow()
                .onChange(of: diarize) { _, value in CaptureSettings.diarize = value }

                SRRow(title: "Speaker models", subtitle: modelsLine, icon: "cpu") {
                    if models.phase == .downloading { ProgressView() }
                }
                .srGlassRow()

                if models.phase != .ready && models.phase != .downloading {
                    Button {
                        SRHaptic.tap()
                        Task {
                            if await CaptureNetwork.isCostly() && !cellular {
                                askCellular = true
                            } else {
                                await models.download(overCellular: cellular)
                            }
                        }
                    } label: {
                        SRRow(title: "Download now", subtitle: "\(CaptureModelsStore.sizeLine), once", icon: "arrow.down.circle")
                    }
                    .buttonStyle(.plain)
                    .srGlassRow()
                }
                if models.phase == .ready {
                    Button(role: .destructive) {
                        Task { await models.remove() }
                    } label: {
                        SRRow(title: "Remove the models", subtitle: "Captures are one speaker until they are downloaded again", icon: "trash", tone: SR.error)
                    }
                    .buttonStyle(.plain)
                    .srGlassRow()
                }

                Toggle(isOn: $cellular) {
                    SRRow(title: "Download on mobile data", subtitle: "Off: the models wait for Wi-Fi.", icon: "antenna.radiowaves.left.and.right")
                }
                .tint(SR.accent)
                .srGlassRow()
                .onChange(of: cellular) { _, value in CaptureSettings.modelsOnCellular = value }
            } header: {
                SRSectionLabel(text: "Who spoke")
            } footer: {
                Text("The models that tell voices apart are not part of the app. They download from Hugging Face (\(CaptureModelsStore.sizeLine)) the first time a capture is read — on Wi-Fi unless you allow mobile data — and run on this phone. Until then, and if the download fails, a capture is sent as one speaker and the site guesses who spoke from the words.")
                    .font(SR.Text.secondary(13))
            }

            Section {
                SRRow(title: "Your voice", subtitle: voiceLine, icon: "person.wave.2") {
                    if enrolment.phase == .reading { ProgressView() }
                }
                .srGlassRow()
                switch enrolment.phase {
                case .recording(let remaining):
                    Button {
                        Task { await enrolment.cancel() }
                    } label: {
                        SRRow(title: "Recording · \(remaining) s left", subtitle: "Read anything aloud in your normal voice. Tap to cancel.", icon: "stop.circle", tone: SR.error)
                    }
                    .buttonStyle(.plain)
                    .srGlassRow()
                default:
                    Button {
                        SRHaptic.tap()
                        Task {
                            await enrolment.start()
                            enrolledAt = OwnerVoice.madeAt
                        }
                    } label: {
                        SRRow(title: enrolledAt == nil ? "Record 20 seconds" : "Record again", subtitle: "So the phone knows which voice is yours", icon: "mic")
                    }
                    .buttonStyle(.plain)
                    .disabled(enrolment.phase == .reading || CaptureRecorder.shared.recording)
                    .srGlassRow()
                }
                if enrolledAt != nil {
                    Button(role: .destructive) {
                        OwnerVoice.forget()
                        enrolledAt = nil
                    } label: {
                        SRRow(title: "Forget my voice", icon: "trash", tone: SR.error)
                    }
                    .buttonStyle(.plain)
                    .srGlassRow()
                }
            } header: {
                SRSectionLabel(text: "Your voice")
            } footer: {
                Text("Twenty seconds of you talking becomes a voice print kept on this phone only; the recording is deleted straight away. In each capture the voice nearest it is marked as you. Needs the speaker models.")
                    .font(SR.Text.secondary(13))
            }

            Section {
                Toggle(isOn: $sensitive) {
                    SRRow(title: "Keep private screens back", subtitle: "Passwords, codes, card numbers", icon: "lock.shield")
                }
                .tint(SR.accent)
                .srGlassRow()
                .onChange(of: sensitive) { _, value in CaptureSettings.denySensitive = value }
                ForEach(denyList, id: \.self) { name in
                    Text(name).font(SR.Text.body()).foregroundStyle(SR.ink).srGlassRow()
                }
                .onDelete { offsets in
                    denyList.remove(atOffsets: offsets)
                    CaptureSettings.denyList = denyList
                }
                HStack {
                    TextField("Add an app", text: $newName)
                        .font(SR.Text.body())
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .srGlassRow()
                Button("Restore the starting list") {
                    denyList = ScreenshotPolicy.defaultDenyList
                    CaptureSettings.denyList = denyList
                }
                .font(SR.Text.secondary())
                .srGlassRow()
            } header: {
                SRSectionLabel(text: "Screenshots never sent from", trailing: "\(denyList.count)")
            } footer: {
                Text("Matched against the words read off the screenshot on this phone. A match sends neither the picture nor its words — only the app's name — and deletes the picture from the phone. Swipe to remove a name.")
                    .font(SR.Text.secondary(13))
            }

            Section {
                Text("Recording happens only between Start and Stop, and the Lock Screen shows it the whole time. Nothing listens otherwise. Audio goes to your site to be kept with the capture, not into Drive. Tell people when you are recording them.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .srGlassRow()
            } header: {
                SRSectionLabel(text: "Privacy")
            }
        }
        .listStyle(.insetGrouped)
        .srPaper()
        .navigationTitle("Capture settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Use mobile data?", isPresented: $askCellular, titleVisibility: .visible) {
            Button("Download on mobile data") { Task { await models.download(overCellular: true) } }
            Button("Wait for Wi-Fi", role: .cancel) {}
        } message: {
            Text("The speaker models are \(CaptureModelsStore.sizeLine).")
        }
        .onDisappear { Task { await enrolment.cancel() } }
        .accessibilityIdentifier("capture-settings")
    }

    private func stepRow(_ number: Int, _ step: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(SR.Text.label())
                .foregroundStyle(SR.paper)
                .frame(width: 22, height: 22)
                .background(Circle().fill(SR.accent))
                .accessibilityHidden(true)
            Text(step)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .srGlassRow()
    }

    private func keepLink() {
        linkRefused = !CaptureShortcutLink.save(pastedLink)
        guard !linkRefused else { return }
        pastedLink = ""
        shortcutLink = CaptureShortcutLink.current()
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !denyList.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        denyList.append(name)
        CaptureSettings.denyList = denyList
        newName = ""
    }

    private var modelsLine: String {
        switch models.phase {
        case .absent: return "Not downloaded yet. They download the first time a capture is read, on Wi-Fi."
        case .waitingForWiFi: return "Waiting for Wi-Fi to download."
        case .downloading: return "Downloading…"
        case .ready: return "On this phone"
        case .failed(let reason): return "The download failed: \(reason)"
        }
    }

    private var voiceLine: String {
        if case .failed(let reason) = enrolment.phase { return reason }
        if enrolment.phase == .reading { return "Making your voice print…" }
        guard let enrolledAt else { return "Not recorded" }
        return "Recorded \(enrolledAt.formatted(date: .abbreviated, time: .omitted))"
    }
}

/// Twenty seconds of the owner's voice, made into an embedding and thrown
/// away. Uses the microphone only while its own countdown runs.
@MainActor
final class OwnerVoiceEnrolment: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording(Int)
        case reading
        case done
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    private var recorder: AVAudioRecorder?
    private var url: URL?
    private var countdown: Task<Void, Never>?

    func start() async {
        guard recorder == nil, !CaptureRecorder.shared.recording else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            phase = .failed("The microphone is off for SR.")
            return
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("enrol-\(UUID().uuidString).m4a")
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            let made = try AVAudioRecorder(url: file, settings: VoiceRecorder.settings)
            guard made.record(forDuration: OwnerVoice.length) else { throw CaptureRecorder.Failure.unavailable }
            recorder = made
            url = file
        } catch {
            phase = .failed("The microphone wouldn't start.")
            return
        }
        let total = Int(OwnerVoice.length)
        phase = .recording(total)
        countdown = Task { [weak self] in
            for left in stride(from: total - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                self?.phase = .recording(left)
            }
        }
        await countdown?.value
        guard recorder != nil, case .recording = phase else { return }
        await finish()
    }

    private func finish() async {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url else { phase = .idle; return }
        self.url = nil
        phase = .reading
        let embedding = await CaptureDiarization.shared.embedding(url)
        try? FileManager.default.removeItem(at: url)
        guard let embedding else {
            phase = .failed("Couldn't make a voice print. The speaker models need to be downloaded first.")
            return
        }
        do {
            try OwnerVoice.save(embedding)
            phase = .done
        } catch {
            phase = .failed("Couldn't save the voice print.")
        }
    }

    func cancel() async {
        countdown?.cancel()
        countdown = nil
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        self.recorder = nil
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
        phase = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
