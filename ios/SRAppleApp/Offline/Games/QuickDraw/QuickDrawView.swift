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
///
/// The overhaul (2026-10-29) painted the stand-off as a desert street at
/// dusk that blazes when DRAW lands (and burns red on a jump), gave every
/// player a row of wins to fill, drew each round's times as a race of bars,
/// and keeps this phone's fastest draw — "New best!" when you beat it.
struct QuickDrawView: View {
    let context: OfflineGameContext<QuickDrawRules>
    @StateObject private var stimulus = OfflineStimulus()
    /// My tap this round, shown at once rather than after the host's echo.
    @State private var local: QuickDrawRules.Tap?
    @State private var localRound = 0
    /// My quickest counted draw this match.
    @State private var fastest: Int?
    /// This phone's best, recorded once when the match ends.
    @State private var best: NearbyPlayBestOutcome?
    @State private var burstToken = 0
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: view.phase) { _, new in
            arm()
            settled(new)
        }
        .onChange(of: context.clock) { _, _ in arm() }
        .onChange(of: scenePhase) { _, new in
            // The display link stops in the background; aim it again on return.
            if new == .active { arm() }
        }
        .onDisappear { stimulus.reset() }
    }

    // MARK: - The stand-off

    private var standOff: some View {
        ZStack {
            QuickDrawStreet(mood: mood)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Text("ROUND \(view.round) OF \(view.maxRounds) · FIRST TO \(view.winsNeeded)")
                    .font(SR.Text.label(13))
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(headline)
                    .font(SR.Text.hero(76))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .scaleEffect(stimulus.shown && myTap == nil ? 1.08 : 1)
                    .srAnimation(.spring(response: 0.25, dampingFraction: 0.5), value: stimulus.shown)
                if let after = afterTap {
                    Text(after)
                        .font(SR.Text.display(28))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.25)))
                }
                Spacer(minLength: 0)
                QuickDrawScoreStrip(rows: view.rows, me: context.me, winsNeeded: view.winsNeeded,
                                    ink: Color.white, revealTaps: true)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.22)))
                Text(footer)
                    .font(SR.Text.mono(13))
                    .foregroundStyle(Color.white.opacity(0.85))
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

    private var mood: QuickDrawStreet.Mood {
        if myTap?.early == true { return .jumped }
        return stimulus.shown ? .draw : .steady
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

    private var accessibilityText: String {
        if myTap != nil { return "Tapped. Waiting for the others." }
        return stimulus.shown ? "Draw now" : "Steady. Wait for draw."
    }

    // MARK: - A round's result

    private var result: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NearbyPlayBanner(kicker: "Round \(view.round) of \(view.maxRounds)", title: resultTitle,
                                 mine: tookIt, mark: .symbol(view.phase == .over ? "trophy.fill" : "bolt.fill")) {
                    if view.phase == .result {
                        NearbyPlayBannerClock(clock: context.clock, until: view.resultUntil,
                                              total: QuickDrawRules.resultPause, mine: false)
                            .accessibilityLabel("Next round soon")
                    }
                }
                QuickDrawTimes(rows: view.rows, me: context.me, winner: view.roundWinner)
                QuickDrawScoreStrip(rows: view.rows, me: context.me, winsNeeded: view.winsNeeded)
                    .padding(SR.cardPadding)
                    .srGlassCard(.paper)
                bestCard
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .overlay { NearbyPlayBurst(token: burstToken) }
        .accessibilityIdentifier("quick-draw-result")
    }

    private var tookIt: Bool {
        if view.phase == .over { return view.champions == [context.me] }
        return view.roundWinner == context.me
    }

    @ViewBuilder
    private var bestCard: some View {
        if let best {
            NearbyPlayBestLine(outcome: best, value: fastest ?? best.best, format: NearbyPlayBestMath.milliseconds)
        } else if let previous = NearbyPlayBestBook.best(QuickDrawRules.info.id), playing {
            HStack(spacing: 10) {
                Image(systemName: "trophy")
                    .font(SR.Text.title(18))
                    .foregroundStyle(SR.warn)
                    .accessibilityHidden(true)
                Text("Fastest draw on this phone")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                Spacer(minLength: 8)
                Text(NearbyPlayBestMath.milliseconds(previous))
                    .font(SR.Text.title(17))
                    .foregroundStyle(SR.ink)
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityElement(children: .combine)
        }
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

    /// A round has settled: note my time, cheer a win, keep a best at the end.
    private func settled(_ phase: QuickDrawRules.Phase) {
        guard phase != .waiting else { return }
        if let ms = view.rows.first(where: { $0.id == context.me })?.ms, OfflineReaction.counts(ms) {
            fastest = min(fastest ?? ms, ms)
        }
        if phase == .result && view.roundWinner == context.me { burstToken += 1 }
        if phase == .over {
            if view.champions == [context.me] {
                burstToken += 1
                SRHaptic.ok()
            }
            if best == nil, playing, let fastest {
                best = NearbyPlayBestBook.record(QuickDrawRules.info.id, value: fastest, rule: .lower)
            }
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

/// The stand-off's backdrop: a desert street at dusk, a low sun, two cacti
/// and the boards of a saloon, drawn once per mood. DRAW turns the sky to a
/// blaze of green-gold; a jump turns it red. Fixed colours: it is a scene,
/// the same in light and dark, and only white type sits on it.
struct QuickDrawStreet: View, Equatable {
    enum Mood: Equatable { case steady, draw, jumped }
    let mood: Mood

    var body: some View {
        Canvas { context, size in
            QuickDrawStreet.paint(in: &context, size: size, mood: mood)
        }
        // No easing: DRAW must be on the glass in the frame it lands.
        .accessibilityHidden(true)
    }

    static func paint(in context: inout GraphicsContext, size: CGSize, mood: Mood) {
        let w = size.width, h = size.height
        let sky: [Color]
        switch mood {
        case .steady: sky = [Color(hex: 0x1B1640), Color(hex: 0x5B2A6E), Color(hex: 0xE0784A)]
        case .draw: sky = [Color(hex: 0x0C6B3C), Color(hex: 0x1FA463), Color(hex: 0xF4D35E)]
        case .jumped: sky = [Color(hex: 0x5A0B12), Color(hex: 0xB3261E), Color(hex: 0xF08A5D)]
        }
        let horizon = h * 0.68
        context.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon)),
                     with: .linearGradient(Gradient(colors: sky), startPoint: CGPoint(x: w / 2, y: 0),
                                           endPoint: CGPoint(x: w / 2, y: horizon)))
        // The sun, half down behind the street.
        let sunR = min(w, h) * 0.16
        let sun = CGRect(x: w * 0.5 - sunR, y: horizon - sunR * 1.1, width: sunR * 2, height: sunR * 2)
        context.fill(Path(ellipseIn: sun), with: .color(Color(hex: 0xFFE3A3).opacity(mood == .draw ? 0.95 : 0.8)))
        // The street.
        context.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)),
                     with: .linearGradient(Gradient(colors: [Color(hex: 0x6B3F22), Color(hex: 0x2E1A0E)]),
                                           startPoint: CGPoint(x: w / 2, y: horizon), endPoint: CGPoint(x: w / 2, y: h)))
        var tracks = Path()
        tracks.move(to: CGPoint(x: w * 0.42, y: horizon))
        tracks.addLine(to: CGPoint(x: w * 0.12, y: h))
        tracks.move(to: CGPoint(x: w * 0.58, y: horizon))
        tracks.addLine(to: CGPoint(x: w * 0.88, y: h))
        context.stroke(tracks, with: .color(Color.black.opacity(0.18)), lineWidth: 2)
        // A saloon front on the left, a cactus each side.
        let silhouette = Color(hex: 0x120A1C).opacity(0.85)
        let saloon = CGRect(x: -w * 0.02, y: horizon - h * 0.2, width: w * 0.26, height: h * 0.2)
        context.fill(Path(saloon), with: .color(silhouette))
        context.fill(Path(CGRect(x: saloon.minX, y: saloon.minY - h * 0.04, width: saloon.width * 0.7, height: h * 0.04)),
                     with: .color(silhouette))
        cactus(in: &context, x: w * 0.82, base: horizon, height: h * 0.16, colour: silhouette)
        cactus(in: &context, x: w * 0.32, base: horizon, height: h * 0.08, colour: silhouette)
    }

    private static func cactus(in context: inout GraphicsContext, x: CGFloat, base: CGFloat, height: CGFloat, colour: Color) {
        let trunk = height * 0.22
        var path = Path(roundedRect: CGRect(x: x - trunk / 2, y: base - height, width: trunk, height: height),
                        cornerRadius: trunk / 2)
        path.addRoundedRect(in: CGRect(x: x - trunk * 1.9, y: base - height * 0.7, width: trunk * 0.8, height: height * 0.38),
                            cornerSize: CGSize(width: trunk * 0.4, height: trunk * 0.4))
        path.addRoundedRect(in: CGRect(x: x - trunk * 1.9, y: base - height * 0.4, width: trunk * 1.6, height: trunk * 0.7),
                            cornerSize: CGSize(width: trunk * 0.35, height: trunk * 0.35))
        path.addRoundedRect(in: CGRect(x: x + trunk * 1.1, y: base - height * 0.85, width: trunk * 0.8, height: height * 0.42),
                            cornerSize: CGSize(width: trunk * 0.4, height: trunk * 0.4))
        path.addRoundedRect(in: CGRect(x: x + trunk * 0.3, y: base - height * 0.5, width: trunk * 1.6, height: trunk * 0.7),
                            cornerSize: CGSize(width: trunk * 0.35, height: trunk * 0.35))
        context.fill(path, with: .color(colour))
    }
}

