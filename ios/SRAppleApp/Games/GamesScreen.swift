import SwiftUI
import UIKit

/// The Games tab: invitations waiting, rooms I am in, and a game to start.
///
/// A shelf of games rather than one game's front door — one card per game
/// (Tap Duel, Wordle Race, Quiz Night, Anagram Blitz, Quick Maths Sprint,
/// Sequence Memory), and the rooms and invites above them say which game each is.
struct GamesScreen: View {
    @ObservedObject var store: GamesStore
    @EnvironmentObject private var router: Router
    /// The game whose card was tapped; the sheet opens on it.
    @State private var starting: GameKind?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SR.sectionGap) {
                VStack(alignment: .leading, spacing: 8) {
                    // No page title: the tab says Games. The one honest
                    // sentence about delivery. No push certificate: an invite
                    // rings only a phone with the app open.
                    Text("Invites reach phones with the app open.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("games-delivery-note")
                }

                if !store.invites.isEmpty {
                    section("Invitations", trailing: "\(store.invites.count)") {
                        ForEach(store.invites) { invite in
                            GameInviteCard(
                                invite: invite,
                                busy: store.busy == invite.roomId,
                                join: {
                                    Task {
                                        if await store.join(invite) {
                                            router.push(GameRoomRef(id: invite.roomId, game: invite.game), on: .games)
                                        }
                                    }
                                },
                                decline: { Task { await store.decline(invite) } }
                            )
                        }
                    }
                }

                if !store.rooms.isEmpty {
                    section("Your games", trailing: nil) {
                        ForEach(store.rooms) { room in
                            // A Button onto the tab's path, not a NavigationLink:
                            // the link under an interactive glass card never
                            // received the tap in CI; a Button over the same
                            // glass (the Tap Duel card) does.
                            Button {
                                SRHaptic.tap()
                                router.push(GameRoomRef(id: room.id, game: room.game), on: .games)
                            } label: {
                                GameRoomRow(room: room)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("games-room-\(room.id)")
                        }
                    }
                }

                // Every finished game, every game: today, this week, all time.
                Button {
                    SRHaptic.tap()
                    router.push(GameLeaderboardRef(), on: .games)
                } label: {
                    SRCard(interactive: true) {
                        HStack(spacing: 12) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(SR.accent)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Leaderboard")
                                    .font(SR.Text.title())
                                    .foregroundStyle(SR.ink)
                                Text("High scores and wins — today, this week, all time.")
                                    .font(SR.Text.secondary())
                                    .foregroundStyle(SR.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SR.inkGhost)
                        }
                        .frame(minHeight: SR.tapTarget)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("games-leaderboard")

                section("Play", trailing: nil) {
                    ForEach(GameKind.allCases) { kind in
                        Button {
                            SRHaptic.tap()
                            starting = kind
                        } label: {
                            GameCard(kind: kind)
                        }
                        .buttonStyle(.plain)
                        // Tap Duel keeps the id it shipped with.
                        .accessibilityIdentifier(kind == .tapDuel ? "games-new" : "games-new-\(kind.rawValue)")
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("games-screen")
        .srGround(.warm)
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SRBarMark() } }
        .task {
            if store.lobby == nil { await store.load() }
            await store.askForNotificationsIfUndecided()
        }
        .srRefreshable { await store.load() }
        .overlay {
            if store.loading && store.lobby == nil { ProgressView().tint(SR.accent) }
        }
        .overlay(alignment: .bottom) {
            if let message = store.message { SRBanner(text: message) }
        }
        .sheet(item: $starting) { kind in
            NewGameSheet(game: kind, players: store.players, busy: store.busy == "new") { request in
                switch await store.create(request) {
                case .created(let room):
                    starting = nil
                    router.push(GameRoomRef(id: room.id, game: room.game), on: .games)
                    return nil
                case .refused(let sentence):
                    return sentence
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, trailing: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: title, trailing: trailing)
            content()
        }
    }
}

/// An invitation: who, how hard, who else — Join or Decline.
struct GameInviteCard: View {
    let invite: GameInvite
    let busy: Bool
    let join: () -> Void
    let decline: () -> Void

    var body: some View {
        SRCard(accented: true) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(invite.hostName) invited you to \(GameNames.title(invite.game))")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let about = invite.about {
                        Text(about)
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.accentInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("games-invite-about-\(invite.roomId)")
                    }
                    Text("\(GameDifficulty.label(for: invite.difficulty)) · \(GameNames.list(invite.players))")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button { SRHaptic.tap(); join() } label: {
                        SRButtonLabel(title: "Join", icon: "play.fill", fill: true)
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .accessibilityIdentifier("games-invite-join-\(invite.roomId)")
                    Button { decline() } label: {
                        SRButtonLabel(title: "Decline", fill: true)
                    }
                    .srButton(.regular)
                    .controlSize(.large)
                    .accessibilityIdentifier("games-invite-decline-\(invite.roomId)")
                }
                .disabled(busy)
            }
        }
        .accessibilityIdentifier("games-invite-\(invite.roomId)")
    }
}

