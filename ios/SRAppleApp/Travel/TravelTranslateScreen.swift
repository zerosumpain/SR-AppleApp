import SwiftUI

/// Live translation, two ways.
///
/// **Conversation** — two big buttons, one per person. Tap yours, speak, and
/// the words are translated as you say them; at the pause the translation is
/// said aloud in the other language and the mic hands back. **Live captions**
/// — the phone listens on and on (a guide, an announcement, a waiter reading
/// the specials) and each sentence lands translated as it ends, with the one
/// in progress translating live underneath.
///
/// Speech and translation both run on the phone once the language is
/// downloaded, so it works on a plane, in the Colosseum's basement or with
/// roaming off.
struct TravelTranslateScreen: View {
    @StateObject private var bridge = TravelTranslationBridge()
    @StateObject private var listener = TravelListener()
    @ObservedObject private var voice = TravelVoice.shared
    @State private var mode: Mode = .conversation
    @State private var lines: [Line] = []
    /// Who is speaking now: `.out` is me in English, `.back` is them.
    @State private var speaker: TravelDirection = .out
    @State private var liveTranslation = ""
    @State private var translating = false
    @State private var speakAloud = true
    @State private var showing: TravelShowCard?

    enum Mode: String, CaseIterable, Identifiable {
        case conversation = "Conversation"
        case captions = "Live captions"
        var id: String { rawValue }
    }

