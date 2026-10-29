import SwiftUI
import UIKit

/// One Sequence Memory room, from lobby to the last one standing.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`);
/// the lobby carries a how-to card with this phone's longest sequence. A round
/// is one screen through both its halves: the grid flashes the sequence in
/// `show` (in sync with every other phone, off the server's clock) and takes
/// the player's taps in `input`. A banner over the grid says which half it is
/// — dark "Watch", violet "Your turn" — with the flash count or a draining
/// clock beside it. Every tile has a colour AND a symbol and a number, so the
/// game never depends on telling colours apart.
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
            case .lobby, .unknown, .armed, .playing, .question, .reveal, .review:
                GameLobby(room: room, store: store, prefix: "memory", done: { dismiss() },
                          panel: AnyView(SequenceHowTo(room: room)))
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

// MARK: - Lobby

/// How to play, in the lobby, with this phone's longest sequence at this level.
struct SequenceHowTo: View {
    let room: GameRoom
    @State private var best: Int?
    @State private var played = 0

    var body: some View {
        QuickRoomHowTo(
            pitch: "Watch, remember, repeat",
            rules: [
                QuickRoomRule(icon: "eye.fill", text: "The tiles light up one at a time. Watch the order — every phone sees the same."),
                QuickRoomRule(icon: "hand.tap.fill", text: "When it says Your turn, tap the tiles back in the same order. Undo takes back the last tap."),
                QuickRoomRule(icon: "plus.circle.fill", text: "Get it right and the next round is one tile longer."),
                QuickRoomRule(icon: "person.fill.xmark", text: "One slip and you are out. The last one standing wins.")
            ],
            best: best.map { "Best \($0) steps" },
            played: played,
            id: "memory-howto"
        )
        .onAppear {
            let book = QuickRoomBestStore.memory
            best = book.best(difficulty: room.difficulty)
            played = book.gamesPlayed()
        }
    }
}

// MARK: - Tiles

extension SequencePalette {
    /// Nine SR tokens: the six strong ones, then three light ones — so a
    /// 3×3 grid has lightness steps as well as hues.
    static func fill(_ tile: Int) -> Color {
        // Fixed, not the mode-following tokens: in dark mode `SR.accent`
        // becomes `accentOnDark`, and two tiles would share a colour.
        let fills: [Color] = [Color(hex: SR.Fixed.accent), Color(hex: SR.Fixed.accentInk), Color(hex: SR.Fixed.good),
                              Color(hex: SR.Fixed.warn), Color(hex: SR.Fixed.error), Color(hex: SR.Fixed.inkSecondary),
                              SR.accentOnDark, SR.accentInkOnDark, SR.goodOnDark]
        return fills[tile % fills.count]
    }

    /// The symbol's colour on its fill: paper on the strong ones, ink on the light.
    static func mark(_ tile: Int) -> Color {
        switch tile % 9 {
        case 3, 6, 7, 8: return SR.band
        default: return SR.cream
        }
    }
}

/// One tile: a colour, a symbol, a number, with a sheen so it reads as a
/// button. Lit, it is full strength, larger, ringed twice and glowing;
/// otherwise it rests dimmed.
struct SequenceTile: View {
    let tile: Int
    let lit: Bool
    /// Dimmed while resting (the show); full while taking taps.
    let resting: Bool
    var symbolSize: CGFloat = 34

