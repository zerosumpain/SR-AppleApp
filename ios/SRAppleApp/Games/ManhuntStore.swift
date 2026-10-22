import Foundation
import CoreLocation

/// One Manhunt room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns the
/// game's own location session (`ManhuntLocator`) and its one rule: positions
/// are sent only while the room is in the head start or the hunt and I am in
/// it. Anything else — the finish, Leave, the room closing or going away, the
/// screen being closed — stops it on the spot. A fix is sent no sooner than
/// the server's gap after the last (it would only be ignored), and only when
/// it is fresh and sharp enough to mean something.
///
/// In the lobby the host's phone sends where it is as the circle's centre.
@MainActor
final class ManhuntStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// Why the last catch (or set-up) was refused, shown for a moment.
    @Published private(set) var refusal: String?
    @Published private(set) var sending = false
    /// The lobby is finding the host's position for the centre.
    @Published private(set) var centring = false
    /// Location is off for the app: the game cannot see this phone.
    @Published private(set) var locationOff = false
    /// When this phone last sent a fix (server time), for "last sent" on screen.
    @Published private(set) var lastSentAt: Double?

    private let link: GameRoomLink
    private let locator: ManhuntLocator
    private var noteTask: Task<Void, Never>?
    private var lastPhase: ManhuntPhase?
    private var lastPingCount = 0
    private var wasLive = false
    private var hadClaim = false
    private var autoCentred = false
    /// Monotonic ms of the last fix sent.
    private var lastSentMono: Double?
    private var posting = false

    init(roomId: String) {
        self.roomId = roomId
        self.link = GameRoomLink(roomId: roomId)
        self.locator = ManhuntLocator()
        link.onRoom = { [weak self] room in self?.apply(room) }
        link.onEnd = { [weak self] in self?.didEnd() }
        link.onNote = { [weak self] update in self?.note(update) }
        locator.onFix = { [weak self] location in self?.send(location) }
        locator.onDenied = { [weak self] in self?.locationOff = true }
    }

    func serverNow() -> Double? { link.serverNow() }

    // MARK: - Connection

    func open() { link.open() }

    /// The scene went to the background: the stream closes, but a live hunt
    /// keeps sending positions (every answer carries the room, so the finish
    /// still stops the session).
    func pauseStream() { link.close() }

    /// The screen is going: stop everything, the location session first.
    func close() {
        locator.stop()
        link.close()
    }

    private func didEnd() {
        ended = true
        locator.stop()
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
        let state = next.manhunt
        let phase = ManhuntScreenPhase.of(next)
        let previous = lastPhase
        lastPhase = phase
        room = next

        // The one place the location session is switched: on while the hunt
        // is live and I am in it, off for everything else.
        if phase.collectsPositions, state?.myRole != nil, next.me?.joined == true {
            locator.start()
        } else {
            locator.stop()
        }

        if phase == .headstart, previous == .countdown {
            if state?.myRole == .runner { SRHaptic.ok() } else { SRHaptic.tap() }
        }
        if phase == .hunt, previous == .headstart { SRHaptic.tap() }
        let pings = state?.pings.count ?? 0
        if phase == .hunt, pings > lastPingCount, previous != nil { SRHaptic.select() }
        lastPingCount = pings
        let live = state?.runnerLiveUntil != nil
        if live, !wasLive, previous != nil { SRHaptic.bad() }
        wasLive = live
        let claim = state?.claim != nil
        if claim, !hadClaim, state?.myRole == .runner { SRHaptic.bad() }
        hadClaim = claim
        if phase == .finished, previous == .hunt {
            if next.winnerIds.contains(next.meId) { SRHaptic.ok() } else { SRHaptic.select() }
        }

        // The host's lobby centres itself once, as soon as it opens.
        if phase == .lobby, next.isHost, state?.area == nil, !autoCentred, !SRDemo.isOn {
            autoCentred = true
            centreHere()
        }
        if phase != .lobby { autoCentred = false }
    }

    // MARK: - Reading the room

    var state: ManhuntState? { room?.manhunt }

    var myRole: ManhuntRole? { state?.myRole }

    var claimByMe: Bool {
        guard let room, let claim = state?.claim else { return false }
        return claim.hunterId == room.meId
    }

    var claimOnMe: Bool { state?.claim != nil && myRole == .runner }

    var runnerLive: Bool { state?.runnerLiveUntil != nil }

    /// I may tap Catch: a hunter, in the hunt, no claim standing, not cooling down.
    func canCatch(now: Double?) -> Bool {
        guard myRole == .hunter, ManhuntScreenPhase.of(room) == .hunt, state?.claim == nil, !sending else { return false }
        if let until = state?.catchCooldownUntil, let now, now < until { return false }
        return true
    }

    // MARK: - Positions

    private func send(_ location: CLLocation) {
        guard let room, room.manhunt?.phase.collectsPositions == true else { return }
        let gap = room.manhunt?.fixMinGapMs ?? 3_000
        let mono = GameRoomLink.nowMs()
        let age = -location.timestamp.timeIntervalSinceNow
        guard !posting,
              ManhuntRules.shouldSend(accuracy: location.horizontalAccuracy, ageSeconds: age,
                                      sinceLastSentMs: lastSentMono.map { mono - $0 }, minGapMs: gap) else { return }
        lastSentMono = mono
        posting = true
        // The fix's time on the server's clock: now there, less how old it is.
        let at = serverNow().map { $0 - max(0, age) * 1000 }
        let body = GameActionBody(action: "position", lat: location.coordinate.latitude, lng: location.coordinate.longitude,
                                  accuracy: location.horizontalAccuracy, at: at)
        Task {
            let outcome = await self.link.post(body)
            self.posting = false
            if outcome == .ok { self.lastSentAt = self.serverNow() }
        }
    }

    // MARK: - Moves

    /// The host's lobby: centre the circle where this phone is.
    func centreHere() {
        guard !centring else { return }
        centring = true
        Task {
            let fix = await locator.oneFix()
            centring = false
            guard let fix else {
                refuse(locationOff
                       ? "Location is off for the SR app: turn it on in Settings to set the play area."
                       : "Couldn't find where you are. Step outside and try again.")
                return
            }
            await post(GameActionBody(action: "area", lat: fix.coordinate.latitude, lng: fix.coordinate.longitude))
        }
    }

    /// The host changes the circle's size or the game's length in the lobby.
    func setSize(radius: Int? = nil, minutes: Int? = nil) {
        guard let area = state?.area else { return }
        Task { await post(GameActionBody(action: "area", lat: area.lat, lng: area.lng, radius: radius, minutes: minutes)) }
    }

    /// The host picks who runs; nil lets the start draw one.
    func pickRunner(_ playerId: String?) {
        SRHaptic.select()
        Task { await post(GameActionBody(action: "runner", playerId: playerId)) }
    }

    func catchNow() {
        guard canCatch(now: serverNow()) else { return }
        SRHaptic.tap()
        Task { await post(GameActionBody(action: "catch")) }
    }

    /// The runner owns up.
    func confirm() {
        guard claimOnMe else { return }
        SRHaptic.tap()
        Task { await post(GameActionBody(action: "confirm")) }
    }

    private func post(_ body: GameActionBody) async {
        sending = true
        let outcome = await link.post(body)
        sending = false
        switch outcome {
        case .ok:
            if body.action == "catch" { SRHaptic.ok() }
            clearNotes()
        case .refused(let sentence):
            refuse(sentence)
        case .wrongPhase:
            await link.refresh()
        case .gone:
            break
        case .failed(let text):
            message = text
        }
    }

    private func refuse(_ sentence: String) {
        refusal = sentence
        SRHaptic.bad()
        noteTask?.cancel()
        noteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
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
        // Leaving stops the location session before anything is sent.
        if action == "leave" { locator.stop() }
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

/// Which page a room is on: Manhunt's own phase when the room carries it,
/// else the shared phase (a lobby from an older answer).
enum ManhuntScreenPhase {
    static func of(_ room: GameRoom?) -> ManhuntPhase {
        guard let room else { return .unknown }
        if let phase = room.manhunt?.phase, phase != .unknown { return phase }
        switch room.phase {
        case .lobby: return .lobby
        case .countdown: return .countdown
        case .finished: return .finished
        case .closed: return .closed
        default: return .unknown
        }
    }
}
