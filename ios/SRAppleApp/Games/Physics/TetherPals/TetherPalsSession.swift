import SwiftUI
import UIKit

/// What a spark is, so the drawing picks its colour and how it moves.
enum TetherPalsSparkKind {
    case dust, poof, boost, star, confetti
}

/// One spark, in tiles: flung from a point, fading as it goes.
struct TetherPalsSpark {
    let x: Double
    let y: Double
    let vx: Double
    let vy: Double
    let born: Double
    let life: Double
    let size: Double
    let kind: TetherPalsSparkKind
    /// Which pal's colour, or a place on the colour wheel for confetti.
    let tint: Double
}

/// The beat the board is drawn to. Only the board's canvas watches it, so a
/// frame redraws the world and nothing else on the screen.
@MainActor
final class TetherPalsClock: ObservableObject {
    @Published var now: Double = 0
}

/// Tether Pals' engine on this phone: a display link that steps the rules on
/// their fixed beat (1/120 s, however fast the screen draws), turns what the
/// fingers on the pad hold into each pal's buttons, keeps the sparks, and
/// publishes only what the HUD and the cards show. The link runs while the
/// pals can move and stops the moment they can't.
@MainActor
final class TetherPalsSession: ObservableObject {
    enum Stage: Equatable {
        /// The card with how to play, the players and the levels.
        case intro
        /// On the level, waiting for the first button.
        case ready
        case playing
        case paused
        /// Everyone is at the flag: a moment of cheering before the card.
        case cheering
        case over
    }

    @Published private(set) var stage: Stage = .intro
    @Published private(set) var records: TetherPalsRecords
    @Published private(set) var result: TetherPalsResult?
    @Published private(set) var levelNumber: Int
    @Published private(set) var players: TetherPalsPlayers
    /// The HUD's clock, in tenths of a second.
    @Published private(set) var tenths = 0
    @Published private(set) var homeCount = 0
    @Published private(set) var popCount = 0
    /// Playing solo, the pal the buttons drive.
    @Published private(set) var active = 0
    /// What each strip of the pad is holding, for lighting the buttons.
    @Published private(set) var holds: [TetherPalsHold] = []
    /// A short line over the board.
    @Published private(set) var toast: String?
    /// Waiting after a pause rather than before a new go.
    @Published private(set) var resuming = false
    /// "Show me how": the pals play the level's walkthrough by themselves.
    @Published private(set) var watching = false

    let clock = TetherPalsClock()
    /// Demo mode plays itself, so the screenshots move.
    let scripted = SRDemo.isOn

    private(set) var world: TetherPalsWorld
    private(set) var sparks: [TetherPalsSpark] = []
    /// Seconds the screen has been animating, for bobbing and waving.
    private(set) var playTime: Double = 0
    /// When the active pal last changed, for its little hop of a marker.
    private(set) var swappedAt: Double = -10

    private var pilot: TetherPalsAutopilot?
    private var ticker: FrameTicker?
    private var lastFrame: Double?
    private var accumulator = 0.0
    private var cheerAt: Double?
    private var readySince = 0.0
    /// VoiceOver's steps: a direction held for a moment, per pal.
    private var nudges: [Int: (direction: Int, until: Double)] = [:]
    /// VoiceOver's jumps, pressed for one step.
    private var jumpTaps: Set<Int> = []
    private var random = TetherPalsRandom(seed: 1)
    private var toastTask: Task<Void, Never>?
    private let store = TetherPalsRecordStore()
    /// The demo's games are not this phone's, so they are not kept.
    private var persists: Bool { !scripted }

    init() {
        let records = TetherPalsRecordStore().load()
        let demo = SRDemo.isOn
        let number = demo ? 2 : records.startLevel
        let players: TetherPalsPlayers = demo ? .two : records.players
        self.records = records
        levelNumber = number
        self.players = players
        world = TetherPalsWorld(level: TetherPalsCatalogue.level(number), team: players.team)
        holds = Array(repeating: TetherPalsHold(), count: players.strips)
    }

    // MARK: - What the screen reads

