import Foundation

// Klondike patience, the rules alone: the deck, the deal, what may go where,
// drawing and turning the waste back over, the hints and the finish. No
// SwiftUI here, so every rule is tested on Linux (`SolitaireTests`); the
// screen asks this file what is legal and never decides it itself.

// MARK: - Cards

/// The four suits, in the order the foundations sit on the table.
enum SolitaireSuit: Int, CaseIterable, Codable, Hashable {
    case spades = 0, hearts, diamonds, clubs

    var isRed: Bool { self == .hearts || self == .diamonds }

    /// Plural, as said aloud: "Queen of hearts".
    var name: String {
        switch self {
        case .spades: return "spades"
        case .hearts: return "hearts"
        case .diamonds: return "diamonds"
        case .clubs: return "clubs"
        }
    }

    /// The SF Symbol drawn on the card.
    var symbolName: String {
        switch self {
        case .spades: return "suit.spade.fill"
        case .hearts: return "suit.heart.fill"
        case .diamonds: return "suit.diamond.fill"
        case .clubs: return "suit.club.fill"
        }
    }
}

/// One card. Its `id` (0–51) is the card's identity on the table, so a card
/// keeps the same view wherever it goes and every move can glide.
struct SolitaireCard: Hashable, Codable, Identifiable {
    let suit: SolitaireSuit
    /// 1 (ace) to 13 (king).
    let rank: Int

    init(suit: SolitaireSuit, rank: Int) {
        self.suit = suit
        self.rank = rank
    }

    init(id: Int) {
        let safe = min(max(id, 0), 51)
        self.suit = SolitaireSuit(rawValue: safe / 13) ?? .spades
        self.rank = safe % 13 + 1
    }

    var id: Int { suit.rawValue * 13 + rank - 1 }
    var isRed: Bool { suit.isRed }

    /// The corner index: A, 2–10, J, Q, K.
    var rankLabel: String {
        switch rank {
        case 1: return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return "\(rank)"
        }
    }

    var rankName: String {
        switch rank {
        case 1: return "Ace"
        case 11: return "Jack"
        case 12: return "Queen"
        case 13: return "King"
        default: return "\(rank)"
        }
    }

    /// "Queen of hearts", for VoiceOver.
    var spoken: String { "\(rankName) of \(suit.name)" }

    /// The 52, in id order.
    static let deck: [SolitaireCard] = (0..<52).map { SolitaireCard(id: $0) }

    // Saved as its id alone: a game's undo history is a few hundred tables
    // of 52 cards, and an id is a tenth of the size of a keyed object.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let id = try container.decode(Int.self)
        guard (0..<52).contains(id) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "No card \(id)")
        }
        self.init(id: id)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }
}

/// Turn one card from the stock at a time, or three.
enum SolitaireDrawMode: Int, Codable, CaseIterable, Hashable {
    case one = 1
    case three = 3

    var count: Int { rawValue }
    var title: String { self == .one ? "Draw 1" : "Draw 3" }
    /// The key a best is filed under.
    var key: String { self == .one ? "draw1" : "draw3" }
}

/// A splitmix64 generator: the same seed deals the same game on every phone
/// and every version of Swift (the standard shuffle makes no such promise).
struct SolitaireRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< 1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }

    /// 0 ..< bound, without the bias of a plain remainder mattering at 52.
    mutating func below(_ bound: Int) -> Int {
        guard bound > 1 else { return 0 }
        return Int(next() % UInt64(bound))
    }

    /// A fresh seed for a new deal, never 0.
    static func freshSeed() -> UInt64 {
        UInt64.random(in: 1...UInt64(UInt32.max))
    }

    /// The seed after `seed`, for trying deal after deal in a fixed order.
    static func seed(after seed: UInt64) -> UInt64 {
        var g = SolitaireRandom(seed: seed)
        let next = g.next() % UInt64(UInt32.max)
        return next == 0 ? 1 : next
    }
}

// MARK: - The table

