import SwiftUI
import UIKit

/// One Pass the Plate room, from lobby to the ice cream.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the deck and how to play as the lobby's panel; Start waits for a
/// second player.
///
/// A turn is my plate: a platter on a gingham cloth with my cards on it — only
/// mine — as big cards to tap (easy shows what each would add), dealt in
/// afresh each time the plates move. Above it a banner says what to do now
/// (take one, take two with the spoon, or you have chosen) with the turn
/// clock, and a strip of faces shows who has chosen. Below, the last reveal
/// and everybody's table, grouped by kind — with, when the level shows hints,
/// how far each set has got.
///
/// Between rounds the round's scores stay up as bars, with the round's top
/// plate crowned and a clock to the next deal; the finish is the final table
/// with the ice cream, a celebration for the winner and this phone's best.
///
/// There is no pause — the turn clock is everyone's — so the "?" in the bar
/// opens how to play over a table that carries on.
struct PassThePlateScreen: View {
    let roomId: String
    @StateObject private var store: PassThePlateStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingLeave = false
    @State private var showingHowTo = false

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
                if showsHelp {
                    ToolbarItem(placement: .topBarTrailing) {
                        TableHelpButton(id: "plate-help") { showingHowTo = true }
                    }
                }
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
            .sheet(isPresented: $showingHowTo) {
                TableHowToSheet(game: "Pass the Plate", steps: PassThePlateHowTo.steps,
                                note: TableHowToNote.live, id: "plate-how-to")
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

    private var showsHelp: Bool {
        guard !store.ended, let room = store.room else { return false }
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
            VStack(spacing: 14) {
                PassThePlateDish()
                    .frame(width: 120, height: 84)
                    .overlay { Text("🍽️").font(.system(size: 34)) }
                ProgressView()
                    .tint(SR.accent)
                Text("Laying the table…")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .srPaper()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Laying the table")
        }
    }
}

// MARK: - How to play

enum PassThePlateHowTo {
    static let steps = [
        TableHowToStep(icon: "hand.tap.fill", title: "Take one card",
                       text: "Everyone picks one card from their plate in secret. You can change your mind until everybody has chosen."),
        TableHowToStep(icon: "arrow.triangle.2.circlepath", title: "Show, then pass",
                       text: "The cards are shown together and go on your table. Then every plate moves to the next player."),
        TableHowToStep(icon: "square.stack.3d.up.fill", title: "Collect sets",
                       text: "Two pancakes make a pair, three pizza slices a whole pizza, popcorn grows the more you have, and the most strawberries scores big."),
        TableHowToStep(icon: "fork.knife", title: "Gravy and the spoon",
                       text: "A gravy jug doubles your next pie. A serving spoon lets you take two cards at once on a later turn."),
        TableHowToStep(icon: "trophy.fill", title: "Three rounds, then ice cream",
                       text: "Rounds are scored as they end. Ice cream is counted at the very end: most scoops wins a bonus."),
    ]
}

// MARK: - Paint

/// The table's colours: a platter, a gingham cloth, and a colour per card
/// family (the band across the top of each card). Every card also says its
/// name, so the colours are an aid, never the only clue.
enum PassThePlatePaint {
    static var plate: Color { Color(light: 0xFCFBF8, dark: 0x2C3152) }
    static var plateRim: Color { Color(light: 0xE6E0D4, dark: 0x3D4470) }
    static var cloth: Color { Color(light: 0xFFF7F4, dark: 0x221C2C) }
    static var check: Color { Color(light: 0xE8B4AC, dark: 0x5A3446) }
    static var card: Color { Color(light: 0xFFFFFF, dark: 0x20264A) }

