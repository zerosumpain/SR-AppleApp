import SwiftUI

/// Knockout Whist on one phone: who is still in, the trick on the table,
/// trumps, and my hand.
///
/// The host decides everything; this view draws the latest `PlayerView` and
/// sends one action at a time. On my turn the cards I may play are bright and
/// the rest dimmed — so "follow suit if you can" is shown rather than
/// explained — and tapping one plays it. When I took the most tricks, the
/// next hand opens with four big suit tiles to name trumps, each saying how
/// many of that suit I hold. A player who is knocked out keeps watching with
/// an empty hand.
///
/// The overhaul (2026-10-29) put the trick on green baize with everyone sat
/// along the top, trumps as a medallion in the corner, the cards landing
/// as they are played, and "Your trick!" (or who took it) popping up.
struct KnockoutWhistView: View {
    let context: OfflineGameContext<KnockoutWhistRules>
    /// An action has gone to the host and its answer has not come back yet,
    /// so a double tap sends once. Any new view clears it.
    @State private var waiting = false
    @State private var callout = ""
    @State private var calloutTone: Color = SR.accentDeep
    @State private var calloutIcon: String?
    @State private var calloutToken = 0
    @State private var burstToken = 0

    private var view: KnockoutWhistRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                banner
                switch view.phase {
                case .choosingTrump:
                    table
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
        .overlay {
            ZStack {
                NearbyPlayBurst(token: burstToken)
                NearbyPlayCallout(text: callout, icon: calloutIcon, tone: calloutTone, token: calloutToken)
            }
        }
        .onChange(of: view) { _, _ in
            waiting = false
        }
        .onChange(of: view.turnPlayer) { _, new in
            if new == context.me && view.phase == .playing { SRHaptic.tap() }
        }
        .onChange(of: view.phase) { _, new in
            reactToPhase(new)
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

    private var myChoice: Bool { view.phase == .choosingTrump && view.chooser == context.me }

    private func who(_ id: String) -> String {
        id == context.me ? "You" : context.name(of: id)
    }

    private func seatTone(_ id: String?) -> Color {
        guard let id, let index = view.seats.firstIndex(where: { $0.id == id }) else { return SR.accent }
        return OfflineSeatColour.of(index)
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

    // MARK: - The top

    private var bannerMark: NearbyPlayMark {
        switch view.phase {
        case .choosingTrump:
            return view.chooser.map { NearbyPlayMark.person(context.name(of: $0)) } ?? .symbol("suit.spade.fill")
        case .playing:
            return view.turnPlayer.map { NearbyPlayMark.person(context.name(of: $0)) } ?? .symbol("suit.spade.fill")
        case .trickWon:
            return .symbol("hand.raised.fill")
        case .handOver:
            return .symbol("list.number")
        case .over:
            return .symbol("trophy.fill")
        }
    }

    private var bannerTone: Color {
        switch view.phase {
        case .choosingTrump: return seatTone(view.chooser)
        case .playing: return seatTone(view.turnPlayer)
        case .trickWon: return seatTone(view.trickWinner)
        case .handOver, .over: return SR.accent
        }
    }

    private var banner: some View {
        NearbyPlayBanner(kicker: kicker, title: title, strap: strap, mine: myTurn || myChoice,
                         tone: bannerTone, mark: bannerMark) {
            bannerClock
        }
    }

    @ViewBuilder
    private var bannerClock: some View {
        switch view.phase {
        case .playing:
            NearbyPlayBannerClock(clock: context.clock, until: view.turnEndsAt,
                                  total: KnockoutWhistRules.turnSeconds, mine: myTurn)
        case .choosingTrump:
            NearbyPlayBannerClock(clock: context.clock, until: view.turnEndsAt,
                                  total: KnockoutWhistRules.chooseSeconds, mine: myChoice)
        case .handOver:
            NearbyPlayBannerClock(clock: context.clock, until: view.pauseUntil,
                                  total: KnockoutWhistRules.resultPause, mine: false)
                .accessibilityLabel(view.champion == nil ? "Next hand soon" : "Results soon")
        case .trickWon, .over:
            EmptyView()
        }
    }

    // MARK: - The table

    private func cardsText(_ count: Int) -> String {
        count == 1 ? "1 card" : "\(count) cards"
    }

    private var stripSeats: [NearbyPlaySeat] {
        view.seats.enumerated().map { pair -> NearbyPlaySeat in
            let seat = pair.element
            let acting = isActing(seat.id)
            let status: String = seat.away ? "left" : (seat.out ? "out" : cardsText(seat.cards))
            return NearbyPlaySeat(
                id: seat.id, name: seat.name, tone: OfflineSeatColour.of(pair.offset),
                isMe: seat.id == context.me, acting: acting, faded: seat.out || seat.away,
                badge: seat.out || seat.away ? nil : "\(seat.tricks)",
                detail: status,
                mark: view.trickWinner == seat.id && view.phase == .trickWon ? "hand.raised.fill" : nil,
                spoken: seatLabel(seat)
            )
        }
    }

    /// The baize: everyone along the top, trumps in the corner, the trick in
    /// the middle.
    private var table: some View {
        NearbyPlayFelt(tone: .baize) {
            VStack(alignment: .leading, spacing: 14) {
                NearbyPlaySeatStrip(seats: stripSeats)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("offline-knockout-whist-seats")
                HStack(alignment: .center, spacing: 12) {
                    trumpMedallion
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TRUMPS")
                            .font(SR.Text.label())
                            .tracking(1.4)
                            .foregroundStyle(NearbyPlayFeltInk.secondary)
                        Text(view.trump.map { $0.name.capitalized } ?? "Not yet named")
                            .font(SR.Text.title())
                            .foregroundStyle(NearbyPlayFeltInk.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("Number on each face: tricks won")
                            .font(SR.Text.mono(12))
                            .foregroundStyle(NearbyPlayFeltInk.faint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                    if let card = view.trumpCard {
                        OfflineCardFace(card: card, width: 40)
                            .rotationEffect(.degrees(8))
                            .accessibilityLabel("Trump card: \(card.name)")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(view.trump.map { "Trumps are \($0.name)" } ?? "Trumps not yet named")
                if view.phase != .choosingTrump {
                    trickRow
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-knockout-whist-table")
    }

    /// A disc with the trump suit, red or black, glowing gold.
    private var trumpMedallion: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0xFFFDF8))
            Circle()
                .strokeBorder(NearbyPlayFeltInk.gold, lineWidth: 3)
            Text(view.trump?.symbol ?? "?")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(view.trump?.isRed == true ? Color(hex: 0xCF2236) : Color(hex: 0x1F1D2B))
        }
        .frame(width: 54, height: 54)
        .shadow(color: NearbyPlayFeltInk.gold.opacity(view.trump == nil ? 0 : 0.5), radius: 8, x: 0, y: 0)
        .accessibilityHidden(true)
    }

    /// The seat whose move the table is waiting for.
    private func isActing(_ id: String) -> Bool {
        (view.phase == .playing && view.turnPlayer == id) || (view.phase == .choosingTrump && view.chooser == id)
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

    /// The trick: up to five cards, each over its player's name, sized from
    /// the width so five always fit. Each card lands as it is played.
    private var trickRow: some View {
        let maxCard: CGFloat = 62
        let labelHeight: CGFloat = 22
        return GeometryReader { geo in
            let spacing: CGFloat = 8
            let slots = CGFloat(max(1, min(5, view.seats.count)))
            let width = max(24, min(maxCard, (geo.size.width - spacing * (slots - 1)) / slots))
            if view.trick.isEmpty {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
                        .strokeBorder(NearbyPlayFeltInk.faint, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: width, height: width * OfflineCardMetrics.aspect)
                    Text(trickPrompt)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(NearbyPlayFeltInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(view.trick.enumerated()), id: \.offset) { _, played in
                        trickCard(played, width: width)
                            .transition(.asymmetric(insertion: .scale(scale: 0.5).combined(with: .opacity),
                                                    removal: .opacity))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: maxCard * OfflineCardMetrics.aspect + labelHeight + 6)
        .srAnimation(.spring(response: 0.35, dampingFraction: 0.7), value: view.trick.count)
        .accessibilityIdentifier("offline-knockout-whist-trick")
    }

    private func trickCard(_ played: KnockoutWhistRules.Played, width: CGFloat) -> some View {
        let winner = view.phase == .trickWon && played.playerId == view.trickWinner
        return VStack(spacing: 4) {
            OfflineCardFace(card: played.card, width: width, selected: winner)
                .offset(y: winner ? -4 : 0)
            HStack(spacing: 2) {
                if winner {
                    Image(systemName: "crown.fill")
                        .font(SR.Text.label(12))
                        .foregroundStyle(NearbyPlayFeltInk.gold)
                        .accessibilityHidden(true)
                }
                Text(played.playerId == context.me ? "You" : context.name(of: played.playerId))
                    .font(SR.Text.mono(12))
                    .foregroundStyle(winner ? NearbyPlayFeltInk.gold : NearbyPlayFeltInk.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(who(played.playerId)) played the \(played.card.name)\(winner ? ", winning" : "")")
    }

    private var trickPrompt: String {
        guard let turn = view.turnPlayer else { return "The table is empty." }
        return turn == context.me ? "Your lead — any card." : "\(context.name(of: turn)) leads."
    }

    // MARK: - Naming trumps

    private var choosingNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(SR.Text.title(18))
                .foregroundStyle(SR.inkMuted)
                .accessibilityHidden(true)
            Text(view.chooser.map { "\(context.name(of: $0)) is choosing trumps" } ?? "Trumps are being chosen")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-knockout-whist-choosing")
    }

    /// Four suits as a two-by-two grid of big tiles, each with how many of
    /// that suit I hold — the thing the choice rests on.
    private var suitPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Name trumps")
            ForEach([[OfflineSuit.clubs, .diamonds], [.hearts, .spades]], id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row) { suit in
                        suitTile(suit)
                    }
                }
            }
        }
    }

    private func suitTile(_ suit: OfflineSuit) -> some View {
        let held = view.myCards.filter { $0.suit == suit }.count
        let shape = RoundedRectangle(cornerRadius: NearbyPlayMetrics.radius, style: .continuous)
        let ink = suit.isRed ? Color(hex: 0xCF2236) : Color(hex: 0x1F1D2B)
        return Button {
            SRHaptic.ok()
            send(.chooseTrump(hand: view.hand, suit: suit))
        } label: {
            HStack(spacing: 10) {
                Text(suit.symbol)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suit.name.capitalized)
                        .font(SR.Text.title(17))
                        .foregroundStyle(Color(hex: 0x1F1D2B))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(held == 1 ? "You hold 1" : "You hold \(held)")
                        .font(SR.Text.mono(12))
                        .foregroundStyle(Color(hex: 0x4A4760))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(shape.fill(Color(hex: 0xFFFDF8)))
            .overlay(shape.strokeBorder(held >= 3 ? NearbyPlayFeltInk.gold : Color.black.opacity(0.14), lineWidth: held >= 3 ? 3 : 1))
            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
            .contentShape(shape)
        }
        .buttonStyle(SRPressStyle())
        .disabled(waiting)
        .opacity(waiting ? 0.5 : 1)
        .accessibilityLabel("Make \(suit.name) trumps, you hold \(held)")
        .accessibilityIdentifier("offline-knockout-whist-suit-\(suit.rawValue)")
    }

    // MARK: - My hand

    private var myHand: some View {
        VStack(alignment: .leading, spacing: 14) {
            SRSectionLabel(text: myTurn ? "Your hand · tap a bright card" : "Your hand",
                           trailing: cardsText(view.myCards.count))
            Group {
                if myTurn {
                    OfflineHand(
                        cards: view.myCards,
                        cardWidth: 66,
                        playable: waiting ? Set<String>() : Set(view.playable),
                        onTap: { card in tapped(card) }
                    )
                } else {
                    // Between turns — and while naming trumps, when the cards
                    // are what the choice rests on — the hand is drawn at full
                    // strength rather than dimmed as unplayable.
                    OfflineHand(cards: view.myCards, cardWidth: 66)
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
                    resultRow(seat, index: index)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("offline-knockout-whist-result")
    }

    private func resultRow(_ seat: KnockoutWhistRules.Seat, index: Int) -> some View {
        let status = resultStatus(seat)
        let tone = statusTone(seat)
        return HStack(spacing: 10) {
            OfflineInitial(name: seat.name, size: 32, tone: seat.out ? SR.inkGhost : OfflineSeatColour.of(index))
            Text(seat.id == context.me ? "You" : seat.name)
                .font(SR.Text.title())
                .foregroundStyle(seat.out ? SR.inkMuted : SR.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            if seat.id == view.champion {
                Image(systemName: "crown.fill")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.warn)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            Text(status.uppercased())
                .font(SR.Text.label(12))
                .tracking(0.8)
                .foregroundStyle(tone)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(tone.opacity(0.12)))
                .fixedSize()
            Text("\(seat.tricks)")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .frame(minWidth: 28, alignment: .trailing)
                .fixedSize()
        }
        .frame(minHeight: 52)
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resultLabel(seat))
    }

    private func statusTone(_ seat: KnockoutWhistRules.Seat) -> Color {
        if seat.id == view.champion { return SR.good }
        if view.knockedOut.contains(seat.id) { return SR.error }
        if seat.id == view.nextChooser { return SR.accent }
        return SR.inkSecondary
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

    // MARK: - Moments

    private func reactToPhase(_ phase: KnockoutWhistRules.Phase) {
        switch phase {
        case .trickWon:
            guard let winner = view.trickWinner else { return }
            if winner == context.me {
                SRHaptic.ok()
                pop("Your trick!", icon: "hand.raised.fill", tone: SR.good)
            } else {
                pop("\(context.name(of: winner)) takes it", icon: "hand.raised.fill", tone: SR.accentDeep)
            }
        case .handOver, .over:
            if view.champion == context.me {
                SRHaptic.ok()
                burstToken += 1
                pop("You win!", icon: "crown.fill", tone: SR.good)
            } else if view.knockedOut.contains(context.me) {
                SRHaptic.bad()
                pop("Knocked out", icon: "xmark.circle.fill", tone: SR.error)
            } else if stillIn && phase == .handOver {
                pop("Through!", icon: "checkmark.circle.fill", tone: SR.good)
            }
        case .choosingTrump:
            if view.chooser == context.me { SRHaptic.tap() }
        case .playing:
            break
        }
    }

    private func pop(_ text: String, icon: String?, tone: Color) {
        callout = text
        calloutIcon = icon
        calloutTone = tone
        calloutToken += 1
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
