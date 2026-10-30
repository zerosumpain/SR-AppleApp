import SwiftUI

/// The card over the table between games: the intro, the shuffle, the pause
/// and the results. Nothing shows while a game is being played.
struct SolitaireOverlay: View {
    @ObservedObject var game: SolitaireGame

    var body: some View {
        switch game.stage {
        case .intro:
            SolitairePanelFrame { SolitaireIntroPanel(game: game) }
        case .shuffling:
            SolitairePanelFrame { SolitaireShufflePanel(game: game) }
        case .paused:
            SolitairePanelFrame { SolitairePausePanel(game: game) }
        case .won:
            if game.showResults {
                SolitairePanelFrame { SolitaireResultsPanel(game: game) }
            }
        case .playing:
            EmptyView()
        }
    }
}

/// A glass card in the middle of a dimmed table, scrolling if the reader's
/// text size makes it taller than the screen.
struct SolitairePanelFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                ScrollView {
                    content
                        .padding(SR.cardPadding + 4)
                        .frame(maxWidth: 460, alignment: .leading)
                        .srGlassCard(.paper)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

/// The eyebrow over a panel's headline.
struct SolitaireKicker: View {
    let text: String
    var tone: Color = SR.accent

    var body: some View {
        Text(text)
            .font(SR.Text.label())
            .tracking(SR.inkKickerTracking)
            .foregroundStyle(tone)
    }
}

/// One line of the rules, with a dot.
struct SolitaireRuleLine: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(SR.accent)
        }
    }
}

// MARK: - Intro

