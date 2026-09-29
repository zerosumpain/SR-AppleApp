import Foundation
import CoreGraphics

// Draw & Guess's wire pieces and the rules the phone applies itself — keeping
// the drawing in step with the server's changes, putting a finger's path onto
// the 0…1000 canvas, thinning it before it is sent, batching it while the
// finger moves, the host's options — as pure values, so each is a unit test.
// The server judges every guess and keeps the score; nothing here decides
// whether a guess is right.

/// Where a Draw & Guess room is. Its own enum, not `GamePhase`: `picking` and
/// `drawing` are this game's alone, and the shared enum reads them as unknown.
enum DrawGuessPhase: String, Equatable {
    case lobby, countdown, picking, drawing, reveal, finished, closed, unknown

    static func from(_ raw: String?) -> DrawGuessPhase {
        raw.flatMap(DrawGuessPhase.init(rawValue:)) ?? .unknown
    }
}

/// A point on the square canvas, 0…1000 on both axes.
struct DrawGuessPoint: Equatable, Hashable {
    var x: Int
    var y: Int

    init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

/// One line of the drawing.
struct DrawGuessStroke: Decodable, Equatable, Identifiable {
    let id: Int
    /// A palette name: black, red, … white (the eraser).
    let color: String
    /// Pen width in canvas units.
    let width: Int
    var points: [DrawGuessPoint]

    init(id: Int, color: String, width: Int, points: [DrawGuessPoint]) {
        self.id = id
        self.color = color
        self.width = width
        self.points = points
    }

    private enum CodingKeys: String, CodingKey { case id, color, width, points }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? "black"
        width = (try? c.decodeIfPresent(Int.self, forKey: .width)) ?? DrawGuessPen.widths[0]
        points = DrawGuessWire.points((try? c.decodeIfPresent([[Double]].self, forKey: .points)) ?? nil)
    }
}

/// One change to the drawing, numbered by the room's drawing revision.
enum DrawGuessOp: Decodable, Equatable {
    /// Points for a stroke: appended to the stroke with that id, or a new one.
    case stroke(seq: Int, DrawGuessStroke)
    case undo(seq: Int)
    case clear(seq: Int)
    /// An op this version does not know; skipped.
    case other(seq: Int)

    var seq: Int {
        switch self {
        case .stroke(let seq, _), .undo(let seq), .clear(let seq), .other(let seq): return seq
        }
    }

    private enum CodingKeys: String, CodingKey { case seq, op }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let seq = try c.decode(Int.self, forKey: .seq)
        switch (try? c.decodeIfPresent(String.self, forKey: .op)) ?? nil {
        case "stroke": self = .stroke(seq: seq, try DrawGuessStroke(from: decoder))
        case "undo": self = .undo(seq: seq)
        case "clear": self = .clear(seq: seq)
        default: self = .other(seq: seq)
        }
    }
}

/// `drawing` on the wire: the whole drawing (`since` nil, `strokes`), or the
/// changes after `since` (`ops`).
struct DrawGuessDrawingWire: Decodable, Equatable {
    let revision: Int
    let since: Int?
    let strokes: [DrawGuessStroke]?
    let ops: [DrawGuessOp]?

    init(revision: Int, since: Int?, strokes: [DrawGuessStroke]?, ops: [DrawGuessOp]?) {
        self.revision = revision
        self.since = since
        self.strokes = strokes
        self.ops = ops
    }

    private enum CodingKeys: String, CodingKey { case revision, since, strokes, ops }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revision = try c.decode(Int.self, forKey: .revision)
        since = (try? c.decodeIfPresent(Int.self, forKey: .since)) ?? nil
        strokes = (try? c.decodeIfPresent([DrawGuessStroke].self, forKey: .strokes)) ?? nil
        ops = (try? c.decodeIfPresent([DrawGuessOp].self, forKey: .ops)) ?? nil
    }
}

