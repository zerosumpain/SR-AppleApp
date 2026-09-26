import Foundation
import QuartzCore

/// One Tap Duel room, live.
///
/// The connection — stream, snapshot fallback, reconnects, the clock and the
/// lobby's auto-join — is `GameRoomLink`, shared with every game. This owns
/// what a Tap Duel room means.
///
/// The armed phase runs off a display link rather than a timer: each frame
/// asks `TapTiming.signal` what the screen should show at the instant THAT
/// FRAME reaches the glass (`targetTimestamp`), and the frame that first shows
/// green is the one the reaction is measured from.
@MainActor
final class TapDuelStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    @Published private(set) var signal: TapSignal = .wait
    /// My tap this round, judged on the phone — shown until the result.
    @Published private(set) var myTap: TapOutcome?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?

    private let link: GameRoomLink
    private var ledger = TapLedger()
    /// Monotonic seconds at which green reached the screen this round.
    private var shownAt: Double?
    private var roundNumber: Int?
    private var ticker: FrameTicker?

    init(roomId: String) {
        self.roomId = roomId
        self.link = GameRoomLink(roomId: roomId)
        link.onRoom = { [weak self] room in self?.apply(room) }
        link.onEnd = { [weak self] in self?.didEnd() }
        link.onNote = { [weak self] update in self?.note(update) }
    }

    var clock: GameClock { link.clock }

    /// Monotonic milliseconds — the phone's side of `GameClock`.
    static func nowMs() -> Double { GameRoomLink.nowMs() }

    /// The server's clock, now, as well as this phone can tell.
    func serverNow() -> Double? { link.serverNow() }

    // MARK: - Connection

    /// Open (or reopen) the room. Idempotent.
    func open() { link.open() }

    /// Close the stream and stop the display link. The room screen calls this
    /// when it goes away and when the scene leaves the foreground.
    func close() {
        link.close()
        ticker?.stop()
        ticker = nil
    }

    func refresh() async { await link.refresh() }

    private func didEnd() {
        ended = true
        close()
    }

    private func note(_ note: GameLinkNote) {
        switch note {
        case .reconnecting: message = "Reconnecting…"
        case .reconnected: if message == "Reconnecting…" { message = nil }
        case .error(let text): message = text
        }
    }

    // MARK: - Applying a room

    private func apply(_ next: GameRoom) {
        if next.phase == .closed {
            room = next
            return
        }
        let newRound = next.round?.number
        if newRound != roundNumber {
            roundNumber = newRound
            shownAt = nil
            myTap = nil
            signal = .wait
        }
        room = next

        // Armed: the display link drives the signal. Anything else: it rests.
        if next.phase == .armed, next.round != nil {
            startTicker()
        } else {
            ticker?.stop()
            ticker = nil
            if next.phase != .armed { signal = next.phase == .result ? .go : .wait }
        }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let ticker = FrameTicker { [weak self] target in
            guard let self else { return false }
            self.frame(at: target)
            return true
        }
        self.ticker = ticker
        ticker.start()
    }

    /// One display frame, which will reach the glass at `target` (monotonic s).
    private func frame(at target: Double) {
        guard let round = room?.round, room?.phase == .armed,
              let server = clock.server(target * 1000) else { return }
        let next = TapTiming.signal(for: round, atServer: server)
        if next == .go, shownAt == nil { shownAt = target }
        if next != signal { signal = next }
    }

    // MARK: - Tapping

    /// A touch on the armed surface, at its own monotonic timestamp.
    func tap(at timestamp: Double) {
        guard let room, room.phase == .armed, let round = room.round,
              room.me?.joined == true, ledger.claim(round: round.number) else { return }
        let outcome = TapTiming.judge(tappedAt: timestamp, shownAt: shownAt)
        myTap = outcome
        if outcome.counts { SRHaptic.ok() } else { SRHaptic.bad() }
        let body = outcome.body(round: round.number)
        Task { await self.send(body) }
    }

    func hasTapped(round: Int) -> Bool { ledger.hasTapped(round: round) }

    // MARK: - Actions

    /// join | leave | start | again.
    @discardableResult
    func act(_ action: String) async -> Bool {
        busy = true
        defer { busy = false }
        return await send(GameActionBody(action: action))
    }

    @discardableResult
    private func send(_ body: GameActionBody) async -> Bool {
        switch await link.post(body) {
        case .ok:
            return true
        case .gone, .wrongPhase:
            // Gone: the link has ended the screen. Wrong phase — a tap for a
            // round that just closed: the stream already carries the truth.
            return false
        case .refused(let text), .failed(let text):
            message = text
            return false
        }
    }
}

/// A `CADisplayLink`, as a closure. The closure returns false to stop.
@MainActor
final class FrameTicker: NSObject {
    private var link: CADisplayLink?
    private let onFrame: @MainActor (Double) -> Bool

    init(onFrame: @escaping @MainActor (Double) -> Bool) {
        self.onFrame = onFrame
    }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        if !onFrame(link.targetTimestamp) { stop() }
    }
}
