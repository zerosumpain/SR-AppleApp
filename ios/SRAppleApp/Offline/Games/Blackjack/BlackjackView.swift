import SwiftUI

/// Blackjack on one phone: the dealer, my stake or my hand, and the table.
///
/// The host deals, times and pays everything; this view draws the latest
/// `PlayerView` and sends one action at a time. In the betting window the
/// stake is picked with − and + (or a chip to add 10 or 25) and sent with Bet.
/// On my turn the buttons the rules allow appear under my hand — Hit and Stand
/// always, Double and Split only when the view says they are legal — and the
/// hand stands by itself when the timer runs out. The dealer's hole card
/// arrives as a face-down card and only turns over when the host's view
/// includes it.
///
/// It is played on a felt (`PlayTableFelt`): the dealer's cards along the
/// top, the house rules printed on the baize, my stake as a stack of chips and
/// my cards dealt in with a slide. Each total sits in a badge beside its hand,
/// and when a round settles every hand gets its stamp — "BLACKJACK +15",
/// "BUST −10" — with a success or failure tap for mine. Whose turn it is, and
/// how long they have, is the turn strip's ring.
struct BlackjackView: View {
    let context: OfflineGameContext<BlackjackRules>
    /// The stake being chosen, before Bet sends it.
    @State private var stake = 10
    /// An action has gone to the host and its answer has not come back yet,
    /// so a double tap sends once. Any new view clears it.
    @State private var waiting = false
    /// The page's content width, for sizing cards.
    @State private var width: CGFloat = 335

    private var view: BlackjackRules.PlayerView { context.view }

