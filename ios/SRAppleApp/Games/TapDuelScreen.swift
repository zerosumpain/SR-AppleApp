import SwiftUI
import UIKit

/// One Tap Duel room, from lobby to standings.
///
/// Countdown and armed take the whole screen — no bars, no tab bar — because
/// the armed phase IS the button, and a bar at the top is a place a thumb can
/// land and not be counted. Every other phase is an ordinary SR page.
///
/// The lobby carries a how-to card with this phone's best; the armed arena is
/// a target drawn in one Canvas; the round's result races everyone's times
/// along one axis; the final page has a podium, the personal best and, for a
/// win, confetti.
struct TapDuelScreen: View {
    let roomId: String
    @StateObject private var store: TapDuelStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: TapDuelStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Tap Duel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar(immersive ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(immersive)
            .onAppear { store.open() }
            .onDisappear { store.close() }
            // Reconnect on the way back; let go on the way out. A stream held
            // open through a suspend is a stream iOS kills anyway.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.open() } else if phase == .background { store.close() }
            }
            .overlay(alignment: .bottom) {
                if let message = store.message, !immersive { SRBanner(text: message) }
            }
    }

    private var immersive: Bool {
        guard !store.ended, let phase = store.room?.phase else { return false }
        return phase == .countdown || phase == .armed
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "tapduel-ended", done: { dismiss() })
        } else if let room = store.room {
            switch room.phase {
            case .lobby, .unknown, .playing, .question, .reveal, .show, .input, .review:
                GameLobby(room: room, store: store, prefix: "tapduel", done: { dismiss() },
                          panel: AnyView(TapDuelHowTo(difficulty: room.difficulty, rounds: room.rounds)))
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Wait for green. Tap early and the round is gone.",
                                  id: "tapduel-countdown")
            case .armed:
                TapDuelArmed(room: room, store: store)
            case .result:
                TapDuelResult(room: room, store: store)
            case .finished:
                TapDuelFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                SREmpty(title: "This game has ended", icon: "flag.checkered", actionLabel: "Done", action: { dismiss() })
                    .frame(maxHeight: .infinity)
                    .srPaper()
            }
        } else {
            ProgressView()
                .tint(SR.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .srPaper()
        }
    }
}

// MARK: - Lobby

/// How to play, in the lobby, with this phone's fastest tap at this level.
struct TapDuelHowTo: View {
    let difficulty: String
    let rounds: Int
    @State private var best: Int?
    @State private var played = 0

    var body: some View {
        QuickRoomHowTo(
            pitch: "Fastest finger wins",
            rules: [
                QuickRoomRule(icon: "hand.raised.fill", text: "The screen goes dark. Keep your thumb still and wait."),
                QuickRoomRule(icon: "exclamationmark.triangle.fill", text: "Amber is a trick. Tap on amber and that round is gone."),
                QuickRoomRule(icon: "bolt.fill", text: "Green means GO — tap anywhere on the screen, as fast as you can."),
                QuickRoomRule(icon: "crown.fill", text: rounds > 1
                              ? "Quickest tap takes the round. Most rounds out of \(rounds) wins."
                              : "Quickest tap takes it.")
            ],
            best: best.map { "Best \($0) ms" },
            played: played,
            id: "tapduel-howto"
        )
        .onAppear {
            let book = QuickRoomBestStore.tapDuel
            best = book.best(difficulty: difficulty)
            played = book.gamesPlayed()
        }
    }
}

// MARK: - Armed

/// What the arena is showing: the signal, or what my tap made of it.
enum TapDuelMood: Equatable {
    case wait, decoy, go, early, tapped
}

/// The arena's colours. Fixed, not the mode-following tokens: `SR.ink` is
/// near-white in dark mode, and a "wait" screen must be dark on every phone,
/// with green and amber bright enough to land in the corner of an eye.
enum TapDuelPaint {
    static var night: Color { Color(hex: SR.Fixed.ink) }
    static var cream: Color { Color(hex: SR.Fixed.paper) }
    static var amber: Color { Color(hex: SRPaint.current.palette.warn.dark) }
    static var green: Color { Color(hex: SRPaint.current.palette.good.dark) }
    static var red: Color { Color(hex: SR.Fixed.error) }
}

