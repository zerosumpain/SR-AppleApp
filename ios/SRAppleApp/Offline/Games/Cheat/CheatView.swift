import SwiftUI

/// Cheat on one phone: the table, the claim to make, my hand, and the
/// "Cheat!" button while somebody else's play can still be called.
///
/// The host decides everything; this view draws the latest `PlayerView` and
/// sends one action at a time. On my turn I tap up to four cards to raise
/// them, then lay them as the rank shown — honest or not. When anybody else
/// lays cards, two buttons appear for a few seconds: call Cheat!, or believe
/// them. A call turns the cards over for everyone and says who took the pile.
struct CheatView: View {
    let context: OfflineGameContext<CheatRules>
    /// Card ids raised to be laid, at most four.
    @State private var selected: Set<String> = []
    /// An action has gone to the host and its answer has not come back yet,
    /// so a double tap sends once. Any new view clears it.
    @State private var waiting = false
    /// "I'm back" has been sent for this absence, so it goes once.
    @State private var sentBack = false

    private var view: CheatRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: kicker, title: title, strap: strap)
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
                    if view.phase == .play, view.turnPlayer == seat.id {
                        Image(systemName: "arrowtriangle.left.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SR.accent)
                            .accessibilityHidden(true)
                    }
                    if view.phase == .challenge, seat.passed {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SR.good)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 6)
                    Text(seat.away ? "left" : cardsText(seat.cards))
                        .font(SR.Text.mono(13))
                        .foregroundStyle(seat.cards <= 2 && !seat.away ? SR.warn : SR.inkSecondary)
                        .lineLimit(1)
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
        .accessibilityIdentifier("offline-cheat-seats")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 18) {
                VStack(spacing: 6) {
                    OfflineCardBack(width: 60)
                        .opacity(view.pileCount > 0 ? 1 : 0.3)
                    Text("\(view.pileCount) down")
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("The pile, \(cardsText(view.pileCount)) face down")

                VStack(alignment: .leading, spacing: 4) {
                    Text(view.phase == .play ? "LAY" : "CLAIMED")
                        .font(SR.Text.label(12))
                        .tracking(1.4)
                        .foregroundStyle(SR.inkMuted)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(CheatRules.rankText(claimRank))
                            .font(SR.Text.hero(40))
                            .foregroundStyle(SR.ink)
                            .lineLimit(1)
                            .fixedSize()
                        Text(CheatRules.rankName(claimRank))
                            .font(SR.Text.title())
                            .foregroundStyle(SR.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    if let deadline = countdownDeadline {
                        OfflineCountdown(clock: context.clock, until: deadline,
                                         font: SR.Text.mono(13), tone: SR.inkMuted)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(claimLabel)
                Spacer(minLength: 0)
            }
            if let line = lastPlayText {
                Text(line)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("offline-cheat-last-play")
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-cheat-table")
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

    private var countdownDeadline: Double? {
        switch view.phase {
        case .play: return myTurn ? view.turnEndsAt : nil
        case .challenge: return view.challengeEndsAt
        case .reveal, .won, .over: return nil
        }
    }

    // MARK: - Calling

    private var challengeButtons: some View {
        HStack(spacing: 10) {
            Button {
                SRHaptic.tap()
                if let last = view.lastPlay { send(.call(turn: last.turn)) }
            } label: {
                SRButtonLabel(title: "Cheat!", icon: "exclamationmark.bubble.fill", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(waiting)
            .accessibilityLabel("Call cheat")
            .accessibilityIdentifier("offline-cheat-call")

            Button {
                SRHaptic.tap()
                if let last = view.lastPlay { send(.pass(turn: last.turn)) }
            } label: {
                SRButtonLabel(title: "Believe", icon: "hand.thumbsup", fill: true)
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(waiting)
            .accessibilityLabel("Believe them and let it go")
            .accessibilityIdentifier("offline-cheat-pass")
        }
    }

    private func revealCard(_ reveal: CheatRules.Reveal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "\(who(reveal.callerId)) called Cheat!",
                           trailing: reveal.truthful ? "true" : "a lie")
            HStack(spacing: 8) {
                ForEach(Array(reveal.cards.enumerated()), id: \.offset) { _, card in
                    OfflineCardFace(card: card, width: 56, selected: card.rank == reveal.rank)
                        .opacity(card.rank == reveal.rank ? 1 : 0.75)
                }
                Spacer(minLength: 0)
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
                cardWidth: 60,
                selected: selected,
                playable: myTurn && !waiting ? nil : Set<String>(),
                onTap: { card in toggle(card) }
            )
            .accessibilityIdentifier("offline-cheat-hand")

            if myTurn {
                Button {
                    SRHaptic.ok()
                    let cards = view.myCards.filter { selected.contains($0.id) }
                    send(.play(turn: view.turn, cards: cards))
                } label: {
                    SRButtonLabel(title: playTitle, icon: "rectangle.stack.fill", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
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
