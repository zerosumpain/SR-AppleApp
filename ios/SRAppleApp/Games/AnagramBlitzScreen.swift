import SwiftUI
import UIKit

/// One Anagram Blitz room, from lobby to the reveal.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with how to play and my bests as the lobby's panel. Playing is the letters
/// as wooden tiles on a wheel around Shuffle, the word being built in slots
/// above it with what it would score, big Delete and Enter under it, and my
/// words below; a word that lands floats its points off the slots, and one
/// that uses every letter bursts. Everyone else is a name, a word count and a
/// score — never their words — in leaderboard order until the finish reveals
/// every word found, who found it, and what nobody did.
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
                GameLobby(room: room, store: store, prefix: "anagram", done: { dismiss() },
                          panel: AnyView(AnagramBlitzHowTo(room: room)))
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

// MARK: - Lobby

/// How to play, in the lobby: a row of tiles, the rules in four lines, and
/// my best so far.
struct AnagramBlitzHowTo: View {
    let room: GameRoom
    @State private var book = WordRoomBestBook()

    var body: some View {
        WordRoomHowToCard(title: "How to play", steps: steps, best: best, id: "anagram-howto") {
            HStack(spacing: 5) {
                ForEach(Array("TRENIAP".enumerated()), id: \.offset) { item in
                    AnagramBlitzTileFace(letter: String(item.element), side: 38, picked: item.offset == 6 || item.offset == 5)
                }
            }
        }
        .onAppear { book = WordRoomBestStore(game: .anagram).load() }
    }

    private var steps: [WordRoomStep] {
        var list = [
            WordRoomStep(icon: "hand.tap.fill", text: "Tap tiles to spell a word of \(room.minLength) letters or more, then press Enter. Tap a used tile to take it back."),
            WordRoomStep(icon: "shuffle", text: "Stuck? Shuffle spins the letters round for a fresh look."),
            WordRoomStep(icon: "star.fill", text: "Longer words score more: \(AnagramRules.table(room))."),
        ]
        list.append(WordRoomStep(icon: "person.2.fill", text: "Playing with others? A word nobody else finds scores double."))
        list.append(WordRoomStep(icon: "sparkles", text: "Use all \(WordRoomText.number(room.letterCount)) letters for the big one."))
        return list
    }

    private var best: String? {
        guard book.played > 0 else { return nil }
        var parts = ["Your best: \(book.bestScore) points"]
        if !book.longest.isEmpty { parts.append("longest \(book.longest.uppercased())") }
        return parts.joined(separator: " · ")
    }
}

extension AnagramRules {
    /// "3→1 4→2 5→4 6→6 7→10", from the room's table.
    static func table(_ room: GameRoom) -> String {
        (room.minLength...max(room.minLength, room.letterCount)).map { length in
            "\(length)→\(points(for: String(repeating: "a", count: length), table: room.points))"
        }
        .joined(separator: " ")
    }
}

// MARK: - Playing

struct AnagramPlaying: View {
    let room: GameRoom
    @ObservedObject var store: AnagramBlitzStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Bumped once per word that lands: its points float off the slots.
    @State private var landedToken = 0
    @State private var floatText = ""
    /// Bumped for a word that uses every tile.
    @State private var blitz = 0