struct TapDuelArmed: View {
    let room: GameRoom
    @ObservedObject var store: TapDuelStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // The ground changes with NO animation: the reaction is measured
            // from the frame that shows green, so green must be whole on it.
            ground.ignoresSafeArea()

            TapDuelArena(mood: mood, ink: ink, animate: !reduceMotion && store.myTap == nil)
                .ignoresSafeArea()

            centre
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            hud

            // The whole screen is the button. UIKit underneath so the touch
            // keeps its own hardware timestamp.
            TapSurface(label: accessibilityText) { store.tap(at: $0) }
                .ignoresSafeArea()
                .accessibilityIdentifier("tapduel-surface")
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    // MARK: Layers

    private var centre: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 52, weight: .heavy))
                .foregroundStyle(ink)
                .symbolEffect(.bounce, value: mood)
            Text(headline)
                .font(SR.Text.hero(72))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
            afterTap
        }
        .padding(.horizontal, SR.gutter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var afterTap: some View {
        if let tap = store.myTap {
            switch tap {
            case .early:
                Text("False start")
                    .font(SR.Text.display(26))
                    .foregroundStyle(ink.opacity(0.9))
                Text("Wait for green next round.")
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(ink.opacity(0.75))
            case .reaction(let ms):
                TapDuelReactionReadout(ms: ms, ink: ink)
            }
        }
    }

    private var hud: some View {
        VStack(spacing: 10) {
            if let round = room.round {
                Text("ROUND \(round.number) OF \(room.rounds)")
                    .font(SR.Text.label(13))
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(ink.opacity(0.75))
                TapDuelRoundPips(current: round.number, total: room.rounds, ink: ink)
            }
            if !room.solo {
                Text(scoreLine)
                    .font(SR.Text.mono(13))
                    .foregroundStyle(ink.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
            Label(footer, systemImage: tapped ? "hourglass" : "hand.tap.fill")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(ink.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
        .padding(.bottom, 28)
        .padding(.horizontal, SR.gutter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: State

    private var tapped: Bool {
        guard let round = room.round else { return false }
        return store.hasTapped(round: round.number)
    }

    private var mood: TapDuelMood {
        if let tap = store.myTap {
            return tap == .early ? .early : .tapped
        }
        switch store.signal {
        case .wait: return .wait
        case .decoy: return .decoy
        case .go: return .go
        }
    }

    private var headline: String {
        if let tap = store.myTap {
            switch tap {
            case .early: return "Too soon"
            case .reaction: return store.signal == .go ? "Got it" : "Wait…"
            }
        }
        switch store.signal {
        case .wait: return "Wait…"
        case .decoy: return "Not yet"
        case .go: return "TAP!"
        }
    }

    private var icon: String {
        switch mood {
        case .wait: return "hand.raised.fill"
        case .decoy: return "exclamationmark.triangle.fill"
        case .go: return "bolt.fill"
        case .early: return "xmark.octagon.fill"
        case .tapped: return "checkmark.circle.fill"
        }
    }

    private var footer: String {
        tapped ? "Waiting for everyone else." : "Tap anywhere when it turns green."
    }

    private var scoreLine: String {
        let parts: [String] = room.playing.map { player -> String in
            let name: String = player.id == room.meId ? "You" : player.name
            return "\(name) \(player.score)"
        }
        return parts.joined(separator: "  ·  ")
    }

    private var ground: Color {
        if store.myTap == .early { return TapDuelPaint.red }
        switch store.signal {
        case .wait: return TapDuelPaint.night
        case .decoy: return TapDuelPaint.amber
        case .go: return TapDuelPaint.green
        }
    }

    /// Cream on the dark grounds (wait, false start), night on the bright ones.
    private var ink: Color {
        if store.myTap == .early { return TapDuelPaint.cream }
        return store.signal == .wait ? TapDuelPaint.cream : TapDuelPaint.night
    }

    private var accessibilityText: String {
        if tapped { return "Tapped. Waiting for everyone else." }
        switch store.signal {
        case .wait: return "Wait"
        case .decoy: return "Not yet"
        case .go: return "Tap now"
        }
    }
}

/// The target: rings round a core that breathes while you wait, a turning
/// hazard ring on amber, and shock rings out from the centre on green. One
/// Canvas, redrawn by the timeline only while there is something moving.
struct TapDuelArena: View {
    let mood: TapDuelMood
    let ink: Color
    /// False under Reduce Motion and once I have tapped: the arena holds still.
    let animate: Bool

    @State private var wentGreen: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animate)) { timeline in
            let now = timeline.date
            let burst: Double? = wentGreen.map { now.timeIntervalSince($0) }
            let seconds = now.timeIntervalSinceReferenceDate
            Canvas { context, size in
                TapDuelArena.draw(&context, size: size, mood: mood, ink: ink, t: seconds, burst: burst)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: mood) { _, next in
            wentGreen = next == .go ? Date() : nil
        }
    }

    static func draw(_ context: inout GraphicsContext, size: CGSize, mood: TapDuelMood, ink: Color,
                     t: Double, burst: Double?) {
        let cx = Double(size.width) / 2
        let cy = Double(size.height) / 2
        let base = Double(min(size.width, size.height)) * 0.3

        // Three still rings, fading outwards; they breathe while waiting.
        for k in 0..<3 {
            let breathe = mood == .wait ? sin(t * 2.2 - Double(k) * 0.7) * 5 : 0
            let r = base * (1.15 + Double(k) * 0.32) + breathe
            context.stroke(circle(cx, cy, r), with: .color(ink.opacity(0.16 - Double(k) * 0.04)), lineWidth: 2)
        }

        // The core.
        let glow: Double
        switch mood {
        case .wait: glow = 0.07 + 0.05 * (sin(t * 2.2) + 1) / 2
        case .go, .tapped: glow = 0.16
        case .decoy, .early: glow = 0.12
        }
        context.fill(circle(cx, cy, base), with: .color(ink.opacity(glow)))
        context.stroke(circle(cx, cy, base), with: .color(ink.opacity(0.28)), lineWidth: 3)

        // Amber: a dashed ring that turns — "this is not it".
        if mood == .decoy {
            // The phase wraps at one dash period: `t` is seconds since 2001,
            // and a phase in the billions loses its precision on the GPU.
            let phase = (t * 60).truncatingRemainder(dividingBy: 28)
            let style = StrokeStyle(lineWidth: 7, lineCap: .round, dash: [16, 12], dashPhase: CGFloat(phase))
            context.stroke(circle(cx, cy, base * 1.15), with: .color(ink.opacity(0.55)), style: style)
        }

        // Green: three shock rings out from the core, gone inside a second.
        if mood == .go, let burst {
            for k in 0..<3 {
                let age = burst - Double(k) * 0.12
                guard age > 0, age < 0.8 else { continue }
                let r = base + age * 700
                let alpha = 0.55 * (1 - age / 0.8)
                context.stroke(circle(cx, cy, r), with: .color(ink.opacity(alpha)), lineWidth: 10)
            }
        }
    }

    private static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }
}

/// A valid tap's time, large, with its word and where it sits from quick to slow.
struct TapDuelReactionReadout: View {
    let ms: Int
    let ink: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(ms)")
                    .font(SR.Text.hero(64))
                    .monospacedDigit()
                Text("ms")
                    .font(SR.Text.display(24))
            }
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            Text(ms < TapTiming.anticipationMs ? "Too quick to count" : TapDuelRating.label(ms: ms, floor: TapTiming.anticipationMs))
                .font(SR.Text.display(22))
                .foregroundStyle(ink.opacity(0.9))
            TapDuelMeter(share: TapDuelRating.meter(ms: ms, floor: TapTiming.anticipationMs), ink: ink)
                .frame(maxWidth: 260)
        }
    }
}

