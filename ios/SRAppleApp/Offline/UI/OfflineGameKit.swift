import SwiftUI
import UIKit

// The furniture every offline game's view may use, so twenty games look like
// one app: playing cards and a hand that fits the screen, a countdown on the
// host's clock, the table of standings, and the timer that shows a reaction
// game's stimulus at the right instant and measures the tap against it.
//
// The games overhaul (2026-10-29) added the shell's own art and feedback
// here too, for any game to borrow: a game's badge (`OfflineGameBadge`), the
// big thumb-sized button (`OfflineKitButton`), "whose turn" (`OfflineTurnBanner`),
// medals (`OfflineMedal`), wrapping tags (`OfflineTagRow`) and a short,
// finite shower of confetti for a win (`OfflineConfettiView`).
//
// Every size here comes from a width the caller passes or from the space
// available — never from content — so nothing runs off a 375pt phone.

// MARK: - Cards

enum OfflineCardMetrics {
    /// Height over width of a playing card (63 × 88 mm).
    static let aspect: CGFloat = 1.4
}

/// The colours of a real deck: a white card and black or red ink in both
/// appearances, the way a card on a dark table is still white.
enum OfflineCardPaint {
    static let paper = Color(hex: 0xFFFDF8)
    static let black = Color(hex: 0x1F1D2B)
    static let red = Color(hex: 0xCF2236)
    static let rim = Color.black.opacity(0.16)
}

/// One playing card, face up, `width` points wide.
struct OfflineCardFace: View {
    let card: OfflineCard
    var width: CGFloat = 56
    /// Drawn with an accent rim (a card picked to play).
    var selected = false

    private var height: CGFloat { width * OfflineCardMetrics.aspect }
    private var ink: Color { card.isRed ? OfflineCardPaint.red : OfflineCardPaint.black }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
        ZStack {
            shape.fill(OfflineCardPaint.paper)
            centre
            index
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if width >= 48 {
                index
                    .rotationEffect(.degrees(180))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay { shape.strokeBorder(rimColour, lineWidth: selected ? 2.5 : 0.75) }
        .shadow(color: shadowColour, radius: shadowRadius, x: 0, y: width * 0.03)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.name)
    }

    private var rimColour: Color { selected ? SR.accent : OfflineCardPaint.rim }
    private var shadowColour: Color { selected ? SR.accent.opacity(0.45) : Color.black.opacity(0.16) }
    private var shadowRadius: CGFloat { selected ? width * 0.12 : width * 0.04 }

