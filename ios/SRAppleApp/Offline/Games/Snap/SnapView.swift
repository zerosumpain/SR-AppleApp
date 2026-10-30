import SwiftUI
import UIKit

/// Snap on one phone: everyone's face-up piles, the clock, and a big SNAP pad.
///
/// The pad is a `TapSurface`, so a touch keeps its hardware timestamp. Each
/// time a new card comes in, `OfflineStimulus` is aimed at the host instant
/// the card was turned; that instant is already past, so the stimulus fires
/// on the very next display frame — the frame that puts the card on this
/// glass — and a snap is timed from there to the touch. The view sends that
/// figure with the card's number and waits for the host to judge.
///
/// Sizes come from the space the room screen gives it: card width from the
/// width shared by the piles in a row (at most three across) and from the
/// height left over after the pad, so five piles fit a 375pt phone.
///
/// The overhaul (2026-10-29) laid the piles on a midnight felt where each
/// new card slaps down (fully drawn from its first frame, so nobody's
/// reaction is timed against a fade), made the pad a big hot button that
/// jumps under the hand, ran the match clock as a ring, and pops a won snap
/// or a false one in big type.
struct SnapView: View {
    let context: OfflineGameContext<SnapRules>
    @StateObject private var stimulus = OfflineStimulus()
    /// The card the stimulus is aimed at.
    @State private var armedFlip = 0
    /// The card I last snapped at — one snap a card.
    @State private var sentFlip = 0
    /// My measured time for that snap, shown before the host answers.
    @State private var sentMs: Int?
    @State private var padPresses = 0
    @State private var callout = ""
    @State private var calloutTone: Color = SR.accentDeep
    @State private var calloutToken = 0
    @State private var burstToken = 0
    @Environment(\.scenePhase) private var scenePhase

    private var view: SnapRules.PlayerView { context.view }

