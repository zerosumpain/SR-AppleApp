import SwiftUI
import UIKit

/// One One Clue room, from lobby to the team's score.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with what the game is — drawn as the word card and its sticky-note clues,
/// with the three rules — as the lobby's panel; Start waits for three. Each
/// card is a page per phase, under the same header: which card, a badge for
/// what I am on it (guessing, giving a clue, watching), the team's score, the
/// clock and a row of ten pips:
/// - clues: a clue-giver sees the word on a card that flips in, and one big
///   field for one word with Lock in beside it; the guesser sees a face-down
///   card and a note for every clue locked so far;
/// - review: the clue-givers see every clue as the server judged it and tap
///   another's to veto it, with Done at the foot of the screen; the guesser waits;
/// - guess: the guesser sees the surviving clues as sticky notes and guesses
///   or passes;
/// - reveal: everyone sees the word, stamped with how it went, the guess and
///   every clue, cancelled ones included.
/// The finish is the team's score inside a dial of ten, our best on this
/// phone, the table and every card.
struct OneClueScreen: View {
    let roomId: String
    @StateObject private var store: OneClueStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: OneClueStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("One Clue")
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
        return OneClueRules.phase(room) == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "oneclue-ended", done: { dismiss() })
        } else if let room = store.room {
            switch OneClueRules.phase(room) {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "oneclue", done: { dismiss() },
                          panel: AnyView(OneClueTableCard(room: room)),
                          startBlocked: room.playing.count < (room.oneClue?.minPlayers ?? 3))
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "One word each. Matching clues cancel out, so think different.",
                                  id: "oneclue-countdown")
            case .clues:
                OneClueWriting(room: room, store: store)
            case .review:
                OneClueReview(room: room, store: store)
            case .guess:
                OneClueGuessing(room: room, store: store)
            case .reveal:
                OneClueReveal(room: room, store: store)
            case .finished:
                OneClueFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "oneclue-ended", done: { dismiss() })
            }
        } else {
            VStack(spacing: 18) {
                OneClueTableArt()
                    .frame(width: 150, height: 104)
                HStack(spacing: 10) {
                    ProgressView().tint(SR.accent)
                    Text("Dealing the cards…")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .srPaper()
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Palette

/// One Clue's own colours. The sticky notes are fixed pastels with fixed dark
/// type, the same in both modes — paper notes, not glass — every pair well
/// past 7:1.
enum OneClueInk {
    static let noteHexes: [UInt32] = [0xFFE58A, 0xFFC9D6, 0xC2F0D8, 0xC7E4FF, 0xE0D2FF, 0xFFD9B0]
    static let noteType = Color(hex: 0x2A2340)

    static func note(_ index: Int) -> Color {
        Color(hex: noteHexes[((index % noteHexes.count) + noteHexes.count) % noteHexes.count])
    }

    /// The word card's face.
    static var card: Color { SR.accentInk }
}

/// A sticky note with a clue on it, tilted a touch.
struct OneClueStickyNote: View {
    let text: String
    var author: String? = nil
    let index: Int
    var big: Bool = true

    var body: some View {
        VStack(spacing: 4) {
            Text(text)
                .font(big ? SR.Text.display(24) : SR.Text.title(16))
                .foregroundStyle(OneClueInk.noteType)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let author {
                Text(author.uppercased())
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(OneClueInk.noteType.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, big ? 14 : 8)
        .frame(maxWidth: .infinity, minHeight: big ? 84 : 44)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(OneClueInk.note(index))
                .shadow(color: Color.black.opacity(0.14), radius: 4, x: 0, y: 3)
        )
        .overlay(alignment: .top) {
            // The strip of tape.
            Rectangle()
                .fill(Color.white.opacity(0.55))
                .frame(width: big ? 34 : 22, height: big ? 10 : 7)
                .rotationEffect(.degrees(-4))
                .offset(y: big ? -5 : -3)
        }
        .rotationEffect(.degrees(PartyRoomMaths.tilt(index, spread: big ? 2.2 : 3)))
    }
}

// MARK: - Lobby

/// What the game is, in the lobby — and, until three are in, that it needs three.
struct OneClueTableCard: View {
    let room: GameRoom

    var body: some View {
        let state = room.oneClue
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                OneClueTableArt()
                    .frame(width: 112, height: 80)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(state?.cardCount ?? 10) CARDS · A TEAM GAME")
                        .font(SR.Text.label())
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(SR.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("One word each")
                        .font(SR.Text.display(22))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 10) {
                OneClueRuleLine(icon: "eye.slash.fill", text: "Take turns to guess. Everyone else sees the word.")
                OneClueRuleLine(icon: "text.bubble.fill", text: "Each writes one clue; clues that match cancel out, so think different.")
                OneClueRuleLine(icon: "person.3.fill", text: "Score as many of the ten as you can, together.")
            }
            if let line = OneClueRules.lobbyLine(playing: room.playing.count, min: state?.minPlayers ?? 3,
                                                 max: state?.maxPlayers ?? 7) {
                Label(line, systemImage: "person.badge.plus")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("oneclue-needs-three")
            }
        }
        .padding(SR.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("oneclue-table")
    }
}

/// One rule in the lobby: an icon in a soft disc and a sentence.
struct OneClueRuleLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(SR.Text.title(14))
                .foregroundStyle(SR.accentInk)
                .frame(width: 32, height: 32)
                .background(Circle().fill(SR.accentInk.opacity(0.12)))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }
}

/// The game, drawn: a word card in the middle and three clue notes round it.
struct OneClueTableArt: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: h * 0.12, style: .continuous)
                    .fill(OneClueInk.card)
                    .frame(width: w * 0.44, height: h * 0.62)
                    .overlay(
                        Text("?")
                            .font(SR.Text.hero(h * 0.34))
                            .foregroundStyle(SR.paper)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                    )
                    .shadow(color: OneClueInk.card.opacity(0.35), radius: 5, y: 3)
                note(0, w: w * 0.3, h: h * 0.26).offset(x: -w * 0.33, y: -h * 0.28)
                note(1, w: w * 0.3, h: h * 0.26).offset(x: w * 0.34, y: -h * 0.18)
                note(2, w: w * 0.3, h: h * 0.26).offset(x: w * 0.02, y: h * 0.36)
            }
            .frame(width: w, height: h)
        }
        .accessibilityHidden(true)
    }

    private func note(_ index: Int, w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: h * 0.14) {
            Capsule().fill(OneClueInk.noteType.opacity(0.45)).frame(width: w * 0.6, height: max(2, h * 0.1))
            Capsule().fill(OneClueInk.noteType.opacity(0.25)).frame(width: w * 0.4, height: max(2, h * 0.1))
        }
        .frame(width: w, height: h)
        .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(OneClueInk.note(index)))
        .shadow(color: Color.black.opacity(0.14), radius: 2, y: 2)
        .rotationEffect(.degrees(PartyRoomMaths.tilt(index, spread: 6)))
    }
}

