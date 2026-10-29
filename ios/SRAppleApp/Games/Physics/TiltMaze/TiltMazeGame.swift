import SwiftUI

/// A game of Tilt Maze: which maze is on the board, where in the game we are
/// (the menu, the card before a maze, rolling, paused, done), the endless
/// run's marbles, and the book of bests. The engine rolls the marble; this
/// hears from it only at the moments that matter — the first roll, a fall,
/// the cup — so the screen redraws a handful of times a maze, not every
/// frame.
@MainActor
final class TiltMazeGame: ObservableObject {
    enum Mode: Equatable {
        case campaign(Int)
        case endless
    }

    enum Stage: Equatable {
        /// The level grid and the endless door.
        case menu
        /// The card before a maze: its name, a tip, the times to beat.
        case briefing
        case playing
        case paused
        /// Into the cup: the results card.
        case cleared
        /// An endless run out of marbles (or stopped).
        case over
    }

    /// How a maze went.
    struct Finish: Equatable {
        var time: Double
        var stars: Int
        var falls: Int
        var newBestTime: Bool
        var newStars: Bool
        var bestTime: Double?
    }

    @Published private(set) var stage: Stage = .menu
    @Published private(set) var mode: Mode
    @Published private(set) var book: TiltMazeBook
    @Published private(set) var finish: Finish? = nil
    @Published private(set) var level: TiltMazeLevel
    /// Names the maze on the board, for the drawn-once layers.
    @Published private(set) var key: String
    @Published private(set) var par: TiltMazePar
    /// Endless: marbles left, and mazes cleared this run.
    @Published private(set) var lives = TiltMazeGame.startLives
    @Published private(set) var cleared = 0
    @Published private(set) var endlessNewBest = false
    /// The marble has rolled on this maze: the clock is going.
    @Published private(set) var started = false
    /// Steer with the on-screen stick rather than by tilting. Remembered.
    @Published var useStick: Bool {
        didSet {
            engine.useStick = useStick
            UserDefaults.standard.set(useStick, forKey: Self.stickKey)
        }
    }

    let engine: TiltMazeEngine
    private let store = TiltMazeStore()
    private var seed: UInt64 = 1
    /// This endless run is already in the book: it is never counted twice.
    private var runRecorded = false

    static let stickKey = "tilt-maze.stick"
    static let startLives = 3
    static let maxLives = 5

    init() {
        let book = TiltMazeStore().load()
        let number = book.unlocked
        let first = TiltMazeCatalogue.level(number)
        let engine = TiltMazeEngine(level: first)
        self.book = book
        self.mode = .campaign(number)
        self.level = first
        self.key = "campaign-\(number)"
        self.par = TiltMazePar.of(first)
        self.engine = engine
        self.useStick = UserDefaults.standard.bool(forKey: Self.stickKey) || !engine.motion.available
        engine.useStick = useStick
        engine.onEvents = { [weak self] events in self?.handle(events) }
    }

    var tiltAvailable: Bool { engine.motion.available }
    var scripted: Bool { engine.scripted }
    var steersByTilt: Bool { engine.steersByTilt }

    /// The campaign level being played (0 in endless).
    var number: Int {
        if case .campaign(let n) = mode { return n }
        return 0
    }

    var isEndless: Bool { mode == .endless }

    var info: TiltMazeLevelInfo {
        if isEndless {
            return TiltMazeLevelInfo(number: cleared + 1, name: "Maze \(cleared + 1)",
                                     tip: "Fresh mazes, one after another, a little bigger each time.",
                                     cols: level.cols, rows: level.rows)
        }
        return TiltMazeCatalogue.info(number)
    }

    var wood: TiltMazeWood { TiltMazeWood.of(level: isEndless ? cleared + 1 : number) }

    // MARK: - Choosing

    /// The briefing for campaign level `n`, if it is open.
    func play(_ n: Int) {
        let n = min(max(1, n), TiltMazeCatalogue.campaignCount)
        guard book.isOpen(n) || scripted else { return }
        mode = .campaign(n)
        load(TiltMazeCatalogue.level(n), key: "campaign-\(n)")
        stage = .briefing
    }