/// A tableau column: its cards bottom to top, the first `faceDown` of them
/// turned over.
struct SolitairePile: Codable, Equatable, Hashable {
    var cards: [SolitaireCard] = []
    var faceDown = 0

    var top: SolitaireCard? { cards.last }
    var faceUpCount: Int { cards.count - faceDown }
    func isFaceUp(_ index: Int) -> Bool { index >= faceDown }
}

/// Where a card can be.
enum SolitairePlace: Hashable {
    case stock
    case waste
    /// One per suit, by `SolitaireSuit.rawValue`.
    case foundation(Int)
    case tableau(Int)
}

/// Moving the top `count` cards of `from` onto `to`.
struct SolitaireMove: Hashable {
    let from: SolitairePlace
    let to: SolitairePlace
    let count: Int

    init(from: SolitairePlace, to: SolitairePlace, count: Int = 1) {
        self.from = from
        self.to = to
        self.count = count
    }
}

/// Everything a player (or the finish) can do.
enum SolitaireAction: Hashable {
    /// Turn the next one or three from the stock, or the waste back over.
    case draw
    /// Turn exactly one, whatever the draw: only the finish uses it, so a
    /// draw-3 game with every card showing always runs out.
    case turnOne
    case move(SolitaireMove)
}

/// The whole table.
struct SolitaireState: Codable, Equatable, Hashable {
    /// Face down; the top is the last.
    var stock: [SolitaireCard] = []
    /// Face up; the top (the one you may play) is the last.
    var waste: [SolitaireCard] = []
    /// Ace upwards, one per suit.
    var foundations: [[SolitaireCard]] = Array(repeating: [], count: 4)
    var tableau: [SolitairePile] = Array(repeating: SolitairePile(), count: 7)
    var drawMode: SolitaireDrawMode = .one
    /// Times the waste has been turned back into the stock. Unlimited.
    var passes = 0

    /// Deal `seed`: shuffle, then seven columns of one to seven cards, the
    /// top of each face up, and the other 24 in the stock.
    static func deal(seed: UInt64, drawMode: SolitaireDrawMode) -> SolitaireState {
        var deck = SolitaireCard.deck
        var random = SolitaireRandom(seed: seed)
        // Fisher–Yates with our own generator, so a seed is a deal for ever.
        var i = deck.count - 1
        while i > 0 {
            let j = random.below(i + 1)
            deck.swapAt(i, j)
            i -= 1
        }
        var state = SolitaireState()
        state.drawMode = drawMode
        var next = 0
        for row in 0..<7 {
            for column in row..<7 {
                state.tableau[column].cards.append(deck[next])
                next += 1
            }
        }
        for column in 0..<7 { state.tableau[column].faceDown = column }
        state.stock = Array(deck[next...])
        return state
    }

    /// The order the 28 tableau cards were dealt in, for the dealing animation.
    var dealOrder: [Int] {
        var order: [Int] = []
        for row in 0..<7 {
            for column in row..<7 where row < tableau[column].cards.count {
                order.append(tableau[column].cards[row].id)
            }
        }
        return order
    }

    var isWon: Bool { foundations.allSatisfy { $0.count == 13 } }
    /// Every tableau card is showing: from here the game cannot be lost.
    var allFaceUp: Bool { tableau.allSatisfy { $0.faceDown == 0 } }
    var canAutoComplete: Bool { allFaceUp && !isWon }
    var foundationCount: Int { foundations.reduce(0) { $0 + $1.count } }

    /// Where card `id` is, and how far up its pile.
    func locate(_ id: Int) -> (place: SolitairePlace, index: Int)? {
        if let i = stock.firstIndex(where: { $0.id == id }) { return (.stock, i) }
        if let i = waste.firstIndex(where: { $0.id == id }) { return (.waste, i) }
        for (f, pile) in foundations.enumerated() {
            if let i = pile.firstIndex(where: { $0.id == id }) { return (.foundation(f), i) }
        }
        for (t, pile) in tableau.enumerated() {
            if let i = pile.cards.firstIndex(where: { $0.id == id }) { return (.tableau(t), i) }
        }
        return nil
    }

