import Foundation

// A Klondike solver, for "winnable deals only". It knows where the face-down
// cards are (it is checking the deal, not playing it), searches depth first
// with the moves most likely to help tried first, never visits the same
// table twice, and stops at a budget of tables or a deadline. It is run off
// the main thread by `SolitaireDealer`; nothing here touches the screen.

/// What the solver found.
enum SolitaireSolveResult: Equatable {
    /// A win: every action, in order, from the table it was given.
    case won([SolitaireAction])
    /// Every table reachable was tried and none of them wins.
    case unsolvable
    /// The budget or the deadline ran out first.
    case gaveUp

    var isWon: Bool {
        if case .won = self { return true }
        return false
    }
}

struct SolitaireSolver {
    /// Tables examined before giving up.
    var maxNodes = 60_000
    /// Wall-clock cap; nil for none (the tests use the node budget alone).
    var deadline: Date?

    private struct Frame {
        let state: SolitaireState
        let options: [[SolitaireAction]]
        var next = 0
    }

    func solve(_ start: SolitaireState) -> SolitaireSolveResult {
        var root = start
        let opening = Self.playSafe(&root)
        if root.allFaceUp { return .won(opening + root.autoComplete()) }

        var visited = Set<Int>()
        visited.insert(Self.key(root))
        var frames = [Frame(state: root, options: Self.options(root))]
        // path[k]: the actions from the table before frame k to frame k.
        var path: [[SolitaireAction]] = [opening]
        var nodes = 0

        while !frames.isEmpty {
            let top = frames.count - 1
            if frames[top].next >= frames[top].options.count {
                frames.removeLast()
                path.removeLast()
                continue
            }
            let option = frames[top].options[frames[top].next]
            frames[top].next += 1

            var child = frames[top].state
            var applied = true
            for action in option {
                if !child.apply(action) {
                    applied = false
                    break
                }
            }
            guard applied else { continue }
            let steps = option + Self.playSafe(&child)

            // With every tableau card showing, the finish always wins.
            if child.allFaceUp {
                var finished = child
                let tail = finished.autoComplete()
                if finished.isWon { return .won(path.flatMap { $0 } + steps + tail) }
            }
            guard visited.insert(Self.key(child)).inserted else { continue }

            nodes += 1
            if nodes >= maxNodes { return .gaveUp }
            if nodes % 512 == 0 {
                if Task.isCancelled { return .gaveUp }
                if let deadline, Date() >= deadline { return .gaveUp }
            }
            frames.append(Frame(state: child, options: Self.options(child)))
            path.append(steps)
        }
        return .unsolvable
    }

    // MARK: - Moves to try

    /// A card that can go home and that nothing will ever need to build on:
    /// an ace or two, or one whose two possible children (the next rank down,
    /// other colour) are both already home.
    static func isSafeHome(_ card: SolitaireCard, in state: SolitaireState) -> Bool {
        guard state.canFound(card) else { return false }
        if card.rank <= 2 { return true }
        let others: [SolitaireSuit] = card.isRed ? [.spades, .clubs] : [.hearts, .diamonds]
        return others.allSatisfy { state.foundations[$0.rawValue].count >= card.rank - 1 }
    }

    /// Plays every safe card home, as a person would without thinking.
    static func playSafe(_ state: inout SolitaireState) -> [SolitaireAction] {
        var done: [SolitaireAction] = []
        var moved = true
        while moved {
            moved = false
            if let top = state.waste.last, isSafeHome(top, in: state) {
                let action = SolitaireAction.move(SolitaireMove(from: .waste, to: .foundation(top.suit.rawValue)))
                if state.apply(action) { done.append(action); moved = true }
            }
            for t in 0..<7 {
                guard let top = state.tableau[t].top, isSafeHome(top, in: state) else { continue }
                let action = SolitaireAction.move(SolitaireMove(from: .tableau(t), to: .foundation(top.suit.rawValue)))
                if state.apply(action) { done.append(action); moved = true }
            }
        }
        return done
    }

