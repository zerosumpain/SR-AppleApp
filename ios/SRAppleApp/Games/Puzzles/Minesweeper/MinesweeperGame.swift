import SwiftUI
import UIKit

/// Keeps the field's TimelineView ticking only while something on it moves:
/// a dig rolling out, a flag popping, the ripple after a loss, a camera glide,
/// or a finger held down (the long-press ring). Otherwise it is paused and the
/// field is redrawn only when the game changes, so an idle board costs nothing.
@MainActor
final class MinesweeperPulse: ObservableObject {
    @Published private(set) var live = false
    private var until: Double = 0
    private var touching = false
    private var wake: Task<Void, Never>?

    nonisolated static func now() -> Double { Date().timeIntervalSinceReferenceDate }

    /// Keep ticking until at least `time`.
    func hold(until time: Double) {
        guard time > until else { return }
        until = time
        refresh()
    }

    /// A finger is down on the field.
    func setTouching(_ on: Bool) {
        guard touching != on else { return }
        touching = on
        refresh()
    }

    /// The screen went away: stop at once.
    func stop() {
        until = 0
        touching = false
        wake?.cancel()
        wake = nil
        if live { live = false }
    }

    private func refresh() {
        let wanted = touching || Self.now() < until
        if live != wanted { live = wanted }
        wake?.cancel()
        wake = nil
        guard wanted, !touching else { return }
        // One sleep to the end of the motion, not a repeating timer.
        let wait = max(0, until - Self.now())
        wake = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000) + 30_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}

/// Where the board's window looks: set directly while a finger drags or
/// pinches, or gliding (ease-out) to a new place after a fling, the zoom
/// button or a new field.
@MainActor
final class MinesweeperCamera: ObservableObject {
    /// Where the camera is, or where its glide will end.
    @Published private(set) var resting: MinesweeperViewport
    private var glideFrom: MinesweeperViewport?
    private var glideStart: Double = 0
    private var glideTime: Double = 0.35
    private let pulse: MinesweeperPulse
    private var sized = false

    init(pulse: MinesweeperPulse) {
        self.pulse = pulse
        resting = MinesweeperViewport(columns: 9, rows: 9, width: 320, height: 320)
    }

    func viewport(at now: Double) -> MinesweeperViewport {
        guard let from = glideFrom else { return resting }
        let t = (now - glideStart) / glideTime
        if t >= 1 { return resting }
        let eased = 1 - pow(1 - max(0, t), 3)
        return from.blended(to: resting, eased)
    }

    /// Straight there: a finger is moving it.
    func set(_ viewport: MinesweeperViewport) {
        glideFrom = nil
        if viewport != resting { resting = viewport }
    }

    /// Ease there over `duration`.
    func glide(to viewport: MinesweeperViewport, duration: Double = 0.35) {
        let now = MinesweeperPulse.now()
        glideFrom = self.viewport(at: now)
        glideStart = now
        glideTime = max(0.05, duration)
        resting = viewport
        pulse.hold(until: now + duration + 0.05)
    }

    /// Stop a glide where it is: a finger came down.
    func freeze() {
        guard glideFrom != nil else { return }
        let here = viewport(at: MinesweeperPulse.now())
        glideFrom = nil
        resting = here
    }

    /// The window's size, from the board's GeometryReader.
    func layout(width: Double, height: Double) {
        guard width > 1, height > 1 else { return }
        if !sized {
            sized = true
            resting = MinesweeperViewport(columns: resting.columns, rows: resting.rows, width: width, height: height)
            return
        }
        guard abs(resting.viewWidth - width) > 0.5 || abs(resting.viewHeight - height) > 0.5 else { return }
        glideFrom = nil
        resting = resting.resized(width: width, height: height)
    }

    /// A new field: its opening view in the same window.
    func reset(columns: Int, rows: Int) {
        glideFrom = nil
        resting = MinesweeperViewport(columns: columns, rows: rows, width: resting.viewWidth, height: resting.viewHeight)
    }