/// A line in the guess feed. `close` entries reach only their guesser.
struct DrawGuessFeedEntry: Decodable, Equatable, Identifiable {
    let n: Int
    let playerId: String
    let name: String
    /// guess | solved | close.
    let kind: String
    /// The guess as typed; nil for "solved" (a right answer is never shown).
    let text: String?

    var id: Int { n }

    private enum CodingKeys: String, CodingKey { case n, playerId, name, kind, text }

    init(n: Int, playerId: String, name: String, kind: String, text: String?) {
        self.n = n
        self.playerId = playerId
        self.name = name
        self.kind = kind
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = (try? c.decodeIfPresent(Int.self, forKey: .n)) ?? 0
        playerId = (try? c.decodeIfPresent(String.self, forKey: .playerId)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Someone"
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "guess"
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? nil
    }
}

/// Somebody who guessed it, and what it scored them.
struct DrawGuessSolver: Decodable, Equatable, Identifiable {
    let id: String
    let points: Int

    private enum CodingKeys: String, CodingKey { case id, points }

    init(id: String, points: Int) {
        self.id = id
        self.points = points
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        points = (try? c.decodeIfPresent(Int.self, forKey: .points)) ?? 0
    }
}

/// The drawing in progress (or the last one, at the reveal and finish).
struct DrawGuessTurn: Decodable, Equatable {
    /// Position in the order, from 0; `of` turns in all.
    let index: Int
    let of: Int
    let drawerId: String
    let startedAt: Double?
    /// The drawer's three words, while picking. Nil for everyone else.
    let choices: [String]?
    /// The drawer's and a solver's while drawing; everyone's once it ends.
    let word: String?
    /// While drawing: letters `_` until given away, spaces kept.
    let hint: String?
    let solvers: [DrawGuessSolver]
    /// Once it ends.
    let drawerPoints: Int?
    /// time | solved | left, once it ends.
    let ended: String?
    let feed: [DrawGuessFeedEntry]

    private enum CodingKeys: String, CodingKey {
        case index, of, drawerId, startedAt, choices, word, hint, solvers, drawerPoints, ended, feed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = max(0, (try? c.decodeIfPresent(Int.self, forKey: .index)) ?? 0)
        of = max(1, (try? c.decodeIfPresent(Int.self, forKey: .of)) ?? 1)
        drawerId = (try? c.decodeIfPresent(String.self, forKey: .drawerId)) ?? ""
        startedAt = (try? c.decodeIfPresent(Double.self, forKey: .startedAt)) ?? nil
        choices = (try? c.decodeIfPresent([String].self, forKey: .choices)) ?? nil
        word = (try? c.decodeIfPresent(String.self, forKey: .word)) ?? nil
        hint = (try? c.decodeIfPresent(String.self, forKey: .hint)) ?? nil
        solvers = (try? c.decodeIfPresent([DrawGuessSolver].self, forKey: .solvers)) ?? []
        drawerPoints = (try? c.decodeIfPresent(Int.self, forKey: .drawerPoints)) ?? nil
        ended = (try? c.decodeIfPresent(String.self, forKey: .ended)) ?? nil
        feed = (try? c.decodeIfPresent([DrawGuessFeedEntry].self, forKey: .feed)) ?? []
    }
}

/// A player's Draw & Guess flags (the rest is `GamePlayer`).
struct DrawGuessSeat: Decodable, Equatable {
    let id: String
    let solved: Bool
    let isDrawing: Bool

    private enum CodingKeys: String, CodingKey { case id, solved, isDrawing }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        solved = (try? c.decodeIfPresent(Bool.self, forKey: .solved)) ?? false
        isDrawing = (try? c.decodeIfPresent(Bool.self, forKey: .isDrawing)) ?? false
    }
}

/// Everything Draw & Guess adds to a room, read from the same JSON as
/// `GameRoom` (`GameRoom.drawGuess`).
struct DrawGuessState: Decodable, Equatable {
    let phase: DrawGuessPhase
    let turnsEach: Int
    let pickMs: Double
    let revealMs: Double
    let turn: DrawGuessTurn?
    let drawing: DrawGuessDrawingWire?
    let palette: [String]
    let widths: [Int]
    let seats: [DrawGuessSeat]

