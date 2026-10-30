import SwiftUI

/// Liar's Dice on one phone: whose bid and the turn clock, my cup, the bid
/// standing and the round's bids, the bid picker and Liar! on my turn, the
/// lifted cups after a call, and everyone's dice left.
///
/// The dice are the online game's `LiarsDie`, so the cups look the same as
/// on the site; mine light up when they count towards the standing bid's
/// face (ones always do — they are wild). The picker starts on the smallest
/// raise and checks every bid with the rules' own `problem` before sending,
/// so a mistake is explained before it reaches the host.
///
/// The overhaul (2026-10-29) set the table in a tavern: everyone along the
/// top with their dice left on their discs, the standing bid as a plaque,
/// my dice in a cup tray, big steppers and dice to pick a bid with, Liar!
/// as its own red button, and the cups lifting with a verdict that pops.
struct OfflineLiarsDiceView: View {
    let context: OfflineGameContext<OfflineLiarsDiceRules>
    /// The bid being put together on my turn.
    @State private var quantity = 1
    @State private var face = 2
    /// An action has gone to the host and its answer has not come back yet.
    @State private var waiting = false
    @State private var callout = ""
    @State private var calloutTone: Color = SR.accentDeep
    @State private var calloutToken = 0
    @State private var burstToken = 0

