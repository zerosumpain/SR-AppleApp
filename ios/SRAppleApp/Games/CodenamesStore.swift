import Foundation

/// One Codenames room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns what
/// this phone is in the middle of — the lobby's pick, a clue being typed and
/// its number, a card lifted before it is turned over — and the moves:
/// `team`, `clue`, `guess` and `pass`. Nothing is played ahead of the server:
/// a move is sent, and the grid changes when the room that answers it (or the
/// stream) arrives.
///
/// A clue is checked here first (`CodenamesRules.clueProblem`, the server's
/// own check) so a word on the board is refused at once; one the server
/// still refuses (400) shows its sentence under the field and costs nothing.
/// A touch that lands after the turn moved on (409: the clock ran out)
/// re-reads the room.
@MainActor
final class CodenamesStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// The clue being typed, and its number.
    @Published private(set) var clueDraft = ""
    @Published private(set) var clueCount = 1
    /// Why the clue was refused — by the check here or by the server. Stays
    /// until the clue is changed.
    @Published private(set) var clueRefusal: String?
    /// The card lifted by a first tap; a second tap (or Turn it over) sends it.
    @Published private(set) var lifted: Int?
    /// Why the last touch or pass was refused, shown for a moment.
    @Published private(set) var refusal: String?
    /// A move is on its way to the server.
    @Published private(set) var sending = false
    /// What the last card turned was, said once (VoiceOver, and under the grid).
    @Published private(set) var revealNote: String?

    private let link: GameRoomLink
    private var noteTask: Task<Void, Never>?
    private var lastPhase: CodenamesPhase?
    private var lastTurns: Int?
    private var lastRevealAt: Double?

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

    func close() { link.close() }

    private func didEnd() {
        ended = true
        noteTask?.cancel()
    }

    private func note(_ note: GameLinkNote) {
        switch note {
        case .reconnecting: message = "Reconnecting…"
        case .reconnected: if message == "Reconnecting…" { message = nil }
        case .error(let text): message = text
        }
    }

    private func apply(_ next: GameRoom) {
        let phase = CodenamesScreenPhase.of(next)
        let previousPhase = lastPhase
        let previousTurns = lastTurns
        let previousReveal = lastRevealAt
        let state = next.codenames
        lastPhase = phase
        lastTurns = state?.turns
        lastRevealAt = state?.last?.at
        room = next
        if phase == .clue, previousPhase == .countdown { SRHaptic.tap() }
        // A new turn: a lifted card and a half-typed clue belong to the last one.
        if state?.turns != previousTurns {
            lifted = nil
            clueRefusal = nil
            if state?.canClue == true, previousPhase != nil { SRHaptic.ok() }
        }
        // The clue is in: the team feels it on every phone that may guess.
        if phase == .guess, previousPhase == .clue, state?.canGuess == true { SRHaptic.select() }
        // A card turned over (anybody's, the TV's, the clock's): feel what it was.
        if let last = state?.last, last.at != previousReveal, previousPhase != nil, phase.inPlay || phase == .finished {
            let word = state?.cards.first { $0.i == last.card }?.word ?? ""
            revealNote = CodenamesRules.revealLine(last, word: word, mode: state?.mode ?? .teams)
            switch CodenamesRules.feel(last, myTeam: state?.myTeam) {
            case .good: SRHaptic.ok()
            case .bad: SRHaptic.bad()
            case .plain: SRHaptic.select()
            }
        }
        // A lifted card that has been turned (by a team-mate), or a turn that is no longer mine to guess.
        if let i = lifted, state?.canGuess != true || state?.cards.first(where: { $0.i == i })?.faceDown != true {
            lifted = nil
        }
        if phase == .finished, previousPhase?.inPlay == true {
            if next.winnerIds.contains(next.meId) { SRHaptic.ok() } else { SRHaptic.select() }
        }
    }

    // MARK: - What the screen reads

    var state: CodenamesState? { room?.codenames }

    var phase: CodenamesPhase? { room.map(CodenamesScreenPhase.of) }

    /// It is this phone's move: a clue to give, or cards to touch.
    var myMove: Bool { (state?.canClue ?? false) || (state?.canGuess ?? false) }

    /// I am in the game (not watching, not gone).
    var seated: Bool { room?.me?.joined == true && state?.myTeam != nil }

    /// What the local check says of the clue as typed — nil while it is fine
    /// (or empty: the field says what to type).
    var draftProblem: String? {
        guard let state, !clueDraft.isEmpty else { return nil }
        return CodenamesRules.clueProblem(clueDraft, faceDown: state.faceDownWords)
    }

    var canSendClue: Bool { state?.canClue == true && !sending && !clueDraft.isEmpty }

    // MARK: - The lobby's pick

    /// A team (nil = anywhere), keeping whether I asked to give clues.
    func pickTeam(_ team: CodenamesTeam?) {
        let spymaster = state?.mySeat?.spymaster ?? false
        send(.pick(team, spymaster: spymaster))
    }

    /// "I'll give the clues", on or off, keeping my team.
    func askToGiveClues(_ on: Bool) {
        send(.pick(state?.myTeam, spymaster: on))
    }

    // MARK: - The clue

    func editClue(_ raw: String) {
        let kept = CodenamesRules.typing(raw)
        if kept != clueDraft { clueDraft = kept }
        clueRefusal = nil
    }

    func stepCount(_ by: Int) {
        let next = CodenamesRules.clampCount(clueCount + by)
        guard next != clueCount else { return }
        clueCount = next
        SRHaptic.select()
    }

    /// Send the clue — unless the server's own check would refuse it, which
    /// says why at once.
    func sendClue() {
        guard let state, state.canClue, !sending else { return }
        if let problem = CodenamesRules.clueProblem(clueDraft, faceDown: state.faceDownWords) {
            clueRefusal = problem
            SRHaptic.bad()
            return
        }
        send(.clue(clueDraft.trimmingCharacters(in: .whitespacesAndNewlines), count: clueCount), clue: true)
    }

    // MARK: - Guessing

    /// A tap on a card: the first lifts it, the second (on the same card) turns it over.
    func tap(_ i: Int) {
        guard let state, state.canGuess, !sending,
              state.cards.first(where: { $0.i == i })?.faceDown == true else { return }
        if lifted == i {
            confirm()
        } else {
            lifted = i
            SRHaptic.select()
            clearNotes()
        }
    }

    /// Turn the lifted card over.
    func confirm() {
        guard let i = lifted, state?.canGuess == true, !sending else { return }
        send(.guess(i))
    }

    /// Put a lifted card down again.
    func putDown() {
        guard lifted != nil else { return }
        lifted = nil
        SRHaptic.select()
    }

    /// End the turn, once a card is turned on this clue.
    func pass() {
        guard state?.canPass == true, !sending else { return }
        send(.pass)
    }

    // MARK: - Sending

    private func send(_ move: CodenamesMove, clue: Bool = false) {
        sending = true
        SRHaptic.tap()
        Task {
            let outcome = await self.link.post(move)
            self.sending = false
            switch outcome {
            case .ok:
                if clue {
                    self.clueDraft = ""
                    self.clueCount = 1
                    self.clueRefusal = nil
                }
                self.lifted = nil
                self.clearNotes()
            case .refused(let sentence):
                if clue {
                    self.clueRefusal = sentence
                    SRHaptic.bad()
                } else {
                    self.refuse(sentence)
                }
            case .wrongPhase:
                self.lifted = nil
                await self.link.refresh()
            case .gone:
                break
            case .failed(let text):
                if clue { self.clueRefusal = text } else { self.message = text }
            }
        }
    }

    private func refuse(_ sentence: String) {
        refusal = sentence
        SRHaptic.bad()
        noteTask?.cancel()
        noteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.refusal = nil
        }
    }

    private func clearNotes() {
        noteTask?.cancel()
        refusal = nil
    }

    // MARK: - Actions

    /// join | leave | start | again.
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

/// Which of the screen's pages a room is on: Codenames' own phase when the
/// room carries it (`clue` and `guess` are its alone), else the shared phase.
enum CodenamesScreenPhase {
    static func of(_ room: GameRoom) -> CodenamesPhase {
        if let phase = room.codenames?.phase, phase != .unknown { return phase }
        switch room.phase {
        case .lobby: return .lobby
        case .countdown: return .countdown
        case .finished: return .finished
        case .closed: return .closed
        default: return .unknown
        }
    }
}