    func cards(at place: SolitairePlace) -> [SolitaireCard] {
        switch place {
        case .stock: return stock
        case .waste: return waste
        case .foundation(let f): return foundations.indices.contains(f) ? foundations[f] : []
        case .tableau(let t): return tableau.indices.contains(t) ? tableau[t].cards : []
        }
    }

    // MARK: Rules

    /// Ace on an empty foundation, then the same suit one higher.
    func canFound(_ card: SolitaireCard) -> Bool {
        foundations[card.suit.rawValue].count == card.rank - 1
    }

    /// Down one, the other colour.
    static func canStack(_ card: SolitaireCard, on target: SolitaireCard) -> Bool {
        card.isRed != target.isRed && card.rank == target.rank - 1
    }

    /// `card` (heading a run) onto column `t`: a king to an empty one, or
    /// down one in the other colour.
    func canBuild(_ card: SolitaireCard, on t: Int) -> Bool {
        guard tableau.indices.contains(t) else { return false }
        guard let top = tableau[t].top else { return card.rank == 13 }
        return Self.canStack(card, on: top)
    }

    /// The cards `move` would lift, if it may lift them.
    private func lifted(_ move: SolitaireMove) -> [SolitaireCard]? {
        guard move.count >= 1 else { return nil }
        switch move.from {
        case .stock:
            return nil
        case .waste:
            guard move.count == 1, let top = waste.last else { return nil }
            return [top]
        case .foundation(let f):
            guard foundations.indices.contains(f), move.count == 1, let top = foundations[f].last else { return nil }
            return [top]
        case .tableau(let t):
            guard tableau.indices.contains(t) else { return nil }
            let pile = tableau[t]
            guard move.count <= pile.faceUpCount else { return nil }
            let run = Array(pile.cards.suffix(move.count))
            // A run is only ever built legally, but a saved game is checked anyway.
            for k in 1..<max(run.count, 1) where !Self.canStack(run[k], on: run[k - 1]) { return nil }
            return run
        }
    }

    func isLegal(_ move: SolitaireMove) -> Bool {
        guard move.from != move.to, let run = lifted(move), let first = run.first else { return false }
        switch move.to {
        case .stock, .waste:
            return false
        case .foundation(let f):
            return run.count == 1 && f == first.suit.rawValue && canFound(first)
        case .tableau(let t):
            return canBuild(first, on: t)
        }
    }

    /// Do it. False, and nothing changes, when it is not allowed.
    @discardableResult
    mutating func apply(_ action: SolitaireAction) -> Bool {
        switch action {
        case .draw: return turn(drawMode.count)
        case .turnOne: return turn(1)
        case .move(let move): return apply(move)
        }
    }

    private mutating func turn(_ count: Int) -> Bool {
        if stock.isEmpty {
            guard !waste.isEmpty else { return false }
            stock = waste.reversed()
            waste.removeAll()
            passes += 1
            return true
        }
        for _ in 0..<min(count, stock.count) {
            waste.append(stock.removeLast())
        }
        return true
    }

    private mutating func apply(_ move: SolitaireMove) -> Bool {
        guard isLegal(move), let run = lifted(move) else { return false }
        switch move.from {
        case .waste: waste.removeLast()
        case .foundation(let f): foundations[f].removeLast()
        case .tableau(let t):
            tableau[t].cards.removeLast(run.count)
            // The card underneath turns over by itself.
            if tableau[t].faceDown >= tableau[t].cards.count {
                tableau[t].faceDown = max(0, tableau[t].cards.count - 1)
            }
        case .stock: return false
        }
        switch move.to {
        case .foundation(let f): foundations[f].append(contentsOf: run)
        case .tableau(let t): tableau[t].cards.append(contentsOf: run)
        case .stock, .waste: return false
        }
        return true
    }

