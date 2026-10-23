import Foundation

/// One Odd Artist Out room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns the
/// picture as the phone holds it (`DrawGuessCanvas`, kept at a revision so the
/// server sends only what is new), my one line on my turn (Draw & Guess's pen,
/// in my seat's colour, batched every ~200 ms while the finger moves; the lift
/// is the last post, marked `end`), my vote, and the caught fake's guess.
///
/// My line shows the instant I make it: the pen's live points are drawn over
/// the server's copy until the lift has been answered.
@MainActor
final class FakeArtistStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    @Published private(set) var canvas = DrawGuessCanvas()
    @Published private(set) var pen = DrawGuessPen()
    /// My line while it streams, drawn over the server's copy (by id).
    @Published private(set) var unsent: DrawGuessStroke?
    /// I have lifted my finger this turn: one line is all I get.
    @Published private(set) var lifted = false
    @Published var guessText = ""
    @Published private(set) var note: String?
    @Published private(set) var shakes = 0

    private let link: GameRoomLink
    private var lastPhase: FakeArtistPhase?
    private var lastTurnKey: String?
    private var queue: [(body: GameActionBody, finishes: Bool, retries: Int)] = []
    /// Points of my line queued this turn, against the server's per-line cap.
    private var sentThisLine = 0
    private var pumping = false
    private var batchTask: Task<Void, Never>?
    private var noteTask: Task<Void, Never>?
    private var fetchingWhole = false

    init(roomId: String) {
        self.roomId = roomId
        self.link = GameRoomLink(roomId: roomId)
        link.onRoom = { [weak self] room in self?.apply(room) }
        link.onEnd = { [weak self] in self?.didEnd() }
        link.onNote = { [weak self] update in self?.linkNote(update) }
    }

    func serverNow() -> Double? { link.serverNow() }

    // MARK: - Connection

    func open() { link.open() }

    func close() {
        link.close()
        stopBatching()
    }

    private func didEnd() {
        ended = true
        stopBatching()
        noteTask?.cancel()
    }

    private func linkNote(_ update: GameLinkNote) {
        switch update {
        case .reconnecting: message = "Reconnecting…"
        case .reconnected: if message == "Reconnecting…" { message = nil }
        case .error(let text): message = text
        }
    }

    private func apply(_ next: GameRoom) {
        let state = next.fakeArtist
        let phase = state?.phase ?? .unknown
        let previous = lastPhase
        lastPhase = phase
        // A new turn (or round): a fresh pen, numbered as the server will number
        // the line and inked in my seat's colour. My lift is sent before the
        // answer that moves the turn on, so nothing of mine is in flight here.
        let key = "\(state?.current?.number ?? 0)-\(state?.current?.turn ?? -1)-\(phase == .drawing)"
        let newTurn = key != lastTurnKey
        if newTurn {
            lastTurnKey = key
            pen.cancel()
            stopBatching()
            pen = DrawGuessPen(firstId: state?.lineId ?? 1)
            pen.color = state?.seat(next.meId)?.color ?? "black"
            pen.width = FakeArtistInk.width
            lifted = false
            unsent = nil
            sentThisLine = 0
        }
        if let wire = state?.drawing {
            if canvas.apply(wire) == .gap { fetchWhole() }
        } else {
            canvas.reset()
        }
        if phase != .drawing || state?.myTurn(next.meId) != true, pen.isDown {
            pen.cancel()
            stopBatching()
        }
        if newTurn, phase == .drawing, state?.myTurn(next.meId) == true { SRHaptic.tap() }
        if phase == .reading, previous != .reading { SRHaptic.select() }
        if phase == .reveal, previous != .reveal { SRHaptic.select() }
        if phase != .guessing { guessText = "" }
        room = next
    }

    private func fetchWhole() {
        guard !fetchingWhole else { return }
        fetchingWhole = true
        Task {
            await self.link.refresh()
            self.fetchingWhole = false
        }
    }

    // MARK: - What the screen reads

    var state: FakeArtistState? { room?.fakeArtist }
    var phase: FakeArtistPhase { state?.phase ?? .unknown }
    var current: FakeArtistRound? { state?.current }

    var isMyTurn: Bool {
        guard let room, let state else { return false }
        return state.myTurn(room.meId) && room.me?.joined == true
    }

    /// My finger may draw now: my turn, and I have not lifted yet.
    var canDraw: Bool { isMyTurn && !lifted }

    var artistName: String {
        guard let room, let id = current?.artistId else { return "Someone" }
        return id == room.meId ? "You" : room.name(of: id)
    }

    var fakeName: String {
        guard let room, let id = current?.fakeId else { return "The fake" }
        return id == room.meId ? "You" : room.name(of: id)
    }

    var canVote: Bool {
        phase == .voting && room?.me?.joined == true && current.map { $0.isFake || $0.isArtist } == true
    }

    var canGuess: Bool { phase == .guessing && current?.isFake == true && room?.me?.joined == true }

    /// The server's lines, mine over them while it streams, and the stroke under my finger on top.
    var strokes: [DrawGuessStroke] {
        var out = canvas.strokes
        func put(_ stroke: DrawGuessStroke) {
            if let at = out.firstIndex(where: { $0.id == stroke.id }) {
                if stroke.points.count >= out[at].points.count { out[at] = stroke }
            } else {
                out.append(stroke)
            }
        }
        if let unsent { put(unsent) }
        if let id = pen.strokeId, !pen.live.isEmpty {
            put(DrawGuessStroke(id: id, color: pen.color, width: pen.width, points: pen.live))
        }
        return out
    }

    // MARK: - My line

    func down(at point: DrawGuessPoint) {
        guard canDraw, !pen.isDown else { return }
        sentThisLine = 0
        pen.down(at: point)
        startBatching()
    }

    func move(to point: DrawGuessPoint) {
        guard canDraw, pen.isDown else { return }
        pen.move(to: point)
    }

    /// The finger lifts: the line is done, and so is my turn.
    func up() {
        guard pen.isDown else { return }
        stopBatching()
        let id = pen.strokeId
        let points = pen.live
        let color = pen.color
        let width = pen.width
        let posts = FakeArtistPosts.capped(pen.up(), sent: sentThisLine)
        sentThisLine = posts.sent
        lifted = true
        if let id, !points.isEmpty { unsent = DrawGuessStroke(id: id, color: color, width: width, points: points) }
        let bodies = FakeArtistPosts.lift(posts.posts)
        for (i, body) in bodies.enumerated() { queue.append((body: body, finishes: i == bodies.count - 1, retries: 0)) }
        SRHaptic.select()
        pump()
    }

    private func startBatching() {
        batchTask?.cancel()
        batchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(DrawGuessPen.batchInterval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                guard self.pen.isDown else { return }
                if let post = self.pen.batch() {
                    let capped = FakeArtistPosts.capped([post], sent: self.sentThisLine)
                    self.sentThisLine = capped.sent
                    for p in capped.posts { self.queue.append((body: p.body, finishes: false, retries: 0)) }
                    // A full line lifts itself, as the server does: the turn moves on.
                    if capped.full {
                        self.up()
                        return
                    }
                    self.pump()
                }
            }
        }
    }

    private func stopBatching() {
        batchTask?.cancel()
        batchTask = nil
    }

    /// Send the queue one post at a time, in order, each saying what picture it holds.
    private func pump() {
        guard !pumping else { return }
        pumping = true
        Task {
            while !self.queue.isEmpty {
                let item = self.queue.removeFirst()
                var body = item.body
                body.since = self.canvas.revision
                switch await self.link.post(body) {
                case .ok, .wrongPhase:
                    break
                case .gone:
                    self.queue.removeAll()
                case .failed(let text):
                    // A lift lost on the network would leave the table waiting
                    // out the turn clock, and my finger can't lift twice: send
                    // it again, bare, a couple of times.
                    if item.body.end == true, item.retries < FakeArtistPosts.liftRetries {
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        self.queue.insert((body: FakeArtistPosts.bareLift(), finishes: item.finishes, retries: item.retries + 1), at: 0)
                        continue
                    }
                    self.show(text)
                case .refused(let text):
                    self.show(text)
                }
                if item.finishes { self.unsent = nil }
            }
            self.pumping = false
        }
    }

    // MARK: - Vote and guess

    func vote(for playerId: String) {
        guard canVote, current?.myVote != playerId else { return }
        SRHaptic.tap()
        Task {
            var body = FakeArtistPosts.vote(playerId)
            body.since = self.canvas.revision
            switch await self.link.post(body) {
            case .refused(let text), .failed(let text): self.show(text)
            default: break
            }
        }
    }

    var canSendGuess: Bool { canGuess && FakeArtistPosts.guess(guessText) != nil && !busy }

    func sendGuess() {
        guard canGuess, var body = FakeArtistPosts.guess(guessText) else { return }
        busy = true
        body.since = canvas.revision
        Task {
            switch await self.link.post(body) {
            case .ok: SRHaptic.tap()
            case .refused(let text), .failed(let text): self.show(text)
            case .wrongPhase, .gone: break
            }
            self.busy = false
        }
    }

    private func show(_ text: String) {
        note = text
        shakes += 1
        SRHaptic.bad()
        noteTask?.cancel()
        noteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.note = nil
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