    static func family(_ family: String) -> Color {
        switch family {
        case "pair": return Color(hex: 0xE0A040)
        case "triple": return Color(hex: 0xD9534F)
        case "sliding": return Color(hex: 0xF2C14E)
        case "majority": return Color(hex: 0xE05A8A)
        case "pie": return Color(hex: 0xA86A3D)
        case "multiplier": return Color(hex: 0x3E9A8B)
        case "takeTwo": return Color(hex: 0x7D8597)
        case "dessert": return Color(hex: 0x9B7FD1)
        default: return Color(hex: 0x8A8F98)
        }
    }
}

/// A platter: a rim and a well, as an ellipse that fits whatever it is behind.
struct PassThePlateDish: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(PassThePlatePaint.plateRim)
                .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 6)
            Ellipse()
                .inset(by: 12)
                .fill(PassThePlatePaint.plate)
            Ellipse()
                .inset(by: 12)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }
}

/// A gingham cloth: stripes both ways, drawn once per layout.
struct PassThePlateCloth: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
        ZStack {
            shape.fill(PassThePlatePaint.cloth)
            Canvas { context, size in
                let step: CGFloat = 22
                let band = step / 2
                let tone = GraphicsContext.Shading.color(PassThePlatePaint.check.opacity(0.35))
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: 0, width: band, height: size.height)), with: tone)
                    x += step
                }
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: band)), with: tone)
                    y += step
                }
            }
            .clipShape(shape)
            shape.strokeBorder(PassThePlatePaint.check.opacity(0.6), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Lobby

/// The game in the lobby: three cards fanned on a plate beside the level's
/// line, how to play in brief and, until somebody else is in, that this game
/// needs two.
struct PassThePlateTableCard: View {
    let room: GameRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            fan
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
            }
            TableHowToList(steps: Array(PassThePlateHowTo.steps.prefix(3)))
            if room.playing.count < 2 {
                Label("Needs at least two players.", systemImage: "person.2.fill")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityIdentifier("plate-needs-two")
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plate-table")
    }

    private var fan: some View {
        ZStack {
            PassThePlateDish()
                .frame(width: 230, height: 130)
            HStack(spacing: -14) {
                PlateCardFace(info: PlateDeck.fallback("pancake"))
                    .frame(width: 70)
                    .rotationEffect(.degrees(-10))
                PlateCardFace(info: PlateDeck.fallback("pizza"))
                    .frame(width: 70)
                    .offset(y: -8)
                    .zIndex(1)
                PlateCardFace(info: PlateDeck.fallback("icecream"))
                    .frame(width: 70)
                    .rotationEffect(.degrees(10))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(PassThePlateCloth())
    }
}

// MARK: - A card

/// One food card: a band in its family's colour, the food large, its name, a
/// pie's points or a berry count, and on easy a badge with what it would add.
/// `chosen` lifts it with a tick; `compact` is a small chip for a table.
struct PlateCardFace: View {
    let info: PlateKind
    var gain: Int? = nil
    var chosen: Bool = false
    var compact: Bool = false
    var boosted: Bool = false
    var spent: Bool = false

    var body: some View {
        if compact {
            chip
        } else {
            full
        }
    }

    private var chip: some View {
        Text(info.emoji)
            .font(.system(size: 20))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(PassThePlatePaint.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(PassThePlatePaint.family(info.family).opacity(0.9), lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(badgeTone))
                        .offset(x: 6, y: -6)
                }
            }
            .opacity(spent ? 0.5 : 1)
    }

    private var full: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(spacing: 4) {
            Capsule()
                .fill(PassThePlatePaint.family(info.family))
                .frame(height: 6)
                .padding(.horizontal, 10)
                .padding(.top, 8)
            Text(info.emoji)
                .font(.system(size: 40))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 2)
            Text(info.name)
                .font(SR.Text.label())
                .foregroundStyle(SR.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            if let figure {
                Text(figure)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, minHeight: 128)
        .background(shape.fill(PassThePlatePaint.card))
        .overlay(shape.strokeBorder(chosen ? SR.accent : SR.line, lineWidth: chosen ? 3.5 : 1))
        .overlay(alignment: .topLeading) {
            if chosen {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(SR.paper)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(SR.accent))
                    .offset(x: -6, y: -8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badge {
                Text(badge)
                    .font(SR.Text.label())
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(badgeTone))
                    .offset(x: 6, y: -8)
            }
        }
        .shadow(color: Color.black.opacity(chosen ? 0.22 : 0.1), radius: chosen ? 10 : 4, x: 0, y: chosen ? 8 : 2)
        .offset(y: chosen ? -8 : 0)
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

    /// Badges carry white type, so they take the deeper of each pair.
    private var badgeTone: Color { boosted ? Color(hex: 0x4426D6) : Color(hex: 0x1F7A4D) }
}

// MARK: - A turn

struct PassThePlatePlaying: View {
    let room: GameRoom
    @ObservedObject var store: PassThePlateStore
    @State private var showRules: Bool?

    private var state: PassThePlateState? { room.passThePlate }
    private var seatedHere: Bool { room.me?.joined == true && state?.seat(room.meId)?.seated == true }
    /// The table is waiting on me: a card to choose and none chosen yet.
    private var needsMe: Bool { store.canPick && !store.chosenSent }
    private var turnKey: String { "\(state?.round ?? 0)|\(state?.turn ?? 0)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                banner
                PassThePlateChoosers(room: room, store: store)
                if seatedHere {
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

    // MARK: The banner

    private var banner: some View {
        TableTurnBanner(mine: needsMe) {
            header
        } clock: {
            TableTurnClock(store: store, endsAt: room.phaseEndsAt, turnMs: state?.turnMs ?? 30_000, mine: needsMe)
                .accessibilityIdentifier("plate-turn-bar")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kickerLine)
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(TableTurnInk.kicker(needsMe))
                .fixedSize(horizontal: false, vertical: true)
            Text(headline)
                .font(SR.Text.display(24))
                .foregroundStyle(TableTurnInk.ink(needsMe))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("plate-headline")
            HStack(spacing: 6) {
                Image(systemName: (state?.direction ?? "left") == "right" ? "arrow.turn.down.right" : "arrow.turn.down.left")
                    .font(SR.Text.label(13))
                    .accessibilityHidden(true)
                Text(PassThePlateRules.passLine(direction: state?.direction ?? "left",
                                                to: state?.passTo.map { room.name(of: $0) }))
                    .font(SR.Text.secondary())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plate-direction")
            }
            .foregroundStyle(TableTurnInk.soft(needsMe))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plate-header")
    }

    /// "ROUND 2 OF 3 · TURN 4 · MEDIUM", built as a plain String so the Text
    /// above is not a four-way optional interpolation for the type checker.
    private var kickerLine: String {
        let round: Int = state?.round ?? 1
        let rounds: Int = state?.rounds ?? 3
        let turn: Int = state?.turn ?? 1
        let level: String = GameDifficulty.label(for: room.difficulty).uppercased()
        return "ROUND \(round) OF \(rounds) · TURN \(turn) · \(level)"
    }

    private var headline: String {
        if store.chosenSent { return "Chosen — change it until everyone has" }
        if store.takeTwo { return store.holding.isEmpty ? "Pick two cards" : "Now pick the second" }
        if !seatedHere { return "Plates are going round" }
        return "Take one card"
    }

    // MARK: My plate

    private var myPlate: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Your plate", trailing: "Only you can see this")
            plate
            if state?.canTakeTwo == true { spoon }
        }
    }

    private var plate: some View {
        let hand = state?.hand ?? []
        return ZStack {
            PassThePlateDish()
                .padding(.horizontal, 4)
                .padding(.vertical, 10)
            // 80pt keeps three cards a row on a 375pt phone (92 left only two,
            // and a ten-card plate five rows deep).
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 10)], spacing: 14) {
                ForEach(Array(hand.enumerated()), id: \.element.id) { index, card in
                    cardButton(card)
                        .tablePopIn(delay: Double(index) * 0.04)
                }
            }
            .id(turnKey)
            .padding(.horizontal, 18)
            .padding(.top, 26)
            .padding(.bottom, 20)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("plate-hand")
        }
        .padding(10)
        .background(PassThePlateCloth())
        .srAnimation(.snappy(duration: 0.22), value: store.chosen)
    }

    private func cardButton(_ card: PlateCard) -> some View {
        let info = state?.info(card.kind) ?? PlateDeck.fallback(card.kind)
        let chosen = store.chosen.contains(card.uid)
        return Button { store.tap(card.uid) } label: {
            PlateCardFace(info: info, gain: card.gain, chosen: chosen)
        }
        .buttonStyle(SRPressStyle())
        .disabled(!store.canPick || store.sending)
        .accessibilityLabel(PassThePlateRules.spoken(info, gain: card.gain, chosen: chosen))
        .accessibilityHint(info.rule)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("plate-card-\(card.uid)")
    }

    private var spoon: some View {
        VStack(spacing: 6) {
            Button { store.toggleTakeTwo() } label: {
                TableButtonLabel(title: store.takeTwo ? "Take just one" : "Use the spoon: take two", icon: "fork.knife")
            }
            .buttonStyle(TableSolidButtonStyle(outline: !store.takeTwo))
            .disabled(!store.canPick || store.sending)
            .accessibilityIdentifier("plate-spoon")
            if store.takeTwo {
                Text("Tap two cards. They go on your table together, and the spoon goes back on the plate.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(SR.inkMuted)
                Text(waiting)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("plate-waiting")
            }
        }
    }

    // MARK: The last reveal

    private func lastTurn(_ plays: [PlateTurnPlay]) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Last turn")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(plays) { play in
                    lastTurnRow(play)
                }
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plate-last-turn")
    }

    private func lastTurnRow(_ play: PlateTurnPlay) -> some View {
        let who = play.playerId == room.meId ? "You" : room.name(of: play.playerId)
        let names = play.cards.map { state?.info($0.kind).name ?? $0.kind }
        return HStack(spacing: 10) {
            GameInitial(name: who, tone: SR.accentInk, side: 28)
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
            HStack(spacing: 6) {
                ForEach(play.cards) { card in
                    PlateCardFace(info: state?.info(card.kind) ?? PlateDeck.fallback(card.kind), compact: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(who) took \(GameNames.list(names))\(play.auto ? ", timed out" : "")")
    }

    // MARK: What the cards do

    private var reference: some View {
        let open = showRules ?? (state?.hints == .gains)
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { showRules = !open }
                SRHaptic.select()
            } label: {
                HStack {
                    SRSectionLabel(text: "What the cards do")
                    Spacer(minLength: 8)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.inkMuted)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Hide what the cards do" : "Show what the cards do")
            .accessibilityIdentifier("plate-reference-toggle")
            if open {
                PassThePlateReference(kinds: state?.kinds ?? [])
                    .transition(.opacity)
            }
        }
    }
}

/// Who has chosen this turn: a face per player, ticked once they have.
struct PassThePlateChoosers: View {
    let room: GameRoom
    @ObservedObject var store: PassThePlateStore

    private var state: PassThePlateState? { room.passThePlate }

    var body: some View {
        let seated = room.players.filter { p in
            guard let seat = state?.seat(p.id) else { return p.joined }
            return seat.seated && !seat.left && p.joined
        }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 8)], spacing: 10) {
            ForEach(seated, id: \.id) { player in
                face(player)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plate-choosers")
    }

    private func chosen(_ player: GamePlayer) -> Bool {
        if player.id == room.meId { return store.chosenSent || state?.seat(player.id)?.picked == true }
        return state?.seat(player.id)?.picked == true
    }

    private func face(_ player: GamePlayer) -> some View {
        let me = player.id == room.meId
        let done = chosen(player)
        let name = me ? "You" : player.name
        return VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(done ? SR.paper : SR.ink)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(done ? SR.good : SR.surface))
                    .overlay(
                        Circle().strokeBorder(done ? Color.clear : SR.ink.opacity(0.25),
                                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    )
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(SR.good, SR.paper)
                        .background(Circle().fill(SR.paper).padding(2))
                        .offset(x: 4, y: 4)
                        .tablePopIn()
                }
            }
            Text(name)
                .font(SR.Text.label())
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(done ? "CHOSEN" : "CHOOSING")
                .font(SR.Text.label(12))
                .tracking(0.6)
                .foregroundStyle(done ? SR.good : SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .srAnimation(.snappy(duration: 0.25), value: done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(done ? "has chosen" : "still choosing")")
    }
}

/// Every kind in this room's deck, one line each.
struct PassThePlateReference: View {
    let kinds: [PlateKind]

    var body: some View {
        // The three strawberry cards share one rule: say it once.
        let rows = kinds.filter { $0.kind != "berry2" && $0.kind != "berry3" }
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { kind in
                HStack(alignment: .center, spacing: 12) {
                    PlateCardFace(info: kind, compact: true)
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
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("plate-reference")
    }
}

/// Everybody's table this round: who has chosen, the score, the round so far
/// (when the level shows it), and the cards they have taken grouped by kind —
/// with how far each set has got when the level shows hints.
struct PassThePlateTables: View {
    let room: GameRoom

    private var state: PassThePlateState? { room.passThePlate }
    private var hinting: Bool { (state?.hints ?? PassThePlateHints.none) != PassThePlateHints.none }

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
        let tally = tallyGroups(seat)
        return VStack(alignment: .leading, spacing: 10) {
            rowHeader(player, seat: seat, me: me, gone: gone)
            if !tally.isEmpty { chips(tally) }
        }
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(player, seat: seat, me: me, gone: gone, groups: tally))
        .accessibilityIdentifier("plate-seat-\(player.id)")
    }

    private func rowHeader(_ player: GamePlayer, seat: PlateSeat?, me: Bool, gone: Bool) -> some View {
        let picking = state?.phase == .picking
        let picked = seat?.picked == true
        return HStack(spacing: 10) {
            GameInitial(name: me ? "You" : player.name, tone: picked && picking ? SR.good : SR.accentInk, side: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.name + (me ? " (you)" : ""))
                    .font(SR.Text.title())
                    .foregroundStyle(gone ? SR.inkGhost : SR.ink)
                    .strikethrough(gone, color: SR.inkMuted)
                    .lineLimit(1)
                Text(detail(seat))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if gone {
                Text("LEFT")
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(SR.inkMuted)
            } else if picking {
                Image(systemName: picked ? "checkmark.circle.fill" : "ellipsis.circle")
                    .font(SR.Text.title())
                    .foregroundStyle(picked ? SR.good : SR.inkGhost)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            rowScore(seat, picking: picking)
        }
    }

    private func rowScore(_ seat: PlateSeat?, picking: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(seat?.score ?? 0)")
                .font(SR.Text.figure(24))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
            if let soFar = seat?.roundSoFar, picking {
                Text("+\(soFar) this round")
                    .font(SR.Text.mono())
                    .foregroundStyle(soFar > 0 ? SR.good : SR.inkMuted)
            }
        }
    }

    private func chips(_ tally: [PassThePlateTally.Group]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: hinting ? 132 : 64), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(tally) { group in
                chip(group)
            }
        }
        .accessibilityHidden(true)
    }

    private func tallyCard(_ card: PlatePlayed) -> PassThePlateTally.Card {
        let info = state?.info(card.kind) ?? PlateDeck.fallback(card.kind)
        return PassThePlateTally.Card(kind: card.kind, family: info.family, value: info.value,
                                      boosted: card.boosted, spent: card.spent)
    }

    private func tallyGroups(_ seat: PlateSeat?) -> [PassThePlateTally.Group] {
        PassThePlateTally.groups((seat?.played ?? []).map(tallyCard))
    }

    private func chip(_ group: PassThePlateTally.Group) -> some View {
        let info = state?.info(group.sample) ?? PlateDeck.fallback(group.sample)
        return HStack(spacing: 6) {
            PlateCardFace(info: info, compact: true)
            VStack(alignment: .leading, spacing: 0) {
                Text("×\(group.count)")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
                    .monospacedDigit()
                if hinting, let caption = PassThePlateTally.caption(group) {
                    Text(caption)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if hinting, let size = group.setSize {
                    setPips(have: group.towardsNext, of: size)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PassThePlatePaint.family(group.family).opacity(0.12))
        )
    }

    private func setPips(have: Int, of size: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<size, id: \.self) { i in
                Circle()
                    .fill(i < have ? SR.good : SR.line)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.top, 2)
    }

    private func detail(_ seat: PlateSeat?) -> String {
        guard let seat else { return "" }
        var bits = [GameResults.count(seat.handCount, "card left", "cards left")]
        if seat.berries > 0 { bits.append(GameResults.count(seat.berries, "berry", "berries")) }
        if seat.iceCream > 0 { bits.append(GameResults.count(seat.iceCream, "scoop", "scoops")) }
        return bits.joined(separator: " · ")
    }

    private func spoken(_ player: GamePlayer, seat: PlateSeat?, me: Bool, gone: Bool,
                        groups: [PassThePlateTally.Group]) -> String {
        let who = me ? "You" : player.name
        if gone { return "\(who), left" }
        guard let seat else { return who }
        let names = seat.played.map { state?.info($0.kind).name ?? $0.kind }
        let chose = state?.phase == .picking ? (seat.picked ? ", has chosen" : ", still choosing") : ""
        let taken = names.isEmpty ? "nothing taken yet" : "taken: \(names.joined(separator: ", "))"
        var line = "\(who), \(seat.score) points\(chose). \(taken). \(detail(seat))."
        if hinting {
            let notes = groups.compactMap(PassThePlateTally.caption)
            if !notes.isEmpty { line += " \(notes.joined(separator: "; "))." }
        }
        return line
    }
}

