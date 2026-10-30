import SwiftUI

/// Cheat on one phone: the table, the claim to make, my hand, and the
/// "Cheat!" button while somebody else's play can still be called.
///
/// The host decides everything; this view draws the latest `PlayerView` and
/// sends one action at a time. On my turn I tap up to four cards to raise
/// them, then lay them as the rank shown — honest or not. When anybody else
/// lays cards, two buttons appear for a few seconds: call Cheat!, or believe
/// them. A call turns the cards over for everyone and says who took the pile.
///
/// Everyone sits along the seat rail with a fan of their cards; the pile is a
/// dropped heap on the felt beside a placard of the rank to claim. The call
/// window is a draining ring and a big red CHEAT! button; a call turns the
/// laid cards over one by one and stamps the verdict — TRUE or LIAR!
struct CheatView: View {
    let context: OfflineGameContext<CheatRules>
    /// Card ids raised to be laid, at most four.
    @State private var selected: Set<String> = []
    /// An action has gone to the host and its answer has not come back yet,
    /// so a double tap sends once. Any new view clears it.
    @State private var waiting = false
    /// "I'm back" has been sent for this absence, so it goes once.
    @State private var sentBack = false
    /// The page's content width, for sizing cards.
    @State private var width: CGFloat = 335

    private var view: CheatRules.PlayerView { context.view }