    /// The rank over its suit, in the corner.
    private var index: some View {
        VStack(spacing: -width * 0.04) {
            Text(card.rankText)
                .font(.system(size: width * 0.28, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(card.suit.symbol)
                .font(.system(size: width * 0.2))
        }
        .foregroundStyle(ink)
        .frame(width: width * 0.3)
        .padding(.leading, width * 0.04)
        .padding(.top, width * 0.06)
        .padding(.trailing, width * 0.04)
        .padding(.bottom, width * 0.06)
    }

    /// Pips for a number card big enough to show them, a framed letter for a
    /// court card, one big suit otherwise.
    @ViewBuilder
    private var centre: some View {
        if card.isFace {
            court
        } else if card.rank >= 2, card.rank <= 10, width >= 60 {
            pips
        } else {
            Text(card.suit.symbol)
                .font(.system(size: width * (card.rank == 1 ? 0.6 : 0.46)))
                .foregroundStyle(ink)
                .padding(.top, width * 0.06)
        }
    }

    private var court: some View {
        let panel = RoundedRectangle(cornerRadius: width * 0.06, style: .continuous)
        return ZStack {
            panel.fill(ink.opacity(0.08))
            panel.strokeBorder(ink.opacity(0.35), lineWidth: max(0.75, width * 0.015))
            VStack(spacing: 0) {
                Text(card.rankText)
                    .font(.system(size: width * 0.32, weight: .heavy, design: .serif))
                Text(card.suit.symbol)
                    .font(.system(size: width * 0.22))
            }
            .foregroundStyle(ink)
        }
        .frame(width: width * 0.44, height: height * 0.52)
    }

    private var pips: some View {
        let spots = OfflineCardFace.pipSpots(card.rank)
        // The pip columns sit inside the corner indices (which take the
        // outer 0.04–0.34 of the width at each side), so a pip never sits on
        // the rank letter.
        let left = width * 0.36, across = width * 0.28
        let top = height * 0.2, down = height * 0.6
        return ZStack {
            ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
                Text(card.suit.symbol)
                    .font(.system(size: width * 0.17))
                    .foregroundStyle(ink)
                    .rotationEffect(.degrees(spot.y > 0.5 ? 180 : 0))
                    .position(x: left + across * spot.x, y: top + down * spot.y)
            }
        }
        .frame(width: width, height: height)
    }

    /// Where a number card's pips sit, as fractions of the pip area: the
    /// layout every deck uses.
    static func pipSpots(_ rank: Int) -> [CGPoint] {
        let third: CGFloat = 1.0 / 3.0
        let pairs: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)]
        let middles: [CGPoint] = [CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)]
        switch rank {
        case 2: return [CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)]
        case 3: return [CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 1)]
        case 4: return pairs
        case 5: return pairs + [CGPoint(x: 0.5, y: 0.5)]
        case 6: return pairs + middles
        case 7: return pairs + middles + [CGPoint(x: 0.5, y: 0.25)]
        case 8: return pairs + middles + [CGPoint(x: 0.5, y: 0.25), CGPoint(x: 0.5, y: 0.75)]
        case 9:
            return pairs + [CGPoint(x: 0, y: third), CGPoint(x: 1, y: third),
                            CGPoint(x: 0, y: 2 * third), CGPoint(x: 1, y: 2 * third), CGPoint(x: 0.5, y: 0.5)]
        case 10:
            return pairs + [CGPoint(x: 0, y: third), CGPoint(x: 1, y: third),
                            CGPoint(x: 0, y: 2 * third), CGPoint(x: 1, y: 2 * third),
                            CGPoint(x: 0.5, y: third * 0.5), CGPoint(x: 0.5, y: 1 - third * 0.5)]
        default: return []
        }
    }
}