// MARK: - Between rounds

struct PassThePlateScoring: View {
    let room: GameRoom
    @ObservedObject var store: PassThePlateStore

    private var state: PassThePlateState? { room.passThePlate }
    private var result: PlateRoundResult? { state?.results.last }
    private var topIds: [String] {
        guard let rows = result?.rows, let best = rows.map(\.total).max() else { return [] }
        return rows.filter { $0.total == best }.map(\.playerId)
    }
    private var iTopped: Bool { topIds.contains(room.meId) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                HStack(alignment: .top, spacing: 12) {
                    SRPageHeader(kicker: "Pass the Plate · round \(state?.round ?? 1) of \(state?.rounds ?? 3)",
                                 title: "Round \(state?.round ?? 1) scored",
                                 strap: (state?.round ?? 1) < (state?.rounds ?? 3)
                                    ? "The next plates are on their way."
                                    : "Now for the ice cream.")
                    TableTurnClock(store: store, endsAt: room.phaseEndsAt, turnMs: state?.scoringMs ?? 8_000)
                        .accessibilityLabel("Next round soon")
                        .accessibilityIdentifier("plate-next-clock")
                }
                if !topIds.isEmpty { topPlate }
                if let result {
                    PassThePlateRoundCard(room: room, result: result)
                }
                PassThePlateTables(room: room)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .overlay {
            if iTopped { TableCelebration(colours: TableCheer.colours, bursts: 3, duration: 2.4, seed: state?.round ?? 1) }
        }
        .accessibilityIdentifier("plate-scoring")
    }