// MARK: - The header every card shares

/// Which card, what I am on it, the team's score, the clock, and the row of ten.
struct OneClueHeader: View {
    let room: GameRoom
    @ObservedObject var store: OneClueStore
    let title: String
    let timerId: String

    var body: some View {
        let state = room.oneClue
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    // The team's score sits by the clock, so the kicker is just the card.
                    Text((state.map(OneClueRules.cardLine) ?? "One Clue").uppercased())
                        .font(SR.Text.label())
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(SR.accent)
                        .accessibilityLabel("\(state.map(OneClueRules.cardLine) ?? "One Clue"), team score \(state?.score ?? 0)")
                        .accessibilityIdentifier("oneclue-card-line")
                    Text(title)
                        .font(SR.Text.display(22))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("oneclue-headline")
                    OneClueRoleBadge(role: role)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    WordleTimer(room: room, store: store, id: timerId)
                    if let state {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(state.score)")
                                .font(SR.Text.figure(22))
                                .foregroundStyle(SR.good)
                                .srNumeric(Double(state.score))
                            Text("TEAM")
                                .font(SR.Text.label())
                                .foregroundStyle(SR.inkMuted)
                        }
                        .accessibilityHidden(true)
                    }
                }
            }
            if let state {
                OneCluePips(state: state)
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private var role: OneClueRole {
        if store.amGuesser { return .guesser }
        if store.amGiver { return .clue }
        return .watching
    }
}

/// What I am on this card, as a coloured badge.
struct OneClueRoleBadge: View {
    let role: OneClueRole

    var body: some View {
        Label(text, systemImage: icon)
            .font(SR.Text.label())
            .tracking(1)
            .foregroundStyle(SR.paper)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tone))
            .accessibilityLabel(spoken)
            .accessibilityIdentifier("oneclue-role")
    }

    private var text: String {
        switch role {
        case .guesser: return "YOU'RE GUESSING"
        case .clue: return "CLUE-GIVER"
        case .watching, .unknown: return "WATCHING"
        }
    }

    private var spoken: String {
        switch role {
        case .guesser: return "You're the guesser on this card"
        case .clue: return "You're a clue-giver on this card"
        case .watching, .unknown: return "You're watching this card"
        }
    }

    private var icon: String {
        switch role {
        case .guesser: return "magnifyingglass"
        case .clue: return "pencil"
        case .watching, .unknown: return "eye"
        }
    }

    private var tone: Color {
        switch role {
        case .guesser: return SR.accentDeep
        case .clue: return SR.accentInk
        case .watching, .unknown: return SR.inkSecondary
        }
    }
}

/// Ten pips: filled for a card won, crossed for one lost, dashed for one
/// discarded, ringed (and a touch bigger) for the one in play. Shape as well
/// as colour.
struct OneCluePips: View {
    let state: OneClueState

