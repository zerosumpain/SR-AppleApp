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
struct SnapView: View {
    let context: OfflineGameContext<SnapRules>
    @StateObject private var stimulus = OfflineStimulus()
    /// The card the stimulus is aimed at.
    @State private var armedFlip = 0
    /// The card I last snapped at — one snap a card.
    @State private var sentFlip = 0
    /// My measured time for that snap, shown before the host answers.
    @State private var sentMs: Int?

    private var view: SnapRules.PlayerView { context.view }

    var body: some View {
        GeometryReader { geo in
            let padHeight = playing ? min(150, max(96, geo.size.height * 0.2)) : 0
            VStack(spacing: 12) {
                header
                SnapTable(piles: view.piles, me: context.me, lastFlipper: view.lastFlipper,
                          flip: view.flip,
                          width: geo.size.width - SR.gutter * 2,
                          height: max(120, geo.size.height - padHeight - 150))
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
        .onAppear { arm() }
        .onChange(of: view.flip) { _, _ in arm() }
        .onChange(of: view.phase) { _, _ in arm() }
        .onChange(of: context.clock) { _, _ in arm() }
        .onChange(of: view.notice) { _, notice in react(to: notice) }
        .onDisappear { stimulus.reset() }
    }

    // MARK: - The top line

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(status)
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("offline-snap-status")
            Spacer(minLength: 8)
            if view.phase == .playing {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let left = context.clock.secondsLeft(until: view.endsAt)
                    Text(String(format: "%d:%02d", left / 60, left % 60))
                        .font(SR.Text.mono(15))
                        .foregroundStyle(left <= 15 ? SR.error : SR.inkSecondary)
                        .monospacedDigit()
                        .fixedSize()
                        .accessibilityLabel("\(left) seconds left")
                }
                .accessibilityIdentifier("offline-snap-clock")
            }
        }
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
            shape.fill(padFill)
            VStack(spacing: 4) {
                Text("SNAP!")
                    .font(SR.Text.hero(48))
                    .foregroundStyle(SR.paper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(padHint)
                    .font(SR.Text.mono(13))
                    .foregroundStyle(SR.paper.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 16)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            TapSurface(label: padLabel) { touched(at: $0) }
                .accessibilityIdentifier("offline-snap-pad")
        }
        .clipShape(shape)
    }

    private var padFill: Color {
        guard snappedThisCard else { return SR.ink }
        return view.mySnap == -1 ? SR.error : SR.accent
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
        SRHaptic.tap()
        context.send(.snap(flip: view.flip, ms: ms))
    }

    /// A buzz for my own wins and false snaps.
    private func react(to notice: SnapRules.Notice?) {
        guard let notice, notice.playerId == context.me else { return }
        switch notice.kind {
        case .won: SRHaptic.ok()
        case .falseSnap: SRHaptic.bad()
        case .missed, .turnedOver: break
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
    private let captions: CGFloat = 44

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
                        SnapPileTile(row: piles[index], me: me, width: side,
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
/// how many cards they hold face down and face up.
struct SnapPileTile: View {
    let row: SnapRules.PileRow
    let me: String
    let width: CGFloat
    /// This pile took the newest card.
    let fresh: Bool

    private var name: String { row.id == me ? "You" : row.name }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if row.isTurn {
                    Circle()
                        .fill(SR.accent)
                        .frame(width: 6, height: 6)
                }
                Text(name)
                    .font(SR.Text.label(12))
                    .foregroundStyle(row.isTurn ? SR.accent : SR.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: width)

            Group {
                if let top = row.top {
                    OfflineCardFace(card: top, width: width)
                } else {
                    shape
                        .strokeBorder(SR.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: width, height: width * OfflineCardMetrics.aspect)
                }
            }
            .overlay {
                if fresh {
                    shape.stroke(SR.accent, lineWidth: 3)
                }
            }

            Text(counts)
                .font(SR.Text.mono(11))
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: width)
        }
        .opacity(row.out || row.away ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("offline-snap-pile-\(row.id)")
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
