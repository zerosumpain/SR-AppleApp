import SwiftUI
import UIKit

/// One Wordle Race room, from lobby to the reveal.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`).
/// Playing is my grid, the others' colours above it, and a keyboard pinned
/// under it; finished reveals the word and everybody's letters.
struct WordleRaceScreen: View {
    let roomId: String
    @StateObject private var store: WordleRaceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: WordleRaceStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Wordle Race")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar(immersive ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(immersive)
            .onAppear { store.open() }
            .onDisappear { store.close() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.open() } else if phase == .background { store.close() }
            }
            // At the top: the keyboard owns the bottom edge while playing.
            .overlay(alignment: .top) {
                if let message = store.message, !immersive { SRBanner(text: message) }
            }
    }

    private var immersive: Bool {
        guard !store.ended, let phase = store.room?.phase else { return false }
        return phase == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "wordle-ended", done: { dismiss() })
        } else if let room = store.room {
            switch room.phase {
            case .lobby, .unknown, .armed, .result, .question, .reveal, .show, .input:
                GameLobby(room: room, store: store, prefix: "wordle", done: { dismiss() })
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Same word for everyone. Six guesses. The others see your colours, not your letters.",
                                  id: "wordle-countdown")
            case .playing:
                WordlePlaying(room: room, store: store)
            case .finished:
                WordleFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "wordle-ended", done: { dismiss() })
            }
        } else {
            ProgressView()
                .tint(SR.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .srPaper()
        }
    }
}

// MARK: - Playing

struct WordlePlaying: View {
    let room: GameRoom
    @ObservedObject var store: WordleRaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !room.others.isEmpty {
                    WordleOthersStrip(room: room)
                }
                WordleBoard(
                    rows: me?.rows ?? [],
                    typing: store.canType ? store.input : nil,
                    maxGuesses: room.maxGuesses,
                    wordLength: room.wordLength,
                    side: 52,
                    shakes: reduceMotion ? 0 : store.shakes
                )
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("wordle-board")
                statusLine
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .srGround(.warm)
        .safeAreaInset(edge: .bottom) {
            WordleKeyboardView(
                marks: WordleKeyboard.marks(server: room.keyboard, rows: me?.rows ?? []),
                enabled: store.canType && !store.submitting,
                press: { store.press($0) },
                delete: { store.delete() },
                submit: { store.submit() }
            )
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(SR.paper.opacity(0.94), ignoresSafeAreaEdges: .bottom)
        }
        .accessibilityIdentifier("wordle-playing")
        .onChange(of: store.shakes) { _, _ in
            if let refusal = store.refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
    }

    private var me: GamePlayer? { room.me }

