import Foundation

/// One Homestead room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns what
/// the player is in the middle of — the piece picked to build, a fox move
/// waiting on "take from whom?", the sheet on show, a trade being composed —
/// and sends each move as a `HomesteadMove`. The server lists every legal spot
/// for me (`legal`), so the board lights the right corners and sides without
/// knowing the rules; a move it still refuses (400, or a 409 that says why)
/// shows its sentence for a moment and the room re-reads.
@MainActor
final class HomesteadStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// The piece picked from the build bar; nil lights every spot (not on hard).
    @Published var picked: HomesteadPiece?
    /// The sheet on show.
    @Published var sheet: HomesteadSheet?
    /// A fox hex tapped where two or more could be robbed: whom to take from.
    @Published var foxAsk: HomesteadFoxAsk?
    /// Why the last move was refused, shown under the board for a moment.
    @Published private(set) var refusal: String?
    /// A move is on its way to the server.
    @Published private(set) var sending = false
    /// The dice last rolled, to tumble when they change.
    @Published private(set) var rollSerial = 0

    private let link: GameRoomLink
    private var noteTask: Task<Void, Never>?
    private var lastStep: HomesteadStep?
    private var lastActive: String?
    private var lastDiceAt: Double?
    private var lastPhase: HomesteadPhase?

    init(roomId: String) {
        self.roomId = roomId
        self.link = GameRoomLink(roomId: roomId)
        link.onRoom = { [weak self] room in self?.apply(room) }
        link.onEnd = { [weak self] in self?.didEnd() }
        link.onNote = { [weak self] update in self?.note(update) }
    }

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
        let state = next.homestead
        let phase = HomesteadScreenPhase.of(next)
        let previousPhase = lastPhase
        let previousActive = lastActive
        let previousStep = lastStep
        lastPhase = phase
        lastActive = state?.activeId
        lastStep = state?.step
        room = next

        if let at = state?.dice?.at, at != lastDiceAt {
            if lastDiceAt != nil { rollSerial += 1 }
            lastDiceAt = at
        }
        if phase == .playing, previousPhase == .countdown { SRHaptic.tap() }
        // My turn has come round.
        if phase == .playing, state?.activeId == next.meId, previousActive != next.meId, previousPhase != nil {
            SRHaptic.ok()
        }
        if phase == .finished, previousPhase == .playing {
            if next.winnerIds.contains(next.meId) { SRHaptic.ok() } else { SRHaptic.select() }
        }
        // The step moved under a pick: drop it, and any fox question.
        if state?.step != previousStep || state?.activeId != previousActive {
            picked = nil
            foxAsk = nil
        }
        // A sheet whose moment has gone closes itself.
        if let sheet, !(state.map({ sheet.stillFits($0) }) ?? false) { self.sheet = nil }
        // A discard I owe takes the one sheet slot, over hand, trade or log:
        // SwiftUI shows one sheet at a time, so it cannot be a second one.
        if mustDiscard, sheet != .discard { sheet = .discard }
    }

    /// Open a sheet from the bar. While I owe a discard, that is the only one.
    func show(_ next: HomesteadSheet) {
        sheet = mustDiscard ? .discard : next
    }

    // MARK: - Reading the room

    var state: HomesteadState? { room?.homestead }

    var myTurn: Bool { state?.isMyTurn ?? false }

    /// I hold a seat (not watching).
    var seated: Bool { state?.myself?.seated == true && room?.me?.joined == true }

    /// Every spot to light now.
    var lit: [HomesteadTarget] {
        guard let state, !sending else { return [] }
        return HomesteadTargets.lit(state, picked: picked)
    }

    /// The build bar is offered: my main step, or anyone's in a five-player
    /// game's open building (the server's `legal` says which).
    var canBuild: Bool {
        guard let state, state.step == .main else { return false }
        let legal = state.legal
        return !legal.road.isEmpty || !legal.cottage.isEmpty || !legal.town.isEmpty || legal.canBuy
    }

    /// A discard is owed by me: the sheet that cannot be dismissed.
    var mustDiscard: Bool { (state?.step == .discard) && (state?.myDiscard ?? 0) > 0 }

    // MARK: - The board

    /// A tap on a lit spot.
    func tap(_ target: HomesteadTarget) {
        guard let state, !sending else { return }
        switch target.tool {
        case .fox:
            let victims = state.legal.victims[target.id] ?? []
            if victims.count >= 2 {
                foxAsk = HomesteadFoxAsk(hex: target.id, victims: victims)
                SRHaptic.select()
            } else {
                send(.fox(target.id, victim: victims.first))
            }
        case .road, .cottage, .town:
            guard let piece = target.tool.piece else { return }
            send(.build(piece, at: target.id))
        }
    }

    func robFrom(_ victim: String) {
        guard let ask = foxAsk else { return }
        foxAsk = nil
        send(.fox(ask.hex, victim: victim))
    }

    /// Pick a piece on the build bar, or put it down again.
    func pick(_ piece: HomesteadPiece) {
        picked = picked == piece ? nil : piece
        SRHaptic.select()
    }

    // MARK: - Moves

    func roll() { send(.roll) }
    func buy() { send(.buy) }
    func end() { send(.end) }
    func skip() { send(.skip) }

    /// Play an almanac card. Harvest and market ask first (the hand sheet).
    func play(_ card: HomesteadCard, take: [HomesteadResource]? = nil, resource: HomesteadResource? = nil) {
        send(.play(card, take: take, resource: resource))
        if sheet == .hand { sheet = nil }
    }

    func bank(give: HomesteadResource, get: HomesteadResource) { send(.bank(give: give, get: get)) }

    func offer(_ draft: HomesteadTradeDraft, to: [String]?) { send(.offer(give: draft.give, want: draft.want, to: to)) }

    func counter(_ offerId: String, _ draft: HomesteadTradeDraft) { send(.counter(offerId, give: draft.give, want: draft.want)) }

    func accept(_ offerId: String) { send(.accept(offerId)) }
    func refuse(_ offerId: String) { send(.refuse(offerId)) }
    func cancel(_ offerId: String) { send(.cancel(offerId)) }

    func discard(_ draft: HomesteadDiscardDraft) { send(.discard(draft.cards)) }

    private func send(_ move: HomesteadMove) {
        guard !sending else { return }
        sending = true
        SRHaptic.tap()
        Task {
            let outcome = await self.link.post(move)
            self.sending = false
            switch outcome {
            case .ok:
                if move.action == "build" {
                    SRHaptic.ok()
                    self.picked = nil
                }
                self.clearNotes()
            case .refused(let sentence):
                self.showRefusal(sentence)
            case .wrongPhase:
                // Somebody moved first or a timer ran out; the room says where it is.
                if let sentence = self.link.lastConflict, !sentence.isEmpty { self.showRefusal(sentence) }
                await self.link.refresh()
            case .gone:
                break
            case .failed(let text):
                self.message = text
            }
        }
    }

    private func showRefusal(_ sentence: String) {
        refusal = sentence
        SRHaptic.bad()
        noteTask?.cancel()
        noteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.refusal = nil
        }
    }

    private func clearNotes() {
        noteTask?.cancel()
        refusal = nil
    }

    // MARK: - Lobby actions

    /// join | leave | start | again.
    @discardableResult
    func act(_ action: String) async -> Bool {
        busy = true
        defer { busy = false }
        switch await link.post(GameActionBody(action: action)) {
        case .ok:
            return true
        case .wrongPhase:
            if let sentence = link.lastConflict, !sentence.isEmpty { message = sentence }
            return false
        case .gone:
            return false
        case .refused(let text), .failed(let text):
            message = text
            return false
        }
    }
}

/// The sheets over the board.
enum HomesteadSheet: String, Identifiable {
    case hand, bank, trade, log
    /// After a 7, when I hold too many: cannot be dismissed, and nothing else shows while it is owed.
    case discard

    var id: String { rawValue }

    /// Whether the sheet still makes sense for the room as it now is.
    func stillFits(_ state: HomesteadState) -> Bool {
        guard state.phase == .playing else { return false }
        let owing = state.step == .discard && state.myDiscard > 0
        if owing { return self == .discard }
        switch self {
        case .hand, .log, .trade: return true
        case .bank: return state.isMyTurn && state.step == .main
        case .discard: return false
        }
    }
}

struct HomesteadFoxAsk: Equatable, Identifiable {
    let hex: String
    let victims: [String]
    var id: String { hex }
}