/// A room I am in, to go back to.
struct GameRoomRow: View {
    let room: GameRoomSummary

    var body: some View {
        SRCard(interactive: true) {
            HStack(spacing: 12) {
                Image(systemName: GameKind(rawValue: room.game)?.icon ?? "gamecontroller")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SR.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(GameNames.title(room.game))
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Text("Hosted by \(room.hostName)")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 8)
                SRGlassChip(text: phaseLabel, tone: SR.accentInk)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SR.inkGhost)
            }
            .frame(minHeight: SR.tapTarget)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Resume")
    }

    private var phaseLabel: String {
        switch room.phase {
        case .lobby: return "Lobby"
        case .countdown, .armed, .result, .playing, .question, .reveal, .show, .input, .review: return "Playing"
        case .finished: return "Finished"
        case .closed: return "Closed"
        case .unknown: return "Open"
        }
    }
}

/// One game's card on the shelf.
struct GameCard: View {
    let kind: GameKind

    var body: some View {
        SRCard(interactive: true) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: kind.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SR.paper)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(fill))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title)
                        .font(SR.Text.display(22))
                        .foregroundStyle(SR.ink)
                    Text(kind.blurb)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("NEW GAME")
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(SR.accent)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var fill: Color {
        switch kind {
        case .tapDuel: return SR.accent
        case .wordleRace: return SR.accentInk
        case .quizNight: return SR.good
        case .anagramBlitz: return SR.warn
        case .mathsSprint: return SR.ink
        case .sequenceMemory: return SR.error
        case .boggle: return SR.accentDeep
        case .categories: return SR.good
        case .liarsDice: return SR.good
        case .drawGuess: return SR.accentInk
        }
    }
}

/// Which game, how hard, who to invite, Start.
struct NewGameSheet: View {
    let players: [GamePerson]
    let busy: Bool
    /// Creates the room. Nil when it did (the sheet is then closed by its
    /// owner); otherwise the server's sentence, shown above Start.
    let start: (CreateGameBody) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var game: GameKind
    @State private var difficulty: GameDifficulty = .easy
    @State private var invited: Set<String> = []
    @State private var working = false
    // Quiz Night.
    @State private var topic = ""
    @State private var audience: QuizAudience = .family
    // Boggle.
    @State private var boggleSize = 4
    @State private var boggleSeconds = 120
    @State private var boggleScoring: BoggleScoring = .classic
    // Categories.
    @State private var categoriesCount = CategoriesSettings.defaultCount
    @State private var categoriesSeconds = CategoriesSettings.defaultSeconds
    // Liar's Dice.
    @State private var liarsDice = 5
    // Draw & Guess.
    @State private var drawTurns = 1
    @State private var drawSeconds = 80
    /// Why the last Start was refused.
    @State private var refusal: String?

