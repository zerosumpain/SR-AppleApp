import XCTest
@testable import SRAppleApp

/// Klondike's rules: the deal, every move rule, drawing and recycling, undo,
/// the finish, the tap and the hints, the layout on a small phone, the stats
/// and the store.
final class SolitaireTests: XCTestCase {

    // MARK: - Helpers

    private func card(_ rank: Int, _ suit: SolitaireSuit) -> SolitaireCard {
        SolitaireCard(suit: suit, rank: rank)
    }

    /// An empty table to build positions on.
    private func blank(_ mode: SolitaireDrawMode = .one) -> SolitaireState {
        var state = SolitaireState()
        state.drawMode = mode
        return state
    }

    private func move(_ from: SolitairePlace, _ to: SolitairePlace, _ count: Int = 1) -> SolitaireMove {
        SolitaireMove(from: from, to: to, count: count)
    }

    /// Every card id on the table, wherever it is.
    private func allIDs(_ state: SolitaireState) -> [Int] {
        var ids = state.stock.map(\.id) + state.waste.map(\.id)
        for pile in state.foundations { ids += pile.map(\.id) }
        for pile in state.tableau { ids += pile.cards.map(\.id) }
        return ids
    }

    /// A table with every card home but the kings, which sit one per column.
    private func nearlyWon() -> SolitaireState {
        var state = blank()
        for suit in SolitaireSuit.allCases {
            state.foundations[suit.rawValue] = (1...12).map { card($0, suit) }
            state.tableau[suit.rawValue].cards = [card(13, suit)]
        }
        return state
    }

    // MARK: - Cards

    func testCardIdsRoundTrip() {
        for id in 0..<52 {
            XCTAssertEqual(SolitaireCard(id: id).id, id)
        }
        XCTAssertEqual(SolitaireCard(id: 0).rankLabel, "A")
        XCTAssertEqual(SolitaireCard(id: 12).rankLabel, "K")
        XCTAssertEqual(card(12, .hearts).spoken, "Queen of hearts")
        XCTAssertEqual(card(10, .clubs).rankLabel, "10")
        XCTAssertTrue(card(3, .diamonds).isRed)
        XCTAssertFalse(card(3, .spades).isRed)
    }

    // MARK: - The deal

    func testDealHas52UniqueCardsInTheKlondikeLayout() {
        for seed: UInt64 in [1, 2, 99, 123_456] {
            let state = SolitaireState.deal(seed: seed, drawMode: .one)
            let ids = allIDs(state)
            XCTAssertEqual(ids.count, 52)
            XCTAssertEqual(Set(ids), Set(0..<52))
            XCTAssertEqual(state.stock.count, 24)
            XCTAssertTrue(state.waste.isEmpty)
            XCTAssertTrue(state.foundations.allSatisfy { $0.isEmpty })
            for column in 0..<7 {
                XCTAssertEqual(state.tableau[column].cards.count, column + 1)
                XCTAssertEqual(state.tableau[column].faceDown, column, "only the top card of each column is face up")
                XCTAssertEqual(state.tableau[column].faceUpCount, 1)
            }
            XCTAssertEqual(state.dealOrder.count, 28)
            XCTAssertEqual(Set(state.dealOrder).count, 28)
        }
    }

    func testTheSameSeedDealsTheSameGame() {
        XCTAssertEqual(SolitaireState.deal(seed: 42, drawMode: .one), SolitaireState.deal(seed: 42, drawMode: .one))
        XCTAssertNotEqual(SolitaireState.deal(seed: 42, drawMode: .one).tableau,
                          SolitaireState.deal(seed: 43, drawMode: .one).tableau)
        XCTAssertNotEqual(SolitaireRandom.seed(after: 42), 42)
    }

    // MARK: - Move rules

