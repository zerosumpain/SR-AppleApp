import SwiftUI

// What the three offline word games draw alike — Boggle, Anagram Blitz and
// Categories: the clock bar, everyone's scores, words as chips, and the
// "See the table" button that ends a reveal. Each game's view brings its own
// board; these keep the rest of the page the same from game to game.

/// The clock: what it is counting to, the seconds left, and a chip on the right.
struct OfflineWordClock: View {
    let clock: OfflineHostClock
    /// "Starting in", "Time left", "Time's up".
    let label: String
    /// The host time counted down to; nil shows no count.
    let until: Double?
    var chip: String? = nil
    var tone: Color = SR.ink

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SR.accent)
                .accessibilityHidden(true)
            Text(label)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.inkSecondary)
                .lineLimit(1)
            if let until {
                OfflineCountdown(clock: clock, until: until, font: SR.Text.figure(24), tone: tone)
            }
            Spacer(minLength: 8)
            if let chip {
                SRGlassChip(text: chip, tone: SR.accent)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 12)
        .srGlassCard(.paper)
    }
}

/// One row of the scores: a player, a short line, a figure.
struct OfflineWordScoreRow: Identifiable, Equatable {
    let id: String
    let name: String
    /// "12 words", "5 of 8 answered".
    let detail: String
    let score: Int?
    let away: Bool
    /// Tapped on from the reveal: shows a tick.
    let ready: Bool
}

/// Everyone, best first, one row each — five names fit one column.
struct OfflineWordScores: View {
    let title: String
    let rows: [OfflineWordScoreRow]
    let me: String
    /// Seat order, for each player's colour.
    let players: [OfflinePlayer]
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: title)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(SR.divider) }
                    HStack(spacing: 12) {
                        OfflineInitial(name: row.name, size: 28,
                                       tone: OfflineSeatColour.of(players.firstIndex { $0.id == row.id } ?? 0))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.id == me ? "\(row.name) (you)" : row.name)
                                .font(SR.Text.title(16))
                                .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(row.away ? "\(row.detail) · left" : row.detail)
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if row.ready {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(SR.good)
                                .accessibilityLabel("ready")
                        }
                        if let score = row.score {
                            Text("\(score)")
                                .font(SR.Text.figure(22))
                                .foregroundStyle(SR.ink)
                                .fixedSize()
                        }
                    }
                    .frame(minHeight: SR.tapTarget)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
            .accessibilityIdentifier(id)
        }
    }
}

/// A word as a chip: the word, what it scored, crossed out when it scored nothing.
struct OfflineWordChip: Identifiable, Equatable {
    let id: String
    let text: String
    let points: Int?
    var crossed = false
    var lit = false
    /// What VoiceOver reads.
    let spoken: String
}

/// Words that wrap in a grid of chips. With `pick`, each is a button.
struct OfflineWordChips: View {
    let chips: [OfflineWordChip]
    var pick: ((String) -> Void)? = nil

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(chips) { chip in
                if let pick {
                    Button { pick(chip.id) } label: { face(chip) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows it on the board")
                        .accessibilityAddTraits(chip.lit ? .isSelected : [])
                } else {
                    face(chip)
                }
            }
        }
    }

    private func face(_ chip: OfflineWordChip) -> some View {
        HStack(spacing: 6) {
            Text(chip.text)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(chip.lit ? SR.paper : chip.crossed ? SR.inkGhost : SR.ink)
                .strikethrough(chip.crossed, color: SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            if let points = chip.points {
                Text("\(points)")
                    .font(SR.Text.label())
                    .foregroundStyle(chip.lit ? SR.paper : chip.crossed ? SR.inkGhost : SR.accent)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: SR.tapTarget)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 2, style: .continuous)
                .fill(chip.lit ? SR.accentInk : Color.clear)
        )
        .srGlassCard(chip.lit ? .clear : .paper, radius: SR.Glass.innerRadius + 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.spoken)
    }
}

/// The end of a reveal: "See the table", then who it is waiting for.
struct OfflineWordContinue: View {
    let ready: Bool
    /// Names of the players who have not tapped on yet.
    let waitingOn: [String]
    let id: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button {
                SRHaptic.tap()
                action()
            } label: {
                SRButtonLabel(title: ready ? "Waiting" : "See the table", icon: ready ? "hourglass" : "list.number", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(ready)
            .accessibilityIdentifier(id)
            if ready, !waitingOn.isEmpty {
                Text("Waiting for \(waitingOn.joined(separator: ", ")).")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
