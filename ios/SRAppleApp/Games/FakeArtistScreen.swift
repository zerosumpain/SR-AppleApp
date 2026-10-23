import SwiftUI
import UIKit

/// One Odd Artist Out room, from lobby to the final standings.
///
/// The lobby and the 3-2-1 are every game's. Then, round by round: the card
/// (the category, and the word — or "You're the fake"), then twice round the
/// table one line each on a shared square of paper in each player's colour,
/// then a vote for the fake, the caught fake's one guess, and the reveal.
struct FakeArtistScreen: View {
    let roomId: String
    @StateObject private var store: FakeArtistStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: FakeArtistStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Odd Artist Out")
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
        guard !store.ended, store.room != nil else { return false }
        return store.phase == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "fakeartist-ended", done: { dismiss() })
        } else if let room = store.room {
            switch store.phase {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "fakeartist", done: { dismiss() },
                          panel: AnyView(FakeArtistOptionsCard(room: room)),
                          startBlocked: FakeArtistSettings.startBlock(joined: room.playing.count) != nil)
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "One of you doesn't know the word. Draw so the others can tell you do.",
                                  id: "fakeartist-countdown")
            case .reading, .drawing, .voting, .guessing, .reveal:
                FakeArtistPlaying(room: room, store: store)
            case .finished:
                FakeArtistFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "fakeartist-ended", done: { dismiss() })
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

struct FakeArtistOptionsCard: View {
    let room: GameRoom

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "theatermasks.fill")
                .font(SR.Text.display(26))
                .foregroundStyle(SR.paper)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(SR.accentDeep))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(FakeArtistSettings.about(room).uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text("A new fake every round")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(FakeArtistSettings.startBlock(joined: room.playing.count)
                     ?? "One line each, twice round, then vote. Catch the fake, or the fake scores.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fakeartist-options")
    }
}

// MARK: - A round

