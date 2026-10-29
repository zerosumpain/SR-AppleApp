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
///
/// The overhaul (2026-10-29) dug the holes in a lawn: a real mole (snout,
/// eyes, teeth) pops up out of the ground, the golden one shines, the bomb
/// has a lit fuse, a whack lands a hammer and a "+1", a bomb flashes the
/// field red, the time runs as a ring with 3-2-1 before the moles come, and
/// this phone's best score is kept.
struct WhackAMoleView: View {
    let context: OfflineGameContext<WhackAMoleRules>
    @StateObject private var field = WhackAMoleField()
    /// Moles I have whacked, shown at once rather than after the host's echo.
    @State private var whacked: Set<Int> = []
    @State private var bombFlash = false
    @State private var best: NearbyPlayBestOutcome?
    @State private var burstToken = 0
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: view.phase) { _, new in
            follow()
            settled(new)
        }
        .onChange(of: context.clock) { _, _ in follow() }
        .onChange(of: scenePhase) { _, new in
            // The display link has nothing to show in the background.
            // `new` is passed in, not read back from the environment, so a
            // stale phase can never keep the field from starting again.
            if new == .active { follow(active: true) } else { field.stop() }
        }
        .onDisappear { field.stop() }
    }

    // MARK: - The field

    private var playing: some View {
        VStack(spacing: 14) {
            header
            GeometryReader { geo in
                let side = max(0, min(geo.size.width, geo.size.height, 420))
                let inner = max(0, side - 16)
                let cell = inner / CGFloat(WhackAMoleRules.columns)
                ZStack {
                    WhackAMoleLawn()
                        .equatable()
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<3, id: \.self) { column in
                                    hole(row * WhackAMoleRules.columns + column, cell: cell)
                                }
                            }
                        }
                    }
                    .frame(width: inner, height: inner)
                    RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                        .fill(Color(hex: 0xE5383B).opacity(bombFlash ? 0.35 : 0))
                        .allowsHitTesting(false)
                    leadIn(side: side)
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
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

    /// 3, 2, 1 over the lawn until the moles come.
    @ViewBuilder
    private func leadIn(side: CGFloat) -> some View {
        if context.clock.now() < view.startsAt {
            NearbyPlayCountdownHero(clock: context.clock, until: view.startsAt,
                                    size: max(24, side * 0.3), tone: Color.white)
                .allowsHitTesting(false)
        }
    }

    /// The ring for the time left (or to the start), my points, and what to
    /// do. Redraws only until time is up.
    private var header: some View {
        let lastInstant = max(view.startsAt, view.endsAt)
        let end = Date().addingTimeInterval(max(0, lastInstant - context.clock.now()))
        return TimelineView(NearbyPlayFiniteSchedule(end: end, step: 0.25)) { _ in
            let leadIn = context.clock.now() < view.startsAt
            let secondsLeft = context.clock.secondsLeft(until: leadIn ? view.startsAt : view.endsAt)
            let clockLabel: String = leadIn ? "Moles in \(secondsLeft) seconds" : "\(secondsLeft) seconds left"
            let pointsLabel: String = isPlayer ? "You have \(myScore) points" : "You are watching this match"
            HStack(alignment: .center, spacing: 12) {
                NearbyPlayClockRing(clock: context.clock, until: leadIn ? view.startsAt : view.endsAt,
                                    total: leadIn ? WhackAMoleRules.leadIn : WhackAMoleRules.duration,
                                    size: 56, tone: leadIn ? SR.inkMuted : SR.good, urgentBelow: 10,
                                    ticks: isPlayer && !leadIn)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(clockLabel)
                VStack(alignment: .leading, spacing: 2) {
                    Text(leadIn ? "GET READY" : "TIME LEFT")
                        .font(SR.Text.label())
                        .tracking(SR.inkKickerTracking)
                        .foregroundStyle(SR.accent)
                        .lineLimit(1)
                    Text(instruction(leadIn: leadIn))
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("offline-whack-a-mole-instruction")
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(isPlayer ? "POINTS" : "WATCHING")
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
                            .contentTransition(.numericText(value: Double(myScore)))
                            .nearbyPlayBump(myScore, scale: 1.12)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(pointsLabel)
            }
            .padding(SR.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srGlassCard(.paper)
        }
    }

    private func instruction(leadIn: Bool) -> String {
        if !isPlayer { return "You are watching this match." }
        if leadIn { return "Tap moles as they pop up. Leave the bombs." }
        return "Whack the moles — golden is 3, bombs cost 2."
    }

    /// One hole: the dirt, whatever is in it rising out of the ground, the
    /// front lip of the hole, and the touch surface on top.
    private func hole(_ index: Int, cell: CGFloat) -> some View {
        let mole = upMole(in: index)
        let settled = settledMole(in: index)
        let size = cell * 0.84
        let showing = mole.map { settled?.id != $0.id } ?? false
        return ZStack {
            // The hole itself.
            Ellipse()
                .fill(RadialGradient(colors: [Color(hex: 0x1E120A), Color(hex: 0x4A2E18)],
                                     center: .center, startRadius: 0, endRadius: size * 0.5))
                .frame(width: size, height: size * 0.42)
                .offset(y: size * 0.24)
            // What pops out, clipped to the ground so it rises from the hole.
            ZStack(alignment: .bottom) {
                if let mole, showing {
                    if whackedByMe(mole) {
                        WhackAMoleWhacked(points: mole.kind.points, size: size)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    } else {
                        WhackAMoleCritter(kind: mole.kind, size: size * 0.78)
                            .transition(.move(edge: .bottom))
                    }
                }
            }
            .frame(width: size, height: size * 0.86, alignment: .bottom)
            .clipShape(WhackAMoleHoleMask())
            .offset(y: -size * 0.02)
            // The front lip of the hole, over the critter's base.
            Ellipse()
                .strokeBorder(Color(hex: 0x8A5A2B), lineWidth: max(2, size * 0.05))
                .frame(width: size, height: size * 0.42)
                .offset(y: size * 0.24)
            if !showing, let settled {
                settledMark(settled, size: size)
                    .offset(y: -size * 0.08)
                    .transition(.scale.combined(with: .opacity))
            }
            if isPlayer && view.phase == .playing {
                TapSurface(label: holeLabel(index, mole: mole)) { touched(hole: index, at: $0) }
                    .frame(width: cell, height: cell)
                    .accessibilityIdentifier("offline-whack-a-mole-hole-\(index + 1)")
            }
        }
        .frame(width: cell, height: cell)
        .animation(.easeOut(duration: 0.08), value: mole?.id)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: mole.map { whackedByMe($0) } ?? false)
    }

    /// Who got a settled mole: their initial, or my −2 for a bomb.
    @ViewBuilder
    private func settledMark(_ mole: WhackAMoleRules.MoleView, size: CGFloat) -> some View {
        if let taker = mole.takenBy {
            VStack(spacing: 2) {
                OfflineInitial(name: context.name(of: taker), size: size * 0.42, tone: seatColour(taker))
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 2) }
                Text(mole.kind == .golden ? "+3" : "+1")
                    .font(.system(size: size * 0.18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(taker == context.me ? "You" : context.name(of: taker)) took it")
        } else if mole.kind == .bomb && mole.bombed.contains(context.me) {
            Text("−2")
                .font(.system(size: size * 0.3, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(hex: 0xFFD6D6))
                .shadow(color: Color(hex: 0xB3261E), radius: 4, x: 0, y: 0)
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
            VStack(alignment: .leading, spacing: 18) {
                NearbyPlayBanner(kicker: "Time's up", title: resultTitle, mine: view.champions == [context.me],
                                 mark: .symbol("hammer.fill")) {
                    if view.phase == .timeUp {
                        NearbyPlayBannerClock(clock: context.clock, until: view.resultUntil,
                                              total: WhackAMoleRules.resultPause, mine: false)
                            .accessibilityLabel("Final table soon")
                    }
                }
                WhackAMoleScores(rows: view.rows.sorted { $0.score > $1.score }, me: context.me, large: true)
                if let best {
                    NearbyPlayBestLine(outcome: best, value: myScore, format: { "\($0) pts" })
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .overlay { NearbyPlayBurst(token: burstToken) }
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
    private func follow(active: Bool? = nil) {
        if view.phase == .playing && (active ?? (scenePhase == .active)) {
            field.follow(view.moles, clock: context.clock)
        } else {
            field.stop()
        }
    }

    /// Time is up: cheer a win, keep a best.
    private func settled(_ phase: WhackAMoleRules.Phase) {
        guard phase != .playing else { return }
        if view.champions.contains(context.me) && burstToken == 0 {
            burstToken += 1
            SRHaptic.ok()
        }
        if best == nil, isPlayer {
            best = NearbyPlayBestBook.record(WhackAMoleRules.info.id, value: myScore, rule: .higher)
        }
    }

    /// A touch on a hole, at its own hardware timestamp.
    private func touched(hole: Int, at timestamp: Double) {
        guard view.phase == .playing, isPlayer, let mole = upMole(in: hole), !whackedByMe(mole) else { return }
        // Under a tenth of a second after it showed is a tap that was coming
        // anyway, not a whack; let it pass rather than throw a refusal.
        guard let ms = field.reactionMs(mole: mole.id, touchedAt: timestamp), OfflineReaction.counts(ms) else { return }
        whacked.insert(mole.id)
        if mole.kind == .bomb {
            SRHaptic.bad()
            withAnimation(.easeOut(duration: 0.08)) { bombFlash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.easeOut(duration: 0.3)) { bombFlash = false }
            }
        } else {
            SRHaptic.ok()
        }
        context.send(.whack(mole: mole.id, ms: ms))
    }
}

/// The lawn the holes are dug in: a sunny green with tufts of grass, drawn
/// once per size.
struct WhackAMoleLawn: View, Equatable {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [Color(hex: 0x7BCB52), Color(hex: 0x3E8E2F)]),
                startPoint: CGPoint(x: size.width / 2, y: 0), endPoint: CGPoint(x: size.width / 2, y: size.height)))
            var tufts = Path()
            let step: CGFloat = 26
            var row = 0
            var y: CGFloat = 14
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 10 : 23
                while x < size.width {
                    tufts.move(to: CGPoint(x: x - 3, y: y + 4))
                    tufts.addLine(to: CGPoint(x: x - 1, y: y - 2))
                    tufts.move(to: CGPoint(x: x, y: y + 4))
                    tufts.addLine(to: CGPoint(x: x + 1, y: y - 4))
                    tufts.move(to: CGPoint(x: x + 3, y: y + 4))
                    tufts.addLine(to: CGPoint(x: x + 4, y: y - 1))
                    x += step
                }
                y += step
                row += 1
            }
            context.stroke(tufts, with: .color(Color(hex: 0x2E6B22).opacity(0.35)), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}

/// The mask that makes a critter rise out of the ground: everything above
/// the hole's middle, and the round of the hole below it.
struct WhackAMoleHoleMask: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let ground = rect.maxY - rect.height * 0.2
        path.addRect(CGRect(x: rect.minX - rect.width, y: rect.minY - rect.height, width: rect.width * 3,
                            height: ground - rect.minY + rect.height))
        path.addEllipse(in: CGRect(x: rect.minX, y: ground - rect.height * 0.2, width: rect.width, height: rect.height * 0.4))
        return path
    }
}

