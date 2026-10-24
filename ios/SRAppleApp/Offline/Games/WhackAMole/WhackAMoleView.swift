import SwiftUI
import UIKit

/// Whack-a-Mole on one phone: the field of nine holes, the clock, everyone's
/// points, and "Time's up" at the end.
///
/// Every hole is its own `TapSurface`, so a touch keeps its hardware
/// timestamp. Moles arrive in the host's view a moment before they are due;
/// `WhackAMoleField` runs a display link that pops each one up on the first
/// frame due at or after its host-clock `upAt`, remembers that frame's local
/// time, and drops it at `downAt`. A whack is measured from that frame to the
/// touch, here, and only the milliseconds are sent — the host gives a mole to
/// the lowest time, so the slower link never loses a race it won.
struct WhackAMoleView: View {
    let context: OfflineGameContext<WhackAMoleRules>
    @StateObject private var field = WhackAMoleField()
    /// Moles I have whacked, shown at once rather than after the host's echo.
    @State private var whacked: Set<Int> = []

    private var view: WhackAMoleRules.PlayerView { context.view }

    var body: some View {
        Group {
            switch view.phase {
            case .playing: playing
            case .timeUp, .over: timeUp
            }
        }
        .onAppear { follow() }
        .onChange(of: view.moles) { _, _ in follow() }
        .onChange(of: view.phase) { _, _ in follow() }
        .onChange(of: context.clock) { _, _ in follow() }
        .onDisappear { field.stop() }
    }

    // MARK: - The field

