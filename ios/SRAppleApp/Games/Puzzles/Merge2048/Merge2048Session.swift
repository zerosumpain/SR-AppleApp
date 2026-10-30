import SwiftUI

/// A tile as the board draws it: on the board, or merged away and sliding
/// onto the tile that took it, for the length of one slide.
struct Merge2048Sprite: Identifiable, Equatable {
    let tile: Merge2048Tile
    let leaving: Bool

    var id: Int { tile.id }
}

/// Points just scored, for the "+16" that rises off the score.
struct Merge2048Gain: Equatable {
    let id: Int
    let amount: Int
}

/// 2048 on this phone: the game in progress for the chosen board, the card
/// between games, the bests, and the feedback each move gives. The rules are
/// `Merge2048State`'s; this decides what the screen shows and when.
///
/// Nothing here ticks. A move is a published change the board animates; the
/// sparks layer's timeline runs only while a burst is in the air.
@MainActor
final class Merge2048Session: ObservableObject {
    enum Stage: Equatable {
        /// The how-to-play card and the board picker.
        case intro
        case playing
        case paused
        /// The winning tile was just made: Keep going, or a new game.
        case won
        /// No move is left.
        case over
    }

    @Published private(set) var size: Merge2048Size
    @Published private(set) var state: Merge2048State
    @Published private(set) var sprites: [Merge2048Sprite] = []
    @Published private(set) var stage: Stage = .intro
    @Published private(set) var book: Merge2048Book
    /// This game has beaten the best score it started against.
    @Published private(set) var newBest = false
    @Published private(set) var gain: Merge2048Gain?
    /// Counts the swipes that moved nothing; the board shakes on each.
    @Published private(set) var bumps = 0
    @Published private(set) var sparks: [Merge2048Spark] = []
    @Published private(set) var sparksLive = false
    /// The boards with a game left part-way, for "Carry on".
    @Published private(set) var saved: Set<Merge2048Size> = []
    /// Bumped whenever a different game is put on the board. Tile ids start
    /// again at 1 in every game, so the board view is keyed on this: a new
    /// game's tiles grow in fresh instead of sliding out of the old game's.
    @Published private(set) var round = 0

    /// Demo mode plays the same board every time, for the screenshots.
    let scripted = SRDemo.isOn
    /// Sparks and confetti are off under Reduce Motion; the screen says so.
    var calm = false

    private let store = Merge2048Store()
    private var gainCounter = 0
    private var bestAtStart = 0
    /// Between the last move and the end card: input waits.
    private var settling = false
    private var leavingTask: Task<Void, Never>?
    private var sparksTask: Task<Void, Never>?
    private var endTask: Task<Void, Never>?
    /// The card `settle` is waiting to show.
    private var pendingStage: Stage?

    init() {
        let store = Merge2048Store()
        let size = store.loadSize()
        self.size = size
        book = store.loadBook()
        state = store.loadGame(size)
            ?? Merge2048State(size: size, seed: SRDemo.isOn ? 2048 : UInt64.random(in: 1...UInt64.max))
        refreshSaved()
        sprites = Self.sprites(state.tiles)
    }

    // MARK: - Reading

    var record: Merge2048Record { book.record(size) }
    var best: Int { max(record.bestScore, state.score) }
    var hasSavedGame: Bool { saved.contains(size) }
    var canUndo: Bool { state.canUndo && !settling && (stage == .playing || stage == .over) }
    var accepting: Bool { stage == .playing && !settling }

    // MARK: - Between games

    /// Pick a board on the intro card: its game in progress, or a fresh one.
    func choose(_ next: Merge2048Size) {
        guard next != size else { return }
        size = next
        store.saveSize(next)
        clearFeedback()
        replace(with: store.loadGame(next) ?? fresh(next))
    }

    /// Carry on with the game on the board (or start it, if it is new).
    func play() {
        bestAtStart = record.bestScore
        newBest = false
        if state.isOver { replace(with: fresh(size)) }
        stage = .playing
        save()
    }

    /// Set the board aside and start again on the same size.
    func newGame() {
        closeGame()
        clearFeedback()
        replace(with: fresh(size))
        bestAtStart = record.bestScore
        newBest = false
        stage = .playing
        save()
    }

    /// Back to the intro card to pick another board. A finished game counts
    /// now; one still going waits on its board for next time.
    func changeBoard() {
        if stage == .over {
            closeGame()
            replace(with: fresh(size))
        } else {
            save()
        }
        clearFeedback()
        refreshSaved()
        stage = .intro
    }

    func pause() {
        guard stage == .playing else { return }
        save()
        stage = .paused
    }

    func resume() {
        guard stage == .paused else { return }
        stage = .playing
    }

    /// After the win card: play on past the target. If the winning move also
    /// filled the board for good, there is nothing to play on with, so the
    /// end card comes up instead of a board that only shakes.
    func keepGoing() {
        guard stage == .won else { return }
        if state.isOver {
            SRHaptic.bad()
            stage = .over
        } else {
            stage = .playing
        }
    }

    /// The app is going to the background, or the screen is closing: the game
    /// is saved and, if it was being played, paused.
    func sleep() {
        land()
        if stage == .playing { stage = .paused }
        save()
        sparksLive = false
        sparks = []
    }

