import Foundation

// Sequence Memory's wire pieces and the rules the phone applies itself — when
// each tile flashes, which tile is lit at an instant, collecting the taps — as
// pure values, so each is a unit test rather than something only two phones
// side by side can show.
//
// The server deals each round's flashes AHEAD with its own times (`steps[].at`)
// so every phone lights the same tile at the same instant, whatever its
// latency — Tap Duel's `goAt`, many times over. The phone maps those instants
// onto its own clock through `GameClock`, exactly as Tap Duel does. During
// `input` the sequence is off the wire: the phone does not know it, so it can
// only collect the player's taps and send them once there are `length` of them.

/// One flash: which tile, when it starts (server epoch ms), how long it lasts.
struct SequenceStep: Decodable, Equatable {
    let tile: Int
    let at: Double
    let ms: Double

    init(tile: Int, at: Double, ms: Double) {
        self.tile = tile; self.at = at; self.ms = ms
    }
}

/// A player's attempt, shown at the result. `taps` nil: the window closed
/// without one.
struct SequenceAttempt: Decodable, Equatable {
    let playerId: String
    let taps: [Int]?
    let correct: Bool

    private enum CodingKeys: String, CodingKey { case playerId, taps, correct }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(String.self, forKey: .playerId)
        taps = (try? c.decodeIfPresent([Int].self, forKey: .taps)) ?? nil
        correct = (try? c.decodeIfPresent(Bool.self, forKey: .correct)) ?? false
    }
}

/// One round: the show's timing, the input window, and — once settled — how
/// everyone did.
struct SequenceRound: Decodable, Equatable {
    let number: Int
    let length: Int
    let showAt: Double
    let stepMs: Double
    let gapMs: Double
    /// The flashes: during `show` and once settled. NIL during `input`.
    let steps: [SequenceStep]?
    let inputAt: Double
    let windowMs: Double
    let inputEndsAt: Double
    let closesAt: Double?
    /// Who has sent an attempt — never what, until the result.
    let answeredIds: [String]
    let attempts: [SequenceAttempt]?
    let survivorIds: [String]?

    private enum CodingKeys: String, CodingKey {
        case number, length, showAt, stepMs, gapMs, steps, inputAt, windowMs, inputEndsAt, closesAt
        case answeredIds, attempts, survivorIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Required: without these it is not this game's round (Tap Duel's
        // round has none of them, and decodes as `GameRound` instead).
        number = try c.decode(Int.self, forKey: .number)
        let start = try c.decode(Double.self, forKey: .showAt)
        let count = try c.decode(Int.self, forKey: .length)
        let step = (try? c.decodeIfPresent(Double.self, forKey: .stepMs)) ?? 700
        let gap = (try? c.decodeIfPresent(Double.self, forKey: .gapMs)) ?? 150
        let opens = (try? c.decodeIfPresent(Double.self, forKey: .inputAt))
            ?? SequenceSchedule.inputAt(showAt: start, stepMs: step, gapMs: gap, length: count)
        let window = (try? c.decodeIfPresent(Double.self, forKey: .windowMs)) ?? SequenceSchedule.windowMs(length: count)
        length = count
        showAt = start
        stepMs = step
        gapMs = gap
        steps = (try? c.decodeIfPresent([SequenceStep].self, forKey: .steps)) ?? nil
        inputAt = opens
        windowMs = window
        inputEndsAt = (try? c.decodeIfPresent(Double.self, forKey: .inputEndsAt)) ?? (opens + window)
        closesAt = (try? c.decodeIfPresent(Double.self, forKey: .closesAt)) ?? nil
        answeredIds = (try? c.decodeIfPresent([String].self, forKey: .answeredIds)) ?? []
        attempts = (try? c.decodeIfPresent([SequenceAttempt].self, forKey: .attempts)) ?? nil
        survivorIds = (try? c.decodeIfPresent([String].self, forKey: .survivorIds)) ?? nil
    }

    func attempt(of playerId: String) -> SequenceAttempt? { attempts?.first { $0.playerId == playerId } }