/// Quick on the left, slow on the right, and a dot where this tap landed.
struct TapDuelMeter: View {
    let share: Double
    let ink: Color

    var body: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(ink.opacity(0.22))
                .frame(height: 10)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Circle()
                            .fill(ink)
                            .frame(width: 18, height: 18)
                            .offset(x: (geo.size.width - 18) * CGFloat(share), y: -4)
                    }
                }
            HStack {
                Text("QUICK")
                Spacer()
                Text("SLOW")
            }
            .font(SR.Text.label())
            .tracking(1.2)
            .foregroundStyle(ink.opacity(0.7))
        }
    }
}

/// One pip a round: done, this one (longer), still to come.
struct TapDuelRoundPips: View {
    let current: Int
    let total: Int
    let ink: Color

    var body: some View {
        if total > 1 && total <= 15 {
            HStack(spacing: 6) {
                ForEach(1...total, id: \.self) { n in
                    Capsule()
                        .fill(ink.opacity(n <= current ? 0.9 : 0.25))
                        .frame(width: n == current ? 26 : 12, height: 6)
                }
            }
        }
    }
}

/// A full-screen touch target that reports each touch's own timestamp —
/// `UITouch.timestamp`, on the same monotonic clock as `CACurrentMediaTime`
/// and the display link. A SwiftUI gesture would report when SwiftUI got
/// round to it, a frame or more later.
struct TapSurface: UIViewRepresentable {
    let label: String
    let onTouch: (Double) -> Void