    func testTableauBuildsDownInAlternateColours() {
        var state = blank()
        state.tableau[0].cards = [card(8, .hearts)]
        state.tableau[1].cards = [card(7, .spades)]
        state.tableau[2].cards = [card(7, .diamonds)]
        state.tableau[3].cards = [card(6, .clubs)]
        state.tableau[4].cards = [card(9, .clubs)]
        // Black 7 on red 8: yes. Red 7 on red 8: no.
        XCTAssertTrue(state.isLegal(move(.tableau(1), .tableau(0))))
        XCTAssertFalse(state.isLegal(move(.tableau(2), .tableau(0))))
        // Not descending by one.
        XCTAssertFalse(state.isLegal(move(.tableau(3), .tableau(0))), "a 6 does not go on an 8")
        XCTAssertFalse(state.isLegal(move(.tableau(4), .tableau(0))), "going up is not allowed")
        XCTAssertFalse(state.isLegal(move(.tableau(0), .tableau(1))), "an 8 does not go on a 7")
        XCTAssertTrue(state.apply(.move(move(.tableau(1), .tableau(0)))))
        XCTAssertEqual(state.tableau[0].cards, [card(8, .hearts), card(7, .spades)])
        XCTAssertTrue(state.tableau[1].cards.isEmpty)
    }

    func testOnlyAKingGoesToAnEmptyColumn() {
        var state = blank()
        state.tableau[0].cards = [card(13, .hearts)]
        state.tableau[1].cards = [card(12, .spades)]
        state.tableau[2].cards = [card(4, .clubs), card(13, .clubs)]
        state.tableau[2].faceDown = 1
        XCTAssertFalse(state.isLegal(move(.tableau(1), .tableau(3))), "a queen may not take an empty column")
        XCTAssertTrue(state.isLegal(move(.tableau(0), .tableau(3))))
        XCTAssertTrue(state.apply(.move(move(.tableau(2), .tableau(4)))))
        XCTAssertEqual(state.tableau[4].cards, [card(13, .clubs)])
        XCTAssertEqual(state.tableau[2].faceDown, 0, "the card underneath turns over")
    }

    func testFoundationsGoAceToKingInOneSuit() {
        var state = blank()
        state.waste = [card(2, .hearts)]
        state.tableau[0].cards = [card(1, .hearts)]
        state.tableau[1].cards = [card(1, .spades)]
        XCTAssertFalse(state.isLegal(move(.waste, .foundation(1))), "a two needs its ace first")
        XCTAssertFalse(state.isLegal(move(.tableau(0), .foundation(0))), "hearts go on the hearts foundation")
        XCTAssertTrue(state.apply(.move(move(.tableau(0), .foundation(1)))))
        XCTAssertTrue(state.apply(.move(move(.waste, .foundation(1)))))
        XCTAssertEqual(state.foundations[1].map(\.rank), [1, 2])
        state.waste = [card(3, .diamonds)]
        XCTAssertFalse(state.isLegal(move(.waste, .foundation(1))), "same colour is not same suit")
        XCTAssertFalse(state.isLegal(move(.waste, .foundation(2))), "a three is not an ace")
        // All the way to the king.
        state.foundations[0] = (1...12).map { card($0, .spades) }
        state.waste = [card(13, .spades)]
        XCTAssertTrue(state.apply(.move(move(.waste, .foundation(0)))))
        XCTAssertEqual(state.foundations[0].count, 13)
    }

    func testRunsMoveTogetherAndOnlyFaceUpOnes() {
        var state = blank()
        state.tableau[0].cards = [card(2, .clubs), card(9, .hearts), card(8, .spades), card(7, .diamonds)]
        state.tableau[0].faceDown = 1
        state.tableau[1].cards = [card(10, .clubs)]
        XCTAssertTrue(state.isLegal(move(.tableau(0), .tableau(1), 3)))
        XCTAssertFalse(state.isLegal(move(.tableau(0), .tableau(1), 4)), "a face-down card never moves")
        XCTAssertFalse(state.isLegal(move(.tableau(0), .foundation(2), 3)), "only one card at a time goes home")
        XCTAssertTrue(state.apply(.move(move(.tableau(0), .tableau(1), 3))))
        XCTAssertEqual(state.tableau[1].cards.map(\.rank), [10, 9, 8, 7])
        XCTAssertEqual(state.tableau[0].cards, [card(2, .clubs)])
        XCTAssertEqual(state.tableau[0].faceDown, 0)
    }

    func testFoundationCardsCanComeBackToTheTable() {
        var state = blank()
        state.foundations[1] = [card(1, .hearts), card(2, .hearts), card(3, .hearts)]
        state.tableau[0].cards = [card(4, .spades)]
        XCTAssertTrue(state.isLegal(move(.foundation(1), .tableau(0))))
        XCTAssertFalse(state.isLegal(move(.stock, .tableau(0))), "nothing is played straight from the stock")
        XCTAssertFalse(state.isLegal(move(.tableau(0), .waste)))
    }

