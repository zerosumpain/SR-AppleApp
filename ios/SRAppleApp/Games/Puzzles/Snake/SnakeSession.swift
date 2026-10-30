import SwiftUI
import UIKit

/// What a spark is made of, so the drawing picks its colour.
enum SnakeSparkKind {
    case apple, gold, leaf, body, confetti
}

/// One spark: flung from a point on the board (in cells), falling as it fades.
struct SnakeSpark {
    let x: Double
    let y: Double
    /// Cells a second.
    let vx: Double
    let vy: Double
    /// Play time it was born at, seconds.
    let born: Double
    let life: Double
    /// Radius in cells.
    let size: Double
    let kind: SnakeSparkKind
    /// For confetti and a rainbow snake: where on the colour wheel.
    let hue: Double
}

/// "+10" rising from an apple.
struct SnakePop {
    let text: String
    let x: Double
    let y: Double
    let born: Double
    let gold: Bool
}

/// The beat the board is drawn to. Only the board's canvas watches it, so a
/// frame redraws the snake and nothing else on the screen.
@MainActor
final class SnakeClock: ObservableObject {
    /// Play time in seconds: it stops while paused, so nothing jumps on resume.
    @Published var now: Double = 0
}

/// Snake's engine on this phone: a display link that steps the rules on a
/// fixed beat (one cell per `stepInterval`, however fast the screen draws),
/// keeps the sparks, and publishes only what the HUD and cards show. The
/// display link runs while a game is moving and stops the moment it is not.
@MainActor
final class SnakeSession: ObservableObject {
    enum Stage: Equatable {
        /// The card with how to play and the settings.
        case intro
        /// On the board, waiting for the first swipe.
        case ready
        case playing
        case paused
        /// The crash (or the win), before the card comes up.
        case dying
        case over
    }

    @Published private(set) var stage: Stage = .intro
    @Published private(set) var score = 0
    @Published private(set) var length = SnakeRules.startLength
    /// 0 at the start to 1 at top speed.
    @Published private(set) var speed: Double = 0
    @Published private(set) var records: SnakeRecords
    @Published private(set) var result: SnakeRunResult?
    /// A short line over the board: a maze or colour just opened.
    @Published private(set) var toast: String?
    /// Waiting after a pause rather than before a new game.
    @Published private(set) var resuming = false

    let clock = SnakeClock()
    /// Demo mode steers itself, so the screenshots move.
    let scripted = SRDemo.isOn

    private(set) var game: SnakeGame
    private(set) var maze: SnakeMaze?
    /// How far through the current step, 0 to 1, for gliding between cells.
    private(set) var fraction: Double = 1
    private(set) var sparks: [SnakeSpark] = []
    private(set) var pops: [SnakePop] = []
    /// When the apple appeared, for its pop; long ago for the still preview.
    private(set) var foodBorn: Double = -1
    private(set) var goldenBorn: Double = 0
    private(set) var ateAt: Double = -10
    private(set) var endedAt: Double?

    private var playTime: Double = 0
    private var ticker: FrameTicker?
    private var lastFrame: Double?
    private var accumulator: Double = 0
    private var readySince: Double = 0
    /// How long the crash (or the win) plays before the card.
    private var endDelay: Double = 1.15
    private var toastTask: Task<Void, Never>?
    private var announced: Set<String> = []
    private let store = SnakeRecordStore()
    /// The demo's autopilot games are not the phone's own, so they are not kept.
    private var persists: Bool { !scripted }

    init() {
        let records = SnakeRecordStore().load()
        let maze: SnakeMaze? = records.mode == .maze ? records.maze : nil
        self.records = records
        self.maze = maze
        self.game = SnakeGame(mode: records.mode, maze: maze, seed: 1)
    }

    // MARK: - What the screen reads

    var mode: SnakeMode { records.mode }
    var skin: SnakeSkin { records.activeSkin }

    /// The best in the mode (and maze) on the board.
    var best: Int { records.best(mode: game.mode, maze: maze).score }

    /// Where the game is going: "Classic", "Maze · Pillars".
    var place: String {
        if let maze, game.mode == .maze { return "\(SnakeMode.maze.title) · \(maze.name)" }
        return game.mode.title
    }

    // MARK: - Settings, on the intro card

    func choose(_ mode: SnakeMode) {
        guard stage == .intro, records.mode != mode else { return }
        records.mode = mode
        save()
        preview()
    }

    func choose(maze: SnakeMaze) {
        guard stage == .intro, records.isUnlocked(maze) else { return }
        records.mazeId = maze.id
        save()
        preview()
    }

    func choose(skin: SnakeSkin) {
        guard records.isUnlocked(skin) else { return }
        records.skin = skin
        save()
    }

    func setPad(_ on: Bool) {
        records.pad = on
        save()
    }