    var body: some View {
        GeometryReader { full in
            ScrollView {
                page(wheel: wheelSide(full.size))
            }
        }
        .srGround(.warm)
        .accessibilityIdentifier("anagram-playing")
        .onChange(of: store.shakes) { _, _ in
            if let refusal = store.refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
        .onChange(of: store.landed) { _, word in
            guard let word else { return }
            let full = word.word.count >= room.letterCount
            floatText = full ? "ALL \(room.letterCount)! +\(word.points)" : "+\(word.points)"
            landedToken += 1
            if full { blitz += 1 }
            UIAccessibility.post(notification: .announcement, argument: "\(word.word), \(word.points) points")
        }
    }

    /// As big as the width allows, and small enough on a short phone that
    /// Enter is still on screen without scrolling.
    private func wheelSide(_ size: CGSize) -> CGFloat {
        let reserved: CGFloat = room.others.isEmpty ? 300 : 360
        let byHeight = size.height - reserved
        let byWidth = size.width - SR.gutter * 2
        return max(230, min(340, min(byWidth, byHeight)))
    }

    private func page(wheel: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            WordRoomTimeBar(room: room, store: store)
            if !room.others.isEmpty {
                AnagramOthersStrip(room: room)
            }
            wordRow
            AnagramTiles(room: room, store: store, side: wheel)
                .overlay { WordRoomBurst(token: blitz) }
            controls
            statusLine
                .frame(maxWidth: .infinity, minHeight: 36)
            AnagramMyWords(room: room, words: store.mine)
        }
        .padding(.horizontal, SR.gutter)
        .padding(.top, 4)
        .padding(.bottom, 28)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ANAGRAM BLITZ · \(GameDifficulty.label(for: room.difficulty).uppercased())")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(room.me?.score ?? 0)")
                        .font(SR.Text.display(30))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                        .srNumeric(Double(room.me?.score ?? 0))
                    Text(GameResults.count(room.me?.wordCount ?? 0, "word", "words").uppercased())
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your score, \(room.me?.score ?? 0) points, \(GameResults.count(room.me?.wordCount ?? 0, "word", "words"))")
                .accessibilityIdentifier("anagram-my-score")
            }
            Spacer(minLength: 8)
            WordRoomClock(room: room, store: store, id: "anagram-timer")
        }
    }

    private var wordState: WordRoomWordState {
        let word = store.input.word
        return WordRoomWordState.of(word: word, minLength: room.minLength, mine: store.mine.map(\.word),
                                    points: AnagramRules.points(for: word, table: room.points))
    }

    /// The word being built, in slots — one per tile — with what it would
    /// score under it, and the points of a word that landed floating off.
    private var wordRow: some View {
        let word = store.input.word.uppercased()
        let letters = Array(word)
        let count = max(room.letterCount, store.input.letters.count, 1)
        return VStack(spacing: 8) {
            GeometryReader { geo in
                let gap: CGFloat = 6
                let side = max(26, min(48, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count)))
                HStack(spacing: gap) {
                    ForEach(0..<count, id: \.self) { index in
                        slot(index < letters.count ? String(letters[index]) : nil, side: side, next: index == letters.count)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(height: 50)
            .modifier(WordleShake(animatableData: CGFloat(reduceMotion ? 0 : store.shakes)))
            .animation(.linear(duration: 0.4), value: store.shakes)
            .overlay { WordRoomFloatUp(text: floatText, token: landedToken, tone: SR.good) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(word.isEmpty ? "Your word, empty" : "Your word, \(word)")
            .accessibilityValue(wordState.text)
            .accessibilityIdentifier("anagram-word")

            stateChip
                .frame(height: 22)
        }
    }

    private func slot(_ letter: String?, side: CGFloat, next: Bool) -> some View {
        ZStack {
            if let letter {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(LinearGradient(colors: [SR.accent, SR.accentDeep], startPoint: .top, endPoint: .bottom))
                Text(letter)
                    .font(.system(size: side * 0.55, weight: .heavy, design: .rounded))
                    .foregroundStyle(SR.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .strokeBorder(next ? SR.accent.opacity(0.7) : SR.line,
                                  style: StrokeStyle(lineWidth: next ? 2 : 1.5, dash: next ? [] : [4, 3]))
            }
        }
        .frame(width: side, height: side)
        .modifier(WordRoomPop(animatableData: letter == nil ? 0 : 1, amount: 0.14))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: letter == nil)
    }

    @ViewBuilder
    private var stateChip: some View {
        let state = wordState
        switch state {
        case .empty:
            Text("Tap the tiles to spell a word")
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
        case .short:
            Text(state.text.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
        case .have:
            Label("HAVE IT", systemImage: "checkmark.circle")
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
        case .worth(let points):
            Text("+\(points) IF IT COUNTS")
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.accentInk)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { store.delete() } label: {
                Image(systemName: "delete.left.fill")
                    .font(.title3.weight(.semibold))
            }
            .buttonStyle(WordRoomButtonStyle(tone: .soft))
            .frame(width: 96)
            .disabled(store.input.isEmpty)
            .accessibilityLabel("Delete letter")
            .accessibilityIdentifier("anagram-delete")

            Button { store.submit() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "return")
                        .font(.headline.weight(.bold))
                    Text("ENTER")
                }
            }
            .buttonStyle(WordRoomButtonStyle(tone: wordState.ready ? .go : .firm))
            .disabled(store.input.isEmpty || store.submitting)
            .accessibilityLabel("Enter")
            .accessibilityIdentifier("anagram-enter")
        }
        .disabled(!store.canPlay)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let refusal = store.refusal {
            WordRoomPill(text: refusal, icon: "exclamationmark.circle.fill", tone: SR.error)
                .accessibilityIdentifier("anagram-refusal")
        } else if let landed = store.landed {
            WordRoomPill(text: "\(landed.word.uppercased()) +\(landed.points)", icon: "checkmark.circle.fill", tone: SR.good, filled: true)
                .accessibilityIdentifier("anagram-landed")
        } else if room.me?.joined != true {
            WordRoomPill(text: "You are not playing in this one.", icon: "eye", tone: SR.inkMuted)
        } else {
            Text(rulesLine)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .multilineTextAlignment(.center)
        }
    }

    /// "3+ letters · 3→1 4→2 5→4 6→6 7→10".
    private var rulesLine: String {
        "\(room.minLength)+ letters · " + AnagramRules.table(room)
    }
}

