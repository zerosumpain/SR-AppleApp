import SwiftUI
import UIKit

/// One Liar's Dice room, from lobby to the last die.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the table the host picked — dice each, whether ones are wild — as the
/// lobby's panel; Start waits for a second player (there is no solo table).
/// Bidding is my cup — my dice as big pips, nobody else's — over the standing
/// bid, the table (everyone's dice count, whose turn, the turn clock) and this
/// round's bids. On my turn: a quantity stepper and a face picker that only
/// offer legal raises, Bid, and Liar!. A call lifts every cup, lighting the
/// dice that count, and says who lost a die. The finish is the order people
/// went out in.
struct LiarsDiceScreen: View {
    let roomId: String
    @StateObject private var store: LiarsDiceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: LiarsDiceStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Liar's Dice")
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
    }

    private var immersive: Bool {
        guard !store.ended, let room = store.room else { return false }
        return LiarsDiceScreenPhase.of(room) == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "liars-ended", done: { dismiss() })
        } else if let room = store.room {
            switch LiarsDiceScreenPhase.of(room) {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "liars", done: { dismiss() },
                          panel: AnyView(LiarsDiceTableCard(room: room)),
                          startBlocked: room.playing.count < 2)
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Only you can see your dice. Bid on what the whole table holds.",
                                  id: "liars-countdown")
            case .bidding, .reveal:
                LiarsDicePlaying(room: room, store: store)
            case .finished:
                LiarsDiceFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "liars-ended", done: { dismiss() })
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

/// The table the host picked, in the lobby: a little row of dice beside dice
/// each and the rule about ones — and, until somebody else is in, that this
/// game needs two.
struct LiarsDiceTableCard: View {
    let room: GameRoom

