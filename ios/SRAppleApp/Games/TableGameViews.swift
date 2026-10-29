import SwiftUI
import UIKit

// The pieces Liar's Dice, Pass the Plate and Fireworks share at the table:
// the turn banner with its clock, the big buttons, a celebration that plays
// once and stops, the how-to-play sheet, and the record this phone keeps.
//
// Nothing here animates while the screen is idle. The clock ticks twice a
// second (as the old turn bars did — an always-animating view keeps the app
// from going idle, and UI tests then cannot read the screen); a celebration
// runs for a few seconds and then removes itself.

// MARK: - The turn clock

/// The turn running out, as a dial: a ring that empties and warms, and the
/// seconds in the middle. When it is my turn it nudges (a light tap) at ten
/// and five seconds.
///
/// It reads the server's clock through the room's store, exactly as the
/// shared 3-2-1 (`GameCountdownView`) does.
struct TableTurnClock<Store: GameRoomStoring>: View {
    let store: Store
    let endsAt: Double?
    let turnMs: Double
    var mine: Bool = false
    var side: CGFloat = 56

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let current = store.serverNow()
            TableClockDial(
                fraction: TableClock.fraction(endsAt: endsAt, turnMs: turnMs, now: current),
                seconds: TableClock.secondsLeft(endsAt: endsAt, now: current),
                mine: mine,
                side: side
            )
        }
    }
}

/// One frame of the clock.
struct TableClockDial: View {
    let fraction: Double
    let seconds: Int?
    let mine: Bool
    var side: CGFloat = 56