    func testIllegalMoveChangesNothing() {
        var state = SolitaireState.deal(seed: 5, drawMode: .one)
        let before = state
        XCTAssertFalse(state.apply(.move(move(.tableau(6), .tableau(6)))))
        XCTAssertFalse(state.apply(.move(move(.waste, .tableau(0)))), "an empty waste has nothing to give")
        XCTAssertEqual(state, before)
    }

    // MARK: - Stock and waste

    func testDrawOneTurnsOneAndRecyclesTheWaste() {
        var state = SolitaireState.deal(seed: 11, drawMode: .one)
        let stock = state.stock
        XCTAssertTrue(state.apply(.draw))
        XCTAssertEqual(state.waste, [stock.last!])
        XCTAssertEqual(state.stock.count, 23)
        for _ in 0..<23 { state.apply(.draw) }
        XCTAssertTrue(state.stock.isEmpty)
        XCTAssertEqual(state.waste, stock.reversed())
        XCTAssertTrue(state.apply(.draw), "an empty stock turns the waste back over")
        XCTAssertEqual(state.stock, stock, "in the same order it was dealt")
        XCTAssertTrue(state.waste.isEmpty)
        XCTAssertEqual(state.passes, 1)
    }

    func testDrawThreeCyclesInThreesAndRecycles() {
        var state = SolitaireState.deal(seed: 11, drawMode: .three)
        let stock = state.stock
        XCTAssertTrue(state.apply(.draw))
        XCTAssertEqual(state.waste.count, 3)
        // The third card turned is the one on top, playable.
        XCTAssertEqual(state.waste.last, stock[stock.count - 3])
        XCTAssertEqual(state.waste.first, stock.last)
        for _ in 0..<7 { state.apply(.draw) }
        XCTAssertTrue(state.stock.isEmpty)
        XCTAssertEqual(state.waste.count, 24)
        XCTAssertTrue(state.apply(.draw))
        XCTAssertEqual(state.stock, stock)
        XCTAssertEqual(state.passes, 1)

        // A stock that is not a multiple of three: the last draw takes what is left.
        var short = blank(.three)
        short.stock = [card(1, .spades), card(2, .spades), card(3, .spades), card(4, .spades)]
        short.apply(.draw)
        XCTAssertEqual(short.waste.map(\.rank), [4, 3, 2])
        short.apply(.draw)
        XCTAssertEqual(short.waste.map(\.rank), [4, 3, 2, 1])
        XCTAssertTrue(short.stock.isEmpty)
        short.apply(.draw)
        XCTAssertEqual(short.stock.map(\.rank), [1, 2, 3, 4])
    }

    func testDrawingWithNothingLeftDoesNothing() {
        var state = blank()
        XCTAssertFalse(state.apply(.draw))
        XCTAssertEqual(state.passes, 0)
    }

    func testReachableWasteCardsInDrawThreeAreEveryThird() {
        var state = blank(.three)
        state.stock = (1...6).map { card($0, .clubs) }
        // Draws turn 6,5,4 (4 on top) then 3,2,1 (1 on top).
        XCTAssertEqual(state.reachableWasteCards().map(\.rank), [4, 1])
        state.drawMode = .one
        XCTAssertEqual(Set(state.reachableWasteCards().map(\.rank)), Set(1...6))
    }

    // MARK: - Undo

    func testUndoRestoresTheExactTable() {
        var session = SolitaireSession(seed: 77, drawMode: .three)
        let start = session.state
        var tables = [start]
        var played = 0
        // Play a mix of draws and real moves.
        for _ in 0..<40 {
            let action = session.state.hints().first ?? .draw
            if session.perform(action) {
                tables.append(session.state)
                played += 1
            }
        }
        XCTAssertGreaterThan(played, 5)
        XCTAssertEqual(session.moves, played)
        while tables.count > 1 {
            tables.removeLast()
            XCTAssertTrue(session.undo())
            XCTAssertEqual(session.state, tables.last!, "each undo is exactly the table before")
        }
        XCTAssertEqual(session.state, start)
        XCTAssertFalse(session.undo(), "nothing left to undo")
        XCTAssertEqual(session.undos, played)
    }

