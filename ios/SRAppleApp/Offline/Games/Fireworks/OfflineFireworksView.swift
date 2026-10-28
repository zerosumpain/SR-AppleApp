import SwiftUI

/// Fireworks on one phone: whose turn and the turn clock, the tokens and the
/// score, the five fireworks, everyone else's cards face up with what their
/// owners know, my own cards face down with what the hints have told me,
/// the hint composer and Play / Drop on my turn, the latest moves and the
/// discards.
///
/// The cards are the online game's `FireworksCardFace` and `FireworksPaint`,
/// and what a card is known to be is the online game's own sentence
/// (`FireworksRules.knownText`), so the offline show looks like the site's.
/// A hint is built in two taps — a player's Hint, then a colour or number —
/// and the cards it would point at light up before it is sent.
struct OfflineFireworksView: View {
    let context: OfflineGameContext<OfflineFireworksRules>
    /// The player a hint is being put together for.
    @State private var target: String?
    @State private var choice: OfflineFireworksRules.HintChoice?
    /// My card picked to play or drop.
    @State private var picked: Int?
    /// An action has gone to the host and its answer has not come back yet.
    @State private var waiting = false

    private typealias Rules = OfflineFireworksRules
    private var view: Rules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SRPageHeader(kicker: kicker, title: title, strap: strap)
                if view.phase == .playing { turnBar }
                counters
                stacks
                if seated {
                    ForEach(others) { seat in otherHand(seat) }
                    if target != nil { hintComposer }
                    if let me = view.seats.first(where: { $0.id == context.me }) { myHand(me) }
                } else {
                    Text("Hands stay hidden from anyone watching, so nobody can be told their cards.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !view.log.isEmpty { logCard }
                if !view.discards.isEmpty { discardsCard }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("offline-fireworks")
        .onChange(of: view) { _, _ in waiting = false }
        .onChange(of: view.turnNumber) { _, _ in
            target = nil
            choice = nil
            picked = nil
            if myTurn { SRHaptic.tap() }
        }
        .onChange(of: view.phase) { _, new in
            guard new == .done else { return }
            if view.ending == .misfires { SRHaptic.bad() } else { SRHaptic.ok() }
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

    private var seated: Bool { view.seats.contains { $0.id == context.me } }

    private var myTurn: Bool { view.phase == .playing && view.turnPlayer == context.me }

    private var canAct: Bool { myTurn && !waiting }

    /// Everyone else at the table, in turn order from me.
    private var others: [Rules.Seat] {
        guard let at = view.seats.firstIndex(where: { $0.id == context.me }) else { return view.seats }
        let count = view.seats.count
        return (1..<max(1, count)).map { view.seats[(at + $0) % count] }
    }

    private func who(_ id: String) -> String { id == context.me ? "You" : context.name(of: id) }

    private var kicker: String {
        "Fireworks · Turn \(view.turnNumber) · \(view.deck) in the deck"
    }

    private var title: String {
        switch view.phase {
        case .playing:
            if myTurn { return "Your turn" }
            guard let turn = view.turnPlayer else { return "Fireworks" }
            return "\(context.name(of: turn))\u{2019}s turn"
        case .done, .over:
            return FireworksRules.verdict(score: view.score, max: Rules.maxScore)
        }
    }

    private var strap: String? {
        if view.phase != .playing { return Rules.endingLine(view.ending, score: view.score) }
        if let left = view.finalTurns {
            return left == 1 ? "The deck is empty: this is the last turn." : "The deck is empty: \(left) turns left."
        }
        if myTurn {
            if picked != nil { return "Play it, or drop it for a hint token." }
            return "Hint a player, or tap one of your cards to play or drop it."
        }
        return "Watch what the others hint — it is about your cards."
    }

    // MARK: - The turn and the tokens

    private var turnBar: some View {
        HStack(spacing: 10) {
            if let turn = view.turnPlayer {
                OfflineInitial(name: context.name(of: turn), size: 28,
                               tone: OfflineSeatColour.of(view.seats.firstIndex { $0.id == turn } ?? 0))
                Text(turn == context.me ? "Your turn" : "\(context.name(of: turn)) is thinking")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 6)
            Image(systemName: "timer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SR.inkSecondary)
                .accessibilityHidden(true)
            OfflineCountdown(clock: context.clock, until: view.turnEndsAt, font: SR.Text.display(22),
                             tone: myTurn ? SR.accent : SR.ink)
                .fixedSize()
        }
        .padding(.horizontal, SR.cardPadding)
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 4)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-fireworks-turn")
    }

    private var counters: some View {
        HStack(spacing: 8) {
            counter("lightbulb.fill", "\(view.hints)/\(Rules.maxHints)", "hints", tone: view.hints == 0 ? SR.error : SR.ink)
            counter("flame.fill", "\(view.misfires)/\(Rules.maxMisfires)", "misfires",
                    tone: view.misfires >= Rules.maxMisfires - 1 ? SR.error : SR.ink)
            counter("sparkles", "\(view.score)/\(Rules.maxScore)", "score", tone: SR.accent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-fireworks-counters")
    }

    private func counter(_ icon: String, _ value: String, _ label: String, tone: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tone)
                    .accessibilityHidden(true)
                Text(value)
                    .font(SR.Text.figure(20))
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(label.uppercased())
                .font(SR.Text.label(10))
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .srGlassCard(.paper)
        .accessibilityLabel("\(label) \(value)")
    }

    // MARK: - The fireworks

    private var stacks: some View {
        HStack(spacing: 6) {
            ForEach(Array(Rules.colours.enumerated()), id: \.offset) { index, colour in
                let top = view.stacks.indices.contains(index) ? view.stacks[index] : 0
                VStack(spacing: 2) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(FireworksPaint.fill(colour).opacity(top > 0 ? 1 : 0.22))
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(SR.ink.opacity(0.22), lineWidth: 1)
                        Text(top > 0 ? "\(top)" : "–")
                            .font(SR.Text.figure(24))
                            .foregroundStyle(top > 0 ? FireworksPaint.ink(colour) : SR.inkMuted)
                    }
                    .aspectRatio(0.8, contentMode: .fit)
                    Text(FireworksPaint.tag(colour))
                        .font(SR.Text.label(9))
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(colour.capitalized) firework: \(top == 0 ? "not started" : "up to \(top)")")
            }
        }
        .accessibilityIdentifier("offline-fireworks-stacks")
    }

    // MARK: - Everyone else's hands

    private func knownText(_ card: Rules.CardView) -> String {
        FireworksRules.knownText(FireworksKnowledge(colours: card.colours, ranks: card.ranks, hinted: card.touched),
                                 allColours: Rules.colours)
    }

    private func otherHand(_ seat: Rules.Seat) -> some View {
        let targeted = target == seat.id
        let lit = targeted ? choice.map { Rules.touched(by: $0, in: seat.hand) } ?? [] : []
        let isTurn = view.turnPlayer == seat.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                OfflineInitial(name: seat.name, size: 26, tone: isTurn ? SR.accent : SR.accentInk)
                Text(seat.name)
                    .font(SR.Text.title())
                    .foregroundStyle(seat.left ? SR.inkMuted : SR.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if seat.left {
                    Text("LEFT")
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                } else if isTurn {
                    Text("PLAYING")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.accent)
                }
                Spacer(minLength: 4)
                if canAct && !seat.left && !seat.hand.isEmpty {
                    Button {
                        SRHaptic.select()
                        picked = nil
                        choice = nil
                        target = targeted ? nil : seat.id
                    } label: {
                        Text(targeted ? "Cancel" : "Hint")
                            .font(SR.Text.bodyMedium(15))
                    }
                    .srButton(targeted ? .regular : .prominent)
                    .disabled(view.hints == 0)
                    .accessibilityLabel(targeted ? "Cancel the hint for \(seat.name)" : "Give \(seat.name) a hint")
                    .accessibilityIdentifier("offline-fireworks-hint-\(seat.id)")
                }
            }
            HStack(alignment: .top, spacing: 6) {
                ForEach(seat.hand) { card in
                    VStack(spacing: 4) {
                        FireworksCardFace(colour: card.colour, rank: card.rank, lit: lit.contains(card.id))
                        Text(knownText(card))
                            .font(SR.Text.label(9))
                            .foregroundStyle(card.touched ? SR.accentInk : SR.inkGhost)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spokenOther(card, lit: lit.contains(card.id)))
                }
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-fireworks-hand-\(seat.id)")
    }

    private func spokenOther(_ card: Rules.CardView, lit: Bool) -> String {
        var bits = [card.colour.map { "\($0.capitalized) \(card.rank ?? 0)" } ?? "A card"]
        let known = knownText(card)
        bits.append(known == "Nothing yet" ? "they know nothing about it yet" : "they know: \(known)")
        if lit { bits.append("this hint points at it") }
        return bits.joined(separator: ", ")
    }

    // MARK: - Hinting

    private var targetSeat: Rules.Seat? { target.flatMap { id in view.seats.first { $0.id == id } } }

    private var hintComposer: some View {
        let hand = targetSeat?.hand ?? []
        let choices = Rules.possibleHintChoices(for: hand)
        return VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Hint for \(targetSeat?.name ?? "them")")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                ForEach(choices, id: \.self) { option in
                    hintChip(option)
                }
            }
            Button { sendHint() } label: {
                SRButtonLabel(title: sendTitle(hand), icon: "lightbulb.fill", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(choice == nil || !canAct || view.hints == 0)
            .accessibilityIdentifier("offline-fireworks-send-hint")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-fireworks-hint-composer")
    }

    private func sendTitle(_ hand: [Rules.CardView]) -> String {
        guard let choice else { return "Pick a colour or a number" }
        let n = Rules.touched(by: choice, in: hand).count
        return "Point at \(n == 1 ? "1 card" : "\(n) cards"): \(choice.spoken)"
    }

    private func swatch(_ option: Rules.HintChoice) -> String? {
        if case .colour(let c) = option { return c }
        return nil
    }

    private func hintChip(_ option: Rules.HintChoice) -> some View {
        let on = choice == option
        return Button {
            SRHaptic.select()
            choice = option
        } label: {
            HStack(spacing: 6) {
                if let c = swatch(option) {
                    Circle()
                        .fill(FireworksPaint.fill(c))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(SR.ink.opacity(0.3), lineWidth: 1))
                }
                Text(option.spoken)
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(on ? SR.paper : SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? SR.accent : SR.paper))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SR.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hint \(option.spoken)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - My hand

    private func myHand(_ me: Rules.Seat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Your cards", trailing: "facing away")
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(me.hand.enumerated()), id: \.element.id) { index, card in
                    FireworksCardFace(colour: nil, rank: nil, picked: picked == card.id,
                                      known: knownText(card), knownColour: card.colours.count == 1 ? card.colours[0] : nil)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { pick(card.id) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Your card \(index + 1), oldest first: \(knownText(card))")
                        .accessibilityAddTraits(canAct ? .isButton : [])
                        .accessibilityAddTraits(picked == card.id ? .isSelected : [])
                        .accessibilityIdentifier("offline-fireworks-mine-\(index)")
                }
            }
            if canAct, let picked {
                HStack(spacing: 10) {
                    Button {
                        send(.play(turn: view.turnNumber, card: picked))
                    } label: {
                        SRButtonLabel(title: "Play", icon: "sparkle", fill: true)
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .accessibilityIdentifier("offline-fireworks-play")
                    Button {
                        send(.discard(turn: view.turnNumber, card: picked))
                    } label: {
                        SRButtonLabel(title: "Drop", icon: "trash", fill: true)
                    }
                    .srButton(.regular)
                    .controlSize(.large)
                    .disabled(view.hints >= Rules.maxHints)
                    .accessibilityLabel(view.hints >= Rules.maxHints ? "Drop — not while every hint token is in" : "Drop for a hint token")
                    .accessibilityIdentifier("offline-fireworks-drop")
                }
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-fireworks-mine")
    }

    // MARK: - What happened

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SRSectionLabel(text: "Lately")
            ForEach(Array(view.log.enumerated().reversed()), id: \.offset) { _, entry in
                Text(Rules.logLine(entry, name: who))
                    .font(SR.Text.secondary())
                    .foregroundStyle(entry.ok == false ? SR.error : SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-fireworks-log")
    }

    private var discardsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SRSectionLabel(text: "Discards", trailing: "\(view.discards.count)")
            ForEach(Rules.colours, id: \.self) { colour in
                let ranks = view.discards.filter { $0.colour == colour }.map(\.rank).sorted()
                if !ranks.isEmpty {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(FireworksPaint.fill(colour))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(SR.ink.opacity(0.3), lineWidth: 1))
                        Text("\(colour.capitalized): " + ranks.map(String.init).joined(separator: " "))
                            .font(SR.Text.mono(13))
                            .foregroundStyle(SR.ink)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-fireworks-discards")
    }

    // MARK: - Acting

    private func pick(_ id: Int) {
        guard canAct else { return }
        SRHaptic.select()
        target = nil
        choice = nil
        picked = picked == id ? nil : id
    }

    private func sendHint() {
        guard let target, let choice else { return }
        switch choice {
        case .colour(let c): send(.hintColour(turn: view.turnNumber, to: target, colour: c))
        case .rank(let r): send(.hintRank(turn: view.turnNumber, to: target, rank: r))
        }
    }

    private func send(_ action: Rules.Action) {
        guard canAct else { return }
        SRHaptic.tap()
        waiting = true
        context.send(action)
    }
}
