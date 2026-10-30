import SwiftUI

/// Crazy Eights on one phone: the table, my hand, and the hand's result.
///
/// The host decides everything; this view draws the latest `PlayerView` and
/// sends one action at a time. Tapping a card that fits plays it at once —
/// an eight first asks which suit to name. Cards that do not fit are dimmed,
/// so the only thing to learn is "match the suit or the number". Draw and
/// Pass sit under the hand and only appear when they are allowed.
///
/// Everyone sits along the seat rail with a fan of their cards and their
/// penalty total; the stock and the discard pile are on the felt, the newest
/// card dealt onto the pile with a slide, and the suit to follow is a big
/// badge that flashes when an eight names a new one. On my turn the strip
/// takes my colour and its ring counts the turn down. Naming a suit is four
/// big suit tiles, not a list.
struct CrazyEightsView: View {
    let context: OfflineGameContext<CrazyEightsRules>
    /// An eight waiting for its suit to be named.
    @State private var pendingEight: OfflineCard?
    /// An action has gone to the host and its answer has not come back yet,
    /// so a double tap sends once. Any new view clears it.
    @State private var waiting = false
    /// The page's content width, for sizing cards.
    @State private var width: CGFloat = 335

    private var view: CrazyEightsRules.PlayerView { context.view }

