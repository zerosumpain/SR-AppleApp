import SwiftUI

/// Anagram Blitz on one phone: the clock, seven tiles, the word being built,
/// and everyone's scores; at the end, the word the letters came from, every
/// word found and the longest ones missed.
///
/// A tile is picked by its place, not its letter (`AnagramInput`, the online
/// game's), so a word can use a letter only as often as the tiles hold it.
/// The word being built and the tile order (Shuffle) stay on this phone; only
/// Enter sends the word, and the host checks and scores it.
///
/// The tiles are ivory pieces with a lip (`PlayTableLetterTile`), sized from
/// the page's width — four across fill a 375pt phone and grow on a big one.
/// A picked tile presses down into the table and a small copy drops into the
/// rack above, which has one slot per tile so the word's length reads at a
/// glance. A word this phone already knows is wrong shakes the rack; a word
/// the host scores pops up as a "+3" with a success tap.
struct OfflineAnagramView: View {
    let context: OfflineGameContext<OfflineAnagramRules>
    @State private var input = AnagramInput()
    /// The tiles' order on screen, as indices into the letters.
    @State private var order: [Int] = []
    /// A refusal this phone can say without asking the host.
    @State private var note: String?
    /// Bumped to shake the rack.
    @State private var shakes = 0
    /// The page's content width, for sizing tiles.
    @State private var width: CGFloat = 335
    @ObservedObject private var results = OfflineResultStore.shared

    private typealias Rules = OfflineAnagramRules
    private static let gap: CGFloat = 10

    private var view: Rules.PlayerView { context.view }
    private var revealed: Bool { view.phase == .reveal || view.phase == .over }
    private var interactive: Bool { view.phase == .playing && view.mine != nil }
    private var myScore: Int { view.board.first { $0.id == context.me }?.score ?? 0 }

