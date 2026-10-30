import Foundation

// Where every card sits on the table, worked out from the table's size and
// the state alone. The board draws all 52 cards from this, each at its own
// spot, so when the state changes every card that moved glides to its new
// spot by itself. Foundation only (CGFloat and CGPoint come with it), so the
// fit on a 375-point phone is tested on Linux.

/// One card's place on screen.
struct SolitaireSpot: Equatable {
    var center: CGPoint
    var faceUp: Bool
    /// Drawing order: later piles and higher cards on top.
    var z: Double
    /// Drawn at all: cards buried deep in the stock or a foundation are not,
    /// so the phone does not paint fifty cards to show five.
    var visible: Bool
}

struct SolitaireLayout: Equatable {
    /// Height over width of a card.
    static let aspect: CGFloat = 1.4

    let size: CGSize
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let spacing: CGFloat
    /// The left edge of the first column.
    let originX: CGFloat
    /// The centre line of the stock, waste and foundations.
    let topRowY: CGFloat
    /// The top edge of the tableau's first cards.
    let tableauTop: CGFloat
    /// The tableau's bottom limit.
    let bottom: CGFloat

    init(size: CGSize) {
        self.size = size
        let w = max(size.width, 200)
        let h = max(size.height, 240)
        let inset: CGFloat = w < 400 ? 6 : 10
        spacing = w < 400 ? 4 : 6
        let byWidth = (w - 2 * inset - 6 * spacing) / 7
        // The top row, a gap, and a column of a king to an ace still fitting.
        let byHeight = (h - 12) / (5.4 * Self.aspect)
        cardWidth = max(30, min(byWidth, byHeight, 112).rounded(.down))
        cardHeight = (cardWidth * Self.aspect).rounded()
        originX = ((w - (7 * cardWidth + 6 * spacing)) / 2).rounded()
        topRowY = 4 + cardHeight / 2
        tableauTop = 4 + cardHeight + (cardHeight * 0.22).rounded()
        bottom = h - 6
    }

    func columnX(_ column: Int) -> CGFloat {
        originX + cardWidth / 2 + CGFloat(column) * (cardWidth + spacing)
    }

    var stockCenter: CGPoint { CGPoint(x: columnX(0), y: topRowY) }
    var wasteCenter: CGPoint { CGPoint(x: columnX(1), y: topRowY) }
    func foundationCenter(_ f: Int) -> CGPoint { CGPoint(x: columnX(3 + f), y: topRowY) }
    func tableauBase(_ t: Int) -> CGPoint { CGPoint(x: columnX(t), y: tableauTop + cardHeight / 2) }
    /// The draw-3 waste's spread.
    var wasteFan: CGFloat { (cardWidth * 0.36).rounded() }

    /// The gaps down a column: face-down cards close, face-up ones far enough
    /// apart to read the corner, both closing up when the column is long.
    func fan(faceDown: Int, faceUp: Int) -> (down: CGFloat, up: CGFloat) {
        var down = (cardHeight * 0.13).rounded()
        var up = (cardHeight * 0.30).rounded()
        let room = bottom - tableauTop - cardHeight
        let ups = CGFloat(max(faceUp - 1, 0))
        let downs = CGFloat(faceDown)
        if downs * down + ups * up > room {
            down = max((cardHeight * 0.07).rounded(), min(down, (room - ups * up) / max(downs, 1)))
            if ups > 0 {
                up = max((cardHeight * 0.18).rounded(), min(up, (room - downs * down) / ups))
            }
        }
        return (down, up)
    }

    /// The centre of card `index` in column `t`.
    func tableauCenter(_ t: Int, index: Int, pile: SolitairePile) -> CGPoint {
        let gaps = fan(faceDown: pile.faceDown, faceUp: pile.faceUpCount)
        let downs = CGFloat(min(index, pile.faceDown))
        let ups = CGFloat(max(index - pile.faceDown, 0))
        let base = tableauBase(t)
        return CGPoint(x: base.x, y: base.y + downs * gaps.down + ups * gaps.up)
    }

