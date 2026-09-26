import SwiftUI
import UIKit

/// One Tap Duel room, from lobby to standings.
///
/// Countdown and armed take the whole screen — no bars, no tab bar — because
/// the armed phase IS the button, and a bar at the top is a place a thumb can
/// land and not be counted. Every other phase is an ordinary SR page.
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
            SREmpty(
                title: "This game has ended",
                icon: "flag.checkered",
                message: "Rooms last a few minutes. Start another from Games.",
                actionLabel: "Done",
                action: { dismiss() }
            )
            .frame(maxHeight: .infinity)
            .srPaper()
            .accessibilityIdentifier("tapduel-ended")
        } else if let room = store.room {
            switch room.phase {
            case .lobby, .unknown:
                TapDuelLobby(room: room, store: store, done: { dismiss() })
            case .countdown:
                TapDuelCountdown(room: room, store: store)
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

struct TapDuelLobby: View {
    let room: GameRoom
    @ObservedObject var store: TapDuelStore
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(
                    kicker: "Tap Duel · \(GameDifficulty.label(for: room.difficulty))",
                    title: room.isHost ? "Your game" : (room.host.map { "\($0.name)’s game" } ?? "A game"),
                    strap: strap
                )

                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: "Players", trailing: "\(room.playing.count) in")
                    VStack(spacing: 0) {
                        ForEach(Array(room.players.enumerated()), id: \.element.id) { index, player in
                            if index > 0 { Divider().overlay(SR.divider) }
                            HStack(spacing: 12) {
                                Text(player.name + (player.id == room.meId ? " (you)" : ""))
                                    .font(SR.Text.title())
                                    .foregroundStyle(player.joined ? SR.ink : SR.inkMuted)
                                if player.isHost {
                                    Text("HOST")
                                        .font(SR.Text.label())
                                        .tracking(1.2)
                                        .foregroundStyle(SR.accent)
                                }
                                Spacer(minLength: 8)
                                SRGlassChip(text: statusLabel(player.status), tone: statusTone(player.status))
                            }
                            .frame(minHeight: SR.tapTarget)
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("tapduel-player-\(player.id)")
                        }
                    }
                    .padding(.horizontal, SR.cardPadding)
                    .padding(.vertical, 6)
                    .srGlassCard(.paper)
                }

                if let closes = closesText {
                    Text(closes)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }

                VStack(spacing: 10) {
                    if room.isHost {
                        Button {
                            SRHaptic.tap()
                            Task { await store.act("start") }
                        } label: {
                            SRButtonLabel(title: "Start", icon: "play.fill", fill: true)
                        }
                        .srButton(.prominent)
                        .controlSize(.large)
                        .disabled(store.busy)
                        .accessibilityIdentifier("tapduel-start")
                    }
                    if room.me?.joined == true {
                        Button {
                            Task {
                                await store.act("leave")
                                done()
                            }
                        } label: {
                            SRButtonLabel(title: "Leave", fill: true)
                        }
                        .srButton(.regular)
                        .controlSize(.large)
                        .disabled(store.busy)
                        .accessibilityIdentifier("tapduel-leave")
                    } else if room.me?.status == "invited" {
                        HStack(spacing: 8) {
                            ProgressView().tint(SR.accent)
                            Text("Joining…").font(SR.Text.secondary()).foregroundStyle(SR.inkMuted)
                        }
                    } else {
                        Button { done() } label: { SRButtonLabel(title: "Done", fill: true) }
                            .srButton(.regular)
                            .controlSize(.large)
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("tapduel-lobby")
    }

    private var strap: String {
        if room.me?.status == "declined" || room.me?.status == "left" { return "You are not playing in this one." }
        if room.isHost {
            return room.solo
                ? "Just you. Start when you are ready."
                : "Start when everyone you want is in. Anyone still invited is left out."
        }
        return "Waiting for \(room.host?.name ?? "the host") to start."
    }

    /// "Lobby closes at 14:03", from the server's deadline on this phone's clock.
    private var closesText: String? {
        guard let end = room.phaseEndsAt, let now = store.serverNow() else { return nil }
        let at = Date().addingTimeInterval((end - now) / 1000)
        return "Lobby closes at \(at.formatted(date: .omitted, time: .shortened))"
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "joined": return "In"
        case "invited": return "Invited"
        case "declined": return "Declined"
        case "left": return "Left"
        default: return status
        }
    }

    private func statusTone(_ status: String) -> Color {
        switch status {
        case "joined": return SR.good
        case "invited": return SR.accentInk
        default: return SR.inkMuted
        }
    }
}

// MARK: - Countdown

struct TapDuelCountdown: View {
    let room: GameRoom
    @ObservedObject var store: TapDuelStore

