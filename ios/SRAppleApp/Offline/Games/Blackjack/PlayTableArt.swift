import SwiftUI

// The table the nearby card and board games are played on, drawn once so
// Blackjack, Cheat, Crazy Eights, Fireworks, Dots and Boxes, Four in a Row,
// Chess and Code Breaker feel like one games room:
//
// - `PlayTableFelt` — green baize inside a wooden rail, for the cards.
// - `PlayTableTurnStrip` — whose turn it is, in their colour, with a ring that
//   drains as the turn clock runs down and goes red at the end.
// - `PlayTableSeatRail` — everyone at the table as a pod: their disc, ringed
//   on their turn, and a little fan of the cards they hold.
// - `PlayTablePile` — a dropped pile of face-down cards, not a neat stack.
// - `PlayTableChips` — casino chips that make a stake.
// - `PlayTableStamp` — "WIN +20", "LIAR!": a result that lands with a thump.
// - `PlayTableButton` — the big thumb-sized action (56pt and up).
// - `PlayTableShake`, `.playTableDeal`, `.playTableFlip` — the motion.
//
// The arithmetic is in `PlayTableMath` (Foundation only, unit-tested). Every
// clock here redraws at most four times a second, and only while it is on
// screen with time left; nothing animates while a table is idle.

// MARK: - Sizes and paint

enum PlayTableMetrics {
    /// The shortest a game's action button is: the owner asked for bigger
    /// buttons in games, and a child's thumb wants more than 44.
    static let bigButton: CGFloat = 56
    /// The label's floor inside a large glass button, which brings the whole
    /// button to `bigButton` or more.
    static let bigLabel: CGFloat = 36
}

/// The table's colours. Fixed in both appearances (a card table is green in a
/// dark room too), a touch deeper in dark mode so it does not glare.
enum PlayTablePaint {
    static let feltLight = Color(light: 0x2E8A5E, dark: 0x237451)
    static let feltDeep = Color(light: 0x165034, dark: 0x0D3523)
    static let railLight = Color(light: 0x9A643A, dark: 0x6E4325)
    static let railDeep = Color(light: 0x5E3519, dark: 0x3F2311)
    /// Type and marks on the felt.
    static let onFelt = Color.white.opacity(0.95)
    static let onFeltMuted = Color.white.opacity(0.74)
    static let gold = Color(hex: 0xF5C451)
    /// A win on the felt, and a loss: light enough to read on green.
    static let winOnFelt = Color(hex: 0x9CF0B8)
    static let loseOnFelt = Color(hex: 0xFFB4AE)
    /// A card's white, and its black and red ink: the same in both
    /// appearances, as a real card is.
    static let cardPaper = Color(hex: 0xFFFDF8)
    static let cardInk = Color(hex: 0x1F1D2B)
    static let cardRed = Color(hex: 0xCF2236)
}

// MARK: - The felt

/// Green baize inside a wooden rail, with the stitched line a real table has.
/// Decoration: hidden from VoiceOver.
struct PlayTableFelt: View {
    var radius: CGFloat = SR.Glass.radius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [PlayTablePaint.railLight, PlayTablePaint.railDeep],
                                      startPoint: .top, endPoint: .bottom))
            shape.inset(by: 5).fill(RadialGradient(colors: [PlayTablePaint.feltLight, PlayTablePaint.feltDeep],
                                                   center: .center, startRadius: 0, endRadius: 340))
            shape.inset(by: 11).stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 6)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Lays this content on the card table.
    func playTableFelt(radius: CGFloat = SR.Glass.radius) -> some View {
        background { PlayTableFelt(radius: radius) }
    }
}

// MARK: - Buttons

/// What a table button says to the hand when it is pressed.
enum PlayTableHaptic {
    case tap, select, ok, none

    func play() {
        switch self {
        case .tap: SRHaptic.tap()
        case .select: SRHaptic.select()
        case .ok: SRHaptic.ok()
        case .none: break
        }
    }
}

/// A big game button: the app's glass at a thumb's size, filling the width
/// it is given (two side by side share a row).
struct PlayTableButton: View {
    let title: String
    var icon: String? = nil
    var weight: SRButtonWeight = .prominent
    var haptic: PlayTableHaptic = .tap
    let action: () -> Void

