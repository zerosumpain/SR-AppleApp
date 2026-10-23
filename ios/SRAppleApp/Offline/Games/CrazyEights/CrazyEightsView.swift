import SwiftUI

/// Crazy Eights on one phone: the table, my hand, and the hand's result.
///
/// The host decides everything; this view draws the latest `PlayerView` and
/// sends one action at a time. Tapping a card that fits plays it at once —
/// an eight first asks which suit to name. Cards that do not fit are dimmed,
/// so the only thing to learn is "match the suit or the number". Draw and
/// Pass sit under the hand and only appear when they are allowed.
struct CrazyEightsView: View {
    let context: OfflineGameContext<CrazyEightsRules>
    /// An eight waiting for its suit to be named.
    @State private var pendingEight: OfflineCard?
    /// An action has gone to the host and its answer has not come back yet,
    /// so a double tap sends once. Any new view clears it.
    @State private var waiting = false

    private var view: CrazyEightsRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: kicker, title: title, strap: strap)
                seats
                switch view.phase {
                case .playing:
                    pile
                    if let line = lastMoveText {
                        Text(line)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("offline-crazy-eights-last-move")
                    }
                    if playing { myHand }
                case .handOver, .over:
                    result
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .onChange(of: view) { _, _ in
            waiting = false
        }
        .onChange(of: view.turnNumber) { _, _ in
            pendingEight = nil
        }
        .onChange(of: context.refusal) { _, new in
            if new != nil {
                SRHaptic.bad()
                waiting = false
            }
        }
        .task(id: waiting) {
            // A lost answer (or a repeated refusal, which changes nothing)
            // must not leave the hand locked: give up waiting after a while.
            guard waiting else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { waiting = false }
        }
    }

    // MARK: - Words

    /// Whether I hold a seat in this match and am still here.
    private var playing: Bool {
        view.seats.contains { $0.id == context.me && !$0.away }
    }

    private var myTurn: Bool { view.turnPlayer == context.me }

    private func who(_ id: String) -> String {
        id == context.me ? "You" : context.name(of: id)
    }

    private var kicker: String {
        "Hand \(view.hand) of \(view.maxHands) · to \(view.targetScore)"
    }

    private var title: String {
        switch view.phase {
        case .playing:
            guard let turn = view.turnPlayer else { return "Crazy Eights" }
            return turn == context.me ? "Your turn" : "\(context.name(of: turn))'s turn"
        case .handOver:
            guard let winner = view.handWinner else { return "Nobody could go" }
            return winner == context.me ? "You went out" : "\(context.name(of: winner)) went out"
        case .over:
            let names = view.champions.map { who($0) }
            if names.count == 1 { return names[0] == "You" ? "You win" : "\(names[0]) wins" }
            return names.isEmpty ? "Game over" : "A tie"
        }
    }

    /// What to do now, in one sentence.
    private var strap: String? {
        guard view.phase == .playing else {
            return view.phase == .over ? "Lowest penalty total wins." : nil
        }
        if !playing { return "You are watching this game." }
        guard myTurn else { return "Wait for your turn. Follow \(view.suit.name) or the number." }
        if pendingEight != nil { return "Name the suit the next player must follow." }
        if let drawn = view.drawn { return "You drew the \(drawn.name). Play it, or pass." }
        if view.playable.isEmpty {
            return view.canDraw ? "Nothing fits — draw a card." : "Nothing fits and nothing to draw — pass."
        }
        return "Tap a card to play it: \(view.suit.name), the same number, or an eight."
    }

    private var lastMoveText: String? {
        guard let move = view.lastMove else { return nil }
        let name = who(move.playerId)
        switch move.kind {
        case .played:
            guard let card = move.card else { return nil }
            if let named = move.named { return "\(name) played the \(card.name) and named \(named.name)." }
            return "\(name) played the \(card.name)."
        case .drew: return "\(name) drew a card."
        case .passed: return "\(name) passed."
        case .timedOut: return "\(name) ran out of time."
        }
    }

    // MARK: - The players

    private var seats: some View {
        VStack(spacing: 0) {
            ForEach(Array(view.seats.enumerated()), id: \.element.id) { index, seat in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack(spacing: 10) {
                    OfflineInitial(name: seat.name, size: 28, tone: OfflineSeatColour.of(index))
                    Text(seat.id == context.me ? "You" : seat.name)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(seat.away ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if view.turnPlayer == seat.id {
                        Image(systemName: "arrowtriangle.left.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SR.accent)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 6)
                    Text(seat.away ? "left" : cardsText(seat.cards))
                        .font(SR.Text.mono(13))
                        .foregroundStyle(SR.inkSecondary)
                        .lineLimit(1)
                        .fixedSize()
                    Text("\(seat.score)")
                        .font(SR.Text.mono(15))
                        .foregroundStyle(SR.ink)
                        .frame(minWidth: 30, alignment: .trailing)
                        .fixedSize()
                }
                .frame(minHeight: 40)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(seatLabel(seat))
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-crazy-eights-seats")
    }

    private func cardsText(_ count: Int) -> String {
        count == 1 ? "1 card" : "\(count) cards"
    }

    private func seatLabel(_ seat: CrazyEightsRules.Seat) -> String {
        var parts = [seat.id == context.me ? "You" : seat.name]
        parts.append(seat.away ? "left the game" : cardsText(seat.cards))
        parts.append("\(seat.score) penalty points")
        if view.turnPlayer == seat.id { parts.append("their turn") }
        return parts.joined(separator: ", ")
    }

    // MARK: - The table

    private var pile: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(spacing: 6) {
                OfflineCardBack(width: 64)
                    .opacity(view.stockCount > 0 ? 1 : 0.3)
                Text("\(view.stockCount) left")
                    .font(SR.Text.mono(12))
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stock, \(view.stockCount) cards")

            VStack(spacing: 6) {
                if let top = view.top {
                    OfflineCardFace(card: top, width: 64)
                } else {
                    OfflineCardBack(width: 64).opacity(0.3)
                }
                Text("pile")
                    .font(SR.Text.mono(12))
                    .foregroundStyle(SR.inkMuted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(view.top.map { "Top of the pile: \($0.name)" } ?? "The pile is empty")

            VStack(alignment: .leading, spacing: 6) {
                Text("FOLLOW")
                    .font(SR.Text.label(12))
                    .tracking(1.4)
                    .foregroundStyle(SR.inkMuted)
                HStack(spacing: 6) {
                    Text(view.suit.symbol)
                        .font(.system(size: 30))
                        .foregroundStyle(view.suit.isRed ? SR.error : SR.ink)
                    Text(view.suit.name)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if myTurn {
                    OfflineCountdown(clock: context.clock, until: view.turnEndsAt,
                                     font: SR.Text.mono(13), tone: SR.inkMuted)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Follow \(view.suit.name)")
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-crazy-eights-pile")
    }

    // MARK: - My hand

    private var myHand: some View {
        VStack(alignment: .leading, spacing: 14) {
            SRSectionLabel(text: "Your hand", trailing: cardsText(view.myCards.count))
            Group {
                if myTurn {
                    OfflineHand(
                        cards: view.myCards,
                        cardWidth: 64,
                        selected: pendingEight.map { Set([$0.id]) } ?? Set<String>(),
                        playable: waiting ? Set<String>() : Set(view.playable),
                        onTap: { card in tapped(card) }
                    )
                } else {
                    // Nothing to tap between turns, so the hand is drawn at
                    // full strength to read rather than dimmed as unplayable.
                    OfflineHand(cards: view.myCards, cardWidth: 64)
                }
            }
            .accessibilityIdentifier("offline-crazy-eights-hand")

            if myTurn {
                if let eight = pendingEight {
                    suitPicker(for: eight)
                } else {
                    turnButtons
                }
            }
        }
    }

    private var turnButtons: some View {
        HStack(spacing: 10) {
            if view.canDraw {
                Button {
                    SRHaptic.tap()
                    send(.draw(turn: view.turnNumber))
                } label: {
                    SRButtonLabel(title: "Draw", icon: "plus.rectangle.on.rectangle", fill: true)
                }
                .srButton(view.playable.isEmpty ? .prominent : .regular)
                .controlSize(.large)
                .disabled(waiting)
                .accessibilityIdentifier("offline-crazy-eights-draw")
                .accessibilityLabel("Draw a card")
            }
            if view.canPass {
                Button {
                    SRHaptic.tap()
                    send(.pass(turn: view.turnNumber))
                } label: {
                    SRButtonLabel(title: "Pass", icon: "arrow.uturn.forward", fill: true)
                }
                .srButton(view.drawn == nil && view.playable.isEmpty ? .prominent : .regular)
                .controlSize(.large)
                .disabled(waiting)
                .accessibilityIdentifier("offline-crazy-eights-pass")
                .accessibilityLabel("Pass your turn")
            }
        }
    }

    /// Four suits as a two-by-two grid, so the buttons stay wide on any phone.
    private func suitPicker(for eight: OfflineCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Name a suit", trailing: eight.text)
            ForEach([[OfflineSuit.clubs, .diamonds], [.hearts, .spades]], id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row) { suit in
                        Button {
                            SRHaptic.ok()
                            pendingEight = nil
                            send(.play(turn: view.turnNumber, card: eight, suit: suit))
                        } label: {
                            SRButtonLabel(title: "\(suit.symbol) \(suit.name)", fill: true)
                        }
                        .srButton(.regular)
                        .controlSize(.large)
                        .accessibilityLabel("Name \(suit.name)")
                        .accessibilityIdentifier("offline-crazy-eights-suit-\(suit.rawValue)")
                    }
                }
            }
            Button {
                SRHaptic.tap()
                pendingEight = nil
            } label: {
                SRButtonLabel(title: "Cancel", fill: true)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("offline-crazy-eights-suit-cancel")
        }
    }

    // MARK: - A hand's result

    private var result: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            if view.phase == .handOver {
                SRSectionLabel(text: "This hand", trailing: "penalty · total")
            }
            VStack(spacing: 0) {
                ForEach(Array(view.seats.enumerated()), id: \.element.id) { index, seat in
                    if index > 0 { Divider().overlay(SR.divider) }
                    HStack(spacing: 10) {
                        Text(seat.id == context.me ? "You" : seat.name)
                            .font(SR.Text.title())
                            .foregroundStyle(seat.away ? SR.inkMuted : SR.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if seat.id == view.handWinner {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SR.accent)
                                .accessibilityHidden(true)
                        }
                        Spacer(minLength: 8)
                        if let penalty = seat.lastPenalty {
                            Text("+\(penalty)")
                                .font(SR.Text.mono(15))
                                .foregroundStyle(penalty == 0 ? SR.good : SR.inkSecondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        Text("\(seat.score)")
                            .font(SR.Text.display(20))
                            .foregroundStyle(SR.ink)
                            .frame(minWidth: 34, alignment: .trailing)
                            .fixedSize()
                    }
                    .frame(minHeight: SR.tapTarget)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(resultLabel(seat))
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)

            if view.phase == .handOver {
                HStack(spacing: 8) {
                    Text("Next hand in")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                    OfflineCountdown(clock: context.clock, until: view.nextHandAt,
                                     font: SR.Text.mono(), tone: SR.inkMuted)
                }
            }
        }
        .accessibilityIdentifier("offline-crazy-eights-result")
    }

    private func resultLabel(_ seat: CrazyEightsRules.Seat) -> String {
        var parts = [seat.id == context.me ? "You" : seat.name]
        if seat.id == view.handWinner { parts.append("went out") }
        if let penalty = seat.lastPenalty { parts.append("\(penalty) this hand") }
        parts.append("\(seat.score) in total")
        return parts.joined(separator: ", ")
    }

    // MARK: - Acting

    private func tapped(_ card: OfflineCard) {
        guard myTurn, !waiting, view.playable.contains(card.id) else { return }
        if card.rank == 8 {
            pendingEight = card
        } else {
            send(.play(turn: view.turnNumber, card: card, suit: nil))
        }
    }

    private func send(_ action: CrazyEightsRules.Action) {
        waiting = true
        context.send(action)
    }
}