struct SolitaireIntroPanel: View {
    @ObservedObject var game: SolitaireGame

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SolitaireKicker(text: "SOLITAIRE")
            Text("Klondike patience")
                .font(SR.Text.display(24))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            rules
            buttons
            Divider()
            SolitaireSettingsBlock(game: game)
            Divider()
            SolitaireStatsGrid(stats: game.stats, mode: game.settings.drawMode)
        }
        .accessibilityIdentifier("solitaire-intro")
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 6) {
            SolitaireRuleLine(text: "Send every suit home to the top right, ace first, up to the king.")
            SolitaireRuleLine(text: "Build the seven columns downwards, red on black and black on red. Only a king can fill an empty column.")
            SolitaireRuleLine(text: "Tap a card to send it to its best place, or drag it (and the cards on it) where you want. Double-tap sends a card home.")
            SolitaireRuleLine(text: "Tap the stock at the top left, or Draw, to turn over cards. When it runs out, tap it again to turn the pile back over.")
            SolitaireRuleLine(text: "Undo as far back as you like. Hint shows a useful move. Once every card is face up, Finish plays the rest.")
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if game.canCarryOn {
            VStack(spacing: 10) {
                Button {
                    game.carryOn()
                } label: {
                    SRButtonLabel(title: "Carry on", icon: "play.fill", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("solitaire-carry-on")
                Button {
                    SRHaptic.tap()
                    game.newDeal()
                } label: {
                    SRButtonLabel(title: "New deal", icon: "rectangle.stack.badge.plus", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("solitaire-deal")
            }
        } else {
            Button {
                SRHaptic.tap()
                game.newDeal()
            } label: {
                SRButtonLabel(title: "Deal", icon: "rectangle.stack.fill", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("solitaire-deal")
        }
    }
}

// MARK: - Shuffling

struct SolitaireShufflePanel: View {
    @ObservedObject var game: SolitaireGame

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SolitaireKicker(text: "SHUFFLING")
            HStack(spacing: 12) {
                ProgressView()
                    .tint(SR.accent)
                Text("Finding a deal you can win…")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Each deal is played through before it reaches you. It takes a moment or two.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                SRHaptic.tap()
                game.dealAnyway()
            } label: {
                SRButtonLabel(title: "Deal any game", icon: "forward.fill", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("solitaire-deal-any")
        }
        .accessibilityIdentifier("solitaire-shuffling")
    }
}

// MARK: - Paused

struct SolitairePausePanel: View {
    @ObservedObject var game: SolitaireGame

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SolitaireKicker(text: "PAUSED")
            Text(summary)
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                game.resume()
            } label: {
                SRButtonLabel(title: "Carry on", icon: "play.fill", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("solitaire-resume")
            HStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    game.restartDeal()
                } label: {
                    SRButtonLabel(title: "Restart", icon: "arrow.counterclockwise", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityLabel("Start this deal again")
                .accessibilityIdentifier("solitaire-restart")
                Button {
                    SRHaptic.tap()
                    game.newDeal()
                } label: {
                    SRButtonLabel(title: "New deal", icon: "rectangle.stack.badge.plus", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("solitaire-new-deal")
            }
            if game.session.started {
                Text("A new deal counts this game as not won.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            SolitaireSettingsBlock(game: game)
            Divider()
            SolitaireStatsGrid(stats: game.stats, mode: game.session.drawMode)
        }
        .accessibilityIdentifier("solitaire-paused")
    }

    private var summary: String {
        let moves = game.session.moves == 1 ? "1 move" : "\(game.session.moves) moves"
        let home = game.state.foundationCount
        return "\(SolitaireClock.format(game.session.elapsed)) · \(moves) · \(home) of 52 home"
    }
}

// MARK: - Won

struct SolitaireResultsPanel: View {
    @ObservedObject var game: SolitaireGame

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SolitaireKicker(text: kicker, tone: SR.good)
            Text(SolitaireClock.format(game.session.elapsed))
                .font(SR.Text.hero(44))
                .foregroundStyle(SR.ink)
                .accessibilityLabel("Won in \(SolitaireClock.spoken(game.session.elapsed))")
            Text(line)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                SRHaptic.tap()
                game.newDeal()
            } label: {
                SRButtonLabel(title: "Play again", icon: "rectangle.stack.fill", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("solitaire-again")
            Button {
                SRHaptic.tap()
                game.backToIntro()
            } label: {
                SRButtonLabel(title: "Settings and rules", icon: "slider.horizontal.3", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("solitaire-menu")
            Divider()
            SolitaireStatsGrid(stats: game.stats, mode: game.session.drawMode)
        }
        .accessibilityIdentifier("solitaire-won")
    }

    private var kicker: String {
        if game.record.bestTime { return "NEW BEST TIME" }
        if game.record.fewestMoves { return "FEWEST MOVES YET" }
        if game.record.bestStreak { return "LONGEST STREAK YET" }
        return "YOU WON"
    }

    private var line: String {
        let session = game.session
        let moves = session.moves == 1 ? "1 move" : "\(session.moves) moves"
        var parts = ["All 52 home in \(moves), \(session.drawMode.title.lowercased())."]
        if let best = game.stats.bestTime(session.drawMode) {
            parts.append("Best time \(SolitaireClock.format(best)).")
        }
        if game.stats.streak > 1 {
            parts.append("\(game.stats.streak) wins in a row.")
        }
        if session.undos == 0 && session.hintsUsed == 0 {
            parts.append("No undos, no hints.")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Settings

/// The draw, winnable deals, four-colour suits and the cloth.
struct SolitaireSettingsBlock: View {
    @ObservedObject var game: SolitaireGame

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SolitaireKicker(text: "SETTINGS", tone: SR.inkMuted)
            Picker("Draw", selection: $game.settings.drawMode) {
                ForEach(SolitaireDrawMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("solitaire-draw-mode")
            if game.stage == .paused && game.settings.drawMode != game.session.drawMode {
                Text("\(game.settings.drawMode.title) starts with the next deal.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            Toggle(isOn: $game.settings.winnableOnly) {
                toggleLabel("Winnable deals only", "Every deal is checked before you get it.")
            }
            .accessibilityIdentifier("solitaire-winnable")
            Toggle(isOn: $game.settings.fourColour) {
                toggleLabel("Four-colour suits", "Blue diamonds and green clubs, with firmer outlines.")
            }
            .accessibilityIdentifier("solitaire-four-colour")
            feltPicker
        }
        .tint(SR.accent)
    }

    private func toggleLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(SR.Text.bodyMedium())
                .foregroundStyle(SR.ink)
            Text(detail)
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var feltPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Table")
                .font(SR.Text.bodyMedium())
                .foregroundStyle(SR.ink)
            HStack(spacing: 12) {
                ForEach(SolitaireFelt.allCases, id: \.self) { felt in
                    feltSwatch(felt)
                }
            }
        }
    }

    private func feltSwatch(_ felt: SolitaireFelt) -> some View {
        let chosen = game.settings.felt == felt
        return Button {
            SRHaptic.select()
            game.settings.felt = felt
        } label: {
            Circle()
                .fill(RadialGradient(colors: [felt.glow, felt.base], center: .center, startRadius: 2, endRadius: 30))
                .frame(width: 48, height: 48)
                .overlay(Circle().strokeBorder(chosen ? SR.accent : SR.line, lineWidth: chosen ? 3 : 1))
                .overlay {
                    if chosen {
                        Image(systemName: "checkmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(felt.title)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
}

// MARK: - Stats

/// Played, won, the win rate, the streaks and the bests for one draw.
struct SolitaireStatsGrid: View {
    let stats: SolitaireStats
    let mode: SolitaireDrawMode

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12, alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SolitaireKicker(text: "YOUR RECORD", tone: SR.inkMuted)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                cell("Played", "\(stats.played)")
                cell("Won", "\(stats.won)")
                cell("Win rate", "\(stats.winRate)%")
                cell("Streak", "\(stats.streak)")
                cell("Best streak", "\(stats.bestStreak)")
                cell("Best · \(mode.title)", stats.bestTime(mode).map { SolitaireClock.format($0) } ?? "–")
                cell("Fewest moves", stats.fewestMoves(mode).map { "\($0)" } ?? "–")
            }
        }
        .accessibilityIdentifier("solitaire-stats")
    }

    private func cell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(SR.Text.figure(22))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
