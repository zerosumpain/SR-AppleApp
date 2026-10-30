import SwiftUI
import UIKit

// The pieces Wordle Race, Anagram Blitz and Boggle share on the phone: the
// clock as a pill and a draining bar, the big thumb-sized buttons, the
// "+4" that floats off a word that landed, the burst for a big moment, the
// how-to-play card in the lobby and the bests card at the finish.
//
// Nothing here animates while idle. The clock ticks twice a second (as
// `WordleTimer` always has); the float and the burst run for about a second
// after their trigger changes and then stop, so a phone left on a results
// page draws nothing at all.

// MARK: - The clock

/// The time left, as a pill: a timer glyph beside `WordleTimer`, on glass.
struct WordRoomClock<Store: GameRoomStoring>: View {
    let room: GameRoom
    @ObservedObject var store: Store
    /// The timer's accessibility id ("wordle-timer", "anagram-timer"…).
    let id: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.body.weight(.bold))
                .foregroundStyle(SR.inkMuted)
                .accessibilityHidden(true)
            WordleTimer(room: room, store: store, id: id)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .srGlassCard(.paper, radius: 22)
    }
}

/// The sand running out: a bar that empties towards the limit and warms as
/// it goes, with one tap on the phone as the last ten seconds begin.
///
/// Ticks, not an animation: a bar that is always animating keeps the app
/// from ever going idle, and UI tests then cannot read the screen.
struct WordRoomTimeBar<Store: GameRoomStoring>: View {
    let room: GameRoom
    @ObservedObject var store: Store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            WordRoomTimeBarFill(fraction: fraction, urgency: urgency)
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private var msLeft: Double? {
        guard let end = room.phaseEndsAt, let now = store.serverNow() else { return nil }
        return max(0, end - now)
    }

    private var fraction: CGFloat {
        guard let left = msLeft, let limit = room.timeLimitMs, limit > 0 else { return 1 }
        return CGFloat(min(1, max(0, left / limit)))
    }

    private var urgency: WordRoomUrgency {
        WordRoomUrgency.of(msLeft: msLeft, limitMs: room.timeLimitMs)
    }
}

/// The bar itself, so the one-off tap can watch the urgency change.
struct WordRoomTimeBarFill: View {
    let fraction: CGFloat
    let urgency: WordRoomUrgency

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SR.line)
                Capsule()
                    .fill(LinearGradient(colors: [tone.opacity(0.75), tone], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, geo.size.width * fraction))
            }
        }
        .onChange(of: urgency) { old, new in
            if new == .last, old != .last { SRHaptic.tap() }
        }
    }

    private var tone: Color {
        switch urgency {
        case .calm: return SR.good
        case .hurry: return SR.warn
        case .last: return SR.error
        }
    }
}

// MARK: - Buttons

/// How loud a big button is.
enum WordRoomButtonTone {
    /// The one thing to press now: accent, cream type.
    case go
    /// A firm second action: ink, paper type.
    case firm
    /// Everything else: a lifted sheet, ink type.
    case soft
}

/// A big, thumb-sized button, at least 56 points tall, that gives under the
/// finger (dims instead under Reduce Motion) and greys out when disabled.
struct WordRoomButtonStyle: ButtonStyle {
    var tone: WordRoomButtonTone = .soft
    var height: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        WordRoomButtonBody(configuration: configuration, tone: tone, height: height)
    }
}

/// Its own view so it can read the environment.
struct WordRoomButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tone: WordRoomButtonTone
    let height: CGFloat

    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(SR.Text.label(15))
            .tracking(1.1)
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 10)
            .background(plate)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(enabled ? (pressed && reduceMotion ? 0.8 : 1) : 0.4)
            .scaleEffect(pressed && !reduceMotion ? 0.95 : 1)
            .animation(.snappy(duration: 0.16), value: pressed)
    }

    private var ink: Color {
        switch tone {
        case .go: return SR.cream
        case .firm: return SR.paper
        case .soft: return SR.ink
        }
    }

    @ViewBuilder
    private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        switch tone {
        case .go:
            shape.fill(LinearGradient(colors: [SR.accent, SR.accentDeep], startPoint: .top, endPoint: .bottom))
                .shadow(color: SR.accentDeep.opacity(0.35), radius: 6, y: 3)
        case .firm:
            shape.fill(SR.ink)
        case .soft:
            shape.fill(SR.surface)
                .overlay(shape.strokeBorder(SR.line, lineWidth: 1))
        }
    }
}