    private typealias Rules = OfflineLiarsDiceRules
    private var view: Rules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                banner
                table
                if let reveal = view.reveal { revealCard(reveal) }
                if myTurn { picker }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .overlay {
            ZStack {
                NearbyPlayBurst(token: burstToken)
                NearbyPlayCallout(text: callout, icon: "die.face.5.fill", tone: calloutTone, token: calloutToken)
            }
        }
        .accessibilityIdentifier("offline-liars-dice")
        .onAppear { resetPicker() }
        .onChange(of: view) { _, _ in waiting = false }
        .onChange(of: view.turnNumber) { _, _ in
            resetPicker()
            if myTurn { SRHaptic.tap() }
        }
        .onChange(of: view.phase) { _, new in
            if new == .reveal, let reveal = view.reveal {
                if reveal.loserId == context.me { SRHaptic.bad() } else { SRHaptic.ok() }
                popReveal(reveal)
            }
            if (new == .done || new == .over) && view.winner == context.me {
                burstToken += 1
            }
        }
        .onChange(of: context.refusal) { _, new in
            if new != nil {
                SRHaptic.bad()
                waiting = false
            }
        }
        .task(id: waiting) {
            guard waiting else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { waiting = false }
        }
    }

    // MARK: - Words

    private var myTurn: Bool { view.phase == .bidding && view.turnPlayer == context.me }

    private var standing: Rules.Bid? { view.bids.last }

    private func who(_ id: String) -> String { id == context.me ? "You" : context.name(of: id) }

    private var kicker: String {
        "Liar's Dice · Round \(view.round) · \(view.totalDice) dice in play"
    }

    private var title: String {
        switch view.phase {
        case .bidding:
            if myTurn { return "Your bid" }
            guard let turn = view.turnPlayer else { return "Liar's Dice" }
            return "\(context.name(of: turn)) is bidding"
        case .reveal:
            guard let reveal = view.reveal else { return "Cups up" }
            return reveal.bidStood ? "The bid stood" : "Caught out"
        case .done, .over:
            guard let winner = view.winner else { return "Game over" }
            return winner == context.me ? "You win" : "\(context.name(of: winner)) wins"
        }
    }

    private var strap: String? {
        switch view.phase {
        case .bidding:
            if view.myDice.isEmpty {
                return view.seats.contains(where: { $0.id == context.me }) ? "You are out of dice — watch the rest." : "You are watching this game."
            }
            if let standing {
                let bid = Rules.bidText(quantity: standing.quantity, face: standing.face)
                return "\(who(standing.playerId)) bid \(bid)\(standing.auto ? " (time ran out)" : ""). Ones are wild."
            }
            return myTurn ? "Open the bidding. Ones are wild." : "Waiting for the first bid. Ones are wild."
        case .reveal:
            return view.reveal.map { Rules.revealLine($0, name: who) }
        case .done, .over:
            return view.reveal.map { Rules.revealLine($0, name: who) }
        }
    }

    private func seatTone(_ id: String?) -> Color {
        guard let id else { return SR.accent }
        return OfflineSeatColour.of(view.seats.firstIndex { $0.id == id } ?? 0)
    }

    // MARK: - The top

    private var bannerMark: NearbyPlayMark {
        switch view.phase {
        case .bidding:
            return view.turnPlayer.map { NearbyPlayMark.person(context.name(of: $0)) } ?? .symbol("die.face.5.fill")
        case .reveal:
            return .symbol("cup.and.saucer.fill")
        case .done, .over:
            return .symbol("trophy.fill")
        }
    }

    @ViewBuilder
    private var banner: some View {
        if view.phase == .bidding {
            NearbyPlayBanner(kicker: kicker, title: title, strap: strap, mine: myTurn,
                             tone: seatTone(view.turnPlayer), mark: bannerMark) {
                NearbyPlayBannerClock(clock: context.clock, until: view.turnEndsAt,
                                      total: Rules.turnSeconds, mine: myTurn)
            }
            .accessibilityIdentifier("offline-liars-dice-turn")
        } else {
            NearbyPlayBanner(kicker: kicker, title: title, strap: strap,
                             mine: view.winner == context.me && view.phase != .reveal,
                             tone: seatTone(view.reveal?.loserId), mark: bannerMark)
        }
    }

    // MARK: - The table

    private var stripSeats: [NearbyPlaySeat] {
        view.seats.enumerated().map { pair -> NearbyPlaySeat in
            let seat = pair.element
            let status: String = seat.left ? "left" : seat.out ? "out" : (seat.dice == 1 ? "1 die" : "\(seat.dice) dice")
            var spoken = "\(who(seat.id)), \(status)"
            if view.turnPlayer == seat.id { spoken += ", bidding now" }
            if view.winner == seat.id { spoken += ", winner" }
            return NearbyPlaySeat(
                id: seat.id, name: seat.name, tone: OfflineSeatColour.of(pair.offset),
                isMe: seat.id == context.me,
                acting: view.phase == .bidding && view.turnPlayer == seat.id,
                faded: seat.out || seat.left,
                badge: seat.out || seat.left ? nil : "\(seat.dice)",
                detail: status,
                mark: view.winner == seat.id ? "crown.fill" : (view.reveal?.loserId == seat.id ? "minus.circle.fill" : nil),
                markTone: view.winner == seat.id ? NearbyPlayFeltInk.gold : Color(hex: 0xFF8A80),
                spoken: spoken
            )
        }
    }

    private var table: some View {
        NearbyPlayFelt(tone: .tavern) {
            VStack(alignment: .leading, spacing: 14) {
                NearbyPlaySeatStrip(seats: stripSeats)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("offline-liars-dice-players")
                if view.phase == .bidding {
                    standingPlaque
                    if !view.myDice.isEmpty { myCup }
                }
            }
        }
    }

    /// The bid to beat, as a plaque: "3 × ⚄", by whom, and the bids before it.
    private var standingPlaque: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THE BID TO BEAT")
                .font(SR.Text.label())
                .tracking(1.3)
                .foregroundStyle(NearbyPlayFeltInk.secondary)
            if let standing {
                HStack(spacing: 12) {
                    Text("\(standing.quantity) ×")
                        .font(SR.Text.figure(34))
                        .foregroundStyle(NearbyPlayFeltInk.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    LiarsDie(face: standing.face, side: 46, lit: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Rules.bidText(quantity: standing.quantity, face: standing.face))
                            .font(SR.Text.title(16))
                            .foregroundStyle(NearbyPlayFeltInk.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("bid by \(who(standing.playerId))")
                            .font(SR.Text.mono())
                            .foregroundStyle(NearbyPlayFeltInk.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .id("\(standing.quantity)-\(standing.face)-\(standing.playerId)")
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("offline-liars-dice-standing")
                if view.bids.count > 1 {
                    Text(view.bids.dropLast().map { "\(who($0.playerId)): \(Rules.bidText(quantity: $0.quantity, face: $0.face))" }
                        .joined(separator: " · "))
                        .font(SR.Text.mono(12))
                        .foregroundStyle(NearbyPlayFeltInk.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(myTurn ? "No bid yet — you open." : "No bid yet.")
                    .font(SR.Text.title(17))
                    .foregroundStyle(NearbyPlayFeltInk.primary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(NearbyPlayFeltInk.chip))
        .srAnimation(.spring(response: 0.35, dampingFraction: 0.7), value: view.bids.count)
    }

    /// My dice in a dark cup tray; the ones that count towards the bid lit.
    private var myCup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("YOUR CUP")
                    .font(SR.Text.label())
                    .tracking(1.3)
                    .foregroundStyle(NearbyPlayFeltInk.secondary)
                Spacer(minLength: 6)
                if let standing {
                    let counting = view.myDice.filter { Rules.counts($0, towards: standing.face) }.count
                    Text(counting == 1 ? "1 of yours counts" : "\(counting) of yours count")
                        .font(SR.Text.mono(12))
                        .foregroundStyle(NearbyPlayFeltInk.gold)
                        .lineLimit(1)
                }
            }
            GeometryReader { geo in
                let side = max(16, min(56, (geo.size.width - 4 * 8) / 5))
                HStack(spacing: 8) {
                    ForEach(Array(view.myDice.enumerated()), id: \.offset) { _, die in
                        LiarsDie(face: die, side: side, lit: standing.map { Rules.counts(die, towards: $0.face) } ?? false)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            }
            .frame(height: 56)
            .padding(10)
            .background(
                Capsule().fill(Color.black.opacity(0.32))
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your dice: " + view.myDice.map(String.init).joined(separator: ", "))
            .accessibilityIdentifier("offline-liars-dice-cup")
        }
    }

    // MARK: - Bidding

    private var problem: String? {
        Rules.problem(quantity: quantity, face: face, standing: standing, total: view.totalDice)
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 14) {
            SRSectionLabel(text: "Your bid")
            HStack(spacing: 12) {
                stepButton("minus", label: "One fewer") { quantity = max(1, quantity - 1) }
                    .disabled(quantity <= 1)
                VStack(spacing: 0) {
                    Text("\(quantity)")
                        .font(SR.Text.figure(36))
                        .foregroundStyle(SR.ink)
                        .contentTransition(.numericText(value: Double(quantity)))
                        .srAnimation(.snappy(duration: 0.2), value: quantity)
                    Text(quantity == 1 ? "die" : "dice")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
                .frame(minWidth: 56)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(quantity) dice")
                stepButton("plus", label: "One more") { quantity = min(view.totalDice, quantity + 1) }
                    .disabled(quantity >= view.totalDice)
                Text("showing")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                ForEach(Rules.lowestFace...Rules.faces, id: \.self) { value in
                    faceButton(value)
                }
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                NearbyPlayButton(title: "Bid", icon: "hand.raised.fill", kind: .primary,
                                 enabled: problem == nil && !waiting, minHeight: 64) {
                    send(.bid(turn: view.turnNumber, quantity: quantity, face: face))
                }
                .accessibilityLabel("Bid \(Rules.bidText(quantity: quantity, face: face))")
                .accessibilityIdentifier("offline-liars-dice-bid")
                if standing != nil {
                    NearbyPlayButton(title: "Liar!", icon: "exclamationmark.bubble.fill", kind: .danger,
                                     enabled: !waiting, minHeight: 64) {
                        send(.liar(turn: view.turnNumber))
                    }
                    .accessibilityLabel("Call liar")
                    .accessibilityIdentifier("offline-liars-dice-liar")
                }
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-liars-dice-picker")
    }

    private func faceButton(_ value: Int) -> some View {
        let picked = face == value
        return Button {
            SRHaptic.select()
            face = value
        } label: {
            LiarsDie(face: value, side: 46, lit: picked)
                .scaleEffect(picked ? 1.1 : 1)
                .frame(maxWidth: .infinity, minHeight: 58)
                .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .srAnimation(.snappy(duration: 0.2), value: picked)
        .accessibilityLabel("\(value)s")
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("offline-liars-dice-face-\(value)")
    }

    private func stepButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        let shape = Circle()
        return Button {
            SRHaptic.select()
            action()
        } label: {
            Image(systemName: icon)
                .font(SR.Text.title(20))
                .foregroundStyle(SR.ink)
                .frame(width: 56, height: 56)
                .background(shape.fill(SR.surface))
                .overlay(shape.strokeBorder(SR.line, lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(label)
    }

    // MARK: - The cups, lifted

    private func revealCard(_ reveal: Rules.Reveal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            verdictPlaque(reveal)
            ForEach(reveal.cups) { cup in
                cupRow(cup, reveal: reveal)
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-liars-dice-reveal")
    }

    /// "Counted 3 — the bid was 4 fives": the sum the call turned on.
    private func verdictPlaque(_ reveal: Rules.Reveal) -> some View {
        HStack(spacing: 12) {
            LiarsDie(face: reveal.bid.face, side: 40, lit: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Counted \(reveal.count) of \(reveal.bid.quantity)")
                    .font(SR.Text.title(18))
                    .foregroundStyle(SR.ink)
                Text(reveal.bidStood ? "The bid stood — the caller loses a die." : "Short — the bidder loses a die.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: reveal.bidStood ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(SR.Text.display(28))
                .foregroundStyle(reveal.bidStood ? SR.good : SR.error)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func cupRow(_ cup: Rules.Cup, reveal: Rules.Reveal) -> some View {
        let loser = cup.playerId == reveal.loserId
        return HStack(spacing: 8) {
            OfflineInitial(name: context.name(of: cup.playerId), size: 28, tone: seatTone(cup.playerId))
            Text(who(cup.playerId))
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(loser ? SR.error : SR.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 64, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(Array(cup.dice.enumerated()), id: \.offset) { _, die in
                    LiarsDie(face: die, side: 30, lit: Rules.counts(die, towards: reveal.bid.face),
                             dim: !Rules.counts(die, towards: reveal.bid.face))
                }
            }
            Spacer(minLength: 0)
            if loser {
                Text("−1")
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.error)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(loser ? SR.error.opacity(0.1) : Color.clear)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(who(cup.playerId)): " + cup.dice.map(String.init).joined(separator: ", ") + (loser ? ", loses a die" : ""))
    }

    private func popReveal(_ reveal: Rules.Reveal) {
        if reveal.loserId == context.me {
            callout = reveal.eliminated ? "You're out of dice" : "You lose a die"
            calloutTone = SR.error
        } else if reveal.challengerId == context.me {
            callout = "Caught them!"
            calloutTone = SR.good
        } else if reveal.bid.playerId == context.me {
            callout = "Your bid stood!"
            calloutTone = SR.good
        } else {
            callout = reveal.bidStood ? "The bid stood" : "Caught out!"
            calloutTone = SR.accentDeep
        }
        calloutToken += 1
    }

    // MARK: - Acting

    /// The picker back to the smallest raise (or my favourite face to open).
    private func resetPicker() {
        let preferred = view.myDice.isEmpty ? nil : Rules.favouriteFace(view.myDice)
        if let start = Rules.startingBid(standing: standing, total: view.totalDice, preferred: preferred) {
            quantity = start.quantity
            face = start.face
        }
    }

    private func send(_ action: Rules.Action) {
        guard myTurn, !waiting else { return }
        SRHaptic.tap()
        waiting = true
        context.send(action)
    }
}
