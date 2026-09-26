import SwiftUI
import UIKit

/// One Sequence Memory room, from lobby to the last one standing.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`).
/// A round is one screen through both its halves: the grid flashes the
/// sequence in `show` (in sync with every other phone, off the server's clock)
/// and takes the player's taps in `input`. Every tile has a colour AND a
/// symbol and a number, so the game never depends on telling colours apart.
struct SequenceMemoryScreen: View {
    let roomId: String
    @StateObject private var store: SequenceMemoryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: SequenceMemoryStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Sequence Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar(immersive ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(immersive)
            .onAppear { store.open() }
            .onDisappear { store.close() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.open() } else if phase == .background { store.close() }
            }
            .overlay(alignment: .bottom) {
                if let message = store.message, !immersive { SRBanner(text: message) }
            }
    }

    private var immersive: Bool {
        guard !store.ended, let phase = store.room?.phase else { return false }
        return phase == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "memory-ended", done: { dismiss() })
        } else if let room = store.room {
            switch room.phase {
            case .lobby, .unknown, .armed, .playing, .question, .reveal:
                GameLobby(room: room, store: store, prefix: "memory", done: { dismiss() })
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Watch the tiles, then tap them back in order. One more each round.",
                                  id: "memory-countdown")
            case .show, .input:
                if let round = room.memory {
                    SequencePlay(room: room, round: round, store: store)
                } else {
                    waiting
                }
            case .result:
                if let round = room.memory {
                    SequenceResult(room: room, round: round, store: store)
                } else {
                    waiting
                }
            case .finished:
                SequenceFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "memory-ended", done: { dismiss() })
            }
        } else {
            waiting
        }
    }

    private var waiting: some View {
        ProgressView()
            .tint(SR.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .srPaper()
    }
}

// MARK: - Tiles

extension SequencePalette {
    /// Nine SR tokens: the six strong ones, then three light ones — so a
    /// 3×3 grid has lightness steps as well as hues.
    static func fill(_ tile: Int) -> Color {
        let fills: [Color] = [SR.accent, SR.accentInk, SR.good, SR.warn, SR.error, SR.inkSecondary,
                              SR.accentOnDark, SR.accentInkOnDark, SR.goodOnDark]
        return fills[tile % fills.count]
    }

    /// The symbol's colour on its fill: paper on the strong ones, ink on the light.
    static func mark(_ tile: Int) -> Color {
        switch tile % 9 {
        case 3, 6, 7, 8: return SR.ink
        default: return SR.paper
        }
    }
}

/// One tile: a colour, a symbol, a number. Lit, it is full strength, larger
/// and ringed; otherwise it rests dimmed.
struct SequenceTile: View {
    let tile: Int
    let lit: Bool
    /// Dimmed while resting (the show); full while taking taps.
    let resting: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SequencePalette.fill(tile))
                .opacity(lit ? 1 : (resting ? 0.38 : 0.82))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(lit ? SR.ink : Color.clear, lineWidth: 4)
            Image(systemName: SequencePalette.symbol(tile))
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(SequencePalette.mark(tile))
                .opacity(lit ? 1 : 0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("\(tile + 1)")
                .font(SR.Text.label(13))
                .foregroundStyle(SequencePalette.mark(tile))
                .padding(10)
        }
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(lit ? 1.05 : 1)
        .shadow(color: lit ? SequencePalette.fill(tile).opacity(0.6) : .clear, radius: lit ? 14 : 0)
        .animation(.easeOut(duration: 0.08), value: lit)
    }
}

