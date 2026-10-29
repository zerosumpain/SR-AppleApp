import SwiftUI
import UIKit
import CoreMotion

/// Steady Hand on one phone: the table with its drifting ring and rolling
/// ball, the clock, everyone's points, and each round's result.
///
/// The ball is this phone's alone. `SteadyHandTable` runs a display link:
/// each frame it reads the phone's tilt (Core Motion's device-motion gravity,
/// which needs no permission), rolls the ball with the rules' own physics,
/// and asks the rules' ring path whether the ball is inside at this
/// host-clock instant. It keeps, second by second, how much of each second
/// the ball spent inside, and sends each finished second as tenths — the host
/// only adds them up. Without a motion sensor (the simulator), the ball
/// follows a finger dragged across the table instead.
///
/// The overhaul (2026-10-29) drew the table as a lit dish with a glowing
/// ring that turns green while the ball is in it, made the ball a shaded
/// marble with a shadow, counts the lead-in down in big digits, runs the
/// round's clock as a ring, stops the engine (and the sensor) when the app
/// goes to the background, and keeps this phone's best total.
struct SteadyHandView: View {
    let context: OfflineGameContext<SteadyHandRules>
    @StateObject private var table = SteadyHandTable()
    @State private var best: NearbyPlayBestOutcome?
    @State private var burstToken = 0
    @Environment(\.scenePhase) private var scenePhase

    private var view: SteadyHandRules.PlayerView { context.view }

    var body: some View {
        Group {
            switch view.phase {
            case .ready, .playing: playing
            case .result, .over: result
            }
        }
        .onAppear { follow() }
        .onChange(of: view) { _, _ in follow() }
        .onChange(of: view.phase) { _, new in settled(new) }
        .onChange(of: context.clock) { _, _ in follow() }
        .onChange(of: scenePhase) { _, new in
            // No sensor and no display link behind the player's back.
            // `new` is passed in rather than read back from the environment,
            // so a stale phase can never keep the ball from restarting.
            if new == .active { follow(active: true) } else { table.stop() }
        }
        .onDisappear { table.stop() }
    }

    /// Whether I am in this match (not a spectator).
    private var isPlayer: Bool {
        view.rows.contains { $0.id == context.me }
    }

    /// Hand the latest view to the table, which starts or stops itself.
    private func follow(active: Bool? = nil) {
        guard active ?? (scenePhase == .active) else { return }
        table.follow(view, clock: context.clock, scoring: isPlayer, send: context.send)
    }

    // MARK: - Playing

