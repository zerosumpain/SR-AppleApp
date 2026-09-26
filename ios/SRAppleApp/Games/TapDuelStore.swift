import Foundation
import QuartzCore

/// One Tap Duel room, live.
///
/// The room arrives over the site's SSE stream (`api/native/games/<id>/stream`,
/// frames `{"type":"room","room":…}`); every action is a POST that answers with
/// the room too. The stream is reopened on a drop and when the scene comes
/// back; a stream that cannot be opened at all (demo mode answers 404) falls
/// back to re-reading the snapshot on the same backoff, so the screen never
/// sits on a stale room without trying.
///
/// The armed phase runs off a display link rather than a timer: each frame
/// asks `TapTiming.signal` what the screen should show at the instant THAT
/// FRAME reaches the glass (`targetTimestamp`), and the frame that first shows
/// green is the one the reaction is measured from.
@MainActor
final class TapDuelStore: ObservableObject {
    let roomId: String

    @Published private(set) var room: GameRoom?
    @Published private(set) var signal: TapSignal = .wait
    /// My tap this round, judged on the phone — shown until the result.
    @Published private(set) var myTap: TapOutcome?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?

    private(set) var clock = GameClock()
    private var ledger = TapLedger()
    /// Monotonic seconds at which green reached the screen this round.
    private var shownAt: Double?
    private var roundNumber: Int?
    private var streamTask: Task<Void, Never>?
    private var ticker: FrameTicker?
    private var joinTried = false
    private let client = SiteClient.shared

    init(roomId: String) {
        self.roomId = roomId
    }

    /// Monotonic milliseconds — the phone's side of `GameClock`.
    static func nowMs() -> Double { CACurrentMediaTime() * 1000 }

    /// The server's clock, now, as well as this phone can tell.
    func serverNow() -> Double? { clock.server(Self.nowMs()) }

    // MARK: - Connection

    /// Open (or reopen) the room. Idempotent.
    func open() {
        guard streamTask == nil, !ended else { return }
        streamTask = Task { [weak self] in
            var backoff: UInt64 = 1
            while !Task.isCancelled {
                guard let self, !self.ended else { return }
                await self.refresh()
                if self.ended || Task.isCancelled { return }
                let delivered = await self.listen()
                if Task.isCancelled || self.ended { return }
                // A stream that carried frames earns a quick retry; one that
                // never opened backs off, up to ten seconds.
                backoff = delivered ? 1 : min(backoff * 2, 10)
                try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
            }
        }
    }

    /// Close the stream and stop the display link. The room screen calls this
    /// when it goes away and when the scene leaves the foreground.
    func close() {
        streamTask?.cancel()
        streamTask = nil
        ticker?.stop()
        ticker = nil
    }

    /// The snapshot: `GET api/native/games/<id>`, timed as a round trip.
    func refresh() async {
        let sent = Self.nowMs()
        do {
            let envelope: GameRoomEnvelope = try await client.send("api/native/games/\(roomId)")
            clock.record(serverNow: envelope.room.serverNow, sentAt: sent, receivedAt: Self.nowMs())
            apply(envelope.room)
        } catch SiteError.status(let code, _) where code == 404 {
            end()
        } catch SiteError.status(let code, _) where code == 403 {
            message = "You are not in this game."
            end()
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            message = room == nil ? error.localizedDescription : "Reconnecting…"
        }
    }

    /// Read the stream until it ends. True when at least one frame arrived.
    private func listen() async -> Bool {
        var delivered = false
        do {
            let stream = try client.stream(path: "api/native/games/\(roomId)/stream")
            for try await frame in stream {
                if Task.isCancelled { break }
                let received = Self.nowMs()
                guard let decoded = try? JSONDecoder().decode(GameStreamFrame.self, from: frame.data),
                      decoded.type == "room", let room = decoded.room else { continue }
                delivered = true
                clock.record(serverNow: room.serverNow, receivedAt: received)
                apply(room)
                if message == "Reconnecting…" { message = nil }
            }
        } catch {
            // Dropped or refused. The loop re-reads the snapshot next, which
            // is what tells a gone room (404) from a flaky connection.
        }
        return delivered
    }

    private func end() {
        ended = true
        close()
    }

    // MARK: - Applying a room

    private func apply(_ next: GameRoom) {
        if next.phase == .closed {
            room = next
            end()
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

        // An invitee who opened the room — from the notification or the list —
        // is in it. Once: a decline elsewhere must not be undone by this.
        if next.phase == .lobby, next.me?.status == "invited", !joinTried {
            joinTried = true
            Task { await self.act("join") }
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
        let sent = Self.nowMs()
        do {
            let data = try await client.post("api/native/games/\(roomId)", body: try JSONEncoder().encode(body))
            let received = Self.nowMs()
            if let envelope = try? JSONDecoder().decode(GameRoomEnvelope.self, from: data) {
                clock.record(serverNow: envelope.room.serverNow, sentAt: sent, receivedAt: received)
                apply(envelope.room)
            }
            return true
        } catch SiteError.status(let code, _) where code == 404 {
            end()
            return false
        } catch SiteError.status(let code, _) where code == 409 {
            // Wrong phase — a tap for a round that just closed. The stream
            // already carries the truth; nothing to say.
            return false
        } catch {
            message = error.localizedDescription
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
