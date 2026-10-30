import SwiftUI

/// A burst of sparks over a foundation when a card lands on it.
struct SolitaireBurst: Identifiable, Equatable {
    let id: Int
    let foundation: Int
    let born: Date
    /// A king: the suit is complete, and the burst is bigger.
    let big: Bool
}

/// The hint on show: the cards to move glow, and so does where they go.
struct SolitaireHintMark: Equatable {
    let action: SolitaireAction
    let cards: Set<Int>
    /// Nil for a draw (the stock glows instead).
    let target: SolitairePlace?
}

/// Solitaire on this phone: the game in progress, the stats and settings,
/// and everything that happens between taps — the deal flying out, the
/// clock, the hint, the finish, the sparks and the win. Moves themselves are
/// `SolitaireSession`'s; this decides when they may happen and what the
/// table does about them.
@MainActor
final class SolitaireGame: ObservableObject {
    enum Stage: Equatable {
        /// The intro card: how to play, the settings, carry on or deal.
        case intro
        /// The solver is looking for a deal that can be won.
        case shuffling
        case playing
        case paused
        case won
    }

    @Published private(set) var session: SolitaireSession
    @Published private(set) var stage: Stage = .intro
    @Published private(set) var stats: SolitaireStats
    @Published var settings: SolitaireSettings {
        didSet { if settings != oldValue { store.save(settings) } }
    }
    /// A game was left half-played and can be carried on.
    @Published private(set) var canCarryOn: Bool
    @Published private(set) var hint: SolitaireHintMark?
    /// Cards mid-move, drawn over everything until they land.
    @Published private(set) var flying: Set<Int> = []
    /// Cards still in the dealer's hand while a deal flies out.
    @Published private(set) var undealt: Set<Int> = []
    @Published private(set) var bursts: [SolitaireBurst] = []
    /// A nudge for a card that cannot go anywhere: its count goes up by one.
    @Published private(set) var shakes: [Int: Int] = [:]
    /// Nothing useful is left on the table.
    @Published private(set) var stuck = false
    /// The finish is playing every card home.
    @Published private(set) var finishing = false
    /// The cards are bouncing off the foundations.
    @Published private(set) var celebrating = false
    /// The results card is up.
    @Published private(set) var showResults = false
    @Published private(set) var record = SolitaireRecord()

    private let store: SolitaireStore
    /// When the clock last started; nil while it is stopped.
    private var clockStart: Date?
    private var shuffleTask: Task<Void, Never>?
    private var dealTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var winTask: Task<Void, Never>?
    private var hintTask: Task<Void, Never>?
    private var flyTask: Task<Void, Never>?
    private var lastTap: (id: Int, at: Date)?
    private var burstSerial = 0
    private var hintCursor = 0
    private var unsaved = 0

    init(store: SolitaireStore = SolitaireStore()) {
        self.store = store
        let settings = store.loadSettings()
        self.settings = settings
        self.stats = store.loadStats()
        if let saved = store.loadGame() {
            session = saved
            canCarryOn = true
        } else {
            // A fresh deal behind the intro card; not counted until it is played.
            session = SolitaireSession(seed: SolitaireRandom.freshSeed(), drawMode: settings.drawMode)
            canCarryOn = false
        }
    }

    var state: SolitaireState { session.state }
    var isPlaying: Bool { stage == .playing && undealt.isEmpty }
    var canUndo: Bool { isPlaying && session.canUndo && !finishing }
    var canFinish: Bool { isPlaying && state.canAutoComplete && !finishing }

    // MARK: - The clock

    var clockRunning: Bool { clockStart != nil }