    var body: some View {
        Button {
            haptic.play()
            action()
        } label: {
            SRButtonLabel(title: title, icon: icon, fill: true)
                .frame(minHeight: PlayTableMetrics.bigLabel)
        }
        .srButton(weight)
        .controlSize(.large)
    }
}

// MARK: - The turn

/// A ring that drains as a timer runs down, with the seconds in it: calm,
/// then amber, then red and a touch bigger in the last few.
struct PlayTableTimerRing: View {
    let secondsLeft: Double
    let total: Double
    var size: CGFloat = 46
    /// Drawn on the felt: light ink and track instead of the ground's.
    var onFelt: Bool = false

    var body: some View {
        let fraction = PlayTableMath.drainFraction(secondsLeft: secondsLeft, total: total)
        let urgency = PlayTableMath.urgency(secondsLeft: secondsLeft, total: total)
        let seconds = PlayTableMath.shownSeconds(secondsLeft)
        let tone = onFelt ? PlayTableTimerRing.feltTone(urgency) : PlayTableTimerRing.tone(urgency)
        let ink: Color = onFelt ? (urgency == .urgent ? PlayTablePaint.loseOnFelt : PlayTablePaint.onFelt)
                                : (urgency == .urgent ? SR.error : SR.ink)
        let track: Color = onFelt ? Color.white.opacity(0.22) : SR.inkGhost.opacity(0.35)
        let line = max(3, size * 0.11)
        return ZStack {
            Circle()
                .stroke(track, lineWidth: line)
            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(tone, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(seconds)")
                .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
        .scaleEffect(urgency == .urgent && seconds > 0 ? 1.08 : 1)
        .srAnimation(.linear(duration: 0.25), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seconds == 1 ? "1 second left" : "\(seconds) seconds left")
    }

    static func tone(_ urgency: PlayTableMath.Urgency) -> Color {
        switch urgency {
        case .calm: return SR.accent
        case .hurry: return SR.warn
        case .urgent: return SR.error
        }
    }

    static func feltTone(_ urgency: PlayTableMath.Urgency) -> Color {
        switch urgency {
        case .calm: return PlayTablePaint.gold
        case .hurry: return Color(hex: 0xFFB54A)
        case .urgent: return PlayTablePaint.loseOnFelt
        }
    }
}

/// The ring on the host's clock: four redraws a second while it is shown.
struct PlayTableClockRing: View {
    let clock: OfflineHostClock
    let until: Double
    let total: Double
    var size: CGFloat = 46
    var onFelt: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            PlayTableTimerRing(secondsLeft: until - clock.now(), total: total, size: size, onFelt: onFelt)
        }
    }
}

/// Whose turn it is: their badge, "Your turn" or "Sam is choosing", and the
/// draining clock. On my turn the strip takes my colour and glows, so the
/// change is seen out of the corner of an eye.
struct PlayTableTurnStrip<Badge: View>: View {
    let text: String
    let mine: Bool
    let clock: OfflineHostClock
    let until: Double?
    let total: Double
    let tone: Color
    let badge: Badge

    init(text: String, mine: Bool, clock: OfflineHostClock, until: Double?, total: Double,
         tone: Color = SR.accent, @ViewBuilder badge: () -> Badge) {
        self.text = text
        self.mine = mine
        self.clock = clock
        self.until = until
        self.total = total
        self.tone = tone
        self.badge = badge()
    }

    var body: some View {
        HStack(spacing: 12) {
            badge
            VStack(alignment: .leading, spacing: 1) {
                Text(mine ? "YOUR TURN" : "WAITING")
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(mine ? tone : SR.inkMuted)
                    .lineLimit(1)
                Text(text)
                    .font(SR.Text.title(18))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 8)
            if let until {
                PlayTableClockRing(clock: clock, until: until, total: total)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: 66)
        .modifier(PlayTableStripSurface(lit: mine, tone: tone))
        .srAnimation(.snappy(duration: 0.3), value: mine)
        .accessibilityElement(children: .combine)
    }
}

/// The turn strip's ground: glass while waiting, my colour's wash and rim
/// (ink type on it in both appearances) on my turn.
struct PlayTableStripSurface: ViewModifier {
    let lit: Bool
    let tone: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
        if lit {
            content
                .background(shape.fill(tone.opacity(0.16)))
                .overlay(shape.strokeBorder(tone, lineWidth: 2.5))
                .shadow(color: tone.opacity(0.35), radius: 12, x: 0, y: 5)
        } else {
            content.srGlassCard(.paper)
        }
    }
}