    private var handCardWidth: CGFloat { max(56, min(80, width / 4.6)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SRPageHeader(kicker: kicker, title: title, strap: strap)
                if view.phase == .play { turnStrip }
                seats
                table
                if view.phase == .challenge, view.canCall {
                    challengeButtons
                }
                if let reveal = view.reveal, view.phase == .reveal || view.phase == .won {
                    revealCard(reveal)
                }
                if playing, view.phase != .over {
                    myHand
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
        .onAppear { comeBackIfAway() }
        .onChange(of: view) { _, _ in
            waiting = false
            comeBackIfAway()
        }
        .onChange(of: view.turn) { _, _ in
            selected = []
        }
        .onChange(of: myTurn) { _, mine in
            if mine { SRHaptic.select() }
        }
        .onChange(of: view.reveal) { _, new in
            guard let new else { return }
            if new.pickedUpBy == context.me {
                SRHaptic.bad()
            } else {
                SRHaptic.ok()
            }
        }
        .onChange(of: context.refusal) { _, new in
            if new != nil {
                SRHaptic.bad()
                waiting = false
            }
        }
        .task(id: waiting) {
            // A lost answer must not leave the buttons locked: give up
            // waiting after a while.
            guard waiting else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { waiting = false }
        }
    }

    // MARK: - Words

    private var mySeat: CheatRules.Seat? {
        view.seats.first { $0.id == context.me }
    }

    /// Whether I hold a seat in this match.
    private var playing: Bool { mySeat != nil }

    private var myTurn: Bool {
        view.phase == .play && view.turnPlayer == context.me && mySeat?.away == false
    }

    private func who(_ id: String) -> String {
        id == context.me ? "You" : context.name(of: id)
    }

    private func tone(of id: String) -> Color {
        OfflineSeatColour.of(view.seats.firstIndex { $0.id == id } ?? 0)
    }

    private var rankWord: String { CheatRules.rankName(view.rank) }

    private func cardsText(_ count: Int) -> String {
        count == 1 ? "1 card" : "\(count) cards"
    }

    /// "two sevens", "one ace".
    private func claimText(_ play: CheatRules.Play) -> String {
        let numbers = ["one", "two", "three", "four"]
        let number = play.count >= 1 && play.count <= 4 ? numbers[play.count - 1] : "\(play.count)"
        return "\(number) \(CheatRules.rankName(play.rank, plural: play.count != 1))"
    }

    private var kicker: String {
        "Play \(view.turn) · pile of \(view.pileCount)"
    }

    private var title: String {
        switch view.phase {
        case .play:
            return myTurn ? "Your turn" : "\(context.name(of: view.turnPlayer))'s turn"
        case .challenge:
            guard let last = view.lastPlay else { return "Cheat?" }
            return last.playerId == context.me ? "Will they call?" : "Cheat?"
        case .reveal:
            guard let reveal = view.reveal else { return "Turned over" }
            return reveal.truthful ? "It was true" : "Caught lying"
        case .won, .over:
            guard let winner = view.winner else { return "Game over" }
            return winner == context.me ? "You went out" : "\(context.name(of: winner)) went out"
        }
    }

    /// What to do now, in one sentence.
    private var strap: String? {
        if !playing { return "You are watching this game." }
        switch view.phase {
        case .play:
            if myTurn {
                return "Pick one to four cards and lay them as \(rankWord). You may lie."
            }
            return "\(context.name(of: view.turnPlayer)) must lay \(rankWord)."
        case .challenge:
            guard let last = view.lastPlay else { return nil }
            if last.playerId == context.me {
                return "You laid \(claimText(last)). Anyone may call Cheat!"
            }
            if view.canCall {
                return "\(context.name(of: last.playerId)) says \(claimText(last)). Believe them?"
            }
            return "You let it go. Waiting for the others."
        case .reveal:
            guard let reveal = view.reveal else { return nil }
            return "\(who(reveal.pickedUpBy)) \(reveal.pickedUpBy == context.me ? "pick" : "picks") up \(cardsText(reveal.pileSize))."
        case .won, .over:
            return "Fewest cards left ranks next."
        }
    }

    private var lastPlayText: String? {
        guard let last = view.lastPlay else { return nil }
        let name = who(last.playerId)
        if last.timedOut { return "\(name) ran out of time — the host laid \(claimText(last))." }
        return "\(name) laid \(claimText(last))."
    }

    // MARK: - The turn

    private var turnStrip: some View {
        let turn = view.turnPlayer
        return PlayTableTurnStrip(text: myTurn ? "Lay \(rankWord)" : "\(context.name(of: turn)) is laying \(rankWord)",
                                  mine: myTurn, clock: context.clock, until: view.turnEndsAt,
                                  total: CheatRules.turnSeconds, tone: tone(of: turn)) {
            OfflineInitial(name: context.name(of: turn), size: 40, tone: tone(of: turn))
        }
        .accessibilityIdentifier("offline-cheat-turn")
    }

    // MARK: - The players

    private var seats: some View {
        PlayTableSeatRail(seats: Array(view.seats.enumerated()).map { pod($0.offset, $0.element) })
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("offline-cheat-seats")
    }

    private func pod(_ index: Int, _ seat: CheatRules.Seat) -> PlayTableSeat {
        let won = view.winner == seat.id
        let passed = view.phase == .challenge && seat.passed
        let mark: String? = won ? "crown.fill" : (passed ? "hand.thumbsup.fill" : nil)
        let markTone: Color = won ? Color(hex: 0xE0A21C) : SR.good
        return PlayTableSeat(
            id: seat.id,
            label: seat.id == context.me ? "You" : seat.name,
            initialOf: seat.name,
            tone: OfflineSeatColour.of(index),
            detail: seat.away ? "left" : cardsText(seat.cards),
            cards: seat.away ? 0 : seat.cards,
            turn: view.phase == .play && view.turnPlayer == seat.id,
            away: seat.away,
            mark: mark,
            markTone: markTone,
            warn: seat.cards <= 2 && !seat.away,
            spoken: seatLabel(seat)
        )
    }

    private func seatLabel(_ seat: CheatRules.Seat) -> String {
        var parts = [seat.id == context.me ? "You" : seat.name]
        parts.append(seat.away ? "left the game" : cardsText(seat.cards))
        if view.phase == .play, view.turnPlayer == seat.id { parts.append("their turn") }
        if view.phase == .challenge, seat.passed { parts.append("let it go") }
        return parts.joined(separator: ", ")
    }

    // MARK: - The table

    private var table: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                VStack(spacing: 8) {
                    PlayTablePile(count: view.pileCount, cardWidth: 58)
                    Text("\(view.pileCount) down")
                        .font(SR.Text.mono(12))
                        .foregroundStyle(PlayTablePaint.onFeltMuted)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("The pile, \(cardsText(view.pileCount)) face down")

                claimPlacard
                Spacer(minLength: 0)
            }
            if let line = lastPlayText {
                Text(line)
                    .font(SR.Text.secondary())
                    .foregroundStyle(PlayTablePaint.onFelt)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("offline-cheat-last-play")
            }
        }
        .padding(SR.cardPadding + 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .playTableFelt()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-cheat-table")
    }

    /// The rank to lay (or that was claimed), as a big card-like placard,
    /// with the call window's ring beside it.
    private var claimPlacard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(view.phase == .play ? "LAY" : "CLAIMED")
                .font(SR.Text.label(12))
                .tracking(1.4)
                .foregroundStyle(PlayTablePaint.onFeltMuted)
            HStack(alignment: .center, spacing: 12) {
                Text(CheatRules.rankText(claimRank))
                    .font(SR.Text.hero(40))
                    .foregroundStyle(PlayTablePaint.cardInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 64, height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(PlayTablePaint.cardPaper)
                            .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
                    )
                    .contentTransition(.numericText())
                    .srAnimation(.snappy(duration: 0.3), value: claimRank)
                VStack(alignment: .leading, spacing: 6) {
                    Text(CheatRules.rankName(claimRank).capitalized)
                        .font(SR.Text.title())
                        .foregroundStyle(PlayTablePaint.onFelt)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if view.phase == .challenge {
                        PlayTableClockRing(clock: context.clock, until: view.challengeEndsAt,
                                           total: CheatRules.challengeSeconds, size: 36, onFelt: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(claimLabel)
    }

    /// The rank on the table: the one to lay now, or the one the last play claimed.
    private var claimRank: Int {
        if view.phase != .play, let last = view.lastPlay { return last.rank }
        return view.rank
    }

    private var claimLabel: String {
        let word = CheatRules.rankName(claimRank)
        return view.phase == .play ? "Lay \(word)" : "Claimed \(word)"
    }

    // MARK: - Calling

    private var challengeButtons: some View {
        HStack(spacing: 10) {
            Button {
                SRHaptic.tap()
                if let last = view.lastPlay { send(.call(turn: last.turn)) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.bubble.fill")
                    Text("CHEAT!")
                        .tracking(1.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .font(SR.Text.display(22))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0xEF4A4F), Color(hex: 0xB21E28)],
                                             startPoint: .top, endPoint: .bottom))
                        .shadow(color: Color(hex: 0xB21E28).opacity(0.45), radius: 10, x: 0, y: 5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(SRPressStyle())
            .disabled(waiting)
            .layoutPriority(1)
            .accessibilityLabel("Call cheat")
            .accessibilityIdentifier("offline-cheat-call")

            PlayTableButton(title: "Believe", icon: "hand.thumbsup", weight: .regular) {
                if let last = view.lastPlay { send(.pass(turn: last.turn)) }
            }
            .disabled(waiting)
            .accessibilityLabel("Believe them and let it go")
            .accessibilityIdentifier("offline-cheat-pass")
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private func revealCard(_ reveal: CheatRules.Reveal) -> some View {
        let width = max(48, min(66, (self.width - 2 * SR.cardPadding - 24) / 4))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SRSectionLabel(text: "\(who(reveal.callerId)) called Cheat!",
                               trailing: reveal.truthful ? "true" : "a lie")
            }
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    ForEach(Array(reveal.cards.enumerated()), id: \.offset) { index, card in
                        CheatFlipCard(card: card, width: width, honest: card.rank == reveal.rank,
                                      delay: PlayTableMath.stagger(index: index, step: 0.18, cap: 0.8))
                    }
                    Spacer(minLength: 0)
                }
                PlayTableStamp(text: reveal.truthful ? "True" : "Liar!", tone: reveal.truthful ? SR.good : SR.error, size: 24)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Turned over: " + reveal.cards.map(\.name).joined(separator: ", "))
            Text(revealSentence(reveal))
                .font(SR.Text.bodyMedium())
                .foregroundStyle(reveal.pickedUpBy == context.me ? SR.error : SR.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-cheat-reveal")
    }

    private func revealSentence(_ reveal: CheatRules.Reveal) -> String {
        let player = who(reveal.playerId)
        let taker = who(reveal.pickedUpBy)
        let verb = reveal.pickedUpBy == context.me ? "take" : "takes"
        if reveal.truthful {
            return "\(player) told the truth. \(taker) \(verb) the pile of \(reveal.pileSize)."
        }
        return "\(player) lied. \(taker) \(verb) the pile of \(reveal.pileSize)."
    }

    // MARK: - My hand

    private var myHand: some View {
        VStack(alignment: .leading, spacing: 14) {
            SRSectionLabel(text: "Your hand",
                           trailing: myTurn && !selected.isEmpty ? "\(selected.count) of 4 picked" : cardsText(view.myCards.count))
            OfflineHand(
                cards: view.myCards,
                cardWidth: handCardWidth,
                selected: selected,
                playable: myTurn && !waiting ? nil : Set<String>(),
                onTap: { card in toggle(card) }
            )
            .accessibilityIdentifier("offline-cheat-hand")

            if myTurn {
                PlayTableButton(title: playTitle, icon: "rectangle.stack.fill", haptic: .ok) {
                    let cards = view.myCards.filter { selected.contains($0.id) }
                    send(.play(turn: view.turn, cards: cards))
                }
                .disabled(selected.isEmpty || waiting)
                .accessibilityLabel(playLabel)
                .accessibilityIdentifier("offline-cheat-play")
            }
        }
    }

    private var playLabel: String {
        selected.isEmpty ? "Pick cards to lay" : "Lay \(cardsText(selected.count)) as \(rankWord)"
    }

    private var playTitle: String {
        selected.isEmpty ? "Pick cards" : "Lay \(selected.count) as \(CheatRules.rankText(view.rank))"
    }

    // MARK: - Acting

    private func toggle(_ card: OfflineCard) {
        guard myTurn, !waiting else { return }
        if selected.contains(card.id) {
            selected.remove(card.id)
        } else if selected.count < CheatRules.maxCardsPerPlay {
            selected.insert(card.id)
        } else {
            SRHaptic.bad()
        }
    }

    /// The host marked me away while my phone was gone; seeing views again
    /// means I am back, so say so once.
    private func comeBackIfAway() {
        guard let seat = mySeat else { return }
        if seat.away {
            guard !sentBack, view.phase != .won, view.phase != .over else { return }
            sentBack = true
            context.send(.back)
        } else {
            sentBack = false
        }
    }

    private func send(_ action: CheatRules.Action) {
        waiting = true
        context.send(action)
    }
}

/// A laid card turned over after a call: face down, then over it goes after
/// `delay`. The claimed rank's cards are ringed; the rest — the lies — dim.
struct CheatFlipCard: View {
    let card: OfflineCard
    let width: CGFloat
    let honest: Bool
    let delay: Double
    @State private var turned: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CheatFlipFace(progress: reduceMotion ? 1 : turned, card: card, width: width, honest: honest)
            .onAppear {
                guard !reduceMotion, turned < 1 else { return }
                withAnimation(.easeInOut(duration: 0.45).delay(delay)) { turned = 1 }
            }
    }
}

/// The two sides of a turning card: its back until half way, then its face.
/// Animatable, so the swap happens exactly edge-on.
struct CheatFlipFace: View, Animatable {
    var progress: Double
    let card: OfflineCard
    let width: CGFloat
    let honest: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let showFace = progress >= 0.5
        let angle = showFace ? (progress - 1) * 180 : progress * 180
        return Group {
            if showFace {
                OfflineCardFace(card: card, width: width, selected: honest)
                    .opacity(honest ? 1 : 0.8)
            } else {
                OfflineCardBack(width: width)
            }
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }
}