    /// Seconds played so far, including the running stretch.
    var elapsedNow: Double {
        session.elapsed + (clockStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func startClock() {
        guard clockStart == nil, stage == .playing, session.started, !session.won else { return }
        clockStart = Date()
    }

    private func stopClock() {
        guard let start = clockStart else { return }
        session.elapsed += Date().timeIntervalSince(start)
        clockStart = nil
    }

    // MARK: - Starting and stopping

    /// Back to the game left half-played.
    func carryOn() {
        SRHaptic.tap()
        stage = .playing
        startClock()
        refreshStuck()
    }

    /// A new deal: a winnable one if asked for, found off the main thread.
    func newDeal() {
        abandonIfStarted()
        cancelWork()
        if settings.winnableOnly {
            stage = .shuffling
            let mode = settings.drawMode
            let first = SolitaireRandom.freshSeed()
            shuffleTask = Task { [weak self] in
                let started = Date()
                let pick = await SolitaireDealer.pickInBackground(drawMode: mode, firstSeed: first, seconds: 3)
                // Long enough to read, so the card does not just flicker.
                let shown = Date().timeIntervalSince(started)
                if shown < 0.6 { try? await Task.sleep(nanoseconds: UInt64((0.6 - shown) * 1_000_000_000)) }
                guard !Task.isCancelled, let self, self.stage == .shuffling else { return }
                self.begin(seed: pick.seed, proven: pick.proven)
            }
        } else {
            begin(seed: SolitaireRandom.freshSeed(), proven: false)
        }
    }

    /// Stop looking for a winnable deal and play any.
    func dealAnyway() {
        shuffleTask?.cancel()
        shuffleTask = nil
        begin(seed: SolitaireRandom.freshSeed(), proven: false)
    }

    /// The same cards again from the start.
    func restartDeal() {
        cancelWork()
        clockStart = nil
        session.restart()
        resetTable()
        stage = .playing
        dealOut()
        save()
    }

    private func begin(seed: UInt64, proven: Bool) {
        cancelWork()
        clockStart = nil
        session = SolitaireSession(seed: seed, drawMode: settings.drawMode, proven: proven)
        resetTable()
        canCarryOn = false
        stage = .playing
        store.clearGame()
        dealOut()
    }

    private func resetTable() {
        hint = nil
        stuck = false
        finishing = false
        celebrating = false
        showResults = false
        record = SolitaireRecord()
        bursts = []
        flying = []
        hintCursor = 0
    }

    /// The deal flies out of the stock one card at a time, row by row.
    private func dealOut() {
        let order = session.state.dealOrder
        undealt = Set(order)
        dealTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            for id in order {
                guard !Task.isCancelled, let self else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    _ = self.undealt.remove(id)
                }
                try? await Task.sleep(nanoseconds: 26_000_000)
            }
            guard let self else { return }
            self.undealt = []
            SRHaptic.select()
        }
    }

    /// A started game left for a new one ends the streak.
    private func abandonIfStarted() {
        if session.started && !session.won && session.counted {
            stats.recordAbandon()
            store.save(stats)
        }
    }

    func pause() {
        guard stage == .playing else { return }
        finishTask?.cancel()
        finishing = false
        stopClock()
        stage = .paused
        save()
    }

    func resume() {
        guard stage == .paused else { return }
        SRHaptic.tap()
        stage = .playing
        startClock()
    }

    /// Off screen: everything stops and the game is kept.
    func leave() {
        if stage == .playing { pause() }
        if stage == .shuffling { stage = .intro }
        cancelWork()
        undealt = []
        save()
    }

    /// The menu from the results card.
    func backToIntro() {
        canCarryOn = false
        stage = .intro
    }

    private func cancelWork() {
        shuffleTask?.cancel()
        dealTask?.cancel()
        finishTask?.cancel()
        winTask?.cancel()
        hintTask?.cancel()
        flyTask?.cancel()
        shuffleTask = nil
        dealTask = nil
        finishTask = nil
        winTask = nil
        undealt = []
        finishing = false
    }

    /// Keeps the game for next time, mid-game only.
    private func save() {
        unsaved = 0
        // A deal started again has no moves yet but is still this game: keep
        // it, so an older save from before the restart is not what comes back.
        guard !session.won, session.started || session.counted else {
            store.clearGame()
            return
        }
        var copy = session
        copy.elapsed = elapsedNow
        store.saveGame(copy)
    }

    // MARK: - Touches