/// A key or a tile that dips when pressed — the play field's own buttons.
struct WordRoomPressStyle: ButtonStyle {
    var depth: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        WordRoomPressBody(configuration: configuration, depth: depth)
    }
}

struct WordRoomPressBody: View {
    let configuration: ButtonStyleConfiguration
    let depth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? depth : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Motion

/// A quick swell and settle, once per change of `animatableData` — the
/// same trick as `WordleShake`: animating from n to n + 1 passes through
/// the fractions, and a whole number is at rest.
struct WordRoomPop: GeometryEffect {
    var animatableData: CGFloat
    var amount: CGFloat = 0.12

    func effectValue(size: CGSize) -> ProjectionTransform {
        let phase = animatableData - animatableData.rounded(.down)
        let scale = 1 + amount * CGFloat(sin(Double(phase) * Double.pi))
        let tx = size.width * (1 - scale) / 2
        let ty = size.height * (1 - scale) / 2
        return ProjectionTransform(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: tx, ty: ty))
    }
}

/// "+4" rising off the word that landed and fading as it goes. `token`
/// changes once per word; nothing is drawn at rest.
struct WordRoomFloatUp: View {
    let text: String
    let token: Int
    var tone: Color = SR.good

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1

    var body: some View {
        Text(text)
            .font(SR.Text.figure(30))
            .foregroundStyle(tone)
            .shadow(color: SR.paper.opacity(0.9), radius: 3)
            .offset(y: -56 * progress)
            .opacity(progress >= 1 ? 0 : 1 - Double(progress) * 0.9)
            .scaleEffect(1 + 0.25 * progress)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: token) { _, _ in
                guard !reduceMotion, !text.isEmpty else { return }
                progress = 0
                // From the start, on the next turn of the run loop: set and
                // animated in one turn, SwiftUI would see only the end.
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.9)) { progress = 1 }
                }
            }
    }
}

/// A burst of paper bits from the middle, for a big moment: a seven-letter
/// word, a solve, a new best. Draws for 1.4 seconds after `token` changes,
/// then stops; nothing under Reduce Motion.
struct WordRoomBurst: View {
    let token: Int
    var colours: [Color] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started: Date?

    static let duration: Double = 1.4
    static let pieces = 26

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: started == nil)) { timeline in
            Canvas { context, size in
                guard let start = started else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t >= 0, t < Self.duration else { return }
                Self.draw(context: &context, size: size, t: t, colours: palette, seed: token)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: token) { _, _ in
            guard !reduceMotion else { return }
            let mine = Date()
            started = mine
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Self.duration * 1_000_000_000) + 50_000_000)
                // A later burst owns the clock now; leave it running.
                if started == mine { started = nil }
            }
        }
    }

    private var palette: [Color] {
        colours.isEmpty ? [SR.accent, SR.good, SR.warn, SR.accentInk] : colours
    }

    /// Each piece flies out on its own angle and speed, falls a little, spins
    /// and fades. Seeded, so the same token gives the same burst.
    static func draw(context: inout GraphicsContext, size: CGSize, t: Double, colours: [Color], seed: Int) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let reach = Double(min(size.width, size.height)) * 0.55
        let fade = max(0, 1 - t / duration)
        for i in 0..<pieces {
            let r1 = unit(seed &* 31 &+ i &* 7)
            let r2 = unit(seed &* 17 &+ i &* 13 &+ 3)
            let angle = Double(i) / Double(pieces) * 2 * Double.pi + r1 * 0.5
            let speed = reach * (0.55 + 0.45 * r2)
            let travel = speed * (1 - pow(1 - min(1, t / 0.7), 3))
            let x = Double(centre.x) + cos(angle) * travel
            let y = Double(centre.y) + sin(angle) * travel + 60 * t * t
            let side = 5 + 5 * r1
            let rect = CGRect(x: -side / 2, y: -side * 0.35, width: side, height: side * 0.7)
            var piece = context
            piece.translateBy(x: CGFloat(x), y: CGFloat(y))
            piece.rotate(by: .radians(angle + t * (4 + 6 * r2)))
            piece.opacity = fade
            let colour = colours[i % max(colours.count, 1)]
            piece.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(colour))
        }
    }

    /// 0..<1 from an integer, cheaply and the same every time.
    static func unit(_ n: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: n) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x % 10_000) / 10_000
    }
}

