import SwiftUI
import UIKit

/// One One Clue room, from lobby to the team's score.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with what the game is as the lobby's panel; Start waits for three. Each card
/// is a page per phase, under the same header — which card, the team's score,
/// the clock and a row of ten pips:
/// - clues: a clue-giver sees the word, big, and one field for one word; the
///   guesser sees only who has written;
/// - review: the clue-givers see every clue as the server judged it and tap
///   another's to veto it; the guesser waits;
/// - guess: the guesser sees the surviving clues and guesses or passes;
/// - reveal: everyone sees the word, the guess and every clue, cancelled ones
///   included.
/// The finish is the team's score out of ten, the table and every card.
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
            ProgressView()
                .tint(SR.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .srPaper()
        }
    }
}

// MARK: - Lobby

/// What the game is, in the lobby — and, until three are in, that it needs three.
struct OneClueTableCard: View {
    let room: GameRoom

    var body: some View {
        let state = room.oneClue
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "text.bubble.fill")
                .font(SR.Text.display(28))
                .foregroundStyle(SR.paper)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SR.accentInk))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(state?.cardCount ?? 10) CARDS · A TEAM GAME")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text("One word each")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text("Take turns to guess. Everyone else sees the word and writes one clue; clues that match cancel out. Score as many of the ten as you can, together.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = OneClueRules.lobbyLine(playing: room.playing.count, min: state?.minPlayers ?? 3,
                                                     max: state?.maxPlayers ?? 7) {
                    Text(line)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("oneclue-needs-three")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("oneclue-table")
    }
}

// MARK: - The header every card shares

/// Which card, the team's score, the clock, and the row of ten.
struct OneClueHeader: View {
    let room: GameRoom
    @ObservedObject var store: OneClueStore
    let title: String
    let timerId: String

    var body: some View {
        let state = room.oneClue
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(state.map(OneClueRules.cardLine) ?? "One Clue") · TEAM \(state?.score ?? 0)".uppercased())
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
                }
                Spacer(minLength: 8)
                WordleTimer(room: room, store: store, id: timerId)
            }
            if let state { OneCluePips(state: state) }
        }
    }
}

/// Ten pips: filled for a card won, crossed for one lost, dashed for one
/// discarded, ringed for the one in play. Shape as well as colour.
struct OneCluePips: View {
    let state: OneClueState

    var body: some View {
        let pips = OneClueRules.pips(state)
        HStack(spacing: 6) {
            ForEach(Array(pips.enumerated()), id: \.offset) { _, pip in
                ZStack {
                    switch pip {
                    case .won:
                        Circle().fill(SR.good)
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(SR.paper)
                    case .lost:
                        Circle().fill(SR.line)
                        Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(SR.inkMuted)
                    case .discarded:
                        Circle().strokeBorder(SR.inkGhost, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                    case .current:
                        Circle().strokeBorder(SR.accent, lineWidth: 2.5)
                    case .toCome:
                        Circle().strokeBorder(SR.line, lineWidth: 1.5)
                    }
                }
                .frame(width: 18, height: 18)
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

/// The secret word, big, on a card.
struct OneClueWordCard: View {
    let word: String
    var kicker: String = "THE WORD"

    var body: some View {
        VStack(spacing: 6) {
            Text(kicker)
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.paper.opacity(0.8))
            Text(word.uppercased())
                .font(SR.Text.hero(40))
                .foregroundStyle(SR.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, SR.cardPadding)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SR.accentInk))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The word is \(word)")
        .accessibilityIdentifier("oneclue-word")
    }
}

/// The guesser's card while the others write: no word, just a question mark.
struct OneClueHiddenCard: View {
    let line: String

    var body: some View {
        VStack(spacing: 8) {
            Text("?")
                .font(SR.Text.hero(48))
                .foregroundStyle(SR.paper)
            Text(line)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.paper.opacity(0.9))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, SR.cardPadding)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SR.ink))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("oneclue-hidden")
    }
}

/// Who the table is waiting on, as chips.
struct OneClueWaiting: View {
    let room: GameRoom
    let label: String

