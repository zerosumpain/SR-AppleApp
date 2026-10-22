import Foundation

/// One One Clue room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns my
/// clue as I type it — sent a moment after the typing stops (or at once on
/// Return), so the server holds nearly what the screen shows and the clock
/// running out loses at most the last letter — my vetoes on their way, my
/// "done", and the guesser's guess or pass. The server checks every clue; the
/// field only warns.
@MainActor
final class OneClueStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// My clue as typed.
    @Published private(set) var draft = ""
    /// The guesser's guess as typed.
    @Published var guessDraft = ""
    /// A guess or pass is on its way.
    @Published private(set) var guessing = false

    private let link: GameRoomLink
    private var lastPhase: OneCluePhase?
    /// The card the draft belongs to; a new card clears it.
    private var card: Int?
    /// What the server last took.
    private var sent = ""
    private var pending: Task<Void, Never>?
    /// Vetoes on their way, so a double tap sends one.
    private var vetoing: Set<String> = []

    /// How long after the last keystroke a clue is sent.
    static let settleNanoseconds: UInt64 = 600_000_000

    init(roomId: String) {
        self.roomId = roomId
        self.link = GameRoomLink(roomId: roomId)
        link.onRoom = { [weak self] room in self?.apply(room) }
        link.onEnd = { [weak self] in self?.didEnd() }
        link.onNote = { [weak self] update in self?.note(update) }
    }

    /// The server's clock, now, as well as this phone can tell.
    func serverNow() -> Double? { link.serverNow() }

    // MARK: - Connection

    func open() { link.open() }

    func close() {
        flush()
        link.close()
    }

    private func didEnd() {
        ended = true
        pending?.cancel()
        pending = nil
    }

    private func note(_ note: GameLinkNote) {
        switch note {
        case .reconnecting: message = "Reconnecting…"
        case .reconnected: if message == "Reconnecting…" { message = nil }
        case .error(let text): message = text
        }
    }

    private func apply(_ next: GameRoom) {
        let previous = lastPhase
        let phase = OneClueRules.phase(next)
        lastPhase = phase
        let state = next.oneClue
        // A new card: the draft is the server's — empty, or what it kept if
        // this phone is rejoining mid-card.
        if state?.cardIndex != card || (phase == .clues && previous != .clues && previous != nil) {
            card = state?.cardIndex
            pending?.cancel()
            pending = nil
            draft = state?.myClue ?? ""
            sent = draft
            guessDraft = ""
            vetoing = []
        }
        if phase == .clues, previous != .clues, previous != nil { SRHaptic.tap() }
        if phase == .guess, previous != .guess, state?.role == .guesser { SRHaptic.ok() }
        if phase == .reveal, previous != .reveal, previous != nil {
            if state?.outcome == .correct { SRHaptic.ok() } else { SRHaptic.bad() }
        }
        room = next
        #if DEBUG
        // Demo mode: a half-typed clue, so the screenshot shows the field in use.
        if SRDemo.isShowcase, phase == .clues, previous == nil, state?.role == .clue, draft.isEmpty {
            draft = "Orchard"
        }
        #endif
    }

    // MARK: - Reading the room

    var state: OneClueState? { room?.oneClue }
    var phase: OneCluePhase { room.map(OneClueRules.phase) ?? .unknown }
    var amGuesser: Bool { state?.role == .guesser && room?.me?.joined == true }
    var amGiver: Bool { state?.role == .clue && room?.me?.joined == true }

    /// True while I can write a clue.
    var canClue: Bool { phase == .clues && amGiver }

    /// True while I can guess.
    var canGuess: Bool { phase == .guess && amGuesser && !guessing }

    /// The warning under my field.
    var warning: String? { OneClueRules.warning(draft, word: state?.word) }

    // MARK: - Writing a clue

    /// A keystroke in the clue field. Sent once the typing settles.
    func edit(_ text: String) {
        guard canClue, let state else { return }
        let capped = OneClueRules.cap(text, max: state.maxClue)
        guard draft != capped else { return }
        draft = capped
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.settleNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.send()
        }
    }

    /// Return, or leaving the field: send now.
    func commit() {
        pending?.cancel()
        pending = nil
        Task { await self.send() }
    }

    /// A clue not yet sent, now — the screen is going.
    func flush() {
        if pending != nil { commit() }
    }

    private func send() async {
        pending = nil
        guard canClue else { return }
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard sent != text else { return }
        sent = text
        switch await link.post(GameActionBody(action: "clue", text: text)) {
        case .ok, .gone:
            break
        case .wrongPhase:
            // Time's up, or the last clue in opened the review: the stream says.
            sent = ""
            await link.refresh()
        case .refused(let sentence), .failed(let sentence):
            sent = ""
            message = sentence
        }
    }

    // MARK: - The review

    /// Tap somebody else's clue: veto it, or take my veto back.
    func toggleVeto(_ clue: OneClueClue) {
        guard let room, OneClueRules.canVeto(clue, room: room) else { return }
        guard !vetoing.contains(clue.playerId) else { return }
        vetoing.insert(clue.playerId)
        SRHaptic.select()
        let action = clue.vetoed ? "unveto" : "veto"
        Task {
            let outcome = await self.link.post(GameActionBody(action: action, playerId: clue.playerId))
            self.vetoing.remove(clue.playerId)
            switch outcome {
            case .ok, .gone:
                break
            case .wrongPhase:
                await self.link.refresh()
            case .refused(let text), .failed(let text):
                self.message = text
            }
        }
    }

    /// Review: seen enough. Reveal: ready for the next card.
    func ready() {
        guard let room, let seat = state?.seat(room.meId), !seat.done else { return }
        SRHaptic.tap()
        Task { _ = await self.act("done") }
    }

    var meDone: Bool {
        guard let room else { return false }
        return state?.seat(room.meId)?.done == true
    }

    // MARK: - Guessing

    func submitGuess() {
        let text = guessDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canGuess, !text.isEmpty else { return }
        guessing = true
        SRHaptic.tap()
        Task {
            await self.guessAction(GameActionBody(action: "guess", text: text))
        }
    }

    func pass() {
        guard canGuess else { return }
        guessing = true
        SRHaptic.select()
        Task { await self.guessAction(GameActionBody(action: "pass")) }
    }

    private func guessAction(_ body: GameActionBody) async {
        let outcome = await link.post(body)
        guessing = false
        switch outcome {
        case .ok, .gone:
            break
        case .wrongPhase:
            await link.refresh()
        case .refused(let text), .failed(let text):
            message = text
        }
    }

    // MARK: - Actions

    /// join | leave | start | again | done.
    @discardableResult
    func act(_ action: String) async -> Bool {
        busy = true
        defer { busy = false }
        switch await link.post(GameActionBody(action: action)) {
        case .ok:
            return true
        case .gone, .wrongPhase:
            return false
        case .refused(let text), .failed(let text):
            message = text
            return false
        }
    }
}
