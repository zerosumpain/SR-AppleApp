import SwiftUI
import UIKit

/// Snake: the score along the top with Pause, the lawn in the middle (swipe
/// anywhere to turn), the big arrows underneath when they are switched on,
/// and a card before and after each game. Pushed on the Games stack by
/// `PhysicsGameScreen`.
struct SnakeScreen: View {
    @StateObject private var session = SnakeSession()
    /// Where the current swipe last turned from; nil between swipes.
    @State private var swipeAnchor: CGPoint?
    /// Where the current swipe began. A swipe the system cancels never
    /// reaches `onEnded`, so a new start point is how a fresh swipe is told
    /// from the old one (and the old anchor is not used to judge it).
    @State private var swipeStart: CGPoint?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        ZStack {
            GeometryReader { geo in
                // A short phone keeps the arrows a little smaller so the board stays big.
                playArea(padKey: geo.size.height < 640 ? 56 : 64)
            }
            cardLayer
        }
        .srPaper()
        .navigationTitle(GameKind.snake.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        // While the snake moves, a swipe right from the left edge is a turn,
        // not "go back": hiding the back button switches that gesture off.
        // Pause brings it back.
        .navigationBarBackButtonHidden(steering)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: session.stage)
        .animation(.easeInOut(duration: 0.25), value: session.toast)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.sleep() }
        }
        .onChange(of: session.stage) { _, stage in announce(stage) }
        .onDisappear { session.leave() }
        .accessibilityIdentifier("snake-screen")
    }

    private var dark: Bool { colorScheme == .dark }
    private var steering: Bool { session.stage == .ready || session.stage == .playing }
    private var cardUp: Bool {
        session.stage == .intro || session.stage == .paused || session.stage == .over
    }
    /// The arrows: when asked for, and always for VoiceOver, which cannot swipe the board.
    private var showsPad: Bool { session.records.pad || voiceOver }

    // MARK: - Play area

    private func playArea(padKey: CGFloat) -> some View {
        VStack(spacing: 10) {
            hud
            statusLine
            board
            if showsPad {
                SnakePad(onTurn: { direction in session.turn(direction) }, size: padKey)
                    .opacity(steering ? 1 : 0.5)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .gesture(swipe, including: steering ? .all : .subviews)
        // Behind a card the board is scenery: VoiceOver reads the card.
        .accessibilityHidden(cardUp)
    }

    private var hud: some View {
        HStack(spacing: 8) {
            SnakeStatBox(title: "Score", value: session.score, strong: true)
                .accessibilityIdentifier("snake-score")
            SnakeStatBox(title: "Best", value: max(session.best, session.score))
                .accessibilityIdentifier("snake-best")
            SnakeStatBox(title: "Length", value: session.length)
                .accessibilityIdentifier("snake-length")
            pauseButton
        }
    }

    private var pauseButton: some View {
        Button {
            SRHaptic.tap()
            session.pause()
        } label: {
            Image(systemName: "pause.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(SR.ink)
                .frame(width: 56, height: 56)
                .srGlassCard(.paper, radius: 28)
                .contentShape(Circle())
        }
        .buttonStyle(SRPressStyle())
        .disabled(!steering)
        .opacity(steering ? 1 : 0.4)
        .accessibilityLabel("Pause")
        .accessibilityIdentifier("snake-pause")
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Label(session.place, systemImage: session.game.mode.icon)
                .font(SR.Text.label())
                .foregroundStyle(SR.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text(session.speed >= 0.999 ? "TOP SPEED" : "SPEED")
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(session.speed >= 0.999 ? SR.error : SR.inkMuted)
                .lineLimit(1)
            SnakeSpeedPips(level: session.speed)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Board

    private var board: some View {
        GeometryReader { geo in
            let game = session.game
            let cell = SnakeLayout.cell(for: geo.size, columns: game.columns, rows: game.rows)
            boardStack(cell: cell)
                .frame(width: cell * CGFloat(game.columns), height: cell * CGFloat(game.rows))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func boardStack(cell: CGFloat) -> some View {
        let game = session.game
        let shape = RoundedRectangle(cornerRadius: SnakeLayout.radius, style: .continuous)
        return ZStack {
            SnakeBoardView(columns: game.columns, rows: game.rows, mode: game.mode,
                           layout: session.maze?.id ?? game.mode.rawValue, walls: game.walls, dark: dark)
                .equatable()
            SnakeFieldView(clock: session.clock, session: session,
                           skin: SnakeSkinPaint.of(session.skin), calm: reduceMotion)
        }
        .clipShape(shape)
        .overlay(shape.stroke(SnakeBoardPaint.of(dark: dark).rim, lineWidth: 1))
        .overlay(alignment: .bottom) { readyHint }
        .overlay(alignment: .top) { toastView }
        .shadow(color: Color.black.opacity(dark ? 0.4 : 0.16), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(boardLabel)
        .accessibilityIdentifier("snake-board")
    }

    @ViewBuilder
    private var readyHint: some View {
        if session.stage == .ready {
            SnakeReadyHint(resuming: session.resuming, pad: showsPad)
                .padding(.bottom, 18)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = session.toast {
            Label(toast, systemImage: "lock.open.fill")
                .font(SR.Text.title(15))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    private var boardLabel: String {
        let game = session.game
        var words = "Snake board, \(session.place). Length \(game.length), heading \(game.heading.word)."
        if let food = game.food { words += " Apple \(offset(from: game.head, to: food, in: game))." }
        if let gold = game.golden { words += " Golden apple \(offset(from: game.head, to: gold.at, in: game))." }
        return words
    }

    /// "3 right and 2 up", the short way round on a wrapping board.
    private func offset(from head: SnakePoint, to target: SnakePoint, in game: SnakeGame) -> String {
        var dx = target.x - head.x
        var dy = target.y - head.y
        if !game.mode.edgesKill {
            if dx > game.columns / 2 { dx -= game.columns }
            if dx < -game.columns / 2 { dx += game.columns }
            if dy > game.rows / 2 { dy -= game.rows }
            if dy < -game.rows / 2 { dy += game.rows }
        }
        var parts: [String] = []
        if dx != 0 { parts.append("\(abs(dx)) \(dx > 0 ? "right" : "left")") }
        if dy != 0 { parts.append("\(abs(dy)) \(dy > 0 ? "down" : "up")") }
        return parts.isEmpty ? "here" : parts.joined(separator: " and ")
    }

    // MARK: - Swiping

    /// A swipe turns once it has gone far enough one way; the same finger can
    /// carry on and turn again (an L-shaped swipe is two turns).
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                if swipeStart != value.startLocation {
                    swipeStart = value.startLocation
                    swipeAnchor = nil
                }
                let anchor = swipeAnchor ?? value.startLocation
                let dx = value.location.x - anchor.x
                let dy = value.location.y - anchor.y
                guard max(abs(dx), abs(dy)) >= 18 else {
                    if swipeAnchor == nil { swipeAnchor = anchor }
                    return
                }
                let direction: SnakeDirection
                if abs(dx) > abs(dy) {
                    direction = dx > 0 ? .right : .left
                } else {
                    direction = dy > 0 ? .down : .up
                }
                session.turn(direction)
                swipeAnchor = value.location
            }
            .onEnded { _ in
                swipeAnchor = nil
                swipeStart = nil
            }
    }

    // MARK: - Cards

    @ViewBuilder
    private var cardLayer: some View {
        switch session.stage {
        case .intro:
            cardFrame { SnakeIntroCard(session: session, dark: dark) }
        case .paused:
            cardFrame { SnakePauseCard(session: session) }
        case .over:
            if let result = session.result {
                cardFrame {
                    SnakeOverCard(result: result, onAgain: { session.play() }, onMenu: { session.menu() })
                }
            }
        case .ready, .playing, .dying:
            EmptyView()
        }
    }

    private func cardFrame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(dark ? 0.35 : 0.14)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            content()
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// VoiceOver hears each change of stage without hunting for it.
    private func announce(_ stage: SnakeSession.Stage) {
        let words: String
        switch stage {
        case .ready:
            words = session.resuming ? "Paused. Press an arrow to carry on." : "Ready. Press an arrow to start."
        case .over:
            guard let result = session.result else { return }
            words = result.newBest ? "New best. \(result.score) points." : "Game over. \(result.score) points. Best \(result.best)."
        case .paused:
            words = "Paused."
        case .intro, .playing, .dying:
            return
        }
        UIAccessibility.post(notification: .announcement, argument: words)
    }
}

/// "Swipe to start", over the board while the snake waits.
struct SnakeReadyHint: View {
    let resuming: Bool
    let pad: Bool
    @State private var lifted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 16, weight: .bold))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.title(15))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .offset(y: lifted ? -4 : 0)
        .onAppear {
            guard !reduceMotion else { return }
            // A few bobs, not forever: the board's own clock goes quiet after a
            // while of waiting and this should too, so an idle phone stays cool.
            withAnimation(.easeInOut(duration: 0.8).repeatCount(15, autoreverses: true)) { lifted = true }
        }
    }

    private var text: String {
        let how = pad ? "Swipe or press an arrow" : "Swipe"
        return resuming ? "\(how) to carry on" : "\(how) to start"
    }
}
