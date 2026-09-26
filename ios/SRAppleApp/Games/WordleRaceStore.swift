import Foundation

/// One Wordle Race room, live.
///
/// The connection is `GameRoomLink`, the same as Tap Duel's. This owns the row
/// being typed and what a guess costs: a guess the server refuses (400 — not a
/// word, a hard-mode breach) costs nothing, so the row stays, shakes, and the
/// server's sentence is shown for a few seconds.
@MainActor
final class WordleRaceStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// The row being typed.
    @Published private(set) var input = WordleInput()
    /// A guess is on its way to the server.
    @Published private(set) var submitting = false
    /// Why the last guess was refused, shown under the grid for a moment.
    @Published private(set) var refusal: String?
    /// Bumped on every refusal; the typing row shakes when it changes.
    @Published private(set) var shakes = 0

    private let link: GameRoomLink
    private var refusalTask: Task<Void, Never>?
    private var lastPhase: GamePhase?

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
        refusalTask?.cancel()
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
        lastPhase = next.phase
        if input.length != next.wordLength {
            input = WordleInput(length: next.wordLength)
        }
        // A new game in the same room ("Play again") starts with a clean row.
        if next.phase != .playing, previous == .playing || previous == .finished {
            input.clear()
            clearRefusal()
        }
        if next.phase == .playing, previous == .countdown { SRHaptic.tap() }
        room = next
        #if DEBUG
        // Demo mode: a fourth guess half typed, so the screenshot shows the
        // typing row as well as the scored ones.
        if SRDemo.isOn, next.phase == .playing, previous == nil, input.isEmpty {
            for letter in "gr" { input.add(letter) }
        }
        #endif
    }

    // MARK: - Typing

    /// True while my row can take letters: playing, in, not solved, not out.
    var canType: Bool {
        guard let room, room.phase == .playing, let me = room.me, me.joined else { return false }
        return !me.done && !me.solved && me.guessCount < room.maxGuesses
    }

    func press(_ letter: Character) {
        guard canType, !submitting else { return }
        if input.add(letter) {
            SRHaptic.tap()
            if refusal != nil { clearRefusal() }
        }
    }

    func delete() {
        guard canType, !submitting else { return }
        if input.delete() { SRHaptic.tap() }
    }

    /// Enter. A short row never reaches the server.
    func submit() {
        guard canType, !submitting else { return }
        guard input.isComplete else {
            refuse("Not enough letters.")
            return
        }
        let word = input.word
        submitting = true
        Task {
            let outcome = await self.link.post(GameActionBody(action: "guess", word: word))
            self.submitting = false
            switch outcome {
            case .ok:
                // The answering room already holds the row.
                self.input.clear()
                self.clearRefusal()
                if self.room?.me?.solved == true { SRHaptic.ok() } else { SRHaptic.select() }
            case .refused(let sentence):
                self.refuse(sentence)
            case .wrongPhase:
                // Solved, out of guesses, or out of time — the stream says which.
                self.input.clear()
                await self.link.refresh()
            case .gone:
                break
            case .failed(let text):
                self.message = text
            }
        }
    }

    private func refuse(_ sentence: String) {
        refusal = sentence
        shakes += 1
        SRHaptic.bad()
        refusalTask?.cancel()
        refusalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.refusal = nil
        }
    }

    private func clearRefusal() {
        refusalTask?.cancel()
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