    /// Every legal move on the table (not draws), for the tests and the solver.
    func legalMoves() -> [SolitaireMove] {
        var out: [SolitaireMove] = []
        var sources: [(SolitairePlace, Int)] = []
        if !waste.isEmpty { sources.append((.waste, 1)) }
        for f in 0..<4 where !foundations[f].isEmpty { sources.append((.foundation(f), 1)) }
        for t in 0..<7 {
            let pile = tableau[t]
            if pile.faceUpCount > 0 {
                for count in 1...pile.faceUpCount { sources.append((.tableau(t), count)) }
            }
        }
        for (from, count) in sources {
            var targets: [SolitairePlace] = (0..<7).map { SolitairePlace.tableau($0) }
            if count == 1 { targets += (0..<4).map { SolitairePlace.foundation($0) } }
            for to in targets {
                let move = SolitaireMove(from: from, to: to, count: count)
                if isLegal(move) { out.append(move) }
            }
        }
        return out
    }

    // MARK: Tap, hint, finish

    /// Where a tap on card `id` sends it: home to its foundation if it can
    /// go, else onto the best column. A tap on the stock draws.
    func bestAction(forCard id: Int) -> SolitaireAction? {
        guard let found = locate(id) else { return nil }
        let place = found.place, index = found.index
        switch place {
        case .stock:
            return .draw
        case .waste:
            guard index == waste.count - 1 else { return nil }
            let card = waste[index]
            if canFound(card) { return .move(SolitaireMove(from: .waste, to: .foundation(card.suit.rawValue))) }
            return columnFor(card, from: .waste, count: 1, clearsSomething: true).map { .move($0) }
        case .foundation(let f):
            guard index == foundations[f].count - 1 else { return nil }
            return columnFor(foundations[f][index], from: place, count: 1, clearsSomething: true).map { .move($0) }
        case .tableau(let t):
            let pile = tableau[t]
            guard pile.isFaceUp(index) else { return nil }
            let card = pile.cards[index]
            let count = pile.cards.count - index
            if count == 1 && canFound(card) {
                return .move(SolitaireMove(from: place, to: .foundation(card.suit.rawValue)))
            }
            // A king already at the foot of its column has nowhere better to be.
            return columnFor(card, from: place, count: count, clearsSomething: index > 0).map { .move($0) }
        }
    }

    /// Only home: the double tap.
    func foundationAction(forCard id: Int) -> SolitaireAction? {
        guard let found = locate(id) else { return nil }
        let place = found.place, index = found.index
        let move = SolitaireMove(from: place, to: .foundation(SolitaireCard(id: id).suit.rawValue))
        guard cards(at: place).count - 1 == index, isLegal(move) else { return nil }
        return .move(move)
    }

    /// The best column for `card`: one with cards first (left to right), an
    /// empty one only when the move uncovers something.
    private func columnFor(_ card: SolitaireCard, from: SolitairePlace, count: Int, clearsSomething: Bool) -> SolitaireMove? {
        var empty: SolitaireMove?
        for t in 0..<7 {
            if case .tableau(let source) = from, source == t { continue }
            guard canBuild(card, on: t) else { continue }
            let move = SolitaireMove(from: from, to: .tableau(t), count: count)
            if tableau[t].cards.isEmpty {
                if empty == nil && clearsSomething { empty = move }
            } else {
                return move
            }
        }
        return empty
    }