    private var playing: some View {
        VStack(spacing: 14) {
            header
            GeometryReader { geo in
                let side = max(0, min(geo.size.width, geo.size.height, 420))
                let cell = side / CGFloat(WhackAMoleRules.columns)
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { column in
                                hole(row * WhackAMoleRules.columns + column, cell: cell)
                            }
                        }
                    }
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityIdentifier("offline-whack-a-mole-field")
            WhackAMoleScores(rows: view.rows, me: context.me)
        }
        .padding(.horizontal, SR.gutter)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srGround(.warm)
    }

    /// The lead-in countdown, then the time left and my points.
    private var header: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let leadIn = context.clock.now() < view.startsAt
            let secondsLeft = context.clock.secondsLeft(until: leadIn ? view.startsAt : view.endsAt)
            let clockLabel: String = leadIn ? "Moles in \(secondsLeft) seconds" : "\(secondsLeft) seconds left"
            let pointsLabel: String = isPlayer ? "You have \(myScore) points" : "You are watching this match"
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(leadIn ? "GET READY" : "TIME LEFT")
                            .font(SR.Text.label())
                            .tracking(SR.inkKickerTracking)
                            .foregroundStyle(SR.accent)
                            .lineLimit(1)
                        Text("\(secondsLeft)")
                            .font(SR.Text.figure(34))
                            .foregroundStyle(SR.ink)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(clockLabel)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(isPlayer ? "YOUR POINTS" : "WATCHING")
                            .font(SR.Text.label())
                            .tracking(SR.inkKickerTracking)
                            .foregroundStyle(SR.inkMuted)
                            .lineLimit(1)
                        if isPlayer {
                            Text("\(myScore)")
                                .font(SR.Text.figure(34))
                                .foregroundStyle(myScore < 0 ? SR.error : SR.ink)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(pointsLabel)
                }
                Text(instruction(leadIn: leadIn))
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("offline-whack-a-mole-instruction")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func instruction(leadIn: Bool) -> String {
        if !isPlayer { return "You are watching this match." }
        if leadIn { return "Tap moles as they pop up. Leave the bombs." }
        return "Whack the moles — golden is 3, bombs cost 2."
    }

    /// One hole: the mound, whatever is in it, and the touch surface on top.
    private func hole(_ index: Int, cell: CGFloat) -> some View {
        let mole = upMole(in: index)
        let settled = settledMole(in: index)
        let size = cell * 0.84
        return ZStack {
            Circle()
                .fill(SR.ink.opacity(0.14))
                .overlay { Circle().stroke(SR.line, lineWidth: 1) }
                .frame(width: size, height: size)
            if let mole, settled?.id != mole.id {
                if whackedByMe(mole) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: size * 0.32, weight: .bold))
                        .foregroundStyle(SR.inkMuted)
                } else {
                    WhackAMoleCritter(kind: mole.kind, size: size * 0.78)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            } else if let settled {
                settledMark(settled, size: size)
            }
            if isPlayer && view.phase == .playing {
                TapSurface(label: holeLabel(index, mole: mole)) { touched(hole: index, at: $0) }
                    .frame(width: cell, height: cell)
                    .accessibilityIdentifier("offline-whack-a-mole-hole-\(index + 1)")
            }
        }
        .frame(width: cell, height: cell)
        .animation(.easeOut(duration: 0.08), value: mole?.id)
    }

    /// Who got a settled mole: their initial, or my −2 for a bomb.
    @ViewBuilder
    private func settledMark(_ mole: WhackAMoleRules.MoleView, size: CGFloat) -> some View {
        if let taker = mole.takenBy {
            VStack(spacing: 2) {
                OfflineInitial(name: context.name(of: taker), size: size * 0.42, tone: seatColour(taker))
                Text(mole.kind == .golden ? "+3" : "+1")
                    .font(.system(size: size * 0.16, weight: .bold, design: .rounded))
                    .foregroundStyle(SR.inkSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(taker == context.me ? "You" : context.name(of: taker)) took it")
        } else if mole.kind == .bomb && mole.bombed.contains(context.me) {
            Text("−2")
                .font(.system(size: size * 0.26, weight: .heavy, design: .rounded))
                .foregroundStyle(SR.error)
                .accessibilityLabel("You hit a bomb, minus 2")
        }
    }

    private func holeLabel(_ index: Int, mole: WhackAMoleRules.MoleView?) -> String {
        guard let mole else { return "Hole \(index + 1), empty" }
        switch mole.kind {
        case .mole: return "Hole \(index + 1), mole up"
        case .golden: return "Hole \(index + 1), golden mole up"
        case .bomb: return "Hole \(index + 1), bomb — don't tap"
        }
    }

    // MARK: - Time's up

    private var timeUp: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Time's up", title: resultTitle)
                WhackAMoleScores(rows: view.rows.sorted { $0.score > $1.score }, me: context.me, large: true)
                if view.phase == .timeUp {
                    HStack(spacing: 8) {
                        Text("Final table in")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                        OfflineCountdown(clock: context.clock, until: view.resultUntil, font: SR.Text.mono(), tone: SR.inkMuted)
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("offline-whack-a-mole-result")
    }

    private var resultTitle: String {
        let names = view.champions.map { $0 == context.me ? "You" : context.name(of: $0) }
        if names.count == 1 { return names[0] == "You" ? "You win" : "\(names[0]) wins" }
        return names.isEmpty ? "Nobody scored" : "A tie"
    }

    // MARK: - Reading the view

    private var isPlayer: Bool {
        view.rows.contains { $0.id == context.me && !$0.away }
    }

    private var myScore: Int {
        view.rows.first { $0.id == context.me }?.score ?? 0
    }

    /// The mole on screen in a hole right now, by this phone's display link.
    private func upMole(in hole: Int) -> WhackAMoleRules.MoleView? {
        view.moles.first { $0.hole == hole && field.showing.contains($0.id) }
    }

    /// The latest settled mole in a hole that someone took (or that cost me).
    private func settledMole(in hole: Int) -> WhackAMoleRules.MoleView? {
        view.moles.last { mole in
            mole.hole == hole && mole.resolved
                && (mole.takenBy != nil || (mole.kind == .bomb && mole.bombed.contains(context.me)))
        }
    }

    private func whackedByMe(_ mole: WhackAMoleRules.MoleView) -> Bool {
        mole.mine || whacked.contains(mole.id)
    }

    private func seatColour(_ id: String) -> Color {
        OfflineSeatColour.of(view.rows.firstIndex { $0.id == id } ?? 0)
    }

    // MARK: - Acting

    /// Hand the field this view's moles, or rest it once time is up.
    private func follow() {
        if view.phase == .playing {
            field.follow(view.moles, clock: context.clock)
        } else {
            field.stop()
        }
    }

    /// A touch on a hole, at its own hardware timestamp.
    private func touched(hole: Int, at timestamp: Double) {
        guard view.phase == .playing, isPlayer, let mole = upMole(in: hole), !whackedByMe(mole) else { return }
        // Under a tenth of a second after it showed is a tap that was coming
        // anyway, not a whack; let it pass rather than throw a refusal.
        guard let ms = field.reactionMs(mole: mole.id, touchedAt: timestamp), OfflineReaction.counts(ms) else { return }
        whacked.insert(mole.id)
        if mole.kind == .bomb { SRHaptic.bad() } else { SRHaptic.ok() }
        context.send(.whack(mole: mole.id, ms: ms))
    }
}

/// A mole, a golden mole or a bomb popping out of its hole.
struct WhackAMoleCritter: View {
    let kind: WhackAMoleRules.Kind
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(fill)
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(SR.paper)
        }
        .frame(width: size, height: size)
        .shadow(color: SR.ink.opacity(0.18), radius: 4, y: 2)
        .accessibilityHidden(true)
    }

    private var fill: Color {
        switch kind {
        case .mole: return SR.accentDeep
        case .golden: return SR.warn
        case .bomb: return SR.ink
        }
    }

    private var symbol: String {
        switch kind {
        case .mole: return "pawprint.fill"
        case .golden: return "star.fill"
        case .bomb: return "flame.fill"
        }
    }
}

