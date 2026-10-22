import SwiftUI
import UIKit

/// One Fireworks room, from lobby to the last bang.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the rule the host picked as the lobby's panel; Start waits for a second
/// player. Play is the table's tokens and fireworks across the top, everyone
/// else's hand face up (tap one to hint them, with the cards the hint would
/// point at lit before it is sent), and my own hand face down — each card
/// saying only what hints have told me. Tap one of mine to play or drop it.
/// The finish is the team's score, the show in a sentence and the fireworks.
struct FireworksScreen: View {
    let roomId: String
    @StateObject private var store: FireworksStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: FireworksStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Fireworks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar(immersive ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(immersive)
            .onAppear { store.open() }
            .onDisappear { store.close() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.open() } else if phase == .background { store.close() }
            }
            .overlay(alignment: .top) {
                if let message = store.message, !immersive { SRBanner(text: message) }
            }
    }

    private var immersive: Bool {
        guard !store.ended, let room = store.room else { return false }
        return FireworksScreenPhase.of(room) == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "fireworks-ended", done: { dismiss() })
        } else if let room = store.room {
            switch FireworksScreenPhase.of(room) {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "fireworks", done: { dismiss() },
                          panel: AnyView(FireworksTableCard(room: room)),
                          startBlocked: room.playing.count < 2)
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "You can see everyone's cards but your own. Hints are how you learn yours.",
                                  id: "fireworks-countdown")
            case .playing:
                FireworksPlaying(room: room, store: store)
            case .finished:
                FireworksFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "fireworks-ended", done: { dismiss() })
            }
        } else {
            ProgressView()
                .tint(SR.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .srPaper()
        }
    }
}

// MARK: - Colours

/// The suits as paint. Fixed in both themes — they are cards on a table —
/// and every card also SAYS its colour, so nobody needs to tell red from green.
enum FireworksPaint {
    static func fill(_ colour: String) -> Color {
        switch colour {
        case "red": return Color(hex: 0xC4473C)
        case "yellow": return Color(hex: 0xE3B22B)
        case "green": return Color(hex: 0x3A8658)
        case "blue": return Color(hex: 0x2F5FA8)
        case "white": return Color(hex: 0xF4EFE4)
        default: return Color(hex: 0x6B4A9B)
        }
    }

    /// Ink that reads on the fill.
    static func ink(_ colour: String) -> Color {
        colour == "yellow" || colour == "white" ? Color(hex: 0x1E1B16) : Color(hex: 0xFBF7EF)
    }

    /// The prism's sheen: every colour at once.
    static var prism: AngularGradient {
        AngularGradient(colors: ["red", "yellow", "green", "blue", "white", "red"].map(fill), center: .center)
    }

    /// A short tag printed on every card.
    static func tag(_ colour: String) -> String {
        colour == FireworksRules.prism ? "PRISM" : colour.uppercased()
    }
}

/// The face of a card, front or back.
struct FireworksCardFace: View {
    /// Nil for a face-down card.
    let colour: String?
    let rank: Int?
    var lit: Bool = false
    var picked: Bool = false
    /// Under a face-down card: what it is known to be.
    var known: String? = nil
    var knownColour: String? = nil

    var body: some View {
        ZStack {
            background
            VStack(spacing: 2) {
                if let colour, let rank {
                    Text("\(rank)")
                        .font(SR.Text.figure(26))
                        .foregroundStyle(FireworksPaint.ink(colour))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(FireworksPaint.tag(colour))
                        .font(SR.Text.label(9))
                        .tracking(0.5)
                        .foregroundStyle(FireworksPaint.ink(colour))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Image(systemName: "sparkle")
                        .font(SR.Text.title())
                        .foregroundStyle(knownColour.map(FireworksPaint.fill) ?? SR.inkGhost)
                        .accessibilityHidden(true)
                    Text(known ?? "?")
                        .font(SR.Text.label(9))
                        .foregroundStyle(SR.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 2)
                }
            }
            .padding(4)
        }
        .aspectRatio(0.7, contentMode: .fit)
        .frame(maxWidth: 72)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(picked ? SR.accent : lit ? SR.accent.opacity(0.9) : SR.ink.opacity(0.22),
                              lineWidth: picked || lit ? 3 : 1)
        )
        .offset(y: picked || lit ? -6 : 0)
        .animation(.snappy(duration: 0.18), value: picked || lit)
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if let colour, rank != nil {
            if colour == FireworksRules.prism {
                shape.fill(FireworksPaint.prism)
            } else {
                shape.fill(FireworksPaint.fill(colour))
            }
        } else {
            shape.fill(SR.paper)
        }
    }
}