    /// A new endless run.
    func playEndless() {
        mode = .endless
        lives = Self.startLives
        cleared = 0
        endlessNewBest = false
        runRecorded = false
        seed = scripted ? 7 : UInt64.random(in: 1...UInt64(UInt32.max))
        loadEndless()
        stage = .briefing
    }

    private func loadEndless() {
        let mazeSeed = seed &+ UInt64(cleared) &* 0x9E37_79B9
        load(TiltMazeCatalogue.endless(depth: cleared, seed: mazeSeed), key: "endless-\(mazeSeed)-\(cleared)")
    }

    private func load(_ level: TiltMazeLevel, key: String) {
        engine.load(level)
        engine.useStick = useStick
        self.level = level
        self.key = key
        par = TiltMazePar.of(level)
        finish = nil
        started = false
    }

    // MARK: - Playing

    /// From the briefing: the way the phone is held now is level, and roll.
    func roll() {
        guard stage == .briefing else { return }
        engine.calibrate()
        go()
    }

    func pause() {
        guard stage == .playing else { return }
        engine.stop()
        stage = .paused
    }

    func resume() {
        guard stage == .paused else { return }
        go()
    }

    private func go() {
        stage = .playing
        engine.start()
    }

    /// The same maze again from the start (campaign), or a new run (endless).
    func restart() {
        switch mode {
        case .campaign(let n):
            load(TiltMazeCatalogue.level(n), key: "campaign-\(n)")
            engine.calibrate()
            go()
        case .endless:
            closeEndlessRun()
            store.save(book)
            playEndless()
        }
    }

    /// After the cup: the next level's briefing, or the next endless maze.
    func next() {
        guard stage == .cleared else { return }
        switch mode {
        case .campaign(let n):
            if n < TiltMazeCatalogue.campaignCount {
                play(n + 1)
            } else {
                toMenu()
            }
        case .endless:
            loadEndless()
            go()
        }
    }

    /// Endless: stop the run here and see how it went.
    func endRun() {
        guard isEndless, stage != .over else { return }
        engine.stop()
        endlessNewBest = closeEndlessRun()
        store.save(book)
        stage = .over
    }

    func toMenu() {
        engine.stop()
        if isEndless { closeEndlessRun() }
        store.save(book)
        stage = .menu
    }

    /// An endless run into the book, once, if it got going at all (a run
    /// left at its first card is not a run). True when it is a new best.
    @discardableResult
    private func closeEndlessRun() -> Bool {
        guard isEndless, !runRecorded, cleared > 0 || started else { return false }
        runRecorded = true
        return book.recordEndless(mazes: cleared)
    }

    /// The screen has gone or the app is in the background: everything stops.
    func leave() {
        pause()
        engine.stop()
        // Walking away mid-run still counts the mazes cleared.
        if isEndless && cleared > 0 { closeEndlessRun() }
        store.save(book)
    }

    func calibrate() { engine.calibrate() }

    // MARK: - What the engine says

    private func handle(_ events: TiltMazeEvents) {
        if events.started { started = true }
        if events.fell {
            book.recordFall()
            if isEndless { lives = max(0, lives - 1) }
        }
        if events.respawned && isEndless && lives <= 0 {
            endRun()
            return
        }
        if events.cleared { finished() }
    }

    private func finished() {
        engine.stop()
        let run = engine.run
        switch mode {
        case .campaign(let n):
            let stars = par.stars(for: run.time)
            let clear = book.recordClear(level: n, time: run.time, stars: stars)
            finish = Finish(time: run.time, stars: stars, falls: run.falls, newBestTime: clear.newBestTime,
                            newStars: clear.newStars, bestTime: book.bestTime(for: n))
        case .endless:
            cleared += 1
            book.noteEndlessMaze()
            // Every third maze earns a marble back.
            if cleared % 3 == 0 { lives = min(Self.maxLives, lives + 1) }
            finish = Finish(time: run.time, stars: 0, falls: run.falls, newBestTime: false, newStars: false, bestTime: nil)
        }
        store.save(book)
        stage = .cleared
    }
}