    private var topPlate: some View {
        let names = topIds.map { $0 == room.meId ? "You" : room.name(of: $0) }
        let total = result?.rows.first { topIds.contains($0.playerId) }?.total ?? 0
        return HStack(spacing: 14) {
            Image(systemName: "crown.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(SR.paper)
                .frame(width: 56, height: 56)
                .background(Circle().fill(SR.accent))
                .tablePopIn()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("TOP PLATE THIS ROUND")
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.accent)
                Text(GameNames.list(names))
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text("\(total)")
                .font(SR.Text.figure(30))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plate-top")
    }
}

/// One round's scores, best first, each with a bar and what it came from.
struct PassThePlateRoundCard: View {
    let room: GameRoom
    let result: PlateRoundResult
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Round \(result.round)")
            VStack(spacing: 0) {
                let rows = result.rows.sorted { $0.total > $1.total }
                let top = max(1, rows.first?.total ?? 1)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(SR.divider) }
                    line(row, top: top, first: index == 0)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .onAppear {
            if reduceMotion {
                grown = true
            } else {
                withAnimation(.smooth(duration: 0.8).delay(0.15)) { grown = true }
            }
        }
    }

    private func line(_ row: PlateRoundRow, top: Int, first: Bool) -> some View {
        let me = row.playerId == room.meId
        let share = CGFloat(max(0, row.total)) / CGFloat(top)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(me ? "You" : room.name(of: row.playerId))
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
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.line)
                    Capsule()
                        .fill(first ? SR.accent : (me ? SR.good : SR.inkGhost))
                        .frame(width: geo.size.width * (grown ? share : 0))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plate-round-\(result.round)-\(row.playerId)")
    }
}

