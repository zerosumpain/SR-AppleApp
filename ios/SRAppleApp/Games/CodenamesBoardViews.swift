import SwiftUI

// Codenames' board pieces: the colours, a card, the 5×5 grid, the two teams'
// agents as pips, this turn's clue, and every clue so far. The screen
// (`CodenamesScreen.swift`) puts them together for each phase.
//
// A card shows what this phone was sent and nothing more. Face down to an
// operative it is a plain word. To a spymaster it is tinted by the key —
// lighter while face down, solid once turned — so the two never read alike.
// Turned over, it is its colour for everyone, with the mark of what it was
// (so red and blue never depend on colour alone) and who touched it. A card
// flips as it turns, and the last card turned keeps a ring until the next.

/// The cards' colours. Fixed, the same in both modes: red and blue each hold
/// white type at 5:1 or better (Quiz Night's own red and blue), the
/// bystander is a pale card with dark type, the assassin near black.
enum CodenamesInk {
    static func fill(_ kind: CodenamesKind) -> Color {
        switch kind {
        case .red: return Color(hex: 0xC8283E)
        case .blue: return Color(hex: 0x1E5FC8)
        case .neutral: return Color(hex: 0xD8C9A3)
        case .assassin: return Color(hex: 0x231F1C)
        }
    }

    /// The type on a solid card.
    static func onFill(_ kind: CodenamesKind) -> Color {
        kind == .neutral ? Color(hex: 0x2B2418) : Color.white
    }

    static func team(_ team: CodenamesTeam) -> Color { fill(team == .red ? .red : .blue) }

    /// A face-down card a spymaster holds the key to: the colour, lightly. The
    /// assassin stays dark, so it is the one card nobody can miss.
    static func tint(_ kind: CodenamesKind) -> Color {
        kind == .assassin ? fill(.assassin).opacity(0.82) : fill(kind).opacity(kind == .neutral ? 0.38 : 0.2)
    }

    static func onTint(_ kind: CodenamesKind) -> Color { kind == .assassin ? Color.white : SR.ink }
}

// MARK: - A card

/// One card of the grid.
struct CodenamesCardView: View {
    let card: CodenamesCard
    /// The kind this phone may show: the card's own once turned, else the key's.
    let shown: CodenamesKind?
    /// Lifted by a first tap, waiting for the second.
    var lifted: Bool = false
    /// The last card turned: ringed.
    var last: Bool = false
    /// The toucher's initial, for the stamp on a turned card.
    var stamp: String? = nil
    /// The finish: a card nobody turned fades in under its colour.
    var revealing: Bool = false
    var enabled: Bool = false
    var action: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flip: Double = 0

    private var turned: Bool { !card.faceDown }

    var body: some View {
        Button { action?() } label: { face }
            .buttonStyle(SRPressStyle())
            .disabled(!enabled)
            .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .scaleEffect(lifted && !reduceMotion ? 1.07 : 1)
            .offset(y: lifted && !reduceMotion ? -4 : 0)
            .zIndex(lifted ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: lifted)
            .onChange(of: card.by) { old, new in
                // Turned over: it swings in from edge-on, showing its colour.
                guard old == nil, new != nil, !reduceMotion else { return }
                var start = Transaction()
                start.disablesAnimations = true
                withTransaction(start) { flip = -90 }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { flip = 0 }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spoken)
            .accessibilityHint(enabled ? (lifted ? "Tap again to turn it over" : "Lifts the card") : "")
            .accessibilityAddTraits(enabled ? .isButton : [])
            .accessibilityIdentifier("codenames-card-\(card.i)")
    }

