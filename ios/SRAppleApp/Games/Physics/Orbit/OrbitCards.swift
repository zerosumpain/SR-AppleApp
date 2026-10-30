import SwiftUI

// The cards over the field: a level's briefing, the pause, running out of
// probes and the results. Paper glass in the app's own type, so they read
// the same as Lander's and follow light and dark mode.

/// One to three stars in a row, filled for those earned.
struct OrbitStarRow: View {
    let earned: Int
    var total = 3
    var font: Font = .title2
    /// The earned stars pop in one after another.
    var animated = false
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Image(systemName: i < visible ? "star.fill" : "star")
                    .font(font.weight(.bold))
                    .foregroundStyle(i < visible ? OrbitPaint.goldDeep : SR.inkGhost)
                    .scaleEffect(i < visible ? 1 : 0.86)
            }
        }
        .onAppear { reveal() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(earned) of \(total) stars")
    }

    private var visible: Int { animated && !reduceMotion ? shown : earned }

    private func reveal() {
        guard animated, !reduceMotion, earned > 0 else { return }
        shown = 0
        let count = earned
        Task { @MainActor in
            for i in 1...count {
                try? await Task.sleep(nanoseconds: i == 1 ? 300_000_000 : 280_000_000)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { shown = i }
                SRHaptic.tap()
            }
        }
    }
}

/// A bullet line on a card.
struct OrbitRuleLine: View {
    let text: String
    var icon = "circle.fill"
    var tone: Color = SR.accent
    var small = true

    var body: some View {
        Label {
            Text(text)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .font(small ? Font.system(size: 5) : Font.footnote.weight(.bold))
                .foregroundStyle(tone)
        }
    }
}

/// How to play, in four lines: on the level list and before level 1.
struct OrbitHowToPlay: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            OrbitRuleLine(text: "Drag anywhere on space and pull back, like a catapult. The probe flies the other way; pull further for more power.")
            OrbitRuleLine(text: "The dotted line shows the start of the flight. Fine-tune with the turn and power buttons, then press Launch.")
            OrbitRuleLine(text: "Planets, moons and suns all pull. Hitting anything solid, flying into rocks or a black hole, or drifting off into space ends the flight.")
            OrbitRuleLine(text: "Stars: one for reaching the station or wormhole, one for picking up every gold star, one for doing it within par. Five probes a level.")
        }
    }
}

/// A primary action on a card.
struct OrbitCardButton: View {
    let title: String
    let icon: String
    var prominent = true
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            SRButtonLabel(title: title, icon: icon, fill: true)
                .frame(minHeight: 44)
        }
        .srButton(prominent ? .prominent : .regular)
        .controlSize(.large)
    }
}

/// Before the first launch on a level: its name, what it asks, the three
/// stars on offer and the best so far.
struct OrbitBriefingCard: View {
    @ObservedObject var game: OrbitGame