    func makeUIView(context: Context) -> TapSurfaceView {
        let view = TapSurfaceView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        view.isAccessibilityElement = true
        view.accessibilityTraits = [.button, .allowsDirectInteraction]
        return view
    }

    func updateUIView(_ view: TapSurfaceView, context: Context) {
        view.onTouch = onTouch
        view.accessibilityLabel = label
    }
}

final class TapSurfaceView: UIView {
    var onTouch: ((Double) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first { onTouch?(touch.timestamp) }
    }

    /// VoiceOver's double-tap. Timed now: there is no hardware touch to read.
    override func accessibilityActivate() -> Bool {
        onTouch?(CACurrentMediaTime())
        return true
    }
}

// MARK: - Result

struct TapDuelResult: View {
    let room: GameRoom
    @ObservedObject var store: TapDuelStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Round \(room.round?.number ?? 0) of \(room.rounds)", title: title)
                if room.me?.joined == true {
                    TapDuelMyTime(room: room)
                }
                TapDuelTimes(room: room)
                TapDuelNextLine(room: room, store: store)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("tapduel-result")
        .onAppear {
            if !room.solo, let winner = room.round?.winnerId, winner == room.meId { SRHaptic.ok() }
        }
    }

    private var title: String {
        guard let winner = room.round?.winnerId else {
            return room.solo ? "No time this round" : "Nobody took it"
        }
        if room.solo { return mineText ?? "Round done" }
        return winner == room.meId ? "You took it" : "\(room.name(of: winner)) took it"
    }

    private var mineText: String? {
        guard let mine = room.round?.response(for: room.meId) else { return nil }
        if mine.early { return "False start" }
        return mine.reactionMs.map { "\($0) ms" }
    }
}

/// My tap this round, as the one big figure: the time and its word, a false
/// start, or no tap at all. A crown when it took the round.
struct TapDuelMyTime: View {
    let room: GameRoom
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(tone)
                Image(systemName: icon)
                    .font(SR.Text.title(26))
                    // The ground token, not white: the fills lift in dark mode
                    // and carry dark type there.
                    .foregroundStyle(SR.paper)
            }
            .frame(width: 64, height: 64)
            .scaleEffect(shown ? 1 : 0.5)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(won ? "FASTEST THIS ROUND" : "YOUR TAP")
                    .font(SR.Text.label())
                    .tracking(1.4)
                    .foregroundStyle(won ? SR.accent : SR.inkMuted)
                Text(figure)
                    .font(SR.Text.hero(40))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let word {
                    Text(word)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .fill(won ? SR.accent.opacity(0.12) : Color.clear)
        )
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("tapduel-my-time")
        .onAppear {
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { shown = true }
            }
        }
    }

    private var mine: GameResponse? { room.round?.response(for: room.meId) }
    private var won: Bool { !room.solo && room.round?.winnerId == room.meId }

    private var figure: String {
        guard let mine else { return "No tap" }
        if mine.early { return "False start" }
        return mine.reactionMs.map { "\($0) ms" } ?? "—"
    }

    private var word: String? {
        guard let mine, !mine.early, let ms = mine.reactionMs else {
            return mine?.early == true ? "Tapped before green" : "The round closed first"
        }
        return TapDuelRating.label(ms: ms, floor: TapTiming.anticipationMs)
    }

    private var icon: String {
        guard let mine else { return "hourglass" }
        if mine.early { return "xmark" }
        return won ? "crown.fill" : "bolt.fill"
    }

    private var tone: Color {
        guard let mine else { return SR.inkMuted }
        if mine.early { return SR.error }
        return won ? SR.accent : SR.good
    }

    private var spoken: String {
        var parts = ["Your tap: \(figure)"]
        if let word { parts.append(word) }
        if won { parts.append("fastest this round") }
        return parts.joined(separator: ", ")
    }
}

