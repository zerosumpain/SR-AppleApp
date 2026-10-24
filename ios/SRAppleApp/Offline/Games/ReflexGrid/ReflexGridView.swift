import SwiftUI
import UIKit

/// Reflex Grid on one phone: the countdown, the four-by-four grid with its
/// one lit tile, my stopwatch, and a bar for everybody's progress.
///
/// The phone has the whole run from the start, so nothing waits for the host
/// between tiles: a tap on the lit tile lights the next one in the same
/// frame. GO is an `OfflineStimulus` aimed at the host's `startsAt`; every
/// tile's time is measured from the frame that showed GO to the touch (each
/// tile is its own `TapSurface`, so the touch keeps its hardware timestamp).
/// Each cleared tile is reported with the stopwatch so far and my misses, and
/// the host's view only ever moves my run forward, never back.
struct ReflexGridView: View {
    let context: OfflineGameContext<ReflexGridRules>
    @StateObject private var go = OfflineStimulus()
    /// Tiles I have cleared, counted here rather than waiting for the host.
    @State private var cleared = 0
    /// Dark tiles I have tapped.
    @State private var misses = 0
    /// My stopwatch at the last cleared tile, ms from GO.
    @State private var lastMs = 0
    /// A dark tile I just tapped, flashed red for a moment.
    @State private var flash: Int?

    private var view: ReflexGridRules.PlayerView { context.view }

    var body: some View {
        Group {
            switch view.phase {
            case .racing: race
            case .result, .over: result
            }
        }
        .onAppear {
            catchUp()
            arm()
        }
        .onChange(of: view.phase) { _, _ in arm() }
        .onChange(of: view.startsAt) { _, _ in arm() }
        .onChange(of: context.clock) { _, _ in arm() }
        .onChange(of: view.mine) { _, _ in catchUp() }
        .onDisappear { go.reset() }
    }

    // MARK: - The race

    private var race: some View {
        VStack(spacing: 14) {
            header
            board
            ReflexGridProgress(rows: view.rows, me: context.me, myCleared: isPlayer ? cleared : nil,
                               runLength: view.runLength)
        }
        .padding(.horizontal, SR.gutter)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srGround(.warm)
    }