    private var playing: some View {
        VStack(spacing: 12) {
            header
            GeometryReader { geo in
                let side = max(0, min(geo.size.width, geo.size.height, 420))
                SteadyHandBoard(table: table, path: view.path, startsAt: view.startsAt,
                                side: side, showBall: isPlayer, steerByDrag: isPlayer && !table.tiltAvailable)
                    .frame(width: side, height: side)
                    .overlay { leadIn(side: side) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityIdentifier("offline-steady-hand-table")
            SteadyHandScores(rows: view.rows, me: context.me, showRound: true)
        }
        .padding(.horizontal, SR.gutter)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srGround(.warm)
    }

    /// 3, 2, 1 over the table until the round starts.
    @ViewBuilder
    private func leadIn(side: CGFloat) -> some View {
        if context.clock.now() < view.startsAt {
            NearbyPlayCountdownHero(clock: context.clock, until: view.startsAt,
                                    size: max(24, side * 0.3), tone: Color.white)
                .allowsHitTesting(false)
        }
    }

    /// The round, the clock (to the start, then to the end), my points, and
    /// what to do. Redraws only until the round ends.
    private var header: some View {
        let lastInstant = max(view.startsAt, view.endsAt)
        let end = Date().addingTimeInterval(max(0, lastInstant - context.clock.now()))
        return TimelineView(NearbyPlayFiniteSchedule(end: end, step: 0.25)) { _ in
            let leadIn = context.clock.now() < view.startsAt
            let secondsLeft = context.clock.secondsLeft(until: leadIn ? view.startsAt : view.endsAt)
            let clockLabel: String = leadIn
                ? "Round \(view.round) starts in \(secondsLeft) seconds"
                : "\(secondsLeft) seconds left in round \(view.round)"
            let kicker: String = leadIn ? "GET READY" : "ROUND \(view.round) OF \(view.rounds) · ×\(view.multiplier)"
            let pointsLabel: String = isPlayer ? "You have \(myTotal) points" : "You are watching this match"
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    NearbyPlayClockRing(clock: context.clock, until: leadIn ? view.startsAt : view.endsAt,
                                        total: leadIn ? SteadyHandRules.readyPause : Double(SteadyHandRules.roundSeconds),
                                        size: 56, tone: leadIn ? SR.inkMuted : SR.accent, ticks: isPlayer && !leadIn)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(clockLabel)
                        .accessibilityIdentifier("offline-steady-hand-clock")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kicker)
                            .font(SR.Text.label())
                            .tracking(SR.inkKickerTracking)
                            .foregroundStyle(SR.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(instruction(leadIn: leadIn))
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("offline-steady-hand-instruction")
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(isPlayer ? "POINTS" : "WATCHING")
                            .font(SR.Text.label())
                            .tracking(SR.inkKickerTracking)
                            .foregroundStyle(SR.inkMuted)
                            .lineLimit(1)
                        if isPlayer {
                            Text("\(myTotal)")
                                .font(SR.Text.figure(32))
                                .foregroundStyle(SR.ink)
                                .monospacedDigit()
                                .lineLimit(1)
                                .contentTransition(.numericText(value: Double(myTotal)))
                                .nearbyPlayBump(myTotal, scale: 1.08)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(pointsLabel)
                }
            }
            .padding(SR.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srGlassCard(.paper)
        }
    }

    private var myTotal: Int {
        view.rows.first { $0.id == context.me }?.total ?? 0
    }

    private func instruction(leadIn: Bool) -> String {
        if !isPlayer { return "You are watching this match." }
        let steer = table.tiltAvailable ? "Tilt your phone" : "Drag on the table"
        if leadIn { return "\(steer) to roll the ball. Points start when the clock does." }
        if view.phase == .playing && context.clock.now() >= view.endsAt { return "Time! Adding up the scores." }
        return "\(steer) — keep the ball inside the ring."
    }

    // MARK: - A round's result

    private var result: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NearbyPlayBanner(kicker: "Round \(view.round) of \(view.rounds) · ×\(view.multiplier)", title: resultTitle,
                                 mine: leading, mark: .symbol(view.phase == .over ? "trophy.fill" : "scope")) {
                    if view.phase == .result {
                        NearbyPlayBannerClock(clock: context.clock, until: view.resultUntil,
                                              total: SteadyHandRules.resultPause, mine: false)
                            .accessibilityLabel(view.round >= view.rounds ? "Final table soon" : "Next round soon")
                    }
                }
                SteadyHandScores(rows: view.rows.sorted { $0.total > $1.total }, me: context.me,
                                 showRound: true, large: true, leaders: view.roundLeaders)
                if let best, view.phase == .over {
                    NearbyPlayBestLine(outcome: best, value: myTotal, format: { "\($0) pts" })
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .overlay { NearbyPlayBurst(token: burstToken) }
        .accessibilityIdentifier("offline-steady-hand-result")
    }

    private var leading: Bool {
        if view.phase == .over { return view.champions == [context.me] }
        return view.roundLeaders == [context.me]
    }

    private var resultTitle: String {
        if view.phase == .over {
            let names = view.champions.map { $0 == context.me ? "You" : context.name(of: $0) }
            if names.count == 1 { return names[0] == "You" ? "You win" : "\(names[0]) wins" }
            return names.isEmpty ? "Nobody scored" : "A tie"
        }
        let names = view.roundLeaders.map { $0 == context.me ? "You" : context.name(of: $0) }
        if names.count == 1 { return names[0] == "You" ? "Steadiest: you" : "Steadiest: \(names[0])" }
        return names.isEmpty ? "Nobody stayed in" : "A tie for steadiest"
    }

    /// A round has ended: cheer the steadiest, keep a best at the end.
    private func settled(_ phase: SteadyHandRules.Phase) {
        guard phase == .result || phase == .over else { return }
        if view.roundLeaders.contains(context.me) || (phase == .over && view.champions.contains(context.me)) {
            SRHaptic.ok()
            burstToken += 1
        }
        if phase == .over, best == nil, isPlayer {
            best = NearbyPlayBestBook.record(SteadyHandRules.info.id, value: myTotal, rule: .higher)
        }
    }
}

// MARK: - The table

/// The square table: a lit dish, the ring where the rules say it is now,
/// and my ball as a shaded marble. Sized from the width it is given, so it
/// fits any phone. Fixed colours: it is a game board, the same in both modes.
struct SteadyHandBoard: View {
    @ObservedObject var table: SteadyHandTable
    let path: SteadyHandRules.RingPath
    let startsAt: Double
    let side: CGFloat
    /// I am playing, so I have a ball (a spectator sees only the ring).
    let showBall: Bool
    /// No motion sensor: a finger steers.
    let steerByDrag: Bool

    var body: some View {
        let t = table.hostNow - startsAt
        let centre = path.center(at: t)
        let ringDiameter = CGFloat(path.radius(at: t)) * side
        let ballDiameter = CGFloat(SteadyHandRules.ballRadius) * side
        let inside = table.inside && showBall
        let ballTone = table.inside ? Color(hex: 0x2BD07A) : Color(hex: 0xFF5A5F)
        ZStack {
            SteadyHandDish()
                .equatable()
            Circle()
                .fill(inside ? Color(hex: 0x2BD07A).opacity(0.2) : Color(hex: 0x8F75FF).opacity(0.16))
                .overlay {
                    Circle().stroke(inside ? Color(hex: 0x2BD07A) : Color(hex: 0xA48BFF), lineWidth: 4)
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                        .padding(-6)
                }
                // A wide soft stroke rather than a blurred shadow: this
                // redraws every frame, and a blur every frame runs hot.
                .overlay {
                    Circle().stroke(Color(hex: 0x2BD07A).opacity(inside ? 0.28 : 0), lineWidth: 12)
                }
                .frame(width: ringDiameter, height: ringDiameter)
                .position(point(centre.x, centre.y))
            if showBall {
                Ellipse()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: ballDiameter * 0.9, height: ballDiameter * 0.36)
                    .position(point(table.ball.x, table.ball.y, dy: ballDiameter * 0.55))
                Circle()
                    .fill(RadialGradient(colors: [Color.white, ballTone, ballTone.opacity(0.85)],
                                         center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: ballDiameter * 0.75))
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5) }
                    .frame(width: ballDiameter, height: ballDiameter)
                    .position(point(table.ball.x, table.ball.y))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
        .contentShape(Rectangle())
        .gesture(dragToSteer)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(hintText)
    }

    private var accessibilityText: String {
        guard showBall else { return "The ring" }
        return table.inside ? "Ball inside the ring" : "Ball outside the ring"
    }

    private var hintText: String {
        guard showBall else { return "" }
        return steerByDrag ? "Drag to steer the ball." : "Tilt your phone to roll the ball."
    }

    /// Table units (-1…1, y down) to points.
    private func point(_ x: Double, _ y: Double, dy: CGFloat = 0) -> CGPoint {
        CGPoint(x: (CGFloat(x) + 1) / 2 * side, y: (CGFloat(y) + 1) / 2 * side + dy)
    }

    private var dragToSteer: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard steerByDrag, side > 0 else { return }
                let x = Double(value.location.x / side) * 2 - 1
                let y = Double(value.location.y / side) * 2 - 1
                table.dragTarget = SteadyHandTable.Target(x: x, y: y)
            }
            .onEnded { _ in table.dragTarget = nil }
    }
}

