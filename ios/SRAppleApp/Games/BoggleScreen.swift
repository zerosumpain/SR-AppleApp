import SwiftUI
import UIKit

/// One Boggle room, from lobby to the reveal.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the round the host picked — grid, clock, scoring — as the lobby's panel.
/// Playing is the board of dice, filling the width: drag a finger through
/// touching letters and lift to send the word, or tap the tiles one at a time
/// and press Enter. Everyone else is a name, a word count and a score until the
/// finish reveals every word found, who found it, what was crossed out, and the
/// best words nobody saw — any of which lights its path on the board.
struct BoggleScreen: View {
    let roomId: String
    @StateObject private var store: BoggleStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: BoggleStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Boggle")
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
            GameEndedView(id: "boggle-ended", done: { dismiss() })
        } else if let room = store.room {
            switch room.phase {
            case .lobby, .unknown, .armed, .result, .question, .reveal, .show, .input:
                GameLobby(room: room, store: store, prefix: "boggle", done: { dismiss() },
                          panel: AnyView(BoggleRoundCard(room: room)))
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Drag through touching letters. Lift to send the word.",
                                  id: "boggle-countdown")
            case .playing:
                BogglePlaying(room: room, store: store)
            case .finished:
                BoggleFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "boggle-ended", done: { dismiss() })
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

/// The round the host picked, in the lobby: a little empty tray of the right
/// size beside grid, clock and scoring.
struct BoggleRoundCard: View {
    let room: GameRoom