    var body: some View {
        let pips = OneClueRules.pips(state)
        // Ten at 24pt fit a 375pt phone inside the header card; a longer game
        // shrinks them rather than running off the edge.
        let side: CGFloat = pips.count > 10 ? max(14, 240 / CGFloat(pips.count)) : 24
        let gap: CGFloat = pips.count > 10 ? 3 : 5
        HStack(spacing: gap) {
            ForEach(Array(pips.enumerated()), id: \.offset) { _, pip in
                OneCluePipDot(pip: pip, side: side)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(pips))
        .accessibilityIdentifier("oneclue-pips")
    }

    private func spoken(_ pips: [OneCluePip]) -> String {
        let won = pips.filter { $0 == .won }.count
        let lost = pips.filter { $0 == .lost }.count
        let discarded = pips.filter { $0 == .discarded }.count
        var parts = ["\(won) won", "\(lost) lost"]
        if discarded > 0 { parts.append("\(discarded) discarded") }
        return parts.joined(separator: ", ")
    }
}

/// One pip.
struct OneCluePipDot: View {
    let pip: OneCluePip
    var side: CGFloat = 22

    var body: some View {
        ZStack {
            switch pip {
            case .won:
                Circle().fill(SR.good)
                Image(systemName: "checkmark").font(.system(size: side * 0.45, weight: .heavy)).foregroundStyle(SR.paper)
            case .lost:
                Circle().fill(SR.ink.opacity(0.16))
                Image(systemName: "xmark").font(.system(size: side * 0.42, weight: .heavy)).foregroundStyle(SR.inkMuted)
            case .discarded:
                Circle().strokeBorder(SR.inkMuted, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
            case .current:
                Circle().fill(SR.accent.opacity(0.16))
                Circle().strokeBorder(SR.accent, lineWidth: 2.5)
            case .toCome:
                Circle().strokeBorder(SR.line, lineWidth: 1.5)
            }
        }
        .frame(width: side, height: side)
        .scaleEffect(pip == .current ? 1.15 : 1)
    }
}

/// The secret word, big, on a playing card that flips in the first time it
/// is shown.
struct OneClueWordCard: View {
    let word: String
    var kicker: String = "THE WORD"
    /// Flips in on appearing: the deal and the reveal. Elsewhere it is simply there.
    var flips: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flipped = false

    var body: some View {
        VStack(spacing: 6) {
            Text(kicker)
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.paper.opacity(0.85))
            Text(word.uppercased())
                .font(SR.Text.hero(42))
                .foregroundStyle(SR.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, SR.cardPadding)
        .background(face)
        .rotation3DEffect(.degrees(flipped || reduceMotion || !flips ? 0 : 88), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .opacity(flipped || reduceMotion || !flips ? 1 : 0)
        .onAppear {
            guard !flipped else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.78)) { flipped = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The word is \(word)")
        .accessibilityIdentifier("oneclue-word")
    }

    private var face: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [OneClueInk.card.opacity(0.86), OneClueInk.card],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .padding(8)
            VStack {
                HStack {
                    Image(systemName: "text.bubble.fill")
                    Spacer()
                    Image(systemName: "text.bubble.fill")
                }
                Spacer()
                HStack {
                    Image(systemName: "text.bubble.fill")
                    Spacer()
                    Image(systemName: "text.bubble.fill")
                }
            }
            .font(SR.Text.label(12))
            .foregroundStyle(Color.white.opacity(0.4))
            .padding(16)
            .accessibilityHidden(true)
        }
        .shadow(color: OneClueInk.card.opacity(0.3), radius: 8, y: 4)
    }
}

/// The guesser's card while the others write: face down, a pattern and a
/// question mark.
struct OneClueHiddenCard: View {
    let line: String

    var body: some View {
        VStack(spacing: 8) {
            Text("?")
                .font(SR.Text.hero(52))
                .foregroundStyle(SR.cream)
            Text(line)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.cream.opacity(0.92))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, SR.cardPadding)
        .background(OneClueCardBack())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("oneclue-hidden")
    }
}

/// A card's back: the band's indigo with a lattice of small diamonds, drawn
/// once in a Canvas.
struct OneClueCardBack: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(SR.band)
            Canvas { context, size in
                let step: CGFloat = 18
                let r: CGFloat = 3.2
                let tint = GraphicsContext.Shading.color(Color.white.opacity(0.08))
                var y: CGFloat = 0
                var row = 0
                while y < size.height + step {
                    var x: CGFloat = row % 2 == 0 ? 0 : step / 2
                    while x < size.width + step {
                        var diamond = Path()
                        diamond.move(to: CGPoint(x: x, y: y - r))
                        diamond.addLine(to: CGPoint(x: x + r, y: y))
                        diamond.addLine(to: CGPoint(x: x, y: y + r))
                        diamond.addLine(to: CGPoint(x: x - r, y: y))
                        diamond.closeSubpath()
                        context.fill(diamond, with: tint)
                        x += step
                    }
                    y += step / 2
                    row += 1
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1.5)
                .padding(8)
        }
        .accessibilityHidden(true)
    }
}

