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
///
/// The show itself is a night sky: each colour's firework is drawn as a
/// burst that grows with its stack, and when a card is played onto it the
/// burst goes off — a second of sparks, then still again. Hint tokens are a
/// row of blue counters and misfires a row of fuses, so what is left reads
/// without counting.
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
        .onChange(of: view.score) { old, new in
            if new > old { SRHaptic.ok() }
        }
        .onChange(of: view.misfires) { old, new in
            if new > old { SRHaptic.bad() }
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

    private func tone(of id: String) -> Color {
        OfflineSeatColour.of(view.seats.firstIndex { $0.id == id } ?? 0)
    }

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

    @ViewBuilder
    private var turnBar: some View {
        if let turn = view.turnPlayer {
            PlayTableTurnStrip(text: turn == context.me ? "Hint, play or drop" : "\(context.name(of: turn)) is thinking",
                               mine: turn == context.me, clock: context.clock, until: view.turnEndsAt,
                               total: Rules.turnSeconds, tone: tone(of: turn)) {
                OfflineInitial(name: context.name(of: turn), size: 40, tone: tone(of: turn))
            }
            .accessibilityIdentifier("offline-fireworks-turn")
        }
    }

    private var counters: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                counterLabel("Hints", "\(view.hints)/\(Rules.maxHints)", tone: view.hints == 0 ? SR.error : SR.ink)
                OfflineFireworksTokens(filled: view.hints, total: Rules.maxHints)
                counterLabel("Misfires", "\(view.misfires)/\(Rules.maxMisfires)",
                             tone: view.misfires >= Rules.maxMisfires - 1 ? SR.error : SR.ink)
                OfflineFireworksFuses(burnt: view.misfires, total: Rules.maxMisfires)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 2) {
                Text("\(view.score)")
                    .font(SR.Text.hero(40))
                    .foregroundStyle(SR.accent)
                    .srNumeric(Double(view.score))
                Text("OF \(Rules.maxScore)")
                    .font(SR.Text.label(11))
                    .tracking(1)
                    .foregroundStyle(SR.inkMuted)
            }
            .frame(minWidth: 84)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("hints \(view.hints)/\(Rules.maxHints), misfires \(view.misfires)/\(Rules.maxMisfires), score \(view.score)/\(Rules.maxScore)")
        .accessibilityIdentifier("offline-fireworks-counters")
    }

    private func counterLabel(_ label: String, _ value: String, tone: Color) -> some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(SR.Text.label(11))
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
            Text(value)
                .font(SR.Text.mono(13))
                .foregroundStyle(tone)
        }
    }

    // MARK: - The fireworks

    private var stacks: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(Rules.colours.enumerated()), id: \.offset) { index, colour in
                stackColumn(index, colour)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x0B1030), Color(hex: 0x1D1650)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 4)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-fireworks-stacks")
    }

    /// One colour's column: its burst in the sky, its stack card and its tag.
    private func stackColumn(_ index: Int, _ colour: String) -> some View {
        let top: Int = view.stacks.indices.contains(index) ? view.stacks[index] : 0
        let figureTone: Color = top > 0 ? FireworksPaint.ink(colour) : Color.white.opacity(0.6)
        let spoken: String = top == 0 ? "not started" : "up to \(top)"
        return VStack(spacing: 6) {
            OfflineFireworksBurst(colour: colour, level: top, levels: Rules.ranks.count)
                .frame(height: 76)
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(FireworksPaint.fill(colour).opacity(top > 0 ? 1 : 0.22))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                Text(top > 0 ? "\(top)" : "–")
                    .font(SR.Text.figure(22))
                    .foregroundStyle(figureTone)
                    .contentTransition(.numericText())
            }
            .aspectRatio(0.8, contentMode: .fit)
            .srAnimation(.spring(response: 0.3, dampingFraction: 0.6), value: top)
            Text(FireworksPaint.tag(colour))
                .font(SR.Text.label(9))
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(colour.capitalized) firework: \(spoken)")
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
        let seatTone = tone(of: seat.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                OfflineInitial(name: seat.name, size: 32, tone: seatTone)
                    .overlay(Circle().strokeBorder(isTurn ? seatTone : Color.clear, lineWidth: 2.5).padding(-4))
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
                        .foregroundStyle(seatTone)
                }
                Spacer(minLength: 4)
                if canAct && !seat.left && !seat.hand.isEmpty {
                    Button {
                        SRHaptic.select()
                        picked = nil
                        choice = nil
                        target = targeted ? nil : seat.id
                    } label: {
                        Label(targeted ? "Cancel" : "Hint", systemImage: targeted ? "xmark" : "lightbulb.fill")
                            .font(SR.Text.bodyMedium(15))
                            .frame(minHeight: PlayTableMetrics.bigLabel)
                    }
                    .srButton(targeted ? .regular : .prominent)
                    .controlSize(.large)
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
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .fill(isTurn ? seatTone.opacity(0.08) : Color.clear)
        )
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
        return VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Hint for \(targetSeat?.name ?? "them")")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(choices, id: \.self) { option in
                    hintChip(option)
                }
            }
            PlayTableButton(title: sendTitle(hand), icon: "lightbulb.fill") {
                sendHint()
            }
            .disabled(choice == nil || !canAct || view.hints == 0)
            .accessibilityIdentifier("offline-fireworks-send-hint")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
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
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(SR.ink.opacity(0.3), lineWidth: 1))
                }
                Text(option.spoken)
                    .font(SR.Text.title(16))
                    .foregroundStyle(on ? SR.paper : SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: PlayTableMetrics.bigButton)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? SR.accent : SR.paper))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Color.clear : SR.line, lineWidth: 1))
            .scaleEffect(on ? 1.04 : 1)
        }
        .buttonStyle(SRPressStyle())
        .srAnimation(.snappy(duration: 0.18), value: on)
        .accessibilityLabel("Hint \(option.spoken)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - My hand

    private func myHand(_ me: Rules.Seat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    PlayTableButton(title: "Play", icon: "sparkle", haptic: .none) {
                        send(.play(turn: view.turnNumber, card: picked))
                    }
                    .accessibilityIdentifier("offline-fireworks-play")
                    PlayTableButton(title: "Drop", icon: "trash", weight: .regular, haptic: .none) {
                        send(.discard(turn: view.turnNumber, card: picked))
                    }
                    .disabled(view.hints >= Rules.maxHints)
                    .accessibilityLabel(view.hints >= Rules.maxHints ? "Drop — not while every hint token is in" : "Drop for a hint token")
                    .accessibilityIdentifier("offline-fireworks-drop")
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .srAnimation(.snappy(duration: 0.22), value: picked)
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-fireworks-mine")
    }

    // MARK: - What happened

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "Lately")
            ForEach(Array(view.log.enumerated().reversed()), id: \.offset) { index, entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: entry.ok == false ? "flame.fill" : "sparkle")
                        .font(SR.Text.label(12))
                        .foregroundStyle(entry.ok == false ? SR.error : SR.accent)
                        .accessibilityHidden(true)
                    Text(Rules.logLine(entry, name: who))
                        .font(SR.Text.secondary())
                        .foregroundStyle(entry.ok == false ? SR.error : SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(index == view.log.count - 1 ? 1 : 0.8)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-fireworks-log")
    }

    private var discardsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "Discards", trailing: "\(view.discards.count)")
            ForEach(Rules.colours, id: \.self) { colour in
                let ranks = view.discards.filter { $0.colour == colour }.map(\.rank).sorted()
                if !ranks.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(ranks.enumerated()), id: \.offset) { _, rank in
                            Text("\(rank)")
                                .font(SR.Text.label(12))
                                .foregroundStyle(FireworksPaint.ink(colour))
                                .frame(width: 22, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(FireworksPaint.fill(colour))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(SR.ink.opacity(0.2), lineWidth: 1)
                                )
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(colour.capitalized): " + ranks.map(String.init).joined(separator: " "))
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

/// Hint tokens as a row of blue counters: filled ones are still to spend.
struct OfflineFireworksTokens: View {
    let filled: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 0), id: \.self) { index in
                Circle()
                    .fill(index < filled ? Color(hex: 0x2F6FE0) : Color.clear)
                    .overlay(Circle().strokeBorder(Color(hex: 0x2F6FE0).opacity(index < filled ? 0 : 0.5), lineWidth: 1.5))
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(index < filled ? 0.35 : 0))
                            .padding(4)
                            .offset(x: -2, y: -2)
                    )
                    .frame(width: 18, height: 18)
            }
        }
        .srAnimation(.spring(response: 0.3, dampingFraction: 0.6), value: filled)
        .accessibilityHidden(true)
    }
}