struct FakeArtistPlaying: View {
    let room: GameRoom
    @ObservedObject var store: FakeArtistStore
    @FocusState private var typing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                FakeArtistTimeBar(room: room, store: store)
                FakeArtistCard(store: store)
                FakeArtistSeats(room: room, store: store)
                if store.phase == .reveal {
                    FakeArtistRevealCard(room: room, store: store)
                }
                FakeArtistCanvasView(store: store)
                turnLine
                if store.phase == .voting { FakeArtistVotePanel(room: room, store: store) }
                if store.phase == .guessing { guessPanel }
                noteLine
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        // A finger on the paper draws; it must not scroll the page.
        .scrollDisabled(store.pen.isDown)
        .scrollDismissesKeyboard(.interactively)
        .srGround(.warm)
        .accessibilityIdentifier("fakeartist-playing")
        .onChange(of: store.shakes) { _, _ in
            if let note = store.note { UIAccessibility.post(notification: .announcement, argument: note) }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker)
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text(title)
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("fakeartist-title")
            }
            Spacer(minLength: 8)
            WordleTimer(room: room, store: store, id: "fakeartist-timer")
        }
    }

    private var kicker: String {
        let round = store.current.map { "ROUND \($0.number) OF \(room.rounds)" } ?? "ODD ARTIST OUT"
        return "\(round) · \(GameDifficulty.label(for: room.difficulty).uppercased())"
    }

    private var title: String {
        switch store.phase {
        case .reading: return store.current?.isFake == true ? "Shh — you're the fake" : "Read your card"
        case .drawing: return store.isMyTurn ? (store.lifted ? "Line drawn" : "Your line") : "\(store.artistName) is drawing"
        case .voting: return "Who's the fake?"
        case .guessing: return store.current?.isFake == true ? "Caught! Name the word" : "\(store.fakeName) was caught"
        case .reveal: return "The reveal"
        default: return "Odd Artist Out"
        }
    }

    @ViewBuilder
    private var turnLine: some View {
        if store.phase == .drawing {
            let turn = FakeArtistText.turnLabel(store.current).map { "\($0). " } ?? ""
            Text(store.canDraw
                 ? "\(turn)One line — keep your finger down, and lift it to finish."
                 : "\(turn)Watch \(store.artistName == "You" ? "your" : store.artistName + "'s") line appear.")
                .font(SR.Text.mono())
                .foregroundStyle(store.canDraw ? SR.accent : SR.inkMuted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("fakeartist-turn")
        } else if store.phase == .reading {
            Text("The drawing starts in a moment. Twice round, one line each.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var guessPanel: some View {
        if store.canGuess {
            VStack(alignment: .leading, spacing: 10) {
                Text("One guess. Name the \(store.current?.category.lowercased() ?? "word") and you still win.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    TextField("The word is…", text: $store.guessText)
                        .font(SR.Text.body(17))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .focused($typing)
                        .onSubmit { store.sendGuess() }
                        .padding(.horizontal, 14)
                        .frame(minHeight: SR.tapTarget + 4)
                        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
                        .accessibilityIdentifier("fakeartist-guess-field")
                    Button { store.sendGuess() } label: {
                        SRButtonLabel(title: "Guess", icon: "paperplane.fill")
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .disabled(!store.canSendGuess)
                    .accessibilityIdentifier("fakeartist-guess-send")
                }
                .modifier(WordleShake(animatableData: CGFloat(reduceMotion ? 0 : store.shakes)))
                .animation(.linear(duration: 0.4), value: store.shakes)
            }
        } else {
            Label("\(store.fakeName) gets one guess at the word. Fingers crossed.", systemImage: "hourglass")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.inkSecondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("fakeartist-guess-wait")
        }
    }

    @ViewBuilder
    private var noteLine: some View {
        if let note = store.note {
            Label(note, systemImage: "exclamationmark.circle")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.error)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("fakeartist-note")
        } else if room.me?.joined != true {
            Text("You are not playing in this one.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .frame(maxWidth: .infinity)
        }
    }
}

/// The clock for whatever is running, as a bar that empties and warms.
struct FakeArtistTimeBar: View {
    let room: GameRoom
    @ObservedObject var store: FakeArtistStore

    var body: some View {
        // Ticks, not an animation: UI tests need the app to go idle.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let left = fraction
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
    }

    private var fraction: CGFloat {
        guard let end = room.phaseEndsAt, let limit = store.state?.phaseLength, limit > 0,
              let now = store.serverNow() else { return 1 }
        return CGFloat(min(1, max(0, (end - now) / limit)))
    }
}

/// My card: the category, and the word — or that I am the fake.
struct FakeArtistCard: View {
    @ObservedObject var store: FakeArtistStore

    var body: some View {
        let round = store.current
        let card = FakeArtistText.card(round)
        let fake = round?.isFake == true
        VStack(alignment: .leading, spacing: 6) {
            Text("CATEGORY · \((round?.category ?? "").uppercased())")
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(fake ? SR.paper.opacity(0.8) : SR.inkMuted)
                .accessibilityIdentifier("fakeartist-category")
            Text(card.kicker)
                .font(SR.Text.secondary())
                .foregroundStyle(fake ? SR.paper.opacity(0.9) : SR.inkSecondary)
            Text(card.title.uppercased())
                .font(SR.Text.hero(30))
                .tracking(1.5)
                .foregroundStyle(fake ? SR.paper : SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .accessibilityIdentifier("fakeartist-word")
            if fake && store.phase != .reveal {
                Text("Nobody else knows. Draw something that fits the category, and watch for clues.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.paper.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 6, style: .continuous)
                .fill(fake ? SR.accentDeep : Color.clear)
        )
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(round))
        .accessibilityIdentifier("fakeartist-card")
    }

    private func spoken(_ round: FakeArtistRound?) -> String {
        guard let round else { return "" }
        if round.isFake { return "Category, \(round.category). You're the fake: you don't know the word." }
        if let word = round.word { return "Category, \(round.category). The word is \(word)." }
        return "Category, \(round.category)."
    }
}

/// Everyone: their ink, who is drawing, who has voted, the score.
struct FakeArtistSeats: View {
    let room: GameRoom
    @ObservedObject var store: FakeArtistStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(room.playing) { player in
                    let seat = store.state?.seat(player.id)
                    let drawing = seat?.isDrawing == true
                    let voted = store.phase == .voting && (store.current?.voted.contains(player.id) ?? false)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(FakeArtistInk.color(seat?.color))
                            .frame(width: 12, height: 12)
                        Text(player.id == room.meId ? "You" : player.name)
                            .font(SR.Text.bodyMedium(14))
                            .foregroundStyle(SR.ink)
                            .lineLimit(1)
                        if drawing {
                            Image(systemName: "pencil.tip").font(SR.Text.label()).foregroundStyle(SR.accent)
                        } else if voted {
                            Image(systemName: "checkmark.circle.fill").font(SR.Text.label()).foregroundStyle(SR.good)
                        }
                        Text("\(player.score)")
                            .font(SR.Text.label())
                            .foregroundStyle(SR.inkMuted)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken(player, colour: seat?.color, drawing: drawing, voted: voted))
                    .accessibilityIdentifier("fakeartist-seat-\(player.id)")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("fakeartist-seats")
    }

    private func spoken(_ player: GamePlayer, colour: String?, drawing: Bool, voted: Bool) -> String {
        let name = player.id == room.meId ? "You" : player.name
        let ink = colour.map { ", \($0)" } ?? ""
        let doing = drawing ? ", drawing" : voted ? ", has voted" : ""
        return "\(name)\(ink)\(doing), \(player.score) points"
    }
}

/// The shared square of paper. Draws everyone's lines; on my turn a finger draws one.
struct FakeArtistCanvasView: View {
    @ObservedObject var store: FakeArtistStore

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            Canvas { context, size in
                for stroke in store.strokes { draw(stroke, in: &context, side: size.width) }
            }
            .frame(width: side, height: side)
            .background(DrawGuessInk.paper)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(store.canDraw ? FakeArtistInk.color(store.pen.color) : SR.line,
                              lineWidth: store.canDraw ? 3 : 1))
            .overlay { prompt }
            .contentShape(Rectangle())
            .gesture(drag(side: side), including: store.canDraw ? .all : .subviews)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("fakeartist-canvas")
    }

    @ViewBuilder
    private var prompt: some View {
        if store.canDraw && !store.pen.isDown {
            Text("Your line — draw it in one go")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkGhost)
                .padding(8)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
        }
    }

    private var spoken: String {
        let n = store.strokes.count
        let lines = GameResults.count(n, "line", "lines")
        if store.canDraw { return "The picture, \(lines). Your turn: drag to draw one line." }
        return "The picture, \(lines)"
    }

    private func draw(_ stroke: DrawGuessStroke, in context: inout GraphicsContext, side: CGFloat) {
        guard let first = stroke.points.first else { return }
        let width = CGFloat(stroke.width) * side / CGFloat(DrawGuessGeometry.side)
        let ink = FakeArtistInk.color(stroke.color)
        if stroke.points.count == 1 || stroke.points.allSatisfy({ $0 == first }) {
            let p = DrawGuessGeometry.place(first, size: side)
            context.fill(Path(ellipseIn: CGRect(x: p.x - width / 2, y: p.y - width / 2, width: width, height: width)),
                         with: .color(ink))
            return
        }
        var path = Path()
        path.move(to: DrawGuessGeometry.place(first, size: side))
        for point in stroke.points.dropFirst() { path.addLine(to: DrawGuessGeometry.place(point, size: side)) }
        context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func drag(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = DrawGuessGeometry.quantise(value.location, size: side)
                if store.pen.isDown {
                    store.move(to: point)
                } else {
                    store.down(at: point)
                }
            }
            .onEnded { _ in store.up() }
    }
}

/// Everyone else, to vote for. My choice is lit; I can change it until the vote closes.
struct FakeArtistVotePanel: View {
    let room: GameRoom
    @ObservedObject var store: FakeArtistStore

    var body: some View {
        let people = store.state?.candidates(in: room) ?? []
        let voted = store.current?.voted.count ?? 0
        let dealt = Set(store.current?.turns ?? [])
        let total = room.playing.filter { dealt.contains($0.id) }.count
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Vote for the fake", trailing: FakeArtistText.votedLine(voted: voted, of: total))
            VStack(spacing: 0) {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    if index > 0 { Divider().overlay(SR.divider) }
                    let mine = store.current?.myVote == person.id
                    Button { store.vote(for: person.id) } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(FakeArtistInk.color(store.state?.seat(person.id)?.color))
                                .frame(width: 16, height: 16)
                            Text(person.name)
                                .font(SR.Text.title())
                                .foregroundStyle(SR.ink)
                            Spacer(minLength: 8)
                            Image(systemName: mine ? "largecircle.fill.circle" : "circle")
                                .font(SR.Text.title())
                                .foregroundStyle(mine ? SR.accent : SR.inkGhost)
                        }
                        .frame(minHeight: SR.tapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.canVote)
                    .accessibilityLabel(mine ? "\(person.name), your vote" : "Vote for \(person.name)")
                    .accessibilityAddTraits(mine ? .isSelected : [])
                    .accessibilityIdentifier("fakeartist-vote-\(person.id)")
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
            Text(store.current?.isFake == true
                 ? "Vote like an artist would. You need a tie, or someone else picked, to get away."
                 : "The fake is caught only with more votes than anyone else. You can change your vote until everyone has voted.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fakeartist-vote")
    }
}

/// The reveal: the word, the fake, the votes, the guess and the points.
struct FakeArtistRevealCard: View {
    let room: GameRoom
    @ObservedObject var store: FakeArtistStore

    var body: some View {
        let round = store.current
        let fakeId = round?.fakeId ?? ""
        VStack(alignment: .leading, spacing: 10) {
            Text(FakeArtistText.outcome(round?.outcome, fake: room.name(of: fakeId), meIsFake: fakeId == room.meId))
                .font(SR.Text.display(22))
                .foregroundStyle(round?.outcome?.fakeWins == true ? SR.accent : SR.good)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("fakeartist-outcome")
            Text("The word was \(round?.word ?? "…").")
                .font(SR.Text.bodyMedium(16))
                .foregroundStyle(SR.ink)
            if let guess = round?.guess {
                Text("Their guess: \(guess)")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
            }
            let counts = round?.counts ?? [:]
            if !counts.isEmpty {
                ForEach(room.playing.filter { (counts[$0.id] ?? 0) > 0 }.sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }) { p in
                    HStack(spacing: 8) {
                        Image(systemName: p.id == fakeId ? "theatermasks.fill" : "person.fill")
                            .font(SR.Text.label())
                            .foregroundStyle(p.id == fakeId ? SR.accentDeep : SR.inkMuted)
                        Text(p.id == room.meId ? "You" : p.name)
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.ink)
                        Spacer(minLength: 8)
                        Text(GameResults.count(counts[p.id] ?? 0, "vote", "votes"))
                            .font(SR.Text.label())
                            .foregroundStyle(SR.inkMuted)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            let awarded = round?.awarded ?? [:]
            if !awarded.isEmpty {
                Text(awarded.keys.sorted().map { "\($0 == room.meId ? "You" : room.name(of: $0)) +\(awarded[$0] ?? 0)" }
                    .joined(separator: " · "))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fakeartist-reveal")
    }
}

// MARK: - Finished

struct FakeArtistFinished: View {
    let room: GameRoom
    @ObservedObject var store: FakeArtistStore
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Odd Artist Out · \(FakeArtistSettings.about(room)) · final",
                             title: GameResults.title(room, solo: "You scored \(room.me?.score ?? 0)", none: "Nobody scored"),
                             strap: GameResults.strap(room))

                GameStandingsCard(
                    room: room,
                    label: "Standings",
                    id: "fakeartist-standings",
                    detail: { row in
                        guard let extra = store.state?.extra(row.id), extra.timesFake > 0 else { return "" }
                        return "Fake \(extra.timesFake)×, got away \(extra.winsAsFake)×"
                    },
                    figure: { (text: "\($0.score)", spoken: "\($0.score) points") }
                )

                if let history = store.state?.history, !history.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "Rounds", trailing: "\(history.count)")
                        VStack(spacing: 0) {
                            ForEach(Array(history.enumerated()), id: \.element.id) { index, past in
                                if index > 0 { Divider().overlay(SR.divider) }
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("\(past.number)")
                                        .font(SR.Text.figure(18))
                                        .foregroundStyle(SR.inkMuted)
                                        .monospacedDigit()
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(past.word) · \(past.category)")
                                            .font(SR.Text.bodyMedium(15))
                                            .foregroundStyle(SR.ink)
                                        Text(FakeArtistText.outcome(past.outcome, fake: room.name(of: past.fakeId),
                                                                    meIsFake: past.fakeId == room.meId))
                                            .font(SR.Text.secondary())
                                            .foregroundStyle(SR.inkMuted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 8)
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(.horizontal, SR.cardPadding)
                        .padding(.vertical, 4)
                        .srGlassCard(.paper)
                    }
                    .accessibilityIdentifier("fakeartist-history")
                }

                if !store.strokes.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "The last picture", trailing: store.state?.history.last?.word)
                        FakeArtistCanvasView(store: store)
                    }
                }

                GameFinishedButtons(room: room, store: store, prefix: "fakeartist", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("fakeartist-finished")
        .onAppear { if room.winnerIds.contains(room.meId) { SRHaptic.ok() } }
    }
}