    var body: some View {
        let waiting = OneClueRules.waitingOn(room)
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: label)
            if waiting.isEmpty {
                Text("Everyone's ready.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            } else {
                Text("Waiting on \(OneClueRules.names(waiting, me: room.meId)).")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("oneclue-waiting")
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
        let cancelled = !clue.status.survives && clue.status != .unknown
        let traits: AccessibilityTraits = !canVeto ? [] : clue.vetoed ? [.isButton, .isSelected] : .isButton
        Button {
            onTap?()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                GameInitial(name: isMe ? "You" : room.name(of: clue.playerId), tone: isMe ? SR.accent : SR.accentInk)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clue.text.isEmpty ? "—" : clue.text)
                        .font(SR.Text.title(18))
                        .foregroundStyle(cancelled || clue.text.isEmpty ? SR.inkGhost : SR.ink)
                        .strikethrough(cancelled && !clue.text.isEmpty, color: clue.status == .vetoed ? SR.error : SR.inkMuted)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if let tag = clue.status.tag {
                            Text(tag)
                                .font(SR.Text.label())
                                .tracking(1)
                                .foregroundStyle(clue.status == .vetoed ? SR.error : SR.inkMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .overlay(Capsule().strokeBorder(clue.status == .vetoed ? SR.error : SR.line, lineWidth: 1))
                        }
                        if let line = OneClueRules.vetoLine(clue) {
                            Text(line)
                                .font(SR.Text.mono())
                                .foregroundStyle(clue.status == .vetoed ? SR.error : SR.warn)
                        }
                    }
                }
                Spacer(minLength: 8)
                if canVeto {
                    Image(systemName: clue.vetoed ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .font(SR.Text.title())
                        .foregroundStyle(clue.vetoed ? SR.error : SR.inkGhost)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: SR.tapTarget)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(clue.vetoed ? SR.error.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canVeto || onTap == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(isMe: isMe))
        .accessibilityHint(canVeto ? (clue.vetoed ? "Takes your veto back" : "Vetoes it") : "")
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier("oneclue-clue-\(clue.playerId)")
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
            ForEach(Array(clues.enumerated()), id: \.element.id) { index, clue in
                if index > 0 { Divider().overlay(SR.divider) }
                OneClueClueRow(clue: clue, room: room, onTap: store.map { s -> () -> Void in { s.toggleVeto(clue) } })
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 4)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
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
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                OneClueHeader(room: room, store: store,
                              title: store.amGuesser ? "You're guessing" : "Write one clue",
                              timerId: "oneclue-timer")
                if store.amGiver, let word = state?.word {
                    OneClueWordCard(word: word)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("One word", text: Binding(get: { store.draft }, set: { store.edit($0) }))
                            .font(SR.Text.body(20))
                            .foregroundStyle(SR.ink)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(false)
                            .submitLabel(.done)
                            .focused($focused)
                            .onSubmit { store.lockIn() }
                            .disabled(!store.canClue)
                            .padding(.horizontal, 14)
                            .frame(minHeight: SR.tapTarget + 8)
                            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
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
                            Label("Locked in. Change it any time before the clues open.", systemImage: "lock.fill")
                                .font(SR.Text.secondary(13))
                                .foregroundStyle(SR.good)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("oneclue-locked")
                        } else {
                            Button { store.lockIn() } label: {
                                SRButtonLabel(title: "Lock in my clue", icon: "lock", fill: true)
                            }
                            .srButton(.prominent)
                            .controlSize(.large)
                            .disabled(!store.canLock)
                            .accessibilityIdentifier("oneclue-lock")
                        }
                        Text("Take your time: the clues open once everyone has locked one in. If the clock runs out, what you've written still counts. If anyone writes the same clue as you, both cancel out — so think different.")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if store.amGuesser {
                    OneClueHiddenCard(line: "Everyone else can see the word and is writing one clue for you. No peeking needed.")
                } else {
                    Text("You are not playing in this one.")
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
    }
}

// MARK: - Review

struct OneClueReview: View {
    let room: GameRoom
    @ObservedObject var store: OneClueStore

    var body: some View {
        let state = room.oneClue
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                OneClueHeader(room: room, store: store,
                              title: store.amGiver ? "Any too close?" : "Checking the clues",
                              timerId: "oneclue-review-timer")
                if store.amGiver {
                    if let word = state?.word { OneClueWordCard(word: word) }
                    Text("Matching clues and ones too like the word are already out. Tap somebody else's clue to veto it if it gives too much away; half the others vetoing strikes it.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    OneClueClueList(clues: state?.clues ?? [], room: room, store: store, id: "oneclue-review-list")
                    if store.meDone {
                        OneClueWaiting(room: room, label: "Review")
                    } else {
                        Button { store.ready() } label: {
                            SRButtonLabel(title: "Done reviewing", icon: "checkmark", fill: true)
                        }
                        .srButton(.prominent)
                        .controlSize(.large)
                        .disabled(store.busy)
                        .accessibilityIdentifier("oneclue-done-review")
                    }
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
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                OneClueHeader(room: room, store: store,
                              title: store.amGuesser ? "Your guess" : "\(room.name(of: state?.guesserId ?? "")) is guessing",
                              timerId: "oneclue-guess-timer")
                if store.amGuesser {
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
                        Text(cancelled == 1 ? "1 clue was cancelled." : "\(cancelled) clues were cancelled.")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .accessibilityIdentifier("oneclue-cancelled-count")
                    }
                    guessField(state)
                } else {
                    if let word = state?.word { OneClueWordCard(word: word) }
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

    /// The surviving clues, big, as cards to read.
    private func clueWall(_ clues: [OneClueClue]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(clues) { clue in
                VStack(spacing: 4) {
                    Text(clue.text)
                        .font(SR.Text.display(24))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(room.name(of: clue.playerId))
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 72)
                .padding(.horizontal, 8)
                .srGlassCard(.paper)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(clue.text), from \(room.name(of: clue.playerId))")
                .accessibilityIdentifier("oneclue-survivor-\(clue.playerId)")
            }
        }
    }

    private func guessField(_ state: OneClueState?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("The word is…", text: $store.guessDraft)
                .font(SR.Text.body(20))
                .foregroundStyle(SR.ink)
                .textInputAutocapitalization(.never)
                .submitLabel(.go)
                .focused($focused)
                .onSubmit { store.submitGuess() }
                .disabled(!store.canGuess)
                .padding(.horizontal, 14)
                .frame(minHeight: SR.tapTarget + 8)
                .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
                .accessibilityLabel("Your guess")
                .accessibilityIdentifier("oneclue-guess-field")
            Button { store.submitGuess() } label: {
                SRButtonLabel(title: "Guess", icon: "checkmark", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(!store.canGuess || store.guessDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("oneclue-guess-button")
            Button { store.pass() } label: {
                SRButtonLabel(title: "Pass", icon: "forward.fill", fill: true)
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(!store.canGuess)
            .accessibilityIdentifier("oneclue-pass")
            Text("Passing loses this card. A wrong guess loses this card and the next one, so pass if you're stuck.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                OneClueHeader(room: room, store: store, title: line, timerId: "oneclue-reveal-timer")
                if let word = state?.word {
                    OneClueWordCard(word: word, kicker: state?.outcome == .correct ? "RIGHT!" : "IT WAS")
                }
                if let guess = state?.guess {
                    Text("Guessed: \(guess)")
                        .font(SR.Text.title())
                        .foregroundStyle(state?.outcome == .correct ? SR.good : SR.error)
                        .accessibilityIdentifier("oneclue-guessed")
                }
                if state?.outcome == .wrong, state?.tookBack == false,
                   let discarded = state?.cards.first(where: { $0.outcome == .discarded && $0.index == (state?.cardIndex ?? -2) + 1 }) {
                    Text("The next card, \(discarded.word), is discarded.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .accessibilityIdentifier("oneclue-discarded")
                }
                SRSectionLabel(text: "The clues")
                OneClueClueList(clues: state?.clues ?? [], room: room, id: "oneclue-reveal-list")
                if room.me?.joined == true {
                    if store.meDone {
                        OneClueWaiting(room: room, label: "Next card")
                    } else {
                        Button { store.ready() } label: {
                            SRButtonLabel(title: state?.allSettled == true ? "See the score" : "Next card",
                                          icon: "arrow.right", fill: true)
                        }
                        .srButton(.prominent)
                        .controlSize(.large)
                        .disabled(store.busy)
                        .accessibilityIdentifier("oneclue-next")
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("oneclue-reveal")
    }
}

// MARK: - Finished

struct OneClueFinished: View {
    let room: GameRoom
    @ObservedObject var store: OneClueStore
    let done: () -> Void

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
                if let state { OneCluePips(state: state) }

                // A team game: no places. Everyone shares the score, as on the leaderboard.
                VStack(alignment: .leading, spacing: SR.cardGap) {
                    GameRecordLine(room: room)
                    SRSectionLabel(text: "The team", trailing: "Everyone \(score)")
                    VStack(spacing: 0) {
                        ForEach(Array((room.standings ?? []).enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider().overlay(SR.divider) }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.name + (row.id == room.meId ? " (you)" : ""))
                                    .font(SR.Text.title())
                                    .foregroundStyle(SR.ink)
                                Text(detail(row, state))
                                    .font(SR.Text.mono())
                                    .foregroundStyle(SR.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, minHeight: SR.tapTarget, alignment: .leading)
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

                if let note = GameResults.strap(room) {
                    Text(note)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                GameFinishedButtons(room: room, store: store, prefix: "oneclue", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("oneclue-finished")
        .onAppear { if score >= 6 { SRHaptic.ok() } }
    }

    private func detail(_ row: GameStanding, _ state: OneClueState?) -> String {
        guard let mine = state?.standings?.first(where: { $0.id == row.id }) else { return "" }
        return "\(mine.guessed) guessed right · \(GameResults.count(mine.clues, "clue got through", "clues got through"))"
    }

    private func cardRow(_ card: OneClueCard) -> some View {
        let kept = card.clues.filter { $0.status.survives }.map(\.text)
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: card.outcome.won ? "checkmark.circle.fill" : card.outcome == .discarded ? "minus.circle" : "xmark.circle")
                .font(SR.Text.title())
                .foregroundStyle(card.outcome.won ? SR.good : SR.inkGhost)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.word.capitalized)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
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