    var body: some View {
        let lv = game.level
        let best = game.progress.best(lv.number)
        VStack(alignment: .leading, spacing: 12) {
            Text("LEVEL \(lv.number) · \(lv.system.title.uppercased())")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text(lv.name)
                .font(SR.Text.display(24))
                .foregroundStyle(SR.ink)
            Text(lv.hint)
                .font(SR.Text.body(15))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if lv.number == 1 && game.progress.finishedLevels == 0 {
                OrbitHowToPlay()
            }
            goals(lv)
            if let best {
                HStack(spacing: 8) {
                    Text("BEST")
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                    OrbitStarRow(earned: best.stars, font: .footnote)
                    Text(best.launches == 1 ? "in 1 launch" : "in \(best.launches) launches")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                }
            }
            OrbitCardButton(title: "Start", icon: "scope") { game.begin() }
                .accessibilityIdentifier("orbit-start")
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: 520, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityIdentifier("orbit-briefing")
    }

    private func goals(_ lv: OrbitLevel) -> some View {
        let reach = lv.target.kind == .station ? "Dock with the station" : "Fly into the wormhole"
        let stars = lv.stars.count == 1 ? "Pick up the gold star" : "Pick up all \(lv.stars.count) gold stars"
        let par = lv.par == 1 ? "Do it with your first probe" : "Do it in \(lv.par) launches or fewer"
        return VStack(alignment: .leading, spacing: 4) {
            OrbitRuleLine(text: reach, icon: "star.fill", tone: OrbitPaint.goldDeep, small: false)
            OrbitRuleLine(text: stars, icon: "star.fill", tone: OrbitPaint.goldDeep, small: false)
            OrbitRuleLine(text: par, icon: "star.fill", tone: OrbitPaint.goldDeep, small: false)
        }
    }
}

/// Paused: carry on, start the level again, or go back to the list.
struct OrbitPauseCard: View {
    @ObservedObject var game: OrbitGame

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PAUSED")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text("Level \(game.levelNumber): \(game.level.name)")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(game.hud.probesLeft) of \(OrbitPhysics.probes) probes left, \(game.hud.starsGot) of \(game.hud.starsTotal) stars picked up.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
            OrbitCardButton(title: "Resume", icon: "play.fill") { game.resume() }
                .accessibilityIdentifier("orbit-resume")
            HStack(spacing: 10) {
                OrbitCardButton(title: "Restart", icon: "arrow.counterclockwise", prominent: false) { game.retry() }
                    .accessibilityIdentifier("orbit-restart")
                OrbitCardButton(title: "Levels", icon: "square.grid.3x3", prominent: false) { game.showLevels() }
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: 520, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityIdentifier("orbit-paused")
    }
}

/// Every probe spent without arriving.
struct OrbitOutOfProbesCard: View {
    @ObservedObject var game: OrbitGame

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OUT OF PROBES")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.error)
            Text("So close. Have another go.")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
            Text("All \(OrbitPhysics.probes) probes are spent. The dotted ghost shows your last flight, so you can aim from there.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            OrbitCardButton(title: "Try again", icon: "arrow.counterclockwise") { game.retry() }
                .accessibilityIdentifier("orbit-again")
            OrbitCardButton(title: "Levels", icon: "square.grid.3x3", prominent: false) { game.showLevels() }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: 520, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityIdentifier("orbit-out")
    }
}

/// Arrived: the stars earned, how it went, the best, and what next.
struct OrbitResultsCard: View {
    @ObservedObject var game: OrbitGame
    let finish: OrbitFinish

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kicker)
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.good)
            HStack(alignment: .center) {
                Text(game.level.name)
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                OrbitStarRow(earned: finish.stars, font: .title, animated: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                OrbitRuleLine(text: launchesLine, icon: finish.launches <= finish.par ? "checkmark.circle.fill" : "circle",
                              tone: finish.launches <= finish.par ? SR.good : SR.inkMuted, small: false)
                OrbitRuleLine(text: starsLine, icon: finish.starsGot == finish.starsTotal ? "checkmark.circle.fill" : "circle",
                              tone: finish.starsGot == finish.starsTotal ? SR.good : SR.inkMuted, small: false)
                OrbitRuleLine(text: bestLine, icon: "trophy.fill", tone: OrbitPaint.goldDeep, small: false)
            }
            if finish.level < OrbitLevels.count {
                OrbitCardButton(title: "Level \(finish.level + 1)", icon: "arrow.right") { game.nextLevel() }
                    .accessibilityIdentifier("orbit-next")
            } else {
                OrbitCardButton(title: "All levels", icon: "square.grid.3x3") { game.showLevels() }
                    .accessibilityIdentifier("orbit-next")
            }
            HStack(spacing: 10) {
                OrbitCardButton(title: "Play again", icon: "arrow.counterclockwise", prominent: false) { game.retry() }
                    .accessibilityIdentifier("orbit-replay")
                if finish.level < OrbitLevels.count {
                    OrbitCardButton(title: "Levels", icon: "square.grid.3x3", prominent: false) { game.showLevels() }
                }
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: 520, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityIdentifier("orbit-results")
    }

    private var kicker: String {
        if finish.newBest && finish.stars == 3 { return "PERFECT · NEW BEST" }
        if finish.newBest { return "NEW BEST" }
        return game.level.target.kind == .station ? "DOCKED" : "THROUGH THE WORMHOLE"
    }

    private var launchesLine: String {
        let used = finish.launches == 1 ? "1 launch" : "\(finish.launches) launches"
        return "\(used), par \(finish.par)"
    }

    private var starsLine: String {
        "\(finish.starsGot) of \(finish.starsTotal) gold stars picked up"
    }

    private var bestLine: String {
        let total = game.progress.totalStars
        return "Best here \(finish.bestStars) of 3 · \(total) of \(OrbitLevels.count * 3) stars in all"
    }
}