    var level: TetherPalsLevel { world.level }
    var team: Int { world.team }
    var solo: Bool { players == .solo }
    var best: Double? { records.best(levelNumber) }
    var elapsed: Double { Double(tenths) / 10 }
    var canSwap: Bool { solo && stage != .intro }

    /// Every level is open in the demo; otherwise one past the furthest cleared.
    func isOpen(_ number: Int) -> Bool { scripted ? number >= 1 && number <= TetherPalsCatalogue.count : records.isOpen(number) }

    var hasNext: Bool { levelNumber < TetherPalsCatalogue.count && isOpen(levelNumber + 1) }

    /// The pal a strip drives: playing solo, whichever is active.
    func pal(forStrip strip: Int) -> Int { solo ? active : strip }

    /// The pal marked with a pointer: solo's active one (or the demo pilot's).
    var markedPal: Int? {
        if scripted || watching, stage == .playing || stage == .ready { return pilot?.currentPal ?? (solo ? active : nil) }
        return solo ? active : nil
    }

    // MARK: - The start card

    func choose(level number: Int) {
        guard stage == .intro, isOpen(number), number != levelNumber else { return }
        SRHaptic.select()
        levelNumber = number
        records.level = number
        save()
        preview()
    }

    func choose(players: TetherPalsPlayers) {
        guard stage == .intro, players != self.players else { return }
        SRHaptic.select()
        self.players = players
        records.players = players
        save()
        preview()
    }

    /// The level behind the card, as it will start.
    private func preview() {
        world = TetherPalsWorld(level: TetherPalsCatalogue.level(levelNumber), team: players.team)
        holds = Array(repeating: TetherPalsHold(), count: players.strips)
        sparks.removeAll()
        active = 0
        tenths = 0
        homeCount = 0
        popCount = 0
        clock.now = playTime
    }

    // MARK: - Playing

    /// The chosen level from the start, waiting for the first button.
    func play() {
        stopClock()
        preview()
        result = nil
        cheerAt = nil
        accumulator = 0
        nudges = [:]
        jumpTaps = []
        resuming = false
        watching = false
        pilot = scripted ? TetherPalsAutopilot(script: level.script) : nil
        readySince = playTime
        stage = .ready
        startClock()
        if scripted { go() }
    }

    /// From the pause card: the level from the start, played by the pals
    /// themselves. It is not timed or kept; at the flag it is the player's turn.
    func showMe() {
        guard stage == .paused || stage == .ready else { return }
        SRHaptic.tap()
        play()
        watching = true
        pilot = TetherPalsAutopilot(script: level.script)
        go()
    }

    func restart() {
        guard stage != .intro else { return }
        SRHaptic.tap()
        play()
    }

    /// The next level, from the results card.
    func playNext() {
        guard hasNext else { return }
        levelNumber += 1
        records.level = levelNumber
        save()
        play()
    }

    private func go() {
        resuming = false
        stage = .playing
        startClock()
    }

    func pause() {
        guard stage == .playing || stage == .ready else { return }
        if watching {
            // A pause hands the pals back to the player, where they stand.
            watching = false
            if !scripted { pilot = nil }
        }
        stage = .paused
        releaseAll()
        stopClock()
    }

    /// Back on the level, waiting for a button to carry on.
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

    /// Back to the start card.
    func menu() {
        stopClock()
        result = nil
        pilot = nil
        watching = false
        stage = .intro
        preview()
    }

    /// Off screen: stop everything. A clear mid-cheer still gets its card.
    func leave() {
        pause()
        if stage == .cheering { finish() }
        stopClock()
        toastTask?.cancel()
    }

    // MARK: - The pad

    /// The keys every finger on the pad is on now, and the ones just pressed.
    func touches(_ keys: [(player: Int, key: TetherPalsKey)], pressed: [(player: Int, key: TetherPalsKey)]) {
        guard !scripted, !watching else { return }
        let next = TetherPalsPadLayout.holds(keys, strips: players.strips)
        if next != holds { holds = next }
        guard !pressed.isEmpty else { return }
        if pressed.contains(where: { $0.key == .swap }) { swap() }
        // A tap quicker than a frame still jumps: the press is kept for the next step.
        for press in pressed where press.key == .jump {
            let index = pal(forStrip: press.player)
            if index < team { jumpTaps.insert(index) }
        }
        if stage == .ready {
            SRHaptic.tap()
            go()
        }
    }

