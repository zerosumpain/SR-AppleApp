import SwiftUI

/// Tilt Maze's front page: carry on where you left off, how to play, the
/// forty levels with their stars, and the endless run.
struct TiltMazeMenu: View {
    @ObservedObject var game: TiltMazeGame

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Physics", title: GameKind.tiltMaze.title, strap: GameKind.tiltMaze.line)
                carryOn
                TiltMazeHowToPlay(steersByTilt: game.steersByTilt)
                if game.tiltAvailable { steering }
                levels
                endless
                totals
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tilt-maze-menu")
    }

    /// The next level to play, one tap away.
    private var carryOn: some View {
        let n = game.book.unlocked
        let info = TiltMazeCatalogue.info(n)
        let fresh = game.book.stars(for: n) == 0
        return Button {
            SRHaptic.tap()
            game.play(n)
        } label: {
            SRButtonLabel(title: fresh ? "Play level \(n): \(info.name)" : "Play level \(n) again", icon: "play.fill", fill: true)
                .frame(minHeight: 56)
        }
        .srButton(.prominent)
        .controlSize(.large)
        .accessibilityIdentifier("tilt-maze-start")
    }

    private var steering: some View {
        Toggle(isOn: $game.useStick) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Use the joystick")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(game.useStick ? "Drag the stick on screen to roll the marble." :
                        "Off: tilt the phone to roll the marble.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(SR.accent)
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("tilt-maze-stick")
    }

    private var levels: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Levels", trailing: "\(game.book.totalStars) of \(TiltMazeCatalogue.campaignCount * 3) stars")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(1...TiltMazeCatalogue.campaignCount, id: \.self) { n in
                    TiltMazeLevelTile(number: n, stars: game.book.stars(for: n), open: game.book.isOpen(n),
                                      next: n == game.book.unlocked) {
                        game.play(n)
                    }
                }
            }
            Text("The first ten are drawn by hand to teach the board. After that every maze is bigger, with more holes.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var endless: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Endless", trailing: game.book.endlessBest > 0 ? "Best \(game.book.endlessBest)" : nil)
            SRCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("How far can you go?")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Text("Fresh mazes one after another, growing as you go. Three marbles: a fall costs one, and every third maze earns one back.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        SRHaptic.tap()
                        game.playEndless()
                    } label: {
                        SRButtonLabel(title: "Play endless", icon: "infinity", fill: true)
                            .frame(minHeight: 50)
                    }
                    .srButton(.regular)
                    .controlSize(.large)
                    .accessibilityIdentifier("tilt-maze-endless")
                }
            }
        }
    }

    private var totals: some View {
        let book = game.book
        let mazes = book.mazesCleared == 1 ? "1 maze cleared" : "\(book.mazesCleared) mazes cleared"
        let falls = book.falls == 1 ? "1 fall" : "\(book.falls) falls"
        return Text("\(mazes) · \(falls). Bests are kept on this phone.")
            .font(SR.Text.mono())
            .foregroundStyle(SR.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// How to play, in four lines.
struct TiltMazeHowToPlay: View {
    let steersByTilt: Bool

    var body: some View {
        SRCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("HOW TO PLAY")
                    .font(SR.Text.label())
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(SR.accent)
                rule(steersByTilt ? "Tilt the phone to roll the marble. Steer it into the brass cup."
                     : "Drag the joystick to roll the marble. Steer it into the brass cup.")
                rule("A hole sends you back to the start, or to the last flag you rolled over.")
                rule("The clock starts when the marble moves. Be quick for up to three stars.")
                if steersByTilt {
                    rule("The target button makes the way you are holding the phone level.")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func rule(_ text: String) -> some View {
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

/// One level in the grid: its number, its stars, or a lock.
struct TiltMazeLevelTile: View {
    let number: Int
    let stars: Int
    let open: Bool
    /// The one to play next: ringed.
    let next: Bool
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            VStack(spacing: 4) {
                if open {
                    Text("\(number)")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                    TiltMazeStars(lit: stars, size: 9)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(SR.inkGhost)
                    Text("\(number)")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkGhost)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius, interactive: open)
            .overlay {
                if next {
                    RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                        .stroke(SR.accent, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
        }
        .buttonStyle(SRPressStyle())
        .disabled(!open)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("tilt-maze-level-\(number)")
    }

    private var label: String {
        let name = TiltMazeCatalogue.info(number).name
        guard open else { return "Level \(number), \(name), locked" }
        let starsText = stars == 0 ? "not yet cleared" : (stars == 1 ? "1 star" : "\(stars) stars")
        return "Level \(number), \(name), \(starsText)"
    }
}