    private func solvedLine(_ guesses: Int) -> String {
        guesses == 1 ? "Solved in one. Waiting for the others." : "Solved in \(guesses). Waiting for the others."
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker)
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text(progress)
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
            }
            Spacer(minLength: 8)
            WordleTimer(room: room, store: store)
        }
    }

    private var kicker: String {
        let level = GameDifficulty.label(for: room.difficulty).uppercased()
        return room.hardMode ? "WORDLE RACE · \(level) · HARD MODE" : "WORDLE RACE · \(level)"
    }

    private var progress: String {
        guard let me else { return "Watching" }
        if me.solved { return "Solved" }
        if me.done || me.guessCount >= room.maxGuesses { return "Out" }
        return "Guess \(me.guessCount + 1) of \(room.maxGuesses)"
    }

    @ViewBuilder
    private var statusLine: some View {
        if let refusal = store.refusal {
            Label(refusal, systemImage: "exclamationmark.circle")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.error)
                .multilineTextAlignment(.center)
                .transition(.opacity)
                .accessibilityIdentifier("wordle-refusal")
        } else if let me, me.solved {
            Text(solvedLine(me.guessCount))
                .font(SR.Text.secondary())
                .foregroundStyle(SR.good)
                .multilineTextAlignment(.center)
        } else if let me, me.done || me.guessCount >= room.maxGuesses {
            Text("Out of guesses. The word is revealed when everyone is done.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .multilineTextAlignment(.center)
        } else if room.me?.joined != true {
            Text("You are not playing in this one.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
        } else if room.hardMode {
            Text("Hard mode: greens stay put, found letters stay in.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .multilineTextAlignment(.center)
        }
    }
}

/// The time limit, counting down to `phaseEndsAt`. Any game's store: Anagram
/// Blitz and Quick Maths Sprint count down the same way, under their own id.
struct WordleTimer<Store: GameRoomStoring>: View {
    let room: GameRoom
    @ObservedObject var store: Store
    var id: String = "wordle-timer"

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let left = msLeft
            Text(left.map { WordleClock.text(msLeft: $0) } ?? "–:––")
                .font(SR.Text.figure(28))
                .monospacedDigit()
                .foregroundStyle(tone(left))
                .lineLimit(1)
                .accessibilityLabel(left.map { "\(WordleClock.text(msLeft: $0)) left" } ?? "Time left unknown")
                .accessibilityIdentifier(id)
        }
    }

    private var msLeft: Double? {
        guard let end = room.phaseEndsAt, let now = store.serverNow() else { return nil }
        return max(0, end - now)
    }

    private func tone(_ left: Double?) -> Color {
        guard let left else { return SR.inkMuted }
        if left <= 30_000 { return SR.error }
        if left <= 60_000 { return SR.accent }
        return SR.ink
    }
}

// MARK: - Tiles

/// Tile colours, and the second cue that makes them readable without colour.
///
/// Olive (`good`) for a letter in place, mustard (`warn`) for a letter in the
/// word elsewhere, pale ink for a letter not in it — three steps of lightness
/// as well as three hues. On top of that, shape: a bar under a letter in place,
/// a dot in the corner of a letter elsewhere, nothing on a miss. Olive and
/// mustard are the two a red-green reader is most likely to confuse, and the
/// bar and dot tell them apart at any size, down to the others' mini grids.
enum WordlePalette {
    static func fill(_ mark: WordleMark) -> Color {
        switch mark {
        case .correct: return SR.good
        case .present: return SR.warn
        case .absent: return SR.ink.opacity(0.26)
        case .unknown: return SR.surface
        }
    }

    static func letter(_ mark: WordleMark) -> Color {
        switch mark {
        case .correct: return SR.paper
        case .present: return SR.ink
        case .absent: return SR.inkSecondary
        case .unknown: return SR.ink
        }
    }

    /// The cue's own colour: paper on olive, ink on mustard.
    static func cue(_ mark: WordleMark) -> Color {
        mark == .correct ? SR.paper : SR.ink
    }
}

/// The shape cue for one mark, laid over a tile or key of side `side`.
struct WordleCue: View {
    let mark: WordleMark
    let side: CGFloat

