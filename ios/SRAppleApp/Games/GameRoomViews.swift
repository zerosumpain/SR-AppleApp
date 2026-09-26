import SwiftUI

// The parts of a room every game shares: the route that picks the game's
// screen, the lobby, the 3-2-1, and the "this game has ended" page.

// MARK: - The route

/// One room, whichever game it is. The Games tab's stack pushes this for every
/// `GameRoomRef`; it hands over to the game's own screen.
///
/// A ref from a list knows its game. A bare id — a notification raised by an
/// older build — reads the room's snapshot once to find out, retrying a flaky
/// connection and giving up only on a room that has gone.
struct GameRoomScreen: View {
    let ref: GameRoomRef
    @State private var game: String?
    @State private var gone = false
    @Environment(\.dismiss) private var dismiss

    init(ref: GameRoomRef) {
        self.ref = ref
        _game = State(initialValue: ref.game)
    }

    var body: some View {
        if gone {
            GameEndedView(id: "game-ended", done: { dismiss() })
                .toolbar(.hidden, for: .tabBar)
        } else if let game {
            switch GameKind(rawValue: game) {
            case .tapDuel?:
                TapDuelScreen(roomId: ref.id)
            case .wordleRace?:
                WordleRaceScreen(roomId: ref.id)
            case .quizNight?:
                QuizNightScreen(roomId: ref.id)
            case .anagramBlitz?:
                AnagramBlitzScreen(roomId: ref.id)
            case .mathsSprint?:
                MathsSprintScreen(roomId: ref.id)
            case .sequenceMemory?:
                SequenceMemoryScreen(roomId: ref.id)
            case nil:
                SREmpty(
                    title: "\(GameNames.title(game)) needs a newer app",
                    icon: "arrow.down.app",
                    message: "This version of the app does not know that game yet.",
                    actionLabel: "Done",
                    action: { dismiss() }
                )
                .frame(maxHeight: .infinity)
                .srPaper()
                .toolbar(.hidden, for: .tabBar)
            }
        } else {
            ProgressView()
                .tint(SR.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .srPaper()
                .toolbar(.hidden, for: .tabBar)
                .task { await resolve() }
        }
    }

    private func resolve() async {
        var wait: UInt64 = 1
        while !Task.isCancelled {
            do {
                let envelope: GameRoomEnvelope = try await SiteClient.shared.send("api/native/games/\(ref.id)")
                game = envelope.room.game
                return
            } catch SiteError.status(let code, _) where code == 404 || code == 403 {
                gone = true
                return
            } catch {
                try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
                wait = min(wait * 2, 10)
            }
        }
    }
}

/// The room has gone: rooms last minutes, and a restart ends them.
struct GameEndedView: View {
    let id: String
    let done: () -> Void

    var body: some View {
        SREmpty(
            title: "This game has ended",
            icon: "flag.checkered",
            message: "Rooms last a few minutes. Start another from Games.",
            actionLabel: "Done",
            action: done
        )
        .frame(maxHeight: .infinity)
        .srPaper()
        .accessibilityIdentifier(id)
    }
}

// MARK: - Lobby

/// Who is in, who is invited, Start (the host) and Leave. The same for every
/// game; `prefix` keeps each game's accessibility ids its own.
struct GameLobby<Store: GameRoomStoring>: View {
    let room: GameRoom
    @ObservedObject var store: Store
    /// "tapduel", "wordle", "quiz".
    let prefix: String
    let done: () -> Void
    /// A game's own panel between the header and the players — Quiz Night's
    /// topic and "jkai is writing the questions…".
    var panel: AnyView? = nil
    /// Start is shown to the host but cannot be pressed yet.
    var startBlocked: Bool = false
    /// The host's Start is replaced by something in `panel`.
    var hidesStart: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(
                    kicker: "\(GameNames.title(room.game)) · \(GameDifficulty.label(for: room.difficulty))",
                    title: room.isHost ? "Your game" : (room.host.map { "\($0.name)’s game" } ?? "A game"),
                    strap: strap
                )

                if let panel { panel }

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
                            .accessibilityIdentifier("\(prefix)-player-\(player.id)")
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
                    if room.isHost && !hidesStart {
                        Button {
                            SRHaptic.tap()
                            Task { _ = await store.act("start") }
                        } label: {
                            SRButtonLabel(title: "Start", icon: "play.fill", fill: true)
                        }
                        .srButton(.prominent)
                        .controlSize(.large)
                        .disabled(store.busy || startBlocked)
                        .accessibilityIdentifier("\(prefix)-start")
                    }
                    if room.me?.joined == true {
                        Button {
                            Task {
                                _ = await store.act("leave")
                                done()
                            }
                        } label: {
                            SRButtonLabel(title: "Leave", fill: true)
                        }
                        .srButton(.regular)
                        .controlSize(.large)
                        .disabled(store.busy)
                        .accessibilityIdentifier("\(prefix)-leave")
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
        .accessibilityIdentifier("\(prefix)-lobby")
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

/// The 3-2-1, full screen on ink, before any game's play begins.
struct GameCountdownView<Store: GameRoomStoring>: View {
    let room: GameRoom
    @ObservedObject var store: Store
    /// One line under the figure: the rule that matters in the first second.
    let note: String
    let id: String

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
                Text(note)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.onInk(.note))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SR.gutter)
            }
        }
        .accessibilityIdentifier(id)
    }

    private var figure: String {
        guard let end = room.phaseEndsAt, let now = store.serverNow() else { return "…" }
        let left = GameCountdown.secondsLeft(until: end, atServer: now)
        return left > 0 ? "\(min(left, 3))" : "…"
    }
}
