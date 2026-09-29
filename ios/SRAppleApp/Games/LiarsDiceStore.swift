import Foundation

/// One Liar's Dice room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns the
/// bid being picked — quantity and face, kept legal against the standing bid
/// as it moves — and the two moves: bid, and call. A bid the server refuses
/// (400) shows the server's sentence for a moment and costs nothing; one that
/// arrives after the turn moved on (409) just re-reads the room.
@MainActor
final class LiarsDiceStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// The bid being picked.
    @Published private(set) var quantity = 1
    @Published private(set) var face = 2
    /// Why the last bid was refused, shown under the picker for a moment.
    @Published private(set) var refusal: String?
    /// A move is on its way to the server.
    @Published private(set) var sending = false

    private let link: GameRoomLink
    private var noteTask: Task<Void, Never>?
    private var lastPhase: LiarsDicePhase?
    private var lastTurn: String?
    /// The round and standing bid the picker was last fitted to.
    private var fittedTo: String?

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
        let state = next.liarsDice
        let phase = LiarsDiceScreenPhase.of(next)
        let previousPhase = lastPhase
        let previousTurn = lastTurn
        lastPhase = phase
        lastTurn = state?.turnId
        room = next
        if phase == .bidding, previousPhase == .countdown { SRHaptic.tap() }
        if phase == .reveal, previousPhase == .bidding { SRHaptic.select() }
        // My turn has come round: a nudge, and a fresh picker.
        if phase == .bidding, state?.turnId == next.meId, previousTurn != next.meId {
            if previousPhase != nil { SRHaptic.ok() }
            clearNotes()
        }
        // The standing bid moved (or a new round began): fit the picker to it.
        let key = Self.fitKey(state)
        if key != fittedTo {
            fittedTo = key
            fitPicker(reset: true)
        }
    }

    // MARK: - Picking a bid

    /// "round|who:quantity×face|dice" — changes whenever the picker must start over.
    private static func fitKey(_ state: LiarsDiceState?) -> String {
        guard let state else { return "" }
        let bid = state.bid.map { "\($0.playerId):\($0.quantity)x\($0.face)" } ?? "-"
        return "\(state.round)|\(bid)|\(state.totalDice)"
    }

    private var state: LiarsDiceState? { room?.liarsDice }

    /// True while it is my turn to bid or call.
    var myTurn: Bool {
        guard let room, let state, LiarsDiceScreenPhase.of(room) == .bidding else { return false }
        return state.turnId == room.meId && room.me?.joined == true
    }

    /// My dice this round; empty when I have none (out, or not rolled yet).
    var myDice: [Int] { state?.seat(room?.meId ?? "")?.dice ?? [] }

    var canCall: Bool { myTurn && state?.bid != nil && !sending }

    /// A bid is possible at all (no raise past the table's dice is).
    var canBid: Bool {
        guard myTurn, let state else { return false }
        return LiarsDiceRules.minQuantity(standing: state.bid, total: state.totalDice, wild: state.wildOnes) != nil
    }

    var pickedIsLegal: Bool {
        guard let state else { return false }
        return LiarsDiceRules.isLegal(quantity: quantity, face: face, standing: state.bid,
                                      total: state.totalDice, wild: state.wildOnes)
    }

    var canRaiseQuantity: Bool { quantity < (state?.totalDice ?? 0) }

    var canLowerQuantity: Bool {
        guard let state,
              let low = LiarsDiceRules.minQuantity(standing: state.bid, total: state.totalDice, wild: state.wildOnes)
        else { return false }
        return quantity > low
    }

    func faceIsLegal(_ f: Int) -> Bool {
        guard let state else { return false }
        return LiarsDiceRules.isLegal(quantity: quantity, face: f, standing: state.bid,
                                      total: state.totalDice, wild: state.wildOnes)
    }

    func raiseQuantity() {
        guard canRaiseQuantity else { return }
        quantity += 1
        SRHaptic.select()
        fitPicker(reset: false)
    }

    func lowerQuantity() {
        guard canLowerQuantity else { return }
        quantity -= 1
        SRHaptic.select()
        fitPicker(reset: false)
    }

    func pick(face f: Int) {
        guard faceIsLegal(f) else { return }
        face = f
        SRHaptic.select()
        if refusal != nil { refusal = nil }
    }

    /// Keep the picker on a legal bid: from scratch (the smallest raise, my
    /// best face to open), or by moving the face to the nearest legal one.
    private func fitPicker(reset: Bool) {
        guard let state else { return }
        let wild = state.wildOnes
        if reset {
            let preferred = LiarsDiceRules.mostCommonFace(myDice, wild: wild)
            if let start = LiarsDiceRules.startingBid(standing: state.bid, total: state.totalDice, wild: wild,
                                                      preferred: preferred) {
                quantity = start.quantity
                face = start.face
            }
            return
        }
        if let fitted = LiarsDiceRules.fitFace(face, quantity: quantity, standing: state.bid,
                                               total: state.totalDice, wild: wild) {
            face = fitted
        }
    }

    // MARK: - Moves

    /// Raise to the picked bid.
    func bid() {
        guard myTurn, !sending, let state else { return }
        if let sentence = LiarsDiceRules.problem(quantity: quantity, face: face, standing: state.bid,
                                                 total: state.totalDice, wild: state.wildOnes) {
            refuse(sentence)
            return
        }
        send(GameActionBody(action: "bid", quantity: quantity, face: face))
    }

    /// Call the standing bid a lie: every cup is lifted.
    func callLiar() {
        guard canCall else { return }
        SRHaptic.tap()
        send(GameActionBody(action: "liar"))
    }

    private func send(_ body: GameActionBody) {
        sending = true
        Task {
            let outcome = await self.link.post(body)
            self.sending = false
            switch outcome {
            case .ok:
                SRHaptic.ok()
                self.clearNotes()
            case .refused(let sentence):
                self.refuse(sentence)
            case .wrongPhase:
                // The turn moved on (a clock ran out) — the room says where it is.
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

/// Which of the screen's pages a room is on: Liar's Dice's own phase when the
/// room carries it, else the shared phase (a lobby from an older answer).
enum LiarsDiceScreenPhase {
    static func of(_ room: GameRoom) -> LiarsDicePhase {
        if let phase = room.liarsDice?.phase, phase != .unknown { return phase }
        switch room.phase {
        case .lobby: return .lobby
        case .countdown: return .countdown
        case .reveal: return .reveal
        case .finished: return .finished
        case .closed: return .closed
        case .playing: return .bidding
        default: return .unknown
        }
    }
}
