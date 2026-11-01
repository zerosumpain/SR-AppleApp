import SwiftUI

/// Before a level: how to play, who is playing, which level, then Play.
struct TetherPalsIntroCard: View {
    @ObservedObject var session: TetherPalsSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TetherPalsCardHolder {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    howTo
                    playersPicker
                    levelPicker
                }
            }
            playButton
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("tether-pals-intro")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TETHER PALS")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text("Everyone to the flag. Nobody gets left behind.")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 10) {
            TetherPalsHowRow(icon: "arrow.left.and.right", text: "Left, right and jump. The level is done when every pal is at the flag.")
            TetherPalsHowRow(icon: "person.2.fill", text: "Too high or too far? Walk into a pal, hop on their head, and jump off it.",
                             tint: TetherPalsPalette.palDeep(0))
            TetherPalsHowRow(icon: "link", text: "Tied together? Walking drags your pal along, and you can pull them up a ledge.",
                             tint: TetherPalsPalette.palDeep(1))
            TetherPalsHowRow(icon: "circle.circle.fill", text: "Stand on a button to open its doors and bridges.",
                             tint: TetherPalsPalette.channelDeep(.gold))
        }
    }

    private var playersPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHO'S PLAYING")
                .font(SR.Text.label())
                .tracking(SR.inkLabelTracking)
                .foregroundStyle(SR.inkMuted)
            HStack(spacing: 8) {
                ForEach(TetherPalsPlayers.allCases) { players in
                    TetherPalsChoiceTile(icon: players.icon, title: players.title, selected: session.players == players) {
                        session.choose(players: players)
                    }
                    .accessibilityIdentifier("tether-pals-players-\(players.rawValue)")
                }
            }
            Text(session.players.line)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LEVELS")
                    .font(SR.Text.label())
                    .tracking(SR.inkLabelTracking)
                    .foregroundStyle(SR.inkMuted)
                Spacer()
                Label("\(session.records.stars) of \(TetherPalsCatalogue.count)", systemImage: "star.fill")
                    .font(SR.Text.mono(12))
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityLabel("\(session.records.stars) stars of \(TetherPalsCatalogue.count)")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(TetherPalsCatalogue.all) { level in
                    TetherPalsLevelChip(number: level.number, open: session.isOpen(level.number),
                                        selected: session.levelNumber == level.number,
                                        star: session.records.hasStar(level.number),
                                        cleared: session.records.isCleared(level.number)) {
                        session.choose(level: level.number)
                    }
                }
            }
            Text(levelLine)
                .font(SR.Text.mono(13))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var levelLine: String {
        let level = session.level
        let par = "par \(TetherPalsFormat.par(level.par))"
        guard let best = session.best else { return "\(level.number). \(level.name) · \(par)" }
        return "\(level.number). \(level.name) · best \(TetherPalsFormat.time(best)) · \(par)"
    }

    private var playButton: some View {
        Button {
            SRHaptic.tap()
            session.play()
        } label: {
            SRButtonLabel(title: "Play level \(session.levelNumber)", icon: "play.fill", fill: true)
                .frame(minHeight: 48)
        }
        .srButton(.prominent)
        .controlSize(.large)
        .accessibilityIdentifier("tether-pals-start")
    }
}

