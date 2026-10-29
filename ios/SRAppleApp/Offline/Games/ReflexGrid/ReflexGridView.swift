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
///
/// The overhaul (2026-10-29) made the lit tile glow, flashes a cleared tile
/// green and a missed one red (with a shake), counts 3-2-1 in big bumping
/// digits, runs everyone's progress as coloured lanes, stops the stopwatch's
/// redraws the moment I finish, and keeps this phone's quickest run.
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
    /// The tile I just cleared, flashed green for a moment.
    @State private var hit: Int?
    @State private var shakes = 0
    @State private var best: NearbyPlayBestOutcome?
    @State private var burstToken = 0
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: view.phase) { _, new in
            arm()
            settled(new)
        }
        .onChange(of: view.startsAt) { _, _ in arm() }
        .onChange(of: context.clock) { _, _ in arm() }
        .onChange(of: view.mine) { _, _ in catchUp() }
        .onChange(of: scenePhase) { _, new in
            if new == .active { arm() }
        }
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

    /// My stopwatch runs only while I am racing; finished or waiting, the
    /// timeline is paused and nothing redraws.
    private var running: Bool { isPlayer && go.shown && !finished && view.phase == .racing }

    /// What to do now, and my stopwatch (time plus penalties).
    private var header: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: !running)) { _ in
            let total = myTotalMs()
            let timeLabel: String = isPlayer ? "Your time, \(ReflexGridRules.seconds(total))" : "Watching"
            let tilesLabel: String = isPlayer ? "\(cleared) of \(view.runLength) tiles" : "Watching"
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kicker)
                            .font(SR.Text.label())
                            .tracking(SR.inkKickerTracking)
                            .foregroundStyle(finished ? SR.good : SR.accent)
                            .lineLimit(1)
                        Text(ReflexGridRules.seconds(total))
                            .font(SR.Text.figure(38))
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
                            .font(SR.Text.figure(38))
                            .foregroundStyle(SR.ink)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                            .nearbyPlayBump(cleared, scale: 1.08)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(tilesLabel)
                }
                HStack(spacing: 8) {
                    if misses > 0 {
                        NearbyPlayStat(icon: "xmark.octagon.fill",
                                       text: "+\(ReflexGridRules.seconds(misses * view.penaltyMs))")
                    }
                    Text(instruction)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("offline-reflex-grid-instruction")
                }
            }
            .padding(SR.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srGlassCard(.paper)
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
            let inner = max(0, side - 20)
            let cell = max(0, (inner - gap * CGFloat(columns - 1)) / CGFloat(columns))
            VStack(spacing: gap) {
                ForEach(0..<columns, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { column in
                            tile(row * columns + column, cell: cell)
                        }
                    }
                }
            }
            .padding(10)
            .frame(width: side, height: side)
            .background(
                RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x1D2140), Color(hex: 0x0E1028)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .modifier(NearbyPlayShake(travel: 7, animatableData: CGFloat(shakes)))
            .overlay { countdown(side: side) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-reflex-grid-board")
    }

    /// 3, 2, 1 over the dark grid until GO shows.
    @ViewBuilder
    private func countdown(side: CGFloat) -> some View {
        if !go.shown && view.phase == .racing {
            NearbyPlayCountdownHero(clock: context.clock, until: view.startsAt,
                                    size: max(24, side * 0.34), tone: Color.white)
                .allowsHitTesting(false)
        }
    }

    /// One tile: lit, dark, flashing green after a hit or red after a miss —
    /// with its own touch surface.
    private func tile(_ index: Int, cell: CGFloat) -> some View {
        let lit = litTile == index
        let missed = flash == index
        let justHit = hit == index
        let radius = max(4, cell * 0.2)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            ZStack {
                shape.fill(tileFill(lit: lit, missed: missed, cleared: justHit))
                if lit {
                    shape.fill(RadialGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)],
                                              center: .center, startRadius: 0, endRadius: cell * 0.6))
                    Image(systemName: "bolt.fill")
                        .font(.system(size: max(8, cell * 0.38), weight: .bold))
                        .foregroundStyle(Color.white)
                        .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                }
                shape.strokeBorder(lit ? Color.white.opacity(0.7) : Color.white.opacity(0.08), lineWidth: lit ? 2 : 1)
            }
            .shadow(color: lit ? Color(hex: 0x7C5CFF).opacity(0.8) : Color.clear, radius: cell * 0.2, x: 0, y: 0)
            .scaleEffect(lit ? 1.04 : (missed ? 0.94 : 1))
            .accessibilityHidden(true)
            if canTap {
                TapSurface(label: tileLabel(index, lit: lit)) { touched(tile: index, at: $0) }
                    .frame(width: cell, height: cell)
                    .accessibilityIdentifier("offline-reflex-grid-tile-\(index + 1)")
            }
        }
        .frame(width: cell, height: cell)
    }

    /// Fixed colours: the board is a dark panel in both modes.
    private func tileFill(lit: Bool, missed: Bool, cleared: Bool) -> Color {
        if lit { return Color(hex: 0x7C5CFF) }
        if missed { return Color(hex: 0xE5383B) }
        if cleared { return Color(hex: 0x1FA463) }
        return Color.white.opacity(0.07)
    }

    private func tileLabel(_ index: Int, lit: Bool) -> String {
        let place = "Row \(index / max(1, view.columns) + 1), column \(index % max(1, view.columns) + 1)"
        return lit ? "\(place), lit — tap it" : "\(place), dark"
    }

    // MARK: - The result

    private var result: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NearbyPlayBanner(kicker: "Race over", title: resultTitle, mine: view.winners == [context.me],
                                 mark: .symbol("flag.checkered")) {
                    if view.phase == .result {
                        NearbyPlayBannerClock(clock: context.clock, until: view.resultUntil,
                                              total: ReflexGridRules.resultPause, mine: false)
                            .accessibilityLabel("Final table soon")
                    }
                }
                ReflexGridTimes(rows: view.rows, me: context.me, winners: view.winners, runLength: view.runLength)
                if let best, let mine = myRow?.totalMs {
                    NearbyPlayBestLine(outcome: best, value: mine, format: NearbyPlayBestMath.seconds(fromMs:))
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .overlay { NearbyPlayBurst(token: burstToken) }
        .accessibilityIdentifier("offline-reflex-grid-result")
    }

    private var resultTitle: String {
        let names = view.winners.map { $0 == context.me ? "You" : context.name(of: $0) }
        if names.count == 1 { return names[0] == "You" ? "You win" : "\(names[0]) wins" }
        return names.isEmpty ? "Nobody finished" : "A tie"
    }

    // MARK: - Reading the view

    private var myRow: ReflexGridRules.Row? { view.rows.first { $0.id == context.me } }

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

    /// The race is over: cheer a win, keep my time as a best.
    private func settled(_ phase: ReflexGridRules.Phase) {
        guard phase != .racing else { return }
        if view.winners.contains(context.me) && burstToken == 0 {
            burstToken += 1
            SRHaptic.ok()
        }
        if best == nil, isPlayer, let total = myRow?.totalMs {
            best = NearbyPlayBestBook.record(ReflexGridRules.info.id, value: total, rule: .lower)
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
            withAnimation(.linear(duration: 0.3)) { shakes += 1 }
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
        hit = index
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if hit == index { hit = nil }
        }
        if step >= view.runLength { SRHaptic.ok() } else { SRHaptic.tap() }
        context.send(.tile(step: step, ms: ms, misses: misses))
    }
}