    struct Line: Identifiable, Hashable {
        let id = UUID()
        let heard: String
        var translated: String?
        let direction: TravelDirection
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Mode", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("travel-translate-mode")
                        languageRow
                        TravelTranslatorNote(bridge: bridge)
                        if let problem = listener.problem {
                            Text(problem)
                                .font(SR.Text.secondary(14))
                                .foregroundStyle(SR.error)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if lines.isEmpty && !listener.listening { empty }
                        ForEach(lines) { line in
                            bubble(line).id(line.id)
                        }
                        if listener.listening && !listener.partial.isEmpty {
                            liveBubble.id("live")
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, SR.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .onChange(of: lines.count) { _, _ in withAnimation { reader.scrollTo("end") } }
                .onChange(of: listener.partial) { _, _ in reader.scrollTo("end") }
            }
            controls
        }
        .background(TravelTranslationHost(bridge: bridge))
        .srGround(.warm)
        .navigationTitle("Live translate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !lines.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { lines.removeAll() }
                        .disabled(listener.listening)
                }
            }
        }
        .sheet(item: $showing) { TravelShowSheet(card: $0) }
        .onAppear(perform: wire)
        .onDisappear {
            listener.stop()
            voice.stop()
        }
        .onChange(of: mode) { _, _ in listener.stop() }
        .accessibilityIdentifier("travel-translate")
    }

    // MARK: - Pieces

    private var languageRow: some View {
        HStack {
            Text("English ⇄")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.inkSecondary)
            Picker("Their language", selection: $bridge.language) {
                ForEach(TravelLanguage.theirs) { Text($0.name).tag($0) }
            }
            .pickerStyle(.menu)
            .disabled(listener.listening)
            Spacer()
            if mode == .conversation {
                Toggle(isOn: $speakAloud) {
                    Image(systemName: speakAloud ? "speaker.wave.2.fill" : "speaker.slash")
                        .foregroundStyle(SR.accent)
                }
                .toggleStyle(.button)
                .accessibilityLabel("Say translations aloud")
            }
        }
    }

    private var empty: some View {
        SRCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(mode == .conversation ? "Talk to someone" : "Listen to Rome")
                    .font(SR.Text.title(17))
                    .foregroundStyle(SR.ink)
                Text(mode == .conversation
                     ? "Tap your button and speak. The translation appears as you talk and is said aloud in \(bridge.language.name) when you pause. Then they tap theirs."
                     : "Point the phone at whoever is talking — a guide, a tannoy, the waiter's specials. Each sentence appears in English as it ends.")
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bubble(_ line: Line) -> some View {
        let mine = line.direction == .out
        return VStack(alignment: .leading, spacing: 6) {
            Text(line.heard)
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkSecondary)
                .textSelection(.enabled)
            Text(line.translated ?? (TravelTranslationBridge.supported ? "…" : "—"))
                .font(SR.Text.title(19))
                .foregroundStyle(SR.ink)
                .textSelection(.enabled)
            if let translated = line.translated {
                HStack(spacing: 16) {
                    Button {
                        voice.say(translated, in: mine ? bridge.language.speech : TravelLanguage.english.speech)
                    } label: { Label("Say", systemImage: "speaker.wave.2") }
                    if mine {
                        Button {
                            showing = TravelShowCard(big: translated, small: line.heard, speech: bridge.language.speech)
                        } label: { Label("Show", systemImage: "rectangle.expand.vertical") }
                    }
                }
                .font(SR.Text.label(13))
                .foregroundStyle(SR.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(mine ? SR.accent.opacity(0.12) : SR.surface))
        .padding(mine ? .leading : .trailing, 28)
        .accessibilityElement(children: .combine)
    }

    private var liveBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(SR.error).frame(width: 8, height: 8)
                Text("LISTENING").font(SR.Text.label(11)).foregroundStyle(SR.inkMuted)
            }
            .accessibilityHidden(true)
            Text(listener.partial)
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkSecondary)
            if !liveTranslation.isEmpty {
                Text(liveTranslation)
                    .font(SR.Text.title(19))
                    .foregroundStyle(SR.ink.opacity(0.75))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(SR.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .accessibilityIdentifier("travel-live-line")
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            switch mode {
            case .conversation:
                talkButton(.out, title: "I speak", subtitle: "English")
                talkButton(.back, title: "Parla", subtitle: bridge.language.native)
            case .captions:
                Button {
                    SRHaptic.tap()
                    if listener.listening { listener.stop() } else { listen(.back) }
                } label: {
                    Label(listener.listening ? "Stop listening" : "Listen in \(bridge.language.name)",
                          systemImage: listener.listening ? "stop.fill" : "ear")
                        .font(SR.Text.title(17))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .srButton(.prominent)
                .accessibilityIdentifier("travel-captions-toggle")
            }
        }
        .padding(.horizontal, SR.gutter)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func talkButton(_ direction: TravelDirection, title: String, subtitle: String) -> some View {
        let live = listener.listening && speaker == direction
        return Button {
            SRHaptic.tap()
            if live { listener.stop() } else { listen(direction) }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: live ? "stop.fill" : "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                Text(live ? "Done" : title).font(SR.Text.title(16))
                Text(subtitle).font(SR.Text.label(11)).opacity(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
        }
        .srButton(live || direction == .out ? .prominent : .regular)
        .disabled(listener.listening && !live)
        .accessibilityIdentifier(direction == .out ? "travel-talk-mine" : "travel-talk-theirs")
    }

    // MARK: - Behaviour

    private func wire() {
        listener.onPartial = { text in livePartial(text) }
        listener.onSegment = { text in finished(text) }
    }

    private func listen(_ direction: TravelDirection) {
        voice.stop()
        speaker = direction
        liveTranslation = ""
        listener.continuous = mode == .captions
        listener.pause = mode == .captions ? 1.1 : 1.6
        let speech = direction == .out ? TravelLanguage.english.speech : bridge.language.speech
        Task { await listener.start(speech) }
    }

    /// The sentence in progress, translated as it grows. One translation in
    /// flight at a time; when it lands, the latest words go next — so a fast
    /// speaker is never more than one translation behind.
    private func livePartial(_ text: String) {
        guard !translating else { return }
        translating = true
        let direction = speaker
        Task {
            var sent = text
            while true {
                let answer = await bridge.translate(sent, direction)
                guard listener.listening else { break }
                if let answer { liveTranslation = answer }
                if listener.partial == sent || listener.partial.isEmpty { break }
                sent = listener.partial
            }
            translating = false
        }
    }

    private func finished(_ text: String) {
        let direction = speaker
        let line = Line(heard: text, translated: nil, direction: direction)
        lines.append(line)
        liveTranslation = ""
        let id = line.id
        Task {
            let answer = await bridge.translate(text, direction)
            guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
            lines[index].translated = answer
            if let answer, mode == .conversation, speakAloud {
                voice.say(answer, in: direction == .out ? bridge.language.speech : TravelLanguage.english.speech)
            }
        }
    }
}