/// A card face down: someone else's hand, the stock.
struct OfflineCardBack: View {
    var width: CGFloat = 56

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
        let inner = width * 0.08
        ZStack {
            shape.fill(LinearGradient(colors: [SR.accent, SR.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { context, size in
                OfflineCardBack.lattice(in: &context, size: size, step: max(4, size.width / 5))
            }
            .padding(inner)
            .clipShape(RoundedRectangle(cornerRadius: width * 0.07, style: .continuous))
            shape.inset(by: inner)
                .stroke(Color.white.opacity(0.55), lineWidth: max(1, width * 0.03))
            Circle()
                .fill(SR.accentDeep)
                .frame(width: width * 0.42, height: width * 0.42)
                .overlay { Circle().stroke(Color.white.opacity(0.6), lineWidth: max(1, width * 0.025)) }
            Image(systemName: "suit.spade.fill")
                .font(.system(size: width * 0.22))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .frame(width: width, height: width * OfflineCardMetrics.aspect)
        .shadow(color: Color.black.opacity(0.16), radius: width * 0.04, x: 0, y: width * 0.03)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Face-down card")
    }

    /// The diamond lattice of a card back.
    static func lattice(in context: inout GraphicsContext, size: CGSize, step: CGFloat) {
        var path = Path()
        var x: CGFloat = -size.height
        while x < size.width + size.height {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x + size.height, y: size.height))
            path.move(to: CGPoint(x: x + size.height, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        context.stroke(path, with: .color(Color.white.opacity(0.2)), lineWidth: max(0.5, size.width * 0.025))
    }
}

/// A row of cards that always fits the width it is given: the cards overlap
/// more as the hand grows, rather than running off the edge. Selected cards
/// sit raised.
struct OfflineHand: View {
    let cards: [OfflineCard]
    /// The widest a card may be; it shrinks if even one card would not fit.
    var cardWidth: CGFloat = 64
    /// Ids of raised cards.
    var selected: Set<String> = []
    /// Cards that may be tapped, by id; nil means all of them (when `onTap` is set).
    var playable: Set<String>? = nil
    var onTap: ((OfflineCard) -> Void)? = nil

    private var lift: CGFloat { cardWidth * 0.25 }

    var body: some View {
        GeometryReader { geo in
            let width = min(cardWidth, geo.size.width)
            let count = cards.count
            let natural = width + 6
            let step = count > 1 ? min(natural, (geo.size.width - width) / CGFloat(count - 1)) : 0
            let used = count > 0 ? width + step * CGFloat(count - 1) : 0
            ZStack(alignment: .topLeading) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    handCard(card, index: index, width: width, step: step)
                }
            }
            // Centred when the hand is narrower than the space.
            .padding(.leading, max(0, (geo.size.width - used) / 2))
            .srAnimation(.snappy(duration: 0.22), value: selected)
        }
        .frame(height: cardWidth * OfflineCardMetrics.aspect + lift)
    }

    /// A hand only to look at (no `onTap`) is plain cards, not disabled
    /// buttons — VoiceOver would call every one of them "dimmed".
    @ViewBuilder
    private func handCard(_ card: OfflineCard, index: Int, width: CGFloat, step: CGFloat) -> some View {
        if onTap == nil {
            OfflineCardFace(card: card, width: width, selected: selected.contains(card.id))
                .offset(x: CGFloat(index) * step, y: selected.contains(card.id) ? 0 : lift)
                .zIndex(Double(index))
                .accessibilityAddTraits(selected.contains(card.id) ? .isSelected : [])
        } else {
            tappableCard(card, index: index, width: width, step: step)
        }
    }

    private func tappableCard(_ card: OfflineCard, index: Int, width: CGFloat, step: CGFloat) -> some View {
        let raised = selected.contains(card.id)
        let canTap = onTap != nil && (playable?.contains(card.id) ?? true)
        let hint: String = canTap ? (raised ? "Selected. Tap to put it back." : "Tap to pick it.") : ""
        return Button {
            SRHaptic.select()
            onTap?(card)
        } label: {
            OfflineCardFace(card: card, width: width, selected: raised)
                // A card that cannot be played now dims; one that can sits
                // bright, so the playable ones read at a glance.
                .opacity(onTap == nil || canTap ? 1 : 0.45)
                .saturation(onTap == nil || canTap ? 1 : 0.4)
        }
        .buttonStyle(SRPressStyle())
        .disabled(!canTap)
        .offset(x: CGFloat(index) * step, y: raised ? 0 : lift)
        .zIndex(Double(index))
        .accessibilityAddTraits(raised ? .isSelected : [])
        .accessibilityHint(hint)
    }
}

// MARK: - Time

/// Whole seconds until a host-clock instant, ticking down.
struct OfflineCountdown: View {
    let clock: OfflineHostClock
    /// Host-clock seconds.
    let until: Double
    var font: Font = SR.Text.figure()
    var tone: Color = SR.ink

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            OfflineCountdownFace(seconds: clock.secondsLeft(until: until), font: font, tone: tone)
        }
    }
}

/// The number itself: it rolls down a digit at a time, and in the last three
/// seconds it lifts a touch so the end is felt coming.
private struct OfflineCountdownFace: View {
    let seconds: Int
    let font: Font
    let tone: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let urgent = OfflineShell.isUrgent(secondsLeft: seconds)
        Text("\(seconds)")
            .font(font)
            .foregroundStyle(tone)
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            .scaleEffect(urgent && !reduceMotion ? 1.08 : 1)
            .animation(reduceMotion ? nil : Animation.snappy(duration: 0.25), value: seconds)
            .accessibilityLabel("\(seconds) seconds left")
    }
}

/// Shows a reaction game's stimulus at a host-clock instant, and remembers
/// the LOCAL time of the display frame that first showed it, so a tap can be
/// measured from what the player actually saw.
///
/// Driven by a display link (`FrameTicker`): each frame knows when it will
/// reach the glass (`targetTimestamp`), and the first frame due at or after
/// the stimulus is the one that turns. Touches from `TapSurface` carry
/// `UITouch.timestamp` on the same clock, so `reactionMs` never crosses clocks.
@MainActor
final class OfflineStimulus: ObservableObject {
    /// The stimulus is on screen.
    @Published private(set) var shown = false
    /// Local uptime of the frame that first showed it.
    private(set) var shownAt: Double?
    private var target: Double?
    private var ticker: FrameTicker?