    var body: some View {
        let face = SequencePalette.fill(tile)
        let mark = SequencePalette.mark(tile)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(face)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(lit ? 0.38 : 0.22), Color.white.opacity(0), Color.black.opacity(0.14)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(lit ? 0.95 : 0.2), lineWidth: lit ? 4 : 1)
            Image(systemName: SequencePalette.symbol(tile))
                .font(.system(size: symbolSize, weight: .bold))
                .foregroundStyle(mark)
                .scaleEffect(lit ? 1.12 : 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("\(tile + 1)")
                .font(SR.Text.label(13))
                .foregroundStyle(mark)
                .padding(10)
        }
        .overlay {
            if lit {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .strokeBorder(SR.ink.opacity(0.85), lineWidth: 3)
                    .padding(-6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .opacity(lit ? 1 : (resting ? 0.42 : 0.95))
        .scaleEffect(lit ? 1.06 : 1)
        .shadow(color: lit ? face.opacity(0.75) : Color.black.opacity(0.10), radius: lit ? 18 : 4, y: lit ? 0 : 2)
        .animation(.easeOut(duration: 0.08), value: lit)
    }
}

/// The grid: 2×2, 2×3 or 3×3, never so wide on a big phone that the controls
/// fall off the screen.
struct SequenceGrid: View {
    let tiles: Int
    let lit: Int?
    let resting: Bool
    let enabled: Bool
    let tap: (Int) -> Void

    var body: some View {
        let count = SequenceSchedule.columns(tiles: tiles)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: count)
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(0..<tiles, id: \.self) { tile in
                Button {
                    tap(tile)
                } label: {
                    SequenceTile(tile: tile, lit: lit == tile, resting: resting, symbolSize: count == 2 ? 50 : 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuickRoomKeyStyle())
                .disabled(!enabled)
                .accessibilityLabel(SequencePalette.spoken(tile))
                .accessibilityAddTraits(lit == tile ? [.isSelected] : [])
                .accessibilityIdentifier("memory-tile-\(tile)")
            }
        }
        .frame(maxWidth: count == 2 ? 330 : 420)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("memory-grid")
    }
}

// MARK: - A round

/// The banner's colours: a dark slab to watch, violet for my turn, glass for
/// everything else. Fixed values, so cream type holds on them in dark mode.
enum SequenceBannerPaint {
    static var night: Color { Color(hex: SR.Fixed.ink) }
    static var violet: Color { Color(hex: SR.Fixed.accent) }
    static var cream: Color { Color(hex: SR.Fixed.paper) }
    static var amber: Color { Color(hex: SRPaint.current.palette.warn.dark) }
}

struct SequencePlay: View {
    let room: GameRoom
    let round: SequenceRound
    @ObservedObject var store: SequenceMemoryStore
    /// The furthest flash shown this round, so the pips stay lit between flashes.
    @State private var shownSteps = 0

    private var me: GamePlayer? { room.me }
    private var inGame: Bool { me?.joined == true && me?.alive == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                banner
                if !store.inputOpen {
                    SequenceShowPips(length: round.length, shown: shownSteps, lit: store.litStep)
                }
                SequenceGrid(
                    tiles: room.tiles,
                    lit: store.lit ?? store.pressed,
                    resting: !store.inputOpen,
                    enabled: store.canTap,
                    tap: { store.tap($0) }
                )
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
                SRHaptic.tap()
                UIAccessibility.post(notification: .announcement, argument: "Your turn. \(round.length) taps.")
            }
        }
        .onChange(of: store.litStep) { _, step in
            if let step, step > shownSteps { shownSteps = step }
        }
        .onChange(of: round.number) { _, _ in shownSteps = 0 }
    }

    // MARK: Banner

    private var banner: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(bannerInk.opacity(0.16))
                Image(systemName: bannerIcon)
                    .font(SR.Text.title(24))
                    .foregroundStyle(bannerInk)
                    .symbolEffect(.bounce, value: store.inputOpen)
            }
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("ROUND \(round.number) · \(round.length) STEPS")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(bannerInk.opacity(0.75))
                Text(headline)
                    .font(SR.Text.display(24))
                    .foregroundStyle(bannerInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("memory-headline")
            }
            Spacer(minLength: 8)
            bannerTrailing
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .fill(bannerFill)
        )
        .srGlassCard(.paper)
        .animation(.easeOut(duration: 0.25), value: store.inputOpen)
    }

    @ViewBuilder
    private var bannerTrailing: some View {
        if store.inputOpen {
            SequenceWindowClock(round: round, store: store, ink: bannerInk,
                                urgent: myTurn ? SequenceBannerPaint.amber : SR.error)
        } else if let step = store.litStep {
            Text("\(step)/\(round.length)")
                .font(SR.Text.figure(26))
                .foregroundStyle(bannerInk)
                .monospacedDigit()
                .accessibilityLabel("Flash \(step) of \(round.length)")
        }
    }

    /// Watching the show (and still in), or tapping now.
    private var watching: Bool { !store.inputOpen && inGame }
    private var myTurn: Bool { store.inputOpen && inGame && !store.sent && !store.sending }

    private var bannerFill: Color {
        if myTurn { return SequenceBannerPaint.violet }
        if watching { return SequenceBannerPaint.night }
        return Color.clear
    }

    private var bannerInk: Color {
        (myTurn || watching) ? SequenceBannerPaint.cream : SR.ink
    }

    private var bannerIcon: String {
        guard me?.joined == true else { return "eye" }
        guard me?.alive == true else { return "person.fill.xmark" }
        if !store.inputOpen { return "eye.fill" }
        if store.sent { return "checkmark.circle.fill" }
        if store.sending { return "paperplane.fill" }
        return "hand.tap.fill"
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
                    .frame(minHeight: 56)
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(!(store.taps?.canUndo ?? false) || !store.canTap)
            .accessibilityIdentifier("memory-undo")
            if store.sendFailed {
                Button { store.send() } label: {
                    SRButtonLabel(title: "Send again", icon: "arrow.clockwise", fill: true)
                        .frame(minHeight: 56)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("memory-resend")
            }
        }
    }
}