    /// Where a card lands if it is played to `place`: on top of what is there.
    func landing(_ place: SolitairePlace, in state: SolitaireState) -> CGPoint {
        switch place {
        case .stock: return stockCenter
        case .waste: return wasteCenter
        case .foundation(let f): return foundationCenter(f)
        case .tableau(let t):
            let pile = state.tableau[t]
            guard !pile.cards.isEmpty else { return tableauBase(t) }
            return tableauCenter(t, index: pile.cards.count - 1, pile: pile)
        }
    }

    /// Every card's spot, indexed by card id. Cards in `undealt` are still
    /// in the dealer's hand: on the stock, face down, waiting to fly.
    func spots(for state: SolitaireState, undealt: Set<Int> = []) -> [SolitaireSpot] {
        var out = Array(repeating: SolitaireSpot(center: stockCenter, faceUp: false, z: 0, visible: false), count: 52)
        let stock = state.stock
        for (i, card) in stock.enumerated() {
            // A thickness to the pack: half a point per eight cards.
            let lift = CGFloat(i / 8) * 0.5
            out[card.id] = SolitaireSpot(center: CGPoint(x: stockCenter.x - lift, y: stockCenter.y - lift),
                                         faceUp: false, z: Double(i), visible: i >= stock.count - 2)
        }
        let waste = state.waste
        let spread = state.drawMode == .three
        for (i, card) in waste.enumerated() {
            let fromTop = waste.count - 1 - i
            var x = wasteCenter.x
            if spread {
                // The top three fan to the right; the rest sit under the first.
                let shown = min(waste.count, 3)
                let slot = max(0, shown - 1 - fromTop)
                x += CGFloat(slot) * wasteFan
            }
            out[card.id] = SolitaireSpot(center: CGPoint(x: x, y: wasteCenter.y), faceUp: true,
                                         z: 100 + Double(i), visible: fromTop < (spread ? 4 : 2))
        }
        for (f, pile) in state.foundations.enumerated() {
            for (i, card) in pile.enumerated() {
                out[card.id] = SolitaireSpot(center: foundationCenter(f), faceUp: true,
                                             z: 200 + Double(i), visible: i >= pile.count - 2)
            }
        }
        for (t, pile) in state.tableau.enumerated() {
            for (i, card) in pile.cards.enumerated() {
                out[card.id] = SolitaireSpot(center: tableauCenter(t, index: i, pile: pile), faceUp: pile.isFaceUp(i),
                                             z: 300 + Double(i), visible: true)
            }
        }
        if !undealt.isEmpty {
            var order = 0
            for card in state.dealOrder.reversed() where undealt.contains(card) {
                out[card] = SolitaireSpot(center: stockCenter, faceUp: false, z: 60 + Double(order), visible: true)
                order += 1
            }
        }
        return out
    }

    /// The place a card dropped with its centre at `point` is aimed at: a
    /// foundation in the top row, a column below it, nothing over the stock.
    func dropTarget(at point: CGPoint) -> SolitairePlace? {
        let slot = column(at: point.x)
        if point.y < tableauTop - cardHeight * 0.15 {
            return slot >= 3 ? .foundation(slot - 3) : nil
        }
        return .tableau(slot)
    }

    /// Where to try a drop, best first: the place under the card, then the
    /// next column along when the card overlaps it, so a drop that is a
    /// little off still lands.
    func dropTargets(at point: CGPoint) -> [SolitairePlace] {
        guard let first = dropTarget(at: point) else { return [] }
        guard case .tableau(let t) = first else { return [first] }
        let offset = point.x - columnX(t)
        let neighbour = offset < 0 ? t - 1 : t + 1
        if abs(offset) > cardWidth * 0.2 && (0..<7).contains(neighbour) {
            return [first, .tableau(neighbour)]
        }
        return [first]
    }

    /// The column (or top-row slot) under `x`, nearest at the edges.
    func column(at x: CGFloat) -> Int {
        let pitch = cardWidth + spacing
        return min(max(Int(((x - originX + spacing / 2) / pitch).rounded(.down)), 0), 6)
    }
}