    /// The board behind the card shows the layout about to be played.
    private func preview() {
        maze = records.mode == .maze ? records.maze : nil
        game = SnakeGame(mode: records.mode, maze: maze, seed: 1)
        fraction = 1
        foodBorn = playTime - 1
        endedAt = nil
        sparks.removeAll()
        pops.removeAll()
        clock.now = playTime
    }

    // MARK: - Playing

    /// A new game on the chosen mode, waiting for the first swipe.
    func play() {
        maze = records.mode == .maze ? records.maze : nil
        let seed: UInt64 = scripted ? 7 : UInt64.random(in: 1...UInt64.max)
        game = SnakeGame(mode: records.mode, maze: maze, seed: seed)
        sparks.removeAll()
        pops.removeAll()
        fraction = 1
        accumulator = 0
        endedAt = nil
        result = nil
        announced = []
        score = 0
        length = game.length
        speed = 0
        foodBorn = playTime
        resuming = false
        readySince = playTime
        stage = .ready
        startClock()
        if scripted { go() }
    }

    /// A swipe or an arrow. The first one starts the snake moving.
    func turn(_ direction: SnakeDirection) {
        switch stage {
        case .ready:
            if direction != game.heading { game.turn(direction) }
            SRHaptic.tap()
            go()
        case .playing:
            if game.turn(direction) { SRHaptic.select() }
        default:
            break
        }
    }

    private func go() {
        // A fresh snake takes its first step on the next frame, so it glides
        // forward from where it sits rather than from the cell behind.
        if game.steps == 0 { accumulator = game.stepInterval }
        resuming = false
        stage = .playing
        startClock()
    }

    func pause() {
        guard stage == .playing || stage == .ready else { return }
        stage = .paused
        stopClock()
    }

    /// Back on the board, waiting for a swipe to carry on.
    func resume() {
        guard stage == .paused else { return }
        SRHaptic.tap()
        if scripted {
            go()
            return
        }
        resuming = true
        readySince = playTime
        stage = .ready
        startClock()
    }

    /// Back to the card with the settings.
    func menu() {
        stopClock()
        result = nil
        stage = .intro
        preview()
    }

    /// The scene went to the background.
    func sleep() {
        pause()
    }

    /// Off screen: stop everything. A crash mid-animation still gets its card.
    func leave() {
        pause()
        if stage == .dying { finish() }
        stopClock()
    }

    // MARK: - The clock

    private func startClock() {
        guard ticker == nil else { return }
        lastFrame = nil
        let ticker = FrameTicker { [weak self] time in
            guard let self else { return false }
            return self.frame(time)
        }
        self.ticker = ticker
        ticker.start()
    }

    private func stopClock() {
        ticker?.stop()
        ticker = nil
        lastFrame = nil
    }

    /// One display frame. False stops the link.
    private func frame(_ time: Double) -> Bool {
        // After a stall (a call, a notification pulled down) step a short
        // moment, not the whole gap.
        let dt = lastFrame.map { min(max(0, time - $0), 1.0 / 15) } ?? 0
        lastFrame = time
        playTime += dt
        switch stage {
        case .playing:
            advance(dt)
        case .dying:
            if let at = endedAt, playTime - at >= endDelay { finish() }
        default:
            break
        }
        if !sparks.isEmpty { sparks.removeAll { playTime - $0.born > $0.life } }
        if !pops.isEmpty { pops.removeAll { playTime - $0.born > 0.9 } }
        clock.now = playTime
        let running: Bool
        switch stage {
        case .playing, .dying: running = true
        // Waiting for a swipe: the tongue flicks and the apple bobs a while,
        // then the board holds still until someone touches it.
        case .ready: running = playTime - readySince < 25
        default: running = false
        }
        if !running {
            ticker = nil
            lastFrame = nil
        }
        return running
    }

    /// Steps owed since the last frame, at most a few, then where between
    /// cells the snake is drawn.
    private func advance(_ dt: Double) {
        accumulator += dt
        var steps = 0
        while accumulator >= game.stepInterval && steps < 4 {
            accumulator -= game.stepInterval
            steps += 1
            if scripted && game.turns.isEmpty {
                let direction = SnakeAutopilot.choose(game)
                if direction != game.heading { game.turn(direction) }
            }
            react(to: game.step())
            if stage != .playing { break }
        }
        if stage == .playing {
            fraction = min(1, max(0, accumulator / game.stepInterval))
        }
    }