// MARK: - Lobby

/// The rule the host picked, in the lobby — and, until two are in, that it needs two.
struct FireworksTableCard: View {
    let room: GameRoom

    private var colours: [String] {
        room.fireworks?.colours ?? (room.difficulty == "hard" ? FireworksRules.baseColours + [FireworksRules.prism] : FireworksRules.baseColours)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(colours, id: \.self) { colour in
                    FireworksCardFace(colour: colour, rank: 5)
                        .frame(width: 34)
                }
            }
            .accessibilityHidden(true)
            Text((room.fireworks?.rule ?? GameDifficulty.label(for: room.difficulty)).uppercased())
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.accent)
                .fixedSize(horizontal: false, vertical: true)
            Text("One team, one show")
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
            Text("Play each colour from 1 to 5 in order. You see everyone's cards but your own, so the team gives hints — a colour or a number — and each hint costs a token. Dropping a card wins one back.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            if room.playing.count < 2 {
                Text("Needs one more player.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityIdentifier("fireworks-needs-two")
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fireworks-table")
    }
}

// MARK: - The table

/// Tokens, misfires, the deck and the score in one row.
struct FireworksCounters: View {
    let state: FireworksState

    var body: some View {
        HStack(spacing: 10) {
            counter("HINTS", "\(state.hints)/\(state.maxHints)", tone: state.hints == 0 ? SR.error : SR.accentInk,
                    spoken: "\(state.hints) of \(state.maxHints) hint tokens", id: "fireworks-hints")
            counter("MISFIRES", "\(state.misfires)/\(state.maxMisfires)",
                    tone: state.misfires + 1 >= state.maxMisfires ? SR.error : SR.ink,
                    spoken: "\(state.misfires) of \(state.maxMisfires) misfires", id: "fireworks-misfires")
            counter("DECK", state.finalTurns.map { "\($0) left" } ?? "\(state.deck)", tone: SR.ink,
                    spoken: state.finalTurns.map { "Deck empty, \($0) turns left" } ?? "\(state.deck) cards to draw",
                    id: "fireworks-deck")
            counter("SCORE", "\(state.score)", tone: SR.accent,
                    spoken: "Score \(state.score) of \(state.maxScore)", id: "fireworks-score")
        }
    }

    private func counter(_ label: String, _ value: String, tone: Color, spoken: String, id: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(SR.Text.label(10))
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(value)
                .font(SR.Text.figure(20))
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier(id)
    }
}

/// One card per colour: the firework's top number, or an empty slot.
struct FireworksStacks: View {
    let state: FireworksState