/// Who the table is waiting on: a face for each, and the sentence.
struct OneClueWaiting: View {
    let room: GameRoom
    let label: String

    var body: some View {
        let waiting = OneClueRules.waitingOn(room)
        let tones = SR.PersonHue.assign(room.players.map(\.id))
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: label)
            if waiting.isEmpty {
                Label("Everyone's ready.", systemImage: "checkmark.circle.fill")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.good)
            } else {
                HStack(spacing: 10) {
                    HStack(spacing: -8) {
                        ForEach(waiting.prefix(5)) { player in
                            GameInitial(name: player.id == room.meId ? "You" : player.name,
                                        tone: tones[player.id] ?? SR.accentInk, side: 32)
                                .overlay(Circle().strokeBorder(SR.paper, lineWidth: 2))
                        }
                    }
                    Text("Waiting on \(OneClueRules.names(waiting, me: room.meId)).")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLine(waiting))
        .accessibilityIdentifier("oneclue-waiting")
    }

    private func spokenLine(_ players: [GamePlayer]) -> String {
        players.isEmpty ? "\(label). Everyone's ready." : "\(label). Waiting on \(OneClueRules.names(players, me: room.meId))."
    }
}

/// One clue, as judged: who wrote it, the text (struck through when
/// cancelled), its tag and vetoes. A button when I may veto it.
struct OneClueClueRow: View {
    let clue: OneClueClue
    let room: GameRoom
    var onTap: (() -> Void)? = nil

    var body: some View {
        let canVeto = OneClueRules.canVeto(clue, room: room)
        let isMe = clue.playerId == room.meId
        let traits: AccessibilityTraits = !canVeto ? [] : clue.vetoed ? [.isButton, .isSelected] : .isButton
        Button {
            onTap?()
        } label: {
            label(canVeto: canVeto, isMe: isMe)
        }
        .buttonStyle(SRPressStyle())
        .disabled(!canVeto || onTap == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(isMe: isMe))
        .accessibilityHint(canVeto ? (clue.vetoed ? "Takes your veto back" : "Vetoes it") : "")
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier("oneclue-clue-\(clue.playerId)")
    }

    private var cancelled: Bool { !clue.status.survives && clue.status != .unknown }

    private func label(canVeto: Bool, isMe: Bool) -> some View {
        let tone = SR.PersonHue.assign(room.players.map(\.id))[clue.playerId] ?? SR.accentInk
        return HStack(alignment: .center, spacing: 10) {
            GameInitial(name: isMe ? "You" : room.name(of: clue.playerId), tone: isMe ? SR.accent : tone, side: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(clue.text.isEmpty ? "—" : clue.text)
                    .font(SR.Text.title(18))
                    .foregroundStyle(cancelled || clue.text.isEmpty ? SR.inkMuted : SR.ink)
                    .strikethrough(cancelled && !clue.text.isEmpty, color: clue.status == .vetoed ? SR.error : SR.inkMuted)
                    .lineLimit(2)
                tags
            }
            Spacer(minLength: 8)
            if canVeto {
                vetoChip
            } else if clue.status.survives {
                Image(systemName: "checkmark.circle.fill")
                    .font(SR.Text.title(18))
                    .foregroundStyle(SR.good)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 56)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(clue.vetoed ? SR.error.opacity(0.08) : Color.clear))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var tags: some View {
        let line = OneClueRules.vetoLine(clue)
        if clue.status.tag != nil || line != nil {
            HStack(spacing: 6) {
                if let tag = clue.status.tag {
                    Text(tag)
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(clue.status == .vetoed ? SR.error : SR.inkMuted)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(clue.status == .vetoed ? SR.error : SR.line, lineWidth: 1))
                }
                if let line {
                    Text(line)
                        .font(SR.Text.mono())
                        .foregroundStyle(clue.status == .vetoed ? SR.error : SR.warn)
                }
            }
        }
    }