/// A choice on the start card: an icon over a word.
struct TetherPalsChoiceTile: View {
    let icon: String
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(SR.Text.label(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).fill(fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var ink: Color { selected ? SR.paper : SR.ink }
    private var fill: Color { selected ? SR.accent : SR.ink.opacity(0.06) }
}

/// A level on the start card: its number, a star when under par, a lock when shut.
struct TetherPalsLevelChip: View {
    let number: Int
    let open: Bool
    let selected: Bool
    let star: Bool
    let cleared: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                if open {
                    Text("\(number)")
                        .font(SR.Text.title(16))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Image(systemName: mark)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(markInk)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .disabled(!open)
        .accessibilityLabel(accessibilityWords)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("tether-pals-level-\(number)")
    }

    private var mark: String {
        if star { return "star.fill" }
        return cleared ? "checkmark" : "circle"
    }

    private var markInk: Color {
        if star { return Color(red: 0.95, green: 0.7, blue: 0.1) }
        return selected ? SR.paper : SR.inkMuted
    }

    private var ink: Color {
        if selected { return SR.paper }
        return open ? SR.ink : SR.inkGhost
    }

    private var fill: Color {
        if selected { return SR.accent }
        return SR.ink.opacity(open ? 0.07 : 0.03)
    }

    private var accessibilityWords: String {
        guard open else { return "Level \(number), locked" }
        if star { return "Level \(number), star" }
        return cleared ? "Level \(number), cleared" : "Level \(number)"
    }
}

/// Mid-level, the clock stopped.
struct TetherPalsPauseCard: View {
    @ObservedObject var session: TetherPalsSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PAUSED")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text("Level \(session.levelNumber) · \(session.level.name)")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("\(TetherPalsFormat.time(session.elapsed)) so far. The pals wait where you left them: press any button to carry on.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TetherPalsHowRow(icon: "lightbulb.fill", text: session.level.tip, tint: TetherPalsPalette.channelDeep(.gold))
            Button {
                session.resume()
            } label: {
                SRButtonLabel(title: "Resume", icon: "play.fill", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("tether-pals-resume")
            Button {
                session.showMe()
            } label: {
                SRButtonLabel(title: "Show me how", icon: "eye.fill", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("tether-pals-show-me")
            HStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    session.play()
                } label: {
                    SRButtonLabel(title: "Restart", icon: "arrow.counterclockwise", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("tether-pals-restart")
                Button {
                    SRHaptic.tap()
                    session.menu()
                } label: {
                    SRButtonLabel(title: "Levels", icon: "square.grid.3x2.fill", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("tether-pals-menu")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("tether-pals-paused")
    }
}

/// Everyone made it: the time against the best and par, and what opened.
struct TetherPalsOverCard: View {
    let result: TetherPalsResult
    let hasNext: Bool
    let onNext: () -> Void
    let onAgain: () -> Void
    let onMenu: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TetherPalsCardHolder {
                VStack(alignment: .leading, spacing: 12) {
                    kicker
                    Text(title)
                        .font(SR.Text.display(22))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(line)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    chips
                    Text(tally)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let opened = result.opened {
                        TetherPalsHowRow(icon: "lock.open.fill",
                                         text: "Level \(opened) is open: \(TetherPalsCatalogue.level(opened).name).", tint: SR.good)
                    }
                }
            }
            buttons
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("tether-pals-over")
    }

    private var kicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 18, weight: .bold))
                .accessibilityHidden(true)
            Text(kickerText)
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
        }
        .foregroundStyle(SR.good)
    }

    private var kickerText: String {
        if result.allCleared && result.level == TetherPalsCatalogue.count { return "EVERY LEVEL CLEARED" }
        if result.newBest { return "NEW BEST" }
        return "LEVEL \(result.level) CLEARED"
    }

    private var title: String {
        result.players == .solo ? "Both pals made it to the flag!" : "Everyone made it to the flag!"
    }

    private var line: String {
        if result.newStar { return "Under par: you've earned this level's star." }
        if result.star { return "Under par again. Can you go faster still?" }
        return "Finish in under \(TetherPalsFormat.par(result.par)) to earn the star."
    }

    private var chips: some View {
        HStack(spacing: 8) {
            TetherPalsStatChip(label: "TIME", value: TetherPalsFormat.time(result.time))
            TetherPalsStatChip(label: "BEST", value: TetherPalsFormat.time(result.best))
            TetherPalsStatChip(label: "PAR", value: TetherPalsFormat.par(result.par), icon: result.star ? "star.fill" : nil)
        }
    }

    private var tally: String {
        "Level \(result.level), \(result.name): \(TetherPalsFormat.pops(result.pops)) on the way."
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            if hasNext {
                Button {
                    SRHaptic.tap()
                    onNext()
                } label: {
                    SRButtonLabel(title: "Next level", icon: "arrow.right", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("tether-pals-next")
            }
            HStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    onAgain()
                } label: {
                    SRButtonLabel(title: "Play again", icon: "arrow.counterclockwise", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(hasNext ? .regular : .prominent)
                .controlSize(.large)
                .accessibilityIdentifier("tether-pals-again")
                Button {
                    SRHaptic.tap()
                    onMenu()
                } label: {
                    SRButtonLabel(title: "Levels", icon: "square.grid.3x2.fill", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("tether-pals-over-menu")
            }
        }
    }
}