    var body: some View {
        let urgency = TableClock.urgency(fraction: fraction, seconds: seconds)
        ZStack {
            Circle().fill(SR.surface)
            Circle().stroke(SR.line, lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(tone(urgency), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: figure)
                .font(.system(size: side * 0.36, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(urgency == .last ? SR.error : SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(width: side, height: side)
        .onChange(of: seconds) { old, new in
            if mine, TableClock.nudge(from: old, to: new) { SRHaptic.tap() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var figure: String {
        guard let seconds else { return "–" }
        return String(seconds)
    }

    private var spoken: String {
        guard let seconds else { return "Turn clock" }
        return seconds == 1 ? "1 second left" : "\(seconds) seconds left"
    }

    private func tone(_ urgency: TableClock.Urgency) -> Color {
        switch urgency {
        case .calm: return SR.good
        case .hurry: return SR.warn
        case .last: return SR.error
        }
    }
}

// MARK: - The turn banner

/// The top of the table: whose move it is, said big. When it is mine the
/// banner is the accent; otherwise it is a quiet sheet of glass. The caller
/// supplies the words (so a game can combine them into one VoiceOver element
/// with its own identifier) and, optionally, the clock.
struct TableTurnBanner<Content: View, Clock: View>: View {
    let mine: Bool
    @ViewBuilder var content: Content
    @ViewBuilder var clock: Clock

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            clock
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 14)
        .background(backing)
        .srAnimation(.snappy(duration: 0.3), value: mine)
    }

    @ViewBuilder
    private var backing: some View {
        let shape = RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
        if mine {
            shape
                .fill(SR.accent)
                .shadow(color: SR.accent.opacity(0.35), radius: 12, x: 0, y: 6)
        } else {
            Color.clear.srGlassCard(.paper)
        }
    }

}

/// Type on the banner: the paper colour on the accent (it holds its contrast
/// in both modes — the accent is deep on a light phone and lifted on a dark
/// one), ink otherwise.
enum TableTurnInk {
    static func ink(_ mine: Bool) -> Color { mine ? SR.paper : SR.ink }
    static func soft(_ mine: Bool) -> Color { mine ? SR.paper.opacity(0.88) : SR.inkSecondary }
    static func kicker(_ mine: Bool) -> Color { mine ? SR.paper.opacity(0.88) : SR.accent }
}

/// The banner's usual words: a kicker, the headline and a line under it.
struct TableTurnWords: View {
    let mine: Bool
    let kicker: String
    let title: String
    var detail: String? = nil
    var titleId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(kicker.uppercased())
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(TableTurnInk.kicker(mine))
                .fixedSize(horizontal: false, vertical: true)
            titleText
            if let detail {
                Text(detail)
                    .font(SR.Text.secondary())
                    .foregroundStyle(TableTurnInk.soft(mine))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var titleText: some View {
        let text = Text(title)
            .font(SR.Text.display(26))
            .foregroundStyle(TableTurnInk.ink(mine))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        if let titleId {
            text.accessibilityIdentifier(titleId)
        } else {
            text
        }
    }
}

// MARK: - Buttons

/// A big, solid, thumb-sized button: 56pt tall, a capsule of `fill` with
/// `ink` type, giving a little under the finger (dimming instead under Reduce
/// Motion). `outline` is the quieter partner: the surface with a hairline.
struct TableSolidButtonStyle: ButtonStyle {
    var fill: Color = SR.accent
    var ink: Color = SR.paper
    var outline: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        Pressed(configuration: configuration, fill: fill, ink: ink, outline: outline)
    }

    private struct Pressed: View {
        let configuration: ButtonStyleConfiguration
        let fill: Color
        let ink: Color
        let outline: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .foregroundStyle(textColour)
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.horizontal, 14)
                .background(backing)
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
                .animation(.snappy(duration: 0.16), value: configuration.isPressed)
        }

        private var textColour: Color {
            if !enabled { return SR.inkMuted }
            return outline ? SR.ink : ink
        }

        @ViewBuilder
        private var backing: some View {
            if outline {
                ZStack {
                    Capsule().fill(SR.surface)
                    Capsule().strokeBorder(enabled ? SR.ink.opacity(0.28) : SR.line, lineWidth: 1.5)
                }
            } else {
                Capsule()
                    .fill(enabled ? fill : SR.line)
                    .shadow(color: enabled ? fill.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
            }
        }
    }
}

/// The big buttons' label: an icon and an uppercase, tracked title that
/// shrinks a little rather than truncating.
struct TableButtonLabel: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(SR.Text.title())
                    .accessibilityHidden(true)
            }
            Text(title.uppercased())
                .font(SR.Text.label(15))
                .tracking(1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // Said in its own case: VoiceOver spells some capitals out.
                .accessibilityLabel(title)
        }
        .padding(.vertical, 6)
    }
}

/// A round, 60pt stepper button (− and +).
struct TableRoundButton: View {
    let icon: String
    let label: String
    var enabled: Bool = true
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(enabled ? SR.ink : SR.inkGhost)
                .frame(width: 60, height: 60)
                .background(Circle().fill(SR.surface))
                .overlay(Circle().strokeBorder(enabled ? SR.ink.opacity(0.26) : SR.line, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(SRPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Motion

/// Pops a view in on its first appearance — a stamp landing, a die settling.
/// Under Reduce Motion it is simply there.
struct TablePopIn: ViewModifier {
    var delay: Double = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.55)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.66).delay(delay)) { shown = true }
                }
            }
    }
}

extension View {
    func tablePopIn(delay: Double = 0) -> some View { modifier(TablePopIn(delay: delay)) }
}

// MARK: - Celebration

/// Fireworks over a result: a few bursts in `colours`, for `duration`
/// seconds, then nothing. One Canvas, redrawn on the display's clock only
/// while it runs; skipped entirely under Reduce Motion. Never in the way of a
/// finger and never read aloud.
struct TableCelebration: View {
    let colours: [Color]
    let duration: Double
    private let plan: [TableSparks.Burst]
    private let sparksPerBurst = 18
    @State private var start = Date()
    @State private var running = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(colours: [Color], bursts: Int = 7, duration: Double = 3.4, seed: Int = 1) {
        self.colours = colours
        self.duration = duration
        self.plan = TableSparks.show(count: bursts, duration: duration, seed: seed)
    }

    var body: some View {
        ZStack {
            if running && !reduceMotion && !colours.isEmpty {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        draw(&context, size: size, at: timeline.date.timeIntervalSince(start))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            start = Date()
            try? await Task.sleep(nanoseconds: UInt64(max(0.1, duration) * 1_000_000_000))
            running = false
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, at t: Double) {
        let side = Double(min(size.width, size.height))
        let width = Double(size.width)
        let height = Double(size.height)
        for burst in plan {
            let colour = colours[burst.hue % colours.count]
            for i in 0..<sparksPerBurst {
                guard let spark = TableSparks.spark(i, of: sparksPerBurst, burst: burst, at: t) else { continue }
                let x = burst.x * width + spark.dx * side
                let y = burst.y * height + spark.dy * side
                let r = 2.0 + 2.2 * spark.alpha
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(colour.opacity(spark.alpha)))
            }
        }
    }
}

// MARK: - How to play

/// One step of a game's rules, with an SF Symbol.
struct TableHowToStep: Identifiable {
    let icon: String
    let title: String
    let text: String

