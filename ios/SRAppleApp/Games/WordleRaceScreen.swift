import SwiftUI
import UIKit

/// One Wordle Race room, from lobby to the reveal.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with how to play — a scored sample row and what each colour means — and my
/// bests as the lobby's panel. Playing is my grid, sized to the room the phone
/// has above the keyboard, the others' colours in a strip over it and a clock
/// that drains; a guess flips in tile by tile, a solve jumps and bursts, and
/// once I have nothing left to play the keyboard gives way to who we are
/// waiting for. Finished flips the word over, then standings, my bests and
/// everybody's letters.
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
            case .lobby, .unknown, .armed, .result, .question, .reveal, .show, .input, .review:
                GameLobby(room: room, store: store, prefix: "wordle", done: { dismiss() },
                          panel: AnyView(WordleRaceHowTo(room: room)))
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

// MARK: - Lobby

/// How to play, in the lobby: a sample row scored the way the real ones are,
/// what each colour means, and my bests so far.
struct WordleRaceHowTo: View {
    let room: GameRoom
    @State private var book = WordRoomBestBook()

    var body: some View {
        WordRoomHowToCard(title: "How to play", steps: steps, best: best, id: "wordle-howto") {
            WordleRaceSample()
        }
        .onAppear { book = WordRoomBestStore(game: .wordle).load() }
    }

    private var steps: [WordRoomStep] {
        var list = [
            WordRoomStep(icon: "keyboard", text: "Everyone gets the same \(WordRoomText.number(room.wordLength))-letter word and \(room.maxGuesses) guesses. Race to crack it."),
            WordRoomStep(icon: "square.fill", text: "Green with a bar: right letter, right place. Yellow with a dot: in the word, somewhere else. Grey: not in it."),
            WordRoomStep(icon: "eye.slash", text: "The others see your colours, never your letters, until the end."),
        ]
        if room.hardMode {
            list.append(WordRoomStep(icon: "lock.fill", text: "Hard mode: greens stay put, and found letters must stay in."))
        }
        return list
    }

    private var best: String? {
        guard book.played > 0 else { return nil }
        var parts = ["Played \(book.played)"]
        if book.fewestGuesses > 0 { parts.append("best solve in \(book.fewestGuesses)") }
        if book.bestStreak > 1 { parts.append("longest run \(book.bestStreak)") }
        return parts.joined(separator: " · ")
    }
}