    /// Playing solo: drive the next pal.
    func swap() {
        guard solo, stage == .ready || stage == .playing else { return }
        active = (active + 1) % team
        swappedAt = playTime
        SRHaptic.select()
        show("Now moving \(TetherPalsCast.name(active))")
    }

    /// VoiceOver: a short step one way.
    func step(_ pal: Int, direction: Int) {
        guard !scripted, !watching, pal < team else { return }
        if stage == .ready { go() }
        guard stage == .playing else { return }
        nudges[pal] = (direction, playTime + 0.3)
    }

    /// VoiceOver: one jump.
    func jump(_ pal: Int) {
        guard !scripted, !watching, pal < team else { return }
        if stage == .ready { go() }
        guard stage == .playing else { return }
        jumpTaps.insert(pal)
    }

    private func releaseAll() {
        if holds.contains(where: { $0 != TetherPalsHold() }) {
            holds = Array(repeating: TetherPalsHold(), count: players.strips)
        }
        nudges = [:]
        jumpTaps = []
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
        // After a stall step a short moment, not the whole gap.
        let dt = lastFrame.map { min(max(0, time - $0), 1.0 / 15) } ?? 0
        lastFrame = time
        playTime += dt
        switch stage {
        case .playing:
            advance(dt)
        case .cheering:
            if let at = cheerAt, playTime - at >= (watching ? 1.2 : 1.7) { finish() }
        default:
            break
        }
        if !sparks.isEmpty { sparks.removeAll { playTime - $0.born > $0.life } }
        clock.now = playTime
        let running: Bool
        switch stage {
        case .playing, .cheering: running = true
        // Waiting for a button: the flag waves a while, then the board holds still.
        case .ready: running = playTime - readySince < 20
        default: running = false
        }
        if !running {
            ticker = nil
            lastFrame = nil
        }
        return running
    }

    /// The steps owed since the last frame, a few at most.
    private func advance(_ dt: Double) {
        accumulator += dt
        var steps = 0
        while accumulator >= TetherPalsRules.step && steps < 10 {
            accumulator -= TetherPalsRules.step
            steps += 1
            let events = world.step(inputs())
            react(to: events)
            if stage != .playing { break }
        }
        if accumulator > TetherPalsRules.step * 10 { accumulator = 0 }
        sync()
    }

    /// Every pal's buttons this step: the pilot's in the demo, else the pad's
    /// (and VoiceOver's).
    private func inputs() -> [TetherPalsInput] {
        if scripted || watching, var pilot {
            let out = pilot.inputs(for: world)
            self.pilot = pilot
            showPilot(out, pal: pilot.currentPal)
            return out
        }
        var out = Array(repeating: TetherPalsInput.none, count: team)
        for strip in holds.indices {
            let index = self.pal(forStrip: strip)
            if index < team { out[index] = holds[strip].input }
        }
        for (pal, nudge) in nudges where pal < team {
            if nudge.until > playTime {
                out[pal].left = out[pal].left || nudge.direction < 0
                out[pal].right = out[pal].right || nudge.direction > 0
            } else {
                nudges[pal] = nil
            }
        }
        for pal in jumpTaps where pal < team { out[pal].jump = true }
        jumpTaps = []
        return out
    }

    /// The demo lights the pad's buttons as the pilot presses them.
    private func showPilot(_ inputs: [TetherPalsInput], pal: Int?) {
        if solo, let pal, pal != active {
            active = pal
            swappedAt = playTime
        }
        var lit = Array(repeating: TetherPalsHold(), count: players.strips)
        for strip in lit.indices {
            let index = self.pal(forStrip: strip)
            guard index < inputs.count else { continue }
            lit[strip] = TetherPalsHold(left: inputs[index].left, right: inputs[index].right, jump: inputs[index].jump)
        }
        if lit != holds { holds = lit }
    }

    /// The HUD's figures, published only when they change.
    private func sync() {
        let now = Int((world.time * 10).rounded(.down))
        if now != tenths { tenths = now }
        if homeCount != world.homeCount { homeCount = world.homeCount }
        if popCount != world.pops { popCount = world.pops }
    }

