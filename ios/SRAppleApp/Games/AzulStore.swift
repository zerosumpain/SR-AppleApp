import Foundation

/// One Azul room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns what
/// a turn is built from — a source (a factory or the centre) and a colour
/// picked there — and the one move, `take`. Nothing is played ahead of the
/// server: a take is sent, and the board moves when the room that answers it
/// (or the stream) arrives. A take the server refuses (400) shows its
/// sentence for a moment and costs nothing; one that lands after the turn
/// moved on (409: a clock ran out) re-reads the room.
@MainActor
final class AzulStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// Where the picked tiles are, and their colour.
    @Published private(set) var pickedSource: AzulSource?
    @Published private(set) var pickedColour: String?
    /// Why the last take was refused, shown for a moment.
    @Published private(set) var refusal: String?
    /// A take is on its way to the server.
    @Published private(set) var sending = false

    private let link: GameRoomLink
    private var noteTask: Task<Void, Never>?
    private var lastPhase: AzulPhase?
    private var lastTurn: String?

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
        let phase = AzulScreenPhase.of(next)
        let previousPhase = lastPhase
        let previousTurn = lastTurn
        lastPhase = phase
        lastTurn = next.azul?.turnId
        room = next
        if phase == .playing, previousPhase == .countdown { SRHaptic.tap() }
        // The round is tiled: the walls fill on every phone.
        if phase == .scoring, previousPhase == .playing { SRHaptic.select() }
        // The turn moved: whatever was half picked is gone.
        if next.azul?.turnId != previousTurn {
            clearPick()
            if phase == .playing, next.azul?.turnId == next.meId, previousPhase != nil { SRHaptic.ok() }
        }
        // A pick whose tiles have gone from their source is let go.
        if let source = pickedSource, let colour = pickedColour, pickedTiles(source, colour).isEmpty { clearPick() }
        if phase == .finished, previousPhase == .scoring || previousPhase == .playing {
            if next.winnerIds.contains(next.meId) { SRHaptic.ok() } else { SRHaptic.select() }
        }
    }

    // MARK: - What the screen reads

    var state: AzulState? { room?.azul }

    /// True while it is my turn.
    var myTurn: Bool {
        guard let room, let state, AzulScreenPhase.of(room) == .playing else { return false }
        return state.turnId == room.meId && room.me?.joined == true
    }

    /// I am at the table (not watching, not gone).
    var seated: Bool {
        guard let room else { return false }
        return state?.board(room.meId)?.seated == true && room.me?.joined == true
    }

    /// My own board.
    var myBoard: AzulBoard? { room.flatMap { state?.board($0.meId) } }

    /// Everyone else at the table, in the order they move after me.
    var others: [AzulBoard] {
        guard let room, let state else { return [] }
        return state.others(after: room.meId).filter { $0.id != room.meId }
    }

    private func pickedTiles(_ source: AzulSource, _ colour: String) -> [AzulTile] {
        AzulRules.tiles(colour, in: state?.tiles(at: source) ?? [])
    }

    /// The tiles picked up, in their source.
    var picked: [AzulTile] {
        guard let source = pickedSource, let colour = pickedColour else { return [] }
        return pickedTiles(source, colour)
    }

    /// The ids picked, for lifting them where they lie.
    var pickedIds: Set<Int> { Set(picked.map(\.id)) }

    /// The first take from the centre brings the marker with it.
    var takesMarker: Bool { pickedSource == .centre && state?.firstInCentre == true }

    /// My lines lit for the picked colour (the floor is always open).
    var litLines: Set<Int> {
        guard myTurn, let colour = pickedColour, let state else { return [] }
        return AzulRules.litLines(state.canPlace, colour: colour)
    }

    /// Every place the picked tiles may go, with what would happen there.
    var destinations: [AzulDestination] {
        guard myTurn, let colour = pickedColour, let state, let board = myBoard, !picked.isEmpty else { return [] }
        return AzulRules.destinations(for: colour, count: picked.count, board: board, canPlace: state.canPlace,
                                      marker: takesMarker)
    }

    var canTake: Bool { myTurn && !sending }

    // MARK: - Picking

    /// A tile tapped in a factory or the centre: every tile of its colour
    /// there is picked up. The same again puts them back.
    func pick(_ source: AzulSource, colour: String) {
        guard myTurn, colour != AzulRules.marker else { return }
        if pickedSource == source, pickedColour == colour {
            clearPick()
        } else {
            pickedSource = source
            pickedColour = colour
        }
        SRHaptic.select()
        clearNotes()
    }

    /// A tap anywhere else: put the tiles back.
    func cancel() {
        guard pickedSource != nil else { return }
        clearPick()
        SRHaptic.select()
    }

    func clearPick() {
        pickedSource = nil
        pickedColour = nil
    }

    // MARK: - The move

    /// Lay the picked tiles on a line or the floor: one whole turn.
    func place(_ line: AzulLine) {
        guard canTake, let source = pickedSource, let colour = pickedColour, !picked.isEmpty else { return }
        if case .line(let i) = line, !litLines.contains(i) {
            refuse(lineRefusal(i, colour: colour))
            return
        }
        var body = GameActionBody(action: "take")
        switch source {
        case .centre: body.source = .named("centre")
        case .factory(let i): body.source = .id(i)
        }
        body.colour = colour
        switch line {
        case .floor: body.line = .named("floor")
        case .line(let i): body.line = .id(i)
        }
        send(body)
    }

    /// Why a line that is not lit cannot take the colour — the server's words.
    private func lineRefusal(_ i: Int, colour: String) -> String {
        guard let board = myBoard, board.lines.indices.contains(i) else { return "Pick a pattern line or the floor." }
        let line = board.lines[i]
        if line.count >= i + 1 { return "That line is full." }
        if let held = line.first?.c, held != colour { return "That line is collecting \(held)." }
        return "Your wall already has \(colour) in that row."
    }

    private func send(_ body: GameActionBody) {
        sending = true
        SRHaptic.tap()
        Task {
            let outcome = await self.link.post(body)
            self.sending = false
            switch outcome {
            case .ok:
                self.clearPick()
                self.clearNotes()
            case .refused(let sentence):
                self.refuse(sentence)
            case .wrongPhase:
                self.clearPick()
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

/// Which of the screen's pages a room is on: Azul's own phase when the room
/// carries it (`scoring` is Azul's alone), else the shared phase.
enum AzulScreenPhase {
    static func of(_ room: GameRoom) -> AzulPhase {
        if let phase = room.azul?.phase, phase != .unknown { return phase }
        switch room.phase {
        case .lobby: return .lobby
        case .countdown: return .countdown
        case .playing: return .playing
        case .finished: return .finished
        case .closed: return .closed
        default: return .unknown
        }
    }
}

/// The new-game sheet's Azul: the level (the live turn clock) and the table.
/// The pace is added by the sheet, as for every durable game.
struct AzulSettings: Equatable {
    var difficulty: GameDifficulty
    var table: AzulTable = .phones

    func createBody(invite: [String]) -> CreateGameBody {
        var body = CreateGameBody(game: GameKind.azul.rawValue, difficulty: difficulty.rawValue, invite: invite)
        body.table = table.rawValue
        return body
    }
}
