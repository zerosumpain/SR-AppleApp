import Foundation

/// One Secret Mission room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns the
/// team a leader is picking and the five moves: ready, propose, vote, play,
/// guess. A move the server refuses (400) shows its sentence for a moment and
/// costs nothing; one that lands after the clock moved the room on (409) just
/// re-reads it.
@MainActor
final class MissionStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// The team being picked, in tap order (the leader's).
    @Published private(set) var picked: [String] = []
    /// The Tracker's pick, before they send it.
    @Published private(set) var suspect: String?
    /// Why the last move was refused, shown for a moment.
    @Published private(set) var refusal: String?
    /// A move is on its way to the server.
    @Published private(set) var sending = false

    private let link: GameRoomLink
    private var noteTask: Task<Void, Never>?
    private var lastPhase: MissionPhase?
    private var lastLeader: String?
    /// The proposal the picker was last cleared for: "mission.attempt".
    private var pickedFor: String?

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
        let state = next.mission
        let phase = MissionScreenPhase.of(next)
        let previous = lastPhase
        let previousLeader = lastLeader
        lastPhase = phase
        lastLeader = state?.leaderId
        room = next
        if phase != previous, previous != nil {
            switch phase {
            case .roles: SRHaptic.tap()
            case .voting, .tally, .outcome: SRHaptic.select()
            case .mission where state?.seat(next.meId)?.onTeam == true: SRHaptic.ok()
            case .hunt where state?.secret?.role == .tracker: SRHaptic.ok()
            default: break
            }
        }
        // My turn to lead has come round.
        if phase == .proposing, state?.leaderId == next.meId, previousLeader != next.meId || previous != .proposing {
            if previous != nil { SRHaptic.ok() }
        }
        let key = "\(state?.mission ?? 0).\(state?.attempt ?? 0)"
        if key != pickedFor {
            pickedFor = key
            picked = []
            clearNotes()
        }
        if phase != .hunt { suspect = nil }
    }

    private var state: MissionState? { room?.mission }

    private var amSeated: Bool {
        guard let room else { return false }
        return state?.seat(room.meId)?.seated == true && room.me?.joined == true
    }

    // MARK: - What I can do

    var phase: MissionPhase { room.map(MissionScreenPhase.of) ?? .unknown }

    var myRole: MissionRole? { state?.secret?.role }

    var amLeader: Bool { phase == .proposing && amSeated && state?.leaderId == room?.meId }

    var canPropose: Bool { amLeader && !sending && picked.count == (state?.teamSize ?? 0) && !picked.isEmpty }

    var canVote: Bool { phase == .voting && amSeated && state?.secret?.vote == nil && !sending }

    var onTeam: Bool { amSeated && (state?.team ?? []).contains(room?.meId ?? "") }

    var canPlay: Bool { phase == .mission && onTeam && state?.secret?.card == nil && !sending }

    /// Only spies are offered Sabotage; the server refuses it from the crew anyway.
    var maySabotage: Bool { myRole?.side == .spies }

    var amTracker: Bool { phase == .hunt && amSeated && myRole == .tracker }

    var amReady: Bool { state?.seat(room?.meId ?? "")?.ready == true }

    // MARK: - Moves

    func toggle(_ id: String) {
        guard amLeader, let size = state?.teamSize else { return }
        let next = MissionRules.toggle(id, in: picked, size: size)
        if next == picked {
            SRHaptic.bad()
        } else {
            SRHaptic.select()
            picked = next
        }
        if refusal != nil { refusal = nil }
    }

    func pickSuspect(_ id: String) {
        guard amTracker else { return }
        suspect = suspect == id ? nil : id
        SRHaptic.select()
    }

    func ready() {
        guard phase == .roles, amSeated, !amReady, !sending else { return }
        send(GameActionBody(action: "ready"))
    }

    func propose() {
        guard canPropose else { return }
        SRHaptic.tap()
        send(GameActionBody(action: "propose", team: picked))
    }

    func vote(approve: Bool) {
        guard canVote else { return }
        SRHaptic.tap()
        send(GameActionBody(action: "vote", approve: approve))
    }

    func play(sabotage: Bool) {
        guard canPlay, !sabotage || maySabotage else { return }
        SRHaptic.tap()
        send(GameActionBody(action: "play", card: sabotage ? "sabotage" : "succeed"))
    }

    func guess() {
        guard amTracker, let suspect, !sending else { return }
        SRHaptic.tap()
        var body = GameActionBody(action: "guess")
        body.playerId = suspect
        send(body)
    }

    private func send(_ body: GameActionBody) {
        sending = true
        Task {
            let outcome = await self.link.post(body)
            self.sending = false
            switch outcome {
            case .ok:
                self.clearNotes()
            case .refused(let sentence):
                self.refuse(sentence)
            case .wrongPhase:
                // A clock ran out first — the room says where it is.
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

    // MARK: - Lobby verbs

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