/// A mole, a golden mole or a bomb popping out of its hole. Drawn, not a
/// symbol: a mole has a snout and teeth.
struct WhackAMoleCritter: View {
    let kind: WhackAMoleRules.Kind
    let size: CGFloat

    var body: some View {
        Group {
            switch kind {
            case .mole: mole(fur: [Color(hex: 0x9A6B47), Color(hex: 0x5E3A22)])
            case .golden: mole(fur: [Color(hex: 0xFFE07A), Color(hex: 0xD99A0B)])
            case .bomb: bomb
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func mole(fur: [Color]) -> some View {
        ZStack {
            // Head and body.
            RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                .fill(LinearGradient(colors: fur, startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.82, height: size * 0.98)
                .offset(y: size * 0.12)
            // Eyes.
            HStack(spacing: size * 0.18) {
                Circle().fill(Color(hex: 0x1A1A1A)).frame(width: size * 0.1, height: size * 0.1)
                Circle().fill(Color(hex: 0x1A1A1A)).frame(width: size * 0.1, height: size * 0.1)
            }
            .offset(y: -size * 0.12)
            // Snout, nose and teeth.
            Ellipse()
                .fill(Color(hex: 0xF2C9A0))
                .frame(width: size * 0.42, height: size * 0.28)
                .offset(y: size * 0.06)
            Ellipse()
                .fill(Color(hex: 0xE66A7F))
                .frame(width: size * 0.16, height: size * 0.1)
                .offset(y: -size * 0.02)
            HStack(spacing: size * 0.01) {
                Rectangle().fill(Color.white).frame(width: size * 0.06, height: size * 0.08)
                Rectangle().fill(Color.white).frame(width: size * 0.06, height: size * 0.08)
            }
            .offset(y: size * 0.15)
            if kind == .golden {
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.28, weight: .bold))
                    .foregroundStyle(Color.white)
                    .offset(x: size * 0.32, y: -size * 0.32)
            }
        }
        .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
    }

    private var bomb: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x5A5F6E), Color(hex: 0x14161C)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.5))
                .frame(width: size * 0.78, height: size * 0.78)
                .offset(y: size * 0.1)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: 0x3A3F4B))
                .frame(width: size * 0.18, height: size * 0.12)
                .offset(y: -size * 0.3)
            Path { path in
                path.move(to: CGPoint(x: size * 0.5, y: size * 0.14))
                path.addQuadCurve(to: CGPoint(x: size * 0.7, y: size * 0.02), control: CGPoint(x: size * 0.52, y: 0))
            }
            .stroke(Color(hex: 0xC8A46A), lineWidth: max(1.5, size * 0.04))
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.24, weight: .bold))
                .foregroundStyle(Color(hex: 0xFFD166))
                .position(x: size * 0.72, y: size * 0.02)
            Text("!")
                .font(.system(size: size * 0.34, weight: .black, design: .rounded))
                .foregroundStyle(Color(hex: 0xFF6B6B))
                .offset(y: size * 0.1)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
    }
}