/// One letter tile, drawn like wood: a lighter face over a darker lip, the
/// letter pressed into it. `picked` leaves only the tile's outline behind.
struct AnagramBlitzTileFace: View {
    let letter: String
    let side: CGFloat
    var picked = false

    // The tile keeps its wood in dark mode, as a real one would.
    static let face = Color(hex: 0xF6E3B4)
    static let faceLow = Color(hex: 0xE7C985)
    static let lip = Color(hex: 0xB48A45)
    static let letterInk = Color(hex: 0x3A2A12)

    var body: some View {
        let radius = side * 0.2
        ZStack {
            if picked {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(SR.ink.opacity(0.05))
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(SR.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                Text(letter)
                    .font(.system(size: side * 0.46, weight: .heavy, design: .rounded))
                    .foregroundStyle(SR.inkGhost)
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Self.lip)
                    .offset(y: max(2, side * 0.06))
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Self.face, Self.faceLow], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                Text(letter)
                    .font(.system(size: side * 0.52, weight: .heavy, design: .rounded))
                    .foregroundStyle(Self.letterInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: side, height: side)
    }
}

/// The tiles on a wheel, in the store's shuffled order, around Shuffle. A
/// picked tile stays where it is, hollow, so tapping it again takes it back
/// out; a shuffle swings every tile to its new place.
struct AnagramTiles: View {
    let room: GameRoom
    @ObservedObject var store: AnagramBlitzStore
    /// The wheel's side.
    var side: CGFloat = 300

    var body: some View {
        let order = store.order
        let count = max(order.count, 1)
        let tile = tileSide(count: count)
        let radius = side / 2 - tile / 2 - 4
        ZStack {
            Circle()
                .fill(SR.surface.opacity(0.55))
                .overlay(Circle().strokeBorder(SR.line, lineWidth: 1))
                .padding(tile * 0.18)
                .accessibilityHidden(true)
            ForEach(order, id: \.self) { index in
                let slot = order.firstIndex(of: index) ?? 0
                tileButton(index, side: tile)
                    .position(position(slot: slot, count: count, radius: radius))
            }
            shuffleButton
                .position(x: side / 2, y: side / 2)
        }
        .frame(width: side, height: side)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: order)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("anagram-tiles")
    }

    /// As big as the wheel allows, without neighbours touching.
    private func tileSide(count: Int) -> CGFloat {
        let n = CGFloat(max(count, 3))
        let guess = min(84, side * 0.25)
        let radius = side / 2 - guess / 2 - 4
        let chord = 2 * radius * CGFloat(sin(Double.pi / Double(n)))
        return max(44, min(guess, chord * 0.84))
    }