    var body: some View {
        HStack(spacing: 6) {
            ForEach(state.colours, id: \.self) { colour in
                let top = state.top(colour)
                Group {
                    if top > 0 {
                        FireworksCardFace(colour: colour, rank: top)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(FireworksPaint.fill(colour == FireworksRules.prism ? "blue" : colour).opacity(0.8),
                                          style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            .aspectRatio(0.7, contentMode: .fit)
                            .frame(maxWidth: 72)
                            .overlay(
                                Text(FireworksPaint.tag(colour))
                                    .font(SR.Text.label(9))
                                    .foregroundStyle(SR.inkMuted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .padding(2)
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(FireworksRules.colourName(colour)): \(top == 0 ? "not started" : "up to \(top)")")
                .accessibilityIdentifier("fireworks-stack-\(colour)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fireworks-stacks")
    }
}

/// The turn's clock as a bar. Ticks, not an animation (see `LiarsDiceTurnBar`).
struct FireworksTurnBar: View {
    let room: GameRoom
    @ObservedObject var store: FireworksStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let left = CGFloat(FireworksRules.turnLeft(endsAt: room.phaseEndsAt, turnMs: room.fireworks?.turnMs ?? 75_000,
                                                      now: store.serverNow()))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.line)
                    Capsule()
                        .fill(left < 0.17 ? SR.error : left < 0.34 ? SR.accent : SR.good)
                        .frame(width: geo.size.width * left)
                }
            }
            .frame(height: 5)
        }
        .accessibilityHidden(true)
        .accessibilityIdentifier("fireworks-turn-bar")
    }
}

// MARK: - Playing

struct FireworksPlaying: View {
    let room: GameRoom
    @ObservedObject var store: FireworksStore

    private var state: FireworksState? { room.fireworks }
    private func name(_ id: String) -> String { id == room.meId ? "You" : room.name(of: id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let state {
                    FireworksTurnBar(room: room, store: store)
                    FireworksCounters(state: state)
                    FireworksStacks(state: state)
                    ForEach(store.others) { seat in
                        otherHand(seat, state: state)
                    }
                    if store.hintTarget != nil { hintComposer }
                    if store.seated { myHand(state) }
                    statusLine.frame(maxWidth: .infinity)
                    if !state.log.isEmpty { logCard(state) }
                    if !state.discards.isEmpty { discardsCard(state) }
                    if let rule = state.rule {
                        Text(rule)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("fireworks-rule")
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("fireworks-playing")
        .onChange(of: store.refusal) { _, refusal in
            if let refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FIREWORKS · TURN \((state?.turn ?? 0) + 1) · \(GameDifficulty.label(for: room.difficulty).uppercased())")
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.accent)
            Text(headline)
                .font(SR.Text.display(24))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("fireworks-headline")
            if let left = state?.finalTurns {
                Text(left == 1 ? "The deck is empty: this is the last turn." : "The deck is empty: \(left) turns left.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.error)
                    .accessibilityIdentifier("fireworks-final")
            }
        }
    }

    private var headline: String {
        guard let state else { return "Setting up…" }
        if store.myTurn { return "Your turn" }
        guard let turn = state.turnId else { return "Waiting…" }
        return "\(room.name(of: turn))’s turn"
    }

    // MARK: Everyone else's hands

    private func otherHand(_ seat: FireworksSeat, state: FireworksState) -> some View {
        let targeted = store.hintTarget == seat.id
        let preview = targeted ? store.previewIds : []
        let isTurn = state.turnId == seat.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                GameInitial(name: room.name(of: seat.id), tone: isTurn ? SR.accent : SR.accentInk)
                Text(room.name(of: seat.id))
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                if isTurn {
                    Text("PLAYING")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.accent)
                }
                Spacer(minLength: 4)
                if store.myTurn {
                    Button {
                        store.target(seat.id)
                    } label: {
                        Text(targeted ? "Cancel" : "Hint")
                            .font(SR.Text.bodyMedium(15))
                    }
                    .srButton(targeted ? .regular : .prominent)
                    .disabled(!store.canHint)
                    .accessibilityLabel(targeted ? "Cancel the hint for \(room.name(of: seat.id))" : "Give \(room.name(of: seat.id)) a hint")
                    .accessibilityIdentifier("fireworks-hint-\(seat.id)")
                }
            }
            HStack(alignment: .top, spacing: 6) {
                ForEach(seat.hand) { card in
                    VStack(spacing: 4) {
                        FireworksCardFace(colour: card.colour, rank: card.rank, lit: preview.contains(card.id))
                        Text(FireworksRules.knownText(card.knows, allColours: state.colours))
                            .font(SR.Text.label(9))
                            .foregroundStyle(card.knows?.hinted == true ? SR.accentInk : SR.inkGhost)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spokenOther(card, state: state, lit: preview.contains(card.id)))
                    .accessibilityIdentifier("fireworks-card-\(card.id)")
                }
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fireworks-hand-\(seat.id)")
    }

    private func spokenOther(_ card: FireworksCard, state: FireworksState, lit: Bool) -> String {
        var bits = [FireworksRules.cardText(card)]
        let known = FireworksRules.knownText(card.knows, allColours: state.colours)
        bits.append(known == "Nothing yet" ? "they know nothing about it yet" : "they know: \(known)")
        if lit { bits.append("this hint points at it") }
        return bits.joined(separator: ", ")
    }

    private var hintComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            let target = store.hintTarget.map { room.name(of: $0) } ?? "them"
            SRSectionLabel(text: "Hint for \(target)")
            if store.hintChoices.isEmpty {
                Text("No hint would point at anything in that hand.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                    ForEach(store.hintChoices, id: \.self) { choice in
                        hintChip(choice)
                    }
                }
            }
            Button { store.sendHint() } label: {
                SRButtonLabel(title: sendTitle, icon: "lightbulb.fill", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(store.hint == nil || !store.canHint)
            .accessibilityIdentifier("fireworks-send-hint")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("fireworks-hint-composer")
    }

    private var sendTitle: String {
        guard let hint = store.hint else { return "Pick a colour or a number" }
        let n = store.previewIds.count
        return "Point at \(n == 1 ? "1 card" : "\(n) cards"): \(hint.spoken)"
    }

    private func hintChip(_ choice: FireworksHint) -> some View {
        let on = store.hint == choice
        return Button { store.choose(choice) } label: {
            HStack(spacing: 6) {
                if let c = swatch(choice) {
                    Circle().fill(FireworksPaint.fill(c)).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(SR.ink.opacity(0.3), lineWidth: 1))
                }
                Text(choice.spoken)
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
        .accessibilityLabel("Hint \(choice.spoken)")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("fireworks-choice-\(choiceId(choice))")
    }

    private func swatch(_ choice: FireworksHint) -> String? {
        if case .colour(let c) = choice { return c }
        return nil
    }

    private func choiceId(_ choice: FireworksHint) -> String {
        switch choice {
        case .colour(let c): return c
        case .rank(let r): return "\(r)"
        }
    }

    // MARK: My hand

    private func myHand(_ state: FireworksState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Your cards", trailing: "facing away")
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(store.myHand.enumerated()), id: \.element.id) { index, card in
                    let known = FireworksRules.knownText(card.knows, allColours: state.colours)
                    VStack(spacing: 4) {
                        FireworksCardFace(colour: nil, rank: nil, picked: store.pickedCard == card.id,
                                          known: known, knownColour: card.knows?.colour)
                        if let could = FireworksRules.couldText(card.could) {
                            Text(could)
                                .font(SR.Text.label(9))
                                .foregroundStyle(SR.inkMuted)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .minimumScaleFactor(0.6)
                                .accessibilityIdentifier("fireworks-could-\(index)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { store.pick(card: card.id) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spokenMine(card, index: index, known: known))
                    .accessibilityAddTraits(store.myTurn ? .isButton : [])
                    .accessibilityAddTraits(store.pickedCard == card.id ? .isSelected : [])
                    .accessibilityIdentifier("fireworks-mine-\(index)")
                }
            }
            if store.myTurn {
                HStack(spacing: 10) {
                    Button { store.play() } label: {
                        SRButtonLabel(title: "Play it", icon: "sparkles", fill: true)
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .disabled(!store.canPlay)
                    .accessibilityIdentifier("fireworks-play")
                    Button { store.discard() } label: {
                        SRButtonLabel(title: "Drop it", icon: "arrow.down.to.line", fill: true)
                    }
                    .srButton(.regular)
                    .controlSize(.large)
                    .disabled(store.pickedCard == nil || store.sending)
                    .accessibilityIdentifier("fireworks-discard")
                }
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fireworks-my-hand")
    }

    private func spokenMine(_ card: FireworksCard, index: Int, known: String) -> String {
        var bits = ["Your card \(index + 1)", known == "Nothing yet" ? "nothing known yet" : known]
        if let could = FireworksRules.couldText(card.could) { bits.append(could.lowercased()) }
        if store.pickedCard == card.id { bits.append("picked") }
        return bits.joined(separator: ", ")
    }

    @ViewBuilder
    private var statusLine: some View {
        if let refusal = store.refusal {
            Label(refusal, systemImage: "exclamationmark.circle")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.error)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("fireworks-refusal")
        } else if store.myTurn {
            Text(store.pickedCard != nil
                 ? "Play it onto its firework, or drop it for a hint token."
                 : store.hintTarget != nil ? "Pick what to tell them; the cards it points at light up."
                 : "Tap one of your cards, or Hint somebody.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("fireworks-guide")
        } else if !store.seated {
            Text("You are watching this one.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
        }
    }

    private func logCard(_ state: FireworksState) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "What happened", trailing: GameResults.count(state.log.count, "move", "moves"))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(state.log.suffix(6).reversed().enumerated()), id: \.offset) { _, entry in
                    Text(FireworksRules.logLine(entry, name: name))
                        .font(SR.Text.secondary())
                        .foregroundStyle(entry.kind == .play && entry.ok == false ? SR.error : SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityIdentifier("fireworks-log")
        }
    }

    private func discardsCard(_ state: FireworksState) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Dropped and misfired", trailing: GameResults.count(state.discards.count, "card", "cards"))
            Text(FireworksDiscards.summary(state.discards, colours: state.colours))
                .font(SR.Text.mono())
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SR.cardPadding)
                .srGlassCard(.paper)
                .accessibilityIdentifier("fireworks-discards")
        }
    }
}

/// The discard pile as a line per colour: "Red 1 1 4".
enum FireworksDiscards {
    static func summary(_ cards: [FireworksCard], colours: [String]) -> String {
        colours.compactMap { colour in
            let ranks = cards.filter { $0.colour == colour }.compactMap(\.rank).sorted()
            guard !ranks.isEmpty else { return nil }
            return "\(FireworksRules.colourName(colour)) " + ranks.map(String.init).joined(separator: " ")
        }
        .joined(separator: "\n")
    }
}

// MARK: - Finished

struct FireworksFinished: View {
    let room: GameRoom
    @ObservedObject var store: FireworksStore
    let done: () -> Void

    private var state: FireworksState? { room.fireworks }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Fireworks · \(GameDifficulty.label(for: room.difficulty)) · final",
                             title: FireworksRules.verdict(score: state?.score ?? 0, max: state?.maxScore ?? 25),
                             strap: GameResults.strap(room))

                if let state {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(state.score)")
                            .font(SR.Text.figure(48))
                            .foregroundStyle(SR.accent)
                        Text("of \(state.maxScore)")
                            .font(SR.Text.title())
                            .foregroundStyle(SR.inkMuted)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("The team scored \(state.score) of \(state.maxScore)")
                    .accessibilityIdentifier("fireworks-final-score")

                    Text(FireworksRules.endingLine(state))
                        .font(SR.Text.bodyMedium(16))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("fireworks-outcome")

                    FireworksStacks(state: state)
                }

                GameStandingsCard(
                    room: room,
                    label: "The team",
                    id: "fireworks-standings",
                    detail: { row in standing(row.id)?.left == true ? "left early" : "played to the end" },
                    figure: { row in
                        guard let s = standing(row.id) else { return nil }
                        return (text: "\(s.score)", spoken: "team score \(s.score)")
                    }
                )

                GameFinishedButtons(room: room, store: store, prefix: "fireworks", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("fireworks-finished")
    }

    private func standing(_ id: String) -> FireworksStanding? {
        state?.standings?.first { $0.id == id }
    }
}
