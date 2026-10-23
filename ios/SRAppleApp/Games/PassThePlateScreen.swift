import SwiftUI
import UIKit

/// One Pass the Plate room, from lobby to the ice cream.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`);
/// Start waits for a second player. A turn is my plate — only mine, as cards to
/// tap (easy shows what each would add) — over the turn clock, who is still
/// choosing, and everybody's table so far. Between rounds the round's scores
/// stay up for a few seconds; the finish is the final table with the ice cream.
struct PassThePlateScreen: View {
    let roomId: String
    @StateObject private var store: PassThePlateStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingLeave = false

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: PassThePlateStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Pass the Plate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar(immersive ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(immersive)
            .onAppear { store.open() }
            .onDisappear { store.close() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.open() } else if phase == .background { store.close() }
            }
            .overlay(alignment: .top) {
                if let message = store.message, !immersive { SRBanner(text: message) }
            }
            .toolbar {
                if canLeaveMidGame {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Leave") { confirmingLeave = true }
                            .disabled(store.busy)
                            .accessibilityLabel("Leave game")
                            .accessibilityIdentifier("plate-leave")
                    }
                }
            }
            .confirmationDialog("Leave this game?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Leave game", role: .destructive) {
                    Task {
                        _ = await store.act("leave")
                        dismiss()
                    }
                }
                Button("Keep playing", role: .cancel) {}
            } message: {
                Text("Your plate leaves with you and you finish below everyone still playing.")
            }
    }

    /// Mid-game (a turn or the scores between rounds) a seated player can leave
    /// the table; otherwise the clock would keep choosing for them every turn.
    private var canLeaveMidGame: Bool {
        guard !store.ended, let room = store.room, room.me?.joined == true,
              room.passThePlate?.seat(room.meId)?.seated == true else { return false }
        switch PassThePlateScreenPhase.of(room) {
        case .picking, .scoring: return true
        default: return false
        }
    }

    private var immersive: Bool {
        guard !store.ended, let room = store.room else { return false }
        return PassThePlateScreenPhase.of(room) == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "plate-ended", done: { dismiss() })
        } else if let room = store.room {
            switch PassThePlateScreenPhase.of(room) {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "plate", done: { dismiss() },
                          panel: AnyView(PassThePlateTableCard(room: room)),
                          startBlocked: room.playing.count < 2)
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Take one card each turn. Everyone shows theirs together, then the plates move on.",
                                  id: "plate-countdown")
            case .picking:
                PassThePlatePlaying(room: room, store: store)
            case .scoring:
                PassThePlateScoring(room: room, store: store)
            case .finished:
                PassThePlateFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "plate-ended", done: { dismiss() })
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

