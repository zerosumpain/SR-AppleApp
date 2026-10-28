import SwiftUI

/// Anagram Blitz on one phone: the clock, seven tiles, the word being built,
/// and everyone's scores; at the end, the word the letters came from, every
/// word found and the longest ones missed.
///
/// A tile is picked by its place, not its letter (`AnagramInput`, the online
/// game's), so a word can use a letter only as often as the tiles hold it.
/// The word being built and the tile order (Shuffle) stay on this phone; only
/// Enter sends the word, and the host checks and scores it.
struct OfflineAnagramView: View {
    let context: OfflineGameContext<OfflineAnagramRules>
    @State private var input = AnagramInput()
    /// The tiles' order on screen, as indices into the letters.
    @State private var order: [Int] = []
    /// A refusal this phone can say without asking the host.
    @State private var note: String?

    private typealias Rules = OfflineAnagramRules
    private static let tileSide: CGFloat = 64

    private var view: Rules.PlayerView { context.view }
    private var revealed: Bool { view.phase == .reveal || view.phase == .over }
    private var interactive: Bool { view.phase == .playing && view.mine != nil }
    private var myScore: Int { view.board.first { $0.id == context.me }?.score ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SRPageHeader(kicker: kicker, title: title)
                    .accessibilityIdentifier("offline-anagram-header")
                clockBar
                if view.letters != nil {
                    if interactive {
                        wordRow
                        tiles
                        controls
                        statusLine
                            .frame(maxWidth: .infinity)
                    } else if let seed = view.seed {
                        seedCard(seed)
                    } else {
                        tiles
                    }
                } else {
                    Text("Shuffling the letters. Get ready.")
                        .font(SR.Text.body())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if revealed {
                    reveal
                } else if let mine = view.mine, !mine.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "Your words", trailing: "\(mine.count)")
                        OfflineWordChips(chips: mine.map { chip($0.word, points: $0.points) })
                            .accessibilityIdentifier("offline-anagram-mine")
                    }
                }
                OfflineWordScores(title: view.board.count == 1 ? "Score" : "Scores", rows: rows, me: context.me,
                                  players: context.players, id: "offline-anagram-scores")
            }
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
            if new != nil { SRHaptic.bad() }
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

    // MARK: - Building a word

    private var wordRow: some View {
        let word = input.word
        let had = view.mine?.contains { $0.word == word } ?? false
        return VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(word.isEmpty ? " " : word.uppercased())
                    .font(SR.Text.hero(34))
                    .tracking(3)
                    .foregroundStyle(had ? SR.inkGhost : SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                if word.count >= Rules.minLength && !had {
                    Text("+\(Rules.points(word))")
                        .font(SR.Text.figure(20))
                        .foregroundStyle(SR.accent)
                } else if had {
                    Text("HAVE IT")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            Rectangle().fill(SR.line).frame(height: 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word.isEmpty ? "Your word, empty" : "Your word, \(word)")
        .accessibilityIdentifier("offline-anagram-word")
    }

    /// Four tiles over three: 4 × 64 points and three gaps fit a 375-point phone.
    private var tiles: some View {
        let split = (order.count + 1) / 2
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(Array(order.prefix(split)), id: \.self) { tile($0) }
            }
            HStack(spacing: 10) {
                ForEach(Array(order.dropFirst(split)), id: \.self) { tile($0) }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.25), value: order)
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
            Text(letter)
                .font(SR.Text.display(30))
                .foregroundStyle(picked ? SR.inkGhost : SR.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: Self.tileSide, height: Self.tileSide)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(picked ? SR.surface : SR.ink)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(picked ? SR.line : Color.clear, lineWidth: 1.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!interactive)
        .accessibilityLabel(picked ? "\(letter), in your word" : letter)
        .accessibilityHint(interactive ? (picked ? "Takes it back out" : "Adds it to your word") : "")
        .accessibilityIdentifier("offline-anagram-tile-\(index)")
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                var random = SystemRandomNumberGenerator()
                order = AnagramRules.shuffled(order, using: &random)
                SRHaptic.select()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(minWidth: SR.tapTarget, minHeight: 30)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityLabel("Shuffle the tiles")
            .accessibilityIdentifier("offline-anagram-shuffle")
            Button {
                input.delete()
                SRHaptic.select()
            } label: {
                Image(systemName: "delete.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(minWidth: SR.tapTarget, minHeight: 30)
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(input.isEmpty)
            .accessibilityLabel("Delete letter")
            .accessibilityIdentifier("offline-anagram-delete")
            Button {
                submit()
            } label: {
                SRButtonLabel(title: "Enter", icon: "return", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(input.isEmpty)
            .accessibilityIdentifier("offline-anagram-enter")
        }
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
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.good)
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
            SRHaptic.bad()
            return
        }
        if view.mine?.contains(where: { $0.word == word }) == true {
            note = "You already have that one."
            SRHaptic.bad()
            return
        }
        note = nil
        context.send(.word(word))
    }

    // MARK: - The reveal

    private func seedCard(_ seed: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("THE LETTERS SPELLED")
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.accent)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(seed.uppercased())
                    .font(SR.Text.hero(34))
                    .tracking(3)
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 8)
                Text("\(view.found?.count ?? 0) of \(view.possibleWords) found")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize()
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
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
