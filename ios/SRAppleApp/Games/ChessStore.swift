import Foundation

/// One chess room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns the
/// piece picked up — a tap on one of my pieces, then a tap where it goes — and
/// the three moves: move, resign, draw. The server sends every legal move for
/// the side to move, so the board lights the right squares without knowing
/// the rules; a move the server still refuses (400) shows its sentence for a
/// moment, and one that lands after the turn moved on (409) re-reads the room.
@MainActor
final class ChessStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// The piece picked up, by square.
    @Published private(set) var selected: ChessSquare?
    /// A pawn reaching the last rank, waiting to be told what it becomes.
    @Published private(set) var promotion: ChessPromotionAsk?
    /// Resign asks first.
    @Published var confirmingResign = false
    /// Why the last move was refused, shown under the board for a moment.
    @Published private(set) var refusal: String?
    /// A move is on its way to the server.
    @Published private(set) var sending = false

    private let link: GameRoomLink
    private var noteTask: Task<Void, Never>?
    private var lastPhase: ChessPhase?
    private var lastTurn: String?

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
        let state = next.chess
        let phase = ChessScreenPhase.of(next)
        let previousPhase = lastPhase
        let previousTurn = lastTurn
        lastPhase = phase
        lastTurn = state?.turnId
        room = next
        if phase == .playing, previousPhase == .countdown { SRHaptic.tap() }
        // My move has come round: a nudge — a sharper one when I am in check.
        if phase == .playing, state?.turnId == next.meId, previousTurn != next.meId, previousPhase != nil {
            if state?.check == true { SRHaptic.bad() } else { SRHaptic.ok() }
        }
        if phase == .finished, previousPhase == .playing {
            if next.winnerIds.contains(next.meId) { SRHaptic.ok() } else { SRHaptic.select() }
        }
        // The board moved under a pick: drop it.
        if state?.turnId != next.meId {
            selected = nil
            promotion = nil
        }
    }

    // MARK: - Reading the room

    private var state: ChessState? { room?.chess }

    var myColour: ChessColour? {
        guard let room, let state else { return nil }
        return state.colour(of: room.meId)
    }

    /// True while it is my move.
    var myTurn: Bool {
        guard let room, let state, ChessScreenPhase.of(room) == .playing else { return false }
        return state.turnId == room.meId && room.me?.joined == true
    }

    /// I am one of the two at the board (not watching).
    var seated: Bool {
        guard let room, let state else { return false }
        return state.seat(room.meId)?.seated == true && room.me?.joined == true
    }

    /// Where the picked-up piece may go.
    var targets: [ChessLegalMove] {
        guard let selected, let state else { return [] }
        return state.targets(from: selected)
    }

    var targetNames: Set<String> { Set(targets.map(\.to)) }

    var drawOfferedByMe: Bool {
        guard let room, let state else { return false }
        return state.drawOfferBy == room.meId
    }

    var drawOfferedToMe: Bool {
        guard let room, let state, let by = state.drawOfferBy else { return false }
        return by != room.meId
    }

    // MARK: - Picking and moving

    func canPick(_ square: ChessSquare) -> Bool {
        guard myTurn, let state else { return false }
        return state.movable.contains(square.name)
    }

    /// A tap on the board: pick up a piece, put it down, or move it.
    func tap(_ square: ChessSquare) {
        guard myTurn, !sending else { return }
        if let picked = selected {
            if square == picked {
                selected = nil
                SRHaptic.select()
                return
            }
            if let target = targets.first(where: { $0.to == square.name }) {
                if target.promotes {
                    promotion = ChessPromotionAsk(from: picked, to: square)
                    SRHaptic.select()
                } else {
                    send(from: picked, to: square, promotion: nil)
                }
                return
            }
        }
        if canPick(square) {
            selected = square
            SRHaptic.select()
        } else if selected != nil {
            selected = nil
        }
    }

    /// The pawn becomes this.
    func promote(to kind: ChessPieceKind) {
        guard let ask = promotion else { return }
        promotion = nil
        send(from: ask.from, to: ask.to, promotion: String(kind.rawValue))
    }

    func cancelPromotion() {
        promotion = nil
    }

    private func send(from: ChessSquare, to: ChessSquare, promotion: String?) {
        selected = nil
        send(GameActionBody(action: "move", from: from.name, to: to.name, promotion: promotion))
    }

    /// Give up. The screen confirms first.
    func resign() {
        guard seated, !sending else { return }
        SRHaptic.tap()
        send(GameActionBody(action: "resign"))
    }

    /// Offer a draw, or take the one on the table.
    func draw() {
        guard seated, !sending, !drawOfferedByMe else { return }
        SRHaptic.tap()
        send(GameActionBody(action: "draw"))
    }

    private func send(_ body: GameActionBody) {
        sending = true
        Task {
            let outcome = await self.link.post(body)
            self.sending = false
            switch outcome {
            case .ok:
                if body.action == "move" { SRHaptic.ok() }
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

/// A pawn move waiting on the picker: the two squares.
struct ChessPromotionAsk: Equatable {
    let from: ChessSquare
    let to: ChessSquare
}

/// Which of the screen's pages a room is on: chess's own phase when the room
/// carries it, else the shared phase (a lobby from an older answer).
enum ChessScreenPhase {
    static func of(_ room: GameRoom) -> ChessPhase {
        if let phase = room.chess?.phase, phase != .unknown { return phase }
        switch room.phase {
        case .lobby: return .lobby
        case .countdown: return .countdown
        case .playing: return .playing
        case .finished: return .finished
        case .closed: return .closed
        default: return .unknown
        }
    }
}
