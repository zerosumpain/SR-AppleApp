import Foundation

/// One Quick Maths Sprint room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns the
/// answer being typed on the keypad and what the server made of the last one.
/// The server never says "right" or "wrong": a right answer moves my problem
/// on, a wrong one counts a miss and leaves the same problem in front of me
/// (`SprintVerdict`). A wrong one shakes the problem and clears the keypad.
@MainActor
final class MathsSprintStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// The answer on the keypad.
    @Published private(set) var input = SprintInput()
    /// An answer is on its way to the server.
    @Published private(set) var submitting = false
    /// Bumped on every wrong answer; the problem shakes when it changes.
    @Published private(set) var shakes = 0
    /// The wrong answer just given, shown for a moment ("Not 54").
    @Published private(set) var wrongValue: Int?
    /// Bumped each time a streak reaches a bonus; the streak flares.
    @Published private(set) var bonuses = 0

    private let link: GameRoomLink
    private var noteTask: Task<Void, Never>?
    private var lastPhase: GamePhase?

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
        let previous = lastPhase
        lastPhase = next.phase
        if next.phase == .playing, previous == .countdown { SRHaptic.tap() }
        // A new game in the same room ("Play again") starts with a clean keypad.
        if next.phase != .playing, previous == .playing || previous == .finished {
            input.clear()
            wrongValue = nil
        }
        room = next
        #if DEBUG
        // Demo mode: an answer half typed, so the screenshot shows the keypad in use.
        if SRDemo.isOn, next.phase == .playing, previous == nil, input.isEmpty {
            input.press(5)
        }
        #endif
    }

    // MARK: - The keypad

    /// True while I can answer: playing, in, and a problem in front of me.
    var canAnswer: Bool {
        guard let room, room.phase == .playing, room.me?.joined == true else { return false }
        return room.sprint?.problem != nil
    }

    func press(_ digit: Int) {
        guard canAnswer else { return }
        if input.press(digit) {
            SRHaptic.tap()
            wrongValue = nil
        }
    }

    func toggleSign() {
        guard canAnswer else { return }
        input.toggleSign()
        SRHaptic.tap()
    }

    func delete() {
        guard canAnswer else { return }
        if input.delete() { SRHaptic.tap() }
    }

    /// Go. An answer with no digits never reaches the server.
    func submit() {
        guard canAnswer, !submitting, let room, let problem = room.sprint?.problem, let value = input.value else { return }
        let before = room.sprint
        submitting = true
        // Cleared now: right, the next problem wants an empty keypad; wrong,
        // the same problem does too.
        input.clear()
        Task {
            let outcome = await self.link.post(MathsSprint.body(index: problem.index, value: value))
            self.submitting = false
            switch outcome {
            case .ok:
                self.judge(SprintVerdict.judge(sentIndex: problem.index, before: before, after: self.room?.sprint), value: value)
            case .wrongPhase:
                // A stale index, or the time is up. The snapshot says which.
                await self.link.refresh()
            case .refused(let text), .failed(let text):
                self.message = text
            case .gone:
                break
            }
        }
    }

    private func judge(_ verdict: SprintVerdict, value: Int) {
        switch verdict {
        case .right:
            wrongValue = nil
            let streak = room?.sprint?.streak ?? 0
            if MathsSprint.onBonus(streak: streak, every: room?.streakBonus ?? 5) {
                bonuses += 1
                SRHaptic.ok()
            } else {
                SRHaptic.select()
            }
        case .wrong:
            wrongValue = value
            shakes += 1
            SRHaptic.bad()
            noteTask?.cancel()
            noteTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                self?.wrongValue = nil
            }
        case .unknown:
            break
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
