import SwiftUI

/// Pairs on one phone: the grid of cards, whose turn it is, and everyone's pairs.
///
/// The host holds the layout; this view draws the latest `PlayerView`, where a
/// card carries its picture only while it is face up or taken. On my turn a
/// face-down card is a button that sends one flip and waits for the host's
/// answer, so a double tap never turns two cards. The grid sizes its cells
/// from the width it is given — four or five columns of square cards — so it
/// fits a 375-point phone with room to spare.
struct MemoryPairsView: View {
    let context: OfflineGameContext<MemoryPairsRules>
    /// The card I have just tapped, until the host's next view says what it is.
    @State private var pending: Int?
    /// I have told the host my phone is back after being marked away.
    @State private var sentBack = false

    private var view: MemoryPairsRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: kicker, title: title, strap: strap)
                if let line = lastText {
                    Text(line)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("offline-memory-pairs-last")
                }
                grid
                if view.phase == .choosing {
                    turnClock
                }
                seats
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .onAppear { comeBackIfAway() }
        .onChange(of: view) { _, _ in
            pending = nil
            comeBackIfAway()
        }
        .onChange(of: view.last) { _, new in
            guard let new, new.playerId == context.me else { return }
            switch new.kind {
            case .matched: SRHaptic.ok()
            case .missed: SRHaptic.tap()
            case .timedOut: SRHaptic.bad()
            }
        }
        .onChange(of: context.refusal) { _, new in
            if new != nil {
                SRHaptic.bad()
                pending = nil
            }
        }
        .task(id: pending) {
            // A lost answer must not leave the grid locked: give up after a while.
            guard pending != nil else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { pending = nil }
        }
    }

    // MARK: - Words

    /// Whether I hold a seat in this match and am still here.
    private var playing: Bool {
        view.seats.contains { $0.id == context.me && !$0.away }
    }

    private var myTurn: Bool { view.turnPlayer == context.me && playing }

    private var upCount: Int { view.cards.filter(\.up).count }

    private func who(_ id: String) -> String {
        id == context.me ? "You" : context.name(of: id)
    }

    private var kicker: String {
        view.pairsLeft == 1 ? "Pairs · 1 pair left" : "Pairs · \(view.pairsLeft) pairs left"
    }

    private var title: String {
        switch view.phase {
        case .choosing, .showing:
            return view.turnPlayer == context.me ? "Your turn" : "\(context.name(of: view.turnPlayer))'s turn"
        case .finale, .over:
            let names = view.champions.map { who($0) }
            if names.count == 1 { return names[0] == "You" ? "You win" : "\(names[0]) wins" }
            return names.isEmpty ? "Game over" : "A tie"
        }
    }

    /// What to do now, in one sentence.
    private var strap: String? {
        switch view.phase {
        case .finale, .over:
            return "Every pair has been found. Most pairs wins."
        case .showing:
            return myTurn ? "No match. Remember where they are." : "No match. Remember where those two are."
        case .choosing:
            if !playing { return "You are watching this game." }
            guard myTurn else { return "Watch the cards they turn and remember them." }
            return upCount == 0 ? "Tap a card to turn it over." : "Now tap the card you think matches it."
        }
    }

    private var lastText: String? {
        guard let last = view.last else { return nil }
        let name = who(last.playerId)
        switch last.kind {
        case .matched:
            let picture = last.symbol.map { MemoryPairsRules.pictureName($0) } ?? "pictures"
            return "\(name) found a pair: \(picture). " + (last.playerId == context.me ? "Go again." : "They go again.")
        case .missed:
            return last.playerId == context.me ? "You missed." : "\(name) missed."
        case .timedOut:
            return "\(name) ran out of time."
        }
    }

    // MARK: - The grid

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: max(view.columns, 1))
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(view.cards) { card in
                cell(card)
            }
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("offline-memory-pairs-grid")
    }

    private func canFlip(_ card: MemoryPairsRules.Card) -> Bool {
        myTurn && view.phase == .choosing && pending == nil && card.owner == nil && !card.up
    }

    private func cell(_ card: MemoryPairsRules.Card) -> some View {
        Button {
            flip(card)
        } label: {
            MemoryPairsCardFace(card: card, ownerTone: ownerTone(card.owner),
                                pending: pending == card.index, live: canFlip(card))
        }
        .buttonStyle(.plain)
        .disabled(!canFlip(card))
        .accessibilityLabel(label(card))
        .accessibilityHint(canFlip(card) ? "Turns this card over." : "")
        .accessibilityIdentifier("offline-memory-pairs-card-\(card.index)")
    }

    private func ownerTone(_ owner: String?) -> Color? {
        guard let owner, let seat = view.seats.firstIndex(where: { $0.id == owner }) else { return nil }
        return OfflineSeatColour.of(seat)
    }

    private func label(_ card: MemoryPairsRules.Card) -> String {
        let place = "Card \(card.index + 1)"
        guard let symbol = card.symbol else { return "\(place), face down" }
        let picture = MemoryPairsRules.pictureName(symbol)
        if let owner = card.owner {
            return "\(place), \(picture), taken by \(owner == context.me ? "you" : context.name(of: owner))"
        }
        return "\(place), \(picture), face up"
    }

    private var turnClock: some View {
        HStack(spacing: 8) {
            Text(myTurn ? "Your turn ends in" : "Turn ends in")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            OfflineCountdown(clock: context.clock, until: view.turnEndsAt, font: SR.Text.mono(), tone: SR.inkMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-memory-pairs-clock")
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
                    if view.turnPlayer == seat.id && (view.phase == .choosing || view.phase == .showing) {
                        Image(systemName: "arrowtriangle.left.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SR.accent)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 6)
                    if seat.away {
                        Text("left")
                            .font(SR.Text.mono(13))
                            .foregroundStyle(SR.inkMuted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text("\(seat.pairs)")
                        .font(SR.Text.mono(15))
                        .foregroundStyle(SR.ink)
                        .frame(minWidth: 30, alignment: .trailing)
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
        .accessibilityIdentifier("offline-memory-pairs-seats")
    }

    private func seatLabel(_ seat: MemoryPairsRules.Seat) -> String {
        var parts = [seat.id == context.me ? "You" : seat.name]
        parts.append(seat.pairs == 1 ? "1 pair" : "\(seat.pairs) pairs")
        if seat.away { parts.append("left the game") }
        if view.turnPlayer == seat.id && (view.phase == .choosing || view.phase == .showing) {
            parts.append("their turn")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Acting

    /// The host marked me away while my phone was gone; seeing views again
    /// means I am back, so say so once.
    private func comeBackIfAway() {
        guard let seat = view.seats.first(where: { $0.id == context.me }) else { return }
        if seat.away {
            guard !sentBack, view.phase == .choosing || view.phase == .showing else { return }
            sentBack = true
            context.send(.back)
        } else {
            sentBack = false
        }
    }

    private func flip(_ card: MemoryPairsRules.Card) {
        guard canFlip(card) else { return }
        SRHaptic.select()
        pending = card.index
        context.send(.flip(turn: view.turn, index: card.index))
    }
}

/// One square card in the Pairs grid: a dark back while face down, the
/// picture on paper while face up, and a faded picture edged in the taker's
/// colour once the pair is taken. Square, and as wide as its grid column.
struct MemoryPairsCardFace: View {
    let card: MemoryPairsRules.Card
    /// The colour of the seat that took this card, if anyone has.
    let ownerTone: Color?
    /// I have just tapped it and the host has not answered yet.
    let pending: Bool
    /// I may tap it now.
    let live: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            if let symbol = card.symbol {
                shape.fill(card.owner == nil ? SR.paper : SR.surface)
                Image(systemName: MemoryPairsRules.symbolName(symbol))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(OfflineSeatColour.of(symbol))
                    .padding(12)
                    .opacity(card.owner == nil ? 1 : 0.4)
                shape.strokeBorder(ownerTone ?? SR.accent, lineWidth: card.owner == nil ? 2.5 : 2)
                    .opacity(card.owner == nil ? 1 : 0.7)
            } else {
                shape.fill(SR.ink.opacity(pending ? 0.7 : (live ? 1 : 0.85)))
                Image(systemName: "questionmark")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(SR.paper.opacity(0.28))
                    .padding(18)
                if pending {
                    shape.strokeBorder(SR.accent, lineWidth: 2.5)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(shape)
        .animation(SRMotion.settle, value: card)
    }
}