    private enum CodingKeys: String, CodingKey {
        case phase, turnsEach, pickMs, revealMs, turn, drawing, palette, widths, players
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = DrawGuessPhase.from((try? c.decodeIfPresent(String.self, forKey: .phase)) ?? nil)
        turnsEach = max(1, (try? c.decodeIfPresent(Int.self, forKey: .turnsEach)) ?? 1)
        pickMs = (try? c.decodeIfPresent(Double.self, forKey: .pickMs)) ?? 10_000
        revealMs = (try? c.decodeIfPresent(Double.self, forKey: .revealMs)) ?? 5_000
        turn = (try? c.decodeIfPresent(DrawGuessTurn.self, forKey: .turn)) ?? nil
        drawing = (try? c.decodeIfPresent(DrawGuessDrawingWire.self, forKey: .drawing)) ?? nil
        let palette = ((try? c.decodeIfPresent([String].self, forKey: .palette)) ?? nil) ?? []
        self.palette = palette.isEmpty ? DrawGuessPen.palette : palette
        let widths = ((try? c.decodeIfPresent([Int].self, forKey: .widths)) ?? nil) ?? []
        self.widths = widths.isEmpty ? DrawGuessPen.widths : widths
        seats = (try? c.decodeIfPresent([DrawGuessSeat].self, forKey: .players)) ?? []
    }

    func seat(_ id: String) -> DrawGuessSeat? { seats.first { $0.id == id } }
}

enum DrawGuessWire {
    /// `[[x, y], …]` onto the canvas: rounded, clamped, anything malformed dropped.
    static func points(_ raw: [[Double]]?) -> [DrawGuessPoint] {
        (raw ?? []).compactMap { pair in
            guard pair.count == 2, pair[0].isFinite, pair[1].isFinite else { return nil }
            return DrawGuessPoint(DrawGuessGeometry.clamp(Int(pair[0].rounded())),
                                  DrawGuessGeometry.clamp(Int(pair[1].rounded())))
        }
    }
}

// MARK: - The drawing, kept in step

/// The drawing as this phone holds it, and the revision it holds it at — what
/// every post says back as `since`, so the server sends only what is new.
struct DrawGuessCanvas: Equatable {
    private(set) var strokes: [DrawGuessStroke] = []
    /// Nil until a whole drawing has arrived.
    private(set) var revision: Int?

    enum Outcome: Equatable {
        /// Taken in (possibly nothing new).
        case applied
        /// Older than what this phone holds: ignored.
        case stale
        /// Changes after a revision this phone never had: fetch the whole drawing.
        case gap
    }

    /// No drawing (the lobby, a new game): forget it.
    mutating func reset() {
        strokes = []
        revision = nil
    }

    mutating func apply(_ wire: DrawGuessDrawingWire) -> Outcome {
        if wire.since == nil {
            if let revision, wire.revision < revision { return .stale }
            strokes = wire.strokes ?? []
            revision = wire.revision
            return .applied
        }
        guard let held = revision, let since = wire.since, since <= held else { return .gap }
        guard wire.revision > held else { return .stale }
        for op in wire.ops ?? [] where op.seq > held {
            switch op {
            case .stroke(_, let piece):
                if let at = strokes.firstIndex(where: { $0.id == piece.id }) {
                    strokes[at].points += piece.points
                } else {
                    strokes.append(piece)
                }
            case .undo:
                if !strokes.isEmpty { strokes.removeLast() }
            case .clear:
                strokes.removeAll()
            case .other:
                break
            }
        }
        revision = wire.revision
        return .applied
    }
}

// MARK: - Geometry

enum DrawGuessGeometry {
    /// The canvas's side in wire units.
    static let side = 1000

    static func clamp(_ v: Int) -> Int { min(side, max(0, v)) }

