import SwiftUI

/// The round's scorecard: a row for every hole, a column for every player,
/// each score coloured against par, and the totals at the foot.
struct MiniGolfScorecardView: View {
    let round: MiniGolfRound

    /// Green under par, ink at par, amber over; faint for not played.
    static func tone(_ strokes: Int?, par: Int) -> Color {
        guard let strokes else { return SR.inkGhost }
        switch MiniGolfScoreWord.tone(strokes: strokes, par: par) {
        case -1: return SR.good
        case 0: return SR.ink
        default: return SR.warn
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                Text(round.loop.title.uppercased() + " · PAR \(round.loop.par)")
                    .font(SR.Text.label())
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(SR.accent)
                grid
                    .padding(SR.cardPadding)
                    .srGlassCard(.paper)
                Text("Under par in green, over par in amber. A hole takes at most par + 4.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 16)
        }
        .srPaper()
        .accessibilityIdentifier("mini-golf-scorecard-sheet")
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            header
            Divider()
            ForEach(0..<round.holeCount, id: \.self) { slot in
                holeRow(slot)
            }
            Divider()
            totals
        }
    }

    private var header: some View {
        GridRow {
            Text("HOLE")
                .font(SR.Text.label(11))
                .foregroundStyle(SR.inkMuted)
            Text("PAR")
                .font(SR.Text.label(11))
                .foregroundStyle(SR.inkMuted)
                .gridColumnAlignment(.center)
            ForEach(Array(round.players.indices), id: \.self) { index in
                playerHead(index)
            }
        }
    }

    private func playerHead(_ index: Int) -> some View {
        let player = round.players[index]
        return VStack(spacing: 3) {
            MiniGolfBallBadge(seat: player.seat, size: 14)
            Text(String(player.name.prefix(6)))
                .font(SR.Text.label(11))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: 40)
        .gridColumnAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private func holeRow(_ slot: Int) -> some View {
        let hole = round.hole(at: slot)
        let current = slot == round.holeSlot && !round.isOver
        return GridRow {
            HStack(spacing: 6) {
                Text("\(hole.number)")
                    .font(SR.monoBold(13))
                    .foregroundStyle(current ? SR.accent : SR.ink)
                    .frame(minWidth: 20, alignment: .trailing)
                Text(hole.name)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text("\(hole.par)")
                .font(SR.Text.mono(13))
                .foregroundStyle(SR.inkMuted)
            ForEach(Array(round.players.indices), id: \.self) { index in
                scoreCell(round.strokes(player: index, slot: slot), par: hole.par)
                    .accessibilityLabel(cellLabel(index, slot: slot))
            }
        }
    }

    private func cellLabel(_ index: Int, slot: Int) -> String {
        let hole = round.hole(at: slot)
        let name = round.players[index].name
        guard let strokes = round.strokes(player: index, slot: slot) else { return "\(name), hole \(hole.number): not played" }
        return "\(name), hole \(hole.number): \(strokes), \(MiniGolfScoreWord.word(strokes: strokes, par: hole.par))"
    }

    private func scoreCell(_ strokes: Int?, par: Int) -> some View {
        let text = strokes.map { "\($0)" } ?? "·"
        let tone = Self.tone(strokes, par: par)
        let ace = strokes == 1
        return Text(text)
            .font(SR.monoBold(15))
            .foregroundStyle(tone)
            .frame(minWidth: 30, minHeight: 26)
            .background {
                if ace {
                    Circle().stroke(MiniGolfPaint.gold, lineWidth: 2)
                } else if let strokes, strokes < par {
                    Circle().stroke(SR.good.opacity(0.6), lineWidth: 1)
                }
            }
    }

    private var totals: some View {
        GridRow {
            Text("TOTAL")
                .font(SR.Text.label(12))
                .foregroundStyle(SR.ink)
            Text("\(round.loop.par)")
                .font(SR.monoBold(13))
                .foregroundStyle(SR.inkMuted)
            ForEach(Array(round.players.indices), id: \.self) { index in
                VStack(spacing: 2) {
                    Text("\(round.total(index))")
                        .font(SR.monoBold(16))
                        .foregroundStyle(SR.ink)
                    Text(MiniGolfScoreWord.toPar(round.toPar(index)))
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(round.players[index].name): \(round.total(index)) strokes, \(MiniGolfScoreWord.toPar(round.toPar(index))) to par")
            }
        }
    }
}
