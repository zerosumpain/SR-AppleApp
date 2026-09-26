import Foundation

/// One Quiz Night room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns my
/// answer: it locks the moment it is tapped (`QuizAnswerLock`), so a second
/// tap never reaches the wire, and is handed back only if the POST never
/// arrived. The server marks it; the reveal says how it went.
///
/// "Play again" is a NEW quiz, not the `again` verb — the server answers that
/// with 409 for Quiz Night. The same settings and the same people go to
/// `POST /api/native/games`, and the screen moves to the room that comes back.
@MainActor
final class QuizNightStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    @Published private(set) var lock = QuizAnswerLock()
    /// A new quiz is being asked for ("Play again", or a lobby whose
    /// questions could not be written).
    @Published private(set) var creating = false

    private let link: GameRoomLink
    private var lastPhase: GamePhase?
    private var lastRevealed: Int?

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

    private func didEnd() { ended = true }

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
        if next.phase == .question, previous != .question { SRHaptic.tap() }
        // The reveal, once per question: a success buzz for a right answer,
        // an error one for a wrong one, nothing for no answer at all.
        if next.phase == .reveal, let question = next.question, lastRevealed != question.index {
            lastRevealed = question.index
            if previous != nil, let mine = question.pick(of: next.meId) {
                if mine.right { SRHaptic.ok() } else { SRHaptic.bad() }
            }
        }
        if next.phase == .lobby, previous == .lobby, room?.prep == .writing {
            if next.prep == .ready { SRHaptic.ok() } else if next.prep == .failed { SRHaptic.bad() }
        }
        room = next
    }

    // MARK: - Answering

    /// What I picked for the question on screen.
    var myChoice: Int? {
        guard let question = room?.question else { return nil }
        return lock.choice(for: question)
    }

    var canAnswer: Bool {
        guard let room else { return false }
        return lock.canAnswer(in: room)
    }

    /// Tap an answer. Locked at once; posted `{action:"answer", question, choice}`.
    func answer(_ choice: Int) {
        guard let room, let question = room.question, lock.canAnswer(in: room),
              choice >= 0, choice < question.options.count else { return }
        let index = question.index
        guard lock.lock(question: index, choice: choice) else { return }
        SRHaptic.select()
        Task {
            switch await self.link.post(QuizAnswerLock.body(question: index, choice: choice)) {
            case .ok, .gone:
                break
            case .wrongPhase:
                // The question closed on the way. The reveal says so.
                await self.link.refresh()
            case .refused(let text), .failed(let text):
                // It never counted: hand the question back while it is open.
                self.lock.release(question: index)
                self.message = text
            }
        }
    }

    // MARK: - Actions

    /// join | leave | start.
    @discardableResult
    func act(_ action: String) async -> Bool {
        busy = true
        defer { busy = false }
        switch await link.post(GameActionBody(action: action)) {
        case .ok:
            return true
        case .gone:
            return false
        case .wrongPhase:
            // Start while jkai is still writing is a 409; the stream carries
            // the truth, so re-read rather than guess.
            await link.refresh()
            return false
        case .refused(let text), .failed(let text):
            message = text
            return false
        }
    }

    /// A new quiz with the same settings and the same people. The room, for
    /// the screen to move to; nil with `message` set when it was refused.
    func playAgain() async -> GameRoom? {
        guard let room, !creating else { return nil }
        creating = true
        defer { creating = false }
        switch await GamesStore.createRoom(QuizNight.playAgain(from: room)) {
        case .created(let next):
            SRHaptic.ok()
            return next
        case .refused(let sentence):
            SRHaptic.bad()
            message = sentence
            return nil
        }
    }
}