    /// A tap on a card: home if it can go, else the best column; a second
    /// tap straight after sends it home if it can go there now.
    func tap(_ id: Int) {
        guard isPlaying, !finishing else { return }
        let now = Date()
        if let last = lastTap, last.id == id, now.timeIntervalSince(last.at) < 0.4 {
            // The second tap of a double-tap: home if it can go now, else
            // nothing. (The first tap has often sent it home already, and a
            // plain tap on a foundation card would bring it straight back down.)
            lastTap = nil
            if let home = state.foundationAction(forCard: id) {
                withAnimation(Self.motion) { _ = perform(home) }
            }
            return
        }
        // A tap on the stock turns that card onto the waste, and a quick tap on
        // it there is a new tap, not the second half of a double-tap.
        var fromStock = false
        if let found = state.locate(id), case .stock = found.place { fromStock = true }
        if fromStock {
            lastTap = nil
        } else {
            lastTap = (id: id, at: now)
        }
        if let action = state.bestAction(forCard: id) {
            withAnimation(Self.motion) { _ = perform(action) }
        } else {
            nudge(id)
        }
    }

    /// A tap on the stock's empty place: turn the waste back over.
    func tapStock() {
        guard isPlaying, !finishing else { return }
        withAnimation(Self.motion) { _ = perform(.draw) }
    }

    /// The cards a finger on `id` lifts, if it may lift them.
    func pickUp(_ id: Int) -> [Int]? {
        guard isPlaying, !finishing, let found = state.locate(id) else { return nil }
        switch found.place {
        case .stock:
            return nil
        case .waste:
            return found.index == state.waste.count - 1 ? [id] : nil
        case .foundation(let f):
            return found.index == state.foundations[f].count - 1 ? [id] : nil
        case .tableau(let t):
            let pile = state.tableau[t]
            guard pile.isFaceUp(found.index) else { return nil }
            return pile.cards[found.index...].map(\.id)
        }
    }

    /// The cards lifted with `id` were let go over `targets` (best first).
    /// The caller wraps this in the animation that carries them there, or
    /// back where they came from.
    func drop(_ id: Int, on targets: [SolitairePlace]) {
        guard isPlaying, let found = state.locate(id), !targets.isEmpty else { return }
        let count = state.cards(at: found.place).count - found.index
        for target in targets {
            var destination = target
            // Any foundation will do: the card goes to its own suit's.
            if case .foundation = target { destination = .foundation(SolitaireCard(id: id).suit.rawValue) }
            // Let go over where it started: put back, no fuss.
            if destination == found.place { return }
            let move = SolitaireMove(from: found.place, to: destination, count: count)
            if perform(.move(move)) { return }
        }
        SRHaptic.bad()
    }

    func draw() {
        guard isPlaying, !finishing else { return }
        withAnimation(Self.motion) { _ = perform(.draw) }
    }

    func undo() {
        guard canUndo else { return }
        SRHaptic.select()
        withAnimation(Self.motion) {
            let before = session.state
            if session.undo() { markFlying(before: before, after: session.state) }
        }
        hint = nil
        hintCursor = 0
        refreshStuck()
        startClock()
    }

