import SwiftUI
import UIKit

/// Sky Hopper: the score along the top with Pause, the sky in the middle
/// (Hop bounces by itself; tilt or hold the arrows to steer), the arrows or
/// the tilt bar underneath, and a card before, during a pause and after
/// each run. Pushed on the Games stack by `PhysicsGameScreen`.
struct SkyHopperScreen: View {
    @StateObject private var session = SkyHopperSession()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        ZStack {
            GeometryReader { geo in
                // A short phone keeps the arrows a little smaller so the sky stays big.
                playArea(barHeight: geo.size.height < 640 ? 60 : 72)
            }
            cardLayer
        }
        .srPaper()
        .navigationTitle(GameKind.skyHopper.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        // While Hop is in the air the arrows are held near the screen's
        // edges: hiding the back button switches the back swipe off. Pause
        // brings it back.
        .navigationBarBackButtonHidden(session.isSteering)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: session.stage)
        .animation(.easeInOut(duration: 0.25), value: session.toast)
        .onAppear { session.setVoiceOver(voiceOver) }
        .onChange(of: voiceOver) { _, on in session.setVoiceOver(on) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.sleep() }
        }
        .onChange(of: session.stage) { _, stage in announce(stage) }
        .onDisappear { session.leave() }
        .accessibilityIdentifier("sky-hopper-screen")
    }

    private var dark: Bool { colorScheme == .dark }
    private var cardUp: Bool {
        session.stage == .intro || session.stage == .paused || session.stage == .over
    }

    // MARK: - Play area

    private func playArea(barHeight: CGFloat) -> some View {
        VStack(spacing: 10) {
            hud
            statusLine
            board
            SkyHopperControlBar(session: session, buttons: session.showsButtons, height: barHeight)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        // Behind a card the sky is scenery: VoiceOver reads the card.
        .accessibilityHidden(cardUp)
    }

    private var hud: some View {
        HStack(spacing: 8) {
            SkyHopperStatBox(title: "Score", value: session.score, strong: true, rolls: false)
                .accessibilityIdentifier("sky-hopper-score")
            SkyHopperStatBox(title: "Best", value: max(session.best, session.score), rolls: false)
                .accessibilityIdentifier("sky-hopper-best")
            SkyHopperStatBox(title: "Stars", value: session.stars)
                .accessibilityIdentifier("sky-hopper-stars")
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
        .disabled(!session.isSteering)
        .opacity(session.isSteering ? 1 : 0.4)
        .accessibilityLabel("Pause")
        .accessibilityIdentifier("sky-hopper-pause")
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Label(session.zone.name, systemImage: "cloud.sun.fill")
                .font(SR.Text.label())
                .foregroundStyle(SR.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            SkyHopperPowerChips(powers: session.powers)
            Text("\(session.metres) m")
                .font(SR.Text.mono(13))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .accessibilityLabel("\(session.metres) metres up")
        }
        .padding(.horizontal, 4)
    }

    // MARK: - The sky

    private var board: some View {
        GeometryReader { geo in
            boardStack
                .frame(width: geo.size.width, height: geo.size.height)
                .onAppear { session.fit(width: Double(geo.size.width), height: Double(geo.size.height)) }
                .onChange(of: geo.size) { _, size in
                    session.fit(width: Double(size.width), height: Double(size.height))
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var boardStack: some View {
        let shape = RoundedRectangle(cornerRadius: SkyHopperScene.radius, style: .continuous)
        return SkyHopperSkyView(clock: session.clock, session: session,
                                hop: SkyHopperHopPaint.of(session.colour), dark: dark, calm: reduceMotion)
            .clipShape(shape)
            .overlay(shape.stroke(rim, lineWidth: 1))
            .overlay(alignment: .bottom) { readyHint }
            .overlay(alignment: .top) { toastView }
            .shadow(color: Color.black.opacity(dark ? 0.4 : 0.16), radius: 14, x: 0, y: 6)
            .contentShape(Rectangle())
            .onTapGesture { session.start() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(boardLabel)
            .accessibilityAction { session.start() }
            .accessibilityIdentifier("sky-hopper-board")
    }

    private var rim: Color { dark ? Color.white.opacity(0.10) : Color.black.opacity(0.12) }

    @ViewBuilder
    private var readyHint: some View {
        if session.stage == .ready && !session.scripted {
            SkyHopperReadyHint(resuming: session.resuming, buttons: session.showsButtons)
                .padding(.bottom, 18)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = session.toast {
            Label(toast, systemImage: "sparkles")
                .font(SR.Text.title(15))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .padding(.top, 12)
                .padding(.horizontal, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    /// Where Hop is and where the next cloud is, in words.
    private var boardLabel: String {
        let game = session.game
        let hop = game.hopper
        var words = "Sky, \(session.zone.name), \(session.metres) metres up."
        let above = game.clouds.filter { $0.y > hop.y + 2 && $0.isSolid(at: game.time) }.min { $0.y < $1.y }
        if let cloud = above {
            let dx = Int(SkyHopperRules.wrapDelta(from: hop.x, to: cloud.x).rounded())
            let side = abs(dx) <= 6 ? "straight above" : dx > 0 ? "\(abs(dx)) to the right" : "\(abs(dx)) to the left"
            words += " Next \(cloud.kind.word) \(side)."
        }
        if session.powers.propeller > 0 { words += " Flying with the propeller cap." }
        if session.powers.bubble { words += " A bubble will catch a fall." }
        if session.stage == .ready { words += " Double tap to start." }
        return words
    }

    // MARK: - Cards

    @ViewBuilder
    private var cardLayer: some View {
        switch session.stage {
        case .intro:
            cardFrame { SkyHopperIntroCard(session: session) }
        case .paused:
            cardFrame { SkyHopperPauseCard(session: session) }
        case .over:
            if let result = session.result {
                cardFrame {
                    SkyHopperOverCard(result: result, onAgain: { session.play() }, onMenu: { session.menu() })
                }
                if result.newBest {
                    GameConfettiView(seed: UInt64(max(1, result.score)))
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        case .ready, .playing, .falling:
            EmptyView()
        }
    }

    private func cardFrame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(dark ? 0.35 : 0.14)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            content()
                .frame(maxWidth: 480)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// VoiceOver hears each change of stage without hunting for it.
    private func announce(_ stage: SkyHopperSession.Stage) {
        let words: String
        switch stage {
        case .ready:
            words = session.resuming ? "Paused in mid-air. Press an arrow to carry on." : "Ready. Press an arrow to start."
        case .over:
            guard let result = session.result else { return }
            words = result.newBest
                ? "New best. \(result.score) points, \(result.metres) metres."
                : "Game over. \(result.metres) metres, \(result.score) points. Best \(result.best)."
        case .paused:
            words = "Paused."
        case .falling:
            words = "Hop fell."
        case .intro, .playing:
            return
        }
        UIAccessibility.post(notification: .announcement, argument: words)
    }
}

/// "Tap the sky to start", over the sky while Hop waits.
struct SkyHopperReadyHint: View {
    let resuming: Bool
    let buttons: Bool
    @State private var lifted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
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
        .padding(.horizontal, 12)
        .offset(y: lifted ? -4 : 0)
        .onAppear {
            guard !reduceMotion else { return }
            // A few bobs, not forever: the sky's own clock goes quiet after a
            // while of waiting and this should too.
            withAnimation(.easeInOut(duration: 0.8).repeatCount(15, autoreverses: true)) { lifted = true }
        }
    }

    private var text: String {
        let how = buttons ? "Tap the sky or press an arrow" : "Tap the sky"
        return resuming ? "\(how) to carry on" : "\(how) to start"
    }
}
