import SwiftUI
import UIKit

/// One Anagram Blitz room, from lobby to the reveal.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`).
/// Playing is the seven letters as large tiles, the word being built above
/// them, Shuffle / Delete / Enter under them, and my words below; everyone
/// else is a name, a word count and a score — never their words — until the
/// finish reveals every word found, who found it, and what nobody did.
struct AnagramBlitzScreen: View {
    let roomId: String
    @StateObject private var store: AnagramBlitzStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: AnagramBlitzStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Anagram Blitz")
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
        guard !store.ended, let phase = store.room?.phase else { return false }
        return phase == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "anagram-ended", done: { dismiss() })
        } else if let room = store.room {
            switch room.phase {
            case .lobby, .unknown, .armed, .result, .question, .reveal, .show, .input, .review:
                GameLobby(room: room, store: store, prefix: "anagram", done: { dismiss() })
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Same seven letters for everyone. Longer words score more.",
                                  id: "anagram-countdown")
            case .playing:
                AnagramPlaying(room: room, store: store)
            case .finished:
                AnagramFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "anagram-ended", done: { dismiss() })
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

struct AnagramPlaying: View {
    let room: GameRoom
    @ObservedObject var store: AnagramBlitzStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !room.others.isEmpty {
                    AnagramOthersStrip(room: room)
                }
                wordRow
                AnagramTiles(room: room, store: store)
                controls
                statusLine
                    .frame(maxWidth: .infinity)
                AnagramMyWords(room: room, words: store.mine)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("anagram-playing")
        .onChange(of: store.shakes) { _, _ in
            if let refusal = store.refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ANAGRAM BLITZ · \(GameDifficulty.label(for: room.difficulty).uppercased())")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(room.me?.score ?? 0)")
                        .font(SR.Text.display(26))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                    Text(GameResults.count(room.me?.wordCount ?? 0, "word", "words").uppercased())
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your score, \(room.me?.score ?? 0) points, \(GameResults.count(room.me?.wordCount ?? 0, "word", "words"))")
                .accessibilityIdentifier("anagram-my-score")
            }
            Spacer(minLength: 8)
            WordleTimer(room: room, store: store, id: "anagram-timer")
        }
    }

    /// The word being built, letter by letter, over a rule.
    private var wordRow: some View {
        let word = store.input.word.uppercased()
        return VStack(spacing: 6) {
            Text(word.isEmpty ? " " : word)
                .font(SR.Text.hero(40))
                .tracking(4)
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: 52)
            Rectangle().fill(SR.line).frame(height: 1.5)
        }
        .modifier(WordleShake(animatableData: CGFloat(reduceMotion ? 0 : store.shakes)))
        .animation(.linear(duration: 0.4), value: store.shakes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word.isEmpty ? "Your word, empty" : "Your word, \(word)")
        .accessibilityIdentifier("anagram-word")
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { store.shuffle() } label: {
                SRButtonLabel(title: "Shuffle", icon: "shuffle", fill: true)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("anagram-shuffle")
            Button { store.delete() } label: {
                Image(systemName: "delete.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(minWidth: SR.tapTarget, minHeight: 30)
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(store.input.isEmpty)
            .accessibilityLabel("Delete letter")
            .accessibilityIdentifier("anagram-delete")
            Button { store.submit() } label: {
                SRButtonLabel(title: "Enter", icon: "return", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(store.input.isEmpty || store.submitting)
            .accessibilityIdentifier("anagram-enter")
        }
        .disabled(!store.canPlay)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let refusal = store.refusal {
            Label(refusal, systemImage: "exclamationmark.circle")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.error)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("anagram-refusal")
        } else if let landed = store.landed {
            Label("\(landed.word.uppercased()) +\(landed.points)", systemImage: "checkmark.circle.fill")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.good)
                .accessibilityIdentifier("anagram-landed")
        } else if room.me?.joined != true {
            Text("You are not playing in this one.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
        } else {
            Text(rulesLine)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .multilineTextAlignment(.center)
        }
    }

    /// "3+ letters · 3→1 4→2 5→4 6→6 7→10".
    private var rulesLine: String {
        let table = (room.minLength...max(room.minLength, room.letterCount)).map { length in
            "\(length)→\(AnagramRules.points(for: String(repeating: "a", count: length), table: room.points))"
        }
        return "\(room.minLength)+ letters · " + table.joined(separator: " ")
    }
}

/// The seven tiles, in two rows, in the store's shuffled order. A picked tile
/// stays where it is, dimmed and ticked, so tapping it again takes it back out.
struct AnagramTiles: View {
    let room: GameRoom
    @ObservedObject var store: AnagramBlitzStore

    static let side: CGFloat = 72

    var body: some View {
        let order = store.order
        let split = (order.count + 1) / 2
        VStack(spacing: 10) {
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
        .accessibilityIdentifier("anagram-tiles")
    }

    private func tile(_ index: Int) -> some View {
        let letters = store.input.letters
        let letter = index < letters.count ? String(letters[index]).uppercased() : "?"
        let picked = store.input.isPicked(index)
        return Button {
            store.tap(tile: index)
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(picked ? SR.surface : SR.ink)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(picked ? SR.line : Color.clear, lineWidth: 1.5)
                Text(letter)
                    .font(SR.Text.display(34))
                    .foregroundStyle(picked ? SR.inkGhost : SR.paper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if picked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SR.accent)
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: Self.side, height: Self.side)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!store.canPlay)
        .accessibilityLabel(picked ? "\(letter), in your word" : letter)
        .accessibilityHint(picked ? "Takes it back out" : "Adds it to your word")
        .accessibilityIdentifier("anagram-tile-\(index)")
    }
}

/// Everyone else: a name, how many words, the score. Never the words.
/// Boggle's strip too, under its own prefix.
struct AnagramOthersStrip: View {
    let room: GameRoom
    var prefix = "anagram"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(room.others) { player in
                    HStack(spacing: 10) {
                        GameInitial(name: player.name, side: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name)
                                .font(SR.Text.title(14))
                                .foregroundStyle(SR.ink)
                                .lineLimit(1)
                            Text("\(GameResults.count(player.wordCount, "word", "words")) · \(player.score)")
                                .font(SR.Text.label())
                                .foregroundStyle(SR.inkSecondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(player.name), \(GameResults.count(player.wordCount, "word", "words")), \(player.score) points")
                    .accessibilityIdentifier("\(prefix)-other-\(player.id)")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("\(prefix)-others")
    }
}

/// My words, newest first, with their points.
struct AnagramMyWords: View {
    let room: GameRoom
    let words: [AnagramWord]

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Your words", trailing: words.isEmpty ? nil : "\(words.count)")
            if words.isEmpty {
                Text("Tap the letters to make a word, then Enter.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(AnagramRules.newestFirst(words)) { word in
                        HStack(spacing: 6) {
                            Text(word.word.uppercased())
                                .font(SR.Text.bodyMedium(15))
                                .foregroundStyle(SR.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer(minLength: 4)
                            Text("+\(word.points)")
                                .font(SR.Text.label())
                                .foregroundStyle(SR.accent)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 2)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(word.word), \(word.points) points")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("anagram-my-words")
    }
}

// MARK: - Finished

struct AnagramFinished: View {
    let room: GameRoom
    @ObservedObject var store: AnagramBlitzStore
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Anagram Blitz · final",
                             title: GameResults.title(room, solo: "You scored \(room.me?.score ?? 0)", none: "Nobody scored"),
                             strap: GameResults.strap(room))

                if let seed = room.seed, !seed.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "The seven-letter word")
                        HStack(spacing: 6) {
                            ForEach(Array(seed.uppercased().enumerated()), id: \.offset) { _, letter in
                                Text(String(letter))
                                    .font(SR.Text.display(22))
                                    .foregroundStyle(SR.paper)
                                    .frame(width: 40, height: 40)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SR.good))
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("The letters came from \(seed.uppercased())")
                        .accessibilityIdentifier("anagram-seed")
                    }
                }

                GameStandingsCard(
                    room: room,
                    label: room.solo ? "Your game" : "Standings",
                    id: "anagram-standings",
                    detail: detail,
                    figure: { (text: "\($0.score)", spoken: "\($0.score) points") }
                )

                if let found = room.found, !found.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "Every word found", trailing: "\(found.count)")
                        VStack(spacing: 0) {
                            ForEach(Array(found.enumerated()), id: \.element.id) { index, word in
                                if index > 0 { Divider().overlay(SR.divider) }
                                foundRow(word)
                            }
                        }
                        .padding(.horizontal, SR.cardPadding)
                        .padding(.vertical, 6)
                        .srGlassCard(.paper)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("anagram-found")
                    }
                }

                if let missed = room.missed, !missed.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "Nobody found")
                        Text(missed.map { $0.uppercased() }.joined(separator: " · "))
                            .font(SR.Text.bodyMedium(16))
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("anagram-missed")
                    }
                }

                GameFinishedButtons(room: room, store: store, prefix: "anagram", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("anagram-finished")
        .onAppear { if room.winnerIds.contains(room.meId) { SRHaptic.ok() } }
    }

    private func detail(_ row: GameStanding) -> String {
        let words = GameResults.count(row.words, "word", "words")
        guard let longest = row.longest, !longest.isEmpty else { return words }
        return "\(words) · longest \(longest.uppercased())"
    }

    private func foundRow(_ word: AnagramFound) -> some View {
        HStack(spacing: 10) {
            Text(word.word.uppercased())
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if word.unique {
                Text("UNIQUE ×2")
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(SR.paper)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(SR.accent))
            }
            Spacer(minLength: 8)
            HStack(spacing: -6) {
                ForEach(word.finderIds, id: \.self) { id in
                    GameInitial(name: id == room.meId ? "You" : room.name(of: id),
                                tone: id == room.meId ? SR.accent : SR.accentInk)
                        .overlay(Circle().strokeBorder(SR.paper, lineWidth: 1.5))
                }
            }
            Text("\(word.scored)")
                .font(SR.Text.figure(18))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
                .frame(minWidth: 28, alignment: .trailing)
        }
        .frame(minHeight: SR.tapTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(word))
    }

    private func spoken(_ word: AnagramFound) -> String {
        let who = GameNames.list(word.finderIds.map { $0 == room.meId ? "you" : room.name(of: $0) })
        let unique = word.unique ? ", unique, double points" : ""
        return "\(word.word), found by \(who)\(unique), \(word.scored) points"
    }
}