    /// A point on a view `size` points square onto the canvas.
    static func quantise(_ p: CGPoint, size: CGFloat) -> DrawGuessPoint {
        guard size > 0 else { return DrawGuessPoint(0, 0) }
        let k = CGFloat(side) / size
        let q = { (v: CGFloat) -> Int in
            guard v.isFinite else { return 0 }
            return clamp(Int((v * k).rounded()))
        }
        return DrawGuessPoint(q(p.x), q(p.y))
    }

    /// A canvas point back onto a view `size` points square.
    static func place(_ p: DrawGuessPoint, size: CGFloat) -> CGPoint {
        let k = size / CGFloat(side)
        return CGPoint(x: CGFloat(p.x) * k, y: CGFloat(p.y) * k)
    }

    /// Ramer–Douglas–Peucker: drop the points within `tolerance` canvas units of
    /// the line between those kept. The first and last always stay.
    static func simplify(_ points: [DrawGuessPoint], tolerance: Double) -> [DrawGuessPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (lo, hi) = stack.popLast() {
            guard hi > lo + 1 else { continue }
            var best = -1.0
            var at = lo
            for i in (lo + 1)..<hi {
                let d = distance(points[i], from: points[lo], to: points[hi])
                if d > best {
                    best = d
                    at = i
                }
            }
            if best > tolerance {
                keep[at] = true
                stack.append((lo, at))
                stack.append((at, hi))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    /// How far `p` is from the segment `a`–`b`.
    static func distance(_ p: DrawGuessPoint, from a: DrawGuessPoint, to b: DrawGuessPoint) -> Double {
        let (px, py) = (Double(p.x), Double(p.y))
        let (ax, ay) = (Double(a.x), Double(a.y))
        let (dx, dy) = (Double(b.x) - ax, Double(b.y) - ay)
        let length = dx * dx + dy * dy
        guard length > 0 else { return hypot(px - ax, py - ay) }
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / length))
        return hypot(px - (ax + t * dx), py - (ay + t * dy))
    }
}

// MARK: - The pen

/// One post's worth of a stroke: `{action:"stroke", id, color, width, points}`.
struct DrawGuessStrokePost: Equatable {
    let id: Int
    let color: String
    let width: Int
    let points: [DrawGuessPoint]

    var body: GameActionBody {
        var body = GameActionBody(action: "stroke")
        body.id = id
        body.color = color
        body.width = width
        body.points = points.map { [$0.x, $0.y] }
        return body
    }
}

/// The drawer's finger, as posts. Points land here as the finger moves; a
/// timer takes a batch every ~200 ms and the lift takes the rest, each thinned
/// (RDP) against the last point sent so the joins stay true. Every batch of
/// one stroke carries the same id, so the server appends them.
struct DrawGuessPen: Equatable {
    static let palette = ["black", "red", "orange", "yellow", "green", "blue", "purple", "brown", "white"]
    static let widths = [6, 14, 32]
    /// How often a moving finger is sent.
    static let batchInterval: TimeInterval = 0.2
    /// Canvas units a thinned point may stray from the line (the canvas is 1000 wide).
    static let tolerance = 1.5
    /// The server's cap per post.
    static let maxPostPoints = 300

    var color = "black"
    var width = 14
    /// The stroke being drawn, or nil with the finger up.
    private(set) var strokeId: Int?
    /// Every point of the stroke being drawn, as the finger made it — what the
    /// drawer sees at once, before the server has any of it.
    private(set) var live: [DrawGuessPoint] = []
    private var pending: [DrawGuessPoint] = []
    private var lastSent: DrawGuessPoint?
    private var nextId: Int

    init(firstId: Int = 1) {
        nextId = firstId
    }

    var isDown: Bool { strokeId != nil }
    var hasPending: Bool { !pending.isEmpty }

    /// The finger lands: a new stroke.
    mutating func down(at p: DrawGuessPoint) {
        strokeId = nextId
        nextId += 1
        live = [p]
        pending = [p]
        lastSent = nil
    }