// MARK: - The players

/// One player at the table, as the seat rail draws them.
struct PlayTableSeat: Identifiable, Equatable {
    let id: String
    /// What the pod says: "You", or their name.
    let label: String
    /// Whose initial goes in the disc.
    let initialOf: String
    let tone: Color
    /// "5 cards", "12 pts".
    let detail: String
    /// Face-down cards to fan under the name; 0 shows none.
    var cards: Int = 0
    var turn: Bool = false
    var away: Bool = false
    /// An SF Symbol on the disc: a crown, a thumbs-up.
    var mark: String? = nil
    var markTone: Color = SR.accent
    /// The detail in amber: down to their last cards.
    var warn: Bool = false
    /// A second short line under the detail: a score.
    var score: String? = nil
    /// What VoiceOver reads for the pod.
    let spoken: String
}

/// Everyone at the table, side by side: centred when they fit, a sideways
/// scroll (that keeps whoever's turn it is in view) when they do not.
struct PlayTableSeatRail: View {
    let seats: [PlayTableSeat]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(seats) { seat in
                    PlayTableSeatPod(seat: seat)
                }
            }
            .frame(maxWidth: .infinity)
            scrolling
        }
    }

    private var turnId: String? { seats.first { $0.turn }?.id }

    private var scrolling: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(seats) { seat in
                        PlayTableSeatPod(seat: seat)
                            .id(seat.id)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onAppear {
                if let id = turnId { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: turnId) { _, id in
                guard let id else { return }
                withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

/// One player's pod: the disc (ringed in their colour on their turn), their
/// name, a fan of their cards and one short line.
struct PlayTableSeatPod: View {
    let seat: PlayTableSeat

    var body: some View {
        VStack(spacing: 4) {
            disc
            Text(seat.label)
                .font(SR.Text.label(13))
                .foregroundStyle(seat.away ? SR.inkMuted : SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if seat.cards > 0 {
                PlayTableMiniFan(count: seat.cards)
            }
            Text(seat.detail)
                .font(SR.Text.mono(12))
                .foregroundStyle(seat.warn ? SR.warn : SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let score = seat.score {
                Text(score)
                    .font(SR.Text.label(12))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: 78)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .fill(seat.turn ? seat.tone.opacity(0.14) : Color.clear)
        )
        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seat.spoken)
    }

    private var disc: some View {
        ZStack {
            if seat.turn {
                Circle()
                    .fill(seat.tone.opacity(0.22))
                    .frame(width: 56, height: 56)
                Circle()
                    .strokeBorder(seat.tone, lineWidth: 3)
                    .frame(width: 52, height: 52)
            }
            OfflineInitial(name: seat.initialOf, size: 42, tone: seat.tone)
                .opacity(seat.away ? 0.4 : 1)
            if let mark = seat.mark {
                Image(systemName: mark)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(seat.markTone))
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                    .offset(x: 19, y: -19)
            }
            if seat.away {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(SR.inkMuted))
                    .offset(x: 19, y: 19)
            }
        }
        .frame(width: 58, height: 58)
    }
}

/// A little fan of face-down cards: how many someone holds, at a glance.
struct PlayTableMiniFan: View {
    let count: Int
    var cardWidth: CGFloat = 13

    var body: some View {
        let shown = min(max(count, 0), 5)
        let shape = RoundedRectangle(cornerRadius: cardWidth * 0.2, style: .continuous)
        return ZStack {
            ForEach(0..<shown, id: \.self) { index in
                shape
                    .fill(LinearGradient(colors: [SR.accent, SR.accentDeep], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.75), lineWidth: 1))
                    .frame(width: cardWidth, height: cardWidth * OfflineCardMetrics.aspect)
                    .rotationEffect(.degrees(PlayTableMath.fanAngle(index: index, count: shown, spread: 48)),
                                    anchor: .bottom)
            }
        }
        .frame(width: cardWidth * 3.2, height: cardWidth * 1.6)
        .accessibilityHidden(true)
    }
}

// MARK: - Cards on the table

/// A pile of face-down cards as it lands on a table: each card at its own
/// small angle, so it reads as dropped. The angles are fixed per card, so the
/// pile never shuffles itself on a redraw. Five at most are drawn.
struct PlayTablePile: View {
    let count: Int
    var cardWidth: CGFloat = 60

    var body: some View {
        let shown = PlayTableMath.pileShown(count)
        let height = cardWidth * OfflineCardMetrics.aspect
        return ZStack {
            if shown == 0 {
                RoundedRectangle(cornerRadius: cardWidth * 0.12, style: .continuous)
                    .strokeBorder(PlayTablePaint.onFeltMuted, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: cardWidth, height: height)
            }
            ForEach(0..<shown, id: \.self) { index in
                OfflineCardBack(width: cardWidth)
                    .rotationEffect(.degrees(PlayTableMath.tilt(index, range: 10)))
                    .offset(x: CGFloat(PlayTableMath.tilt(index + 50, range: 4)), y: CGFloat(-index) * 1.5)
                    .transition(.playTableDeal)
            }
        }
        .frame(width: cardWidth * 1.3, height: height * 1.15)
        .srAnimation(.snappy(duration: 0.3), value: shown)
        .accessibilityHidden(true)
    }
}

/// The deck: face-down cards squared up with a little depth showing.
struct PlayTableDeck: View {
    let count: Int
    var cardWidth: CGFloat = 60

    var body: some View {
        let layers = count > 0 ? min(4, (count + 9) / 10) : 0
        let height = cardWidth * OfflineCardMetrics.aspect
        return ZStack {
            if layers == 0 {
                RoundedRectangle(cornerRadius: cardWidth * 0.12, style: .continuous)
                    .strokeBorder(PlayTablePaint.onFeltMuted, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: cardWidth, height: height)
            }
            ForEach(0..<layers, id: \.self) { index in
                OfflineCardBack(width: cardWidth)
                    .offset(x: CGFloat(index) * -1.5, y: CGFloat(index) * -2)
            }
        }
        .frame(width: cardWidth + 8, height: height + 8)
        .accessibilityHidden(true)
    }
}

extension AnyTransition {
    /// A card dealt onto the table: in from the deck's corner, small, and
    /// settling to its place.
    static var playTableDeal: AnyTransition {
        .asymmetric(
            insertion: AnyTransition.offset(x: -40, y: -50)
                .combined(with: .scale(scale: 0.7))
                .combined(with: .opacity),
            removal: .opacity
        )
    }

    /// A card turned over in place.
    static var playTableFlip: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: PlayTableFlipModifier(angle: 90), identity: PlayTableFlipModifier(angle: 0)),
            removal: .opacity
        )
    }
}

