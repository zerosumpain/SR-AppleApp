import SwiftUI
import UIKit

/// One Odd Artist Out room, from lobby to the final standings.
///
/// The lobby and the 3-2-1 are every game's, with the options and how to play
/// as the lobby's panel. Then, round by round: the card (the category, and the
/// word — or "You're the fake"), then twice round the table one line each on a
/// shared sheet of paper in each player's colour, with the turn order drawn as
/// a row of coloured dots so whose go it is (and whose is next) reads at a
/// glance; then a vote for the fake, the caught fake's one guess, and the
/// reveal — the fake unmasked, the votes as bars, the points.
///
/// The room runs on the server's clock for everyone, so there is no pause:
/// the "?" in the bar opens how to play over the game instead.
struct FakeArtistScreen: View {
    let roomId: String
    @StateObject private var store: FakeArtistStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingHowTo = false

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
            .toolbar {
                if store.phase.inRound && !store.ended {
                    ToolbarItem(placement: .topBarTrailing) {
                        TableHelpButton(id: "fakeartist-help") { showingHowTo = true }
                    }
                }
            }
            .sheet(isPresented: $showingHowTo) {
                TableHowToSheet(game: "Odd Artist Out", steps: FakeArtistHowTo.steps,
                                note: TableHowToNote.live, id: "fakeartist-how-to")
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
                          panel: AnyView(FakeArtistLobbyPanel(room: room)),
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
            VStack(spacing: 14) {
                FakeArtistMaskArt(side: 84)
                Text("Setting out the paper…")
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(SR.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .srGround(.warm)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("fakeartist-loading")
        }
    }
}

// MARK: - How to play

enum FakeArtistHowTo {
    static let steps: [TableHowToStep] = [
        TableHowToStep(icon: "rectangle.portrait.on.rectangle.portrait.fill", title: "Read your card",
                       text: "Everyone sees the category. All but one see the word too — the odd one out is the fake."),
        TableHowToStep(icon: "scribble", title: "One line each, twice round",
                       text: "On your go, add one line in your colour. Keep your finger down; lifting it ends your line."),
        TableHowToStep(icon: "hand.point.right.fill", title: "Vote for the fake",
                       text: "Talk it over, then vote. The fake is caught only with more votes than anyone else."),
        TableHowToStep(icon: "theatermasks.fill", title: "The fake's last chance",
                       text: "A caught fake can still win the round by naming the word."),
    ]
}

// MARK: - Lobby

/// The lobby's panel: the options, why Start waits, and how to play.
struct FakeArtistLobbyPanel: View {
    let room: GameRoom

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            FakeArtistOptionsCard(room: room)
            VStack(alignment: .leading, spacing: 14) {
                SRSectionLabel(text: "How to play")
                TableHowToList(steps: FakeArtistHowTo.steps, tint: FakeArtistPalette.mask)
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("fakeartist-howto")
        }
    }
}

struct FakeArtistOptionsCard: View {
    let room: GameRoom

