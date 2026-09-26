import SwiftUI

// The finished page's parts that Anagram Blitz, Quick Maths Sprint and
// Sequence Memory share: the headline, the standings card and the Play again /
// Done pair. The same shapes Tap Duel, Wordle Race and Quiz Night draw
// inline — pulled out here so three more games do not copy them three times.

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
}

/// The final table: place, name (with a crown for a winner), a detail line,
/// and a figure on the right.
struct GameStandingsCard: View {
    let room: GameRoom
    let label: String
    let id: String
    let detail: (GameStanding) -> String
    /// The right-hand figure and what VoiceOver calls it; nil for none.
    let figure: (GameStanding) -> (text: String, spoken: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: label)
            VStack(spacing: 0) {
                ForEach(Array((room.standings ?? []).enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(SR.divider) }
                    HStack(alignment: .center, spacing: 12) {
                        Text("\(index + 1)")
                            .font(SR.Text.display(26))
                            .foregroundStyle(room.winnerIds.contains(row.id) ? SR.accent : SR.inkGhost)
                            .frame(width: 32, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(row.name + (row.id == room.meId ? " (you)" : ""))
                                    .font(SR.Text.title())
                                    .foregroundStyle(SR.ink)
                                if room.winnerIds.contains(row.id), !room.solo {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(SR.accent)
                                        .accessibilityLabel("Winner")
                                }
                            }
                            Text(detail(row))
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if let figure = figure(row) {
                            Text(figure.text)
                                .font(SR.Text.figure(24))
                                .foregroundStyle(SR.ink)
                                .monospacedDigit()
                                .accessibilityLabel(figure.spoken)
                        }
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("\(id)-\(row.id)")
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
            .accessibilityIdentifier(id)
        }
    }
}

/// Play again (the host) and Done.
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
                    SRButtonLabel(title: "Play again", icon: "arrow.counterclockwise", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(store.busy)
                .accessibilityIdentifier("\(prefix)-again")
            }
            Button { done() } label: { SRButtonLabel(title: "Done", fill: true) }
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
            .foregroundStyle(filled ? SR.paper : SR.inkSecondary)
            .frame(width: side, height: side)
            .background(Circle().fill(filled ? tone : Color.clear))
            .overlay(Circle().strokeBorder(filled ? Color.clear : SR.line, lineWidth: 1.5))
            .accessibilityLabel(name)
    }
}