    /// The screen is closing. A finished game counts now; one still going is
    /// kept on its board for next time.
    func leave() {
        land()
        if state.isOver && state.moves > 0 {
            closeGame()
            replace(with: fresh(size))
            stage = .intro
        } else {
            save()
        }
        sparksLive = false
        sparks = []
    }

    /// An end card still waiting on the last slide comes up at once.
    private func land() {
        endTask?.cancel()
        settling = false
        if let next = pendingStage {
            pendingStage = nil
            stage = next
        }
    }

    // MARK: - Playing

    /// One swipe or arrow.
    func move(_ direction: Merge2048Direction) {
        guard accepting else { return }
        guard let turn = state.move(direction) else {
            bumps += 1
            return
        }
        leavingTask?.cancel()
        sprites = Self.sprites(state.tiles) + turn.consumed.map { Merge2048Sprite(tile: $0, leaving: true) }
        leavingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((Merge2048Motion.slide + 0.03) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.sprites = Merge2048Session.sprites(self.state.tiles)
        }

        if turn.gained > 0 {
            gainCounter += 1
            gain = Merge2048Gain(id: gainCounter, amount: turn.gained)
        }
        feel(turn)
        burst(turn)

        book.note(size: size, score: state.score, biggest: state.biggest)
        if bestAtStart > 0 && state.score > bestAtStart { newBest = true }
        store.saveBook(book)
        save()

        if turn.reachedTarget {
            settle(into: .won, after: 0.45)
        } else if turn.over {
            SRHaptic.bad()
            settle(into: .over, after: 0.6)
        }
    }

    /// Take back the last move.
    func undo() {
        guard canUndo, state.undo() else { return }
        leavingTask?.cancel()
        SRHaptic.select()
        sprites = Self.sprites(state.tiles)
        gain = nil
        if stage == .over { stage = .playing }
        save()
    }

    // MARK: - Feedback

    private func feel(_ turn: Merge2048Turn) {
        if turn.reachedTarget {
            SRHaptic.ok()
        } else if let biggest = turn.newBiggest, biggest >= 256, !turn.over {
            SRHaptic.ok()
        } else if !turn.merges.isEmpty {
            SRHaptic.tap()
        } else {
            SRHaptic.select()
        }
    }

    private func burst(_ turn: Merge2048Turn) {
        guard !calm else { return }
        let now = Date().timeIntervalSinceReferenceDate + Merge2048Motion.slide * 0.8
        var made: [Merge2048Spark] = []
        for merge in turn.merges {
            let colour = Merge2048Palette.swatch(merge.value).glow
            made += Merge2048SparkMaker.merge(row: merge.row, col: merge.col, side: state.side,
                                               value: merge.value, colour: colour, at: now)
        }
        if turn.reachedTarget { made += Merge2048SparkMaker.celebration(at: now + 0.2) }
        guard !made.isEmpty else { return }
        let clock = Date().timeIntervalSinceReferenceDate
        var kept = sparks.filter { clock - $0.born <= $0.life }
        kept += made
        sparks = kept
        sparksLive = true
        let until = kept.map { $0.born + $0.life }.max() ?? clock
        sparksTask?.cancel()
        sparksTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.05, until - clock + 0.05) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.sparksLive = false
            self.sparks = []
        }
    }

    /// Let the last slide land before the card comes up.
    private func settle(into next: Stage, after seconds: Double) {
        settling = true
        pendingStage = next
        endTask?.cancel()
        endTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.settling = false
            self.pendingStage = nil
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                self.stage = next
            }
        }
    }

    private func clearFeedback() {
        leavingTask?.cancel()
        endTask?.cancel()
        settling = false
        pendingStage = nil
        gain = nil
        sparks = []
        sparksLive = false
    }

    // MARK: - Keeping

    /// Put a different game on the board.
    private func replace(with next: Merge2048State) {
        state = next
        sprites = Self.sprites(next.tiles)
        round += 1
    }

    private func fresh(_ size: Merge2048Size) -> Merge2048State {
        Merge2048State(size: size, seed: scripted ? 2048 : UInt64.random(in: 1...UInt64.max))
    }

    /// Count the game on the board, if it was played at all, and clear it.
    private func closeGame() {
        if state.moves > 0 {
            book.note(size: size, score: state.score, biggest: state.biggest)
            book.finish(size: size, won: state.hasWon)
            store.saveBook(book)
        }
        store.clearGame(size)
    }

    private func save() {
        var next = saved
        if state.isOver || state.moves == 0 {
            store.clearGame(size)
            next.remove(size)
        } else {
            store.saveGame(state, size: size)
            next.insert(size)
        }
        if next != saved { saved = next }
    }

    private func refreshSaved() {
        var out = Set<Merge2048Size>()
        for option in Merge2048Size.allCases where store.loadGame(option) != nil { out.insert(option) }
        if saved != out { saved = out }
    }

    private static func sprites(_ tiles: [Merge2048Tile]) -> [Merge2048Sprite] {
        tiles.map { Merge2048Sprite(tile: $0, leaving: false) }
    }
}