// MARK: - The win

/// A point the cascade passed through.
struct SolitaireCascadePoint: Equatable {
    var x: Double
    var y: Double
}

/// The old bouncing-cards win: the foundations empty one card at a time,
/// kings first, and each card leaps off, falls, bounces along the floor and
/// leaves a trail of itself behind, until it is off the side of the screen.
/// Stepped at a fixed 120 Hz, whatever the display does.
struct SolitaireCascade {
    struct Flyer: Equatable {
        let card: Int
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var trail: [SolitaireCascadePoint] = []
        var sinceSample: Double = 0
    }

    static let step = 1.0 / 120
    static let launchGap = 0.16
    static let gravity = 2100.0
    static let bounce = 0.74
    static let trailLength = 9
    static let trailGap = 1.0 / 28

    let width: Double
    let floor: Double
    let cardWidth: Double
    let cardHeight: Double
    let starts: [SolitaireCascadePoint]
    private(set) var flyers: [Flyer] = []
    private(set) var launched = 0
    /// Cards each foundation has already thrown.
    private(set) var thrown = [0, 0, 0, 0]
    private(set) var clock: Double = 0
    private var accumulator: Double = 0
    private var random: SolitaireRandom

    init(width: Double, floor: Double, cardWidth: Double, cardHeight: Double,
         starts: [SolitaireCascadePoint], seed: UInt64 = 7) {
        self.width = width
        self.floor = floor
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.starts = starts.count == 4 ? starts : Array(repeating: SolitaireCascadePoint(x: width / 2, y: 0), count: 4)
        self.random = SolitaireRandom(seed: seed)
    }

    /// Kings first, round the four foundations, then queens, down to aces.
    static let order: [Int] = {
        var out: [Int] = []
        for rank in stride(from: 13, through: 1, by: -1) {
            for suit in [3, 2, 1, 0] { out.append(suit * 13 + rank - 1) }
        }
        return out
    }()

    var finished: Bool { launched >= 52 && flyers.isEmpty }

    /// The card still waiting on foundation `f`, if any.
    func waiting(_ f: Int) -> Int? {
        let rank = 13 - thrown[f]
        return rank >= 1 ? f * 13 + rank - 1 : nil
    }

    mutating func advance(by dt: Double) {
        // A long gap (the app was away) is one short step, not a jump.
        accumulator += min(max(dt, 0), 0.1)
        while accumulator >= Self.step {
            tick()
            accumulator -= Self.step
        }
    }

    private mutating func tick() {
        clock += Self.step
        if launched < 52 && clock >= Double(launched) * Self.launchGap {
            launch(Self.order[launched])
            launched += 1
        }
        let halfH = cardHeight / 2
        for i in flyers.indices {
            flyers[i].vy += Self.gravity * Self.step
            flyers[i].x += flyers[i].vx * Self.step
            flyers[i].y += flyers[i].vy * Self.step
            if flyers[i].y + halfH > floor {
                flyers[i].y = floor - halfH
                flyers[i].vy = -abs(flyers[i].vy) * Self.bounce
            }
            flyers[i].sinceSample += Self.step
            if flyers[i].sinceSample >= Self.trailGap {
                flyers[i].sinceSample = 0
                flyers[i].trail.append(SolitaireCascadePoint(x: flyers[i].x, y: flyers[i].y))
                if flyers[i].trail.count > Self.trailLength { flyers[i].trail.removeFirst() }
            }
        }
        let margin = cardWidth
        flyers.removeAll { $0.x < -margin || $0.x > width + margin }
    }

    private mutating func launch(_ card: Int) {
        let f = card / 13
        thrown[f] += 1
        let start = starts[f]
        // Mostly away from the nearer edge's far side, so cards cross the table.
        let leftward = start.x > width * 0.5 ? random.unit() < 0.75 : random.unit() < 0.25
        let speed = 140 + random.unit() * 220
        let vx = leftward ? -speed : speed
        let vy = -(random.unit() * 520)
        flyers.append(Flyer(card: card, x: start.x, y: start.y, vx: vx, vy: vy))
    }
}
