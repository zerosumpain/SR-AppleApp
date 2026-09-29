import Foundation

/// One Categories room, live.
///
/// The connection is `GameRoomLink`, the same as every game's. This owns my
/// drafts — what is in each field as I type — and sends each one a moment after
/// the typing stops (or at once on Return), so the server always holds nearly
/// what the screen shows and time running out loses at most the last word. An
/// answer is never refused for its letter: the field warns, the review judges.
/// In the review it owns the vetoes I am casting, and my "done".
@MainActor
final class CategoriesStore: ObservableObject, GameRoomStoring {
    let roomId: String

    @Published private(set) var room: GameRoom?
    /// The room is gone (404) or closed.
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// What is in each field, by category index.
    @Published private(set) var drafts: [Int: String] = [:]

    private let link: GameRoomLink
    private var lastPhase: GamePhase?
    /// The letter and card the drafts belong to; a new deal clears them.
    private var dealt: String?
    /// The text the server last took for each slot.
    private var sent: [Int: String] = [:]
    /// A send waiting for the typing to stop, per slot.
    private var pending: [Int: Task<Void, Never>] = [:]
    /// Vetoes on their way, so a double tap sends one.
    private var vetoing: Set<String> = []

    /// How long after the last keystroke a draft is sent.
    static let settleNanoseconds: UInt64 = 600_000_000

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

    func close() {
        flush()
        link.close()
    }

    private func didEnd() {
        ended = true
        for task in pending.values { task.cancel() }
        pending = [:]
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
        // A new deal ("Play again", or the first one): the drafts are the
        // server's — empty, or what it kept if this phone is rejoining.
        let deal = next.letter.map { "\($0)|\((next.categories ?? []).joined(separator: "|"))" }
        if deal != dealt {
            dealt = deal
            for task in pending.values { task.cancel() }
            pending = [:]
            let mine = next.me?.categoryAnswers ?? []
            drafts = Dictionary(mine.map { ($0.index, $0.text) }, uniquingKeysWith: { _, last in last })
            sent = drafts
            vetoing = []
        }
        if next.phase == .playing, previous == .countdown { SRHaptic.tap() }
        if next.phase == .review, previous == .playing { SRHaptic.ok() }
        room = next
        #if DEBUG
        // Demo mode: a half-typed answer, so the screenshot shows the warning.
        if SRDemo.isShowcase, next.phase == .playing, previous == nil, let slot = next.categories?.indices.last {
            drafts[slot] = "Pumpkin"
        }
        #endif
    }

    // MARK: - Answering

    /// True while I can write answers: playing, in, card dealt.
    var canPlay: Bool {
        guard let room, room.phase == .playing, room.me?.joined == true, room.categories != nil else { return false }
        return true
    }

    func draft(_ index: Int) -> String { drafts[index] ?? "" }

    /// How many of my slots have something in them, as the screen shows it.
    var filled: Int { drafts.values.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count }

    /// A keystroke in field `index`. Sent once the typing settles.
    func edit(_ index: Int, _ text: String) {
        guard canPlay, let room else { return }
        let capped = CategoriesRules.cap(text, max: room.maxAnswer)
        guard drafts[index] != capped else { return }
        drafts[index] = capped
        pending[index]?.cancel()
        pending[index] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.settleNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.send(index)
        }
    }

    /// Return in a field, or leaving it: send now.
    func commit(_ index: Int) {
        pending[index]?.cancel()
        pending[index] = nil
        Task { await self.send(index) }
    }

    /// Every draft not yet sent, now — the clock is nearly out, or the screen is going.
    func flush() {
        for index in drafts.keys where pending[index] != nil { commit(index) }
    }

    private func send(_ index: Int) async {
        pending[index] = nil
        guard canPlay else { return }
        let text = (drafts[index] ?? "").trimmingCharacters(in: .whitespaces)
        guard sent[index] != text else { return }
        sent[index] = text
        switch await link.post(GameActionBody(action: "answer", index: index, text: text)) {
        case .ok, .gone:
            break
        case .wrongPhase:
            // Time's up: the stream carries the review.
            sent[index] = nil
        case .refused(let sentence), .failed(let sentence):
            sent[index] = nil
            message = sentence
        }
    }

    // MARK: - The review

    /// Tap someone else's answer: veto it, or take my veto back.
    func toggleVeto(owner: GamePlayer, answer: CategoriesAnswer) {
        guard let room, CategoriesRules.canVeto(answer, ownerId: owner.id, room: room) else { return }
        let key = "\(owner.id):\(answer.index)"
        guard !vetoing.contains(key) else { return }
        vetoing.insert(key)
        SRHaptic.select()
        let action = answer.vetoed ? "unveto" : "veto"
        Task {
            let outcome = await self.link.post(GameActionBody(action: action, index: answer.index, playerId: owner.id))
            self.vetoing.remove(key)
            switch outcome {
            case .ok, .gone:
                break
            case .wrongPhase:
                await self.link.refresh()
            case .refused(let text), .failed(let text):
                self.message = text
            }
        }
    }

    /// I have seen enough; the review ends when everyone has.
    func finishReview() {
        guard room?.phase == .review, room?.me?.done == false else { return }
        SRHaptic.tap()
        Task { _ = await self.act("done") }
    }

    // MARK: - Actions

    /// join | leave | start | again | done.
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