    /// What to do now, and my stopwatch (time plus penalties).
    private var header: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            let total = myTotalMs()
            let timeLabel: String = isPlayer ? "Your time, \(ReflexGridRules.seconds(total))" : "Watching"
            let tilesLabel: String = isPlayer ? "\(cleared) of \(view.runLength) tiles" : "Watching"
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kicker)
                            .font(SR.Text.label())
                            .tracking(SR.inkKickerTracking)
                            .foregroundStyle(SR.accent)
                            .lineLimit(1)
                        Text(ReflexGridRules.seconds(total))
                            .font(SR.Text.figure(34))
                            .foregroundStyle(SR.ink)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(timeLabel)
                    .accessibilityIdentifier("offline-reflex-grid-time")
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("TILES")
                            .font(SR.Text.label())
                            .tracking(SR.inkKickerTracking)
                            .foregroundStyle(SR.inkMuted)
                            .lineLimit(1)
                        Text("\(isPlayer ? cleared : 0)/\(view.runLength)")
                            .font(SR.Text.figure(34))
                            .foregroundStyle(SR.ink)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(tilesLabel)
                }
                Text(instruction)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("offline-reflex-grid-instruction")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var kicker: String {
        if !isPlayer { return "WATCHING" }
        if finished { return "FINISHED" }
        return go.shown ? "YOUR TIME" : "GET READY"
    }

    private var instruction: String {
        if !isPlayer { return "You are watching this race." }
        if finished { return "Done! Waiting for the others to cross the line." }
        if !go.shown { return "Tap the lit tile when the countdown says GO." }
        if misses > 0 {
            let penalty = misses * view.penaltyMs
            return "Tap the lit tile. Misses so far: \(misses) (+\(ReflexGridRules.seconds(penalty)))."
        }
        return "Tap the lit tile — the next one lights at once."
    }

    /// The grid, sized from the space it is given, with the countdown over it.
    private var board: some View {
        GeometryReader { geo in
            let side = max(0, min(geo.size.width, geo.size.height, 420))
            let columns = max(1, view.columns)
            let gap: CGFloat = 8
            let cell = max(0, (side - gap * CGFloat(columns - 1)) / CGFloat(columns))
            VStack(spacing: gap) {
                ForEach(0..<columns, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { column in
                            tile(row * columns + column, cell: cell)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .overlay { countdown(side: side) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-reflex-grid-board")
    }

    /// 3, 2, 1 over the dark grid until GO shows.
    @ViewBuilder
    private func countdown(side: CGFloat) -> some View {
        if !go.shown {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let left = context.clock.secondsLeft(until: view.startsAt)
                let shown: String = left > 0 ? "\(left)" : "GO"
                let spoken: String = left > 0 ? "Starting in \(left)" : "Go"
                Text(shown)
                    .font(.system(size: max(24, side * 0.32), weight: .heavy, design: .rounded))
                    .foregroundStyle(SR.ink.opacity(0.75))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .accessibilityLabel(spoken)
            }
            .allowsHitTesting(false)
        }
    }

    /// One tile: lit, dark, or flashing red after a miss — with its own touch surface.
    private func tile(_ index: Int, cell: CGFloat) -> some View {
        let lit = litTile == index
        let missed = flash == index
        let radius = max(4, cell * 0.16)
        return ZStack {
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(lit ? SR.accent : (missed ? SR.error : SR.ink.opacity(0.10)))
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(lit ? SR.accentDeep : SR.line, lineWidth: 1)
                if lit {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: max(8, cell * 0.34), weight: .bold))
                        .foregroundStyle(SR.paper)
                }
            }
            .accessibilityHidden(true)
            if canTap {
                TapSurface(label: tileLabel(index, lit: lit)) { touched(tile: index, at: $0) }
                    .frame(width: cell, height: cell)
                    .accessibilityIdentifier("offline-reflex-grid-tile-\(index + 1)")
            }
        }
        .frame(width: cell, height: cell)
    }

    private func tileLabel(_ index: Int, lit: Bool) -> String {
        let place = "Row \(index / max(1, view.columns) + 1), column \(index % max(1, view.columns) + 1)"
        return lit ? "\(place), lit — tap it" : "\(place), dark"
    }

    // MARK: - The result

    private var result: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Race over", title: resultTitle)
                ReflexGridTimes(rows: view.rows, me: context.me, winners: view.winners, runLength: view.runLength)
                if view.phase == .result {
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
        .accessibilityIdentifier("offline-reflex-grid-result")
    }

    private var resultTitle: String {
        let names = view.winners.map { $0 == context.me ? "You" : context.name(of: $0) }
        if names.count == 1 { return names[0] == "You" ? "You win" : "\(names[0]) wins" }
        return names.isEmpty ? "Nobody finished" : "A tie"
    }

    // MARK: - Reading the view

    /// I am racing in this match and still here (not a spectator).
    private var isPlayer: Bool {
        view.mine != nil && view.rows.contains { $0.id == context.me && !$0.away }
    }

    private var finished: Bool { cleared >= view.runLength }

    private var canTap: Bool {
        isPlayer && view.phase == .racing && go.shown && !finished
    }

    /// The tile to tap now, if I am racing and GO has shown.
    private var litTile: Int? {
        guard isPlayer, go.shown, view.phase == .racing, cleared < view.sequence.count else { return nil }
        return view.sequence[cleared]
    }

    /// My stopwatch plus penalties: running until I finish, then frozen.
    private func myTotalMs() -> Int {
        guard isPlayer else { return 0 }
        let penalty = misses * view.penaltyMs
        if finished { return lastMs + penalty }
        guard let shownAt = go.shownAt else { return 0 }
        let running = max(0, Int(((OfflineUptime.now() - shownAt) * 1000).rounded()))
        return running + penalty
    }

    // MARK: - Acting

    /// Aim GO at the host's start, or rest it once the race is closed.
    private func arm() {
        if view.phase == .racing {
            go.arm(at: view.startsAt, clock: context.clock)
        } else {
            go.reset()
        }
    }

    /// The host's word on my run only moves it forward (after a rejoin, say).
    private func catchUp() {
        guard let mine = view.mine else { return }
        if mine.cleared > cleared {
            cleared = mine.cleared
            lastMs = mine.ms
        }
        if mine.misses > misses { misses = mine.misses }
    }

    /// A touch on a tile, at its own hardware timestamp.
    private func touched(tile index: Int, at timestamp: Double) {
        guard canTap, let lit = litTile, let ms = go.reactionMs(touchedAt: timestamp) else { return }
        guard index == lit else {
            misses += 1
            flash = index
            SRHaptic.bad()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                if flash == index { flash = nil }
            }
            return
        }
        let step = cleared + 1
        // Quicker than anyone can see and move: a tap that was already coming.
        // Let it pass rather than send a time the host must refuse.
        guard ms >= step * ReflexGridRules.minTileMs, ms >= lastMs else { return }
        cleared = step
        lastMs = ms
        if step >= view.runLength { SRHaptic.ok() } else { SRHaptic.tap() }
        context.send(.tile(step: step, ms: ms, misses: misses))
    }
}