    /// My cards: four fit across the felt, bigger on a big phone.
    private var myCardWidth: CGFloat { max(56, min(84, (width - 2 * SR.cardPadding) / 4.4)) }
    private var dealerCardWidth: CGFloat { max(52, min(76, (width - 2 * SR.cardPadding) / 4.8)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SRPageHeader(kicker: kicker, title: title, strap: strap)
                if view.phase == .playing, let turn = view.turnPlayer { turnStrip(turn) }
                felt
                if view.phase == .playing, myTurn, mySeat.map({ !$0.hands.isEmpty }) == true {
                    turnButtons
                }
                if view.phase == .betting, view.myMaxBet > 0 {
                    betButton
                }
                table
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { width = geo.size.width }
                        .onChange(of: geo.size.width) { _, new in width = new }
                }
            )
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .onChange(of: view) { _, _ in
            waiting = false
        }
        .onChange(of: view.phase) { _, new in
            guard new == .settled, let net = mySeat?.net else { return }
            if net > 0 { SRHaptic.ok() } else if net < 0 { SRHaptic.bad() }
        }
        .onChange(of: myTurn) { _, mine in
            if mine { SRHaptic.select() }
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

    private var myTurn: Bool { view.phase == .playing && view.turnPlayer == context.me }

    private func who(_ id: String) -> String {
        id == context.me ? "You" : context.name(of: id)
    }

    private func seatIndex(_ id: String) -> Int {
        view.seats.firstIndex { $0.id == id } ?? 0
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

    /// The badge's short form: "BJ", "BUST", "S17", "20".
    private func badgeText(_ hand: BlackjackRules.Hand) -> String {
        if hand.isBlackjack { return "BJ" }
        if hand.busted { return "BUST" }
        return hand.soft && hand.total < 21 ? "soft \(hand.total)" : "\(hand.total)"
    }

    private func badgeTone(_ hand: BlackjackRules.Hand) -> Color {
        if hand.isBlackjack { return Color(hex: 0x8A5A00) }
        if hand.busted { return PlayTablePaint.cardRed }
        return PlayTablePaint.cardInk
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

    /// The same, light enough to read on the felt.
    private func outcomeToneOnFelt(_ hand: BlackjackRules.Hand) -> Color {
        guard let outcome = hand.outcome else { return PlayTablePaint.onFelt }
        switch outcome {
        case .blackjack: return PlayTablePaint.gold
        case .win: return PlayTablePaint.winOnFelt
        case .lose, .bust: return PlayTablePaint.loseOnFelt
        case .push: return PlayTablePaint.onFelt
        }
    }

    // MARK: - The turn

    private func turnStrip(_ turn: String) -> some View {
        let mine = turn == context.me
        let tone = OfflineSeatColour.of(seatIndex(turn))
        let handNote = (mySeat?.hands.count ?? 0) > 1 && mine ? " · hand \(view.turnHand + 1)" : ""
        return PlayTableTurnStrip(text: (mine ? "Your turn" : "\(context.name(of: turn)) is playing") + handNote,
                                  mine: mine, clock: context.clock, until: view.turnEndsAt,
                                  total: BlackjackRules.turnTime, tone: tone) {
            OfflineInitial(name: context.name(of: turn), size: 40, tone: tone)
        }
        .accessibilityIdentifier("offline-blackjack-turn")
    }

    // MARK: - The felt

    private var felt: some View {
        VStack(alignment: .leading, spacing: 14) {
            dealerArea
            Text("BLACKJACK PAYS 3 TO 2 · DEALER STANDS ON 17")
                .font(SR.Text.label(11))
                .tracking(1.2)
                .foregroundStyle(PlayTablePaint.gold.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            switch view.phase {
            case .betting:
                if view.myMaxBet > 0 { betPicker } else { myStakeNote }
            case .playing, .dealer, .settled, .over:
                if let seat = mySeat, !seat.hands.isEmpty { myHands(seat) }
            }
        }
        .padding(.horizontal, SR.cardPadding + 6)
        .padding(.vertical, SR.cardPadding + 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .playTableFelt()
    }

    // MARK: - The dealer

    private var dealerArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PlayTableFeltLabel(text: "Dealer", trailing: dealerTrailing)
                if !view.dealerCards.isEmpty {
                    PlayTableTotalBadge(text: view.dealerHidden > 0 ? "\(view.dealerTotal)+" : "\(view.dealerTotal)",
                                        tone: view.dealerTotal > 21 ? PlayTablePaint.cardRed : PlayTablePaint.cardInk)
                }
            }
            if view.dealerCards.isEmpty && view.dealerHidden == 0 {
                HStack(spacing: 14) {
                    PlayTableDeck(count: view.shoeLeft, cardWidth: 44)
                    Text(shoeLine)
                        .font(SR.Text.secondary())
                        .foregroundStyle(PlayTablePaint.onFelt)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                BlackjackCardRow(cards: view.dealerCards, hidden: view.dealerHidden, cardWidth: dealerCardWidth,
                                 arrive: .playTableFlip)
            }
            if view.phase == .betting {
                countdownLine("Betting closes in", until: view.bettingEndsAt, total: BlackjackRules.bettingTime)
            } else if view.phase == .settled {
                countdownLine("Next round in", until: view.nextRoundAt, total: BlackjackRules.resultPause)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dealerLabel)
        .accessibilityIdentifier("offline-blackjack-dealer")
    }

    private var dealerTrailing: String? {
        guard !view.dealerCards.isEmpty else { return "\(view.shoeLeft) in shoe" }
        return view.dealerHidden > 0 ? "showing" : nil
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

    private func countdownLine(_ words: String, until: Double, total: Double) -> some View {
        HStack(spacing: 10) {
            PlayTableClockRing(clock: context.clock, until: until, total: total, size: 34, onFelt: true)
            Text(words)
                .font(SR.Text.mono())
                .foregroundStyle(PlayTablePaint.onFelt)
                .lineLimit(1)
        }
    }

    // MARK: - Betting

    /// The stake shown: what I picked, kept inside the limits I can afford.
    private var clampedStake: Int {
        min(max(stake, view.minBet), view.myMaxBet)
    }

    private var myStakeNote: some View {
        HStack(spacing: 12) {
            if let bet = mySeat?.bet {
                PlayTableChips(amount: bet, chipSize: 30)
                Text("You bet \(bet)")
                    .font(SR.Text.title())
                    .foregroundStyle(PlayTablePaint.onFelt)
            } else {
                Text(mySeat?.broke == true ? "Out of chips" : "Waiting for the deal")
                    .font(SR.Text.title())
                    .foregroundStyle(PlayTablePaint.onFeltMuted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
    }

    private var betPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            PlayTableFeltLabel(text: "Your stake", trailing: "\(mySeat?.chips ?? 0) chips")
            HStack(spacing: 12) {
                stakeStep(icon: "minus", spoken: "Five fewer chips", id: "offline-blackjack-stake-down",
                          enabled: clampedStake > view.minBet) {
                    stake = max(view.minBet, clampedStake - 5)
                }
                VStack(spacing: 6) {
                    PlayTableChips(amount: clampedStake, chipSize: 30)
                        .frame(height: 52, alignment: .bottom)
                    Text("\(clampedStake)")
                        .font(SR.Text.figure(30))
                        .foregroundStyle(PlayTablePaint.onFelt)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .srNumeric(Double(clampedStake))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Stake \(clampedStake) chips")
                stakeStep(icon: "plus", spoken: "Five more chips", id: "offline-blackjack-stake-up",
                          enabled: clampedStake < view.myMaxBet) {
                    stake = min(view.myMaxBet, clampedStake + 5)
                }
            }
            HStack(spacing: 14) {
                Spacer(minLength: 0)
                ForEach([10, 25], id: \.self) { value in
                    chipButton(value)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-blackjack-stake")
    }

    private func stakeStep(icon: String, spoken: String, id: String, enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            Image(systemName: icon)
                .font(SR.Text.title(22))
                .foregroundStyle(PlayTablePaint.cardInk)
                .frame(width: PlayTableMetrics.bigButton, height: PlayTableMetrics.bigButton)
                .background(Circle().fill(Color.white.opacity(enabled ? 0.95 : 0.45)))
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 2)
        }
        .buttonStyle(SRPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier(id)
    }

    /// A chip to tap: adds its value to the stake, up to what I can bet.
    private func chipButton(_ value: Int) -> some View {
        let room = view.myMaxBet - clampedStake
        return Button {
            SRHaptic.select()
            stake = min(view.myMaxBet, clampedStake + value)
        } label: {
            PlayTableChip(value: value, size: PlayTableMetrics.bigButton)
                .opacity(room > 0 ? 1 : 0.45)
        }
        .buttonStyle(SRPressStyle())
        .disabled(room <= 0)
        .accessibilityLabel("Add \(value) chips")
        .accessibilityIdentifier("offline-blackjack-chip-\(value)")
    }

    private var betButton: some View {
        PlayTableButton(title: "Bet \(clampedStake)", icon: "circle.circle.fill", haptic: .ok) {
            let amount = clampedStake
            stake = amount
            send(.bet(round: view.round, amount: amount))
        }
        .disabled(waiting)
        .accessibilityLabel("Bet \(clampedStake) chips")
        .accessibilityIdentifier("offline-blackjack-bet")
    }

    // MARK: - My hands

    private func myHands(_ seat: BlackjackRules.Seat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(seat.hands.enumerated()), id: \.offset) { index, hand in
                myHand(hand, index: index, count: seat.hands.count)
            }
        }
    }

    private func myHand(_ hand: BlackjackRules.Hand, index: Int, count: Int) -> some View {
        let live = myTurn && index == view.turnHand
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(count > 1 ? "YOUR HAND \(index + 1)" : "YOUR HAND")
                    .font(SR.Text.label())
                    .tracking(1.3)
                    .foregroundStyle(live ? PlayTablePaint.gold : PlayTablePaint.onFeltMuted)
                PlayTableTotalBadge(text: badgeText(hand), tone: badgeTone(hand),
                                    fill: hand.isBlackjack ? PlayTablePaint.gold : Color.white)
                Spacer(minLength: 6)
                PlayTableChips(amount: hand.bet, chipSize: 22)
                Text("\(hand.bet)\(hand.doubled ? " ×2" : "")")
                    .font(SR.Text.mono(13))
                    .foregroundStyle(PlayTablePaint.onFelt)
                    .fixedSize()
            }
            ZStack(alignment: .topTrailing) {
                BlackjackCardRow(cards: hand.cards, cardWidth: myCardWidth)
                if let outcome = outcomeText(hand) {
                    PlayTableStamp(text: outcome, tone: outcomeToneOnFelt(hand), size: 20)
                        .padding(.top, myCardWidth * 0.3)
                        .padding(.trailing, 4)
                        .accessibilityHidden(true)
                }
            }
            .opacity(myTurn && !live ? 0.55 : 1)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(live ? PlayTablePaint.gold : Color.clear, lineWidth: 2)
        )
        .srAnimation(.snappy(duration: 0.25), value: live)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(handLabel(hand, owner: "Your", index: index, count: count))
        .accessibilityIdentifier("offline-blackjack-my-hand-\(index)")
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
        PlayTableButton(title: title, icon: icon, weight: weight) {
            send(make(view.move))
        }
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
        let turn = view.turnPlayer == seat.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                OfflineInitial(name: seat.name, size: 34, tone: OfflineSeatColour.of(index))
                    .overlay(Circle().strokeBorder(turn ? OfflineSeatColour.of(index) : Color.clear, lineWidth: 2.5).padding(-4))
                Text(seat.id == context.me ? "You" : seat.name)
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(seat.away || seat.broke ? SR.inkMuted : SR.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if turn {
                    Text("PLAYING")
                        .font(SR.Text.label(10))
                        .tracking(0.8)
                        .foregroundStyle(OfflineSeatColour.of(index))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(OfflineSeatColour.of(index).opacity(0.14)))
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 6)
                Text(seatStatus(seat))
                    .font(SR.Text.mono(13))
                    .foregroundStyle(seatStatusTone(seat))
                    .lineLimit(1)
                    .fixedSize()
                Text("\(seat.chips)")
                    .font(SR.Text.figure(17))
                    .foregroundStyle(SR.ink)
                    .frame(minWidth: 38, alignment: .trailing)
                    .fixedSize()
                    .srNumeric(Double(seat.chips))
            }
            if seat.id != context.me || view.phase != .playing {
                ForEach(Array(seat.hands.enumerated()), id: \.offset) { _, hand in
                    HStack(alignment: .center, spacing: 10) {
                        BlackjackCardRow(cards: hand.cards, cardWidth: 32)
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
        .frame(minHeight: 48)
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
/// width it is given: the cards overlap more as the row grows. A card added
/// to the row arrives with `arrive` — dealt in from the shoe, or turned over.
struct BlackjackCardRow: View {
    let cards: [OfflineCard]
    var hidden: Int = 0
    /// The widest a card may be.
    var cardWidth: CGFloat = 56
    var arrive: AnyTransition = .playTableDeal

    var body: some View {
        GeometryReader { geo in
            let count = cards.count + hidden
            let width = min(cardWidth, geo.size.width)
            let step: CGFloat = count > 1 ? max(0, min(width + 6, (geo.size.width - width) / CGFloat(count - 1))) : 0
            ZStack(alignment: .topLeading) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    OfflineCardFace(card: card, width: width)
                        .offset(x: CGFloat(index) * step)
                        .transition(arrive)
                }
                ForEach(0..<max(0, hidden), id: \.self) { index in
                    OfflineCardBack(width: width)
                        .offset(x: CGFloat(cards.count + index) * step)
                        .transition(.opacity)
                }
            }
        }
        .frame(height: cardWidth * OfflineCardMetrics.aspect)
        .srAnimation(.spring(response: 0.4, dampingFraction: 0.78), value: cards.count * 10 + hidden)
        .accessibilityHidden(true)
    }
}
