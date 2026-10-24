import SwiftUI
import UIKit

/// Quick Draw on one phone: the stand-off, DRAW!, and each round's times.
///
/// The whole stand-off is the button — a `TapSurface` under everything, so a
/// touch keeps its own hardware timestamp. DRAW appears when this phone's
/// estimate of the host clock reaches the host's `drawAt`; `OfflineStimulus`
/// notes the frame that showed it, and the reaction is measured from that
/// frame to the touch, here, so Bluetooth latency never enters the figure.
/// The view sends the measured time and waits for the host's next view.
struct QuickDrawView: View {
    let context: OfflineGameContext<QuickDrawRules>
    @StateObject private var stimulus = OfflineStimulus()
    /// My tap this round, shown at once rather than after the host's echo.
    @State private var local: QuickDrawRules.Tap?
    @State private var localRound = 0

    private var view: QuickDrawRules.PlayerView { context.view }

    var body: some View {
        Group {
            switch view.phase {
            case .waiting: standOff
            case .result, .over: result
            }
        }
        .onAppear { arm() }
        .onChange(of: view.round) { _, _ in arm() }
        .onChange(of: view.phase) { _, _ in arm() }
        .onChange(of: context.clock) { _, _ in arm() }
        .onDisappear { stimulus.reset() }
    }

    // MARK: - The stand-off

