import SwiftUI

/// Solitaire: Klondike patience on the cloth, the clock and moves above it,
/// big thumb buttons below, and a card over it all between games. Played on
/// this phone, offline; a game left half-way is there next time.
struct SolitaireScreen: View {
    @StateObject private var game = SolitaireGame()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SolitaireFeltView(felt: game.settings.felt)
            VStack(spacing: 8) {
                SolitaireHUD(game: game)
                    .padding(.horizontal, 12)
                SolitaireTable(game: game)
                    .overlay(alignment: .bottom) { stuckBanner }
                SolitaireControls(game: game)
                    .padding(.horizontal, 12)
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
            if game.stage == .won && !game.showResults {
                // Any tap during the cascade brings the results up.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { game.skipCelebration() }
                    .accessibilityElement()
                    .accessibilityLabel("You won. Show the results")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { game.skipCelebration() }
            }
            SolitaireOverlay(game: game)
        }
        .animation(.snappy(duration: 0.25), value: game.stage)
        .animation(.snappy(duration: 0.25), value: game.showResults)
        .navigationTitle(GameKind.solitaire.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.pause() }
        }
        .onChange(of: game.stage) { _, stage in
            if stage == .won && reduceMotion { game.skipCelebration() }
        }
        .onDisappear { game.leave() }
        .accessibilityIdentifier("solitaire-screen")
    }

    @ViewBuilder
    private var stuckBanner: some View {
        if game.stuck && game.isPlaying {
            SolitaireStuckBanner(game: game)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - The strip at the top

/// Time, moves, which draw, and pause.
struct SolitaireHUD: View {
    @ObservedObject var game: SolitaireGame

    var body: some View {
        HStack(spacing: 14) {
            figure("TIME") { clock }
            figure("MOVES") {
                Text("\(game.session.moves)")
                    .font(SR.Text.figure(20))
                    .foregroundStyle(SR.ink)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 4)
            dealChip
            pauseButton
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .srGlassCard(.paper, radius: 24)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func figure<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.inkMuted)
            value()
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var clock: some View {
        if game.clockRunning {
            TimelineView(.periodic(from: Date(), by: 1)) { _ in clockText }
        } else {
            clockText
        }
    }

    private var clockText: some View {
        Text(SolitaireClock.format(game.elapsedNow))
            .font(SR.Text.figure(20))
            .foregroundStyle(SR.ink)
            .accessibilityLabel(SolitaireClock.spoken(game.elapsedNow))
    }

    private var dealChip: some View {
        HStack(spacing: 4) {
            if game.session.proven {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SR.good)
            }
            Text(game.session.drawMode.title.uppercased())
                .font(SR.Text.label())
                .tracking(0.8)
                .foregroundStyle(SR.inkSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(SR.ink.opacity(0.07)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.session.proven ? "\(game.session.drawMode.title), a deal that can be won" : game.session.drawMode.title)
    }

    private var pauseButton: some View {
        Button {
            SRHaptic.tap()
            game.pause()
        } label: {
            Image(systemName: "pause.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(SR.ink)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(SRPressStyle())
        .disabled(game.stage != .playing)
        .accessibilityLabel("Pause")
        .accessibilityIdentifier("solitaire-pause")
    }
}

// MARK: - The buttons at the bottom

/// Undo, hint, draw (or finish, once nothing is hidden) and a new deal,
/// each a big target for a thumb.
struct SolitaireControls: View {
    @ObservedObject var game: SolitaireGame
    @State private var confirmingNew = false

    var body: some View {
        HStack(spacing: 8) {
            SolitaireBarButton(icon: "arrow.uturn.backward", title: "Undo", enabled: game.canUndo,
                               identifier: "solitaire-undo") { game.undo() }
            SolitaireBarButton(icon: "lightbulb.fill", title: "Hint", enabled: game.isPlaying && !game.finishing,
                               identifier: "solitaire-hint") { game.showHint() }
            if game.canFinish || game.finishing {
                SolitaireBarButton(icon: "wand.and.stars", title: "Finish", enabled: game.canFinish, prominent: true,
                                   identifier: "solitaire-finish") { game.finish() }
            } else {
                SolitaireBarButton(icon: "rectangle.stack.fill", title: "Draw", enabled: drawEnabled,
                                   identifier: "solitaire-draw") { game.draw() }
            }
            SolitaireBarButton(icon: "plus.rectangle.on.rectangle", title: "New", enabled: game.isPlaying,
                               identifier: "solitaire-new") { askForNewDeal() }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .confirmationDialog("Deal a new game?", isPresented: $confirmingNew, titleVisibility: .visible) {
            Button("New deal", role: .destructive) { game.newDeal() }
            Button("Start this deal again") { game.restartDeal() }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("A new deal counts this game as not won and ends your streak. Starting again keeps the same cards.")
        }
    }

    private var drawEnabled: Bool {
        game.isPlaying && !game.finishing && !(game.state.stock.isEmpty && game.state.waste.isEmpty)
    }

    private func askForNewDeal() {
        if game.session.started && !game.session.won {
            confirmingNew = true
        } else {
            game.newDeal()
        }
    }
}

/// A big square-ish button: an icon over a word.
struct SolitaireBarButton: View {
    let icon: String
    let title: String
    var enabled = true
    var prominent = false
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(SRPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private var content: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
            Text(title.uppercased())
                .font(SR.Text.label())
                .tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var label: some View {
        if prominent {
            content
                .foregroundStyle(SR.paper)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(SR.accentDeep))
        } else {
            content
                .foregroundStyle(SR.ink)
                .srGlassCard(.paper, radius: 20, interactive: true)
        }
    }
}

/// Said when nothing on the table helps any more.
struct SolitaireStuckBanner: View {
    @ObservedObject var game: SolitaireGame

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.title3)
                .foregroundStyle(SR.warn)
            Text("No moves left that help. Undo a few, or deal again.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .srGlassCard(.paper, radius: 20)
        // It only tells; the cards under it can still be played.
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("solitaire-stuck")
    }
}