    var body: some View {
        let scoring = BoggleScoring.from(room.scoring)
        HStack(alignment: .center, spacing: 16) {
            tray
            VStack(alignment: .leading, spacing: 4) {
                Text(BoggleSettings.about(room).uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text(scoring.label)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(scoring.line)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(room.minLength)+ letters")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Round: \(BoggleSettings.about(room)). \(scoring.label). \(scoring.line) Words of \(room.minLength) letters or more.")
        .accessibilityIdentifier("boggle-round")
    }

    private var tray: some View {
        let n = room.size
        let side: CGFloat = 64
        let gap: CGFloat = 2
        let cell = (side - gap * CGFloat(n - 1)) / CGFloat(n)
        return VStack(spacing: gap) {
            ForEach(0..<n, id: \.self) { _ in
                HStack(spacing: gap) {
                    ForEach(0..<n, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(SR.paper)
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(SR.accentDeep))
        .accessibilityHidden(true)
    }
}

// MARK: - Playing

struct BogglePlaying: View {
    let room: GameRoom
    @ObservedObject var store: BoggleStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                BoggleTimeBar(room: room, store: store)
                if !room.others.isEmpty {
                    AnagramOthersStrip(room: room, prefix: "boggle")
                }
                wordRow
                BoggleBoard(room: room, store: store, interactive: true)
                controls
                statusLine
                    .frame(maxWidth: .infinity)
                BoggleMyWords(words: store.mine)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        // A drag on the board must trace, not scroll the page.
        .scrollDisabled(!store.trace.isEmpty)
        .srGround(.warm)
        .accessibilityIdentifier("boggle-playing")
        .onChange(of: store.shakes) { _, _ in
            if let refusal = store.refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BOGGLE · \(BoggleSettings.sizeLabel(room.size)) · \(GameDifficulty.label(for: room.difficulty).uppercased())")
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
                .accessibilityIdentifier("boggle-my-score")
            }
            Spacer(minLength: 8)
            WordleTimer(room: room, store: store, id: "boggle-timer")
        }
    }

    /// The word being traced, with what it would score, over a rule.
    private var wordRow: some View {
        let word = store.word
        let shown = BoggleRules.display(word)
        let long = word.count >= room.minLength
        let had = store.mine.contains { $0.word == word }
        return VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(word.isEmpty ? " " : shown.uppercased())
                    .font(SR.Text.hero(36))
                    .tracking(3)
                    .foregroundStyle(had ? SR.inkGhost : SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                if long && !had {
                    Text("+\(BoggleRules.points(for: word, table: room.points))")
                        .font(SR.Text.figure(20))
                        .foregroundStyle(SR.accent)
                        .monospacedDigit()
                        .transition(.opacity)
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
        .modifier(WordleShake(animatableData: CGFloat(reduceMotion ? 0 : store.shakes)))
        .animation(.linear(duration: 0.4), value: store.shakes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word.isEmpty ? "Your word, empty" : "Your word, \(word)")
        .accessibilityIdentifier("boggle-word")
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { store.rotate() } label: {
                Image(systemName: "rotate.right")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(minWidth: SR.tapTarget, minHeight: 30)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityLabel("Turn the board")
            .accessibilityIdentifier("boggle-rotate")
            Button { store.delete() } label: {
                Image(systemName: "delete.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(minWidth: SR.tapTarget, minHeight: 30)
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(store.trace.isEmpty)
            .accessibilityLabel("Delete letter")
            .accessibilityIdentifier("boggle-delete")
            Button { store.submit() } label: {
                SRButtonLabel(title: "Enter", icon: "return", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(store.trace.path.count < 2)
            .accessibilityIdentifier("boggle-enter")
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
                .accessibilityIdentifier("boggle-refusal")
        } else if let landed = store.landed {
            Label("\(BoggleRules.display(landed.word).uppercased()) +\(landed.points)", systemImage: "checkmark.circle.fill")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.good)
                .accessibilityIdentifier("boggle-landed")
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

    /// "3+ letters · 3–4→1 5→2 6→3 7→5 8+→11 · shared words cross out".
    private var rulesLine: String {
        let t = { (n: Int) in BoggleRules.points(for: String(repeating: "a", count: n), table: room.points) }
        var table = room.minLength <= 3 ? ["3–4→\(t(3))"] : ["4→\(t(4))"]
        table += ["5→\(t(5))", "6→\(t(6))", "7→\(t(7))", "8+→\(t(8))"]
        var line = "\(room.minLength)+ letters · " + table.joined(separator: " ")
        if BoggleScoring.from(room.scoring) == .classic, !room.solo { line += " · shared words cross out" }
        return line
    }
}

/// The sand running out: a bar that empties towards the limit and warms as it goes.
struct BoggleTimeBar: View {
    let room: GameRoom
    @ObservedObject var store: BoggleStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let left = fraction
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.line)
                    Capsule()
                        .fill(left < 0.17 ? SR.error : left < 0.34 ? SR.accent : SR.good)
                        .frame(width: geo.size.width * left)
                        .animation(.linear(duration: 0.25), value: left)
                }
            }
            .frame(height: 5)
        }
        .accessibilityHidden(true)
    }

    private var fraction: CGFloat {
        guard let end = room.phaseEndsAt, let limit = room.timeLimitMs, limit > 0,
              let now = store.serverNow() else { return 1 }
        return CGFloat(min(1, max(0, (end - now) / limit)))
    }
}

/// The dice. While playing it takes a finger: a drag through touching tiles
/// traces a word and lifting sends it; a touch that never leaves its tile is a
/// tap, which builds a word one tile at a time. Finished, it is still, and
/// lights the path of whichever word was picked below.
///
/// Every tile is also an accessibility button (a VoiceOver double-tap is a
/// tap), labelled with its letter and where it sits in the word.
struct BoggleBoard: View {
    let room: GameRoom
    @ObservedObject var store: BoggleStore
    let interactive: Bool

    /// Space between dice.
    static let gap: CGFloat = 6
    /// A drag's first tile, until the finger moves to another.
    @State private var touchStart: Int?
    /// The finger has moved off its first tile: this is a drag, not a tap.
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let side = BoggleRules.tileSide(width: geo.size.width - 12, size: room.size, gap: Self.gap)
            let boardSide = side * CGFloat(room.size) + Self.gap * CGFloat(room.size - 1)
            board(side: side)
                .frame(width: boardSide, height: boardSide)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(SR.accentDeep)
                        .shadow(color: SR.ink.opacity(0.18), radius: 8, y: 4)
                )
                .frame(maxWidth: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("boggle-board")
    }

    private var path: [Int] { interactive ? store.trace.path : store.highlightedPath }

    private func board(side: CGFloat) -> some View {
        let n = room.size
        let grid = room.grid ?? Array(repeating: "", count: n * n)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: Self.gap) {
                ForEach(0..<n, id: \.self) { row in
                    HStack(spacing: Self.gap) {
                        ForEach(0..<n, id: \.self) { column in
                            let tile = BoggleRules.tile(atDisplay: row * n + column, size: n, turns: store.turns)
                            die(tile, face: tile < grid.count ? grid[tile] : "", side: side)
                        }
                    }
                }
            }
            traceLine(side: side)
                .allowsHitTesting(false)
        }
        .animation(.snappy(duration: 0.3), value: store.turns)
        .contentShape(Rectangle())
        .highPriorityGesture(drag(side: side), including: interactive ? .all : .subviews)
    }

    private func centre(of tile: Int, side: CGFloat) -> CGPoint {
        let shown = BoggleRules.displayed(tile, size: room.size, turns: store.turns)
        let (row, column) = BoggleRules.cell(shown, size: room.size)
        let pitch = side + Self.gap
        return CGPoint(x: CGFloat(column) * pitch + side / 2, y: CGFloat(row) * pitch + side / 2)
    }

    /// The trace, as one line through the centres of its tiles.
    private func traceLine(side: CGFloat) -> some View {
        let points = path.map { centre(of: $0, side: side) }
        return Path { line in
            guard let first = points.first else { return }
            line.move(to: first)
            for point in points.dropFirst() { line.addLine(to: point) }
        }
        .stroke(interactive ? SR.accent.opacity(0.55) : SR.accentInk.opacity(0.6),
                style: StrokeStyle(lineWidth: max(8, side * 0.22), lineCap: .round, lineJoin: .round))
    }

    private func die(_ tile: Int, face: String, side: CGFloat) -> some View {
        let at = path.firstIndex(of: tile)
        let lit = at != nil
        let last = interactive && tile == path.last
        let pressed = interactive && touchStart == tile && !dragging && !lit
        let text = BoggleRules.display(face)
        let fill: Color = lit ? (interactive ? SR.accent : SR.accentInk) : pressed ? SR.surface : SR.paper
        return ZStack {
            RoundedRectangle(cornerRadius: side * 0.2, style: .continuous)
                .fill(fill)
                .shadow(color: SR.ink.opacity(lit ? 0 : 0.22), radius: 0, x: 0, y: 2)
            RoundedRectangle(cornerRadius: side * 0.2, style: .continuous)
                .strokeBorder(last ? SR.paper : SR.ink.opacity(0.08), lineWidth: last ? 3 : 1)
            Text(text.isEmpty ? " " : text)
                .font(SR.Text.display(text.count > 1 ? side * 0.4 : side * 0.52))
                .foregroundStyle(lit ? SR.paper : SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 3)
            if let at, !interactive || path.count > 1 {
                Text("\(at + 1)")
                    .font(SR.Text.label(max(9, side * 0.16)))
                    .foregroundStyle(SR.paper.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(side * 0.08)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side)
        .scaleEffect(last ? 1.06 : 1)
        .animation(.snappy(duration: 0.12), value: last)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(text, at: at))
        .accessibilityAddTraits(interactive ? .isButton : [])
        .accessibilityAddTraits(lit ? .isSelected : [])
        .accessibilityHint(interactive ? (tile == path.last ? "Takes it back off" : "Adds it to your word") : "")
        .accessibilityAction { if interactive { store.tap(tile: tile) } }
        .accessibilityIdentifier("boggle-tile-\(tile)")
    }

    private func spoken(_ face: String, at: Int?) -> String {
        guard let at else { return face }
        return "\(face), letter \(at + 1) of your word"
    }

    private func drag(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let hit = { (point: CGPoint) -> Int? in
                    BoggleRules.tile(at: point, size: room.size, side: side, gap: Self.gap).map {
                        BoggleRules.tile(atDisplay: $0, size: room.size, turns: store.turns)
                    }
                }
                if touchStart == nil {
                    // The first touch must land squarely on a tile; a wider
                    // reach so a fingertip on its edge still counts.
                    touchStart = BoggleRules.tile(at: value.startLocation, size: room.size, side: side,
                                                  gap: Self.gap, reach: 0.72)
                        .map { BoggleRules.tile(atDisplay: $0, size: room.size, turns: store.turns) }
                }
                guard let start = touchStart, let tile = hit(value.location), tile != start || dragging else { return }
                if !dragging {
                    dragging = true
                    // Carry on from a word built by taps if this drag began on
                    // its last tile; otherwise the drag is a new word.
                    if store.trace.last != start {
                        store.clearTrace()
                        store.drag(to: start)
                    }
                }
                store.drag(to: tile)
            }
            .onEnded { _ in
                defer {
                    touchStart = nil
                    dragging = false
                }
                guard let start = touchStart else { return }
                if dragging {
                    store.submit()
                } else {
                    store.tap(tile: start)
                }
            }
    }
}

/// My words, newest first, with their points.
struct BoggleMyWords: View {
    let words: [BoggleWord]

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Your words", trailing: words.isEmpty ? nil : "\(words.count)")
            if words.isEmpty {
                Text("Drag through touching letters and lift to send. Or tap them one by one, then Enter.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(BoggleRules.newestFirst(words)) { word in
                        HStack(spacing: 6) {
                            Text(BoggleRules.display(word.word).uppercased())
                                .font(SR.Text.bodyMedium(15))
                                .foregroundStyle(SR.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
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
        .accessibilityIdentifier("boggle-my-words")
    }
}

// MARK: - Finished

struct BoggleFinished: View {
    let room: GameRoom
    @ObservedObject var store: BoggleStore
    let done: () -> Void

    private var classic: Bool { BoggleScoring.from(room.scoring) == .classic && !room.solo }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    SRPageHeader(kicker: "Boggle · \(BoggleSettings.about(room)) · final",
                                 title: GameResults.title(room, solo: "You scored \(room.me?.score ?? 0)", none: "Nobody scored"),
                                 strap: GameResults.strap(room))

                    GameStandingsCard(
                        room: room,
                        label: room.solo ? "Your game" : "Standings",
                        id: "boggle-standings",
                        detail: detail,
                        figure: { (text: "\($0.score)", spoken: "\($0.score) points") }
                    )

                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "The board", trailing: caption)
                        BoggleBoard(room: room, store: store, interactive: false)
                        Text(boardLine)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("boggle-possible")
                    }
                    .id("board")

                    if let found = room.boggleFound, !found.isEmpty {
                        VStack(alignment: .leading, spacing: SR.cardGap) {
                            SRSectionLabel(text: "Every word found", trailing: "\(found.count)")
                            VStack(spacing: 0) {
                                ForEach(Array(found.enumerated()), id: \.element.id) { index, word in
                                    if index > 0 { Divider().overlay(SR.divider) }
                                    foundRow(word) { show(word.word, reader) }
                                }
                            }
                            .padding(.horizontal, SR.cardPadding)
                            .padding(.vertical, 6)
                            .srGlassCard(.paper)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("boggle-found")
                        }
                    }

                    if let missed = room.boggleMissed, !missed.isEmpty {
                        VStack(alignment: .leading, spacing: SR.cardGap) {
                            SRSectionLabel(text: "Nobody found")
                            FlowChips(missed: missed, lit: store.highlighted) { show($0, reader) }
                                .accessibilityIdentifier("boggle-missed")
                        }
                    }

                    GameFinishedButtons(room: room, store: store, prefix: "boggle", done: done)
                }
                .padding(.horizontal, SR.gutter)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .srGround(.warm)
        .accessibilityIdentifier("boggle-finished")
        .onAppear { if room.winnerIds.contains(room.meId) { SRHaptic.ok() } }
    }

    /// The lit word, over the board.
    private var caption: String? {
        store.highlighted.map { BoggleRules.display($0).uppercased() }
    }

    private var boardLine: String {
        let found = room.boggleFound?.count ?? 0
        let tail = store.highlighted == nil ? "Tap a word below to see it on the board." : "Tap it again to clear."
        guard let line = BoggleRules.possibleLine(found: found, possible: room.possible, solo: room.solo) else { return tail }
        return "\(line) \(tail)"
    }

    private func show(_ word: String, _ reader: ScrollViewProxy) {
        store.highlight(word)
        if store.highlighted != nil {
            withAnimation(.snappy) { reader.scrollTo("board", anchor: .top) }
        }
    }

    private func detail(_ row: GameStanding) -> String {
        let words = GameResults.count(row.words, "word", "words")
        guard let longest = row.longest, !longest.isEmpty else { return words }
        return "\(words) · longest \(BoggleRules.display(longest).uppercased())"
    }

    private func foundRow(_ word: BoggleFound, action: @escaping () -> Void) -> some View {
        let crossed = classic && word.shared
        let lit = store.highlighted == word.word
        return Button(action: action) {
            HStack(spacing: 10) {
                Text(BoggleRules.display(word.word).uppercased())
                    .font(SR.Text.title())
                    .foregroundStyle(crossed ? SR.inkGhost : SR.ink)
                    .strikethrough(crossed, color: SR.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if crossed {
                    Text("SHARED")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(SR.line, lineWidth: 1))
                }
                Spacer(minLength: 8)
                HStack(spacing: -6) {
                    ForEach(word.finderIds, id: \.self) { id in
                        GameInitial(name: id == room.meId ? "You" : room.name(of: id),
                                    tone: id == room.meId ? SR.accent : SR.accentInk)
                            .overlay(Circle().strokeBorder(SR.paper, lineWidth: 1.5))
                    }
                }
                Text("\(word.points)")
                    .font(SR.Text.figure(18))
                    .foregroundStyle(crossed ? SR.inkGhost : SR.ink)
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
            }
            .frame(minHeight: SR.tapTarget)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(lit ? SR.accentInk.opacity(0.12) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(word, crossed: crossed))
        .accessibilityHint("Shows it on the board")
        .accessibilityAddTraits(lit ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("boggle-found-\(word.word)")
    }

    private func spoken(_ word: BoggleFound, crossed: Bool) -> String {
        let who = GameNames.list(word.finderIds.map { $0 == room.meId ? "you" : room.name(of: $0) })
        let shared = crossed ? ", shared, crossed out" : ""
        return "\(word.word), found by \(who)\(shared), \(word.points) points"
    }
}

/// The best words nobody found, as chips that wrap; each lights its path.
private struct FlowChips: View {
    let missed: [BoggleMissed]
    let lit: String?
    let pick: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(missed) { word in
                let on = lit == word.word
                Button {
                    pick(word.word)
                } label: {
                    HStack(spacing: 6) {
                        Text(BoggleRules.display(word.word).uppercased())
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(on ? SR.paper : SR.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 4)
                        Text("\(word.points)")
                            .font(SR.Text.label())
                            .foregroundStyle(on ? SR.paper : SR.accent)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: SR.tapTarget)
                    .background(
                        RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 2, style: .continuous)
                            .fill(on ? SR.accentInk : Color.clear)
                    )
                    .srGlassCard(on ? .clear : .paper, radius: SR.Glass.innerRadius + 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(word.word), \(word.points) points, nobody found it")
                .accessibilityHint("Shows it on the board")
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("boggle-missed-\(word.word)")
            }
        }
    }
}