    /// The sequence itself, when the round carries it.
    var sequence: [Int]? { steps?.map(\.tile) }
}

/// When the flashes happen.
enum SequenceSchedule {
    /// The spec's input window: 2 s plus 800 ms a step.
    static func windowMs(length: Int) -> Double { 2000 + 800 * Double(length) }

    /// Flash `i` starts at `showAt + i·(step + gap)` and lasts `step`.
    static func flashes(showAt: Double, stepMs: Double, gapMs: Double, tiles: [Int]) -> [SequenceStep] {
        tiles.enumerated().map { i, tile in
            SequenceStep(tile: tile, at: showAt + Double(i) * (stepMs + gapMs), ms: stepMs)
        }
    }

    /// The window opens when the last flash ends.
    static func inputAt(showAt: Double, stepMs: Double, gapMs: Double, length: Int) -> Double {
        guard length > 0 else { return showAt }
        return showAt + Double(length) * stepMs + Double(length - 1) * gapMs
    }

    /// The flash showing at a server instant: its index in the round and its
    /// tile, or nil between flashes and outside the show.
    static func lit(_ steps: [SequenceStep], atServer now: Double) -> (step: Int, tile: Int)? {
        for (i, step) in steps.enumerated() where now >= step.at && now < step.at + step.ms {
            return (step: i, tile: step.tile)
        }
        return nil
    }

    /// The input window is open at this server instant: the room says so, or
    /// the show is over by the phone's reckoning and the frame has not come.
    static func inputOpen(phase: GamePhase, round: SequenceRound, atServer now: Double?) -> Bool {
        if phase == .input { return true }
        guard phase == .show, let now else { return false }
        return now >= round.inputAt
    }

    /// "Grid" columns for a tile count: 2×2, 2×3, 3×3.
    static func columns(tiles: Int) -> Int {
        tiles <= 4 ? 2 : 3
    }
}

/// The taps for one round. Nothing is sent until there are `length` of them;
/// until then Undo takes the last one back. Once complete it is locked: the
/// attempt is the phone's one answer.
struct SequenceTaps: Equatable {
    let round: Int
    let length: Int
    let tiles: Int
    private(set) var taps: [Int] = []

    init(round: Int, length: Int, tiles: Int) {
        self.round = round
        self.length = max(1, length)
        self.tiles = max(1, tiles)
    }

    var isComplete: Bool { taps.count >= length }
    var canUndo: Bool { !taps.isEmpty && !isComplete }

    enum Outcome: Equatable {
        /// Taken; more wanted.
        case added
        /// Taken, and that was the last: send these.
        case complete([Int])
        /// Not a tile, or the attempt is already complete.
        case ignored
    }

    mutating func tap(_ tile: Int) -> Outcome {
        guard !isComplete, tile >= 0, tile < tiles else { return .ignored }
        taps.append(tile)
        return isComplete ? .complete(taps) : .added
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard canUndo else { return false }
        taps.removeLast()
        return true
    }

    /// The body to POST: `{action:"attempt", round, taps}`.
    func body() -> GameActionBody {
        GameActionBody(action: "attempt", round: round, taps: taps)
    }
}

/// Each tile's colour and symbol. Colour is never the only carrier: every tile
/// has its own shape as well, and VoiceOver names both.
enum SequencePalette {
    /// Up to nine, distinct in hue AND lightness, from the SR tokens.
    static let names = ["Orange", "Teal", "Olive", "Mustard", "Red", "Brown", "Peach", "Sky", "Sage"]
    static let symbols = ["circle.fill", "triangle.fill", "square.fill", "star.fill", "heart.fill",
                          "diamond.fill", "moon.fill", "bolt.fill", "cloud.fill"]
    static let symbolNames = ["circle", "triangle", "square", "star", "heart", "diamond", "moon", "bolt", "cloud"]

    static func symbol(_ tile: Int) -> String { symbols[tile % symbols.count] }

    /// "Tile 3, star, mustard".
    static func spoken(_ tile: Int) -> String {
        "Tile \(tile + 1), \(symbolNames[tile % symbolNames.count]), \(names[tile % names.count].lowercased())"
    }
}