    var body: some View {
        GeometryReader { geo in
            let padHeight = playing ? min(160, max(104, geo.size.height * 0.22)) : 0
            VStack(spacing: 12) {
                header
                NearbyPlayFelt(tone: .navy, padding: 10) {
                    SnapTable(piles: view.piles, me: context.me, lastFlipper: view.lastFlipper,
                              flip: view.flip,
                              width: geo.size.width - SR.gutter * 2 - 20,
                              height: max(120, geo.size.height - padHeight - 190))
                }
                noticeLine
                Spacer(minLength: 0)
                if playing {
                    pad.frame(height: padHeight)
                } else {
                    Text(watchingText)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("offline-snap-watching")
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .srGround(.warm)
        .overlay {
            ZStack {
                NearbyPlayBurst(token: burstToken)
                NearbyPlayCallout(text: callout, icon: "hand.raised.fill", tone: calloutTone, token: calloutToken, hold: 1.0)
            }
        }
        .onAppear { arm() }
        .onChange(of: view.flip) { _, _ in arm() }
        .onChange(of: view.phase) { _, new in
            arm()
            if new != .playing && view.champions == [context.me] { burstToken += 1 }
        }
        .onChange(of: context.clock) { _, _ in arm() }
        .onChange(of: view.notice) { _, notice in react(to: notice) }
        .onChange(of: scenePhase) { _, new in
            if new == .active { arm() }
        }
        .onDisappear { stimulus.reset() }
    }

    // MARK: - The top line

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker)
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
                Text(status)
                    .font(SR.Text.display(22))
                    .foregroundStyle(statusTone)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("offline-snap-status")
            }
            Spacer(minLength: 8)
            if view.phase == .playing {
                NearbyPlayClockRing(clock: context.clock, until: view.endsAt, total: SnapRules.matchLength,
                                    size: 50, urgentBelow: 15)
                    .accessibilityIdentifier("offline-snap-clock")
            }
        }
    }

    private var kicker: String {
        guard let row = myRow else { return "Snap · watching" }
        return "Snap · \(row.stack + row.pile) cards yours"
    }

    /// My row in the table, if I am playing this match.
    private var myRow: SnapRules.PileRow? {
        view.piles.first { $0.id == context.me }
    }

    /// I am in the match, still in, and it is running.
    private var playing: Bool {
        guard view.phase == .playing, let row = myRow else { return false }
        return !row.out && !row.away
    }

    /// I have snapped at the card on show.
    private var snappedThisCard: Bool { sentFlip == view.flip && view.flip > 0 }

    private var status: String {
        if view.phase != .playing {
            let names = view.champions.map { $0 == context.me ? "You" : context.name(of: $0) }
            if names.count == 1 { return names[0] == "You" ? "You win!" : "\(names[0]) wins!" }
            return names.isEmpty ? "Nobody has any cards left" : "A tie on cards"
        }
        guard let row = myRow else { return "You are watching" }
        if row.out { return "You are out of cards" }
        if view.flip == 0 { return "Get ready…" }
        if snappedThisCard {
            if view.mySnap == -1 { return "Too quick — that was a guess" }
            if let ms = view.mySnap ?? sentMs { return "Snap! \(ms) ms" }
            return "Snap!"
        }
        return "Snap when two cards match"
    }

    private var statusTone: Color {
        if snappedThisCard && view.mySnap == -1 { return SR.error }
        if snappedThisCard { return SR.accent }
        return SR.ink
    }

    private var watchingText: String {
        if view.phase != .playing { return "The final table is coming up." }
        if myRow?.out == true { return "You are out — watch the rest of the game." }
        return "You are watching this game."
    }

    // MARK: - What just happened

    @ViewBuilder
    private var noticeLine: some View {
        if let notice = view.notice {
            Text(sentence(notice))
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(tone(notice))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("offline-snap-notice")
        } else {
            // Holds the line's place so the pad does not jump.
            Text(" ")
                .font(SR.Text.bodyMedium(15))
                .accessibilityHidden(true)
        }
    }

    private func who(_ id: String?) -> String {
        guard let id else { return "Someone" }
        return id == context.me ? "You" : context.name(of: id)
    }

    private func sentence(_ notice: SnapRules.Notice) -> String {
        let cards = notice.cards == 1 ? "1 card" : "\(notice.cards) cards"
        switch notice.kind {
        case .won:
            let time = notice.ms.map { " in \($0) ms" } ?? ""
            return "\(who(notice.playerId)) snapped \(cards)\(time)"
        case .missed:
            return "Nobody snapped that pair"
        case .falseSnap:
            return "False snap! \(who(notice.playerId)) paid \(cards)"
        case .turnedOver:
            let name = who(notice.playerId)
            return name == "You" ? "You turned your pile over" : "\(name) turned their pile over"
        }
    }

    private func tone(_ notice: SnapRules.Notice) -> Color {
        switch notice.kind {
        case .won: return notice.playerId == context.me ? SR.good : SR.accent
        case .falseSnap: return SR.error
        case .missed, .turnedOver: return SR.inkSecondary
        }
    }

    // MARK: - The pad

    private var pad: some View {
        let shape = RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
        return ZStack {
            shape.fill(LinearGradient(colors: padColours, startPoint: .top, endPoint: .bottom))
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                                      startPoint: .top, endPoint: .center))
            shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
            HStack(spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 38, weight: .bold))
                    .rotationEffect(.degrees(-12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("SNAP!")
                        .font(SR.Text.hero(48))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(padHint)
                        .font(SR.Text.mono(13))
                        .opacity(0.9)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(Color.white)
            .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
            .padding(.horizontal, 16)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            TapSurface(label: padLabel) { touched(at: $0) }
                .accessibilityIdentifier("offline-snap-pad")
        }
        .clipShape(shape)
        .shadow(color: (padColours.last ?? Color.clear).opacity(0.4), radius: 12, x: 0, y: 6)
        .nearbyPlayBump(padPresses, scale: 0.95)
    }

    /// Fixed colours: a hot orange to slap, violet once snapped, red for a guess.
    private var padColours: [Color] {
        guard snappedThisCard else { return [Color(hex: 0xFF7A3D), Color(hex: 0xD9480F)] }
        return view.mySnap == -1 ? [Color(hex: 0xF0525A), Color(hex: 0xB3261E)] : [Color(hex: 0x8F75FF), Color(hex: 0x5B3FD9)]
    }

    private var padHint: String {
        if view.flip == 0 { return "First card coming" }
        if snappedThisCard { return "Wait for the next card" }
        return "Tap the moment two match"
    }

    private var padLabel: String {
        if view.flip == 0 { return "Snap. Wait for the first card." }
        if snappedThisCard { return "Snapped. Wait for the next card." }
        return "Snap"
    }

    // MARK: - Acting

    /// Aim the stimulus at the card on show, so a snap is timed from the
    /// frame that drew it.
    private func arm() {
        guard view.phase == .playing, view.flip > 0 else {
            stimulus.reset()
            return
        }
        if armedFlip != view.flip {
            stimulus.reset()
            armedFlip = view.flip
        }
        stimulus.arm(at: view.flipAt, clock: context.clock)
    }

    /// A touch on the pad, at its own hardware timestamp.
    private func touched(at timestamp: Double) {
        guard playing, view.flip > 0, armedFlip == view.flip, !snappedThisCard else { return }
        // Nil: the newest card has not reached the glass yet, so there is
        // nothing to have reacted to. Let the touch go.
        guard let ms = stimulus.reactionMs(touchedAt: timestamp) else { return }
        sentFlip = view.flip
        sentMs = ms
        padPresses += 1
        SRHaptic.tap()
        context.send(.snap(flip: view.flip, ms: ms))
    }

    /// A buzz and a pop for my own wins and false snaps, and a word for others'.
    private func react(to notice: SnapRules.Notice?) {
        guard let notice else { return }
        let mine = notice.playerId == context.me
        switch notice.kind {
        case .won:
            if mine { SRHaptic.ok() }
            callout = mine ? "Snap! +\(notice.cards)" : "\(who(notice.playerId)) snapped!"
            calloutTone = mine ? SR.good : SR.accentDeep
            calloutToken += 1
        case .falseSnap:
            if mine { SRHaptic.bad() }
            callout = mine ? "False snap! −\(notice.cards)" : "False snap!"
            calloutTone = SR.error
            calloutToken += 1
        case .missed, .turnedOver:
            break
        }
    }
}

