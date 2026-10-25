import SwiftUI
import AVFoundation
// Weak-linked (app.yml): it exists from iOS 18, and every use is behind
// `#available`.
import Translation

/// A language the Travel kit can listen to, translate and speak.
///
/// Italian first: the kit was built the day before Newcastle → Rome
/// (2026-10-26). The others are there for the next trip, not decoration —
/// every one has an on-device recogniser, a Translation model and a voice.
struct TravelLanguage: Hashable, Identifiable {
    let id: String
    /// "Italian", in English.
    let name: String
    /// "Italiano", in itself: the button the other person reads.
    let native: String
    /// For `SFSpeechRecognizer` and the speaking voice.
    let speech: String
    /// For Translation, which wants the language without the region.
    let translation: String

    static let english = TravelLanguage(id: "en", name: "English", native: "English", speech: "en-GB", translation: "en")
    static let italian = TravelLanguage(id: "it", name: "Italian", native: "Italiano", speech: "it-IT", translation: "it")
    static let spanish = TravelLanguage(id: "es", name: "Spanish", native: "Español", speech: "es-ES", translation: "es")
    static let french = TravelLanguage(id: "fr", name: "French", native: "Français", speech: "fr-FR", translation: "fr")
    static let german = TravelLanguage(id: "de", name: "German", native: "Deutsch", speech: "de-DE", translation: "de")
    static let portuguese = TravelLanguage(id: "pt", name: "Portuguese", native: "Português", speech: "pt-PT", translation: "pt")

    /// What the other person might speak. English is always "mine".
    static let theirs: [TravelLanguage] = [italian, spanish, french, german, portuguese]

    static func find(_ id: String) -> TravelLanguage { theirs.first { $0.id == id } ?? italian }
}

/// Which way a sentence goes.
enum TravelDirection: Hashable {
    /// English → their language.
    case out
    /// Their language → English.
    case back
}

/// Translation on the phone, offered to plain async code.
///
/// Apple's `TranslationSession` only exists inside a view's `.translationTask`
/// closure and must not escape it, so a view (`TravelTranslationHost`) keeps
/// one closure per direction alive and feeds it from a queue: `translate`
/// enqueues and awaits. Each screen owns its own bridge and host — two hosts
/// on one bridge would fight over the queue.
///
/// Before iOS 18 there is no Translation framework: every call answers nil and
/// `supported` is false, and the screens say so rather than pretend.
@MainActor
final class TravelTranslationBridge: ObservableObject {
    @Published var language: TravelLanguage {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.id, forKey: Self.languageKey)
            Task { await refreshInstalled() }
        }
    }
    /// The offline models for both directions are on the phone.
    @Published private(set) var installed = false
    /// The system download sheet is up, or a download is running.
    @Published private(set) var preparing = false
    /// Bumped to ask the host to show the download sheet.
    @Published fileprivate(set) var prepareTick = 0

    static let languageKey = "travel.language"

    struct Job {
        let id: UUID
        let text: String
    }

    /// One live session per direction, with a token naming it.
    fileprivate var queues: [TravelDirection: (token: UUID, queue: AsyncStream<Job>.Continuation)] = [:]
    /// Every caller still waiting, so a session that is cancelled mid-queue
    /// (the language changed, the screen went) answers them nil rather than
    /// leaving them awaiting for ever.
    private var waiting: [UUID: (session: UUID, reply: CheckedContinuation<String?, Never>)] = [:]

    init() {
        language = TravelLanguage.find(UserDefaults.standard.string(forKey: Self.languageKey) ?? "it")
    }

    static var supported: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }

    /// The translation, or nil: no framework, no model and no network to
    /// fetch one, or the host was not on screen in time.
    func translate(_ text: String, _ direction: TravelDirection) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.supported, !trimmed.isEmpty else { return nil }
        // The host registers on its first appearance; a call made in the
        // same breath as the screen opening waits for it, briefly.
        for _ in 0..<30 where queues[direction] == nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let live = queues[direction] else { return nil }
        let id = UUID()
        return await withCheckedContinuation { reply in
            waiting[id] = (live.token, reply)
            if case .terminated = live.queue.yield(Job(id: id, text: trimmed)) {
                answer(id, nil)
            }
        }
    }

    fileprivate func answer(_ id: UUID, _ text: String?) {
        waiting.removeValue(forKey: id)?.reply.resume(returning: text)
    }

    /// A session ended: whatever it had not answered gets nil.
    fileprivate func ended(_ direction: TravelDirection, session token: UUID) {
        for (id, entry) in waiting where entry.session == token { answer(id, nil) }
        if queues[direction]?.token == token { queues[direction] = nil }
    }

    /// Ask for the offline models: iOS shows its own download sheet.
    func prepare() {
        guard Self.supported else { return }
        preparing = true
        prepareTick += 1
    }

    fileprivate func prepared() {
        preparing = false
        Task { await refreshInstalled() }
    }

    func refreshInstalled() async {
        if #available(iOS 18.0, *) {
            let availability = LanguageAvailability()
            let mine = Locale.Language(identifier: TravelLanguage.english.translation)
            let theirs = Locale.Language(identifier: language.translation)
            let out = await availability.status(from: mine, to: theirs)
            let back = await availability.status(from: theirs, to: mine)
            installed = out == .installed && back == .installed
            return
        }
        installed = false
    }
}