    var id: String { title }
}

/// The steps as a list: a numbered icon, a bold line, the detail.
struct TableHowToList: View {
    let steps: [TableHowToStep]
    var tint: Color = SR.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: step.icon)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.paper)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(tint))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(SR.Text.title())
                            .foregroundStyle(SR.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(step.text)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// How to play, as a sheet over the table. The table carries on underneath:
/// these are live games on a shared clock, so there is no pausing them.
struct TableHowToSheet: View {
    let game: String
    let steps: [TableHowToStep]
    var note: String? = nil
    let id: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    SRPageHeader(kicker: game, title: "How to play")
                    TableHowToList(steps: steps)
                    if let note {
                        Label(note, systemImage: "clock")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { dismiss() } label: {
                        TableButtonLabel(title: "Back to the table", icon: "arrow.uturn.backward")
                    }
                    .buttonStyle(TableSolidButtonStyle())
                    .accessibilityIdentifier("\(id)-close")
                }
                .padding(.horizontal, SR.gutter)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .srGround(.warm)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier(id)
    }
}

/// The toolbar's "?" that opens it.
struct TableHelpButton: View {
    let id: String
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            Image(systemName: "questionmark.circle")
        }
        .accessibilityLabel("How to play")
        .accessibilityIdentifier(id)
    }
}

/// The note every table game's how-to ends on.
enum TableHowToNote {
    static let live = "Everyone plays live on the same clock, so the game cannot be paused. If time runs out, the game moves for you."
}

// MARK: - The record

/// What this phone remembers of a game: played, won, the streak, the best
/// score — and, when this game set it, a badge that says so.
struct TableRecordCard: View {
    let record: TableGameRecord
    /// This game's key, so the badge knows whether it set the best.
    let gameKey: String
    /// What the best figure is called ("Best score", "Best show"); nil hides it.
    var bestLabel: String? = "Best score"
    var bestSuffix: String = ""
    var showsWins: Bool = true
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "On this phone", trailing: GameResults.count(record.played, "game", "games"))
            VStack(alignment: .leading, spacing: 12) {
                if record.beatBest(gameKey) {
                    badge("New best!", icon: "star.fill", tone: SR.good)
                } else if showsWins, record.streak >= 2 {
                    badge("\(record.streak) wins in a row", icon: "flame.fill", tone: SR.accent)
                }
                HStack(spacing: 10) {
                    if let bestLabel, let best = record.best {
                        tile(bestLabel, "\(best)\(bestSuffix)")
                    }
                    if showsWins {
                        tile("Won", "\(record.wins)")
                        tile("Best run", "\(record.bestStreak)")
                    } else {
                        tile("Played", "\(record.played)")
                    }
                }
            }
            .padding(SR.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier(id)
    }

    private func badge(_ text: String, icon: String, tone: Color) -> some View {
        Label(text.uppercased(), systemImage: icon)
            .font(SR.Text.label(13))
            .tracking(1)
            .foregroundStyle(SR.paper)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(tone))
            .tablePopIn(delay: 0.3)
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(SR.Text.figure(26))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var spoken: String {
        var bits = ["On this phone: \(GameResults.count(record.played, "game", "games")) played"]
        if showsWins { bits.append("\(record.wins) won, best run \(record.bestStreak)") }
        if let bestLabel, let best = record.best { bits.append("\(bestLabel.lowercased()) \(best)\(bestSuffix)") }
        if record.beatBest(gameKey) { bits.append("a new best") }
        return bits.joined(separator: ", ")
    }
}

/// The colours a win is celebrated in: the accent and a few bright partners.
enum TableCheer {
    static var colours: [Color] {
        [SR.accent, Color(hex: 0xE3B22B), SR.good, Color(hex: 0xC4473C), Color(hex: 0x2F8FD8), Color(hex: 0xF48FB1)]
    }
}