/// Turns content edge-on about its upright axis.
struct PlayTableFlipModifier: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .opacity(angle >= 89 ? 0 : 1)
    }
}

/// A side-to-side shake: "no". Bump `animatableData` by one, animated, for
/// one shake; it ends where it started.
struct PlayTableShake: GeometryEffect {
    var travel: CGFloat = 9
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let x = travel * sin(animatableData * .pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

// MARK: - Chips

/// One casino chip: a disc in its value's colour, the striped edge, the value.
struct PlayTableChip: View {
    let value: Int
    var size: CGFloat = 34

    var body: some View {
        let paint = PlayTableChip.paint(value)
        return ZStack {
            Circle()
                .fill(paint.base)
            Circle()
                .strokeBorder(paint.edge, style: StrokeStyle(lineWidth: size * 0.12, dash: [size * 0.17, size * 0.17]))
            Circle()
                .strokeBorder(paint.edge.opacity(0.85), lineWidth: max(1, size * 0.03))
                .padding(size * 0.2)
            Text("\(value)")
                .font(.system(size: size * 0.3, weight: .heavy, design: .rounded))
                .foregroundStyle(paint.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(size * 0.22)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.28), radius: 1.5, x: 0, y: 1.5)
        .accessibilityHidden(true)
    }

    static func paint(_ value: Int) -> (base: Color, edge: Color, ink: Color) {
        switch value {
        case 100: return (Color(hex: 0x23202B), Color(hex: 0xF5C451), Color(hex: 0xF5C451))
        case 25: return (Color(hex: 0x1F8A4C), Color.white, Color.white)
        case 10: return (Color(hex: 0x2558C9), Color.white, Color.white)
        case 5: return (Color(hex: 0xC8283A), Color.white, Color.white)
        default: return (Color(hex: 0xF2EFE6), Color(hex: 0x5C5868), Color(hex: 0x2A2733))
        }
    }
}

/// The chips that make `amount`, a stack per value, standing on the table.
struct PlayTableChips: View {
    let amount: Int
    var chipSize: CGFloat = 30

    var body: some View {
        let stacks = PlayTableMath.chips(for: amount, maxPerStack: 5)
        return HStack(alignment: .bottom, spacing: chipSize * 0.16) {
            ForEach(Array(stacks.enumerated()), id: \.offset) { _, stack in
                stackView(stack)
            }
        }
        .srAnimation(.snappy(duration: 0.25), value: amount)
        .accessibilityHidden(true)
    }

    private func stackView(_ stack: PlayTableMath.Chip) -> some View {
        let rise = chipSize * 0.14
        return ZStack(alignment: .bottom) {
            ForEach(0..<stack.count, id: \.self) { level in
                PlayTableChip(value: stack.value, size: chipSize)
                    .offset(y: CGFloat(-level) * rise)
            }
        }
        .frame(width: chipSize, height: chipSize + rise * CGFloat(max(0, stack.count - 1)), alignment: .bottom)
    }
}

// MARK: - Results

/// A result stamped on: "WIN +20", "BUST", "LIAR!". It lands with a thump
/// when it first appears (and simply appears under Reduce Motion).
struct PlayTableStamp: View {
    let text: String
    var tone: Color = SR.good
    var size: CGFloat = 22
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let down = landed || reduceMotion
        return Text(text.uppercased())
            .font(SR.Text.display(size))
            .tracking(1.4)
            .foregroundStyle(tone)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(shape.fill(tone.opacity(0.14)))
            .overlay(shape.strokeBorder(tone, lineWidth: 3))
            .rotationEffect(.degrees(-5))
            .scaleEffect(down ? 1 : 1.7)
            .opacity(down ? 1 : 0)
            .onAppear {
                guard !reduceMotion, !landed else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.58)) { landed = true }
            }
    }
}