    private func position(slot: Int, count: Int, radius: CGFloat) -> CGPoint {
        let angle = -Double.pi / 2 + 2 * Double.pi * Double(slot) / Double(max(count, 1))
        return CGPoint(x: side / 2 + radius * CGFloat(cos(angle)), y: side / 2 + radius * CGFloat(sin(angle)))
    }

    private func tileButton(_ index: Int, side tile: CGFloat) -> some View {
        let letters = store.input.letters
        let letter = index < letters.count ? String(letters[index]).uppercased() : "?"
        let picked = store.input.isPicked(index)
        return Button {
            store.tap(tile: index)
        } label: {
            AnagramBlitzTileFace(letter: letter, side: tile, picked: picked)
                .scaleEffect(picked ? 0.88 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(WordRoomPressStyle(depth: 0.9))
        .disabled(!store.canPlay)
        .srAnimation(.snappy(duration: 0.18), value: picked)
        .accessibilityLabel(picked ? "\(letter), in your word" : letter)
        .accessibilityHint(picked ? "Takes it back out" : "Adds it to your word")
        .accessibilityIdentifier("anagram-tile-\(index)")
    }

    private var shuffleButton: some View {
        Button { store.shuffle() } label: {
            VStack(spacing: 2) {
                Image(systemName: "shuffle")
                    .font(.title2.weight(.bold))
                Text("SHUFFLE")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.8)
            }
            .foregroundStyle(SR.paper)
            .frame(width: 78, height: 78)
            .background(Circle().fill(SR.ink))
            .overlay(Circle().strokeBorder(SR.paper.opacity(0.25), lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(WordRoomPressStyle(depth: 0.9))
        .disabled(!store.canPlay)
        .accessibilityLabel("Shuffle")
        .accessibilityHint("Moves the tiles round")
        .accessibilityIdentifier("anagram-shuffle")
    }
}

/// Everyone else: a name, how many words, the score, in score order with the
/// leader crowned. Never the words. Boggle's strip too, under its own prefix.
struct AnagramOthersStrip: View {
    let room: GameRoom
    var prefix = "anagram"

    var body: some View {
        let entries = room.others.map { WordRoomRanking.Entry(id: $0.id, name: $0.name, score: $0.score) }
        let order = WordRoomRanking.order(entries)
        let leader = WordRoomRanking.leader(entries)
        let ranked = order.compactMap { id in room.others.first { $0.id == id } }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ranked) { player in
                    card(player, leads: player.id == leader)
                }
            }
            .padding(.vertical, 2)
            .srAnimation(.snappy, value: order)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("\(prefix)-others")
    }

    private func card(_ player: GamePlayer, leads: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                GameInitial(name: player.name, tone: leads ? SR.warn : SR.accentInk, side: 30)
                if leads {
                    Image(systemName: "crown.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SR.warn)
                        .offset(x: 5, y: -7)
                        .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
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
        .accessibilityLabel("\(player.name), \(GameResults.count(player.wordCount, "word", "words")), \(player.score) points\(leads ? ", in the lead" : "")")
        .accessibilityIdentifier("\(prefix)-other-\(player.id)")
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
                        chip(word)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .srAnimation(.snappy, value: words.count)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("anagram-my-words")
    }

    private func chip(_ word: AnagramWord) -> some View {
        let full = word.word.count >= room.letterCount
        return HStack(spacing: 6) {
            Text(word.word.uppercased())
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text("+\(word.points)")
                .font(SR.Text.label())
                .foregroundStyle(full ? SR.paper : SR.accentInk)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(full ? SR.accent : SR.accent.opacity(0.14)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(word.word), \(word.points) points")
    }
}

// MARK: - Finished

struct AnagramFinished: View {
    let room: GameRoom
    @ObservedObject var store: AnagramBlitzStore
    let done: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var book: WordRoomBestBook?
    @State private var news = WordRoomNewBests()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Anagram Blitz · final",
                             title: GameResults.title(room, solo: "You scored \(room.me?.score ?? 0)", none: "Nobody scored"),
                             strap: GameResults.strap(room))

                if let seed = room.seed, !seed.isEmpty {
                    seedCard(seed)
                }

                GameStandingsCard(
                    room: room,
                    label: room.solo ? "Your game" : "Standings",
                    id: "anagram-standings",
                    detail: detail,
                    figure: { (text: "\($0.score)", spoken: "\($0.score) points") }
                )

                if let book {
                    WordRoomBestsCard(items: bestItems(book), id: "anagram-bests")
                }

                if let found = room.found, !found.isEmpty {
                    foundCard(found)
                }

                if let missed = room.missed, !missed.isEmpty {
                    missedCard(missed)
                }

                GameFinishedButtons(room: room, store: store, prefix: "anagram", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("anagram-finished")
        .onAppear {
            recordBests()
            if reduceMotion {
                revealed = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { revealed = true }
            }
        }
    }

    /// The word the letters came from, its tiles turning over one by one.
    private func seedCard(_ seed: String) -> some View {
        let letters = Array(seed.uppercased())
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "The \(WordRoomText.number(letters.count))-letter word")
            // The largest tiles that fit across, for a deal longer than seven.
            ViewThatFits(in: .horizontal) {
                seedRow(letters, side: 42)
                seedRow(letters, side: 34)
                seedRow(letters, side: 28)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("The letters came from \(seed.uppercased())")
            .accessibilityIdentifier("anagram-seed")
        }
    }

    private func seedRow(_ letters: [Character], side: CGFloat) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<letters.count, id: \.self) { index in
                AnagramBlitzTileFace(letter: String(letters[index]), side: side)
                    .rotation3DEffect(.degrees(revealed ? 0 : 90), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .opacity(revealed ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(0.1 * Double(index)), value: revealed)
            }
        }
    }

    private func foundCard(_ found: [AnagramFound]) -> some View {
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

    private func missedCard(_ missed: [String]) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Nobody found", trailing: "\(missed.count)")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(missed, id: \.self) { word in
                    Text(word.uppercased())
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                                .strokeBorder(SR.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Nobody found: " + missed.joined(separator: ", "))
            .accessibilityIdentifier("anagram-missed")
        }
    }

    private func detail(_ row: GameStanding) -> String {
        let words = GameResults.count(row.words, "word", "words")
        guard let longest = row.longest, !longest.isEmpty else { return words }
        return "\(words) · longest \(longest.uppercased())"
    }

    private func foundRow(_ word: AnagramFound) -> some View {
        let mine = word.finderIds.contains(room.meId)
        return HStack(spacing: 10) {
            Text(word.word.uppercased())
                .font(SR.Text.title())
                .foregroundStyle(mine ? SR.accentInk : SR.ink)
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

    // MARK: Bests

    private func recordBests() {
        guard book == nil, let me = room.me, me.joined else { return }
        let mine = room.standings?.first { $0.id == room.meId }
        let myWords = me.words ?? []
        let mineLongest: String = myWords.map(\.word).max(by: { $0.count < $1.count }) ?? ""
        let longest: String = mine?.longest ?? mineLongest
        let deal = room.seed ?? (room.letters ?? []).joined()
        let round = WordRoomRound(
            key: WordRoomRound.key(roomId: room.id, startedAt: room.startedAt, deal: deal),
            competitive: !room.solo,
            won: room.winnerIds.contains(room.meId),
            score: mine?.score ?? me.score,
            words: mine?.words ?? me.wordCount,
            longest: longest
        )
        let result = WordRoomBestStore(game: .anagram).record(round, persist: !SRDemo.isOn)
        book = result.book
        news = result.news ?? WordRoomNewBests()
        if news.any, !room.winnerIds.contains(room.meId) { SRHaptic.ok() }
    }

    private func bestItems(_ book: WordRoomBestBook) -> [WordRoomBestItem] {
        var items = [
            WordRoomBestItem(label: "Best score", value: "\(book.bestScore)", fresh: news.score),
            WordRoomBestItem(label: "Longest word", value: book.longest.isEmpty ? "–" : book.longest.uppercased(), fresh: news.longest),
            WordRoomBestItem(label: "Most words", value: "\(book.bestWords)"),
            WordRoomBestItem(label: "Played", value: "\(book.played)"),
        ]
        if book.won > 0 { items.append(WordRoomBestItem(label: "Won", value: "\(book.won) · \(book.winPercent)%")) }
        return items
    }
}
