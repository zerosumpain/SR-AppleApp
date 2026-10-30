import Foundation

/// One golfer in a pass-the-phone round.
struct MiniGolfPlayer: Equatable, Identifiable, Codable {
    let id: Int
    var name: String
    /// Which colour they play in (`OfflineSeatColour`).
    var seat: Int
}

/// What a score on a hole is called.
enum MiniGolfScoreWord {
    /// "Hole in one!", "Birdie", "Par", "Bogey"… for `strokes` on a par `par`.
    static func word(strokes: Int, par: Int) -> String {
        if strokes == 1 { return "Hole in one!" }
        switch strokes - par {
        case ...(-3): return "Albatross!"
        case -2: return "Eagle!"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double bogey"
        case 3: return "Triple bogey"
        default: return "\(strokes - par) over"
        }
    }

    /// A score against par as written on a card: "E", "−2", "+3".
    static func toPar(_ diff: Int) -> String {
        if diff == 0 { return "E" }
        return diff < 0 ? "\u{2212}\(-diff)" : "+\(diff)"
    }

    /// Better than par, par, or worse: how a scorecard colours a score.
    static func tone(strokes: Int, par: Int) -> Int { strokes < par ? -1 : (strokes == par ? 0 : 1) }
}

/// A round of mini golf: who is playing, which holes, and the scorecard.
///
/// Each player plays the whole hole in turn (pass the phone after each
/// holes out), then the next hole starts with the first player again.
struct MiniGolfRound: Equatable {
    let loop: MiniGolfLoop
    let players: [MiniGolfPlayer]
    /// Strokes by player, then by hole in this round; nil until played.
    private(set) var scores: [[Int?]]
    /// Which of the round's holes is being played, from 0.
    private(set) var holeSlot = 0
    /// Whose turn it is, by index into `players`.
    private(set) var turn = 0

    init(loop: MiniGolfLoop, players: [MiniGolfPlayer]) {
        self.loop = loop
        let who = players.isEmpty ? [MiniGolfPlayer(id: 0, name: "You", seat: 0)] : Array(players.prefix(4))
        self.players = who
        scores = Array(repeating: Array(repeating: nil, count: loop.holeIndices.count), count: who.count)
    }

    var holeCount: Int { loop.holeIndices.count }
    var hole: MiniGolfHole { MiniGolfCourse.holes[loop.holeIndices[min(holeSlot, holeCount - 1)]] }
    var player: MiniGolfPlayer { players[min(turn, players.count - 1)] }
    var isSolo: Bool { players.count == 1 }
    /// Every player has finished every hole.
    var isOver: Bool { scores.allSatisfy { row in row.allSatisfy { $0 != nil } } }
    /// Every player has finished the hole being played.
    var holeDone: Bool { scores.allSatisfy { $0[holeSlot] != nil } }

    /// The hole in slot `slot` of this round.
    func hole(at slot: Int) -> MiniGolfHole { MiniGolfCourse.holes[loop.holeIndices[slot]] }

    func strokes(player: Int, slot: Int) -> Int? {
        guard scores.indices.contains(player), scores[player].indices.contains(slot) else { return nil }
        return scores[player][slot]
    }

    /// The current player finished the current hole in `strokes`. Moves the
    /// turn to the next player who has not played it; returns the score's word.
    @discardableResult
    mutating func record(strokes: Int) -> String {
        let capped = min(max(1, strokes), MiniGolfRules.maxStrokes(par: hole.par))
        scores[turn][holeSlot] = capped
        let word = MiniGolfScoreWord.word(strokes: capped, par: hole.par)
        if let next = (0..<players.count).first(where: { scores[$0][holeSlot] == nil }) { turn = next }
        return word
    }

    /// On to the next hole once everyone has played this one. False at the end of the round.
    @discardableResult
    mutating func nextHole() -> Bool {
        guard holeDone, holeSlot + 1 < holeCount else { return false }
        holeSlot += 1
        turn = 0
        return true
    }

    /// Strokes so far for player `index`.
    func total(_ index: Int) -> Int { scores[index].compactMap { $0 }.reduce(0, +) }

    /// Par of the holes player `index` has finished.
    func parPlayed(_ index: Int) -> Int {
        var par = 0
        for (slot, score) in scores[index].enumerated() where score != nil { par += hole(at: slot).par }
        return par
    }

    func toPar(_ index: Int) -> Int { total(index) - parPlayed(index) }