    /// The finger moves. A point on the one before is dropped.
    mutating func move(to p: DrawGuessPoint) {
        guard isDown, live.last != p else { return }
        live.append(p)
        pending.append(p)
    }

    /// What the timer sends: the points since the last batch, thinned. Nil if
    /// there is nothing new.
    mutating func batch() -> DrawGuessStrokePost? {
        guard let id = strokeId, !pending.isEmpty else { return nil }
        let anchored = (lastSent.map { [$0] } ?? []) + pending
        var thinned = DrawGuessGeometry.simplify(anchored, tolerance: Self.tolerance)
        if lastSent != nil { thinned.removeFirst() }
        // A single tap is a dot: send it twice so it has length.
        if lastSent == nil, thinned.count == 1 { thinned.append(thinned[0]) }
        if thinned.count > Self.maxPostPoints {
            // Leave the rest for the next batch, from where this one stops.
            let sent = Array(thinned.prefix(Self.maxPostPoints))
            pending = Array(thinned.dropFirst(Self.maxPostPoints))
            lastSent = sent.last
            return DrawGuessStrokePost(id: id, color: color, width: width, points: sent)
        }
        pending = []
        lastSent = thinned.last ?? lastSent
        guard !thinned.isEmpty else { return nil }
        return DrawGuessStrokePost(id: id, color: color, width: width, points: thinned)
    }

    /// The finger lifts: the last batch, and the pen is up.
    mutating func up() -> [DrawGuessStrokePost] {
        var posts: [DrawGuessStrokePost] = []
        while let post = batch() { posts.append(post) }
        strokeId = nil
        live = []
        return posts
    }

    /// The drawing ended under the finger: drop what was not sent.
    mutating func cancel() {
        strokeId = nil
        live = []
        pending = []
        lastSent = nil
    }
}

// MARK: - The game the host picks

struct DrawGuessSettings: Equatable {
    static let turns = [1, 2]
    static let times = [60, 80, 100]

    var difficulty: GameDifficulty
    var turnsEach: Int = 1
    var seconds: Int = 80

    func createBody(invite: [String]) -> CreateGameBody {
        CreateGameBody(
            game: GameKind.drawGuess.rawValue,
            difficulty: difficulty.rawValue,
            invite: invite,
            seconds: seconds,
            turnsEach: turnsEach
        )
    }

    /// "Once round", "Twice round".
    static func turnsLabel(_ n: Int) -> String { n == 2 ? "Twice round" : "Once round" }

    /// "80 s".
    static func timeLabel(_ seconds: Int) -> String { "\(seconds) s" }

    /// "80 s a drawing · twice round", for the lobby.
    static func about(_ room: GameRoom) -> String {
        var parts: [String] = []
        if let limit = room.timeLimitMs { parts.append("\(timeLabel(Int((limit / 1000).rounded()))) a drawing") }
        if (room.drawGuess?.turnsEach ?? 1) == 2 { parts.append("twice round") }
        return parts.isEmpty ? "Draw & Guess" : parts.joined(separator: " · ")
    }
}

// MARK: - What the screen says

enum DrawGuessText {
    /// The hint spaced for reading: "a _ _ l e", a gap of three between words.
    static func spaced(_ hint: String) -> String {
        hint.split(separator: " ", omittingEmptySubsequences: false)
            .map { word in word.map { String($0) }.joined(separator: " ") }
            .joined(separator: "   ")
    }

    /// "5 letters", "3, 5 letters" for two words.
    static func letters(_ hint: String) -> String {
        let words = hint.split(separator: " ").map(\.count)
        guard !words.isEmpty else { return "" }
        return words.map(String.init).joined(separator: ", ") + (words == [1] ? " letter" : " letters")
    }

    /// Whether a guess may go now: something typed, not too soon after the last.
    static func canSend(_ text: String, lastSentAt: Double?, now: Double, gapMs: Double = 700) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return false }
        guard let last = lastSentAt else { return true }
        return now - last >= gapMs
    }
}