    var body: some View {
        let block = FakeArtistSettings.startBlock(joined: room.playing.count)
        HStack(alignment: .center, spacing: 16) {
            FakeArtistMaskArt(side: 72)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(FakeArtistSettings.about(room).uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text("A new fake every round")
                    .font(SR.Text.title(19))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(block ?? "One line each, twice round, then vote. Catch the fake, or the fake scores.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(block == nil ? SR.inkMuted : SR.error)
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

/// The colours the game's own chrome uses: fixed, so a fake's card is the same
/// deep ink in both themes and white type always reads on it.
enum FakeArtistPalette {
    static let mask = Color(hex: 0x4B2E83)
    static let night = Color(hex: 0x1E1640)
    static let dusk = Color(hex: 0x3A2A7A)
}

/// The game's picture: a mask in a ring of everyone's paint.
struct FakeArtistMaskArt: View {
    var side: CGFloat = 72

    var body: some View {
        ZStack {
            Canvas { context, size in
                let s = min(size.width, size.height)
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let names = FakeArtistInk.palette
                for (index, name) in names.enumerated() {
                    let angle = Double(index) / Double(names.count) * 2 * Double.pi - Double.pi / 2
                    let r = s * 0.40
                    let x = centre.x + CGFloat(cos(angle)) * r
                    let y = centre.y + CGFloat(sin(angle)) * r
                    let d = s * 0.15
                    context.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)),
                                 with: .color(FakeArtistInk.color(name)))
                }
            }
            Circle()
                .fill(LinearGradient(colors: [FakeArtistPalette.dusk, FakeArtistPalette.night],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: side * 0.58, height: side * 0.58)
            Image(systemName: "theatermasks.fill")
                .font(.system(size: side * 0.26, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .frame(width: side, height: side)
    }
}

// MARK: - A round

struct FakeArtistPlaying: View {
    let room: GameRoom
    @ObservedObject var store: FakeArtistStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FakeArtistHeader(room: room, store: store)
                FakeArtistTimeBar(room: room, store: store)
                FakeArtistCard(store: store)
                if store.phase == .reading || store.phase == .drawing {
                    FakeArtistTurnStrip(room: room, store: store)
                }
                FakeArtistSeats(room: room, store: store)
                if store.phase == .reveal {
                    FakeArtistRevealCard(room: room, store: store)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
                FakeArtistCanvasView(store: store)
                FakeArtistTurnLine(store: store)
                if store.phase == .voting {
                    FakeArtistVotePanel(room: room, store: store)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if store.phase == .guessing { FakeArtistGuessPanel(store: store) }
                noteLine
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
            .srAnimation(.snappy(duration: 0.3), value: store.phase)
        }
        // A finger on the paper draws; it must not scroll the page.
        .scrollDisabled(store.pen.isDown)
        .scrollDismissesKeyboard(.interactively)
        .srGround(.warm)
        .accessibilityIdentifier("fakeartist-playing")
        .onChange(of: store.shakes) { _, _ in
            if let note = store.note { UIAccessibility.post(notification: .announcement, argument: note) }
        }
        .onChange(of: store.isMyTurn) { _, mine in
            if mine, store.phase == .drawing {
                UIAccessibility.post(notification: .announcement, argument: "Your turn to draw one line")
            }
        }
    }

    @ViewBuilder
    private var noteLine: some View {
        if let note = store.note {
            Label(note, systemImage: "exclamationmark.circle.fill")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.error)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("fakeartist-note")
        } else if room.me?.joined != true {
            Label("You are not playing in this one.", systemImage: "eye")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Round N of M, what is happening now, and the clock.
struct FakeArtistHeader: View {
    let room: GameRoom
    @ObservedObject var store: FakeArtistStore

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(SR.Text.title(20))
                .foregroundStyle(Color.white)
                .frame(width: 46, height: 46)
                .background(Circle().fill(tone))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker)
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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

    private var icon: String {
        switch store.phase {
        case .reading: return store.current?.isFake == true ? "theatermasks.fill" : "eye.fill"
        case .drawing: return store.isMyTurn ? "pencil.tip" : "hourglass"
        case .voting: return "hand.point.right.fill"
        case .guessing: return "questionmark"
        case .reveal: return "sparkles"
        default: return "paintpalette.fill"
        }
    }

    private var tone: Color {
        if store.phase == .drawing && store.isMyTurn { return FakeArtistInk.color(store.pen.color) }
        if store.current?.isFake == true { return FakeArtistPalette.mask }
        return FakeArtistInk.color("blue")
    }
}

/// The clock for whatever is running, as a bar that empties and warms; a tap
/// at ten seconds and at five while it is my move.
struct FakeArtistTimeBar: View {
    let room: GameRoom
    @ObservedObject var store: FakeArtistStore

    var body: some View {
        // Ticks, not an animation: UI tests need the app to go idle.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            DrawGuessClockTrack(fraction: fraction, seconds: seconds, nudges: nudges)
        }
        .accessibilityHidden(true)
    }

    private var fraction: Double {
        guard let limit = store.state?.phaseLength else { return 1 }
        return TableClock.fraction(endsAt: room.phaseEndsAt, turnMs: limit, now: store.serverNow())
    }

    private var seconds: Int? { TableClock.secondsLeft(endsAt: room.phaseEndsAt, now: store.serverNow()) }

    private var nudges: Bool {
        switch store.phase {
        case .drawing: return store.canDraw
        case .voting: return store.canVote && store.current?.myVote == nil
        case .guessing: return store.canGuess
        default: return false
        }
    }
}

/// My card: the category, and the word — or that I am the fake.
struct FakeArtistCard: View {
    @ObservedObject var store: FakeArtistStore

    var body: some View {
        let round = store.current
        let fake = round?.isFake == true
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                badge(fake: fake)
                words(round, fake: fake)
                Spacer(minLength: 0)
            }
            if fake && store.phase != .reveal {
                Text("Nobody else knows. Draw something that fits the category, and watch for clues.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(Color.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { ground(fake: fake) }
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(round))
        .accessibilityIdentifier("fakeartist-card")
    }

    private func badge(fake: Bool) -> some View {
        Image(systemName: fake ? "theatermasks.fill" : "paintbrush.pointed.fill")
            .font(SR.Text.hero(26))
            .foregroundStyle(fake ? FakeArtistPalette.mask : Color.white)
            .frame(width: 60, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fake ? Color.white : FakeArtistInk.color(store.pen.color))
            )
            .rotationEffect(.degrees(-4))
            .accessibilityHidden(true)
    }

    private func words(_ round: FakeArtistRound?, fake: Bool) -> some View {
        let card = FakeArtistText.card(round)
        return VStack(alignment: .leading, spacing: 2) {
            Text("CATEGORY · \((round?.category ?? "").uppercased())")
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(fake ? Color.white.opacity(0.8) : SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("fakeartist-category")
            Text(card.kicker)
                .font(SR.Text.secondary())
                .foregroundStyle(fake ? Color.white.opacity(0.9) : SR.inkSecondary)
            Text(card.title.uppercased())
                .font(SR.Text.hero(30))
                .tracking(1.5)
                .foregroundStyle(fake ? Color.white : SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .accessibilityIdentifier("fakeartist-word")
        }
    }

    @ViewBuilder
    private func ground(fake: Bool) -> some View {
        if fake {
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .fill(LinearGradient(colors: [FakeArtistPalette.dusk, FakeArtistPalette.night],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        } else {
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .fill(FakeArtistInk.color(store.pen.color).opacity(0.10))
        }
    }

    private func spoken(_ round: FakeArtistRound?) -> String {
        guard let round else { return "" }
        if round.isFake { return "Category, \(round.category). You're the fake: you don't know the word." }
        if let word = round.word { return "Category, \(round.category). The word is \(word)." }
        return "Category, \(round.category)."
    }
}

/// The drawing order for the round, both laps, as dots in each artist's
/// colour: done (filled), now (big, ringed, with their initial), to come
/// (hollow), missed (faded). Whose go it is, and whose is next, at a glance.
struct FakeArtistTurnStrip: View {
    let room: GameRoom
    @ObservedObject var store: FakeArtistStore

    var body: some View {
        if let round = store.current, !round.turns.isEmpty {
            let laps = max(1, store.state?.laps ?? 2)
            let perLap = max(1, round.turns.count / laps)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text((FakeArtistText.turnLabel(round) ?? "Turn order").uppercased())
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(SR.inkMuted)
                    Spacer(minLength: 8)
                    if let next = nextName(round) {
                        Text("NEXT: \(next.uppercased())")
                            .font(SR.Text.label())
                            .tracking(1)
                            .foregroundStyle(SR.inkSecondary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 3) {
                    ForEach(Array(round.turns.enumerated()), id: \.offset) { index, id in
                        dot(index: index, id: id, round: round)
                        if index == perLap - 1, index < round.turns.count - 1 {
                            Capsule()
                                .fill(SR.line)
                                .frame(width: 2, height: 16)
                        }
                    }
                }
                .frame(height: 30)
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 12)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(round))
            .accessibilityIdentifier("fakeartist-order")
        }
    }

    private func dot(index: Int, id: String, round: FakeArtistRound) -> some View {
        let colour = FakeArtistInk.color(store.state?.seat(id)?.color)
        let now = round.turn == index && store.phase == .drawing
        let done = (round.turn.map { index < $0 } ?? false)
        let missed = round.skipped.contains(index)
        // A big table (up to twenty turns) gets smaller dots so a 375pt phone fits them.
        let crowded = round.turns.count > 12
        let side: CGFloat = now ? (crowded ? 20 : 24) : (crowded ? 10 : 14)
        return ZStack {
            if now {
                Circle().fill(colour)
                Circle().strokeBorder(SR.ink, lineWidth: 2).padding(-3)
                Text(String(name(id).prefix(1)).uppercased())
                    .font(.system(size: crowded ? 9 : 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
            } else if done {
                Circle().fill(colour.opacity(missed ? 0.3 : 1))
            } else {
                Circle().strokeBorder(colour, lineWidth: 2)
            }
        }
        .frame(width: side, height: side)
        .frame(maxWidth: .infinity)
    }

    private func name(_ id: String) -> String { id == room.meId ? "You" : room.name(of: id) }

    private func nextName(_ round: FakeArtistRound) -> String? {
        guard store.phase == .drawing, let turn = round.turn, turn + 1 < round.turns.count else { return nil }
        return name(round.turns[turn + 1])
    }

    private func spoken(_ round: FakeArtistRound) -> String {
        var line = FakeArtistText.turnLabel(round) ?? "The drawing order"
        if let next = nextName(round) { line += ". Next, \(next)" }
        return line
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
                    seat(player)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("fakeartist-seats")
    }

    private func seat(_ player: GamePlayer) -> some View {
        let seat = store.state?.seat(player.id)
        let drawing = seat?.isDrawing == true
        let voted = store.phase == .voting && (store.current?.voted.contains(player.id) ?? false)
        let ink = FakeArtistInk.color(seat?.color)
        return HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                GameInitial(name: player.name, filled: true, tone: ink, side: 30)
                if drawing || voted {
                    Image(systemName: drawing ? "pencil" : "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(drawing ? SR.ink : SR.good))
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                        .offset(x: 4, y: 4)
                }
            }
            Text(player.id == room.meId ? "You" : player.name)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
            Text("\(player.score)")
                .font(SR.Text.figure(17))
                .foregroundStyle(SR.inkSecondary)
                .monospacedDigit()
                .srNumeric(Double(player.score))
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background {
            if drawing { Capsule().fill(ink.opacity(0.16)) }
        }
        .overlay {
            if drawing { Capsule().strokeBorder(ink, lineWidth: 2) }
        }
        .srGlass(.paper, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(player, colour: seat?.color, drawing: drawing, voted: voted))
        .accessibilityIdentifier("fakeartist-seat-\(player.id)")
    }

    private func spoken(_ player: GamePlayer, colour: String?, drawing: Bool, voted: Bool) -> String {
        let name = player.id == room.meId ? "You" : player.name
        let ink = colour.map { ", \($0)" } ?? ""
        let doing = drawing ? ", drawing" : voted ? ", has voted" : ""
        return "\(name)\(ink)\(doing), \(player.score) points"
    }
}

/// The shared sheet of paper. Draws everyone's lines (the newest with a soft
/// halo while the drawing goes round); on my turn a finger draws one.
struct FakeArtistCanvasView: View {
    @ObservedObject var store: FakeArtistStore
    /// The finished page's copy: a picture to look at, never to draw on.
    var framed = false

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let strokes = store.strokes
            let glowing = store.phase == .drawing && !framed
            Canvas { context, size in
                DrawGuessArt.paperGrid(in: &context, size: size)
                for (index, stroke) in strokes.enumerated() {
                    let ink = FakeArtistInk.color(stroke.color)
                    if glowing, index == strokes.count - 1 {
                        DrawGuessArt.halo(stroke, ink: ink, in: &context, side: size.width)
                    }
                    DrawGuessArt.draw(stroke, ink: ink, in: &context, side: size.width)
                }
            }
            .frame(width: side, height: side)
            .background(DrawGuessInk.paper)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColour, lineWidth: borderWidth))
            .overlay(alignment: .bottom) { prompt }
            .overlay { DrawGuessTape() }
            .contentShape(Rectangle())
            .gesture(drag(side: side), including: store.canDraw && !framed ? .all : .subviews)
        }
        .aspectRatio(1, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DrawGuessInk.paper)
                .shadow(color: Color.black.opacity(0.14), radius: 12, x: 0, y: 6)
        )
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("fakeartist-canvas")
    }

    /// My turn rims the paper in my own colour.
    private var borderColour: Color {
        guard !framed, store.canDraw else { return SR.line }
        return FakeArtistInk.color(store.pen.color)
    }

    private var borderWidth: CGFloat { !framed && store.canDraw ? 4 : 1 }

    /// A pill at the foot of the paper on my turn: in my colour, white type,
    /// readable in both themes.
    @ViewBuilder
    private var prompt: some View {
        if !framed, store.canDraw, !store.pen.isDown {
            Label("Your line — draw it in one go", systemImage: "hand.draw.fill")
                .font(SR.Text.title(15))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(FakeArtistInk.color(store.pen.color)))
                .padding(.bottom, 14)
                .allowsHitTesting(false)
                .transition(.opacity)
        } else if !framed, store.isMyTurn, store.lifted {
            Label("Line drawn — passing it on", systemImage: "checkmark")
                .font(SR.Text.title(15))
                .foregroundStyle(DrawGuessInk.onPaper)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.9)))
                .padding(.bottom, 14)
                .allowsHitTesting(false)
        }
    }

    private var spoken: String {
        let n = store.strokes.count
        let lines = GameResults.count(n, "line", "lines")
        if store.canDraw && !framed { return "The picture, \(lines). Your turn: drag to draw one line." }
        return "The picture, \(lines)"
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

/// Under the paper: what to do now, or whose line it is.
struct FakeArtistTurnLine: View {
    @ObservedObject var store: FakeArtistStore

    var body: some View {
        if store.phase == .drawing {
            let turn = FakeArtistText.turnLabel(store.current).map { "\($0). " } ?? ""
            Text(store.canDraw
                 ? "\(turn)One line — keep your finger down, and lift it to finish."
                 : "\(turn)Watch \(store.artistName == "You" ? "your" : store.artistName + "'s") line appear.")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(store.canDraw ? SR.accent : SR.inkMuted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("fakeartist-turn")
        } else if store.phase == .reading {
            Label("The drawing starts in a moment. Twice round, one line each.", systemImage: "clock")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - The vote

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
            FakeArtistVoteProgress(voted: voted, total: total)
            VStack(spacing: 8) {
                ForEach(people) { person in
                    row(person)
                }
            }
            Text(store.current?.isFake == true
                 ? "Vote like an artist would. You need a tie, or someone else picked, to get away."
                 : "The fake is caught only with more votes than anyone else. You can change your vote until everyone has voted.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fakeartist-vote")
    }

    private func row(_ person: GamePlayer) -> some View {
        let mine = store.current?.myVote == person.id
        let ink = FakeArtistInk.color(store.state?.seat(person.id)?.color)
        return Button { store.vote(for: person.id) } label: {
            HStack(spacing: 14) {
                GameInitial(name: person.name, filled: true, tone: ink, side: 40)
                Text(person.name)
                    .font(SR.Text.title(18))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if mine {
                    Label("YOUR VOTE", systemImage: "hand.point.left.fill")
                        .font(SR.Text.label())
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(SR.accent))
                        .tablePopIn()
                } else {
                    Image(systemName: "circle")
                        .font(SR.Text.title(22))
                        .foregroundStyle(SR.inkGhost)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                    .fill(mine ? SR.accent.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                    .strokeBorder(mine ? SR.accent : SR.line, lineWidth: mine ? 2 : 1)
            )
            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4, interactive: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .disabled(!store.canVote)
        .srAnimation(.snappy(duration: 0.25), value: mine)
        .accessibilityLabel(mine ? "\(person.name), your vote" : "Vote for \(person.name)")
        .accessibilityAddTraits(mine ? .isSelected : [])
        .accessibilityIdentifier("fakeartist-vote-\(person.id)")
    }
}

/// How many have voted, as pips: never who for whom.
struct FakeArtistVoteProgress: View {
    let voted: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index < voted ? SR.good : SR.line)
                    .frame(height: 8)
            }
        }
        .srAnimation(.snappy, value: voted)
        .accessibilityHidden(true)
    }
}

/// The caught fake's one guess, or the wait for it.
struct FakeArtistGuessPanel: View {
    @ObservedObject var store: FakeArtistStore
    @FocusState private var typing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if store.canGuess {
            VStack(alignment: .leading, spacing: 10) {
                Text("One guess. Name the \(store.current?.category.lowercased() ?? "word") and you still win.")
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    TextField("The word is…", text: $store.guessText)
                        .font(SR.Text.body(18))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .focused($typing)
                        .onSubmit { store.sendGuess() }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SR.surface))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(typing ? SR.accent : SR.line, lineWidth: typing ? 2 : 1)
                        )
                        .accessibilityIdentifier("fakeartist-guess-field")
                    Button { store.sendGuess() } label: {
                        Image(systemName: "paperplane.fill")
                            .font(SR.Text.title(20))
                            .foregroundStyle(Color.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(store.canSendGuess ? SR.accent : SR.inkGhost))
                            .contentShape(Circle())
                    }
                    .buttonStyle(SRPressStyle())
                    .disabled(!store.canSendGuess)
                    .accessibilityLabel("Guess")
                    .accessibilityIdentifier("fakeartist-guess-send")
                }
                .modifier(WordleShake(animatableData: CGFloat(reduceMotion ? 0 : store.shakes)))
                .animation(.linear(duration: 0.4), value: store.shakes)
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .onAppear { typing = true }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "hourglass")
                    .font(SR.Text.title(22))
                    .foregroundStyle(FakeArtistPalette.mask)
                    .accessibilityHidden(true)
                Text("\(store.fakeName) gets one guess at the word. Fingers crossed.")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("fakeartist-guess-wait")
        }
    }
}

