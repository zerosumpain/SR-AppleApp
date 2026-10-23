import SwiftUI

/// Knockout Whist on one phone: who is still in, the trick on the table,
/// trumps, and my hand.
///
/// The host decides everything; this view draws the latest `PlayerView` and
/// sends one action at a time. On my turn the cards I may play are bright and
/// the rest dimmed — so "follow suit if you can" is shown rather than
/// explained — and tapping one plays it. When I took the most tricks, the
/// next hand opens with four suit buttons to name trumps. A player who is
/// knocked out keeps watching with an empty hand.
struct KnockoutWhistView: View {
    let context: OfflineGameContext<KnockoutWhistRules>
    /// An action has gone to the host and its answer has not come back yet,
    /// so a double tap sends once. Any new view clears it.
    @State private var waiting = false

    private var view: KnockoutWhistRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: kicker, title: title, strap: strap)
                seats
                switch view.phase {
                case .choosingTrump:
                    if view.chooser == context.me {
                        suitPicker
                    } else {
                        choosingNote
                    }
                    if stillIn { myHand }
                case .playing, .trickWon:
                    table
                    if stillIn { myHand }
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
        .onChange(of: context.refusal) { _, new in
            if new != nil {
                SRHaptic.bad()
                waiting = false
            }
        }
        .task(id: waiting) {
            // A lost answer must not leave the hand locked: give up waiting after a while.
            guard waiting else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { waiting = false }
        }
    }

    // MARK: - Words

    private var mySeat: KnockoutWhistRules.Seat? {
        view.seats.first { $0.id == context.me }
    }

    /// I hold a seat, have not been knocked out and have not left.
    private var stillIn: Bool {
        guard let seat = mySeat else { return false }
        return !seat.out && !seat.away
    }

    private var myTurn: Bool { view.phase == .playing && view.turnPlayer == context.me }

    private func who(_ id: String) -> String {
        id == context.me ? "You" : context.name(of: id)
    }

    private var kicker: String {
        let cards = view.handSize == 1 ? "1 card each" : "\(view.handSize) cards each"
        return "Hand \(view.hand) · \(cards)"
    }

    private var title: String {
        switch view.phase {
        case .choosingTrump:
            guard let chooser = view.chooser else { return "Naming trumps" }
            return chooser == context.me ? "Name trumps" : "\(context.name(of: chooser)) picks trumps"
        case .playing:
            guard let turn = view.turnPlayer else { return "Knockout Whist" }
            return turn == context.me ? "Your turn" : "\(context.name(of: turn))'s turn"
        case .trickWon:
            guard let winner = view.trickWinner else { return "Trick taken" }
            return winner == context.me ? "You take the trick" : "\(context.name(of: winner)) takes it"
        case .handOver, .over:
            if let champion = view.champion {
                return champion == context.me ? "You win" : "\(context.name(of: champion)) wins"
            }
            if view.knockedOut.contains(context.me) { return "You're out" }
            switch view.knockedOut.count {
            case 0: return "Nobody is out"
            case 1: return "\(context.name(of: view.knockedOut[0])) is out"
            default: return "\(view.knockedOut.count) players are out"
            }
        }
    }

    /// What to do now, in one sentence.
    private var strap: String? {
        let trumps = view.trump.map { "Trumps are \($0.name)." } ?? ""
        switch view.phase {
        case .over:
            return "The last player standing wins."
        case .handOver:
            if view.champion != nil { return "The last player standing wins." }
            guard let next = view.nextChooser else { return nil }
            let size = max(1, view.handSize - 1)
            let cards = size == 1 ? "1 card" : "\(size) cards"
            return next == context.me
                ? "You took the most tricks, so you name trumps for the next hand of \(cards)."
                : "\(context.name(of: next)) took the most tricks and names trumps for the next hand of \(cards)."
        case .trickWon:
            return "The next trick starts in a moment. \(trumps)"
        case .choosingTrump:
            if view.chooser == context.me {
                return "You took the most tricks. Look at your cards, then pick the suit that beats the rest."
            }
            return stillIn ? "Wait while trumps are chosen, then the chooser leads." : watchingLine
        case .playing:
            guard stillIn else { return watchingLine }
            guard myTurn else { return "Wait for your turn. \(trumps)" }
            guard let led = view.ledSuit else { return "Lead any card. \(trumps)" }
            if view.myCards.contains(where: { $0.suit == led }) { return "Follow \(led.name) — play one of yours. \(trumps)" }
            return "No \(led.name) left — play anything; a trump can win it. \(trumps)"
        }
    }

    private var watchingLine: String {
        mySeat?.out == true ? "You've been knocked out — watch the rest." : "You are watching this game."
    }

    // MARK: - The players

    private var seats: some View {
        VStack(spacing: 0) {
            ForEach(Array(view.seats.enumerated()), id: \.element.id) { index, seat in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack(spacing: 10) {
                    OfflineInitial(name: seat.name, size: 28,
                                   tone: seat.out ? SR.inkGhost : OfflineSeatColour.of(index))
                    Text(seat.id == context.me ? "You" : seat.name)
                        .font(SR.Text.bodyMedium(15))
                        .strikethrough(seat.out, color: SR.inkMuted)
                        .foregroundStyle(seat.out ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if isActing(seat.id) {
                        Image(systemName: "arrowtriangle.left.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SR.accent)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 6)
                    Text(seatStatus(seat))
                        .font(SR.Text.mono(13))
                        .foregroundStyle(SR.inkSecondary)
                        .lineLimit(1)
                        .fixedSize()
                    Text("\(seat.tricks)")
                        .font(SR.Text.mono(15))
                        .foregroundStyle(seat.out ? SR.inkMuted : SR.ink)
                        .frame(minWidth: 24, alignment: .trailing)
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
        .accessibilityIdentifier("offline-knockout-whist-seats")
    }

    /// The seat whose move the table is waiting for.
    private func isActing(_ id: String) -> Bool {
        (view.phase == .playing && view.turnPlayer == id) || (view.phase == .choosingTrump && view.chooser == id)
    }

    private func cardsText(_ count: Int) -> String {
        count == 1 ? "1 card" : "\(count) cards"
    }

    private func seatStatus(_ seat: KnockoutWhistRules.Seat) -> String {
        if seat.away { return "left" }
        if seat.out { return "out" }
        return cardsText(seat.cards)
    }

    private func seatLabel(_ seat: KnockoutWhistRules.Seat) -> String {
        var parts = [seat.id == context.me ? "You" : seat.name]
        if seat.away {
            parts.append("left the game")
        } else if seat.out {
            parts.append("knocked out")
        } else {
            parts.append(cardsText(seat.cards))
        }
        parts.append(seat.tricks == 1 ? "1 trick this hand" : "\(seat.tricks) tricks this hand")
        if isActing(seat.id) { parts.append(view.phase == .choosingTrump ? "choosing trumps" : "their turn") }
        return parts.joined(separator: ", ")
    }

    // MARK: - The table

    private var table: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                trumpBadge
                Spacer(minLength: 6)
                if myTurn {
                    OfflineCountdown(clock: context.clock, until: view.turnEndsAt,
                                     font: SR.Text.mono(13), tone: SR.inkMuted)
                }
            }
            trickRow
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-knockout-whist-table")
    }

    private var trumpBadge: some View {
        HStack(spacing: 10) {
            if let card = view.trumpCard {
                OfflineCardFace(card: card, width: 34)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("TRUMPS")
                    .font(SR.Text.label(12))
                    .tracking(1.4)
                    .foregroundStyle(SR.inkMuted)
                if let trump = view.trump {
                    HStack(spacing: 6) {
                        Text(trump.symbol)
                            .font(.system(size: 24))
                            .foregroundStyle(trump.isRed ? SR.error : SR.ink)
                        Text(trump.name)
                            .font(SR.Text.title())
                            .foregroundStyle(SR.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                } else {
                    Text("not yet named")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(view.trump.map { "Trumps are \($0.name)" } ?? "Trumps not yet named")
    }

    /// The trick: up to five cards, each over its player's name, sized from
    /// the width so five always fit.
    private var trickRow: some View {
        let maxCard: CGFloat = 56
        let labelHeight: CGFloat = 20
        return GeometryReader { geo in
            let spacing: CGFloat = 8
            let slots = CGFloat(max(1, min(5, view.seats.count)))
            let width = max(24, min(maxCard, (geo.size.width - spacing * (slots - 1)) / slots))
            if view.trick.isEmpty {
                Text(trickPrompt)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(view.trick.enumerated()), id: \.offset) { _, played in
                        VStack(spacing: 4) {
                            OfflineCardFace(card: played.card, width: width,
                                            selected: view.phase == .trickWon && played.playerId == view.trickWinner)
                            Text(played.playerId == context.me ? "You" : context.name(of: played.playerId))
                                .font(SR.Text.mono(12))
                                .foregroundStyle(SR.inkSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: width)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(who(played.playerId)) played the \(played.card.name)")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: maxCard * OfflineCardMetrics.aspect + labelHeight)
        .accessibilityIdentifier("offline-knockout-whist-trick")
    }

    private var trickPrompt: String {
        guard let turn = view.turnPlayer else { return "The table is empty." }
        return turn == context.me ? "Your lead — any card." : "\(context.name(of: turn)) leads."
    }

    // MARK: - Naming trumps

    private var choosingNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "hourglass")
                .foregroundStyle(SR.inkMuted)
                .accessibilityHidden(true)
            Text(view.chooser.map { "\(context.name(of: $0)) is choosing trumps" } ?? "Trumps are being chosen")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            OfflineCountdown(clock: context.clock, until: view.turnEndsAt,
                             font: SR.Text.mono(13), tone: SR.inkMuted)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-knockout-whist-choosing")
    }

    /// Four suits as a two-by-two grid, so the buttons stay wide on any phone.
    private var suitPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SRSectionLabel(text: "Name trumps")
                Spacer(minLength: 6)
                OfflineCountdown(clock: context.clock, until: view.turnEndsAt,
                                 font: SR.Text.mono(13), tone: SR.inkMuted)
            }
            ForEach([[OfflineSuit.clubs, .diamonds], [.hearts, .spades]], id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row) { suit in
                        Button {
                            SRHaptic.ok()
                            send(.chooseTrump(hand: view.hand, suit: suit))
                        } label: {
                            SRButtonLabel(title: "\(suit.symbol) \(suit.name)", fill: true)
                        }
                        .srButton(.regular)
                        .controlSize(.large)
                        .disabled(waiting)
                        .accessibilityLabel("Make \(suit.name) trumps")
                        .accessibilityIdentifier("offline-knockout-whist-suit-\(suit.rawValue)")
                    }
                }
            }
        }
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
                        playable: waiting ? Set<String>() : Set(view.playable),
                        onTap: { card in tapped(card) }
                    )
                } else {
                    // Between turns — and while naming trumps, when the cards
                    // are what the choice rests on — the hand is drawn at full
                    // strength rather than dimmed as unplayable.
                    OfflineHand(cards: view.myCards, cardWidth: 64)
                }
            }
            .accessibilityIdentifier("offline-knockout-whist-hand")
        }
    }

    // MARK: - A hand's result

    private var result: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "This hand", trailing: "tricks")
            VStack(spacing: 0) {
                ForEach(Array(view.seats.enumerated()), id: \.element.id) { index, seat in
                    if index > 0 { Divider().overlay(SR.divider) }
                    HStack(spacing: 10) {
                        Text(seat.id == context.me ? "You" : seat.name)
                            .font(SR.Text.title())
                            .foregroundStyle(seat.out ? SR.inkMuted : SR.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if seat.id == view.champion {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SR.accent)
                                .accessibilityHidden(true)
                        }
                        Spacer(minLength: 8)
                        Text(resultStatus(seat))
                            .font(SR.Text.mono(13))
                            .foregroundStyle(view.knockedOut.contains(seat.id) ? SR.error : SR.inkSecondary)
                            .lineLimit(1)
                            .fixedSize()
                        Text("\(seat.tricks)")
                            .font(SR.Text.display(20))
                            .foregroundStyle(SR.ink)
                            .frame(minWidth: 28, alignment: .trailing)
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
                    Text(view.champion == nil ? "Next hand in" : "Results in")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                    OfflineCountdown(clock: context.clock, until: view.pauseUntil,
                                     font: SR.Text.mono(), tone: SR.inkMuted)
                }
            }
        }
        .accessibilityIdentifier("offline-knockout-whist-result")
    }

    private func resultStatus(_ seat: KnockoutWhistRules.Seat) -> String {
        if seat.id == view.champion { return "winner" }
        if view.knockedOut.contains(seat.id) { return "knocked out" }
        if seat.away { return "left" }
        if seat.out { return "out" }
        if seat.id == view.nextChooser { return "names trumps" }
        return "through"
    }

    private func resultLabel(_ seat: KnockoutWhistRules.Seat) -> String {
        var parts = [seat.id == context.me ? "You" : seat.name]
        parts.append(seat.tricks == 1 ? "1 trick" : "\(seat.tricks) tricks")
        parts.append(resultStatus(seat))
        return parts.joined(separator: ", ")
    }

    // MARK: - Acting

    private func tapped(_ card: OfflineCard) {
        guard myTurn, !waiting, view.playable.contains(card.id) else { return }
        send(.play(turn: view.turnNumber, card: card))
    }

    private func send(_ action: KnockoutWhistRules.Action) {
        waiting = true
        context.send(action)
    }
}
