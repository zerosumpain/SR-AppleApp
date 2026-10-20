import Foundation

/// One Marble Race room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns the
/// two moves — back a marble, report the finish — and hands the dealt race to
/// Marbler's page (`MarblerModel`), which runs it on this phone. The race is
/// sent with how far into it the room's clock already is, so a phone that
/// opens the room late (or whose page reloads) joins the same moment as
/// everyone else.
@MainActor
final class MarbleRaceStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// Why the last pick was refused, shown under the marbles for a moment.
    @Published private(set) var refusal: String?

    /// The web view's side: the race runs there.
    let marbler = MarblerModel()

    private let link: GameRoomLink
    private var noteTask: Task<Void, Never>?
    /// The race (by seed) already handed to the page, and whether this phone has reported it.
    private var sentSeed: UInt32?
    private var reported = false

    init(roomId: String) {
        self.roomId = roomId
        self.link = GameRoomLink(roomId: roomId)
        link.onRoom = { [weak self] room in self?.apply(room) }
        link.onEnd = { [weak self] in self?.didEnd() }
        link.onNote = { [weak self] update in self?.note(update) }
        marbler.roomScript = { [weak self] in self?.raceScript() }
        marbler.onRoomFinished = { [weak self] order in self?.report(order) }
    }

    /// The server's clock, now, as well as this phone can tell.
    func serverNow() -> Double? { link.serverNow() }

    var state: MarbleRaceState? { room?.marbleRace }

    /// Marble Race's own phase, or the shared one's nearest (a lobby from an older answer).
    var phase: MarbleRaceState.Phase {
        if let p = state?.phase, p != .unknown { return p }
        switch room?.phase {
        case .lobby?: return .lobby
        case .finished?: return .finished
        case .closed?: return .closed
        default: return .unknown
        }
    }

    var myMarble: Int? { room.flatMap { state?.marble(of: $0.meId) } }

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
        let before = phase
        room = next
        if phase == .picking, before == .lobby { SRHaptic.tap() }
        if phase == .lobby { sentSeed = nil }
        // A new race was dealt: hand it to the page (now, or when the page is ready).
        if phase == .racing, let race = state?.race, sentSeed != race.seed {
            sentSeed = race.seed
            reported = false
            marbler.sendRoom()
        }
    }

    /// The page's `room(…)` call for the dealt race, with the room's clock as it stands now.
    private func raceScript() -> String? {
        guard let room, let state, phase == .racing, let race = state.race else { return nil }
        let now = link.serverNow() ?? room.serverNow
        return MarbleRaceBridge.script(room: room, state: state, elapsed: (now - race.startAt) / 1000)
    }

    // MARK: - Moves

    /// Back marble `m` (picking again swaps).
    func back(_ m: Int) {
        guard phase == .picking, myMarble != m else { return }
        SRHaptic.select()
        Task { [weak self] in
            guard let self else { return }
            switch await self.link.post(GameActionBody(action: "back", marble: m)) {
            case .ok: self.clearRefusal()
            case .refused(let sentence): self.refuse(sentence)
            case .wrongPhase:
                // Somebody took it first, or picking closed: the room says which.
                self.refuse("Somebody else has that one.")
                await self.link.refresh()
            case .gone: break
            case .failed(let text): self.message = text
            }
        }
    }

    /// This phone saw the race end: tell the room, once.
    private func report(_ order: [Int]) {
        guard phase == .racing, !reported else { return }
        reported = true
        Task { [weak self] in
            guard let self else { return }
            switch await self.link.post(GameActionBody(action: "finish", order: order)) {
            case .ok, .gone: break
            case .wrongPhase:
                // The room settled without us (its clock ran out first).
                await self.link.refresh()
            case .refused(let text), .failed(let text):
                self.reported = false
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

    private func clearRefusal() {
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