/// A whack landing: the hammer and the points, while the mole is still up.
struct WhackAMoleWhacked: View {
    let points: Int
    let size: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "hammer.fill")
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(Color.white)
                .rotationEffect(.degrees(-30))
            Text(points > 0 ? "+\(points)" : "−\(abs(points))")
                .font(.system(size: size * 0.22, weight: .heavy, design: .rounded))
                .foregroundStyle(points > 0 ? Color(hex: 0xFFF3B0) : Color(hex: 0xFFD6D6))
        }
        .shadow(color: Color.black.opacity(0.45), radius: 3, x: 0, y: 1)
        .frame(width: size, height: size * 0.8)
        .accessibilityHidden(true)
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
                    if large {
                        NearbyPlayPlaceDisc(place: index + 1)
                    } else {
                        Circle()
                            .fill(OfflineSeatColour.of(index))
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                    }
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
                        .font(large ? SR.Text.display(22) : SR.Text.title(16))
                        .foregroundStyle(row.score < 0 ? SR.error : SR.ink)
                        .monospacedDigit()
                        .frame(minWidth: 26, alignment: .trailing)
                        .fixedSize()
                }
                .frame(minHeight: large ? 52 : 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.id == me ? "You" : row.name), \(row.score) points\(row.away ? ", left" : "")")
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, large ? 6 : 10)
        .srGlassCard(.paper)
        .frame(maxWidth: 420)
        .accessibilityIdentifier("offline-whack-a-mole-scores")
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