    var body: some View {
        let state = room.liarsDice
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    LiarsDie(face: [6, 1, 3][i], side: 20)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(LiarsDiceSettings.about(state).uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text((state?.wildOnes ?? true) ? "Ones are wild" : "No wilds")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(state?.rule ?? "Bid on what the whole table holds, or call the last bid a lie.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if room.playing.count < 2 {
                    Text("Needs at least two players.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .accessibilityIdentifier("liars-needs-two")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("liars-table")
    }
}

// MARK: - A die

/// One die as pips. `face` nil is a die under a cup: a blank with a question
/// mark. `lit` marks a die that counts towards the bid on a reveal; `dim` one
/// that does not.
struct LiarsDie: View {
    let face: Int?
    var side: CGFloat = 52
    var lit: Bool = false
    var dim: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                .fill(face == nil ? SR.accentDeep : lit ? SR.accent : SR.paper)
                .shadow(color: SR.ink.opacity(face == nil || dim ? 0 : 0.22), radius: 0, x: 0, y: max(1, side * 0.04))
            RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                .strokeBorder(SR.ink.opacity(0.12), lineWidth: 1)
            if let face {
                pips(face)
            } else {
                Text("?")
                    .font(SR.Text.display(side * 0.5))
                    .foregroundStyle(SR.paper.opacity(0.8))
            }
        }
        .frame(width: side, height: side)
        .opacity(dim ? 0.4 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(face.map { "\($0)" } ?? "Hidden")
    }

    /// Where the pips sit for each face, on a 3×3 grid (0…8, row-major).
    static func spots(_ face: Int) -> [Int] {
        switch face {
        case 1: return [4]
        case 2: return [2, 6]
        case 3: return [2, 4, 6]
        case 4: return [0, 2, 6, 8]
        case 5: return [0, 2, 4, 6, 8]
        default: return [0, 2, 3, 5, 6, 8]
        }
    }

    private func pips(_ face: Int) -> some View {
        let inset = side * 0.2
        let step = (side - inset * 2) / 2
        let pip = side * 0.18
        let on = Self.spots(face)
        return ZStack(alignment: .topLeading) {
            ForEach(on, id: \.self) { spot in
                Circle()
                    .fill(lit ? SR.paper : SR.ink)
                    .frame(width: pip, height: pip)
                    .offset(x: inset + CGFloat(spot % 3) * step - pip / 2,
                            y: inset + CGFloat(spot / 3) * step - pip / 2)
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
    }
}

// MARK: - Bidding and the reveal

struct LiarsDicePlaying: View {
    let room: GameRoom
    @ObservedObject var store: LiarsDiceStore
    /// The cup is down over my dice: a peek-proof moment when somebody looks over.
    @State private var cupDown = false

    private var state: LiarsDiceState? { room.liarsDice }
    private var revealing: Bool { LiarsDiceScreenPhase.of(room) == .reveal }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if revealing, let reveal = state?.reveal {
                    revealCard(reveal)
                } else {
                    standingBid
                    myCup
                    if room.me?.joined == true, store.myTurn { picker }
                    statusLine
                        .frame(maxWidth: .infinity)
                }
                table
                if let bids = state?.bids, !bids.isEmpty { talk(bids) }
                if let rule = state?.rule {
                    Text(rule)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("liars-rule")
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier(revealing ? "liars-reveal" : "liars-playing")
        .onChange(of: store.refusal) { _, refusal in
            if let refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LIAR'S DICE · ROUND \(state?.round ?? 1) · \(GameDifficulty.label(for: room.difficulty).uppercased())")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(state?.totalDice ?? 0)")
                        .font(SR.Text.display(26))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                    Text("DICE IN PLAY")
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(state?.totalDice ?? 0) dice in play")
                .accessibilityIdentifier("liars-total")
            }
            Spacer(minLength: 8)
        }
    }

    // MARK: The standing bid

    private var standingBid: some View {
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "Standing bid")
            HStack(spacing: 14) {
                if let bid = state?.bid {
                    Text("\(bid.quantity)")
                        .font(SR.Text.hero(44))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                    Text("×")
                        .font(SR.Text.display(26))
                        .foregroundStyle(SR.inkMuted)
                    LiarsDie(face: bid.face, side: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bid.playerId == room.meId ? "Your bid" : "\(room.name(of: bid.playerId))’s bid")
                            .font(SR.Text.title())
                            .foregroundStyle(SR.ink)
                        if bid.auto {
                            Text("TIMED OUT")
                                .font(SR.Text.label())
                                .tracking(1)
                                .foregroundStyle(SR.error)
                        }
                    }
                } else {
                    Text("No bid yet")
                        .font(SR.Text.display(26))
                        .foregroundStyle(SR.inkGhost)
                    Spacer(minLength: 0)
                    Text(opener)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .multilineTextAlignment(.trailing)
                }
                Spacer(minLength: 0)
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(bidSpoken)
            .accessibilityIdentifier("liars-bid")
        }
    }

    private var opener: String {
        guard let turn = state?.turnId else { return "" }
        return turn == room.meId ? "You open." : "\(room.name(of: turn)) opens."
    }

    private var bidSpoken: String {
        guard let bid = state?.bid else { return "No bid yet. \(opener)" }
        let who = bid.playerId == room.meId ? "You" : room.name(of: bid.playerId)
        let timed = bid.auto ? ", timed out" : ""
        return "Standing bid: \(LiarsDiceRules.bidText(quantity: bid.quantity, face: bid.face)), by \(who)\(timed)"
    }

    // MARK: My cup

    private var myCup: some View {
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "Your dice", trailing: store.myDice.isEmpty ? nil : "Only you can see these")
            if store.myDice.isEmpty {
                Text(room.me?.joined == true ? "You are out of dice. Watch the rest play it out." : "You are not playing in this one.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            } else {
                HStack(spacing: 10) {
                    ForEach(Array(store.myDice.enumerated()), id: \.offset) { _, die in
                        LiarsDie(face: cupDown ? nil : die, side: 56, lit: !cupDown && countsTowardsBid(die))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(SR.accentDeep)
                        .shadow(color: SR.ink.opacity(0.18), radius: 8, y: 4)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    SRHaptic.select()
                    withAnimation(.snappy) { cupDown.toggle() }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(cupDown ? "Your dice, under the cup" : "Your dice: \(store.myDice.map(String.init).joined(separator: ", "))")
                .accessibilityHint(cupDown ? "Lifts the cup" : "Puts the cup down")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { cupDown.toggle() }
                .accessibilityIdentifier("liars-my-dice")
                Text(cupDown ? "Tap the cup to peek." : "Tap to put the cup down.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Whether one of my dice counts towards the standing bid's face.
    private func countsTowardsBid(_ die: Int) -> Bool {
        guard let state, let bid = state.bid else { return false }
        return LiarsDiceRules.counts(die, towards: bid.face, wild: state.wildOnes)
    }

    // MARK: The picker

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Your turn")
            if store.canBid {
                HStack(spacing: 12) {
                    Button { store.lowerQuantity() } label: {
                        Image(systemName: "minus")
                            .font(SR.Text.title())
                            .frame(minWidth: SR.tapTarget, minHeight: 30)
                    }
                    .srButton(.regular)
                    .disabled(!store.canLowerQuantity)
                    .accessibilityLabel("Fewer dice")
                    .accessibilityIdentifier("liars-quantity-down")
                    Text("\(store.quantity)")
                        .font(SR.Text.hero(40))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                        .frame(minWidth: 56)
                        .accessibilityLabel("\(store.quantity) dice")
                        .accessibilityIdentifier("liars-quantity")
                    Button { store.raiseQuantity() } label: {
                        Image(systemName: "plus")
                            .font(SR.Text.title())
                            .frame(minWidth: SR.tapTarget, minHeight: 30)
                    }
                    .srButton(.regular)
                    .disabled(!store.canRaiseQuantity)
                    .accessibilityLabel("More dice")
                    .accessibilityIdentifier("liars-quantity-up")
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    ForEach(LiarsDiceRules.biddableFaces(wild: state?.wildOnes ?? true), id: \.self) { f in
                        let legal = store.faceIsLegal(f)
                        Button { store.pick(face: f) } label: {
                            LiarsDie(face: f, side: 40, lit: store.face == f, dim: !legal)
                                .frame(minWidth: SR.tapTarget, minHeight: SR.tapTarget)
                        }
                        .buttonStyle(.plain)
                        .disabled(!legal)
                        .accessibilityLabel("\(f)s")
                        .accessibilityAddTraits(store.face == f ? .isSelected : [])
                        .accessibilityIdentifier("liars-face-\(f)")
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("No bid can go higher than every die on the table. Call it.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            HStack(spacing: 10) {
                Button { store.callLiar() } label: {
                    SRButtonLabel(title: "Liar!", icon: "hand.raised.fill", fill: true)
                }
                .srButton(.regular)
                .controlSize(.large)
                .disabled(!store.canCall)
                .accessibilityIdentifier("liars-call")
                Button { store.bid() } label: {
                    SRButtonLabel(title: "Bid \(LiarsDiceRules.bidText(quantity: store.quantity, face: store.face))",
                                  icon: "arrow.up", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(!store.canBid || !store.pickedIsLegal || store.sending)
                .accessibilityIdentifier("liars-bid-send")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let refusal = store.refusal {
            Label(refusal, systemImage: "exclamationmark.circle")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.error)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("liars-refusal")
        } else if !store.myTurn, let turn = state?.turnId, room.me?.joined == true {
            Text("Waiting for \(room.name(of: turn))…")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .accessibilityIdentifier("liars-waiting")
        }
    }

    // MARK: The table

    private var table: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "The table")
            VStack(spacing: 0) {
                let seated = room.players.filter { state?.seat($0.id)?.seated ?? $0.joined }
                ForEach(Array(seated.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { Divider().overlay(SR.divider) }
                    seatRow(player)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liars-seats")
    }

    private func seatRow(_ player: GamePlayer) -> some View {
        let seat = state?.seat(player.id)
        let count = seat?.diceCount ?? 0
        let out = seat?.out == true || !player.joined
        let turn = !revealing && state?.turnId == player.id
        let me = player.id == room.meId
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                GameInitial(name: me ? "You" : player.name, tone: turn ? SR.accent : SR.accentInk)
                Text(player.name + (me ? " (you)" : ""))
                    .font(SR.Text.title())
                    .foregroundStyle(out ? SR.inkGhost : SR.ink)
                    .strikethrough(out, color: SR.inkMuted)
                    .lineLimit(1)
                if turn {
                    Text("TO BID")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.accent)
                }
                Spacer(minLength: 8)
                if out {
                    Text(player.joined ? "OUT" : "LEFT")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                } else {
                    HStack(spacing: 3) {
                        ForEach(0..<count, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(me ? SR.accent : SR.accentDeep)
                                .frame(width: 12, height: 12)
                        }
                    }
                    Text("\(count)")
                        .font(SR.Text.figure(18))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                        .frame(minWidth: 20, alignment: .trailing)
                }
            }
            if turn {
                LiarsDiceTurnBar(room: room, store: store)
            }
        }
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seatSpoken(player, count: count, out: out, turn: turn))
        .accessibilityIdentifier("liars-seat-\(player.id)")
    }

    private func seatSpoken(_ player: GamePlayer, count: Int, out: Bool, turn: Bool) -> String {
        let who = player.id == room.meId ? "You" : player.name
        if out { return "\(who), \(player.joined ? "out" : "left")" }
        return "\(who), \(GameResults.count(count, "die", "dice"))\(turn ? ", bidding now" : "")"
    }

    // MARK: Table talk

    private func talk(_ bids: [LiarsDiceBid]) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "This round", trailing: GameResults.count(bids.count, "bid", "bids"))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(bids.enumerated().reversed()), id: \.offset) { index, bid in
                    HStack(spacing: 8) {
                        Text(bid.playerId == room.meId ? "You" : room.name(of: bid.playerId))
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(index == bids.count - 1 ? SR.ink : SR.inkMuted)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if bid.auto {
                            Text("TIMED OUT")
                                .font(SR.Text.label())
                                .tracking(1)
                                .foregroundStyle(SR.error)
                        }
                        Text("\(bid.quantity) ×")
                            .font(SR.Text.figure(18))
                            .foregroundStyle(SR.ink)
                            .monospacedDigit()
                        LiarsDie(face: bid.face, side: 22)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(bid.playerId == room.meId ? "You" : room.name(of: bid.playerId)) bid \(LiarsDiceRules.bidText(quantity: bid.quantity, face: bid.face))\(bid.auto ? ", timed out" : "")")
                }
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liars-talk")
    }

    // MARK: The reveal

    private func revealCard(_ reveal: LiarsDiceReveal) -> some View {
        LiarsDiceRevealCard(room: room, reveal: reveal)
    }
}

/// Every cup lifted after a call: the bid, the count, who lost a die, and each
/// player's dice with the ones that count lit.
struct LiarsDiceRevealCard: View {
    let room: GameRoom
    let reveal: LiarsDiceReveal

    private var wild: Bool { room.liarsDice?.wildOnes ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Cups up")
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(reveal.count)")
                        .font(SR.Text.hero(44))
                        .foregroundStyle(reveal.bidStood ? SR.good : SR.error)
                        .monospacedDigit()
                    Text("OF \(reveal.bid.quantity) BID")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                    Spacer(minLength: 0)
                    LiarsDie(face: reveal.bid.face, side: 36)
                }
                Text(LiarsDiceRules.revealLine(reveal) { $0 == room.meId ? "You" : room.name(of: $0) })
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("liars-reveal-line")
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)

            VStack(spacing: 0) {
                ForEach(Array(reveal.dice.enumerated()), id: \.element.id) { index, cup in
                    if index > 0 { Divider().overlay(SR.divider) }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(cup.playerId == room.meId ? "You" : room.name(of: cup.playerId))
                                .font(SR.Text.title())
                                .foregroundStyle(SR.ink)
                            if cup.playerId == reveal.loserId {
                                Text(reveal.eliminated ? "OUT" : "−1 DIE")
                                    .font(SR.Text.label())
                                    .tracking(1)
                                    .foregroundStyle(SR.error)
                            }
                            Spacer(minLength: 8)
                            Text("\(LiarsDiceRules.tally([cup.dice], face: reveal.bid.face, wild: wild))")
                                .font(SR.Text.figure(18))
                                .foregroundStyle(SR.accent)
                                .monospacedDigit()
                        }
                        HStack(spacing: 6) {
                            ForEach(Array(cup.dice.enumerated()), id: \.offset) { _, die in
                                let hit = LiarsDiceRules.counts(die, towards: reveal.bid.face, wild: wild)
                                LiarsDie(face: die, side: 34, lit: hit, dim: !hit)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(cupSpoken(cup))
                    .accessibilityIdentifier("liars-cup-\(cup.playerId)")
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liars-reveal-card")
    }

    private func cupSpoken(_ cup: LiarsDiceCup) -> String {
        let who = cup.playerId == room.meId ? "You" : room.name(of: cup.playerId)
        let n = LiarsDiceRules.tally([cup.dice], face: reveal.bid.face, wild: wild)
        return "\(who): \(cup.dice.map(String.init).joined(separator: ", ")). \(n) counting."
    }
}

/// The turn running out: a bar that empties towards the turn clock and warms
/// as it goes — Boggle's sand, a turn long.
struct LiarsDiceTurnBar: View {
    let room: GameRoom
    @ObservedObject var store: LiarsDiceStore

    var body: some View {
        // Ticks, not an animation: a bar that is always animating keeps the app
        // from ever going idle, and UI tests then cannot read the screen.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let left = CGFloat(LiarsDiceRules.turnLeft(endsAt: room.phaseEndsAt, turnMs: room.liarsDice?.turnMs ?? 45_000,
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
        .accessibilityIdentifier("liars-turn-bar")
    }
}

// MARK: - Finished

struct LiarsDiceFinished: View {
    let room: GameRoom
    @ObservedObject var store: LiarsDiceStore
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Liar's Dice · \(LiarsDiceSettings.about(room.liarsDice)) · final",
                             title: GameResults.title(room, solo: "Game over", none: "Nobody won"),
                             strap: GameResults.strap(room))

                GameStandingsCard(
                    room: room,
                    label: "Standings",
                    id: "liars-standings",
                    detail: detail,
                    figure: { row in
                        let dice = standing(row.id)?.dice ?? 0
                        return dice > 0 ? (text: "\(dice)", spoken: GameResults.count(dice, "die", "dice") + " left") : nil
                    }
                )

                if let reveal = room.liarsDice?.reveal {
                    LiarsDiceRevealCard(room: room, reveal: reveal)
                }

                GameFinishedButtons(room: room, store: store, prefix: "liars", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("liars-finished")
        .onAppear { if room.winnerIds.contains(room.meId) { SRHaptic.ok() } }
    }

    private func standing(_ id: String) -> LiarsDiceStanding? {
        room.liarsDice?.standings?.first { $0.id == id }
    }

    private func detail(_ row: GameStanding) -> String {
        guard let s = standing(row.id) else { return "" }
        if room.winnerIds.contains(row.id) { return "Last one with dice" }
        if s.left { return s.outRound.map { "Left in round \($0)" } ?? "Left" }
        return s.outRound.map { "Out in round \($0)" } ?? "Out"
    }
}