    private var handCardWidth: CGFloat { max(56, min(80, width / 4.6)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SRPageHeader(kicker: kicker, title: title, strap: strap)
                if view.phase == .playing, let turn = view.turnPlayer { turnStrip(turn) }
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
        .onChange(of: view.turnNumber) { _, _ in
            pendingEight = nil
        }
        .onChange(of: myTurn) { _, mine in
            if mine && view.phase == .playing { SRHaptic.select() }
        }
        .onChange(of: view.phase) { _, new in
            guard new == .handOver else { return }
            if view.handWinner == context.me { SRHaptic.ok() }
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

    private func tone(of id: String) -> Color {
        OfflineSeatColour.of(view.seats.firstIndex { $0.id == id } ?? 0)
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

    // MARK: - The turn

    private func turnStrip(_ turn: String) -> some View {
        let mine = turn == context.me
        return PlayTableTurnStrip(text: mine ? "Follow \(view.suit.symbol) \(view.suit.name) or the number" : "\(context.name(of: turn)) is choosing",
                                  mine: mine, clock: context.clock, until: view.turnEndsAt,
                                  total: CrazyEightsRules.turnSeconds, tone: tone(of: turn)) {
            OfflineInitial(name: context.name(of: turn), size: 40, tone: tone(of: turn))
        }
        .accessibilityIdentifier("offline-crazy-eights-turn")
    }

    // MARK: - The players

    private var seats: some View {
        PlayTableSeatRail(seats: Array(view.seats.enumerated()).map { pod($0.offset, $0.element) })
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("offline-crazy-eights-seats")
    }

    private func pod(_ index: Int, _ seat: CrazyEightsRules.Seat) -> PlayTableSeat {
        let crowned = view.phase != .playing && (seat.id == view.handWinner || view.champions.contains(seat.id))
        return PlayTableSeat(
            id: seat.id,
            label: seat.id == context.me ? "You" : seat.name,
            initialOf: seat.name,
            tone: OfflineSeatColour.of(index),
            detail: seat.away ? "left" : cardsText(seat.cards),
            cards: seat.away || view.phase != .playing ? 0 : seat.cards,
            turn: view.phase == .playing && view.turnPlayer == seat.id,
            away: seat.away,
            mark: crowned ? "crown.fill" : nil,
            markTone: Color(hex: 0xE0A21C),
            warn: seat.cards == 1 && !seat.away && view.phase == .playing,
            score: "\(seat.score) pts",
            spoken: seatLabel(seat)
        )
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
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 8) {
                PlayTableDeck(count: view.stockCount, cardWidth: 58)
                Text("\(view.stockCount) left")
                    .font(SR.Text.mono(12))
                    .foregroundStyle(PlayTablePaint.onFeltMuted)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stock, \(view.stockCount) cards")

            VStack(spacing: 8) {
                discard
                Text("pile")
                    .font(SR.Text.mono(12))
                    .foregroundStyle(PlayTablePaint.onFeltMuted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(view.top.map { "Top of the pile: \($0.name)" } ?? "The pile is empty")

            Spacer(minLength: 0)
            CrazyEightsSuitBadge(suit: view.suit, named: view.top.map { $0.suit != view.suit } ?? false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Follow \(view.suit.name)")
        }
        .padding(SR.cardPadding + 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .playTableFelt()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-crazy-eights-pile")
    }

    /// The discard pile: the top card over the edges of two beneath it.
    private var discard: some View {
        let cardWidth: CGFloat = 64
        let shape = RoundedRectangle(cornerRadius: cardWidth * 0.12, style: .continuous)
        return ZStack {
            if view.top != nil {
                shape.fill(PlayTablePaint.cardPaper)
                    .frame(width: cardWidth, height: cardWidth * OfflineCardMetrics.aspect)
                    .rotationEffect(.degrees(-9))
                    .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                shape.fill(PlayTablePaint.cardPaper)
                    .frame(width: cardWidth, height: cardWidth * OfflineCardMetrics.aspect)
                    .rotationEffect(.degrees(6))
                    .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
            }
            if let top = view.top {
                OfflineCardFace(card: top, width: cardWidth)
                    .id(top.id)
                    .transition(.playTableDeal)
            } else {
                shape
                    .strokeBorder(PlayTablePaint.onFeltMuted, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: cardWidth, height: cardWidth * OfflineCardMetrics.aspect)
            }
        }
        .frame(width: cardWidth * 1.3, height: cardWidth * OfflineCardMetrics.aspect * 1.1)
        .srAnimation(.spring(response: 0.38, dampingFraction: 0.75), value: view.top?.id)
    }

    // MARK: - My hand

    private var myHand: some View {
        VStack(alignment: .leading, spacing: 14) {
            SRSectionLabel(text: "Your hand",
                           trailing: myTurn && !view.playable.isEmpty ? "\(view.playable.count) can go" : cardsText(view.myCards.count))
            Group {
                if myTurn {
                    OfflineHand(
                        cards: view.myCards,
                        cardWidth: handCardWidth,
                        selected: pendingEight.map { Set([$0.id]) } ?? Set<String>(),
                        playable: waiting ? Set<String>() : Set(view.playable),
                        onTap: { card in tapped(card) }
                    )
                } else {
                    // Nothing to tap between turns, so the hand is drawn at
                    // full strength to read rather than dimmed as unplayable.
                    OfflineHand(cards: view.myCards, cardWidth: handCardWidth)
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
                PlayTableButton(title: "Draw", icon: "plus.rectangle.on.rectangle",
                                weight: view.playable.isEmpty ? .prominent : .regular) {
                    send(.draw(turn: view.turnNumber))
                }
                .disabled(waiting)
                .accessibilityIdentifier("offline-crazy-eights-draw")
                .accessibilityLabel("Draw a card")
            }
            if view.canPass {
                PlayTableButton(title: "Pass", icon: "arrow.uturn.forward",
                                weight: view.drawn == nil && view.playable.isEmpty ? .prominent : .regular) {
                    send(.pass(turn: view.turnNumber))
                }
                .disabled(waiting)
                .accessibilityIdentifier("offline-crazy-eights-pass")
                .accessibilityLabel("Pass your turn")
            }
        }
    }

    /// Four suits as big tiles in a row, each a thumb wide on any phone.
    private func suitPicker(for eight: OfflineCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Name a suit", trailing: eight.text)
            HStack(spacing: 10) {
                ForEach([OfflineSuit.clubs, .diamonds, .hearts, .spades]) { suit in
                    suitTile(suit, eight: eight)
                }
            }
            PlayTableButton(title: "Cancel", weight: .regular) {
                pendingEight = nil
            }
            .accessibilityIdentifier("offline-crazy-eights-suit-cancel")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    private func suitTile(_ suit: OfflineSuit, eight: OfflineCard) -> some View {
        Button {
            SRHaptic.ok()
            pendingEight = nil
            send(.play(turn: view.turnNumber, card: eight, suit: suit))
        } label: {
            VStack(spacing: 4) {
                Text(suit.symbol)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(suit.isRed ? PlayTablePaint.cardRed : PlayTablePaint.cardInk)
                Text(suit.name.capitalized)
                    .font(SR.Text.label(12))
                    .foregroundStyle(PlayTablePaint.cardInk.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PlayTablePaint.cardPaper)
                    .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel("Name \(suit.name)")
        .accessibilityIdentifier("offline-crazy-eights-suit-\(suit.rawValue)")
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
                    resultRow(seat, index: index)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)

            if view.phase == .handOver {
                HStack(spacing: 10) {
                    PlayTableClockRing(clock: context.clock, until: view.nextHandAt,
                                       total: CrazyEightsRules.resultPause, size: 34)
                    Text("Next hand in")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                    OfflineCountdown(clock: context.clock, until: view.nextHandAt,
                                     font: SR.Text.mono(), tone: SR.inkMuted)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityIdentifier("offline-crazy-eights-result")
    }

    private func resultRow(_ seat: CrazyEightsRules.Seat, index: Int) -> some View {
        let wentOut = seat.id == view.handWinner
        return HStack(spacing: 10) {
            OfflineInitial(name: seat.name, size: 34, tone: OfflineSeatColour.of(index))
            Text(seat.id == context.me ? "You" : seat.name)
                .font(SR.Text.title())
                .foregroundStyle(seat.away ? SR.inkMuted : SR.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            if wentOut {
                Image(systemName: "crown.fill")
                    .font(SR.Text.label(13))
                    .foregroundStyle(Color(hex: 0xE0A21C))
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
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .frame(minWidth: 38, alignment: .trailing)
                .fixedSize()
                .srNumeric(Double(seat.score))
        }
        .frame(minHeight: 52)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .fill(wentOut ? SR.good.opacity(0.12) : Color.clear)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resultLabel(seat))
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
            SRHaptic.select()
            pendingEight = card
        } else {
            SRHaptic.tap()
            send(.play(turn: view.turnNumber, card: card, suit: nil))
        }
    }

    private func send(_ action: CrazyEightsRules.Action) {
        waiting = true
        context.send(action)
    }
}

/// The suit to follow, as a big white disc with the suit in it. When an
/// eight has named a suit that is not the top card's, it says so and the
/// disc gives a short pulse.
struct CrazyEightsSuitBadge: View {
    let suit: OfflineSuit
    /// The suit was named by an eight.
    let named: Bool
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            Text("FOLLOW")
                .font(SR.Text.label(12))
                .tracking(1.4)
                .foregroundStyle(PlayTablePaint.onFeltMuted)
            Text(suit.symbol)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(suit.isRed ? PlayTablePaint.cardRed : PlayTablePaint.cardInk)
                .frame(width: 70, height: 70)
                .background(Circle().fill(PlayTablePaint.cardPaper))
                .overlay(Circle().strokeBorder(named ? PlayTablePaint.gold : Color.clear, lineWidth: 3))
                .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
                .scaleEffect(pulse ? 1.12 : 1)
            Text(named ? "NAMED" : suit.name.uppercased())
                .font(SR.Text.label(11))
                .tracking(0.8)
                .foregroundStyle(named ? PlayTablePaint.gold : PlayTablePaint.onFelt)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .onChange(of: suit) { _, _ in bump() }
    }

    private func bump() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { pulse = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pulse = false }
        }
    }
}