/// CRANE, scored: the colours and their shapes, as the grid will show them.
struct WordleRaceSample: View {
    static let letters: [Character] = Array("CRANE")
    static let marks: [WordleMark] = [.absent, .present, .correct, .absent, .correct]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<Self.letters.count, id: \.self) { index in
                    WordleTile(letter: Self.letters[index], mark: Self.marks[index], side: 44)
                }
            }
            HStack(spacing: 8) {
                legend(.correct, "Right place")
                legend(.present, "In the word")
                legend(.absent, "Not in it")
            }
        }
    }

    private func legend(_ mark: WordleMark, _ text: String) -> some View {
        HStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(WordlePalette.fill(mark))
                WordleCue(mark: mark, side: 16)
            }
            .frame(width: 16, height: 16)
            Text(text)
                .font(SR.Text.label())
                .foregroundStyle(SR.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Playing

struct WordlePlaying: View {
    let room: GameRoom
    @ObservedObject var store: WordleRaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The newest scored row, flipping in tile by tile.
    @State private var flipRow: Int?
    @State private var flipped = true
    /// Bumped when I solve it: the row jumps and the board bursts.
    @State private var cheers = 0

    /// Header, clock bar, the others and the status line, roughly: what the
    /// grid must leave room for above the keyboard.
    private var reserved: CGFloat { room.others.isEmpty ? 150 : 222 }

    var body: some View {
        GeometryReader { full in
            let keyHeight: CGFloat = full.size.height < 640 ? 50 : 56
            let bottomHeight = keyHeight * 3 + WordleKeyboardView.rowGap * 2 + 20
            let side = CGFloat(WordRoomLayout.wordleTileSide(
                width: Double(full.size.width - SR.gutter * 2),
                height: Double(full.size.height - bottomHeight - reserved),
                wordLength: room.wordLength,
                maxGuesses: room.maxGuesses
            ))
            VStack(spacing: 0) {
                ScrollView {
                    page(side: side)
                }
                bottom(keyHeight: keyHeight)
            }
        }
        .srGround(.warm)
        .accessibilityIdentifier("wordle-playing")
        .onChange(of: store.shakes) { _, _ in
            if let refusal = store.refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
        .onChange(of: me?.rows.count ?? 0) { old, new in
            if new > old { flip(new - 1) }
        }
        .onChange(of: me?.solved ?? false) { old, new in
            if new && !old {
                cheers += 1
                UIAccessibility.post(notification: .announcement, argument: solvedLine(me?.guessCount ?? 0))
            }
        }
    }

    private var me: GamePlayer? { room.me }

    private func page(side: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            WordRoomTimeBar(room: room, store: store)
            if !room.others.isEmpty {
                WordleOthersStrip(room: room)
            }
            board(side: side)
            statusLine
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .padding(.horizontal, SR.gutter)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private func board(side: CGFloat) -> some View {
        WordleBoard(
            rows: me?.rows ?? [],
            typing: store.canType ? store.input : nil,
            maxGuesses: room.maxGuesses,
            wordLength: room.wordLength,
            side: side,
            shakes: reduceMotion ? 0 : store.shakes,
            flipRow: flipRow,
            flipped: flipped,
            cheerRow: (me?.solved ?? false) ? max(0, (me?.rows.count ?? 1) - 1) : nil,
            cheers: reduceMotion ? 0 : cheers
        )
        .frame(maxWidth: .infinity)
        .overlay {
            WordRoomBurst(token: cheers, colours: [SR.good, SR.warn, SR.accent])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wordle-board")
    }

    /// The new row turns edge-on at once, then each tile flips face up in turn.
    private func flip(_ row: Int) {
        guard !reduceMotion else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            flipRow = row
            flipped = false
        }
        DispatchQueue.main.async { flipped = true }
    }

    private func solvedLine(_ guesses: Int) -> String {
        guesses == 1 ? "Solved in one!" : "Solved in \(guesses)!"
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker)
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(progress)
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .srAnimation(.snappy, value: progress)
            }
            Spacer(minLength: 8)
            WordRoomClock(room: room, store: store, id: "wordle-timer")
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

    // MARK: Status

    @ViewBuilder
    private var statusLine: some View {
        if let refusal = store.refusal {
            WordRoomPill(text: refusal, icon: "exclamationmark.circle.fill", tone: SR.error)
                .transition(.opacity)
                .accessibilityIdentifier("wordle-refusal")
        } else if let me, me.solved {
            WordRoomPill(text: solvedLine(me.guessCount), icon: "checkmark.seal.fill", tone: SR.good, filled: true)
        } else if let me, me.done || me.guessCount >= room.maxGuesses {
            WordRoomPill(text: "Out of guesses. The word is revealed when everyone is done.", icon: "hourglass", tone: SR.inkMuted)
        } else if room.me?.joined != true {
            WordRoomPill(text: "You are not playing in this one.", icon: "eye", tone: SR.inkMuted)
        } else if store.submitting {
            WordRoomPill(text: "Checking…", icon: "ellipsis", tone: SR.inkMuted)
        } else {
            WordRoomPill(text: hint, icon: store.input.isComplete ? "return" : "hand.point.up.left", tone: store.input.isComplete ? SR.accentInk : SR.inkMuted)
        }
    }

    private var hint: String {
        let line = WordRoomText.wordleHint(typed: store.input.letters.count, length: room.wordLength,
                                           guessNumber: (me?.guessCount ?? 0) + 1)
        if room.hardMode, store.input.isEmpty, (me?.guessCount ?? 0) > 0 {
            return "Hard mode: greens stay put, found letters stay in."
        }
        return line
    }

    // MARK: Bottom

    @ViewBuilder
    private func bottom(keyHeight: CGFloat) -> some View {
        Group {
            if store.canType {
                WordleKeyboardView(
                    marks: WordleKeyboard.marks(server: room.keyboard, rows: me?.rows ?? []),
                    enabled: !store.submitting,
                    ready: store.input.isComplete,
                    keyHeight: keyHeight,
                    press: { store.press($0) },
                    delete: { store.delete() },
                    submit: { store.submit() }
                )
                .padding(.horizontal, 4)
            } else {
                waitCard
                    .padding(.horizontal, SR.gutter)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(
            SR.paper.opacity(0.94)
                .overlay(alignment: .top) { Rectangle().fill(SR.line).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private var waitCard: some View {
        if let me, me.joined, me.solved {
            WordRoomWaitCard(icon: "checkmark", title: solvedLine(me.guessCount), line: waitingLine, tone: SR.good)
                .accessibilityIdentifier("wordle-waiting")
        } else if let me, me.joined {
            WordRoomWaitCard(icon: "hourglass", title: "Out of guesses", line: waitingLine, tone: SR.inkMuted)
                .accessibilityIdentifier("wordle-waiting")
        } else {
            WordRoomWaitCard(icon: "eye", title: "Watching", line: "You are not playing in this one. The word is shown at the end.", tone: SR.accentInk)
                .accessibilityIdentifier("wordle-watching")
        }
    }

    private var waitingLine: String {
        let still = room.others.filter { !$0.done && !$0.solved }.map(\.name)
        if still.isEmpty { return "Everyone is done. Here comes the word…" }
        return "Waiting for \(WordRoomText.list(still)). The word is revealed when everyone is done."
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
///
/// A scored tile is lit from above — a sheen over its top half and a darker
/// lip along its foot — so the grid reads as tiles, not flat swatches. Mini
/// tiles (the others' grids) skip the sheen: at 7 points it is only noise.
struct WordleTile: View {
    let letter: Character?
    let mark: WordleMark?
    let side: CGFloat

    private var radius: CGFloat { max(2, side * 0.12) }
    private var detailed: Bool { side >= 20 }

    var body: some View {
        ZStack {
            if let mark {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(WordlePalette.fill(mark))
                if detailed && mark != .unknown {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                                             startPoint: .top, endPoint: .center))
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                }
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(letter == nil ? Color.clear : SR.surface.opacity(0.85))
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(letter == nil ? SR.line : SR.ink.opacity(0.75), lineWidth: letter == nil ? 1.5 : 2.5)
            }
            if let letter {
                Text(String(letter).uppercased())
                    // The play field keeps its own size: a tile is a tile.
                    .font(.system(size: max(6, side * 0.54), weight: .heavy, design: .rounded))
                    .foregroundStyle(mark.map { WordlePalette.letter($0) } ?? SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(side * 0.06)
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
    /// The scored row turning over, and whether it has turned.
    var flipRow: Int? = nil
    var flipped: Bool = true
    /// The solved row jumps, tile after tile, each time `cheers` changes.
    var cheerRow: Int? = nil
    var cheers: Int = 0

    var body: some View {
        VStack(spacing: max(1.5, side * 0.12)) {
            ForEach(0..<maxGuesses, id: \.self) { index in
                rowView(index)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ index: Int) -> some View {
        let spacing = max(1.5, side * 0.12)
        if index < rows.count {
            let row = rows[index]
            let letters = row.letters
            HStack(spacing: spacing) {
                ForEach(0..<wordLength, id: \.self) { column in
                    scoredTile(row: index, column: column, letters: letters, marks: row.marks)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WordleSpeech.row(row, number: index + 1))
        } else if index == rows.count, let typing {
            HStack(spacing: spacing) {
                ForEach(0..<wordLength, id: \.self) { column in
                    let letter: Character? = column < typing.letters.count ? typing.letters[column] : nil
                    WordleTile(letter: letter, mark: nil, side: side)
                        .modifier(WordRoomPop(animatableData: letter == nil ? 0 : 1, amount: 0.12))
                        .animation(.easeOut(duration: 0.14), value: letter == nil)
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

    private func scoredTile(row: Int, column: Int, letters: [Character]?, marks: [WordleMark]) -> some View {
        let turning = row == flipRow && !flipped
        let cheering = row == cheerRow
        return WordleTile(
            letter: Self.letter(at: column, in: letters),
            mark: column < marks.count ? marks[column] : .unknown,
            side: side
        )
        .rotation3DEffect(.degrees(turning ? 90 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .animation(.easeOut(duration: 0.26).delay(0.11 * Double(column)), value: turning)
        .modifier(WordRoomPop(animatableData: cheering ? CGFloat(cheers) : 0, amount: 0.22))
        .animation(.easeOut(duration: 0.32).delay(0.6 + 0.08 * Double(column)), value: cheers)
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

/// Everyone else, as colours: their rows without letters beside their name,
/// how many guesses, and whether they have it — compact, so the grid keeps
/// the room on a small phone.
struct WordleOthersStrip: View {
    let room: GameRoom

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(room.others) { player in
                    card(player)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("wordle-others")
    }

    private func card(_ player: GamePlayer) -> some View {
        HStack(alignment: .center, spacing: 10) {
            WordleBoard(
                rows: player.rows,
                typing: nil,
                maxGuesses: room.maxGuesses,
                wordLength: room.wordLength,
                side: 7
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    GameInitial(name: player.name, tone: player.solved ? SR.good : SR.accentInk, side: 22)
                    Text(player.name)
                        .font(SR.Text.title(14))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                }
                standing(player)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                .strokeBorder(player.solved ? SR.good : Color.clear, lineWidth: 2)
        )
        .srAnimation(.snappy, value: player.guessCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(player))
        .accessibilityIdentifier("wordle-other-\(player.id)")
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
/// are 50 to 56 points tall; ten across a phone cannot also be 44 wide, so
/// they are as tall as the phone allows instead. Enter lights up once the
/// row is full — the one key to press next.
struct WordleKeyboardView: View {
    let marks: [Character: WordleMark]
    let enabled: Bool
    var ready: Bool = false
    var keyHeight: CGFloat = 56
    let press: (Character) -> Void
    let delete: () -> Void
    let submit: () -> Void

    static let rowGap: CGFloat = 8
    static let keyGap: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            keys(unit: max(20, (geo.size.width - Self.keyGap * 9) / 10))
                .frame(width: geo.size.width)
        }
        .frame(height: keyHeight * 3 + Self.rowGap * 2)
        .opacity(enabled ? 1 : 0.6)
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
                enterKey(width: unit * 1.5)
                ForEach(WordleKeyboard.rows[2], id: \.self) { letterKey($0, width: unit) }
                deleteKey(width: unit * 1.5)
            }
        }
    }

    private func keyFace(fill: Color, edge: Color, outlined: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(edge)
                .offset(y: 2)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(fill)
            if outlined {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(SR.line, lineWidth: 1)
            }
        }
    }

    private func letterKey(_ letter: Character, width: CGFloat) -> some View {
        let mark = marks[letter]
        let fill: Color = mark.map { WordlePalette.fill($0) } ?? SR.surface
        return Button {
            press(letter)
        } label: {
            ZStack {
                keyFace(fill: fill, edge: SR.ink.opacity(0.18), outlined: mark == nil)
                Text(String(letter).uppercased())
                    .font(.system(size: min(22, keyHeight * 0.4), weight: .bold, design: .rounded))
                    .foregroundStyle(mark.map { WordlePalette.letter($0) } ?? SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let mark { WordleCue(mark: mark, side: min(width, keyHeight)) }
            }
            .frame(width: width, height: keyHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(WordRoomPressStyle(depth: 0.9))
        .disabled(!enabled)
        .accessibilityLabel(mark.map { "\(String(letter).uppercased()), \($0.spoken)" } ?? String(letter).uppercased())
        .accessibilityIdentifier("wordle-key-\(letter)")
    }

    private func enterKey(width: CGFloat) -> some View {
        Button {
            submit()
        } label: {
            ZStack {
                keyFace(fill: ready ? SR.accent : SR.ink, edge: ready ? SR.accentDeep : SR.ink.opacity(0.5), outlined: false)
                Text("ENTER")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(ready ? SR.cream : SR.paper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 2)
            }
            .frame(width: width, height: keyHeight)
            .contentShape(Rectangle())
            .srAnimation(.snappy, value: ready)
        }
        .buttonStyle(WordRoomPressStyle(depth: 0.92))
        .disabled(!enabled)
        .accessibilityLabel("Enter guess")
        .accessibilityHint(ready ? "Sends your guess" : "Fill the row first")
        .accessibilityIdentifier("wordle-enter")
    }

    private func deleteKey(width: CGFloat) -> some View {
        Button {
            delete()
        } label: {
            ZStack {
                keyFace(fill: SR.ink, edge: SR.ink.opacity(0.5), outlined: false)
                Image(systemName: "delete.left.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(SR.paper)
            }
            .frame(width: width, height: keyHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(WordRoomPressStyle(depth: 0.92))
        .disabled(!enabled)
        .accessibilityLabel("Delete letter")
        .accessibilityIdentifier("wordle-delete")
    }
}

// MARK: - Finished

struct WordleFinished: View {
    let room: GameRoom
    @ObservedObject var store: WordleRaceStore
    let done: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The word has turned face up.
    @State private var revealed = false
    @State private var book: WordRoomBestBook?
    @State private var news = WordRoomNewBests()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Wordle Race · final", title: title, strap: strap)

                if let secret = room.secret, !secret.isEmpty {
                    secretCard(secret)
                }

                GameStandingsCard(
                    room: room,
                    label: room.solo ? "Your game" : "Standings",
                    id: "wordle-standings",
                    detail: detail,
                    figure: figure
                )

                if let book {
                    WordRoomBestsCard(items: bestItems(book), id: "wordle-bests")
                }

                grids

                GameFinishedButtons(room: room, store: store, prefix: "wordle", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("wordle-finished")
        .onAppear {
            recordBests()
            if reduceMotion {
                revealed = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { revealed = true }
            }
        }
    }

    /// The word, turning face up a letter at a time.
    private func secretCard(_ secret: String) -> some View {
        let letters = Array(secret.uppercased())
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "The word")
            // The largest tiles that fit across: a six- or seven-letter word
            // at 52 points would run off a 375-point phone.
            ViewThatFits(in: .horizontal) {
                secretRow(letters, side: 52)
                secretRow(letters, side: 42)
                secretRow(letters, side: 34)
                secretRow(letters, side: 26)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("The word was \(secret.uppercased())")
            .accessibilityIdentifier("wordle-secret")
        }
    }

    private func secretRow(_ letters: [Character], side: CGFloat) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<letters.count, id: \.self) { index in
                WordleTile(letter: letters[index], mark: .correct, side: side)
                    .rotation3DEffect(.degrees(revealed ? 0 : 90), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                    .opacity(revealed ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(0.12 * Double(index)), value: revealed)
            }
        }
    }

    private var grids: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: room.solo ? "Your grid" : "Everyone’s grids")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(room.playing) { player in
                    gridCard(player)
                }
            }
        }
    }

    private func gridCard(_ player: GamePlayer) -> some View {
        let winner = room.winnerIds.contains(player.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(player.name + (player.id == room.meId ? " (you)" : ""))
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                if winner, !room.solo {
                    Image(systemName: "crown.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SR.warn)
                        .accessibilityLabel("Winner")
                }
            }
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

    private func guesses(_ row: GameStanding) -> Int {
        row.guesses ?? room.players.first(where: { $0.id == row.id })?.guessCount ?? 0
    }

    private func detail(_ row: GameStanding) -> String {
        let count = guesses(row) == 1 ? "1 guess" : "\(guesses(row)) guesses"
        guard row.solved else { return "not solved · \(count)" }
        if let ms = row.solveMs { return "\(count) · \(WordleClock.duration(ms: ms))" }
        return count
    }

    private func figure(_ row: GameStanding) -> (text: String, spoken: String)? {
        guard row.solved else { return (text: "–", spoken: "not solved") }
        let n = guesses(row)
        return (text: "\(n)/\(room.maxGuesses)", spoken: n == 1 ? "solved in one guess" : "solved in \(n) guesses")
    }

    // MARK: Bests

    private func recordBests() {
        guard book == nil else { return }
        guard let me = room.me, me.joined else {
            book = nil
            return
        }
        let mine = standings.first { $0.id == room.meId }
        let round = WordRoomRound(
            key: WordRoomRound.key(roomId: room.id, startedAt: room.startedAt, deal: room.secret ?? ""),
            competitive: !room.solo,
            won: room.winnerIds.contains(room.meId),
            tracksStreak: true,
            solved: mine?.solved ?? me.solved,
            guesses: mine?.guesses ?? me.guessCount,
            solveMs: mine?.solveMs ?? me.solveMs
        )
        let result = WordRoomBestStore(game: .wordle).record(round, persist: !SRDemo.isOn)
        book = result.book
        news = result.news ?? WordRoomNewBests()
        // A win is already felt through the standings; a new best on its own
        // deserves the same tap.
        if news.any, !room.winnerIds.contains(room.meId) { SRHaptic.ok() }
    }

    private func bestItems(_ book: WordRoomBestBook) -> [WordRoomBestItem] {
        var items = [WordRoomBestItem(label: "Played", value: "\(book.played)")]
        if !room.solo || book.won > 0 {
            items.append(WordRoomBestItem(label: "Won", value: "\(book.won) · \(book.winPercent)%"))
        }
        items.append(WordRoomBestItem(label: "Fewest guesses", value: book.fewestGuesses > 0 ? "\(book.fewestGuesses)" : "–", fresh: news.guesses))
        items.append(WordRoomBestItem(label: "Fastest solve", value: WordRoomText.clock(ms: book.fastestMs), fresh: news.time))
        items.append(WordRoomBestItem(label: "Solved in a row", value: "\(book.streak) · best \(book.bestStreak)", fresh: news.streak))
        return items
    }
}
