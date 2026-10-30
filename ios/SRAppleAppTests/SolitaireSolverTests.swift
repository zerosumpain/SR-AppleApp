import XCTest
@testable import SRAppleApp

/// The solver behind "winnable deals only": it wins known deals with moves
/// that really play, says so when a table has no way out, gives up politely
/// at its budget, and the dealer falls back to a plain deal in time.
final class SolitaireSolverTests: XCTestCase {

    /// Replays a solution on a fresh session: every action must be legal and
    /// the last one must win.
    private func assertPlays(_ result: SolitaireSolveResult, seed: UInt64, mode: SolitaireDrawMode,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard case .won(let actions) = result else {
            return XCTFail("expected a win, got \(result)", file: file, line: line)
        }
        var session = SolitaireSession(seed: seed, drawMode: mode)
        for action in actions {
            XCTAssertTrue(session.perform(action), "illegal step \(action)", file: file, line: line)
        }
        XCTAssertTrue(session.won, file: file, line: line)
    }

    func testFindsAWinOnAKnownWinnableDrawOneDeal() {
        // Seed 2 falls in well under 500 tables (measured).
        let result = SolitaireSolver(maxNodes: 5_000).solve(.deal(seed: 2, drawMode: .one))
        assertPlays(result, seed: 2, mode: .one)
    }

    func testFindsAWinOnAKnownWinnableDrawThreeDeal() {
        let result = SolitaireSolver(maxNodes: 5_000).solve(.deal(seed: 2, drawMode: .three))
        assertPlays(result, seed: 2, mode: .three)
    }

    func testANearlyFinishedTableIsWonAtOnce() {
        var state = SolitaireState()
        for suit in SolitaireSuit.allCases {
            state.foundations[suit.rawValue] = (1...11).map { SolitaireCard(suit: suit, rank: $0) }
            state.tableau[suit.rawValue].cards = [SolitaireCard(suit: suit, rank: 13), SolitaireCard(suit: suit, rank: 12)]
        }
        // Queens on kings of the same suit are not a legal build, but they are face up:
        // nothing is hidden, so the finish wins.
        guard case .won(let actions) = SolitaireSolver(maxNodes: 10).solve(state) else {
            return XCTFail("a table with every card showing is a win")
        }
        var copy = state
        for action in actions { XCTAssertTrue(copy.apply(action)) }
        XCTAssertTrue(copy.isWon)
    }

    func testATableWithNoWayOutIsUnsolvable() {
        // Seven columns topped by twos and fours, everything else face down
        // beneath them, nothing in the stock: not one legal move.
        var state = SolitaireState()
        let tops = [SolitaireCard(suit: .spades, rank: 2), SolitaireCard(suit: .clubs, rank: 2),
                    SolitaireCard(suit: .hearts, rank: 2), SolitaireCard(suit: .diamonds, rank: 2),
                    SolitaireCard(suit: .spades, rank: 4), SolitaireCard(suit: .clubs, rank: 4),
                    SolitaireCard(suit: .hearts, rank: 4)]
        let rest = SolitaireCard.deck.filter { !tops.contains($0) }
        for (t, top) in tops.enumerated() {
            let buried = rest.enumerated().filter { $0.offset % 7 == t }.map(\.element)
            state.tableau[t].cards = buried + [top]
            state.tableau[t].faceDown = buried.count
        }
        XCTAssertEqual(Set(state.tableau.flatMap { $0.cards.map(\.id) }).count, 52)
        XCTAssertTrue(state.legalMoves().isEmpty)
        XCTAssertEqual(SolitaireSolver(maxNodes: 10_000).solve(state), .unsolvable)
        XCTAssertTrue(state.isStuck)
    }

    func testGivesUpAtItsBudgetRatherThanClaimingUnsolvable() {
        // Seed 1 is a hard deal: one table is nowhere near enough.
        XCTAssertEqual(SolitaireSolver(maxNodes: 1).solve(.deal(seed: 1, drawMode: .one)), .gaveUp)
    }

    func testGivesUpAtAPassedDeadline() {
        // The deadline is checked every 512 tables, so a hard deal with a big
        // budget still stops.
        let solver = SolitaireSolver(maxNodes: 1_000_000, deadline: Date().addingTimeInterval(-1))
        XCTAssertEqual(solver.solve(.deal(seed: 1, drawMode: .one)), .gaveUp)
    }

    func testSafeHomeOnlyTakesCardsNothingNeeds() {
        var state = SolitaireState()
        state.foundations[0] = (1...4).map { SolitaireCard(suit: .spades, rank: $0) }
        XCTAssertTrue(SolitaireSolver.isSafeHome(SolitaireCard(suit: .hearts, rank: 1), in: state))
        XCTAssertFalse(SolitaireSolver.isSafeHome(SolitaireCard(suit: .spades, rank: 5), in: state),
                       "a red four might still want the black five")
        state.foundations[1] = (1...4).map { SolitaireCard(suit: .hearts, rank: $0) }
        state.foundations[2] = (1...4).map { SolitaireCard(suit: .diamonds, rank: $0) }
        XCTAssertTrue(SolitaireSolver.isSafeHome(SolitaireCard(suit: .spades, rank: 5), in: state))
    }

    func testColumnOrderDoesNotMakeANewPosition() {
        var a = SolitaireState.deal(seed: 4, drawMode: .one)
        var b = a
        b.tableau.swapAt(1, 5)
        XCTAssertEqual(SolitaireSolver.key(a), SolitaireSolver.key(b))
        a.apply(.draw)
        XCTAssertNotEqual(SolitaireSolver.key(a), SolitaireSolver.key(b))
    }

    func testDealerPicksAProvenDealAndFallsBackInTime() {
        let proven = SolitaireDealer.pick(drawMode: .one, firstSeed: 2, deadline: Date().addingTimeInterval(30))
        XCTAssertEqual(proven, SolitaireDealPick(seed: 2, proven: true))
        let late = SolitaireDealer.pick(drawMode: .one, firstSeed: 1, deadline: Date().addingTimeInterval(-1))
        XCTAssertEqual(late, SolitaireDealPick(seed: 1, proven: false), "out of time: the plain random deal")
    }

    func testDealerRunsInTheBackground() async {
        let pick = await SolitaireDealer.pickInBackground(drawMode: .three, firstSeed: 2, seconds: 30)
        XCTAssertEqual(pick.seed, 2)
        XCTAssertTrue(pick.proven)
    }
}