/// A heading for a stretch of the table, on the felt: a small caps label in
/// the felt's light ink, and an optional figure on the right.
struct PlayTableFeltLabel: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(text.uppercased())
                .font(SR.Text.label())
                .tracking(1.3)
                .foregroundStyle(PlayTablePaint.onFeltMuted)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing.uppercased())
                    .font(SR.Text.mono())
                    .foregroundStyle(PlayTablePaint.onFelt)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// A round total badge beside a hand: "17", "BJ", "BUST".
struct PlayTableTotalBadge: View {
    let text: String
    var tone: Color = PlayTablePaint.cardInk
    var fill: Color = Color.white

    var body: some View {
        Text(text)
            .font(SR.Text.title(16))
            .monospacedDigit()
            .foregroundStyle(tone)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 10)
            .frame(minWidth: 40, minHeight: 32)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
    }
}

/// This round's score beside this phone's best — and a star when it is one.
struct PlayTableBestStrip: View {
    let score: Int
    let best: Int?

    private var isBest: Bool { score > 0 && score >= (best ?? 0) }

    /// The heading: a new best, level with it (the shell may already have
    /// counted this round), or the best to beat.
    private var heading: String {
        guard isBest else { return "Your best" }
        if let best, score == best { return "Level with your best" }
        return "A new best"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isBest ? "star.fill" : "star")
                .font(SR.Text.title(18))
                .foregroundStyle(isBest ? Color(hex: 0xE0A21C) : SR.inkMuted)
                .frame(width: 40, height: 40)
                .background(Circle().fill(SR.accent.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(heading)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                Text(best.map { "Best so far \($0) · this round \(score)" } ?? "This round \(score) — the one to beat next time")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
    }
}
