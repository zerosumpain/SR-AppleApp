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
struct SteadyHandView: View {
    let context: OfflineGameContext<SteadyHandRules>
    @StateObject private var table = SteadyHandTable()

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
        .onChange(of: context.clock) { _, _ in follow() }
        .onDisappear { table.stop() }
    }

    /// Whether I am in this match (not a spectator).
    private var isPlayer: Bool {
        view.rows.contains { $0.id == context.me }
    }

    /// Hand the latest view to the table, which starts or stops itself.
    private func follow() {
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

    /// The round, the countdown (to the start, then to the end), my points,
    /// and what to do.
    private var header: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let leadIn = context.clock.now() < view.startsAt
            let secondsLeft = context.clock.secondsLeft(until: leadIn ? view.startsAt : view.endsAt)
            let clockLabel: String = leadIn
                ? "Round \(view.round) starts in \(secondsLeft) seconds"
                : "\(secondsLeft) seconds left in round \(view.round)"
            let kicker: String = leadIn ? "GET READY" : "ROUND \(view.round) OF \(view.rounds) · ×\(view.multiplier)"
            let pointsLabel: String = isPlayer ? "You have \(myTotal) points" : "You are watching this match"
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kicker)
                            .font(SR.Text.label())
                            .tracking(SR.inkKickerTracking)
                            .foregroundStyle(SR.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(secondsLeft)")
                            .font(SR.Text.figure(34))
                            .foregroundStyle(SR.ink)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(clockLabel)
                    .accessibilityIdentifier("offline-steady-hand-clock")
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(isPlayer ? "YOUR POINTS" : "WATCHING")
                            .font(SR.Text.label())
                            .tracking(SR.inkKickerTracking)
                            .foregroundStyle(SR.inkMuted)
                            .lineLimit(1)
                        if isPlayer {
                            Text("\(myTotal)")
                                .font(SR.Text.figure(34))
                                .foregroundStyle(SR.ink)
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
                    .accessibilityIdentifier("offline-steady-hand-instruction")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Round \(view.round) of \(view.rounds) · ×\(view.multiplier)", title: resultTitle)
                SteadyHandScores(rows: view.rows.sorted { $0.total > $1.total }, me: context.me,
                                 showRound: true, large: true, leaders: view.roundLeaders)
                if view.phase == .result {
                    HStack(spacing: 8) {
                        Text(view.round >= view.rounds ? "Final table in" : "Next round in")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                        OfflineCountdown(clock: context.clock, until: view.resultUntil, font: SR.Text.mono(), tone: SR.inkMuted)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("offline-steady-hand-result")
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
}

// MARK: - The table

/// The square table: the ring where the rules say it is now, and my ball.
/// Sized from the width it is given, so it fits any phone.
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
        let tone = table.inside ? SR.good : SR.error
        ZStack {
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .fill(SR.ink.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                        .stroke(SR.line, lineWidth: 1)
                }
            Circle()
                .fill(SR.accent.opacity(0.12))
                .overlay { Circle().stroke(SR.accent, lineWidth: 3) }
                .frame(width: ringDiameter, height: ringDiameter)
                .position(point(centre.x, centre.y))
            if showBall {
                Circle()
                    .fill(tone)
                    .overlay { Circle().stroke(SR.paper, lineWidth: 2) }
                    .frame(width: ballDiameter, height: ballDiameter)
                    .position(point(table.ball.x, table.ball.y))
            }
        }
        .frame(width: side, height: side)
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
    private func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: (CGFloat(x) + 1) / 2 * side, y: (CGFloat(y) + 1) / 2 * side)
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
                    Text(row.id == me ? "You" : row.name)
                        .font(large ? SR.Text.title() : SR.Text.bodyMedium(15))
                        .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if leaders.contains(row.id) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SR.accent)
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
                            .foregroundStyle(SR.inkSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text("\(row.total)")
                        .font(large ? SR.Text.display(20) : SR.Text.mono(15))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: 36, alignment: .trailing)
                }
                .frame(minHeight: large ? SR.tapTarget : 28)
                .padding(.vertical, large ? 4 : 1)
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