/// The game in the lobby: three cards fanned beside the level's line and, until
/// somebody else is in, that this game needs two.
struct PassThePlateTableCard: View {
    let room: GameRoom

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: -10) {
                ForEach(["pancake", "pizza", "icecream"], id: \.self) { kind in
                    PlateCardFace(info: PlateDeck.fallback(kind), compact: true)
                        .frame(width: 44)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(PassThePlateSettings.about(difficulty: room.difficulty).uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Take one, pass it on")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text("Everyone chooses a card from their plate in secret, shows it together, then passes the plate.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if room.playing.count < 2 {
                    Text("Needs at least two players.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .accessibilityIdentifier("plate-needs-two")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plate-table")
    }
}

// MARK: - A card

/// One food card: the emoji large, its name, a pie's points or a berry count,
/// and on easy a badge with what it would add. `compact` is a table chip.
struct PlateCardFace: View {
    let info: PlateKind
    var gain: Int? = nil
    var chosen: Bool = false
    var compact: Bool = false
    var boosted: Bool = false
    var spent: Bool = false

    var body: some View {
        VStack(spacing: compact ? 0 : 4) {
            Text(info.emoji)
                .font(SR.Text.display(compact ? 20 : 34))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !compact {
                Text(info.name)
                    .font(SR.Text.label())
                    .foregroundStyle(SR.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                if let figure {
                    Text(figure)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 36 : 104)
        .padding(compact ? 4 : 8)
        .background(
            RoundedRectangle(cornerRadius: compact ? 8 : 14, style: .continuous)
                .fill(chosen ? SR.accent.opacity(0.16) : SR.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 8 : 14, style: .continuous)
                .strokeBorder(chosen ? SR.accent : SR.line, lineWidth: chosen ? 3 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if let badge {
                Text(badge)
                    .font(SR.Text.label())
                    .foregroundStyle(SR.paper)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(badgeTone))
                    .offset(x: 4, y: -6)
            }
        }
        .opacity(spent ? 0.5 : 1)
    }

    /// A pie's points or a card's berries, under the name.
    private var figure: String? {
        switch info.family {
        case "pie": return "\(info.value) points"
        case "majority": return info.value == 1 ? "1 berry" : "\(info.value) berries"
        default: return nil
        }
    }

    private var badge: String? {
        if boosted { return "×2" }
        if let gain, gain > 0 { return PassThePlateRules.gainText(gain) }
        return nil
    }

    private var badgeTone: Color { boosted ? SR.accent : SR.good }
}

// MARK: - A turn

struct PassThePlatePlaying: View {
    let room: GameRoom
    @ObservedObject var store: PassThePlateStore
    @State private var showRules: Bool?

    private var state: PassThePlateState? { room.passThePlate }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                PassThePlateTurnBar(room: room, store: store)
                if room.me?.joined == true, state?.seat(room.meId)?.seated == true {
                    myPlate
                    statusLine
                        .frame(maxWidth: .infinity)
                } else {
                    Text("You are watching this one.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }
                if let last = state?.lastTurn, !last.isEmpty { lastTurn(last) }
                PassThePlateTables(room: room)
                reference
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("plate-playing")
        .onChange(of: store.refusal) { _, refusal in
            if let refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ROUND \(state?.round ?? 1) OF \(state?.rounds ?? 3) · TURN \(state?.turn ?? 1) · \(GameDifficulty.label(for: room.difficulty).uppercased())")
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.accent)
                .fixedSize(horizontal: false, vertical: true)
            Text(headline)
                .font(SR.Text.display(24))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("plate-headline")
            Text(PassThePlateRules.passLine(direction: state?.direction ?? "left",
                                            to: state?.passTo.map { room.name(of: $0) }))
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .accessibilityIdentifier("plate-direction")
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plate-header")
    }

    private var headline: String {
        if store.chosenSent { return "Chosen — change it until everyone has" }
        if store.takeTwo { return store.holding.isEmpty ? "Pick two cards" : "Now pick the second" }
        return "Take one card"
    }

    // MARK: My plate

    private var myPlate: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Your plate", trailing: "Only you can see this")
            let hand = state?.hand ?? []
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(hand) { card in
                    let info = state?.info(card.kind) ?? PlateDeck.fallback(card.kind)
                    let chosen = store.chosen.contains(card.uid)
                    Button { store.tap(card.uid) } label: {
                        PlateCardFace(info: info, gain: card.gain, chosen: chosen)
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.canPick || store.sending)
                    .accessibilityLabel(PassThePlateRules.spoken(info, gain: card.gain, chosen: chosen))
                    .accessibilityHint(info.rule)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                    .accessibilityIdentifier("plate-card-\(card.uid)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("plate-hand")
            if state?.canTakeTwo == true {
                Button { store.toggleTakeTwo() } label: {
                    SRButtonLabel(title: store.takeTwo ? "Take just one" : "Use the spoon: take two",
                                  icon: "fork.knife", fill: store.takeTwo)
                }
                .srButton(store.takeTwo ? .prominent : .regular)
                .controlSize(.large)
                .accessibilityIdentifier("plate-spoon")
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let refusal = store.refusal {
            Label(refusal, systemImage: "exclamationmark.circle")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.error)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("plate-refusal")
        } else if let waiting = PassThePlateRules.waitingLine(store.waitingFor) {
            Text(waiting)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("plate-waiting")
        }
    }

    // MARK: The last reveal

    private func lastTurn(_ plays: [PlateTurnPlay]) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Last turn")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plays) { play in
                    let who = play.playerId == room.meId ? "You" : room.name(of: play.playerId)
                    let names = play.cards.map { state?.info($0.kind).name ?? $0.kind }
                    HStack(spacing: 8) {
                        Text(who)
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if play.auto {
                            Text("TIMED OUT")
                                .font(SR.Text.label())
                                .tracking(1)
                                .foregroundStyle(SR.error)
                        }
                        Text(play.cards.map { state?.info($0.kind).emoji ?? "" }.joined(separator: " "))
                            .font(SR.Text.title())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(who) took \(GameNames.list(names))\(play.auto ? ", timed out" : "")")
                }
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plate-last-turn")
    }

    // MARK: What the cards do

    private var reference: some View {
        let open = showRules ?? (state?.hints == .gains)
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            Button {
                showRules = !open
                SRHaptic.select()
            } label: {
                HStack {
                    SRSectionLabel(text: "What the cards do")
                    Spacer(minLength: 8)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .foregroundStyle(SR.inkMuted)
                }
                .frame(minHeight: SR.tapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Hide what the cards do" : "Show what the cards do")
            .accessibilityIdentifier("plate-reference-toggle")
            if open {
                PassThePlateReference(kinds: state?.kinds ?? [])
            }
        }
    }
}

/// Every kind in this room's deck, one line each.
struct PassThePlateReference: View {
    let kinds: [PlateKind]

    var body: some View {
        // The three strawberry cards share one rule: say it once.
        let rows = kinds.filter { $0.kind != "berry2" && $0.kind != "berry3" }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { kind in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(kind.emoji)
                        .font(SR.Text.title())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.family == "majority" ? "Strawberries" : kind.name)
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.ink)
                        Text(kind.rule)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("plate-reference")
    }
}

/// Everybody's table this round: who has chosen, cards left, the round so far
/// (when the level shows it), scoops, and the cards they have taken.
struct PassThePlateTables: View {
    let room: GameRoom

    private var state: PassThePlateState? { room.passThePlate }

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "The tables")
            VStack(spacing: 0) {
                let seated = room.players.filter { state?.seat($0.id)?.seated ?? $0.joined }
                ForEach(Array(seated.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { Divider().overlay(SR.divider) }
                    row(player)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plate-tables")
    }

    private func row(_ player: GamePlayer) -> some View {
        let seat = state?.seat(player.id)
        let me = player.id == room.meId
        let gone = seat?.left == true || !player.joined
        let picking = state?.phase == .picking
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                GameInitial(name: me ? "You" : player.name, tone: seat?.picked == true ? SR.good : SR.accentInk)
                Text(player.name + (me ? " (you)" : ""))
                    .font(SR.Text.title())
                    .foregroundStyle(gone ? SR.inkGhost : SR.ink)
                    .strikethrough(gone, color: SR.inkMuted)
                    .lineLimit(1)
                if gone {
                    Text("LEFT")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                } else if picking {
                    Image(systemName: seat?.picked == true ? "checkmark.circle.fill" : "ellipsis.circle")
                        .foregroundStyle(seat?.picked == true ? SR.good : SR.inkGhost)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(seat?.score ?? 0)")
                        .font(SR.Text.figure(20))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                    if let soFar = seat?.roundSoFar, state?.phase == .picking {
                        Text("+\(soFar) this round")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                    }
                }
            }
            let played = seat?.played ?? []
            if !played.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(played) { card in
                        PlateCardFace(info: state?.info(card.kind) ?? PlateDeck.fallback(card.kind),
                                      compact: true, boosted: card.boosted, spent: card.spent)
                    }
                }
                .accessibilityHidden(true)
            }
            Text(detail(seat))
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(player, seat: seat, me: me, gone: gone))
        .accessibilityIdentifier("plate-seat-\(player.id)")
    }

    private func detail(_ seat: PlateSeat?) -> String {
        guard let seat else { return "" }
        var bits = [GameResults.count(seat.handCount, "card left", "cards left")]
        if seat.berries > 0 { bits.append(GameResults.count(seat.berries, "berry", "berries")) }
        if seat.iceCream > 0 { bits.append(GameResults.count(seat.iceCream, "scoop", "scoops")) }
        return bits.joined(separator: " · ")
    }

    private func spoken(_ player: GamePlayer, seat: PlateSeat?, me: Bool, gone: Bool) -> String {
        let who = me ? "You" : player.name
        if gone { return "\(who), left" }
        guard let seat else { return who }
        let names = seat.played.map { state?.info($0.kind).name ?? $0.kind }
        let chose = state?.phase == .picking ? (seat.picked ? ", has chosen" : ", still choosing") : ""
        let taken = names.isEmpty ? "nothing taken yet" : "taken: \(names.joined(separator: ", "))"
        return "\(who), \(seat.score) points\(chose). \(taken). \(detail(seat))."
    }
}

/// The turn running out — a bar that empties towards the turn clock.
struct PassThePlateTurnBar: View {
    let room: GameRoom
    @ObservedObject var store: PassThePlateStore

    var body: some View {
        // Ticks, not an animation, so the app can go idle (UI tests read it).
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let left = CGFloat(PassThePlateRules.turnLeft(endsAt: room.phaseEndsAt,
                                                          turnMs: room.passThePlate?.turnMs ?? 30_000,
                                                          now: store.serverNow()))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.line)
                    Capsule()
                        .fill(left < 0.17 ? SR.error : left < 0.34 ? SR.accent : SR.good)
                        .frame(width: geo.size.width * left)
                }
            }
            .frame(height: 5)
        }
        .accessibilityHidden(true)
        .accessibilityIdentifier("plate-turn-bar")
    }
}