/// Everyone's points, one row each: five names fit a 375pt phone because each
/// row truncates its name rather than pushing the figure off the edge.
struct WhackAMoleScores: View {
    let rows: [WhackAMoleRules.Row]
    let me: String
    var large = false

    var body: some View {
        VStack(spacing: large ? 0 : 4) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if large && index > 0 { Divider().overlay(SR.divider) }
                HStack(spacing: 8) {
                    Text(row.id == me ? "You" : row.name)
                        .font(large ? SR.Text.title() : SR.Text.bodyMedium(15))
                        .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if row.away {
                        Text("left")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize()
                    }
                    Spacer(minLength: 6)
                    Text("\(row.score)")
                        .font(large ? SR.Text.display(20) : SR.Text.mono(15))
                        .foregroundStyle(row.score < 0 ? SR.error : SR.ink)
                        .monospacedDigit()
                        .frame(minWidth: 26, alignment: .trailing)
                        .fixedSize()
                }
                .frame(minHeight: large ? SR.tapTarget : 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.id == me ? "You" : row.name), \(row.score) points\(row.away ? ", left" : "")")
            }
        }
        .padding(.horizontal, large ? SR.cardPadding : 0)
        .padding(.vertical, large ? 6 : 0)
        .modifier(WhackAMoleCardIf(on: large))
        .frame(maxWidth: 420)
        .accessibilityIdentifier("offline-whack-a-mole-scores")
    }
}

/// The glass card round the final scores only.
private struct WhackAMoleCardIf: ViewModifier {
    let on: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if on {
            content.srGlassCard(.paper)
        } else {
            content
        }
    }
}

/// The field's clock: a display link that pops each mole up on the first
/// frame due at or after its host-clock `upAt` and drops it at `downAt`,
/// remembering the local time of the frame that showed it so a whack can be
/// measured from what the player actually saw — `OfflineStimulus`, but for
/// several moles at once.
@MainActor
final class WhackAMoleField: ObservableObject {
    /// Ids of the moles on screen now.
    @Published private(set) var showing: Set<Int> = []
    /// Local uptime of the frame that first showed each mole.
    private var shownAt: [Int: Double] = [:]
    /// Each mole's window on this phone's clock.
    private var windows: [(id: Int, up: Double, down: Double)] = []
    private var ticker: FrameTicker?

    /// Follow this view's moles. A refined clock re-aims those not yet up;
    /// a mole already showing keeps the frame it showed on.
    func follow(_ moles: [WhackAMoleRules.MoleView], clock: OfflineHostClock) {
        windows = moles.map { mole in
            (id: mole.id, up: clock.local(fromHost: mole.upAt), down: clock.local(fromHost: mole.downAt))
        }
        let ids = Set(moles.map(\.id))
        shownAt = shownAt.filter { ids.contains($0.key) }
        guard ticker == nil else { return }
        let ticker = FrameTicker { [weak self] frameTime in
            guard let self else { return false }
            self.frame(frameTime)
            return true
        }
        self.ticker = ticker
        ticker.start()
    }

    /// Stop the display link and clear the field.
    func stop() {
        ticker?.stop()
        ticker = nil
        windows = []
        shownAt = [:]
        if !showing.isEmpty { showing = [] }
    }

    /// Milliseconds from a mole shown to a touch at `touchTime` (local uptime
    /// — `UITouch.timestamp`). Nil if that mole never showed here.
    func reactionMs(mole id: Int, touchedAt touchTime: Double) -> Int? {
        OfflineReaction.ms(shownAt: shownAt[id], touchedAt: touchTime)
    }

    /// One frame, at the local time it reaches the glass.
    private func frame(_ frameTime: Double) {
        var now: Set<Int> = []
        for window in windows where frameTime >= window.up && frameTime < window.down {
            now.insert(window.id)
            if shownAt[window.id] == nil { shownAt[window.id] = frameTime }
        }
        if now != showing { showing = now }
    }
}