/// Everyone's face-up pile, three across at most, each card as wide as the
/// width and height allow.
struct SnapTable: View {
    let piles: [SnapRules.PileRow]
    let me: String
    let lastFlipper: String?
    let flip: Int
    /// The width the table may use.
    let width: CGFloat
    /// The most height the table may use.
    let height: CGFloat

    private let gap: CGFloat = 12
    /// Name line above and count line below a card, with their spacing.
    private let captions: CGFloat = 46

    private var columns: Int {
        switch piles.count {
        case 0, 1: return 1
        case 2, 4: return 2
        default: return 3
        }
    }

    /// Seat indexes, row by row.
    private var rows: [[Int]] {
        stride(from: 0, to: piles.count, by: columns).map { start in
            Array(start..<min(start + columns, piles.count))
        }
    }

    private var cardWidth: CGFloat {
        let cols = CGFloat(columns)
        let byWidth = (max(width, 60) - gap * (cols - 1)) / cols
        let rowCount = CGFloat(max(rows.count, 1))
        let byHeight = ((height - gap * (rowCount - 1)) / rowCount - captions) / OfflineCardMetrics.aspect
        return max(36, min(110, byWidth, byHeight))
    }

    var body: some View {
        let side = cardWidth
        VStack(spacing: gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: gap) {
                    ForEach(row, id: \.self) { index in
                        SnapPileTile(row: piles[index], seat: index, me: me, width: side,
                                     fresh: piles[index].id == lastFlipper && flip > 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-snap-table")
    }
}

/// One player's pile: their name, the face-up top (or an empty slot), and
/// how many cards they hold face down and face up. A new top slaps down.
struct SnapPileTile: View {
    let row: SnapRules.PileRow
    var seat: Int = 0
    let me: String
    let width: CGFloat
    /// This pile took the newest card.
    let fresh: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var name: String { row.id == me ? "You" : row.name }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(row.isTurn ? NearbyPlayFeltInk.gold : OfflineSeatColour.of(seat))
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(SR.Text.label(12))
                    .foregroundStyle(row.isTurn ? NearbyPlayFeltInk.gold : NearbyPlayFeltInk.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: width)

            ZStack {
                // The face-down stack under the pile, a card's edge per few cards.
                if row.stack > 0 {
                    OfflineCardBack(width: width)
                        .offset(x: 3, y: 3)
                        .opacity(0.8)
                }
                if let top = row.top {
                    OfflineCardFace(card: top, width: width)
                        .id(top.id + "-\(row.pile)")
                        .transition(reduceMotion ? AnyTransition.identity : SnapPileTile.slap)
                } else {
                    shape
                        .strokeBorder(NearbyPlayFeltInk.faint, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: width, height: width * OfflineCardMetrics.aspect)
                }
            }
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: row.top)
            .overlay {
                if fresh {
                    shape.stroke(NearbyPlayFeltInk.gold, lineWidth: 3)
                }
            }

            Text(counts)
                .font(SR.Text.mono(12))
                .foregroundStyle(NearbyPlayFeltInk.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: width)
        }
        .opacity(row.out || row.away ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("offline-snap-pile-\(row.id)")
    }

    /// A new top lands from a little above and a little larger — drawn in
    /// full from its first frame — and the old one goes at once.
    static var slap: AnyTransition {
        AnyTransition.asymmetric(insertion: AnyTransition.scale(scale: 1.18).combined(with: AnyTransition.offset(y: -10)),
                                 removal: AnyTransition.identity)
    }

    private var counts: String {
        if row.away { return "left" }
        if row.out { return "out" }
        return "\(row.stack) down · \(row.pile) up"
    }

    private var spoken: String {
        var parts = [name]
        if let top = row.top { parts.append("\(top.name) on top") } else { parts.append("no face-up card") }
        parts.append("\(row.stack) face down, \(row.pile) face up")
        if row.isTurn { parts.append("turns the next card") }
        if row.out { parts.append("out") }
        if row.away { parts.append("left the game") }
        return parts.joined(separator: ", ")
    }
}