// MARK: - The reveal

/// The reveal: the fake unmasked, the word, the votes as bars, the guess and
/// the points. A round I scored in gets a few sparks and a success tap.
struct FakeArtistRevealCard: View {
    let room: GameRoom
    @ObservedObject var store: FakeArtistStore

    var body: some View {
        let round = store.current
        let fakeId = round?.fakeId ?? ""
        VStack(alignment: .leading, spacing: 12) {
            unmasked(fakeId)
            Text(FakeArtistText.outcome(round?.outcome, fake: room.name(of: fakeId), meIsFake: fakeId == room.meId))
                .font(SR.Text.display(22))
                .foregroundStyle(round?.outcome?.fakeWins == true ? SR.accent : SR.good)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("fakeartist-outcome")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("The word was")
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(SR.inkSecondary)
                Text((round?.word ?? "…").uppercased())
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            if let guess = round?.guess {
                Label("Their guess: \(guess)", systemImage: "text.bubble.fill")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
            }
            FakeArtistVoteBars(room: room, store: store, fakeId: fakeId)
            awardedLine(round?.awarded ?? [:])
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .overlay {
            if scoredThisRound {
                TableCelebration(colours: TableCheer.colours, bursts: 4, duration: 2.4, seed: round?.number ?? 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fakeartist-reveal")
        .task {
            guard scoredThisRound else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            SRHaptic.ok()
        }
    }

    private var scoredThisRound: Bool { (store.current?.awarded?[room.meId] ?? 0) > 0 }

    /// The fake, in their own colour, behind the mask.
    private func unmasked(_ fakeId: String) -> some View {
        let ink = FakeArtistInk.color(store.state?.seat(fakeId)?.color)
        let name = fakeId == room.meId ? "You" : room.name(of: fakeId)
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(ink)
                Image(systemName: "theatermasks.fill")
                    .font(SR.Text.hero(26))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 64, height: 64)
            .tablePopIn()
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("THE FAKE WAS")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.inkMuted)
                Text(fakeId.isEmpty ? "…" : name)
                    .font(SR.Text.hero(30))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func awardedLine(_ awarded: [String: Int]) -> some View {
        if !awarded.isEmpty {
            Text(awarded.keys.sorted().map { "\($0 == room.meId ? "You" : room.name(of: $0)) +\(awarded[$0] ?? 0)" }
                .joined(separator: " · "))
                .font(SR.Text.title(15))
                .foregroundStyle(SR.good)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The votes each player drew, as bars in their colour, most first.
struct FakeArtistVoteBars: View {
    let room: GameRoom
    @ObservedObject var store: FakeArtistStore
    let fakeId: String

    var body: some View {
        let counts = store.current?.counts ?? [:]
        let rows = room.playing
            .filter { (counts[$0.id] ?? 0) > 0 }
            .sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }
        let most = max(1, rows.map { counts[$0.id] ?? 0 }.max() ?? 1)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SRSectionLabel(text: "The votes")
                ForEach(rows) { player in
                    bar(player, votes: counts[player.id] ?? 0, most: most)
                }
            }
        }
    }

    private func bar(_ player: GamePlayer, votes: Int, most: Int) -> some View {
        let ink = FakeArtistInk.color(store.state?.seat(player.id)?.color)
        let share = CGFloat(votes) / CGFloat(most)
        return HStack(spacing: 10) {
            Image(systemName: player.id == fakeId ? "theatermasks.fill" : "person.fill")
                .font(SR.Text.label(13))
                .foregroundStyle(player.id == fakeId ? FakeArtistPalette.mask : SR.inkMuted)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(player.id == room.meId ? "You" : player.name)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .frame(width: 72, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.line)
                    Capsule().fill(ink).frame(width: max(14, geo.size.width * share))
                }
            }
            .frame(height: 14)
            .accessibilityHidden(true)
            Text(GameResults.count(votes, "vote", "votes"))
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Finished

struct FakeArtistFinished: View {
    let room: GameRoom
    @ObservedObject var store: FakeArtistStore
    let done: () -> Void
    @State private var record: TableGameRecord?

    /// Odd Artist Out rooms send no `startedAt`, so the finish's own clock (set
    /// once, when the game ends) tells one game in this room from the next:
    /// without it, Play again would never be counted.
    private var gameKey: String {
        TableGameKey.finished(roomId: room.id, startedAt: room.startedAt ?? room.phaseEndsAt)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Odd Artist Out · \(FakeArtistSettings.about(room)) · final",
                             title: GameResults.title(room, solo: "You scored \(myScore)", none: "Nobody scored"),
                             strap: GameResults.strap(room))

                if room.me?.joined == true { hero }

                // The standings card cheers (confetti and a tap) when I won.
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

                GameFinishedButtons(room: room, store: store, prefix: "fakeartist", done: done)

                if let record {
                    TableRecordCard(record: record, gameKey: gameKey, bestLabel: "Best score", id: "fakeartist-record")
                }

                FakeArtistHistory(room: room, store: store)

                if !store.strokes.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "The last picture", trailing: store.state?.history.last?.word)
                        FakeArtistCanvasView(store: store, framed: true)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(FakeArtistPalette.night))
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("fakeartist-finished")
        .onAppear { noteRecord() }
    }

    private var myScore: Int {
        room.standings?.first { $0.id == room.meId }?.score ?? room.me?.score ?? 0
    }

    private var place: Int? {
        guard !room.solo, let rows = room.standings, !rows.isEmpty else { return nil }
        return PartyRoomMaths.place(of: room.meId, ids: rows.map(\.id), scores: rows.map(\.score))
    }

    /// My game: the score, the place, and my turns as the fake.
    private var hero: some View {
        let won = room.winnerIds.contains(room.meId)
        let extra = store.state?.extra(room.meId)
        return HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(won ? Color(hex: 0xE3B22B) : FakeArtistPalette.mask.opacity(0.16))
                    .frame(width: 76, height: 76)
                Image(systemName: won ? "trophy.fill" : "theatermasks.fill")
                    .font(SR.Text.hero(32))
                    .foregroundStyle(won ? Color.white : FakeArtistPalette.mask)
            }
            .tablePopIn()
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(myScore)")
                        .font(SR.Text.hero(44))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                    Text(myScore == 1 ? "point" : "points")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.inkSecondary)
                }
                if let place {
                    Text("\(PartyRoomMaths.ordinal(place)) of \(room.standings?.count ?? room.playing.count)")
                        .font(SR.Text.title(15))
                        .foregroundStyle(place == 1 ? SR.accent : SR.inkSecondary)
                }
                if let extra, extra.timesFake > 0 {
                    Text("Fake \(extra.timesFake)×, got away \(extra.winsAsFake)×")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fakeartist-result")
    }

    private func noteRecord() {
        guard record == nil, room.me?.joined == true else { return }
        let book = TableGameBestStore(gameId: GameKind.fakeArtist.rawValue, persists: !SRDemo.isOn)
        let won = room.winnerIds.contains(room.meId)
        let kept = book.note(variant: GameKind.fakeArtist.rawValue, key: gameKey, won: won, score: myScore)
        record = kept
        // A win is felt by the standings card; a new best without one is felt here.
        if kept.beatBest(gameKey), !won { SRHaptic.ok() }
    }
}

