import SwiftUI

// The family's games leaderboard: `GET api/native/games/leaderboard?window=…`
// (SR-Main `src/routes/api/native/games/leaderboard`). Every finished round of
// every game is recorded by the site; this reads back today, this week (Monday
// on, UK time) or all time — overall wins first, then a board per game with
// each person's best score, wins and games played.
//
// Names only on the wire, never an email; `me` is the caller's player id so
// the phone can pick out its own rows.

/// Navigation value for the leaderboard, pushed on the Games stack.
struct GameLeaderboardRef: Hashable {}

/// Which stretch of time a board covers.
enum LeaderboardWindow: String, CaseIterable, Identifiable {
    case day, week, all

    var id: String { rawValue }

    /// The segmented control's word.
    var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .all: return "All"
        }
    }

    /// What the window means, in a sentence.
    var caption: String {
        switch self {
        case .day: return "Today, since midnight UK time."
        case .week: return "This week, since Monday midnight UK time."
        case .all: return "Every game ever recorded."
        }
    }
}

/// One window's boards.
struct GameLeaderboard: Decodable, Equatable {
    /// The caller's player id — "me" in every row.
    let meId: String
    let window: String
    let overall: [LeaderboardOverallRow]
    let games: [LeaderboardGame]

    private enum CodingKeys: String, CodingKey { case me, window, overall, games }
    private struct Me: Decodable { let id: String }

    init(meId: String, window: String, overall: [LeaderboardOverallRow], games: [LeaderboardGame]) {
        self.meId = meId
        self.window = window
        self.overall = overall
        self.games = games
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meId = ((try? c.decodeIfPresent(Me.self, forKey: .me)) ?? nil)?.id ?? ""
        window = (try? c.decodeIfPresent(String.self, forKey: .window)) ?? "week"
        overall = (try? c.decodeIfPresent([LeaderboardOverallRow].self, forKey: .overall)) ?? []
        games = (try? c.decodeIfPresent([LeaderboardGame].self, forKey: .games)) ?? []
    }

    var isEmpty: Bool { overall.isEmpty && games.isEmpty }
}

/// A person across every game: wins and games played.
struct LeaderboardOverallRow: Decodable, Equatable, Identifiable {
    let rank: Int
    let playerId: String
    let name: String
    let wins: Int
    let played: Int

    var id: String { playerId }
}

/// One game's board. `scored` false: the game has no numeric score (Liar's
/// Dice, Wordle Race) and the board ranks by wins, with no best column.
struct LeaderboardGame: Decodable, Equatable, Identifiable {
    let game: String
    let title: String
    let scored: Bool
    let rows: [LeaderboardRow]

    var id: String { game }

    private enum CodingKeys: String, CodingKey { case game, title, scored, rows }

    init(game: String, title: String, scored: Bool, rows: [LeaderboardRow]) {
        self.game = game
        self.title = title
        self.scored = scored
        self.rows = rows
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        game = try c.decode(String.self, forKey: .game)
        // The app's own name when it knows the game; the site's otherwise.
        let sent = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil
        title = GameKind(rawValue: game)?.title ?? sent ?? GameNames.title(game)
        scored = (try? c.decodeIfPresent(Bool.self, forKey: .scored)) ?? false
        rows = (try? c.decodeIfPresent([LeaderboardRow].self, forKey: .rows)) ?? []
    }
}

/// A person on one game's board.
struct LeaderboardRow: Decodable, Equatable, Identifiable {
    let rank: Int
    let playerId: String
    let name: String
    /// The best score in the window; nil for a game with no score.
    let best: Int?
    /// What the best was set on — "5×5 · 90 seconds · hard".
    let bestLabel: String?
    let wins: Int
    let played: Int

    var id: String { playerId }

    private enum CodingKeys: String, CodingKey { case rank, playerId, name, best, bestLabel, wins, played }

    init(rank: Int, playerId: String, name: String, best: Int?, bestLabel: String?, wins: Int, played: Int) {
        self.rank = rank
        self.playerId = playerId
        self.name = name
        self.best = best
        self.bestLabel = bestLabel
        self.wins = wins
        self.played = played
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(String.self, forKey: .playerId)
        rank = (try? c.decodeIfPresent(Int.self, forKey: .rank)) ?? 0
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Someone"
        best = (try? c.decodeIfPresent(Int.self, forKey: .best)) ?? nil
        bestLabel = (try? c.decodeIfPresent(String.self, forKey: .bestLabel)) ?? nil
        wins = (try? c.decodeIfPresent(Int.self, forKey: .wins)) ?? 0
        played = (try? c.decodeIfPresent(Int.self, forKey: .played)) ?? 0
    }
}

/// "1 game", "3 wins".
enum LeaderboardWords {
    static func count(_ n: Int, _ one: String, _ many: String) -> String {
        n == 1 ? "1 \(one)" : "\(n) \(many)"
    }
}

// MARK: - Store

@MainActor
final class GameLeaderboardStore: ObservableObject {
    @Published var window: LeaderboardWindow = .week
    @Published private(set) var boards: [LeaderboardWindow: GameLeaderboard] = [:]
    @Published private(set) var loading = false
    @Published var message: String?

    private let client = SiteClient.shared

    /// The board on screen, once it has loaded.
    var current: GameLeaderboard? { boards[window] }

    /// Read the selected window. A board already on screen stays there while
    /// a refresh is in flight, and after one that failed.
    func load() async {
        let asked = window
        loading = true
        defer { loading = false }
        do {
            let board: GameLeaderboard = try await client.send("api/native/games/leaderboard?window=\(asked.rawValue)")
            boards[asked] = board
            message = nil
        } catch is CancellationError {
            return
        } catch SiteError.expired {
            message = "This iPhone needs pairing again."
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            message = boards[asked] == nil ? error.localizedDescription : nil
        }
    }
}

