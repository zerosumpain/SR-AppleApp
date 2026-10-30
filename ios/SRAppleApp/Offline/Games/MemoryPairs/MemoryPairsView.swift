import SwiftUI

/// Pairs on one phone: the grid of cards, whose turn it is, and everyone's pairs.
///
/// The host holds the layout; this view draws the latest `PlayerView`, where a
/// card carries its picture only while it is face up or taken. On my turn a
/// face-down card is a button that sends one flip and waits for the host's
/// answer, so a double tap never turns two cards. The grid sizes its cells
/// from the width it is given — four or five columns of square cards — so it
/// fits a 375-point phone with room to spare.
///
/// The overhaul (2026-10-29) laid the grid on a midnight felt, made every
/// card turn over with a real flip (and back again on a miss), edged a taken
/// pair in the taker's colour with their initial, sat the players along the
/// top, and pops "Pair!" with a burst when you find one.
struct MemoryPairsView: View {
    let context: OfflineGameContext<MemoryPairsRules>
    /// The card I have just tapped, until the host's next view says what it is.
    @State private var pending: Int?
    /// I have told the host my phone is back after being marked away.
    @State private var sentBack = false
    @State private var callout = ""
    @State private var calloutTone: Color = SR.accentDeep
    @State private var calloutIcon: String?
    @State private var calloutToken = 0
    @State private var burstToken = 0

    private var view: MemoryPairsRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                banner
                if let line = lastText {
                    NearbyPlayBubble(text: line, icon: lastIcon)
                        .id(line)
                        .transition(.opacity)
                        .accessibilityIdentifier("offline-memory-pairs-last")
                }
                board
                seats
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .overlay {
            ZStack {
                NearbyPlayBurst(token: burstToken)
                NearbyPlayCallout(text: callout, icon: calloutIcon, tone: calloutTone, token: calloutToken, hold: 1.1)
            }
        }
        .onAppear { comeBackIfAway() }
        .onChange(of: view) { _, _ in
            pending = nil
            comeBackIfAway()
        }
        .onChange(of: view.turnPlayer) { _, new in
            if new == context.me && playing { SRHaptic.tap() }
        }
        .onChange(of: view.last) { _, new in
            guard let new else { return }
            react(to: new)
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

    private func seatTone(_ id: String) -> Color {
        OfflineSeatColour.of(view.seats.firstIndex { $0.id == id } ?? 0)
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

    private var lastIcon: String {
        switch view.last?.kind {
        case .matched?: return "checkmark.circle.fill"
        case .timedOut?: return "timer"
        default: return "arrow.uturn.backward.circle.fill"
        }
    }

    // MARK: - The top

    private var bannerMark: NearbyPlayMark {
        switch view.phase {
        case .choosing, .showing: return .person(context.name(of: view.turnPlayer))
        case .finale, .over: return .symbol("trophy.fill")
        }
    }

    private var banner: some View {
        NearbyPlayBanner(kicker: kicker, title: title, strap: strap,
                         mine: myTurn && (view.phase == .choosing || view.phase == .showing),
                         tone: seatTone(view.turnPlayer), mark: bannerMark) {
            bannerClock
        }
    }

    @ViewBuilder
    private var bannerClock: some View {
        switch view.phase {
        case .choosing:
            NearbyPlayBannerClock(clock: context.clock, until: view.turnEndsAt,
                                  total: MemoryPairsRules.turnTime, mine: myTurn)
                .accessibilityIdentifier("offline-memory-pairs-clock")
        case .finale:
            NearbyPlayBannerClock(clock: context.clock, until: view.finaleUntil,
                                  total: MemoryPairsRules.finalePause, mine: false)
                .accessibilityLabel("Results soon")
        case .showing, .over:
            EmptyView()
        }
    }

    // MARK: - The grid

    private var board: some View {
        NearbyPlayFelt(tone: .navy, padding: 12) {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: max(view.columns, 1))
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(view.cards) { card in
                    cell(card)
                }
            }
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
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
                                ownerName: card.owner.map { context.name(of: $0) },
                                pending: pending == card.index, live: canFlip(card))
        }
        .buttonStyle(SRPressStyle())
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

    // MARK: - The players

    private var seats: some View {
        NearbyPlaySeatStrip(seats: stripSeats, onFelt: false, avatar: 38)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .srGlassCard(.paper)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("offline-memory-pairs-seats")
    }