    // MARK: - Events

    private func react(to events: TetherPalsEvents) {
        guard !events.isEmpty else { return }
        for index in events.jumped { burst(at: index, kind: .dust, count: 5, speed: 1.6, up: false) }
        for index in events.boosted {
            burst(at: index, kind: .boost, count: 10, speed: 2.6, up: false)
            SRHaptic.tap()
        }
        for index in events.landedOnPal {
            burst(at: index, kind: .star, count: 4, speed: 1.2, up: true)
            SRHaptic.select()
        }
        if !events.popped.isEmpty {
            for index in events.popped { burst(at: index, kind: .poof, count: 14, speed: 2.4, up: false) }
            SRHaptic.bad()
        }
        for index in events.respawned { burst(at: index, kind: .star, count: 6, speed: 1.4, up: true) }
        for index in events.arrived {
            burst(at: index, kind: .star, count: 8, speed: 1.8, up: true)
            SRHaptic.tap()
        }
        if events.buttonChanged { SRHaptic.select() }
        if events.won { end() }
    }

    /// Everyone is at the flag. The record is kept now, in case the screen is
    /// left before the card comes up.
    private func end() {
        sync()
        stage = .cheering
        cheerAt = playTime
        releaseAll()
        SRHaptic.ok()
        confetti()
        // A walkthrough watched is not a clear: nothing is kept.
        guard !watching else { return }
        var book = records
        let result = book.record(level: levelNumber, time: world.time, pops: world.pops, players: players)
        if let opened = result.opened, opened > levelNumber { book.level = opened }
        self.result = result
        if persists {
            records = book
            save()
        }
    }

    private func finish() {
        guard stage == .cheering else { return }
        if watching {
            // Back to the start of the level: now the player has a go.
            play()
            show("Your turn")
            return
        }
        stage = .over
        stopClock()
    }

    private func save() {
        guard persists else { return }
        store.save(records)
    }

    private func show(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - Sparks

    private func burst(at index: Int, kind: TetherPalsSparkKind, count: Int, speed: Double, up: Bool) {
        guard index >= 0, index < world.pals.count else { return }
        let pal = world.pals[index]
        let x = pal.centreX
        let y = kind == .dust || kind == .boost ? pal.bottom : pal.centreY
        for i in 0..<count {
            let spread = up ? Double.pi * 0.8 : Double.pi * 2
            let angle = (up ? -Double.pi / 2 - spread / 2 : 0) + spread * (Double(i) + random.unit()) / Double(count)
            let v = speed * random.range(0.5, 1)
            sparks.append(TetherPalsSpark(x: x, y: y, vx: cos(angle) * v, vy: sin(angle) * v - (kind == .dust ? 0.6 : 0),
                                          born: playTime, life: random.range(0.35, 0.7),
                                          size: kind == .poof ? random.range(0.1, 0.18) : random.range(0.05, 0.1),
                                          kind: kind, tint: Double(index)))
        }
    }

    /// The level is cleared: a fountain of colour from the flag.
    private func confetti() {
        let x = Double(level.flag.col) + 0.5, y = Double(level.flag.row)
        for _ in 0..<70 {
            let angle = -Double.pi / 2 + random.range(-1.1, 1.1)
            let v = random.range(4, 9)
            sparks.append(TetherPalsSpark(x: x, y: y, vx: cos(angle) * v, vy: sin(angle) * v,
                                          born: playTime + random.range(0, 0.3), life: random.range(1, 1.6),
                                          size: random.range(0.07, 0.13), kind: .confetti, tint: random.unit()))
        }
    }

    // MARK: - Words

    /// The board in words, for VoiceOver.
    var boardLabel: String {
        var words = "Level \(levelNumber), \(level.name). "
        if level.tied { words += "The pals are tied together. " }
        for index in 0..<team { words += world.describe(index) + " " }
        for channel in TetherPalsChannel.allCases where level.uses(channel) {
            let colour = channel == .gold ? "Gold" : "Blue"
            words += world.isPressed(channel) ? "\(colour) button pressed. " : "\(colour) button up. "
        }
        return words.trimmingCharacters(in: .whitespaces)
    }
}
