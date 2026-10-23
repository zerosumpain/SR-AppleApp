import SwiftUI

/// Old Maid on one phone: whose turn it is, the face-down fan to draw from
/// when it is mine, what the last draw did, my own hand, and the table.
///
/// The view never changes the game. Tapping a face-down card sends one draw
/// with that card's position and waits for the host's next view; the card I
/// tapped sits raised until the host answers. The fan is a grid of card
/// backs sized from the width available, so even a full hand of thirteen
/// stays on a 375pt screen with every card big enough to tap.
struct OldMaidView: View {
    let context: OfflineGameContext<OldMaidRules>
    /// The turn number I last drew on, so a double tap sends once.
    @State private var sentTurn: Int?
    /// The position I tapped, raised until the host's view arrives.
    @State private var picked: Int?

    private var view: OldMaidRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                status
                if view.phase != .playing {
                    finale
                } else if myTurn, let target = view.target {
                    fanSection(target)
                }
                if let note = view.lastDraw, view.phase == .playing {
                    lastDrawCard(note)
                }
                if let hand = view.myHand, !hand.isEmpty {
                    handSection(hand)
                }
                tableSection
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("offline-old-maid")
        .onChange(of: view.turnNumber) { _, _ in
            sentTurn = nil
            picked = nil
        }
        .onChange(of: context.refusal) { _, new in
            guard new != nil else { return }
            SRHaptic.bad()
            sentTurn = nil
            picked = nil
        }
    }

    // MARK: - Who is doing what

    private var mySeat: OldMaidRules.Seat? { view.seats.first { $0.id == context.me } }

    private var myTurn: Bool { view.phase == .playing && view.turn == context.me }

    private func who(_ id: String) -> String {
        id == context.me ? "You" : context.name(of: id)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRPageHeader(kicker: kicker, title: headline, strap: instruction)
            if view.phase == .playing {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SR.inkMuted)
                        .accessibilityHidden(true)
                    Text(myTurn ? "Your time" : "Turn time")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                    OfflineCountdown(clock: context.clock, until: view.turnEndsAt, font: SR.Text.mono(), tone: SR.inkMuted)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("offline-old-maid-status")
    }

    private var kicker: String {
        let holding = view.seats.filter { $0.cards > 0 }.count
        return "Pairs down \(view.discarded / 2) · \(holding) still holding"
    }

    private var headline: String {
        if view.phase != .playing {
            guard let loser = view.loser else { return "Game over" }
            return loser == context.me ? "You're the Old Maid" : "\(context.name(of: loser)) is the Old Maid"
        }
        if myTurn { return "Your turn" }
        guard let turn = view.turn else { return "Old Maid" }
        return "\(context.name(of: turn))'s turn"
    }

    private var instruction: String? {
        if view.phase != .playing {
            if view.loser == context.me { return "You were left holding the odd queen." }
            if mySeat?.safe == true { return "You got rid of every card. Safe!" }
            guard let loser = view.loser else { return "The game ended early." }
            return "\(context.name(of: loser)) was left holding the odd queen."
        }
        guard let seat = mySeat else { return "You are watching this game." }
        if seat.away { return "You have left this game. The others can still draw from your cards." }
        if seat.safe { return "You're safe — no cards left. Watch the rest play out." }
        if myTurn {
            if sentTurn == view.turnNumber { return "Drawing…" }
            guard let target = view.target else { return "Waiting for the table." }
            return "Tap one of \(context.name(of: target))'s face-down cards to draw it."
        }
        if view.target == context.me, let turn = view.turn {
            return "\(context.name(of: turn)) is picking one of your cards."
        }
        return "Wait for your turn. Pairs go down by themselves."
    }

    // MARK: - Drawing

    private func fanSection(_ target: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Draw from \(context.name(of: target))", trailing: cardsText(view.targetCards))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: SR.tapTarget, maximum: 64), spacing: 8)], spacing: 10) {
                ForEach(0..<view.targetCards, id: \.self) { position in
                    backButton(position, of: view.targetCards, from: target)
                }
            }
            .padding(.top, 6)
            .accessibilityIdentifier("offline-old-maid-fan")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private func backButton(_ position: Int, of count: Int, from target: String) -> some View {
        let raised = picked == position
        return Button {
            draw(position)
        } label: {
            Color.clear
                .aspectRatio(1 / OfflineCardMetrics.aspect, contentMode: .fit)
                .overlay {
                    GeometryReader { geo in
                        OfflineCardBack(width: geo.size.width)
                    }
                }
                .overlay {
                    if raised {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(SR.ink, lineWidth: 2.5)
                    }
                }
                .offset(y: raised ? -6 : 0)
        }
        .buttonStyle(.plain)
        .disabled(sentTurn == view.turnNumber)
        .accessibilityLabel("Card \(position + 1) of \(count), face down")
        .accessibilityHint("Draws this card from \(context.name(of: target)).")
        .accessibilityIdentifier("offline-old-maid-card-\(position)")
    }

    private func draw(_ position: Int) {
        guard myTurn, sentTurn != view.turnNumber, position >= 0, position < view.targetCards else { return }
        SRHaptic.tap()
        sentTurn = view.turnNumber
        picked = position
        context.send(.draw(turn: view.turnNumber, position: position))
    }

    // MARK: - The last draw

    private func lastDrawCard(_ note: OldMaidRules.DrawNote) -> some View {
        HStack(alignment: .center, spacing: 14) {
            if let pair = note.pair, pair.count == 2 {
                HStack(spacing: -18) {
                    OfflineCardFace(card: pair[0], width: 44)
                    OfflineCardFace(card: pair[1], width: 44)
                }
                .fixedSize()
            } else if let card = note.card {
                OfflineCardFace(card: card, width: 44)
            } else {
                OfflineCardBack(width: 44)
            }
            Text(drawSentence(note))
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(drawSentence(note))
        .accessibilityIdentifier("offline-old-maid-last-draw")
    }

    private func drawSentence(_ note: OldMaidRules.DrawNote) -> String {
        let pairText = note.pair.flatMap { $0.first }.map { "a pair of \(rankPlural($0.rank))" }
        if note.drawer == context.me {
            let lead = note.automatic ? "Time ran out, so a card was drawn for you" : "You drew"
            let what = note.card.map { "the \($0.text)" } ?? "a card"
            let base = note.automatic ? "\(lead): \(what) from \(context.name(of: note.from))" : "\(lead) \(what) from \(context.name(of: note.from))"
            if let pairText { return "\(base) — \(pairText) went down." }
            return note.card?.rank == 12 ? "\(base). That's a queen — hope someone draws it from you." : "\(base)."
        }
        if note.from == context.me {
            let what = note.card.map { "your \($0.text)" } ?? "one of your cards"
            if let pairText { return "\(context.name(of: note.drawer)) took \(what) and put down \(pairText)." }
            return "\(context.name(of: note.drawer)) took \(what)."
        }
        let base = "\(who(note.drawer)) drew a card from \(who(note.from))"
        if let pairText { return "\(base) and put down \(pairText)." }
        return "\(base)."
    }

    // MARK: - The end

    private var finale: some View {
        VStack(spacing: 14) {
            if let card = view.oldMaidCard {
                OfflineCardFace(card: card, width: 84)
            } else {
                OfflineCardBack(width: 84)
            }
            Text(view.oldMaidCard == nil ? "Game over" : "The odd queen")
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if view.phase == .finale {
                HStack(spacing: 8) {
                    Text("Standings in")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                    OfflineCountdown(clock: context.clock, until: view.finaleUntil, font: SR.Text.mono(), tone: SR.inkMuted)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-old-maid-finale")
    }

    // MARK: - My hand

    private func handSection(_ hand: [OfflineCard]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Your hand", trailing: cardsText(hand.count))
            OfflineHand(cards: hand, cardWidth: 56)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your hand: " + hand.map(\.name).joined(separator: ", "))
                .accessibilityIdentifier("offline-old-maid-hand")
            if hand.contains(where: { $0.rank == 12 }) && view.phase == .playing {
                Text("You hold a queen. If it never pairs, it's the Old Maid.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - The table

    private var tableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Table")
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
        .accessibilityIdentifier("offline-old-maid-table")
    }

    private func seatRow(_ seat: OldMaidRules.Seat, index: Int) -> some View {
        let isTurn = view.turn == seat.id
        let isTarget = view.target == seat.id
        return HStack(spacing: 10) {
            OfflineInitial(name: seat.name, size: 28, tone: OfflineSeatColour.of(index))
            VStack(alignment: .leading, spacing: 2) {
                Text(seat.id == context.me ? "You" : seat.name)
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(seat.away ? SR.inkMuted : SR.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(seatDetail(seat, isTurn: isTurn, isTarget: isTarget))
                    .font(SR.Text.mono())
                    .foregroundStyle(isTurn ? SR.accent : SR.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if seat.safe {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SR.good)
                    .accessibilityHidden(true)
            } else if view.loser == seat.id {
                Image(systemName: "crown.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SR.error)
                    .accessibilityHidden(true)
            }
            Text("\(seat.cards)")
                .font(SR.Text.display(20))
                .foregroundStyle(SR.ink)
                .frame(minWidth: 26, alignment: .trailing)
                .fixedSize()
                .accessibilityHidden(true)
        }
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(who(seat.id)), \(seatDetail(seat, isTurn: isTurn, isTarget: isTarget))")
        .accessibilityIdentifier("offline-old-maid-seat-\(seat.id)")
    }

    private func seatDetail(_ seat: OldMaidRules.Seat, isTurn: Bool, isTarget: Bool) -> String {
        var parts: [String] = []
        if let place = seat.place {
            parts.append("safe, \(OldMaidRules.ordinal(place)) out")
        } else if view.loser == seat.id {
            parts.append("the Old Maid")
        } else {
            parts.append(cardsText(seat.cards))
        }
        if isTurn { parts.append("drawing") }
        if isTarget { parts.append("being drawn from") }
        if seat.away { parts.append("left") }
        let pairs = seat.pairs == 1 ? "1 pair" : "\(seat.pairs) pairs"
        parts.append(pairs)
        return parts.joined(separator: " · ")
    }

    // MARK: - Words

    private func cardsText(_ n: Int) -> String {
        n == 1 ? "1 card" : "\(n) cards"
    }

    private func rankPlural(_ rank: Int) -> String {
        switch rank {
        case 1: return "aces"
        case 11: return "jacks"
        case 12: return "queens"
        case 13: return "kings"
        case 6: return "sixes"
        default: return "\(rank)s"
        }
    }
}