// MARK: - Between rounds

struct PassThePlateScoring: View {
    let room: GameRoom
    @ObservedObject var store: PassThePlateStore

    private var state: PassThePlateState? { room.passThePlate }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Pass the Plate · round \(state?.round ?? 1) of \(state?.rounds ?? 3)",
                             title: "Round \(state?.round ?? 1) scored",
                             strap: (state?.round ?? 1) < (state?.rounds ?? 3)
                                ? "The next plates are on their way."
                                : "Now for the ice cream.")
                if let result = state?.results.last {
                    PassThePlateRoundCard(room: room, result: result)
                }
                PassThePlateTables(room: room)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("plate-scoring")
    }
}

/// One round's scores, best first, with what each came from.
struct PassThePlateRoundCard: View {
    let room: GameRoom
    let result: PlateRoundResult

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Round \(result.round)")
            VStack(spacing: 0) {
                let rows = result.rows.sorted { $0.total > $1.total }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(SR.divider) }
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.playerId == room.meId ? "You" : room.name(of: row.playerId))
                                .font(SR.Text.title())
                                .foregroundStyle(SR.ink)
                            Text(PassThePlateRules.breakdownLine(row))
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Text("\(row.total)")
                            .font(SR.Text.figure(24))
                            .foregroundStyle(SR.ink)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("plate-round-\(result.round)-\(row.playerId)")
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
    }
}