    /// The branches from `state`, best first. Each is a short list of
    /// actions: the draws to reach a waste card are folded into its move, so
    /// the search goes card to card rather than draw to draw.
    static func options(_ state: SolitaireState) -> [[SolitaireAction]] {
        var home: [[SolitaireAction]] = []
        var uncover: [[SolitaireAction]] = []
        var fromWaste: [[SolitaireAction]] = []
        var partial: [[SolitaireAction]] = []

        for t in 0..<7 {
            guard let top = state.tableau[t].top, state.canFound(top) else { continue }
            home.append([.move(SolitaireMove(from: .tableau(t), to: .foundation(top.suit.rawValue)))])
        }

        let firstEmpty = (0..<7).first { state.tableau[$0].cards.isEmpty }
        let columns = (0..<7).sorted { state.tableau[$0].faceDown > state.tableau[$1].faceDown }
        for t in columns {
            let pile = state.tableau[t]
            guard pile.faceUpCount > 0 else { continue }
            let base = pile.cards[pile.faceDown]
            let uncovers = pile.faceDown > 0
            for target in 0..<7 where target != t {
                let empty = state.tableau[target].cards.isEmpty
                if empty {
                    // Only a king, only if it uncovers a card, only the first gap.
                    guard base.rank == 13, uncovers, target == firstEmpty else { continue }
                } else if !state.canBuild(base, on: target) {
                    continue
                }
                uncover.append([.move(SolitaireMove(from: .tableau(t), to: .tableau(target), count: pile.faceUpCount))])
            }
            // Part of the run, to free the card under it for home.
            if pile.faceUpCount > 1 {
                for k in (pile.faceDown + 1)..<pile.cards.count where state.canFound(pile.cards[k - 1]) {
                    for target in 0..<7 where target != t && !state.tableau[target].cards.isEmpty
                        && state.canBuild(pile.cards[k], on: target) {
                        partial.append([.move(SolitaireMove(from: .tableau(t), to: .tableau(target), count: pile.cards.count - k))])
                    }
                }
            }
        }

        // Every card a trip round the stock reaches, with the draws to reach it.
        var sim = state
        var draws: [SolitaireAction] = []
        let startStock = sim.stock.count, startWaste = sim.waste.count
        let limit = 2 * (startStock + startWaste) + 2
        var steps = 0
        while true {
            if let top = sim.waste.last {
                if sim.canFound(top) {
                    fromWaste.append(draws + [.move(SolitaireMove(from: .waste, to: .foundation(top.suit.rawValue)))])
                }
                for target in 0..<7 where sim.canBuild(top, on: target) {
                    if sim.tableau[target].cards.isEmpty && target != firstEmpty { continue }
                    fromWaste.append(draws + [.move(SolitaireMove(from: .waste, to: .tableau(target)))])
                }
            }
            guard steps < limit, sim.apply(.draw) else { break }
            draws.append(.draw)
            steps += 1
            if sim.stock.count == startStock && sim.waste.count == startWaste { break }
        }

        return home + uncover + fromWaste + partial
    }

    // MARK: - Seen tables

    /// A table's fingerprint. Columns are interchangeable, so they are
    /// sorted first: the same cards in a different column order is the same
    /// position, and the search need not try it twice.
    static func key(_ state: SolitaireState) -> Int {
        var hasher = Hasher()
        for pile in state.foundations { hasher.combine(pile.count) }
        hasher.combine(state.stock.count)
        for card in state.stock { hasher.combine(card.id) }
        hasher.combine(-1)
        for card in state.waste { hasher.combine(card.id) }
        var columns: [Int] = []
        columns.reserveCapacity(7)
        for pile in state.tableau {
            var column = Hasher()
            column.combine(pile.faceDown)
            for card in pile.cards { column.combine(card.id) }
            columns.append(column.finalize())
        }
        columns.sort()
        for column in columns { hasher.combine(column) }
        return hasher.finalize()
    }
}

/// The deal picked for a new game.
struct SolitaireDealPick: Equatable, Sendable {
    let seed: UInt64
    /// The solver found a win from it.
    let proven: Bool
}

/// Finds a deal the solver can win, trying one seed after another until a
/// deadline, and falls back to the first seed (an ordinary random deal) if
/// none is found in time.
///
/// Each deal gets a small budget. Measured over 40 deals, most winnable ones
/// fall in under 500 tables while the stubborn ones eat any budget given, so
/// many quick tries find a winner far sooner than a few long ones.
enum SolitaireDealer {
    static func pick(drawMode: SolitaireDrawMode, firstSeed: UInt64, attempts: Int = 80,
                     nodesPerDeal: Int = 3_000, deadline: Date) -> SolitaireDealPick {
        var seed = firstSeed
        for _ in 0..<attempts {
            if Task.isCancelled || Date() >= deadline { break }
            let solver = SolitaireSolver(maxNodes: nodesPerDeal, deadline: deadline)
            if solver.solve(SolitaireState.deal(seed: seed, drawMode: drawMode)).isWon {
                return SolitaireDealPick(seed: seed, proven: true)
            }
            seed = SolitaireRandom.seed(after: seed)
        }
        return SolitaireDealPick(seed: firstSeed, proven: false)
    }

    /// The same, off the main thread. Cancelling the calling task stops it.
    static func pickInBackground(drawMode: SolitaireDrawMode, firstSeed: UInt64, seconds: Double) async -> SolitaireDealPick {
        let deadline = Date().addingTimeInterval(seconds)
        let work = Task.detached(priority: .userInitiated) { () -> SolitaireDealPick in
            pick(drawMode: drawMode, firstSeed: firstSeed, deadline: deadline)
        }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }
}