    /// The next useful move glows; asking again shows the one after.
    func showHint() {
        guard isPlaying, !finishing else { return }
        let hints = state.hints()
        guard !hints.isEmpty else {
            stuck = true
            SRHaptic.bad()
            return
        }
        let action = hints[hintCursor % hints.count]
        hintCursor += 1
        session.hintsUsed += 1
        SRHaptic.select()
        withAnimation(.easeOut(duration: 0.2)) { hint = mark(for: action) }
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.hint = nil }
        }
    }

    private func mark(for action: SolitaireAction) -> SolitaireHintMark {
        switch action {
        case .draw, .turnOne:
            let top = state.stock.last.map { Set([$0.id]) } ?? []
            return SolitaireHintMark(action: action, cards: top, target: nil)
        case .move(let move):
            let cards = state.cards(at: move.from).suffix(move.count).map(\.id)
            return SolitaireHintMark(action: action, cards: Set(cards), target: move.to)
        }
    }

    /// Plays every card home, one after another.
    func finish() {
        guard canFinish else { return }
        finishing = true
        hint = nil
        SRHaptic.tap()
        finishTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.stage == .playing, let action = self.state.autoCompleteAction() else { break }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    _ = self.perform(action, finishing: true)
                }
                try? await Task.sleep(nanoseconds: 75_000_000)
            }
            self?.finishing = false
        }
    }

    // MARK: - After a move

    static let motion = Animation.spring(response: 0.34, dampingFraction: 0.84)

    /// Plays `action` and does everything that follows from it.
    @discardableResult
    private func perform(_ action: SolitaireAction, finishing: Bool = false) -> Bool {
        guard stage == .playing, undealt.isEmpty else { return false }
        guard finishing || !self.finishing else { return false }
        let before = session.state
        guard session.perform(action) else { return false }
        let after = session.state

        if !session.counted {
            session.counted = true
            stats.recordStart()
            store.save(stats)
        }
        startClock()
        hint = nil
        hintCursor = 0
        markFlying(before: before, after: after)

        switch action {
        case .draw, .turnOne:
            if !finishing { SRHaptic.select() }
        case .move(let move):
            if case .foundation(let f) = move.to {
                let king = after.foundations[f].count == 13
                addBurst(f, big: king)
                if king { SRHaptic.ok() } else if !finishing { SRHaptic.tap() }
            } else {
                SRHaptic.tap()
            }
        }

        if after.isWon {
            win()
            return true
        }
        refreshStuck()
        unsaved += 1
        if unsaved >= 8 { save() }
        // Nothing left to decide: every card showing and the stock spent.
        if !finishing && after.canAutoComplete && after.stock.isEmpty && after.waste.isEmpty {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.finish()
            }
        }
        return true
    }

    /// Cards that changed place ride above the rest until they land.
    private func markFlying(before: SolitaireState, after: SolitaireState) {
        var moved = Set<Int>()
        var places: [SolitairePlace] = [.stock, .waste]
        for f in 0..<4 { places.append(.foundation(f)) }
        for t in 0..<7 { places.append(.tableau(t)) }
        for place in places {
            let was = before.cards(at: place).map(\.id)
            let now = after.cards(at: place).map(\.id)
            if was != now {
                let common = zip(was, now).prefix { $0 == $1 }.count
                moved.formUnion(now.dropFirst(common))
            }
        }
        flying = moved
        flyTask?.cancel()
        flyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self?.flying = []
        }
    }

    private func addBurst(_ foundation: Int, big: Bool) {
        burstSerial += 1
        let now = Date()
        bursts = bursts.filter { now.timeIntervalSince($0.born) < SolitaireSparks.life } +
            [SolitaireBurst(id: burstSerial, foundation: foundation, born: now, big: big)]
        let serial = burstSerial
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SolitaireSparks.life * 1_000_000_000) + 50_000_000)
            guard let self, self.burstSerial == serial else { return }
            self.bursts = []
        }
    }

    private func nudge(_ id: Int) {
        SRHaptic.bad()
        withAnimation(.linear(duration: 0.32)) {
            shakes[id, default: 0] += 1
        }
    }

    private func refreshStuck() {
        let now = state.isStuck
        if now != stuck { withAnimation(.snappy(duration: 0.25)) { stuck = now } }
    }

    // MARK: - The win

    private func win() {
        stopClock()
        finishTask?.cancel()
        finishing = false
        stuck = false
        record = stats.recordWin(mode: session.drawMode, time: session.elapsed, moves: session.moves)
        store.save(stats)
        store.clearGame()
        canCarryOn = false
        stage = .won
        SRHaptic.ok()
        winTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled, let self else { return }
            self.celebrating = true
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.3)) { self.showResults = true }
        }
    }

    /// A tap during the cascade brings the results straight up.
    func skipCelebration() {
        guard stage == .won, !showResults else { return }
        winTask?.cancel()
        celebrating = true
        withAnimation(.snappy(duration: 0.3)) { showResults = true }
    }
}
