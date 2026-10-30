import SwiftUI

// The pieces Tap Duel, Quick Maths Sprint and Sequence Memory share beyond
// the shared lobby and standings: the how-to-play card in the lobby, the
// personal-best card and the stat tiles on the results, the podium, the
// confetti for a win, and the key press every big game button uses.

// MARK: - How to play

/// One rule on the how-to card: an SF Symbol and a line.
struct QuickRoomRule: Identifiable {
    let icon: String
    let text: String
    var id: String { text }
}

/// The lobby's how-to-play card: a one-line pitch, three or four rules, and
/// this phone's best at the room's difficulty when there is one. The rules
/// fold away for somebody who has played a few games here; the header opens
/// them again.
struct QuickRoomHowTo: View {
    let pitch: String
    let rules: [QuickRoomRule]
    /// "Best 212 ms", already worded.
    var best: String? = nil
    /// Games this phone has recorded; from three the rules start folded.
    var played: Int = 0
    var tint: Color = SR.accent
    let id: String

    /// The reader's own choice, once they have pressed the header.
    @State private var toggled: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rulesOpen: Bool { toggled ?? (played < 3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(pitch)
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            if rulesOpen {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rules) { rule in
                        ruleRow(rule)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(SR.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                SRHaptic.select()
                let next = !rulesOpen
                if reduceMotion {
                    toggled = next
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { toggled = next }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("HOW TO PLAY")
                        .font(SR.Text.label())
                        .tracking(SR.kickerTracking)
                    Image(systemName: rulesOpen ? "chevron.up" : "chevron.down")
                        .font(SR.Text.label())
                }
                .foregroundStyle(tint)
                .frame(minHeight: SR.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rulesOpen ? "How to play, hide the rules" : "How to play, show the rules")
            .accessibilityIdentifier("\(id)-toggle")
            Spacer(minLength: 8)
            if let best {
                Label(best, systemImage: "trophy.fill")
                    .font(SR.monoMedium(12))
                    .foregroundStyle(SR.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func ruleRow(_ rule: QuickRoomRule) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: rule.icon)
                .font(SR.Text.title(16))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.14)))
                .accessibilityHidden(true)
            Text(rule.text)
                .font(SR.Text.body(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }
}

// MARK: - Buttons

/// A big game key that gives under the thumb: it shrinks a touch and darkens
/// while pressed. Under Reduce Motion it only darkens.
struct QuickRoomKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pressed(configuration: configuration)
    }

    private struct Pressed: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
                .brightness(configuration.isPressed ? -0.08 : 0)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
        }
    }
}

// MARK: - Results

/// A personal best on this phone: the figure, whether this game set it, and
/// what it was before. The star pops in when it is new.
struct QuickRoomBestCard: View {
    /// "Your fastest tap", "Your best sprint".
    let title: String
    /// The best, worded ("198 ms"), or nil before one has counted.
    let value: String?
    let isNew: Bool
    /// "was 212 ms", when a new best beat an old one.
    var previous: String? = nil
    let id: String

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            badge
            VStack(alignment: .leading, spacing: 3) {
                Text(isNew ? "NEW PERSONAL BEST" : "PERSONAL BEST")
                    .font(SR.Text.label())
                    .tracking(1.4)
                    .foregroundStyle(SR.accent)
                Text(value ?? "None yet")
                    .font(SR.Text.figure(28))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(detail)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .fill(isNew ? SR.accent.opacity(0.10) : Color.clear)
        )
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier(id)
        .onAppear {
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.25)) { shown = true }
            }
        }
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(isNew ? SR.accent : SR.accent.opacity(0.14))
            Image(systemName: isNew ? "star.fill" : "trophy.fill")
                .font(SR.Text.title(22))
                .foregroundStyle(isNew ? SR.paper : SR.accent)
        }
        .frame(width: 54, height: 54)
        .scaleEffect(shown ? 1 : 0.4)
        .opacity(shown ? 1 : 0)
        .accessibilityHidden(true)
    }

    private var detail: String {
        if let previous, isNew { return "\(title) · \(previous)" }
        return title
    }

    private var spoken: String {
        let figure = value ?? "none yet"
        return isNew ? "New personal best. \(title): \(figure)" : "Personal best. \(title): \(figure)"
    }
}

/// One figure for a stat tile.
struct QuickRoomStat: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

/// Two to four figures in tiles — score, right, best streak.
struct QuickRoomStatRow: View {
    let stats: [QuickRoomStat]

    var body: some View {
        let count = stats.count <= 3 ? max(1, stats.count) : 2
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(stats) { stat in
                tile(stat)
            }
        }
    }

    private func tile(_ stat: QuickRoomStat) -> some View {
        VStack(spacing: 4) {
            Text(stat.value)
                .font(SR.Text.figure(26))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(stat.label.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stat.label), \(stat.value)")
    }
}

