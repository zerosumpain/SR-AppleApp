import Foundation

/// One Pass the Plate room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns the
/// card being chosen and the one move, `pick`. A tap on a card sends it at
/// once — a choice can be changed until everybody has chosen, so there is no
/// separate "confirm". With a serving spoon in use, the first tap holds a card
/// here and the second sends both. A pick the server refuses (400) shows its
/// sentence for a moment; one that lands after the plates moved on (409, or
/// "not on your plate") re-reads the room.
@MainActor
final class PassThePlateStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// Cards held on this phone before sending (the spoon's first of two).
    @Published private(set) var holding: [Int] = []
    /// Use the serving spoon this turn.
    @Published private(set) var takeTwo = false
    /// Why the last pick was refused, shown for a moment.
    @Published private(set) var refusal: String?
    /// A pick is on its way to the server.
    @Published private(set) var sending = false

    private let link: GameRoomLink
    private var noteTask: Task<Void, Never>?
    private var lastPhase: PassThePlatePhase?
    private var lastTurnKey: String?

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
        let state = next.passThePlate
        let phase = PassThePlateScreenPhase.of(next)
        let previous = lastPhase
        lastPhase = phase
        room = next
        if phase == .picking, previous == .countdown { SRHaptic.tap() }
        if phase == .scoring, previous == .picking { SRHaptic.select() }
        if phase == .finished, previous != nil, previous != .finished {
            if next.winnerIds.contains(next.meId) { SRHaptic.ok() } else { SRHaptic.select() }
        }
        // A new turn (the plates moved): whatever was held belongs to a plate
        // that has gone.
        let key = "\(state?.round ?? 0)|\(state?.turn ?? 0)"
        if key != lastTurnKey {
            if lastTurnKey != nil, phase == .picking { SRHaptic.select() }
            lastTurnKey = key
            holding = []
            takeTwo = false
            clearNotes()
        }
        if state?.canTakeTwo != true { takeTwo = false }
    }

    // MARK: - Reading the room

    private var state: PassThePlateState? { room?.passThePlate }

    /// I am at the table and it is a turn.
    var canPick: Bool {
        guard let room, PassThePlateScreenPhase.of(room) == .picking else { return false }
        return state?.seat(room.meId)?.seated == true && room.me?.joined == true && !(state?.hand.isEmpty ?? true)
    }

    /// What shows as chosen: the cards held here, else what the server has.
    var chosen: [Int] { holding.isEmpty ? (state?.myPick ?? []) : holding }

    var chosenSent: Bool { holding.isEmpty && !(state?.myPick.isEmpty ?? true) }

    /// The others still choosing, by name.
    var waitingFor: [String] {
        guard let room, let state else { return [] }
        return room.players.filter { p in
            guard p.id != room.meId, p.joined, let seat = state.seat(p.id) else { return false }
            return seat.seated && !seat.picked
        }.map(\.name)
    }

    // MARK: - Choosing

    func toggleTakeTwo() {
        guard state?.canTakeTwo == true else { return }
        takeTwo.toggle()
        holding = []
        SRHaptic.select()
    }

    /// A tap on a card on my plate.
    func tap(_ uid: Int) {
        guard canPick, !sending else { return }
        SRHaptic.select()
        let next = PassThePlateRules.toggle(uid, in: takeTwo ? holding : [], takeTwo: takeTwo)
        if PassThePlateRules.ready(next, takeTwo: takeTwo) {
            holding = takeTwo ? next : []
            send(next)
        } else {
            holding = next
        }
    }

    private func send(_ cards: [Int]) {
        sending = true
        Task {
            let outcome = await self.link.post(GameActionBody(action: "pick", cards: cards))
            self.sending = false
            self.holding = []
            switch outcome {
            case .ok:
                self.clearNotes()
            case .refused(let sentence):
                self.refuse(sentence)
                await self.link.refresh()
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

/// Which of the screen's pages a room is on: the game's own phase when the
/// room carries it, else the shared phase (a lobby from an older answer).
enum PassThePlateScreenPhase {
    static func of(_ room: GameRoom) -> PassThePlatePhase {
        if let phase = room.passThePlate?.phase, phase != .unknown { return phase }
        switch room.phase {
        case .lobby: return .lobby
        case .countdown: return .countdown
        case .finished: return .finished
        case .closed: return .closed
        case .playing: return .picking
        default: return .unknown
        }
    }
}