/// Everybody's progress as one lane each — name, bar, tiles — so five racers
/// fit a 375pt phone: the name truncates and the bar takes what is left.
struct ReflexGridProgress: View {
    let rows: [ReflexGridRules.Row]
    let me: String
    /// My own count, ahead of the host's echo; nil when watching.
    let myCleared: Int?
    let runLength: Int

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { seat, row in
                lane(row, seat: seat)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: 420)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-reflex-grid-progress")
    }

    private func lane(_ row: ReflexGridRules.Row, seat: Int) -> some View {
        let count = row.id == me ? max(row.cleared, myCleared ?? row.cleared) : row.cleared
        let fraction = CGFloat(min(count, runLength)) / CGFloat(max(1, runLength))
        let tone = OfflineSeatColour.of(seat)
        return HStack(spacing: 8) {
            Text(row.id == me ? "You" : row.name)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 72, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.ink.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [tone.opacity(0.7), tone], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(12, geo.size.width * fraction))
                    if row.finished {
                        Image(systemName: "flag.checkered")
                            .font(SR.Text.label(12))
                            .foregroundStyle(SR.ink)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 4)
                    }
                }
            }
            .frame(height: 14)
            .srAnimation(.snappy(duration: 0.2), value: count)
            Text(status(row, count: count))
                .font(SR.Text.mono(13))
                .foregroundStyle(row.finished ? SR.ink : SR.inkSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minHeight: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(row, count: count))
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

/// The race's times, quickest first with places; those who did not finish
/// after them.
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
                    NearbyPlayPlaceDisc(place: row.totalMs == nil ? 0 : index + 1)
                    Text(row.id == me ? "You" : row.name)
                        .font(SR.Text.title())
                        .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if winners.contains(row.id) {
                        Image(systemName: "crown.fill")
                            .font(SR.Text.title(15))
                            .foregroundStyle(SR.warn)
                            .accessibilityLabel("Fastest")
                    }
                    Spacer(minLength: 8)
                    if row.misses > 0 {
                        Text(missText(row.misses))
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.error)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text(time(row))
                        .font(SR.Text.title(16))
                        .monospacedDigit()
                        .foregroundStyle(winners.contains(row.id) ? SR.accent : SR.inkSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(minHeight: 52)
                .padding(.vertical, 2)
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