    private func react(to step: SnakeStepResult) {
        if let death = step.died {
            end(death: death)
            return
        }
        if let cell = step.ate {
            ateAt = playTime
            foodBorn = playTime
            burst(at: cell, kind: .apple, count: 14, speed: 3.2)
            burst(at: cell, kind: .leaf, count: 4, speed: 2.2)
            pops.append(SnakePop(text: "+\(SnakeRules.applePoints)", x: Double(cell.x) + 0.5,
                                 y: Double(cell.y) + 0.5, born: playTime, gold: false))
            SRHaptic.tap()
        }
        if let cell = step.ateGolden {
            ateAt = playTime
            burst(at: cell, kind: .gold, count: 26, speed: 4.2)
            pops.append(SnakePop(text: "+\(SnakeRules.goldenPoints)", x: Double(cell.x) + 0.5,
                                 y: Double(cell.y) + 0.5, born: playTime, gold: true))
            SRHaptic.ok()
        }
        if step.goldenAppeared != nil {
            goldenBorn = playTime
            SRHaptic.select()
        }
        if step.filled {
            end(death: nil)
            return
        }
        sync()
    }

    /// The HUD's numbers, published only when they change.
    private func sync() {
        if score != game.score {
            score = game.score
            noteOpenings()
        }
        if length != game.length { length = game.length }
        let level = SnakeRules.speedLevel(eaten: game.eaten)
        if abs(level - speed) > 0.001 { speed = level }
    }

    /// Mid-game: say so the moment a score opens the next maze or a colour.
    private func noteOpenings() {
        if game.mode == .maze, let maze, let index = SnakeMaze.all.firstIndex(of: maze),
           index + 1 < SnakeMaze.all.count {
            let next = SnakeMaze.all[index + 1]
            if !records.isUnlocked(next), game.score >= next.unlockScore, !announced.contains(next.id) {
                announced.insert(next.id)
                show("\(next.name) is open")
            }
        }
        if let skin = records.nextSkin, records.apples + game.eaten >= skin.unlockApples,
           !announced.contains(skin.rawValue) {
            announced.insert(skin.rawValue)
            show("New colour: \(skin.title)")
        }
    }

    private func show(_ text: String) {
        toast = text
        SRHaptic.ok()
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    /// A crash, or (with no death) a full board. The record is kept now, in
    /// case the screen is left before the card comes up.
    private func end(death: SnakeDeath?) {
        sync()
        endedAt = playTime
        endDelay = death == nil ? 1.8 : 1.15
        fraction = 1
        stage = .dying
        if death == nil {
            SRHaptic.ok()
            confetti()
        } else {
            SRHaptic.bad()
            crumble()
        }
        result = records.record(game, maze: maze)
        save()
    }

    private func finish() {
        guard stage == .dying else { return }
        stage = .over
        stopClock()
    }

    private func save() {
        guard persists else { return }
        store.save(records)
    }

    // MARK: - Sparks

    private func burst(at cell: SnakePoint, kind: SnakeSparkKind, count: Int, speed: Double) {
        let cx = Double(cell.x) + 0.5, cy = Double(cell.y) + 0.5
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * Double.pi + Double.random(in: -0.3...0.3)
            let v = speed * Double.random(in: 0.45...1.0)
            sparks.append(SnakeSpark(x: cx, y: cy, vx: cos(angle) * v, vy: sin(angle) * v - 1.2,
                                     born: playTime, life: Double.random(in: 0.35...0.65),
                                     size: Double.random(in: 0.06...0.12), kind: kind,
                                     hue: Double.random(in: 0...1)))
        }
    }

    /// The snake breaks into pieces along its length.
    private func crumble() {
        let body = game.body
        let every = max(1, body.count / 28)
        for (index, cell) in body.enumerated() where index % every == 0 {
            for _ in 0..<2 {
                let angle = Double.random(in: 0...(2 * Double.pi))
                let v = Double.random(in: 1.0...3.4)
                sparks.append(SnakeSpark(x: Double(cell.x) + 0.5, y: Double(cell.y) + 0.5,
                                         vx: cos(angle) * v, vy: sin(angle) * v - 1.6,
                                         born: playTime + min(0.45, Double(index) * 0.012), life: Double.random(in: 0.5...0.9),
                                         size: Double.random(in: 0.09...0.16), kind: .body,
                                         hue: Double(index) * 0.055))
            }
        }
    }

    /// A full board: a fountain of colour from the middle.
    private func confetti() {
        let cx = Double(game.columns) / 2, cy = Double(game.rows) * 0.6
        for _ in 0..<90 {
            let angle = -Double.pi / 2 + Double.random(in: -1.2...1.2)
            let v = Double.random(in: 5...11)
            sparks.append(SnakeSpark(x: cx, y: cy, vx: cos(angle) * v, vy: sin(angle) * v,
                                     born: playTime + Double.random(in: 0...0.3), life: Double.random(in: 0.9...1.4),
                                     size: Double.random(in: 0.08...0.15), kind: .confetti,
                                     hue: Double.random(in: 0...1)))
        }
    }
}