/// Everyone's time this round, fastest first, with the running score — and
/// each time drawn as a bar on one axis, so "how close was it" is a glance.
struct TapDuelTimes: View {
    let room: GameRoom
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, player in
                if index > 0 { Divider().overlay(SR.divider) }
                row(player)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
        .onAppear {
            if reduceMotion {
                grown = true
            } else {
                withAnimation(.easeOut(duration: 0.7).delay(0.15)) { grown = true }
            }
        }
    }

    private func row(_ player: GamePlayer) -> some View {
        let won = room.round?.winnerId == player.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(player.name + (player.id == room.meId ? " (you)" : ""))
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                if won {
                    Image(systemName: "crown.fill")
                        .font(SR.Text.label(13))
                        .foregroundStyle(SR.accent)
                        .accessibilityLabel("Won the round")
                }
                Spacer(minLength: 8)
                Text(time(for: player))
                    .font(SR.Text.mono(15))
                    .foregroundStyle(won ? SR.accent : (early(player) ? SR.error : SR.inkSecondary))
                Text("\(player.score)")
                    .font(SR.Text.display(20))
                    .foregroundStyle(SR.ink)
                    .frame(minWidth: 28, alignment: .trailing)
                    .accessibilityLabel("\(player.score) points")
            }
            if let ms = reaction(player) {
                bar(share: TapDuelRating.share(ms: ms, axis: axis), won: won)
            }
        }
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func bar(share: Double, won: Bool) -> some View {
        Capsule()
            .fill(SR.line.opacity(0.6))
            .frame(height: 8)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(won ? SR.accent : SR.inkSecondary.opacity(0.7))
                        .frame(width: max(8, geo.size.width * CGFloat(grown ? share : 0)))
                }
            }
            .accessibilityHidden(true)
    }

    private var rows: [GamePlayer] {
        room.playing.sorted { a, b in sortKey(a) < sortKey(b) }
    }

    private var axis: Int {
        TapDuelRating.axisMs(times: rows.compactMap { reaction($0) })
    }

    private func reaction(_ player: GamePlayer) -> Int? {
        guard let response = room.round?.response(for: player.id), !response.early else { return nil }
        return response.reactionMs
    }

    private func early(_ player: GamePlayer) -> Bool {
        room.round?.response(for: player.id)?.early == true
    }

    private func sortKey(_ player: GamePlayer) -> Int {
        guard let response = room.round?.response(for: player.id) else { return Int.max }
        if response.early { return Int.max - 1 }
        return response.reactionMs ?? Int.max - 2
    }

    private func time(for player: GamePlayer) -> String {
        guard let response = room.round?.response(for: player.id) else { return "No tap" }
        if response.early { return "False start" }
        return response.reactionMs.map { "\($0) ms" } ?? "—"
    }
}

/// "Round 3 in 2…", from the result's deadline when the room carries one.
struct TapDuelNextLine: View {
    let room: GameRoom
    @ObservedObject var store: TapDuelStore

    var body: some View {
        if let round = room.round {
            if round.number >= room.rounds {
                line("Final standings in a moment.", icon: "flag.checkered")
            } else if let end = room.phaseEndsAt {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    line(text(next: round.number + 1, end: end), icon: "timer")
                }
            } else {
                line("Round \(round.number + 1) in a moment.", icon: "timer")
            }
        }
    }

    private func text(next: Int, end: Double) -> String {
        guard let now = store.serverNow() else { return "Round \(next) in a moment." }
        let left = GameCountdown.secondsLeft(until: end, atServer: now)
        return left > 0 ? "Round \(next) in \(left)…" : "Round \(next) in a moment."
    }

    private func line(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(SR.Text.mono(14))
            .foregroundStyle(SR.inkMuted)
            .monospacedDigit()
    }
}