    private var stripSeats: [NearbyPlaySeat] {
        view.seats.enumerated().map { pair -> NearbyPlaySeat in
            let seat = pair.element
            let acting = view.turnPlayer == seat.id && (view.phase == .choosing || view.phase == .showing)
            let champion = (view.phase == .finale || view.phase == .over) && view.champions.contains(seat.id)
            return NearbyPlaySeat(
                id: seat.id, name: seat.name, tone: OfflineSeatColour.of(pair.offset),
                isMe: seat.id == context.me, acting: acting, faded: seat.away,
                badge: "\(seat.pairs)",
                detail: seat.away ? "left" : (seat.pairs == 1 ? "1 pair" : "\(seat.pairs) pairs"),
                mark: champion ? "crown.fill" : nil,
                markTone: SR.warn,
                spoken: seatLabel(seat)
            )
        }
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

    // MARK: - Moments

    private func react(to last: MemoryPairsRules.Last) {
        let mine = last.playerId == context.me
        switch last.kind {
        case .matched:
            if mine {
                SRHaptic.ok()
                burstToken += 1
            }
            pop(mine ? "Pair!" : "\(context.name(of: last.playerId)) found a pair", icon: "sparkles",
                tone: mine ? SR.good : SR.accentDeep)
        case .missed:
            if mine { SRHaptic.tap() }
            pop("No match", icon: "arrow.uturn.backward", tone: SR.inkSecondary)
        case .timedOut:
            if mine { SRHaptic.bad() }
            pop("Time's up", icon: "timer", tone: SR.error)
        }
    }

    private func pop(_ text: String, icon: String?, tone: Color) {
        callout = text
        calloutIcon = icon
        calloutTone = tone
        calloutToken += 1
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

/// One square card in the Pairs grid: a patterned back while face down, the
/// picture on paper while face up, and a faded picture edged in the taker's
/// colour (with their initial) once the pair is taken. It turns over with a
/// flip each way. Square, and as wide as its grid column.
struct MemoryPairsCardFace: View {
    let card: MemoryPairsRules.Card
    /// The colour of the seat that took this card, if anyone has.
    let ownerTone: Color?
    /// The name of whoever took it, for the initial on the corner.
    var ownerName: String? = nil
    /// I have just tapped it and the host has not answered yet.
    let pending: Bool
    /// I may tap it now.
    let live: Bool

    /// The picture last shown, kept while the card turns face down again so
    /// the face does not go blank half way through the flip.
    @State private var shown: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MemoryPairsTurn(angle: card.symbol == nil ? 180 : 0, symbol: card.symbol ?? shown,
                        taken: card.owner != nil, ownerTone: ownerTone, ownerName: ownerName,
                        pending: pending, live: live)
            .aspectRatio(1, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78), value: card.symbol == nil)
            .animation(SRMotion.settle, value: card.owner)
            .onAppear { if let symbol = card.symbol { shown = symbol } }
            .onChange(of: card.symbol) { _, new in
                if let new { shown = new }
            }
    }
}

/// The card's two sides on one turning axis. `angle` 0 is face up, 180 is
/// face down; SwiftUI animates it, and the side that shows flips at 90.
struct MemoryPairsTurn: View, Animatable {
    var angle: Double
    let symbol: Int?
    let taken: Bool
    let ownerTone: Color?
    let ownerName: String?
    let pending: Bool
    let live: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let showingFace = angle < 90
        ZStack {
            front
                .opacity(showingFace ? 1 : 0)
            back
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(showingFace ? 0 : 1)
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var front: some View {
        ZStack {
            shape.fill(Color(hex: 0xFFFDF8))
            if let symbol {
                Image(systemName: MemoryPairsRules.symbolName(symbol))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(OfflineSeatColour.of(symbol))
                    .padding(12)
                    .opacity(taken ? 0.45 : 1)
            }
            shape.strokeBorder(ownerTone ?? SR.accent, lineWidth: taken ? 3 : 2.5)
            if taken, let ownerName {
                OfflineInitial(name: ownerName, size: 20, tone: ownerTone ?? SR.accent)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .shadow(color: (ownerTone ?? Color.black).opacity(taken ? 0.35 : 0.15), radius: taken ? 6 : 3, x: 0, y: 2)
    }

    private var back: some View {
        ZStack {
            shape.fill(LinearGradient(colors: [SR.accent, SR.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { context, size in
                MemoryPairsTurn.lattice(in: &context, size: size)
            }
            .padding(6)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Image(systemName: "questionmark")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.white.opacity(live ? 0.6 : 0.3))
                .padding(20)
            shape.strokeBorder(pending ? NearbyPlayFeltInk.gold : Color.white.opacity(live ? 0.55 : 0.2),
                               lineWidth: pending ? 3 : 1.5)
        }
        .opacity(live || pending ? 1 : 0.82)
        .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
    }

    /// The diamond lattice on a card's back.
    static func lattice(in context: inout GraphicsContext, size: CGSize) {
        let step = max(5, size.width / 5)
        var path = Path()
        var x: CGFloat = -size.height
        while x < size.width + size.height {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x + size.height, y: size.height))
            path.move(to: CGPoint(x: x + size.height, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        context.stroke(path, with: .color(Color.white.opacity(0.18)), lineWidth: max(0.5, size.width * 0.02))
    }
}
