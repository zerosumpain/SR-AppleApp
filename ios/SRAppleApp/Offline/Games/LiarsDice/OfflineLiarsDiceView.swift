import SwiftUI

/// Liar's Dice on one phone: whose bid and the turn clock, my cup, the bid
/// standing and the round's bids, the bid picker and Liar! on my turn, the
/// lifted cups after a call, and everyone's dice left.
///
/// The dice are the online game's `LiarsDie`, so the cups look the same as
/// on the site; mine light up when they count towards the standing bid's
/// face (ones always do — they are wild). The picker starts on the smallest
/// raise and checks every bid with the rules' own `problem` before sending,
/// so a mistake is explained before it reaches the host.
struct OfflineLiarsDiceView: View {
    let context: OfflineGameContext<OfflineLiarsDiceRules>
    /// The bid being put together on my turn.
    @State private var quantity = 1
    @State private var face = 2
    /// An action has gone to the host and its answer has not come back yet.
    @State private var waiting = false

    private typealias Rules = OfflineLiarsDiceRules
    private var view: Rules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SRPageHeader(kicker: kicker, title: title, strap: strap)
                if view.phase == .bidding { turnBar }
                if let reveal = view.reveal { revealCard(reveal) }
                if !view.myDice.isEmpty && view.phase == .bidding { myCup }
                if view.phase == .bidding { bidsCard }
                if myTurn { picker }
                seatsCard
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("offline-liars-dice")
        .onAppear { resetPicker() }
        .onChange(of: view) { _, _ in waiting = false }
        .onChange(of: view.turnNumber) { _, _ in
            resetPicker()
            if myTurn { SRHaptic.tap() }
        }
        .onChange(of: view.phase) { _, new in
            if new == .reveal, let reveal = view.reveal {
                if reveal.loserId == context.me { SRHaptic.bad() } else { SRHaptic.ok() }
            }
        }
        .onChange(of: context.refusal) { _, new in
            if new != nil {
                SRHaptic.bad()
                waiting = false
            }
        }
        .task(id: waiting) {
            guard waiting else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { waiting = false }
        }
    }

    // MARK: - Words

    private var myTurn: Bool { view.phase == .bidding && view.turnPlayer == context.me }

    private var standing: Rules.Bid? { view.bids.last }

    private func who(_ id: String) -> String { id == context.me ? "You" : context.name(of: id) }

    private var kicker: String {
        "Liar's Dice · Round \(view.round) · \(view.totalDice) dice in play"
    }

    private var title: String {
        switch view.phase {
        case .bidding:
            if myTurn { return "Your bid" }
            guard let turn = view.turnPlayer else { return "Liar's Dice" }
            return "\(context.name(of: turn)) is bidding"
        case .reveal:
            guard let reveal = view.reveal else { return "Cups up" }
            return reveal.bidStood ? "The bid stood" : "Caught out"
        case .done, .over:
            guard let winner = view.winner else { return "Game over" }
            return winner == context.me ? "You win" : "\(context.name(of: winner)) wins"
        }
    }

    private var strap: String? {
        switch view.phase {
        case .bidding:
            if view.myDice.isEmpty {
                return view.seats.contains(where: { $0.id == context.me }) ? "You are out of dice — watch the rest." : "You are watching this game."
            }
            if let standing {
                let bid = Rules.bidText(quantity: standing.quantity, face: standing.face)
                return "\(who(standing.playerId)) bid \(bid)\(standing.auto ? " (time ran out)" : ""). Ones are wild."
            }
            return myTurn ? "Open the bidding. Ones are wild." : "Waiting for the first bid. Ones are wild."
        case .reveal:
            return view.reveal.map { Rules.revealLine($0, name: who) }
        case .done, .over:
            return view.reveal.map { Rules.revealLine($0, name: who) }
        }
    }

    // MARK: - The turn

    private var turnBar: some View {
        HStack(spacing: 10) {
            if let turn = view.turnPlayer {
                OfflineInitial(name: context.name(of: turn), size: 28, tone: seatTone(turn))
                Text(turn == context.me ? "Your turn" : "\(context.name(of: turn)) is thinking")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 6)
            Image(systemName: "timer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SR.inkSecondary)
                .accessibilityHidden(true)
            OfflineCountdown(clock: context.clock, until: view.turnEndsAt, font: SR.Text.display(22),
                             tone: myTurn ? SR.accent : SR.ink)
                .fixedSize()
        }
        .padding(.horizontal, SR.cardPadding)
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 4)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-liars-dice-turn")
    }

    private func seatTone(_ id: String) -> Color {
        OfflineSeatColour.of(view.seats.firstIndex { $0.id == id } ?? 0)
    }

    // MARK: - My cup

    private var myCup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Your cup", trailing: view.myDice.count == 1 ? "1 die" : "\(view.myDice.count) dice")
            GeometryReader { geo in
                let side = min(56, (geo.size.width - 4 * 8) / 5)
                HStack(spacing: 8) {
                    ForEach(Array(view.myDice.enumerated()), id: \.offset) { _, die in
                        LiarsDie(face: die, side: side, lit: standing.map { Rules.counts(die, towards: $0.face) } ?? false)
                    }
                }
            }
            .frame(height: 56)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your dice: " + view.myDice.map(String.init).joined(separator: ", "))
            .accessibilityIdentifier("offline-liars-dice-cup")
        }
    }

    // MARK: - The bids

    private var bidsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "This round", trailing: view.bids.isEmpty ? "no bids yet" : nil)
            if let standing {
                HStack(spacing: 12) {
                    LiarsDie(face: standing.face, side: 40, lit: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Rules.bidText(quantity: standing.quantity, face: standing.face))
                            .font(SR.Text.display(22))
                            .foregroundStyle(SR.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("bid by \(who(standing.playerId))")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("offline-liars-dice-standing")
                if view.bids.count > 1 {
                    Text(view.bids.dropLast().map { "\(who($0.playerId)): \(Rules.bidText(quantity: $0.quantity, face: $0.face))" }
                        .joined(separator: " · "))
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    // MARK: - Bidding

    private var problem: String? {
        Rules.problem(quantity: quantity, face: face, standing: standing, total: view.totalDice)
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Your bid")
            HStack(spacing: 12) {
                stepButton("minus", label: "One fewer") { quantity = max(1, quantity - 1) }
                    .disabled(quantity <= 1)
                Text("\(quantity)")
                    .font(SR.Text.figure(30))
                    .foregroundStyle(SR.ink)
                    .frame(minWidth: 44)
                    .accessibilityLabel("\(quantity) dice")
                stepButton("plus", label: "One more") { quantity = min(view.totalDice, quantity + 1) }
                    .disabled(quantity >= view.totalDice)
                Text(quantity == 1 ? "die showing" : "dice showing")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ForEach(Rules.lowestFace...Rules.faces, id: \.self) { value in
                    Button {
                        SRHaptic.select()
                        face = value
                    } label: {
                        LiarsDie(face: value, side: 44, lit: face == value)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(value)s")
                    .accessibilityAddTraits(face == value ? .isSelected : [])
                    .accessibilityIdentifier("offline-liars-dice-face-\(value)")
                }
            }
            if let problem {
                Text(problem)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button {
                    send(.bid(turn: view.turnNumber, quantity: quantity, face: face))
                } label: {
                    SRButtonLabel(title: "Bid", icon: "hand.raised.fill", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(problem != nil || waiting)
                .accessibilityLabel("Bid \(Rules.bidText(quantity: quantity, face: face))")
                .accessibilityIdentifier("offline-liars-dice-bid")
                if standing != nil {
                    Button {
                        send(.liar(turn: view.turnNumber))
                    } label: {
                        SRButtonLabel(title: "Liar!", icon: "exclamationmark.bubble.fill", fill: true)
                    }
                    .srButton(.regular)
                    .controlSize(.large)
                    .disabled(waiting)
                    .accessibilityLabel("Call liar")
                    .accessibilityIdentifier("offline-liars-dice-liar")
                }
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-liars-dice-picker")
    }

    private func stepButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .frame(width: SR.tapTarget, height: SR.tapTarget)
        }
        .srButton(.regular)
        .accessibilityLabel(label)
    }

    // MARK: - The cups, lifted

    private func revealCard(_ reveal: Rules.Reveal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Cups up", trailing: reveal.count == 1 ? "1 counted" : "\(reveal.count) counted")
            ForEach(reveal.cups) { cup in
                HStack(spacing: 8) {
                    Text(who(cup.playerId))
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(cup.playerId == reveal.loserId ? SR.error : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 84, alignment: .leading)
                    HStack(spacing: 4) {
                        ForEach(Array(cup.dice.enumerated()), id: \.offset) { _, die in
                            LiarsDie(face: die, side: 30, lit: Rules.counts(die, towards: reveal.bid.face),
                                     dim: !Rules.counts(die, towards: reveal.bid.face))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(who(cup.playerId)): " + cup.dice.map(String.init).joined(separator: ", "))
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-liars-dice-reveal")
    }

    // MARK: - The table

    private var seatsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(view.seats.enumerated()), id: \.element.id) { index, seat in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack(spacing: 10) {
                    OfflineInitial(name: seat.name, size: 26, tone: OfflineSeatColour.of(index))
                        .opacity(seat.out ? 0.4 : 1)
                    Text(seat.id == context.me ? "You" : seat.name)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(seat.out ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if view.turnPlayer == seat.id {
                        Image(systemName: "arrowtriangle.left.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SR.accent)
                            .accessibilityHidden(true)
                    }
                    if view.winner == seat.id {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SR.accent)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 6)
                    Text(seat.left ? "left" : seat.out ? "out" : seat.dice == 1 ? "1 die" : "\(seat.dice) dice")
                        .font(SR.Text.mono(14))
                        .foregroundStyle(seat.out ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(minHeight: 40)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-liars-dice-players")
    }

    // MARK: - Acting

    /// The picker back to the smallest raise (or my favourite face to open).
    private func resetPicker() {
        let preferred = view.myDice.isEmpty ? nil : Rules.favouriteFace(view.myDice)
        if let start = Rules.startingBid(standing: standing, total: view.totalDice, preferred: preferred) {
            quantity = start.quantity
            face = start.face
        }
    }

    private func send(_ action: Rules.Action) {
        guard myTurn, !waiting else { return }
        SRHaptic.tap()
        waiting = true
        context.send(action)
    }
}