    /// Show the stimulus at `hostTime`. Calling again with a new time (a
    /// refined clock, a new round) re-aims it; once shown, only a new round's
    /// `reset()` clears it.
    func arm(at hostTime: Double, clock: OfflineHostClock) {
        guard !shown else { return }
        target = clock.local(fromHost: hostTime)
        guard ticker == nil else { return }
        let ticker = FrameTicker { [weak self] frameTime in
            guard let self else { return false }
            return self.frame(frameTime)
        }
        self.ticker = ticker
        ticker.start()
    }

    /// Back to waiting, for the next round.
    func reset() {
        ticker?.stop()
        ticker = nil
        target = nil
        shownAt = nil
        if shown { shown = false }
    }

    /// Milliseconds from the stimulus shown to a touch at `touchTime` (local
    /// uptime — `UITouch.timestamp`). Nil means the touch came first: a false start.
    func reactionMs(touchedAt touchTime: Double) -> Int? {
        OfflineReaction.ms(shownAt: shownAt, touchedAt: touchTime)
    }

    /// One frame. False stops the display link — and a stopped ticker is
    /// let go, so the next `arm` starts a fresh one rather than waiting on it.
    private func frame(_ frameTime: Double) -> Bool {
        guard let target else {
            ticker = nil
            return false
        }
        if frameTime >= target {
            shownAt = frameTime
            shown = true
            ticker = nil
            return false
        }
        return true
    }
}

// MARK: - People

/// The table after a match: a medal for the top three, the name, the figure,
/// one detail line — and this phone's row lit, so you find yourself first.
struct OfflineStandingsCard: View {
    let standings: [OfflineStanding]
    let me: String

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(standings.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(SR.divider).padding(.horizontal, 8) }
                standingRow(row)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .srGlassCard(.paper)
    }

    private func standingRow(_ row: OfflineStanding) -> some View {
        let mine = row.playerId == me
        return HStack(alignment: .center, spacing: 12) {
            OfflineMedal(rank: row.rank, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name + (mine ? " (you)" : ""))
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                if let detail = row.detail {
                    Text(detail)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text("\(row.score)")
                .font(SR.Text.figure(24))
                .foregroundStyle(row.rank == 1 ? SR.accent : SR.ink)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: SR.tapTarget)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .fill(mine ? SR.accent.opacity(0.12) : Color.clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(row, mine: mine))
    }

    private func spoken(_ row: OfflineStanding, mine: Bool) -> String {
        var parts: [String] = [OfflineShell.ordinal(row.rank), mine ? "\(row.name), you" : row.name, "\(row.score)"]
        if let detail = row.detail { parts.append(detail) }
        return parts.joined(separator: ", ")
    }
}

/// A person's initial in a coloured disc — the lobby and scoreboards.
struct OfflineInitial: View {
    let name: String
    var size: CGFloat = 32
    var tone: Color = SR.accent

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(LinearGradient(colors: [tone.opacity(0.85), tone], startPoint: .top, endPoint: .bottom))
            )
            .overlay { Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: max(1, size * 0.04)) }
            .accessibilityHidden(true)
    }
}

/// The colour for a seat (0-based), so a player keeps one colour all game.
enum OfflineSeatColour {
    static func of(_ seat: Int) -> Color {
        let all = SR.PersonHue.all
        guard !all.isEmpty else { return SR.accent }
        return all[((seat % all.count) + all.count) % all.count]
    }
}

// MARK: - Medals

/// Gold, silver and bronze for the top three; a plain disc below them.
struct OfflineMedal: View {
    let rank: Int
    var size: CGFloat = 34