// MARK: - Screen

/// Day / Week / All, the overall table, then a board per game played.
struct GameLeaderboardScreen: View {
    @StateObject private var store = GameLeaderboardStore()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SR.sectionGap) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Window", selection: $store.window) {
                        ForEach(LeaderboardWindow.allCases) { window in
                            Text(window.label).tag(window)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: store.window) { _, _ in SRHaptic.select() }
                    .accessibilityIdentifier("leaderboard-window")
                    Text(store.window.caption)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let board = store.current {
                    if board.isEmpty {
                        SREmpty(
                            title: "No games yet",
                            icon: "trophy",
                            message: "Finish a game and it lands here — solo games count for high scores."
                        )
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("leaderboard-empty")
                    } else {
                        overall(board)
                        ForEach(board.games) { game in
                            gameBoard(game, meId: board.meId)
                        }
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("leaderboard-screen")
        .srGround(.warm)
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        // One read per window change, and the first on arrival.
        .task(id: store.window) { await store.load() }
        .srRefreshable { await store.load() }
        .overlay {
            if store.loading && store.current == nil { ProgressView().tint(SR.accent) }
        }
        .overlay(alignment: .bottom) {
            if let message = store.message { SRBanner(text: message) }
        }
    }

    // MARK: Overall

    private func overall(_ board: GameLeaderboard) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Overall", trailing: "Wins")
            VStack(spacing: 0) {
                ForEach(Array(board.overall.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(SR.divider) }
                    LeaderboardLine(
                        rank: row.rank,
                        name: row.name,
                        isMe: row.playerId == board.meId,
                        detail: LeaderboardWords.count(row.played, "game", "games"),
                        figure: "\(row.wins)",
                        spoken: LeaderboardWords.count(row.wins, "win", "wins")
                    )
                    .accessibilityIdentifier("leaderboard-overall-\(row.playerId)")
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("leaderboard-overall")
    }

    // MARK: One game

    private func gameBoard(_ game: LeaderboardGame, meId: String) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: game.title, trailing: game.scored ? "Best" : "Wins")
            VStack(spacing: 0) {
                ForEach(Array(game.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(SR.divider) }
                    LeaderboardLine(
                        rank: row.rank,
                        name: row.name,
                        isMe: row.playerId == meId,
                        detail: detail(row, scored: game.scored),
                        figure: figureText(row, scored: game.scored),
                        spoken: spokenText(row, scored: game.scored)
                    )
                    .accessibilityIdentifier("leaderboard-\(game.game)-\(row.playerId)")
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("leaderboard-game-\(game.game)")
    }

    /// The right-hand figure: the best score, or wins for a game with no score.
    private func figureText(_ row: LeaderboardRow, scored: Bool) -> String {
        guard scored else { return "\(row.wins)" }
        guard let best = row.best else { return "–" }
        return "\(best)"
    }

    private func spokenText(_ row: LeaderboardRow, scored: Bool) -> String {
        guard scored else { return LeaderboardWords.count(row.wins, "win", "wins") }
        guard let best = row.best else { return "no score" }
        return "best \(best)"
    }

    /// Under a name: what the best was set on, then wins and games.
    private func detail(_ row: LeaderboardRow, scored: Bool) -> String {
        let tally = scored
            ? "\(LeaderboardWords.count(row.wins, "win", "wins")) · \(LeaderboardWords.count(row.played, "game", "games"))"
            : LeaderboardWords.count(row.played, "game", "games")
        guard scored, let label = row.bestLabel, !label.isEmpty else { return tally }
        return "\(label)\n\(tally)"
    }
}

/// One row of a board: rank, name (mine picked out), a detail line, a figure.
struct LeaderboardLine: View {
    let rank: Int
    let name: String
    let isMe: Bool
    let detail: String
    let figure: String
    let spoken: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(rank)")
                .font(SR.Text.display(24))
                .foregroundStyle(rank == 1 ? SR.accent : SR.inkGhost)
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(isMe ? "\(name) (you)" : name)
                        .font(SR.Text.title())
                        .foregroundStyle(isMe ? SR.accentInk : SR.ink)
                    if rank == 1 {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SR.accent)
                            .accessibilityLabel("First")
                    }
                }
                Text(detail)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(figure)
                .font(SR.Text.figure(24))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
                .accessibilityLabel(spoken)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, isMe ? 6 : 0)
        .background {
            if isMe {
                RoundedRectangle(cornerRadius: SR.Radius.soft, style: .continuous)
                    .fill(SR.accentInk.opacity(0.08))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - New high score, on a finished room

/// The line a finished room shows when the site says somebody in it set a
/// new family high score: "New high score this week — Sam". Nothing when
/// nobody did (or the site has not said yet).
struct GameRecordLine: View {
    let room: GameRoom

    var body: some View {
        if let text = GameRecordLine.text(room) {
            Label(text, systemImage: "trophy.fill")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.accent)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("game-record")
        }
    }

    /// The sentence, or nil. The widest window anyone reached, and who.
    static func text(_ room: GameRoom) -> String? {
        guard !room.records.isEmpty else { return nil }
        let order = ["all", "week", "day"]
        guard let widest = order.first(where: { window in room.records.values.contains(window) }) else { return nil }
        let when: String
        switch widest {
        case "all": when = "ever"
        case "week": when = "this week"
        default: when = "today"
        }
        let ids = room.records.filter { $0.value == widest }.map(\.key).sorted()
        let names = ids.map { $0 == room.meId ? "You" : room.name(of: $0) }
        if names == ["You"] { return "New high score \(when)!" }
        return "New high score \(when) — \(GameNames.list(names))"
    }
}
