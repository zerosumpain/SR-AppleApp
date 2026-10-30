import SwiftUI

/// The cards a finger is carrying.
struct SolitaireDrag: Equatable {
    /// The card the finger is on: the run's bottom card.
    let origin: Int
    let cards: [Int]
    var translation: CGSize
}

/// The table at whatever size the screen gives it.
struct SolitaireTable: View {
    @ObservedObject var game: SolitaireGame

    var body: some View {
        GeometryReader { geo in
            SolitaireBoard(game: game, layout: SolitaireLayout(size: geo.size))
        }
    }
}

/// The table itself: the empty places, then all 52 cards, each drawn at its
/// spot from `SolitaireLayout`. A card keeps its identity wherever it goes,
/// so every move, draw, undo and deal is the card gliding to its new spot.
struct SolitaireBoard: View {
    @ObservedObject var game: SolitaireGame
    let layout: SolitaireLayout
    @State private var drag: SolitaireDrag?
    /// The card a finger is dragging, as the gesture system sees it. It goes
    /// back to nil by itself when a drag ends OR is cancelled (a call, the
    /// notification shade, a second finger), which `onEnded` never hears.
    @GestureState private var dragging: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = game.state
        let spots = layout.spots(for: state, undealt: game.undealt)
        let spoken = voiceLabels(state)
        return ZStack(alignment: .topLeading) {
            places(state)
            ForEach(0..<52, id: \.self) { id in
                cardView(id, spot: spots[id], label: spoken[id])
            }
            hintRing(state)
            if !game.bursts.isEmpty {
                SolitaireSparks(bursts: game.bursts, layout: layout)
                    .zIndex(4000)
            }
            if game.celebrating && !reduceMotion {
                SolitaireCascadeView(layout: layout, fourColour: game.settings.fourColour)
                    .zIndex(5000)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .onChange(of: game.stage) { _, _ in drag = nil }
        .onChange(of: dragging) { _, now in
            guard now == nil else { return }
            // A drag that ended has already been dropped by now; one that was
            // cancelled has not, and its cards would hang in the air and block
            // every later drag. Queued on the main actor, so onEnded goes first.
            Task { @MainActor in
                if drag != nil {
                    withAnimation(SolitaireGame.motion) { drag = nil }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("solitaire-table")
    }

    private var radius: CGFloat { layout.cardWidth * 0.12 }

    // MARK: - Cards

    private func cardView(_ id: Int, spot: SolitaireSpot, label: String?) -> some View {
        let lifted = drag?.cards.contains(id) ?? false
        let shift = lifted ? (drag?.translation ?? .zero) : .zero
        let hinted = game.hint?.cards.contains(id) ?? false
        let hidden = game.celebrating || !spot.visible
        let flying = game.flying.contains(id)
        let lift: Double = lifted ? 2000 : 0
        let fly: Double = flying ? 1000 : 0
        let z: Double = spot.z + lift + fly
        let angle: Double = spot.faceUp ? 0 : 180
        let scale: CGFloat = lifted ? 1.06 : 1
        let alpha: Double = hidden ? 0 : 1
        let shake: CGFloat = CGFloat(game.shakes[id] ?? 0)
        let at = CGPoint(x: spot.center.x + shift.width, y: spot.center.y + shift.height)
        return SolitaireCardView(angle: angle, card: SolitaireCard(id: id),
                                 width: layout.cardWidth, fourColour: game.settings.fourColour, lifted: lifted)
            .overlay {
                if hinted { hintOutline.transition(.opacity) }
            }
            .modifier(SolitaireShake(phase: shake))
            .scaleEffect(scale)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onTapGesture { game.tap(id) }
            .gesture(dragGesture(id, from: spot.center))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label ?? "")
            .accessibilityHint("Moves it to its best place")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { game.tap(id) }
            .accessibilityHidden(label == nil || hidden)
            .position(at)
            .zIndex(z)
            .opacity(alpha)
            .allowsHitTesting(!hidden)
    }

    private var hintOutline: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(SolitaireInk.hint, lineWidth: 3)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(SolitaireInk.hint.opacity(0.16))
            )
    }

    private func dragGesture(_ id: Int, from center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($dragging) { _, held, _ in held = id }
            .onChanged { value in
                if let current = drag {
                    if current.origin == id { drag?.translation = value.translation }
                    return
                }
                guard let run = game.pickUp(id) else { return }
                SRHaptic.select()
                drag = SolitaireDrag(origin: id, cards: run, translation: value.translation)
            }
            .onEnded { value in
                guard let current = drag, current.origin == id else { return }
                let point = CGPoint(x: center.x + value.translation.width, y: center.y + value.translation.height)
                let targets = layout.dropTargets(at: point)
                withAnimation(SolitaireGame.motion) {
                    game.drop(id, on: targets)
                    drag = nil
                }
            }
    }

    /// What VoiceOver says for each card it may land on: the waste's top
    /// card and every face-up card in the columns. The rest stay silent.
    private func voiceLabels(_ state: SolitaireState) -> [Int: String] {
        var out: [Int: String] = [:]
        if let top = state.waste.last {
            out[top.id] = "\(top.spoken), from the stock"
        }
        for (t, pile) in state.tableau.enumerated() {
            for (i, card) in pile.cards.enumerated() where pile.isFaceUp(i) {
                var text = "\(card.spoken), column \(t + 1)"
                if i < pile.cards.count - 1 { text += ", with cards on it" }
                if i == pile.faceDown && pile.faceDown > 0 {
                    text += pile.faceDown == 1 ? ", 1 card face down under it" : ", \(pile.faceDown) cards face down under it"
                }
                out[card.id] = text
            }
        }
        return out
    }

    // MARK: - The empty places

    private func places(_ state: SolitaireState) -> some View {
        ZStack(alignment: .topLeading) {
            stockPlace(state)
            ForEach(0..<4, id: \.self) { f in
                foundationPlace(f, state: state)
            }
            ForEach(0..<7, id: \.self) { t in
                columnPlace(t, state: state)
            }
        }
    }

    private func outline(_ strength: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            shape.fill(Color.white.opacity(strength * 0.25))
            shape.strokeBorder(Color.white.opacity(strength), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        .frame(width: layout.cardWidth, height: layout.cardHeight)
    }

    private func stockPlace(_ state: SolitaireState) -> some View {
        let canTurn = state.stock.isEmpty && !state.waste.isEmpty
        return outline(0.32)
            .overlay {
                if canTurn {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: layout.cardWidth * 0.38, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onTapGesture { game.tapStock() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stockLabel(state))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { game.draw() }
            .accessibilityIdentifier("solitaire-stock")
            .position(layout.stockCenter)
    }

    private func stockLabel(_ state: SolitaireState) -> String {
        if state.stock.isEmpty {
            return state.waste.isEmpty ? "Stock, empty" : "Stock, empty. Turn the waste back over"
        }
        let cards = state.stock.count == 1 ? "1 card" : "\(state.stock.count) cards"
        return "Stock, \(cards). Turn over \(state.drawMode == .one ? "one" : "three")"
    }

    private func foundationPlace(_ f: Int, state: SolitaireState) -> some View {
        let suit = SolitaireSuit(rawValue: f) ?? .spades
        let pile = state.foundations[f]
        let label = pile.last.map { "\(suit.name.capitalized) home, up to the \($0.rankName.lowercased())" }
            ?? "\(suit.name.capitalized) home, empty"
        return outline(0.3)
            .overlay {
                Image(systemName: suit.symbolName)
                    .font(.system(size: layout.cardWidth * 0.42, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier("solitaire-foundation-\(f)")
            .position(layout.foundationCenter(f))
    }

    private func columnPlace(_ t: Int, state: SolitaireState) -> some View {
        let empty = state.tableau[t].cards.isEmpty
        return outline(empty ? 0.26 : 0.12)
            .overlay {
                Text("K")
                    .font(.system(size: layout.cardWidth * 0.4, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(empty ? 0.28 : 0))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Column \(t + 1), empty. Only a king can go here")
            .accessibilityHidden(!empty)
            .position(layout.tableauBase(t))
    }

    // MARK: - The hint

    @ViewBuilder
    private func hintRing(_ state: SolitaireState) -> some View {
        if let hint = game.hint {
            RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                .strokeBorder(SolitaireInk.hint, style: StrokeStyle(lineWidth: 3, dash: [7, 4]))
                .frame(width: layout.cardWidth + 8, height: layout.cardHeight + 8)
                .position(hint.target.map { layout.landing($0, in: state) } ?? layout.stockCenter)
                .zIndex(3000)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }
}