/// Every round in a line: the word, the fake, and how it went.
struct FakeArtistHistory: View {
    let room: GameRoom
    @ObservedObject var store: FakeArtistStore

    var body: some View {
        if let history = store.state?.history, !history.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Rounds", trailing: "\(history.count)")
                VStack(spacing: 0) {
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, past in
                        if index > 0 { Divider().overlay(SR.divider) }
                        row(past)
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 4)
                .srGlassCard(.paper)
            }
            .accessibilityIdentifier("fakeartist-history")
        }
    }

    private func row(_ past: FakeArtistPastRound) -> some View {
        let fakeWon = past.outcome.fakeWins
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon(past.outcome))
                .font(SR.Text.title())
                .foregroundStyle(Color.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(fakeWon ? FakeArtistPalette.mask : SR.good))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(past.number). \(past.word) · \(past.category)")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(FakeArtistText.outcome(past.outcome, fake: room.name(of: past.fakeId),
                                            meIsFake: past.fakeId == room.meId))
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func icon(_ outcome: FakeArtistOutcome) -> String {
        switch outcome {
        case .escaped: return "theatermasks.fill"
        case .guessed: return "lightbulb.fill"
        case .caught: return "hand.raised.fill"
        case .fakeLeft: return "door.left.hand.open"
        case .unknown: return "questionmark"
        }
    }
}