    var body: some View {
        ZStack {
            if mark == .correct {
                Capsule()
                    .fill(WordlePalette.cue(mark))
                    .frame(width: side * 0.5, height: max(2, side * 0.07))
                    .padding(.bottom, max(1, side * 0.09))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            } else if mark == .present {
                Circle()
                    .fill(WordlePalette.cue(mark))
                    .frame(width: max(3, side * 0.14), height: max(3, side * 0.14))
                    .padding(max(1, side * 0.09))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One square. `mark` nil is a tile not yet scored: empty, or being typed.
struct WordleTile: View {
    let letter: Character?
    let mark: WordleMark?
    let side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(2, side * 0.06), style: .continuous)
                .fill(mark.map { WordlePalette.fill($0) } ?? Color.clear)
            if mark == nil {
                RoundedRectangle(cornerRadius: max(2, side * 0.06), style: .continuous)
                    .strokeBorder(letter == nil ? SR.line : SR.ink, lineWidth: letter == nil ? 1.5 : 2)
            }
            if let letter {
                Text(String(letter).uppercased())
                    .font(SR.Text.display(side * 0.5))
                    .foregroundStyle(mark.map { WordlePalette.letter($0) } ?? SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(side * 0.08)
            }
            if let mark { WordleCue(mark: mark, side: side) }
        }
        .frame(width: side, height: side)
    }
}

/// A grid of guesses: the scored rows, then (while I can type) the row being
/// typed, then empty rows up to `maxGuesses`. Letters where the row has them.
struct WordleBoard: View {
    let rows: [WordleRow]
    /// The row being typed, or nil when this grid takes no input.
    let typing: WordleInput?
    let maxGuesses: Int
    let wordLength: Int
    let side: CGFloat
    /// The typing row shakes each time this changes.
    var shakes: Int = 0

    var body: some View {
        VStack(spacing: max(2, side * 0.12)) {
            ForEach(0..<maxGuesses, id: \.self) { index in
                rowView(index)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ index: Int) -> some View {
        let spacing = max(2, side * 0.12)
        if index < rows.count {
            let row = rows[index]
            let letters = row.letters
            HStack(spacing: spacing) {
                ForEach(0..<wordLength, id: \.self) { column in
                    WordleTile(
                        letter: Self.letter(at: column, in: letters),
                        mark: column < row.marks.count ? row.marks[column] : .unknown,
                        side: side
                    )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WordleSpeech.row(row, number: index + 1))
        } else if index == rows.count, let typing {
            HStack(spacing: spacing) {
                ForEach(0..<wordLength, id: \.self) { column in
                    WordleTile(
                        letter: column < typing.letters.count ? typing.letters[column] : nil,
                        mark: nil,
                        side: side
                    )
                }
            }
            .modifier(WordleShake(animatableData: CGFloat(shakes)))
            .animation(.linear(duration: 0.4), value: shakes)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(typing.isEmpty ? "Guess \(index + 1), empty" : "Guess \(index + 1), typing \(typing.word.uppercased())")
            .accessibilityIdentifier("wordle-typing-row")
        } else {
            HStack(spacing: spacing) {
                ForEach(0..<wordLength, id: \.self) { _ in
                    WordleTile(letter: nil, mark: nil, side: side)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

extension WordleBoard {
    static func letter(at column: Int, in letters: [Character]?) -> Character? {
        guard let letters, column < letters.count else { return nil }
        return letters[column]
    }
}

/// A side-to-side shake, three times over one change of `animatableData`.
struct WordleShake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 6), y: 0))
    }
}

/// What VoiceOver says for a row.
enum WordleSpeech {
    static func row(_ row: WordleRow, number: Int) -> String {
        if let letters = row.letters {
            let parts = zip(letters, row.marks).map { "\(String($0.0)) \($0.1.spoken)" }
            return "Guess \(number), \(String(letters)): " + parts.joined(separator: ", ")
        }
        return "Guess \(number): " + summary(row.marks)
    }

    /// "2 in place, 1 elsewhere" — a colours-only row, spoken.
    static func summary(_ marks: [WordleMark]) -> String {
        let places = marks.filter { $0 == .correct }.count
        let elsewhere = marks.filter { $0 == .present }.count
        if places == marks.count, !marks.isEmpty { return "solved" }
        if places == 0 && elsewhere == 0 { return "nothing" }
        return "\(places) in place, \(elsewhere) elsewhere"
    }
}

// MARK: - The others

/// Everyone else, as colours: their rows without letters, how many guesses,
/// and whether they have it.
struct WordleOthersStrip: View {
    let room: GameRoom

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(room.others) { player in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(player.name)
                            .font(SR.Text.title(14))
                            .foregroundStyle(SR.ink)
                            .lineLimit(1)
                        WordleBoard(
                            rows: player.rows,
                            typing: nil,
                            maxGuesses: room.maxGuesses,
                            wordLength: room.wordLength,
                            side: 11
                        )
                        .accessibilityHidden(true)
                        standing(player)
                    }
                    .padding(10)
                    .frame(minWidth: 96, alignment: .leading)
                    .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken(player))
                    .accessibilityIdentifier("wordle-other-\(player.id)")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("wordle-others")
    }

    @ViewBuilder
    private func standing(_ player: GamePlayer) -> some View {
        if player.solved {
            Label("Solved", systemImage: "checkmark.circle.fill")
                .font(SR.Text.label())
                .foregroundStyle(SR.good)
        } else if player.done {
            Text("OUT")
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
        } else {
            Text("\(player.guessCount)/\(room.maxGuesses)")
                .font(SR.Text.label())
                .foregroundStyle(SR.inkSecondary)
                .monospacedDigit()
        }
    }

    private func spoken(_ player: GamePlayer) -> String {
        let state: String
        if player.solved {
            state = "solved in \(player.guessCount)"
        } else if player.done {
            state = "out of guesses"
        } else {
            state = player.guessCount == 1 ? "1 guess" : "\(player.guessCount) guesses"
        }
        let last = player.rows.last.map { ", last guess \(WordleSpeech.summary($0.marks))" } ?? ""
        return "\(player.name), \(state)\(last)"
    }
}

// MARK: - Keyboard

/// QWERTY, coloured by my best mark per letter, with Enter and Delete. Keys
/// are at least 44 points tall; ten across a phone cannot also be 44 wide.
struct WordleKeyboardView: View {
    let marks: [Character: WordleMark]
    let enabled: Bool
    let press: (Character) -> Void
    let delete: () -> Void
    let submit: () -> Void

    static let keyHeight: CGFloat = 52
    static let rowGap: CGFloat = 8
    static let keyGap: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            keys(unit: max(20, (geo.size.width - Self.keyGap * 9) / 10))
                .frame(width: geo.size.width)
        }
        .frame(height: Self.keyHeight * 3 + Self.rowGap * 2)
        .opacity(enabled ? 1 : 0.55)
        // `.contain`, so each key keeps its own id under the keyboard's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wordle-keyboard")
    }

    private func keys(unit: CGFloat) -> some View {
        VStack(spacing: Self.rowGap) {
            HStack(spacing: Self.keyGap) {
                ForEach(WordleKeyboard.rows[0], id: \.self) { letterKey($0, width: unit) }
            }
            HStack(spacing: Self.keyGap) {
                ForEach(WordleKeyboard.rows[1], id: \.self) { letterKey($0, width: unit) }
            }
            HStack(spacing: Self.keyGap) {
                actionKey(title: "ENTER", icon: nil, label: "Enter guess", id: "wordle-enter", width: unit * 1.5, action: submit)
                ForEach(WordleKeyboard.rows[2], id: \.self) { letterKey($0, width: unit) }
                actionKey(title: nil, icon: "delete.left", label: "Delete letter", id: "wordle-delete", width: unit * 1.5, action: delete)
            }
        }
    }

    private func letterKey(_ letter: Character, width: CGFloat) -> some View {
        let mark = marks[letter]
        return Button {
            press(letter)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(mark.map { WordlePalette.fill($0) } ?? SR.surface)
                if mark == nil {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(SR.line, lineWidth: 1)
                }
                Text(String(letter).uppercased())
                    .font(SR.bodyBold(18))
                    .foregroundStyle(mark.map { WordlePalette.letter($0) } ?? SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let mark { WordleCue(mark: mark, side: min(width, Self.keyHeight)) }
            }
            .frame(width: width, height: Self.keyHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(mark.map { "\(String(letter).uppercased()), \($0.spoken)" } ?? String(letter).uppercased())
        .accessibilityIdentifier("wordle-key-\(letter)")
    }

    private func actionKey(title: String?, icon: String?, label: String, id: String, width: CGFloat,
                           action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(SR.ink)
                if let title {
                    Text(title)
                        .font(SR.Text.label(12))
                        .foregroundStyle(SR.paper)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SR.paper)
                }
            }
            .frame(width: width, height: Self.keyHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Finished

struct WordleFinished: View {
    let room: GameRoom
    @ObservedObject var store: WordleRaceStore
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Wordle Race · final", title: title, strap: strap)

                if let secret = room.secret, !secret.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "The word")
                        HStack(spacing: 6) {
                            ForEach(Array(secret.uppercased().enumerated()), id: \.offset) { _, letter in
                                WordleTile(letter: letter, mark: .correct, side: 48)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("The word was \(secret.uppercased())")
                        .accessibilityIdentifier("wordle-secret")
                    }
                }

                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: room.solo ? "Your game" : "Standings")
                    VStack(spacing: 0) {
                        ForEach(Array(standings.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider().overlay(SR.divider) }
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(SR.Text.display(26))
                                    .foregroundStyle(room.winnerIds.contains(row.id) ? SR.accent : SR.inkGhost)
                                    .frame(width: 32, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(row.name + (row.id == room.meId ? " (you)" : ""))
                                            .font(SR.Text.title())
                                            .foregroundStyle(SR.ink)
                                        if room.winnerIds.contains(row.id), !room.solo {
                                            Image(systemName: "crown.fill")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(SR.accent)
                                                .accessibilityLabel("Winner")
                                        }
                                    }
                                    Text(detail(row))
                                        .font(SR.Text.mono())
                                        .foregroundStyle(SR.inkMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: row.solved ? "checkmark.circle.fill" : "xmark.circle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(row.solved ? SR.good : SR.inkGhost)
                                    .accessibilityLabel(row.solved ? "Solved" : "Not solved")
                            }
                            .padding(.vertical, 10)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.horizontal, SR.cardPadding)
                    .padding(.vertical, 6)
                    .srGlassCard(.paper)
                    .accessibilityIdentifier("wordle-standings")
                }

                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: room.solo ? "Your grid" : "Everyone’s grids")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(room.playing) { player in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(player.name + (player.id == room.meId ? " (you)" : ""))
                                    .font(SR.Text.title(15))
                                    .foregroundStyle(SR.ink)
                                    .lineLimit(1)
                                WordleBoard(
                                    rows: player.rows,
                                    typing: nil,
                                    maxGuesses: room.maxGuesses,
                                    wordLength: room.wordLength,
                                    side: 24
                                )
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("wordle-grid-\(player.id)")
                        }
                    }
                }

                VStack(spacing: 10) {
                    if room.isHost {
                        Button {
                            SRHaptic.tap()
                            Task { await store.act("again") }
                        } label: {
                            SRButtonLabel(title: "Play again", icon: "arrow.counterclockwise", fill: true)
                        }
                        .srButton(.prominent)
                        .controlSize(.large)
                        .disabled(store.busy)
                        .accessibilityIdentifier("wordle-again")
                    }
                    Button { done() } label: { SRButtonLabel(title: "Done", fill: true) }
                        .srButton(.regular)
                        .controlSize(.large)
                        .accessibilityIdentifier("wordle-done")
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("wordle-finished")
        .onAppear { if room.winnerIds.contains(room.meId) { SRHaptic.ok() } }
    }

    /// The server's standings; failing those, everyone in, solvers first.
    private var standings: [GameStanding] { room.standings ?? [] }

    private var title: String {
        let mine = standings.first { $0.id == room.meId }
        if room.solo { return mine?.solved == true ? "You got it" : "Not this time" }
        let names = room.winnerIds.map { $0 == room.meId ? "You" : room.name(of: $0) }
        switch names.count {
        case 0: return "Nobody got it"
        case 1: return names[0] == "You" ? "You win" : "\(names[0]) wins"
        default: return "\(GameNames.list(names)) tie"
        }
    }

    private var strap: String? {
        room.isHost ? nil : "Only \(room.host?.name ?? "the host") can start another round of this one."
    }

    private func detail(_ row: GameStanding) -> String {
        let guesses = row.guesses ?? room.players.first(where: { $0.id == row.id })?.guessCount ?? 0
        let count = guesses == 1 ? "1 guess" : "\(guesses) guesses"
        guard row.solved else { return "not solved · \(count)" }
        if let ms = row.solveMs { return "\(count) · \(WordleClock.duration(ms: ms))" }
        return count
    }
}