// MARK: - Status

/// One short line in a capsule: a refusal, a word that landed, a hint.
struct WordRoomPill: View {
    let text: String
    var icon: String? = nil
    var tone: Color = SR.inkMuted
    var filled = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(SR.Text.bodyMedium(15))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(filled ? SR.paper : tone)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(filled ? tone : tone.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
    }
}

/// The card that takes the keyboard's or the board's place once I have
/// nothing left to play: solved, out, or only watching.
struct WordRoomWaitCard: View {
    let icon: String
    let title: String
    let line: String
    var tone: Color = SR.accent

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(SR.paper)
                .frame(width: 52, height: 52)
                .background(Circle().fill(tone))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SR.Text.display(20))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The lobby's how-to-play

/// One step of how to play: a symbol and a sentence.
struct WordRoomStep: Identifiable {
    let icon: String
    let text: String
    var id: String { text }
}

/// How to play, in the lobby: the game's own little picture, three or four
/// steps, and my best so far — so the wait for others teaches the game.
struct WordRoomHowToCard<Art: View>: View {
    let title: String
    let steps: [WordRoomStep]
    /// "Your best: 23 points", or nil before any round.
    let best: String?
    let id: String
    let art: Art

    init(title: String, steps: [WordRoomStep], best: String?, id: String, @ViewBuilder art: () -> Art) {
        self.title = title
        self.steps = steps
        self.best = best
        self.id = id
        self.art = art()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text(title.uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            art
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: step.icon)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(SR.accent)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        Text(step.text)
                            .font(SR.Text.body(15))
                            .foregroundStyle(SR.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let best {
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SR.warn)
                        .accessibilityHidden(true)
                    Text(best)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Bests at the finish

/// One figure on the bests card.
struct WordRoomBestItem: Identifiable {
    let label: String
    let value: String
    /// Set by this round: lit, and said so.
    var fresh = false
    var id: String { label }
}

/// My bests in this game, kept on this phone, with any this round just set
/// lit up and a burst the first time the page shows them.
struct WordRoomBestsCard: View {
    let items: [WordRoomBestItem]
    let id: String

    @State private var burst = 0

    private var anyFresh: Bool { items.contains { $0.fresh } }

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Your bests", trailing: anyFresh ? "New best" : "On this phone")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(items) { item in
                    tile(item)
                }
            }
        }
        .overlay {
            WordRoomBurst(token: burst, colours: [SR.warn, SR.accent, SR.good])
                .frame(height: 220)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
        .onAppear {
            guard anyFresh, burst == 0 else { return }
            // After the standings have settled in.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { burst += 1 }
        }
    }

    private func tile(_ item: WordRoomBestItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(item.label.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.1)
                    .foregroundStyle(item.fresh ? SR.accentInk : SR.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if item.fresh {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SR.warn)
                        .accessibilityHidden(true)
                }
            }
            Text(item.value)
                .font(SR.Text.figure(24))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .fill(item.fresh ? SR.warn.opacity(0.18) : SR.surface.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .strokeBorder(item.fresh ? SR.warn : SR.line, lineWidth: item.fresh ? 1.5 : 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.label), \(item.value)\(item.fresh ? ", a new best" : "")")
    }
}
