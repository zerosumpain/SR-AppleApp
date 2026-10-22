import Foundation

/// One Fireworks room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns the
/// two things a turn is built from — one of my cards picked (to play or drop),
/// or another player and a hint for them — and the three moves. A move the
/// server refuses (400) shows its sentence for a moment and costs nothing; one
/// that lands after the turn moved on (409: a clock ran out) re-reads the room.
@MainActor
final class FireworksStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// One of my own cards, picked to play or drop.
    @Published private(set) var pickedCard: Int?
    /// Whose hand a hint is being put together for.
    @Published private(set) var hintTarget: String?
    /// The hint picked for them, previewed on their hand before it is sent.
    @Published private(set) var hint: FireworksHint?
    /// Why the last move was refused, shown for a moment.
    @Published private(set) var refusal: String?
    /// A move is on its way to the server.
    @Published private(set) var sending = false

    private let link: GameRoomLink
    private var noteTask: Task<Void, Never>?
    private var lastPhase: FireworksPhase?
    private var lastTurn: String?
    private var lastLogCount = 0

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
        let state = next.fireworks
        let phase = FireworksScreenPhase.of(next)
        let previousPhase = lastPhase
        let previousTurn = lastTurn
        lastPhase = phase
        lastTurn = state?.turnId
        room = next
        if phase == .playing, previousPhase == .countdown { SRHaptic.tap() }
        // Somebody played: a bang lands, a misfire thuds.
        let logCount = state?.log.count ?? 0
        if logCount > lastLogCount, previousPhase == .playing, let entry = state?.log.last, entry.kind == .play {
            if entry.ok == true { SRHaptic.ok() } else { SRHaptic.bad() }
        }
        lastLogCount = logCount
        // The turn moved: whatever was half picked is gone.
        if state?.turnId != previousTurn {
            clearPicks()
            if phase == .playing, state?.turnId == next.meId, previousPhase != nil { SRHaptic.ok() }
        }
        // A picked card that has left my hand, or a target who left, is let go.
        if let picked = pickedCard, !(myHand.contains { $0.id == picked }) { pickedCard = nil }
        if let target = hintTarget, state?.seat(target) == nil || next.players.first(where: { $0.id == target })?.joined != true {
            hintTarget = nil
            hint = nil
        }
        if phase == .finished, previousPhase == .playing {
            if next.winnerIds.contains(next.meId) { SRHaptic.ok() } else { SRHaptic.select() }
        }
    }

    // MARK: - What the screen reads

    private var state: FireworksState? { room?.fireworks }

    /// True while it is my turn.
    var myTurn: Bool {
        guard let room, let state, FireworksScreenPhase.of(room) == .playing else { return false }
        return state.turnId == room.meId && room.me?.joined == true
    }

    /// I am at the table (not watching, not gone).
    var seated: Bool {
        guard let room else { return false }
        return state?.seat(room.meId)?.seated == true && room.me?.joined == true
    }

    /// My own hand: ids and knowledge only.
    var myHand: [FireworksCard] { state?.seat(room?.meId ?? "")?.hand ?? [] }

    /// Everyone else at the table still playing, seat order from the player after me.
    var others: [FireworksSeat] {
        guard let room, let state else { return [] }
        let seats = state.seats.filter { s in
            s.seated && s.id != room.meId && room.players.first(where: { $0.id == s.id })?.joined == true
        }
        guard let mine = state.seats.firstIndex(where: { $0.id == room.meId }) else { return seats }
        let after = state.seats[(mine + 1)...].map(\.id) + state.seats[..<mine].map(\.id)
        return after.compactMap { id in seats.first { $0.id == id } }
    }

    var canHint: Bool { myTurn && (state?.hints ?? 0) > 0 && !sending }
    /// A drop is refused while every token is in.
    var canDiscard: Bool { myTurn && pickedCard != nil && (state?.hints ?? 0) < (state?.maxHints ?? 8) && !sending }
    var canPlay: Bool { myTurn && pickedCard != nil && !sending }

    /// The cards the hint being built would point at.
    var previewIds: Set<Int> {
        guard let hint, let target = hintTarget, let hand = state?.seat(target)?.hand else { return [] }
        return Set(FireworksRules.touched(hint, in: hand))
    }

    /// The hints possible for the player picked.
    var hintChoices: [FireworksHint] {
        guard let target = hintTarget, let state, let hand = state.seat(target)?.hand else { return [] }
        return FireworksRules.possibleHints(for: hand, colours: state.hintColours)
    }

    // MARK: - Picking

    func pick(card id: Int) {
        guard myTurn else { return }
        hintTarget = nil
        hint = nil
        pickedCard = pickedCard == id ? nil : id
        SRHaptic.select()
        clearNotes()
    }

    func target(_ playerId: String) {
        guard myTurn else { return }
        pickedCard = nil
        if hintTarget == playerId {
            hintTarget = nil
            hint = nil
        } else {
            hintTarget = playerId
            hint = nil
        }
        SRHaptic.select()
        clearNotes()
    }

    func choose(_ next: FireworksHint) {
        guard hintTarget != nil else { return }
        hint = hint == next ? nil : next
        SRHaptic.select()
    }

    func clearPicks() {
        pickedCard = nil
        hintTarget = nil
        hint = nil
    }

    // MARK: - Moves

    func sendHint() {
        guard canHint, let target = hintTarget, let hint else { return }
        var body = GameActionBody(action: "hint")
        body.to = target
        switch hint {
        case .colour(let c): body.colour = c
        case .rank(let r): body.rank = r
        }
        send(body)
    }

    func play() {
        guard canPlay, let id = pickedCard else { return }
        var body = GameActionBody(action: "play")
        body.card = id
        send(body)
    }

    func discard() {
        guard myTurn, let id = pickedCard, !sending else { return }
        guard canDiscard else {
            refuse("All the hint tokens are in — give a hint or play a card.")
            return
        }
        var body = GameActionBody(action: "discard")
        body.card = id
        send(body)
    }

    private func send(_ body: GameActionBody) {
        sending = true
        Task {
            let outcome = await self.link.post(body)
            self.sending = false
            switch outcome {
            case .ok:
                self.clearPicks()
                self.clearNotes()
            case .refused(let sentence):
                self.refuse(sentence)
            case .wrongPhase:
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
