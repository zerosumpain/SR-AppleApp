import SwiftUI
import UIKit

/// Tether Pals: the level, time and best along the top with Pause, the
/// level's name with Restart, the world in the middle, and a strip of
/// buttons per player along the bottom; a card before, during a pause and
/// after each level. Pushed on the Games stack by `PhysicsGameScreen`.
struct TetherPalsScreen: View {
    @StateObject private var session = TetherPalsSession()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            GeometryReader { geo in
                playArea(compact: geo.size.height < 640)
            }
            cardLayer
        }
        .srPaper()
        .navigationTitle(GameKind.tetherPals.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: session.stage)
        .animation(.easeInOut(duration: 0.25), value: session.toast)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.pause() }
        }
        .onChange(of: session.stage) { _, stage in announce(stage) }
        .onDisappear { session.leave() }
        .accessibilityIdentifier("tether-pals-screen")
    }

    private var dark: Bool { colorScheme == .dark }
    private var live: Bool { session.stage == .ready || session.stage == .playing }
    private var cardUp: Bool {
        session.stage == .intro || session.stage == .paused || session.stage == .over
    }

    // MARK: - Play area

    private func playArea(compact: Bool) -> some View {
        VStack(spacing: 8) {
            hud
            statusLine
            board
            TetherPalsPad(session: session, rowHeight: padRow(compact: compact))
                .opacity(live ? 1 : 0.5)
                .allowsHitTesting(live)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        // Behind a card the level is scenery: VoiceOver reads the card.
        .accessibilityHidden(cardUp)
    }

    /// A strip's height: a little shorter on a short phone, taller for solo's one strip.
    private func padRow(compact: Bool) -> CGFloat {
        if session.solo { return compact ? 62 : 74 }
        return compact ? 52 : 62
    }

    private var hud: some View {
        HStack(spacing: 8) {
            TetherPalsStatBox(title: "Level", value: "\(session.levelNumber)", strong: true)
                .accessibilityIdentifier("tether-pals-level")
            TetherPalsStatBox(title: "Time", value: TetherPalsFormat.time(session.elapsed))
                .accessibilityIdentifier("tether-pals-score")
            TetherPalsStatBox(title: "Best", value: TetherPalsFormat.time(session.best))
                .accessibilityIdentifier("tether-pals-best")
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
        .disabled(!live)
        .opacity(live ? 1 : 0.4)
        .accessibilityLabel("Pause")
        .accessibilityIdentifier("tether-pals-pause")
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Label(session.level.name, systemImage: session.level.icon)
                .font(SR.Text.label())
                .foregroundStyle(SR.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if session.level.tied { tiedChip }
            parChip
            restartButton
        }
        .padding(.horizontal, 4)
    }

    private var tiedChip: some View {
        Image(systemName: "link")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(SR.accent)
            .accessibilityLabel("Tied together")
    }

    private var parChip: some View {
        HStack(spacing: 3) {
            Image(systemName: session.records.hasStar(session.levelNumber) ? "star.fill" : "star")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.95, green: 0.7, blue: 0.1))
                .accessibilityHidden(true)
            Text("PAR \(TetherPalsFormat.par(session.level.par))")
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private var restartButton: some View {
        Button {
            session.restart()
        } label: {
            Label("Restart", systemImage: "arrow.counterclockwise")
                .font(SR.Text.label(13))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .srGlassCard(.paper, radius: 22)
                .contentShape(Capsule())
        }
        .buttonStyle(SRPressStyle())
        .disabled(!live)
        .accessibilityLabel("Restart the level")
        .accessibilityIdentifier("tether-pals-restart-level")
    }

    // MARK: - Board

    private var board: some View {
        GeometryReader { geo in
            let level = session.level
            let cell = min(geo.size.width / CGFloat(level.columns), geo.size.height / CGFloat(level.rows))
            boardStack(cell: cell)
                .frame(width: cell * CGFloat(level.columns), height: cell * CGFloat(level.rows))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func boardStack(cell: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return TetherPalsBoardView(clock: session.clock, session: session, dark: dark, calm: reduceMotion)
            .clipShape(shape)
            .overlay(shape.stroke(SR.line, lineWidth: 1))
            .overlay(alignment: .top) { notes }
            .overlay(alignment: .topLeading) { homeChip }
            .shadow(color: Color.black.opacity(dark ? 0.4 : 0.14), radius: 12, x: 0, y: 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(session.boardLabel)
            .accessibilityIdentifier("tether-pals-board")
    }

    /// Over the sky, where the pals seldom are: a toast, and the hint before a start.
    private var notes: some View {
        VStack(spacing: 6) {
            toastView
            readyHint
        }
        .padding(.top, 8)
        .padding(.horizontal, 10)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var readyHint: some View {
        if session.stage == .ready && !session.scripted {
            TetherPalsReadyHint(tip: session.level.tip, resuming: session.resuming)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = session.toast {
            Text(toast)
                .font(SR.Text.title(14))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var homeChip: some View {
        if session.watching {
            Label("Watch how", systemImage: "eye.fill")
                .font(SR.Text.label())
                .foregroundStyle(Color.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .padding(8)
                .allowsHitTesting(false)
        } else if session.stage == .playing || session.stage == .cheering {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
                Text("\(session.homeCount) of \(session.team)")
                    .font(SR.Text.label())
                    .monospacedDigit()
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.4)))
            .padding(8)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private var cardLayer: some View {
        switch session.stage {
        case .intro:
            cardFrame { TetherPalsIntroCard(session: session) }
        case .paused:
            cardFrame { TetherPalsPauseCard(session: session) }
        case .over:
            if let result = session.result {
                cardFrame {
                    TetherPalsOverCard(result: result, hasNext: session.hasNext,
                                       onNext: { session.playNext() }, onAgain: { session.play() }, onMenu: { session.menu() })
                }
                .overlay { GameConfettiView(seed: UInt64(result.level), count: 60).allowsHitTesting(false).accessibilityHidden(true) }
            }
        case .ready, .playing, .cheering:
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
    private func announce(_ stage: TetherPalsSession.Stage) {
        let words: String
        switch stage {
        case .ready:
            words = session.resuming
                ? "Paused. Press any button to carry on."
                : "Level \(session.levelNumber), \(session.level.name). \(session.level.tip) Press any button to start."
        case .cheering:
            words = "Everyone made it to the flag."
        case .over:
            guard let result = session.result else { return }
            words = result.newBest
                ? "New best. \(TetherPalsFormat.time(result.time))."
                : "Level cleared in \(TetherPalsFormat.time(result.time))."
        case .paused:
            words = "Paused."
        case .intro, .playing:
            return
        }
        UIAccessibility.post(notification: .announcement, argument: words)
    }
}