    /// Players best first: fewest strokes, then the order they played in.
    var standings: [Int] {
        players.indices.sorted { a, b in
            let ta = total(a), tb = total(b)
            return ta == tb ? a < b : ta < tb
        }
    }

    /// The winner's index once the round is over, or nil for a tie at the top.
    var winner: Int? {
        guard isOver, players.count > 1 else { return isOver ? 0 : nil }
        let order = standings
        guard order.count > 1 else { return order.first }
        return total(order[0]) == total(order[1]) ? nil : order[0]
    }
}

/// Mini Golf's bests, on this phone: the best round on each loop and the best
/// score on each hole, whoever played it.
struct MiniGolfBook: Codable, Equatable {
    /// Fewest strokes for a whole round, by `MiniGolfLoop.rawValue`.
    var bestRound: [String: Int] = [:]
    /// Fewest strokes on each hole, by hole number as text ("1"…"18").
    var bestHole: [String: Int] = [:]
    var holesInOne = 0
    var rounds = 0

    func best(hole number: Int) -> Int? { bestHole["\(number)"] }
    func best(loop: MiniGolfLoop) -> Int? { bestRound[loop.rawValue] }

    /// A finished hole. True when it beats the best on that hole.
    @discardableResult
    mutating func noteHole(_ number: Int, strokes: Int) -> Bool {
        if strokes == 1 { holesInOne += 1 }
        let key = "\(number)"
        guard strokes < (bestHole[key] ?? .max) else { return false }
        bestHole[key] = strokes
        return true
    }

    /// A finished round. True when it beats the best on that loop.
    @discardableResult
    mutating func noteRound(_ loop: MiniGolfLoop, strokes: Int) -> Bool {
        rounds += 1
        guard strokes < (bestRound[loop.rawValue] ?? .max) else { return false }
        bestRound[loop.rawValue] = strokes
        return true
    }
}

/// Where the book lives: UserDefaults, under the game's own key.
struct MiniGolfStore {
    var defaults: UserDefaults = .standard
    static let key = "mini-golf.book.v1"

    func load() -> MiniGolfBook {
        guard let data = defaults.data(forKey: Self.key),
              let book = try? JSONDecoder().decode(MiniGolfBook.self, from: data) else { return MiniGolfBook() }
        return book
    }

    func save(_ book: MiniGolfBook) {
        if let data = try? JSONEncoder().encode(book) { defaults.set(data, forKey: Self.key) }
    }
}

/// Where the camera looks and how close: points per course unit, and the
/// course point at the middle of the picture.
struct MiniGolfCamera: Equatable {
    var centre: MiniGolfVec
    var scale: Double

    /// Never closer than this, points per unit, so a small hole is not a giant one.
    static let closest = 16.0
    /// Close enough that a ball is easy to see and aim: if the whole hole
    /// would be smaller than this, the camera follows the ball instead.
    static let comfortable = 10.0

    /// The camera for a hole whose frame is `bounds`, in a picture `width` ×
    /// `height` points, following `focus`. `overview` shows the whole hole
    /// however small.
    static func framing(_ bounds: MiniGolfBox, width: Double, height: Double, focus: MiniGolfVec,
                        overview: Bool = false) -> MiniGolfCamera {
        let margin = 2.0
        let w = max(1, width), h = max(1, height)
        let box = bounds.outset(margin)
        let fit = min(w / box.width, h / box.height)
        let acrossFit = w / box.width
        var scale: Double
        if overview || fit >= comfortable {
            scale = min(fit, closest)
        } else {
            scale = min(acrossFit, max(fit, comfortable))
        }
        scale = max(scale, 1)
        let halfW = w / 2 / scale, halfH = h / 2 / scale
        func clamp(_ value: Double, _ low: Double, _ high: Double, _ middle: Double) -> Double {
            low > high ? middle : min(max(value, low), high)
        }
        let cx = clamp(focus.x, box.minX + halfW, box.maxX - halfW, box.centre.x)
        let cy = clamp(focus.y, box.minY + halfH, box.maxY - halfH, box.centre.y)
        return MiniGolfCamera(centre: MiniGolfVec(cx, cy), scale: scale)
    }

    /// Eased towards `target`: `rate` is how much of the way per second.
    func eased(towards target: MiniGolfCamera, dt: Double, rate: Double = 5) -> MiniGolfCamera {
        let k = min(1, max(0, dt * rate))
        return MiniGolfCamera(centre: centre + (target.centre - centre) * k, scale: scale + (target.scale - scale) * k)
    }
}
