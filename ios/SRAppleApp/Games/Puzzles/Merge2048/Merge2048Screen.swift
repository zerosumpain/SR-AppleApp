import SwiftUI

/// 2048: the score and best along the top with Undo and Pause, the board in
/// the middle (swipe it), four big arrows underneath, and a card between
/// games. Pushed on the Games stack by `PhysicsGameScreen`.
struct Merge2048Screen: View {
    @StateObject private var session = Merge2048Session()
    /// This drag has already slid the board; the rest of it does nothing.
    @State private var swipeFired = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            playfield
            cardLayer
        }
        .background { SRAtmosphere(mood: .warm) }
        .navigationTitle(GameKind.merge2048.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { session.calm = reduceMotion }
        .onChange(of: reduceMotion) { _, calm in
            session.calm = calm
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.sleep() }
        }
        .onDisappear { session.leave() }
        .accessibilityIdentifier("merge-2048-screen")
    }

    // MARK: - Play field

    private var playfield: some View {
        VStack(spacing: 12) {
            hud
            status
            boardArea
            arrows
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        // Behind a card the board is scenery: VoiceOver reads the card.
        .accessibilityHidden(session.stage != .playing)
    }

    private var hud: some View {
        HStack(spacing: 10) {
            Merge2048ScoreBox(title: "Score", value: session.state.score, gain: session.gain)
                .accessibilityIdentifier("merge-2048-score")
            Merge2048ScoreBox(title: "Best", value: session.best, gain: nil)
                .accessibilityIdentifier("merge-2048-best")
            Spacer(minLength: 0)
            Merge2048RoundButton(icon: "arrow.uturn.backward", label: "Undo last move", enabled: session.canUndo) {
                let animation: Animation? = reduceMotion ? nil : Animation.easeOut(duration: Merge2048Motion.slide)
                withAnimation(animation) { session.undo() }
            }
            .accessibilityIdentifier("merge-2048-undo")
            Merge2048RoundButton(icon: "pause.fill", label: "Pause", enabled: session.stage == .playing) {
                SRHaptic.tap()
                withAnimation(.snappy) { session.pause() }
            }
            .accessibilityIdentifier("merge-2048-pause")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var status: some View {
        let state = session.state
        let size = session.size
        let goal = state.hasWon ? "goal \(String(state.target)) made" : "goal \(String(state.target))"
        let moves = state.moves == 1 ? "1 move" : "\(state.moves) moves"
        return Text("\(size.title) \(size.dimension) · \(goal) · \(moves)")
            .font(SR.Text.mono())
            .foregroundStyle(SR.inkSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityIdentifier("merge-2048-status")
    }

    /// The board, and the space around it that a swipe also counts in.
    private var boardArea: some View {
        Merge2048BoardView(side: session.state.side, sprites: session.sprites, sparks: session.sparks,
                           sparksLive: session.sparksLive, bumps: session.bumps)
            // A new game is a new board: its tiles grow in rather than slide
            // from where the last game's tiles (with the same ids) sat.
            .id(session.round)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(swipe)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(boardLabel)
            .accessibilityHint("Use the arrow buttons below, or the actions, to slide the tiles.")
            .accessibilityAction(named: "Slide up") { slide(.up) }
            .accessibilityAction(named: "Slide down") { slide(.down) }
            .accessibilityAction(named: "Slide left") { slide(.left) }
            .accessibilityAction(named: "Slide right") { slide(.right) }
            .accessibilityIdentifier("merge-2048-board")
    }

    private var arrows: some View {
        HStack(spacing: 10) {
            Merge2048ArrowButton(direction: .left, icon: "arrow.left", enabled: session.accepting) { slide(.left) }
            Merge2048ArrowButton(direction: .up, icon: "arrow.up", enabled: session.accepting) { slide(.up) }
            Merge2048ArrowButton(direction: .down, icon: "arrow.down", enabled: session.accepting) { slide(.down) }
            Merge2048ArrowButton(direction: .right, icon: "arrow.right", enabled: session.accepting) { slide(.right) }
        }
        .frame(maxWidth: 440)
    }

    // MARK: - Cards

    @ViewBuilder
    private var cardLayer: some View {
        if session.stage != .playing {
            ZStack {
                Color.black
                    .opacity(scrim)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                Merge2048CardHost {
                    card
                }
            }
            .transition(.opacity)
        }
    }

    /// Lighter over the end cards, so the final board still shows.
    private var scrim: Double {
        switch session.stage {
        case .won, .over: return 0.22
        default: return 0.34
        }
    }

    @ViewBuilder
    private var card: some View {
        switch session.stage {
        case .intro:
            Merge2048IntroCard(session: session)
        case .paused:
            Merge2048PausedCard(session: session)
        case .won:
            Merge2048WonCard(session: session)
        case .over:
            Merge2048OverCard(session: session)
        case .playing:
            EmptyView()
        }
    }

    // MARK: - Input

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard !swipeFired else { return }
                // Fire as soon as the finger has clearly picked a way, not
                // when it lifts: the board answers the swipe, not the release.
                if let direction = Merge2048Screen.direction(of: value.translation, threshold: 28) {
                    swipeFired = true
                    slide(direction)
                }
            }
            .onEnded { value in
                if !swipeFired, let direction = Merge2048Screen.direction(of: value.translation, threshold: 14) {
                    slide(direction)
                }
                swipeFired = false
            }
    }

    /// The way a drag of `translation` points, once it is at least
    /// `threshold` points long.
    static func direction(of translation: CGSize, threshold: CGFloat) -> Merge2048Direction? {
        let dx = translation.width
        let dy = translation.height
        guard max(abs(dx), abs(dy)) >= threshold else { return nil }
        if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .down : .up
    }

    private func slide(_ direction: Merge2048Direction) {
        guard session.accepting else { return }
        if reduceMotion {
            session.move(direction)
        } else {
            withAnimation(.easeOut(duration: Merge2048Motion.slide)) {
                session.move(direction)
            }
        }
    }

    private var boardLabel: String {
        let state = session.state
        var parts: [String] = ["\(session.size.title) board, score \(state.score)."]
        for (index, row) in state.rows.enumerated() {
            let cells: [String] = row.map { $0 == 0 ? "empty" : String($0) }
            parts.append("Row \(index + 1): \(cells.joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Pieces

/// The score or the best, in a glass box, with the "+16" rising off it.
struct Merge2048ScoreBox: View {
    let title: String
    let value: Int
    let gain: Merge2048Gain?

    var body: some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            Text(value.formatted())
                .font(SR.Text.figure(22))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .srNumeric(Double(value))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minWidth: 84, minHeight: 56)
        .srGlassCard(.paper, radius: 18)
        .overlay(alignment: .top) {
            if let gain {
                Merge2048GainLabel(amount: gain.amount)
                    .id(gain.id)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}

/// "+16", rising and fading.
struct Merge2048GainLabel: View {
    let amount: Int
    @State private var rise = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(verbatim: "+\(amount)")
            .font(SR.Text.label(14))
            .foregroundStyle(SR.accent)
            .offset(y: rise && !reduceMotion ? -30 : -8)
            .opacity(rise ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) { rise = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A round 56pt glass button in the top bar of the game: Undo, Pause.
struct Merge2048RoundButton: View {
    let icon: String
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(enabled ? SR.ink : SR.inkGhost)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
                .srGlassCard(.paper, radius: 28, interactive: true)
        }
        .buttonStyle(SRPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// One of the four arrows under the board: wide, 60pt tall, easy to hit.
struct Merge2048ArrowButton: View {
    let direction: Merge2048Direction
    let icon: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(enabled ? SR.ink : SR.inkGhost)
                .frame(maxWidth: .infinity, minHeight: 60)
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .srGlassCard(.paper, radius: 20, interactive: true)
        }
        .buttonStyle(SRPressStyle())
        .disabled(!enabled)
        .accessibilityLabel("Slide \(direction.word)")
        .accessibilityIdentifier("merge-2048-\(direction.rawValue)")
    }
}