/// Misfires as fuses: a burnt one for each misfire.
struct OfflineFireworksFuses: View {
    let burnt: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(total, 0), id: \.self) { index in
                Image(systemName: index < burnt ? "flame.fill" : "flame")
                    .font(SR.Text.title(17))
                    .foregroundStyle(index < burnt ? SR.error : SR.inkGhost)
                    .scaleEffect(index < burnt ? 1.1 : 1)
            }
        }
        .srAnimation(.spring(response: 0.3, dampingFraction: 0.5), value: burnt)
        .accessibilityHidden(true)
    }
}

/// One colour's firework in the night sky: a burst that grows with the
/// stack. When the stack goes up it goes off — sparks flying out for about a
/// second on one animation timeline, which then stops. Still under Reduce
/// Motion.
struct OfflineFireworksBurst: View {
    let colour: String
    let level: Int
    /// The most a stack can reach.
    let levels: Int
    @State private var firedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let burstSeconds: Double = 1.1

    var body: some View {
        let tone = colour == FireworksRules.prism ? Color.white : FireworksPaint.fill(colour)
        let level = self.level
        let levels = self.levels
        let fired = firedAt
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: fired == nil)) { timeline in
            Canvas { context, size in
                let age = fired.map { timeline.date.timeIntervalSince($0) } ?? -1
                OfflineFireworksBurst.paint(in: &context, size: size, tone: tone, level: level, levels: levels, age: age)
            }
        }
        .onChange(of: level) { old, new in
            guard new > old, !reduceMotion else { return }
            firedAt = Date()
        }
        .task(id: firedAt) {
            guard firedAt != nil else { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.burstSeconds * 1_000_000_000))
            if !Task.isCancelled { firedAt = nil }
        }
        .accessibilityHidden(true)
    }

    /// The still burst, and — while `age` is within a burst — sparks flying
    /// out and fading.
    static func paint(in context: inout GraphicsContext, size: CGSize, tone: Color, level: Int, levels: Int, age: Double) {
        let centre = CGPoint(x: size.width / 2, y: size.height * 0.45)
        let reach = min(size.width, size.height) / 2
        guard level > 0 else {
            let r: CGFloat = 2.5
            context.fill(Path(ellipseIn: CGRect(x: centre.x - r, y: size.height - 8, width: r * 2, height: r * 2)),
                         with: .color(tone.opacity(0.5)))
            return
        }
        let strength = CGFloat(level) / CGFloat(max(levels, 1))
        let radius = reach * (0.35 + 0.6 * strength)
        let rays = 6 + level * 2
        var lines = Path()
        for ray in 0..<rays {
            let angle = Double(ray) / Double(rays) * 2 * .pi
            let inner = radius * 0.25
            lines.move(to: CGPoint(x: centre.x + CGFloat(cos(angle)) * inner, y: centre.y + CGFloat(sin(angle)) * inner))
            lines.addLine(to: CGPoint(x: centre.x + CGFloat(cos(angle)) * radius, y: centre.y + CGFloat(sin(angle)) * radius))
        }
        context.stroke(lines, with: .color(tone.opacity(0.85)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        let core = radius * 0.18
        context.fill(Path(ellipseIn: CGRect(x: centre.x - core, y: centre.y - core, width: core * 2, height: core * 2)),
                     with: .color(Color.white.opacity(0.9)))
        guard age >= 0, age < burstSeconds else { return }
        let t = age / burstSeconds
        let fly = CGFloat(t) * reach * 1.1
        let fade = 1 - t
        for spark in 0..<18 {
            let angle = Double(spark) / 18 * 2 * .pi + 0.2
            let drop = CGFloat(t * t) * reach * 0.4
            let point = CGPoint(x: centre.x + CGFloat(cos(angle)) * fly, y: centre.y + CGFloat(sin(angle)) * fly + drop)
            let r: CGFloat = 2.6
            context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                         with: .color(tone.opacity(fade)))
        }
        let flash = radius * CGFloat(0.4 + t)
        context.stroke(Path(ellipseIn: CGRect(x: centre.x - flash, y: centre.y - flash, width: flash * 2, height: flash * 2)),
                       with: .color(Color.white.opacity(0.5 * fade)), lineWidth: 2)
    }
}