/// Everyone's round wins as a row of pips to fill, one row each: fits five
/// players on a 375pt phone because each row shares the width and
/// truncates its name.
struct QuickDrawScoreStrip: View {
    let rows: [QuickDrawRules.Row]
    let me: String
    var winsNeeded: Int = QuickDrawRules.winsNeeded
    var ink: Color = SR.ink
    /// Mark who has tapped this round.
    var revealTaps = false

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { seat, row in
                HStack(spacing: 8) {
                    Text(row.id == me ? "You" : row.name)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(ink.opacity(row.away ? 0.5 : 1))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if revealTaps && row.tapped {
                        Image(systemName: row.early ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(SR.Text.label(13))
                            .foregroundStyle(ink.opacity(0.9))
                    }
                    Spacer(minLength: 6)
                    HStack(spacing: 4) {
                        ForEach(0..<max(1, winsNeeded), id: \.self) { pip in
                            Circle()
                                .fill(pip < row.wins ? OfflineSeatColour.of(seat) : ink.opacity(0.18))
                                .overlay { Circle().strokeBorder(ink.opacity(pip < row.wins ? 0.6 : 0.25), lineWidth: 1) }
                                .frame(width: 12, height: 12)
                        }
                    }
                    .fixedSize()
                    Text("\(row.wins)")
                        .font(SR.Text.mono(15))
                        .foregroundStyle(ink)
                        .frame(minWidth: 18, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(row))
            }
        }
        .frame(maxWidth: 420)
    }

