import Foundation

/// One Anagram Blitz room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns the
/// word being built from the tiles, the order the tiles sit in (Shuffle moves
/// them; the word keeps its tiles), and what a word costs: nothing. A word the
/// server refuses (400 — wrong letters, too short, not a word) shakes, shows
/// the server's sentence for a moment, and the player carries on.
@MainActor
final class AnagramBlitzStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// The word being built.
    @Published private(set) var input = AnagramInput()
    /// The tiles' on-screen order: indices into the dealt letters.
    @Published private(set) var order: [Int] = []
    /// A word is on its way to the server.
    @Published private(set) var submitting = false
    /// Why the last word was refused, shown under the tiles for a moment.
    @Published private(set) var refusal: String?
    /// The word that just landed, shown for a moment.
    @Published private(set) var landed: AnagramWord?
    /// Bumped on every refusal; the word row shakes when it changes.
    @Published private(set) var shakes = 0

    private let link: GameRoomLink
    private var noteTask: Task<Void, Never>?
    private var lastPhase: GamePhase?
    private var dealt: [String]?

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
        let previous = lastPhase
        lastPhase = next.phase
        // A new deal ("Play again", or the first one): fresh tiles, empty word.
        if next.letters != dealt {
            dealt = next.letters
            input = AnagramInput(tiles: next.letters ?? [])
            order = Array(0..<(next.letters?.count ?? 0))
            clearNotes()
        }
        if next.phase == .playing, previous == .countdown { SRHaptic.tap() }
        room = next
        #if DEBUG
        // Demo mode: a word half built, so the screenshot shows the word row.
        if SRDemo.isOn, next.phase == .playing, previous == nil, input.isEmpty {
            for letter in "pai" { input.add(letter) }
        }
        #endif
    }

    // MARK: - Building a word

    /// True while I can find words: playing, in, tiles dealt.
    var canPlay: Bool {
        guard let room, room.phase == .playing, room.me?.joined == true, let letters = room.letters else { return false }
        return !letters.isEmpty
    }

    /// My words as the server has them.
    var mine: [AnagramWord] { room?.me?.words ?? [] }

    func tap(tile: Int) {
        guard canPlay else { return }
        if input.tap(tile) {
            SRHaptic.tap()
            if refusal != nil { refusal = nil }
        }
    }

    func delete() {
        guard canPlay else { return }
        if input.delete() { SRHaptic.tap() }
    }

    func shuffle() {
        guard canPlay else { return }
        var random = SystemRandomNumberGenerator()
        order = AnagramRules.shuffled(order, using: &random)
        SRHaptic.select()
    }

    /// Enter. The obvious refusals (too short, a word I already have) answer
    /// here; everything else is the server's call.
    func submit() {
        guard canPlay, !submitting, let room else { return }
        let word = input.word
        guard !word.isEmpty else { return }
        if let sentence = AnagramRules.localRefusal(word: word, minLength: room.minLength, mine: mine.map(\.word)) {
            refuse(sentence)
            return
        }
        submitting = true
        // Cleared at once, so the next word can be started while this one flies.
        input.clear()
        Task {
            let outcome = await self.link.post(GameActionBody(action: "word", word: word))
            self.submitting = false
            switch outcome {
            case .ok:
                SRHaptic.ok()
                let scored = self.mine.first { $0.word == word }
                    ?? AnagramWord(word: word, points: AnagramRules.points(for: word, table: self.room?.points ?? [:]))
                self.show(landed: scored)
            case .refused(let sentence):
                self.refuse(sentence)
            case .wrongPhase:
                // A repeat (409) or time's up — the list says which.
                if self.mine.contains(where: { $0.word == word }) {
                    self.refuse("You already have that one.")
                } else {
                    await self.link.refresh()
                }
            case .gone:
                break
            case .failed(let text):
                self.message = text
            }
        }
    }

    private func refuse(_ sentence: String) {
        landed = nil
        refusal = sentence
        shakes += 1
        SRHaptic.bad()
        scheduleClear()
    }

    private func show(landed word: AnagramWord) {
        refusal = nil
        landed = word
        scheduleClear()
    }

    private func scheduleClear() {
        noteTask?.cancel()
        noteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.refusal = nil
            self?.landed = nil
        }
    }

    private func clearNotes() {
        noteTask?.cancel()
        refusal = nil
        landed = nil
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