/// The dish under the ring: a deep blue lit from above with faint rings,
/// drawn once per size (it never changes while the ball rolls).
struct SteadyHandDish: View, Equatable {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .radialGradient(
                Gradient(colors: [Color(hex: 0x34407A), Color(hex: 0x141A3A)]),
                center: CGPoint(x: size.width / 2, y: size.height * 0.4),
                startRadius: 0, endRadius: max(size.width, size.height) * 0.75))
            var rings = Path()
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let step = min(size.width, size.height) / 10
            for index in 1...6 {
                let r = step * CGFloat(index)
                rings.addEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
            }
            context.stroke(rings, with: .color(Color.white.opacity(0.05)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Scores

/// Everyone's points as rows: five players fit a 375pt phone because each
/// row takes the full width and truncates its name.
struct SteadyHandScores: View {
    let rows: [SteadyHandRules.Row]
    let me: String
    var showRound = false
    var large = false
    var leaders: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack(spacing: 10) {
                    if large {
                        NearbyPlayPlaceDisc(place: index + 1)
                    }
                    Text(row.id == me ? "You" : row.name)
                        .font(large ? SR.Text.title() : SR.Text.bodyMedium(15))
                        .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if leaders.contains(row.id) {
                        Image(systemName: "crown.fill")
                            .font(SR.Text.title(15))
                            .foregroundStyle(SR.warn)
                            .accessibilityLabel("Steadiest this round")
                    }
                    Spacer(minLength: 8)
                    if row.away {
                        Text("left")
                            .font(SR.Text.mono(13))
                            .foregroundStyle(SR.inkMuted)
                            .lineLimit(1)
                            .fixedSize()
                    } else if showRound {
                        Text("+\(row.roundPoints)")
                            .font(SR.Text.mono(13))
                            .foregroundStyle(row.roundPoints > 0 ? SR.good : SR.inkSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text("\(row.total)")
                        .font(large ? SR.Text.display(22) : SR.Text.title(16))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: 36, alignment: .trailing)
                }
                .frame(minHeight: large ? 52 : 30)
                .padding(.vertical, large ? 2 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(row))
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-steady-hand-scores")
    }

    private func label(_ row: SteadyHandRules.Row) -> String {
        let who = row.id == me ? "You" : row.name
        var text = "\(who), \(row.total) points"
        if showRound { text += ", \(row.roundPoints) this round" }
        if row.away { text += ", left" }
        return text
    }
}

// MARK: - The ball's engine

/// This phone's ball and its bookkeeping: a display link that reads the tilt,
/// rolls the ball, checks it against the ring at the host-clock instant of
/// the frame, keeps how long each second was spent inside, and sends each
/// finished second to the host as tenths.
///
/// Motion updates are pulled (no queue, no callbacks) and stopped whenever
/// the round is not running or the view goes away, so the sensor is never
/// left on behind the player's back.
@MainActor
final class SteadyHandTable: ObservableObject {
    /// A finger's spot on the table, in table units.
    struct Target: Equatable {
        var x: Double
        var y: Double
    }

    @Published private(set) var ball = SteadyHandRules.Ball()
    @Published private(set) var inside = false
    /// Host-clock time of the last frame drawn.
    @Published private(set) var hostNow: Double = 0
    /// Whether this phone has a motion sensor; without one, drag steers.
    let tiltAvailable: Bool
    /// Where the finger is, when dragging steers.
    var dragTarget: Target?

    private let motion: CMMotionManager
    private var ticker: FrameTicker?
    private var lastFrame: Double?
    private var clock = OfflineHostClock.host
    private var round = 0
    private var startsAt: Double = 0
    private var endsAt: Double = 0
    private var path: SteadyHandRules.RingPath?
    private var scoring = false
    private var send: ((SteadyHandRules.Action) -> Void)?
    /// Seconds into the round → time the ball spent inside / time sampled.
    private var insideTime: [Int: Double] = [:]
    private var sampledTime: [Int: Double] = [:]
    /// Seconds already sent (or already held by the host).
    private var sent: Set<Int> = []

    init() {
        let manager = CMMotionManager()
        motion = manager
        tiltAvailable = manager.isDeviceMotionAvailable
    }

    /// Catch up with the host's latest view: a new round resets the ball and
    /// the tally; the table runs while the round is getting ready or running.
    func follow(_ view: SteadyHandRules.PlayerView, clock: OfflineHostClock, scoring: Bool,
                send: @escaping (SteadyHandRules.Action) -> Void) {
        self.clock = clock
        self.scoring = scoring
        self.send = send
        if view.round != round {
            round = view.round
            ball = SteadyHandRules.Ball()
            insideTime = [:]
            sampledTime = [:]
            sent = []
        }
        sent.formUnion(view.myReported)
        startsAt = view.startsAt
        endsAt = view.endsAt
        path = view.path
        if view.phase == .ready || view.phase == .playing {
            start()
        } else {
            stop()
        }
    }

    func start() {
        if tiltAvailable && !motion.isDeviceMotionActive {
            motion.deviceMotionUpdateInterval = 1.0 / 60
            motion.startDeviceMotionUpdates()
        }
        guard ticker == nil else { return }
        lastFrame = nil
        let ticker = FrameTicker { [weak self] frameTime in
            guard let self else { return false }
            self.frame(frameTime)
            return true
        }
        self.ticker = ticker
        ticker.start()
    }

    func stop() {
        ticker?.stop()
        ticker = nil
        lastFrame = nil
        dragTarget = nil
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
    }

    /// One display frame at local uptime `local`.
    private func frame(_ local: Double) {
        guard let path else { return }
        let dt = lastFrame.map { max(0, local - $0) } ?? 0
        lastFrame = local
        let now = clock.host(fromLocal: local)

        var next = ball
        if tiltAvailable {
            if let gravity = motion.deviceMotion?.gravity {
                next.roll(tiltX: gravity.x, tiltY: gravity.y, dt: dt)
            }
        } else if let target = dragTarget {
            next.follow(toX: target.x, toY: target.y, dt: dt)
        } else {
            next.vx = 0
            next.vy = 0
        }
        ball = next
        hostNow = now

        let t = now - startsAt
        let isInside = path.contains(x: next.x, y: next.y, at: t)
        let running = t >= 0 && now < endsAt
        if isInside != inside {
            inside = isInside
            if !isInside && running && scoring { SRHaptic.select() }
        }
        if running && scoring {
            let second = min(SteadyHandRules.roundSeconds - 1, Int(t))
            sampledTime[second, default: 0] += dt
            if isInside { insideTime[second, default: 0] += dt }
        }
        reportFinishedSeconds(now: now)
    }

    /// Send every second that has ended and not yet been sent.
    private func reportFinishedSeconds(now: Double) {
        guard scoring, let send, round > 0 else { return }
        let finished = min(SteadyHandRules.roundSeconds, max(0, Int((now - startsAt).rounded(.down))))
        guard finished > 0 else { return }
        for second in 0..<finished where !sent.contains(second) {
            sent.insert(second)
            let sampled = sampledTime[second] ?? 0
            let share = sampled > 0 ? (insideTime[second] ?? 0) / sampled : 0
            let tenths = min(10, max(0, Int((share * 10).rounded())))
            send(.report(round: round, second: second, tenths: tenths))
        }
    }
}