/// One step of the podium.
struct QuickRoomPodiumSlot: Identifiable {
    let rank: Int
    let row: GameStanding
    var id: String { row.id }
}

/// The top three on steps — first in the middle and tallest — rising in when
/// the page opens. A picture of the standings card below it, so VoiceOver
/// reads the card and skips this.
struct QuickRoomPodium: View {
    let room: GameRoom
    /// The figure under each name: "3 rounds", "24 pts".
    let figure: (GameStanding) -> String

    @State private var risen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(slots) { slot in
                step(slot)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                risen = true
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.72).delay(0.1)) { risen = true }
            }
        }
    }

    /// Second, first, third — so first stands in the middle.
    private var slots: [QuickRoomPodiumSlot] {
        let top = Array((room.standings ?? []).prefix(3))
        let ranked = top.enumerated().map { QuickRoomPodiumSlot(rank: $0.offset + 1, row: $0.element) }
        guard ranked.count >= 2 else { return ranked }
        var order: [QuickRoomPodiumSlot] = [ranked[1], ranked[0]]
        if ranked.count > 2 { order.append(ranked[2]) }
        return order
    }

    private func step(_ slot: QuickRoomPodiumSlot) -> some View {
        let won = room.winnerIds.contains(slot.row.id)
        return VStack(spacing: 6) {
            if won {
                Image(systemName: "crown.fill")
                    .font(SR.Text.title(18))
                    .foregroundStyle(SR.accent)
            }
            GameInitial(name: slot.row.name, tone: tone(slot.rank), side: slot.rank == 1 ? 48 : 40)
            Text(slot.row.id == room.meId ? "You" : slot.row.name)
                .font(SR.Text.title(15))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(figure(slot.row))
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tone(slot.rank).gradient)
                Text("\(slot.rank)")
                    .font(SR.Text.hero(30))
                    // The ground token: the step's fill lifts in dark mode.
                    .foregroundStyle(SR.paper)
                    .padding(.top, 8)
            }
            .frame(height: height(slot.rank))
            .scaleEffect(x: 1, y: risen ? 1 : 0.05, anchor: .bottom)
        }
        .frame(maxWidth: 120)
    }

    private func height(_ rank: Int) -> CGFloat {
        switch rank {
        case 1: return 104
        case 2: return 78
        default: return 60
        }
    }

    private func tone(_ rank: Int) -> Color {
        switch rank {
        case 1: return SR.accent
        case 2: return SR.accentInk
        default: return SR.inkSecondary
        }
    }
}

// MARK: - Confetti

/// A burst of confetti falling from the top for a couple of seconds, then
/// nothing at all: the timeline stops once it is done, and Reduce Motion never
/// starts it. Draw it over a page with `.overlay`; it takes no touches.
struct QuickRoomConfetti: View {
    static let duration: Double = 2.8
    static let pieces = 72

    @State private var start = Date()
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion || finished {
                Color.clear
            } else {
                falling
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            start = Date()
            try? await Task.sleep(nanoseconds: UInt64(Self.duration * 1_000_000_000))
            finished = true
        }
    }

    private var falling: some View {
        let colours: [Color] = [SR.accent, SR.Hue.family.glow, SR.Hue.trips.glow,
                                SR.Hue.games.glow, SR.goodOnDark, Color(hex: SRPaint.current.palette.warn.dark)]
        let began = start
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSince(began)
            Canvas { context, size in
                QuickRoomConfetti.draw(&context, size: size, t: t, colours: colours)
            }
        }
        .ignoresSafeArea()
    }

    /// One frame: every piece from its seed, so nothing is stored per piece.
    static func draw(_ context: inout GraphicsContext, size: CGSize, t: Double, colours: [Color]) {
        guard t >= 0, !colours.isEmpty else { return }
        let fade = max(0, min(1, (duration - t) / 0.7))
        let width = Double(size.width)
        let height = Double(size.height)
        for i in 0..<pieces {
            let seed = Double(i) + 1
            let r1 = unit(seed * 12.9898)
            let r2 = unit(seed * 78.233)
            let r3 = unit(seed * 37.719)
            let delay = r2 * 0.4
            let tt = t - delay
            if tt < 0 { continue }
            let x = width * r1 + (r2 - 0.5) * 140 * tt + sin(tt * 3 + seed) * 16
            let y = -24 + (140 + r3 * 220) * tt + 130 * tt * tt
            if y > height + 24 { continue }
            var piece = context
            piece.opacity = fade
            piece.translateBy(x: CGFloat(x), y: CGFloat(y))
            piece.rotate(by: .radians(tt * (2 + r3 * 6) + seed))
            let w = CGFloat(7 + r1 * 5)
            let h = CGFloat(4 + r3 * 3)
            let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            piece.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(colours[i % colours.count]))
        }
    }

    /// A repeatable 0..<1 from a seed.
    private static func unit(_ x: Double) -> Double {
        let s = sin(x) * 43758.5453
        return s - floor(s)
    }
}
