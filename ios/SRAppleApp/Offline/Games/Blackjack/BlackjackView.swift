import SwiftUI

/// Blackjack on one phone: the dealer, my stake or my hand, and the table.
///
/// The host deals, times and pays everything; this view draws the latest
/// `PlayerView` and sends one action at a time. In the betting window the
/// stake is picked with − and + and sent with Bet. On my turn the buttons the
/// rules allow appear under my hand — Hit and Stand always, Double and Split
/// only when the view says they are legal — and the hand stands by itself when
/// the timer runs out. The dealer's hole card arrives as a face-down card and
/// only turns over when the host's view includes it.
struct BlackjackView: View {
    let context: OfflineGameContext<BlackjackRules>
    /// The stake being chosen, before Bet sends it.
    @State private var stake = 10
    /// An action has gone to the host and its answer has not come back yet,
    /// so a double tap sends once. Any new view clears it.
    @State private var waiting = false

    private var view: BlackjackRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: kicker, title: title, strap: strap)
                dealerCard
                switch view.phase {
                case .betting:
                    if view.myMaxBet > 0 { betPicker }
                case .playing:
                    if let seat = mySeat, !seat.hands.isEmpty { myHands(seat) }
                case .dealer, .settled, .over:
                    EmptyView()
                }
                table
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
            // A lost answer must not leave the buttons locked until the turn
            // timer moves the table on: give up waiting after a while.
            guard waiting else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { waiting = false }
        }
    }

    // MARK: - Words

    private var mySeat: BlackjackRules.Seat? {
        view.seats.first { $0.id == context.me }
    }

    private var myTurn: Bool { view.turnPlayer == context.me }

    private func who(_ id: String) -> String {
        id == context.me ? "You" : context.name(of: id)
    }

    private var kicker: String {
        "Round \(view.round) of \(view.maxRounds) · bets \(view.minBet)–\(view.maxBet)"
    }

    private var title: String {
        switch view.phase {
        case .betting:
            return "Place your bets"
        case .playing:
            guard let turn = view.turnPlayer else { return "Blackjack" }
            return turn == context.me ? "Your turn" : "\(context.name(of: turn))'s turn"
        case .dealer:
            return "Dealer's turn"
        case .settled:
            guard let net = mySeat?.net else {
                return view.seats.contains { !$0.hands.isEmpty } ? "Round over" : "Nobody bet"
            }
            if net > 0 { return "You won \(net)" }
            if net < 0 { return "You lost \(-net)" }
            return "You broke even"
        case .over:
            let names = view.champions.map { who($0) }
            if names.count == 1 { return names[0] == "You" ? "You win" : "\(names[0]) wins" }
            return names.isEmpty ? "Game over" : "A tie"
        }
    }

    /// What to do now, in one sentence.
    private var strap: String? {
        guard let seat = mySeat else { return "You are watching this game." }
        if seat.away { return "You have left this table." }
        switch view.phase {
        case .betting:
            if view.myMaxBet > 0 {
                return "Choose a stake of \(view.minBet)–\(view.myMaxBet) chips, then tap Bet."
            }
            if let bet = seat.bet { return "You bet \(bet). Waiting for the others." }
            return seat.broke ? "You're out of chips — watch the table." : "Waiting for the deal."
        case .playing:
            guard myTurn, let hand = currentHand else {
                return seat.hands.isEmpty ? "You sat this round out." : "Wait for your turn."
            }
            let list: String
            switch (view.canDouble, view.canSplit) {
            case (true, true): list = "Hit, stand, double or split"
            case (true, false): list = "Hit, stand or double"
            case (false, true): list = "Hit, stand or split"
            case (false, false): list = "Hit or stand"
            }
            return "You have \(totalText(hand)). \(list)."
        case .dealer:
            return "The dealer draws to 16 and stands on every 17."
        case .settled:
            return "Next round starts shortly."
        case .over:
            return "The most chips wins."
        }
    }

    private var currentHand: BlackjackRules.Hand? {
        guard let seat = mySeat, view.turnHand < seat.hands.count else { return nil }
        return seat.hands[view.turnHand]
    }

    private func totalText(_ hand: BlackjackRules.Hand) -> String {
        if hand.isBlackjack { return "blackjack" }
        if hand.busted { return "\(hand.total), bust" }
        return hand.soft && hand.total < 21 ? "soft \(hand.total)" : "\(hand.total)"
    }

    private func outcomeText(_ hand: BlackjackRules.Hand) -> String? {
        guard let outcome = hand.outcome else { return nil }
        let net = (hand.returned ?? 0) - hand.bet
        switch outcome {
        case .blackjack: return "Blackjack +\(net)"
        case .win: return "Win +\(net)"
        case .push: return "Push"
        case .lose: return "Lose −\(hand.bet)"
        case .bust: return "Bust −\(hand.bet)"
        }
    }

    private func outcomeTone(_ hand: BlackjackRules.Hand) -> Color {
        guard let outcome = hand.outcome else { return SR.inkSecondary }
        switch outcome {
        case .blackjack, .win: return SR.good
        case .lose, .bust: return SR.error
        case .push: return SR.inkSecondary
        }
    }

    // MARK: - The dealer

    private var dealerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Dealer", trailing: dealerTrailing)
            if view.dealerCards.isEmpty && view.dealerHidden == 0 {
                Text(shoeLine)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                BlackjackCardRow(cards: view.dealerCards, hidden: view.dealerHidden, cardWidth: 60)
            }
            if view.phase == .betting {
                countdownLine("Betting closes in", until: view.bettingEndsAt)
            } else if view.phase == .settled {
                countdownLine("Next round in", until: view.nextRoundAt)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dealerLabel)
        .accessibilityIdentifier("offline-blackjack-dealer")
    }

    private var dealerTrailing: String? {
        guard !view.dealerCards.isEmpty else { return "\(view.shoeLeft) in shoe" }
        return view.dealerHidden > 0 ? "showing \(view.dealerTotal)" : "\(view.dealerTotal)"
    }

    private var shoeLine: String {
        let base = "\(view.shoeLeft) cards left in the shoe."
        return view.reshuffled ? "Fresh shoe — the cards were reshuffled. " + base : base
    }

    private var dealerLabel: String {
        if view.dealerCards.isEmpty { return "Dealer. " + shoeLine }
        let cards = view.dealerCards.map(\.name).joined(separator: ", ")
        if view.dealerHidden > 0 { return "Dealer shows \(cards), and one card face down. \(view.dealerTotal) showing." }
        return "Dealer has \(cards): \(view.dealerTotal)."
    }

    private func countdownLine(_ words: String, until: Double) -> some View {
        HStack(spacing: 8) {
            Text(words)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            OfflineCountdown(clock: context.clock, until: until, font: SR.Text.mono(), tone: SR.inkMuted)
        }
    }

    // MARK: - Betting

    /// The stake shown: what I picked, kept inside the limits I can afford.
    private var clampedStake: Int {
        min(max(stake, view.minBet), view.myMaxBet)
    }

    private var betPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            SRSectionLabel(text: "Your stake", trailing: "\(mySeat?.chips ?? 0) chips")
            HStack(spacing: 12) {
                Button {
                    SRHaptic.select()
                    stake = max(view.minBet, clampedStake - 5)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: SR.tapTarget, height: SR.tapTarget)
                }
                .srButton(.regular)
                .disabled(clampedStake <= view.minBet)
                .accessibilityLabel("Five fewer chips")
                .accessibilityIdentifier("offline-blackjack-stake-down")

                Text("\(clampedStake)")
                    .font(SR.Text.figure())
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Stake \(clampedStake) chips")

                Button {
                    SRHaptic.select()
                    stake = min(view.myMaxBet, clampedStake + 5)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: SR.tapTarget, height: SR.tapTarget)
                }
                .srButton(.regular)
                .disabled(clampedStake >= view.myMaxBet)
                .accessibilityLabel("Five more chips")
                .accessibilityIdentifier("offline-blackjack-stake-up")
            }
            Button {
                SRHaptic.ok()
                let amount = clampedStake
                stake = amount
                send(.bet(round: view.round, amount: amount))
            } label: {
                SRButtonLabel(title: "Bet \(clampedStake)", icon: "circle.circle.fill", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(waiting)
            .accessibilityLabel("Bet \(clampedStake) chips")
            .accessibilityIdentifier("offline-blackjack-bet")
        }
        .accessibilityIdentifier("offline-blackjack-stake")
    }

    // MARK: - My hands

    private func myHands(_ seat: BlackjackRules.Seat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(seat.hands.enumerated()), id: \.offset) { index, hand in
                VStack(alignment: .leading, spacing: 10) {
                    SRSectionLabel(
                        text: seat.hands.count > 1 ? "Your hand \(index + 1)" : "Your hand",
                        trailing: "\(totalText(hand)) · bet \(hand.bet)"
                    )
                    BlackjackCardRow(cards: hand.cards, cardWidth: 64)
                        .opacity(myTurn && index != view.turnHand ? 0.55 : 1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(handLabel(hand, owner: "Your", index: index, count: seat.hands.count))
                .accessibilityIdentifier("offline-blackjack-my-hand-\(index)")
            }
            if myTurn {
                HStack(spacing: 8) {
                    Text("Time left")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                    OfflineCountdown(clock: context.clock, until: view.turnEndsAt,
                                     font: SR.Text.mono(), tone: SR.inkMuted)
                }
                turnButtons
            }
        }
    }

    private var turnButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                actionButton("Hit", icon: "plus", weight: .prominent, enabled: view.canHit,
                             id: "hit", spoken: "Hit: take a card") { .hit(move: $0) }
                actionButton("Stand", icon: "hand.raised", weight: .regular, enabled: view.canStand,
                             id: "stand", spoken: "Stand: keep this hand") { .stand(move: $0) }
            }
            if view.canDouble || view.canSplit {
                HStack(spacing: 10) {
                    if view.canDouble {
                        actionButton("Double", icon: "multiply", weight: .regular, enabled: true,
                                     id: "double", spoken: "Double: twice the bet, one more card") { .double(move: $0) }
                    }
                    if view.canSplit {
                        actionButton("Split", icon: "arrow.left.and.right", weight: .regular, enabled: true,
                                     id: "split", spoken: "Split the pair into two hands") { .split(move: $0) }
                    }
                }
            }
        }
    }

    private func actionButton(_ title: String, icon: String, weight: SRButtonWeight, enabled: Bool,
                              id: String, spoken: String,
                              make: @escaping (Int) -> BlackjackRules.Action) -> some View {
        Button {
            SRHaptic.tap()
            send(make(view.move))
        } label: {
            SRButtonLabel(title: title, icon: icon, fill: true)
        }
        .srButton(weight)
        .controlSize(.large)
        .disabled(!enabled || waiting)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("offline-blackjack-\(id)")
    }

    private func handLabel(_ hand: BlackjackRules.Hand, owner: String, index: Int, count: Int) -> String {
        var parts = [count > 1 ? "\(owner) hand \(index + 1)" : "\(owner) hand"]
        parts.append(hand.cards.map(\.name).joined(separator: ", "))
        parts.append(totalText(hand))
        parts.append("bet \(hand.bet)")
        if hand.doubled { parts.append("doubled") }
        if let outcome = outcomeText(hand) { parts.append(outcome) }
        return parts.joined(separator: ". ")
    }

    // MARK: - The table

    /// Every seat as a row: name, chips and stake, then each hand's cards
    /// small underneath. One column of rows, so five names fit any phone.
    private var table: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Table", trailing: "chips")
            VStack(spacing: 0) {
                ForEach(Array(view.seats.enumerated()), id: \.element.id) { index, seat in
                    if index > 0 { Divider().overlay(SR.divider) }
                    seatRow(seat, index: index)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("offline-blackjack-table")
    }

    private func seatRow(_ seat: BlackjackRules.Seat, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                OfflineInitial(name: seat.name, size: 28, tone: OfflineSeatColour.of(index))
                Text(seat.id == context.me ? "You" : seat.name)
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(seat.away || seat.broke ? SR.inkMuted : SR.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if view.turnPlayer == seat.id {
                    Image(systemName: "arrowtriangle.left.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SR.accent)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 6)
                Text(seatStatus(seat))
                    .font(SR.Text.mono(13))
                    .foregroundStyle(seatStatusTone(seat))
                    .lineLimit(1)
                    .fixedSize()
                Text("\(seat.chips)")
                    .font(SR.Text.mono(15))
                    .foregroundStyle(SR.ink)
                    .frame(minWidth: 34, alignment: .trailing)
                    .fixedSize()
            }
            if seat.id != context.me || view.phase != .playing {
                ForEach(Array(seat.hands.enumerated()), id: \.offset) { _, hand in
                    HStack(alignment: .center, spacing: 10) {
                        BlackjackCardRow(cards: hand.cards, cardWidth: 30)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(totalText(hand))
                                .font(SR.Text.mono(13))
                                .foregroundStyle(SR.ink)
                                .lineLimit(1)
                            if let outcome = outcomeText(hand) {
                                Text(outcome)
                                    .font(SR.Text.mono(12))
                                    .foregroundStyle(outcomeTone(hand))
                                    .lineLimit(1)
                            }
                        }
                        .fixedSize()
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seatLabel(seat))
    }

    /// The short note beside a seat's chips.
    private func seatStatus(_ seat: BlackjackRules.Seat) -> String {
        if seat.away { return "left" }
        if let net = seat.net { return net > 0 ? "+\(net)" : net < 0 ? "−\(-net)" : "±0" }
        if seat.broke { return "broke" }
        if view.phase == .betting { return seat.bet.map { "bet \($0)" } ?? "…" }
        let staked = seat.hands.reduce(0) { $0 + $1.bet }
        return staked > 0 ? "bet \(staked)" : "out"
    }

    private func seatStatusTone(_ seat: BlackjackRules.Seat) -> Color {
        guard let net = seat.net, !seat.away else { return SR.inkSecondary }
        return net > 0 ? SR.good : net < 0 ? SR.error : SR.inkSecondary
    }

    private func seatLabel(_ seat: BlackjackRules.Seat) -> String {
        let owner = seat.id == context.me ? "Your" : "\(seat.name)'s"
        var parts = [seat.id == context.me ? "You" : seat.name, "\(seat.chips) chips"]
        if seat.away { parts.append("left the game") } else if seat.broke { parts.append("out of chips") }
        if view.phase == .betting, let bet = seat.bet { parts.append("bet \(bet)") }
        if let net = seat.net { parts.append(net >= 0 ? "won \(net) this round" : "lost \(-net) this round") }
        if view.turnPlayer == seat.id { parts.append("their turn") }
        for (index, hand) in seat.hands.enumerated() {
            parts.append(handLabel(hand, owner: owner, index: index, count: seat.hands.count))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Acting

    private func send(_ action: BlackjackRules.Action) {
        guard !waiting else { return }
        waiting = true
        context.send(action)
    }
}

/// A row of cards, face up then `hidden` face down, that always fits the
/// width it is given: the cards overlap more as the row grows.
struct BlackjackCardRow: View {
    let cards: [OfflineCard]
    var hidden: Int = 0
    /// The widest a card may be.
    var cardWidth: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let count = cards.count + hidden
            let width = min(cardWidth, geo.size.width)
            let step: CGFloat = count > 1 ? max(0, min(width + 6, (geo.size.width - width) / CGFloat(count - 1))) : 0
            ZStack(alignment: .topLeading) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    OfflineCardFace(card: card, width: width)
                        .offset(x: CGFloat(index) * step)
                }
                ForEach(0..<max(0, hidden), id: \.self) { index in
                    OfflineCardBack(width: width)
                        .offset(x: CGFloat(cards.count + index) * step)
                }
            }
        }
        .frame(height: cardWidth * OfflineCardMetrics.aspect)
        .accessibilityHidden(true)
    }
}