    /// The zoom button: in to a comfortable square, or back out to the whole field.
    func toggleZoom(around index: Int?) {
        let here = viewport(at: MinesweeperPulse.now())
        glide(to: here.isZoomedIn ? here.fitted() : here.zoomedIn(on: index), duration: 0.4)
    }
}

/// A finger held on a square: which, and since when (for the long-press ring).
struct MinesweeperPress: Equatable {
    var cell: Int
    var since: Double
}

/// The clock: runs from the first dig, stops for a pause, a loss or a win.
struct MinesweeperClock {
    private(set) var banked: Double = 0
    private(set) var since: Date? = nil

    var running: Bool { since != nil }

    func elapsed(at now: Date) -> Double {
        banked + (since.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    mutating func start(at now: Date) {
        if since == nil { since = now }
    }

    @discardableResult
    mutating func stop(at now: Date) -> Double {
        banked = elapsed(at: now)
        since = nil
        return banked
    }
}

/// The face on the restart button.
enum MinesweeperMood: Equatable {
    case happy
    /// A finger is down on a covered square.
    case worried
    /// Laying a no-guessing field.
    case thinking
    case cool
    case dead
}

/// Minesweeper's game on this phone: the field, the stage, the clock, the
/// bests, and the motion the painter draws. Taps arrive as squares from the
/// board view; everything a square does is decided here.
@MainActor
final class MinesweeperGame: ObservableObject {
    enum Stage: Equatable {
        /// The start card: choose a field.
        case intro
        /// A fresh field, waiting for the first dig.
        case ready
        /// Laying a no-guessing field after the first dig.
        case laying
        case playing
        case won
        case lost
    }

    @Published private(set) var stage: Stage = .intro
    @Published private(set) var board: MinesweeperBoard
    @Published private(set) var paused = false
    /// Taps plant flags instead of digging.
    @Published var flagMode = false
    @Published private(set) var setup: MinesweeperSetup
    @Published private(set) var records: MinesweeperRecords
    /// The end card is up (it waits for the ripple to finish).
    @Published private(set) var showResult = false
    /// The finished time's place in the top five, 1 being a new best.
    @Published private(set) var place: Int? = nil
    @Published private(set) var finalTime: Double = 0
    @Published private(set) var press: MinesweeperPress? = nil
    /// This field was checked by the solver: no guess is ever needed.
    @Published private(set) var logicalField = false

    /// The motion on the field. Not published: it changes with the board, and
    /// the pulse keeps the field redrawing while it plays out.
    private(set) var fx: MinesweeperEffects
    let pulse: MinesweeperPulse
    let camera: MinesweeperCamera
    /// The key the game in play is recorded under, fixed when it starts.
    private(set) var playingKey: String
    private var clock = MinesweeperClock()
    private var lastDig: Int? = nil
    private var generation = 0
    /// The screen went away while a no-guessing field was being laid: pause once it lands.
    private var pauseWhenLaid = false
    private var resultTask: Task<Void, Never>?
    private let store = MinesweeperRecordStore()

    init() {
        let store = MinesweeperRecordStore()
        let saved = store.loadSetup()
        let pulse = MinesweeperPulse()
        self.pulse = pulse
        camera = MinesweeperCamera(pulse: pulse)
        setup = saved
        records = store.load()
        board = MinesweeperBoard(width: saved.width, height: saved.height, mines: saved.mines)
        fx = MinesweeperEffects(count: saved.width * saved.height)
        playingKey = saved.recordKey
        camera.reset(columns: saved.width, rows: saved.height)
    }

    // MARK: - Reading

    var mood: MinesweeperMood {
        switch stage {
        case .won: return .cool
        case .lost: return .dead
        case .laying: return .thinking
        case .intro, .ready, .playing:
            if let press, board.cells[press.cell] != .revealed { return .worried }
            return .happy
        }
    }

    /// Squares and flags can be touched.
    var acceptsTouch: Bool { (stage == .ready || stage == .playing) && !paused }
    var clockRunning: Bool { clock.running }

    func elapsed(at now: Date) -> Double { clock.elapsed(at: now) }

    /// The best time for the field chosen on the start card.
    var bestForSetup: Double? { records.best(setup.recordKey) }
    var bestForGame: Double? { records.best(playingKey) }

    /// Safe squares dug, as a share of all of them.
    var cleared: Double {
        guard board.safeCount > 0 else { return 0 }
        return Double(board.revealedCount) / Double(board.safeCount)
    }

    /// The square most recently dug, for the zoom button to centre on.
    var focusCell: Int? { lastDig }

    // MARK: - Choosing

    func changeSetup(_ change: (inout MinesweeperSetup) -> Void) {
        var next = setup
        change(&next)
        next.tidyCustom()
        guard next != setup else { return }
        setup = next
        store.saveSetup(next)
    }

    // MARK: - Starting

    /// From the start card: a fresh field of the chosen size.
    func begin() {
        newField()
        stage = .ready
    }

    /// The face: a fresh field, same size, at once.
    func restart() {
        newField()
        stage = .ready
        UIAccessibility.post(notification: .announcement, argument: "New field. Tap any square to start.")
    }

    /// Back to the start card to choose another field.
    func toIntro() {
        generation += 1
        resultTask?.cancel()
        clock.stop(at: Date())
        paused = false
        showResult = false
        press = nil
        pulse.stop()
        stage = .intro
    }

    private func newField() {
        generation += 1
        resultTask?.cancel()
        let s = setup
        board = MinesweeperBoard(width: s.width, height: s.height, mines: s.mines)
        fx = MinesweeperEffects(count: s.width * s.height)
        playingKey = s.recordKey
        clock = MinesweeperClock()
        paused = false
        showResult = false
        place = nil
        finalTime = 0
        press = nil
        lastDig = nil
        logicalField = false
        flagMode = false
        pauseWhenLaid = false
        camera.reset(columns: s.width, rows: s.height)
    }

    // MARK: - Touch

    /// A tap on a square.
    func tap(_ cell: Int) {
        guard acceptsTouch, cell >= 0, cell < board.size else { return }
        if stage == .ready {
            firstDig(cell)
            return
        }
        switch board.cells[cell] {
        case .revealed:
            chord(cell)
        case .flagged:
            if flagMode { toggleFlag(cell) } else { SRHaptic.select() }
        case .hidden:
            if flagMode { toggleFlag(cell) } else { dig(cell) }
        }
    }

    /// A long press: the other action from a tap. Flags in dig mode, digs in
    /// flag mode; on a number it chords either way.
    func hold(_ cell: Int) {
        guard acceptsTouch, cell >= 0, cell < board.size else { return }
        press = nil
        pulse.setTouching(false)
        if stage == .ready {
            // Nothing to flag before the mines are laid: a hold still digs.
            firstDig(cell)
            return
        }
        switch board.cells[cell] {
        case .revealed:
            chord(cell)
        case .flagged:
            toggleFlag(cell)
        case .hidden:
            if flagMode { dig(cell) } else { toggleFlag(cell) }
        }
    }

    /// VoiceOver's "Flag" action on a square.
    func flagFromVoiceOver(_ cell: Int) {
        guard acceptsTouch, stage == .playing else { return }
        toggleFlag(cell)
    }

    func pressBegan(_ cell: Int) {
        guard acceptsTouch else { return }
        press = MinesweeperPress(cell: cell, since: MinesweeperPulse.now())
        pulse.setTouching(true)
    }

    func pressEnded() {
        if press != nil { press = nil }
        pulse.setTouching(false)
    }

    // MARK: - Moves

    private func firstDig(_ cell: Int) {
        let s = setup
        let gen = generation
        let seed = UInt64.random(in: 0...UInt64.max)
        if !s.noGuess {
            let field = MinesweeperGenerator.field(width: s.width, height: s.height, mines: s.mines,
                                                   firstDig: cell, noGuess: false, seed: seed)
            lay(field, first: cell)
            return
        }
        stage = .laying
        Task { [weak self] in
            let field = await Task.detached(priority: .userInitiated) { () -> MinesweeperField in
                MinesweeperGenerator.field(width: s.width, height: s.height, mines: s.mines, firstDig: cell,
                                           noGuess: true, seed: seed, deadline: Date().addingTimeInterval(1.6))
            }.value
            guard let self, self.generation == gen, self.stage == .laying else { return }
            self.lay(field, first: cell)
        }
    }

    private func lay(_ field: MinesweeperField, first cell: Int) {
        board = field.board
        logicalField = field.logical
        stage = .playing
        clock.start(at: Date())
        dig(cell)
        if pauseWhenLaid {
            pauseWhenLaid = false
            pause()
        }
    }

    private func dig(_ cell: Int) {
        var next = board
        let outcome = next.reveal(cell)
        guard outcome.changed else { return }
        board = next
        lastDig = cell
        handle(outcome)
    }

    private func chord(_ cell: Int) {
        guard board.counts[cell] > 0 else { return }
        if board.canChord(cell) {
            var next = board
            let outcome = next.chord(cell)
            board = next
            lastDig = cell
            handle(outcome)
        } else {
            // Not enough (or too many) flags round it: blink the squares it is counting.
            let now = MinesweeperPulse.now()
            let covered = board.neighbours(of: cell).filter { board.cells[$0] != .revealed }
            guard !covered.isEmpty else { return }
            fx.hint(covered, at: now)
            pulse.hold(until: now + MinesweeperEffects.hintTime)
            SRHaptic.select()
            objectWillChange.send()
        }
    }

    private func toggleFlag(_ cell: Int) {
        var next = board
        guard next.toggleFlag(cell) else { return }
        let now = MinesweeperPulse.now()
        fx.flag(cell, at: now)
        board = next
        pulse.hold(until: now + MinesweeperEffects.popTime)
        SRHaptic.select()
    }

    private func handle(_ outcome: MinesweeperOutcome) {
        let now = MinesweeperPulse.now()
        if !outcome.opened.isEmpty {
            let span = fx.uncover(outcome.opened, width: board.width, at: now)
            pulse.hold(until: now + span)
            if outcome.hitMine == nil && !outcome.won { SRHaptic.tap() }
        }
        if let hit = outcome.hitMine {
            lose(at: hit, now: now)
        } else if outcome.won {
            win(now: now)
        }
    }

    private func lose(at hit: Int, now: Double) {
        finalTime = clock.stop(at: Date())
        stage = .lost
        records.recordLoss(key: playingKey)
        store.save(records)
        let span = fx.explode(at: hit, mines: board.mineIndices, width: board.width, now: now)
        pulse.hold(until: fx.settlesAt)
        SRHaptic.bad()
        UIAccessibility.post(notification: .announcement, argument: "Boom. You dug a mine.")
        showResultAfter(span + 0.45)
    }

    private func win(now: Double) {
        finalTime = clock.stop(at: Date())
        stage = .won
        place = records.recordWin(key: playingKey, time: finalTime)
        store.save(records)
        let span = fx.celebrate(from: lastDig ?? 0, mines: board.mineIndices, width: board.width, now: now)
        pulse.hold(until: fx.settlesAt)
        SRHaptic.ok()
        let words = place == 1 ? "Field cleared. A new best: \(MinesweeperFormat.spoken(finalTime))."
            : "Field cleared in \(MinesweeperFormat.spoken(finalTime))."
        UIAccessibility.post(notification: .announcement, argument: words)
        showResultAfter(span + 0.35)
    }

    private func showResultAfter(_ seconds: Double) {
        resultTask?.cancel()
        let gen = generation
        resultTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            guard !Task.isCancelled, let self, self.generation == gen else { return }
            self.showResult = true
        }
    }

    // MARK: - Pause

    func pause() {
        guard stage == .playing, !paused else { return }
        paused = true
        clock.stop(at: Date())
        pressEnded()
    }

    func resume() {
        guard paused else { return }
        paused = false
        if stage == .playing { clock.start(at: Date()) }
    }

    /// Off screen or into the background: the clock stops and nothing ticks.
    func stop() {
        if stage == .laying { pauseWhenLaid = true }
        pause()
        pressEnded()
        pulse.stop()
    }
}