    func testFailedActionIsNotAMoveAndRestartDealsAgain() {
        var session = SolitaireSession(seed: 3, drawMode: .one)
        XCTAssertFalse(session.perform(.move(move(.waste, .tableau(0)))))
        XCTAssertEqual(session.moves, 0)
        XCTAssertFalse(session.canUndo)
        session.perform(.draw)
        session.perform(.draw)
        session.elapsed = 30
        session.counted = true
        session.restart()
        XCTAssertEqual(session.state, SolitaireState.deal(seed: 3, drawMode: .one))
        XCTAssertEqual(session.moves, 0)
        XCTAssertEqual(session.elapsed, 0)
        XCTAssertTrue(session.counted, "a restart is the same game for the stats")
    }

    // MARK: - The finish

    func testAutoCompleteFinishesASolvedPosition() {
        var state = nearlyWon()
        XCTAssertTrue(state.canAutoComplete)
        let actions = state.autoComplete()
        XCTAssertEqual(actions.count, 4)
        XCTAssertTrue(state.isWon)
        XCTAssertNil(state.autoCompleteAction())
    }

    func testAutoCompleteFinishesWithCardsStillInTheStock() {
        // Every tableau card showing, but half the cards in a draw-3 stock and
        // waste in an awkward order: the finish turns one at a time and wins.
        var state = blank(.three)
        var rest: [SolitaireCard] = []
        for suit in SolitaireSuit.allCases {
            for rank in 1...13 { rest.append(card(rank, suit)) }
        }
        var random = SolitaireRandom(seed: 9)
        rest.shuffle(using: &random)
        state.stock = Array(rest[0..<20])
        state.waste = Array(rest[20..<30])
        // The rest as single face-up cards and runs on the table.
        var column = 0
        for c in rest[30...] {
            state.tableau[column % 7].cards.append(c)
            column += 1
        }
        // Make each column a legal pile for the purpose of the test: one
        // card a column is always legal, so stack the leftovers in the waste.
        for t in 0..<7 {
            let extra = state.tableau[t].cards.dropFirst()
            state.waste += extra
            state.tableau[t].cards = Array(state.tableau[t].cards.prefix(1))
        }
        XCTAssertEqual(allIDs(state).count, 52)
        XCTAssertTrue(state.canAutoComplete)
        state.autoComplete()
        XCTAssertTrue(state.isWon)
    }

    func testNoAutoCompleteWhileACardIsFaceDown() {
        let state = SolitaireState.deal(seed: 1, drawMode: .one)
        XCTAssertFalse(state.canAutoComplete)
        XCTAssertNil(state.autoCompleteAction())
    }

    // MARK: - Tap and hint

    func testTapSendsHomeFirstThenToAColumn() {
        var state = blank()
        state.foundations[1] = [card(1, .hearts)]
        state.tableau[0].cards = [card(2, .hearts)]
        state.tableau[1].cards = [card(3, .spades)]
        state.tableau[2].cards = [card(9, .diamonds)]
        state.waste = [card(8, .clubs)]
        XCTAssertEqual(state.bestAction(forCard: card(2, .hearts).id),
                       .move(move(.tableau(0), .foundation(1))), "home beats the black three")
        XCTAssertEqual(state.bestAction(forCard: card(8, .clubs).id), .move(move(.waste, .tableau(2))))
        XCTAssertNil(state.bestAction(forCard: card(9, .diamonds).id), "nowhere for the nine")
        state.stock = [card(5, .clubs)]
        XCTAssertEqual(state.bestAction(forCard: card(5, .clubs).id), .draw)
    }

    func testTapKeepsAKingAtTheFootOfItsColumn() {
        var state = blank()
        state.tableau[0].cards = [card(13, .spades)]
        state.tableau[1].cards = [card(5, .hearts), card(13, .hearts)]
        state.tableau[1].faceDown = 1
        XCTAssertNil(state.bestAction(forCard: card(13, .spades).id))
        XCTAssertEqual(state.bestAction(forCard: card(13, .hearts).id), .move(move(.tableau(1), .tableau(2))))
    }

    func testDoubleTapOnlyGoesHome() {
        var state = blank()
        state.tableau[0].cards = [card(1, .clubs)]
        state.tableau[1].cards = [card(6, .hearts)]
        state.tableau[2].cards = [card(7, .spades)]
        XCTAssertEqual(state.foundationAction(forCard: card(1, .clubs).id), .move(move(.tableau(0), .foundation(3))))
        XCTAssertNil(state.foundationAction(forCard: card(6, .hearts).id))
    }