    var body: some View {
        let colours = OfflineMedal.colours(rank)
        ZStack {
            Circle().fill(LinearGradient(colors: [colours.glow, colours.base], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(Color.white.opacity(rank <= 3 ? 0.55 : 0.2), lineWidth: max(1, size * 0.06))
            Text("\(rank)")
                .font(.system(size: size * 0.46, weight: .heavy, design: .rounded))
                .foregroundStyle(colours.ink)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
        .shadow(color: rank <= 3 ? colours.base.opacity(0.35) : Color.clear, radius: size * 0.12, x: 0, y: size * 0.05)
        .accessibilityHidden(true)
    }

    static func colours(_ rank: Int) -> (glow: Color, base: Color, ink: Color) {
        switch rank {
        case 1: return (Color(hex: 0xFFE07A), Color(hex: 0xE0A21C), Color(hex: 0x4A3203))
        case 2: return (Color(hex: 0xF1F3F8), Color(hex: 0xA9B1C2), Color(hex: 0x2C3140))
        case 3: return (Color(hex: 0xF3B98A), Color(hex: 0xB86B37), Color(hex: 0x3D1E08))
        default: return (SR.inkGhost.opacity(0.35), SR.inkGhost.opacity(0.55), SR.ink)
        }
    }
}

// MARK: - A game's art

/// The hue a game's shelf is painted in: cards, reactions and skill games
/// each read as their own colour before their names are read.
enum OfflineGameArt {
    static func hue(_ category: OfflineGameCategory) -> SR.Hue {
        switch category {
        case .card: return SR.Hue.games
        case .reaction: return SR.Hue.alerts
        case .skill: return SR.Hue.trips
        }
    }

    /// The motif under a badge's symbol: fanned cards, ripples, a grid.
    static func motif(_ category: OfflineGameCategory, in context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let white = Color.white
        switch category {
        case .card:
            for (index, turn) in [-18.0, 4.0].enumerated() {
                var ctx = context
                ctx.translateBy(x: w * (0.24 + 0.1 * CGFloat(index)), y: h * 0.62)
                ctx.rotate(by: .degrees(turn))
                let rect = CGRect(x: -w * 0.18, y: -h * 0.26, width: w * 0.36, height: h * 0.5)
                ctx.fill(Path(roundedRect: rect, cornerRadius: w * 0.05), with: .color(white.opacity(0.16 + 0.06 * Double(index))))
            }
        case .reaction:
            let centre = CGPoint(x: w * 0.82, y: h * 0.82)
            for ring in 1...4 {
                let r = w * 0.18 * CGFloat(ring)
                let rect = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(white.opacity(0.24 - 0.04 * Double(ring))),
                               lineWidth: max(1, w * 0.035))
            }
        case .skill:
            let step = w / 5
            var dots = Path()
            for row in 1..<5 {
                for col in 1..<5 where (row + col) % 2 == 0 {
                    let d = w * 0.06
                    dots.addEllipse(in: CGRect(x: step * CGFloat(col) - d / 2, y: step * CGFloat(row) - d / 2, width: d, height: d))
                }
            }
            context.fill(dots, with: .color(white.opacity(0.22)))
        }
    }
}

/// A game's badge: its symbol on a squircle of its shelf's hue, over a drawn
/// motif and a soft highlight. Art, so it is hidden from VoiceOver.
struct OfflineGameBadge: View {
    let info: OfflineGameInfo
    var size: CGFloat = 56

    var body: some View {
        let hue = OfflineGameArt.hue(info.category)
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        let category = info.category
        ZStack {
            shape.fill(hue.gradient)
            Canvas { context, canvasSize in
                OfflineGameArt.motif(category, in: &context, size: canvasSize)
            }
            .clipShape(shape)
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0)],
                                      startPoint: .top, endPoint: .center))
            Image(systemName: info.symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(hue.onFill)
                .shadow(color: Color.black.opacity(0.18), radius: size * 0.04, x: 0, y: size * 0.02)
        }
        .frame(width: size, height: size)
        .shadow(color: hue.base.opacity(0.3), radius: size * 0.12, x: 0, y: size * 0.06)
        .accessibilityHidden(true)
    }
}

// MARK: - Buttons and labels

enum OfflineKitMetrics {
    /// The tallest a game's action button is, at least: the owner asked for
    /// bigger buttons in games, and a child's thumb wants more than 44.
    static let bigButton: CGFloat = 56
    /// The label's own floor inside a large glass button, which brings the
    /// whole button to `bigButton` or more.
    static let bigLabel: CGFloat = 36
}