/// The grid: 2×2, 2×3 or 3×3.
struct SequenceGrid: View {
    let tiles: Int
    let lit: Int?
    let resting: Bool
    let enabled: Bool
    let tap: (Int) -> Void

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: SequenceSchedule.columns(tiles: tiles))
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<tiles, id: \.self) { tile in
                Button {
                    tap(tile)
                } label: {
                    SequenceTile(tile: tile, lit: lit == tile, resting: resting)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .accessibilityLabel(SequencePalette.spoken(tile))
                .accessibilityAddTraits(lit == tile ? [.isSelected] : [])
                .accessibilityIdentifier("memory-tile-\(tile)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("memory-grid")
    }
}

// MARK: - A round

struct SequencePlay: View {
    let room: GameRoom
    let round: SequenceRound
    @ObservedObject var store: SequenceMemoryStore

    private var me: GamePlayer? { room.me }
    private var inGame: Bool { me?.joined == true && me?.alive == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                SequenceGrid(
                    tiles: room.tiles,
                    lit: store.lit ?? store.pressed,
                    resting: !store.inputOpen,
                    enabled: store.canTap,
                    tap: { store.tap($0) }
                )
                if store.inputOpen && inGame {
                    SequenceTapsRow(round: round, taps: store.taps?.taps ?? [])
                    tapControls
                }
                SequencePlayers(room: room, round: round, showAnswered: store.inputOpen)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier(store.inputOpen ? "memory-input" : "memory-show")
        .onChange(of: store.inputOpen) { _, open in
            if open && inGame {
                UIAccessibility.post(notification: .announcement, argument: "Your turn. \(round.length) taps.")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ROUND \(round.number) · \(round.length) STEPS")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text(headline)
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
                    .accessibilityIdentifier("memory-headline")
            }
            Spacer(minLength: 8)
            if store.inputOpen {
                SequenceWindowClock(round: round, store: store)
            } else if let step = store.litStep {
                Text("\(step)/\(round.length)")
                    .font(SR.Text.figure(24))
                    .foregroundStyle(SR.inkMuted)
                    .monospacedDigit()
                    .accessibilityLabel("Flash \(step) of \(round.length)")
            }
        }
    }

    private var headline: String {
        guard me?.joined == true else { return "Watching" }
        guard me?.alive == true else { return "You’re out — watching" }
        if !store.inputOpen { return "Watch…" }
        if store.sent { return "Sent. Waiting for the others." }
        if store.sending { return "Sending…" }
        let count = store.taps?.taps.count ?? 0
        return "Your turn · \(count) of \(round.length)"
    }

    private var tapControls: some View {
        HStack(spacing: 10) {
            Button { store.undo() } label: {
                SRButtonLabel(title: "Undo", icon: "arrow.uturn.backward", fill: true)
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(!(store.taps?.canUndo ?? false) || !store.canTap)
            .accessibilityIdentifier("memory-undo")
            if store.sendFailed {
                Button { store.send() } label: {
                    SRButtonLabel(title: "Send again", icon: "arrow.clockwise", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("memory-resend")
            }
        }
    }
}

/// The taps so far, as the tiles' symbols, and empty slots for the rest.
struct SequenceTapsRow: View {
    let round: SequenceRound
    let taps: [Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(0..<round.length, id: \.self) { i in
                    if i < taps.count {
                        Image(systemName: SequencePalette.symbol(taps[i]))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(SequencePalette.mark(taps[i]))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(SequencePalette.fill(taps[i])))
                    } else {
                        Circle()
                            .strokeBorder(SR.line, lineWidth: 1.5)
                            .frame(width: 30, height: 30)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(taps.isEmpty ? "No taps yet" : "Tapped: " + taps.map { "tile \($0 + 1)" }.joined(separator: ", "))
        .accessibilityIdentifier("memory-taps")
    }
}

/// Seconds left in the input window.
struct SequenceWindowClock: View {
    let round: SequenceRound
    @ObservedObject var store: SequenceMemoryStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let left = secondsLeft
            Text(left.map { "\($0)s" } ?? "–")
                .font(SR.Text.figure(24))
                .foregroundStyle((left ?? 99) <= 2 ? SR.error : SR.ink)
                .monospacedDigit()
                .accessibilityLabel(left.map { "\($0) seconds left" } ?? "Time left unknown")
                .accessibilityIdentifier("memory-timer")
        }
    }

    private var secondsLeft: Int? {
        guard let now = store.serverNow() else { return nil }
        return GameCountdown.secondsLeft(until: round.inputEndsAt, atServer: now)
    }
}

/// Everyone still in, everyone out, and — while the window is open — who has
/// sent their attempt.
struct SequencePlayers: View {
    let room: GameRoom
    let round: SequenceRound
    let showAnswered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Players", trailing: "\(alive.count) in")
            VStack(spacing: 0) {
                ForEach(Array(seated.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { Divider().overlay(SR.divider) }
                    HStack(spacing: 12) {
                        GameInitial(name: player.name, filled: player.alive, tone: SR.accentInk, side: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name + (player.id == room.meId ? " (you)" : ""))
                                .font(SR.Text.title())
                                .foregroundStyle(player.alive ? SR.ink : SR.inkMuted)
                            Text(detail(player))
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                        }
                        Spacer(minLength: 8)
                        status(player)
                    }
                    .frame(minHeight: SR.tapTarget)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("memory-player-\(player.id)")
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("memory-players")
    }

    /// Everyone seated this game; alive first.
    private var seated: [GamePlayer] {
        let list = room.players.filter { $0.seated || $0.joined }
        return list.filter(\.alive) + list.filter { !$0.alive }
    }

    private var alive: [GamePlayer] { room.players.filter(\.alive) }

    private func detail(_ player: GamePlayer) -> String {
        if !player.alive, let out = player.outRound { return "out in round \(out) · best \(player.best)" }
        return player.best > 0 ? "best \(player.best)" : "no rounds yet"
    }

    @ViewBuilder
    private func status(_ player: GamePlayer) -> some View {
        if !player.alive {
            SRGlassChip(text: "Out", tone: SR.inkMuted)
        } else if showAnswered, round.answeredIds.contains(player.id) {
            Label("Sent", systemImage: "checkmark.circle.fill")
                .font(SR.Text.label())
                .foregroundStyle(SR.good)
        } else if showAnswered {
            Text("TAPPING")
                .font(SR.Text.label())
                .foregroundStyle(SR.inkSecondary)
        } else {
            SRGlassChip(text: "In", tone: SR.good)
        }
    }
}

// MARK: - Result

struct SequenceResult: View {
    let room: GameRoom
    let round: SequenceRound
    @ObservedObject var store: SequenceMemoryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Round \(round.number) · \(round.length) steps", title: title)

                if let sequence = round.sequence {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "The sequence")
                        SequenceSymbols(tiles: sequence)
                            .accessibilityIdentifier("memory-sequence")
                        if let mine = round.attempt(of: room.meId), let taps = mine.taps {
                            SRSectionLabel(text: mine.correct ? "Yours — right" : "Yours")
                            SequenceSymbols(tiles: taps)
                        }
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, player in
                        if index > 0 { Divider().overlay(SR.divider) }
                        let survived = round.survivorIds?.contains(player.id) == true
                        HStack(spacing: 12) {
                            Image(systemName: survived ? "checkmark.circle.fill" : "xmark.circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(survived ? SR.good : SR.inkGhost)
                                .accessibilityHidden(true)
                            Text(player.name + (player.id == room.meId ? " (you)" : ""))
                                .font(SR.Text.title())
                                .foregroundStyle(SR.ink)
                            Spacer(minLength: 8)
                            Text(line(player, survived: survived))
                                .font(SR.Text.mono())
                                .foregroundStyle(survived ? SR.good : SR.inkMuted)
                        }
                        .frame(minHeight: SR.tapTarget)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("memory-result-\(player.id)")
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 6)
                .srGlassCard(.paper)
                .accessibilityIdentifier("memory-survivors")

                Text(next)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("memory-result")
    }

    /// Who was in this round: everyone with an attempt row.
    private var rows: [GamePlayer] {
        let ids = Set((round.attempts ?? []).map(\.playerId))
        return room.players.filter { ids.contains($0.id) }
    }

    private var title: String {
        let survivors = round.survivorIds ?? []
        if survivors.contains(room.meId) { return "You got it" }
        if round.attempt(of: room.meId) != nil { return "You’re out" }
        if survivors.isEmpty { return "Everyone’s out" }
        return "\(GameNames.list(survivors.map { room.name(of: $0) })) still in"
    }

    private func line(_ player: GamePlayer, survived: Bool) -> String {
        if survived { return "through" }
        return round.attempt(of: player.id)?.taps == nil ? "no answer" : "wrong"
    }

    private var next: String {
        (round.survivorIds ?? []).isEmpty || round.length >= room.maxLength
            ? "Final standings in a moment."
            : "Round \(round.number + 1) — \(round.length + 1) steps — in a moment."
    }
}

/// A sequence as a row of the tiles' symbols.
struct SequenceSymbols: View {
    let tiles: [Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    Image(systemName: SequencePalette.symbol(tile))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(SequencePalette.mark(tile))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(SequencePalette.fill(tile)))
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tiles.map { "tile \($0 + 1)" }.joined(separator: ", "))
    }
}

// MARK: - Finished

struct SequenceFinished: View {
    let room: GameRoom
    @ObservedObject var store: SequenceMemoryStore
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Sequence Memory · final",
                             title: GameResults.title(room, solo: soloTitle, none: "Nobody made it"),
                             strap: GameResults.strap(room))

                GameStandingsCard(
                    room: room,
                    label: room.solo ? "Your game" : "Standings",
                    id: "memory-standings",
                    detail: detail,
                    figure: { (text: "\($0.best)", spoken: "best length \($0.best)") }
                )

                GameFinishedButtons(room: room, store: store, prefix: "memory", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("memory-finished")
        .onAppear { if room.winnerIds.contains(room.meId) { SRHaptic.ok() } }
    }

    private var soloTitle: String {
        let best = room.standings?.first { $0.id == room.meId }?.best ?? room.me?.best ?? 0
        return best > 0 ? "Best: \(best) steps" : "Not this time"
    }

    private func detail(_ row: GameStanding) -> String {
        let rounds = GameResults.count(row.roundsSurvived, "round", "rounds")
        if let out = row.outRound { return "\(rounds) survived · out in round \(out)" }
        return "\(rounds) survived · still standing"
    }
}