    func testHintsPreferHomeThenUncoveringAndEndWithADraw() {
        var state = blank()
        state.stock = [card(9, .spades)]
        state.waste = [card(1, .diamonds)]
        state.tableau[0].cards = [card(4, .clubs), card(6, .hearts)]
        state.tableau[0].faceDown = 1
        state.tableau[1].cards = [card(7, .clubs)]
        let hints = state.hints()
        XCTAssertEqual(hints.first, .move(move(.waste, .foundation(2))))
        XCTAssertTrue(hints.contains(.move(move(.tableau(0), .tableau(1)))))
        XCTAssertEqual(hints.last, .draw)
        for hint in hints {
            var copy = state
            XCTAssertTrue(copy.apply(hint), "every hint is legal: \(hint)")
        }
    }

    func testHintsNeverShuffleAKingAlongTheBottom() {
        var state = blank()
        state.tableau[0].cards = [card(13, .spades), card(12, .hearts)]
        XCTAssertTrue(state.hints().isEmpty)
        XCTAssertTrue(state.isStuck)
    }

    func testStuckSeesCardsTheStockWillReach() {
        var state = blank()
        state.tableau[0].cards = [card(13, .spades)]
        state.stock = [card(12, .hearts), card(5, .clubs)]
        XCTAssertFalse(state.isStuck, "the red queen is two draws away")
        state.stock = [card(12, .clubs), card(5, .clubs)]
        XCTAssertTrue(state.isStuck)
    }

    // MARK: - Layout

    func testSevenColumnsFitOnASmallPhone() {
        for width: CGFloat in [320, 375, 390, 430] {
            let layout = SolitaireLayout(size: CGSize(width: width, height: 560))
            XCTAssertGreaterThanOrEqual(layout.originX, 0)
            XCTAssertLessThanOrEqual(layout.columnX(6) + layout.cardWidth / 2, width)
            XCTAssertGreaterThan(layout.columnX(1) - layout.cardWidth / 2, layout.columnX(0) + layout.cardWidth / 2)
            XCTAssertGreaterThanOrEqual(layout.cardWidth, 40, "big enough to read at \(width)")
        }
    }

    func testALongColumnStaysOnTheTable() {
        let layout = SolitaireLayout(size: CGSize(width: 375, height: 470))
        var pile = SolitairePile()
        pile.cards = (1...13).reversed().map { card($0, $0 % 2 == 0 ? .hearts : .spades) }
        pile.cards.insert(contentsOf: (1...6).map { card($0, .diamonds) }, at: 0)
        pile.faceDown = 6
        let last = layout.tableauCenter(6, index: pile.cards.count - 1, pile: pile)
        XCTAssertLessThanOrEqual(last.y + layout.cardHeight / 2, layout.bottom + 0.5)
    }

    func testSpotsCoverEveryCardAndDropTargetsReadTheTable() {
        let layout = SolitaireLayout(size: CGSize(width: 375, height: 560))
        let state = SolitaireState.deal(seed: 8, drawMode: .three)
        let spots = layout.spots(for: state)
        XCTAssertEqual(spots.count, 52)
        let top = state.tableau[6].top!
        XCTAssertTrue(spots[top.id].faceUp)
        XCTAssertFalse(spots[state.tableau[6].cards[0].id].faceUp)
        XCTAssertGreaterThan(spots[top.id].z, spots[state.tableau[6].cards[0].id].z)
        XCTAssertEqual(layout.dropTarget(at: layout.foundationCenter(2)), .foundation(2))
        XCTAssertNil(layout.dropTarget(at: layout.stockCenter))
        XCTAssertEqual(layout.dropTarget(at: layout.tableauBase(4)), .tableau(4))
        // A drop a little to the right of column 2 also offers column 3.
        let nudged = CGPoint(x: layout.columnX(2) + layout.cardWidth * 0.4, y: layout.tableauBase(2).y)
        XCTAssertEqual(layout.dropTargets(at: nudged), [.tableau(2), .tableau(3)])
        XCTAssertEqual(layout.dropTargets(at: layout.tableauBase(5)), [.tableau(5)])
        XCTAssertEqual(layout.dropTargets(at: layout.stockCenter), [])
        // Undealt cards wait on the stock, face down.
        let undealt = Set(state.dealOrder)
        let waiting = layout.spots(for: state, undealt: undealt)
        XCTAssertEqual(waiting[top.id].center, layout.stockCenter)
        XCTAssertFalse(waiting[top.id].faceUp)
    }