/// Everybody's progress as one row each — name, bar, tiles — so five racers
/// fit a 375pt phone: the name truncates and the bar takes what is left.
struct ReflexGridProgress: View {
    let rows: [ReflexGridRules.Row]
    let me: String
    /// My own count, ahead of the host's echo; nil when watching.
    let myCleared: Int?
    let runLength: Int

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { seat, row in
                let count = row.id == me ? max(row.cleared, myCleared ?? row.cleared) : row.cleared
                HStack(spacing: 8) {
                    Text(row.id == me ? "You" : row.name)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 84, alignment: .leading)
                    ProgressView(value: Double(min(count, runLength)), total: Double(max(1, runLength)))
                        .progressViewStyle(.linear)
                        .tint(OfflineSeatColour.of(seat))
                        .frame(maxWidth: .infinity)
                    Text(status(row, count: count))
                        .font(SR.Text.mono(13))
                        .foregroundStyle(row.finished ? SR.ink : SR.inkSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(minHeight: 22)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(row, count: count))
            }
        }
        .frame(maxWidth: 420)
        .accessibilityIdentifier("offline-reflex-grid-progress")
    }

    private func status(_ row: ReflexGridRules.Row, count: Int) -> String {
        if row.away { return "left" }
        if let total = row.totalMs { return ReflexGridRules.seconds(total) }
        return "\(count)/\(runLength)"
    }

    private func label(_ row: ReflexGridRules.Row, count: Int) -> String {
        let who = row.id == me ? "You" : row.name
        if row.away { return "\(who), left" }
        if let total = row.totalMs { return "\(who), finished in \(ReflexGridRules.seconds(total))" }
        return "\(who), \(count) of \(runLength) tiles"
    }
}

/// The race's times, quickest first; those who did not finish after them.
struct ReflexGridTimes: View {
    let rows: [ReflexGridRules.Row]
    let me: String
    let winners: [String]
    let runLength: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack(spacing: 10) {
                    Text(row.id == me ? "You" : row.name)
                        .font(SR.Text.title())
                        .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if winners.contains(row.id) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SR.accent)
                            .accessibilityLabel("Fastest")
                    }
                    Spacer(minLength: 8)
                    if row.misses > 0 {
                        Text(missText(row.misses))
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text(time(row))
                        .font(SR.Text.mono(15))
                        .foregroundStyle(winners.contains(row.id) ? SR.accent : SR.inkSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(minHeight: SR.tapTarget)
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-reflex-grid-times")
    }

    private func missText(_ misses: Int) -> String {
        misses == 1 ? "1 miss" : "\(misses) misses"
    }

    private var sorted: [ReflexGridRules.Row] {
        rows.sorted { key($0) < key($1) }
    }

    /// Finishers by total; then the rest by tiles cleared, most first.
    private func key(_ row: ReflexGridRules.Row) -> Int {
        if let total = row.totalMs { return total }
        return Int.max / 2 + (runLength - row.cleared)
    }

    private func time(_ row: ReflexGridRules.Row) -> String {
        if let total = row.totalMs { return ReflexGridRules.seconds(total) }
        if row.away { return "left" }
        return "\(row.cleared)/\(runLength)"
    }
}