    /// The veto, as something that looks pressable.
    private var vetoChip: some View {
        HStack(spacing: 4) {
            Image(systemName: clue.vetoed ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            Text(clue.vetoed ? "VETOED" : "VETO")
                .tracking(0.8)
        }
        .font(SR.Text.label())
        .foregroundStyle(clue.vetoed ? SR.paper : SR.error)
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(Capsule().fill(clue.vetoed ? SR.error : SR.error.opacity(0.1)))
        .overlay(Capsule().strokeBorder(SR.error.opacity(clue.vetoed ? 0 : 0.5), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private func spoken(isMe: Bool) -> String {
        let who = isMe ? "You" : room.name(of: clue.playerId)
        guard !clue.text.isEmpty else { return "\(who), no clue" }
        var parts = ["\(who), \(clue.text)"]
        let status = clue.status.spoken
        if !status.isEmpty, clue.status != .ok { parts.append(status) }
        if let line = OneClueRules.vetoLine(clue) { parts.append(line) }
        if clue.vetoed { parts.append("you vetoed it") }
        return parts.joined(separator: ", ")
    }
}

/// A list of clues in a card.
struct OneClueClueList: View {
    let clues: [OneClueClue]
    let room: GameRoom
    var store: OneClueStore? = nil
    let id: String

    var body: some View {
        VStack(spacing: 0) {
            if clues.isEmpty {
                Text("No clues on this card.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            }
            ForEach(Array(clues.enumerated()), id: \.element.id) { index, clue in
                if index > 0 { Divider().overlay(SR.divider) }
                OneClueClueRow(clue: clue, room: room, onTap: store.map { s -> () -> Void in { s.toggleVeto(clue) } })
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}

/// The foot of a page, always in reach: one big action or who it waits on.
struct OneClueFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .srGlassCard(.paper)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
    }
}

// MARK: - Clues

struct OneClueWriting: View {
    let room: GameRoom
    @ObservedObject var store: OneClueStore
    @FocusState private var focused: Bool

    var body: some View {
        let state = room.oneClue
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap - 4) {
                OneClueHeader(room: room, store: store,
                              title: store.amGuesser ? "You're guessing" : "Write one clue",
                              timerId: "oneclue-timer")
                if store.amGiver, let word = state?.word {
                    OneClueWordCard(word: word)
                    composer
                } else if store.amGuesser {
                    OneClueHiddenCard(line: "Everyone else can see the word and is writing one clue for you. No peeking needed.")
                    if let state { lockedNotes(state) }
                } else {
                    Label("You are not playing in this one.", systemImage: "eye")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }
                OneClueWaiting(room: room, label: "Clues")
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .srGround(.warm)
        .accessibilityIdentifier("oneclue-clues")
        .onChange(of: focused) { was, _ in
            if was { store.commit() }
        }
        .srAnimation(.snappy, value: store.locked)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("One word", text: Binding(get: { store.draft }, set: { store.edit($0) }))
                .font(SR.Text.title(22))
                .foregroundStyle(SR.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(false)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { store.lockIn() }
                .disabled(!store.canClue)
                .padding(.horizontal, 16)
                .frame(minHeight: 60)
                .background(
                    RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 2, style: .continuous)
                        .fill(SR.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 2, style: .continuous)
                        .strokeBorder(fieldStroke, lineWidth: focused || store.locked ? 2 : 1)
                )
                .accessibilityLabel("Your clue")
                .accessibilityIdentifier("oneclue-clue-field")
            if let warning = store.warning {
                Label(warning, systemImage: "exclamationmark.circle")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("oneclue-warning")
            }
            if store.locked {
                lockedCard
            } else {
                Button { store.lockIn() } label: {
                    SRButtonLabel(title: "Lock in my clue", icon: "lock.fill", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(!store.canLock)
                .accessibilityIdentifier("oneclue-lock")
            }
            Text("Take your time: the clues open once everyone has locked one in. If the clock runs out, what you've written still counts. If anyone writes the same clue as you, both cancel out, so think different.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private var fieldStroke: Color {
        if store.locked { return SR.good }
        if store.warning != nil { return SR.warn }
        if focused { return SR.accent }
        return SR.line
    }

    private var lockedCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(SR.Text.title(16))
                .foregroundStyle(SR.paper)
                .frame(width: 40, height: 40)
                .background(Circle().fill(SR.good))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Locked in")
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                Text("Change it any time before the clues open.")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).fill(SR.good.opacity(0.12)))
        .transition(.scale(scale: 0.94).combined(with: .opacity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locked in. Change it any time before the clues open.")
        .accessibilityIdentifier("oneclue-locked")
    }

    /// For the guesser: a face-down note for every clue-giver, turned blank
    /// side up once they have locked one in.
    private func lockedNotes(_ state: OneClueState) -> some View {
        let givers = state.seats.filter { $0.role == .clue }
        let ready = givers.filter(\.submitted).count
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Clues coming", trailing: "\(ready) of \(givers.count) locked")
            HStack(spacing: 10) {
                ForEach(Array(givers.enumerated()), id: \.element.id) { index, seat in
                    noteSlot(index: index, done: seat.submitted)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ready) of \(givers.count) clues locked in")
        .accessibilityIdentifier("oneclue-coming")
    }

    private func noteSlot(index: Int, done: Bool) -> some View {
        ZStack {
            if done {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(OneClueInk.note(index))
                    .shadow(color: Color.black.opacity(0.12), radius: 2, y: 2)
                Image(systemName: "lock.fill")
                    .font(SR.Text.label(13))
                    .foregroundStyle(OneClueInk.noteType.opacity(0.7))
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(SR.line, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .frame(width: 44, height: 44)
        .rotationEffect(.degrees(PartyRoomMaths.tilt(index, spread: 3)))
        .srAnimation(.spring(response: 0.35, dampingFraction: 0.6), value: done)
    }
}

// MARK: - Review

struct OneClueReview: View {
    let room: GameRoom
    @ObservedObject var store: OneClueStore

    var body: some View {
        let state = room.oneClue
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap - 4) {
                OneClueHeader(room: room, store: store,
                              title: store.amGiver ? "Any too close?" : "Checking the clues",
                              timerId: "oneclue-review-timer")
                if store.amGiver {
                    if let word = state?.word { OneClueWordCard(word: word, flips: false) }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "hand.thumbsdown.fill")
                            .font(SR.Text.title(16))
                            .foregroundStyle(SR.error)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(SR.error.opacity(0.12)))
                            .accessibilityHidden(true)
                        Text("Matching clues and ones too like the word are already out. Tap somebody else's clue to veto it if it gives too much away; half the others vetoing strikes it.")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    OneClueClueList(clues: state?.clues ?? [], room: room, store: store, id: "oneclue-review-list")
                } else {
                    OneClueHiddenCard(line: "The others are checking their clues. Yours are on the way.")
                    OneClueWaiting(room: room, label: "Review")
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.amGiver {
                OneClueFooter {
                    if store.meDone {
                        OneClueWaiting(room: room, label: "Review")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Button { store.ready() } label: {
                            SRButtonLabel(title: "Done reviewing", icon: "checkmark", fill: true)
                                .frame(minHeight: 44)
                        }
                        .srButton(.prominent)
                        .controlSize(.large)
                        .disabled(store.busy)
                        .accessibilityIdentifier("oneclue-done-review")
                    }
                }
            }
        }
        .accessibilityIdentifier("oneclue-review")
    }
}

// MARK: - Guess

struct OneClueGuessing: View {
    let room: GameRoom
    @ObservedObject var store: OneClueStore
    @FocusState private var focused: Bool

    var body: some View {
        let state = room.oneClue
        let clues = state?.clues ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap - 4) {
                OneClueHeader(room: room, store: store,
                              title: store.amGuesser ? "Your guess" : "\(room.name(of: state?.guesserId ?? "")) is guessing",
                              timerId: "oneclue-guess-timer")
                if store.amGuesser {
                    guesserPage(state, clues: clues)
                } else {
                    if let word = state?.word { OneClueWordCard(word: word, flips: false) }
                    SRSectionLabel(text: "What they see")
                    OneClueClueList(clues: clues, room: room, id: "oneclue-guess-list")
                    OneClueWaiting(room: room, label: "Guess")
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .srGround(.warm)
        .accessibilityIdentifier("oneclue-guess")
    }

    @ViewBuilder
    private func guesserPage(_ state: OneClueState?, clues: [OneClueClue]) -> some View {
        SRSectionLabel(text: "Your clues", trailing: "\(clues.count)")
        if clues.isEmpty {
            Text("Every clue cancelled out. Have a go anyway, or pass.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            clueWall(clues)
        }
        if let cancelled = state?.cancelledCount, cancelled > 0 {
            Label(cancelled == 1 ? "1 clue was cancelled." : "\(cancelled) clues were cancelled.",
                  systemImage: "scissors")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .accessibilityIdentifier("oneclue-cancelled-count")
        }
        guessField(state)
    }

    /// The surviving clues, big, as sticky notes to read.
    private func clueWall(_ clues: [OneClueClue]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], spacing: 16) {
            ForEach(Array(clues.enumerated()), id: \.element.id) { index, clue in
                OneClueStickyNote(text: clue.text, author: room.name(of: clue.playerId), index: index)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(clue.text), from \(room.name(of: clue.playerId))")
                    .accessibilityIdentifier("oneclue-survivor-\(clue.playerId)")
            }
        }
        .padding(.vertical, 6)
    }

    private func guessField(_ state: OneClueState?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("The word is…", text: $store.guessDraft)
                .font(SR.Text.title(22))
                .foregroundStyle(SR.ink)
                .textInputAutocapitalization(.never)
                .submitLabel(.go)
                .focused($focused)
                .onSubmit { store.submitGuess() }
                .disabled(!store.canGuess)
                .padding(.horizontal, 16)
                .frame(minHeight: 60)
                .background(
                    RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 2, style: .continuous)
                        .fill(SR.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 2, style: .continuous)
                        .strokeBorder(focused ? SR.accent : SR.line, lineWidth: focused ? 2 : 1)
                )
                .accessibilityLabel("Your guess")
                .accessibilityIdentifier("oneclue-guess-field")
            Button { store.submitGuess() } label: {
                Group {
                    if store.guessing {
                        ProgressView().tint(SR.cream)
                    } else {
                        SRButtonLabel(title: "Guess", icon: "checkmark", fill: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(!store.canGuess || store.guessDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Guess")
            .accessibilityIdentifier("oneclue-guess-button")
            Button { store.pass() } label: {
                SRButtonLabel(title: "Pass", icon: "forward.fill", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(!store.canGuess)
            .accessibilityIdentifier("oneclue-pass")
            VStack(alignment: .leading, spacing: 6) {
                Label("Passing loses this card.", systemImage: "forward")
                Label("A wrong guess loses this card and the next one, so pass if you're stuck.", systemImage: "exclamationmark.triangle")
            }
            .font(SR.Text.mono())
            .foregroundStyle(SR.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }
}

// MARK: - Reveal

struct OneClueReveal: View {
    let room: GameRoom
    @ObservedObject var store: OneClueStore

    var body: some View {
        let state = room.oneClue
        let guesser = state?.guesserId ?? ""
        let line = OneClueRules.outcomeLine(state?.outcome, guesser: room.name(of: guesser),
                                            isMe: guesser == room.meId, tookBack: state?.tookBack ?? false)
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap - 4) {
                OneClueHeader(room: room, store: store, title: line, timerId: "oneclue-reveal-timer")
                if let word = state?.word {
                    OneClueWordCard(word: word, kicker: state?.outcome == .correct ? "RIGHT!" : "IT WAS")
                        .overlay(alignment: .topTrailing) {
                            OneClueStamp(outcome: state?.outcome)
                                .offset(x: -6, y: -14)
                        }
                }
                if let guess = state?.guess {
                    Label("Guessed: \(guess)", systemImage: state?.outcome == .correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(SR.Text.title())
                        .foregroundStyle(state?.outcome == .correct ? SR.good : SR.error)
                        .accessibilityIdentifier("oneclue-guessed")
                }
                if state?.outcome == .wrong, state?.tookBack == false,
                   let discarded = state?.cards.first(where: { $0.outcome == .discarded && $0.index == (state?.cardIndex ?? -2) + 1 }) {
                    Label("The next card, \(discarded.word), is discarded.", systemImage: "minus.circle")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .accessibilityIdentifier("oneclue-discarded")
                }
                SRSectionLabel(text: "The clues")
                OneClueClueList(clues: state?.clues ?? [], room: room, id: "oneclue-reveal-list")
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if room.me?.joined == true {
                OneClueFooter {
                    if store.meDone {
                        OneClueWaiting(room: room, label: "Next card")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Button { store.ready() } label: {
                            SRButtonLabel(title: state?.allSettled == true ? "See the score" : "Next card",
                                          icon: "arrow.right", fill: true)
                                .frame(minHeight: 44)
                        }
                        .srButton(.prominent)
                        .controlSize(.large)
                        .disabled(store.busy)
                        .accessibilityIdentifier("oneclue-next")
                    }
                }
            }
        }
        .accessibilityIdentifier("oneclue-reveal")
    }
}

/// The reveal's rubber stamp across the word card's corner: GOT IT, or how
/// the card was lost. It thumps down once.
struct OneClueStamp: View {
    let outcome: OneClueOutcome?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var down = false

    var body: some View {
        Text(text)
            .font(SR.Text.title(15))
            .tracking(1.4)
            .foregroundStyle(SR.paper)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tone))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5))
            .rotationEffect(.degrees(-8))
            .scaleEffect(down || reduceMotion ? 1 : 1.8)
            .opacity(down || reduceMotion ? 1 : 0)
            .onAppear {
                guard !down else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.55).delay(0.35)) { down = true }
            }
            .accessibilityHidden(true)
    }

    private var text: String {
        switch outcome {
        case .correct?: return "GOT IT"
        case .passed?: return "PASSED"
        case .wrong?: return "MISSED"
        case .timeout?: return "TIME UP"
        default: return "LOST"
        }
    }

    private var tone: Color { outcome == .correct ? SR.good : SR.error }
}

// MARK: - Finished

struct OneClueFinished: View {
    let room: GameRoom
    @ObservedObject var store: OneClueStore
    let done: () -> Void

    /// What this game did to our best on this phone; set once on appearing.
    @State private var best: PartyRoomBestNote?

    var body: some View {
        let state = room.oneClue
        let score = state?.score ?? 0
        let count = state?.cardCount ?? 10
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "One Clue · final",
                             title: OneClueRules.scoreLine(score, of: count),
                             strap: state?.verdict ?? OneClueRules.verdict(score))
                    .accessibilityIdentifier("oneclue-score")

                if let state {
                    OneClueScoreDial(state: state, best: best)
                }

                team(state, score: score)

                GameFinishedButtons(room: room, store: store, prefix: "oneclue", done: done)

                cards(state)

                if let note = GameResults.strap(room) {
                    Text(note)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("oneclue-finished")
        .onAppear { finish(score: score, count: count) }
    }

    private func finish(score: Int, count: Int) {
        guard best == nil else { return }
        var note: PartyRoomBestNote? = nil
        if room.me?.joined == true {
            // Play again keeps the room's id, so the game is told apart by its
            // start and by its deck of words (either may be missing).
            let deck = (room.oneClue?.cards ?? []).map(\.word).joined(separator: ",")
            let token = "\(room.id)|\(Int(room.startedAt ?? 0))|\(deck)"
            note = PartyRoomBestStore.oneClue.record(score, kind: "\(count)", token: token)
        }
        best = note ?? PartyRoomBestNote(previous: nil, best: nil, isNew: false)
        if score >= 6 || note?.isNew == true { SRHaptic.ok() }
    }

    // A team game: no places. Everyone shares the score, as on the leaderboard.
    private func team(_ state: OneClueState?, score: Int) -> some View {
        let tones = SR.PersonHue.assign(room.players.map(\.id))
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            GameRecordLine(room: room)
            SRSectionLabel(text: "The team", trailing: "Everyone \(score)")
            VStack(spacing: 0) {
                ForEach(Array((room.standings ?? []).enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(SR.divider) }
                    HStack(spacing: 12) {
                        GameInitial(name: row.name, tone: tones[row.id] ?? SR.accentInk, side: 34)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name + (row.id == room.meId ? " (you)" : ""))
                                .font(SR.Text.title())
                                .foregroundStyle(row.id == room.meId ? SR.accentInk : SR.ink)
                            Text(detail(row, state))
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("oneclue-standings-\(row.id)")
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
            .accessibilityIdentifier("oneclue-standings")
        }
    }

    private func cards(_ state: OneClueState?) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Every card")
            VStack(spacing: 0) {
                ForEach(Array((state?.cards ?? []).enumerated()), id: \.element.id) { index, card in
                    if index > 0 { Divider().overlay(SR.divider) }
                    cardRow(card)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
            .accessibilityIdentifier("oneclue-cards")
        }
    }

    private func detail(_ row: GameStanding, _ state: OneClueState?) -> String {
        guard let mine = state?.standings?.first(where: { $0.id == row.id }) else { return "" }
        return "\(mine.guessed) guessed right · \(GameResults.count(mine.clues, "clue got through", "clues got through"))"
    }

    private func cardRow(_ card: OneClueCard) -> some View {
        let kept = card.clues.filter { $0.status.survives }.map(\.text)
        let pip: OneCluePip = card.outcome == .discarded ? .discarded : (card.outcome.won ? .won : .lost)
        return HStack(alignment: .center, spacing: 12) {
            OneCluePipDot(pip: pip, side: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.word.capitalized)
                    .font(SR.Text.title())
                    .foregroundStyle(card.outcome.won ? SR.ink : SR.inkSecondary)
                Text(cardLine(card, kept: kept))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("oneclue-card-\(card.index)")
    }

    private func cardLine(_ card: OneClueCard, kept: [String]) -> String {
        if card.outcome == .discarded { return "Discarded after a wrong guess" }
        let who = card.guesserId.map { $0 == room.meId ? "You" : room.name(of: $0) } ?? "Nobody"
        var parts = ["\(who): \(card.outcome.short.lowercased())"]
        if let guess = card.guess, card.outcome != .correct { parts.append("guessed \(guess)") }
        if !kept.isEmpty { parts.append(kept.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

/// The team's score inside a ring of the ten cards — each pip landing in
/// turn — with our best on this phone under it.
struct OneClueScoreDial: View {
    let state: OneClueState
    let best: PartyRoomBestNote?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let pips = OneClueRules.pips(state)
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(SR.good.opacity(0.08))
                    .frame(width: 150, height: 150)
                ForEach(Array(pips.enumerated()), id: \.offset) { index, pip in
                    let angle = Double(index) * 360 / Double(max(pips.count, 1))
                    OneCluePipDot(pip: pip, side: 26)
                        .rotationEffect(.degrees(-angle))
                        .offset(y: -92)
                        .rotationEffect(.degrees(angle))
                        .scaleEffect(shown || reduceMotion ? 1 : 0.2)
                        .opacity(shown || reduceMotion ? 1 : 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6).delay(0.07 * Double(index)),
                                   value: shown)
                }
                VStack(spacing: 0) {
                    Text("\(state.score)")
                        .font(SR.Text.hero(56))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("OUT OF \(state.cardCount)")
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(SR.inkMuted)
                }
                .frame(width: 130)
            }
            .frame(width: 220, height: 220)
            bestLine
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SR.cardPadding)
        .srGlassCard(.paper)
        .onAppear { shown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("oneclue-dial")
    }

    @ViewBuilder
    private var bestLine: some View {
        if let best {
            if best.isNew {
                Label("New team best on this phone!", systemImage: "star.fill")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.good)
                    .accessibilityIdentifier("oneclue-new-best")
            } else if let value = best.best {
                Text("Your best team score here: \(value) out of \(state.cardCount)")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
        }
    }

    private var spoken: String {
        var parts = ["Team score \(state.score) out of \(state.cardCount)"]
        if let best {
            if best.isNew { parts.append("a new team best on this phone") }
            else if let value = best.best { parts.append("best here \(value)") }
        }
        return parts.joined(separator: ", ")
    }
}