    /// Four tiles over three, as big as the width allows.
    private var tileSide: CGFloat {
        max(52, min(84, (width - 3 * Self.gap) / 4))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SRPageHeader(kicker: kicker, title: title)
                    .accessibilityIdentifier("offline-anagram-header")
                clockBar
                play
                if revealed {
                    reveal
                } else if let mine = view.mine, !mine.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "Your words", trailing: "\(mine.count)")
                        OfflineWordChips(chips: mine.map { chip($0.word, points: $0.points) })
                            .accessibilityIdentifier("offline-anagram-mine")
                    }
                }
                if revealed { bestCard }
                OfflineWordScores(title: view.board.count == 1 ? "Score" : "Scores", rows: rows, me: context.me,
                                  players: context.players, id: "offline-anagram-scores")
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { width = geo.size.width }
                        .onChange(of: geo.size.width) { _, new in width = new }
                }
            )
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .onAppear { deal(view.letters) }
        .onChange(of: view.letters) { _, new in deal(new) }
        .onChange(of: view.mine?.count) { old, new in
            if (new ?? 0) > (old ?? 0) { SRHaptic.ok() }
        }
        .onChange(of: context.refusal) { _, new in
            if new != nil {
                SRHaptic.bad()
                shakes += 1
            }
        }
        .onChange(of: view.phase) { _, new in
            input.clear()
            note = nil
            if new == .playing { SRHaptic.select() }
            if new == .reveal { SRHaptic.ok() }
        }
    }

    /// New letters: a fresh word and the tiles in the order dealt.
    private func deal(_ letters: [String]?) {
        let letters = letters ?? []
        guard input.letters.map({ String($0) }) != letters else { return }
        input = AnagramInput(tiles: letters)
        order = Array(letters.indices)
        note = nil
    }

    // MARK: - Words

    private var kicker: String {
        guard let mine = view.mine else { return "Anagram Blitz · watching" }
        return "Anagram Blitz · \(mine.count == 1 ? "1 word" : "\(mine.count) words")"
    }

    private var title: String {
        switch view.phase {
        case .countdown: return "Ready…"
        case .playing: return view.mine == nil ? "Spelling" : "\(myScore) points"
        case .reveal, .over:
            guard let top = view.board.first else { return "Time's up" }
            if view.board.count == 1 { return "\(top.score) points" }
            if view.board.filter({ $0.score == top.score }).count > 1 { return "A tie" }
            return top.id == context.me ? "You win" : "\(top.name) wins"
        }
    }

    private var clockBar: some View {
        switch view.phase {
        case .countdown:
            return OfflineWordClock(clock: context.clock, label: "Starting in", until: view.startsAt, tone: SR.accent)
        case .playing:
            return OfflineWordClock(clock: context.clock, label: "Time left", until: view.endsAt,
                                    chip: view.doubling ? "unique words double" : nil)
        case .reveal, .over:
            return OfflineWordClock(clock: context.clock, label: "Time's up", until: nil)
        }
    }

    // MARK: - The table

    @ViewBuilder
    private var play: some View {
        if view.letters != nil {
            if interactive {
                wordRow
                tiles
                controls
                statusLine
                    .frame(maxWidth: .infinity)
                    .srAnimation(.spring(response: 0.35, dampingFraction: 0.6), value: view.mine?.first?.word)
            } else if let seed = view.seed {
                seedCard(seed)
            } else {
                tiles
            }
        } else {
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { _ in
                        PlayTableLetterTile(letter: "?", side: max(30, min(44, (width - 36) / 7)), state: .used)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
                Text("Shuffling the letters. Get ready.")
                    .font(SR.Text.body())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Building a word

    private var wordRow: some View {
        let word = input.word
        let had = view.mine?.contains { $0.word == word } ?? false
        let letters = word.uppercased().map { String($0) }
        return VStack(spacing: 8) {
            PlayTableRack(letters: letters, slots: max(input.letters.count, 1), maxSlot: 40)
                .modifier(PlayTableShake(animatableData: CGFloat(shakes)))
                .srAnimation(.linear(duration: 0.4), value: shakes)
            HStack(spacing: 8) {
                if word.count >= Rules.minLength && !had {
                    Text("+\(Rules.points(word))")
                        .font(SR.Text.figure(20))
                        .foregroundStyle(SR.accent)
                        .transition(.scale.combined(with: .opacity))
                } else if had {
                    Text("HAVE IT")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                } else if !word.isEmpty {
                    Text("\(Rules.minLength)+ LETTERS")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                }
            }
            .frame(minHeight: 26)
            .srAnimation(.snappy(duration: 0.2), value: word)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word.isEmpty ? "Your word, empty" : "Your word, \(word)")
        .accessibilityIdentifier("offline-anagram-word")
    }

    /// Four tiles over three, sized from the page's width.
    private var tiles: some View {
        let split = (order.count + 1) / 2
        return VStack(spacing: Self.gap) {
            HStack(spacing: Self.gap) {
                ForEach(Array(order.prefix(split)), id: \.self) { tile($0) }
            }
            HStack(spacing: Self.gap) {
                ForEach(Array(order.dropFirst(split)), id: \.self) { tile($0) }
            }
        }
        .frame(maxWidth: .infinity)
        .srAnimation(.spring(response: 0.35, dampingFraction: 0.72), value: order)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-anagram-tiles")
    }

    private func tile(_ index: Int) -> some View {
        let letters = input.letters
        let letter = index < letters.count ? String(letters[index]).uppercased() : "?"
        let picked = input.isPicked(index)
        return Button {
            note = nil
            input.tap(index)
            SRHaptic.select()
        } label: {
            PlayTableLetterTile(letter: letter, side: tileSide, state: picked ? .used : .ready,
                                points: OfflineAnagramView.letterValue(letter))
                .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .disabled(!interactive)
        .srAnimation(.snappy(duration: 0.15), value: picked)
        .accessibilityLabel(picked ? "\(letter), in your word" : letter)
        .accessibilityHint(interactive ? (picked ? "Takes it back out" : "Adds it to your word") : "")
        .accessibilityIdentifier("offline-anagram-tile-\(index)")
    }

    /// The figure printed in a tile's corner: a word-game tile's look. Not a
    /// score — words score by length (`Rules.points`).
    static func letterValue(_ letter: String) -> Int? {
        switch letter {
        case "A", "E", "I", "O", "U", "L", "N", "S", "T", "R": return 1
        case "D", "G": return 2
        case "B", "C", "M", "P": return 3
        case "F", "H", "V", "W", "Y": return 4
        case "K": return 5
        case "J", "X": return 8
        case "Q", "Z": return 10
        default: return nil
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            iconButton("shuffle", label: "Shuffle the tiles", id: "offline-anagram-shuffle", enabled: true) {
                var random = SystemRandomNumberGenerator()
                order = AnagramRules.shuffled(order, using: &random)
            }
            iconButton("delete.left", label: "Delete letter", id: "offline-anagram-delete", enabled: !input.isEmpty) {
                input.delete()
            }
            PlayTableButton(title: "Enter", icon: "return", haptic: .none) {
                submit()
            }
            .disabled(input.isEmpty)
            .accessibilityIdentifier("offline-anagram-enter")
        }
    }

    private func iconButton(_ icon: String, label: String, id: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            Image(systemName: icon)
                .font(SR.Text.title(20))
                .frame(width: PlayTableMetrics.bigLabel, height: PlayTableMetrics.bigLabel)
        }
        .srButton(.regular)
        .controlSize(.large)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let note {
            Label(note, systemImage: "exclamationmark.circle")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.error)
                .multilineTextAlignment(.center)
        } else if let last = view.mine?.first {
            Label("\(last.word.uppercased()) +\(last.points)", systemImage: "checkmark.circle.fill")
                .font(SR.Text.title(16))
                .foregroundStyle(SR.good)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(SR.good.opacity(0.14)))
                .id(last.word)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityIdentifier("offline-anagram-landed")
        } else {
            Text("Tap letters, then Enter. \(Rules.minLength)+ letters; all seven make a word.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Sends the word, unless this phone already knows the answer.
    private func submit() {
        let word = input.word
        input.clear()
        guard interactive, !word.isEmpty else { return }
        if word.count < Rules.minLength {
            note = "Words need at least \(Rules.minLength) letters."
            refuse()
            return
        }
        if view.mine?.contains(where: { $0.word == word }) == true {
            note = "You already have that one."
            refuse()
            return
        }
        SRHaptic.tap()
        note = nil
        context.send(.word(word))
    }

    private func refuse() {
        SRHaptic.bad()
        shakes += 1
    }

    // MARK: - The reveal

    private func seedCard(_ seed: String) -> some View {
        let letters = seed.uppercased().map { String($0) }
        let count: CGFloat = CGFloat(max(letters.count, 1))
        let gaps: CGFloat = 6 * CGFloat(max(letters.count - 1, 0))
        let room: CGFloat = width - 2 * SR.cardPadding - gaps
        let side: CGFloat = max(28, min(46, room / count))
        return VStack(alignment: .leading, spacing: 10) {
            Text("THE LETTERS SPELLED")
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.accent)
            HStack(spacing: 6) {
                ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                    OfflineAnagramSeedTile(letter: letter, side: side, delay: PlayTableMath.stagger(index: index, step: 0.07, cap: 0.6))
                }
            }
            .frame(maxWidth: .infinity)
            Text("\(view.found?.count ?? 0) of \(view.possibleWords) found")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The letters spelled \(seed). \(view.found?.count ?? 0) of \(view.possibleWords) found")
        .accessibilityIdentifier("offline-anagram-seed")
    }

    @ViewBuilder
    private var reveal: some View {
        if let found = view.found, !found.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Every word found", trailing: view.doubling ? "unique ones double" : "\(found.count)")
                OfflineWordChips(chips: found.map { word in
                    OfflineWordChip(id: word.word, text: word.unique ? "\(word.word.uppercased()) ×2" : word.word.uppercased(),
                                    points: word.points, spoken: spoken(word))
                })
                .accessibilityIdentifier("offline-anagram-found")
            }
        } else {
            Text("Nobody found a word this time.")
                .font(SR.Text.body())
                .foregroundStyle(SR.inkSecondary)
        }
        if let missed = view.missed, !missed.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Nobody found")
                OfflineWordChips(chips: missed.map { chip($0, points: Rules.points($0), missed: true) })
                    .accessibilityIdentifier("offline-anagram-missed")
            }
        }
        if view.mine != nil, view.phase == .reveal {
            OfflineWordContinue(ready: view.board.first { $0.id == context.me }?.ready ?? false,
                                waitingOn: view.board.filter { !$0.ready && !$0.away && $0.id != context.me }.map(\.name),
                                id: "offline-anagram-continue") {
                context.send(.ready)
            }
        }
    }

    /// This round against this phone's best at the game.
    @ViewBuilder
    private var bestCard: some View {
        if view.mine != nil {
            PlayTableBestStrip(score: myScore, best: results.queue.tallies[Rules.info.id]?.best)
        }
    }

    private func chip(_ word: String, points: Int, missed: Bool = false) -> OfflineWordChip {
        OfflineWordChip(id: word, text: word.uppercased(), points: points,
                        spoken: "\(word), \(points) \(points == 1 ? "point" : "points")\(missed ? ", nobody found it" : "")")
    }

    private func spoken(_ word: Rules.Reveal) -> String {
        let names = word.finders.map { $0 == context.me ? "you" : context.name(of: $0) }
        let unique = word.unique ? ", nobody else found it, doubled" : ""
        return "\(word.word), found by \(names.joined(separator: " and "))\(unique), \(word.points) points"
    }

    // MARK: - Scores

    private var rows: [OfflineWordScoreRow] {
        view.board.map { row in
            OfflineWordScoreRow(id: row.id, name: row.name, detail: row.words == 1 ? "1 word" : "\(row.words) words",
                                score: row.score, away: row.away, ready: revealed && row.ready)
        }
    }
}

/// One letter of the seed word, turning over into place after `delay`.
struct OfflineAnagramSeedTile: View {
    let letter: String
    let side: CGFloat
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let up = shown || reduceMotion
        return PlayTableLetterTile(letter: letter, side: side, state: .shown)
            .rotation3DEffect(.degrees(up ? 0 : 90), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .opacity(up ? 1 : 0)
            .onAppear {
                guard !reduceMotion, !shown else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(delay)) { shown = true }
            }
    }
}