    /// Moves worth making, most useful first: cards home, runs that turn a
    /// card over or clear a column, the waste onto the table, part of a run
    /// to free a card for home, and last of all a draw. Never a move that
    /// only shuffles cards back and forth.
    func hints() -> [SolitaireAction] {
        var out: [SolitaireAction] = []
        if let top = waste.last, canFound(top) {
            out.append(.move(SolitaireMove(from: .waste, to: .foundation(top.suit.rawValue))))
        }
        for t in 0..<7 {
            if let top = tableau[t].top, canFound(top) {
                out.append(.move(SolitaireMove(from: .tableau(t), to: .foundation(top.suit.rawValue))))
            }
        }
        // Whole runs: the column with most cards still face down first.
        let columns = (0..<7).sorted { tableau[$0].faceDown > tableau[$1].faceDown }
        for t in columns {
            let pile = tableau[t]
            guard pile.faceUpCount > 0 else { continue }
            let base = pile.cards[pile.faceDown]
            let uncovers = pile.faceDown > 0
            // A king at the foot of a column is already where it belongs.
            if base.rank == 13 && !uncovers { continue }
            if let move = columnFor(base, from: .tableau(t), count: pile.faceUpCount, clearsSomething: uncovers) {
                out.append(.move(move))
            }
        }
        if let top = waste.last, let move = columnFor(top, from: .waste, count: 1, clearsSomething: true) {
            out.append(.move(move))
        }
        // Part of a run, when the card it uncovers can go home.
        for t in 0..<7 {
            let pile = tableau[t]
            guard pile.faceUpCount > 1 else { continue }
            for k in (pile.faceDown + 1)..<pile.cards.count where canFound(pile.cards[k - 1]) {
                if let move = columnFor(pile.cards[k], from: .tableau(t), count: pile.cards.count - k, clearsSomething: true) {
                    out.append(.move(move))
                }
            }
        }
        if !stock.isEmpty || !waste.isEmpty { out.append(.draw) }
        var seen = Set<SolitaireAction>()
        return out.filter { seen.insert($0).inserted }
    }

    /// Every card the waste will offer in one full trip round the stock, in
    /// the order the draws reach them.
    func reachableWasteCards() -> [SolitaireCard] {
        var copy = self
        var out: [SolitaireCard] = []
        if let top = copy.waste.last { out.append(top) }
        let startStock = copy.stock.count, startWaste = copy.waste.count
        let limit = 2 * (startStock + startWaste) + 2
        var steps = 0
        while steps < limit, copy.turn(drawMode.count) {
            steps += 1
            if let top = copy.waste.last, !out.contains(top) { out.append(top) }
            if copy.stock.count == startStock && copy.waste.count == startWaste { break }
        }
        return out
    }

    /// Nothing useful is left: no hint but a draw, and no card the draws
    /// will reach can be played. (Taking a card back off a foundation is
    /// still allowed, so this says "stuck", not "lost".)
    var isStuck: Bool {
        guard !isWon else { return false }
        let useful = hints().filter { $0 != .draw }
        guard useful.isEmpty else { return false }
        for card in reachableWasteCards() {
            if canFound(card) { return false }
            for t in 0..<7 where canBuild(card, on: t) { return false }
        }
        return true
    }

    /// The finish, one step at a time: the lowest card that can go home, or
    /// a single card turned from the stock. Nil when there is nothing to do.
    func autoCompleteAction() -> SolitaireAction? {
        guard canAutoComplete else { return nil }
        var best: (SolitaireMove, Int)?
        if let top = waste.last, canFound(top) {
            best = (SolitaireMove(from: .waste, to: .foundation(top.suit.rawValue)), top.rank)
        }
        for t in 0..<7 {
            guard let top = tableau[t].top, canFound(top) else { continue }
            if best == nil || top.rank < best!.1 {
                best = (SolitaireMove(from: .tableau(t), to: .foundation(top.suit.rawValue)), top.rank)
            }
        }
        if let best { return .move(best.0) }
        if !stock.isEmpty || !waste.isEmpty { return .turnOne }
        return nil
    }

    /// Plays the finish to the end and says what it did.
    @discardableResult
    mutating func autoComplete(maxSteps: Int = 10_000) -> [SolitaireAction] {
        var done: [SolitaireAction] = []
        var steps = 0
        while steps < maxSteps, let action = autoCompleteAction() {
            guard apply(action) else { break }
            done.append(action)
            steps += 1
        }
        return done
    }
}
