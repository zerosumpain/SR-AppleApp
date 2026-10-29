import SwiftUI

// The finished page's parts that the room games share: the headline, the
// standings card and the Play again / Done pair. The same shapes Tap Duel,
// Wordle Race and Quiz Night draw inline — pulled out here so the rest do not
// copy them a dozen times.
//
// The standings are the moment a game pays off, so they are drawn as one:
// gold, silver and bronze for the first three, my own row lit, the rows
// settling in one after another, and — when I won — a burst of confetti and
// a success tap. Under Reduce Motion the rows are simply there and nothing
// falls.

enum GameResults {
    /// "You win", "Sam wins", "Sam and You tie", or `none` when nobody won.
    /// Solo games say `solo` instead.
    static func title(_ room: GameRoom, solo: String, none: String) -> String {
        if room.solo { return solo }
        let names = room.winnerIds.map { $0 == room.meId ? "You" : room.name(of: $0) }
        switch names.count {
        case 0: return none
        case 1: return names[0] == "You" ? "You win" : "\(names[0]) wins"
        default: return "\(GameNames.list(names)) tie"
        }
    }

    /// Under the headline, for everyone but the host.
    static func strap(_ room: GameRoom) -> String? {
        room.isHost ? nil : "Only \(room.host?.name ?? "the host") can start another round of this one."
    }

    /// "1 word", "3 words".
    static func count(_ n: Int, _ one: String, _ many: String) -> String {
        n == 1 ? "1 \(one)" : "\(n) \(many)"
    }

    /// The confetti's seed for a room: the same burst every time it is seen,
    /// a different one for every room. Not `hashValue`, which changes each launch.
    static func seed(_ roomId: String) -> UInt64 {
        roomId.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
    }

    /// I won, against somebody: the confetti's cue. A solo round is a score,
    /// not a win, unless it set a new family high score.
    static func celebrates(_ room: GameRoom) -> Bool {
        if room.solo { return room.records[room.meId] != nil }
        return room.winnerIds.contains(room.meId)
    }
}

/// The final table: place (a medal for the first three), name (with a crown
/// for a winner), a detail line, and a figure on the right.
struct GameStandingsCard: View {
    let room: GameRoom
    let label: String
    let id: String
    let detail: (GameStanding) -> String
    /// The right-hand figure and what VoiceOver calls it; nil for none.
    let figure: (GameStanding) -> (text: String, spoken: String)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The rows have settled in.
    @State private var shown = false
    /// The win has been felt once on this page.
    @State private var cheered = false

    private var rows: [GameStanding] { room.standings ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            GameRecordLine(room: room)
            SRSectionLabel(text: label, trailing: rows.count > 1 ? "\(rows.count) players" : nil)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(SR.divider) }
                    standingRow(row, place: index + 1)
                        .opacity(shown || reduceMotion ? 1 : 0)
                        .offset(y: shown || reduceMotion ? 0 : 14)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.45).delay(0.08 * Double(index)), value: shown)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
            .accessibilityIdentifier(id)
        }
        .overlay(alignment: .top) {
            if GameResults.celebrates(room) {
                GameConfettiView(seed: GameResults.seed(room.id))
                    .frame(height: 420)
                    .offset(y: -60)
            }
        }
        .onAppear {
            shown = true
            if !cheered && GameResults.celebrates(room) {
                cheered = true
                SRHaptic.ok()
            }
        }
    }

    private func standingRow(_ row: GameStanding, place: Int) -> some View {
        let mine = row.id == room.meId
        let winner = room.winnerIds.contains(row.id)
        return HStack(alignment: .center, spacing: 12) {
            GameMedal(place: place, side: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.name + (mine ? " (you)" : ""))
                        .font(SR.Text.title())
                        .foregroundStyle(mine ? SR.accentInk : SR.ink)
                    if winner, !room.solo {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xE9A800))
                            .accessibilityLabel("Winner")
                    }
                }
                let line = detail(row)
                if !line.isEmpty {
                    Text(line)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let figure = figure(row) {
                Text(figure.text)
                    .font(SR.Text.figure(place == 1 ? 28 : 24))
                    .foregroundStyle(SR.ink)
                    .monospacedDigit()
                    .accessibilityLabel(figure.spoken)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, mine ? 8 : 0)
        .background {
            if mine {
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                    .fill(SR.accentInk.opacity(0.09))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("\(id)-\(row.id)")
    }
}

/// Play again (the host) and Done — big, and the host's again the one lit.
struct GameFinishedButtons<Store: GameRoomStoring>: View {
    let room: GameRoom
    @ObservedObject var store: Store
    /// "anagram", "sprint", "memory".
    let prefix: String
    let done: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if room.isHost {
                Button {
                    SRHaptic.tap()
                    Task { _ = await store.act("again") }
                } label: {
                    Group {
                        if store.busy {
                            ProgressView().tint(SR.cream)
                        } else {
                            SRButtonLabel(title: "Play again", icon: "arrow.counterclockwise", fill: true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(store.busy)
                .accessibilityLabel("Play again")
                .accessibilityIdentifier("\(prefix)-again")
            }
            Button {
                SRHaptic.tap()
                done()
            } label: {
                SRButtonLabel(title: "Done", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("\(prefix)-done")
        }
    }
}

/// A small initial in a circle — who found a word, who has answered.
struct GameInitial: View {
    let name: String
    var filled: Bool = true
    var tone: Color = SR.accentInk
    var side: CGFloat = 26

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(SR.Text.label(max(11, side * 0.45)))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(filled ? SR.paper : SR.inkSecondary)
            .frame(width: side, height: side)
            .background(Circle().fill(filled ? tone : Color.clear))
            .overlay(Circle().strokeBorder(filled ? Color.clear : SR.line, lineWidth: 1.5))
            .accessibilityLabel(name)
    }
}
