import SwiftUI

/// Minesweeper: the start card, then the field with the mine counter, the
/// face and the clock above it and Dig / Flag below, and a card at the end.
/// Pushed on the Games stack from the shelf (`PhysicsGameScreen`).
struct MinesweeperScreen: View {
    @StateObject private var game = MinesweeperGame()
    @Environment(\.scenePhase) private var scenePhase
    /// The end card folded away so the field can be looked at.
    @State private var tucked = false

    var body: some View {
        Group {
            if game.stage == .intro {
                MinesweeperIntroView(game: game)
                    .transition(.opacity)
            } else {
                playView
                    .transition(.opacity)
            }
        }
        .srGround(.warm)
        .navigationTitle(GameKind.minesweeper.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .animation(.easeInOut(duration: 0.25), value: game.stage == .intro)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: game.showResult)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: tucked)
        .animation(.easeInOut(duration: 0.2), value: game.paused)
        .onDisappear { game.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.stop() }
        }
        .onChange(of: game.showResult) { _, _ in tucked = false }
        .accessibilityIdentifier("minesweeper-screen")
    }

    // MARK: - Playing

    private var over: Bool { game.stage == .won || game.stage == .lost }

    private var playView: some View {
        VStack(spacing: 12) {
            hud
            boardArea
                .frame(minHeight: 180)
            bottom
                .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var hud: some View {
        HStack(spacing: 10) {
            MinesweeperReadout(label: "MINES", icon: "flag.fill", value: "\(game.board.minesLeft)",
                               spoken: minesSpoken, tint: game.board.minesLeft < 0 ? SR.error : SR.ink)
                .accessibilityIdentifier("minesweeper-mines-left")
            faceButton
            MinesweeperClockReadout(game: game)
        }
    }

    private var minesSpoken: String {
        let n = game.board.minesLeft
        return n == 1 ? "1 mine left to flag" : "\(n) mines left to flag"
    }

    private var faceButton: some View {
        Button {
            SRHaptic.tap()
            tucked = false
            game.restart()
        } label: {
            MinesweeperFace(mood: game.mood)
                .frame(width: 46, height: 46)
                .scaleEffect(game.mood == .worried ? 0.9 : 1)
                .rotationEffect(.degrees(game.mood == .dead ? -8 : 0))
                .animation(.spring(response: 0.28, dampingFraction: 0.55), value: game.mood)
                .frame(width: 68, height: 68)
                .srGlassCard(.paper, radius: 34)
                .contentShape(Circle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel("New field")
        .accessibilityHint("Starts again with a fresh field of the same size")
        .accessibilityIdentifier("minesweeper-face")
    }

    private var boardArea: some View {
        ZStack {
            MinesweeperBoardView(game: game, camera: game.camera, pulse: game.pulse)
            boardOverlay
        }
    }

    @ViewBuilder
    private var boardOverlay: some View {
        if game.paused {
            MinesweeperBoardNote(icon: "pause.fill", text: "Paused")
                .allowsHitTesting(false)
        } else if game.stage == .laying {
            HStack(spacing: 10) {
                ProgressView()
                Text("Laying a fair field…")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .srGlassCard(.paper, radius: 24)
            .allowsHitTesting(false)
            .accessibilityIdentifier("minesweeper-laying")
        } else if game.stage == .ready {
            VStack {
                MinesweeperBoardNote(icon: "hand.tap.fill", text: "Tap any square to start. The first dig is always safe.")
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            .padding(.horizontal, 10)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var bottom: some View {
        if game.paused {
            MinesweeperCardHolder { MinesweeperPausedCard(game: game) }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if over && game.showResult && !tucked {
            MinesweeperCardHolder {
                MinesweeperResultCard(game: game) { tucked = true }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if over {
            overBar
        } else {
            controls
        }
    }

    /// While playing: pause, Dig or Flag, and the zoom on a big field.
    private var controls: some View {
        HStack(spacing: 10) {
            MinesweeperRoundButton(icon: "pause.fill", label: "Pause", id: "minesweeper-pause",
                                   enabled: game.stage == .playing) {
                game.pause()
            }
            MinesweeperModeToggle(flagMode: $game.flagMode)
                .accessibilityIdentifier("minesweeper-mode")
            MinesweeperZoomButton(camera: game.camera, focus: game.focusCell)
        }
    }

    /// After the end card is folded away (or before it rises): the way back in.
    private var overBar: some View {
        HStack(spacing: 10) {
            if game.showResult {
                MinesweeperRoundButton(icon: "chevron.up", label: "Show the result", id: "minesweeper-untuck") {
                    tucked = false
                }
            }
            Button {
                SRHaptic.tap()
                game.restart()
            } label: {
                SRButtonLabel(title: "Play again", icon: "arrow.counterclockwise", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("minesweeper-again-bar")
            MinesweeperZoomButton(camera: game.camera, focus: game.focusCell)
        }
        .frame(minHeight: 64)
    }
}

/// A short note floating on the field: the first-dig hint, "Paused".
struct MinesweeperBoardNote: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(SR.Text.title(15))
        .foregroundStyle(SR.ink)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .srGlassCard(.paper, radius: 22)
    }
}