/// During the show: one pip a flash, lit as each one goes by, the current one
/// larger — so "how many more" is a glance.
struct SequenceShowPips: View {
    let length: Int
    /// Flashes shown so far this round.
    let shown: Int
    /// The flash showing now, 1-based, or nil between flashes.
    let lit: Int?

    var body: some View {
        let side: CGFloat = length > 12 ? 9 : 14
        HStack(spacing: length > 12 ? 4 : 6) {
            ForEach(1...max(1, length), id: \.self) { n in
                Circle()
                    .fill(n <= shown ? SR.accent : SR.line)
                    .frame(width: side, height: side)
                    .scaleEffect(lit == n ? 1.5 : 1)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.12), value: lit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(shown) of \(length) flashes shown")
    }
}

/// The taps so far, as the tiles' symbols, and numbered slots for the rest.
struct SequenceTapsRow: View {
    let round: SequenceRound
    let taps: [Int]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<round.length, id: \.self) { i in
                        slot(i)
                            .id(i)
                    }
                }
                .padding(.vertical, 4)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: taps.count)
            }
            .onChange(of: taps.count) { _, count in
                proxy.scrollTo(min(count, max(0, round.length - 1)), anchor: .center)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(taps.isEmpty ? "No taps yet" : "Tapped: " + taps.map { "tile \($0 + 1)" }.joined(separator: ", "))
        .accessibilityIdentifier("memory-taps")
    }

    @ViewBuilder
    private func slot(_ i: Int) -> some View {
        if i < taps.count {
            Image(systemName: SequencePalette.symbol(taps[i]))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(SequencePalette.mark(taps[i]))
                .frame(width: 36, height: 36)
                .background(Circle().fill(SequencePalette.fill(taps[i])))
                .transition(.scale(scale: 0.3).combined(with: .opacity))
        } else {
            Text("\(i + 1)")
                .font(SR.Text.label(12))
                .foregroundStyle(i == taps.count ? SR.accent : SR.inkGhost)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle().strokeBorder(i == taps.count ? SR.accent : SR.line, lineWidth: i == taps.count ? 2 : 1.5)
                )
        }
    }
}

