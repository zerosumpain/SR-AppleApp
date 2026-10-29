import SwiftUI

/// Old Maid on one phone: whose turn it is, the face-down cards to draw from
/// when it is mine, what the last draw did, my own hand, and the table.
///
/// The view never changes the game. Tapping a face-down card sends one draw
/// with that card's position and waits for the host's next view; the card I
/// tapped sits raised until the host answers. The cards to draw from are a
/// grid of backs sized from the width available, so even a full hand of
/// thirteen stays on a 375pt screen with every card big enough to tap.
///
/// The overhaul (2026-10-29) put the draw on a plum velvet table — who is
/// drawing from whom, face to face, with the cards between them — turns the
/// drawn card over with a flip, pops "Pair!" (or the dreaded queen), and
/// ends on the odd queen under a ribbon with the loser's name.
struct OldMaidView: View {
    let context: OfflineGameContext<OldMaidRules>
    /// The turn number I last drew on, so a double tap sends once.
    @State private var sentTurn: Int?
    /// The position I tapped, raised until the host's view arrives.
    @State private var picked: Int?
    @State private var callout = ""
    @State private var calloutTone: Color = SR.accentDeep
    @State private var calloutIcon: String?
    @State private var calloutToken = 0
    @State private var burstToken = 0

    private var view: OldMaidRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                status
                if view.phase != .playing {
                    finale
                } else {
                    drawTable
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
        .overlay {
            ZStack {
                NearbyPlayBurst(token: burstToken)
                NearbyPlayCallout(text: callout, icon: calloutIcon, tone: calloutTone, token: calloutToken)
            }
        }
        .accessibilityIdentifier("offline-old-maid")
        .onChange(of: view.turnNumber) { _, _ in
            sentTurn = nil
            picked = nil
            if myTurn { SRHaptic.tap() }
        }
        .onChange(of: view.lastDraw) { _, new in
            guard let new else { return }
            react(to: new)
        }
        .onChange(of: view.phase) { _, new in
            guard new != .playing else { return }
            if view.loser == context.me {
                SRHaptic.bad()
            } else if mySeat != nil {
                SRHaptic.ok()
                burstToken += 1
            }
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

    private func seatTone(_ id: String?) -> Color {
        guard let id, let index = view.seats.firstIndex(where: { $0.id == id }) else { return SR.accent }
        return OfflineSeatColour.of(index)
    }

    private var status: some View {
        NearbyPlayBanner(kicker: kicker, title: headline, strap: instruction, mine: myTurn,
                         tone: seatTone(view.turn), mark: bannerMark) {
            bannerClock
        }
        .accessibilityIdentifier("offline-old-maid-status")
    }

    @ViewBuilder
    private var bannerClock: some View {
        if view.phase == .playing {
            NearbyPlayBannerClock(clock: context.clock, until: view.turnEndsAt,
                                  total: OldMaidRules.turnSeconds, mine: myTurn)
        } else if view.phase == .finale {
            NearbyPlayBannerClock(clock: context.clock, until: view.finaleUntil,
                                  total: OldMaidRules.finalePause, mine: false)
                .accessibilityLabel("Standings soon")
        }
    }

    private var bannerMark: NearbyPlayMark {
        if view.phase != .playing { return .symbol("crown.fill") }
        guard let turn = view.turn else { return .symbol("suit.heart.fill") }
        return .person(context.name(of: turn))
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

    // MARK: - The draw

    /// The velvet: the drawer and the one drawn from, face to face, and the
    /// face-down cards between them — buttons when the draw is mine.
    private var drawTable: some View {
        NearbyPlayFelt(tone: .plum) {
            VStack(spacing: 14) {
                faceOff
                if let target = view.target, view.targetCards > 0 {
                    if myTurn {
                        fanSection(target)
                    } else {
                        watchFan
                    }
                }
            }
        }
    }

    /// "Sam → Ann": who is drawing from whom.
    private var faceOff: some View {
        HStack(spacing: 10) {
            person(view.turn, caption: "drawing")
            Image(systemName: "arrow.left")
                .font(SR.Text.display(22))
                .foregroundStyle(NearbyPlayFeltInk.gold)
                .accessibilityHidden(true)
            person(view.target, caption: view.targetCards == 1 ? "1 card" : "\(view.targetCards) cards")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(faceOffLabel)
    }

    private var faceOffLabel: String {
        guard let turn = view.turn, let target = view.target else { return "Waiting for the table" }
        return "\(who(turn)) drawing from \(target == context.me ? "you" : context.name(of: target))"
    }

    private func person(_ id: String?, caption: String) -> some View {
        VStack(spacing: 4) {
            if let id {
                OfflineInitial(name: context.name(of: id), size: 48, tone: seatTone(id))
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 2) }
                Text(who(id))
                    .font(SR.Text.title(15))
                    .foregroundStyle(NearbyPlayFeltInk.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Circle().fill(NearbyPlayFeltInk.chip).frame(width: 48, height: 48)
                Text("—")
                    .font(SR.Text.title(15))
                    .foregroundStyle(NearbyPlayFeltInk.faint)
            }
            Text(caption)
                .font(SR.Text.mono(12))
                .foregroundStyle(NearbyPlayFeltInk.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func fanSection(_ target: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PICK ONE OF \(context.name(of: target).uppercased())'S CARDS")
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(NearbyPlayFeltInk.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52, maximum: 68), spacing: 8)], spacing: 12) {
                ForEach(0..<view.targetCards, id: \.self) { position in
                    backButton(position, of: view.targetCards, from: target)
                }
            }
            .padding(.top, 6)
            .accessibilityIdentifier("offline-old-maid-fan")
        }
    }

    /// The same backs, small and still, for everyone watching the draw.
    private var watchFan: some View {
        let count = min(view.targetCards, 13)
        return HStack(spacing: -22) {
            ForEach(0..<count, id: \.self) { index in
                OfflineCardBack(width: 40)
                    .rotationEffect(.degrees((Double(index) - Double(count - 1) / 2) * 3))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func backButton(_ position: Int, of count: Int, from target: String) -> some View {
        let raised = picked == position
        let tilt = Double((position % 3) - 1) * 3
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
                            .strokeBorder(NearbyPlayFeltInk.gold, lineWidth: 3)
                    }
                }
                .rotationEffect(.degrees(raised ? 0 : tilt))
                .offset(y: raised ? -10 : 0)
                .shadow(color: raised ? NearbyPlayFeltInk.gold.opacity(0.6) : Color.black.opacity(0.2),
                        radius: raised ? 10 : 3, x: 0, y: raised ? 6 : 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .disabled(sentTurn == view.turnNumber)
        .srAnimation(.spring(response: 0.3, dampingFraction: 0.6), value: raised)
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
            Group {
                if let pair = note.pair, pair.count == 2 {
                    HStack(spacing: -18) {
                        OfflineCardFace(card: pair[0], width: 44)
                            .rotationEffect(.degrees(-6))
                        OfflineCardFace(card: pair[1], width: 44)
                            .rotationEffect(.degrees(6))
                    }
                    .fixedSize()
                } else {
                    NearbyPlayFlipCard(card: note.card, width: 44)
                }
            }
            .accessibilityHidden(true)
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
        NearbyPlayFelt(tone: .plum) {
            VStack(spacing: 14) {
                ZStack(alignment: .bottom) {
                    Group {
                        if let card = view.oldMaidCard {
                            OfflineCardFace(card: card, width: 96)
                        } else {
                            OfflineCardBack(width: 96)
                        }
                    }
                    .rotationEffect(.degrees(-4))
                    .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 6)
                    Text(view.oldMaidCard == nil ? "GAME OVER" : "OLD MAID")
                        .font(SR.Text.label(14))
                        .tracking(2)
                        .foregroundStyle(Color(hex: 0x4A0F2E))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(NearbyPlayFeltInk.gold))
                        .offset(y: 14)
                }
                .padding(.bottom, 14)
                .accessibilityHidden(true)
                Text(finaleLine)
                    .font(SR.Text.title())
                    .foregroundStyle(NearbyPlayFeltInk.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-old-maid-finale")
    }

    private var finaleLine: String {
        guard view.oldMaidCard != nil else { return "Game over" }
        guard let loser = view.loser else { return "The odd queen" }
        return loser == context.me ? "The odd queen stayed with you" : "The odd queen stayed with \(context.name(of: loser))"
    }

    // MARK: - My hand

    private func handSection(_ hand: [OfflineCard]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Your hand", trailing: cardsText(hand.count))
            OfflineHand(cards: hand, cardWidth: 60)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your hand: " + hand.map(\.name).joined(separator: ", "))
                .accessibilityIdentifier("offline-old-maid-hand")
            if hand.contains(where: { $0.rank == 12 }) && view.phase == .playing {
                Label("You hold a queen. If it never pairs, it's the Old Maid.", systemImage: "exclamationmark.triangle.fill")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.warn)
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
            OfflineInitial(name: seat.name, size: 32, tone: OfflineSeatColour.of(index))
                .overlay { Circle().strokeBorder(isTurn ? SR.accent : Color.clear, lineWidth: 2.5).padding(-3) }
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
                    .font(SR.Text.title(17))
                    .foregroundStyle(SR.good)
                    .accessibilityHidden(true)
            } else if view.loser == seat.id {
                Image(systemName: "crown.fill")
                    .font(SR.Text.title(17))
                    .foregroundStyle(SR.error)
                    .accessibilityHidden(true)
            }
            Text("\(seat.cards)")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .contentTransition(.numericText(value: Double(seat.cards)))
                .frame(minWidth: 26, alignment: .trailing)
                .fixedSize()
                .accessibilityHidden(true)
        }
        .frame(minHeight: 52)
        .padding(.vertical, 2)
        .srAnimation(.snappy(duration: 0.25), value: seat)
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

    // MARK: - Moments

    private func react(to note: OldMaidRules.DrawNote) {
        if note.drawer == context.me {
            if note.pair != nil {
                SRHaptic.ok()
                pop("Pair! Down they go", icon: "rectangle.on.rectangle", tone: SR.good)
            } else if note.card?.rank == 12 {
                SRHaptic.bad()
                pop("Oh no — a queen!", icon: "crown.fill", tone: SR.error)
            }
        } else if note.from == context.me && note.card?.rank == 12 {
            SRHaptic.ok()
            pop("They took your queen!", icon: "hand.thumbsup.fill", tone: SR.good)
        }
    }

    private func pop(_ text: String, icon: String?, tone: Color) {
        callout = text
        calloutIcon = icon
        calloutTone = tone
        calloutToken += 1
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