    // MARK: - The win cascade

    func testCascadeThrowsEveryCardAndEnds() {
        let starts = (0..<4).map { SolitaireCascadePoint(x: 200 + Double($0) * 50, y: 40) }
        var cascade = SolitaireCascade(width: 375, floor: 600, cardWidth: 48, cardHeight: 67, starts: starts)
        XCTAssertEqual(cascade.waiting(0), 12, "the king of spades waits first")
        var seconds = 0.0
        while !cascade.finished && seconds < 120 {
            cascade.advance(by: 1.0 / 60)
            seconds += 1.0 / 60
            for flyer in cascade.flyers {
                XCTAssertLessThanOrEqual(flyer.y + 67 / 2, 600.001, "nothing falls through the floor")
            }
        }
        XCTAssertTrue(cascade.finished)
        XCTAssertNil(cascade.waiting(3))
        XCTAssertEqual(Set(SolitaireCascade.order).count, 52)
    }

    // MARK: - Stats, settings, store

    func testStatsCountWinsStreaksAndBests() {
        var stats = SolitaireStats()
        stats.recordStart()
        var record = stats.recordWin(mode: .one, time: 300, moves: 120)
        XCTAssertFalse(record.bestTime, "the first win is not a new best: there was none")
        XCTAssertEqual(stats.bestTime(.one), 300)
        stats.recordStart()
        record = stats.recordWin(mode: .one, time: 250, moves: 130)
        XCTAssertTrue(record.bestTime)
        XCTAssertFalse(record.fewestMoves)
        XCTAssertEqual(stats.fewestMoves(.one), 120)
        XCTAssertEqual(stats.streak, 2)
        stats.recordStart()
        stats.recordAbandon()
        XCTAssertEqual(stats.streak, 0)
        XCTAssertEqual(stats.bestStreak, 2)
        XCTAssertEqual(stats.played, 3)
        XCTAssertEqual(stats.won, 2)
        XCTAssertEqual(stats.winRate, 67)
        XCTAssertNil(stats.bestTime(.three))
    }

    func testStoreKeepsStatsSettingsAndAGameInProgress() throws {
        let name = "solitaire-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SolitaireStore(defaults: defaults)
        XCTAssertEqual(store.loadStats(), SolitaireStats())
        XCTAssertEqual(store.loadSettings(), SolitaireSettings())
        XCTAssertNil(store.loadGame())

        var stats = SolitaireStats()
        stats.recordStart()
        _ = stats.recordWin(mode: .three, time: 99, moves: 80)
        store.save(stats)
        var settings = SolitaireSettings()
        settings.drawMode = .three
        settings.fourColour = true
        settings.felt = .plum
        store.save(settings)
        var session = SolitaireSession(seed: 21, drawMode: .three, proven: true)
        session.perform(.draw)
        session.perform(.draw)
        session.elapsed = 12.5
        store.saveGame(session)

        XCTAssertEqual(store.loadStats(), stats)
        XCTAssertEqual(store.loadSettings(), settings)
        XCTAssertEqual(store.loadGame(), session, "the undo history comes back too")
        store.clearGame()
        XCTAssertNil(store.loadGame())
        XCTAssertTrue(SolitaireStore.statsKey.hasPrefix("solitaire."))
    }

    func testOldSettingsWithMissingFieldsStillLoad() throws {
        let data = Data(#"{"drawMode":3}"#.utf8)
        let settings = try JSONDecoder().decode(SolitaireSettings.self, from: data)
        XCTAssertEqual(settings.drawMode, .three)
        XCTAssertTrue(settings.winnableOnly)
        XCTAssertEqual(settings.felt, .baize)
    }

    func testClockReadsLikeAClock() {
        XCTAssertEqual(SolitaireClock.format(0), "0:00")
        XCTAssertEqual(SolitaireClock.format(187), "3:07")
        XCTAssertEqual(SolitaireClock.format(3729), "1:02:09")
        XCTAssertEqual(SolitaireClock.spoken(61), "1 minute 1 second")
    }
}