// MARK: - Finished

struct PassThePlateFinished: View {
    let room: GameRoom
    @ObservedObject var store: PassThePlateStore
    let done: () -> Void

    private var state: PassThePlateState? { room.passThePlate }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Pass the Plate · \(PassThePlateSettings.about(difficulty: room.difficulty)) · final",
                             title: GameResults.title(room, solo: "Game over", none: "Nobody won"),
                             strap: GameResults.strap(room))

                GameStandingsCard(
                    room: room,
                    label: "Final scores",
                    id: "plate-standings",
                    detail: detail,
                    figure: { row in
                        let score = standing(row.id)?.score ?? row.score
                        return (text: "\(score)", spoken: GameResults.count(score, "point", "points"))
                    }
                )

                ForEach((state?.results ?? []).reversed()) { result in
                    PassThePlateRoundCard(room: room, result: result)
                }

                GameFinishedButtons(room: room, store: store, prefix: "plate", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("plate-finished")
    }

    private func standing(_ id: String) -> PlateStanding? {
        state?.standings?.first { $0.id == id }
    }

    private func detail(_ row: GameStanding) -> String {
        guard let s = standing(row.id) else { return "" }
        if s.left { return "Left the table" }
        let rounds = (state?.results ?? []).compactMap { r in r.rows.first { $0.playerId == row.id }?.total }
        var bits: [String] = []
        if !rounds.isEmpty { bits.append("Rounds " + rounds.map(String.init).joined(separator: ", ")) }
        let dessert = state?.dessert?.first { $0.playerId == row.id }
        let scoops = GameResults.count(s.scoops, "scoop", "scoops")
        if let points = dessert?.points, points != 0 {
            bits.append("\(scoops) \(points > 0 ? "+" : "")\(points)")
        } else {
            bits.append(scoops)
        }
        return bits.joined(separator: " · ")
    }
}