    /// Opens on the game whose card was tapped; the first section can change it.
    init(game: GameKind = .tapDuel, players: [GamePerson], busy: Bool,
         start: @escaping (CreateGameBody) async -> String?) {
        self.players = players
        self.busy = busy
        self.start = start
        _game = State(initialValue: game)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    SRPageHeader(kicker: "New game", title: game.title)

                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "Game")
                        ForEach(GameKind.allCases) { kind in
                            choice(
                                title: kind.title,
                                line: kind.line,
                                selected: game == kind,
                                id: "games-game-\(kind.rawValue)"
                            ) {
                                game = kind
                                refusal = nil
                            }
                        }
                    }

                    if game == .quizNight {
                        quizSettings
                    }

                    if game == .boggle {
                        boggleSettings
                    }

                    if game == .categories {
                        categoriesSettings
                    }

                    if game == .liarsDice {
                        liarsDiceSettings
                    }

                    if game == .drawGuess {
                        drawGuessSettings
                    }

                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "Difficulty")
                        ForEach(GameDifficulty.allCases) { level in
                            choice(
                                title: level.label,
                                line: level.line(for: game),
                                selected: difficulty == level,
                                id: "games-difficulty-\(level.rawValue)"
                            ) { difficulty = level }
                        }
                    }

                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "Players", trailing: invited.isEmpty ? "Solo" : "\(invited.count + 1)")
                        if players.isEmpty {
                            Text("Nobody else in the family can play yet, so this is a solo game.")
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(players) { person in
                                choice(
                                    title: person.name,
                                    line: nil,
                                    selected: invited.contains(person.id),
                                    multi: true,
                                    id: "games-player-\(person.id)"
                                ) {
                                    invited.formSymmetricDifference([person.id])
                                }
                            }
                            Text("Nothing starts yet: the lobby waits for people to join, and you can ask more in from there. Invites reach phones with the app open.")
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let refusal {
                        Label(refusal, systemImage: "exclamationmark.circle")
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.error)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("games-new-refusal")
                    }

                    Button {
                        SRHaptic.tap()
                        working = true
                        refusal = nil
                        let payload = request
                        Task {
                            if let sentence = await start(payload) {
                                refusal = sentence
                                SRHaptic.bad()
                                UIAccessibility.post(notification: .announcement, argument: sentence)
                            }
                            working = false
                        }
                    } label: {
                        SRButtonLabel(title: invited.isEmpty ? "Open the lobby" : "Invite and open the lobby", icon: "arrow.right", fill: true)
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .disabled(working || busy)
                    .accessibilityIdentifier("games-start")
                }
                .padding(.horizontal, SR.gutter)
                .padding(.vertical, 12)
            }
            .srGround(.warm)
            .navigationTitle("New game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("games-new-cancel")
                }
            }
        }
        .presentationDetents([.large])
    }

    /// What Start sends.
    private var request: CreateGameBody {
        let invite = players.filter { invited.contains($0.id) }.map(\.id)
        if game == .quizNight {
            return QuizNightSettings(difficulty: difficulty, topic: topic, audience: audience).createBody(invite: invite)
        }
        if game == .boggle {
            return BoggleSettings(difficulty: difficulty, size: boggleSize, seconds: boggleSeconds, scoring: boggleScoring)
                .createBody(invite: invite)
        }
        if game == .categories {
            return CategoriesSettings(difficulty: difficulty, count: categoriesCount, seconds: categoriesSeconds)
                .createBody(invite: invite)
        }
        if game == .liarsDice {
            return LiarsDiceSettings(difficulty: difficulty, dice: liarsDice).createBody(invite: invite)
        }
        if game == .drawGuess {
            return DrawGuessSettings(difficulty: difficulty, turnsEach: drawTurns, seconds: drawSeconds)
                .createBody(invite: invite)
        }
        return CreateGameBody(game: game.rawValue, difficulty: difficulty.rawValue, invite: invite)
    }

    /// Times round and the clock — Draw & Guess's game.
    private var drawGuessSettings: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Game")
            segments(
                title: "Turns",
                options: DrawGuessSettings.turns.map { (value: $0, label: DrawGuessSettings.turnsLabel($0)) },
                selected: $drawTurns,
                id: "games-drawguess-turns"
            )
            segments(
                title: "Time to draw",
                options: DrawGuessSettings.times.map { (value: $0, label: DrawGuessSettings.timeLabel($0)) },
                selected: $drawSeconds,
                id: "games-drawguess-time"
            )
            Text("Two to five players. Everyone draws in turn while the others guess.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("games-drawguess-line")
        }
    }

    /// Card size and clock — Categories' round.
    private var categoriesSettings: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Round")
            segments(
                title: "Categories",
                options: CategoriesSettings.counts.map { (value: $0, label: "\($0)") },
                selected: $categoriesCount,
                id: "games-categories-count"
            )
            segments(
                title: "Time",
                options: CategoriesSettings.times.map { (value: $0, label: BoggleSettings.timeLabel($0)) },
                selected: $categoriesSeconds,
                id: "games-categories-time"
            )
            Text(CategoriesSettings.line(count: categoriesCount, seconds: categoriesSeconds))
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("games-categories-line")
        }
    }

    /// Grid, clock and scoring — Boggle's round.
    private var boggleSettings: some View {
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Round")
                segments(
                    title: "Grid",
                    options: BoggleSettings.sizes.map { (value: $0, label: BoggleSettings.sizeLabel($0)) },
                    selected: $boggleSize,
                    id: "games-boggle-size"
                )
                segments(
                    title: "Time",
                    options: BoggleSettings.times.map { (value: $0, label: BoggleSettings.timeLabel($0)) },
                    selected: $boggleSeconds,
                    id: "games-boggle-time"
                )
                Text(BoggleSettings.line(size: boggleSize, seconds: boggleSeconds))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("games-boggle-line")
            }

            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Scoring")
                ForEach(BoggleScoring.allCases) { rule in
                    choice(
                        title: rule.label,
                        line: rule.line,
                        selected: boggleScoring == rule,
                        id: "games-boggle-scoring-\(rule.rawValue)"
                    ) { boggleScoring = rule }
                }
            }
        }
    }

    /// Dice each — Liar's Dice's table. It needs two players, so it says so.
    private var liarsDiceSettings: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Table")
            segments(
                title: "Dice each",
                options: LiarsDiceSettings.diceCounts.map { (value: $0, label: "\($0)") },
                selected: $liarsDice,
                id: "games-liars-dice"
            )
            Text(LiarsDiceSettings.line(dice: liarsDice) + " Two to five players: invite at least one.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("games-liars-line")
        }
    }

    /// A labelled segmented picker, sized for a thumb.
    private func segments(title: String, options: [(value: Int, label: String)], selected: Binding<Int>,
                          id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.inkSecondary)
            Picker(title, selection: selected) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].label).tag(options[index].value)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selected.wrappedValue) { _, _ in SRHaptic.select() }
            .accessibilityIdentifier(id)
        }
    }

    /// Topic and audience — Quiz Night's own questions.
    private var quizSettings: some View {
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Topic", trailing: "\(topic.count)/\(QuizNightSettings.topicLimit)")
                TextField("Leave blank and jkai picks", text: $topic)
                    .font(SR.Text.body(17))
                    .foregroundStyle(SR.ink)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .submitLabel(.done)
                    .padding(.horizontal, SR.cardPadding)
                    .frame(minHeight: SR.tapTarget + 8)
                    .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
                    .onChange(of: topic) { _, typed in
                        let capped = QuizNightSettings.limit(typed)
                        if capped != typed { topic = capped }
                        refusal = nil
                    }
                    .accessibilityLabel("Topic")
                    .accessibilityHint("Optional. Leave blank and jkai picks.")
                    .accessibilityIdentifier("games-quiz-topic")
                Text("Anything: the solar system, 90s pop, dinosaurs. Leave it blank for a surprise.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Audience")
                ForEach(QuizAudience.allCases) { level in
                    choice(
                        title: level.label,
                        line: level.line,
                        selected: audience == level,
                        id: "games-audience-\(level.rawValue)"
                    ) { audience = level }
                }
            }
        }
    }

    private func choice(title: String, line: String?, selected: Bool, multi: Bool = false, id: String,
                        action: @escaping () -> Void) -> some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected
                      ? (multi ? "checkmark.square.fill" : "largecircle.fill.circle")
                      : (multi ? "square" : "circle"))
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(selected ? SR.accent : SR.inkGhost)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    if let line {
                        Text(line)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, SR.rowPadding)
            .frame(maxWidth: .infinity, minHeight: SR.tapTarget, alignment: .leading)
            .srGlassCard(selected ? .paper : .clear, radius: SR.Glass.innerRadius + 4, interactive: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