    var body: some View {
        ZStack {
            SR.ink.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("GET READY")
                    .font(SR.Text.label(13))
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(SR.onInk(.label))
                TimelineView(.periodic(from: .now, by: 0.05)) { _ in
                    Text(figure)
                        .font(SR.Text.hero(150))
                        .foregroundStyle(SR.paper)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText(countsDown: true))
                        .accessibilityLabel(figure == "…" ? "Get ready" : "Starting in \(figure)")
                }
                Text("Wait for green. Tap early and the round is gone.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.onInk(.note))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SR.gutter)
            }
        }
        .accessibilityIdentifier("tapduel-countdown")
    }

    private var figure: String {
        guard let end = room.phaseEndsAt, let now = store.serverNow() else { return "…" }
        let left = GameCountdown.secondsLeft(until: end, atServer: now)
        return left > 0 ? "\(min(left, 3))" : "…"
    }
}

// MARK: - Armed

struct TapDuelArmed: View {
    let room: GameRoom
    @ObservedObject var store: TapDuelStore

    var body: some View {
        ZStack {
            ground.ignoresSafeArea()
            VStack(spacing: 14) {
                if let round = room.round {
                    Text("ROUND \(round.number) OF \(room.rounds)")
                        .font(SR.Text.label(13))
                        .tracking(SR.inkKickerTracking)
                        .foregroundStyle(ink.opacity(0.7))
                }
                Spacer()
                Text(headline)
                    .font(SR.Text.hero(72))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                if let after = afterTap {
                    Text(after)
                        .font(SR.Text.display(26))
                        .foregroundStyle(ink.opacity(0.85))
                }
                Spacer()
                Text(footer)
                    .font(SR.Text.mono(13))
                    .foregroundStyle(ink.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 40)
            .padding(.horizontal, SR.gutter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            // The whole screen is the button. UIKit underneath so the touch
            // keeps its own hardware timestamp.
            TapSurface(label: accessibilityText) { store.tap(at: $0) }
                .ignoresSafeArea()
                .accessibilityIdentifier("tapduel-surface")
        }
    }

    private var tapped: Bool {
        guard let round = room.round else { return false }
        return store.hasTapped(round: round.number)
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

    private var afterTap: String? {
        guard let tap = store.myTap else { return nil }
        switch tap {
        case .early: return "False start"
        case .reaction(let ms): return ms < TapTiming.anticipationMs ? "\(ms) ms — too quick to count" : "\(ms) ms"
        }
    }

    private var footer: String {
        tapped ? "Waiting for everyone else." : "Tap anywhere when it turns green."
    }

    private var ground: Color {
        if store.myTap == .early { return SR.error }
        switch store.signal {
        case .wait: return SR.ink
        case .decoy: return SR.warn
        case .go: return SR.good
        }
    }

    private var ink: Color {
        store.signal == .decoy && store.myTap != .early ? SR.ink : SR.paper
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
                TapDuelTimes(room: room)
                if let next = nextText {
                    Text(next).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("tapduel-result")
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

    private var nextText: String? {
        guard let round = room.round, round.number < room.rounds else { return nil }
        return "Round \(round.number + 1) in a moment."
    }
}

/// Everyone's time this round, fastest first, with the running score.
struct TapDuelTimes: View {
    let room: GameRoom

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, player in
                if index > 0 { Divider().overlay(SR.divider) }
                let won = room.round?.winnerId == player.id
                HStack(spacing: 12) {
                    Text(player.name + (player.id == room.meId ? " (you)" : ""))
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    if won {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SR.accent)
                            .accessibilityLabel("Won the round")
                    }
                    Spacer(minLength: 8)
                    Text(time(for: player))
                        .font(SR.Text.mono(15))
                        .foregroundStyle(won ? SR.accent : SR.inkSecondary)
                    Text("\(player.score)")
                        .font(SR.Text.display(20))
                        .foregroundStyle(SR.ink)
                        .frame(minWidth: 28, alignment: .trailing)
                        .accessibilityLabel("\(player.score) points")
                }
                .frame(minHeight: SR.tapTarget)
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
    }

    private var rows: [GamePlayer] {
        room.playing.sorted { a, b in sortKey(a) < sortKey(b) }
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

// MARK: - Finished

struct TapDuelFinished: View {
    let room: GameRoom
    @ObservedObject var store: TapDuelStore
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Tap Duel · final", title: title, strap: strap)

                VStack(spacing: 0) {
                    ForEach(Array(standings.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider().overlay(SR.divider) }
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
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 6)
                .srGlassCard(.paper)
                .accessibilityIdentifier("tapduel-standings")

                VStack(spacing: 10) {
                    if room.isHost {
                        Button {
                            SRHaptic.tap()
                            Task { await store.act("again") }
                        } label: {
                            SRButtonLabel(title: "Play again", icon: "arrow.counterclockwise", fill: true)
                        }
                        .srButton(.prominent)
                        .controlSize(.large)
                        .disabled(store.busy)
                        .accessibilityIdentifier("tapduel-again")
                    }
                    Button { done() } label: { SRButtonLabel(title: "Done", fill: true) }
                        .srButton(.regular)
                        .controlSize(.large)
                        .accessibilityIdentifier("tapduel-done")
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .onAppear { if room.winnerIds.contains(room.meId) { SRHaptic.ok() } }
    }

    private var standings: [GameStanding] { room.standings ?? [] }

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
