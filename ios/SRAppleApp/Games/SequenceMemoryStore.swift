import Foundation
import QuartzCore

/// One Sequence Memory room, live.
///
/// The connection — stream, snapshot fallback, the clock — is `GameRoomLink`.
/// This owns the show and the taps.
///
/// The show runs off a display link, as Tap Duel's armed phase does: each frame
/// asks `SequenceSchedule.lit` which tile is showing at the instant THAT FRAME
/// reaches the glass, on the server's clock, so every phone lights the same
/// tile together. A new flash ticks the haptic engine. When the last flash
/// ends the phone opens the input window itself rather than wait a network
/// hop for the `input` frame.
///
/// In `input` the phone does not know the sequence — it is off the wire — so it
/// collects `length` taps (Undo takes the last one back until then) and sends
/// them as the round's one attempt.
@MainActor
final class SequenceMemoryStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// The tile lit by the show right now.
    @Published private(set) var lit: Int?
    /// Which flash of the round is showing (1-based for the screen), or nil.
    @Published private(set) var litStep: Int?
    /// The input window is open, by the room or by the phone's own clock.
    @Published private(set) var inputOpen = false
    /// This round's taps.
    @Published private(set) var taps: SequenceTaps?
    /// The tile just tapped, lit briefly as feedback.
    @Published private(set) var pressed: Int?
    /// The attempt is on its way.
    @Published private(set) var sending = false
    /// The server has this round's attempt.
    @Published private(set) var sent = false
    /// The attempt could not be sent; the player can try again.
    @Published private(set) var sendFailed = false

    private let link: GameRoomLink
    private var ticker: FrameTicker?
    private var roundNumber: Int?
    private var lastPhase: GamePhase?
    private var pressTask: Task<Void, Never>?

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

    /// Close the stream and stop the display link.
    func close() {
        link.close()
        stopTicker()
    }

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
        let previous = lastPhase
        lastPhase = next.phase
        if next.phase == .closed {
            room = next
            stopTicker()
            return
        }
        let round = next.memory
        if round?.number != roundNumber {
            roundNumber = round?.number
            taps = round.map { SequenceTaps(round: $0.number, length: $0.length, tiles: next.tiles) }
            sent = false
            sending = false
            sendFailed = false
            lit = nil
            litStep = nil
            inputOpen = false
        }
        // The server has my attempt even if this phone lost the answer.
        if let round, round.answeredIds.contains(next.meId) { sent = true }

        // The result, once per round: did I survive it?
        if next.phase == .result, previous != .result, previous != nil,
           let round, let me = next.me, me.seated, round.attempts?.contains(where: { $0.playerId == me.id }) == true {
            if round.survivorIds?.contains(me.id) == true { SRHaptic.ok() } else { SRHaptic.bad() }
        }
        room = next

        switch next.phase {
        case .show:
            if round?.steps != nil { startTicker() }
        case .input:
            stopTicker()
            lit = nil
            litStep = nil
            inputOpen = true
        default:
            stopTicker()
            lit = nil
            litStep = nil
            inputOpen = false
        }
        #if DEBUG
        // Demo mode: two taps in, so the screenshot shows an attempt under way.
        if SRDemo.isShowcase, next.phase == .input, previous == nil, var demo = taps, demo.taps.isEmpty {
            _ = demo.tap(2)
            _ = demo.tap(0)
            taps = demo
        }
        #endif
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let ticker = FrameTicker { [weak self] target in
            guard let self else { return false }
            return self.frame(at: target)
        }
        self.ticker = ticker
        ticker.start()
    }

    private func stopTicker() {
        ticker?.stop()
        ticker = nil
    }

    /// One display frame, reaching the glass at `target` (monotonic s). False
    /// once the show is over and the ticker can stop.
    private func frame(at target: Double) -> Bool {
        guard let room, room.phase == .show, let round = room.memory, let steps = round.steps,
              let server = link.clock.server(target * 1000) else { return false }
        let now = SequenceSchedule.lit(steps, atServer: server)
        if now?.step != litStep.map({ $0 - 1 }) {
            if let now {
                lit = now.tile
                litStep = now.step + 1
                SRHaptic.select()
            } else {
                lit = nil
                litStep = nil
            }
        }
        if server >= round.inputAt {
            lit = nil
            litStep = nil
            inputOpen = true
            return false
        }
        return true
    }

    // MARK: - Tapping

    /// True while my taps count: the window is open, I am still in, and the
    /// attempt is not complete.
    var canTap: Bool {
        guard let room, inputOpen, let me = room.me, me.joined, me.alive, let taps else { return false }
        return !taps.isComplete && !sent
    }

    func tap(_ tile: Int) {
        guard canTap, var next = taps else { return }
        let outcome = next.tap(tile)
        guard outcome != .ignored else { return }
        taps = next
        SRHaptic.tap()
        pressed = tile
        pressTask?.cancel()
        pressTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            self?.pressed = nil
        }
        if case .complete = outcome { send() }
    }

    func undo() {
        guard canTap, var next = taps else { return }
        guard next.undo() else { return }
        taps = next
        SRHaptic.select()
    }

    /// Send the complete attempt — again, after a failure.
    func send() {
        guard let taps, taps.isComplete, !sending, !sent else { return }
        sending = true
        sendFailed = false
        let body = taps.body()
        Task {
            let outcome = await self.link.post(body)
            self.sending = false
            switch outcome {
            case .ok:
                self.sent = true
            case .wrongPhase:
                // The round closed on the way, or I am out. The snapshot says.
                self.sent = true
                await self.link.refresh()
            case .gone:
                break
            case .refused(let text), .failed(let text):
                self.sendFailed = true
                self.message = text
            }
        }
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