/// What a button says to the hand when it is pressed.
enum OfflineKitHaptic {
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

/// A big, full-width game button: the app's glass, a thumb's size.
struct OfflineKitButton: View {
    let title: String
    var icon: String? = nil
    var prominent: Bool = true
    var haptic: OfflineKitHaptic = .tap
    /// The accessibility identifier, when UI tests find it.
    var id: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            haptic.play()
            action()
        } label: {
            SRButtonLabel(title: title, icon: icon, fill: true)
                .frame(minHeight: OfflineKitMetrics.bigLabel)
        }
        .srButton(prominent ? .prominent : .regular)
        .controlSize(.large)
        .modifier(OfflineOptionalIdentifier(id: id))
    }
}

/// `.accessibilityIdentifier` only when there is one to set.
struct OfflineOptionalIdentifier: ViewModifier {
    let id: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let id {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}

/// "Your turn" or "Sam's turn": a capsule that fills with the accent and
/// nudges the hand when it becomes this phone's go.
struct OfflineTurnBanner: View {
    let text: String
    /// It is this phone's turn.
    let mine: Bool
    /// The colour of the player whose turn it is.
    var tone: Color = SR.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: mine ? "hand.point.up.left.fill" : "hourglass")
                .font(SR.Text.title(15))
                .symbolEffect(.pulse, options: .repeating, isActive: mine && !reduceMotion)
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.title(16))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(mine ? Color.white : SR.ink)
        .padding(.horizontal, 16)
        .frame(minHeight: SR.tapTarget)
        .background(
            Capsule().fill(mine ? AnyShapeStyle(tone) : AnyShapeStyle(tone.opacity(0.14)))
        )
        .overlay { Capsule().strokeBorder(tone.opacity(mine ? 0 : 0.45), lineWidth: 1) }
        .srAnimation(.snappy(duration: 0.25), value: mine)
        .onChange(of: mine) { _, now in
            if now { SRHaptic.select() }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Short tags that wrap onto a second line rather than run off a small phone.
struct OfflineTagRow: View {
    let tags: [String]
    var tone: Color = SR.accent

    var body: some View {
        OfflineFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                Text(tag.uppercased())
                    .font(SR.Text.label())
                    .tracking(0.9)
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tone.opacity(0.12)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tags.joined(separator: ", "))
    }
}

/// Lays its children left to right, wrapping when the line is full.
struct OfflineFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, min(x - spacing, width))
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += line + lineSpacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

// MARK: - Celebration

/// A short shower of confetti over a win. Finite: it draws for
/// `OfflineConfettiField.duration` seconds on one animation timeline, then
/// the timeline goes and nothing is drawn — no idle frames afterwards. Never
/// under Reduce Motion, and it never takes a touch.
struct OfflineConfettiView: View {
    var seed: UInt64 = 1
    var count: Int = 90
    @State private var started = Date()
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion || finished {
                Color.clear
            } else {
                shower
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var shower: some View {
        let pieces = OfflineConfettiField.pieces(count: count, seed: seed, colours: 6)
        let colours: [Color] = OfflineConfettiView.palette()
        let start = started
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: finished)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSince(start)
                let width = Double(size.width), height = Double(size.height)
                for piece in pieces {
                    let spot = OfflineConfettiField.spot(piece, at: time, width: width, height: height)
                    guard spot.visible else { continue }
                    var ctx = context
                    ctx.translateBy(x: CGFloat(spot.x), y: CGFloat(spot.y))
                    ctx.rotate(by: .radians(spot.angle))
                    let side = CGFloat(piece.size)
                    let rect = CGRect(x: -side / 2, y: -side * 0.3, width: side, height: side * 0.6)
                    ctx.fill(Path(rect), with: .color(colours[piece.colour % colours.count]))
                }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: UInt64(OfflineConfettiField.duration * 1_000_000_000))
            finished = true
        }
    }

    /// The family's colours and the accent: six, to match the field.
    static func palette() -> [Color] {
        var colours = Array(SR.PersonHue.all.prefix(5))
        colours.append(SR.accent)
        while colours.count < 6 { colours.append(SR.accent) }
        return colours
    }
}
