import SwiftUI
import UIKit

// The furniture every offline game's view may use, so twenty games look like
// one app: playing cards and a hand that fits the screen, a countdown on the
// host's clock, the table of standings, and the timer that shows a reaction
// game's stimulus at the right instant and measures the tap against it.
//
// Every size here comes from a width the caller passes or from the space
// available — never from content — so nothing runs off a 375pt phone.

// MARK: - Cards

enum OfflineCardMetrics {
    /// Height over width of a playing card (63 × 88 mm).
    static let aspect: CGFloat = 1.4
}

/// One playing card, face up, `width` points wide.
struct OfflineCardFace: View {
    let card: OfflineCard
    var width: CGFloat = 56
    /// Drawn with an accent rim (a card picked to play).
    var selected = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(SR.surface)
            VStack(alignment: .leading, spacing: -width * 0.04) {
                Text(card.rankText)
                    .font(.system(size: width * 0.3, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(card.suit.symbol)
                    .font(.system(size: width * 0.24))
            }
            .padding(.leading, width * 0.09)
            .padding(.top, width * 0.07)
            Text(card.suit.symbol)
                .font(.system(size: width * 0.46))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, width * 0.2)
        }
        .foregroundStyle(card.isRed ? SR.error : SR.ink)
        .frame(width: width, height: width * OfflineCardMetrics.aspect)
        .overlay { shape.stroke(selected ? SR.accent : SR.line, lineWidth: selected ? 2.5 : 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.name)
    }
}

/// A card face down: someone else's hand, the stock.
struct OfflineCardBack: View {
    var width: CGFloat = 56

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
        shape
            .fill(SR.accent)
            .overlay {
                shape.inset(by: width * 0.08)
                    .stroke(SR.paper.opacity(0.55), lineWidth: max(1, width * 0.03))
            }
            .overlay {
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: width * 0.3))
                    .foregroundStyle(SR.paper.opacity(0.7))
            }
            .frame(width: width, height: width * OfflineCardMetrics.aspect)
            .accessibilityLabel("Face-down card")
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
                    let raised = selected.contains(card.id)
                    let canTap = onTap != nil && (playable?.contains(card.id) ?? true)
                    Button {
                        SRHaptic.select()
                        onTap?(card)
                    } label: {
                        OfflineCardFace(card: card, width: width, selected: raised)
                            .opacity(onTap == nil || canTap ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canTap)
                    .offset(x: CGFloat(index) * step, y: raised ? 0 : lift)
                }
            }
            // Centred when the hand is narrower than the space.
            .padding(.leading, max(0, (geo.size.width - used) / 2))
        }
        .frame(height: cardWidth * OfflineCardMetrics.aspect + lift)
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
            Text("\(clock.secondsLeft(until: until))")
                .font(font)
                .foregroundStyle(tone)
                .monospacedDigit()
                .accessibilityLabel("\(clock.secondsLeft(until: until)) seconds left")
        }
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

/// The table after a match: rank, name, the figure, one detail line.
struct OfflineStandingsCard: View {
    let standings: [OfflineStanding]
    let me: String

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(standings.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack(alignment: .top, spacing: 12) {
                    Text("\(row.rank)")
                        .font(SR.Text.display(24))
                        .foregroundStyle(row.rank == 1 ? SR.accent : SR.inkGhost)
                        .frame(width: 30, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.name + (row.playerId == me ? " (you)" : ""))
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
                        .font(SR.Text.display(22))
                        .foregroundStyle(SR.ink)
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
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
            .foregroundStyle(SR.paper)
            .frame(width: size, height: size)
            .background(Circle().fill(tone))
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
