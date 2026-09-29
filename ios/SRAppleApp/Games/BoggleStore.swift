import Foundation

/// One Boggle room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns the
/// trace being drawn on the grid, and what a word costs: nothing. A word the
/// server refuses (400 — too short, not on the board, not a word) shakes,
/// shows the server's sentence for a moment, and the player carries on. At the
/// finish it owns which word's path is lit on the board.
@MainActor
final class BoggleStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// The tiles being traced.
    @Published private(set) var trace = BoggleTrace(size: 4)
    /// Why the last word was refused, shown under the grid for a moment.
    @Published private(set) var refusal: String?
    /// The word that just landed, shown for a moment.
    @Published private(set) var landed: BoggleWord?
    /// Bumped on every refusal; the word row shakes when it changes.
    @Published private(set) var shakes = 0
    /// Finished: the word whose path is lit on the board.
    @Published var highlighted: String?
    /// Quarter turns the board is drawn at. The trace and the server never
    /// see it: a tile keeps its index wherever it is drawn.
    @Published private(set) var turns = 0

    private let link: GameRoomLink
    private var noteTask: Task<Void, Never>?
    private var lastPhase: GamePhase?
    private var dealt: [String]?
    /// Words sent and not yet answered, so a double release sends one.
    private var inFlight: Set<String> = []

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
        // A new roll ("Play again", or the first one): an empty trace.
        if next.grid != dealt {
            dealt = next.grid
            trace = BoggleTrace(size: next.size)
            turns = 0
            highlighted = nil
            clearNotes()
        }
        if next.phase == .playing, previous == .countdown { SRHaptic.tap() }
        if next.phase == .finished, previous == .playing { trace.clear() }
        room = next
        #if DEBUG
        // Demo mode: a word half traced, so the screenshot shows the line.
        if SRDemo.isShowcase, next.phase == .playing, previous == nil, trace.isEmpty {
            for tile in [5, 6, 10] { trace.drag(to: tile) }
        }
        if SRDemo.isShowcase, next.phase == .finished, previous == nil {
            highlighted = next.boggleMissed?.first?.word
        }
        #endif
    }

    // MARK: - Tracing a word

    /// True while I can find words: playing, in, grid rolled.
    var canPlay: Bool {
        guard let room, room.phase == .playing, room.me?.joined == true, let grid = room.grid else { return false }
        return grid.count == room.size * room.size
    }

    /// My words as the server has them.
    var mine: [BoggleWord] { room?.me?.boggleWords ?? [] }

    /// The word the trace spells so far.
    var word: String { BoggleRules.word(trace.path, grid: room?.grid ?? []) }

    /// A finger entering a tile mid-drag.
    func drag(to tile: Int) {
        guard canPlay else { return }
        if trace.drag(to: tile) {
            SRHaptic.select()
            if refusal != nil { refusal = nil }
        }
    }

    /// A tap on a tile — the one-at-a-time path, and VoiceOver's.
    func tap(tile: Int) {
        guard canPlay else { return }
        if trace.tap(tile) {
            SRHaptic.tap()
            if refusal != nil { refusal = nil }
        }
    }

    func delete() {
        guard canPlay else { return }
        if trace.delete() { SRHaptic.tap() }
    }

    /// Turn the board a quarter clockwise, for a fresh look at the same dice.
    func rotate() {
        guard room?.grid != nil else { return }
        turns = (turns + 1) % 4
        SRHaptic.select()
    }

    func clearTrace() {
        guard !trace.isEmpty else { return }
        trace.clear()
    }

    /// The finger lifts, or Enter. A single tile is a slip, not a word: it is
    /// dropped quietly. The obvious refusals answer here; everything else is
    /// the server's call.
    func submit() {
        guard canPlay, let room else { return }
        let path = trace.path
        let word = BoggleRules.word(path, grid: room.grid ?? [])
        guard path.count > 1, !word.isEmpty else {
            trace.clear()
            return
        }
        trace.clear()
        if let sentence = BoggleRules.localRefusal(word: word, minLength: room.minLength, mine: mine.map(\.word)) {
            refuse(sentence)
            return
        }
        guard !inFlight.contains(word) else { return }
        inFlight.insert(word)
        Task {
            let outcome = await self.link.post(GameActionBody(action: "word", word: word, path: path))
            self.inFlight.remove(word)
            switch outcome {
            case .ok:
                SRHaptic.ok()
                let scored = self.mine.first { $0.word == word }
                    ?? BoggleWord(word: word, points: BoggleRules.points(for: word, table: self.room?.points ?? [:]), path: path)
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

    private func show(landed word: BoggleWord) {
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

    // MARK: - The reveal

    /// Light a word's path on the board, or put it out when it is already lit.
    func highlight(_ word: String) {
        SRHaptic.select()
        highlighted = highlighted == word ? nil : word
    }

    /// The lit word's tiles, in order.
    var highlightedPath: [Int] {
        guard let word = highlighted, let room else { return [] }
        if let found = room.boggleFound?.first(where: { $0.word == word }) { return found.path }
        if let missed = room.boggleMissed?.first(where: { $0.word == word }) { return missed.path }
        return room.me?.boggleWords?.first { $0.word == word }?.path ?? []
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