    private var standOff: some View {
        ZStack {
            ground.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("ROUND \(view.round) OF \(view.maxRounds) · FIRST TO \(view.winsNeeded)")
                    .font(SR.Text.label(13))
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(ink.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(headline)
                    .font(SR.Text.hero(72))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                if let after = afterTap {
                    Text(after)
                        .font(SR.Text.display(26))
                        .foregroundStyle(ink.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                QuickDrawScoreStrip(rows: view.rows, me: context.me, ink: ink, revealTaps: true)
                Text(footer)
                    .font(SR.Text.mono(13))
                    .foregroundStyle(ink.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, SR.gutter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            if playing {
                TapSurface(label: accessibilityText) { touched(at: $0) }
                    .ignoresSafeArea()
                    .accessibilityIdentifier("quick-draw-surface")
            }
        }
    }

    /// Whether I am in this match and still here (not a spectator).
    private var playing: Bool {
        view.rows.contains { $0.id == context.me && !$0.away }
    }

    /// My tap this round: the host's word if it has spoken, else my own.
    private var myTap: QuickDrawRules.Tap? {
        view.myTap ?? (localRound == view.round ? local : nil)
    }

    private var headline: String {
        if let tap = myTap {
            return tap.early ? "Too soon!" : "Bang!"
        }
        return stimulus.shown ? "DRAW!" : "Steady…"
    }

    private var afterTap: String? {
        guard let tap = myTap else { return nil }
        if tap.early { return "You sit this one out" }
        return tap.ms.map { "\($0) ms" }
    }

    private var footer: String {
        if !playing { return "You are watching this match." }
        if myTap != nil { return "Waiting for the others." }
        return stimulus.shown ? "Tap anywhere!" : "Tap when it says DRAW — not before."
    }

    private var ground: Color {
        if myTap?.early == true { return SR.error }
        return stimulus.shown ? SR.good : SR.ink
    }

    /// Paper on every ground here: ink, the go colour and the error colour
    /// all carry it.
    private var ink: Color { SR.paper }

    private var accessibilityText: String {
        if myTap != nil { return "Tapped. Waiting for the others." }
        return stimulus.shown ? "Draw now" : "Steady. Wait for draw."
    }

    // MARK: - A round's result

    private var result: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Round \(view.round) of \(view.maxRounds)", title: resultTitle)
                QuickDrawTimes(rows: view.rows, me: context.me, winner: view.roundWinner)
                if view.phase == .result {
                    HStack(spacing: 8) {
                        Text("Next round in")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                        OfflineCountdown(clock: context.clock, until: view.resultUntil, font: SR.Text.mono(), tone: SR.inkMuted)
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("quick-draw-result")
    }

    private var resultTitle: String {
        if view.phase == .over {
            let names = view.champions.map { $0 == context.me ? "You" : context.name(of: $0) }
            if names.count == 1 { return names[0] == "You" ? "You win" : "\(names[0]) wins" }
            return names.isEmpty ? "Nobody won" : "A tie"
        }
        guard let winner = view.roundWinner else { return "Nobody took it" }
        return winner == context.me ? "You took it" : "\(context.name(of: winner)) took it"
    }

    // MARK: - Acting

    /// Point the stimulus at this round's DRAW, or rest it between rounds.
    private func arm() {
        if view.phase == .waiting {
            if localRound != view.round {
                stimulus.reset()
                local = nil
                localRound = view.round
            }
            stimulus.arm(at: view.drawAt, clock: context.clock)
        } else {
            stimulus.reset()
        }
    }

    /// A touch on the stand-off, at its own hardware timestamp.
    private func touched(at timestamp: Double) {
        guard view.phase == .waiting, playing, myTap == nil else { return }
        let round = view.round
        localRound = round
        if let ms = stimulus.reactionMs(touchedAt: timestamp) {
            let counts = OfflineReaction.counts(ms)
            local = QuickDrawRules.Tap(early: !counts, ms: counts ? ms : nil)
            if counts { SRHaptic.ok() } else { SRHaptic.bad() }
            context.send(.draw(round: round, ms: ms))
        } else {
            local = QuickDrawRules.Tap(early: true, ms: nil)
            SRHaptic.bad()
            context.send(.early(round: round))
        }
    }
}

/// Everyone's round wins as a strip of names and pips: fits five players on
/// a 375pt phone because each row shares the width and truncates its name.
struct QuickDrawScoreStrip: View {
    let rows: [QuickDrawRules.Row]
    let me: String
    var ink: Color = SR.ink
    /// Mark who has tapped this round.
    var revealTaps = false

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.id == me ? "You" : row.name)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(ink.opacity(row.away ? 0.5 : 1))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if revealTaps && row.tapped {
                        Image(systemName: row.early ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ink.opacity(0.85))
                    }
                    Spacer(minLength: 6)
                    Text(String(repeating: "●", count: min(row.wins, QuickDrawRules.winsNeeded)))
                        .font(.system(size: 12))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .fixedSize()
                    Text("\(row.wins)")
                        .font(SR.Text.mono(15))
                        .foregroundStyle(ink)
                        .frame(minWidth: 18, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: 420)
    }
}

/// This round's times, fastest first, with the running score.
struct QuickDrawTimes: View {
    let rows: [QuickDrawRules.Row]
    let me: String
    let winner: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack(spacing: 10) {
                    Text(row.id == me ? "You" : row.name)
                        .font(SR.Text.title())
                        .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                    if row.id == winner {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SR.accent)
                            .accessibilityLabel("Took the round")
                    }
                    Spacer(minLength: 8)
                    Text(time(row))
                        .font(SR.Text.mono(15))
                        .foregroundStyle(row.id == winner ? SR.accent : SR.inkSecondary)
                        .lineLimit(1)
                    Text("\(row.wins)")
                        .font(SR.Text.display(20))
                        .foregroundStyle(SR.ink)
                        .frame(minWidth: 26, alignment: .trailing)
                        .accessibilityLabel("\(row.wins) rounds")
                }
                .frame(minHeight: SR.tapTarget)
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
    }

    private var sorted: [QuickDrawRules.Row] {
        rows.sorted { key($0) < key($1) }
    }

    private func key(_ row: QuickDrawRules.Row) -> Int {
        if let ms = row.ms { return ms }
        if row.early { return Int.max - 1 }
        return Int.max
    }

    private func time(_ row: QuickDrawRules.Row) -> String {
        if row.away { return "left" }
        if let ms = row.ms { return "\(ms) ms" }
        if row.early { return "jumped" }
        return "no tap"
    }
}
