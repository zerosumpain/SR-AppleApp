import Foundation

/// One Draw & Guess room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns the
/// drawing as the phone holds it (`DrawGuessCanvas`, kept at a revision so the
/// server sends only what is new), the drawer's pen (points batched every
/// ~200 ms while the finger moves, sent one post at a time in order), and the
/// guess box with its feed.
///
/// The drawer sees their own stroke the instant they make it: the pen's live
/// points are drawn over the server's copy until the lift has been sent.
@MainActor
final class DrawGuessStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// The drawing as this phone holds it.
    @Published private(set) var canvas = DrawGuessCanvas()
    /// The drawer's pen: colour, width, and the stroke under the finger.
    @Published private(set) var pen = DrawGuessPen()
    /// Strokes the drawer made that the server has not all of yet, drawn over
    /// its copy (by id) so a line never flickers back while it streams.
    @Published private(set) var unsent: [DrawGuessStroke] = []
    /// What is in the guess box.
    @Published var guessText = ""
    /// A line under the guess box for a moment ("Not so fast", a refusal).
    @Published private(set) var note: String?
    /// Bumped on every refusal; the guess row shakes when it changes.
    @Published private(set) var shakes = 0

    private let link: GameRoomLink
    private var lastPhase: DrawGuessPhase?
    private var lastTurn: Int?
    /// Posts waiting their turn: strokes, undo and clear must land in order.
    /// An item with `finishes` is a stroke's last post (or, with no body, a
    /// marker after it): once it has been answered, that stroke's overlay goes.
    private var queue: [(body: GameActionBody?, finishes: Int?)] = []
    private var pumping = false
    private var batchTask: Task<Void, Never>?
    private var noteTask: Task<Void, Never>?
    private var lastGuessAt: Double?
    private var fetchingWhole = false

    init(roomId: String) {
        self.roomId = roomId
        self.link = GameRoomLink(roomId: roomId)
        link.onRoom = { [weak self] room in self?.apply(room) }
        link.onEnd = { [weak self] in self?.didEnd() }
        link.onNote = { [weak self] update in self?.linkNote(update) }
    }

    /// The server's clock, now, as well as this phone can tell.
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
        let state = next.drawGuess
        let phase = state?.phase ?? .unknown
        let previous = lastPhase
        lastPhase = phase
        let turn = state?.turn?.index
        if turn != lastTurn || phase == .lobby {
            // A new drawing: nothing of mine is in flight for it.
            lastTurn = turn
            unsent = []
            pen.cancel()
            stopBatching()
            guessText = ""
            lastGuessAt = nil
            clearNote()
        }
        if let wire = state?.drawing {
            if canvas.apply(wire) == .gap { fetchWhole() }
        } else {
            canvas.reset()
        }
        if phase != .drawing, pen.isDown {
            pen.cancel()
            stopBatching()
        }
        if phase == .picking, previous != .picking, state?.turn?.drawerId == next.meId { SRHaptic.tap() }
        if phase == .reveal, previous == .drawing { SRHaptic.select() }
        room = next
        #if DEBUG
        // Demo mode: a guess half typed, so the screenshot shows the box in use.
        if SRDemo.isShowcase, previous == nil, phase == .drawing, !isDrawer { guessText = "a sail" }
        #endif
    }

    /// Changes arrived after a revision this phone never had: read the whole room.
    private func fetchWhole() {
        guard !fetchingWhole else { return }
        fetchingWhole = true
        Task {
            await self.link.refresh()
            self.fetchingWhole = false
        }
    }

    // MARK: - What the screen reads

    var state: DrawGuessState? { room?.drawGuess }
    var phase: DrawGuessPhase { state?.phase ?? .unknown }
    var turn: DrawGuessTurn? { state?.turn }

    /// It is my turn to draw.
    var isDrawer: Bool {
        guard let room, let turn else { return false }
        return turn.drawerId == room.meId
    }

    var drawerName: String {
        guard let room, let turn else { return "Someone" }
        return turn.drawerId == room.meId ? "You" : room.name(of: turn.drawerId)
    }

    /// I have guessed this one.
    var solved: Bool {
        guard let room else { return false }
        return turn?.solvers.contains { $0.id == room.meId } ?? false
    }

    var canDraw: Bool { phase == .drawing && isDrawer && room?.me?.joined == true }

    var canGuess: Bool { phase == .drawing && !isDrawer && !solved && room?.me?.joined == true }

    /// What the canvas shows: the server's strokes, my unsent ones over them by
    /// id, and the stroke under my finger on top.
    var strokes: [DrawGuessStroke] {
        var out = canvas.strokes
        for mine in unsent {
            if let at = out.firstIndex(where: { $0.id == mine.id }) {
                out[at] = mine
            } else {
                out.append(mine)
            }
        }
        if let id = pen.strokeId, !pen.live.isEmpty {
            let live = DrawGuessStroke(id: id, color: pen.color, width: pen.width, points: pen.live)
            if let at = out.firstIndex(where: { $0.id == id }) {
                out[at] = live
            } else {
                out.append(live)
            }
        }
        return out
    }

    // MARK: - Drawing

    func pickColor(_ color: String) {
        guard pen.color != color else { return }
        pen.color = color
        SRHaptic.select()
    }

    func pickWidth(_ width: Int) {
        guard pen.width != width else { return }
        pen.width = width
        SRHaptic.select()
    }

    /// The finger lands on the canvas (canvas units).
    func down(at point: DrawGuessPoint) {
        guard canDraw else { return }
        pen.down(at: point)
        startBatching()
    }

    func move(to point: DrawGuessPoint) {
        guard canDraw, pen.isDown else { return }
        pen.move(to: point)
    }

    /// The finger lifts: send the rest, keep the stroke drawn until it lands.
    func up() {
        guard pen.isDown else { return }
        stopBatching()
        let id = pen.strokeId
        let color = pen.color
        let width = pen.width
        let points = pen.live
        let posts = pen.up()
        if let id, !points.isEmpty {
            unsent.removeAll { $0.id == id }
            unsent.append(DrawGuessStroke(id: id, color: color, width: width, points: points))
        }
        for post in posts { enqueue(post.body) }
        if let id { queue.append((body: nil, finishes: id)) }
        pump()
    }

    func undo() {
        guard canDraw else { return }
        if pen.isDown { up() }
        SRHaptic.tap()
        // The last stroke may still be mine, unsent: it goes when the undo lands.
        enqueue(GameActionBody(action: "undo"))
    }

    func clear() {
        guard canDraw else { return }
        if pen.isDown { up() }
        SRHaptic.tap()
        enqueue(GameActionBody(action: "clear"))
    }

    private func startBatching() {
        batchTask?.cancel()
        batchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(DrawGuessPen.batchInterval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                guard self.pen.isDown else { return }
                if let post = self.pen.batch() { self.enqueue(post.body) }
            }
        }
    }

    private func stopBatching() {
        batchTask?.cancel()
        batchTask = nil
    }

    private func enqueue(_ body: GameActionBody) {
        queue.append((body: body, finishes: nil))
        pump()
    }

    /// Send the queue one post at a time, each saying what drawing it holds.
    private func pump() {
        guard !pumping else { return }
        pumping = true
        Task {
            while !self.queue.isEmpty {
                let item = self.queue.removeFirst()
                if var body = item.body {
                    body.since = self.canvas.revision
                    switch await self.link.post(body) {
                    case .ok, .wrongPhase:
                        break
                    case .gone:
                        self.queue.removeAll()
                    case .refused(let text), .failed(let text):
                        self.show(text)
                    }
                }
                // The stroke's last post has been answered: the server's copy
                // (already applied from that answer) is the one to draw.
                if let id = item.finishes { self.unsent.removeAll { $0.id == id } }
            }
            self.pumping = false
        }
    }

    // MARK: - Picking

    func pick(_ index: Int) {
        guard phase == .picking, isDrawer, !busy else { return }
        SRHaptic.tap()
        busy = true
        Task {
            var body = GameActionBody(action: "pick")
            body.index = index
            body.since = self.canvas.revision
            _ = await self.link.post(body)
            self.busy = false
        }
    }

    // MARK: - Guessing

    /// Something typed to send. The 700 ms between guesses is checked on send.
    var canSendGuess: Bool {
        canGuess && !guessText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func sendGuess() {
        guard canGuess else { return }
        let text = guessText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard DrawGuessText.canSend(text, lastSentAt: lastGuessAt, now: GameRoomLink.nowMs()) else {
            show("Not so fast — one guess at a time.")
            return
        }
        lastGuessAt = GameRoomLink.nowMs()
        guessText = ""
        Task {
            var body = GameActionBody(action: "guess")
            body.text = text
            body.since = self.canvas.revision
            switch await self.link.post(body) {
            case .ok:
                if self.solved { SRHaptic.ok() }
            case .refused(let sentence), .failed(let sentence):
                self.show(sentence)
            case .wrongPhase, .gone:
                break
            }
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

    private func clearNote() {
        noteTask?.cancel()
        note = nil
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