/// The invisible view that holds the two translation sessions. Put it in a
/// screen's `.background`; it draws nothing.
struct TravelTranslationHost: View {
    @ObservedObject var bridge: TravelTranslationBridge

    var body: some View {
        if #available(iOS 18.0, *) {
            TravelTranslationSessions(bridge: bridge)
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

@available(iOS 18.0, *)
private struct TravelTranslationSessions: View {
    @ObservedObject var bridge: TravelTranslationBridge
    @State private var out: TranslationSession.Configuration?
    @State private var back: TranslationSession.Configuration?
    @State private var download: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .translationTask(out) { session in await serve(session, .out) }
            .translationTask(back) { session in await serve(session, .back) }
            // Its own session, so asking for the download never stalls the
            // queues: `prepareTranslation` shows the sheet for both
            // directions' models, which are the same pair.
            .translationTask(download) { session in await prepare(session) }
            .onAppear(perform: configure)
            .onChange(of: bridge.language) { _, _ in configure() }
            .onChange(of: bridge.prepareTick) { _, _ in
                let pair = languages
                if download == nil {
                    download = .init(source: pair.mine, target: pair.theirs)
                } else {
                    download?.invalidate()
                }
            }
            .task { await bridge.refreshInstalled() }
    }

    private var languages: (mine: Locale.Language, theirs: Locale.Language) {
        (Locale.Language(identifier: TravelLanguage.english.translation),
         Locale.Language(identifier: bridge.language.translation))
    }

    private func configure() {
        let pair = languages
        // A new configuration replaces the old session; the old closure is
        // cancelled and its queue ends with it.
        out = .init(source: pair.mine, target: pair.theirs)
        back = .init(source: pair.theirs, target: pair.mine)
        download = nil
    }

    private func serve(_ session: TranslationSession, _ direction: TravelDirection) async {
        let (stream, queue) = AsyncStream<TravelTranslationBridge.Job>.makeStream()
        let token = UUID()
        bridge.queues[direction]?.queue.finish()
        bridge.queues[direction] = (token, queue)
        for await job in stream {
            let answer = try? await session.translate(job.text)
            bridge.answer(job.id, answer?.targetText)
        }
        // Cancelled (new language, screen gone) or replaced: anything still
        // queued is answered, not dropped — its caller is awaiting.
        bridge.ended(direction, session: token)
    }

    private func prepare(_ session: TranslationSession) async {
        do { try await session.prepareTranslation() } catch {}
        bridge.prepared()
    }
}

/// Speaks a line aloud in a language's own voice. One for the whole kit, so a
/// new line cuts off the last rather than talking over it.
@MainActor
final class TravelVoice: NSObject, ObservableObject, @preconcurrency AVSpeechSynthesizerDelegate {
    static let shared = TravelVoice()
    @Published private(set) var speaking = false
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ text: String, in speech: String, slow: Bool = false) {
        guard !text.isEmpty else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let session = AVAudioSession.sharedInstance()
        // Recording leaves the session in a quiet, earpiece-leaning state;
        // a line meant for the person opposite comes out of the speaker.
        if session.category != .playAndRecord {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        }
        try? session.setActive(true)
        let line = AVSpeechUtterance(string: text)
        line.voice = AVSpeechSynthesisVoice(language: speech)
        line.rate = slow ? AVSpeechUtteranceDefaultSpeechRate * 0.8 : AVSpeechUtteranceDefaultSpeechRate
        speaking = true
        synth.speak(line)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        speaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speaking = synth.isSpeaking
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        speaking = synth.isSpeaking
    }
}

/// "Show them": one line, as big as the screen allows, for holding up to a
/// waiter, a driver or a ticket desk.
struct TravelShowCard: Identifiable, Hashable {
    let id = UUID()
    let big: String
    var small: String? = nil
    var speech: String? = nil
}

struct TravelShowSheet: View {
    let card: TravelShowCard
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var voice = TravelVoice.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            Text(card.big)
                .font(SR.Text.hero(44))
                .foregroundStyle(SR.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.3)
                .textSelection(.enabled)
                .accessibilityIdentifier("travel-show-big")
            if let small = card.small {
                Text(small)
                    .font(SR.Text.body(17))
                    .foregroundStyle(SR.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                if let speech = card.speech {
                    SRButton(title: voice.speaking ? "Stop" : "Say it") {
                        if voice.speaking { voice.stop() } else { voice.say(card.big, in: speech, slow: true) }
                    }
                }
                SRButton(title: "Done", filled: true) { dismiss() }
            }
        }
        .padding(SR.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srGround(.warm)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

/// The note every translating screen shows when it cannot translate.
struct TravelTranslatorNote: View {
    @ObservedObject var bridge: TravelTranslationBridge

    var body: some View {
        if !TravelTranslationBridge.supported {
            note("Translation runs on the phone and needs iOS 18 or later. Update in Settings → General → Software Update.", tone: SR.warn)
        } else if !bridge.installed {
            Button {
                SRHaptic.tap()
                bridge.prepare()
            } label: {
                note(bridge.preparing
                     ? "Downloading \(bridge.language.name)…"
                     : "Download \(bridge.language.name) to translate with no signal — do it on Wi-Fi before you fly. Tap here.",
                     tone: SR.accent)
            }
            .buttonStyle(.plain)
            .disabled(bridge.preparing)
            .accessibilityIdentifier("travel-download-language")
        }
    }

    private func note(_ text: String, tone: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(tone)
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tone.opacity(0.12)))
    }
}