// MARK: - Finished

struct PassThePlateFinished: View {
    let room: GameRoom
    @ObservedObject var store: PassThePlateStore
    let done: () -> Void
    @State private var record: TableGameRecord?

    private var state: PassThePlateState? { room.passThePlate }
    private var iWon: Bool { room.winnerIds.contains(room.meId) }
    private var gameKey: String { TableGameKey.finished(roomId: room.id, startedAt: room.startedAt) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Pass the Plate · \(PassThePlateSettings.about(difficulty: room.difficulty)) · final",
                             title: GameResults.title(room, solo: "Game over", none: "Nobody won"),
                             strap: GameResults.strap(room))

                if let dessert = dessertLine { dessertCard(dessert) }

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

                if let record {
                    TableRecordCard(record: record, gameKey: gameKey, bestLabel: "Best score", id: "plate-record")
                }

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
        .overlay {
            if iWon { TableCelebration(colours: TableCheer.colours, bursts: 7, duration: 3.4, seed: 23) }
        }
        .accessibilityIdentifier("plate-finished")
        .onAppear(perform: noteRecord)
    }

    /// The ice cream, said once: who had most scoops, and what it was worth.
    private var dessertLine: String? {
        guard let dessert = state?.dessert, !dessert.isEmpty else { return nil }
        let best = dessert.map(\.points).max() ?? 0
        guard best > 0 else { return "Nobody won the ice cream." }
        let names = dessert.filter { $0.points == best }.map { $0.playerId == room.meId ? "You" : room.name(of: $0.playerId) }
        let scoops = dessert.first { $0.points == best }?.scoops ?? 0
        let verb = names.count == 1 ? "had" : "shared"
        return "\(GameNames.list(names)) \(verb) the most ice cream — \(GameResults.count(scoops, "scoop", "scoops")), +\(best)."
    }

    private func dessertCard(_ line: String) -> some View {
        HStack(spacing: 14) {
            Text("🍨")
                .font(.system(size: 40))
                .frame(width: 64, height: 64)
                .background(Circle().fill(PassThePlatePaint.family("dessert").opacity(0.2)))
                .tablePopIn()
                .accessibilityHidden(true)
            Text(line)
                .font(SR.Text.bodyMedium(16))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plate-dessert")
    }

    private func noteRecord() {
        guard let mine = standing(room.meId) else { return }
        let book = TableGameBestStore(gameId: GameKind.passThePlate.rawValue, persists: !SRDemo.isOn)
        record = book.note(variant: GameKind.passThePlate.rawValue, key: gameKey, won: iWon, score: mine.score)
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