    private func spoken(_ row: QuickDrawRules.Row) -> String {
        let name = row.id == me ? "You" : row.name
        var text = "\(name), \(row.wins) of \(winsNeeded) rounds"
        if row.tapped { text += row.early ? ", jumped" : ", tapped" }
        return text
    }
}

/// This round's times as a race: fastest first, each with a bar as long
/// as the time (shorter is better), the winner's in gold.
struct QuickDrawTimes: View {
    let rows: [QuickDrawRules.Row]
    let me: String
    let winner: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(SR.divider) }
                line(row, place: index + 1)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
    }

    private func line(_ row: QuickDrawRules.Row, place: Int) -> some View {
        let won = row.id == winner
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                NearbyPlayPlaceDisc(place: row.ms == nil ? 0 : place)
                Text(row.id == me ? "You" : row.name)
                    .font(SR.Text.title())
                    .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                    .lineLimit(1)
                if won {
                    Image(systemName: "crown.fill")
                        .font(SR.Text.title(15))
                        .foregroundStyle(SR.warn)
                        .accessibilityLabel("Took the round")
                }
                Spacer(minLength: 8)
                Text(time(row))
                    .font(SR.Text.title(16))
                    .monospacedDigit()
                    .foregroundStyle(won ? SR.accent : SR.inkSecondary)
                    .lineLimit(1)
                Text("\(row.wins)")
                    .font(SR.Text.display(20))
                    .foregroundStyle(SR.ink)
                    .frame(minWidth: 26, alignment: .trailing)
                    .accessibilityLabel("\(row.wins) rounds")
            }
            if let ms = row.ms {
                GeometryReader { geo in
                    Capsule()
                        .fill(won ? SR.warn : SR.accent.opacity(0.55))
                        .frame(width: max(8, geo.size.width * CGFloat(min(1, Double(ms) / Double(slowest)))))
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 52)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var slowest: Int {
        max(1, rows.compactMap(\.ms).max() ?? 1)
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