// MARK: - Finished

struct TapDuelFinished: View {
    let room: GameRoom
    @ObservedObject var store: TapDuelStore
    let done: () -> Void
    @State private var note: QuickRoomBestNote?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Tap Duel · final", title: title, strap: strap)
                GameRecordLine(room: room)
                if !room.solo && standings.count >= 2 {
                    QuickRoomPodium(room: room, figure: { GameResults.count($0.score, "round", "rounds") })
                }
                if let note, mine != nil {
                    QuickRoomBestCard(title: "Your fastest tap at \(GameDifficulty.label(for: room.difficulty).lowercased())",
                                      value: note.best.map { "\($0) ms" },
                                      isNew: note.isNew,
                                      previous: note.previous.map { "was \($0) ms" },
                                      id: "tapduel-best")
                }
                standingsCard
                buttons
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .overlay {
            if celebrate { QuickRoomConfetti() }
        }
        .onAppear {
            if room.winnerIds.contains(room.meId) { SRHaptic.ok() }
            recordBest()
        }
    }

    private var standingsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(standings.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(SR.divider) }
                standingRow(index: index, row: row)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
        .accessibilityIdentifier("tapduel-standings")
    }

    private func standingRow(index: Int, row: GameStanding) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(SR.Text.display(26))
                .foregroundStyle(room.winnerIds.contains(row.id) ? SR.accent : SR.inkGhost)
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name + (row.id == room.meId ? " (you)" : ""))
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(detail(row))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !room.solo {
                Text("\(row.score)")
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                    .accessibilityLabel("\(row.score) rounds")
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            if room.isHost {
                Button {
                    SRHaptic.tap()
                    Task { await store.act("again") }
                } label: {
                    SRButtonLabel(title: "Play again", icon: "arrow.counterclockwise", fill: true)
                        .frame(minHeight: 56)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(store.busy)
                .accessibilityIdentifier("tapduel-again")
            }
            Button { done() } label: {
                SRButtonLabel(title: "Done", fill: true)
                    .frame(minHeight: 56)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("tapduel-done")
        }
    }

    private var standings: [GameStanding] { room.standings ?? [] }

    private var mine: GameStanding? { standings.first { $0.id == room.meId } }

    /// Confetti for a win against somebody, or a new best on my own.
    private var celebrate: Bool {
        (!room.solo && room.winnerIds.contains(room.meId)) || note?.isNew == true
    }

    private func recordBest() {
        guard note == nil, let mine else { return }
        let signature = standings
            .map { "\($0.id):\($0.score):\($0.bestMs ?? -1):\($0.avgMs ?? -1):\($0.falseStarts)" }
            .joined(separator: ",")
        // The last round's GO instant tells two games in one room apart.
        let lastGo = Int(room.round?.goAt ?? 0)
        note = QuickRoomBestStore.tapDuel.record(mine.bestMs, difficulty: room.difficulty,
                                                 token: "\(room.id)|\(lastGo)|\(signature)")
    }

    private var title: String {
        if room.solo { return "Your times" }
        let names = room.winnerIds.map { $0 == room.meId ? "You" : room.name(of: $0) }
        switch names.count {
        case 0: return "No winner"
        case 1: return names[0] == "You" ? "You win" : "\(names[0]) wins"
        default: return "\(GameNames.list(names)) tie"
        }
    }

    private var strap: String? {
        room.isHost ? nil : "Only \(room.host?.name ?? "the host") can start another round of this one."
    }

    private func detail(_ row: GameStanding) -> String {
        var parts: [String] = []
        if let best = row.bestMs { parts.append("best \(best) ms") }
        if let avg = row.avgMs { parts.append("avg \(avg) ms") }
        if row.falseStarts > 0 { parts.append(row.falseStarts == 1 ? "1 false start" : "\(row.falseStarts) false starts") }
        return parts.isEmpty ? "no valid taps" : parts.joined(separator: " · ")
    }
}