    private var face: some View {
        let shape = RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
        return ZStack(alignment: .topTrailing) {
            shape.fill(background)
            if turned || revealing, let shown {
                Image(systemName: shown.glyph)
                    .font(SR.Text.label(12))
                    .foregroundStyle(ink.opacity(0.8))
                    .padding(4)
                    .accessibilityHidden(true)
            } else if let shown {
                Image(systemName: shown.glyph)
                    .font(SR.Text.label(12))
                    .foregroundStyle((shown == .assassin ? Color.white : CodenamesInk.fill(shown)).opacity(0.75))
                    .padding(4)
                    .accessibilityHidden(true)
            }
            Text(card.word.uppercased())
                .font(SR.Text.title(13))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .strikethrough(turned && shown != nil && !revealing, color: ink.opacity(0.35))
            if let stamp, turned {
                Text(stamp)
                    .font(SR.Text.label(12))
                    .foregroundStyle(ink.opacity(0.85))
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 54)
        .overlay(shape.strokeBorder(border, lineWidth: lifted || last ? 2.5 : 1))
        .shadow(color: lifted ? SR.accent.opacity(0.35) : Color.clear, radius: 8, y: 4)
        .opacity(revealing ? 0.72 : 1)
        .contentShape(shape)
    }

    private var background: Color {
        guard let shown else { return SR.surface }
        if turned || revealing { return CodenamesInk.fill(shown) }
        return CodenamesInk.tint(shown)
    }

    private var ink: Color {
        guard let shown else { return SR.ink }
        if turned || revealing { return CodenamesInk.onFill(shown) }
        return CodenamesInk.onTint(shown)
    }

    private var border: Color {
        if lifted { return SR.accent }
        if last { return SR.warn }
        if shown != nil, turned || revealing { return Color.clear }
        return SR.line
    }

    private var spoken: String {
        var bits = [card.word]
        if turned, let shown { bits.append("turned over, \(shown.spoken)") }
        else if let shown { bits.append(revealing ? "was \(shown.spoken)" : "face down, \(shown.spoken)") }
        else { bits.append("face down") }
        if lifted { bits.append("lifted") }
        if last { bits.append("just turned") }
        return bits.joined(separator: ", ")
    }
}

// MARK: - The grid

/// The 25 cards, five to a row.
struct CodenamesGrid: View {
    let state: CodenamesState
    let room: GameRoom
    var lifted: Int? = nil
    /// The finish: every card's kind shown, the untouched ones fading in.
    var final: Bool = false
    var tap: ((Int) -> Void)? = nil

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 6) {
            ForEach(state.cards) { card in
                CodenamesCardView(
                    card: card,
                    shown: state.shownKind(card.i),
                    lifted: lifted == card.i,
                    last: !final && state.last?.card == card.i,
                    stamp: stamp(card),
                    revealing: final && card.faceDown,
                    enabled: tap != nil && state.canGuess && card.faceDown,
                    action: { tap?(card.i) }
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(final ? "codenames-key" : "codenames-grid")
    }

    /// Who turned a card: their initial, or a clock for co-op's own turn.
    private func stamp(_ card: CodenamesCard) -> String? {
        guard let by = card.by else { return nil }
        if by == CodenamesRules.auto { return "·" }
        return room.name(of: by).first.map { String($0).uppercased() }
    }
}

// MARK: - The teams

/// Both teams across the top: agents as pips (solid while still to find),
/// how many are left, the spymaster, and a ring round the team whose turn it is.
struct CodenamesSidesHeader: View {
    let state: CodenamesState
    let room: GameRoom

    var body: some View {
        HStack(spacing: 10) {
            ForEach(CodenamesTeam.allCases) { team in
                side(team)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("codenames-teams")
    }

    private func side(_ team: CodenamesTeam) -> some View {
        let info = state.side(team)
        let up = state.phase.inPlay && state.turnTeam == team
        let tone = CodenamesInk.team(team)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: team == .red ? CodenamesKind.red.glyph : CodenamesKind.blue.glyph)
                    .font(SR.Text.label(12))
                    .foregroundStyle(tone)
                    .accessibilityHidden(true)
                Text(title(team).uppercased())
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(tone)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(info?.left ?? 0)")
                    .font(SR.Text.figure(22))
                    .foregroundStyle(SR.ink)
                    .srNumeric(Double(info?.left ?? 0))
            }
            pips(info, tone: tone)
            Text(line(team))
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .overlay {
            if up {
                RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                    .strokeBorder(tone, lineWidth: 2.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(team, info: info, up: up))
        .accessibilityIdentifier("codenames-team-\(team.rawValue)")
    }

    private func pips(_ info: CodenamesSide?, tone: Color) -> some View {
        let agents = info?.agents ?? 0
        let left = info?.left ?? 0
        return HStack(spacing: 3) {
            ForEach(0..<max(0, agents), id: \.self) { index in
                Circle()
                    .fill(index < left ? tone : tone.opacity(0.18))
                    .frame(width: 8, height: 8)
            }
        }
        .srAnimation(.snappy, value: left)
        .accessibilityHidden(true)
    }

    private func title(_ team: CodenamesTeam) -> String {
        state.mode == .coop && team == .blue ? "Blue agents" : team.label
    }

    private func line(_ team: CodenamesTeam) -> String {
        if state.mode == .coop && team == .blue { return "One turns itself over each turn" }
        guard let spy = state.spymaster(team) else { return "Left to find" }
        return spy.id == room.meId ? "You give the clues" : "\(spy.name) gives the clues"
    }

    private func spoken(_ team: CodenamesTeam, info: CodenamesSide?, up: Bool) -> String {
        var bits = ["\(title(team)): \(info?.left ?? 0) of \(info?.agents ?? 0) agents left"]
        bits.append(line(team))
        if up { bits.append("their turn") }
        return bits.joined(separator: ". ")
    }
}

// MARK: - The clue

/// This turn's clue, large in its team's colour, with the guesses left.
struct CodenamesClueBanner: View {
    let clue: CodenamesClue
    let state: CodenamesState
    let room: GameRoom

    var body: some View {
        let tone = CodenamesInk.team(clue.team)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(clue.team.label)’s clue · from \(clue.by == room.meId ? "you" : room.name(of: clue.by))".uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(CodenamesRules.clueText(clue))
                    .font(SR.Text.hero(30))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityIdentifier("codenames-clue-word")
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(state.guessesLeft)")
                    .font(SR.Text.figure(30))
                    .foregroundStyle(Color.white)
                    .srNumeric(Double(state.guessesLeft))
                Text(state.guessesLeft == 1 ? "GUESS LEFT" : "GUESSES LEFT")
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(Color.white.opacity(0.88))
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .fill(tone)
                .shadow(color: tone.opacity(0.3), radius: 10, y: 5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clue.team.label)’s clue: \(clue.word), \(clue.count). \(CodenamesRules.guessesLine(state.guessesLeft)).")
        .accessibilityIdentifier("codenames-clue")
    }
}

/// Every clue so far, newest first: the team, the word and number, who gave
/// it, and the cards turned on it in their colours.
struct CodenamesClueHistory: View {
    let state: CodenamesState
    let room: GameRoom

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Clues", trailing: GameResults.count(state.clues.count, "clue", "clues"))
            VStack(spacing: 0) {
                ForEach(Array(state.clues.reversed().enumerated()), id: \.element.id) { index, clue in
                    if index > 0 { Divider().overlay(SR.divider) }
                    row(clue)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("codenames-history")
    }

    private func row(_ clue: CodenamesClue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(CodenamesInk.team(clue.team))
                .frame(width: 10, height: 10)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(CodenamesRules.clueText(clue))
                        .font(SR.Text.title(15))
                        .foregroundStyle(SR.ink)
                    Text(clue.by == room.meId ? "you" : room.name(of: clue.by))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(1)
                }
                if clue.cards.isEmpty {
                    Text("Nothing turned yet")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                } else {
                    turned(clue.cards)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func turned(_ cards: [Int]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 4, alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(cards, id: \.self) { i in
                let card = state.cards.first { $0.i == i }
                let kind = state.shownKind(i) ?? .neutral
                Text((card?.word ?? "?").uppercased())
                    .font(SR.Text.label(12))
                    .foregroundStyle(CodenamesInk.onFill(kind))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(CodenamesInk.fill(kind)))
                    .accessibilityLabel("\(card?.word ?? "a card"), \(kind.spoken)")
            }
        }
    }
}