/// Seconds left in the input window, as a ring that drains around the figure.
struct SequenceWindowClock: View {
    let round: SequenceRound
    @ObservedObject var store: SequenceMemoryStore
    var ink: Color = SR.ink
    /// The colour of the last two seconds.
    var urgent: Color = SR.error

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            ring(left: secondsLeft, share: share)
        }
    }

    private func ring(left: Int?, share: Double) -> some View {
        let tone = (left ?? 99) <= 2 ? urgent : ink
        return ZStack {
            Circle()
                .stroke(ink.opacity(0.2), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(share))
                .stroke(tone, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .srAnimation(.linear(duration: 0.25), value: share)
            Text(left.map { "\($0)" } ?? "–")
                .font(SR.Text.figure(20))
                .foregroundStyle(tone)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: 56, height: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(left.map { "\($0) seconds left" } ?? "Time left unknown")
        .accessibilityIdentifier("memory-timer")
    }

    private var secondsLeft: Int? {
        guard let now = store.serverNow() else { return nil }
        return GameCountdown.secondsLeft(until: round.inputEndsAt, atServer: now)
    }

    private var share: Double {
        guard let now = store.serverNow() else { return 0 }
        return SequenceCompare.windowShare(msLeft: round.inputEndsAt - now, windowMs: round.windowMs)
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
                    row(player)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("memory-players")
    }

    private func row(_ player: GamePlayer) -> some View {
        HStack(spacing: 12) {
            GameInitial(name: player.name, filled: player.alive, tone: SR.accentInk, side: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name + (player.id == room.meId ? " (you)" : ""))
                    .strikethrough(!player.alive, color: SR.inkMuted)
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
            Label("Tapping", systemImage: "hand.tap")
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
                if round.attempt(of: room.meId) != nil {
                    outcome
                }
                sequenceCard
                survivorsCard
                Label(next, systemImage: "timer")
                    .font(SR.Text.mono(14))
                    .foregroundStyle(SR.inkMuted)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("memory-result")
    }

    // MARK: Parts

    private var survived: Bool { round.survivorIds?.contains(room.meId) == true }

    /// My round in one line: through (and what is next) or out.
    private var outcome: some View {
        HStack(spacing: 14) {
            Image(systemName: survived ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(SR.Text.hero(36))
                .foregroundStyle(survived ? SR.good : SR.error)
                .symbolEffect(.bounce, value: survived)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(survived ? "Through" : "Out this round")
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                Text(outcomeLine)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .fill((survived ? SR.good : SR.error).opacity(0.10))
        )
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("memory-outcome")
    }

    private var outcomeLine: String {
        if survived {
            return round.length >= room.maxLength
                ? "All \(round.length) steps — the longest there is."
                : "All \(round.length) steps right. Next round is \(round.length + 1)."
        }
        if let mine = round.attempt(of: room.meId), let taps = mine.taps, let sequence = round.sequence,
           let slip = SequenceCompare.firstMistake(sequence: sequence, taps: taps) {
            return "It went wrong at step \(slip + 1) of \(round.length)."
        }
        return "The time ran out before all \(round.length) taps."
    }

    @ViewBuilder
    private var sequenceCard: some View {
        if let sequence = round.sequence {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                if let mine = round.attempt(of: room.meId), let taps = mine.taps {
                    SRSectionLabel(text: mine.correct ? "Yours — right" : "Yours",
                                   trailing: mine.correct ? nil : "\(taps.count) taps")
                    SequenceCompareStrip(sequence: sequence, taps: taps)
                        .accessibilityIdentifier("memory-sequence")
                } else {
                    SRSectionLabel(text: "The sequence")
                    SequenceSymbols(tiles: sequence)
                        .accessibilityIdentifier("memory-sequence")
                }
            }
            .padding(SR.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srGlassCard(.paper)
        }
    }

    private var survivorsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, player in
                if index > 0 { Divider().overlay(SR.divider) }
                survivorRow(player)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
        .accessibilityIdentifier("memory-survivors")
    }

    private func survivorRow(_ player: GamePlayer) -> some View {
        let through = round.survivorIds?.contains(player.id) == true
        return HStack(spacing: 12) {
            Image(systemName: through ? "checkmark.circle.fill" : "xmark.circle")
                .font(SR.Text.title(20))
                .foregroundStyle(through ? SR.good : SR.inkGhost)
                .accessibilityHidden(true)
            Text(player.name + (player.id == room.meId ? " (you)" : ""))
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
            Spacer(minLength: 8)
            Text(line(player, survived: through))
                .font(SR.Text.mono())
                .foregroundStyle(through ? SR.good : SR.inkMuted)
        }
        .frame(minHeight: SR.tapTarget)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("memory-result-\(player.id)")
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

/// The sequence over my taps, column by column, so a slip is exactly where
/// it happened: a red ring and a cross on the first wrong tap and after.
struct SequenceCompareStrip: View {
    let sequence: [Int]
    let taps: [Int]

    var body: some View {
        let marks = SequenceCompare.marks(sequence: sequence, taps: taps)
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                rowLabel("SHOWN")
                rowLabel("YOU")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<max(sequence.count, taps.count), id: \.self) { i in
                        column(i, marks: marks)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(marks))
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(SR.Text.label())
            .tracking(1)
            .foregroundStyle(SR.inkMuted)
            .frame(height: 40)
    }

    private func column(_ i: Int, marks: [Bool]) -> some View {
        VStack(spacing: 4) {
            if i < sequence.count {
                SequenceDot(tile: sequence[i])
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
            if i < taps.count {
                SequenceDot(tile: taps[i], wrong: i < marks.count && !marks[i])
            } else {
                Circle()
                    .strokeBorder(SR.line, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: 36, height: 36)
            }
        }
        .frame(height: 80, alignment: .top)
    }

    private func spoken(_ marks: [Bool]) -> String {
        let shown = sequence.map { "tile \($0 + 1)" }.joined(separator: ", ")
        let mine = taps.map { "tile \($0 + 1)" }.joined(separator: ", ")
        if let slip = marks.firstIndex(of: false) {
            return "The sequence: \(shown). Yours: \(mine). Wrong from step \(slip + 1)."
        }
        return "The sequence: \(shown). Yours: \(mine). All right."
    }
}

/// One tile as a small disc: its colour and symbol. `wrong` rings it in red
/// and adds a cross.
struct SequenceDot: View {
    let tile: Int
    var wrong: Bool = false

    var body: some View {
        Image(systemName: SequencePalette.symbol(tile))
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(SequencePalette.mark(tile))
            .frame(width: 36, height: 36)
            .background(Circle().fill(SequencePalette.fill(tile)))
            .overlay {
                if wrong {
                    Circle().strokeBorder(SR.error, lineWidth: 3).padding(-3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if wrong {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, SR.error)
                        .offset(x: 5, y: -5)
                }
            }
    }
}

/// A sequence as a row of the tiles' symbols.
struct SequenceSymbols: View {
    let tiles: [Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    SequenceDot(tile: tile)
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
    @State private var note: QuickRoomBestNote?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Sequence Memory · final",
                             title: GameResults.title(room, solo: soloTitle, none: "Nobody made it"),
                             strap: GameResults.strap(room))

                if let mine {
                    QuickRoomStatRow(stats: stats(mine))
                }

                if let note, mine != nil {
                    QuickRoomBestCard(title: "Your longest at \(GameDifficulty.label(for: room.difficulty).lowercased())",
                                      value: note.best.map { "\($0) steps" },
                                      isNew: note.isNew,
                                      previous: note.previous.map { "was \($0)" },
                                      id: "memory-best")
                }

                if !room.solo && (room.standings?.count ?? 0) >= 2 {
                    QuickRoomPodium(room: room, figure: { "\($0.best) steps" })
                }

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
        .overlay {
            if celebrate { QuickRoomConfetti() }
        }
        .accessibilityIdentifier("memory-finished")
        // A win's tap and confetti come from `GameStandingsCard`; this page
        // adds them only for a new best the card does not celebrate.
        .onAppear { recordBest() }
    }

    private var mine: GameStanding? { room.standings?.first { $0.id == room.meId } }

    private func stats(_ row: GameStanding) -> [QuickRoomStat] {
        [
            QuickRoomStat(label: "Longest", value: "\(row.best)"),
            QuickRoomStat(label: "Rounds", value: "\(row.roundsSurvived)"),
            QuickRoomStat(label: row.outRound == nil ? "Out" : "Out in round", value: row.outRound.map { "\($0)" } ?? "Never")
        ]
    }

    /// Confetti for a new best — unless the standings card is already
    /// throwing its own for a win (or a family record).
    private var celebrate: Bool {
        note?.isNew == true && !GameResults.celebrates(room)
    }

    private func recordBest() {
        guard note == nil, let mine else { return }
        let signature = (room.standings ?? [])
            .map { "\($0.id):\($0.best):\($0.roundsSurvived):\($0.outRound ?? -1)" }
            .joined(separator: ",")
        // The last round's show time tells two games in one room apart.
        let lastShow = Int(room.memory?.showAt ?? 0)
        let fresh = QuickRoomBestStore.memory.record(mine.best, difficulty: room.difficulty,
                                                     token: "\(room.id)|\(lastShow)|\(signature)")
        note = fresh
        if fresh.isNew && !GameResults.celebrates(room) { SRHaptic.ok() }
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
